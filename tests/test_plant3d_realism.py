"""Walkdown Plant's realism base (docs/plant3d/REALISM.md §2.1, §2.7–§2.9, milestone RE1) on the reference:
- ref/vectors/plant3d-realism.json is what ref/make_plant3d_vectors.py makes, part by part;
- the streams: FNV-1a against its published values, a stream per purpose and item that no other item moves;
- the synthetic plant with clock values passes with its counts, each reject is caught with its code, its runs replay
  (every event, the snapshots, the state digests);
- the clock values: their values across midnight and in a jump's own step, and a person's draws unchanged by a world;
- a scenario without `world` keeps every slot and value as before (format 2's vectors stay byte for byte: their own
  tests, test_plant3d.Vectors2 and test_plant3d_staff, compare them with the generator's output)."""
import copy, json, math, os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from ref import plant3d as P                     # noqa: E402
from ref import plant3d_world as W               # noqa: E402
from ref import make_plant3d_vectors as G        # noqa: E402


def files_of(st, r=None):
    F = {k: t.encode() for k, t in st['files'].items()}
    if r is not None:
        F['scenarios/s1.json'] = json.dumps(r['scenario']).encode()
        for rel, v in r.get('files', {}).items():
            F[rel] = json.dumps(v).encode()
    return F


def replay(st, r, scenario=None, digests=None):
    """A run of the file on the reference: (engine, snapshots at the run's `every`)."""
    if scenario is not None:
        r = dict(r, scenario=scenario)
    e = P.Engine(P.check_files(files_of(st, r)), 's1')
    states = [e.snapshot()]
    if digests is not None:
        digests.append(e.digest())
    inputs = sorted(r['inputs'], key=lambda x: x[0])
    j = 0
    while e.step_no < r['until']:
        while j < len(inputs) and inputs[j][0] == e.step_no + 1:
            G.apply_staff(e, inputs[j])
            j += 1
        e.step()
        if e.step_no % r['every'] == 0 or e.step_no == r['until']:
            states.append(e.snapshot())
        if digests is not None and e.step_no % G.DIGEST_EVERY == 0:
            digests.append(e.digest())
    return e, states


def plain(x):
    return json.loads(G.dump(x))


