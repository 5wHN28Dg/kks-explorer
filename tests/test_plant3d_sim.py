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
unless KKS_REQUIRE_GODOT=1 (CI), where a missing Godot fails. The reference's runs are made while Godot runs, side by
side in up to 4 processes (KKS_REF_JOBS=N for N; 1: one after the other).
  .venv/bin/python -m unittest tests.test_plant3d_sim"""
import copy, hashlib, json, os, random, re, struct, subprocess, sys, tempfile, time, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, REPO)
from ref import plant3d as P  # noqa: E402
from ref import make_plant3d_vectors as G  # noqa: E402

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
    elif kind in ('board', 'alight'):
        getattr(e, kind)(item[2], item[3])              # a lift's riders (PLANT3D §20.3)
    else:
        raise ValueError(f'an input this harness does not replay: {item}')


class Hasher:
    """The reference's side of run_vectors.gd's digests: SHA-256 over every value's IEEE double (little-endian, slot
    order) after every step, cut every 1000 steps."""

    def __init__(self, start):
        self.start, self.chunks, self.h, self.last, self.vals = start, [], hashlib.sha256(), None, {}
        self.states = []        # the state digest (PLANT3D.md §17.14) of every 50th step, as run_vectors.gd's `state`
        self.doubles = None     # a struct.Struct for the run's values, made at its first step

    def add(self, e, keep=None):
        if e.step_no % 50 == 0:
            self.states.append(e.digest())
        if self.doubles is None:
            self.doubles = struct.Struct(f'<{len(e.names)}d')
        b = self.doubles.pack(*e.cur)
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
    for rel, v in s.get('files', {}).items():       # (a lift's runs: the kit, the plant's key and area a2, §20.9)
        files[rel] = json.dumps(v).encode()
    return P.check_files(files)


def steps_runs(valid_files, steps, keep=None, prefix=''):
    """The unit runs (the vectors' `steps`) on the reference, as reference_runs."""
    out = {}
    for i, s in enumerate(steps):
        run = f'{prefix}steps/{i}'
        kk = (keep[1], keep[2]) if keep and keep[0] == run else None
        e = P.Engine(steps_bundle(valid_files, s), 's1', s.get('session', False))
        h = Hasher(0)
        h.add(e, kk)
        j = 0
        while e.step_no < len(s['states']) - 1:
            while j < len(s['inputs']) and s['inputs'][j][0] == e.step_no + 1:
                (G.apply_staff if e.session else apply)(e, s['inputs'][j])
                j += 1
            e.step()
            h.add(e, kk)
        assert j == len(s['inputs']), f'{run}: inputs after the end'
        h.end()
        out[run] = (0, h.chunks, e.names, h.vals, h.states)
    return out


# the water treatment plant's runs in plant3d-v2.json (W2: its start from cold; W3: cleaning in place, regeneration)
WTP_RUNS = ('wtp', 'wtp_cip', 'wtp_regen')


def reference_runs(V, keep=None, V2=None, jobs=1):
    """Every run of run_vectors.gd on the reference: {run: (first step hashed, chunk digests, names, kept values)}.
    keep = (run, from, to) keeps that run's values at those steps. jobs > 1 makes the runs side by side in that many
    processes (ref_tasks: each task's runs are made as they would be one after the other); the result is the same."""
    tasks = ref_tasks(V, V2)
    parts = G.side_by_side(lambda i: run_task(V, V2, keep, tasks[i][:2]), len(tasks), cost=lambda i: tasks[i][2],
                           procs=jobs)
    out = {}
    for part in parts:
        out.update(part)
    return out


def ref_tasks(V, V2):
    """reference_runs' work as tasks that can be made side by side, in the vectors' order: (kind, which, steps run).
    A start's forks are in its task (they start from its clones); the day's runs each start from step 0."""
    t = [('steps', 'v1', sum(len(s['states']) for s in V['steps']))]
    for name in ('train', 'hot'):
        t.append(('train', name, train_cost(V[name])))
    if V2 is not None:
        t.append(('steps', 'v2', sum(len(s['states']) for s in V2['steps'])))
        for name in ('train',) + WTP_RUNS:
            if name in V2:
                t.append(('train', 'v2/' + name, train_cost(V2[name])))
        if 'staff' in V2:
            t.append(('staff', None, sum(r['until'] for r in V2['staff']['runs'])))
        if 'day' in V2:
            t.append(('day', None, V2['day']['until']))
            t += [('day', i, f['until']) for i, f in enumerate(V2['day']['forks'])]
    return t


def train_cost(t):
    return t['until'] + sum(f['until'] - f['base_step'] for f in t['forks'])


_BUNDLE = []        # the content's bundle, checked once per process


def bundle():
    if not _BUNDLE:
        _BUNDLE.append(P.check_dir(DATA))
    return _BUNDLE[0]


def run_task(V, V2, keep, task):
    """One of ref_tasks' tasks on the reference: {run: as reference_runs}."""
    kind, which = task
    out = {}

    def k(run):
        return (keep[1], keep[2]) if keep and keep[0] == run else None

    if kind == 'steps':
        if which == 'v1':
            out.update(steps_runs(V['valid'][0]['files'], V['steps'], keep))
        else:
            out.update(steps_runs(V2['valid'][0]['files'], V2['steps'], keep, 'v2/'))
    elif kind == 'train':
        if which.startswith('v2/'):
            train_runs(bundle(), which, V2[which[3:]], out, k, 'v2/')
        else:
            train_runs(bundle(), which, V[which], out, k)
    elif kind == 'staff':
        for i, r in enumerate(V2['staff']['runs']):
            out[f'v2/staff/{i}'] = staff_run(V2['staff']['files'], r, k(f'v2/staff/{i}'))
    else:
        day_runs(bundle(), V2['day'], out, k, which)
    return out


def day_runs(b, d, out, k, only='all'):
    """The first train's day and its runs with a trainee (the vectors' `day`), as reference_runs; only: None for the
    day alone, a fork's index for that fork alone."""
    from ref import make_plant3d_vectors as G
    runs = [('v2/day', [], d['until'], d['scenario'], False)] + [
        ('v2/day/' + f['id'], f['inputs'], f['until'], f.get('scenario', d['scenario']), f.get('session', False))
        for f in d['forks']]
    if only != 'all':
        runs = [runs[0 if only is None else only + 1]]
    for name, inputs, until, sid, ses in runs:
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
        # Godot's run and the reference's side by side: the reference's runs (test_every_value_bit_for_bit's) are
        # made while Godot runs, its output going to files (a pipe nobody reads would fill and stop it)
        args = [GODOT, '--headless', '--script', os.path.join(SIM, 'tests', 'run_vectors.gd'), '--',
                f'--digests={cls.digest_path}']
        out, err = (os.path.join(cls.tmp.name, x) for x in ('godot.out', 'godot.err'))
        deadline = time.monotonic() + 1800         # (as godot()'s timeout)
        with open(out, 'w', encoding='utf-8') as fo, open(err, 'w', encoding='utf-8') as fe:
            proc = subprocess.Popen(args, stdout=fo, stderr=fe, cwd=REPO)
            try:
                try:
                    cls.ref, cls.ref_error = reference_runs(cls.V, V2=cls.V2, jobs=G.jobs()), None
                except Exception as x:          # (test_every_value_bit_for_bit's failure, not every test's)
                    cls.ref, cls.ref_error = None, x
                code = proc.wait(timeout=max(0.0, deadline - time.monotonic()))
            except BaseException:               # timed out or interrupted: Godot is not left running
                proc.kill()
                proc.wait()
                cls.tmp.cleanup()
                raise
        with open(out, encoding='utf-8') as fo, open(err, encoding='utf-8') as fe:
            cls.result = subprocess.CompletedProcess(args, code, fo.read(), fe.read())

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
        if self.ref_error is not None:
            raise self.ref_error
        ref = self.ref
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
        ref = reference_runs(self.V, keep=(run, lo, hi), V2=self.V2, jobs=G.jobs())[run][3]
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


def bench_runs(V4):
    """The Workshop bench vectors' runs (WORKSHOP.md §6.2) on the reference, as reference_runs: every value's bits at
    every step and the state digests."""
    from ref import plant3d_bench as BM
    out = {}
    for k, s in enumerate(V4['steps']):
        e = BM.check(BM.loads(s['bench']), s['components'], 'bench').engine()
        h = Hasher(0)
        h.add(e)
        inputs = sorted(s['inputs'], key=lambda x: x[0])
        j = 0
        while e.step_no < len(s['states']) - 1:
            while j < len(inputs) and inputs[j][0] == e.step_no + 1:
                apply(e, inputs[j])
                j += 1
            e.step()
            h.add(e)
        h.end()
        out[f'bench/steps/{k}'] = (0, h.chunks, e.names, h.vals, h.states)
    return out


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptBench(unittest.TestCase):
    """ref/vectors/plant3d-bench-v1.json (docs/plant3d/WORKSHOP.md §6.2, milestone K3) through the app's loader
    (sim/bench_model.gd) and engine: every valid bench loads, every run's snapshots and events match, and every value's
    bits at every step and the state digests are the reference's, with the straight-line program and with the
    interpreter alone."""

    def test_bench_vectors(self):
        with open(os.path.join(REPO, 'ref', 'vectors', 'plant3d-bench-v1.json'), encoding='utf-8') as f:
            V4 = json.load(f)
        want = bench_runs(V4)
        n = len(V4['valid']) + len(V4['steps'])
        for extra in ([], ['--interpreter=1']):
            with tempfile.TemporaryDirectory() as d:
                dig = os.path.join(d, 'digests.json')
                r = godot('run_vectors.gd', '--only=bench', f'--digests={dig}', *extra, timeout=300)
                no_errors(self, r)
                self.assertEqual(r.returncode, 0, r.stdout[-4000:])
                self.assertIn(f'VECTORS passed={n} failed=0', r.stdout)
                with open(dig, encoding='utf-8') as f:
                    got = json.load(f)
            self.assertEqual(sorted(got), sorted(want), extra)
            for run, (start, chunks, names, _, states) in want.items():
                self.assertEqual((got[run]['from'], got[run]['chunks']), (start, chunks), f'{run} {extra}')
                self.assertEqual(got[run]['state'], states, f'{run} {extra}: the state digests')


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptRealism(unittest.TestCase):
    """ref/vectors/plant3d-realism.json (docs/plant3d/REALISM.md §13, milestone RE1) through the app's engine: the
    world's streams (sim/world.gd), and the runs with the clock values, every value's bits at every step and the state
    digests, with the straight-line program and with the interpreter alone."""

    def test_realism_vectors(self):
        with open(os.path.join(REPO, 'ref', 'vectors', 'plant3d-realism.json'), encoding='utf-8') as f:
            V3 = json.load(f)
        want, n = {}, 1
        for part in ('staff', 'wear', 'weather', 'hands'):   # RE1, AG1 (REALISM.md §2.2), WX1 (§5.1), HW1 (§2.13)
            st = V3[part]
            want.update({f'realism/{part}/{i}': staff_run(st['files'], r, None) for i, r in enumerate(st['runs'])})
            n += 1 + len(st['runs'])
        for extra in ([], ['--interpreter=1']):
            with tempfile.TemporaryDirectory() as d:
                dig = os.path.join(d, 'digests.json')
                r = godot('run_vectors.gd', '--only=realism', f'--digests={dig}', *extra, timeout=300)
                no_errors(self, r)
                self.assertEqual(r.returncode, 0, r.stdout[-4000:])
                self.assertIn(f'VECTORS passed={n} failed=0', r.stdout)
                with open(dig, encoding='utf-8') as f:
                    got = json.load(f)
            self.assertEqual(sorted(got), sorted(want), extra)
            for run, (start, chunks, names, _, states) in want.items():
                self.assertEqual((got[run]['from'], got[run]['chunks']), (start, chunks), f'{run} {extra}')
                self.assertEqual(got[run]['state'], states, f'{run} {extra}: the state digests')
                self.assertEqual(names[-3:] if run.startswith('realism/weather') else names[-2:],
                                 ['world_hour', 'world_day', 'world_wx'][:3 if run.startswith('realism/weather') else 2],
                                 run)

    def test_loader_guard(self):
        """The loader refuses a scenario without `world` when the model reads a clock value, and the step bench
        answers a load it can't read with its ERROR line (sim/tests/check_world.gd)."""
        r = godot('check_world.gd', os.path.join(REPO, 'ref', 'vectors', 'plant3d-realism.json'), timeout=300)
        no_errors(self, r)
        self.assertIn('WORLD bad=0', r.stdout, r.stdout[-4000:])
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])

    def test_step_bench(self):
        """The step bench with a synthetic realism load (app/step_bench.gd, as the phone's `step=bench` runs it):
        the train as built, with 600 values, and with 600 values of AG1's nodes and WX1's weather (--engine) load,
        run the cold start and step at base load; the weather step is timed alone: the built weather's seven values
        in the train as built and with 600 values (cold_iron has its season's weather since 2026-11-03), the load's
        ten with --engine."""
        with tempfile.TemporaryDirectory() as d:
            path, epath = os.path.join(d, 'r600.json'), os.path.join(d, 'e600.json')
            subprocess.run([sys.executable, os.path.join(REPO, 'tools', 'plant3d', 'realism_synth.py'), '600', path],
                           check=True, cwd=REPO)
            subprocess.run([sys.executable, os.path.join(REPO, 'tools', 'plant3d', 'realism_synth.py'), '600', epath,
                            '--engine'], check=True, cwd=REPO)
            hpath = os.path.join(d, 'h600.json')        # (HW1: the hands step alone with 12 actions under way)
            subprocess.run([sys.executable, os.path.join(REPO, 'tools', 'plant3d', 'realism_synth.py'), '600', hpath,
                            '--engine', '--hands'], check=True, cwd=REPO)
            r = godot('bench_realism.gd', f'--synth=r600:{path},e600:{epath},h600:{hpath}', '--base-steps=200',
                      timeout=900)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])
        self.assertIn('WEATHER load=e600 values=10 ', r.stdout)
        self.assertIn('WEATHER load=built values=7 ', r.stdout)
        self.assertIn('WEATHER load=r600 values=7 ', r.stdout)
        for load in ('built', 'r600', 'e600'):
            self.assertIn(f'BATCH load={load} values=', r.stdout)
        self.assertIn('STEP load=r600 values=', r.stdout)
        self.assertIn('HANDS load=h600 hands=150 meters=50 busy=12 ', r.stdout)
        self.assertIn('world=true phase=cold_start', r.stdout)
        # cold_iron's weather fixed clear unless --weather= says otherwise (a measured run's: app/main.gd
        # measured_weather); the --engine load keeps its own seeded chain
        for load in ('built', 'r600'):
            self.assertIn(f'STEP load={load} values=', r.stdout)
            self.assertRegex(r.stdout, rf'STEP load={load} values=\d+ weather=clear world=true phase=cold_start')
        self.assertRegex(r.stdout, r'STEP load=e600 values=\d+ weather=seeded world=true phase=cold_start')


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
        for run, (start, chunks, *_) in steps_runs(V['valid'][0]['files'], E['steps']).items():
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
class GdscriptIdleRiders(unittest.TestCase):
    """A ride in an idle task (the adversarial review of the staff step's speed-up, PLANT3D.md §21.15): the camp's
    synthetic plant with its off-duty idle task a ride to the control room's stop; people off duty go to the camp's
    stop, wait there (asleep in the app's engine) and get on when the 05:40 bus comes. The app's engine replays it as the
    reference made it (a run of its own, not in the vectors)."""

    def test_idle_riders_get_on(self):
        camp = G.with_camp(G.mini_staff()['staff.json'])
        for t in camp['tasks']:
            if t['id'] == 'rest_home':
                t['steps'] = [{'ride': {'from': 'camp_stop', 'to': 'cr_stop'}}, {'work': 30}]
        base = G.mini_staff()
        sc = copy.deepcopy(base['scenarios/s1.json'])
        sc['start'] = {'day': 1, 'time': '05:00'}
        e = P.Recorder(G.check(G.staff_files(sc, camp)), 's1', False)
        states, digests = [e.snapshot()], [e.digest()]
        while e.step_no < 500:
            e.step()
            if e.step_no % 20 == 0:
                states.append(e.snapshot())
            if e.step_no % G.DIGEST_EVERY == 0:
                digests.append(e.digest())
        on = [x for x in e.events if x[1] == 'aboard' and x[3] == 'bus' and x[4] == 'camp_stop' and x[5] == 'on']
        self.assertTrue(on, 'someone off duty on the bus')    # (crew A's control room operator, waiting from step 244)
        with open(VECTORS2, encoding='utf-8') as f:
            V2 = json.load(f)
        run = {'why': 'idle riders', 'scenario': sc, 'staff': camp, 'inputs': e.inputs, 'until': 500, 'every': 20,
               'states': states, 'events': e.events, 'digests': digests}
        V2 = {'about': V2['about'], 'valid': V2['valid'], 'reject': [], 'steps': [],
              'staff': dict(V2['staff'], runs=[run], reject=[])}
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'idle.json')
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(V2, f)
            r = godot('run_vectors.gd', '--only=v2', f'--vectors2={path}', timeout=600)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])
        self.assertIn('VECTORS passed=', r.stdout)
        self.assertIn(' failed=0', r.stdout, r.stdout[-3000:])


