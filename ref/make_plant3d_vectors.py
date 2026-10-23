#!/usr/bin/env python3
"""Generate ref/vectors/plant3d-v1.json: test vectors for the Walkdown Plant content format (docs/PLANT3D.md §12).

  valid, reject  a small synthetic plant ({relative path: file text}), and changes to it that each break one rule
                 (`change`: the files replaced, null for a file removed)
  steps          small synthetic models stepped by events, the expected state after every step
  train          the first train (data/plant3d): the cold start run by its procedure (the inputs at the steps they
                 take effect, every event, a full snapshot every 10 min of model time) and forks from it that make
                 each trip and interlock fire and each wrong operator action be refused or alarmed
  hot            the same for the hot restart (its scenario and procedure) and its forks

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
                        ['flow', {'lag': 'pump_cmd', 'tau': 2, 'unit': 'm³/h'}], ['p', {'product': ['flow', 5], 'unit': 'bar',
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
            'faults': [{'id': 'f1', 'set': {'pump_cmd': 0}, 'text': 'Pump trips', 'kks': '10LAC10AP001',
                        'repair': {'valve_cmd': 0}}]}
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
    screens = {'format': 'walkdown-plant-screens', 'version': 1, 'overview': {'title': 'Overview', 'short': 'Overview',
                                                                                  'key': ['p']},
               'screens': [{'id': 'feed', 'short': 'Feed', 'title': 'Feedwater',
                            'groups': [{'id': 'pumps', 'title': 'Pumps', 'at': [0, 0], 'codes': ['10LAC10'],
                                        'extra': ['flow']},
                                       {'id': 'pipe', 'title': 'Piping', 'at': [1, 0], 'codes': ['10LAB10']}],
                            'lines': [{'from': 'pumps', 'to': 'pipe', 'medium': 'water'}], 'trend': ['p']}],
               'left_out': [{'codes': ['10LAB10AA'], 'why': 'A hand valve without position feedback'}]}
    return {'kit.json': kit, 'plant.json': plant, 'sounds.json': sounds, 'screens.json': screens,
            'areas/a1.json': a1, 'areas/a2.json': a2,
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
SCR = ['screens.json', 'screens', 0]
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
    ('a fault\'s repair writing a value that is not a state', 'bad_ref',
     _set(['scenarios/s1.json', 'faults', 0, 'repair'], {'flow': 0})),
    ('a fault repaired at equipment that does not exist', 'bad_ref',
     _set(['scenarios/s1.json', 'faults', 0, 'kks'], '10LAB10AA009')),
    ('a fault with an unknown key', 'unknown_key', _set(['scenarios/s1.json', 'faults', 0, 'fix'], {'pump_cmd': 0})),
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
    # the control room screens (§7.11)
    ('a code of the model on no screen and not left out', 'unplaced', _all(
        _del(['screens.json', 'left_out']), _set(SCR + ['groups', 1, 'codes'], ['10LAB10CP']))),
    ('a group whose codes begin no code of the model', 'bad_ref', _app(SCR + ['groups'], {
        'id': 'none', 'title': 'Nothing', 'at': [2, 0], 'codes': ['10LAC20']})),
    ('one beginning of a code in two groups', 'dup_id', _set(SCR + ['groups', 1, 'codes'], ['10LAB10', '10LAC10'])),
    ('an extra value that has a code', 'bad_ref', _set(SCR + ['groups', 1, 'extra'], ['p'])),
    ('a beginning of a code without its system letters', 'bad_kks', _set(SCR + ['groups', 1, 'codes'], ['10LA'])),
    ('a line to a group of no screen', 'bad_ref', _set(SCR + ['lines', 0, 'to'], 'tank')),
    ('a trend of a value without a unit', 'bad_ref', _set(SCR + ['trend'], ['valve_cmd'])),
    ('two groups in one place on the screen', 'dup_id', _set(SCR + ['groups', 1, 'at'], [0, 0])),
    ('an unknown key on a screen', 'unknown_key', _set(SCR + ['colour'], 'grey')),
    ('a left-out entry that leaves out nothing', 'bad_ref', _app(['screens.json', 'left_out'], {
        'codes': ['10LAC10AP002'], 'why': 'Nothing'})),
    ("a group beyond the screen's grid", 'bad_number', _set(SCR + ['groups', 1, 'at'], [8, 0])),
    ("a screen's name over 16 characters", 'bad_type', _set(SCR + ['short'], 'Feedwater pumps 1')),
    ('a screen called overview', 'dup_id', _set(SCR + ['id'], 'overview')),
    ('a line carrying no medium of the plant', 'bad_ref', _set(SCR + ['lines', 0, 'medium'], 'lava')),
    ('a key value twice on the overview', 'dup_id', _set(['screens.json', 'overview', 'key'], ['p', 'p'])),
    ('more than 6 trends on a screen', 'bad_length', _set(SCR + ['trend'], ['p'] * 7)),
    ('an extra value twice', 'dup_id', _set(SCR + ['groups', 0, 'extra'], ['flow', 'flow'])),
    ('an extra value without a unit', 'bad_ref', _set(SCR + ['groups', 0, 'extra'], ['valve_cmd'])),
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
    repairs = {
        'values': [['a', {'state': 0, 'kks': '10LAC10AP001'}], ['b', {'state': 0, 'kks': '10LAC10AP001'}],
                   ['c', {'state': 0, 'kks': '10LAB10AA001'}], ['a_on', {'cmp': ['a', '>=', 1]}]],
        'ops': [{'kks': '10LAC10AP001', 'do': 'set', 'input': 'a', 'range': [0, 9], 'where': ['local']}]}
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
        ('repairs: of a fault not yet applied, applied, repaired, pressed and repaired again; a fault with a when '
         'repaired is not applied again; repairs naming no fault, a fault without a repair, asked twice in a step',
         repairs, {'ambient_t': 20},
         [{'id': 'g', 'set': {'b': 5}, 'text': 'Trainer sets B', 'kks': '10LAC10AP001', 'repair': {'b': 0}},
          {'id': 'h', 'when': 'a_on', 'set': {'c': 7}, 'text': 'C when A', 'repair': {'c': 1}},
          {'id': 'k', 'set': {'c': 3}, 'text': 'No repair for this one'}], [
            [1, 'repair', 'g'], [2, 'fault', 'g'], [2, 'repair', 'g'], [3, 'repair', 'g'], [3, 'repair', 'g'],
            [4, 'repair', 'g'], [5, 'fault', 'g'], [6, 'fault', 'g'], [7, 'repair', 'g'],
            [8, 'op', '10LAC10AP001', 'set', 1, None], [10, 'repair', 'h'], [11, 'op', '10LAC10AP001', 'set', 0, None],
            [12, 'op', '10LAC10AP001', 'set', 2, None], [13, 'repair', 'h'],
            [14, 'fault', 'k'], [15, 'repair', 'k'], [15, 'repair', 'none'], [15, 'repair', 3]], 16),
    ]


def unit_bundle(model, init, faults):
    """The synthetic plant with model/a1.json and scenarios/s1.json replaced and procedures/p1.json and screens.json
    removed (they name ops and values of the synthetic model). `init` may carry the scenario's `latched` list."""
    F = mini()
    F['model/a1.json'] = dict({'format': 'walkdown-plant-model', 'version': 1, 'area': 'a1'}, **model)
    init = dict(init)
    latched = init.pop('latched', None)
    F['scenarios/s1.json'] = {'format': 'walkdown-plant-scenario', 'version': 1, 'id': 's1', 'title': 'Units',
                              'init': init, 'faults': faults}
    if latched:
        F['scenarios/s1.json']['latched'] = latched
    for rel in ('procedures/p1.json', 'screens.json'):
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
    elif kind == 'repair':
        e.repair(item[2])
    elif kind == 'permit':
        e.permit(item[2], item[3], item[4])
    elif kind in ('lock', 'unlock'):
        getattr(e, kind)(item[2], item[3], item[4])
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
# it ended), 'start' (step 0) or 'end'. Actions: ('op', kks, do, value, trip), ('fault', id), ('repair', id),
# ('run', seconds), ('until', value name, max seconds). Expectations are checked by tests/test_plant3d.py against FIRST-TRAIN.md.
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
    ('gt_load_without_sink', 'gt_brk', [('op', '10MKA10', 'set', 60, None), ('run', 330),
                                        ('op', '30MAN10AA001', 'manual', None, None), ('run', 60),
                                        ('op', '10MKA10', 'set', 250, None), ('run', 60)],
     {'alarms': ['gt1_runback'], 'max': {'gt1_mw': [60, 60]},
      'end': {'gt1_mw': [20, 20], 'gt1_load_sp': [250, 250]}}),
    ('runback_never_raises_load', 'gt_brk', [('op', '10MKA10', 'set', 10, None), ('run', 120),
                                             ('op', '30MAN10AA001', 'manual', None, None), ('run', 60)],
     {'alarms': ['gt1_runback'], 'end': {'gt1_mw': [10, 10]}}),
    ('cw_b_normal_stop', 'end', [('op', '30PAC10AP002', 'stop', None, None), ('run', 180)],
     {'interlocks': ['cw_b_v_close'], 'no_alarms': ['cw_flow_low', 'cond_p1_h']}),
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
      'first_out': {'st': 'st_trip_cond_p', 'gt1': 'gt1_trip_drum_hh'}, 'interlocks': ['byp_blocked'],
      'end': {'hp_fwv_pos': [1, 1], 'cep_mf_pos': [1, 1], 'st_gland_pos': [0, 0], 'hp_spray_on': [0, 0]},
      'max': {'hp_p': [135, 137]}}),
    ('st_trip_no_bypass', 'end', [('fault', 'st_trip_no_bypass'), ('run', 600)],
     {'first_out': {'st': 'st_trip_vib'}, 'interlocks': ['byp_blocked'],
      'alarms': ['gt1_runback', 'hp_p_high', 'hp_sv_open'], 'machines': {'hp_byp_ctrl': 'manual'},
      'max': {'hp_p': [135, 137]}, 'end': {'gt1_mw': [20, 20], 'hp_sv_open': [1, 1]}}),
    ('safety_valve_reseats_after_gt_trip', 'end', [('fault', 'st_trip_no_bypass'), ('run', 300),
                                                   ('fault', 'gt1_vib'), ('run', 1200),
                                                   ('op', '10HAN30AA001', 'open', None, None), ('run', 600)],
     {'alarms': ['hp_sv_open'], 'end': {'hp_sv_open': [0, 0], 'hp_p': [0, 100]}}),
    ('bypass_hydraulics_lost', 'end', [('fault', 'byp_hyd'), ('run', 60)],
     {'interlocks': ['byp_blocked'], 'no_trip': True, 'alarms': ['byp_hyd']}),
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
    # behaviour limits closed for plant-v0.2.0: a motor valve without its supply worked by its handwheel, the trainer's
    # faults repaired (at the equipment or from the trainer's panel)
    ('cw_hand_needs_power_lost', 'end', [('op', '30PAC10AA102', 'hand_close', None, None), ('run', 1)],
     {'refused': [['30PAC10AA102', 'hand_close', ['cw_b_v_stuck']]]}),
    ('cw_valve_closed_by_hand', 'end', [('fault', 'cw_valve_power'), ('run', 10), ('fault', 'cw_b_motor'),
                                        ('run', 30), ('op', '30PAC10AA102', 'hand_close', None, None), ('run', 30)],
     {'first_out': {'cw_b': 'cw_b_trip_ol'}, 'done': [['30PAC10AA102', 'hand_close']],
      'machines': {'cw_b_v_hand': 'closing'}, 'end': {'cw_b_v_pos': [0.85, 0.95]}}),
    ('cw_valve_closed_by_hand_end', 'end', [('fault', 'cw_valve_power'), ('run', 10), ('fault', 'cw_b_motor'),
                                            ('run', 30), ('op', '30PAC10AA102', 'hand_close', None, None),
                                            ('run', 320)],
     {'machines': {'cw_b_v_hand': 'idle'}, 'end': {'cw_b_v_pos': [0, 0.003], 'cw_b_back': [0, 25]}}),
    ('cw_hand_stopped', 'end', [('fault', 'cw_valve_power'), ('run', 10),
                                ('op', '30PAC10AA101', 'hand_close', None, None), ('run', 60),
                                ('op', '30PAC10AA101', 'hand_stop', None, None), ('run', 60)],
     {'done': [['30PAC10AA101', 'hand_stop']], 'end': {'cw_a_v_pos': [0.79, 0.81]}}),
    ('cw_valve_power_repaired', 'end', [('fault', 'cw_valve_power'), ('run', 10), ('fault', 'cw_b_motor'),
                                        ('run', 30), ('op', '30PAC10AA102', 'hand_close', None, None), ('run', 60),
                                        ('repair', 'cw_valve_power'), ('run', 90)],
     {'repaired': ['cw_valve_power'], 'machines': {'cw_b_v_hand': 'idle'},
      'end': {'cw_b_v_pos': [0, 0.003], 'cw_b_v_hw_on': [0, 0], 'cw_a_v_stuck': [0, 0]}}),
    ('cw_b_motor_repaired', 'end', [('fault', 'cw_b_motor'), ('run', 120), ('repair', 'cw_b_motor'), ('run', 1),
                                    ('op', '30PAC10AP002', 'reset', None, 'cw_b_trip_ol'), ('run', 1),
                                    ('op', '30PAC10AA102', 'set', 0.15, None), ('until', 'cw_b_vstart', 120),
                                    ('op', '30PAC10AP002', 'start', None, None), ('run', 10)],
     {'repaired': ['cw_b_motor'], 'done': [['30PAC10AP002', 'start']], 'end': {'cw_b_run': [1, 1]}}),
    ('cw_b_motor_again', 'end', [('fault', 'cw_b_motor'), ('run', 120), ('repair', 'cw_b_motor'), ('run', 10),
                                 ('fault', 'cw_b_motor'), ('run', 1)],
     {'repaired': ['cw_b_motor'], 'faults': ['cw_b_motor', 'cw_b_motor'], 'end': {'cw_b_fault': [1, 1]}}),
] + [  # every cooling tower fan (fans 6–10 stand at the end of the cold start: started first)
    (f'ct_fan{i}_vibration', 'end',
     ([] if i <= 5 else [('op', f'30PAD10AN{i:03d}', 'start', None, None), ('run', 60)]) +
     [('fault', f'ct_fan{i}_vib'), ('run', 60)],
     {'first_out': {'ct_fans': f'ct_fan{i}_trip_vib'}, 'alarms': [f'ct_fan{i}_vib_hh']}) for i in range(1, 11)
]


