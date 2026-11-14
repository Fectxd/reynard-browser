//
//  EdgeStartPageViewController.swift
//  Reynard
//
//  Edge-style paged start page shown for homepage tabs.
//  The address-bar overlay keeps upstream's HomepageRootViewController.
//

import UIKit

protocol EdgeStartPageViewControllerDelegate: AnyObject {
    func edgeStartPage(_ controller: EdgeStartPageViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition)
    func edgeStartPage(_ controller: EdgeStartPageViewController, didRequestShareURL url: URL, sourceView: UIView)
    func edgeStartPage(_ controller: EdgeStartPageViewController, didRequestHideFromSuggestions siteID: Int64)
    func edgeStartPage(_ controller: EdgeStartPageViewController, didSelectRecentlyClosedTab id: UUID)
    func edgeStartPageDidSelectFolder(_ folder: BookmarkFolderSnapshot)
    func edgeStartPageDidRequestAddressBarFocus(_ controller: EdgeStartPageViewController)
    func edgeStartPageDidStartScrolling()
}

final class HomepagePanelScrollView: UIScrollView {
    static let maximumContentWidth: CGFloat = 720
    static let topPadding: CGFloat = 4
    
    let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        alwaysBounceVertical = false
        bounces = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        addSubview(stackView)
        // Every page starts at the same top offset (so Favorites, Frequently
        // Visited and Recently Closed line up), follows the page width so
        // narrow windows reflow, and is capped on very wide screens.
        // 999, not .defaultHigh (750): at 750 the page width tied with the
        // labels' compression resistance, so a long single-line title could
        // widen the whole page past the window and push everything off-screen.
        let fillWidth = stackView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor)
        fillWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            contentLayoutGuide.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            stackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: Self.topPadding),
            stackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            stackView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumContentWidth),
            stackView.widthAnchor.constraint(lessThanOrEqualTo: frameLayoutGuide.widthAnchor),
            fillWidth,
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Adaptive side margins: tight in narrow windows (iPhone portrait,
        // Split View / Slide Over), roomier once there is space to spare.
        let horizontal: CGFloat = bounds.width < 500 ? 16 : 28
        if stackView.directionalLayoutMargins.leading != horizontal {
            stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: horizontal, bottom: 0, trailing: horizontal)
        }
    }
    
    func removeAllPanelContent() {
        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }
}

final class EdgeStartPageViewController: UIViewController, HomepageRootContent {
    private enum UX {
        static let horizontalInset: CGFloat = 16
        static let maximumContentWidth: CGFloat = 800
        static let headerTopInset: CGFloat = 8
        static let headerSpacing: CGFloat = 10
        static let bottomInset: CGFloat = 14
        static let embeddedTopReserve: CGFloat = 4
        static let detachedTopReserve: CGFloat = 4
        static let panelOverflowTolerance: CGFloat = 4
        static let weatherRefreshInterval: TimeInterval = 60
    }
    
    weak var delegate: EdgeStartPageViewControllerDelegate?
    
    private let bookmarkStore: BookmarkStore
    private let folder: BookmarkFolderSnapshot?
    private let sections: [HomepageSection]
    private var isPrivateBrowsing: Bool
    private var contentMode: HomepageContentMode = .embeddedNarrow
    /// Mode handed to the sections. Derived from the real page width so a
    /// narrow window (Split View, portrait) gets the narrow layout even on iPad.
    private var sectionContentMode: HomepageContentMode = .embeddedNarrow
    private var visibleContentInsets: UIEdgeInsets = .zero
    private var sectionViewControllers: [HomepageSection: UIViewController] = [:]
    private var panelScrollViews: [HomepagePanelScrollView] = []
    private var panelTitles: [String] = []
    private var currentPageIndex = 0
    private var weatherSnapshot: HomepageWeatherSnapshot?
    private var weatherLoadDate = Date.distantPast
    private var hasRequestedFeed = false
    /// Pager size of the last layout pass; when the window is resized the
    /// pager is snapped back onto the current page and every section re-lays out.
    private var lastPagerSize: CGSize = .zero
    private var isResizing = false
    private var lastSettledPageIndex = 0
    private var lastDisappearDate: Date?
    private weak var weatherDetailViewController: HomepageWeatherDetailViewController?
    
