"""systems.js (KSys.systemsView, the web client's port of core views.systemsView) on the cases of
core/tests/test_model.nim ("systems: …"), in Chromium, Firefox and WebKit: the same input data gives the same groups,
order, counts, descriptions, photo coverage and search results as the Nim core.
  .venv/bin/python tests/web/test_systems.py"""
import json, os, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ENGINES = ('chromium', 'firefox', 'webkit')

# test_model.nim's sample(), as JSON
SAMPLE = {
    'sheets': [{'id': 'a', 'name': 'Sheet A'}],
    'tags': [
        {'id': 'a:1', 'sheet': 'a', 'kks': '11LAB70', 'suffix': '', 'isa': None, 'kind': 'equipment', 'status': 'auto'},
        {'id': 'a:2', 'sheet': 'a', 'kks': '11LAB70AA501', 'suffix': '', 'isa': None, 'kind': 'equipment', 'status': 'auto'},
        {'id': 'a:3', 'sheet': 'a', 'kks': '11HAD70CT101', 'suffix': 'R', 'isa': 'TIAC', 'kind': 'instrument', 'status': 'auto'},
        {'id': 'a:4', 'sheet': 'a', 'kks': None, 'suffix': '', 'isa': None, 'kind': 'other', 'status': 'review'},
        {'id': 'a:5', 'sheet': 'a', 'kks': '11LAB70AA502', 'suffix': '', 'isa': None, 'kind': 'equipment', 'status': 'auto'}],
    'kks': {'systems': {'LAB': 'Feed water piping system', 'HAD': 'HP drum'},
            'components': {'AA': 'Valve', 'CT': 'Temperature measurement'},
            'isa_first': {'T': 'Temperature'}, 'isa_next': {'I': 'Indicate', 'A': 'Alarm', 'C': 'Control'},
            'blocks': {'11': 'Block 1'}},
    'locations': [{'kks': 'LAB70AA501', 'level': '14.50m', 'cabinet': 'C1', 'desc': 'feed valve'},
                  {'kks': 'LAB70AA501', 'level': '14.5 m', 'cabinet': 'C1'}],
    'state': {'reviews': {'a:4': {'status': 'confirmed', 'kks': '11LAB70AA503', 'suffix': '', 'isa': None},
                          'a:5': {'status': 'rejected'}},
              'photos': [{'id': 'p1', 'kks': '11LAB70AA501', 'file': 'x.jxl', 'caption': 'c'}],
              'added_tags': [{'id': '00112233445566778899aabbccddeeff', 'sheet': 'a', 'bbox': [600, 100, 640, 120],
                              'kks': '11LAB70AA504', 'suffix': '', 'isa': None, 'kind': 'equipment', 'note': ''}]},
}

# index.html's mergeTags() + eff() (core model.merge), then KSys.systemsView
RUN = r"""(S) => {
  const added = S.state.added_tags.map(a => ({id: 'u:' + a.id, sheet: a.sheet, kks: a.kks, suffix: a.suffix || '', isa: a.isa,
    kind: a.kind, status: a.kks ? 'verified' : 'review'}));
  const eff = t => { const r = S.state.reviews[t.id];
    if (r) { if (r.status === 'rejected') return null; return {...t, kks: r.kks, isa: r.isa || null, suffix: r.suffix || '', status: 'confirmed'} }
    return t };
  const run = (tags, q) => {
    const loc = {}; for (const e of S.locations) (loc[e.kks] ??= []).push(e);
    return KSys.systemsView({tags: tags.concat(added).map(eff).filter(Boolean), sheets: S.sheets, kks: S.kks, loc,
                             photos: S.state.photos}, q) };
  const two = S.tags.concat([{id: 'b:1', sheet: 'a', kks: '11LAB70AA501', suffix: '', isa: null, kind: 'equipment', status: 'auto'}]);
  return {all: run(S.tags), temperature: run(S.tags, 'temperature'), feed: run(S.tags, 'feed lab70 valve'),
          had: run(S.tags, 'had'), none: run(S.tags, 'nothing like this'), upper: run(S.tags, '  FEED\tValve '),
          two: run(two, '')};
}"""


class Systems(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(REPO, 'systems.js'), encoding='utf-8') as f:
            cls.js = f.read()

    def check(self, engine):
        with sync_playwright() as p:
            b = getattr(p, engine).launch()
            pg = b.new_page()
            pg.set_content('<!doctype html><meta charset=utf-8><body></body>')
            pg.add_script_tag(content=self.js)
            got = pg.evaluate(RUN, SAMPLE)
            b.close()
        v = got['all']
        # a:2 11LAB70AA501, a:3 11HAD70CT101R, a:4 → 11LAB70AA503, added 11LAB70AA504; a:1 11LAB70 doesn't decode; a:5 rejected
        self.assertEqual(v['total'], 5)
        self.assertEqual(len(v['blocks']), 1)
        self.assertEqual((v['blocks'][0]['blk'], v['blocks'][0]['blk_name']), ('11', 'Block 1'))
        systems = v['blocks'][0]['systems']
        self.assertEqual([s['sys'] for s in systems], ['HAD', 'LAB'])
        lab = systems[1]
        self.assertEqual((lab['sys_name'], lab['count']), ('Feed water piping system', 3))
        self.assertEqual(lab['subsystems'][0]['code'], 'LAB70')
        self.assertEqual(lab['subsystems'][0]['fn'], '70')
        self.assertEqual(lab['subsystems'][0]['count'], 3)
        valves = lab['subsystems'][0]['kinds'][0]
        self.assertEqual((valves['comp'], valves['comp_name'], valves['count']), ('AA', 'Valve', 3))
        self.assertEqual([it['code'] for it in valves['items']], ['11LAB70AA501', '11LAB70AA503', '11LAB70AA504'])
        first = valves['items'][0]
        self.assertEqual((first['desc'], first['photos'], first['tag'], first['sheet_name'], first['count']),
                         ('feed valve', 'equipment', 'a:2', 'Sheet A', 1))
        self.assertEqual(valves['items'][2]['tag'], 'u:00112233445566778899aabbccddeeff')
        had = systems[0]
        self.assertEqual((had['sys_name'], had['count'], had['subsystems'][0]['kinds'][0]['comp_name']),
                         ('HP drum', 1, 'Temperature measurement'))
        self.assertEqual(had['subsystems'][0]['kinds'][0]['items'][0]['code'], '11HAD70CT101R')
        self.assertEqual(had['subsystems'][0]['kinds'][0]['items'][0]['photos'], 'none')
        self.assertEqual([x['code'] for x in v['other']], ['11LAB70'])
        self.assertEqual(got['temperature']['total'], 1)
        self.assertEqual(got['feed']['total'], 3)
        self.assertEqual(len(got['had']['blocks'][0]['systems']), 1)
        self.assertEqual(got['none']['total'], 0)
        self.assertEqual(got['none']['blocks'], [])
        self.assertEqual(got['upper']['total'], 3, 'words are split on whitespace and compared without case')
        # a code on two sheets is listed once, with its count
        lab2 = got['two']['blocks'][0]['systems'][1]
        self.assertEqual(lab2['subsystems'][0]['kinds'][0]['items'][0]['count'], 2)
        self.assertEqual(got['two']['total'], 5)

    def test_chromium(self): self.check('chromium')
    def test_firefox(self): self.check('firefox')
    def test_webkit(self): self.check('webkit')


if __name__ == '__main__':
    unittest.main()
