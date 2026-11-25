//
//  TabBarCollection.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

private final class TabBarCollectionLayout: UICollectionViewFlowLayout {
    private enum UX {
        static let separatorWidth: CGFloat = 2 / UIScreen.main.scale
        static let separatorHeight: CGFloat = 20
    }
    
    static let separatorKind = "TabBarSeparator"
    weak var tabBar: TabBar?
    private var insertedIndexPaths = Set<IndexPath>()
    
    func prepareForInsertion(at indexPaths: [IndexPath]) {
        insertedIndexPaths.formUnion(indexPaths)
    }
    
    override func initialLayoutAttributesForAppearingItem(
        at itemIndexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath) else {
            return nil
        }
        
        guard insertedIndexPaths.contains(itemIndexPath) else {
            return attributes
        }
        
        attributes.transform = CGAffineTransform(translationX: attributes.size.width, y: 0)
        return attributes
    }
    
    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedIndexPaths.removeAll()
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributes = super.layoutAttributesForElements(in: rect) ?? []
        guard let collectionView,
              let dataSourceTabCount = tabBar?.dataSource?.activeTabs.count else {
            return attributes
        }
        let tabCount = min(collectionView.numberOfItems(inSection: 0), dataSourceTabCount)
        guard tabCount > 1 else {
            return attributes
        }
        
        for index in 0..<(tabCount - 1) {
            guard showsSeparator(after: index),
                  let separatorAttributes = separatorAttributes(after: index, in: rect) else {
                continue
            }
            attributes.append(separatorAttributes)
        }
        return attributes
    }
    
    override func layoutAttributesForDecorationView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard elementKind == Self.separatorKind else {
            return super.layoutAttributesForDecorationView(ofKind: elementKind, at: indexPath)
        }
        
        guard showsSeparator(after: indexPath.item) else {
            return nil
        }
        return separatorAttributes(after: indexPath.item, in: nil)
    }
    
    private func showsSeparator(after index: Int) -> Bool {
        guard let collectionView,
              let tabBar,
              let dataSourceTabCount = tabBar.dataSource?.activeTabs.count else {
            return false
        }
        let tabCount = min(collectionView.numberOfItems(inSection: 0), dataSourceTabCount)
        guard tabCount > 1,
              index >= 0,
              index < tabCount - 1 else {
            return false
        }
        
        return !tabBar.isTabSelected(at: index) && !tabBar.isTabSelected(at: index + 1)
    }
    
    private func separatorAttributes(
        after index: Int,
        in rect: CGRect?
    ) -> UICollectionViewLayoutAttributes? {
        guard let leftAttributes = super.layoutAttributesForItem(at: IndexPath(item: index, section: 0)),
              let rightAttributes = super.layoutAttributesForItem(at: IndexPath(item: index + 1, section: 0)) else {
            return nil
        }
        
        let centerX = (leftAttributes.frame.maxX + rightAttributes.frame.minX) / 2
        let frame = CGRect(
            x: centerX - (UX.separatorWidth / 2),
            y: leftAttributes.frame.midY - (UX.separatorHeight / 2),
            width: UX.separatorWidth,
            height: UX.separatorHeight
        )
        if let rect,
           !rect.insetBy(dx: -UX.separatorWidth, dy: -UX.separatorHeight).intersects(frame) {
            return nil
        }
        
        let attributes = UICollectionViewLayoutAttributes(
            forDecorationViewOfKind: Self.separatorKind,
            with: IndexPath(item: index, section: 0)
        )
        attributes.frame = frame
        attributes.zIndex = 1
        return attributes
    }
    
}

final class TabBarCollection: UICollectionView {
    private weak var tabBar: TabBar?
    private let layout: TabBarCollectionLayout
    private var lastLayoutWidth: CGFloat = 0
    private var isUpdatingTabs = false
    private var needsReload = false
    private var pendingInsertedIndices = Set<Int>()
    private var pendingDeletedIndices = Set<Int>()
    
