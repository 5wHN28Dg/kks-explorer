"""The gas turbine's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K5a): the words, materials, order and
sources of its component tree, for the plant's first instance of the kind (a heavy-duty single-shaft machine with
can-annular combustion, a cold-end drive and an axial exhaust). Its geometry is the kit's generator,
apps/plant3d/kit/parts_machines.gd `gas_turbine` and its `_gt_*` helpers; the content build joins the two and refuses
a kind whose halves disagree. The scene is built with the instance's shaft line (`context`), so its coupling stands
where it does in the plant.

Generic: a heavy-duty frame as GE's and Siemens' public papers, brochures and patents describe one; no plant data. The
guided order (`assembly`) is the reverse of a major inspection's take-apart as GER-3620P and the patents give it: the
combustion parts out first without lifting a casing (end covers with their fuel nozzles, liners, the combustion
casings, the transition pieces), then the upper halves of the casings lifted one at a time and the upper stator rows
and nozzles out, the bearings opened, the coupling undone, the rotor lifted out by crane, then the lower halves. What
is simplified is listed in apps/plant3d/kit/README.md ("Workshop: the gas turbine"). No sizes, tools or torques here:
they belong to the realism programme's service file (WORKSHOP.md §4.4).
"""

GER3620 = 'ger3620p'
GER3434 = 'ger3434d'
GEA = 'gea12985'
BH9E = 'bh9e'
INLET = 'us2912156'
BELL = 'us8388314'
THRUST = 'us11572806'
EXH = 'us11761347'
REAR = 'us7493769'
LIFT = 'us10184357'
XFIRE = 'us8893501'
NAVY = 'navedtra14114'
WHEELS = 'us6382903'
CANS = 12
CSTAGES = 8
TSTAGES = 3

