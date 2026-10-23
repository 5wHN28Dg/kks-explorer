"""The water treatment plant's behaviour model (docs/plant3d/WATER-TREATMENT.md §5–§8 → docs/PLANT3D.md §7), milestone
W2: the intake, coagulation and the clarifiers, the gravity filters and their backwash, the filtered water tank and
its pumps, dechlorination and the cartridge filters, two RO trains, the degasser, the mixed beds, the demineralised
water tanks and the transfer to the first train, the neutralisation pit and the sludge thickener; with their
operations, interlocks, sequences, trips and alarms, and the ties to the first train (§8).

Faked and reduced (R6), as the train's model: the direction, order of magnitude and time scale of what a trainee can
cause. Every number is invented, round and plausible for the class of plant; WATER-TREATMENT.md §1–§3 give the sources
of the ranges, and the comments here say which number comes from where.

**Two speeds** (WATER-TREATMENT.md §5): pumps, pressures and flows move in model time like the train's; the
inventories that take hours or days on site (tank levels, a filter's head loss, the membranes' fouling, a mixed bed's
exhaustion, the thickener) move at clock rates: their gains are multiplied by the clock's `day_scale` (DAY), so a
mixed bed runs about three clock days. Sequence times (a backwash, an RO flush) are clock times divided by DAY. Flows
are in m³/h of the clock on the WTP's side; the plant's demin tank and the cooling tower basin keep the train's model
rates (§5 "Where the two speeds meet")."""
from train_model import M

DAY = 6                     # PLANT3D §16.1 `day_scale`: plant.json's clock when it has one (staff, milestone S1)


def clock_gain(volume_m3):
    """The gain of a level in % of a tank of `volume_m3`, fed in m³/h of the clock: per second of model time."""
    return round(DAY * 100 / (3600 * volume_m3), 12)


def clock_s(minutes):
    """A clock duration in minutes as seconds of model time."""
    return round(minutes * 60 / DAY, 1)


# design values (WATER-TREATMENT §2–§3)
RAW = [[0, 0], [1, 550], [2, 1050], [3, 1500]]      # raw water flow, m³/h, by the pumps running (3 × 50 %)
FILTERED_TANK = 1000        # m³
DEGASSED_TANK = 100         # m³ (ours)
DEMIN_TANK = 1500           # m³ each, two
PLANT_DEMIN_TANK = 300      # m³: the first train's own tank 00GHC10BB001 (ours), at the train's model rate
PIT = 200                   # m³, the neutralisation pit (ours)
RO_FEED, RO_PERM = 53, 40   # m³/h per train: 75 % recovery
MB_FLOW = 40                # m³/h per mixed bed
TRANSFER = 40               # m³/h per transfer pump
BACKWASH = 1440             # m³/h of water at 45 m/h over a 32 m² cell
MAKEUP_PUMP = 900           # m³/h, one makeup pump (the basin's valve passes 800 at most)

FILTERS = range(1, 7)
FILTER_INIT = {1: 1.4, 2: 0.6, 3: 1.0, 4: 0.8, 5: 1.2, 6: 0.3}      # head loss, m: staggered, as filters wash in turn
F_STATES = ['service', 'drain', 'air', 'air_water', 'rinse']
F_TIMES = [10, 3, 5, 10]    # clock minutes of drain, air scour, air and water, rinse ([10SS] §4.3.1: water 10 min)
RO_STATES = ['stopped', 'flushing', 'starting', 'service', 'stopping']
MB_STATES = ['service', 'recirc', 'standby']

# what the scenarios that start with the WTP stopped (wtp_cold) put in: everything stopped, tanks at 60 %
COLD_WTP = {'rw_a_cmd': 0, 'rw_b_cmd': 0, 'rw_a_spd': 0, 'rw_b_spd': 0, 'hy_a_cmd': 0, 'wt_raw': 0,
            'mx_cmd': 0, 'cg_a_cmd': 0, 'pl_a_cmd': 0, 'mk_a_cmd': 0, 'sw_a_cmd': 0, 'sw_a_p': 0,
            'mk_a_p': 0, 'sbs_a_cmd': 0, 'as_a_cmd': 0, 'ac_a_cmd': 0, 'ro_a_park': 1, 'ro_a_hp': 0, 'ro_a_dump': 1,
            'ro_a_spd': 0, 'ro_a_p': 0, 'ro_a_feedv': 0, 'ro_a_concv': 0, 'ro_a_su': 0, 'cf_a_dp': 0,
            'ct_mk_sup': 0, 'dg_cmd': 0, 'dg_co2': 40,
            'mf_a_cmd': 0, 'mf_a_spd': 0, 'tr_a_cmd': 0, 'tr_a_spd': 0, 'fp_cmd': 0, 'wt_hy': 0, 'cl_ntu': 1,
            'ft_lvl': 60, 'dg_lvl': 60, 'dt_a_lvl': 60, 'dt_b_lvl': 60, 'cg_lvl': 60, 'dm_lvl': 60, 'dm_in': 0}

FAULTS = [  # trainer faults (WATER-TREATMENT §7), each repaired at its equipment
    ('rw_a_motor', {'rw_a_fault': 1}, 'Raw water pump A motor overload'),
    ('rw_b_motor', {'rw_b_fault': 1}, 'Raw water pump B motor overload'),
    ('rw_c_motor', {'rw_c_fault': 1}, 'Raw water pump C motor overload'),
    ('screen_clog', {'rw_clog': 1}, 'Band screens blocked by debris (the intake level falls)'),
    ('coag_pump', {'cg_a_fault': 1}, 'Coagulant dosing pump A fails'),
    ('sbs_pump', {'sbs_a_fault': 1}, 'Sodium bisulphite dosing pump A fails: chlorine reaches the RO'),
    ('cart_a_clog', {'cf_a_clog': 1}, 'Cartridge filter A clogging (the RO A suction pressure falls)'),
    ('cart_b_clog', {'cf_b_clog': 1}, 'Cartridge filter B clogging (the RO B suction pressure falls)'),
    ('ro_a_conc_stuck', {'ro_a_conc_fault': 1}, 'RO A concentrate valve stuck nearly closed'),
    ('ro_b_conc_stuck', {'ro_b_conc_fault': 1}, 'RO B concentrate valve stuck nearly closed'),
    ('ro_a_oring', {'ro_a_leak': 1}, 'RO A: a leaking interconnector O-ring (salt passes into the permeate)'),
    ('ro_b_oring', {'ro_b_leak': 1}, 'RO B: a leaking interconnector O-ring (salt passes into the permeate)'),
    ('ro_a_fouling', {'ro_a_fast': 1}, 'RO A fouls fast (a colloid upset upstream): cleaning due early'),
    ('mb_a_early', {'mb_a_fast': 1}, 'Mixed bed A exhausts early (silica breaks through first)'),
    ('mb_b_early', {'mb_b_fast': 1}, 'Mixed bed B exhausts early (silica breaks through first)'),
    ('dt_drain', {'dt_drain': 1}, 'A demineralised water tank drain valve left open'),
    ('tr_a_motor', {'tr_a_fault': 1}, 'Demineralised water transfer pump A motor overload'),
    ('tr_b_motor', {'tr_b_fault': 1}, 'Demineralised water transfer pump B motor overload'),
    ('nr_ph_drift', {'nr_drift': 1}, 'Neutralisation pit pH probe drifts low'),
    ('dm_drain', {'dm_drain': 1}, 'The plant\'s demineralised water tank drain valve left open'),
]


def bop_tie(m):
    """In the first train's bop model (before the steam turbine's area): the plant's demineralised water tank
    00GHC10BB001, at the train's model rate (WATER-TREATMENT §8). Filled by the WTP's transfer pumps, drawn by the
    hotwell makeup (st: hw_mk, kg/s) and the HRSG's continuous losses while it makes steam (blowdown, sampling: ~8 m³/h,
    1–2 % of its steam, §2). Read through lags: those values come later in the joined model (PLANT3D §7.1)."""
    m.state('dm_drain', 0, '00GHC10BB001')
    m.lag('dm_in', 'tr_q', 10, init=TRANSFER, unit='m³/h')
    m.lag('dm_hw', 'hw_mk', 1)
    m.lag('dm_gen', 'hp_gen', 1)
    m.cmp('dm_hrsg_on', 'dm_gen', '>', 1)
    m.prod('dm_loss', ['dm_hrsg_on', 8])
    m.prod('dm_hw_q', ['dm_hw', 3.6])
    m.prod('dm_drain_q', ['dm_drain', 300])
    m.sum('dm_out', ['dm_hw_q', 'dm_loss', 'dm_drain_q'], 'm³/h')
    m.diff('dm_net', 'dm_in', 'dm_out')
    m.integ('dm_lvl', 'dm_net', round(100 / (3600 * PLANT_DEMIN_TANK), 12), 0, 100, 80, '%', '00GHC10BB001')
    m.cmp('dm_ok', 'dm_lvl', '>', 3)
    m.cmp('dm_l', 'dm_lvl', '<', 30)
    m.cmp('dm_lc', 'dm_lvl', '>', 35)
    m.alarm('dm_low', '00GHC10BB001', 'Demineralised water tank low (makeup from the water treatment plant)', 'dm_l', 2,
            isa='LAL', clear='dm_lc')
    m.b(kks='00GHC10BB001', show='dm_lvl')


