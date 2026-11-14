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
        # the upper quarter on the right (+x), the rotor and its blades shown whole; the turbine runs only closed
        'views': {'xray_all': ['intake', 'comp_upper', 'comp_lower', 'cdc_upper', 'cdc_lower', 'tshell_upper',
                               'tshell_lower', 'brg1_cover'] + ['can_' + k for k in ks()],
                  'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}, {'normal': [0, 0, 1], 'offset': 0}],
                              'keep': ['rotor', 'cblades'] + [f'tbucket{n}' for n in range(1, TSTAGES + 1)]},
                  # (K5b) it runs only closed, as the steam turbine: the casings hold the air and the gas, the
                  # bearings the rotor, and there is no lagging to leave off; it is opened only at standstill on its turning gear (the
                  # user's decision, 2026-11-07)
                  'run_exploded': {'allowed': [],
                                   'why': 'A gas turbine runs only closed: the casings hold the air and the hot gas, '
                                          'the bearings the rotor. Put it back together first.'},
                  'open_running': {'allowed': [],
                                   'why': 'Not opened while the rotor turns: stop it, let the rotor come to '
                                          'standstill on its turning gear, then open it up.'}},
    }


# ------------------------------------------------------------------ the bench (WORKSHOP.md §6, milestone K5b)
# The gas turbine run on its bench: the plant's own start-up sequence (`gt1_start`: the SFC cranks it, the HRSG purge,
# coasting to ignition speed, fuel and igniters, the flame detected, the run-up, the SFC off at 70 %, full speed no
# load, synchronised, loaded), its trips, alarms, interlock and the values they read, taken from the generated gt1
# model by make_bench.py (never copied here). The bench gives what the plant's other areas would: the ambient air (a
# slider), the closed cooling water, the grid, the HRSG's permissives; and the gas path the plant's model doesn't have:
# the pressure and the temperature through the compressor's stages, the combustion and the firing temperature, the
# expansion through the turbine's stages to the exhaust, the fuel's flow. Generic: no plant data.
NASA_C = 'nasa_compth'
NASA_T = 'nasa_powtrbth'
NIST_CH4 = 'nist_methane'
SOURCES_BENCH = [
    {'id': NASA_C, 'cite': 'NASA Glenn Research Center, Beginner\'s Guide to Propulsion: Compressor Thermodynamics: '
                           'the total temperature ratio across a compressor from its pressure ratio, Tt3/Tt2 = '
                           '(pt3/pt2)^((gam-1)/gam), and the work it takes divided by the efficiency nc',
     'url': 'https://www.grc.nasa.gov/www/k-12/airplane/compth.html'},
    {'id': NASA_T, 'cite': 'NASA Glenn Research Center, Beginner\'s Guide to Propulsion: Power Turbine '
                           'Thermodynamics: the temperature ratio across a turbine from its pressure ratio, '
                           'Tt5/Tt4 = (pt5/pt4)^((gam-1)/gam), the work it gives times the efficiency nt',
     'url': 'https://www.grc.nasa.gov/www/k-12/airplane/powtrbth.html'},
    {'id': NIST_CH4, 'cite': 'NIST Chemistry WebBook, SRD 69, Methane: the enthalpy of combustion of the gas, '
                             '-890.7 kJ/mol (water as liquid); less the two moles of water\'s 44.0 kJ/mol of '
                             'vaporisation, 802.7 kJ/mol over 16.04 g/mol, the lower heating value 50.0 MJ/kg',
     'url': 'https://webbook.nist.gov/cgi/cbook.cgi?ID=C74828&Mask=1'},
    {'id': GER3434, 'cite': 'Brandt and Wesorick, GE Gas Turbine Design Philosophy, GE GER-3434D (1994): pp. 8-10 '
                            'the cans, the liner cooled by the compressor\'s air, the transition piece to the first '
                            'stage\'s nozzles; pp. 13-15 three turbine stages, the first two air-cooled',
     'url': 'https://uodiyala.edu.iq/uploads/PDF%20ELIBRARY%20UODIYALA/EL23/General%20Electric%20Gas%20turbine%20'
            'Power%20Generator%20philosophy%201994.pdf'},
    {'id': GER3620, 'cite': 'Beagle et al., Heavy-Duty Gas Turbine Operating and Maintenance Considerations, GE '
                            'GER-3620P (2021): the start, firing and the run-up, trips from load, the hot gas path\'s '
                            'temperatures',
     'url': 'https://www.gevernova.com/content/dam/gepower-new/global/en_US/downloads/gas-new-site/resources/'
            'reference/GER-3620-P.pdf'},
]
P_AMB = 1.0             # bar (absolute) at the bellmouth: the plant's compressor discharge pressure is 1 at standstill
GAMMA_AIR = 1.4
GAMMA_GAS = 1.33        # the hot gas's ratio of specific heats
ETA_C = 0.87            # the compressor's isentropic efficiency (NASA's nc)
ETA_T = 0.89            # the turbine's (NASA's nt)
AIR_RATED = 620.0       # kg/s at base load (the plant's: gt1_exh_flow's tables, 430 at full speed and 190 with load)
LHV = 50.0              # MJ/kg, methane's lower heating value (NIST, above)
HEAT_RATE = 9750.0      # kJ/kWh at base load, the plant's (gt1_hr)
BASE_MW = 250.0         # the plant's base load (gt1_cap)
FUEL_RATED = round(BASE_MW * HEAT_RATE / 3600.0 / LHV, 3)   # kg/s of fuel at base load: the fuel valve's 1
# the compressor discharge pressure's points the stage tables are made at (bar absolute; the plant's runs 1 to 15, and
# down to 0.5 in a surge at standstill: below 1 bar the stages run the other way, still each between its neighbours)
CPD = [0.5, 0.625, 0.75, 0.875, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20]
MC = (GAMMA_AIR - 1) / GAMMA_AIR
MT = (GAMMA_GAS - 1) / GAMMA_GAS