# Forks from the hot restart (FIRST-TRAIN §4 "As built"): the HP casing still at about 470 °C when the superheaters
# are drained with the GT at minimum load; the steam more than 50 K colder than the casing; loaded until it is matched.
HOT_FORKS = [
    ('hot_roll_steam_too_cold', 'drains_close', [('until', 'st_sh_ok', 600), ('op', '30MAA10', 'roll', None, None),
                                                 ('run', 1)],
     {'refused': [['30MAA10', 'roll', ['st_match']]], 'end': {'st_mismatch': [-250, -50.001], 'st_casing_t': [450, 480]}}),
    ('hot_warmup_refused', 'gland', [('op', '30MAA10AA101', 'open', None, None), ('run', 60)],
     {'refused': [['30MAA10AA101', 'open', ['st_cas_coolish']]], 'end': {'st_casing_t': [460, 480]}}),
    ('hot_roll_matched', 'match', [('op', '30MAA10', 'roll', None, None), ('run', 60)],
     {'done': [['30MAA10', 'roll']], 'machines': {'st_start': 'roll'}, 'end': {'st_mismatch': [-50, 150]}}),
]


def train_bundle():
    return P.check_dir(DATA)


def run_cold_start(b, scenario='cold_iron', procedure='cold_start'):
    """The cold start (or another start) by its procedure, keeping the engine as it stood after every step (the
    forks' bases)."""
    bases = {}
    first = P.Recorder(b, scenario)
    bases['start'] = first.clone()

    def keep(sid, e):
        bases[sid] = e.clone()
    e, log = P.run_procedure(b, procedure, eng=first, on_step=keep)
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
        elif a[0] == 'repair':
            e.repair(a[1])
        elif a[0] == 'permit':
            e.permit(a[1], a[2])
        elif a[0] in ('lock', 'unlock'):
            getattr(e, a[0])(a[1], a[2])
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


