import SwiftUI
import PencilKit
import ZenNoteCore

struct DrawingSettings: Codable, Equatable {
    enum Input: String, Codable, CaseIterable {
        case stylus, compatible
        var title: String { self == .stylus ? "Stylus + finger navigation" : "Touch-style pen fallback" }
    }
    enum Tool: String, Codable, CaseIterable { case pen, eraser, highlighter }
    enum Layout: String, Codable, CaseIterable {
        case split, textbook, notes
        var title: String {
            switch self { case .split: return "Split view"; case .textbook: return "Textbook fullscreen"; case .notes: return "Notes fullscreen" }
        }
        var symbol: String {
            switch self { case .split: return "rectangle.split.2x1"; case .textbook: return "book"; case .notes: return "pencil.and.outline" }
        }
    }
    enum Toolbar: String, Codable, CaseIterable {
        case docked, autoHide
        var title: String { self == .docked ? "Top-docked" : "Auto-hide" }
    }
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
    var layout: Layout = .split
    var zenToolbar: Toolbar = .docked

    init() {}

    private enum CodingKeys: String, CodingKey {
        case input, tool, ink, markerInk, width, paper, divider, layout, zenToolbar
    }

    // Added preferences must not make an existing v1 library undecodable.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        input = try values.decodeIfPresent(Input.self, forKey: .input) ?? .stylus
        tool = try values.decodeIfPresent(Tool.self, forKey: .tool) ?? .pen
        ink = try values.decodeIfPresent(Ink.self, forKey: .ink) ?? .black
        markerInk = try values.decodeIfPresent(Ink.self, forKey: .markerInk) ?? .yellow
        width = try values.decodeIfPresent(Double.self, forKey: .width) ?? 2.5
        paper = try values.decodeIfPresent(PaperStyle.self, forKey: .paper) ?? .grid
        divider = try values.decodeIfPresent(Double.self, forKey: .divider) ?? 0.5
        layout = try values.decodeIfPresent(Layout.self, forKey: .layout) ?? .split
        zenToolbar = try values.decodeIfPresent(Toolbar.self, forKey: .zenToolbar) ?? .docked
        width = min(8, max(1, width.isFinite ? width : 2.5))
        divider = min(0.72, max(0.28, divider.isFinite ? divider : 0.5))
    }

    @MainActor var pencilTool: PKTool {
        switch tool {
        case .pen: return PKInkingTool(.pen, color: ink.color, width: CGFloat(width))
        case .highlighter: return PKInkingTool(.marker, color: markerInk.color.withAlphaComponent(0.5), width: CGFloat(max(10, width * 5)))
        case .eraser: return PKEraserTool(.bitmap)
        }
    }
}
