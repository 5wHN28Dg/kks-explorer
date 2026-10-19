"""The first train's areas (docs/plant3d/FIRST-TRAIN.md §1–§3 → docs/PLANT3D.md §3–§5): equipment at its plot-plan
position, pipe routes, structures and signs. Everything is invented (R1); sizes are round, typical values."""
import math

import kit

STAIR_GOING = 0.25


def eq(kks, name, part, at, yaw=0, params=None, plate=None, parts=None):
    e = {'kks': kks, 'name': name, 'part': part, 'at': at}
    if yaw:
        e['yaw'] = yaw
    if params:
        e['params'] = params
    if plate:
        e['plate'] = plate
    if parts:
        e['parts'] = parts
    return e


def first_plate(part):
    """The part's first tag plate point (kit.py), or None. Every valve and every piece of equipment with a code
    carries its tag plate, as in the field (PLANT3D.md §4 `plate`, §10); instruments get theirs from the kit when the
    content names none."""
    plates = kit.PARTS[part].get('plates', [])
    return plates[0] if plates and kit.PARTS[part]['group'] != 'instruments' else None


def child(kks, name, part, at, params=None, yaw=0):
    return eq(kks, name, part, at, yaw, params, first_plate(part))


def pipe(kks, name, medium, dn, frm, points, to, **kw):
    p = {'kks': kks, 'name': name, 'medium': medium, 'dn': dn, 'from': frm, 'points': points, 'to': to}
    p.update(kw)
    return p


def nz(kks, nozzle):
    return {'kks': kks, 'nozzle': nozzle}


def jn(pipe_code, at):
    return {'pipe': pipe_code, 'at': at}


def free(at):
    return {'at': at}


def valve(kks, part, at, name, **params):
    v = {'kks': kks, 'part': part, 'at': at, 'name': name}
    if params:
        v['params'] = params
    plate = first_plate(part)
    if plate:
        v['plate'] = plate
    return v


def inst(kks, part, at, side, name, **params):
    v = {'kks': kks, 'part': part, 'at': at, 'side': side, 'name': name}
    if params:
        v['params'] = params
    return v


def rect(w, h):
    return [[0, 0], [w, 0], [w, h], [0, h]]


def box(x0, y0, x1, y1):
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


def st(sid, part, at=None, yaw=0, kks=None, params=None, **kw):
    params = params or kw
    s = {'id': sid, 'part': part}
    if kks:
        s['kks'] = kks
    if at is not None:
        s['at'] = at
    if yaw:
        s['yaw'] = yaw
    if params:
        s['params'] = params
    return s


def stair_straight(sid, foot, direction, h, width=1.0):
    """A straight stair rising h from foot along direction ('e', 'w', 'n', 's'): the plan length the step rules give
    (rise ≤ 0.19 m, going max(0.25, 0.63 − 2 × rise), landings of the stair's width between flights of ≤ 3.6 m)."""
    n = math.ceil(h / 0.19)
    f = math.ceil(h / 3.6 - 1e-9)
    rise = h / n
    g = max(STAIR_GOING, 0.63 - 2 * rise)
    run = round((n - f) * g + (f - 1) * width + 0.005, 2)
    dx, dy = {'e': (run, 0), 'w': (-run, 0), 'n': (0, run), 's': (0, -run)}[direction]
    top = [round(foot[0] + dx, 3), round(foot[1] + dy, 3), round(foot[2] + h, 3)]
    return st(sid, 'stair', params={'foot': foot, 'top': top, 'layout': 'straight', 'width': width})


def stair_tower(sid, foot, top, width=1.2):
    return st(sid, 'stair', params={'foot': foot, 'top': top, 'layout': 'switchback', 'width': width})


def sign(text, at, yaw=0, size=0.4, symbol=None):
    s = {'text': text, 'at': at, 'yaw': yaw, 'size': size}
    if symbol:
        s['symbol'] = symbol
    return s


HEARING = 'Hearing protection required'
HEARING_SIZE = 0.3
HEARING_HALF = 0.55 * HEARING_SIZE * len(HEARING) / 2   # half its text's width: about 0.55 em a character
HEARING_MARGIN = 0.4 * HEARING_SIZE                       # its board's beyond the text (kit_place.gd sign_layout)


def hearing_signs(structures, flip=()):
    """The mandatory sign (ISO 7010 M003, wear ear protection) at every door in `structures`, as on site
    (FIRST-TRAIN §6): on the wall beside the opening at eye height, facing out (a door's yaw points out of its
    building), its board (the symbol above the text) clear of the opening: to the door's right seen from outside, or its left for the doors in
    `flip` (where the wall's corner is nearer). The areas call it for their loud buildings, those with a machine of
    85 dB(A) or more inside (the upper exposure action value of EU Directive 2003/10/EC); tests/test_plant3d_sounds.py
    checks that these are exactly the loud ones and that each sign sits on its wall clear of the opening."""
    out = []
    for d in structures:
        if d['part'] != 'door':
            continue
        yaw = d.get('yaw', 0)
        r = math.radians(yaw)
        fx, fy = math.sin(r), math.cos(r)
        k = (d['params'].get('width', 1.0) / 2 + HEARING_HALF + HEARING_MARGIN + 0.3) * (-1 if d['id'] in flip else 1)
        out.append(sign(HEARING, [round(d['at'][0] + fy * k, 3) + 0.0, round(d['at'][1] - fx * k, 3) + 0.0, 1.8],
                        yaw, HEARING_SIZE, 'M003'))
    return out


def area(aid, title, bounds, equipment=(), pipes=(), structures=(), signs=()):
    return {'format': 'walkdown-plant-area', 'version': 1, 'id': aid, 'title': title, 'bounds': bounds,
            'pack': 'base', 'equipment': list(equipment), 'pipes': list(pipes), 'structures': list(structures),
            'signs': list(signs)}


