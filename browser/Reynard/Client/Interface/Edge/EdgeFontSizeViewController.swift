//
//  EdgeFontSizeViewController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Edge-style "Font size" (字体大小) popup. It reads and writes the current
//  site's page-zoom level (stored per host in SiteSettingsStore) and lets the
//  user drag a slider between the smallest and the largest supported level.
//
//  Layout follows Edge:
//    < 字体大小                     (header: back chevron + title)
//      ─────────────────────────
//      网页字体大小                 (section label)
//      A  ────●──────  A           (small A, slider, large A)
//             100%                 (current level)
//      此字号仅适用于此域中的网站。  (footer note)
//

import UIKit

final class EdgeFontSizeViewController: UIViewController {

    private enum UX {
        static let contentWidth: CGFloat = 360
        // Natural content height is ~198pt (52 header + 0.5 divider + 12 +
        // section + 12 + slider + 6 + percent + 14 + note + ~12 bottom). The
        // old 236 left a tall empty band under the footer note. 200 keeps a
        // small cushion while removing the dead space.
        static let contentHeight: CGFloat = 200
        static let blueTint = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        static let smallAFontSize: CGFloat = 11
        static let largeAFontSize: CGFloat = 26
        static let percentFontSize: CGFloat = 17
        static let noteFontSize: CGFloat = 12
        static let sectionFontSize: CGFloat = 14
        static let headerFontSize: CGFloat = 18
    }

    /// Invoked with the newly selected level; the presenter applies it per-site
    /// (persisting to SiteSettingsStore and updating the session).
    var onApply: ((Int) -> Void)?

    /// The zoom levels, in ascending order. The slider maps continuously to the
    /// index of this array so every step is evenly spaced; the value snaps to
    /// the nearest level on change (and on release).
    private let levels = PageZoomLevels.all

    private var currentLevel: Int = Prefs.BrowsingSettings.defaultPageZoomLevel

    // MARK: - View Construction

    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        button.tintColor = UX.blueTint
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        return button
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "字体大小"
        label.font = .systemFont(ofSize: UX.headerFontSize, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let topDivider: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    private let sectionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "网页字体大小"
        label.font = .systemFont(ofSize: UX.sectionFontSize, weight: .regular)
        label.textColor = .label
        return label
    }()

    private let smallALabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "A"
        label.font = .systemFont(ofSize: UX.smallAFontSize, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = Float(levels.count - 1)
        slider.isContinuous = true
        slider.tintColor = UX.blueTint
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        slider.addTarget(
            self,
            action: #selector(sliderReleased(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return slider
    }()

    private let largeALabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "A"
        label.font = .systemFont(ofSize: UX.largeAFontSize, weight: .medium)
        label.textColor = .label
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let percentLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UX.percentFontSize, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private let noteLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "此字号仅适用于此域中的网站。"
        label.font = .systemFont(ofSize: UX.noteFontSize, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    // MARK: - Lifecycle

    init(level: Int? = nil) {
        if let level, levels.contains(level) {
            currentLevel = level
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: UX.contentWidth, height: UX.contentHeight)
        configureHierarchy()
        configureConstraints()
        refreshUI()
    }

    // MARK: - Setup

    private func configureHierarchy() {
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)
        [headerView, topDivider, sectionLabel, smallALabel, slider, largeALabel, percentLabel, noteLabel].forEach {
            view.addSubview($0)
        }
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 52),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -12),

            topDivider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            topDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 0.5),

            sectionLabel.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 12),
            sectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            sectionLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            smallALabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            smallALabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),

            slider.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: smallALabel.trailingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: largeALabel.leadingAnchor, constant: -10),

            largeALabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            largeALabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),

            percentLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 6),
            percentLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            noteLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 14),
            noteLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            noteLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            noteLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - State

    private func refreshUI() {
        guard let index = levels.firstIndex(of: currentLevel) else {
            return
        }
        slider.value = Float(index)
        percentLabel.text = PageZoomLevels.displayText(for: currentLevel)
    }

    private func applyLevel(_ level: Int) {
        currentLevel = level
        percentLabel.text = PageZoomLevels.displayText(for: level)
        onApply?(level)
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: UISlider) {
        let index = Int(sender.value.rounded())
        sender.value = Float(index)
        applyLevel(levels[index])
    }

    /// Snaps to the nearest level once the finger lifts, in case the slider was
    /// still between two steps when `isContinuous` delivered the last value.
    @objc private func sliderReleased(_ sender: UISlider) {
        let index = Int(sender.value.rounded())
        sender.value = Float(index)
        applyLevel(levels[index])
    }

    @objc private func backTapped() {
        dismiss(animated: true)
    }
}
