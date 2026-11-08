"""WDP-MAN-003, manual and check valves (kit parts `valve_gate`, `valve_globe`, `valve_ball`, `valve_butterfly`,
`valve_check`). Generic, in our own words: the structure and the facts follow the public documents listed in
`sources`; no text is copied from them."""
from manual_blocks import S, H, P, UL, OL, TABLE, WARNING, CAUTION, NOTE, TROUBLE, UNIT, SERIES, PARTS

MANUAL = {
    'id': 'valves',
    'number': 'WDP-MAN-003',
    'title': 'Manual and check valves: gate, globe, ball, butterfly, check',
    'short': 'MV',
    'kinds': ['valve_gate', 'valve_globe', 'valve_ball', 'valve_butterfly', 'valve_check'],
    'kind_names': {'valve_gate': 'Gate valve', 'valve_globe': 'Globe valve', 'valve_ball': 'Ball valve',
                   'valve_butterfly': 'Butterfly valve', 'valve_check': 'Check valve'},
    'params': {'dn': ('Nominal size', 'DN {}'), 'rating': ('Pressure rating', '{}'), 'actuator': ('Operator', '{}')},
    'consumables': [
        ('packing_set', 'Stem packing rings (graphite or PTFE), by size', '1 set', 'New at every repacking'),
        ('bonnet_gasket', 'Bonnet or cover gasket, by size and rating', '1', 'New whenever the bonnet comes off'),
        ('seat_set', 'Ball valve seats and seals, by size', '1 set', 'Soft seats: replaced, never lapped'),
        ('liner', 'Butterfly valve liner (resilient seat), by size', '1', 'New when it is cut or has taken a set'),
        ('disc_hinge_pin', 'Swing check valve hinge pin and bushes', '1 set', 'New when the disc is loose on its pin'),
        ('stem_nut', 'Stem nut (yoke bush)', '1', 'New when the handwheel turns with backlash or the thread is worn'),
    ],
    'sources': [
        {'id': 'api598', 'cite': 'API Standard 598, Valve inspection and testing: shell, backseat and seat tests'},
        {'id': 'api600', 'cite': 'API Standard 600, Steel gate valves: flanged and butt-welding ends, bolted '
         'bonnets (body, bonnet, wedge, stem, backseat, packing)'},
        {'id': 'fcvh', 'cite': 'Emerson, Control Valve Handbook (fifth edition): valve body types, packing, '
         'leakage, maintenance'},
        {'id': 'liptak', 'cite': 'B. G. Lipták (ed.), Instrument Engineers\' Handbook, vol. 2, Process Control and '
         'Optimization: valve types and their uses'},
    ],
    'sections': [
        S('description', 'Description', [
            P('Manual valves isolate (open or shut) or, for a globe valve, throttle by hand. A check valve lets flow '
              'one way only and needs no operator at all.'),
            TABLE(['Kind', 'How it shuts', 'Use it for', 'Do not'], [
                ['**Gate**', 'A wedge slides across the bore on a rising stem', 'Isolation, fully open or fully shut',
                 'Throttle: the wedge chatters and its seat faces cut'],
                ['**Globe**', 'A disc comes down onto a seat across the flow', 'Throttling, and isolation of small '
                 'lines', 'Expect a low pressure drop: the flow turns twice'],
                ['**Ball**', 'A bored ball turns a quarter turn', 'Quick isolation, tight shut-off', 'Throttle: soft '
                 'seats are cut by the jet'],
                ['**Butterfly**', 'A disc on a shaft turns a quarter turn in the bore', 'Isolation of large, low '
                 'pressure lines; rough throttling', 'Leave it near shut for long: the liner wears'],
                ['**Check**', 'A swinging or lifting disc, shut by back flow and its own weight', 'Stopping reverse '
                 'flow after pumps and at branches', 'Install it the wrong way round: it then blocks the line'],
            ]),
            P('Large or high pressure valves have a gearbox or an electric, pneumatic or hydraulic actuator in place of '
              'the handwheel. The stem passes through **packing** in the bonnet; gate and globe valves have a '
              '**backseat**, a seat on the stem that seals the packing off when the valve is fully open.'),
        ], src=['api600', 'liptak', 'fcvh']),
        S('specifications', 'Specifications', [
            UNIT(),
            SERIES(),
            NOTE('A valve\'s pressure rating (PN) is the pressure it may hold at room temperature; it may hold less '
                 'when hot. Its body is marked with the size, rating, material and the flow arrow where it has one.'),
        ], src=['api600']),
        S('installation', 'Installation', [
            UL('Clean the line and the valve\'s ends; take off end covers only when fitting.',
               'Check the flow arrow on globe and check valves; a gate or ball valve may go either way.',
               'Bolt flanges up crosswise to even gasket stress; never pull pipe into line with the valve\'s bolts.',
               'Leave room to turn the handwheel and to take the bonnet off.',
               'A swing check valve goes in horizontal lines, or in vertical lines with the flow upward only.',
               'Keep check valves at least five pipe diameters downstream of a pump or elbow, where the flow is '
               'steady, so the disc does not flutter.'),
        ], src=['api600', 'fcvh']),
        S('commissioning', 'Commissioning', [
            OL('Stroke every valve once fully open and fully shut before the line is filled: it must move freely.',
               'Fill and vent the line slowly with the valve open.',
               'Check the packing and the bonnet joint for leaks once the line is at pressure; tighten the packing '
               'evenly if it weeps.',
               'For an actuated valve, check its open and shut limit switches and its stroke time with the control '
               'room.'),
        ], src=['api598']),
        S('operation', 'Operation', [
            UL('Open and shut by hand only: a wheel key or a bar on the handwheel bends the stem or cracks the yoke.',
               'Open a gate or globe valve fully, then back it off a quarter turn from the backseat, so it does not '
               'jam open when it heats up.',
               'Open a valve across a large pressure difference slowly, or open its bypass first to warm and '
               'equalise the line.',
               'Shut a valve until it seats, then no more: forcing it damages the seat.',
               'Lock valves in their position where the procedure or the isolation says so (a chain and padlock).'),
            CAUTION('A valve that is hard to turn is telling you something: dirt in the seat, a dry stem thread, packing '
                    'too tight, or a line pressure difference. Find out before using more force.'),
        ], src=['api600', 'fcvh']),
        S('maintenance', 'Maintenance', [
            TABLE(['Interval', 'Task'], [
                ['Every round', 'Leaks at the packing, bonnet and flanges; the stem clean'],
                ['6 months', 'Grease the stem thread and the stem nut; stroke valves that are never moved'],
                ['12 months', 'Check the gearbox oil or grease; check the packing\'s gland follower has adjustment left'],
                ['At overhaul', 'Repack; lap gate and globe seats or replace soft seats; new bonnet gasket; seat test'],
            ]),
            H('Repacking under pressure'),
            P('Only on a gate or globe valve with a backseat, only if the procedure allows it: open it fully onto its '
              'backseat, then the packing may be renewed. Otherwise isolate and depressurise first.'),
        ], src=['api598', 'api600']),
        S('troubleshooting', 'Troubleshooting', [
            TROUBLE(
                ('Leak at the stem', 'Packing worn or loose', 'Tighten the gland nuts evenly; repack'),
                ('Leaks through when shut', 'Dirt on the seat, a cut seat or wedge, or not fully shut',
                 'Open a little and shut again to flush it; lap or replace the seats'),
                ('Hard to turn', 'Dry stem thread, packing too tight, a bent stem, or a pressure difference',
                 'Grease the thread; ease the packing; check for a bent stem; equalise across it'),
                ('Handwheel turns, valve does not move', 'Worn stem nut or a broken stem',
                 'Replace the stem nut or the stem'),
                ('Check valve chatters or slams', 'Too little flow to hold it open, or too close to a pump or elbow',
                 'Check the flow and the valve\'s position; a valve of another size or kind'),
                ('Reverse flow through a check valve', 'Disc stuck open, worn seat, or a broken hinge pin',
                 'Open it up; replace the seat or the hinge pin and bushes'),
            ),
        ], src=['api598', 'fcvh']),
        S('parts', 'Spare parts', [
            P('Part numbers are the generic plant\'s catalogue; each is ordered by the valve\'s size and rating.'),
            PARTS(),
        ], src=['api600']),
        S('safety', 'Safety', [
            WARNING('Never take a bonnet, cover or flange off a valve that is not isolated on both sides, drained and '
                    'vented. Pressure trapped in the body cavity of a shut gate or ball valve stays there: vent it.'),
            UL('Hot lines stay hot after isolation: gloves and a face shield when venting.',
               'An actuated valve may move without warning: isolate its power or air before putting a hand near it.'),
        ], src=['api598', 'api600']),
    ],
}
