"""The first train's plant file, sound library, scenario, procedure and tours (docs/plant3d/FIRST-TRAIN.md)."""
import re

# Meanings in our own words of the KKS key letters this plant uses (FIRST-TRAIN §1 names the public sources).
UNITS = {'0': 'Common to the whole plant', '1': 'Gas turbine train 1 (GT 1, generator 1, HRSG 1)',
         '3': 'Steam turbine unit (turbine, generator, condenser, cooling water)'}
SYSTEMS = {
    'BAC': 'Generator circuit breaker', 'BAT': 'Generator step-up transformer', 'BBT': 'Unit auxiliary transformer',
    'GHC': 'Demineralised water storage', 'HAC': 'Economiser', 'HAD': 'Evaporator and drum', 'HAH': 'Superheater',
    'HAJ': 'Reheater', 'HAN': 'Boiler drains and vents', 'HNA': 'Flue gas ducts (HRSG inlet and casing)',
    'HNE': 'Stack', 'LAB': 'Feedwater piping', 'LAC': 'Feedwater pumps', 'LAE': 'Superheater spray water',
    'LBA': 'Main steam piping', 'LBB': 'Hot reheat piping', 'LBC': 'Cold reheat piping',
    'LBG': 'Auxiliary steam', 'LCA': 'Main condensate piping', 'LCB': 'Condensate pumps',
    'LCE': 'Condensate spray water', 'LCQ': 'Boiler blowdown', 'MAA': 'HP turbine', 'MAB': 'IP turbine',
    'MAD': 'Steam turbine bearings', 'MAG': 'Condenser', 'MAJ': 'Condenser air extraction', 'MAK': 'Turning gear',
    'MAN': 'Turbine bypass', 'MAV': 'Steam turbine lube oil', 'MAW': 'Gland steam', 'MAY': 'Steam turbine control and '
    'protection', 'MBA': 'Gas turbine: compressor and turbine', 'MBD': 'Gas turbine bearings',
    'MBJ': 'Gas turbine start-up unit', 'MBK': 'Gas turbine gear and turning gear', 'MBL': 'Gas turbine intake air',
    'MBM': 'Combustion system', 'MBP': 'Fuel gas', 'MBR': 'Gas turbine exhaust',
    'MBV': 'Gas turbine lube oil', 'MBY': 'Gas turbine control and protection', 'MKA': 'Generator',
    'MKC': 'Generator excitation', 'PAB': 'Circulating water piping', 'PAC': 'Circulating water pumps',
    'PAD': 'Cooling tower', 'PAR': 'Cooling tower makeup water', 'PGB': 'Closed cooling water coolers',
    'PGC': 'Closed cooling water pumps', 'QFA': 'Instrument air compressors', 'QFB': 'Instrument air distribution',
    'QHA': 'Auxiliary boiler', 'CWA': 'Main control desk A', 'CWB': 'Main control desk B',
    'UCA': 'Control building', 'UHA': 'HRSG structure', 'UHN': 'Stack structure',
    'UMA': 'Turbine hall', 'UMB': 'Gas turbine hall', 'UQA': 'Circulating water pump house',
    'URA': 'Cooling tower structure'}
EQUIPMENT = {'AA': 'Valve or damper with its actuator', 'AC': 'Heat exchanger or heating surface',
             'AE': 'Turning, driving or lifting gear', 'AN': 'Fan or compressor', 'AP': 'Pump unit',
             'AT': 'Filter or cleaning unit', 'BB': 'Vessel or tank', 'BR': 'Pipe', 'BS': 'Silencer'}
MEASUREMENTS = {'CB': 'Radiation (flame)', 'CF': 'Flow', 'CG': 'Position or displacement', 'CL': 'Level',
                'CP': 'Pressure', 'CS': 'Speed', 'CT': 'Temperature', 'CY': 'Vibration'}

MEDIA = {'cooling_water': ('water', '#2e7d32'), 'raw_water': ('water', '#558b2f'), 'feedwater': ('water', '#1b5e20'),
         'condensate': ('water', '#43a047'), 'boiler_water': ('water', '#00695c'), 'steam_hp': ('steam', '#c62828'),
         'steam_rh': ('steam', '#ad1457'), 'steam_crh': ('steam', '#e57373'), 'steam_lp': ('steam', '#ef6c00'),
         'steam_aux': ('steam', '#d84315'), 'air': ('air', '#78909c'), 'fuel_gas': ('gas', '#f9a825')}