SOURCES = [
    {'id': GER3620, 'cite': 'Beagle et al., Heavy-Duty Gas Turbine Operating and Maintenance Considerations, GE '
                            'GER-3620P (2021): printed p. 3 split casings, upper halves lifted one at a time, stator '
                            'rows slid out; p. 16 the casings; figs. 31, 32, 34 the combustion, hot gas path and major '
                            'inspections',
     'url': 'https://www.gevernova.com/content/dam/gepower-new/global/en_US/downloads/gas-new-site/resources/'
            'reference/GER-3620-P.pdf'},
    {'id': GER3434, 'cite': 'Brandt and Wesorick, GE Gas Turbine Design Philosophy, GE GER-3434D (1994): p. 2 '
                            'inlet guide vanes; pp. 5-6 a compressor of disks on tie bolts; pp. 8-10 cans, six fuel '
                            'nozzles on each end cover, liner, transition piece; pp. 13-15 three turbine stages',
     'url': 'https://uodiyala.edu.iq/uploads/PDF%20ELIBRARY%20UODIYALA/EL23/General%20Electric%20Gas%20turbine%20'
            'Power%20Generator%20philosophy%201994.pdf'},
    {'id': GEA, 'cite': 'GE Power Systems, Gas Turbine and Combined Cycle Products, GEA-12985B (2002): p. 6 F class '
                        'machines with an 18-stage compressor, a three-stage turbine, a cold-end drive and an axial '
                        'exhaust; p. 5 the H class\'s 12 and 14 cans',
     'url': 'https://courses.washington.edu/mengr430/au07/handouts/ge/product_des.pdf'},
    {'id': BH9E, 'cite': 'Baker Hughes, Frame 9/1E gas turbine overview (2025): p. 5 horizontally split casings; p. 6 '
                         'a 17-stage compressor, three turbine stages with cooled first and second stages, 14 '
                         'combustion chambers',
     'url': 'https://dam.bakerhughes.com/m/1e233875f260d5ff/original/Frame91E-Overview.pdf'},
    {'id': INLET, 'cite': 'US patent 2,912,156 (GE, 1959), Inlet casing for axial flow compressor: figs. 1, 2 and 4, '
                          'the inlet plenum round the casing, the flared bellmouth, the bearing housing inside the '
                          'inlet casing split at a horizontal flange',
     'url': 'https://patents.google.com/patent/US2912156'},
    {'id': BELL, 'cite': 'US patent 8,388,314 (GE, 2013), Turbine inlet casing with integral bearing housing: '
                         'figs. 2-5, the inner and outer bellmouths and the split bearing housing',
     'url': 'https://patents.google.com/patent/US8388314'},
    {'id': THRUST, 'cite': 'US patent 11,572,806 (GE, 2023): the thrust bearing beside the compressor\'s inlet '
                           'bellmouth with a journal bearing, the generator coupled to the shaft (fig. 2); to reach '
                           'them the upper bearing housing comes off, then the thrust bearing, then the upper journal '
                           'bearing (figs. 6-7)',
     'url': 'https://patents.google.com/patent/US11572806'},
    {'id': EXH, 'cite': 'US patent 11,761,347 (GE, 2023), Exhaust frame differential cooling system: figs. 1A, 2 and '
                        '3, the exhaust frame\'s inner and outer barrels joined by struts, the bearing tunnel in the '
                        'inner barrel',
     'url': 'https://patents.google.com/patent/US11761347'},
    {'id': REAR, 'cite': 'US patent 7,493,769 (GE, 2009): fig. 1, the rear bearing inside the exhaust frame, its '
                         'struts ending in the exhaust diffuser',
     'url': 'https://patents.google.com/patent/US7493769'},
    {'id': LIFT, 'cite': 'US patent 10,184,357 (GE, 2019), background and figs. 2-3: each upper casing section (inlet, '
                         'compressor, combustor, turbine, exhaust) taken off, then a crane lifts the rotor out of the '
                         'lower casing',
     'url': 'https://patents.google.com/patent/US10184357'},
    {'id': XFIRE, 'cite': 'US patent 8,893,501 (GE, 2014), Combustor crossfire tube: figs. 2-3, the liner inside the '
                          'flow sleeve inside the combustion casing, the air running between them, crossfire tubes '
                          'between neighbouring cans',
     'url': 'https://patents.google.com/patent/US8893501'},
    {'id': NAVY, 'cite': 'US Navy, Gas Turbine Systems Technician, NAVEDTRA 14114, vol. 2, ch. 1, p. 1-18 and fig. 1-19 '
                         '(as adapted by CED Engineering, M04-041, pdf p. 21): can-annular combustors, separate cans in '
                         'an annular case, one or more fuel nozzles in each',
     'url': 'https://www.cedengineering.com/userfiles/M04-041%20-%20Fundamentals%20of%20Gas%20Turbine%20Engines%20'
            '-%20US.pdf'},
    {'id': WHEELS, 'cite': 'US patent 6,382,903 (GE, 2002): fig. 3, turbine wheels and spacers held together by '
                           'axial bolts round the rotor, with rabbeted joints',
     'url': 'https://patents.google.com/patent/US6382903'},
]

ORD = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth']
SIMPLE = ' (simplified)'


