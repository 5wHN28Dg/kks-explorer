// The sharp drawing for the browser client (decision 0034): a module Worker that reads a sheet's path store
// (docs/PATHSTORE.md) and renders the visible area at the screen's resolution on an OffscreenCanvas. The page shows
// the result above the overview pyramid. Messages:
//   {t:'open', sheet, url}                      → {t:'opened', sheet, w, h} (quanta) or {t:'error', sheet, why}
//   {t:'render', key, sheet, x0, y0, s, W, H, dark}   → {t:'frame', key, bmp} (ImageBitmap, transferred)
//   {t:'level', id, url}                        → {t:'level', id, blob, ms} (a BMP) or {t:'level', id, why}
// x0, y0: the top-left of the area in points; s: device pixels per point; W, H: device pixels; dark: dark drawings
// (dark.js: every colour's lightness inverted, hue kept). 'level' decodes an overview pyramid level with our libjxl,
// turns it dark pixel by pixel here, off the page's thread, and hands it back as a BMP for the page's <img>.
'use strict';
import {darkRgb, darkenPixels} from '/dark.js';

const sheets = new Map();     // id → parsed sheet (or a Promise while loading)
let latest = 0;               // only the newest render request is drawn

// ---------- reading (PATHSTORE.md "Layout") ----------
class Reader {
  constructor(b) { this.b = b; this.p = 0; }
  u8() { if (this.p >= this.b.length) throw new Error('truncated'); return this.b[this.p++]; }
  u16() { const v = this.b[this.p] | (this.b[this.p + 1] << 8); this.p += 2; if (this.p > this.b.length) throw new Error('truncated'); return v; }
  u32() { const v = (this.b[this.p] | (this.b[this.p + 1] << 8) | (this.b[this.p + 2] << 16)) + this.b[this.p + 3] * 16777216; this.p += 4; if (this.p > this.b.length) throw new Error('truncated'); return v; }
  varint() {   // unsigned LEB128, at most 5 bytes
    let v = 0, mul = 1;
    for (let i = 0; i < 5; i++) { const c = this.u8(); v += (c & 127) * mul; if (!(c & 128)) return v; mul *= 128; }
    throw new Error('varint too long');
  }
  svarint() { const u = this.varint(); return (u % 2) ? -(u + 1) / 2 : u / 2; }
  bytes(n) { if (this.p + n > this.b.length) throw new Error('truncated'); const s = this.b.subarray(this.p, this.p + n); this.p += n; return s; }
}

async function inflate(bytes) {
  const s = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
  return new Uint8Array(await new Response(s).arrayBuffer());
}

async function parse(buf) {
  let b = new Uint8Array(buf);
  if (b.length < 8 || String.fromCharCode(b[0], b[1], b[2], b[3]) !== 'KKP1') throw new Error('not a path store');
  const h = new Reader(b); h.p = 4;
  if (h.u16() !== 1) throw new Error('unknown path store version');
  const flags = h.u16();
  if (flags & ~1) throw new Error('unknown path store flags');
  const r = new Reader(flags & 1 ? await inflate(b.subarray(8)) : b.subarray(8));
  const S = {width: r.u32(), height: r.u32(), gx: r.u16(), gy: r.u16()};
  const nStyles = r.varint(), nPaths = r.varint(), nImages = r.varint();
  S.styles = [];
  for (let i = 0; i < nStyles; i++) {
    const kind = r.u8(), cap = r.u8(), join = r.u8(), width = r.varint(), sc = r.bytes(3), fc = r.bytes(3);
    const css = c => `rgb(${c[0]},${c[1]},${c[2]})`;
    S.styles.push({kind, cap: ['butt', 'round', 'square'][cap] || 'butt', join: ['miter', 'round', 'bevel'][join] || 'miter', width,
                   stroke: css(sc), fill: css(fc), strokeDark: css(darkRgb(sc[0], sc[1], sc[2])), fillDark: css(darkRgb(fc[0], fc[1], fc[2]))});
  }
  // paths: style, bbox, commands and points, kept compact; a Path2D is made when first drawn
  S.pStyle = new Uint32Array(nPaths); S.bbox = new Int32Array(nPaths * 4);
  S.cmdAt = new Uint32Array(nPaths + 1); S.ptAt = new Uint32Array(nPaths + 1);
  const cmds = [], xy = [];
  for (let i = 0; i < nPaths; i++) {
    S.pStyle[i] = r.varint();
    const x0 = r.varint(), y0 = r.varint(), x1 = r.varint(), y1 = r.varint();
    S.bbox.set([x0, y0, x1, y1], i * 4);
    const n = r.varint(), packed = r.bytes(Math.ceil(n / 4));
    S.cmdAt[i] = cmds.length; S.ptAt[i] = xy.length / 2;
    let x = x0, y = y0;
    for (let k = 0; k < n; k++) {
      const c = (packed[k >> 2] >> ((k & 3) * 2)) & 3;
      cmds.push(c);
      const pts = c === 2 ? 3 : c === 3 ? 0 : 1;
      for (let j = 0; j < pts; j++) { x += r.svarint(); y += r.svarint(); xy.push(x, y); }
    }
  }
  S.cmdAt[nPaths] = cmds.length; S.ptAt[nPaths] = xy.length / 2;
  S.cmds = Uint8Array.from(cmds); S.xy = Int32Array.from(xy);
  S.cells = [];
  for (let c = 0; c < S.gx * S.gy; c++) {
    const n = r.varint(), list = new Uint32Array(n);
    let v = 0;
    for (let k = 0; k < n; k++) { v = k === 0 ? r.varint() : v + r.varint(); list[k] = v; }
    S.cells.push(list);
  }
  S.images = [];
  for (let i = 0; i < nImages; i++) {
    const after = r.varint(), x0 = r.varint(), y0 = r.varint(), x1 = r.varint(), y1 = r.varint(), len = r.varint();
    S.images.push({after, x0, y0, x1, y1, data: r.bytes(len).slice(), bmp: null, bmpDark: null});
  }
  if (r.p !== r.b.length) throw new Error('trailing bytes');
  S.paths2d = new Array(nPaths);
  return S;
}

