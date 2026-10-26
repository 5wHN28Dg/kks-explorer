"""The water treatment plant's staff (docs/plant3d/STAFF.md, WATER-TREATMENT.md §7 "Staff"; milestone S3), joined to
the first train's by train_staff.py: the WTP operator and the shift chemist of each crew, two chemists on days; the
WTP's places (its control room with the WTP desk 00CWD10 and lockers, the laboratory, the sample panel), the walk to
it from the train, its zones (the treatment building's hall, the chemical areas where face shield and apron are worn),
and its tasks: the handover at the WTP panel, the operator's rounds, the sequences run from the WTP desk (a filter's
backwash ordered by the shift supervisor, a mixed bed's regeneration after the laboratory's silica finding, an RO
train's cleaning in place, an RO trip's flush, the regenerant tanks' bulk delivery), the chemists' samples and dosing
checks, the train's call when its demineralised water runs low, and the WTP's jobs under permits (cartridge changes,
the analysers' calibrations, a mixed bed's internals in a confined space, an RO train's membranes).

Nothing here is a real plant's organisation; people have call signs."""

# The walking network to and through the WTP (plant coordinates), measured on the navigation mesh like the train's
# (train_staff.py, apps/plant3d/tests/staff_layout.gd): north of the cooling tower to the treatment building's west
# door, its hall, its control room and laboratory, the yard north of it (the degasser, the mixed beds' feed pumps, the
# backwash pumps, the filter bank and its deck, the filtered water tank and its pumps), the demineralised water tanks,
# the chemical store and the neutralisation pit, and the road east and north to the intake.
POINTS = {
    'p_wtp_r1': (215, 40, 0), 'p_wtp_r2': (268, 41, 0), 'p_wtp_w': (296.5, 56, 0), 'p_wtp_hw': (302, 57, 0),
    'p_wtp_hm': (314, 57, 0), 'p_wtp_he': (328.5, 57, 0), 'p_wtp_hne': (328.5, 67.6, 0), 'p_wtp_lab': (332, 55.4, 0),
    'p_wtp_ctl': (332, 67.6, 0), 'p_wtp_hn': (322, 72.5, 0), 'p_wtp_n': (322, 78.5, 0), 'p_wtp_nw': (300, 79, 0),
    'p_wtp_dt': (276, 75, 0), 'p_wtp_bw': (321, 93, 0), 'p_wtp_fw': (321, 111, 0), 'p_wtp_fst': (324.75, 121, 0),
    'p_wtp_fdk': (330, 111, 4.5), 'p_wtp_ft': (284, 104, 0), 'p_wtp_ne': (345, 80, 0), 'p_wtp_e': (343.5, 52, 0),
    'p_wtp_se': (343.5, 44, 0), 'p_wtp_chs': (351.5, 45.3, 0), 'p_wtp_chin': (355, 55, 0), 'p_wtp_chn': (355, 64.5, 0),
    'p_wtp_pit': (366.5, 70, 0), 'p_wtp_r4': (400, 44, 0), 'p_int_sw': (425, 70, 0), 'p_int_w': (429.5, 85, 0),
    'p_int_in': (436.5, 89, 0), 'p_int_s': (450, 79, 0), 'p_int_se': (462, 79, 0), 'p_wtp_cl': (373, 111, 0),
    'p_wtp_ftn': (296, 130, 0), 'p_wtp_mb': (308, 67, 0),
}
EDGES = [
    ('p_c165', 'p_wtp_r1'), ('p_wtp_r1', 'p_wtp_r2'), ('p_wtp_r2', 'p_wtp_w'), ('p_wtp_w', 'p_wtp_hw'),
    ('p_wtp_hw', 'p_wtp_hm'), ('p_wtp_hm', 'p_wtp_he'), ('p_wtp_he', 'p_wtp_hne'), ('p_wtp_he', 'p_wtp_lab'),
    ('p_wtp_hne', 'p_wtp_ctl'), ('p_wtp_hne', 'p_wtp_hn'), ('p_wtp_hn', 'p_wtp_n'), ('p_wtp_n', 'p_wtp_nw'),
    ('p_wtp_w', 'p_wtp_dt'), ('p_wtp_nw', 'p_wtp_dt'), ('p_wtp_n', 'p_wtp_bw'), ('p_wtp_bw', 'p_wtp_fw'),
    ('p_wtp_fw', 'p_wtp_fst'), ('p_wtp_fst', 'p_wtp_fdk'), ('p_wtp_nw', 'p_wtp_ft'), ('p_wtp_fw', 'p_wtp_ft'),
    ('p_wtp_n', 'p_wtp_ne'), ('p_wtp_lab', 'p_wtp_e'), ('p_wtp_e', 'p_wtp_se'), ('p_wtp_se', 'p_wtp_chs'),
    ('p_wtp_chin', 'p_wtp_chn'), ('p_wtp_chn', 'p_wtp_ne'), ('p_wtp_chn', 'p_wtp_pit'),
    ('p_wtp_chs', 'p_wtp_r4'), ('p_wtp_r4', 'p_int_sw'), ('p_int_sw', 'p_int_w'), ('p_int_w', 'p_int_in'),
    ('p_wtp_r2', 'p_wtp_se'), ('p_int_in', 'p_int_s'), ('p_int_s', 'p_int_se'), ('p_wtp_pit', 'p_wtp_cl'),
    ('p_wtp_ne', 'p_wtp_cl'), ('p_wtp_ft', 'p_wtp_ftn'), ('p_wtp_fst', 'p_wtp_ftn'), ('p_wtp_hw', 'p_wtp_mb'),
    ('p_wtp_mb', 'p_wtp_hn'),
]
# The WTP's rooms: its control room (the desk 00CWD10, a table, the lockers where its people keep their PPE and the
# face shields and aprons of chemical work) and the laboratory (the bench 00QUG20, seats; the sample panel 00QUG10 on
# its east wall)
ANCHORS = {
    'wtp_ctl_door': dict(at=(331, 67.65, 0), kind='door', room='wtp_control'),
    'wtp_desk': dict(at=(335.8, 67.2, 0), kind='desk', room='wtp_control', yaw=180, pose='sit'),
    'wtp_desk_2': dict(at=(334.2, 67.2, 0), kind='desk', room='wtp_control', yaw=180, pose='sit'),
    'wtp_table': dict(at=(338, 72, 0), kind='table', room='wtp_control', yaw=90, pose='sit'),
    'wtp_lk_door': dict(at=(332.5, 72.6, 0), kind='door', room='wtp_lockers'),
    **{f'wtp_locker_{k}': dict(at=(331 + k, 73.9, 0), kind='locker', room='wtp_lockers', yaw=0) for k in range(4)},
    'lab_door': dict(at=(331, 55.45, 0), kind='door', room='lab'),
    'lab_seat_1': dict(at=(333.5, 52.5, 0), kind='seat', room='lab', yaw=0),
    'lab_seat_2': dict(at=(335.5, 52.5, 0), kind='seat', room='lab', yaw=0),
    'lab_seat_3': dict(at=(337.5, 57.5, 0), kind='seat', room='lab', yaw=90),
}
# Zones (STAFF.md §4): the WTP's yards (helmet, boots, glasses), round the treatment building's control room and
# laboratory, which are no zone; its hall with the RO's high-pressure pumps (hearing protection, as the signs); the
# intake's pump house; and the chemical areas where acids and caustic are handled: the chemical store with the
# dosing skids, and the regenerant tanks with the CIP skid in the hall (face shield and apron, gloves).
CHEM_PPE = ['helmet', 'boots', 'glasses', 'gloves', 'face_shield', 'apron']
ZONES = [
    ('wtp_yard_w', 'Water treatment plant, west yards', (270, 45, 330, 135), ['helmet', 'boots', 'glasses']),
    ('wtp_yard_n', 'Water treatment plant, north yards', (330, 75, 390, 135), ['helmet', 'boots', 'glasses']),
    ('wtp_yard_e', 'Water treatment plant, chemical store and pit', (340, 45, 390, 75), ['helmet', 'boots', 'glasses']),
    ('wtp_hall', 'Treatment building hall', (300, 50, 330, 75), ['helmet', 'boots', 'glasses', 'ear']),
    ('wtp_regen', 'Regenerant tanks and CIP skid', (301, 50.3, 316.6, 55.5), CHEM_PPE),
    ('wtp_chem', 'Chemical store', (344, 48, 366, 61), CHEM_PPE),
    ('intake', 'Intake pump house', (430, 60, 470, 110), ['helmet', 'boots', 'glasses', 'ear']),
]
# The scenario `shift_wtp` (milestone S3): the day shift with the WTP's day work coming in its first hours: filter 1
# nearly due for its backwash (its head loss reaches 2.2 m at about 06:05), mixed bed A further used than in
# wtp_normal (its silica passes the laboratory's 15 µg/kg at about 06:50 and the analyser's alarm at 20 at about
# 08:15; the lags at their steady values, from wtp_normal's run)
SHIFT_WTP = {'fl1_hl': 2.17, 'mb_a_ex': 0.875555556, 'mb_a_cond_lag': 0.0794259, 'mb_a_si': 10.638618916}

