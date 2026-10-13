# Target-iPad acceptance checklist

## Current validation status

- Foundation core: compiled and 18 automated tests passed with Swift 6.1.3 on Linux in Docker.
- App-module source: passed `swiftc -frontend -parse` grammar checking on Linux; the Foundation-only autosave queue also passed Linux type checking.
- Generated transfer ZIP: CRCs, source integrity, landscape manifest, and exclusion of build/test artifacts checked.
- Synthetic test PDF: 600 pages, object/xref offsets, rotated pages, and crop-box test pages checked.
- Initial iPad operation: **USER REPORTS WORKING**. This establishes an initial device smoke test, not completion of the detailed checklist below.
- Detailed touch input, UI, and restart-persistence acceptance checks: **TESTING IN PROGRESS**.
- Third-party stylus palm rejection and hundreds-of-pages performance: **NOT YET CONFIRMED**.

Do not interpret the core test results as an iPad build. Use disposable practice notes until every essential device gate below passes.

## Preparation

- Record actual iPad model, iPadOS version, Swift Playgrounds version, and pencil brand/model.
- Extract `artifacts/ZenNote-iPad.zip` in Files and open `ZenNote.swiftpm` with Swift Playgrounds.
- Run the app full-screen in landscape. Report any build error with file/line and exact text.
- Use `artifacts/Practice-Textbook.pdf` (generate with `node scripts/make-test-pdf.mjs 600`) for repeatable tests, then use a representative real textbook. The synthetic text-only PDF is not a substitute for a large scanned/image-heavy book.

## Essential early gates

- [ ] Project opens and compiles in Playgrounds without Mac, developer membership, external package downloads, or paid services.
- [ ] Full-screen app stays in landscape; the pane divider is adjustable.
- [ ] PDF imports from Files, then opens with the source unavailable and the iPad offline.
- [ ] Actual pencil writes in Stylus mode, with one-finger scrolling and independent two-finger pinch-to-zoom.
- [ ] If Stylus mode does not recognize the pen, touch-style mode can write; two-finger navigation and the hand toggle work.
- [ ] Resting the palm while writing causes neither accidental ink nor unwanted page changes. Test both PDF and notes. **If this fails, third-party-pencil compatibility is not accepted**, even if a finger can draw.
- [ ] A completed stroke persists after stopping the full-screen app and tapping Run App again.
- [ ] Stopping/relaunching Swift Playgrounds preserves the same book and strokes.
- [ ] A harmless source edit/rebuild preserves local data with the same bundle identifier/project. If not, the sandbox-lifetime requirement needs resolution before using real notes.

## Linked notebook walkthrough

- [ ] Open PDF page 12: an unwritten blank/grid sheet is available without pre-creating notes for every PDF page.
- [ ] Write `page 12, sheet 1`; add another sheet and write `page 12, sheet 2`.
- [ ] Horizontally swipe between sheets at fit-to-page scale. Header arrows also work.
- [ ] Scroll PDF to page 13: its own empty sheet appears automatically.
- [ ] Return to page 12: sheet 2 is selected and both drawings remain intact.
- [ ] Write while quickly changing PDF pages afterward: the completed ink remains attached to its original page, not the newly active one.
- [ ] Navigate through many PDF pages without writing: they do not appear as materialized note sheets when revisited beyond the ready-to-write placeholder.
- [ ] Grid/blank choices persist for written/materialized sheets. Changing an empty sheet's paper alone does not create stored page notes.
- [ ] A note sheet is finite. Adding another sheet is explicit rather than endlessly scrolling down.
- [ ] Zoom a note sheet, pan within it, and resize the divider: ink keeps the same logical position and sheet dimensions.

## PDF annotations and navigation

- [ ] Pen, freehand marker, and bitmap eraser work on the PDF.
- [ ] Marker is translucent/freehand and requires no selectable text or OCR.
- [ ] Ink remains aligned after PDF scrolling, zooming, and divider resizing.
- [ ] Test a rotated page (practice page 50) and a non-zero crop origin (practice page 25): annotation alignment survives revisiting and relaunching.
- [ ] The page at the center of the reading pane controls the notebook when two PDF pages are visible.
- [ ] Undo/redo affect the last-used drawing surface, never a different PDF page or note sheet. No lasso is exposed.
- [ ] Close the book, reopen it, and recover the PDF page, approximate viewport position, and last-viewed note sheets.

## Offline/autosave safety

- [ ] Complete strokes, leave the app, return offline, and confirm all ink and metadata.
- [ ] Navigate or close immediately after a stroke: no cross-page save or lost completed stroke.
- [ ] PDF annotations persist alongside notes after Playgrounds restart.
- [ ] Original PDF file in Files is unchanged.
- [ ] If a save error is displayed, stop testing valuable work, keep the app open, free storage if appropriate, and use Retry saves. The error must not silently disappear while unsaved data remains.
- [ ] No cloud sync, accounts, export, backup, pinning, or text-anchor features have slipped into v1.

## Performance gate: iPad 8th generation

- [ ] Import and scroll a real textbook containing hundreds of pages.
- [ ] Rapidly scroll forward/backward while notes follow without prolonged stalls.
- [ ] Write and zoom without unusable latency or crashes.
- [ ] Repeatedly switch pages/books: memory use does not grow because all pages retain live canvases.
- [ ] Test an image-heavy textbook separately; note its page count, file size, import time, and any lag/crash.

Record failures with the PDF page, selected input mode, zoom state, and exact reproduction steps. Device gates remain pending until evidence is recorded here.
