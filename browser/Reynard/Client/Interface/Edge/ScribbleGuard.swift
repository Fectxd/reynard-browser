//
//  ScribbleGuard.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Tapping with an Apple Pencil (or a third-party pencil) crashed the app:
//  iPadOS starts Scribble (handwriting into text inputs) and its PencilKit
//  renderer crashes inside -[PKRendererVSyncController init] under Gecko's run
//  loop (see minh-ton/reynard-browser#100). The page view and the address bar
//  are both text inputs, so the crash could happen anywhere.
//
//  Scribble is switched off by attaching a UIScribbleInteraction whose delegate
//  refuses to begin to every text-input view when it enters a window. Pencil
//  taps, drawing on web pages, pressure and hover still go through as before;
//  only handwriting-to-text is unavailable.
//

import ObjectiveC
import UIKit

enum ScribbleGuard {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled, #available(iOS 14.0, *) else {
            return
        }
        isInstalled = true

        guard let original = class_getInstanceMethod(UIView.self, #selector(UIView.didMoveToWindow)),
              let replacement = class_getInstanceMethod(UIView.self, #selector(UIView.reynard_scribbleGuardDidMoveToWindow)) else {
            return
        }
        method_exchangeImplementations(original, replacement)
    }
}

@available(iOS 14.0, *)
private final class ScribbleBlocker: NSObject, UIScribbleInteractionDelegate {
    static let shared = ScribbleBlocker()

    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        return false
    }
}

extension UIView {
    @objc fileprivate func reynard_scribbleGuardDidMoveToWindow() {
        // Calls the original didMoveToWindow (implementations are exchanged).
        reynard_scribbleGuardDidMoveToWindow()

        guard #available(iOS 14.0, *),
              window != nil,
              self is UITextInput,
              !interactions.contains(where: { $0 is UIScribbleInteraction }) else {
            return
        }
        addInteraction(UIScribbleInteraction(delegate: ScribbleBlocker.shared))
    }
}
