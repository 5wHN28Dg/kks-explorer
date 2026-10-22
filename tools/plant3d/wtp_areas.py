"""The water treatment plant's areas (docs/plant3d/WATER-TREATMENT.md, docs/plant3d/SITE.md: `intake` and `wtp`, pack
`wtp`; docs/PLANT3D.md §3–§5): the intake on the river bank, the pretreatment (rapid mixer, two clarifiers, the
gravity filters), the filtered water tank and its pumps, the treatment building (cartridge filters, two RO trains,
mixed beds, the WTP's control room and laboratory), the degasser, the demineralised water tanks and their transfer
pumps, the chemical store, the neutralisation pit, the sludge thickener and the filter press, and the pipes to the
first train: the cooling tower's makeup and the plant's demineralised water tank. Everything is invented (R1);
sizes are round values in the ranges WATER-TREATMENT.md §2–§3 gives. Behaviour comes in milestone W2 (MILESTONES.md):
here only what turns and sounds while the plant runs (wtp_model.py)."""
import math

from train_areas import (eq, child, pipe, nz, jn, free, valve, inst, rect, box, louvre, window, st, stair_straight,
                         sign, hearing_signs, pg)

PACK = 'wtp'
DECK_OVER = 0.55          # a clarifier's bridge deck over its wall's top (kit: parts_water.gd): 28 risers of 0.1875 m
                          # for the clarifiers' stairs, 27 for the thickener's (a stair of 0.19 m risers ends a walker
                          # more than half a metre up its last going: tests/test_walk.gd)
BRIDGE_OUT = 1.6          # the bridge's deck beyond the wall: the landing at the top of its stair (parts_water.gd)
WALL = 0.3                # a clarifier's wall


def area(aid, title, bounds, equipment=(), pipes=(), structures=(), signs=()):
    return {'format': 'walkdown-plant-area', 'version': 1, 'id': aid, 'title': title, 'bounds': bounds,
            'pack': PACK, 'equipment': list(equipment), 'pipes': list(pipes), 'structures': list(structures),
            'signs': list(signs)}


def stair_run(h, width=1.0):
    """The plan length of a straight stair rising h (train_areas.stair_straight's rule)."""
    n = math.ceil(h / 0.19 - 1e-9)
    f = math.ceil(h / 3.6 - 1e-9)
    g = max(0.25, 0.63 - 2 * h / n)
    return round((n - f) * g + (f - 1) * width + 0.005, 2)


def stair_to(sid, top, direction, h, width=1.0):
    """A straight stair whose top is `top`, rising towards `direction` ('e', 'w', 'n', 's')."""
    run = stair_run(h, width)
    dx, dy = {'e': (run, 0), 'w': (-run, 0), 'n': (0, run), 's': (0, -run)}[direction]
    return stair_straight(sid, [round(top[0] - dx, 3), round(top[1] - dy, 3), 0.0], direction, h, width)


def bridge_deck(sid, centre, r, z):
    """A clarifier's (or the thickener's) bridge deck, walkable: the square round the drive at the centre, the strip
    to north over the wall (the part's -x at yaw 90) and the landing beyond it, where the stair arrives from the west
    (rising eastwards: a walker from the train comes from the west and walks straight onto it; a foot at the east end
    made walkers turn back round the stair's rail end, where they caught: tests/test_walk.gd). Returns the platform
    and the landing's stair top."""
    rim = r + WALL
    out = rim + BRIDGE_OUT
    poly = [[-1.4, -1.4], [1.4, -1.4], [1.4, 1.4], [0.75, 1.4], [0.75, out], [-1.75, out], [-1.75, rim],
            [-0.75, rim], [-0.75, 1.4], [-1.4, 1.4]]
    deck = st(sid, 'platform', [centre[0], centre[1], z], outline=poly, deck='grating', edge='handrail')
    return deck, [round(centre[0] - 1.7, 3), round(centre[1] + rim + BRIDGE_OUT / 2, 3), z]


# ---------------------------------------------------------------- the intake on the river bank

PIT = (441, 80.5, 28.5, 9)         # the intake's channel and wet well: x0, y0, length (east), width
PIT_DEPTH = 7.0
RIVER_LEVEL = -1.5
RAW_X = (444, 448, 452)