    private let wallpaperImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private let topBarView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        return stackView
    }()
    
    private let headerContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let headerStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = UX.headerSpacing
        return stackView
    }()
    
    private lazy var weatherChipView: HomepageWeatherChipView = {
        let chip = HomepageWeatherChipView(frame: .zero)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleWeatherChipTap))
        tap.cancelsTouchesInView = false
        chip.addGestureRecognizer(tap)
        return chip
    }()
    
    private let headerSpacerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var settingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = EdgeHomepagePalette.secondaryText
        button.setImage(UIImage(
            systemName: "gearshape",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        ), for: .normal)
        button.addTarget(self, action: #selector(handleSettingsTap), for: .touchUpInside)
        return button
    }()
    
    private lazy var searchFieldView: HomepageSearchFieldView = {
        let field = HomepageSearchFieldView(frame: .zero)
        field.addTarget(self, action: #selector(handleSearchFieldTap), for: .touchUpInside)
        return field
    }()
    
    private let pagerScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .none
        return scrollView
    }()
    
    private let pagesStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 0
        return stackView
    }()
    
    private lazy var panelRailView: HomepagePanelRailView = {
        let view = HomepagePanelRailView(frame: .zero)
        view.onSelectPage = { [weak self] index, animated in
            self?.scrollToPage(index, animated: animated)
        }
        return view
    }()
    
    private lazy var hintView: HomepagePanelHintView = {
        let view = HomepagePanelHintView(frame: .zero)
        return view
    }()
    
    private var headerTopConstraint: NSLayoutConstraint?
    private var pagesWidthConstraint: NSLayoutConstraint?
    private var hintBottomConstraint: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    
    init(
        bookmarkStore: BookmarkStore,
        folder: BookmarkFolderSnapshot? = nil,
        sections: [HomepageSection] = HomepageSection.allCases,
        isPrivateBrowsing: Bool = false
    ) {
        self.bookmarkStore = bookmarkStore
        self.folder = folder
        self.sections = sections
        self.isPrivateBrowsing = isPrivateBrowsing
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = folder?.title
        observeHomepageSettings()
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        headerContainerView.isHidden = folder != nil
        topBarView.isHidden = folder != nil
        pagerScrollView.delegate = self
        updateSectionContentMode()
        rebuildPanels()
        reloadWeather(force: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadWeather(force: true)
        // Opening the start page (new tab, switching back to it) starts on the
        // first page (Favorites). Resizing the window can briefly hide and
        // re-show this view; that must keep the current page, so only reset
        // when it was really gone for a moment.
        let wasAwayLongEnough = lastDisappearDate.map { Date().timeIntervalSince($0) > 1.0 } ?? true
        if folder == nil, wasAwayLongEnough {
            resetToFirstPage()
        }
        showHintForCurrentPage()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lastDisappearDate = Date()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSectionContentMode()
        handlePagerResizeIfNeeded()
        updatePanelScrollability()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let pageIndex = currentPageIndex
        isResizing = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else {
                return
            }
            self.isResizing = false
            self.lastPagerSize = .zero
            self.currentPageIndex = pageIndex
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }
    
    /// iPad window resizes (Split View, Slide Over, Stage Manager, rotation)
    /// change the pager size without a page change. Keep the visible page
    /// aligned and make every section recompute its columns for the new width.
    private func handlePagerResizeIfNeeded() {
        let size = pagerScrollView.bounds.size
        guard size.width > 0, size.height > 0, size != lastPagerSize else {
            return
        }
        let widthChanged = abs(size.width - lastPagerSize.width) > 0.5
        lastPagerSize = size
        
        if widthChanged {
            for viewController in sectionViewControllers.values {
                viewController.view.setNeedsLayout()
            }
            for panel in panelScrollViews {
                panel.setNeedsLayout()
                panel.stackView.setNeedsLayout()
            }
            pagesStackView.setNeedsLayout()
            pagesStackView.layoutIfNeeded()
        }
        
        guard !pagerScrollView.isDragging, !pagerScrollView.isDecelerating else {
            return
        }
        let index = min(max(currentPageIndex, 0), max(panelScrollViews.count - 1, 0))
        let target = CGPoint(x: 0, y: CGFloat(index) * size.height)
        if abs(pagerScrollView.contentOffset.y - target.y) > 0.5 {
            pagerScrollView.setContentOffset(target, animated: false)
        }
        if !isResizing {
            updateHintForOffset()
        }
    }
    
    private func resetToFirstPage() {
        guard isViewLoaded, !panelScrollViews.isEmpty else {
            return
        }
        pagerScrollView.setContentOffset(.zero, animated: false)
        currentPageIndex = 0
        for panel in panelScrollViews {
            panel.setContentOffset(.zero, animated: false)
        }
        frequentlyVisitedSectionViewController?.scrollToStart(animated: false)
        updateHintForOffset()
    }
    
    private func updateSectionContentMode() {
        // One breakpoint instead of continuous reflow: wide windows keep the
        // wide layout (6 favourites per row, 2 closed-tab columns) and the
        // tiles shrink with the width; below 560pt (Slide Over, 1/3 split,
        // narrow Stage Manager windows) switch once to the narrow layout
        // (4 per row, 1 column) so tiles never get too small for their text.
        let pageWidth = pagerScrollView.bounds.width > 0 ? pagerScrollView.bounds.width : view.bounds.width
        let mode: HomepageContentMode
        if traitCollection.userInterfaceIdiom == .pad, pageWidth == 0 || pageWidth >= 560 {
            mode = contentMode.isDetached ? .detachedWide : .embeddedWide
        } else {
            mode = contentMode.isDetached ? .detachedNarrow : .embeddedNarrow
        }
        guard mode != sectionContentMode else {
            return
        }
        sectionContentMode = mode
        recommendationViewControllers.forEach { $0.setContentMode(mode) }
        privateBrowsingSectionViewController?.setContentMode(mode)
        favoritesSectionViewController?.setContentMode(mode)
        frequentlyVisitedSectionViewController?.setContentMode(mode)
        recentlyClosedTabsSectionViewController?.setContentMode(mode)
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateInsets()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBackground()
    }
    
    // MARK: - Public API
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }
        
        self.contentMode = contentMode
        updateSectionContentMode()
        if isViewLoaded {
            updateBackground()
            updateInsets()
        }
    }
    
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }
        
        self.isPrivateBrowsing = isPrivateBrowsing
        guard isViewLoaded else {
            return
        }
        
        if folder == nil {
            rebuildPanels()
            return
        }
        
        recommendationViewControllers.forEach { viewController in
            viewController.setPrivateBrowsing(isPrivateBrowsing)
        }
        privateBrowsingSectionViewController?.setPrivateBrowsing(isPrivateBrowsing)
    }
    
    func setVisibleContentInsets(_ visibleContentInsets: UIEdgeInsets) {
        guard self.visibleContentInsets != visibleContentInsets else {
            return
        }
        
        self.visibleContentInsets = visibleContentInsets
        guard isViewLoaded else {
            return
        }
        updateInsets()
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        view.backgroundColor = EdgeHomepagePalette.background
        updateBackground()
    }
    
    private func configureHierarchy() {
        view.addSubview(wallpaperImageView)
        view.addSubview(pagerScrollView)
        pagerScrollView.addSubview(pagesStackView)
        view.addSubview(topBarView)
        view.addSubview(headerContainerView)
        headerContainerView.addSubview(headerStackView)
        view.addSubview(panelRailView)
        view.addSubview(hintView)
        
        // Weather sits in the top-left corner and settings in the top-right
        // corner of the page, independent of the centred search column.
        topBarView.addArrangedSubview(weatherChipView)
        topBarView.addArrangedSubview(headerSpacerView)
        topBarView.addArrangedSubview(settingsButton)
        headerSpacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        weatherChipView.setContentHuggingPriority(.required, for: .horizontal)
        weatherChipView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        weatherChipView.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        
        headerStackView.addArrangedSubview(searchFieldView)
        
        NSLayoutConstraint.activate([
            settingsButton.widthAnchor.constraint(equalToConstant: 30),
            settingsButton.heightAnchor.constraint(equalToConstant: 30),
        ])
        
    }
    
    private func configureConstraints() {
        let headerTop = topBarView.topAnchor.constraint(equalTo: view.topAnchor, constant: UX.headerTopInset)
        headerTopConstraint = headerTop
        
        let headerWidth = headerContainerView.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -UX.horizontalInset * 2
        )
        headerWidth.priority = .defaultHigh
        
        // See HomepagePanelScrollView: the pages must never be wider than the
        // pager, whatever their content wants.
        let pagesWidth = pagesStackView.widthAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.widthAnchor)
        pagesWidth.priority = UILayoutPriority(999)
        pagesWidthConstraint = pagesWidth
        
        let hintBottom = hintView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UX.bottomInset)
        hintBottomConstraint = hintBottom
        
        let pagerTop = pagerScrollView.topAnchor.constraint(
            equalTo: headerContainerView.bottomAnchor,
            constant: UX.headerSpacing
        )
        let folderPagerTop = pagerScrollView.topAnchor.constraint(equalTo: view.topAnchor)
        pagerTop.isActive = folder == nil
        folderPagerTop.isActive = folder != nil
        
        NSLayoutConstraint.activate([
            wallpaperImageView.topAnchor.constraint(equalTo: view.topAnchor),
            wallpaperImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wallpaperImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wallpaperImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            headerTop,
            topBarView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: UX.horizontalInset),
            topBarView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -UX.horizontalInset),
            topBarView.heightAnchor.constraint(equalToConstant: 36),
            
            headerContainerView.topAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: UX.headerSpacing),
            headerContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            headerContainerView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maximumContentWidth),
            headerWidth,
            
            headerStackView.topAnchor.constraint(equalTo: headerContainerView.topAnchor),
            headerStackView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            headerStackView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerStackView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            
            pagerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            pagesStackView.topAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.topAnchor),
            pagesStackView.bottomAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.bottomAnchor),
            pagesStackView.centerXAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.centerXAnchor),
            pagesStackView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maximumContentWidth),
            pagesStackView.widthAnchor.constraint(lessThanOrEqualTo: pagerScrollView.frameLayoutGuide.widthAnchor),
            pagesWidth,
            
            panelRailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            panelRailView.centerYAnchor.constraint(equalTo: pagerScrollView.centerYAnchor),
            
            hintView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintBottom,
        ])
    }
    
    // MARK: - Panels
    
    private func rebuildPanels() {
        if let feedViewController = feedPanelViewController {
            feedViewController.willMove(toParent: nil)
            feedViewController.view.removeFromSuperview()
            feedViewController.removeFromParent()
            feedPanelViewController = nil
        }
        
        let shouldReloadFeed = hasRequestedFeed
        hasRequestedFeed = false
        
        for view in pagesStackView.arrangedSubviews {
            pagesStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        panelScrollViews = []
        panelTitles = []
        currentPageIndex = 0
        lastSettledPageIndex = 0
        pagerScrollView.setContentOffset(.zero, animated: false)
        
        let panels = panelDefinitions()
        for definition in panels {
            let panel = HomepagePanelScrollView(frame: .zero)
            pagesStackView.addArrangedSubview(panel)
            panelScrollViews.append(panel)
            panelTitles.append(definition.title)
            
            NSLayoutConstraint.activate([
                panel.heightAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.heightAnchor),
            ])
            
            if definition.isFeed {
                let feedViewController = HomepageFeedPanelViewController()
                feedViewController.delegate = self
                addChild(feedViewController)
                feedViewController.view.translatesAutoresizingMaskIntoConstraints = false
                panel.stackView.addArrangedSubview(feedViewController.view)
                feedViewController.didMove(toParent: self)
                feedPanelViewController = feedViewController
                continue
            }
            
            for section in definition.sections {
                guard let viewController = sectionViewController(for: section) else {
                    continue
                }
                // Favorites has no built-in top spacing while Frequently
                // Visited / Recently Closed start ~16pt down; pad it so the
                // three page titles sit at the same height.
                if section == .favorites {
                    let spacer = UIView()
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    spacer.heightAnchor.constraint(equalToConstant: 16).isActive = true
                    panel.stackView.addArrangedSubview(spacer)
                }
                panel.stackView.addArrangedSubview(viewController.view)
            }
        }
        
        if shouldReloadFeed, let feedViewController = feedPanelViewController {
            hasRequestedFeed = true
            feedViewController.reload()
        }
        
        panelRailView.configure(pageCount: panelScrollViews.count)
        updateInsets()
        updateHintForOffset()
    }
    
    private struct PanelDefinition {
        let title: String
        let sections: [HomepageSection]
        let isFeed: Bool
    }
    
    private func panelDefinitions() -> [PanelDefinition] {
        if folder != nil {
            return [PanelDefinition(title: NSLocalizedString("Favorites", comment: ""), sections: sections, isFeed: false)]
        }
        
        var primarySections: [HomepageSection] = []
        var frequentlyVisitedSections: [HomepageSection] = []
        var recentlyClosedSections: [HomepageSection] = []
        
        for section in displayedSections {
            switch section {
            case .recommendation, .privateBrowsing, .favorites:
                primarySections.append(section)
            case .frequentlyVisited:
                frequentlyVisitedSections.append(section)
            case .recentlyClosedTabs:
                recentlyClosedSections.append(section)
            }
        }
        
        // Recommendation cards (update / donation / performance) are not a page
        // of their own: if Favorites is switched off they ride along on the
        // first remaining page instead of keeping an otherwise blank page.
        if !primarySections.contains(where: { $0 == .favorites || $0 == .privateBrowsing }) {
            let recommendations = primarySections
            primarySections = []
            if !frequentlyVisitedSections.isEmpty {
                frequentlyVisitedSections = recommendations + frequentlyVisitedSections
            } else if !recentlyClosedSections.isEmpty {
                recentlyClosedSections = recommendations + recentlyClosedSections
            }
        }
        
        var definitions: [PanelDefinition] = []
        // Only add pages that have something switched on; a section turned off
        // in Homepage settings removes its whole page from the pager.
        if !primarySections.isEmpty {
            definitions.append(PanelDefinition(
                title: NSLocalizedString("Favorites", comment: ""),
                sections: primarySections,
                isFeed: false
            ))
        }
        
        if !frequentlyVisitedSections.isEmpty {
            definitions.append(PanelDefinition(
                title: NSLocalizedString("Frequently Visited", comment: ""),
                sections: frequentlyVisitedSections,
                isFeed: false
            ))
        }
        
        if !recentlyClosedSections.isEmpty {
            definitions.append(PanelDefinition(
                title: NSLocalizedString("Recently Closed Tabs", comment: ""),
                sections: recentlyClosedSections,
                isFeed: false
            ))
        }
        
        if Prefs.HomepageSettings.showsFeed {
            definitions.append(PanelDefinition(
                title: NSLocalizedString("Feed", comment: "Homepage information panel title"),
                sections: [],
                isFeed: true
            ))
        }
        
        return definitions
    }
    
    private var feedPanelViewController: HomepageFeedPanelViewController?
    
    private func sectionViewController(for section: HomepageSection) -> UIViewController? {
        if let existing = sectionViewControllers[section] {
            return existing
        }
        
        let viewController = makeSectionViewController(for: section)
        addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        viewController.didMove(toParent: self)
        sectionViewControllers[section] = viewController
        return viewController
    }
    
    private func makeSectionViewController(for section: HomepageSection) -> UIViewController {
        switch section {
        case .recommendation(.performance):
            let viewController = PerformanceRecommendationViewController()
            viewController.delegate = self
            viewController.setContentMode(sectionContentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .recommendation(.updateAvailable):
            let viewController = UpdateAvailableViewController()
            viewController.delegate = self
            viewController.setContentMode(sectionContentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .recommendation(.donation):
            let viewController = DonationRecommendationViewController()
            viewController.delegate = self
            viewController.setContentMode(sectionContentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .privateBrowsing:
            let viewController = PrivateBrowsingSectionViewController()
            viewController.setContentMode(sectionContentMode)
            viewController.setPrivateBrowsing(isPrivateBrowsing)
            return viewController
            
        case .favorites:
            let viewController = FavoritesSectionViewController(
                bookmarkStore: bookmarkStore,
                folder: folder,
                showsSectionTitle: folder == nil
            )
            viewController.delegate = self
            viewController.setContentMode(sectionContentMode)
            if folder == nil {
                viewController.showsAddTile = true
                // The grid block is centred on the page (the page itself is
                // centred); the tiles inside it start from the left.
                viewController.centersRows = false
                viewController.showsAllFavorites = true
                viewController.onAddFavorite = { [weak self] in
                    self?.presentAddFavorite()
                }
            }
            return viewController
            
        case .frequentlyVisited:
            let viewController = FrequentlyVisitedSectionViewController()
            viewController.delegate = self
            viewController.scalesCardsToWidth = true
            viewController.setContentMode(sectionContentMode)
            return viewController
            
        case .recentlyClosedTabs:
            let viewController = RecentlyClosedTabsSectionViewController()
            viewController.delegate = self
            viewController.setContentMode(sectionContentMode)
            return viewController
        }
    }
    
    // MARK: - Layout
    
    private func updateBackground() {
        let showsWallpaper = folder == nil
        && Prefs.HomepageSettings.showsWallpaper
        && !contentMode.isDetached
        && HomepageWallpaper.image != nil
        
        if showsWallpaper {
            wallpaperImageView.image = HomepageWallpaper.image
            wallpaperImageView.isHidden = false
            view.backgroundColor = .clear
        } else {
            wallpaperImageView.image = nil
            wallpaperImageView.isHidden = true
            view.backgroundColor = EdgeHomepagePalette.background
        }
    }
    
    private func updateInsets() {
        let topReserve = contentMode.isDetached ? UX.detachedTopReserve : UX.embeddedTopReserve
        headerTopConstraint?.constant = max(visibleContentInsets.top, 0) + topReserve + UX.headerTopInset
        hintBottomConstraint?.constant = -(visibleContentInsets.bottom + UX.bottomInset)
        
        for panel in panelScrollViews {
            panel.contentInset = UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: visibleContentInsets.bottom + UX.bottomInset,
                right: 0
            )
        }
    }
    
    private func updatePanelScrollability() {
        guard pagerScrollView.bounds.height > 0 else {
            return
        }
        
        for panel in panelScrollViews {
            let availableHeight = pagerScrollView.bounds.height
            let contentHeight = panel.contentSize.height - panel.contentInset.bottom
            panel.isScrollEnabled = contentHeight > availableHeight + UX.panelOverflowTolerance
        }
    }
    
    private func updateHintForOffset() {
        guard !panelTitles.isEmpty else {
            hintView.hide()
            return
        }
        
        let pageHeight = pagerScrollView.bounds.height
        guard pageHeight > 0 else {
            return
        }
        
        let progress = pagerScrollView.contentOffset.y / pageHeight
        panelRailView.update(progress: progress)
        currentPageIndex = min(max(Int(progress.rounded()), 0), panelTitles.count - 1)
        
        let index = currentPageIndex
        var hint: String?
        // Only point at the next page. The last page (e.g. the feed) shows
        // no hint: "swipe down for Recently Closed" there was misleading.
        if index + 1 < panelTitles.count {
            hint = String(
                format: NSLocalizedString("Swipe up for %@", comment: "Homepage panel swipe hint"),
                panelTitles[index + 1]
            )
        }
        
        if let hint = hint, panelTitles.count > 1 {
            hintView.show(hint)
        } else {
            hintView.hide()
        }
    }
    
    private func showHintForCurrentPage() {
        guard isViewLoaded, panelTitles.count > 1 else {
            return
        }
        
        updateHintForOffset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hintView.hide()
        }
    }
    
    // MARK: - Weather
    
    private func reloadWeather(force: Bool) {
        guard folder == nil else {
            return
        }
        
        if !force, Date().timeIntervalSince(weatherLoadDate) < UX.weatherRefreshInterval {
            return
        }
        
        if force, Date().timeIntervalSince(weatherLoadDate) < 5 {
            return
        }
        
        weatherLoadDate = Date()
        weatherChipView.setLoading(true)
        HomepageWeatherService.shared.load { [weak self] snapshot in
            guard let self = self else {
                return
            }
            
            self.weatherChipView.setLoading(false)
            guard let snapshot = snapshot else {
                return
            }
            
            self.weatherSnapshot = snapshot
            self.weatherChipView.update(with: snapshot)
            self.weatherDetailViewController?.update(with: snapshot)
        }
    }
    
    @objc private func handleWeatherChipTap() {
        let viewController = HomepageWeatherDetailViewController(snapshot: weatherSnapshot)
        viewController.onRequestRefresh = { [weak self] in
            guard let self = self else {
                return
            }
            self.reloadWeather(force: true)
        }
        weatherDetailViewController = viewController
        present(viewController, animated: true)
        
        if weatherSnapshot == nil {
            viewController.setRefreshing(true)
        }
        reloadWeather(force: true)
    }
    
    // MARK: - Actions
    
    @objc private func handleSearchFieldTap() {
        delegate?.edgeStartPageDidRequestAddressBarFocus(self)
    }
    
    private func presentAddFavorite() {
        let alert = UIAlertController(
            title: NSLocalizedString("Add to Favorites", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("Name", comment: "Add favorite name field")
            field.autocapitalizationType = .sentences
            field.returnKeyType = .next
        }
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("URL", comment: "Add favorite address field")
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Add", comment: "Homepage favorites add tile"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let fields = alert?.textFields,
                  let url = Self.favoriteURL(from: fields[1].text) else {
                return
            }
            let typedTitle = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = typedTitle.isEmpty ? (url.host ?? url.absoluteString) : typedTitle
            let favoritesGUID = self.bookmarkStore.favoritesFolderContents().parent.guid
            _ = self.bookmarkStore.addBookmark(title: title, url: url, to: favoritesGUID)
        })
        present(alert, animated: true)
    }
    
    private static func favoriteURL(from text: String?) -> URL? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.contains(" ") else {
            return nil
        }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
    
    @objc private func handleSettingsTap() {
        presentHomepageSettings()
    }
        
    private func presentHomepageSettings() {
        let viewController = HomepagePreferencesViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .popover
        navigationController.preferredContentSize = CGSize(width: 380, height: 560)
        
        if let popover = navigationController.popoverPresentationController {
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton.bounds
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = self
        }
        
        present(navigationController, animated: true)
    }
    
    // MARK: - Settings Observation
    
    private var displayedSections: [HomepageSection] {
        guard folder == nil else {
            return sections
        }
        
        return sections.filter { section in
            switch section {
            case .privateBrowsing:
                return isPrivateBrowsing
            case .favorites:
                return Prefs.HomepageSettings.showsFavorites &&
                (!isPrivateBrowsing || Prefs.HomepageSettings.showsFavoritesInPrivateBrowsing)
            case .frequentlyVisited:
                return Prefs.HomepageSettings.showsFrequentlyVisited &&
                (!isPrivateBrowsing || Prefs.HomepageSettings.showsFrequentlyVisitedInPrivateBrowsing)
            case .recentlyClosedTabs:
                return Prefs.HomepageSettings.showsRecentlyClosedTabs && !isPrivateBrowsing
            default:
                return true
            }
        }
    }
    
    private func observeHomepageSettings() {
        guard folder == nil else {
            return
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(homepageSettingsDidChange),
            name: .homepageSettingsDidChange,
            object: nil
        )
    }
    
    @objc private func homepageSettingsDidChange() {
        updateBackground()
        rebuildPanels()
    }
    
    // MARK: - Helpers
    
    private var recommendationViewControllers: [HomepageRecommendationViewController] {
        return sectionViewControllers.compactMap { section, viewController in
            guard case .recommendation = section else {
                return nil
            }
            
            return viewController as? HomepageRecommendationViewController
        }
    }
    
    private var privateBrowsingSectionViewController: PrivateBrowsingSectionViewController? {
        return sectionViewControllers[.privateBrowsing] as? PrivateBrowsingSectionViewController
    }
    
    private var favoritesSectionViewController: FavoritesSectionViewController? {
        return sectionViewControllers[.favorites] as? FavoritesSectionViewController
    }
    
    private var frequentlyVisitedSectionViewController: FrequentlyVisitedSectionViewController? {
        return sectionViewControllers[.frequentlyVisited] as? FrequentlyVisitedSectionViewController
    }
    
    private var recentlyClosedTabsSectionViewController: RecentlyClosedTabsSectionViewController? {
        return sectionViewControllers[.recentlyClosedTabs] as? RecentlyClosedTabsSectionViewController
    }
}

