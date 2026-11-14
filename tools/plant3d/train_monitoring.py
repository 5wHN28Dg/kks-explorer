"""Condition monitoring in the first train (docs/plant3d/REALISM.md §9.3, §2.19; milestone AG3): the vibration data
collector, the thermal camera and the oil sampling kits at the store counter (tools.json); the collector's meters at
the pumps' and cooling tower fans' vibration probes and the camera's at the pump motors (§2.5: a reading is S1's
`read` with the meter named, so a point's readings are the run's `read` events of its code); the pump bearings' outer
race defect tone, seen in the collector's spectrum before the overall leaves ISO 20816-3's zone A/B; oil samples (a
hand action at the equipment's work place with a kit) from the CW pump motors' oil-bath bearings and the fan gear
reducers, analysed by the lab (`sample` nodes, §2.19) for iron, the ISO 4406 code at 6 µm, the viscosity at 40 °C and
water, results after 48 clock hours; and the monitoring file (data/plant3d/monitoring.json) the app draws the
spectrum, the zones and the lab's report from (the engine never reads it).

Every number is invented, round and plausible for the class of machine, from public sources:
- ISO 20816-1 and ISO 20816-3 (overall velocity, mm/s r.m.s., 10 Hz to 1 kHz; the zones A/B, B/C, C/D for groups 1
  and 2 on rigid foundations; AG2's alarms at C/D);
- ISO 13373-1 (measurement points on the bearing housings, routes, trending) and ISO 13373-2 (spectrum analysis: 1x
  unbalance, 2x misalignment, the bearing defect frequencies and their harmonics, gear mesh frequencies);
- ISO 18436-2 (the vibration analyst's categories: a category I analyst collects the route, a category II reads the
  spectrum: the trainee does both);
- SKF, "Bearing damage and failure analysis" and SKF's defect frequency formulas (BPFO = n/2 fr (1 - d/D cos a), BPFI
  = n/2 fr (1 + d/D cos a), BSF = D/(2d) fr (1 - (d/D cos a)^2), FTF = fr/2 (1 - d/D cos a)), with the approximate
  geometry of a 6316 deep groove ball bearing (8 balls of 28.6 mm on a 125 mm pitch circle, contact angle 0): not a
  datasheet value, a plausible one;
- ISO 4406 (solid contamination codes per 4, 6 and 14 µm), ASTM D6224 (in-service monitoring of auxiliary power
  plant lubricating oil: viscosity, water, particle count, wear metals as routine tests), ASTM D7720 (statistically
  derived alert and alarm limits: the limits below are of that kind, set as a plant's own would be), ASTM D445
  (kinematic viscosity at 40 °C), ASTM D6304 (water by Karl Fischer), ASTM D5185 (wear metals by ICP);
- ISO 3448 (the oils' viscosity grades: VG 68 for the large motors' oil baths, VG 220 for the cooling tower gear
  reducers, as the gear makers' public manuals ask, e.g. Amarillo Gear's and Hansen's cooling tower drive manuals)."""
import math

import train_ageing
from train_ageing import KINDS, PUMPS, FANS, ZONES, BRG_RISE, BRG_TAU

STORE = 'store_counter'     # the store's counter (train_staff.py ANCHORS): the CM tools are issued from the stores
TOOLS = [
    {'id': 'vib_dc', 'title': 'Vibration data collector', 'kind': 'collector', 'modes': ['vel'], 'at': [[STORE, 1]]},
    {'id': 'ir_cam', 'title': 'Thermal camera', 'kind': 'camera', 'modes': ['ir'], 'at': [[STORE, 1]]},
    {'id': 'oil_kit', 'title': 'Oil sampling kit (vacuum pump, tube, clean bottles)', 'kind': 'sampler',
     'at': [[STORE, 2]]},
]

# ------------------------------------------------------------------------------------------------ the spectrum
# the approximate geometry of a 6316 deep groove ball bearing (SKF's formulas, contact angle 0)
BALLS, BALL_D, PITCH_D = 8, 28.6, 125.0


