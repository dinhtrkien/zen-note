import Foundation

public enum PaperStyle: String, Codable, CaseIterable, Sendable {
    case blank, grid
}

public struct NoteSheet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var paper: PaperStyle

    public init(id: UUID = UUID(), paper: PaperStyle = .grid) {
        self.id = id
        self.paper = paper
    }
}

public struct PageNotes: Codable, Equatable, Sendable {
    public var sheets: [NoteSheet]
    public var selectedSheetID: UUID?

    public init(sheets: [NoteSheet] = [], selectedSheetID: UUID? = nil) {
        self.sheets = sheets
        self.selectedSheetID = selectedSheetID
    }

    public var selectedSheet: NoteSheet? {
        sheets.first(where: { $0.id == selectedSheetID }) ?? sheets.first
    }
}

public struct ReadingPosition: Codable, Equatable, Sendable {
    public var pageIndex: Int
    // Coordinates relative to the PDF crop box; PDF y increases upward.
    public var x: Double
    public var y: Double
    public var zoom: Double

    public init(pageIndex: Int = 0, x: Double = 0.5, y: Double = 0.5, zoom: Double = 1) {
        self.pageIndex = max(0, pageIndex)
        self.x = Self.unit(x)
        self.y = Self.unit(y)
        self.zoom = zoom.isFinite ? min(6, max(1, zoom)) : 1
    }

    public func clamped(pageCount: Int) -> ReadingPosition {
        ReadingPosition(pageIndex: min(max(0, pageIndex), max(0, pageCount - 1)), x: x, y: y, zoom: zoom)
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }
}

public struct BookState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var readingPosition: ReadingPosition
    public private(set) var pages: [String: PageNotes]

    public init(readingPosition: ReadingPosition = ReadingPosition(), pages: [String: PageNotes] = [:]) {
        self.readingPosition = readingPosition
        self.pages = pages
    }

    public func notes(for pageIndex: Int) -> PageNotes {
        pages[String(pageIndex)] ?? PageNotes()
    }

    // Called only for actual writing or an explicit Add Sheet action, never
    // because a PDF page was visited or an empty placeholder was displayed.
    public mutating func materialize(_ sheet: NoteSheet, on pageIndex: Int) {
        guard pageIndex >= 0 else { return }
        let key = String(pageIndex)
        var notes = notes(for: pageIndex)
        if !notes.sheets.contains(where: { $0.id == sheet.id }) {
            notes.sheets.append(sheet)
        }
        if notes.selectedSheetID == nil { notes.selectedSheetID = sheet.id }
        pages[key] = notes
    }

    public mutating func select(sheetID: UUID, on pageIndex: Int) {
        let key = String(pageIndex)
        guard var notes = pages[key], notes.sheets.contains(where: { $0.id == sheetID }) else { return }
        notes.selectedSheetID = sheetID
        pages[key] = notes
    }

    public mutating func setPaper(_ paper: PaperStyle, sheetID: UUID, on pageIndex: Int) {
        let key = String(pageIndex)
        guard var notes = pages[key], let index = notes.sheets.firstIndex(where: { $0.id == sheetID }) else { return }
        notes.sheets[index].paper = paper
        pages[key] = notes
    }
}

public struct BookRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var pageCount: Int
    public var importedAt: Date

    public init(id: UUID = UUID(), title: String, pageCount: Int, importedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.pageCount = pageCount
        self.importedAt = importedAt
    }
}

public struct LibraryCatalog: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var books: [BookRecord]

    public init(books: [BookRecord] = []) { self.books = books }
}

public enum DrawingTarget: Hashable, Sendable {
    case pdf(page: Int)
    case note(page: Int, sheet: UUID)

    public var pageIndex: Int {
        switch self {
        case .pdf(let page), .note(let page, _): return page
        }
    }

    public var relativePath: String {
        switch self {
        case .pdf(let page): return "pdf/page-\(page).drawing"
        case .note(let page, let sheet): return "notes/page-\(page)/\(sheet.uuidString).drawing"
        }
    }
}
