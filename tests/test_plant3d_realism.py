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
            if v is None:
                F.pop(rel, None)        # (a file the run leaves out)
            else:
                F[rel] = json.dumps(v).encode()
    return F


def replay(st, r, scenario=None, digests=None):
    """A run of the file on the reference: (engine, snapshots at the run's `every`)."""
    if scenario is not None:
        r = dict(r, scenario=scenario)
    e = P.Engine(P.check_files(files_of(st, r)), 's1', r.get('session', False))    # (a session run: HS7's)
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
    e = P.Engine(P.check_files(files_of(st, r)), 's1', r.get('session', False))
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

    def test_jump_reads_the_rate_before(self):
        """Run 5: the pump stopped in the jump's own step: run_h adds the previous step's running rate × (gap / 10)
        and × k though this step's rate is 0; the step after adds nothing."""
        r = self.st['runs'][5]
        e = run_on(self.st, r, 29)
        before, rate = e.v('run_h'), e.v('run_rate')
        self.assertGreater(rate, 0)
        e = run_on(self.st, r, 30)
        ev = [x for x in e.events if x[1] == 'jump'][0]
        self.assertIn([30, 'op', '10LAC10AP001', 'stop', 'done', [], 'local', 'c_fo'], plain(e.events))
        self.assertEqual(e.v('run_rate'), 0.0)
        self.assertEqual(e.v('run_h'), before + rate * ((ev[3] - ev[2]) / 10.0) + rate * (0.1 * 60))
        e.step()
        self.assertEqual(e.v('run_h'), e.prev[e.ix['run_h']])

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


class FreePlaySeeds(unittest.TestCase):
    """Every shipped scenario with seeded weather draws a weather sequence of its own (the user, 2026-11-03: a world
    seed per scenario, REALISM.md §5.6): the world seeds (W.world_seed: its own, else the staff's, else 1, §2.1) all differ, and
    so do the weather streams' first day of draws."""

    def test_distinct_seeds(self):
        d = os.path.join(os.path.dirname(HERE), 'data', 'plant3d', 'scenarios')
        seeds = {}
        for f in sorted(os.listdir(d)):
            sc = json.load(open(os.path.join(d, f)))
            world = sc.get('world', {})
            if 'season' not in world.get('weather', {}):
                continue
            seeds[sc['id']] = W.world_seed(sc)
        self.assertGreaterEqual(set(seeds), {'cold_iron', 'hot_restart', 'wtp_cold', 'wtp_normal', 'wtp_flood',
                                             'shift_cold', 'shift_wtp'})
        self.assertEqual(len(set(seeds.values())), len(seeds), seeds)
        draws = {}
        for sid, seed in seeds.items():
            s, out = W.stream(seed, W.TAGS['weather'], 'weather'), []
            for _ in range(24):
                s, r = W.draw(s)
                out.append(r)
            draws[sid] = tuple(out)
        self.assertEqual(len(set(draws.values())), len(draws))


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

    def test_the_instructors_weather_in_a_session_and_a_save(self):
        """The app's input checks take the weather input (REALISM.md §2.12): a save with one queued loads (its size
        and a text kind), a session carries it, and only the host or an instructor seat may make it (as a fault)."""
        app = os.path.join(os.path.dirname(HERE), 'apps', 'plant3d')
        save = open(os.path.join(app, 'ui', 'autosave.gd'), encoding='utf-8').read()
        self.assertIn('"weather": [2]', save)
        self.assertIn('q[0] in ["fault", "repair", "weather"] and typeof(q[1]) != TYPE_STRING', save)
        chk = open(os.path.join(app, 'net', 'input_check.gd'), encoding='utf-8').read()
        self.assertIn('"weather": [["s"]]', chk)
        body = chk[chk.index('static func trainer_only'):chk.index('static func allowed')]
        self.assertIn('"fault", "weather":', body)

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


