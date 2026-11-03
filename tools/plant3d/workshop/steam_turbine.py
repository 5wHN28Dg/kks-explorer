"""The steam turbine's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K4a): the words, materials, order and
sources of its component tree, for the plant's first instance of the kind, the HP turbine (one casing, its combined
stop and control valves on the sides). Its geometry is the kit's generator, apps/plant3d/kit/parts_machines.gd
`steam_turbine` and its `_st_*` helpers; the content build joins the two and refuses a kind whose halves disagree.
The scene is built with the instance's shaft line (`context`), so its coupling stands where it does in the plant.

Generic: a single-flow HP turbine as the public papers and manuals describe one; no plant data. The guided order
(`assembly`) is the reverse of the overhaul's take-apart in the Siemens/KWU procedure (insulation first; the bearing
caps, the thrust bearing and the coupling; the outer casing's joint and upper half; the upper inner casing and blade
carrier; the glands and upper journal bearings; the rotor lifted out; then the lower halves), with the blade carrier
inside the inner casing as GE's papers have the diaphragms inside the inner shell; its trial fits are left out. What
is simplified is listed in apps/plant3d/kit/README.md ("Workshop: the steam turbine"). No sizes, tools or torques
here: they belong to the realism programme's service file (WORKSHOP.md §4.4).
"""

GE_LARGE = 'ger3646'
GE_STAG = 'ger3582'
IMIA = 'imia_wgp42'
NAVY = 'navedtra14104'
NRC = 'nrc_w73'
KWU = 'kwu_overhaul'
PAT_COUPLING = 'us5257905'
PAT_SHELL = 'us5511941'
STAGES = 8

SOURCES = [
    {'id': GE_LARGE, 'cite': 'J. K. Reinker and P. B. Mason, Steam Turbines for Large Power Applications, GE Power '
                             'Systems GER-3646D: pp. 9-11 stages, balance piston, inner shells and their joint '
                             'flanges; p. 13 diaphragms in the inner shell, shells on the bearing '
                             'standards; p. 15 coupling bolts and joint studs',
     'url': 'https://www.docenti.unina.it/webdocenti-be/allegati/materiale-didattico/64409'},
    {'id': GE_STAG, 'cite': 'M. Boss, Steam Turbines for STAG Combined-Cycle Power Systems, GE Power Systems '
                            'GER-3582E (1996): p. 12 the thrust bearing in the front standard, near the HP stages; '
                            'pp. 16-17 combined stop and control valves piped to the lower casing; pp. 20-21 joint '
                            'flanges and packings',
     'url': 'https://www.slideshare.net/slideshow/steam-turbinesforcombinedcycle/6369564'},
    {'id': IMIA, 'cite': 'IMIA working group paper WGP 42 (05), Maintenance and Overhaul of Steam Turbines (2005): '
                         '2.A.2 rotors and their flange couplings; tables 8-9 overhaul tasks (the upper casings '
                         'removed, bearings opened, coupling bolts checked)',
     'url': 'https://www.imia.com/wp-content/uploads/2023/08/wgp4205-5.pdf'},
    {'id': NAVY, 'cite': 'US Navy, Fireman, NAVEDTRA 14104 (1992), chapter 5 Steam Turbines: casings, rotors, '
                         'radial and thrust bearings, labyrinth shaft packing glands',
     'url': 'https://tpub.com/fireman/43.htm'},
    {'id': NRC, 'cite': 'US NRC, Westinghouse Technology Systems Manual, section 7.3 Main Turbine, MSR and EHC '
                        '(a course copy): 7.3.2.1 steam chests with stop and governor valves each side, 7.3.2.2 '
                        'rotors forged, flanged rigid couplings',
     'url': 'https://assets.excelsior.edu/private/sbt/secure/NUC350/WManual/W07.3%20Turbine.htm'},
    {'id': KWU, 'cite': 'S. Rameshkumar, Turbine overhauling procedure (after the Siemens/KWU service manual, '
                        '2006): pp. 2-11 the take-apart order (insulation, bearing pedestal tops and thrust bearing, '
                        'uncoupling, outer casing, blade carrier and inner casing, glands, rotor, lower halves); '
                        'pp. 52-60 reassembly',
     'url': 'https://www.slideshare.net/slideshow/turbineoverhaulingprocedure-siemens-recommends-birkosit/9779663'},
    {'id': PAT_COUPLING, 'cite': 'US patent 5,257,905 (Westinghouse, 1993): flanges formed at the end of each rotor, '
                                 'joined by coupling bolts and nuts',
     'url': 'https://patents.google.com/patent/US5257905'},
    {'id': PAT_SHELL, 'cite': 'US patent 5,511,941 (1996), background: the shell bolts loosened before the upper '
                              'half shell is lifted',
     'url': 'https://patents.google.com/patent/US5511941'},
]

ORD = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth']


