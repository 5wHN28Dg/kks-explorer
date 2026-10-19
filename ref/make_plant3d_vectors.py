#!/usr/bin/env python3
"""Generate ref/vectors/plant3d-v1.json: test vectors for the Walkdown Plant content format (docs/PLANT3D.md §12).

  valid, reject  a small synthetic plant ({relative path: file text}), and changes to it that each break one rule
                 (`change`: the files replaced, null for a file removed)
  steps          small synthetic models stepped by events, the expected state after every step
  train          the first train (data/plant3d): the cold start run by its procedure (the inputs at the steps they
                 take effect, every event, a full snapshot every 10 min of model time) and forks from it that make
                 each trip and interlock fire and each wrong operator action be refused or alarmed

FROZEN once the app's evaluator uses it (PLANT3D §12): a change of format or model makes a new file.
  python3 ref/make_plant3d_vectors.py [--write]"""
import copy, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ref import plant3d as P

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v1.json')
DATA = os.path.join(ROOT, 'data', 'plant3d')
SNAP_EVERY = 6000           # model steps between full snapshots of the cold start (10 min)


def R(x):
    """Round floats for the file (readers compare to 1e-6)."""
    if isinstance(x, float):
        r = round(x, 9)
        return 0.0 if r == 0 else r
    if isinstance(x, list):
        return [R(v) for v in x]
    if isinstance(x, dict):
        return {k: R(v) for k, v in x.items()}
    return x


# ================================================================ the synthetic plant

def mini():
    kit = {'format': 'walkdown-plant-kit', 'version': 1, 'dn_od_mm': [[50, 60.3], [100, 114.3], [200, 219.1]],
           'parts': {
               'pump_horizontal': {'group': 'rotating',
                                   'params': {'flow_m3h': {'type': 'num', 'min': 0.1, 'max': 5000, 'default': 50},
                                              'length': {'type': 'num', 'min': 1, 'max': 6, 'default': 2}},
                                   'nozzles': {'suction': {'at': [0, ['length', 0.5, 0], 0.6], 'dir': 'n'},
                                               'discharge': {'at': [0, ['length', 0.25, 0], 1.4], 'dir': 'up'}},
                                   'anim': ['shaft'], 'plates': ['motor_side']},
               'tank_vertical': {'group': 'vessels',
                                 'params': {'d': {'type': 'num', 'min': 0.5, 'max': 40, 'default': 4},
                                            'height': {'type': 'num', 'min': 1, 'max': 30, 'default': 6}},
                                 'nozzles': {'inlet': {'at': [0, ['d', -0.5, -0.3], ['height', 0.9, 0]], 'dir': 's'},
                                             'outlet': {'at': [0, ['d', 0.5, 0.3], 0.5], 'dir': 'n'}},
                                 'plates': ['side']},
               'valve_gate': {'group': 'valves', 'params': {'dn': {'type': 'int', 'min': 6, 'max': 4000, 'default': 100}},
                              'anim': ['stem'], 'plates': ['body'], 'inline': True},
               'pressure_gauge': {'group': 'instruments',
                                  'params': {'range': {'type': 'pair', 'default': [0, 10]}},
                                  'anim': ['needle'], 'inline': True},
               'platform': {'group': 'structures', 'params': {'outline': {'type': 'polygon'},
                                                              'openings': {'type': 'polygons', 'default': []}},
                            'walkable': True},
               'stair': {'group': 'structures', 'params': {
                   'foot': {'type': 'xyz'}, 'top': {'type': 'xyz'},
                   'layout': {'type': 'enum', 'values': ['straight', 'switchback'], 'default': 'straight'},
                   'width': {'type': 'num', 'min': 0.6, 'max': 2.5, 'default': 1.0}}, 'walkable': True},
               'ladder': {'group': 'structures', 'params': {
                   'foot': {'type': 'xyz'}, 'top': {'type': 'num', 'min': -30, 'max': 200},
                   'facing': {'type': 'num', 'min': 0, 'max': 360, 'default': 0}}, 'walkable': True},
               'door': {'group': 'structures', 'params': {
                   'kind': {'type': 'enum', 'values': ['personnel', 'roller'], 'default': 'personnel'}}}}}
    plant = {'format': 'walkdown-plant', 'version': 1, 'id': 'mini', 'title': 'A test plant', 'frequency_hz': 50,
             'kks': {'units': {'1': 'Unit 1'}, 'systems': {'LAB': 'Feedwater piping', 'LAC': 'Feedwater pumps'},
                     'equipment': {'AA': 'Valve', 'AP': 'Pump', 'BB': 'Tank', 'BR': 'Pipe'},
                     'measurements': {'CP': 'Pressure'}, 'source': 'test'},
             'media': {'water': {'group': 'water', 'band': '#2e7d32'}},
             'areas': ['a1', 'a2'], 'ext': ['ambient_t'], 'start': {'at': [5, 5, 0], 'yaw': 90}}
    a1 = {'format': 'walkdown-plant-area', 'version': 1, 'id': 'a1', 'title': 'Area 1', 'bounds': [[0, 0], [40, 20]],
          'pack': 'base',
          'equipment': [{'kks': '10LAC10AP001', 'name': 'Pump', 'part': 'pump_horizontal', 'at': [10, 5, 0],
                         'params': {'length': 2}, 'plate': 'motor_side'},
                        {'kks': '10LAB10BB001', 'name': 'Tank', 'part': 'tank_vertical', 'at': [30, 5, 0]}],
          'pipes': [{'kks': '10LAB10BR001', 'name': 'Pump to tank', 'medium': 'water', 'dn': 100,
                     'from': {'kks': '10LAC10AP001', 'nozzle': 'discharge'},
                     'points': [[10, 5.5, 5.4], [10, 1, 5.4], [30, 1, 5.4]],
                     'to': {'kks': '10LAB10BB001', 'nozzle': 'inlet'},
                     'valves': [{'kks': '10LAB10AA001', 'part': 'valve_gate', 'at': 0.5}],
                     'parts': [{'kks': '10LAB10CP501', 'part': 'pressure_gauge', 'at': 0.1, 'side': 'top'}]},
                    {'kks': '10LAB10BR002', 'name': 'Drain', 'medium': 'water', 'dn': 50,
                     'from': {'pipe': '10LAB10BR001', 'at': [20, 1, 5.4]}, 'points': [[20, 1, -1]],
                     'to': {'at': [20, 3, -1]}}],
          'structures': [{'id': 'p1', 'part': 'platform', 'at': [20, 10, 3], 'params': {'outline': [[0, 0], [10, 0],
                                                                                                  [10, 6], [0, 6]]}},
                         {'id': 's1', 'part': 'stair', 'params': {'foot': [16.2, 13, 0], 'top': [20.03, 13, 3]}},
                         {'id': 'l1', 'part': 'ladder', 'params': {'foot': [30.2, 12, 0], 'top': 3, 'facing': 270}},
                         {'id': 'd1', 'part': 'door', 'at': [5, 0, 0], 'yaw': 180}],
          'signs': [{'text': 'Area 1', 'at': [5, 1, 2], 'yaw': 180}]}
    a2 = {'format': 'walkdown-plant-area', 'version': 1, 'id': 'a2', 'title': 'Area 2', 'bounds': [[50, 0], [60, 20]],
          'pack': 'base', 'equipment': [], 'pipes': [], 'structures': [], 'signs': []}
    model = {'format': 'walkdown-plant-model', 'version': 1, 'area': 'a1',
             'values': [['pump_cmd', {'state': 0, 'kks': '10LAC10AP001'}], ['valve_cmd', {'state': 0}],
                        ['flow', {'lag': 'pump_cmd', 'tau': 2}], ['p', {'product': ['flow', 5], 'unit': 'bar',
                                                                         'kks': '10LAB10CP501'}],
                        ['p_high', {'cmp': ['p', '>', 4]}], ['valve_open', {'cmp': ['valve_cmd', '>=', 0.5]}]],
             'ops': [{'kks': '10LAC10AP001', 'do': 'start', 'set': {'pump_cmd': 1},
                      'needs': [['valve_open', 'Valve closed']], 'where': ['local', 'screen']},
                     {'kks': '10LAC10AP001', 'do': 'stop', 'set': {'pump_cmd': 0}, 'where': ['local']},
                     {'kks': '10LAB10AA001', 'do': 'open', 'set': {'valve_cmd': 1}, 'where': ['local']},
                     {'kks': '10LAB10CP501', 'do': 'reset', 'trip': 't1', 'where': ['screen']}],
             'trips': [{'id': 't1', 'kks': '10LAB10CP501', 'text': 'Pressure high', 'when': 'p_high', 'delay': 0.5,
                        'do': [{'set': {'pump_cmd': 0}}], 'first_out': 'g'}],
             'alarms': [{'id': 'a1', 'kks': '10LAB10CP501', 'isa': 'PAH', 'text': 'Pressure high', 'when': 'p_high',
                         'priority': 2.0, 'where': '10LAC10AP001'}],      # 2.0 is 2 to any JSON reader
             'bind': [{'kks': '10LAC10AP001', 'anim': 'shaft', 'of': 'flow', 'scale': 25},
                      {'kks': '10LAB10CP501', 'show': 'p'},
                      {'kks': '10LAC10AP001', 'sound': 'hum', 'gain': {'of': 'flow', 'table': [[0, 0], [1, 1]]}}]}
    scen = {'format': 'walkdown-plant-scenario', 'version': 1, 'id': 's1', 'title': 'Start', 'init': {'ambient_t': 30},
            'faults': [{'id': 'f1', 'set': {'pump_cmd': 0}, 'text': 'Pump trips'}]}
    proc = {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'p1', 'title': 'Start the pump',
            'kind': 'procedure', 'scenario': 's1',
            'steps': [{'id': 'open', 'text': ['Open ', {'link': ['the valve'], 'to': {'kks': '10LAB10AA001'}}, '.'],
                       'at': ['10LAB10AA001'], 'go': 'walk', 'do': [{'kks': '10LAB10AA001', 'do': 'open'}],
                       'done': 'valve_open'},
                      {'id': 'start', 'text': ['Start the pump.'], 'at': ['10LAC10AP001'], 'go': 'walk',
                       'do': [{'kks': '10LAC10AP001', 'do': 'start'}],
                       'why': [{'p': ['See ', {'link': ['the course'], 'to': {'course': 'ppt', 'page': 'pumps'}}]}]}]}
    tour = {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 't1', 'title': 'A tour', 'kind': 'tour',
            'steps': [{'id': 's1', 'text': ['The pump.'], 'at': ['10LAC10AP001'], 'go': 'walk'}]}
    sounds = {'format': 'walkdown-plant-sounds', 'version': 1,
              'sounds': [{'id': 'hum', 'kind': 'synth', 'tones': [{'hz': 100}]}]}
    return {'kit.json': kit, 'plant.json': plant, 'sounds.json': sounds, 'areas/a1.json': a1, 'areas/a2.json': a2,
            'model/a1.json': model, 'scenarios/s1.json': scen, 'procedures/p1.json': proc, 'procedures/t1.json': tour}


