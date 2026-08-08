//
//  ToolbarController.swift
//  Reynard
//
//  Created by Minh Ton on 4/8/26.
//

import UIKit

final class ToolbarController {
    private enum UX {
        static let toolbarScrollFactor: CGFloat = 0.5
        static let snapDelay: TimeInterval = 0.1
        static let snapDuration: TimeInterval = 0.15
    }
    
    private unowned let browserChrome: BrowserChrome
    private unowned let tabBar: TabBar
    private unowned let contentView: ContentView
    private unowned let rootView: UIView
    
    private var chromeMode: BrowserChromeMode = .phone
    private var toolbarOffset: CGFloat = 0
    private var maxToolbarOffset: CGFloat = 0
    private var maxTopToolbarOffset: CGFloat = 0
    private var snapOrigin: CGFloat = 0
    private var snapStartTime: CFTimeInterval = 0
    private var pendingSnap: DispatchWorkItem?
    private var snapDisplayLink: CADisplayLink?
    
    // MARK: - Lifecycle
    
    init(
        browserChrome: BrowserChrome,
        tabBar: TabBar,
        contentView: ContentView,
        rootView: UIView
    ) {
        self.browserChrome = browserChrome
        self.tabBar = tabBar
        self.contentView = contentView
        self.rootView = rootView
        contentView.onVerticalScroll = { [weak self] scrollDelta in
            self?.handleScroll(delta: scrollDelta)
        }
    }
    
    deinit {
        cancelSnap()
    }
    
    // MARK: - Layout
    
    func updateLayout(chromeMode: BrowserChromeMode, isToolbarEnabled: Bool) {
        let offsetLimits = toolbarOffsetLimits(for: chromeMode)
        let maxToolbarOffset = isToolbarEnabled ? offsetLimits.total : 0
        let maxTopToolbarOffset = isToolbarEnabled ? offsetLimits.top : 0
        if self.chromeMode != chromeMode
            || abs(maxToolbarOffset - self.maxToolbarOffset) > 0.5
            || abs(maxTopToolbarOffset - self.maxTopToolbarOffset) > 0.5 {
            resetToolbar()
            self.chromeMode = chromeMode
            self.maxToolbarOffset = maxToolbarOffset
            self.maxTopToolbarOffset = maxTopToolbarOffset
        }
        contentView.setToolbarLimits(
            maxHeight: maxToolbarOffset,
            topOffset: maxTopToolbarOffset
        )
    }
    
    private func toolbarOffsetLimits(
        for chromeMode: BrowserChromeMode
    ) -> (total: CGFloat, top: CGFloat) {
        let topToolbarHeight = browserChrome.topToolbarTransitionFrame(in: rootView).height
        let bottomToolbarHeight = browserChrome.bottomToolbarTransitionFrame(in: rootView).height
        switch chromeMode {
        case .phone:
            return (bottomToolbarHeight, 0)
        case .compact:
            let topContentHeight = max(0, topToolbarHeight - rootView.safeAreaInsets.top)
            return (topContentHeight + bottomToolbarHeight, topContentHeight)
        case .pad:
            let maxOffset = topToolbarHeight + (tabBar.visibility == .visible ? tabBar.bounds.height : 0)
            return (maxOffset, maxOffset)
        }
    }
    
