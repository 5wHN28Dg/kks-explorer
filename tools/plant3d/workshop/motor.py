"""The motor's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a totally enclosed fan-cooled induction
motor, foot mounted, as the public manuals describe one. Its geometry is the kit's `motor_h` helper
(apps/plant3d/kit/parts_common.gd), which the motor kind and the horizontal pump share: the pump carries this same
tree under its own root (tools/plant3d/workshop/pump_horizontal.py calls `components`, `fasteners` and `assembly`
here, so the words are written once).

The take-apart order is DERIVED FROM HOW THE MOTOR IS BUILT, NOT FROM A MANUAL (the user's decision, 2026-11-09): no
public motor manual read for K6 (ABB, WEG, Siemens/Innomotics) gives a numbered dismantling sequence. It is the order
the parts physically allow: the fan cowl, the fan, the end shields (with their bearing caps), the rotor out of the
stator, the bearings off the shaft; reassembly the reverse. Each part cites what the manuals do say about it. No sizes,
tools or torques here: they belong to the realism programme's service file (WORKSHOP.md §4.4).
"""

ABB = 'abb_lv'
WEG = 'weg_iom'
SIMOTICS = 'simotics'
DERIVED = ('Order derived from how the motor is built, not from a manual: no public manual read gives a numbered '
           'dismantling sequence.')

SOURCES = [
    {'id': ABB, 'cite': 'ABB, Low voltage motors manual: installation, operation, maintenance and safety manual, '
                        '3GZF500730-85 rev. D (2009): §3.9 direction of rotation (clockwise seen at the drive end '
                        'with L1-L2-L3 on U-V-W), §6.1 bearings replaced when worn, §7.3 bearings pulled with pullers '
                        'and fitted hot',
     'url': 'https://library.e.abb.com/public/e20ddd6a89ed4815821e8163f569bf63/'
            'Standard_LV_Motors_Manual_EN_01_2009%20Rev%20D.pdf'},
    {'id': WEG, 'cite': 'WEG, Installation, operation and maintenance manual, electric motors, 50033244 '
                        'rev. 43 (2026): §8.3 disassembly precautions (a fan fitted with interference replaced), '
                        '§8.3.1 the terminal box, §8.4 the parts removed to dry a stator (end shields, rotor with '
                        'shaft, fan cover, fan, terminal box)',
     'url': 'https://static.weg.net/medias/downloadcenter/ha6/h39/WEG-WMO-safe-area-50033244-manual-pt-en-es.pdf'},
    {'id': SIMOTICS, 'cite': 'Innomotics (Siemens), SIMOTICS 1LE1 shaft height 63-315 operating instructions,'
                             ' A5E38483075A (07/2024): §3.3.1.2 cooling IC 411 (IEC 60034-6), §3.3.4 IM B3 '
                             '(IEC 60034-7), §9.3 corrective maintenance (windings protected when an end shield is '
                             'fitted), §9.3.3 fan pulled, hub warmed, §10.3 bearings',
     'url': 'https://temsrl.it/wp-content/uploads/2025/01/'
            'siemens-simotics-motor-instructions-EN_1LE1_1FP1_1FP3_1PC1_1PC3_op_Instr_0724.pdf'},
]