class HandsVectors(PartVectors, unittest.TestCase):
    """Milestone HW1 (REALISM.md §2.3–§2.7, settled in §2.13): tools carried, hand actions, meters and HART ops,
    hidden causes and cures, the NPCs' slips; each with its reasons in order."""
    part, rejects = 'hands', 'REJECTS_HANDS'

    def evs(self, k, kinds=('tool', 'hand', 'read', 'cause', 'slip', 'repair', 'early'), steps=None):
        return [x for x in self.st['runs'][k]['events'] if x[1] in kinds and (steps is None or x[0] in steps)]

    def test_tool_reasons(self):
        """Taken only at a place that keeps it, by the input's own person; refused carried, full, none_left,
        not_carried, where (put back where it isn't kept); the counts per place in the snapshot's digest."""
        ev = self.evs(0, ('tool',))
        self.assertEqual(ev[:5], [[1, 'tool', 'sd_flat', 1, 'ic1', 'refused', ['where']],
                                  [1, 'tool', 'sd_flat', 1, 'ic2', 'refused', ['authority', 'where']],
                                  [1, 'tool', 'nope', 1, 'ic1', 'unknown', []],
                                  [1, 'tool', 'sd_flat', 2, 'ic1', 'unknown', []],
                                  [1, 'tool', 'sd_flat', 1, None, 'refused', ['authority', 'where']]])
        why = {(x[0], x[2], x[3]): x[6] for x in ev if x[5] == 'refused'}
        self.assertEqual(why[(3, 'spanner_17', 0)], ['not_carried'])
        self.assertEqual(why[(3, 'loopcal', 1)], ['where'])
        self.assertEqual(why[(7, 'loopcal', 1)], ['full'])
        self.assertEqual(why[(7, 'spanner_13', 0)], ['where'])
        self.assertIn([308, 'tool', 'hart', 1, 'ic2', 'refused', ['none_left']], ev)
        e = run_on(self.st, self.st['runs'][0], 10)
        self.assertEqual(len(e.carried['ic1']), 12)
        self.assertEqual(e.tool_n[e.tools['ix']['spanner_17']], [0, 2])     # one taken at tb1, one back at store1
        self.assertEqual(e.tool_n[e.tools['ix']['loopcal']], [0])

    def test_hand_reasons_in_order(self):
        """authority, where, busy, tool, wrong_tool, the needs, value; a hand action on the locked code is made."""
        ev = self.evs(1, ('hand',), steps=(3, 5, 12, 21))
        self.assertEqual([(x[3], x[4], x[6], x[7]) for x in ev], [
            ('connect_hart', 'hart', 'refused', ['where']),       # at the toolbox, away from the gauge (§2.15)
            ('open_cover', 'sd_flat', 'refused', ['authority']), ('connect_hart', 'hart', 'done', []),
            ('no_such', 'sd_flat', 'unknown', []), ('pull_test', None, 'refused', ['authority', 'where']),
            ('open_cover', 'spanner_13', 'refused', ['wrong_tool']), ('open_cover', None, 'refused', ['tool']),
            ('open_cover', 'dmm', 'refused', ['tool']), ('lift_wire', 'sd_flat', 'refused', ['g1_body_open']),
            ('torque_gland', 'spanner_17', 'refused', ['value']), ('torque_gland', 'spanner_17', 'refused', ['value']),
            ('pull_test', 'sd_flat', 'refused', ['wrong_tool']), ('pull_test', None, 'refused', ['busy']),
            ('tighten', 'spanner_13', 'refused', ['busy', 'wrong_tool'])])
        # (the adversarial review) the tool of an action under way can't be put back: one tool, one job at a time
        self.assertIn([21, 'tool', 'sd_flat', 0, 'ic1', 'refused', ['where', 'busy']], self.st['runs'][1]['events'])
        self.assertIn([8, 'lock', 'wo_gauge', 0, 'ic1', 'done', []], self.st['runs'][1]['events'])

    def test_timed_hand(self):
        """Started at 20, two clock minutes (20 steps at day_scale 60), its set written in step 40's step 3; one
        abandoned when the trainee left the place; an input written at once."""
        seen = {}

        def each(e):
            seen[e.step_no] = (e.v('g1_body_open'), e.v('g1_body_torque'), list(e.busy))
        run_on(self.st, self.st['runs'][1], 50, each)
        self.assertEqual(seen[39][0], 0.0)
        self.assertEqual(seen[40][0], 1.0)
        self.assertEqual(seen[39][2], ['ic1'])
        self.assertEqual(seen[40][2], [])
        self.assertEqual(seen[45][1], 7.5)
        ev = self.evs(1, ('hand',))
        self.assertIn([15, 'hand', '10LAB10CP501', 'open_cover', 'sd_flat', 'ic1', 'abandoned', []], ev)
        # (§2.15) the HART op on the locked code is made under the trainee's own accepted permit
        self.assertIn([50, 'op', '10LAB10CP501', 'set', 'done', [], 'hart', 'ic1'], self.st['runs'][1]['events'])

    def test_hart_under_own_permit(self):
        """REALISM.md §2.15: a HART op on a locked code is made only under the work's own accepted permit (and
        written); refused with no permit, an issued one not yet accepted, another work's accepted permit, by another
        person, and after the work's done."""
        r = next(x for x in self.st['runs'] if x['why'].startswith('a HART op on the locked gauge'))
        ops = [(x[0], x[4], x[6]) for x in r['events'] if x[1] == 'op' and x[2] == '10LAB10CP501']
        L = ['iso_gauge_locked']
        self.assertEqual(ops, [(7, 'done', 'hart'), (12, 'refused', 'hart'), (15, 'refused', 'hart'),
                               (21, 'refused', 'hart'), (24, 'done', 'hart'), (24, 'refused', 'hart'),
                               (24, 'refused', 'local'), (28, 'refused', 'hart')])
        why = [x[5] for x in r['events'] if x[1] == 'op' and x[2] == '10LAB10CP501' and x[4] == 'refused']
        self.assertEqual(why, [L, L, L, ['authority', 'hart'] + L, ['where'] + L, L])
        seen = {}
        run_on(self.st, r, 30, lambda e: seen.__setitem__(e.step_no, e.v('g1_cfg_urv')))
        self.assertEqual((seen[7], seen[23], seen[24], seen[30]), (20.0, 20.0, 24.0, 24.0))

    def test_hart_permit_acceptor_rule(self):
        """REALISM.md §2.15: under the work's permit means by its acceptor, or another with accept and its discipline
        while the acceptor is off duty: the HART run at step 23 with ic2 (on duty) named the acceptor refuses ic1's
        HART op on the locked code; with ic2 absent it is made."""
        r = next(x for x in self.st['runs'] if x['why'].startswith('a HART op on the locked gauge'))
        e = run_on(self.st, r, 23)
        self.assertEqual(e.acceptor['wo_gauge'], 'ic1')
        e.acceptor['wo_gauge'] = 'ic2'
        G.apply_staff(e, [24, 'op', '10LAB10CP501', 'set', 24, None, 'hart', 'ic1'])
        e.step()
        self.assertIn([24, 'op', '10LAB10CP501', 'set', 'refused', ['iso_gauge_locked'], 'hart', 'ic1'], e.events)
        self.assertEqual(e.v('g1_cfg_urv'), 20.0)
        e.staff.absent.add('ic2')
        G.apply_staff(e, [25, 'op', '10LAB10CP501', 'set', 25, None, 'hart', 'ic1'])
        e.step()
        self.assertEqual(e.v('g1_cfg_urv'), 25.0)

    def test_hart_permit_without_hw1_keys(self):
        """REALISM.md §2.15: the permit is found in a run with none of HW1's keys too (the app's engine once built
        its works per code only with them): under the accepted permit the locks are not named."""
        r = next(x for x in self.st['runs'] if x['why'].startswith('a HART op without HW1'))
        e = run_on(self.st, r, 1)
        self.assertFalse(e.hw)
        ops = [x[5] for x in r['events'] if x[1] == 'op' and x[2] == '10LAB10CP501']
        self.assertEqual(ops, [['hart', 'iso_gauge_locked'], ['hart']])

    def test_npc_hand_step_walks_there(self):
        """REALISM.md §2.15: an NPC whose job left the gauge walks back to its work place for its hand step."""
        r = next(x for x in self.st['runs'] if x['why'].startswith('an NPC\'s hand step away'))
        ev = [x for x in r['events'] if 'ic2' in x and x[1] in ('move', 'hand')]
        k = next(i for i, x in enumerate(ev) if x[1] == 'hand')
        self.assertEqual(ev[k - 1][1:5:3], ['move', 'w_gauge'])        # (arrived there last)
        self.assertIn(['move', 'ic2', 'p5', 'tb1'], [x[1:5] for x in ev[:k]])      # (and had gone back first)
        self.assertEqual(ev[k][3:8], ['open_cover', 'sd_flat', 'ic2', 'start', []])

    def test_hand_away_from_the_equipment(self):
        """REALISM.md §2.15: a hand action is made only at its code's work place (where); an NPC's hand step walks
        there first; a hand step on a code without a work place is refused by the validator."""
        ev = self.st['runs'][1]['events']
        self.assertIn([3, 'hand', '10LAB10CP501', 'connect_hart', 'hart', 'ic1', 'refused', ['where']], ev)
        self.assertIn([5, 'hand', '10LAB10CP501', 'pull_test', None, 'ic2', 'refused', ['authority', 'where']], ev)
        self.assertTrue(any(x['why'].startswith('a hand step on a code without a work place')
                            for x in self.st['reject']))

    def test_meters_and_hart(self):
        """A read through a meter: tool without it (the step waits), misread against its else, 0 round both wires,
        the communicator's PV; a HART op refused hart, where, its range, authority; done with it connected."""
        ev = [x for x in self.st['runs'][2]['events'] if x[1] in ('read', 'op') and x[0] >= 10 and x[2] in
              ('ic1', '10LAB10CP501')]
        self.assertEqual([x[1:] for x in ev], [
            ['read', 'ic1', '10LAB10CP501', 8.8, 'tool'], ['read', 'ic1', '10LAB10CP501', 8.8, 'misread'],
            ['read', 'ic1', '10LAB10CP501', 0, 'ok'],
            ['op', '10LAB10CP501', 'set', 'refused', ['hart'], 'hart', 'ic1'],
            ['op', '10LAB10CP501', 'set', 'refused', ['where'], 'local', 'ic1'],
            ['op', '10LAB10CP501', 'set', 'refused', ['g1_cfg_urv'], 'hart', 'ic1'],
            ['op', '10LAB10CP501', 'set', 'done', [], 'hart', 'ic1'],
            ['op', '10LAB10CP501', 'set', 'refused', ['authority', 'hart'], 'hart', 'ic2'],
            ['read', 'ic1', '10LAB10CP501', 3, 'ok'], ['read', 'ic1', '10LAB10CP501', -1, 'tool'],
            ['op', '10LAB10CP501', 'set', 'refused', ['iso_gauge_locked'], 'hart', 'ic1']])
        self.assertEqual(run_on(self.st, self.st['runs'][2]).v('g1_cfg_urv'), 25.0)

    def test_jump_abandons(self):
        ev = self.evs(3, ('hand', 'jump'))
        self.assertEqual([x[1:] for x in ev[:3]], [
            ['hand', '10LAB10CP501', 'clean_glass', None, 'ic1', 'start', []],
            ['jump', 1134480, 1962000, 'done'],
            ['hand', '10LAB10CP501', 'clean_glass', None, 'ic1', 'abandoned', []]])

    def test_npc_job_and_slips(self):
        """ic2's job: its slips drawn from its own stream (seed 7, purpose slips, its id): per mille 1000 always,
        per mille 1 at the second draw only if (r × 1000) >> 24 is 0; the read without a clamp meter and the hand
        action without a 17 mm spanner go to their else; every tool back in the box at the end."""
        r = self.st['runs'][4]
        e = run_on(self.st, r)
        s0 = W.stream(7, W.TAGS['slips'], 'ic2')
        s1, r1 = W.draw(s0)
        s2, r2 = W.draw(s1)
        self.assertEqual(e.slip_s['ic2'], s2)
        slips = [x for x in r['events'] if x[1] == 'slip']
        self.assertEqual(len(slips), 1 + ((r2 * 1000) >> 24 < 1))
        self.assertEqual(slips[0][2:], ['ic2', 'ic_job', 8])
        self.assertEqual(e.v('g1_body_loose'), 1.0)
        self.assertIn(['read', 'ic2', '10LAB10CP501', None, 'tool'], [x[1:] for x in r['events']])
        self.assertIn(['hand', '10LAB10CP501', 'tighten', 'spanner_17', 'ic2', 'refused', ['tool']],
                      [x[1:] for x in r['events']])
        self.assertEqual(e.carried, {})
        self.assertEqual(e.tool_n, [list(c for _, c in at) for at in e.tools['at']])
        self.assertEqual(e.slip_s['ic1'], W.stream(7, W.TAGS['slips'], 'ic1'))     # nobody else drew

    def test_pre_empted(self):
        ev = [x[1:] for x in self.st['runs'][5]['events'] if x[0] in (515, 520, 521, 551)
              and x[1] in ('hand', 'task', 'fault')]
        self.assertIn(['hand', '10LAB10CP501', 'open_cover', 'sd_flat', 'ic2', 'abandoned', []], ev)
        self.assertLess(ev.index(['hand', '10LAB10CP501', 'open_cover', 'sd_flat', 'ic2', 'abandoned', []]),
                        ev.index(['task', 'ic2', 'ic_urgent', 'start']))
        self.assertEqual(ev[-1], ['hand', '10LAB10CP501', 'open_cover', 'sd_flat', 'ic2', 'start', []])
        self.assertNotIn(['fault', 'f_low'], ev)        # (pressed with the gauge locked out: not made)

    def test_task_ended_under_a_hand_action(self):
        """(The blind review of HW1) an NPC's task that ends while its hand action is under way (a stop, a failure, a
        suspended permit's job) abandons the action: nothing written at its end, no result handed to a later step."""
        e = run_on(self.st, self.st['runs'][4], 525)
        sr = e.staff
        p = sr.people[sr.st.person_ix['ic2']]
        self.assertIn('ic2', e.busy)
        self.assertTrue(p.cur['st'].get('hw'))
        sr.finish(p, 'abandoned')
        self.assertNotIn('ic2', e.busy)
        self.assertEqual(e.events[-2][1:], ['hand', '10LAB10CP501', 'open_cover', 'sd_flat', 'ic2', 'abandoned', []])
        e.step(20)
        self.assertEqual(e.v('g1_body_open'), 0.0)

    def pick(self, s, weights):
        s, r = W.draw(s)
        y = (r * sum(weights)) >> 24
        acc = 0
        for k, w in enumerate(weights):
            acc += w
            if acc > y:
                return s, k

    def test_causes_from_the_stream(self):
        """Each draw from the fault's stream (seed 7, purpose causes, its id) with the weights 3, 2 and loose_w (1):
        at steps 2, 32 and 102 only (not when named, not when the fault isn't made)."""
        r = self.st['runs'][7]
        names = ['blocked', 'drift', 'term']
        s = W.stream(7, W.TAGS['causes'], 'f_low')
        want = []
        for _ in range(3):
            s, k = self.pick(s, [3, 2, 1])
            want.append(names[k])
        got = [(x[0], x[3]) for x in r['events'] if x[1] == 'cause']
        self.assertEqual(got, [(2, want[0]), (32, want[1]), (36, 'term'), (102, want[2])])
        e = run_on(self.st, r)
        self.assertEqual(e.cause_s['f_low'], s)
        self.assertNotIn(36, [x[0] for x in r['events'] if x[1] == 'instructor' and len(x) == 4])

    def test_cures(self):
        """wo_gauge cures blocked and drift, wo_gauge2 term: the done of a work that doesn't cure, and a repair under
        its permit, repair nothing and make no event; the trainer's repair repairs whatever the cause."""
        r = self.st['runs'][7]
        reps = [x[0] for x in r['events'] if x[1] == 'repair']
        cause0 = next(x[3] for x in r['events'] if x[1] == 'cause')
        self.assertEqual(reps, ([12] if cause0 in ('blocked', 'drift') else []) + [34, 67])
        self.assertNotIn(47, [x[0] for x in r['events']])       # the repair under the permit: no event at all
        e = run_on(self.st, r, 66)
        self.assertEqual((e.v('g1_fault'), e.v('g1_term')), (1.0, 1.0))
        e.step()
        self.assertEqual((e.v('g1_fault'), e.v('g1_term')), (1.0, 1.0))     # (the term cause has no repair)

    def test_cure_follows_the_fix(self):
        """REALISM.md §2.16: a cause's `fixed`: under the drift, the gland torqued (the loose terminal's fix) leaves the
        fault at the work's done and at a repair under its permit, though the work cures the drift; the re-range (the
        drift's fix) under the work's permit taken again lets its done repair fault and cause."""
        k = next(i for i, x in enumerate(self.st['runs']) if x['why'].startswith('a cause\'s fix'))
        r = self.st['runs'][k]
        self.assertEqual([x[3] for x in r['events'] if x[1] == 'cause'], ['drift'])
        dones = [x[0] for x in r['events'] if x[1] == 'permit' and x[3] == 'done' and x[5] == 'done']
        self.assertEqual(dones, [44, 62])
        self.assertEqual([x[0] for x in r['events'] if x[1] == 'repair'], [62])
        e = run_on(self.st, r, 61)
        self.assertEqual((e.v('g1_fault'), e.v('g1_drift'), e.v('g1_urv_ok')), (1.0, 1.0, 1.0))
        e = run_on(self.st, r, 62)      # (the done's input applied in its own step)
        self.assertEqual((e.v('g1_fault'), e.v('g1_drift')), (0.0, 0.0))

    def test_value_weight(self):
        r = self.st['runs'][8]
        names = ['blocked', 'drift', 'term']
        s = W.stream(7, W.TAGS['causes'], 'f_low')
        want = []
        for _ in range(20):
            s, k = self.pick(s, [3, 2, 7])
            want.append(names[k])
        self.assertEqual([x[3] for x in r['events'] if x[1] == 'cause'], want)

    def test_no_keys_no_state(self):
        """A run without HW1's keys keeps its snapshot's keys and digest (its own vectors stay byte for byte)."""
        with open(G.OUT3, encoding='utf-8') as f:
            V = json.load(f)
        for part in ('staff', 'wear', 'weather'):
            for r in V[part]['runs']:
                for s in r['states']:
                    self.assertFalse({'carried', 'busy', 'causes'} & set(s), part)

    def test_component_from_the_workshop_tree(self):
        """A hand action's component is checked against the Workshop data file's components when the kind has one,
        else `body` (WORKSHOP.md §4.1)."""
        from ref import plant3d_hands as H

        class B:
            pass
        b = B()
        b.model = B()
        b.model.hands = [{'kks': 'X', 'action': 'a', 'component': 'terminal_block'}]
        b.equipment = {'X': {'part': 'pressure_transmitter'}}
        b.workshop = {'pressure_transmitter': {'components': 2}}       # (the Workshop check's summary: a count)
        b.workshop_tree = {'pressure_transmitter': {'housing', 'terminal_block'}}
        H.check_components(b)
        b.model.hands[0]['component'] = 'body'
        with self.assertRaises(P.FormatError):
            H.check_components(b)
        b.workshop, b.workshop_tree = {}, {}
        H.check_components(b)


