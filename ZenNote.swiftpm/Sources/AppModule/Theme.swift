import SwiftUI
import UIKit

/// A single matte theme. These UI colors never replace saved PencilKit ink or
/// modify the source PDF's page/illustration colors.
@MainActor
enum Theme {
    static let backgroundUI = color(0xADA28E)
    static let controlsUI = color(0xD5C9B2)
    static let paperUI = color(0xF3E7CC)
    static let gridUI = color(0xBBAE90)
    static let textUI = color(0x40392F)
    static let accentUI = color(0x596344)

    static let background = Color(uiColor: backgroundUI)
    static let controls = Color(uiColor: controlsUI)
    static let paper = Color(uiColor: paperUI)
    static let grid = Color(uiColor: gridUI)
    static let text = Color(uiColor: textUI)
    static let accent = Color(uiColor: accentUI)

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
