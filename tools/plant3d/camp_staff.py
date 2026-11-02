"""The full day's staff (docs/PLANT3D.md §21, milestone S4; docs/plant3d/STAFF.md §1, §2, §5): the camp, the site's
walkways and offices, the bus, the roles the first train's staff lacked (guards, managers and engineers, the driver,
the storekeeper, the camp's staff), everyone's home and off-duty routine, joined to the train's by train_staff.py.

Coordinates are the plot plan's (SITE.md §1; x east, y north, z up): the camp from x −480 to −260, the road to the plant
gate at y 21, the admin area from x −140. Every place west of the plant's fence (x −140) is off site (§21.1). Ways are
measured on the built plant's navigation mesh like the train's (apps/plant3d/tests/staff_layout.gd); the bus's drive
ways are the roads' lengths (ROADS).

Nothing here is a real plant's: roles as most combined-cycle plants have them, people by call sign."""

FENCE_X = -140              # west of it: off site (the camp and the road to it)

# The walking network: the walkway from the control building north to the gate road, along it to the plant gate, the
# road to the camp (its walkway at y 21), the camp's main walkway, the blocks' walkway (x −411) and paths to the
# buildings' doors; the admin area from the gate road north.
POINTS = {
    'p_s40': (-40, 21.5, 0), 'p_s90': (-90, 22, 0), 'p_gate_in': (-112, 22, 0), 'p_rw_e': (-146, 21.5, 0),
    'p_rw_w': (-255, 21.5, 0), 'p_cg': (-276, 21, 0), 'p_c300': (-300, 21, 0), 'p_c330': (-330, 21, 0),
    'p_c352': (-352, 21, 0), 'p_c370': (-370, 21, 0), 'p_c411': (-411, 21, 0),
    'p_bw35': (-411, 35, 0), 'p_bw55': (-411, 55, 0), 'p_bw75': (-411, 75, 0), 'p_bw95': (-411, 95, 0),
    'p_b1_c': (-396, 35, 0),                                    # block 1's corridor (its interior, §18.5)
    'p_mess': (-340, 7, 0), 'p_mess_in': (-340, 1, 0), 'p_kitchen': (-326, -11, 0),
    'p_gym': (-352, 23.5, 0), 'p_gym_in': (-352, 28.5, 0), 'p_rec': (-330, 23.5, 0), 'p_rec_in': (-330, 30, 0),
    'p_pray': (-308, 23.5, 0), 'p_pray_in': (-308, 31, 0), 'p_ldy': (-361, 50, 0), 'p_ldy_in': (-355, 50, 0),
    'p_ldy_n': (-361, 40, 0), 'p_off': (-284, 23.5, 0), 'p_cpark': (-276, -8, 0),
    'p_adm_s': (-94, 30, 0), 'p_adm_ws': (-97, 57, 0), 'p_adm_n': (-100, 92, 0), 'p_adm_door': (-108, 95, 0),
    'p_adm_lobby': (-108, 101.5, 0), 'p_adm_meet': (-101, 102, 0), 'p_ws_in': (-110, 57, 0),
    'p_store': (-84, 52, 0),
}
EDGES = [
    ('p_w20', 'p_s40'), ('p_s40', 'p_s90'), ('p_s90', 'p_gate_in'), ('p_gate_in', 'p_rw_e'), ('p_rw_e', 'p_rw_w'),
    ('p_rw_w', 'p_cg'), ('p_cg', 'p_c300'), ('p_c300', 'p_c330'), ('p_c330', 'p_c352'), ('p_c352', 'p_c370'),
    ('p_c370', 'p_c411'), ('p_c411', 'p_bw35'), ('p_bw35', 'p_bw55'), ('p_bw55', 'p_bw75'), ('p_bw75', 'p_bw95'),
    ('p_bw35', 'p_b1_c'), ('p_c330', 'p_mess'), ('p_mess', 'p_mess_in'), ('p_mess_in', 'p_kitchen'),
    ('p_c352', 'p_gym'), ('p_gym', 'p_gym_in'), ('p_c330', 'p_rec'), ('p_rec', 'p_rec_in'), ('p_c300', 'p_pray'),
    ('p_pray', 'p_pray_in'), ('p_c370', 'p_ldy_n'), ('p_ldy_n', 'p_ldy'), ('p_ldy', 'p_ldy_in'), ('p_cg', 'p_off'),
    ('p_cg', 'p_cpark'), ('p_s90', 'p_adm_s'), ('p_adm_s', 'p_adm_ws'), ('p_adm_ws', 'p_adm_n'),
    ('p_adm_n', 'p_adm_door'), ('p_adm_door', 'p_adm_lobby'), ('p_adm_lobby', 'p_adm_meet'), ('p_adm_ws', 'p_ws_in'),
    ('p_adm_ws', 'p_store'),
]

