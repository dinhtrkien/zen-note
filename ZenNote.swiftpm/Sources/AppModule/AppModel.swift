import SwiftUI
import PDFKit
import PencilKit
import ZenNoteCore

@MainActor
final class AppModel: ObservableObject {
    @Published var catalog = LibraryCatalog()
    @Published var session: BookSession?
    @Published var busy = false
    @Published var issue: String?
    @Published var saveError: String?
    @Published var libraryAvailable = false
    @Published var navigating = false {
        didSet { session?.refreshSurfaces() }
    }
    @Published var settings = DrawingSettings() {
        didSet {
            session?.refreshSurfaces()
            guard libraryAvailable else { return }
            preferencesSave?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.savePreferences() }
            preferencesSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    let disk: DiskStore
    let writer: LocalWriter
    private var openToken = UUID()
    private var preferencesSave: DispatchWorkItem?

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZenNote", isDirectory: true)
        disk = DiskStore(root: root)
        writer = LocalWriter(disk: disk)
        writer.onStatus = { [weak self] error in self?.saveError = error }
        do {
            catalog = try disk.loadCatalog()
            if let data = try disk.read("preferences.json") {
                settings = try JSONDecoder().decode(DrawingSettings.self, from: data)
            }
            settings.divider = min(0.72, max(0.28, settings.divider.isFinite ? settings.divider : 0.5))
            settings.width = min(8, max(1, settings.width.isFinite ? settings.width : 2.5))
            libraryAvailable = true
        } catch {
            // Do not silently replace unreadable metadata with an empty library.
            issue = "Could not open saved data: \(error.localizedDescription) Existing files have not been replaced."
        }
    }

    func importPDF(_ source: URL) {
        guard !busy, libraryAvailable else { return }
        busy = true
        let id = UUID(), disk = disk
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                try disk.copyPDF(from: source, to: id)
                guard let document = PDFDocument(url: disk.pdfURL(for: id)), !document.isLocked, document.pageCount > 0 else {
                    throw ImportError.invalidPDF
                }
                let title = source.deletingPathExtension().lastPathComponent
                let record = BookRecord(id: id, title: title.isEmpty ? "Untitled book" : title, pageCount: document.pageCount)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.catalog.books.insert(record, at: 0)
                    do {
                        self.writer.enqueue([
                            disk.bookPath(id, "state.json"): try DiskStore.encode(BookState()),
                            "library.json": try DiskStore.encode(self.catalog)
                        ])
                    } catch { self.issue = error.localizedDescription }
                    self.busy = false
                    self.openBook(record)
                }
            } catch {
                let cleanupError: String?
                do { try disk.removeUnfinishedImport(id); cleanupError = nil }
                catch { cleanupError = error.localizedDescription }
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.issue = "Import failed: \(error.localizedDescription)" + (cleanupError.map { " Cleanup also failed: \($0)" } ?? "")
                }
            }
        }
    }

    func openBook(_ record: BookRecord) {
        guard !busy, libraryAvailable else { return }
        session?.flush()
        busy = true
        openToken = UUID()
        let token = openToken, disk = disk, writer = writer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let state: BookState
                if let data = try writer.read(disk.bookPath(record.id, "state.json")) {
                    state = try JSONDecoder().decode(BookState.self, from: data)
                } else { throw StorageError.missingBookState }
                guard state.schemaVersion == 1 else { throw StorageError.unsupportedVersion(state.schemaVersion) }
                guard let document = PDFDocument(url: disk.pdfURL(for: record.id)), !document.isLocked, document.pageCount > 0 else {
                    throw ImportError.invalidPDF
                }
                DispatchQueue.main.async {
                    guard let self, token == self.openToken else { return }
                    self.session = BookSession(app: self, record: record, state: state, document: document)
                    self.busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, token == self.openToken else { return }
                    self.busy = false
                    self.issue = "Could not open this book: \(error.localizedDescription)"
                }
            }
        }
    }

    func closeBook() {
        session?.flush()
        session = nil
        navigating = false
    }

    private func savePreferences() {
        guard libraryAvailable else { return }
        do { writer.enqueue(["preferences.json": try DiskStore.encode(settings)]) }
        catch { issue = error.localizedDescription }
    }

    func suspend() {
        session?.flush()
        preferencesSave?.cancel()
        savePreferences()
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Finish Zen Note autosave") {
            DispatchQueue.main.async {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
            }
        }
        writer.afterDraining {
            if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
        }
    }

    private enum ImportError: LocalizedError {
        case invalidPDF
        var errorDescription: String? { "This file is not a readable PDF, has no pages, or is password-locked. Password-protected PDFs are not supported by this prototype." }
    }
}

