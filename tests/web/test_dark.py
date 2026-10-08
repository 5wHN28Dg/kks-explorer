"""dark.js (dark drawings) against apps/common/darkcolor.nim in Chromium, Firefox and WebKit: darkRgb and darkenPixels on
the Nim function's output for every grey and a colour grid (tests/web/dark-vectors.json, made by make_dark_vectors.nim),
and index.html's dark tag colours: dark.js's lightenForDark of the light ones, each 3:1 against the dark paper.
  /path/to/venv-with-playwright/bin/python tests/web/test_dark.py
WebKit on Linux may need PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=1 (see platform/linux/e2e/test_web_v2.py)."""
import json, os, re, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

RUN = r"""(V) => {
  const got = V.rgb.map(([r, g, b]) => darkRgb(r, g, b));
  const px = new Uint8ClampedArray(V.rgb.length * 4);
  V.rgb.forEach(([r, g, b], i) => px.set([r, g, b, i & 255], i * 4));
  darkenPixels(px);
  const buf = []; for (let i = 0; i < V.rgb.length; i++) buf.push([px[i * 4], px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3]]);
  return {lo: DARK_LO, hi: DARK_HI, got, buf, light: lightenForDark(0.1, 0.4, 0.9)};
}"""


def hexrgb(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def contrast(a, b):
    def lum(c):
        f = lambda x: x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
        r, g, b = [v / 255 for v in c]
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


class Dark(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(os.path.dirname(__file__), 'dark-vectors.json')) as f: cls.V = json.load(f)
        with open(os.path.join(REPO, 'dark.js'), encoding='utf-8') as f: cls.js = f.read().replace('export ', '')

    def check(self, engine):
        with sync_playwright() as p:
            b = getattr(p, engine).launch()
            pg = b.new_page()
            pg.set_content('<!doctype html><meta charset=utf-8><body></body>')
            pg.add_script_tag(content=self.js)
            r = pg.evaluate(RUN, self.V)
            b.close()
        self.assertEqual((r['lo'], r['hi']), (self.V['lo'], self.V['hi']))
        for v, got, buf in zip(self.V['rgb'], r['got'], r['buf']):
            self.assertEqual(got, v[3:], f'{engine}: darkRgb{tuple(v[:3])}')
            self.assertEqual(buf[:3], v[3:], f'{engine}: darkenPixels{tuple(v[:3])}')
        self.assertEqual([b[3] for b in r['buf']], [i & 255 for i in range(len(self.V['rgb']))], 'alpha changed')
        for got, want in zip(r['light'], (0.415, 0.61, 0.935)): self.assertAlmostEqual(got, want)

    def test_chromium(self): self.check('chromium')
    def test_firefox(self): self.check('firefox')
    def test_webkit(self): self.check('webkit')

    def test_tag_colours(self):
        """index.html: each dark tag colour is lightenForDark (0.35) of its light colour, and reaches 3:1 on #121212"""
        with open(os.path.join(REPO, 'index.html'), encoding='utf-8') as f: src = f.read()
        light = dict(re.findall(r'--(ok|review|accent):(#[0-9a-f]{6})', src.split('body.darkdwg')[0]))
        light |= dict(re.findall(r'\.p-(\w+)\{--pc:(#[0-9a-f]{6})\}', src.split('body.darkdwg')[0]))
        block = re.search(r'body\.darkdwg #viewer\{([^}]*)\}', src)[1]
        dark = dict(re.findall(r'--(ok|review|accent):(#[0-9a-f]{6})', block))
        dark |= dict(re.findall(r'body\.darkdwg :is\(\.hs,\.sw\)\.p-(\w+)\{--pc:(#[0-9a-f]{6})\}', src))
        self.assertEqual(set(dark), {'ok', 'review', 'accent', 'both', 'equipment', 'plate', 'none'})
        bg = (self.V['lo'],) * 3
        for k, h in dark.items():
            want = tuple(round((c / 255 + (1 - c / 255) * 0.35) * 255) for c in hexrgb(light[k]))
            self.assertEqual(hexrgb(h), want, k)
            self.assertGreaterEqual(contrast(hexrgb(h), bg), 3.0, k)


if __name__ == '__main__':
    unittest.main()