def orders():
    """The bearing's defect frequencies in orders of the shaft's speed (SKF's formulas)."""
    r = BALL_D / PITCH_D
    return {'bpfo': round(BALLS / 2 * (1 - r), 3), 'bpfi': round(BALLS / 2 * (1 + r), 3),
            'bsf': round(PITCH_D / (2 * BALL_D) * (1 - r * r), 3), 'ftf': round(0.5 * (1 - r), 3)}


# the motors' speeds (rpm, 50 Hz): the CW pumps' large vertical motors 12 poles, the rest 4 poles
RPM = {'cw': 495, 'ccw': 1485, 'cep': 1485}
FAN_RPM = 1485          # the fan motor (the gear reducer's input shaft)
FAN_RATIO = 10.5        # the gear reducer's ratio: the fan at about 141 rpm
PINION_TEETH = 17       # the input pinion's teeth: the gear mesh at 17x the input speed
SHARE_2X = 0.3          # the 2x line's share of the overall (a well aligned set: ISO 13373-2)
FLOOR = 0.03            # mm/s: the spectrum's noise floor per line
# the outer race tone (mm/s, in shares of the zone's base) against the bearing's margin, from its P point: it is
# seen in the spectrum while the overall is still in zone A/B (the P-F curve's order, §4.2: the spectrum's bearing
# tones first; tests/test_plant3d_monitoring.py checks it)
TONE = [(-1, 0), (-0.9, 1 / 3), (-0.6, 2 / 3), (-0.3, 1.4), (0, 2.2)]
# ISO 20816-3, rigid foundations, mm/s r.m.s.: the zone boundaries A/B, B/C, C/D
ZONE_LIMITS = {1: [2.3, 4.5, 7.1], 2: [1.4, 2.8, 4.5]}
FAN_ZONES = [2.8, 4.5, 6.3]     # the fans: AG2's advisory at 6.3 mm/s, the trip at 10


def tone(m, item):
    """A pump bearing's outer race tone (BPFO): 0 below its P point, rising over the P-F interval; 0 stopped."""
    p, _, _, _, _, spd, _, _, _, group, _ = item
    pf = KINDS['bearing']['pf']
    base = ZONES[group]['base']
    m.tab(f'{p}_bt_k', f'{p}_brg_mgn', [[round(f * pf, 3), round(s * base, 4)] for f, s in TONE], 'mm/s')
    return m.prod(f'{p}_bt', [spd, f'{p}_bt_k'], 'mm/s')


# ------------------------------------------------------------------------------------------------ the thermal picture
# The camera's false-colour picture (REALISM.md §9.3, §2.19; drawn by the app with the Workshop's heat view): each
# component of the pump's Workshop tree (the motor's inside it) at the temperature of a model value. What a running pump
# set shows: the bearing housing whose wear the camera's spot reads (the monitored bearing: its rise grows over its P-F
# interval, train_ageing.py), the motor's frame and its other bearings, the pump's bearing frame and shaft at a sound
# bearing's rise over the air (BRG_RISE: a frame and its sound bearings run about as warm, the fan's air over the frame
# keeps it there), what the water wets at the water's temperature, the rest at the air's.
PICTURE_KIND = {'cw': 'pump_vertical', 'ccw': 'pump_horizontal', 'cep': 'pump_vertical'}
FLUID_T = {'cw': 'cw_cold_t', 'ccw': 'ccw_t', 'cep': 'cond_t'}    # the pumped water: the CW basin's, the CCW loop's,
# the condensate's
PICTURE = {
    # the monitored bearing is the motor's drive end bearing (beside the coupling: the collector's point)
    'pump_horizontal': {'brg': ['end_shield_de', 'bearing_de'],
                        'warm': ['motor', 'end_shield_nde', 'bearing_nde', 'rotor', 'frame', 'end_cover', 'bearing_ib',
                                 'bearing_ob', 'shaft'],
                        'fluid': ['volute', 'casing_cover', 'impeller', 'seal'],
                        'air': ['baseplate', 'coupling', 'guard', 'terminal_box', 'fan', 'fan_cowl', 'grille']},
    # a vertical motor's oil-bath bearing is its thrust bearing in the top bracket (the oil points' bearing,
    # train_monitoring.oil): the one that wears and runs hot
    'pump_vertical': {'brg': ['end_shield_nde', 'bearing_thrust'],
                      'warm': ['motor', 'end_shield_de', 'bearing_guide', 'rotor'],
                      'fluid': ['head', 'seal', 'shaft', 'discharge_case', 'bowl_1', 'bowl_2', 'suction_bell',
                                'impeller_1', 'impeller_2', 'column_1', 'column_2', 'column_3'],
                      'air': ['soleplate', 'coupling', 'drip_cover', 'fan', 'terminal_box']},
}
SPOT = {'pump_horizontal': 'end_shield_de', 'pump_vertical': 'end_shield_nde'}   # where the camera's spot is aimed


