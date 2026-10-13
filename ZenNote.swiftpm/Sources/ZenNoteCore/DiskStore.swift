import Foundation

public enum StorageError: LocalizedError {
    case unsupportedVersion(Int), unsafePath, missingBookState, missingCatalog
    case libraryUnavailable, libraryChanged, coordinationFailed, destinationNotEmpty, overlappingLibraries, invalidLibrary

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Unsupported saved-data version (\(version)). Existing files have not been replaced."
        case .unsafePath: return "Invalid local storage path."
        case .missingBookState: return "This book's saved metadata is missing. Existing drawing files have not been replaced."
        case .missingCatalog: return "The library index is missing. Reselect your existing library folder; no empty replacement was created."
        case .libraryUnavailable: return "The library folder is unavailable. Reconnect it in Files; existing data has not been replaced."
        case .libraryChanged: return "This location now contains a different library. Reconnect the original folder; unsaved drafts have not been written to the replacement."
        case .coordinationFailed: return "The file provider could not complete access to the library."
        case .destinationNotEmpty: return "Choose an empty folder for a new library, or a folder containing an existing Zen Note library. No files were overwritten."
        case .overlappingLibraries: return "Choose a separate folder, not the library itself or one of its parent/child folders."
        case .invalidLibrary: return "The folder's library is incomplete or invalid. Existing files have not been replaced."
        }
    }
}

/// A private v1 store or a user-selected Files library. External directories are
/// never silently recreated: losing access must produce a reconnect prompt.
public struct DiskStore: Sendable {
    public let root: URL
    public let coordinatesAccess: Bool
    public let expectedLibraryID: UUID?

    public init(root: URL, coordinatesAccess: Bool = false, expectedLibraryID: UUID? = nil) {
        self.root = root
        self.coordinatesAccess = coordinatesAccess
        self.expectedLibraryID = expectedLibraryID
    }

    public func bookPath(_ id: UUID, _ file: String) -> String { "books/\(id.uuidString)/\(file)" }
    public func pdfURL(for id: UUID) -> URL { root.appendingPathComponent(bookPath(id, "document.pdf")) }

