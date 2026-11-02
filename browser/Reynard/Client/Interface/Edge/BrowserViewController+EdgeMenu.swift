//
//  BrowserViewController+EdgeMenu.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Presents the Edge-style overflow menu ("≡") and dispatches each menu item
//  to the building blocks that already exist in the app. Items without a real
//  implementation yet are left as icon placeholders inside the menu.
//

import GeckoView
import UIKit

extension BrowserViewController {

    /// Presents the Edge-style overflow menu from the "≡" (library) button.
    func presentEdgeMenu() {
        toolbarController.reset()
        browserChrome.dismissActionBar(animated: false)

        let menu = EdgeMenuViewController()
        menu.onSelect = { [weak self] item in
            guard let self else { return }
            // Placeholder items stay open (no action yet); everything else
            // dismisses the menu first, then runs the action.
            guard !item.isUnavailablePlaceholder else {
                return
            }
            self.dismiss(animated: true) {
                self.handleEdgeMenuItem(item)
            }
        }

        // Make the desktop/mobile website toggle label reflect the current mode.
        let isDesktop = tabManager.selectedTab.flatMap { tab in
            tab.url.flatMap { sessionManager.isDesktopMode(for: $0, tabID: tab.id) }
        } ?? false
        menu.titleOverride = { item in
            guard item == .requestDesktopWebsite else { return nil }
            return isDesktop ? "查看移动版网页" : "查看桌面网页"
        }
        menu.symbolOverride = { item in
            guard item == .requestDesktopWebsite else { return nil }
            return isDesktop ? "reynard.smartphone" : "reynard.desktopcomputer"
        }

        if browserLayout.interfaceIdiom == .pad {
            menu.modalPresentationStyle = .popover
            if let popover = menu.popoverPresentationController {
                popover.sourceView = browserChrome
                popover.sourceRect = browserChrome.menuButtonAnchorRect()
                popover.permittedArrowDirections = [.up, .down]
                popover.backgroundColor = .systemBackground
            }
            menu.preferredContentSize = CGSize(width: 375, height: 560)
        } else {
            menu.modalPresentationStyle = .pageSheet
            if #available(iOS 16.0, *), let sheet = menu.sheetPresentationController {
                // The menu always uses the tall 4-column grid now, so give the
                // sheet enough height (up to ~92% of screen) to show it without
                // forcing a scroll; grabber stays for pull-to-dismiss.
                sheet.detents = [.custom { _ in
                    let available = menu.view.window?.screen.bounds.height ?? UIScreen.main.bounds.height
                    let gridHeight = menu.preferredContentSize.height + 48
                    return min(available * 0.92, gridHeight)
                }]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 18
            }
        }
        present(menu, animated: true)
    }

    private func handleEdgeMenuItem(_ item: EdgeMenuViewController.Item) {
        switch item {
        case .favorites:
            presentEdgeLibraryPanel(section: .bookmarks)
        case .history:
            presentEdgeLibraryPanel(section: .history)
        case .downloads:
            presentEdgeLibraryPanel(section: .downloads)
        case .settings:
            // Settings always opens as the modal (portrait) settings screen,
            // in both portrait and landscape — reused as-is.
            presentEdgeSettings()
        case .home:
            openHomepage()
        case .newInPrivateTab:
            createNewTab(mode: .private)
        case .addToFavorites:
            presentBookmarkEditor(addToFavorites: true)
        case .requestDesktopWebsite:
            _ = tabManager.changeWebsiteModeForSelectedTab()
            refreshAddressBar()
        case .appearance:
            presentAppearancePopup()
        case .clearData:
            presentClearBrowsingData()
        case .shareExtension:
            presentExtensions()
        case .share:
            presentShareCurrentPage()
        case .translate:
            presentPageTranslation()
        case .addToPhone:
            presentQRCodeShare()
        case .exitBrowser:
            exitBrowserToBackground()
        case .findInPage:
            presentFindInPage()
        case .fontSize:
            presentPerSitePageZoom()
        case .sendToDevice, .downloadPage:
            // Removed from the displayed menu; kept in the enum for exhaustive
            // switch coverage, and no-ops if ever selected.
            break
        }
    }

    /// Dismisses the Edge overflow menu when the device layout changes
    /// (portrait <-> landscape), like Edge. The Settings modal is intentionally
    /// left open, matching the "except 设置" behaviour.
    func dismissEdgeMenuOnLayoutChange() {
        guard let presented = presentedViewController else {
            return
        }
        if presented is EdgeMenuViewController {
            dismiss(animated: true)
        }
    }

    // MARK: - Individual Actions

    /// Settings always opens as the modal (portrait) settings screen in both
    /// orientations, reusing the same settings UI as portrait.
    func presentEdgeSettings() {
        let settingsController = SettingsViewController()
        presentContentModal(settingsController)
    }

    /// "深色/浅色模式" — presents an Edge-style popup (deep/light/system),
    /// shown the same way as the Font size window.
    private func presentAppearancePopup() {
        let controller = EdgeAppearanceViewController(
            current: Prefs.AppearanceSettings.appAppearance
        )
        controller.onSelect = { [weak self] appearance in
            Prefs.AppearanceSettings.appAppearance = appearance
            AppAppearanceController.apply(appearance)
        }
        presentEdgePopup(controller)
    }

    private func openHomepage() {
        createNewTab(mode: .regular)
    }

    private func presentClearBrowsingData() {
        let controller = ClearBrowsingDataViewController()
        controller.title = NSLocalizedString("删除数据", comment: "Edge menu")
        presentContentModal(controller)
    }

    private func presentExtensions() {
        let controller = AddonsPreferencesViewController()
        controller.title = "拓展"
        presentContentModal(controller)
    }

    /// Shares the current page (reuses the standard share sheet).
    private func presentShareCurrentPage() {
        guard let tab = tabManager.selectedTab,
              let url = tabManager.shareableURL(for: tab) else {
            return
        }
        let sourceView = browserChrome.sharePopoverSourceView()
        presentShareSheet(
            items: [url],
            sourceView: sourceView,
            sourceRect: sourceView.bounds
        )
    }

    /// Translates the current page, in the spirit of Firefox Android's built-in
    /// translate action. We open the page through the (key-free) Google
    /// Translate page-proxy so the user gets a translated copy of the current
    /// URL in a new tab. A language chooser mirrors the Android target-language
    /// picker.
    private func presentPageTranslation() {
        guard let tab = tabManager.selectedTab,
              let urlString = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            return
        }

        let sheet = UIAlertController(
            title: "翻译",
            message: "选择目标语言，在新标签页中打开当前页面的翻译。",
            preferredStyle: .actionSheet
        )
        let languages: [(String, String)] = [
            ("简体中文", "zh-CN"),
            ("English", "en"),
            ("日本語", "ja"),
            ("한국어", "ko"),
            ("Français", "fr"),
            ("Deutsch", "de"),
            ("Español", "es"),
            ("Русский", "ru"),
        ]
        for (name, code) in languages {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                self?.openTranslatedPage(url, to: code)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = browserChrome
            popover.sourceRect = browserChrome.menuButtonAnchorRect()
            popover.permittedArrowDirections = [.up, .down]
        }
        present(sheet, animated: true)
    }

    private func openTranslatedPage(_ url: URL, to targetLanguage: String) {
        let query = [
            "sl=auto",
            "tl=\(targetLanguage)",
            "u=\(url.absoluteString)",
        ].joined(separator: "&")
        guard let translateURL = URL(string: "https://translate.google.com/translate?\(query)") else {
            return
        }
        _ = tabManager.createRegularTab(
            selecting: true,
            target: .end,
            url: translateURL.absoluteString,
            loadImmediately: true
        )
    }

    /// Presents a QR-code share for the current URL, with a field to paste your
    /// own text and generate a QR of that instead (Firefox Android's QR flow).
    private func presentQRCodeShare() {
        let urlString = tabManager.selectedTab.flatMap {
            $0.url?.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        let controller = EdgeQRCodeShareViewController(initialText: urlString)
        presentContentModal(controller)
    }

    /// "退出浏览器" — background the app, like pressing the Home button.
    /// Uses the same selector that the app's existing quit flow uses
    /// (UIApplication suspend), which references a real method so #selector
    /// compiles.
    private func exitBrowserToBackground() {
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
    }

    private func presentFindInPage() {
        guard tabManager.selectedTab != nil else {
            return
        }
        browserChrome.showActionBar(.findInPage(query: nil), animated: true)
    }

    /// Font size is exposed as per-site page zoom, backed by SiteSettingsStore
    /// so the level is remembered for the current host only.
    /// Presents the Edge-style Font size window for the current site. The zoom
    /// level is applied per host by `setSelectedPageZoomLevel`, which persists
    /// to SiteSettingsStore and updates the live session.
    private func presentPerSitePageZoom() {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }

        let controller = EdgeFontSizeViewController(
            level: selectedTab.session.settings.pageZoom.level
        )
        controller.onApply = { [weak self] level in
            self?.setSelectedPageZoomLevel(level)
        }

        presentEdgePopup(controller)
    }

    /// Presents an Edge-style popup sheet, shared by the Font-size, Appearance,
    /// and other small windows. Pad → popover anchored to the menu button;
    /// phone → a compact pageSheet (detent sized to the content or maxHeight)
    /// with a grabber.
    private func presentEdgePopup(_ controller: UIViewController, maxHeight: CGFloat? = nil) {
        if browserLayout.interfaceIdiom == .pad {
            controller.modalPresentationStyle = .popover
            if let popover = controller.popoverPresentationController {
                popover.sourceView = browserChrome
                popover.sourceRect = browserChrome.menuButtonAnchorRect()
                popover.permittedArrowDirections = [.up, .down]
                popover.backgroundColor = .systemBackground
            }
        } else {
            controller.modalPresentationStyle = .pageSheet
            if #available(iOS 16.0, *), let sheet = controller.sheetPresentationController {
                // The sheet detent is measured from the screen bottom. A pageSheet
                // also reserves a grabber + top inset above the content, so add
                // clearance so the card is fully visible and not shrunken.
                let availableHeight = controller.view.window?.screen.bounds.height ?? UIScreen.main.bounds.height
                let detentHeight: CGFloat
                if let maxHeight {
                    detentHeight = maxHeight
                } else {
                    detentHeight = min(
                        controller.preferredContentSize.height + 48,
                        availableHeight * 0.62
                    )
                }
                sheet.detents = [.custom { _ in detentHeight }]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 18
            }
        }
        present(controller, animated: true)
    }
}