def warm(m, item):
    """A running pump set's frame and sound bearings: BRG_RISE over the air at speed, lagging as a housing does."""
    p, spd = item[0], item[5]
    m.prod(f'{p}_warm_rise', [spd, BRG_RISE], 'K')
    m.lag(f'{p}_warm_rl', f'{p}_warm_rise', BRG_TAU, unit='K')
    m.sum(f'{p}_warm_t', ['ambient_t', f'{p}_warm_rl'], '°C')


def picture(p):
    """The ir point's picture: the kind, where the spot is, and each component's temperature value."""
    k = p.split('_')[0]
    kind = PICTURE_KIND[k]
    val = {'brg': f'{p}_brg_t', 'warm': f'{p}_warm_t', 'fluid': FLUID_T[k], 'air': 'ambient_t'}
    return {'kind': kind, 'spot': SPOT[kind],
            'parts': {c: val[role] for role, cs in PICTURE[kind].items() for c in cs}}


# ------------------------------------------------------------------------------------------------ oil analysis
HOURS = 48              # the lab's turnaround (clock hours): a commercial lab's usual (ASTM D6224's routine tests)
MINUTES = 10            # a sample drawn by the vacuum pump from the sampling valve, the bottle labelled
OIL_PUMPS = ['cw_a', 'cw_b', 'cw_c']   # the large vertical motors' oil-bath bearings (the rest are greased)


def _spread(a):
    """A small lab spread of +-a (an inverse distribution: most results within half of it)."""
    return [[0, -a], [0.1, round(-0.5 * a, 4)], [0.5, 0], [0.9, round(0.5 * a, 4)], [1, a]]


# per kind of oil point: the oil's grade (cSt at 40 °C), the truth tables of iron (ppm) and the ISO 4406 code at
# 6 µm against the item's margin (fractions of its P-F interval), the spreads, and the plant's alert and alarm limits
OIL = {
    'bearing': {'title': 'motor bearing oil bath', 'visc': 68, 'water': 60,
                'fe': [(-1, 4), (-0.6, 12), (-0.3, 35), (0, 90)], 'pc': [(-1, 15), (-0.6, 16), (-0.3, 18), (0, 21)],
                'spread': {'fe': 2, 'pc': 0.6, 'visc': 1.5, 'h2o': 20},
                'limits': {'fe': [15, 30], 'pc': [17, 19], 'visc': [[61.2, 74.8], [54.4, 81.6]], 'h2o': [200, 500]}},
    'gearbox': {'title': 'gear reducer oil', 'visc': 220, 'water': 120,
                'fe': [(-1, 30), (-0.5, 80), (0, 250)], 'pc': [(-1, 17), (-0.5, 19), (0, 22)],
                'spread': {'fe': 8, 'pc': 0.6, 'visc': 4, 'h2o': 30},
                'limits': {'fe': [100, 200], 'pc': [19, 21], 'visc': [[198, 242], [176, 264]], 'h2o': [300, 800]}},
}
RESULTS = [('fe', 'Iron', 'ppm'), ('pc', 'ISO 4406 code at 6 µm', ''), ('visc', 'Viscosity at 40 °C', 'cSt'),
           ('h2o', 'Water', 'ppm')]


def oil_points():
    """[(prefix, code, kind, item margin, title, area)] of every oil sampling point."""
    out = []
    for p in OIL_PUMPS:
        it = next(i for i in PUMPS if i[0] == p)
        out.append((p, it[1], 'bearing', f'{p}_brg_mgn', f'{it[8]} motor', it[3]))
    for i in FANS:
        out.append((f'ct_fan{i}', f'30PAD10AN{i:03d}', 'gearbox', f'ct_fan{i}_gbx_mgn', f'Cooling tower fan {i} gear '
                    f'reducer', 'ct'))
    return out


