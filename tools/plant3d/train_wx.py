"""The weather in the first train's model (docs/plant3d/REALISM.md §5.2, §5.7; milestone WX2): the gas turbine's
output and heat rate against the air's temperature, its inlet filters loaded by the dust and pulse-cleaned, its
compressor fouled by dust and damp air and washed online or offline, the cooling tower's approach against the wet
bulb and ice on its fans on frosty nights, an outdoor transmitter's impulse line that freezes, water in a junction box
with a poor gland in the rain, lightning counted by the step-up transformer's surge arrester and a strike's surge
reaching an exposed instrument loop, and the dust in the excitation cabinet's air filters.

Every number is invented, round and plausible for the class of machine, from public sources:
- [GER3567] GE GER-3567H, "GE Gas Turbine Performance Characteristics": a heavy-duty machine's output and heat rate
  against compressor inlet temperature (its figure 3: about 0.5-0.9 % of output per °C), and the inlet pressure drop's
  cost (10 mbar, 4 in. of water: 1.42 % of output, 0.45 % of heat rate);
- [GER3620] GE GER-3620P, "Heavy-Duty Gas Turbine Operating and Maintenance Considerations": inlet filtration, pulse
  self-cleaning filters in dusty sites, compressor fouling (a few % of output between washes), online washing at load
  and offline (crank) washing with the wheel spaces cooled;
- manufacturers' published data for self-cleaning pulse cartridge filter houses (a clean pressure drop of about
  2.5 mbar, pulsing on demand from about 6 mbar, a final pressure drop near 10 mbar);
- [Perry], [CTI]: a counterflow tower's approach growing as the wet bulb falls (less heat taken per kelvin by cold
  air); ice on the fan blades and stacks on freezing nights;
- [Liptak]: impulse lines without heat tracing freezing; [IEC60529], [IEC62444]: cable glands and the ingress of
  water; [NFPA850]: lightning protection, surge arresters and their counters.

The rating stays FIRST-TRAIN's: about 250 MW at 35 °C. The load setpoint's top stays 250 MW (the generator's and the
step-up transformer's rating), so a cool day shows as a lower heat rate and a margin, a hot one as less output: base
load (`gt1_at_base`) is 250 MW or, when the day gives less, the most it gives.
"""

