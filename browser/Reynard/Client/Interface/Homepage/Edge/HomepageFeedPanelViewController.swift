//
//  HomepageFeedPanelViewController.swift
//  Reynard
//
//  Information panel for the Edge style homepage.
//

import UIKit

protocol HomepageFeedPanelViewControllerDelegate: AnyObject {
    func homepageFeedPanelViewController(_ controller: HomepageFeedPanelViewController, didSelect article: HomepageFeedArticle)
}

final class HomepageFeedRowView: UIControl {
    private enum UX {
        static let thumbnailSize: CGFloat = 72
        static let verticalInset: CGFloat = 10
    }
    
    private let thumbnailView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = EdgeHomepagePalette.chip
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 14, weight: .medium)
        label.textColor = EdgeHomepagePalette.primaryText
        label.numberOfLines = 2
        return label
    }()
    
    private let metaLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 11)
        label.textColor = EdgeHomepagePalette.secondaryText
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private let separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = EdgeHomepagePalette.hairline
        return view
    }()
    
    private(set) var article: HomepageFeedArticle?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        
        let textStackView = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.alignment = .fill
        textStackView.spacing = 4
        
        addSubview(thumbnailView)
        addSubview(textStackView)
        addSubview(separatorView)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: UX.thumbnailSize + UX.verticalInset * 2),
            
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: UX.verticalInset),
            thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -UX.verticalInset),
            thumbnailView.widthAnchor.constraint(equalToConstant: UX.thumbnailSize),
            thumbnailView.heightAnchor.constraint(equalToConstant: UX.thumbnailSize),
            
            textStackView.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            textStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textStackView.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            
            separatorView.leadingAnchor.constraint(equalTo: textStackView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: EdgeHomepagePalette.UX.hairline),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1.0
        }
    }
    
    func configure(article: HomepageFeedArticle) {
        self.article = article
        titleLabel.text = article.title
        
        var metaParts: [String] = []
        if !article.provider.isEmpty {
            metaParts.append(article.provider)
        }
        if let publishedAt = article.publishedAt {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateFormat = "MM-dd HH:mm"
            metaParts.append(formatter.string(from: publishedAt))
        }
        metaLabel.text = metaParts.joined(separator: " · ")
        
        thumbnailView.image = nil
        guard let imageURL = article.imageURL else {
            return
        }
        
        HomepageFeedImageLoader.shared.image(for: imageURL) { [weak self] image in
            guard let self = self,
                  let image = image,
                  self.article?.imageURL == imageURL else {
                return
            }
            self.thumbnailView.image = image
        }
    }
}

final class HomepageFeedPanelViewController: UIViewController {
    weak var delegate: HomepageFeedPanelViewControllerDelegate?
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 22, weight: .bold)
        )
        label.textColor = EdgeHomepagePalette.primaryText
        label.text = NSLocalizedString("Feed", comment: "Homepage information panel title")
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = EdgeHomepagePalette.scaledFont(size: 12)
        label.textColor = EdgeHomepagePalette.secondaryText
        label.numberOfLines = 0
        return label
    }()
    
    private let rowsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 0
        return stackView
    }()
    
    private var articles: [HomepageFeedArticle] = []
    private var isLoading = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureHierarchy()
        configureConstraints()
        reset()
    }
    
    func reset() {
        for subview in rowsStackView.arrangedSubviews {
            rowsStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        statusLabel.text = NSLocalizedString("Loading feed…", comment: "Homepage feed loading state")
        articles = []
    }
    
    func reload() {
        guard !isLoading else {
            return
        }
        
        isLoading = true
        reset()
        HomepageFeedService.shared.load { [weak self] articles in
            guard let self = self else {
                return
            }
            
            self.isLoading = false
            self.apply(articles: articles)
        }
    }
    
    private func apply(articles: [HomepageFeedArticle]) {
        for subview in rowsStackView.arrangedSubviews {
            rowsStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        
        let visible = Array(articles.prefix(20))
        self.articles = visible
        
        guard !visible.isEmpty else {
            statusLabel.text = NSLocalizedString("No feed content available.", comment: "Homepage feed empty state")
            return
        }
        
        statusLabel.text = ""
        for article in visible {
            let row = HomepageFeedRowView(frame: .zero)
            row.configure(article: article)
            row.addTarget(self, action: #selector(handleRowTap(_:)), for: .touchUpInside)
            rowsStackView.addArrangedSubview(row)
        }
    }
    
    private func configureHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(rowsStackView)
        view.addSubview(statusLabel)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            
            rowsStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            rowsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rowsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: rowsStackView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    @objc private func handleRowTap(_ sender: HomepageFeedRowView) {
        guard let article = sender.article else {
            return
        }
        
        delegate?.homepageFeedPanelViewController(self, didSelect: article)
    }
}