def enc(files):
    return {k: (v if isinstance(v, (bytes, str)) else json.dumps(v)).encode() if not isinstance(v, bytes) else v
            for k, v in files.items()}


def check(files):
    return P.check_files(enc(files))


# Each reject: why, the error code, and a change to the synthetic plant (a function of a deep copy).
def _set(path, value):
    def f(F):
        node = F[path[0]]
        for k in path[1:-1]:
            node = node[k]
        node[path[-1]] = value
    return f


def _del(path):
    def f(F):
        node = F[path[0]]
        for k in path[1:-1]:
            node = node[k]
        del node[path[-1]]
    return f


def _app(path, value):
    def f(F):
        node = F[path[0]]
        for k in path[1:]:
            node = node[k]
        node.append(value)
    return f


def _raw(rel, text):
    def f(F):
        F[rel] = text
    return f


def _put(rel, obj):
    def f(F):
        F[rel] = obj
    return f


def _all(*changes):
    def f(F):
        for c in changes:
            c(F)
    return f


A2_MODEL = {'format': 'walkdown-plant-model', 'version': 1, 'area': 'a2'}
EQ = ['areas/a1.json', 'equipment']
PIPE = ['areas/a1.json', 'pipes', 0]
ST = ['areas/a1.json', 'structures']
MOD = ['model/a1.json']
REJECTS = [
    ('a duplicate key', 'bad_json', _raw('plant.json', '{"format": "walkdown-plant", "format": "x"}')),
    ('a trailing comma', 'bad_json', _raw('sounds.json', '{"format": "walkdown-plant-sounds", "version": 1, '
                                                         '"sounds": [],}')),
    ('an unknown key', 'unknown_key', _set(['plant.json', 'colour'], 'red')),
    ('a missing key', 'missing_key', _del(['plant.json', 'start'])),
    ('the wrong format name', 'bad_format', _set(['areas/a1.json', 'format'], 'walkdown-plant-model')),
    ('version 2', 'bad_version', _set(['model/a1.json', 'version'], 2)),
    ('a file outside the layout', 'unknown_key', _raw('extra.json', '{}')),
    ('an area file not listed in plant.json', 'bad_ref', _set(['plant.json', 'areas'], ['a1'])),
    ('a code used twice', 'dup_id', _set(EQ + [1, 'kks'], '10LAC10AP001')),
    ('a code with the letter I', 'bad_kks', _set(EQ + [0, 'kks'], '10LIC10AP001')),
    ('a code without F0', 'bad_kks', _set(EQ + [0, 'kks'], '1LAC10AP001')),
    ('a system not in the plant\'s key', 'bad_kks', _set(EQ + [0, 'kks'], '10LCB10AP001')),
    ('an equipment code not in the key', 'bad_kks', _set(EQ + [0, 'kks'], '10LAC10AN001')),
    ('a measurement code in the equipment table', 'bad_kks', _set(['plant.json', 'kks', 'equipment', 'CP'], 'x')),
    ('an unknown kit part', 'bad_ref', _set(EQ + [0, 'part'], 'pump_magic')),
    ('an unknown parameter', 'unknown_key', _set(EQ + [0, 'params'], {'colour': 1})),
    ('a parameter out of range', 'bad_number', _set(EQ + [0, 'params'], {'length': 99})),
    ('a missing required parameter', 'missing_key', _del(ST + [0, 'params', 'outline'])),
    ('a plate point the part lacks', 'bad_ref', _set(EQ + [0, 'plate'], 'roof')),
    ('equipment outside its area', 'outside_area', _set(EQ + [1, 'at'], [45, 5, 0])),
    ('a structure outline outside its area', 'outside_area', _set(ST + [0, 'at'], [35, 10, 3])),
    ('a sign outside its area', 'outside_area', _set(['areas/a1.json', 'signs', 0, 'at'], [5, 25, 2])),
    ('overlapping areas', 'area_overlap', _set(['areas/a2.json', 'bounds'], [[35, 0], [60, 20]])),
    ('a pipe ending on no equipment', 'bad_ref', _set(PIPE + ['to', 'kks'], '10LAB10BB002')),
    ('a pipe ending on a nozzle the part lacks', 'bad_ref', _set(PIPE + ['to', 'nozzle'], 'manhole')),
    ('a free pipe end above ground', 'bad_route', _set(['areas/a1.json', 'pipes', 1, 'to', 'at'], [20, 3, 1])),
    ('a junction off the other pipe\'s route', 'bad_route',
     _set(['areas/a1.json', 'pipes', 1, 'from', 'at'], [20, 2, 5.4])),
    ('a junction on a pipe that does not exist', 'bad_ref',
     _set(['areas/a1.json', 'pipes', 1, 'from', 'pipe'], '10LAB10BR009')),
    ('a route leaving its nozzle at an angle', 'bad_route', _set(PIPE + ['points', 0], [10.5, 5.5, 5.4])),
    ('a bend that does not fit', 'bad_route', _set(PIPE + ['points'], [[10, 5.5, 5.4], [10, 1, 5.4],
                                                                     [10.1, 1, 5.4], [30, 1, 5.4]])),
    ('a route that turns back on itself', 'bad_route', _set(PIPE + ['points'], [[10, 5.5, 8], [10, 5.5, 6],
                                                                              [10, 1, 6], [30, 1, 6], [30, 1, 5.4]])),
    ('a pipe whose from end is outside its area', 'outside_area',
     _set(['areas/a1.json', 'pipes', 1, 'from'], {'at': [45, 3, -1]})),
    ('an unknown medium', 'bad_ref', _set(PIPE + ['medium'], 'steam')),
    ('a DN not in the kit\'s table without od_mm', 'bad_value', _set(PIPE + ['dn'], 150)),
    ('an inline part that is not inline', 'bad_kind', _set(PIPE + ['valves', 0, 'part'], 'tank_vertical')),
    ('a stair whose foot meets nothing walkable', 'not_walkable', _set(ST + [1, 'params', 'foot'], [16.2, 13, 1])),
    ('a stair whose top meets nothing walkable', 'not_walkable', _set(ST + [1, 'params', 'top'], [18.03, 13, 3])),
    ('a stair too steep for the step rules', 'bad_stair', _set(ST + [1, 'params', 'foot'], [18.5, 13, 0])),
    ('a stair whose top is below its foot', 'bad_stair', _set(ST + [1, 'params', 'top'], [20.03, 13, 0])),
    ('a ladder whose top exit meets nothing walkable', 'not_walkable', _set(ST + [2, 'params', 'facing'], 90)),
    ('a ladder whose foot is in the air', 'not_walkable', _set(ST + [2, 'params', 'foot'], [30.2, 12, 1])),
    ('a structure id used twice', 'dup_id', _set(ST + [1, 'id'], 'p1')),
    ('a value read before it is computed', 'forward_ref', _set(MOD + ['values', 2], ['flow', {'product': ['p', 1]}])),
    ('a value that does not exist', 'bad_ref', _set(MOD + ['values', 4], ['p_high', {'cmp': ['q', '>', 4]}])),
    ('a value name used twice', 'dup_id', _set(MOD + ['values', 1], ['pump_cmd', {'state': 0}])),
    ('a set of a value that is not a state', 'bad_ref', _set(MOD + ['ops', 2, 'set'], {'flow': 1})),
    ('a time that is not a multiple of 0.1 s', 'bad_time', _set(MOD + ['values', 2], ['flow', {'lag': 'pump_cmd',
                                                                                              'tau': 0.25}])),
    ('a table whose x decreases', 'bad_table', _set(MOD + ['bind', 2, 'gain', 'table'], [[1, 0], [0, 1]])),
    ('a binding to a value that does not exist', 'bad_ref', _set(MOD + ['bind', 1, 'show'], 'pressure')),
    ('a binding to an anim channel the part lacks', 'bad_ref', _set(MOD + ['bind', 0, 'anim'], 'disc')),
    ('a binding to a sound that does not exist', 'bad_ref', _set(MOD + ['bind', 2, 'sound'], 'roar')),
    ('an op on equipment that does not exist', 'bad_ref', _set(MOD + ['ops', 1, 'kks'], '10LAC10AP002')),
    ('an op twice on one piece of equipment', 'dup_id', _set(MOD + ['ops', 1, 'do'], 'start')),
    ('a permissive that does not exist', 'bad_ref', _set(MOD + ['ops', 0, 'needs', 0, 0], 'valve_shut')),
    ('a reset of a trip that does not exist', 'bad_ref', _set(MOD + ['ops', 3, 'trip'], 't9')),
    ('an alarm of priority 4', 'bad_value', _set(MOD + ['alarms', 0, 'priority'], 4)),
    ('a trip id too long for its latch value', 'bad_id', _set(MOD + ['trips', 0, 'id'], 't' * 25)),
    ('a machine moving to a state it lacks', 'bad_ref', _set(MOD + ['machines'], [
        {'id': 'm', 'kks': '10LAC10AP001', 'init': 'off', 'commands': {'go': {'from': '*', 'to': 'on'}},
         'states': [{'id': 'off', 'next': [['p_high', 'away']]}, {'id': 'on'}]}])),
    ('a value named like an earlier area\'s trip latch', 'dup_id',
     _put('model/a2.json', dict(A2_MODEL, values=[['t1_latched', {'const': 1}]]))),
    ('a value named like an earlier area\'s machine state', 'dup_id', _all(
        _set(MOD + ['machines'], [{'id': 'm', 'kks': '10LAC10AP001', 'init': 'off', 'commands': {},
                                   'states': [{'id': 'off'}]}]),
        _put('model/a2.json', dict(A2_MODEL, values=[['m_state', {'const': 1}]])))),
    ('an ext value named like a trip latch', 'dup_id', _all(
        _set(['plant.json', 'ext'], ['ambient_t', 't1_latched']),
        _set(['scenarios/s1.json', 'init', 't1_latched'], 0))),
    ('an ext value named like a machine state', 'dup_id', _all(
        _set(['plant.json', 'ext'], ['ambient_t', 'm_state']),
        _set(['scenarios/s1.json', 'init', 'm_state'], 0),
        _set(MOD + ['machines'], [{'id': 'm', 'kks': '10LAC10AP001', 'init': 'off', 'commands': {},
                                   'states': [{'id': 'off'}]}]))),
    ('a trip the scenario latches twice', 'dup_id', _set(['scenarios/s1.json', 'latched'], ['t1', 't1'])),
    ('an alarm priority that is not 1, 2 or 3', 'bad_value', _set(MOD + ['alarms', 0, 'priority'], 2.5)),
    ('a scenario setting a latch to neither 0 nor 1', 'bad_value', _all(
        _app(MOD + ['values'], ['lt', {'latch': 'p_high', 'reset': 'valve_open'}]),
        _set(['scenarios/s1.json', 'init', 'lt'], 0.5))),
    ('a scenario setting an integrate outside its range', 'bad_value', _all(
        _app(MOD + ['values'], ['lv', {'integrate': 'flow', 'gain': 1, 'min': 0, 'max': 2}]),
        _set(['scenarios/s1.json', 'init', 'lv'], 3))),
    ('a scenario setting a wrap outside [0, period)', 'bad_value', _all(
        _app(MOD + ['values'], ['ang', {'wrap': 'flow', 'period': 1}]),
        _set(['scenarios/s1.json', 'init', 'ang'], 1))),
    ('a scenario setting a timer', 'bad_ref', _all(
        _app(MOD + ['values'], ['tm', {'timer': 'p_high'}]),
        _set(['scenarios/s1.json', 'init', 'tm'], 1))),
    ('a scenario setting a stateless value', 'bad_ref', _set(['scenarios/s1.json', 'init', 'p'], 3)),
    ('a scenario without an ext value', 'missing_key', _set(['scenarios/s1.json', 'init'], {})),
    ('a scenario latching a trip that does not exist', 'bad_ref', _set(['scenarios/s1.json', 'latched'], ['t2'])),
    ('a procedure step at equipment that does not exist', 'bad_ref',
     _set(['procedures/p1.json', 'steps', 0, 'at'], ['10LAB10AA009'])),
    ('a procedure step expecting an op the model lacks', 'bad_ref',
     _set(['procedures/p1.json', 'steps', 0, 'do'], [{'kks': '10LAB10AA001', 'do': 'close'}])),
    ('a procedure step ending on a value that does not exist', 'bad_ref',
     _set(['procedures/p1.json', 'steps', 0, 'done'], 'valve_wide')),
    ('a link to equipment that does not exist', 'bad_link',
     _set(['procedures/p1.json', 'steps', 0, 'text', 1, 'to'], {'kks': '10LAB10AA009'})),
    ('a figure in a procedure', 'bad_kind', _set(['procedures/p1.json', 'intro'], [{'figure': 'x'}])),
    ('a tour step that expects an op', 'unknown_key',
     _set(['procedures/t1.json', 'steps', 0, 'do'], [{'kks': '10LAC10AP001', 'do': 'start'}])),
    ('a procedure without a scenario', 'missing_key', _del(['procedures/p1.json', 'scenario'])),
    ('a procedure over the step limit', 'limit', _set(['procedures/t1.json', 'steps'], [
        {'id': f's{i}', 'text': ['x'], 'at': ['10LAC10AP001'], 'go': 'walk'} for i in range(201)])),
    ('a recorded sound that is not CC0', 'bad_value', _set(['sounds.json', 'sounds'], [
        {'id': 'x', 'kind': 'loop', 'file': 'x.ogg', 'licence': 'CC-BY-4.0', 'source': 'https://example.org/x',
         'made': 'trimmed'}])),
]


