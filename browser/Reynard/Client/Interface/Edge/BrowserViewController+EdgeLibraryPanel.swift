//
//  BrowserViewController+EdgeLibraryPanel.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Hosts the Edge right side-by-side Library panel on the wide (pad) layout.
//  While the panel is open the web content's trailing edge is pulled in by the
//  panel width (see BrowserViewController.setEdgeLibraryContentTrailingInset)
//  so the content shifts left and the panel sits side-by-side on the right.
//  The panel is only ever shown when the layout is pad; narrow/phone keeps the
//  classic full-screen modal library (presentLibrary). Opening a web page from
//  a bookmark / history row collapses the panel.
//

import UIKit

extension BrowserViewController {

    /// Presents the side-by-side library panel (pad only) or falls back to the
    /// classic full-screen modal (phone / narrow). If the panel is already open
    /// it just switches to the requested section.
    func presentEdgeLibraryPanel(section: LibrarySection, animated: Bool = true) {
        toolbarController.reset()
        browserChrome.dismissActionBar(animated: false)
        guard canHostEdgeLibraryPanel else {
            presentLibrary(initialSection: section)
            return
        }

        if let panel = edgeLibraryPanel {
            panel.showSection(section)
            return
        }

        let panel = EdgeLibrarySidePanelController()
        panel.onClose = { [weak self] in
            self?.dismissEdgeLibraryPanel(animated: true)
        }

        addChild(panel)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel.view)
        NSLayoutConstraint.activate([
            panel.view.topAnchor.constraint(equalTo: browserChrome.topToolbarBottomAnchor),
            panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.view.widthAnchor.constraint(equalToConstant: EdgeLibrarySidePanelController.panelWidth),
        ])
        panel.didMove(toParent: self)
        edgeLibraryPanel = panel

        panel.showSection(section)
        setEdgeLibraryContentTrailingInset(EdgeLibrarySidePanelController.panelWidth)
        // Appear in place without the fly-in / slide animation: apply the first
        // layout synchronously so the panel and content inset both pop into their
        // final geometry.
        view.layoutIfNeeded()
    }

    /// Dismisses the side-by-side library panel, restoring the content to full
    /// width. No-op when the panel is not open.
    func dismissEdgeLibraryPanel(animated: Bool = true) {
        guard let panel = edgeLibraryPanel else {
            return
        }
        let removePanel = {
            panel.willMove(toParent: nil)
            panel.view.removeFromSuperview()
            panel.removeFromParent()
        }
        if animated {
            setEdgeLibraryContentTrailingInset(0)
            UIView.animate(withDuration: BrowserViewController.layoutAnimationDuration, animations: {
                self.view.layoutIfNeeded()
            }, completion: { _ in
                removePanel()
            })
        } else {
            setEdgeLibraryContentTrailingInset(0)
            view.layoutIfNeeded()
            removePanel()
        }
        edgeLibraryPanel = nil
    }

    /// Whether this layout can host the side-by-side panel. Only the wide pad
    /// layout qualifies; fullscreen media and the tab overview are excluded.
    var canHostEdgeLibraryPanel: Bool {
        guard browserLayout.chromeMode == .pad,
              !isShowingFullscreenMedia,
              !tabOverview.isPresented else {
            return false
        }
        return true
    }

    /// Ensures the side panel matches the current layout. Called from layout
    /// changes (rotation, window resize) so an open panel on the wide layout
    /// stays put, and collapses itself when the layout stops being wide.
    func updateEdgeLibraryPanelForLayout() {
        guard edgeLibraryPanel != nil else {
            setEdgeLibraryContentTrailingInset(0)
            return
        }
        if canHostEdgeLibraryPanel {
            setEdgeLibraryContentTrailingInset(EdgeLibrarySidePanelController.panelWidth)
        } else {
            dismissEdgeLibraryPanel(animated: false)
        }
    }

    /// Called when a web page is opened from inside the panel (bookmarks /
    /// history rows). Collapses the panel so the content can fill the width.
    func edgeLibraryPanelDidOpenWebPage() {
        dismissEdgeLibraryPanel(animated: true)
    }
}

private extension BrowserViewController {
    static var layoutAnimationDuration: TimeInterval { return 0.22 }
}