def _waits(e):
    """The NPCs of reference run e waiting for a place taken (at the place where they wait) or for a meeting's others:
    person id -> (kind, the step the wait began)."""
    sr = e.staff
    out = {}
    for i, p in enumerate(sr.people):
        if p.cur is None or sr.slot_of(i) is not None:
            continue
        s = sr.st.tasks[p.cur['task']]['steps'][p.cur['step']]
        x = p.cur['st']
        if 'meet' in s and 'meet_since' in x and not x.get('met'):
            out[p.id] = ('meet', x['meet_since'])
        elif x.get('waiting') and 'wait_since' in x and p.pos == x.get('dest'):
            out[p.id] = ('place', x['wait_since'])
    return out


class _ClaimWaiting:
    """A session's player (§17.13) for GdscriptWaits: slot `slot` takes the first NPC found waiting (kind 'meet' or
    'place') and gives them back `hold` steps later, played meanwhile as the generator's Trainee plays."""

    def __init__(self, kind, slot, hold):
        self.kind, self.slot, self.hold = kind, slot, hold
        self.who, self.at = None, None
        self.pl = G.Trainee(slot=slot, quiet=True)

    def __call__(self, e):
        n = e.step_no + 1
        if self.who is None:
            w = [k for k, v in sorted(_waits(e).items()) if v[0] == self.kind]
            if w:
                self.who, self.at = w[0], n
                G.apply_staff(e, [n, 'role', self.who, self.slot])
        elif n == self.at + self.hold:
            G.apply_staff(e, [n, 'release', self.slot])
        self.pl(e)


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptWaits(unittest.TestCase):
    """The people waiting for a place taken, or for a meeting's others, asleep in the app's engine (PLANT3D.md
    §21.15) until their 15 minutes are over or something that can end the wait happens (staff.gd _wake_at): a place in
    the room let go or taken, someone coming into the room or coming on duty there; and as any sleeper, a task, a
    duty, a stop, a placement. Runs of the reference on the synthetic plant (not in the vectors), busier than its
    usual day (a third field operator, the field operators' idle task leaving its seat every few minutes), replayed by
    the app's engine bit for bit: the shift change's meetings (some met early, some given up) and seats (some freed,
    some given up), a person claimed by a session slot while they wait and given back, the same for a place, and a
    jump while people wait. A save and restore while people wait: check_staff_waits.gd."""

    @staticmethod
    def busy():
        st = copy.deepcopy(G.mini_staff()['staff.json'])
        st['people'].append({'id': 'a_fo3', 'role': 'field_op', 'roster': 'shift', 'crew': 'a', 'call': 'Field 3 A'})
        for t in st['tasks']:
            if t['id'] == 'idle_field':
                t['steps'] = [{'go': {'kind': 'seat', 'room': 'office'}}, {'work': 4}, {'go': 'ws_door'}, {'work': 2}]
        return st

    def run_ref(self, why, start, until, player=None, session=False, trainee=None):
        sc = copy.deepcopy(G.mini_staff()['scenarios/s1.json'])
        sc['start'] = {'day': 1, 'time': start}
        if trainee is not None:
            sc['staff']['trainee'] = trainee
        staff = self.busy()
        e = P.Recorder(G.check(G.staff_files(sc, staff)), 's1', session)
        states, digests = [e.snapshot()], [e.digest()]
        tpm = e.staff.st.tpm
        prev, ends = {}, set()
        while e.step_no < until:
            if player is not None:
                player(e)
            e.step()
            if e.step_no % 20 == 0 or e.step_no == until:
                states.append(e.snapshot())
            if e.step_no % G.DIGEST_EVERY == 0:
                digests.append(e.digest())
            w = _waits(e)
            for pid, v in prev.items():
                if w.get(pid) != v:
                    ends.add((v[0], 'given up' if e.step_no - v[1] >= 15 * tpm else 'ended early'))
            prev = w
        run = dict({'why': why, 'scenario': sc, 'staff': staff, 'inputs': e.inputs, 'until': until, 'every': 20,
                    'states': states, 'events': e.events, 'digests': digests}, **({'session': True} if session else {}))
        return run, ends, e

    def test_waits_replay(self):
        runs = []
        run, ends, _ = self.run_ref('the shift change\'s meetings and seats', '05:30', 3000)
        self.assertEqual(ends, {('meet', 'ended early'), ('meet', 'given up'), ('place', 'ended early'),
                                ('place', 'given up')})
        runs.append(run)
        run, ends, _ = self.run_ref('the morning\'s seats', '07:00', 3000)
        self.assertIn(('place', 'ended early'), ends)
        runs.append(run)
        for kind, slot in (('meet', 0), ('place', 1)):
            pl = _ClaimWaiting(kind, slot, 40)
            run, _, e = self.run_ref('a session slot takes a person waiting (%s) and gives them back' % kind,
                                     '05:30', 1500, pl, session=True)
            self.assertIsNotNone(pl.who, 'nobody waiting (%s) to claim' % kind)
            self.assertTrue(any(x[1] == 'role' and x[-1] == slot for x in e.inputs), e.inputs[:20])
            self.assertTrue(any(x[1] == 'release' for x in e.inputs))
            runs.append(run)
        jumped = []

        def jump(e):
            if not jumped and _waits(e):
                jumped.append(e.step_no + 1)
                G.apply_staff(e, [e.step_no + 1, 'task_ack'])      # (the supervisor's tasks seen: else refused)
                G.apply_staff(e, [e.step_no + 1, 'jump', '07:30'])
        run, _, e = self.run_ref('a jump while people wait', '05:30', 1500, jump, trainee='a_sup')
        self.assertTrue(jumped)
        self.assertTrue(any(x[1] == 'jump' and x[-1] == 'done' for x in e.events), 'the jump was refused')
        runs.append(run)
        with open(VECTORS2, encoding='utf-8') as f:
            V2 = json.load(f)
        V2 = {'about': V2['about'], 'valid': V2['valid'], 'reject': [], 'steps': [],
              'staff': dict(V2['staff'], runs=runs, reject=[])}
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'waits.json')
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(V2, f)
            r = godot('run_vectors.gd', '--only=v2', f'--vectors2={path}', timeout=900)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])
        self.assertIn('VECTORS passed=', r.stdout)
        self.assertIn(' failed=0', r.stdout, r.stdout[-3000:])

    def test_every_change_a_wait_reads_wakes(self):
        """What the waits read (who holds a place, where people are, who is on duty) is written only where the
        sleepers in that room are woken: a place given to sp_pos only through _put (place_all, which wakes everyone,
        aside), st_holder changed only in reserve, unreserve and leave_place, each calling _wake_at (and place_all),
        sp_on set only in phase 1, which wakes the room, and place_all; nothing outside staff.gd writes them."""
        with open(os.path.join(SIM, 'staff.gd'), encoding='utf-8') as f:
            src = f.read()
        funcs = {}
        name = None
        for line in src.splitlines():
            m = re.match(r'(?:static )?func (\w+)', line)
            if m:
                name = m.group(1)
            funcs.setdefault(name, []).append(line)
        where = lambda pat: sorted({k for k, ls in funcs.items() for x in ls if re.search(pat, x)})  # noqa: E731
        self.assertEqual(where(r'sp_pos\[[^]]*\] = (?!-1)'), ['_put', 'place_all'])
        self.assertEqual(where(r'st_holder(\[[^]]*\] = |\.erase\(| = \{)'),
                         ['leave_place', 'place_all', 'reserve', 'unreserve'])
        for k in ('leave_place', 'reserve', 'unreserve', '_put'):
            self.assertTrue(any('_wake_at(e, ' in x for x in funcs[k]), k)
        self.assertEqual(where(r'sp_on\[[^]]*\] = 1'), ['_phase1', 'place_all'])
        on = '\n'.join(funcs['_phase1'])
        self.assertRegex(on, r'e\.sp_on\[pi\] = 1\n(.*\n){0,3}.*_wake_at\(e, e\.sp_pos\[pi\]\)')
        self.assertRegex('\n'.join(funcs['place_all']), r'sp_wait_on\.fill\(-1\)')
        for root, _, files in os.walk(os.path.join(REPO, 'apps', 'plant3d')):
            for fn in files:
                if fn.endswith('.gd') and fn != 'staff.gd' and 'tests' not in root.split(os.sep):
                    with open(os.path.join(root, fn), encoding='utf-8') as f:
                        t = f.read()
                    self.assertIsNone(re.search(r'(sp_pos|sp_on)\[[^]]*\] = |st_holder(\[[^]]*\] = |\.erase\()', t), fn)

    def test_save_and_restore_while_waiting(self):
        r = godot('check_staff_waits.gd', timeout=900)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])
        self.assertIn('WAITS ok', r.stdout)