def build_rejects():
    out = []
    base = mini()
    for why, code, change in REJECTS:
        F = copy.deepcopy(base)
        change(F)
        try:
            check(F)
        except P.FormatError as e:
            assert e.code == code, f'{why}: expected {code}, got {e}'
        else:
            raise AssertionError(f'{why}: not rejected')
        text = {k: (v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)) for k, v in F.items()}
        old = {k: json.dumps(v, ensure_ascii=False) for k, v in base.items()}
        change = {k: t for k, t in text.items() if old.get(k) != t}
        change.update({k: None for k in old if k not in text})
        out.append({'why': why, 'code': code, 'change': change})
    return out


# ================================================================ engine unit vectors (§7)

def unit_models():
    """Small models, each pinning some node kinds and rules; events are [step, input…] as in Recorder.inputs."""
    nodes = {'values': [
        ['u', {'state': 0}], ['k', {'state': 0}],
        ['lag', {'lag': 'u', 'tau': 0.5, 'tau_down': 1.0}],
        ['ramp', {'ramp': 'u', 'rate': 2, 'rate_down': 1}],
        ['integ', {'integrate': 'u', 'gain': 3, 'min': -0.5, 'max': 1}],
        ['latch', {'latch': 'u', 'reset': 'k'}],
        ['delay', {'delay': 'u', 'on': 0.3, 'off': 0.2}],
        ['timer', {'timer': 'u'}],
        ['wrap', {'wrap': 'neg', 'period': 1, 'init': 0.25}],
        ['neg', {'product': ['u', -4.5]}],
        ['tab', {'of': 'u', 'table': [[0, 1], [0.5, 2], [0.5, 5], [1, 6]]}],
        ['tstep', {'of': 'u', 'table': [[0, 1], [0.5, 2], [1, 3]], 'step': True}],
        ['sel', {'select': 'tstep', 'cases': [10, 20, 'u']}],
        ['mn', {'min': ['u', 0.3]}], ['mx', {'max': ['u', 0.3]}], ['df', {'diff': ['u', 'k']}],
        ['sm', {'sum': ['u', 'k', 0.5]}], ['cmp', {'cmp': ['u', '>=', 0.5]}],
        ['and', {'and': ['u', 'k']}], ['or', {'or': ['u', 'k']}], ['not', {'not': 'u'}],
        ['ext2', {'product': ['ambient_t', 2]}]],
        'ops': [{'kks': '10LAC10AP001', 'do': 'set', 'input': 'u', 'range': [-2, 2], 'where': ['screen']},
                {'kks': '10LAB10AA001', 'do': 'set', 'input': 'k', 'range': [0, 1], 'where': ['screen']}]}
    rules = {'values': [
        ['a', {'state': 0}], ['b', {'state': 0}], ['c', {'state': 0}], ['m_go', {'state': 0}],
        ['a_seen', {'lag': 'a', 'tau': 0.1}], ['a_now', {'product': ['a', 1]}],
        ['b_hi', {'cmp': ['b', '>=', 1]}], ['c_hi', {'cmp': ['c', '>=', 1]}], ['both', {'and': ['b_hi', 'c_hi']}],
        ['sup', {'cmp': ['a', '>=', 2]}], ['clr', {'cmp': ['b', '<', 0.5]}]],
        'ops': [{'kks': '10LAC10AP001', 'do': 'start', 'set': {'a': 1}, 'needs': [['b_hi', 'B must be high']],
                 'where': ['local']},
                {'kks': '10LAC10AP001', 'do': 'set', 'input': 'b', 'range': [0, 5], 'where': ['screen']},
                {'kks': '10LAB10AA001', 'do': 'set', 'input': 'c', 'range': [0, 5], 'where': ['screen']},
                {'kks': '10LAB10BB001', 'do': 'set', 'input': 'a', 'range': [0, 5], 'where': ['screen']},
                {'kks': '10LAB10AA001', 'do': 'go', 'machine': 'm', 'where': ['screen']},
                {'kks': '10LAB10CP501', 'do': 'reset', 'trip': 'tb', 'where': ['screen']},
                {'kks': '10LAB10BB001', 'do': 'reset', 'trip': 'tc', 'where': ['screen']}],
        'interlocks': [{'id': 'il', 'when': 'both', 'do': [{'set': {'m_go': 1}}, {'machine': 'm', 'to': 'two'}]}],
        'machines': [{'id': 'm', 'kks': '10LAC10AP001', 'init': 'zero',
                      'commands': {'go': {'from': ['zero'], 'to': 'one'}},
                      'states': [{'id': 'zero', 'set': {'a': 0}, 'watch': False},
                                 {'id': 'one', 'next': [['b_hi', 'two'], ['b_hi', 'three']]},
                                 {'id': 'two', 'next': [['c_hi', 'three']], 'watch': False},
                                 {'id': 'three', 'set': {'c': 0}, 'next': [['b_hi', 'zero']], 'say': 'Three'}]}],
        'trips': [{'id': 'tb', 'kks': '10LAB10CP501', 'text': 'B', 'when': 'b_hi', 'delay': 0.2,
                   'do': [{'set': {'a': 3}}], 'first_out': 'g'},
                  {'id': 'tc', 'kks': '10LAB10BB001', 'text': 'C', 'when': 'c_hi', 'do': [{'set': {'a': 4}}],
                   'first_out': 'g'}],
        'alarms': [{'id': 'al', 'kks': '10LAB10CP501', 'text': 'B high', 'when': 'b_hi', 'clear': 'clr',
                    'delay': 0.2, 'priority': 1, 'where': '10LAC10AP001', 'suppress': 'sup'},
                   {'id': 'al2', 'kks': '10LAB10BB001', 'text': 'C high', 'when': 'c_hi', 'priority': 3,
                    'where': '10LAB10BB001'}]}
    first_out = {'values': [
        ['a', {'state': 0}], ['b', {'state': 0}], ['x', {'state': 0}],
        ['a_hi', {'cmp': ['a', '>=', 1]}], ['b_hi', {'cmp': ['b', '>=', 1]}]],
        'ops': [{'kks': '10LAC10AP001', 'do': 'set', 'input': 'a', 'range': [0, 1], 'where': ['screen']},
                {'kks': '10LAB10AA001', 'do': 'set', 'input': 'b', 'range': [0, 1], 'where': ['screen']},
                {'kks': '10LAC10AP001', 'do': 'reset', 'trip': 'ta', 'where': ['screen']},
                {'kks': '10LAB10AA001', 'do': 'reset', 'trip': 'tb', 'where': ['screen']}],
        'trips': [{'id': 'ta', 'kks': '10LAC10AP001', 'text': 'A', 'when': 'a_hi', 'do': [{'set': {'x': 1}}],
                   'first_out': 'g'},
                  {'id': 'tb', 'kks': '10LAB10AA001', 'text': 'B', 'when': 'b_hi', 'do': [{'set': {'x': 2}}],
                   'first_out': 'g'}],
        'alarms': [{'id': 'al', 'kks': '10LAB10AA001', 'text': 'B high', 'when': 'b_hi', 'priority': 3,
                    'where': '10LAB10AA001'}]}
    return [
        ('every node kind', nodes, {'ambient_t': 21}, [], [
            [1, 'op', '10LAC10AP001', 'set', 1, None], [6, 'op', '10LAB10AA001', 'set', 1, None],
            [8, 'op', '10LAB10AA001', 'set', 0, None], [10, 'op', '10LAC10AP001', 'set', -1, None],
            [14, 'op', '10LAC10AP001', 'set', 0.5, None], [16, 'op', '10LAC10AP001', 'set', 0, None],
            [17, 'op', '10LAC10AP001', 'set', 3, None]], 24),
        ('permissives, interlock edges, machines, trips with first-out and reset, alarm states', rules,
         {'ambient_t': 20}, [{'id': 'f', 'when': {'cmp': ['a', '>=', 3]}, 'set': {'c': 2}, 'text': 'C follows'},
                             {'id': 'g', 'set': {'b': 0}, 'text': 'Trainer clears B'}], [
            [1, 'op', '10LAC10AP001', 'start', None, None],
            [2, 'op', '10LAB10AA001', 'go', None, None],
            [3, 'op', '10LAC10AP001', 'set', 1, None],
            [4, 'op', '10LAC10AP001', 'start', None, None],
            [5, 'op', '10LAB10AA001', 'go', None, None],
            [6, 'op', '10LAB10AA001', 'set', 1, None],
            [9, 'op', '10LAB10CP501', 'reset', None, 'tb'],
            [10, 'ack', 'al'],
            [12, 'fault', 'g'],
            [14, 'op', '10LAB10CP501', 'reset', None, 'tb'],
            [15, 'ack', 'al2'],
            [16, 'op', '10LAB10BB001', 'set', 0, None],
            [16, 'op', '10LAB10AA001', 'set', 0, None],
            [17, 'op', '10LAB10BB001', 'reset', None, 'tc'],
            [18, 'op', '10LAC10AP001', 'set', 1, None],
            [18, 'shelve', 'al2', 0.5],
            [19, 'op', '10LAB10AA001', 'set', 1, None],
            [26, 'op', '10LAB10BB001', 'set', 2, None],
            [27, 'op', '10LAC10AP001', 'set', 0, None],
            [27, 'op', '10LAB10AA001', 'set', 0, None],
            [29, 'ack', 'al'], [29, 'ack', 'al2'],
            [30, 'op', '10LAB10BB001', 'set', 0, None],
            [31, 'op', '10LAC10AP001', 'set', 2, None], [33, 'op', '10LAC10AP001', 'set', 0, None]], 36),
        ('first out with a trip the scenario starts latched; inputs naming no alarm or fault', first_out,
         {'ambient_t': 20, 'latched': ['ta']}, [], [
            [1, 'op', '10LAB10AA001', 'set', 1, None],
            [3, 'op', '10LAB10AA001', 'set', 0, None],
            [4, 'op', '10LAB10AA001', 'reset', None, 'tb'],
            [5, 'op', '10LAC10AP001', 'reset', None, 'ta'],
            [6, 'op', '10LAB10AA001', 'set', 1, None],
            [8, 'ack', 'none'], [8, 'shelve', 'none', 5], [8, 'unshelve', 'none'], [8, 'fault', 'none'],
            [8, 'shelve', 'al', 0], [8, 'shelve', 'al', -1], [8, 'shelve', 'al', 1e6], [8, 'shelve', 'al', 0.25],
            [11, 'shelve', 'al', 999999.9]], 12),
    ]


