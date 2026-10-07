// Dark drawings (a PDF reader's dark mode for the P&IDs), the web's copy of apps/common/darkcolor.nim: each colour's
// lightness is inverted while its hue stays, then squeezed into [DARK_LO, DARK_HI], so black lines become a soft white,
// white paper #121212 and red markup stays red. Closed form c' = c + 255 - (max + min) (exact in HSL). Integer maths,
// the same numbers as the desktop apps (tests/web/test_dark.py checks them against the Nim function's output).
export const DARK_LO = 18, DARK_HI = 237;
const SPAN = DARK_HI - DARK_LO;

/** the dark-mode colour of an 8-bit RGB colour → [r, g, b] */
export function darkRgb(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), k = 255 - mx - mn;
  return [DARK_LO + (((r + k) * SPAN + 127) / 255 | 0), DARK_LO + (((g + k) * SPAN + 127) / 255 | 0),
          DARK_LO + (((b + k) * SPAN + 127) / 255 | 0)];
}

/** in place over packed RGBA (straight alpha, alpha untouched) */
export function darkenPixels(px) {
  for (let i = 0, n = px.length; i + 2 < n; i += 4) {
    const r = px[i], g = px[i + 1], b = px[i + 2];
    const k = 255 - (r > g ? (r > b ? r : b) : (g > b ? g : b)) - (r < g ? (r < b ? r : b) : (g < b ? g : b));
    px[i] = DARK_LO + (((r + k) * SPAN + 127) / 255 | 0);
    px[i + 1] = DARK_LO + (((g + k) * SPAN + 127) / 255 | 0);
    px[i + 2] = DARK_LO + (((b + k) * SPAN + 127) / 255 | 0);
  }
  return px;
}

/** a marker colour (0..1 channels) raised toward white so it stays readable on the dark sheet */
export function lightenForDark(r, g, b, amount = 0.35) {
  return [r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount];
}
