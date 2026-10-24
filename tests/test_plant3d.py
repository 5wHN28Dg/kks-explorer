"""Walkdown Plant content format 1 (docs/PLANT3D.md) and the first train (docs/plant3d/FIRST-TRAIN.md):
- data/plant3d is exactly what tools/plant3d/make_content.py makes, and passes the reference validator (ref/plant3d.py);
- the validator rejects each kind of mistake with its error code (ref/vectors/plant3d-v1.json `reject`);
- the reference engine follows §7 (node values worked out by hand, the step order's rules);
- the vectors are what ref/make_plant3d_vectors.py makes, and replaying their inputs gives their events and values;
- the cold start, run by its procedure, reaches base load in a plausible time with no alarm and no trip;
- every trip and interlock fires as FIRST-TRAIN §4 says, and wrong operator actions are refused or alarmed;
- every alarm row and code of FIRST-TRAIN is in the model, and nothing comes from a real plant."""
import copy, hashlib, json, math, os, re, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))
from ref import plant3d as P, make_plant3d_vectors as G
import make_content

DATA = os.path.join(ROOT, 'data', 'plant3d')
FIRST_TRAIN = os.path.join(ROOT, 'docs', 'plant3d', 'FIRST-TRAIN.md')


def close(a, b, path='', tol=1e-6):
    if isinstance(a, bool) or isinstance(b, bool) or a is None or b is None or isinstance(a, str):
        return None if a == b else f'{path}: {a!r} != {b!r}'
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return None if math.isclose(a, b, abs_tol=tol) else f'{path}: {a} != {b}'
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return f'{path}: length {len(a)} != {len(b)}'
        for i, (x, y) in enumerate(zip(a, b)):
            d = close(x, y, f'{path}[{i}]', tol)
            if d:
                return d
        return None
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            return f'{path}: keys {sorted(set(a) ^ set(b))[:6]}'
        for k in a:
            d = close(a[k], b[k], f'{path}.{k}', tol)
            if d:
                return d
        return None
    return f'{path}: {type(a).__name__} != {type(b).__name__}'


def plain(x):
    return json.loads(json.dumps(x))


def expand(code_range):
    """'10MBD10CY001–004' → the four codes; '30PAC10AA101–103' likewise; a plain code → itself."""
    m = re.fullmatch(r'([0-9A-Z]+?)([0-9]{3})[–-]([0-9]{3})', code_range)
    if not m:
        return [code_range]
    return [f'{m.group(1)}{n:03d}' for n in range(int(m.group(2)), int(m.group(3)) + 1)]


