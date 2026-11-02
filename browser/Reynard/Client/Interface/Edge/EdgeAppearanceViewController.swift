//
//  EdgeAppearanceViewController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Edge-style "深色/浅色模式" popup, presented the same way as the Font size
//  window. The user picks one of: 深色 / 浅色 / 跟随系统.
//

import UIKit

final class EdgeAppearanceViewController: UIViewController {

    private enum UX {
        static let contentWidth: CGFloat = 300
        static let contentHeight: CGFloat = 292
        static let blueTint = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        static let headerFontSize: CGFloat = 18
        static let rowFontSize: CGFloat = 16
        static let rowHeight: CGFloat = 50
        static let rowSpacing: CGFloat = 8
        static let topPadding: CGFloat = 28
        static let bottomPadding: CGFloat = 20
    }

    /// Invoked when the user picks an appearance; the presenter persists the
    /// choice and applies it.
    var onSelect: ((AppAppearance) -> Void)?

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

    private var optionButtons: [UIButton] = []

    init(current: AppAppearance) {
        super.init(nibName: nil, bundle: nil)
        configureOptions(current: current)
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
    }

    private func configureOptions(current: AppAppearance) {
        let options: [(AppAppearance, String)] = [
            (.dark, "深色"),
            (.light, "浅色"),
            (.system, "跟随系统"),
        ]
        for (appearance, title) in options {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: UX.rowFontSize, weight: .medium)
            button.setTitleColor(.label, for: .normal)
            button.contentHorizontalAlignment = .left
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            button.backgroundColor = UIColor.secondarySystemBackground
            button.layer.cornerRadius = 10
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 1
            button.layer.borderColor = (appearance == current ? UX.blueTint : UIColor.clear).cgColor
            button.tintColor = appearance == current ? UX.blueTint : .clear
            button.tag = options.firstIndex(where: { $0.0 == appearance }) ?? 0
            button.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            optionButtons.append(button)
        }
    }

    private func configureHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        optionButtons.forEach { view.addSubview($0) }
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: UX.topPadding),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            optionButtons[0].topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
        ])

        var previousButton: UIButton?
        for button in optionButtons {
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                button.heightAnchor.constraint(equalToConstant: UX.rowHeight),
            ])
            if let previousButton {
                NSLayoutConstraint.activate([
                    button.topAnchor.constraint(equalTo: previousButton.bottomAnchor, constant: UX.rowSpacing),
                ])
            }
            previousButton = button
        }
        if let last = optionButtons.last {
            NSLayoutConstraint.activate([
                last.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -UX.bottomPadding),
            ])
        }
    }

    @objc private func optionTapped(_ sender: UIButton) {
        let options: [AppAppearance] = [.dark, .light, .system]
        guard options.indices.contains(sender.tag) else {
            return
        }
        onSelect?(options[sender.tag])
        dismiss(animated: true)
    }
}
