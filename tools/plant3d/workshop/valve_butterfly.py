"""The butterfly valve's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a resilient-seated butterfly
valve with a one-piece shaft under a part-turn electric actuator. Its geometry is the kit's generator,
apps/plant3d/kit/parts_valves.gd `_quarter` (valve_butterfly with an electric actuator; the lever, gear, pneumatic
and hydraulic ones have no tree yet).

The valve's parts and order follow Bray's resilient seated butterfly valves' instruction manual (the Series 35/36,
whose disc is held on its shaft by taper pins: the actuator off, the gland, the pins, the shaft out through the top
with its bushing and packing, the disc, the seat), the actuator AUMA's SQ part-turn actuators' operation
instructions (the handwheel, the coupling, servicing). The actuator's gearing, motor and controls are not drawn: it
is one part, as the plant draws it. Generic: no plant data. The parameters are an electric butterfly valve the plant
has six of (DN 250).
"""

BRAY = 'bray_bf'
AUMA = 'auma_sq'

SOURCES = [
    {'id': BRAY, 'cite': 'Bray International, resilient seated butterfly valves, installation, operation and '
                         'maintenance manual EN_BR_IOM_BF_ALL_20250604 (2025): Series 35/36 (appendix H), disassembly '
                         '§13.1 and assembly §13.2 p. 28, exploded view and parts list p. 29',
     'url': 'https://www.bray.com/docs/default-source/manuals-guides/iom-manuals/en_br_iom_bf_all_8-16-2023.pdf'},
    {'id': AUMA, 'cite': 'AUMA, part-turn actuators SQ 05.2-SQ 14.2 / SQR 05.2-SQR 14.2 Control unit: '
                         'electromechanical, operation instructions Y005.559/003 (PR00442/en/1.26): fitting the '
                         'handwheel §5.2 p. 12, mounting on the valve with the coupling §5.3.1 pp. 13-15, end stops '
                         '§10.1 p. 27, servicing §13 p. 41',
     'url': 'https://www.auma.com/documents/sites/aumanet-services-internetdokumente/AUMA%20Pre%20und%20Aftersales%20'
            'Dokumente/betriebsanleitungen/antriebe_ohne_steuerung/schwenkantriebe/ba_sqr2_05_14_norm_en.pdf'},
]

PARAMS = {'dn': 250, 'actuator': 'electric'}


def _c(name, does, material, sources=(BRAY,)):
    return {'name': name, 'does': does, 'material': material, 'sources': list(sources)}


def components():
    return {
        'body': _c('Valve body', 'Holds the seat and the shaft between the pipe\'s flanges, the line\'s bolts round '
                   'it; its neck carries the actuator.', 'Ductile iron'),
        'liner': _c('Seat (liner)', 'A rubber ring lining the bore: the disc\'s edge presses into it to close the '
                    'valve tight. It comes out last, squeezed into an oval.', 'EPDM or nitrile rubber'),
        'disc': _c('Disc', 'Turns a quarter of a turn on its shaft: across the bore it closes the valve, edge-on it '
                   'opens it. Held on the shaft by taper pins.', 'Stainless steel or coated ductile iron'),
        'shaft': _c('Shaft', 'Carries the disc and turns it; its top end takes the actuator\'s coupling.',
                    'Stainless steel'),
        'packing': _c('Shaft bushing and packing', 'Guide the shaft in the neck and seal it, under the packing '
                      'gland.', 'Bronze bushing, PTFE packing'),
        'actuator': _c('Electric part-turn actuator', 'A motor and a worm gear that turn the shaft a quarter of a '
                       'turn between its end stops, with its limit and torque switches. It is one part here: its '
                       'maker\'s service opens it.', 'Aluminium housing, motor, gearing, switches', (AUMA, BRAY)),
        'coupling': _c('Coupling', 'Joins the actuator\'s output to the shaft\'s top: it goes on the shaft first and '
                       'the actuator over it.', 'Steel', (AUMA,)),
        'indicator': _c('Position indicator', 'A disc on top that turns with the valve: along the pipe is open, '
                        'across it closed.', 'Plastic', (AUMA,)),
        'handwheel': _c('Handwheel', 'Works the valve by hand when the motor is not running.',
                        'Cast iron or aluminium', (AUMA,)),
    }


