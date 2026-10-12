import Foundation

public enum StorageError: LocalizedError {
    case unsupportedVersion(Int)
    case unsafePath
    case missingBookState

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Unsupported saved-data version (\(version)). Existing files have not been replaced."
        case .unsafePath: return "Invalid local storage path."
        case .missingBookState: return "This book's saved metadata is missing. Existing drawing files have not been replaced."
        }
    }
}

/// All PDFs stay untouched after import. Editable PencilKit drawings are small,
/// per-page sidecars: autosave never serializes an entire textbook.
public struct DiskStore: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    public func bookPath(_ id: UUID, _ file: String) -> String {
        "books/\(id.uuidString)/\(file)"
    }

    public func pdfURL(for id: UUID) -> URL {
        root.appendingPathComponent(bookPath(id, "document.pdf"))
    }

    public func loadCatalog() throws -> LibraryCatalog {
        guard let data = try read("library.json") else { return LibraryCatalog() }
        let catalog = try JSONDecoder().decode(LibraryCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else { throw StorageError.unsupportedVersion(catalog.schemaVersion) }
        return catalog
    }

    public func loadBook(_ id: UUID) throws -> BookState {
        guard let data = try read(bookPath(id, "state.json")) else { return BookState() }
        let state = try JSONDecoder().decode(BookState.self, from: data)
        guard state.schemaVersion == 1 else { throw StorageError.unsupportedVersion(state.schemaVersion) }
        return state
    }

    public func read(_ path: String) throws -> Data? {
        let url = try checkedURL(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ path: String, data: Data) throws {
        let url = try checkedURL(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Copy, do not depend on continued access to the Files/iCloud source URL.
    public func copyPDF(from source: URL, to id: UUID) throws {
        let destination = pdfURL(for: id)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func removeUnfinishedImport(_ id: UUID) throws {
        let directory = pdfURL(for: id).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func checkedURL(_ path: String) throws -> URL {
        // Paths are generated internally, but still reject traversal at the IO boundary.
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.split(separator: "/").contains("..") else { throw StorageError.unsafePath }
        let url = root.appendingPathComponent(path).standardizedFileURL
        let prefix = root.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(prefix) else { throw StorageError.unsafePath }
        return url
    }
}

/// Used exclusively on the application's serial IO queue. A failed write leaves
/// all unsaved data available for retry; new snapshots replace older snapshots.
public struct PendingWrites {
    private var files: [String: Data] = [:]
    public init() {}
    public var isEmpty: Bool { files.isEmpty }
    public var count: Int { files.count }
    public func data(for path: String) -> Data? { files[path] }

    public mutating func stage(_ updates: [String: Data]) {
        files.merge(updates) { _, newest in newest }
    }

    public mutating func flush(write: (String, Data) throws -> Void) throws {
        // Drawing first, book metadata next, library last. A new sheet is not
        // published on disk before its drawing has been saved successfully.
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
