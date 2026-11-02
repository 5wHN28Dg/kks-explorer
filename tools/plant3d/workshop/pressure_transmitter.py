"""The pressure transmitter's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K1a): the words, materials and
sources of its component tree. Its geometry (the components, their pivots, explode directions, the fastener groups'
positions) is the kit's generator, apps/plant3d/kit/parts_instruments.gd `_transmitter`; the content build joins the
two and refuses a kind whose halves disagree.

Generic: a coplanar differential/gauge pressure transmitter as the public manuals describe one; no plant data.
The guided assembly order (`assembly`) comes with milestone K2.
"""

R3051 = 'r3051'
SOURCES = [
    {'id': R3051, 'cite': 'Emerson, Rosemount 3051 Pressure Transmitter with HART Protocol, reference manual '
                          '00809-0100-4007 rev. BA (2017): §3.5 integral manifolds, §4.3 LCD display, §6.4 '
                          'disassembly and §6.5 reassembly procedures',
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
                                'metal; its window shows the display.', 'Low-copper aluminium, painted'),
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
    }
