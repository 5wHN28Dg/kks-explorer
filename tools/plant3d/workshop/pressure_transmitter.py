"""The pressure transmitter's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K1a): the words, materials and
sources of its component tree. Its geometry (the components, their pivots, explode directions, the fastener groups'
positions) is the kit's generator, apps/plant3d/kit/parts_instruments.gd `_transmitter`; the content build joins the
two and refuses a kind whose halves disagree.

Generic: a coplanar differential/gauge pressure transmitter as the public manuals describe one; no plant data.
The guided assembly order (`assembly`, milestone K2) follows the manual's reassembly procedures (§6.5, §6.5.1-§6.5.4;
the take-apart order of §6.4 is its reverse); the sentences for placing and removing too early say what those sections
say must come first. No sizes, tools or torque values here: they belong to the realism programme's service file
(WORKSHOP.md §4.4).
"""

R3051 = 'r3051'
SOURCES = [
    {'id': R3051, 'cite': 'Emerson, Rosemount 3051 Pressure Transmitter with HART Protocol, reference manual '
                          '00809-0100-4007 rev. BA (2017): §3.5 integral manifolds, §4.3 LCD display, §6.4 '
                          'disassembly and §6.5 reassembly procedures, appendix A spare parts (the LCD display cover '
                          'comes with its window)',
     'url': 'https://core.instrumart.com/assets/rosemount_3051-420ma_manual.pdf'},
]


def comp(name, does, material, sealed_why=None):
    c = {'name': name, 'does': does, 'material': material, 'sources': [R3051]}
    if sealed_why:
        c['sealed'] = True
        c['sealed_why'] = sealed_why
    return c