class RealismVectors(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(G.OUT3, encoding='utf-8') as f:
            cls.text = f.read()
        cls.V = json.loads(cls.text)
        cls.st = cls.V['staff']

    def test_file_is_what_the_generator_makes(self):
        self.assertEqual(list(self.V), list(G.parts3()), 'run python3 ref/make_plant3d_vectors.py --only-realism '
                                                         '--write')
        for k, f in G.parts3().items():
            self.assertEqual(json.loads(G.dump(f())), self.V[k], f'{k}: run python3 ref/make_plant3d_vectors.py '
                                                                 '--only-realism --write')
        self.assertEqual(G.dump(G.build3()), self.text)

    def test_fnv1a_published_values(self):
        """The FNV-1a 32-bit test values of its authors (draft-eastlake-fnv), and UTF-8 bytes, not code points."""
        for s, h in (('', 0x811c9dc5), ('a', 0xe40c292c), ('foobar', 0xbf9cf968)):
            self.assertEqual(W.fnv1a(s), h, s)
        self.assertEqual(W.fnv1a('ä'), W.mul32(W.mul32(0x811c9dc5 ^ 0xc3, 16777619) ^ 0xa4, 16777619))

    def test_streams(self):
        for x in self.V['streams']:
            s = W.stream(x['seed'], W.TAGS[x['tag']], x['item'])
            self.assertEqual(s, x['state'])
            for r in x['draws']:
                s, got = W.draw(s)
                self.assertEqual(got, r)
        # a stream belongs to its purpose and its item alone: the same item under another purpose, or another
        # item, starts elsewhere; the same three always start at the same state
        states = {(x['seed'], x['tag'], x['item']): x['state'] for x in self.V['streams']}
        self.assertEqual(len(set(states.values())), len(states))
        self.assertEqual(states[(7, 'draw', 'f1')], W.stream(7, W.TAGS['draw'], 'f1'))
        self.assertNotEqual(states[(7, 'draw', 'f1')], states[(7, 'causes', 'f1')])
        self.assertEqual(len(set(W.TAGS.values())), len(W.TAGS))
        # a person's stream (§17.5) is not any world stream's: the tags are not mul32(i + 1, 0x9e3779b9)
        persons = {W.mul32(i + 1, 0x9e3779b9) for i in range(4096)}
        self.assertFalse(persons & set(W.TAGS.values()))

    def test_valid_counts(self):
        b = P.check_files(files_of(self.st))
        self.assertEqual(b.counts, self.st['counts'])

    def test_each_reject_is_caught_with_its_code(self):
        base = files_of(self.st)
        for r in self.st['reject']:
            F = dict(base)
            for k, t in r['change'].items():
                if t is None:
                    F.pop(k)
                else:
                    F[k] = t.encode()
            with self.assertRaises(P.FormatError, msg=r['why']) as cm:
                P.check_files(F)
            self.assertEqual(cm.exception.code, r['code'], f'{r["why"]}: {cm.exception}')
            self.assertIn('world', str(cm.exception), f'{r["why"]}: caught by another rule? {cm.exception}')

    def test_runs_replay(self):
        for r in self.st['runs']:
            digests = []
            e, states = replay(self.st, r, digests=digests)
            self.assertEqual(plain(e.events), r['events'], r['why'][:60])
            self.assertEqual(plain(states), r['states'], r['why'][:60])
            self.assertEqual(digests, r['digests'], f'{r["why"][:60]}: the state digests (§17.14)')

    def test_clock_values_across_midnight(self):
        """world_hour and world_day at every step from 23:00 (day_scale 60: a clock minute is 10 steps), the new day
        at step 600 exactly; the nodes reading them as any node reads a machine's state."""
        r = self.st['runs'][0]
        e = P.Engine(P.check_files(files_of(self.st, r)), 's1')
        for n in range(0, 700):
            if n:
                e.step()
            c = (1 * 1440 + 23 * 60) * 600 + n * 60
            self.assertEqual(e.clock(), c)
            self.assertEqual((e.v('world_hour'), e.v('world_day')), ((c % 864000) / 36000, float(c // 864000)), n)
            self.assertEqual(e.v('night'), 1.0 if e.v('world_hour') >= 18 else 0.0)
            self.assertEqual(e.v('day_n'), e.v('world_day') + 0.5)
        self.assertEqual(e.names[-2:], ['world_hour', 'world_day'])

    def test_clock_values_in_a_jumps_own_step(self):
        """Step 1w comes after step 1's inputs: the jump's step already reads the new clock; a hold reads the step
        before's (a stateful node's input is the previous step's)."""
        r = self.st['runs'][1]
        e = P.Engine(P.check_files(files_of(self.st, r)), 's1')
        jump = next(x for x in r['inputs'] if x[1] == 'jump')
        while e.step_no < jump[0] - 1:
            e.step()
        G.apply_staff(e, jump)
        e.step()
        self.assertEqual([x for x in e.events if x[1] == 'jump'], [[jump[0], 'jump', 1693800, 1935000, 'done']])
        self.assertEqual((e.v('world_hour'), e.v('world_day')), (5.75, 2.0))
        self.assertEqual(e.prev[e.ix['world_day']], 1.0)

    def test_people_draws_unchanged_by_a_world(self):
        """The staff's morning with a world (the vectors' run 2) and without one: the same events and snapshots but
        the clock values (§2.1: the people's streams are seeded as before)."""
        r = self.st['runs'][2]
        sc = copy.deepcopy(r['scenario'])
        del sc['world']
        e0, s0 = replay(self.st, r, sc)
        self.assertEqual(plain(e0.events), r['events'])
        for a, b in zip(plain(s0), r['states']):
            vb = dict(b['values'])
            self.assertEqual((vb.pop('world_hour'), vb.pop('world_day')),
                             tuple(plain(list(W.clock_values(b['clock'])))))
            self.assertEqual(dict(a, values=a['values']), dict(b, values=vb))
        self.assertTrue(any(x[1] == 'task' for x in r['events']))

    def test_no_world_no_slots(self):
        """A version 2 scenario without `world` has no clock values: the slots and digests are format 2's."""
        F = files_of(self.st, self.st['runs'][2])
        sc = json.loads(F['scenarios/s1.json'])
        del sc['world']
        F['scenarios/s1.json'] = json.dumps(sc).encode()
        e = P.Engine(P.check_files(F), 's1')
        self.assertNotIn('world_hour', e.names)
        self.assertIsNone(e.world)

    def test_world_seed(self):
        """The world's seed: its own, else the staff's, else 1 (§2.1)."""
        self.assertEqual(W.world_seed({'world': {'seed': 9}, 'staff': {'seed': 4}}), 9)
        self.assertEqual(W.world_seed({'world': {}, 'staff': {'seed': 4}}), 4)
        self.assertEqual(W.world_seed({'world': {}}), 1)
        es = [P.Engine(P.check_files(files_of(self.st, r)), 's1') for r in self.st['runs']]
        self.assertEqual([e.world['seed'] for e in es], [7, 7, 1, 1])
        self.assertEqual([e.world['year_day'] for e in es], [200, 200, 1, 365])

    def test_rejects_cover_every_rule(self):
        whys = {r['why'] for r in self.st['reject']}
        for w in ('a world seed of 2^32', 'a year day of 366', 'a world in a version 1 scenario',
                  'a value named like a clock value', 'a model reading the clock values with a scenario without a world',
                  'a world in a plant without a clock', 'a reaction of the staff reading a clock value with a scenario '
                  'without a world'):
            self.assertIn(w, whys)


def run_on(st, r, upto=None, each=None):
    """Replays run r of a part on the reference up to step `upto` (its end by default), calling each(e) after every
    step (step 0 too); returns the engine."""
    e = P.Engine(P.check_files(files_of(st, r)), 's1')
    inputs = sorted(r['inputs'], key=lambda x: x[0])
    j = 0
    if each:
        each(e)
    while e.step_no < (upto if upto is not None else r['until']):
        while j < len(inputs) and inputs[j][0] == e.step_no + 1:
            G.apply_staff(e, inputs[j])
            j += 1
        e.step()
        if each:
            each(e)
    return e


class PartVectors:
    """A part of the realism file laid out as `staff` (files, counts, rejects with their codes, runs)."""
    part, rejects = None, None

    @classmethod
    def setUpClass(cls):
        with open(G.OUT3, encoding='utf-8') as f:
            cls.st = json.load(f)[cls.part]

    def test_valid_counts(self):
        self.assertEqual(P.check_files(files_of(self.st)).counts, self.st['counts'])

    def test_each_reject_is_caught_by_its_rule(self):
        base = files_of(self.st)
        rules = {r[0]: r[3] for r in getattr(G, self.rejects)}
        self.assertEqual(sorted(rules), sorted(r['why'] for r in self.st['reject']))
        for r in self.st['reject']:
            F = dict(base)
            for k, t in r['change'].items():
                if t is None:
                    F.pop(k)
                else:
                    F[k] = t.encode()
            with self.assertRaises(P.FormatError, msg=r['why']) as cm:
                P.check_files(F)
            self.assertEqual(cm.exception.code, r['code'], f'{r["why"]}: {cm.exception}')
            self.assertIn(rules[r['why']], str(cm.exception), f'{r["why"]}: caught by another rule? {cm.exception}')

    def test_runs_replay(self):
        for r in self.st['runs']:
            digests = []
            e, states = replay(self.st, r, digests=digests)
            self.assertEqual(plain(e.events), r['events'], r['why'][:60])
            self.assertEqual(plain(states), r['states'], r['why'][:60])
            self.assertEqual(digests, r['digests'], f'{r["why"][:60]}: the state digests (§17.14)')


class WearVectors(PartVectors, unittest.TestCase):
    """Milestone AG1 (REALISM.md §2.2, §4.2–§4.3, J0): the draw, wear and count nodes, works' renews and age_rate."""
    part, rejects = 'wear', 'REJECTS_WEAR'

    def test_wear_step_by_step(self):
        """Every step of run 0: brg_wear = 0 when brg_new read true, else min(1, y + max(0, rate) × k), k = 0.1 × 60,
        all as the previous step left them; clock_s the same with rate 1, run_h with its own rate."""
        r = self.st['runs'][0]
        last = {}
        k = 0.1 * 60

        def each(e):
            ix, cur = e.ix, e.cur
            if last:
                p = last
                want = 0.0 if p['brg_new'] >= 0.5 else min(1.0, p['brg_wear'] + max(0.0, p['brg_rate']) * k)
                self.assertEqual(cur[ix['brg_wear']], want, e.step_no)
                self.assertEqual(cur[ix['clock_s']], min(900000000.0, p['clock_s'] + 1.0 * k), e.step_no)
                self.assertEqual(cur[ix['run_h']], min(100000.0, p['run_h'] + max(0.0, p['run_rate']) * k))
            for n in ('brg_new', 'brg_wear', 'brg_rate', 'clock_s', 'run_h', 'run_rate'):
                last[n] = cur[ix[n]]
        e = run_on(self.st, r, each=each)
        self.assertEqual(e.v('clock_s'), 2600 * k)
        self.assertEqual([x for x in e.events if x[1] == 'fault'], [[598, 'fault', 'f_brg'], [1800, 'fault', 'f_new']])

    def test_draws(self):
        """A draw takes table(u), u = r / 2^24 of its own stream's first draw (the world's seed, purpose draw, its
        name); its own init or the scenario's keeps that value; another draw added before it in the file changes
        nothing (streams by id, §2.1)."""
        r = self.st['runs'][0]
        e = P.Engine(P.check_files(files_of(self.st, r)), 's1')
        _, u = W.draw(W.stream(7, W.TAGS['draw'], 'brg_life'))
        self.assertEqual(e.v('brg_life'), 0.3 + (0.9 - 0.3) * (u / 2 ** 24))
        _, u = W.draw(W.stream(7, W.TAGS['draw'], 'brg_life_c'))
        self.assertEqual(e.v('brg_life_c'), 0.1 + (0.2 - 0.1) * (u / 2 ** 24))
        self.assertEqual(e.v('brg_life_b'), 0.42)
        self.assertEqual(run_on(self.st, self.st['runs'][1], 0).v('brg_life_c'), 0.15)
        F = files_of(self.st, r)
        m = json.loads(F['model/a1.json'])
        m['values'].insert(0, ['a_first', {'draw': [[0, 5], [1, 6]]}])
        F['model/a1.json'] = json.dumps(m).encode()
        e2 = P.Engine(P.check_files(F), 's1')
        self.assertEqual(e2.v('brg_life'), e.v('brg_life'))
        self.assertTrue(5 <= e2.v('a_first') <= 6)
        # another seed, another life; the draw happens at step 0 only
        F = files_of(self.st, dict(r, scenario=dict(r['scenario'], world=dict(r['scenario']['world'], seed=8))))
        e3 = P.Engine(P.check_files(F), 's1')
        self.assertNotEqual(e3.v('brg_life'), e.v('brg_life'))
        e3.step(50)
        self.assertEqual(e3.v('brg_life'), e3.prev[e3.ix['brg_life']])

    def test_counts(self):
        """pump_starts counts the pump's command turning on (not the step 0 state), pump_trips adds 8 when the bearing
        reads bad and is reset by brg_new; a count starting true at step 0 doesn't count (run 4: the pump running)."""
        seen = []
        e = run_on(self.st, self.st['runs'][0], each=lambda e: seen.append(
            (e.step_no, e.v('pump_starts'), e.v('pump_trips'))))
        steps_up = [s for (s, a, _), (_, b, _) in zip(seen, seen[1:]) if b != a]
        self.assertEqual(steps_up, [2, 1900])      # the start ops' steps: the count reads them a step later
        trips = sorted({t for _, _, t in seen})
        self.assertEqual(trips, [0.0, 8.0])
        self.assertEqual(e.v('pump_starts'), 2.0)
        self.assertEqual(run_on(self.st, self.st['runs'][4]).v('pump_starts'), 0.0)
        self.assertEqual(run_on(self.st, self.st['runs'][1]).v('pump_starts'), 4.0)    # from the scenario's 3

    def test_renewal_and_its_isolation(self):
        """The work's done renews the bearing in step 3 (read 0 in that step's snapshot); with a lock removed by
        authority in done's own step, nothing is renewed."""
        a = run_on(self.st, self.st['runs'][2], 650)
        b = run_on(self.st, self.st['runs'][3], 650)
        self.assertEqual(a.v('brg_wear'), 0.0)
        self.assertGreater(b.v('brg_wear'), 0.3)
        self.assertEqual(a.prev[a.ix['brg_wear']], b.prev[b.ix['brg_wear']])

    def test_wear_across_a_jump(self):
        """In the jump's step, y + rate × (gap / 10) first, then + rate × k, then the max: clock_s by the gap's
        seconds and the step's; the bearing at its max (1) and failing at once."""
        r = self.st['runs'][4]
        jump = next(x for x in r['inputs'] if x[1] == 'jump')
        e = run_on(self.st, r, jump[0] - 1)
        before = e.v('clock_s')
        G.apply_staff(e, jump)
        e.step()
        ev = [x for x in e.events if x[1] == 'jump'][0]
        gap = ev[3] - ev[2]
        self.assertEqual(e.v('clock_s'), before + 1.0 * (gap / 10.0) + 1.0 * (0.1 * 60))
        self.assertEqual(e.v('brg_wear'), 1.0)
        self.assertIn([jump[0], 'fault', 'f_brg'], e.events)

    def test_age_rate(self):
        """age_rate scales the wear (§4.3): the training rate 50 against the real rate 1, both from the same duty."""
        a = run_on(self.st, self.st['runs'][0], 300)
        b = run_on(self.st, self.st['runs'][1], 300)
        self.assertAlmostEqual(a.v('brg_wear') / 50, (b.v('brg_wear') - 0.25) / 1, places=12)

    def test_v1_nodes_keep_format_1s_codes(self):
        """In a version 1 model file the new kinds are refused as format 1 refused them: alone no node kind
        (bad_kind), beside another kind that kind's unknown key."""
        whys = {r['why']: r['code'] for r in self.st['reject']}
        self.assertEqual(whys['a draw node in a version 1 model file'], 'bad_kind')
        self.assertEqual(whys['a wear node (with its max) in a version 1 model file'], 'unknown_key')
        self.assertEqual(whys['a count node in a version 1 model file'], 'bad_kind')


class WeatherVectors(PartVectors, unittest.TestCase):
    """Milestone WX1 (REALISM.md §5.1): weather.json and the weather step, seeded, fixed and scripted, the
    instructor's input and a jump."""
    part, rejects = 'weather', 'REJECTS_WEATHER'

    def wx(self, r=None):
        F = files_of(self.st, r)
        return json.loads(F['weather.json'])

    def chain(self, seed, year_day, kind, hours):
        """The kinds the seeded weather takes at the given whole hours (clock hours from day 0), computed here from
        weather.json and the stream alone."""
        d = self.wx()
        kinds = [k['id'] for k in d['kinds']]
        s = W.stream(seed, W.TAGS['weather'], 'weather')
        out = []
        for h in hours:
            s, r = W.draw(s)
            doy = (year_day - 1 + h // 24 - 1) % 365 + 1
            season = next(x for x in d['seasons'] if doy in W.season_days(x['days']))
            rows = [x for x in season['hourly'] if x[0] == kind]
            total = sum(x[2] for x in rows)
            pick, acc = (r * total) >> 24, 0
            for x in rows:
                acc += x[2]
                if acc > pick:
                    kind = x[1]
                    break
            out.append(kind)
        assert kinds
        return out

    def test_seeded_chain(self):
        """Run 0: a draw at each whole hour from 06:00 (day 1), the kind from the current kind's row; the events are
        the changes of that chain."""
        r = self.st['runs'][0]
        ks = self.chain(7, 200, 'hot', [24 + h for h in range(6, 12)])
        want, k = [], 'hot'
        for i, x in enumerate(ks):
            if x != k:
                want.append([300 + 600 * i, 'weather', k, x])
            k = x
        self.assertEqual([x for x in r['events'] if x[1] == 'weather'], want)

    def test_season_at_midnight(self):
        """Run 1: the draws at 23:00 use summer's rows, at 00:00 and 01:00 winter's (year day 300, then 301)."""
        r = self.st['runs'][1]
        ks = self.chain(11, 300, 'hot', [24 + 23, 48, 49])
        got = [x for x in r['events'] if x[1] == 'weather']
        k, want = 'hot', []
        for i, x in enumerate(ks):
            if x != k:
                want.append([300 + 600 * i, 'weather', k, x])
            k = x
        self.assertEqual(got, want)
        self.assertIn('rain', ks)       # winter's alone

    def test_lags_step_by_step(self):
        """Every step of run 0: each driven value moves toward its kind's table at world_hour by 1 − e^(−6 / (60 tau));
        world_wx the kind; a stateless node reads this step's value, a lag the step before's."""
        r = self.st['runs'][0]
        d = self.wx()
        kinds = [k['id'] for k in d['kinds']]
        f = {v['id']: 1 - math.exp(-0.1 * 60 / (60 * v['tau'])) for v in d['values']}
        last = {}

        def each(e):
            if last:
                k = d['kinds'][int(e.v('world_wx'))]
                for v in f:
                    t = P.table_at([[float(x), float(y)] for x, y in k['targets'][v]], e.v('world_hour'))
                    self.assertEqual(e.v(v), last[v] + (t - last[v]) * f[v], (e.step_no, v))
                self.assertEqual(e.v('amb_hot'), 1.0 if e.v('ambient_t') >= 33 else 0.0)
                self.assertEqual(e.v('wx_wet'), 1.0 if e.v('world_wx') >= 3 else 0.0)
            for v in f:
                last[v] = e.v(v)
        e = run_on(self.st, r, 1300, each)
        self.assertEqual(kinds[int(e.v('world_wx'))], e.wx['kinds'][e.wx_kind])
        self.assertEqual(e.names[-3:], ['world_hour', 'world_day', 'world_wx'])

    def test_instructor(self):
        r2, r3 = self.st['runs'][2], self.st['runs'][3]
        self.assertEqual([x for x in r2['events'] if x[1] in ('weather', 'instructor')],
                         [[200, 'instructor', 'weather', 'dust'], [200, 'weather', 'clear', 'dust'],
                          [400, 'instructor', 'weather', 'rain'], [400, 'weather', 'dust', 'rain']])
        self.assertEqual([x for x in r3['events'] if x[1] in ('weather', 'instructor')],
                         [[300, 'weather', 'clear', 'rain'], [400, 'instructor', 'weather', 'dust'],
                          [400, 'weather', 'rain', 'dust'], [500, 'weather', 'dust', 'clear'],
                          [700, 'weather', 'clear', 'dust']])
        # outside a scenario with weather the input does nothing and makes no event
        with open(G.OUT3, encoding='utf-8') as f:
            wear = json.load(f)['wear']
        e = run_on(wear, wear['runs'][0], 0)
        self.assertIsNone(e.wx)
        e.weather('dust')
        e.step()
        self.assertEqual([x for x in e.events if x[1] in ('weather', 'instructor')], [])

    def test_jump(self):
        """Run 4: in the jump's step one draw per whole hour crossed, in order (the stream advanced that many times),
        the driven values at their targets, one event for the net change."""
        r = self.st['runs'][4]
        jump = next(x for x in r['inputs'] if x[1] == 'jump')
        e = run_on(self.st, r, jump[0] - 1)
        s0, k0 = e.wx_s, e.wx_kind
        G.apply_staff(e, jump)
        e.step()
        ev = [x for x in e.events if x[1] == 'jump'][0]
        c0, c1 = ev[2] - 60, ev[3]          # the clock of the step before, and of the jump's step
        hours = range(c0 // 36000 + 1, c1 // 36000 + 1)
        s = s0
        for _ in hours:
            s, _r = W.draw(s)
        self.assertEqual(e.wx_s, s)
        self.assertEqual(len(hours), 6)      # 00:00 to 05:00
        d = self.wx()
        k = d['kinds'][e.wx_kind]
        for v in ('ambient_t', 'dust_mg'):
            self.assertEqual(e.v(v), P.table_at([[float(x), float(y)] for x, y in k['targets'][v]], e.v('world_hour')))
        self.assertEqual(len([x for x in e.events if x[1] == 'weather']), 1 if e.wx_kind != k0 else 0)

    def test_digest_has_the_weather(self):
        e = run_on(self.st, self.st['runs'][0], 10)
        d0 = e.digest()
        c = e.clone()
        c.wx_s ^= 1
        self.assertNotEqual(c.digest(), d0)
        c = e.clone()
        c.wx_kind = (c.wx_kind + 1) % 4
        self.assertNotEqual(c.digest(), d0)
        self.assertEqual(e.clone().digest(), d0)

    def test_people_draws_unchanged_by_weather(self):
        """Run 5 (the staff's morning with seeded weather) replayed without weather (and without the nodes reading
        it): the same events but the weather's, the people where they were."""
        r = self.st['runs'][5]
        F = files_of(self.st, r)
        sc = json.loads(F['scenarios/s1.json'])
        del sc['world']['weather']
        m = json.loads(F['model/a1.json'])
        m['values'] = [v for v in m['values'] if v[0] not in [n[0] for n in G.WEATHER_NODES]]
        F['scenarios/s1.json'] = json.dumps(sc).encode()
        F['model/a1.json'] = json.dumps(m).encode()
        e = P.Engine(P.check_files(F), 's1')
        inputs = sorted(r['inputs'], key=lambda x: x[0])
        j = 0
        while e.step_no < r['until']:
            while j < len(inputs) and inputs[j][0] == e.step_no + 1:
                G.apply_staff(e, inputs[j])
                j += 1
            e.step()
        self.assertEqual(plain(e.events), [x for x in r['events'] if x[1] != 'weather'])
        self.assertEqual(plain(e.snapshot())['people'], r['states'][-1]['people'])


class SyntheticLoad(unittest.TestCase):
    """tools/plant3d/realism_synth.py (§11's measurement before any realism content): its loads of 600 and 1,000
    values pass the validator on the first train, are made the same every time, keep §11's split, and step."""

    def test_loads(self):
        import glob
        sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'tools', 'plant3d'))
        import realism_synth as RS
        b = P.check_dir(os.path.join(os.path.dirname(HERE), 'data', 'plant3d'))
        for n in (600, 1000):
            vals = RS.make(n, b)
            self.assertEqual(vals, RS.make(n, b))
            self.assertEqual(len(vals), n)
            self.assertEqual(sum(1 for v in vals if v[0].startswith('rw')), 250 if n >= 600 else n * 5 // 12)
            self.assertEqual(sum(1 for v in vals if v[0].startswith(('rc', 'rm'))), 200)
            files = {}
            root = os.path.join(os.path.dirname(HERE), 'data', 'plant3d')
            for f in glob.glob(os.path.join(root, '**', '*.json'), recursive=True):
                with open(f, encoding='utf-8') as fh:
                    files[os.path.relpath(f, root)] = json.load(fh)
            RS.apply(files, vals)
            b2 = P.check_files({k: json.dumps(v).encode() for k, v in files.items()})
            self.assertEqual(b2.counts['values'], b.counts['values'] + n)
            e = P.Engine(b2, 'cold_iron')
            e.step(20)
            self.assertEqual(e.names[-2:], ['world_hour', 'world_day'])
            self.assertTrue(all(map(lambda x: x == x, e.cur)))

    def test_engine_load(self):
        """--engine (AG1, WX1): the wear items are wear, draw and count nodes, and the load brings weather.json with
        ten driven values (the train's ambient_t and ambient_wb and eight of its own), every scenario seeded by it;
        it passes the validator and steps with the weather on."""
        import glob
        sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'tools', 'plant3d'))
        import realism_synth as RS
        root = os.path.join(os.path.dirname(HERE), 'data', 'plant3d')
        b = P.check_dir(root)
        vals = RS.make(600, b, engine=True)
        self.assertEqual(len(vals), 600)
        kinds = [P.node_kind(v[1], v[0]) for v in vals]
        for k in ('wear', 'draw', 'count'):
            self.assertIn(k, kinds)
        self.assertEqual(sum(1 for v in vals if v[0].startswith('rw')), 250)
        files = {}
        for f in glob.glob(os.path.join(root, '**', '*.json'), recursive=True):
            with open(f, encoding='utf-8') as fh:
                files[os.path.relpath(f, root)] = json.load(fh)
        RS.apply(files, vals, RS.weather_doc(), RS.WX_EXT)
        b2 = P.check_files({k: json.dumps(v).encode() for k, v in files.items()})
        e = P.Engine(b2, 'cold_iron')
        self.assertEqual(len(e.wx['values']), 10)
        self.assertEqual(e.names[-3:], ['world_hour', 'world_day', 'world_wx'])
        e.step(20)
        self.assertTrue(all(map(lambda x: x == x, e.cur)))


if __name__ == '__main__':
    unittest.main()
