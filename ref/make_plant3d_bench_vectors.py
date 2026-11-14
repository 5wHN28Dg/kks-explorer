"""Makes ref/vectors/plant3d-bench-v1.json: the Workshop bench format's vectors (docs/plant3d/WORKSHOP.md §6.2,
milestone K3), from ref/plant3d_bench.py and the reference engine (ref/plant3d.py).

  valid    bench files that pass, with their kind's component ids (the committed ones and a synthetic one)
  reject   a bench file broken one way each, with the code the validator answers
  steps    each valid bench stepped from `start` by inputs (sliders, machine commands, faults and their repairs,
           acknowledgements, refusals), the snapshot after every step and every event

The bench files are kept as their exact text: the app's loader (apps/plant3d/sim/bench_model.gd) reads that text, as
it reads the built scene's. Numbers in snapshots are rounded to 9 decimals (readers compare to 1e-6); the app's run is
compared bit for bit through digests (tests/test_plant3d_sim.py GdscriptBench).

    python3 ref/make_plant3d_bench_vectors.py           # check the file is up to date
    python3 ref/make_plant3d_bench_vectors.py --write   # write it
"""
import copy, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from ref import plant3d as P  # noqa: E402
from ref import plant3d_bench as B  # noqa: E402
from ref.courses import FormatError  # noqa: E402
from ref.make_plant3d_vectors import R, apply  # noqa: E402

OUT = os.path.join(ROOT, 'ref', 'vectors', 'plant3d-bench-v1.json')
DATA = os.path.join(ROOT, 'data', 'plant3d')


def text(d):
    return json.dumps(d, ensure_ascii=False, separators=(', ', ': '))


def committed():
    """Every committed bench file: (part, its text, its kind's component ids, sounds.json's sounds)."""
    files = P.load_dir(DATA)
    sounds = json.loads(files['sounds.json'])['sounds']
    out = []
    for rel in sorted(files):
        if rel.startswith('workshop/bench/'):
            part = rel[len('workshop/bench/'):-len('.json')]
            comps = list(json.loads(files[f'workshop/{part}.json'])['components'])
            out.append((part, files[rel].decode(), comps, sounds))
    return out


# ---------------------------------------------------------------- a synthetic kind: a small pump on the bench

GADGET_COMPS = ['casing', 'rotor', 'valve', 'gauge']