def unit_bundle(model, init, faults):
    """The synthetic plant with model/a1.json and scenarios/s1.json replaced and procedures/p1.json removed (its
    steps name ops of the synthetic model). `init` may carry the scenario's `latched` list."""
    F = mini()
    F['model/a1.json'] = dict({'format': 'walkdown-plant-model', 'version': 1, 'area': 'a1'}, **model)
    init = dict(init)
    latched = init.pop('latched', None)
    F['scenarios/s1.json'] = {'format': 'walkdown-plant-scenario', 'version': 1, 'id': 's1', 'title': 'Units',
                              'init': init, 'faults': faults}
    if latched:
        F['scenarios/s1.json']['latched'] = latched
    for rel in ('procedures/p1.json',):
        del F[rel]
    return F, check(F)


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
    elif kind == 'fault':
        e.fault(item[2])
    else:
        raise ValueError(kind)


def replay(e, inputs, until):
    """Applies inputs (each [step, …], taking effect in that step) and steps the engine to step `until`."""
    i = 0
    inputs = sorted(inputs, key=lambda x: x[0])
    while e.step_no < until:
        while i < len(inputs) and inputs[i][0] == e.step_no + 1:
            apply(e, inputs[i])
            i += 1
        e.step()
    assert i == len(inputs), 'inputs after the end'


