"""The vertical pump's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a wet-pit vertical turbine pump of
two stages, its column hanging from a discharge head on a sole plate over the pit, driven by a vertical motor on the
head's motor stand through a spacer coupling. Its geometry is the kit's generator, apps/plant3d/kit/parts_rotating.gd
`pump_vertical` (with its motor's tree from parts_common.gd `motor_v`).

The take-apart order follows the Goulds VIT manual's disassembly (§6, p. 31: uncouple the driver and lift it off,
remove the coupling and the packing box, take the pump apart down to the bowls by reversing the installation, then
drive each impeller off its taperlock) and the Flowserve VTP user instructions (§6.8: the coupling apart, the motor
set down, the seal off, the discharge head off, the column sections apart with their bearing retainers, the bowl
assembly lifted and removed last); reassembly is their reverse (Goulds §6, pp. 32-33, the bowls stage by stage;
installation §3, pp. 13-19, the column and the head). The motor's order is derived from how it is built, as the motor
kind's is (motor.py). Generic: no plant data. The parameters are a vertical pump the plant has three of.
"""

from workshop import motor

GOULDS_VIT = 'goulds_vit'
GOULDS_VIC = 'goulds_vic'
FLOWSERVE_VTP = 'flowserve_vtp'
FLOWSERVE_POSTER = 'flowserve_vtp_poster'
GOULDS_BROCHURE = 'goulds_vit_brochure'
KSB_VANE = 'ksb_vane'

SOURCES = [
    {'id': GOULDS_VIT, 'cite': 'Goulds Water Technology (Xylem), Model VIT vertical industrial turbine pumps, IOM '
                               'IOMGWVITR02 (2018): p. 6 bowl assembly (impellers on taperlocks), figs 1-4 pp. 7-10, '
                               'installation pp. 13-19, impeller adjustment p. 20, couplings pp. 20-21, disassembly §6 '
                               'p. 31, reassembly pp. 32-33, parts §7 p. 34',
     'url': 'https://www.mitchellewis.com/wp-content/uploads/2021/08/Xylem_ShortSet_Turbine_Manual.pdf'},
    {'id': GOULDS_VIC, 'cite': 'Goulds Water Technology (Xylem), Model VIC can pump, installation, operation and '
                               'maintenance instructions, IOMGWVICR01-EN: §6 pp. 26-28 disassembly and reassembly '
                               '(the same order as the VIT\'s)',
     'url': 'https://prod.xylem.com/siteassets/brand/goulds-water-technology/resources/manual/iomgwvicr01-en.pdf'},
    {'id': FLOWSERVE_VTP, 'cite': 'Flowserve, Vertical turbine pumps (VTP) wet pit, user instructions PCN 71569224: §6.8 '
                                  'disassembly (coupling apart, motor set down, seal off, head off, column sections '
                                  'apart with their bearing retainers, the bowl assembly last)',
     'url': 'https://www.manualsdir.com/manuals/766630/flowserve-vtp-wet-pit.html?page=51'},
    {'id': FLOWSERVE_POSTER, 'cite': 'Flowserve, VTP wet pit vertical turbine pump, poster FPD-1140a (2011): '
                                     'enclosed impellers on drive collets, the head\'s adjusting nut',
     'url': 'https://production.axflow.com/globalassets/catalog/eq/flowserve-vtp-wet-pit-poster-fpd-1140.pdf'},
    {'id': GOULDS_BROCHURE, 'cite': 'Goulds Water Technology, Vertical turbine pumps brochure BVERTTURB (2012): '
                                    'impellers semi-open or enclosed, fastened by taperlock or keyed',
     'url': 'https://www.andersonprocess.com/wp-content/uploads/2023/05/Goulds-Water-Technology-Vertical-Turbine-Pumps.pdf'},
    {'id': KSB_VANE, 'cite': 'KSB, Centrifugal pump lexicon: Vane (the outlet angle of a radial impeller below 90 '
                             'degrees, a backward-curved vane) and Direction of rotation (named as seen from the drive)',
     'url': 'https://www.ksb.com/en-global/centrifugal-pump-lexicon/article/vane-1118440'},
]

PARAMS = {'flow_m3h': 550, 'head_m': 30, 'motor_kw': 75, 'pit_depth': 6.5}
COLUMNS = 3       # the plant's column has a flanged joint every 3 m of the pit (parts_rotating.gd)
DERIVED = motor.DERIVED