# what the bench takes from the plant's gt1 model (WORKSHOP.md §6.3)
TAKE_VALUES = (
    # the commands, the sequence's set points and the trainer's faults
    ['gt1_lac_cmd', 'gt1_lac_fault', 'gt1_ldc_cmd', 'gt1_ldc_fault', 'gt1_oil_leak', 'gt1_tg_cmd', 'gt1_sfc_on',
     'gt1_fuel_on', 'gt1_ign', 'gt1_speed_sp', 'gt1_bias', 'gt1_load_sp', 'gt1_exc_cmd', 'gt1_brk_cmd',
     'gt1_gov_fault', 'gt1_fuel_fault', 'gt1_tc_fault', 'gt1_flameout', 'gt1_surge', 'gt1_vib_fault', 'gt1_gas_low',
     # the rotor's speed
     'gt1_speed', 'gt1_still', 'gt1_at_rest',
     # the lube oil: the AC and the DC pumps, three pressure switches (two out of three trip), the DC pump's start,
     # the oil's temperature
     'gt1_lac_ok', 'gt1_lac_run', 'gt1_ldc_ok', 'gt1_ldc_run', 'gt1_ldc_q', 'gt1_lsup', 'gt1_lp_sp0', 'gt1_lp_leakf',
     'gt1_lp_sp', 'gt1_lube_p', 'gt1_lp_1', 'gt1_lp_1_l', 'gt1_lp_1_ll', 'gt1_lp_2', 'gt1_lp_2_ll', 'gt1_lp_3',
     'gt1_lp_3_ll', 'gt1_lp_llv', 'gt1_lp_ll', 'gt1_lube_ok', 'gt1_lp_norm', 'gt1_pumps_off', 'gt1_lube_off',
     'gt1_lube_est', 'gt1_lube_sup', 'gt1_lp_low', 'gt1_dc_auto_c', 'gt1_oil_heat', 'gt1_oil_k', 'gt1_oil_rise',
     'gt1_oil_tgt', 'gt1_oil_t', 'gt1_oil_t_h', 'gt1_oil_t_hc', 'gt1_oil_t_hh',
     # the turning gear, the governor, the speed's target, overspeed
     'gt1_slow', 'gt1_tg_run', 'gt1_tg_spd', 'gt1_driven', 'gt1_gov', 'gt1_sp_eff', 'gt1_free_tgt', 'gt1_grid_pu',
     'gt1_tgt', 'gt1_rpm', 'gt1_os',
     # the sequence's states and steps: the purge's timer, the speeds it waits for, firing
     'gt1_in_purge_ge', 'gt1_in_purge_le', 'gt1_in_purge', 'gt1_in_fsnl_ge', 'gt1_in_fsnl_le', 'gt1_in_fsnl',
     'gt1_purge_t', 'gt1_purge_done', 'gt1_at_crank', 'gt1_at_coast', 'gt1_at_sfc_off', 'gt1_at_full',
     'gt1_fired_ge', 'gt1_fired_le', 'gt1_fired',
     # the fuel gas, ignition and the flame
     'gt1_gas_p', 'gt1_gas_ok', 'gt1_gas_lo', 'gt1_fi', 'gt1_lit', 'gt1_nofuel', 'gt1_flame_rst', 'gt1_flame',
     'gt1_noflame', 'gt1_flame_lost',
     # the load: the capacity by the ambient air, the runbacks, the load's ramp, the fuel's demand and valves
     'gt1_rb_cap', 'gt1_amb_f', 'gt1_dp_rb_cap', 'gt1_cap', 'gt1_base_cap', 'gt1_inv_cap', 'gt1_load_eff',
     'gt1_mw_tgt', 'gt1_mw', 'gt1_lf', 'gt1_fuel_acc', 'gt1_fuel_ld', 'gt1_fuel_dem', 'gt1_fuel', 'gt1_fuel_v',
     'gt1_stop_v',
     # the exhaust's temperature and its twelve thermocouples, the spread
     'gt1_exh_spd', 'gt1_exh_ld', 'gt1_exh_flt', 'gt1_exh_fired', 'gt1_exh_tgt', 'gt1_exh_t', 'gt1_tc7_err'] +
    [f'gt1_tc{k}' for k in range(1, 13)] +
    ['gt1_tc1_h', 'gt1_tc7_d', 'gt1_tc7_da', 'gt1_tc7_dev', 'gt1_tc_max', 'gt1_tc_min', 'gt1_spread',
     'gt1_spread_hh', 'gt1_exh_hh',
     # the air's flow, the compressor's discharge pressure and surge
     'gt1_flow_spd', 'gt1_flow_ld', 'gt1_exh_flow', 'gt1_cpd_b', 'gt1_cpd_l', 'gt1_cpd_s', 'gt1_cpd_f', 'gt1_cpd_t',
     'gt1_cpd', 'gt1_cpd_slow', 'gt1_cpd_drop', 'gt1_surge_c',
     # the bearings' vibration
     'gt1_vib_b', 'gt1_vib_f', 'gt1_vib1', 'gt1_vib1_hh', 'gt1_vib2', 'gt1_vib2_h', 'gt1_vib2_hh', 'gt1_vib3',
     'gt1_vib3_hh', 'gt1_vib4', 'gt1_vib4_hh', 'gt1_vib_hh',
     # the generator's excitation and the synchronising check
     'gt1_v_sp', 'gt1_v', 'gt1_f', 'gt1_slip', 'gt1_slip_deg', 'gt1_phase', 'gt1_ph', 'gt1_ph_abs', 'gt1_ph_ok',
     'gt1_slip_abs', 'gt1_slip_ok', 'gt1_v_dev', 'gt1_v_ok', 'gt1_sync_ok', 'gt1_spd95', 'gt1_brk_open',
     'gen1_prot_c'])
