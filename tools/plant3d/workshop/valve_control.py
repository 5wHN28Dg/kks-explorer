"""The control valve's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a cage-guided globe valve with a
spring-and-diaphragm actuator and a digital positioner. Its geometry is the kit's generator,
apps/plant3d/kit/parts_valves.gd `_rising` (valve_control with a pneumatic actuator; the electric and hydraulic
actuators have no tree yet).

The body and its trim follow the Fisher easy-e ES instruction manual (packing: the actuator and the bonnet off, the
packing out; trim: the plug and stem, the cage, the seat ring; assembly the reverse), the actuator the Fisher 667
instruction manual (the spring relieved, the stem connector parted and the actuator taken off the valve, then the
spring, the casing cap screws, the upper casing, the diaphragm with its head and stem, the lower casing), with the
SAMSON 3241 valve and 3271 actuator instructions as second sources. Generic: no plant data. The parameters are a
pneumatic control valve the plant has two of (DN 150).
"""

ES = 'fisher_es'
F667 = 'fisher_667'
S3241 = 'samson_3241'
S3271 = 'samson_3271'
DVC = 'dvc6200'
IEC = 'iec_60534_1'
ISA = 'isa_75_05_01'

SOURCES = [
    {'id': ES, 'cite': 'Emerson, Fisher ES and EAS easy-e valves CL125-CL600, instruction manual D100397X012 '
                       '(2025): replacing packing pp. 8-13, trim disassembly §3.3 pp. 14-15 (plug and stem, cage, '
                       'seat ring), assembly pp. 17-19, figure 8 p. 28, cross section figure 13 p. 32',
     'url': 'https://www.emerson.com/is/content/emerson/en/final-control/flow-controls/documents/'
            'instruction-manual-fisher-es-eas-easy-e-valves-cl125-through-cl600-en-11745482.pdf'},
    {'id': F667, 'cite': 'Emerson, Fisher 667 diaphragm actuator sizes 30/30i-76/76i and 87, instruction manual '
                         'D100310X012 (2018): mounting pp. 5-6, disassembly pp. 13-14 (spring relieved, stem '
                         'connector, actuator off, spring, cap screws, upper casing, diaphragm and stem), assembly '
                         'pp. 14-15, figure 6 p. 27',
     'url': 'https://www.emerson.com/is/content/emerson/en/final-control/flow-controls/documents/'
            'd100310x012-667-diaphragm-actuator-sizes-30-30i-76-76i-and-87-fisher.pdf'},
    {'id': S3241, 'cite': 'SAMSON, Type 3241 globe valve, mounting and operating instructions EB 8015 EN (April '
                          '2024): figure 4 p. 13, mounting the actuator §5.3.2 p. 32, service §9.4.1-9.4.3 pp. 47-50 '
                          '(the body nuts undone crosswise, the bonnet lifted off with the plug and stem)',
     'url': 'https://www.samsongroup.com/document/e80150en.pdf'},
    {'id': S3271, 'cite': 'SAMSON, Type 3271 pneumatic actuator, mounting and operating instructions EB 8310 EN '
                          '(2004) pp. 6-7: the top diaphragm case lifted off, the springs, then the stem with its '
                          'plate and diaphragm',
     'url': 'https://www.samsongroup.com/document/e83100en.pdf'},
    {'id': DVC, 'cite': 'Emerson, Fisher FIELDVUE DVC6200 digital valve controller quick start guide D103556X012 '
                        '(August 2025) pp. 6-7: on a sliding-stem valve the travel feedback is a magnet assembly on '
                        'the stem connector',
     'url': 'https://www.emerson.com/is/content/emerson/en/final-control/flow-controls/documents/'
            'quick-start-guide-fieldvue-dvc6200-series-digital-valve-controllers-en.pdf'},
    {'id': IEC, 'cite': 'IEC 60534-1:2023, Industrial-process control valves, part 1: control valve terminology and '
                        'general considerations (§3.1: a control valve is a valve with an actuator that changes the '
                        'position of its closure member)',
     'url': 'https://webstore.iec.ch/publication/85733'},
    {'id': ISA, 'cite': 'ANSI/ISA-75.05.01-2019, Control valve terminology',
     'url': 'https://www.isa.org/products/ansi-isa-75-05-01-2019-control-valve-terminology'},
]

PARAMS = {'dn': 150, 'actuator': 'pneumatic'}


def _c(name, does, material, sources):
    return {'name': name, 'does': does, 'material': material, 'sources': sources}


