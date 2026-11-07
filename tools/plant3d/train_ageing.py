"""The first train ages (docs/plant3d/REALISM.md §4, §2.18; milestone AG2): wear items on its pumps, cooling tower
fans, CW discharge valves and a condenser pressure transmitter, each a `wear` node of its duty times the scenario's
`age_rate` (§4.3), its life a `draw` from the seed (§2.2), its early signs tables of how near its end it is (the P-F
curve: vibration first, then noise, then heat), its failure an ordinary scenario fault with `when` (§4.2) that the
staff and the trainee repair under a permit by a work that `renews` it. Seeded hazards with no sign (a CW pump's motor
protection tripping by itself) are a `draw` against the pump's running hours.

Wear is counted in equivalent hours: a wear's rate is its duty (running: 0 or 1; a valve's grease and a sensor age
whether or not they run) times `age_h` = `age_rate` / 3600, so a wear grows by one hour for every clock hour of duty
at `age_rate` 1 (real time) and by `age_rate` hours at a training rate. A life is drawn in hours from an inverse
Weibull table (ISO 281's life spread for bearings; [OREDA]-style characteristic lives), never below its floor: an item
that fails sooner is an installation fault, not wear (left to hidden causes, §2.6). Every sign that feeds a value the
train had before AG2 is 0 until the item's P point (its life less its P-F interval): below P nothing can be detected
(the P-F curve's definition, [Moubray]), and so every run before AG2 keeps its values bit for bit.

Every number is invented, round and plausible for the class of machine, from public sources: ISO 281 (bearing life,
Weibull slope 1.5), ISO 20816-3 (vibration zones), IEEE 493 (motor and protection failure rates), [OREDA] public
summaries (pumps' critical failure modes: vibration, noise, overheating), [CTI] (cooling tower gear reducers), US NRC
Generic Letter 89-10 and [MOV-diag] (a valve actuator's running torque rising as its grease and packing age), [R3051]
(a transmitter's stability)."""
import math

# ------------------------------------------------------------------------------------------------ the item kinds
# eta: the characteristic life (h); beta: the Weibull slope; pf: the P-F interval (h, the signs before the failure);
# floor: no life drawn below it (h); every one in equivalent hours of the item's duty
KINDS = {
    # a large motor's rolling bearings (ISO 281: slope 1.5; API 610 asks an L10 of 25,000 h at the rated point, the
    # motors' lives in service are longer): the vibration first, then the noise, the heat last (ISO 17359)
    'bearing': {'eta': 50000, 'beta': 1.5, 'pf': 3000, 'floor': 7500},
    # a cooling tower fan's right-angle gear reducer (CTI: ten years and more with its oil changed): the gear mesh's
    # vibration on the fan's own probe, a gear whine
    'gearbox': {'eta': 60000, 'beta': 1.8, 'pf': 4000, 'floor': 10000},
    # a motor-operated valve's actuator: its grease hardens and the stem packing dries with the years whether it moves
    # or not (NRC GL 89-10, 96-05: the periodic torque checks); the running torque rises until the torque switch stops
    # it mid-stroke (the valve stays where it is)
    'actuator': {'eta': 35000, 'beta': 2.5, 'pf': 4000, 'floor': 10000},
    # a motor protection relay's spurious trip (with its wiring and CT circuits): no sign, the hazard of a constant
    # rate (exponential, IEEE 493's order of magnitude for protection)
    'relay': {'eta': 200000, 'beta': 1.0, 'pf': 0, 'floor': 5000},
}
ROWS = [0, 0.02, 0.05, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 0.95, 0.99, 1.0]
U_TOP = 0.995           # the table's last row: the 99.5 % life (no table reaches an infinite life)


def life_table(kind):
    """The inverse Weibull distribution of a kind's life (h), u → life, at ROWS, never below the floor."""
    k = KINDS[kind]
    out = []
    for u in ROWS:
        t = k['eta'] * (-math.log(1 - min(u, U_TOP))) ** (1 / k['beta'])
        out.append([u, round(max(k['floor'], t))])
    return out


