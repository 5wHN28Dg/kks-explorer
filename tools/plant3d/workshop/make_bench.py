"""Makes a kind's bench file from the plant's own content (docs/plant3d/WORKSHOP.md §6.3): where the plant already has a
machine's start-up sequence, its trips, interlocks, alarms and the values they read, the bench takes them from the
generated plant model (`data/plant3d/model/<area>.json`, as make_content.py makes it) rather than a copy by hand, so a
change to the plant's sequence is a change to the bench (tests/test_plant3d_content.py checks every committed file is
what make_content.py makes).

A kind's bench source (`tools/plant3d/workshop/<part>.py` `bench_source()`) names:
    area       the plant model the pieces come from
    prefix     stripped from every taken name (`st_speed` -> `speed`); `rename` maps a name otherwise (a machine's
               id, a trip's: their `<id>_state` and `<id>_latched` values follow)
    at         {kks: component or "bench"}: where each taken piece's code is on the bench (a code left out refuses)
    machines, trips, alarms, interlocks     ids to take
    ops        [[kks, do], …] to take beside those of the taken machines and trips (each trip's reset is taken)
    values     the plant values to take, by name: their definitions as the plant has them (codes dropped)
    bench      the bench's own file: its values (everything the taken pieces read that isn't taken), ops, faults,
               bindings, sources…; the taken pieces are added to it
    before     the bench's own values that come before the taken ones; the file's values are these, then the taken
               in the plant's order, then the bench file's own `values`, each moved only as far as a stateless node
               must be to come after the values it reads (ref/plant3d.py: a stateless node reads earlier values only)
    titles     {(kks, do) or trip id: title} the Run panel's words for a taken op

make(source, models) -> the bench file (a dict). It refuses (ValueError) a reference neither taken nor defined by the
bench, a code with no place on the bench, a name taken twice or one the bench defines too.
"""
import copy

STATEFUL = ('lag', 'ramp', 'integrate', 'latch', 'delay', 'timer', 'wrap', 'hold', 'draw', 'wear', 'count')

# the value nodes' fields that name other values (format 1 and 2: ref/plant3d.py); the rest are numbers or words
_REF_ONE = ('lag', 'integrate', 'of', 'not', 'select', 'ramp', 'timer', 'wrap', 'hold', 'when', 'latch', 'reset',
            'delay')
_REF_LIST = ('sum', 'product', 'diff', 'min', 'max', 'and', 'or', 'cases')
_WORDS = ('unit', 'kks', 'text', 'say', 'title', 'isa', 'first_out')


def _err(msg):
    raise ValueError(f'make_bench: {msg}')


class _Names:
    def __init__(self, src, plant):
        self.prefix = src.get('prefix', '')
        self.rename = dict(src.get('rename', {}))
        for kind in ('machines', 'trips'):     # a machine's state value, a trip's latch follow the piece's own name
            for x in plant[kind]:
                if x['id'] in self.rename:
                    sfx = '_state' if kind == 'machines' else '_latched'
                    self.rename.setdefault(x['id'] + sfx, self.rename[x['id']] + sfx)
        self.read = set()                       # every bench name a taken piece reads

    def __call__(self, name):
        if name in self.rename:
            return self.rename[name]
        if self.prefix and name.startswith(self.prefix):
            return name[len(self.prefix):]
        return name

    def ref(self, x):
        """A value reference (a name or a number) renamed, and noted as read."""
        if isinstance(x, str):
            n = self(x)
            self.read.add(n)
            return n
        return x


def _node(n, names):
    out = {}
    for k, v in n.items():
        if k == 'kks':
            continue
        if k in _REF_ONE and isinstance(v, str):
            out[k] = names.ref(v)
        elif k in _REF_LIST and isinstance(v, list):
            out[k] = [names.ref(x) for x in v]
        elif k == 'cmp':
            out[k] = [names.ref(v[0]), v[1], names.ref(v[2])]
        elif k == 'cases' or k in _WORDS or k == 'table' or not isinstance(v, (str, list)):
            out[k] = copy.deepcopy(v)
        else:
            _err(f'a value node field {k!r} the tool does not know (add it to make_bench.py)')
    return out


def _reads(node):
    """The names a value node reads."""
    out = []
    for k, v in node.items():
        if k in _REF_ONE and isinstance(v, str):
            out.append(v)
        elif k in _REF_LIST and isinstance(v, list):
            out += [x for x in v if isinstance(x, str)]
        elif k == 'cmp':
            out += [x for x in (v[0], v[2]) if isinstance(x, str)]
    return out


def _ordered(values):
    """The values in their given order, except that a stateless node comes after every value it reads (the first
    of those ready, each time: the order kept wherever it can be)."""
    names = {v[0] for v in values}
    left = list(values)
    done, out = set(), []
    while left:
        for i, (n, node) in enumerate(left):
            stateful = any(k in node for k in STATEFUL) or 'state' in node
            if stateful or all(r in done or r not in names for r in _reads(node)):
                out.append(left.pop(i))
                done.add(n)
                break
        else:
            _err('the values read each other in a loop of stateless nodes: ' + ', '.join(v[0] for v in left))
    return out


def _sets(s, names):
    return {names.ref(k): v for k, v in s.items()}


def _at(kks, src, where):
    if kks not in src['at']:
        _err(f'{where}: the code {kks} has no place on the bench (the source\'s `at`)')
    return src['at'][kks]