def gadget():
    """Every node kind a bench may hold (format 1's and hold), a machine with a sequence and a trip, an interlock,
    alarms, ops with permissives, faults with and without a component, each binding kind."""
    return {
        'format': 'walkdown-plant-bench', 'version': 1, 'part': 'test_gadget',
        'sources': [{'id': 'none', 'cite': 'A synthetic kind for the vectors only', 'url': 'https://example.org/'}],
        'values': [
            ['valve_cmd', {'state': 0, 'unit': '%'}],
            ['lube', {'state': 1}],
            ['run', {'state': 0}],
            ['seized', {'state': 0}],
            ['boost', {'state': 1}],
            ['ambient', {'const': 20, 'unit': '°C'}],
            ['drive_cmd', {'product': ['run', 'boost']}],
            ['drive', {'select': 'seized', 'cases': ['drive_cmd', 0]}],
            ['speed', {'ramp': 'drive', 'rate': 0.5, 'rate_down': 0.25, 'unit': 'rpm'}],
            ['valve_frac', {'lag': 'valve_cmd', 'tau': 0.5, 'tau_down': 1.0}],
            ['flow', {'product': ['speed', 'valve_frac']}],
            ['rise', {'of': 'speed', 'table': [[0, 0], [1, 40]]}],
            ['heat', {'sum': ['ambient', 'rise']}],
            ['temp', {'lag': 'heat', 'tau': 2.0}],
            ['vol', {'integrate': 'flow', 'gain': 2, 'min': 0, 'max': 50}],
            ['hot', {'cmp': ['temp', '>=', 45]}],
            ['cool', {'cmp': ['temp', '<', 30]}],
            ['hot_latch', {'latch': 'hot', 'reset': 'cool'}],
            ['closedish', {'cmp': ['valve_frac', '<', 0.1]}],
            ['low_flow', {'and': ['run', 'closedish']}],
            ['slow', {'delay': 'low_flow', 'on': 0.5, 'off': 0.3}],
            ['t_run', {'timer': 'run'}],
            ['angle', {'wrap': 'speed', 'period': 1}],
            ['peak', {'max': ['speed', 'valve_frac']}],
            ['least', {'min': ['speed', 'valve_frac']}],
            ['gap', {'diff': ['speed', 'valve_frac']}],
            ['either', {'or': ['hot', 'slow']}],
            ['still', {'not': 'run'}],
            ['frozen', {'hold': 'flow', 'when': 'seized'}],
            ['over', {'cmp': ['speed', '>', 1.05]}],
            ['still_dry', {'not': 'lube'}],
            ['no_lube_run', {'and': ['run', 'still_dry']}],
            ['spun', {'cmp': ['speed', '>=', 0.9]}],
        ],
        'ops': [
            {'at': 'valve', 'do': 'set', 'input': 'valve_cmd', 'range': [0, 1], 'title': 'Valve'},
            {'at': 'rotor', 'do': 'start', 'machine': 'drive_m', 'title': 'Start',
             'needs': [['lube', 'The bearings need oil first']]},
            {'at': 'rotor', 'do': 'stop', 'machine': 'drive_m', 'title': 'Stop'},
            {'at': 'casing', 'do': 'reset', 'trip': 'overspeed'},
            {'at': 'bench', 'do': 'open', 'set': {'lube': 1}},
            {'at': 'bench', 'do': 'close', 'set': {'lube': 0}},
        ],
        'interlocks': [{'id': 'no_oil', 'at': 'rotor', 'when': 'no_lube_run', 'do': [{'machine': 'drive_m',
                                                                                         'to': 'stopped'}],
                        'text': 'Stopped: no oil'}],
        'machines': [{'id': 'drive_m', 'at': 'rotor', 'init': 'stopped',
                      'commands': {'start': {'from': ['stopped'], 'to': 'starting'}, 'stop': {'from': '*',
                                                                                                'to': 'stopped'}},
                      'states': [{'id': 'stopped', 'set': {'run': 0}},
                                 {'id': 'starting', 'set': {'run': 1}, 'next': [['spun', 'running']],
                                  'say': 'Running up'},
                                 {'id': 'running', 'watch': False}]}],
        'trips': [{'id': 'overspeed', 'at': 'casing', 'text': 'Overspeed', 'when': 'over', 'delay': 0.2,
                   'do': [{'machine': 'drive_m', 'to': 'stopped'}], 'isa': 'SZ'}],
        'alarms': [{'id': 'hot_a', 'at': 'casing', 'where': 'gauge', 'when': 'hot_latch', 'priority': 2,
                    'text': 'Casing hot', 'clear': 'cool'},
                   {'id': 'slow_a', 'at': 'valve', 'where': 'valve', 'when': 'slow', 'priority': 3,
                    'text': 'Low flow', 'delay': 0.3}],
        'faults': [{'id': 'runaway', 'at': 'rotor', 'text': 'Governor runs away', 'set': {'boost': 1.2},
                    'repair': {'boost': 1}},
                   {'id': 'seize', 'at': 'rotor', 'text': 'Rotor seized', 'set': {'seized': 1}, 'repair': {'seized': 0}},
                   {'id': 'leak', 'text': 'Oil leak', 'set': {'lube': 0}}],
        'start': {'valve_cmd': 0.2, 'temp': 20},
        'bind': [
            {'at': 'rotor', 'anim': 'spin', 'of': 'speed', 'scale': 2},
            {'at': 'gauge', 'show': 'temp', 'lit': 'run'},
            {'at': 'gauge', 'show': 'flow'},
            {'at': 'bench', 'sound': 'pump_hum', 'gain': {'of': 'speed', 'table': [[0, 0], [1, 1]]}},
            {'at': 'casing', 'lamp': 'running', 'of': 'run'},
            {'flow': 'outlet', 'of': 'flow', 'speed': 0.5, 'colour': 'heat', 'by': 'temp'},
            {'flow': 'inlet', 'of': 'flow', 'speed': 0.5},
            {'at': 'casing', 'heat': 'temp'},
            {'at': 'valve', 'pressure': 'flow'},
        ],
        'legends': {'heat': {'unit': '°C', 'table': [[20, '#2c7bb6'], [60, '#d7191c']]},
                    'pressure': {'unit': 'bar', 'table': [[0, '#2c7bb6'], [1, '#d7191c']]}},
        'readouts': ['speed', 'flow', 'temp', 'vol'],
        'mirror': [{'value': 'valve_cmd', 'from': {'bind': 'anim', 'channel': 'stem'}},
                   {'value': 'drive_m_state', 'from': {'machine': True, 'else': 'stopped'}},
                   {'value': 'temp', 'from': {'bind': 'show'}},
                   {'value': 'lube', 'from': {'bind': 'lamp', 'kind': 'running'}},
                   {'value': 'speed', 'from': {'bind': 'sound', 'id': 'pump_hum'}}],
    }