# The training rates (§4.3, the user 2026-11-01: a training rate per scenario, real rates available, the trainee
# doesn't pick it): the scenarios that teach operating age gently (a bearing's P-F interval lasts 30 clock hours, two
# and a half shifts); the ageing scenario at a rate where an item near its end shows its signs within a shift (10)
RATE = 100
RATES = {'shift_aged': 300}
# The months since the overhaul (world.age, read by this tool only): the cold start after the long outage and the
# scenarios made from it start with the plant overhauled; the hot restart two months on
AGES = {'hot_restart': 2}
HOURS_A_MONTH = 730

# ------------------------------------------------------------------------------------------------ the items
# (prefix, motor code, its vibration probe, model area, running value, speed value, motor fault state, isolation,
#  name, ISO 20816-3 group (1: above 300 kW, 2: 15-300 kW), the share of the months it runs)
PUMPS = [
    ('cw_a', '30PAC10AP001', '30PAC10CY001', 'cw', 'cw_a_run', 'cw_a_spd', 'cw_a_fault', 'iso_cw_a', 'CW pump A', 1, 2 / 3),
    ('cw_b', '30PAC10AP002', '30PAC10CY002', 'cw', 'cw_b_run', 'cw_b_spd', 'cw_b_fault', 'iso_cw_b', 'CW pump B', 1, 2 / 3),
    ('cw_c', '30PAC10AP003', '30PAC10CY003', 'cw', 'cw_c_run', 'cw_c_spd', 'cw_c_fault', 'iso_cw_c', 'CW pump C', 1, 2 / 3),
    ('ccw_a', '00PGC10AP001', '00PGC10CY001', 'bop', 'ccw_a_run', 'ccw_a_run', 'ccw_a_fault', 'iso_ccw_a',
     'Closed cooling water pump A', 2, 1 / 2),
    ('ccw_b', '00PGC10AP002', '00PGC10CY002', 'bop', 'ccw_b_run', 'ccw_b_run', 'ccw_b_fault', 'iso_ccw_b',
     'Closed cooling water pump B', 2, 1 / 2),
    ('cep_a', '30LCB10AP001', '30LCB10CY001', 'st', 'cep_a_run', 'cep_a_spd', 'cep_a_fault', 'iso_cep_a',
     'Condensate extraction pump A', 2, 1 / 2),
    ('cep_b', '30LCB10AP002', '30LCB10CY002', 'st', 'cep_b_run', 'cep_b_spd', 'cep_b_fault', 'iso_cep_b',
     'Condensate extraction pump B', 2, 1 / 2),
]
FANS = range(1, 11)
FAN_DUTY = 0.8                  # eight fans of ten run in the hot months
VALVES = [('a', 1), ('b', 2), ('c', 3)]
RELAYS = ['cw_a', 'cw_b', 'cw_c']
# ISO 20816-3, rigid foundations, mm/s r.m.s.: a machine in service (zone A/B), the zone C/D boundary (damage)
ZONES = {1: {'base': 1.8, 'cd': 7.1, 'end': 11}, 2: {'base': 1.2, 'cd': 4.5, 'end': 7.1}}
BRG_RISE, BRG_RISE_END, BRG_T_H = 25, 60, 90     # K over the air running; K at the failure; the alarm's °C
BRG_TAU = 600                   # s (model time): a bearing housing's heat
GBX_END = 9                     # mm/s added on the fan's probe by a gearbox at its end
TQ_BASE, TQ_END = 55, 100       # % of the torque switch's setting: a sound actuator's running torque; at the trip
DRIFT_FROM, DRIFT_SPAN, DRIFT_KPA = 8760, 26280, 2.0   # h: a transmitter within its spec for a year; 2 kPa at three


