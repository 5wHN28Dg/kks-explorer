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
# W3: an RO train's clean-in-place ([FT] §6.3 tables 35–37; [TSB] p. 2, p. 8–12): two stages recirculated in turn, a
# soak and a flush, clock minutes (ours, inside the sources' 30–60 min per stage and 1–15 h soak)
CIP_TANK = 4                # m³ (ours): a first stage's 36 elements at ~36 L each, the hoses and a heel
CIP_FILL = 24               # m³/h of permeate into the CIP tank, and its drain to the pit (ours)
CIP_TIMES = [30, 30, 30]    # clock minutes: stage 1, stage 2, a short soak (cumulative in the sequence)
CIP_FLUSH = 20              # clock minutes of the flush to the pit
CIP_CLEAN = 2.5             # per clock hour: how fast a solution at its best takes its foulant off (ours)
# W3: a mixed bed's regeneration ([MB] p. 2–3), clock minutes of each timed state (ours, about 3.5 hours with the
# operator's two holds; [MB]: ~4 h): backwash and separation, settle, drain; regenerants, displacement, drain; air mix, refill,
# final rinse (at least 30 min, then until the outlet is good)
MB_REGEN = [('backwash', 25), ('settle', 5), ('drain', 10), ('ready', None), ('inject', 40), ('displace', 60),
            ('drain2', 15), ('air_ready', None), ('air_mix', 10), ('refill', 15), ('rinse', 30)]
# the water each state sends to the neutralisation pit, m³/h of the clock (ours: the backwash at ~10 m/h over the
# 2 m² bed, the regenerants diluted, three bed volumes of displacement, the final rinse at the service flow)
MB_WASTE = {'backwash': 20, 'drain': 10, 'inject': 8, 'displace': 9, 'drain2': 10, 'rinse': 40}
# the regenerants' excess the pit receives, kmol/h of the clock (negative: acid). HCl 5 % at ~90 g/L and NaOH 4 % at
# ~100 g/L of resin ([MB]) on 1.5 m³ of each resin: about 3.7 kmol of each; the resin takes the most part, and the
# acid's excess is the larger (ours)
MB_ACID = {'inject': -0.2, 'displace': -0.15}
REGEN_USE = 21              # % of a regenerant tank a clock hour of injection (≈14 % a regeneration; ours)
# the neutralisation pit's pH from its excess of base, kmol (negative: acid), in ~100 m³ of water with the river's
# own buffer (ours: strong acid or base, 0.1 kmol in 100 m³ is pH 3 or 11)
NR_PH = [[-2, 1.5], [-0.3, 2.5], [-0.05, 4.0], [-0.01, 5.5], [-0.002, 6.5], [0, 7.2], [0.002, 7.8], [0.01, 9.0],
         [0.05, 10.5], [0.3, 11.5], [2, 12.5]]

# what the scenarios that start with the WTP stopped (wtp_cold) put in: everything stopped, tanks at 60 %
COLD_WTP = {'rw_a_cmd': 0, 'rw_b_cmd': 0, 'rw_a_spd': 0, 'rw_b_spd': 0, 'hy_a_cmd': 0, 'wt_raw': 0,
            'mx_cmd': 0, 'cg_a_cmd': 0, 'pl_a_cmd': 0, 'mk_a_cmd': 0, 'sw_a_cmd': 0, 'sw_a_p': 0,
            'mk_a_p': 0, 'sbs_a_cmd': 0, 'as_a_cmd': 0, 'ac_a_cmd': 0, 'ro_a_park': 1, 'ro_a_hp': 0, 'ro_a_dump': 1,
            'ro_a_spd': 0, 'ro_a_p': 0, 'ro_a_feedv': 0, 'ro_a_concv': 0, 'ro_a_su': 0, 'cf_a_dp': 0,
            'ct_mk_sup': 0, 'dg_cmd': 0, 'dg_co2': 40,
            'mf_a_cmd': 0, 'mf_a_spd': 0, 'tr_a_cmd': 0, 'tr_a_spd': 0, 'fp_cmd': 0, 'wt_hy': 0, 'cl_ntu': 1, 'cla_ntu': 1, 'clb_ntu': 1,
            'ft_lvl': 60, 'dg_lvl': 60, 'dt_a_lvl': 60, 'dt_b_lvl': 60, 'cg_lvl': 60, 'dm_lvl': 60, 'dm_in': 0}

# W3's scenarios (WATER-TREATMENT §7). wtp_normal: one RO and one mixed bed stream in service, the day's work waiting
# in its first hour: filter 1 due for its backwash (its alarm standing), RO B off line for its cleaning (its normalised
# flow 89 %, a third of its fouling in each part, ro_bio/sc/irr), mixed bed A 82 % used (silica breaks through in
# about an hour: its lags at their steady values)
NORMAL_WTP = {'fl1_hl': 2.25, 'mb_a_ex': 0.82, 'mb_a_cond_lag': 0.078222222, 'mb_a_si': 4.894117647,
              'ro_b_bio': 0.216, 'ro_b_sc': 0.108, 'ro_b_irr': 0.036, 'ro_b_cond': 142.08}