    /// Reports whether the strip can still be scrolled towards each edge, so
    /// the tab bar can show or hide its soft edge hints.
    var scrollStateDidChange: ((_ canScrollLeft: Bool, _ canScrollRight: Bool) -> Void)?
    private(set) var dragSourceIndex: Int?
    private(set) var dragDestinationIndex: Int?
    /// Set once the drag has lifted, so reloaded cells keep the slot empty.
    private var isShowingDragPlaceholder = false
    
    init() {
        let layout = TabBarCollectionLayout()
        self.layout = layout
        super.init(frame: .zero, collectionViewLayout: layout)
        configureAppearance()
        configureLayout(layout)
        configureCollection()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        let widthChanged = abs(lastLayoutWidth - bounds.width) > 0.5
        super.layoutSubviews()
        guard widthChanged else {
            return
        }
        lastLayoutWidth = bounds.width
        guard !isUpdatingTabs else {
            return
        }
        updateScrollability()
        refreshVisibleTabs()
        revealSelectedTab()
    }
    
    // MARK: - Configuration
    
    func attach(to tabBar: TabBar) {
        self.tabBar = tabBar
        layout.tabBar = tabBar
        layout.invalidateLayout()
    }
    
    // MARK: - Updates
    
    func reloadTabs() {
        guard !isUpdatingTabs else {
            needsReload = true
            refreshVisibleTabs()
            return
        }
        
        reloadData()
        updateLayout()
        refreshVisibleTabs()
    }
    
    func updateTabs(inserting insertedIndices: [Int] = [], deleting deletedIndices: [Int] = []) {
        guard !isUpdatingTabs else {
            pendingInsertedIndices.formUnion(insertedIndices)
            pendingDeletedIndices.formUnion(deletedIndices)
            return
        }
        
        let currentCount = numberOfItems(inSection: 0)
        let hasSingleChangeType = insertedIndices.isEmpty != deletedIndices.isEmpty
        guard let tabBar,
              hasSingleChangeType,
              let tabCount = tabBar.dataSource?.activeTabs.count,
              currentCount + insertedIndices.count - deletedIndices.count == tabCount,
              insertedIndices.allSatisfy((0..<tabCount).contains),
              deletedIndices.allSatisfy((0..<currentCount).contains) else {
            reloadTabs()
            return
        }
        
        let insertedIndexPaths = insertedIndices.map { IndexPath(item: $0, section: 0) }
        let deletedIndexPaths = deletedIndices.map { IndexPath(item: $0, section: 0) }
        let shouldRevealRightmostTab = insertedIndices.contains(tabCount - 1)
        layout.prepareForInsertion(at: insertedIndexPaths)
        updateLayout()
        isUpdatingTabs = true
        performBatchUpdates({
            if !deletedIndexPaths.isEmpty {
                deleteItems(at: deletedIndexPaths)
            }
            if !insertedIndexPaths.isEmpty {
                insertItems(at: insertedIndexPaths)
            }
        }, completion: { [weak self] _ in
            guard let self else {
                return
            }
            
            self.finishTabUpdate()
        })
        
        if shouldRevealRightmostTab {
            updateScrollability()
            layoutIfNeeded()
            scrollToItem(
                at: IndexPath(item: tabCount - 1, section: 0),
                at: .right,
                animated: true
            )
        }
    }
    
    func reloadTab(at index: Int) {
        let indexPath = IndexPath(item: index, section: 0)
        guard let tabBarCell = cellForItem(at: indexPath) as? TabBarCell else {
            return
        }
        configure(tabBarCell, at: indexPath)
    }
    
    func invalidateLayout() {
        collectionViewLayout.invalidateLayout()
    }
    
    func updateLayout() {
        updateScrollability()
        collectionViewLayout.invalidateLayout()
        layoutIfNeeded()
        revealSelectedTab()
    }
    