def pg(kks, name, rng, at, unit='bar'):
    return {'kks': kks, 'name': name, 'part': 'pressure_transmitter', 'at': at, 'params': {'range': rng, 'unit': unit}}


# ---------------------------------------------------------------- control building

def control():
    return area('control', 'Control building', [[-40, -15], [-10, 15]], structures=[
        st('ctl_building', 'building', [-40, -15, 0], kks='00UCA10', outline=rect(30, 30), height=12,
           cladding='concrete', openings=[{'kind': 'door', 'at': [30, 15, 0], 'width': 1.8, 'height': 2.4}]),
        st('ctl_door', 'door', [-10, 0, 0], 90, kind='double', width=1.8),
        st('ctl_floor_6', 'floor', [-40, -15, 6], outline=rect(30, 30), openings=[box(1, 1, 8.5, 5)]),
        stair_tower('ctl_stair', [-39, -14, 0], [-31.4, -10, 6]),
    ], signs=[sign('Control room', [-11, 2, 2.6], 90), sign('Control building 00UCA10', [-10.1, -4, 3], 90)])


# ---------------------------------------------------------------- common auxiliaries (bop)

def bop():
    structures = [
        st('bop_boiler_house', 'building', [88, -8, 0], outline=rect(16, 16), height=10, cladding='metal',
           openings=[{'kind': 'door', 'at': [16, 4, 0], 'width': 3, 'height': 3.5},
                     {'kind': 'pipe', 'at': [0, 8, 9], 'width': 0.5, 'height': 0.5}]),
        st('bop_boiler_door', 'door', [104, -4, 0], 90, kind='roller', width=3, height=3.5),
    ]
    return area('bop', 'Auxiliary boiler, demineralised water, instrument air, closed cooling water',
                [[85, -25], [135, 25]],
        equipment=[
            eq('00QHA10', 'Auxiliary boiler', 'package_boiler', [95, 0, 0], 90, {'d': 3, 'length': 8, 'steam_tph': 30},
               'side', [pg('00QHA10CP001', 'Auxiliary steam pressure', [0, 16], [1.8, 2, 2.5])]),
            eq('00GHC10BB001', 'Demineralised water tank', 'tank_vertical', [125, 15, 0], 0,
               {'d': 12, 'height': 10, 'roof': 'cone'}, 'side',
               [child('00GHC10CL001', 'Demineralised water tank level', 'level_transmitter', [6.3, 0, 1],
                      {'range': [0, 10000], 'unit': 'mm'})]),
            eq('00QFA10AN001', 'Instrument air compressor A', 'compressor_skid', [110, -15, 0], 0,
               {'kw': 250, 'length': 4, 'width': 2}, 'side',
               [pg('00QFB10CP001', 'Instrument air header pressure', [0, 10], [1.2, 2.2, 1.5])]),
            eq('00QFA10AN002', 'Instrument air compressor B', 'compressor_skid', [116, -15, 0], 0,
               {'kw': 250, 'length': 4, 'width': 2}, 'side'),
            eq('00PGC10AP001', 'Closed cooling water pump A', 'pump_horizontal', [110, 5, 0], 0,
               {'flow_m3h': 900, 'head_m': 45, 'motor_kw': 160, 'length': 3}, 'motor_side'),
            eq('00PGC10AP002', 'Closed cooling water pump B', 'pump_horizontal', [116, 5, 0], 0,
               {'flow_m3h': 900, 'head_m': 45, 'motor_kw': 160, 'length': 3}, 'motor_side'),
            eq('00PGB10AC001', 'Closed cooling water cooler', 'plate_hx', [124, -8, 0], 0,
               {'plates': 300, 'height': 2.5}, 'frame',
               [child('00PGB10CT001', 'Closed cooling water supply temperature', 'temperature_element',
                      [0, 1.4, 1.2], {'range': [0, 100]})]),
        ],
        pipes=[
            pipe('00LBG10BR001', 'Auxiliary steam to the gland steam supply', 'steam_aux', 150,
                 nz('00QHA10', 'steam_out'), [[95, 0, 9], [67, 0, 9], [67, 1.5, 9]], nz('30MAA10', 'gland_in'),
                 insulation_mm=80, arrows=10,
                 valves=[valve('30MAW10AA001', 'valve_control', 0.93, 'Gland steam supply control valve',
                               dn=150, actuator='pneumatic')]),
        ],
        structures=structures,
        signs=[sign('Auxiliary boiler 00QHA10', [104.1, 0, 3.5], 90), sign('Instrument air', [113, -12, 2.5], 0),
               sign('Closed cooling water', [113, 8, 2.5], 0), sign('Demineralised water 00GHC10', [125, 8.5, 3], 180)]
        + hearing_signs(structures, flip=('bop_boiler_door',)))


# ---------------------------------------------------------------- cooling tower

FAN_X = [183, 199, 215, 231, 247]
FAN_Y = [-8, 8]


def fans():
    out = []
    i = 0
    for y in FAN_Y:
        for x in FAN_X:
            i += 1
            out.append((i, x, y))
    return out