def data():
    return {
        'format': 'walkdown-plant-workshop', 'version': 1, 'part': 'pressure_transmitter',
        'sources': SOURCES,
        'components': {
            'manifold': comp('Valve manifold', 'Bolted under the process flange: its valves isolate the transmitter '
                             'from the process and equalise its two sides, so it can be zeroed or taken off in service.',
                             'Forged stainless steel body, valve stems and seats'),
            'process_flange': comp('Process flange', 'Brings the process pressure through two ports to the sensor '
                                   'module\'s isolating diaphragms; PTFE O-rings seal it to the module.',
                                   '316 stainless steel'),
            'drain_vents': comp('Drain/vent valves', 'Screwed into the process flange beside each port: opened to '
                                'drain liquid or vent gas trapped in the flange chambers.', '316 stainless steel'),
            'sensor_module': comp('Sensor module', 'Turns the process pressure into an electrical signal: the '
                                  'isolating diaphragms pass it through the fill fluid to the sensing cell.',
                                  '316L stainless steel housing',
                                  sealed_why='The sensor module is sealed and filled at the factory and is replaced '
                                             'as a unit, never opened in the field.'),
            'isolator': comp('Isolating diaphragms', 'Thin corrugated diaphragms that meet the process and pass its '
                             'pressure to the fill fluid; never scratched, punctured or pressed.',
                             '316L stainless steel'),
            'sensor_cell': comp('Sensing cell', 'A capacitance cell: the fill fluid moves its sensing diaphragm '
                                'between two plates, and the change in capacitance measures the pressure.',
                                'Silicone fill fluid, metal and ceramic cell'),
            'housing': comp('Electronics housing', 'Threaded onto the sensor module\'s neck; a wall divides it into '
                            'the electronics compartment and the field terminal compartment, each with its cover.',
                            'Low-copper aluminium, painted'),
            'cover_front': comp('Electronics cover', 'Screws onto the electronics side of the housing, metal to '
                                'metal; its window shows the display.', 'Low-copper aluminium, painted',
                                sealed_why='The window is set in the cover at the factory: the cover and its window '
                                           'are one spare part.'),
            'window': comp('Display window', 'The glass in the electronics cover through which the display is read.',
                           'Glass'),
            'cover_back': comp('Terminal cover', 'Screws onto the side marked "FIELD TERMINALS"; taken off to reach '
                               'the wiring.', 'Low-copper aluminium, painted'),
            'electronics': comp('Electronics board', 'Linearises the sensor\'s signal and makes the 4–20 mA output '
                                'and its HART signal; held in the housing by two captive screws.',
                                'Printed circuit board'),
            'display': comp('LCD display', 'Shows the measured value; plugs onto the electronics board with a pin '
                            'connector and can be turned in steps.', 'Plastic, liquid crystal display'),
            'terminal_block': comp('Terminal block', 'Where the loop wires land: the signal terminals and the test '
                                   'terminals; slides onto the housing\'s power posts, held by two screws.',
                                   'Plastic body, brass terminals'),
            'cable_gland': comp('Cable gland', 'Seals the loop cable where it enters the terminal compartment.',
                                'Nickel-plated brass'),
        },
        'fasteners': {
            'flange_bolts': {'name': '4 flange bolts', 'joins': ['process_flange', 'sensor_module'],
                             'sources': [R3051]},
            'set_screw': {'name': 'Housing rotation set screw', 'joins': ['housing', 'sensor_module'],
                          'sources': [R3051]},
        },
        'assembly': ASSEMBLY,
        # the views (WORKSHOP.md §4.7): the X-ray takes the shells round the insides; the cutaway opens a quarter on
        # the display side and the front, through the housing's axis and the sensor module's (the manual's cutaway
        # figures show the module and the electronics this way); the transmitter runs taken apart (on the bench the
        # loop is wired to the terminal block wherever it lies); powered, only the terminal cover may be opened (to
        # measure the loop current or connect a HART communicator, outside a hazardous area): the electronics, the
        # sensor module and the flange come out with the loop supply off (the user's decision, 2026-11-07)
        'views': {'xray_all': ['manifold', 'process_flange', 'sensor_module', 'housing', 'cover_front',
                               'cover_back'],
                  'cutaway': {'planes': [{'normal': [0, -1, 0], 'offset': 0}, {'normal': [1, 0, 0], 'offset': 0}]},
                  'run_exploded': True,
                  'open_running': {'allowed': ['cover_back'],
                                   'why': 'Switch the loop supply off first. With the loop live only the terminal '
                                          'cover comes off, to measure the loop current or connect a HART '
                                          'communicator (outside a hazardous area); everything else (the '
                                          'electronics, the sensor module, the flange) comes out with the loop '
                                          'dead.'}},
    }


def step(place, text, needs=(), why=None):
    s = {'place': place, 'text': [text], 'sources': [R3051]}
    if why:
        s['why'] = [why]
    if needs:
        s['needs'] = [list(n) for n in needs]
    return s