# ------------------------------------------------------------------------------------------------ the gas turbine
# GER-3567's curve (a heavy-duty single-shaft machine) as factors of the 35 °C rating
AMB_OUT = [[-10, 1.263], [0, 1.212], [15, 1.117], [25, 1.061], [35, 1.0], [45, 0.939], [50, 0.905]]
AMB_HR = [[-10, 0.940], [0, 0.950], [15, 0.964], [25, 0.982], [35, 1.0], [45, 1.020], [50, 1.032]]
HR_35 = 9750            # kJ/kWh at base load and 35 °C (an F-class machine's ISO figure about 9,400, + 3.7 %)
HR_LF = [[0, 3.0], [0.1, 2.5], [0.3, 1.45], [0.5, 1.2], [0.75, 1.07], [1, 1.0]]     # part load (generic)
RATING = 250
INV_CAP = [[c, round(1 / c, 9)] for c in range(100, RATING + 1, 5)]     # 1/MW, by 5 MW (0.06 % at most off)
AIR_DENSITY = 1.15      # kg/m³ (the exhaust's mass flow stands for the air's: its fuel is about 2 %)
# the filter house (pulse cartridges, at full flow): the clean media, the cake that pulsing removes, the residue
# that only new cartridges remove (a share of what is caught). Both follow the dust the weather brings, hour for hour:
# not the training rate, which compresses the calendar between storms, not a storm (the scenario's age gives the
# residue of the months before)
DP_CLEAN = 2.5          # mbar
CAKE = [[0, 0], [20, 4], [60, 14], [100, 26]]       # kg of cake → mbar
RESIDUE = [[0, 0], [100, 2], [200, 5], [400, 12]]   # kg of residue → mbar
RESIDUE_SHARE = 0.02
PULSE_AT, DP_H, DP_HH, DP_RESET = 6.5, 9, 11, 7     # mbar: pulsing on demand, alarm, runback, runback cleared
DP_DELAY = 30                                       # s: the alarm's and the runback's delay
RUNBACK_MW = 150
# (q / 620 kg/s)² as a table: the pressure drop goes with the square of the flow
FLOW_SQ = [[q, round((q / 620) ** 2, 6)] for q in (0, 100, 200, 300, 400, 500, 620, 700)]
DP_OUT = [[0, 1.00355], [DP_CLEAN, 1.0], [12.5, 0.9858], [30, 0.961]]    # 1.42 % a 10 mbar
DP_HR = [[0, 0.99887], [DP_CLEAN, 1.0], [12.5, 1.0045], [30, 1.01238]]  # 0.45 % a 10 mbar
# compressor fouling, in equivalent hours of firing (× the training rate), faster in dust (the fine dust the filters
# pass) and damp air (it makes the deposits stick): the share an online wash removes levels off within days; the rest
# grows until an offline wash
F_DUST = [[0, 0.7], [0.2, 1], [1.5, 2], [10, 5]]
F_DAMP = [[0, 1.6], [5, 1.2], [12, 1]]                 # by the wet-bulb depression (K)
FOUL_ON = [[0, 1], [100, 0.99], [200, 0.983], [400, 0.976], [800, 0.973]]
FOUL_OFF = [[0, 1], [1000, 0.99], [3000, 0.972], [6000, 0.958]]
FOUL_HR = [[0.9, 1.05], [1, 1]]                        # half the output lost shows in the heat rate
WASH_ON_S, WASH_OFF_S = 600, 1800                       # model seconds: the online wash; the offline soak, rinse, dry
WASH_LOAD = 150                                         # MW: online washing at high load ([GER3620])
WS_WASH = 95                                            # °C: the wheel spaces cool enough for water (offline)
# the excitation cabinet (in the GT's electrical package, ventilated with filtered outside air)
CAB_DUST = [[0, 0.5], [0.2, 1], [1.5, 2], [10, 6]]
CAB_RISE = [[0, 4], [2000, 6], [5000, 12], [8000, 22]]  # K over the air by the filters' equivalent hours
CAB_H = 55                                              # °C: the electronics' alarm

# ------------------------------------------------------------------------------------------------ the cooling tower
APPROACH_WB = [[-5, 2.0], [5, 1.6], [15, 1.3], [25, 1.0], [32, 0.85]]  # × the approach at the design 25 °C
ICE = [[-3, 6], [0, 2.5], [2, 0]]                       # mm/s on a running fan's probe by the air's °C
ICE_TAU = 600                                           # s (an hour of the clock): the ice builds and melts
LINE_TAU = 600                                          # s (an hour of the clock): the basin level transmitter's impulse line cools
JB_RAIN = [[0, 3], [0.5, 10], [1, 30]]                  # mm of rain before the water reaches the terminals
STRIKE_GAP = [[0, 120], [0.5, 1000], [1, 4000]]         # clock seconds of storm between strikes near the plant
STRIKE_N = [[0, 1], [0.5, 3], [1, 12]]                  # the strike whose surge reaches fan 9's loop
INGRESS_FAN, SURGE_FAN = 7, 9
FAN_TRIP = 10