def ct():
    equipment = [
        eq('30PAD10', 'Cooling tower', 'cooling_tower', [215, 0, 0], 0,
           {'cells_x': 5, 'cells_y': 2, 'length': 80, 'width': 32, 'height': 14, 'fan_d': 9.5, 'basin_depth': 2,
            'fill': 'film'}, 'basin'),
        eq('30PAD10BB001', 'Cooling tower basin', 'basin', [215, 0, -2], 0, {'length': 80, 'width': 32, 'depth': 2},
           'edge', [child('30PAD10CL001', 'Cooling tower basin level', 'level_transmitter', [-41, 10, 2],
                          {'range': [-1.5, 0.5], 'unit': 'm'})]),
    ]
    for i, x, y in fans():
        equipment.append(eq(f'30PAD10AN{i:03d}', f'Cooling tower fan {i}', 'fan_axial', [x, y, 14], 0,
                            {'d': 9.5, 'blades': 8, 'motor_kw': 200, 'stack_height': 3}, 'deck',
                            [child(f'30PAD10CY{i:03d}', f'Cooling tower fan {i} vibration', 'vibration_probe',
                                   [5.5, 0, 0.5], {'kind': 'velocity', 'range': [0, 25], 'unit': 'mm/s'})]))
    openings = [box(x - 5 - 175, y - 5 + 16, x + 5 - 175, y + 5 + 16) for _, x, y in fans()]
    return area('ct', 'Cooling tower', [[170, -35], [260, 35]], equipment=equipment,
        pipes=[
            pipe('30PAR10BR001', 'Cooling tower makeup water', 'raw_water', 300, free([258, 0, -1]), [[258, 0, 0.5]],
                 nz('30PAD10', 'makeup_in'),
                 valves=[valve('30PAR10AA001', 'valve_control', 0.7, 'Cooling tower makeup control valve', dn=300,
                               actuator='electric')]),
        ],
        structures=[
            st('ct_fan_deck', 'platform', [175, -16, 14], kks='30URA10', outline=rect(80, 32), openings=openings,
               deck='concrete', edge='handrail'),
            stair_tower('ct_stair_w', [170.5, -20, 0], [175, -13, 14]),
            stair_tower('ct_stair_e', [259.5, -7.5, 0], [255, -0.5, 14]),
        ],
        signs=[sign('Cooling tower 30PAD10', [215, -16.5, 3], 180), sign('Fan deck +14 m', [176, -15, 15.5], 90)])


# ---------------------------------------------------------------- circulating water pump house

CW_X = {'a': 145, 'b': 150, 'c': 155}


def cw():
    equipment = []
    pipes = [
        pipe('30PAB10BR010', 'Circulating water supply', 'cooling_water', 2200, free([142, -14, -4.5]),
             [[160, -14, -4.5], [160, -30, -4.5], [41, -30, -4.5]], nz('30MAG10AC001', 'cw_inlet_a'), od_mm=2235,
             buried=[[0, 2]], arrows=25,
             parts=[inst('30PAB10CF001', 'flow_element', 0.9, 'top', 'Circulating water flow', kind='magnetic',
                         range=[0, 40000], unit='m³/h')]),
    ]
    for n, x in enumerate(CW_X.values(), 1):
        letter = 'ABC'[n - 1]
        equipment.append(eq(f'30PAC10AP00{n}', f'Circulating water pump {letter}', 'pump_vertical', [x, -6, 0], 180,
                            {'flow_m3h': 15000, 'head_m': 22, 'motor_kw': 1250, 'pit_depth': 9}, 'motor_side'))
        pipes.append(pipe(f'30PAC10BR00{n}', f'Circulating water pump {letter} discharge', 'cooling_water', 1400,
                          nz(f'30PAC10AP00{n}', 'discharge'), [[x, -14, 1.5]], jn('30PAB10BR010', [x, -14, -4.5]),
                          valves=[valve(f'30PAC10AA10{n}', 'valve_butterfly', 0.35,
                                        f'Circulating water pump {letter} discharge valve', dn=1400,
                                        actuator='electric')],
                          parts=[inst(f'30PAC10CP50{n}', 'pressure_gauge', 0.1, 'top',
                                      f'Circulating water pump {letter} discharge pressure', range=[0, 4],
                                      unit='bar'),
                                 inst(f'30PAC10CP00{n}', 'pressure_transmitter', 0.2, 'top',
                                      f'Circulating water pump {letter} discharge pressure (transmitter)',
                                      range=[0, 10], unit='bar')]))
    structures = [
        st('cw_house', 'building', [140, -12, 0], kks='30UQA10', outline=rect(25, 20), height=12,
           openings=[{'kind': 'door', 'at': [12, 20, 0], 'width': 4, 'height': 4},
                     {'kind': 'pipe', 'at': [10, 0, 1.5], 'width': 14, 'height': 1.6}]),
        st('cw_pit', 'pit', [142, -8, 0], outline=rect(16, 5), depth=9),
        st('cw_pit_cover', 'grating', [142, -8, 0], outline=rect(16, 5)),
        st('cw_door', 'door', [152, 8, 0], 0, kind='roller', width=4, height=4),
    ]
    return area('cw', 'Circulating water pump house', [[140, -20], [165, 20]], equipment=equipment, pipes=pipes,
        structures=structures,
        signs=[sign('CW pump house 30UQA10', [152, 8.1, 4.6], 0), sign('CW pumps A B C', [150, -2, 3], 180)]
        + hearing_signs(structures))


# ---------------------------------------------------------------- turbine hall