def gadget_ok():
    return gadget()


GADGET_SOUNDS = [{'id': 'pump_hum'}]


def gadget_inputs():
    """(step, kind, …) inputs as the plant vectors' (ref/make_plant3d_vectors.apply)."""
    return [
        [2, 'op', 'rotor', 'start', None, None],
        [3, 'op', 'valve', 'set', 2, None],             # outside its range: refused
        [3, 'op', 'valve', 'set', 0.8, None],
        [4, 'op', 'pump', 'start', None, None],          # no such op
        [25, 'fault', 'runaway'],
        [33, 'repair', 'runaway'],
        [34, 'op', 'casing', 'reset', None, 'overspeed'],
        [36, 'op', 'rotor', 'start', None, None],
        [40, 'fault', 'seize'],
        [45, 'op', 'casing', 'reset', None, 'overspeed'],
        [60, 'repair', 'seize'],
        [61, 'op', 'valve', 'set', 0.05, None],
        [80, 'ack', 'slow_a'],
        [90, 'op', 'bench', 'close', None, None],        # the oil off: the interlock stops it
        [95, 'op', 'rotor', 'start', None, None],         # refused: no oil
        [100, 'op', 'bench', 'open', None, None],
        [101, 'op', 'rotor', 'start', None, None],
        [140, 'fault', 'leak'],
        [150, 'op', 'rotor', 'stop', None, None],
        [151, 'ack', 'hot_a'],
    ]


def gadget_mirror_inputs():
    """The mirror (WORKSHOP.md §6.5) on the synthetic kind: the machine entered into the plant's state with its
    `set`, values written over step 2's (a lag, a ramp, a state), what the model doesn't have left out; the plant's
    values followed (a session) up to an overspeed whose trip can't stop the mirrored machine, a command refused by
    it, the machine's own sequence not taken while mirrored; the mirror ended, the machine its own again."""
    return [
        [3, 'mirror', {'valve_cmd': 0.6, 'speed': 0.5, 'temp': 40, 'nothing': 1, 'lube': 'x'},
         {'drive_m': 'starting', 'pump_m': 'running'}],
        [20, 'mirror', {'valve_cmd': 0.6, 'speed': 0.95, 'temp': 52}, {'drive_m': 'starting'}],
        [30, 'mirror', {'valve_cmd': 0.6, 'speed': 1.2, 'temp': 58}, {'drive_m': 'running'}],
        [35, 'op', 'rotor', 'stop', None, None],          # a command on the mirrored machine: not taken
        [50, 'mirror', {'speed': 1.0, 'temp': 30.5}, {'drive_m': 'stopped'}],
        [70, 'mirror', {}, {}],                           # the mirror ended: the bench its own again
        [72, 'op', 'casing', 'reset', None, 'overspeed'],
        [74, 'op', 'rotor', 'start', None, None],
    ]


def transmitter_mirror_inputs():
    """The transmitter mirrored from the plant (§6.5): a show's pressure and the loop supply's `else` state (no plant
    machine runs a transmitter), then a condenser's vacuum in kPa(a) made gauge bar."""
    return [
        [1, 'mirror', {'p_applied': 6.5}, {'supply': 'on'}],
        [60, 'mirror', {'p_applied': -0.92125}, {'supply': 'on'}],       # (9.2 kPa(a): 0.092 − 1.01325 bar)
    ]


def turbine_mirror_inputs(part):
    """A turbine mirrored mid-run (§6.5): the plant's sequence state and the shaft's speed, then its trip and coast."""
    state = {'steam_turbine': 'accel', 'gas_turbine': 'accel'}[part]
    vals = {'speed': 0.6, 'flow': 30.0} if part == 'steam_turbine' else {'speed': 0.6}
    return [
        [1, 'mirror', vals, {'turbine': state}],
        [80, 'mirror', dict(vals, speed=0.55), {'turbine': 'coastdown'}],
        [81, 'op', 'rotor', 'roll' if part == 'steam_turbine' else 'start', None, None],    # not taken: mirrored
    ]


