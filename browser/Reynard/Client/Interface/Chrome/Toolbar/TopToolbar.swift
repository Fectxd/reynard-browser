//
//  TopToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TopToolbar: UIView {
    private enum UX {
        static let topToolbarContentHeight: CGFloat = 54
        static let topToolbarButtonStackHeight: CGFloat = 30
        static let topToolbarStandardButtonStackWidth: CGFloat = 126
        // Landscape / pad address-bar right side has 4 static buttons
        // (share, favorite, tab-overview, hamburger) plus the download button,
        // which only appears while a download is active. The width formula is
        // computed dynamically (see trailingWidth).
        static let trailingButtonStackWidth: CGFloat = (4 * 30) + (3 * 10)
        static let topToolbarHorizontalInset: CGFloat = 12
        static let topToolbarButtonSpacing: CGFloat = 10
        static let topToolbarTrailingButtonSpacing: CGFloat = 14
        static let topToolbarAddressBarSpacing: CGFloat = 12
        static let topToolbarAddressBarVerticalSpacing: CGFloat = 8
        static let backgroundViewHorizontalExtension: CGFloat = 16
        static let borderWidth: CGFloat = 0.5
    }
    
    enum LayoutState {
        case hidden
        case standard
        case compact
    }
    
    var onSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onShare: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onTabOverview: (() -> Void)?
    var onFavorite: (() -> Void)?
    var onMenu: (() -> Void)?
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    /// Solid, opaque theme surface for the address / function row. The Edge UI
    /// uses a flat theme colour instead of a translucent material so the web
    /// page can never show through the top chrome.
    private let backgroundView: UIVisualEffectView = {
        // Keep the UIVisualEffectView as the container (constraints/layout code
        // depend on it) but disable the effect so it renders as a plain surface.
        let view = UIVisualEffectView(effect: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = EdgeChromePalette.surface
        view.contentView.backgroundColor = EdgeChromePalette.surface
        return view
    }()
    
    private let backgroundBottomBorderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.separator.withAlphaComponent(0.2)
        return view
    }()
    
    private lazy var sidebarButton = ToolbarButton(
        buttonType: .sidebar,
        target: self,
        action: #selector(sidebarTapped)
    )
    private lazy var backButton = ToolbarButton(
        buttonType: .back,
        target: self,
        action: #selector(backTapped)
    )
    private lazy var forwardButton = ToolbarButton(
        buttonType: .forward,
        target: self,
        action: #selector(forwardTapped)
    )
    private lazy var libraryButton = ToolbarButton(
        buttonType: .library,
        target: self,
        action: #selector(libraryTapped)
    )
    private lazy var downloadButton = ToolbarButton(
        buttonType: .download,
        target: self,
        action: #selector(downloadsTapped)
    )
    private lazy var shareButton = ToolbarButton(
        buttonType: .share,
        target: self,
        action: #selector(shareTapped)
    )
    private lazy var newTabButton = ToolbarButton(
        buttonType: .newTab,
        target: self,
        action: #selector(newTabTapped)
    )
    private lazy var tabOverviewButton = ToolbarButton(
        buttonType: .tabOverview,
        target: self,
        action: #selector(tabOverviewTapped)
    )
    private lazy var favoriteButton = ToolbarButton(
        buttonType: .favorite,
        target: self,
        action: #selector(favoriteTapped)
    )
    private lazy var menuButton = ToolbarButton(
        buttonType: .library,
        target: self,
        action: #selector(menuTapped)
    )
    private let buttonMenus = ToolbarButtonMenus()
    
    private lazy var leadingButtons: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [sidebarButton, backButton, forwardButton, libraryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = UX.topToolbarButtonSpacing
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var trailingButtons: UIStackView = {
        // Landscape / pad address-bar right side: download (when active), share,
        // favorite, tab-overview, hamburger menu. Spacing is +1 vs the leading
        // side (11 instead of 10) for a slightly airier right cluster.
        downloadButton.isHidden = true
        let stack = UIStackView(arrangedSubviews: [downloadButton, shareButton, favoriteButton, tabOverviewButton, menuButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = UX.topToolbarTrailingButtonSpacing
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var contentLayoutGuide: UILayoutGuide = {
        if #available(iOS 26.0, *) {
            return layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
        }
        
        return safeAreaLayoutGuide
    }()
    
    private var compactAddressBarHorizontalInset: CGFloat {
        if #available(iOS 26.0, *) {
            return 0
        }
        
        return UX.topToolbarHorizontalInset
    }
    
    private var heightConstraint: NSLayoutConstraint!
    private var contentTopConstraint: NSLayoutConstraint!
    private var backgroundBottomConstraint: NSLayoutConstraint!
    private var leadingWidthConstraint: NSLayoutConstraint!
    private var trailingWidthConstraint: NSLayoutConstraint!
    private var standardAddressBarConstraints: [NSLayoutConstraint] = []
    private var compactAddressBarConstraints: [NSLayoutConstraint] = []
    
    private var layoutState: LayoutState = .hidden
    private var layoutInterfaceIdiom: UIUserInterfaceIdiom = .unspecified
    private var layoutSidebarButtonVisible = false
    
    // MARK: - Lifecycle
    
    init() {
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateStandardAddressBarLayout()
    }
    
    // MARK: - Layout
    
    func attachAddressBar(_ addressBar: AddressBar) {
        if addressBar.superview !== contentView {
            addressBar.removeFromSuperview()
            contentView.addSubview(addressBar)
        }
        if standardAddressBarConstraints.isEmpty {
            standardAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: leadingButtons.trailingAnchor, constant: UX.topToolbarAddressBarSpacing),
                addressBar.trailingAnchor.constraint(equalTo: trailingButtons.leadingAnchor, constant: -UX.topToolbarAddressBarSpacing),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
            compactAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(
                    equalTo: contentLayoutGuide.leadingAnchor,
                    constant: compactAddressBarHorizontalInset
                ),
                addressBar.trailingAnchor.constraint(
                    equalTo: contentLayoutGuide.trailingAnchor,
                    constant: -compactAddressBarHorizontalInset
                ),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
        }
    }
    
    func detachAddressBar() {
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + compactAddressBarConstraints)
    }
    
    func sharePopoverSourceView() -> UIView {
        return shareButton
    }
    
    func extendBackground(to bottomAnchor: NSLayoutYAxisAnchor) {
        backgroundBottomConstraint.isActive = false
        backgroundBottomConstraint = backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        backgroundBottomConstraint.isActive = true
    }
    
    func setBackgroundCollapseOffset(_ offset: CGFloat) {
        backgroundBottomConstraint.constant = -offset
    }
    
    func apply(
        state: LayoutState,
        topInset: CGFloat,
        interfaceIdiom: UIUserInterfaceIdiom,
        sidebarButtonVisible: Bool
    ) {
        layoutState = state
        layoutInterfaceIdiom = interfaceIdiom
        layoutSidebarButtonVisible = sidebarButtonVisible
        
        UIView.performWithoutAnimation {
            contentTopConstraint.constant = topInset
            heightConstraint.constant = topInset + UX.topToolbarContentHeight
            isHidden = state == .hidden
            guard state != .hidden else { return }
            
            let isCompact = state == .compact
            leadingButtons.isHidden = isCompact
            trailingButtons.isHidden = isCompact
            leadingWidthConstraint.constant = isCompact ? 0 : leadingWidth(
                interfaceIdiom: interfaceIdiom,
                sidebarButtonVisible: sidebarButtonVisible,
                showsDownloads: downloadButton.isShowingDownloads
            )
            trailingWidthConstraint.constant = isCompact ? 0 : trailingWidth(
                showsDownloads: downloadButton.isShowingDownloads
            )
            
            sidebarButton.isHidden = interfaceIdiom != .pad || !sidebarButtonVisible
            libraryButton.isHidden = interfaceIdiom == .pad
            downloadButton.isHidden = isCompact || !downloadButton.isShowingDownloads
            
            NSLayoutConstraint.deactivate(standardAddressBarConstraints + compactAddressBarConstraints)
            if isCompact {
                NSLayoutConstraint.activate(compactAddressBarConstraints)
            } else {
                // Wide (standard) layout: the address bar always stretches all
                // the way between the leading and trailing button groups (the
                // old 650pt center cap is gone), so the plain set is enough.
                NSLayoutConstraint.activate(standardAddressBarConstraints)
            }
            layoutIfNeeded()
        }
    }
    
    func setContentAlpha(_ alpha: CGFloat) {
        contentView.alpha = alpha
    }
    
    // MARK: - Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        shareButton.isEnabled = canShare
    }
    
    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        buttonMenus.installNavigationMenus(
            on: backButton,
            forwardButton: forwardButton,
            itemsProvider: itemsProvider,
            onSelect: onSelect,
            isReversed: false
        )
    }
    
    func configureRecentlyClosedTabsMenu(
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        buttonMenus.installRecentlyClosedTabsMenu(
            on: newTabButton,
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        buttonMenus.installLibraryMenus(
            on: [sidebarButton, libraryButton],
            onSelect: onSelect
        )
    }
    
    func configureTabOverviewMenus(
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        buttonMenus.installTabOverviewMenus(
            on: [tabOverviewButton],
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadButton.applyDownloadSummary(summary)
        updateDownloadButtonVisibility()
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        libraryButton.setImage(
            hasUpdate ? UIImage(named: "reynard.ellipsis.circle.badge") : UIImage(named: "reynard.ellipsis.circle"),
            for: .normal
        )
    }

    func setTabOverviewBadge(count: Int, isPrivate: Bool) {
        tabOverviewButton.setTabCount(count, isPrivate: isPrivate)
    }
    
    func syncSidebarButton(splitViewController: UISplitViewController?) {
        sidebarButton.setImage(splitViewController?.displayModeButtonItem.image ?? UIImage(named: "reynard.sidebar.left"), for: .normal)
        sidebarButton.accessibilityLabel = splitViewController?.displayModeButtonItem.accessibilityLabel
    }
    
    func sidebarButtonFrame(in view: UIView) -> CGRect {
        return sidebarButton.convert(sidebarButton.bounds, to: view)
    }
    
    func setSidebarButtonTransition(alpha: CGFloat, hidden: Bool) {
        sidebarButton.alpha = alpha
        sidebarButton.isHidden = hidden
    }
    
    // MARK: - Action Wiring
    
    @objc private func sidebarTapped() { onSidebar?() }
    @objc private func backTapped() { onBack?() }
    @objc private func forwardTapped() { onForward?() }
    @objc private func libraryTapped() { onLibrary?() }
    @objc private func downloadsTapped() { onDownloads?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func newTabTapped() { onNewTab?() }
    @objc private func tabOverviewTapped() { onTabOverview?() }
    @objc private func favoriteTapped() { onFavorite?() }
    @objc private func menuTapped() { onMenu?() }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addSubview(backgroundView)
        addSubview(backgroundBottomBorderView)
        addSubview(contentView)
        contentView.addSubview(leadingButtons)
        contentView.addSubview(trailingButtons)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight)
        contentTopConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
        backgroundBottomConstraint = backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        leadingWidthConstraint = leadingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        trailingWidthConstraint = trailingButtons.widthAnchor.constraint(equalToConstant: UX.trailingButtonStackWidth)
        
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -UX.backgroundViewHorizontalExtension),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: UX.backgroundViewHorizontalExtension),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundBottomConstraint,
            
            backgroundBottomBorderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            backgroundBottomBorderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            backgroundBottomBorderView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            backgroundBottomBorderView.heightAnchor.constraint(equalToConstant: UX.borderWidth),
            
            heightConstraint,
            contentTopConstraint,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight),
            
            leadingButtons.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: UX.topToolbarHorizontalInset),
            leadingButtons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leadingWidthConstraint,
            leadingButtons.heightAnchor.constraint(equalToConstant: UX.topToolbarButtonStackHeight),
            
            trailingButtons.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -UX.topToolbarHorizontalInset),
            trailingButtons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trailingWidthConstraint,
            trailingButtons.heightAnchor.constraint(equalToConstant: UX.topToolbarButtonStackHeight),
        ])
    }
    
    private func leadingWidth(
        interfaceIdiom: UIUserInterfaceIdiom,
        sidebarButtonVisible: Bool,
        showsDownloads: Bool
    ) -> CGFloat {
        guard interfaceIdiom == .pad else { return UX.topToolbarStandardButtonStackWidth }
        let visibleButtonCount = (sidebarButtonVisible ? 3 : 2) + (showsDownloads ? 1 : 0)
        return (CGFloat(visibleButtonCount) * UX.topToolbarButtonStackHeight)
        + (CGFloat(max(visibleButtonCount - 1, 0)) * UX.topToolbarButtonSpacing)
    }

    private func trailingWidth(showsDownloads: Bool) -> CGFloat {
        // Four static buttons (share, favorite, tab-overview, hamburger) plus
        // the download button when a download is active.
        let visibleButtonCount = 4 + (showsDownloads ? 1 : 0)
        return (CGFloat(visibleButtonCount) * UX.topToolbarButtonStackHeight)
        + (CGFloat(max(visibleButtonCount - 1, 0)) * UX.topToolbarTrailingButtonSpacing)
    }
    
    private func updateStandardAddressBarLayout() {
        // The wide address bar is always pinned between the two button groups;
        // re-assert those constraints (no width cap exists anymore).
        guard layoutState == .standard else {
            return
        }
        
        NSLayoutConstraint.activate(standardAddressBarConstraints)
    }
    
    private func updateDownloadButtonVisibility() {
        let isCompact = layoutState == .compact
        let showsDownloads = downloadButton.isShowingDownloads
        downloadButton.isHidden = layoutState != .standard || !showsDownloads
        leadingWidthConstraint.constant = isCompact ? 0 : leadingWidth(
            interfaceIdiom: layoutInterfaceIdiom,
            sidebarButtonVisible: layoutSidebarButtonVisible,
            showsDownloads: showsDownloads
        )
        trailingWidthConstraint.constant = isCompact ? 0 : trailingWidth(showsDownloads: showsDownloads)
        updateStandardAddressBarLayout()
        layoutIfNeeded()
    }
}