def plant(codes):
    """plant.json, with decoder tables holding only the letters `codes` use."""
    used = {'units': set(), 'systems': set(), 'equipment': set(), 'measurements': set()}
    rx = re.compile(r'([0-9])[0-9]([A-Z]{3})[0-9]{2}(?:([A-Z]{2})[0-9]{3}[A-Z]?)?')
    for c in codes:
        g = rx.fullmatch(c)
        used['units'].add(g.group(1))
        used['systems'].add(g.group(2))
        if g.group(3):
            used['measurements' if g.group(3).startswith('C') else 'equipment'].add(g.group(3))
    tables = {'units': UNITS, 'systems': SYSTEMS, 'equipment': EQUIPMENT, 'measurements': MEASUREMENTS}
    kks = {k: {c: tables[k][c] for c in sorted(used[k])} for k in tables}
    kks['source'] = ('Codes follow the public KKS key (sources: docs/plant3d/FIRST-TRAIN.md §1); only the letters '
                     'this plant uses, with meanings in our own words.')
    return {'format': 'walkdown-plant', 'version': 1, 'id': 'ccpp', 'title': 'Generic 2-2-1 combined-cycle plant',
            'frequency_hz': 50, 'kks': kks,
            'media': {k: {'group': g, 'band': b} for k, (g, b) in MEDIA.items()},
            'areas': ['control', 'bop', 'ct', 'cw', 'gt1', 'trafo1', 'hrsg1', 'st', 'rack'],
            'ext': ['ambient_t', 'ambient_wb', 'grid_frequency'],
            'start': {'at': [-20, 0, 0], 'yaw': 90}}


def synth(sid, tones=None, noise=None, made=None):
    s = {'id': sid, 'kind': 'synth'}
    if tones:
        s['tones'] = tones
    if noise:
        s['noise'] = noise
    if made:
        s['made'] = made
    return s


def sounds():
    """The sound library (FIRST-TRAIN §6). All synthesised for now (tools/plant3d/sounds/make_sounds.py, which says
    the physics behind each tone and band, each sound's level and its time structure); recorded CC0 clips may
    replace some later (0054), each with its licence and source."""
    def t(*pairs):
        return [{'hz': hz, 'gain': g} for hz, g in pairs]
    return {'format': 'walkdown-plant-sounds', 'version': 1, 'sounds': [
        synth('gt_whine', t((2850, 0.6), (5700, 0.2), (3550, 0.25), (50, 0.2)),
              {'colour': 'pink', 'band': [200, 4000], 'gain': 0.5}, 'compressor blade-pass tone at full speed'),
        synth('combustion', None, {'colour': 'brown', 'band': [30, 600]}, 'combustion roar'),
        synth('exhaust_rumble', None, {'colour': 'brown', 'band': [20, 200]}),
        synth('sfc_whine', t((600, 0.4), (1200, 0.3), (500, 0.15), (700, 0.15), (1100, 0.1), (1300, 0.1), (100, 0.3)),
              {'colour': 'pink', 'band': [500, 4000], 'gain': 0.12}, '12-pulse converter buzz'),
        synth('gen_hum', t((100, 0.7), (200, 0.35), (300, 0.2), (400, 0.15), (600, 0.08)),
              {'colour': 'pink', 'band': [300, 3000], 'gain': 0.35}),
        synth('transformer_hum', t((100, 0.8), (200, 0.45), (300, 0.3), (400, 0.2), (500, 0.12), (600, 0.1)),
              {'colour': 'pink', 'band': [150, 2000], 'gain': 0.12}),
        synth('turbine_hum', t((50, 0.5), (100, 0.4), (150, 0.25), (3600, 0.12)),
              {'colour': 'pink', 'band': [100, 2000], 'gain': 0.35}),
        synth('steam_rush', None, {'colour': 'white', 'band': [500, 8000]}),
        synth('steam_vent', None, {'colour': 'white', 'band': [300, 10000]}),
        synth('turning_gear', t((8, 0.5), (100, 0.3), (600, 0.12)),
              {'colour': 'brown', 'band': [50, 400], 'gain': 0.3}),
        synth('motor_large', t((100, 0.6), (200, 0.2), (742.5, 0.15), (642.5, 0.07), (842.5, 0.07), (49.5, 0.3)),
              {'colour': 'pink', 'band': [100, 2500], 'gain': 0.5}),
        synth('motor_small', t((100, 0.5), (200, 0.15), (1087, 0.12), (987, 0.06), (1187, 0.06), (271.5, 0.1)),
              {'colour': 'pink', 'band': [200, 4000], 'gain': 0.4}),
        synth('fan_large', t((16, 0.4), (420, 0.1), (100, 0.15)),
              {'colour': 'pink', 'band': [60, 1500], 'gain': 0.6}),
        synth('water_rain', None, {'colour': 'white', 'band': [400, 9000]}),
        synth('liquid_ring', t((25, 0.4), (300, 0.15), (100, 0.25)),
              {'colour': 'brown', 'band': [80, 1200], 'gain': 0.6}),
        synth('burner', None, {'colour': 'brown', 'band': [40, 800]}),
        synth('valve_motor', t((400, 0.5), (800, 0.2), (100, 0.3)),
              {'colour': 'pink', 'band': [500, 3000], 'gain': 0.2}),
        synth('breaker', t((160, 0.6), (410, 0.5), (1150, 0.35), (2650, 0.2)),
              {'colour': 'white', 'band': [100, 6000], 'gain': 0.8},
              'a breaker closing, then its spring-charging motor (played once)'),
        synth('breaker_open', t((210, 0.5), (530, 0.45), (1400, 0.3), (3100, 0.2)),
              {'colour': 'white', 'band': [150, 7000], 'gain': 0.9}, 'a breaker opening (played once)'),
        synth('motor_start', t((100, 0.6), (742.5, 0.15), (49.5, 0.3)),
              {'colour': 'pink', 'band': [100, 2500], 'gain': 0.5},
              'a large motor started direct on line (played once, then motor_large)'),
        synth('surge_thud', t((40, 0.8), (90, 0.5), (230, 0.3), (1130, 0.12)),
              {'colour': 'brown', 'band': [25, 1500], 'gain': 0.9},
              'a CW pump started against an open valve: the water slamming in its pipe (played once)'),
        synth('horn_p1', t((880, 0.8), (1760, 0.3), (2640, 0.2))),
        synth('horn_p2', t((660, 0.7), (1320, 0.25), (1980, 0.15))),
        synth('horn_p3', t((440, 0.5), (880, 0.2), (1320, 0.1))),
        synth('horn_ack', t((1000, 0.6), (2000, 0.2)), None, 'an alarm acknowledged (played once)'),
        # people cues: a footstep on each kind of floor (played once a stride), the doors
        synth('step_concrete', t((90, 0.6)), {'colour': 'pink', 'band': [80, 5000], 'gain': 0.8},
              'a footstep on concrete (played once a stride)'),
        synth('step_grating', t((420, 0.5), (1180, 0.4), (2350, 0.3), (3700, 0.2)),
              {'colour': 'white', 'band': [200, 6000], 'gain': 0.6},
              'a footstep on steel bar grating (played once a stride)'),
        synth('step_stair', t((260, 0.6), (690, 0.45), (1560, 0.3), (3050, 0.15)),
              {'colour': 'pink', 'band': [100, 5000], 'gain': 0.5},
              'a footstep on a steel stair tread, chequer plate or a ladder rung (played once)'),
        synth('door_slide', t((180, 0.4), (520, 0.25)), {'colour': 'pink', 'band': [60, 2500], 'gain': 0.7},
              'a sliding door running on its rollers to its stop (played once)'),
        synth('door_roller', t((15, 0.5), (100, 0.3), (350, 0.3)), {'colour': 'pink', 'band': [150, 5000], 'gain': 0.6},
              'a roller door: its motor and the slats rattling in their guides (loops while it moves)'),
        # ambience outdoors
        synth('wind', None, {'colour': 'pink', 'band': [30, 1500]}, 'wind at the ear, in gusts'),
        synth('plant_distant', t((100, 0.5), (200, 0.2)), {'colour': 'brown', 'band': [30, 700], 'gain': 0.8},
              'the running plant heard from afar'),
    ]}