def intake():
    x0, y0, L, W = PIT
    deck_openings = [box(21.5, 0.5, 28.0, 8.5),                 # the approach channel, the bar screen across it
                     box(19.0, 0.8, 20.0, 3.7), box(19.0, 5.3, 20.0, 8.2)]   # the band screens' slots
    level = child('00GAA10CL001', 'Intake level', 'level_transmitter', [9, -4.25, PIT_DEPTH],
                  {'range': [-3, 1], 'unit': 'm'})
    skid_at = [437.0, 85.0, 0]
    equipment = [
        eq('00GAA10BB001', 'Intake channel and wet well', 'basin', [x0 + L / 2, y0 + W / 2, -PIT_DEPTH], 0,
           {'length': L, 'width': W, 'depth': round(PIT_DEPTH + RIVER_LEVEL - 0.03, 2)}, None, [level]),
        eq('00GAA10AT001', 'Bar screen', 'bar_screen', [468.5, 85, 0], 270, {'width': 8.0, 'depth': PIT_DEPTH}, 'side'),
        eq('00GAA10AT002', 'Band screen A', 'screen_band', [460.5, 82.75, 0], 270,
           {'width': 3.0, 'depth': PIT_DEPTH, 'motor_kw': 1.5}, 'side'),
        eq('00GAA10AT003', 'Band screen B', 'screen_band', [460.5, 87.25, 0], 270,
           {'width': 3.0, 'depth': PIT_DEPTH, 'motor_kw': 1.5}, 'side'),
        dosing('00GBN30', 'Hypochlorite', skid_at, 0, 1000),
    ]
    pipes = [pipe('00GAC10BR010', 'Raw water main to the water treatment plant', 'raw_water', 500, free([455, 79, -1.5]),
                  [[386, 79, -1.5], [386, 112, -1.5]], free([383.5, 112, -1.5]), buried=[[0, 2]], arrows=25)]
    for n, x in enumerate(RAW_X, 1):
        letter = 'ABC'[n - 1]
        equipment.append(eq(f'00GAF10AP00{n}', f'Raw water pump {letter}', 'pump_vertical', [x, 85, 0], 180,
                            {'flow_m3h': 550, 'head_m': 30, 'motor_kw': 75, 'pit_depth': PIT_DEPTH - 0.5}, 'motor_side'))
        pipes.append(pipe(f'00GAF10BR00{n}', f'Raw water pump {letter} discharge', 'raw_water', 300,
                          nz(f'00GAF10AP00{n}', 'discharge'), [[x, 79, 1.5]], jn('00GAC10BR010', [x, 79, -1.5]),
                          valves=[valve(f'00GAF10AA20{n}', 'valve_check', 0.15, f'Raw water pump {letter} check valve',
                                        dn=300),
                                  valve(f'00GAF10AA10{n}', 'valve_butterfly', 0.4,
                                        f'Raw water pump {letter} discharge valve', dn=300, actuator='electric')],
                          parts=[inst(f'00GAF10CP50{n}', 'pressure_gauge', 0.06, 'top',
                                      f'Raw water pump {letter} discharge pressure', range=[0, 6], unit='bar')]))
    structures = [
        st('intake_pit', 'pit', [x0, y0, 0], outline=rect(L, W), depth=PIT_DEPTH),
        st('intake_deck', 'platform', [x0, y0, 0], outline=rect(L, W), openings=deck_openings, deck='concrete',
           edge='handrail'),
        # the wall between the two band screens' channels, from the channel's floor to the deck
        st('intake_divider', 'wall', [455.5, 85, -PIT_DEPTH], route=[[0, 0, 0], [6.5, 0, 0]], height=PIT_DEPTH,
           thickness=0.4),
        # the intake house over the wet well, the pumps and the screens; the channel runs on under its east wall
        # and the road to the river (site.gd draws the river and the channel's headwall on its bank)
        st('intake_house', 'building', [434, 77, 0], kks='00UGA10', outline=rect(36, 16), height=9, floor='concrete',
           openings=[{'kind': 'door', 'at': [12, 0, 0], 'width': 4, 'height': 4.5},
                     {'kind': 'door', 'at': [0, 8, 0], 'width': 1.0, 'height': 2.1},
                     louvre(0, 3, 7), louvre(0, 13, 7), louvre(5, 16, 7), louvre(18, 16, 7), louvre(31, 16, 7),
                     louvre(36, 13, 7), window(5, 0, 4.5), window(19, 0, 4.5), window(30, 0, 4.5),
                     window(10, 16, 4.5), window(25, 16, 4.5)]),
        st('intake_door_s', 'door', [446, 77, 0], 180, kind='roller', width=4, height=4.5),
        st('intake_door_w', 'door', [434, 85, 0], 270, kind='personnel'),
    ]
    signs = [sign('Raw water intake 00UGA10', [440, 77, 5.2], 180), sign('Raw water pumps A B C', [448, 92.9, 3], 180)]
    return area('intake', 'Raw water intake', [[430, 60], [470, 110]], equipment, pipes, structures, signs)


def dosing(sys_code, chem, at, yaw, tank_l, pumps=2):
    """A dosing skid (its day tank coded BB001) with its metering pumps (AP001, AP002) on the skid's plinth, placed
    as kit/parts_water.gd dosing_skid lays the skid out."""
    L, W = 2.4, 1.2
    V = tank_l / 1000.0
    td = min(max((4 * V / (1.3 * math.pi)) ** (1 / 3), 0.4), min(W, L * 0.6))
    yt = -L / 2 + td / 2 + 0.08
    y0 = yt + td / 2 + 0.3
    kids = [child(f'{sys_code}AP00{k}', f'{chem} dosing pump {"AB"[k - 1]}', 'metering_pump',
                  [0, round(y0 + 0.15 + 0.45 * (k - 1), 3), 0.2], {'kw': 0.37}) for k in range(1, pumps + 1)]
    return eq(f'{sys_code}BB001', f'{chem} day tank and dosing skid', 'dosing_skid', at, yaw,
              {'length': L, 'width': W, 'tank_l': tank_l}, 'front', kids)


# ---------------------------------------------------------------- the treatment plant

CLAR = {'a': (362, 122), 'b': (362, 99)}
CLAR_D, CLAR_H = 17, 4.7
FILTER = (335, 111)               # the filter bank's centre; its axis east (yaw 90)
FILTER_L, FILTER_W, FILTER_G, FILTER_H = 16.5, 5, 3.5, 4.5
TANK_FW = (296, 118)              # the filtered water tank
DEMIN = {'a': (283, 66), 'b': (283, 84)}
BLD = (300, 50, 40, 25)           # the treatment building: x0, y0, length (east), width (north)
RO_X = {'a': 317.6, 'b': 324.6}   # each RO stream's line: cartridge filter, HP pump, the train's feed
MB_Y = {'a': 70, 'b': 64}


