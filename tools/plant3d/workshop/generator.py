"""The generator's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): an air-cooled turbo-generator (its
coolers on top, totally enclosed water-to-air cooled) with a brushless exciter at its non-drive end, for the plant's
first instance of the kind (the gas turbine's generator). Its geometry is the kit's generator,
apps/plant3d/kit/parts_machines.gd `generator` and its `_gen_*` helpers; the scene is built with the instance's shaft
line (`context`), so its coupling stands where it does in the plant.

Where the order comes from (the user's decision, 2026-11-14: "BHEL order + WEG"): the step order of BHEL's overhaul
tender for a 250 MW turbo-generator (section B: the general activities 1-8 for taking it apart, the generator's
assembly f.1-6 and the exciter g.1-3 for putting it back). That is a CONTRACT SCOPE, NOT A MAKER'S MANUAL: it lists the
jobs a contractor does in the order of an overhaul. Its machine is hydrogen-cooled: its hydrogen seals and their seal
oil have no counterpart in the plant's air-cooled machine and are left out (said in the steps). WEG's turbogenerator
manual (S line, horizontal) is the second source: its own disassembly list (§8.1: the pipes, the electrical
connections, the heat exchanger, the bearing sensors, the shaft supported, the bearings, the rotor drawn out without
touching the core or the end windings) and its assembly (§8.2: the reverse). Generic: no plant data. No sizes, tools or
torques here: they belong to the realism programme's service file (WORKSHOP.md §4.4).
"""

BHEL = 'bhel_thri'
WEG = 'weg_tg'

SOURCES = [
    {'id': BHEL, 'cite': 'BHEL, e-tender enquiry PSER:PUR:MJA-S670:26 (ENQ:26:PP:0015:PUR:27), 20-08-2026, overhaul of '
                         'a THRI 108/44-F hydrogen-cooled 250 MW generator: a contract scope, not a maker\'s manual. '
                         'Section B.a items 1-8 PDF pp. 28-29 (printed 7-8); B.f items 1-6 and B.g PDF p. 30 '
                         '(printed 9)',
     'url': 'https://tenders.bhel.com/sites/default/files/ENQUIRY-2026-08-20-05:15:32.pdf'},
    {'id': WEG, 'cite': 'WEG, Installation, operation and maintenance manual, turbogenerators, S line, horizontal, '
                        'document 10174576 rev. 11: §8.1 disassembly and §8.2 assembly (the reverse), p. 46',
     'url': 'https://static.weg.net/medias/downloadcenter/h94/hd0/WEG-turbogenerator-10174576-manual-english-dc.pdf'},
]

SCOPE = 'BHEL\'s overhaul scope (a contract scope, not a maker\'s manual) gives the order.'