FAULTS = [  # trainer faults (no `when`: pressed by the trainer, PLANT3D §7.8)
    ('ccw_a_motor', {'ccw_a_fault': 1}, 'Closed cooling water pump A motor fails'),
    ('ccw_b_motor', {'ccw_b_fault': 1}, 'Closed cooling water pump B motor fails'),
    ('gt1_lac_fails', {'gt1_lac_fault': 1}, 'GT 1 AC lube oil pump fails'),
    ('gt1_lube_both', {'gt1_lac_fault': 1, 'gt1_ldc_fault': 1}, 'Both GT 1 lube oil pumps fail'),
    ('gt1_flameout', {'gt1_flameout': 1}, 'GT 1 flame out (a fuel supply disturbance)'),
    ('gt1_fuel_ctrl', {'gt1_fuel_fault': 1}, 'GT 1 fuel control fault: exhaust 80 K hotter'),
    ('gt1_tc7', {'gt1_tc_fault': 1}, 'GT 1 burner fault: a cold spot at thermocouple 7'),
    ('gt1_load_rej', {'gt1_brk_cmd': 0, 'gt1_gov_fault': 1}, 'Load rejection with a stuck GT 1 fuel valve'),
    ('gt1_vib', {'gt1_vib_fault': 1}, 'GT 1 bearing 2 damage'),
    ('gt1_surge', {'gt1_surge': 1}, 'GT 1 compressor surge'),
    ('gt1_gas_low', {'gt1_gas_low': 1}, 'Fuel gas supply pressure falls'),
    ('gt1_stator', {'gt1_stator_fault': 1}, 'Generator 1 cooling fault'),
    ('hp_fwv_open', {'hp_fwv_fail_open': 1}, 'HP feedwater control valve fails open'),
    ('hp_fwv_closed', {'hp_fwv_fail_closed': 1}, 'HP feedwater control valve fails closed'),
    ('fw_recirc', {'fw_recirc_fault': 1}, 'Feedwater pump recirculation valve stuck closed'),
    ('hp_spray_stuck', {'hp_spray_stuck': 1}, 'HP superheater spray valve stuck open'),
    ('st_lac_fails', {'st_lac_fault': 1}, 'Steam turbine AC lube oil pump fails'),
    ('st_lube_both', {'st_lac_fault': 1, 'st_ldc_fault': 1}, 'Both steam turbine lube oil pumps fail'),
    ('st_load_rej', {'st_brk_cmd': 0, 'st_gov_fault': 1}, 'Load rejection with stuck steam turbine control valves'),
    ('st_thrust', {'st_thrust_fault': 1}, 'Steam turbine thrust bearing wear'),
    ('st_vib', {'st_vib_fault': 1}, 'Steam turbine bearing 3 damage'),
    ('cw_a_motor', {'cw_a_fault': 1}, 'CW pump A motor overload'),
    ('cw_b_motor', {'cw_b_fault': 1}, 'CW pump B motor overload'),
    ('cw_c_motor', {'cw_c_fault': 1}, 'CW pump C motor overload'),
    ('cw_ab_fail', {'cw_a_fault': 1, 'cw_b_fault': 1}, 'CW pumps A and B trip (a supply fault)'),
    ('cw_a_valve_stuck', {'cw_a_v_stuck': 1}, 'CW pump A discharge valve actuator fails'),
    ('cw_b_valve_stuck', {'cw_b_v_stuck': 1}, 'CW pump B discharge valve actuator fails'),
    ('cw_c_valve_stuck', {'cw_c_v_stuck': 1}, 'CW pump C discharge valve actuator fails'),
    ('ct_drain_open', {'ct_drain_open': 1}, 'Cooling tower basin drain left open'),
] + [(f'ct_fan{i}_vib', {f'ct_fan{i}_vfault': 1}, f'Cooling tower fan {i} blade damage') for i in range(1, 11)] + [
    ('hw_leak', {'hw_leak': 1, 'hw_mk_fail': 1}, 'Condensate leak with the hotwell makeup failed'),
    # FIRST-TRAIN §4 "As built": closed cooling water lost, instrument air lost (the valves' fail-safe positions),
    # the valves' power lost, a start against an open valve, the loss of every steam sink
    ('ccw_both', {'ccw_a_fault': 1, 'ccw_b_fault': 1}, 'Both closed cooling water pumps trip (a supply fault)'),
    ('ia_lost', {'ia_a_fault': 1, 'ia_b_fault': 1}, 'Both instrument air compressors trip'),
    ('cw_valve_power', {'cw_a_v_stuck': 1, 'cw_b_v_stuck': 1, 'cw_c_v_stuck': 1},
     'CW pump house valve power supply lost: the motor-operated discharge valves stay where they are'),
] + [(f'cw_{x}_ls', {f'cw_{x}_ls_fault': 1}, f'CW pump {x.upper()} discharge valve: the start-position limit switch '
      f'sticks made (the permissive passes with the valve open)') for x in 'abc'] + [
    ('byp_hyd', {'byp_hyd_fault': 1}, 'Bypass valves\' hydraulic unit fails: the bypass is blocked'),
    ('st_trip_no_bypass', {'st_vib_fault': 1, 'byp_hyd_fault': 1},
     'Steam turbine bearing 3 damage with the bypass hydraulics failed: no steam sink'),
]