def gt_values(m):
    """In gt1, after the exhaust and before the load (the capability caps the load)."""
    m.tab('gt1_amb_f', 'ambient_t', AMB_OUT)
    # the inlet filters
    # the air through the filter house: the exhaust's flow (computed further on: read through a lag of a second, as
    # the previous step left it)
    m.lag('gt1_air_q', 'gt1_exh_flow', 1, unit='kg/s')
    m.prod('gt1_cake_rate', ['dust', 'gt1_air_q', round(1e-6 / AIR_DENSITY, 12)], 'kg/s')
    m.v('gt1_filt_cake', {'wear': 'gt1_cake_rate', 'max': 100, 'reset': 'gt1_pulse'}, 'kg')
    m.prod('gt1_res_rate', ['gt1_cake_rate', RESIDUE_SHARE], 'kg/s')
    m.v('gt1_filt_res', {'wear': 'gt1_res_rate', 'max': 1000}, 'kg')
    m.tab('gt1_flow_sq', 'gt1_air_q', FLOW_SQ)
    m.tab('gt1_dp_cake', 'gt1_filt_cake', CAKE, 'mbar')
    m.tab('gt1_dp_res', 'gt1_filt_res', RESIDUE, 'mbar')
    m.sum('gt1_dp_k', [DP_CLEAN, 'gt1_dp_cake', 'gt1_dp_res'], 'mbar')
    m.prod('gt1_filt_dp', ['gt1_dp_k', 'gt1_flow_sq'], 'mbar', '10MBL10AT001')
    m.cmp('gt1_pulse_need', 'gt1_filt_dp', '>=', PULSE_AT)
    m.NOT('gt1_pulse_ok', 'gt1_pulse_fail')
    m.AND('gt1_pulse', ['gt1_pulse_need', 'gt1_pulse_ok'])
    m.cmp('gt1_dp_h', 'gt1_filt_dp', '>', DP_H)
    m.cmp('gt1_dp_hh', 'gt1_filt_dp', '>=', DP_HH)
    m.cmp('gt1_dp_lo', 'gt1_filt_dp', '<', DP_RESET)
    # the alarm and the runback wait 30 s, as a filter house's switches do: a clock jump's dust arrives in one step,
    # before the next step's pulse has cleaned it off
    m.delay('gt1_dp_h_d', 'gt1_dp_h', DP_DELAY)
    m.delay('gt1_dp_hh_d', 'gt1_dp_hh', DP_DELAY)
    m.latch('gt1_dp_rb', 'gt1_dp_hh_d', 'gt1_dp_lo')
    m.tab('gt1_dp_rb_cap', 'gt1_dp_rb', [[0, RATING], [1, RUNBACK_MW]], 'MW')
    m.tab('gt1_dp_f', 'gt1_filt_dp', DP_OUT)
    # compressor fouling
    m.tab('gt1_f_dust', 'dust', F_DUST)
    m.diff('gt1_wb_dep', 'ambient_t', 'ambient_wb', 'K')
    m.tab('gt1_f_damp', 'gt1_wb_dep', F_DAMP)
    m.prod('gt1_foul_rate', ['gt1_flame', 'age_h', 'gt1_f_dust', 'gt1_f_damp'], 'h/s')
    m.v('gt1_foul_on', {'wear': 'gt1_foul_rate', 'max': 100000, 'reset': 'gt1_wash_done'}, 'h')    # either wash
    m.v('gt1_foul_off', {'wear': 'gt1_foul_rate', 'max': 100000, 'reset': 'gt1_wash_off_done'}, 'h')
    m.tab('gt1_foul_on_f', 'gt1_foul_on', FOUL_ON)
    m.tab('gt1_foul_off_f', 'gt1_foul_off', FOUL_OFF)
    m.prod('gt1_foul_f', ['gt1_foul_on_f', 'gt1_foul_off_f'])
    # what the day gives
    m.prod('gt1_cap', [RATING, 'gt1_amb_f', 'gt1_dp_f', 'gt1_foul_f'], 'MW', '10MKA10')
    m.diff('gt1_cap_1', 'gt1_cap', 1, 'MW')
    m.min('gt1_base_mw', [RATING - 1, 'gt1_cap_1'], 'MW')
    # base load as the machine's load fraction: on a hot day base load burns at the same firing temperature, the
    # lost output mostly the compressor's lighter air; the exhaust's heat changes little ([GER3567]), so the HRSG and
    # the steam turbine see base load as before
    m.min('gt1_base_cap', [RATING, 'gt1_cap'], 'MW')
    m.tab('gt1_inv_cap', 'gt1_base_cap', INV_CAP, '1/MW')
    return ['gt1_cap', 'gt1_dp_rb_cap']


