import SwiftUI
import PencilKit
import ZenNoteCore

struct DrawingSettings: Codable, Equatable {
    enum Input: String, Codable, CaseIterable {
        case stylus, compatible
        var title: String { self == .stylus ? "Stylus + finger navigation" : "Touch-style pen fallback" }
    }
    enum Tool: String, Codable, CaseIterable { case pen, eraser, highlighter }
    enum Ink: String, Codable, CaseIterable {
        case black, blue, red, green, yellow
        @MainActor var color: UIColor {
            switch self {
            case .black: return .black
            case .blue: return .systemBlue
            case .red: return .systemRed
            case .green: return .systemGreen
            case .yellow: return .systemYellow
            }
        }
    }

    var input: Input = .stylus
    var tool: Tool = .pen
    var ink: Ink = .black
    var markerInk: Ink = .yellow
    var activeInk: Ink {
        get { tool == .highlighter ? markerInk : ink }
        set { if tool == .highlighter { markerInk = newValue } else { ink = newValue } }
    }
    var width: Double = 2.5
    var paper: PaperStyle = .grid
    var divider: Double = 0.5

    @MainActor var pencilTool: PKTool {
        switch tool {
        case .pen: return PKInkingTool(.pen, color: ink.color, width: CGFloat(width))
        case .highlighter: return PKInkingTool(.marker, color: markerInk.color.withAlphaComponent(0.5), width: CGFloat(max(10, width * 5)))
        case .eraser: return PKEraserTool(.bitmap)
        }
    }
}