# Where a fault is repaired when that isn't the equipment of the first state it puts back: the GT for its combustion
# and fuel control faults; nowhere in the field (the instructor's panel only) for a fault of a supply from outside
# the plant or of several pieces of equipment at once
REPAIR_AT = {'gt1_flameout': '10MBA10', 'gt1_fuel_ctrl': '10MBA10', 'gt1_load_rej': '10MBA10',
             'gt1_gas_low': None, 'cw_valve_power': None, 'st_trip_no_bypass': None, 'cw_ab_fail': None,
             'ccw_both': None, 'ia_lost': None, 'hw_leak': None,
             # damage inside a machine (a bearing, blades, a thrust collar, a stator): an overhaul, not a repair a
             # trainee makes at a running machine; the instructor's panel only
             'gt1_vib': None, 'gt1_surge': None, 'gt1_stator': None, 'gt1_tc7': None, 'st_thrust': None, 'st_vib': None,
             **{f'ct_fan{i}_vib': None for i in range(1, 11)}}


def fault(fid, sets, text, state_kks):
    """A trainer's fault with its repair (PLANT3D §7.8): the repair puts back every state the fault set, except a
    breaker it opened (the trainee closes it again); offered at the equipment of the first state it puts back, or as
    REPAIR_AT says."""
    f = {'id': fid, 'set': sets, 'text': text}
    repair = {k: 0 for k in sets if not k.endswith('_brk_cmd')}
    if repair:
        at = REPAIR_AT.get(fid, state_kks[next(iter(repair))])
        if at:
            f['kks'] = at
        f['repair'] = repair
    return f


COLD_INIT = {'ambient_t': 35, 'ambient_wb': 25, 'grid_frequency': 50, 'hp_mass': -100, 'lp_lvl': -50}
# The hot restart (FIRST-TRAIN §4 "As built"): the train tripped from load about three hours ago and everything
# stopped. The HP casing has cooled only to 480 °C (τ 30 h), the boxed-up HP drum to 280 °C (64 bar, 10 K an hour), the
# steam at the superheater outlet to 270 °C. The first steam is far colder than the casing: the turbine may roll only once the GT's load
# has brought the steam within 50 K of it.
HOT_INIT = {'st_casing_t': 480, 'hp_casing_seen': 480, 'hp_tw': 280, 'hp_tsat_slow': 280, 'hp_steam_t': 270,
            'st_inlet_t': 250}


