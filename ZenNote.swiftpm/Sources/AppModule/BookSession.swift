import SwiftUI
import PDFKit
import PencilKit
import ZenNoteCore

@MainActor
final class BookSession: ObservableObject {
    let app: AppModel
    let record: BookRecord
    let document: PDFDocument
    private let disk: DiskStore
    private let writer: LocalWriter
    private let writable: Bool
    private var closed = false
    var acceptsDrawing: Bool { writable && !closed }
    @Published private(set) var state: BookState
    @Published private(set) var activePage: Int
    @Published private(set) var pinnedPage: Int?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var isDrawing = false
    @Published private(set) var interactionCount = 0
    @Published private(set) var zenMode = false
    weak var focusedSurface: DrawingSurface?
    private(set) var jumpToPage: ((Int) -> Void)?
    private(set) var captureReadingPosition: (() -> Void)?
    private var readerID: UUID?
    private var placeholders: [Int: NoteSheet] = [:]
    private var surfaces: [WeakSurface] = []
    private var strokes = Set<ObjectIdentifier>()
    private var drawingNotePage: Int?
    private var positionSave: DispatchWorkItem?

    init(app: AppModel, record: BookRecord, state: BookState, document: PDFDocument) {
        self.app = app
        self.record = record
        self.document = document
        disk = app.disk
        writer = app.writer
        writable = app.isFilesLibrary
        var initial = state
        initial.readingPosition = state.readingPosition.clamped(pageCount: document.pageCount)
        self.state = initial
        activePage = initial.readingPosition.pageIndex
    }

    // A stroke never changes canvas midway through PDF navigation. Automatic
    // following resumes as soon as that note stroke finishes.
    var notePage: Int { pinnedPage ?? drawingNotePage ?? activePage }
    var visibleSheets: [NoteSheet] { sheets(on: notePage) }
    var selectedSheet: NoteSheet { state.notes(for: notePage).selectedSheet ?? visibleSheets[0] }

    func sheets(on page: Int) -> [NoteSheet] {
        let saved = state.notes(for: page).sheets
        if !saved.isEmpty { return saved }
        if let placeholder = placeholders[page] { return [placeholder] }
        let placeholder = NoteSheet(paper: app.settings.paper)
        placeholders[page] = placeholder
        return [placeholder]
    }

    func attachReader(id: UUID, capture: @escaping () -> Void, jump: @escaping (Int) -> Void) {
        readerID = id
        captureReadingPosition = capture
        jumpToPage = jump
    }

    func detachReader(id: UUID) {
        guard readerID == id else { return }
        readerID = nil
        captureReadingPosition = nil
        jumpToPage = nil
    }

    func activity() { if !closed { interactionCount &+= 1 } }

    func toggleZen() {
        guard !closed, !isDrawing else { return }
        captureReadingPosition?()
        flushSurfaces()
        zenMode.toggle()
        activity()
    }

    func togglePin() {
        guard !closed, !isDrawing else { return }
        captureReadingPosition?()
        flushSurfaces()
        pinnedPage = pinnedPage == nil ? activePage : nil
        focusedSurface = nil
        updateUndo()
        activity()
    }

    func follow(_ position: ReadingPosition) {
        guard !closed else { return }
        let position = position.clamped(pageCount: document.pageCount)
        guard position != state.readingPosition else { return }
        if activePage != position.pageIndex {
            flushSurfaces()
            if pinnedPage == nil && drawingNotePage == nil {
                focusedSurface = nil
            } else if let focusedSurface, case .pdf = focusedSurface.target {
                self.focusedSurface = nil
            }
            updateUndo()
            activePage = position.pageIndex
        }
        state.readingPosition = position
        activity()
        positionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveState() }
        positionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func selectSheet(_ id: UUID, on page: Int) {
        guard !closed, page == notePage, state.notes(for: page).sheets.contains(where: { $0.id == id }) else { return }
        flushSurfaces()
        state.select(sheetID: id, on: page)
        focusedSurface = nil
        updateUndo()
        saveState()
        activity()
    }

