// Generates a ONE-FILE replacement against the exact v1 commit the user ran.
// No current v2 UI/core dependency is introduced into the old playground.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { writeZip } from './zip.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const baseline = '144cf16b016474ba1c0036bfb1f2822ef99a9784';
let source = execFileSync('git', ['show', `${baseline}:ZenNote.swiftpm/Sources/AppModule/ContentView.swift`], { cwd: root, encoding: 'utf8' });
function replace(oldText, newText) {
  const first = source.indexOf(oldText);
  if (first < 0 || source.indexOf(oldText, first + oldText.length) >= 0) {
    throw new Error('V1 source anchor is not unique; refusing to generate an ambiguous patch.');
  }
  source = source.slice(0, first) + newText + source.slice(first + oldText.length);
}
replace('import SwiftUI\nimport UniformTypeIdentifiers\nimport ZenNoteCore',
`// ONE-TIME V1 MIGRATION: REPLACE the OLD ContentView.swift; do not add a second file.
// Keep every other v1 source and its Package.swift unchanged. Never paste into v2.
import Foundation
import ZenNoteCore
#if !ZENNOTE_MIGRATION_PORTABLE
import SwiftUI
import UIKit
import UniformTypeIdentifiers`);
replace('    @State private var importing = false',
`    @State private var importing = false
    @State private var choosingMigrationFolder = false
    @State private var migrationFolder: URL?
    @StateObject private var migration = V1MigrationController()`);
// Avoid an SDK-dependent ViewBuilder diagnostic at the if/else closing brace.
// Explicit AnyView returns keep this selection in ordinary Swift control flow.
replace(`            if let session = app.session {
                WorkspaceView(app: app, session: session)
                    .id(session.record.id)
            } else {
                library
            }`, '            mainContent');
replace('    private var library: some View {',
`    private var mainContent: AnyView {
        if let session = app.session {
            return AnyView(WorkspaceView(app: app, session: session).id(session.record.id))
        }
        return AnyView(library)
    }

    private var library: some View {`);
replace('ProgressView("Opening your book…")', 'ProgressView(migration.isCopying ? migration.status : "Opening your book…")');
replace('        .fileImporter(isPresented: $importing',
`        .sheet(isPresented: $choosingMigrationFolder, onDismiss: {
            guard let folder = migrationFolder else { return }
            migrationFolder = nil
            migration.copy(app: app, to: folder)
        }) {
            V1MigrationFolderPicker(onSelect: { folder in
                migrationFolder = folder
                choosingMigrationFolder = false
            }, onCancel: { migrationFolder = nil; choosingMigrationFolder = false })
        }
        .fileImporter(isPresented: $importing`);
replace('                Button { importing = true } label: { Label("Import PDF", systemImage: "plus") }',
`                Button { choosingMigrationFolder = true } label: {
                    Label("Copy library to Files", systemImage: "folder")
                }.buttonStyle(.bordered)
                    .disabled(!app.libraryAvailable || app.catalog.books.isEmpty)
                Button { importing = true } label: { Label("Import PDF", systemImage: "plus") }`);
replace('            saveFailure\n',
`            Text("Migration helper: choose an EMPTY local folder outside Playgrounds. The original library stays here. Keep the app open until copying and verification finish.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 12)
            saveFailure
`);
source += fs.readFileSync(path.join(root, 'migrations/v1/Exporter.swift.inc'), 'utf8');
const generated = path.join(root, 'migrations/v1/ContentView.swift');
fs.writeFileSync(generated, source);
const instructions = fs.readFileSync(path.join(root, 'migrations/v1/INSTRUCTIONS.txt'));
const artifact = path.join(root, 'artifacts', 'ZenNote-v1-Migration.zip');
writeZip([
  { name: 'ContentView.swift.txt', data: source },
  { name: 'ContentView.swift', data: source },
  { name: 'READ-ME-FIRST.txt', data: instructions }
], artifact);
// Plain text is also available directly, without navigating ANY package bundle.
fs.writeFileSync(path.join(root, 'artifacts', 'ContentView-v1-Migration.txt'), source);
console.log(`Generated ${generated} from v1 ${baseline.slice(0, 7)} (not an iPad build).`);
