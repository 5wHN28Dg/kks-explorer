"""The plate heat exchanger's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a gasketed plate heat
exchanger whose plate package is pressed between a fixed frame plate and a pressure plate by tightening and locking
bolts, the plates hanging from a carrying bar and kept in line by a guiding bar, the bars held at their far end by a
support column. Its geometry is the kit's generator, apps/plant3d/kit/parts_heat.gd `plate_hx`.

The parts, their names and the order follow the Grundfos by Alfa Laval plate heat exchangers' maintenance manual (the
main components, the bolt layout, opening and closing the plate package, the plates out and in). The plate package is
drawn as End plate II, the channel plates and End plate I, the plates thicker than real ones (a picture: the pack's
length is the plant's). Generic: no plant data. The parameters are the plate heat exchanger the plant has (300
plates, 2.5 m high).
"""

ALFA = 'alfa_phe'

SOURCES = [
    {'id': ALFA, 'cite': 'Alfa Laval, Grundfos by Alfa Laval plate heat exchangers, maintenance manual 200019583-2-EN-GB '
                         '(2026-07): main components pp. 16-18, bolt configuration p. 35, opening (steps 1-15) pp. '
                         '45-48, torque p. 49, closing (steps 1-17) pp. 50-52, plates out and in p. 55',
     'url': 'https://assets.alfalaval.com/documents/p99dbc05b/alfa-laval-grundfos-maintenance-manual-phe-en-gb.pdf'},
]

PARAMS = {'plates': 300, 'height': 2.5}


def _c(name, does, material, sources=(ALFA,)):
    return {'name': name, 'does': does, 'material': material, 'sources': list(sources)}


def components():
    return {
        'frame_plate': _c('Frame plate', 'The fixed plate, with the portholes and the four connections to the pipes. '
                          'The plate package is pressed against it; it stays on its foundation with its pipes on '
                          'when the exchanger is opened.', 'Painted carbon steel'),
        'pressure_plate': _c('Pressure plate', 'The moveable plate that compresses the plate package against the '
                             'frame plate. It hangs from the carrying bar and is pushed back along it to open the '
                             'package.', 'Painted carbon steel'),
        'carrying_bar': _c('Carrying bar', 'Carries the plate package and the pressure plate. Its sliding surfaces are '
                           'cleaned and greased before the pressure plate is moved.', 'Steel'),
        'guiding_bar': _c('Guiding bar', 'Keeps all the plates aligned at their lower end.', 'Steel'),
        'support_column': _c('Support column', 'Supports the carrying bar and the guiding bar at their far end.',
                             'Painted carbon steel'),
        'end_plate_2': _c('End plate II', 'The plate next to the frame plate, the first one hung on the carrying bar '
                          'when the package is closed.', 'Stainless steel plate with its gasket'),
        'plates': _c('Channel plates', 'The plates that transfer heat: the two fluids flow in the channels between '
                     'them, every other channel each. Each plate carries a gasket that seals between the channels '
                     'and to the surroundings.', 'Stainless steel plates with elastomer gaskets'),
        'end_plate_1': _c('End plate I', 'The plate next to the pressure plate, the first one off when the package is '
                          'opened.', 'Stainless steel plate with its gasket'),
    }


