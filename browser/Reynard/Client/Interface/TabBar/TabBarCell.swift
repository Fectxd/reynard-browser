//
//  TabBarCell.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabBarCell: UICollectionViewCell {
    private enum UX {
        static let expandedTabMinimumWidth: CGFloat = 220
        /// Below this width the cell drops to favicon-only. Above it the title
        /// is always shown and simply fades out towards the trailing edge, so
        /// the label survives as long as there is room for a couple of glyphs.
        static let collapsedTabMinimumWidth: CGFloat = 82
        /// Narrowest a tab may shrink to before the strip starts scrolling.
        static let minimumTabWidth: CGFloat = 96
        static let tabTitleFontSize: CGFloat = 14
        static let tabTitleSpacing: CGFloat = 6
        static let tabFaviconSideLength: CGFloat = 16
        static let tabFaviconCornerRadius: CGFloat = 3
        static let tabCloseButtonSideLength: CGFloat = 22
        static let tabCloseButtonTrailingInset: CGFloat = 6
        static let tabCloseButtonSymbolPointSize: CGFloat = 14
        static let expandedTabContentLeadingInset: CGFloat = 12
        static let expandedTabContentTrailingInset: CGFloat = 32
        static let collapsedTabContentHorizontalInset: CGFloat = 10
        /// leading inset + favicon + spacing + trailing reserve
        static let expandedTabTitleWidthInset: CGFloat = 66
        static let minimumVisibleTabTitleWidth: CGFloat = 18
        static let contentCornerRadius: CGFloat = 10
        /// Horizontal room the bottom flare consumes on each side of the chip.
        static let tabFlareWidth: CGFloat = 8
        /// Width of the soft fade applied to a clipped title.
        static let tabTitleFadeWidth: CGFloat = 14
        static let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        static let borderWidth: CGFloat = 0.5
    }
    
    enum LayoutMode {
        case expanded
        case faviconOnly
    }
    
    static let reuseIdentifier = "TabBarCell"
    
    static var expandedMinimumWidth: CGFloat {
        return UX.expandedTabMinimumWidth
    }
    
    static var collapsedMinimumWidth: CGFloat {
        return UX.collapsedTabMinimumWidth
    }
    
    static var minimumTabWidth: CGFloat {
        return UX.minimumTabWidth
    }
    
    static var contentCornerRadius: CGFloat {
        return UX.contentCornerRadius
    }
    
    static var contentInsets: UIEdgeInsets {
        return UX.contentInsets
    }
    
    private static let fallbackFavicon = UIImage(named: "reynard.globe")
    var closeHandler: (() -> Void)?
    private(set) var tabID: UUID?
    private var isSelectedTab = false
    
    private let tabContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    /// Draws the chip silhouette: rounded top corners plus the concave bottom
    /// "flare" that lets the active tab hug the row below it.
    private let tabShapeLayer = CAShapeLayer()
    
    /// Fades the trailing edge of a clipped title instead of truncating it with
    /// an ellipsis.
    private let titleFadeLayer = CAGradientLayer()
    
    private let faviconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = UX.tabFaviconCornerRadius
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: UX.tabTitleFontSize, weight: .semibold)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.textAlignment = .left
        // Clipped rather than truncated: the gradient mask softens the cut.
        label.lineBreakMode = .byClipping
        return label
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        if #available(iOS 13.4, *) {
            button.isPointerInteractionEnabled = true
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "reynard.xmark"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.tabCloseButtonSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
        button.tintColor = .secondaryLabel
        button.isHidden = true
        return button
    }()
    
    private let titleStack: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = UX.tabTitleSpacing
        return stackView
    }()
    
    private var expandedTrailingConstraint: NSLayoutConstraint!
    private var collapsedTrailingConstraint: NSLayoutConstraint!
    private var expandedLeadingConstraint: NSLayoutConstraint!
    private var collapsedLeadingConstraint: NSLayoutConstraint!
    private var expandedTitleWidthConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureContentPriorities()
        configureActions()
        configureConstraints()
        updateBorderColor()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        tabID = nil
        closeHandler = nil
        tabContentView.layer.borderWidth = 0
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateTabShape()
        updateTitleFade()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        
        updateBorderColor()
        applyChipColor()
    }
    
    // MARK: - Configuration
    
    func configure(
        tab: Tab,
        isSelected: Bool,
        layoutMode: LayoutMode,
        cellWidth: CGFloat
    ) {
        tabID = tab.id
        isSelectedTab = isSelected
        // The selected tab's flare spills into the neighbouring cells, so it
        // has to sit on top of them regardless of the item order.
        layer.zPosition = isSelected ? 1 : 0
        let displayTitle = tab.title.isEmpty ? NSLocalizedString("Homepage", comment: "") : tab.title
        titleLabel.text = displayTitle
        faviconView.image = tab.favicon ?? Self.fallbackFavicon
        applyChipColor()
        tabContentView.layer.borderWidth = 0
        applyShadow(isSelected: isSelected)
        titleLabel.textColor = isSelected ? .label : .secondaryLabel
        faviconView.tintColor = isSelected ? .label : .secondaryLabel
        // The title is kept for as long as a short word fits; narrowing past
        // that falls back to favicon-only, never to an ellipsis.
        let isTooNarrowForTitle = cellWidth - UX.expandedTabTitleWidthInset < UX.minimumVisibleTabTitleWidth
        let isCollapsed = layoutMode == .faviconOnly || isTooNarrowForTitle
        
        titleLabel.isHidden = isCollapsed
        titleStack.spacing = isCollapsed ? 0 : UX.tabTitleSpacing
        expandedLeadingConstraint.isActive = !isCollapsed
        collapsedLeadingConstraint.isActive = isCollapsed
        expandedTrailingConstraint.isActive = !isCollapsed
        collapsedTrailingConstraint.isActive = isCollapsed
        expandedTitleWidthConstraint.isActive = !isCollapsed
        // Every tab keeps its close affordance, matching the reference.
        closeButton.isHidden = isCollapsed
        closeButton.tintColor = isSelected ? .label : .secondaryLabel
        setNeedsLayout()
    }
    
    func containsCloseButton(at point: CGPoint) -> Bool {
        guard !closeButton.isHidden else {
            return false
        }
        
        let convertedPoint = convert(point, to: tabContentView)
        return closeButton.frame.contains(convertedPoint)
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        contentView.backgroundColor = .clear
        // The silhouette is drawn by shape layer instead of `cornerRadius`, so
        // the bottom flare can be expressed and the shadow can use an exact
        // path (masks stay off, otherwise the shadow would be clipped away).
        tabContentView.backgroundColor = .clear
        tabContentView.layer.masksToBounds = false
        tabContentView.layer.borderWidth = 0
        tabShapeLayer.fillColor = UIColor.clear.cgColor
        tabContentView.layer.addSublayer(tabShapeLayer)
        
        titleFadeLayer.colors = [
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.clear.cgColor,
        ]
        titleFadeLayer.locations = [0, 0.85, 1]
        titleFadeLayer.startPoint = CGPoint(x: 0, y: 0.5)
        titleFadeLayer.endPoint = CGPoint(x: 1, y: 0.5)
        titleLabel.layer.mask = titleFadeLayer
    }
    
    private func configureHierarchy() {
        contentView.addSubview(tabContentView)
        tabContentView.addSubview(titleStack)
        titleStack.addArrangedSubview(faviconView)
        titleStack.addArrangedSubview(titleLabel)
        tabContentView.addSubview(closeButton)
    }
    
    private func configureContentPriorities() {
        faviconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        faviconView.setContentCompressionResistancePriority(.required, for: .vertical)
        faviconView.setContentHuggingPriority(.required, for: .horizontal)
    }
    
    private func configureActions() {
        closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
    }
    
    private func configureConstraints() {
        expandedTrailingConstraint = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: tabContentView.trailingAnchor, constant: -UX.expandedTabContentTrailingInset)
        collapsedTrailingConstraint = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: tabContentView.trailingAnchor, constant: -UX.collapsedTabContentHorizontalInset)
        expandedLeadingConstraint = titleStack.leadingAnchor.constraint(equalTo: tabContentView.leadingAnchor, constant: UX.expandedTabContentLeadingInset)
        collapsedLeadingConstraint = titleStack.leadingAnchor.constraint(equalTo: tabContentView.leadingAnchor, constant: UX.collapsedTabContentHorizontalInset)
        expandedTitleWidthConstraint = titleLabel.widthAnchor.constraint(lessThanOrEqualTo: tabContentView.widthAnchor, constant: -UX.expandedTabTitleWidthInset)
        
        NSLayoutConstraint.activate([
            tabContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.contentInsets.left),
            tabContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.contentInsets.right),
            tabContentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.contentInsets.top),
            tabContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.contentInsets.bottom),
            
            titleStack.centerYAnchor.constraint(equalTo: tabContentView.centerYAnchor),
            expandedLeadingConstraint,
            expandedTrailingConstraint,
            
            faviconView.widthAnchor.constraint(equalToConstant: UX.tabFaviconSideLength),
            faviconView.heightAnchor.constraint(equalToConstant: UX.tabFaviconSideLength),
            
            expandedTitleWidthConstraint,
            
            closeButton.trailingAnchor.constraint(equalTo: tabContentView.trailingAnchor, constant: -UX.tabCloseButtonTrailingInset),
            closeButton.centerYAnchor.constraint(equalTo: tabContentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: UX.tabCloseButtonSideLength),
            closeButton.heightAnchor.constraint(equalToConstant: UX.tabCloseButtonSideLength),
        ])
    }
    
    // MARK: - Drawing
    
    private func applyChipColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let color = isSelectedTab ? EdgeChromePalette.surface : EdgeChromePalette.inactiveTab
        tabShapeLayer.fillColor = color.resolvedColor(with: traitCollection).cgColor
    }
    
    private func applyShadow(isSelected: Bool) {
        let isDark = traitCollection.userInterfaceStyle == .dark
        tabContentView.layer.shadowColor = UIColor.black.cgColor
        tabContentView.layer.shadowRadius = 3
        tabContentView.layer.shadowOffset = CGSize(width: 0, height: 1)
        tabContentView.layer.shadowOpacity = isSelected ? (isDark ? 0.45 : 0.16) : 0
    }
    
    private func updateTabShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let bounds = tabContentView.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        
        // Only the selected tab gets the bottom flare; inactive tabs stay as
        // plain chips with rounded top corners. The flare grows outwards (over
        // the neighbours) so the active tab still spans its whole cell width
        // and reads as flush with the tabs beside it.
        let flare = isSelectedTab ? min(UX.tabFlareWidth, bounds.height / 3) : 0
        let radius = min(UX.contentCornerRadius, bounds.width / 2, bounds.height)
        let path = Self.chipPath(in: bounds, cornerRadius: max(0, radius), flare: flare)
        tabShapeLayer.frame = bounds
        tabShapeLayer.path = path.cgPath
        tabContentView.layer.shadowPath = path.cgPath
    }
    
    private func updateTitleFade() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let bounds = titleLabel.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        
        titleFadeLayer.frame = bounds
        // The mask only exists to soften a cut, so a title that already fits
        // must stay fully opaque -- otherwise short labels lose their tail.
        let textWidth = ceil(titleLabel.intrinsicContentSize.width)
        let isClipped = textWidth > bounds.width + 0.5
        let fade = isClipped ? min(UX.tabTitleFadeWidth, bounds.width) : 0
        let solid = Double((bounds.width - fade) / bounds.width)
        titleFadeLayer.locations = [0, NSNumber(value: solid), 1]
    }
    
    private static func chipPath(
        in rect: CGRect,
        cornerRadius radius: CGFloat,
        flare: CGFloat
    ) -> UIBezierPath {
        let path = UIBezierPath()
        let minimumX = rect.minX
        let maximumX = rect.maxX
        let minimumY = rect.minY
        let maximumY = rect.maxY
        
        // Bottom-left fillet: it starts `flare` points outside the cell and
        // curves up into the straight side, which is what makes the active tab
        // look welded to the row below without stealing width from the tab.
        path.move(to: CGPoint(x: minimumX - flare, y: maximumY))
        path.addQuadCurve(
            to: CGPoint(x: minimumX, y: maximumY - flare),
            controlPoint: CGPoint(x: minimumX, y: maximumY)
        )
        path.addLine(to: CGPoint(x: minimumX, y: minimumY + radius))
        path.addQuadCurve(
            to: CGPoint(x: minimumX + radius, y: minimumY),
            controlPoint: CGPoint(x: minimumX, y: minimumY)
        )
        path.addLine(to: CGPoint(x: maximumX - radius, y: minimumY))
        path.addQuadCurve(
            to: CGPoint(x: maximumX, y: minimumY + radius),
            controlPoint: CGPoint(x: maximumX, y: minimumY)
        )
        path.addLine(to: CGPoint(x: maximumX, y: maximumY - flare))
        path.addQuadCurve(
            to: CGPoint(x: maximumX + flare, y: maximumY),
            controlPoint: CGPoint(x: maximumX, y: maximumY)
        )
        path.close()
        return path
    }
    
    private func updateBorderColor() {
        tabContentView.layer.borderColor = UIColor.separator.withAlphaComponent(0.2).cgColor
    }
    
    // MARK: - Actions
    
    @objc private func handleCloseTap() {
        closeHandler?()
    }
}