def _step(place, text, needs=(), why=None, sources=(BRAY,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# The assembly (Bray §13.2, then AUMA §5.3.1), each part in its place, a part's parent first. Taking apart is the
# reverse, Bray's §13.1: the actuator off, the gland and the pins, the shaft out through the top, the disc, the seat.
ASSEMBLY = [
    _step('body', 'The body sits on the bench, its bore across.',
          why='Bray takes the valve out of the line and lays it down with the taper pins\' nuts up, the disc on wooden '
              'blocks, before the shaft is driven out.'),
    _step('liner', 'Squeeze the seat into an oval and work it into the body\'s bore, its shaft holes on the '
          'body\'s.', [('body', 'The seat lines the body\'s bore.', 'The body stays.')]),
    _step('disc', 'Push the disc into the seat, its hub\'s bore on the shaft holes.',
          [('liner', 'The disc closes in the seat: fit the seat first.', 'Take the disc out before the seat.')]),
    _step('shaft', 'Drive the shaft down through the neck and the disc\'s hub, and fit the taper pins and their '
          'nuts.', [('disc', 'The shaft goes through the disc\'s hub: put the disc in first.',
                     'Drive the taper pins and the shaft out before the disc comes out.')],
          why='The disc\'s pins and the bottom plate under the shaft are not drawn: the pins come out before the '
              'shaft, the bottom plate and its thrust bearing before the pins.'),
    _step('packing', 'Slide the bushing and the packing over the shaft into the neck and fit the packing gland.',
          [('shaft', 'The packing seals round the shaft: put the shaft in first.',
            'The packing comes out with the shaft.')]),
    _step('actuator', 'Set the actuator onto the neck\'s top flange over the coupling, the valve and the actuator '
          'both at the same end position.',
          [('packing', 'Fit the gland before the actuator goes on.', 'Take the actuator off first.')],
          why='Isolate the actuator\'s supply before anything is undone. Its end stops are set again after it is '
              'mounted.', sources=(AUMA, BRAY)),
    _step('coupling', 'The coupling joins the actuator\'s output to the shaft\'s top.',
          [('actuator', 'The coupling is the actuator\'s output: set the actuator on first.',
            'It comes off with the actuator.')],
          why='AUMA fits the coupling on the shaft first and lowers the actuator over it.', sources=(AUMA,)),
    _step('indicator', 'The position indicator turns with the actuator\'s output, on its top.',
          [('actuator', 'The indicator is the actuator\'s: set the actuator on first.',
            'It comes off with the actuator.')], sources=(AUMA,)),
    _step('handwheel', 'Put the handwheel on its input shaft and fit its retaining ring.',
          [('actuator', 'The handwheel is the actuator\'s: set the actuator on first.',
            'Take the handwheel off once the actuator is off the valve.')], sources=(AUMA,)),
    _step('actuator_bolts', 'Fit the actuator\'s mounting bolts and tighten them crosswise.',
          [('actuator', 'The bolts hold the actuator\'s flange: set it on first.',
            'Take the mounting bolts out first.')], sources=(AUMA, BRAY)),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'valve_butterfly',
        'params': PARAMS,
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'actuator_bolts': {'name': '4 actuator mounting bolts', 'joins': ['actuator', 'body'],
                               'sources': [AUMA, BRAY]},
        },
        'assembly': ASSEMBLY,
        # the X-ray takes the body; the cutaway opens it along the flow through the shaft, so the disc shows in the
        # seat in section; the actuator stays whole
        'views': {'xray_all': ['body', 'liner'],
                  'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['actuator', 'coupling', 'indicator', 'handwheel', 'shaft']}},
    }