def pretreatment():
    eqs, pipes, sts = [], [], []
    # the rapid mixer: a concrete tank, its agitator on the access deck over it
    eqs.append(eq('00GBD10BB001', 'Rapid mix tank', 'basin', [383, 112, 0], 0, {'length': 4, 'width': 4, 'depth': 4.25},
                  'edge'))
    eqs.append(eq('00GBD10AM001', 'Rapid mixer', 'agitator', [383, 112, 4.5], 0, {'kw': 5.5, 'd': 1.2, 'shaft': 3.3},
                  'motor'))
    sts.append(st('wtp_mixer_deck', 'platform', [380.6, 109.6, 4.5], outline=rect(4.8, 4.8), deck='grating',
                  edge='handrail'))
    sts.append(stair_to('wtp_mixer_stair', [380.7, 112, 4.5], 'e', 4.5))   # from the west, as walkers come
    # the clarifiers: bridges to the north (the part's -x at yaw 90), stairs from the east up to their landings
    for k, (cx, cy) in CLAR.items():
        n = 1 if k == 'a' else 2
        L = k.upper()
        tq = child(f'00GBD1{n}CQ001', f'Clarifier {L} clarified water turbidity', 'local_panel', [-1.5, 9.8, 0],
                   {'width': 0.5, 'height': 0.8}, 90)
        eqs.append(eq(f'00GBD1{n}AT001', f'Clarifier {L}', 'clarifier', [cx, cy, 0], 90,
                      {'d': CLAR_D, 'height': CLAR_H, 'bridge': True}, 'wall', [tq]))
        deck, top = bridge_deck(f'wtp_clar_{k}_bridge', (cx, cy), CLAR_D / 2, CLAR_H + DECK_OVER)
        sts.append(deck)
        sts.append(stair_to(f'wtp_clar_{k}_stair', top, 'e', CLAR_H + DECK_OVER))
    # coagulated water from the rapid mixer to the clarifiers' centre wells (under the ground)
    pipes.append(pipe('00GBD11BR001', 'Coagulated water to clarifier A', 'raw_water', 400, free([381.5, 113, -2]),
                      [[366, 113, -2], [366, 122, -2], [362, 122, -2]], nz('00GBD11AT001', 'inlet'), buried=[[0, 3]]))
    pipes.append(pipe('00GBD12BR001', 'Coagulated water to clarifier B', 'raw_water', 400, free([381.5, 111, -2.5]),
                      [[366.5, 111, -2.5], [366.5, 99, -2.5], [362, 99, -2.5]], nz('00GBD12AT001', 'inlet'),
                      buried=[[0, 3]]))
    # clarified water to the filters' inlet channel
    pipes.append(pipe('00GBD10BR002', 'Clarified water to the filters', 'clarified_water', 500,
                      nz('00GBD12AT001', 'outlet'), [[347, 99, 3.8], [347, 111, 3.8]], nz('00GBB10', 'inlet'),
                      arrows=10))
    pipes.append(pipe('00GBD11BR002', 'Clarified water from clarifier A', 'clarified_water', 500,
                      nz('00GBD11AT001', 'outlet'), [[350, 122, 3.8], [350, 105, 3.8]],
                      jn('00GBD10BR002', [347, 105, 3.8]), arrows=10))
    # the gravity filter bank: six cells in two rows (filters 1-3 south, 4-6 north), the gallery between them, the
    # operating deck over the gallery, its stair from the north; each filter's outlet valve and head loss in the
    # gallery, its number board at the deck's edge
    cl = (FILTER_L - 0.3) / 3
    kids = []
    for n in range(1, 7):
        south = n <= 3
        i = (n - 1) % 3
        yc = round(-FILTER_L / 2 + 0.3 + cl * i + (cl - 0.3) / 2, 3)   # along the bank (east)
        s = 1 if south else -1                                          # the part's +x is south
        kids.append(child(f'00GBB1{n}AA001', f'Filter {n} outlet valve', 'valve_butterfly',
                          [round(1.05 * s, 3), yc, 0.8], {'dn': 250, 'actuator': 'electric'}, 90))
        kids.append(child(f'00GBB1{n}CP001', f'Filter {n} head loss', 'pressure_transmitter',
                          [round((FILTER_G / 2 - 0.1) * s, 3), round(yc + 1.0, 3), 1.6],
                          {'range': [0, 3], 'unit': 'm'}, 270 if south else 90))
        kids.append(child(f'00GBB1{n}AT001', f'Filter {n}', 'sign', [round((FILTER_G / 2 + 0.15) * s, 3), yc,
                                                                      FILTER_H], {'size': 0.3},
                          270 if south else 90))
    eqs.append(eq('00GBB10', 'Gravity filter bank (filters 1 to 6)', 'filter_bank', [FILTER[0], FILTER[1], 0], 90,
                  {'cells': 6, 'length': FILTER_L, 'width': FILTER_W, 'gallery': FILTER_G, 'height': FILTER_H},
                  'end', kids))
    x0 = FILTER[0] - FILTER_L / 2
    deck_y0 = FILTER[1] - FILTER_G / 2 - 0.3
    sts.append(st('wtp_filter_deck', 'platform', [x0 - 4, deck_y0, FILTER_H],
                  outline=rect(FILTER_L + 4, FILTER_G + 0.6), deck='grating', edge='handrail'))
    sts.append(stair_to('wtp_filter_stair', [x0 - 2, deck_y0 + FILTER_G + 0.6 - 0.1, FILTER_H], 's', FILTER_H))
    # backwash pumps and air scour blowers by the bank's west end; their lines go under the ground to the gallery
    for n, y in ((1, 100), (2, 96)):
        L = 'AB'[n - 1]
        eqs.append(eq(f'00GBR10AP00{n}', f'Filter backwash pump {L}', 'pump_horizontal', [318, y, 0], 90,
                      {'flow_m3h': 1100, 'head_m': 15, 'motor_kw': 75, 'length': 3}, 'motor_side'))
        pipes.append(pipe(f'00GBR10BR00{n}', f'Backwash pump {L} suction from the filtered water tank',
                          'filtered_water', 400, free([321, y, -1]), [[321, y, 0.6]], nz(f'00GBR10AP00{n}', 'suction')))
        pipes.append(pipe(f'00GBR10BR01{n}', f'Backwash pump {L} discharge to the filter gallery', 'filtered_water',
                          300, nz(f'00GBR10AP00{n}', 'discharge'), [[318.75, y, 2.8], [316.5, y, 2.8]],
                          free([316.5, y, -1])))
    for n, x in ((1, 323), (2, 326)):
        L = 'AB'[n - 1]
        eqs.append(eq(f'00GBR10AN00{n}', f'Air scour blower {L}', 'compressor_skid', [x, 96, 0], 0,
                      {'kw': 55, 'length': 3, 'width': 1.6}, 'side'))
        pipes.append(pipe(f'00GBR10BR02{n}', f'Air scour blower {L} to the filter gallery', 'air', 150,
                          nz(f'00GBR10AN00{n}', 'air_out'), [[x, 99.5, 1.0]], free([x, 99.5, -1])))
    # filtered water from the gallery to the filtered water tank
    pipes.append(pipe('00GBB10BR001', 'Filtered water to the filtered water tank', 'filtered_water', 300,
                      nz('00GBB10', 'outlet'), [[324.5, 111, 0.8], [324.5, 111, -1.2], [312, 111, -1.2],
                                                [312, 118, -1.2], [312, 118, 5.85]],
                      nz('00GBL10BB001', 'inlet'), buried=[[2, 3]], arrows=10))
    return eqs, pipes, sts