# The train's own areas: its alarms and trips are the main control room's; the WTP's and the intake's are the WTP's
# (PLANT3D §17.12)
TRAIN_AREAS = ['gt1', 'hrsg1', 'st', 'cw', 'ct', 'bop', 'trafo1']
WTP_AREAS = ['wtp', 'intake']

# The WTP operator's round (STAFF.md §3): the gauges of the whole plant, in the order walked from the WTP's control
# room (the hall, the demineralised water tanks, the filtered water tank, the filters, the clarifiers, the intake,
# the pit), each with the range it holds running normally (tests/test_plant3d_staff.py checks them on shift_cold).
# The site is large and walking is not compressed (STAFF.md §2): a round takes about an hour and a half of the clock,
# so it is made twice a shift, four hours apart (the last ends before the handover)
ROUND = [
    ('00GCB21CQ002', [0, 250], 5), ('00GCB11CP001', [0, 1], 0.05), ('00GCL10CL001', [25, 100], 1),
    ('00GBL10CL001', [30, 100], 1), ('00GBB11CP001', [0, 2.2], 0.05), ('00GBB12CP001', [0, 2.2], 0.05),
    ('00GBB13CP001', [0, 2.2], 0.05), ('00GBB14CP001', [0, 2.2], 0.05), ('00GBB15CP001', [0, 2.2], 0.05),
    ('00GBB16CP001', [0, 2.2], 0.05), ('00GBD11CQ001', [0, 5], 0.1), ('00GBD12CQ001', [0, 5], 0.1),
    ('00GAA10CL001', [-1, 1], 0.05), ('00GNR10CQ001', [6, 9], 0.1),
]
# The chemists' samples: drawn at the sample panel (the SDI read there), analysed at the laboratory bench. The mixed
# beds' silica has the laboratory's action limit, 15 µg/kg, under the analysers' alarm at 20: a finding there is
# acted on by the WTP operator (the reactions below)
SAMPLES_PANEL = [('00QUG10', [0, 5], 0.1)]
SAMPLES_LAB = [('00GBB10', [0, 0.5], 0.02), ('00GCB21CQ001', [0, 50], 1), ('00GCF11CQ001', [0, 0.2], 0.005),
               ('00GCF11CQ002', [0, 15], 0.5), ('00GCF12CQ001', [0, 0.2], 0.005), ('00GCF12CQ002', [0, 15], 0.5)]
