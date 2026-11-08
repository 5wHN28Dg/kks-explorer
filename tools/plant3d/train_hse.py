"""The first train's hazard library (data/plant3d/hse.json, format walkdown-plant-hse version 1; docs/plant3d/REALISM.md
§8.6, milestone HS1) and each work's job kind: the hazards its jobs meet and the controls that answer them, from public
sources only (the keys of REALISM.md §14: OSHA3071 job hazard analysis, HSG250 permits to work, IOGP459 life-saving
rules, INDG163 risk assessment). Nothing here is any real plant's."""

FORMAT = 'walkdown-plant-hse'

CONTROLS = [
    ('loto', 'Isolation locked, tagged and tried before work starts', 'IOGP459'),
    ('test_dead', 'Tested dead with an approved voltage tester before touching', 'HSG250'),
    ('insulated_tools', 'Insulated tools; rings and watches off', 'OSHA3071'),
    ('arc_ppe', 'Arc-rated clothing and face shield to rack the breaker or test', 'OSHA3071'),
    ('discharge', 'Winding discharged to earth after the insulation test', 'OSHA3071'),
    ('warn_area', 'Test area barriered and the people near warned', 'HSG250'),
    ('guards', 'Guards back on and the area clear before any test run', 'OSHA3071'),
    ('fan_locked', 'Fan brake on and the fan locked against turning in the wind', 'OSHA3071'),
    ('drain_vent', 'Line drained and vented: its gauge reads zero before opening', 'HSG250'),
    ('spring_release', 'Actuator\'s stored energy released before taking it apart', 'OSHA3071'),
    ('stroke_control', 'Valve moved only by agreement, from the local station, hands clear', 'IOGP459'),
    ('cool_down', 'Left to cool; temperature checked before touching', 'OSHA3071'),
    ('harness', 'Harness on and clipped to an anchor point at height', 'IOGP459'),
    ('scaffold_tag', 'Platform or scaffold inspected and tagged safe before use', 'IOGP459'),
    ('barrier_below', 'Area below barriered off; tools tethered', 'IOGP459'),
    ('lifting_plan', 'Lifting plan: certified slings and hoist within rating, nobody under the load', 'IOGP459'),
    ('two_person', 'Heavy parts moved by two people or with a lifting aid', 'INDG163'),
    ('gloves', 'Work gloves for the job', 'OSHA3071'),
    ('glasses', 'Safety glasses', 'OSHA3071'),
    ('hearing', 'Hearing protection in the noisy areas', 'INDG163'),
    ('chem_ppe', 'Chemical goggles, gloves and apron; safety data sheet read; eyewash checked', 'OSHA3071'),
    ('gas_test', 'Gas tested before entry, a standby person at the entry', 'HSG250'),
    ('respirator', 'Dust mask or respirator; the space ventilated', 'OSHA3071'),
    ('no_ignition', 'No hot work or other ignition near; tins kept closed', 'HSG250'),
    ('housekeeping', 'Spills cleaned up at once; walkways kept clear', 'INDG163'),
    ('inform_ccr', 'Control room told before and after; the instrument\'s trips and alarms checked with them',
     'HSG250'),
    ('lift_secured', 'Cab and counterweight secured; brake held before work in the shaft', 'OSHA3071'),
]

HAZARDS = [
    ('elec_shock', 'Electric shock from a live conductor', ['loto', 'test_dead', 'insulated_tools'], 'OSHA3071'),
    ('arc_flash', 'Arc flash when racking the breaker or testing', ['arc_ppe', 'loto'], 'OSHA3071'),
    ('test_voltage', 'Insulation-test voltage left on the winding', ['discharge', 'warn_area'], 'OSHA3071'),
    ('rotating', 'The machine started or turned while hands are in it', ['loto', 'guards'], 'IOGP459'),
    ('windmilling', 'The fan turned by the wind', ['fan_locked'], 'OSHA3071'),
    ('stored_pressure', 'Pressure or vacuum left in the line', ['drain_vent', 'loto'], 'HSG250'),
    ('stored_spring', 'Energy stored in the actuator\'s spring', ['spring_release'], 'OSHA3071'),
    ('valve_stroke', 'The valve moved by its actuator while hands are on it', ['stroke_control', 'loto'], 'IOGP459'),
    ('hot_surface', 'Hot surfaces and hot oil', ['cool_down', 'gloves'], 'OSHA3071'),
    ('height', 'A fall from height', ['harness', 'scaffold_tag'], 'IOGP459'),
    ('dropped', 'Tools or parts dropped on people below', ['barrier_below'], 'IOGP459'),
    ('lifting', 'A suspended load falls or swings', ['lifting_plan'], 'IOGP459'),
    ('manual', 'Strain lifting heavy parts by hand', ['two_person'], 'INDG163'),
    ('pinch', 'Hands caught between parts', ['gloves'], 'OSHA3071'),
    ('debris', 'Grit or rust in the eyes', ['glasses'], 'OSHA3071'),
    ('noise', 'Noise of the running plant around', ['hearing'], 'INDG163'),
    ('slips', 'Slips on oil, water or ice', ['housekeeping'], 'INDG163'),
    ('chemicals', 'Acid, caustic or treatment chemicals on skin or in the eyes', ['chem_ppe'], 'OSHA3071'),
    ('confined', 'A bad atmosphere inside the vessel', ['gas_test'], 'HSG250'),
    ('dust', 'Dust from filters and cabinets', ['respirator'], 'OSHA3071'),
    ('fumes', 'Paint solvent fumes', ['respirator'], 'OSHA3071'),
    ('flammable', 'Paint and solvent catching fire', ['no_ignition'], 'HSG250'),
    ('process_trip', 'A trip or a false signal while the instrument is out of service', ['inform_ccr'], 'HSG250'),
    ('lift_moves', 'The lift\'s cab or counterweight moving', ['lift_secured', 'loto'], 'OSHA3071'),
]