def filtered_water():
    """The filtered water tank, the cooling tower makeup pumps and the service water pumps, and the makeup line to
    the cooling tower (SITE.md §1: overhead on posts along the plant's west side and y = 38, then under the ground to
    the cooling tower's makeup pipe 30PAR10BR001)."""
    eqs = [eq('00GBL10BB001', 'Filtered water tank', 'tank_vertical', [TANK_FW[0], TANK_FW[1], 0], 270,
              {'d': 15, 'height': 6.5, 'roof': 'cone'}, 'side',
              [child('00GBL10CL001', 'Filtered water tank level', 'level_transmitter', [7.8, 0, 1],
                     {'range': [0, 6500], 'unit': 'mm'})])]
    pumps = [('00GHB10AP001', 'Cooling tower makeup pump A', 126, 'mk'), ('00GHB10AP002', 'Cooling tower makeup pump B',
                                                                           122, 'mk'),
             ('00GHA10AP001', 'Service water pump A', 114, 'sw'), ('00GHA10AP002', 'Service water pump B', 110, 'sw')]
    for code, name, y, kind in pumps:
        p = ({'flow_m3h': 900, 'head_m': 40, 'motor_kw': 160, 'length': 3} if kind == 'mk' else
             {'flow_m3h': 120, 'head_m': 50, 'motor_kw': 30, 'length': 2})
        x = 281 - p['length'] / 2
        eqs.append(eq(code, name, 'pump_horizontal', [x, y, -0.1], 90, p, 'motor_side',
                      [pg(code[:7] + 'CP00' + code[-1], f'{name} discharge pressure', [0, 10],
                          [0.6, p['length'] / 4, 1.8])]))
    pipes = [
        pipe('00GBL10BR002', 'Filtered water suction header (makeup pumps)', 'filtered_water', 500,
             nz('00GBL10BB001', 'outlet'), [[284, 118, 0.5], [284, 126, 0.5]], nz('00GHB10AP001', 'suction')),
        pipe('00GHB10BR012', 'Makeup pump B suction', 'filtered_water', 500, jn('00GBL10BR002', [284, 122, 0.5]), [],
             nz('00GHB10AP002', 'suction')),
        pipe('00GBL10BR003', 'Filtered water suction header (service water pumps)', 'filtered_water', 300,
             jn('00GBL10BR002', [286, 118, 0.5]), [[286, 110, 0.5]], nz('00GHA10AP002', 'suction')),
        pipe('00GHA10BR011', 'Service water pump A suction', 'filtered_water', 300, jn('00GBL10BR003', [286, 114, 0.5]),
             [], nz('00GHA10AP001', 'suction')),
        pipe('00GHB10BR001', 'Cooling tower makeup water', 'filtered_water', 400, nz('00GHB10AP001', 'discharge'),
             [[280.25, 126, 5], [271, 126, 5], [271, 38, 5], [262, 38, 5], [262, 3, 5], [262, 3, -0.6],
              [258, 3, -0.6]], jn('30PAR10BR001', [258, 0, -0.6]), buried=[[6, 7]], arrows=20,
             valves=[valve('00GHB10AA201', 'valve_check', 0.008, 'Makeup pump A check valve', dn=400),
                     valve('00GHB10AA101', 'valve_gate', 0.017, 'Makeup pump A discharge valve', dn=400)]),
        pipe('00GHB10BR002', 'Makeup pump B discharge', 'filtered_water', 400, nz('00GHB10AP002', 'discharge'),
             [[280.25, 122, 5], [276, 122, 5]], jn('00GHB10BR001', [276, 126, 5]),
             valves=[valve('00GHB10AA202', 'valve_check', 0.15, 'Makeup pump B check valve', dn=400),
                     valve('00GHB10AA102', 'valve_gate', 0.38, 'Makeup pump B discharge valve', dn=400)]),
    ]
    for n, y in ((1, 114), (2, 110)):
        L = 'AB'[n - 1]
        pipes.append(pipe(f'00GHA10BR00{n}', f'Service water pump {L} discharge (to the service water main)',
                          'filtered_water', 200, nz(f'00GHA10AP00{n}', 'discharge'), [[280.5, y, 2.6], [277, y, 2.6]],
                          free([277, y, -1]),
                          valves=[valve(f'00GHA10AA10{n}', 'valve_gate', 0.3, f'Service water pump {L} discharge valve',
                                        dn=200)]))
    return eqs, pipes