def build_steps():
    out = []
    for why, model, init, faults, inputs, n in unit_models():
        F, b = unit_bundle(model, init, faults)
        e = P.Engine(b, 's1')
        states = [e.snapshot()]
        i = 0
        while e.step_no < n:
            while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                apply(e, inputs[i])
                i += 1
            e.step()
            states.append(e.snapshot())
        out.append({'why': why, 'model': F['model/a1.json'], 'scenario': F['scenarios/s1.json'], 'inputs': inputs,
                    'states': states, 'events': e.events})
    return out


# ================================================================ the first train

# Forks from the cold start: (id, base, actions, expectations). base is a procedure step id (the state just after
# it ended), 'start' (step 0) or 'end'. Actions: ('op', kks, do, value, trip), ('fault', id), ('run', seconds),
# ('until', value name, max seconds). Expectations are checked by tests/test_plant3d.py against FIRST-TRAIN.md.
FORKS = [
    # wrong operator actions
    ('cw_start_valve_open', 'start', [('op', '30PAC10AA102', 'open', None, None), ('run', 70),
                                      ('op', '30PAC10AP002', 'start', None, None), ('run', 1)],
     {'refused': [['30PAC10AP002', 'start', ['cw_b_vstart']]]}),
    ('gland_without_tg', 'start', [('op', '30MAW10AA001', 'open', None, None), ('run', 1)],
     {'refused': [['30MAW10AA001', 'open', ['st_tg_run', 'aux_ok', 'ia_ok']]]}),
    ('valve_without_air', 'start', [('op', '30LCA10AA001', 'open', None, None), ('run', 1)],
     {'refused': [['30LCA10AA001', 'open', ['ia_ok']]]}),
    ('gt_start_cold', 'start', [('op', '10MBA10', 'start', None, None), ('run', 1)],
     {'refused': [['10MBA10', 'start', ['gt1_lube_ok', 'gt1_tg_run', 'ccw_ok', 'gt1_trips_clear', 'fw_avail']]]}),
    ('reset_with_cause', 'start', [('op', '30MAG10CP001', 'reset', None, 'st_trip_cond_p'), ('run', 1)],
     {'refused': [['30MAG10CP001', 'reset', ['cond_hh']]]}),
    ('bypass_before_vacuum', 'aux', [('op', '30MAN10AA001', 'auto', None, None), ('run', 1)],
     {'refused': [['30MAN10AA001', 'auto', ['byp_permit']]]}),
    ('cep_without_minflow', 'vac_hold', [('op', '30LCB10AP001', 'start', None, None), ('run', 1)],
     {'refused': [['30LCB10AP001', 'start', ['cep_mf_open']]]}),
    ('tg_stop_with_gland', 'gland', [('op', '30MAK10AE001', 'stop', None, None), ('run', 30)],
     {'alarms': ['st_tg_gland']}),
    ('close_breaker_out_of_phase', 'gt_exc', [('op', '10BAC10', 'close_breaker', None, None), ('run', 1)],
     {'refused': [['10BAC10', 'close_breaker', ['gt1_ph_ok']]]}),
    ('gt_load_too_early', 'gt_brk', [('op', '10MKA10', 'set', 250, None), ('run', 900)],
     {'alarms': ['hp_warm_fast']}),
    ('roll_too_early', 'drains_close', [('op', '30MAA10', 'roll', None, None), ('run', 1)],
     {'refused': [['30MAA10', 'roll', ['st_p_ok', 'st_warm_shut']]]}),
    ('hold_in_critical_band', 'warm_close', [('op', '30MAA10', 'roll', None, None), ('until', 'st_inband', 900),
                                             ('op', '30MAA10', 'hold', None, None), ('run', 400)],
     {'first_out': {'st': 'st_trip_vib'}, 'alarms': ['st_vib4_hh']}),
    # trips and interlocks at base load
    ('gt_lube_both', 'end', [('fault', 'gt1_lube_both'), ('run', 60)],
     {'first_out': {'gt1': 'gt1_trip_lube'}, 'tripped': ['gen1_trip_prot'], 'machines': {'gt1_start': 'trip'},
      'alarms': ['gt1_lp1_ll', 'gen1_brk_trip']}),
    ('gt_lac_fails', 'end', [('fault', 'gt1_lac_fails'), ('run', 60)],
     {'interlocks': ['gt1_dc_auto'], 'no_trip': True}),
    ('gt_lube_stopped_at_rest', 'gt_lube_reset', [('until', 'gt1_lube_est', 30),   # the oil system in service first
                                                  ('op', '10MBV10AP001', 'stop', None, None), ('run', 60)],
     {'no_interlocks': ['gt1_dc_auto']}),
    ('gt_lube_ac_stopped_on_tg', 'gt_tg', [('run', 120), ('op', '10MBV10AP001', 'stop', None, None), ('run', 60)],
     {'interlocks': ['gt1_dc_auto'], 'no_trip': True}),
    ('st_lube_ac_stopped_on_tg', 'st_tg', [('run', 120), ('op', '30MAV10AP001', 'stop', None, None), ('run', 60)],
     {'interlocks': ['st_dc_auto'], 'no_trip': True}),
    ('gt_lube_ac_stopped', 'end', [('op', '10MBV10AP001', 'stop', None, None), ('run', 60)],
     {'interlocks': ['gt1_dc_auto'], 'no_trip': True}),
    ('gt_flameout', 'end', [('fault', 'gt1_flameout'), ('run', 30)], {'first_out': {'gt1': 'gt1_trip_flame'}}),
    ('gt_exhaust_hot', 'end', [('fault', 'gt1_fuel_ctrl'), ('run', 300)],
     {'first_out': {'gt1': 'gt1_trip_exh'}, 'alarms': ['gt1_tc4_h', 'gt1_tc4_hh']}),
    ('gt_spread', 'end', [('fault', 'gt1_tc7'), ('run', 120)],
     {'first_out': {'gt1': 'gt1_trip_spread'}, 'alarms': ['gt1_tc7_dev']}),
    ('gt_overspeed', 'end', [('fault', 'gt1_load_rej'), ('run', 120)],
     {'first_out': {'gt1': 'gt1_trip_os'}, 'alarms': ['gt1_os1']}),
    ('gt_vibration', 'end', [('fault', 'gt1_vib'), ('run', 30)],
     {'first_out': {'gt1': 'gt1_trip_vib'}, 'alarms': ['gt1_vib2_hh']}),
    ('gt_surge', 'end', [('fault', 'gt1_surge'), ('run', 30)], {'first_out': {'gt1': 'gt1_trip_surge'}}),
    ('drum_level_high', 'end', [('fault', 'hp_fwv_open'), ('run', 900)],
     {'first_out': {'gt1': 'gt1_trip_drum_hh'}, 'alarms': ['hp_l1_h', 'hp_l1_hh']}),
    ('drum_level_low', 'end', [('fault', 'hp_fwv_closed'), ('run', 300)],
     {'first_out': {'gt1': 'gt1_trip_drum_ll'}, 'alarms': ['hp_l1_l', 'hp_l1_ll']}),
    ('st_lube_both', 'end', [('fault', 'st_lube_both'), ('run', 60)],
     {'first_out': {'st': 'st_trip_lube'}, 'tripped': ['gen3_trip_prot'], 'machines': {'st_start': 'trip'}}),
    ('st_lac_fails', 'end', [('fault', 'st_lac_fails'), ('run', 60)],
     {'interlocks': ['st_dc_auto'], 'no_trip': True}),
    ('cw_pumps_lost', 'end', [('fault', 'cw_ab_fail'), ('run', 300)],
     {'first_out': {'st': 'st_trip_cond_p', 'cw_a': 'cw_a_trip_ol', 'cw_b': 'cw_b_trip_ol'},
      'interlocks': ['byp_blocked', 'cw_a_v_close', 'cw_b_v_close'], 'alarms': ['cond_p1_hh', 'cw_flow_low'],
      'machines': {'hp_byp_ctrl': 'manual', 'lp_byp_ctrl': 'manual'}}),
    ('st_overspeed', 'end', [('fault', 'st_load_rej'), ('run', 120)], {'first_out': {'st': 'st_trip_os'}}),
    ('st_axial', 'end', [('fault', 'st_thrust'), ('run', 120)], {'first_out': {'st': 'st_trip_axial'}}),
    ('st_vibration', 'end', [('fault', 'st_vib'), ('run', 30)], {'first_out': {'st': 'st_trip_vib'}}),
    ('wet_steam', 'end', [('fault', 'hp_spray_stuck'), ('run', 900)],
     {'first_out': {'st': 'st_trip_steam_t'}, 'alarms': ['st_sh_low']}),
    ('cw_overload', 'end', [('fault', 'cw_a_motor'), ('run', 120)],
     {'first_out': {'cw_a': 'cw_a_trip_ol'}, 'interlocks': ['cw_a_v_close'], 'alarms': ['cw_a_tripped']}),
    ('basin_low_low', 'end', [('fault', 'ct_drain_open'), ('run', 900)],
     {'first_out': {'cw_a': 'cw_a_trip_ll', 'cw_b': 'cw_b_trip_ll'}, 'alarms': ['ct_basin_low', 'ct_basin_ll']}),
    ('cw_valve_late', 'end', [('op', '30PAC10AA103', 'set', 0.15, None), ('until', 'cw_c_vstart', 60),
                              ('op', '30PAC10AP003', 'start', None, None), ('run', 1), ('fault', 'cw_c_valve_stuck'),
                              ('op', '30PAC10AA103', 'open', None, None), ('run', 150)],
     {'first_out': {'cw_c': 'cw_c_trip_valve'}, 'alarms': ['cw_c_valve_late']}),
    ('hotwell_low_low', 'end', [('fault', 'hw_leak'), ('run', 1200)],
     {'first_out': {'cep': 'cep_trip_hw'}, 'alarms': ['hw_low', 'hw_ll']}),
    ('ccw_pump_trip', 'end', [('fault', 'ccw_a_motor'), ('run', 30)],
     {'first_out': {'ccw': 'ccw_a_trip'}, 'interlocks': ['ccw_b_auto'], 'alarms': ['ccw_a_tripped']}),
    ('ccw_standby_a', 'end', [('op', '00PGC10AP002', 'start', None, None), ('run', 10),
                              ('op', '00PGC10AP001', 'stop', None, None), ('run', 10),
                              ('fault', 'ccw_b_motor'), ('run', 30)],
     {'first_out': {'ccw': 'ccw_b_trip'}, 'interlocks': ['ccw_a_auto'], 'alarms': ['ccw_b_tripped']}),
    ('cw_b_overload', 'end', [('fault', 'cw_b_motor'), ('run', 120)],
     {'first_out': {'cw_b': 'cw_b_trip_ol'}, 'interlocks': ['cw_b_v_close'], 'alarms': ['cw_b_tripped']}),
    ('cw_c_overload', 'end', [('op', '30PAC10AA103', 'set', 0.15, None), ('until', 'cw_c_vstart', 60),
                              ('op', '30PAC10AP003', 'start', None, None), ('run', 30), ('fault', 'cw_c_motor'),
                              ('run', 60)],
     {'first_out': {'cw_c': 'cw_c_trip_ol'}, 'interlocks': ['cw_c_v_close'], 'alarms': ['cw_c_tripped']}),
    ('basin_low_low_three_pumps', 'end', [('op', '30PAC10AA103', 'set', 0.15, None), ('until', 'cw_c_vstart', 60),
                                          ('op', '30PAC10AP003', 'start', None, None), ('run', 1),
                                          ('op', '30PAC10AA103', 'open', None, None), ('run', 80),
                                          ('fault', 'ct_drain_open'), ('run', 900)],
     {'first_out': {'cw_a': 'cw_a_trip_ll', 'cw_b': 'cw_b_trip_ll', 'cw_c': 'cw_c_trip_ll'},
      'alarms': ['ct_basin_ll']}),
    ('cw_a_valve_late', 'basin', [('op', '30PAC10AA101', 'set', 0.15, None), ('until', 'cw_a_vstart', 60),
                                  ('op', '30PAC10AP001', 'start', None, None), ('run', 1),
                                  ('fault', 'cw_a_valve_stuck'), ('op', '30PAC10AA101', 'open', None, None),
                                  ('run', 150)],
     {'first_out': {'cw_a': 'cw_a_trip_valve'}, 'alarms': ['cw_a_valve_late']}),
    ('cw_b_valve_late', 'gt_load', [('op', '30PAC10AA102', 'set', 0.15, None), ('until', 'cw_b_vstart', 60),
                                    ('op', '30PAC10AP002', 'start', None, None), ('run', 1),
                                    ('fault', 'cw_b_valve_stuck'), ('op', '30PAC10AA102', 'open', None, None),
                                    ('run', 150)],
     {'first_out': {'cw_b': 'cw_b_trip_valve'}, 'alarms': ['cw_b_valve_late']}),
    # FIRST-TRAIN §4 "As built" (2026-10-19): CCW, the lube oil temperatures, instrument air and the valves'
    # fail-safe positions, the valves' power, the surge of a start against an open valve, the HP safety valve and
    # the GT runback, the HP casing warm-up
    ('warm_without_tg', 'start', [('op', '30MAA10AA101', 'open', None, None), ('run', 1)],
     {'refused': [['30MAA10AA101', 'open', ['st_tg_run', 'aux_ok']]]}),
    ('roll_with_warmup_open', 'roll_ready', [('op', '30MAA10', 'roll', None, None), ('run', 1)],
     {'refused': [['30MAA10', 'roll', ['st_warm_shut']]]}),
    ('gt_load_without_sink', 'gt_brk', [('op', '10MKA10', 'set', 60, None), ('run', 60),
                                        ('op', '30MAN10AA001', 'manual', None, None), ('run', 5),
                                        ('op', '10MKA10', 'set', 250, None), ('run', 1)],
     {'interlocks': ['gt1_runback'], 'alarms': ['gt1_runback'], 'refused': [['10MKA10', 'set', ['hp_slide']]],
      'end': {'gt1_load_sp': [20, 20]}}),
    # the spray in manual: nothing holds the steam near the casing, so the roll is refused on the match
    ('roll_steam_too_hot', 'warm_close', [('op', '10LAE30AA001', 'manual', None, None), ('run', 600),
                                          ('op', '30MAA10', 'roll', None, None), ('run', 1)],
     {'refused': [['30MAA10', 'roll', ['st_match']]]}),
    ('ia_stopped_at_load', 'end', [('op', '00QFA10AN001', 'stop', None, None), ('run', 200)],
     {'alarms': ['ia_p_low']}),
    ('ccw_lost', 'end', [('fault', 'ccw_both'), ('run', 900)],
     {'first_out': {'ccw': 'ccw_a_trip', 'gt1': 'gt1_trip_oil_temp', 'st': 'st_trip_oil_temp'},
      'alarms': ['ccw_t_high', 'gt1_oil_t_h', 'gt1_oil_t_hh', 'st_oil_t_h', 'st_oil_t_hh', 'cond_p1_h'],
      'max': {'gt1_oil_t': [70, 80], 'ccw_t': [45, 60], 'cond_p': [15, 25]}}),
    ('instrument_air_lost', 'end', [('fault', 'ia_lost'), ('run', 900)],
     {'alarms': ['ia_p_low', 'ia_a_tripped', 'cond_p1_hh', 'gt1_runback', 'hp_sv_open', 'hp_l1_hh'],
      'first_out': {'st': 'st_trip_cond_p', 'gt1': 'gt1_trip_drum_hh'}, 'interlocks': ['byp_blocked', 'gt1_runback'],
      'end': {'hp_fwv_pos': [1, 1], 'cep_mf_pos': [1, 1], 'st_gland_pos': [0, 0], 'hp_spray_on': [0, 0]},
      'max': {'hp_p': [135, 137]}}),
    ('st_trip_no_bypass', 'end', [('fault', 'st_trip_no_bypass'), ('run', 600)],
     {'first_out': {'st': 'st_trip_vib'}, 'interlocks': ['byp_blocked', 'gt1_runback'],
      'alarms': ['gt1_runback', 'hp_p_high', 'hp_sv_open'], 'machines': {'hp_byp_ctrl': 'manual'},
      'max': {'hp_p': [135, 137]}, 'end': {'gt1_mw': [20, 20], 'hp_sv_open': [1, 1]}}),
    ('safety_valve_reseats_after_gt_trip', 'end', [('fault', 'st_trip_no_bypass'), ('run', 300),
                                                   ('fault', 'gt1_vib'), ('run', 1200)],
     {'alarms': ['hp_sv_open'], 'end': {'hp_sv_open': [0, 0]}}),
    ('bypass_hydraulics_lost', 'end', [('fault', 'byp_hyd'), ('run', 60)],
     {'interlocks': ['byp_blocked'], 'no_interlocks': ['gt1_runback'], 'no_trip': True, 'alarms': ['byp_hyd']}),
    ('cw_valve_power_lost', 'end', [('fault', 'cw_valve_power'), ('run', 10), ('fault', 'cw_b_motor'), ('run', 300)],
     {'first_out': {'cw_b': 'cw_b_trip_ol'}, 'interlocks': ['cw_b_v_close'],
      'alarms': ['cw_flow_low', 'cw_a_v_fault', 'cw_b_v_fault'],
      'end': {'cw_b_v_pos': [1, 1], 'cw_flow': [7000, 8000]}}),
    ('cw_a_start_open_valve', 'basin', [('fault', 'cw_a_ls'), ('op', '30PAC10AA101', 'open', None, None),
                                        ('run', 70), ('op', '30PAC10AP001', 'start', None, None), ('run', 20)],
     {'alarms': ['cw_a_surge'], 'max': {'cw_a_pt': [7, 9]}}),
    ('cw_b_start_open_valve', 'gt_load', [('fault', 'cw_b_ls'), ('op', '30PAC10AA102', 'open', None, None),
                                          ('run', 70), ('op', '30PAC10AP002', 'start', None, None), ('run', 20)],
     {'alarms': ['cw_b_surge']}),
    ('cw_c_start_open_valve', 'end', [('fault', 'cw_c_ls'), ('op', '30PAC10AA103', 'open', None, None),
                                      ('run', 70), ('op', '30PAC10AP003', 'start', None, None), ('run', 20)],
     {'alarms': ['cw_c_surge'], 'max': {'cw_c_pt': [3.5, 6]}}),
] + [  # every cooling tower fan (fans 6–10 stand at the end of the cold start: started first)
    (f'ct_fan{i}_vibration', 'end',
     ([] if i <= 5 else [('op', f'30PAD10AN{i:03d}', 'start', None, None), ('run', 60)]) +
     [('fault', f'ct_fan{i}_vib'), ('run', 60)],
     {'first_out': {'ct_fans': f'ct_fan{i}_trip_vib'}, 'alarms': [f'ct_fan{i}_vib_hh']}) for i in range(1, 11)
]


