//
//  HomepageWeatherDetailViewController.swift
//  Reynard
//
//  Detailed weather panel: current conditions, air quality, five day
//  forecast and a 24 hour temperature curve.
//

import UIKit

final class HomepageHourlyChartCanvasView: UIView {
    private enum UX {
        static let columnWidth: CGFloat = 56
        static let chartTop: CGFloat = 50
        static let chartHeight: CGFloat = 46
        static let height: CGFloat = 132
    }
    
    private let hours: [HomepageWeatherSnapshot.Hour]
    private let currentIndex: Int
    
    init(hours: [HomepageWeatherSnapshot.Hour], currentIndex: Int) {
        self.hours = hours
        self.currentIndex = currentIndex
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: CGFloat(max(hours.count, 1)) * UX.columnWidth, height: UX.height)
    }
    
    override func draw(_ rect: CGRect) {
        guard !hours.isEmpty else {
            return
        }
        
        drawTemperatures(in: rect)
        drawColumns()
    }
    
    private func drawTemperatures(in rect: CGRect) {
        let temperatures = hours.map { $0.temperature }
        guard let minimum = temperatures.min(),
              let maximum = temperatures.max() else {
            return
        }
        
        let range = max(maximum - minimum, 3)
        let points: [CGPoint] = temperatures.enumerated().map { index, temperature in
            let x = CGFloat(index) * UX.columnWidth + UX.columnWidth / 2
            let ratio = CGFloat((temperature - minimum) / range)
            let y = UX.chartTop + (UX.chartHeight - 8) * (1 - ratio) + 4
            return CGPoint(x: x, y: y)
        }
        
        guard points.count > 1 else {
            return
        }
        
        let path = UIBezierPath()
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let previous = index > 0 ? points[index - 1] : points[index]
            let start = points[index]
            let end = points[index + 1]
            let next = index < points.count - 2 ? points[index + 2] : end
            let control1 = CGPoint(
                x: start.x + (end.x - previous.x) / 6,
                y: start.y + (end.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: end.x - (next.x - start.x) / 6,
                y: end.y - (next.y - start.y) / 6
            )
            path.addCurve(to: end, controlPoint1: control1, controlPoint2: control2)
        }
        
        EdgeHomepagePalette.accent.setStroke()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        
        for point in points {
            let dot = UIBezierPath(ovalIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
            EdgeHomepagePalette.accent.setFill()
            dot.fill()
        }
    }
    
    private func drawColumns() {
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: EdgeHomepagePalette.scaledFont(size: 10),
            .foregroundColor: EdgeHomepagePalette.secondaryText,
        ]
        let temperatureAttributes: [NSAttributedString.Key: Any] = [
            .font: EdgeHomepagePalette.scaledFont(size: 13, weight: .semibold),
            .foregroundColor: EdgeHomepagePalette.primaryText,
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: EdgeHomepagePalette.scaledFont(size: 9),
            .foregroundColor: EdgeHomepagePalette.tertiaryText,
        ]
        
        let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        for (index, hour) in hours.enumerated() {
            let originX = CGFloat(index) * UX.columnWidth
            let centerX = originX + UX.columnWidth / 2
            
            let summary = String(hour.summary.prefix(4))
            let summarySize = summary.size(withAttributes: summaryAttributes)
            summary.draw(
                at: CGPoint(x: centerX - summarySize.width / 2, y: 0),
                withAttributes: summaryAttributes
            )
            
            let name = HomepageWeatherStyle.imageName(
                symbol: hour.symbol,
                summary: hour.summary,
                isDaytime: hour.isDaytime
            )
            if let image = UIImage(systemName: name, withConfiguration: iconConfiguration)?
                .withTintColor(EdgeHomepagePalette.secondaryText, renderingMode: .alwaysOriginal) {
                image.draw(in: CGRect(
                    x: centerX - image.size.width / 2,
                    y: 14,
                    width: image.size.width,
                    height: image.size.height
                ))
            }
            
            let temperature = HomepageWeatherStyle.temperature(hour.temperature)
            let temperatureSize = temperature.size(withAttributes: temperatureAttributes)
            temperature.draw(
                at: CGPoint(x: centerX - temperatureSize.width / 2, y: 32),
                withAttributes: temperatureAttributes
            )
            
            let aqiText = "\(EdgeHomepagePalette.aqiLevel(for: hour.aqi))级"
            let aqiSize = aqiText.size(withAttributes: secondaryAttributes)
            aqiText.draw(
                at: CGPoint(x: centerX - aqiSize.width / 2, y: UX.chartTop + UX.chartHeight),
                withAttributes: secondaryAttributes
            )
            
            let isCurrent = index == currentIndex
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: EdgeHomepagePalette.scaledFont(size: 10, weight: isCurrent ? .semibold : .regular),
                .foregroundColor: isCurrent ? EdgeHomepagePalette.accent : EdgeHomepagePalette.secondaryText,
            ]
            let time = HomepageWeatherStyle.hourLabel(for: hour.date, isCurrentHour: isCurrent)
            let timeSize = time.size(withAttributes: timeAttributes)
            time.draw(
                at: CGPoint(x: centerX - timeSize.width / 2, y: UX.height - 14),
                withAttributes: timeAttributes
            )
        }
    }
}