    private func finishTabUpdate() {
        isUpdatingTabs = false
        updateLayout()
        refreshVisibleTabs()
        
        let insertedIndices = pendingInsertedIndices.sorted()
        let deletedIndices = pendingDeletedIndices.sorted()
        let reloadPending = needsReload
        pendingInsertedIndices.removeAll()
        pendingDeletedIndices.removeAll()
        needsReload = false
        
        let hasSingleChangeType = insertedIndices.isEmpty != deletedIndices.isEmpty
        if hasSingleChangeType {
            needsReload = reloadPending
            updateTabs(inserting: insertedIndices, deleting: deletedIndices)
        } else if reloadPending || !insertedIndices.isEmpty || !deletedIndices.isEmpty {
            reloadTabs()
        }
    }
    
    private func updateScrollability() {
        // Edge UI: tabs stop shrinking at their minimum width and the strip
        // scrolls instead, so the trailing "+" never rides with the content.
        let contentWidth = collectionViewLayout.collectionViewContentSize.width
        let canScroll = contentWidth > bounds.width + 0.5
        isScrollEnabled = canScroll
        if !canScroll && contentOffset.x != 0 {
            contentOffset = CGPoint(x: 0, y: contentOffset.y)
        }
        notifyScrollState()
    }
    
    private func notifyScrollState() {
        guard let scrollStateDidChange else {
            return
        }
        
        let contentWidth = collectionViewLayout.collectionViewContentSize.width
        let canScroll = contentWidth > bounds.width + 0.5
        let canScrollLeft = canScroll && contentOffset.x > 0.5
        let canScrollRight = canScroll && contentOffset.x + bounds.width < contentWidth - 0.5
        scrollStateDidChange(canScrollLeft, canScrollRight)
    }
    
    private func refreshVisibleTabs() {
        for case let tabBarCell as TabBarCell in visibleCells {
            guard let indexPath = indexPath(for: tabBarCell) else {
                continue
            }
            configure(tabBarCell, at: indexPath)
        }
    }
    
    private func revealSelectedTab() {
        guard isScrollEnabled,
              let tabBar,
              let tabs = tabBar.dataSource?.activeTabs,
              let selectedIndex = tabs.indices.first(where: tabBar.isTabSelected(at:)),
              selectedIndex < numberOfItems(inSection: 0),
              let attributes = layoutAttributesForItem(
                at: IndexPath(item: selectedIndex, section: 0)
              ) else {
            return
        }
        
        scrollRectToVisible(attributes.frame, animated: false)
    }
    
    private func configure(_ tabBarCell: TabBarCell, at indexPath: IndexPath) {
        guard let tabBar,
              let tabs = tabBar.dataSource?.activeTabs,
              tabs.indices.contains(indexPath.item) else {
            return
        }
        
        let tab = tabs[indexPath.item]
        let cellLayout = tabBar.cellLayout(at: indexPath.item)
        tabBarCell.configure(
            tab: tab,
            isSelected: tabBar.isTabSelected(at: indexPath.item),
            layoutMode: cellLayout.mode,
            cellWidth: cellLayout.width
        )
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        contentInset = .zero
        contentInsetAdjustmentBehavior = .never
    }
    
    private func configureLayout(_ layout: UICollectionViewFlowLayout) {
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
    }
    
    private func configureCollection() {
        dataSource = self
        delegate = self
        dragDelegate = self
        dropDelegate = self
        dragInteractionEnabled = true
        scrollsToTop = false
        register(TabBarCell.self, forCellWithReuseIdentifier: TabBarCell.reuseIdentifier)
        layout.register(
            TabBarSeparatorView.self,
            forDecorationViewOfKind: TabBarCollectionLayout.separatorKind
        )
    }
}