def scenarios(state_kks):
    faults = [fault(f, s, t, state_kks) for f, s, t in FAULTS]
    latched = ['gt1_trip_lube', 'st_trip_lube', 'st_trip_cond_p']
    return [{'format': 'walkdown-plant-scenario', 'version': 1, 'id': 'cold_iron',
             'title': 'Cold start after a long outage', 'init': dict(COLD_INIT), 'latched': latched,
             'faults': faults},
            {'format': 'walkdown-plant-scenario', 'version': 1, 'id': 'hot_restart',
             'title': 'Hot restart three hours after a trip', 'init': dict(COLD_INIT, **HOT_INIT),
             'latched': latched, 'faults': faults}]


def k(code):
    return {'link': [code], 'to': {'kks': code}}


def step(sid, text, at, do=(), done=None, why=None, go='walk', ordered=False):
    s = {'id': sid, 'text': text, 'at': list(at), 'go': go}
    if do:
        s['do'] = list(do)
    if ordered:
        s['ordered'] = True
    if done:
        s['done'] = done
    if why:
        s['why'] = [{'p': why}]
    return s


def op(code, do, value=None, trip=None):
    o = {'kks': code, 'do': do}
    if value is not None:
        o['value'] = value
    if trip:
        o['trip'] = trip
    return o


