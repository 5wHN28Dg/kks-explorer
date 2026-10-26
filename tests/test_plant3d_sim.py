"""Walkdown Plant's behaviour engine in GDScript (apps/plant3d/sim) against the reference (ref/plant3d.py), run with
the pinned Godot (decision 0041) headless:
- every vector of ref/vectors/plant3d-v1.json and plant3d-v2.json (format 2: permits, isolations, the hold node)
  replays through it (apps/plant3d/sim/tests/run_vectors.gd): events
  exactly, snapshots to the file's precision, the cold start run as a trainee by its procedure, every fork, every link;
- bit for bit: the SHA-256 of every value at every step of every run (the unit runs, the 66,436-step cold start and
  its 70 forks) equals the reference's; a difference is reported at its first step and value;
- its strict JSON reader reads every number as Python's float() does (the content's, the vectors', and hard cases:
  halfway points, subnormals, the largest double, long decimals) and passes the strict JSON vectors (v2-json.json).
Needs the Godot editor (KKS_GODOT, else the path tools/plant3d/bench/fetch_godot.sh installs it to); skipped without,
unless KKS_REQUIRE_GODOT=1 (CI), where a missing Godot fails.
  .venv/bin/python -m unittest tests.test_plant3d_sim"""
import copy, hashlib, json, os, random, struct, subprocess, sys, tempfile, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, REPO)
from ref import plant3d as P  # noqa: E402

SIM = os.path.join(REPO, 'apps', 'plant3d', 'sim')
VECTORS = os.path.join(REPO, 'ref', 'vectors', 'plant3d-v1.json')
VECTORS2 = os.path.join(REPO, 'ref', 'vectors', 'plant3d-v2.json')
DATA = os.path.join(REPO, 'data', 'plant3d')
GODOT = os.environ.get('KKS_GODOT') or os.path.expanduser('~/.local/kksdev/godot/Godot_v4.7.2-stable_linux.x86_64')
HAVE = os.access(GODOT, os.X_OK)
REQUIRED = os.environ.get('KKS_REQUIRE_GODOT') == '1'
CHUNK = 1000        # steps per digest, as run_vectors.gd


def godot(script, *args, timeout=1800):
    return subprocess.run([GODOT, '--headless', '--script', os.path.join(SIM, 'tests', script), '--', *args],
                          capture_output=True, text=True, timeout=timeout, cwd=REPO)


def apply(e, item):
    kind = item[1]
    if kind == 'op':
        e.op(*item[2:6])
    elif kind == 'ack':
        e.ack(item[2])
    elif kind == 'shelve':
        e.shelve(item[2], item[3])
    elif kind == 'unshelve':
        e.unshelve(item[2])
    elif kind == 'repair' and len(item) > 3:
        e.repair_under(item[2], item[3], item[4])       # the trainee's, under a permit (PLANT3D §15.5)
    elif kind == 'repair':
        e.repair(item[2])
    elif kind == 'permit':
        e.permit(item[2], item[3], item[4])
    elif kind in ('lock', 'unlock'):
        getattr(e, kind)(item[2], item[3], item[4])
    elif kind == 'remove_lock':
        e.remove_lock(item[2], item[3], item[4], item[5], *item[6:7], named=len(item) > 6)
    elif kind == 'fault':
        e.fault(item[2])
    else:
        raise ValueError(f'an input this harness does not replay: {item}')


class Hasher:
    """The reference's side of run_vectors.gd's digests: SHA-256 over every value's IEEE double (little-endian, slot
    order) after every step, cut every 1000 steps."""

    def __init__(self, start):
        self.start, self.chunks, self.h, self.last, self.vals = start, [], hashlib.sha256(), None, {}
        self.states = []        # the state digest (PLANT3D.md §17.14) of every 50th step, as run_vectors.gd's `state`

    def add(self, e, keep=None):
        if e.step_no % 50 == 0:
            self.states.append(e.digest())
        b = struct.pack(f'<{len(e.names)}d', *e.cur)
        if keep and keep[0] <= e.step_no <= keep[1]:
            self.vals[e.step_no] = b
        self.h.update(b)
        self.last = e.step_no
        if e.step_no - self.start + 1 == CHUNK:
            self.cut()

    def cut(self):
        self.chunks.append(self.h.hexdigest())
        self.start = self.last + 1
        self.h = hashlib.sha256()

    def end(self):
        if self.last >= self.start:
            self.cut()