def st_area():
    def vib(code, at):
        return child(code, f'Steam turbine bearing vibration {code[-3:]}', 'vibration_probe', at,
                     {'kind': 'proximity', 'range': [0, 400], 'unit': 'µm'})
    hp_parts = [vib('30MAD10CY001', [1.5, 4.2, 1.5]), vib('30MAD10CY002', [1.5, -4.2, 1.5]),
                child('30MAD10CG001', 'Steam turbine axial displacement', 'vibration_probe', [0, 4.4, 1.2],
                      {'kind': 'proximity', 'range': [-2, 2], 'unit': 'mm'})]
    hp_parts += [child(f'30MAY10CS00{k}', f'Steam turbine speed {k}', 'speed_probe', [-1.5, 4.3, 0.8 + 0.3 * k],
                       {'range': [0, 3600], 'unit': 'rpm'}) for k in (1, 2, 3)]
    hp_parts += [child('30MAA10AA101', 'HP turbine casing warm-up valve (auxiliary steam)', 'valve_globe',
                       [-2.3, -2.5, -1.2], {'dn': 80, 'rating': 'pn40', 'actuator': 'electric'})]
    iplp_parts = [vib('30MAD10CY003', [2.2, 8.2, 1.5]), vib('30MAD10CY004', [2.2, -8.2, 1.5])]
    gen_parts = [vib(f'30MAD10CY00{k}', [1.8, 5.2 - 3.4 * (k - 5), 1.5]) for k in (5, 6, 7, 8)]
    cond_parts = [child('30MAG10BB001', 'Hotwell', 'vessel_horizontal', [0, 0, 0.2],
                        {'d': 1.6, 'length': 12, 'saddles': 2}),
                  child('30MAG10CL001', 'Hotwell level', 'level_transmitter', [6.3, -3, 1],
                        {'range': [-600, 600], 'unit': 'mm'})]
    cond_parts += [child(f'30MAG10CP00{k}', f'Condenser pressure {k}', 'pressure_transmitter', [-6.3, -4 + 2 * k, 12],
                         {'range': [0, 120], 'unit': 'kPa(a)'}) for k in (1, 2, 3)]
    cond_parts += [child(f'30PAB10AA40{k}', f'Condenser water box vent {k}', 'valve_ball',
                         [(-3, 3, -3, 3)[k - 1], (-8, -8, 8, 8)[k - 1], 3.3], {'dn': 50, 'actuator': 'manual'})
                   for k in (1, 2, 3, 4)]
    equipment = [
        eq('30MAA10', 'HP turbine', 'steam_turbine', [64, 0, 12], 90,
           {'length': 8, 'd': 3.5, 'casings': [{'kind': 'hp', 'length': 8, 'd': 3.5}]}, 'side', hp_parts),
        eq('30MAB10', 'IP/LP turbine', 'steam_turbine', [44, 0, 12], 90,
           {'length': 16, 'd': 4.5, 'casings': [{'kind': 'ip_lp', 'length': 16, 'd': 4.5}], 'exhaust': 'down'},
           'side', iplp_parts),
        eq('30MAK10AE001', 'Steam turbine turning gear', 'turning_gear', [31, 0, 12], 90, {'kw': 45}, 'side'),
        eq('30MKA10', 'Steam turbine generator', 'generator', [18, 0, 12], 90,
           {'rating_mva': 170, 'length': 10, 'd': 3.4, 'cooling': 'air'}, 'side', gen_parts),
        eq('30MKC10', 'Steam turbine generator excitation', 'cabinet', [5, -20, 0], 0,
           {'width': 4, 'height': 2.3, 'depth': 1}, 'front'),
        eq('30BAC10', 'Steam turbine generator circuit breaker', 'breaker', [5, -10, 0], 0, {'kind': 'gcb', 'length': 6},
           'side'),
        eq('30MAG10AC001', 'Condenser', 'condenser', [44, 0, -6], 0,
           {'length': 14, 'width': 12, 'height': 16, 'waterboxes': 4, 'passes': 1, 'hotwell': True}, 'shell',
           cond_parts),
        eq('30LCB10AP001', 'Condensate extraction pump A', 'pump_vertical', [52, -8, -6], 0,
           {'flow_m3h': 400, 'head_m': 160, 'motor_kw': 280, 'pit_depth': 3}, 'motor_side'),
        eq('30LCB10AP002', 'Condensate extraction pump B', 'pump_vertical', [56, -8, -6], 0,
           {'flow_m3h': 400, 'head_m': 160, 'motor_kw': 280, 'pit_depth': 3}, 'motor_side'),
        eq('30MAJ10AP001', 'Vacuum pump A', 'vacuum_pump_skid', [27, -16, 0], 0, {'kw': 160, 'length': 4}, 'side'),
        eq('30MAJ10AP002', 'Vacuum pump B', 'vacuum_pump_skid', [21, -16, 0], 0, {'kw': 160, 'length': 4}, 'side'),
        eq('30MAV10AP001', 'Steam turbine lube oil pump (AC)', 'pump_horizontal', [60, 20, 0], 0,
           {'flow_m3h': 120, 'head_m': 50, 'motor_kw': 45, 'length': 2.5}, 'motor_side',
           [pg(f'30MAV10CP00{k}', f'Steam turbine lube oil pressure {k}', [0, 6], [1, 0.6 * k, 1.2])
            for k in (1, 2, 3)] +
           [child('30MAV10CT001', 'Steam turbine lube oil temperature (after the cooler)', 'temperature_element',
                  [1, -0.6, 1.2], {'range': [0, 120]})]),
        eq('30MAV10AP002', 'Steam turbine emergency lube oil pump (DC)', 'pump_horizontal', [64, 20, 0], 0,
           {'flow_m3h': 80, 'head_m': 40, 'motor_kw': 22, 'length': 2.5}, 'motor_side'),
        eq('30MAV20AP001', 'Steam turbine jacking oil pump', 'pump_horizontal', [68, 20, 0], 0,
           {'flow_m3h': 6, 'head_m': 1500, 'motor_kw': 30, 'length': 2}, 'motor_side'),
    ]
    pipes = [
        pipe('30PAB10BR011', 'Circulating water supply to condenser half B', 'cooling_water', 1600,
             jn('30PAB10BR010', [41, -20, -4.5]), [[47, -20, -4.5]], nz('30MAG10AC001', 'cw_inlet_b'), arrows=10),
        pipe('10LBC10BR001', 'Cold reheat steam to HRSG 1', 'steam_crh', 400, nz('30MAA10', 'crh_out'),
             [[62, -1.5, 8], [83, -1.5, 8], [83, 46, 8], [83, 46, 35], [104, 46, 35], [104, 69, 35]],
             nz('10HNA10', 'crh_in'), insulation_mm=150, arrows=15),
        pipe('30MAN10BR001', 'HP bypass', 'steam_hp', 250, jn('10LBA30BR001', [75, 4, 10]), [[75, 4, 8]],
             jn('10LBC10BR001', [75, -1.5, 8]), insulation_mm=200,
             valves=[valve('30MAN10AA001', 'valve_control', 0.4, 'HP bypass valve', dn=250, rating='pn160',
                           actuator='hydraulic')]),
        pipe('30MAN20BR001', 'LP bypass to the condenser', 'steam_rh', 600, jn('10LBB10BR001', [55, 6, 10]),
             [[55, 6, 3.6], [55, 0, 3.6]], nz('30MAG10AC001', 'bypass_in'), insulation_mm=150,
             valves=[valve('30MAN20AA001', 'valve_control', 0.3, 'LP bypass valve', dn=600, rating='pn40',
                           actuator='hydraulic')]),
        pipe('30LCA10BR001', 'Condensate to HRSG 1', 'condensate', 250, nz('30LCB10AP001', 'discharge'),
             [[52, -4, -4.5], [60, -4, -4.5], [60, -4, 8], [81, -4, 8], [81, 51, 8], [147, 51, 8], [147, 51, 4]],
             nz('10HNA10', 'lp_cond_in'), arrows=15),
        pipe('30LCA10BR002', 'Condensate extraction pump B discharge', 'condensate', 250, nz('30LCB10AP002', 'discharge'),
             [], jn('30LCA10BR001', [56, -4, -4.5])),
        pipe('30LCA10BR010', 'Condensate minimum flow recirculation', 'condensate', 150, jn('30LCA10BR001', [60, -4, 2]),
             [[60, -4, -1.2], [60, 3.5, -1.2]], nz('30MAG10AC001', 'recirc_in'),
             valves=[valve('30LCA10AA001', 'valve_control', 0.5, 'Condensate minimum flow valve', dn=150,
                           actuator='pneumatic')]),
        pipe('30LCE10BR001', 'LP bypass spray water', 'condensate', 80, jn('30LCA10BR001', [70, -4, 8]),
             [[70, 3, 8], [55, 3, 8]], jn('30MAN20BR001', [55, 3, 3.6]),
             valves=[valve('30LCE10AA001', 'valve_control', 0.6, 'LP bypass spray valve', dn=80,
                           actuator='pneumatic')]),
        pipe('30MAJ10BR001', 'Condenser air extraction to vacuum pump A', 'air', 200, nz('30MAG10AC001', 'air_out'),
             [[27, 3.5, 2], [27, -10, 2], [27, -10, 1.2]], nz('30MAJ10AP001', 'suction')),
        pipe('30MAJ10BR002', 'Condenser air extraction to vacuum pump B', 'air', 200, jn('30MAJ10BR001', [27, -2, 2]),
             [[21, -2, 2], [21, -10, 2], [21, -10, 1.2]], nz('30MAJ10AP002', 'suction')),
        pipe('30PAB20BR010', 'Circulating water return', 'cooling_water', 2200, nz('30MAG10AC001', 'cw_outlet_a'),
             [[41, 18, -4.5], [70, 18, -4.5], [70, 18, -12], [70, -33, -12], [215, -33, -12], [215, -33, 12]],
             nz('30PAD10', 'hot_water_in'), od_mm=2235, buried=[[2, 5]], arrows=25),
        pipe('30PAB20BR011', 'Circulating water return from condenser half B', 'cooling_water', 1600,
             nz('30MAG10AC001', 'cw_outlet_b'), [], jn('30PAB20BR010', [47, 18, -4.5])),
    ]
    structures = [
        st('st_hall', 'building', [0, -25, 0], kks='30UMA10', outline=rect(80, 50), height=32, cladding='metal',
           openings=[{'kind': 'door', 'at': [80, 30, 0], 'width': 6, 'height': 6},
                     {'kind': 'door', 'at': [0, 45, 0], 'width': 1.2, 'height': 2.4},
                     {'kind': 'pipe', 'at': [80, 27, 9], 'width': 14, 'height': 4}]),
        st('st_floor_12', 'platform', [10, -20, 12], outline=rect(70, 40), deck='concrete', edge='handrail'),
        st('st_floor_6', 'floor', [0, -25, 6], outline=rect(10, 50)),
        stair_tower('st_stair_w', [3, 12, 0], [10, 16, 12]),
        st('st_pit', 'pit', [30, -14, 0], outline=rect(28, 26), depth=6),
        stair_straight('st_pit_stair', [57, 3.5, -6], 'n', 6),
        st('st_door_e', 'door', [80, 5, 0], 90, kind='roller', width=6, height=6),
        st('st_door_w', 'door', [0, 20, 0], 270, kind='personnel'),
    ]
    signs = [sign('Turbine hall 30UMA10', [79.9, 12, 7], 90), sign('Operating floor +12 m', [11, 15, 13.6], 90),
             sign('Condenser 30MAG10AC001', [44, -8.5, 1], 180), sign('Condensate pumps', [54, -10, -4.5], 180),
             sign('Steam turbine lube oil', [64, 22, 2.5], 0)] + hearing_signs(structures, flip=('st_door_w',))
    return area('st', 'Turbine hall', [[0, -25], [80, 25]], equipment, pipes, structures, signs)