def cold_start():
    S = []
    S.append(step('ia', ['Start instrument air compressor A (', k('00QFA10AN001'), ').'], ['00QFA10AN001'],
                  [op('00QFA10AN001', 'start')], 'ia_p_norm',
                  ['Air-operated valves (the auxiliary boiler\'s burner, the control valves) need 4 bar to move.']))
    S.append(step('ccw', ['Start closed cooling water pump A (', k('00PGC10AP001'), ').'], ['00PGC10AP001'],
                  [op('00PGC10AP001', 'start')], 'ccw_flow_ok'))
    S.append(step('ccw_cooler', ['Put the closed cooling water cooler (', k('00PGB10AC001'), ') in service.'],
                  ['00PGB10AC001'], [op('00PGB10AC001', 'open')], 'ccw_ok',
                  ['Lube oil coolers, the vacuum pumps\' seal water and the generator coolers all need it.']))
    S.append(step('basin', ['Check the cooling tower basin level (', k('30PAD10CL001'), ') and put the makeup valve (',
                            k('30PAR10AA001'), ') in automatic.'], ['30PAD10CL001', '30PAR10AA001'],
                  [op('30PAR10AA001', 'auto')], 'ct_mk_auto', ['The basin is the source of all circulating water.'],
                  'fly'))
    S.append(step('cw_a_valve', ['Set the discharge valve of CW pump A (', k('30PAC10AA101'),
                                 ') to its start position, 15 %.'], ['30PAC10AA101'],
                  [op('30PAC10AA101', 'set', 0.15)], 'cw_a_vstart'))
    S.append(step('cw_a_start', ['Start circulating water pump A (', k('30PAC10AP001'), ').'], ['30PAC10AP001'],
                  [op('30PAC10AP001', 'start')], 'cw_a_run',
                  ['With the valve at its start position the empty pipe fills slowly, without a pressure surge, and '
                   'the motor starts against a light load: its inrush current lasts four seconds.']))
    S.append(step('cw_a_open', ['Open the discharge valve fully within two minutes.'], ['30PAC10AA101'],
                  [op('30PAC10AA101', 'open')], 'cw_a_vfull',
                  ['A pump running against a nearly closed valve for long overheats: the pump trips after 120 s.']))
    S.append(step('vents_open', ['Open the condenser water box vents (', k('30PAB10AA401'), ' to ', k('30PAB10AA404'),
                                 ') until water shows.'], ['30PAB10AA401', '30PAB10AA402', '30PAB10AA403',
                                                           '30PAB10AA404'],
                  [op(f'30PAB10AA40{n}', 'open') for n in (1, 2, 3, 4)], 'cw_wb_full',
                  ['Air trapped in the top of the water boxes blinds tubes: the condenser loses vacuum later.']))
    S.append(step('vents_close', ['Close the four vents.'], ['30PAB10AA401'],
                  [op(f'30PAB10AA40{n}', 'close') for n in (1, 2, 3, 4)], 'cw_vents_closed'))
    S.append(step('hotwell', ['Check the hotwell level (', k('30MAG10CL001'), '): the makeup keeps it near zero.'],
                  ['30MAG10CL001'], (), 'hw_ok'))
    S.append(step('st_lube', ['Start the steam turbine AC lube oil pump (', k('30MAV10AP001'), ').'],
                  ['30MAV10AP001'], [op('30MAV10AP001', 'start')], 'st_lube_ok'))
    S.append(step('st_lube_reset', ['Reset the lube oil low-low trip now that the pressure is normal.'],
                  ['30MAV10CP001'], [op('30MAV10CP001', 'reset', trip='st_trip_lube')], 'st_lube_trip_clear',
                  go='none'))
    S.append(step('st_jack', ['Start the jacking oil pump (', k('30MAV20AP001'), ').'], ['30MAV20AP001'],
                  [op('30MAV20AP001', 'start')], 'st_jack_ok',
                  ['Jacking oil lifts the rotor on its bearings so the turning gear can turn it without wear.']))
    S.append(step('st_tg', ['Start the steam turbine turning gear (', k('30MAK10AE001'), ').'], ['30MAK10AE001'],
                  [op('30MAK10AE001', 'start')], 'st_tg_run',
                  ['A rotor left still sags; turning it slowly straightens it again. Watch the eccentricity fall.']))
    S.append(step('gt_lube', ['Start the GT 1 AC lube oil pump (', k('10MBV10AP001'), ') and reset its low-low trip.'],
                  ['10MBV10AP001'], [op('10MBV10AP001', 'start')], 'gt1_lube_ok'))
    S.append(step('gt_lube_reset', ['Reset the GT 1 lube oil low-low trip.'], ['10MBV10CP001'],
                  [op('10MBV10CP001', 'reset', trip='gt1_trip_lube')], 'gt1_lube_trip_clear', go='none'))
    S.append(step('gt_tg', ['Start the GT 1 turning gear (', k('10MBK10AE001'), ').'], ['10MBK10AE001'],
                  [op('10MBK10AE001', 'start')], 'gt1_tg_run'))
    S.append(step('aux', ['Start the auxiliary boiler (', k('00QHA10'), ') and wait for 10 bar.'], ['00QHA10'],
                  [op('00QHA10', 'start')], 'aux_ok', ['The first steam of a cold start comes from here.']))
    S.append(step('gland', ['Admit gland steam (', k('30MAW10AA001'), ').'], ['30MAW10AA001'],
                  [op('30MAW10AA001', 'open')], 'st_gland_on',
                  ['Only with the rotor turning: steam on a stopped rotor heats one side and bows it.']))
    S.append(step('casing_warm', ['Open the HP casing warm-up valve (', k('30MAA10AA101'), ').'], ['30MAA10AA101'],
                  [op('30MAA10AA101', 'open')], 'st_warm_on',
                  ['Auxiliary steam warms the cold HP casing while the rotor turns, so that the first steam from the '
                   'HRSG can be matched to the metal: steam much hotter than the casing cracks it, colder steam '
                   'quenches it.']))
    S.append(step('vacuum', ['Start both vacuum pumps (', k('30MAJ10AP001'), ', ', k('30MAJ10AP002'),
                             ') and wait for the condenser pressure to fall below 12 kPa(a).'],
                  ['30MAJ10AP001', '30MAJ10AP002'], [op('30MAJ10AP001', 'start'), op('30MAJ10AP002', 'start')],
                  'st_vac_ok', ['With gland steam on, air can\'t leak in along the shaft: the vacuum gets deep.']))
    S.append(step('cond_reset', ['Reset the condenser pressure high-high trip.'], ['30MAG10CP001'],
                  [op('30MAG10CP001', 'reset', trip='st_trip_cond_p')], 'st_cond_trip_clear', go='none'))
    S.append(step('vac_hold', ['Stop vacuum pump B: one pump holds the vacuum.'], ['30MAJ10AP002'],
                  [op('30MAJ10AP002', 'stop')], 'st_vac_ok'))
    S.append(step('cep_mf', ['Open the condensate minimum flow valve (', k('30LCA10AA001'), ').'], ['30LCA10AA001'],
                  [op('30LCA10AA001', 'open')], 'cep_mf_open'))
    S.append(step('cep', ['Start condensate extraction pump A (', k('30LCB10AP001'), ').'], ['30LCB10AP001'],
                  [op('30LCB10AP001', 'start')], 'cep_a_run',
                  ['Until the HRSG takes condensate, the pump runs on its minimum flow line back to the condenser.']))
    S.append(step('drains', ['Open the HP superheater drains (', k('10HAN30AA401'), ' to ', k('10HAN30AA404'),
                             ') and the start-up vent (', k('10HAN30AA001'), ').'],
                  ['10HAN30AA401', '10HAN30AA001'],
                  [op(f'10HAN30AA40{n}', 'open') for n in (1, 2, 3, 4)] + [op('10HAN30AA001', 'open')],
                  'hp_drains_vent_open',
                  ['Steam condenses in the cold superheaters; the water must go before it reaches the turbine.']))
    S.append(step('fw', ['Start feedwater pump A (', k('10LAC10AP001'), '). The HP drum level control is in automatic.'],
                  ['10LAC10AP001'], [op('10LAC10AP001', 'start')], 'fw_a_run'))
    S.append(step('bypass', ['Put the HP and LP bypass (', k('30MAN10AA001'), ', ', k('30MAN20AA001'),
                             ') in automatic.'], ['30MAN10AA001', '30MAN20AA001'],
                  [op('30MAN10AA001', 'auto'), op('30MAN20AA001', 'auto')], 'hp_byp_on',
                  ['The bypass dumps the first steam into the condenser and holds the HRSG pressure. It needs the '
                   'condenser: vacuum, circulating water and a condensate pump for its spray water.']))
    S.append(step('gt_start', ['Check the GT 1 start permissives on the screen, then start GT 1 (', k('10MBA10'),
                               ').'], ['10MBA10'], [op('10MBA10', 'start')], 'gt1_in_fsnl',
                  ['Crank, purge the HRSG with five volume changes of air, ignite, accelerate: listen to the '
                   'compressor whine rise.'], 'fly'))
    S.append(step('gt_exc', ['Switch on the generator 1 excitation (', k('10MKC10'), ').'], ['10MKC10'],
                  [op('10MKC10', 'start')], 'gt1_v_ok', go='none'))
    S.append(step('gt_sync', ['Raise the GT speed a little (+0.05 Hz) and watch the synchroscope turn.'],
                  ['10MBY10CS001'], [op('10MBY10CS001', 'set', 0.001)], 'gt1_sync_ok', go='none'))
    S.append(step('gt_brk', ['Close the generator 1 breaker (', k('10BAC10'), ') as the pointer passes twelve '
                             'o\'clock.'], ['10BAC10'], [op('10BAC10', 'close_breaker')], 'gt1_in_loaded',
                  ['The sync-check relay refuses a close outside ±10°, ±0.1 Hz and ±5 % voltage.'], 'none'))
    S.append(step('hrsg_warm', ['Hold GT 1 at minimum load and watch the HP drum pressure (', k('10HAD30CP001'),
                                ') and level rise.'], ['10HAD30CP001', '10HAD30CL501'], (), 'hp_p_10',
                  ['The drum warms at about 3 K per minute; more load would warm it too fast.']))
    S.append(step('drains_close', ['Close the superheater drains and the start-up vent.'],
                  ['10HAN30AA401', '10HAN30AA001'],
                  [op(f'10HAN30AA40{n}', 'close') for n in (1, 2, 3, 4)] + [op('10HAN30AA001', 'close')],
                  'hp_drains_closed'))
    S.append(step('casing_hot', ['Wait for the HP casing (', k('30MAA10'), ') to reach 190 °C.'], ['30MAA10'], (),
                  'st_casing_warm', go='none'))
    S.append(step('roll_ready', ['Wait until the steam turbine may roll: pressure, superheat, matching, eccentricity '
                                 'and vacuum.'], ['30MAA10'], (), 'st_roll_ready', go='none'))
    S.append(step('warm_close', ['Close the HP casing warm-up valve (', k('30MAA10AA101'), '): the steam itself '
                                 'warms the casing from now on.'], ['30MAA10AA101'],
                  [op('30MAA10AA101', 'close')], 'st_warm_shut', go='none'))
    S.append(step('st_roll', ['Roll the steam turbine (', k('30MAA10'), ').'], ['30MAA10'],
                  [op('30MAA10', 'roll')], 'st_in_fsnl',
                  ['It warms at 800 rpm, then accelerates through the critical speeds without stopping.'], 'fly'))
    S.append(step('st_exc', ['Switch on the steam turbine generator excitation (', k('30MKC10'), ').'], ['30MKC10'],
                  [op('30MKC10', 'start')], 'st_v_ok', go='none'))
    S.append(step('st_sync', ['Raise the steam turbine speed a little and synchronise.'], ['30MAY10CS001'],
                  [op('30MAY10CS001', 'set', 0.001)], 'st_sync_ok', go='none'))
    S.append(step('st_brk', ['Close the steam turbine generator breaker (', k('30BAC10'), ').'], ['30BAC10'],
                  [op('30BAC10', 'close_breaker')], 'st_in_loaded', go='none'))
    S.append(step('ct_fans', ['Start cooling tower fans 1 to 5 as the heat load comes.'],
                  ['30PAD10AN001', '30PAD10AN005'], [op(f'30PAD10AN{n:03d}', 'start') for n in range(1, 6)],
                  'ct_fans_5', go='fly'))
    S.append(step('gt_load', ['Raise GT 1 to base load, 250 MW (', k('10MKA10'), '): the bypass closes as the '
                              'steam turbine takes the steam.'], ['10MKA10'], [op('10MKA10', 'set', 250)],
                  'gt1_at_base', go='none'))
    S.append(step('cw_b_valve', ['Bring circulating water pump B (', k('30PAC10AP002'), ') in: valve to 15 %.'],
                  ['30PAC10AA102'], [op('30PAC10AA102', 'set', 0.15)], 'cw_b_vstart', go='fly'))
    S.append(step('cw_b_start', ['Start CW pump B.'], ['30PAC10AP002'], [op('30PAC10AP002', 'start')], 'cw_b_run'))
    S.append(step('cw_b_open', ['Open its discharge valve.'], ['30PAC10AA102'], [op('30PAC10AA102', 'open')],
                  'cw_b_vfull', ['A second pump halves the temperature rise in the condenser and deepens the vacuum, '
                                 'for 1.25 MW more pump power.']))
    S.append(step('at_load', ['The train is at base load: the HP bypass is closed and the steam turbine carries the '
                              'steam.'], ['30MKA10'], (), 'plant_at_load', go='none'))
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'cold_start', 'title': 'Cold start of train 1',
            'kind': 'procedure', 'scenario': 'cold_iron',
            'intro': [{'p': ['Bring train 1 from cold iron to base load: auxiliaries, circulating water, oil systems, '
                             'vacuum, the gas turbine, the HRSG warm-up, the steam turbine and loading.']}],
            'steps': S}