TRIPS = ['gt1_trip_lube', 'gt1_trip_flame', 'gt1_trip_exh', 'gt1_trip_spread', 'gt1_trip_os', 'gt1_trip_vib',
         'gt1_trip_surge', 'gt1_trip_oil_temp']
BREAKER_TRIP = 'gen1_trip_prot'     # the breaker opened by the turbine's protection (else the grid holds a tripped rotor)
ALARMS = ['gt1_lp1_low', 'gt1_oil_t_h', 'gt1_gas_low', 'gt1_flame1_fail', 'gt1_tc1_h', 'gt1_tc7_dev', 'gt1_os1',
          'gt1_vib2_h']


def _table(f):
    """A table of the compressor discharge pressure (CPD's points) to f(it), rounded."""
    return [[x, round(f(float(x)), 9)] for x in CPD]


def _gas_path():
    """The gas path (the bench's own: the plant's gt1 model has the compressor's discharge pressure, the air's flow and
    the exhaust's temperature, not what lies between). The compressor's eight stages share its pressure ratio equally
    (each stage's pressure the discharge's to the power k/8, from the plant's 1 bar at the bellmouth); each stage's
    temperature from the ambient air's by NASA's compressor relation with the efficiency, T/T0 = 1 + (r^((g-1)/g) - 1)
    / nc. The turbine's three stages share the expansion likewise, down to the bellmouth's pressure at the exhaust,
    T/Tin = 1 - nt (1 - (p/pin)^((g-1)/g)). Every turbine temperature comes from one chain, so the stages stay in order
    through ignition, a trip and the coast-down: the hot gas's, worked back from the plant's exhaust temperature (its
    thermocouples' lag, 20 s up and 60 s down, is the gas path's) through the expansion from each stage to the exhaust,
    the last stage the plant's exhaust temperature itself; or, where hotter, the compressor's discharge air expanded
    from the first nozzles (no flame: the purge, a coast-down). The turbine inlet temperature (`tit`, at the first
    nozzles: the combustor's outlet, above a maker's "firing temperature" at the first buckets) is the larger of the
    hot gas's and the discharge air's. The fuel's flow in kg/s is the plant's fuel valve times the base load's heat
    input (the plant's heat rate) over methane's lower heating value."""
    v = [
        ['amb_k', {'sum': ['ambient_t', 273.15], 'unit': 'K'}],
        ['air_frac', {'product': ['exh_flow', round(1.0 / AIR_RATED, 9)]}],
        ['fuel_flow', {'product': ['fuel_v', FUEL_RATED], 'unit': 'kg/s'}],
        ['fl_lvl', {'of': 'fuel_v', 'table': [[0, 0.4], [1, 1]]}],
        ['flame_v', {'product': ['flame', 'fl_lvl']}],
    ]
    for k in range(1, CSTAGES + 1):
        e = k / CSTAGES
        v += [
            [f'c_p{k}', {'of': 'cpd', 'table': _table(lambda x: x ** e), 'unit': 'bar'}],
            [f'c_tr{k}', {'of': 'cpd', 'table': _table(lambda x: 1 + (x ** (e * MC) - 1) / ETA_C)}],
            [f'c_tk{k}', {'product': ['amb_k', f'c_tr{k}'], 'unit': 'K'}],
            [f'c_t{k}', {'sum': [f'c_tk{k}', -273.15], 'unit': '°C'}],
        ]

    def t_ratio(x, e):      # T at the fraction e of the turbine's expansion over T at its inlet
        return 1 - ETA_T * (1 - x ** (-MT * e))

    cd = f'c_tk{CSTAGES}'
    v += [
        ['exh_k', {'sum': ['exh_t', 273.15], 'unit': 'K'}],
        ['tit_x', {'of': 'cpd', 'table': _table(lambda x: 1 / t_ratio(x, 1))}],
        ['tit_hot', {'product': ['exh_k', 'tit_x'], 'unit': 'K'}],
        ['tit_k', {'max': ['tit_hot', cd], 'unit': 'K'}],
        ['tit', {'sum': ['tit_k', -273.15], 'unit': '°C'}],
    ]
    for k in range(1, TSTAGES + 1):
        e = k / TSTAGES
        v += [
            [f't_p{k}', {'of': 'cpd', 'table': _table(lambda x: x ** (1 - e)), 'unit': 'bar'}],
            # (stage k's exit over the exhaust: 1 at the last stage, so the hot chain's last stage is exh_t itself)
            [f't_hx{k}', {'of': 'cpd', 'table': _table(lambda x: t_ratio(x, e) / t_ratio(x, 1))}],
            [f't_hot{k}', {'product': ['exh_k', f't_hx{k}'], 'unit': 'K'}],
            [f't_ax{k}', {'of': 'cpd', 'table': _table(lambda x: t_ratio(x, e))}],
            [f't_air{k}', {'product': [cd, f't_ax{k}'], 'unit': 'K'}],
            [f't_tk{k}', {'max': [f't_hot{k}', f't_air{k}'], 'unit': 'K'}],
            [f't_t{k}', {'sum': [f't_tk{k}', -273.15], 'unit': '°C'}],
        ]
    return v