# ---------------------------------------------------------------- pipe rack

def rack():
    return area('rack', 'Pipe rack between the turbine hall and the auxiliaries', [[80, -25], [85, 45]],
                structures=[st('rack_main', 'pipe_rack', [82.5, 10, 0], 0, length=70, width=4, height=10, tiers=2,
                               bays=10)],
                signs=[sign('Pipe rack: steam and condensate to and from HRSG 1', [84.9, 30, 3], 90)])


# ---------------------------------------------------------------- gas turbine 1

def gt1():
    tcs = [child(f'10MBR10CT{k:03d}', f'GT exhaust temperature {k}', 'temperature_element',
                 [2 + 1.4 * k, round(1.5 * math.cos(math.radians(30 * k)), 3),
                  round(5 + 1.5 * math.sin(math.radians(30 * k)), 3)],
                 {'range': [0, 800]}) for k in range(1, 13)]
    gt_parts = [child(f'10MBD10CY00{k}', f'GT bearing vibration {k}', 'vibration_probe', [2.6, -15 + 10 * k, 2],
                      {'kind': 'velocity', 'range': [0, 50], 'unit': 'mm/s'}) for k in (1, 2, 3)]
    gt_parts += [child('10MBD10CY004', 'GT bearing vibration 4', 'vibration_probe', [-2.6, 14, 2],
                       {'kind': 'velocity', 'range': [0, 50], 'unit': 'mm/s'})]
    gt_parts += [child(f'10MBY10CS00{k}', f'GT speed {k}', 'speed_probe', [-2.6, -14.6, 1.6 + 0.3 * k],
                       {'range': [0, 3600], 'unit': 'rpm'}) for k in (1, 2, 3)]
    gt_parts += [child(f'10MBM10CB00{k}', f'GT flame detector {k}', 'flame_detector', [(-2.8, 2.8)[k - 1], 2, 3.5])
                 for k in (1, 2)]
    gen_parts = [child(f'10MKA10CT00{k}', f'Generator 1 stator winding temperature {k}', 'temperature_element',
                       [1.9, -4 + 1.6 * (k - 1), 1.5], {'range': [0, 200]}) for k in range(1, 7)]
    equipment = [
        eq('10MBA10', 'Gas turbine 1', 'gas_turbine', [45, 65, 0], 90,
           {'rating_mw': 250, 'length': 30, 'casing_d': 4.5, 'intake': 'top'}, 'side', gt_parts),
        eq('10MBR10', 'GT 1 exhaust diffuser', 'duct', [60, 65, 0], 0,
           {'route': [[0, 0, 5], [20, 0, 5]], 'width': 8, 'height': 9, 'joints': 1}, 'side', tcs),
        eq('10MBL10AT001', 'GT 1 air intake filter house', 'filter_house', [40, 65, 20], 90,
           {'length': 14, 'width': 16, 'height': 9}, 'side'),
        eq('10MBK10AE001', 'GT 1 turning gear', 'turning_gear', [26, 65, 0], 90, {'kw': 75}, 'side'),
        eq('10MKA10', 'Generator 1', 'generator', [15, 65, 0], 90,
           {'rating_mva': 300, 'length': 10, 'd': 3.6, 'cooling': 'air'}, 'side', gen_parts),
        eq('10BAC10', 'Generator 1 circuit breaker', 'breaker', [4, 58, 0], 0, {'kind': 'gcb', 'length': 6}, 'side'),
        eq('10MBJ10', 'GT 1 static frequency converter', 'sfc', [12, 86, 0], 90, {'panels': 8, 'depth': 0.8}, 'front'),
        eq('10MKC10', 'Generator 1 excitation', 'cabinet', [22, 86, 0], 90, {'width': 4, 'height': 2.3, 'depth': 1},
           'front'),
        eq('10MBV10AP001', 'GT 1 lube oil pump (AC)', 'pump_horizontal', [34, 86, 0], 0,
           {'flow_m3h': 150, 'head_m': 45, 'motor_kw': 55, 'length': 2.5}, 'motor_side',
           [pg(f'10MBV10CP00{k}', f'GT 1 lube oil pressure {k}', [0, 6], [1, 0.6 * k, 1.2])
            for k in (1, 2, 3)] +
           [child('10MBV10CT001', 'GT 1 lube oil temperature (after the cooler)', 'temperature_element',
                  [1, -0.6, 1.2], {'range': [0, 120]})]),
        eq('10MBV10AP002', 'GT 1 emergency lube oil pump (DC)', 'pump_horizontal', [38, 86, 0], 0,
           {'flow_m3h': 100, 'head_m': 35, 'motor_kw': 30, 'length': 2.5}, 'motor_side'),
    ]
    pipes = [
        pipe('10MBP10BR001', 'Fuel gas to GT 1', 'fuel_gas', 300, free([40, 91, -1]),
             [[40, 91, 1], [40, 72, 1], [45, 72, 1]], nz('10MBA10', 'fuel_in'), arrows=10,
             valves=[valve('10MBP10AA201', 'valve_ball', 0.55, 'Fuel gas stop valve', dn=300, rating='pn63',
                           actuator='hydraulic'),
                     valve('10MBP10AA001', 'valve_control', 0.75, 'Fuel gas control valve', dn=300, rating='pn63',
                           actuator='hydraulic')],
             parts=[inst('10MBP10CP001', 'pressure_transmitter', 0.3, 'top', 'Fuel gas pressure', range=[0, 50])]),
    ]
    structures = [
        st('gt1_hall', 'building', [0, 50, 0], kks='10UMB10', outline=rect(80, 30), height=20, cladding='metal',
           openings=[{'kind': 'door', 'at': [40, 0, 0], 'width': 6, 'height': 6},
                     {'kind': 'louvre', 'at': [40, 15, 20], 'width': 14, 'height': 16},
                     {'kind': 'pipe', 'at': [80, 15, 5], 'width': 9, 'height': 10},
                     {'kind': 'door', 'at': [30, 30, 0], 'width': 1.0, 'height': 2.1},
                     {'kind': 'pipe', 'at': [40, 30, 1], 'width': 0.6, 'height': 0.6}]),
        st('gt1_door_s', 'door', [40, 50, 0], 180, kind='roller', width=6, height=6),
        st('gt1_door_n', 'door', [30, 80, 0], 0, kind='personnel'),
        st('gt1_skid_slab', 'slab', [8, 82, 0], outline=rect(36, 8), thickness=0.3),
    ]
    signs = [sign('GT 1 hall 10UMB10', [40, 50, 7], 180), sign('Gas turbine 1 10MBA10', [45, 61, 3], 180),
             sign('GT 1 auxiliaries: SFC, excitation, lube oil', [25, 81, 2.5], 0)] + hearing_signs(structures)
    return area('gt1', 'Gas turbine 1 hall and auxiliaries', [[0, 50], [80, 92]], equipment, pipes, structures, signs)


