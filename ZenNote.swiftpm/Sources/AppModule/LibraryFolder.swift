import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZenNoteCore

/// Holding this object retains directory permission for PDFKit's lazy reads and
/// background autosave. The writer also holds it until its IO has finished.
final class LibraryFolderAccess {
    let url: URL
    let identity: NSObject?

    init(url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else { throw StorageError.libraryUnavailable }
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileResourceIdentifierKey])
            guard values.isDirectory == true else { throw StorageError.libraryUnavailable }
            self.url = url
            identity = values.fileResourceIdentifier as? NSObject
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    deinit { url.stopAccessingSecurityScopedResource() }

    func remember(at bookmarkURL: URL) throws {
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.createDirectory(at: bookmarkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: bookmarkURL, options: .atomic)
    }

    static func restore(from bookmarkURL: URL) throws -> LibraryFolderAccess {
        let data = try Data(contentsOf: bookmarkURL)
        var stale = false
        let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        let access = try LibraryFolderAccess(url: url)
        // A stale bookmark may still resolve after a rename. Refresh only after
        // access succeeds; inability to refresh must not destroy the old token.
        if stale { try access.remember(at: bookmarkURL) }
        return access
    }
}

@MainActor
struct LibraryFolderPicker: UIViewControllerRepresentable {
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
