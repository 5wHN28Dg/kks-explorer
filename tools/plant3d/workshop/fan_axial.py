"""The cooling tower fan's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): an adjustable-pitch axial fan on
a hub over a right-angle double reduction gear drive, in its stack on the tower's deck, driven by a composite drive
shaft from a motor outside the stack. Its geometry is the kit's generator, apps/plant3d/kit/parts_rotating.gd
`fan_axial` and its `_fan_*` helpers; the motor is the motor kind's tree from the same helper (`motor_h`), whose
words, fasteners and assembly come from tools/plant3d/workshop/motor.py, written once.

Where each order comes from (the user's decision, 2026-11-14: "reverse install + derived"):
- the fan and its hub: Hudson's Tuf-Lite 6000 series hub INSTALLATION manual. Hudson gives no removal procedure, so the
  take-apart is THE REVERSE OF HUDSON'S INSTALLATION ORDER (the hub on the gear's shaft, the blades clamped in it,
  pitch and track set, the seal disc on top), and every such step says so;
- the gear drive: Amarillo's repair instructions for its double reduction fan drives, which give both orders
  (disassembly §1-4, assembly §5-15);
- the drive shaft: Amarillo's composite drive shaft INSTALLATION instructions, reversed to take it off (said in its
  step);
- the motor: DERIVED FROM HOW IT IS BUILT, as the motor kind's (motor.py).
Generic: no plant data. The parameters are the plant's cooling tower fan (it has several, all alike). No sizes, tools
or torques here: they belong to the realism programme's service file (WORKSHOP.md §4.4).
"""

from workshop import motor

HUDSON = 'hudson_6000'
AMARILLO = 'amarillo_drr'
SHAFT = 'amarillo_omds'
REVERSED = ('Hudson gives the installation order only: taking the fan apart is its reverse, not a maker\'s removal '
            'procedure.')

SOURCES = [
    {'id': HUDSON, 'cite': 'Hudson Products (Chart Industries), Tuf-Lite and Tuf-Lite II fans, 6000 series hub, '
                           'installation manual R8 (2018): hub on the shaft p. 2; thrust retainer, blades and pitch '
                           'p. 3; track and seal disc p. 4; rotation and tip clearance p. 5; parts list p. 6; '
                           'materials p. 7',
     'url': 'https://files.chartindustries.com/hudson/6000-IN-MANUAL_R8.pdf'},
    {'id': AMARILLO, 'cite': 'Amarillo Gear, Double reduction fan drives: instructions for repairing, DRR 6/09 '
                             '(printed pages; PDF = printed + 3): disassembly §1 pp. 1-4, sections figs. 1-2 pp. 2-3, '
                             'input shaft §2 pp. 5-8, other shafts §3-4 p. 8, assembly §5-9 pp. 10-13, adjustment '
                             'and completion §10-15 pp. 13-17',
     'url': 'https://amarillogear.com/wp-content/uploads/2024/05/Double-Reduction-Fan-Drive-Repair-Manual-0609.pdf'},
    {'id': SHAFT, 'cite': 'Amarillo Gear Company, Installation and alignment instructions for Amarillo composite drive '
                          'shafts, OMDS 03/14: installation steps 1-9 (the hubs on the motor\'s and the gear drive\'s '
                          'shafts, the spacer tube between them, the flex discs bolted to its end flanges) pp. 1-2',
     'url': 'https://amarillogear.com/wp-content/uploads/2024/05/Drive-Shaft-O-M-OMDS-03-14.pdf'},
]

PARAMS = {'d': 9.5, 'blades': 8, 'motor_kw': 200, 'stack_height': 3}


