// Dark drawings (a PDF reader's dark mode for the P&IDs), the web's copy of apps/common/darkcolor.nim: each colour's
// lightness is inverted while its hue stays, then squeezed into [DARK_LO, DARK_HI], so black lines become a soft white,
// white paper #121212 and red markup stays red. Closed form c' = c + 255 - (max + min) (exact in HSL). Integer maths,
// the same numbers as the desktop apps (tests/web/test_dark.py checks them against the Nim function's output).
export const DARK_LO = 18, DARK_HI = 237;
// a line or markup colour (coloured enough, no lighter than HSL 0.6) too dark on the dark sheet is mixed toward DARK_HI
// in sixteenths until its gamma-2 luminance reaches 0.16 of white (3:1 against #121212): as darkcolor.nim
export const RAISE_CHROMA = 48, RAISE_LIGHT = 306, RAISE_Y2 = 104040000;
const SPAN = DARK_HI - DARK_LO;

function dark3(r, g, b, out, i) {
  const mx = r > g ? (r > b ? r : b) : (g > b ? g : b), mn = r < g ? (r < b ? r : b) : (g < b ? g : b), k = 255 - mx - mn;
  const r0 = DARK_LO + (((r + k) * SPAN + 127) / 255 | 0), g0 = DARK_LO + (((g + k) * SPAN + 127) / 255 | 0),
        b0 = DARK_LO + (((b + k) * SPAN + 127) / 255 | 0);
  let dr = r0, dg = g0, db = b0;
  if (mx - mn >= RAISE_CHROMA && mx + mn <= RAISE_LIGHT)
    for (let s = 1; s <= 16 && 2126 * dr * dr + 7152 * dg * dg + 722 * db * db < RAISE_Y2; s++) {
      dr = r0 + ((DARK_HI - r0) * s >> 4); dg = g0 + ((DARK_HI - g0) * s >> 4); db = b0 + ((DARK_HI - b0) * s >> 4);
    }
  out[i] = dr; out[i + 1] = dg; out[i + 2] = db;
}

/** the dark-mode colour of an 8-bit RGB colour → [r, g, b] */
export function darkRgb(r, g, b) { const o = [0, 0, 0]; dark3(r, g, b, o, 0); return o; }

/** in place over packed RGBA (straight alpha, alpha untouched) */
export function darkenPixels(px) {
  for (let i = 0, n = px.length; i + 2 < n; i += 4) dark3(px[i], px[i + 1], px[i + 2], px, i);
  return px;
}

/** a marker colour (0..1 channels) raised toward white so it stays readable on the dark sheet */
export function lightenForDark(r, g, b, amount = 0.35) {
  return [r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount];
}
