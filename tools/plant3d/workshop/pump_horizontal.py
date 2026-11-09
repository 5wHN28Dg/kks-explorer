"""The horizontal pump's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a single-stage end-suction back
pull-out centrifugal pump (the OH1 configuration in API 610's terms) on a baseplate, driven by a foot-mounted motor
through a spacer coupling under a guard. Its geometry is the kit's generator, apps/plant3d/kit/parts_rotating.gd `pump_horizontal` (the
end-suction branch; the multi-stage barrel pump's tree is not built yet), and its motor is the motor kind's tree from
the same helper (`motor_h`): its words, fasteners and assembly come from tools/plant3d/workshop/motor.py, written once.

The take-apart order follows the Goulds 3196 i-FRAME manual's maintenance chapter (drain, coupling guard, coupling,
back pull-out assembly, impeller, seal chamber cover and seal, power end: the shaft assembly out of the frame at the
coupling end, the bearings off the shaft) and the Flowserve Mark 3 ISO instructions (§6.8: the same order, the shaft
"towards the coupling end"); reassembly is their reverse (Goulds' reassembly chapter, Flowserve §6.10). The motor's
order is derived from how it is built (motor.py). Generic: no plant data. The parameters are an end-suction pump the
plant has three of, so that the Workshop shows the pump a trainee walks past (the plant's first horizontal pump is a
multi-stage feed pump, whose tree is later work).
"""

from workshop import motor

GOULDS = 'goulds_3196'
FLOWSERVE = 'flowserve_mk3'
API610 = 'api610_types'
DOE = 'doe_pumps'
KSB_VANE = 'ksb_vane'

SOURCES = [
    {'id': GOULDS, 'cite': 'ITT Goulds Pumps, Installation, operation and maintenance manual, model 3196 i-FRAME, '
                           'IOM.3196.i-FRAME.en-US.2017-03: maintenance pp. 73-84 (drain the pump, remove the '
                           'coupling, the back pull-out assembly, the impeller, the seal-chamber cover, disassemble '
                           'the power end), reassembly pp. 102-132',
     'url': 'https://inspectapedia.com/water/Goulds-3196-Pump-IO-Manual.pdf'},
    {'id': FLOWSERVE, 'cite': 'Flowserve, Durco Mark 3 ISO frame mounted pumps, user instructions PCN 85392719 '
                              '12-14 (E): §6.8.1 the power end out of the casing, §6.8.2 impeller, §6.8.3 cover and '
                              'seal, §6.8.4 the shaft and bearings towards the coupling end, §6.10 assembly',
     'url': 'https://www.axflow.com/globalassets/catalog/um/flowserve-85392719-e.pdf'},
    {'id': API610, 'cite': 'Wermac, Centrifugal pumps according to API 610: the pump types (OH1 a flexibly coupled '
                           'horizontal pump with foot support, OH2 centreline mounted, BB between bearings)',
     'url': 'https://www.wermac.org/equipment/pumps_centrifugal_api.html'},
    {'id': DOE, 'cite': 'US DOE Fundamentals Handbook, Mechanical Science, DOE-HDBK-1018/1-93, Pumps: the volute '
                        'expands in cross-sectional area as it wraps round the casing',
     'url': 'https://engineeringlibrary.org/reference/pumps-doe-handbook'},
    {'id': KSB_VANE, 'cite': 'KSB, Centrifugal pump lexicon: Vane (the outlet angle of a radial impeller below 90 '
                             'degrees, a backward-curved vane) and Direction of rotation (named as seen from the drive)',
     'url': 'https://www.ksb.com/en-global/centrifugal-pump-lexicon/article/vane-1118440'},
]

PARAMS = {'flow_m3h': 900, 'head_m': 40, 'motor_kw': 160, 'length': 3}


