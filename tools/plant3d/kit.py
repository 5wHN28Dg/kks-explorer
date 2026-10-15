"""The parts kit's interface (docs/PLANT3D.md §9): every part with its parameters (defaults and limits), nozzles, anim
channels and plate points. Written to data/plant3d/kit.json by make_content.py; the Godot kit (apps/plant3d/kit)
implements each part declared here and the content build refuses a part it lacks.

Nozzle coordinates are in the part's frame (x right, y forward = the part's main axis, z up, origin on its base at the
centre of its footprint), each a number or [parameter, factor, offset] = parameter × factor + offset."""


def N(lo, hi, default=None):
    d = {'type': 'num', 'min': lo, 'max': hi}
    if default is not None:
        d['default'] = default
    return d


def I(lo, hi, default=None):
    d = {'type': 'int', 'min': lo, 'max': hi}
    if default is not None:
        d['default'] = default
    return d


def E(values, default=None):
    d = {'type': 'enum', 'values': list(values)}
    if default is not None:
        d['default'] = default
    return d


def B(default):
    return {'type': 'bool', 'default': default}


def T(kind):
    return {'type': kind}


def TXT(default, hi=16):
    return {'type': 'text', 'max': hi, 'default': default}


def R(fields, hi):
    return {'type': 'records', 'fields': fields, 'max': hi}


def part(group, params, nozzles=None, anim=None, plates=None, inline=False, walkable=False):
    p = {'group': group, 'params': params}
    if nozzles:
        p['nozzles'] = {k: {'at': at, 'dir': d} for k, (at, d) in nozzles.items()}
    if anim:
        p['anim'] = anim
    if plates:
        p['plates'] = plates
    if inline:
        p['inline'] = True
    if walkable:
        p['walkable'] = True
    return p


# EN 10220 / ASME B36.10 outside diameters (mm) for the nominal sizes the plant uses
DN_OD = [[15, 21.3], [20, 26.9], [25, 33.7], [32, 42.4], [40, 48.3], [50, 60.3], [65, 76.1], [80, 88.9],
         [100, 114.3], [125, 139.7], [150, 168.3], [200, 219.1], [250, 273.0], [300, 323.9], [350, 355.6],
         [400, 406.4], [450, 457.0], [500, 508.0], [600, 610.0], [700, 711.0], [800, 813.0], [900, 914.0],
         [1000, 1016.0], [1200, 1219.0], [1400, 1422.0], [1600, 1626.0], [1800, 1829.0], [2000, 2032.0]]

VALVE = {'dn': I(6, 4000, 100), 'rating': E(['pn10', 'pn16', 'pn25', 'pn40', 'pn63', 'pn100', 'pn160', 'pn250'], 'pn16'),
         'actuator': E(['manual', 'gear', 'electric', 'pneumatic', 'hydraulic'], 'manual'),
         'handwheel': E(['top', 'left', 'right'], 'top')}
RANGE = {'range': T('pair'), 'unit': TXT('bar')}