class AudioVectors(PartVectors, unittest.TestCase):
    """Milestone HS7 (REALISM.md §8.5): personal audio and the phone: banned and Ex zones, the audio and phone inputs
    and acts, noticing after a drawn delay or at once after a missed call, the device held until the duty ends."""
    part, rejects = 'audio', 'REJECTS_AUDIO'

    def evs(self, k, kinds):
        return [x for x in self.st['runs'][k]['events'] if x[1] in kinds]

    def test_noticed_not_at_once(self):
        """An observer sharing the zone takes at least `notice`'s minimum (2 clock minutes, 20 steps at day_scale
        60) to notice music: the stop's task never starts in the step the act does (a hard hat is seen at once)."""
        for k in (0, 3):
            ev = self.st['runs'][k]['events']
            start = next(x[0] for x in ev if x[1:4] == ['unsafe', 'a_fo1', 'audio'])
            stop = next(x for x in ev if x[1] == 'stop' and x[3] == 'a_fo1')
            given = next(x[0] for x in ev if x[1:5] == ['task', stop[2], 'stop_unsafe', 'start'] and x[0] >= start)
            self.assertGreaterEqual(given - start, 20, f'run {k}')

    def test_control_room(self):
        """The follow-ups (the user, 2026-11-03): music in the control room (`audio.rooms`) is an act whose detail is
        the room; leaving its places ends it; the shift supervisor at the room's table notices and stops it."""
        run = self.st['runs'][9]
        self.assertEqual(run['files']['staff.json']['audio']['rooms'], ['cr'])
        acts = [x[1:] for x in run['events'] if x[1] in ('unsafe', 'safe') and x[2] == 'a_fo1']
        self.assertEqual(acts[:3], [['unsafe', 'a_fo1', 'audio', 'cr'], ['safe', 'a_fo1', 'audio', 'cr'],
                                    ['unsafe', 'a_fo1', 'audio', 'cr']])
        self.assertIn(['stop', 'a_sup', 'a_fo1', 'audio', 'cr', 'done', []], [x[1:] for x in run['events']])
        self.assertIn(['held', 'a_fo1', 'a_sup'], [x[1:] for x in run['events']])

    def test_held_off_duty_to_the_next_duty(self):
        """Taken off duty (18:30, day 1), the device stays held through a jump to 17:30 of day 2 (inside the next
        duty: an audio input refused, held) and comes back with the jump past its end (18:00)."""
        ev = self.st['runs'][10]['events']
        held = next(x for x in ev if x[1:] == ['held', 'a_fo1', 'b_sup'])
        refused = next(x for x in ev if x[1:] == ['audio', 'a_fo1', 20, 'refused', ['held']])
        returned = next(x for x in ev if x[1:] == ['returned', 'a_fo1'])
        jumps = [x for x in ev if x[1] == 'jump' and x[4] == 'done']
        # (before the follow-ups it came back in the stop's step)
        self.assertLess(held[0], jumps[0][0])
        self.assertLess(refused[0], returned[0])
        self.assertEqual(returned[0], jumps[1][0])
        self.assertEqual([x[1:] for x in ev if x[1] == 'audio'][-1], ['audio', 'a_fo1', 20, 'done', []])

    def test_music_at_the_wheel(self):
        ev = [x[1:] for x in self.st['runs'][11]['events'] if x[1] == 'audio']
        self.assertEqual(ev, [['audio', 'drv1', 30, 'done', []], ['audio', 'drv1', 0, 'done', ['driving']],
                              ['audio', 'drv1', 20, 'refused', ['driving']], ['audio', 'drv1', 0, 'done', []],
                              ['audio', 'drv1', 20, 'done', []]])

    def test_locker_and_radio_call_missed(self):
        ev = [x[1:] for x in self.st['runs'][12]['events']]
        phone = [x for x in ev if x[0] == 'phone']
        self.assertEqual(phone, [['phone', 'a_fo1', 'leave', 'refused', ['locker']],
                                 ['phone', 'a_fo1', 'leave', 'done', []], ['phone', 'a_fo1', 'take', 'done', []]])
        missed = [x for x in self.st['runs'][12]['events'] if x[1] == 'missed']
        self.assertIn(['missed', 'a_fo1', 'check_alarm', 'c_ccr', 'call'], [x[1:] for x in missed])
        # a call and its message in one step are one exchange: missed once
        self.assertEqual(len({(x[0], x[4]) for x in missed}), len(missed))
        self.assertIn(['held', 'a_fo1', 'a_sup'], ev)

    def test_phone_taken_only_at_its_locker(self):
        """The second follow-ups (the user, 2026-11-07): the engine knows which locker holds the phone; taking it at
        another is refused (locker), leaving it while it is in a locker is refused (left), and the digest between the
        leave and the take carries the locker (the phone's entry 3 + its place index, run 2's and the session's
        digests changed with it)."""
        r = self.st['runs'][13]
        phone = [x[3:] for x in r['events'] if x[1] == 'phone']
        self.assertEqual(phone, [['leave', 'done', []], ['leave', 'refused', ['left']], ['take', 'refused', ['locker']],
                                 ['leave', 'refused', ['left']], ['take', 'done', []], ['take', 'done', []]])
        self.assertEqual([x[0] for x in r['events'] if x[1] == 'phone' and x[4] == 'done'], [3, 60, 62])
        e = run_on(self.st, r, 50)
        sm = e.staff
        me = sm.people[sm.st.person_ix['a_fo1']]
        self.assertEqual((me.phone, me.locker), (0, sm.st.pix['locker3']))
        self.assertEqual(e.snapshot()['audio'], {'a_fo1': [0, 0]})

    def test_held_off_duty_to_the_next_duty_worked(self):
        """Taken off duty, the device comes back at the end of the next duty actually worked (the user, 2026-11-07):
        a jump past the whole next duty (never begun) keeps it held; a jump landing inside the duty after begins it,
        and the device comes back once that one ends."""
        ev = self.st['runs'][14]['events']
        jumps = [x[0] for x in ev if x[1] == 'jump' and x[4] == 'done']
        self.assertEqual(len(jumps), 3)
        self.assertEqual([x[0] for x in ev if x[1:] == ['audio', 'a_fo1', 20, 'refused', ['held']]], [320, 360])
        self.assertEqual([x[0] for x in ev if x[1:] == ['returned', 'a_fo1']], [jumps[2]])
        self.assertIn([400, 'audio', 'a_fo1', 20, 'done', []], ev)
        from ref import plant3d_staff as S
        e = run_on(self.st, self.st['runs'][14], 330)
        me = e.staff.people[e.staff.st.person_ix['a_fo1']]
        self.assertEqual((me.phone, me.held_to), (2, S.HELD_NEXT))      # (its next duty passed in the gap)
        e = run_on(self.st, self.st['runs'][14], 370)
        me = e.staff.people[e.staff.st.person_ix['a_fo1']]
        self.assertTrue(me.on)
        self.assertEqual(me.held_to, me.duty[1])

    def test_missed_call_reports_the_act(self):
        """A message missed over the music while the act goes on: the shift supervisor (the only one of the roles on
        duty at 17:00, in the control room, nowhere near the hall) is given the stop at once: it starts when their
        idle step ends, and they are the one who holds the device."""
        ev = self.st['runs'][1]['events']
        missed = next(x for x in ev if x[1] == 'missed')
        self.assertEqual(missed[2], 'a_fo1')
        started = next(x for x in ev if x[1:4] == ['task', 'a_sup', 'stop_unsafe'])
        self.assertLessEqual(missed[0], started[0])
        self.assertIn([started[0], 'task', 'a_sup', 'idle_sup', 'done'], ev)
        self.assertIn(['held', 'a_fo1', 'a_sup'], [x[1:] for x in ev])

    def test_device_held_until_the_duty_ends(self):
        ev = self.st['runs'][1]['events']
        off = next(x[0] for x in ev if x[1:] == ['duty', 'a_fo1', 'off'])
        self.assertEqual([x[0] for x in ev if x[1] == 'returned'], [off])
        held = next(x[0] for x in ev if x[1] == 'held')
        self.assertTrue(all(x[4] == 'refused' and x[5] == ['held'] for x in ev
                            if x[1] in ('audio', 'phone') and held < x[0] < off))
        self.assertEqual(self.evs(1, ('audio',))[-1][4:], ['done', []])

    def test_device_back_after_a_jump_into_the_next_duty(self):
        """The device held in one duty comes back when that duty ends, by the clock: a jump landing inside the next
        duty (on duty again in the same step) gives it back in the jump's step, and the music plays again."""
        ev = self.st['runs'][7]['events']
        jump = next(x for x in ev if x[1] == 'jump')
        self.assertEqual(jump[4], 'done')
        self.assertIn([jump[0], 'returned', 'a_fo1'], ev)
        self.assertIn([420, 'audio', 'a_fo1', 20, 'done', []], ev)

    def test_session_slots(self):
        """In a session each player's audio and phone events carry their slot; a message to their role is missed by
        each player over the mask, in slot order."""
        r = self.st['runs'][6]
        self.assertTrue(r['session'])
        ev = r['events']
        self.assertIn([20, 'audio', 'a_fo2', 70, 'done', [], 1], ev)
        self.assertIn([301, 'audio', 'a_fo2', 10, 'refused', ['left'], 1], ev)
        missed = [x for x in ev if x[1] == 'missed']
        self.assertEqual([x[2] for x in missed[:2]], ['a_fo1', 'a_fo2'])
        self.assertEqual(missed[0][0], missed[1][0])

    def test_music_toggled_is_still_noticed(self):
        """Music off and on again every clock minute (under the 2-minute least time to notice) in an observer's
        sight: their time keeps running while it is off, so the act is still noticed, stopped and the device held."""
        ev = self.st['runs'][8]['events']
        starts = [x for x in ev if x[1:4] == ['unsafe', 'a_fo1', 'audio']]
        self.assertGreater(len(starts), 5)
        self.assertEqual([x[1:] for x in ev if x[1] == 'held'], [['held', 'a_fo1', 'hse1']])

    def test_refusals(self):
        self.assertIn([2301, 'phone', 'a_fo1', 'leave', 'refused', ['held']], self.evs(0, ('phone',)))
        self.assertIn([620, 'audio', 'a_fo1', 20, 'refused', ['left']], self.evs(2, ('audio',)))
        self.assertEqual([x[4:] for x in self.evs(4, ('audio', 'phone'))], [['refused', ['no_audio']]] * 2)
        self.assertEqual(self.evs(5, ('audio', 'phone', 'held')), [])     # free mode: nothing

    def test_no_acts_of_the_new_kinds_without_the_key(self):
        self.assertFalse([x for x in self.evs(4, ('unsafe',)) if x[3] in ('audio', 'phone')])

    def test_out_of_range_inputs_ignored(self):
        """A volume of 101 or not a number, a phone input not leave or take: no event."""
        self.assertEqual([x[3] for x in self.evs(1, ('audio',))], [60, 20])
        self.assertNotIn('drop', [x[3] for x in self.evs(2, ('phone',))])

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
            # cold_iron has its season's weather (the user, 2026-11-03): the clock values, then the weather's kind
            self.assertEqual(e.names[-3:], ['world_hour', 'world_day', 'world_wx'])
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

    def test_hands_load(self):
        """--hands (HW1): the component states written by hand actions, the meter values read through meters,
        tools.json at the store; it passes the validator and steps with the staff's scenario."""
        import glob
        sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'tools', 'plant3d'))
        import realism_synth as RS
        root = os.path.join(os.path.dirname(HERE), 'data', 'plant3d')
        b = P.check_dir(root)
        vals = RS.make(600, b, engine=True)
        hands = RS.hands_doc(b, vals)
        self.assertEqual((len(hands[0]), len(hands[1])), (150, 50))
        files = {}
        for f in glob.glob(os.path.join(root, '**', '*.json'), recursive=True):
            with open(f, encoding='utf-8') as fh:
                files[os.path.relpath(f, root)] = json.load(fh)
        RS.apply(files, vals, RS.weather_doc(), RS.WX_EXT, hands)
        b2 = P.check_files({k: json.dumps(v).encode() for k, v in files.items()})
        e = P.Engine(b2, 'shift_cold')
        self.assertTrue(e.hw)
        e.step(20)
        self.assertTrue(all(map(lambda x: x == x, e.cur)))