def treatment_building():
    bx, by, bl, bw = BLD
    eqs, pipes = [], []
    for k, x in RO_X.items():
        n = 1 if k == 'a' else 2
        L = k.upper()
        eqs.append(eq(f'00GCB1{n}AT001', f'Cartridge filter {L}', 'cartridge_housing', [x, by + 1.5, 0], 270,
                      {'d': 0.7, 'height': 1.8}, 'side',
                      [child(f'00GCB1{n}CP001', f'Cartridge filter {L} differential pressure', 'pressure_transmitter',
                             [0.55, 0.45, 1.3], {'range': [0, 2], 'unit': 'bar'})]))
        eqs.append(eq(f'00GCB2{n}AP001', f'RO high-pressure pump {L}', 'pump_horizontal', [x, by + 5, 0], 180,
                      {'flow_m3h': 53, 'head_m': 130, 'motor_kw': 37, 'length': 2.5}, 'motor_side',
                      [pg(f'00GCB2{n}CP002', f'RO {L} high-pressure pump suction pressure', [0, 6], [0.5, 0.9, 0.9])]))
        ro = [pg(f'00GCB2{n}CP001', f'RO {L} feed pressure', [0, 25], [0.8, -2.6, 1.3]),
              child(f'00GCB2{n}CQ001', f'RO {L} permeate conductivity', 'local_panel', [1.2, 3.0, 0],
                    {'width': 0.4, 'height': 0.6}, 270),
              child(f'00GCB2{n}CQ002', f'RO {L} feed ORP', 'local_panel', [-1.2, -2.9, 0],
                    {'width': 0.4, 'height': 0.6}, 90)]
        eqs.append(eq(f'00GCB2{n}AT001', f'Reverse osmosis train {L}', 'ro_train', [x + 0.4, by + 13.5, 0], 0,
                      {'stage1': 6, 'stage2': 3, 'elements': 6}, 'frame', ro))
        pipes.append(pipe(f'00GCB1{n}BR001', f'RO {L} feed from the service water main', 'filtered_water', 100,
                          free([x, by + 0.5, -1]), [[x, by + 0.5, 1.08]], nz(f'00GCB1{n}AT001', 'inlet')))
        pipes.append(pipe(f'00GCB1{n}BR002', f'Cartridge filter {L} to the high-pressure pump', 'filtered_water', 100,
                          nz(f'00GCB1{n}AT001', 'outlet'), [], nz(f'00GCB2{n}AP001', 'suction')))
        pipes.append(pipe(f'00GCB2{n}BR001', f'RO {L} feed', 'filtered_water', 80, nz(f'00GCB2{n}AP001', 'discharge'),
                          [[x, by + 4.375, 2.4], [x, by + 8.2, 2.4], [x, by + 8.2, 0.3]], nz(f'00GCB2{n}AT001', 'feed_in'),
                          valves=[valve(f'00GCB2{n}AA101', 'valve_globe', 0.3, f'RO {L} feed valve', dn=80,
                                        rating='pn25', actuator='electric')]))
        pipes.append(pipe(f'00GCB2{n}BR003', f'RO {L} concentrate to drain', 'raw_water', 50,
                          nz(f'00GCB2{n}AT001', 'concentrate_out'), [[x + 0.8, by + 18, 0.3]],
                          free([x + 0.8, by + 18, -1]),
                          valves=[valve(f'00GCB2{n}AA301', 'valve_control', 0.25, f'RO {L} concentrate valve', dn=50,
                                        rating='pn25', actuator='pneumatic')]))
    pipes.append(pipe('00GCB21BR002', 'RO permeate to the degasser', 'permeate', 80, nz('00GCB21AT001', 'permeate_out'),
                      [[317.6, 68.5, 0.55], [317.6, 68.5, 6.3], [317.6, 79, 6.3], [301.5, 79, 6.3], [301.5, 88.5, 6.3]],
                      nz('00GCH10AT001', 'inlet'), arrows=10,
                      parts=[inst('00GCB21CF001', 'flow_element', 0.015, 'top', 'RO A permeate flow', kind='magnetic',
                                  range=[0, 60], unit='m³/h')]))
    pipes.append(pipe('00GCB22BR002', 'RO B permeate', 'permeate', 80, nz('00GCB22AT001', 'permeate_out'),
                      [[324.6, 70, 0.55], [324.6, 70, 6.3]], jn('00GCB21BR002', [317.6, 70, 6.3]),
                      parts=[inst('00GCB22CF001', 'flow_element', 0.05, 'top', 'RO B permeate flow', kind='magnetic',
                                  range=[0, 60], unit='m³/h')]))
    # the mixed beds, their analysers, the regenerant tanks and the resin mixing blower
    for k, y in MB_Y.items():
        n = 1 if k == 'a' else 2
        L = k.upper()
        eqs.append(eq(f'00GCF1{n}AT001', f'Mixed bed {L}', 'ion_exchanger', [304, y, 0], 270, {'d': 1.6, 'height': 2.5},
                      'front',
                      [child(f'00GCF1{n}CQ001', f'Mixed bed {L} outlet conductivity', 'local_panel', [1.3, -0.6, 0],
                             {'width': 0.4, 'height': 0.6}, 180),
                       child(f'00GCF1{n}CQ002', f'Mixed bed {L} outlet silica', 'local_panel', [1.3, 0.3, 0],
                             {'width': 0.4, 'height': 0.6}, 180)]))
    eqs.append(eq('00GCP10BB001', 'Regeneration acid tank (hydrochloric acid)', 'chemical_tank', [303.5, 53.3, 0], 0,
                  {'d': 1.4, 'height': 2.2, 'bund': True}, 'side'))
    eqs.append(eq('00GCP20BB001', 'Regeneration caustic tank (sodium hydroxide)', 'chemical_tank', [307.5, 53.3, 0], 0,
                  {'d': 1.4, 'height': 2.2, 'bund': True}, 'side'))
    eqs.append(eq('00GCP30AN001', 'Resin mixing air blower', 'compressor_skid', [303, 58, 0], 0,
                  {'kw': 7.5, 'length': 1.6, 'width': 1.0}, 'side'))
    # the WTP's control room and laboratory (behind the partitions at the east end)
    eqs.append(eq('00CWD10', 'Water treatment plant control desk', 'operator_desk', [335, 68.8, 0], 180,
                  {'width': 3.2, 'screens': 3}, 'front'))
    eqs.append(eq('00QUG10', 'Water treatment sample panel', 'sample_panel', [339.4, 59.5, 0], 270,
                  {'width': 2.4, 'points': 6}, 'front'))
    eqs.append(eq('00QUG20', 'Laboratory bench (analysers)', 'lab_bench', [334.5, 50.9, 0], 0, {'length': 3}, 'front'))
    openings = [{'kind': 'door', 'at': [22, bw, 0], 'width': 4, 'height': 4.5},
                {'kind': 'door', 'at': [36, bw, 0], 'width': 1.0, 'height': 2.1},
                {'kind': 'door', 'at': [0, 6, 0], 'width': 1.0, 'height': 2.1},
                {'kind': 'door', 'at': [bl, 3, 0], 'width': 1.0, 'height': 2.1},
                {'kind': 'pipe', 'at': [17.6, bw, 6.3], 'width': 0.5, 'height': 0.5},
                {'kind': 'pipe', 'at': [16.8, bw, 5.5], 'width': 0.5, 'height': 0.5},
                {'kind': 'pipe', 'at': [0, 18.5, 7.5], 'width': 0.5, 'height': 0.5},
                {'kind': 'pipe', 'at': [0, 12.5, 6.9], 'width': 0.5, 'height': 0.5},
                louvre(8, bw, 8.2), louvre(30, bw, 8.2), louvre(10, 0, 8.2), louvre(30, 0, 8.2),
                window(6, 0, 3.2), window(14, 0, 3.2), window(24, 0, 3.2), window(34, 0, 2.2, 1.6, 1.0),
                window(bl, 18, 2.0, 2.0, 1.0), window(30, bw, 2.2, 2.0, 1.0)]
    structures = [
        st('wtp_building', 'building', [bx, by, 0], kks='00UGD10', outline=rect(bl, bw), height=10, floor='epoxy',
           openings=openings),
        st('wtp_door_n', 'door', [322, 75, 0], 0, kind='roller', width=4, height=4.5),
        st('wtp_door_ctl', 'door', [336, 75, 0], 0, kind='personnel'),
        st('wtp_door_w', 'door', [300, 56, 0], 270, kind='personnel'),
        st('wtp_door_e', 'door', [340, 53, 0], 90, kind='personnel'),
        # the partitions of the control room (north) and the laboratory (south), each open to the hall by a doorway
        st('wtp_wall_lab_w', 'wall', [330, 50.25, 0], route=[[0, 0, 0], [0, 4.6, 0]], height=3.2, thickness=0.2),
        st('wtp_wall_mid_w', 'wall', [330, 56.05, 0], route=[[0, 0, 0], [0, 10.9, 0]], height=3.2, thickness=0.2),
        st('wtp_wall_ctl_w', 'wall', [330, 68.35, 0], route=[[0, 0, 0], [0, 6.4, 0]], height=3.2, thickness=0.2),
        st('wtp_wall_lab_n', 'wall', [330.1, 62.5, 0], route=[[0, 0, 0], [9.65, 0, 0]], height=3.2, thickness=0.2),
    ]
    signs = [sign('Water treatment building 00UGD10', [300, 66, 3.2], 270),
             sign('RO trains', [327, 74.75, 3.4], 180, 0.3), sign('Mixed beds', [300.25, 67, 2.6], 90, 0.25),
             sign('WTP control room', [330, 71.5, 2.4], 270, 0.25), sign('Laboratory', [330, 52.5, 2.4], 270, 0.25)]
    signs += hearing_signs(structures, flip=('wtp_door_e', 'wtp_door_ctl'))
    return eqs, pipes, structures, signs