def comp(name, does, material, sources, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': sources}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def components():
    c = {
        'lagging_upper': comp('Lagging, upper half', 'Insulation and its sheet-metal cladding over the upper casing: '
                              'keeps the heat in and the outside safe to touch. The first thing off in an overhaul.',
                              'Mineral wool under aluminium sheet', [KWU]),
        'lagging_lower': comp('Lagging, lower half', 'Insulation and cladding round the lower casing.',
                              'Mineral wool under aluminium sheet', [KWU]),
        'casing_lower': comp('Outer casing, lower half', 'Holds the steam; rests on the bearing pedestals and carries '
                             'the inner casing. Its flanges meet the upper half at the horizontal joint.',
                             'Cast alloy steel', [GE_LARGE]),
        'casing_upper': comp('Outer casing, upper half', 'Bolted to the lower half at the horizontal joint; lifted '
                             'off to open the turbine.', 'Cast alloy steel', [GE_LARGE, KWU]),
        'inner_lower': comp('Inner casing, lower half', 'A second shell inside the outer one: takes the inlet '
                            'steam\'s full pressure and carries the blade carriers.', 'Cast alloy steel',
                            [GE_LARGE]),
        'inner_upper': comp('Inner casing, upper half', 'Bolted to the lower half through its own joint flanges.',
                            'Cast alloy steel', [GE_LARGE, KWU]),
        'carrier_lower': comp('Blade carrier, lower half', 'Holds the lower halves of the stationary blade rows in '
                              'the inner casing.', 'Alloy steel', [GE_LARGE, KWU],
                              'The stationary blades are fixed in the carrier\'s grooves: in an overhaul the carrier '
                              'comes out with them, and they are renewed only in a shop.'),
        'carrier_upper': comp('Blade carrier, upper half', 'Holds the upper halves of the stationary blade rows.',
                              'Alloy steel', [GE_LARGE, KWU],
                              'The stationary blades are fixed in the carrier\'s grooves: in an overhaul the carrier '
                              'comes out with them, and they are renewed only in a shop.'),
        'glands_lower': comp('Shaft glands, lower halves', 'Labyrinth seals where the shaft leaves the casing at '
                             'each end: they keep steam in and air out.', 'Alloy steel, labyrinth strips',
                             [NAVY, KWU]),
        'glands_upper': comp('Shaft glands, upper halves', 'The upper halves of the labyrinth seals at both ends.',
                             'Alloy steel, labyrinth strips', [NAVY, KWU]),
        'rotor': comp('Rotor', 'Forged in one piece with its blade rows, balance piston, thrust collar and coupling '
                      'flange; turns in the journal bearings and drives the next rotor along the shaft line.',
                      'Forged alloy steel', [NAVY, NRC, GE_LARGE],
                      'The rotor is lifted out and set back as one piece: its blades are renewed only in a shop, '
                      'and the rotor balanced again.'),
        'collar': comp('Thrust collar', 'A disc on the rotor between the thrust bearing\'s pads: it holds the rotor '
                       'in place along its axis against the steam\'s push (simplified).', 'Forged alloy steel',
                       [NAVY, GE_STAG]),
        'pedestal_f': comp('Front bearing pedestal', 'Stands on the foundation and carries the front journal '
                           'bearing and the thrust bearing; the casing rests on it.', 'Cast iron, painted',
                           [GE_LARGE, GE_STAG]),
        'cap_f': comp('Front pedestal cover', 'Closes the front pedestal over its bearings; lifted off first to '
                      'reach them.', 'Steel plate, painted', [KWU]),
        'brg_f_lower': comp('Front journal bearing, lower half', 'Carries the rotor\'s weight on an oil film.',
                            'Steel shell, white metal lining', [NAVY, KWU]),
        'brg_f_upper': comp('Front journal bearing, upper half', 'Closes the bearing over the journal.',
                            'Steel shell, white metal lining', [NAVY, KWU]),
        'thrust_lower': comp('Thrust bearing, lower half', 'Pads on both faces of the thrust collar keep the rotor '
                             'in its place along the axis; this half rolls in under the collar (simplified).',
                             'Steel pads, white metal faces', [NAVY, GE_STAG, KWU]),
        'thrust_upper': comp('Thrust bearing, upper half', 'The upper pads on both faces of the thrust collar '
                             '(simplified).', 'Steel pads, white metal faces', [NAVY, GE_STAG, KWU]),
        'pedestal_r': comp('Rear bearing pedestal', 'Carries the rear journal bearing; the casing\'s rear end '
                           'rests on it.', 'Cast iron, painted', [GE_LARGE]),
        'cap_r': comp('Rear pedestal cover', 'Closes the rear pedestal over its bearing.', 'Steel plate, painted',
                      [KWU]),
        'brg_r_lower': comp('Rear journal bearing, lower half', 'Carries the rotor\'s weight on an oil film.',
                            'Steel shell, white metal lining', [NAVY, KWU]),
        'brg_r_upper': comp('Rear journal bearing, upper half', 'Closes the bearing over the journal.',
                            'Steel shell, white metal lining', [NAVY, KWU]),
    }
    for side, word in (('l', 'left'), ('r', 'right')):
        c['valve_' + side] = comp(f'Stop and control valve, {word}', 'The combined valve chest on this side of the '
                                  'casing: live steam passes its stop valve, then its control valve, into the '
                                  'casing.', 'Cast alloy steel body under lagging', [GE_STAG, NRC])
        c['stop_' + side] = comp(f'Stop valve disc, {word}', 'Shuts off the steam at once when the turbine trips.',
                                 'Alloy steel', [GE_STAG, NRC])
        c['ctrl_' + side] = comp(f'Control valve plug, {word}', 'Opens as far as the governor asks: it sets how '
                                 'much steam goes to the blades.', 'Alloy steel', [GE_STAG, NRC])
        c['servo_' + side] = comp(f'Valve actuator, {word}', 'The hydraulic servomotor that moves the valve: oil '
                                  'pressure opens it, a spring closes it.', 'Steel, painted', [GE_STAG])
    for k in range(STAGES):
        n = ORD[k]

        c[f'srow_u{k + 1}'] = comp(f'Stage {k + 1} stationary blades, upper', f'The {n} stage\'s fixed blades: they '
                                   'speed the steam up and turn it onto the moving blades.', 'Stainless steel',
                                   [GE_LARGE, NAVY])
        c[f'srow_l{k + 1}'] = comp(f'Stage {k + 1} stationary blades, lower', f'The lower half of the {n} stage\'s '
                                   'fixed blades.', 'Stainless steel', [GE_LARGE, NAVY])
        c[f'mrow_{k + 1}'] = comp(f'Stage {k + 1} moving blades', f'The {n} stage\'s blades on the rotor: the steam '
                                  'pushes them round. They lengthen stage by stage as the steam expands.',
                                  'Stainless steel', [GE_LARGE, NAVY])

    return c


def step(place, text, needs=(), why=None, sources=(KWU,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


def assembly():
    a = [
        step('pedestal_f', 'Set the front bearing pedestal on the foundation.', sources=(GE_LARGE,)),
        step('pedestal_r', 'Set the rear bearing pedestal on the foundation.', sources=(GE_LARGE,)),
        step('casing_lower', 'Lower the outer casing\'s lower half onto the pedestals and line it up with the shaft '
             'line.', [('pedestal_f', 'The casing rests on the front pedestal: set it first.',
                        'Lift the lower casing off before the front pedestal is moved.'),
                       ('pedestal_r', 'The casing rests on the rear pedestal: set it first.',
                        'Lift the lower casing off before the rear pedestal is moved.')], sources=(GE_LARGE,)),
    ]
    for side, word in (('l', 'left'), ('r', 'right')):
        v = 'valve_' + side
        a += [
            step(v, f'Set the {word} stop and control valve beside the casing and connect it to the lower half.',
                 [('casing_lower', 'The valve\'s steam lead goes into the lower casing: set the casing first.',
                   'Disconnect the valve before the lower casing is lifted.')], sources=(GE_STAG,)),
            step('stop_' + side, f'Fit the {word} stop valve disc and its stem in the chest.',
                 [(v, 'The disc goes inside the valve chest: set the chest first.',
                   'Take the stop valve disc out before the chest is moved.')], sources=(GE_STAG,)),
            step('ctrl_' + side, f'Fit the {word} control valve plug and its stem in the chest, above the stop valve.',
                 [(v, 'The plug goes inside the valve chest: set the chest first.',
                   'Take the control valve plug out before the chest is moved.'),
                  ('stop_' + side, 'The stop valve sits below the control valve: fit its disc first.',
                   'Take the control valve plug out before the stop valve disc, which lies below it.')],
                 sources=(GE_STAG,)),
            step('servo_' + side, f'Mount the {word} valve actuator on the chest and couple it to the stems.',
                 [('stop_' + side, 'Fit the stop valve disc before the actuator closes the chest.',
                   'Take the actuator off before the stop valve disc.'),
                  ('ctrl_' + side, 'Fit the control valve plug before the actuator closes the chest.',
                   'Take the actuator off before the control valve plug.')], sources=(GE_STAG,)),
        ]
    a += [
        step('inner_lower', 'Lower the inner casing\'s lower half into the outer casing.',
             [('casing_lower', 'The inner casing sits in the outer casing\'s lower half: set that first.',
               'Lift the lower inner casing out before the outer casing\'s lower half is moved.')]),
        step('carrier_lower', 'Lower the blade carrier\'s lower half into the inner casing.',
             [('inner_lower', 'The blade carrier sits in the inner casing: set the lower inner casing first.',
               'Lift the lower blade carrier out before the lower inner casing.')]),
    ]
    for k in range(STAGES):
        a.append(step(f'srow_l{k + 1}', f'Stage {k + 1}\'s lower stationary blades come with the blade carrier.',
                      sources=(GE_LARGE,)))
    a += [
        step('glands_lower', 'Fit the lower halves of the shaft glands at both ends of the casing.',
             [('casing_lower', 'The glands sit in the lower casing\'s ends: set the casing first.',
               'Take the lower glands out before the lower casing is lifted.')]),
        step('brg_f_lower', 'Roll the front journal bearing\'s lower half into the front pedestal.',
             [('pedestal_f', 'The bearing sits in the front pedestal: set the pedestal first.',
               'Roll the lower front bearing out before the pedestal is moved.')]),
        step('brg_r_lower', 'Roll the rear journal bearing\'s lower half into the rear pedestal.',
             [('pedestal_r', 'The bearing sits in the rear pedestal: set the pedestal first.',
               'Roll the lower rear bearing out before the pedestal is moved.')]),
        step('rotor', 'Lower the rotor level onto the lower journal bearings, clear of the blades and glands.',
             [('brg_f_lower', 'The rotor rests on the journal bearings: roll the lower front bearing in first.',
               'Lift the rotor out before the lower front bearing comes out.'),
              ('brg_r_lower', 'The rotor rests on the journal bearings: roll the lower rear bearing in first.',
               'Lift the rotor out before the lower rear bearing comes out.'),
              ('carrier_lower', 'Set the lower blade carrier before the rotor: it cannot go in under the blades.',
               'Lift the rotor out before the lower blade carrier.'),
              ('glands_lower', 'Fit the lower glands before the rotor: they go in under the shaft.',
               'Lift the rotor out before the lower glands.')],
             why='A rotor set down off level or touched against the blades bends blades and scores seals.'),
    ]
    for k in range(STAGES):
        a.append(step(f'mrow_{k + 1}', f'Stage {k + 1}\'s moving blades come with the rotor.', sources=(GE_LARGE,)))
    a += [
        step('collar', 'The thrust collar is part of the rotor.', sources=(GE_STAG,)),
        step('brg_f_upper', 'Close the front journal bearing with its upper half.',
             [('rotor', 'The upper half closes over the rotor\'s journal: set the rotor first.',
               'Take the upper front bearing off before the rotor is lifted.')]),
        step('brg_r_upper', 'Close the rear journal bearing with its upper half.',
             [('rotor', 'The upper half closes over the rotor\'s journal: set the rotor first.',
               'Take the upper rear bearing off before the rotor is lifted.')]),
        step('glands_upper', 'Fit the upper halves of the shaft glands over the shaft.',
             [('rotor', 'The upper glands close over the shaft: set the rotor first.',
               'Take the upper glands off before the rotor is lifted.')]),
        step('carrier_upper', 'Lower the blade carrier\'s upper half over the rotor onto the lower half.',
             [('rotor', 'The upper carrier\'s blades fit between the rotor\'s: set the rotor first.',
               'Lift the upper blade carrier off before the rotor.'),
              ('carrier_lower', 'The upper carrier sits on the lower one: set that first.',
               'Lift the upper blade carrier off before the lower one.')]),
    ]
    for k in range(STAGES):
        a.append(step(f'srow_u{k + 1}', f'Stage {k + 1}\'s upper stationary blades come with the blade carrier.',
                      sources=(GE_LARGE,)))
    a += [
        step('inner_upper', 'Lower the inner casing\'s upper half onto the lower half.',
             [('carrier_upper', 'The upper inner casing closes over the blade carrier: set the upper carrier first.',
               'Lift the upper inner casing off before the upper blade carrier.'),
              ('inner_lower', 'The upper inner casing sits on the lower one: set that first.',
               'Lift the upper inner casing off before the lower one.')]),
        step('inner_bolts', 'Fit the inner casing\'s joint studs and tighten their nuts.',
             [('inner_upper', 'The studs go through both halves\' flanges: set the upper inner casing first.',
               'Take the inner casing\'s studs out before its upper half is lifted.')], sources=(KWU, GE_LARGE)),
        step('casing_upper', 'Lower the outer casing\'s upper half onto the joint on its guide pins.',
             [('inner_upper', 'Close the inner casing before the outer casing: set the upper inner casing first.',
               'Lift the upper outer casing off before the upper inner casing.'),
              ('inner_bolts', 'Tighten the inner casing\'s studs before the outer casing closes over them.',
               'Lift the upper outer casing off before the inner casing\'s studs come out.'),
              ('glands_upper', 'Fit the upper glands before the outer casing closes over them.',
               'Lift the upper outer casing off before the upper glands.'),
              ('casing_lower', 'The upper half sits on the lower half\'s flanges: set the lower half first.',
               'Lift the upper outer casing off before the lower half.')],
             why='Jacking screws take the upper half the first few millimetres off the joint, square, so it does not '
                 'bind on its guide pins.'),
        step('joint_bolts', 'Fit the horizontal joint\'s studs and tighten their nuts in the casing maker\'s order.',
             [('casing_upper', 'The studs hold the two halves of the joint: set the upper casing first.',
               'Loosen and take out all the joint\'s studs before the upper casing is lifted.')],
             sources=(KWU, PAT_SHELL, GE_LARGE)),
        step('coupling_bolts', 'Couple the rotor to the next one: line the flanges up and fit the coupling bolts.',
             [('rotor', 'The bolts join the rotor\'s coupling flange to the next rotor\'s: set the rotor first.',
               'Take the coupling bolts out, uncoupling the rotors, before the rotor is lifted.')],
             why='The rotors are lined up before coupling; coupled out of line they shake the bearings.',
             sources=(KWU, PAT_COUPLING, IMIA)),
        step('thrust_lower', 'Roll the thrust bearing\'s lower half in under the thrust collar, its pads on both '
             'faces.', [('rotor', 'The pads go on the faces of the rotor\'s thrust collar: set the rotor first.',
                         'Roll the lower thrust bearing out before the rotor is lifted.')], sources=(KWU, GE_STAG)),
        step('thrust_upper', 'Close the thrust bearing with its upper half.',
             [('thrust_lower', 'The upper half closes on the lower one: roll the lower half in first.',
               'Take the upper thrust bearing off before the lower half is rolled out.')], sources=(KWU, GE_STAG)),
        step('cap_f', 'Close the front pedestal with its cover.',
             [('brg_f_upper', 'Close the front journal bearing before the cover goes on.',
               'Take the front pedestal\'s cover off before the upper front bearing.'),
              ('thrust_upper', 'Fit the thrust bearing before the cover goes on.',
               'Take the front pedestal\'s cover off before the thrust bearing.')]),
        step('cap_r', 'Close the rear pedestal with its cover.',
             [('brg_r_upper', 'Close the rear journal bearing before the cover goes on.',
               'Take the rear pedestal\'s cover off before the upper rear bearing.')]),
        step('lagging_lower', 'Put the lower half\'s insulation and cladding back.',
             [('casing_lower', 'The lagging covers the lower casing: set it first.',
               'Strip the lower lagging before the lower casing is moved.')]),
        step('lagging_upper', 'Put the upper half\'s insulation and cladding back, the last thing on.',
             [('casing_upper', 'The lagging covers the upper casing: close the casing first.',
               'Strip the upper lagging first: it covers the casing\'s joint and its studs.'),
              ('joint_bolts', 'Tighten the joint\'s studs before they are lagged over.',
               'Strip the upper lagging before the joint\'s studs are loosened.')]),
    ]
    return a


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'steam_turbine',
        'context': ['axis_z', 'shaft_lo', 'shaft_hi'],
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'joint_bolts': {'name': '44 horizontal joint studs and nuts', 'joins': ['casing_upper', 'casing_lower'],
                            'sources': [GE_LARGE, KWU, PAT_SHELL]},
            'inner_bolts': {'name': '12 inner casing joint studs and nuts', 'joins': ['inner_upper', 'inner_lower'],
                            'sources': [GE_LARGE, KWU]},
            'coupling_bolts': {'name': '12 coupling bolts', 'joins': ['rotor'],
                               'beyond': 'the next turbine\'s rotor (its own machine)',
                               'sources': [PAT_COUPLING, IMIA, KWU]},
        },
        'assembly': assembly(),
        # the views (WORKSHOP.md §4.7): the X-ray takes the shells round the blade path; the cutaway opens the upper
        # quarter on the right (+x), the rotor and its blades shown whole; the turbine runs only closed
        'views': {'xray_all': ['lagging_upper', 'lagging_lower', 'casing_upper', 'casing_lower', 'inner_upper',
                               'inner_lower', 'carrier_upper', 'carrier_lower', 'cap_f', 'cap_r'],
                  'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}, {'normal': [0, 0, 1], 'offset': 0}],
                              'keep': ['rotor'] + [f'mrow_{k + 1}' for k in range(STAGES)] + ['collar']},
                  'run_exploded': {'allowed': ['lagging_upper', 'lagging_lower'],
                                   'why': 'A steam turbine runs only closed: the casing holds the steam and the '
                                          'bearings the rotor. Put it back together first (the lagging may stay '
                                          'off).'}},
    }