def build_train(b, scenario='cold_iron', procedure='cold_start', fork_list=None):
    e, log, bases = run_cold_start(b, scenario, procedure)
    # the snapshots: replay the inputs on a fresh engine (also proves the inputs alone reproduce the run)
    r = P.Engine(b, scenario)
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
    for fid, base, actions, expect in (FORKS if fork_list is None else fork_list):
        probes = sorted(set(expect.get('max', {})) | set(expect.get('end', {})))
        f, start, fin, fev, seen = run_fork(bases[base], actions, probes)
        fork = {'id': fid, 'base_step': start, 'inputs': fin, 'until': f.step_no, 'events': fev,
                'end': f.snapshot(values=False), 'expect': expect}
        if probes:
            fork['seen'] = seen
        forks.append(fork)
    return {'scenario': scenario, 'procedure': procedure, 'inputs': inputs, 'until': e.step_no,
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


# ================================================================ format 2 (PLANT3D §14–§15, §19): permits, isolations, hold

OUT2 = os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v2.json')
PUMP, VALVE, TANK, GAUGE = '10LAC10AP001', '10LAB10AA001', '10LAB10BB001', '10LAB10CP501'


def mini2():
    """The synthetic plant as version 2: its model has isolations, works and a hold node."""
    F = mini()
    F['plant.json']['version'] = 2
    m = F['model/a1.json']
    m['version'] = 2
    m['values'][1] = ['valve_cmd', {'state': 0, 'kks': VALVE}]
    m['values'] += [['pump_off', {'not': 'pump_cmd'}], ['valve_shut', {'not': 'valve_cmd'}],
                    ['p_held', {'hold': 'p', 'when': 'iso_gauge_complete', 'unit': 'bar', 'kks': GAUGE}]]
    m['isolations'] = [
        {'id': 'iso_pump', 'text': 'The pump: its motor supply and its discharge valve',
         'points': [{'kks': PUMP, 'kind': 'electrical', 'safe': 'pump_off', 'how': 'Pump stopped; breaker locked'},
                    {'kks': VALVE, 'kind': 'mechanical', 'safe': 'valve_shut', 'how': 'Valve shut and chained'}]},
        {'id': 'iso_gauge', 'text': 'The pressure gauge', 'points': [
            {'kks': GAUGE, 'kind': 'instrument', 'how': 'Root valve shut and tagged'}]}]
    m['works'] = [{'id': 'wo_pump', 'kks': PUMP, 'title': 'Pump: bearing', 'discipline': 'mech', 'permit': 'general',
                   'isolation': 'iso_pump', 'repairs': 'f1', 'task': 'job_pump'},
                  {'id': 'wo_gauge', 'kks': GAUGE, 'title': 'Gauge: calibration', 'discipline': 'inst',
                   'permit': 'general', 'isolation': 'iso_gauge', 'set': {}}]
    return F


ISO = ['model/a1.json', 'isolations']
WORK = ['model/a1.json', 'works']
REJECTS2 = [
    ('a version 2 model in a version 1 plant', 'bad_version', _set(['plant.json', 'version'], 1)),
    ('plant.json of version 3', 'bad_version', _set(['plant.json', 'version'], 3)),
    ('isolations in a version 1 model file', 'unknown_key', _all(
        _set(MOD + ['version'], 1), _del(MOD + ['works']),
        _set(MOD + ['values', 8], ['p_held', {'product': ['p', 1]}]))),
    ('a hold node in a version 1 model file', 'bad_kind', _all(
        _set(MOD + ['version'], 1), _del(MOD + ['works']), _del(MOD + ['isolations']))),
    ('a hold reading a later value', 'forward_ref', _set(MOD + ['values', 6], ['pump_off', {'hold': 'valve_shut',
                                                                                          'when': 0}])),
    ('a hold whose when is no value', 'bad_ref', _set(MOD + ['values', 8], ['p_held', {'hold': 'p', 'when': 'zz'}])),
    ('a hold without its when', 'missing_key', _set(MOD + ['values', 8], ['p_held', {'hold': 'p'}])),
    ('an isolation point on a code of no state or alarm', 'bad_ref', _set(ISO + [1, 'points', 0, 'kks'], TANK)),
    ('an isolation point on a code the plant lacks', 'bad_ref', _set(ISO + [1, 'points', 0, 'kks'], '10LAB10CP509')),
    ('an isolation point of an unknown kind', 'bad_value', _set(ISO + [0, 'points', 0, 'kind'], 'hydraulic')),
    ('one code twice in an isolation', 'dup_id', _set(ISO + [0, 'points', 1, 'kks'], PUMP)),
    ('an isolation id over 22 characters', 'bad_id', _set(ISO + [1, 'id'], 'i' * 23)),
    ('two isolations with one id', 'dup_id', _set(ISO + [1, 'id'], 'iso_pump')),
    ('an isolation without points', 'bad_length', _set(ISO + [1, 'points'], [])),
    ('an isolation of 17 points', 'limit', _set(ISO + [1, 'points'], [
        {'kks': GAUGE, 'kind': 'instrument', 'how': f'Point {i}'} for i in range(17)])),
    ('a safe value that does not exist', 'bad_ref', _set(ISO + [0, 'points', 0, 'safe'], 'pump_safe')),
    ("a point's how over 200 characters", 'bad_type', _set(ISO + [0, 'points', 0, 'how'], 'x' * 201)),
    ("a value named like an isolation's value", 'dup_id', _app(MOD + ['values'], ['iso_pump_complete', {'const': 1}])),
    ("a value named like a work's permit", 'dup_id', _app(MOD + ['values'], ['wo_pump_permit', {'const': 1}])),
    ("an ext value named like an isolation's value", 'dup_id', _all(
        _set(['plant.json', 'ext'], ['ambient_t', 'iso_gauge_locked']),
        _set(['scenarios/s1.json', 'init', 'iso_gauge_locked'], 0))),
    ('a work whose isolation is a list', 'bad_id', _set(WORK + [0, 'isolation'], [])),
    ('a work whose isolation is an object', 'bad_id', _set(WORK + [0, 'isolation'], {})),
    ('a model file that is a list', 'bad_type', lambda F: F.__setitem__('model/a1.json', [])),
    ('a work naming an isolation that does not exist', 'bad_ref', _set(WORK + [0, 'isolation'], 'iso_motor')),
    ('a work on equipment that does not exist', 'bad_ref', _set(WORK + [0, 'kks'], '10LAC10AP009')),
    ('a work of an unknown discipline', 'bad_value', _set(WORK + [0, 'discipline'], 'paint')),
    ('a work with an unknown permit kind', 'bad_value', _set(WORK + [0, 'permit'], 'cold')),
    ('a work setting a value that is not a state', 'bad_ref', _set(WORK + [1, 'set'], {'flow': 0})),
    ('a work repairing a fault that is not an identifier', 'bad_id', _set(WORK + [0, 'repairs'], 'F 1')),
    ('two works with one id', 'dup_id', _set(WORK + [1, 'id'], 'wo_pump')),
    ('a work id over 22 characters', 'bad_id', _set(WORK + [1, 'id'], 'w' * 23)),
    ('over 128 works', 'limit', _set(WORK, [{'id': f'w{i}', 'kks': PUMP, 'title': 'W', 'discipline': 'mech',
                                              'permit': 'general'} for i in range(129)])),
    ('a scenario setting a hold to text', 'bad_number', _set(['scenarios/s1.json', 'init', 'p_held'], 'x')),
    # screens.json's desks (§14)
    ('desks in a version 1 screens.json', 'unknown_key', _set(SCR + ['desks'], [PUMP])),
    ("a screen's desks naming no operator desk", 'bad_ref', _all(_set(['screens.json', 'version'], 2),
                                                                 _set(SCR + ['desks'], [PUMP]))),
    ("the overview's desks empty", 'bad_length', _all(_set(['screens.json', 'version'], 2),
                                                      _set(['screens.json', 'overview', 'desks'], []))),
    ('screens.json of version 3', 'bad_version', _set(['screens.json', 'version'], 3)),
]


def build_rejects2():
    out = []
    base = mini2()
    for why, code, change in REJECTS2:
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


def unit_models2():
    """Format 2's unit runs (§19): models with permits, isolations and holds, inputs as Recorder.inputs."""
    pump = {
        'values': [
            ['pump_cmd', {'state': 0, 'kks': PUMP}], ['pump_fault', {'state': 0, 'kks': PUMP}],
            ['valve_cmd', {'state': 0, 'kks': VALVE}], ['aux', {'state': 0}], ['aux2', {'state': 0}],
            ['pump_off', {'not': 'pump_cmd'}], ['valve_shut', {'not': 'valve_cmd'}],
            ['valve_open', {'cmp': ['valve_cmd', '>=', 0.5]}],
            ['aux_hi', {'cmp': ['aux', '>=', 1]}], ['trip_c', {'cmp': ['aux', '>=', 2]}],
            ['il_c', {'cmp': ['aux', '>=', 3]}], ['p', {'product': ['pump_cmd', 5], 'kks': GAUGE}],
            ['p_high', {'cmp': ['p', '>', 4]}], ['permit_seen', {'product': ['wo_p_permit', 1]}],
            ['locked_seen', {'product': ['iso_p_locked', 1]}], ['complete_seen', {'lag': 'iso_p_complete', 'tau': 0.1}]],
        'ops': [{'kks': PUMP, 'do': 'start', 'set': {'pump_cmd': 1}, 'needs': [['valve_open', 'Valve closed']],
                 'where': ['local', 'screen']},
                {'kks': PUMP, 'do': 'stop', 'set': {'pump_cmd': 0}, 'where': ['local', 'screen']},
                {'kks': PUMP, 'do': 'reset', 'trip': 'tp', 'where': ['screen']},
                {'kks': VALVE, 'do': 'open', 'set': {'valve_cmd': 1}, 'where': ['local']},
                {'kks': VALVE, 'do': 'close', 'set': {'valve_cmd': 0}, 'where': ['local']},
                {'kks': TANK, 'do': 'set', 'input': 'aux', 'range': [0, 9], 'where': ['screen']},
                {'kks': TANK, 'do': 'start', 'set': {'pump_cmd': 1, 'aux2': 1}, 'where': ['screen']},
                {'kks': TANK, 'do': 'go', 'machine': 'm', 'where': ['screen']},
                {'kks': TANK, 'do': 'back', 'machine': 'm', 'where': ['screen']},
                {'kks': GAUGE, 'do': 'set', 'input': 'pump_cmd', 'range': [0, 1], 'where': ['screen']}],
        'interlocks': [{'id': 'il', 'when': 'il_c', 'do': [{'set': {'pump_cmd': 1, 'aux2': 2}}]}],
        'machines': [{'id': 'm', 'kks': TANK, 'init': 'idle',
                      'commands': {'go': {'from': ['idle'], 'to': 'run'}, 'back': {'from': '*', 'to': 'idle'}},
                      'states': [{'id': 'idle', 'watch': False}, {'id': 'run', 'set': {'pump_cmd': 1}, 'watch': False}]}],
        'trips': [{'id': 'tp', 'kks': TANK, 'text': 'Aux high', 'when': 'trip_c', 'do': [{'set': {'valve_cmd': 1}}]}],
        'alarms': [{'id': 'alp', 'kks': PUMP, 'text': 'Aux high at the pump', 'when': 'aux_hi', 'priority': 3,
                    'where': PUMP},
                   {'id': 'alt', 'kks': TANK, 'text': 'Aux high at the tank', 'when': 'aux_hi', 'priority': 3,
                    'where': TANK}],
        'isolations': [
            {'id': 'iso_p', 'text': 'Pump: motor and valve',
             'points': [{'kks': PUMP, 'kind': 'electrical', 'safe': 'pump_off', 'how': 'Breaker locked'},
                        {'kks': VALVE, 'kind': 'mechanical', 'safe': 'valve_shut', 'how': 'Valve chained'}]},
            {'id': 'iso_q', 'text': 'Pump: motor only',
             'points': [{'kks': PUMP, 'kind': 'electrical', 'safe': 'pump_off', 'how': 'Breaker locked'}]}],
        'works': [{'id': 'wo_p', 'kks': PUMP, 'title': 'Pump bearing', 'discipline': 'mech', 'permit': 'general',
                   'isolation': 'iso_p', 'repairs': 'f1', 'set': {'valve_cmd': 0, 'aux2': 5}},
                  {'id': 'wo_q', 'kks': PUMP, 'title': 'Pump motor', 'discipline': 'elec', 'permit': 'electrical',
                   'isolation': 'iso_q', 'set': {'pump_cmd': 1, 'aux2': 7}},
                  {'id': 'wo_p2', 'kks': VALVE, 'title': 'Valve packing', 'discipline': 'mech', 'permit': 'general',
                   'isolation': 'iso_p'},
                  {'id': 'wo_n', 'kks': TANK, 'title': 'Tank inspection', 'discipline': 'civil', 'permit': 'confined',
                   'set': {'aux': 1}, 'repairs': 'nofault'}]}
    faults = [{'id': 'f1', 'set': {'pump_fault': 1}, 'text': 'Pump bearing worn', 'kks': PUMP,
               'repair': {'pump_fault': 0}},
              {'id': 'f2', 'set': {'pump_cmd': 1}, 'text': 'Trainer starts the pump', 'repair': {'pump_cmd': 0}}]
    channels = {
        'values': [
            ['x', {'state': 0}], ['w', {'state': 0}],
            ['g1', {'sum': ['x', 0], 'kks': GAUGE}],
            ['g1h', {'hold': 'g1', 'when': 'iso_g_complete', 'kks': GAUGE}],
            ['g2', {'sum': ['x', 0.5]}], ['g3', {'sum': ['x', -0.5]}],
            ['g1h_hi', {'cmp': ['g1h', '>', 5]}],
            ['v1', {'or': ['g1h_hi', 'iso_g_complete']}],
            ['v2', {'cmp': ['g2', '>', 5]}], ['v3', {'cmp': ['g3', '>', 5]}],
            ['votes', {'sum': ['v1', 'v2', 'v3']}],
            ['trip_c', {'cmp': ['votes', '>=', 2]}],
            ['h_init', {'hold': 'x', 'when': 'w', 'init': 7}],
            ['h_sc', {'hold': 'x', 'when': 'w'}],
            ['h_free', {'hold': 'g2', 'when': 'w'}],
            ['h_later', {'hold': 'x', 'when': 'later'}],
            ['h_num', {'hold': 3, 'when': 'w'}],
            ['later', {'cmp': ['w', '>=', 2]}]],
        'ops': [{'kks': TANK, 'do': 'set', 'input': 'x', 'range': [-9, 9], 'where': ['screen']},
                {'kks': PUMP, 'do': 'set', 'input': 'w', 'range': [0, 9], 'where': ['screen']},
                {'kks': TANK, 'do': 'reset', 'trip': 't', 'where': ['screen']}],
        'trips': [{'id': 't', 'kks': TANK, 'text': 'Two of three high', 'when': 'trip_c', 'do': [{'set': {'w': 0}}]}],
        'alarms': [{'id': 'a1', 'kks': GAUGE, 'text': 'Channel 1 high', 'when': 'g1h_hi', 'priority': 2,
                    'where': GAUGE},
                   {'id': 'a2', 'kks': TANK, 'text': 'Channel 2 high', 'when': 'v2', 'priority': 2, 'where': TANK}],
        'isolations': [{'id': 'iso_g', 'text': 'Channel 1', 'points': [
            {'kks': GAUGE, 'kind': 'instrument', 'how': 'Root valve shut'}]}],
        'works': [{'id': 'wo_g', 'kks': GAUGE, 'title': 'Channel 1 calibration', 'discipline': 'inst',
                   'permit': 'general', 'isolation': 'iso_g'}]}
    P_, Q_, P2, N_ = 'wo_p', 'wo_q', 'wo_p2', 'wo_n'

    def pm(n, w, a, who=None):
        return [n, 'permit', w, a, who]

    def lk(n, w, pt, who=None):
        return [n, 'lock', w, pt, who]

    def ul(n, w, pt, who=None):
        return [n, 'unlock', w, pt, who]

    def op(n, kks, do, value=None, trip=None):
        return [n, 'op', kks, do, value, trip]

    life = [
        [1, 'fault', 'f1'], pm(1, P_, 'approve'), pm(1, P_, 'request'), pm(1, P_, 'request'), pm(1, P2, 'approve'),
        pm(1, P2, 'request'), pm(1, P_, 'issue'),
        lk(2, P_, 0), pm(2, P_, 'bogus'), pm(2, 'nope', 'request'), pm(2, 7, 'request'), lk(2, N_, 0), lk(2, P_, 5),
        lk(2, P_, -1), lk(2, P_, True), lk(2, P_, 1.0), lk(2, 'nope', 0), ul(2, P_, 'x'), pm(2, P_, 'approve', 'tech1'),
        lk(2, P_, 0, 'tech1'),
        pm(3, P_, 'approve'),
        op(4, VALVE, 'open'), op(5, PUMP, 'start'),
        lk(6, P_, 0), op(7, PUMP, 'stop'),
        op(8, PUMP, 'start'), lk(8, P_, 0),
        op(9, PUMP, 'stop'), lk(9, P_, 0), lk(9, P_, 0),
        op(10, VALVE, 'close'), lk(10, P_, 1), ul(10, P_, 1), ul(10, P2, 0),
        lk(11, P_, 1),
        op(12, PUMP, 'start'), op(12, PUMP, 'stop'), [12, 'repair', 'f1'],
        op(13, TANK, 'set', 3), op(13, TANK, 'start'), op(13, GAUGE, 'set', 1), op(13, TANK, 'go'), [13, 'fault', 'f2'],
        op(14, PUMP, 'reset', None, 'tp'), op(14, TANK, 'set', 0), [14, 'repair', 'f2'],
        op(15, PUMP, 'reset', None, 'tp'), op(15, TANK, 'back'),
        pm(16, P_, 'issue'), pm(16, P_, 'accept'), pm(16, P_, 'return'),
        pm(17, P_, 'done'),
        pm(18, P_, 'return'), lk(18, P_, 0), pm(18, P_, 'close'),
        ul(19, P_, 0), ul(19, P_, 0),
        ul(20, P_, 1),
        pm(21, P_, 'close'), pm(21, P2, 'request'),
        pm(22, P_, 'request'), op(22, PUMP, 'reset', None, 'tp'),
        pm(23, P2, 'cancel'), pm(23, P_, 'request'), pm(23, P_, 'cancel'), pm(23, P_, 'request')]
    shared = [
        pm(1, Q_, 'request'), pm(1, P_, 'request'), pm(2, Q_, 'approve'), pm(2, P_, 'approve'),
        lk(3, Q_, 0), lk(3, P_, 0), lk(3, P_, 1),
        op(4, PUMP, 'start'), op(4, TANK, 'set', 1),
        pm(5, Q_, 'issue'), pm(5, Q_, 'accept'), pm(5, Q_, 'done'),
        pm(6, Q_, 'return'), ul(7, Q_, 0), pm(8, Q_, 'close'),
        pm(9, P_, 'cancel'), lk(9, P_, 0),
        pm(10, P_, 'request'), pm(10, P2, 'request'),
        ul(11, P_, 0), pm(12, P2, 'request'), ul(12, P_, 1), pm(13, P2, 'request'),
        pm(14, N_, 'request'), pm(14, N_, 'approve'),
        pm(15, N_, 'issue'), pm(15, N_, 'accept'), pm(15, N_, 'done'), pm(15, N_, 'return'),
        pm(16, N_, 'close'), pm(16, N_, 'request'),
        pm(17, Q_, 'request'), pm(17, Q_, 'approve'), lk(18, Q_, 0),
        pm(19, Q_, 'issue'), pm(19, Q_, 'accept'), pm(19, Q_, 'done')]
    G_ = 'wo_g'
    chan = [
        [1, 'op', TANK, 'set', 3, None], [2, 'op', PUMP, 'set', 1, None],
        pm(3, G_, 'request'), pm(3, G_, 'approve'), lk(3, G_, 0), [3, 'op', PUMP, 'set', 0, None],
        [3, 'op', TANK, 'set', 3.5, None],
        [5, 'op', TANK, 'set', 4.8, None], ul(6, G_, 0), lk(7, G_, 0),
        [8, 'op', TANK, 'set', 5.2, None], [8, 'op', PUMP, 'set', 2, None],
        [11, 'op', TANK, 'set', 0, None], [12, 'op', TANK, 'reset', None, 't'],
        [13, 'op', PUMP, 'set', 0, None],
        pm(14, G_, 'issue'), pm(14, G_, 'accept'), pm(14, G_, 'done'), pm(14, G_, 'return'), ul(15, G_, 0),
        [15, 'op', TANK, 'set', 6, None], [18, 'ack', 'a1'], pm(19, G_, 'close')]
    return [
        ("a permit's life: request, approve, the automatic moves, issue, accept, done (its repair and set), return, "
         "close; every refusal (state, iso_busy, authority, unknown); locks against this step's values (a start or a "
         "stop and a lock in one step); what a locked code refuses, skips and suppresses; a fault or a repair asked on a "
         "locked code not made (the work's done repairs the fault)", pump, faults, life, 24),
        ('a code locked by two isolations; a done write made only when every isolation locking its code is held by '
         'the work; a cancel with points still locked; a work without an isolation', pump, faults, shared, 20),
        ('an isolated transmitter: its reading held, its alarm suppressed, its 2-out-of-3 vote tripped; unlocked from '
         'isolated (the permit back to approved) and locked again; the hold node at step 0 (its init, the '
         'scenario\'s, its input), reading a later when, a number',
         channels, [], chan, 20),
    ]


def unit_bundle2(model, init, faults):
    F = mini2()
    F['model/a1.json'] = dict({'format': 'walkdown-plant-model', 'version': 2, 'area': 'a1'}, **model)
    F['scenarios/s1.json'] = {'format': 'walkdown-plant-scenario', 'version': 2, 'id': 's1', 'title': 'Units',
                              'init': dict(init), 'faults': faults}
    for rel in ('procedures/p1.json', 'screens.json'):
        del F[rel]
    return F, check(F)


def build_steps2():
    out = []
    for why, model, faults, inputs, n in unit_models2():
        init = {'ambient_t': 20}
        if 'h_sc' in [v[0] for v in model['values']]:
            init['h_sc'] = -2
        F, b = unit_bundle2(model, init, faults)
        e = P.Engine(b, 's1')
        states = [e.snapshot()]
        i = 0
        while e.step_no < n:
            while i < len(inputs) and inputs[i][0] == e.step_no + 1:
                apply(e, inputs[i])
                i += 1
            e.step()
            states.append(e.snapshot())
        assert i == len(inputs), why
        out.append({'why': why, 'model': F['model/a1.json'], 'scenario': F['scenarios/s1.json'], 'inputs': inputs,
                    'states': states, 'events': e.events})
    return out


# Format 2's forks from the cold start (PLANT3D §19; milestone P1: a permit to work on the first train, run in free
# mode as the several roles in turn). Actions as FORKS, and ('permit', work, action), ('lock' | 'unlock', work, point).
def permit_run(work, isolate, work_s=60):
    """A whole permit in free mode: request, approve, the points locked (isolate: their indexes), issue, accept,
    the work, done, return, the points unlocked, close."""
    a = [('permit', work, 'request'), ('run', 1), ('permit', work, 'approve'), ('run', 1)]
    a += [('lock', work, i) for i in isolate] + [('run', 1)]
    a += [('permit', work, 'issue'), ('permit', work, 'accept'), ('run', work_s), ('permit', work, 'done'),
          ('run', 1), ('permit', work, 'return'), ('run', 1)]
    a += [('unlock', work, i) for i in isolate] + [('run', 1), ('permit', work, 'close'), ('run', 1)]
    return a


CW_B, CW_B_V = '30PAC10AP002', '30PAC10AA102'
FORKS2 = [
    # CW pump B locked out at base load: stopped, its valve closed, both locked; its start refused while locked; its
    # trip latched by the fault stays latched (no reset on a locked code); the motor repaired by the work's done
    ('cw_b_locked_out', 'end',
     [('fault', 'cw_b_motor'), ('run', 20),
      ('permit', 'wo_cw_b_motor', 'request'), ('run', 1), ('permit', 'wo_cw_b_motor', 'approve'), ('run', 1),
      ('lock', 'wo_cw_b_motor', 0), ('lock', 'wo_cw_b_motor', 1), ('run', 90), ('lock', 'wo_cw_b_motor', 1),
      ('run', 1),
      ('op', CW_B, 'start', None, None), ('op', CW_B, 'reset', None, 'cw_b_trip_ol'),
      ('op', CW_B_V, 'set', 0.15, None), ('run', 1),
      ('permit', 'wo_cw_b_motor', 'issue'), ('permit', 'wo_cw_b_motor', 'accept'), ('run', 60),
      ('permit', 'wo_cw_b_motor', 'done'), ('run', 1), ('permit', 'wo_cw_b_motor', 'return'), ('run', 1),
      ('unlock', 'wo_cw_b_motor', 0), ('unlock', 'wo_cw_b_motor', 1), ('run', 1),
      ('permit', 'wo_cw_b_motor', 'close'), ('run', 1),
      ('op', CW_B, 'reset', None, 'cw_b_trip_ol'), ('run', 1), ('op', CW_B_V, 'set', 0.15, None),
      ('until', 'cw_b_vstart', 120), ('op', CW_B, 'start', None, None), ('run', 10)],
     {'refused': [[CW_B, 'start', ['cw_b_vstart', 'cw_b_trips_clear', 'cw_b_ok', 'iso_cw_b_locked']],
                  [CW_B, 'reset', ['iso_cw_b_locked']], [CW_B_V, 'set', ['iso_cw_b_locked']]],
      'lock_refused': [['wo_cw_b_motor', 1, ['cw_b_v_safe']]],
      'repaired': ['cw_b_motor'], 'permits': {'wo_cw_b_motor': 9}, 'done': [[CW_B, 'start']],
      'end': {'cw_b_run': [1, 1], 'iso_cw_b_locked': [0, 0]}}),
    # a start and a lock in one step: the start is done in step 1, so the pump is not safe in step 3
    ('cw_c_start_and_lock', 'end',
     [('permit', 'wo_cw_c_motor', 'request'), ('permit', 'wo_cw_c_motor', 'approve'), ('run', 1),
      ('op', '30PAC10AA103', 'set', 0.15, None), ('until', 'cw_c_vstart', 60),
      ('op', '30PAC10AP003', 'start', None, None), ('lock', 'wo_cw_c_motor', 0), ('run', 1),
      ('permit', 'wo_cw_c_motor', 'cancel'), ('run', 1)],
     {'done': [['30PAC10AP003', 'start']], 'lock_refused': [['wo_cw_c_motor', 0, ['cw_c_safe']]],
      'permits': {'wo_cw_c_motor': 10}}),
    # the standby CCW pump locked out: when the running one trips, the auto-start's interlock fires and its write is
    # skipped (the plant loses its closed cooling water, as it would)
    ('ccw_b_locked_auto_start_skipped', 'end',
     [('permit', 'wo_ccw_b_motor', 'request'), ('permit', 'wo_ccw_b_motor', 'approve'), ('run', 1),
      ('lock', 'wo_ccw_b_motor', 0), ('run', 1), ('fault', 'ccw_a_motor'), ('run', 30)],
     {'interlocks': ['ccw_b_auto'], 'first_out': {'ccw': 'ccw_a_trip'}, 'permits': {'wo_ccw_b_motor': 3},
      'end': {'ccw_b_cmd': [0, 0], 'ccw_b_run': [0, 0]}}),
    # a condenser pressure transmitter isolated: its reading held, its vote tripped (1 out of 2 on the others), its
    # alarms suppressed while the condenser pressure rises after the CW pumps are lost; the turbine still trips
    ('cond_p2_isolated', 'end',
     [('permit', 'wo_cond_p2_cal', 'request'), ('permit', 'wo_cond_p2_cal', 'approve'), ('run', 1),
      ('lock', 'wo_cond_p2_cal', 0), ('run', 2), ('fault', 'cw_ab_fail'), ('run', 300)],
     {'first_out': {'st': 'st_trip_cond_p'}, 'alarms': ['cond_p1_h', 'cond_p1_hh', 'cond_p3_h', 'cond_p3_hh'],
      'no_alarms': ['cond_p2_h', 'cond_p2_hh'], 'permits': {'wo_cond_p2_cal': 3},
      'end': {'cond_p2_vote': [1, 1], 'cond_p2': [3, 12]}, 'max': {'cond_p': [25, 200]}}),
    # the isolated transmitter alone: the trip runs 1 out of 2, nothing trips at normal pressure
    ('cond_p3_isolated_calm', 'end',
     [('permit', 'wo_cond_p3_cal', 'request'), ('permit', 'wo_cond_p3_cal', 'approve'), ('run', 1),
      ('lock', 'wo_cond_p3_cal', 0), ('run', 60)],
     {'no_trip': True, 'end': {'cond_hh_v': [1, 1], 'cond_p3_vote': [1, 1]}, 'permits': {'wo_cond_p3_cal': 3}}),
    # a cooling tower fan's service: stopped, locked out, worked, returned, run again
    ('ct_fan3_service', 'end',
     [('fault', 'ct_fan3_vib'), ('run', 60)] + permit_run('wo_ct_fan3', [0], 120) +
     [('op', '30PAD10CY003', 'reset', None, 'ct_fan3_trip_vib'), ('run', 1),
      ('op', '30PAD10AN003', 'start', None, None), ('run', 60)],
     {'repaired': ['ct_fan3_vib'], 'permits': {'wo_ct_fan3': 9}, 'done': [['30PAD10AN003', 'start']],
      'end': {'ct_fan3_cmd': [1, 1], 'ct_fan3_vib': [0, 5]}}),
]


# The first train's ties to the water treatment plant (WATER-TREATMENT §8): the makeup pump stopped at base load (the
# basin's makeup is gone at once), and the plant's demineralised water tank drained with no transfer (its low alarm in
# the train's control room)
FORKS2 += [
    ('makeup_pump_stopped', 'end', [('op', '00GHB10AP001', 'stop', None, None), ('run', 60)],
     {'done': [['00GHB10AP001', 'stop']], 'end': {'ct_mk_flow': [0, 0], 'ct_net': [-100000, -1]}}),
    ('demin_tank_drained', 'end', [('op', '00GHC10AP001', 'stop', None, None), ('fault', 'dm_drain'), ('run', 2400)],
     {'alarms': ['dm_low'], 'end': {'dm_lvl': [0, 30], 'tr_q': [0, 0]}}),
]

# Forks from the water treatment plant's start from cold (wtp_start), one for each of its trips and interlocks and for
# the refusals the procedure's order avoids (WATER-TREATMENT §5–§7)
RO_B_ON = [('op', '00GCB22AT001', 'start', None, None), ('until', 'ro_b_is3', 1200)]
WTP_FORKS = [
    ('rw_a_overload', 'end', [('fault', 'rw_a_motor'), ('run', 10)],
     {'first_out': {'rw': 'rw_a_trip_ol'}, 'alarms': ['rw_a_tripped']}),
    ('rw_b_overload', 'end', [('fault', 'rw_b_motor'), ('run', 10)],
     {'first_out': {'rw': 'rw_b_trip_ol'}, 'alarms': ['rw_b_tripped']}),
    ('rw_c_overload', 'end', [('op', '00GAF10AP003', 'start', None, None), ('run', 10), ('fault', 'rw_c_motor'),
                              ('run', 10)],
     {'done': [['00GAF10AP003', 'start']], 'first_out': {'rw': 'rw_c_trip_ol'}, 'alarms': ['rw_c_tripped']}),
    ('intake_low_low', 'end', [('op', '00GAF10AP003', 'start', None, None), ('run', 10), ('fault', 'screen_clog'),
                               ('run', 300)],
     {'first_out': {'rw': 'rw_a_trip_ll'}, 'tripped': ['rw_b_trip_ll', 'rw_c_trip_ll'],
      'alarms': ['rw_lvl_low', 'rw_lvl_ll'], 'end': {'rw_flow': [0, 0]}}),
    ('intake_low_start_refused', 'end', [('fault', 'screen_clog'), ('until', 'rw_l', 300),
                                         ('op', '00GAF10AP003', 'start', None, None), ('run', 1)],
     {'refused': [['00GAF10AP003', 'start', ['rw_lvl_ok']]]}),
    ('ro_a_suction', 'end', [('fault', 'cart_a_clog'), ('run', 700)],
     {'first_out': {'ro_a': 'ro_a_trip_suct'}, 'alarms': ['cf_a_dp_h', 'ro_a_suct_ll'],
      'machines': {'ro_a': 'stopped'}}),
    ('ro_a_chlorine', 'end', [('fault', 'sbs_pump'), ('run', 120)],
     {'first_out': {'ro_a': 'ro_a_trip_orp'}, 'alarms': ['ro_a_orp_h', 'ro_a_orp_hh'], 'machines': {'ro_a': 'stopped'}}),
    ('ro_a_pressure', 'end', [('fault', 'ro_a_conc_stuck'), ('run', 60)],
     {'first_out': {'ro_a': 'ro_a_trip_p'}, 'alarms': ['ro_a_p_h', 'ro_a_p_hh']}),
    ('ro_a_restart_refused', 'end', [('fault', 'ro_a_conc_stuck'), ('run', 60),
                                     ('op', '00GCB21AT001', 'start', None, None), ('run', 1)],
     {'refused': [['00GCB21AT001', 'start', ['ro_a_no_trip']]]}),
    ('ro_a_permeate_bad', 'end', [('fault', 'ro_a_oring'), ('run', 120), ('repair', 'ro_a_oring'), ('run', 120)],
     {'interlocks': ['ro_a_to_drain', 'ro_a_to_service'], 'alarms': ['ro_a_cond_h'], 'repaired': ['ro_a_oring'],
      'end': {'ro_a_bad': [0, 0]}}),
    ('ro_b_suction', 'end', RO_B_ON + [('fault', 'cart_b_clog'), ('run', 700)],
     {'done': [['00GCB22AT001', 'start']], 'first_out': {'ro_b': 'ro_b_trip_suct'}, 'alarms': ['cf_b_dp_h']}),
    ('ro_b_chlorine', 'end', RO_B_ON + [('fault', 'sbs_pump'), ('run', 120)],
     {'first_out': {'ro_a': 'ro_a_trip_orp', 'ro_b': 'ro_b_trip_orp'}, 'alarms': ['ro_b_orp_hh']}),
    ('ro_b_pressure', 'end', RO_B_ON + [('fault', 'ro_b_conc_stuck'), ('run', 60)],
     {'first_out': {'ro_b': 'ro_b_trip_p'}, 'alarms': ['ro_b_p_hh']}),
    ('ro_b_permeate_bad', 'end', RO_B_ON + [('fault', 'ro_b_oring'), ('run', 120), ('repair', 'ro_b_oring'),
                                            ('run', 120)],
     {'interlocks': ['ro_b_to_drain', 'ro_b_to_service'], 'alarms': ['ro_b_cond_h']}),
    ('ro_start_without_chemicals', 'service', [('op', '00GCB21AT001', 'start', None, None), ('run', 1)],
     {'refused': [['00GCB21AT001', 'start', ['sbs_on', 'as_on']]]}),
    ('ro_start_without_feed', 'makeup', [('op', '00GCB21AT001', 'start', None, None), ('run', 1)],
     {'refused': [['00GCB21AT001', 'start', ['ro_a_suct_ok', 'sbs_on', 'as_on']]]}),
    ('mb_feed_low_low', 'end', [('op', '00GCK10AP002', 'start', None, None), ('op', '00GCB21AT001', 'stop', None, None),
                                ('run', 1500)],
     {'first_out': {'mb_feed': 'mf_a_trip_ll'}, 'tripped': ['mf_b_trip_ll']}),
    ('mb_a_exhausted', 'end', [('fault', 'mb_a_early'), ('run', 600), ('op', '00GCF12AT001', 'in_service', None, None),
                               ('op', '00GCK10AP002', 'start', None, None), ('run', 30)],
     {'interlocks': ['mb_a_exhausted'], 'alarms': ['mb_a_cond_h', 'mb_a_si_h'], 'machines': {'mb_a': 'recirc'},
      'done': [['00GCF12AT001', 'in_service'], ['00GCK10AP002', 'start']]}),
    ('mb_a_exhausted_refused', 'end', [('fault', 'mb_a_early'), ('run', 600),
                                       ('op', '00GCF11AT001', 'in_service', None, None), ('run', 1)],
     {'refused': [['00GCF11AT001', 'in_service', ['mb_a_good']]]}),
    ('mb_b_exhausted', 'end', [('op', '00GCF12AT001', 'in_service', None, None),
                               ('op', '00GCK10AP002', 'start', None, None), ('run', 30), ('fault', 'mb_b_early'),
                               ('run', 900)],
     {'interlocks': ['mb_b_exhausted'], 'machines': {'mb_b': 'recirc'}}),
    ('tr_a_overload', 'end', [('fault', 'tr_a_motor'), ('run', 10)],
     {'first_out': {'transfer': 'tr_a_trip_ol'}, 'alarms': ['tr_a_tripped']}),
    ('tr_b_overload', 'end', [('op', '00GHC10AP002', 'start', None, None), ('run', 10), ('fault', 'tr_b_motor'),
                              ('run', 10)],
     {'first_out': {'transfer': 'tr_b_trip_ol'}, 'alarms': ['tr_b_tripped']}),
    ('demin_tank_low_low', 'end', [('op', '00GHC10AP002', 'start', None, None), ('fault', 'dt_drain'), ('run', 300)],
     {'first_out': {'transfer': 'tr_a_trip_ll'}, 'tripped': ['tr_b_trip_ll'], 'alarms': ['dt_a_low', 'dt_a_ll'],
      'end': {'tr_q': [0, 0.001]}}),
    ('backwash_one_at_a_time', 'end', [('op', '00GBB11AT001', 'backwash', None, None), ('run', 1),
                                       ('op', '00GBB12AT001', 'backwash', None, None), ('run', 1)],
     {'done': [['00GBB11AT001', 'backwash']], 'refused': [['00GBB12AT001', 'backwash', ['bw_free']]]}),
    # two backwashes commanded in one step both pass the permissive (it reads the previous step): filter 1 goes on,
    # filter 2 goes back to service
    ('backwash_two_in_one_step', 'end', [('op', '00GBB11AT001', 'backwash', None, None),
                                         ('op', '00GBB12AT001', 'backwash', None, None), ('run', 30)],
     {'done': [['00GBB11AT001', 'backwash'], ['00GBB12AT001', 'backwash']],
      'machines': {'filter1': 'drain', 'filter2': 'service'}, 'end': {'bw_n': [1, 1], 'filter2_state': [0, 0]}}),
    # a filter on standby is not being backwashed: its head loss stays, another filter washes, and it washes itself
    ('filter_standby_then_backwash', 'end', [('op', '00GBB12AT001', 'take_out', None, None), ('run', 60),
                                             ('op', '00GBB11AT001', 'backwash', None, None), ('until', 'fl1_clean', 600),
                                             ('op', '00GBB12AT001', 'backwash', None, None), ('until', 'fl2_clean', 600)],
     {'done': [['00GBB12AT001', 'take_out'], ['00GBB11AT001', 'backwash'], ['00GBB12AT001', 'backwash']],
      'machines': {'filter1': 'rinse', 'filter2': 'service'}, 'max': {'fl2_hl': [0.7, 0.9]}}),
    ('filter_put_back', 'end', [('op', '00GBB12AT001', 'take_out', None, None), ('run', 60),
                                ('op', '00GBB12AT001', 'put_in', None, None), ('run', 1)],
     {'done': [['00GBB12AT001', 'put_in']], 'machines': {'filter2': 'service'}, 'end': {'fl2_hl': [0.7, 0.9]}}),
    ('pit_ph_blocked', 'end', [('op', '00GNR10AP001', 'start', None, None), ('run', 10), ('fault', 'nr_ph_drift'),
                               ('run', 200), ('op', '00GNR10AP001', 'start', None, None), ('run', 1)],
     {'interlocks': ['nr_blocked'], 'alarms': ['nr_ph'], 'refused': [['00GNR10AP001', 'start', ['nr_ph_ok']]]}),
    ('pit_emptied', 'end', [('op', '00GNR10AP001', 'start', None, None), ('run', 1200)],
     {'interlocks': ['nr_empty'], 'end': {'nr_a_cmd': [0, 0]}}),
]

# W3 (WATER-TREATMENT §7): the remaining faults, from the WTP started from cold
WTP_FORKS += [
    ('antiscalant_pump_fails', 'end', [('fault', 'as_pump'), ('run', 10)],
     {'alarms': ['as_a_noflow'], 'end': {'as_dose_on': [0, 0], 'as_on': [1, 1]}}),
    ('coagulant_pump_no_flow', 'end', [('fault', 'coag_pump'), ('run', 10)], {'alarms': ['cg_a_noflow']}),
    # clarifier A's rake stalls: its turbidity alarms, B's not; the filters take the two mixed
    ('clarifier_upset', 'end', [('fault', 'cl_upset'), ('run', 900)],
     {'alarms': ['cla_ntu_h'], 'no_alarms': ['clb_ntu_h'], 'max': {'cla_ntu': [5, 20], 'cl_ntu': [3, 10]}}),
    ('filter3_breakthrough', 'end', [('fault', 'fl3_underdrain'), ('run', 30), ('repair', 'fl3_underdrain'),
                                     ('run', 30)],
     {'alarms': ['fl_ntu_h'], 'repaired': ['fl3_underdrain'], 'max': {'sdi': [4, 5]}, 'end': {'fl_ntu': [0, 0.2]}}),
    ('degasser_trip', 'end', [('fault', 'dg_motor'), ('run', 600)],
     {'tripped': ['dg_trip_ol'], 'alarms': ['dg_tripped', 'dg_co2_h'], 'end': {'dg_cmd': [0, 0]}}),
    ('degasser_restart_refused', 'end', [('fault', 'dg_motor'), ('run', 10),
                                         ('op', '00GCH10AN001', 'start', None, None), ('run', 1)],
     {'refused': [['00GCH10AN001', 'start', ['dg_fan_ok']]]}),
    # the bisulphite pump fails, the RO trips; reset and restarted without the fix (the failed pump still says
    # running), its start's flush with chlorinated feed damages the membranes (a fault of the scenario), which only
    # their replacement under a permit repairs
    ('ro_a_chlorine_damage', 'end',
     [('fault', 'sbs_pump'), ('run', 120), ('op', '00GCB21CQ002', 'reset', None, 'ro_a_trip_orp'), ('run', 1),
      ('op', '00GCB21AT001', 'start', None, None), ('run', 400)] + permit_run('wo_ro_a_membranes', [0]),
     {'faults': ['sbs_pump', 'ro_a_cl_damage'], 'repaired': ['ro_a_cl_damage'], 'permits': {'wo_ro_a_membranes': 9},
      'max': {'ro_a_dmg_k': [4, 4]}, 'end': {'ro_a_dmg': [0, 0], 'iso_ro_a_locked': [0, 0]}}),
    # resin leaks from mixed bed A: its strainer blocks; the bed taken out and its internals repaired under a permit
    ('mb_a_resin_leak', 'end',
     [('fault', 'mb_a_resin'), ('run', 600), ('op', '00GCK10AP001', 'stop', None, None),
      ('op', '00GCF11AT001', 'standby', None, None), ('run', 20),
      ('permit', 'wo_mb_a_resin', 'request'), ('run', 1), ('permit', 'wo_mb_a_resin', 'approve'), ('run', 1),
      ('lock', 'wo_mb_a_resin', 0), ('lock', 'wo_mb_a_resin', 1), ('run', 1),
      ('op', '00GCF11AT001', 'in_service', None, None), ('run', 1)] +
     permit_run('wo_mb_a_resin', [0, 1], 120)[4 + 3:],
     {'alarms': ['mb_a_dp_h'], 'refused': [['00GCF11AT001', 'in_service', ['iso_mb_a_locked']]],
      'repaired': ['mb_a_resin'], 'permits': {'wo_mb_a_resin': 9}}),
    # RO B fouling 200 times as fast: in five minutes what a month of the clock brings (from 0.05)
    ('ro_b_fast_fouling', 'end', RO_B_ON + [('fault', 'ro_b_fouling'), ('run', 300)],
     {'faults': ['ro_b_fouling'], 'end': {'ro_b_foul': [0.06, 0.08]}}),
]

# W3: the RO's cleaning in place (ro_cip) from the normal day's work, and its refusals and trip
CIP_FORKS = [
    ('cip_clean_refused_cold', 'fill', [('op', '00GCB30BB001', 'add_caustic', None, None), ('until', 'cip_ph_hi', 600),
                                        ('op', '00GCB22AT001', 'clean', None, None), ('run', 1)],
     {'refused': [['00GCB22AT001', 'clean', ['cip_ready']]]}),
    ('cip_one_train_at_a_time', 'caustic',
     [('op', '00GCB21AT001', 'stop', None, None), ('until', 'ro_a_stopped', 600),
      ('op', '00GCB22AT001', 'clean', None, None), ('op', '00GCB21AT001', 'clean', None, None), ('run', 30),
      ('op', '00GCB22AT001', 'clean', None, None), ('run', 1)],
     {'done': [['00GCB21AT001', 'clean']], 'refused': [['00GCB22AT001', 'clean', ['cip_free']]],
      'machines': {'ro_a': 'cip_circ1', 'ro_b': 'stopped'}}),
    ('cip_drain_refused_while_cleaning', 'caustic', [('op', '00GCB22AT001', 'clean', None, None), ('run', 10),
                                                     ('op', '00GCB30BB001', 'drain', None, None), ('run', 1)],
     {'refused': [['00GCB30BB001', 'drain', ['cip_free']]]}),
    ('cip_stop_cleaning', 'caustic', [('op', '00GCB22AT001', 'clean', None, None), ('run', 60),
                                      ('op', '00GCB22AT001', 'stop_cleaning', None, None), ('until', 'ro_b_stopped', 600)],
     {'done': [['00GCB22AT001', 'stop_cleaning']], 'machines': {'ro_b': 'cip_flush'}}),
    ('cip_overheat_b', 'caustic', [('fault', 'cip_heater'), ('op', '00GCB22AT001', 'clean', None, None),
                                   ('until', 'ro_b_trip_cip_t_latched', 1800), ('run', 10)],
     {'first_out': {'ro_b': 'ro_b_trip_cip_t'}, 'alarms': ['cip_t_h'], 'machines': {'ro_b': 'cip_flush'}}),
    ('cip_overheat_a', 'caustic', [('op', '00GCB21AT001', 'stop', None, None), ('until', 'ro_a_stopped', 600),
                                   ('fault', 'cip_heater'), ('op', '00GCB21AT001', 'clean', None, None),
                                   ('until', 'ro_a_trip_cip_t_latched', 1800), ('run', 10)],
     {'first_out': {'ro_a': 'ro_a_trip_cip_t'}, 'machines': {'ro_a': 'cip_flush'}}),
]

# W3: a mixed bed's regeneration (mb_regeneration) from the normal day's work, and its refusals
REGEN_FORKS = [
    ('regen_refused_feed_running', 'mb_b', [('op', '00GCF11AT001', 'standby', None, None), ('run', 1),
                                            ('op', '00GCF11AT001', 'regenerate', None, None), ('run', 1)],
     {'refused': [['00GCF11AT001', 'regenerate', ['mf_a_off']]]}),
    ('regen_one_bed_at_a_time', 'regen', [('op', '00GCK10AP002', 'stop', None, None),
                                          ('op', '00GCF12AT001', 'standby', None, None), ('run', 1),
                                          ('op', '00GCF12AT001', 'regenerate', None, None), ('run', 1)],
     {'refused': [['00GCF12AT001', 'regenerate', ['mb_regen_free']]]}),
    ('regen_two_in_one_step', 'mb_a_off', [('op', '00GCK10AP002', 'stop', None, None),
                                           ('op', '00GCF12AT001', 'standby', None, None), ('run', 1),
                                           ('op', '00GCF11AT001', 'regenerate', None, None),
                                           ('op', '00GCF12AT001', 'regenerate', None, None), ('run', 30)],
     {'done': [['00GCF11AT001', 'regenerate'], ['00GCF12AT001', 'regenerate']],
      'machines': {'mb_a': 'backwash', 'mb_b': 'standby'}, 'end': {'mb_b_state': [2, 2]}}),
    ('air_mix_refused_without_blower', 'inject', [('op', '00GCF11AT001', 'air_mix', None, None), ('run', 1)],
     {'refused': [['00GCF11AT001', 'air_mix', ['gp_air_cmd']]]}),
    ('regen_acid_tank_filled', 'mb_b', [('op', '00GCP10BB001', 'fill', None, None), ('until', 'gp_hcl_full', 900),
                                       ('run', 10)],
     {'done': [['00GCP10BB001', 'fill']], 'machines': {'gp_hcl_fill': 'idle'}, 'end': {'gp_hcl_lvl': [95, 100]}}),
    # the pit's probe drifts 3 pH low while the batch discharges: the discharge is blocked, and the batch doses caustic
    # into a pit that is already neutral (the true pH rises past 9: the lesson of a drifted probe)
    ('pit_probe_drift_during_discharge', 'end', [('fault', 'nr_ph_drift'), ('run', 600)],
     {'interlocks': ['nr_blocked'], 'machines': {'nr_batch': 'dosing'}, 'max': {'nr_ph_true': [9, 14]}}),
]


def build_train2(b):
    e, log, bases = run_cold_start(b)
    forks = []
    for fid, base, actions, expect in FORKS2:
        probes = sorted(set(expect.get('max', {})) | set(expect.get('end', {})))
        f, start, fin, fev, seen = run_fork(bases[base], actions, probes)
        fork = {'id': fid, 'base_step': start, 'inputs': fin, 'until': f.step_no, 'events': fev,
                'end': f.snapshot(values=False), 'expect': expect}
        if probes:
            fork['seen'] = seen
        forks.append(fork)
    return {'scenario': 'cold_iron', 'procedure': 'cold_start', 'inputs': e.inputs, 'until': e.step_no,
            'forks': forks}


def build2():
    F = mini2()
    return {'about': 'Walkdown Plant content format 2 vectors (docs/PLANT3D.md §19), made by '
                     'ref/make_plant3d_vectors.py from ref/plant3d.py. Numbers compare to 1e-6. Milestone P1: permits, '
                     'isolations and the hold node (§15); W2: the water treatment plant started from cold by its '
                     'procedure (`wtp`, as format 1\'s `train`); W3: an RO train cleaned in place (`wtp_cip`) '
                     'and a mixed bed regenerated (`wtp_regen`) by their procedures; staff (§16–§17) come with S1.',
            'valid': [{'why': 'the synthetic plant as version 2', 'files': {k: json.dumps(v, ensure_ascii=False)
                                                                           for k, v in F.items()},
                       'counts': check(F).counts}],
            'reject': build_rejects2(),
            'steps': build_steps2(),
            'train': build_train2(train_bundle()),
            'wtp': build_train(train_bundle(), 'wtp_cold', 'wtp_start', WTP_FORKS),
            'wtp_cip': build_train(train_bundle(), 'wtp_normal', 'ro_cip', CIP_FORKS),
            'wtp_regen': build_train(train_bundle(), 'wtp_normal', 'mb_regeneration', REGEN_FORKS)}


def build():
    F = mini()
    tb = train_bundle()
    counts = check(F).counts
    links = [{'link': u, 'expect': P.read_link(u, check(F))} for u in LINKS]
    return {'about': 'Walkdown Plant content format 1 vectors (docs/PLANT3D.md §12), made by '
                     'ref/make_plant3d_vectors.py from ref/plant3d.py. Numbers compare to 1e-6.',
            'valid': [{'why': 'the synthetic plant', 'files': {k: json.dumps(v, ensure_ascii=False)
                                                              for k, v in F.items()}, 'counts': counts}],
            'reject': build_rejects(),
            'steps': build_steps(),
            'links': links,
            'train': build_train(tb),
            'hot': build_train(tb, 'hot_restart', 'hot_restart', HOT_FORKS)}


def dump(v):
    return json.dumps(R(v), ensure_ascii=False, separators=(',', ':')) + '\n'


if __name__ == '__main__':
    bad = 0
    for out, make in ((OUT, build), (OUT2, build2)):
        if '--only-v2' in sys.argv and out == OUT:
            continue
        text = dump(make())
        if '--write' in sys.argv:
            with open(out, 'w', encoding='utf-8') as f:
                f.write(text)
            print(f'wrote {out}: {len(text)} bytes')
        else:
            same = os.path.exists(out) and open(out, encoding='utf-8').read() == text
            print(f'{out}: ' + ('up to date' if same else 'differs (run with --write)'))
            bad += not same
    sys.exit(1 if bad else 0)
