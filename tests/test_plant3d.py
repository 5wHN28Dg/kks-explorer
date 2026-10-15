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
        self.assertEqual(c['areas'], 9)
        self.assertGreaterEqual(c['equipment'], 150)
        self.assertGreaterEqual(c['pipes'], 25)
        self.assertGreaterEqual(c['tours'], 1)
        self.assertEqual(c['procedures'], 1)
        self.assertLessEqual(c['values'], P.MAX['values'])

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
        self.assertEqual(len(rows), 33)
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
                  'cw_a_trip_valve', 'cep_trip_hw', 'ct_fan1_trip_vib'):
            self.assertIn(t, trips)
        ops = self.m.op_keys
        needs = lambda kks, do: [n[0] for n in ops[(kks, do, None)].get('needs', [])]
        self.assertIn('st_tg_run', needs('30MAW10AA001', 'open'))           # #10 gland steam needs the turning gear
        self.assertIn('byp_permit', needs('30MAN10AA001', 'auto'))          # #16 bypass blocked without the condenser
        self.assertEqual(needs('10BAC10', 'close_breaker')[2:], ['gt1_ph_ok', 'gt1_slip_ok', 'gt1_v_ok'])   # #14
        self.assertIn('cw_a_vstart', needs('30PAC10AP001', 'start'))        # #4 start position
        self.assertIn('st_jack_ok', needs('30MAK10AE001', 'start'))         # #7 order of the oil systems
        self.assertIn('st_ecc_ok', needs('30MAA10', 'roll'))                # #7, #18
        self.assertIn('st_sh_ok', needs('30MAA10', 'roll'))                 # #18 superheat ≥ 50 K

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

    def test_new_rejects_fail_on_the_old_rules(self):
        """Name clashes across areas (§7.1) and scenario init rules: the reject vectors of these exist."""
        whys = {r['why'] for r in self.V['reject']}
        for w in ('a value named like an earlier area\'s trip latch', 'a value named like an earlier area\'s machine '
                  'state', 'an ext value named like a trip latch', 'a scenario setting a latch to neither 0 nor 1',
                  'a scenario setting a timer'):
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
        # inputs naming an alarm or fault the model doesn't have do nothing and make no event
        self.assertEqual([e for e in ev if e[0] == 8], [])

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
        """The cold start's inputs alone reproduce its events, every snapshot (to 1e-6), and each fork."""
        t = self.V['train']
        b = P.check_dir(DATA)
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
            cls.forks = json.load(f)['train']['forks']
        cls.b = P.check_dir(DATA)

    def test_expectations(self):
        for f in self.forks:
            ex, ev, end = f['expect'], f['events'], f['end']
            with self.subTest(f['id']):
                for kks, do, failed in ex.get('refused', []):
                    self.assertIn([kks, do, 'refused', failed], [e[2:6] for e in ev if e[1] == 'op'])
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
                if ex.get('no_trip'):
                    self.assertEqual([e for e in ev if e[1] == 'trip'], [])

    def test_every_trip_and_interlock_is_exercised(self):
        """Each one, siblings included (every fan, every pump)."""
        fired_t = {e[2] for f in self.forks for e in f['events'] if e[1] == 'trip'}
        fired_i = {e[2] for f in self.forks for e in f['events'] if e[1] == 'interlock'}
        m = self.b.model
        self.assertEqual({t['id'] for t in m.trips} - fired_t, set())
        self.assertEqual({x['id'] for x in m.interlocks} - fired_i, set())


if __name__ == '__main__':
    unittest.main()