# ------------------------------------------------------------------ the bench (WORKSHOP.md §6, milestone K4b)
# The HP turbine run on its bench: steam at the stop valves (pressure and temperature, the sliders) through the stop and
# control valves into the first stage and on through the eight, the pressure and the temperature falling stage by stage
# to the exhaust; the rotor rolled, soaked, run up through its critical speeds, synchronised and loaded, and tripped, by
# the plant's own start-up sequence, trips, alarms and the values they read (make_bench.py takes them from the
# generated st model: never copied here). The bench gives what the plant's other areas would: the steam (the HRSG's), the
# lube oil, the condenser's vacuum, the cooling water, the grid. Generic: no plant data.
NRC_EHC = 'nrc_w73_ehc'
NIST = 'nistir5078'
SOURCES_BENCH = [
    {'id': NRC_EHC, 'cite': 'US NRC, Westinghouse Technology Systems Manual, section 7.3 Main Turbine, MSR and EHC '
                            '(a course copy): 7.3.2 the steam from the inlet chambers through the impulse stage and '
                            'the reaction blading, the impulse stage pressure as the measure of the load; 7.3.3.1 speed '
                            'control from turning gear to synchronous speed, then load once the breaker closes; '
                            '7.3.3.2 the trips (overspeed, thrust bearing, low bearing oil pressure)',
     'url': 'https://assets.excelsior.edu/private/sbt/secure/NUC350/WManual/W07.3%20Turbine.htm'},
    {'id': NAVY, 'cite': 'US Navy, Fireman, NAVEDTRA 14104 (1992), chapter 5 Steam Turbines, the impulse principle: '
                         'the nozzles turn the steam\'s energy into velocity, the blades take it, row after row',
     'url': 'https://tpub.com/fireman/42.htm'},
    {'id': NIST, 'cite': 'A. H. Harvey, Thermodynamic Properties of Water: Tabulation from the IAPWS Formulation 1995 '
                         'for the Thermodynamic Properties of Ordinary Water Substance for General and Scientific Use, '
                         'NISTIR 5078, table 2 (saturation by pressure): the saturation temperatures',
     'url': 'https://www.nist.gov/document/nistir5078-tab2pdf'},
    {'id': GE_STAG, 'cite': 'M. Boss, Steam Turbines for STAG Combined-Cycle Power Systems, GE Power Systems '
                            'GER-3582E (1996): the combined stop and control valves ahead of the HP section',
     'url': 'https://www.slideshare.net/slideshow/steam-turbinesforcombinedcycle/6369564'},
]
RATED_FLOW = 70.0       # kg/s through the HP turbine at full load (the plant's: st_mw_sp's table)
P_FIRST = 90.0          # bar after the control valves at full flow (the first stage's inlet)
P_EXHAUST = 25.0        # bar at the exhaust at full flow (cold reheat)
EXPONENT = 0.2          # T2/T1 = (p2/p1)^n: steam's (k - 1)/k with the stages' efficiency
BLADES = 34             # each moving row's blades (kit/parts_machines.gd _st_rotor): the blade-pass tone at 50 rev/s
# the saturation temperature by pressure (bar, °C), NISTIR 5078 table 2
TSAT = [[1, 99.6], [5, 151.8], [10, 179.9], [20, 212.4], [40, 250.4], [60, 275.6], [80, 295.0], [100, 311.0],
        [120, 324.7], [140, 336.7]]

