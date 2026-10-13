import SwiftUI
import ZenNoteCore

@MainActor
struct WorkspaceView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var session: BookSession
    let onChooseFolder: () -> Void
    @State private var dividerStart: Double?
    @State private var controlsVisible = true
    @State private var hideWork: DispatchWorkItem?

    private var pdfShown: Bool { app.settings.layout != .notes }
    private var notesShown: Bool { app.settings.layout != .textbook }
    private var floatingToolbar: Bool { session.zenMode && app.settings.zenToolbar == .autoHide }

    var body: some View {
        VStack(spacing: 0) {
            if !session.zenMode { header }
            if !session.zenMode || app.settings.zenToolbar == .docked { toolbar }
            ZStack(alignment: .topTrailing) {
                panes
                if floatingToolbar {
                    toolbar.padding(.trailing, 54).padding(8)
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
                        .accessibilityHidden(!controlsVisible)
                }
                if session.zenMode {
                    Button {
                        if floatingToolbar && !controlsVisible {
                            controlsVisible = true
                            session.activity()
                        } else { session.toggleZen() }
                    } label: {
                        Image(systemName: floatingToolbar && !controlsVisible ? "slider.horizontal.3" : "arrow.down.right.and.arrow.up.left")
                            .frame(width: 34, height: 34)
                            .background(Theme.controls, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain).padding(8)
                    .accessibilityLabel(floatingToolbar && !controlsVisible ? "Reveal controls" : "Exit zen mode")
                    .disabled(session.isDrawing && controlsVisible)
                }
            }
            if !session.zenMode { footer }
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            if let error = app.saveError {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).font(.footnote)
                    Spacer(minLength: 0)
                    Button("Retry") { app.writer.retry(); session.activity() }
                    Button("Reconnect", action: onChooseFolder).disabled(session.isDrawing)
                }.padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 8)).padding(8)
            }
        }
        .onAppear { armAutoHide() }
        .onDisappear { hideWork?.cancel() }
        .onChange(of: session.interactionCount) { _ in armAutoHide() }
        .onChange(of: session.isDrawing) { writing in
            if writing { controlsVisible = true }
            armAutoHide()
        }
        .onChange(of: session.zenMode) { _ in controlsVisible = true; armAutoHide() }
        .onChange(of: app.settings.zenToolbar) { _ in controlsVisible = true; armAutoHide() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { app.closeBook() } label: { Label("Books", systemImage: "chevron.left") }
                .disabled(session.isDrawing)
            Text(session.record.title).font(.headline).lineLimit(1)
            Spacer()
            if !app.isFilesLibrary {
                Button("Choose Files folder to write", action: onChooseFolder)
            } else {
                Label(app.folderName, systemImage: "folder").font(.caption).lineLimit(1)
                Button(action: onChooseFolder) { Image(systemName: "folder.badge.gearshape") }
                    .accessibilityLabel("Connect a library folder")
            }
            layoutMenu
            Button { session.toggleZen() } label: { Label("Zen", systemImage: "viewfinder") }
                .disabled(session.isDrawing)
        }.padding(.horizontal, 16).padding(.vertical, 10).background(Theme.controls)
            .disabled(session.isDrawing)
    }

    private var panes: some View {
        GeometryReader { geometry in
            let split = app.settings.layout == .split
            let available = max(0, geometry.size.width - (split ? 18 : 0))
            let pdfWidth = split ? available * CGFloat(app.settings.divider) : (pdfShown ? available : 0)
            let noteWidth = split ? available * CGFloat(1 - app.settings.divider) : (notesShown ? available : 0)
            // Keep both controllers mounted so layout switches preserve canvas
            // undo/zoom state. Hidden PDF tracking and note refresh are paused.
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !session.zenMode && pdfShown { pdfHeader }
                    PDFReader(session: session, app: app, presented: pdfShown)
                }.frame(width: pdfWidth).clipped().allowsHitTesting(pdfShown).accessibilityHidden(!pdfShown)
                divider(totalWidth: available).frame(width: split ? 18 : 0).clipped()
                    .allowsHitTesting(split && !session.isDrawing).accessibilityHidden(!split)
                VStack(spacing: 0) {
                    if !session.zenMode && notesShown { noteHeader }
                    Notebook(session: session, app: app, presented: notesShown)
                }.frame(width: noteWidth).clipped().allowsHitTesting(notesShown).accessibilityHidden(!notesShown)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                toolButton(.pen, title: "Pen", symbol: "pencil.tip")
                toolButton(.highlighter, title: "Marker", symbol: "highlighter")
                toolButton(.eraser, title: "Eraser", symbol: "eraser")
            }.padding(3).background(Theme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            Menu {
                ForEach(DrawingSettings.Ink.allCases, id: \.self) { ink in
                    Button { app.settings.activeInk = ink } label: {
                        Label(ink.rawValue.capitalized, systemImage: app.settings.activeInk == ink ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                Circle().fill(Color(uiColor: app.settings.activeInk.color)).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Theme.text.opacity(0.2), lineWidth: 0.5))
            }.accessibilityLabel("Ink color")
            Menu {
                Button("Fine") { app.settings.width = 1.5 }
                Button("Medium") { app.settings.width = 2.5 }
                Button("Thick") { app.settings.width = 5 }
            } label: { Image(systemName: "lineweight") }.accessibilityLabel("Pen width")
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!session.canUndo).accessibilityLabel("Undo on last writing surface")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!session.canRedo).accessibilityLabel("Redo on last writing surface")
            Spacer(minLength: 4)
            Text("PDF \(session.activePage + 1) · Notes \(session.notePage + 1)")
                .font(.caption.monospacedDigit()).lineLimit(1)
            Button { session.togglePin() } label: {
                Image(systemName: session.pinnedPage == nil ? "pin" : "pin.fill")
                    .foregroundStyle(session.pinnedPage == nil ? Theme.text : Theme.accent)
            }.accessibilityLabel(session.pinnedPage == nil ? "Pin this note set" : "Unpin and follow PDF")
            Button { session.addSheet() } label: { Image(systemName: "plus") }
                .disabled(!app.isFilesLibrary).accessibilityLabel("Add note sheet")
            Button { app.navigating.toggle() } label: {
                Image(systemName: "hand.draw").padding(5)
                    .background(app.navigating ? Theme.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }.accessibilityLabel(app.navigating ? "Enable writing" : "Navigate without writing")
            optionsMenu
        }.font(.subheadline).buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.controls, in: RoundedRectangle(cornerRadius: floatingToolbar ? 8 : 0))
            .disabled(session.isDrawing)
            .simultaneousGesture(TapGesture().onEnded { session.activity() })
    }

    private func toolButton(_ tool: DrawingSettings.Tool, title: String, symbol: String) -> some View {
        Button { app.settings.tool = tool } label: {
            Label(title, systemImage: symbol).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 7)
                .foregroundStyle(app.settings.tool == tool ? Theme.paper : Theme.text)
                .background(app.settings.tool == tool ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }

    private var optionsMenu: some View {
        Menu {
            Text("Notes attached to PDF page \(session.notePage + 1)")
            Picker("Layout", selection: $app.settings.layout) {
                ForEach(DrawingSettings.Layout.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            Button { session.toggleZen() } label: {
                Label(session.zenMode ? "Exit zen" : "Enter zen", systemImage: "viewfinder")
            }
            Picker("Zen toolbar", selection: $app.settings.zenToolbar) {
                ForEach(DrawingSettings.Toolbar.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }
            Divider()
            Menu("Note paper") {
                ForEach(PaperStyle.allCases, id: \.self) { style in
                    Button { session.changePaper(style) } label: {
                        Label(style.title, systemImage: session.selectedSheet.paper == style ? "checkmark" : style.symbol)
                    }
                }
            }.disabled(!app.isFilesLibrary)
            Button("Previous note sheet") { changeSheet(by: -1) }.disabled(sheetIndex == 0)
            Button("Next note sheet") { changeSheet(by: 1) }.disabled(sheetIndex + 1 >= session.visibleSheets.count)
            Button("Previous PDF page") { session.jumpToPage?(session.activePage - 1) }
                .disabled(!pdfShown || session.activePage == 0)
            Button("Next PDF page") { session.jumpToPage?(session.activePage + 1) }
                .disabled(!pdfShown || session.activePage + 1 >= session.document.pageCount)
            Divider()
            Picker("Input", selection: $app.settings.input) {
                ForEach(DrawingSettings.Input.allCases, id: \.self) { input in Text(input.title).tag(input) }
            }
            Button("Library folder", action: onChooseFolder)
            Button("Back to books") { app.closeBook() }
        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 24, minHeight: 30) }
            .accessibilityLabel("Layout, zen, paper, and input controls")
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Layout", selection: $app.settings.layout) {
                ForEach(DrawingSettings.Layout.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
        } label: { Image(systemName: app.settings.layout.symbol) }
            .disabled(session.isDrawing).accessibilityLabel("Workspace layout")
    }

    private var pdfHeader: some View {
        HStack {
            Text("PDF \(session.activePage + 1) / \(session.document.pageCount)").font(.subheadline.monospacedDigit())
            Spacer(minLength: 4)
            Button { session.jumpToPage?(session.activePage - 1) } label: { Image(systemName: "chevron.up") }
                .disabled(session.activePage == 0).accessibilityLabel("Previous PDF page")
            Button { session.jumpToPage?(session.activePage + 1) } label: { Image(systemName: "chevron.down") }
                .disabled(session.activePage + 1 >= session.document.pageCount).accessibilityLabel("Next PDF page")
        }.padding(.horizontal, 12).frame(height: 42).disabled(session.isDrawing)
    }

    private var sheetIndex: Int {
        session.visibleSheets.firstIndex(where: { $0.id == session.selectedSheet.id }) ?? 0
    }

    private func changeSheet(by delta: Int) {
        let sheets = session.visibleSheets, next = sheetIndex + delta
        guard sheets.indices.contains(next) else { return }
        session.selectSheet(sheets[next].id, on: session.notePage)
    }

    private var noteHeader: some View {
        HStack(spacing: 10) {
            Text("Notes \(sheetIndex + 1)/\(session.visibleSheets.count) · PDF \(session.notePage + 1)")
                .font(.caption.monospacedDigit()).lineLimit(1)
            if session.pinnedPage != nil { Image(systemName: "pin.fill").foregroundStyle(Theme.accent) }
            Spacer(minLength: 0)
            Menu {
                ForEach(PaperStyle.allCases, id: \.self) { style in
                    Button(style.title) { session.changePaper(style) }
                }
            } label: { Image(systemName: session.selectedSheet.paper.symbol) }
                .disabled(!app.isFilesLibrary).accessibilityLabel("Note paper")
            Button { changeSheet(by: -1) } label: { Image(systemName: "chevron.left") }
                .disabled(sheetIndex == 0).accessibilityLabel("Previous note sheet")
            Button { changeSheet(by: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(sheetIndex + 1 >= session.visibleSheets.count).accessibilityLabel("Next note sheet")
        }.padding(.horizontal, 12).frame(height: 42).disabled(session.isDrawing)
    }

    private var footer: some View {
        HStack {
            Text(!app.isFilesLibrary ? "Read-only until a Files folder is chosen" : app.navigating ? "Navigate mode · writing is off" :
                app.settings.input == .compatible ? "Touch-style pen · two fingers navigate" : "Pen writes · fingers navigate")
            Spacer()
            Text(session.pinnedPage == nil ? "Notes follow the PDF" : "Pinned to PDF page \(session.notePage + 1)")
        }.font(.caption2).foregroundStyle(Theme.text.opacity(0.7))
            .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func divider(totalWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Theme.text.opacity(0.25))
            .frame(width: 4, height: 48).frame(width: 18).frame(maxHeight: .infinity)
            .background(Theme.controls).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dividerStart ?? app.settings.divider
                    dividerStart = start
                    app.settings.divider = min(0.72, max(0.28, start + Double(value.translation.width / max(1, totalWidth))))
                }.onEnded { _ in dividerStart = nil })
            .accessibilityLabel("Resize PDF and notebook panes")
            .accessibilityAdjustableAction { direction in
                let step: Double = direction == .increment ? 0.05 : -0.05
                app.settings.divider = min(0.72, max(0.28, app.settings.divider + step))
            }
    }

    private func armAutoHide() {
        hideWork?.cancel()
        guard floatingToolbar else { controlsVisible = true; return }
        guard !session.isDrawing else { return }
        let work = DispatchWorkItem {
            guard floatingToolbar, !session.isDrawing else { return }
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