def steps_bundle(valid_files, s):
    files = {rel: t.encode() for rel, t in valid_files.items()}
    files['model/a1.json'] = json.dumps(s['model']).encode()
    files['scenarios/s1.json'] = json.dumps(s['scenario']).encode()
    del files['procedures/p1.json']
    del files['screens.json']
    return P.check_files(files)


def steps_runs(valid_files, steps, keep=None, prefix=''):
    """The unit runs (the vectors' `steps`) on the reference, as reference_runs."""
    out = {}
    for i, s in enumerate(steps):
        run = f'{prefix}steps/{i}'
        kk = (keep[1], keep[2]) if keep and keep[0] == run else None
        e = P.Engine(steps_bundle(valid_files, s), 's1')
        h = Hasher(0)
        h.add(e, kk)
        j = 0
        while e.step_no < len(s['states']) - 1:
            while j < len(s['inputs']) and s['inputs'][j][0] == e.step_no + 1:
                apply(e, s['inputs'][j])
                j += 1
            e.step()
            h.add(e, kk)
        assert j == len(s['inputs']), f'{run}: inputs after the end'
        h.end()
        out[run] = (0, h.chunks, e.names, h.vals, h.states)
    return out


# the water treatment plant's runs in plant3d-v2.json (W2: its start from cold; W3: cleaning in place, regeneration)
WTP_RUNS = ('wtp', 'wtp_cip', 'wtp_regen')


def reference_runs(V, keep=None, V2=None):
    """Every run of run_vectors.gd on the reference: {run: (first step hashed, chunk digests, names, kept values)}.
    keep = (run, from, to) keeps that run's values at those steps."""
    out = {}

    def k(run):
        return (keep[1], keep[2]) if keep and keep[0] == run else None

    for run, r in steps_runs(V['valid'][0]['files'], V['steps'], keep).items():
        out[run] = r
    b = P.check_dir(DATA)
    for name in ('train', 'hot'):
        train_runs(b, name, V[name], out, k)
    if V2 is not None:
        for run, r in steps_runs(V2['valid'][0]['files'], V2['steps'], keep, 'v2/').items():
            out[run] = r
        if 'train' in V2:
            train_runs(b, 'v2/train', V2['train'], out, k, 'v2/')
        for run in WTP_RUNS:
            if run in V2:
                train_runs(b, f'v2/{run}', V2[run], out, k, 'v2/')
        for i, r in enumerate(V2.get('staff', {}).get('runs', [])):
            out[f'v2/staff/{i}'] = staff_run(V2['staff']['files'], r, k(f'v2/staff/{i}'))
        if 'day' in V2:
            day_runs(b, V2['day'], out, k)
    return out


def day_runs(b, d, out, k):
    """The first train's day and its runs with a trainee (the vectors' `day`), as reference_runs."""
    from ref import make_plant3d_vectors as G
    for name, inputs, until, sid, ses in [('v2/day', [], d['until'], d['scenario'], False)] + [
            ('v2/day/' + f['id'], f['inputs'], f['until'], f.get('scenario', d['scenario']), f.get('session', False))
            for f in d['forks']]:
        e = P.Engine(b, sid, ses)
        h = Hasher(0)
        h.add(e, k(name))
        inputs = sorted(inputs, key=lambda x: x[0])
        j = 0
        while e.step_no < until:
            while j < len(inputs) and inputs[j][0] == e.step_no + 1:
                G.apply_staff(e, inputs[j])
                j += 1
            e.step()
            h.add(e, k(name))
        h.end()
        out[name] = (0, h.chunks, e.names, h.vals, h.states)