    func addSheet() {
        guard acceptsDrawing else { app.issue = "Choose a Files library folder before adding or writing notes."; return }
        flushSurfaces()
        let page = notePage
        if state.notes(for: page).sheets.isEmpty { state.materialize(selectedSheet, on: page) }
        let added = NoteSheet(paper: app.settings.paper)
        state.materialize(added, on: page)
        state.select(sheetID: added.id, on: page)
        focusedSurface = nil
        updateUndo()
        saveState()
        activity()
    }

    func changePaper(_ paper: PaperStyle) {
        guard acceptsDrawing else { return }
        let sheet = selectedSheet, page = notePage
        if state.notes(for: page).sheets.isEmpty {
            placeholders[page] = NoteSheet(id: sheet.id, paper: paper)
            app.settings.paper = paper
            objectWillChange.send()
        } else {
            state.setPaper(paper, sheetID: sheet.id, on: page)
            saveState()
        }
        activity()
    }

    func drawing(for target: DrawingTarget) throws -> PKDrawing {
        let path = disk.bookPath(record.id, target.relativePath)
        guard let data = try writer.read(path) else { return PKDrawing() }
        return try PKDrawing(data: data)
    }

    func saveDrawing(_ drawing: PKDrawing, target: DrawingTarget) {
        guard acceptsDrawing else { return }
        if case .note(let page, let id) = target {
            if state.notes(for: page).sheets.isEmpty && drawing.strokes.isEmpty { return }
            let sheet = state.notes(for: page).sheets.first(where: { $0.id == id })
                ?? placeholders[page].flatMap { $0.id == id ? $0 : nil }
                ?? NoteSheet(id: id, paper: app.settings.paper)
            state.materialize(sheet, on: page)
        }
        do {
            writer.enqueue([
                disk.bookPath(record.id, target.relativePath): drawing.dataRepresentation(),
                disk.bookPath(record.id, "state.json"): try DiskStore.encode(state)
            ])
        } catch { app.issue = "Could not encode notes: \(error.localizedDescription)" }
        updateUndo()
    }

    func register(_ surface: DrawingSurface) {
        surfaces.removeAll { $0.value == nil }
        surfaces.append(WeakSurface(surface))
    }

    func refreshSurfaces() {
        surfaces.removeAll { $0.value == nil }
        for surface in surfaces { surface.value?.applySettings() }
    }

    func beginStroke(_ surface: DrawingSurface) {
        guard acceptsDrawing else { return }
        focusedSurface = surface
        if case .note(let page, _) = surface.target { drawingNotePage = page }
        strokes.insert(ObjectIdentifier(surface))
        isDrawing = !strokes.isEmpty
        updateUndo()
        activity()
    }

    func endStroke(_ surface: DrawingSurface) {
        let removed = strokes.remove(ObjectIdentifier(surface))
        if removed != nil, case .note = surface.target { drawingNotePage = nil }
        isDrawing = !strokes.isEmpty
        if removed != nil { activity() }
    }

    func endAllStrokes() { strokes.removeAll(); drawingNotePage = nil; isDrawing = false; activity() }

    func updateUndo() {
        canUndo = focusedSurface?.canvas.undoManager?.canUndo ?? false
        canRedo = focusedSurface?.canvas.undoManager?.canRedo ?? false
    }

    func undo() { focusedSurface?.canvas.undoManager?.undo(); focusedSurface?.flush(); updateUndo(); activity() }
    func redo() { focusedSurface?.canvas.undoManager?.redo(); focusedSurface?.flush(); updateUndo(); activity() }
    func flushSurfaces() { for surface in surfaces { surface.value?.flush() } }

    func flush() {
        captureReadingPosition?()
        positionSave?.cancel()
        flushSurfaces()
        saveState()
    }

    func close() {
        flush()
        closed = true
        endAllStrokes()
        refreshSurfaces()
    }

    private func saveState() {
        guard !closed else { return }
        do { writer.enqueue([disk.bookPath(record.id, "state.json"): try DiskStore.encode(state)]) }
        catch { app.issue = "Could not encode reading position: \(error.localizedDescription)" }
    }

    private final class WeakSurface {
        weak var value: DrawingSurface?
        init(_ value: DrawingSurface) { self.value = value }
    }
}