def comp(name, does, material, sources, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': sources}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def ks():
    return ['%02d' % (i + 1) for i in range(CANS)]


def components():
    c = {
        'base': comp('Foundation and base frame', 'The concrete block and the steel supports the machine stands on: '
                     'the compressor\'s and the turbine\'s legs carry the lower casings.',
                     'Reinforced concrete, painted steel', [GER3620]),
        'intake': comp('Air inlet plenum and duct', 'The box round the compressor\'s inlet, fed from the filter house '
                       'above: it turns the filtered air into the bellmouth.', 'Painted steel plate', [INLET, GER3620]),
        'bell_upper': comp('Inlet bellmouth, upper half', 'The upper half of the flared ring that leads the air smoothly '
                           'into the compressor\'s first row; split at the joint round the shaft, it lifts off for a '
                           'major inspection.' + SIMPLE, 'Cast iron, painted', [INLET, BELL]),
        'bell_lower': comp('Inlet bellmouth, lower half', 'The lower half of the flared ring, under the shaft: the rotor '
                           'lifts off over it.' + SIMPLE, 'Cast iron, painted', [INLET, BELL]),
        'brg1_housing': comp('Front bearing housing', 'The pedestal at the cold end that carries the front journal '
                             'bearing and the thrust bearing; the shaft leaves it to the generator.', 'Cast iron',
                             [BELL, THRUST, GER3620]),
        'brg1_cover': comp('Front bearing housing cover', 'The upper part of the housing: it comes off to reach the '
                           'bearings.' + SIMPLE, 'Cast iron, painted', [THRUST, GER3620]),
        'brg1_upper': comp('Front journal bearing, upper half', 'Closes the journal bearing over the shaft.',
                           'Steel shell, white metal lining', [THRUST, GER3620]),
        'brg1_lower': comp('Front journal bearing, lower half', 'Carries the rotor\'s front end on an oil film.',
                           'Steel shell, white metal lining', [THRUST, GER3620]),
        'thrust': comp('Thrust bearing, upper half', 'Pads on both faces of the rotor\'s thrust collar hold the rotor in '
                       'its place along the axis against the compressor\'s and the turbine\'s pull; the upper half '
                       'comes off before the rotor is lifted.' + SIMPLE, 'Steel pads, white metal faces', [THRUST, BELL]),
        'thrust_lower': comp('Thrust bearing, lower half', 'The lower halves of the pad rings either side of the thrust '
                             'collar: the rotor lifts off over them.' + SIMPLE, 'Steel pads, white metal faces',
                             [THRUST, BELL]),
        'comp_lower': comp('Compressor casing, lower half', 'Holds the lower halves of the stator rows; its flanges '
                           'meet the upper half at the horizontal joint.', 'Cast iron', [GER3620, BH9E]),
        'comp_upper': comp('Compressor casing, upper half', 'Bolted to the lower half at the horizontal joint; lifted '
                           'off to reach the compressor\'s blading.', 'Cast iron', [GER3620, BH9E]),
        'igv_upper': comp('Inlet guide vanes, upper half', 'Vanes ahead of the first stage that turn to let more or '
                          'less air in: closed at start-up and low load.' + SIMPLE, 'Stainless steel',
                          [GER3434, GER3620]),
        'igv_lower': comp('Inlet guide vanes, lower half', 'The lower half of the variable inlet guide vanes.',
                          'Stainless steel', [GER3434, GER3620]),
        'cvanes_upper': comp('Compressor stator rows, upper half', 'The fixed vanes between the moving rows: they turn '
                             'the air and slow it, so its pressure rises stage by stage. They slide out of the casing\'s '
                             'grooves.', 'Stainless steel', [GER3620, GER3434]),
        'cvanes_lower': comp('Compressor stator rows, lower half', 'The lower halves of the stator rows.',
                             'Stainless steel', [GER3620, GER3434]),
        'bleed_pipes': comp('Compressor bleed pipes', 'Take air off a middle stage at start-up and shutdown so the '
                            'compressor doesn\'t stall.', 'Painted steel pipe', [GER3434]),
        'cdc_lower': comp('Compressor discharge casing, lower half', 'The casing after the compressor that holds the '
                          'air at full pressure round the combustion system; the cans are mounted on it.',
                          'Cast steel', [GER3620]),
        'cdc_upper': comp('Compressor discharge casing, upper half', 'Bolted to the lower half at the joint; lifted off '
                          'in a major inspection.', 'Cast steel', [GER3620]),
        'fuel_ring': comp('Fuel gas manifold', 'The ring main round the cans and its pigtails to each end cover, fed '
                          'from the fuel gas supply.', 'Steel pipe, flexible hoses', [GER3620, GER3434]),
        'tshell_lower': comp('Turbine shell, lower half', 'Holds the lower halves of the nozzle rows and the shrouds '
                             'round the buckets; insulated outside.', 'Cast alloy steel under insulation',
                             [GER3620, BH9E]),
        'tshell_upper': comp('Turbine shell, upper half', 'Lifted off in a hot gas path inspection to reach the nozzles '
                             'and buckets.', 'Cast alloy steel under insulation', [GER3620]),
        'brg2_upper': comp('Rear journal bearing, upper half', 'Closes the rear bearing over the shaft (drawn just '
                           'ahead of the exhaust frame: a real one sits in its inner barrel).', 'Steel shell, white '
                           'metal lining', [REAR, EXH]),
        'brg2_lower': comp('Rear journal bearing, lower half', 'Carries the rotor\'s hot end on an oil film.',
                           'Steel shell, white metal lining', [REAR, EXH]),
        'exhaust': comp('Exhaust frame and diffuser', 'Behind the last stage: the frame carries the rear bearing on '
                        'struts, and the diffuser widens to slow the gas on its way to the heat recovery boiler.',
                        'Alloy steel, insulated and clad', [EXH, REAR, GER3620]),
        'rotor': comp('Rotor', 'The compressor\'s disks, the distance piece and the turbine\'s wheels, held together by '
                      'tie bolts: one shaft that turns the compressor and the generator.', 'Forged alloy steel',
                      [GER3434, WHEELS, LIFT],
                      sealed_why='In this view the rotor comes out and goes back as one assembly with its blades and '
                                 'buckets; changing a blade or a bucket is not drawn.'),
        'cblades': comp('Compressor rotor blades', 'The moving rows on the compressor\'s disks: they push the air on, '
                        'shorter stage by stage as it is squeezed.', 'Stainless steel', [GER3434, GEA]),
    }
    for k in range(TSTAGES):
        n = k + 1
        c[f'tnoz{n}_u'] = comp(f'Stage {n} nozzles, upper half', f'The {ORD[k]} stage\'s stationary vanes: they speed '
                               'the hot gas up and turn it onto the buckets.' + (' Air-cooled.' if n < 3 else ''),
                               'Nickel-based superalloy', [GER3620, GER3434])
        c[f'tnoz{n}_l'] = comp(f'Stage {n} nozzles, lower half', f'The lower half of the {ORD[k]} stage\'s nozzles.',
                               'Nickel-based superalloy', [GER3620, GER3434])
        c[f'tbucket{n}'] = comp(f'Stage {n} buckets', f'The {ORD[k]} stage\'s blades on the turbine wheel: the gas '
                                'drives them round.' + (' Air-cooled from inside.' if n < 3 else ''),
                                'Nickel-based superalloy', [GER3434, GER3620])
    for k in ks():
        i = int(k)
        c['can_' + k] = comp(f'Combustion can {i}', 'The can\'s casing and flow sleeve: compressor air flows back '
                             'between them to the head end.', 'Steel, insulated', [XFIRE, NAVY, GER3620])
        c['cover_' + k] = comp(f'End cover {i} with its fuel nozzles', 'Closes the can\'s head end and carries its fuel '
                               'nozzles (six drawn, as on GE\'s Dry Low NOx cans).', 'Stainless steel',
                               [GER3434, GER3620])
        c['liner_' + k] = comp(f'Combustion liner {i}', 'The flame burns inside it; air through its holes mixes in and '
                               'cools it.', 'Nickel-based alloy, thermal barrier coating', [XFIRE, GER3434, GER3620])
        c['tp_' + k] = comp(f'Transition piece {i}', 'Carries the hot gas from the liner to the first stage\'s nozzles, '
                            'from round to a sector of the annulus.', 'Nickel-based alloy', [GER3434, GER3620])
    return c


def step(place, text, needs=(), why=None, sources=(GER3620,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


def assembly():
    a = [
        step('base', 'Set the base frame and the supports on the foundation.'),
        step('brg1_housing', 'Set the front bearing housing on its pedestal at the cold end.',
             [('base', 'The housing stands on the base: set it first.', 'Lift the bearing housing off before the base '
               'is moved.')], sources=(BELL, GER3620)),
        step('comp_lower', 'Lower the compressor casing\'s lower half onto its supports and line it up with the shaft '
             'line.', [('base', 'The casing stands on the base\'s supports: set them first.', 'Lift the lower '
                       'compressor casing off before the base is moved.')]),
        step('cdc_lower', 'Bolt the compressor discharge casing\'s lower half to the compressor casing\'s rear flange.',
             [('comp_lower', 'It bolts to the compressor casing\'s lower half: set that first.', 'Unbolt the lower '
               'discharge casing before the lower compressor casing is moved.')]),
        step('bell_lower', 'Bolt the bellmouth\'s lower half to the compressor casing\'s inlet flange.',
             [('comp_lower', 'It bolts to the compressor casing\'s lower half: set that first.', 'Take the bellmouth\'s '
               'lower half off before the lower compressor casing is moved.')], sources=(BELL, INLET)),
        step('tshell_lower', 'Bolt the turbine shell\'s lower half to the discharge casing and set it on its '
             'supports.', [('cdc_lower', 'It bolts to the discharge casing\'s lower half: set that first.',
                            'Unbolt the lower turbine shell before the lower discharge casing is moved.')]),
        step('exhaust', 'Bolt the exhaust frame and its diffuser to the turbine shell\'s rear flange.',
             [('tshell_lower', 'The exhaust frame bolts to the turbine shell: set its lower half first.',
               'Take the exhaust frame off before the lower turbine shell is moved.')], sources=(EXH, REAR, GER3620)),
        step('igv_lower', 'Fit the lower inlet guide vanes in the compressor casing\'s inlet.',
             [('comp_lower', 'The vanes sit in the lower compressor casing: set it first.', 'Take the lower guide '
               'vanes out before the lower compressor casing is moved.')], sources=(GER3434, GER3620)),
        step('cvanes_lower', 'Slide the lower halves of the stator rows round into the lower casing\'s grooves.',
             [('comp_lower', 'The stator rows slide into the lower compressor casing: set it first.', 'Slide the lower '
               'stator rows out before the lower compressor casing is moved.')]),
    ]
    for k in range(TSTAGES):
        n = k + 1
        a.append(step(f'tnoz{n}_l', f'Fit the stage {n} nozzles\' lower half in the turbine shell.',
                      [('tshell_lower', 'The nozzles sit in the lower turbine shell: set it first.', f'Take the lower '
                        f'stage {n} nozzles out before the lower turbine shell is moved.')]))
    a += [
        step('brg1_lower', 'Roll the front journal bearing\'s lower half into its housing.',
             [('brg1_housing', 'The bearing sits in the front housing: set it first.', 'Roll the lower front bearing '
               'out before its housing is moved.')], sources=(THRUST, GER3620)),
        step('thrust_lower', 'Set the thrust bearing\'s lower pads in the housing, either side of where the collar '
             'will run.', [('brg1_housing', 'The pads sit in the front housing: set it first.', 'Take the lower '
                            'thrust pads out before their housing is moved.')], sources=(THRUST,)),
        step('brg2_lower', 'Fit the rear journal bearing\'s lower half.',
             [('tshell_lower', 'The rear bearing is carried at the turbine end: set the lower turbine shell first.',
               'Take the lower rear bearing out before the lower turbine shell is moved.')], sources=(REAR, GER3620)),
        step('rotor', 'Lower the rotor level by crane onto the lower journal bearings, clear of the stator rows and '
             'nozzles (simplified: a real unit has the exhaust\'s upper half off too before the rotor is lifted; here '
             'the exhaust frame is one part and stays, clear of the rotor\'s end).', [('brg1_lower', 'The rotor rests on the front bearing\'s lower half: fit it first.',
                           'Lift the rotor out before the lower front bearing is taken out.'),
                          ('brg2_lower', 'The rotor rests on the rear bearing\'s lower half: fit it first.',
                           'Lift the rotor out before the lower rear bearing is taken out.'),
                          ('thrust_lower', 'Set the lower thrust pads before the rotor goes in over them.',
                           'Lift the rotor out before the lower thrust pads come out.'),
                          ('igv_lower', 'Fit the lower guide vanes before the rotor goes in over them.',
                           'Lift the rotor out before the lower guide vanes come out.'),
                          ('cvanes_lower', 'Fit the lower stator rows before the rotor goes in over them.',
                           'Lift the rotor out before the lower stator rows come out.')] +
             [(f'tnoz{n}_l', f'Fit the lower stage {n} nozzles before the rotor goes in over them.',
               f'Lift the rotor out before the lower stage {n} nozzles come out.') for n in range(1, TSTAGES + 1)],
             sources=(LIFT, GER3620)),
        step('cblades', 'The compressor\'s rotor blades come with the rotor.', sources=(GER3434,)),
    ]
    for n in range(1, TSTAGES + 1):
        a.append(step(f'tbucket{n}', f'The stage {n} buckets come with the rotor.', sources=(GER3434,)))
    a += [
        step('thrust', 'Close the thrust bearing with its upper pads on both faces of the thrust collar.',
             [('rotor', 'The pads close on the rotor\'s thrust collar: set the rotor first.', 'Take the thrust bearing '
               'out before the rotor is lifted.')], sources=(THRUST,)),
        step('brg1_upper', 'Close the front journal bearing with its upper half.',
             [('rotor', 'The upper half closes over the shaft: set the rotor first.', 'Take the upper front bearing off '
               'before the rotor is lifted.')], sources=(THRUST, GER3620)),
        step('brg2_upper', 'Close the rear journal bearing with its upper half.',
             [('rotor', 'The upper half closes over the shaft: set the rotor first.', 'Take the upper rear bearing off '
               'before the rotor is lifted.')], sources=(REAR, GER3620)),
        step('brg1_cover', 'Close the front bearing housing with its cover.',
             [('brg1_upper', 'Close the journal bearing before the housing.', 'Take the housing\'s cover off before '
               'the upper front bearing.'),
              ('thrust', 'Fit the thrust bearing before the housing is closed.', 'Take the housing\'s cover off before '
               'the thrust bearing.')], sources=(THRUST,)),
        step('coupling_bolts', 'Couple the rotor to the generator: line the flanges up and fit the coupling bolts.',
             [('rotor', 'The coupling joins the rotor to the generator: set the rotor first.', 'Take the coupling '
               'bolts out before the rotor is lifted.')], sources=(GEA, THRUST)),
        step('igv_upper', 'Set the upper inlet guide vanes over the rotor (simplified: in a real unit they sit in the '
             'upper casing half and come off with it; here they are a part of their own, put in before the casing).',
             [('rotor', 'The upper vanes close over the rotor: set it first.', 'Take the upper guide vanes out before '
               'the rotor is lifted.')], sources=(GER3434, GER3620)),
        step('cvanes_upper', 'Set the upper halves of the stator rows over the rotor (simplified: in a real unit they '
             'are slid into the upper casing half\'s grooves and come off with it; here they are a part of their own, '
             'put in before the casing).',
             [('rotor', 'The upper stator rows close over the rotor: set it first.', 'Take the upper stator rows out '
               'before the rotor is lifted.')]),
        step('comp_upper', 'Lower the compressor casing\'s upper half onto the joint on its guide pins.',
             [('comp_lower', 'The upper half closes on the lower half: set it first.', 'Lift the upper half off before '
               'the lower half is moved.'),
              ('igv_upper', 'Fit the upper guide vanes in it first.', 'Lift the upper casing off before its guide '
               'vanes come out.'),
              ('cvanes_upper', 'Fit the upper stator rows in it first.', 'Lift the upper casing off before its stator '
               'rows come out.'),
              ('brg1_cover', 'Close the front bearing first.', 'Lift the upper compressor casing off before the front '
               'bearing is opened.')], sources=(GER3620, LIFT)),
        step('comp_bolts', 'Fit the horizontal joint\'s studs and tighten their nuts.',
             [('comp_upper', 'The studs hold the upper half down: lower it first.', 'Take the joint\'s studs out before '
               'the upper half is lifted.')]),
        step('cdc_upper', 'Lower the compressor discharge casing\'s upper half onto its joint.',
             [('cdc_lower', 'The upper half closes on the lower half: set it first.', 'Lift the upper half off before '
               'the lower half is moved.'),
              ('rotor', 'It closes over the rotor: set the rotor first.', 'Lift the upper discharge casing off before '
               'the rotor.')], sources=(GER3620, LIFT)),
    ]
    for n in range(1, TSTAGES + 1):
        a.append(step(f'tnoz{n}_u', f'Fit the stage {n} nozzles\' upper half over the rotor.',
                      [('rotor', 'The upper nozzles close over the rotor: set it first.', f'Take the upper stage {n} '
                        'nozzles out before the rotor is lifted.')]))
    a.append(step('tshell_upper', 'Lower the turbine shell\'s upper half onto its joint and bolt it down.',
                  [('tshell_lower', 'The upper half closes on the lower half: set it first.', 'Lift the upper half off '
                    'before the lower half is moved.'),
                   ('brg2_upper', 'Close the rear bearing first.', 'Lift the upper turbine shell off before the rear '
                    'bearing is opened.')] +
                  [(f'tnoz{n}_u', f'Fit the upper stage {n} nozzles first.', f'Lift the upper turbine shell off before '
                    f'the upper stage {n} nozzles come out.') for n in range(1, TSTAGES + 1)]))
    for k in ks():
        a.append(step('tp_' + k, f'Fit transition piece {k.lstrip("0")} through its can opening, its aft end on the '
                      'first stage\'s nozzles.',
                      [('cdc_upper', 'The transition pieces go in with the discharge casing closed.', 'Take the '
                        'transition pieces out before the upper discharge casing is lifted.'),
                       ('tshell_upper', 'Close the turbine shell before the transition pieces go in.', 'Take the '
                        'transition pieces out before the upper turbine shell is lifted.')], sources=(GER3620, GER3434)))
    for k in ks():
        i = k.lstrip('0')
        a.append(step('can_' + k, f'Bolt combustion can {i}\'s casing to the discharge casing.',
                      [('tp_' + k, 'Its transition piece goes in first, through the can\'s opening.', 'Take the can\'s '
                        'casing off before its transition piece comes out.')], sources=(XFIRE, GER3620)))
        a.append(step('liner_' + k, f'Slide liner {i} into the can until its aft end seats in the transition piece.',
                      [('can_' + k, 'The liner goes inside the can\'s casing: fit the casing first.', 'Pull the liner out '
                        'before the can\'s casing comes off.')], sources=(XFIRE, GER3620)))
        a.append(step('cover_' + k, f'Bolt end cover {i} with its fuel nozzles onto the can.',
                      [('liner_' + k, 'The end cover closes the can over its liner: fit the liner first.', 'Take the end '
                        'cover off before the liner is pulled.')], sources=(GER3434, GER3620)))
    a += [
        step('fuel_ring', 'Hang the fuel gas manifold round the cans and connect a pigtail to each end cover.',
             [('cover_' + k, f'Its pigtail connects to end cover {k.lstrip("0")}: fit the cover first.',
               f'Disconnect the manifold before end cover {k.lstrip("0")} comes off.') for k in ks()],
             sources=(GER3620,)),
        step('bleed_pipes', 'Connect the bleed pipes to the compressor casing.',
             [('comp_upper', 'The bleed pipes connect to the upper casing: lower it first.', 'Take the bleed pipes off '
               'before the upper compressor casing is lifted.')], sources=(GER3434,)),
        step('bell_upper', 'Close the bellmouth with its upper half, bolted to the upper casing\'s inlet flange and '
             'to the lower half at the joint.',
             [('comp_upper', 'The upper half bolts to the upper casing: close the casing first.', 'Take the '
               'bellmouth\'s upper half off before the upper compressor casing is lifted.'),
              ('bell_lower', 'It closes on the lower half: set that first.', 'Take the upper half off before the '
               'lower half.')], sources=(BELL, INLET)),
        step('intake', 'Close the inlet plenum round the bellmouth and connect it to the duct from the filter house.',
             [('bell_upper', 'The plenum closes round the bellmouth: close it first.', 'Open the plenum before the '
               'bellmouth\'s upper half is taken off.')], sources=(INLET, GER3620)),
    ]
    return a


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'gas_turbine',
        'context': ['axis_z', 'shaft_lo', 'shaft_hi'],
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'comp_bolts': {'name': '40 compressor casing joint studs and nuts', 'joins': ['comp_upper', 'comp_lower'],
                           'sources': [GER3620, BH9E]},
            'coupling_bolts': {'name': '12 coupling bolts', 'joins': ['rotor'],
                               'beyond': 'the generator\'s rotor (its own machine)', 'sources': [GEA, THRUST]},
        },
        'assembly': assembly(),
        # the views (WORKSHOP.md §4.7): the X-ray takes the casings and the cans round the gas path; the cutaway opens
        # the upper quarter on the right (+x), the rotor and its blades shown whole
        'views': {'xray_all': ['intake', 'comp_upper', 'comp_lower', 'cdc_upper', 'cdc_lower', 'tshell_upper',
                               'tshell_lower', 'brg1_cover'] + ['can_' + k for k in ks()],
                  'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}, {'normal': [0, 0, 1], 'offset': 0}],
                              'keep': ['rotor', 'cblades'] + [f'tbucket{n}' for n in range(1, TSTAGES + 1)]}},
    }