PARTS = {
    # machines
    'gas_turbine': part('machines', {'rating_mw': N(1, 600, 250), 'length': N(5, 40, 22), 'casing_d': N(1, 8, 4.5),
                                     'intake': E(['top', 'side'], 'top'), 'exhaust': E(['axial'], 'axial')},
                        {'fuel_in': ([['casing_d', -0.5, -0.8], 0, 1.0], 'w'),
                         'exhaust': ([0, ['length', 0.5, 0], ['casing_d', 0.5, 1.0]], 'n')},
                        ['shaft'], ['side']),
    'generator': part('machines', {'rating_mva': N(1, 800, 300), 'length': N(2, 20, 10), 'd': N(1, 6, 3.5),
                                   'cooling': E(['air', 'hydrogen'], 'air')}, None, ['shaft'], ['side']),
    'steam_turbine': part('machines', {'length': N(5, 60, 30), 'd': N(1, 8, 4),
                                       'casings': R({'kind': E(['hp', 'ip', 'ip_lp', 'lp']), 'length': N(1, 30),
                                                     'd': N(1, 8)}, 4),
                                       'exhaust': E(['down', 'axial'], 'down')},
                          {'hp_inlet': ([0, ['length', 0.5, -3], 0], 'down'),
                           'crh_out': ([1.5, ['length', 0.5, -6], 0], 'down'),
                           'hrh_in': ([-1.5, ['length', 0.5, -9], 0], 'down'),
                           'lp_in': ([0, ['length', 0.5, -14], 0], 'down'),
                           'gland_in': ([-1.5, ['length', 0.5, -1], 0], 'down')},
                          ['shaft'], ['side']),
    'sfc': part('machines', {'panels': I(1, 20, 6), 'depth': N(0.4, 2, 0.8)}, None, None, ['front']),
    'turning_gear': part('machines', {'kw': N(1, 500, 30)}, None, ['shaft'], ['side']),
    # HRSG
    'hrsg': part('hrsg', {'length': N(10, 80, 55), 'width': N(5, 40, 22), 'height': N(10, 50, 30),
                          'modules': I(1, 12, 7), 'inlet_duct': N(0, 30, 15), 'outlet_duct': N(0, 30, 10)},
                 {'hp_steam': ([4, ['length', -0.5, 3], ['height', 1, 0]], 'up'),
                  'hrh_out': ([-4, ['length', -0.5, 7], ['height', 1, 0]], 'up'),
                  'crh_in': ([-4, ['length', -0.5, 9], ['height', 1, 0]], 'up'),
                  'lp_steam': ([4, ['length', 0.5, -10], ['height', 1, 0]], 'up'),
                  'hp_fw_in': ([['width', 0.5, 0], ['length', 0.5, -12], 6], 'e'),
                  'lp_cond_in': ([['width', 0.5, 0], ['length', 0.5, -3], 4], 'e'),
                  'sh_drain': ([['width', 0.5, 0], ['length', -0.5, 4], 1.5], 'e')},
                 None, ['casing']),
    'hrsg_module': part('hrsg', {'kind': E(['economiser', 'evaporator', 'superheater', 'reheater']),
                                 'width': N(2, 40, 20), 'depth': N(0.5, 10, 2.5), 'height': N(2, 50, 26)},
                        None, None, ['door']),
    'drum': part('hrsg', {'d': N(0.5, 4, 1.8), 'length': N(2, 30, 15), 'saddles': I(2, 4, 2)},
                 {'steam_out': ([0, 0, ['d', 1, 0.2]], 'up'),
                  'water_out': ([0, ['length', 0.5, 0.3], 0.6], 'n'),
                  'blowdown': ([0, ['length', -0.5, -0.3], 0.6], 's')},
                 None, ['side']),
    'stack': part('hrsg', {'d': N(1, 15, 7), 'height': N(10, 120, 60), 'platforms': I(0, 6, 2),
                           'damper': B(False)}, None, None, ['base']),
    'duct': part('hrsg', {'route': T('path'), 'width': N(1, 30, 10), 'height': N(1, 30, 10),
                          'joints': I(0, 8, 1)}, None, None, ['side']),
    'silencer': part('hrsg', {'d': N(0.3, 4, 1.2), 'height': N(1, 10, 4)},
                     {'inlet': ([0, ['d', -0.5, -0.3], 0.8], 's')}, None, ['side']),
    'filter_house': part('machines', {'length': N(2, 40, 14), 'width': N(2, 30, 12), 'height': N(2, 20, 8)},
                         None, None, ['side']),
    # rotating
    'pump_horizontal': part('rotating', {'flow_m3h': N(0.1, 50000, 100), 'head_m': N(1, 3000, 50),
                                         'motor_kw': N(0.1, 20000, 30), 'length': N(1, 12, 3)},
                            {'suction': ([0, ['length', 0.5, 0], 0.6], 'n'),
                             'discharge': ([0, ['length', 0.25, 0], 1.4], 'up')},
                            ['shaft'], ['motor_side', 'pump_side']),
    'pump_vertical': part('rotating', {'flow_m3h': N(0.1, 50000, 1000), 'head_m': N(1, 500, 20),
                                       'motor_kw': N(0.1, 20000, 200), 'pit_depth': N(0, 20, 6)},
                          {'discharge': ([0, 1.2, 1.5], 'n'),
                           'suction': ([0, 0, ['pit_depth', -1, 0]], 'down')},
                          ['shaft'], ['motor_side']),
    'fan_axial': part('rotating', {'d': N(0.5, 15, 9.5), 'blades': I(3, 12, 8), 'motor_kw': N(0.1, 2000, 200),
                                   'stack_height': N(0, 10, 3)}, None, ['shaft'], ['deck']),
    'compressor_skid': part('rotating', {'kw': N(1, 5000, 250), 'length': N(1, 12, 4), 'width': N(0.5, 6, 2)},
                            {'air_out': ([0, ['length', 0.5, 0], 1.0], 'n')}, ['shaft'], ['side']),
    'vacuum_pump_skid': part('rotating', {'kind': E(['liquid_ring'], 'liquid_ring'), 'kw': N(1, 1000, 160),
                                          'length': N(1, 10, 4)},
                             {'suction': ([0, ['length', 0.5, 0], 1.2], 'n')}, ['shaft'], ['side']),
    # heat exchange
    'condenser': part('heat_exchange', {'length': N(4, 30, 14), 'width': N(3, 25, 12), 'height': N(4, 25, 16),
                                        'waterboxes': I(2, 4, 4), 'passes': I(1, 2, 1), 'hotwell': B(True)},
                      {'cw_inlet_a': ([['width', -0.25, 0], ['length', -0.5, -1.0], 1.5], 's'),
                       'cw_inlet_b': ([['width', 0.25, 0], ['length', -0.5, -1.0], 1.5], 's'),
                       'cw_outlet_a': ([['width', -0.25, 0], ['length', 0.5, 1.0], 1.5], 'n'),
                       'cw_outlet_b': ([['width', 0.25, 0], ['length', 0.5, 1.0], 1.5], 'n'),
                       'bypass_in': ([['width', 0.5, 0], 0, ['height', 0.6, 0]], 'e'),
                       'recirc_in': ([['width', 0.5, 0], ['length', 0.25, 0], ['height', 0.3, 0]], 'e'),
                       'hotwell_out': ([['width', 0.5, 0], ['length', -0.25, 0], 0.8], 'e'),
                       'air_out': ([['width', -0.5, 0], ['length', 0.25, 0], ['height', 0.5, 0]], 'w')},
                      None, ['shell', 'waterbox']),
    'shell_tube_hx': part('heat_exchange', {'d': N(0.2, 5, 1.2), 'length': N(1, 20, 5),
                                            'orientation': E(['horizontal', 'vertical'], 'horizontal')},
                          {'shell_in': ([0, ['length', 0.3, 0], ['d', 1, 0.3]], 'up'),
                           'shell_out': ([0, ['length', -0.3, 0], ['d', 1, 0.3]], 'up'),
                           'tube_in': ([0, ['length', 0.5, 0.3], ['d', 0.5, 0.3]], 'n'),
                           'tube_out': ([0, ['length', -0.5, -0.3], ['d', 0.5, 0.3]], 's')},
                          None, ['shell']),
    'plate_hx': part('heat_exchange', {'plates': I(5, 800, 200), 'height': N(0.5, 4, 2.2)},
                     {'hot_in': ([-0.3, 0.6, ['height', 0.85, 0]], 'n'), 'hot_out': ([-0.3, 0.6, 0.3], 'n'),
                      'cold_in': ([0.3, 0.6, 0.3], 'n'), 'cold_out': ([0.3, 0.6, ['height', 0.85, 0]], 'n')},
                     None, ['frame']),
    'cooling_tower': part('heat_exchange', {'cells_x': I(1, 20, 5), 'cells_y': I(1, 4, 2),
                                            'length': N(10, 400, 80), 'width': N(10, 80, 32),
                                            'height': N(5, 30, 14), 'fan_d': N(1, 15, 9.5),
                                            'basin_depth': N(0.5, 5, 2), 'fill': E(['film', 'splash'], 'film')},
                          {'hot_water_in': ([0, ['width', -0.5, -1.0], ['height', 1, -2]], 's'),
                           'makeup_in': ([['length', 0.5, 1.0], 0, 0.5], 'e')},
                          None, ['basin']),
    # vessels
    'package_boiler': part('vessels', {'d': N(1, 6, 3), 'length': N(2, 20, 8), 'steam_tph': N(1, 200, 30)},
                           {'steam_out': ([0, 0, ['d', 1, 0.5]], 'up')}, None, ['side']),
    'basin': part('vessels', {'length': N(2, 400, 80), 'width': N(2, 100, 32), 'depth': N(0.5, 6, 2)},
                  None, None, ['edge']),
    'tank_vertical': part('vessels', {'d': N(0.5, 40, 8), 'height': N(1, 30, 10),
                                      'roof': E(['cone', 'dome', 'open'], 'cone')},
                          {'inlet': ([0, ['d', -0.5, -0.3], ['height', 0.9, 0]], 's'),
                           'outlet': ([0, ['d', 0.5, 0.3], 0.5], 'n')},
                          None, ['side']),
    'vessel_horizontal': part('vessels', {'d': N(0.3, 6, 2), 'length': N(1, 30, 6), 'saddles': I(2, 4, 2)},
                              {'inlet': ([0, ['length', -0.5, -0.3], ['d', 0.5, 0.5]], 's'),
                               'outlet': ([0, ['length', 0.5, 0.3], ['d', 0.5, 0.5]], 'n'),
                               'vent': ([0, 0, ['d', 1, 0.7]], 'up')},
                              None, ['side']),
    # valves (inline on pipes) and the damper
    'valve_gate': part('valves', dict(VALVE), None, ['stem', 'handwheel'], ['body'], inline=True),
    'valve_globe': part('valves', dict(VALVE), None, ['stem', 'handwheel'], ['body'], inline=True),
    'valve_butterfly': part('valves', dict(VALVE), None, ['disc', 'handwheel'], ['body'], inline=True),
    'valve_ball': part('valves', dict(VALVE), None, ['disc', 'handwheel'], ['body'], inline=True),
    'valve_check': part('valves', {'dn': I(6, 4000, 100), 'rating': VALVE['rating']}, None, ['disc'], ['body'],
                        inline=True),
    'valve_control': part('valves', dict(VALVE, actuator=E(['electric', 'pneumatic', 'hydraulic'], 'pneumatic')),
                          None, ['stem'], ['body'], inline=True),
    'valve_safety': part('valves', {'dn': I(6, 1000, 100), 'rating': VALVE['rating'], 'set_bar': N(0.5, 400, 10)},
                         None, ['stem'], ['body'], inline=True),
    'damper': part('valves', {'width': N(0.5, 30, 5), 'height': N(0.5, 30, 5), 'blades': I(1, 20, 6),
                              'actuator': VALVE['actuator']}, None, ['blades'], ['frame']),
    # instruments
    'pressure_gauge': part('instruments', dict(RANGE, dial_d=N(0.05, 0.3, 0.1)), None, ['needle'], ['dial'],
                           inline=True),
    'pressure_transmitter': part('instruments', dict(RANGE), None, None, ['body'], inline=True),
    'temperature_element': part('instruments', {'range': T('pair'), 'unit': TXT('°C')}, None, None, ['head'],
                                inline=True),
    'temperature_gauge': part('instruments', {'range': T('pair'), 'unit': TXT('°C')}, None, ['needle'], ['dial'],
                              inline=True),
    'level_glass': part('instruments', {'range': T('pair'), 'unit': TXT('mm')}, None, ['level'], ['body']),
    'level_transmitter': part('instruments', {'range': T('pair'), 'unit': TXT('mm')}, None, None, ['body']),
    'flow_element': part('instruments', {'kind': E(['orifice', 'venturi', 'magnetic'], 'orifice'),
                                         'range': T('pair'), 'unit': TXT('m³/h')}, None, None, ['body'],
                         inline=True),
    'position_switch': part('instruments', {}, None, None, ['body'], inline=True),
    'vibration_probe': part('instruments', {'kind': E(['velocity', 'proximity'], 'proximity'), 'range': T('pair'),
                                            'unit': TXT('µm')}, None, None, ['body']),
    'speed_probe': part('instruments', {'range': T('pair'), 'unit': TXT('rpm')}, None, None, ['body']),
    'flame_detector': part('instruments', {}, None, None, ['body']),
    'local_panel': part('instruments', {'width': N(0.3, 6, 0.8), 'height': N(0.3, 3, 1.8)}, None, None, ['front']),
    'push_button_station': part('instruments', {'buttons': E(['start_stop', 'start_stop_emergency'], 'start_stop')},
                                None, None, ['front']),
    # electrical
    'transformer': part('electrical', {'mva': N(0.1, 1000, 300), 'kind': E(['gsu', 'aux']),
                                       'radiators': I(0, 16, 6), 'bushings': I(3, 9, 6)}, None, None, ['tank']),
    'breaker': part('electrical', {'kind': E(['gcb', 'mv'], 'gcb'), 'length': N(1, 15, 6)}, None, ['contacts'],
                    ['side']),
    'switchgear_row': part('electrical', {'panels': I(1, 60, 10), 'depth': N(0.5, 3, 1.5)}, None, None, ['front']),
    'cabinet': part('electrical', {'width': N(0.3, 20, 1.2), 'height': N(0.5, 3, 2.2), 'depth': N(0.2, 3, 0.8)},
                    None, None, ['front']),
    'junction_box': part('electrical', {}, None, None, ['front']),
    'cable_tray': part('electrical', {'route': T('path'), 'width': N(0.1, 2, 0.6)}, None, None, None),
    'motor': part('electrical', {'kw': N(0.1, 30000, 100)}, None, ['shaft'], ['side']),
    # pipe pieces made by the build (§4, §9)
    'elbow': part('pipes', {'dn': I(6, 4000, 100)}),
    'tee': part('pipes', {'dn': I(6, 4000, 100)}),
    'reducer': part('pipes', {'dn': I(6, 4000, 100), 'dn2': I(6, 4000, 80)}),
    'flange': part('pipes', {'dn': I(6, 4000, 100)}),
    'pipe_support': part('pipes', {'kind': E(['shoe', 'guide', 'anchor', 'hanger'], 'shoe')}),
    # structures (§5): placed by `at` (outline relative to it), or by foot and top
    'building': part('structures', {'outline': T('polygon'), 'height': N(2, 80), 'roof': E(['flat', 'pitched'], 'flat'),
                                    'cladding': E(['metal', 'concrete', 'brick'], 'metal'),
                                    'openings': {'type': 'records', 'max': 64, 'fields': {
                                        'kind': E(['door', 'louvre', 'pipe', 'window']), 'at': T('xyz'),
                                        'width': N(0.2, 30), 'height': N(0.2, 30)}}}),
    'floor': part('structures', {'outline': T('polygon'), 'openings': {'type': 'polygons', 'default': []},
                                 'deck': E(['concrete', 'grating', 'steel'], 'concrete')}, walkable=True),
    'platform': part('structures', {'outline': T('polygon'), 'openings': {'type': 'polygons', 'default': []},
                                    'deck': E(['grating', 'concrete', 'steel'], 'grating'),
                                    'edge': E(['handrail', 'kickplate', 'none'], 'handrail')}, walkable=True),
    'grating': part('structures', {'outline': T('polygon'), 'openings': {'type': 'polygons', 'default': []}},
                    walkable=True),
    'road': part('structures', {'outline': T('polygon'), 'openings': {'type': 'polygons', 'default': []},
                                'surface': E(['asphalt', 'concrete', 'gravel'], 'asphalt')}, walkable=True),
    'stair': part('structures', {'foot': T('xyz'), 'top': T('xyz'), 'layout': E(['straight', 'switchback'], 'straight'),
                                 'width': N(0.6, 2.5, 1.0)}, walkable=True),
    'ladder': part('structures', {'foot': T('xyz'), 'top': N(-30, 200), 'facing': N(0, 360, 0)}, walkable=True),
    'handrail': part('structures', {'route': T('path')}),
    'door': part('structures', {'kind': E(['personnel', 'double', 'roller'], 'personnel'), 'width': N(0.7, 10, 1.0),
                                'height': N(1.9, 10, 2.1)}),
    'column': part('structures', {'height': N(0.5, 80, 6), 'size': N(0.1, 2, 0.4)}),
    'beam': part('structures', {'route': T('path'), 'size': N(0.1, 2, 0.4)}),
    'trench': part('structures', {'outline': T('polygon'), 'depth': N(0.2, 5, 1)}),
    'fence': part('structures', {'route': T('path'), 'height': N(0.5, 5, 2.4)}),
    'slab': part('structures', {'outline': T('polygon'), 'thickness': N(0.1, 3, 0.5)}),
    'pit': part('structures', {'outline': T('polygon'), 'depth': N(0.5, 30, 6)}),
    'pipe_rack': part('structures', {'length': N(2, 500, 50), 'width': N(1, 20, 6), 'height': N(2, 30, 8),
                                     'tiers': I(1, 4, 2), 'bays': I(1, 100, 8)}),
    # people cues
    'tag_plate': part('cues', {'kind': E(['small', 'large'], 'small')}),
    'sign': part('cues', {'size': N(0.05, 2, 0.3)}),
    'lamp': part('cues', {'colour': E(['white', 'green', 'red', 'amber', 'blue'], 'white')}),
    'beacon': part('cues', {'colour': E(['red', 'amber', 'blue'], 'amber')}),
    'horn': part('cues', {}),
    'emergency_stop': part('cues', {}),
    'safety_shower': part('cues', {}),
}


def kit():
    return {'format': 'walkdown-plant-kit', 'version': 1, 'dn_od_mm': DN_OD, 'parts': PARTS}