    public func loadCatalog() throws -> LibraryCatalog {
        guard let data = try read("library.json") else {
            if coordinatesAccess { throw StorageError.missingCatalog }
            return LibraryCatalog()
        }
        let catalog = try JSONDecoder().decode(LibraryCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else { throw StorageError.unsupportedVersion(catalog.schemaVersion) }
        guard Set(catalog.books.map(\.id)).count == catalog.books.count else { throw StorageError.invalidLibrary }
        return catalog
    }

    public func loadBook(_ id: UUID) throws -> BookState {
        guard let data = try read(bookPath(id, "state.json")) else { throw StorageError.missingBookState }
        let state = try JSONDecoder().decode(BookState.self, from: data)
        guard state.schemaVersion == 1 else { throw StorageError.unsupportedVersion(state.schemaVersion) }
        return state
    }

    public func read(_ path: String) throws -> Data? {
        let url = try checkedURL(path, root: root)
        let exists = try withRoot(writing: false) { root in
            FileManager.default.fileExists(atPath: try self.checkedURL(path, root: root).path)
        }
        guard exists else { return nil }
        return try coordinated(at: url, writing: false) { try Data(contentsOf: $0) }
    }

    public func write(_ path: String, data: Data) throws {
        try withRoot(writing: true) { root in
            let url = try self.checkedURL(path, root: root)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Coordinate the actual PDF file so providers can download it before PDFKit
    /// opens it. The directory's security scope remains held by the app.
    public func withPDF<T>(for id: UUID, _ body: @escaping (URL) throws -> T) throws -> T {
        try withRoot(writing: false) { _ in () }
        return try coordinated(at: pdfURL(for: id), writing: false, body)
    }

    /// Copy, never depend on continued access to the Files source URL.
    public func copyPDF(from source: URL, to id: UUID) throws {
        try prepareRoot(writing: true)
        #if canImport(Darwin)
        var coordinationError: NSError?
        var outcome: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: root, options: [], error: &coordinationError) { source, root in
            outcome = Result { try self.copyPDFUncoordinated(from: source, to: id, root: root) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw StorageError.coordinationFailed }
        try outcome.get()
        #else
        try copyPDFUncoordinated(from: source, to: id, root: root)
        #endif
    }

    private func copyPDFUncoordinated(from source: URL, to id: UUID, root: URL) throws {
        try checkIdentity(at: root)
        let destination = try checkedURL(bookPath(id, "document.pdf"), root: root)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func removeUnfinishedImport(_ id: UUID) throws {
        try withRoot(writing: true) { root in
            let directory = try self.checkedURL(self.bookPath(id, "document.pdf"), root: root).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
    }

    public func withRoot<T>(writing: Bool, _ body: @escaping (URL) throws -> T) throws -> T {
        try prepareRoot(writing: writing)
        return try coordinated(at: root, writing: writing) { root in
            try self.checkIdentity(at: root)
            return try body(root)
        }
    }

    /// A directory replaced at the old URL must not receive another library's
    /// pending drafts. Preparing an empty destination uses an unbound store.
    private func checkIdentity(at root: URL) throws {
        guard let expectedLibraryID else { return }
        let index = root.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: index.path) else { throw StorageError.missingCatalog }
        let catalog = try JSONDecoder().decode(LibraryCatalog.self, from: Data(contentsOf: index))
        guard catalog.schemaVersion == 1 else { throw StorageError.unsupportedVersion(catalog.schemaVersion) }
        guard catalog.libraryID == expectedLibraryID else { throw StorageError.libraryChanged }
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func prepareRoot(writing: Bool) throws {
        if coordinatesAccess {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
                throw StorageError.libraryUnavailable
            }
        } else if writing {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    private func coordinated<T>(at url: URL, writing: Bool, _ body: @escaping (URL) throws -> T) throws -> T {
        #if canImport(Darwin)
        if coordinatesAccess {
            var coordinationError: NSError?
            var outcome: Result<T, Error>?
            let coordinator = NSFileCoordinator()
            if writing {
                coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { location in outcome = Result { try body(location) } }
            } else {
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in outcome = Result { try body(location) } }
            }
            if let coordinationError { throw coordinationError }
            guard let outcome else { throw StorageError.coordinationFailed }
            return try outcome.get()
        }
        #endif
        return try body(url)
    }

    private func checkedURL(_ path: String, root: URL) throws -> URL {
        let components = path.split(separator: "/")
        guard root.isFileURL, !components.isEmpty, !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains("\0"),
              !components.contains(".."), !components.contains(".") else { throw StorageError.unsafePath }

        // Normalize the existing root ONCE, not a nonexistent drawing path.
        // Foundation can standardize existing and missing paths differently
        // (notably /var vs /private/var). Missing sidecars are normal: viewing
        // an unwritten sheet must return nil without creating a file.
        let base = root.resolvingSymlinksInPath()
        var url = base
        for component in components {
            url.appendPathComponent(String(component))
            // Allow system aliases in the selected root, not links inside the
            // library that could redirect a read/write outside that root.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
                throw StorageError.unsafePath
            }
        }
        let baseComponents = base.pathComponents, itemComponents = url.pathComponents
        guard itemComponents.count > baseComponents.count,
              itemComponents.starts(with: baseComponents) else { throw StorageError.unsafePath }
        return url
    }
}

/// Owned by the application's serial IO queue. Failed writes remain available
/// for retry; new snapshots replace older snapshots of the same relative file.
public struct PendingWrites {
    private var files: [String: Data] = [:]
    public init() {}
    public var isEmpty: Bool { files.isEmpty }
    public var count: Int { files.count }
    public func data(for path: String) -> Data? { files[path] }

    public mutating func stage(_ updates: [String: Data]) { files.merge(updates) { _, newest in newest } }

    public mutating func flush(write: (String, Data) throws -> Void) throws {
        let paths = files.keys.sorted {
            let left = Self.priority($0), right = Self.priority($1)
            return left == right ? $0 < $1 : left < right
        }
        for path in paths {
            guard let data = files[path] else { continue }
            try write(path, data)
            files.removeValue(forKey: path)
        }
    }

    private static func priority(_ path: String) -> Int {
        if path.hasSuffix(".drawing") { return 0 }
        if path == "library.json" { return 2 }
        return 1
    }
}
