"""The first train's staff (docs/PLANT3D.md §16–§17, docs/plant3d/STAFF.md; milestone S1: the operators' crews and the
technicians who take their permits): staff.json, the plant's clock and the scenario `shift_cold`, for
make_content.py.

Places and ways come from the layout (§16.2): the walking network's points are set along the plant's walkways by
hand (POINTS, EDGES); the desks, seats and doors of the control building likewise (ANCHORS); every other place is a
work place in front of a piece of equipment, where the app's walking directions end a route to it. Where each work
place stands and how long each walk is are measured on the built plant's navigation mesh by
apps/plant3d/tests/staff_layout.gd and kept in staff_layout.json beside this file; the build's test
(apps/plant3d/tests/test_staff_ways.gd) checks every way against the mesh again. After the layout changes:

    python3 tools/plant3d/train_staff.py --requests /tmp/req.json
    godot --headless --path apps/plant3d --script res://tests/staff_layout.gd -- --in=/tmp/req.json \\
        --out=$PWD/tools/plant3d/staff_layout.json
    python3 tools/plant3d/make_content.py --write

Nothing here is a real plant's organisation: roles as most combined-cycle plants have them, people by call sign."""
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LAYOUT = os.path.join(HERE, 'staff_layout.json')

CLOCK = {'day_scale': 6, 'start': {'day': 1, 'time': '06:00'},
         'week': ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']}
SPEEDS = {'walk': 1.3, 'stair': 0.5, 'ladder': 0.3}
K = 8                       # nearest points measured for each place's way into the network
STAIR_RISE = 2.0            # a way that climbs and comes down more than this (m) is walked at stair speed

# The walking network (plant coordinates: x east, y north, z up), along the walkways the frames walk and the walking
# test use: the control building, the road round the turbine hall, the corridor between the turbine hall and the
# gas turbine hall, the auxiliaries, the CW pump house and the cooling tower's west side.
POINTS = {
    'p_cr': (-20, 0, 0), 'p_cr_e': (-13, 0, 0), 'p_cr_n': (-20, 9, 0), 'p_cr_s': (-20, -9, 0),
    'p_door': (-7, 0, 0), 'p_w20': (-5, 20, 0), 'p_w36': (-5, 36, 0), 'p_gate': (-5, -12, 0),
    'p_st_w': (3, 20, 0), 'p_st_20': (20, 20, 0), 'p_st_50': (50, 21, 0), 'p_st_e': (74, 5, 0),
    'p_st_s': (30, -20, 0), 'p_st_pit': (57, 14, 0),
    'p_e5': (87, 5, 0), 'p_e12': (87, 13, 0), 'p_e36': (87, 36, 0),
    'p_c40': (40, 36, 0), 'p_c113': (113, 40, 0), 'p_c140': (140, 36, 0), 'p_c165': (165, 36, 0),
    'p_gt_s': (40, 47, 0), 'p_gt_in': (40, 54, 0), 'p_gt_w': (12, 56, 0), 'p_gt_e': (68, 56, 0),
    'p_gt_nw': (30, 76, 0), 'p_gt_n': (24, 81, 0),
    'p_b1': (106, 12, 0), 'p_b2': (106, 0, 0), 'p_b3': (120, 0, 0), 'p_b4': (113, -11, 0), 'p_b5': (130, 0, 0),
    'p_cw_x': (137, 11, 0), 'p_cw_o': (152, 11, 0), 'p_cw_i': (152, 2, 0),
    'p_ct_n': (167, 12, 0), 'p_ct_s': (167, -18, 0),
    # up the stairs: the turbine hall's operating floor, its condenser pit, HRSG 1's drum platform, the cooling
    # tower's fan deck
    'p_st_12': (12, 16, 12), 'p_st_12e': (60, 12, 12), 'p_st_pit6': (57, 2.5, -6), 'p_h_foot': (93.5, 44.5, 0), 'p_h_30': (101.4, 52.5, 30),
    'p_ct_14': (176, -12, 14),
}
EDGES = [
    ('p_cr', 'p_cr_e'), ('p_cr', 'p_cr_n'), ('p_cr', 'p_cr_s'), ('p_cr_e', 'p_door'), ('p_door', 'p_w20'),
    ('p_door', 'p_gate'), ('p_w20', 'p_w36'), ('p_w20', 'p_st_w'), ('p_st_w', 'p_st_20'), ('p_st_20', 'p_st_50'),
    ('p_st_20', 'p_st_s'), ('p_st_50', 'p_st_pit'), ('p_st_50', 'p_st_e'), ('p_st_e', 'p_e5'), ('p_e5', 'p_e12'),
    ('p_e12', 'p_e36'), ('p_e12', 'p_b1'), ('p_w36', 'p_c40'), ('p_c40', 'p_e36'), ('p_c40', 'p_gt_s'),
    ('p_gt_s', 'p_gt_in'), ('p_gt_in', 'p_gt_w'), ('p_gt_in', 'p_gt_e'), ('p_gt_w', 'p_gt_nw'),
    ('p_gt_nw', 'p_gt_n'), ('p_e36', 'p_c113'), ('p_c113', 'p_c140'), ('p_c140', 'p_c165'),
    ('p_b1', 'p_b2'), ('p_b2', 'p_b3'), ('p_b3', 'p_b4'), ('p_b3', 'p_b5'), ('p_b5', 'p_cw_x'),
    ('p_cw_x', 'p_cw_o'), ('p_cw_o', 'p_cw_i'), ('p_cw_o', 'p_c140'), ('p_c165', 'p_ct_n'), ('p_ct_n', 'p_ct_s'),
    ('p_st_w', 'p_st_12'), ('p_st_12', 'p_st_12e'), ('p_st_pit', 'p_st_pit6'), ('p_e36', 'p_h_foot'), ('p_h_foot', 'p_c113'),
    ('p_h_foot', 'p_h_30'), ('p_ct_s', 'p_ct_14'),
]
# The control building's rooms (its ground floor: the control room, the field office, the maintenance workshop)
# and the gate where people come on site (until the camp and its buses, milestone S4).
ANCHORS = {
    'cr_door': dict(at=(-11.5, 0, 0), kind='door', room='control_room'),
    'cr_desk_a': dict(at=(-26.6, -2.2, 0), kind='desk', room='control_room', yaw=90, pose='sit'),
    'cr_desk_b': dict(at=(-26.6, 2.2, 0), kind='desk', room='control_room', yaw=90, pose='sit'),
    'cr_sup': dict(at=(-30, 6, 0), kind='table', room='control_room', yaw=90, pose='sit'),
    'cr_seat_1': dict(at=(-30, -6, 0), kind='seat', room='control_room', yaw=90, pose='sit'),
    'cr_seat_2': dict(at=(-28, -8, 0), kind='seat', room='control_room', yaw=90, pose='sit'),
    'fo_door': dict(at=(-15, 8, 0), kind='door', room='field_office'),
    'fo_table': dict(at=(-17, 12, 0), kind='table', room='field_office', yaw=0, pose='sit'),
    'fo_seat_1': dict(at=(-20, 12, 0), kind='seat', room='field_office', yaw=0, pose='sit'),
    'fo_seat_2': dict(at=(-23, 12, 0), kind='seat', room='field_office', yaw=0, pose='sit'),
    'fo_seat_3': dict(at=(-26, 12, 0), kind='seat', room='field_office', yaw=0, pose='sit'),
    'fo_seat_4': dict(at=(-29, 12, 0), kind='seat', room='field_office', yaw=0, pose='sit'),
    'ws_door': dict(at=(-15, -8, 0), kind='door', room='workshop'),
    'ws_bench_1': dict(at=(-18, -12, 0), kind='table', room='workshop', yaw=180),
    'ws_bench_2': dict(at=(-22, -12, 0), kind='table', room='workshop', yaw=180),
    'ws_bench_3': dict(at=(-26, -12, 0), kind='table', room='workshop', yaw=180),
    'ws_bench_4': dict(at=(-30, -12, 0), kind='table', room='workshop', yaw=180),
    'gate': dict(at=(-5, -14, 0), kind='door'),
}

# Rounds (STAFF.md §3): each field operator's area, its readings: (code, expect [lo, hi], tol). The ranges hold for
# the plant at rest and running normally (checked by tests/test_plant3d_staff_content.py on the cold start's base
# load), so a reading outside one is a finding.
ROUNDS = {
    'round_gt': ('Field round: gas turbine 1 and HRSG 1', [
        ('10MBV10CP001', [0, 3.0], 0.1), ('10MBV10CT001', [15, 60], 1), ('10MBD10CY001', [0, 7.1], 0.2),
        ('10MKA10CT001', [15, 100], 1), ('10MBR10CT006', [0, 650], 5), ('10LAC10CF001', [0, 1.1], 0.02),
        ('10LAC10CF002', [0, 1.1], 0.02)]),
    'round_st': ('Field round: steam turbine and auxiliaries', [
        ('30MAV10CP001', [0, 3.0], 0.1), ('30MAV10CT001', [15, 60], 1), ('30MAG10CL001', [-50, 400], 5),
        ('00QFB10CP001', [0, 8.5], 0.1), ('00PGB10CT001', [15, 45], 1), ('00QHA10CP001', [0, 14], 0.2)]),
    'round_cw': ('Field round: circulating water and cooling tower', [
        ('30PAC10CP501', [0, 3.2], 0.1), ('30PAC10CP502', [0, 3.2], 0.1), ('30PAC10CP503', [0, 3.2], 0.1),
        ('30PAD10CL001', [-0.5, 0.5], 0.02)]),
}
FIELD = {'round_gt': 'field_gt', 'round_st': 'field_st', 'round_cw': 'field_cw'}

# Faults of the scenario that make a corrective work (P1's works): the supervisor asks for its permit.
FAULT_WORK = {'cw_a_motor': 'wo_cw_a_motor', 'cw_b_motor': 'wo_cw_b_motor', 'cw_c_motor': 'wo_cw_c_motor',
              'ccw_a_motor': 'wo_ccw_a_motor', 'ccw_b_motor': 'wo_ccw_b_motor', 'ct_fan3_vib': 'wo_ct_fan3'}
# who locks each kind of point; who takes a work of each discipline
LOCKER = {'electrical': 'elec_ap', 'mechanical': 'field_op', 'process': 'field_op', 'instrument': 'ic_tech'}
TECH = {'mech': 'mech_tech', 'elec': 'elec_tech', 'inst': 'ic_tech'}
# what a point's locker does first to make it safe (a local op), when the point's safe value needs it
MAKE_SAFE = {'mechanical': 'close'}

# The control room's instructions to a field operator (the radio panel's requests): local ops on the plant.
INSTRUCTIONS = [
    ('ccw_cooler_in', 'Put the closed cooling water cooler in service', [('00PGB10AC001', 'open')],
     'ccw_cooler_done'),
    ('ccw_cooler_out', 'Take the closed cooling water cooler out of service', [('00PGB10AC001', 'close')],
     'ccw_cooler_done'),
    ('cw_vents_open', 'Open the condenser water box vents', [('30PAB10AA401', 'open'), ('30PAB10AA402', 'open'),
                                                             ('30PAB10AA403', 'open'), ('30PAB10AA404', 'open')],
     'vents_done'),
    ('cw_vents_close', 'Close the condenser water box vents', [('30PAB10AA401', 'close'), ('30PAB10AA402', 'close'),
                                                               ('30PAB10AA403', 'close'), ('30PAB10AA404', 'close')],
     'vents_done'),
]

MESSAGES = {
    'handover': 'Handover taken: running equipment, open permits and alarms noted',
    'round_done': 'Round done: readings in the log',
    'finding': 'Round finding: a reading out of its range, see the log',
    'check_alarm': 'Please check the alarm locally and report',
    'alarm_checked': 'Alarm checked locally: reported in the log',
    'trip': 'Trip: all stations stand by',
    'isolated': 'Isolation points locked and tagged',
    'deisolated': 'Isolation points removed',
    'permit_issued': 'Your permit is issued: you may accept it',
    'job_done': 'Job done: permit handed back',
    'permit_closed': 'Permit closed: equipment back in service',
    'instruction': 'Instruction for you over the radio',
    'ccw_cooler_done': 'CCW cooler valves set as asked',
    'vents_done': 'Water box vents set as asked',
    'request': 'Permit requested: please approve',
    'all_well': 'All stations: all well',
}


def round_codes():
    return [c for _, (t, rs) in ROUNDS.items() for c, _, _ in rs]


def model_parts(models):
    """(alarms, isolations, works, ops) of the joined model files."""
    al, isos, works, ops = [], [], [], []
    for m in models:
        f = m.file() if hasattr(m, 'file') else m
        al += f.get('alarms', [])
        isos += f.get('isolations', [])
        works += f.get('works', [])
        ops += f.get('ops', [])
    return al, isos, works, ops


def work_codes(models):
    """Every code a person works at: the rounds' readings, the alarms' local checks (priority 1 and 2: their
    `where`), the works and their isolation points, the instructions' valves."""
    al, isos, works, _ = model_parts(models)
    out = round_codes()
    out += [a['where'] for a in al if a['priority'] <= 2]
    out += [w['kks'] for w in works]
    out += [pt['kks'] for x in isos for pt in x['points']]
    out += [c for _, _, ops, _ in INSTRUCTIONS for c, _ in ops]
    seen, res = set(), []
    for c in out:
        if c not in seen:
            seen.add(c)
            res.append(c)
    return res


def requests(models):
    places = {k: list(v) for k, v in POINTS.items()}
    places.update({k: list(a['at']) for k, a in ANCHORS.items()})
    return {'codes': work_codes(models), 'places': places, 'points': list(POINTS), 'edges': [list(e) for e in EDGES],
            'k': K}


def _metres(length, a, b):
    """A way's length: the mesh's, up 2 % and to the next 5 cm (never under the straight line)."""
    m = math.ceil(length * 1.02 * 20) / 20
    return max(m, math.ceil(math.dist(a, b) * 20 + 1e-9) / 20)


def network(models, layout):
    """(places, ways, next) from the layout measured on the mesh."""
    from ref.plant3d_staff import way_steps, next_table
    places, ways = [], []
    at = {}
    for pid, p in POINTS.items():
        places.append({'id': pid, 'at': list(p), 'kind': 'point'})
        at[pid] = p
    for pid, a in ANCHORS.items():
        pl = {'id': pid, 'at': list(a['at']), 'kind': a['kind']}
        for k in ('room', 'yaw', 'pose'):
            if k in a:
                pl[k] = a[k]
        places.append(pl)
        at[pid] = a['at']
    missing = []
    for code in work_codes(models):
        if code not in layout['stand']:
            missing.append(code)
            continue
        pid = 'w_' + code.lower()
        places.append({'id': pid, 'at': layout['stand'][code], 'kind': 'work', 'kks': code})
        at[pid] = tuple(layout['stand'][code])
    if missing:
        print(f'train_staff: no stand point measured for {missing} (run staff_layout.gd)', file=sys.stderr)
    for a, b in EDGES:
        m, rise, reached = layout['edges'][f'{a}|{b}']
        if not reached:
            raise SystemExit(f'train_staff: the way {a}–{b} is not walkable on the mesh')
        ways.append([a, b, _metres(m, at[a], at[b]), 'stair' if rise > STAIR_RISE else 'walk'])
    for p in places:
        if p['kind'] == 'point':
            continue
        key = ('kks:' + p['kks']) if p['kind'] == 'work' else p['id']
        stubs = layout['stubs'].get(key, [])
        if not stubs:
            raise SystemExit(f'train_staff: {p["id"]} reaches no point on the mesh')
        q, m, rise = min(stubs, key=lambda s: (s[1], s[0]))
        ways.append([p['id'], q, _metres(m, at[p['id']], at[q]), 'stair' if rise > STAIR_RISE else 'walk'])
    pts = list(POINTS)
    adj = [[] for _ in pts]
    for a, b, metres, mode in ways:
        if a in POINTS and b in POINTS:
            st = way_steps(metres, SPEEDS[mode])
            adj[pts.index(a)].append((pts.index(b), st))
            adj[pts.index(b)].append((pts.index(a), st))
    return places, ways, next_table(len(pts), adj)


def roles():
    def role(rid, title, disc, auth, routine, play, look):
        return {'id': rid, 'title': title, 'discipline': disc, 'look': look, 'authority': auth,
                'ppe': ['helmet', 'boots', 'glasses', 'gloves', 'ear'] if rid != 'ccr_op' else ['helmet', 'boots'],
                'routine': routine, 'play': play}
    return [
        role('shift_sup', 'Shift supervisor', 'ops', ['operate_screen', 'request', 'approve', 'issue', 'lock_process',
                                                       'remove_lock'],
             'sup_shift', True, 'coverall_ops_white'),
        dict(role('ccr_op', 'Control room operator', 'ops', ['operate_screen', 'request', 'lock_process'],
                  'ccr_shift', True, 'coverall_ops'), requests=['ask_' + i[0] for i in INSTRUCTIONS]),
        role('field_op', 'Field operator', 'ops', ['operate_local', 'request', 'lock_mechanical', 'lock_process'],
             'field_st', True, 'coverall_ops'),
        role('elec_ap', 'Electrical authorised person', 'ops', ['operate_local', 'request', 'lock_electrical'],
             'elec_shift', True, 'coverall_ops'),
        # the technicians take the operators' permits (S1); their own jobs and play come with S2
        role('mech_tech', 'Mechanical technician', 'mech', ['accept'], 'tech_days', False, 'coverall_mech'),
        role('elec_tech', 'Electrical technician', 'elec', ['accept', 'lock_electrical'], 'tech_days', False,
             'coverall_elec'),
        role('ic_tech', 'I&C technician', 'inst', ['operate_local', 'accept', 'lock_instrument'], 'tech_days', False,
             'coverall_inst'),
    ]


def rosters():
    return [{'id': 'shift', 'kind': 'rotation', 'cycle': ['D', 'D', 'N', 'N', 'O', 'O', 'O', 'O'],
             'crews': {'a': 0, 'b': 2, 'c': 4, 'd': 6},
             'hours': {'D': ['06:00', '18:00'], 'N': ['18:00', '06:00']}},
            {'id': 'day', 'kind': 'days', 'days': ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
             'hours': ['07:00', '16:00']}]


def people():
    out = []
    for crew in 'abcd':
        C = crew.upper()
        out.append({'id': f'{crew}_sup', 'role': 'shift_sup', 'roster': 'shift', 'crew': crew,
                    'call': f'Supervisor, crew {C}'})
        for i in (1, 2):
            out.append({'id': f'{crew}_ccr{i}', 'role': 'ccr_op', 'roster': 'shift', 'crew': crew,
                        'call': f'Control {i}, crew {C}'})
        for rt, name in (('field_gt', 'GT'), ('field_st', 'ST'), ('field_cw', 'CW')):
            out.append({'id': f'{crew}_fo_{name.lower()}', 'role': 'field_op', 'roster': 'shift', 'crew': crew,
                        'call': f'Field {name}, crew {C}', 'routine': rt})
        out.append({'id': f'{crew}_eap', 'role': 'elec_ap', 'roster': 'shift', 'crew': crew,
                    'call': f'Electrical, crew {C}'})
    for i in (1, 2):
        out.append({'id': f'mech{i}', 'role': 'mech_tech', 'roster': 'day', 'call': f'Mechanical {i}'})
    out.append({'id': 'elec1', 'role': 'elec_tech', 'roster': 'day', 'call': 'Electrical technician'})
    out.append({'id': 'ic1', 'role': 'ic_tech', 'roster': 'day', 'call': 'I&C technician'})
    return out


def slot(at, task, **kw):
    return dict({'at': at, 'task': task}, **kw)


def routines():
    field = lambda rid, rnd: {'id': rid, 'idle': 'idle_field', 'slots': [  # noqa: E731
        slot('start-0:15', 'handover_take_f'), slot('start+1:00', rnd, every='2:00', until='end-1:00'),
        slot('end-0:15', 'handover_give_f')]}
    return [
        {'id': 'sup_shift', 'idle': 'idle_sup', 'slots': [slot('start-0:15', 'handover_take_sup'),
                                                          slot('start+0:30', 'sup_walk'),
                                                          slot('end-0:15', 'handover_give_sup')]},
        {'id': 'ccr_shift', 'idle': 'idle_ccr', 'slots': [slot('start-0:15', 'handover_take'),
                                                          slot('end-0:15', 'handover_give')]},
        field('field_gt', 'round_gt'), field('field_st', 'round_st'), field('field_cw', 'round_cw'),
        {'id': 'elec_shift', 'idle': 'idle_elec', 'slots': [slot('start-0:15', 'handover_take_f'),
                                                            slot('end-0:15', 'handover_give_f')]},
        {'id': 'tech_days', 'idle': 'idle_tech', 'slots': [slot('07:00', 'toolbox')]},
    ]


def tasks(models):
    al, isos, works, ops = model_parts(models)
    iso = {x['id']: x for x in isos}
    T = []

    def task(tid, title, steps, **kw):
        T.append(dict({'id': tid, 'title': title, 'steps': steps}, **kw))
    desk = {'go': {'kind': 'desk', 'room': 'control_room'}}
    task('idle_ccr', 'At the control desk: watching the screens', [desk, {'work': 30, 'anim': 'type'}])
    task('idle_sup', 'At the supervisor\'s table: the shift log', [{'go': 'cr_sup'}, {'work': 30, 'anim': 'write'}])
    task('idle_field', 'In the field office', [{'go': {'kind': 'seat', 'room': 'field_office'}}, {'work': 20}])
    task('idle_elec', 'In the field office: switching orders', [{'go': 'fo_table'}, {'work': 30, 'anim': 'write'}])
    task('idle_tech', 'In the workshop', [{'go': {'kind': 'table', 'room': 'workshop'}}, {'work': 30}])
    meet = lambda room, role, minutes=15: {'meet': {'room': room, 'with': [role], 'minutes': minutes}}  # noqa: E731
    task('handover_take', 'Take the control room handover', [meet('control_room', 'ccr_op'),
                                                             {'say': 'handover', 'to': 'shift_sup'}])
    task('handover_give', 'Give the control room handover', [meet('control_room', 'ccr_op')])
    task('handover_take_sup', 'Take the shift handover', [meet('control_room', 'shift_sup')])
    task('handover_give_sup', 'Give the shift handover', [meet('control_room', 'shift_sup')])
    task('handover_take_f', 'Take the field handover', [meet('field_office', 'field_op')])
    task('handover_give_f', 'Give the field handover', [meet('field_office', 'field_op')])
    task('sup_walk', 'The supervisor\'s look round the control room', [{'go': 'cr_sup'}, {'work': 10},
                                                                       {'say': 'all_well', 'to': 'channel'}])
    task('toolbox', 'Toolbox talk in the workshop', [meet('workshop', 'mech_tech', 10)])
    for rid, (title, reads) in ROUNDS.items():
        steps = []
        for code, ex, tol in reads:
            steps += [{'go': {'kks': code}}, {'read': code, 'expect': ex, 'tol': tol}, {'work': [1, 2],
                                                                                      'anim': 'inspect'}]
        steps += [{'say': 'round_done', 'to': 'ccr_op'}, {'choose': [[3, 'back_office'], [1, 'tea_break']]}]
        task(rid, title, steps)
    task('back_office', 'Back to the field office', [{'go': {'kind': 'seat', 'room': 'field_office'}},
                                                     {'work': [5, 10]}], priority=4)
    task('tea_break', 'A tea in the field office', [{'go': {'kind': 'seat', 'room': 'field_office'}},
                                                    {'work': [10, 20], 'anim': 'eat'}], priority=4)
    # alarms: the control room acknowledges and sends a field operator to look (STAFF.md §3)
    task('answer_alarm', 'Answer the alarm', [desk, {'ack': '$'}, {'call': {'role': 'field_op', 'task': 'check_alarm'}},
                                              {'say': 'check_alarm', 'to': 'field_op'}], priority=1,
         interruptible=False)
    task('check_alarm', 'Check the alarm locally', [{'go': {'kks': '$'}}, {'work': [2, 4], 'anim': 'inspect'},
                                                    {'say': 'alarm_checked', 'to': 'ccr_op'}], priority=1)
    task('trip_call', 'A trip: to the control room', [{'go': 'cr_sup'}, {'say': 'trip', 'to': 'channel'},
                                                      {'work': 10}], priority=1)
    # instructions over the radio
    for tid, title, steps_ops, msg in INSTRUCTIONS:
        steps = []
        for code, do in steps_ops:
            steps += [{'go': {'kks': code}}, {'op': {'kks': code, 'do': do, 'where': 'local'}}]
        steps.append({'say': msg, 'to': 'ccr_op'})
        task(tid, title, steps, priority=2)
        # the control room's side: the call itself (what makes it one of the radio panel's requests, §17.8)
        task('ask_' + tid, f'Ask a field operator: {title[0].lower() + title[1:]}', [
            desk, {'call': {'role': 'field_op', 'task': tid}}, {'work': 1}], priority=2)
    # permits (§15, STAFF.md §3): asked for by the supervisor when a fault makes a work, approved and issued by them,
    # isolated by the people whose kind of point it is, accepted, worked and handed back by the technician of the
    # work's discipline, de-isolated, closed
    task('request_permit', 'Ask for a permit for the fault\'s work', [
        {'go': 'cr_sup'}, {'permit': {'work': '$', 'action': 'request'}}], priority=2)
    task('approve_permit', 'Approve the permit', [{'go': 'cr_sup'}, {'permit': {'work': '$', 'action': 'approve'}}],
         priority=2)
    task('issue_permit', 'Issue the permit', [{'go': 'cr_sup'}, {'permit': {'work': '$', 'action': 'issue'}},
                                              {'say': 'permit_issued', 'to': 'channel'}], priority=2)
    task('close_permit', 'Close the permit', [{'go': 'cr_sup'}, {'permit': {'work': '$', 'action': 'close'}},
                                              {'say': 'permit_closed', 'to': 'channel'}], priority=2)
    reacts = []
    for w in works:
        wid = w['id']
        x = iso.get(w.get('isolation'))
        if x is None:
            continue
        lock_s, unlock_s = [], []
        by_role = {}
        for i, pt in enumerate(x['points']):
            by_role.setdefault(LOCKER[pt['kind']], []).append((i, pt))
        for role, pts in by_role.items():
            steps, usteps = [], []
            for i, pt in pts:
                steps.append({'go': {'kks': pt['kks']}})
                if pt['kind'] in MAKE_SAFE:
                    steps.append({'op': {'kks': pt['kks'], 'do': MAKE_SAFE[pt['kind']], 'where': 'local'}})
                steps.append({'lock': {'work': '$', 'point': i}})
                usteps += [{'go': {'kks': pt['kks']}}, {'unlock': {'work': '$', 'point': i}}]
            steps.append({'say': 'isolated', 'to': 'shift_sup'})
            usteps.append({'say': 'deisolated', 'to': 'shift_sup'})
            lt, ut = f'lock_{wid[3:]}_{role}', f'unlock_{wid[3:]}_{role}'
            task(lt, f'Isolate for "{w["title"]}"', steps, priority=2)
            task(ut, f'Remove the isolation of "{w["title"]}"', usteps, priority=2)
            lock_s.append({'call': {'role': role, 'task': lt}})
            unlock_s.append({'call': {'role': role, 'task': ut}})
        task(f'isolate_{wid[3:]}', f'Have "{w["title"]}" isolated', lock_s, priority=2)
        task(f'deisolate_{wid[3:]}', f'Have the isolation of "{w["title"]}" removed', unlock_s, priority=2)
        job = f'job_{wid[3:]}'
        task(job, w['title'], [
            {'go': {'kks': w['kks']}}, {'permit': {'work': '$', 'action': 'accept'}},
            {'work': [30, 60], 'anim': 'wrench'}, {'permit': {'work': '$', 'action': 'done'}},
            {'permit': {'work': '$', 'action': 'return'}}, {'say': 'job_done', 'to': 'shift_sup'}], work=wid)
        reacts += [{'on': {'permit': 'approved'}, 'roles': ['shift_sup'], 'task': f'isolate_{wid[3:]}', 'work': wid},
                   {'on': {'permit': 'issued'}, 'roles': [TECH[w['discipline']]], 'task': job, 'work': wid},
                   {'on': {'permit': 'returned'}, 'roles': ['shift_sup'], 'task': f'deisolate_{wid[3:]}',
                    'work': wid}]
    return T, reacts


def reactions(model_reacts):
    out = [{'on': {'alarm': 2}, 'roles': ['ccr_op'], 'task': 'answer_alarm'},
           {'on': {'trip': '*'}, 'roles': ['shift_sup'], 'task': 'trip_call'},
           {'on': {'permit': 'requested'}, 'roles': ['shift_sup'], 'task': 'approve_permit'},
           {'on': {'permit': 'isolated'}, 'roles': ['shift_sup'], 'task': 'issue_permit'},
           {'on': {'permit': 'deisolated'}, 'roles': ['shift_sup'], 'task': 'close_permit'}]
    out += [{'on': {'fault': f}, 'roles': ['shift_sup'], 'task': 'request_permit', 'work': w}
            for f, w in FAULT_WORK.items()]
    return out + model_reacts


def staff(models, layout):
    places, ways, nxt = network(models, layout)
    T, model_reacts = tasks(models)
    return {'format': 'walkdown-plant-staff', 'version': 1, 'origin': 'cr_desk_a', 'gate': 'gate', 'speeds': SPEEDS,
            'places': places, 'ways': ways, 'next': nxt, 'roles': roles(), 'rosters': rosters(), 'people': people(),
            'routines': routines(), 'tasks': T, 'reactions': reactions(model_reacts), 'messages': MESSAGES}


def scenario(cold):
    """`shift_cold`: the plant cold (as cold_iron), the operators' day shift on duty from its handover (05:30)."""
    s = dict(cold)
    s['version'] = 2
    s['id'] = 'shift_cold'
    s['title'] = 'Day shift, the plant cold: the operators\' crews at work (choose a role)'
    s['start'] = {'day': 1, 'time': '05:30'}
    s['staff'] = {'seed': 1}
    return s


def load_layout():
    with open(LAYOUT, encoding='utf-8') as f:
        return json.load(f)


def works_tasks(models):
    """{work id: its job task} for the model's works (§15.2: a plant with staff names each work's task)."""
    return {w['id']: f'job_{w["id"][3:]}' for w in model_parts(models)[2]}


if __name__ == '__main__':
    sys.path.insert(0, HERE)
    sys.path.insert(0, ROOT)
    import train_model, wtp_model  # noqa: E402
    models = train_model.models() + wtp_model.models()
    if '--requests' in sys.argv:
        path = sys.argv[sys.argv.index('--requests') + 1]
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(requests(models), f, indent=1)
        print(f'wrote {path}: {len(requests(models)["codes"])} codes')