# The chemical stock and dosing check: the coagulant day tank, the bisulphite's effect on the RO feed ORP, the
# regenerant tanks (a low one is refilled from the bulk delivery by the WTP operator)
STOCK = [('00GBN10BB001', [20, 100], 1), ('00GCB21CQ002', [0, 250], 5), ('00GCP10BB001', [20, 100], 1),
         ('00GCP20BB001', [20, 100], 1)]
FILL = {'00GCP10BB001': ('fill_acid', 'Refill the regeneration acid tank from the bulk delivery'),
        '00GCP20BB001': ('fill_caustic', 'Refill the regeneration caustic tank from the bulk delivery'),
        '00GBN10BB001': ('fill_coag', 'Refill the coagulant day tank')}

# Faults of the scenario that make one of the WTP's works: the WTP operator asks for its permit
FAULT_WORK = {'cart_a_clog': 'wo_cart_a', 'cart_b_clog': 'wo_cart_b', 'mb_a_resin': 'wo_mb_a_resin',
              'mb_b_resin': 'wo_mb_b_resin', 'ro_a_cl_damage': 'wo_ro_a_membranes',
              'ro_b_cl_damage': 'wo_ro_b_membranes', 'ro_a_orp_drift': 'wo_ro_a_orp_cal',
              'ro_b_orp_drift': 'wo_ro_b_orp_cal', 'ro_a_cond_drift': 'wo_ro_a_cond_cal',
              'ro_b_cond_drift': 'wo_ro_b_cond_cal'}
