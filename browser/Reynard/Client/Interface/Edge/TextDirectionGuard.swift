//
//  TextDirectionGuard.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  iPadOS calls -setBaseWritingDirection:forRange: on the focused text input
//  (keyboard/language switches, some hardware-keyboard events). Gecko's page
//  view (ChildView) turns that into EditorBase::SwitchTextDirectionTo, which
//  fires a beforeinput event of type "formatSetBlockTextDirection" with data
//  "ltr". Web editors that insert `event.data` for unknown input types (Feishu
//  Sheets/Docs) then write "ltr" / "ltrltr" into the cell.
//
//  Safari does not change the page's text direction here either, so the call
//  is ignored for Gecko's view. Pages keep their own dir handling; typing RTL
//  text still works through the normal text input path.
//

import ObjectiveC
import UIKit

enum TextDirectionGuard {
    private static var isInstalled = false

    /// Installs the override on Gecko's view class the first time an instance
    /// of it shows up (the Gecko framework may be loaded after launch).
    static func installIfNeeded(for view: UIView) {
        guard !isInstalled else {
            return
        }
        let viewClass: AnyClass = type(of: view)
        guard NSStringFromClass(viewClass) == "ChildView" else {
            return
        }
        isInstalled = true

        let selector = NSSelectorFromString("setBaseWritingDirection:forRange:")
        guard let method = class_getInstanceMethod(viewClass, selector) else {
            return
        }
        let ignore: @convention(block) (AnyObject, Int, AnyObject?) -> Void = { _, _, _ in }
        method_setImplementation(method, imp_implementationWithBlock(ignore))
    }
}
