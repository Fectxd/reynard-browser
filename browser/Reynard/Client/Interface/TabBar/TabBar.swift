//
//  TabBar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol TabBarDataSource: AnyObject {
    var tabs: [Tab] { get }
    var selectedTabID: UUID? { get }
    var selectedMode: TabMode { get }
    
    func selectTab(at index: Int, mode: TabMode)
    func closeTab(at index: Int, mode: TabMode)
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode)
}

final class TabBar: UIView {
    private enum UX {
        static let tabBarHeight: CGFloat = 36
        // No bottom padding: the active tab sits flush on the address-bar row.
        static let tabBarBottomPadding: CGFloat = 0
        // Trailing "+" (new tab) button that follows the last tab. The tab
        // cells give up this much room so the button never covers a cell.
        static let newTabButtonSideLength: CGFloat = 30
        static let newTabButtonTrailingInset: CGFloat = 6
        static let newTabButtonGap: CGFloat = 4
        // Thin rule between the last tab and the "+" button, matching the
        // separators the layout draws between tabs.
        static let newTabSeparatorWidth: CGFloat = 1
        static let newTabSeparatorHeight: CGFloat = 18
        static let newTabSeparatorGap: CGFloat = 6
        // Small gap before the first tab; it also gives the active tab's
        // bottom flare somewhere to curve into.
        static let tabCollectionLeadingInset: CGFloat = 8
        // Soft edge hint shown while the strip can still be scrolled.
        static let scrollFadeWidth: CGFloat = 22
    }
    
    enum Visibility: Equatable {
        case hidden
        case layoutReserved
        case visible
    }
    
    enum ReorderState: Equatable {
        case idle
        case pending
        case active
    }
    
    struct CellLayout {
        let width: CGFloat
        let mode: TabBarCell.LayoutMode
    }
    
    weak var dataSource: TabBarDataSource?

    /// Invoked when the trailing "+" new-tab button is tapped.
    var onNewTab: (() -> Void)?
    
    private(set) var visibility: Visibility = .hidden
    private(set) var reorderState: ReorderState = .idle
    private var pendingExpandedTabID: UUID?
    private var displayedTabIDs: [UUID]?
    
    var pendingExpandedTabIndex: Int? {
        guard let pendingExpandedTabID else {
            return nil
        }
        return dataSource?.tabs.firstIndex { $0.id == pendingExpandedTabID }
    }
    
    var standardHeight: CGFloat {
        return UX.tabBarHeight + UX.tabBarBottomPadding
    }
    
    private let tabCollection = TabBarCollection()
    private lazy var presentation = TabBarPresentation(tabBar: self)

    private lazy var newTabButton: ToolbarButton = {
        let button = ToolbarButton(
            buttonType: .newTab,
            target: self,
            action: #selector(newTabTapped)
        )
        button.isHidden = true
        return button
    }()
    
    private let leadingScrollFade = ScrollFadeView(mirrored: false)
    private let trailingScrollFade = ScrollFadeView(mirrored: true)
    