def train_bundle():
    return P.check_dir(DATA)


def run_cold_start(b):
    """The cold start by its procedure, keeping the engine as it stood after every step (the forks' bases)."""
    bases = {}
    first = P.Recorder(b, 'cold_iron')
    bases['start'] = first.clone()

    def keep(sid, e):
        bases[sid] = e.clone()
    e, log = P.run_procedure(b, 'cold_start', eng=first, on_step=keep)
    bases['end'] = e.clone()
    return e, log, bases


def run_fork(base, actions, probes=()):
    """Runs a fork's actions; for each value named in `probes` also keeps its highest value over the fork and its
    value at the end (the expectations `max` and `end` check them)."""
    e = base.clone()
    start = e.step_no
    n_in = len(e.inputs)
    n_ev = len(e.events)
    seen = {n: {'max': e.v(n)} for n in probes}

    def step(k=1):
        for _ in range(k):
            e.step()
            for n in probes:
                seen[n]['max'] = max(seen[n]['max'], e.v(n))
    for a in actions:
        if a[0] == 'op':
            e.op(*a[1:])
        elif a[0] == 'fault':
            e.fault(a[1])
        elif a[0] == 'run':
            step(round(a[1] * 10))
        elif a[0] == 'until':
            t0 = e.step_no
            while not e.truth(a[1]):
                assert e.step_no - t0 < a[2] * 10, f'{a[1]} not true within {a[2]} s'
                step()
    for n in probes:
        seen[n]['end'] = e.v(n)
    return e, start, e.inputs[n_in:], e.events[n_ev:], seen