    private func setToolbarOffset(_ requestedOffset: CGFloat) {
        let clampedToolbarOffset = min(max(0, requestedOffset), maxToolbarOffset)
        guard clampedToolbarOffset != toolbarOffset else {
            return
        }
        toolbarOffset = clampedToolbarOffset
        let topToolbarHeight = browserChrome.topToolbarTransitionFrame(in: rootView).height
        let bottomToolbarHeight = browserChrome.bottomToolbarTransitionFrame(in: rootView).height
        let topToolbarOffset: CGFloat
        let topContentOffset: CGFloat
        let topToolbarContentAlpha: CGFloat
        let bottomToolbarOffset: CGFloat
        let bottomToolbarContentAlpha: CGFloat
        let tabBarOffset: CGFloat
        switch chromeMode {
        case .phone:
            topToolbarOffset = 0
            topContentOffset = 0
            topToolbarContentAlpha = 1
            bottomToolbarOffset = toolbarOffset
            bottomToolbarContentAlpha = 1 - (bottomToolbarOffset / max(bottomToolbarHeight, 1))
            tabBarOffset = 0
        case .compact:
            let progress = toolbarOffset / max(maxToolbarOffset, 1)
            topToolbarOffset = min(topToolbarHeight * progress, maxTopToolbarOffset)
            topContentOffset = topToolbarOffset
            topToolbarContentAlpha = 1 - (topToolbarOffset / max(maxTopToolbarOffset, 1))
            bottomToolbarOffset = bottomToolbarHeight * progress
            bottomToolbarContentAlpha = 1 - (bottomToolbarOffset / max(bottomToolbarHeight, 1))
            tabBarOffset = 0
        case .pad:
            topToolbarOffset = toolbarOffset
            topContentOffset = toolbarOffset
            topToolbarContentAlpha = 1
            bottomToolbarOffset = 0
            bottomToolbarContentAlpha = 1
            tabBarOffset = toolbarOffset
        }
        browserChrome.setToolbarTransition(
            topOffset: -topToolbarOffset,
            bottomOffset: bottomToolbarOffset,
            topContentAlpha: topToolbarContentAlpha,
            bottomContentAlpha: bottomToolbarContentAlpha
        )
        tabBar.transform = CGAffineTransform(translationX: 0, y: -tabBarOffset)
        contentView.applyToolbarOffsets(
            top: topContentOffset,
            bottom: topToolbarOffset + bottomToolbarOffset
        )
    }
    
    // MARK: - Scroll Handling
    
    private func handleScroll(delta: CGFloat) {
        guard maxToolbarOffset > 0 else {
            return
        }
        cancelSnap()
        setToolbarOffset(toolbarOffset + delta * UX.toolbarScrollFactor)
        scheduleSnap()
    }
    
    // MARK: - Snapping
    
    private func scheduleSnap() {
        let snap = DispatchWorkItem { [weak self] in
            self?.beginSnap()
        }
        pendingSnap = snap
        DispatchQueue.main.asyncAfter(deadline: .now() + UX.snapDelay, execute: snap)
    }
    
    private func beginSnap() {
        pendingSnap = nil
        snapOrigin = toolbarOffset
        let snapTarget = snapOrigin < maxToolbarOffset / 2 ? 0 : maxToolbarOffset
        guard snapOrigin != snapTarget else {
            return
        }
        snapStartTime = CACurrentMediaTime()
        let snapDisplayLink = CADisplayLink(target: self, selector: #selector(updateSnap))
        snapDisplayLink.add(to: .main, forMode: .common)
        self.snapDisplayLink = snapDisplayLink
    }
    
    @objc private func updateSnap() {
        let elapsed = CACurrentMediaTime() - snapStartTime
        let progress = min(CGFloat(elapsed / UX.snapDuration), 1)
        let easedProgress = 1 - pow(1 - progress, 2)
        let snapTarget = snapOrigin < maxToolbarOffset / 2 ? 0 : maxToolbarOffset
        let requestedOffset = snapOrigin + (snapTarget - snapOrigin) * easedProgress
        setToolbarOffset(requestedOffset)
        if progress == 1 {
            snapDisplayLink?.invalidate()
            snapDisplayLink = nil
        }
    }
    
    private func cancelSnap() {
        pendingSnap?.cancel()
        pendingSnap = nil
        snapDisplayLink?.invalidate()
        snapDisplayLink = nil
    }
    
    // MARK: - Reset
    
    private func resetToolbar() {
        cancelSnap()
        toolbarOffset = 0
        browserChrome.setToolbarTransition(
            topOffset: 0,
            bottomOffset: 0,
            topContentAlpha: 1,
            bottomContentAlpha: 1
        )
        tabBar.transform = .identity
        contentView.applyToolbarOffsets(top: 0, bottom: 0)
    }
}
