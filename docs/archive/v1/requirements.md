# Zen Note — Prototype v1 Requirements

Status: Agreed product scope; implementation details and compatibility still require validation.

## Goal

Build a free, minimal, personal-use iPad workspace for reading PDF textbooks and books while writing notes, summaries, and problem solutions.

The defining workflow is that the textbook drives the notebook: handwritten notes are linked to individual PDF pages and appear automatically as the reader navigates the PDF.

## Target and constraints

- Target device: iPad 8th generation.
- Reported iPadOS version: 26.7; confirm on the device before compatibility testing.
- Input device: the user's third-party pencil. Brand/model has not been specified.
- The user can currently rest their palm on the screen while writing in other apps; equivalent usable behavior is required here and must be tested.
- No Mac is available.
- Swift Playgrounds on iPad is an acceptable way to build and run the prototype. A standalone app icon is not required for v1.
- No paid Apple Developer Program membership, paid hosting, or other required paid services.
- Personal use only; public distribution and App Store publication are not part of v1.
- Landscape orientation only.
- Imported PDFs and notes must work offline and remain stored locally on the iPad.

## Reading workspace

- Import PDF files.
- Display vertically scrolling PDF pages in the left pane.
- Display handwritten note sheets in the right pane.
- Allow the divider between panes to be adjusted.
- Allow each pane to be pinch-zoomed independently.
- Handle large textbooks containing hundreds of pages without making reading or writing impractical.
- Reopening a book restores its reading position.

## Page-linked notes

- Each PDF page has its own set of zero or more note sheets.
- A note sheet belongs to one PDF page in one imported book, not to a shared set of PDF pages.
- For a problem or topic spanning several PDF pages, attach the notes to its first page. Cross-page links are not required.
- When the active PDF page changes, automatically display that page's note set.
- Browse multiple note sheets associated with the same PDF page horizontally.
- Returning to a PDF page restores its last-viewed note sheet.
- A PDF page without notes shows a blank note sheet ready for writing.
- Do not create stored notes merely because a PDF page is visited. Create the initial note storage when the user first writes.
- Note sheets have fixed boundaries rather than an infinitely expanding canvas.
- When a sheet runs out of room, the user explicitly adds another sheet.
- Offer blank and grid paper backgrounds.
- Zooming changes the view, not the fixed writing-page boundaries.

## Writing and PDF annotation

- Support handwriting on note sheets using the user's third-party pencil.
- Support handwriting directly on PDF pages.
- Support freehand highlighting directly on PDF pages.
- Text-snapping highlights, text-selection anchors, and OCR are not required.
- Intended interaction: pencil writes; fingers navigate, including scrolling and pinch-to-zoom.
- Writing with the palm resting on the screen must not cause disruptive accidental marks or navigation.
- Third-party pencil compatibility is a requirement, not an assumption that the device reports input as Apple Pencil input.

## Local persistence

- Automatically save handwritten notes and PDF annotations locally.
- Persist page-to-note associations, paper backgrounds, the last-viewed note sheet for each PDF page, and each book's reading position.
- Saved work must survive stopping and relaunching the app through Swift Playgrounds and reopening the book.
- No manual save action should be necessary for normal use.
- No cloud sync, export, or backup feature is required for this first prototype.

## Deferred / out of scope

- Lasso selection and moving handwriting.
- Optional note pinning while navigating the PDF. Automatic following is the v1 default; pinning can be added later.
- LiquidText-style links between selected PDF passages and individual note artifacts.
- Linking the same note sheet to multiple PDF pages.
- Infinite writing canvases.
- Cloud synchronization, accounts, and collaboration.
- PDF export and editable-book backup/export.
- Portrait layout, other device platforms, and public distribution.

## Open implementation and UX details

These are not yet agreed requirements:

- Exact pencil brand/model and how iPadOS reports its input. Validate stylus/finger distinction and palm-rest behavior on the actual device.
- Whether a write/navigation mode toggle is needed as a fallback for this pencil. Automatic pencil/finger separation is preferred, but has not been verified.
- The rule for choosing the active PDF page when more than one page is visible.
- Default paper background, sheet dimensions/aspect ratio, and default divider position.
- Exact pen/eraser/highlighter toolbar, color and thickness controls, and undo/redo behavior. A basic toolbar was proposed; lasso was explicitly deferred.
- Book-library organization and import details.
- Representative PDF file sizes and performance targets.

## Early feasibility checks

Before building the complete workspace, verify on the target iPad that Swift Playgrounds can support:

1. Importing and reopening a local PDF.
2. Responsive handwriting with the actual third-party pencil, including palm-rest writing and finger navigation.
3. Freehand PDF annotations that stay aligned while scrolling and zooming.
4. Local note and annotation persistence across stopping and relaunching the playground app.
5. A representative textbook with hundreds of pages without excessive memory usage or unusable latency.

A native Swift Playgrounds implementation is the candidate route; no framework choice is locked by these requirements.

## Core acceptance walkthrough

1. Open the prototype through Swift Playgrounds and import a textbook PDF.
2. Resize the landscape divider and navigate to a PDF page with no notes.
3. See an empty note sheet without automatically creating stored notes for every visited PDF page.
4. Write on that sheet with the third-party pencil while resting the palm comfortably.
5. Add another fixed sheet and browse the two sheets horizontally.
6. Scroll to a different PDF page and see its separate note set automatically.
7. Return to the original PDF page and see the last-viewed note sheet with the writing intact.
8. Handwrite and freehand-highlight on the PDF, then zoom and scroll without annotation misalignment.
9. Stop and relaunch the app offline, reopen the book, and recover the reading position, annotations, and linked notes.

## Repository and source

- Private GitHub repository: https://github.com/dinhtrkien/zen-note
- Repository creation did not upload local files or configure local Git remotes.
- Initial idea: `D:/obsidian/vaults/thoughts/projects/zen-note.md`.
- This document records the subsequent requirements discussion and its agreed scope.