def gt_after(m):
    """In gt1, after the load: the heat rate, the washes, the excitation cabinet, the alarms and the readouts."""
    m.tab('gt1_hr_amb', 'ambient_t', AMB_HR)
    m.tab('gt1_hr_lf', 'gt1_lf', HR_LF)
    m.tab('gt1_hr_foul', 'gt1_foul_f', FOUL_HR)
    m.tab('gt1_hr_dp', 'gt1_filt_dp', DP_HR)
    m.prod('gt1_hr', [HR_35, 'gt1_hr_amb', 'gt1_hr_lf', 'gt1_hr_foul', 'gt1_hr_dp', 'gt1_brk_cmd'], 'kJ/kWh',
           '10MBA10')
    # the compressor washes (a machine: idle, online, offline)
    for i, s in enumerate(('idle', 'online', 'offline')):
        m.eq(f'gt1_wash_{s}', 'gt1_wash_state', i)
    m.NOT('gt1_washing', 'gt1_wash_idle')
    # the wash's time: from 0 at each wash (a wash ended in one step and pressed again in the next starts again: the
    # timer reads the step before, when the ended wash was still running)
    m.timer('gt1_wash_t', 'gt1_wash_run')
    m.cmp('gt1_wash_t_on', 'gt1_wash_t', '>=', WASH_ON_S)
    m.cmp('gt1_wash_t_off', 'gt1_wash_t', '>=', WASH_OFF_S)
    m.AND('gt1_wash_on_done', ['gt1_wash_online', 'gt1_wash_t_on'])
    m.AND('gt1_wash_off_done', ['gt1_wash_offline', 'gt1_wash_t_off'])
    m.OR('gt1_wash_done', ['gt1_wash_on_done', 'gt1_wash_off_done'])     # the offline wash removes both shares
    m.NOT('gt1_wash_ndone', 'gt1_wash_done')
    m.AND('gt1_wash_run', ['gt1_washing', 'gt1_wash_ndone'])
    m.cmp('gt1_wash_load', 'gt1_mw', '>=', WASH_LOAD)
    m.AND('gt1_wash_ok', ['gt1_in_loaded', 'gt1_wash_load'])
    m.NOT('gt1_wash_lost', 'gt1_wash_ok')          # off the grid or below the load: the online wash stops
    m.cmp('gt1_ws_cool', 'gt1_ws', '<', WS_WASH)
    m.cmp('gt1_at_stand', 'gt1_start_state', '<', 0.5)     # the start sequence at standstill
    m.NOT('gt1_spun', 'gt1_still')                  # the rotor driven up: the offline wash stops
    m.machines.append({'id': 'gt1_wash', 'kks': '10MBA10', 'init': 'idle',
        'commands': {'wash_online': {'from': ['idle'], 'to': 'online'},
                     'wash_offline': {'from': ['idle'], 'to': 'offline'}},
        'states': [
            {'id': 'idle', 'watch': False},
            {'id': 'online', 'next': [['gt1_wash_on_done', 'idle'], ['gt1_wash_lost', 'idle']],
             'say': 'Online compressor wash: demineralised water sprayed into the running compressor'},
            {'id': 'offline', 'next': [['gt1_wash_off_done', 'idle'], ['gt1_spun', 'idle']],
             'say': 'Offline compressor wash: the rotor cranked, the compressor soaked with detergent, rinsed and '
                    'dried'}]})
    m.op('10MBA10', 'wash_online', None, [
        ('gt1_in_loaded', 'GT 1 is not on the grid'), ('gt1_wash_load', f'Load below {WASH_LOAD} MW')],
        ('screen',), machine='gt1_wash')
    m.op('10MBA10', 'wash_offline', None, [
        ('gt1_at_stand', 'GT 1 is starting or stopping'), ('gt1_still', 'GT 1 is turning: stop it first'),
        ('gt1_tg_run', 'Turning gear not running'),
        ('gt1_ws_cool', f'Wheel spaces above {WS_WASH} °C: water would crack the hot parts')],
        ('screen',), machine='gt1_wash')
    # the excitation cabinet's air filters
    m.tab('gen1_cab_dust', 'dust', CAB_DUST)
    m.prod('gen1_cab_rate', ['gt1_exc_cmd', 'age_h', 'gen1_cab_dust'], 'h/s')
    m.v('gen1_cab_filt', {'wear': 'gen1_cab_rate', 'max': 100000}, 'h')
    m.tab('gen1_cab_k', 'gen1_cab_filt', CAB_RISE, 'K')
    m.prod('gen1_cab_rise', ['gen1_cab_k', 'gt1_exc_cmd'], 'K')
    m.sum('gen1_cab_tgt', ['ambient_t', 'gen1_cab_rise'], '°C')
    m.lag('gen1_cab_t', 'gen1_cab_tgt', 600, init=35, unit='°C', kks='10MKC10')
    m.cmp('gen1_cab_h', 'gen1_cab_t', '>', CAB_H)
    m.NOT('gen1_exc_off', 'gt1_exc_cmd')
    # alarms and readouts
    m.alarm('gt1_filt_dp_high', '10MBL10AT001', 'GT 1 air intake filter pressure drop high', 'gt1_dp_h_d', 2,
            '10MBL10AT001', 'PDAH')
    m.alarm('gt1_filt_runback', '10MBL10AT001', 'GT 1 runback: air intake filter pressure drop high-high', 'gt1_dp_rb',
            1, '10MBA10', 'PDAHH')
    m.alarm('gen1_cab_hot', '10MKC10', 'Generator 1 excitation cabinet temperature high', 'gen1_cab_h', 2, None, 'TAH')
    m.b(kks='10MBL10AT001', show='gt1_filt_dp')
    # the works: the cartridges changed with the GT stopped (its isolation locks the GT's code: the start refused
    # meanwhile, as intended); the cabinet's filters. The filter house stands 20 m up with no way onto it in the plant
    # yet: the cartridges' work is done from the GT's work place. The pulse system's repair has no work until then: an
    # isolation of its air on the GT's code would lock the running GT (its stop, its alarms); the trainer repairs it
    m.isolation('iso_gt1_filt', 'GT 1 air intake filter house: the GT stopped',
                [('10MBA10', 'electrical', 'gt1_still', 'GT 1 stopped; its starting device isolated, locked and '
                                                       'tagged')])
    m.work('wo_gt1_filters', '10MBA10', 'GT 1 air intake: replace the filter cartridges', 'mech', 'general',
           'iso_gt1_filt')
    m.works[-1]['renews'] = ['gt1_filt_res', 'gt1_filt_cake']
    m.isolation('iso_gen1_exc', 'Generator 1 excitation: its supply',
                [('10MKC10', 'electrical', 'gen1_exc_off', 'Excitation off; its supply isolated, locked and tagged')])
    m.work('wo_gen1_cab', '10MKC10', 'Generator 1 excitation cabinet: replace the air filters', 'elec', 'general',
           'iso_gen1_exc')
    m.works[-1]['renews'] = ['gen1_cab_filt']