def oil(m, pt):
    """One oil sampling point: the truth of its iron and particles, its four sample nodes and its hand action."""
    p, code, kind, mgn, _, _ = pt
    o = OIL[kind]
    pf = KINDS[kind]['pf']
    m.tab(f'{p}_oil_fe', mgn, [[round(f * pf, 3), y] for f, y in o['fe']], 'ppm')
    m.tab(f'{p}_oil_pc', mgn, [[round(f * pf, 3), y] for f, y in o['pc']])
    refs = {'fe': f'{p}_oil_fe', 'pc': f'{p}_oil_pc', 'visc': o['visc'], 'h2o': o['water']}
    units = {'fe': 'ppm', 'pc': None, 'visc': 'cSt', 'h2o': 'ppm'}
    nodes = []
    for k, _, _ in RESULTS:
        nodes.append(m.v(f'{p}_lab_{k}', {'sample': refs[k], 'spread': _spread(o['spread'][k]), 'hours': HOURS},
                         units[k]))
    # a vertical pump's oil-bath bearing is in its motor (the thrust bearing at the top): the component every vertical
    # pump's tree has, whether its motor has a tree of its own (up to 500 kW) or is one part (the CW pumps' 1,250 kW);
    # a fan's gear reducer has no tree yet
    m.hands.append({'kks': code, 'action': 'take_oil', 'component': 'motor' if kind == 'bearing' else 'body',
                    'tools': ['oil_kit'], 'minutes': MINUTES, 'work': False, 'samples': nodes})


# ------------------------------------------------------------------------------------------------ into the models
def model(m):
    """The area's condition monitoring: the pumps' tones and meters, the fans' meters, the oil points."""
    for item in PUMPS:
        p, code, cy, area = item[:4]
        if area != m.area:
            continue
        tone(m, item)
        warm(m, item)
        m.meters.append({'id': f'{p}_vel', 'kks': cy, 'point': 'brg', 'tool_kind': 'collector', 'mode': 'vel',
                         'value': f'{p}_vib'})
        m.meters.append({'id': f'{p}_ir', 'kks': code, 'point': 'brg', 'tool_kind': 'camera', 'mode': 'ir',
                         'value': f'{p}_brg_t'})
    if m.area == 'ct':
        for i in FANS:
            m.meters.append({'id': f'ct_fan{i}_vel', 'kks': f'30PAD10CY{i:03d}', 'point': 'brg',
                             'tool_kind': 'collector', 'mode': 'vel', 'value': f'ct_fan{i}_vib'})
    for pt in oil_points():
        if pt[5] == m.area:
            oil(m, pt)


# ------------------------------------------------------------------------------------------------ the monitoring file
SOURCES = [
    {'id': 'iso20816', 'cite': 'ISO 20816-1:2016 and ISO 20816-3:2022, Mechanical vibration: measurement and '
     'evaluation of machine vibration, part 1 general guidelines, part 3 industrial machines with a power above '
     '15 kW: the zones A/B, B/C and C/D for groups 1 and 2 on rigid foundations', 'url': 'https://www.iso.org/standard/78311.html'},
    {'id': 'iso13373', 'cite': 'ISO 13373-1:2002 and ISO 13373-2:2016, Condition monitoring and diagnostics of '
     'machines, vibration condition monitoring, part 1 general procedures (measurement points, routes, trends), '
     'part 2 processing, analysis and presentation of vibration data (spectra, the defect frequencies)',
     'url': 'https://www.iso.org/standard/68128.html'},
    {'id': 'iso18436', 'cite': 'ISO 18436-2:2014, Condition monitoring and diagnostics of machines, requirements for '
     'qualification and assessment of personnel, part 2 vibration condition monitoring and diagnostics',
     'url': 'https://www.iso.org/standard/50447.html'},
    {'id': 'skf', 'cite': 'SKF, Bearing damage and failure analysis (publication 14219 EN, 2017), and SKF\'s bearing '
     'defect frequency formulas; the geometry used is an approximation of a 6316 deep groove ball bearing',
     'url': 'https://www.skf.com/group/support/engineering-tools/bearing-frequencies-calculator'},
    {'id': 'iso4406', 'cite': 'ISO 4406:2021, Hydraulic fluid power, fluids, method for coding the level of '
     'contamination by solid particles (the codes per 4, 6 and 14 µm)', 'url': 'https://www.iso.org/standard/79690.html'},
    {'id': 'astm_d6224', 'cite': 'ASTM D6224-16, Standard practice for in-service monitoring of lubricating oil for '
     'auxiliary power plant equipment (viscosity, water, particle count and wear metals as routine tests)',
     'url': 'https://www.astm.org/d6224-16.html'},
    {'id': 'astm_d7720', 'cite': 'ASTM D7720-11 (2017), Standard guide for statistically evaluating measurand alarm '
     'limits when using oil analysis to monitor equipment and oil for fitness and contamination',
     'url': 'https://www.astm.org/d7720-11r17.html'},
    {'id': 'iso3448', 'cite': 'ISO 3448:1992, Industrial liquid lubricants, ISO viscosity classification (VG 68, VG '
     '220: the mid-point kinematic viscosity at 40 °C, within 10 %)', 'url': 'https://www.iso.org/standard/8774.html'},
]