extension TabBarCollection: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabBar?.dataSource?.activeTabs.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let tabBarCell = dequeueReusableCell(
            withReuseIdentifier: TabBarCell.reuseIdentifier,
            for: indexPath
        ) as! TabBarCell
        
        guard let tabBar,
              let tabs = tabBar.dataSource?.activeTabs,
              tabs.indices.contains(indexPath.item) else {
            return tabBarCell
        }
        
        configure(tabBarCell, at: indexPath)
        tabBarCell.setDragPlaceholder(isShowingDragPlaceholder && indexPath.item == dragSourceIndex)
        tabBarCell.closeHandler = { [weak self, weak tabBarCell] in
            guard let self,
                  let tabBarCell,
                  let currentIndexPath = self.indexPath(for: tabBarCell) else {
                return
            }
            self.tabBar?.requestCloseTab(at: currentIndexPath.item)
        }
        return tabBarCell
    }
}

extension TabBarCollection: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        notifyScrollState()
    }
    
    // MARK: Context menu (same system interaction as the address bar)
    
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard dragSourceIndex == nil,
              let dataSource = tabBar?.dataSource,
              dataSource.activeTabs.indices.contains(indexPath.item) else {
            return nil
        }
        if let cell = cellForItem(at: indexPath) as? TabBarCell,
           cell.containsCloseButton(at: convert(point, to: cell)) {
            return nil
        }
        let index = indexPath.item
        let mode = dataSource.selectedTabMode
        let tabCount = dataSource.activeTabs.count
        return UIContextMenuConfiguration(identifier: NSNumber(value: index), previewProvider: nil) { [weak self] _ in
            self?.makeTabMenu(index: index, tabCount: tabCount, mode: mode)
        }
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        return tabPreview(for: configuration)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        return tabPreview(for: configuration)
    }
    
    /// Lifts the tab itself with rounded corners, like the address bar pill.
    private func tabPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let index = (configuration.identifier as? NSNumber)?.intValue,
              let cell = cellForItem(at: IndexPath(item: index, section: 0)) else {
            return nil
        }
        let parameters = UIPreviewParameters()
        let bounds = cell.bounds.insetBy(dx: 1, dy: 2)
        parameters.visiblePath = UIBezierPath(roundedRect: bounds, cornerRadius: min(10, bounds.height / 2))
        parameters.backgroundColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground
            : UIColor.systemBackground
        return UITargetedPreview(view: cell, parameters: parameters)
    }
    
    private func makeTabMenu(index: Int, tabCount: Int, mode: TabMode) -> UIMenu {
        let duplicate = UIAction(
            title: "复制标签页",
            image: UIImage(named: "reynard.document.on.document")
        ) { [weak self] _ in
            self?.tabBar?.dataSource?.duplicateTab(at: index, mode: mode)
        }
        
        var closeActions: [UIMenuElement] = []
        if tabCount > 1 {
            closeActions.append(UIAction(
                title: "关闭其他标签页",
                image: UIImage(named: "reynard.xmark"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.closeOtherTabs(keeping: index, mode: mode)
            })
        }
        if index > 0 {
            closeActions.append(UIAction(
                title: "关闭左侧标签页",
                image: UIImage(named: "reynard.xmark"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.closeTabs(before: index, mode: mode)
            })
        }
        if index < tabCount - 1 {
            closeActions.append(UIAction(
                title: "关闭右侧标签页",
                image: UIImage(named: "reynard.xmark"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.closeTabs(after: index, mode: mode)
            })
        }
        closeActions.append(UIAction(
            title: NSLocalizedString("Close This Tab", comment: ""),
            image: UIImage(named: "reynard.xmark"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.tabBar?.dataSource?.closeTab(at: index, mode: mode)
        })
        
        return UIMenu(title: "", children: [
            duplicate,
            UIMenu(title: "", options: .displayInline, children: closeActions),
        ])
    }
    
    private func closeTabs(after index: Int, mode: TabMode) {
        guard let count = tabBar?.dataSource?.activeTabs.count, index < count - 1 else {
            return
        }
        for position in stride(from: count - 1, to: index, by: -1) {
            tabBar?.dataSource?.closeTab(at: position, mode: mode)
        }
    }
    
    private func closeTabs(before index: Int, mode: TabMode) {
        guard index > 0 else {
            return
        }
        for position in stride(from: index - 1, through: 0, by: -1) {
            tabBar?.dataSource?.closeTab(at: position, mode: mode)
        }
    }
    
    private func closeOtherTabs(keeping index: Int, mode: TabMode) {
        guard let count = tabBar?.dataSource?.activeTabs.count, count > 1 else {
            return
        }
        for position in stride(from: count - 1, through: 0, by: -1) where position != index {
            tabBar?.dataSource?.closeTab(at: position, mode: mode)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        tabBar?.requestSelectTab(at: indexPath.item)
    }
}

extension TabBarCollection: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard let tabBar else {
            return .zero
        }
        
        let cellLayout = tabBar.cellLayout(at: indexPath.item)
        return CGSize(width: cellLayout.width, height: bounds.height)
    }
}

extension TabBarCollection: UICollectionViewDragDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let tabBarCell = cellForItem(at: indexPath) as? TabBarCell,
              !tabBarCell.containsCloseButton(at: session.location(in: tabBarCell)),
              let tab = tabBar?.dataSource?.activeTabs[safe: indexPath.item] else {
            return []
        }
        
        dragSourceIndex = indexPath.item
        dragDestinationIndex = indexPath.item
        clipsToBounds = false
        tabBar?.clipsToBounds = false
        return [UIDragItem(tab: tab)]
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        dragPreviewParametersForItemAt indexPath: IndexPath
    ) -> UIDragPreviewParameters? {
        guard let tabBarCell = cellForItem(at: indexPath) else {
            return nil
        }
        
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(
            roundedRect: tabBarCell.bounds.inset(by: TabBarCell.contentInsets),
            cornerRadius: TabBarCell.contentCornerRadius
        )
        return parameters
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        // Edge UI: the lift preview has been snapshotted by now; leave the
        // original slot empty (keeps its width, shows nothing) so only the
        // lifted copy is visible.
        guard let sourceIndex = dragSourceIndex else {
            return
        }
        isShowingDragPlaceholder = true
        (cellForItem(at: IndexPath(item: sourceIndex, section: 0)) as? TabBarCell)?.setDragPlaceholder(true)
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        isShowingDragPlaceholder = false
        for case let cell as TabBarCell in visibleCells {
            cell.setDragPlaceholder(false)
        }
        dragSourceIndex = nil
        dragDestinationIndex = nil
        clipsToBounds = true
        tabBar?.clipsToBounds = true
        updateLayout()
        refreshVisibleTabs()
    }
}