def degassing_and_demin():
    eqs, pipes = [], []
    eqs.append(eq('00GCH10AT001', 'Degasser tower', 'degasser', [305, 88.5, 0], 90, {'d': 1.8, 'height': 7}, 'side',
                  [child('00GCH10AN001', 'Degasser blower', 'compressor_skid', [2.6, 0.25, 0],
                         {'kw': 4, 'length': 1.4, 'width': 0.9}, 270)]))
    eqs.append(eq('00GCK10BB001', 'Degassed water tank', 'tank_vertical', [312, 88.5, 0], 90,
                  {'d': 4, 'height': 4, 'roof': 'cone'}, 'side'))
    for n, y in ((1, 88.5), (2, 85.5)):
        L = 'AB'[n - 1]
        eqs.append(eq(f'00GCK10AP00{n}', f'Mixed bed feed pump {L}', 'pump_horizontal', [317.3, y, -0.1], 270,
                      {'flow_m3h': 45, 'head_m': 45, 'motor_kw': 11, 'length': 2}, 'motor_side'))
    pipes += [
        pipe('00GCH10BR001', 'Degassed water to the degassed water tank', 'permeate', 100, nz('00GCH10AT001', 'outlet'),
             [[307.2, 88.5, 0.9], [307.2, 88.5, 3.6]], nz('00GCK10BB001', 'inlet')),
        pipe('00GCK10BR011', 'Mixed bed feed pump A suction', 'permeate', 80, nz('00GCK10BB001', 'outlet'), [],
             nz('00GCK10AP001', 'suction')),
        pipe('00GCK10BR012', 'Mixed bed feed pump B suction', 'permeate', 80, jn('00GCK10BR011', [315, 88.5, 0.5]),
             [[315, 85.5, 0.5]], nz('00GCK10AP002', 'suction')),
        pipe('00GCK10BR001', 'Degassed water to mixed bed A', 'permeate', 80, nz('00GCK10AP001', 'discharge'),
             [[316.8, 88.5, 5.5], [316.8, 72, 5.5], [307, 72, 5.5], [307, 72, 3.3], [307, 70, 3.3]],
             nz('00GCF11AT001', 'inlet')),
        pipe('00GCK10BR002', 'Mixed bed feed pump B discharge', 'permeate', 80, nz('00GCK10AP002', 'discharge'),
             [[316.8, 85.5, 3.0]], jn('00GCK10BR001', [316.8, 88.5, 3.0])),
        pipe('00GCF12BR001', 'Degassed water to mixed bed B', 'permeate', 80, jn('00GCK10BR001', [309, 72, 5.5]),
             [[309, 64, 5.5], [309, 64, 3.3]], nz('00GCF12AT001', 'inlet')),
        pipe('00GCF11BR002', 'Demineralised water from mixed bed A to demineralised water tank A', 'demin_water', 80,
             nz('00GCF11AT001', 'outlet'), [[306.4, 70, 0.5], [306.4, 68.5, 0.5], [306.4, 68.5, 7.5], [298, 68.5, 7.5],
                                            [298, 66, 7.5], [298, 66, 10.8]], nz('00GCL10BB001', 'inlet'), arrows=10),
        pipe('00GCF12BR002', 'Demineralised water from mixed bed B to demineralised water tank B', 'demin_water', 80,
             nz('00GCF12AT001', 'outlet'), [[306.4, 64, 0.5], [306.4, 62.5, 0.5], [306.4, 62.5, 6.9], [297, 62.5, 6.9],
                                            [297, 84, 6.9], [297, 84, 10.8]], nz('00GCL10BB002', 'inlet'), arrows=10),
    ]
    for k, (x, y) in DEMIN.items():
        n = 1 if k == 'a' else 2
        L = k.upper()
        eqs.append(eq(f'00GCL10BB00{n}', f'Demineralised water tank {L}', 'tank_vertical', [x, y, 0], 270,
                      {'d': 13, 'height': 12, 'roof': 'dome'}, 'side',
                      [child(f'00GCL10CL00{n}', f'Demineralised water tank {L} level', 'level_transmitter', [6.8, 0, 1],
                             {'range': [0, 12000], 'unit': 'mm'})]))
        eqs.append(eq(f'00GHC10AP00{n}', f'Demineralised water transfer pump {L}', 'pump_horizontal', [273.5, y, -0.1],
                      90, {'flow_m3h': 40, 'head_m': 60, 'motor_kw': 15, 'length': 2.5}, 'motor_side'))
        pipes.append(pipe(f'00GCL10BR01{n}', f'Demineralised water tank {L} to transfer pump {L}', 'demin_water', 100,
                          nz(f'00GCL10BB00{n}', 'outlet'), [], nz(f'00GHC10AP00{n}', 'suction')))
    pipes.append(pipe('00GHC10BR001', 'Demineralised water transfer to the plant\'s demineralised water tank',
                      'demin_water', 100, nz('00GHC10AP001', 'discharge'),
                      [[274.125, 66, 6.5], [274.125, 39.5, 6.5], [133, 39.5, 6.5], [133, 4, 6.5], [125, 4, 6.5],
                       [125, 4, 9]], nz('00GHC10BB001', 'inlet'), arrows=20,
                      valves=[valve('00GHC10AA201', 'valve_check', 0.006, 'Transfer pump A check valve', dn=100),
                              valve('00GHC10AA101', 'valve_gate', 0.014, 'Transfer pump A discharge valve', dn=100)]))
    pipes.append(pipe('00GHC10BR002', 'Transfer pump B discharge', 'demin_water', 100, nz('00GHC10AP002', 'discharge'),
                      [[274.125, 84, 4.0]], jn('00GHC10BR001', [274.125, 66, 4.0]),
                      valves=[valve('00GHC10AA202', 'valve_check', 0.1, 'Transfer pump B check valve', dn=100),
                              valve('00GHC10AA102', 'valve_gate', 0.14, 'Transfer pump B discharge valve', dn=100)]))
    return eqs, pipes


