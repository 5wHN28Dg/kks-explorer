"""Walkdown Plant's realism base (docs/plant3d/REALISM.md §2.1, §2.7–§2.9, milestone RE1) on the reference:
- ref/vectors/plant3d-realism.json is what ref/make_plant3d_vectors.py makes, part by part;
- the streams: FNV-1a against its published values, a stream per purpose and item that no other item moves;
- the synthetic plant with clock values passes with its counts, each reject is caught with its code, its runs replay
  (every event, the snapshots, the state digests);
- the clock values: their values across midnight and in a jump's own step, and a person's draws unchanged by a world;
- a scenario without `world` keeps every slot and value as before (format 2's vectors stay byte for byte: their own
  tests, test_plant3d.Vectors2 and test_plant3d_staff, compare them with the generator's output)."""
import copy, json, os, sys, unittest

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


if __name__ == '__main__':
    unittest.main()