class LabVectors(PartVectors, unittest.TestCase):
    """Milestone AG3 (REALISM.md §2.19): the collector and camera read through, sample nodes taken by hand actions,
    the lab's results after clock hours from each node's lab stream, the queue, the sample authority, a jump."""
    part, rejects = 'lab', 'REJECTS_LAB'
    U = 2 ** 24

    def evs(self, k, kinds):
        return [x for x in self.st['runs'][k]['events'] if x[1] in kinds]

    def draws(self, r, name, n):
        """The first n draws (u in [0, 1)) of a sample node's own lab stream (§2.1: purpose lab, the node's name)."""
        s = W.stream(W.world_seed(r['scenario']), W.TAGS['lab'], name)
        out = []
        for _ in range(n):
            s, x = W.draw(s)
            out.append(x / self.U)
        return out

    def test_reasons_in_order(self):
        """where, tool, authority as a hand action's; the queue full: lab, after the needs."""
        ev = self.evs(0, ('hand',))
        why = [(x[0], x[3], x[5], x[6], x[7]) for x in ev if x[6] == 'refused']
        self.assertEqual(why, [
            (3, 'take_oil', 'ic1', 'refused', ['where', 'tool']), (3, 'take_oil', 'ic1', 'refused', ['where']),
            (6, 'take_oil', 'ic1', 'refused', ['tool']), (6, 'take_oil', 'ic2', 'refused', ['authority', 'where', 'tool']),
            (65, 'take_oil', 'ic1', 'refused', ['lab']), (66, 'take_oil', 'ic1', 'refused', ['lab'])])
        self.assertEqual(self.evs(1, ('hand',)), [
            [6, 'hand', '10LAB10CP501', 'take_oil', 'oil_kit', 'ic1', 'refused', ['authority']],
            [6, 'hand', '10LAB10CP501', 'clean_glass', None, 'ic1', 'start', []]])

    def test_queue_filled_under_a_timed_action(self):
        """A timed action whose node's queue filled while it was under way (another person's sample) is done at its
        end but takes no sample and draws nothing: the eight results are the first eight draws' (seven of ic1's, its
        eighth), and the later timed sample's spread is the ninth draw; the next instant one meanwhile refused lab."""
        r = self.st['runs'][4]
        ev = self.evs(4, ('hand',))
        self.assertIn([36, 'hand', '10LAB10CP501', 'take_oil_slow', 'oil_kit', 'ic2', 'done', []], ev)
        self.assertIn([37, 'hand', '10LAB10CP501', 'take_oil', 'oil_kit', 'ic2', 'refused', ['lab']], ev)
        seen = {}

        def each(e):
            seen[e.step_no] = (e.v('oil_fe'), len(e.lab_q['lab_fe']))
        e = run_on(self.st, r, each=each)
        self.assertEqual(seen[35][1], 8)            # full before the timed action's end
        self.assertEqual(seen[36][1], 8)            # and after it: no sample taken
        fe = [x[3] for x in e.events if x[1] == 'lab' and x[2] == 'lab_fe']
        self.assertEqual(len(fe), 9)
        u = self.draws(r, 'lab_fe', 9)
        self.assertAlmostEqual(fe[8], seen[100][0] + (-2 + 4 * u[8]), places=9)

    def test_samples_and_results(self):
        """Each sample: ref's value (the previous step's in step 1, this step's in step 3 for a timed action) plus
        spread(u), u the next draw of the node's lab stream; due the clock at the action's end plus hours × 36,000
        tenths; the results in step 3 at their dues, in order, each with its lab event and the node's value."""
        r = self.st['runs'][0]
        seen = {}

        def each(e):
            seen[e.step_no] = (e.v('oil_fe'), e.clock(), e.v('lab_fe'), e.v('lab_vis'),
                               [list(q) for q in e.lab_q['lab_fe']])
        e = run_on(self.st, r, each=each)
        lab = [x for x in e.events if x[1] == 'lab']           # (exact: the file's numbers are rounded)
        done = [x for x in self.evs(0, ('hand',)) if x[6] == 'done']
        taken = []          # (step, the oil's iron read, the clock at the end) of each lab_fe sample
        for x in done:
            n = x[0]
            if x[3] == 'take_oil':
                taken.append((n, seen[n - 1][0], seen[n][1], True))
            else:
                taken.append((n, seen[n][0], seen[n][1], False))
        u = self.draws(r, 'lab_fe', len(taken))
        want = [(c + 3600, fe + (-2 + 4 * x)) for (n, fe, c, _), x in zip(taken, u)]
        got = [[x[0], x[3]] for x in lab if x[2] == 'lab_fe']
        self.assertEqual(len(got), len(want))
        for (due, v), (n, name, value) in zip(want, [(x[0], 'lab_fe', x[1]) for x in got]):
            self.assertEqual(value, v)
            self.assertEqual(seen[n][1] >= due > seen[n - 1][1], True, (n, due))
            self.assertEqual(seen[n][2], value)
        # lab_vis: the constant 68 plus its own stream's spread, only from take_oil (two nodes each)
        nv = sum(1 for t in taken if t[3])
        uv = self.draws(r, 'lab_vis', nv)
        got = [x[3] for x in lab if x[2] == 'lab_vis']
        self.assertEqual(got, [68 + (-1.5 + 3 * x) for x in uv])
        self.assertEqual(seen[0][3], 70.0)           # the scenario's init until its first result
        # eight queued at most
        self.assertEqual(max(len(v[4]) for v in seen.values()), 8)
        self.assertEqual(len(seen[64][4]), 8)

    def test_snapshot_and_digest_carry_the_queue(self):
        r = self.st['runs'][0]
        s = [x for x in r['states'] if x['step'] == 10][0]
        self.assertEqual(sorted(s['lab']), ['lab_fe', 'lab_vis'])
        self.assertEqual(s['lab']['lab_fe'][0][0] + 3600, s['lab']['lab_vis'][0][0])
        e = run_on(self.st, r, 10)
        tree = e.digest_tree()[-1]
        self.assertEqual(len(tree), 2)
        self.assertEqual(list(tree[0][1].items), [q[0] for q in e.lab_q['lab_fe']])
        d = e.digest()
        e.lab_q['lab_fe'][0][1] += 1e-9
        self.assertNotEqual(e.digest(), d)

    def test_results_across_a_jump(self):
        ev = [x for x in self.st['runs'][2]['events'] if x[1] in ('jump', 'lab')]
        self.assertEqual([x[:3] for x in ev[:3]], [[10, 'jump', 1134600], [10, 'lab', 'lab_fe'], [10, 'lab', 'lab_vis']])
        self.assertEqual(ev[3][:3], [74, 'lab', 'lab_fe'])         # taken at 14 after the jump: 60 steps on

    def test_npc_round(self):
        ev = self.evs(3, ('hand', 'read', 'lab'))
        mine = [x for x in ev if 'ic1' in x or x[1] == 'lab']
        self.assertIn([541, 'read', 'ic1', '10LAB10CP501', 3.0, 'out_of_range'], mine)
        self.assertIn([541, 'read', 'ic1', '10LAB10CP501', 13.0, 'ok'], mine)
        self.assertEqual([x[:3] for x in mine if x[1] == 'lab'], [[602, 'lab', 'lab_fe'], [623, 'lab', 'lab_fe'],
                                                                 [662, 'lab', 'lab_vis']])

    def test_no_samples_no_part(self):
        """A run without sample nodes keeps its digest tree and snapshot as before (the hands part's runs)."""
        with open(G.OUT3, encoding='utf-8') as f:
            hands = json.load(f)['hands']
        e = run_on(hands, hands['runs'][0], 5)
        self.assertEqual(e.lab_nodes, [])
        self.assertNotIn('lab', e.snapshot())

    def test_not_on_the_bench(self):
        from ref import plant3d_bench as B
        self.assertIn('sample', B.NOT_ON_THE_BENCH)