def staff_run(files, r, kk):
    """A staff run (the vectors' `staff.runs`) on the reference, as reference_runs."""
    from ref import make_plant3d_vectors as G
    F = {rel: t.encode() for rel, t in files.items()}
    F['scenarios/s1.json'] = json.dumps(r['scenario']).encode()
    if r['staff'] is not None:
        F['staff.json'] = json.dumps(r['staff']).encode()
    for rel, v in r.get('files', {}).items():
        F[rel] = json.dumps(v).encode()
    e = P.Engine(P.check_files(F), 's1', r.get('session', False))
    h = Hasher(0)
    h.add(e, kk)
    inputs = sorted(r['inputs'], key=lambda x: x[0])
    j = 0
    while e.step_no < r['until']:
        while j < len(inputs) and inputs[j][0] == e.step_no + 1:
            G.apply_staff(e, inputs[j])
            j += 1
        e.step()
        h.add(e, kk)
    h.end()
    return (0, h.chunks, e.names, h.vals, h.states)


def train_runs(b, name, t, out, k, prefix=''):
    """A start run by its procedure (the vectors' `train` or `hot`) and its forks, into out."""
    e = P.Engine(b, t['scenario'])
    base_steps = {f['base_step'] for f in t['forks']}
    bases = {}
    inputs = sorted(t['inputs'], key=lambda x: x[0])
    h = Hasher(0)
    h.add(e, k(name))
    j = 0
    while e.step_no < t['until']:
        if e.step_no in base_steps:
            bases[e.step_no] = e.clone()
        while j < len(inputs) and inputs[j][0] == e.step_no + 1:
            apply(e, inputs[j])
            j += 1
        e.step()
        h.add(e, k(name))
    assert j == len(inputs), f'{name}: inputs after the end'
    h.end()
    if t['until'] in base_steps:
        bases[t['until']] = e.clone()
    out[name] = (0, h.chunks, e.names, h.vals, h.states)
    for f in t['forks']:
        x = bases[f['base_step']].clone()
        fin = sorted(f['inputs'], key=lambda y: y[0])
        h = Hasher(x.step_no + 1)
        j = 0
        while x.step_no < f['until']:
            while j < len(fin) and fin[j][0] == x.step_no + 1:
                apply(x, fin[j])
                j += 1
            x.step()
            h.add(x, k(prefix + f['id']))
        h.end()
        out[prefix + f['id']] = (f['base_step'] + 1, h.chunks, x.names, h.vals, h.states)