# §6.5: the housing onto the sensor module, its set screw; §6.5.1 the electronics board and its cover; §6.5.2 the
# terminal block and its cover; §6.5.3 the process flange and its bolts; §6.5.4 the drain/vent valves; §3.5 the
# manifold under the flange. A part that sits in another (the terminal block in the housing) goes in wherever that one
# stands; the needs are only what the manual says must come first. The sealed parts' insides (the module's diaphragms and cell, the cover's window) come with
# them: their steps are done as soon as the part they sit in is placed.
ASSEMBLY = [
    step('sensor_module', 'Set the sensor module on the bench, its isolating diaphragms down and clear of anything '
         'that could scratch them.'),
    step('isolator', 'The isolating diaphragms come with the sensor module: never scratch, puncture or press them.'),
    step('sensor_cell', 'The sensing cell is sealed inside the sensor module with its fill fluid.'),
    step('housing', 'Tuck the ribbon cable into the internal black cap, lower the electronics housing onto the module '
         'and turn it clockwise until it is no more than one full turn from flush.',
         [('sensor_module', 'The housing threads onto the sensor module\'s neck: put the sensor module in place first.',
           'Unscrew the housing before the sensor module is moved.')],
         why='Turned with the cable caught, the housing would tear the ribbon cable.'),
    step('set_screw', 'Tighten the housing rotation set screw.',
         [('housing', 'The set screw locks the housing on the module: thread the housing on first.',
           'Loosen the housing rotation set screw one full turn before unscrewing the housing.')]),
    step('electronics', 'Connect the ribbon cable to the electronics board, slide the board in by its two captive '
         'screws onto the power posts without forcing it, and tighten the screws.',
         [('housing', 'The electronics board goes into the housing: put the housing on first.',
           'Take the electronics board out and unplug its ribbon cable before the housing comes off the module.')],
         why='The board is sensitive to static: hold it by its captive screws.'),
    step('display', 'Plug the LCD display onto the board\'s pin connector, turned the way it is to be read.',
         [('electronics', 'The display plugs onto the electronics board: fit the board first.',
           'Take the display off before the electronics board comes out.')]),
    step('cover_front', 'Screw the electronics cover on until it meets the housing metal to metal.',
         [('electronics', 'Fit the electronics board before closing the electronics cover.',
           'Take the electronics cover off before the electronics board.'),
          ('display', 'Fit the display before closing the electronics cover.',
           'Take the electronics cover off before the display.')],
         why='Covers engaged metal to metal seal the housing and keep it explosion-proof.'),
    step('window', 'The window comes with the electronics cover.'),
    step('terminal_block', 'Slide the terminal block onto the housing\'s power posts and tighten its two captive '
         'screws.'),
    step('cable_gland', 'Screw the cable gland into the conduit entry of the terminal compartment.'),
    step('cover_back', 'Screw the terminal cover on, fully engaged.',
         [('terminal_block', 'Fit the terminal block before closing the terminal cover.',
           'Take the terminal cover off before the terminal block.')]),
    step('process_flange', 'Check the PTFE O-rings, then hold the process flange on the sensor module with its two '
         'alignment screws, finger tight.',
         [('sensor_module', 'The process flange goes onto the sensor module\'s diaphragms: put the module in place '
           'first.', 'Take the process flange off before the sensor module is moved.')],
         why='Overtightened, the alignment screws would pull the flange out of line with the module.'),
    step('flange_bolts', 'Fit the four flange bolts finger tight, then tighten them crosswise, first to the initial '
         'and then to the final torque.',
         [('process_flange', 'The flange bolts go in once the process flange sits on the sensor module.',
           'Take the four flange bolts out before the process flange comes off.')]),
    step('drain_vents', 'Wrap the drain/vent valves\' threads with sealing tape and screw them into the flange, their '
         'openings pointing down.'),
    step('manifold', 'Bolt the manifold under the process flange, as its maker\'s instructions say.',
         [('process_flange', 'The manifold bolts under the process flange: fit the flange first.',
           'Take the manifold off before the process flange.')]),
]


# ------------------------------------------------------------------ the bench model (WORKSHOP.md §6.4, milestone K3)

NE43 = 'r3051_alarm'
SOURCES_BENCH = [
    {'id': R3051, 'cite': SOURCES[0]['cite'] + '; §2.7.4 and §A.3.9 damping (a first-order time constant, 0–60 s, '
                  'added to the sensor module\'s response), §2.9.1 alarm and saturation levels (table 2-5: the '
                  'NAMUR-compliant 3.8 and 20.5 mA saturation, ≤ 3.6 and ≥ 22.5 mA alarm, after NAMUR NE 43), '
                  'the 2-wire loop-powered 4–20 mA output and its LCD display',
     'url': SOURCES[0]['url']},
    {'id': 'liptak', 'cite': 'B. G. Lipták (ed.), Instrument Engineers\' Handbook, vol. 1: Process Measurement and '
                             'Analysis, 4th ed., CRC Press (2003), ch. 5 pressure measurement: diaphragm seals and '
                             'fill fluids, impulse (sensing) lines, their plugging and the reading it freezes',
     'url': 'https://www.routledge.com/Instrument-Engineers-Handbook-Volume-One-Process-Measurement-and-Analysis/'
            'Liptak/p/book/9780849310836'},
]

