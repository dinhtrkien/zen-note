# Zen Note

A quiet iPad study workspace: PDF on the left, attached handwritten notes on the right.

[`vision.md`](vision.md) is the enduring product direction. [`Iteration 02`](docs/iterations/02-workspace-and-files.md) locks this delivery's scope. V1 documents are historical records under [`docs/archive/v1/`](docs/archive/v1/).

## Run on iPad

No Mac or paid Apple developer membership is needed for running this prototype through **Swift Playgrounds**.

1. Transfer `artifacts/ZenNote-iPad.zip` to Files, extract it, and open `ZenNote.swiftpm` in Swift Playgrounds.
2. Rotate to landscape and tap **Run App** (use the full-screen app).
3. Choose a **Files library folder**. Use an empty local folder outside Playgrounds-owned storage, or select an existing Zen Note library.
4. Confirm the folder, then import a PDF. PDFs, editable ink, notes, associations, and preferences autosave there.

The archive is generated, not committed: `node scripts/package.mjs` creates it. No external app dependencies are downloaded.

## Migrate existing v1 notes first

Files treats `.swiftpm` as an opaque package; the earlier bulk source-folder replacement advice was not a practical iPad workflow. **Do not delete the old project or assume a fresh v2 import can see its private data.**

1. Transfer `artifacts/ZenNote-v1-Migration.zip` and extract it. This contains loose files, not a project bundle. Open `ContentView.swift.txt` and copy all the text. A clipboard fallback using Apple's Shortcuts app is in `READ-ME-FIRST.txt`.
2. In the **original v1 project**, replace all the code in its existing `ContentView.swift` with that text. Change no other source, project name, or bundle identifier; do not add a duplicate file. Keep an original source copy.
3. Run the original project **without renaming it**. The user renamed `ZenNote` to `ZenNoteV1`, saw an empty library, then restored access by renaming it back to `ZenNote`. This is an observed identity/access issue, not proof of a particular storage implementation. **If old books are missing or compilation fails, stop and report it.** It is not a guarantee that private sandbox data survives every Playgrounds operation.
4. From Books, tap **Copy library to Files** and select an **empty local folder outside Playgrounds-owned storage**. Wait for the verified-success message. The helper copies PDFs, editable ink, associations, metadata, and current preferences, retaining the original. Pending save errors block the copy.
5. After verified export, back up the **whole Files folder** separately. Extract `ZenNote-iPad.zip` separately; give only the **new** project a distinct name such as `ZenNote-v2.swiftpm` before first run, without replacing or renaming the old `ZenNote` project. Choose the **existing exported folder**. Check old notes and annotations, restart, and check again before removing anything.

This is a one-time migration bridge, not a new v2 export product feature. Future app projects can simply reconnect the existing Files library. V2's built-in copy flow also remains available if it already has access to the private v1 data.

