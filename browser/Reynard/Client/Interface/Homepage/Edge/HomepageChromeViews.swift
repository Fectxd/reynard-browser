//
//  HomepageChromeViews.swift
//  Reynard
//
//  Weather chip, search field, panel rail and swipe hint used by the Edge
//  style homepage chrome.
//

import UIKit

final class HomepageWeatherChipView: UIControl {
    private enum UX {
        static let height: CGFloat = 34
        static let iconSize: CGFloat = 15
        static let horizontalInset: CGFloat = 11
    }
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = EdgeHomepagePalette.accent
        return imageView
    }()
    
    private let temperatureLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 15, weight: .semibold)
        label.textColor = EdgeHomepagePalette.primaryText
        return label
    }()
    
    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 13)
        label.textColor = EdgeHomepagePalette.secondaryText
        return label
    }()
    
    private let separatorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 13)
        label.textColor = EdgeHomepagePalette.tertiaryText
        label.text = "·"
        return label
    }()
    
    private let cityLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 13)
        label.textColor = EdgeHomepagePalette.secondaryText
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        view.transform = CGAffineTransform(scaleX: 0.62, y: 0.62)
        return view
    }()
    
    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        return stackView
    }()
    
    private(set) var snapshot: HomepageWeatherSnapshot?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        showPlaceholder()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1.0
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = EdgeHomepagePalette.hairline.cgColor
        refreshIcon()
    }
    
    func setLoading(_ isLoading: Bool) {
        if isLoading {
            if snapshot == nil {
                spinner.isHidden = false
                spinner.startAnimating()
            }
        } else {
            spinner.stopAnimating()
            spinner.isHidden = true
        }
    }
    
    func update(with snapshot: HomepageWeatherSnapshot?) {
        self.snapshot = snapshot
        spinner.stopAnimating()
        
        guard let snapshot = snapshot else {
            showPlaceholder()
            return
        }
        
        iconView.isHidden = false
        spinner.isHidden = true
        temperatureLabel.isHidden = false
        temperatureLabel.text = HomepageWeatherStyle.temperature(snapshot.condition.temperature)
        summaryLabel.isHidden = false
        summaryLabel.text = snapshot.condition.summary
        separatorLabel.isHidden = snapshot.city.isEmpty
        cityLabel.isHidden = snapshot.city.isEmpty
        cityLabel.text = snapshot.city
        refreshIcon()
    }
    
    private func showPlaceholder() {
        iconView.isHidden = true
        temperatureLabel.isHidden = true
        summaryLabel.isHidden = false
        summaryLabel.text = NSLocalizedString("Weather", comment: "Homepage weather chip placeholder")
        separatorLabel.isHidden = true
        cityLabel.isHidden = true
    }
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = EdgeHomepagePalette.chip
        layer.cornerRadius = UX.height / 2
        layer.cornerCurve = .continuous
        layer.borderWidth = EdgeHomepagePalette.UX.hairline
        layer.borderColor = EdgeHomepagePalette.hairline.cgColor
    }
    
    private func configureHierarchy() {
        stackView.addArrangedSubview(spinner)
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(temperatureLabel)
        stackView.addArrangedSubview(summaryLabel)
        stackView.addArrangedSubview(separatorLabel)
        stackView.addArrangedSubview(cityLabel)
        addSubview(stackView)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UX.height),
            iconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UX.horizontalInset),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -UX.horizontalInset),
        ])
    }
    
    private func refreshIcon() {
        guard let snapshot = snapshot else {
            return
        }
        
        let name = HomepageWeatherStyle.imageName(
            symbol: snapshot.condition.symbol,
            summary: snapshot.condition.summary,
            isDaytime: snapshot.condition.isDaytime
        )
        iconView.image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: UX.iconSize, weight: .medium)
        )
    }
}

final class HomepageSearchFieldView: UIControl {
    private enum UX {
        static let iconSize: CGFloat = 15
        static let horizontalInset: CGFloat = 14
    }
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = EdgeHomepagePalette.secondaryText
        imageView.image = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        return imageView
    }()
    
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 15)
        label.textColor = EdgeHomepagePalette.secondaryText
        label.text = NSLocalizedString("Search or Enter Address", comment: "Homepage search field placeholder")
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? EdgeHomepagePalette.chip : EdgeHomepagePalette.surface
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = EdgeHomepagePalette.hairline.cgColor
    }
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = EdgeHomepagePalette.surface
        layer.cornerRadius = EdgeHomepagePalette.UX.searchFieldHeight / 2
        layer.cornerCurve = .continuous
        layer.borderWidth = EdgeHomepagePalette.UX.hairline
        layer.borderColor = EdgeHomepagePalette.hairline.cgColor
    }
    
    private func configureHierarchy() {
        addSubview(iconView)
        addSubview(placeholderLabel)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: EdgeHomepagePalette.UX.searchFieldHeight),
            
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UX.horizontalInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            
            placeholderLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UX.horizontalInset),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

final class HomepagePanelRailView: UIView {
    private enum UX {
        static let dotSize: CGFloat = 6
        static let activeDotHeight: CGFloat = 16
        static let spacing: CGFloat = 6
    }
    
    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 6
        return stackView
    }()
    
    private var dots: [UIView] = []
    private var heightConstraints: [NSLayoutConstraint] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(pageCount: Int) {
        for dot in dots {
            dot.removeFromSuperview()
        }
        dots.removeAll()
        heightConstraints.removeAll()
        
        guard pageCount > 1 else {
            isHidden = true
            return
        }
        
        isHidden = false
        for _ in 0..<pageCount {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = UX.dotSize / 2
            dot.layer.cornerCurve = .continuous
            dot.backgroundColor = EdgeHomepagePalette.tertiaryText
            dot.widthAnchor.constraint(equalToConstant: UX.dotSize).isActive = true
            let height = dot.heightAnchor.constraint(equalToConstant: UX.dotSize)
            height.isActive = true
            heightConstraints.append(height)
            stackView.addArrangedSubview(dot)
            dots.append(dot)
        }
        update(progress: 0)
    }
    
    func update(progress: CGFloat) {
        guard !dots.isEmpty else {
            return
        }
        
        for (index, dot) in dots.enumerated() {
            let distance = abs(progress - CGFloat(index))
            let isActive = distance < 0.5
            dot.backgroundColor = isActive ? EdgeHomepagePalette.accent : EdgeHomepagePalette.tertiaryText
            heightConstraints[index].constant = isActive ? UX.activeDotHeight : UX.dotSize
            dot.layer.cornerRadius = UX.dotSize / 2
        }
    }
}

final class HomepagePanelHintView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 12, weight: .medium)
        label.textColor = EdgeHomepagePalette.secondaryText
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0
        
        backgroundColor = EdgeHomepagePalette.chip
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = EdgeHomepagePalette.UX.hairline
        layer.borderColor = EdgeHomepagePalette.hairline.cgColor
        
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = EdgeHomepagePalette.hairline.cgColor
    }
    
    private var displayedText: String?
    
    func show(_ text: String?) {
        guard let text = text, !text.isEmpty else {
            hide()
            return
        }
        
        guard displayedText != text else {
            if alpha < 1 {
                UIView.animate(withDuration: 0.18, animations: {
                    self.alpha = 1
                })
            }
            return
        }
        
        displayedText = text
        label.text = text
        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = 1
        })
    }
    
    func hide() {
        guard alpha > 0 else {
            return
        }
        
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
        })
    }
}
