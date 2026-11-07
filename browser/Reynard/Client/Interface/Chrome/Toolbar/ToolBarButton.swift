//
//  ToolbarButton.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class ToolbarButton: UIButton {
    private enum UX {
        static let toolbarButtonCornerRadius: CGFloat = 10
        static let minimumTouchTargetSideLength: CGFloat = 44
        static let downloadButtonSideLength: CGFloat = 44
        static let downloadIconSize: CGFloat = 24
        static let downloadIconVerticalOffset: CGFloat = -1
        static let downloadProgressTrackWidth: CGFloat = 18
        static let downloadProgressTrackHeight: CGFloat = 2.5
        static let downloadProgressTrackBottomInset: CGFloat = 1
        static let downloadProgressTrackCornerRadius: CGFloat = 1.25
        static let standardButtonSideLength: CGFloat = 30
        static let standardSymbolPointSize: CGFloat = 20
        static let newTabSymbolPointSize: CGFloat = 20
        static let downloadSymbolPointSize: CGFloat = 17
        static let tabCountBadgeSideLength: CGFloat = 14
        static let tabCountBadgeInset: CGFloat = 2
        static let tabCountBadgeFontSize: CGFloat = 9
        // The phone (narrow) bottom toolbar button row is short, so its tab
        // badge uses a smaller, more inset pill that is guaranteed to stay
        // fully inside the visible button.
        static let compactTabCountBadgeSideLength: CGFloat = 12
        static let compactTabCountBadgeInset: CGFloat = 3
        static let compactTabCountBadgeFontSize: CGFloat = 8
    }
    
    enum ButtonType {
        case back
        case forward
        case share
        case library
        case tabOverview
        case download
        case newTab
        case sidebar
        case favorite
    }
    
    enum TabCountBadgeStyle {
        case standard
        case compact
    }
    
    private lazy var downloadIconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .label
        view.clipsToBounds = false
        view.isHidden = true
        return view
    }()
    
    private lazy var downloadProgressTrackView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemFill
        view.layer.cornerRadius = UX.downloadProgressTrackCornerRadius
        view.isHidden = true
        return view
    }()
    
    private lazy var downloadProgressFillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .label
        view.layer.cornerRadius = UX.downloadProgressTrackCornerRadius
        view.isHidden = true
        return view
    }()
    
    private lazy var downloadProgressFillWidthConstraint = downloadProgressFillView.widthAnchor.constraint(equalToConstant: 0)

    // Tab-overview count badge (bottom-right corner). Lazy so it only exists
    // for the tab-overview button.
    private lazy var tabCountBadgeView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.isHidden = true
        view.layer.cornerCurve = .continuous
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? .white : .black
        }
        return view
    }()

    private lazy var tabCountBadgeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        label.font = .monospacedDigitSystemFont(ofSize: badgeFontSize, weight: .bold)
        label.textColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? .black : .white
        }
        label.textAlignment = .center
        return label
    }()

    private let toolbarButtonType: ButtonType
    private let tabCountBadgeStyle: TabCountBadgeStyle
    private(set) var isShowingDownloads = false
    
    // MARK: - Lifecycle
    
    init(
        buttonType: ButtonType,
        target: AnyObject,
        action: Selector,
        tabCountBadgeStyle: TabCountBadgeStyle = .standard
    ) {
        toolbarButtonType = buttonType
        self.tabCountBadgeStyle = tabCountBadgeStyle
        super.init(frame: .zero)
        if #available(iOS 13.4, *) {
            isPointerInteractionEnabled = true
        }
        configureAppearance()
        configureImage()
        configureTarget(target, action: action)
        configureDownloadViewsIfNeeded()
        configureTabCountViewsIfNeeded()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0 else {
            return false
        }
        
        let horizontalInset = min(0, (bounds.width - UX.minimumTouchTargetSideLength) / 2)
        let verticalInset = min(0, (bounds.height - UX.minimumTouchTargetSideLength) / 2)
        let hitFrame = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        
        return hitFrame.contains(point)
    }
    
    override var intrinsicContentSize: CGSize {
        let sideLength = toolbarButtonType == .download
        ? UX.downloadButtonSideLength
        : UX.standardButtonSideLength
        return CGSize(width: sideLength, height: sideLength)
    }
    
    // MARK: - Updates
    
    func applyDownloadSummary(_ summary: DownloadStoreSummary) {
        guard toolbarButtonType == .download else {
            return
        }
        
        let shouldShowDownloads = summary.showsToolbarButton
        if shouldShowDownloads != isShowingDownloads {
            isShowingDownloads = shouldShowDownloads
            if shouldShowDownloads {
                playDownloadBounceAnimation()
            }
        }
        
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.downloadSymbolPointSize, weight: .regular)
        downloadIconView.image = UIImage(named: "reynard.arrow.down.circle", in: .main, with: configuration)
        
        let progress = min(max(CGFloat(summary.aggregateProgress), 0), 1)
        let showsProgress = summary.activeCount > 0
        downloadProgressTrackView.isHidden = !showsProgress
        downloadProgressFillView.isHidden = !showsProgress
        downloadProgressFillWidthConstraint.constant = UX.downloadProgressTrackWidth * progress
        accessibilityLabel = NSLocalizedString("Downloads", comment: "")
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = .label
        layer.cornerRadius = UX.toolbarButtonCornerRadius
        layer.cornerCurve = .continuous
    }
    
    private func configureImage() {
        guard toolbarButtonType != .download else {
            return
        }
        setImage(UIImage(named: symbolName), for: .normal)
        let pointSize = toolbarButtonType == .newTab
        ? UX.newTabSymbolPointSize
        : UX.standardSymbolPointSize
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular),
            forImageIn: .normal
        )
    }
    
    private func configureTarget(_ target: AnyObject, action: Selector) {
        addTarget(target, action: action, for: .touchUpInside)
    }
    
    private func configureDownloadViewsIfNeeded() {
        guard toolbarButtonType == .download else {
            return
        }
        
        layer.masksToBounds = false
        clipsToBounds = false
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        downloadIconView.isHidden = false
        addSubview(downloadIconView)
        addSubview(downloadProgressTrackView)
        addSubview(downloadProgressFillView)
        
        NSLayoutConstraint.activate([
            downloadIconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            downloadIconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: UX.downloadIconVerticalOffset),
            downloadIconView.widthAnchor.constraint(equalToConstant: UX.downloadIconSize),
            downloadIconView.heightAnchor.constraint(equalToConstant: UX.downloadIconSize),
            
            downloadProgressTrackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            downloadProgressTrackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UX.downloadProgressTrackBottomInset),
            downloadProgressTrackView.widthAnchor.constraint(equalToConstant: UX.downloadProgressTrackWidth),
            downloadProgressTrackView.heightAnchor.constraint(equalToConstant: UX.downloadProgressTrackHeight),
            
            downloadProgressFillView.leadingAnchor.constraint(equalTo: downloadProgressTrackView.leadingAnchor),
            downloadProgressFillView.centerYAnchor.constraint(equalTo: downloadProgressTrackView.centerYAnchor),
            downloadProgressFillView.heightAnchor.constraint(equalTo: downloadProgressTrackView.heightAnchor),
            downloadProgressFillWidthConstraint,
        ])
    }

    private func configureTabCountViewsIfNeeded() {
        guard toolbarButtonType == .tabOverview else {
            return
        }

        clipsToBounds = false
        addSubview(tabCountBadgeView)
        tabCountBadgeView.addSubview(tabCountBadgeLabel)

        // Anchor the pill to the BUTTON CENTER with a fixed offset rather than
        // to the button's edges. On the phone (compact) bottom toolbar the tab
        // button is much wider than the centered glyph (fillEqually), so edge
        // anchoring made the pill float away from the icon and drift with the
        // button's width. Center-based anchoring keeps it glued to the glyph's
        // lower-right regardless of the button's width. The offset is constant:
        // side/2 - inset - pill/2 = +6 for both styles.
        let badgeCenterOffset = (UX.standardButtonSideLength / 2) - badgeInset - (badgeSideLength / 2)
        NSLayoutConstraint.activate([
            tabCountBadgeView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: badgeCenterOffset),
            tabCountBadgeView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: badgeCenterOffset),
            tabCountBadgeView.heightAnchor.constraint(equalToConstant: badgeSideLength),
            tabCountBadgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: badgeSideLength),

            tabCountBadgeLabel.leadingAnchor.constraint(equalTo: tabCountBadgeView.leadingAnchor, constant: 3),
            tabCountBadgeLabel.trailingAnchor.constraint(equalTo: tabCountBadgeView.trailingAnchor, constant: -3),
            tabCountBadgeLabel.centerYAnchor.constraint(equalTo: tabCountBadgeView.centerYAnchor),
        ])
    }

    /// Shows the current tab count on the tab-overview button (bottom-right
    /// corner) and swaps the icon to reflect private vs regular mode.
    func setTabCount(_ count: Int, isPrivate: Bool) {
        guard toolbarButtonType == .tabOverview else {
            return
        }

        let normalizedCount = max(count, 0)
        tabCountBadgeLabel.text = normalizedCount > 99 ? "99+" : "\(normalizedCount)"
        tabCountBadgeView.isHidden = normalizedCount == 0
        tabCountBadgeView.layer.cornerRadius = badgeSideLength / 2

        applyTabCountPrivateStyle(isPrivate: isPrivate)

        accessibilityValue = normalizedCount == 0 ? nil : "\(normalizedCount)"
        accessibilityLabel = isPrivate
        ? NSLocalizedString("Private Tabs", comment: "")
        : NSLocalizedString("Tabs", comment: "")
    }

    // MARK: - Tab Count Badge Metrics

    private var badgeSideLength: CGFloat {
        return tabCountBadgeStyle == .compact
        ? UX.compactTabCountBadgeSideLength
        : UX.tabCountBadgeSideLength
    }

    private var badgeInset: CGFloat {
        return tabCountBadgeStyle == .compact
        ? UX.compactTabCountBadgeInset
        : UX.tabCountBadgeInset
    }

    private var badgeFontSize: CGFloat {
        return tabCountBadgeStyle == .compact
        ? UX.compactTabCountBadgeFontSize
        : UX.tabCountBadgeFontSize
    }

    private func applyTabCountPrivateStyle(isPrivate: Bool) {
        // Distinguish modes: private uses the filled glyph + a dimmer tint.
        let baseName = isPrivate ? "reynard.square.on.square.fill" : "reynard.square.on.square"
        let systemFallback = isPrivate ? "square.on.square.fill" : "square.on.square"
        let image = UIImage(named: baseName, in: .main, compatibleWith: traitCollection)
            ?? UIImage(systemName: systemFallback)
        setImage(image, for: .normal)
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.standardSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
        tintColor = isPrivate ? .secondaryLabel : .label
    }
    
    // MARK: - Button
    
    private var symbolName: String {
        switch toolbarButtonType {
        case .back: return "reynard.chevron.backward"
        case .forward: return "reynard.chevron.forward"
        case .share: return "reynard.square.and.arrow.up"
        case .library: return "reynard.ellipsis.circle"
        case .tabOverview: return "reynard.square.on.square"
        case .download: return "reynard.arrow.down.circle"
        case .newTab: return "reynard.plus"
        case .sidebar: return "reynard.sidebar.left"
        case .favorite: return "reynard.star"
        }
    }
    
    private func playDownloadBounceAnimation() {
        if #available(iOS 17.0, *) {
            downloadIconView.addSymbolEffect(.bounce)
        }
    }
}