# what the bench takes from the plant's st model (WORKSHOP.md §6.3)
TAKE_VALUES = (
    # the start-up sequence's states and conditions, the governor and the rotor's speed
    ['st_speed_sp', 'st_adm', 'st_bias', 'st_exc_cmd', 'st_brk_cmd', 'st_gov_fault', 'st_thrust_fault',
     'st_vib_fault', 'st_speed', 'st_still', 'st_slow', 'st_in_soak_ge', 'st_in_soak_le', 'st_in_soak',
     'st_in_fsnl_ge', 'st_in_fsnl_le', 'st_in_fsnl', 'st_in_loaded_ge', 'st_in_loaded_le', 'st_in_loaded',
     'st_in_hold_ge', 'st_in_hold_le', 'st_in_hold', 'st_nhold', 'st_roll_flow', 'st_flow_a', 'st_flow_l',
     'st_flow_t', 'st_flow_t2', 'st_flow', 'st_gov', 'st_sp_eff', 'st_tg_spd', 'st_free', 'st_tgt', 'st_err',
     'st_acc0', 'st_acc', 'st_rpm', 'st_os', 'st_at_800', 'st_at_3000', 'st_soak_t', 'st_soak_done',
     # the lube oil's three pressure switches, two out of three trip
     'st_lp_1', 'st_lp_1_l', 'st_lp_1_ll', 'st_lp_2', 'st_lp_2_l', 'st_lp_2_ll', 'st_lp_3', 'st_lp_3_l', 'st_lp_3_ll',
     'st_lp_llv', 'st_lp_ll', 'st_lube_ok', 'st_lp_low',
     # vibration through the critical speeds, axial displacement, the steam's superheat, the casing's warmth
     'st_band_lo', 'st_band_hi', 'st_inband', 'st_band_t', 'st_vib_base', 'st_vib_hold', 'st_vib_f', 'st_vib'] +
    [f'st_vib{k}{s}' for k in range(1, 9) for s in ('', '_h', '_hh')] +
    ['st_vib_hh', 'st_axial', 'st_axial_hh', 'st_inlet_t', 'st_superheat', 'st_sh_ok', 'st_sh_low',
     'st_sh_wet', 'st_wet_c', 'st_cas_hot', 'st_cas_idle', 'st_cas_tgt', 'st_cas_steam', 'st_cas_k', 'st_casing_t',
     'st_cas_gap', 'st_cas_rate', 'st_mismatch', 'st_mm_hi', 'st_mm_lo', 'st_match', 'st_p_ok',
     'st_run_ge2', 'st_run_le2', 'st_rolling', 'st_sh_alarm_c',
     # the generator's excitation and the synchronising check, the load
     'st_v_sp', 'st_v', 'st_f', 'st_slip', 'st_slip_deg', 'st_phase', 'st_ph', 'st_ph_abs', 'st_ph_ok',
     'st_slip_abs', 'st_slip_ok', 'st_v_dev', 'st_v_ok', 'st_spd95', 'st_brk_open', 'st_mw_sp', 'st_mw_t', 'st_mw',
     'gen3_prot_c'])