Developer regeneration: `node scripts/package-v1-migration.mjs`. The helper is pinned to v1 commit `144cf16`; generated source is under `migrations/v1/`, not in the v2 app. Portable checks and native Apple-framework source compilation passed. The user’s launch error identifies `PlaygroundBuild.ThunkCompileFailure`, which source-only CI does not cover. The current one-file workaround returns `Result` from the copy API and keeps throwing helpers local, avoiding throwing member forwarding wrappers. This targets a [documented SwiftUI thunk failure pattern](https://forums.swift.org/t/swiftui-preview-thunk-does-not-try-a-function-that-can-throw-preview-failed-to-build/66689); the exact generated failing call remains unavailable. The user confirmed the thunk-compatible shape launches on iPad and old books reappeared after restoring the original project name; original PDFs/notes are still readable. Export hit a broad integrity-guard failure. The current path-fix revision retains precise guard/status reporting, enumerates canonical URLs and checks containment/overlap by components instead of brittle raw prefixes, while still rejecting symbolic links and non-regular files. The picker handoff consumes selection once after dismissal, regardless of callback order. The user subsequently reported migration completed and v2 reads books and notes from the exported folder. Restart persistence and full acceptance remain pending. V2 then reported an invalid storage path on unwritten sheets; the 0.2.1 patch below addresses that separate path guard.

**Validation:** the user confirms v0.2.1 is working on iPad after migration and the blank-sheet patch; broader acceptance and restart persistence are not separately reported. Both patched v2 and the exact v1 migration helper passed native Apple-framework source compilation in [GitHub Actions](https://github.com/dinhtrkien/zen-note/actions/runs/38408968903) (Xcode 26.0.1, Swift 6.2 compiler, iOS 26 simulator SDK, Swift 5 language mode). This is not a Playgrounds manifest/package/thunk build or device acceptance. It does not compile the generated code responsible for the user's launch failure. No new automated tests were added or run. Swift Playgrounds and live behavior must still be checked before trusting important work to it.

## Controls

- **Pin:** the pin button holds the complete note set for its PDF page while the textbook scrolls. Browse/add/edit sheets as usual; unpin follows the current PDF page. Pin lasts for the current book session and survives layout changes.
- **Layout:** choose split, textbook fullscreen, or notes fullscreen with the layout button or **…** menu. Both controllers stay mounted; hidden-pane tracking is paused.
- **Zen:** hides headers/footer. **… → Zen toolbar** chooses top-docked or auto-hide (about three idle seconds, held visible during writing). The small top-right control reveals the hidden toolbar; tap again to exit zen. Auto-hide floats over the canvas instead of resizing it mid-stroke.
- **Notes:** swipe horizontally at fit, or use the arrows/menu. **+** adds a fixed 768 × 1024 sheet. Blank, grid, and dotted paper share 24-point grid spacing. Unwritten placeholders do not create stored sheets.
- **PDF:** scroll vertically or use the arrows. Unpinned notes follow the PDF page at the viewport center. A note stroke finishes on its original canvas before following changes resume.
- **Zoom/divider:** pinch each pane independently; drag the split divider. Zoomed notes pan instead of paging.
- **Ink:** unchanged black/blue/red/green/yellow palette, freehand marker, bitmap eraser, width, and surface-focused undo/redo. Warm paper and controls do not recolor saved strokes or PDF content.
- **Input:** **… → Input** selects stylus-only input or touch-style pen fallback. The latter uses two fingers for navigation; the hand button switches writing off for one-finger navigation. Universal third-party pen palm rejection is not guaranteed.

## Files storage and safe updates

```text
<your selected library folder>/
  library.json
  preferences.json
  books/<book UUID>/
    document.pdf
    state.json
    pdf/page-<index>.drawing
    notes/page-<index>/<sheet UUID>.drawing
```

- Imported PDFs are copied; their original Files sources are not modified. Ink stays in editable PencilKit sidecars, not burned into the PDF.
- Stable book/sheet IDs retain page associations. Files are atomically replaced on a serial IO queue, drawings before referencing metadata. Failed saves remain in memory with retry/reconnect controls: **keep the app open while unsaved changes are reported**.
- Directory permission is remembered in a small private bookmark. After sandbox/project replacement, the bookmark may disappear: reselect the **existing** library folder. No data copy or merge is needed to reconnect.
- Missing/revoked access does not create an empty fallback. Connecting another library requires confirmation and successful saving of current drafts. A directory replaced with another library must not receive those drafts.
- Choose local storage for offline study. Cloud-provider folders may need network/download access; there is no app-level cloud-sync implementation.
- The primary folder is **not a backup**. Finish writing, close the book, allow autosave to finish, then copy the whole folder elsewhere in Files. Do not edit/rename its internal files or open multiple writers to one library.
- Keep the original project/library until migration is complete and checked on-device. Do not force-stop during copying. An interrupted transfer can leave a partial destination; keep it and the original, and choose another empty destination rather than overwriting either.
- Deleting the library or its owning storage app can still delete data. Files storage protects against losing the Playgrounds sandbox only when the folder is outside Playgrounds-owned storage and remains available.

### Update to the blank-sheet patch (0.2.1)

Close the book and wait for autosave, copy the whole Files library as a backup, then stop the old v2 app. Open `artifacts/ZenNote-iPad-0.2.1.zip` as a fresh project (`ZenNote-0.2.1.swiftpm`) and reconnect the **same existing library folder**. No repeated migration, source-by-source replacement, schema change, or library recreation. Leave the original v1 project named `ZenNote` unchanged; never run two writers on the same Files library.

The patch normalizes the root once and appends validated relative components without separately standardizing a missing drawing URL. Component containment, traversal/descendant-symlink rejection, file coordination, library identity checks, and read-error protection remain. Missing sidecars return an empty canvas; no note file is created just by viewing a page. Docker and native compilation passed, and the user confirms the patch works on iPad. Continue checking first-note autosave/relaunch and retained existing notes/PDF ink; the brief confirmation is not a complete acceptance report.

Generate the distinctly named handoff with `node scripts/package.mjs ZenNote-0.2.1.swiftpm`, then copy the output archive to `artifacts/ZenNote-iPad-0.2.1.zip`.

## Development checks

This iteration deliberately uses compilation plus live iPad feedback, not automated tests. Existing test sources remain untouched.

```sh
# Portable Foundation core only; excludes Apple UI on Linux.
cd ZenNote.swiftpm
swift build
cd ..

# From the repository root, produce the iPad transfer archives.
node scripts/package.mjs
node scripts/package-v1-migration.mjs
```

Windows/Git Bash with Docker:

```sh
MSYS_NO_PATHCONV=1 docker run --rm \
  -v 'C:/Users/dinht/Desktop/zen-note/ZenNote.swiftpm:/workspace' \
  -w /workspace swift:6.1 bash -lc \
  'swift build && swiftc -frontend -parse Sources/AppModule/*.swift && swiftc -swift-version 5 -typecheck -I .build/x86_64-unknown-linux-gnu/debug/Modules Sources/AppModule/LocalWriter.swift'
```

Linux cannot type-check UIKit/PDFKit/PencilKit or validate the AppleProductTypes manifest.

Native source compilation is integrated into `main`, with the diagnostic history retained on branch `agent/native-ci-20261013`. The user intentionally made the repository public. CI explicitly selects Xcode 26.0.1 instead of the runner's older default, matching Playgrounds 4.7's Swift 6 / iOS 26 SDK family. `.github/workflows/native-ios-typecheck.yml` runs `bash ci/native-ios-typecheck.sh` on macOS with Xcode: it compiles every current app source and separately compiles the generated helper with the exact v1 sources. It uses no signing, test targets, or simulator execution. Account Actions quota could not be read with the current token; no billing settings were changed. The workflow runs for `main` pushes/pull requests, CI-lane pushes, and manual dispatch.

Live handoff checks are in the iteration checklist; no implementation-document review is required.

Repository (public by user choice): https://github.com/dinhtrkien/zen-note.
