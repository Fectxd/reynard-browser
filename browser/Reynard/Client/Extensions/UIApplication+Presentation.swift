//
//  UIApplication+Presentation.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

extension UIApplication {
    var isTwoThirdSplitScreenOrSmaller: Bool {
        guard
            let windowScene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return false
        }
        
        return isTwoThirdSplitScreenOrSmaller(forWindowWidth: window.bounds.width, screen: window.screen)
    }
    
    var isOneThirdSplitScreenOrSmaller: Bool {
        guard
            let windowScene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return false
        }
        
        return isOneThirdSplitScreenOrSmaller(forWindowWidth: window.bounds.width, screen: window.screen)
    }
    
    var isHalfSplitScreenOrSmaller: Bool {
        guard
            let windowScene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return false
        }
        
        return isHalfSplitScreenOrSmaller(forWindowWidth: window.bounds.width, screen: window.screen)
    }
    
    func isTwoThirdSplitScreenOrSmaller(forWindowWidth windowWidth: CGFloat, screen: UIScreen) -> Bool {
        let screenWidth = max(screen.bounds.width, screen.bounds.height)
        return windowWidth <= (3.0 / 4.0) * screenWidth + 0.5
    }
    
    func isOneThirdSplitScreenOrSmaller(forWindowWidth windowWidth: CGFloat, screen: UIScreen) -> Bool {
        let screenWidth = max(screen.bounds.width, screen.bounds.height)
        return windowWidth <= (2.0 / 5.0) * screenWidth + 0.5
    }
    
    func isHalfSplitScreenOrSmaller(forWindowWidth windowWidth: CGFloat, screen: UIScreen) -> Bool {
        let screenWidth = max(screen.bounds.width, screen.bounds.height)
        return windowWidth <= (3.0 / 5.0) * screenWidth + 0.5
    }
    
    func topViewController() -> UIViewController? {
        let rootViewController = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        
        guard let rootViewController else {
            return nil
        }
        
        return topViewController(from: rootViewController)
    }
    
    /// The top-most view controller of the scene that owns `view`, so a prompt
    /// originating from one window is never presented over another window.
    /// Falls back to the globally frontmost window when `view` is not in a
    /// window (yet).
    func topViewController(containing view: UIView?) -> UIViewController? {
        guard let window = view?.window else {
            return topViewController()
        }
        
        return topViewController(for: window)
    }
    
    /// The top-most view controller of `window`. Falls back to the globally
    /// frontmost window when `window` is nil.
    func topViewController(for window: UIWindow?) -> UIViewController? {
        guard let rootViewController = window?.rootViewController else {
            return topViewController()
        }
        
        return topViewController(from: rootViewController)
    }
    
    /// The top-most view controller of `windowScene` (its key window, or the
    /// first window when none is key). Falls back to the globally frontmost
    /// window when `windowScene` is nil.
    func topViewController(in windowScene: UIWindowScene?) -> UIViewController? {
        guard let windowScene else {
            return topViewController()
        }
        
        let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
        return topViewController(for: window)
    }
    
    func topViewController(from rootViewController: UIViewController) -> UIViewController {
        var controller = rootViewController
        while let presentedController = controller.presentedViewController {
            controller = presentedController
        }
        return controller
    }
}
