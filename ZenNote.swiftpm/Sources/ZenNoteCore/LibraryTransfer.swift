import Foundation

/// Runtime migration, not a test harness. Copies into staging, verifies bytes
/// using bounded buffers, and publishes the catalog last. Never deletes source.
public enum LibraryTransfer {
    public static func isEmpty(_ store: DiskStore) throws -> Bool {
        try store.withRoot(writing: false) { try meaningfulContents($0).isEmpty }
    }

    public static func createEmpty(at destination: DiskStore, preferences: Data) throws -> LibraryCatalog {
        try destination.withRoot(writing: true) { root in
            guard try meaningfulContents(root).isEmpty else { throw StorageError.destinationNotEmpty }
            let catalog = LibraryCatalog()
            try stageAndPublish(at: root) { stage in
                let disk = DiskStore(root: stage)
                try disk.write("preferences.json", data: preferences)
                try disk.write("library.json", data: DiskStore.encode(catalog))
            }
            return catalog
        }
    }

    public static func copy(from source: DiskStore, to destination: DiskStore) throws -> LibraryCatalog {
        let sourcePath = source.root.standardizedFileURL.path
        let targetPath = destination.root.standardizedFileURL.path
        guard sourcePath != targetPath, !targetPath.hasPrefix(sourcePath + "/"), !sourcePath.hasPrefix(targetPath + "/") else {
            throw StorageError.overlappingLibraries
        }
        return try source.withRoot(writing: false) { sourceRoot in
            // Already inside the source's coordination scope: do not recursively
            // coordinate the same directory while loading metadata.
            let sourceDisk = DiskStore(root: sourceRoot)
            guard try sourceDisk.read("library.json") != nil else { throw StorageError.missingCatalog }
            var catalog = try sourceDisk.loadCatalog()
            if catalog.libraryID == nil { catalog.libraryID = UUID() }
            try validate(catalog, in: sourceDisk)
            return try destination.withRoot(writing: true) { targetRoot in
                guard try meaningfulContents(targetRoot).isEmpty else { throw StorageError.destinationNotEmpty }
                try stageAndPublish(at: targetRoot) { stage in
                    for item in try meaningfulContents(sourceRoot) {
                        try FileManager.default.copyItem(at: item, to: stage.appendingPathComponent(item.lastPathComponent))
                    }
                    try verifyCopiedFiles(from: sourceRoot, to: stage)
                    let staged = DiskStore(root: stage)
                    try staged.write("library.json", data: DiskStore.encode(catalog))
                    try validate(catalog, in: staged)
                }
                return catalog
            }
        }
    }

    private static func meaningfulContents(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
    }

    private static func validate(_ catalog: LibraryCatalog, in store: DiskStore) throws {
        guard catalog.schemaVersion == 1, Set(catalog.books.map(\.id)).count == catalog.books.count else {
            throw StorageError.invalidLibrary
        }
        for book in catalog.books {
            _ = try store.loadBook(book.id)
            let values = try store.pdfURL(for: book.id).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StorageError.invalidLibrary }
        }
    }

    private static func stageAndPublish(at root: URL, populate: (URL) throws -> Void) throws {
        let stage = root.appendingPathComponent(".zen-note-transfer-" + UUID().uuidString, isDirectory: true)
        var published: [URL] = []
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
            try populate(stage)
            let items = try meaningfulContents(stage).sorted {
                if $0.lastPathComponent == "library.json" { return false }
                if $1.lastPathComponent == "library.json" { return true }
                return $0.lastPathComponent < $1.lastPathComponent
            }
            for item in items {
                let target = root.appendingPathComponent(item.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: target.path) else { throw StorageError.destinationNotEmpty }
                try FileManager.default.moveItem(at: item, to: target)
                published.append(target)
            }
            try FileManager.default.removeItem(at: stage)
        } catch {
            let primary = error.localizedDescription
            var cleanupFailures: [String] = []
            // Only remove paths created by this transfer, never the source or
            // anything that existed at the selected destination beforehand.
            for item in published.reversed() + [stage] {
                do {
                    if FileManager.default.fileExists(atPath: item.path) { try FileManager.default.removeItem(at: item) }
                } catch { cleanupFailures.append(error.localizedDescription) }
            }
            if !cleanupFailures.isEmpty { throw TransferCleanupError(message: primary + " Temporary-copy cleanup failed: " + cleanupFailures.joined(separator: "; ") + ". The original library is unchanged.") }
            throw error
        }
    }

    private static func verifyCopiedFiles(from source: URL, to destination: URL) throws {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            errorHandler: { _, error in enumerationError = error; return false }) else { throw StorageError.invalidLibrary }
        for case let file as URL in enumerator {
            if file.lastPathComponent == ".DS_Store" { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw StorageError.invalidLibrary }
            guard values.isRegularFile == true else { continue }
            let prefix = source.path + "/"
            guard file.path.hasPrefix(prefix) else { throw StorageError.unsafePath }
            let relative = String(file.path.dropFirst(prefix.count))
            let left = try FileHandle(forReadingFrom: file)
            defer { try? left.close() }
            let right = try FileHandle(forReadingFrom: destination.appendingPathComponent(relative))
            defer { try? right.close() }
            while true {
                let a = try left.read(upToCount: 65_536) ?? Data()
                let b = try right.read(upToCount: 65_536) ?? Data()
                guard a == b else { throw StorageError.invalidLibrary }
                if a.isEmpty { break }
            }
        }
        if let enumerationError { throw enumerationError }
    }

    private struct TransferCleanupError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
