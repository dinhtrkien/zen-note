import SwiftUI
import UniformTypeIdentifiers
import ZenNoteCore

@MainActor
struct ContentView: View {
    @ObservedObject var app: AppModel
    @State private var importing = false

    var body: some View {
        ZStack {
            if let session = app.session {
                WorkspaceView(app: app, session: session)
                    .id(session.record.id)
            } else {
                library
            }
            if app.busy {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView("Opening your book…")
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .tint(.teal)
        .disabled(app.busy)
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

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "book.pages").font(.title).foregroundStyle(.teal)
                VStack(alignment: .leading) {
                    Text("Zen Note").font(.title2.bold())
                    Text("Your textbook. Your notes. Together.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { importing = true } label: { Label("Import PDF", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!app.libraryAvailable)
            }.padding(24)
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