def _c(name, does, material, sources, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': sources}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def _motor_components():
    """The vertical motor's tree (parts_common.gd motor_v): its words where the motor kind's say the same."""
    mk = motor.components('motor')
    own = {
        'motor': _c('Stator and frame', 'The stator\'s core and winding in the motor\'s frame: its rotating field turns '
                    'the rotor. The frame stands on the pump\'s motor stand by its mounting flange.',
                    'Cast iron or steel frame, electrical steel laminations, copper winding',
                    [motor.ABB, motor.WEG, motor.SIMOTICS]),
        'end_shield_de': _c('Drive-end bracket (mounting flange)', 'The flange the motor stands on, bolted to the '
                            'motor stand, with the lower guide bearing\'s housing round the shaft.', 'Cast iron',
                            [motor.WEG, motor.SIMOTICS]),
        'end_shield_nde': _c('Top bracket', 'Closes the frame at the top and holds the thrust bearing, which carries '
                             'the weight of the turning parts and the pump\'s thrust.', 'Cast iron',
                             [motor.WEG, GOULDS_VIT]),
        'drip_cover': _c('Drip cover', 'The canopy over the top of the motor: it keeps rain and drips out of the fan '
                         'and the top bracket.', 'Sheet steel or cast iron', [motor.WEG]),
        'fan': dict(mk['fan']),
        'rotor': _c('Rotor', 'The rotor\'s core on its shaft, hung in the thrust bearing; its shaft\'s lower end '
                    'carries the coupling\'s motor half.', 'Electrical steel laminations, aluminium or copper cage, '
                    'steel shaft', [motor.ABB, motor.WEG]),
        'bearing_thrust': _c('Thrust bearing (upper)', 'Carries the rotor\'s weight and the pump\'s downward thrust, '
                             'passed up through the coupling.', 'Bearing steel', [motor.WEG, GOULDS_VIT]),
        'bearing_guide': _c('Guide bearing (lower)', 'Keeps the shaft central at the drive end; it carries no '
                            'thrust.', 'Bearing steel', [motor.WEG]),
        'terminal_box': dict(mk['terminal_box']),
    }
    return own


def components():
    own = {
        'soleplate': _c('Sole plate', 'The steel plate over the pit the discharge head is bolted to, grouted into the '
                        'floor.', 'Fabricated steel, grout', [GOULDS_VIT]),
        'head': _c('Discharge head', 'Hangs the column and the bowls from the floor and turns the water out to the '
                   'discharge branch; its motor stand carries the motor, with windows to reach the coupling and the '
                   'seal.', 'Cast iron or fabricated steel', [GOULDS_VIT, FLOWSERVE_VTP]),
        'seal': _c('Packing box (shaft seal)', 'Seals the shaft where it leaves the head, under the motor stand '
                   '(packing or a mechanical seal).', 'Cast iron box, packing rings or seal faces',
                   [GOULDS_VIT, FLOWSERVE_VTP]),
        'shaft': _c('Pump shaft (lineshaft and bowl shaft)', 'Carries the impellers in the bowls and runs up the '
                    'column to the coupling, held central by the lineshaft bearings. Drawn as one shaft: a real one is '
                    'in sections joined by threaded couplings at the column\'s joints.', 'Carbon or stainless steel',
                    [GOULDS_VIT, FLOWSERVE_VTP]),
        'discharge_case': _c('Discharge case', 'Gathers the water from the top stage\'s bowl into the column; the '
                             'column\'s lowest section is bolted to it.', 'Cast iron', [GOULDS_VIT, FLOWSERVE_VTP]),
        'bowl_2': _c('Bowl, second stage', 'Holds the second impeller; its vanes turn the water from the impeller '
                     'upwards to the next stage.', 'Cast iron, enamel lined', [GOULDS_VIT]),
        'bowl_1': _c('Bowl, first stage', 'Holds the first impeller, bolted to the suction bell below and the next '
                     'bowl above.', 'Cast iron, enamel lined', [GOULDS_VIT]),
        'suction_bell': _c('Suction bell', 'The bell mouth the water comes in at from the pit, with the shaft\'s '
                           'bottom bearing in its hub.', 'Cast iron', [GOULDS_VIT, FLOWSERVE_VTP]),
        'impeller_1': _c('Impeller, first stage', 'An enclosed impeller, fastened to the shaft by its taperlock; its '
                         'vanes, curved back against the way it turns, fling the water outwards and up into the bowl.',
                         'Cast iron or bronze', [GOULDS_VIT, GOULDS_BROCHURE, FLOWSERVE_POSTER, KSB_VANE]),
        'impeller_2': _c('Impeller, second stage', 'The second stage\'s impeller, the same as the first, on its own '
                         'taperlock.', 'Cast iron or bronze', [GOULDS_VIT, GOULDS_BROCHURE, KSB_VANE]),
        'coupling': _c('Spacer coupling', 'Joins the pump\'s shaft to the motor\'s inside the motor stand; its '
                       'adjusting nut sets the impellers\' lift, and its spacer lets the seal be serviced without '
                       'lifting the motor. Drawn as one piece with its hubs.', 'Steel', [GOULDS_VIT, FLOWSERVE_POSTER]),
    }
    for i in range(COLUMNS):
        own['column_%d' % (i + 1)] = _c(
            'Column section %d' % (i + 1),
            'A length of the column pipe the water rises in' + (
                ', with its flanged joint below and the lineshaft bearing in its retainer there.' if i < COLUMNS - 1
                else ', bolted to the discharge case below.'), 'Steel pipe, bronze bearing', [GOULDS_VIT, FLOWSERVE_VTP])
    return dict(own, **_motor_components())


def _step(place, text, needs=(), why=None, sources=(GOULDS_VIT,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


def _mstep(place, text, needs=(), why=None):
    """A step of the vertical motor's own order: derived from how it is built (as the motor kind's)."""
    s = _step(place, text, needs, (why + ' ' if why else '') + DERIVED, sources=(motor.WEG,))
    return s


PULL = ('In the shop the whole pump (the head with the column and the bowls) is lifted out of the pit and laid down '
        'to be taken apart; the steps here fit each part where it stands.')

# The pump's reassembly (Goulds §6 pp. 32-33 for the bowls, installation §3 pp. 13-19 for the column and the head):
# the bowls stage by stage from the bell up (each impeller slid over the shaft and seated, its taperlock driven, the
# next bowl bolted on), the column sections and the lineshaft, the head, the seal; the motor set on the stand, its own
# parts first (its order derived from how it is built), the coupling and the impellers' lift. Taking apart is the
# reverse (Goulds §6 p. 31, Flowserve §6.8).
ASSEMBLY = [
    _step('soleplate', 'The sole plate stays grouted into the floor over the pit.'),
    _step('shaft', 'Stand the pump shaft up; the bowls go on over it from the bell up.', why=PULL,
          sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _step('suction_bell', 'Fit the suction bell on the shaft\'s lower end, its bearing over the shaft.',
          [('shaft', 'The bell goes on the shaft: stand the shaft up first.',
            'Take the bell off before the shaft is laid down.')]),
    _step('impeller_1', 'Slide the first impeller over the shaft until it seats in the bell, then drive its '
          'taperlock in.',
          [('suction_bell', 'The first impeller seats on the suction bell: fit the bell first.',
            'Take the first impeller off before the bell.')],
          why='Taking it apart, the impeller is driven off its taperlock with a taperlock driver.',
          sources=(GOULDS_VIT, GOULDS_VIC)),
    _step('bowl_1', 'Slide the first bowl over the impeller and bolt it to the bell.',
          [('impeller_1', 'The bowl closes over the first impeller: fit the impeller first.',
            'Take the first bowl off before its impeller.')]),
    _step('impeller_2', 'Slide the second impeller over the shaft and drive its taperlock in.',
          [('bowl_1', 'The second impeller seats on the first bowl: fit the bowl first.',
            'Take the second impeller off before the first bowl.')]),
    _step('bowl_2', 'Slide the second bowl over the impeller and bolt it on.',
          [('impeller_2', 'The bowl closes over the second impeller: fit the impeller first.',
            'Take the second bowl off before its impeller.')]),
    _step('discharge_case', 'Bolt the discharge case on top of the bowls.',
          [('bowl_2', 'The discharge case sits on the top bowl: fit the bowl first.',
            'Take the discharge case off before the bowls.')]),
    _step('column_3', 'Bolt the lowest column section to the discharge case.',
          [('discharge_case', 'The column stands on the discharge case: fit it first.',
            'Take the lowest column section off before the discharge case.')],
          sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _step('column_2', 'Fit the next column section with its lineshaft bearing retainer.',
          [('column_3', 'The column goes up section by section: fit the one below first.',
            'Take the column sections off from the top down.')], sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _step('joint_bolts_2', 'Bolt the joint between the two sections.',
          [('column_2', 'The bolts join the two sections: fit the upper one first.',
            'Take the joint\'s bolts out before the upper section comes off.')], sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _step('column_1', 'Fit the top column section with its lineshaft bearing retainer.',
          [('column_2', 'The column goes up section by section: fit the one below first.',
            'Take the column sections off from the top down.')], sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _step('joint_bolts_1', 'Bolt the joint between the two sections.',
          [('column_1', 'The bolts join the two sections: fit the upper one first.',
            'Take the joint\'s bolts out before the upper section comes off.')], sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _step('head', 'Fit the discharge head on the top column section and lower the pump into the pit onto the sole '
          'plate.',
          [('column_1', 'The head hangs the column: fit the top section first.',
            'Take the head off before the column sections.'),
           ('soleplate', 'The head stands on the sole plate: it is there first.',
            'The sole plate stays grouted into the floor.')], sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _step('head_bolts', 'Bolt the head down to the sole plate and connect the discharge pipe.',
          [('head', 'The bolts hold the head down: set it on the sole plate first.',
            'Take the head\'s bolts out before the pump is lifted out.')]),
    _step('seal', 'Fit the packing box over the shaft into the head\'s top.',
          [('head', 'The seal sits in the head\'s top: fit the head first.',
            'Take the seal off before the head.')], sources=(GOULDS_VIT, FLOWSERVE_VTP)),
    _mstep('motor', 'Set the motor\'s stator and frame on the motor stand and bolt its flange down.',
           [('head', 'The motor stands on the head\'s motor stand: fit the head first.',
             'Lift the motor off before the head is unbolted.')],
           why='Goulds and Flowserve lift the motor off first and set it on last.'),
    _mstep('end_shield_de', 'The drive-end bracket (the mounting flange) comes with the frame.',
           [('motor', 'The bracket closes the frame\'s bottom: set the frame first.',
             'The bracket stays on the frame.')]),
    _mstep('rotor', 'Lower the rotor into the stator.',
           [('end_shield_de', 'The rotor\'s shaft goes down through the drive-end bracket: it is there first.',
             'Lift the rotor out before the drive-end bracket is touched.')],
           why='Lifted by an eyebolt in its shaft\'s top.'),
    _mstep('bearing_guide', 'Fit the lower guide bearing on the rotor\'s shaft, in the drive-end bracket.',
           [('rotor', 'The bearing goes on the rotor\'s shaft: put the rotor in first.',
             'Take the guide bearing off the shaft before the rotor is lifted out.')],
           why='In the shop the bearings go on the shaft before the rotor is lowered in, and come off it once it is out '
               '(in the steps here they are fitted and taken off in place).'),
    _mstep('bearing_thrust', 'Fit the thrust bearing on the shaft\'s top.',
           [('rotor', 'The bearing goes on the rotor\'s shaft: put the rotor in first.',
             'Take the thrust bearing off the shaft before the rotor is lifted out.')]),
    _mstep('end_shield_nde', 'Fit the top bracket over the thrust bearing.',
           [('bearing_thrust', 'The bracket holds the thrust bearing: fit the bearing first.',
             'Take the top bracket off before the rotor is lifted.'),
            ('rotor', 'The bracket closes over the rotor: put the rotor in first.',
             'Take the top bracket off before the rotor is lifted.')]),
    _mstep('fan', 'Fit the fan on the shaft\'s top.',
           [('end_shield_nde', 'The fan sits above the top bracket: fit the bracket first.',
             'Take the fan off before the top bracket.')]),
    _mstep('drip_cover', 'Fit the drip cover over the fan.',
           [('fan', 'The cover closes over the fan: fit the fan first.', 'Take the drip cover off first.')]),
    _mstep('terminal_box', 'Fit the terminal box and connect the supply.',
           [('motor', 'The terminal box is on the frame: set the frame first.',
             'Take the terminal box off with the supply disconnected.')]),
    _step('coupling', 'Fit the spacer coupling between the shafts and set the impellers\' lift with its adjusting '
          'nut.',
          [('rotor', 'The coupling\'s top hub is on the motor\'s shaft: put the rotor in first.',
            'Take the coupling out before the motor\'s rotor is lifted.'),
           ('seal', 'The coupling turns above the seal: fit the seal first.',
            'Take the coupling out before the seal.'),
           ('motor', 'The coupling joins the pump to the motor: set the motor first.',
            'Take the coupling out before the motor is lifted.')],
          why='Turning the adjusting nut lifts the impellers just clear of their seats (Goulds p. 20).',
          sources=(GOULDS_VIT, FLOWSERVE_VTP)),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'pump_vertical',
        'params': PARAMS,
        'sources': SOURCES + motor.SOURCES,
        'components': components(),
        'fasteners': {
            'head_bolts': {'name': '8 hold-down bolts', 'joins': ['soleplate', 'head'], 'sources': [GOULDS_VIT]},
            'joint_bolts_1': {'name': '8 column joint bolts', 'joins': ['column_1', 'column_2'],
                              'sources': [GOULDS_VIT, FLOWSERVE_VTP]},
            'joint_bolts_2': {'name': '8 column joint bolts', 'joins': ['column_2', 'column_3'],
                              'sources': [GOULDS_VIT, FLOWSERVE_VTP]},
        },
        'assembly': ASSEMBLY,
        # the X-ray takes the head, the column, the bowls and the motor's casing; the cutaway opens a quarter on the
        # plate's side; nothing is opened while it turns (WORKSHOP.md §4.7: a rotating machine)
        'views': {'xray_all': ['head', 'column_1', 'column_2', 'column_3', 'discharge_case', 'bowl_2', 'bowl_1',
                               'suction_bell', 'motor', 'end_shield_de', 'drip_cover'],
                  'cutaway': {'planes': [{'normal': [0, 1, 0], 'offset': 0}, {'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['impeller_1', 'impeller_2', 'shaft', 'rotor']}},
    }