def transmitter_inputs():
    """The transmitter's run (WORKSHOP.md §6.4): the supply on, the pressure up the range and past it, each fault and
    its repair, the supply off."""
    at, tb = 'process_flange', 'terminal_block'
    return [
        [3, 'op', at, 'set', 5, None],                   # unpowered: the diaphragm moves, the display stays dark
        [20, 'op', tb, 'start', None, None],
        [21, 'op', tb, 'start', None, None],              # already on: refused
        [40, 'op', at, 'set', 10, None],
        [70, 'op', at, 'set', 12, None],                  # past the upper range: 20.5 mA
        [100, 'ack', 'sat_high'],
        [101, 'op', at, 'set', 13, None],                 # outside the slider's range: refused
        [110, 'op', at, 'set', -1, None],                 # vacuum: 3.8 mA
        [140, 'op', at, 'set', 4, None],
        [170, 'fault', 'impulse_blocked'],
        [172, 'op', at, 'set', 8, None],                  # the reading holds what was trapped
        [200, 'repair', 'impulse_blocked'],
        [230, 'fault', 'over_range'],
        [260, 'repair', 'over_range'],
        [290, 'fault', 'loop_open'],
        [300, 'ack', 'loop_dead'],
        [320, 'repair', 'loop_open'],
        [350, 'op', tb, 'stop', None, None],
    ]


def turbine_inputs():
    """The steam turbine's run from its committed file (WORKSHOP.md §6.3, K4b): rolled to 800 rpm (the commands its
    state refuses on the way), a rub's vibration tripping it in its soak, the alarms acknowledged, the trip's reset
    refused while it stands and taken once repaired, the coast down."""
    r, b, pf = 'rotor', 'bench', 'pedestal_f'
    return [
        [1, 'op', r, 'roll', None, None],
        [2, 'op', r, 'roll', None, None],                  # already rolling: refused
        [50, 'op', r, 'hold', None, None],                 # hold is taken while accelerating only: refused
        [60, 'op', b, 'start', None, None],                # excitation below 95 % speed: refused
        [70, 'op', pf, 'set', 0.05, None],                 # the speed bias past its range: refused
        [80, 'op', 'valve_l', 'set', 120, None],           # the steam pressure up: the stage pressures follow
        [700, 'fault', 'rub'],
        [760, 'ack', 'vib1_h'],
        [770, 'op', 'brg_f_upper', 'reset', None, 'trip_vib'],   # the vibration still high: refused
        [780, 'repair', 'rub'],
        [820, 'op', 'brg_f_upper', 'reset', None, 'trip_vib'],
        [830, 'op', r, 'roll', None, None],                # still coasting down: refused
        [840, 'fault', 'lube_pump'],
    ]


def short_soak(bench_text):
    """The committed turbine with its soak at 800 rpm cut from the plant's 300 s to 10 s (the vector's only change):
    the run up, the critical speeds, synchronising and load within a vector's length."""
    d = json.loads(bench_text)
    for v in d['values']:
        if v[0] == 'soak_done':
            assert v[1]['cmp'][0] == 'soak_t' and v[1]['cmp'][2] == 300, v
            v[1]['cmp'][2] = 10
    return text(d)


def turbine_sync_inputs(bench_text, comps, sounds):
    """Rolled with a short soak (short_soak) to full speed; the excitation on at 95 %; a small speed bias slips the
    phase into the synchronising window and the breaker is tried every 5 steps until it closes (the refusals are
    inputs too); loaded; then the governor's fault at no load overspeeds it to its trip. The steps are found by
    running the reference with the inputs so far (deterministic)."""
    r, b, pf = 'rotor', 'bench', 'pedestal_f'
    inputs = [[1, 'op', r, 'roll', None, None]]

    def until(cond, limit):
        bm = B.check(B.loads(bench_text), comps, 'bench', sounds)
        e = bm.engine()
        ins = sorted(inputs, key=lambda x: x[0])
        i = 0
        while e.step_no < limit:
            while i < len(ins) and ins[i][0] == e.step_no + 1:
                apply(e, ins[i])
                i += 1
            e.step()
            if e.step_no > ins[-1][0] and cond(e):
                return e.step_no
        raise AssertionError('the turbine vector\'s run did not get there')

    n = until(lambda e: e.v('spd95') >= 0.5, 4000)
    inputs += [[n + 1, 'op', b, 'start', None, None], [n + 2, 'op', pf, 'set', 0.002, None]]
    k = until(lambda e: e.v('turbine_state') == 4, 4000) + 1
    while True:
        inputs.append([k, 'op', b, 'close_breaker', None, None])
        try:
            until(lambda e: e.v('brk_cmd') >= 0.5, k + 1)
            break
        except AssertionError:
            k += 5
            assert k < 4000, 'the breaker never closed'
    inputs.append([k + 1, 'op', pf, 'set', 0, None])
    inputs += [[k + 150, 'fault', 'rub']]      # tripped on load: the protection opens the breaker too
    return inputs, until(lambda e: e.v('turbine_state') == 8, k + 2000) + 60