def _c(name, does, material, sources, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': list(sources)}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def components():
    own = {
        'stack': _c('Fan stack', 'The cylinder the fan turns in, its top flared to recover the air\'s speed; the blades '
                    'turn with a small clearance to its wall.', 'Fibreglass-reinforced plastic', [HUDSON]),
        'beams': _c('Mechanical equipment support', 'The beams across the stack that carry the gear drive.',
                    'Galvanised steel', [AMARILLO]),
        'gb_case': _c('Gear case', 'Holds the three shafts in their bearings and the oil they run in. Amarillo repairs '
                      'the drive in a shop: it comes off the tower whole first.', 'Cast iron', [AMARILLO]),
        'gb_cover': _c('Vertical cover', 'The gear case\'s top, located on two tapered pins: the upper bearing cups of '
                       'the output and intermediate shafts sit in it.', 'Cast iron', [AMARILLO]),
        'gb_seal_carrier': _c('Vertical seal carrier and upper seal plate', 'Hold the output shaft\'s seals and, with '
                              'their shim pack, set the output bearings\' preload; the seal plate shields them from '
                              'above.', 'Cast iron, steel shims, nitrile seals', [AMARILLO]),
        'gb_int_cover': _c('Upper intermediate bearing cover', 'Closes the intermediate shaft\'s upper bearing; its '
                           'shim pack sets that shaft\'s end play.', 'Cast iron, steel shims', [AMARILLO]),
        'gb_out_shaft': _c('Output shaft', 'The vertical shaft the fan\'s hub sits on, turning with it.',
                           'Alloy steel', [AMARILLO]),
        'gb_helical': _c('Helical gear', 'Keyed on the output shaft, driven by the intermediate shaft\'s helical '
                         'pinion: the drive\'s second reduction.', 'Alloy steel', [AMARILLO]),
        'gb_out_brg_lo': _c('Lower output bearing cone', 'The tapered roller bearing under the helical gear, in its '
                            'cup in the gear case.', 'Bearing steel', [AMARILLO]),
        'gb_out_brg_up': _c('Upper output bearing cone', 'The tapered roller bearing at the output shaft\'s top, in '
                            'its cup in the vertical cover: it carries the fan\'s thrust.', 'Bearing steel',
                            [AMARILLO]),
        'gb_int_shaft': _c('Intermediate shaft', 'A vertical helical pinion shaft beside the output shaft: its spiral '
                           'bevel gear takes the drive from the input pinion, its pinion turns the helical gear.',
                           'Alloy steel', [AMARILLO]),
        'gb_bevel': _c('Spiral bevel gear', 'Keyed on the intermediate shaft between its spacers, meshing with the input '
                       'shaft\'s pinion: the first reduction and the turn through a right angle. It and the pinion are '
                       'a lapped matched set.', 'Alloy steel', [AMARILLO]),
        'gb_int_brg_up': _c('Upper intermediate bearing cone', 'The intermediate shaft\'s upper tapered roller bearing.',
                            'Bearing steel', [AMARILLO]),
        'gb_int_brg_lo': _c('Lower intermediate bearing cone', 'The intermediate shaft\'s lower tapered roller bearing.',
                            'Bearing steel', [AMARILLO]),
        'gb_in_carrier': _c('Horizontal shaft carrier', 'Holds the input shaft\'s two bearing cups and fits in a '
                            'register in the gear case\'s side, match-marked to it.', 'Cast iron', [AMARILLO]),
        'gb_oil_seal': _c('Horizontal oil seal plate', 'Holds the input shaft\'s oil seals on the carrier\'s outer '
                          'face.', 'Steel, nitrile seals', [AMARILLO]),
        'gb_in_shaft': _c('Input shaft', 'Driven by the drive shaft from the motor; carries the spiral bevel pinion '
                          'at its inner end.', 'Alloy steel', [AMARILLO]),
        'gb_pinion': _c('Spiral bevel pinion', 'Keyed on the input shaft\'s inner end, meshing with the spiral bevel '
                        'gear.', 'Alloy steel', [AMARILLO]),
        'gb_in_brg_in': _c('Inner input bearing cone', 'The input shaft\'s tapered roller bearing next to the pinion.',
                           'Bearing steel', [AMARILLO]),
        'gb_in_brg_out': _c('Outer input bearing cone', 'The input shaft\'s tapered roller bearing at the carrier\'s '
                            'outer end; its locknuts set the shaft\'s end play.', 'Bearing steel', [AMARILLO]),
        'gb_low_covers': _c('Lower bearing covers', 'Close the output and intermediate shafts\' lower bearing bores '
                            'under the gear case; the lower cups sit above them.', 'Cast iron', [AMARILLO]),
        'hub': _c('Fan hub', 'The hub spool on the output shaft (on a bushing and key) with its two hub plates, the '
                  'blades clamped between them.', 'Ductile iron spool, coated steel plates, aluminium blade clamps',
                  [HUDSON]),
        'blades': _c('Fan blades', 'Clamped by their necks in the hub at a set pitch angle, they push the air up out '
                     'of the stack. Each is balanced on its own and can be changed alone.',
                     'Fibreglass-reinforced vinyl ester', [HUDSON]),
        'seal_disc': _c('Seal disc', 'Covers the hub so that warm air does not fall back down through it.',
                        'Fibreglass, stainless steel hardware', [HUDSON]),
        'drive_shaft': _c('Drive shaft', 'Joins the motor to the gear drive\'s input shaft: a hub on each shaft, flex '
                          'discs and a composite spacer tube between them.',
                          'Carbon fibre composite tube, stainless steel hubs', [SHAFT]),
        'guard': _c('Drive shaft guard', 'Covers the drive shaft where it turns outside the stack.', 'Steel, painted',
                    [SHAFT]),
        'motor': _c('Motor: stator and frame', 'The fan\'s motor on the deck outside the stack, its feet on the deck: '
                    'the stator in its finned frame, cooled from outside by its own fan (IC 411).',
                    'Cast iron frame, laminated electrical steel core, copper winding', [motor.SIMOTICS, motor.WEG]),
    }
    mc = motor.components('motor')
    mc.pop('motor')
    mc['fan'] = dict(mc['fan'], name='Motor\'s cooling fan')
    return dict(own, **mc)


def fasteners():
    return dict(motor.fasteners('motor'),
                clamp_bolts={'name': '32 blade clamp bolts', 'joins': ['blades', 'hub'], 'sources': [HUDSON]},
                disc_bolts={'name': '6 seal disc bolts', 'joins': ['seal_disc', 'hub'], 'sources': [HUDSON]})


def _step(place, text, needs=(), why=None, sources=(AMARILLO,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


def _fan(place, text, needs=(), why=None):
    """A step of the fan's own order: the reverse of Hudson's installation, said in its reason."""
    return _step(place, text, needs, (why + ' ' if why else '') + REVERSED, (HUDSON,))


# The guided order (reassembly; taking apart is its reverse). The gear drive as Amarillo assembles it (§6-9: the
# shafts' parts pressed on in the shop, the lower cups, the input assembly into the case's side, the output and
# intermediate shafts lowered together, the vertical cover; §11-15: the intermediate bearing cover and the seal
# carrier with their shim packs, the upper seal plate, the oil seal plate); then the fan as Hudson installs it, the
# motor (derived from its build) and the drive shaft (Amarillo's installation). A part's parent is placed first.
ASSEMBLY = [
    _step('stack', 'The fan stack stays on the tower\'s deck.', sources=(HUDSON,)),
    _step('beams', 'The support beams stay across the stack.'),
    _step('gb_case', 'Set the gear case on its beams, its input opening towards the motor.',
          [('beams', 'The gear case stands on the beams: they are there first.', 'The beams stay.')],
          why='Amarillo repairs the drive in a shop: it comes off the tower whole, drained of its oil, and its side and '
              'upper inspection plates (not drawn) come off first.'),
    _step('gb_low_covers', 'Press the lower output and intermediate bearing cups into the case and fit the lower '
          'bearing covers under them.',
          [('gb_case', 'The covers close the gear case\'s lower bores: the case is there first.', 'The case stays.')],
          why='Amarillo tips the case on its back to reach them, the input opening up.'),
    _step('gb_in_carrier', 'Offer the horizontal shaft carrier, with a gasket, to the case\'s side opening, its match '
          'marks on the case\'s.',
          [('gb_case', 'The carrier goes into the gear case\'s side: the case is there first.', 'The case stays.')],
          why='In the shop the input shaft with its pinion and bearings is built into the carrier and the carrier goes '
              'in whole on two guide pins; the steps here fit each part in place.'),
    _step('gb_in_shaft', 'Put the input shaft into the carrier.',
          [('gb_in_carrier', 'The shaft runs in the carrier: fit the carrier first.',
            'Draw the input shaft out of the carrier before the carrier is moved.')]),
    _step('gb_pinion', 'Key and press the spiral bevel pinion onto the shaft\'s inner end, against the oil slinger '
          'plate.', [('gb_in_shaft', 'The pinion goes on the input shaft: put the shaft in first.',
                      'Press the pinion off before the shaft comes out.')],
          why='Antigalling compound on everything pressed on a shaft.'),
    _step('gb_in_brg_in', 'Press the inner bearing cone onto the shaft next to the pinion, never on its roller cage.',
          [('gb_in_shaft', 'The cone goes on the input shaft: put the shaft in first.',
            'Press the inner cone off before the shaft comes out.')]),
    _step('gb_in_brg_out', 'Press the outer bearing cone on and set the shaft\'s end play with its two locknuts.',
          [('gb_in_shaft', 'The cone goes on the input shaft: put the shaft in first.',
            'Take the outer cone off before the shaft comes out.')],
          why='Amarillo leaves the play to be felt by lifting the carrier, then sets it with a dial indicator (§10).'),
    _step('gb_out_shaft', 'Lower the output shaft into the case, on a strong back with the intermediate shaft, onto '
          'its lower cup.',
          [('gb_low_covers', 'The shaft runs in the lower cup over its cover: fit them first.',
            'Lift the output shaft out before the lower covers come off.'),
           ('gb_in_carrier', 'Amarillo puts the input assembly in before the vertical shafts go down.',
            'Lift the vertical shafts out before the horizontal carrier is pulled.')],
          why='The two vertical shafts go in and out together on a strong back across both, so that their lower '
              'bearings and helical gears are not damaged.'),
    _step('gb_helical', 'The helical gear is pressed on the output shaft against its shoulder, keyed.',
          [('gb_out_shaft', 'The gear goes on the output shaft: put the shaft in first.',
            'Press the gear off before the shaft is lifted out.')],
          why='In the shop the gear and both bearing cones are pressed on before the shaft goes in, and come off once '
              'it is out (in the steps here they are fitted and taken off in place).'),
    _step('gb_out_brg_lo', 'The lower output bearing cone goes under the helical gear with the output shaft spacer.',
          [('gb_out_shaft', 'The cone goes on the output shaft: put the shaft in first.',
            'Press the cone off before the shaft is lifted out.')]),
    _step('gb_out_brg_up', 'Press the upper output bearing cone on against the shaft\'s shoulder.',
          [('gb_out_shaft', 'The cone goes on the output shaft: put the shaft in first.',
            'Press the cone off before the shaft is lifted out.')]),
    _step('gb_int_shaft', 'Lower the intermediate shaft in beside the output shaft, the timing marks on its bevel '
          'gear on the pinion\'s.',
          [('gb_low_covers', 'The shaft runs in its lower cup over its cover: fit them first.',
            'Lift the intermediate shaft out before the lower covers come off.'),
           ('gb_in_carrier', 'Amarillo puts the input assembly in before the vertical shafts go down.',
            'Lift the vertical shafts out before the horizontal carrier is pulled.')],
          why='Its lower bearing cone must clear the input shaft\'s bearing retainer on the way.'),
    _step('gb_bevel', 'The spiral bevel gear is keyed and pressed on between its spacers.',
          [('gb_int_shaft', 'The gear goes on the intermediate shaft: put the shaft in first.',
            'Press the gear off before the shaft is lifted out.')],
          why='The gear and the pinion are a lapped matched set, never separated.'),
    _step('gb_int_brg_lo', 'The lower intermediate bearing cone goes on below the below-gear spacer.',
          [('gb_int_shaft', 'The cone goes on the intermediate shaft: put the shaft in first.',
            'Press the cone off before the shaft is lifted out.')]),
    _step('gb_int_brg_up', 'Press the upper intermediate bearing cone on above the above-gear spacer.',
          [('gb_int_shaft', 'The cone goes on the intermediate shaft: put the shaft in first.',
            'Press the cone off before the shaft is lifted out.')]),
    _step('gb_cover', 'Seal the case\'s top flange and lower the vertical cover onto its two tapered pins; bolt it '
          'down and slide the upper cups onto the cones.',
          [('gb_out_brg_up', 'The cover\'s cups close over the upper cones: fit them first.',
            'Lift the vertical cover off before the output shaft\'s upper cone.'),
           ('gb_int_brg_up', 'The cover\'s cups close over the upper cones: fit them first.',
            'Lift the vertical cover off before the intermediate shaft\'s upper cone.'),
           ('gb_out_shaft', 'The cover closes over the output shaft: lower it in first.',
            'Lift the vertical cover off before the output shaft comes out.'),
           ('gb_int_shaft', 'The cover closes over the intermediate shaft: lower it in first.',
            'Lift the vertical cover off before the intermediate shaft comes out.')],
          why='It comes off with a hoist on two eye bolts in the seal carrier\'s and the bearing cover\'s holes.'),
    _step('gb_int_cover', 'Fit the upper intermediate bearing cover with its shim pack, the end play set to 0 to '
          '0.001 inch.', [('gb_cover', 'The bearing cover sits on the vertical cover: fit that first.',
                           'Take the bearing cover off, keeping its shims, before the vertical cover.')],
          why='Never mix up the shim packs: each sets its own shaft.'),
    _step('gb_seal_carrier', 'Fit the vertical seal carrier with its seals and shim pack, then the upper seal plate '
          'clear of it.', [('gb_cover', 'The seal carrier sits on the vertical cover: fit that first.',
                            'Take the seal plate and the seal carrier off, keeping the shims, before the vertical '
                            'cover.')]),
    _step('gb_oil_seal', 'Slide the horizontal oil seal plate with its seals over the input shaft, its keyway taped.',
          [('gb_in_carrier', 'The seal plate sits on the carrier\'s outer face: fit the carrier first.',
            'Take the oil seal plate off before the carrier is pulled.'),
           ('gb_in_brg_out', 'The seal plate closes over the outer bearing: fit it first.',
            'Take the oil seal plate off before the outer bearing.')],
          why='Amarillo takes it off before the vertical cover; its old seals are thrown away. Then the drive is '
              'filled with oil.'),
    _fan('hub', 'Set the hub on the output shaft, its key in the keyway, and lock its bushing\'s cap screws.',
         [('gb_out_shaft', 'The hub sits on the output shaft: the gear drive is there first.',
           'Take the hub off before the gear drive comes apart.'),
          ('gb_seal_carrier', 'The hub stands over the seal carrier: fit it first.',
           'Lift the hub off before the seal carrier comes off.')],
         why='Its mating faces clean and dry; a thrust retainer (optional) holds it down where the shaft has no '
             'shoulder.'),
    _fan('blades', 'Clamp each blade\'s neck in its clamp halves between the hub plates, its thick leading edge to '
         'the left seen from its tip.',
         [('hub', 'The blades are clamped in the hub: set the hub on first.', 'Take the blades out before the hub.')],
         why='Each blade is balanced on its own and can be changed alone.'),
    _fan('clamp_bolts', 'Set each blade\'s pitch with a protractor near its tip, tighten its four clamp bolts, then '
         'check the track and the sweep blade by blade.',
         [('blades', 'The bolts clamp the blades: put them in first.',
           'Loosen and take out the clamp bolts before a blade comes out.')],
         why='The pitch within 0.2 degrees of the design; the tips\' levels marked on the stack within an inch.'),
    _fan('seal_disc', 'Bolt the seal disc\'s two halves together and set it on the six studs of the top hub plate.',
         [('clamp_bolts', 'The seal disc goes on last, over the clamped blades\' roots.',
           'Take the seal disc off before the blades\' clamp bolts.')],
         why='It keeps warm air from falling back down through the hub.'),
    _fan('disc_bolts', 'Fit the seal disc\'s six nuts and washers.',
         [('seal_disc', 'The nuts hold the seal disc: put it on first.', 'Take the six nuts off first.')]),
    _step('motor', 'The motor stands on the deck outside the stack, on its shims.',
          why='Its own parts come apart as the motor kind\'s do. ' + motor.DERIVED, sources=(motor.SIMOTICS,)),
] + motor.assembly('motor', first=False) + [
    _step('drive_shaft', 'Fit a hub on the motor\'s shaft and one on the gear drive\'s input shaft, put the spacer '
          'tube between them, bolt the flex discs to its end flanges, then check the alignment.',
          [('gb_oil_seal', 'The drive shaft\'s hub goes on the input shaft outside its oil seal plate: fit the plate '
            'first.', 'Take the drive shaft off before the oil seal plate.'),
           ('rotor', 'The drive shaft\'s other hub sits on the motor\'s shaft: put the rotor in first.',
            'Take the drive shaft off before the motor\'s rotor is drawn out.'),
           ('motor', 'The drive shaft joins the motor to the gear drive: set the motor down first.',
            'Take the drive shaft off before the motor is moved.')],
          why='Amarillo gives the installation steps; taking it off is their reverse. The motor and the gear drive '
              'are aligned to each other before it goes in.', sources=(SHAFT,)),
    _step('guard', 'Fit the drive shaft\'s guard.',
          [('drive_shaft', 'The guard covers the drive shaft: fit the shaft first.', 'Take the guard off first.')],
          why='The drive shaft never turns without its guard.', sources=(SHAFT,)),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'fan_axial',
        'params': PARAMS,
        'sources': SOURCES + motor.SOURCES,
        'components': components(),
        'fasteners': fasteners(),
        'assembly': ASSEMBLY,
        # the X-ray takes the gear case and its cover, the hub and the motor's casings; the cutaway opens the gear drive
        # and the hub along the input shaft's line (the half towards +y); the blades and the shafts stay whole
        'views': {'xray_all': ['gb_case', 'gb_cover', 'hub', 'seal_disc', 'guard', 'motor', 'end_shield_de',
                               'end_shield_nde', 'fan_cowl'],
                  'cutaway': {'planes': [{'normal': [0, 1, 0], 'offset': 0}],
                              'keep': ['blades', 'gb_out_shaft', 'gb_int_shaft', 'gb_in_shaft', 'rotor']}},
    }
