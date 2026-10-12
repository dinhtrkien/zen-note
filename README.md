# Zen Note

A native, offline iPad study prototype: a vertically scrolling PDF on the left and fixed handwritten note sheets on the right. Notes follow the PDF page at the center of the reading pane. Each PDF page can own multiple horizontally browsed sheets.

The agreed scope is in [`docs/requirements.md`](docs/requirements.md). No subscriptions, server, accounts, cloud sync, export, lasso, or text-anchor system are included.

## Run on your iPad — no Mac or paid developer membership

1. Install Apple's free **Swift Playgrounds** on your iPad.
2. Transfer **`artifacts/ZenNote-iPad.zip`** to the iPad using Files or another file-transfer method.
3. Tap the ZIP in Files to extract it. Open **`ZenNote.swiftpm`** with Swift Playgrounds (use Share → Swift Playgrounds if necessary).
4. Rotate the iPad to landscape and tap **Run App**. Use the full-screen app, not just the editor's preview.
5. Tap **Import PDF** and select a test book from Files.

Generated archives are not versioned. After cloning, run `node scripts/package.mjs` to create the transfer ZIP. It contains only app sources and the Playgrounds manifest; no downloads or external package dependencies are needed by the app.

**Validation:** The user reports that the prototype is working on their iPad. Detailed acceptance testing is still in progress; the Windows development environment cannot compile or run the iPad UI. Linux Swift tests and syntax checks are not an iPad build. Follow [`docs/ipad-testing.md`](docs/ipad-testing.md), particularly the stylus and restart-persistence checks, before entrusting the prototype with valuable notes. Confirm the reported iPadOS version on the device.

## Controls

- **PDF:** scroll vertically; use the header arrows for previous/next page. Notes automatically follow the page at the viewport's center.
- **Notebook:** swipe horizontally at fit-to-page size, or use the header arrows. Tap **+** to add a fixed sheet. Choose **grid/blank** with the paper button.
- **Zoom:** pinch either pane independently. A zoomed note sheet pans rather than changing sheets; header arrows can still change sheets.
- **Divider:** drag the center handle to resize the panes.
- **Ink:** pen, freehand marker (yellow by default), bitmap eraser, ink color, and width. Undo/redo apply to the last-used writing surface and are session-local.
- **Input → Stylus + finger navigation:** PencilKit stylus input writes; fingers navigate. Start here for a third-party pencil that iPadOS recognizes as a stylus.
- **Input → Touch-style pen fallback:** enables drawing from touch-class input. Use **two fingers** to navigate, or tap the **hand** button to disable writing and navigate with one finger.

Some third-party pens report the same input as a finger. Software cannot reliably distinguish such a pen from a palm. The fallback provides a usable input route, **not a promise of universal palm rejection**. Compatibility with the user's actual pencil remains a device-test gate.

## Autosave and local data

- Imported PDFs are copied into the app's local Application Support directory. The source in Files is not modified and continued source-file access is not needed.
- PDF ink and notes use separate PencilKit drawing files. Scrolling a textbook does not create a canvas/file for every page or rewrite the complete PDF.
- Blank placeholders are not stored until first writing. Explicitly adding a sheet can store its empty metadata.
- Reading position, relative PDF zoom, selected note sheets, paper styles, and settings are stored locally.
- Completed strokes save promptly, changes are debounced during drawing, and visible surfaces flush on page changes, closing a book, and app deactivation.
- Files are atomically replaced on a serial IO queue; drawing files precede referencing metadata. Save failures remain visible with a **Retry saves** action. Do not close the app while unsaved changes are reported.
- There is **no export or backup feature** in v1. Removing app data/Swift Playgrounds, changing the app identity, or reinstalling/reimporting the project may lose access to the local sandbox. Keep the same project and bundle identifier. A force-stop during a write can lose the latest incomplete stroke; never treat this prototype as your only copy of irreplaceable work.
- Password-locked PDFs are rejected with a message rather than partially imported.

Storage layout:

```text
Application Support/ZenNote/
  library.json
  preferences.json
  books/<book UUID>/
    document.pdf
    state.json
    pdf/page-<index>.drawing
    notes/page-<index>/<sheet UUID>.drawing
```

## Development and validation

```sh
# On a host with Swift 5.9+; builds the Foundation core, not the iPad UI.
cd ZenNote.swiftpm
swift test

# From the repository root: create the transferable app and a synthetic book.
node scripts/package.mjs
node scripts/make-test-pdf.mjs 600

# With Python 3: verify archive CRCs/source integrity and PDF object offsets.
python scripts/validate-artifacts.py
```

Windows with Docker (Linux containers):

```sh
MSYS_NO_PATHCONV=1 docker run --rm \
  -v 'C:/Users/dinht/Desktop/zen-note/ZenNote.swiftpm:/workspace' \
  -w /workspace swift:6.1 swift test

MSYS_NO_PATHCONV=1 docker run --rm \
  -v 'C:/Users/dinht/Desktop/zen-note/ZenNote.swiftpm:/workspace:ro' \
  -w /workspace swift:6.1 bash -lc 'swiftc -frontend -parse Sources/AppModule/*.swift'
```

`swift test` exercises page linking, lazy note creation, paper/selection persistence, reading-position bounds, disk round trips, corruption handling, atomic replacement, independent imports, and failed-save retry ordering. Only Swift Playgrounds can validate the AppleProductTypes app manifest and UIKit/PDFKit/PencilKit behavior on the target iPad.

## Source layout

- `ZenNote.swiftpm/Sources/ZenNoteCore/`: Foundation models and file storage; independently testable.
- `ZenNote.swiftpm/Sources/AppModule/`: SwiftUI workspace, lazy PDFKit overlays, PencilKit surfaces, notebook paging/zoom, lifecycle autosave.
- `ZenNote.swiftpm/Tests/ZenNoteCoreTests/`: automated core tests.
- `docs/implementation.md`: defaults and technical decisions.
- `docs/ipad-testing.md`: device acceptance checklist and validation status.
- `scripts/`: dependency-free archive and synthetic PDF generators.

Private repository: https://github.com/dinhtrkien/zen-note (branch: `main`).
