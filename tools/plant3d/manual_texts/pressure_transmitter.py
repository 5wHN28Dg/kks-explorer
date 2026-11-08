"""WDP-MAN-001, the pressure transmitter (kit part `pressure_transmitter`). Generic, in our own words: the structure
and the facts follow the public manuals and standards listed in `sources`; no text is copied from them."""
from manual_blocks import S, H, P, UL, OL, TABLE, WARNING, CAUTION, NOTE, FIG, TROUBLE, UNIT, SERIES, PARTS

MANUAL = {
    'id': 'pressure_transmitter',
    'number': 'WDP-MAN-001',
    'title': 'Pressure transmitter, 4–20 mA with HART',
    'short': 'PT',
    'kinds': ['pressure_transmitter'],
    'kind_names': {'pressure_transmitter': 'Pressure transmitter'},
    'params': {'range': 'Calibrated range', 'unit': 'Unit'},
    'comes_with': {'isolator': 'sensor_module', 'sensor_cell': 'sensor_module', 'window': 'cover_front'},
    'consumables': [
        ('flange_orings', 'Process flange O-rings, PTFE (pair)', '1 set', 'New at every refit of the flange'),
        ('cover_orings', 'Cover O-rings (pair)', '1 set', 'New when a cover O-ring is flattened, cut or dry'),
        ('gland_seal', 'Cable gland seal insert', '1', 'Sized to the cable; new when water got past the old one'),
        ('ferrules', 'Wire end ferrules, 0.75 mm², insulated', '10', 'Crimped on every stripped wire end'),
    ],
    'figures': [
        ('pressure_transmitter', 'exploded', 'The transmitter taken apart (from the Workshop): manifold, process '
         'flange and drain/vent valves below, the sensor module, the housing with its two covers above.'),
        ('pressure_transmitter', 'cut', 'The transmitter cut open (from the Workshop): the electronics side and the '
         'terminal side of the housing, the sensor module under them.'),
    ],
    'sources': [
        {'id': 'r3051', 'cite': 'Emerson, Rosemount 3051 Pressure Transmitter with HART Protocol, reference manual '
         '00809-0100-4007: installation (mounting, impulse piping, manifolds), wiring (signal and test terminals, '
         'loop power, the 250 Ω for HART), commissioning, operation (sensor trim, analog output trim, rerange), '
         'troubleshooting tables, disassembly and reassembly',
         'url': 'https://core.instrumart.com/assets/rosemount_3051-420ma_manual.pdf'},
        {'id': 'hart', 'cite': 'FieldComm Group, HART protocol: the digital signal over the 4–20 mA loop, the loop '
         'resistance it needs, primary and secondary masters',
         'url': 'https://www.fieldcommgroup.org/technologies/hart'},
        {'id': 'ne43', 'cite': 'NAMUR NE 43, standardisation of the signal level for the failure information of '
         'digital transmitters (the 3.8–20.5 mA measuring range and the failure currents beyond it)'},
        {'id': 'fluke771', 'cite': 'Fluke 771 Milliamp Process Clamp Meter, users manual: the clamp round one '
         'conductor of the loop; round both the currents cancel'},
        {'id': 'liptak', 'cite': 'B. G. Lipták (ed.), Instrument Engineers\' Handbook, vol. 1, Process Measurement '
         'and Analysis: pressure transmitters, impulse lines, liquid and gas service, calibration'},
        {'id': 'iec62382', 'cite': 'IEC 62382, Control systems in the process industry: electrical and instrumentation '
         'loop check'},
    ],
    'sections': [
        S('description', 'Description', [
            P('This manual covers the plant\'s **pressure transmitters**: two-wire, loop-powered instruments that '
              'measure gauge, absolute or differential pressure and send it as a `4–20 mA` current, with the HART '
              'digital signal on the same pair of wires. The trainee meets them first on the condenser: three '
              'transmitters ([1](kks:30MAG10CP001), [2](kks:30MAG10CP002), [3](kks:30MAG10CP003)) measure the same '
              'pressure, so one that reads apart from its two partners stands out.'),
            FIG('pressure_transmitter', 'exploded'),
            P('The transmitter has two halves. Below, the **sensor module** carries two isolating diaphragms. The '
              'process pushes on them, and a sealed fill fluid passes the pressure to a sensing cell inside. The '
              'module is filled and sealed at the factory and is never opened in the field. Above, the **electronics '
              'housing** has two compartments, each with its own screwed cover: the electronics side (the board and '
              'the optional display, behind the cover with the window) and the terminal side (the terminal block '
              'where the loop wires land).'),
            P('Under the sensor module the **process flange** brings the pressure to the diaphragms through two '
              'ports, with a drain/vent valve beside each. A **valve manifold** bolted under the flange isolates the '
              'transmitter from the process and joins its two sides, so it can be zeroed or removed with the plant '
              'running.'),
            FIG('pressure_transmitter', 'cut'),
            H('How the signal works'),
            UL('`4 mA` is the lower range value (LRV), `20 mA` the upper range value (URV); the current between is '
               'proportional to the pressure.',
               'The transmitter draws its own power from the loop: the current it lets through **is** the signal.',
               'Between `3.8 mA` and `20.5 mA` the current still follows the pressure (a little under and over '
               'range). At or below `3.6 mA`, or at or above `21 mA`, it means the transmitter has found a fault in '
               'itself and has driven its output to its alarm level.',
               'HART rides on the loop as a small tone (two frequencies for 1 and 0) that averages to zero, so it '
               'does not disturb the current. Through it a communicator or the control system reads the primary '
               'variable (PV), the loop current the transmitter thinks it sends, its status, and its configuration.'),
        ], src=['r3051', 'hart', 'ne43', 'liptak']),
        S('specifications', 'Specifications', [
            P('What this transmitter is set up for (shown when the manual is opened from an equipment card):'),
            UNIT(),
            P('The series the plant\'s transmitters come from:'),
            SERIES(),
            TABLE(['Item', 'Value'], [
                ['Output', '`4–20 mA` two-wire, HART digital signal on the same pair'],
                ['Supply at the terminals', '`10.5 V` to `42 V` DC'],
                ['Loop resistance for HART', 'at least `250 Ω` in the loop'],
                ['Failure currents', 'low alarm at or below `3.6 mA`, high alarm at or above `21 mA` (set by a switch '
                 'or in the configuration)'],
                ['Accuracy (reference)', 'about `±0.1 %` of span'],
                ['Damping', 'adjustable, `0` to `60 s`; usually `0.4 s`'],
                ['Enclosure', 'dust-tight and protected against jets of water, with both covers fully on'],
            ]),
            NOTE('The figures above are typical of this class of transmitter. The calibrated range of each one is in '
                 'its own data (the table at the top) and on its tag plate.'),
        ], src=['r3051', 'ne43']),
        S('installation', 'Installation', [
            H('Mounting'),
            UL('Mount the transmitter as close to the tapping as practical, on a stand or a pipe bracket, never hanging '
               'on its impulse lines.',
               'Turn the housing so the covers can come off and the display can be read: the housing turns on the '
               'sensor module once its rotation set screw is loosened, by up to one turn. Tighten the set screw '
               'again afterwards.',
               'A transmitter mounted at an angle reads a small offset (the fill fluid\'s weight). Correct it with a '
               '[zero trim](#calibration) after mounting, never by moving the range.'),
            H('Impulse lines'),
            UL('Keep them short, with a steady slope of at least 1 in 12 and no high or low pockets.',
               '**Liquid service:** the transmitter below the tapping, so gas bubbles rise back into the pipe; the '
               'taps on the side of the pipe.',
               '**Gas service:** the transmitter above the tapping, so condensed liquid drains back; the taps on top '
               'or on the side of the pipe.',
               '**Steam service:** liquid-filled lines with the transmitter below the tapping, so the hot steam never '
               'reaches the diaphragms.',
               'For a differential transmitter keep both legs at the same temperature, side by side, so their liquid '
               'heads stay equal.'),
            H('Wiring'),
            OL('Take the terminal cover off (the compartment marked as the field terminals side).',
               'Bring the twisted, shielded pair in through the cable gland. Do not run it beside power cables.',
               'Strip, crimp a ferrule on each wire end and land the positive wire on the + signal terminal and the '
               'negative on the − terminal. Tighten each screw and pull each wire to check it.',
               'Earth the shield at one end only (in the control room\'s cabinet); at the transmitter cut it back and '
               'insulate it.',
               'Seal the gland round the cable. Put the cover back on until it seats fully, so the enclosure stays '
               'sealed.'),
            CAUTION('A loose terminal or a wire end without its ferrule makes a contact that adds resistance: the loop '
                    'current falls while the transmitter itself still reads right. See [troubleshooting](#troubleshooting).'),
        ], src=['r3051', 'liptak']),
        S('commissioning', 'Commissioning', [
            P('Before it is put in service a new or refitted transmitter gets a loop check with the control room '
              'operator.'),
            OL('Check the transmitter\'s tag, range and units against its data sheet (with the communicator).',
               'With the manifold\'s equalising valve open and the block valves shut, the transmitter sees no '
               'differential pressure (or vent a gauge transmitter to air): check it reads zero, and [trim the '
               'zero](#calibration) if it does not.',
               'Simulate the output (the communicator\'s loop test) at `4`, `8`, `12`, `16` and `20 mA`. At each '
               'one the operator reads the value on the screen; both agree within the loop\'s tolerance.',
               'Check the alarms and trips that use this transmitter from the field, one at a time, with the '
               'control room confirming each.',
               'Put it in service with the manifold, in the [order below](#operation), and compare its reading '
               'with its partners or a local gauge.'),
            NOTE('Record the as-left values. A loop check is the evidence that the whole loop works: the transmitter, '
                 'the cable, the input card and the screen.'),
        ], src=['r3051', 'iec62382']),
        S('operation', 'Operation and the manifold', [
            P('The transmitter needs nothing in normal operation. Its manifold is worked whenever it is taken out of '
              'service or put back. On a differential transmitter the order matters: the sensor must never see the '
              'full process pressure on one side only.'),
            H('Taking it out of service (three-valve manifold)'),
            OL('Ask the control room to put the loop in manual and to inhibit its alarms and trips.',
               'Shut the high pressure block valve.',
               'Open the equalising valve: both sides now see the same pressure.',
               'Shut the low pressure block valve.',
               'Vent or drain through the drain/vent valves before anything is unscrewed.'),
            H('Putting it back in service'),
            OL('Shut the drain/vent valves.',
               'With the equalising valve open, open the high pressure block valve slowly.',
               'Shut the equalising valve.',
               'Open the low pressure block valve.',
               'Tell the control room; it puts the loop back in automatic once the reading is steady and right.'),
            CAUTION('A passing (leaking) equalising valve joins the two sides a little in service: a differential '
                    'transmitter then reads low, and an absolute or gauge one reads between the process and the '
                    'other side. Check it is tight when a reading is low.'),
        ], src=['r3051', 'liptak']),
        S('hart', 'Connecting a HART communicator', [
            P('A communicator talks to the transmitter across the loop. It can be clipped on anywhere along the pair: '
              'on the signal terminals, the test terminals, or in the marshalling cabinet.'),
            OL('Open the terminal side: [unscrew the terminal cover](work:open_cover).',
               '[Clip the communicator\'s leads on the signal terminals](work:connect_hart). Polarity does not matter '
               'for HART.',
               'Switch on and poll. The communicator finds the device at its address (0 for a single transmitter in '
               'a `4–20 mA` loop).',
               'Read the PV, the analog output it reports, the loop current and the status. Compare the reported '
               'output with the current [measured with the multimeter](#loop_current).',
               'When done, [unclip the communicator](work:disconnect_hart).'),
            H('When it says "no device found"'),
            UL('**Too little resistance in the loop.** The HART signal is a voltage made by the current\'s tone '
               'across the loop\'s resistance. Under `250 Ω` it is too weak to hear. On a bench supply with no '
               'resistor, or on a card without one, add a `250 Ω` resistor in series.',
               '**No loop power.** A lifted wire, a blown fuse or an open terminal leaves the transmitter dead: '
               'measure the voltage at the terminals.',
               '**The wrong terminals.** On the test terminals with the multimeter connected there the communicator '
               'may see a short; move it to the signal terminals.',
               '**Another master.** The control system\'s own HART interface may be busy; the communicator is the '
               'secondary master and waits its turn.'),
            CAUTION('Changing the configuration changes the output: a rerange or a trim moves the loop current at once. '
                    'Only do it with the loop in manual and with the control room told.'),
        ], src=['hart', 'r3051']),
        S('loop_current', 'Measuring the loop current', [
            P('Three ways, each with a lesson:'),
            UL('**Across the test terminals:** [put the multimeter (mA) across the test terminals](work:connect_dmm). '
               'The test terminals bridge a diode in the loop; the meter\'s low resistance takes the current, so it '
               'reads it without a wire being lifted and without the loop opening. [Take the leads '
               'off](work:disconnect_dmm) afterwards.',
               '**Across the signal terminals:** [a meter on mA across the signal '
               'terminals](work:dmm_on_sig) shorts the transmitter\'s supply: it reads a current, but not the loop\'s. '
               'Never do it on a live loop.',
               '**With a mA clamp:** [clamp round the positive wire](work:clamp_wire) alone. [Clamped round the whole '
               'cable](work:clamp_cable) the out and return currents cancel and it reads `0 mA`.'),
            P('If the measured current agrees with the output the transmitter reports, and the control room reads the '
              'same, the cable and the card are sound and any error is in the measurement itself.'),
        ], src=['r3051', 'fluke771']),
        S('calibration', 'Calibration', [
            P('Three different adjustments, often confused:'),
            TABLE(['Adjustment', 'What it changes', 'When'], [
                ['**Sensor trim** (zero, or zero and full scale)', 'How the transmitter reads pressure: its PV is '
                 'brought to a reference', 'The PV disagrees with a reference pressure (drift, mounting offset)'],
                ['**Analog output trim** (4 and 20 mA)', 'How the PV is turned into current', 'The current measured '
                 'differs from the output the transmitter reports'],
                ['**Rerange** (LRV and URV)', 'Which pressures mean 4 and 20 mA', 'The process needs another range; '
                 'never to correct an error'],
            ]),
            H('Zero trim in the field'),
            OL('Loop in manual, alarms inhibited.',
               'Equalise the manifold (differential), or vent the transmitter to air (gauge). For an absolute '
               'transmitter a zero trim needs a vacuum reference: use a two-point sensor trim against a reference '
               'gauge instead.',
               'With the communicator, run the zero trim and let the transmitter take the present reading as zero.',
               'Check the PV now reads zero and the output `4 mA` (if the LRV is zero).',
               'Put the manifold back in service in the [right order](#operation).'),
            H('Sensor trim against a reference (two points)'),
            OL('Isolate the transmitter and connect a hand pump with a reference gauge (at least three times as '
               'accurate) to the test connection.',
               'Apply the lower point; run the lower sensor trim and enter the reference reading.',
               'Apply the upper point; run the upper sensor trim and enter the reference reading.',
               'Check at `0`, `25`, `50`, `75` and `100 %` of the range, rising and falling. Record as found and as '
               'left. Within about `±0.25 %` of span it passes.'),
            P('In the plant the sensor trim is offered by the communicator while its leads are on the signal terminals '
              'and the wires are landed: the trim is a HART command, so the transmitter must be powered and heard.'),
            NOTE('A transmitter that needs a large trim, or keeps needing one, is drifting: replace its sensor module '
                 'rather than trimming it again and again.'),
        ], src=['r3051', 'liptak', 'hart']),
        S('maintenance', 'Maintenance', [
            TABLE(['Interval', 'Task'], [
                ['Every round', 'Look: covers on, gland tight, no leaks at the manifold or flange, display readable'],
                ['3 months', 'Blow down or drain the impulse lines in dirty or wet service; compare with partners'],
                ['12 months', 'Zero check with the manifold equalised; check the terminals are tight and dry'],
                ['24 months', 'Five-point calibration check against a reference; inspect cover O-rings and gland seal'],
                ['After any work', 'A loop check with the control room'],
            ]),
            P('Intervals are a starting point: shorten them where the service is dirty, wet or vibrating, lengthen '
              'them where several years of as-found records show no drift.'),
        ], src=['r3051', 'liptak']),
        S('troubleshooting', 'Troubleshooting', [
            P('Start with what you can compare: the transmitter\'s reading against its partners, the PV it reports '
              'against the current in the loop, and the current against the control room\'s screen. Each comparison '
              'rules out one half of the loop.'),
            TROUBLE(
                ('Reads low (or high) against its partners; the loop current agrees with its PV',
                 'The sensor has drifted',
                 'Check against a reference (two-point check); [sensor trim](#calibration); replace the sensor module '
                 'if the drift is large or comes back', 'drift'),
                ('The loop current is lower than the output the transmitter reports; its PV agrees with its partners',
                 'A loose or corroded signal terminal (contact resistance in the loop)',
                 '[Tighten the signal terminals](work:tighten_terms); a ferrule on every wire end; check again', 'loose'),
                ('Reads steady while the process changes',
                 'A blocked impulse line, or a closed root or block valve',
                 'Check the valves are open; isolate and blow the line through'),
                ('A differential transmitter reads low, or near zero',
                 'The manifold\'s equalising valve is passing',
                 'Shut it tight; if it still passes, replace the manifold'),
                ('Reading noisy or wandering',
                 'Gas in a liquid line or liquid in a gas line; legs at different temperatures; vibration',
                 'Vent or drain the lines; run the legs together; lengthen the damping only after the cause is found'),
                ('Reading noisy, current jumping; water in the terminal side',
                 'Water got in at the cable gland or a cover',
                 'Dry it, replace the gland seal and the cover O-ring, check the insulation of the cable'),
                ('`0 mA`, nothing on the display',
                 'No loop power: a lifted wire, an open terminal, a blown fuse, reversed wires',
                 'Measure the voltage at the terminals; trace the loop; land the wires the right way round'),
                ('`3.6 mA` or less, or `21 mA` or more',
                 'The transmitter has found a fault in itself and driven its output to its alarm level',
                 'Read its status with the communicator; replace the part it names'),
                ('The current is right but the screen is wrong',
                 'The control system\'s range or input card does not match',
                 'Check the range in the control system against the transmitter\'s LRV and URV'),
                ('The communicator finds no device',
                 'Less than `250 Ω` in the loop, no loop power, or the leads on the wrong terminals',
                 'See [connecting a HART communicator](#hart)'),
            ),
            H('In the field, step by step'),
            OL('With the permit accepted and the loop in manual, [unscrew the terminal cover](work:open_cover).',
               '[Connect the communicator](work:connect_hart) and read PV, output and status.',
               '[Put the multimeter across the test terminals](work:connect_dmm) and read the loop current.',
               'Compare: PV against the partners, the current against the reported output.',
               'Put right what the comparison points to: [tighten the terminals](work:tighten_terms), or trim the '
               'sensor (in the communicator\'s screen), or plan a replacement.',
               'Read again; take the meters off ([multimeter](work:disconnect_dmm), '
               '[communicator](work:disconnect_hart)) and [screw the terminal cover back on](work:close_cover).',
               'Hand back to the control room for a loop check before the loop goes back to automatic.'),
        ], src=['r3051', 'liptak', 'hart']),
        S('replacing', 'Replacing the sensor module or the electronics', [
            P('Both are done at the workshop bench with the transmitter removed. The Workshop shows each step; the '
              'links open it at that step.'),
            H('Taking it apart'),
            OL('Take the manifold off the process flange ([manifold](workshop:pressure_transmitter/manifold)).',
               'Undo the four flange bolts ([flange bolts](workshop:pressure_transmitter/flange_bolts)) and lift the '
               'process flange off ([process flange](workshop:pressure_transmitter/process_flange)). Keep the O-rings '
               'out of the way: they are not reused.',
               'Unscrew the terminal cover ([terminal cover](workshop:pressure_transmitter/cover_back)) and slide the '
               'terminal block off its posts ([terminal block](workshop:pressure_transmitter/terminal_block)).',
               'Unscrew the electronics cover ([electronics cover](workshop:pressure_transmitter/cover_front)), unplug '
               'the display ([display](workshop:pressure_transmitter/display)) and draw the board out by its captive '
               'screws ([electronics board](workshop:pressure_transmitter/electronics)).',
               'Loosen the rotation set screw ([set screw](workshop:pressure_transmitter/set_screw)) and unscrew the '
               'housing from the sensor module ([housing](workshop:pressure_transmitter/housing)), feeding the ribbon '
               'cable through.',
               'The [sensor module](workshop:pressure_transmitter/sensor_module) is now on its own.'),
            H('Putting it together'),
            P('In the reverse order, with new flange O-rings. Tighten the flange bolts crosswise in two stages. After '
              'reassembly, set the range from the old transmitter\'s record, do a [sensor trim](#calibration) and a '
              'loop check.'),
            CAUTION('Never touch or scratch the isolating diaphragms: a dent changes the reading, a hole lets the fill '
                    'fluid out and ruins the module.'),
        ], src=['r3051']),
        S('parts', 'Spare parts', [
            P('Part numbers are the generic plant\'s catalogue. A sealed part (the sensor module, the electronics '
              'cover with its window) is one spare with everything inside it.'),
            PARTS(),
        ], src=['r3051']),
        S('safety', 'Safety', [
            WARNING('Work on a transmitter only under an accepted permit, with the loop in manual and its alarms and '
                    'trips inhibited by the control room. A transmitter that feeds a trip can trip the unit when its '
                    'output moves.'),
            WARNING('Before any fitting is loosened, isolate at the root valve and the manifold and vent the trapped '
                    'pressure through the drain/vent valve, pointed away from you. Hot condensate and steam lines stay '
                    'hot after isolation.'),
            UL('Keep both covers fully on in service: the enclosure protects the electronics from water and dust.',
               'In an area classified for flammable gas, follow the area\'s rules before a cover comes off with the '
               'power on.',
               'Wear eye protection when venting or blowing down impulse lines.'),
        ], src=['r3051', 'liptak']),
    ],
}