# The I&C maintenance supervisor's week at the WTP: the standby RO train's analysers (RO B in the content's days)
WEEK = [('wo_ro_b_orp_cal', ['tue', 'thu']), ('wo_ro_b_cond_cal', ['wed', 'sat'])]
# who locks each kind of point at the WTP
LOCKER = {'electrical': 'elec_ap', 'mechanical': 'wtp_op', 'process': 'wtp_op', 'instrument': 'ic_tech'}

MESSAGES = {
    'handover_wtp': 'WTP handover taken: running streams, tanks, open permits and alarms noted',
    'handover_lab': 'Laboratory handover taken: samples due and results noted',
    'round_done_wtp': 'WTP round done: readings in the log',
    'backwash_order': 'A filter is due: backwash it',
    'backwash_on': 'Filter backwash started',
    'backwash_done': 'Filter backwashed and back in service',
    'regen_on': 'Mixed bed changed over: the exhausted bed is regenerating',
    'regen_done': 'Mixed bed regenerated and rinsed: in standby',
    'cip_on': 'RO train off line for its cleaning in place',
    'cip_done': 'RO train cleaned: in standby, the wastes neutralised',
    'ro_flushed': 'RO train tripped: flushed, waiting for the cause to be found',
    'samples_done': 'Samples analysed: results in the log',
    'stock_done': 'Chemical stock and dosing checked: results in the log',
    'delivery': 'Tank being filled from the bulk delivery',
    'demin_low': 'Demineralised water tank low at the train: more transfer please',
    'transfer_on': 'Transfer pumps running to the train\'s demineralised water tank',
    'prepared': 'Equipment out of service and safe for its isolation',
}


def _go(code):
    return {'go': {'kks': code}}


DESK = {'go': {'kind': 'desk', 'room': 'wtp_control'}}    # (two places at the WTP desk 00CWD10)
LOCKER_GO = {'go': {'kind': 'locker', 'room': 'wtp_lockers'}}
CHEM_GEAR = [LOCKER_GO, {'ppe': ['face_shield', 'apron']}]


def scr(code, do, **kw):
    return dict({'op': {'kks': code, 'do': do, 'where': 'screen'}}, **kw)


def loc(code, do, **kw):
    return dict({'op': {'kks': code, 'do': do, 'where': 'local'}}, **kw)


def wait(until, minutes, **kw):
    return {'wait': dict({'until': until, 'minutes': minutes}, **kw)}


def say(msg, to):
    return {'say': msg, 'to': to}


def reads(items, work=None):
    out = []
    for code, ex, tol in items:
        out += [_go(code), {'read': code, 'expect': ex, 'tol': tol}]
        if work:
            out.append({'work': work, 'anim': 'inspect'})
    return out


