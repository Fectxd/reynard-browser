//
//  EdgeHomepagePalette.swift
//  Reynard
//
//  Flat light/dark palette for the Edge style homepage.
//

import UIKit

enum EdgeHomepagePalette {
    enum UX {
        static let panelCornerRadius: CGFloat = 16
        static let cardCornerRadius: CGFloat = 12
        static let chipCornerRadius: CGFloat = 11
        static let hairline: CGFloat = 0.5
        static let contentMaximumWidth: CGFloat = 800
        static let searchFieldHeight: CGFloat = 40
    }
    
    static let background = dynamic(
        light: UIColor(red: 0.961, green: 0.965, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.086, green: 0.086, blue: 0.094, alpha: 1)
    )
    
    static let surface = dynamic(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1),
        dark: UIColor(red: 0.137, green: 0.137, blue: 0.149, alpha: 1)
    )
    
    static let chip = dynamic(
        light: UIColor(red: 0.914, green: 0.922, blue: 0.941, alpha: 1),
        dark: UIColor(red: 0.196, green: 0.196, blue: 0.212, alpha: 1)
    )
    
    static let hairline = dynamic(
        light: UIColor(red: 0.886, green: 0.894, blue: 0.910, alpha: 1),
        dark: UIColor(red: 0.227, green: 0.227, blue: 0.243, alpha: 1)
    )
    
    static let accent = dynamic(
        light: UIColor(red: 0.059, green: 0.373, blue: 0.694, alpha: 1),
        dark: UIColor(red: 0.353, green: 0.643, blue: 1.000, alpha: 1)
    )
    
    static let primaryText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let tertiaryText = UIColor.tertiaryLabel
    
    static let dimmedBackdrop = dynamic(
        light: UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 0.28),
        dark: UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 0.48)
    )
    
    static func aqiColor(for aqi: Double) -> UIColor {
        switch aqi {
        case ..<51:
            return dynamic(
                light: UIColor(red: 0.129, green: 0.588, blue: 0.325, alpha: 1),
                dark: UIColor(red: 0.353, green: 0.788, blue: 0.502, alpha: 1)
            )
        case ..<101:
            return dynamic(
                light: UIColor(red: 0.706, green: 0.541, blue: 0.043, alpha: 1),
                dark: UIColor(red: 0.929, green: 0.784, blue: 0.298, alpha: 1)
            )
        case ..<151:
            return dynamic(
                light: UIColor(red: 0.816, green: 0.408, blue: 0.055, alpha: 1),
                dark: UIColor(red: 0.960, green: 0.573, blue: 0.243, alpha: 1)
            )
        case ..<201:
            return dynamic(
                light: UIColor(red: 0.796, green: 0.161, blue: 0.169, alpha: 1),
                dark: UIColor(red: 0.949, green: 0.341, blue: 0.341, alpha: 1)
            )
        default:
            return dynamic(
                light: UIColor(red: 0.533, green: 0.196, blue: 0.604, alpha: 1),
                dark: UIColor(red: 0.741, green: 0.427, blue: 0.812, alpha: 1)
            )
        }
    }
    
    static func aqiLevel(for aqi: Double) -> Int {
        switch aqi {
        case ..<51:
            return 1
        case ..<101:
            return 2
        case ..<151:
            return 3
        case ..<201:
            return 4
        case ..<301:
            return 5
        default:
            return 6
        }
    }
    
    static func scaledFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
    }
    
    private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        return UIColor { traits in
            return traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}
