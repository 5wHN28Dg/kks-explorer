"""The globe valve's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a bolted-bonnet globe valve with a
rising stem under a multi-turn electric actuator. Its geometry is the kit's generator, apps/plant3d/kit/
parts_valves.gd `_rising` (valve_globe with an electric actuator; the manual, gear, pneumatic and hydraulic ones have
no tree yet).

The valve's parts and order follow the Crane Pacific cast steel valves' instruction manual (the globe valve's figure,
parts list, disassembly and reassembly; a gear or motor operated valve's operator off first), the actuator the AUMA
SA multi-turn actuators' operation instructions (the handwheel, output drive type A with its stem nut, servicing).
The actuator's gearing, motor and controls are not drawn: it is one part, as the plant draws it. Generic: no plant
data. The parameters are an electric globe valve the plant has four of (DN 50, PN 160).
"""

CRANE = 'crane_csv'
AUMA = 'auma_sa'

SOURCES = [
    {'id': CRANE, 'cite': 'Crane ChemPharma & Energy, Pacific CSV cast steel valves, IOM manual '
                          'CPE-PACIFIC-CSV-IOM-EN-LT (2018): globe valve figure p. 16, parts list, '
                          'disassembly and reassembly p. 18; gear or motor operated valves §J p. 42 (the operator '
                          'unscrewed off the stem with its handwheel)',
     'url': 'https://cranecpe.com/wp-content/uploads/CPE-PACIFIC-CSV-IOM-EN-LT-2018_23_10.pdf'},
    {'id': AUMA, 'cite': 'AUMA, multi-turn actuators SA 07.2-SA 16.2 / SAR 07.2-SAR 16.2, operation '
                         'instructions Y004.750/003 (PR00242/en/1.26): fitting the '
                         'handwheel §5.2 p. 13, output drive type A (a mounting flange with the stem nut in an axial '
                         'bearing, taking the thrust) §5.3.2 pp. 14-17, servicing §13 pp. 46-47',
     'url': 'https://www.auma.com/documents/sites/aumanet-services-internetdokumente/AUMA%20Pre%20und%20Aftersales%20'
            'Dokumente/betriebsanleitungen/antriebe_ohne_steuerung/drehantriebe/ba_sar2_07_16_norm_en.pdf'},
]

PARAMS = {'dn': 50, 'rating': 'pn160', 'actuator': 'electric'}


def _c(name, does, material, sources=(CRANE,)):
    return {'name': name, 'does': does, 'material': material, 'sources': list(sources)}


def components():
    return {
        'body': _c('Valve body', 'Holds the pressure and turns the flow up through the seat and out again. It stays '
                   'welded or bolted in its pipe when the valve is opened.', 'Forged or cast steel'),
        'seat_ring': _c('Seat ring', 'The ring the disc closes on. It stays in the body: the maintenance steps never '
                        'take it out.', 'Steel, hard-faced at the seat'),
        'disc': _c('Disc', 'The closure member: lowered onto the seat ring it shuts the flow; lifted, it opens it a '
                   'little at a time. It hangs on the stem\'s end, held by a lock nut or a pin.',
                   'Steel, hard-faced at the seat'),
        'stem': _c('Stem', 'Lifts and lowers the disc. Its thread runs in the actuator\'s stem nut; a block on it in '
                   'the yoke\'s window points to the travel on the yoke\'s scale.', 'Stainless steel'),
        'bonnet': _c('Bonnet and yoke', 'Closes the body over the disc on its gasket, carries the packing box round '
                     'the stem, and the actuator on its yoke\'s top flange.', 'Forged or cast steel'),
        'packing': _c('Packing, gland and gland flange', 'Rings of graphite packing squeezed round the stem by the '
                      'gland under the gland flange, so the process cannot leak along the stem.',
                      'Graphite rings, steel gland and flange'),
        'actuator': _c('Electric actuator', 'A motor and a worm gear that turn the stem nut, with its limit and torque '
                       'switches and local controls. It is one part here: its maker\'s service opens it.',
                       'Aluminium housing, motor, gearing, switches', (AUMA, CRANE)),
        'stem_nut': _c('Stem nut (output drive type A)', 'Turns in the actuator\'s output drive on its thrust bearing '
                       'and drives the stem up or down; it carries the valve\'s thrust into the actuator\'s flange.',
                       'Bronze', (AUMA,)),
        'display': _c('Local display', 'Shows the valve\'s position and the actuator\'s state beside its local '
                      'controls.', 'Glass window', (AUMA,)),
        'handwheel': _c('Handwheel', 'Works the valve by hand when the motor is not running.', 'Cast iron or aluminium', (AUMA,)),
    }


