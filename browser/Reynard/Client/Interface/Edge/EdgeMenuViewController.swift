//
//  EdgeMenuViewController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Edge-style overflow menu (the "≡" button). Behaves adaptively like the
//  rest of the app:
//     - wide / regular width  -> a grid of icon + label tiles (matrix)
//     - narrow / compact      -> a vertical list of icon + label rows
//
//  A thin horizontal divider separates the primary (top) group, whose icons
//  are tinted blue, from the secondary group below it.
//

import UIKit

final class EdgeMenuViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    /// The full set of menu items, in display order.
    enum Item: Int, CaseIterable {
        // Primary group (above the line, tinted blue)
        case favorites
        case history
        case downloads
        case settings

        // Secondary group (below the line)
        case home
        case newInPrivateTab
        case addToFavorites
        case requestDesktopWebsite
        case appearance
        case clearData
        case shareExtension
        case share
        case sendToDevice
        case translate
        case addToPhone
        case downloadPage
        case findInPage
        case fontSize
        case exitBrowser

        var title: String {
            switch self {
            case .favorites:
                return "收藏夹"
            case .history:
                return "历史记录"
            case .downloads:
                return "下载"
            case .settings:
                return "设置"
            case .home:
                return "主页"
            case .newInPrivateTab:
                return "新建 InPrivate 标签页"
            case .addToFavorites:
                return "添加到收藏夹"
            case .requestDesktopWebsite:
                return "查看桌面网页"
            case .appearance:
                return "深色/浅色模式"
            case .clearData:
                return "删除数据"
            case .shareExtension:
                return "拓展"
            case .share:
                return "分享"
            case .sendToDevice:
                return "发送到设备"
            case .translate:
                return "翻译"
            case .addToPhone:
                return "二维码分享"
            case .downloadPage:
                return "下载此页面"
            case .findInPage:
                return "在页面上查找"
            case .fontSize:
                return "字体大小"
            case .exitBrowser:
                return "退出浏览器"
            }
        }

        var symbolName: String {
            switch self {
            case .favorites:
                return "reynard.star"
            case .history:
                return "reynard.clock"
            case .downloads:
                return "reynard.arrow.down.circle"
            case .settings:
                return "reynard.gearshape"
            case .home:
                return "reynard.globe"
            case .newInPrivateTab:
                return "reynard.plus.square.fill.on.square.fill"
            case .addToFavorites:
                return "reynard.book"
            case .requestDesktopWebsite:
                return "reynard.desktopcomputer"
            case .appearance:
                return "reynard.moon.fill"
            case .clearData:
                return "reynard.trash"
            case .shareExtension:
                return "reynard.puzzlepiece.extension"
            case .share:
                return "reynard.square.and.arrow.up"
            case .sendToDevice:
                return "reynard.arrow.up.right"
            case .translate:
                return "reynard.globe"
            case .addToPhone:
                return "reynard.smartphone"
            case .downloadPage:
                return "reynard.square.and.arrow.down"
            case .findInPage:
                return "reynard.magnifyingglass"
            case .fontSize:
                return "reynard.textformat.size"
            case .exitBrowser:
                return "reynard.xmark"
            }
        }

        /// The primary (above the line) group keeps a blue tint, matching Edge.
        var usesPrimaryTint: Bool {
            switch self {
            case .favorites, .history, .downloads, .settings:
                return true
            default:
                return false
            }
        }

        /// Items with no real implementation yet are rendered with a faded
        /// icon as a placeholder (to be wired up later).
        var isUnavailablePlaceholder: Bool {
            // All currently displayed items are wired up; nothing is a
            // placeholder anymore.
            return false
        }
    }

    private enum UX {
        // Feature icons shrunk ~8% and rounded to whole points, then the
        // primary (blue) group matched to the secondary size so both rows read
        // as the same reduced scale: primary 26→20, secondary 22→20.
        static let primarySymbolPointSize: CGFloat = 20
        static let secondarySymbolPointSize: CGFloat = 20
        static let gridItemSpacing: CGFloat = 6
        static let gridContentInset: CGFloat = 8
        // Generous vertical room so tile titles can wrap to up to three lines
        // (smaller font) without clipping or an ellipsis.
        static let gridGroupHeight: CGFloat = 116
        // The primary (blue) row's titles are always short (one line), so its
        // tiles are shorter too: with the icons now the same size as the rest,
        // a 116pt primary tile left a large empty band above the divider.
        static let primaryGroupHeight: CGFloat = 88
        static let listRowHeight: CGFloat = 56
        static let blueTint = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    }

    /// Invoked with the selected item; the presenter decides the action and
    /// dismisses this controller.
    var onSelect: ((Item) -> Void)?

    /// Lets the presenter override an item's title (e.g. the desktop/mobile
    /// website toggle label depends on the current mode).
    var titleOverride: ((Item) -> String?)?
    /// Lets the presenter override an item's symbol.
    var symbolOverride: ((Item) -> String?)?

    private func displayTitle(for item: Item) -> String {
        return titleOverride?(item) ?? item.title
    }

    private func displaySymbol(for item: Item) -> String {
        return symbolOverride?(item) ?? item.symbolName
    }

    private enum Section: Int, CaseIterable {
        case primary
        case secondary
    }

    private let cellReuseIdentifier = "EdgeMenuCell"
    private let dividerReuseIdentifier = "EdgeMenuDivider"

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.delegate = self
        view.dataSource = self
        view.alwaysBounceVertical = true
        return view
    }()

    /// The Edge menu always uses the fixed 4-column icon+label grid in both
    /// orientations/layouts (the vertical list variant was removed). This
    /// constant is kept as a single source of truth so every layout call site
    /// (tile size, cell insets, symbol/title placement) picks the grid branch.
    private var isWideLayout: Bool {
        return true
    }

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView.register(EdgeMenuCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        collectionView.register(
            UICollectionReusableView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: dividerReuseIdentifier
        )
        preferredContentSize = CGSize(width: 375, height: gridContentHeight)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.reloadData()
    }

    /// Exact height of the wide 4-column grid: one primary row + the rows the
    /// secondary group wraps into, plus inter-row spacing, the per-section
    /// vertical insets and the 1pt divider between the groups.
    private var gridContentHeight: CGFloat {
        let columnCount = 4
        let secondaryRowCount = (items(in: .secondary).count + columnCount - 1) / columnCount
        let interRowSpacing = CGFloat(max(0, secondaryRowCount - 1)) * UX.gridItemSpacing
        let sectionVerticalInsets = (UX.gridContentInset * 2) * CGFloat(Section.allCases.count)
        // Primary is exactly one (shorter) row; the secondary group wraps into
        // the taller, wrapping-capable rows.
        return UX.primaryGroupHeight
            + CGFloat(secondaryRowCount) * UX.gridGroupHeight
            + interRowSpacing
            + sectionVerticalInsets
            + 1 // divider
    }

    /// Tile height for a section: the one-line primary row is shorter than the
    /// secondary rows, which must fit wrapped titles.
    private func groupHeight(for section: Section) -> CGFloat {
        switch section {
        case .primary:
            return UX.primaryGroupHeight
        case .secondary:
            return UX.gridGroupHeight
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass else {
            return
        }
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
    }

    // MARK: - Data

    private func items(in section: Section) -> [Item] {
        switch section {
        case .primary:
            return [.favorites, .history, .downloads, .settings]
        case .secondary:
            return [
                .home, .newInPrivateTab, .addToFavorites, .requestDesktopWebsite,
                .appearance, .clearData, .shareExtension, .share, .translate,
                .addToPhone, .findInPage, .fontSize, .exitBrowser,
            ]
        }
    }

    // MARK: - UICollectionViewDataSource

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return Section.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let menuSection = Section(rawValue: section) else {
            return 0
        }
        return items(in: menuSection).count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! EdgeMenuCell
        guard let menuSection = Section(rawValue: indexPath.section) else {
            return cell
        }
        let item = items(in: menuSection)[indexPath.row]
        cell.configure(
            title: displayTitle(for: item),
            symbolName: displaySymbol(for: item),
            tint: item.usesPrimaryTint ? UX.blueTint : .label,
            usesPrimaryTint: item.usesPrimaryTint,
            symbolPointSize: item.usesPrimaryTint ? UX.primarySymbolPointSize : UX.secondarySymbolPointSize,
            wideLayout: isWideLayout,
            isPlaceholder: item.isUnavailablePlaceholder
        )
        return cell
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let menuSection = Section(rawValue: indexPath.section) else {
            return
        }
        let items = items(in: menuSection)
        guard items.indices.contains(indexPath.row) else {
            return
        }
        onSelect?(items[indexPath.row])
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        let horizontalInset: CGFloat = isWideLayout ? UX.gridContentInset : 0
        return UIEdgeInsets(top: UX.gridContentInset, left: horizontalInset, bottom: UX.gridContentInset, right: horizontalInset)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        return isWideLayout ? UX.gridItemSpacing : 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        return isWideLayout ? UX.gridItemSpacing : 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let availableWidth = collectionView.bounds.width - (isWideLayout ? (UX.gridContentInset * 2) : 0)
        if isWideLayout {
            // A fixed 4-column grid (4 x N) in wide / landscape layout, like a
            // compact app drawer.
            let columnCount = 4
            let itemWidth = (availableWidth - (CGFloat(columnCount - 1) * UX.gridItemSpacing)) / CGFloat(columnCount)
            let section = Section(rawValue: indexPath.section) ?? .secondary
            return CGSize(width: itemWidth, height: groupHeight(for: section))
        }
        return CGSize(width: availableWidth, height: UX.listRowHeight)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        guard let menuSection = Section(rawValue: section), menuSection == .secondary else {
            return .zero
        }
        return CGSize(width: collectionView.bounds.width, height: 1)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: dividerReuseIdentifier,
            for: indexPath
        )
        header.backgroundColor = .separator
        return header
    }
}

