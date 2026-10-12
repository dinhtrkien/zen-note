import XCTest
@testable import ZenNoteCore

final class ZenNoteCoreTests: XCTestCase {
    func testVisitingHundredsOfPagesDoesNotMaterializeNotes() {
        let state = BookState()
        for page in 0..<800 {
            XCTAssertTrue(state.notes(for: page).sheets.isEmpty)
            XCTAssertNil(state.notes(for: page).selectedSheet)
        }
        XCTAssertTrue(state.pages.isEmpty)
    }

    func testOnePDFPageCanOwnSeveralSheetsWithoutAffectingNeighbors() {
        var state = BookState()
        let first = NoteSheet(paper: .grid), second = NoteSheet(paper: .blank)
        state.materialize(first, on: 20)
        state.materialize(second, on: 20)
        XCTAssertEqual(state.notes(for: 20).sheets, [first, second])
        XCTAssertTrue(state.notes(for: 21).sheets.isEmpty)
        XCTAssertEqual(state.pages.count, 1)
    }

    func testMaterializationIsIdempotent() {
        var state = BookState()
        let sheet = NoteSheet()
        state.materialize(sheet, on: 2)
        state.materialize(sheet, on: 2)
        XCTAssertEqual(state.notes(for: 2).sheets, [sheet])
    }

    func testLastSelectedSheetIsRememberedPerPage() throws {
        var state = BookState()
        let a = NoteSheet(), b = NoteSheet(), c = NoteSheet()
        state.materialize(a, on: 2)
        state.materialize(b, on: 2)
        state.materialize(c, on: 3)
        state.select(sheetID: b.id, on: 2)
        let restored = try JSONDecoder().decode(BookState.self, from: DiskStore.encode(state))
        XCTAssertEqual(restored.notes(for: 2).selectedSheet, b)
        XCTAssertEqual(restored.notes(for: 3).selectedSheet, c)
    }

    func testInvalidSelectionAndPaperChangeDoNotCreateSheets() {
        var state = BookState()
        state.select(sheetID: UUID(), on: 99)
        state.setPaper(.blank, sheetID: UUID(), on: 99)
        state.materialize(NoteSheet(), on: -1)
        XCTAssertTrue(state.pages.isEmpty)
    }

    func testPaperStyleChangesOnlyTheRequestedSheet() {
        var state = BookState()
        let a = NoteSheet(), b = NoteSheet()
        state.materialize(a, on: 2)
        state.materialize(b, on: 2)
        state.setPaper(.blank, sheetID: b.id, on: 2)
        XCTAssertEqual(state.notes(for: 2).sheets.map(\.paper), [.grid, .blank])
    }

    func testReadingPositionClampsInvalidCoordinatesAndPageNumbers() {
        let position = ReadingPosition(pageIndex: 999, x: -.infinity, y: 2, zoom: .nan).clamped(pageCount: 200)
        XCTAssertEqual(position.pageIndex, 199)
        XCTAssertEqual(position.x, 0.5)
        XCTAssertEqual(position.y, 1)
        XCTAssertEqual(position.zoom, 1)
        XCTAssertEqual(ReadingPosition(pageIndex: -3).pageIndex, 0)
        XCTAssertEqual(ReadingPosition(pageIndex: 4).clamped(pageCount: 0).pageIndex, 0)
    }

    func testDrawingsAreIsolatedByPDFPageSheetAndBook() {
        let disk = temporaryDisk(), a = UUID(), b = UUID(), sheet = UUID()
        let note = DrawingTarget.note(page: 8, sheet: sheet).relativePath
        XCTAssertNotEqual(note, DrawingTarget.note(page: 9, sheet: sheet).relativePath)
        XCTAssertNotEqual(note, DrawingTarget.pdf(page: 8).relativePath)
        XCTAssertNotEqual(disk.bookPath(a, note), disk.bookPath(b, note))
    }

    func testCatalogStateAndDrawingsRoundTripOnDisk() throws {
        let disk = temporaryDisk()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let book = BookRecord(title: "Calculus", pageCount: 620)
        let sheet = NoteSheet(paper: .blank)
        var state = BookState(readingPosition: ReadingPosition(pageIndex: 84, x: 0.4, y: 0.7, zoom: 2))
        state.materialize(sheet, on: 84)
        let target = DrawingTarget.note(page: 84, sheet: sheet.id)
        let drawing = Data([0, 1, 2, 255])
        try disk.write(disk.bookPath(book.id, target.relativePath), data: drawing)
        try disk.write(disk.bookPath(book.id, "state.json"), data: DiskStore.encode(state))
        try disk.write("library.json", data: DiskStore.encode(LibraryCatalog(books: [book])))
        let reopened = DiskStore(root: disk.root)
        XCTAssertEqual(try reopened.loadCatalog().books, [book])
        XCTAssertEqual(try reopened.loadBook(book.id), state)
        XCTAssertEqual(try reopened.read(disk.bookPath(book.id, target.relativePath)), drawing)
    }