def number_corpus():
    """Number tokens with the bits Python's float() (or int()) gives them: every number in the content and the
    vectors, hard cases, and random doubles and decimals."""
    toks = set()

    def keep(s):
        toks.add(s)
        return 0

    paths = [VECTORS, VECTORS2] + [os.path.join(r, f) for r, _, fs in os.walk(DATA) for f in fs if f.endswith('.json')]
    for p in paths:
        with open(p, encoding='utf-8') as f:
            json.load(f, parse_float=keep, parse_int=keep)
    toks |= {'5e-324', '4.9406564584124654e-324', '2.4703282292062328e-324', '2.4703282292062327e-324',
             '2.4703282292062329e-324', '2.2250738585072011e-308', '2.2250738585072012e-308',
             '2.2250738585072014e-308', '1.7976931348623157e308', '1.7976931348623158e308', '1.7976931348623159e308',
             '1e309', '1e-400', '9007199254740993', '9007199254740993.0', '9223372036854775807',
             '9223372036854775808', '-9223372036854775808', '123456789012345678901234567890', '1e23', '8.5e-1',
             '3.14159265358979323846264338327950288', '0.30000000000000004', '-0.0', '0e999999999999',
             '1e-999999999999', '1.00000000000000011102230246251565404236316680908203125',
             '1.00000000000000011102230246251565404236316680908203124',
             '1.00000000000000011102230246251565404236316680908203126', '0.016666666666666666', '999999.9'}
    with open(os.path.join(REPO, 'ref', 'vectors', 'v2-json.json'), encoding='utf-8') as f:
        for x in json.load(f)['accept']:
            if x['value']['t'] in ('int', 'big', 'float'):
                toks.add(bytes.fromhex(x['hex']).decode().strip())
    rnd = random.Random(20261016)
    for _ in range(4000):
        x = struct.unpack('<d', struct.pack('<Q', rnd.getrandbits(64)))[0]
        if x == x and abs(x) != float('inf'):
            toks.add(repr(x))
    for _ in range(2000):
        toks.add(f'{rnd.randint(1, 10 ** rnd.randint(1, 30))}e{rnd.randint(-340, 300)}')
    for _ in range(1000):
        toks.add('%.*f' % (rnd.randint(0, 25), rnd.uniform(0, 1000)))
    lines = []
    for t in sorted(toks):
        is_int = not any(c in t for c in '.eE') and abs(int(t)) <= 2 ** 63 - 1
        v = float(int(t)) if is_int else float(t)
        lines.append(f'{t} {struct.pack(">d", v).hex()}')
    return lines


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptEngine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not HAVE:
            raise AssertionError(f'KKS_REQUIRE_GODOT=1 but there is no Godot at {GODOT}')
        with open(VECTORS, encoding='utf-8') as f:
            cls.V = json.load(f)
        with open(VECTORS2, encoding='utf-8') as f:
            cls.V2 = json.load(f)
        cls.tmp = tempfile.TemporaryDirectory()
        cls.digest_path = os.path.join(cls.tmp.name, 'digests.json')
        cls.result = godot('run_vectors.gd', f'--digests={cls.digest_path}')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_every_vector_replays(self):
        no_errors(self, self.result)
        out = self.result.stdout
        self.assertEqual(self.result.returncode, 0, out[-6000:] + self.result.stderr[-3000:])
        self.assertNotIn('FAIL', out)
        n = 1 + len(self.V['steps']) + len(self.V['links']) + 2 * (1 + 1) + len(self.V['train']['forks']) + \
            len(self.V['hot']['forks']) + 1 + len(self.V2['steps']) + len(self.V2.get('train', {}).get('forks', [])) + \
            (1 + len(self.V2['staff']['runs']) if 'staff' in self.V2 else 0) + \
            (1 + len(self.V2['day']['forks']) if 'day' in self.V2 else 0) + \
            sum(2 + len(self.V2[r]['forks']) for r in WTP_RUNS if r in self.V2)
        self.assertIn(f'VECTORS passed={n} failed=0', out)

    def test_every_value_bit_for_bit(self):
        with open(self.digest_path, encoding='utf-8') as f:
            got = json.load(f)
        ref = reference_runs(self.V, V2=self.V2)
        self.assertEqual(sorted(got), sorted(ref))
        for run, (start, chunks, names, _, states) in ref.items():
            g = got[run]
            self.assertEqual(g['from'], start, run)
            self.assertEqual(g['state'], states, f'{run}: the state digests (PLANT3D.md §17.14)')
            bad = next((i for i, (a, b) in enumerate(zip(g['chunks'], chunks)) if a != b), None)
            if bad is None and len(g['chunks']) == len(chunks):
                continue
            if bad is None:
                self.fail(f'{run}: {len(g["chunks"])} digest chunks, the reference {len(chunks)}')
            lo = start + bad * CHUNK
            self.fail(self.first_difference(run, lo, lo + CHUNK - 1, names))

    def first_difference(self, run, lo, hi, names):
        """The first step and value of a run where the two engines differ (both dump the chunk's values)."""
        part = 'v2' if run.startswith('v2/') else 'steps' if run.startswith('steps/') else 'train'
        r = godot('run_vectors.gd', f'--only={part}', f'--dump={run}:{lo}:{hi}')
        dumped = {int(line.split()[1]): bytes.fromhex(line.split()[2])
                  for line in r.stdout.splitlines() if line.startswith('DUMP ')}
        ref = reference_runs(self.V, keep=(run, lo, hi), V2=self.V2)[run][3]
        for step in sorted(ref):
            a, b = dumped.get(step), ref[step]
            if a != b:
                if a is None:
                    return f'{run}: no values dumped at step {step}'
                av = struct.unpack(f'<{len(names)}d', a)
                bv = struct.unpack(f'<{len(names)}d', b)
                i = next(i for i in range(len(names)) if struct.pack('<d', av[i]) != struct.pack('<d', bv[i]))
                return (f'{run}: first difference at step {step}, value {names[i]}: GDScript {av[i]!r} '
                        f'({struct.pack(">d", av[i]).hex()}), the reference {bv[i]!r} ({struct.pack(">d", bv[i]).hex()})')
        return f'{run}: the digests of steps {lo}–{hi} differ but no dumped value does'

    def test_numbers_read_as_python_reads_them(self):
        with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as f:
            f.write('\n'.join(number_corpus()) + '\n')
            path = f.name
        try:
            r = godot('check_numbers.gd', path, timeout=600)
        finally:
            os.unlink(path)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:] + r.stderr[-2000:])
        self.assertRegex(r.stdout, r'NUMBERS checked=\d+ bad=0')

    def test_strict_json_vectors(self):
        """v2-json.json, and strings Godot's own string functions would change: a U+FEFF at a string's start (which
        get_string_from_utf8 drops as a byte-order mark) or after an escape. An escaped U+0000 is refused: a Godot
        String can't hold it (ref/sjson.py accepts it; no content needs it)."""
        from ref import sjson
        accept = ['"\ufeffx"', '"a\ufeff"', '"\\n\ufeff"', '{"\ufeff":1,"a":2}', '"\\ufeff\ufeff"',
                  '["\ufeff", "\\u00e9\ufeffz"]', '"\ufeff\ufeffx"', '"\\n\ufeff\ufeff"', '{"a":1,"\ufeffa":2}',
                  '{"":1,"\ufeff":2}',
                  '"\ufffe\uffff"', '"\\ufffe\\uffff"']
        extra = {'accept': [], 'reject': [{'why': 'an escaped NUL', 'hex': b'"a\\u0000"'.hex()},
                                          {'why': 'an escaped NUL in a key', 'hex': b'{"a\\u0000":1}'.hex()}]}
        for t in accept:
            b = t.encode()
            extra['accept'].append({'why': repr(t), 'hex': b.hex(), 'value': sjson.typed(sjson.loads(b))})
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
            # ASCII only: the expected strings then arrive as \u escapes, built apart from the raw bytes under test
            json.dump(extra, f, ensure_ascii=True)
            path = f.name
        try:
            r = godot('check_json.gd', os.path.join(REPO, 'ref', 'vectors', 'v2-json.json'), path, timeout=300)
        finally:
            os.unlink(path)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:] + r.stderr[-2000:])
        self.assertRegex(r.stdout, r'JSON checked=\d+ bad=0')