def drive(m, name, kks, init, fault=False):
    m.state(f'{name}_cmd', init, kks)
    if fault:
        m.state(f'{name}_fault', 0, kks)


def intake():
    """The intake (WATER-TREATMENT §3 #1–2): screens, three raw water pumps 3 × 50 %, pre-chlorination."""
    m = M('intake')
    for x, init in (('a', 1), ('b', 1), ('c', 0)):
        drive(m, f'rw_{x}', f'00GAF10AP00{"abc".index(x) + 1}', init, True)
    m.state('rw_clog', 0, '00GAA10AT002')
    drive(m, 'hy_a', '00GBN30AP001', 1)
    drive(m, 'hy_b', '00GBN30AP002', 0)
    for x, init in (('a', 1), ('b', 1), ('c', 0)):
        m.drive_values(f'rw_{x}')
        m.lag(f'rw_{x}_spd', f'rw_{x}_run', 4, init=init, unit='pu')
    m.sum('rw_n', ['rw_a_spd', 'rw_b_spd', 'rw_c_spd'])
    m.tab('rw_flow', 'rw_n', RAW, 'm³/h', '00GAC10BR010')
    # the band screens pass 2,000 m³/h clean, 600 blocked: the wet well is drawn down by what they can't pass
    m.tab('rw_scr_cap', 'rw_clog', [[0, 2000], [1, 600]])
    m.diff('rw_excess', 'rw_flow', 'rw_scr_cap')
    m.tab('rw_lvl_sp', 'rw_excess', [[0, 0], [600, -2.5]])
    m.lag('rw_lvl', 'rw_lvl_sp', 90, unit='m', kks='00GAA10CL001')
    m.cmp('rw_l', 'rw_lvl', '<', -1.0)
    m.cmp('rw_ll', 'rw_lvl', '<', -1.5)
    m.cmp('rw_lvl_ok', 'rw_lvl', '>=', -0.8)
    for x in 'abc':
        m.AND(f'rw_{x}_ll_c', ['rw_ll', f'rw_{x}_cmd'])
        m.AND(f'rw_{x}_ol_c', [f'rw_{x}_cmd', f'rw_{x}_fault'])
    # pre-chlorination, 1.5 mg/L while the raw water flows (§3 #2): the dosing pumps dose only with the flow
    m.OR('hy_run', ['hy_a_cmd', 'hy_b_cmd'])
    m.cmp('hy_flow', 'rw_flow', '>=', 100)
    m.AND('hy_on', ['hy_run', 'hy_flow'])
    m.prod('hy_dose', ['hy_on', 1.5], 'mg/L', '00GBN30BB001')
    for x, n in (('a', 1), ('b', 2), ('c', 3)):
        code = f'00GAF10AP00{n}'
        m.start_stop(code, f'rw_{x}', [('rw_lvl_ok', 'Intake level low: the pump would draw air')])
        m.trip(f'rw_{x}_trip_ll', code, f'Raw water pump {x.upper()}: intake level low-low', f'rw_{x}_ll_c',
               [{'set': {f'rw_{x}_cmd': 0}}], 'LALL', 2, 'rw')
        m.trip(f'rw_{x}_trip_ol', code, f'Raw water pump {x.upper()}: motor overload', f'rw_{x}_ol_c',
               [{'set': {f'rw_{x}_cmd': 0}}], None, 0.5, 'rw')
        m.alarm(f'rw_{x}_tripped', code, f'Raw water pump {x.upper()} tripped', f'rw_{x}_trip_ol_latched', 2)
    for x, n in (('a', 1), ('b', 2)):
        m.start_stop(f'00GBN30AP00{n}', f'hy_{x}', ok=False)
    m.alarm('rw_lvl_low', '00GAA10CL001', 'Intake level low', 'rw_l', 2, isa='LAL', clear='rw_lvl_ok')
    m.alarm('rw_lvl_ll', '00GAA10CL001', 'Intake level low-low (raw water pumps trip)', 'rw_ll', 1, isa='LALL')
    for x, n in (('a', 1), ('b', 2), ('c', 3)):
        code = f'00GAF10AP00{n}'
        m.b(kks=code, anim='shaft', of=f'rw_{x}_spd', scale=24.7)
        m.b(kks=code, sound='motor_small', gain={'of': f'rw_{x}_spd', 'table': [[0, 0], [1, 0.8]]})
        m.b(kks=code, lamp='running', of=f'rw_{x}_run')
        m.b(kks=f'00GAF10AA10{n}', anim='disc', of=f'rw_{x}_spd')      # the discharge valve opens with its pump
        m.b(kks=f'00GAF10CP50{n}', show=f'rw_{x}_spd')
    m.b(kks='00GAA10CL001', show='rw_lvl')
    for x, n in (('a', 1), ('b', 2)):
        m.b(kks=f'00GBN30AP00{n}', lamp='running', of=f'hy_{x}_cmd')
    return m


