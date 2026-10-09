"""systems.js's KSys.coverageView (the web client's port of core views.coverageView) in Chromium, Firefox and WebKit:
core/tests/test_model.nim's coverage cases, and a generated plant (tests/web/make_coverage_vectors.nim) whose answer
must equal the Nim core's exactly. The page's own merge (index.html mergeTags + eff) builds the tags, as on the page.
  .venv/bin/python tests/web/test_coverage.py"""
import copy, json, os, unittest
from playwright.sync_api import sync_playwright

from test_systems import SAMPLE

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# index.html's mergeTags() + eff() (core model.merge), then KSys.coverageView
RUN = r"""(S) => {
  const added = (S.state.added_tags || []).map(a => ({id: 'u:' + a.id, sheet: a.sheet, kks: a.kks, suffix: a.suffix || '', isa: a.isa,
    kind: a.kind, status: a.kks ? 'verified' : 'review', added: a.id}));
  const eff = t => { const r = (S.state.reviews || {})[t.id];
    if (r) { if (r.status === 'rejected') return null; return {...t, kks: r.kks, isa: r.isa || null, suffix: r.suffix || '', status: 'confirmed'} }
    if (t.status === 'review') return {...t, kks: t.kks || null};
    return t };
  const loc = {}; for (const e of S.locations) (loc[e.kks] ??= []).push(e);
  return KSys.coverageView({tags: S.tags.concat(added).map(eff).filter(Boolean), sheets: S.sheets, kks: S.kks, loc,
                            equipment: S.state.equipment || {}, photos: S.state.photos || []}) }"""


# core/tests/test_model.nim "coverage percent": 100 only when all, 0 only when none, else to the nearest (halves up)
PCT = [((0, 300), 0), ((1, 300), 1), ((1, 200), 1), ((199, 200), 99), ((299, 300), 99), ((200, 200), 100), ((1, 3), 33),
       ((2, 3), 67), ((1, 8), 13), ((1, 2), 50), ((3, 200), 2), ((197, 200), 99)]


def run(engine, cases, pct=False):
    with open(os.path.join(REPO, 'systems.js'), encoding='utf-8') as f:
        js = f.read()
    with sync_playwright() as p:
        b = getattr(p, engine).launch()
        pg = b.new_page()
        pg.set_content('<!doctype html><meta charset=utf-8><body></body>')
        pg.add_script_tag(content=js)
        out = [pg.evaluate(RUN, c) for c in cases]
        if pct:
            out.append(pg.evaluate('(P) => P.map(([a, b]) => KSys.pct(a, b))', [list(ab) for ab, _ in PCT]))
        b.close()
    return out


class Coverage(unittest.TestCase):
    def check(self, engine):
        typed = copy.deepcopy(SAMPLE)
        typed['state']['equipment'] = {'11LAB70AA504': {'area': 'pump house'}}
        blank = copy.deepcopy(SAMPLE)
        blank['state']['equipment'] = {'11LAB70AA504': {'area': ' \t', 'notes': 'not a place'}}
        v, t2, b2 = run(engine, [SAMPLE, typed, blank])
        # test_model.nim "coverage: per sheet, per system, totals"
        t = v['total']
        self.assertEqual((t['tags'], t['verified'], t['review'], t['marked'], t['codes']), (5, 2, 0, 1, 5))
        self.assertEqual(t['photos'], {'both': 0, 'equipment': 1, 'plate': 0, 'none': 4})
        self.assertEqual(t['located'], 1)
        self.assertEqual([(s['id'], s['name'], s['codes']) for s in v['sheets']], [('a', 'Sheet A', 5)])
        self.assertEqual([s['sys'] for s in v['systems']], ['', 'HAD', 'LAB'])
        lab = v['systems'][2]
        self.assertEqual((lab['codes'], lab['verified'], lab['located'], lab['sys_name']), (3, 2, 1, 'Feed water piping system'))
        self.assertNotIn('tags', lab)
        # "coverage: a place typed by a person counts"; blanks and other fields don't
        self.assertEqual(t2['total']['located'], 2)
        self.assertEqual(b2['total']['located'], 1)

    def against_core(self, engine):
        with open(os.path.join(REPO, 'tests', 'web', 'coverage-vectors.json'), encoding='utf-8') as f:
            V = json.load(f)
        got, = run(engine, [V])
        self.assertEqual(got, V['expected'])

    def pct_rule(self, engine):
        got, = run(engine, [], pct=True)
        self.assertEqual(got, [want for _, want in PCT])

    def test_pct_chromium(self): self.pct_rule('chromium')
    def test_pct_firefox(self): self.pct_rule('firefox')
    def test_pct_webkit(self): self.pct_rule('webkit')
    def test_chromium(self): self.check('chromium')
    def test_firefox(self): self.check('firefox')
    def test_webkit(self): self.check('webkit')
    def test_core_chromium(self): self.against_core('chromium')
    def test_core_firefox(self): self.against_core('firefox')
    def test_core_webkit(self): self.against_core('webkit')


if __name__ == '__main__':
    unittest.main()
