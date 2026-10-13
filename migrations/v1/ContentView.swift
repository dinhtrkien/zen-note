// ONE-TIME V1 MIGRATION: REPLACE the OLD ContentView.swift; do not add a second file.
// Keep every other v1 source and its Package.swift unchanged. Never paste into v2.
// THUNK-COMPATIBLE PATH-FIX REVISION: canonical file checks; first-selection handoff.
import Foundation
import ZenNoteCore
#if !ZENNOTE_MIGRATION_PORTABLE
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @ObservedObject var app: AppModel
    @State private var importing = false
    @State private var choosingMigrationFolder = false
    @StateObject private var migration = V1MigrationController()

    var body: some View {
        ZStack {
            mainContent
            if app.busy {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView(migration.isCopying ? migration.status : "Opening your book…")
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .tint(.teal)
        .disabled(app.busy)
        .sheet(isPresented: $choosingMigrationFolder, onDismiss: {
            migration.folderPickerDismissed(app: app)
        }) {
            V1MigrationFolderPicker(onSelect: { folder in
                migration.folderSelected(folder, app: app)
                choosingMigrationFolder = false
            }, onCancel: {
                migration.folderSelectionCancelled()
                choosingMigrationFolder = false
            })
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let urls): if let url = urls.first { app.importPDF(url) }
                case .failure(let error): app.issue = error.localizedDescription
                }
            }
        }
        .alert("Zen Note", isPresented: Binding(get: { app.issue != nil }, set: { if !$0 { app.issue = nil } })) {
            Button("OK", role: .cancel) { app.issue = nil }
        } message: { Text(app.issue ?? "") }
    }

    private var mainContent: AnyView {
        if let session = app.session {
            return AnyView(WorkspaceView(app: app, session: session).id(session.record.id))
        }
        return AnyView(library)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "book.pages").font(.title).foregroundStyle(.teal)
                VStack(alignment: .leading) {
                    Text("Zen Note").font(.title2.bold())
                    Text("Your textbook. Your notes. Together.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    migration.beginFolderChoice()
                    choosingMigrationFolder = true
                } label: {
                    Label("Copy library to Files", systemImage: "folder")
                }.buttonStyle(.bordered)
                    .disabled(!app.libraryAvailable || app.catalog.books.isEmpty)
                Button { importing = true } label: { Label("Import PDF", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!app.libraryAvailable)
            }.padding(24)
            Text(migration.status)
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 12)
            saveFailure
            if !app.libraryAvailable {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("Saved data could not be opened").font(.headline)
                    Text("Existing files are preserved. Do not remove Swift Playgrounds or this project to troubleshoot.")
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.catalog.books.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 46)).foregroundStyle(.teal)
                    Text("Start with a textbook").font(.title3.bold())
                    Text("Import a PDF from Files. Books, annotations, and linked notes stay on this iPad.")
                        .foregroundStyle(.secondary)
                    Text("If your pen doesn't write in Stylus mode, select the touch-style input fallback in the workspace.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.catalog.books) { book in
                    Button { app.openBook(book) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "book.closed").font(.title2).foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title).font(.headline).foregroundStyle(.primary)
                                Text("\(book.pageCount) pages · stored on this iPad").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }.listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var saveFailure: some View {
        if let error = app.saveError {
            HStack {
                Text(error).font(.footnote)
                Spacer()
                Button("Retry saves") { app.writer.retry() }
            }.padding().background(Color.orange.opacity(0.15))
        }
    }
}