def hot_restart():
    """The hot restart (FIRST-TRAIN §4 "As built"): the cold start's steps without the casing warm-up (the casing is
    hot already), and before the roll a step that loads the GT until the steam is matched to the hot casing."""
    cs = cold_start()
    by_id = {st['id']: st for st in cs['steps']}
    S = []
    for st in cs['steps']:
        if st['id'] in ('casing_warm', 'casing_hot', 'warm_close', 'drains'):
            continue          # the drains: opened once the GT burns (open on a boxed-up HRSG they would empty it)
        if st['id'] == 'aux':
            st = dict(st, why=[{'p': ['Gland steam comes from here while the HRSG is not yet making any.']}])
        if st['id'] == 'hrsg_warm':
            drains = dict(by_id['drains'], text=['The GT burns: open the HP superheater drains (', k('10HAN30AA401'),
                                                 ' to ', k('10HAN30AA404'), ') and the start-up vent (',
                                                 k('10HAN30AA001'), ').'])
            S.append(drains)
            # the drum is hot and under pressure already: what the hold waits for is the superheaters' water
            st = step('sh_drain', ['Hold GT 1 at minimum load with the superheater drains open until they run dry (',
                                   k('10HAN30AA401'), ').'], ['10HAN30AA401', '10HAD30CP001'], (), 'hp_sh_drained',
                      ['Water left in the superheaters would reach the turbine as a slug, and keeps the steam far '
                       'colder than the metal.'])
        S.append(st)
        if st['id'] == 'drains_close':
            S.append(step('match', ['Raise GT 1 to 40 MW (', k('10MKA10'), ') and wait until the HP steam is within '
                                    '50 K of the HP casing (', k('30MAA10'), ').'], ['10MKA10', '30MAA10'],
                          [op('10MKA10', 'set', 40)], 'st_match',
                          ['The casing is still at about 470 °C. Steam more than 50 K colder would chill its inner '
                           'surface while the outside stays hot: the stress cracks it. At minimum load the GT\'s '
                           'exhaust can\'t make steam that hot; more load can, and the bypass takes the steam.'],
                          'none'))
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'hot_restart', 'title': 'Hot restart of train 1',
            'kind': 'procedure', 'scenario': 'hot_restart',
            'intro': [{'p': ['Bring train 1 back to base load three hours after a trip, with the steam turbine\'s HP '
                             'casing still hot: the auxiliaries, the gas turbine, then steam matched to the hot '
                             'casing before the turbine rolls.']}],
            'steps': S}


