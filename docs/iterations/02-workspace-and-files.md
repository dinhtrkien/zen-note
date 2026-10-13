# Iteration 02 — Workspace and Files Library

Status: implemented locally and packaged; native build and device validation pending.

This is a temporary delivery checklist for this iteration, not lifecycle-wide product truth. Product direction lives in `../../vision.md`; completed checklists become historical records.

## Locked scope

- One matte Warm Parchment theme: background `#ADA28E`, controls `#D5C9B2`, paper `#F3E7CC`, grid/dots `#BBAE90`, UI text `#40392F`, accent `#596344`.
- Keep the existing black/blue/red/green/yellow pen palette and existing stroke colors. No dark mode, PDF inversion, or recoloring of PDF content.
- Blank, square-grid, and dotted-grid sheets, with matching 24-point spacing. Existing fixed sheet dimensions stay unchanged.
- Pin the current PDF page's complete note set; browse its sheets normally. Unpin follows the currently visible PDF page. Pin state is retained across layout changes within the current book session.
- Split, textbook-only, and notes-only layouts; preserve reading position, selected sheet, note associations, and pin state.
- Zen hides headers. Toolbar is top-docked or auto-hide (about three idle seconds), never hidden during writing. A persistent small control reveals controls/exits zen.
- One user-selected Files folder is the authoritative library: PDFs, editable drawings, links, metadata, and preferences. Autosave, not repeated Save prompts.
- Prefer local storage outside Playgrounds-owned folders for offline use. Remember directory permission; allow reconnecting an existing library after sandbox/bookmark loss.
- Non-destructive migration: copy and verify existing data, preserve IDs, and retain the original. Never overwrite a different library or silently create an empty fallback after a permission failure.
- Preserve the bundle identifier and schema compatibility; supply defaults for added preferences.

## Not included

Cloud-sync implementation, lasso, passage-based links, changing pen colors, and a separate export/backup product feature. The Files folder can be copied manually by the user.

## Validation policy

No new automated tests and no automated test runs. Existing tests remain untouched. Docker compilation/build checks are required; Apple UI compilation and behavior need live Swift Playgrounds checks on the user's iPad. Do not present syntax parsing as an iPad build.

## Live handoff checks

- In the original v1 project, the authorized one-file migration bridge builds and old books remain visible. Its Files copy preserves PDFs, ink, links, positions, and preferences; original remains available. A fresh v2 project reconnects that exported folder. V2's built-in copy remains an alternative when it can already read v1 private data.
- Reconnect to that folder after restart/project replacement; cancel selection, wrong-folder selection, and permission/save failures do not erase data or produce a silent empty library.
- New imports and strokes autosave directly to the selected folder; offline behavior is verified on a local provider.
- Warm surfaces and dotted paper render correctly; existing ink colors and PDF illustrations remain unchanged.
- Pin while browsing PDF pages; edit/browse/add notes within the pinned group; unpin follows the current PDF.
- Cycle all layouts and zen modes without losing a completed stroke, changing note associations, or moving reading position unexpectedly.
- Top auto-hide toolbar waits until writing ends; reveal/exit control remains usable.

## Delivery evidence

- Added the warm theme, dotted paper, note-set pinning, persistent-controller layouts, and zen controls. Auto-hide uses a fixed overlay and waits through active strokes.
- Added security-scoped Files-folder selection/bookmarks, staged byte-verified migration, stable library identity checks, and reconnect/retry without discarding pending drafts. Original data is never deleted by migration.
- Kept bundle identifier `personal.zennote.prototype`; app version is `0.2.0` / build `2`. Existing v1 preferences receive defaults for added fields.
- Docker `swift:6.1`: `swift build` passed for the portable core; all AppModule files passed frontend syntax parsing; Foundation-only LocalWriter passed Swift 5 type checking without reported warnings. These are not Apple-framework type checks.
- Generated `artifacts/ZenNote-iPad.zip`: 18 entries, including 15 Swift source files; archive index inspected. No automated test suite or artifact-validator run. Existing test sources are unchanged.
- `vision.md` is the short enduring reference; this file is the active bounded checklist. Moved v1 documents unchanged under `docs/archive/v1/`.
- The initial advice to bulk-replace source folders through Files was impractical: `.swiftpm` is opaque there. User authorized a one-file v1 migration bridge. `migrations/v1/ContentView.swift` is generated from v1 commit `144cf16` with the old workspace retained; no other v1 file needs editing.
- Built the exact archived v1 Foundation core with Docker `swift:6.1`; bridge copy logic passed Swift 5 type checking with `ZENNOTE_MIGRATION_PORTABLE`, and the patched v1 app sources passed frontend syntax parsing. No automated tests added or run. This is not an Apple UI build.
- Generated `artifacts/ZenNote-v1-Migration.zip` with loose Swift/text code and instructions, plus direct `artifacts/ContentView-v1-Migration.txt`. Old private notes are copied and byte-verified into an empty folder without deleting the original. Source-code copies alone do not back up study data.
- First live bridge build reported “Call can throw” at the SwiftUI if/else closing brace (user screenshot). Replaced that view-selection builder branch with ordinary Swift control flow returning AnyView; handoff regenerated and portable build/type/syntax checks passed again. This workaround still needs the user's native retry; the root cause is not yet confirmed.
- Device checks above are still pending. V1's earlier smoke test does not validate V2 or the migration bridge. Code/document changes are local and have not been committed or pushed.