extension TabBarCollection: UICollectionViewDropDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        guard let tab = session.localDragSession?.items.first?.draggedTab,
              tab.mode == tabBar?.dataSource?.selectedTabMode else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        if dragSourceIndex != nil,
           let destinationIndex = destinationIndexPath?.item,
           destinationIndex != dragDestinationIndex {
            dragDestinationIndex = destinationIndex
            collectionViewLayout.invalidateLayout()
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
        guard dragSourceIndex != nil,
              dragDestinationIndex != dragSourceIndex else {
            return
        }
        
        dragDestinationIndex = dragSourceIndex
        collectionViewLayout.invalidateLayout()
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let tab = item.dragItem.draggedTab,
              let tabCount = tabBar?.dataSource?.activeTabs.count else {
            return
        }
        
        dragSourceIndex = nil
        dragDestinationIndex = nil
        
        guard let sourceIndexPath = item.sourceIndexPath else {
            tabBar?.requestMoveTab(tab, to: coordinator.destinationIndexPath?.item ?? tabCount)
            return
        }
        
        let destinationItem = min(coordinator.destinationIndexPath?.item ?? tabCount, tabCount - 1)
        let destinationIndexPath = IndexPath(item: destinationItem, section: 0)
        performBatchUpdates {
            tabBar?.requestMoveTab(from: sourceIndexPath.item, to: destinationItem)
            moveItem(at: sourceIndexPath, to: destinationIndexPath)
        }
        coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
    }
}
