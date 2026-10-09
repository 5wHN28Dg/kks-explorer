"""systems.js (KSys.systemsView, the web client's port of core views.systemsView) on the cases of
core/tests/test_model.nim ("systems: …"), in Chromium, Firefox and WebKit: the same input data gives the same groups,
order, counts, descriptions, photo coverage and search results as the Nim core. KSys.valveType (core model.valveTypeOf,
tagView's valve_type) on core/tests/test_valvetype.nim's cases and on tests/web/valve-vectors.json (made by the core).
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

    def against_core(self, engine):
        """a generated plant (tests/web/make_systems_vectors.nim): the JS gives exactly the Nim core's answers"""
        with open(os.path.join(REPO, 'tests', 'web', 'systems-vectors.json'), encoding='utf-8') as f:
            V = json.load(f)
        with sync_playwright() as p:
            b = getattr(p, engine).launch()
            pg = b.new_page()
            pg.set_content('<!doctype html><meta charset=utf-8><body></body>')
            pg.add_script_tag(content=self.js)
            got = pg.evaluate("""(V) => { const loc = {}; for (const e of V.locations) (loc[e.kks] ??= []).push(e);
              const out = {}; for (const q of Object.keys(V.expected))
                out[q] = KSys.systemsView({tags: V.tags, sheets: V.sheets, kks: V.kks, loc, photos: V.photos}, q);
              return out }""", V)
            b.close()
        for q, want in V['expected'].items():
            self.assertEqual(got[q], want, f'search {q!r}')

    def test_chromium(self): self.check('chromium')
    def test_firefox(self): self.check('firefox')
    def test_webkit(self): self.check('webkit')
    def test_core_chromium(self): self.against_core('chromium')
    def test_core_firefox(self): self.against_core('firefox')
    def test_core_webkit(self): self.against_core('webkit')


# the valve tags of core/tests/test_valvetype.nim's plant() (a sheet at 2 px per point)
VALVES = [
    {'id': 'a:1', 'sheet': 'a', 'kks': '11LAB70AA501', 'suffix': '', 'symbol': {'type': 'gate valve', 'actuator': 'motor',
     'nc': False, 'conf': 0.93, 'bbox': [200, 60, 240, 96]}},
    {'id': 'a:2', 'sheet': 'a', 'kks': '11LAB70AA502', 'suffix': ''},
    {'id': 'a:3', 'sheet': 'a', 'kks': '11LAB70AA503', 'suffix': '', 'symbol': {'type': 'globe valve', 'actuator': 'none',
     'nc': True, 'conf': 0.8}},
    {'id': 'a:4', 'sheet': 'a', 'kks': '11LAB70AA504', 'suffix': '', 'symbol': 'not an object'}]

# index.html's eff() then KSys.valveType, as the panel calls it (valveTypeOf)
VALVE_RUN = r"""([tags, state]) => {
  const eff = t => { const r = (state.reviews || {})[t.id];
    if (r) { if (r.status === 'rejected') return null; return {...t, kks: r.kks, isa: r.isa || null, suffix: r.suffix || '', status: 'confirmed'} }
    return t };
  const out = {};
  for (const t0 of tags) { const t = eff(t0); if (!t) continue;
    out[t.id] = KSys.valveType(t, (state.equipment || {})[(t.kks || '') + (t.suffix || '')]) }
  return out }"""


