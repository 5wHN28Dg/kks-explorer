"""The stores of the first train (docs/plant3d/REALISM.md §7.2 and §2.23, milestone WM2): data/plant3d/stores.json, the
`<part>_low` content nodes (model/admin.json: the store is in the admin area) and the storekeeper's reorder tasks and
reactions (train_staff.py appends them after everything before them).

The parts are the spare parts lists of the equipment manuals (REALISM.md §6.2: each number is the manual's own,
`WDP-` + the manual's short code + the component or consumable id; the tests check every one against the manuals'
lists), for the train's equipment classes: the pressure transmitter, control and manual valves, centrifugal pumps
and their motors, and the turbines' consumables; plus complete units where a job replaces one: the condenser
pressure transmitters (absolute, sensor range 3, to 248 kPa: the condenser's 0–120 kPa(a) lies inside it), with a
look-alike of the next range (4, to 2,068 kPa) on the shelf beside them, as two transmitters of one model differ only
by the range code on their plate (`WDP-<short>-UNIT-…`: a complete unit, the manual's whole kind).

Classes are ISO 14224's equipment classes and their maintainable items (Annex A), in our words. Levels follow the
min/max practice of maintenance stores (Palmer, Maintenance Planning and Scheduling Handbook: a reorder point
covering the usage over the lead time plus a safety stock, a maximum a year's usage or so above it): insurance
spares (a complete transmitter, a mechanical seal, a positioner) kept at one or two with a long lead time;
common spares (bearings, packing, gaskets, O-rings) at a few with weeks of lead time; consumables (ferrules, oil)
in larger counts with days. Every part starts above its reorder point, so no reorder is made until someone draws
from the shelf. Generic and invented numbers: no maker's part numbers, no plant's stores."""

STORE = {'id': 'main', 'title': 'Main store', 'place': 'store_counter', 'self_service': False}

# the manuals' short codes (REALISM.md §6.2.1) and the condenser transmitters' look-alike sentences
RANGE3 = 'Range code 3 (to 248 kPa), as the condenser transmitters\' data sheet says'
DIFFERS_A4 = ('The range code on the new transmitter\'s plate is 4 (to 2,068 kPa), not the 3 (to 248 kPa) on the '
              'condenser transmitter\'s data sheet.')
DIFFERS_A3 = ('The range code on the new transmitter\'s plate is 3 (to 248 kPa), not the 4 (to 2,068 kPa) on this '
              'transmitter\'s data sheet.')

