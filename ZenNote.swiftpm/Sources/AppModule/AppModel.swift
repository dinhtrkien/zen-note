import SwiftUI
import PDFKit
import ZenNoteCore

@MainActor
final class AppModel: ObservableObject {
    @Published var catalog = LibraryCatalog()
    @Published var session: BookSession?
    @Published var busy = false { didSet { if !busy { finishBackgroundSaveWhenIdle() } } }
    @Published var busyMessage = "Opening your library…"
    @Published var issue: String?
    @Published var saveError: String?
    @Published var libraryError: String?
    @Published private(set) var libraryAvailable = false
    @Published private(set) var isFilesLibrary = false
    @Published private(set) var folderName = "Private v1 library"
    @Published var connectionQuestion: String?
    @Published var navigating = false { didSet { session?.refreshSurfaces(); session?.activity() } }
    @Published var settings = DrawingSettings() {
        didSet {
            guard !loadingPreferences else { return }
            if oldValue.layout != settings.layout {
                session?.captureReadingPosition?()
                session?.flushSurfaces()
            }
            session?.refreshSurfaces()
            session?.activity()
            guard libraryAvailable else { return }
            preferencesSave?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.savePreferences() }
            preferencesSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private(set) var disk: DiskStore
    private(set) var writer: LocalWriter
    private let bookmarkURL: URL
    private var folderAccess: LibraryFolderAccess?
    private var pendingFolder: PreparedFolder?
    private var loadingPreferences = false
    private var preferencesSave: DispatchWorkItem?
    private var openToken = UUID()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = DiskStore(root: support.appendingPathComponent("ZenNote", isDirectory: true))
        bookmarkURL = support.appendingPathComponent("ZenNoteLocation/library.bookmark")
        disk = legacy
        writer = LocalWriter(disk: legacy)
        observeWriter(writer)
        if FileManager.default.fileExists(atPath: bookmarkURL.path) {
            busy = true
            let bookmark = bookmarkURL
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let access = try LibraryFolderAccess.restore(from: bookmark)
                    let store = DiskStore(root: access.url, coordinatesAccess: true)
                    let preferences = try Self.readPreferences(store)
                    let catalog = try Self.attachCatalog(store)
                    DispatchQueue.main.async {
                        self?.install(store: store, access: access, catalog: catalog, preferences: preferences)
                        self?.busy = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.busy = false
                        self?.libraryError = "Reconnect your Files library: \(error.localizedDescription) No empty fallback was created."
                    }
                }
            }
        } else {
            do {
                catalog = try legacy.loadCatalog()
                loadingPreferences = true
                settings = try Self.readPreferences(legacy)
                loadingPreferences = false
                libraryAvailable = true
                if catalog.libraryID == nil {
                    catalog.libraryID = UUID()
                    writer.enqueue(["library.json": try DiskStore.encode(catalog)])
                }
            } catch {
                loadingPreferences = false
                libraryError = "Could not open the private v1 library: \(error.localizedDescription) Its files have not been replaced."
            }
        }
    }

    private func observeWriter(_ observed: LocalWriter) {
        observed.onStatus = { [weak self, weak observed] error in
            guard let self, let observed, self.writer === observed else { return }
            self.saveError = error
        }
    }

    nonisolated private static func readPreferences(_ store: DiskStore) throws -> DrawingSettings {
        guard let data = try store.read("preferences.json") else { return DrawingSettings() }
        return try JSONDecoder().decode(DrawingSettings.self, from: data)
    }

    nonisolated private static func attachCatalog(_ store: DiskStore) throws -> LibraryCatalog {
        try store.withRoot(writing: true) { root in
            let uncoordinated = DiskStore(root: root)
            guard try uncoordinated.read("library.json") != nil else { throw StorageError.missingCatalog }
            var catalog = try uncoordinated.loadCatalog()
            if catalog.libraryID == nil {
                catalog.libraryID = UUID()
                try uncoordinated.write("library.json", data: DiskStore.encode(catalog))
            }
            return catalog
        }
    }

    private func install(store: DiskStore, access: LibraryFolderAccess, catalog: LibraryCatalog,
                         preferences: DrawingSettings, reusing existingWriter: LocalWriter? = nil) {
        disk = DiskStore(root: store.root, coordinatesAccess: true, expectedLibraryID: catalog.libraryID)
        folderAccess = access
        writer = existingWriter ?? LocalWriter(disk: disk, accessLease: access)
        observeWriter(writer)
        self.catalog = catalog
        loadingPreferences = true
        settings = preferences
        loadingPreferences = false
        folderName = access.url.lastPathComponent
        isFilesLibrary = true
        libraryAvailable = true
        libraryError = nil
        if existingWriter == nil { saveError = nil }
        if self.catalog.libraryID == nil {
            self.catalog.libraryID = UUID()
            do { writer.enqueue(["library.json": try DiskStore.encode(self.catalog)]) }
            catch { issue = error.localizedDescription }
        }
    }

    /// Selection is read-only until the user confirms opening/copying a library.
    func prepareFolder(_ url: URL) {
        guard !busy else { return }
        busy = true
        busyMessage = "Checking library folder…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let access = try LibraryFolderAccess(url: url)
                let store = DiskStore(root: url, coordinatesAccess: true)
                let existing: LibraryCatalog?
                if try store.read("library.json") != nil { existing = try store.loadCatalog() }
                else {
                    guard try LibraryTransfer.isEmpty(store) else { throw StorageError.destinationNotEmpty }
                    existing = nil
                }
                let preferences = existing == nil ? nil : try Self.readPreferences(store)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pendingFolder = PreparedFolder(access: access, store: store, catalog: existing, preferences: preferences)
                    if let existing {
                        self.connectionQuestion = "Open the library in “\(url.lastPathComponent)” (\(existing.books.count) books)? Your current library will not be deleted or merged."
                    } else if self.libraryAvailable && !self.catalog.books.isEmpty {
                        self.connectionQuestion = "Copy \(self.catalog.books.count) books, editable notes, and preferences to “\(url.lastPathComponent)” and autosave there? The original will be kept."
                    } else if self.libraryError != nil {
                        self.connectionQuestion = "This folder is empty. Create a new library? This will not recover your previous library; reselect its original folder to recover it."
                    } else {
                        self.connectionQuestion = "Use “\(url.lastPathComponent)” as your Files library? Choose local storage outside Playgrounds-owned folders for reliable offline access."
                    }
                    self.busy = false
                }
            } catch {
                DispatchQueue.main.async { self?.busy = false; self?.issue = error.localizedDescription }
            }
        }
    }

    func cancelFolder() { connectionQuestion = nil; pendingFolder = nil }

    func confirmFolder() {
        guard !busy, let proposed = pendingFolder else { return }
        connectionQuestion = nil
        closeBook()
        preferencesSave?.cancel()
        savePreferences()
        busy = true
        busyMessage = proposed.catalog == nil ? "Copying and verifying your library…" : "Connecting library…"
        let source = disk, previousWriter = writer, sourceAvailable = libraryAvailable
        let sourceCatalog = catalog, currentPreferences = settings, bookmark = bookmarkURL
        let sameIdentity = proposed.catalog?.libraryID != nil && proposed.catalog?.libraryID == catalog.libraryID
        let sameDirectory = disk.root.standardizedFileURL == proposed.store.root.standardizedFileURL ||
            (folderAccess?.identity != nil && folderAccess?.identity == proposed.access.identity)
        let reconnecting = isFilesLibrary && sameIdentity && sameDirectory

        // Adopt the renewed scope before rebind. Even if a retry fails, keep the
        // same writer and its unsaved drafts attached to the selected directory.
        let renewedStore = DiskStore(root: proposed.store.root, coordinatesAccess: true, expectedLibraryID: sourceCatalog.libraryID)
        if reconnecting { disk = renewedStore; folderAccess = proposed.access }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let resultCatalog: LibraryCatalog
                let resultPreferences: DrawingSettings
                var reconnectError: String?
                if reconnecting {
                    do { try previousWriter.reconnect(to: renewedStore, accessLease: proposed.access) }
                    catch { reconnectError = error.localizedDescription }
                    resultCatalog = sourceCatalog
                    resultPreferences = currentPreferences
                } else {
                    try previousWriter.finishPending()
                    if proposed.catalog != nil {
                        // Re-read after confirmation; another process may have
                        // changed the folder while the confirmation was visible.
                        resultPreferences = try Self.readPreferences(proposed.store)
                        resultCatalog = try Self.attachCatalog(proposed.store)
                    } else if sourceAvailable && !sourceCatalog.books.isEmpty {
                        resultCatalog = try LibraryTransfer.copy(from: source, to: proposed.store)
                        resultPreferences = try Self.readPreferences(proposed.store)
                    } else {
                        resultCatalog = try LibraryTransfer.createEmpty(at: proposed.store, preferences: DiskStore.encode(currentPreferences))
                        resultPreferences = currentPreferences
                    }
                }
                var bookmarkWarning: String?
                do { try proposed.access.remember(at: bookmark) }
                catch { bookmarkWarning = "The Files library is connected, but permission could not be remembered. Reselect it next launch: \(error.localizedDescription)" }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.install(store: proposed.store, access: proposed.access, catalog: resultCatalog,
                                 preferences: resultPreferences, reusing: reconnecting ? previousWriter : nil)
                    self.pendingFolder = nil
                    self.busy = false
                    if let reconnectError { self.issue = "Reconnected, but autosave still needs retry: \(reconnectError). Unsaved changes remain in memory." }
                    else if let bookmarkWarning { self.issue = bookmarkWarning }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.pendingFolder = nil
                    self?.issue = "Could not switch libraries: \(error.localizedDescription) The original library and unsaved changes were retained."
                }
            }
        }
    }

    func importPDF(_ source: URL) {
        guard !busy, libraryAvailable, isFilesLibrary else { return }
        busy = true
        busyMessage = "Importing PDF…"
        let id = UUID(), disk = disk
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                try disk.copyPDF(from: source, to: id)
                let count = try disk.withPDF(for: id) { url -> Int in
                    guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { throw ImportError.invalidPDF }
                    return document.pageCount
                }
                let title = source.deletingPathExtension().lastPathComponent
                let record = BookRecord(id: id, title: title.isEmpty ? "Untitled book" : title, pageCount: count)
                DispatchQueue.main.async {
                    guard let self else { return }
                    do {
                        var next = self.catalog
                        next.books.insert(record, at: 0)
                        self.writer.enqueue([
                            disk.bookPath(id, "state.json"): try DiskStore.encode(BookState()),
                            "library.json": try DiskStore.encode(next)
                        ])
                        self.catalog = next
                    } catch { self.issue = error.localizedDescription }
                    self.busy = false
                    self.openBook(record)
                }
            } catch {
                var cleanupError: String?
                do { try disk.removeUnfinishedImport(id) }
                catch { cleanupError = error.localizedDescription }
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.issue = "Import failed: \(error.localizedDescription)" + (cleanupError.map { " Cleanup failed: \($0)" } ?? "")
                }
            }
        }
    }

    func openBook(_ record: BookRecord) {
        guard !busy, libraryAvailable else { return }
        session?.close()
        busy = true
        busyMessage = "Opening your book…"
        openToken = UUID()
        let token = openToken, disk = disk, writer = writer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let data = try writer.read(disk.bookPath(record.id, "state.json")) else { throw StorageError.missingBookState }
                let state = try JSONDecoder().decode(BookState.self, from: data)
                guard state.schemaVersion == 1 else { throw StorageError.unsupportedVersion(state.schemaVersion) }
                let document = try disk.withPDF(for: record.id) { url -> PDFDocument in
                    guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { throw ImportError.invalidPDF }
                    return document
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
        session?.close()
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
        session?.endAllStrokes()
        preferencesSave?.cancel()
        savePreferences()
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish Zen Note storage") { [weak self] in
                DispatchQueue.main.async { self?.endBackgroundTask() }
            }
        }
        finishBackgroundSaveWhenIdle()
    }

    private func finishBackgroundSaveWhenIdle() {
        guard backgroundTask != .invalid, !busy else { return }
        writer.afterDraining { [weak self] in
            guard let self, !self.busy else { return }
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private struct PreparedFolder {
        let access: LibraryFolderAccess
        let store: DiskStore
        let catalog: LibraryCatalog?
        let preferences: DrawingSettings?
    }

    private enum ImportError: LocalizedError {
        case invalidPDF
        var errorDescription: String? { "This file is not a readable PDF, has no pages, or is password-locked. Password-protected PDFs are not supported by this prototype." }
    }
}
