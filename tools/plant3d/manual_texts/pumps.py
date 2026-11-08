"""WDP-MAN-004, centrifugal pumps (kit parts `pump_horizontal`, `pump_vertical`). Generic, in our own words: the
structure and the facts follow the public standards and handbooks listed in `sources`; no text is copied from them."""
from manual_blocks import S, H, P, UL, OL, TABLE, WARNING, CAUTION, NOTE, TROUBLE, UNIT, SERIES, PARTS

MANUAL = {
    'id': 'pumps',
    'number': 'WDP-MAN-004',
    'title': 'Centrifugal pumps, horizontal and vertical',
    'short': 'CP',
    'kinds': ['pump_horizontal', 'pump_vertical'],
    'kind_names': {'pump_horizontal': 'Horizontal pump', 'pump_vertical': 'Vertical pump'},
    'params': {'flow_m3h': ('Rated flow', '{} m³/h'), 'head_m': ('Rated head', '{} m'),
               'motor_kw': ('Motor rating', '{} kW'), 'pit_depth': ('Pit depth', '{} m')},
    'consumables': [
        ('mech_seal', 'Mechanical seal cartridge', '1', 'Replaced as a cartridge, never taken apart on site'),
        ('bearing_de', 'Rolling bearing, drive end', '1', 'Fitted heated or pressed on the inner ring only'),
        ('bearing_nde', 'Rolling bearing, non-drive end', '1', 'As the drive end'),
        ('wear_rings', 'Casing and impeller wear rings', '1 set', 'Replace when the clearance has doubled'),
        ('casing_gasket', 'Casing gasket', '1', 'New whenever the casing is opened'),
        ('coupling_element', 'Coupling flexible element', '1', 'New when cracked, hardened or worn'),
        ('oil', 'Bearing oil, ISO VG 46 or 68 (as the plate says)', 'as needed', 'Changed every 4,000 h or by the '
         'oil analysis'),
        ('line_bearing', 'Vertical pump line shaft bearings (bushes)', '1 set', 'Vertical pumps: at every overhaul'),
    ],
    'sources': [
        {'id': 'api610', 'cite': 'API Standard 610, Centrifugal pumps for petroleum, petrochemical and natural gas '
         'industries: pump types (overhung, between bearings, vertically suspended), allowable operating region, '
         'vibration limits, bearings and lubrication'},
        {'id': 'api682', 'cite': 'API Standard 682, Pumps: shaft sealing systems for centrifugal and rotary pumps '
         '(seal arrangements and their flush plans)'},
        {'id': 'api686', 'cite': 'API Recommended Practice 686, Machinery installation and installation design: '
         'foundations and grouting, pipe strain, alignment'},
        {'id': 'hi961', 'cite': 'ANSI/HI 9.6.1, Rotodynamic pumps: guideline for NPSH margin'},
        {'id': 'skf', 'cite': 'SKF, Bearing maintenance handbook: mounting by heat, lubrication, bearing damage and '
         'its causes'},
        {'id': 'piotrowski', 'cite': 'J. Piotrowski, Shaft Alignment Handbook (third edition): rim and face, reverse '
         'indicator and laser alignment, tolerances, soft foot'},
        {'id': 'iso20816', 'cite': 'ISO 20816-3, Mechanical vibration: measurement and evaluation of machine '
         'vibration, industrial machines above 15 kW (zones A to D)'},
    ],
    'sections': [
        S('description', 'Description', [
            P('A centrifugal pump gives a liquid speed with a spinning **impeller**, and its **casing** turns that '
              'speed into pressure. The plant has two arrangements:'),
            UL('**Horizontal pumps** (cooling water, condensate extraction boosters, feedwater, chemical transfer): '
               'the pump and its motor side by side on a baseplate, joined by a flexible coupling. The shaft runs in '
               'two rolling or sleeve bearings in an oil-lubricated bearing housing.',
               '**Vertical pumps** (circulating water, intake): the motor stands on top of a column hung down into a '
               'pit or sump; a long line shaft inside the column drives the impeller bowls at the bottom, guided by '
               'water-lubricated line bearings.'),
            P('Where the shaft leaves the casing a **mechanical seal** stops the leak: a spinning face pressed on a '
              'stationary face, cooled and kept clean by a flush of the pumped liquid.'),
            H('The pump curve'),
            P('Each pump has its curve: head against flow at its speed. It runs where its curve meets the system\'s. '
              'Far to the left (nearly shut in) the liquid recirculates and heats up; far to the right the pump runs '
              'out and cavitates. Stay near the best efficiency point.'),
        ], src=['api610', 'api682']),
        S('specifications', 'Specifications', [
            UNIT(),
            SERIES(),
            TABLE(['Item', 'Value'], [
                ['Allowable operating region', 'about `70 %` to `120 %` of the best efficiency flow'],
                ['NPSH margin', 'available at least `1.1` to `1.3` times the pump\'s required NPSH, more for '
                 'hot or high energy duties'],
                ['Vibration', 'new pumps within zone A of ISO 20816-3; alarm at the zone C boundary'],
                ['Bearing housing temperature', 'normally below `80 °C`; alarm at `90 °C`'],
            ]),
        ], src=['api610', 'hi961', 'iso20816']),
        S('installation', 'Installation', [
            UL('Set the baseplate on its foundation level, then grout it so it bears evenly everywhere.',
               'Connect the pipes without forcing them: loosened flange bolts must not move the pump. Pipe strain '
               'pulls the shafts out of line and the casing out of shape.',
               'Check for **soft foot**: loosen each foot bolt in turn with a dial gauge on the foot; it may not lift '
               'more than a few hundredths of a millimetre.',
               'Align pump and motor with a laser or dial gauges, to within about `0.05 mm` offset and `0.05 mm` '
               'per `100 mm` angularity at running speed; check again once the pipes are connected and once '
               'the pump has run hot.',
               'Suction pipe: as short and straight as practical, no high points where air collects, an eccentric '
               'reducer flat side up.'),
        ], src=['api686', 'piotrowski']),
        S('commissioning', 'Commissioning', [
            OL('Check the motor\'s insulation and **rotation** with the coupling apart (a short bump).',
               'Fit the coupling and its guard; fill the bearing housing with oil to the sight glass\'s mark.',
               'Open the suction valve fully; fill and vent the casing until liquid comes out with no air.',
               'Discharge valve shut or a little open (as the pump\'s procedure says); minimum flow line open.',
               'Start. Open the discharge valve slowly within a minute of the start; never run against a shut valve.',
               'Check the pressures against the curve, the seal (no leak), the vibration and the bearing temperatures '
               'for the first hours.'),
            CAUTION('Never run the pump dry, even for seconds: the mechanical seal\'s faces burn without liquid between '
                    'them.'),
        ], src=['api610', 'api686']),
        S('operation', 'Operation', [
            UL('Run within the allowable operating region; a pump that must run at low flow needs its minimum flow '
               'line open.',
               'Watch suction pressure: a falling suction pressure or a rising temperature eats the NPSH margin, and '
               'the pump starts to cavitate (a rattle like gravel, the discharge pressure wavering).',
               'Change over duty and standby pumps regularly so both stay fit.',
               'A standby pump is kept full, vented and with its valves set to start at once.'),
        ], src=['api610', 'hi961']),
        S('maintenance', 'Maintenance', [
            TABLE(['Interval', 'Task'], [
                ['Every round', 'Oil level, seal leak, noise, vibration felt, bearing temperature'],
                ['Monthly', 'Vibration readings at both bearings (velocity, mm/s), the trend compared'],
                ['3 months', 'Oil sample for analysis; grease the motor bearings by quantity, not by feel'],
                ['12 months', 'Check the alignment; inspect the coupling element; change the oil if analysis says'],
                ['At overhaul', 'Bearings, mechanical seal, wear ring clearances, impeller; new gaskets; realign'],
            ]),
            H('Bearings'),
            P('Fit a rolling bearing by heating it on an induction heater (never a flame) to about `110 °C`, so it '
              'slides onto the shaft; press only on the ring that is being fitted. Too much grease heats a bearing as '
              'surely as too little.'),
        ], src=['skf', 'iso20816', 'api610']),
        S('troubleshooting', 'Troubleshooting', [
            TROUBLE(
                ('No flow or too little', 'Not primed, air in the suction, a suction valve shut, wrong rotation, '
                 'worn wear rings', 'Vent and prime; check valves and rotation; measure the wear ring clearance'),
                ('Noise like gravel; discharge pressure wavering', 'Cavitation: too little NPSH available',
                 'Raise the suction level or pressure, clean the strainer, reduce the flow'),
                ('Vibration rising', 'Misalignment, an unbalanced or damaged impeller, worn bearings, a loose foot, '
                 'running far from the best efficiency point', 'Read the spectrum; check the alignment and the feet; '
                 'replace bearings; run nearer the design flow'),
                ('Bearing running hot', 'Oil level wrong, oil degraded, too much grease, misalignment, a bearing '
                 'failing', 'Check the oil and its analysis; correct the grease quantity; realign; replace'),
                ('Mechanical seal leaking', 'Faces worn or cracked, run dry, flush blocked, shaft vibration',
                 'Replace the seal cartridge; clear the flush; find the cause of the vibration'),
                ('Motor overloaded', 'Running out at too high a flow, a denser liquid, rubbing inside',
                 'Throttle to the design flow; check for rubbing'),
            ),
        ], src=['api610', 'skf', 'hi961', 'api682']),
        S('parts', 'Spare parts', [
            P('Part numbers are the generic plant\'s catalogue; each is ordered for the pump\'s size and model.'),
            PARTS(),
        ], src=['api610']),
        S('safety', 'Safety', [
            WARNING('Before any work: the motor isolated and locked off at its switchgear and proved dead, the suction '
                    'and discharge valves shut and locked, the casing drained and vented. A pump can turn backwards '
                    'from the flow of the others if its check valve passes: make sure it cannot.'),
            UL('Never run with the coupling guard off.',
               'Hot liquid in the casing: let it cool before opening, wear gloves and a face shield.',
               'Vertical pumps: work in the pit is confined space entry.'),
        ], src=['api610', 'api686']),
    ],
}
