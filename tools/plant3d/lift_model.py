"""A service lift as model content (docs/PLANT3D.md §20.1, "How the content tool makes a lift"; decision 0071): the
cab, its landing gates and its controls as values, ops, an alarm and faults of §7, and the model's `lifts` entry that
names their handles for the engine and the staff. Used by the first train's content and by the vectors' small plant
(ref/make_plant3d_vectors.py).

    m = lift_model('hrsg1_lift', '10SNB10', [0, 12, 30])
    m['values'], m['ops'], m['alarms'], m['lift'], m['faults'], m['codes']

What it makes, for a lift `L` with landings 0 … n−1 (heights z rising):
- `L_target` (a state: the landing the cab is sent to), `L_estop` (the emergency stop), `L_main` (the main switch,
  1 on: an isolation's point), `L_drive_fault` (the drive's fault), per gate `L_gate<i>_cmd` (its command) and
  `L_gate<i>_switch` (a fault of its switch: it reads not shut);
- the gates' positions (ramps of their commands, `gate_s` to open or shut), `open` and `shut`;
- `L_ready` (the main switch on, no emergency stop, no drive fault), the load's limit (`L_load` is the engine's,
  §20.3), `L_run` (every gate shut and commanded shut, ready, the load within the rated load: a gate's `open` and a
  call done in one step, each against the step before, leave the cab where it stands until the gate is shut again);
- the cab's floor `L_z`, a ramp of `L_u` at `speed`, and `L_u` = `L_z` while the cab may not run, else the target's
  height (a ramp reads its input as the previous step left it, so a cab that may not run stays exactly where it is);
- per landing `L_at<i>`: level there and not about to move; `L_idle`: at its target with every gate shut;
- ops: each landing's call `start` and the panel's `set` need ready, idle and the load; a gate's `open` needs its
  landing's `at`; `close` needs nothing; the panel's `stop` and `start` press and release the emergency stop;
- the alarm `L_overload` (priority 3) while the load is over the rated load;
- the scenario faults `L_drive` (the drive) and `L_gate_switch` (landing 0's gate switch reads not shut).

Codes (KKS `SN` lifts; 0071): `AE001` the drive, `AB00<i+1>` the landing gates, `GH00<i+1>` the call stations,
`GH010` the cab panel, `CW001` the load cell; the caller places them as equipment."""