def _step(place, text, needs=(), why=None, sources=(ALFA,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# Closing the plate package (Alfa Laval pp. 50-52, the plates hung by the hanging list p. 55), each part in its place,
# a part's parent first. Opening it (pp. 45-48) is the reverse: the locking bolts first, then the tightening bolts,
# the pressure plate pushed back, the plates out one by one.
ASSEMBLY = [
    _step('frame_plate', 'The frame plate stays on its foundation, its pipes connected.',
          why='All four connections are on the frame plate here, so the package opens without undoing a pipe; '
              'pipes on a pressure plate are taken off first (opening, step 3).'),
    _step('support_column', 'The support column stays where it stands.',
          why='If there is a support foot under the guiding bar, it stays where it is (opening, step 7).'),
    _step('carrying_bar', 'The carrying bar stays between the frame plate and the support column: wipe its sliding '
          'surfaces clean and grease them.',
          [('frame_plate', 'The carrying bar hangs from the frame plate.', 'The frame plate stays.'),
           ('support_column', 'The carrying bar rests on the support column.', 'The support column stays.')],
          why='Opening, step 4: the pressure plate slides along it.'),
    _step('guiding_bar', 'The guiding bar stays between the frame plate and the support column.',
          [('frame_plate', 'The guiding bar is fixed to the frame plate.', 'The frame plate stays.'),
           ('support_column', 'The guiding bar rests on the support column.', 'The support column stays.')]),
    _step('end_plate_2', 'Hang End plate II on the carrying bar, against the frame plate.',
          [('carrying_bar', 'The plates hang from the carrying bar.', 'Take the plates off before the carrying '
            'bar.'),
           ('guiding_bar', 'The guiding bar keeps the plates in line at the bottom.', 'Take the plates off before the '
            'guiding bar.')],
          why='Check first that every gasket sits in its groove and every sealing surface is clean (closing, steps '
              '1 and 3).'),
    _step('plates', 'Hang the channel plates one by one, in the order and the way round the plate hanging list '
          'gives, each pressed towards the frame plate by its upper part.',
          [('end_plate_2', 'The channel plates go against End plate II.', 'Take the channel plates off before End '
            'plate II.')],
          why='Taking them out, each plate is lifted off by itself, by hand or with a lifting device for large ones, '
              'never by the edges round its portholes (p. 55). The diagonal line drawn on the package before it '
              'was opened shows when a plate is out of order.'),
    _step('end_plate_1', 'Hang End plate I last, next to where the pressure plate comes.',
          [('plates', 'End plate I goes against the last channel plate.', 'End plate I comes off first.')]),
    _step('pressure_plate', 'Push the pressure plate along the carrying bar against the plate package and press the '
          'package together.',
          [('end_plate_1', 'The pressure plate closes the package: hang all the plates first.',
            'Push the pressure plate back before the plates come off.')],
          why='Opening, step 13: the pressure plate is pushed gently away from the frame plate once the bolts are '
              'out.'),
    _step('tightening_bolts', 'Put the tightening bolts in place and tighten them crosswise until the package '
          'measures 1.2 times the A-measurement, the frame plate and the pressure plate kept parallel; then let the '
          'package rest for an hour if possible.',
          [('pressure_plate', 'The tightening bolts pull the pressure plate in: push it against the package first.',
            'Take the tightening bolts out before the pressure plate is pushed back.')],
          why='Closing, steps 5 to 8. Opening, steps 9 to 12: the threads brushed and greased, the bolts loosened '
              'keeping the plates parallel (no more than 10 mm skew across, 25 mm up and down), then taken out. The '
              'A-measurement, noted before opening (step 6), is what counts, not the torque (p. 49).'),
    _step('locking_bolts', 'Put the locking bolts in place, then tighten all the bolts crosswise until the '
          'A-measurement is reached.',
          [('tightening_bolts', 'The locking bolts go in at 1.2 times the A-measurement, after the tightening '
            'bolts.', 'Take the locking bolts out before the tightening bolts are loosened.')],
          why='Closing, steps 9 and 10, then the protection sheets, the pipes and the pressure plate\'s feet back on '
              'and a hydrostatic test (steps 13 to 16). Opening starts here: the exchanger cooled to about 40 °C and '
              'drained, the protection sheets off, a diagonal line drawn on the package, the A-measurement noted, the '
              'feet at the pressure plate off (steps 1 to 7), then the locking bolts out (step 8).'),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'plate_hx',
        'params': PARAMS,
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'tightening_bolts': {'name': '4 tightening bolts', 'joins': ['pressure_plate', 'frame_plate'],
                                 'sources': [ALFA]},
            'locking_bolts': {'name': '2 locking bolts', 'joins': ['pressure_plate', 'frame_plate'],
                              'sources': [ALFA]},
        },
        'assembly': ASSEMBLY,
        # the X-ray takes the frame and pressure plates; the cutaway opens the package down its middle, across the
        # plates, so the plates show between the frame plate and the pressure plate
        'views': {'xray_all': ['frame_plate', 'pressure_plate'],
                  'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['carrying_bar', 'guiding_bar', 'support_column']}},
    }