class Content(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.b = P.check_dir(DATA)
        cls.m = cls.b.model

    def test_files_are_what_the_generator_makes(self):
        made = make_content.build()
        on_disk = P.load_dir(DATA)
        self.assertEqual(sorted(made), sorted(on_disk))
        for rel, text in made.items():
            self.assertEqual(on_disk[rel], text.encode(), rel)

    def test_counts(self):
        c = self.b.counts
        self.assertEqual(c['areas'], 9 + 2 + 12)      # the first train; the water treatment plant; the site, the camp and their interiors
        self.assertGreaterEqual(c['equipment'], 150)
        self.assertGreaterEqual(c['pipes'], 25)
        self.assertGreaterEqual(c['tours'], 1)
        self.assertEqual(c['procedures'], 7)          # the cold start, the hot restart, the WTP's three (W2) and two (W3)
        self.assertLessEqual(c['values'], P.MAX['values'])

    def test_screens_show_every_code_of_the_model(self):
        """§7.11: every code the model has something for is on exactly one control room screen or left out, each
        screen the user asked for (2026-10-19) has its systems, and the first train leaves out only hand valves."""
        items = P.screen_items(self.m)
        placed = self.b.screen_of
        left = set(items) - set(placed)
        self.assertEqual(left, {'30PAB10AA401', '30PAB10AA402', '30PAB10AA403', '30PAB10AA404'})
        by_screen = {}
        for code, (sid, _) in placed.items():
            by_screen.setdefault(sid, set()).add(code)
        for sid, code in (('gt', '10MBV10AP001'), ('gt', '10MBP10AA001'), ('hrsg', '10HAD30CL001'),
                          ('hrsg', '10LAE30AA001'), ('hrsg', '10LBA30AA901'), ('st', '30MAJ10AP001'),
                          ('condensate', '30LCB10AP001'), ('condensate', '30MAG10CL001'), ('cw', '30PAC10AP001'),
                          ('ct', '30PAD10AN001'), ('aux', '00PGC10AP001'), ('el', '10BAC10'), ('el', '30MKC10')):
            self.assertIn(code, by_screen.get(sid, set()), f'{code} on screen {sid}')
        # every value with a unit and a code is on its code's screen
        for name, node, _ in self.m.values:
            if 'unit' in node and 'kks' in node:
                self.assertTrue(node['kks'] in placed or node['kks'] in left, name)

    def test_screens_never_leave_out_what_only_they_work(self):
        """§7.11: a code with an alarm or an op from the screens can't be left out (on no tab, never acknowledged)."""
        files = P.load_dir(DATA)
        for code in ('30PAR10AA001', '00QFB10CP001'):      # the makeup valve's screen ops; the air header's alarm
            s = json.loads(files['screens.json'])
            s['left_out'].append({'codes': [code], 'why': 'A test of what may not be left out'})
            files['screens.json'] = json.dumps(s).encode()
            with self.assertRaises(P.FormatError, msg=code) as cm:
                P.check_files(files)
            self.assertEqual(cm.exception.code, 'bad_ref')
            self.assertIn(f'leaves out {code}', str(cm.exception))
            files = P.load_dir(DATA)

    def test_every_first_train_code_is_in_the_plant(self):
        """Every code of FIRST-TRAIN §1 is a piece of equipment, a pipe or a structure, or (for a whole system) the
        system of one. The one exception is written down in FIRST-TRAIN §1."""
        with open(FIRST_TRAIN, encoding='utf-8') as f:
            text = f.read().split('## 2.')[0]
        codes = set(self.b.equipment) | set(self.b.pipes) | \
            {s['kks'] for a in self.b.areas for s in a['structures'] if 'kks' in s}
        listed = set()
        for cell in re.findall(r'^\| ([0-9][^|]*?) \|', text, re.M):
            for part in re.split(r',\s*', cell):
                part = part.strip()
                if re.fullmatch(r'[0-9]{2}[A-Z]{3}[0-9]{2}([A-Z]{2}[0-9]{3})?([–-][0-9]{3})?', part):
                    listed.update(expand(part))
        self.assertGreater(len(listed), 100)
        missing = sorted(c for c in listed if c not in codes and not any(x.startswith(c) for x in codes))
        self.assertEqual(missing, ['30MAC10'])

    def test_every_alarm_row_is_in_the_model(self):
        """Each row of FIRST-TRAIN §5: an alarm for every code of the row, with each of its ISA letter groups, at the
        row's priorities."""
        with open(FIRST_TRAIN, encoding='utf-8') as f:
            text = f.read().split('## 5. Alarms')[1].split('## 6.')[0]
        rows = re.findall(r'^\| ([0-9][0-9A-Z–-]+) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \|$', text, re.M)
        self.assertEqual(len(rows), 43)
        alarms = self.m.alarms
        for code, isa, what, limit, prio in rows:
            isas = [x.strip() for x in isa.split('/')] if isa.strip() not in ('—', '') else [None]
            prios = [int(x) for x in re.findall(r'[123]', prio)]
            for c in expand(code):
                have = [a for a in alarms if a['kks'] == c]
                self.assertTrue(have, f'no alarm on {c} ({what.strip()})')
                for i, letters in enumerate(isas):
                    p = prios[min(i, len(prios) - 1)]
                    hit = [a for a in have if a.get('isa') == letters and a['priority'] == p]
                    self.assertTrue(hit, f'{c}: no alarm {letters} at priority {p} ({what.strip()})')

    def test_trips_and_interlocks_of_first_train_are_in_the_model(self):
        trips = {t['id'] for t in self.m.trips}
        for t in ('gt1_trip_lube', 'gt1_trip_flame', 'gt1_trip_exh', 'gt1_trip_spread', 'gt1_trip_os', 'gt1_trip_vib',
                  'gt1_trip_surge', 'gt1_trip_drum_hh', 'gt1_trip_drum_ll', 'st_trip_lube', 'st_trip_cond_p',
                  'st_trip_os', 'st_trip_axial', 'st_trip_vib', 'st_trip_steam_t', 'cw_a_trip_ol', 'cw_a_trip_ll',
                  'cw_a_trip_valve', 'cep_trip_hw', 'ct_fan1_trip_vib', 'gt1_trip_oil_temp', 'st_trip_oil_temp'):
            self.assertIn(t, trips)
        self.assertIn('gt1_runback', {a['id'] for a in self.m.alarms})         # §4 "As built": the GT runback
        ops = self.m.op_keys
        needs = lambda kks, do: [n[0] for n in ops[(kks, do, None)].get('needs', [])]
        self.assertIn('st_tg_run', needs('30MAW10AA001', 'open'))           # #10 gland steam needs the turning gear
        self.assertIn('byp_permit', needs('30MAN10AA001', 'auto'))          # #16 bypass blocked without the condenser
        self.assertEqual(needs('10BAC10', 'close_breaker')[2:], ['gt1_ph_ok', 'gt1_slip_ok', 'gt1_v_ok'])   # #14
        self.assertIn('cw_a_vstart', needs('30PAC10AP001', 'start'))        # #4 start position
        self.assertIn('st_jack_ok', needs('30MAK10AE001', 'start'))         # #7 order of the oil systems
        self.assertIn('st_ecc_ok', needs('30MAA10', 'roll'))                # #7, #18
        self.assertIn('st_sh_ok', needs('30MAA10', 'roll'))                 # #18 superheat ≥ 50 K
        self.assertIn('st_match', needs('30MAA10', 'roll'))                 # #18 matched to the HP casing
        self.assertIn('st_warm_shut', needs('30MAA10', 'roll'))             # #18 the casing warm-up closed first
        self.assertIn('st_tg_run', needs('30MAA10AA101', 'open'))           # #18 warm-up only on the turning gear

    def test_codes_are_unique_and_decode(self):
        k = self.b.plant['kks']
        for c in self.b.equipment:
            g = P.kks_parts(c)
            self.assertIsNotNone(g, c)
            self.assertIn(g[2], k['systems'])

    def test_nothing_from_a_real_plant(self):
        """The plant is invented (R1): no code of the real plant data in this repository (Walkdown's decoder table
        and plant courses), none of their meaning texts, and no word whose hash is on the list of the real plant's
        names (the names themselves stay out of tracked files)."""
        real_codes = set()
        for name in os.listdir(os.path.join(ROOT, 'data', 'courses')):
            if name.endswith('.json'):
                with open(os.path.join(ROOT, 'data', 'courses', name), encoding='utf-8') as f:
                    real_codes |= set(re.findall(r'\b[0-9]{2}[A-Z]{3}[0-9]{2}(?:[A-Z]{2}[0-9]{3}[A-Z]?)?\b', f.read()))
        ours = set(self.b.equipment) | set(self.b.pipes)
        self.assertFalse(ours & real_codes)
        with open(os.path.join(ROOT, 'data', 'kks.json'), encoding='utf-8') as f:
            walkdown = json.load(f)
        real_texts = set()

        def walk(x):
            if isinstance(x, str) and len(x) > 12:
                real_texts.add(x.strip().lower())
            elif isinstance(x, dict):
                for v in x.values():
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        walk(walkdown)
        k = self.b.plant['kks']
        for t in ('units', 'systems', 'equipment', 'measurements'):
            for meaning in k[t].values():
                self.assertNotIn(meaning.strip().lower(), real_texts, meaning)
        texts = dict(P.load_dir(DATA))
        for name in os.listdir(os.path.join(ROOT, 'tools', 'plant3d')):
            if name.endswith('.py'):
                with open(os.path.join(ROOT, 'tools', 'plant3d', name), 'rb') as f:
                    texts['tools/plant3d/' + name] = f.read()
        for rel, data in texts.items():
            for word in set(re.findall(r'[a-z]+', data.decode('utf-8').lower())):
                self.assertNotIn(hashlib.sha256(word.encode()).hexdigest(), NAME_HASHES, rel)


# SHA-256 of the real plant's place and owner names in lower case (the words themselves never go in tracked files)
NAME_HASHES = {
    '053b985b01d7896155df438f99ff0b9e0b799326d79c74936d81154b63909384',
    '191a42bb95c1e8cf831c4293d651f7d584380e0b9ce32f4cf64bcbc4684dcfe1',
    '40d78ccce9816c8ce1ca78112fd35dbfd4a9f51d9f56f59435e7cb6430236bb6',
    '545e4ba6a171ddfc698e56f6e46bf87f703347f167365275efcf9872cfe6f811',
    '8d71046f44eafb6dfbe67a64f2c58238983b81e9721be439ae730b2e6ffd557f',
    '90208d0aea7ca76ead6e89fbb3f384ea90a47e9f21a4fe2b5a671e7892f008e4',
    'ab9da388c7391005d952b1cafe30eb1b644d5d688ce1df3bbedad8af25612e88',
    'b6a3df8ad16ab20ef9670b56c59827b60202d6db67f3aff7b168f7d228976460',
    'c2f2d91c2a31954e293fe038488e1a411a2fd90c0196c126c918852e3e80a7d9',
}


class WaterTreatment(unittest.TestCase):
    """Milestone W1 (docs/plant3d/MILESTONES.md): the water treatment plant and its intake, walkable, as
    WATER-TREATMENT.md §3-§4 and SITE.md lay them out; its tour; the pipes that tie it to the first train."""

    @classmethod
    def setUpClass(cls):
        cls.areas = {}
        for name in os.listdir(os.path.join(DATA, 'areas')):
            with open(os.path.join(DATA, 'areas', name), encoding='utf-8') as f:
                a = json.load(f)
            cls.areas[a['id']] = a
        cls.codes = {}
        for a in cls.areas.values():
            for e in a['equipment']:
                cls.codes[e['kks']] = (a['id'], e)
                for c in e.get('parts', []):
                    cls.codes[c['kks']] = (a['id'], c)
            for p in a['pipes']:
                cls.codes[p['kks']] = (a['id'], p)
                for v in p.get('valves', []) + p.get('parts', []):
                    cls.codes[v['kks']] = (a['id'], v)

    def test_areas_where_the_site_puts_them(self):
        self.assertEqual(self.areas['wtp']['bounds'], [[270, 45], [390, 135]])      # SITE.md §1
        self.assertEqual(self.areas['intake']['bounds'], [[430, 60], [470, 110]])
        for aid in ('wtp', 'intake'):
            self.assertEqual(self.areas[aid]['pack'], 'wtp')
        with open(os.path.join(DATA, 'plant.json'), encoding='utf-8') as f:
            order = json.load(f)['areas']
        # the water treatment pack's two areas, together after the first train's (the site's and the camp's
        # areas, C1, come after them)
        self.assertEqual(order[order.index('wtp'):order.index('wtp') + 2], ['wtp', 'intake'])
        self.assertGreater(order.index('wtp'), order.index('rack'))

    def test_every_stage_has_its_equipment(self):
        """WATER-TREATMENT.md §3's stages, each by its codes of §4, in the area that holds it."""
        want = {'intake': ['00GAA10AT001', '00GAA10AT002', '00GAA10AT003', '00GAA10CL001', '00GAF10AP001',
                           '00GAF10AP002', '00GAF10AP003', '00GAC10BR010', '00GBN30BB001'],
                'wtp': ['00GBD10AM001', '00GBD11AT001', '00GBD12AT001', '00GBD11CQ001', '00GBD12CQ001', '00GBN10BB001',
                        '00GBN20BB001', '00GBN10AP001', '00GBN10AP002']
                       + [f'00GBB1{n}AT001' for n in range(1, 7)] + [f'00GBB1{n}CP001' for n in range(1, 7)]
                       + ['00GBR10AP001', '00GBR10AP002', '00GBR10AN001', '00GBR10AN002', '00GBL10BB001',
                          '00GHB10AP001', '00GHB10AP002', '00GHA10AP001', '00GHA10AP002', '00GCN10BB001',
                          '00GCN20BB001', '00GCE10BB001', '00GCB11AT001', '00GCB12AT001', '00GCB21AP001',
                          '00GCB22AP001', '00GCB21AT001', '00GCB22AT001', '00GCB21CQ001', '00GCB21CQ002',
                          '00GCB21CP001', '00GCB21CP002', '00GCB21CF001', '00GCB11CP001', '00GCH10AT001',
                          '00GCH10AN001', '00GCK10BB001', '00GCK10AP001', '00GCK10AP002', '00GCF11AT001',
                          '00GCF12AT001', '00GCF11CQ001', '00GCF11CQ002', '00GCP10BB001', '00GCP20BB001',
                          '00GCP30AN001', '00GCL10BB001', '00GCL10BB002', '00GHC10AP001', '00GHC10AP002',
                          '00GNR10BB001', '00GNR10AP001', '00GNR10AP002', '00GNR10AM001', '00GNR10CQ001',
                          '00GBS10AT001', '00GBS20AT001', '00QUG10', '00CWD10']}
        for aid, codes in want.items():
            for code in codes:
                with self.subTest(code=code):
                    self.assertIn(code, self.codes)
                    self.assertEqual(self.codes[code][0], aid)
        buildings = {s.get('kks') for a in ('wtp', 'intake') for s in self.areas[a]['structures']
                     if s['part'] == 'building'}
        self.assertEqual(buildings, {'00UGA10', '00UGD10', '00UGQ10', '00UTS10'})

    def test_tied_to_the_train(self):
        """SITE.md §1: the makeup line ends in the cooling tower's makeup pipe before its valve, the transfer line on
        the plant's demineralised water tank, the raw water main runs from the intake to the rapid mixer."""
        _, mk = self.codes['00GHB10BR001']
        self.assertEqual(mk['from'], {'kks': '00GHB10AP001', 'nozzle': 'discharge'})
        self.assertEqual(mk['to']['pipe'], '30PAR10BR001')
        _, tr = self.codes['00GHC10BR001']
        self.assertEqual(tr['to'], {'kks': '00GHC10BB001', 'nozzle': 'inlet'})
        _, main = self.codes['00GAC10BR010']
        self.assertGreater(main['from']['at'][0], 430)
        mix = self.codes['00GBD10BB001'][1]['at']
        self.assertLess(math.dist(main['to']['at'][:2], mix[:2]), 3.0, 'the raw water main ends under the rapid mixer')

    def test_the_tour_from_the_river_to_the_demin_tank(self):
        with open(os.path.join(DATA, 'procedures', 'wtp_path.json'), encoding='utf-8') as f:
            t = json.load(f)
        self.assertEqual(t['kind'], 'tour')
        stops = [c for s in t['steps'] for c in s['at']]
        self.assertEqual(stops[0], '00GAA10AT001')
        self.assertEqual(stops[-1], '00GHC10BB001')
        for code in stops[:-1]:
            self.assertIn(self.codes[code][0], ('wtp', 'intake'), code)
        self.assertTrue(all(s['go'] == 'walk' for s in t['steps']))

    def test_running_pumps_turn_and_sound(self):
        """W2: every pump and blower of the WTP turns, sounds and lights its lamp by its model value; in the train's
        scenarios the running half of each pair runs (WATER-TREATMENT §8: in service in cold_iron), the standby half
        and the backwash's pump and blower stand still."""
        bind = []
        for aid in ('wtp', 'intake'):
            with open(os.path.join(DATA, 'model', f'{aid}.json'), encoding='utf-8') as f:
                bind += json.load(f)['bind']
        b = P.check_dir(DATA)
        e = P.Engine(b, 'cold_iron')
        shaft = {x['kks']: x['of'] for x in bind if x.get('anim') == 'shaft'}
        sounding = {x['kks'] for x in bind if 'sound' in x}
        lamp = {x['kks'] for x in bind if x.get('lamp') == 'running'}
        for code in ('00GAF10AP001', '00GAF10AP002', '00GHB10AP001', '00GHA10AP001', '00GCB21AP001', '00GCK10AP001',
                     '00GHC10AP001', '00GCH10AN001'):
            self.assertIn(code, sounding & lamp)
            self.assertEqual(e.v(shaft[code]), 1, code)
        for code in ('00GAF10AP003', '00GHB10AP002', '00GCB22AP001', '00GHC10AP002', '00GBR10AP001', '00GBR10AN001'):
            self.assertIn(code, sounding & lamp)
            self.assertEqual(e.v(shaft[code]), 0, code)


_RUNS = {}


def procedure_run(b, pid):
    """A procedure run once as a trainee (P.run_procedure), shared by the tests: (its last engine, its log, a clone of
    the engine at the start of each step, before its operations). Clone what you change."""
    if pid not in _RUNS:
        first = P.Recorder(b, b.procedures[pid]['scenario'])
        steps = [s['id'] for s in b.procedures[pid]['steps']]
        bases = {steps[0]: first.clone()}

        def keep(sid, e):
            i = steps.index(sid)
            if i + 1 < len(steps):
                bases[steps[i + 1]] = e.clone()
        e, log = P.run_procedure(b, pid, eng=first, on_step=keep)
        _RUNS[pid] = (e, log, bases)
    return _RUNS[pid]


class WaterTreatmentModel(unittest.TestCase):
    """Milestone W2 (WATER-TREATMENT.md §5–§8): the WTP started from cold by its procedure, its other procedures run in
    the model alone, the main control room reads its overview without working it, every alarm of §6 is in the model,
    and the ties to the train are transparent while the WTP is in service (the train's values unchanged)."""

    @classmethod
    def setUpClass(cls):
        with open(G.OUT2, encoding='utf-8') as f:
            cls.V2 = json.load(f)
        with open(G.OUT, encoding='utf-8') as f:
            cls.train = json.load(f)['train']
        cls.b = P.check_dir(DATA)

    def test_start_from_cold(self):
        t = self.V2['wtp']
        self.assertEqual((t['scenario'], t['procedure']), ('wtp_cold', 'wtp_start'))
        self.assertEqual([s['id'] for s in self.b.procedures['wtp_start']['steps']], [s for s, _ in t['steps']])
        self.assertEqual({e[1] for e in t['events']}, {'op', 'machine'}, 'no alarm, trip or interlock on the way')
        self.assertTrue(all(e[4] == 'done' for e in t['events'] if e[1] == 'op'))
        init = self.b.scenarios['wtp_cold']['init']
        for st in ('rw_a_cmd', 'rw_b_cmd', 'mk_a_cmd', 'sw_a_cmd', 'mf_a_cmd', 'tr_a_cmd', 'dg_cmd'):
            self.assertEqual(init[st], 0, st)
        for lvl in ('ft_lvl', 'dg_lvl', 'dt_a_lvl', 'dt_b_lvl'):
            self.assertEqual(init[lvl], 60, lvl)
        end = t['snapshots'][-1]
        self.assertEqual(end['machines']['ro_a'], 'service')
        self.assertEqual(end['machines']['mb_a'], 'service')
        v = end['values']
        self.assertEqual(v['mb_a_making'], 1)
        self.assertGreaterEqual(v['tr_q'], 30)
        self.assertGreaterEqual(v['wt_raw'], 1000)
        self.assertLess(v['ro_a_cond'], 50)
        self.assertLess(v['mb_a_cond'], 0.1)
        self.assertEqual(v['mk_avail'], 1)
        self.assertLess(t['until'] / 600, 45, 'about half an hour of model time')

    def test_other_procedures_run_in_the_model_alone(self):
        for pid, last in (('filter_backwash', 'back'), ('ro_stop_flush', 'mb')):
            with self.subTest(pid):
                e, log, _ = procedure_run(self.b, pid)
                self.assertEqual(log[-1][0], last)
                self.assertTrue(all(x[4] == 'done' for x in e.events if x[1] == 'op'))
                self.assertEqual({x[1] for x in e.events} - {'op', 'machine'}, set())
        e, _, _ = procedure_run(self.b, 'filter_backwash')
        moves = [x[4] for x in e.events if x[1] == 'machine' and x[2] == 'filter1']
        self.assertEqual(moves, ['drain', 'air', 'air_water', 'rinse', 'service'])
        self.assertAlmostEqual(e.v('fl1_hl'), 0.3, delta=0.001)     # the clean bed, a little load since

    def test_main_control_room_reads_the_wtp_without_working_it(self):
        """§7: the WTP's own desk works it; the main control room's desks show its overview only (PLANT3D §14)."""
        with open(os.path.join(DATA, 'screens.json'), encoding='utf-8') as f:
            sc = json.load(f)
        main, wtp = {'00CWA10', '00CWB10'}, {'00CWD10'}
        self.assertEqual(set(sc['overview']['desks']), main)
        screen_ops = {o['kks'] for o in self.b.model.ops if 'screen' in o['where']}
        by_id = {x['id']: x for x in sc['screens']}
        for code, (sid, _) in self.b.screen_of.items():
            desks = set(by_id[sid]['desks'])
            if sid.startswith('wtp'):
                if desks & main:
                    self.assertNotIn(code, screen_ops, f'{code}: worked from the main control room')
                if code in screen_ops:
                    self.assertEqual(desks, wtp, code)
        self.assertEqual(set(by_id['wtp']['desks']), main | wtp)
        self.assertEqual(self.b.screen_of['00GHC10BB001'][0], 'aux', 'the plant\'s demin tank on the train\'s screens')

    def test_every_alarm_of_the_table_is_in_the_model(self):
        """WATER-TREATMENT §6, by code and ISA letters."""
        rows = [('00GAA10CL001', 'LAL'), ('00GAA10CL001', 'LALL'), ('00GBD11CQ001', 'QAH'), ('00GBD12CQ001', 'QAH'),
                ('00GBN10BB001', 'LAL'), ('00GBL10CL001', 'LAL'), ('00GCB21CQ002', 'QAH'), ('00GCB21CQ002', 'QAHH'),
                ('00GCB22CQ002', 'QAHH'), ('00GCB11CP001', 'PDAH'), ('00GCB12CP001', 'PDAH'), ('00GCB21CP001', 'PAH'),
                ('00GCB21CP001', 'PAHH'), ('00GCB22CP002', 'PALL'), ('00GCB21CF001', 'FAL'), ('00GCB21CQ001', 'QAH'),
                ('00GCF11CQ001', 'QAH'), ('00GCF12CQ002', 'QAH'), ('00GCL10CL001', 'LAL'), ('00GCL10CL002', 'LALL'),
                ('00GNR10CQ001', 'QAH'), ('00GBS10AT001', 'LAH'), ('00GHC10BB001', 'LAL')] + \
               [(f'00GBB1{i}CP001', 'PDAH') for i in range(1, 7)]
        have = {(a['kks'], a.get('isa')) for a in self.b.model.alarms}
        for r in rows:
            self.assertIn(r, have)
        for code in ('00GAF10AP001', '00GAF10AP002', '00GAF10AP003'):
            self.assertIn(code, {a['kks'] for a in self.b.model.alarms})

    def test_the_ties_are_transparent_while_the_wtp_runs(self):
        """§8: in the cold start the WTP supplies the makeup and the demin tank throughout, so the train's makeup flow
        and hotwell makeup are what they were before the ties (the factor is exactly 1)."""
        for s in self.train['snapshots']:
            v = s['values']
            self.assertEqual((v['ct_mk_sup'], v['mk_avail'], v['dm_ok'], v['hw_mk_ok']), (1, 1, 1, 1), s['step'])
            self.assertAlmostEqual(v['ct_mk_flow'], v['ct_mk_pos'] * 800, delta=1e-6)
            self.assertGreater(v['dm_lvl'], 30)
        nodes = {n: node for n, node, _ in self.b.model.values}
        self.assertEqual(nodes['ct_mk_flow']['product'], ['ct_mk_pos', 800, 'ct_mk_sup'])
        self.assertEqual(nodes['hw_mk_ok']['and'], ['hw_mk_free', 'dm_ok'])

    def _engine(self, base, **init):
        """An engine on a copy of a scenario with some initial values changed."""
        b = copy.copy(self.b)
        b.scenarios = dict(self.b.scenarios)
        sc = copy.deepcopy(self.b.scenarios[base])
        sc['init'].update(init)
        b.scenarios['_t'] = sc
        return P.Engine(b, '_t')

    def test_a_stopped_plant_stays_quiet(self):
        """wtp_cold left alone: no alarm (the standing clarifiers settle instead of going turbid)."""
        e = P.Engine(self.b, 'wtp_cold')
        for _ in range(3000):
            e.step()
        self.assertEqual([x for x in e.events if x[1] == 'alarm'], [])
        self.assertLess(e.v('cl_ntu'), 2)

    def test_pumps_do_not_chatter_at_an_empty_filtered_tank(self):
        """The makeup and service water pumps stop below 5 % and wait for 10 %: with the basin's makeup valve wide
        open by hand and one raw water pump stopped, the makeup does not flip on and off at the limit."""
        e = P.Engine(self.b, 'cold_iron')
        e.op('30PAR10AA001', 'manual')
        e.step()
        e.op('30PAR10AA001', 'set', 1.0)
        e.op('00GAF10AP002', 'stop')
        e.step()
        for _ in range(20000):
            e.step()
            if e.v('ft_lvl') < 6:
                break
        self.assertLess(e.v('ft_lvl'), 6, 'the tank did not empty')
        flips, last = 0, e.v('mk_avail')
        for _ in range(1200):
            e.step()
            flips += e.v('mk_avail') != last
            last = e.v('mk_avail')
        self.assertLessEqual(flips, 2)

    # ---------------------------------------------------------------- milestone W3: the WTP's day work

    def test_ro_cleaned_in_place(self):
        """W3: RO B cleaned by ro_cip from wtp_normal, as the vectors have it: a high-pH then a low-pH cleaning, each
        two stages, a soak and a flush; most of the fouling off, not all; the wastes neutralised and discharged."""
        t = self.V2['wtp_cip']
        self.assertEqual((t['scenario'], t['procedure']), ('wtp_normal', 'ro_cip'))
        self.assertEqual([s['id'] for s in self.b.procedures['ro_cip']['steps']], [s for s, _ in t['steps']])
        self.assertTrue(all(e[4] == 'done' for e in t['events'] if e[1] == 'op'))
        moves = [e[4] for e in t['events'] if e[1] == 'machine' and e[2] == 'ro_b']
        self.assertEqual(moves, ['cip_circ1', 'cip_circ2', 'cip_soak', 'cip_flush', 'stopped'] * 2)
        self.assertNotIn('trip', {e[1] for e in t['events']})
        e0 = P.Engine(self.b, 'wtp_normal')                  # step 0 (the snapshots start at 10 minutes)
        first = {n: e0.v(n) for n in ('ro_b_nflow', 'ro_b_bio', 'ro_b_sc')}
        end = t['snapshots'][-1]['values']
        self.assertLess(first['ro_b_nflow'], 90)
        self.assertGreaterEqual(end['ro_b_nflow'], 98)
        self.assertGreater(end['ro_b_foul'], end['ro_b_irr'] - 1e-9, 'a cleaning never takes the last of it')
        self.assertLess(end['ro_b_bio'], first['ro_b_bio'] / 10)
        self.assertLess(end['ro_b_sc'], first['ro_b_sc'] / 10)
        self.assertEqual(t['snapshots'][-1]['machines']['nr_batch'], 'discharging')
        self.assertTrue(6 <= end['nr_ph'] <= 9)
        # about five clock hours of work (two cleanings of 2.5 h), under an hour of model time
        self.assertLess(t['until'] / 600, 60)
        # the mixed bed near exhaustion holds out until the cleaning is done (WATER-TREATMENT §7: the first hour)
        self.assertEqual(t['snapshots'][-1]['machines']['mb_a'], 'service')

    def test_mixed_bed_regenerated(self):
        """W3: mixed bed A regenerated by mb_regeneration from wtp_normal: B in service first, A's sequence through
        every state of [MB] p. 2–3, its exhaustion restored, the regenerants used, the wastes neutralised."""
        t = self.V2['wtp_regen']
        self.assertEqual((t['scenario'], t['procedure']), ('wtp_normal', 'mb_regeneration'))
        self.assertTrue(all(e[4] == 'done' for e in t['events'] if e[1] == 'op'))
        moves = [e[4] for e in t['events'] if e[1] == 'machine' and e[2] == 'mb_a']
        self.assertEqual(moves, ['standby', 'backwash', 'settle', 'drain', 'ready', 'inject', 'displace', 'drain2',
                                 'air_ready', 'air_mix', 'refill', 'rinse', 'standby'])
        e0 = P.Engine(self.b, 'wtp_normal')                  # step 0 (the snapshots start at 10 minutes)
        first = {n: e0.v(n) for n in ('mb_a_ex', 'gp_hcl_lvl', 'gp_naoh_lvl')}
        end = t['snapshots'][-1]['values']
        self.assertGreater(first['mb_a_ex'], 0.8)
        self.assertLess(end['mb_a_ex'], 0.05)
        self.assertLess(end['mb_a_cond'], 0.1)
        self.assertLess(end['mb_a_si'], 10)
        self.assertEqual(end['gp_air_cmd'], 0, 'the sequence stops the blower')
        for c in ('hcl', 'naoh'):
            self.assertAlmostEqual(first[f'gp_{c}_lvl'] - end[f'gp_{c}_lvl'], 14, delta=0.5)
        self.assertEqual(end['mb_b_making'], 1)
        # its timed states take about four clock hours with the operator's holds ([MB]: ~4 h)
        steps = dict(t['steps'])
        clock_h = (steps['air'] - steps['mb_a_off']) / 10 * 6 / 3600
        self.assertTrue(3 <= clock_h <= 4.5, clock_h)
        self.assertEqual(t['snapshots'][-1]['machines']['nr_batch'], 'discharging')

    def test_the_day_work_runs_in_the_model_alone(self):
        """The two W3 procedures from wtp_normal, as a trainee who does exactly what each step says."""
        for pid, last in (('ro_cip', 'pit'), ('mb_regeneration', 'pit')):
            with self.subTest(pid):
                e, log, _ = procedure_run(self.b, pid)
                self.assertEqual(log[-1][0], last)

    def test_a_step_with_operations_does_not_end_before_them(self):
        """The app ends a step as soon as its `done` is true: a step with operations whose `done` is already true when
        it begins would pass before the trainee made them (blind review of W3: the cleanings' steps)."""
        for pid in ('wtp_start', 'filter_backwash', 'ro_stop_flush', 'ro_cip', 'mb_regeneration'):
            pr = self.b.procedures[pid]
            _, _, bases = procedure_run(self.b, pid)
            for s in pr['steps']:
                ops = s.get('do', [])
                if not ops or 'done' not in s:
                    continue
                if not s.get('ordered'):
                    ops = ops[::-1]         # a trainee may make them in any order: the other one than the reference's
                e = bases[s['id']].clone()  # where the reference's trainee stood at the step's start
                with self.subTest(pid=pid, step=s['id']):
                    self.assertFalse(e.truth(s['done']), f'{s["done"]} already true')
                    # nor before the last of them: half a model minute between operations (adversarial review of W3:
                    # drain_alk ended with the tank's drain, its heater still on)
                    for d in ops[:-1]:
                        e.op(d['kks'], d['do'], d.get('value'), d.get('trip'))
                        for _ in range(300):
                            e.step()
                        self.assertFalse(e.truth(s['done']), f'{s["done"]} true before {ops[-1]["do"]}')

    def test_a_cleaning_stopped_early_does_not_end_its_step(self):
        """A cleaning stopped (or tripped) before its soak ends goes to its flush, but does not count as done: ro_cip's
        step waits for a whole cycle (adversarial review of W3: the procedure then stuck at `flow`)."""
        e = procedure_run(self.b, 'ro_cip')[2]['clean_alk'].clone()
        e.op('00GCB22AT001', 'clean')
        for _ in range(600):
            e.step()
        e.op('00GCB22AT001', 'stop_cleaning')
        n = 0
        while not e.truth('ro_b_stopped') or n < 10:
            e.step()
            n += 1
            self.assertLess(n, 36000)
        for _ in range(100):
            e.step()
        self.assertFalse(e.truth('ro_b_alk_cleaned'))

    def test_chlorine_exposure_fades_after_a_handled_trip(self):
        """The membranes' chlorine exposure is forgotten over about a clock hour: trips handled one by one do not add
        up to the damage (adversarial review of W3: the fourth handled trip damaged them)."""
        e = P.Engine(self.b, 'wtp_normal')
        e.fault('sbs_pump')
        n = 0
        while not e.truth('ro_a_trip_orp_latched'):
            e.step()
            n += 1
            self.assertLess(n, 6000)
        e.op('00GCN10AP002', 'start')
        for _ in range(100):
            e.step()
        x = e.v('ro_a_clx')
        self.assertGreater(x, 5)
        for _ in range(12000):
            e.step()
        self.assertLess(e.v('ro_a_clx'), x / 5)

    def test_mixed_bed_taken_out_waits_for_its_standby(self):
        """mb_regeneration's `mb_a_off` ends only when both its operations are made: the pump stopped alone does not
        end it (blind review of W3: else `regenerate` is refused at the next step)."""
        e = procedure_run(self.b, 'mb_regeneration')[2]['mb_a_off'].clone()
        e.op('00GCK10AP001', 'stop')
        for _ in range(600):
            e.step()
        self.assertEqual(e.v('mf_a_safe'), 1)
        self.assertFalse(e.truth('mb_a_taken'))
        e.op('00GCF11AT001', 'standby')
        e.step()
        self.assertTrue(e.truth('mb_a_taken'))

    def test_clarifier_a_upset_clears_when_it_is_taken_out(self):
        """Clarifier A's stalled rake spoils its own water, not B's; taken out of service, the filters' water clears
        (blind review of W3: the upset was on the clarifiers' shared turbidity)."""
        e = P.Engine(self.b, 'wtp_normal')
        e.fault('cl_upset')
        for _ in range(6000):
            e.step()
        self.assertGreater(e.v('cla_ntu'), 5)
        self.assertLess(e.v('clb_ntu'), 2)
        self.assertGreater(e.v('cl_ntu'), 3)
        e.op('00GBD11AT001', 'stop')
        for _ in range(12000):
            e.step()
        self.assertLess(e.v('cl_ntu'), 2)
        self.assertLess(e.v('cla_ntu'), 2, 'out of service, its water stands and settles')

    def test_high_ph_cleaning_trips_above_its_limit(self):
        """A high-pH solution trips the cleaning above 36.5 °C ([FT] table 35: 35 °C), not only at the skid's 40 °C
        (blind review of W3: the limit was checked only at the start)."""
        e = procedure_run(self.b, 'ro_cip')[2]['clean_alk'].clone()
        e.fault('cip_heater')
        e.op('00GCB22AT001', 'clean')
        n = 0
        while not e.truth('ro_b_trip_cip_t_latched'):
            e.step()
            n += 1
            self.assertLess(n, 36000, 'no trip')
        self.assertLess(e.v('cip_t'), 37.5)

    def test_cip_flush_draws_its_solution_from_the_tank(self):
        """The flush sends the tank's solution to the pit, so the drain sends only what is left: a cleaning never takes
        more chemical to the pit than the tank held (blind review of W3)."""
        e = procedure_run(self.b, 'ro_cip')[2]['drain_alk'].clone()
        self.assertLess(e.v('cip_lvl'), 30)

    def test_cip_fill_stops_at_an_empty_degassed_tank(self):
        """The CIP tank's fill stops when the degassed water tank reaches its low-low level (blind review of W3)."""
        cip = next(m for m in self.b.model.machines if m['id'] == 'cip')
        filling = next(s for s in cip['states'] if s['id'] == 'filling')
        self.assertIn(['dg_ll', 'water'], filling['next'])

    def test_neutralisation_batch_stops_its_agitator(self):
        """The batch starts the pit's agitator and stops it when it ends (blind review of W3: it ran on for ever)."""
        e = procedure_run(self.b, 'ro_cip')[0].clone()
        self.assertEqual(e.v('nr_mix_cmd'), 1)
        n = 0
        while e.mstate['nr_batch'] != 0:
            e.step()
            n += 1
            self.assertLess(n, 72000, 'the batch did not end')
        e.step()
        self.assertEqual(e.v('nr_mix_cmd'), 0)

    def test_wtp_normal_holds_the_days_work(self):
        """§7: the filter's backwash due at once, RO B waiting for its cleaning, mixed bed A's silica through in about
        an hour."""
        e = P.Engine(self.b, 'wtp_normal')
        e.step()
        self.assertTrue(e.truth('fl1_hl_h'))
        self.assertTrue(e.truth('ro_b_nflow_l0'))
        self.assertAlmostEqual(e.v('mb_a_cond'), 0.078222222, delta=1e-6, msg='its lags start where they stand')
        n = 0
        while not e.truth('mb_a_si_h') and n < 6000 * 10:
            e.step()
            n += 1
        self.assertTrue(55 <= n / 600 <= 80, n / 600)

    def test_flood(self):
        """§7 wtp_flood: at the dry season's dose the clarifiers carry over within the hour; raised to 80 mg/L they
        hold the clarified water under the alarm."""
        for dose, high in ((None, True), (80, False)):
            with self.subTest(dose=dose):
                e = P.Engine(self.b, 'wtp_flood')
                self.assertEqual(e.v('river_ntu'), 500)
                if dose:
                    e.op('00GBN10BB001', 'set', dose)
                for _ in range(6000):
                    e.step()
                alarms = {x[2] for x in e.events if x[1] == 'alarm'}
                self.assertEqual('cla_ntu_h' in alarms, high, alarms)

    def test_cip_and_regeneration_wastes_reach_the_pit(self):
        """The CIP tank's drain carries its chemical to the pit; the batch doses the other way to pH 6.5–8.5."""
        nodes = {n: node for n, node, _ in self.b.model.values}
        self.assertEqual(nodes['nr_alk_in']['sum'][:5], ['cip_dr_chem', 'ro_a_fl_chem', 'ro_b_fl_chem', 'mb_a_wc',
                                                          'mb_b_wc'])
        self.assertEqual(nodes['nr_ph_true']['table'][5], [0, 7.2], 'a neutral pit reads as before W3')

    def test_two_speeds(self):
        """§5: the WTP's inventories at clock rate (× day_scale), the plant's demin tank at the train's rate."""
        import wtp_model
        nodes = {n: node for n, node, _ in self.b.model.values}
        D = wtp_model.DAY
        self.assertAlmostEqual(nodes['dt_a_lvl']['gain'], D * 100 / (3600 * 1500))
        self.assertAlmostEqual(nodes['dm_lvl']['gain'], 100 / (3600 * 300))
        self.assertAlmostEqual(nodes['mb_a_ex']['gain'], D / 3600)
        # a mixed bed lasts about three clock days at design: 1/72 of its capacity per clock hour
        rate = 40 * 26.56 * 1 * 1 * nodes['mb_a_rate']['product'][-1]
        self.assertAlmostEqual(rate, 1 / 72, places=6)


class Validator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            cls.V = json.load(f)

    def test_valid(self):
        for v in self.V['valid']:
            b = P.check_files({k: t.encode() for k, t in v['files'].items()})
            self.assertEqual(b.counts, v['counts'])

    def test_each_reject_is_caught_with_its_code(self):
        base = {k: t.encode() for k, t in self.V['valid'][0]['files'].items()}
        codes = set()
        for r in self.V['reject']:
            files = dict(base)
            for k, t in r['change'].items():
                if t is None:
                    files.pop(k)
                else:
                    files[k] = t.encode()
            with self.assertRaises(P.FormatError, msg=r['why']) as cm:
                P.check_files(files)
            self.assertEqual(cm.exception.code, r['code'], f'{r["why"]}: {cm.exception}')
            codes.add(r['code'])
        for c in ('bad_json', 'unknown_key', 'missing_key', 'dup_id', 'bad_kks', 'bad_ref', 'forward_ref',
                  'bad_route', 'outside_area', 'not_walkable', 'bad_stair', 'bad_time', 'bad_table', 'bad_link',
                  'area_overlap', 'limit'):
            self.assertIn(c, codes)

    def test_a_format_1_model_file_keeps_format_1_error_codes(self):
        """Format 2 must not change what a format 1 model file is refused with (keys are checked before the version),
        and a model file that is no object is refused, not a crash."""
        base = {k: t.encode() for k, t in self.V['valid'][0]['files'].items()}
        name = next(k for k in base if k.startswith('model/'))
        d = json.loads(base[name])
        cases = [({k: v for k, v in d.items() if k != 'format'}, 'missing_key'),
                 (dict(d, extra=1, version=2), 'unknown_key'),
                 (dict(d, works=[]), 'unknown_key'),
                 ([], 'bad_type'), ('x', 'bad_type'),
                 (dict(d, values=d['values'] + [['zz', {'hold': d['values'][0][0], 'when': d['values'][0][0]}]]),
                  'bad_kind'),
                 (dict(d, values=d['values'] + [['zz', {'const': 1, 'hold': 'x'}]]), 'unknown_key')]
        files = dict(base, **{name: json.dumps(dict(d, version=1.0)).encode()})
        P.check_files(files)                    # 1.0 is version 1, as format 1 always took it
        for m, code in cases:
            files = dict(base, **{name: json.dumps(m).encode()})
            with self.assertRaises(P.FormatError, msg=repr(m)[:60]) as cm:
                P.check_files(files)
            self.assertEqual(cm.exception.code, code, repr(m)[:60])
        # a scenario fault's `when` with a hold key: format 1's unknown key beside its node kind
        sname = next(k for k in base if k.startswith('scenarios/'))
        sc = json.loads(base[sname])
        f0 = dict(sc['faults'][0], when={'cmp': [d['values'][0][0], '>', 1], 'hold': 'x'})
        files = dict(base, **{sname: json.dumps(dict(sc, faults=[f0] + sc['faults'][1:])).encode()})
        with self.assertRaises(P.FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'unknown_key', str(cm.exception))

    def test_a_sign_symbol_the_app_does_not_draw_is_refused(self):
        """A safety sign's `symbol` is one the app draws (ISO 7010 M003, apps/plant3d/builder/kit_place.gd
        SIGN_SYMBOLS): the app's own check is an assert, which a release build drops."""
        files = {k: t.encode() for k, t in self.V['valid'][0]['files'].items()}
        name = next(k for k in sorted(files) if k.startswith('areas/'))
        for symbol, ok in (('M003', True), ('W012', False)):
            a = json.loads(files[name])
            a['signs'] = a.get('signs', []) + [{'text': 'Hearing protection required', 'at': [0, 0, 1.8], 'yaw': 0,
                                                'size': 0.3, 'symbol': symbol}]
            changed = dict(files, **{name: json.dumps(a).encode()})
            if ok:
                P.check_files(changed)
            else:
                with self.assertRaises(P.FormatError) as cm:
                    P.check_files(changed)
                self.assertEqual(cm.exception.code, 'bad_value')
                self.assertIn('W012', str(cm.exception))

    def test_the_photo_passs_content_is_checked(self):
        """A medium's stencilled `name` (1 to 40 characters, no other new key), a `wall` (its height and thickness in
        range) and a building's `floor` finish and `crane` rail height (docs/PLANT3D.md §2, §5)."""
        files = {k: t.encode() for k, t in self.V['valid'][0]['files'].items()}
        # the vectors' kit is frozen: these parts as the kit has them now
        with open(os.path.join(ROOT, 'data', 'plant3d', 'kit.json'), encoding='utf-8') as f:
            now = json.load(f)['parts']
        kit = json.loads(files['kit.json'])
        for part in ('wall', 'building', 'floor', 'platform'):
            kit['parts'][part] = now[part]
        files['kit.json'] = json.dumps(kit).encode()
        area = next(k for k in sorted(files) if k.startswith('areas/'))

        def plant_with(**media_extra):
            pl = json.loads(files['plant.json'])
            m = next(iter(pl['media']))
            pl['media'][m].update(media_extra)
            return dict(files, **{'plant.json': json.dumps(pl).encode()})

        def area_with(*structures):
            a = json.loads(files[area])
            a['structures'] = a.get('structures', []) + list(structures)
            return dict(files, **{area: json.dumps(a).encode()})

        wall = {'id': 'fw', 'part': 'wall', 'at': [0, 0, 0], 'params': {'route': [[0, 0, 0], [5, 0, 0]], 'height': 8}}
        hall = {'id': 'h', 'part': 'building', 'at': [0, 0, 0], 'params': {'outline': [[0, 0], [10, 0], [10, 10], [0, 10]],
                                                                        'height': 12, 'floor': 'tile', 'crane': 8, 'openings': [{'kind': 'door', 'at': [5, 0, 0], 'width': 1, 'height': 2.1}]}}
        P.check_files(plant_with(name='Feedwater'))
        P.check_files(area_with(wall))
        P.check_files(area_with(hall))
        P.check_files(area_with(dict(hall, params=dict(hall['params'], outline=[[0, 0], [36, 0], [36, 19], [0, 19]],
                                                         height=20, crane=14.5))))
        for bad in (plant_with(name='x' * 41), plant_with(name=''), plant_with(label='Feedwater'),
                    area_with(dict(wall, params=dict(wall['params'], height=25))),
                    area_with(dict(hall, params=dict(hall['params'], floor='marble'))),
                    area_with(dict(hall, params=dict(hall['params'], crane=90))),
                    area_with(dict(hall, params=dict(hall['params'], crane=4))),
                    area_with(dict(hall, params=dict(hall['params'], crane=10))),
                    area_with(dict(hall, params=dict(hall['params'], cladding='concrete'))),
                    # the build's own refusals mirrored: a rail too high for the trusses of a 30 m span (test_builder's
                    # crane_clash case), and a rectangular hall turned off the plant's axes
                    area_with(dict(hall, params=dict(hall['params'], outline=[[0, 0], [36, 0], [36, 19], [0, 19]],
                                                     height=20, crane=16))),
                    area_with(dict(hall, yaw=30))):
            with self.assertRaises(P.FormatError):
                P.check_files(bad)

    def test_error_messages_name_the_file_and_item(self):
        r = next(x for x in self.V['reject'] if x['why'] == 'a bend that does not fit')
        files = {k: t.encode() for k, t in self.V['valid'][0]['files'].items()}
        files.update({k: t.encode() for k, t in r['change'].items()})
        with self.assertRaises(P.FormatError) as cm:
            P.check_files(files)
        msg = str(cm.exception)
        self.assertIn('areas/a1.json', msg)
        self.assertIn('10LAB10BR001', msg)
        self.assertIn('segment', msg)

    def test_the_first_trains_stairs_keep_the_step_rules(self):
        """Each stair of the first train, worked out here from §5's text (not with the validator's code): some number
        of steps keeps the rise, going and step rules."""
        b = P.check_dir(DATA)
        stairs = [s for s in b.structures.values() if s['part'] == 'stair']
        self.assertGreaterEqual(len(stairs), 5)
        for s in stairs:
            prm = s['params']
            foot, top = prm['foot'], prm['top']
            width = prm.get('width', 1.0)
            h = top[2] - foot[2]
            dx, dy = abs(top[0] - foot[0]), abs(top[1] - foot[1])
            f = math.ceil(round(h / 3.6, 9))
            fits = []
            for n in range(1, 400):
                rise = h / n
                if not 0.15 <= round(rise, 9) <= 0.20:
                    continue
                if prm.get('layout', 'straight') == 'straight':
                    going = (math.hypot(dx, dy) - (f - 1) * width) / (n - f)
                else:
                    self.assertGreaterEqual(min(dx, dy), 2 * width, s['id'])
                    going = (max(dx, dy) - 2 * width) / (math.ceil(n / f) - 1)
                if round(going, 9) >= 0.25 and 0.60 <= round(going + 2 * rise, 9) <= 0.66:
                    fits.append(n)
            self.assertTrue(fits, f'{s["id"]}: no step count keeps the rules')

    def test_name_clash_and_scenario_init_rejects_are_present(self):
        """Name clashes across areas (§7.1) and scenario init rules have reject vectors (each is checked above)."""
        whys = {r['why'] for r in self.V['reject']}
        for w in ('a value named like an earlier area\'s trip latch', 'a value named like an earlier area\'s machine '
                  'state', 'an ext value named like a trip latch', 'a scenario setting a latch to neither 0 nor 1',
                  'a scenario setting a timer', 'a scenario setting an integrate outside its range',
                  'a scenario setting a wrap outside [0, period)', 'an ext value named like a machine state',
                  'a trip the scenario latches twice', 'an alarm priority that is not 1, 2 or 3',
                  'a code of the model on no screen and not left out', 'one beginning of a code in two groups'):
            self.assertIn(w, whys)


class Engine(unittest.TestCase):
    """§7 worked out by hand on the synthetic unit models (the same models as the vectors' `steps`)."""

    @classmethod
    def setUpClass(cls):
        cls.runs = {}
        for why, model, init, faults, inputs, n in G.unit_models():
            F, b = G.unit_bundle(model, init, faults)
            e = P.Engine(b, 's1')
            states = [e.snapshot()]
            i = 0
            while e.step_no < n:
                while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                    G.apply(e, inputs[i])
                    i += 1
                e.step()
                states.append(e.snapshot())
            cls.runs[why[:5]] = (states, e.events)

    def test_first_out_with_a_trip_latched_at_the_start(self):
        """§7.5: a trip latching while another of its group is latched (here one the scenario started latched) is
        not first out; once both are reset, the next one is. A latched-at-start trip's actions are not applied."""
        states, ev = self.runs['first']
        self.assertEqual(states[0]['tripped'], ['ta'])
        self.assertEqual(states[0]['first_out'], {})
        self.assertEqual(states[0]['values']['x'], 0)
        self.assertIn([1, 'trip', 'tb', False], ev)
        self.assertEqual(states[1]['first_out'], {})
        self.assertIn([4, 'op', '10LAB10AA001', 'reset', 'done', []], ev)
        self.assertIn([5, 'op', '10LAC10AP001', 'reset', 'done', []], ev)
        self.assertIn([6, 'trip', 'tb', True], ev)
        self.assertEqual(states[6]['first_out'], {'g': 'tb'})
        # inputs naming an alarm or fault the model doesn't have, and shelving outside 0 < t < 10⁶ s, do nothing and
        # make no event; 0.25 s is 3 steps, rounded half up (§7.1), so the shelf ends in step 11
        self.assertEqual([e for e in ev if e[0] == 8], [[8, 'shelve', 'al', 0.25]])
        self.assertEqual(states[10]['shelved'], ['al'])
        # a shelf just under 10⁶ s is made (in step 1 of step 11, replacing the first before it ends in step 7)
        self.assertIn([11, 'shelve', 'al', 999999.9], ev)
        self.assertNotIn([11, 'unshelve', 'al'], ev)
        self.assertEqual(states[12]['shelved'], ['al'])

    def v(self, run, step, name):
        return self.runs[run][0][step]['values'][name]

    def test_nodes(self):
        r = 'every'
        # u set to 1 in step 1: stateless nodes see it at once, stateful ones from step 2 (§7.1)
        self.assertEqual(self.v(r, 1, 'tab'), 6)
        self.assertEqual(self.v(r, 1, 'lag'), 0)
        for n in range(2, 10):
            self.assertAlmostEqual(self.v(r, n, 'lag'), 1 - math.exp(-0.2 * (n - 1)), 12)
            self.assertAlmostEqual(self.v(r, n, 'ramp'), min(1, 0.2 * (n - 1)), 12)
            self.assertAlmostEqual(self.v(r, n, 'integ'), min(1, 0.3 * (n - 1)), 12)
            self.assertEqual(self.v(r, n, 'timer'), (n - 1) / 10)
        # u = −1 from step 10: lag falls with tau_down = 1 s, ramp at rate_down, integrate down at its gain
        y9 = self.v(r, 9, 'lag')
        self.assertAlmostEqual(self.v(r, 11, 'lag'), self.v(r, 10, 'lag') + (-1 - self.v(r, 10, 'lag')) *
                               (1 - math.exp(-0.1)), 12)
        self.assertAlmostEqual(self.v(r, 10, 'lag'), y9 + (1 - y9) * (1 - math.exp(-0.2)), 12)
        self.assertAlmostEqual(self.v(r, 11, 'ramp'), 0.9, 12)
        self.assertAlmostEqual(self.v(r, 11, 'integ'), 0.7, 12)
        self.assertAlmostEqual(self.v(r, 14, 'integ'), -0.2, 12)
        self.assertEqual(self.v(r, 11, 'timer'), 0)
        # latch: set from step 2; k = 1 in step 6 resets it in step 7 (reset wins); set again in step 9
        self.assertEqual([self.v(r, n, 'latch') for n in (1, 2, 6, 7, 8, 9)], [0, 1, 1, 0, 0, 1])
        # delay on 0.3 s: true at the third step that read true (step 4); off 0.2 s: false at the second false read
        self.assertEqual([self.v(r, n, 'delay') for n in (3, 4, 11, 12)], [0, 1, 1, 0])
        # wrap: 0 ≤ y < period also for negative input (−4.5 per second, period 1, from 0.25)
        self.assertAlmostEqual(self.v(r, 2, 'wrap'), 0.8, 12)
        self.assertAlmostEqual(self.v(r, 3, 'wrap'), 0.35, 12)
        # a table's jump is right-continuous; a step table takes the last point at or below; select clamps
        self.assertEqual(self.v(r, 14, 'tab'), 5)
        self.assertEqual([self.v(r, n, 'tstep') for n in (1, 10, 14)], [3, 1, 2])
        self.assertEqual([self.v(r, n, 'sel') for n in (1, 10, 14)], [1, 20, 0.5])
        self.assertEqual(self.v(r, 0, 'ext2'), 42)
        # an input outside the op's range is refused (u stays 0)
        self.assertEqual(self.v(r, 17, 'u'), 0)
        self.assertIn([17, 'op', '10LAC10AP001', 'set', 'refused', ['u']], self.runs[r][1])

    def test_step_order_rules(self):
        states, ev = self.runs['permi']
        # permissives read the previous step: refused in step 1 (b = 0)
        self.assertIn([1, 'op', '10LAC10AP001', 'start', 'refused', ['b_hi']], ev)
        # a machine moved by a command does not move again by `next` in the same step
        self.assertIn([2, 'machine', 'm', 'zero', 'one', 'command'], ev)
        self.assertEqual(states[2]['machines']['m'], 'one')
        # the first true `next` wins (two, not three)
        self.assertIn([3, 'machine', 'm', 'one', 'two', 'next'], ev)
        # trip delay 0.2 s: latched at the second step reading true; alarm delay likewise
        self.assertIn([4, 'trip', 'tb', True], ev)
        self.assertIn([4, 'alarm', 'al', 'active_unack'], ev)
        # a command in a state that does not take it is refused
        self.assertIn([5, 'op', '10LAB10AA001', 'go', 'refused', ['m_state']], ev)
        # a fault with a condition is applied once, reading the values of step 2
        self.assertEqual([e for e in ev if e[1] == 'fault'], [[5, 'fault', 'f'], [12, 'fault', 'g']])
        # interlock on a rising edge; its machine action holds the machine in step 5; a trip that is not first
        self.assertIn([6, 'interlock', 'il'], ev)
        self.assertIn([6, 'trip', 'tc', False], ev)
        self.assertEqual(states[6]['machines']['m'], 'two')
        self.assertIn([7, 'machine', 'm', 'two', 'three', 'next'], ev)
        # a reset is refused while the cause holds, done once it has cleared
        self.assertIn([9, 'op', '10LAB10CP501', 'reset', 'refused', ['b_hi']], ev)
        self.assertIn([14, 'op', '10LAB10CP501', 'reset', 'done', []], ev)
        # first-out stays while any trip of its group is latched, clears with the last reset
        self.assertEqual(states[16]['first_out'], {'g': 'tb'})
        self.assertEqual(states[17]['first_out'], {})
        # two trips in one step: the first listed is first out
        self.assertIn([19, 'trip', 'tb', True], ev)
        self.assertIn([19, 'trip', 'tc', False], ev)
        # a shelved alarm does not change state; its shelf ends by itself after 0.5 s
        self.assertNotIn([19, 'alarm', 'al2', 'active_unack'], ev)
        self.assertIn([23, 'unshelve', 'al2'], ev)
        # a suppressed alarm keeps its state (active_unack from step 19 while a = 2 in steps 26–29)
        self.assertEqual(states[28]['alarms']['al'], 'active_unack')
        # acknowledge, clear with the deadband value, re-activation after the delay
        self.assertEqual([e for e in ev if e[1] == 'alarm' and e[2] == 'al'][-3:],
                         [[30, 'alarm', 'al', 'normal'], [32, 'alarm', 'al', 'active_unack'],
                          [33, 'alarm', 'al', 'cleared_unack']])
        # fast-forward: not while a machine is in a watched state or an alarm is unacknowledged
        self.assertEqual([s['fast_forward'] for s in states[1:4]], [True, False, True])
        self.assertFalse(states[32]['fast_forward'])


class Vectors(unittest.TestCase):
    """The vector file is what the generator makes (this also re-runs the cold start and every fork), and replaying
    its inputs on a fresh engine gives its events and values: what the app's evaluator must do."""

    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            cls.text = f.read()
        cls.V = json.loads(cls.text)
        cls.built = json.loads(G.dump(G.build()))

    def test_file_is_frozen(self):
        self.assertEqual(json.loads(self.text), self.built, 'run python3 ref/make_plant3d_vectors.py --write')

    def test_unit_steps_replay(self):
        for s in self.V['steps']:
            F = G.mini()
            F['model/a1.json'] = s['model']
            F['scenarios/s1.json'] = s['scenario']
            del F['procedures/p1.json']
            del F['screens.json']
            e = P.Engine(G.check(F), 's1')
            got = [plain(e.snapshot())]
            i = 0
            inputs = s['inputs']
            while e.step_no < len(s['states']) - 1:
                while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                    G.apply(e, inputs[i])
                    i += 1
                e.step()
                got.append(plain(e.snapshot()))
            d = close(got, s['states'])
            self.assertIsNone(d, d)
            self.assertEqual(plain(e.events), s['events'])

    def test_links(self):
        """§6: what each link opens in the synthetic plant, and the cases the rules name."""
        b = P.check_files({k: t.encode() for k, t in self.V['valid'][0]['files'].items()})
        for x in self.V['links']:
            self.assertEqual(plain(P.read_link(x['link'], b)), x['expect'], x['link'])
        got = {x['link'].split('://', 1)[1]: x['expect'] for x in self.V['links']}
        self.assertEqual(got['kks/10LAC10AP001KP01']['match'], 'without_a3')
        self.assertEqual(got['kks/10LAC10AP001KP01']['code'], '10LAC10AP001')
        self.assertEqual(got['kks/10LAC10AP002'], {'open': 'kks', 'code': '10LAC10AP001', 'match': 'same_kind',
                                                   'decode': {'unit': 'Unit 1', 'system': 'Feedwater pumps',
                                                              'equipment': 'Pump'}})
        self.assertEqual(got['kks/10LAB10AP005']['match'], 'same_equipment')
        self.assertEqual(got['kks/20MAA10AP001']['decode'], {'unit': None, 'system': None, 'equipment': 'Pump'})
        self.assertEqual(got['kks/10MAA10AN001']['match'], 'decode')
        self.assertEqual(got['procedure/p1/start'], {'open': 'procedure', 'id': 'p1', 'step': 'start'})
        for k in ('kks/10lac10ap001', 'kks/10IAC10AP001', 'kks/10LAC10AP0019999999999999', 'kks/10LAC10AP001?x=1',
                  'procedure/p1/nope', 'course/ppt', 'example.org/'):
            self.assertEqual(got[k], {'open': 'start'}, k)

    def test_train_replay(self):
        """The cold start's inputs alone reproduce its events, every snapshot (to 1e-6), and each fork; so do the hot
        restart's."""
        b = P.check_dir(DATA)
        for name in ('train', 'hot'):
            with self.subTest(name):
                self._replay(b, self.V[name])

    def _replay(self, b, t):
        e = P.Engine(b, t['scenario'])
        bases = {}
        base_steps = sorted({f['base_step'] for f in t['forks']})
        snaps = iter(t['snapshots'])
        inputs = sorted(t['inputs'], key=lambda x: x[0])
        i = 0
        while e.step_no < t['until']:
            if e.step_no in base_steps:
                bases[e.step_no] = e.clone()
            while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                G.apply(e, inputs[i])
                i += 1
            e.step()
            if e.step_no % t['snapshot_every'] == 0 or e.step_no == t['until']:
                d = close(plain(e.snapshot()), next(snaps), f'step {e.step_no}')
                self.assertIsNone(d, d)
        if t['until'] in base_steps:
            bases[t['until']] = e.clone()
        self.assertEqual(plain(e.events), t['events'])
        for f in t['forks']:
            x = bases[f['base_step']].clone()
            n0 = len(x.events)
            G.replay(x, f['inputs'], f['until'])
            self.assertEqual(plain(x.events[n0:]), f['events'], f['id'])
            d = close(plain(x.snapshot(values=False)), f['end'], f['id'])
            self.assertIsNone(d, d)


def replay_asking(e, inputs, until, effects, tc):
    """Replays inputs to step `until`, asking each of `effects` ([step, work, point, answer]) when the run is at its
    step with the next step's inputs made (§15.6); returns them as asked, and checks that asking changes nothing."""
    inputs = sorted(inputs, key=lambda x: x[0])
    got, i = [], 0
    while e.step_no < until:
        while i < len(inputs) and inputs[i][0] == e.step_no + 1:
            G.apply(e, inputs[i])
            i += 1
        for q in effects:
            if q[0] == e.step_no:
                before = (plain(e.snapshot()), len(e.events), list(e.queue))
                got.append([q[0], q[1], q[2], e.lock_effects(q[1], q[2])])
                tc.assertEqual((plain(e.snapshot()), len(e.events), list(e.queue)), before, 'asking changed the run')
        e.step()
    return got


class Vectors2(unittest.TestCase):
    """Format 2 (PLANT3D §14–§15, §19; milestone P1: permits, isolations and the hold node): the file is what the
    generator makes; its valid plant passes with its counts, each reject is caught with its code; its unit runs and
    the first train's permit forks replay from their inputs; and format 1's vectors keep their synthetic parts."""

    @classmethod
    def setUpClass(cls):
        with open(G.OUT2, encoding='utf-8') as f:
            cls.text = f.read()
        cls.V = json.loads(cls.text)

    def test_file_is_what_the_generator_makes(self):
        self.assertEqual(json.loads(self.text), json.loads(G.dump(G.build2())),
                         'run python3 ref/make_plant3d_vectors.py --write')

    def test_valid(self):
        for v in self.V['valid']:
            b = P.check_files({k: t.encode() for k, t in v['files'].items()})
            self.assertEqual(b.counts, v['counts'])
            self.assertEqual((b.version, b.counts['isolations'], b.counts['works']), (2, 2, 2))

    def test_each_reject_is_caught_with_its_code(self):
        base = {k: t.encode() for k, t in self.V['valid'][0]['files'].items()}
        codes = set()
        for r in self.V['reject']:
            files = dict(base)
            for k, t in r['change'].items():
                if t is None:
                    files.pop(k)
                else:
                    files[k] = t.encode()
            with self.assertRaises(P.FormatError, msg=r['why']) as cm:
                P.check_files(files)
            self.assertEqual(cm.exception.code, r['code'], f'{r["why"]}: {cm.exception}')
            codes.add(r['code'])
        for c in ('bad_version', 'unknown_key', 'forward_ref', 'bad_ref', 'bad_value', 'dup_id', 'bad_id', 'limit',
                  'bad_length', 'bad_type', 'locked_write'):
            self.assertIn(c, codes)

    def test_unit_steps_replay(self):
        for s in self.V['steps']:
            F = G.mini2()
            F['model/a1.json'] = s['model']
            F['scenarios/s1.json'] = s['scenario']
            del F['procedures/p1.json']
            del F['screens.json']
            e = P.Engine(G.check(F), 's1')
            got = [plain(e.snapshot())]
            i = 0
            inputs = s['inputs']
            asked = []
            while e.step_no < len(s['states']) - 1:
                while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                    G.apply(e, inputs[i])
                    i += 1
                asked += [[q[0], q[1], q[2], e.lock_effects(q[1], q[2])] for q in s.get('effects', [])
                          if q[0] == e.step_no]
                e.step()
                got.append(plain(e.snapshot()))
            self.assertEqual(asked, s.get('effects', []))
            d = close(got, s['states'])
            self.assertIsNone(d, d)
            self.assertEqual(plain(e.events), s['events'])

    def test_every_permit_action_and_refusal_is_pinned(self):
        """§19: each permit transition and refusal, the automatic moves, locks and unlocks done and refused for each
        reason, unknown inputs, a refused op naming a lock, a skipped write and a suppressed alarm."""
        ev = [e for s in self.V['steps'] for e in s['events']]
        done = {e[3] for e in ev if e[1] == 'permit' and e[5] == 'done'}
        self.assertEqual(done, {'request', 'approve', 'issue', 'accept', 'done', 'return', 'close', 'cancel', 'auto'})
        autos = {e[6][0] for e in ev if e[1] == 'permit' and e[3] == 'auto'}
        self.assertEqual(autos, {2, 3, 8})
        reasons = {r for e in ev if e[1] in ('permit', 'lock', 'unlock') for r in e[6] if e[5] == 'refused'}
        for r in ('state', 'iso_busy', 'authority', 'locked', 'unlocked', 'pump_off'):
            self.assertIn(r, reasons)
        self.assertTrue(any(e[1] == 'lock' and e[5] == 'unknown' for e in ev))
        self.assertTrue(any(e[1] == 'permit' and e[5] == 'unknown' for e in ev))
        self.assertIn(['10LAC10AP001', 'start', 'refused', ['valve_open', 'iso_p_locked', 'iso_q_locked']],
                      [e[2:6] for e in ev if e[1] == 'op'])
        # a point locked and unlocked in one step; back to approved when a point is unlocked from an isolated permit
        life = self.V['steps'][0]
        self.assertIn([10, 'unlock', 'wo_p', 1, None, 'done', []], life['events'])
        self.assertIn([6, 'permit', 'wo_g', 'auto', None, 'done', [2]], self.V['steps'][2]['events'])

    def test_locked_writes_skipped_alarms_suppressed(self):
        life = self.V['steps'][0]
        st = life['states']
        # step 13: an interlock, a trip, a machine, an op on another code, a set op and a trainer fault all write the
        # locked pump's or valve's states: each skipped; the alarm at the locked pump suppressed, the tank's raised
        self.assertEqual(st[13]['values']['pump_cmd'], 0.0)
        self.assertEqual(st[13]['values']['valve_cmd'], 0.0)
        self.assertEqual(st[13]['values']['aux2'], 2.0)              # the interlock's write to an unlocked state
        self.assertEqual(st[13]['machines']['m'], 'run')              # the machine entered its state all the same
        self.assertIn('alt', st[13]['alarms'])
        self.assertNotIn('alp', st[13]['alarms'])
        # the trainee's repair under the accepted permit writes the locked pump's state (the work holds the isolation
        # locking the code); the work's done then finds it repaired (the done's own repair: steps[1], f3 at step 19)
        self.assertEqual(st[15]['values']['pump_fault'], 1.0)
        self.assertEqual(st[16]['values']['pump_fault'], 0.0)
        self.assertIn([16, 'repair', 'f1'], life['events'])
        self.assertNotIn([17, 'repair', 'f1'], life['events'])
        shared = self.V['steps'][1]['states']
        self.assertEqual(shared[5]['values']['motor_fault'], 1.0)     # the other isolation's lock: not repaired
        self.assertEqual(shared[5]['values']['aux2'], 7.0)
        self.assertEqual(shared[19]['values']['motor_fault'], 0.0)    # only its own isolation locks it: repaired
        self.assertIn([19, 'repair', 'f3'], self.V['steps'][1]['events'])

    def test_repairs_under_a_permit(self):
        """§15.5: the trainee's repair names a work whose permit is accepted; the trainer's repair needs none."""
        life, shared = self.V['steps'][0]['events'], self.V['steps'][1]['events']
        self.assertIn([12, 'repair', 'f1', 'wo_p', None, 'refused', ['state']], life)       # isolated, not accepted
        self.assertNotIn([12, 'repair', 'f1'], life)                                        # the trainer's: locked
        self.assertIn([16, 'repair', 'f1', 'wo_p', 'tech1', 'refused', ['authority']], life)
        for fid, w in (('f2', 'wo_p'), ('f1', 'wo_q'), ('f1', 'nope'), ('nofault', 'wo_n')):
            self.assertIn([16, 'repair', fid, w, None, 'unknown', []], life)
        self.assertIn([16, 'repair', 'f1'], life)              # made on the locked pump, as the work's
        self.assertEqual(self.V['steps'][0]['states'][16]['values']['pump_fault'], 0.0)
        self.assertEqual([e for e in life if e[1] == 'repair' and len(e) == 3], [[16, 'repair', 'f1']])  # done: none
        self.assertIn([2, 'repair', 'f1', 'wo_p', None, 'refused', ['state']], shared)
        self.assertIn([2, 'repair', 'f1'], shared)             # the trainer's, on a free code

    def test_repair_needs_the_isolation(self):
        """§15.5 (2026-10-24): a work without an isolation can't be repaired under its accepted permit (its done
        still repairs); before, it could (the gap the S1 review left)."""
        shared = self.V['steps'][1]['events']
        self.assertIn([15, 'repair', 'f4', 'wo_n', None, 'refused', ['isolation']], shared)
        self.assertIn([15, 'repair', 'f4'], shared)                    # by the work's done
        self.assertIn([2, 'repair', 'f1', 'wo_p', None, 'refused', ['state', 'isolation']], shared)

    def test_removal_while_issued_suspends_the_work(self):
        """§15.1, §15.3 (2026-10-24): a lock removed by authority while the permit is accepted suspends the work
        (back to approved); an unlock then is refused when no other lock stays; a repair noted in that step is not
        made; a removal names its owner."""
        run = next(r for r in self.V['steps'] if r['why'].startswith('a lock removed by authority'))
        ev = run['events']
        self.assertIn([4, 'unlock', 'wo_p', 0, None, 'refused', ['state']], ev)
        self.assertIn([5, 'remove_lock', 'wo_p', 1, None, 'done', [], None, 'Locker went home'], ev)
        self.assertIn([5, 'permit', 'wo_p', 'auto', None, 'done', [2]], ev)
        self.assertNotIn([5, 'repair', 'f1'], ev)
        self.assertIn([6, 'repair', 'f1', 'wo_p', None, 'refused', ['state', 'isolation']], ev)
        self.assertIn([7, 'repair', 'f1'], ev)
        self.assertIn([8, 'remove_lock', 'wo_p', 0, None, 'refused', ['unlocked'], 'tech1', 'Not here'], ev)
        self.assertIn([8, 'remove_lock', 'wo_p', 0, 'tech1', 'refused', ['authority'], None, 'Not mine'], ev)
        self.assertIn([9, 'remove_lock', 'wo_p', 0, None, 'done', [], None, 'Named'], ev)
        self.assertIn([9, 'permit', 'wo_p', 'auto', None, 'done', [2]], ev)

    def test_instructor_events(self):
        """§15.5 (2026-10-24): in a version 2 plant every trainer's fault and repair input makes an instructor
        event as it comes; format 1's vectors have none."""
        life = self.V['steps'][0]['events']
        self.assertEqual(life[0], [1, 'instructor', 'fault', 'f1'])
        self.assertIn([12, 'instructor', 'repair', 'f1'], life)     # asked on a locked code: made nothing, still seen
        self.assertNotIn([12, 'repair', 'f1'], life)
        v1 = json.load(open(os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v1.json'), encoding='utf-8'))
        self.assertFalse(any(x[1] == 'instructor' for r in v1['steps'] for x in r['events']))

    def test_lock_effects(self):
        """§15.6: what a lock would do, asked of the reference again where the vectors asked it."""
        chan = self.V['steps'][2]
        self.assertEqual([q[3] for q in chan['effects']],
                         [{'lock': 'refused', 'trips': [], 'alarms': []},
                          {'lock': 'done', 'trips': ['t'], 'alarms': ['a3']},
                          {'lock': 'done', 'trips': [], 'alarms': []}])
        F = G.mini2()
        F['model/a1.json'] = chan['model']
        F['scenarios/s1.json'] = chan['scenario']
        del F['procedures/p1.json']
        del F['screens.json']
        e = P.Engine(G.check(F), 's1')
        got = replay_asking(e, chan['inputs'], len(chan['states']) - 1, chan['effects'], self)
        self.assertEqual(got, chan['effects'])

    def test_hold_node(self):
        st = self.V['steps'][2]['states']
        v0 = st[0]['values']
        self.assertEqual((v0['h_init'], v0['h_sc'], v0['h_free'], v0['h_num']), (7.0, -2.0, 0.5, 3.0))
        self.assertEqual(st[3]['values']['h_init'], 3.0)              # held: w was 1 in the previous step
        self.assertEqual(st[4]['values']['h_init'], 3.5)
        self.assertEqual(st[5]['values']['g1h'], 3.5)                # the isolated channel holds
        self.assertEqual(st[5]['tripped'], ['t'])                     # and votes tripped: 1 out of 2 on the others
        self.assertNotIn('a1', st[12]['alarms'])
        self.assertIn('a1', st[16]['alarms'])                         # back in service: its reading and alarm

    def test_train_forks_replay(self):
        """The first train's permit forks: the cold start's inputs reproduce the base, each fork its events."""
        t = self.V['train']
        b = P.check_dir(DATA)
        e = P.Engine(b, t['scenario'])
        bases = {}
        base_steps = {f['base_step'] for f in t['forks']}
        G.replay(e, t['inputs'], t['until'])
        self.assertEqual(base_steps, {t['until']})
        bases[t['until']] = e
        for f in t['forks']:
            x = bases[f['base_step']].clone()
            n0 = len(x.events)
            self.assertEqual(replay_asking(x, f['inputs'], f['until'], f.get('effects', []), self),
                             f.get('effects', []), f['id'])
            self.assertEqual(plain(x.events[n0:]), f['events'], f['id'])
            d = close(plain(x.snapshot(values=False)), f['end'], f['id'])
            self.assertIsNone(d, d)

    def test_wtp_replays(self):
        """W2: the water treatment plant's start from cold, its snapshots and forks, from its inputs alone."""
        Vectors._replay(self, P.check_dir(DATA), self.V["wtp"])

    def test_format1_vectors_keep_their_synthetic_parts(self):
        """plant3d-v1.json's synthetic plant, rejects, unit runs and links are format 1's and stay what they were;
        its train runs only gained the first train's format 2 values (their events are unchanged)."""
        with open(G.OUT, encoding='utf-8') as f:
            V1 = json.load(f)
        self.assertEqual(json.loads(V1['valid'][0]['files']['plant.json'])['version'], 1)
        for s in V1['steps']:
            self.assertEqual(s['model']['version'], 1)
            self.assertNotIn('permits', s['states'][0])


class HotRestart(unittest.TestCase):
    """FIRST-TRAIN §4 "As built": the hot restart by its procedure reaches base load without an alarm or a trip, and
    on the way the roll is refused while the steam is more than 50 K colder than the hot casing."""

    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            cls.t = json.load(f)['hot']
        cls.b = P.check_dir(DATA)

    def test_reaches_base_load_cleanly(self):
        t = self.t
        self.assertEqual((t['scenario'], t['procedure']), ('hot_restart', 'hot_restart'))
        self.assertEqual(t['steps'][-1][0], 'at_load')
        self.assertEqual({e[1] for e in t['events']}, {'op', 'machine'})
        end = t['snapshots'][-1]
        self.assertEqual((end['alarms'], end['tripped']), ({}, []))
        self.assertEqual(end['machines']['st_start'], 'loaded')
        self.assertGreaterEqual(end['values']['gt1_mw'], 249)

    def test_the_casing_starts_hot_and_the_steam_cold(self):
        sc = self.b.scenarios['hot_restart']
        self.assertGreaterEqual(sc['init']['st_casing_t'], 450)
        steps = [s['id'] for s in self.b.procedures['hot_restart']['steps']]
        self.assertNotIn('casing_warm', steps)          # no auxiliary steam warm-up: the casing is hot
        self.assertLess(steps.index('match'), steps.index('st_roll'))
        fork = next(f for f in self.t['forks'] if f['id'] == 'hot_roll_steam_too_cold')
        self.assertLess(fork['seen']['st_mismatch']['end'], -50)    # the bound the refusal is about

    def test_the_hot_casing_cools_slowly(self):
        """Left alone (no steam on it) the casing cools with τ 30 h: at 520 °C at a trip it is still over 400 °C
        eight hours later (the usual line for a hot start), near 480 °C three hours after it, as the scenario has it;
        steam on it heats or cools it with τ 15 min."""
        k = next(v[1] for v in self.b.model.values if v[0] == 'st_cas_k')['cases']
        tau_alone, tau_steam = 1 / k[0], 1 / k[1]
        self.assertAlmostEqual(tau_alone / 3600, 30, delta=0.01)
        self.assertAlmostEqual(tau_steam / 60, 15, delta=0.01)
        self.assertGreater(35 + (520 - 35) * math.exp(-8 * 3600 / tau_alone), 400)
        at3 = 35 + (520 - 35) * math.exp(-3 * 3600 / tau_alone)
        self.assertAlmostEqual(self.b.scenarios['hot_restart']['init']['st_casing_t'], at3, delta=10)


class ColdStart(unittest.TestCase):
    """FIRST-TRAIN §4 run by its procedure in the model alone (0054 §10): every step's operation accepted, base load
    reached, no alarm and no trip on the way, in a plausible time."""

    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            cls.t = json.load(f)['train']
        cls.b = P.check_dir(DATA)

    def test_reaches_base_load_cleanly(self):
        t = self.t
        self.assertEqual(t['steps'][-1][0], 'at_load')
        self.assertEqual([s['id'] for s in self.b.procedures['cold_start']['steps']], [s for s, _ in t['steps']])
        kinds = {e[1] for e in t['events']}
        self.assertEqual(kinds, {'op', 'machine'}, 'only operations and sequence steps: no alarm, trip or interlock')
        self.assertTrue(all(e[4] == 'done' for e in t['events'] if e[1] == 'op'))
        end = t['snapshots'][-1]
        self.assertEqual(end['alarms'], {})
        self.assertEqual(end['tripped'], [])
        self.assertEqual(end['machines']['gt1_start'], 'loaded')
        self.assertEqual(end['machines']['st_start'], 'loaded')
        v = end['values']
        self.assertGreaterEqual(v['gt1_mw'], 249)
        self.assertGreaterEqual(v['st_mw'], 120)
        self.assertLess(v['cond_p'], 11)                    # ~10 kPa(a) at full load on a hot day, two CW pumps less
        self.assertLess(v['hp_byp_pos'], 0.05)
        self.assertAlmostEqual(v['hp_p'], 120, delta=2)     # HP 120 bar(a) at base load (FIRST-TRAIN §2)

    def test_time_is_plausible(self):
        """About 4 h of a real cold start compressed: between 1 and 2.5 h of model time; with fast-forward wherever
        §7.9 allows it, under 30 min of the trainee's time (walking comes on top: about 40 min of play)."""
        minutes = self.t['until'] / 600
        self.assertGreater(minutes, 60)
        self.assertLess(minutes, 150)
        e = P.Engine(self.b, 'cold_iron')
        inputs = sorted(self.t['inputs'], key=lambda x: x[0])
        i, watched, fast = 0, 0, 0
        while e.step_no < self.t['until']:
            while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                G.apply(e, inputs[i])
                i += 1
            ff = e.fast_forward()
            e.step()
            if ff:
                fast += 1
            else:
                watched += 1
        play_min = (watched * 0.1 + fast * 0.1 / 60) / 60
        self.assertLess(play_min, 30)
        self.assertGreater(watched, 0)


class Forks(unittest.TestCase):
    """Each fork of the vectors against its expectation (written from FIRST-TRAIN §4–§5 in the generator), and
    together they make every trip and interlock of the model fire."""

    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            V = json.load(f)
        cls.forks = V['train']['forks'] + V['hot']['forks']
        with open(G.OUT2, encoding='utf-8') as f:
            V2 = json.load(f)
        cls.forks += V2['train']['forks'] + V2['wtp']['forks'] + V2['wtp_cip']['forks'] + V2['wtp_regen']['forks']
        cls.b = P.check_dir(DATA)

    def test_expectations(self):
        for f in self.forks:
            ex, ev, end = f['expect'], f['events'], f['end']
            with self.subTest(f['id']):
                for kks, do, failed in ex.get('refused', []):
                    self.assertIn([kks, do, 'refused', failed], [e[2:6] for e in ev if e[1] == 'op'])
                for kks, do in ex.get('done', []):
                    self.assertIn([kks, do, 'done', []], [e[2:6] for e in ev if e[1] == 'op'])
                for work, point, why in ex.get('lock_refused', []):
                    self.assertIn([work, point, None, 'refused', why], [e[2:7] for e in ev if e[1] == 'lock'])
                if 'permits' in ex:
                    self.assertEqual(end['permits'], ex['permits'])
                for fid in ex.get('repaired', []):
                    self.assertIn(['repair', fid], [e[1:3] for e in ev if e[1] == 'repair'])
                for fid, w, why in ex.get('repair_refused', []):
                    self.assertIn([fid, w, None, 'refused', why], [e[2:7] for e in ev if e[1] == 'repair'])
                if 'repairs' in ex:
                    self.assertEqual(len([e for e in ev if e[1] == 'repair' and len(e) == 3]), ex['repairs'])
                if 'effects' in ex:
                    self.assertEqual([[q[1], q[2], q[3]['lock'], q[3]['trips'], q[3]['alarms']] for q in f['effects']],
                                     ex['effects'])
                if 'faults' in ex:                # every fault applied, in order (a repaired one pressed again)
                    self.assertEqual(ex['faults'], [e[2] for e in ev if e[1] == 'fault'])
                for g, t in ex.get('first_out', {}).items():
                    self.assertIn(['trip', t, True], [e[1:4] for e in ev if e[1] == 'trip'])
                    self.assertEqual(end['first_out'].get(g), t)
                for t in ex.get('tripped', []):
                    self.assertIn(t, end['tripped'])
                for m, s in ex.get('machines', {}).items():
                    seen = [e[4] for e in ev if e[1] == 'machine' and e[2] == m]
                    self.assertIn(s, seen + [end['machines'][m]])
                for a in ex.get('alarms', []):
                    self.assertIn(['alarm', a, 'active_unack'], [e[1:4] for e in ev if e[1] == 'alarm'])
                for il in ex.get('interlocks', []):
                    self.assertIn(['interlock', il], [e[1:3] for e in ev if e[1] == 'interlock'])
                for a in ex.get('no_alarms', []):
                    self.assertNotIn(a, [e[2] for e in ev if e[1] == 'alarm'])
                for il in ex.get('no_interlocks', []):
                    self.assertNotIn(['interlock', il], [e[1:3] for e in ev if e[1] == 'interlock'])
                if ex.get('no_trip'):
                    self.assertEqual([e for e in ev if e[1] == 'trip'], [])
                for kind in ('max', 'end'):       # a value's highest over the fork, or its value at the end
                    for n, (lo, hi) in ex.get(kind, {}).items():
                        got = f['seen'][n][kind]
                        self.assertTrue(lo - 1e-9 <= got <= hi + 1e-9, f'{n} {kind} {got} not in [{lo}, {hi}]')

    def test_every_trip_and_interlock_is_exercised(self):
        """Each one, siblings included (every fan, every pump)."""
        fired_t = {e[2] for f in self.forks for e in f['events'] if e[1] == 'trip'}
        fired_i = {e[2] for f in self.forks for e in f['events'] if e[1] == 'interlock'}
        m = self.b.model
        self.assertEqual({t['id'] for t in m.trips} - fired_t, set())
        self.assertEqual({x['id'] for x in m.interlocks} - fired_i, set())


class Bake(unittest.TestCase):
    """The lightmap bake (apps/plant3d/builder/bake/bake_plugin.gd) runs only in the editor on a GPU, so not here; its
    order is checked from the source. The lightmap's .import file must be written after the editor's scan of the new
    folder: written before it, it stands without its image while the editor scans, and the scan crashed the editor
    (signal 11) on every fresh checkout (second realism pass, 2026-10-17)."""

    def test_import_settings_are_written_after_the_editors_scan(self):
        with open(os.path.join(ROOT, 'apps', 'plant3d', 'builder', 'bake', 'bake_plugin.gd'), encoding='utf-8') as f:
            src = f.read()
        body = src[src.index('func _bake()'):]
        write = body.index('.exr.import"')
        scan = body.index('fs.scan()')
        wait = body.index('while fs.is_scanning()', scan)
        bake = body.index('button.pressed.emit()')
        self.assertLess(scan, write, 'the .import file is written before the editor scans the lightmap folder')
        self.assertLess(wait, write, 'the .import file is written while the editor may still be scanning')
        self.assertLess(write, bake, 'the import settings come before the bake writes its image')


if __name__ == '__main__':
    unittest.main()