function path2d(S, i) {
  let p = S.paths2d[i];
  if (p) return p;
  p = new Path2D();
  let q = S.ptAt[i] * 2, mx = 0, my = 0;
  for (let k = S.cmdAt[i]; k < S.cmdAt[i + 1]; k++) {
    switch (S.cmds[k]) {
      case 0: mx = S.xy[q]; my = S.xy[q + 1]; p.moveTo(mx, my); q += 2; break;
      case 1: p.lineTo(S.xy[q], S.xy[q + 1]); q += 2; break;
      case 2: p.bezierCurveTo(S.xy[q], S.xy[q + 1], S.xy[q + 2], S.xy[q + 3], S.xy[q + 4], S.xy[q + 5]); q += 6; break;
      default: p.closePath(); p.moveTo(mx, my);     // a segment after close continues from the move point
    }
  }
  return S.paths2d[i] = p;
}

// ---------- JPEG XL images inside a drawing: the browser's decoder, else our libjxl in WebAssembly (kks-wasm.js) ----------
let wasm = null;
async function bitmapOf(bytes) {
  try { return await createImageBitmap(new Blob([bytes], {type: 'image/jxl'})); } catch (e) { /* not decoded natively */ }
  wasm ??= import('/kks-wasm.js');   // our libjxl build (decision 0037)
  const d = await (await wasm).jxlDecode(bytes);
  return await createImageBitmap(new ImageData(d.rgba, d.width, d.height));
}
// dark drawings: always our libjxl, the decoder the desktop apps use, so the pixels transformed are the same
async function rgbaOf(bytes) {
  wasm ??= import('/kks-wasm.js');
  return (await wasm).jxlDecode(bytes);
}
async function darkBitmapOf(bytes) {
  const d = await rgbaOf(bytes);
  return await createImageBitmap(new ImageData(darkenPixels(d.rgba), d.width, d.height));
}

// an overview level in dark mode: decoded, transformed, packed as a 24-bit BMP (rows bottom-up, BGR, padded to 4 bytes;
// the format common.js's K.jxl.bmp gives the page for JPEG XL it can't show), the transform fused into the packing
async function darkLevel(url) {
  const r = await fetch(url, {credentials: 'same-origin'});
  if (!r.ok) throw new Error('overview ' + r.status);
  const d = await rgbaOf(new Uint8Array(await r.arrayBuffer()));
  const t0 = performance.now(), w = d.width, h = d.height, row = (w * 3 + 3) & ~3, size = 54 + row * h;
  const buf = new Uint8Array(size), v = new DataView(buf.buffer);
  buf[0] = 66; buf[1] = 77; v.setUint32(2, size, true); v.setUint32(10, 54, true); v.setUint32(14, 40, true);
  v.setInt32(18, w, true); v.setInt32(22, h, true); v.setUint16(26, 1, true); v.setUint16(28, 24, true);
  v.setUint32(34, row * h, true);
  const px = darkenPixels(d.rgba);
  for (let y = 0; y < h; y++) {
    let o = 54 + (h - 1 - y) * row, s = y * w * 4;
    for (let x = 0; x < w; x++, s += 4) { buf[o++] = px[s + 2]; buf[o++] = px[s + 1]; buf[o++] = px[s] }
  }
  return {blob: new Blob([buf], {type: 'image/bmp'}), ms: performance.now() - t0};
}