def bench_source():
    """The gas turbine's bench source for make_bench.py (WORKSHOP.md §6.3)."""
    before = [
        # the ambient air (the slider) at the bellmouth
        ['ambient_t', {'state': 30, 'unit': '°C'}],
        ['p_amb', {'state': P_AMB, 'unit': 'bar'}],
        # what the plant's other areas give the turbine: the closed cooling water, the grid, the HRSG's drum and
        # feedwater (the start's permissives); no compressor wash, a clean filter and blading, no runback
        ['ccw_ok', {'state': 1}],
        ['ccw_t', {'state': 35, 'unit': '°C'}],
        ['grid_frequency', {'state': 50, 'unit': 'Hz'}],
        ['hp_lvl_ok', {'state': 1}],
        ['fw_avail', {'state': 1}],
        ['wash_idle', {'state': 1}],
        ['dp_f', {'state': 1}],
        ['foul_f', {'state': 1}],
        ['dp_rb', {'state': 0}],
        ['rb', {'state': 0}],
    ]
    after = [
        # the trips the bench takes (the plant's gt1_any_trip reads two more: the HRSG drum's level)
        # (with the breaker's: left latched it would not open the breaker at the next trip on load)
        ['any_trip', {'or': [n.replace('gt1_', '', 1) + '_latched' for n in TRIPS] + ['trip_breaker_latched']}],
        ['trips_clear', {'not': 'any_trip'}],
    ] + _gas_path()
    bind = [{'at': 'rotor', 'anim': 'shaft', 'of': 'speed', 'scale': 50}]
    # the colours: the air through the compressor, the flame in the liners and transition pieces, the hot gas
    # through the turbine's stages, the exhaust
    for h in ('upper', 'lower'):
        bind += [{'at': f'igv_{h}', 'heat': 'ambient_t'}, {'at': f'igv_{h}', 'pressure': 'p_amb'}]
        bind += [{'at': f'comp_{h}', 'heat': 'c_t4'}, {'at': f'comp_{h}', 'pressure': 'c_p4'}]
        bind += [{'at': f'cvanes_{h}', 'heat': 'c_t4'}, {'at': f'cvanes_{h}', 'pressure': 'c_p4'}]
        bind += [{'at': f'cdc_{h}', 'heat': f'c_t{CSTAGES}'}, {'at': f'cdc_{h}', 'pressure': 'cpd'}]
        bind += [{'at': f'tshell_{h}', 'heat': 't_t2'}, {'at': f'tshell_{h}', 'pressure': 't_p1'}]
    bind += [{'at': 'intake', 'heat': 'ambient_t'}, {'at': 'intake', 'pressure': 'p_amb'},
             {'at': 'cblades', 'heat': 'c_t4'}, {'at': 'cblades', 'pressure': 'c_p4'}]
    for k in ks():
        for c in ('liner_', 'tp_'):
            bind += [{'at': c + k, 'heat': 'tit'}, {'at': c + k, 'pressure': 'cpd'}]
    for n in range(1, TSTAGES + 1):
        tin, pin = ('tit', 'cpd') if n == 1 else (f't_t{n - 1}', f't_p{n - 1}')
        for s in ('u', 'l'):
            bind += [{'at': f'tnoz{n}_{s}', 'heat': tin}, {'at': f'tnoz{n}_{s}', 'pressure': pin}]
        bind += [{'at': f'tbucket{n}', 'heat': f't_t{n}'}, {'at': f'tbucket{n}', 'pressure': f't_p{n}'}]
    bind += [{'at': 'exhaust', 'heat': 'exh_t'}, {'at': 'exhaust', 'pressure': 'p_amb'}]
    # the flow paths (kit/parts_machines.gd _gt_flows): the air in, along the compressor, the fuel to two cans, the
    # flame in three, the gas along the turbine, the exhaust
    air = {'of': 'air_frac', 'colour': 'pressure'}
    bind.append(dict(air, flow='air_in', speed=2.0, by='p_amb'))
    for q in range(4):
        bind.append(dict(air, flow=f'comp_{q}', speed=2.0, by='c_p4'))
    for q in range(2):
        bind.append({'flow': f'fuel_{q}', 'of': 'fuel_v', 'speed': 0.8, 'colour': 'pressure', 'by': 'gas_p'})
    for q in range(3):
        bind.append({'flow': f'flame_{q}', 'of': 'flame_v', 'speed': 1.5, 'colour': 'heat', 'by': 'tit'})
    for q in range(4):
        bind.append(dict(air, flow=f'turb_{q}', speed=3.0, by='t_p1'))
    for q in range(2):
        bind.append(dict(air, flow=f'exhaust_{q}', speed=2.5, by='p_amb'))
    bind += [
        {'at': 'brg1_housing', 'show': 'rpm'},
        {'at': 'exhaust', 'show': 'exh_t'},
        {'at': 'rotor', 'sound': 'compressor_pass', 'gain': {'of': 'speed', 'table': [[0, 0], [0.05, 0.15], [1, 1]]},
         'pitch': {'of': 'speed', 'table': [[0, 0.05], [1.2, 1.2]]}},
        {'at': 'liner_01', 'sound': 'combustion', 'gain': {'of': 'flame_v', 'table': [[0, 0], [1, 1]]}},
        {'at': 'exhaust', 'sound': 'exhaust_rumble', 'gain': {'of': 'air_frac', 'table': [[0, 0], [1, 1]]}},
        {'at': 'brg1_housing', 'sound': 'sfc_whine', 'gain': {'of': 'sfc_on', 'table': [[0, 0], [1, 0.6]]}},
    ]
    bench = {
        'format': 'walkdown-plant-bench', 'version': 1, 'part': 'gas_turbine',
        'sources': SOURCES_BENCH,
        'values': after,
        'ops': [{'at': 'intake', 'do': 'set', 'input': 'ambient_t', 'range': [0, 50], 'title': 'Ambient temperature'}],
        'faults': [
            {'id': 'flameout', 'at': 'liner_02', 'text': 'Flame out in the cans (a lean blow-out)',
             'set': {'flameout': 1}, 'repair': {'flameout': 0}},
            {'id': 'governor', 'at': 'bench', 'text': 'Speed governor fault: the speed set 15 % high',
             'set': {'gov_fault': 1}, 'repair': {'gov_fault': 0}},
            {'id': 'tc_fault', 'at': 'exhaust', 'text': 'Exhaust thermocouple 7 reading 80 K low: the spread',
             'set': {'tc_fault': 1}, 'repair': {'tc_fault': 0}},
            {'id': 'surge', 'at': 'cvanes_upper', 'text': 'Compressor surge: the air flow breaks down',
             'set': {'surge': 1}, 'repair': {'surge': 0}},
            {'id': 'rub', 'at': 'brg2_upper', 'text': 'Rotor rubbing: bearing vibration high',
             'set': {'vib_fault': 1}, 'repair': {'vib_fault': 0}},
            {'id': 'oil_leak', 'at': 'brg1_housing', 'text': 'Lube oil leak: the bearings\' oil pressure falls',
             'set': {'oil_leak': 1}, 'repair': {'oil_leak': 0}},
            {'id': 'lube_pump', 'at': 'bench', 'text': 'AC lube oil pump lost: the DC emergency pump takes over',
             'set': {'lac_fault': 1}, 'repair': {'lac_fault': 0}},
            {'id': 'gas_low', 'at': 'fuel_ring', 'text': 'Fuel gas pressure low: a start is refused',
             'set': {'gas_low': 1}, 'repair': {'gas_low': 0}},
        ],
        # at standstill on its turning gear, the AC lube oil pump running, oil on the bearings; the compressor's
        # discharge at the bellmouth's 1 bar (the plant's lags start from 0, which the gas path's tables don't reach)
        'start': {'lac_cmd': 1, 'tg_cmd': 1, 'lube_p': 2.5, 'cpd': 1, 'cpd_slow': 1},
        'bind': bind,
        'legends': {
            'heat': {'unit': '°C', 'table': [[20, '#2c7bb6'], [150, '#abd9e9'], [400, '#ffffbf'], [700, '#fdae61'],
                                             [1000, '#d7191c'], [1400, '#fff2c0']]},
            'pressure': {'unit': 'bar', 'table': [[1, '#2c7bb6'], [4, '#abd9e9'], [8, '#ffffbf'], [12, '#fdae61'],
                                                  [16, '#d7191c'], [32, '#67001f']]},
        },
        'readouts': ['rpm', 'exh_flow', 'cpd', 'fuel_flow', 'tit', 'exh_t', 'spread', 'lube_p', 'vib2', 'ph',
                     'slip', 'mw'],
        # the live plant's gas turbine on the bench (WORKSHOP.md §6.5): its start-up sequence's state and the shaft's
        # speed (its fuel is a product of the sequence's own values: the state brings it)
        'mirror': [{'value': 'turbine_state', 'from': {'machine': True}},
                   {'value': 'speed', 'from': {'bind': 'anim', 'channel': 'shaft'}}],
    }
    oil = '10MBV10'
    return {
        'area': 'gt1', 'prefix': 'gt1_',
        'rename': {'gt1_start': 'turbine', 'gen1_trip_prot': 'trip_breaker', 'gen1_prot_c': 'prot_c'},
        'at': {'10MBA10': 'rotor', '10MKC10': 'bench', '10BAC10': 'bench', '10MKA10': 'bench',
               '10MBK10AE001': 'brg1_housing', oil + 'AP001': 'bench', oil + 'AP002': 'bench',
               oil + 'CP001': 'brg1_housing', oil + 'CP002': 'brg1_housing', oil + 'CP003': 'brg1_housing',
               oil + 'CT001': 'brg1_housing', '10MBM10CB001': 'liner_02', '10MBR10CT001': 'exhaust',
               '10MBR10CT002': 'exhaust', '10MBR10CT007': 'exhaust', '10MBY10CS001': 'brg1_housing',
               '10MBD10CY001': 'brg1_upper', '10MBD10CY002': 'brg2_upper', '10MBP10CP001': 'fuel_ring'},
        'machines': ['gt1_start'], 'trips': TRIPS + [BREAKER_TRIP], 'alarms': ALARMS, 'interlocks': ['gt1_dc_auto'],
        # (the oil pumps' own ops stay off the bench: the AC pump runs from the start, the DC pump by the interlock)
        'ops': [['10MBK10AE001', 'start'], ['10MBK10AE001', 'stop'], ['10MKC10', 'start'], ['10MKC10', 'stop'],
                ['10BAC10', 'close_breaker'], ['10BAC10', 'open_breaker'], ['10MBY10CS001', 'set'],
                ['10MKA10', 'set']],
        'titles': {('10MBA10', 'start'): 'Start', ('10MBA10', 'stop'): 'Stop',
                   ('10MBK10AE001', 'start'): 'Turning gear on', ('10MBK10AE001', 'stop'): 'Turning gear off',
                   ('10MKC10', 'start'): 'Excitation on', ('10MKC10', 'stop'): 'Excitation off',
                   ('10BAC10', 'close_breaker'): 'Close the breaker', ('10BAC10', 'open_breaker'): 'Open the breaker',
                   ('10MBY10CS001', 'set'): 'Speed bias', ('10MKA10', 'set'): 'Load set point',
                   'gt1_trip_lube': 'Reset: lube oil', 'gt1_trip_flame': 'Reset: flame', 'gt1_trip_exh':
                   'Reset: exhaust temperature', 'gt1_trip_spread': 'Reset: exhaust spread', 'gt1_trip_os':
                   'Reset: overspeed', 'gt1_trip_vib': 'Reset: vibration', 'gt1_trip_surge': 'Reset: surge',
                   'gt1_trip_oil_temp': 'Reset: oil temperature', BREAKER_TRIP: 'Reset: breaker'},
        'values': TAKE_VALUES,
        'before': before,
        'bench': bench,
    }


def bench(models):
    """The gas turbine's bench file, made from the plant's gt1 model (WORKSHOP.md §6.3)."""
    from workshop import make_bench
    return make_bench.make(bench_source(), models)