    private lazy var newTabSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }()
    
    private var heightConstraint: NSLayoutConstraint!
    private var tabCollectionWidthConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureTabCollection()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateTabCollectionWidth()
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self && tabCollection.transform.ty < 0 ? nil : hitView
    }
    
    // MARK: - Layout
    
    func setVisibility(_ visibility: Visibility, animated: Bool) {
        presentation.setVisibility(visibility, animated: animated)
    }
    
    func setCollapseOffset(_ offset: CGFloat) {
        alpha = 1 - offset / max(bounds.height, 1)
        tabCollection.transform = CGAffineTransform(translationX: 0, y: -offset)
    }
    
    func invalidateLayout() {
        tabCollection.invalidateLayout()
    }
    
    func updateLayout() {
        clearInvalidPendingExpansion()
        tabCollection.updateLayout()
    }
    
    func cellLayout(at index: Int) -> CellLayout {
        let tabs = dataSource?.tabs ?? []
        let layoutTabCount = max(1, tabs.count)
        let fixedTabWidth = TabBarCell.expandedMinimumWidth
        
        // Tabs keep a fixed length until they no longer fit, then shrink
        // proportionally -- but never below the width ten tabs would get. Past
        // that point the strip scrolls instead of squeezing the title out.
        let fitWidth = floor(tabAreaWidth / CGFloat(layoutTabCount))
        let tabWidth = max(minimumTabWidth, min(fixedTabWidth, fitWidth))
        if tabWidth <= TabBarCell.collapsedMinimumWidth {
            return CellLayout(width: max(0, tabWidth), mode: .faviconOnly)
        }
        return CellLayout(width: max(0, tabWidth), mode: .expanded)
    }
    
    /// Narrowest width a tab may shrink to: what the strip would hand to a tab
    /// if there were ten of them. Ten tabs is the last count that still fits.
    private var minimumTabWidth: CGFloat {
        let tenTabWidth = floor(tabAreaWidth / 10)
        return max(TabBarCell.collapsedMinimumWidth, min(TabBarCell.expandedMinimumWidth, tenTabWidth))
    }
    
    /// True once the tabs no longer fit at their minimum width; the collection
    /// then scrolls and the "+" stays pinned to the right edge.
    private var isScrollable: Bool {
        let tabCount = CGFloat(dataSource?.tabs.count ?? 0)
        guard tabCount > 0 else {
            return false
        }
        return tabCount * minimumTabWidth > tabAreaWidth + 0.5
    }
    
    // MARK: - Updates
    
    func reloadTabs() {
        clearInvalidPendingExpansion()
        let tabs = dataSource?.tabs ?? []
        let (insertedIndices, deletedIndices) = changedTabIndices(in: tabs)
        if !insertedIndices.isEmpty && deletedIndices.isEmpty {
            tabCollection.updateTabs(inserting: insertedIndices)
        } else if insertedIndices.isEmpty && !deletedIndices.isEmpty {
            tabCollection.updateTabs(deleting: deletedIndices)
        } else {
            tabCollection.reloadTabs()
        }
        displayedTabIDs = tabs.map { $0.id }
        updateTabCollectionWidth()
    }
    
    func reloadTab(at index: Int) {
        tabCollection.reloadTab(at: index)
    }
    
    func setPendingExpansion(at index: Int?) {
        pendingExpandedTabID = index.flatMap { dataSource?.tabs[safe: $0]?.id }
        if index != nil {
            tabCollection.reloadTabs()
        }
    }
    
    func isTabSelected(at index: Int) -> Bool {
        guard let tabs = dataSource?.tabs,
              tabs.indices.contains(index) else {
            return false
        }
        
        return isTabSelected(id: tabs[index].id)
    }
    
    func isTabSelected(id: UUID) -> Bool {
        guard let tabs = dataSource?.tabs else {
            return false
        }
        
        let selectedTabID = pendingExpandedTabID.flatMap { pendingTabID in
            tabs.first { $0.id == pendingTabID }?.id
        }
        ?? dataSource?.selectedTabID
        return id == selectedTabID
    }
    
    func setPresentationAlpha(_ alpha: CGFloat) {
        presentation.setAlpha(alpha)
    }
    
    private func changedTabIndices(in tabs: [Tab]) -> (inserted: [Int], deleted: [Int]) {
        guard let displayedTabIDs,
              !displayedTabIDs.isEmpty,
              displayedTabIDs.count != tabs.count else {
            return ([], [])
        }
        
        let currentTabIDs = tabs.map { $0.id }
        let displayedTabIDSet = Set(displayedTabIDs)
        let currentTabIDSet = Set(currentTabIDs)
        if displayedTabIDs.count < currentTabIDs.count {
            guard displayedTabIDSet.isSubset(of: currentTabIDSet) else {
                return ([], [])
            }
            return (currentTabIDs.indices.filter { !displayedTabIDSet.contains(currentTabIDs[$0]) }, [])
        }
        
        guard currentTabIDSet.isSubset(of: displayedTabIDSet) else {
            return ([], [])
        }
        return ([], displayedTabIDs.indices.filter { !currentTabIDSet.contains(displayedTabIDs[$0]) })
    }
    
    // MARK: - Collection Coordination
    
    func updateReorderState(_ state: ReorderState) {
        reorderState = state
    }
    
    func requestSelectTab(at index: Int) {
        guard let dataSource else {
            return
        }
        dataSource.selectTab(at: index, mode: dataSource.selectedMode)
    }
    
    func requestCloseTab(at index: Int) {
        pendingExpandedTabID = nil
        guard let dataSource else {
            return
        }
        dataSource.closeTab(at: index, mode: dataSource.selectedMode)
    }
    
    func requestMoveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard let dataSource else {
            return
        }
        dataSource.moveTab(from: sourceIndex, to: destinationIndex, mode: dataSource.selectedMode)
        displayedTabIDs = dataSource.tabs.map { $0.id }
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        // Flat strip surface matching the Edge reference (also used for the
        // status-bar band above, so the two read as one bar).
        backgroundColor = EdgeChromePalette.chrome
        clipsToBounds = true
        isHidden = true
    }
    
    private func configureHierarchy() {
        addSubview(tabCollection)
        addSubview(leadingScrollFade)
        addSubview(trailingScrollFade)
        addSubview(newTabSeparator)
        addSubview(newTabButton)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        tabCollectionWidthConstraint = tabCollection.widthAnchor.constraint(equalToConstant: 0)
        let tabCollectionHeightConstraint = tabCollection.heightAnchor.constraint(equalToConstant: UX.tabBarHeight)
        NSLayoutConstraint.activate([
            tabCollection.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UX.tabCollectionLeadingInset),
            tabCollection.topAnchor.constraint(equalTo: topAnchor),
            tabCollectionHeightConstraint,
            tabCollectionWidthConstraint,
            
            leadingScrollFade.leadingAnchor.constraint(equalTo: tabCollection.leadingAnchor),
            leadingScrollFade.topAnchor.constraint(equalTo: tabCollection.topAnchor),
            leadingScrollFade.bottomAnchor.constraint(equalTo: tabCollection.bottomAnchor),
            leadingScrollFade.widthAnchor.constraint(equalToConstant: UX.scrollFadeWidth),
            
            trailingScrollFade.trailingAnchor.constraint(equalTo: tabCollection.trailingAnchor),
            trailingScrollFade.topAnchor.constraint(equalTo: tabCollection.topAnchor),
            trailingScrollFade.bottomAnchor.constraint(equalTo: tabCollection.bottomAnchor),
            trailingScrollFade.widthAnchor.constraint(equalToConstant: UX.scrollFadeWidth),
            
            // A thin rule separates the last tab from the "+" button, exactly
            // like the rules the layout draws between adjacent tabs.
            newTabSeparator.leadingAnchor.constraint(equalTo: tabCollection.trailingAnchor, constant: UX.newTabSeparatorGap),
            newTabSeparator.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabSeparator.widthAnchor.constraint(equalToConstant: UX.newTabSeparatorWidth),
            newTabSeparator.heightAnchor.constraint(equalToConstant: UX.newTabSeparatorHeight),
            
            // The "+" sits immediately after that rule rather than being
            // pinned to the far edge, and only ever uses the reserved room.
            newTabButton.leadingAnchor.constraint(equalTo: newTabSeparator.trailingAnchor, constant: UX.newTabSeparatorGap),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: UX.newTabButtonSideLength),
            newTabButton.heightAnchor.constraint(equalToConstant: UX.newTabButtonSideLength),
            
            heightConstraint,
        ])
    }
    
    // MARK: - Strip Metrics
    
    /// Width available to tabs once the "+" button and its insets are removed.
    private var tabAreaWidth: CGFloat {
        let reserved = UX.tabCollectionLeadingInset
            + UX.newTabSeparatorGap * 2
            + UX.newTabSeparatorWidth
            + UX.newTabButtonSideLength
            + UX.newTabButtonTrailingInset
        return max(0, bounds.width - reserved)
    }
    
    /// The collection grows with the tab count (fixed-length tabs) and stops at
    /// the strip width, where the cells start shrinking instead.
    private func updateTabCollectionWidth() {
        guard let widthConstraint = tabCollectionWidthConstraint else {
            return
        }
        
        let tabCount = dataSource?.tabs.count ?? 0
        // In scroll mode the strip takes the whole available width so the "+"
        // parks on the right edge instead of trailing the content.
        let total = isScrollable
        ? tabAreaWidth
        : min(TabBarCell.expandedMinimumWidth * CGFloat(tabCount), tabAreaWidth)
        if abs(widthConstraint.constant - total) > 0.5 {
            widthConstraint.constant = total
        }
    }
    
    private func configureTabCollection() {
        tabCollection.attach(to: self)
        tabCollection.scrollStateDidChange = { [weak self] canScrollLeft, canScrollRight in
            self?.updateScrollFades(canScrollLeft: canScrollLeft, canScrollRight: canScrollRight)
        }
    }
    
    private func updateScrollFades(canScrollLeft: Bool, canScrollRight: Bool) {
        let color = EdgeChromePalette.chrome.resolvedColor(with: traitCollection)
        leadingScrollFade.applyColor(color)
        trailingScrollFade.applyColor(color)
        leadingScrollFade.isHidden = !canScrollLeft
        trailingScrollFade.isHidden = !canScrollRight
    }
    
    // MARK: - Layout State
    
    private func clearInvalidPendingExpansion() {
        guard pendingExpandedTabID != nil else {
            return
        }
        
        if pendingExpandedTabIndex == nil {
            pendingExpandedTabID = nil
        }
    }
    
    private func isExpandedTab(at index: Int, in tabs: [Tab]) -> Bool {
        guard let tab = displayedTab(at: index, in: tabs) else {
            return false
        }
        return isTabSelected(id: tab.id)
    }
    
    private func displayedTab(at index: Int, in tabs: [Tab]) -> Tab? {
        guard tabs.indices.contains(index) else {
            return nil
        }
        
        guard let sourceIndex = tabCollection.dragSourceIndex,
              let targetIndex = tabCollection.dragDestinationIndex,
              tabs.indices.contains(sourceIndex),
              tabs.indices.contains(targetIndex),
              sourceIndex != targetIndex else {
            return tabs[index]
        }
        
        var reorderedTabs = tabs
        let movedTab = reorderedTabs.remove(at: sourceIndex)
        reorderedTabs.insert(movedTab, at: targetIndex)
        return reorderedTabs[index]
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        
        updateScrollFades(
            canScrollLeft: !leadingScrollFade.isHidden,
            canScrollRight: !trailingScrollFade.isHidden
        )
    }
    
    // MARK: - Presentation Coordination
    
    func applyVisibility(_ visibility: Visibility) {
        self.visibility = visibility
        let isHidden = visibility == .hidden
        heightConstraint.constant = isHidden ? 0 : standardHeight
        // The "+" rides on the strip and is only interactive while the strip
        // is actually visible (layoutReserved keeps the space but hides it).
        newTabButton.isHidden = visibility != .visible
        newTabSeparator.isHidden = visibility != .visible
        if visibility != .visible {
            updateScrollFades(canScrollLeft: false, canScrollRight: false)
        }
        updateTabCollectionWidth()
    }
    
    // MARK: - Actions
    
    @objc private func newTabTapped() {
        onNewTab?()
    }
}

/// Soft edge hint that tells the user the tab strip can be scrolled further.
private final class ScrollFadeView: UIView {
    private let mirrored: Bool
    
    init(mirrored: Bool) {
        self.mirrored = mirrored
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        isHidden = true
        gradientLayer.startPoint = CGPoint(x: mirrored ? 1 : 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: mirrored ? 0 : 1, y: 0.5)
        gradientLayer.locations = [0, 1]
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }
    
    private var gradientLayer: CAGradientLayer {
        // swiftlint:disable:next force_cast
        layer as! CAGradientLayer
    }
    
    func applyColor(_ color: UIColor) {
        // Opaque at the outer edge, transparent towards the tabs.
        gradientLayer.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
    }
}
