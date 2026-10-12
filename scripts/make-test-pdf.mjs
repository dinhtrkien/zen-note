// Synthetic, text-only test book. No copyrighted textbook content is included.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const count = Number(process.argv[2] ?? 600);
if (!Number.isInteger(count) || count < 2 || count > 2000) throw new Error('Choose 2–2000 pages.');
const objects = ['', '', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
const pages = [];
function object(body) { objects.push(body); return objects.length; }
for (let page = 1; page <= count; page++) {
  const lines = [
    `Zen Note practice textbook - page ${page}`,
    `Chapter ${Math.ceil(page / 20)} - sample reading and problem solving`,
    'Write a summary on the linked note sheet. Add another sheet when full.',
    'Highlight this line, then zoom and scroll: the ink should stay aligned.',
    'Problem: solve 2x + 7 = 19. Attach working to this PDF page only.',
    'Return here after visiting another PDF page: the last note sheet should reappear.'
  ];
  let stream = 'BT /F1 16 Tf 50 740 Td\n';
  for (const line of lines) stream += `(${line.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)')}) Tj 0 -36 Td\n`;
  stream += 'ET\n0.7 G 50 460 500 70 re S\n';
  const content = object(`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}endstream`);
  // Include rotation and a non-zero crop-box origin to exercise PDFKit overlays.
  const special = page % 50 === 0 ? '/Rotate 90' : page % 25 === 0 ? '/CropBox [20 20 592 772]' : '';
  pages.push(object(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ${special} /Resources << /Font << /F1 3 0 R >> >> /Contents ${content} 0 R >>`));
}
objects[0] = '<< /Type /Catalog /Pages 2 0 R >>';
objects[1] = `<< /Type /Pages /Count ${count} /Kids [${pages.map(id => `${id} 0 R`).join(' ')}] >>`;
let pdf = '%PDF-1.4\n', offsets = [0];
for (let i = 0; i < objects.length; i++) {
  offsets.push(Buffer.byteLength(pdf));
  pdf += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
}
const xref = Buffer.byteLength(pdf);
pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
pdf += offsets.slice(1).map(n => `${String(n).padStart(10, '0')} 00000 n \n`).join('');
pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
const output = path.join(root, 'artifacts', 'Practice-Textbook.pdf');
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, pdf);
console.log(`Created ${output} (${count} pages, ${Buffer.byteLength(pdf)} bytes)`);
