//
//  ToolbarButtonMenus.swift
//  Reynard
//
//  Created by Minh Ton on 14/8/26.
//

import UIKit

final class ToolbarButtonMenus {
    enum NavigationDirection {
        case back
        case forward
    }
    
    private final class NavigationMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
        private let direction: NavigationDirection
        private let itemsProvider: (NavigationDirection) -> [NavigationHistoryStore.HistoryItem]
        private let onSelect: (NavigationDirection, Int) -> Void
        
        init(
            direction: NavigationDirection,
            itemsProvider: @escaping (NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
            onSelect: @escaping (NavigationDirection, Int) -> Void
        ) {
            self.direction = direction
            self.itemsProvider = itemsProvider
            self.onSelect = onSelect
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            let items = itemsProvider(direction)
            guard !items.isEmpty else {
                return nil
            }
            
            let actions = items.enumerated().reversed().map { index, item in
                makeAction(for: item, at: index)
            }
            let menu = UIMenu(title: "", children: actions)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                menu
            }
        }
        
        private func makeAction(
            for item: NavigationHistoryStore.HistoryItem,
            at index: Int
        ) -> UIAction {
            let url = displayURL(for: item.url)
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTitle = !title.isEmpty && title != item.url
            let actionTitle: String
            if #available(iOS 15.0, *) {
                actionTitle = hasTitle ? title : url
            } else {
                actionTitle = url
            }
            
            let action = UIAction(title: actionTitle) { [onSelect, direction] _ in
                onSelect(direction, index)
            }
            if #available(iOS 15.0, *) {
                action.subtitle = url
            }
            return action
        }
        
        private func displayURL(for value: String) -> String {
            guard let url = URL(string: value) else {
                return value
            }
            return URLUtils.displayString(for: url)
        }
    }
    
    private var navigationMenuDelegates: [NavigationMenuDelegate] = []
    
    func installNavigationMenus(
        on backButton: ToolbarButton,
        forwardButton: ToolbarButton,
        itemsProvider: @escaping (NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (NavigationDirection, Int) -> Void
    ) {
        installNavigationMenu(
            on: backButton,
            direction: .back,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
        installNavigationMenu(
            on: forwardButton,
            direction: .forward,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    private func installNavigationMenu(
        on button: ToolbarButton,
        direction: NavigationDirection,
        itemsProvider: @escaping (NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (NavigationDirection, Int) -> Void
    ) {
        let delegate = NavigationMenuDelegate(
            direction: direction,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
        button.addInteraction(UIContextMenuInteraction(delegate: delegate))
        navigationMenuDelegates.append(delegate)
    }
}