def gas_turbine_inputs():
    """The gas turbine's run from its committed file (WORKSHOP.md §6.7, K5b): started (the SFC cranks it to the purge
    speed; the commands its state refuses on the way), the ambient air warmer, the AC lube oil pump lost and the DC
    pump started by the interlock, a rub's vibration tripping it in its purge, the alarm acknowledged, the trip's reset
    refused while it stands and taken once repaired, a start refused while it coasts, the fuel gas's pressure low."""
    r, b, h = 'rotor', 'bench', 'brg1_housing'
    return [
        [1, 'op', r, 'start', None, None],
        [2, 'op', r, 'start', None, None],                 # already starting: refused
        [60, 'op', b, 'start', None, None],                # excitation below 95 % speed: refused
        [70, 'op', b, 'close_breaker', None, None],        # not at full speed no load: refused
        [80, 'op', 'intake', 'set', 40, None],             # the ambient air warmer: the compressor's air too
        [100, 'op', h, 'set', 0.05, None],                 # the speed bias past its range: refused
        [200, 'fault', 'lube_pump'],                       # the DC emergency pump takes over (the interlock)
        [260, 'repair', 'lube_pump'],
        [510, 'fault', 'rub'],                             # (in the purge, which began at step 490)
        [550, 'ack', 'vib2_h'],
        [560, 'op', 'brg1_upper', 'reset', None, 'trip_vib'],    # the vibration still high: refused
        [570, 'repair', 'rub'],
        [600, 'op', 'brg1_upper', 'reset', None, 'trip_vib'],
        [610, 'op', r, 'start', None, None],               # still coasting down: refused
        [640, 'fault', 'gas_low'],
    ]


def short_purge(bench_text):
    """The committed gas turbine with the HRSG's purge cut from the plant's 480 s to 10 s (the vector's only change):
    ignition, the run-up, synchronising and load within a vector's length."""
    d = json.loads(bench_text)
    for v in d['values']:
        if v[0] == 'purge_done':
            assert v[1]['cmp'][0] == 'purge_t' and v[1]['cmp'][2] == 480, v
            v[1]['cmp'][2] = 10
    return text(d)


def gas_turbine_sync_inputs(bench_text, comps, sounds):
    """Started with a short purge (short_purge): cranked, purged, coasted to ignition speed, fired, run up to full
    speed; the excitation on at 95 %; a small speed bias slips the phase into the synchronising window and the
    breaker is tried every 5 steps at full speed no load until it closes (the refusals are inputs too); loaded towards
    100 MW; then the flame lost on load trips it and the protection opens the breaker. The inputs are found in one run
    of the reference, each made as it is chosen (deterministic)."""
    r, b, h = 'rotor', 'bench', 'brg1_housing'
    e = B.check(B.loads(bench_text), comps, 'bench', sounds).engine()
    inputs = []

    def do(*item):
        x = [e.step_no + 1] + list(item)
        inputs.append(x)
        apply(e, x)

    do('op', r, 'start', None, None)
    exc = closed = trip = None
    while True:
        if exc is None and e.step_no > 1 and e.v('spd95') >= 0.5:
            do('op', b, 'start', None, None)
            exc = e.step_no + 1
        elif exc is not None and e.step_no == exc:
            do('op', h, 'set', 0.001, None)
        elif closed is None and e.v('turbine_state') == 7 and e.step_no % 5 == 0:
            do('op', b, 'close_breaker', None, None)
        if closed is None and e.v('brk_cmd') >= 0.5:
            closed = e.step_no
            do('op', h, 'set', 0, None)
        elif closed is not None and e.step_no == closed + 1:
            do('op', b, 'set', 100, None)
        elif closed is not None and e.step_no == closed + 100:
            do('fault', 'flameout')
        if trip is None and e.v('turbine_state') == 10:
            trip = e.step_no
        if trip is not None and e.step_no >= trip + 30:
            return inputs, e.step_no
        assert e.step_no < 6000, 'the gas turbine vector\'s run did not get there'
        e.step()