def edge_steps():
    """Unit runs the vectors don't hold, made here on the reference (same form as the vectors' `steps`): edges of
    the arithmetic and of the inputs that the app's engine must also get right."""
    A, B = '10LAC10AP001', '10LAB10AA001'
    long_delay = {'values': [['u', {'state': 1}], ['d', {'delay': 'u', 'on': 300000000, 'off': 0.1}],
                             ['d2', {'delay': 'u', 'on': 0, 'off': 300000000}]]}
    inputs = {'values': [['u', {'state': 0}], ['k', {'state': 0}], ['on', {'cmp': ['u', '>=', 1]}],
                         ['neg', {'product': ['u', -0.0]}], ['mn', {'min': ['neg', 0]}], ['mx', {'max': [0, 'neg']}],
                         ['sm', {'sum': ['neg']}], ['sel', {'select': 'neg', 'cases': ['mn', 'mx']}]],
              'ops': [{'kks': A, 'do': 'set', 'input': 'u', 'range': [0, 2], 'where': ['screen']},
                      {'kks': B, 'do': 'start', 'set': {'k': 1}, 'where': ['local']}],
              'alarms': [{'id': 'al', 'kks': A, 'text': 'U high', 'when': 'on', 'priority': 1, 'where': A}]}
    table = [[x * 1.0, (x * 0.37) % 7.1] for x in range(1024)]
    big = {'values': [['u', {'state': 0}], ['r', {'ramp': 'u', 'rate': 1000}],
                      ['lin', {'of': 'r', 'table': table}], ['stp', {'of': 'r', 'table': table, 'step': True}],
                      ['h', {'cmp': ['r', '>=', 500]}],
                      ['sm', {'sum': ['lin', 'stp', 0.1] * 13 + ['r']}], ['pr', {'product': ['h', 1.01] * 20}],
                      ['mn', {'min': ['lin', 'stp', 3] * 13 + ['r']}], ['mx', {'max': ['stp', 'lin', -1] * 13 + ['r']}],
                      ['an', {'and': ['h', 1] * 20}], ['orr', {'or': [0, 'h'] * 20}],
                      ['one', {'of': 'r', 'table': [[5, 2]]}], ['one_s', {'of': 'r', 'table': [[5, 2]], 'step': True}]],
           'ops': [{'kks': A, 'do': 'set', 'input': 'u', 'range': [0, 2000], 'where': ['screen']}]}
    return [
        ('delays longer than 2^31 steps never fire (and an off delay that long never drops)', long_delay,
         {'ambient_t': 20}, [], [], 4),
        ("nodes past the generated program's limits (engine.gd _FAST_TERMS, _FAST_ROWS): 1024-row tables, "
         'linear and steps, one-row tables, and lists of 40 refs', big, {'ambient_t': 20}, [], [[1, 'op', A, 'set', 1000, None],
                                                                                [12, 'op', A, 'set', 0, None]], 30),
        ('shelving times at the half step, a bool as a set value, refusals, unknown ops, -0.0 through min, max, '
         'sum and select', inputs, {'ambient_t': 20}, [], [
            [1, 'op', A, 'set', 1, None], [2, 'shelve', 'al', 0.05], [3, 'shelve', 'al', 0.15],
            [3, 'op', A, 'set', True, None], [4, 'op', A, 'set', 3, None], [4, 'op', A, 'set', None, None],
            [4, 'op', A, 'start', None, 't9'], [4, 'op', B, 'start', None, None], [4, 'op', B, 'start', 1, None],
            [5, 'shelve', 'al', 5], [5, 'unshelve', 'al'], [6, 'shelve', 'al', 0.35], [6, 'ack', 'al'],
            [7, 'shelve', 'al', 1e-9], [7, 'shelve', 'al', 999999.95], [8, 'unshelve', 'al'], [8, 'ack', 'al'],
            [9, 'op', A, 'set', 0, None], [9, 'op', A, 'set', 2.0, None], [10, 'fault', 'none']], 14),
    ]