# ---------------------------------------------------------------- transformers

def trafo1():
    return area('trafo1', 'Transformer yard', [[-30, 40], [0, 60]], equipment=[
        eq('10BAT10', 'Step-up transformer 1', 'transformer', [-23, 46, 0], 90,
           {'mva': 300, 'kind': 'gsu', 'radiators': 8, 'bushings': 6}, 'tank'),
        eq('30BAT10', 'Steam turbine step-up transformer', 'transformer', [-23, 55, 0], 90,
           {'mva': 170, 'kind': 'gsu', 'radiators': 6, 'bushings': 6}, 'tank'),
        eq('10BBT10', 'Unit auxiliary transformer 1', 'transformer', [-8, 50, 0], 90,
           {'mva': 25, 'kind': 'aux', 'radiators': 2, 'bushings': 6}, 'tank'),
    ], structures=[
        st('trafo_fence', 'fence', [-30, 40, 0], route=[[0.5, 0.5, 0], [29.5, 0.5, 0], [29.5, 19.5, 0], [0.5, 19.5, 0]],
           height=2.4),
    ], signs=[sign('Transformer yard: danger, high voltage', [-15, 40.4, 2], 180)])


# ---------------------------------------------------------------- HRSG 1

HRSG_MODULES = [  # gas flow order from the GT (west) to the stack (east)
    ('10HAH30', 'HP superheater', 'superheater'), ('10HAJ10', 'Reheater', 'reheater'),
    ('10HAD30', 'HP evaporator', 'evaporator'), ('10HAC30AC002', 'HP economiser stage 2', 'economiser'),
    ('10HAH20', 'IP superheater', 'superheater'), ('10HAD20', 'IP evaporator', 'evaporator'),
    ('10HAC30AC001', 'HP economiser stage 1', 'economiser'), ('10HAC20', 'IP economiser', 'economiser'),
    ('10HAD10', 'LP evaporator', 'evaporator'), ('10HAC10', 'LP economiser', 'economiser')]


