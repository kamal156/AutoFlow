#!/usr/bin/env node
// Generates assets/autoflow.ico (a 256px PNG wrapped in an ICO container) with
// zero dependencies. Windows Vista+ reads PNG-compressed icons natively.
// Re-run any time you want a different look: node scripts/make-icon.js
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const SIZE = 256;
const px = Buffer.alloc(SIZE * SIZE * 4);

function set(x, y, r, g, b, a) {
  const i = (y * SIZE + x) * 4;
  // simple alpha-over compositing
  const da = px[i + 3] / 255, sa = a / 255;
  const oa = sa + da * (1 - sa);
  if (oa === 0) return;
  px[i]     = Math.round((r * sa + px[i]     * da * (1 - sa)) / oa);
  px[i + 1] = Math.round((g * sa + px[i + 1] * da * (1 - sa)) / oa);
  px[i + 2] = Math.round((b * sa + px[i + 2] * da * (1 - sa)) / oa);
  px[i + 3] = Math.round(oa * 255);
}

const cx = SIZE / 2, cy = SIZE / 2;
// Rounded-square background, deep indigo -> violet gradient.
const R = 118, corner = 40;
for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    const dx = Math.max(Math.abs(x - cx) - (R - corner), 0);
    const dy = Math.max(Math.abs(y - cy) - (R - corner), 0);
    const d = Math.sqrt(dx * dx + dy * dy) - corner;
    if (d > 1) continue;
    const a = d < 0 ? 255 : Math.round(255 * (1 - d));
    const t = (x + y) / (2 * SIZE);
    set(x, y, Math.round(58 + 60 * t), Math.round(44 + 30 * t), Math.round(150 + 80 * t), a);
  }
}
// Four windmill blades (a windmill for Windmill) in warm white, rotating around the centre.
function blade(angle) {
  const cos = Math.cos(angle), sin = Math.sin(angle);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      // rotate into blade space
      const rx = (x - cx) * cos + (y - cy) * sin;
      const ry = -(x - cx) * sin + (y - cy) * cos;
      if (rx < 14 || rx > 92) continue;
      const half = 9 + (rx - 14) * 0.22; // blade widens outward
      const d = Math.abs(ry) - half;
      if (d > 1) continue;
      const a = d < 0 ? 240 : Math.round(240 * (1 - d));
      set(x, y, 255, 250, 235, a);
    }
  }
}
for (let k = 0; k < 4; k++) blade(k * Math.PI / 2 + Math.PI / 8);
// Hub
for (let y = 0; y < SIZE; y++) for (let x = 0; x < SIZE; x++) {
  const d = Math.hypot(x - cx, y - cy) - 17;
  if (d > 1) continue;
  set(x, y, 255, 196, 61, d < 0 ? 255 : Math.round(255 * (1 - d)));
}

// --- PNG encode ---
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
const raw = Buffer.alloc((SIZE * 4 + 1) * SIZE);
for (let y = 0; y < SIZE; y++) {
  raw[y * (SIZE * 4 + 1)] = 0; // filter: none
  px.copy(raw, y * (SIZE * 4 + 1) + 1, y * SIZE * 4, (y + 1) * SIZE * 4);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0); ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);

// --- ICO container: one PNG entry ---
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(1, 4);
const entry = Buffer.alloc(16);
entry[0] = 0; entry[1] = 0;             // 256 px is encoded as 0
entry[2] = 0; entry[3] = 0;
entry.writeUInt16LE(1, 4); entry.writeUInt16LE(32, 6);
entry.writeUInt32LE(png.length, 8); entry.writeUInt32LE(22, 12);
const out = path.join(__dirname, '..', 'assets', 'autoflow.ico');
fs.writeFileSync(out, Buffer.concat([header, entry, png]));
fs.writeFileSync(path.join(__dirname, '..', 'assets', 'autoflow.png'), png);
console.log(`wrote ${out} (${png.length} bytes PNG inside)`);
