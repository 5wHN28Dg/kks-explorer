"""Walkdown Plant's Workshop bench models (docs/plant3d/WORKSHOP.md §6, milestone K3): the reference validator of the
format `walkdown-plant-bench` (version 1, one file per part kind, `data/plant3d/workshop/bench/<part>.json`) and the
join that turns a checked file into the model the reference's `Engine` (ref/plant3d.py) steps, unchanged.

A bench model is a plant model without KKS codes: its ops, machines, trips, alarms, faults and bindings name a
component of the kind's Workshop tree (or `bench`, the bench itself) in `at`, which the join writes into the engine's
`kks` field, so the engine finds an op by (at, do, trip) exactly as a plant op by (kks, do, trip). Its values are
format 1's node kinds and format 2's `hold` (§15.4); no staff, isolations, works, lifts, clock or world. Faults are a
scenario's trainer faults (no `when`), pressed from the bench panel with their repair; `start` is the scenario's
`init`. Bindings are by component: §7.7's anim, show (with an optional `lit` value), sound and lamp, and the
Workshop's own flow (a generator's flow path), heat and pressure (a component's colour from a legend).

    check(d, comps, where, sounds=None) -> Bench (raises FormatError(code, where) on the first broken rule)
    Bench.engine()                      -> ref.plant3d.Engine at step 0, inputs as for a plant's
"""
import re
from ref import sjson
from ref import plant3d as P
from ref.courses import FormatError, need, keys, num, lst, ident, is_num, check_table

FORMAT = 'walkdown-plant-bench'
VERSION = 1
AT_BENCH = 'bench'
# WORKSHOP.md §6.1's limits (and the parts it leaves to this file)
LIMIT = {'values': 600, 'ops': 48, 'machines': 8, 'trips': 48, 'alarms': 64, 'faults': 24, 'bind': 128,
         'flows': 16, 'readouts': 12, 'interlocks': 64, 'sources': 16, 'legends': 8, 'mirror': 64}
BIND_KINDS = ('anim', 'show', 'sound', 'lamp', 'flow', 'heat', 'pressure')
LAMPS = ('running', 'stopped', 'open', 'closed', 'fault', 'beacon')
NOT_ON_THE_BENCH = ('draw', 'wear', 'count')     # the realism programme's nodes: a version 2 of this format (§6.1)
WORLD = ('world_hour', 'world_day', 'world_wx')      # the clock values' names: reserved as in a version 2 plant
SID = re.compile(r'[a-z_][a-z0-9_]{0,31}')
HEX = re.compile(r'#[0-9a-f]{6}')


def loads(data, where='bench'):
    if isinstance(data, str):
        data = data.encode('utf-8')
    try:
        return sjson.loads(data)
    except sjson.StrictError as e:
        raise FormatError('bad_json', f'{where}: {e}')


def words(x, where, hi):
    need(isinstance(x, str) and 1 <= len(x) <= hi and x == x.strip(), 'bad_type', f'{where}: text of 1–{hi} characters')
    return x


class _Plant:
    """What ref.plant3d.Model reads of the plant: the codes (here the components and `bench`)."""
    def __init__(self, comps):
        self.codes = set(comps) | {AT_BENCH}
        self.equipment = {}
        self.sound_refs = []


class _Bundle:
    """What ref.plant3d.Model and Engine read of a bundle."""
    def __init__(self):
        self.plant = {'ext': []}
        self.version = 2            # format 2's `hold` (§15.4) and its trainer's events; nothing else of format 2 is here
        self.staff = None
        self.kit = None
        self.sounds = None
        self.model = None
        self.scenarios = {}


class BenchModel(P.Model):
    """ref.plant3d.Model with components for codes."""

    def kks_ref(self, c, where):
        need(isinstance(c, str) and c in self.p.codes, 'bad_ref', f'{where}: no component {c!r} (nor "bench")')

    def world_names(self):
        return ()                   # no clock values on the bench


class Bench:
    def __init__(self, part, b, scenario, units, readouts, bind, legends, faults):
        self.part, self.b, self.scenario = part, b, scenario
        self.units, self.readouts, self.bind, self.legends, self.faults = units, readouts, bind, legends, faults

    def engine(self):
        return P.Engine(self.b, self.scenario)