def make(src, models):
    area = src['area']
    plant = next((m for m in models if m['area'] == area), None)
    if plant is None:
        _err(f'no plant model {area!r}')
    names = _Names(src, plant)
    bench = copy.deepcopy(src['bench'])
    by_id = {k: {x['id']: x for x in plant.get(k, [])} for k in ('machines', 'trips', 'alarms', 'interlocks')}
    defs = {v[0]: v[1] for v in plant['values']}

    def take(kind, ids):
        out = []
        for i in ids:
            if i not in by_id[kind]:
                _err(f'no {kind[:-1]} {i!r} in the plant model {area}')
            out.append(by_id[kind][i])
        return out

    machines = []
    for m in take('machines', src.get('machines', [])):
        states = []
        for s in m['states']:
            y = {'id': s['id']}
            if 'set' in s:
                y['set'] = _sets(s['set'], names)
            if 'next' in s:
                y['next'] = [[names.ref(c), to] for c, to in s['next']]
            for k in ('watch', 'say'):
                if k in s:
                    y[k] = s[k]
            states.append(y)
        machines.append({'id': names(m['id']), 'at': _at(m['kks'], src, m['id']), 'init': m['init'],
                         'commands': copy.deepcopy(m['commands']), 'states': states})

    def does(do):
        out = []
        for a in do:
            if 'machine' in a:
                out.append({'machine': names(a['machine']), 'to': a['to']})
            else:
                out.append({'set': _sets(a['set'], names)})
        return out

    trips = []
    for t in take('trips', src.get('trips', [])):
        y = {'id': names(t['id']), 'at': _at(t['kks'], src, t['id']), 'text': t['text'], 'when': names.ref(t['when']),
             'do': does(t['do'])}
        for k in ('isa', 'delay', 'first_out'):
            if k in t:
                y[k] = t[k]
        trips.append(y)
    alarms = []
    for a in take('alarms', src.get('alarms', [])):
        y = {'id': names(a['id']), 'at': _at(a['kks'], src, a['id']), 'text': a['text'], 'when': names.ref(a['when']),
             'priority': a['priority'], 'where': _at(a['where'], src, a['id'])}
        for k in ('isa', 'delay'):
            if k in a:
                y[k] = a[k]
        for k in ('clear', 'suppress'):
            if k in a:
                y[k] = names.ref(a[k])
        alarms.append(y)
    interlocks = []
    for x in take('interlocks', src.get('interlocks', [])):
        y = {'id': names(x['id']), 'when': names.ref(x['when']), 'do': does(x['do'])}
        if 'kks' in x:
            y['at'] = _at(x['kks'], src, x['id'])
        if 'text' in x:
            y['text'] = x['text']
        interlocks.append(y)
    machine_ids = set(src.get('machines', []))
    trip_ids = set(src.get('trips', []))
    want = {tuple(o) for o in src.get('ops', [])}
    ops, found = [], set()
    titles = src.get('titles', {})
    for o in plant['ops']:
        key = (o['kks'], o['do'])
        if not (o.get('machine') in machine_ids or o.get('trip') in trip_ids or key in want):
            continue
        found.add(key)
        y = {'at': _at(o['kks'], src, f'op {key}'), 'do': o['do']}
        t = titles.get(o.get('trip')) if 'trip' in o else titles.get(key)
        if t:
            y['title'] = t
        if 'machine' in o:
            y['machine'] = names(o['machine'])
        if 'trip' in o:
            y['trip'] = names(o['trip'])
        if 'input' in o:
            y['input'] = names.ref(o['input'])
        if 'range' in o:
            y['range'] = list(o['range'])
        if 'set' in o:
            y['set'] = _sets(o['set'], names)
        if 'needs' in o:
            y['needs'] = [[names.ref(c), why] for c, why in o['needs']]
        ops.append(y)
    for key in sorted(want - found):
        _err(f'no op {list(key)} in the plant model {area}')
    # the values: those named, as the plant defines them (its order), then the bench's own
    taken = []
    for n in src.get('values', []):
        if n not in defs:
            _err(f'no value {n!r} in the plant model {area}')
    for n, node in plant['values']:
        if n in src.get('values', []):
            taken.append([names(n), _node(node, names)])
    before = copy.deepcopy(src.get('before', []))
    own = {v[0] for v in bench.get('values', []) + before}
    seen = set()
    for n, _ in taken:
        if n in seen:
            _err(f'{n} is taken twice (two plant names rename to it)')
        if n in own:
            _err(f'{n} is taken from the plant and defined by the bench too')
        seen.add(n)
    derived = {m['id'] + '_state' for m in machines} | {t['id'] + '_latched' for t in trips}
    defined = seen | own | derived | {m['id'] + '_state' for m in bench.get('machines', [])} | \
        {t['id'] + '_latched' for t in bench.get('trips', [])}
    missing = sorted(n for n in names.read if n not in defined)
    if missing:
        _err('read by the taken pieces but neither taken nor defined by the bench: ' + ', '.join(missing))
    bench['values'] = _ordered(before + taken + bench.get('values', []))
    for k, xs in (('machines', machines), ('trips', trips), ('alarms', alarms), ('interlocks', interlocks),
                  ('ops', ops)):
        if xs or k in bench:
            bench[k] = xs + bench.get(k, [])
    order = ['format', 'version', 'part', 'sources', 'values', 'ops', 'interlocks', 'machines', 'trips', 'alarms',
             'faults', 'start', 'bind', 'legends', 'readouts', 'mirror']
    return {k: bench[k] for k in order if k in bench}