// ---------- drawing (PATHSTORE.md "Drawing a view", the style rules of "style") ----------
function cellRange(v0, v1, size, n) {
  const cell = v => Math.min(n - 1, Math.floor(Math.max(0, Math.min(v, size - 1)) * n / Math.max(1, size)));
  return [cell(v0), cell(v1)];
}

async function render(m) {
  const S = await sheets.get(m.sheet);
  if (!S || m.key !== latest) return;
  const k = m.s / 64;                                // device px per quantum
  const qx0 = Math.floor(m.x0 * 64), qy0 = Math.floor(m.y0 * 64);
  const qx1 = Math.ceil((m.x0 + m.W / m.s) * 64), qy1 = Math.ceil((m.y0 + m.H / m.s) * 64);
  // images in view, decoded before drawing (in paint order)
  const imgs = S.images.filter(im => im.x1 >= qx0 && im.x0 <= qx1 && im.y1 >= qy0 && im.y0 <= qy1);
  const bk = m.dark ? 'bmpDark' : 'bmp';
  for (const im of imgs) if (!im[bk]) { try { im[bk] = await (m.dark ? darkBitmapOf : bitmapOf)(im.data); } catch (e) { im[bk] = 'failed'; } }
  if (m.key !== latest) return;
  const c = new OffscreenCanvas(m.W, m.H), x = c.getContext('2d');
  x.fillStyle = m.dark ? 'rgb(18,18,18)' : '#fff'; x.fillRect(0, 0, m.W, m.H);   // dark: darkRgb(white), #121212
  x.setTransform(k, 0, 0, k, -m.x0 * m.s, -m.y0 * m.s);
  x.miterLimit = 10;
  const [cx0, cx1] = cellRange(qx0, qx1, S.width, S.gx), [cy0, cy1] = cellRange(qy0, qy1, S.height, S.gy);
  const seen = new Uint8Array(S.pStyle.length), list = [];
  for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++)
    for (const i of S.cells[cy * S.gx + cx]) if (!seen[i]) { seen[i] = 1; list.push(i); }
  list.sort((a, b) => a - b);
  let ii = 0;
  const px1 = 1 / k;
  const drawImage = im => { const b = im[bk]; if (b && b !== 'failed') x.drawImage(b, im.x0, im.y0, im.x1 - im.x0, im.y1 - im.y0); };
  for (const i of list) {
    while (ii < imgs.length && imgs[ii].after <= i) drawImage(imgs[ii++]);
    const b = i * 4;
    if (S.bbox[b + 2] < qx0 || S.bbox[b] > qx1 || S.bbox[b + 3] < qy0 || S.bbox[b + 1] > qy1) continue;
    const st = S.styles[S.pStyle[i]], p = path2d(S, i);
    if (st.kind & 2) { x.fillStyle = m.dark ? st.fillDark : st.fill; x.fill(p, st.kind & 4 ? 'evenodd' : 'nonzero'); }
    if (st.kind & 1) {
      x.lineWidth = st.kind & 8 ? px1 : Math.max(st.width, px1);   // hairline, and never thinner than a pixel
      x.lineCap = st.cap; x.lineJoin = st.join; x.strokeStyle = m.dark ? st.strokeDark : st.stroke;
      x.stroke(p);
    }
  }
  while (ii < imgs.length) drawImage(imgs[ii++]);
  if (m.key !== latest) return;
  const bmp = c.transferToImageBitmap();
  postMessage({t: 'frame', key: m.key, bmp}, [bmp]);
}

onmessage = e => {
  const m = e.data;
  if (m.t === 'open') {
    if (sheets.has(m.sheet)) { sheets.get(m.sheet).then(S => S && postMessage({t: 'opened', sheet: m.sheet, w: S.width, h: S.height})); return; }
    const p = fetch(m.url, {credentials: 'same-origin'}).then(r => { if (!r.ok) throw new Error('drawing ' + r.status); return r.arrayBuffer(); })
      .then(parse).then(S => { postMessage({t: 'opened', sheet: m.sheet, w: S.width, h: S.height}); return S; })
      .catch(err => { postMessage({t: 'error', sheet: m.sheet, why: String(err.message || err)}); sheets.delete(m.sheet); return null; });
    sheets.set(m.sheet, p);
  } else if (m.t === 'level') {
    darkLevel(m.url).then(({blob, ms}) => postMessage({t: 'level', id: m.id, blob, ms}))
      .catch(err => postMessage({t: 'level', id: m.id, why: String(err.message || err)}));
  } else if (m.t === 'render') {
    latest = m.key;
    render(m).catch(err => postMessage({t: 'error', sheet: m.sheet, why: String(err.message || err)}));
  }
};