extension EdgeStartPageViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        return .none
    }
}

extension EdgeStartPageViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.edgeStartPageDidStartScrolling()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pagerScrollView else {
            return
        }
        // A window resize changes the page height before viewDidLayoutSubviews
        // re-aligns the pager; offsets seen in between would pick a wrong page.
        if isResizing || (lastPagerSize != .zero && scrollView.bounds.size != lastPagerSize) {
            return
        }
        updateHintForOffset()
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pagerScrollView else {
            return
        }
        finishPageChange()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pagerScrollView, !decelerate else {
            return
        }
        finishPageChange()
    }
    
    func scrollToPage(_ index: Int, animated: Bool) {
        guard panelScrollViews.indices.contains(index) else {
            return
        }
        let target = CGPoint(x: 0, y: CGFloat(index) * pagerScrollView.bounds.height)
        if index != currentPageIndex {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        pagerScrollView.setContentOffset(target, animated: animated)
        if !animated {
            finishPageChange()
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === pagerScrollView else {
            return
        }
        finishPageChange()
    }
    
    private func finishPageChange() {
        updateHintForOffset()
        if lastSettledPageIndex != currentPageIndex {
            // Leaving or entering a page puts Frequently Visited back at its
            // first (left-most) site.
            frequentlyVisitedSectionViewController?.scrollToStart(animated: false)
            lastSettledPageIndex = currentPageIndex
        }
        guard currentPageIndex == panelScrollViews.count - 1,
              let feedPanelViewController = feedPanelViewController,
              !hasRequestedFeed else {
            return
        }
        
        hasRequestedFeed = true
        feedPanelViewController.reload()
    }
}

extension EdgeStartPageViewController: HomepageFeedPanelViewControllerDelegate {
    func homepageFeedPanelViewController(_ controller: HomepageFeedPanelViewController, didSelect article: HomepageFeedArticle) {
        delegate?.edgeStartPage(self, didRequestOpenURL: article.url, disposition: .currentTab)
    }
}

extension EdgeStartPageViewController: HomepageSectionDelegate {
    func homepageSection(_ viewController: UIViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition) {
        delegate?.edgeStartPage(self, didRequestOpenURL: url, disposition: disposition)
    }
    
    func homepageSection(
        _ viewController: UIViewController,
        didRequestShareURL url: URL,
        sourceView: UIView
    ) {
        delegate?.edgeStartPage(self, didRequestShareURL: url, sourceView: sourceView)
    }
    
    func homepageSection(_ viewController: UIViewController, didRequestHideFromSuggestions siteID: Int64) {
        delegate?.edgeStartPage(self, didRequestHideFromSuggestions: siteID)
    }
    
    func homepageSection(_ viewController: UIViewController, didSelectRecentlyClosedTab id: UUID) {
        delegate?.edgeStartPage(self, didSelectRecentlyClosedTab: id)
    }
    
    func homepageSectionDidSelectSettings(_ viewController: UIViewController) {
        presentHomepageSettings()
    }
}

extension EdgeStartPageViewController: FavoritesSectionViewControllerDelegate {
    func favoritesSectionViewController(_ controller: FavoritesSectionViewController, didSelectFolder folder: BookmarkFolderSnapshot) {
        delegate?.edgeStartPageDidSelectFolder(folder)
    }
}