# the blocks (SITE.md §3): block k's door on the blocks' walkway (odd blocks' west doors at x −404, even blocks' east
# doors at x −418), at y 35, 55, 75, 95
BLOCK_DOOR = {k: (-404.0 if k % 2 else -418.0, 35.0 + 20 * ((k - 1) // 2)) for k in range(1, 9)}
OPEN_ROOMS = {'room_101': (-401.4, 31.4), 'room_107': (-401.4, 38.6)}   # block 1's two rooms drawn open: their beds


def _beds():
    out = {}
    for k in range(1, 9):
        x, y = BLOCK_DOOR[k]
        for r in range(1, 13):
            rid = f'room_{k}{r:02d}'
            if rid in OPEN_ROOMS:
                bx, by = OPEN_ROOMS[rid]
                out[f'bed_{k}{r:02d}'] = dict(at=(bx, by, 0), kind='bed', room=rid, pose='lie', yaw=90)
            else:           # behind its shut door: a hidden place outside the block's door (§21.1)
                out[f'bed_{k}{r:02d}'] = dict(at=(x + (-1.2 if k % 2 else 1.2), y + (r - 6.5) * 0.04, 0),
                                              kind='bed', room=rid, pose='lie', hidden=True)
    return out


def _mess_seats():
    out = {}
    for t in range(1, 21):
        tx = -357.5 + 5 * ((t - 1) % 7) if t <= 14 else -357.5 + 5 * [0, 1, 3, 4, 5, 6][t - 15]
        ty = -3.2 if t <= 7 else (-0.2 if t <= 14 else 2.6)
        out[f'mess_{t}s'] = dict(at=(tx, round(ty - 0.6, 2), 0), kind='seat', room='mess', pose='sit', yaw=0)
        out[f'mess_{t}n'] = dict(at=(tx, round(ty + 0.6, 2), 0), kind='seat', room='mess', pose='sit', yaw=180)
    return out


ANCHORS = {
    # the bus's stops and its depot (the camp's parking), and the plant gate (staff.json's gate, §21.1)
    'camp_stop': dict(at=(-273, 22.6, 0), kind='stop'), 'gate_stop': dict(at=(-108, 22.6, 0), kind='stop'),
    'cr_stop': dict(at=(-46, 20.2, 0), kind='stop'), 'bus_depot': dict(at=(-280, -20, 0), kind='depot'),
    'gate': dict(at=(-116, 23.5, 0), kind='door'),
    'gate_post': dict(at=(-115.5, 25, 0), kind='desk', room='gate_house', yaw=90),
    'camp_post': dict(at=(-267.5, 24, 0), kind='desk', room='camp_booth', yaw=270),
    # the mess: its door, the serving counter, the kitchen's range and sinks, seats at every table
    'mess_door': dict(at=(-340, 2.6, 0), kind='door', room='mess'),
    'mess_serve': dict(at=(-340, -5.4, 0), kind='counter', room='mess'),
    'kitchen_range': dict(at=(-340, -14.5, 0), kind='table', room='kitchen', yaw=180),
    'kitchen_sinks': dict(at=(-327, -14.5, 0), kind='table', room='kitchen', yaw=180),
    **_mess_seats(),
    'gym_door': dict(at=(-352, 26.8, 0), kind='door', room='gym'),
    **{f'gym_{i}': dict(at=a, kind='seat', room='gym', pose=p, yaw=y) for i, (a, p, y) in enumerate([
        ((-357, 33.5, 0), 'stand', 0), ((-355, 33.5, 0), 'stand', 0), ((-353, 33.5, 0), 'stand', 0),
        ((-350.5, 33.8, 0), 'sit', 0), ((-348.8, 33.8, 0), 'sit', 0), ((-356.5, 30.6, 0), 'sit', 90),
        ((-351.5, 30.6, 0), 'sit', 90)], 1)},
    'rec_door': dict(at=(-330, 26.8, 0), kind='door', room='rec'),
    **{f'rec_{i}': dict(at=a, kind='seat', room='rec', pose='sit', yaw=y) for i, (a, y) in enumerate([
        ((-333.2, 31.3, 0), 0), ((-326.8, 31.3, 0), 0), ((-335.9, 33.4, 0), 270), ((-335.75, 28.6, 0), 90),
        ((-334.25, 28.6, 0), 270), ((-325.75, 28.6, 0), 90), ((-324.25, 28.6, 0), 270)], 1)},
    'pray_door': dict(at=(-308, 26.8, 0), kind='door', room='prayer'),
    **{f'pray_{i}': dict(at=(-311 + 1.5 * (i % 4), 32 + 1.5 * (i // 4), 0), kind='seat', room='prayer', pose='kneel',
                         yaw=0) for i in range(8)},
    'ldy_door': dict(at=(-357.4, 50, 0), kind='door', room='laundry'),
    **{f'ldy_{i}': dict(at=(-357 + 0.8 * i, 52.8, 0), kind='seat', room='laundry', yaw=0) for i in range(1, 5)},
    'ldy_table': dict(at=(-353, 48.8, 0), kind='table', room='laundry', yaw=180),
    'camp_desk': dict(at=(-286.5, 27.7, 0), kind='desk', room='camp_office', pose='sit', yaw=180),
    **_beds(),
    # the admin building's ground floor (§18.5's interior): the permit office's desks, the meeting room, the lobby,
    # the offices
    'adm_door': dict(at=(-108, 98.8, 0), kind='door', room='admin'),
    'adm_permit_1': dict(at=(-114.2, 108.0, 0), kind='desk', room='admin', pose='sit', yaw=0),
    'adm_permit_2': dict(at=(-111.6, 108.0, 0), kind='desk', room='admin', pose='sit', yaw=0),
    'meet_door': dict(at=(-98, 104.6, 0), kind='door', room='meeting'),
    **{f'meet_{i}': dict(at=(x, y, 0), kind='seat', room='meeting', pose='sit', yaw=yw) for i, (x, y, yw) in enumerate([
        (-99.4, 106.95, 0), (-98.0, 106.95, 0), (-96.6, 106.95, 0), (-99.4, 109.05, 180), (-98.0, 109.05, 180),
        (-96.6, 109.05, 180)], 1)},
    **{f'office_{i}': dict(at=(x, 100.4, 0), kind='desk', room='offices', pose='sit', yaw=0)
       for i, x in enumerate([-112, -108, -104, -100, -96], 1)},
    'adm_lobby_seat': dict(at=(-111.6, 102.2, 0), kind='seat', room='admin', pose='sit', yaw=270),
    # the workshops' I&C calibration bench and the store's counter
    'ws_cal': dict(at=(-123.4, 62.3, 0), kind='table', room='ic_shop', pose='sit', yaw=180),
    'store_counter': dict(at=(-81.3, 52, 0), kind='store', yaw=90),
}

# the places among the furniture (seats, beds, the counters): a person stands or sits at the walkable point beside
# where the furniture is (staff_layout.gd's `snap`), clear of it
SNAP = {pid for pid, a in ANCHORS.items() if a['kind'] in ('seat', 'bed', 'desk', 'table', 'store', 'counter')
        and not a.get('hidden')} | {'gate'}

# The bus's roads (metres along the road: the depot to the camp gate's stop, along the road to the plant gate, on to
# the control building's stop)
ROADS = [('bus_depot', 'camp_stop', 52), ('camp_stop', 'gate_stop', 166), ('gate_stop', 'cr_stop', 64)]
DRIVE = 8.0                 # m/s


def off_site(pid, at):
    return at[0] < FENCE_X


def roles():
    def role(rid, title, disc, auth, routine, play, look, ppe=None):
        return {'id': rid, 'title': title, 'discipline': disc, 'look': look, 'authority': auth,
                'ppe': ppe if ppe is not None else ['helmet', 'boots', 'glasses'], 'routine': routine, 'play': play}
    office = ['helmet', 'boots', 'glasses', 'ear']     # (the halls need hearing protection: the walk-round)
    return [
        role('guard', 'Security guard', 'security', [], 'guard_plant', False, 'supervisor', []),
        role('plant_mgr', 'Plant manager', 'mgmt', [], 'mgr_days', True, 'engineer', office),
        role('ops_mgr', 'Operations manager', 'mgmt', ['approve'], 'mgr_days', True, 'engineer', office),
        role('maint_mgr', 'Maintenance manager', 'mgmt', ['approve'], 'mgr_days', True, 'engineer', office),
        role('ic_eng', 'I&C engineer', 'inst', ['request', 'accept'], 'eng_days', True, 'engineer', office),
        role('mech_eng', 'Mechanical engineer', 'mech', ['request', 'accept'], 'eng_days', True, 'engineer', office),
        role('elec_eng', 'Electrical engineer', 'elec', ['request', 'accept', 'lock_electrical'], 'eng_days', True,
             'engineer', office),
        role('driver', 'Driver', 'transport', ['drive'], 'drv_shift', True, 'supervisor', []),
        role('store', 'Storekeeper', 'mech', [], 'store_days', False, 'coverall_mech', []),
        role('camp', 'Camp staff', 'camp', [], 'camp_cook', False, 'supervisor', []),
    ]


def rosters():
    week = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
    return [{'id': 'driver_shift', 'kind': 'rotation', 'cycle': ['D', 'D', 'N', 'N', 'O', 'O', 'O', 'O'],
             'crews': {'a': 0, 'b': 2, 'c': 4, 'd': 6},
             'hours': {'D': ['04:40', '16:40'], 'N': ['16:40', '04:40']}},
            {'id': 'camp_early', 'kind': 'days', 'days': week, 'hours': ['04:30', '13:00']},
            {'id': 'camp_late', 'kind': 'days', 'days': week, 'hours': ['12:00', '20:30']}]


def people():
    out = []
    for crew in 'abcd':
        C = crew.upper()
        out.append({'id': f'{crew}_guard1', 'role': 'guard', 'roster': 'shift', 'crew': crew,
                    'call': f'Gate, crew {C}'})
        out.append({'id': f'{crew}_guard2', 'role': 'guard', 'roster': 'shift', 'crew': crew,
                    'call': f'Camp gate, crew {C}', 'routine': 'guard_camp'})
        out.append({'id': f'{crew}_drv', 'role': 'driver', 'roster': 'driver_shift', 'crew': crew,
                    'call': f'Driver, crew {C}'})
    out += [{'id': 'pm', 'role': 'plant_mgr', 'roster': 'day', 'call': 'Plant manager'},
            {'id': 'om', 'role': 'ops_mgr', 'roster': 'day', 'call': 'Operations manager'},
            {'id': 'mm', 'role': 'maint_mgr', 'roster': 'day', 'call': 'Maintenance manager'},
            {'id': 'ice', 'role': 'ic_eng', 'roster': 'day', 'call': 'I&C engineer'},
            {'id': 'mce', 'role': 'mech_eng', 'roster': 'day', 'call': 'Mechanical engineer'},
            {'id': 'ele', 'role': 'elec_eng', 'roster': 'day', 'call': 'Electrical engineer'},
            {'id': 'store1', 'role': 'store', 'roster': 'day', 'call': 'Storekeeper'}]
    for i, (ro, rt, call) in enumerate([('camp_early', 'camp_cook', 'Cook 1'), ('camp_late', 'camp_cook', 'Cook 2'),
                                        ('camp_early', 'camp_clean', 'Cleaner 1'),
                                        ('camp_late', 'camp_clean', 'Cleaner 2'),
                                        ('camp_early', 'camp_laundry', 'Laundry 1'),
                                        ('camp_late', 'camp_laundry', 'Laundry 2')], 1):
        out.append({'id': f'camp{i}', 'role': 'camp', 'roster': ro, 'call': call, 'routine': rt})
    return out


def homes(everyone):
    """A room each, blocks in order (block 1's two open rooms to crew A's CW field operator and first control room
    operator, whom a trainee often plays)."""
    rooms = [f'room_{k}{r:02d}' for k in range(1, 9) for r in range(1, 13)]
    first = {'a_fo_cw': 'room_101', 'a_ccr1': 'room_107'}
    left = [r for r in rooms if r not in first.values()]
    for p in everyone:
        p['home'] = first[p['id']] if p['id'] in first else left.pop(0)


def slot(at, task, **kw):
    return dict({'at': at, 'task': task}, **kw)


# who rides which bus in and out (§21.6): the routine's commute slots, by the routine's kind
SHIFT_ROUTINES = ('sup_shift', 'ccr_shift', 'field_gt', 'field_st', 'field_cw', 'elec_shift', 'guard_plant')
WTP_ROUTINES = ('wtp_shift', 'chem_shift')
DAY_TO_CR = ('tech_days', 'ms_mech', 'ms_elec', 'ms_ic', 'hse_days1', 'hse_days2', 'con_sup_days', 'con_days')
DAY_WTP = ('chem_days', 'chem_days2')   # (the day chemists: in by the bus, home on foot from the WTP's lab)
DAY_TO_GATE = ('mgr_days', 'eng_days', 'store_days')


def commute(rid, routine):
    """The commute slots a duty routine gains (§21.6)."""
    if rid == 'guard_plant':        # (the plant gate's guard: the gate's own stop)
        return [slot('start-0:50', 'bus_in_gate'), slot('end+0:05', 'bus_out_gate')]
    if rid in SHIFT_ROUTINES:
        return [slot('start-0:50', 'bus_in'), slot('end+0:05', 'bus_out')]
    if rid in WTP_ROUTINES:         # (their PPE put on with the commute: the routine's own gear_up is dropped)
        routine['slots'] = [x for x in routine['slots'] if x['task'] != 'gear_up']
        return [slot('start-1:40', 'bus_in_wtp'), slot('end+0:05', 'walk_out')]
    if rid in DAY_TO_CR:
        return [slot('start-0:50', 'bus_in'), slot('end+0:05', 'bus_out')]
    if rid in DAY_WTP:
        return [slot('start-0:50', 'bus_in'), slot('end+0:05', 'walk_out')]
    if rid in DAY_TO_GATE:
        return [slot('start-0:35', 'bus_in_gate'), slot('end+0:05', 'bus_out_gate')]
    return []


def routines():
    return [
        {'id': 'guard_plant', 'idle': 'guard_at_gate', 'slots': [slot('start+1:00', 'patrol_site', every='2:00',
                                                                      until='end-1:00')]},
        {'id': 'guard_camp', 'idle': 'guard_at_camp', 'slots': [slot('start+1:30', 'patrol_camp', every='2:00',
                                                                     until='end-1:00')]},
        {'id': 'mgr_days', 'idle': 'office_work', 'slots': [slot('07:30', 'morning_meeting'),
                                                            slot('10:00', 'walk_round', days=['mon']),
                                                            slot('14:00', 'office_reports')]},
        {'id': 'eng_days', 'idle': 'office_work', 'slots': [slot('07:30', 'morning_meeting'),
                                                            slot('14:00', 'review_jobs')]},
        {'id': 'store_days', 'idle': 'store_issue', 'slots': []},
        {'id': 'drv_shift', 'idle': 'drv_wait', 'slots': [slot('start+0:05', 'bus_check')]},
        {'id': 'camp_cook', 'idle': 'cook', 'slots': []},
        {'id': 'camp_clean', 'idle': 'clean_blocks', 'slots': []},
        {'id': 'camp_laundry', 'idle': 'laundry_work', 'slots': []},
        # off duty (§21.2): a meal after the duty, free time, sleep before the next, breakfast; a day off's meals
        {'id': 'off_shift', 'idle': 'at_home', 'slots': [
            slot('prev+0:30', 'meal'), slot('prev+1:30', 'free_time'), slot('next-9:30', 'sleep'),
            slot('next-1:50', 'breakfast')]},
        {'id': 'off_days', 'idle': 'at_home', 'slots': [
            slot('prev+1:30', 'meal'), slot('prev+2:30', 'free_time'), slot('next-9:00', 'sleep'),
            slot('next-1:30', 'breakfast'), slot('12:30', 'meal', days=['sun'])]},
        {'id': 'off_camp', 'idle': 'at_home', 'slots': [slot('prev+0:30', 'free_time'), slot('next-8:00', 'sleep')]},
    ]


def off_routine(role):
    """The off-duty routine of a role (§21.2)."""
    if role in ('camp',):
        return 'off_camp'
    if role in ('shift_sup', 'ccr_op', 'field_op', 'elec_ap', 'wtp_op', 'shift_chem', 'guard', 'driver'):
        return 'off_shift'
    return 'off_days'


def tasks():
    T = []

    def task(tid, title, steps, **kw):
        T.append(dict({'id': tid, 'title': title, 'steps': steps}, **kw))
    mess = {'go': {'kind': 'seat', 'room': 'mess'}}
    task('bus_in', 'The bus to the plant', [{'ride': {'from': 'camp_stop', 'to': 'cr_stop'}}], priority=1,
         interruptible=False)
    task('bus_out', 'The bus to the camp', [{'ride': {'from': 'cr_stop', 'to': 'camp_stop'}}, {'go': 'home'},
                                            {'work': 5}], priority=3)
    task('bus_in_wtp', 'The bus to the plant, PPE on at the control building', [
        {'ride': {'from': 'camp_stop', 'to': 'cr_stop'}}, {'go': {'kind': 'locker', 'room': 'lockers'}},
        {'ppe': 'role'}], priority=1, interruptible=False)
    task('walk_out', 'Home to the camp on foot (the WTP is far from the bus)', [{'go': 'home'}, {'work': 5}],
         priority=3)
    task('bus_in_gate', 'The bus to the plant gate', [{'ride': {'from': 'camp_stop', 'to': 'gate_stop'}}],
         priority=1, interruptible=False)
    task('bus_out_gate', 'The bus to the camp', [{'ride': {'from': 'gate_stop', 'to': 'camp_stop'}}, {'go': 'home'},
                                                 {'work': 5}], priority=3)
    task('meal', 'A meal at the mess', [mess, {'work': [20, 35], 'anim': 'eat'}])
    task('breakfast', 'Breakfast at the mess', [mess, {'work': [10, 20], 'anim': 'eat'}])
    task('free_time', 'Free time', [{'choose': [[3, 'gym_time'], [2, 'rec_time'], [2, 'laundry_time'],
                                                [1, 'prayer_time'], [4, 'room_time']]}])
    task('gym_time', 'The gym', [{'go': {'kind': 'seat', 'room': 'gym'}, 'else': 2}, {'work': [30, 60]},
                                 {'go': 'home'}], priority=4)
    task('rec_time', 'The recreation room', [{'go': {'kind': 'seat', 'room': 'rec'}, 'else': 2},
                                             {'work': [30, 90], 'anim': 'sit'}, {'go': 'home'}], priority=4)
    task('laundry_time', 'The laundry', [{'go': {'kind': 'seat', 'room': 'laundry'}, 'else': 2}, {'work': [20, 40]},
                                         {'go': 'home'}], priority=4)
    task('prayer_time', 'The prayer room', [{'go': {'kind': 'seat', 'room': 'prayer'}, 'else': 2}, {'work': 15},
                                            {'go': 'home'}], priority=4)
    task('room_time', 'In the room', [{'go': 'home'}, {'work': [30, 60]}], priority=4)
    task('sleep', 'Sleep', [{'sleep': {'until': 'next-2:00'}}], priority=4, interruptible=False)
    task('at_home', 'At home', [{'go': 'home'}, {'work': 60, 'anim': 'sleep'}])
    task('guard_at_gate', 'At the plant gate', [{'go': 'gate_post'}, {'work': 30}])
    task('guard_at_camp', 'At the camp gate', [{'go': 'camp_post'}, {'work': 30}])
    task('patrol_site', 'Patrol: the fence line by the gate and the admin area',
         [{'go': 'p_rw_e'}, {'work': 2}, {'go': 'p_store'}, {'work': 2}, {'go': 'p_adm_n'}, {'work': 2},
          {'go': 'gate_post'}])
    task('patrol_camp', 'Patrol: the camp', [{'go': 'p_bw95'}, {'work': 2}, {'go': 'p_cpark'}, {'work': 2},
                                             {'go': 'camp_post'}])
    task('office_work', 'At the office', [{'go': {'kind': 'desk', 'room': 'offices'}, 'else': 2},
                                          {'work': 30, 'anim': 'type'}, {'work': 30}])
    task('office_reports', 'Reports', [{'go': {'kind': 'desk', 'room': 'offices'}, 'else': 2},
                                       {'work': 45, 'anim': 'type'}, {'work': 1}])
    task('morning_meeting', 'The morning meeting',
         [{'meet': {'room': 'meeting', 'with': ['plant_mgr', 'ops_mgr', 'maint_mgr'], 'minutes': 30}}], priority=2)
    task('walk_round', 'The managers\' walk-round', [
        {'go': {'kind': 'locker', 'room': 'lockers'}}, {'ppe': 'role'}, {'go': 'p_st_20'}, {'work': 5, 'anim': 'inspect'}, {'go': 'p_gt_in'},
        {'work': 5, 'anim': 'inspect'}, {'go': 'p_cw_o'}, {'work': 5, 'anim': 'inspect'}, {'go': 'p_adm_lobby'}],
         priority=3)
    task('review_jobs', 'A look at the day\'s jobs in the workshops', [{'go': 'p_ws_in'}, {'work': 20, 'anim': 'talk'},
                                                                      {'go': {'kind': 'desk', 'room': 'offices'},
                                                                       'else': 3}, {'work': 10}])
    task('store_issue', 'At the store\'s counter', [{'go': 'store_counter'}, {'work': 30}])
    task('drv_wait', 'At the depot', [{'go': 'bus_depot'}, {'work': 20}])
    task('bus_check', 'The bus\'s daily checks', [{'go': 'bus_depot'}, {'work': 10, 'anim': 'inspect'}])
    task('cook', 'In the kitchen', [{'go': {'kind': 'table', 'room': 'kitchen'}, 'else': 2}, {'work': 30},
                                    {'go': 'mess_serve'}, {'work': 15}])
    task('clean_blocks', 'Cleaning the blocks', [{'go': 'p_bw35'}, {'work': 10}, {'go': 'p_bw55'}, {'work': 10},
                                                 {'go': 'p_bw75'}, {'work': 10}, {'go': 'p_bw95'}, {'work': 10}])
    task('laundry_work', 'The laundry', [{'go': {'kind': 'table', 'room': 'laundry'}, 'else': 1}, {'work': 30}])
    return T


def vehicles():
    """The bus (the camp's second bus stays parked: one driver is on duty at a time, §21.6)."""
    to_plant = ['camp_stop', 'gate_stop', 'cr_stop']
    to_camp = ['cr_stop', 'gate_stop', 'camp_stop']
    wtp = ['camp_stop', 'cr_stop']      # (the WTP's people: straight to the control building, then the walk)
    runs = [(t, wtp) for t in ('05:02', '17:02')] + \
        [(t, to_plant) for t in ('05:40', '06:35', '06:50', '17:40')] + \
        [(t, to_camp) for t in ('06:25', '16:15', '18:25')]
    runs.sort()
    return [{'id': 'bus_1', 'kind': 'bus', 'seats': 45, 'driver': 'driver', 'home': 'bus_depot',
             'runs': [{'at': t, 'stops': s, 'dwell': 1} for t, s in runs]}]