# (part id, the manual's short code, the catalogue id (the number's tail, `_` as `-`), title, class,
#  stock, min, reorder, max, lead days[, looks_like])
PARTS = [
    # the pressure transmitter (WDP-MAN-001): complete units first, then the manual's spare parts list
    ('pt_unit_a3', 'PT', 'unit_a3', 'Pressure transmitter, absolute, range 3 (to 248 kPa)',
     'Pressure transmitter', 2, 1, 1, 3, 42, [('pt_unit_a4', DIFFERS_A4)]),
    ('pt_unit_a4', 'PT', 'unit_a4', 'Pressure transmitter, absolute, range 4 (to 2,068 kPa)',
     'Pressure transmitter', 2, 1, 1, 3, 42, [('pt_unit_a3', DIFFERS_A3)]),
    ('pt_sensor_module', 'PT', 'sensor_module', 'Sensor module, absolute, range 3', 'Pressure transmitter: sensor',
     1, 0, 0, 2, 42),
    ('pt_electronics', 'PT', 'electronics', 'Electronics board (4–20 mA with HART)',
     'Pressure transmitter: electronics', 2, 1, 1, 3, 28),
    ('pt_terminal_block', 'PT', 'terminal_block', 'Terminal block', 'Pressure transmitter: wiring', 3, 1, 1, 4, 28),
    ('pt_manifold', 'PT', 'manifold', 'Three-valve manifold', 'Pressure transmitter: manifold', 2, 1, 1, 3, 35),
    ('pt_cover_front', 'PT', 'cover_front', 'Display-side cover with window', 'Pressure transmitter: housing',
     2, 1, 1, 3, 28),
    ('pt_flange_orings', 'PT', 'flange_orings', 'Process flange O-rings, PTFE (pair)', 'Pressure transmitter: seals',
     12, 4, 6, 16, 14),
    ('pt_cover_orings', 'PT', 'cover_orings', 'Cover O-rings (pair)', 'Pressure transmitter: seals', 12, 4, 6, 16, 14),
    ('pt_gland_seal', 'PT', 'gland_seal', 'Cable gland seal insert', 'Pressure transmitter: wiring', 20, 5, 8, 24, 14),
    ('pt_ferrules', 'PT', 'ferrules', 'Wire end ferrules, 0.75 mm², insulated', 'Pressure transmitter: wiring',
     400, 100, 200, 500, 7),
    # the control valve (WDP-MAN-002)
    ('cv_positioner', 'CV', 'positioner', 'Digital positioner with feedback linkage', 'Control valve: positioner',
     2, 1, 1, 3, 56),
    ('cv_diaphragm', 'CV', 'diaphragm', 'Actuator diaphragm', 'Control valve: actuator', 3, 1, 1, 4, 28),
    ('cv_packing_set', 'CV', 'packing_set', 'Stem packing set', 'Control valve: packing', 6, 2, 3, 8, 21),
    ('cv_body_gasket', 'CV', 'body_gasket', 'Bonnet gasket', 'Control valve: body', 6, 2, 3, 8, 21),
    ('cv_seat_ring_gasket', 'CV', 'seat_ring_gasket', 'Seat ring gasket', 'Control valve: trim', 4, 1, 2, 6, 21),
    ('cv_trim_set', 'CV', 'trim_set', 'Trim set: plug, stem, seat ring, cage', 'Control valve: trim', 1, 0, 0, 2, 90),
    ('cv_air_filter', 'CV', 'air_filter', 'Air filter regulator element', 'Control valve: actuator', 8, 2, 4, 10, 14),
    # manual and check valves (WDP-MAN-003)
    ('mv_packing_set', 'MV', 'packing_set', 'Stem packing rings, by size', 'Valve: packing', 20, 6, 8, 24, 14),
    ('mv_bonnet_gasket', 'MV', 'bonnet_gasket', 'Bonnet or cover gasket, by size', 'Valve: body', 12, 4, 6, 16, 21),
    ('mv_seat_set', 'MV', 'seat_set', 'Ball valve seats and seals, by size', 'Valve: seat', 6, 2, 3, 8, 28),
    ('mv_liner', 'MV', 'liner', 'Butterfly valve liner, by size', 'Valve: seat', 3, 1, 1, 4, 42),
    ('mv_disc_hinge_pin', 'MV', 'disc_hinge_pin', 'Swing check valve hinge pin and bushes', 'Valve: closure member',
     3, 1, 1, 4, 28),
    ('mv_stem_nut', 'MV', 'stem_nut', 'Stem nut (yoke bush)', 'Valve: stem', 3, 1, 1, 4, 28),
    # centrifugal pumps and their motors (WDP-MAN-004)
    ('cp_mech_seal', 'CP', 'mech_seal', 'Mechanical seal cartridge', 'Pump: shaft seal', 2, 1, 1, 3, 56),
    ('cp_bearing_de', 'CP', 'bearing_de', 'Rolling bearing, drive end', 'Pump: bearing', 4, 2, 2, 6, 21),
    ('cp_bearing_nde', 'CP', 'bearing_nde', 'Rolling bearing, non-drive end', 'Pump: bearing', 4, 2, 2, 6, 21),
    ('cp_wear_rings', 'CP', 'wear_rings', 'Casing and impeller wear rings', 'Pump: casing', 2, 1, 1, 3, 42),
    ('cp_casing_gasket', 'CP', 'casing_gasket', 'Casing gasket', 'Pump: casing', 6, 2, 3, 8, 21),
    ('cp_coupling_element', 'CP', 'coupling_element', 'Coupling flexible element', 'Pump: coupling', 4, 1, 2, 6, 21),
    ('cp_oil', 'CP', 'oil', 'Bearing oil, ISO VG 68, 20 l', 'Pump: lubrication', 10, 3, 4, 12, 7),
    ('cp_line_bearing', 'CP', 'line_bearing', 'Vertical pump line shaft bushes', 'Pump: bearing', 2, 1, 1, 3, 56),
    ('cp_v_bearing_thrust', 'CP', 'v_bearing_thrust', 'Vertical motor thrust bearing', 'Electric motor: bearing',
     2, 1, 1, 3, 42),
    ('cp_h_bearing_de', 'CP', 'h_bearing_de', 'Motor bearing, drive end', 'Electric motor: bearing', 4, 2, 2, 6, 21),
    ('cp_h_bearing_nde', 'CP', 'h_bearing_nde', 'Motor bearing, non-drive end', 'Electric motor: bearing',
     4, 2, 2, 6, 21),
    ('cp_h_fan', 'CP', 'h_fan', 'Motor cooling fan', 'Electric motor: cooling', 2, 1, 1, 3, 28),
    # the steam turbine (WDP-MAN-005) and the gas turbine (WDP-MAN-006): consumables and outage spares
    ('st_lube_oil', 'ST', 'lube_oil', 'Turbine oil, ISO VG 32, 200 l', 'Steam turbine: lubrication', 6, 2, 3, 8, 14),
    ('st_valve_seals', 'ST', 'valve_seals', 'Stop and control valve stem seals and seat gaskets',
     'Steam turbine: valves', 2, 1, 1, 3, 90),
    ('st_gland_segments', 'ST', 'gland_segments', 'Labyrinth gland seal segments with springs',
     'Steam turbine: seals', 1, 0, 0, 2, 120),
    ('gt_inlet_filters', 'GT', 'inlet_filters', 'Inlet air filter elements', 'Gas turbine: air inlet', 2, 1, 1, 3, 60),
    ('gt_igniters', 'GT', 'igniters', 'Spark igniter', 'Gas turbine: combustion', 4, 2, 2, 6, 42),
    ('gt_flame_scanners', 'GT', 'flame_scanners', 'Flame detector', 'Gas turbine: combustion', 2, 1, 1, 3, 56),
    ('gt_wash_detergent', 'GT', 'wash_detergent', 'Compressor wash detergent, 200 l', 'Gas turbine: compressor',
     4, 1, 2, 5, 21),
]


