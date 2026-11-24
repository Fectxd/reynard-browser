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
        // Edge UI tab-count badge.
        static let tabCountBadgeSideLength: CGFloat = 14
        static let tabCountBadgeInset: CGFloat = 2
        static let tabCountBadgeFontSize: CGFloat = 9
        // The phone (narrow) bottom toolbar row is short, so its badge is a
        // smaller, more inset pill that stays fully inside the button.
        static let compactTabCountBadgeSideLength: CGFloat = 12
        static let compactTabCountBadgeInset: CGFloat = 3
        static let compactTabCountBadgeFontSize: CGFloat = 8
    }
    
    enum TabCountBadgeStyle {
        case standard
        case compact
    }
    
    enum ButtonType: Equatable {
        case item(ToolbarItem)
        case sidebar
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
    
    let toolbarButtonType: ButtonType
    private let tabCountBadgeStyle: TabCountBadgeStyle
    
    // Tab-overview count badge (lower-right of the glyph). Lazy so it only
    // exists for the tab-overview button.
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
        let sideLength = toolbarButtonType == .item(.downloads)
        ? UX.downloadButtonSideLength
        : UX.standardButtonSideLength
        return CGSize(width: sideLength, height: sideLength)
    }
    
    // MARK: - Updates
    
    func applyDownloadSummary(_ summary: DownloadStoreSummary) {
        guard toolbarButtonType == .item(.downloads) else {
            return
        }
        
        let shouldShowDownloads = summary.showsToolbarButton
        if shouldShowDownloads != isShowingDownloads {
            isShowingDownloads = shouldShowDownloads
            if shouldShowDownloads {
                playDownloadBounceAnimation()
            }
        }
        
        let progress = min(max(CGFloat(summary.aggregateProgress), 0), 1)
        let showsProgress = summary.activeCount > 0
        downloadProgressTrackView.isHidden = !showsProgress
        downloadProgressFillView.isHidden = !showsProgress
        downloadProgressFillWidthConstraint.constant = UX.downloadProgressTrackWidth * progress
        accessibilityLabel = NSLocalizedString("Downloads", comment: "")
    }
    
    // MARK: - Tab Count Badge (Edge UI)
    
    /// Shows the tab count on the tab-overview button and swaps the glyph for
    /// private vs regular mode.
    func setTabCount(_ count: Int, isPrivate: Bool) {
        guard toolbarButtonType == .item(.tabOverview) else {
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
    
    private func configureTabCountViewsIfNeeded() {
        guard toolbarButtonType == .item(.tabOverview) else {
            return
        }
        
        clipsToBounds = false
        addSubview(tabCountBadgeView)
        tabCountBadgeView.addSubview(tabCountBadgeLabel)
        // Anchored to the button centre with a fixed offset, so the pill stays
        // on the glyph's lower-right however wide the button is stretched.
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
    
    private var badgeSideLength: CGFloat {
        return tabCountBadgeStyle == .compact ? UX.compactTabCountBadgeSideLength : UX.tabCountBadgeSideLength
    }
    
    private var badgeInset: CGFloat {
        return tabCountBadgeStyle == .compact ? UX.compactTabCountBadgeInset : UX.tabCountBadgeInset
    }
    
    private var badgeFontSize: CGFloat {
        return tabCountBadgeStyle == .compact ? UX.compactTabCountBadgeFontSize : UX.tabCountBadgeFontSize
    }
    
    private func applyTabCountPrivateStyle(isPrivate: Bool) {
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
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = .label
        layer.cornerRadius = UX.toolbarButtonCornerRadius
        layer.cornerCurve = .continuous
    }
    
    private func configureImage() {
        guard toolbarButtonType != .item(.downloads) else {
            return
        }
        setImage(UIImage(named: symbolName), for: .normal)
        let pointSize = toolbarButtonType == .item(.newTab)
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
        guard toolbarButtonType == .item(.downloads) else {
            return
        }
        
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.downloadSymbolPointSize, weight: .regular)
        downloadIconView.image = UIImage(named: "reynard.arrow.down.circle", in: .main, with: configuration)
        
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
    
    // MARK: - Button
    
    private var symbolName: String {
        switch toolbarButtonType {
        case .item(let item): return item.symbolName
        case .sidebar: return "reynard.sidebar.left"
        }
    }
    
    private func playDownloadBounceAnimation() {
        if #available(iOS 17.0, *) {
            downloadIconView.addSymbolEffect(.bounce)
        }
    }
}
