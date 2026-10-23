"""The first train's control room screens (docs/PLANT3D.md §7.11): which systems each screen shows, where each system's
group stands on the screen's grid, the flow lines between the groups, the values trended on each screen and the
overview's key values. What a group shows is not listed here: it is every code of the model whose code begins with one
of the group's `codes` (the longest beginning wins), so the screens follow the model when it changes."""


def g(gid, title, at, codes, extra=None):
    out = {'id': gid, 'title': title, 'at': at, 'codes': codes}
    if extra:
        out['extra'] = extra
    return out


def ln(frm, to, medium=None):
    out = {'from': frm, 'to': to}
    if medium:
        out['medium'] = medium
    return out


MAIN = ['00CWA10', '00CWB10']      # the main control room's desks
WTP = ['00CWD10']                  # the water treatment plant's own desk (WATER-TREATMENT §7)


def screens():
    """The train's screens, worked from the main control room's desks, then the water treatment plant's: its
    overview is on every desk (the main control room reads it), the rest on the WTP's own desk only (PLANT3D §14:
    `desks`). Each screen says its desks: without them it would be on every desk."""
    out = train()
    for sc in out['screens']:
        sc['desks'] = list(MAIN)
    out['overview']['desks'] = list(MAIN)
    out['screens'] += wtp()
    out['version'] = 2
    return out