class HseVectors(PartVectors, unittest.TestCase):
    """Milestone HS1 (REALISM.md §8.6): hse.json's hazard library, works' job kinds, the jsa and talk inputs, the issue
    refused without a JSA, the talk's attendance, the JSA's life with its permit."""
    part, rejects = 'hse', 'REJECTS_HSE'

    def evs(self, k, kinds):
        return [x[1:] for x in self.st['runs'][k]['events'] if x[1] in kinds]

    def test_npc_jsa_is_the_works_own_list(self):
        """An NPC's JSA is the work's own list: the job's hazards in order, then each hazard's controls in order, each
        once (pump_brg: rotating loto guard, pinch gloves, pressure drain loto); its talk's points the job's hazards."""
        ev = self.evs(0, ('jsa', 'talk'))
        self.assertIn(['jsa', 'wo_pump', ['rotating', 'pinch', 'pressure'], ['loto', 'guard', 'gloves', 'drain'],
                       'ms1', 'done', []], ev)
        self.assertIn(['jsa', 'wo_paint', ['height', 'fumes', 'dropped'], ['harness', 'barrier', 'mask', 'ventilate'],
                       'ms1', 'done', []], ev)
        talks = [x for x in ev if x[0] == 'talk']
        self.assertEqual({x[1]: x[2] for x in talks}, {'wo_pump': ['rotating', 'pinch', 'pressure'],
                                                        'wo_paint': ['height', 'fumes', 'dropped']})

    def test_npc_step_without_a_work(self):
        """The adversarial review: an NPC's JSA step on a task with no work (a routine's slot starting the pump's JSA
        task, which only a call gives a work) is unknown, as a permit step's is, and the task abandoned: not a crash;
        the supervisor goes on to the painting's JSA."""
        ev = [x[1:] for x in self.st['runs'][8]['events']]
        self.assertIn(['jsa', None, [], [], 'ms1', 'unknown', []], ev)
        i = ev.index(['jsa', None, [], [], 'ms1', 'unknown', []])
        self.assertEqual(ev[i + 1], ['task', 'ms1', 'jsa_pump', 'abandoned'])
        self.assertIn(['jsa', 'wo_paint', ['height', 'fumes', 'dropped'], ['harness', 'barrier', 'mask', 'ventilate'],
                       'ms1', 'done', []], ev[i:])

    def test_npc_flow_order(self):
        """Every JSA before its permit's issue, every talk after it and before its accept; the talk in the workshop
        attended by the technician who then accepts; the one at the muster point by the contractors standing there."""
        ev = self.st['runs'][0]['events']
        for w in ('wo_pump', 'wo_paint'):
            jsa = next(x[0] for x in ev if x[1] == 'jsa' and x[2] == w and x[6] == 'done')
            issue = next(x[0] for x in ev if x[1:4] == ['permit', w, 'issue'] and x[5] == 'done')
            talk = next(x for x in ev if x[1] == 'talk' and x[2] == w and x[5] == 'done')
            accept = next(x for x in ev if x[1:4] == ['permit', w, 'accept'] and x[5] == 'done')
            self.assertLess(jsa, issue, w)
            self.assertLess(issue, talk[0], w)
            self.assertLess(talk[0], accept[0], w)
            self.assertIn(accept[4], talk[7], f'{w}: the acceptor was at the talk')
        self.assertFalse([x for x in ev if x[1] == 'permit' and x[3] == 'issue' and 'jsa' in x[6]])

    def test_issue_refused_without_a_jsa(self):
        """The night supervisor's issue of the painting before its JSA is refused `jsa` (their task abandoned), the
        form's too; once the JSA is made the issue is done; the reasons in §2.7's order (authority, state, iso_busy,
        jsa)."""
        ev = self.evs(2, ('permit', 'jsa'))
        issues = [x for x in ev if x[0] == 'permit' and x[2] == 'issue']
        self.assertEqual([x[4:] for x in issues], [['refused', ['jsa']], ['refused', ['jsa']], ['done', []]])
        self.assertEqual(issues[0][3], 'a_sup')
        self.assertIn(['jsa', 'wo_paint', ['height', 'fumes', 'dropped'], ['harness', 'barrier', 'mask', 'ventilate'],
                       'ms1', 'refused', ['state']], ev)

    def test_unknown_and_refused(self):
        ev = self.evs(1, ('jsa', 'talk'))
        self.assertEqual([x[5] for x in ev if x[0] == 'jsa'][:7], ['unknown'] * 7)
        self.assertEqual(ev[7], ['talk', 'wo_pump', [], 'ms1', 'unknown', [], []])
        self.assertEqual(ev[8], ['jsa', 'wo_pump', ['rotating'], [], 'a_sup', 'refused', ['authority']])
        self.assertEqual(ev[9], ['talk', 'wo_pump', ['rotating'], 'ms1', 'refused', ['state', 'jsa'], []])

    def test_attendance(self):
        """In the workshop (a room, at its door) the technicians at its benches attend; on the way the giver alone; at
        the muster point (no room) those standing there; the work's attendance is the union, in people order."""
        r = self.st['runs'][1]
        talks = [x for x in r['events'] if x[1] == 'talk' and x[5] == 'done']
        self.assertEqual([x[7] for x in talks], [['mech1', 'mech2', 'ms1'], ['ms1'], ['ms1', 'csup', 'con1', 'con2']])
        self.assertEqual(r['states'][-1]['hse']['wo_pump']['talk'], ['mech1', 'mech2', 'ms1', 'csup', 'con1', 'con2'])

    def test_cancel_clears(self):
        ev = self.evs(3, ('talk', 'jsa'))
        self.assertEqual([x[4:6] for x in ev if x[0] == 'talk'],
                         [['done', []], ['refused', ['state', 'jsa']], ['refused', ['jsa']], ['done', []]])
        self.assertIn(['jsa', 'wo_pump', ['rotating'], [], 'a_sup', 'refused', ['authority']], ev)

    def test_without_hse_nothing_changes(self):
        """Without hse.json the inputs are unknown, the snapshots have no `hse` and the digests no part of it: the
        safety staff's own runs (plant3d-v2.json) stay byte for byte."""
        r = self.st['runs'][4]
        self.assertEqual([x[1:][-2] for x in r['events'] if x[1] in ('jsa', 'talk')], ['unknown', []])
        self.assertFalse(any('hse' in s for s in r['states']))

    def test_free_mode_talk_attended_by_nobody(self):
        r = self.st['runs'][5]
        self.assertIn(['talk', 'wo_paint', ['height'], None, 'done', [], []], [x[1:] for x in r['events']])
        self.assertEqual(r['states'][-1]['hse'], {'wo_paint': {'jsa': [['height'], ['harness'], None]}})

    def test_player_plays_their_steps(self):
        """The maintenance supervisor played (the Trainee helper as the app would): the hosting task's JSA, the called
        jsa_pump and talk_pump, each step done by their own input, the tasks done."""
        ev = self.st['runs'][7]['events']
        for t in ('host_paint', 'jsa_pump', 'talk_pump'):
            self.assertIn(['task', 'ms1', t, 'done'], [x[1:5] for x in ev], t)
        self.assertIn(['talk', 'wo_pump', ['rotating', 'pinch', 'pressure'], 'ms1', 'done', []],
                      [x[1:7] for x in ev])

    def test_session(self):
        ev = self.evs(6, ('jsa', 'talk'))
        self.assertEqual(ev[-1], ['talk', 'wo_paint', ['height', 'fumes'], 'hse1', 'done', [], ['a_elec', 'hse1', 'ms1']])
        self.assertEqual(self.st['runs'][6]['states'][-1]['hse']['wo_paint']['jsa'][2], 'hse1')