@MainActor
private struct WorkspaceView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var session: BookSession
    @State private var dividerStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { app.closeBook() } label: { Label("Books", systemImage: "chevron.left") }
                Text(session.record.title).font(.headline).lineLimit(1)
                Spacer()
                Label(app.saveError == nil ? "Local autosave" : "Save needs attention", systemImage: app.saveError == nil ? "internaldrive" : "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(app.saveError == nil ? Color.secondary : Color.orange)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            toolbar
            if let error = app.saveError {
                HStack {
                    Text(error).font(.footnote)
                    Spacer()
                    Button("Retry saves") { app.writer.retry() }
                }.padding(10).background(Color.orange.opacity(0.15))
            }
            GeometryReader { geometry in
                let available = max(0, geometry.size.width - 18)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        pdfHeader
                        PDFReader(session: session, app: app)
                    }.frame(width: available * CGFloat(app.settings.divider))
                    divider(totalWidth: available)
                    VStack(spacing: 0) {
                        noteHeader
                        Notebook(session: session, app: app)
                    }.frame(width: available * CGFloat(1 - app.settings.divider))
                }
            }
            HStack {
                Text(app.navigating ? "Navigate mode · writing is off" :
                    app.settings.input == .compatible ? "Touch-style pen · use two fingers to navigate, or tap the hand" : "Pen writes · fingers navigate")
                Spacer()
                Text("Notes follow the PDF page at the center of the left pane")
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("Writing tool", selection: $app.settings.tool) {
                Label("Pen", systemImage: "pencil.tip").tag(DrawingSettings.Tool.pen)
                Label("Marker", systemImage: "highlighter").tag(DrawingSettings.Tool.highlighter)
                Label("Eraser", systemImage: "eraser").tag(DrawingSettings.Tool.eraser)
            }.pickerStyle(.segmented).frame(width: 250)
            Menu {
                ForEach(DrawingSettings.Ink.allCases, id: \.self) { ink in
                    Button { app.settings.activeInk = ink } label: {
                        Label(ink.rawValue.capitalized, systemImage: app.settings.activeInk == ink ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: { Circle().fill(Color(uiColor: app.settings.activeInk.color)).frame(width: 22, height: 22) }
                .accessibilityLabel("Ink color")
            Menu {
                Button("Fine") { app.settings.width = 1.5 }
                Button("Medium") { app.settings.width = 2.5 }
                Button("Thick") { app.settings.width = 5 }
            } label: { Label("Width", systemImage: "lineweight") }
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!session.canUndo).accessibilityLabel("Undo on last writing surface")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!session.canRedo).accessibilityLabel("Redo on last writing surface")
            Spacer(minLength: 4)
            Menu {
                ForEach(DrawingSettings.Input.allCases, id: \.self) { input in
                    Button { app.settings.input = input } label: {
                        Label(input.title, systemImage: app.settings.input == input ? "checkmark" : "pencil")
                    }
                }
            } label: { Label("Input", systemImage: "pencil.and.outline") }
            Button { app.navigating.toggle() } label: {
                Image(systemName: "hand.draw").padding(6)
                    .background(app.navigating ? Color.teal.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }.accessibilityLabel(app.navigating ? "Enable writing" : "Navigate without writing")
        }.padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
    }

    private var pdfHeader: some View {
        HStack {
            Text("PDF \(session.activePage + 1) / \(session.document.pageCount)").font(.subheadline.monospacedDigit())
            Spacer(minLength: 4)
            Button { session.jumpToPage?(session.activePage - 1) } label: { Image(systemName: "chevron.up") }
                .disabled(session.activePage == 0).accessibilityLabel("Previous PDF page")
            Button { session.jumpToPage?(session.activePage + 1) } label: { Image(systemName: "chevron.down") }
                .disabled(session.activePage + 1 >= session.document.pageCount).accessibilityLabel("Next PDF page")
        }.padding(.horizontal, 12).frame(height: 42)
    }

    private var noteHeader: some View {
        let sheets = session.visibleSheets
        let selected = session.selectedSheet
        let index = sheets.firstIndex(where: { $0.id == selected.id }) ?? 0
        return HStack(spacing: 12) {
            Text("Notes \(index + 1) / \(sheets.count)").font(.subheadline.monospacedDigit())
            Spacer(minLength: 0)
            Menu {
                Button("Grid") { session.changePaper(.grid) }
                Button("Blank") { session.changePaper(.blank) }
            } label: { Image(systemName: selected.paper == .grid ? "square.grid.3x3" : "square") }
                .accessibilityLabel("Note paper")
            Button { session.selectSheet(sheets[index - 1].id, on: session.activePage) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0).accessibilityLabel("Previous note sheet")
            Button { session.selectSheet(sheets[index + 1].id, on: session.activePage) } label: { Image(systemName: "chevron.right") }
                .disabled(index + 1 >= sheets.count).accessibilityLabel("Next note sheet")
            Button { session.addSheet() } label: { Image(systemName: "plus") }.accessibilityLabel("Add note sheet")
        }.padding(.horizontal, 12).frame(height: 42)
    }

    private func divider(totalWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.25))
            .frame(width: 4, height: 48)
            .frame(width: 18).frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dividerStart ?? app.settings.divider
                    dividerStart = start
                    app.settings.divider = min(0.72, max(0.28, start + Double(value.translation.width / max(1, totalWidth))))
                }
                .onEnded { _ in dividerStart = nil })
            .accessibilityLabel("Resize PDF and notebook panes")
            .accessibilityAdjustableAction { direction in
                let step: Double = direction == .increment ? 0.05 : -0.05
                app.settings.divider = min(0.72, max(0.28, app.settings.divider + step))
            }
    }
}

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
    @Published private(set) var status = "Ready to copy. Choose an empty local Files folder; original data stays here."
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var selectedFolder: URL?
    private var pickerDismissed = false

    // UIKit may deliver selection either before or after SwiftUI's onDismiss.
    // Keep both events in this stable controller, consume the URL exactly once,
    // and never begin copying while the folder picker is still presented.
    func beginFolderChoice() {
        selectedFolder = nil
        pickerDismissed = false
        status = "Choose an empty local Files folder. Original data stays here."
    }

    func folderSelected(_ folder: URL, app: AppModel) {
        selectedFolder = folder
        status = "Folder selected; waiting for the picker to close…"
        copyIfReady(app: app)
    }

    func folderSelectionCancelled() {
        selectedFolder = nil
        status = "Folder selection cancelled. Original data was not changed."
    }

    func folderPickerDismissed(app: AppModel) {
        pickerDismissed = true
        copyIfReady(app: app)
    }

    private func copyIfReady(app: AppModel) {
        guard pickerDismissed, let folder = selectedFolder else { return }
        selectedFolder = nil
        copy(app: app, to: folder)
    }

    private func copy(app: AppModel, to folder: URL) {
        guard !app.busy, !isCopying else { return }
        guard app.libraryAvailable, app.session == nil else {
            status = "Return to Books with the original library open before copying."
            app.issue = status
            return
        }
        guard !app.catalog.books.isEmpty else {
            status = "No old books are visible. Stop here; an empty library is not a successful migration."
            app.issue = status
            return
        }
        guard folder.startAccessingSecurityScopedResource() else {
            status = "Files did not grant access to this folder. Choose another empty local folder. The original library was not changed."
            app.issue = status
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
                let result = V1MigrationCopy.copy(from: source, to: folder, expectedBookIDs: expectedIDs)
                DispatchQueue.main.async { [self, app] in
                    switch result {
                    case .success(let receipt):
                        finish(app: app, folder: folder, message: "Copied and byte-verified \(receipt.books) books and \(receipt.files) files into “\(folder.lastPathComponent)”. Original data is retained. Now open the NEW Zen Note project, choose this EXISTING folder, and check your notes before deleting anything.")
                    case .failure(let error):
                        finish(app: app, folder: folder, message: "Copy failed: \(error.localizedDescription) Original data was not deleted. Keep this project and destination unchanged, and report this exact message before retrying.")
                    }
                }
            }
        }
    }

    private func finish(app: AppModel, folder: URL, message: String) {
        folder.stopAccessingSecurityScopedResource()
        endBackgroundTask()
        isCopying = false
        status = message
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

    // Playgrounds generates thunks for declarations in SwiftUI source files.
    // Keep the member API non-throwing: generated forwarding calls then need no
    // `try`. Throwing implementation helpers are local, not type members.
    // The user confirmed this thunk-compatible shape launches on iPad.
    // Export errors remain explicit; no partial library is treated as success.
    static func copy(from source: URL, to destination: URL, expectedBookIDs: Set<UUID>) -> Result<Receipt, Error> {
        func contents(_ root: URL) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
        }

        func files(in root: URL) throws -> [String] {
            // iOS can expose the same sandbox via /var and /private/var aliases.
            // Enumerate and compare canonical URLs, never mixed raw spellings.
            let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(at: canonicalRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                errorHandler: { _, error in enumerationError = error; return false }) else {
                throw CopyError.incomplete("ENUM_UNAVAILABLE: cannot enumerate \(canonicalRoot.path).")
            }
            var paths: [String] = []
            // Component comparison also avoids trailing-slash ambiguity and
            // cannot confuse sibling directory names with descendants.
            let rootComponents = canonicalRoot.pathComponents
            for case let item as URL in enumerator {
                if item.lastPathComponent == ".DS_Store" { continue }
                let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                // Check before resolving the item so a symlink cannot be hidden
                // by canonicalization. Links/special files remain forbidden.
                guard values.isSymbolicLink != true else {
                    throw CopyError.incomplete("LINK_REJECTED: \(item.lastPathComponent) is a symbolic link.")
                }
                if values.isDirectory == true { continue }
                guard values.isRegularFile == true else {
                    throw CopyError.incomplete("FILE_NOT_REGULAR: \(item.path), regular=\(String(describing: values.isRegularFile)), directory=\(String(describing: values.isDirectory)).")
                }
                let canonicalItem = item.resolvingSymlinksInPath().standardizedFileURL
                let itemComponents = canonicalItem.pathComponents
                guard itemComponents.count > rootComponents.count,
                      Array(itemComponents.prefix(rootComponents.count)) == rootComponents else {
                    throw CopyError.incomplete("FILE_OUTSIDE_LIBRARY: item=\(canonicalItem.path), root=\(canonicalRoot.path).")
                }
                paths.append(itemComponents.dropFirst(rootComponents.count).joined(separator: "/"))
            }
            if let enumerationError { throw enumerationError }
            return paths.sorted()
        }

        func compare(_ original: URL, _ copied: URL) throws {
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

        func validate(_ catalog: LibraryCatalog, in disk: DiskStore) throws {
            for book in catalog.books {
                guard let data = try disk.read(disk.bookPath(book.id, "state.json")) else {
                    throw CopyError.incomplete("BOOK_STATE_MISSING: books/\(book.id.uuidString)/state.json is absent in \(disk.root.path).")
                }
                let state: BookState
                do { state = try JSONDecoder().decode(BookState.self, from: data) }
                catch {
                    throw CopyError.incomplete("BOOK_STATE_UNREADABLE: book \(book.id.uuidString): \(error.localizedDescription)")
                }
                guard state.schemaVersion == 1 else {
                    throw CopyError.incomplete("BOOK_STATE_VERSION: book \(book.id.uuidString) has schema \(state.schemaVersion), expected 1.")
                }
                let pdf: URLResourceValues
                do { pdf = try disk.pdfURL(for: book.id).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) }
                catch {
                    throw CopyError.incomplete("PDF_UNREADABLE: book \(book.id.uuidString): \(error.localizedDescription)")
                }
                guard pdf.isRegularFile == true, pdf.isSymbolicLink != true, (pdf.fileSize ?? 0) > 0 else {
                    throw CopyError.incomplete("PDF_INVALID: book \(book.id.uuidString), regular=\(String(describing: pdf.isRegularFile)), link=\(String(describing: pdf.isSymbolicLink)), bytes=\(String(describing: pdf.fileSize)).")
                }
            }
        }

        func copyCoordinated(from source: URL, to destination: URL, expectedBookIDs: Set<UUID>) throws -> Receipt {
            let destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard destinationValues.isDirectory == true, destinationValues.isSymbolicLink != true else { throw CopyError.unavailable }
            guard try contents(destination).isEmpty else { throw CopyError.notEmpty }
            let disk = DiskStore(root: source)
            guard let index = try disk.read("library.json") else {
                throw CopyError.incomplete("CATALOG_MISSING: library.json is absent in \(source.path); visible books=\(expectedBookIDs.count).")
            }
            let catalog: LibraryCatalog
            do { catalog = try JSONDecoder().decode(LibraryCatalog.self, from: index) }
            catch { throw CopyError.incomplete("CATALOG_UNREADABLE: \(error.localizedDescription)") }
            guard catalog.schemaVersion == 1 else {
                throw CopyError.incomplete("CATALOG_VERSION: schema \(catalog.schemaVersion), expected 1.")
            }
            guard !catalog.books.isEmpty else {
                throw CopyError.incomplete("CATALOG_EMPTY: disk has zero books; visible books=\(expectedBookIDs.count).")
            }
            let storedIDs = Set(catalog.books.map(\.id))
            guard storedIDs.count == catalog.books.count else {
                throw CopyError.incomplete("CATALOG_DUPLICATE_IDS: \(catalog.books.count) records but \(storedIDs.count) distinct book IDs.")
            }
            guard storedIDs == expectedBookIDs else {
                throw CopyError.incomplete("CATALOG_ID_MISMATCH: disk books=\(storedIDs.count), visible books=\(expectedBookIDs.count), missing on disk=\(expectedBookIDs.subtracting(storedIDs).count), unexpected on disk=\(storedIDs.subtracting(expectedBookIDs).count).")
            }
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

        return Result {
            let sourceComponents = source.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            let destinationComponents = destination.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard !sourceComponents.starts(with: destinationComponents),
                  !destinationComponents.starts(with: sourceComponents) else { throw CopyError.overlap }
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
    }

    private enum CopyError: LocalizedError {
        case notEmpty, unavailable, overlap, changed
        case incomplete(String), cleanup(String)
        var errorDescription: String? {
            switch self {
            case .notEmpty: return "Choose an EMPTY folder. No existing library or other files will be overwritten."
            case .unavailable: return "Files could not provide a writable folder."
            case .overlap: return "Choose a separate destination, not the original library or its parent/child folders."
            case .incomplete(let detail): return "Library check failed [\(detail)] Stop rather than copying an empty or partial library."
            case .changed: return "The files changed during copying or verification did not match. Nothing was reported as a successful copy."
            case .cleanup(let message): return message
            }
        }
    }
}