def monitoring():
    """data/plant3d/monitoring.json (format walkdown-plant-monitoring version 1, REALISM.md §2.19)."""
    o = orders()
    points = []
    for item in PUMPS:
        p, code, cy, _, _, _, _, _, title, group, _ = item
        rpm = RPM[p.split('_')[0]]
        points.append({'code': cy, 'kind': 'vib', 'title': f'{title} motor, drive end bearing', 'meter': f'{p}_vel',
                       'rpm': rpm, 'group': group, 'zones': ZONE_LIMITS[group], 'floor': FLOOR,
                       'tones': o,
                       'lines': [{'name': '2×', 'order': 2, 'share': SHARE_2X},
                                 {'name': 'BPFO', 'order': o['bpfo'], 'value': f'{p}_bt'},
                                 {'name': '2×BPFO', 'order': round(2 * o['bpfo'], 3), 'value': f'{p}_bt',
                                  'share': 0.5}]})
        points.append({'code': code, 'kind': 'ir', 'title': f'{title} motor, bearing housing', 'meter': f'{p}_ir',
                       'limits': [train_ageing.BRG_T_H - 10, train_ageing.BRG_T_H], 'picture': picture(p)})
    for i in FANS:
        gm = PINION_TEETH
        points.append({'code': f'30PAD10CY{i:03d}', 'kind': 'vib', 'title': f'Cooling tower fan {i} gear reducer',
                       'meter': f'ct_fan{i}_vel', 'rpm': FAN_RPM, 'group': 2, 'zones': FAN_ZONES, 'floor': FLOOR,
                       'lines': [{'name': 'Fan 1×', 'order': round(1 / FAN_RATIO, 4), 'value': f'ct_fan{i}_vft',
                                  'by': f'ct_fan{i}_spd'},
                                 {'name': 'Gear mesh', 'order': gm, 'value': f'ct_fan{i}_gbx_x',
                                  'by': f'ct_fan{i}_spd'},
                                 {'name': '2× gear mesh', 'order': 2 * gm, 'value': f'ct_fan{i}_gbx_x',
                                  'by': f'ct_fan{i}_spd', 'share': 0.4}]})
    for p, code, kind, _, title, _ in oil_points():
        lim = OIL[kind]['limits']
        points.append({'code': code, 'kind': 'oil', 'title': f'{title} ({OIL[kind]["title"]})', 'action': 'take_oil',
                       'hours': HOURS,
                       'results': [{'node': f'{p}_lab_{k}', 'title': t, 'unit': u, 'alert': lim[k][0],
                                    'alarm': lim[k][1]} for k, t, u in RESULTS]})
    return {'format': 'walkdown-plant-monitoring', 'version': 1, 'sources': SOURCES, 'points': points}


def values_added():
    """(tone and picture values, oil values) this tool adds to the first train (REALISM.md §11's budgets: the
    picture's warm frames count with the wear signs)."""
    return 2 * len(PUMPS) + 3 * len(PUMPS), len(oil_points()) * (2 + len(RESULTS))


assert math.isclose(orders()['bpfo'], 3.085, abs_tol=0.01)