def number(short, cid):
    """REALISM.md §6.2's rule (tools/plant3d/manuals.py part_number)."""
    return 'WDP-%s-%s' % (short, cid.upper().replace('_', '-'))


def stores():
    """stores.json (format walkdown-plant-stores, version 1)."""
    parts = []
    for row in PARTS:
        pid, short, cid, title, cls, stock, lo, reorder, hi, lead = row[:10]
        p = {'id': pid, 'number': number(short, cid), 'title': title, 'class': cls, 'store': STORE['id'],
             'stock': stock, 'min': lo, 'reorder': reorder, 'max': hi, 'lead_days': lead}
        if len(row) > 10:
            p['looks_like'] = [{'part': q, 'differs': d} for q, d in row[10]]
        parts.append(p)
    return {'format': 'walkdown-plant-stores', 'version': 1, 'stores': [dict(STORE)], 'parts': parts}


def low_nodes():
    """Per part, what is on the shelf and on order (`<part>_have`) and whether that is at or under the reorder point
    (`<part>_low`, REALISM.md §2.23): the storekeeper's reaction reads it."""
    out = []
    for row in PARTS:
        pid, reorder = row[0], row[7]
        out.append([f'{pid}_have', {'sum': [f'{pid}_stock', f'{pid}_due']}])
        out.append([f'{pid}_low', {'cmp': [f'{pid}_have', '<=', reorder]}])
    return out


def model():
    """model/admin.json: the stores' content nodes, in the store's area."""
    return {'format': 'walkdown-plant-model', 'version': 2, 'area': 'admin', 'values': low_nodes()}


def tasks():
    """The storekeeper's reorder of each part: at the counter, the order written, up to the part's max."""
    return [{'id': f'reorder_{row[0]}', 'title': f'Reorder: {row[3]}'[:120], 'priority': 4,
             'steps': [{'go': 'store_counter'}, {'work': 5, 'anim': 'write'}, {'order': row[0]}]} for row in PARTS]


def reactions():
    """When a part's shelf and orders reach its reorder point, the storekeeper orders it (on their duty days; an offer
    nobody could take is made again when they come on, §17.12)."""
    return [{'on': {'value': f'{row[0]}_low'}, 'roles': ['store'], 'task': f'reorder_{row[0]}'} for row in PARTS]
