# v1 implementation decisions

The product scope in `requirements.md` is unchanged. These choices resolve implementation details that were previously open, without adding deferred features.

## Platform and defaults

- Native Swift Playgrounds `.swiftpm` app, iPad-only, iOS 16+ APIs, landscape orientations, full-screen presentation requested.
- SwiftUI for the workspace; PDFKit for on-demand PDF rendering/page overlays; PencilKit for editable ink. No third-party dependencies or network code.
- Pane widths default to 50/50 and can range from 28/72 to 72/28.
- The active PDF page is the page nearest the vertical/horizontal center of the PDF viewport. Position tracking is throttled to avoid republishing state at every scroll pixel.
- Fixed logical sheets are 768 × 1024 points, grid by default with 24-point spacing. Each sheet fits the available note viewport initially and can zoom to six times that fit scale. Blank paper is also available.
- An empty page has a stable, in-memory placeholder sheet. Visiting it never calls the metadata materialization operation. First writing creates storage; an explicit Add Sheet action can materialize the current empty sheet before appending a new one.
- PDF page and sheet targets are captured in each drawing surface, so delayed save callbacks cannot write notes onto a newly active PDF page.
- Native lazy PDF overlays and `UIPageViewController` neighbor loading avoid creating hundreds of live canvases. Drawings are loaded only for displayed/requested surfaces.

## Input

- Default stylus mode uses PencilKit `.pencilOnly` and finger-only navigation gestures.
- A touch-style fallback uses `.anyInput`, two-finger navigation, and an explicit hand/navigation-only toggle. It does not pretend that every third-party pen can be differentiated from palm input.
- Pan and pinch belong to the enclosing PDF/notes viewport; the drawing canvases do not independently scroll.
- At fit-to-page size, finger swipes page the notebook horizontally. When zoomed, finger pans move within the current sheet. Header arrows remain available in both cases.
- Tools: pen, freehand marker, bitmap eraser, undo/redo on the focused canvas, basic colors, and three width choices. No lasso or native tool picker exposing deferred tools.
- Pencil brand/model recognition and palm-rest behavior are still unverified on hardware.

## Persistence

- Each imported book receives a UUID and its own local PDF copy, metadata, and drawing sidecars. The original PDF is never overwritten.
- PDF annotation sidecars are displayed through PDFKit page overlays and remain editable. They are not embedded/exported into a new PDF because export is outside v1.
- Drawing changes debounce for 300 ms while editing; tool completion, surface removal, and lifecycle transitions flush them. Reading position uses a 600 ms debounce; closing/backgrounding forces it to save.
- Save IO is serialized. New drawing files save before book metadata, then library metadata. Each individual file replacement is atomic, not a multi-file transaction.
- Pending writes retain the latest snapshot per file. A failed write pauses draining; the UI shows an error and offers retry. Unsaved bytes remain in memory. Already successful files are not rewritten during retry unless newer changes arrive.
- Reopening a book can read queued snapshots as well as completed files, preventing rapid close/reopen from showing stale data.
- Corrupt/future-version metadata is reported instead of replaced with an empty library. Missing metadata for an existing book also blocks opening instead of silently losing note links.
- Settings writes are debounced during divider dragging; app deactivation flushes settings.
- Book files persist only in the actual app sandbox. Whether Swift Playgrounds preserves that sandbox across stop/relaunch/rebuild is an explicit target-device acceptance gate, not something Linux tests establish.

## Validation boundaries

The Foundation core can compile and test on Linux. Swift syntax parsing can check app source grammar without resolving Apple frameworks. Neither verifies Apple framework availability, app-manifest compilation, touch delivery, drawing alignment, landscape behavior, Playgrounds sandbox lifetime, or iPad performance. Those checks are specified in `ipad-testing.md` and must not be reported as completed without device evidence.

## References checked

- Apple: [Run your app in Swift Playgrounds](https://support.apple.com/guide/playgrounds-ipad/run-your-app-itc650868b1f/ipados).
- Apple WWDC22: [What's new in PDFKit](https://developer.apple.com/videos/play/wwdc2022/10089/) — lazy overlay lifecycle, page sizing/rotation, PencilKit integration.
- Apple: [PDFPageOverlayViewProvider](https://developer.apple.com/documentation/pdfkit/pdfpageoverlayviewprovider).
- Apple: [PKCanvasView drawingGestureRecognizer](https://developer.apple.com/documentation/pencilkit/pkcanvasview/drawinggesturerecognizer).
- [AppleProductTypes interface reference](https://gist.github.com/treastrain/2f21d42c360dc9b9876ddde125abe247) — Swift Playgrounds app product, placeholder icon, orientation, and additional Info.plist settings. The actual shipped manifest still needs validation in Playgrounds.
