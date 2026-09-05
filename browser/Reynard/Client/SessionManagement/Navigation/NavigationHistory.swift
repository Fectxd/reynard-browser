//
//  NavigationHistory.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import Foundation
import GeckoView
import UIKit

final class NavigationHistory {
    private let store: NavigationHistoryStore
    
    init(store: NavigationHistoryStore = .shared) {
        self.store = store
    }
    
    func restoreState(for tabID: UUID) -> NavigationAvailability {
        store.restoreState(for: tabID)
        return availability(for: tabID, sessionState: .unavailable)
    }
    
    func availability(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationAvailability {
        let state = store.currentState(for: tabID)
        if state.usesStoredHistory {
            return NavigationAvailability(
                canGoBack: state.canGoBack,
                canGoForward: state.canGoForward
            )
        }
        return NavigationAvailability(
            canGoBack: sessionState.canGoBack,
            canGoForward: sessionState.canGoForward
        )
    }
    
    func snapshot(for tabID: UUID) -> NavigationHistoryStore.Snapshot {
        store.currentSnapshot(for: tabID)
    }
    
    func usesStoredHistory(for tabID: UUID) -> Bool {
        return store.currentState(for: tabID).usesStoredHistory
    }
    
    func record(
        to url: String,
        title: String,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationAvailability {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              trimmedURL.lowercased() != "about:blank" else {
            return availability(for: tabID, sessionState: sessionState)
        }
        store.recordNavigation(to: trimmedURL, title: title, for: tabID)
        return availability(for: tabID, sessionState: sessionState)
    }
    
    func synchronizeNavigationHistory(
        with sessionState: GeckoSessionState,
        for tabID: UUID
    ) -> Int? {
        return store.synchronizeNavigationHistory(with: sessionState, for: tabID)
    }
    
    func goBack(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        let state = store.currentState(for: tabID)
        if !state.usesStoredHistory {
            guard sessionState.canGoBack else {
                return nil
            }
            return NavigationTransition(
                action: .session,
                availability: availability(for: tabID, sessionState: sessionState)
            )
        }
        
        guard let url = store.goBack(to: 0, for: tabID) else {
            return nil
        }
        store.setUsesPersistedHistory(true, for: tabID)
        return NavigationTransition(
            action: .load(url),
            availability: availability(for: tabID, sessionState: sessionState)
        )
    }
    
    func goBack(
        to index: Int,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        guard store.currentState(for: tabID).usesStoredHistory else {
            return nil
        }
        guard let url = store.goBack(to: index, for: tabID) else {
            return nil
        }
        store.setUsesPersistedHistory(true, for: tabID)
        return NavigationTransition(
            action: .load(url),
            availability: availability(for: tabID, sessionState: sessionState)
        )
    }
    
    func goForward(
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        let state = store.currentState(for: tabID)
        if !state.usesStoredHistory {
            guard sessionState.canGoForward else {
                return nil
            }
            return NavigationTransition(
                action: .session,
                availability: availability(for: tabID, sessionState: sessionState)
            )
        }
        
        guard let url = store.goForward(to: 0, for: tabID) else {
            return nil
        }
        store.setUsesPersistedHistory(true, for: tabID)
        return NavigationTransition(
            action: .load(url),
            availability: availability(for: tabID, sessionState: sessionState)
        )
    }
    
    func goForward(
        to index: Int,
        for tabID: UUID,
        sessionState: SessionNavigationAvailability
    ) -> NavigationTransition? {
        guard store.currentState(for: tabID).usesStoredHistory else {
            return nil
        }
        guard let url = store.goForward(to: index, for: tabID) else {
            return nil
        }
        store.setUsesPersistedHistory(true, for: tabID)
        return NavigationTransition(
            action: .load(url),
            availability: availability(for: tabID, sessionState: sessionState)
        )
    }
    
    func useStoredHistory(for tabID: UUID) -> NavigationAvailability {
        store.setUsesPersistedHistory(true, for: tabID)
        return availability(for: tabID, sessionState: .unavailable)
    }
    
    func updateCurrentHistoryTitle(_ title: String, for tabID: UUID, matching url: String) {
        store.updateCurrentHistoryTitle(title, for: tabID, matching: url)
    }
    
    func updateCurrentHistoryThumbnail(
        _ image: UIImage?,
        for tabID: UUID,
        matching url: String,
        completion: @escaping () -> Void
    ) {
        store.updateCurrentHistoryThumbnail(image, for: tabID, matching: url, completion: completion)
    }
    
    func previewImages(for tabID: UUID) -> NavigationPreviewImages {
        return store.currentPreviewImages(for: tabID)
    }
    
    func flushPendingWrites() {
        store.flushPendingWrites()
    }
    
    func invalidateThumbnails() {
        store.invalidateThumbnails()
    }
    
    func removeHistory(for tabID: UUID) {
        store.removeNavigationHistory(for: tabID)
    }
}