def _c(name, does, material, sources, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': list(sources)}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def components():
    return {
        'plinth': _c('Foundation block', 'The concrete block the generator stands on, in line with its turbine.',
                     'Reinforced concrete', [WEG]),
        'stator': _c('Stator', 'The frame with its laminated core and the three-phase winding in the core\'s slots: '
                     'the rotor\'s turning field induces the generator\'s voltage in it. The end turns of the winding '
                     'stand out at both ends of the core.', 'Steel frame, laminated electrical steel core, copper '
                     'winding', [WEG, BHEL]),
        'terminal_box': _c('Terminal box', 'Under the frame: the phase and neutral terminal bushings bring the '
                           'winding\'s ends out to the busbars.', 'Steel, porcelain or resin bushings', [BHEL]),
        'cooler': _c('Coolers', 'Water-to-air heat exchangers in their housing on top: the air the rotor\'s fans drive '
                     'round the machine gives up its heat to the cooling water.', 'Steel housing, copper alloy tubes',
                     [WEG, BHEL]),
        'cw_pipes': _c('Cooling water pipes', 'Bring the cooling water to the coolers and take it away.',
                       'Galvanised steel', [WEG, BHEL]),
        'es_te_up': _c('Drive-end shield, upper half', 'Closes the frame at the turbine end above the shaft line; its '
                       'bottom half is bolted to it.', 'Fabricated steel', [BHEL]),
        'es_te_lo': _c('Drive-end shield, lower half', 'Closes the frame at the turbine end below the shaft line.',
                       'Fabricated steel', [BHEL]),
        'es_ee_up': _c('Exciter-end shield, upper half', 'Closes the frame at the exciter end above the shaft line.',
                       'Fabricated steel', [BHEL]),
        'es_ee_lo': _c('Exciter-end shield, lower half', 'Closes the frame at the exciter end below the shaft line.',
                       'Fabricated steel', [BHEL]),
        'fan_shield_te': _c('Drive-end fan shield', 'The air guide round the rotor\'s fan at the turbine end.',
                            'Steel or insulating sheet', [BHEL]),
        'fan_shield_ee': _c('Exciter-end fan shield', 'The air guide round the rotor\'s fan at the exciter end.',
                            'Steel or insulating sheet', [BHEL]),
        'ped_te': _c('Drive-end bearing pedestal', 'Carries the rotor\'s journal at the turbine end in the bearing\'s '
                     'bottom half.',
                     'Cast steel, white-metal lined bearing shell', [BHEL, WEG]),
        'ped_ee': _c('Exciter-end bearing pedestal', 'Carries the rotor\'s journal at the exciter end in the bearing\'s '
                     'bottom half; insulated from its foundation against shaft currents.',
                     'Cast steel, white-metal lined bearing shell', [BHEL, WEG]),
        'brg_cap_te': _c('Drive-end bearing top half', 'The bearing\'s top half and its cap with the outer oil catcher; '
                         'its temperature sensor comes out first.', 'Cast steel, white-metal lined shell', [BHEL, WEG]),
        'brg_cap_ee': _c('Exciter-end bearing top half', 'The bearing\'s top half and its cap with the outer oil '
                         'catcher.', 'Cast steel, white-metal lined shell', [BHEL, WEG]),
        'rotor': _c('Rotor', 'One forging: its body carries the field winding in slots, held at the ends by retaining '
                    'rings; a fan at each end drives the cooling air. Turned by the turbine through the coupling.',
                    'Alloy steel forging, copper field winding, non-magnetic steel retaining rings', [WEG, BHEL]),
        'exc_cover': _c('Exciter hood', 'Encloses the exciter at the end of the shaft line.', 'Sheet steel',
                        [BHEL], sealed_why='The end grille is part of the hood: they come off as one.'),
        'exc_grille': _c('Exciter hood\'s end grille', 'Lets the exciter\'s cooling air out at the hood\'s end.',
                         'Sheet steel', [BHEL]),
        'exciter': _c('Exciter', 'A brushless exciter: its stator on its bed, its rotor (the armature, the diode wheel) '
                      'on the shaft\'s end, feeding the rotor\'s field without brushes.', 'Steel, copper windings, '
                      'diodes', [BHEL, WEG],
                      sealed_why='The exciter comes off its bed whole, its rotor in it, once it is uncoupled.'),
        'exc_rotor': _c('Exciter rotor', 'The exciter\'s armature and diode wheel on their shaft, coupled to the '
                        'generator\'s rotor.', 'Steel, copper winding, diodes', [BHEL]),
    }


def _step(place, text, needs=(), why=None, sources=(BHEL,)):
    s = {'place': place, 'text': [text], 'sources': list(sources), 'why': [(why + ' ' if why else '') + SCOPE]}
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# The guided order (reassembly): the reverse of BHEL's take-apart (B.a 1-8) and WEG's (§8.1), so that the steps undone
# one by one are BHEL's order. BHEL's own reassembly (f.1-6, g.1-3) is the same in outline: the rotor threaded in and
# the bottom end shields, alignment and coupling, the top end shields, the bearings, the exciter on its bed and its hood.
def assembly(coupled):
    steps = [
        _step('plinth', 'The foundation block stays.', sources=(WEG,)),
        _step('stator', 'The stator stays on its foundation.', [('plinth', 'The stator stands on the block.',
                                                                  'The block stays.')]),
        _step('rotor', 'Thread the rotor into the stator\'s bore from the drive end, its weight carried all the way.',
              [('stator', 'The rotor goes into the stator\'s bore: the stator is there first.',
                'Thread the rotor out before the stator is touched.')],
              why='It must never drag on the core or the end windings (WEG §8.1); the air gap is measured at both '
                  'ends before it comes out.', sources=(BHEL, WEG)),
        _step('fan_shield_te', 'Fit the drive-end fan shield round the rotor\'s fan.',
              [('rotor', 'The fan shield goes round the rotor\'s fan: thread the rotor in first.',
                'Take the fan shield out before the rotor is threaded out.')]),
        _step('fan_shield_ee', 'Fit the exciter-end fan shield the same way.',
              [('rotor', 'The fan shield goes round the rotor\'s fan: thread the rotor in first.',
                'Take the fan shield out before the rotor is threaded out.')]),
        _step('es_te_lo', 'Raise the drive end shield\'s bottom half into place under the shaft.',
              [('rotor', 'The bottom half closes under the rotor\'s shaft: thread the rotor in first.',
                'Lower the bottom half before the rotor is threaded out.')],
              why='BHEL fits the bottom halves with the rotor (f.1) and lowers them just before it comes out (a.7). '
                  'Its hydrogen seals and their seal oil are a hydrogen-cooled machine\'s: this one is air-cooled.'),
        _step('es_ee_lo', 'Raise the exciter end shield\'s bottom half into place.',
              [('rotor', 'The bottom half closes under the rotor\'s shaft: thread the rotor in first.',
                'Lower the bottom half before the rotor is threaded out.')]),
        _step('ped_te', 'Set the drive-end bearing\'s bottom half in its pedestal under the journal and lower the rotor '
              'onto it.', [('rotor', 'The bearing carries the rotor\'s journal: thread the rotor in first.',
                            'Take the bearing\'s bottom half out, the rotor held, before the rotor is threaded out.')],
              why='Its clearances are recorded as it comes out and checked as it goes back (a.7, f.3, f.5).',
              sources=(BHEL, WEG)),
        _step('ped_ee', 'Set the exciter-end bearing\'s bottom half in its pedestal the same way.',
              [('rotor', 'The bearing carries the rotor\'s journal: thread the rotor in first.',
                'Take the bearing\'s bottom half out, the rotor held, before the rotor is threaded out.')],
              why='Its pedestal is insulated: the insulation\'s resistance is checked once it is assembled (f.5).',
              sources=(BHEL, WEG)),
    ]
    if coupled:
        steps.append(_step('coupling_bolts', 'Align the rotor to the turbine\'s and fit the coupling bolts with the '
                           'bolt stretcher; check the coupled run-out.',
                           [('ped_te', 'The rotor is aligned on its bearings: they are in first.',
                             'Take the coupling bolts out before the bearings\' bottom halves are touched.')],
                           why='The coupling\'s run-out is recorded before it is parted (a.2).'))
    steps += [
        _step('es_te_up', 'Lower the drive end shield\'s top half onto the bottom half, sealed.',
              [('es_te_lo', 'The top half bolts onto the bottom half: fit that first.',
                'Lift the top half off before the bottom half is lowered.'),
               ('fan_shield_te', 'The end shield closes over the fan shield: fit it first.',
                'Lift the end shield off before the fan shield comes out.')]),
        _step('es_ee_up', 'Lower the exciter end shield\'s top half onto its bottom half, sealed.',
              [('es_ee_lo', 'The top half bolts onto the bottom half: fit that first.',
                'Lift the top half off before the bottom half is lowered.'),
               ('fan_shield_ee', 'The end shield closes over the fan shield: fit it first.',
                'Lift the end shield off before the fan shield comes out.')]),
        _step('brg_cap_te', 'Fit the drive-end bearing\'s top half and cap with its outer oil catcher; refit its '
              'temperature sensor.', [('ped_te', 'The top half closes over the journal in the bottom half: fit that '
                                       'first.', 'Lift the bearing\'s top half off first.')],
              why='WEG takes the bearing sensors and the grounding brush off before the bearings.',
              sources=(BHEL, WEG)),
        _step('brg_cap_ee', 'Fit the exciter-end bearing\'s top half and cap the same way.',
              [('ped_ee', 'The top half closes over the journal in the bottom half: fit that first.',
                'Lift the bearing\'s top half off first.')], sources=(BHEL, WEG)),
        _step('exciter', 'Set the exciter on its bed, align it to the generator\'s rotor and couple it.',
              [('ped_ee', 'The exciter is coupled to the rotor on its bearings: they are in first.',
                'Uncouple the exciter and take it off its bed before the exciter-end bearing\'s bottom half is touched.')],
              why='Its swing and run-out are recorded before it is uncoupled (a.3, g.3).'),
        _step('exc_rotor', 'The exciter\'s rotor comes with it, coupled to the generator\'s.'),
        _step('exc_cover', 'Fit the exciter\'s hood.',
              [('exciter', 'The hood closes over the exciter: set it on its bed first.',
                'Take the hood off first.')], why='The enclosures come off first of all (a.1, a.3).'),
        _step('exc_grille', 'The end grille comes with the hood.'),
        _step('cooler', 'Lower the coolers into their housing on top of the frame.',
              [('stator', 'The coolers sit on the stator\'s frame: it is there first.',
                'Lift the coolers off before the stator is touched.')],
              why='Each cooler is pressure-tested while it is out (a.6).', sources=(BHEL, WEG)),
        _step('cw_pipes', 'Reconnect the cooling water pipes to the coolers.',
              [('cooler', 'The pipes feed the coolers: lower them in first.',
                'Disconnect the cooling water pipes before the coolers are lifted.')],
              why='WEG disconnects the cooling water and oil pipes before anything else.', sources=(BHEL, WEG)),
        _step('terminal_box', 'Mount the phase and neutral terminal bushings with new gaskets and connect their '
              'jumpers.', [('stator', 'The bushings bring the stator winding\'s ends out: it is there first.',
                            'Disconnect the jumpers and take the bushings out first.')],
              why='Each bushing is pressure-tested on its own while it is out (a.1). WEG disconnects the electrical '
                  'connections before the generator is opened.', sources=(BHEL, WEG)),
    ]
    # the reverse of BHEL's take-apart (a.1 the bushings, a.2 the bearings' top halves and the coupling, a.3 the
    # exciter's hood and the exciter, a.5 the pipes, the coolers, the end shields and fan shields, a.7 the bearings and
    # the bottom end shields, a.8 the rotor)
    order = ['plinth', 'stator', 'rotor', 'es_te_lo', 'es_ee_lo', 'ped_te', 'ped_ee', 'fan_shield_te', 'fan_shield_ee',
             'es_te_up', 'es_ee_up', 'cooler', 'cw_pipes', 'exciter', 'exc_rotor', 'exc_cover', 'exc_grille', 'coupling_bolts',
             'brg_cap_te', 'brg_cap_ee', 'terminal_box']
    by = {s['place']: s for s in steps}
    return [by[p] for p in order if p in by]


def data(coupled=True):
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'generator',
        # its parameters and shaft line are the plant's first generator's (WORKSHOP.md §5)
        'context': ['axis_z', 'shaft_lo', 'shaft_hi'],
        'sources': SOURCES,
        'components': components(),
        'fasteners': ({'coupling_bolts': {'name': '12 coupling bolts', 'joins': ['rotor'],
                                          'beyond': 'The gas turbine\'s rotor: the next machine on the shaft line',
                                          'sources': [BHEL]}} if coupled else {}),
        'assembly': assembly(coupled),
        # the X-ray takes the frame, its end shields, the coolers and the exciter's hood; the cutaway opens a quarter
        # above the shaft on the plates' side; the rotor stays whole
        'views': {'xray_all': ['stator', 'es_te_up', 'es_te_lo', 'es_ee_up', 'es_ee_lo', 'cooler', 'exc_cover'],
                  'cutaway': {'planes': [{'normal': [0, 0, 1], 'offset': 0}, {'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['rotor', 'exc_rotor']}},
    }