URV = 10.0          # the calibrated range 0–10 bar gauge (a range the 3051's gauge sensor modules cover)
DAMPING = 0.4       # seconds (one time constant: §A.3.9)
LINE_TAU = 0.3      # the impulse line and the isolating diaphragm's fill: how fast the sensor sees a change
SURGE = 15.0        # bar: the over-range fault's process pressure (past the upper range, within overpressure limits)


def bench():
    """The transmitter on the bench: a hand pump's pressure on the process flange (the slider, from vacuum to past the
    upper range), the 24 V loop supply (Start, Stop) and a meter in the loop. Every channel reads one value of this
    model: the isolating diaphragm's travel (`x_dia`), the display (`pv`, lit by `lit`), the terminals' current
    (`loop_ma`), the impulse line's flow (`flow_frac`), the sensor's colour (`p_dia`)."""
    v = [
        ['p_applied', {'state': 0, 'unit': 'bar'}],             # the hand pump's pressure (the slider)
        ['powered', {'state': 0}],                               # the loop supply (the machine writes it)
        ['blocked', {'state': 0}],                               # faults' states
        ['loop_open', {'state': 0}],
        ['surge', {'state': 0}],
        # the pressure at the process flange: the pump's, or the surge's while the over-range fault stands
        ['p_proc', {'select': 'surge', 'cases': ['p_applied', SURGE], 'unit': 'bar'}],
        # the impulse line: blocked, it keeps the pressure trapped between the blockage and the diaphragm (Liptak)
        ['p_line', {'hold': 'p_proc', 'when': 'blocked', 'unit': 'bar'}],
        # the isolating diaphragm and its fill fluid follow the line with the line's lag; what flows in the line is the
        # difference still to fill (signed: into the transmitter while the pressure rises, out while it falls)
        ['p_dia', {'lag': 'p_line', 'tau': LINE_TAU, 'unit': 'bar'}],
        ['dp_fill', {'diff': ['p_line', 'p_dia']}],
        ['flow_frac', {'of': 'dp_fill', 'table': [[-1, -1], [1, 1]]}],
        # the diaphragm's travel, 0 at no pressure and 1 at the upper range; it stops on its bed past 1.2 (the
        # module's overpressure protection) and bows out a little under vacuum (drawn exaggerated: the anim's travel)
        ['x_dia', {'of': 'p_dia', 'table': [[-1, -0.1], [0, 0], [URV, 1], [URV * 1.2, 1.2]]}],
        ['p_sensed', {'lag': 'p_dia', 'tau': 0.1, 'unit': 'bar'}],   # the sensing cell's own response
        # the electronics: damping (one time constant), the 4–20 mA line, NAMUR saturation (3.8, 20.5 mA)
        ['pv', {'lag': 'p_sensed', 'tau': DAMPING, 'unit': 'bar'}],
        ['pct', {'product': ['pv', 100 / URV], 'unit': '%'}],
        ['ma_line', {'of': 'pv', 'table': [[-URV, -12], [0, 4], [URV, 20], [2 * URV, 36]], 'unit': 'mA'}],
        ['ma_lo', {'max': ['ma_line', 3.8]}],
        ['ma_out', {'min': ['ma_lo', 20.5], 'unit': 'mA'}],
        ['over', {'cmp': ['ma_line', '>', 20.5]}],
        ['under', {'cmp': ['ma_line', '<', 3.8]}],
        # a 2-wire transmitter takes its power from the loop: no supply or an open loop, no current, a dark display
        ['closed', {'not': 'loop_open'}],
        ['lit', {'and': ['powered', 'closed']}],
        ['loop_ma', {'select': 'lit', 'cases': [0, 'ma_out'], 'unit': 'mA'}],
        ['sat_hi', {'and': ['lit', 'over']}],
        ['sat_lo', {'and': ['lit', 'under']}],
        ['no_current', {'and': ['powered', 'loop_open']}],
    ]
    return {
        'format': 'walkdown-plant-bench', 'version': 1, 'part': 'pressure_transmitter',
        'sources': SOURCES_BENCH,
        'values': v,
        'ops': [
            {'at': 'process_flange', 'do': 'set', 'input': 'p_applied', 'range': [-1, 12],
             'title': 'Applied pressure'},
            {'at': 'terminal_block', 'do': 'start', 'machine': 'supply', 'title': 'Loop supply on'},
            {'at': 'terminal_block', 'do': 'stop', 'machine': 'supply', 'title': 'Loop supply off'},
        ],
        'machines': [
            {'id': 'supply', 'at': 'terminal_block', 'init': 'off',
             'commands': {'start': {'from': ['off'], 'to': 'on'}, 'stop': {'from': '*', 'to': 'off'}},
             'states': [{'id': 'off', 'set': {'powered': 0}, 'say': 'The loop supply is off.'},
                        {'id': 'on', 'set': {'powered': 1}, 'say': 'The loop supply is on: 24 V DC across the loop.'}]},
        ],
        'alarms': [
            {'id': 'sat_high', 'at': 'electronics', 'where': 'display', 'when': 'sat_hi', 'priority': 2,
             'text': 'Over range: the output is held at 20.5 mA'},
            {'id': 'sat_low', 'at': 'electronics', 'where': 'display', 'when': 'sat_lo', 'priority': 2,
             'text': 'Under range: the output is held at 3.8 mA'},
            {'id': 'loop_dead', 'at': 'terminal_block', 'where': 'terminal_block', 'when': 'no_current',
             'priority': 1, 'text': 'No loop current: the loop is open'},
        ],
        'faults': [
            {'id': 'over_range', 'at': 'process_flange', 'text': 'Process pressure surges past the upper range',
             'set': {'surge': 1}, 'repair': {'surge': 0}},
            {'id': 'impulse_blocked', 'at': 'process_flange', 'text': 'Impulse line blocked',
             'set': {'blocked': 1}, 'repair': {'blocked': 0}},
            {'id': 'loop_open', 'at': 'terminal_block', 'text': 'Loop open: a wire off the signal terminals',
             'set': {'loop_open': 1}, 'repair': {'loop_open': 0}},
        ],
        'start': {'p_applied': 0},
        'bind': [
            {'at': 'isolator', 'anim': 'deflect', 'of': 'x_dia', 'scale': 1},
            {'at': 'display', 'show': 'pv', 'lit': 'lit'},
            {'at': 'display', 'show': 'loop_ma', 'lit': 'lit'},
            {'at': 'terminal_block', 'show': 'loop_ma'},
            {'flow': 'impulse', 'of': 'flow_frac', 'speed': 0.06, 'colour': 'pressure', 'by': 'p_line'},
            {'at': 'sensor_cell', 'pressure': 'p_dia'},
            {'at': 'isolator', 'pressure': 'p_dia'},
        ],
        'legends': {'pressure': {'unit': 'bar', 'table': [[-1, '#5e3c99'], [0, '#2c7bb6'], [5, '#ffffbf'],
                                                          [10, '#d7191c']]}},
        'readouts': ['p_applied', 'p_sensed', 'pv', 'pct', 'loop_ma'],
        # the live plant's transmitter on the bench (WORKSHOP.md §6.5): the pressure its display shows; the loop
        # supply on (the plant's transmitters have no supply of their own to mirror: they read, so they are powered)
        'mirror': [{'value': 'p_applied', 'from': {'bind': 'show'}},
                   {'value': 'supply_state', 'from': {'machine': True, 'else': 'on'}}],
    }