/// A single tile (grid) or row (list) in the Edge menu.
final class EdgeMenuCell: UICollectionViewCell {

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        // One size smaller so titles fit the slightly widened tiles; wrap up to
        // three lines without a truncating ellipsis.
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.numberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    private let symbolView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .center
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var wideConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []

    func configure(
        title: String,
        symbolName: String,
        tint: UIColor,
        usesPrimaryTint: Bool,
        symbolPointSize: CGFloat,
        wideLayout: Bool,
        isPlaceholder: Bool
    ) {
        titleLabel.text = title
        titleLabel.textColor = tint

        let configuration = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: usesPrimaryTint ? .medium : .regular)
        symbolView.image = UIImage(named: symbolName, in: .main, with: configuration)
        symbolView.tintColor = tint

        let alpha: CGFloat = isPlaceholder ? 0.4 : 1
        symbolView.alpha = alpha
        titleLabel.alpha = alpha

        // No tile background: Edge shows plain icon + label (only a selection
        // tint on highlight), keeping the menu light.
        contentView.backgroundColor = .clear

        applyLayout(wideLayout: wideLayout)
    }

    private func applyLayout(wideLayout: Bool) {
        if contentView.subviews.isEmpty {
            contentView.addSubview(symbolView)
            contentView.addSubview(titleLabel)
        }

        NSLayoutConstraint.deactivate(wideConstraints + listConstraints)
        wideConstraints = []
        listConstraints = []

        if wideLayout {
            wideConstraints = [
                symbolView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                symbolView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
                symbolView.widthAnchor.constraint(equalToConstant: 40),
                symbolView.heightAnchor.constraint(equalToConstant: 40),

                titleLabel.topAnchor.constraint(equalTo: symbolView.bottomAnchor, constant: 8),
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
                titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
                titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            ]
            NSLayoutConstraint.activate(wideConstraints)
        } else {
            listConstraints = [
                symbolView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
                symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                symbolView.widthAnchor.constraint(equalToConstant: 40),
                symbolView.heightAnchor.constraint(equalToConstant: 40),

                titleLabel.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ]
            titleLabel.textAlignment = .natural
            NSLayoutConstraint.activate(listConstraints)
        }
    }
}