def ct_values(m):
    """In ct, before the fans: the approach's factor and the ice."""
    m.tab('ct_appr_f', 'ambient_wb', APPROACH_WB)
    m.tab('ct_ice_k', 'ambient_t', ICE, 'mm/s')
    m.lag('ct_ice', 'ct_ice_k', ICE_TAU, unit='mm/s')
    # water in fan 7's probe's junction box (a poor gland): the rain it has taken against what it takes
    m.prod('ct_jb7_rate', ['rain', round(1 / 3600, 15)], 'mm/s')
    m.v('ct_jb7_rain', {'wear': 'ct_jb7_rate', 'max': 100000}, 'mm')
    m.v('ct_jb7_mm', {'draw': JB_RAIN}, 'mm')
    for s, code in (('ct_fan7_cy_err', '30PAD10CY007'), ('ct_jb7_wet', '30PAD10CY007'), ('ct_cy7_bad', '30PAD10CY007'),
                    ('ct_fan9_cy_fail', '30PAD10CY009'), ('ct_lvl_frozen', '30PAD10CL001')):
        m.state(s, 0, code)
    m.ramp('ct_fan7_drift', 'ct_fan7_cy_err', round(1 / 1200, 9), unit='pu')
    m.prod('ct_fan7_derr', ['ct_fan7_drift', 9], 'mm/s')
    m.prod('ct_fan9_fs', ['ct_fan9_cy_fail', 25], 'mm/s')
    # lightning: storm seconds between strikes near the plant (drawn once), each counted by the arrester
    m.v('ln_w', {'wear': 'lightning', 'max': 1000000, 'reset': 'ln_strike'}, 's')
    m.v('ln_gap', {'draw': STRIKE_GAP}, 's')
    m.cmp('ln_strike', 'ln_w', '>=', 'ln_gap')
    m.v('ln_count', {'count': 'ln_strike'}, None, '10BAT10')
    m.v('ln_n', {'draw': STRIKE_N})
    # the basin level transmitter's impulse line: it freezes below 0 °C (the fault, made once) and holds the reading
    # until it thaws above 3 °C
    m.lag('ct_line_t', 'ambient_t', LINE_TAU, init=35, unit='°C')
    m.cmp('ct_line_ice', 'ct_line_t', '<', 0)
    m.cmp('ct_line_cold', 'ct_line_t', '<', 3)
    m.AND('ct_lvl_held', ['ct_lvl_frozen', 'ct_line_cold'])