def wtp():
    return [
        {'id': 'wtp', 'short': 'WTP', 'title': 'Water treatment plant overview', 'desks': MAIN + WTP,
         'groups': [
             g('raw', 'Raw water: intake level and flow', [0, 0], ['00GAA10CL', '00GAC10']),
             g('clar', 'Clarified water', [1, 0], ['00GBD11CQ', '00GBD12CQ']),
             g('filt', 'Filtered water', [2, 0], ['00GBB10', '00QUG10']),
             g('perm', 'RO permeate', [2, 1], ['00GCB21CQ001', '00GCB22CQ001']),
             g('demin', 'Demineralised water', [1, 1], ['00GCF11CQ', '00GCF12CQ']),
             g('transfer', 'Transfer to the plant', [0, 1], ['00GHC10BR'])],
         'lines': [ln('raw', 'clar', 'raw_water'), ln('clar', 'filt', 'clarified_water'),
                   ln('filt', 'perm', 'filtered_water'), ln('perm', 'demin', 'permeate'),
                   ln('demin', 'transfer', 'demin_water')],
         'trend': ['wt_raw', 'cl_ntu', 'ft_lvl', 'dt_a_lvl', 'tr_q']},
        {'id': 'wtp_pre', 'short': 'Pretreatment', 'title': 'Intake, coagulation and clarifiers', 'desks': WTP,
         'groups': [
             g('intake', 'Intake: screens and raw water pumps', [0, 0], ['00GAA10', '00GAF10']),
             g('chlor', 'Pre-chlorination', [0, 1], ['00GBN30']),
             g('coag', 'Coagulant and polymer dosing', [1, 1], ['00GBN10', '00GBN20']),
             g('mix', 'Rapid mixer', [1, 0], ['00GBD10']),
             g('clar', 'Clarifiers', [2, 0], ['00GBD11', '00GBD12'])],
         'lines': [ln('intake', 'mix', 'raw_water'), ln('chlor', 'intake'), ln('coag', 'mix'),
                   ln('mix', 'clar', 'raw_water')],
         'trend': ['wt_raw', 'rw_lvl', 'cl_ntu', 'cg_dose']},
        {'id': 'wtp_filters', 'short': 'Filters', 'title': 'Gravity filters, backwash and filtered water',
         'desks': WTP,
         'groups': [g(f'f{i}', f'Filter {i}', [(i - 1) % 3, (i - 1) // 3], [f'00GBB1{i}']) for i in range(1, 7)] + [
             g('bw', 'Backwash pumps and air scour blowers', [3, 0], ['00GBR10']),
             g('tank', 'Filtered water tank', [3, 1], ['00GBL10']),
             g('mk', 'Cooling tower makeup pumps', [4, 0], ['00GHB10']),
             g('sw', 'Service water pumps (RO feed)', [4, 1], ['00GHA10'])],
         'lines': [ln('bw', 'f3'), ln('f6', 'tank', 'filtered_water'), ln('tank', 'mk', 'filtered_water'),
                   ln('tank', 'sw', 'filtered_water')],
         'trend': ['ft_lvl', 'fl_ntu', 'fl1_hl', 'ct_mk_flow']},
        {'id': 'wtp_ro', 'short': 'RO', 'title': 'Dechlorination, cartridge filters and reverse osmosis', 'desks': WTP,
         'groups': [
             g('chem', 'Bisulphite, antiscalant and acid dosing', [0, 0], ['00GCN10', '00GCN20', '00GCE10']),
             g('cfa', 'Cartridge filter A', [1, 0], ['00GCB11']),
             g('cfb', 'Cartridge filter B', [1, 1], ['00GCB12']),
             g('roa', 'RO train A', [2, 0], ['00GCB21']),
             g('rob', 'RO train B', [2, 1], ['00GCB22']),
             g('dg', 'Degasser and degassed water tank', [3, 0], ['00GCH10', '00GCK10BB']),
             g('cip', 'Cleaning (CIP) skid', [3, 1], ['00GCB30'])],
         'lines': [ln('chem', 'cfa'), ln('cfa', 'roa', 'filtered_water'), ln('cfb', 'rob', 'filtered_water'),
                   ln('roa', 'dg', 'permeate'), ln('rob', 'dg', 'permeate'), ln('cip', 'rob')],
         'trend': ['ro_a_p', 'ro_a_cond', 'ro_a_orp', 'ro_a_suct', 'dg_lvl']},
        {'id': 'wtp_demin', 'short': 'Demin', 'title': 'Mixed beds, demineralised water and transfer', 'desks': WTP,
         'groups': [
             g('feed', 'Mixed bed feed pumps', [0, 0], ['00GCK10AP']),
             g('mba', 'Mixed bed A', [1, 0], ['00GCF11']),
             g('mbb', 'Mixed bed B', [1, 1], ['00GCF12']),
             g('tanks', 'Demineralised water tanks', [2, 0], ['00GCL10']),
             g('transfer', 'Transfer pumps', [3, 0], ['00GHC10']),
             g('regen', 'Regeneration: acid and caustic tanks, resin mixing blower', [0, 1], ['00GCP'])],
         'lines': [ln('feed', 'mba', 'permeate'), ln('feed', 'mbb', 'permeate'), ln('mba', 'tanks', 'demin_water'),
                   ln('regen', 'mbb'),
                   ln('mbb', 'tanks', 'demin_water'), ln('tanks', 'transfer', 'demin_water')],
         'trend': ['mb_a_cond', 'mb_a_si', 'dt_a_lvl', 'tr_q']},
        {'id': 'wtp_waste', 'short': 'Wastes', 'title': 'Neutralisation pit and sludge', 'desks': WTP,
         'groups': [
             g('pit', 'Neutralisation pit', [0, 0], ['00GNR10']),
             g('pitdose', 'Pit acid and caustic dosing', [0, 1], ['00GNR20', '00GNR30']),
             g('th', 'Sludge thickener', [1, 0], ['00GBS10']),
             g('press', 'Filter press', [1, 1], ['00GBS20'])],
         'lines': [ln('th', 'press', 'waste_water'), ln('pitdose', 'pit')],
         'trend': ['nr_ph', 'nr_lvl', 'th_lvl']},
    ]


def train():
    return {
        'format': 'walkdown-plant-screens', 'version': 1,
        'overview': {'title': 'Train 1 overview', 'short': 'Overview',
                     'key': ['gt1_mw', 'st_mw', 'gt1_speed', 'st_speed', 'hp_p', 'hp_lvl', 'hp_steam_t', 'cond_p',
                             'hw_lvl', 'cw_flow', 'cw_cold_t', 'ia_p']},
        'screens': [
            {'id': 'gt', 'short': 'GT 1', 'title': 'Gas turbine 1 with lube oil and fuel gas',
             'groups': [
                 g('fuel', 'Fuel gas', [0, 0], ['10MBP10']),
                 g('lube', 'Lube oil', [0, 1], ['10MBV10']),
                 g('gt', 'Gas turbine and turning gear', [1, 0], ['10MBA10', '10MBK10', '10MBY10']),
                 g('flame', 'Combustion: flame detectors', [1, 1], ['10MBM10']),
                 g('exhaust', 'Exhaust temperatures', [2, 0], ['10MBR10']),
                 g('bearings', 'Bearing vibration', [2, 1], ['10MBD10'])],
             'lines': [ln('fuel', 'gt', 'fuel_gas'), ln('lube', 'bearings'), ln('gt', 'exhaust')],
             'trend': ['gt1_speed', 'gt1_exh_t', 'gt1_lube_p', 'gt1_oil_t']},
            {'id': 'hrsg', 'short': 'HRSG 1', 'title': 'HRSG 1 water and steam',
             'groups': [
                 g('lp', 'LP drum and deaerator', [0, 0], ['10HAD10']),
                 g('fw', 'Feedwater pumps', [0, 1], ['10LAC10']),
                 g('fwv', 'HP feedwater control', [1, 1], ['10LAB30']),
                 g('hp', 'HP drum', [1, 0], ['10HAD30']),
                 g('sh', 'HP superheater, spray and safety valve', [2, 0], ['10LBA30', '10LAE30']),
                 g('drains', 'HP drains and start-up vent', [2, 1], ['10HAN30'])],
             'lines': [ln('lp', 'fw', 'feedwater'), ln('fw', 'fwv', 'feedwater'), ln('fwv', 'hp', 'feedwater'),
                       ln('hp', 'sh', 'steam_hp'), ln('sh', 'drains', 'steam_hp')],
             'trend': ['hp_p', 'hp_lvl', 'hp_steam_t', 'lp_lvl']},
            {'id': 'st', 'short': 'ST', 'title': 'Steam turbine, condenser and vacuum',
             'groups': [
                 g('gland', 'Gland steam', [0, 0], ['30MAW10']),
                 g('lube', 'Lube and jacking oil', [0, 1], ['30MAV10', '30MAV20']),
                 g('st', 'Steam turbine and turning gear', [1, 0], ['30MAA10', '30MAB10', '30MAK10', '30MAY10']),
                 g('bearings', 'Bearings and axial position', [1, 1], ['30MAD10']),
                 g('bypass', 'HP and LP bypass', [2, 0], ['30MAN']),
                 g('cond', 'Condenser and vacuum pumps', [2, 1], ['30MAG10', '30MAJ10'])],
             'lines': [ln('gland', 'st', 'steam_aux'), ln('lube', 'bearings'), ln('st', 'cond', 'steam_lp'),
                       ln('bypass', 'cond', 'steam_lp')],
             'trend': ['st_speed', 'cond_p', 'st_inlet_t', 'st_casing_t']},
            {'id': 'condensate', 'short': 'Condensate', 'title': 'Condensate',
             'groups': [
                 g('hotwell', 'Hotwell', [0, 0], ['30MAG10CL']),
                 g('cep', 'Condensate extraction pumps', [1, 0], ['30LCB10']),
                 g('minflow', 'Minimum flow recirculation', [2, 0], ['30LCA10'])],
             'lines': [ln('hotwell', 'cep', 'condensate'), ln('cep', 'minflow', 'condensate')],
             'trend': ['hw_lvl']},
            {'id': 'cw', 'short': 'CW', 'title': 'Circulating water',
             'groups': [
                 g('pumps', 'Circulating water pumps and discharge valves', [0, 0], ['30PAC10']),
                 g('flow', 'Supply and return', [1, 0], ['30PAB'])],
             'lines': [ln('pumps', 'flow', 'cooling_water')],
             'trend': ['cw_flow', 'cw_ret_t']},
            {'id': 'ct', 'short': 'Cooling tower', 'title': 'Cooling tower',
             'groups': [
                 g('fans', 'Cooling tower fans', [0, 0], ['30PAD10AN', '30PAD10CY']),
                 g('basin', 'Basin and cold water', [1, 0], ['30PAD10']),
                 g('makeup', 'Makeup water', [1, 1], ['30PAR10'])],
             'lines': [ln('makeup', 'basin', 'raw_water')],
             'trend': ['cw_cold_t', 'ct_basin_level']},
            {'id': 'aux', 'short': 'Auxiliaries', 'title': 'Closed cooling water, instrument air, auxiliary steam',
             'groups': [
                 g('ccw', 'Closed cooling water pumps', [0, 0], ['00PGC10']),
                 g('cooler', 'Closed cooling water cooler', [1, 0], ['00PGB10']),
                 g('air', 'Instrument air', [0, 1], ['00QFA10', '00QFB10']),
                 g('aux', 'Auxiliary boiler', [1, 1], ['00QHA10']),
                 g('demin', 'Demineralised water tank (from the water treatment plant)', [2, 0], ['00GHC10BB'])],
             'lines': [ln('ccw', 'cooler', 'cooling_water')],
             'trend': ['ccw_t', 'ia_p', 'aux_p', 'dm_lvl']},
            {'id': 'el', 'short': 'Electrical', 'title': 'Electrical: generators, excitation and breakers',
             'groups': [
                 g('gen1', 'Generator 1 and excitation', [0, 0], ['10MKA10', '10MKC10'],
                   ['gt1_v', 'gt1_f', 'gt1_slip', 'gt1_ph']),
                 g('brk1', 'Generator 1 breaker', [1, 0], ['10BAC10']),
                 g('gen3', 'Generator 3 (steam turbine) and excitation', [0, 1], ['30MKA10', '30MKC10'],
                   ['st_v', 'st_f', 'st_slip', 'st_ph']),
                 g('brk3', 'Generator 3 breaker', [1, 1], ['30BAC10'])],
             'trend': ['gt1_mw', 'st_mw', 'gt1_ph', 'st_ph']},
        ],
        'left_out': [
            {'codes': ['30PAB10AA40'], 'why': 'Water box vents are hand valves without position feedback: they are '
                                              'worked and seen at the condenser'},
        ],
    }