def wtp():
    m = M('wtp')
    # ---------------------------------------------------------------- states (the operable things and the faults)
    drive(m, 'mx', '00GBD10AM001', 1)
    for x, n, init in (('a', 1, 1), ('b', 2, 0)):
        drive(m, f'cg_{x}', f'00GBN10AP00{n}', init)
        drive(m, f'pl_{x}', f'00GBN20AP00{n}', init)
    m.state('cg_a_fault', 0, '00GBN10AP001')
    m.state('cg_dose_sp', 30, '00GBN10BB001', 'mg/L')        # the season's jar-test dose (§3 #3: 20–80 mg/L)
    m.state('cg_filling', 0, '00GBN10BB001')
    m.state('cla_cmd', 1, '00GBD11AT001')
    m.state('clb_cmd', 1, '00GBD12AT001')
    m.state('bw_air', 0, '00GBR10AN001')
    m.state('bw_water', 0, '00GBR10AP001')
    for x, n, init in (('a', 1, 1), ('b', 2, 0)):
        drive(m, f'mk_{x}', f'00GHB10AP00{n}', init)
        drive(m, f'sw_{x}', f'00GHA10AP00{n}', init)
        drive(m, f'sbs_{x}', f'00GCN10AP00{n}', init)
        drive(m, f'as_{x}', f'00GCN20AP00{n}', init)
        drive(m, f'ac_{x}', f'00GCE10AP00{n}', init)
        drive(m, f'mf_{x}', f'00GCK10AP00{n}', init)
        drive(m, f'tr_{x}', f'00GHC10AP00{n}', init, True)
        drive(m, f'nr_{x}', f'00GNR10AP00{n}', 0)
    m.state('sbs_a_fault', 0, '00GCN10AP001')
    for x, n in (('a', 1), ('b', 2)):
        m.state(f'cf_{x}_clog', 0, f'00GCB1{n}AT001')
        ro = f'00GCB2{n}AT001'
        for s, init in (('hp', 1 if x == 'a' else 0), ('flush', 0), ('dump', 0 if x == 'a' else 1), ('bad', 0),
                        ('park', 0), ('leak', 0), ('fast', 0)):
            m.state(f'ro_{x}_{s}', init, ro)
        m.state(f'ro_{x}_conc_fault', 0, f'00GCB2{n}AA301')
        m.state(f'mb_{x}_fast', 0, f'00GCF1{n}AT001')
    drive(m, 'dg', '00GCH10AN001', 1)
    m.state('dt_drain', 0, '00GCL10BB001')
    drive(m, 'nr_mix', '00GNR10AM001', 1)
    m.state('nr_drift', 0, '00GNR10CQ001')
    drive(m, 'fp', '00GBS20AT001', 1)

    # ---------------------------------------------------------------- the inventories (clock rate, §5): stateful, so
    # they stand first and read their flows as the previous step left them
    m.integ('cg_lvl', 'cg_net', round(DAY / 3600, 12), 0, 100, 70, '%', '00GBN10BB001')
    m.integ('dg_lvl', 'dg_net', clock_gain(DEGASSED_TANK), 0, 100, 60, '%', '00GCK10BB001')
    m.integ('ft_lvl', 'ft_net', clock_gain(FILTERED_TANK), 0, 90, 90, '%', '00GBL10CL001')
    m.integ('nr_lvl', 'nr_net', clock_gain(PIT), 0, 100, 40, '%', '00GNR10BB001')
    # the thickener: 10 % of its volume a clock hour at the design's sludge (in units of it)
    m.integ('th_lvl', 'th_bal', round(DAY * 10 / 3600, 12), 0, 100, 32.5, '%', '00GBS10AT001')
    for x, n in (('a', 1), ('b', 2)):
        m.integ(f'dt_{x}_lvl', f'dt_{x}_net', clock_gain(DEMIN_TANK), 0, 100, 70, '%', f'00GCL10CL00{n}')

    # ---------------------------------------------------------------- coagulation and the clarifiers (§3 #3–4)
    m.lag('wt_raw', 'rw_flow', 30, init=1050, unit='m³/h', kks='00GBD10BB001')   # read through a lag: the intake comes later
    m.cmp('wt_flow', 'wt_raw', '>=', 100)
    m.cmp('wt_raw_ok', 'wt_raw', '>=', 1000)
    m.AND('mx_run', ['mx_cmd'])
    m.NOT('cg_a_ok', 'cg_a_fault')
    m.AND('cg_a_run', ['cg_a_cmd', 'cg_a_ok'])
    m.OR('cg_on', ['cg_a_run', 'cg_b_cmd'])
    m.cmp('cg_tank_ok', 'cg_lvl', '>', 2)
    m.AND('cg_dosing', ['cg_on', 'wt_flow', 'cg_tank_ok'])
    m.prod('cg_dose', ['cg_dosing', 'cg_dose_sp'], 'mg/L')
    # the dose the river's turbidity asks for (jar tests; ours, inside [IEPA] p. 17): its inverse, so dose × it = ratio
    m.tab('cg_inv', 'river_ntu', [[5, round(1 / 12, 9)], [20, round(1 / 25, 9)], [100, round(1 / 45, 9)],
                                  [500, round(1 / 80, 9)]])
    m.prod('cg_ratio', ['cg_dose', 'cg_inv'])
    m.OR('pl_run', ['pl_a_cmd', 'pl_b_cmd'])
    m.AND('pl_on', ['pl_run', 'wt_flow'])
    m.tab('pl_k', 'pl_on', [[0, 2], [1, 1]])            # without polymer the flocs are small and settle badly
    m.tab('mx_k', 'mx_run', [[0, 3], [1, 1]])           # without the rapid mixer the coagulant is not spread
    # the fraction of the river's turbidity the clarifiers pass: under-dosed they carry floc over, over-dosed no better
    m.tab('cl_frac', 'cg_ratio', [[0, 0.9], [0.4, 0.5], [0.7, 0.1], [0.9, 0.03], [1.1, 0.02], [3, 0.025]])
    m.sum('cl_n', ['cla_cmd', 'clb_cmd'])
    m.tab('cl_share', 'cl_n', [[1, 1], [2, 0.5]])
    m.prod('cl_load', ['wt_raw', 'cl_share'], 'm³/h')
    m.tab('cl_over', 'cl_load', [[600, 1], [1100, 4]])  # one clarifier with all the flow: upflow 4.6 m/h, past 2.4
    m.prod('cl_sp0', ['river_ntu', 'cl_frac', 'pl_k', 'mx_k', 'cl_over'])
    m.max('cl_sp1', ['cl_sp0', 0.3])
    # with no flow the water stands and settles: the clarified turbidity goes to 0.5 NTU, whatever the dosing
    m.NOT('wt_still', 'wt_flow')
    m.prod('cl_sp_run', ['cl_sp1', 'wt_flow'])
    m.prod('cl_sp_still', ['wt_still', 0.5])
    m.sum('cl_sp', ['cl_sp_run', 'cl_sp_still'])
    m.lag('cl_ntu', 'cl_sp', 600, init=0.405263158, unit='NTU')       # about an hour through a clarifier (clock)
    m.max('cla_ntu', ['cl_ntu'], 'NTU', '00GBD11CQ001')
    m.max('clb_ntu', ['cl_ntu'], 'NTU', '00GBD12CQ001')
    m.cmp('cl_h', 'cl_ntu', '>', 5)
    m.cmp('cl_hc', 'cl_ntu', '<', 4)
    m.cmp('cl_ok', 'cl_ntu', '<', 2)
    m.delay('wt_raw_long', 'wt_raw_ok', 300)
    m.AND('cl_stable', ['cl_ok', 'wt_raw_long'])
    # the coagulant day tank: 3 m³ of 40 % ferric chloride (568 kg/m³ of FeCl3), about two days at 30 mg/L
    m.prod('cg_use', ['cg_dose', 'wt_raw', round(-100 / (1000 * 568 * 3), 12)])
    m.prod('cg_fill_q', ['cg_filling', 50])
    m.sum('cg_net', ['cg_use', 'cg_fill_q'])
    m.cmp('cg_l', 'cg_lvl', '<', 20)
    m.cmp('cg_lc', 'cg_lvl', '>', 25)
    m.cmp('cg_full', 'cg_lvl', '>=', 95)

    # ---------------------------------------------------------------- the gravity filters (§3 #5)
    m.prod('fl_in', ['wt_raw', 0.97], 'm³/h')            # 3 % leaves the clarifiers as sludge
    for i in FILTERS:
        st = f'filter{i}_state'
        m.cmp(f'fl{i}_svc', st, '<', 0.5)
        # the backwash's states are 1–4 (drain to rinse); standby (5) is neither
        m.cmp(f'fl{i}_st_lo', st, '>', 0.5)
        m.cmp(f'fl{i}_st_hi', st, '<', 4.5)
        m.AND(f'fl{i}_bw', [f'fl{i}_st_lo', f'fl{i}_st_hi'])
        m.cmp(f'fl{i}_st_r', st, '>', 3.5)
        m.AND(f'fl{i}_rinse', [f'fl{i}_st_r', f'fl{i}_st_hi'])
        m.timer(f'fl{i}_t', f'fl{i}_bw')
        t = 0
        for k, minutes in enumerate(F_TIMES, 1):
            t = round(t + clock_s(minutes), 1)
            m.cmp(f'fl{i}_t{k}', f'fl{i}_t', '>=', t)
    m.sum('fl_n', [f'fl{i}_svc' for i in FILTERS])
    m.tab('fl_share', 'fl_n', [[n, round(1 / n, 9)] for n in range(1, 7)])
    m.prod('fl_per', ['fl_in', 'fl_share'], 'm³/h')
    m.cmp('fl_any', 'fl_n', '>=', 0.5)
    m.prod('fl_flow', ['fl_in', 'fl_any'], 'm³/h')
    m.sum('bw_n', [f'fl{i}_bw' for i in FILTERS])
    m.cmp('bw_free', 'bw_n', '<', 0.5)
    # two backwashes commanded in one step both pass the permissive (it reads the previous step): the lower-numbered
    # filter goes on, the other returns to service
    for i in FILTERS:
        if i == 1:
            m.cmp('fl1_clash', 'bw_n', '<', -1)        # never: filter 1 always goes on
            continue
        m.sum(f'fl{i}_before', [f'fl{j}_bw' for j in range(1, i)])
        m.cmp(f'fl{i}_other', f'fl{i}_before', '>', 0.5)
        m.AND(f'fl{i}_clash', [f'fl{i}_bw', f'fl{i}_other'])
    for i in FILTERS:
        # head loss: the solids caught (turbidity × flow), about 0.05 m a clock hour at design (0.3 to 2.2 m in ~36 h);
        # the backwash's rinse washes it back to the clean bed's 0.3 m
        m.prod(f'fl{i}_load', [f'fl{i}_svc', 'cl_ntu', 'fl_per', 0.00077])
        m.prod(f'fl{i}_wash', [f'fl{i}_rinse', -60])
        m.sum(f'fl{i}_rate', [f'fl{i}_load', f'fl{i}_wash'])
        m.integ(f'fl{i}_hl', f'fl{i}_rate', round(DAY / 3600, 12), 0.3, 3, FILTER_INIT[i], 'm', f'00GBB1{i}CP001')
        m.cmp(f'fl{i}_hl_h', f'fl{i}_hl', '>', 2.2)
        m.cmp(f'fl{i}_hl_hc', f'fl{i}_hl', '<', 2.0)
        m.cmp(f'fl{i}_cleanbed', f'fl{i}_hl', '<', 0.5)
        m.AND(f'fl{i}_clean', [f'fl{i}_cleanbed', f'fl{i}_svc'])
        m.tab(f'fl{i}_bt', f'fl{i}_hl', [[2.2, 1], [2.8, 10]])         # breakthrough past the head loss limit
        m.prod(f'fl{i}_ntu', ['cl_ntu', 0.1, f'fl{i}_bt', f'fl{i}_svc'])
        m.ramp(f'fl{i}_v', f'fl{i}_svc', 0.05, init=1, unit='pu', kks=f'00GBB1{i}AA001')
    m.max('fl_ntu', [f'fl{i}_ntu' for i in FILTERS], 'NTU', '00GBB10')
    # SDI at the sample panel from the filtered turbidity (§3 #7: under 5 for the RO)
    m.tab('sdi', 'fl_ntu', [[0.05, 2.5], [0.2, 3], [1, 4.5], [3, 6]], 'SDI', '00QUG10')
    # the backwash: pump A and blower A, worked by the filters' sequences
    m.prod('bw_q', ['bw_water', BACKWASH], 'm³/h')

    # ---------------------------------------------------------------- the filtered water tank and its pumps (§3 #6)
    # the pumps' dry-run protection: off below 5 %, back above 10 % (no chatter at the limit)
    m.cmp('ft_dry_set', 'ft_lvl', '<', 5)
    m.cmp('ft_dry_reset', 'ft_lvl', '>', 10)
    m.latch('ft_dry', 'ft_dry_set', 'ft_dry_reset')
    m.NOT('ft_ok', 'ft_dry')
    m.cmp('ft_bw_ok', 'ft_lvl', '>=', 40)
    m.cmp('ft_l', 'ft_lvl', '<', 30)
    m.cmp('ft_lc', 'ft_lvl', '>', 35)
    m.cmp('ft_70', 'ft_lvl', '>=', 70)
    for x in 'ab':
        m.AND(f'mk_{x}_run', [f'mk_{x}_cmd', 'ft_ok'])
        m.AND(f'sw_{x}_run', [f'sw_{x}_cmd', 'ft_ok'])
        m.prod(f'mk_{x}_p0', [f'mk_{x}_run', 4.5])
        m.lag(f'mk_{x}_p', f'mk_{x}_p0', 3, init=4.5 if x == 'a' else 0, unit='bar', kks=f'00GHB10CP00{"ab".index(x) + 1}')
        m.prod(f'sw_{x}_p0', [f'sw_{x}_run', 3.5])
        m.lag(f'sw_{x}_p', f'sw_{x}_p0', 3, init=3.5 if x == 'a' else 0, unit='bar', kks=f'00GHA10CP00{"ab".index(x) + 1}')
    # the cooling tower makeup is there while a makeup pump runs with water in the tank (§8): the basin reads it
    m.OR('mk_run', ['mk_a_run', 'mk_b_run'])
    m.AND('mk_avail', ['mk_run'])
    m.max('sw_p', ['sw_a_p', 'sw_b_p'], 'bar')
    m.OR('sw_on', ['sw_a_run', 'sw_b_run'])
    m.cmp('sw_p_ok', 'sw_p', '>=', 3)

    # ---------------------------------------------------------------- dechlorination, antiscalant, acid (§3 #8)
    m.NOT('sbs_a_ok', 'sbs_a_fault')
    m.AND('sbs_a_run', ['sbs_a_cmd', 'sbs_a_ok'])
    m.OR('sbs_run', ['sbs_a_run', 'sbs_b_cmd'])
    m.AND('sbs_on', ['sbs_run', 'sw_on'])
    m.OR('as_run', ['as_a_cmd', 'as_b_cmd'])
    m.AND('as_on', ['as_run', 'sw_on'])
    m.OR('ac_run', ['ac_a_cmd', 'ac_b_cmd'])
    m.AND('ac_on', ['ac_run', 'sw_on'])
    m.AND('chem_on', ['sbs_on', 'as_on'])
    m.lag('wt_hy', 'hy_dose', 600, init=1.5)            # the chlorine dosed at the intake, an hour later
    m.tab('sbs_k', 'sbs_on', [[0, 1], [1, 0]])
    m.prod('cl_free', ['wt_hy', 0.5, 'sbs_k'], 'mg/L')  # half used up on the way; SBS takes the rest out
    m.tab('orp_sp', 'cl_free', [[0, 200], [0.05, 240], [0.2, 330], [0.75, 420]])
    m.sum('as_ac', ['as_on', 'ac_on'])
    m.tab('scale_k', 'as_ac', [[0, 5], [1, 2], [2, 1]])  # scaling without antiscalant and acid
    m.tab('sdi_k', 'sdi', [[3, 1], [5, 3], [6.5, 8]])
    m.prod('feed_cond', ['river_tds', 1.6], 'µS/cm')     # ~1.6 µS/cm per mg/L of salts

    # ---------------------------------------------------------------- the RO trains (§3 #9; [FT] §5.2 start and stop)
    for x, n in (('a', 1), ('b', 2)):
        p = f'ro_{x}'
        st = f'{p}_state'
        for k, s in enumerate(RO_STATES):
            m.cmp(f'{p}_ge{k}', st, '>', k - 0.5)
            m.cmp(f'{p}_le{k}', st, '<', k + 0.5)
            m.AND(f'{p}_is{k}', [f'{p}_ge{k}', f'{p}_le{k}'])
        m.timer(f'{p}_tf', f'{p}_is1')
        m.timer(f'{p}_ts', f'{p}_is2')
        m.timer(f'{p}_tp', f'{p}_is4')
        m.cmp(f'{p}_flushed', f'{p}_tf', '>=', clock_s(30))     # 30 min at 2–4 bar
        m.cmp(f'{p}_ts_done', f'{p}_ts', '>=', clock_s(60))     # permeate to drain for the first hour
        m.cmp(f'{p}_stop_flushed', f'{p}_tp', '>=', clock_s(30))
        m.ramp(f'{p}_spd', f'{p}_hp', 0.05, 0.2, init=1 if x == 'a' else 0, unit='pu')   # ramped slowly
        m.lag(f'{p}_fl', f'{p}_flush', 10)
        m.prod(f'{p}_fl_half', [f'{p}_fl', 0.5])
        m.max(f'{p}_ff', [f'{p}_spd', f'{p}_fl_half'])
        m.prod(f'{p}_feed', [f'{p}_ff', RO_FEED], 'm³/h')
        # the cartridge filter's differential pressure with the flow; clogged it takes the pump's suction away
        m.tab(f'cf_{x}_dp0', f'cf_{x}_clog', [[0, 0.35], [1, 2.9]])
        m.prod(f'cf_{x}_dp_sp', [f'cf_{x}_dp0', f'{p}_ff'])
        m.lag(f'cf_{x}_dp', f'cf_{x}_dp_sp', 300, init=0.35 if x == 'a' else 0, unit='bar', kks=f'00GCB1{n}CP001')
        m.diff(f'{p}_suct', 'sw_p', f'cf_{x}_dp', 'bar', f'00GCB2{n}CP002')
        m.cmp(f'{p}_suct_ok', f'{p}_suct', '>=', 1.5)
        m.cmp(f'{p}_suct_low', f'{p}_suct', '<', 1)
        m.AND(f'{p}_suct_ll', [f'{p}_suct_low', f'{p}_hp'])
        m.lag(f'{p}_orp', 'orp_sp', 20, init=200, unit='mV', kks=f'00GCB2{n}CQ002')
        m.cmp(f'{p}_orp_h0', f'{p}_orp', '>', 250)
        m.cmp(f'{p}_orp_hh0', f'{p}_orp', '>', 300)
        m.AND(f'{p}_orp_h', [f'{p}_orp_h0', f'{p}_hp'])
        m.AND(f'{p}_orp_hh', [f'{p}_orp_hh0', f'{p}_hp'])
        m.cmp(f'{p}_orp_ok', f'{p}_orp', '<', 230)
        # fouling (0–1): the colloids the feed's SDI brings, faster without antiscalant and acid; at design about a
        # tenth in a clock month, so cleaning (-10 % normalised flow, [FT] §6.3) comes after two to three months
        m.tab(f'{p}_fast_k', f'{p}_fast', [[0, 1], [1, 200]])
        m.prod(f'{p}_frate', [f'{p}_spd', 'sdi_k', 'scale_k', f'{p}_fast_k', 0.00014])
        m.integ(f'{p}_foul', f'{p}_frate', round(DAY / 3600, 12), 0, 1, 0.08 if x == 'a' else 0.05, 'pu')
        # the feed pressure the pump makes to hold 40 m³/h of permeate (~12 bar, [FT]); more as the membranes foul
        m.tab(f'{p}_pneed', f'{p}_foul', [[0, 11], [1, 16.5]], 'bar')
        m.prod(f'{p}_prun', [f'{p}_pneed', f'{p}_spd'])
        m.prod(f'{p}_pfl', [f'{p}_fl', 3])                # the low-pressure flush: 3 bar from the feed pumps
        m.prod(f'{p}_pconc', [f'{p}_conc_fault', f'{p}_spd', 6])   # a concentrate valve stuck nearly closed
        m.max(f'{p}_p0', [f'{p}_prun', f'{p}_pfl'])
        m.sum(f'{p}_p_sp', [f'{p}_p0', f'{p}_pconc'])
        m.lag(f'{p}_p', f'{p}_p_sp', 3, init=11.44 if x == 'a' else 0, unit='bar', kks=f'00GCB2{n}CP001')
        m.cmp(f'{p}_p_h', f'{p}_p', '>', 15)
        m.cmp(f'{p}_p_hc', f'{p}_p', '<', 14)
        m.cmp(f'{p}_p_hh', f'{p}_p', '>', 16)
        m.prod(f'{p}_perm', [f'{p}_spd', RO_PERM], 'm³/h', f'00GCB2{n}CF001')
        m.tab(f'{p}_nflow', f'{p}_foul', [[0, 100], [1, 70]], '%', f'00GCB2{n}CF001')
        m.cmp(f'{p}_nflow_l0', f'{p}_nflow', '<', 90)
        m.AND(f'{p}_nflow_l', [f'{p}_nflow_l0', f'{p}_is3'])
        # salt passage ~1.5 % (rejection ~98.5 %), worse fouled; four times that just after a start until flushed out;
        # a leaking O-ring passes feed straight into the permeate
        m.tab(f'{p}_pass', f'{p}_foul', [[0, 0.015], [1, 0.035]])
        m.lag(f'{p}_su', f'{p}_hp', 120, init=1 if x == 'a' else 0)
        m.tab(f'{p}_su_k', f'{p}_su', [[0, 4], [1, 1]])
        m.tab(f'{p}_leak_k', f'{p}_leak', [[0, 1], [1, 5]])
        m.prod(f'{p}_cond_sp', ['feed_cond', f'{p}_pass', f'{p}_su_k', f'{p}_leak_k'])
        m.lag(f'{p}_cond', f'{p}_cond_sp', 20, init=26.56 if x == 'a' else 102.4, unit='µS/cm', kks=f'00GCB2{n}CQ001')
        m.cmp(f'{p}_cond_h0', f'{p}_cond', '>', 50)
        m.AND(f'{p}_cond_h', [f'{p}_cond_h0', f'{p}_is3'])
        m.delay(f'{p}_cond_hd', f'{p}_cond_h', 10)
        m.cmp(f'{p}_cond_good', f'{p}_cond', '<', 40)
        m.AND(f'{p}_good_again', [f'{p}_bad', f'{p}_cond_good'])
        m.OR(f'{p}_drain', [f'{p}_dump', f'{p}_bad'])
        m.NOT(f'{p}_to_dg', f'{p}_drain')
        m.prod(f'{p}_out', [f'{p}_perm', f'{p}_to_dg'], 'm³/h')
        m.tab(f'{p}_conc_sp', st, [[0, 0], [0.5, 1], [1.5, 1], [2, 0.25], [3.5, 0.25], [3.6, 1]])
        m.max(f'{p}_feedv_sp', [f'{p}_hp', f'{p}_flush'])
        m.ramp(f'{p}_feedv', f'{p}_feedv_sp', 0.1, init=1 if x == 'a' else 0, unit='pu', kks=f'00GCB2{n}AA101')
        m.ramp(f'{p}_concv', f'{p}_conc_sp', 0.1, init=0.25 if x == 'a' else 0, unit='pu', kks=f'00GCB2{n}AA301')
        m.OR(f'{p}_tripped', [f'{p}_trip_suct_latched', f'{p}_trip_p_latched', f'{p}_trip_orp_latched'])
        m.NOT(f'{p}_no_trip', f'{p}_tripped')
        m.cmp(f'{p}_stopped', st, '<', 0.5)

    # ---------------------------------------------------------------- degasser and degassed water tank (§3 #10)
    m.tab('dg_sp', 'dg_cmd', [[0, 40], [1, 5]])        # CO2 left in the permeate, mg/L ([FT] p. 33; vendors 5–15)
    m.lag('dg_co2', 'dg_sp', 300, init=5, unit='mg/L')
    m.tab('co2_k', 'dg_co2', [[5, 1], [40, 3]])
    m.prod('perm_cond', ['feed_cond', 0.0166], 'µS/cm')     # the permeate in the degassed water tank, mixed
    m.sum('dg_in', ['ro_a_out', 'ro_b_out'], 'm³/h')
    m.cmp('dg_ll', 'dg_lvl', '<', 10)
    m.cmp('dg_ok', 'dg_lvl', '>=', 20)
    m.cmp('dg_room', 'dg_lvl', '<', 90)
    m.cmp('dg_h', 'dg_lvl', '>', 95)
    m.cmp('dg_hc', 'dg_lvl', '<', 90)
    m.tab('dg_feed_k', 'dg_lvl', [[10, 0.3], [30, 1]])  # the mixed beds' feed throttled as the tank empties

    # ---------------------------------------------------------------- mixed beds (§3 #11; [MB])
    for x, n in (('a', 1), ('b', 2)):
        p = f'mb_{x}'
        st = f'{p}_state'
        m.cmp(f'{p}_svc', st, '<', 0.5)
        m.cmp(f'{p}_rc0', st, '>', 0.5)
        m.cmp(f'{p}_rc1', st, '<', 1.5)
        m.AND(f'{p}_rc', [f'{p}_rc0', f'{p}_rc1'])
        m.OR(f'{p}_path', [f'{p}_svc', f'{p}_rc'])
        m.AND(f'mf_{x}_run', [f'mf_{x}_cmd'])
        m.lag(f'mf_{x}_spd', f'mf_{x}_run', 3, init=1 if x == 'a' else 0, unit='pu')
        m.prod(f'{p}_flow', [f'mf_{x}_spd', MB_FLOW, f'{p}_path', 'dg_feed_k'], 'm³/h')
        m.prod(f'{p}_out', [f'{p}_flow', f'{p}_svc'], 'm³/h')
        # exhaustion (0–1.2): the ions the bed takes (permeate conductivity × flow), more with CO2 left in; one
        # bed of RO permeate lasts about three clock days ([MB]: ≥ 24 h; on RO permeate much longer)
        m.tab(f'{p}_fast_k', f'{p}_fast', [[0, 1], [1, 60]])
        m.prod(f'{p}_rate', [f'{p}_flow', 'perm_cond', 'co2_k', f'{p}_fast_k', round(1 / (72 * MB_FLOW * 26.56), 12)])
        m.integ(f'{p}_ex', f'{p}_rate', round(DAY / 3600, 12), 0, 1.2, 0.5 if x == 'a' else 0, 'pu')
        m.tab(f'{p}_cond_sp', f'{p}_ex', [[0, 0.06], [0.9, 0.08], [1, 0.5], [1.2, 5]])
        m.lag(f'{p}_cond', f'{p}_cond_sp', 60, init=0.07111111 if x == 'a' else 0.06, unit='µS/cm',
              kks=f'00GCF1{n}CQ001')
        m.tab(f'{p}_si_sp', f'{p}_ex', [[0, 2], [0.85, 5], [1, 40], [1.2, 200]])
        m.lag(f'{p}_si', f'{p}_si_sp', 60, init=3.764705882 if x == 'a' else 2, unit='µg/kg', kks=f'00GCF1{n}CQ002')
        m.cmp(f'{p}_cond_h0', f'{p}_cond', '>', 0.2)
        m.AND(f'{p}_cond_h', [f'{p}_cond_h0', f'{p}_path'])
        m.AND(f'{p}_exh', [f'{p}_cond_h0', f'{p}_svc'])
        m.cmp(f'{p}_si_h0', f'{p}_si', '>', 20)
        m.AND(f'{p}_si_h', [f'{p}_si_h0', f'{p}_path'])
        m.cmp(f'{p}_good', f'{p}_cond', '<', 0.1)
        m.cmp(f'{p}_flowing', f'{p}_flow', '>=', 35)
        m.AND(f'{p}_making', [f'{p}_flowing', f'{p}_good', f'{p}_svc'])
        m.AND(f'mf_{x}_ll_c', ['dg_ll', f'mf_{x}_cmd'])
    m.sum('dg_out', ['mb_a_out', 'mb_b_out'])          # a recirculating bed's water comes back to the tank
    m.diff('dg_net', 'dg_in', 'dg_out')

    # ---------------------------------------------------------------- the demineralised water tanks and transfer (§3 #12)
    # the mixed beds fill both tanks through a common header; the transfer pumps draw on both
    m.sum('mb_out', ['mb_a_out', 'mb_b_out'], 'm³/h')
    m.prod('dt_in', ['mb_out', 0.5])
    m.prod('dt_drain_q', ['dt_drain', 2000])
    for x in 'ab':
        m.NOT(f'tr_{x}_ok', f'tr_{x}_fault')
        m.AND(f'tr_{x}_run', [f'tr_{x}_cmd', f'tr_{x}_ok'])
        m.lag(f'tr_{x}_spd', f'tr_{x}_run', 3, init=1 if x == 'a' else 0, unit='pu')
        m.AND(f'tr_{x}_ol_c', [f'tr_{x}_cmd', f'tr_{x}_fault'])
    m.sum('tr_n', ['tr_a_spd', 'tr_b_spd'])
    m.tab('tr_lc', 'dm_lvl', [[85, 1], [95, 0]])           # the plant tank's level valve: full at 95 %
    m.prod('tr_q', ['tr_n', TRANSFER, 'tr_lc'], 'm³/h', '00GHC10BR001')
    m.prod('dt_out1', ['tr_q', 0.5])
    m.sum('dt_a_out', ['dt_out1', 'dt_drain_q'])
    m.diff('dt_a_net', 'dt_in', 'dt_a_out')
    m.diff('dt_b_net', 'dt_in', 'dt_out1')
    for x, n in (('a', 1), ('b', 2)):
        m.cmp(f'dt_{x}_l', f'dt_{x}_lvl', '<', 25)
        m.cmp(f'dt_{x}_lc', f'dt_{x}_lvl', '>', 30)
        m.cmp(f'dt_{x}_ll', f'dt_{x}_lvl', '<', 10)
    m.OR('dt_ll', ['dt_a_ll', 'dt_b_ll'])
    m.NOT('dt_ok', 'dt_ll')
    for x in 'ab':
        m.AND(f'tr_{x}_ll_c', ['dt_ll', f'tr_{x}_cmd'])
    m.cmp('tr_flowing', 'tr_q', '>=', 30)

    # ---------------------------------------------------------------- filtered water tank level (all its flows known)
    m.sum('sw_use', ['ro_a_feed', 'ro_b_feed'])
    m.prod('sw_svc', ['sw_on', 50])                       # the site's service water
    m.sum('ft_out', ['bw_q', 'ct_mk_flow', 'sw_use', 'sw_svc'], 'm³/h')
    m.diff('ft_net', 'fl_flow', 'ft_out')
    # above 90 % the tank's overflow returns to the clarifiers' inlet channel (ours)

    # ---------------------------------------------------------------- neutralisation pit (§3 #13) and sludge (#14)
    m.OR('nr_on', ['nr_a_cmd', 'nr_b_cmd'])
    m.prod('nr_dis', ['nr_on', 60])
    m.diff('nr_net', 3, 'nr_dis')                       # the laboratory's and sample panel's drains, 3 m³/h
    m.prod('nr_ph_off', ['nr_drift', -2])
    m.sum('nr_ph_sp', [7.2, 'nr_ph_off'])
    m.lag('nr_ph', 'nr_ph_sp', 60, init=7.2, unit='pH', kks='00GNR10CQ001')
    m.cmp('nr_ph_lo', 'nr_ph', '>=', 6)
    m.cmp('nr_ph_hi', 'nr_ph', '<=', 9)
    m.AND('nr_ph_ok', ['nr_ph_lo', 'nr_ph_hi'])
    m.NOT('nr_ph_bad', 'nr_ph_ok')
    m.cmp('nr_low', 'nr_lvl', '<', 5)
    m.cmp('nr_lvl_ok', 'nr_lvl', '>=', 10)
    m.cmp('nr_h', 'nr_lvl', '>', 90)
    m.cmp('nr_hc', 'nr_lvl', '<', 85)
    m.AND('nr_low_run', ['nr_low', 'nr_on'])
    m.prod('th_load', ['wt_raw', 'river_ntu', round(1 / (1050 * 20), 12)])   # 1 at the dry season's design
    # the press takes up to 1.6 times the design's sludge while there is sludge to take (the level above 20 %)
    m.tab('th_cap', 'th_lvl', [[20, 0], [40, 1.6]])
    m.prod('th_out', ['fp_cmd', 'th_cap'])
    m.diff('th_bal', 'th_load', 'th_out')
    m.cmp('th_h', 'th_lvl', '>', 80)
    m.cmp('th_hc', 'th_lvl', '<', 75)

    # ---------------------------------------------------------------- operations
    m.start_stop('00GBD10AM001', 'mx', ok=False)
    m.b(kks='00GBD10AM001', lamp='running', of='mx_cmd')
    for x, n in (('a', 1), ('b', 2)):
        m.start_stop(f'00GBN10AP00{n}', f'cg_{x}', ok=(x == 'a'),
                     needs=[('cg_tank_ok', 'The coagulant day tank is empty')])
        m.start_stop(f'00GBN20AP00{n}', f'pl_{x}', ok=False)
    m.op('00GBN10BB001', 'set', None, (), input='cg_dose_sp', range=[0, 100])
    m.machines.append({'id': 'cg_fill', 'kks': '00GBN10BB001', 'init': 'idle',
                       'commands': {'fill': {'from': ['idle'], 'to': 'filling'},
                                    'stop_fill': {'from': ['filling'], 'to': 'idle'}},
                       'states': [{'id': 'idle', 'set': {'cg_filling': 0}, 'watch': False},
                                  {'id': 'filling', 'set': {'cg_filling': 1}, 'next': [['cg_full', 'idle']],
                                   'watch': False, 'say': 'Filling the day tank from the bulk tank'}]})
    m.op('00GBN10BB001', 'fill', None, (), machine='cg_fill')
    m.op('00GBN10BB001', 'stop_fill', None, (), machine='cg_fill')
    for x, code in (('a', '00GBD11AT001'), ('b', '00GBD12AT001')):
        m.op(code, 'start', {f'cl{x}_cmd': 1})
        m.op(code, 'stop', {f'cl{x}_cmd': 0})
    for i in FILTERS:
        mid = f'filter{i}'
        times = [f'fl{i}_t{k}' for k in range(1, 5)]
        m.machines.append({'id': mid, 'kks': f'00GBB1{i}AT001', 'init': 'service',
                           'commands': {'backwash': {'from': ['service', 'standby'], 'to': 'drain'},
                                        'take_out': {'from': ['service'], 'to': 'standby'},
                                        'put_in': {'from': ['standby'], 'to': 'service'}},
                           'states': [{'id': 'service', 'set': {'bw_air': 0, 'bw_water': 0}, 'watch': False},
                                      {'id': 'drain', 'next': [[f'fl{i}_clash', 'service'], [times[0], 'air']],
                                       'say': 'Draining down to the media'},
                                      {'id': 'air', 'set': {'bw_air': 1}, 'next': [[f'fl{i}_clash', 'service'], [times[1], 'air_water']],
                                       'say': 'Air scour, 1 m³/min per m²'},
                                      {'id': 'air_water', 'set': {'bw_water': 1}, 'next': [[f'fl{i}_clash', 'service'], [times[2], 'rinse']],
                                       'say': 'Air and water together'},
                                      {'id': 'rinse', 'set': {'bw_air': 0}, 'next': [[f'fl{i}_clash', 'service'], [times[3], 'service']],
                                       'say': 'Water at 45 m/h: the bed expands and the dirt goes to waste'},
                                      {'id': 'standby', 'watch': False}]})
        m.op(f'00GBB1{i}AT001', 'backwash', None,
             [('bw_free', 'Another filter is being backwashed: one at a time'),
              ('ft_bw_ok', 'Filtered water tank below 40 %: not enough water for a backwash')], machine=mid)
        m.op(f'00GBB1{i}AT001', 'take_out', None, (), machine=mid)
        m.op(f'00GBB1{i}AT001', 'put_in', None, (), machine=mid)
    for x, n in (('a', 1), ('b', 2)):
        m.start_stop(f'00GHB10AP00{n}', f'mk_{x}', [('ft_ok', 'Filtered water tank empty')], ok=False)
        m.start_stop(f'00GHA10AP00{n}', f'sw_{x}', [('ft_ok', 'Filtered water tank empty')], ok=False)
        m.start_stop(f'00GCN10AP00{n}', f'sbs_{x}', ok=(x == 'a'))
        m.start_stop(f'00GCN20AP00{n}', f'as_{x}', ok=False)
        m.start_stop(f'00GCE10AP00{n}', f'ac_{x}', ok=False)
    for x, n in (('a', 1), ('b', 2)):
        p = f'ro_{x}'
        code = f'00GCB2{n}AT001'
        m.machines.append({'id': p, 'kks': code, 'init': 'service' if x == 'a' else 'stopped',
                           'commands': {'start': {'from': ['stopped'], 'to': 'flushing'},
                                        'stop': {'from': ['flushing', 'starting', 'service'], 'to': 'stopping'},
                                        'flush': {'from': ['stopped'], 'to': 'stopping'}},
                           'states': [{'id': 'stopped', 'set': {f'{p}_hp': 0, f'{p}_flush': 0, f'{p}_dump': 1,
                                                                f'{p}_park': 0, f'{p}_bad': 0}, 'watch': False},
                                      {'id': 'flushing', 'set': {f'{p}_flush': 1, f'{p}_dump': 1},
                                       'next': [[f'{p}_flushed', 'starting']],
                                       'say': 'Low-pressure flush with feed water, 30 minutes'},
                                      {'id': 'starting', 'set': {f'{p}_flush': 0, f'{p}_hp': 1},
                                       'next': [[f'{p}_ts_done', 'service']],
                                       'say': 'High-pressure pump ramping up; permeate to drain for the first hour'},
                                      {'id': 'service', 'set': {f'{p}_dump': 0}, 'next': [[f'{p}_park', 'stopped']],
                                       'watch': False},
                                      {'id': 'stopping', 'set': {f'{p}_hp': 0, f'{p}_flush': 1, f'{p}_dump': 1},
                                       'next': [[f'{p}_stop_flushed', 'stopped']],
                                       'say': 'Flushing with permeate until the concentrate matches the feed'}]})
        m.op(code, 'start', None,
             [(f'{p}_no_trip', 'An RO trip is latched: reset it first'),
              (f'{p}_suct_ok', 'Suction pressure below 1.5 bar: no service water pump, or the cartridge filter is blocked'),
              ('sbs_on', 'Sodium bisulphite dosing not running: chlorine would reach the membranes'),
              ('as_on', 'Antiscalant dosing not running: the membranes would scale'),
              ('dg_room', 'Degassed water tank full')], machine=p)
        m.op(code, 'stop', None, (), machine=p)
        m.op(code, 'flush', None, [(f'{p}_no_trip', 'An RO trip is latched: reset it first'),
                                   ('sw_p_ok', 'No service water pressure to flush with')], machine=p)
        stop = [{'machine': p, 'to': 'stopped'}]
        L = x.upper()
        m.trip(f'{p}_trip_suct', f'00GCB2{n}CP002', f'RO {L}: high-pressure pump suction pressure low-low',
               f'{p}_suct_ll', stop, 'PALL', 2, p)
        m.trip(f'{p}_trip_p', f'00GCB2{n}CP001', f'RO {L}: feed pressure high-high', f'{p}_p_hh', stop, 'PAHH', 2, p)
        m.trip(f'{p}_trip_orp', f'00GCB2{n}CQ002', f'RO {L}: feed ORP high-high (chlorine)', f'{p}_orp_hh', stop,
               'QAHH', 10, p)
        m.interlock(f'{p}_to_drain', f'{p}_cond_hd', [{'set': {f'{p}_bad': 1}}], f'00GCB2{n}CQ001',
                    f'RO {L} permeate conductivity high: permeate to drain')
        m.interlock(f'{p}_to_service', f'{p}_good_again', [{'set': {f'{p}_bad': 0}}], f'00GCB2{n}CQ001',
                    f'RO {L} permeate good again: back to the degasser')
    m.start_stop('00GCH10AN001', 'dg', ok=False)
    for x, n in (('a', 1), ('b', 2)):
        p = f'mb_{x}'
        code = f'00GCF1{n}AT001'
        m.machines.append({'id': p, 'kks': code, 'init': 'service' if x == 'a' else 'standby',
                           'commands': {'in_service': {'from': ['recirc', 'standby'], 'to': 'service'},
                                        'recirculate': {'from': ['service', 'standby'], 'to': 'recirc'},
                                        'standby': {'from': ['service', 'recirc'], 'to': 'standby'}},
                           'states': [{'id': 'service', 'watch': False},
                                      {'id': 'recirc', 'watch': False,
                                       'say': 'Recirculating to the degassed water tank: the outlet is not good'},
                                      {'id': 'standby', 'watch': False}]})
        m.op(code, 'in_service', None, [(f'{p}_good', 'Outlet conductivity above 0.1 µS/cm: the bed needs '
                                                     'regeneration')], machine=p)
        m.op(code, 'recirculate', None, (), machine=p)
        m.op(code, 'standby', None, (), machine=p)
        m.interlock(f'{p}_exhausted', f'{p}_exh', [{'machine': p, 'to': 'recirc'}], code,
                    f'Mixed bed {x.upper()} exhausted (outlet above 0.2 µS/cm): to recirculation; the standby bed is '
                    f'offered')
        m.start_stop(f'00GCK10AP00{n}', f'mf_{x}', [('dg_ok', 'Degassed water tank below 20 %')], ok=False)
        m.trip(f'mf_{x}_trip_ll', f'00GCK10AP00{n}', f'Mixed bed feed pump {x.upper()}: degassed water tank low-low',
               f'mf_{x}_ll_c', [{'set': {f'mf_{x}_cmd': 0}}], 'LALL', 2, 'mb_feed')
    for x, n in (('a', 1), ('b', 2)):
        code = f'00GHC10AP00{n}'
        m.start_stop(code, f'tr_{x}', [('dt_ok', 'Demineralised water tanks low-low')])
        m.trip(f'tr_{x}_trip_ll', code, f'Transfer pump {x.upper()}: demineralised water tank low-low',
               f'tr_{x}_ll_c', [{'set': {f'tr_{x}_cmd': 0}}], 'LALL', 2, 'transfer')
        m.trip(f'tr_{x}_trip_ol', code, f'Transfer pump {x.upper()}: motor overload', f'tr_{x}_ol_c',
               [{'set': {f'tr_{x}_cmd': 0}}], None, 0.5, 'transfer')
        m.alarm(f'tr_{x}_tripped', code, f'Demineralised water transfer pump {x.upper()} tripped',
                f'tr_{x}_trip_ol_latched', 2)
    for x, n in (('a', 1), ('b', 2)):
        m.start_stop(f'00GNR10AP00{n}', f'nr_{x}', [('nr_ph_ok', 'pH outside 6–9: the discharge is blocked'),
                                                    ('nr_lvl_ok', 'Pit level below 10 %')], ok=False)
    m.interlock('nr_blocked', 'nr_ph_bad', [{'set': {'nr_a_cmd': 0, 'nr_b_cmd': 0}}], '00GNR10CQ001',
                'Neutralisation pit pH outside 6–9: discharge blocked')
    m.interlock('nr_empty', 'nr_low_run', [{'set': {'nr_a_cmd': 0, 'nr_b_cmd': 0}}], '00GNR10BB001',
                'Neutralisation pit empty: discharge pumps stopped')
    m.start_stop('00GNR10AM001', 'nr_mix', ok=False)
    m.start_stop('00GBS20AT001', 'fp', ok=False)

    # ---------------------------------------------------------------- alarms (§6)
    m.alarm('cg_low', '00GBN10BB001', 'Coagulant day tank low', 'cg_l', 3, isa='LAL', clear='cg_lc')
    for x, code in (('a', '00GBD11CQ001'), ('b', '00GBD12CQ001')):
        m.alarm(f'cl{x}_ntu_h', code, f'Clarifier {x.upper()}: clarified water turbidity high', 'cl_h', 2,
                isa='QAH', clear='cl_hc')
    for i in FILTERS:
        m.alarm(f'fl{i}_hl_h', f'00GBB1{i}CP001', f'Filter {i} head loss high: backwash due', f'fl{i}_hl_h', 3,
                f'00GBB1{i}AT001', 'PDAH', f'fl{i}_hl_hc')
    m.alarm('ft_low', '00GBL10CL001', 'Filtered water tank low', 'ft_l', 2, isa='LAL', clear='ft_lc')
    for x, n in (('a', 1), ('b', 2)):
        p = f'ro_{x}'
        L = x.upper()
        m.cmp(f'cf_{x}_dp_h', f'cf_{x}_dp', '>', 1.0)
        m.alarm(f'cf_{x}_dp_h', f'00GCB1{n}CP001', f'Cartridge filter {L} differential pressure high', f'cf_{x}_dp_h',
                3, f'00GCB1{n}AT001', 'PDAH')
        m.alarm(f'{p}_orp_h', f'00GCB2{n}CQ002', f'RO {L} feed ORP high', f'{p}_orp_h', 2, isa='QAH')
        m.alarm(f'{p}_orp_hh', f'00GCB2{n}CQ002', f'RO {L} feed ORP high-high (RO trip)', f'{p}_orp_hh', 1, isa='QAHH')
        m.alarm(f'{p}_p_h', f'00GCB2{n}CP001', f'RO {L} feed pressure high', f'{p}_p_h', 2, isa='PAH', clear=f'{p}_p_hc')
        m.alarm(f'{p}_p_hh', f'00GCB2{n}CP001', f'RO {L} feed pressure high-high (RO trip)', f'{p}_p_hh', 1, isa='PAHH')
        m.alarm(f'{p}_suct_ll', f'00GCB2{n}CP002', f'RO {L} high-pressure pump suction pressure low-low (RO trip)',
                f'{p}_suct_ll', 1, isa='PALL')
        m.alarm(f'{p}_cip', f'00GCB2{n}CF001', f'RO {L} normalised permeate flow low: cleaning due', f'{p}_nflow_l', 3,
                isa='FAL')
        m.alarm(f'{p}_cond_h', f'00GCB2{n}CQ001', f'RO {L} permeate conductivity high (to drain)', f'{p}_cond_h', 2,
                isa='QAH')
    for x, n in (('a', 1), ('b', 2)):
        m.alarm(f'mb_{x}_cond_h', f'00GCF1{n}CQ001', f'Mixed bed {x.upper()} outlet conductivity high (exhausted)',
                f'mb_{x}_cond_h', 2, f'00GCF1{n}AT001', 'QAH')
        m.alarm(f'mb_{x}_si_h', f'00GCF1{n}CQ002', f'Mixed bed {x.upper()} outlet silica high', f'mb_{x}_si_h', 2,
                f'00GCF1{n}AT001', 'QAH')
        m.alarm(f'dt_{x}_low', f'00GCL10CL00{n}', f'Demineralised water tank {x.upper()} low', f'dt_{x}_l', 2,
                f'00GCL10BB00{n}', 'LAL', f'dt_{x}_lc')
        m.alarm(f'dt_{x}_ll', f'00GCL10CL00{n}', f'Demineralised water tank {x.upper()} low-low (transfer pumps trip)',
                f'dt_{x}_ll', 1, f'00GCL10BB00{n}', 'LALL')
    m.alarm('nr_ph', '00GNR10CQ001', 'Neutralisation pit pH out of range (discharge blocked)', 'nr_ph_bad', 3,
            '00GNR10BB001', 'QAH')
    m.alarm('dg_high', '00GCK10BB001', 'Degassed water tank high: the permeate overflows to drain', 'dg_h', 3,
            isa='LAH', clear='dg_hc')
    m.alarm('nr_high', '00GNR10BB001', 'Neutralisation pit level high: discharge it', 'nr_h', 3, isa='LAH',
            clear='nr_hc')
    m.alarm('th_high', '00GBS10AT001', 'Thickener sludge level high', 'th_h', 3, isa='LAH', clear='th_hc')

    # ---------------------------------------------------------------- what is seen and heard
    m.b(kks='00GBD10AM001', sound='motor_small', gain={'of': 'mx_cmd', 'table': [[0, 0], [1, 0.4]]})
    for x, n in (('a', 1), ('b', 2)):
        for pre, sys in (('cg', '00GBN10'), ('pl', '00GBN20'), ('sbs', '00GCN10'), ('as', '00GCN20'),
                         ('ac', '00GCE10')):
            # a failed pump (coagulant and bisulphite A) shows stopped
            run = f'{pre}_a_run' if x == 'a' and pre in ('cg', 'sbs') else f'{pre}_{x}_cmd'
            m.b(kks=f'{sys}AP00{n}', lamp='running', of=run)
        for pre, sys, run in (('mk', '00GHB10', 'mk_{x}_run'), ('sw', '00GHA10', 'sw_{x}_run'),
                              ('mf', '00GCK10', 'mf_{x}_spd'), ('tr', '00GHC10', 'tr_{x}_spd')):
            code = f'{sys}AP00{n}'
            r = run.format(x=x)
            m.b(kks=code, anim='shaft', of=r, scale=24.7)
            m.b(kks=code, sound='motor_small', gain={'of': r, 'table': [[0, 0], [1, 0.8]]})
            m.b(kks=code, lamp='running', of=r)
        for v, valve in (('mk', '00GHB10AA10'), ('sw', '00GHA10AA10'), ('tr', '00GHC10AA10')):
            m.b(kks=f'{valve}{n}', anim='stem', of=f'{v}_{x}_cmd')
        m.b(kks=f'00GHB10CP00{n}', show=f'mk_{x}_p')
        m.b(kks=f'00GHA10CP00{n}', show=f'sw_{x}_p')
        hp = f'00GCB2{n}AP001'
        m.b(kks=hp, anim='shaft', of=f'ro_{x}_spd', scale=49.5)
        m.b(kks=hp, sound='ro_hp_pump', gain={'of': f'ro_{x}_spd', 'table': [[0, 0], [1, 1]]})
        m.b(kks=hp, lamp='running', of=f'ro_{x}_spd')
        m.b(kks=f'00GCB2{n}AA101', anim='stem', of=f'ro_{x}_feedv')
        m.b(kks=f'00GCB2{n}AA301', anim='stem', of=f'ro_{x}_concv')
        m.b(kks=f'00GCB2{n}CP001', show=f'ro_{x}_p')
        m.b(kks=f'00GCB2{n}CP002', show=f'ro_{x}_suct')
        m.b(kks=f'00GCB1{n}CP001', show=f'cf_{x}_dp')
        m.b(kks=f'00GCB2{n}CQ001', show=f'ro_{x}_cond')
        m.b(kks=f'00GCB2{n}CQ002', show=f'ro_{x}_orp')
        m.b(kks=f'00GCF1{n}CQ001', show=f'mb_{x}_cond')
        m.b(kks=f'00GCF1{n}CQ002', show=f'mb_{x}_si')
        m.b(kks=f'00GCL10CL00{n}', show=f'dt_{x}_lvl')
        m.b(kks=f'00GNR10AP00{n}', lamp='running', of=f'nr_{x}_cmd')
    m.b(kks='00GCH10AN001', anim='shaft', of='dg_cmd', scale=25)
    m.b(kks='00GCH10AN001', sound='motor_small', gain={'of': 'dg_cmd', 'table': [[0, 0], [1, 0.6]]})
    m.b(kks='00GCH10AN001', lamp='running', of='dg_cmd')
    m.b(kks='00GBR10AP001', anim='shaft', of='bw_water', scale=24.7)
    m.b(kks='00GBR10AP001', sound='motor_small', gain={'of': 'bw_water', 'table': [[0, 0], [1, 0.9]]})
    m.b(kks='00GBR10AP001', lamp='running', of='bw_water')
    m.b(kks='00GBR10AN001', anim='shaft', of='bw_air', scale=25)
    m.b(kks='00GBR10AN001', sound='motor_small', gain={'of': 'bw_air', 'table': [[0, 0], [1, 0.8]]})
    m.b(kks='00GBR10AN001', lamp='running', of='bw_air')
    for i in FILTERS:
        m.b(kks=f'00GBB1{i}AA001', anim='disc', of=f'fl{i}_v')
        m.b(kks=f'00GBB1{i}CP001', show=f'fl{i}_hl')
    m.b(kks='00GBL10CL001', show='ft_lvl')
    m.b(kks='00GBD11CQ001', show='cla_ntu')
    m.b(kks='00GBD12CQ001', show='clb_ntu')
    m.b(kks='00GNR10CQ001', show='nr_ph')
    m.b(kks='00GNR10AM001', lamp='running', of='nr_mix_cmd')
    m.b(kks='00GBS20AT001', lamp='running', of='fp_cmd')
    return m


def models():
    """wtp's and intake's models, in plant.json's area order (wtp before intake)."""
    return [wtp(), intake()]


def faults(state_kks):
    from train_content import fault
    return [fault(f, s, t, state_kks) for f, s, t in FAULTS]