class DiscussVectors(PartVectors, unittest.TestCase):
    """Milestone DC3 (REALISM.md §6.3.1): discussions.json, the step `discuss` (a lead's meeting and a joiner's
    wait), modes npc and open, points taken by picks or by their defaults, the agreement and its outcome task, and the
    input `discuss` with its reasons."""
    part, rejects = 'discuss', 'REJECTS_DISCUSS'

    def evs(self, k, kinds=('discussion', 'point', 'discuss')):
        return [x for x in self.st['runs'][k]['events'] if x[1] in kinds]

    def test_npc_mode(self):
        """Between NPCs: started once a called technician and the called electrical authorised person are in the
        office (the first called of each role in person order), every point's default after its 10 minutes (null takers), the last
        agreement (no task): the supervisor's task goes on in the same step; the participant technician's step ends
        with it, the other's after its 15 minutes in the office."""
        ev = self.evs(0)
        start = ev[0]
        self.assertEqual(start[1:], ['discussion', 'pump_run', 'start', 'a_sup', ['a_sup', 'mech1', 'a_elec'], 'npc'])
        n = start[0] + 10 * 10
        self.assertEqual(ev[1:], [[n, 'point', 'pump_run', 'when', 'weekend', None],
                                  [n, 'point', 'pump_run', 'watch', 'weekly', None],
                                  [n, 'discussion', 'pump_run', 'agreed', 2, None]])
        all_ev = self.st['runs'][0]['events']
        self.assertIn([n, 'say', 'a_sup', 'all_well', 'channel'], all_ev)
        self.assertIn([n, 'task', 'a_sup', 'debate_pump', 'done'], all_ev)
        end = self.st['runs'][0]['states'][-1]['discussions']['pump_run']
        self.assertEqual(end, {'count': 1, 'lead': 'a_sup', 'participants': ['a_sup', 'mech1', 'a_elec'],
                               'mode': 'npc', 'start': start[0], 'point': 2, 'since': start[0],
                               'taken': [['weekend', None], ['weekly', None]], 'agreed': 2})

    def test_open_mode_picks_and_reasons(self):
        """The trainee technician: a pick before the start (state), ids not in the file (unknown), the second point
        while the first is current (state), their pick (done, their id on the point), a second pick of it
        (state: taken); the second point's default after its 3 minutes from the pick."""
        ev = [x[:2] + x[3:] for x in self.evs(1)]
        self.assertEqual([x[1:] for x in ev if x[1] == 'discuss'], [
            ['discuss', 'pump_run', 'when', 'now', 'refused', ['state']],
            ['discuss', 'pay', 'when', 'now', 'refused', ['unknown']],
            ['discuss', 'pump_run', 'why', 'now', 'refused', ['unknown']],
            ['discuss', 'pump_run', 'when', 'later', 'refused', ['unknown']],
            ['discuss', 'pump_run', 'when', None, 'refused', ['unknown']],
            ['discuss', 'pump_run', 'watch', 'daily', 'refused', ['state']],
            ['discuss', 'pump_run', 'when', 'now', 'done', []],
            ['discuss', 'pump_run', 'when', 'weekend', 'refused', ['state']]])
        full = self.evs(1)
        self.assertEqual(full[5][1:7], ['discussion', 'pump_run', 'start', 'a_sup', ['a_sup', 'mech1', 'a_elec'],
                                        'open'])
        pick = next(x for x in full if x[1] == 'discuss' and x[6] == 'done')
        self.assertEqual(pick[2], 'mech1')
        nxt = full[full.index(pick) + 1]
        self.assertEqual(nxt, [pick[0], 'point', 'pump_run', 'when', 'now', 'mech1'])
        self.assertIn([pick[0] + 30, 'point', 'pump_run', 'watch', 'weekly', None], full)

    def test_outcome_task_replaces_the_rest(self):
        """The first agreement (`now`) names stop_pump: it runs in place of the rest of the lead's task (no
        all_well said by debate_pump), as choose's task does."""
        r = self.st['runs'][1]['events']
        ag = next(x for x in r if x[1] == 'discussion' and x[3] == 'agreed')
        self.assertEqual(ag[4:], [0, 'stop_pump'])
        k = r.index(ag)
        self.assertEqual(r[k + 1:k + 3], [[ag[0], 'task', 'a_sup', 'debate_pump', 'done'],
                                          [ag[0], 'task', 'a_sup', 'stop_pump', 'start']])
        said = [x[0] for x in r if x[1:3] == ['say', 'a_sup'] and x[0] >= ag[0]]
        done = next(x[0] for x in r if x[1:5] == ['task', 'a_sup', 'stop_pump', 'done'])
        self.assertEqual(said, [done])      # (stop_pump's own say, at its end)

    def test_default_then_pick_and_a_reading_term(self):
        """The trainee lead: the first point's default after 5 minutes (null), their pick of `daily`; the valve open
        (valve_shut false, as the model's step left it) and `daily`: the second agreement, at once."""
        ev = self.evs(2)
        st = ev[0][0]
        self.assertEqual(ev[0][-1], 'open')
        self.assertEqual(ev[1], [st + 50, 'point', 'pump_run', 'when', 'weekend', None])
        pick = ev[2]
        self.assertEqual(pick[1:], ['discuss', 'a_sup', 'pump_run', 'watch', 'daily', 'done', []])
        self.assertEqual(ev[3:], [[pick[0], 'point', 'pump_run', 'watch', 'daily', 'a_sup'],
                                  [pick[0], 'discussion', 'pump_run', 'agreed', 1, None]])
        vals = self.st['runs'][2]['states'][-1]['values']
        self.assertEqual(vals['valve_shut'], 0.0)

    def test_outcome_runs_for_the_lead_alone(self):
        """An outcome task runs in the lead's task only (REALISM.md §6.3.1): a step only the lead's role may take
        (the shift supervisor's permit request, which the technician and the electrical authorised person, the
        joiners, lack) is valid in it."""
        F = G.discuss_files()
        next(t for t in F['staff.json']['tasks'] if t['id'] == 'stop_pump')['steps'].insert(
            1, {'permit': {'work': 'wo_pump', 'action': 'request'}, 'else': 2})
        P.check_files({k: v if isinstance(v, bytes) else json.dumps(v).encode() for k, v in F.items()})

    def test_session_first_pick_counts(self):
        """A session: a slot whose person is not a participant (authority), a slot playing nobody (authority); the
        supervisor's and the technician's picks of one point in one step: the first in the commit's order counts."""
        ev = [x[1:] for x in self.evs(3, ('discuss',))]
        self.assertEqual(ev, [['discuss', 'mech2', 'pump_run', 'when', 'now', 'refused', ['authority']],
                              ['discuss', None, 'pump_run', 'when', 'now', 'refused', ['authority']],
                              ['discuss', 'a_sup', 'pump_run', 'when', 'weekend', 'done', []],
                              ['discuss', 'mech1', 'pump_run', 'when', 'now', 'refused', ['state']]])
        self.assertTrue(self.st['runs'][3].get('session'))

    def test_joiner_times_out(self):
        """The supervisor absent: no discussion starts; each technician's joiner step ends 15 clock minutes (150
        steps) after they came into the office."""
        r = self.st['runs'][4]
        self.assertEqual(self.evs(4), [])
        for who in ('mech1', 'mech2'):
            came = max(x[0] for x in r['events'] if x[1] == 'move' and x[2] == who and x[4] in (
                'seat1', 'seat2', 'office_door', 'office_table') and x[0] < 300)
            arrive = next(x[5] for x in r['events'] if x[1] == 'move' and x[2] == who and x[0] == came)
            done = next(x[0] for x in r['events'] if x[1:5] == ['task', who, 'join_pump', 'done'])
            self.assertEqual(done, arrive + 150 + 10, who)     # (then the task's own minute of work)
        self.assertEqual(r['states'][-1]['discussions'], {})

    def test_no_file_no_part(self):
        """Without discussions.json the snapshots have no `discussions`, the digests no part and the input is
        unknown: every earlier part's runs stay byte for byte."""
        V = json.load(open(G.OUT3, encoding='utf-8'))
        for k, part in V.items():
            if k in ('about', 'streams', 'discuss'):
                continue
            for r in part['runs']:
                self.assertFalse(any('discussions' in s for s in r['states']), k)
        F = G.discuss_files()
        G._dc_no_file(F)
        e = P.Engine(G.check(F), 's1')
        e.discuss('pump_run', 'when', 'now')
        e.step()
        self.assertIn([1, 'discuss', None, 'pump_run', 'when', 'now', 'refused', ['unknown']], e.events)
        self.assertNotIn('discussions', e.snapshot())

    def test_lead_task_gone_ends_liveness(self):
        """A live discussion whose lead no longer has a task at its step (abandoned, stopped, skipped by a jump) is
        not live: a pick is refused (state), and the next lead's step starts a new one (count 2)."""
        from ref import plant3d_discuss as DC
        F = G.discuss_files()
        F['scenarios/s1.json']['staff']['trainee'] = 'mech1'
        e = P.Engine(G.check(F), 's1')
        pl = G.Trainee()
        while e.step_no < 280:
            pl(e)
            e.step()
        sr = e.staff
        x = sr.disc[0]
        self.assertTrue(DC._live(sr, sr.st.discuss['list'][0], x))
        lead = sr.people[x['lead']]
        sr.finish(lead, 'abandoned')
        self.assertFalse(DC._live(sr, sr.st.discuss['list'][0], x))
        e.discuss('pump_run', 'when', 'now')
        e.step()
        self.assertIn(['discuss', 'mech1', 'pump_run', 'when', 'now', 'refused', ['state']],
                      [y[1:] for y in e.events if y[0] == e.step_no])

    def test_called_not_a_bystander(self):
        """The participant of a joining role is the called person (current task at a discuss step of it), not the
        first of the role in the room: the first technician sits in the office on a break, not called, and takes no
        part; the second, called, does (the user, 2026-11-09)."""
        ev = self.evs(5)
        self.assertEqual(ev[0][1:], ['discussion', 'pump_run', 'start', 'a_sup', ['a_sup', 'mech2', 'a_elec'], 'npc'])
        start = ev[0][0]
        e = P.Engine(G.check(G.discuss_bystander_files()), 's1')
        while e.step_no < start:
            e.step()
        sr = e.staff
        m1 = sr.people[sr.st.person_ix['mech1']]
        self.assertIn(m1.pos, sr.st.rooms['office'])          # in the room, earlier in person order
        self.assertEqual(m1.cur['task'], 'sit_office')         # but not called

    def test_joiner_leaves_a_paused_lead(self):
        """The lead's task held at the end of their day (the discussion still live): the participant supervisor waits
        15 clock minutes (150 steps) of the pause from the first step it sees it, then their step is done; the
        discussion stays unended (the user, 2026-11-09)."""
        r = self.st['runs'][6]
        ev = self.evs(6)
        self.assertEqual(ev, [[ev[0][0], 'discussion', 'gauge_cal', 'start', 'mech1', ['mech1', 'a_sup'], 'npc']])
        held = [x[0] for x in r['events'] if x[1:] == ['task', 'mech1', 'lead_gauge', 'held']]
        done = [x[0] for x in r['events'] if x[1:] == ['task', 'a_sup', 'join_gauge', 'done']]
        self.assertEqual(len(held), 1)
        self.assertEqual(done, [held[0] + 1 + 150])
        self.assertIsNone(r['states'][-1]['discussions']['gauge_cal']['agreed'])

    def test_joiner_pause_restarts_its_count(self):
        """A joiner's count of its lead's pause is for minutes in a row: the joiner's own task paused (pre-empted, held)
        drops it, so a resumed joiner counts again from when it next sees the lead paused (adversarial review)."""
        r = self.st['runs'][6]
        held = [x[0] for x in r['events'] if x[1:] == ['task', 'mech1', 'lead_gauge', 'held']][0]
        F = G.discuss_paused_files()
        F['scenarios/s1.json']['staff']['absent'] = ['mech2']        # (as the vectors' run)
        e = P.Engine(G.check(F), 's1')
        while e.step_no < held + 10:
            e.step()
        sr = e.staff
        sup = sr.people[sr.st.person_ix['a_sup']]
        self.assertIn('pz', sup.cur['st'])
        sr.pause(sup)
        self.assertEqual([q['task'] for q in sup.queue], ['join_gauge'])
        self.assertNotIn('pz', sup.queue[0]['st'])

    def test_joiner_kept_by_a_waiting_lead(self):
        """A called joiner whose own 15 minutes end while the lead waits in the room for the others waits on and takes
        part when the lead's 15 minutes end (the first train's joiners come before their lead)."""
        r = self.st['runs'][7]
        ev = self.evs(7)
        self.assertEqual(ev[0][1:], ['discussion', 'pump_run', 'start', 'a_sup', ['a_sup', None, 'a_elec'], 'npc'])
        came = [x[0] for x in r['events'] if x[1:] == ['task', 'a_elec', 'join_pump_e', 'start']][0]
        self.assertGreater(ev[0][0] - came, 150 + 62)          # past their own 15 minutes in the office
        self.assertIn([ev[0][0] + 100, 'task', 'a_elec', 'join_pump_e', 'done'], r['events'])