def lift_model(lid, kks, zs, *, rated_kg=500, person_kg=75, speed=0.6, gate_s=2):
    n = len(zs)
    codes = {'drive': kks + 'AE001', 'panel': kks + 'GH010', 'load': kks + 'CW001',
             'gates': [f'{kks}AB{i + 1:03d}' for i in range(n)], 'calls': [f'{kks}GH{i + 1:03d}' for i in range(n)]}
    v = []

    def val(name, node):
        v.append([name, node])
        return name

    L = lid
    target = val(f'{L}_target', {'state': 0, 'kks': codes['panel']})
    estop = val(f'{L}_estop', {'state': 0, 'kks': codes['panel']})
    main = val(f'{L}_main', {'state': 1, 'kks': codes['drive']})
    fault = val(f'{L}_drive_fault', {'state': 0, 'kks': codes['drive']})
    cmd = [val(f'{L}_gate{i}_cmd', {'state': 0, 'kks': codes['gates'][i]}) for i in range(n)]
    switch = [val(f'{L}_gate{i}_switch', {'state': 0, 'kks': codes['gates'][i]}) for i in range(n)]
    pos = [val(f'{L}_gate{i}_pos', {'ramp': cmd[i], 'rate': 1 / gate_s}) for i in range(n)]
    z = val(f'{L}_z', {'ramp': f'{L}_u', 'rate': speed, 'init': zs[0], 'unit': 'm', 'kks': codes['drive']})
    opened, shut, down = [], [], []
    for i in range(n):
        opened.append(val(f'{L}_open{i}', {'cmp': [pos[i], '>=', 1]}))
        closed = val(f'{L}_gate{i}_closed', {'cmp': [pos[i], '<=', 0]})
        ok = val(f'{L}_gate{i}_ok', {'not': switch[i]})
        shut.append(val(f'{L}_shut{i}', {'and': [closed, ok]}))
        down.append(val(f'{L}_gate{i}_down', {'not': cmd[i]}))
    stop_off = val(f'{L}_estop_off', {'not': estop})
    drive_ok = val(f'{L}_drive_ok', {'not': fault})
    ready = val(f'{L}_ready', {'and': [main, stop_off, drive_ok]})
    load_ok = val(f'{L}_load_ok', {'cmp': [f'{L}_load', '<=', rated_kg]})
    over = val(f'{L}_over', {'cmp': [f'{L}_load', '>', rated_kg]})
    run = val(f'{L}_run', {'and': shut + down + [ready, load_ok]})
    tz = val(f'{L}_target_z', {'select': target, 'cases': list(zs)})
    u = val(f'{L}_u', {'select': run, 'cases': [z, tz]})
    u_ge = val(f'{L}_u_ge', {'cmp': [u, '>=', z]})
    u_le = val(f'{L}_u_le', {'cmp': [u, '<=', z]})
    at = []
    for i in range(n):
        lo = val(f'{L}_lv{i}_lo', {'cmp': [z, '>=', zs[i]]})
        hi = val(f'{L}_lv{i}_hi', {'cmp': [z, '<=', zs[i]]})
        at.append(val(f'{L}_at{i}', {'and': [lo, hi, u_ge, u_le]}))
    t_ge = val(f'{L}_tz_ge', {'cmp': [z, '>=', tz]})
    t_le = val(f'{L}_tz_le', {'cmp': [z, '<=', tz]})
    idle = val(f'{L}_idle', {'and': [t_ge, t_le] + shut})
    needs = [[ready, 'The lift is not ready: stopped, faulted or switched off'],
             [idle, 'The cab is travelling or a gate is not shut'],
             [load_ok, 'The cab is over its rated load']]
    ops = [{'kks': codes['calls'][i], 'do': 'start', 'set': {target: i}, 'needs': needs, 'where': ['local']}
           for i in range(n)]
    ops += [{'kks': codes['panel'], 'do': 'set', 'input': target, 'range': [0, n - 1], 'needs': needs,
             'where': ['local']},
            {'kks': codes['panel'], 'do': 'stop', 'set': {estop: 1}, 'where': ['local']},
            {'kks': codes['panel'], 'do': 'start', 'set': {estop: 0}, 'where': ['local']}]
    for i in range(n):
        ops += [{'kks': codes['gates'][i], 'do': 'open', 'set': {cmd[i]: 1},
                 'needs': [[at[i], 'The cab is not standing at this landing']], 'where': ['local']},
                {'kks': codes['gates'][i], 'do': 'close', 'set': {cmd[i]: 0}, 'where': ['local']}]
    alarms = [{'id': f'{L}_overload', 'kks': codes['load'], 'text': 'Lift overloaded', 'when': over, 'priority': 3,
               'where': codes['panel']}]
    faults = [{'id': f'{L}_drive', 'set': {fault: 1}, 'repair': {fault: 0}, 'text': 'Lift drive fault',
               'kks': codes['drive']},
              {'id': f'{L}_gate_switch', 'set': {switch[0]: 1}, 'repair': {switch[0]: 0},
               'text': 'A landing gate switch reads not shut', 'kks': codes['gates'][0]}]
    lift = {'id': lid, 'kks': kks, 'rated_kg': rated_kg, 'person_kg': person_kg, 'ready': ready, 'idle': idle,
            'panel': codes['panel'], 'target': target,
            'landings': [{'z': zs[i], 'at': at[i], 'open': opened[i], 'shut': shut[i], 'call': codes['calls'][i],
                          'gate': codes['gates'][i]} for i in range(n)]}
    return {'values': v, 'ops': ops, 'alarms': alarms, 'faults': faults, 'lift': lift, 'codes': codes}
