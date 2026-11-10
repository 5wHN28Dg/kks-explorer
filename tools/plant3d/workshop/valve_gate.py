"""The gate valve's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a bolted-bonnet, outside-screw-and-yoke
gate valve with a rising stem and a handwheel on top. Its geometry is the kit's generator, apps/plant3d/kit/
parts_valves.gd `_rising` (valve_gate with a manual handwheel on top; the gear, electric and hydraulic actuators
have no tree yet).

The parts and their order follow the Crane Pacific cast steel valves' instruction manual (the gate valve's figure,
parts list, disassembly and reassembly); the yoke is the bonnet's own, as Crane's is. Generic: no plant data. The
parameters are a manual gate valve the plant has several of (DN 300).
"""

CRANE = 'crane_csv'

SOURCES = [
    {'id': CRANE, 'cite': 'Crane ChemPharma & Energy, Pacific CSV cast steel valves, installation, operation and '
                          'maintenance manual CPE-PACIFIC-CSV-IOM-EN-LT (2018): gate valve figure p. 12, operating '
                          'the handwheel §2.1 p. 13 (the handwheel on the stem nut under the handwheel nut), parts '
                          'list, disassembly and reassembly p. 14',
     'url': 'https://cranecpe.com/wp-content/uploads/CPE-PACIFIC-CSV-IOM-EN-LT-2018_23_10.pdf'},
]

PARAMS = {'dn': 300, 'actuator': 'manual'}


def _c(name, does, material, sources=(CRANE,)):
    return {'name': name, 'does': does, 'material': material, 'sources': list(sources)}


def components():
    return {
        'body': _c('Valve body', 'Holds the pressure and the flow\'s way straight through. It stays bolted between its '
                   'pipe flanges when the valve is opened.', 'Cast carbon steel'),
        'seat_rings': _c('Seat rings', 'The two rings the wedge closes against, one each side of it. They stay in '
                         'the body: the maintenance steps never take them out.',
                         'Steel, hard-faced at the seat'),
        'wedge': _c('Wedge', 'The closure member: a wedge whose two faces close on the seat rings. Lifted by the '
                    'stem clear of the bore, the valve is fully open.', 'Cast steel, '
                    'hard-faced at the seat'),
        'stem': _c('Stem', 'Carries the wedge on its T-head. Its thread runs in the stem nut, so turning the '
                   'handwheel raises or lowers it; how far it stands out of the yoke shows how far the valve is '
                   'open.', 'Stainless steel'),
        'bonnet': _c('Bonnet and yoke', 'Closes the body over the wedge on its gasket, carries the packing box '
                     'round the stem and, in its yoke, the stem nut.', 'Cast carbon steel'),
        'packing': _c('Packing, gland and gland flange', 'Rings of graphite packing squeezed round the stem by the '
                      'gland under the gland flange, so the process cannot leak along the stem.',
                      'Graphite rings, steel gland and flange'),
        'stem_nut': _c('Stem nut', 'Turns in the yoke\'s head, held by its retainer: the handwheel turns it, and its '
                       'thread drives the stem up or down.', 'Bronze'),
        'handwheel': _c('Handwheel', 'Turned by hand to open (anticlockwise) or close the valve; it sits on the '
                        'stem nut under the handwheel nut.', 'Cast iron or steel'),
    }


def _step(place, text, needs=(), why=None, sources=(CRANE,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# The reassembly (Crane p. 14), each part in its place, a part's parent first: Crane takes the bonnet off with its
# yoke, the stem, the wedge, the packing and the handwheel as one, and takes them apart on the bench (said in the
# steps' reasons). Taking apart is the reverse.
ASSEMBLY = [
    _step('body', 'The body stays bolted between its pipe flanges.',
          why='The bonnet, the stem and the wedge all come out upwards, without disturbing the pipes.'),
    _step('seat_rings', 'The seat rings stay in the body: look at their faces for cuts and wear.',
          [('body', 'The seat rings are in the body.', 'The body stays on its pipes.')],
          why='Crane\'s steps never take the seat rings out of the body.'),
    _step('wedge', 'Lower the wedge into the body between its seat rings, the way round it was marked when it came '
          'out.', [('seat_rings', 'The wedge closes on the seat rings: they are there first.',
                    'Lift the wedge out before anything is done to the seat rings.')],
          why='In the shop the wedge is hung on the stem\'s T-head and goes in with the bonnet assembly; the steps '
              'here fit each part in its place.'),
    _step('stem', 'Put the stem\'s T-head down into the wedge\'s slot.',
          [('wedge', 'The stem carries the wedge: put the wedge in first.',
            'Draw the stem up out of the wedge before the wedge comes out.')]),
    _step('bonnet', 'Fit a new bonnet gasket and lower the bonnet over the stem onto the body.',
          [('stem', 'The bonnet goes on over the stem: put the stem in first.',
            'Lift the bonnet off before the stem comes out.')],
          why='Crane lifts the bonnet off with the stem and the wedge on it, then takes the wedge off the stem and '
              'draws the stem out by turning the handwheel.'),
    _step('bonnet_bolts', 'Fit the bonnet studs and nuts and tighten them evenly, crosswise.',
          [('bonnet', 'The nuts hold the bonnet down: set it on first.',
            'Take the bonnet nuts off before the bonnet is lifted.')]),
    _step('stem_nut', 'Screw the stem nut onto the stem\'s thread in the yoke\'s head and fit its retainer.',
          [('bonnet', 'The stem nut turns in the yoke\'s head: set the bonnet on first.',
            'Take the stem nut out before the bonnet comes off.'),
           ('stem', 'The stem\'s thread runs in the stem nut: put the stem in first.',
            'Take the stem nut off before the stem comes out.')],
          why='Crane takes the handwheel and the stem nut off the bonnet last, on the bench, and the stem nut only '
              'when it needs renewing (its retainer\'s set screws or tack welds off first); here they come off the '
              'bonnet before it is lifted, a part\'s own parts first.'),
    _step('handwheel', 'Put the handwheel on the stem nut and screw the handwheel nut down on it.',
          [('stem_nut', 'The handwheel sits on the stem nut: fit it first.',
            'Take the handwheel off before the stem nut.')]),
    _step('packing', 'Put new packing rings over the stem into the packing box, then the gland and the gland '
          'flange, and tighten the gland\'s eyebolt nuts evenly.',
          [('bonnet_bolts', 'Pack the stem when the bonnet is bolted down.',
            'Take the gland off and the packing out before the bonnet nuts.')],
          why='Taking apart, Crane loosens the gland\'s nuts first, then the bonnet\'s, and hooks the old packing out '
              'once the bonnet is on the bench.'),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'valve_gate',
        'params': PARAMS,
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'bonnet_bolts': {'name': '12 bonnet studs and nuts', 'joins': ['bonnet', 'body'], 'sources': [CRANE]},
        },
        'assembly': ASSEMBLY,
        # the X-ray takes the body, the bonnet and the packing; the cutaway opens the valve along the flow through the
        # stem, so the wedge shows between its seat rings in section; the handwheel stays whole
        'views': {'xray_all': ['body', 'bonnet', 'packing'],
                  'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['stem', 'handwheel', 'stem_nut']}},
    }
