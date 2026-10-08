// libjxl and zxing-cpp in WebAssembly, our own build (decision 0037, platform/web/build-wasm.sh): JPEG XL decode and
// encode, QR read and write. The SIMD build where the engine has WebAssembly SIMD, else the scalar one. An ES module;
// loaded only when a page needs it (a browser without JPEG XL, a photo to send, a QR code).
const simd = (() => { try {   // the smallest module using a v128 instruction (i8x16.popcnt on a zero vector)
  return WebAssembly.validate(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11]));
} catch (e) { return false } })();
let mod = null, dec = null;
/** everything (encoding, QR codes): about 1.5 MB compressed */
export function load() {
  // (a load that failed, offline, is not kept: the next call tries again)
  return mod ??= import(simd ? '/vendor/kks/kks-simd.js' : '/vendor/kks/kks.js').then(m => m.default()).catch(e => { mod = null; throw e });
}
/** JPEG XL decoding only, for browsers that can't show it themselves (smaller; the full module serves too if loaded) */
function loadDecoder() {
  return mod ?? (dec ??= import(simd ? '/vendor/kks/kks-simd-dec.js' : '/vendor/kks/kks-dec.js').then(m => m.default()).catch(e => { dec = null; throw e }));
}
export const variant = simd ? 'simd' : 'scalar';

function copyIn(M, bytes) { const p = M._kks_malloc(bytes.length || 1); M.HEAPU8.set(bytes, p); return p }

/** JPEG XL bytes → {width, height, rgba: Uint8ClampedArray} */
export async function jxlDecode(bytes) {
  const M = await loadDecoder(), src = copyIn(M, new Uint8Array(bytes)), wh = M._kks_malloc(8);
  try {
    const out = M._kks_jxl_decode(src, bytes.byteLength ?? bytes.length, wh);
    if (!out) throw new Error('not a JPEG XL image this decoder can read');
    const w = M.HEAPU32[wh >> 2], h = M.HEAPU32[(wh >> 2) + 1];
    const rgba = new Uint8ClampedArray(M.HEAPU8.slice(out, out + w * h * 4).buffer);
    M._kks_free(out);
    return {width: w, height: h, rgba};
  } finally { M._kks_free(src); M._kks_free(wh) }
}

/** RGBA pixels → a lossy JPEG XL codestream (Uint8Array) */
export async function jxlEncode(rgba, width, height, distance = 1.9, effort = 7) {
  const M = await load(), src = copyIn(M, rgba), len = M._kks_malloc(4);
  try {
    const out = M._kks_jxl_encode(src, width, height, distance, effort, len);
    if (!out) throw new Error('the photo could not be encoded');
    const n = M.HEAPU32[len >> 2], r = M.HEAPU8.slice(out, out + n);
    M._kks_free(out);
    return r;
  } finally { M._kks_free(src); M._kks_free(len) }
}

/** a grayscale frame (1 byte per pixel) → the text of the first QR code, or null */
export async function qrRead(lum, width, height) {
  const M = await load(), src = copyIn(M, lum);
  try {
    const out = M._kks_qr_read(src, width, height);
    if (!out) return null;
    let end = out; while (M.HEAPU8[end]) end++;
    const s = new TextDecoder().decode(M.HEAPU8.slice(out, end));
    M._kks_free(out);
    return s;
  } finally { M._kks_free(src) }
}

/** text → {side, modules: Uint8Array (0 dark, 255 light), quiet zone included} */
export async function qrWrite(text) {
  const M = await load(), t = new TextEncoder().encode(text + '\0'), src = copyIn(M, t), side = M._kks_malloc(4);
  try {
    const out = M._kks_qr_write(src, side);
    if (!out) throw new Error('the text does not fit a QR code');
    const n = M.HEAPU32[side >> 2], r = M.HEAPU8.slice(out, out + n * n);
    M._kks_free(out);
    return {side: n, modules: r};
  } finally { M._kks_free(src); M._kks_free(side) }
}