def chemicals_and_wastes():
    eqs, pipes = [], []
    for x, code, chem, litres in ((348, '00GBN10', 'Coagulant (ferric chloride)', 2000),
                                  (351.5, '00GBN20', 'Polymer', 1000),
                                  (355, '00GCN10', 'Sodium bisulphite', 1000),
                                  (358.5, '00GCN20', 'Antiscalant', 500),
                                  (362, '00GCE10', 'Acid', 1000)):
        eqs.append(dosing(code, chem, [x, 51.5, 0], 0, litres))
    # the neutralisation pit: its water, the bridge across it with the agitator and the discharge pumps
    eqs.append(eq('00GNR10BB001', 'Neutralisation pit', 'basin', [373, 67, -3], 0,
                  {'length': 10, 'width': 6, 'depth': 2.2}, None,
                  [child('00GNR10CQ001', 'Neutralisation pit pH', 'temperature_element', [1.3, -2.75, 3.1],
                         {'range': [0, 14], 'unit': 'pH'})]))
    eqs.append(eq('00GNR10AM001', 'Neutralisation pit agitator', 'agitator', [373.8, 67, 0], 0,
                  {'kw': 4, 'd': 1.0, 'shaft': 2.3}, 'motor'))
    for n, y in ((1, 65.2), (2, 68.8)):
        L = 'AB'[n - 1]
        eqs.append(eq(f'00GNR10AP00{n}', f'Neutralisation pit discharge pump {L}', 'pump_vertical', [372.4, y, 0], 270,
                      {'flow_m3h': 60, 'head_m': 20, 'motor_kw': 7.5, 'pit_depth': 2.6}, 'motor_side'))
        pipes.append(pipe(f'00GNR10BR00{n}', f'Neutralisation pit discharge pump {L} to the outfall', 'raw_water', 100,
                          nz(f'00GNR10AP00{n}', 'discharge'), [[366.5, y, 1.5]], free([366.5, y, -1])))
    # the sludge thickener and the filter press
    tq = []
    eqs.append(eq('00GBS10AT001', 'Sludge thickener', 'thickener', [380, 80, 0], 90, {'d': 10, 'height': CLAR_H,
                                                                                         'bridge': True}, 'wall', tq))
    eqs.append(eq('00GBS20AT001', 'Sludge filter press', 'filter_press', [383, 52.5, 0], 0,
                  {'plates': 60, 'length': 6}, 'side'))
    deck, top = bridge_deck('wtp_thick_bridge', (380, 80), 5, CLAR_H + DECK_OVER)
    structures = [
        st('wtp_chem_store', 'building', [345, 48, 0], kks='00UTS10', outline=rect(20, 13), height=6, floor='epoxy',
           openings=[{'kind': 'door', 'at': [10, 13, 0], 'width': 3, 'height': 3.5},
                     {'kind': 'door', 'at': [6.5, 0, 0], 'width': 1.0, 'height': 2.1},
                     louvre(4, 13, 4.6, 2, 1), louvre(16, 13, 4.6, 2, 1), louvre(20, 6.5, 4.6, 2, 1)]),
        st('wtp_chem_door_n', 'door', [355, 61, 0], 0, kind='roller', width=3, height=3.5),
        st('wtp_chem_door_s', 'door', [351.5, 48, 0], 180, kind='personnel'),
        st('wtp_neut_pit', 'pit', [368, 64, 0], outline=rect(10, 6), depth=3),
        st('wtp_neut_bridge', 'platform', [371.5, 64, 0], outline=rect(3, 6), deck='grating', edge='handrail'),
        deck, stair_to('wtp_thick_stair', top, 'e', CLAR_H + DECK_OVER),
        st('wtp_press_house', 'building', [376, 48, 0], kks='00UGQ10', outline=rect(12, 9), height=7,
           floor='concrete',
           openings=[{'kind': 'door', 'at': [0, 4.5, 0], 'width': 3, 'height': 3.5},
                     {'kind': 'door', 'at': [9, 9, 0], 'width': 1.0, 'height': 2.1},
                     louvre(12, 4.5, 5.5, 2, 1), window(4, 9, 3, 2, 1)]),
        st('wtp_press_door_w', 'door', [376, 52.5, 0], 270, kind='roller', width=3, height=3.5),
        st('wtp_press_door_n', 'door', [385, 57, 0], 0, kind='personnel'),
    ]
    signs = [sign('Chemical store 00UTS10', [350, 61, 3.4], 0), sign('Filter press house 00UGQ10', [380, 57, 3.6], 0),
             sign('Dosing: coagulant, polymer, SBS, antiscalant, acid', [355, 48.25, 3.2], 0, 0.25)]
    return eqs, pipes, structures, signs


def wtp():
    eqs, pipes, sts, signs = [], [], [], []
    e, p, s = pretreatment()
    eqs += e; pipes += p; sts += s
    e, p = filtered_water()
    eqs += e; pipes += p
    e, p, s, g = treatment_building()
    eqs += e; pipes += p; sts += s; signs += g
    e, p = degassing_and_demin()
    eqs += e; pipes += p
    e, p, s, g = chemicals_and_wastes()
    eqs += e; pipes += p; sts += s; signs += g
    signs += [sign('Gravity filters 00GBB10', [335, 103.65, 2.6], 180),
              sign('Filtered water tank 00GBL10BB001', [296, 110.5, 2.4], 180, 0.3),
              sign('Demineralised water tank A', [283, 72.5, 2.4], 0, 0.3),
              sign('Water treatment plant', [320, 50, 6.5], 180, 0.8)]
    return area('wtp', 'Water treatment plant', [[270, 45], [390, 135]], eqs, pipes, sts, signs)


def areas():
    return [wtp(), intake()]