def shared(m):
    """`age_h` (bop, the first area): the hours of wear a clock second of duty adds."""
    m.prod('age_h', ['age_rate', round(1 / 3600, 15)], 'h/s')


def _item(m, p, kind, rate):
    """The wear, its drawn life and the margin to the end (h: below 0 while it lasts), for one item: the model's
    workings, without a code, so no screen shows them (a trainee is never told a failure is coming, §4.3)."""
    k = KINDS[kind]
    w = m.v(f'{p}_wear', {'wear': rate, 'max': 1000000}, 'h')
    life = m.v(f'{p}_life', {'draw': life_table(kind)}, 'h')
    if k['pf']:
        m.diff(f'{p}_mgn', w, life, 'h')
    return w, life


def pump(m, item):
    """A pump motor's bearings (§4.2): wear by running hours; its vibration on the probe (from zone A/B to beyond
    C/D in the P-F interval), the bearing temperature (its rise over the air, the heat coming last), the alarms at the
    zone C/D boundary and at 90 °C (advisory, priority 3), the noise and shake at the probe."""
    p, code, cy, _, run, spd, _, _, title, group, _ = item
    pf = KINDS['bearing']['pf']
    z = ZONES[group]
    b = f'{p}_brg'
    rate = m.prod(f'{b}_rate', [run, 'age_h'], 'h/s')
    _item(m, b, 'bearing', rate)
    m.tab(f'{p}_vib_k', f'{b}_mgn', [[-pf, z['base']], [-0.6 * pf, z['base'] * 1.6], [-0.3 * pf, z['cd'] * 0.75],
                                     [0, z['end']]], 'mm/s')
    m.prod(f'{p}_vib', [spd, f'{p}_vib_k'], 'mm/s', cy)
    m.tab(f'{b}_tk', f'{b}_mgn', [[-0.25 * pf, BRG_RISE], [0, BRG_RISE_END]], 'K')
    m.prod(f'{b}_rise', [spd, f'{b}_tk'], 'K')
    m.lag(f'{b}_rise_l', f'{b}_rise', BRG_TAU, unit='K')
    m.sum(f'{b}_t', ['ambient_t', f'{b}_rise_l'], '°C', code)
    m.cmp(f'{p}_vib_h', f'{p}_vib', '>', z['cd'])
    m.cmp(f'{b}_t_h', f'{b}_t', '>', BRG_T_H)
    m.alarm(f'{p}_vib_high', cy, f'{title} motor vibration high', f'{p}_vib_h', 3, code, 'VAH')
    m.alarm(f'{p}_brg_t_high', code, f'{title} motor bearing temperature high', f'{b}_t_h', 3, None, 'TAH')
    m.b(kks=cy, show=f'{p}_vib')
    m.b(kks=cy, shake=f'{p}_vib', scale=0.02)
    # the noise: nothing in zone A/B, rising through C, full beyond C/D
    m.b(kks=cy, sound='bearing_noise', gain={'of': f'{p}_vib', 'table': [[z['base'] * 1.6, 0], [z['cd'], 0.6],
                                                                         [z['end'], 1]]})


def relay(m, p):
    """A CW pump's motor protection tripping by itself (§4.2's seeded hazard): its running hours against a drawn
    life; no sign before it."""
    _item(m, f'{p}_rly', 'relay', f'{p}_brg_rate')


def fan(m, i):
    """A fan's gear reducer: the gear mesh's vibration added to the fan's own (the existing value
    ct_fan{i}_vft, the blades' share, plus this: 0 until the P point). Returns the value the fan's vibration target
    multiplies by its speed."""
    p = f'ct_fan{i}_gbx'
    pf = KINDS['gearbox']['pf']
    rate = m.prod(f'{p}_rate', [f'ct_fan{i}_cmd', 'age_h'], 'h/s')
    _item(m, p, 'gearbox', rate)
    m.tab(f'{p}_x', f'{p}_mgn', [[-pf, 0], [-0.5 * pf, 2.5], [0, GBX_END]], 'mm/s')
    return m.sum(f'ct_fan{i}_vfs', [f'ct_fan{i}_vft', f'{p}_x'], 'mm/s')


