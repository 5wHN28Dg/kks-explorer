"""Walkdown Plant's generated P&IDs (docs/plant3d/REALISM.md §6.1.1, milestone DC1; tools/plant3d/pid.py):
- the set is made from the content and passes the tool's own checks (symbols apart, texts clear);
- every drawn code has exactly one home, every model code a P&ID shows is drawn, what a P&ID doesn't show has none;
- every part kind shown has a symbol; every character drawn is in the lettering;
- the output is the same on every run;
- an off-sheet connector names a sheet that has its code;
- a revision clouds what changed and adds a row to the table;
- the checks refuse overlapping texts and symbols."""
import copy, hashlib, json, os, subprocess, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))
import pid                # noqa: E402
import pid_font as F      # noqa: E402
import pid_symbols as S   # noqa: E402


class Drawings(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plant, cls.areas, cls.model_codes = pid.load()
        cls.items = pid.items_of(cls.areas)
        cls.sheets, cls.index = pid.make()

    def test_the_set(self):
        ids = [s['id'] for s in self.index['sheets']]
        self.assertEqual(ids, [s['id'] for s in pid.SHEETS])
        self.assertEqual(ids[0], 'legend')
        self.assertEqual(set(ids), set(self.sheets))
        for i, s in enumerate(self.index['sheets']):
            d = self.sheets[s['id']].data()
            self.assertEqual(d['format'], 'walkdown-plant-drawing')
            self.assertEqual(d['version'], 1)
            self.assertEqual(d['number'], 'WDP-PID-%03d' % (i + 1))
            self.assertEqual(d['revisions'], [pid.REV0])
            self.assertEqual(d['size'], [841.0, 594.0])

    def test_every_code_has_one_home(self):
        homes = {}
        for sid, sh in self.sheets.items():
            for code, box, home in sh.spots:
                if home:
                    self.assertNotIn(code, homes, f'{code} has two homes')
                    homes[code] = sid
        self.assertEqual(homes, self.index['home'])
        drawn = {c for c, it in self.items.items() if pid.drawn(it, self.items)}
        self.assertEqual(set(homes), drawn)
        # every code of the model a P&ID shows is on a sheet; what it doesn't show (electrical, desks, lifting gear)
        # has no home, so its card has no Drawing button
        for c in self.model_codes:
            if c in self.items and pid.drawn(self.items[c], self.items):
                self.assertIn(c, homes)
        for code in ('10BAC10', '10BAT10', '00CWA10', '10SNB10', '30SMT10AE001', '10SMF10CW001', '10MBJ10'):
            self.assertIn(code, self.items)
            self.assertNotIn(code, homes, f'{code} is not on a P&ID')
        # the first train's main items, by name
        for code in ('10HNA10', '10HAH30', '10LAC10AP001', '30MAA10', '30MAG10AC001', '30PAC10AP002', '30PAD10',
                     '10MBA10', '10LBA30BR001', '10LBA30AA901', '10HAD30CL001', '30PAC10CP501'):
            self.assertIn(code, homes)

    def test_every_shown_kind_has_a_symbol(self):
        for c, it in self.items.items():
            if not pid.drawn(it, self.items) or it.role == 'pipe':
                continue
            self.assertTrue(it.kind in S.EQUIPMENT or it.kind in S.VALVES or it.kind in S.INSTRUMENTS,
                            f'{c}: no symbol for {it.kind}')
            if it.kind in S.EQUIPMENT or it.kind in S.VALVES:
                self.assertIn(it.kind, S.LEGEND)
        # a kind with no symbol is refused, naming the code
        it = self.items['30PAC10AP001']
        it2 = copy.copy(it)
        it2.kind = 'warp_core'
        with self.assertRaisesRegex(pid.LayoutError, 'no symbol for part kind'):
            pid.Block(it2, [], [], self.items)

    def test_instrument_letters(self):
        self.assertEqual(S.isa_letters('10HAD30CP001', 'pressure_transmitter'), 'PT')
        self.assertEqual(S.isa_letters('10MBR10CT001', 'temperature_element'), 'TE')
        self.assertEqual(S.isa_letters('30PAC10CP501', 'pressure_gauge'), 'PI')
        self.assertEqual(S.isa_letters('10HAD30CL501', 'level_glass'), 'LG')
        self.assertEqual(S.isa_letters('30PAD10CY001', 'vibration_probe'), 'VE')
        self.assertEqual(S.isa_letters('00GCB21CQ001', 'local_panel'), 'AIT')
        texts = {t[5] for sh in self.sheets.values() for t in sh.texts}
        self.assertIn('PT', texts)
        self.assertIn('10HAD30CP001', texts)

    def test_lettering(self):
        for sh in self.sheets.values():
            for t in sh.texts:
                self.assertEqual(F.check(t[5]), [], t[5])
                self.assertEqual(t[5], t[5].upper())
        g = self.index['lettering']
        self.assertEqual((g['advance'], g['cap']), (F.ADVANCE, F.CAP))
        for ch in 'ABCXYZ0123456789-/().,:':
            self.assertIn(ch, g['glyphs'])
        sh = pid.Sheet('x', 'WDP-PID-999', 'x')
        with self.assertRaisesRegex(pid.LayoutError, 'no glyph'):
            sh.text(0, 0, 2, 'TEMPERATURE ~ 5', 0, 0, 'o')
        self.assertAlmostEqual(F.width('ABC', 6.0), 14.0)

    def test_the_same_every_run(self):
        a = pid.files()
        b = pid.files()
        self.assertEqual(a, b)
        self.assertEqual(sorted(a), sorted(['index.json'] + [s['id'] + '.json' for s in pid.SHEETS]))
        for text in a.values():
            json.loads(text)
        # the whole set stays small (the package's budget, REALISM.md §11)
        self.assertLess(sum(len(v) for v in a.values()), 1_500_000)

    def test_connectors_name_a_sheet_that_has_the_code(self):
        n = 0
        for sid, sh in self.sheets.items():
            for target, code, box in sh.links:
                self.assertNotEqual(target, sid)
                self.assertTrue(any(c == code for c, _, _ in self.sheets[target].spots), (sid, target, code))
                n += 1
        self.assertGreater(n, 10)
        # the HP steam leaves the HRSG's sheet for the steam turbine's, at the HP turbine
        self.assertIn(('st', '30MAA10'), {(t, c) for t, c, _ in self.sheets['hrsg1'].links})

    def test_drawn_within_the_frame(self):
        for sid, sh in self.sheets.items():
            for w, d, pts, o in sh.lines:
                for x, y in pts:
                    self.assertTrue(0 <= x <= 841 and 0 <= y <= 594, (sid, o, x, y))
            for code, (x0, y0, x1, y1), home in sh.spots:
                if home:
                    self.assertTrue(pid.FRAME[0] <= x0 and x1 <= pid.FRAME[2] and pid.FRAME[1] <= y0 and
                                    y1 <= pid.FRAME[3], (sid, code))

    def test_revision(self):
        # a synthetic change: a new pressure transmitter on feedwater pump B
        areas = copy.deepcopy(self.areas)
        for e in areas['hrsg1']['equipment']:
            if e['kks'] == '10LAC10AP002':
                e.setdefault('parts', []).append({'kks': '10LAC10CP009', 'name': 'Feedwater pump B discharge pressure',
                                                  'part': 'pressure_transmitter', 'at': [0, 0, 1]})
        rows = [pid.REV0, ['1', 'Pressure transmitter added on feedwater pump B']]
        pins = {'hrsg1': self.sheets['hrsg1'].positions}
        sheets, index = pid.make(revisions={'hrsg1': rows}, areas_override=areas, pins=pins)
        new = pid.revise(self.sheets['hrsg1'], sheets['hrsg1'], '1', rows[1][1])
        d = new.data()
        self.assertEqual(d['revisions'], rows)
        self.assertEqual(index['home']['10LAC10CP009'], 'hrsg1')
        spot = next(b for c, b, h in new.spots if c == '10LAC10CP009' and h)
        clouded = [c for c in d['clouds'] if c[0] == '1']
        self.assertTrue(clouded)
        self.assertTrue(any(c[1] <= spot[0] and c[2] <= spot[1] and spot[2] <= c[3] and spot[3] <= c[4]
                            for c in clouded), 'the new transmitter is not clouded')
        # what did not move is not clouded: the HRSG's casing and the HP drum
        for code in ('10HNA10', '10HAD30BB001'):
            b = next(b for c, b, h in new.spots if c == code and h)
            self.assertFalse(any(c[1] <= b[0] and c[2] <= b[1] and b[2] <= c[3] and b[3] <= c[4] for c in clouded),
                             code)
        # the title block shows the revision in force, the table both rows
        texts = [t[5] for t in new.texts]
        self.assertIn('PRESSURE TRANSMITTER ADDED ON FEEDWATER PUMP B', texts)
        # a code that is gone is clouded where it was
        gone = pid.revise(sheets['hrsg1'], self.sheets['hrsg1'], '2', 'Transmitter removed')
        self.assertTrue(any(c[0] == '2' for c in gone.data()['clouds']))

    def test_checks_refuse_overlaps(self):
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.text(100, 100, 2.5, 'ONE', 0, 0, 'a')
        sh.text(101, 100, 2.5, 'TWO', 0, 0, 'b')
        with self.assertRaisesRegex(pid.LayoutError, 'overlap'):
            pid.check_sheet(sh)
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.symbols += [((0, 0, 10, 10), 'a'), ((5, 5, 15, 15), 'b')]
        with self.assertRaisesRegex(pid.LayoutError, 'symbols'):
            pid.check_sheet(sh)
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.text(100, 100, 2.5, 'LABEL', 0, 0, 'a')
        sh.line([(95, 99), (120, 99)], 0.5, 0, 'pipe')
        with self.assertRaisesRegex(pid.LayoutError, 'crosses the text'):
            pid.check_sheet(sh)

    def test_every_pipe_has_a_flow_arrow(self):
        for sid, sh in self.sheets.items():
            if sid == 'legend':
                continue
            drawn_pipes = {o for w, d, pts, o in sh.lines if o in self.items and self.items[o].role == 'pipe'}
            self.assertTrue(drawn_pipes)
            arrows = {o for pts, o in sh.fills if len(pts) == 3}
            self.assertEqual(drawn_pipes - arrows, set(), sid)

    def test_lines_and_labels(self):
        sh = self.sheets['hrsg1']
        widths = lambda code: {w for w, d, pts, o in sh.lines if o == code}
        self.assertEqual(widths('10LBA30BR001'), {0.7})      # DN 300
        self.assertEqual(widths('10LCQ10BR001'), {0.5})      # DN 80
        label = ' '.join(t[5] for t in sh.texts if t[6] == '10LBA30BR001#label')
        for part in ('10LBA30BR001', 'DN300', 'HP STEAM'):
            self.assertIn(part, label)
        # an off-sheet connector: an arrow pentagon (six points, closed) with the other sheet's number
        pent = [pts for w, d, pts, o in sh.lines if o.startswith('10LBA30BR001#end')]
        self.assertTrue(pent and len(pent[0]) == 6 and pent[0][0] == pent[0][-1])
        self.assertIn('WDP-PID-004', [t[5] for t in sh.texts if t[6] == '10LBA30BR001#end1'])
        # the title block's fields
        texts = [t[5] for t in sh.texts]
        for f in ('WDP-PID-003', '3 OF 10', '0', 'HRSG 1: FEEDWATER, DRUMS AND STEAM', 'GENERIC 2-2-1 COMBINED-CYCLE PLANT'):
            self.assertIn(f, texts)

    def test_crossings_are_broken(self):
        plant, areas = self.plant, self.areas
        n = 0
        for i, meta in enumerate(pid.SHEETS[1:], 1):
            g = pid.Gen(plant, areas, i, self.items, pid.SHEETS)
            sh = g.make()
            for pp in g.pipes:
                if not pp.get('crossings'):
                    continue
                n += 1
                pieces = [pts for w, d, pts, o in sh.lines if o == pp['code']]
                self.assertEqual(len(pieces), len(pp['crossings']) + 1, pp['code'])
                for c in pp['crossings']:
                    for pts in pieces:
                        for a, b in zip(pts, pts[1:]):
                            self.assertFalse(pid.point_on(c, a, b), (pp['code'], c))
        self.assertGreater(n, 0, 'no pipe crosses another anywhere: the case is not tested')

    def test_the_legend_shows_every_symbol_used(self):
        texts = {t[5] for t in self.sheets['legend'].texts}
        used = {it.kind for it in self.items.values() if pid.drawn(it, self.items) and it.role != 'pipe'}
        for kind in used:
            if kind in S.EQUIPMENT:            # equipment names wrap at 24 characters, valves' don't
                self.assertIn(pid.wrap(S.LEGEND[kind].upper(), 24)[0], texts, kind)
            elif kind in S.VALVES:
                self.assertIn(S.LEGEND[kind].upper(), texts, kind)
        for letters in ('PT', 'ANALYSIS', 'TRANSMITTER', 'HOW A CODE READS (KKS)'):
            self.assertIn(letters, texts)

    def test_two_homes_are_refused(self):
        a = pid.Sheet('a', 'WDP-PID-901', 'a')
        b = pid.Sheet('b', 'WDP-PID-902', 'b')
        a.spot('10LAC10AP001', (0, 0, 1, 1), True)
        b.spot('10LAC10AP001', (0, 0, 1, 1), False)
        self.assertEqual(pid.homes_of({'a': a, 'b': b}), {'10LAC10AP001': 'a'})
        b.spot('10LAC10AP001', (2, 2, 3, 3), True)
        with self.assertRaisesRegex(pid.LayoutError, 'home on a and on b'):
            pid.homes_of({'a': a, 'b': b})

    def test_the_same_whatever_the_hash_seed(self):
        code = ('import hashlib, sys; sys.path.insert(0, %r); import pid; f = pid.files(); '
                'print(hashlib.sha256("".join(k + f[k] for k in sorted(f)).encode()).hexdigest())'
                % os.path.join(ROOT, 'tools', 'plant3d'))
        out = set()
        for seed in ('1', '2'):
            r = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True, timeout=300,
                               env=dict(os.environ, PYTHONHASHSEED=seed))
            self.assertEqual(r.returncode, 0, r.stderr)
            out.add(r.stdout.strip())
        self.assertEqual(len(out), 1)

    def test_checks_see_the_exact_geometry(self):
        # a line through another owner's symbol (a leader through a valve); the pipe the valve sits on may
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.symbols.append(((100, 100, 108, 105), 'V1'))
        sh.hosts['V1'] = 'P1'
        sh.line([(90, 102.5), (120, 102.5)], 0.5, 0, 'P1')
        sh.line([(104, 90), (104, 99.9)], 0.25, 0, 'L1')            # ends on its edge: a joint
        pid.check_sheet(sh)
        sh.line([(103, 90), (103, 120)], 0.25, 0, 'L2')
        with self.assertRaisesRegex(pid.LayoutError, 'runs through the symbol of V1'):
            pid.check_sheet(sh)
        # two owners' lines along each other
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.line([(0, 50), (40, 50)], 0.5, 0, 'P1')
        sh.line([(30, 50), (60, 50)], 0.25, 0, 'P2#label')
        with self.assertRaisesRegex(pid.LayoutError, 'along each other'):
            pid.check_sheet(sh)
        # a text over another owner's filled shape or circle, and a pipe's label on its own pipe
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.text(100, 100, 2.5, 'LABEL', 0, 0, 'P1#label')
        sh.fill([(101, 98), (103, 98), (102, 99.5)], 'P2')
        with self.assertRaisesRegex(pid.LayoutError, 'filled shape'):
            pid.check_sheet(sh)
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.text(100, 100, 2.5, 'LABEL', 0, 0, 'P1#label')
        sh.line([(95, 99), (120, 99)], 0.5, 0, 'P1')
        with self.assertRaisesRegex(pid.LayoutError, 'crosses the text'):
            pid.check_sheet(sh)
        sh = pid.Sheet('t', 'WDP-PID-999', 't')
        sh.text(100, 100, 2.5, 'LABEL', 0, 0, '#legend')
        sh.line([(95, 99), (120, 99)], 0.5, 0, '#sym:pump')
        with self.assertRaisesRegex(pid.LayoutError, 'crosses the text'):
            pid.check_sheet(sh)

    def test_content_mistakes_are_named(self):
        areas = copy.deepcopy(self.areas)
        areas['bop']['equipment'].append(copy.deepcopy(areas['bop']['equipment'][0]))
        with self.assertRaisesRegex(pid.LayoutError, 'twice'):
            pid.items_of(areas)
        areas = copy.deepcopy(self.areas)
        areas['wtp']['equipment'].append({'kks': '00GZZ10BB001', 'name': 'A tank no sheet takes',
                                          'part': 'tank_vertical', 'at': [400, 100, 0]})
        with self.assertRaisesRegex(pid.LayoutError, 'no sheet takes'):
            pid.make(areas_override=areas)

    def test_an_item_at_the_pipes_start_goes_with_it(self):
        # `at` 0.0 is the pipe's very start, not "unset": an item there beside an end on another sheet whose equipment
        # shares its system group is drawn on that end's stub
        areas = copy.deepcopy(self.areas)
        for p in areas['bop']['pipes']:
            if p['kks'] == '00LBG10BR001':           # turned round: from the HP turbine (on st) to the boiler
                p['from'], p['to'] = p['to'], p['from']
                p['valves'][0]['at'] = 0.0               # 30MAW10AA001, beside the turbine
        items = pid.items_of(areas)
        ids = [s['id'] for s in pid.SHEETS]
        inline = {}
        for sid in ('bop', 'st'):
            g = pid.Gen(self.plant, areas, ids.index(sid), items, pid.SHEETS)
            g.collect()
            inline[sid] = [it.code for pp in g.pipes if pp['code'] == '00LBG10BR001' for it in pp['inline']]
        self.assertEqual(inline, {'bop': [], 'st': ['30MAW10AA001']})

if __name__ == '__main__':
    unittest.main()