    func testAtomicReplacementKeepsTheLatestSnapshot() throws {
        let disk = temporaryDisk()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        try disk.write("test.drawing", data: Data([1]))
        try disk.write("test.drawing", data: Data([2, 3]))
        XCTAssertEqual(try disk.read("test.drawing"), Data([2, 3]))
    }

    func testCorruptMetadataThrowsWithoutReplacingFiles() throws {
        let disk = temporaryDisk()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let corrupt = Data("not json".utf8)
        try disk.write("library.json", data: corrupt)
        XCTAssertThrowsError(try disk.loadCatalog())
        XCTAssertEqual(try disk.read("library.json"), corrupt)
    }

    func testFutureMetadataVersionIsRejected() throws {
        let disk = temporaryDisk()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        var future = LibraryCatalog()
        future.schemaVersion = 2
        try disk.write("library.json", data: DiskStore.encode(future))
        XCTAssertThrowsError(try disk.loadCatalog())
        var state = BookState()
        state.schemaVersion = 99
        let id = UUID()
        try disk.write(disk.bookPath(id, "state.json"), data: DiskStore.encode(state))
        XCTAssertThrowsError(try disk.loadBook(id))
    }

    func testMissingLibraryStartsEmptyWithoutWritingFiles() throws {
        let disk = temporaryDisk()
        XCTAssertTrue(try disk.loadCatalog().books.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.root.path))
    }

    func testUnsafeStoragePathsAreRejected() throws {
        let disk = temporaryDisk()
        for path in ["", "../outside", "/absolute", "folder/../../outside", "folder\\outside"] {
            XCTAssertThrowsError(try disk.write(path, data: Data()))
            XCTAssertThrowsError(try disk.read(path))
        }
    }

    func testImportMakesAnIndependentLocalCopy() throws {
        let disk = temporaryDisk()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let bytes = Data("representative PDF bytes".utf8)
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let id = UUID()
        try disk.copyPDF(from: source, to: id)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: disk.pdfURL(for: id)), bytes)
    }

    func testWritesPublishDrawingsBeforeMetadataAndCatalog() throws {
        var pending = PendingWrites()
        pending.stage(["library.json": Data([3]), "books/a/state.json": Data([2]), "books/a/notes/a.drawing": Data([1])])
        var order: [String] = []
        try pending.flush { path, _ in order.append(path) }
        XCTAssertEqual(order, ["books/a/notes/a.drawing", "books/a/state.json", "library.json"])
        XCTAssertTrue(pending.isEmpty)
    }

    func testFailedDrawingSavePreservesAllDataAndBlocksMetadataPublication() throws {
        enum Failure: Error { case diskFull }
        var pending = PendingWrites()
        pending.stage(["state.json": Data([2]), "note.drawing": Data([1])])
        var order: [String] = []
        XCTAssertThrowsError(try pending.flush { path, _ in order.append(path); throw Failure.diskFull })
        XCTAssertEqual(order, ["note.drawing"])
        XCTAssertEqual(pending.count, 2)
        pending.stage(["note.drawing": Data([9])])
        XCTAssertEqual(pending.data(for: "note.drawing"), Data([9]))
        var saved: [String: Data] = [:]
        try pending.flush { saved[$0] = $1 }
        XCTAssertEqual(saved["note.drawing"], Data([9]))
        XCTAssertEqual(saved["state.json"], Data([2]))
        XCTAssertTrue(pending.isEmpty)
    }

    func testPartialFailureRetriesOnlyRemainingWrites() throws {
        enum Failure: Error { case diskFull }
        var pending = PendingWrites()
        pending.stage(["a.drawing": Data([1]), "state.json": Data([2])])
        XCTAssertThrowsError(try pending.flush { path, _ in if path == "state.json" { throw Failure.diskFull } })
        XCTAssertNil(pending.data(for: "a.drawing"))
        XCTAssertEqual(pending.count, 1)
        var paths: [String] = []
        try pending.flush { path, _ in paths.append(path) }
        XCTAssertEqual(paths, ["state.json"])
    }

    private func temporaryDisk() -> DiskStore {
        DiskStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("zen-note-tests-" + UUID().uuidString))
    }
}