def run(bench_text, comps, sounds, inputs, until):
    bm = B.check(B.loads(bench_text), comps, 'bench', sounds)
    e = bm.engine()
    states = [e.snapshot()]
    inputs = sorted(inputs, key=lambda x: x[0])
    i = 0
    while e.step_no < until:
        while i < len(inputs) and inputs[i][0] == e.step_no + 1:
            apply(e, inputs[i])
            i += 1
        e.step()
        states.append(e.snapshot())
    assert i == len(inputs), 'inputs after the end'
    return states, e.events


# ---------------------------------------------------------------- rejects (each on the synthetic kind)

def _set(path, value):
    def f(g):
        node = g
        for k in path[:-1]:
            node = node[k]
        node[path[-1]] = value
    return f


def _do(fn):
    return fn


REJECTS = [
    ('the format name', 'bad_format', _set(['format'], 'walkdown-plant-model')),
    ('version 2', 'bad_version', _set(['version'], 2)),
    ('an unknown top-level key', 'unknown_key', _set(['isolations'], [])),
    ('no sources', 'missing_key', lambda g: g.pop('sources')),
    ('a source over http', 'bad_value', _set(['sources', 0, 'url'], 'http://example.org/')),
    ('no values', 'bad_length', _set(['values'], [])),
    ('an op naming a code', 'unknown_key', _set(['ops', 0, 'kks'], '10LAC10AP001')),
    ('an op at no component', 'bad_ref', _set(['ops', 0, 'at'], 'impeller')),
    ('an op with a where', 'unknown_key', _set(['ops', 0, 'where'], ['local'])),
    ('a title over 40 characters', 'bad_type', _set(['ops', 0, 'title'], 'x' * 41)),
    ('a set op without its range', 'missing_key', lambda g: g['ops'][0].pop('range')),
    ('two ops alike', 'dup_id', lambda g: g['ops'].append(dict(g['ops'][2]))),
    ('a machine at no component', 'bad_ref', _set(['machines', 0, 'at'], 'motor')),
    ('a machine without at', 'missing_key', lambda g: g['machines'][0].pop('at')),
    ('an alarm where no component is', 'bad_ref', _set(['alarms', 0, 'where'], 'panel')),
    ('a trip at no component', 'bad_ref', _set(['trips', 0, 'at'], 'motor')),
    ('a draw node (version 2 of the bench)', 'bad_kind', _set(['values', 5], ['ambient', {'draw': [[0, 1], [1, 2]]}])),
    ('a wear node', 'bad_kind', _set(['values', 5], ['ambient', {'wear': 1, 'max': 2}])),
    ('a value with a code', 'unknown_key', _set(['values', 0, 1, 'kks'], '10LAC10AP001')),
    ('a read of no value', 'bad_ref', _set(['values', 10], ['flow', {'product': ['speed', 'nothing']}])),
    ('a fault writing a computed value', 'bad_ref', _set(['faults', 1, 'set'], {'speed': 1})),
    ('a fault at no component', 'bad_ref', _set(['faults', 1, 'at'], 'motor')),
    ('a fault with when', 'unknown_key', _set(['faults', 1, 'when'], 'hot')),
    ('two faults alike', 'dup_id', lambda g: g['faults'].append(dict(g['faults'][1]))),
    ('a start of a computed value', 'bad_ref', _set(['start', 'flow'], 1)),
    ('a start of a timer', 'bad_ref', _set(['start', 't_run'], 1)),
    ('a binding at no component', 'bad_ref', _set(['bind', 1, 'at'], 'dial')),
    ('a binding naming a code', 'unknown_key', _set(['bind', 1, 'kks'], '10LAC10AP001')),
    ('two binding kinds in one', 'bad_kind', _set(['bind', 1, 'lamp'], 'running')),
    ('an anim at the bench', 'bad_ref', _set(['bind', 0, 'at'], 'bench')),
    ('a show of no value', 'bad_ref', _set(['bind', 1, 'show'], 'nothing')),
    ('a lamp of no kind', 'bad_value', _set(['bind', 4, 'lamp'], 'green')),
    ('no such sound', 'bad_ref', _set(['bind', 3, 'sound'], 'siren')),
    ('a flow path bound twice', 'dup_id', _set(['bind', 6, 'flow'], 'outlet')),
    ('a flow colour without its value', 'missing_key', lambda g: g['bind'][5].pop('by')),
    ('a flow colour of no legend', 'bad_ref', _set(['bind', 5, 'colour'], 'flame')),
    ('a heat binding without its legend', 'bad_ref', lambda g: g['legends'].pop('heat') and
     g['bind'][5].update({'colour': 'pressure'})),
    ('a legend not increasing', 'bad_number', _set(['legends', 'heat', 'table'], [[60, '#2c7bb6'], [20, '#d7191c']])),
    ('a legend colour not #rrggbb', 'bad_value', _set(['legends', 'heat', 'table', 0, 1], 'blue')),
    ('a readout twice', 'dup_id', _set(['readouts'], ['speed', 'speed'])),
    ('a readout of no value', 'bad_ref', _set(['readouts'], ['nothing'])),
    ('over 12 readouts', 'limit', lambda g: g.update(readouts=[v[0] for v in g['values'][:13]])),
    ('over 48 ops', 'limit', lambda g: g.update(ops=[{'at': 'bench', 'do': 'open', 'set': {'lube': 1}}] * 49)),
    ('over 24 faults', 'limit', lambda g: g.update(faults=[dict(g['faults'][2], id=f'f{i}') for i in range(25)])),
    ('over 128 bindings', 'limit', lambda g: g.update(bind=[g['bind'][2]] * 129)),
    ('a value with a clock value\'s name', 'dup_id', _set(['values', 1], ['world_hour', {'state': 1}])),
    ('two lit values on one face', 'bad_value', lambda g: g['bind'].append({'at': 'gauge', 'show': 'vol', 'lit': 'still'})),
    ('two anims on one component', 'dup_id', lambda g: g['bind'].append({'at': 'rotor', 'anim': 'spin', 'of': 'flow'})),
    ('a mirror of no value', 'bad_ref', _set(['mirror', 0, 'value'], 'nothing')),
    ('a mirror from no binding kind', 'bad_value', _set(['mirror', 0, 'from'], {'bind': 'shake'})),
    ('a mirror from an anim without its channel', 'missing_key', _set(['mirror', 0, 'from'], {'bind': 'anim'})),
    ('a machine mirrored into a plain value', 'bad_ref', _set(['mirror', 1, 'value'], 'run')),
    ('a machine mirror\'s else no state of it', 'bad_ref', _set(['mirror', 1, 'from', 'else'], 'flying')),
    ('a machine mirror with another key', 'unknown_key', _set(['mirror', 1, 'from', 'channel'], 'shaft')),
    ('a mirror of a stateless node', 'bad_kind', _set(['mirror', 2, 'value'], 'flow')),
    ('a mirror of a timer', 'bad_kind', _set(['mirror', 2, 'value'], 't_run')),
    ('a mirror of a constant', 'bad_kind', _set(['mirror', 2, 'value'], 'ambient')),
    ('a value mirrored twice', 'dup_id', lambda g: g['mirror'].append({'value': 'temp', 'from': {'bind': 'show'}})),
    ('a machine mirrored twice', 'dup_id', lambda g: g['mirror'].append(dict(g['mirror'][1]))),
]
COMPONENT_REJECTS = [
    ('a component called bench', 'bad_id', GADGET_COMPS + ['bench']),
]