def fan_parts(m, i):
    """The fan's advisory alarm (ISO 20816-3 zone C, the trip stays at 10 mm/s) and the gear whine at its probe."""
    cy = f'30PAD10CY{i:03d}'
    m.cmp(f'ct_fan{i}_vib_h', f'ct_fan{i}_vib', '>', 6.3)
    m.alarm(f'ct_fan{i}_vib_high', cy, f'Cooling tower fan {i} vibration high', f'ct_fan{i}_vib_h', 3,
            f'30PAD10AN{i:03d}', 'VAH')
    m.b(kks=cy, sound='gear_whine', gain={'of': f'ct_fan{i}_vib', 'table': [[3.5, 0], [6.3, 0.6], [10, 1]]})


def valve(m, x, n):
    """A CW pump discharge valve's actuator: its grease and packing age by the calendar; its running torque (shown
    while it strokes, % of the torque switch's setting) rises over the P-F interval; at the end the torque switch
    stops it for good (the actuator fault, `cw_{x}_v_stuck`)."""
    p = f'cw_{x}_act'
    pf = KINDS['actuator']['pf']
    aa = f'30PAC10AA10{n}'
    _item(m, p, 'actuator', 'age_h')
    m.tab(f'{p}_mv', f'cw_{x}_v_m_mv', [[-1, 1], [0, 0], [1, 1]])
    m.tab(f'{p}_tk', f'{p}_mgn', [[-pf, TQ_BASE], [-0.5 * pf, 70], [0, TQ_END]], '%')
    m.prod(f'{p}_tq', [f'{p}_mv', f'{p}_tk'], '%', aa)


def drift_values(m):
    """Condenser pressure transmitter 3's sensor drifts with the time since its calibration (§4.2), its direction
    drawn: nothing within its spec for a year, then up to 2 kPa at three ([R3051]'s stability, far exceeded:
    a training figure). Added to the transmitter's own value (0 until a year: every earlier value stays)."""
    p = 'cond_p3_age'
    m.v(f'{p}_w', {'wear': 'age_h', 'max': 1000000}, 'h')
    m.v(f'{p}_dir', {'draw': [[0, -1], [0.5, -1], [0.5, 1], [1, 1]]})
    m.tab(f'{p}_mag', f'{p}_w', [[DRIFT_FROM, 0], [DRIFT_SPAN, DRIFT_KPA]], 'kPa')
    return m.prod(p, [f'{p}_dir', f'{p}_mag'], 'kPa')


# ------------------------------------------------------------------------------------------------ permits and works
def _safe(m, s, cmd, spd):
    m.NOT(f'{s}_nocmd', cmd)
    m.cmp(f'{s}_still', spd, '<', 0.01)
    return m.AND(f'{s}_safe', [f'{s}_nocmd', f'{s}_still'])