def work_codes():
    """Every WTP code a person of the WTP works at (beyond the alarms' and works' codes, train_staff.work_codes)."""
    out = [c for c, _, _ in ROUND + SAMPLES_PANEL + SAMPLES_LAB + STOCK]
    out += ['00QUG20', '00GCB30BB001', '00GCB30AH001', '00GCF11CQ003', '00GCF12CQ003']
    return out


def roles():
    field = ['helmet', 'boots', 'glasses', 'gloves', 'ear']

    def role(rid, title, auth, routine, look):
        return {'id': rid, 'title': title, 'discipline': 'chem', 'look': look, 'authority': auth, 'ppe': field,
                'routine': routine, 'play': True}
    return [
        role('wtp_op', 'WTP operator', ['operate_local', 'operate_screen', 'request', 'lock_mechanical',
                                         'lock_process', 'sample'], 'wtp_shift', 'coverall_ops'),
        role('shift_chem', 'Shift chemist', ['sample', 'request'], 'chem_shift', 'coverall_chem'),
        role('chemist', 'Chemist', ['sample', 'request'], 'chem_days', 'chemist'),
    ]


def people():
    """After S1's and S2's people (a person added at the end changes no one else's draws, PLANT3D §17.5)."""
    out = []
    for crew in 'abcd':
        C = crew.upper()
        out.append({'id': f'{crew}_wtp', 'role': 'wtp_op', 'roster': 'shift', 'crew': crew,
                    'call': f'WTP, crew {C}'})
        out.append({'id': f'{crew}_chem', 'role': 'shift_chem', 'roster': 'shift', 'crew': crew,
                    'call': f'Chemist, crew {C}'})
    for i in (1, 2):
        out.append(dict({'id': f'chem{i}', 'role': 'chemist', 'roster': 'day', 'call': f'Laboratory {i}'},
                        **({'routine': 'chem_days2'} if i == 2 else {})))
    return out


def routines(slot):
    """The WTP's people put their PPE on at the control building's locker room as they come on site (the train's
    gear_up, before anything else: priority 2), then walk to the WTP, about half an hour of the clock: their handover
    slots are a little earlier than the train's (after 05:30, when the content's scenarios start), at the time of the
    gear_up (so nobody leaves the site between the two)."""
    return [
        {'id': 'wtp_shift', 'idle': 'idle_wtp', 'slots': [
            slot('start-0:25', 'gear_up'), slot('start-0:25', 'handover_take_wtp'),
            slot('start+1:00', 'round_wtp', every='4:00', until='end-3:30'), slot('end-0:15', 'handover_give_wtp')]},
        {'id': 'chem_shift', 'idle': 'idle_lab', 'slots': [
            slot('start-0:25', 'gear_up'), slot('start-0:25', 'handover_take_lab'),
            slot('start+1:30', 'wtp_samples', every='4:00', until='end-1:00'), slot('start+3:30', 'chem_stock'),
            slot('end-0:15', 'handover_give_lab')]},
        # the two chemists on days: the stock and dosing check, the WTP's performance samples, each at their hours
        {'id': 'chem_days', 'idle': 'idle_lab', 'slots': [
            slot('07:00', 'gear_up'), slot('07:45', 'chem_stock'), slot('13:30', 'wtp_samples')]},
        {'id': 'chem_days2', 'idle': 'idle_lab', 'slots': [
            slot('07:00', 'gear_up'), slot('09:30', 'wtp_samples'), slot('14:30', 'chem_stock')]},
    ]


def _other(x):
    return 'b' if x == 'a' else 'a'