def reading(i):
    """The name of fan i's vibration reading."""
    return f'ct_fan{i}_vm' if i in (INGRESS_FAN, SURGE_FAN) else f'ct_fan{i}_vib'


def fan_reading(m, i):
    """The vibration the fan's protection and alarms read: its own, or for fans 7 and 9 the transmitter's reading
    (the drift of water in the junction box; full scale after a lightning surge)."""
    if i == INGRESS_FAN:
        return m.sum(f'ct_fan{i}_vm', [f'ct_fan{i}_vib', 'ct_fan7_derr'], 'mm/s', f'30PAD10CY{i:03d}')
    if i == SURGE_FAN:
        return m.sum(f'ct_fan{i}_vm', [f'ct_fan{i}_vib', 'ct_fan9_fs'], 'mm/s', f'30PAD10CY{i:03d}')
    return f'ct_fan{i}_vib'


def ct_after(m):
    """In ct, after the basin: the held level reading and the works."""
    m.isolation('iso_ct_lvl', 'Cooling tower basin level transmitter',
                [('30PAD10CL001', 'instrument', None, 'Transmitter isolated at its root valve and tagged; the impulse '
                                                      'line drained')])
    m.work('wo_ct_lvl_thaw', '30PAD10CL001', 'Cooling tower basin level transmitter: thaw the impulse line and fit '
           'heat tracing', 'inst', 'general', 'iso_ct_lvl', 'ct_lvl_frozen')
    m.work('wo_ct_fan7_cy', '30PAD10AN007', 'Cooling tower fan 7 vibration reads high: find the cause and put it right',
           'inst', 'general', 'iso_ct_fan7', 'ct_fan7_ingress')
    m.works[-1]['renews'] = ['ct_jb7_rain']
    m.work('wo_ct_fan9_cy', '30PAD10AN009', 'Cooling tower fan 9 vibration transmitter: replace it and its surge '
           'protector', 'inst', 'general', 'iso_ct_fan9', 'ct_fan9_surge')
    m.b(kks='10BAT10', show='ln_count')


# ------------------------------------------------------------------------------------------------ faults and staff
def faults():
    """The weather's faults (PLANT3D §7.8, made once in a run): the frozen line, the junction box's water (two causes,
    REALISM.md §2.6), the lightning surge. The pulse system's failure is a trainer's fault."""
    return [
        {'id': 'ct_lvl_frozen', 'when': 'ct_line_ice', 'set': {'ct_lvl_frozen': 1},
         'text': 'The cooling tower basin level transmitter\'s impulse line freezes: the reading holds',
         'kks': '30PAD10CL001', 'repair': {'ct_lvl_frozen': 0}},
        {'id': 'ct_fan7_ingress', 'when': {'cmp': ['ct_jb7_rain', '>=', 'ct_jb7_mm']}, 'set': {'ct_fan7_cy_err': 1},
         'text': 'Cooling tower fan 7 vibration reads high and climbing', 'kks': '30PAD10CY007',
         'repair': {'ct_fan7_cy_err': 0},
         'causes': [{'id': 'water', 'weight': 4, 'set': {'ct_jb7_wet': 1}, 'repair': {'ct_jb7_wet': 0},
                     'text': 'Rain in the junction box through a poor cable gland: the wet terminals leak current '
                             'into the loop'},
                    {'id': 'electronics', 'weight': 1, 'set': {'ct_cy7_bad': 1}, 'repair': {'ct_cy7_bad': 0},
                     'text': 'The transmitter\'s electronics have failed'}]},
        {'id': 'ct_fan9_surge', 'when': {'cmp': ['ln_count', '>=', 'ln_n']}, 'set': {'ct_fan9_cy_fail': 1},
         'text': 'A lightning surge damages cooling tower fan 9\'s vibration transmitter: it reads full scale',
         'kks': '30PAD10CY009', 'repair': {'ct_fan9_cy_fail': 0}},
        {'id': 'gt1_pulse', 'set': {'gt1_pulse_fail': 1},
         'text': 'GT 1 air intake: the pulse cleaning stops (its controller fails)', 'kks': '10MBL10AT001',
         'repair': {'gt1_pulse_fail': 0}},
    ]