JOBS = [
    ('elec_motor', 'A motor\'s windings and terminals checked', ['elec_shock', 'arc_flash', 'rotating', 'noise']),
    ('elec_ir', 'A motor\'s insulation resistance tested', ['elec_shock', 'arc_flash', 'test_voltage', 'rotating']),
    ('elec_relay', 'A motor\'s protection tested and its relay replaced', ['elec_shock', 'arc_flash', 'process_trip']),
    ('elec_cabinet', 'An electrical cabinet\'s air filters replaced', ['elec_shock', 'dust', 'pinch']),
    ('motor_bearings', 'A pump motor\'s bearings replaced', ['rotating', 'lifting', 'manual', 'pinch', 'hot_surface',
                                                             'noise', 'slips']),
    ('valve_actuator', 'A valve\'s actuator overhauled and its stem repacked', ['stored_spring', 'stored_pressure',
                                                                                'valve_stroke', 'manual', 'pinch',
                                                                                'noise']),
    ('limit_switch', 'A valve\'s limit switch replaced', ['elec_shock', 'valve_stroke', 'process_trip', 'noise']),
    ('fan_gearbox', 'A cooling tower fan\'s gear reducer overhauled', ['height', 'windmilling', 'lifting', 'dropped',
                                                                       'manual', 'slips']),
    ('fan_service', 'A cooling tower fan\'s bearings serviced', ['height', 'windmilling', 'dropped', 'hot_surface',
                                                                 'slips']),
    ('transmitter', 'A pressure transmitter calibrated or put right', ['process_trip', 'stored_pressure', 'elec_shock',
                                                                       'noise']),
    ('level_thaw', 'A frozen impulse line thawed and heat tracing fitted', ['process_trip', 'stored_pressure',
                                                                            'elec_shock', 'slips']),
    ('vib_transmitter', 'A fan\'s vibration transmitter checked or replaced', ['height', 'windmilling', 'process_trip',
                                                                               'elec_shock']),
    ('gt_filters', 'The gas turbine\'s intake filter cartridges replaced', ['height', 'dust', 'dropped', 'manual']),
    ('lift_drive', 'The service lift\'s drive repaired', ['lift_moves', 'elec_shock', 'height', 'pinch']),
    ('wtp_resin', 'A mixed bed\'s underdrain repaired and resin topped up', ['confined', 'chemicals', 'manual',
                                                                             'slips']),
    ('wtp_membranes', 'An RO train\'s membrane elements replaced', ['stored_pressure', 'chemicals', 'manual', 'pinch']),
    ('wtp_cartridge', 'A cartridge filter\'s cartridges changed', ['stored_pressure', 'chemicals', 'manual']),
    ('analyser', 'A water analyser calibrated', ['chemicals', 'process_trip', 'elec_shock']),
    ('scaffold', 'A scaffold built on a platform', ['height', 'dropped', 'manual', 'lifting']),
    ('painting', 'Pipework painted by running plant', ['fumes', 'flammable', 'noise', 'debris']),
]

# a work's job kind from its id (wo_ + the rest): the first pattern that matches, in this order
_PATTERNS = [
    ('_ir', 'elec_ir', 'end'), ('_rly', 'elec_relay', 'end'), ('gen1_cab', 'elec_cabinet', 'is'),
    ('_brg', 'motor_bearings', 'end'), ('_act', 'valve_actuator', 'end'), ('_ls', 'limit_switch', 'end'),
    ('_gbx', 'fan_gearbox', 'end'), ('_cy', 'vib_transmitter', 'end'), ('ct_lvl_thaw', 'level_thaw', 'is'),
    ('cond_p', 'transmitter', 'start'), ('ct_fan', 'fan_service', 'start'), ('gt1_filters', 'gt_filters', 'is'),
    ('hrsg1_lift_drive', 'lift_drive', 'is'), ('_resin', 'wtp_resin', 'end'), ('_membranes', 'wtp_membranes', 'end'),
    ('cart_', 'wtp_cartridge', 'start'), ('_cal', 'analyser', 'end'), ('scaffold_', 'scaffold', 'start'),
    ('paint_', 'painting', 'start'),
]


def job_of(work):
    """A work's job kind (REALISM.md §8.6): its `jsa`. An electrical work on a motor is its windings' check, a
    mechanical one its bearings'."""
    x = work['id'][3:]
    for pat, job, how in _PATTERNS:
        if how == 'is' and x == pat or how == 'end' and x.endswith(pat) or how == 'start' and x.startswith(pat):
            return job
    if x.endswith('_motor'):
        return 'elec_motor' if work['discipline'] == 'elec' else 'motor_bearings'
    raise KeyError(f'{work["id"]}: no job kind (tools/plant3d/train_hse.py)')


def hse():
    """data/plant3d/hse.json."""
    return {'format': FORMAT, 'version': 1,
            'controls': [{'id': i, 'title': t, 'source': s} for i, t, s in CONTROLS],
            'hazards': [{'id': i, 'title': t, 'controls': c, 'source': s} for i, t, c, s in HAZARDS],
            'jobs': [{'id': i, 'title': t, 'hazards': h} for i, t, h in JOBS]}
