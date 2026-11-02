//
//  EdgeLibrarySidePanelController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  True right side-by-side Library panel for the wide (pad) layout. The web
//  content region is inset from the trailing edge (see BrowserViewController
//  contentTrailingConstraint) and this panel occupies the vacated strip on the
//  right. It hosts the existing standalone library sections (收藏夹 / 历史 /
//  下载) and lets the user switch among them inline, replacing the old modal
//  UITabBarController whose bottom 收藏/历史/下载/设置 tab bar is no longer used
//  on the wide layout. Each section keeps its own navigation stack so folder /
//  item drill-down (Bookmarks folders etc.) still works.
//

import UIKit

final class EdgeLibrarySidePanelController: UIViewController, UINavigationControllerDelegate {

    /// The sections that appear in the side panel (书签 / 历史 / 下载). Settings
    /// stays in the modal Settings screen and is intentionally excluded.
    static let panelSections: [LibrarySection] = [.bookmarks, .history, .downloads]

    /// The width (points) the panel occupies on the trailing edge.
    static let panelWidth: CGFloat = UX.panelWidth

    /// Invoked when the user taps the panel's close button.
    var onClose: (() -> Void)?

    private enum UX {
        static let panelWidth: CGFloat = 340
        static let headerHeight: CGFloat = 52
        static let segmentedHeight: CGFloat = 32
        static let segmentedInset: CGFloat = 12
        static let closeButtonWidth: CGFloat = 44
        static let fontSize: CGFloat = 15
    }

    private let sectionItemIdentifiers = EdgeLibrarySidePanelController.panelSections

    /// One UINavigationController per section so drilling into a section does
    /// not disturb another section's stack.
    private var navigationControllers: [LibrarySection: UINavigationController] = [:]
    private weak var activeNavigationController: UINavigationController?

    private let headerView = UIView()
    private let segmentedControl = UISegmentedControl()
    private let contentContainerView = UIView()

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: UX.panelWidth, height: 700)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureHeader()
        configureContent()
    }

    private func configureHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .systemBackground
        view.addSubview(headerView)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        sectionItemIdentifiers.forEach { section in
            segmentedControl.insertSegment(
                withTitle: section.panelTitle,
                at: segmentedControl.numberOfSegments,
                animated: false
            )
        }
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.setTitleTextAttributes(
            [.font: UIFont.systemFont(ofSize: UX.fontSize - 1, weight: .semibold)],
            for: .normal
        )
        segmentedControl.addTarget(
            self,
            action: #selector(segmentedControlDidChange),
            for: .valueChanged
        )
        headerView.addSubview(segmentedControl)

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: UX.headerHeight),

            segmentedControl.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: UX.segmentedInset),
            segmentedControl.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -UX.segmentedInset),
            segmentedControl.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            segmentedControl.heightAnchor.constraint(equalToConstant: UX.segmentedHeight),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: UX.closeButtonWidth),
            closeButton.heightAnchor.constraint(equalToConstant: UX.headerHeight),
        ])
    }

    private func configureContent() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainerView)
        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Section Switching

    func showSection(_ section: LibrarySection) {
        guard sectionItemIdentifiers.contains(section) else {
            return
        }

        if let index = sectionItemIdentifiers.firstIndex(of: section) {
            segmentedControl.selectedSegmentIndex = index
        }

        let navigationController = navigationController(for: section)
        guard activeNavigationController !== navigationController else {
            return
        }

        if let activeNavigationController {
            activeNavigationController.willMove(toParent: nil)
            activeNavigationController.view.removeFromSuperview()
            activeNavigationController.removeFromParent()
        }

        addChild(navigationController)
        navigationController.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(navigationController.view)
        NSLayoutConstraint.activate([
            navigationController.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            navigationController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            navigationController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            navigationController.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])
        navigationController.didMove(toParent: self)

        activeNavigationController = navigationController
    }

    private func navigationController(for section: LibrarySection) -> UINavigationController {
        if let existing = navigationControllers[section] {
            return existing
        }
        let rootViewController = makeSectionController(for: section)
        let navigationController = UINavigationController(rootViewController: rootViewController)
        // The panel's segmented header is the only "title" at the section level,
        // so the per-section nav bar starts hidden (removes the bookmarks "书签"
        // title and the blank band under history/downloads). The delegate shows
        // the bar only once the user drills into a folder (push) so the back
        // chevron remains available.
        navigationController.isNavigationBarHidden = true
        navigationController.delegate = self
        navigationControllers[section] = navigationController
        return navigationController
    }

    // MARK: - UINavigationControllerDelegate

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        // Root level (one view controller): keep the bar hidden. Any push (a
        // bookmarks folder) reveals it so the back button + title are visible.
        let isRoot = navigationController.viewControllers.count <= 1
        navigationController.setNavigationBarHidden(isRoot, animated: animated)
    }

    private func makeSectionController(for section: LibrarySection) -> UIViewController {
        switch section {
        case .bookmarks:
            return BookmarksViewController()
        case .history:
            return HistoryViewController()
        case .downloads:
            return DownloadsViewController()
        case .settings:
            // Never requested for the side panel; keep exhaustive switch.
            return SettingsViewController()
        }
    }

    // MARK: - Actions

    @objc private func segmentedControlDidChange() {
        let index = segmentedControl.selectedSegmentIndex
        guard sectionItemIdentifiers.indices.contains(index) else {
            return
        }
        showSection(sectionItemIdentifiers[index])
    }

    @objc private func closeTapped() {
        onClose?()
    }
}

private extension LibrarySection {
    /// Chinese labels used by the Edge UI panel (the stock LibrarySection.title
    /// is the localised English Bookmarks/History/Downloads).
    var panelTitle: String {
        switch self {
        case .bookmarks:
            return "收藏夹"
        case .history:
            return "历史记录"
        case .downloads:
            return "下载"
        case .settings:
            return "设置"
        }
    }
}