def build_edge_vectors(V):
    """A vector file of edge_steps() in the vectors' form (valid plant, steps; no links, no train)."""
    steps = []
    for why, model, init, faults, inputs, n in edge_steps():
        scen = {'format': 'walkdown-plant-scenario', 'version': 1, 'id': 's1', 'title': 'Edges', 'init': init,
                'faults': faults}
        s = {'why': why, 'model': dict({'format': 'walkdown-plant-model', 'version': 1, 'area': 'a1'}, **model),
             'scenario': scen, 'inputs': inputs}
        e = P.Engine(steps_bundle(V['valid'][0]['files'], s), 's1')
        states = [e.snapshot()]
        i = 0
        while e.step_no < n:
            while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                apply(e, inputs[i])
                i += 1
            e.step()
            states.append(e.snapshot())
        s.update(states=states, events=e.events)
        steps.append(s)
    return {'valid': V['valid'], 'steps': steps, 'links': [], 'train': {'forks': []}}


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptEngineEdges(unittest.TestCase):
    """edge_steps() through the app's engine: the snapshots, the events and every value's bits."""

    def test_edges(self):
        with open(VECTORS, encoding='utf-8') as f:
            V = json.load(f)
        E = build_edge_vectors(V)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'edges.json')
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(E, f)
            dig = os.path.join(d, 'digests.json')
            r = godot('run_vectors.gd', f'--vectors={path}', '--only=steps', f'--digests={dig}', timeout=300)
            no_errors(self, r)
            self.assertEqual(r.returncode, 0, r.stdout[-4000:])
            self.assertIn(f'VECTORS passed={len(E["steps"])} failed=0', r.stdout)
            self.assertIn(f'PROGRAM straight-line={len(E["steps"])} interpreter=0', r.stdout)
            with open(dig, encoding='utf-8') as f:
                got = json.load(f)
        for run, (start, chunks, _, _) in steps_runs(V['valid'][0]['files'], E['steps']).items():
            self.assertEqual(got[run]['chunks'], chunks, run)


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptStaffEdges(unittest.TestCase):
    """Places held in cases the staff vectors don't reach, as tests/test_plant3d_staff.py checks the reference."""

    def test_staff_edges(self):
        r = godot('check_staff_edges.gd', os.path.join(REPO, 'ref', 'vectors', 'plant3d-v2.json'), timeout=300)
        no_errors(self, r)
        self.assertIn('STAFF_EDGES bad=0', r.stdout, r.stdout[-4000:])
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptEngineInterpreter(unittest.TestCase):
    """The engine steps with a straight-line GDScript program generated from the model (engine.gd _gen_fast), which
    every other test here runs. Its interpreter (engine.gd _run: step 0, faults' `when` nodes, and every step when the
    program could not be compiled) must give the same bits: the unit runs (formats 1 and 2) and the edge runs, stepped by
    it alone."""

    def test_unit_and_edge_runs(self):
        with open(VECTORS, encoding='utf-8') as f:
            V = json.load(f)
        E = build_edge_vectors(V)
        with tempfile.TemporaryDirectory() as d:
            for name, vec in (('steps', V), ('edges', E)):
                path = os.path.join(d, name + '.json')
                with open(path, 'w', encoding='utf-8') as f:
                    json.dump(vec, f)
                dig = os.path.join(d, name + '-digests.json')
                r = godot('run_vectors.gd', f'--vectors={path}', '--only=steps', f'--digests={dig}', '--interpreter=1',
                          timeout=600)
                no_errors(self, r)
                self.assertEqual(r.returncode, 0, r.stdout[-4000:])
                self.assertIn(f'VECTORS passed={len(vec["steps"])} failed=0', r.stdout)
                self.assertIn(f'PROGRAM straight-line=0 interpreter={len(vec["steps"])}', r.stdout)
                with open(dig, encoding='utf-8') as f:
                    got = json.load(f)
                for run, (start, chunks, _, _) in steps_runs(V['valid'][0]['files'], vec['steps']).items():
                    self.assertEqual(got[run]['chunks'], chunks, f'{name} {run}')
            # format 2's unit runs (permits, isolations, the hold node), without its runs of the first train's content
            # (train, water plant, the staff's day: they need the content's model, which --only=v2 doesn't load) nor
            # the staff's runs (GdscriptEngine replays them)
            with open(VECTORS2, encoding='utf-8') as f:
                V2 = json.load(f)
            V2 = {k: v for k, v in V2.items() if k not in ('train', 'day', 'staff') and k not in WTP_RUNS}
            path = os.path.join(d, 'v2.json')
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(V2, f)
            dig = os.path.join(d, 'v2-digests.json')
            r = godot('run_vectors.gd', '--only=v2', f'--vectors2={path}', f'--digests={dig}', '--interpreter=1',
                      timeout=600)
            no_errors(self, r)
            self.assertEqual(r.returncode, 0, r.stdout[-4000:])
            self.assertIn(f'VECTORS passed={1 + len(V2["steps"])} failed=0', r.stdout)
            self.assertIn(f'PROGRAM straight-line=0 interpreter={len(V2["steps"])}', r.stdout)
            with open(dig, encoding='utf-8') as f:
                got = json.load(f)
            for run, (start, chunks, _, _) in steps_runs(V2['valid'][0]['files'], V2['steps'], prefix='v2/').items():
                self.assertEqual(got[run]['chunks'], chunks, run)


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptEngineFastOutsideReference(unittest.TestCase):
    """Where the reference has no result (it raises), the straight-line program must still do what the interpreter
    does (apps/plant3d/sim/tests/check_fast.gd), and a program that fails to compile is tried once per model."""

    def files(self, d, model):
        with open(VECTORS, encoding='utf-8') as f:
            V = json.load(f)
        files = dict(V['valid'][0]['files'])
        files['model/a1.json'] = json.dumps(dict({'format': 'walkdown-plant-model', 'version': 1, 'area': 'a1'},
                                                 **model))
        files['scenarios/s1.json'] = json.dumps({'format': 'walkdown-plant-scenario', 'version': 1, 'id': 's1',
                                                 'title': 'Edges', 'init': {'ambient_t': 20}, 'faults': []})
        del files['procedures/p1.json']
        del files['screens.json']
        path = os.path.join(d, 'files.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(files, f)
        return path

    def test_one_row_table_given_nan(self):
        """A one-row linear table fed NaN: _table reads the next node's arguments as its second row and gives NaN
        (the reference raises IndexError); an unrolled `if u < x0 / elif u >= x0` would keep the last step's value.
        Here the input is -inf for 3 steps, then NaN (inf * 0)."""
        model = {'values': [['k', {'state': 1}], ['u', {'state': 100000000}], ['inf', {'product': ['u'] * 64}],
                            ['d', {'delay': 'k', 'on': 0.3, 'off': 0.1}], ['z', {'diff': ['d', 1]}],
                            ['x', {'product': ['inf', 'z']}], ['one', {'of': 'x', 'table': [[5, 2]]}],
                            ['after', {'of': 'k', 'table': [[1, 3], [2, 4]]}]]}
        with tempfile.TemporaryDirectory() as d:
            r = godot('check_fast.gd', f'--files={self.files(d, model)}', '--steps=8', timeout=300)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])
        self.assertIn('FAST steps=8 differ=0', r.stdout)

    def test_failed_compile_cached(self):
        with tempfile.TemporaryDirectory() as d:
            r = godot('check_fast.gd', f'--files={self.files(d, {"values": [["k", {"state": 1}]]})}', '--broken=1',
                      timeout=300)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])
        self.assertIn('BROKEN cached=true fast=<null>,<null>', r.stdout)


