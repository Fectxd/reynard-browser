//
//  EdgeAppearanceViewController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Edge-style "深色/浅色模式" popup, presented the same way as the Font size
//  window. Reuses the three option tiles of Settings > Appearance
//  (AppAppearanceOptionControl: 系统 / 浅色 / 深色), each kept square.
//

import UIKit

final class EdgeAppearanceViewController: UIViewController {

    private enum UX {
        static let contentWidth: CGFloat = 300
        // Natural height: 16 + title 22 + 4 + subtitle 16 + 16 + tiles 118 + 16.
        static let contentHeight: CGFloat = 212
        static let headerFontSize: CGFloat = 18
        static let horizontalPadding: CGFloat = 16
        static let topPadding: CGFloat = 16
        static let minimumGap: CGFloat = 16
        // AppAppearanceOptionControl: 74pt preview + 5pt side insets, so an
        // 84pt-wide option shows a square preview.
        static let optionWidth: CGFloat = 84
        static let optionSpacing: CGFloat = 8
    }

    /// Invoked when the user picks an appearance; the presenter persists the
    /// choice and applies it.
    var onSelect: ((AppAppearance) -> Void)?

    private var selectedAppearance: AppAppearance

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "深色/浅色模式"
        label.font = .systemFont(ofSize: UX.headerFontSize, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "选择外观"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    // Same controls, symbols and titles as Settings > Appearance.
    private let systemOption = AppAppearanceOptionControl(
        appearance: .system,
        symbolName: "reynard.circle.lefthalf.filled",
        title: NSLocalizedString("System", comment: "Appearance option")
    )
    private let lightOption = AppAppearanceOptionControl(
        appearance: .light,
        symbolName: "reynard.sun.max.fill",
        title: NSLocalizedString("Day", comment: "Light appearance option")
    )
    private let darkOption = AppAppearanceOptionControl(
        appearance: .dark,
        symbolName: "reynard.moon.fill",
        title: NSLocalizedString("Night", comment: "Dark appearance option")
    )

    private lazy var optionsStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [systemOption, lightOption, darkOption])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = UX.optionSpacing
        return stackView
    }()

    init(current: AppAppearance) {
        selectedAppearance = current
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Same grouped (grey) background as Settings > Appearance: a selected
        // tile is filled with systemBackground, which is invisible on a white
        // panel.
        view.backgroundColor = .systemGroupedBackground
        preferredContentSize = CGSize(width: UX.contentWidth, height: UX.contentHeight)
        configureHierarchy()
        configureConstraints()
        displaySelection()
        systemOption.addTarget(self, action: #selector(selectSystem), for: .touchUpInside)
        lightOption.addTarget(self, action: #selector(selectLight), for: .touchUpInside)
        darkOption.addTarget(self, action: #selector(selectDark), for: .touchUpInside)
    }

    private func configureHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(optionsStackView)
    }

    private func configureConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        // The popover can be taller than the content (the menu container
        // sizes it). Keep the header at the top of the safe area and centre
        // the tiles in the space below it, so spare height is split evenly
        // instead of piling up at the bottom (the Font size panel looked
        // shifted up for exactly that reason).
        let topGap = UILayoutGuide()
        let bottomGap = UILayoutGuide()
        view.addLayoutGuide(topGap)
        view.addLayoutGuide(bottomGap)
        let equalGaps = topGap.heightAnchor.constraint(equalTo: bottomGap.heightAnchor)
        equalGaps.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: UX.topPadding),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalPadding),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -UX.horizontalPadding),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalPadding),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -UX.horizontalPadding),

            topGap.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor),
            topGap.bottomAnchor.constraint(equalTo: optionsStackView.topAnchor),
            topGap.heightAnchor.constraint(greaterThanOrEqualToConstant: UX.minimumGap),
            bottomGap.topAnchor.constraint(equalTo: optionsStackView.bottomAnchor),
            bottomGap.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            bottomGap.heightAnchor.constraint(greaterThanOrEqualToConstant: UX.minimumGap),
            equalGaps,

            // Not stretched to the popover width: three square tiles, centred.
            optionsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            optionsStackView.widthAnchor.constraint(equalToConstant: UX.optionWidth * 3 + UX.optionSpacing * 2),
        ])
    }

    private func displaySelection() {
        systemOption.displaySelection(selected: selectedAppearance == .system)
        lightOption.displaySelection(selected: selectedAppearance == .light)
        darkOption.displaySelection(selected: selectedAppearance == .dark)
    }

    @objc private func selectSystem() {
        systemOption.animateTap()
        select(.system)
    }

    @objc private func selectLight() {
        lightOption.animateTap()
        select(.light)
    }

    @objc private func selectDark() {
        darkOption.animateTap()
        select(.dark)
    }

    private func select(_ appearance: AppAppearance) {
        selectedAppearance = appearance
        displaySelection()
        onSelect?(appearance)
        // Let the new selection show for a moment before closing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}