def tasks(models):
    """(tasks, reactions) of the WTP's people (the WTP works' isolation and job tasks are made by
    train_staff.tasks with this module's LOCKER and prep())."""
    T = []

    def task(tid, title, steps, **kw):
        T.append(dict({'id': tid, 'title': title, 'steps': steps}, **kw))
    meet = lambda room, role, minutes=15: {'meet': {'room': room, 'with': [role], 'minutes': minutes}}  # noqa: E731
    task('idle_wtp', 'At the WTP desk: watching the screens', [DESK, {'work': 30, 'anim': 'type'}])
    task('idle_lab', 'In the laboratory', [{'go': {'kind': 'seat', 'room': 'lab'}}, {'work': 30, 'anim': 'write'}])
    take, give = {'handover': 'take'}, {'handover': 'give'}
    task('handover_take_wtp', 'Take the WTP handover', [meet('wtp_control', 'wtp_op'),
                                                        say('handover_wtp', 'shift_sup'), take])
    task('handover_give_wtp', 'Give the WTP handover', [meet('wtp_control', 'wtp_op'), give])
    task('handover_take_lab', 'Take the laboratory handover', [meet('lab', 'shift_chem'),
                                                               say('handover_lab', 'wtp_op')])
    task('handover_give_lab', 'Give the laboratory handover', [meet('lab', 'shift_chem')])
    task('round_wtp', 'WTP round: intake, clarifiers, filters, RO and demineralised water',
         reads(ROUND, [1, 2]) + [say('round_done_wtp', 'shift_sup')])
    task('wtp_samples', 'Samples: the sample panel, then the laboratory\'s analyses',
         reads(SAMPLES_PANEL, [3, 5]) + [_go('00QUG20'), {'work': [10, 15], 'anim': 'write'}]
         + [{'read': c, 'expect': ex, 'tol': tol} for c, ex, tol in SAMPLES_LAB] + [say('samples_done', 'wtp_op')])
    task('chem_stock', 'Chemical stock and dosing check', CHEM_GEAR + reads(STOCK, 1) + [say('stock_done', 'wtp_op')])
    reacts = []
    # the regenerant tanks and the coagulant day tank refilled from the bulk delivery when a check finds one low (the
    # tanker's unloading is not built, WATER-TREATMENT §9: the delivery is the tank's fill)
    for code, (tid, title) in FILL.items():
        task(tid, title, [DESK, scr(code, 'fill'), say('delivery', 'channel')], priority=2)
        reacts.append({'on': {'finding': code}, 'roles': ['wtp_op'], 'task': tid})
    # a filter's backwash, ordered by the shift supervisor when its head loss is due (its alarm's value), run by the WTP
    # operator from the WTP desk, the air scour watched at the filter bank (WATER-TREATMENT §7, filter_backwash)
    for i in range(1, 7):
        f = f'00GBB1{i}AT001'
        task(f'order_backwash_{i}', f'Have filter {i} backwashed', [
            {'go': 'cr_sup'}, {'call': {'role': 'wtp_op', 'task': f'backwash_{i}'}},
            say('backwash_order', 'wtp_op')], priority=2)
        task(f'backwash_{i}', f'Backwash filter {i}', [
            DESK, wait('ft_bw_ok', 30), scr(f, 'backwash'), say('backwash_on', 'shift_sup'),
            _go(f'00GBB1{i}CP001'), {'work': [5, 10], 'anim': 'inspect'}, DESK, wait(f'fl{i}_clean', 60),
            say('backwash_done', 'shift_sup')], priority=2)
        reacts.append({'on': {'value': f'fl{i}_hl_h'}, 'roles': ['shift_sup'], 'task': f'order_backwash_{i}'})
    # a mixed bed's regeneration after the laboratory finds its silica over the action limit: the other bed in service,
    # this one regenerated (the regenerant tanks checked in the chemical PPE), mixed, rinsed; the pit's batch
    for x, n in (('a', 1), ('b', 2)):
        o, no = _other(x), 3 - n
        bed, obed = f'00GCF1{n}AT001', f'00GCF1{no}AT001'
        task(f'mb_regen_{x}', f'Regenerate mixed bed {x.upper()}', [
            # (each change-over op refused as already made goes on: a standby bed found exhausted is regenerated too)
            DESK, scr(obed, 'in_service', **{'else': 2}), scr(f'00GCK10AP00{no}', 'start', **{'else': 3}),
            wait(f'mb_{o}_making', 30), scr(f'00GCK10AP00{n}', 'stop', **{'else': 5}),
            scr(bed, 'standby', **{'else': 6}), scr(bed, 'regenerate'), say('regen_on', 'shift_sup'),
            wait(f'mb_{x}_rdy', 90)] + CHEM_GEAR + reads([('00GCP10BB001', [15, 100], 1),
                                                         ('00GCP20BB001', [15, 100], 1)]) + [
            DESK, scr(bed, 'inject'), wait(f'mb_{x}_airrdy', 150), scr('00GCP30AN001', 'start'),
            scr(bed, 'air_mix'), wait(f'mb_{x}_sb', 120), scr('00GNR10BB001', 'neutralise'),
            say('regen_done', 'shift_sup')], priority=2)
        reacts.append({'on': {'finding': f'00GCF1{n}CQ002'}, 'roles': ['wtp_op'], 'task': f'mb_regen_{x}'})
    # an RO train's cleaning in place when its normalised flow is down 10 % (its CIP alarm's value): the other train
    # in service, this one stopped and flushed, the high-pH then the low-pH cleaning from the CIP skid (its chemicals
    # dosed at the skid in the chemical PPE), the wastes neutralised (ro_cip)
    for x, n in (('a', 1), ('b', 2)):
        o = _other(x)
        ro, oro = f'00GCB2{n}AT001', f'00GCB2{3 - n}AT001'
        cip, heat = '00GCB30BB001', '00GCB30AH001'
        steps = [DESK, scr(oro, 'start', **{'else': 2}), wait(f'ro_{o}_hp', 60), scr(ro, 'stop', **{'else': 4}),
                 wait(f'ro_{x}_stopped', 60), say('cip_on', 'shift_sup')] + CHEM_GEAR + [
            _go(cip), loc(cip, 'fill'), wait('cip_water', 30), loc(cip, 'add_caustic'), loc(heat, 'start'),
            wait('cip_alk_ok', 90), DESK, scr(ro, 'clean'), wait(f'ro_{x}_alk_cleaned', 180),
            _go(cip), loc(heat, 'stop'), loc(cip, 'drain'), wait('cip_idle_off', 60), loc(cip, 'fill'),
            wait('cip_water', 30), loc(cip, 'add_acid'), wait('cip_acid_ok', 60), DESK, scr(ro, 'clean'),
            wait(f'ro_{x}_acid_cleaned', 180), _go(cip), loc(cip, 'drain'), wait('cip_idle', 60), DESK,
            scr('00GNR10BB001', 'neutralise'), say('cip_done', 'shift_sup')]
        task(f'cip_ro_{x}', f'Clean RO train {x.upper()} in place', steps, priority=2)
        reacts.append({'on': {'value': f'ro_{x}_nflow_l'}, 'roles': ['wtp_op'], 'task': f'cip_ro_{x}'})
        # an RO trip stops the train without its flush (W2): the operator resets the trip from the desk (its cause
        # gone with the high-pressure pump stopped), flushes the train with permeate and reports; a refusal abandons
        # the task (the debrief shows it), never a report of a flush not made
        for t, code in (('suct', f'00GCB2{n}CP002'), ('p', f'00GCB2{n}CP001'), ('orp', f'00GCB2{n}CQ002')):
            tid = f'ro_{x}_trip_{t}'
            task(f'ro_trip_{x}_{t}', f'RO train {x.upper()} tripped: reset and flush it', [
                DESK, {'op': {'kks': code, 'do': 'reset', 'trip': tid, 'where': 'screen'}}, scr(ro, 'flush'),
                say('ro_flushed', 'shift_sup')], priority=1)
            reacts.append({'on': {'trip': tid}, 'roles': ['wtp_op'], 'task': f'ro_trip_{x}_{t}'})
    # the WTP's alarms answered at the WTP (its trips too, through their alarms): acknowledged at its desk, looked at
    # locally with the chemical PPE on (several of them are at the dosing skids), reported; after an RO trip's own
    # task, which comes first
    task('answer_alarm_wtp', 'Answer the WTP alarm', [DESK, {'ack': '$'}] + CHEM_GEAR + [
        {'go': {'kks': '$'}}, {'work': [2, 4], 'anim': 'inspect'}, say('alarm_checked', 'shift_sup')], priority=2)
    reacts.append({'on': {'alarm': 2}, 'areas': WTP_AREAS, 'roles': ['wtp_op'], 'task': 'answer_alarm_wtp'})
    # the train's call when its demineralised water tank runs low (WATER-TREATMENT §8): the control room asks the
    # WTP for more transfer; the WTP operator starts the transfer pumps that are not running
    task('demin_transfer', 'More demineralised water to the train', [
        DESK, scr('00GHC10AP002', 'start', **{'else': 2}), scr('00GHC10AP001', 'start', **{'else': 3}),
        say('transfer_on', 'ccr_op')], priority=2)
    cr_desk = {'go': {'kind': 'desk', 'room': 'control_room'}}
    task('call_wtp_demin', 'Demineralised water low: call the WTP', [
        cr_desk, {'call': {'role': 'wtp_op', 'task': 'demin_transfer'}}, say('demin_low', 'wtp_op')], priority=2)
    task('ask_wtp_demin', 'Ask the WTP for more demineralised water', [
        cr_desk, {'call': {'role': 'wtp_op', 'task': 'demin_transfer'}}, {'work': 1}], priority=2)
    reacts.append({'on': {'value': 'dm_l'}, 'roles': ['ccr_op'], 'task': 'call_wtp_demin'})
    # the WTP's works: the WTP operator asks for the permit of a fault's work; the week's calibrations by the I&C
    # maintenance supervisor (train_staff's plan_ tasks); the equipment taken out of service for its isolation
    task('request_permit_wtp', 'Ask for a permit for the fault\'s work', [
        DESK, {'permit': {'work': '$', 'action': 'request'}}, say('request', 'shift_sup')], priority=2)
    for f, w in FAULT_WORK.items():
        reacts.append({'on': {'fault': f}, 'roles': ['wtp_op'], 'task': 'request_permit_wtp', 'work': w})
    return T, reacts


