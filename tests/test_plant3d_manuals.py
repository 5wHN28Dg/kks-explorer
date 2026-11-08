"""Walkdown Plant's equipment manuals (docs/plant3d/REALISM.md §6.2.1, milestone DC2; tools/plant3d/manuals.py):
- the set is made from the texts and the content and passes the generator's checks; the output is the same on every run;
- every manual has the required sections, in the format; a kind has at most one manual; the manuals the trainee needs
  first are there (the transmitter with calibration, HART and troubleshooting; the turbines; pumps; valves);
- every link resolves (sections, manuals, codes, the service file's actions, the Workshop's steps), and the reverse
  links point at sections that link back;
- every troubleshooting cause id is a hidden cause (§2.6) of a fault on the manual's kinds, and the transmitter's table
  names every cause the content has for it;
- every code of a manual's kinds has its own data; part numbers follow the scheme and are unique;
- the figures are listed exactly for the kinds with a Workshop scene;
- the checks refuse a broken link, an unknown cause, a missing section, an unlisted or uncited source;
- no text names a real plant or a manufacturer's product as ours."""
import copy, hashlib, importlib, json, os, re, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))
import manuals as M        # noqa: E402


def runs_text(x):
    """Every string inside a run, block or list, joined."""
    if isinstance(x, str):
        return x
    if isinstance(x, list):
        return ' '.join(runs_text(v) for v in x)
    if isinstance(x, dict):
        return ' '.join(runs_text(v) for k, v in x.items() if k != 'to')
    return ''


class Manuals(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index, cls.manuals = M.make()
        cls.content = M.load_content()

    def test_the_set(self):
        ids = [m['id'] for m in self.index['manuals']]
        self.assertEqual(ids, M.ORDER)
        for i, e in enumerate(self.index['manuals']):
            m = self.manuals[e['id']]
            self.assertEqual(m['format'], 'walkdown-plant-manual')
            self.assertEqual(m['version'], 1)
            self.assertEqual(m['number'], 'WDP-MAN-%03d' % (i + 1))
            secs = [s['id'] for s in m['sections']]
            for r in M.REQUIRED:
                self.assertIn(r, secs, m['id'])
            for s in m['sections']:
                self.assertTrue(s['blocks'] and s['src'], (m['id'], s['id']))
        self.assertEqual(self.index['format'], 'walkdown-plant-manuals')
        for k in ('pressure_transmitter', 'steam_turbine', 'gas_turbine', 'pump_horizontal', 'pump_vertical',
                  'valve_control', 'valve_gate', 'valve_globe', 'valve_ball', 'valve_butterfly', 'valve_check'):
            self.assertIn(k, self.index['kinds'])
        pt = [s['id'] for s in self.manuals['pressure_transmitter']['sections']]
        for s in ('calibration', 'hart', 'troubleshooting'):
            self.assertIn(s, pt)

    def test_same_on_every_run(self):
        a = M.files()
        b = M.files()
        self.assertEqual(a, b)
        # and in another process with another hash seed: the same bytes on disk
        with tempfile.TemporaryDirectory() as d:
            out = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'plant3d', 'manuals.py'), d],
                                 capture_output=True, text=True, env=dict(os.environ, PYTHONHASHSEED='7'))
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertEqual(sorted(os.listdir(d)), sorted(a))
            for n, text in a.items():
                with open(os.path.join(d, n), encoding='utf-8') as f:
                    self.assertEqual(f.read(), text, n)

    def test_links_resolve_and_reverse_links_link_back(self):
        n = {'work': 0, 'workshop': 0, 'kks': 0, 'section': 0}
        for m in self.manuals.values():
            def one(item, m=m):
                t = item['to']
                for k in n:
                    if k in t:
                        n[k] += 1
            M.walk_runs(m['sections'], one)
        for k, v in n.items():
            self.assertGreater(v, 0, 'no %s links' % k)
        for key, (man, sec) in self.index['work'].items():
            kind, action = key.split(':')
            found = []
            s = [x for x in self.manuals[man]['sections'] if x['id'] == sec][0]
            M.walk_runs(s['blocks'], lambda it: found.append(it['to'].get('work')))
            self.assertIn(action, found, key)
            self.assertIn(action, {a['action'] for a in self.content['service'][kind]['actions']})
        for key, (man, sec) in self.index['workshop'].items():
            kind, place = key.split(':')
            found = []
            s = [x for x in self.manuals[man]['sections'] if x['id'] == sec][0]
            M.walk_runs(s['blocks'], lambda it: found.append('%s:%s' % (it['to'].get('workshop'), it['to'].get('place'))))
            self.assertIn(key, found)
        # the transmitter's field procedure opens from its actions
        self.assertEqual(self.index['work']['pressure_transmitter:open_cover'], ['pressure_transmitter', 'troubleshooting'])
        self.assertEqual(self.index['workshop']['pressure_transmitter:sensor_module'], ['pressure_transmitter', 'replacing'])

    def test_troubleshooting_causes(self):
        ids = []
        for m in self.manuals.values():
            for s in m['sections']:
                for b in s['blocks']:
                    for r in b.get('trouble', []):
                        if 'id' in r:
                            ids.append((m['id'], r['id']))
                            known = set()
                            for k in m['kinds']:
                                known |= self.content['causes'].get(k, set())
                            self.assertIn(r['id'], known)
        # every cause the content has for the transmitter is in its table
        pt = {c for m, c in ids if m == 'pressure_transmitter'}
        self.assertEqual(pt, self.content['causes']['pressure_transmitter'])
        self.assertTrue(pt >= {'drift', 'loose'})

    def test_units_and_parts(self):
        for code, it in self.content['items'].items():
            if it.part in self.index['kinds']:
                u = self.index['units'][code]
                self.assertEqual(u['manual'], self.index['kinds'][it.part])
        self.assertEqual(self.index['units']['30MAG10CP002']['rows'][0][0], 'Calibrated range')
        self.assertIn(['Pressure rating', 'PN 160'], self.index['units']['30MAA10AA201']['rows'])
        nums = []
        for m in self.manuals.values():
            parts = [s for s in m['sections'] if s['id'] == 'parts'][0]
            tables = [b['table'] for b in parts['blocks'] if 'table' in b]
            self.assertEqual(len(tables), 1)
            for r in tables[0]['rows']:
                pn = runs_text(r[0])
                self.assertRegex(pn, r'^WDP-%s-[A-Z0-9-]+$' % m['short'])
                nums.append(pn)
        self.assertEqual(len(nums), len(set(nums)))
        # the transmitter's list comes from its Workshop tree: the sealed module is one spare with its insides
        pt = [s for s in self.manuals['pressure_transmitter']['sections'] if s['id'] == 'parts'][0]
        rows = {runs_text(r[0]): runs_text(r[3]) for r in pt['blocks'][1]['table']['rows']}
        self.assertIn('WDP-PT-SENSOR-MODULE', rows)
        self.assertIn('isolating diaphragms', rows['WDP-PT-SENSOR-MODULE'])
        self.assertNotIn('WDP-PT-ISOLATOR', rows)

    def test_figures(self):
        want = set()
        for m in self.manuals.values():
            for k in m['kinds']:
                if k in self.content['workshop']:
                    want |= {(k, 'exploded'), (k, 'cut')}
        got = {(f['kind'], f['view']) for f in self.index['figures']}
        self.assertEqual(got, want)
        self.assertIn(('pressure_transmitter', 'cut'), got)
        for m in self.manuals.values():
            figs = {f['id'] for f in m['figures']}
            for s in m['sections']:
                for b in s['blocks']:
                    if 'figure' in b:
                        self.assertIn(b['figure'], figs)
            # a kind without a Workshop scene has no figure yet, and no figure block left behind
            for k in m['kinds']:
                if k not in self.content['workshop']:
                    self.assertFalse(any(f['kind'] == k for f in m['figures']))

    # words a generic manual never holds (the names of real places and companies), kept as the first 16 hex digits of
    # their lowercase SHA-256 so that this public file doesn't spell them out
    NOT_GENERIC = {'8d71046f44eafb6d', '191a42bb95c1e8cf', 'b6a3df8ad16ab20e', '90208d0aea7ca76e', '40d78ccce9816c8c',
                   'c2f2d91c2a31954e', '545e4ba6a171ddfc', 'f429d420086f70a3'}

    def test_generic_words(self):
        for mid, m in self.manuals.items():
            for w in set(re.findall(r'[a-z]+', json.dumps(m, ensure_ascii=False).lower())):
                self.assertNotIn(hashlib.sha256(w.encode()).hexdigest()[:16], self.NOT_GENERIC, (mid, w))