def rejects():
    out = []
    base = gadget_ok()
    for why, code, change in REJECTS:
        g = copy.deepcopy(base)
        change(g)
        out.append({'why': why, 'code': code, 'components': GADGET_COMPS, 'bench': text(g)})
    for why, code, comps in COMPONENT_REJECTS:
        out.append({'why': why, 'code': code, 'components': comps, 'bench': text(base)})
    out.append({'why': 'a duplicate key', 'code': 'bad_json', 'components': GADGET_COMPS,
                'bench': '{"format": "walkdown-plant-bench", "format": "x"}'})
    for item in out:          # each is refused with its code
        try:
            B.check(B.loads(item['bench']), item['components'], 'bench', GADGET_SOUNDS)
        except FormatError as x:
            assert x.code == item['code'], f'{item["why"]}: {x.code} ({x}), expected {item["code"]}'
        else:
            raise AssertionError(f'{item["why"]}: passed')
    return out


def build():
    valid, steps = [], []
    for part, t, comps, sounds in committed():
        valid.append({'why': f'the committed {part}', 'components': comps, 'bench': t})
        if part == 'pressure_transmitter':
            states, events = run(t, comps, sounds, transmitter_inputs(), 380)
            steps.append({'why': 'the pressure transmitter: the supply, the range and past it, each fault and its '
                                 'repair', 'components': comps, 'bench': t, 'inputs': transmitter_inputs(),
                          'states': states, 'events': events})
            states, events = run(t, comps, sounds, transmitter_mirror_inputs(), 100)
            steps.append({'why': 'the pressure transmitter mirrored: a pressure and the supply\'s else state, then a '
                                 'vacuum', 'components': comps, 'bench': t, 'inputs': transmitter_mirror_inputs(),
                          'states': states, 'events': events})
        if part == 'steam_turbine':
            ins = turbine_mirror_inputs(part)
            states, events = run(t, comps, sounds, ins, 120)
            steps.append({'why': f'the {part.replace("_", " ")} mirrored: its sequence\'s state and its speed, '
                                 'then its coast, a command not taken', 'components': comps, 'bench': t,
                          'inputs': ins, 'states': states, 'events': events})
            states, events = run(t, comps, sounds, turbine_inputs(), 900)
            steps.append({'why': 'the steam turbine: rolled to its soak, refusals, a rub\'s vibration trip, its reset, '
                                 'the lube oil lost', 'components': comps, 'bench': t, 'inputs': turbine_inputs(),
                          'states': states, 'events': events})
            t2 = short_soak(t)
            ins, end = turbine_sync_inputs(t2, comps, sounds)
            states, events = run(t2, comps, sounds, ins, end)
            steps.append({'why': 'the steam turbine with a 10 s soak: run up through its critical speeds, '
                                 'synchronised, loaded, tripped on load by a rub (the breaker opened by protection)',
                          'components': comps, 'bench': t2, 'inputs': ins, 'states': states, 'events': events})
        if part == 'gas_turbine':
            ins = turbine_mirror_inputs(part)
            states, events = run(t, comps, sounds, ins, 120)
            steps.append({'why': f'the {part.replace("_", " ")} mirrored: its sequence\'s state and its speed, '
                                 'then its coast, a command not taken', 'components': comps, 'bench': t,
                          'inputs': ins, 'states': states, 'events': events})
            states, events = run(t, comps, sounds, gas_turbine_inputs(), 680)
            steps.append({'why': 'the gas turbine: cranked to its purge, refusals, the AC oil pump lost and the DC pump '
                                 'started, a rub\'s vibration trip, its reset, the fuel gas low',
                          'components': comps, 'bench': t, 'inputs': gas_turbine_inputs(), 'states': states,
                          'events': events})
            t2 = short_purge(t)
            ins, end = gas_turbine_sync_inputs(t2, comps, sounds)
            states, events = run(t2, comps, sounds, ins, end)
            steps.append({'why': 'the gas turbine with a 10 s purge: fired, run up, synchronised, loaded, tripped on '
                                 'load by a flame-out (the breaker opened by protection)',
                          'components': comps, 'bench': t2, 'inputs': ins, 'states': states, 'events': events})
    g = text(gadget_ok())
    valid.append({'why': 'the synthetic kind', 'components': GADGET_COMPS, 'bench': g})
    states, events = run(g, GADGET_COMPS, GADGET_SOUNDS, gadget_inputs(), 170)
    steps.append({'why': 'the synthetic kind: every node kind, a machine, its trip and interlock, alarms, faults',
                  'components': GADGET_COMPS, 'bench': g, 'inputs': gadget_inputs(), 'states': states,
                  'events': events})
    states, events = run(g, GADGET_COMPS, GADGET_SOUNDS, gadget_mirror_inputs(), 110)
    steps.append({'why': 'the synthetic kind mirrored: a machine and values written after step 2, followed live, a trip '
                         'and a command that can\'t move the mirrored machine, the mirror ended',
                  'components': GADGET_COMPS, 'bench': g, 'inputs': gadget_mirror_inputs(), 'states': states,
                  'events': events})
    return {'about': 'Walkdown Plant Workshop bench format vectors (docs/plant3d/WORKSHOP.md §6.2), made by '
                     'ref/make_plant3d_bench_vectors.py from ref/plant3d_bench.py and ref/plant3d.py. Numbers '
                     'compare to 1e-6.',
            'sounds': GADGET_SOUNDS, 'valid': valid, 'reject': rejects(), 'steps': steps}


def dump(v):
    return json.dumps(R(v), ensure_ascii=False, separators=(',', ':')) + '\n'


if __name__ == '__main__':
    t = dump(build())
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(t)
        print(f'wrote {OUT}: {len(t)} bytes')
    else:
        same = os.path.exists(OUT) and open(OUT, encoding='utf-8').read() == t
        print(f'{OUT}: ' + ('up to date' if same else 'differs (run with --write)'))
        sys.exit(0 if same else 1)
