//
//  SceneDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var browserWindow: BrowserWindow?
    
    /// Process-level bookkeeping: the first scene connected in this process is
    /// the primary window and restores the shared tab set. Any subsequent scene
    /// (⌘N, or an extra Stage Manager window) starts at the homepage and uses an
    /// isolated ephemeral tab store, so it can never clobber the primary
    /// window's saved tabs. The flag is intentionally never reset: a window
    /// opened after the primary one was closed must still not overwrite the
    /// saved tab list.
    private static var hasConnectedScene = false
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let draggedTabID = connectionOptions.userActivities.lazy.compactMap(\.draggedTabID).first
        let browserWindow = BrowserWindowManager.shared.connect(windowScene, draggedTabID: draggedTabID)
        window = browserWindow.window
        self.browserWindow = browserWindow
        
        handleIncomingURLContexts(connectionOptions.urlContexts)
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleIncomingURLContexts(URLContexts)
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        guard let browserWindow else {
            return
        }
        
        BrowserWindowManager.shared.disconnect(browserWindow)
        self.browserWindow = nil
        window = nil
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let browserWindow else {
            return
        }
        
        BrowserWindowManager.shared.activate(browserWindow)
        browserWindow.sceneDidBecomeActive()
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        browserWindow?.sceneWillResignActive()
    }
    
    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        browserWindow?.interfaceOrientationDidChange(to: windowScene.interfaceOrientation)
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        browserWindow?.setForeground(true)
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        browserWindow?.setForeground(false)
    }
    
    private func handleIncomingURLContexts(_ urlContexts: Set<UIOpenURLContext>) {
        guard let incomingURL = urlContexts.first?.url,
              let resolvedURL = resolvedBrowserURL(from: incomingURL) else {
            return
        }
        
        browserWindow?.openExternalURL(resolvedURL)
    }
    
    private func resolvedBrowserURL(from incomingURL: URL) -> URL? {
        guard let scheme = incomingURL.scheme?.lowercased() else {
            return nil
        }
        
        if scheme == "http" || scheme == "https" {
            return incomingURL
        }
        
        guard scheme == "reynard",
              let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
              let encodedURL = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return nil
        }
        
        return URL(string: encodedURL)
    }
}