def _c(name, does, material, sources, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': sources}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def components(root):
    """The motor's components; `root` is the stator's id (the motor kind's `stator`, the pump's `motor`)."""
    return {
        root: _c('Stator and frame' if root == 'stator' else 'Motor: stator and frame',
                 'The finned frame with its feet holds the stator core and its three-phase winding; the rotating '
                 'field the winding makes turns the rotor. Cooled from outside by the fan\'s air over the fins '
                 '(IC 411).', 'Cast iron frame, laminated electrical steel core, copper winding', [SIMOTICS, WEG]),
        'terminal_box': _c('Terminal box', 'Where the supply cable lands on the winding\'s terminals U1, V1, W1; '
                           'record the connections before it is opened.', 'Cast iron, brass terminals', [WEG, ABB]),
        'end_shield_de': _c('Drive-end shield', 'Closes the frame at the drive end and holds the drive-end bearing '
                            'in its housing; its bearing cap keeps the grease in.', 'Cast iron', [WEG, SIMOTICS]),
        'end_shield_nde': _c('Non-drive-end shield', 'Closes the frame at the fan end and holds the non-drive-end '
                             'bearing in its housing.', 'Cast iron', [WEG, SIMOTICS]),
        'fan': _c('Cooling fan', 'On the shaft\'s non-drive end: blows air along the frame\'s fins whichever way '
                  'the motor turns (straight radial blades). A fan fitted with interference is replaced, not '
                  'reused.', 'Plastic or aluminium', [WEG, SIMOTICS]),
        'fan_cowl': _c('Fan cowl', 'Guards the fan and guides its air over the fins.', 'Sheet steel, painted',
                       [WEG, SIMOTICS],
                       sealed_why='The grille is part of the fan cowl: they come off as one.'),
        'grille': _c('Air intake grille', 'Lets the cooling air in at the cowl\'s end; kept clear of dirt.',
                     'Sheet steel', [WEG]),
        'rotor': _c('Rotor', 'The squirrel-cage rotor on its shaft: the stator\'s field drives it round. Drawn out '
                    'of the stator\'s bore without touching the winding.', 'Laminated steel core, aluminium cage, '
                    'steel shaft', [WEG, SIMOTICS]),
        'bearing_de': _c('Drive-end bearing', 'A rolling bearing on the shaft at the drive end, in the drive-end '
                         'shield: it carries the load the coupling puts on the shaft.', 'Bearing steel',
                         [ABB, SIMOTICS]),
        'bearing_nde': _c('Non-drive-end bearing', 'A rolling bearing on the shaft at the fan end, in the '
                          'non-drive-end shield.', 'Bearing steel', [ABB, SIMOTICS]),
    }


def fasteners(root):
    return {
        'de_bolts': {'name': '4 drive-end shield bolts', 'joins': ['end_shield_de', root], 'sources': [WEG]},
        'cowl_screws': {'name': '4 fan cowl screws', 'joins': ['fan_cowl', root], 'sources': [WEG]},
    }


def _step(place, text, needs=(), why=None, sources=(WEG,)):
    """A step of the motor's own order: its reason says the order is derived from the build (the user, 2026-11-09)."""
    s = {'place': place, 'text': [text], 'sources': list(sources), 'why': [(why + ' ' if why else '') + DERIVED]}
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


def assembly(root, first=True):
    """The motor's guided order (reassembly; taking apart is its reverse). `first`: the root is placed here (the
    motor kind) rather than by the machine it drives."""
    steps = [_step(root, 'Set the stator in its frame on its baseplate, feet down, the winding protected.',
                   [('baseplate', 'The motor stands on its baseplate: it is there first.',
                     'The baseplate stays grouted to the floor.')], sources=(SIMOTICS,))] if first else []
    return steps + [
        _step('rotor', 'Slide the rotor into the stator\'s bore from the drive end, its weight carried so that it '
              'never rests on the winding.',
              [(root, 'The rotor goes into the stator\'s bore: set the stator down first.',
                'Draw the rotor out before the stator is moved.')],
              why='A rotor dragged against the winding damages its insulation.', sources=(SIMOTICS, WEG)),
        _step('bearing_de', 'Fit the drive-end bearing on the shaft, heated, pressing on its inner ring only.',
              why='In the shop the bearings go on the shaft before the rotor goes in, and come off it once the rotor '
                  'is out (in the steps here they are fitted and taken off in place).', sources=(ABB, SIMOTICS)),
        _step('bearing_nde', 'Fit the non-drive-end bearing on the shaft the same way.', sources=(ABB, SIMOTICS)),
        _step('end_shield_nde', 'Fit the non-drive-end shield over its bearing and into the frame, with its bearing '
              'cap.',
              [('bearing_nde', 'The shield\'s housing closes over the non-drive-end bearing: fit the bearing first.',
                'Take the non-drive-end shield off before its bearing.')],
              why='Its spigot is entered square, without forcing, so that the bearing is not loaded.'),
        _step('end_shield_de', 'Fit the drive-end shield over its bearing and into the frame, with its bearing cap.',
              [('bearing_de', 'The shield\'s housing closes over the drive-end bearing: fit the bearing first.',
                'Take the drive-end shield off before its bearing.'),
               ('rotor', 'The drive-end shield closes the stator over the rotor: put the rotor in first.',
                'Take the drive-end shield off before the rotor is drawn out.')]),
        _step('de_bolts', 'Fit the four drive-end shield bolts and tighten them evenly; turn the shaft by hand: it '
              'must turn freely.',
              [('end_shield_de', 'The bolts hold the drive-end shield: fit the shield first.',
                'Take the four bolts out before the drive-end shield comes off.')]),
        _step('fan', 'Push the fan onto the shaft\'s non-drive end and lock it.',
              [('end_shield_nde', 'The fan sits behind the non-drive-end shield: fit the shield first.',
                'Pull the fan off before the non-drive-end shield comes off.'),
               ('rotor', 'The fan goes on the rotor\'s shaft: put the rotor in first.',
                'Pull the fan off before the rotor is drawn out: it is wider than the stator\'s bore.')],
              why='A fan fitted with interference is pulled with a puller, never knocked off, and replaced.',
              sources=(WEG, SIMOTICS)),
        _step('fan_cowl', 'Put the fan cowl over the fan.',
              [('fan', 'The cowl closes over the fan: fit the fan first.',
                'Take the fan cowl off before the fan.')]),
        _step('grille', 'The grille comes with the fan cowl.'),
        _step('cowl_screws', 'Fit the four cowl screws.',
              [('fan_cowl', 'The screws hold the cowl: put the cowl on first.',
                'Take the four cowl screws out before the cowl comes off.')]),
        _step('terminal_box', 'Fit the terminal box and connect the supply as recorded before it was opened.',
              [(root, 'The terminal box sits on the stator\'s frame: set the stator down first.',
                'Take the terminal box off before the stator is moved.')], sources=(WEG, ABB)),
    ]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'motor',
        'sources': SOURCES,
        'components': dict(components('stator'),
                           baseplate=_c('Baseplate', 'The steel frame the motor\'s feet are bolted to, grouted to '
                                        'the floor.', 'Steel, grout', [SIMOTICS])),
        'fasteners': fasteners('stator'),
        'assembly': [{'place': 'baseplate', 'text': ['The baseplate stays grouted to the floor.'],
                      'sources': [SIMOTICS]}] +
        assembly('stator'),
        # the X-ray takes the frame and its closures; the cutaway opens a quarter above the shaft on the side away from
        # the terminal box; the motor runs only assembled, and nothing is opened while it turns
        'views': {'xray_all': ['stator', 'end_shield_de', 'end_shield_nde', 'fan_cowl', 'terminal_box'],
                  'cutaway': {'planes': [{'normal': [0, 0, 1], 'offset': 0}, {'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['rotor']}},
    }