@MainActor
final class BookSession: ObservableObject {
    let app: AppModel
    let record: BookRecord
    let document: PDFDocument
    @Published private(set) var state: BookState
    @Published private(set) var activePage: Int
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    weak var focusedSurface: DrawingSurface?
    var jumpToPage: ((Int) -> Void)?
    var captureReadingPosition: (() -> Void)?
    private var placeholders: [Int: NoteSheet] = [:]
    private var surfaces: [WeakSurface] = []
    private var positionSave: DispatchWorkItem?

    init(app: AppModel, record: BookRecord, state: BookState, document: PDFDocument) {
        self.app = app
        self.record = record
        self.document = document
        var initial = state
        initial.readingPosition = state.readingPosition.clamped(pageCount: document.pageCount)
        self.state = initial
        activePage = initial.readingPosition.pageIndex
    }

    var visibleSheets: [NoteSheet] {
        sheets(on: activePage)
    }

    func sheets(on page: Int) -> [NoteSheet] {
        let saved = state.notes(for: page).sheets
        if !saved.isEmpty { return saved }
        if let placeholder = placeholders[page] { return [placeholder] }
        let placeholder = NoteSheet(paper: app.settings.paper)
        placeholders[page] = placeholder
        return [placeholder]
    }

    var selectedSheet: NoteSheet {
        state.notes(for: activePage).selectedSheet ?? visibleSheets[0]
    }

    func follow(_ position: ReadingPosition) {
        let position = position.clamped(pageCount: document.pageCount)
        guard position != state.readingPosition else { return }
        if activePage != position.pageIndex {
            flushSurfaces()
            focusedSurface = nil
            updateUndo()
            activePage = position.pageIndex
        }
        state.readingPosition = position
        positionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveState() }
        positionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func selectSheet(_ id: UUID, on page: Int) {
        guard state.notes(for: page).sheets.contains(where: { $0.id == id }) else { return }
        flushSurfaces()
        state.select(sheetID: id, on: page)
        focusedSurface = nil
        updateUndo()
        saveState()
    }

    func addSheet() {
        flushSurfaces()
        let page = activePage
        // Explicit Add is allowed to materialize the current empty sheet, so
        // users can return to it; merely reading never creates a sheet.
        if state.notes(for: page).sheets.isEmpty { state.materialize(selectedSheet, on: page) }
        let added = NoteSheet(paper: app.settings.paper)
        state.materialize(added, on: page)
        state.select(sheetID: added.id, on: page)
        focusedSurface = nil
        updateUndo()
        saveState()
    }

    func changePaper(_ paper: PaperStyle) {
        let sheet = selectedSheet, page = activePage
        if state.notes(for: page).sheets.isEmpty {
            placeholders[page] = NoteSheet(id: sheet.id, paper: paper)
            // Update an app default without creating page-linked note storage.
            app.settings.paper = paper
            objectWillChange.send()
        } else {
            state.setPaper(paper, sheetID: sheet.id, on: page)
            saveState()
        }
    }

    func drawing(for target: DrawingTarget) throws -> PKDrawing {
        let path = app.disk.bookPath(record.id, target.relativePath)
        guard let data = try app.writer.read(path) else { return PKDrawing() }
        return try PKDrawing(data: data)
    }

    func saveDrawing(_ drawing: PKDrawing, target: DrawingTarget) {
        if case .note(let page, let id) = target {
            if state.notes(for: page).sheets.isEmpty && drawing.strokes.isEmpty { return }
            let sheet = state.notes(for: page).sheets.first(where: { $0.id == id })
                ?? placeholders[page].flatMap { $0.id == id ? $0 : nil }
                ?? NoteSheet(id: id, paper: app.settings.paper)
            state.materialize(sheet, on: page)
        }
        do {
            app.writer.enqueue([
                app.disk.bookPath(record.id, target.relativePath): drawing.dataRepresentation(),
                app.disk.bookPath(record.id, "state.json"): try DiskStore.encode(state)
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

    func focus(_ surface: DrawingSurface) {
        focusedSurface = surface
        updateUndo()
    }

    func updateUndo() {
        canUndo = focusedSurface?.canvas.undoManager?.canUndo ?? false
        canRedo = focusedSurface?.canvas.undoManager?.canRedo ?? false
    }

    func undo() { focusedSurface?.canvas.undoManager?.undo(); focusedSurface?.flush(); updateUndo() }
    func redo() { focusedSurface?.canvas.undoManager?.redo(); focusedSurface?.flush(); updateUndo() }

    func flushSurfaces() {
        for surface in surfaces { surface.value?.flush() }
    }

    func flush() {
        captureReadingPosition?()
        positionSave?.cancel()
        flushSurfaces()
        saveState()
    }

    private func saveState() {
        do { app.writer.enqueue([app.disk.bookPath(record.id, "state.json"): try DiskStore.encode(state)]) }
        catch { app.issue = "Could not encode reading position: \(error.localizedDescription)" }
    }

    private final class WeakSurface {
        weak var value: DrawingSurface?
        init(_ value: DrawingSurface) { self.value = value }
    }
}