# The bench's gate: generous, so that a busy runner doesn't fail it (about 0.12 ms a step on the laptop with the
# straight-line program, 0.5 ms before it; CI's runner has been 1.5-2 times slower than the laptop). Losing the
# program itself is caught exactly by the PROGRAM line.
MAX_STEP_US = 750


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptEngineStepCost(unittest.TestCase):
    """The model's step on this machine (apps/plant3d/sim/tests/bench_step.gd, the whole plant over the cold start
    and at base load): printed for the record, and failed above MAX_STEP_US microseconds."""

    def test_step_cost(self):
        r = godot('bench_step.gd', '--base-steps=3000', f'--max-us={MAX_STEP_US}', timeout=900)
        print('\n' + '\n'.join(x for x in r.stdout.splitlines() if x.split(' ')[0] in ('LOAD', 'COMPILE', 'PROGRAM', 'STEP',
                                                                                  'BATCH', 'FF_CHECK', 'GATE')))
        no_errors(self, r)
        self.assertIn('PROGRAM straight-line', r.stdout)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:])
        self.assertIn('GATE ok', r.stdout)


def no_errors(case, r):
    """Godot carries on after a script error or push_error: any of them fails the test."""
    bad = [x for x in (r.stdout + r.stderr).splitlines() if 'SCRIPT ERROR' in x or x.startswith('ERROR:')]
    case.assertEqual(bad, [], (r.stdout + r.stderr)[-4000:])


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptEngineCatchesDivergence(unittest.TestCase):
    """The comparison is not vacuous: a vector file with one number, one event or one snapshot changed fails."""

    def run_changed(self, change):
        with open(VECTORS, encoding='utf-8') as f:
            V = json.load(f)
        V = copy.deepcopy(V)
        change(V)
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
            json.dump(V, f)
            path = f.name
        try:
            return godot('run_vectors.gd', f'--vectors={path}', '--only=steps', timeout=300)
        finally:
            os.unlink(path)

    def test_a_value_off_by_1e_6_fails(self):
        def change(V):
            V['steps'][0]['states'][5]['values']['lag'] += 1e-6
        r = self.run_changed(change)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('FAIL steps/0', r.stdout)
        self.assertIn('step 5.values.lag', r.stdout)

    def test_a_float_for_an_int_fails(self):
        def change(V):
            V['steps'][0]['states'][3]['step'] = 3.0       # Python writes 3.0 for a float: the types are compared
        r = self.run_changed(change)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('FAIL steps/0 (every node kind): step 3.step: 3 (int), the reference 3.0 (float)', r.stdout)

    def test_alarm_order_counts(self):
        def change(V):
            s = next(s for s in V['steps'][1]['states'] if len(s['alarms']) >= 2)
            s['alarms'] = dict(reversed(list(s['alarms'].items())))
        r = self.run_changed(change)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('FAIL steps/1', r.stdout)


if __name__ == '__main__':
    unittest.main()
