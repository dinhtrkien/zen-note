
// MARK: - One-time v1 migration UI (not part of the v2 app)

@MainActor
private struct V1MigrationFolderPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        let onCancel: () -> Void
        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onSelect(url) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

@MainActor
private final class V1MigrationController: ObservableObject {
    @Published private(set) var isCopying = false
    @Published private(set) var status = "Copying and verifying your library…"
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    func copy(app: AppModel, to folder: URL) {
        guard !app.busy, !isCopying, app.libraryAvailable, app.session == nil else { return }
        guard !app.catalog.books.isEmpty else {
            app.issue = "No old books are visible. Stop here; an empty library is not a successful migration."
            return
        }
        guard folder.startAccessingSecurityScopedResource() else {
            app.issue = "Files did not grant access to this folder. Choose another empty local folder. The original library was not changed."
            return
        }
        isCopying = true
        app.busy = true
        status = "Finishing old autosave…"
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Copy v1 study library") { [weak self] in
            DispatchQueue.main.async {
                self?.status = "Return to Zen Note to let copying finish. Do not force-stop it."
                self?.endBackgroundTask()
            }
        }
        do {
            // Persist the currently selected preferences using the old writer.
            app.writer.enqueue(["preferences.json": try DiskStore.encode(app.settings)])
        } catch {
            finish(app: app, folder: folder, message: "Could not prepare migration: \(error.localizedDescription)")
            return
        }
        let source = app.disk.root
        let expectedIDs = Set(app.catalog.books.map(\.id))
        app.writer.afterDraining { [self, app] in
            guard app.saveError == nil else {
                finish(app: app, folder: folder, message: "Old autosave needs retry before copying. Unsaved changes remain in memory; keep the app open and use Retry saves.")
                return
            }
            status = "Copying and verifying your library…"
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try V1MigrationCopy.copy(from: source, to: folder, expectedBookIDs: expectedIDs) }
                DispatchQueue.main.async { [self, app] in
                    switch result {
                    case .success(let receipt):
                        finish(app: app, folder: folder, message: "Copied and byte-verified \(receipt.books) books and \(receipt.files) files into “\(folder.lastPathComponent)”. Original data is retained. Now open the NEW Zen Note project, choose this EXISTING folder, and check your notes before deleting anything.")
                    case .failure(let error):
                        finish(app: app, folder: folder, message: "Copy failed: \(error.localizedDescription) Your original library was not deleted. Keep this project and retry with an empty local folder.")
                    }
                }
            }
        }
    }

    private func finish(app: AppModel, folder: URL, message: String) {
        folder.stopAccessingSecurityScopedResource()
        endBackgroundTask()
        isCopying = false
        app.busy = false
        app.issue = message
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
#endif

// Foundation-only copy logic stays in this same file so the old project needs
// ONE replacement. ZENNOTE_MIGRATION_PORTABLE is only a host compilation flag.
private enum V1MigrationCopy {
    struct Receipt { let books: Int; let files: Int }

    static func copy(from source: URL, to destination: URL, expectedBookIDs: Set<UUID>) throws -> Receipt {
        let a = source.resolvingSymlinksInPath().standardizedFileURL.path
        let b = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard a != b, !a.hasPrefix(b + "/"), !b.hasPrefix(a + "/") else { throw CopyError.overlap }
        #if canImport(Darwin)
        var coordinationError: NSError?
        var outcome: Result<Receipt, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: [], error: &coordinationError) { original, target in
            outcome = Result { try copyCoordinated(from: original, to: target, expectedBookIDs: expectedBookIDs) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CopyError.unavailable }
        return try outcome.get()
        #else
        return try copyCoordinated(from: source, to: destination, expectedBookIDs: expectedBookIDs)
        #endif
    }

    private static func copyCoordinated(from source: URL, to destination: URL, expectedBookIDs: Set<UUID>) throws -> Receipt {
        let destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard destinationValues.isDirectory == true, destinationValues.isSymbolicLink != true else { throw CopyError.unavailable }
        guard try contents(destination).isEmpty else { throw CopyError.notEmpty }
        let disk = DiskStore(root: source)
        guard let index = try disk.read("library.json") else { throw CopyError.incomplete }
        let catalog = try JSONDecoder().decode(LibraryCatalog.self, from: index)
        guard catalog.schemaVersion == 1, !catalog.books.isEmpty,
              Set(catalog.books.map(\.id)) == expectedBookIDs,
              expectedBookIDs.count == catalog.books.count else { throw CopyError.incomplete }
        try validate(catalog, in: disk)
        // Reject links/special files BEFORE copying. Also freezes the relative
        // file list so changes to the source can be detected during verification.
        let originalFiles = try files(in: source)
        let stage = destination.appendingPathComponent(".zen-note-v1-copy-" + UUID().uuidString, isDirectory: true)
        var published: [URL] = []
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
            for item in try contents(source) {
                try FileManager.default.copyItem(at: item, to: stage.appendingPathComponent(item.lastPathComponent))
            }
            guard try files(in: stage) == originalFiles else { throw CopyError.changed }
            for path in originalFiles {
                try compare(source.appendingPathComponent(path), stage.appendingPathComponent(path))
            }
            guard try files(in: source) == originalFiles else { throw CopyError.changed }
            try validate(catalog, in: DiskStore(root: stage))
            // Metadata/index is published LAST. Until then the folder cannot be
            // mistaken for a completed Zen Note library by the new app.
            for item in try contents(stage).sorted(by: {
                if $0.lastPathComponent == "library.json" { return false }
                if $1.lastPathComponent == "library.json" { return true }
                return $0.lastPathComponent < $1.lastPathComponent
            }) {
                let target = destination.appendingPathComponent(item.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: target.path) else { throw CopyError.notEmpty }
                try FileManager.default.moveItem(at: item, to: target)
                published.append(target)
            }
            try FileManager.default.removeItem(at: stage)
            return Receipt(books: catalog.books.count, files: originalFiles.count)
        } catch {
            let primary = error.localizedDescription
            var cleanupErrors: [String] = []
            for item in published.reversed() + [stage] {
                do {
                    if FileManager.default.fileExists(atPath: item.path) { try FileManager.default.removeItem(at: item) }
                } catch { cleanupErrors.append(error.localizedDescription) }
            }
            if !cleanupErrors.isEmpty {
                throw CopyError.cleanup(primary + " Temporary copy cleanup also failed: " + cleanupErrors.joined(separator: "; ") + ". Keep the partial destination and choose another empty folder. The original is retained.")
            }
            throw error
        }
    }

    private static func validate(_ catalog: LibraryCatalog, in disk: DiskStore) throws {
        for book in catalog.books {
            guard let data = try disk.read(disk.bookPath(book.id, "state.json")) else { throw CopyError.incomplete }
            let state = try JSONDecoder().decode(BookState.self, from: data)
            guard state.schemaVersion == 1 else { throw CopyError.incomplete }
            let pdf = try disk.pdfURL(for: book.id).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard pdf.isRegularFile == true, pdf.isSymbolicLink != true, (pdf.fileSize ?? 0) > 0 else { throw CopyError.incomplete }
        }
    }

    private static func contents(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
    }

    private static func files(in root: URL) throws -> [String] {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            errorHandler: { _, error in enumerationError = error; return false }) else { throw CopyError.incomplete }
        var paths: [String] = []
        let prefix = root.path + "/"
        for case let item as URL in enumerator {
            if item.lastPathComponent == ".DS_Store" { continue }
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CopyError.incomplete }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, item.path.hasPrefix(prefix) else { throw CopyError.incomplete }
            paths.append(String(item.path.dropFirst(prefix.count)))
        }
        if let enumerationError { throw enumerationError }
        return paths.sorted()
    }

    private static func compare(_ original: URL, _ copied: URL) throws {
        let left = try FileHandle(forReadingFrom: original)
        defer { try? left.close() }
        let right = try FileHandle(forReadingFrom: copied)
        defer { try? right.close() }
        while true {
            let a = try left.read(upToCount: 65_536) ?? Data()
            let b = try right.read(upToCount: 65_536) ?? Data()
            guard a == b else { throw CopyError.changed }
            if a.isEmpty { return }
        }
    }

    private enum CopyError: LocalizedError {
        case notEmpty, unavailable, overlap, incomplete, changed, cleanup(String)
        var errorDescription: String? {
            switch self {
            case .notEmpty: return "Choose an EMPTY folder. No existing library or other files will be overwritten."
            case .unavailable: return "Files could not provide a writable folder."
            case .overlap: return "Choose a separate destination, not the original library or its parent/child folders."
            case .incomplete: return "The original library is incomplete, unreadable, or does not match the visible books. Stop rather than copying an empty or partial library."
            case .changed: return "The files changed during copying or verification did not match. Nothing was reported as a successful copy."
            case .cleanup(let message): return message
            }
        }
    }
}