@unittest.skipUnless(HAVE or REQUIRED, 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class GdscriptReleasedDriver(unittest.TestCase):
    """A session's player who plays a bus's driver, released aboard (PLANT3D.md §17.13, §21.4; found by S4e's steered
    vectors): the task taken from them when the run began, counted by the player's rule until then, goes on as an
    NPC's at the depot, a step a turn, as the reference counts it (the app's engine counted every step since the
    player's last at once and ended it on arrival). A run of its own, not in the vectors."""

    def test_released_driver_works_on(self):
        camp = G.with_camp(G.mini_staff()['staff.json'])
        sc = copy.deepcopy(G.mini_staff()['scenarios/s1.json'])
        sc['start'] = {'day': 1, 'time': '05:30'}
        pl = G.Session([G.Trainee(slot=0), G.Trainee(slot=1, quiet=True)], extra=[[1, 'role', 'drv1', 0]],
                       when=[(lambda e: e.step_no > 110 and e.staff.veh[0]['leg'] is not None, ('release', 0))])
        e = P.Recorder(G.check(G.staff_files(sc, camp)), 's1', True)
        states, digests = [e.snapshot()], [e.digest()]
        while e.step_no < 400:
            pl(e)
            e.step()
            if e.step_no % 20 == 0:
                states.append(e.snapshot())
            if e.step_no % G.DIGEST_EVERY == 0:
                digests.append(e.digest())
        self.assertTrue([x for x in e.events if x[1] == 'release' and x[2] == 'drv1'])
        with open(VECTORS2, encoding='utf-8') as f:
            V2 = json.load(f)
        run = {'why': 'released driver', 'scenario': sc, 'staff': camp, 'inputs': e.inputs, 'until': 400,
               'every': 20, 'states': states, 'events': e.events, 'digests': digests, 'session': True}
        V2 = {'about': V2['about'], 'valid': V2['valid'], 'reject': [], 'steps': [],
              'staff': dict(V2['staff'], runs=[run], reject=[])}
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'released.json')
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(V2, f)
            r = godot('run_vectors.gd', '--only=v2', f'--vectors2={path}', timeout=600)
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:])
        self.assertIn(' failed=0', r.stdout, r.stdout[-3000:])


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
                for run, (start, chunks, *_) in steps_runs(V['valid'][0]['files'], vec['steps']).items():
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
            for run, (start, chunks, *_) in steps_runs(V2['valid'][0]['files'], V2['steps'], prefix='v2/').items():
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

    def test_staff_work_at_the_gate(self):
        """The staff step over the gate walk's hour (bench_staff.gd: 05:40-06:40, the buses and the shift change,
        PLANT3D.md §21.15): the work it does, counted (the same on every machine). Before the speed-up (2026-11-02)
        it ran 52,637 task steps in the hour (riders waiting at a stop looked again every step), worked out the bus's
        next run 6,002 times (every step) and looked at 53,495 people's acts; after it, 10,072, 2 and 10,930; with the
        people waiting for a place or for a meeting's others asleep too (2026-11-03), 1,752, 2 and 2,610."""
        r = godot('bench_staff.gd', timeout=600)
        print('\n' + '\n'.join(x for x in r.stdout.splitlines() if x.split(' ')[0] in ('STAFF', 'PHASE', 'COUNT')))
        no_errors(self, r)
        self.assertEqual(r.returncode, 0, r.stdout[-3000:])
        m = re.search(r'^COUNT runs=(\d+) due=(\d+) acts=(\d+)$', r.stdout, re.M)
        self.assertIsNotNone(m, r.stdout[-3000:])
        runs, due, acts = (int(x) for x in m.groups())
        self.assertLess(runs, 3000)
        self.assertLess(due, 100)
        self.assertLess(acts, 4000)


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