class ValveType(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(REPO, 'systems.js'), encoding='utf-8') as f:
            cls.js = f.read()

    def page(self, p, engine):
        b = getattr(p, engine).launch()
        pg = b.new_page()
        pg.set_content('<!doctype html><meta charset=utf-8><body></body>')
        pg.add_script_tag(content=self.js)
        return b, pg

    def check(self, engine):
        with sync_playwright() as p:
            b, pg = self.page(p, engine)
            run = lambda state: pg.evaluate(VALVE_RUN, [VALVES, state])
            v = run({'equipment': {}})
            # the full KKS in a correction: the edited value replaces the drawing's in the same proposal
            corrected = pg.evaluate("""(c) => [KSys.withValveType(c, '  check valve '), KSys.withValveType(c, '   '), c]""",
                                    v['a:3']['confirm'])
            # an infinite number (JSON.parse reads 1e999 as Infinity) never reaches the view
            inf = pg.evaluate("""() => KSys.valveType(JSON.parse('{"id":"a:9","kks":"11LAB70AA509","suffix":"","symbol":'
              + '{"type":"gate valve","actuator":"none","nc":false,"conf":1e999,"bbox":[1e999,0,10,10]}}'), {})""")
            empty = run({'equipment': {'11LAB70AA501': {'custom': [{'k': 'Size', 'v': 'DN50'}, {'k': 'Valve type', 'v': ''}]}}})
            full = run({'equipment': {'11LAB70AA501': {'custom': [{'k': 'f%d' % i, 'v': 'x'} for i in range(100)]}}})
            confirmed = run({'equipment': {'11LAB70AA501': {'custom': [{'k': 'Valve type', 'v': 'gate valve, motor-operated'}]},
                                           '11LAB70AA503': {'custom': [{'k': 'Valve type', 'v': 'check valve'}]},
                                           '11LAB70AA502': {'custom': [{'k': 'Valve type', 'v': 'butterfly valve'}]}}})
            reviewed = run({'equipment': {}, 'reviews': {
                'a:1': {'status': 'confirmed', 'kks': '11LAB70CP501', 'isa': '', 'suffix': ''},
                'a:3': {'status': 'confirmed', 'kks': '11LAB70AA513', 'isa': '', 'suffix': ''}}})
            b.close()
        g = v['a:1']
        self.assertEqual((g['status'], g['text'], g['conf']), ('drawing', 'gate valve, motor-operated', 0.93))
        self.assertEqual(g['line'], 'Valve type: gate valve, motor-operated (from the drawing, unchecked)')
        self.assertEqual(g['box'], [200, 60, 240, 96], 'in the tag\'s own units (level-0 px)')
        self.assertEqual(g['confirm'], {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                         'changes': {'custom': [{'k': 'Valve type', 'v': 'gate valve, motor-operated'}]}, 'base': {'custom': []}}})
        self.assertEqual(v['a:3']['text'], 'globe valve, normally closed')
        self.assertNotIn('box', v['a:3'])
        self.assertIsNone(v['a:2'])
        self.assertIsNone(v['a:4'])
        self.assertEqual(corrected[0]['payload']['changes']['custom'], [{'k': 'Valve type', 'v': 'check valve'}])
        self.assertIsNone(corrected[1])
        self.assertEqual(corrected[2]['payload']['changes']['custom'][0]['v'], 'globe valve, normally closed', 'not changed in place')
        self.assertIsNone(inf['conf'])
        self.assertNotIn('box', inf)
        c = empty['a:1']['confirm']['payload']
        self.assertEqual(c['changes']['custom'], [{'k': 'Size', 'v': 'DN50'}, {'k': 'Valve type', 'v': 'gate valve, motor-operated'}])
        self.assertEqual(c['base']['custom'], [{'k': 'Size', 'v': 'DN50'}, {'k': 'Valve type', 'v': ''}])
        self.assertEqual(full['a:1']['status'], 'drawing')
        self.assertIsNone(full['a:1']['confirm'])
        self.assertEqual(confirmed['a:1'], {'status': 'confirmed', 'text': 'gate valve, motor-operated', 'drawn': 'gate valve, motor-operated',
                                            'label': 'confirmed', 'line': 'Valve type: gate valve, motor-operated (confirmed)',
                                            'drawn_differs': False})
        self.assertEqual((confirmed['a:3']['text'], confirmed['a:3']['drawn'], confirmed['a:3']['drawn_differs']),
                         ('check valve', 'globe valve, normally closed', True))
        self.assertEqual(confirmed['a:2']['text'], 'butterfly valve')
        self.assertIsNone(reviewed['a:1'])
        self.assertEqual(reviewed['a:3']['text'], 'globe valve, normally closed')

    def against_core(self, engine):
        """generated tags (tests/web/make_valve_vectors.nim): the JS gives exactly core tagView's valve_type (its box
        in points: the JS keeps the tag's px, so it is divided by the sheet's scale here)"""
        with open(os.path.join(REPO, 'tests', 'web', 'valve-vectors.json'), encoding='utf-8') as f:
            V = json.load(f)
        with sync_playwright() as p:
            b, pg = self.page(p, engine)
            got = pg.evaluate(VALVE_RUN, [V['tags'], V['state']])
            b.close()
        scale = V['sheets'][0]['scale']
        self.assertEqual(set(got), set(V['expected']))
        for i, want in V['expected'].items():
            g = got[i]
            if g and 'box' in g: g['box'] = [x / scale for x in g['box']]
            self.assertEqual(g, want, i)

    def test_chromium(self): self.check('chromium')
    def test_firefox(self): self.check('firefox')
    def test_webkit(self): self.check('webkit')
    def test_core_chromium(self): self.against_core('chromium')
    def test_core_firefox(self): self.against_core('firefox')
    def test_core_webkit(self): self.against_core('webkit')


if __name__ == '__main__':
    unittest.main()