def _step(place, text, needs=(), why=None, sources=(CRANE,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# The reassembly (Crane p. 18, then the operator, Crane §J and AUMA §5.3.2), each part in its place, a part's parent
# first. Taking apart is the reverse: the actuator off first, then Crane's steps.
ASSEMBLY = [
    _step('body', 'The body stays in its pipe.',
          why='The bonnet, the stem and the disc all come out upwards, without disturbing the pipe.'),
    _step('seat_ring', 'The seat ring stays in the body: look at its face for cuts and wear.',
          [('body', 'The seat ring is in the body.', 'The body stays in its pipe.')],
          why='Crane\'s steps never take the seat ring out of the body.'),
    _step('disc', 'Set the disc on the seat ring.',
          [('seat_ring', 'The disc closes on the seat ring: it is there first.',
            'Lift the disc out before anything is done to the seat ring.')]),
    _step('stem', 'Put the stem\'s end into the disc and fix the disc on it with its lock nut or pin.',
          [('disc', 'The stem carries the disc: put the disc in first.',
            'Free the disc from the stem (its lock nut\'s tack welds ground off, or its pin out) before the disc '
            'comes out.')],
          why='In the shop the disc is fixed on the stem and goes in with the bonnet assembly; the steps here fit each '
              'part in its place.'),
    _step('bonnet', 'Fit a new bonnet gasket and lower the bonnet over the stem onto the body.',
          [('stem', 'The bonnet goes on over the stem: put the stem in first.',
            'Lift the bonnet off before the stem comes out.')]),
    _step('bonnet_bolts', 'Fit the bonnet studs and nuts and tighten them evenly, crosswise.',
          [('bonnet', 'The nuts hold the bonnet down: set it on first.',
            'Take the bonnet nuts off before the bonnet is lifted.')]),
    _step('packing', 'Put new packing rings over the stem into the packing box, then the gland and the gland '
          'flange, and tighten the gland bolts evenly.',
          [('bonnet_bolts', 'Pack the stem when the bonnet is bolted down.',
            'Take the gland off and the packing out before the bonnet nuts.')],
          why='Taking apart, Crane loosens the gland bolts first, then the bonnet nuts, and takes the packing out '
              'once the bonnet is off.'),
    _step('actuator', 'Sling the actuator over the stem onto the yoke\'s top flange and turn its handwheel until the '
          'flanges meet.',
          [('packing', 'Pack the stem before the actuator goes on.',
            'Take the actuator off before the packing.')],
          why='Crane takes a motor operated valve\'s operator off first: its mounting bolts out, then it is unscrewed '
              'off the stem by turning the handwheel towards closed, and lifted off. AUMA screws the output drive '
              'onto the stem first and sets the actuator on it, its dogs engaging.', sources=(CRANE, AUMA)),
    _step('stem_nut', 'The stem nut turns in the actuator\'s output drive, on the stem\'s thread.',
          [('actuator', 'The stem nut is the actuator\'s output drive: set the actuator on first.',
            'Take the stem nut out of the actuator once it is off the valve.')],
          why='AUMA takes the stem nut out of the output drive (its spigot ring off) to machine it to the stem\'s '
              'thread, and greases it going back.', sources=(AUMA,)),
    _step('display', 'The local display is in the actuator\'s controls\' cover.',
          [('actuator', 'The display is the actuator\'s: set the actuator on first.',
            'It comes off with the actuator.')], sources=(AUMA,)),
    _step('handwheel', 'Put the handwheel on its input shaft and fit its retaining ring.',
          [('actuator', 'The handwheel is the actuator\'s: set the actuator on first.',
            'Take the handwheel off once the actuator is off the valve.')], sources=(AUMA,)),
    _step('actuator_bolts', 'Fit the actuator\'s mounting bolts and tighten them crosswise.',
          [('actuator', 'The bolts hold the actuator\'s flange: set it on first.',
            'Take the mounting bolts out first.'),
           ('handwheel', 'Turn the handwheel to bring the flanges together before the bolts.',
            'Take the bolts out before the handwheel comes off.')],
          why='Isolate the actuator\'s supply before anything is undone.', sources=(CRANE, AUMA)),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'valve_globe',
        'params': PARAMS,
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'bonnet_bolts': {'name': '8 bonnet studs and nuts', 'joins': ['bonnet', 'body'], 'sources': [CRANE]},
            'actuator_bolts': {'name': '4 actuator mounting bolts', 'joins': ['actuator', 'bonnet'],
                               'sources': [CRANE, AUMA]},
        },
        'assembly': ASSEMBLY,
        # the X-ray takes the body, the bonnet, the packing and the actuator; the cutaway opens the upstream half,
        # across the flow through the stem, so the seat and the disc show in section; the actuator stays whole
        'views': {'xray_all': ['body', 'bonnet', 'packing', 'actuator'],
                  'cutaway': {'planes': [{'normal': [0, -1, 0], 'offset': 0}],
                              'keep': ['stem', 'actuator', 'stem_nut', 'display', 'handwheel']}},
    }
