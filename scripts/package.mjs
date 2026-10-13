// Dependency-free ZIP packaging for transfer to an iPad. Excludes build output,
// tests, and host-only files; contains the .swiftpm app and a short START HERE.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { writeZip } from './zip.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const app = path.join(root, 'ZenNote.swiftpm');
const projectName = process.argv[2] ?? 'ZenNote.swiftpm';
if (!projectName.endsWith('.swiftpm') || projectName.includes('/') || projectName.includes('\\')) {
  throw new Error('Project name must be a single .swiftpm filename.');
}
const entries = [];
function walk(directory, prefix) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (['.build', '.swiftpm', 'Tests', '.DS_Store'].includes(entry.name)) continue;
    const location = path.join(directory, entry.name), name = `${prefix}/${entry.name}`;
    if (entry.isDirectory()) walk(location, name);
    else if (entry.isFile()) entries.push({ name, data: fs.readFileSync(location) });
  }
}
walk(app, projectName);
// Tests are excluded to reduce transfer clutter. Keep the manifest coherent.
const manifest = entries.find(entry => entry.name === `${projectName}/Package.swift`);
manifest.data = Buffer.from(manifest.data.toString().replace(
  ',\n    .testTarget(name: "ZenNoteCoreTests", dependencies: ["ZenNoteCore"], path: "Tests/ZenNoteCoreTests")', ''
));
entries.push({ name: 'START-HERE.txt', data: Buffer.from(
  'Install Apple Swift Playgrounds (free). Extract this ZIP in Files.\n' +
  `Open ${projectName} using Swift Playgrounds, rotate to landscape, and tap Run App.\n` +
  'Choose a Files library folder before importing/writing. Prefer an empty local folder outside Playgrounds-owned storage.\n' +
  'An existing private v1 library is copied and verified; the original is retained. Reconnect an existing Files library without copying.\n' +
  'UPDATING V1: first use the separate ZenNote-v1-Migration.zip one-file helper in your OLD project to copy its library to Files.\n' +
  'Verify the copy, then open this new project and select that EXISTING library folder. Do not delete the old project yet.\n' +
  'UPDATING FILES-BASED V2: close the book, wait for autosave, and back up the whole library folder.\n' +
  'Use a distinct new project name BEFORE first run; keep the original v1 ZenNote name unchanged.\n' +
  'Select the SAME EXISTING Files folder. Do not repeat migration or choose a new empty folder.\n' +
  'Pin holds the current note set. Layout/zen/input/paper controls are in the layout button and ... menu.\n' +
  'Check your pencil in Stylus mode; if needed select ... > Input > Touch-style pen fallback (two fingers navigate).\n' +
  'IMPORTANT: verify migration and restart persistence on the iPad before storing valuable notes. Keep the app open on save errors.\n' +
  'The Files folder is primary storage, not a backup. Copy the whole folder separately after saves finish.\n'
) });

writeZip(entries, path.join(root, 'artifacts', 'ZenNote-iPad.zip'));