def components():
    return {
        'body': _c('Valve body', 'Holds the pressure and the flow\'s way: in at one flange, under the seat ring, up '
                   'through it and out at the other. It stays bolted between its pipe flanges when the valve is '
                   'opened.', 'Cast carbon or stainless steel', [ES, IEC, ISA]),
        'seat_ring': _c('Seat ring', 'The ring the plug closes on: the gap between them sets the flow. Held down in '
                        'the body by the cage, on its gasket.', 'Stainless steel, hardened at the seat', [ES, S3241]),
        'cage': _c('Cage', 'Guides the plug as it moves and holds the seat ring down; the flow passes through its '
                   'windows, whose shape gives the valve its characteristic.', 'Stainless steel', [ES]),
        'plug_stem': _c('Valve plug and stem', 'The plug is the closure member: it rises off the seat ring to open '
                        'the valve. Its stem, pinned to it, leaves the body through the bonnet\'s packing.',
                        'Stainless steel', [ES, IEC]),
        'bonnet': _c('Bonnet', 'Closes the body over the trim, holds the cage down on its gasket and carries the '
                     'packing box and the actuator\'s yoke.', 'Cast carbon or stainless steel', [ES, S3241]),
        'packing': _c('Packing, follower and packing flange', 'Rings of PTFE or graphite squeezed round the stem by '
                      'the follower under the packing flange, so the process cannot leak along the stem.',
                      'PTFE or graphite rings, stainless steel follower and flange', [ES]),
        'yoke': _c('Yoke', 'The actuator\'s frame, clamped to the bonnet by the yoke locknut; the stem connector '
                   'and the travel scale are in its window.', 'Cast iron or steel', [F667]),
        'stem_connector': _c('Stem connector and travel indicator', 'Clamps the valve stem to the actuator stem; '
                             'its indicator disk shows the travel against the yoke\'s scale.', 'Steel',
                             [F667, DVC]),
        'lower_casing': _c('Lower diaphragm casing', 'The lower half of the casing round the diaphragm, bolted to '
                           'the yoke; the actuator stem passes through its middle.', 'Pressed steel', [F667]),
        'upper_casing': _c('Upper diaphragm casing', 'The upper half: the air from the positioner fills it above '
                           'the diaphragm and pushes the stem down.', 'Pressed steel', [F667, S3271]),
        'diaphragm': _c('Diaphragm', 'A rubber sheet that turns the air\'s pressure into a force on the diaphragm '
                        'head.', 'Nitrile rubber on a fabric', [F667, S3271]),
        'actuator_stem': _c('Actuator stem and diaphragm head', 'The diaphragm head (a plate under the diaphragm) on '
                            'the actuator stem: the air pushes it down, the spring back up.', 'Steel', [F667]),
        'spring': _c('Actuator spring', 'Pushes the diaphragm head up against the air: when the air goes, the '
                     'spring lifts the stem and the valve fails open.', 'Spring steel', [F667]),
        'positioner': _c('Positioner', 'Compares the 4-20 mA demand with the stem\'s travel (a magnet on the stem '
                         'connector) and sends air to the actuator until they agree.', 'Aluminium housing, '
                         'electronics, pneumatic relay', [DVC]),
        'tubing': _c('Actuator tubing', 'Carries the positioner\'s output air to the actuator\'s casing.',
                     'Stainless steel or copper tube', [DVC, F667]),
    }