def tour(tid, title, intro, stops):
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': tid, 'title': title, 'kind': 'tour',
            'intro': [{'p': [intro]}],
            'steps': [step(f's{i}', text, at, go='walk') for i, (text, at) in enumerate(stops, 1)]}


def tours():
    return [
        tour('cw_path', 'Tour: the circulating water path',
             'Follow the cooling water from the tower basin through the pumps and the condenser and back to the fans.',
             [(['The cooling tower basin (', k('30PAD10BB001'), '): cooled water collects here, under the fill.'],
               ['30PAD10BB001']),
              (['The pump house: three vertical pumps (', k('30PAC10AP001'), ') lift water from the wet pit.'],
               ['30PAC10AP001', '30PAC10AP002', '30PAC10AP003']),
              (['Each pump discharges through a motor-operated butterfly valve (', k('30PAC10AA101'), ').'],
               ['30PAC10AA101']),
              (['The supply pipe (', k('30PAB10BR010'), ') runs buried, 2.2 m across, to the turbine hall.'],
               ['30PAB10BR010']),
              (['The condenser (', k('30MAG10AC001'), '): water passes through its tubes and takes the exhaust '
                'steam\'s heat.'], ['30MAG10AC001']),
              (['The return pipe (', k('30PAB20BR010'), ') carries the warm water back to the tower.'], ['30PAB20BR010']),
              (['The fans on the deck (', k('30PAD10AN001'), ') pull air up through the falling water.'],
               ['30PAD10AN001'])]),
        tour('water_steam', 'Tour: the water-steam cycle',
             'From the condenser through the HRSG to the turbine and back.',
             [(['The hotwell under the condenser (', k('30MAG10BB001'), ') collects the condensate.'], ['30MAG10BB001']),
              (['Condensate pumps (', k('30LCB10AP001'), ') push it to the HRSG\'s LP drum.'], ['30LCB10AP001']),
              (['The LP drum with its deaerator (', k('10HAD10BB001'), ') feeds the feedwater pumps.'],
               ['10HAD10BB001']),
              (['Feedwater pumps (', k('10LAC10AP001'), ') raise it to 130 bar.'], ['10LAC10AP001']),
              (['The HP drum (', k('10HAD30BB001'), ') separates steam from water. Its level glass is ',
                k('10HAD30CL501'), '.'], ['10HAD30BB001', '10HAD30CL501']),
              (['HP steam (', k('10LBA30BR001'), ') runs down the pipe rack to the HP turbine (', k('30MAA10'), ').'],
               ['10LBA30BR001', '30MAA10']),
              (['The IP/LP turbine (', k('30MAB10'), ') exhausts down into the condenser.'], ['30MAB10'])]),
    ]
