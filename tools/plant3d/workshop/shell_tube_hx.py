"""The shell-and-tube heat exchanger's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K6): a horizontal
exchanger with a removable straight-tube bundle, a bonnet at each end and a packed floating tubesheet with a lantern
ring at the rear (TEMA type BEW). Its geometry is the kit's generator, apps/plant3d/kit/parts_heat.gd
`shell_tube_hx` (horizontal; the vertical one has no tree yet).

Why this type: the plant's generator draws a flanged bonnet on the front end, a bonnet without a flange on the rear
end with the tube side's inlet there (one tube pass, straight tubes), and the public manuals take apart a packed
floating end of this kind step by step (the Xylem Standard Xchange CPK manual: bonnet or channel, lantern ring,
packing rings, then the bundle drawn from the stationary end; API Heat Transfer's Basco guide for the AEW/BEW and BEP
types). Neither gives a numbered strip-down of a split-ring floating head (TEMA S), so the tree is not that one.

Generic: no plant data. The plant has no shell-and-tube exchanger: the parameters are the kit's defaults (1.2 m,
5 m long, horizontal).
"""

CPK = 'xylem_cpk'
BASCO = 'basco_st'

SOURCES = [
    {'id': CPK, 'cite': 'Xylem, Standard Xchange CPK shell and tube heat exchangers, IOM manual 0120-1 (January 2020), '
                        'printed pages (the PDF\'s are one more): construction Fig. 1 p. 7; maintenance items 1-15 '
                        'pp. 15-18; packing rings a-h p. 19; torque and the 16-bolt pattern p. 20',
     'url': 'https://prod.xylem.com/siteassets/brand/standard-xchange/resources/manual/cpk-shell-tube-iom_0120-1-rev-0.pdf'},
    {'id': BASCO, 'cite': 'API Heat Transfer, Basco shell and tube heat exchangers installation and maintenance guide R9: '
                          'the types p. 2, tube joint leaks and bundle removal p. 4, gaskets p. 6, type OP (TEMA '
                          'AEW/BEW) p. 7, outside packed (AEP/BEP) p. 8',
     'url': 'https://www.apiheattransfer.com/wp-content/uploads/2026/07/Basco-Installation-Guide-ShellandTube_R9.pdf'},
]

PARAMS = {'d': 1.2, 'length': 5, 'orientation': 'horizontal'}