def _at(x, where):
    need(isinstance(x, dict), 'bad_type', where)
    need('kks' not in x, 'unknown_key', f'{where}.kks: a bench names a component in `at`, never a code')
    y = {('kks' if k == 'at' else k): v for k, v in x.items()}
    return y


def check(d, comps, where='bench', sounds=None, part=None):
    """Checks one bench file (parsed) against its kind's component ids `comps` (the Workshop data file's, WORKSHOP.md
    §4.1) and, when given, sounds.json (parsed: its `sounds`). `part`: the kind it must be for. Returns a Bench."""
    keys(d, ('format', 'version', 'part', 'sources', 'values', 'start'),
         ('ops', 'interlocks', 'machines', 'trips', 'alarms', 'faults', 'bind', 'legends', 'readouts', 'mirror'), where)
    need(d['format'] == FORMAT, 'bad_format', f'{where}.format: {FORMAT}')
    need(d['version'] == VERSION and type(d['version']) is int, 'bad_version', f'{where}.version: {VERSION}')
    ident(d['part'], f'{where}.part')
    need(part is None or d['part'] == part, 'bad_ref', f'{where}.part: {part} expected')
    comps = set(comps)
    need(AT_BENCH not in comps, 'bad_id', f'{where}: a component may not be called {AT_BENCH!r}')
    srcs = set()
    for i, s in enumerate(lst(d['sources'], f'{where}.sources', 1, LIMIT['sources'])):
        sw = f'{where}.sources[{i}]'
        keys(s, ('id', 'cite', 'url'), (), sw)
        need(isinstance(s['id'], str) and SID.fullmatch(s['id']) is not None, 'bad_id', f'{sw}.id')
        need(s['id'] not in srcs, 'dup_id', sw)
        srcs.add(s['id'])
        words(s['cite'], f'{sw}.cite', 600)
        need(isinstance(s['url'], str) and s['url'].startswith('https://') and len(s['url']) <= 300, 'bad_value',
             f'{sw}.url: an https URL')
    for k in ('values', 'ops', 'machines', 'trips', 'alarms', 'faults', 'interlocks', 'readouts', 'mirror', 'bind'):
        lst(d.get(k, []), f'{where}.{k}', 1 if k == 'values' else 0)
        need(len(d.get(k, [])) <= LIMIT[k], 'limit', f'{where}.{k}: at most {LIMIT[k]} (WORKSHOP.md §6.1)')
    units = {}
    for i, pair in enumerate(d['values']):
        lst(pair, f'{where}.values[{i}]', 2, 2)
        need(isinstance(pair[1], dict), 'bad_type', f'{where}.values[{i}]')
        need('kks' not in pair[1], 'unknown_key', f'{where}.values[{i}].kks: no codes on the bench')
        bad = [k for k in NOT_ON_THE_BENCH if k in pair[1]]
        need(not bad, 'bad_kind', f'{where}.values[{i}]: {bad and bad[0]} is not a bench node (version 1: format 1\'s '
                                  f'nodes and hold)')
        need(pair[0] not in WORLD, 'dup_id', f'{where}.values[{i}]: {pair[0]} is a clock value\'s name (the app '
                                             f'reserves it, REALISM.md §2.1)')
        if 'unit' in pair[1] and isinstance(pair[0], str):
            units[pair[0]] = pair[1]['unit']
    b = _Bundle()
    m = BenchModel(b, _Plant(comps))
    b.model = m
    model = {'format': P.FORMATS['model'], 'version': 2, 'area': AT_BENCH, 'values': d['values']}
    ops = []
    for i, o in enumerate(d.get('ops', [])):
        ow = f'{where}.ops[{i}]'
        keys(o, ('at', 'do'), ('title', 'set', 'needs', 'machine', 'input', 'range', 'trip'), ow)
        if 'title' in o:
            words(o['title'], f'{ow}.title', 40)
        y = _at(o, ow)
        y.pop('title', None)
        y['where'] = ['local']
        ops.append(y)
    model['ops'] = ops
    for k in ('machines', 'trips', 'alarms'):
        out = []
        for i, x in enumerate(d.get(k, [])):
            xw = f'{where}.{k}[{i}]'
            need(isinstance(x, dict) and 'at' in x, 'missing_key', f'{xw}.at')
            out.append(_at(x, xw))
        model[k] = out
    ils = []
    for i, x in enumerate(d.get('interlocks', [])):
        ils.append(_at(x, f'{where}.interlocks[{i}]'))
    model['interlocks'] = ils
    m.add(model, AT_BENCH, where)
    # the trainer's faults (a scenario's without `when`) and the start state (a scenario's init)
    faults, seen = [], set()
    for i, f in enumerate(d.get('faults', [])):
        fw = f'{where}: fault {f.get("id", i) if isinstance(f, dict) else i}'
        keys(f, ('id', 'text', 'set'), ('at', 'repair'), fw)
        ident(f['id'], fw)
        need(f['id'] not in seen, 'dup_id', fw)
        seen.add(f['id'])
        words(f['text'], f'{fw}.text', 200)
        m.sets(f['set'], f'{fw}.set')
        if 'repair' in f:
            m.sets(f['repair'], f'{fw}.repair')
        if 'at' in f:
            m.kks_ref(f['at'], f'{fw}.at')
        faults.append(_at(f, fw))
    need(isinstance(d['start'], dict), 'bad_type', f'{where}.start')
    for k, v in d['start'].items():
        num(v, f'{where}.start.{k}')
        kind = m.values[m.index[k]][2] if k in m.index else None
        need(kind in ('state',) + P.STATEFUL and kind != 'timer', 'bad_ref',
             f'{where}.start.{k}: not a state or stateful value (other than a timer)')
        n = m.values[m.index[k]][1]
        if kind in ('latch', 'delay'):
            need(v in (0, 1), 'bad_value', f'{where}.start.{k}: 0 or 1')
        elif kind == 'integrate':
            need(n['min'] <= v <= n['max'], 'bad_value', f'{where}.start.{k}: within min and max')
        elif kind == 'wrap':
            need(0 <= v < n['period'], 'bad_value', f'{where}.start.{k}: within [0, period)')
    # bindings (by component; the builder checks anim channels and flow paths against the generator's)
    legends = {}
    need(isinstance(d.get('legends', {}), dict), 'bad_type', f'{where}.legends')
    for name, lg in d.get('legends', {}).items():
        lw = f'{where}.legends.{name}'
        ident(name, lw)
        keys(lg, ('unit', 'table'), (), lw)
        words(lg['unit'], f'{lw}.unit', 16)
        rows = lst(lg['table'], f'{lw}.table', 2, 16)
        for j, r in enumerate(rows):
            lst(r, f'{lw}.table[{j}]', 2, 2)
            num(r[0], f'{lw}.table[{j}]')
            need(isinstance(r[1], str) and HEX.fullmatch(r[1]) is not None, 'bad_value', f'{lw}.table[{j}]: #rrggbb')
            need(j == 0 or r[0] > rows[j - 1][0], 'bad_number', f'{lw}.table: x increasing')
        legends[name] = lg
    need(len(legends) <= LIMIT['legends'], 'limit', f'{where}.legends')
    shows, flows, binds = [], set(), []
    lit_at, anim_at = {}, set()
    for i, x in enumerate(d.get('bind', [])):
        bw = f'{where}.bind[{i}]'
        need(isinstance(x, dict), 'bad_type', bw)
        kinds = [k for k in BIND_KINDS if k in x]
        need(len(kinds) == 1, 'bad_kind', f'{bw}: exactly one of {", ".join(BIND_KINDS)}')
        k = kinds[0]
        if k == 'flow':
            keys(x, ('flow', 'of', 'speed'), ('colour', 'by'), bw)
            ident(x['flow'], f'{bw}.flow')
            need(x['flow'] not in flows, 'dup_id', f'{bw}: path {x["flow"]} bound twice')
            flows.add(x['flow'])
            num(x['speed'], f'{bw}.speed', 0)
            need('by' not in x or 'colour' in x, 'missing_key', f'{bw}: `by` names the value the colour reads')
            if 'colour' in x:
                need(x['colour'] in legends, 'bad_ref', f'{bw}.colour: no legend {x["colour"]!r}')
                need('by' in x, 'missing_key', f'{bw}.by: the value the colour reads')
                m.cond(x['by'], f'{bw}.by')
            m.cond(x['of'], f'{bw}.of')
        else:
            need('at' in x, 'missing_key', f'{bw}.at')
            m.kks_ref(x['at'], f'{bw}.at')
            need(x['at'] != AT_BENCH or k == 'sound', 'bad_ref', f'{bw}.at: only a sound may be at the bench')
            if k == 'anim':
                keys(x, ('at', 'anim', 'of'), ('scale',), bw)
                need(x['at'] not in anim_at, 'dup_id', f'{bw}: {x["at"]} is already moved by another anim binding')
                anim_at.add(x['at'])
                ident(x['anim'], f'{bw}.anim')
                m.cond(x['of'], f'{bw}.of')
                num(x.get('scale', 1), f'{bw}.scale')
            elif k == 'show':
                keys(x, ('at', 'show'), ('lit',), bw)
                m.cond(x['show'], f'{bw}.show')
                if 'lit' in x:
                    m.cond(x['lit'], f'{bw}.lit')
                if 'lit' in x:      # (a show with `lit` is on the component's face, one without a tag over it)
                    need(lit_at.get(x['at'], x['lit']) == x['lit'], 'bad_value',
                         f'{bw}.lit: {x["at"]}\'s face shows its values under one `lit` value')
                    lit_at[x['at']] = x['lit']
                shows.append({'kks': x['at'], 'show': x['show']})
            elif k == 'sound':
                keys(x, ('at', 'sound'), ('gain', 'pitch'), bw)
                need(sounds is None or x['sound'] in {s['id'] for s in sounds}, 'bad_ref',
                     f'{bw}: no sound {x["sound"]!r} in sounds.json')
                for g in ('gain', 'pitch'):
                    if g in x:
                        keys(x[g], ('of', 'table'), (), f'{bw}.{g}')
                        m.cond(x[g]['of'], f'{bw}.{g}.of')
                        check_table(x[g]['table'], f'{bw}.{g}.table')
            elif k == 'lamp':
                keys(x, ('at', 'lamp', 'of'), (), bw)
                need(x['lamp'] in LAMPS, 'bad_value', f'{bw}.lamp')
                m.cond(x['of'], f'{bw}.of')
            else:   # heat, pressure: the component's colour from the legend of that name
                keys(x, ('at', k), (), bw)
                need(k in legends, 'bad_ref', f'{bw}: no legend {k!r}')
                m.cond(x[k], f'{bw}.{k}')
        binds.append(x)
    need(len(flows) <= LIMIT['flows'], 'limit', f'{where}: over {LIMIT["flows"]} flow paths')
    readouts = []
    for i, r in enumerate(d.get('readouts', [])):
        need(isinstance(r, str), 'bad_ref', f'{where}.readouts[{i}]')
        need(r not in readouts, 'dup_id', f'{where}.readouts[{i}]: {r} twice')
        m.cond(r, f'{where}.readouts[{i}]')
        readouts.append(r)
    for i, x in enumerate(d.get('mirror', [])):
        mw = f'{where}.mirror[{i}]'
        keys(x, ('value', 'from'), (), mw)
        need(isinstance(x['value'], str) and x['value'] in m.index, 'bad_ref', f'{mw}.value: no value {x["value"]!r}')
        f = x['from']
        need(isinstance(f, dict), 'bad_type', f'{mw}.from')
        if 'machine' in f:
            keys(f, ('machine',), (), f'{mw}.from')
            need(f['machine'] is True, 'bad_value', f'{mw}.from.machine: true')
        else:
            keys(f, ('bind',), ('channel', 'kind', 'id'), f'{mw}.from')
            want = {'show': (), 'anim': ('channel',), 'lamp': ('kind',), 'sound': ('id',)}
            need(f['bind'] in want, 'bad_value', f'{mw}.from.bind: one of {", ".join(want)}')
            keys(f, ('bind',) + want[f['bind']], (), f'{mw}.from')
            for k in want[f['bind']]:
                need(isinstance(f[k], str) and f[k], 'bad_value', f'{mw}.from.{k}')
    m.finish()
    m.bind = shows
    sc = {'id': 'bench', 'title': 'The bench', 'init': dict(d['start']), 'faults': faults}
    return Bench(d['part'], b, sc, units, readouts, binds, legends, faults)


def check_bytes(data, comps, where='bench', sounds=None, part=None):
    return check(loads(data, where), comps, where, sounds, part)