def works(m):
    """The isolations and works of the items in this area (PLANT3D §15): each failure's corrective work, renewing
    the item; the works already there that renew one (a CW pump motor's bearing replacement, fan 3's service, the
    transmitter's calibration) gain its `renews`."""
    add = []
    for item in PUMPS:
        p, code, _, area, _, spd, fault, iso, title, _, _ = item
        if area != m.area:
            continue
        if p.startswith('cep'):     # the condensate pumps: their motors' supply
            m.interlock(f'{p}_prot', fault, [{'set': {f'{p}_cmd': 0}}], code,
                        f'{title}: the motor protection stops it')
            _safe(m, p, f'{p}_cmd', spd)
            m.isolation(iso, f'{title}: motor supply',
                        [(code, 'electrical', f'{p}_safe', 'Pump stopped; its breaker racked out, locked and tagged')])
        add.append((f'wo_{p}_brg', code, f'{title}: replace the motor bearings', 'mech', 'general', iso,
                    f'{p}_brg', [f'{p}_brg_wear']))
        if p in RELAYS:
            add.append((f'wo_{p}_rly', code, f'{title}: test the motor protection and replace its relay', 'elec',
                        'electrical', iso, f'{p}_rly', [f'{p}_rly_wear']))
    if m.area == 'ct':
        for i in FANS:
            code = f'30PAD10AN{i:03d}'
            if i not in (3, 4):
                _safe(m, f'ct_fan{i}', f'ct_fan{i}_cmd', f'ct_fan{i}_spd')
                m.isolation(f'iso_ct_fan{i}', f'Cooling tower fan {i}: motor supply',
                            [(code, 'electrical', f'ct_fan{i}_safe',
                              'Fan stopped; its breaker racked out, locked and tagged')])
            add.append((f'wo_ct_fan{i}_gbx', code, f'Cooling tower fan {i}: overhaul the gear reducer', 'mech',
                        'general', f'iso_ct_fan{i}', f'ct_fan{i}_gbx', [f'ct_fan{i}_gbx_wear']))
    if m.area == 'cw':
        for x, n in VALVES:
            aa = f'30PAC10AA10{n}'
            m.isolation(f'iso_cw_{x}_act', f'CW pump {x.upper()} discharge valve actuator: its supply',
                        [(aa, 'electrical', None, 'Actuator supply isolated, locked and tagged; the valve stays where '
                                                  'it stands')])
            add.append((f'wo_cw_{x}_act', aa, f'CW pump {x.upper()} discharge valve: overhaul the actuator, regrease '
                        'and repack the stem', 'mech', 'general', f'iso_cw_{x}_act', f'cw_{x}_act',
                        [f'cw_{x}_act_wear']))
    for wid, code, title, disc, permit, iso, fault, renews in add:
        m.work(wid, code, title, disc, permit, iso, fault)
        m.works[-1]['renews'] = renews
    renew = {**{f'wo_cw_{x}_motor': [f'cw_{x}_brg_wear'] for x, _ in VALVES}, 'wo_ct_fan3': ['ct_fan3_gbx_wear'],
             'wo_cond_p3_cal': ['cond_p3_age_w']}
    for w in m.works:
        if w['id'] in renew:
            w['renews'] = renew[w['id']]


def fault_work():
    """{fault id: its work} for the staff (train_staff.FAULT_WORK): the supervisor asks for the permit."""
    out = {f'{p[0]}_brg': f'wo_{p[0]}_brg' for p in PUMPS}
    out.update({f'{p}_rly': f'wo_{p}_rly' for p in RELAYS})
    out.update({f'ct_fan{i}_gbx': f'wo_ct_fan{i}_gbx' for i in FANS})
    out.update({f'cw_{x}_act': f'wo_cw_{x}_act' for x, _ in VALVES})
    return out


def faults():
    """The failures (§4.2): ordinary scenario faults, each made when its item's wear reaches its life."""
    out = []
    for p, code, _, _, _, _, fault, _, title, _, _ in PUMPS:
        out.append({'id': f'{p}_brg', 'when': {'cmp': [f'{p}_brg_mgn', '>=', 0]}, 'set': {fault: 1},
                    'text': f'{title}: a motor bearing fails (it seizes): the motor trips', 'kks': code,
                    'repair': {fault: 0}})
    for p in RELAYS:
        it = next(i for i in PUMPS if i[0] == p)
        out.append({'id': f'{p}_rly', 'when': {'cmp': [f'{p}_rly_wear', '>=', f'{p}_rly_life']}, 'set': {it[6]: 1},
                    'text': f'{it[8]}: the motor protection trips by itself', 'kks': it[1], 'repair': {it[6]: 0}})
    for i in FANS:
        out.append({'id': f'ct_fan{i}_gbx', 'when': {'cmp': [f'ct_fan{i}_gbx_mgn', '>=', 0]},
                    'set': {f'ct_fan{i}_vfault': 1}, 'text': f'Cooling tower fan {i}: the gear reducer fails',
                    'kks': f'30PAD10AN{i:03d}', 'repair': {f'ct_fan{i}_vfault': 0}})
    for x, n in VALVES:
        out.append({'id': f'cw_{x}_act', 'when': {'cmp': [f'cw_{x}_act_mgn', '>=', 0]}, 'set': {f'cw_{x}_v_stuck': 1},
                    'text': f'CW pump {x.upper()} discharge valve: the actuator\'s torque switch stops it for good',
                    'kks': f'30PAC10AA10{n}', 'repair': {f'cw_{x}_v_stuck': 0}})
    return out