def build_train(b):
    e, log, bases = run_cold_start(b)
    # the snapshots: replay the inputs on a fresh engine (also proves the inputs alone reproduce the run)
    r = P.Engine(b, 'cold_iron')
    snaps = []
    inputs = e.inputs
    k = 0
    while r.step_no < e.step_no:
        nxt = min(e.step_no, (r.step_no // SNAP_EVERY + 1) * SNAP_EVERY)
        part = [x for x in inputs if r.step_no < x[0] <= nxt]
        replay(r, part, nxt)
        snaps.append(r.snapshot())
        k += 1
    assert r.events == e.events, 'replaying the recorded inputs gives other events'
    forks = []
    for fid, base, actions, expect in FORKS:
        probes = sorted(set(expect.get('max', {})) | set(expect.get('end', {})))
        f, start, fin, fev, seen = run_fork(bases[base], actions, probes)
        fork = {'id': fid, 'base_step': start, 'inputs': fin, 'until': f.step_no, 'events': fev,
                'end': f.snapshot(values=False), 'expect': expect}
        if probes:
            fork['seen'] = seen
        forks.append(fork)
    return {'scenario': 'cold_iron', 'procedure': 'cold_start', 'inputs': inputs, 'until': e.step_no,
            'steps': [[sid, n] for sid, n in log], 'snapshot_every': SNAP_EVERY, 'snapshots': snaps,
            'events': e.events, 'forks': forks}


LINKS = [  # links read against the synthetic plant (§6)
    'walkdown-plant://kks/10LAC10AP001',            # exact
    'walkdown-plant://kks/10LAC10AP001KP01',        # a component-level code: cut to the grammar, then the A3 dropped
    'walkdown-plant://kks/10LAC10AP0019999',        # cut to the longest beginning that matches the grammar
    'walkdown-plant://kks/10LAC10AP002',            # same system and equipment letters
    'walkdown-plant://kks/10LAB10AP005',            # same equipment letters only
    'walkdown-plant://kks/20MAA10AP001',            # unit and system not in the key; same equipment letters
    'walkdown-plant://kks/10MAA10AN001',            # nothing of that kind: the decoding only
    'walkdown-plant://kks/10LAB10',                 # a system the plant has no system-level code for
    'walkdown-plant://kks/10lac10ap001',            # lower case: not a link code
    'walkdown-plant://kks/10IAC10AP001',            # no beginning matches the grammar (I is not a KKS letter)
    'walkdown-plant://kks/10LAC10AP0019999999999999',  # 25 characters
    'walkdown-plant://kks/10LAC10AP001?x=1',
    'walkdown-plant://kks/',
    'walkdown-plant://procedure/p1',
    'walkdown-plant://procedure/p1/start',
    'walkdown-plant://procedure/t1/s1',
    'walkdown-plant://procedure/p1/nope',
    'walkdown-plant://procedure/zz',
    'walkdown-plant://course/ppt',
    'walkdown://course/ppt',
    'https://example.org/',
]


def build():
    F = mini()
    counts = check(F).counts
    links = [{'link': u, 'expect': P.read_link(u, check(F))} for u in LINKS]
    return {'about': 'Walkdown Plant content format 1 vectors (docs/PLANT3D.md §12), made by '
                     'ref/make_plant3d_vectors.py from ref/plant3d.py. Numbers compare to 1e-6.',
            'valid': [{'why': 'the synthetic plant', 'files': {k: json.dumps(v, ensure_ascii=False)
                                                              for k, v in F.items()}, 'counts': counts}],
            'reject': build_rejects(),
            'steps': build_steps(),
            'links': links,
            'train': build_train(train_bundle())}


def dump(v):
    return json.dumps(R(v), ensure_ascii=False, separators=(',', ':')) + '\n'


if __name__ == '__main__':
    text = dump(build())
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
        print(f'wrote {OUT}: {len(text)} bytes')
    else:
        with open(OUT, encoding='utf-8') as f:
            same = f.read() == text
        print('up to date' if same else 'differs (run with --write)')
        sys.exit(0 if same else 1)