def _step(place, text, needs=(), why=None, sources=(ES,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# The reassembly: the trim into the body, the bonnet and its nuts, the packing (Fisher ES pp. 17-19); the actuator on
# the bonnet and the stems joined at the stem connector (Fisher 667 pp. 5-6, 14-15); the positioner and its tubing.
# Taking apart is the reverse. A part goes into its parent wherever that stands, so the actuator is put together on
# its yoke here, where the shop does it on the bench and sets it on the valve whole (said in the steps' reasons).
ASSEMBLY = [
    _step('body', 'The body stays bolted between its pipe flanges.',
          why='The trim, the bonnet and the actuator all come out upwards, without disturbing the pipes.'),
    _step('seat_ring', 'Put a new seat ring gasket and the seat ring into the body.',
          [('body', 'The seat ring goes into the body: it is there first.', 'The body stays on its pipes.')]),
    _step('cage', 'Set the cage, with its gasket, on the seat ring.',
          [('seat_ring', 'The cage stands on the seat ring: fit the seat ring first.',
            'Lift the cage out before the seat ring.')]),
    _step('plug_stem', 'Lower the plug and stem into the cage until the plug rests on the seat ring.',
          [('cage', 'The plug is guided in the cage: fit the cage first.',
            'Take the plug and stem out before the cage.')],
          why='The plug and the stem are pinned together: they are changed as one.'),
    _step('bonnet', 'Fit a new bonnet gasket and lower the bonnet over the stem onto the body.',
          [('plug_stem', 'The bonnet goes on over the stem: put the plug and stem in first.',
            'Lift the bonnet off before the plug and stem come out.'),
           ('cage', 'The bonnet holds the cage down: fit the cage first.',
            'Lift the bonnet off before the cage comes out.')], sources=(ES, S3241)),
    _step('bonnet_bolts', 'Tighten the bonnet nuts evenly, crosswise.',
          [('bonnet', 'The nuts hold the bonnet down: set it on first.',
            'Take the bonnet nuts off before the bonnet is lifted.')], sources=(ES, S3241)),
    _step('packing', 'Slide the packing rings over the stem into the bonnet, then the follower and the packing '
          'flange, and tighten its nuts.',
          [('bonnet', 'The packing goes into the bonnet\'s packing box: fit the bonnet first.',
            'Take the packing out before the bonnet comes off.')]),
    _step('yoke', 'Set the actuator\'s yoke over the stem onto the bonnet and tighten the yoke locknut.',
          [('packing', 'Fit the packing before the actuator goes on.',
            'Take the actuator off before the packing comes out.'),
           ('bonnet_bolts', 'The yoke sits on the bonnet: bolt the bonnet down first.',
            'Take the actuator off before the bonnet nuts.')],
          why='In the shop the actuator (the yoke with its casing, diaphragm, stem and spring) is put together on '
              'the bench and set on the valve whole; the steps here fit each part on the yoke in its place, and the '
              '"taken apart" view shows the actuator lifting off whole.', sources=(F667, ES)),
    _step('lower_casing', 'Bolt the lower diaphragm casing to the yoke, the actuator stem\'s seal bushing in its '
          'middle.', [('yoke', 'The lower casing sits on the yoke: fit the yoke first.',
                       'Take the lower casing off before the yoke.')], sources=(F667,)),
    _step('spring', 'Put the spring in, under where the diaphragm head will sit.',
          [('lower_casing', 'The spring sits in the actuator: fit the lower casing first.',
            'Take the spring out before the lower casing.')],
          why='In the 667 the spring sits in the yoke under the lower casing, put in from below with its adjuster '
              'and, taking apart, relieved and taken out first; drawn here inside the lower casing, it comes out '
              'after the diaphragm head.', sources=(F667, S3271)),
    _step('actuator_stem', 'Put the actuator stem, with its diaphragm head, down through the spring and the lower '
          'casing.', [('spring', 'The diaphragm head rests on the spring: put the spring in first.',
                       'Take the stem and its head out before the spring.')], sources=(F667, S3271)),
    _step('diaphragm', 'Lay the diaphragm on the diaphragm head, its edge over the lower casing\'s flange.',
          [('actuator_stem', 'The diaphragm lies on its head: put the stem and head in first.',
            'Lift the diaphragm off before the stem and its head.')], sources=(F667, S3271)),
    _step('upper_casing', 'Set the upper casing on the diaphragm.',
          [('diaphragm', 'The upper casing closes over the diaphragm: lay it first.',
            'Lift the upper casing off before the diaphragm.')], sources=(F667, S3271)),
    _step('casing_bolts', 'Fit the casing cap screws and nuts and tighten them crosswise, a little at a time.',
          [('upper_casing', 'The cap screws hold the upper casing: set it on first.',
            'Take the cap screws out before the upper casing is lifted.')], sources=(F667, S3271)),
    _step('stem_connector', 'With the plug on its seat, bring the actuator stem down to the valve stem and clamp '
          'them together in the stem connector; set the travel indicator to the scale.',
          [('casing_bolts', 'Join the stems when the actuator is bolted together.',
            'Separate the stem connector before the actuator\'s casing comes apart.'),
           ('plug_stem', 'The connector clamps the valve stem: put the plug and stem in first.',
            'Separate the stem connector before the plug and stem come out.'),
           ('actuator_stem', 'The connector clamps the actuator stem: put it in first.',
            'Separate the stem connector before the actuator stem comes out.')],
          why='Taking apart, the spring is relieved before the stem connector is undone: never part it while the '
              'spring pushes on it.', sources=(F667,)),
    _step('positioner', 'Mount the positioner on the yoke, its feedback magnet on the stem connector.',
          [('stem_connector', 'The positioner reads the travel from the stem connector: fit it first.',
            'Take the positioner off before the stem connector.')], sources=(DVC,)),
    _step('tubing', 'Connect the tubing from the positioner\'s output to the upper casing.',
          [('positioner', 'The tubing runs from the positioner: mount it first.',
            'Disconnect the tubing first.'),
           ('upper_casing', 'The tubing goes to the upper casing: fit it first.',
            'Disconnect the tubing before the upper casing comes off.')],
          why='Shut off and vent the air supply before disconnecting anything.', sources=(DVC, F667)),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'valve_control',
        'params': PARAMS,
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'bonnet_bolts': {'name': '8 bonnet studs and nuts', 'joins': ['bonnet', 'body'], 'sources': [ES]},
            'casing_bolts': {'name': '16 casing cap screws and nuts', 'joins': ['upper_casing', 'lower_casing'],
                             'sources': [F667]},
        },
        'assembly': ASSEMBLY,
        # the X-ray takes the body, the bonnet, the casings, the cage and the packing; the cutaway opens the half on the
        # side away from the positioner, down the flow and the stem
        'views': {'xray_all': ['body', 'bonnet', 'lower_casing', 'upper_casing', 'cage', 'packing'],
                  'cutaway': {'planes': [{'normal': [-1, 0, 0], 'offset': 0}],
                              'keep': ['plug_stem', 'actuator_stem', 'stem_connector']}},
    }