# ------------------------------------------------------------------------------------------------ the scenarios' ages
def items():
    """[(wear value, life value or None, months' duty share)] of every wear item: the ones whose wear a scenario's
    age starts."""
    out = [(f'{p[0]}_brg_wear', f'{p[0]}_brg_life', p[10]) for p in PUMPS]
    out += [(f'{p}_rly_wear', f'{p}_rly_life', next(i[10] for i in PUMPS if i[0] == p)) for p in RELAYS]
    out += [(f'ct_fan{i}_gbx_wear', f'ct_fan{i}_gbx_life', FAN_DUTY) for i in FANS]
    out += [(f'cw_{x}_act_wear', f'cw_{x}_act_life', 1) for x, _ in VALVES]
    out.append(('cond_p3_age_w', None, 1))
    return out


def life_of(seed, life):
    """The life the engine draws at step 0 for this seed (REALISM.md §2.2: the stream of purpose `draw` named by the
    value), so the age can skip the items that would have failed and been renewed meanwhile."""
    from ref.plant3d_world import TAGS, stream
    from ref.plant3d_staff import draw
    from ref.plant3d import table_at
    kind = next(k for k, pre in (('bearing', '_brg_'), ('relay', '_rly_'), ('gearbox', '_gbx_'), ('actuator', '_act_'))
                if pre in life)
    _, r = draw(stream(seed, TAGS['draw'], life))
    return float(table_at(life_table(kind), r / 16777216.0))


def apply(sc):
    """A scenario's training rate and age (§4.3): `age_rate` in its init, `world.age`, and each item's wear from the
    months since the overhaul by its duty. An item the months take past its drawn life failed and was renewed
    meanwhile: it starts at what is left over (the same life again: renewal theory's simplest form)."""
    from ref.plant3d_world import world_seed
    sid = sc['id']
    months = {'shift_aged': AGED_MONTHS, **AGES}.get(sid, 0)
    sc['init']['age_rate'] = RATES.get(sid, RATE)
    if 'world' in sc:
        sc['world'] = dict(sc['world'], age={'months': months})
    seed = world_seed(sc)
    for wear, life, duty in items():
        h = months * HOURS_A_MONTH * duty
        if life:
            h = math.fmod(h, life_of(seed, life))
        if h > 0:
            sc['init'][wear] = round(h, 3)
    return sc


# The ageing scenario (§4.1): the day shift with the plant cold but its closed cooling water in service, the plant
# AGED months after its overhaul; its seed (the lives drawn) and the months are chosen so that closed cooling water
# pump A shows its bearing's signs from the start and fails in the day shift's first hours, and nothing else has
# failed or fails in the day (tests/test_plant3d_ageing.py checks it)
AGED_SEED = 663
AGED_MONTHS = 30


def aged_scenario(cold):
    """`shift_aged` from shift_cold (train_staff.scenario): pump A of the closed cooling water running."""
    s = dict(cold)
    s['id'] = 'shift_aged'
    s['title'] = f'Day shift {AGED_MONTHS} months after the overhaul: the plant\'s wear to find (choose a role)'
    s['init'] = dict(s['init'], ccw_a_cmd=1)
    s['world'] = dict(s['world'], seed=AGED_SEED)
    return s
