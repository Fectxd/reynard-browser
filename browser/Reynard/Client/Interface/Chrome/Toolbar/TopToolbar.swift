//
//  TopToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import GeckoView
import UIKit

final class TopToolbar: UIView {
    private enum UX {
        static let topToolbarContentHeight: CGFloat = 54
        static let topToolbarButtonStackHeight: CGFloat = 30
        static let topToolbarStandardButtonStackWidth: CGFloat = 126
        static let topToolbarTrailingButtonWidth: CGFloat = 42
        static let topToolbarHorizontalInset: CGFloat = 12
        static let topToolbarButtonSpacing: CGFloat = 10
        // Edge UI: the right-hand cluster is slightly airier.
        static let topToolbarTrailingButtonSpacing: CGFloat = 14
        static let topToolbarAddressBarSpacing: CGFloat = 12
        static let topToolbarAddressBarVerticalSpacing: CGFloat = 8
        static let topToolbarAddressBarWidthLimit: CGFloat = 650
        static let backgroundViewHorizontalExtension: CGFloat = 16
        static let borderWidth: CGFloat = 0.5
    }
    
    enum LayoutState {
        case hidden
        case standard
        case compact
    }
    
    var onSidebar: (() -> Void)?
    var onItem: ((ToolbarItem) -> Void)?
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    private let backgroundView: UIVisualEffectView = {
        // Edge UI: a solid, opaque theme surface instead of a translucent
        // material, so the page can never show through the top chrome. The
        // UIVisualEffectView stays as the container (layout depends on it).
        let view = UIVisualEffectView(effect: nil)
        view.backgroundColor = EdgeChromePalette.surface
        view.contentView.backgroundColor = EdgeChromePalette.surface
        view.translatesAutoresizingMaskIntoConstraints = false
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
    private var itemButtons: [ToolbarItem: ToolbarButton] = [:]
    private var trailingItems: [ToolbarItem] = []
    private let buttonMenus = ToolbarButtonMenus()
    
    // Edge UI: only navigation on the left of the address bar. Everything
    // else -- downloads (while active), the page actions and the ⋯ menu as the
    // right-most button -- sits on the right (see arrangeTrailingButtons).
    private lazy var leadingButtons: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            sidebarButton,
            button(for: .back),
            button(for: .forward),
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = UX.topToolbarButtonSpacing
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var trailingButtons: UIStackView = {
        let stack = UIStackView()
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
    private var widthLimitedStandardAddressBarConstraints: [NSLayoutConstraint] = []
    
    private var layoutState: LayoutState = .hidden
    private var layoutInterfaceIdiom: UIUserInterfaceIdiom = .unspecified
    private var layoutSidebarButtonVisible = false
    private var isUsingStandardAddressBarWidthLimit = false
    
    // MARK: - Lifecycle
    
    init() {
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureObservers()
        arrangeTrailingButtons()
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
            widthLimitedStandardAddressBarConstraints = [
                addressBar.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
                addressBar.widthAnchor.constraint(equalToConstant: UX.topToolbarAddressBarWidthLimit),
                addressBar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingButtons.trailingAnchor, constant: UX.topToolbarAddressBarSpacing),
                addressBar.trailingAnchor.constraint(lessThanOrEqualTo: trailingButtons.leadingAnchor, constant: -UX.topToolbarAddressBarSpacing),
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
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints + compactAddressBarConstraints)
        isUsingStandardAddressBarWidthLimit = false
    }
    
    func sharePopoverSourceView() -> UIView {
        return button(for: .share)
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
                showsDownloads: showsLeadingDownloadButton
            )
            trailingWidthConstraint.constant = isCompact ? 0 : trailingWidth
            
            sidebarButton.isHidden = interfaceIdiom != .pad || !sidebarButtonVisible
            button(for: .library).isHidden = false
            button(for: .downloads).isHidden = isCompact || !showsDownloadButton
            
            NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints + compactAddressBarConstraints)
            isUsingStandardAddressBarWidthLimit = false
            if isCompact {
                NSLayoutConstraint.activate(compactAddressBarConstraints)
            } else {
                setStandardAddressBarWidthLimitEnabled(shouldLimitStandardAddressBarWidth)
            }
            layoutIfNeeded()
        }
    }
    
    func setContentAlpha(_ alpha: CGFloat) {
        contentView.alpha = alpha
    }
    
    // MARK: - Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        button(for: .back).isEnabled = canGoBack
        button(for: .forward).isEnabled = canGoForward
        button(for: .share).isEnabled = canShare
    }
    
    func updatePageActions(canUsePageTools: Bool, canShowReader: Bool, isBookmarked: Bool) {
        button(for: .findInPage).isEnabled = canUsePageTools
        button(for: .pageZoom).isEnabled = canUsePageTools
        button(for: .reader).isEnabled = canShowReader
        
        button(for: .addBookmark).isEnabled = canUsePageTools
        button(for: .addBookmark).setImage(
            isBookmarked ? UIImage(named: "reynard.bookmark.fill") : UIImage(named: "reynard.bookmark"),
            for: .normal
        )
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        button(for: .downloads).applyDownloadSummary(summary)
        updateButtonLayout()
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        button(for: .library).setImage(
            hasUpdate ? UIImage(named: "reynard.ellipsis.circle.badge") : UIImage(named: "reynard.ellipsis.circle"),
            for: .normal
        )
    }
    
    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [GeckoSessionHistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        buttonMenus.installNavigationMenus(
            on: button(for: .back),
            forwardButton: button(for: .forward),
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
            on: button(for: .newTab),
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        buttonMenus.installLibraryMenus(
            on: [sidebarButton, button(for: .library)],
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
            on: [button(for: .tabOverview)],
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
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
    
    /// Tab count on the tab-overview button (Edge UI badge).
    func setTabOverviewBadge(count: Int, isPrivate: Bool) {
        button(for: .tabOverview).setTabCount(count, isPrivate: isPrivate)
    }
    
    @objc private func itemTapped(_ sender: ToolbarButton) {
        guard case .item(let item) = sender.toolbarButtonType else {
            return
        }
        
        onItem?(item)
    }
    
    @objc private func toolbarItemsDidChange() {
        arrangeTrailingButtons()
        updateButtonLayout()
    }
    
    // MARK: - Buttons
    
    private func button(for item: ToolbarItem) -> ToolbarButton {
        if let button = itemButtons[item] {
            return button
        }
        
        let button = ToolbarButton(buttonType: .item(item), target: self, action: #selector(itemTapped(_:)))
        itemButtons[item] = button
        return button
    }
    
    private func arrangeTrailingButtons() {
        // Edge UI order: downloads (shown only while a download is active),
        // the chosen items, and the ⋯ menu always last (right-most).
        var items = ToolbarPlacement.topToolbar.items.filter { $0 != .downloads && $0 != .library && $0 != .back && $0 != .forward }
        items.insert(.downloads, at: 0)
        items.append(.library)
        trailingItems = items
        trailingButtons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        trailingItems.forEach { trailingButtons.addArrangedSubview(button(for: $0)) }
        button(for: .downloads).isHidden = !button(for: .downloads).isShowingDownloads
    }
    
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
        trailingWidthConstraint = trailingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        
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
    
    private func configureObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarItemsDidChange),
            name: .toolbarItemsDidChange,
            object: nil
        )
    }
    
    /// The download button only appears while a download is active.
    private var showsDownloadButton: Bool {
        return button(for: .downloads).isShowingDownloads
    }
    
    /// Downloads never sit on the left in the Edge layout.
    private var showsLeadingDownloadButton: Bool {
        return false
    }
    
    private var trailingWidth: CGFloat {
        // Visible right-hand buttons (downloads only while active), 30pt each,
        // with the trailing spacing between them.
        let visibleCount = trailingItems.filter { $0 != .downloads || showsDownloadButton }.count
        return (CGFloat(visibleCount) * UX.topToolbarButtonStackHeight)
        + (CGFloat(max(visibleCount - 1, 0)) * UX.topToolbarTrailingButtonSpacing)
    }
    
    private func leadingWidth(
        interfaceIdiom: UIUserInterfaceIdiom,
        sidebarButtonVisible: Bool,
        showsDownloads: Bool
    ) -> CGFloat {
        guard interfaceIdiom == .pad else { return UX.topToolbarStandardButtonStackWidth }
        // sidebar (when shown), back, forward.
        let visibleButtonCount = (sidebarButtonVisible ? 3 : 2)
        return (CGFloat(visibleButtonCount) * UX.topToolbarButtonStackHeight)
        + (CGFloat(max(visibleButtonCount - 1, 0)) * UX.topToolbarButtonSpacing)
    }
    
    private var shouldLimitStandardAddressBarWidth: Bool {
        // Edge UI: the wide address bar always stretches between the leading
        // and trailing buttons (no 650pt centred cap).
        return false
    }
    
    private var contentLayoutInsets: UIEdgeInsets {
        if #available(iOS 26.0, *) {
            return edgeInsets(for: .safeArea(cornerAdaptation: .horizontal))
        }
        
        return safeAreaInsets
    }
    
    private func updateStandardAddressBarLayout() {
        guard layoutState == .standard else {
            return
        }
        
        setStandardAddressBarWidthLimitEnabled(shouldLimitStandardAddressBarWidth)
    }
    
    private func setStandardAddressBarWidthLimitEnabled(_ isEnabled: Bool) {
        let activeConstraints = isEnabled ? widthLimitedStandardAddressBarConstraints : standardAddressBarConstraints
        guard activeConstraints.contains(where: { !$0.isActive }) || isUsingStandardAddressBarWidthLimit != isEnabled else {
            return
        }
        
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints)
        NSLayoutConstraint.activate(activeConstraints)
        isUsingStandardAddressBarWidthLimit = isEnabled
    }
    
    private func updateButtonLayout() {
        let isCompact = layoutState == .compact
        button(for: .downloads).isHidden = layoutState != .standard || !showsDownloadButton
        leadingWidthConstraint.constant = isCompact ? 0 : leadingWidth(
            interfaceIdiom: layoutInterfaceIdiom,
            sidebarButtonVisible: layoutSidebarButtonVisible,
            showsDownloads: showsLeadingDownloadButton
        )
        trailingWidthConstraint.constant = isCompact ? 0 : trailingWidth
        updateStandardAddressBarLayout()
        layoutIfNeeded()
    }
}