def _c(name, does, material, sources=(CPK,), sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': list(sources)}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def components():
    return {
        'shell': _c('Shell', 'Holds the shell-side fluid round the tubes, between the stationary tubesheet and the '
                    'packing at the floating end. It stays on its saddles with its pipes when the bundle comes out.',
                    'Carbon steel'),
        'saddles': _c('Saddles', 'Carry the shell on its foundation. The foundation bolts at the floating end are left '
                      'loose so the shell can expand.', 'Painted carbon steel', (CPK, BASCO)),
        'bundle': _c('Tube bundle (stationary tubesheet)', 'The tubes, their two tubesheets, the baffles and the tie '
                     'rods, drawn out of the shell as one from the stationary end. This tubesheet, at the front, '
                     'is held at the joint between the shell and the front bonnet.', 'Steel tubesheet',
                     sealed_why='The tubes are expanded into both tubesheets and the baffles are held on the tie rods: '
                                'the bundle is pulled, carried and cleaned as one and never taken apart in the field '
                                '(a leaking tube joint is rolled again or the tube plugged).'),
        'tubesheet_f': _c('Floating tubesheet', 'The tubes\' other end. It slides in the packing as the tubes grow '
                          'longer than the shell when hot, so the bundle can expand without strain.', 'Steel'),
        'tubes': _c('Tubes', 'Carry the tube-side fluid from end to end; heat passes through their walls. Their ends '
                    'are expanded into the tubesheets.', 'Copper alloy or stainless steel tubes'),
        'baffles': _c('Baffles', 'Support the tubes along their length and lead the shell-side fluid across them, '
                      'from one side to the other.', 'Steel plates'),
        'tie_rods': _c('Tie rods and spacers', 'Hold the baffles in place along the bundle.', 'Steel'),
        'packing_in': _c('Inner packing rings', 'Seal the shell side round the floating tubesheet.',
                         'Packing rings (braided)'),
        'lantern_ring': _c('Lantern ring', 'Sits between the two sets of packing rings: a leak past either set comes '
                           'out at the tell-tale holes beside it instead of mixing the two fluids.', 'Bronze or steel',
                           (CPK, BASCO)),
        'packing_out': _c('Outer packing rings', 'Seal the tube side round the floating tubesheet.',
                          'Packing rings (braided)'),
        'rear_bonnet': _c('Rear bonnet', 'Closes the tube side at the floating end, with the tube-side inlet. It '
                          'presses the packing rings in when it is bolted up.', 'Carbon steel', (CPK, BASCO)),
        'front_bonnet': _c('Front bonnet', 'Closes the tube side at the stationary end, with the tube-side outlet. It '
                           'comes off to look at the tube ends or to draw the bundle.', 'Carbon steel', (CPK, BASCO)),
    }


def _step(place, text, needs=(), why=None, sources=(CPK,)):
    s = {'place': place, 'text': [text], 'sources': list(sources)}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# The reassembly, each part in its place, a part's parent first; taking apart is the reverse (CPK items 3-6 and 16,
# Basco p. 4 and p. 7): the front bonnet's studs and the bonnet, the rear bonnet, the packing and the lantern ring,
# then the bundle drawn out of the stationary end.
ASSEMBLY = [
    _step('shell', 'The shell stays on its saddles with its pipes.',
          why='The bundle comes out of the shell; the shell itself is not moved.', sources=(CPK, BASCO)),
    _step('saddles', 'The saddles stay on the foundation.',
          [('shell', 'The saddles carry the shell.', 'The shell stays on its saddles.')], sources=(BASCO,)),
    _step('bundle', 'Push the tube bundle into the shell from the stationary end, the floating tubesheet first, '
          'level, until the stationary tubesheet sits on the shell\'s flange.',
          [('shell', 'The bundle goes into the shell.', 'Draw the bundle out before the shell is moved.')],
          why='Drawn out, it is pulled from the floating tubesheet with rods through two or more tubes and bearing '
              'plates at each end (a jack on the floating tubesheet breaks it free if it has stuck), carried by its '
              'tubesheets and baffles in a cradle, never by the tubes, and never dragged (CPK items 6 to 10).',
          sources=(CPK, BASCO)),
    _step('tubesheet_f', 'The floating tubesheet comes with the bundle, at its far end.'),
    _step('tubes', 'The tubes come with the bundle, expanded into both tubesheets.',
          why='A leaking tube joint is rolled again with a parallel roller expander, no deeper than the tubesheet '
              'less 1/8 inch (CPK item 14).'),
    _step('baffles', 'The baffles come with the bundle, on their tie rods.'),
    _step('tie_rods', 'The tie rods and spacers come with the bundle.'),
    _step('packing_in', 'Slide the first packing rings over the floating tubesheet into the recess in the shell\'s '
          'flange, not twisted and square in the recess.',
          [('bundle', 'The packing seals round the floating tubesheet: put the bundle in first.',
            'Take the packing out before the bundle is drawn.')],
          why='CPK item 16 c; new packing rings at every reassembly (item 15).'),
    _step('lantern_ring', 'Slide the lantern ring over the floating tubesheet against the packing rings.',
          [('packing_in', 'The lantern ring goes against the first packing rings.',
            'Take the lantern ring out before the first packing rings.')], why='CPK item 16 d.'),
    _step('packing_out', 'Slide the remaining packing rings over the floating tubesheet against the lantern ring, not '
          'twisted.',
          [('lantern_ring', 'The second packing rings go against the lantern ring.',
            'Take the second packing rings out before the lantern ring.')], why='CPK item 16 e.'),
    _step('rear_bonnet', 'Set the rear bonnet on with its studs finger tight, the second packing ring in the bonnet\'s '
          'recess, then tighten each nut one or two turns.',
          [('packing_out', 'The bonnet presses the packing in: fit all the rings first.',
            'Take the rear bonnet off before the packing rings come out.')],
          why='CPK item 16 f and g: the gap between the flanges is then about 3/8 inch; the packing is set when the '
              'exchanger is tested or started (h). The plant draws this bonnet without its flange: its studs are '
              'not drawn.', sources=(CPK, BASCO)),
    _step('front_bonnet', 'Fit new gaskets and set the front bonnet on the stationary tubesheet.',
          [('bundle', 'The front bonnet closes over the stationary tubesheet: put the bundle in first.',
            'Take the front bonnet off before the bundle is drawn.')],
          why='Composition gaskets dry out and metal ones work-harden in service: new ones every time (CPK item 15, '
              'Basco p. 6).', sources=(CPK, BASCO)),
    _step('bonnet_bolts', 'Fit the front bonnet\'s studs and tighten them evenly in the crisscross order, to the '
          'torque the manual gives for their size.',
          [('front_bonnet', 'The studs hold the bonnet: set it on first.',
            'Take the studs out before the front bonnet comes off.')],
          why='CPK items 18 and 19 (the 16-bolt pattern). Before anything is undone the exchanger is shut down, '
              'relieved of all pressure and both sides drained (CPK item 3, Basco p. 4).', sources=(CPK, BASCO)),
]


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'shell_tube_hx',
        'params': PARAMS,
        'sources': SOURCES,
        'components': components(),
        'fasteners': {
            'bonnet_bolts': {'name': '32 front bonnet studs and nuts', 'joins': ['front_bonnet', 'shell'],
                             'sources': [CPK]},
        },
        'assembly': ASSEMBLY,
        # the X-ray takes the shell and the bonnets; the cutaway opens it along its axis so the bundle shows inside
        'views': {'xray_all': ['shell', 'front_bonnet', 'rear_bonnet'],
                  'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}],
                              'keep': ['tubes', 'tie_rods']}},
    }
