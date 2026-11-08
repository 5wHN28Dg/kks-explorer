"""WDP-MAN-002, the control valve and its positioner (kit part `valve_control`). Generic, in our own words: the
structure and the facts follow the public manuals and standards listed in `sources`; no text is copied from them."""
from manual_blocks import S, H, P, UL, OL, TABLE, WARNING, CAUTION, NOTE, TROUBLE, UNIT, SERIES, PARTS

MANUAL = {
    'id': 'control_valve',
    'number': 'WDP-MAN-002',
    'title': 'Control valve with digital positioner',
    'short': 'CV',
    'kinds': ['valve_control'],
    'kind_names': {'valve_control': 'Control valve'},
    'params': {'dn': ('Nominal size', 'DN {}'), 'rating': ('Pressure rating', '{}'), 'actuator': ('Actuator', '{}')},
    'consumables': [
        ('packing_set', 'Stem packing set (PTFE V-rings or graphite rings, with spacer)', '1 set',
         'Sized to the stem; new at every repacking'),
        ('body_gasket', 'Bonnet gasket', '1', 'New whenever the bonnet comes off'),
        ('seat_ring_gasket', 'Seat ring gasket', '1', 'New with the seat ring'),
        ('trim_set', 'Trim set: plug, stem, seat ring, cage', '1 set', 'Plug and seat ring lapped together: the '
         'trim replaced as a set'),
        ('diaphragm', 'Actuator diaphragm', '1', 'New when it leaks or every major overhaul'),
        ('positioner', 'Digital positioner with feedback linkage', '1', 'Calibrated on the valve after fitting'),
        ('air_filter', 'Air filter regulator element', '1', 'Every year, or when the drain shows oil or water'),
    ],
    'sources': [
        {'id': 'fcvh', 'cite': 'Emerson, Control Valve Handbook (fifth edition): valve and actuator types, packing, '
         'flow characteristics, cavitation and flashing, stiction and dead band, installation and maintenance'},
        {'id': 'dvc', 'cite': 'Emerson, Fisher FIELDVUE DVC6200 digital valve controller instruction manual: '
         'mounting, air supply, travel calibration, tuning, alerts and diagnostics'},
        {'id': 'fci702', 'cite': 'ANSI/FCI 70-2, Control valve seat leakage: the leakage classes and their tests'},
        {'id': 'isa7525', 'cite': 'ANSI/ISA-75.25.01, Test procedure for control valve response measurement from '
         'step inputs'},
    ],
    'sections': [
        S('description', 'Description', [
            P('A **control valve** throttles a flow to the opening the control system asks for. The plant\'s control '
              'valves are globe valves with a pneumatic spring-and-diaphragm actuator and a digital **positioner**; a '
              'few large ones are worked by an electric or hydraulic actuator.'),
            UL('**Body and trim:** the plug moves in a seat ring (or inside a cage) and the gap between them sets the '
               'flow. The trim\'s shape gives the characteristic: *linear* (flow in step with travel) or *equal '
               'percentage* (each step of travel adds the same fraction of the flow there already is).',
               '**Bonnet and packing:** the stem leaves the body through the packing, rings squeezed round the stem '
               'by the packing flange so the process cannot leak along it.',
               '**Actuator:** air on a diaphragm pushes against springs. *Fail closed* (air to open) or *fail open* '
               '(air to close): on loss of air or signal the springs drive the valve to its safe position.',
               '**Positioner:** compares the `4–20 mA` demand with the stem\'s travel (fed back by a linkage or a '
               'magnet) and sends air to the actuator until they agree. It speaks HART, and keeps diagnostics: '
               'travel deviation, friction, cycles, supply pressure.'),
        ], src=['fcvh', 'dvc']),
        S('specifications', 'Specifications', [
            UNIT(),
            P('What the generic plant\'s parts kit allows for these kinds (the limits of the model, not a '
              'product\'s ratings):'),
            SERIES(),
            TABLE(['Item', 'Value'], [
                ['Signal', '`4–20 mA` with HART to the positioner'],
                ['Air supply', 'clean, dry instrument air, `4` to `6 bar`, regulated to the actuator\'s rating'],
                ['Seat leakage', 'class IV metal seated as standard; class V or VI where the duty asks'],
                ['Travel deviation alert', 'usually `5 %` for `10 s`'],
            ]),
        ], src=['fcvh', 'fci702']),
        S('installation', 'Installation', [
            UL('Flush the line before the valve goes in: weld beads and scale ruin seats.',
               'Install with the flow arrow on the body pointing the way the process flows.',
               'Upright, actuator on top, is best; another position needs a support for the actuator.',
               'Leave room above for the actuator and bonnet to come off, and a straight run upstream.',
               'Fit isolating valves and a bypass so the valve can be taken out with the plant running.',
               'Bring instrument air through a filter regulator; blow the air line through before connecting it.'),
        ], src=['fcvh']),
        S('commissioning', 'Commissioning', [
            OL('Check the air supply pressure at the positioner against the actuator\'s plate.',
               'With the valve isolated, run the positioner\'s **travel calibration**: it finds the closed and open '
               'ends of travel by itself, then sets its zero and span.',
               'Run its **tuning** for the actuator\'s size, or pick the tuning set its maker gives for it.',
               'Stroke test with the control room: `0`, `25`, `50`, `75`, `100 %` and back. The travel the positioner '
               'reports, the position on the screen and the stem\'s scale agree.',
               'Time a full stroke both ways, and check the fail action: take the air off and see it go to its safe '
               'position.',
               'Check its limit switches, if fitted, at both ends.'),
            NOTE('Keep the calibration\'s report and the first step response: later diagnostics are compared with '
                 'them.'),
        ], src=['dvc', 'isa7525']),
        S('operation', 'Operation', [
            P('The valve is worked from the control room. Locally, a handwheel (where fitted) moves it when the air '
              'is lost; put the handwheel back to neutral before the positioner takes over again.'),
            UL('Throttling close to its seat for long wears the plug and seat (wire drawing). A valve that spends its '
               'life below `10 %` open is too big for its duty.',
               '**Cavitation** (liquid that boils at the vena contracta and collapses again) sounds like gravel in '
               'the pipe and eats the trim; **flashing** (liquid that stays boiled) erodes the body downstream.'),
        ], src=['fcvh']),
        S('maintenance', 'Maintenance', [
            TABLE(['Interval', 'Task'], [
                ['Every round', 'Look and listen: packing leaks, air leaks, noise, the stem moving smoothly'],
                ['3 months', 'Read the positioner\'s diagnostics: travel deviation, friction, supply pressure'],
                ['12 months', 'Drain and check the air filter; a step response test; tighten the packing if it weeps'],
                ['At overhaul', 'Repack, inspect trim and seat, lap or replace; new gaskets; recalibrate'],
            ]),
            H('Packing'),
            P('Tighten the packing nuts evenly, a little at a time, only until the leak stops. Overtightened packing '
              'grips the stem: the friction rises, the valve sticks and then jumps (stiction), and the loop hunts.'),
        ], src=['fcvh', 'dvc']),
        S('troubleshooting', 'Troubleshooting', [
            TROUBLE(
                ('The loop hunts; the valve moves in small jumps',
                 'Stiction: packing too tight, a worn stem, or a dry actuator',
                 'Read the friction in the diagnostics; loosen or renew the packing; never retune the loop to hide it'),
                ('The valve does not reach full travel',
                 'Air supply too low, a leak in the actuator\'s diaphragm or tubing, or a travel stop set wrong',
                 'Check the supply pressure, listen for leaks, renew the diaphragm, recalibrate'),
                ('Travel deviation alert; the valve slow to answer',
                 'Low supply, a blocked filter, or a sticking relay in the positioner',
                 'Drain and renew the filter element; check the relay; compare with the first step response'),
                ('Leaks through when closed',
                 'Seat and plug worn or cut, foreign matter in the seat, or the actuator not seating it',
                 'Check the travel calibration seats it; lap or renew the trim'),
                ('Leaks at the stem', 'Packing worn or loose', 'Tighten evenly; repack at the next chance'),
                ('Noise like gravel, trim eroded',
                 'Cavitation', 'Check the pressure drop against its sizing; an anti-cavitation trim'),
                ('Goes to its fail position by itself', 'Loss of air or of the `4–20 mA` signal',
                 'Check the air supply and the loop current at the positioner'),
            ),
        ], src=['fcvh', 'dvc', 'fci702']),
        S('parts', 'Spare parts', [
            P('Part numbers are the generic plant\'s catalogue.'),
            PARTS(),
        ], src=['fcvh']),
        S('safety', 'Safety', [
            WARNING('Before working on the valve: the permit in place, the valve isolated, drained and vented, the air '
                    'supply shut and the actuator\'s air vented. A spring-loaded actuator stores energy: release the '
                    'spring\'s compression as its maker says before the actuator is taken apart.'),
            CAUTION('A valve that moves when the positioner is calibrated can upset the plant: calibrate only with the '
                    'valve isolated or the control room\'s agreement.'),
        ], src=['fcvh', 'dvc']),
    ],
}