def hrsg1():
    equipment = [
        eq('10HNA10', 'HRSG 1 inlet duct and casing', 'hrsg', [122.5, 65, 0], 90,
           {'length': 55, 'width': 22, 'height': 30, 'modules': 10, 'inlet_duct': 15, 'outlet_duct': 10}, 'casing'),
        eq('10HNE10', 'HRSG 1 stack', 'stack', [160, 65, 0], 0, {'d': 7, 'height': 60, 'platforms': 2}, 'base'),
        eq('10HAD30BB001', 'HP drum', 'drum', [110, 65, 32], 90, {'d': 1.8, 'length': 14}, 'side', [
            child('10HAD30CL001', 'HP drum level 1', 'level_transmitter', [1.1, -3, 0.8], {'range': [-500, 500]}),
            child('10HAD30CL002', 'HP drum level 2', 'level_transmitter', [1.1, -2, 0.8], {'range': [-500, 500]}),
            child('10HAD30CL003', 'HP drum level 3', 'level_transmitter', [1.1, -1, 0.8], {'range': [-500, 500]}),
            child('10HAD30CL501', 'HP drum level glass', 'level_glass', [-1.1, 0, 0.8], {'range': [-500, 500]}),
            pg('10HAD30CP001', 'HP drum pressure', [0, 160], [0, 3, 2.2])]),
        eq('10HAD20BB001', 'IP drum', 'drum', [126, 65, 32], 90, {'d': 1.6, 'length': 10}, 'side'),
        eq('10HAD10BB001', 'LP drum with integral deaerator', 'drum', [140, 65, 32], 90, {'d': 3.2, 'length': 14},
           'side', [child('10HAD10CL001', 'LP drum level', 'level_transmitter', [1.8, -2, 1.2],
                          {'range': [-800, 800]})]),
        eq('10LAC10AP001', 'HP/IP feedwater pump A', 'pump_horizontal', [110, 49, 0], 0,
           {'flow_m3h': 330, 'head_m': 1500, 'motor_kw': 1800, 'length': 3}, 'motor_side',
           [child('10LAC10CF001', 'Feedwater pump A flow', 'flow_element', [0.8, 1.2, 1.4],
                  {'range': [0, 400], 'unit': 't/h'})]),
        eq('10LAC10AP002', 'HP/IP feedwater pump B', 'pump_horizontal', [116, 49, 0], 0,
           {'flow_m3h': 330, 'head_m': 1500, 'motor_kw': 1800, 'length': 3}, 'motor_side',
           [child('10LAC10CF002', 'Feedwater pump B flow', 'flow_element', [0.8, 1.2, 1.4],
                  {'range': [0, 400], 'unit': 't/h'})]),
        eq('10LCQ10BB001', 'Blowdown tank', 'tank_vertical', [152, 49, 0], 0, {'d': 2.5, 'height': 4}, 'side'),
        eq('10HAN30BS001', 'HP start-up vent silencer', 'silencer', [98, 58, 30], 0, {'d': 1.2, 'height': 4}, 'side'),
    ]
    for i, (code, name, kind) in enumerate(HRSG_MODULES):
        equipment.append(eq(code, name, 'hrsg_module', [98 + 5 * i, 65, 2], 90,
                            {'kind': kind, 'width': 20, 'depth': 2.5, 'height': 26}, 'door'))
    hp_steam = [[98, 61, 33], [98, 47, 33], [93.5, 47, 33], [93.5, 47, 10], [81, 47, 10], [81, 4, 10], [65, 4, 10], [65, 0, 10]]
    pipes = [
        pipe('10LBA30BR001', 'HP steam to the steam turbine', 'steam_hp', 300, nz('10HNA10', 'hp_steam'), hp_steam,
             nz('30MAA10', 'hp_inlet'), insulation_mm=250, arrows=15,
             valves=[valve('10LBA30AA901', 'valve_safety', 0.06, 'HP superheater outlet safety valve', dn=100,
                           rating='pn160', set_bar=135),
                     valve('30MAA10AA201', 'valve_gate', 0.975, 'HP stop valve', dn=300, rating='pn160',
                           actuator='hydraulic'),
                     valve('30MAA10AA001', 'valve_control', 0.99, 'HP control valve', dn=300, rating='pn160',
                           actuator='hydraulic')],
             parts=[inst('10LBA30CT001', 'temperature_element', 0.04, 'top', 'HP steam temperature',
                         range=[0, 650]),
                    inst('30MAA10CT001', 'temperature_element', 0.95, 'top', 'HP turbine inlet steam temperature',
                         range=[0, 650])]),
        pipe('10LBB10BR001', 'Hot reheat steam to the steam turbine', 'steam_rh', 450, nz('10HNA10', 'hrh_out'),
             [[102, 69, 35], [102, 48, 35], [92.5, 48, 35], [92.5, 48, 10], [82, 48, 10], [82, 6, 10], [43, 6, 10], [43, 1.5, 10]],
             nz('30MAB10', 'hrh_in'), insulation_mm=250, arrows=15),
        pipe('10LBA10BR001', 'LP steam to the steam turbine', 'steam_lp', 600, nz('10HNA10', 'lp_steam'),
             [[140, 61, 36], [140, 45, 36], [140, 45, 8], [84, 45, 8], [84, 8, 8], [38, 8, 8], [38, 0, 8]],
             nz('30MAB10', 'lp_in'), insulation_mm=120, arrows=15),
        pipe('10LAB10BR001', 'Feedwater pump A suction from the LP drum', 'feedwater', 300,
             nz('10HAD10BB001', 'water_out'),
             [[152, 65, 32.6], [152, 65, 3], [152, 53, 3], [110, 53, 3], [110, 53, 0.6]],
             nz('10LAC10AP001', 'suction'), insulation_mm=80),
        pipe('10LAB10BR002', 'Feedwater pump B suction', 'feedwater', 300, jn('10LAB10BR001', [116, 53, 3]),
             [[116, 53, 0.6]], nz('10LAC10AP002', 'suction'), insulation_mm=80),
        pipe('10LAB30BR001', 'HP feedwater to HRSG 1', 'feedwater', 250, nz('10LAC10AP001', 'discharge'),
             [[110, 49.75, 6], [138, 49.75, 6]], nz('10HNA10', 'hp_fw_in'), insulation_mm=80, arrows=10,
             valves=[valve('10LAB30AA001', 'valve_control', 0.8, 'HP feedwater control valve', dn=250, rating='pn250',
                           actuator='pneumatic')]),
        pipe('10LAB30BR002', 'Feedwater pump B discharge', 'feedwater', 250, nz('10LAC10AP002', 'discharge'), [],
             jn('10LAB30BR001', [116, 49.75, 6]), insulation_mm=80),
        pipe('10LAE30BR001', 'HP superheater spray water', 'feedwater', 80, jn('10LAB30BR001', [130, 49.75, 6]),
             [[130, 49.75, 35], [98, 49.75, 35]], jn('10LBA30BR001', [98, 49.75, 33]),
             valves=[valve('10LAE30AA001', 'valve_control', 0.7, 'HP superheater spray control valve', dn=80,
                           rating='pn250', actuator='pneumatic')]),
        pipe('10LCQ10BR001', 'HP drum blowdown', 'boiler_water', 80, nz('10HAD30BB001', 'blowdown'),
             [[100.5, 65, 32.6], [100.5, 52.5, 32.6], [100.5, 52.5, 3.6], [104, 52.5, 3.6], [104, 46, 3.6], [152, 46, 3.6]],
             nz('10LCQ10BB001', 'inlet')),
        pipe('10HAN30BR401', 'HP superheater drains', 'boiler_water', 50, nz('10HNA10', 'sh_drain'),
             [[99, 52.5, 1.5], [99, 52.5, 3.6]], jn('10LCQ10BR001', [100.5, 52.5, 3.6]),
             valves=[valve(f'10HAN30AA40{k}', 'valve_globe', 0.1 + 0.15 * k, f'HP superheater drain valve {k}', dn=50,
                           rating='pn160', actuator='electric') for k in (1, 2, 3, 4)]),
        pipe('10HAN30BR001', 'HP start-up vent', 'steam_hp', 150, jn('10LBA30BR001', [98, 55, 33]), [[98, 55, 30.8]],
             nz('10HAN30BS001', 'inlet'), insulation_mm=150,
             valves=[valve('10HAN30AA001', 'valve_control', 0.5, 'HP start-up vent valve', dn=150, rating='pn160',
                           actuator='electric')]),
    ]
    structures = [
        st('hrsg1_roof', 'platform', [95, 54, 30], kks='10UHA10', outline=rect(55, 22), deck='grating'),
        st('hrsg1_landing_30', 'platform', [95, 46, 30], outline=rect(7, 8), deck='grating'),
        stair_tower('hrsg1_stair', [95, 46, 0], [102, 50, 30]),
        st('hrsg1_drum_platform', 'platform', [103, 61, 32], outline=rect(44, 8), deck='grating'),
        stair_straight('hrsg1_drum_stair', [100.6, 66.5, 30], 'e', 2),
        st('hrsg1_walkway', 'platform', [150, 63, 30], outline=rect(6, 4), deck='grating'),
        st('hrsg1_stack_platform', 'platform', [155.5, 60.5, 40], kks='10UHN10', outline=rect(9, 9),
           openings=[box(1, 1, 8, 8)], deck='grating'),
        st('hrsg1_stack_ladder', 'ladder', params={'foot': [155.6, 65, 30], 'top': 40, 'facing': 90}),
    ]
    signs = [sign('HRSG 1 10HNA10', [122, 53.9, 6], 180), sign('HP drum 10HAD30BB001', [110, 61.2, 33.5], 180),
             sign('Feedwater pumps', [113, 46.5, 2.5], 180), sign('Stack 10HNE10', [160, 61, 2.5], 180)]
    return area('hrsg1', 'HRSG 1 and its stack', [[80, 45], [175, 85]], equipment, pipes, structures, signs)


def areas():
    return [control(), bop(), ct(), cw(), gt1(), trafo1(), hrsg1(), st_area(), rack()]
