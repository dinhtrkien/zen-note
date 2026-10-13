import SwiftUI
import UniformTypeIdentifiers
import ZenNoteCore

@MainActor
struct ContentView: View {
    @ObservedObject var app: AppModel
    @State private var importing = false
    @State private var choosingFolder = false
    @State private var selectedFolder: URL?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let session = app.session {
                WorkspaceView(app: app, session: session, onChooseFolder: { choosingFolder = true })
                    .id(session.record.id)
            } else {
                library
            }
            if app.busy {
                Theme.text.opacity(0.08).ignoresSafeArea()
                ProgressView(app.busyMessage)
                    .padding(24).background(Theme.controls, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .disabled(app.busy)
        .sheet(isPresented: $choosingFolder, onDismiss: {
            guard let url = selectedFolder else { return }
            selectedFolder = nil
            app.prepareFolder(url)
        }) {
            LibraryFolderPicker(onSelect: { url in
                selectedFolder = url
                choosingFolder = false
            }, onCancel: { selectedFolder = nil; choosingFolder = false })
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let urls): if let url = urls.first { app.importPDF(url) }
                case .failure(let error): app.issue = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Files library", isPresented: Binding(
            get: { app.connectionQuestion != nil },
            set: { if !$0 { app.connectionQuestion = nil } }), titleVisibility: .visible) {
                Button("Use folder") { app.confirmFolder() }
                Button("Cancel", role: .cancel) { app.cancelFolder() }
            } message: { Text(app.connectionQuestion ?? "") }
        .alert("Zen Note", isPresented: Binding(get: { app.issue != nil }, set: { if !$0 { app.issue = nil } })) {
            Button("OK", role: .cancel) { app.issue = nil }
        } message: { Text(app.issue ?? "") }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "book.closed").font(.title).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zen Note").font(.title2.bold())
                    Text("Read. Think. Write.").font(.subheadline).foregroundStyle(Theme.text.opacity(0.7))
                }
                Spacer()
                Button { choosingFolder = true } label: {
                    Label(app.isFilesLibrary ? "Library folder" : "Choose Files folder", systemImage: "folder")
                }.buttonStyle(.bordered)
                Button { importing = true } label: { Label("Import PDF", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(!app.libraryAvailable || !app.isFilesLibrary)
            }.padding(24).background(Theme.controls)
            storageNotice
            if let error = app.saveError {
                HStack {
                    Text(error).font(.footnote)
                    Spacer()
                    Button("Retry") { app.writer.retry() }
                    Button("Reconnect") { choosingFolder = true }
                }.padding().background(Theme.paper)
            }
            if !app.libraryAvailable {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark").font(.largeTitle)
                    Text("Reconnect your library").font(.headline)
                    Text("Select its existing folder in Files. No empty replacement has been created.")
                    Button("Choose folder") { choosingFolder = true }.buttonStyle(.borderedProminent)
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.catalog.books.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: app.isFilesLibrary ? "doc.badge.plus" : "folder.badge.plus")
                        .font(.system(size: 46)).foregroundStyle(Theme.accent)
                    Text(app.isFilesLibrary ? "Start with a textbook" : "A home for your study notes").font(.title3.bold())
                    Text(app.isFilesLibrary ? "Import a PDF. Editable notes and annotations autosave alongside it in your library folder." :
                        "Choose an empty folder in Files, or reconnect an existing Zen Note library. Use a local folder outside Playgrounds for offline study.")
                        .multilineTextAlignment(.center).frame(maxWidth: 560)
                    if !app.isFilesLibrary {
                        Button("Choose Files folder") { choosingFolder = true }.buttonStyle(.borderedProminent)
                    }
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.catalog.books) { book in
                    Button { app.openBook(book) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "book.closed").font(.title2).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title).font(.headline).foregroundStyle(Theme.text)
                                Text("\(book.pageCount) pages").font(.subheadline).foregroundStyle(Theme.text.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.text.opacity(0.6))
                        }.padding(.vertical, 8)
                    }.listRowBackground(Theme.controls).listRowSeparatorTint(Theme.grid)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }

    private var storageNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: app.isFilesLibrary ? "folder" : "info.circle")
            Text(app.libraryError ?? (app.isFilesLibrary ? "Autosave: \(app.folderName) · keep a separate copy of this folder for backup." :
                app.catalog.books.isEmpty ? "Files is the primary library storage. Local folders work offline." :
                "Your private v1 library is retained. Choose a Files folder to copy it and enable writing; you can still read it here."))
                .font(.footnote)
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }
}
