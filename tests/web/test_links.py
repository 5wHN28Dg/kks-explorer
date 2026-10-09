"""systems.js KSys.linksView and KSys.findLink (the web client's ports of core views.linksView / findLink and of
model.parseSheets' "links") on tests/web/links-vectors.json, made by the core itself (make_links_vectors.nim), in
Chromium, Firefox and WebKit: every sheet's connectors, boxes in points and targets exactly as the Nim core gives them.
  .venv/bin/python tests/web/test_links.py"""
import json, os, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

RUN = r"""(V) => {
  const out = {};
  for (const id of Object.keys(V.expected)) out[id] = KSys.linksView(V.sheets, id);
  const v = KSys.linksView(V.sheets, V.find_in);
  return {views: out, finds: V.finds.map(f => KSys.findLink(v, f.label, f.x0, f.y0)),
          gone: KSys.findLink(v, 'nothing', 0, 0), none: KSys.linksView(null, 's0')} }"""


class Links(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(REPO, 'systems.js'), encoding='utf-8') as f:
            cls.js = f.read()
        with open(os.path.join(REPO, 'tests', 'web', 'links-vectors.json'), encoding='utf-8') as f:
            cls.v = json.load(f)

    def check(self, engine):
        with sync_playwright() as p:
            b = getattr(p, engine).launch()
            pg = b.new_page()
            pg.set_content('<!doctype html><meta charset=utf-8><body></body>')
            pg.add_script_tag(content=self.js)
            got = pg.evaluate(RUN, self.v)
            b.close()
        for sid, want in self.v['expected'].items():
            self.assertEqual(got['views'][sid], want, sid)
        self.assertEqual(got['finds'], [f['want'] for f in self.v['finds']])
        self.assertEqual((got['gone'], got['none']), (-1, []))
        # the vectors cover what they should: no targets, one, several, the same sheet, the 20-target cap
        counts = [len(x['targets']) for v in self.v['expected'].values() for x in v]
        self.assertIn(0, counts)
        self.assertIn(1, counts)
        self.assertTrue(any(1 < n < 20 for n in counts))
        self.assertIn(20, counts)
        self.assertTrue(any(t['same_sheet'] for v in self.v['expected'].values() for x in v for t in x['targets']))

    def test_chromium(self): self.check('chromium')
    def test_firefox(self): self.check('firefox')
    def test_webkit(self): self.check('webkit')


if __name__ == '__main__':
    unittest.main()