class Refusals(unittest.TestCase):
    """The checks refuse what the texts may get wrong."""

    def _make_with(self, mid, change):
        src = importlib.import_module('manual_texts.' + mid)
        saved = copy.deepcopy(src.MANUAL)
        try:
            change(src.MANUAL)
            with self.assertRaises(M.ManualError) as e:
                M.make()
            return str(e.exception)
        finally:
            src.MANUAL.clear()
            src.MANUAL.update(saved)

    def _add_p(self, man, text, sec='description'):
        [s for s in man['sections'] if s['id'] == sec][0]['blocks'].append({'p': text})

    def test_broken_links(self):
        for text, why in (('[x](#nowhere)', 'section'), ('[x](manual:nothing)', 'manual'),
                          ('[x](kks:99XXX99AA999)', 'code'), ('[x](work:no_such_action)', 'work action'),
                          ('[x](workshop:pressure_transmitter/no_such_part)', 'Workshop step'),
                          ('[x](workshop:pump_horizontal/impeller)', 'Workshop')):
            msg = self._make_with('pressure_transmitter', lambda m, t=text: self._add_p(m, t))
            self.assertIn(why, msg)

    def test_unknown_cause(self):
        def ch(m):
            [s for s in m['sections'] if s['id'] == 'troubleshooting'][0]['blocks'][1]['trouble'][0]['id'] = 'gremlins'
        self.assertIn('gremlins', self._make_with('pressure_transmitter', ch))

    def test_a_cause_of_another_kind(self):
        def ch(m):
            [s for s in m['sections'] if s['id'] == 'troubleshooting'][0]['blocks'][0]['trouble'][0]['id'] = 'drift'
        self.assertIn('drift', self._make_with('pumps', ch))

    def test_missing_section(self):
        self.assertIn('no safety section', self._make_with('valves', lambda m: m['sections'].pop()))

    def test_sources(self):
        self.assertIn('which no section cites', self._make_with(
            'valves', lambda m: m['sources'].append({'id': 'extra', 'cite': 'Something'})))
        self.assertIn('does not list', self._make_with(
            'valves', lambda m: m['sections'][0]['src'].append('nobody')))

    def test_a_figure_no_section_shows(self):
        def ch(m):
            for s in m['sections']:
                s['blocks'] = [b for b in s['blocks'] if b.get('figure') != ['pressure_transmitter', 'cut']]
        self.assertIn('no section shows', self._make_with('pressure_transmitter', ch))

    def test_markup(self):
        self.assertIn('unclosed', self._make_with('valves', lambda m: self._add_p(m, 'a **bold start')))
        self.assertIn('empty', self._make_with('valves', lambda m: self._add_p(m, '  ')))


if __name__ == '__main__':
    unittest.main()
