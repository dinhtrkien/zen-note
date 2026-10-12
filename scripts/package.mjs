// Dependency-free ZIP packaging for transfer to an iPad. Excludes build output,
// tests, and host-only files; contains the .swiftpm app and a short START HERE.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateRawSync } from 'node:zlib';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const app = path.join(root, 'ZenNote.swiftpm');
const entries = [];
function walk(directory, prefix) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (['.build', '.swiftpm', 'Tests', '.DS_Store'].includes(entry.name)) continue;
    const location = path.join(directory, entry.name), name = `${prefix}/${entry.name}`;
    if (entry.isDirectory()) walk(location, name);
    else if (entry.isFile()) entries.push({ name, data: fs.readFileSync(location) });
  }
}
walk(app, 'ZenNote.swiftpm');
// Tests are excluded to reduce transfer clutter. Keep the manifest coherent.
const manifest = entries.find(entry => entry.name === 'ZenNote.swiftpm/Package.swift');
manifest.data = Buffer.from(manifest.data.toString().replace(
  ',\n    .testTarget(name: "ZenNoteCoreTests", dependencies: ["ZenNoteCore"], path: "Tests/ZenNoteCoreTests")', ''
));
entries.push({ name: 'START-HERE.txt', data: Buffer.from(
  'Install Apple Swift Playgrounds (free). Extract this ZIP in Files.\n' +
  'Open ZenNote.swiftpm using Swift Playgrounds, rotate to landscape, and tap Run App.\n' +
  'Import a test PDF. Check your pencil in Stylus mode; if needed select Input > Touch-style pen fallback.\n' +
  'The fallback uses two fingers for navigation; the hand button disables writing.\n' +
  'IMPORTANT: test autosave after stopping and restarting before storing valuable study notes.\n' +
  'Keep the same project and bundle identifier. Removing Playgrounds or app data can lose local notes.\n'
) });

const table = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = table[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

const local = [], central = [];
let offset = 0;
for (const entry of entries) {
  const name = Buffer.from(entry.name), compressed = deflateRawSync(entry.data), crc = crc32(entry.data);
  const header = Buffer.alloc(30);
  header.writeUInt32LE(0x04034b50, 0); header.writeUInt16LE(20, 4);
  header.writeUInt16LE(0x0800, 6); header.writeUInt16LE(8, 8);
  header.writeUInt16LE(33, 12); // 1980-01-01, deterministic archive date.
  header.writeUInt32LE(crc, 14); header.writeUInt32LE(compressed.length, 18);
  header.writeUInt32LE(entry.data.length, 22); header.writeUInt16LE(name.length, 26);
  local.push(header, name, compressed);
  const record = Buffer.alloc(46);
  record.writeUInt32LE(0x02014b50, 0); record.writeUInt16LE(20, 4); record.writeUInt16LE(20, 6);
  record.writeUInt16LE(0x0800, 8); record.writeUInt16LE(8, 10); record.writeUInt16LE(33, 14);
  record.writeUInt32LE(crc, 16); record.writeUInt32LE(compressed.length, 20);
  record.writeUInt32LE(entry.data.length, 24); record.writeUInt16LE(name.length, 28);
  record.writeUInt32LE(offset, 42); central.push(record, name);
  offset += header.length + name.length + compressed.length;
}
const directory = Buffer.concat(central), end = Buffer.alloc(22);
end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
const destination = path.join(root, 'artifacts', 'ZenNote-iPad.zip');
fs.mkdirSync(path.dirname(destination), { recursive: true });
fs.writeFileSync(destination, Buffer.concat([...local, directory, end]));
console.log(`Created ${destination} (${entries.length} files, ${fs.statSync(destination).size} bytes)`);