# wtp_flood: the river in flood (§2: up to 500 NTU) with the WTP running at the dry season's dose
FLOOD_WTP = {'river_ntu': 500}

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
    # W3 (WATER-TREATMENT §7: the remaining faults)
    ('as_pump', {'as_a_fault': 1}, 'Antiscalant dosing pump A fails: the RO membranes scale faster'),
    ('cl_upset', {'cl_upset': 1}, 'Clarifier A: its rake drive stalls, the sludge blanket rises and floc carries over'),
    ('fl3_underdrain', {'fl3_ud': 1}, 'Filter 3: a broken underdrain nozzle lets media and dirt through (breakthrough)'),
    ('dg_motor', {'dg_fault': 1}, 'Degasser blower motor overload: carbon dioxide stays in the permeate'),
    ('ro_b_fouling', {'ro_b_fast': 1}, 'RO B fouls fast (a colloid upset upstream): cleaning due early'),
    ('mb_a_resin', {'mb_a_resin': 1}, 'Mixed bed A: a broken underdrain lateral leaks resin into the outlet strainer'),
    ('mb_b_resin', {'mb_b_resin': 1}, 'Mixed bed B: a broken underdrain lateral leaks resin into the outlet strainer'),
    ('cip_heater', {'cip_heat_fault': 1}, 'The CIP tank heater\'s thermostat sticks: the solution overheats'),
    # S3: the analysers' drifts, put right by the I&C technicians' calibrations under a permit
    ('ro_a_orp_drift', {'ro_a_orp_drift': 40}, 'RO A feed ORP analyser drifts: reads 40 mV high'),
    ('ro_b_orp_drift', {'ro_b_orp_drift': 40}, 'RO B feed ORP analyser drifts: reads 40 mV high'),
    ('ro_a_cond_drift', {'ro_a_cond_drift': 15}, 'RO A permeate conductivity analyser drifts: reads 15 µS/cm high'),
    ('ro_b_cond_drift', {'ro_b_cond_drift': 15}, 'RO B permeate conductivity analyser drifts: reads 15 µS/cm high'),
]
# repaired only by a work under a permit (hands inside the equipment, STAFF.md), not at the equipment
BY_WORK = {'mb_a_resin', 'mb_b_resin'}


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
    m.state('cl_upset', 0, '00GBD11AT001')
    m.state('cla_cmd', 1, '00GBD11AT001')
    m.state('clb_cmd', 1, '00GBD12AT001')
    m.state('fl3_ud', 0, '00GBB13AT001')
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
    m.state('as_a_fault', 0, '00GCN20AP001')
    for x, n in (('a', 1), ('b', 2)):
        m.state(f'cf_{x}_clog', 0, f'00GCB1{n}AT001')
        ro = f'00GCB2{n}AT001'
        for s, init in (('hp', 1 if x == 'a' else 0), ('flush', 0), ('dump', 0 if x == 'a' else 1), ('bad', 0),
                        ('park', 0), ('leak', 0), ('fast', 0), ('dmg', 0)):
            m.state(f'ro_{x}_{s}', init, ro)
        m.state(f'ro_{x}_conc_fault', 0, f'00GCB2{n}AA301')
        m.state(f'mb_{x}_fast', 0, f'00GCF1{n}AT001')
        m.state(f'mb_{x}_resin', 0, f'00GCF1{n}AT001')
        # the RO train's analysers drift (a fault the trainer sets): the I&C technicians' calibration under a permit
        # puts it back to 0 (milestone S3, WATER-TREATMENT §7 "Staff")
        m.state(f'ro_{x}_orp_drift', 0, f'00GCB2{n}CQ002', 'mV')
        m.state(f'ro_{x}_cond_drift', 0, f'00GCB2{n}CQ001', 'µS/cm')
        m.const(f'mb_{x}_o2', 20.9, '% O₂')         # the air in the vessel, opened and ventilated for a work
    drive(m, 'dg', '00GCH10AN001', 1, True)
    # the CIP skid (W3): the tank's sequence writes its fill, drain and chemical; the heater is worked by hand
    for st_, kks in (('cip_fill', '00GCB30BB001'), ('cip_drain', '00GCB30BB001'), ('cip_chem', '00GCB30BB001'),
                     ('cip_heat_cmd', '00GCB30AH001'), ('cip_heat_fault', '00GCB30AH001')):
        m.state(st_, 0, kks)
    # the mixed beds' regeneration (W3): the resin mixing blower, the regenerant tanks' fills
    drive(m, 'gp_air', '00GCP30AN001', 0)
    m.state('gp_hcl_filling', 0, '00GCP10BB001')
    m.state('gp_naoh_filling', 0, '00GCP20BB001')
    m.state('dt_drain', 0, '00GCL10BB001')
    drive(m, 'nr_mix', '00GNR10AM001', 1)
    m.state('nr_drift', 0, '00GNR10CQ001')
    m.state('nr_auto', 0, '00GNR10BB001')        # the neutralisation batch's dosing (W3)
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
    m.integ('cip_lvl', 'cip_net', clock_gain(CIP_TANK), 0, 100, 0, '%', '00GCB30BB001')
    # the regenerant tanks (% a clock hour) and the pit's excess of base (kmol a clock hour)
    m.integ('gp_hcl_lvl', 'gp_hcl_net', round(DAY / 3600, 12), 0, 100, 60, '%', '00GCP10BB001')
    m.integ('gp_naoh_lvl', 'gp_naoh_net', round(DAY / 3600, 12), 0, 100, 60, '%', '00GCP20BB001')
    m.integ('nr_alk', 'nr_alk_in', round(DAY / 3600, 12), -10, 10, 0, 'kmol')

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
    # a turbid river flocculates better (more collisions): at a flood's 500 NTU, rightly dosed, the clarifiers still
    # give about 2 NTU (W3, wtp_flood; ours, the trend [IEPA] §5.3 describes)
    m.tab('cl_fk', 'river_ntu', [[100, 1], [500, 0.15]])
    m.prod('cl_sp0', ['river_ntu', 'cl_frac', 'pl_k', 'mx_k', 'cl_over', 'cl_fk'])
    m.max('cl_sp1', ['cl_sp0', 0.3])
    # with no flow the water stands and settles: the clarified turbidity goes to 0.5 NTU, whatever the dosing
    m.NOT('wt_still', 'wt_flow')
    m.prod('cl_sp_run', ['cl_sp1', 'wt_flow'])
    m.prod('cl_sp_still', ['wt_still', 0.5])
    m.sum('cl_sp', ['cl_sp_run', 'cl_sp_still'])
    # clarifier A's upset (W3: its rake stalled, the blanket over the weirs) is 30 times its carry-over; the filters
    # take the two clarifiers' water mixed (the one in service alone, all of it)
    m.tab('cl_upset_k', 'cl_upset', [[0, 1], [1, 30]])
    m.prod('cla_in', ['cla_cmd', 'cl_upset_k'])
    m.sum('cl_mix0', ['cla_in', 'clb_cmd'])
    m.prod('cl_mix1', ['cl_mix0', 'cl_share'])
    m.max('cl_mix_k', ['cl_mix1', 1])
    m.prod('cl_sp_mix', ['cl_sp', 'cl_mix_k'])
    m.lag('cl_ntu', 'cl_sp_mix', 600, init=0.405263158, unit='NTU')   # about an hour through a clarifier (clock)
    # each clarifier's own turbidity: out of service its water stands and settles to 0.5 NTU, as with no flow
    for x, n, refs in (('a', 1, ['cl_sp', 'cl_upset_k', 'cla_cmd']), ('b', 2, ['cl_sp', 'clb_cmd'])):
        m.prod(f'cl{x}_sp_run', refs)
        m.NOT(f'cl{x}_out', f'cl{x}_cmd')
        m.prod(f'cl{x}_sp_still', [f'cl{x}_out', 0.5])
        m.sum(f'cl{x}_sp', [f'cl{x}_sp_run', f'cl{x}_sp_still'])
        m.lag(f'cl{x}_ntu', f'cl{x}_sp', 600, init=0.405263158, unit='NTU', kks=f'00GBD1{n}CQ001')
    for x in 'ab':
        m.cmp(f'cl{x}_h', f'cl{x}_ntu', '>', 5)
        m.cmp(f'cl{x}_hc', f'cl{x}_ntu', '<', 4)
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
        refs = ['cl_ntu', 0.1, f'fl{i}_bt', f'fl{i}_svc']
        if i == 3:      # its underdrain fault (W3): media and dirt pass whatever the head loss
            m.tab('fl3_ud_k', 'fl3_ud', [[0, 1], [1, 20]])
            refs.append('fl3_ud_k')
        m.prod(f'fl{i}_ntu', refs)
        m.ramp(f'fl{i}_v', f'fl{i}_svc', 0.05, init=1, unit='pu', kks=f'00GBB1{i}AA001')
    m.max('fl_ntu', [f'fl{i}_ntu' for i in FILTERS], 'NTU', '00GBB10')
    m.cmp('fl_ntu_h', 'fl_ntu', '>', 0.5)                # breakthrough ([10SS] §4.3.1: filtered water under 0.3 NTU)
    m.cmp('fl_ntu_hc', 'fl_ntu', '<', 0.4)
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
    m.AND('sbs_dose_on', ['sbs_run', 'sw_on'])
    # the RO's start reads the dosing pumps' run commands, as a control system sees them, not their flow (a failed
    # pump still says running: its no-flow alarm tells; W3, WATER-TREATMENT §7's restart without the fix)
    m.OR('sbs_cmd_on', ['sbs_a_cmd', 'sbs_b_cmd'])
    m.AND('sbs_on', ['sbs_cmd_on', 'sw_on'])
    m.NOT('as_a_ok', 'as_a_fault')
    m.AND('as_a_run', ['as_a_cmd', 'as_a_ok'])
    m.OR('as_run', ['as_a_run', 'as_b_cmd'])
    m.AND('as_dose_on', ['as_run', 'sw_on'])
    m.OR('as_cmd_on', ['as_a_cmd', 'as_b_cmd'])
    m.AND('as_on', ['as_cmd_on', 'sw_on'])
    m.OR('ac_run', ['ac_a_cmd', 'ac_b_cmd'])
    m.AND('ac_on', ['ac_run', 'sw_on'])
    m.AND('chem_on', ['sbs_on', 'as_on'])
    m.lag('wt_hy', 'hy_dose', 600, init=1.5)            # the chlorine dosed at the intake, an hour later
    m.tab('sbs_k', 'sbs_dose_on', [[0, 1], [1, 0]])
    m.prod('cl_free', ['wt_hy', 0.5, 'sbs_k'], 'mg/L')  # half used up on the way; SBS takes the rest out
    m.tab('orp_sp', 'cl_free', [[0, 200], [0.05, 240], [0.2, 330], [0.75, 420]])
    m.sum('as_ac', ['as_dose_on', 'ac_on'])
    m.tab('scale_k', 'as_ac', [[0, 5], [1, 2], [2, 1]])  # scaling without antiscalant and acid
    m.tab('sdi_k', 'sdi', [[3, 1], [5, 3], [6.5, 8]])
    m.prod('feed_cond', ['river_tds', 1.6], 'µS/cm')     # ~1.6 µS/cm per mg/L of salts

    # ---------------------------------------------------------------- the CIP skid (W3; WATER-TREATMENT §3 "RO cleaning")
    # its tank's sequence (machine cip): 0 empty, 1 filling, 2 water, 3 alkaline, 4 acid, 5 draining
    m.tab('cip_alk', 'cip_state', [[2.5, 0], [3, 1], [3.5, 0]])
    m.tab('cip_acid', 'cip_state', [[3.5, 0], [4, 1], [4.5, 0]])
    m.tab('cip_water', 'cip_state', [[1.5, 0], [2, 1], [2.5, 0]])
    m.tab('cip_idle', 'cip_state', [[0, 1], [0.5, 0]])
    m.NOT('cip_heat_off', 'cip_heat_cmd')
    m.AND('cip_idle_off', ['cip_idle', 'cip_heat_off'])     # drained, its heater stopped (ro_cip's drain_alk)
    m.tab('cip_filling', 'cip_state', [[0.5, 0], [1, 1], [1.5, 0]])
    m.cmp('cip_full', 'cip_lvl', '>=', 90)
    m.cmp('cip_empty', 'cip_lvl', '<', 0.5)
    m.cmp('cip_has', 'cip_lvl', '>=', 20)
    m.NOT('cip_wet', 'cip_empty')
    m.prod('cip_fill_q', ['cip_fill', CIP_FILL], 'm³/h')
    m.prod('cip_dr_q', ['cip_drain', CIP_FILL], 'm³/h')
    # 0.1 % NaOH (0.025 kmol/m³), 0.2 % HCl (0.055 kmol/m³): what the solution takes to the pit
    m.tab('cip_conc', 'cip_chem', [[0, 0], [1, 0.025], [2, -0.055]])
    m.prod('cip_dr_chem', ['cip_dr_q', 'cip_conc'])
    m.tab('cip_ph_sp', 'cip_chem', [[0, 7], [1, 12], [2, 2]])
    m.lag('cip_ph', 'cip_ph_sp', clock_s(5), init=7, unit='pH', kks='00GCB30CQ001')
    # the heater warms the solution to its thermostat's 35 °C, 10 K a clock hour (40 kW in 4 m³; ours); off, it cools
    # 2 K an hour towards the permeate's 28 °C; a stuck thermostat heats on towards 50 °C
    m.AND('cip_heat_on', ['cip_heat_cmd', 'cip_has'])
    m.tab('cip_heat_k', 'cip_heat_fault', [[0, 7], [1, 22]])
    m.prod('cip_rise', ['cip_heat_on', 'cip_heat_k'])
    m.sum('cip_t_sp', [28, 'cip_rise'])
    m.ramp('cip_t', 'cip_t_sp', round(DAY * 10 / 3600, 9), round(DAY * 2 / 3600, 9), init=28, unit='°C',
           kks='00GCB30CT001')
    m.cmp('cip_warm', 'cip_t', '>=', 30)
    m.cmp('cip_t_ok', 'cip_t', '<=', 35.5)      # high pH at most 35 °C ([FT] table 35)
    m.cmp('cip_t_aok', 'cip_t', '<=', 40)       # low pH at most 40 °C (the skid's trip)
    m.cmp('cip_t_h', 'cip_t', '>', 36)
    m.cmp('cip_t_hc', 'cip_t', '<', 35.5)
    m.cmp('cip_t_hh', 'cip_t', '>', 40)
    # the limit the cleaning trips at: 36.5 °C for a high-pH solution (35 °C, [FT] table 35), 40 °C for any
    m.cmp('cip_t_alk_hh0', 'cip_t', '>', 36.5)
    m.AND('cip_t_alk_hh', ['cip_t_alk_hh0', 'cip_alk'])
    m.OR('cip_over', ['cip_t_hh', 'cip_t_alk_hh'])
    m.cmp('cip_ph_hi', 'cip_ph', '>=', 11.5)
    m.cmp('cip_ph_lo', 'cip_ph', '<=', 2.5)
    m.AND('cip_alk_ok', ['cip_alk', 'cip_ph_hi', 'cip_warm', 'cip_t_ok'])
    m.AND('cip_acid_ok', ['cip_acid', 'cip_ph_lo', 'cip_t_aok'])
    m.OR('cip_ready', ['cip_alk_ok', 'cip_acid_ok'])
    # how fast the solution cleans (per clock hour): high pH takes the colloids and biofilm, low pH the scale; a cold
    # high-pH solution works less ([TSB] p. 8: warm cleaning)
    m.tab('cip_tk', 'cip_t', [[25, 0.4], [35, 1]])
    m.prod('cip_alk_k', ['cip_alk', 'cip_tk', -CIP_CLEAN])
    m.prod('cip_acid_k', ['cip_acid', -CIP_CLEAN])

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
        # its cleaning (W3): states 5–7 recirculate and soak (one timer over them), 8 flushes the solution out
        m.tab(f'{p}_incirc', st, [[4.5, 0], [5, 1], [7, 1], [7.5, 0]])
        m.tab(f'{p}_isfl', st, [[7.5, 0], [8, 1]])
        m.tab(f'{p}_incip', st, [[4.5, 0], [5, 1]])
        m.timer(f'{p}_tc', f'{p}_incirc')
        t = 0
        for k, minutes in enumerate(CIP_TIMES, 1):
            t = round(t + clock_s(minutes), 1)
            m.cmp(f'{p}_c{k}', f'{p}_tc', '>=', t)
        m.timer(f'{p}_tfl', f'{p}_isfl')
        m.cmp(f'{p}_fl_done', f'{p}_tfl', '>=', clock_s(CIP_FLUSH))
        m.prod(f'{p}_fl_q', [f'{p}_isfl', 20], 'm³/h')          # the flush to the pit, half of it solution
        # a cleaning with each solution done (its flush ended), until the CIP tank is filled again: the procedure's
        # step ends there, not while the train still stands stopped from before
        # (only a whole cycle: its soak finished, not a cleaning stopped or tripped to its flush early)
        m.latch(f'{p}_soaked', f'{p}_c3', 'cip_filling')
        for c, sol in (('alk', 'cip_alk'), ('acid', 'cip_acid')):
            m.AND(f'{p}_{c}_end', [f'{p}_fl_done', sol, f'{p}_soaked'])
            m.latch(f'{p}_{c}_cl', f'{p}_{c}_end', 'cip_filling')
            m.AND(f'{p}_{c}_cleaned', [f'{p}_{c}_cl', f'{p}_is0'])
        m.prod(f'{p}_fl_chem', [f'{p}_isfl', 'cip_conc', 10, 'cip_wet'])   # only what the tank still holds
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
        # the feed ORP as the water has it, and as its analyser shows it: with the analyser's drift, its last reading
        # while it is isolated for its calibration (PLANT3D §15.4); the alarms and the trip read the analyser
        m.lag(f'{p}_orp_m', 'orp_sp', 20, init=200, unit='mV')
        m.sum(f'{p}_orp_tx', [f'{p}_orp_m', f'{p}_orp_drift'], 'mV')
        m.hold(f'{p}_orp', f'{p}_orp_tx', f'iso_{p}_orp_complete', 'mV', f'00GCB2{n}CQ002')
        m.cmp(f'{p}_orp_h0', f'{p}_orp', '>', 250)
        m.cmp(f'{p}_orp_hh0', f'{p}_orp', '>', 300)
        m.AND(f'{p}_orp_h', [f'{p}_orp_h0', f'{p}_hp'])
        m.AND(f'{p}_orp_hh', [f'{p}_orp_hh0', f'{p}_hp'])
        m.cmp(f'{p}_orp_ok', f'{p}_orp', '<', 230)
        # chlorine on the membranes (W3): seconds of feed above 250 mV at flow; past a minute the polyamide is
        # oxidised (a fault of the scenario, only new membranes repair it; WATER-TREATMENT §7)
        m.tab(f'{p}_onfeed', st, [[0, 0], [1, 1], [3, 1], [4, 0]])     # flushing, starting, service: feed water
        m.prod(f'{p}_clx_add', [f'{p}_orp_h0', f'{p}_ff', f'{p}_onfeed'])
        # leaky (time constant 600 model seconds, a clock hour): trips handled one by one fade; a restart without the
        # fix keeps adding (time compressed, as the whole model: polyamide takes ~1,000 ppm·h, [FT])
        # (a lag of 600 × the input over 600 s: dx/dt = input − x/600)
        m.prod(f'{p}_clx_in', [f'{p}_clx_add', 600])
        m.lag(f'{p}_clx', f'{p}_clx_in', 600, init=0, unit='s')
        m.cmp(f'{p}_cl_dmg_c', f'{p}_clx', '>', 60)
        m.tab(f'{p}_dmg_k', f'{p}_dmg', [[0, 1], [1, 4]])
        # fouling (0–1): the colloids the feed's SDI brings, faster without antiscalant and acid; at design about a
        # tenth in a clock month, so cleaning (-10 % normalised flow, [FT] §6.3) comes after two to three months
        m.tab(f'{p}_fast_k', f'{p}_fast', [[0, 1], [1, 200]])
        m.prod(f'{p}_frate', [f'{p}_spd', 'sdi_k', 'scale_k', f'{p}_fast_k', 0.00014])
        # in three parts (W3; ours): colloids and biofilm (60 %), which the high-pH cleaning takes off; scale and
        # metal oxides (30 %), the low-pH's; and what no cleaning takes (10 %): a CIP restores most, not all
        f0 = 0.08 if x == 'a' else 0.05
        for part, share in (('bio', 0.6), ('sc', 0.3), ('irr', 0.1)):
            m.integ(f'{p}_{part}', f'{p}_{part}_in', round(DAY / 3600, 12), 0, 1, round(f0 * share, 9), 'pu')
        for part, share, k in (('bio', 0.6, 'cip_alk_k'), ('sc', 0.3, 'cip_acid_k')):
            m.prod(f'{p}_{part}_cl', [f'{p}_incirc', k, f'{p}_{part}'])
            m.prod(f'{p}_{part}_fr', [f'{p}_frate', share])
            m.sum(f'{p}_{part}_in', [f'{p}_{part}_fr', f'{p}_{part}_cl'])
        m.prod('{p}_irr_in'.format(p=p), [f'{p}_frate', 0.1])
        m.sum(f'{p}_foul', [f'{p}_bio', f'{p}_sc', f'{p}_irr'], 'pu')
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
        m.cmp(f'{p}_nflow_ok', f'{p}_nflow', '>=', 98)       # cleaned (W3)
        m.AND(f'{p}_nflow_l', [f'{p}_nflow_l0', f'{p}_is3'])
        # salt passage ~1.5 % (rejection ~98.5 %), worse fouled; four times that just after a start until flushed out;
        # a leaking O-ring passes feed straight into the permeate
        m.tab(f'{p}_pass', f'{p}_foul', [[0, 0.015], [1, 0.035]])
        m.lag(f'{p}_su', f'{p}_hp', 120, init=1 if x == 'a' else 0)
        m.tab(f'{p}_su_k', f'{p}_su', [[0, 4], [1, 1]])
        m.tab(f'{p}_leak_k', f'{p}_leak', [[0, 1], [1, 5]])
        m.prod(f'{p}_cond_sp', ['feed_cond', f'{p}_pass', f'{p}_su_k', f'{p}_leak_k', f'{p}_dmg_k'])
        m.lag(f'{p}_cond_m', f'{p}_cond_sp', 20, init=26.56 if x == 'a' else 102.4, unit='µS/cm')
        m.sum(f'{p}_cond_tx', [f'{p}_cond_m', f'{p}_cond_drift'], 'µS/cm')
        m.hold(f'{p}_cond', f'{p}_cond_tx', f'iso_{p}_cond_complete', 'µS/cm', f'00GCB2{n}CQ001')
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
        m.OR(f'{p}_tripped', [f'{p}_trip_suct_latched', f'{p}_trip_p_latched', f'{p}_trip_orp_latched',
                              f'{p}_trip_cip_t_latched'])
        m.AND(f'{p}_cip_hot', [f'{p}_incirc', 'cip_over'])
        m.NOT(f'{p}_no_trip', f'{p}_tripped')
        m.cmp(f'{p}_stopped', st, '<', 0.5)

    # ---------------------------------------------------------------- degasser and degassed water tank (§3 #10)
    # the tank's level: filled, drained, and the solution the flush sends to the pit (10 m³/h)
    m.sum('cip_fl_n', ['ro_a_isfl', 'ro_b_isfl'])
    m.prod('cip_fl_q', ['cip_fl_n', 10])
    m.sum('cip_out', ['cip_dr_q', 'cip_fl_q'])
    m.diff('cip_net', 'cip_fill_q', 'cip_out')
    m.OR('cip_busy', ['ro_a_incip', 'ro_b_incip'])     # the CIP skid serves one train at a time (W3)
    m.NOT('cip_free', 'cip_busy')
    m.OR('cip_pump', ['ro_a_incirc', 'ro_b_incirc'])
    m.AND('ro_b_cip_clash', ['ro_a_incip', 'ro_b_incip'])
    m.NOT('dg_fan_ok', 'dg_fault')
    m.AND('dg_run', ['dg_cmd', 'dg_fan_ok'])
    m.AND('dg_ol_c', ['dg_cmd', 'dg_fault'])
    m.tab('dg_sp', 'dg_run', [[0, 40], [1, 5]])        # CO2 left in the permeate, mg/L ([FT] p. 33; vendors 5–15)
    m.lag('dg_co2', 'dg_sp', 300, init=5, unit='mg/L', kks='00GCH10CQ001')
    m.cmp('dg_co2_h0', 'dg_co2', '>', 10)
    m.tab('co2_k', 'dg_co2', [[5, 1], [40, 3]])
    m.prod('perm_cond', ['feed_cond', 0.0166], 'µS/cm')     # the permeate in the degassed water tank, mixed
    m.sum('dg_in', ['ro_a_out', 'ro_b_out'], 'm³/h')
    m.cmp('dg_in_on', 'dg_in', '>=', 1)
    m.AND('dg_co2_h', ['dg_co2_h0', 'dg_in_on'])
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
        m.tab(f'{p}_resin_k', f'{p}_resin', [[0, 1], [1, 3]])     # a bed that has lost resin exhausts sooner (W3)
        m.prod(f'{p}_rate', [f'{p}_flow', 'perm_cond', 'co2_k', f'{p}_fast_k', f'{p}_resin_k',
                             round(1 / (72 * MB_FLOW * 26.56), 12)])
        # its regeneration (W3, [MB] p. 2–3): states 3–13 of its machine (MB_REGEN); three timed runs between the
        # operator's two holds, one timer over each
        idx = {name: k + 3 for k, (name, _) in enumerate(MB_REGEN)}
        mins = dict(MB_REGEN)
        for j, seg in enumerate((('backwash', 'settle', 'drain'), ('inject', 'displace', 'drain2'),
                                 ('air_mix', 'refill', 'rinse'))):
            lo, hi = idx[seg[0]], idx[seg[-1]]
            m.tab(f'{p}_sg{j}', st, [[lo - 0.5, 0], [lo, 1], [hi, 1]] + ([[hi + 0.5, 0]] if hi < idx['rinse'] else []))
            m.timer(f'{p}_tg{j}', f'{p}_sg{j}')
            t = 0
            for name in seg:
                t = round(t + clock_s(mins[name]), 1)
                m.cmp(f'{p}_{name}_done', f'{p}_tg{j}', '>=', t)
        m.tab(f'{p}_sb', st, [[1.5, 0], [2, 1], [2.5, 0]])
        for v, name in (('rdy', 'ready'), ('airrdy', 'air_ready')):
            m.tab(f'{p}_{v}', st, [[idx[name] - 0.5, 0], [idx[name], 1], [idx[name] + 0.5, 0]])
        m.tab(f'{p}_inregen', st, [[2.5, 0], [3, 1]])
        m.tab(f'{p}_isinj', st, [[idx['inject'] - 0.5, 0], [idx['inject'], 1], [idx['inject'] + 0.5, 0]])
        m.tab(f'{p}_inchem', st, [[idx['inject'] - 0.5, 0], [idx['inject'], 1], [idx['refill'], 1],
                                   [idx['refill'] + 0.5, 0]])
        # the regenerants take the exhaustion off: 40 clock minutes leave about 3 % of it
        m.integ(f'{p}_ex', f'{p}_rin', round(DAY / 3600, 12), 0, 1.2, 0.5 if x == 'a' else 0, 'pu')
        m.prod(f'{p}_regen_r', [f'{p}_isinj', f'{p}_ex', -5.5])
        m.sum(f'{p}_rin', [f'{p}_rate', f'{p}_regen_r'])
        m.tab(f'{p}_cond_sp', f'{p}_ex', [[0, 0.06], [0.9, 0.08], [1, 0.5], [1.2, 5]])
        m.lag(f'{p}_cond_lag', f'{p}_cond_sp', 60, init=0.07111111 if x == 'a' else 0.06, unit='µS/cm')
        # the regenerants left in the bed until the final rinse washes them out (about 20 clock minutes to 0.1 µS/cm;
        # the rinse lasts at least 30)
        m.prod(f'{p}_res_sp', [f'{p}_inchem', 100])
        m.lag(f'{p}_res', f'{p}_res_sp', 5, 25, 0, 'µS/cm')
        m.sum(f'{p}_cond', [f'{p}_cond_lag', f'{p}_res'], 'µS/cm', f'00GCF1{n}CQ001')
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
        m.AND(f'{p}_rinsed', [f'{p}_rinse_done', f'{p}_good'])
        # the water and the regenerants' excess each state sends to the neutralisation pit
        m.tab(f'{p}_wq', st, [[2, 0]] + [[idx[k], MB_WASTE.get(k, 0)] for k in idx], 'm³/h')
        m.tab(f'{p}_wc', st, [[idx['ready'], 0], [idx['inject'], MB_ACID['inject']],
                              [idx['displace'], MB_ACID['displace']], [idx['drain2'], 0]])
        # its outlet strainer: resin from a broken lateral blocks it (W3)
        m.tab(f'{p}_dp0', f'{p}_resin', [[0, 0.12], [1, 1.2]])
        m.prod(f'{p}_dp_sp', [f'{p}_dp0', f'{p}_flow', round(1 / MB_FLOW, 9)])
        m.lag(f'{p}_dp', f'{p}_dp_sp', 300, init=0.12 if x == 'a' else 0, unit='bar', kks=f'00GCF1{n}CP001')
        m.cmp(f'{p}_dp_h', f'{p}_dp', '>', 0.6)
        m.cmp(f'{p}_dp_hc', f'{p}_dp', '<', 0.5)
        # the isolation for work inside the bed: its feed pump stopped
        m.NOT(f'mf_{x}_off', f'mf_{x}_cmd')
        m.cmp(f'mf_{x}_still', f'mf_{x}_spd', '<', 0.01)
        m.AND(f'mf_{x}_safe', [f'mf_{x}_off', f'mf_{x}_still'])
        m.AND(f'{p}_taken', [f'mf_{x}_safe', f'{p}_sb'])          # out of service, ready to regenerate or isolate
    m.OR('mb_regen_any', ['mb_a_inregen', 'mb_b_inregen'])
    m.NOT('mb_regen_free', 'mb_regen_any')
    m.AND('mb_b_clash', ['mb_a_inregen', 'mb_b_inregen'])
    m.OR('mb_inj', ['mb_a_isinj', 'mb_b_isinj'])
    # the regenerant tanks: what an injection takes, a fill from the bulk delivery
    for c in ('hcl', 'naoh'):
        m.prod(f'gp_{c}_use', ['mb_inj', -REGEN_USE])
        m.prod(f'gp_{c}_fq', [f'gp_{c}_filling', 60])
        m.sum(f'gp_{c}_net', [f'gp_{c}_use', f'gp_{c}_fq'])
        m.cmp(f'gp_{c}_ok', f'gp_{c}_lvl', '>', 15)
        m.cmp(f'gp_{c}_l', f'gp_{c}_lvl', '<', 20)
        m.cmp(f'gp_{c}_lc', f'gp_{c}_lvl', '>', 25)
        m.cmp(f'gp_{c}_full', f'gp_{c}_lvl', '>=', 95)
    m.sum('dg_out', ['mb_a_out', 'mb_b_out', 'cip_fill_q'])   # a recirculating bed's water comes back to the tank
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
    # what comes in: the laboratory's and sample panel's drains (3 m³/h), the CIP tank's drain and the RO flush after
    # a cleaning, a regenerating mixed bed's wastes (W3)
    m.sum('nr_in', [3, 'cip_dr_q', 'ro_a_fl_q', 'ro_b_fl_q', 'mb_a_wq', 'mb_b_wq'], 'm³/h')
    m.diff('nr_net', 'nr_in', 'nr_dis')
    # its pH from its excess of base (W3: the wastes' acid and caustic, the batch's dosing; NR_PH)
    m.tab('nr_ph_true', 'nr_alk', NR_PH, 'pH')
    m.prod('nr_ph_off', ['nr_drift', -3])                # a probe drifted 3 pH low (W3: enough to fool the batch)
    m.sum('nr_ph_sp', ['nr_ph_true', 'nr_ph_off'])
    m.lag('nr_ph', 'nr_ph_sp', 60, init=7.2, unit='pH', kks='00GNR10CQ001')
    m.cmp('nr_ph_lo', 'nr_ph', '>=', 6)
    m.cmp('nr_ph_hi', 'nr_ph', '<=', 9)
    m.AND('nr_ph_ok', ['nr_ph_lo', 'nr_ph_hi'])
    m.NOT('nr_ph_bad', 'nr_ph_ok')
    # the neutralisation batch's dosing (machine nr_batch): caustic below pH 7, acid above 7.4, more the further off,
    # kmol a clock hour (ours)
    m.tab('nr_caus_sp', 'nr_ph', [[3, 0.6], [5, 0.15], [6.5, 0.03], [7, 0]])
    m.tab('nr_acid_sp', 'nr_ph', [[7.4, 0], [8, 0.03], [9.5, 0.15], [11, 0.6]])
    m.prod('nr_caus_q', ['nr_auto', 'nr_caus_sp'])
    m.prod('nr_acid_q', ['nr_auto', 'nr_acid_sp'])
    m.cmp('nr_caus_on', 'nr_caus_q', '>', 0.001)
    m.cmp('nr_acid_on', 'nr_acid_q', '>', 0.001)
    m.diff('nr_dose', 'nr_caus_q', 'nr_acid_q')
    m.sum('nr_alk_in', ['cip_dr_chem', 'ro_a_fl_chem', 'ro_b_fl_chem', 'mb_a_wc', 'mb_b_wc', 'nr_dose'])
    m.cmp('nr_ph_mid0', 'nr_ph', '>=', 6.5)
    m.cmp('nr_ph_mid1', 'nr_ph', '<=', 8.5)
    m.AND('nr_ph_mid', ['nr_ph_mid0', 'nr_ph_mid1'])
    m.tab('nr_ismix', 'nr_batch_state', [[1.5, 0], [2, 1], [2.5, 0]])
    m.timer('nr_tm', 'nr_ismix')
    m.cmp('nr_mixed', 'nr_tm', '>=', clock_s(10))
    m.cmp('nr_has', 'nr_lvl', '>=', 10)                 # as nr_lvl_ok (the pumps' start), computed here
    m.AND('nr_mix_ok', ['nr_mixed', 'nr_ph_ok', 'nr_has'])
    m.NOT('nr_lvl_lo', 'nr_has')
    m.AND('nr_mix_dry', ['nr_mixed', 'nr_ph_ok', 'nr_lvl_lo'])
    m.AND('nr_mix_bad', ['nr_mixed', 'nr_ph_bad'])
    m.cmp('nr_room', 'nr_lvl', '<', 60)
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
                                        'flush': {'from': ['stopped'], 'to': 'stopping'},
                                        'clean': {'from': ['stopped'], 'to': 'cip_circ1'},
                                        'stop_cleaning': {'from': ['cip_circ1', 'cip_circ2', 'cip_soak'],
                                                          'to': 'cip_flush'}},
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
                                       'say': 'Flushing with permeate until the concentrate matches the feed'},
                                      # its cleaning (W3; [FT] §6.3): one stage at a time, a soak, the flush
                                      {'id': 'cip_circ1', 'watch': False,
                                       'next': ([['ro_b_cip_clash', 'stopped']] if x == 'b' else []) +
                                               [[f'{p}_c1', 'cip_circ2']],
                                       'say': 'Cleaning: the solution recirculates through the first stage, 6–10 m³/h '
                                              'a vessel, under 4 bar'},
                                      {'id': 'cip_circ2', 'watch': False, 'next': [[f'{p}_c2', 'cip_soak']],
                                       'say': 'Cleaning: the solution recirculates through the second stage'},
                                      {'id': 'cip_soak', 'watch': False, 'next': [[f'{p}_c3', 'cip_flush']],
                                       'say': 'Cleaning: the elements soak in the solution'},
                                      {'id': 'cip_flush', 'watch': False, 'next': [[f'{p}_fl_done', 'stopped']],
                                       'say': 'Flushing the cleaning solution out with permeate to the neutralisation pit'}]})
        m.op(code, 'start', None,
             [(f'{p}_no_trip', 'An RO trip is latched: reset it first'),
              (f'{p}_suct_ok', 'Suction pressure below 1.5 bar: no service water pump, or the cartridge filter is blocked'),
              ('sbs_on', 'Sodium bisulphite dosing not running: chlorine would reach the membranes'),
              ('as_on', 'Antiscalant dosing not running: the membranes would scale'),
              ('dg_room', 'Degassed water tank full')], machine=p)
        m.op(code, 'stop', None, (), machine=p)
        m.op(code, 'flush', None, [(f'{p}_no_trip', 'An RO trip is latched: reset it first'),
                                   ('sw_p_ok', 'No service water pressure to flush with')], machine=p)
        m.op(code, 'clean', None, [(f'{p}_no_trip', 'An RO trip is latched: reset it first'),
                                   ('cip_ready', 'The cleaning solution is not ready: the CIP tank dosed and at its pH, '
                                                 'a high-pH solution warmed to 30–35 °C'),
                                   ('cip_free', 'The other train is being cleaned: the CIP skid serves one at a time'),
                                   ('cip_has', 'The CIP tank is nearly empty: fill and dose it again')],
             machine=p)
        m.op(code, 'stop_cleaning', None, (), machine=p)
        stop = [{'machine': p, 'to': 'stopped'}]
        L = x.upper()
        m.trip(f'{p}_trip_suct', f'00GCB2{n}CP002', f'RO {L}: high-pressure pump suction pressure low-low',
               f'{p}_suct_ll', stop, 'PALL', 2, p)
        m.trip(f'{p}_trip_p', f'00GCB2{n}CP001', f'RO {L}: feed pressure high-high', f'{p}_p_hh', stop, 'PAHH', 2, p)
        m.trip(f'{p}_trip_orp', f'00GCB2{n}CQ002', f'RO {L}: feed ORP high-high (chlorine)', f'{p}_orp_hh', stop,
               'QAHH', 10, p)
        m.trip(f'{p}_trip_cip_t', '00GCB30CT001', f'RO {L} cleaning: solution over the membranes\' limit (high pH 36.5 °C, any 40 °C)',
               f'{p}_cip_hot', [{'machine': p, 'to': 'cip_flush'}], 'TAHH', 2, p)
        m.interlock(f'{p}_to_drain', f'{p}_cond_hd', [{'set': {f'{p}_bad': 1}}], f'00GCB2{n}CQ001',
                    f'RO {L} permeate conductivity high: permeate to drain')
        m.interlock(f'{p}_to_service', f'{p}_good_again', [{'set': {f'{p}_bad': 0}}], f'00GCB2{n}CQ001',
                    f'RO {L} permeate good again: back to the degasser')
    m.op('00GCH10AN001', 'start', {'dg_cmd': 1}, [('dg_fan_ok', 'The motor has a fault: it needs repair before a start')])
    m.op('00GCH10AN001', 'stop', {'dg_cmd': 0})
    m.trip('dg_trip_ol', '00GCH10AN001', 'Degasser blower: motor overload', 'dg_ol_c', [{'set': {'dg_cmd': 0}}], None,
           0.5)
    m.alarm('dg_tripped', '00GCH10AN001', 'Degasser blower tripped', 'dg_trip_ol_latched', 2)
    # the CIP skid (W3): its tank's sequence, the heater
    m.machines.append({'id': 'cip', 'kks': '00GCB30BB001', 'init': 'empty',
                       'commands': {'fill': {'from': ['empty'], 'to': 'filling'},
                                    'add_caustic': {'from': ['water'], 'to': 'alkaline'},
                                    'add_acid': {'from': ['water'], 'to': 'acid'},
                                    'drain': {'from': ['water', 'alkaline', 'acid'], 'to': 'draining'}},
                       'states': [{'id': 'empty', 'set': {'cip_fill': 0, 'cip_drain': 0, 'cip_chem': 0},
                                   'watch': False},
                                  {'id': 'filling', 'set': {'cip_fill': 1}, 'next': [['cip_full', 'water'], ['dg_ll', 'water']],
                                   'say': 'Filling with RO permeate from the degassed water tank'},
                                  {'id': 'water', 'set': {'cip_fill': 0}, 'watch': False},
                                  {'id': 'alkaline', 'set': {'cip_chem': 1}, 'watch': False,
                                   'say': 'Caustic soda dosed and mixed: 0.1 % NaOH, pH 12'},
                                  {'id': 'acid', 'set': {'cip_chem': 2}, 'watch': False,
                                   'say': 'Hydrochloric acid dosed and mixed: 0.2 % HCl, pH 2'},
                                  {'id': 'draining', 'set': {'cip_drain': 1}, 'next': [['cip_empty', 'empty']],
                                   'say': 'Draining to the neutralisation pit'}]})
    m.op('00GCB30BB001', 'fill', None, [('dg_ok', 'Degassed water tank below 20 %: no permeate to fill with')],
         machine='cip')
    m.op('00GCB30BB001', 'add_caustic', None, [('gp_naoh_ok', 'The caustic tank is below 15 %')], machine='cip')
    m.op('00GCB30BB001', 'add_acid', None, [('gp_hcl_ok', 'The acid tank is below 15 %')], machine='cip')
    m.op('00GCB30BB001', 'drain', None, [('cip_free', 'An RO train is being cleaned with it')], machine='cip')
    m.op('00GCB30AH001', 'start', {'cip_heat_cmd': 1}, [('cip_has', 'The CIP tank is nearly empty: the heater would '
                                                                    'burn out')])
    m.op('00GCB30AH001', 'stop', {'cip_heat_cmd': 0})
    for x, n in (('a', 1), ('b', 2)):
        p = f'mb_{x}'
        code = f'00GCF1{n}AT001'
        L = x.upper()
        says = {'backwash': 'Backwash: the bed expands and the lighter anion resin separates above the cation resin',
                'settle': 'Settling: the two resins in their layers', 'drain': 'Draining down to the bed',
                'ready': 'Ready for the regenerants: start their injection',
                'inject': 'Acid (5 % HCl) from below and caustic (4 % NaOH) from above, together, out at the '
                          'interface collector',
                'displace': 'Slow rinse: three bed volumes push the regenerants out',
                'drain2': 'Draining down for the air mix',
                'air_ready': 'Ready for the air mix: start the resin mixing blower, then the air mix',
                'air_mix': 'Air mixing the two resins together', 'refill': 'Refilling slowly: the resins stay mixed',
                'rinse': 'Final rinse to the pit until the outlet is under 0.1 µS/cm'}
        nxt = {'backwash': (([['mb_b_clash', 'standby']] if x == 'b' else []) + [[f'{p}_backwash_done', 'settle']]),
               'settle': [[f'{p}_settle_done', 'drain']], 'drain': [[f'{p}_drain_done', 'ready']],
               'inject': [[f'{p}_inject_done', 'displace']], 'displace': [[f'{p}_displace_done', 'drain2']],
               'drain2': [[f'{p}_drain2_done', 'air_ready']], 'air_mix': [[f'{p}_air_mix_done', 'refill']],
               'refill': [[f'{p}_refill_done', 'rinse']], 'rinse': [[f'{p}_rinsed', 'standby']]}
        regen = []
        for name, _ in MB_REGEN:
            st_ = {'id': name, 'watch': False, 'say': says[name]}
            if name in nxt:
                st_['next'] = nxt[name]
            if name == 'refill':
                st_['set'] = {'gp_air_cmd': 0}          # the sequence stops the blower
            regen.append(st_)
        m.machines.append({'id': p, 'kks': code, 'init': 'service' if x == 'a' else 'standby',
                           'commands': {'in_service': {'from': ['recirc', 'standby'], 'to': 'service'},
                                        'recirculate': {'from': ['service', 'standby'], 'to': 'recirc'},
                                        'standby': {'from': ['service', 'recirc'], 'to': 'standby'},
                                        'regenerate': {'from': ['standby'], 'to': 'backwash'},
                                        'inject': {'from': ['ready'], 'to': 'inject'},
                                        'air_mix': {'from': ['air_ready'], 'to': 'air_mix'}},
                           'states': [{'id': 'service', 'watch': False},
                                      {'id': 'recirc', 'watch': False,
                                       'say': 'Recirculating to the degassed water tank: the outlet is not good'},
                                      {'id': 'standby', 'watch': False}] + regen})
        m.op(code, 'in_service', None, [(f'{p}_good', 'Outlet conductivity above 0.1 µS/cm: the bed needs '
                                                     'regeneration')], machine=p)
        m.op(code, 'recirculate', None, (), machine=p)
        m.op(code, 'standby', None, (), machine=p)
        m.op(code, 'regenerate', None, [(f'mf_{x}_off', f'Mixed bed feed pump {L} runs: stop it first'),
                                        ('mb_regen_free', 'The other bed is being regenerated: one at a time'),
                                        ('nr_room', 'Neutralisation pit above 60 %: no room for the wastes')],
             machine=p)
        m.op(code, 'inject', None, [('gp_hcl_ok', 'The acid tank is below 15 %'),
                                    ('gp_naoh_ok', 'The caustic tank is below 15 %')], machine=p)
        m.op(code, 'air_mix', None, [('gp_air_cmd', 'The resin mixing blower is not running')], machine=p)
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
    # the neutralisation batch (W3; WATER-TREATMENT §5): dose to pH 6.5–8.5 with the agitator running, mix, check,
    # discharge until the pit is low
    m.machines.append({'id': 'nr_batch', 'kks': '00GNR10BB001', 'init': 'idle',
                       'commands': {'neutralise': {'from': ['idle'], 'to': 'dosing'},
                                    'stop_batch': {'from': ['dosing', 'mixing', 'discharging'], 'to': 'idle'}},
                       'states': [{'id': 'idle', 'set': {'nr_auto': 0, 'nr_mix_cmd': 0}, 'watch': False},   # the batch's end stops
                                  {'id': 'dosing', 'set': {'nr_auto': 1, 'nr_mix_cmd': 1},  # the agitator it started
                                   'next': [['nr_ph_mid', 'mixing']],
                                   'say': 'Dosing acid or caustic to bring the pit to pH 6.5–8.5'},
                                  {'id': 'mixing', 'set': {'nr_auto': 0},
                                   'next': [['nr_mix_bad', 'dosing'], ['nr_mix_ok', 'discharging'], ['nr_mix_dry', 'idle']],
                                   'say': 'Mixing, then checking the pH'},
                                  {'id': 'discharging', 'set': {'nr_a_cmd': 1},
                                   'next': [['nr_low', 'idle'], ['nr_ph_bad', 'dosing']],
                                   'say': 'Discharging at pH 6–9 until the pit is low'}]})
    m.op('00GNR10BB001', 'neutralise', None, [('nr_lvl_ok', 'Pit level below 10 %: nothing to neutralise')],
         machine='nr_batch')
    m.op('00GNR10BB001', 'stop_batch', {'nr_a_cmd': 0}, (), machine='nr_batch')
    # the mixed beds' regeneration (W3): the resin mixing blower, the regenerant tanks' fills from the bulk delivery
    m.start_stop('00GCP30AN001', 'gp_air', ok=False)
    for c, code, what in (('hcl', '00GCP10BB001', 'acid'), ('naoh', '00GCP20BB001', 'caustic')):
        mid = f'gp_{c}_fill'
        m.machines.append({'id': mid, 'kks': code, 'init': 'idle',
                           'commands': {'fill': {'from': ['idle'], 'to': 'filling'},
                                        'stop_fill': {'from': ['filling'], 'to': 'idle'}},
                           'states': [{'id': 'idle', 'set': {f'gp_{c}_filling': 0}, 'watch': False},
                                      {'id': 'filling', 'set': {f'gp_{c}_filling': 1},
                                       'next': [[f'gp_{c}_full', 'idle']], 'watch': False,
                                       'say': f'Filling the {what} tank from the bulk delivery'}]})
        m.op(code, 'fill', None, (), machine=mid)
        m.op(code, 'stop_fill', None, (), machine=mid)
        m.alarm(f'gp_{c}_low', code, f'Regeneration {what} tank low', f'gp_{c}_l', 3, isa='LAL', clear=f'gp_{c}_lc')
    # permits to work (PLANT3D §15) where hands go inside the equipment (STAFF.md): a mixed bed's internals, an RO
    # train's membranes
    for x, n in (('a', 1), ('b', 2)):
        L = x.upper()
        bed, pump = f'00GCF1{n}AT001', f'00GCK10AP00{n}'
        m.isolation(f'iso_mb_{x}', f'Mixed bed {L}: feed pump supply and the vessel',
                    [(pump, 'electrical', f'mf_{x}_safe', 'Feed pump stopped; its breaker racked out, locked and tagged'),
                     (bed, 'process', f'mb_{x}_sb', 'Bed in standby and drained; inlet, outlet and regenerant valves '
                                                   'closed, locked and tagged')])
        m.work(f'wo_mb_{x}_resin', bed, f'Mixed bed {L}: underdrain lateral replaced, resin topped up', 'mech',
               'confined', f'iso_mb_{x}', f'mb_{x}_resin')
        ro = f'00GCB2{n}AT001'
        m.isolation(f'iso_ro_{x}', f'RO train {L}: the train and its high-pressure pump',
                    [(ro, 'process', f'ro_{x}_stopped', 'Train stopped and drained; feed, permeate and concentrate '
                                                       'valves closed, locked and tagged; the high-pressure pump\'s '
                                                       'breaker racked out')])
        m.work(f'wo_ro_{x}_membranes', ro, f'RO train {L}: membrane elements replaced', 'mech', 'general',
               f'iso_ro_{x}', f'ro_{x}_cl_damage')
        # milestone S3: the cartridges changed with the RO train isolated (its high-pressure pump draws through them),
        # and the train's analysers calibrated with it off line (its ORP trip and its permeate dump read them)
        m.work(f'wo_cart_{x}', f'00GCB1{n}AT001', f'Cartridge filter {L}: cartridges changed', 'mech', 'general',
               f'iso_ro_{x}', f'cart_{x}_clog')
        for a, what, code in (('orp', 'feed ORP analyser', f'00GCB2{n}CQ002'),
                              ('cond', 'permeate conductivity analyser', f'00GCB2{n}CQ001')):
            m.isolation(f'iso_ro_{x}_{a}', f'RO train {L}: its {what}',
                        [(code, 'instrument', f'ro_{x}_stopped', 'The analyser\'s sample valve shut and tagged; the RO '
                                                                 'train off line')])
            m.work(f'wo_ro_{x}_{a}_cal', code, f'RO train {L} {what}: calibration', 'inst', 'general',
                   f'iso_ro_{x}_{a}', f'ro_{x}_{a}_drift')
    m.start_stop('00GBS20AT001', 'fp', ok=False)

    # ---------------------------------------------------------------- alarms (§6)
    m.alarm('cg_low', '00GBN10BB001', 'Coagulant day tank low', 'cg_l', 3, isa='LAL', clear='cg_lc')
    for x, code in (('a', '00GBD11CQ001'), ('b', '00GBD12CQ001')):
        m.alarm(f'cl{x}_ntu_h', code, f'Clarifier {x.upper()}: clarified water turbidity high', f'cl{x}_h', 2,
                isa='QAH', clear=f'cl{x}_hc')
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
    # W3
    m.alarm('fl_ntu_h', '00GBB10', 'Filtered water turbidity high (a filter breaks through)', 'fl_ntu_h', 2, isa='QAH',
            clear='fl_ntu_hc')
    for pre, code, what in (('cg', '00GBN10AP001', 'Coagulant'), ('sbs', '00GCN10AP001', 'Sodium bisulphite'),
                            ('as', '00GCN20AP001', 'Antiscalant')):
        m.AND(f'{pre}_a_noflow', [f'{pre}_a_cmd', f'{pre}_a_fault'])
        m.alarm(f'{pre}_a_noflow', code, f'{what} dosing pump A: no flow', f'{pre}_a_noflow', 2, isa='FAL', delay=5)
    m.alarm('dg_co2_h', '00GCH10CQ001', 'Degassed water carbon dioxide high', 'dg_co2_h', 3, isa='QAH', delay=10)
    m.alarm('cip_t_h', '00GCB30CT001', 'CIP solution temperature high', 'cip_t_h', 2, isa='TAH', clear='cip_t_hc')
    for x, n in (('a', 1), ('b', 2)):
        m.alarm(f'mb_{x}_dp_h', f'00GCF1{n}CP001', f'Mixed bed {x.upper()} outlet strainer differential pressure high',
                f'mb_{x}_dp_h', 2, f'00GCF1{n}AT001', 'PDAH', f'mb_{x}_dp_hc')

    # ---------------------------------------------------------------- what is seen and heard
    m.b(kks='00GBD10AM001', sound='motor_small', gain={'of': 'mx_cmd', 'table': [[0, 0], [1, 0.4]]})
    for x, n in (('a', 1), ('b', 2)):
        for pre, sys in (('cg', '00GBN10'), ('pl', '00GBN20'), ('sbs', '00GCN10'), ('as', '00GCN20'),
                         ('ac', '00GCE10')):
            # a failed pump (coagulant, bisulphite and antiscalant A) shows stopped
            run = f'{pre}_a_run' if x == 'a' and pre in ('cg', 'sbs', 'as') else f'{pre}_{x}_cmd'
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
        # a mixed bed's manhole gas test (a confined-space permit's air test before anyone goes in, PLANT3D §15.2):
        # the portable detector's oxygen reading, normal air in the vessel ventilated for the work
        m.b(kks=f'00GCF1{n}CQ003', show=f'mb_{x}_o2')
        m.b(kks=f'00GCL10CL00{n}', show=f'dt_{x}_lvl')
        m.b(kks=f'00GNR10AP00{n}', lamp='running', of=f'nr_{x}_cmd')
    # what the chemists and the WTP operator read on their rounds and in the laboratory (milestone S3): the SDI at
    # the sample panel, the filtered water turbidity at the filter bank, the dosing and regenerant tanks' levels
    m.b(kks='00QUG10', show='sdi')
    m.b(kks='00GBB10', show='fl_ntu')
    m.b(kks='00GBN10BB001', show='cg_lvl')
    m.b(kks='00GCP10BB001', show='gp_hcl_lvl')
    m.b(kks='00GCP20BB001', show='gp_naoh_lvl')
    m.b(kks='00GCH10AN001', anim='shaft', of='dg_run', scale=25)
    m.b(kks='00GCH10AN001', sound='motor_small', gain={'of': 'dg_run', 'table': [[0, 0], [1, 0.6]]})
    m.b(kks='00GCH10AN001', lamp='running', of='dg_run')
    m.b(kks='00GCH10CQ001', show='dg_co2')
    # W3: the CIP skid, the resin mixing blower, the mixed beds' strainers, the pit's dosing
    m.b(kks='00GCB30AP001', anim='shaft', of='cip_pump', scale=49.3)
    m.b(kks='00GCB30AP001', sound='motor_small', gain={'of': 'cip_pump', 'table': [[0, 0], [1, 0.7]]})
    m.b(kks='00GCB30AP001', lamp='running', of='cip_pump')
    m.b(kks='00GCB30AH001', lamp='running', of='cip_heat_on')
    m.b(kks='00GCB30CT001', show='cip_t')
    m.b(kks='00GCB30CQ001', show='cip_ph')
    m.b(kks='00GCP30AN001', anim='shaft', of='gp_air_cmd', scale=25)
    m.b(kks='00GCP30AN001', sound='motor_small', gain={'of': 'gp_air_cmd', 'table': [[0, 0], [1, 0.8]]})
    m.b(kks='00GCP30AN001', lamp='running', of='gp_air_cmd')
    for x, n in (('a', 1), ('b', 2)):
        m.b(kks=f'00GCF1{n}CP001', show=f'mb_{x}_dp')
    m.b(kks='00GNR20AP001', lamp='running', of='nr_acid_on')
    m.b(kks='00GNR30AP001', lamp='running', of='nr_caus_on')
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
    """The trainer's faults, and W3's conditional ones: an RO train's membranes damaged by chlorine (WATER-TREATMENT
    §7: a restart without fixing the bisulphite dosing), which only new membranes repair (its work)."""
    from train_content import fault
    out = []
    for f, s, t in FAULTS:
        x = fault(f, s, t, state_kks)
        if f in BY_WORK:
            x.pop('kks', None)
        out.append(x)
    for x in 'ab':
        out.append({'id': f'ro_{x}_cl_damage', 'set': {f'ro_{x}_dmg': 1},
                    'text': f'RO {x.upper()}: the membranes oxidised by chlorine pass salt (new membranes needed)',
                    'when': f'ro_{x}_cl_dmg_c', 'repair': {f'ro_{x}_dmg': 0}})
    return out
