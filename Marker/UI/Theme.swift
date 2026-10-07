import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum Palette {
    static let bg = Color(light: 0xffffff, dark: 0x000000)
    static let fg = Color(light: 0x111114, dark: 0xf5f5f7)
    static let fg2 = Color(light: 0x6e6e73, dark: 0xa1a1a6)
    static let fg3 = Color(light: 0xaeaeb2, dark: 0x636366)
    static let hair = Color(light: 0xdcdce0, dark: 0x2c2c2e)
    static let fill = Color(light: 0xececf0, dark: 0x2c2c2e)
    static let seg = Color(light: 0xffffff, dark: 0x48484a)
    static let acc = Color(light: 0x3939ff, dark: 0x7b7bff)
    static let accOn = Color(light: 0xffffff, dark: 0x0b0b1f)
    static let err = Color(light: 0xb02a37, dark: 0xf07a84)
    static var tint: Color { acc.opacity(0.1) }
}

enum ThemeChoice: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    var label: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Font {
    static let markerLargeTitle = Font.system(.largeTitle, weight: .bold)
    static let sectionLabel = Font.system(.footnote, weight: .semibold)
}
