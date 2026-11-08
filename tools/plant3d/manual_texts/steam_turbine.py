"""WDP-MAN-005, the steam turbine, an overview (kit part `steam_turbine`). Generic, in our own words: the structure
and the facts follow the public papers and handbooks listed in `sources`; no text is copied from them."""
from manual_blocks import S, H, P, UL, OL, TABLE, WARNING, CAUTION, NOTE, FIG, TROUBLE, UNIT, SERIES, PARTS

_ROWS = {'srow_%s%d' % (h, i): 'carrier_%s' % ('upper' if h == 'u' else 'lower') for h in 'ul' for i in range(1, 9)}
_ROWS.update({'mrow_%d' % i: 'rotor' for i in range(1, 9)})

MANUAL = {
    'id': 'steam_turbine',
    'number': 'WDP-MAN-005',
    'title': 'Steam turbine: an overview',
    'short': 'ST',
    'kinds': ['steam_turbine'],
    'kind_names': {'steam_turbine': 'Steam turbine'},
    'params': {'length': ('Length', '{} m'), 'd': ('Casing diameter', '{} m'), 'casings': ('Casings', '{}'),
               'exhaust': ('Exhaust', '{}')},
    'comes_with': _ROWS,
    'consumables': [
        ('joint_compound', 'Horizontal joint sealing compound', 'as needed', 'A thin even coat at every closing'),
        ('gland_segments', 'Labyrinth gland seal segments with springs', '1 set', 'Replaced when the fins are '
         'rubbed or the clearance is over its limit'),
        ('bearing_shells', 'Journal bearing shells, white metal lined', '1 set', 'Relined or replaced when wiped, '
         'scored or the clearance is over its limit'),
        ('thrust_pads', 'Thrust bearing pads', '1 set', 'Replaced as a set'),
        ('valve_seals', 'Stop and control valve stem seals and seat gaskets', '1 set', 'New at every valve '
         'overhaul'),
        ('lube_oil', 'Turbine oil, ISO VG 32', 'as needed', 'Topped up and changed by the oil analysis'),
    ],
    'figures': [
        ('steam_turbine', 'exploded', 'The turbine taken apart in overhaul order (from the Workshop): lagging, upper '
         'casings and blade carrier lifted, the rotor out, the bearings and valves beside.'),
        ('steam_turbine', 'cut', 'The turbine cut open (from the Workshop): outer and inner casings, the stationary '
         'blade rows in their carrier, the rotor\'s moving rows between them, the glands and bearings.', 35, 25),
    ],
    'sources': [
        {'id': 'ger3646', 'cite': 'J. K. Reinker and P. B. Mason, Steam Turbines for Large Power Applications, GE Power '
         'Systems GER-3646D: stages, inner shells and their joint flanges, diaphragms, bearings and couplings'},
        {'id': 'ger3582', 'cite': 'M. Boss, Steam Turbines for STAG Combined-Cycle Power Systems, GE Power Systems '
         'GER-3582E (1996): combined-cycle turbines, the thrust bearing, stop and control valves, start-up'},
        {'id': 'imia_wgp42', 'cite': 'IMIA working group paper WGP 42 (05), Maintenance and Overhaul of Steam '
         'Turbines (2005): overhaul intervals and tasks, damage and its causes',
         'url': 'https://www.imia.com/wp-content/uploads/2023/08/wgp4205-5.pdf'},
        {'id': 'navedtra14104', 'cite': 'US Navy, Fireman, NAVEDTRA 14104 (1992), chapter 5 Steam Turbines: casings, '
         'rotors, bearings, labyrinth glands'},
        {'id': 'asme_tdp1', 'cite': 'ASME TDP-1, Prevention of water damage to steam turbines used for electric '
         'power generation: drains, attemperators, water induction'},
    ],
    'sections': [
        S('description', 'Description', [
            P('The steam turbine turns the steam from the heat recovery steam generators into shaft power for its '
              'generator. In a combined cycle it makes about a third of the plant\'s output, from heat the gas '
              'turbines would otherwise send up the stack.'),
            FIG('steam_turbine', 'cut'),
            UL('**Casings.** The outer casing holds the pressure; inside it an inner casing and a **blade carrier** '
               'hold the stationary blade rows. Each is split at the **horizontal joint** into an upper and a lower '
               'half, bolted through heavy flanges, so the turbine can be opened from above.',
               '**Rotor.** A forged shaft carrying the moving blade rows. Each stage is a stationary row that turns '
               'the steam into a jet and a moving row that the jet drives. The steam expands stage by stage, so the '
               'blades grow longer toward the exhaust.',
               '**Bearings.** Journal bearings (white metal on a steel shell, running on an oil film) carry the rotor '
               'in the front and rear pedestals; a **thrust bearing** against a collar on the shaft holds it '
               'axially, since the steam pushes it toward the exhaust.',
               '**Glands.** Labyrinth seals where the shaft leaves the casing: rings of fins with a very small gap, '
               'fed with sealing steam so neither steam leaks out nor air in.',
               '**Stop and control valves.** The stop valve shuts at once on a trip; the control valve sets the flow. '
               'Each is opened by a hydraulic actuator against springs that shut it.'),
            P('The turbine is put on **turning gear** when it stops: a motor turns the rotor slowly so it cools '
              'evenly and does not bow.'),
        ], src=['ger3646', 'ger3582', 'navedtra14104']),
        S('specifications', 'Specifications', [
            UNIT(),
            SERIES(),
            TABLE(['Item', 'Typical value'], [
                ['Speed', '`3000 rpm` (50 Hz) or `3600 rpm` (60 Hz)'],
                ['Main steam', 'about `120` to `170 bar`, `540` to `565 °C` in a combined cycle'],
                ['Bearing vibration', 'trip set by its maker, usually at about `125 µm` shaft vibration'],
                ['Bearing metal temperature', 'alarm about `110 °C`, trip about `120 °C`'],
            ]),
            NOTE('Every turbine\'s limits are its maker\'s: these are typical values for this class of machine.'),
        ], src=['ger3582']),
        S('installation', 'Installation', [
            P('The turbine is erected on its foundation by its maker\'s team: pedestals set and grouted, the lower '
              'casings placed and lined up with the shaft line, the rotor laid in its bearings, the clearances '
              'measured and recorded, the casings closed, the couplings aligned and bolted. Those first records are '
              'what every later overhaul is compared with.'),
            P('The Workshop shows the order: [the front pedestal](workshop:steam_turbine/pedestal_f), [the lower '
              'casing](workshop:steam_turbine/casing_lower), [the rotor](workshop:steam_turbine/rotor), [the upper '
              'casing](workshop:steam_turbine/casing_upper) and [its joint studs](workshop:steam_turbine/joint_bolts).'),
        ], src=['ger3646', 'imia_wgp42']),
        S('commissioning', 'Commissioning and start-up', [
            OL('Lube oil and jacking oil running, the rotor on turning gear for hours before steam is admitted.',
               'Gland steam on and the condenser under vacuum; drains open to clear water from the casings and pipes.',
               'Steam temperature matched to the metal temperatures (cold, warm or hot start), so the parts heat '
               'evenly.',
               'Roll up through the critical speeds without stopping there, with vibration and differential '
               'expansion watched.',
               'Synchronise and load at the rate the metal temperatures allow.'),
            CAUTION('Water reaching a hot turbine (from a pipe that was not drained, or an attemperator that overspills) '
                    'chills and cracks it and can wreck the blading. Every drain is open on start-up until the steam '
                    'is dry.'),
        ], src=['ger3582', 'asme_tdp1']),
        S('operation', 'Operation', [
            UL('Watch vibration, bearing temperatures, thrust bearing position, differential expansion and the '
               'exhaust temperature and pressure.',
               'Change load within the allowed rate; a fast change stresses the thick rotor and casings.',
               'A trip shuts the stop valves at once; after it the rotor coasts down and goes on turning gear.',
               'Test the stop valves\' movement at the interval the procedure gives, so they cannot seize open.'),
        ], src=['ger3582', 'ger3646']),
        S('maintenance', 'Maintenance and overhaul', [
            TABLE(['Interval', 'Task'], [
                ['Daily', 'Oil levels and temperatures, leaks, vibration and expansion trends'],
                ['Monthly', 'Valve freedom tests; oil sample'],
                ['Every 1 to 2 years', 'Minor inspection: valves, bearings opened as needed, control oil'],
                ['Every 6 to 8 years (about 50,000 h)', 'Major overhaul: the casings opened, the rotor out, every '
                 'clearance measured, blades inspected and tested'],
            ]),
            FIG('steam_turbine', 'exploded'),
            H('Taking it apart (major overhaul)'),
            OL('The lagging off ([upper lagging](workshop:steam_turbine/lagging_upper)) and the casing cool.',
               'The [pedestal covers](workshop:steam_turbine/cap_f) off; the bearings\' upper halves out.',
               'The [joint studs](workshop:steam_turbine/joint_bolts) loosened and the [upper outer '
               'casing](workshop:steam_turbine/casing_upper) lifted on guide pins.',
               'The [inner casing\'s studs](workshop:steam_turbine/inner_bolts), the [upper inner '
               'casing](workshop:steam_turbine/inner_upper) and the [upper blade '
               'carrier](workshop:steam_turbine/carrier_upper) lifted.',
               'The [coupling bolts](workshop:steam_turbine/coupling_bolts) out and the [rotor](workshop:steam_turbine/rotor) '
               'lifted out onto its stands.'),
        ], src=['imia_wgp42', 'ger3646']),
        S('troubleshooting', 'Troubleshooting', [
            TROUBLE(
                ('Vibration rising slowly', 'Rotor imbalance from blade deposits or erosion, a bearing wearing, '
                 'misalignment', 'Trend it with the load; balance or clean at the next outage; check the alignment'),
                ('Vibration jumps suddenly', 'A lost blade or shroud piece, a rub', 'Trip if it passes the limit; '
                 'do not restart before the cause is found'),
                ('Bearing metal temperature rising', 'Oil too hot or too little, a wiped bearing, misalignment',
                 'Check the oil cooler and flow; inspect the bearing'),
                ('Thrust position moving', 'Deposits on the blades changing the stage pressures, thrust pads '
                 'wearing', 'Watch the stage pressures; inspect at the next outage'),
                ('Steam leaking at the glands', 'Gland steam pressure wrong, fins rubbed open', 'Adjust the gland '
                 'steam; renew the segments at overhaul'),
                ('Output falling for the same steam', 'Deposits on the blades, worn glands and tip seals',
                 'Compare the stage pressures with the clean values; plan a wash or overhaul'),
            ),
        ], src=['imia_wgp42', 'ger3646']),
        S('parts', 'Spare parts', [
            P('Part numbers are the generic plant\'s catalogue. The blade rows come with their carrier or the rotor.'),
            PARTS(),
        ], src=['imia_wgp42']),
        S('safety', 'Safety', [
            WARNING('Before the turbine is opened: steam isolated with double block and bleed, drains open, the '
                    'turning gear and oil pumps isolated as the permit says, the casing cooled.'),
            UL('Heavy lifts: the crane and its lifting gear inspected, a lift plan for each casing half and the rotor.',
               'The opened casing is a confined space: entry under its own permit.'),
        ], src=['imia_wgp42']),
    ],
}
