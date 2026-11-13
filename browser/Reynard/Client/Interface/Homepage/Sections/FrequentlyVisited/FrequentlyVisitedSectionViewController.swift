//
//  FrequentlyVisitedSectionViewController.swift
//  Reynard
//
//  Created by Minh Ton on 24/6/26.
//

import UIKit

final class FrequentlyVisitedSectionViewController: UIViewController {
    private enum UX {
        static let horizontalInset: CGFloat = 2
        static let titleTopSpacing: CGFloat = 16
        static let titleBottomSpacing: CGFloat = 14
        static let titleFontSize: CGFloat = 22
        static let cardWidth: CGFloat = 150
        static let cardHeight: CGFloat = 120
        static let cardSpacing: CGFloat = 16
        static let shadowMargin: CGFloat = 20
    }
    
    private enum MetadataState {
        case loading(Task<Void, Never>)
        case loaded(SiteMetadataSnapshot)
        
        func cancelLoad() {
            guard case let .loading(task) = self else {
                return
            }
            
            task.cancel()
        }
    }
    
    private static let titleFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
        for: .systemFont(ofSize: UX.titleFontSize, weight: .bold)
    )
    
    weak var delegate: HomepageSectionDelegate?
    
    private let historyStore: HistoryStore
    private let metadataStore: SiteMetadataStore
    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var sites: [HistorySiteSnapshot] = []
    private var metadataStatesByURL: [URL: MetadataState] = [:]
    private var cardViews: [FrequentlyVisitedSiteCardView] = []
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = FrequentlyVisitedSectionViewController.titleFont
        label.textColor = .label
        label.text = NSLocalizedString("Frequently Visited", comment: "")
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        return scrollView
    }()
    
    private let cardStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = UX.cardSpacing
        return stackView
    }()
    
    // MARK: - Lifecycle
    
    init(historyStore: HistoryStore = .shared, metadataStore: SiteMetadataStore = .shared) {
        self.historyStore = historyStore
        self.metadataStore = metadataStore
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancelMetadataLoads()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        observeChanges()
        reloadSites()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    /// Edge start page only: cards shrink with the available width (down to
    /// 60%) instead of keeping a fixed 150pt; titles keep their font size.
    /// Off by default so upstream's homepage is unchanged.
    var scalesCardsToWidth = false {
        didSet {
            guard oldValue != scalesCardsToWidth, isViewLoaded else { return }
            view.setNeedsLayout()
        }
    }
    private var cardScale: CGFloat = 1
    private var cardSizeConstraints: [NSLayoutConstraint] = []
    private lazy var scrollViewHeightConstraint = scrollView.heightAnchor.constraint(
        equalToConstant: UX.cardHeight + (UX.shadowMargin * 2)
    )
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCardScale()
    }
    
    private func updateCardScale() {
        // ~4 cards across at the full iPad page width (720pt minus margins).
        let referenceWidth: CGFloat = 664
        let width = view.bounds.width
        let scale = scalesCardsToWidth && width > 0 ? min(1, max(0.6, width / referenceWidth)) : 1
        guard abs(scale - cardScale) > 0.005 else {
            return
        }
        cardScale = scale
        applyCardSize()
    }
    
    private var cardSize: CGSize {
        let width = (UX.cardWidth * cardScale).rounded()
        // Only the 16:9 preview shrinks; the title row keeps its height.
        let previewLoss = (UX.cardWidth - width) * 9.0 / 16.0
        return CGSize(width: width, height: (UX.cardHeight - previewLoss).rounded())
    }
    
    private func applyCardSize() {
        NSLayoutConstraint.deactivate(cardSizeConstraints)
        let size = cardSize
        cardSizeConstraints = cardViews.flatMap { cardView in
            [
                cardView.widthAnchor.constraint(equalToConstant: size.width),
                cardView.heightAnchor.constraint(equalToConstant: size.height),
            ]
        }
        NSLayoutConstraint.activate(cardSizeConstraints)
        cardStackView.spacing = (UX.cardSpacing * cardScale).rounded()
        scrollViewHeightConstraint.constant = size.height + (UX.shadowMargin * 2)
    }
    
    /// Scrolls the site row back to its first (left-most) card.
    func scrollToStart(animated: Bool) {
        guard isViewLoaded else {
            return
        }
        let start = CGPoint(x: -scrollView.adjustedContentInset.left, y: scrollView.contentOffset.y)
        scrollView.setContentOffset(start, animated: animated)
    }
    
    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }
        
        self.contentMode = contentMode
        titleLabel.textColor = HomepageWallpaper.foregroundColor(for: contentMode)
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        view.backgroundColor = .clear
        titleLabel.textColor = HomepageWallpaper.foregroundColor(for: contentMode)
    }
    
    private func configureHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(scrollView)
        scrollView.addSubview(cardStackView)
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: UX.titleTopSpacing),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -UX.horizontalInset),
            
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: UX.titleBottomSpacing - UX.shadowMargin),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -UX.shadowMargin),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: UX.shadowMargin),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollViewHeightConstraint,
            
            cardStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: UX.shadowMargin),
            cardStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -UX.shadowMargin),
            cardStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: UX.shadowMargin),
            cardStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -UX.shadowMargin),
            cardStackView.heightAnchor.constraint(equalToConstant: UX.cardHeight),
        ])
    }
    
    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidChange),
            name: .historyStoreDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(homepageSettingsDidChange),
            name: .homepageSettingsDidChange,
            object: nil
        )
    }
    
    // MARK: - History
    
    func site(for cardView: FrequentlyVisitedSiteCardView) -> HistorySiteSnapshot? {
        guard sites.indices.contains(cardView.tag) else {
            return nil
        }
        
        return sites[cardView.tag]
    }
    
    private func reloadSites() {
        sites = historyStore.frequentSites(
            limit: Prefs.HomepageSettings.frequentlyVisitedSiteCount,
            minVisitCount: 3
        ).items
        let retainedURLs = Set(sites.map(\.url))
        metadataStatesByURL = metadataStatesByURL.filter { url, state in
            if retainedURLs.contains(url) {
                return true
            }
            
            state.cancelLoad()
            return false
        }
        
        metadataStore.prune(keeping: sites.map(\.url))
        reloadCardViews()
        view.isHidden = sites.isEmpty
    }
    
    @objc private func historyDidChange() {
        reloadSites()
    }
    
    @objc private func homepageSettingsDidChange() {
        reloadSites()
    }
    
    // MARK: - Metadata
    
    private func metadata(for site: HistorySiteSnapshot) -> SiteMetadataSnapshot? {
        if case let .loaded(metadata) = metadataStatesByURL[site.url] {
            return metadata
        }
        
        if let cachedMetadata = metadataStore.cachedMetadata(for: site.url) {
            metadataStatesByURL[site.url] = .loaded(cachedMetadata)
            return cachedMetadata
        }
        
        loadMetadata(for: site.url)
        return nil
    }
    
    private func loadMetadata(for url: URL) {
        guard metadataStatesByURL[url] == nil else {
            return
        }
        
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            
            let metadata = await self.metadataStore.metadata(for: url)
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                guard let metadata,
                      self.sites.contains(where: { $0.url == url }) else {
                    self.metadataStatesByURL[url] = nil
                    return
                }
                
                self.metadataStatesByURL[url] = .loaded(metadata)
                if let index = self.sites.firstIndex(where: { $0.url == url }) {
                    self.cardViews[index].configure(site: self.sites[index], metadata: metadata)
                }
            }
        }
        
        metadataStatesByURL[url] = .loading(task)
    }
    
    private func cancelMetadataLoads() {
        metadataStatesByURL.values.forEach { $0.cancelLoad() }
    }
    
    // MARK: - Layout
    
    private func reloadCardViews() {
        for cardView in cardViews {
            cardView.removeFromSuperview()
        }
        
        cardViews = sites.enumerated().map { index, site in
            let cardView = FrequentlyVisitedSiteCardView()
            cardView.translatesAutoresizingMaskIntoConstraints = false
            cardView.tag = index
            cardView.configure(site: site, metadata: metadata(for: site))
            cardView.addTarget(self, action: #selector(handleCardTap(_:)), for: .touchUpInside)
            cardView.addInteraction(UIContextMenuInteraction(delegate: self))
            cardStackView.addArrangedSubview(cardView)
            return cardView
        }
        applyCardSize()
    }
    
    // MARK: - Actions
    
    @objc private func handleCardTap(_ sender: FrequentlyVisitedSiteCardView) {
        guard sites.indices.contains(sender.tag) else {
            return
        }
        
        delegate?.homepageSection(self, didRequestOpenURL: sites[sender.tag].url, disposition: .currentTab)
    }
}