final class HomepageWeatherMetricView: UIView {
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 11)
        return label
    }()
    
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 13, weight: .medium)
        label.textColor = EdgeHomepagePalette.primaryText
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = EdgeHomepagePalette.chip
        layer.cornerRadius = EdgeHomepagePalette.UX.chipCornerRadius
        layer.cornerCurve = .continuous
        
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(icon: String, title: String, value: String, tint: UIColor) {
        iconView.image = UIImage(
            systemName: icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )?.withTintColor(tint, renderingMode: .alwaysOriginal)
        titleLabel.text = title
        titleLabel.textColor = tint
        valueLabel.text = value
    }
}

final class HomepageWeatherDetailViewController: UIViewController {
    private enum UX {
        static let cardMaximumWidth: CGFloat = 560
        static let cardMaximumHeight: CGFloat = 640
        static let cardCornerRadius: CGFloat = 22
        static let contentInset: CGFloat = 18
    }
    
    var onRequestRefresh: (() -> Void)?
    
    private var snapshot: HomepageWeatherSnapshot?
    private var isRefreshing = false
    
    private let backdropView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = EdgeHomepagePalette.dimmedBackdrop
        return view
    }()
    
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = EdgeHomepagePalette.surface
        view.layer.cornerRadius = UX.cardCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()
    
    private let contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 14
        return stackView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 17, weight: .semibold)
        label.textColor = EdgeHomepagePalette.primaryText
        label.text = NSLocalizedString("Weather", comment: "Homepage weather panel title")
        return label
    }()
    
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 12)
        label.textColor = EdgeHomepagePalette.secondaryText
        return label
    }()
    
    private lazy var refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = EdgeHomepagePalette.secondaryText
        button.setImage(UIImage(
            systemName: "arrow.clockwise",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        ), for: .normal)
        button.addTarget(self, action: #selector(handleRefresh), for: .touchUpInside)
        return button
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = EdgeHomepagePalette.secondaryText
        button.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        ), for: .normal)
        button.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        return button
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 13)
        label.textColor = EdgeHomepagePalette.secondaryText
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    // MARK: - Lifecycle
    
    init(snapshot: HomepageWeatherSnapshot?) {
        self.snapshot = snapshot
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureHierarchy()
        configureConstraints()
        rebuildContent(animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIView.animate(withDuration: 0.22) {
            self.backdropView.alpha = 1
            self.cardView.transform = .identity
        }
    }
    
    func update(with snapshot: HomepageWeatherSnapshot?) {
        self.snapshot = snapshot
        isRefreshing = false
        guard isViewLoaded else {
            return
        }
        rebuildContent(animated: true)
    }
    
    func setRefreshing(_ isRefreshing: Bool) {
        self.isRefreshing = isRefreshing
        guard isViewLoaded else {
            return
        }
        
        if isRefreshing {
            statusLabel.text = NSLocalizedString("Updating weather…", comment: "Weather refresh status")
        }
    }
    
    // MARK: - Configuration
    
    private func configureHierarchy() {
        view.addSubview(backdropView)
        view.addSubview(cardView)
        cardView.addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        
        let backdropTap = UITapGestureRecognizer(target: self, action: #selector(handleClose))
        backdropView.addGestureRecognizer(backdropTap)
        
        backdropView.alpha = 0
        cardView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
    }
    
    private func configureConstraints() {
        let widthConstraint = cardView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -32)
        widthConstraint.priority = .defaultHigh
        let heightConstraint = cardView.heightAnchor.constraint(equalTo: view.heightAnchor, constant: -72)
        heightConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.cardMaximumWidth),
            cardView.heightAnchor.constraint(lessThanOrEqualToConstant: UX.cardMaximumHeight),
            cardView.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            widthConstraint,
            heightConstraint,
            
            scrollView.topAnchor.constraint(equalTo: cardView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            
            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: UX.contentInset),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -UX.contentInset),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: UX.contentInset),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -UX.contentInset),
            contentStackView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -UX.contentInset * 2
            ),
        ])
    }
    
    // MARK: - Content
    
    private func rebuildContent(animated: Bool) {
        for subview in contentStackView.arrangedSubviews {
            contentStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        
        contentStackView.addArrangedSubview(makeHeaderRow())
        
        guard let snapshot = snapshot else {
            statusLabel.text = NSLocalizedString("Loading weather…", comment: "Weather loading status")
            contentStackView.addArrangedSubview(statusLabel)
            return
        }
        
        locationLabel.text = [snapshot.region, snapshot.city]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        contentStackView.addArrangedSubview(makeHeroCard(snapshot))
        contentStackView.addArrangedSubview(makeMetricsGrid(snapshot))
        contentStackView.addArrangedSubview(makeSectionTitle(NSLocalizedString("5-Day Forecast", comment: "Weather panel section")))
        contentStackView.addArrangedSubview(makeForecastRow(snapshot))
        
        if !snapshot.hours.isEmpty {
            contentStackView.addArrangedSubview(makeSectionTitle(NSLocalizedString("Hourly Forecast", comment: "Weather panel section")))
            contentStackView.addArrangedSubview(makeHourlyCard(snapshot))
        }
        
        if animated {
            UIView.animate(withDuration: 0.18) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    private func makeHeaderRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let textStackView = UIStackView(arrangedSubviews: [titleLabel, locationLabel])
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.alignment = .leading
        textStackView.spacing = 1
        
        container.addSubview(textStackView)
        container.addSubview(refreshButton)
        container.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            textStackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textStackView.topAnchor.constraint(equalTo: container.topAnchor),
            textStackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textStackView.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -10),
            
            refreshButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 30),
            refreshButton.heightAnchor.constraint(equalToConstant: 30),
            
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
        ])
        
        return container
    }
    
    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 13, weight: .semibold)
        label.textColor = EdgeHomepagePalette.secondaryText
        label.text = text
        return label
    }
    
    private func makeHeroCard(_ snapshot: HomepageWeatherSnapshot) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = EdgeHomepagePalette.chip
        card.layer.cornerRadius = EdgeHomepagePalette.UX.cardCornerRadius
        card.layer.cornerCurve = .continuous
        
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = EdgeHomepagePalette.accent
        let name = HomepageWeatherStyle.imageName(
            symbol: snapshot.condition.symbol,
            summary: snapshot.condition.summary,
            isDaytime: snapshot.condition.isDaytime
        )
        iconView.image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        )
        
        let temperatureLabel = UILabel()
        temperatureLabel.translatesAutoresizingMaskIntoConstraints = false
        temperatureLabel.font = UIFont.systemFont(ofSize: 46, weight: .light)
        temperatureLabel.textColor = EdgeHomepagePalette.primaryText
        temperatureLabel.text = HomepageWeatherStyle.temperature(snapshot.condition.temperature)
        
        let summaryLabel = UILabel()
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = EdgeHomepagePalette.scaledFont(size: 14, weight: .medium)
        summaryLabel.textColor = EdgeHomepagePalette.primaryText
        summaryLabel.text = snapshot.condition.summary
        
        let feelsLikeLabel = UILabel()
        feelsLikeLabel.translatesAutoresizingMaskIntoConstraints = false
        feelsLikeLabel.font = EdgeHomepagePalette.scaledFont(size: 12)
        feelsLikeLabel.textColor = EdgeHomepagePalette.secondaryText
        feelsLikeLabel.text = String(
            format: NSLocalizedString("Feels like %@", comment: "Weather feels like temperature"),
            HomepageWeatherStyle.temperature(snapshot.condition.feelsLike)
        )
        
        let textStackView = UIStackView(arrangedSubviews: [temperatureLabel, summaryLabel, feelsLikeLabel])
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.alignment = .leading
        textStackView.spacing = 1
        
        let highLowLabel = UILabel()
        highLowLabel.translatesAutoresizingMaskIntoConstraints = false
        highLowLabel.font = EdgeHomepagePalette.scaledFont(size: 12)
        highLowLabel.textColor = EdgeHomepagePalette.secondaryText
        highLowLabel.numberOfLines = 0
        highLowLabel.textAlignment = .right
        
        var lines: [String] = []
        if let today = snapshot.days.first {
            lines.append(HomepageWeatherStyle.range(high: today.high, low: today.low))
        }
        if let sunrise = snapshot.sunrise {
            lines.append(NSLocalizedString("Sunrise", comment: "Weather sunrise") + " " + HomepageWeatherStyle.timeLabel(for: sunrise))
        }
        if let sunset = snapshot.sunset {
            lines.append(NSLocalizedString("Sunset", comment: "Weather sunset") + " " + HomepageWeatherStyle.timeLabel(for: sunset))
        }
        highLowLabel.text = lines.joined(separator: "\n")
        
        card.addSubview(iconView)
        card.addSubview(textStackView)
        card.addSubview(highLowLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            
            textStackView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textStackView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            textStackView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            textStackView.trailingAnchor.constraint(lessThanOrEqualTo: highLowLabel.leadingAnchor, constant: -12),
            
            highLowLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            highLowLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        
        return card
    }
    
    private func makeMetricsGrid(_ snapshot: HomepageWeatherSnapshot) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let humidity = HomepageWeatherMetricView(frame: .zero)
        humidity.configure(
            icon: "humidity.fill",
            title: NSLocalizedString("Humidity", comment: "Weather metric"),
            value: "\(Int(snapshot.condition.humidity.rounded()))%",
            tint: EdgeHomepagePalette.accent
        )
        
        let wind = HomepageWeatherMetricView(frame: .zero)
        let windValue = snapshot.condition.windSummary.isEmpty
        ? "\(Int(snapshot.condition.windSpeed.rounded())) km/h"
        : snapshot.condition.windSummary
        wind.configure(
            icon: "wind",
            title: NSLocalizedString("Wind", comment: "Weather metric"),
            value: windValue,
            tint: EdgeHomepagePalette.accent
        )
        
        let uv = HomepageWeatherMetricView(frame: .zero)
        let uvValue = snapshot.condition.uvSummary.isEmpty
        ? "\(Int(snapshot.condition.uvIndex.rounded()))"
        : snapshot.condition.uvSummary
        uv.configure(
            icon: "sun.max.fill",
            title: NSLocalizedString("UV Index", comment: "Weather metric"),
            value: uvValue,
            tint: EdgeHomepagePalette.accent
        )
        
        let aqi = HomepageWeatherMetricView(frame: .zero)
        let aqiValue = snapshot.condition.aqiSeverity.isEmpty
        ? "\(Int(snapshot.condition.aqi.rounded()))"
        : "\(Int(snapshot.condition.aqi.rounded())) · \(snapshot.condition.aqiSeverity)"
        aqi.configure(
            icon: "leaf.fill",
            title: NSLocalizedString("Air Quality", comment: "Weather metric"),
            value: aqiValue,
            tint: EdgeHomepagePalette.aqiColor(for: snapshot.condition.aqi)
        )
        
        let pressure = HomepageWeatherMetricView(frame: .zero)
        pressure.configure(
            icon: "gauge",
            title: NSLocalizedString("Pressure", comment: "Weather metric"),
            value: "\(Int(snapshot.condition.pressure.rounded())) hPa",
            tint: EdgeHomepagePalette.accent
        )
        
        let topRow = UIStackView(arrangedSubviews: [humidity, wind])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.axis = .horizontal
        topRow.distribution = .fillEqually
        topRow.spacing = 8
        
        let bottomRow = UIStackView(arrangedSubviews: [uv, aqi])
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.axis = .horizontal
        bottomRow.distribution = .fillEqually
        bottomRow.spacing = 8
        
        let thirdRow = UIStackView(arrangedSubviews: [pressure])
        thirdRow.translatesAutoresizingMaskIntoConstraints = false
        thirdRow.axis = .horizontal
        thirdRow.distribution = .fillEqually
        
        let stackView = UIStackView(arrangedSubviews: [topRow, bottomRow, thirdRow])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        container.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        
        return container
    }
    
    private func makeForecastRow(_ snapshot: HomepageWeatherSnapshot) -> UIView {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        scrollView.addSubview(stackView)
        
        for (index, day) in snapshot.days.prefix(7).enumerated() {
            stackView.addArrangedSubview(makeForecastCell(day, index: index))
        }
        
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 108),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        
        return scrollView
    }
    
    private func makeForecastCell(_ day: HomepageWeatherSnapshot.Day, index: Int) -> UIView {
        let cell = UIView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.backgroundColor = EdgeHomepagePalette.chip
        cell.layer.cornerRadius = EdgeHomepagePalette.UX.cardCornerRadius
        cell.layer.cornerCurve = .continuous
        
        let dayLabel = UILabel()
        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        dayLabel.font = EdgeHomepagePalette.scaledFont(size: 11, weight: index == 0 ? .semibold : .regular)
        dayLabel.textColor = index == 0 ? EdgeHomepagePalette.accent : EdgeHomepagePalette.secondaryText
        dayLabel.textAlignment = .center
        dayLabel.text = HomepageWeatherStyle.dayLabel(for: day.date, index: index)
        
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = EdgeHomepagePalette.accent
        let name = HomepageWeatherStyle.imageName(
            symbol: day.symbol,
            summary: day.summary,
            isDaytime: day.isDaytime
        )
        iconView.image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        )
        
        let conditionLabel = UILabel()
        conditionLabel.translatesAutoresizingMaskIntoConstraints = false
        conditionLabel.font = EdgeHomepagePalette.scaledFont(size: 10)
        conditionLabel.textColor = EdgeHomepagePalette.secondaryText
        conditionLabel.textAlignment = .center
        conditionLabel.lineBreakMode = .byTruncatingTail
        conditionLabel.text = day.summary
        
        let temperatureLabel = UILabel()
        temperatureLabel.translatesAutoresizingMaskIntoConstraints = false
        temperatureLabel.font = EdgeHomepagePalette.scaledFont(size: 12, weight: .medium)
        temperatureLabel.textColor = EdgeHomepagePalette.primaryText
        temperatureLabel.textAlignment = .center
        temperatureLabel.text = HomepageWeatherStyle.range(high: day.high, low: day.low)
        
        let stackView = UIStackView(arrangedSubviews: [dayLabel, iconView, conditionLabel, temperatureLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 4
        cell.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: 76),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            stackView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: cell.leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
        ])
        
        return cell
    }
    
    private func makeHourlyCard(_ snapshot: HomepageWeatherSnapshot) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = EdgeHomepagePalette.chip
        container.layer.cornerRadius = EdgeHomepagePalette.UX.cardCornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        let chart = HomepageHourlyChartCanvasView(
            hours: snapshot.hours,
            currentIndex: HomepageWeatherStyle.currentHourIndex(hours: snapshot.hours)
        )
        
        scrollView.addSubview(chart)
        container.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 148),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            chart.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            chart.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            chart.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            chart.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            chart.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        
        return container
    }
    
    // MARK: - Actions
    
    @objc private func handleRefresh() {
        guard !isRefreshing else {
            return
        }
        setRefreshing(true)
        onRequestRefresh?()
    }
    
    @objc private func handleClose() {
        dismiss(animated: true)
    }
}