def _c(name, does, material, sources, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': sources}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def components():
    own = {
        'baseplate': _c('Baseplate', 'The steel frame the pump and its motor are bolted to, grouted to the floor, so '
                        'that their shafts stay in line.', 'Fabricated steel, grout', [GOULDS]),
        'volute': _c('Casing (volute)', 'Takes the water in at the suction nozzle to the impeller\'s eye and '
                     'gathers it from the impeller\'s tips in a passage that grows round the casing to the discharge '
                     'nozzle. It stays on its pipes when the pump is opened.', 'Cast iron or cast steel',
                     [GOULDS, DOE, API610]),
        'frame': _c('Bearing frame (power end)', 'Holds the shaft in its two bearings and the oil that lubricates '
                    'them; with the casing cover, the shaft, the seal and the impeller it is the back pull-out '
                    'assembly, drawn out of the casing without disturbing the pipes.', 'Cast iron',
                    [GOULDS, FLOWSERVE]),
        'casing_cover': _c('Casing cover (seal chamber)', 'Closes the casing behind the impeller; the mechanical '
                           'seal sits in its bore round the shaft.', 'Cast iron or cast steel', [GOULDS, FLOWSERVE]),
        'impeller': _c('Impeller', 'A closed impeller: its six vanes, curved back against the way it turns, fling '
                       'the water outwards from the eye into the volute. Screwed or keyed onto the shaft\'s end.',
                       'Cast iron, bronze or stainless steel', [GOULDS, KSB_VANE]),
        'shaft': _c('Shaft', 'Carries the impeller at one end and the coupling hub at the other, turning in the '
                    'frame\'s bearings.', 'Carbon or stainless steel', [GOULDS, FLOWSERVE]),
        'seal': _c('Mechanical seal', 'Stops the pumped water leaking along the shaft: a rotating face on the shaft '
                   'runs against a stationary seat in the cover\'s gland.', 'Carbon and silicon carbide faces, '
                   'elastomer and stainless steel parts', [GOULDS]),
        'bearing_ib': _c('Inboard bearing', 'The bearing nearer the impeller: carries the radial load.',
                         'Bearing steel', [GOULDS, FLOWSERVE]),
        'bearing_ob': _c('Outboard (thrust) bearing', 'The bearing at the coupling end: carries the radial and the '
                         'axial thrust.', 'Bearing steel', [GOULDS, FLOWSERVE]),
        'end_cover': _c('Bearing end cover', 'Closes the frame at the coupling end round the shaft, holding the '
                        'outboard bearing in place and the oil in.', 'Cast iron', [GOULDS, FLOWSERVE]),
        'coupling': _c('Spacer coupling', 'Joins the pump\'s shaft to the motor\'s; its spacer lets the back '
                       'pull-out assembly come out without moving the motor. Drawn here as one piece with its hubs.',
                       'Steel hubs and spacer, flexible elements', [GOULDS, FLOWSERVE]),
        'guard': _c('Coupling guard', 'Covers the turning coupling; the pump never runs without it.', 'Sheet steel, '
                    'painted yellow', [GOULDS]),
    }
    return dict(own, **motor.components('motor'))


def _step(place, text, needs=(), why=None, sources=(GOULDS,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# The pump's reassembly (Goulds pp. 102-132, Flowserve §6.10): the motor stands on the baseplate throughout (the spacer
# coupling lets the back pull-out assembly come out without moving it); the power end on the bench (the shaft with its
# bearings already on it into the frame, its end cover), the seal and the casing cover, the impeller; the back pull-out
# assembly into the casing with its bolts; the coupling and the guard. A part goes into its parent wherever that
# stands; the needs are only what the manuals say must come first. The bearings ride with the shaft (its children in
# the tree): they come off it on the bench once it is out of the frame, so no step makes the shaft wait for them.
ASSEMBLY = [
    _step('baseplate', 'The baseplate stays grouted to the floor.'),
    _step('volute', 'The casing stays bolted to the baseplate and to its suction and discharge pipes.',
          why='The back pull-out design lets the rest come out without disturbing the pipes.',
          sources=(GOULDS, FLOWSERVE)),
    _step('motor', 'The motor stands on the baseplate, on its shims.',
          why='The spacer coupling lets the back pull-out assembly come out without moving the motor; its own parts '
              'come apart as the motor kind\'s do.', sources=(GOULDS, motor.SIMOTICS)),
] + motor.assembly('motor', first=False) + [
    _step('frame', 'Set the bearing frame on the bench.', sources=(GOULDS, FLOWSERVE)),
    _step('shaft', 'Slide the shaft, its bearings already on it, into the frame from the coupling end.',
          [('frame', 'The shaft goes into the bearing frame: set the frame down first.',
            'Draw the shaft out of the frame before the frame is moved.')], sources=(GOULDS, FLOWSERVE)),
    _step('bearing_ib', 'The inboard bearing is fitted on the shaft on the bench, before the shaft goes into the '
          'frame: heated, pressed on its inner race only.',
          why='It comes off the shaft once the shaft is out of the frame; bearings are never reused once removed.',
          sources=(GOULDS, FLOWSERVE)),
    _step('bearing_ob', 'The outboard bearing is fitted on the shaft the same way, with its locknut, before the shaft '
          'goes into the frame.', sources=(GOULDS, FLOWSERVE)),
    _step('end_cover', 'Fit the bearing end cover at the coupling end.',
          [('bearing_ob', 'The end cover holds the outboard bearing: fit the bearing first.',
            'Take the end cover off before the shaft and its bearings are drawn out.'),
           ('shaft', 'The end cover closes the frame round the shaft: put the shaft in first.',
            'Take the end cover off before the shaft is drawn out.')], sources=(GOULDS, FLOWSERVE)),
    _step('seal', 'Slide the mechanical seal onto the shaft, its faces clean.',
          [('shaft', 'The seal goes on the shaft: put the shaft in first.',
            'Take the seal off the shaft before the shaft is drawn out of the frame.')], sources=(GOULDS,)),
    _step('casing_cover', 'Fit the casing cover over the seal to the frame.',
          [('seal', 'The cover closes over the seal: fit the seal first.',
            'Take the casing cover off before the seal.')], sources=(GOULDS, FLOWSERVE)),
    _step('impeller', 'Screw the impeller onto the shaft\'s end, holding the shaft with a shaft wrench.',
          [('casing_cover', 'The impeller goes on in front of the casing cover: fit the cover first.',
            'Take the impeller off before the casing cover.'),
           ('shaft', 'The impeller goes on the shaft: put the shaft in first.',
            'Take the impeller off before the shaft is drawn out.')],
          why='It unscrews counter-clockwise seen from the impeller end.', sources=(GOULDS, FLOWSERVE)),
    _step('casing_bolts', 'Slide the back pull-out assembly into the casing with a new gasket and tighten the '
          'twelve casing bolts evenly.',
          [('frame', 'The bolts hold the back pull-out assembly to the casing: put it in first.',
            'Take the casing bolts out before the back pull-out assembly is pulled.'),
           ('casing_cover', 'The bolts clamp the casing cover: fit the cover first.',
            'Take the casing bolts out before the casing cover comes off.'),
           ('impeller', 'The impeller goes on before the back pull-out assembly goes into the casing.',
            'Pull the back pull-out assembly before the impeller comes off.')], sources=(GOULDS, FLOWSERVE)),
    _step('coupling', 'Fit the coupling\'s spacer between the hubs and check the alignment.',
          [('motor', 'The coupling joins the pump to the motor: set the motor down first.',
            'Take the coupling out before the motor is lifted.'),
           ('rotor', 'The coupling\'s motor hub sits on the motor\'s shaft: put the rotor in first.',
            'Take the coupling out before the motor\'s rotor is drawn out.'),
           ('casing_bolts', 'The coupling joins the pump\'s shaft to the motor\'s: bolt the back pull-out assembly in '
            'first.', 'Take the coupling out before the back pull-out assembly is pulled.')],
          sources=(GOULDS, FLOWSERVE)),
    _step('guard', 'Fit the coupling guard.',
          [('coupling', 'The guard covers the coupling: fit the coupling first.',
            'Take the coupling guard off first.')],
          why='The pump never runs without its coupling guard.', sources=(GOULDS, FLOWSERVE)),
]

def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'pump_horizontal',
        'params': PARAMS,
        'sources': SOURCES + motor.SOURCES,
        'components': components(),
        'fasteners': dict(motor.fasteners('motor'),
                          casing_bolts={'name': '12 casing bolts', 'joins': ['frame', 'volute', 'casing_cover'],
                                        'sources': [GOULDS, FLOWSERVE]}),
        'assembly': ASSEMBLY,
        # the X-ray takes the casing, its cover, the frame and the guard; the cutaway opens a quarter above the shaft
        # on the plates' side (as the motor's); nothing is opened while it turns (WORKSHOP.md §4.7: a rotating machine)
        'views': {'xray_all': ['volute', 'casing_cover', 'frame', 'end_cover', 'guard', 'motor', 'end_shield_de',
                               'end_shield_nde', 'fan_cowl'],
                  'cutaway': {'planes': [{'normal': [0, 0, 1], 'offset': 0}, {'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['impeller', 'shaft', 'rotor']}},
    }