if __name__ == '__main__':
    unittest.main()


class WoVectors(PartVectors, unittest.TestCase):
    """Milestone WM1 (REALISM.md §2.20): workorders.json, the wo input's actions and reasons, in progress by itself,
    an NPC's write-up, the record and the run's history, wo steps and reactions."""
    part, rejects = 'wo', 'REJECTS_WO'

    def evs(self, k, kinds=('wo',)):
        return [x for x in self.st['runs'][k]['events'] if x[1] in kinds]

    def test_reasons_in_order(self):
        """authority, state, permit, data: every one that applies, in that order; unknown changes nothing."""
        why = [(x[0], x[2], x[3], x[5], x[6]) for x in self.evs(0)]
        self.assertIn((5, 'wo_valve', 'complete', 'refused', ['authority', 'state', 'permit']), why)
        self.assertIn((3, 'wo_fan', 'notify', 'unknown', []), why)
        self.assertIn((3, 'wo_valve', 'plan', 'unknown', []), why)       # (data not a list)
        self.assertIn((4, 'wo_valve', 'plan', 'refused', ['data']), why)
        self.assertIn((10, 'wo_valve', 'cancel', 'refused', ['permit']), why)
        self.assertIn((23, 'wo_gauge', 'notify', 'refused', ['authority', 'state']),
                      [(x[0], x[2], x[3], x[5], x[6]) for x in self.evs(1)])

    def test_numbers_and_history(self):
        """A work notified again after it was cancelled gets a new number; the cancelled order is in the history."""
        end = self.st['runs'][0]['states'][-1]
        self.assertEqual([h['no'] for h in end['wo_history']], ['WO-0001'])
        self.assertEqual(end['wo_history'][0]['work'], 'wo_valve')
        self.assertEqual(end['wo']['wo_valve']['no'], 'WO-0002')
        self.assertEqual(end['wo']['wo_pump']['no'], 'WO-0003')
        self.assertEqual(end['wo_history'][0]['priority'], 2)       # (2.0 given: kept as a whole number)

    def test_in_progress_by_itself_at_accept(self):
        ev = self.st['runs'][1]['events']
        acc = next(x[0] for x in ev if x[1] == 'permit' and x[3] == 'accept' and x[5] == 'done')
        self.assertIn([acc, 'wo', 'wo_gauge', 'auto', None, 'done', [4]], ev)

    def test_npc_write_up_and_close(self):
        """An NPC's done writes the order up with the work's codes in the same step; the supervisor closes it once
        the permit is closed; the round's notification uses the work's first finds."""
        ev = self.evs(2)
        done = next(x[0] for x in self.st['runs'][2]['events'] if x[1] == 'permit' and x[3] == 'done')
        self.assertIn([done, 'wo', 'wo_pump', 'complete', 'mech1', 'done', []], ev)
        closed = next(x[0] for x in self.st['runs'][2]['events'] if x[1] == 'permit' and x[3] == 'close')
        wo_close = next(x for x in ev if x[3] == 'close')
        self.assertGreaterEqual(wo_close[0], closed)
        end = self.st['runs'][2]['states'][-1]
        self.assertEqual(end['wo_history'][0]['codes'], ['vibration', 'wear', 'replace'])
        self.assertEqual(end['wo']['wo_gauge']['mode'], 'reading')
        self.assertEqual(end['wo']['wo_gauge']['state'], 3)

    def test_trainee_step_early_and_taken(self):
        ev = self.st['runs'][3]['events']
        self.assertTrue(any(x[1] == 'early' and x[5] == 'wo' for x in ev))
        self.assertTrue(any(x[1] == 'task' and x[3] == 'plan_wo' and x[4] == 'done' for x in ev))

    def test_run_history_capped(self):
        """The run's history keeps the newest 4,096 records (§2.21): the oldest drops, numbers go on."""
        from ref.plant3d_wo import LIMITS
        end = self.st['runs'][5]['states'][-1]
        h = end['wo_history']
        self.assertEqual(LIMITS['run_history'], 4096)
        self.assertEqual(len(h), 4096)
        self.assertEqual((h[0]['no'], h[-1]['no']), ('WO-0002', 'WO-4097'))
        self.assertEqual(end['wo']['wo_pump']['no'], 'WO-4098')

    def test_run_history_cap_in_engine(self):
        """One more close past the limit drops exactly the oldest record."""
        from ref import plant3d_wo as WO
        e = P.Engine(G.check(G._wo_bare(G.wo_files())), 's1')
        for _ in range(WO.LIMITS['run_history'] + 1):
            e.work_order('wo_valve', 'notify', None, [None])
            e.work_order('wo_valve', 'cancel', None, [])
        e.step()
        self.assertEqual(len(e.wo_history), WO.LIMITS['run_history'])
        self.assertEqual(e.wo_history[0][0], 'WO-0002')

    def test_offered_again_when_a_supervisor_comes_on(self):
        """An order notified while no shift supervisor is on duty is planned once one comes on (§2.21); one cancelled
        meanwhile is not offered again."""
        r = self.st['runs'][6]
        ev = r['events']
        on = next(x[0] for x in ev if x[1] == 'duty' and x[2] == 'a_sup' and x[3] == 'on')
        self.assertTrue(any(x[:3] == [10, 'wo', 'wo_pump'] for x in ev))
        self.assertIn([10, 'task', None, 'plan_wo', 'unassigned'], ev)
        plan = next(x for x in ev if x[1] == 'wo' and x[2] == 'wo_pump' and x[3] == 'plan')
        self.assertGreater(plan[0], on)
        self.assertEqual((plan[4], plan[5]), ('a_sup', 'done'))
        self.assertFalse(any(x[1] == 'wo' and x[2] == 'wo_valve' and x[3] == 'plan' for x in ev))
        self.assertEqual(r['states'][-1]['wo']['wo_pump']['state'], 3)

    def test_no_file_no_values(self):
        """A plant without workorders.json keeps no work order values and refuses nothing new."""
        F = G.staff_files()
        e = P.Engine(G.check(F), 's1')
        self.assertFalse(any(n.endswith('_wo') for n in e.names))
        e.work_order('wo_pump', 'notify', None, [None])
        e.step()
        self.assertIn([1, 'wo', 'wo_pump', 'notify', None, 'unknown', []], e.events)