def prep(iso):
    """The steps that take an isolation's equipment out of service (the WTP operator's, from the WTP desk) before its
    points are locked: the other stream in service first. None when it needs nothing."""
    if iso.startswith('iso_ro_'):
        x = iso[7]
        n = 1 if x == 'a' else 2
        ro, oro = f'00GCB2{n}AT001', f'00GCB2{3 - n}AT001'
        return [DESK, scr(oro, 'start', **{'else': 2}), wait(f'ro_{_other(x)}_hp', 60),
                scr(ro, 'stop', **{'else': 4}), wait(f'ro_{x}_stopped', 60)]
    if iso.startswith('iso_mb_'):
        x = iso[7]
        n = 1 if x == 'a' else 2
        no = 3 - n
        return [DESK, scr(f'00GCF1{no}AT001', 'in_service', **{'else': 2}),
                scr(f'00GCK10AP00{no}', 'start', **{'else': 3}), wait(f'mb_{_other(x)}_making', 30),
                scr(f'00GCK10AP00{n}', 'stop', **{'else': 5}), scr(f'00GCF1{n}AT001', 'standby', **{'else': 6}),
                wait(f'mb_{x}_sb', 60)]
    return None


def gas_test(work):
    """A confined-space job's gas test (PLANT3D §15.2): the detector's reading at the vessel's manhole."""
    if work.startswith('wo_mb_'):
        code = f'00GCF1{1 if work[6] == "a" else 2}CQ003'
        return [_go(code), {'read': code, 'expect': [19.5, 23.5], 'tol': 0.2, 'test': 'gas'}]
    return []
