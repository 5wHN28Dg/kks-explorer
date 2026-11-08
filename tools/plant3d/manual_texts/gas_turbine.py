"""WDP-MAN-006, the gas turbine, an overview (kit part `gas_turbine`). Generic, in our own words: the structure and
the facts follow the public papers listed in `sources`; no text is copied from them. Its figures come with the gas
turbine's Workshop scene (manuals.py leaves them out until then)."""
from manual_blocks import S, H, P, UL, OL, TABLE, WARNING, CAUTION, NOTE, FIG, TROUBLE, UNIT, SERIES, PARTS

MANUAL = {
    'id': 'gas_turbine',
    'number': 'WDP-MAN-006',
    'title': 'Gas turbine: an overview',
    'short': 'GT',
    'kinds': ['gas_turbine'],
    'kind_names': {'gas_turbine': 'Gas turbine'},
    'params': {'rating_mw': ('Rating', '{} MW'), 'length': ('Length', '{} m'), 'casing_d': ('Casing diameter', '{} m'),
               'intake': ('Air intake', '{}'), 'exhaust': ('Exhaust', '{}')},
    # (the Workshop takes the rotor out and puts it back as one assembly with its blades: they come with it)
    'comes_with': {'cblades': 'rotor', 'tbucket1': 'rotor', 'tbucket2': 'rotor', 'tbucket3': 'rotor'},
    'consumables': [
        ('inlet_filters', 'Inlet air filter elements (pre-filters and fine filters)', '1 set', 'By the pressure drop '
         'across them, or every year'),
        ('fuel_nozzles', 'Fuel nozzles', '1 set', 'Exchanged at every combustion inspection, refurbished off site'),
        ('combustion_liners', 'Combustion liners and transition pieces', '1 set', 'Exchanged at every combustion '
         'inspection'),
        ('igniters', 'Spark igniters', '2', 'Checked at every combustion inspection'),
        ('flame_scanners', 'Flame detectors', '1 set', 'Lenses cleaned at every outage'),
        ('wash_detergent', 'Compressor wash detergent', 'as needed', 'As its maker approves for the compressor'),
    ],
    'figures': [
        ('gas_turbine', 'exploded', 'The gas turbine taken apart (from the Workshop).'),
        ('gas_turbine', 'cut', 'The gas turbine cut open (from the Workshop): compressor, combustors, turbine.'),
    ],
    'sources': [
        {'id': 'ger3567', 'cite': 'F. J. Brooks, GE Gas Turbine Performance Characteristics, GE Power Systems GER-3567H '
         '(2000): the Brayton cycle, the effect of ambient temperature, humidity and inlet and exhaust losses'},
        {'id': 'ger3620', 'cite': 'GE Vernova, Heavy-Duty Gas Turbine Operating and Maintenance Considerations, '
         'GER-3620P (2021): combustion, hot gas path and major inspections, factored hours and starts, inlet '
         'filtration, compressor washing',
         'url': 'https://www.gevernova.com/gas-power/resources/technical-downloads/ger-3620p-operation-maintenance-considerations'},
        {'id': 'ptc22', 'cite': 'ASME PTC 22, Performance test code on gas turbines'},
    ],
    'sections': [
        S('description', 'Description', [
            P('The gas turbine draws in air, compresses it, burns fuel gas in it and expands the hot gas through a '
              'turbine. The turbine drives both the compressor and the generator; the exhaust, still at about '
              '`600 °C`, goes on to the heat recovery steam generator.'),
            FIG('gas_turbine', 'cut'),
            UL('**Inlet:** filters and a silencer clean the air; inlet guide vanes at the compressor\'s mouth set the '
               'air flow at part load.',
               '**Compressor:** many stages of rotating and stationary blades raise the air to about `15` to `20` '
               'times atmospheric pressure. About half the turbine\'s work goes into driving it.',
               '**Combustion system:** several combustors round the machine (or one annular chamber), each with its '
               'fuel nozzles, a liner and a transition piece to the turbine. Low-NOx combustors premix gas and air '
               'lean before they burn.',
               '**Turbine:** three or four stages, the first ones cooled by air bled from the compressor, since the '
               'gas entering them is hotter than the metal could bear on its own.',
               '**Auxiliaries:** lube oil, the starting system (the generator run as a motor by a static frequency '
               'converter), fuel gas valves, the fire protection of the enclosure.'),
            H('What changes its output'),
            P('A gas turbine is a machine of fixed volume flow: on a hot day the air is thinner, less mass goes '
              'through and the output falls, by roughly `0.5` to `0.7 %` for each degree Celsius above `15 °C`. '
              'Dirty inlet filters and a fouled compressor take more.'),
        ], src=['ger3567', 'ger3620']),
        S('specifications', 'Specifications', [
            UNIT(),
            P('What the generic plant\'s parts kit allows for these kinds (the limits of the model, not a '
              'product\'s ratings):'),
            SERIES(),
            TABLE(['Item', 'Typical value'], [
                ['Rated output (ISO conditions: `15 °C`, sea level, `60 %` humidity)', 'see the table above'],
                ['Exhaust temperature', 'about `580` to `630 °C`'],
                ['Pressure ratio', 'about `15` to `20`'],
                ['Speed', '`3000 rpm` (50 Hz) or `3600 rpm` (60 Hz) for a heavy-duty machine driving the generator '
                 'directly'],
            ]),
        ], src=['ger3567', 'ptc22']),
        S('installation', 'Installation', [
            P('The gas turbine arrives assembled on its base and is set, aligned to its generator and connected by its '
              'maker\'s team. After installation its performance is measured in an acceptance test under a '
              'performance test code, corrected to the reference conditions, and that test is the baseline for every '
              'later degradation check.'),
        ], src=['ptc22']),
        S('commissioning', 'Commissioning and start-up', [
            OL('Lube oil running and the rotor on turning gear.',
               'Start: the generator runs as a motor from the static frequency converter and spins the shaft up.',
               'Purge: air is blown through the turbine and the steam generator long enough to clear any gas.',
               'Ignition and flame detected in every combustor; fuel increased while the shaft accelerates.',
               'The starting system drops out; the turbine runs itself up to full speed.',
               'Synchronise and load.'),
            CAUTION('A start that fails to light is followed by a full purge before the next attempt: unburnt gas in '
                    'the exhaust path can explode.'),
        ], src=['ger3620']),
        S('operation', 'Operation', [
            UL('Watch the exhaust temperature spread: one cold spot points to a combustor that has lost its flame or '
               'a fuel nozzle that is blocked.',
               'Watch the inlet filter pressure drop and the compressor\'s efficiency: both rise and fall long before '
               'the output shows it.',
               'Every start and every trip from load counts against the inspection intervals (below) as much as '
               'many hours of steady running.'),
        ], src=['ger3620']),
        S('maintenance', 'Maintenance and inspections', [
            TABLE(['Inspection', 'Typical interval', 'What it covers'], [
                ['Combustion inspection', 'about `8,000` to `12,000` factored hours or `450` to `900` starts',
                 'Fuel nozzles, liners, transition pieces, igniters, flame detectors'],
                ['Hot gas path inspection', 'about `24,000` factored hours', 'The combustion parts and the turbine\'s '
                 'nozzles and buckets'],
                ['Major inspection', 'about `48,000` factored hours', 'The whole machine opened: compressor, '
                 'turbine, bearings, seals'],
            ]),
            P('**Factored hours** count each hour of running weighted by how hard it was: peak load, trips and fast '
              'starts add more than steady base load.'),
            H('Compressor washing'),
            UL('**Online wash:** clean water sprayed into the running compressor, often daily or weekly, to slow the '
               'fouling.',
               '**Offline wash:** detergent and water while the compressor is cranked cold, which restores most of '
               'what fouling took.'),
            FIG('gas_turbine', 'exploded'),
            P('Inlet filters are changed by their pressure drop: in a dusty climate they may need more frequent '
              'changes, and a sandstorm can block them within hours.'),
        ], src=['ger3620']),
        S('troubleshooting', 'Troubleshooting', [
            TROUBLE(
                ('Output and efficiency falling slowly', 'Compressor fouling, dirty inlet filters', 'Offline wash; '
                 'change the filters by their pressure drop'),
                ('Exhaust temperature spread widening', 'A fuel nozzle blocked or a combustor\'s flame weak',
                 'Find the combustor from the spread; inspect at the next stop'),
                ('Flame lost in one combustor at start', 'Igniter or crossfire tube fault, flame detector dirty',
                 'Clean the detectors; check the igniters'),
                ('Inlet filter pressure drop rising fast', 'Dust or sand storm, humid air on dirty filters',
                 'Watch the trend; change filters before the alarm limit; reduce load if it climbs on'),
                ('Vibration rising', 'Imbalance, a bearing, a rub after a fast cool-down', 'Trend it; inspect'),
            ),
        ], src=['ger3620', 'ger3567']),
        S('parts', 'Spare parts', [
            P('Part numbers are the generic plant\'s catalogue. Combustion and hot gas path parts are exchanged as '
              'sets and refurbished off site.'),
            PARTS(),
        ], src=['ger3620']),
        S('safety', 'Safety', [
            WARNING('The gas turbine\'s enclosure is protected by a gas fire extinguishing system that floods it with '
                    'inert gas: lock it off before anyone enters, and never enter when it has discharged until the '
                    'enclosure has been ventilated and tested.'),
            WARNING('Fuel gas: the gas valves isolated and the lines vented before any work on the fuel system; gas '
                    'detection on.'),
            UL('Hot surfaces stay hot for hours after a stop.',
               'Noise above `85 dB(A)` near the running machine: hearing protection.'),
        ], src=['ger3620']),
    ],
}
