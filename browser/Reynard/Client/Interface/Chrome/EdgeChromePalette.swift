//
//  EdgeChromePalette.swift
//  Reynard
//

import UIKit

/// Flat chrome colours sampled from the Edge reference screenshots (light and
/// dark). Kept as explicit values instead of semantic system colours so the
/// tab strip, the status-bar band and the address-bar row match the reference
/// pixel for pixel in both appearances.
enum EdgeChromePalette {
    /// Tab strip surface, also used for the status-bar band above it.
    static let chrome = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
        ? UIColor(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x14 / 255.0, alpha: 1)
        : UIColor(red: 0xDD / 255.0, green: 0xE0 / 255.0, blue: 0xE7 / 255.0, alpha: 1)
    }

    /// Address-bar row surface. The active tab uses the same colour so it can
    /// merge into the row below (the Edge "flush tab" look).
    static let surface = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
        ? UIColor(red: 0x34 / 255.0, green: 0x35 / 255.0, blue: 0x37 / 255.0, alpha: 1)
        : UIColor(red: 0xF5 / 255.0, green: 0xF6 / 255.0, blue: 0xFA / 255.0, alpha: 1)
    }

    /// Inactive tab chip sitting on the tab strip.
    static let inactiveTab = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
        ? UIColor(red: 0x1C / 255.0, green: 0x1D / 255.0, blue: 0x1E / 255.0, alpha: 1)
        : UIColor(red: 0xD9 / 255.0, green: 0xDC / 255.0, blue: 0xE1 / 255.0, alpha: 1)
    }

    /// Address-bar text field fill, slightly recessed against `surface`.
    static let field = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
        ? UIColor(red: 0x26 / 255.0, green: 0x27 / 255.0, blue: 0x29 / 255.0, alpha: 1)
        : UIColor(red: 0xE9 / 255.0, green: 0xEB / 255.0, blue: 0xF1 / 255.0, alpha: 1)
    }
}