def fault_work():
    """{fault: its work} for the staff (train_staff.FAULT_WORK): the supervisor asks for the permit."""
    return {'ct_lvl_frozen': 'wo_ct_lvl_thaw', 'ct_fan7_ingress': 'wo_ct_fan7_cy', 'ct_fan9_surge': 'wo_ct_fan9_cy'}


# ------------------------------------------------------------------------------------------------ the scenarios' ages
# (wear, what a month adds, what it is renewed at): the filters' residue (kg: a hot month's dust at 90 % running;
# new cartridges at 150 kg, before the residue alone would keep the pulsing on), the
# fouling that only offline washes remove (quarterly), what the online washes leave (daily), the cabinet's filters
HOURS_A_MONTH = 730
AGE_ITEMS = [('gt1_filt_res', HOURS_A_MONTH * 0.9 * 3600 * 0.2 * 540 * 1e-6 * RESIDUE_SHARE, 150),
             ('gt1_foul_off', HOURS_A_MONTH * 0.9, 2190),
             ('gt1_foul_on', HOURS_A_MONTH * 0.9, 24),
             ('gen1_cab_filt', HOURS_A_MONTH * 0.9, 4380)]


def age(sc, months):
    """Each item's wear at the scenario's age, less what its renewals took (as train_ageing.apply)."""
    import math
    for wear, per_month, every in AGE_ITEMS:
        x = math.fmod(months * per_month, every)
        if x > 0:
            sc['init'][wear] = round(x, 3)


# ------------------------------------------------------------------------------------------------ the procedure
def wash_offline():
    """The offline compressor wash (GER-3620) from cold iron: the GT's oil and turning gear in service (the cold
    start's own steps), the wheel spaces cool, then the wash: the rotor cranked, soaked, rinsed and dried."""
    import train_content as C
    by_id = {st['id']: st for st in C.cold_start()['steps']}
    S = [by_id[s] for s in ('ia', 'ccw', 'ccw_cooler', 'gt_lube', 'gt_lube_reset', 'gt_tg')]
    S.append(C.step('wash', ['Check the wheel space temperatures are below 95 °C, then start the offline compressor wash '
                             'on the GT 1 screen (', C.k('10MBA10'), ').'], ['10MBA10'],
                    [C.op('10MBA10', 'wash_offline')], 'gt1_wash_offline',
                    ['Water on hot discs and casings would crack them: the wash waits until the wheel spaces have '
                     'cooled. A start is blocked while it runs.'], 'none'))
    S.append(C.step('wash_done', ['Wait for the wash to finish: soak, rinse and the drying crank (half an hour).'],
                    ['10MBA10'], (), 'gt1_wash_idle', go='none'))
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'gt_wash_offline',
            'title': 'GT 1 offline compressor wash', 'kind': 'procedure', 'scenario': 'cold_iron',
            'intro': [{'p': ['Fouling on the compressor blades costs output and heat rate, more in dust and damp air. '
                             'The online wash at load removes only part of it; the offline wash, with the rotor '
                             'cranked cold, the rest.']}],
            'steps': S}