TRIPS = ['st_trip_lube', 'st_trip_os', 'st_trip_axial', 'st_trip_vib', 'st_trip_steam_t']
BREAKER_TRIP = 'gen3_trip_prot'     # the breaker opened by the turbine's protection (else the grid holds a tripped rotor)
ALARMS = ['st_lp1_low', 'st_vib1_h', 'st_os1', 'st_sh_low']


def _stage_values():
    """The steam path (the bench's own: the plant's st model has one flow, not its stages). With the downstream a
    turbine too (the reheater and the IP), every stage's pressure is proportional to the flow (the impulse stage's
    pressure is the load's measure, NRC 7.3.2): the first stage's inlet P_FIRST and the exhaust P_EXHAUST at full flow,
    an equal pressure ratio across each of the eight stages, never below the condenser's (the casing drained to it at
    standstill). The steam's temperature falls with its pressure, T2/T1 = (p2/p1)^n (absolute temperatures); with no
    steam flowing each stage's temperature is the casing's."""
    r = (P_EXHAUST / P_FIRST) ** (1.0 / STAGES)
    v = [
        ['flow_frac', {'product': ['flow', round(1.0 / RATED_FLOW, 9)]}],
        ['p_floor', {'product': ['cond_p', 0.01], 'unit': 'bar'}],
        ['steaming', {'cmp': ['flow', '>', 0.5]}],
        ['inlet_k', {'sum': ['inlet_t', 273.15], 'unit': 'K'}],
        # the stop valves open at once and shut in a fraction of a second; the control valves follow the flow
        ['stop_pos', {'ramp': 'adm', 'rate': 2, 'rate_down': 10, 'unit': 'pu'}],
        ['ctrl_tgt', {'min': ['flow_frac', 1]}],                # (past full flow the valves are wide open)
        ['ctrl_pos', {'lag': 'ctrl_tgt', 'tau': 0.5, 'unit': 'pu'}],
        ['p_first_f', {'product': ['flow_frac', P_FIRST]}],
        ['p_first0', {'max': ['p_first_f', 'p_floor']}],
        ['p_first', {'min': ['p_first0', 'p_supply'], 'unit': 'bar'}],
    ]
    for k in range(1, STAGES + 1):
        pk = round(P_FIRST * r ** k, 6)
        ck = round(r ** (k * EXPONENT), 9)
        v += [
            [f'p{k}_f', {'product': ['flow_frac', pk]}],
            [f'p{k}_c', {'min': [f'p{k}_f', 'p_first']}],          # (never above the first stage: the flow lags)
            [f'p{k}', {'max': [f'p{k}_c', 'p_floor'], 'unit': 'bar'}],
            [f't{k}_k', {'product': ['inlet_k', ck]}],
            [f't{k}_s', {'sum': [f't{k}_k', -273.15]}],
            [f't{k}_tgt', {'select': 'steaming', 'cases': ['casing_t', f't{k}_s']}],
            [f't{k}', {'lag': f't{k}_tgt', 'tau': 10, 'init': 35, 'unit': '°C'}],
        ]
    return v


def bench_source():
    """The turbine's bench source for make_bench.py (WORKSHOP.md §6.3)."""
    before = [
        # the steam at the stop valves (the sliders) and what the HRSG would give through them
        ['p_supply', {'state': 100, 'unit': 'bar'}],
        ['t_set', {'state': 500, 'unit': '°C'}],
        ['t_dip', {'state': 0}],                                 # the fault: the steam's temperature falls 200 K
        ['dip_k', {'product': ['t_dip', 200]}],
        ['steam_t', {'diff': ['t_set', 'dip_k'], 'unit': '°C'}],
        ['tsat', {'of': 'p_supply', 'table': TSAT, 'unit': '°C'}],
        ['steam_avail', {'of': 'p_supply', 'table': [[0, 0], [100, RATED_FLOW], [130, RATED_FLOW * 1.3]],
                         'unit': 'kg/s'}],
        # the bench's lube oil: its pump's pressure, lost with the fault
        ['lube_fail', {'state': 0}],
        ['lube_sp', {'select': 'lube_fail', 'cases': [2.5, 0.4]}],
        ['lube_p', {'lag': 'lube_sp', 'tau': 3, 'unit': 'bar'}],
        ['lube_sup', {'state': 0}],                              # (the oil system is in service from the start)
        # the thrust bearing's wear: the rotor creeps axially while the fault stands, and is back in place once the
        # bearing is renewed (the repair; the plant's wear only grows, which on the bench would latch its trip for good)
        ['ax_rate', {'select': 'thrust_fault', 'cases': [-0.1, 0.02]}],
        ['ax_w', {'integrate': 'ax_rate', 'gain': 1, 'min': 0, 'max': 2, 'init': 0, 'unit': 'mm'}],
        # the turning gear is engaged whenever the rotor is slow with oil on the bearings; the rotor is straight
        ['tg_run', {'and': ['lube_ok', 'slow']}],
        ['ecc_ok', {'state': 1}],
        # the condenser under the exhaust, the grid, the cooling water, the air; no casing warm-up valve on the bench
        ['cond_p', {'state': 6, 'unit': 'kPa(a)'}],
        ['vac_ok', {'cmp': ['cond_p', '<', 12]}],
        ['grid_frequency', {'state': 50, 'unit': 'Hz'}],
        ['grid_pu', {'product': ['grid_frequency', 0.02]}],
        ['ambient_t', {'state': 30, 'unit': '°C'}],
        ['warm_on', {'state': 0}],
        ['warm_shut', {'state': 1}],
    ]
    after = [
        # the trips the bench takes (the plant's st_any_trip reads two more: the condenser's and the oil cooler's)
        # (with the breaker's: left latched it would not open the breaker at the next trip on load)
        ['any_trip', {'or': [n.replace('st_', '', 1) + '_latched' for n in TRIPS] + ['trip_breaker_latched']}],
        ['trips_clear', {'not': 'any_trip'}],
    ] + _stage_values()
    sid = {f'srow_{h}{k}': k for k in range(1, STAGES + 1) for h in 'ul'}
    bind = [{'at': 'rotor', 'anim': 'shaft', 'of': 'speed', 'scale': 50}]
    for s in ('l', 'r'):
        bind += [{'at': f'stop_{s}', 'anim': f'stop_{s}', 'of': 'stop_pos'},
                 {'at': f'ctrl_{s}', 'anim': f'ctrl_{s}', 'of': 'ctrl_pos'}]
    for c, k in list(sid.items()) + [(f'mrow_{k}', k) for k in range(1, STAGES + 1)]:
        bind += [{'at': c, 'heat': f't{k}'}, {'at': c, 'pressure': f'p{k}'}]
    for c in ('inner_upper', 'inner_lower', 'carrier_upper', 'carrier_lower'):
        bind += [{'at': c, 'heat': 'casing_t'}, {'at': c, 'pressure': 'p_first'}]
    for s in ('l', 'r'):
        bind += [{'at': f'valve_{s}', 'heat': 'steam_t'}, {'at': f'valve_{s}', 'pressure': 'p_supply'}]
    for s in ('l', 'r'):
        bind.append({'flow': f'inlet_{s}', 'of': 'flow_frac', 'speed': 1.2, 'colour': 'pressure', 'by': 'p_supply'})
    for q in range(4):
        bind.append({'flow': f'blades_{q}', 'of': 'flow_frac', 'speed': 1.2, 'colour': 'pressure', 'by': 'p4'})
    bind.append({'flow': 'exhaust', 'of': 'flow_frac', 'speed': 1.2, 'colour': 'pressure', 'by': 'p8'})
    bind += [
        {'at': 'pedestal_f', 'show': 'rpm'},
        {'at': 'rotor', 'sound': 'blade_pass', 'gain': {'of': 'speed', 'table': [[0, 0], [0.05, 0.15], [1, 1]]},
         'pitch': {'of': 'speed', 'table': [[0, 0.05], [1.3, 1.3]]}},
        {'at': 'valve_l', 'sound': 'steam_rush', 'gain': {'of': 'flow', 'table': [[0, 0], [RATED_FLOW, 1]]}},
    ]
    bench = {
        'format': 'walkdown-plant-bench', 'version': 1, 'part': 'steam_turbine',
        'sources': SOURCES_BENCH,
        'values': after,
        'ops': [
            {'at': 'valve_l', 'do': 'set', 'input': 'p_supply', 'range': [40, 130], 'title': 'Steam pressure'},
            {'at': 'valve_r', 'do': 'set', 'input': 't_set', 'range': [400, 565], 'title': 'Steam temperature'},
        ],
        'faults': [
            {'id': 'governor', 'at': 'servo_l', 'text': 'Speed governor fault: the speed set 15 % high',
             'set': {'gov_fault': 1}, 'repair': {'gov_fault': 0}},
            {'id': 'thrust_wear', 'at': 'thrust_upper', 'text': 'Thrust bearing wearing: the rotor creeps axially',
             'set': {'thrust_fault': 1}, 'repair': {'thrust_fault': 0}},
            {'id': 'rub', 'at': 'brg_r_upper', 'text': 'Rotor rubbing: bearing vibration high',
             'set': {'vib_fault': 1}, 'repair': {'vib_fault': 0}},
            {'id': 'lube_pump', 'at': 'pedestal_f', 'text': 'Lube oil pump lost: the bearings\' oil pressure falls',
             'set': {'lube_fail': 1}, 'repair': {'lube_fail': 0}},
            {'id': 'wet_steam', 'at': 'valve_l', 'text': 'Steam temperature falls 200 K (water carried over)',
             'set': {'t_dip': 1}, 'repair': {'t_dip': 0}},
        ],
        # a hot start: the casing at 420 °C, the steam at 500 °C at the valves (matched), oil on the bearings
        'start': dict({'casing_t': 420, 'inlet_t': 500, 'lube_p': 2.5}, **{f't{k}': 420 for k in range(1, STAGES + 1)}),
        'bind': bind,
        'legends': {
            'heat': {'unit': '°C', 'table': [[30, '#2c7bb6'], [200, '#abd9e9'], [350, '#ffffbf'], [450, '#fdae61'],
                                             [565, '#d7191c']]},
            'pressure': {'unit': 'bar', 'table': [[0, '#5e3c99'], [1, '#2c7bb6'], [25, '#abd9e9'], [50, '#ffffbf'],
                                                  [75, '#fdae61'], [100, '#d7191c']]},
        },
        # (the steam's pressure and temperature are on their sliders; the phase and the slip are what synchronising reads)
        'readouts': ['rpm', 'flow', 'p_first', 'p8', 't8', 'casing_t', 'superheat', 'vib1', 'axial', 'ph', 'slip', 'mw'],
    }
    return {
        'area': 'st', 'prefix': 'st_',
        'rename': {'st_start': 'turbine', 'gen3_trip_prot': 'trip_breaker', 'gen3_prot_c': 'prot_c',
                   'st_any_trip': 'any_trip', 'hp_p': 'p_supply', 'hp_steam_t': 'steam_t', 'hp_tsat': 'tsat',
                   'hp_steam_net': 'steam_avail', 'gt1_grid_pu': 'grid_pu', 'st_lube_p': 'lube_p',
                   'st_tg_run': 'tg_run', 'st_ecc_ok': 'ecc_ok', 'st_vac_ok': 'vac_ok', 'st_warm_on': 'warm_on',
                   'st_warm_shut': 'warm_shut', 'st_trips_clear': 'trips_clear'},
        'at': {'30MAA10': 'rotor', '30MKC10': 'bench', '30BAC10': 'bench', '30MAY10CS001': 'pedestal_f',
               '30MAY10CS002': 'pedestal_f', '30MAV10CP001': 'pedestal_f', '30MAD10CG001': 'thrust_upper',
               '30MAD10CY001': 'brg_f_upper', '30MAA10CT001': 'valve_l'},
        'machines': ['st_start'], 'trips': TRIPS + [BREAKER_TRIP], 'alarms': ALARMS,
        'ops': [['30MKC10', 'start'], ['30MKC10', 'stop'], ['30BAC10', 'close_breaker'], ['30BAC10', 'open_breaker'],
                ['30MAY10CS001', 'set']],
        'titles': {('30MAA10', 'roll'): 'Roll', ('30MAA10', 'hold'): 'Hold speed',
                   ('30MAA10', 'continue'): 'Continue', ('30MAA10', 'stop'): 'Stop',
                   ('30MKC10', 'start'): 'Excitation on', ('30MKC10', 'stop'): 'Excitation off',
                   ('30BAC10', 'close_breaker'): 'Close the breaker', ('30BAC10', 'open_breaker'): 'Open the breaker',
                   ('30MAY10CS001', 'set'): 'Speed bias',
                   'st_trip_lube': 'Reset: lube oil', 'st_trip_os': 'Reset: overspeed',
                   'st_trip_axial': 'Reset: axial', 'st_trip_vib': 'Reset: vibration',
                   'st_trip_steam_t': 'Reset: wet steam', BREAKER_TRIP: 'Reset: breaker'},
        'values': TAKE_VALUES,
        'before': before,
        'bench': bench,
    }


def bench(models):
    """The turbine's bench file, made from the plant's st model (WORKSHOP.md §6.3)."""
    from workshop import make_bench
    return make_bench.make(bench_source(), models)
