"""The first train's hoists (docs/PLANT3D.md §20.5): HRSG 1's roof monorail hoist 10SMF10 and the turbine hall's
overhead crane 30SMT10, as model content of format 1's nodes and format 2's `hold` (no engine of their own), the
pieces of equipment they are drawn with, the procedures that lift a load with each, the trainer's fault of a load
heavier than its paper says, and their groups on the control room screens.

Each motion is a `state` command of -1, 0 or 1 written by a `set` op (the pendant's hold-to-run buttons: pressed
sends 1 or -1, released 0), its position an `integrate` of the command times its speed between its limits (the
limit switches). A load is hooked on while the hook's latch is closed; it hangs from the hook when the chain is taut
and rests on the floor under it otherwise; a load not hooked on stays where it was put down (a `hold` of the hook's
position while unhooked). Everything is generic and typical (FIRST-TRAIN §2): nothing comes from a real plant."""
import math

# The roof hoist: a monorail beam on HRSG 1's roof (10UHA10, +30 m) along the casing's north half, running 3 m past
# the roof's north edge (the casing's north wall, y = 76) over a barriered drop zone at grade. Its part's origin is at
# grade under the beam's tip; positions along the beam are metres from the tip, heights metres above grade.
ROOF = {'code': '10SMF10', 'at': [125, 79, 0], 'yaw': 180, 'length': 9, 'beam_z': 34, 'deck_z': 30, 'edge': 3,
        'zone': 5}
ROOF_SPEEDS = {'hoist': 0.1, 'trolley': 0.2}            # m/s (an electric chain hoist on a motorised trolley)
ROOF_RATED = 2000                                       # kg
ROOF_SLING = 1.2          # the slings' lifting point above the load's base (a valve on its pallet, its sling legs)
ROOF_TROLLEY = [0.5, 8.0]  # the trolley's limit switches: 0.5 m from the tip, 1 m from the inner end
ROOF_HOOK = [0.4, 32.9]    # the hook's: 0.4 m above grade (the slack-chain switch over the roof), 1.1 m under the beam
                           # (the hook block's top, 0.45 m over its seat, then stays under the hoist's body)
ROOF_LANDING = 6.0         # where the procedure puts the valve down on the roof (3 m in from its edge)
ROOF_CLEAR = 31.3          # a hooked load travels only with its base this high: over the roof's handrail (31.1 m)
ROOF_VALVE_KG = 600        # the spare valve on its pallet (its paper)
ROOF_VALVE_HEAVY = 2400    # the trainer's fault: the crate holds a bigger valve than its paper says
ROOF_HALF = 0.6           # the pallet's half length along the beam (kit/parts_hoists.gd)

# The turbine hall's crane: its runway along the hall's long walls (the building's `crane`, the rail at +26 m), its
# part's origin at grade at the runway's west end on the hall's centre line, the runway along the hall (yaw 90), so
# the bridge's position is the plant's x and the trolley's its y.
CRANE = {'code': '30SMT10', 'at': [0, 0, 0], 'yaw': 90, 'runway': 80, 'rail_z': 26,
         # the rails' centres from the hall's walls: half the wall, the liner and 0.9 m (builder/plant_builder.gd
         # _crane, which checks that the crane fits its runway)
         'span': round(50 - 2 * (0.25 * 0.5 + 0.03 + 0.9), 3),
         'pendant_x': 18, 'pendant_z': 13.2}                # the pendant above the operating floor's south side
CRANE_SPEEDS = {'hoist': 0.05, 'trolley': 0.17, 'bridge': 0.33}   # m/s (a 63 t crane's main hoist, its trolley, bridge)
CRANE_RATED = 63                                        # t
CRANE_SLING = 3.0          # the four-leg sling's lifting point above the crate's base
CRANE_BRIDGE = [12, 77]    # the bridge's limits: clear of the mezzanine at the west end, its buffers at the east end
CRANE_TROLLEY = [-21.9, 21.9]
CRANE_HOOK = [0.4, 24.0]
CRANE_CLEAR = 13.5         # a hooked load travels only with its base over the operating floor's handrail (13.1 m)
CRANE_CRATE_T = 8          # a crate of spares
CRANE_HALF = 0.82          # the crate's half width across the hall, along the trolley (kit/parts_hoists.gd)
# the laydown bay: the ground floor's strip along the south wall at the east end, under the bridge's and the
# trolley's limits, so that both stop over it by themselves (a target a motion runs past is not one a hand can stop
# on: PLANT3D §20.5 "Hold-to-run")
CRANE_LAYDOWN = [CRANE_BRIDGE[1], CRANE_TROLLEY[0], 0]
CRANE_FLOOR_AT = [70, -15]       # where the procedure puts the crate down on the operating floor


def pendant(code, rows):
    return [{'code': f'{code}{c}', 'minus': a, 'plus': b} for c, a, b in rows]


def unit(code, name, kind, at):
    return {'kks': code, 'name': name, 'part': 'hoist_unit', 'at': at, 'params': {'kind': kind}}


def hrsg1_equipment():
    r = ROOF
    c = r['code']
    params = {k: r[k] for k in ('length', 'beam_z', 'deck_z', 'edge', 'zone')}
    params['sling'] = ROOF_SLING
    params['pendant'] = pendant(c, [('AE001', 'Down', 'Up'), ('AE002', 'Out', 'In'), ('AE003', 'Unhook', 'Hook on')])
    # the units ride their pieces (kit/README.md "Moving parts"): placed as the pieces stand at value 0
    bz = r['beam_z']
    return [{'kks': c, 'name': 'HRSG 1 roof monorail hoist', 'part': 'monorail_hoist', 'at': r['at'], 'yaw': r['yaw'],
             'params': params, 'plate': 'beam',
             'parts': [unit(f'{c}AE001', 'Roof hoist: chain hoist', 'hoist', [0, 0, bz - 0.35]),
                       unit(f'{c}AE002', 'Roof hoist: trolley drive', 'trolley', [0.35, 0, bz + 0.15]),
                       unit(f'{c}AE003', 'Roof hoist: hook latch', 'latch', [0, 0, 0.1]),
                       unit(f'{c}CW001', 'Roof hoist: load cell', 'load_cell', [0, 0, 0.35])]}]


def st_equipment():
    r = CRANE
    c = r['code']
    params = {k: r[k] for k in ('runway', 'span', 'rail_z', 'pendant_x', 'pendant_z')}
    params['sling'] = CRANE_SLING
    params['remote'] = True
    params['pendant'] = pendant(c, [('AE001', 'Down', 'Up'), ('AE002', 'South', 'North'), ('AE003', 'West', 'East'),
                                    ('AE004', 'Unhook', 'Hook on')])
    z = r['rail_z']
    return [{'kks': c, 'name': 'Turbine hall crane', 'part': 'overhead_crane', 'at': r['at'], 'yaw': r['yaw'],
             'params': params,
             'parts': [unit(f'{c}AE001', 'Crane: main hoist', 'hoist', [0, 1.2, z + 2.2]),
                       unit(f'{c}AE002', 'Crane: trolley drive', 'trolley', [1.2, 1.2, z + 2.2]),
                       unit(f'{c}AE003', 'Crane: bridge drives', 'bridge', [r['span'] / 2 - 0.5, 1.5, z + 1.2]),
                       unit(f'{c}AE004', 'Crane: hook latch', 'latch', [0, 0.3, 0.15]),
                       unit(f'{c}CW001', 'Crane: load cell', 'load_cell', [0, 0.3, 0.9])]}]


def hrsg1_signs():
    r = ROOF
    # on the drop zone's front barrier, facing out (north)
    y = r['at'][1] - (r['edge'] - 0.3 - r['zone']) + 0.05
    return [{'text': 'Drop zone: keep clear while the roof hoist works', 'at': [r['at'][0] + 1.6, round(y, 2), 1.3],
             'yaw': 0, 'size': 0.25}]


# ---------------------------------------------------------------- the model

LOOK = 0.1      # m: how far ahead of the trolley an empty hook's travel looks for a higher floor (> a step's travel)


def _hoist(m, p, codes, speeds, limits, init, rated, unit_w, mass, sling, clear, floor, half, bridge=False):
    """One hoist's values, ops, alarm and bindings (PLANT3D §20.5). codes: hoist, trolley, [bridge,] latch, cell,
    and the hoist's own code; limits and init per motion; floor: the step table of the floor under a point, of the
    trolley's position (the bridge does not change it); half: the load's half length along the trolley. A load hangs
    `sling` + 0.3 m under the hook when its chain is taut (0.3 m of slack in the slings while the hook sits within
    0.3 m above their lifting point), and comes down on the highest floor under its footprint."""
    hc, tc, lc, cc, own = codes['hoist'], codes['trolley'], codes['latch'], codes['cell'], codes['own']
    m.state(f'{p}_hoist_cmd', 0, hc)
    m.state(f'{p}_trolley_cmd', 0, tc)
    if bridge:
        m.state(f'{p}_bridge_cmd', 0, codes['bridge'])
    m.state(f'{p}_latch', 0, lc)
    m.state(f'{p}_mass', mass)                      # what the load really weighs (a trainer's fault may change it)
    m.NOT(f'{p}_free', f'{p}_latch')                # unhooked
    # the motions: positions between the limit switches (stateful: they read the speeds as the last step left them)
    m.integ(f'{p}_trolley_pos', f'{p}_trolley_v', speeds['trolley'], *limits['trolley'], init['trolley'], 'm', tc)
    if bridge:
        m.integ(f'{p}_bridge_pos', f'{p}_bridge_v', speeds['bridge'], *limits['bridge'], init['bridge'], 'm',
                codes['bridge'])
    m.integ(f'{p}_hook_height', f'{p}_hoist_v', speeds['hoist'], *limits['hook'], init['hook'], 'm', hc)
    # the load: where it was put down while unhooked, under the hook while hooked on
    if bridge:
        m.v(f'{p}_load_x', {'hold': f'{p}_bridge_pos', 'when': f'{p}_free', 'init': init['load'][0]})
        m.v(f'{p}_load_y', {'hold': f'{p}_trolley_pos', 'when': f'{p}_free', 'init': init['load'][1]})
    else:
        m.v(f'{p}_load_along', {'hold': f'{p}_trolley_pos', 'when': f'{p}_free', 'init': init['load'][1]})
    # the floors: under the hook, and under both ends of a load hanging from it (its footprint along the trolley);
    # a load comes down on the highest of them, and stands level only with all three the same floor
    m.tab(f'{p}_floor', f'{p}_trolley_pos', floor, step=True)
    for end, sign in (('a', -1), ('b', 1)):
        m.sum(f'{p}_end_{end}', [f'{p}_trolley_pos', sign * half])
        m.tab(f'{p}_floor_{end}', f'{p}_end_{end}', floor, step=True)
    ends = [f'{p}_floor', f'{p}_floor_a', f'{p}_floor_b']
    m.max(f'{p}_floor_top', ends)
    m.min(f'{p}_floor_low', ends)
    m.cmp(f'{p}_level', f'{p}_floor_low', '>=', f'{p}_floor_top')
    m.sum(f'{p}_hang', [f'{p}_hook_height', -round(sling + 0.3, 6)])
    m.diff(f'{p}_slack', f'{p}_hang', f'{p}_floor_top')
    m.cmp(f'{p}_taut', f'{p}_slack', '>=', 0)
    m.cmp(f'{p}_rest', f'{p}_slack', '<=', 0.01)
    m.max(f'{p}_load_zc', [f'{p}_floor_top', f'{p}_hang'])
    m.v(f'{p}_load_height', {'hold': f'{p}_load_zc', 'when': f'{p}_free', 'init': init['load'][2]})
    # the load cell: what hangs on the hook
    m.prod(f'{p}_weight', [f'{p}_latch', f'{p}_taut', f'{p}_mass'], unit_w, cc)
    m.cmp(f'{p}_over', f'{p}_weight', '>', rated)
    # travel: unhooked, or the load lifted clear of what it would hit; and the hook never carried into a higher
    # floor's edge (an empty hook low over grade stops short of the roof's or the operating floor's edge: it keeps
    # 0.4 m above the floor under it wherever it goes, as lowering does)
    m.cmp(f'{p}_clear', f'{p}_load_height', '>=', clear)
    m.OR(f'{p}_travel_ok', [f'{p}_free', f'{p}_clear'])
    m.prod(f'{p}_look', [f'{p}_trolley_cmd', LOOK])
    m.sum(f'{p}_ahead_at', [f'{p}_trolley_pos', f'{p}_look'])
    m.tab(f'{p}_floor_ahead', f'{p}_ahead_at', floor, step=True)
    m.diff(f'{p}_rise', f'{p}_floor_ahead', f'{p}_floor')
    m.cmp(f'{p}_flat', f'{p}_rise', '<=', 0)
    m.diff(f'{p}_room_ahead', f'{p}_hook_height', f'{p}_floor_ahead')
    m.cmp(f'{p}_above_ahead', f'{p}_room_ahead', '>=', 0.4)
    m.OR(f'{p}_ahead_ok', [f'{p}_flat', f'{p}_above_ahead'])
    m.AND(f'{p}_trolley_ok', [f'{p}_travel_ok', f'{p}_ahead_ok'])
    m.prod(f'{p}_trolley_v', [f'{p}_trolley_cmd', f'{p}_trolley_ok'])
    if bridge:
        m.prod(f'{p}_bridge_v', [f'{p}_bridge_cmd', f'{p}_travel_ok'])
    # the hoist: up within the rated load (the overload device stops it as the load starts to lift); down until the
    # hook is 0.4 m above the floor under it (the slack-chain switch), or with a load hooked on, above the highest
    # floor under the load
    m.sel(f'{p}_hook_floor', f'{p}_latch', [f'{p}_floor', f'{p}_floor_top'])
    m.diff(f'{p}_room', f'{p}_hook_height', f'{p}_hook_floor')
    m.cmp(f'{p}_down_ok', f'{p}_room', '>', 0.4)
    m.cmp(f'{p}_up', f'{p}_hoist_cmd', '>', 0)
    m.NOT(f'{p}_up_ok', f'{p}_over')
    m.sel(f'{p}_hoist_ok', f'{p}_up', [f'{p}_down_ok', f'{p}_up_ok'])
    m.prod(f'{p}_hoist_v', [f'{p}_hoist_cmd', f'{p}_hoist_ok'])
    # the hook at the load's slings: from the load's base up to 0.3 m above their lifting point (a hook lowered
    # past the lifting point only slackens the slings, and the slack-chain switch stops it: a hand that lets go
    # late still finds the hook at them), over the load, and the load's footprint on one floor
    m.diff(f'{p}_gap', f'{p}_hook_height', f'{p}_load_height')
    m.tab(f'{p}_gap_ok', f'{p}_gap', [[-1000, 0], [0, 1], [round(sling + 0.3001, 6), 0]], step=True)
    near = [f'{p}_gap_ok', f'{p}_level']
    for ax, pos, load in (('along', 'trolley_pos', 'load_y' if bridge else 'load_along'),
                          ('across', 'bridge_pos', 'load_x')):
        if ax == 'across' and not bridge:
            continue
        m.diff(f'{p}_off_{ax}', f'{p}_{pos}', f'{p}_{load}')
        m.tab(f'{p}_over_{ax}', f'{p}_off_{ax}', [[-1000, 0], [-0.3, 1], [0.3001, 0]], step=True)
        near.append(f'{p}_over_{ax}')
    m.AND(f'{p}_at_load', near)
    # the ops: hold-to-run motions (a `set` of -1 to 1: the app sends 1 or -1 while a button is held, 0 on release)
    m.op(hc, 'set', None, (), ('local',), input=f'{p}_hoist_cmd', range=[-1, 1])
    m.op(tc, 'set', None, (), ('local',), input=f'{p}_trolley_cmd', range=[-1, 1])
    if bridge:
        m.op(codes['bridge'], 'set', None, (), ('local',), input=f'{p}_bridge_cmd', range=[-1, 1])
    m.op(lc, 'close', {f'{p}_latch': 1},
         [(f'{p}_at_load', 'The hook is not at the slings: lower it to within 0.3 m above their lifting point, over '
                           'the load')], ('local',))
    m.op(lc, 'open', {f'{p}_latch': 0},
         [(f'{p}_rest', 'The load is not resting: lower it onto the floor before unhooking'),
          (f'{p}_level', 'The load stands over a floor\'s edge: bring it wholly over one floor before unhooking')],
         ('local',))
    m.alarm(f'{p}_overload', cc, f'{own} overload: the load is over the rated {rated:,} {unit_w}', f'{p}_over', 3,
            own, 'WAH')
    # what is seen: the moving pieces (kit/README.md "Moving parts")
    m.b(kks=own, anim='trolley', of=f'{p}_trolley_pos')
    m.b(kks=own, anim='hook', of=f'{p}_hook_height')
    m.b(kks=own, anim='rope' if bridge else 'chain', of=f'{p}_hook_height')
    if bridge:
        m.b(kks=own, anim='bridge', of=f'{p}_bridge_pos')
        m.b(kks=own, anim='load_y', of=f'{p}_load_x')
        m.b(kks=own, anim='load_x', of=f'{p}_load_y')
    else:
        m.b(kks=own, anim='load_y', of=f'{p}_load_along')
    m.b(kks=own, anim='load_z', of=f'{p}_load_height')
    m.b(kks=hc, sound='motor_small', gain={'of': f'{p}_hoist_v', 'table': [[-1, 0.6], [0, 0], [1, 0.6]]})


def roof_hoist(m):
    c = ROOF['code']
    p = 'roof_hoist'
    # the floor under a point of the beam: grade over the drop zone, the roof's deck from its edge in
    floor = [[-100, 0], [ROOF['edge'], ROOF['deck_z']]]
    _hoist(m, p, {'hoist': f'{c}AE001', 'trolley': f'{c}AE002', 'latch': f'{c}AE003', 'cell': f'{c}CW001',
                  'own': c}, ROOF_SPEEDS, {'trolley': ROOF_TROLLEY, 'hook': ROOF_HOOK},
           {'trolley': ROOF_TROLLEY[1], 'hook': ROOF_HOOK[1], 'load': [0, ROOF_TROLLEY[0], 0]}, ROOF_RATED, 'kg',
           ROOF_VALVE_KG, ROOF_SLING, ROOF_CLEAR, floor, ROOF_HALF)
    # where the procedure's steps end (PLANT3D §8 `done`)
    m.cmp(f'{p}_at_tip', f'{p}_trolley_pos', '<=', ROOF_TROLLEY[0] + 0.001)
    m.cmp(f'{p}_at_landing', f'{p}_trolley_pos', '>=', ROOF_LANDING)
    m.cmp(f'{p}_hook_clear', f'{p}_hook_height', '>=', ROOF_HOOK[1] - 0.5)


def crane(m):
    c = CRANE['code']
    p = 'crane'
    floor = [[-100, 0], [-20, 12], [20.0001, 0]]     # the operating floor (+12 m) between y -20 and 20, else grade
    _hoist(m, p, {'hoist': f'{c}AE001', 'trolley': f'{c}AE002', 'bridge': f'{c}AE003', 'latch': f'{c}AE004',
                  'cell': f'{c}CW001', 'own': c}, CRANE_SPEEDS,
           {'trolley': CRANE_TROLLEY, 'bridge': CRANE_BRIDGE, 'hook': CRANE_HOOK},
           {'trolley': 0, 'bridge': 66, 'hook': 20, 'load': CRANE_LAYDOWN}, CRANE_RATED, 't', CRANE_CRATE_T,
           CRANE_SLING, CRANE_CLEAR, floor, CRANE_HALF, bridge=True)
    m.cmp(f'{p}_at_laydown', f'{p}_bridge_pos', '>=', CRANE_LAYDOWN[0] - 0.001)
    m.cmp(f'{p}_south', f'{p}_trolley_pos', '<=', CRANE_TROLLEY[0] + 0.001)
    m.cmp(f'{p}_north', f'{p}_trolley_pos', '>=', CRANE_FLOOR_AT[1])
    m.cmp(f'{p}_west', f'{p}_bridge_pos', '<=', CRANE_FLOOR_AT[0])
    m.cmp(f'{p}_hook_clear', f'{p}_hook_height', '>=', 20)


def faults():
    """The trainer's fault (PLANT3D §20.5, as built): the spare valve's crate holds more than its paper says. The
    trainer puts it right (the right crate brought); in a version 2 plant only the trainer repairs."""
    return [{'id': 'roof_hoist_heavy', 'set': {'roof_hoist_mass': ROOF_VALVE_HEAVY},
             'text': f'The spare valve\'s crate weighs {ROOF_VALVE_HEAVY:,} kg, not the {ROOF_VALVE_KG} kg on its '
                     f'paper (the roof hoist is rated {ROOF_RATED:,} kg)',
             'repair': {'roof_hoist_mass': ROOF_VALVE_KG}}]


# ---------------------------------------------------------------- the procedures

def _k(code):
    return {'link': [code], 'to': {'kks': code}}


def _step(sid, text, at, do, done, why=None):
    s = {'id': sid, 'text': text, 'at': list(at), 'go': 'walk', 'do': list(do), 'ordered': True, 'done': done}
    if why:
        s['why'] = [{'p': [why]}]
    return s


def _op(code, do, value=None):
    o = {'kks': code, 'do': do}
    if value is not None:
        o['value'] = value
    return o


def roof_hoist_lift():
    c = ROOF['code']
    h, t, l = f'{c}AE001', f'{c}AE002', f'{c}AE003'
    S = [
        _step('trolley_out', ['At the roof hoist\'s pendant (', _k(c), '), hold Out until the trolley (', _k(t),
                              ') stops at the end of the beam, over the drop zone.'], [c, t],
              [_op(t, 'set', -1)], 'roof_hoist_at_tip',
              'The beam runs 3 m past the roof\'s edge: a load lifted there clears the casing, and the barriered '
              'zone under it keeps everyone out of its way.'),
        _step('lower', ['Release Out, then hold Down: lower the hook (', _k(h), ') to the valve\'s slings at '
                        'grade.'], [h, c], [_op(t, 'set', 0), _op(h, 'set', -1)], 'roof_hoist_at_load'),
        _step('hook_on', ['Release Down and, at the hook, close its latch (', _k(l), ') on the slings.'], [l],
              [_op(h, 'set', 0), _op(l, 'close')], 'roof_hoist_latch',
              'The latch keeps the slings from jumping off the hook when the chain goes slack.'),
        _step('hoist', ['Back at the pendant on the roof, hold Up: hoist the valve until it clears the roof\'s '
                        'handrail. Watch the load cell (', _k(f'{c}CW001'), ').'], [c, f'{c}CW001'],
              [_op(h, 'set', 1)], 'roof_hoist_clear',
              f'The hoist is rated {ROOF_RATED:,} kg: a heavier load stops it as it starts to lift, and the load '
              'cell shows what hangs on the hook.'),
        _step('trolley_in', ['Release Up, then hold In: bring the valve in over the roof, 3 m from its edge.'], [t],
              [_op(h, 'set', 0), _op(t, 'set', 1)], 'roof_hoist_at_landing',
              'The trolley moves a hooked load only once it is clear of the handrail: it would drag it into the '
              'roof\'s edge.'),
        _step('lower_roof', ['Release In, then hold Down: set the valve down on the roof.'], [h],
              [_op(t, 'set', 0), _op(h, 'set', -1)], 'roof_hoist_rest'),
        _step('unhook', ['Release Down and open the hook\'s latch (', _k(l), ') to unhook the slings.'], [l],
              [_op(h, 'set', 0), _op(l, 'open')], 'roof_hoist_free',
              'The latch opens only with the load resting: a hanging load must never be unhooked.'),
        _step('clear', ['Hold Up to raise the empty hook clear of the valve, then release.'], [h],
              [_op(h, 'set', 1)], 'roof_hoist_hook_clear'),
    ]
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'roof_hoist_lift',
            'title': 'Lift a spare valve onto HRSG 1\'s roof', 'kind': 'procedure', 'scenario': 'cold_iron',
            'intro': [{'p': ['Lift a spare valve on its pallet from the drop zone at grade onto HRSG 1\'s roof with '
                             'the roof\'s monorail hoist (', _k(c), '): hook on at grade, hoist, bring it in over '
                             'the roof, set it down and unhook. The pendant\'s buttons run a motion only while '
                             'they are held.']}],
            'steps': S}


def crane_lift():
    """The steps worked at the pendant are at the crane's own code (its drives ride on the bridge and trolley, 26 m
    up: no walk ends within reach of them); the latch's are at the hook."""
    c = CRANE['code']
    h, t, b, l = f'{c}AE001', f'{c}AE002', f'{c}AE003', f'{c}AE004'
    S = [
        _step('travel_east', ['At the crane\'s pendant (', _k(c), '), hold East until the bridge (', _k(b),
                              ') stops at the hall\'s east end, over the laydown bay.'], [c], [_op(b, 'set', 1)],
              'crane_at_laydown',
              'The laydown bay is the ground floor\'s strip along the south wall: nothing stands over it, so a load '
              'comes up from there past the operating floor\'s edge.'),
        _step('trolley_south', ['Release East, then hold South until the trolley (', _k(t), ') stops over the '
                                'crate.'], [c], [_op(b, 'set', 0), _op(t, 'set', -1)], 'crane_south'),
        _step('lower', ['Release South, then hold Down: lower the hook (', _k(h), ') to the crate\'s sling.'], [c],
              [_op(t, 'set', 0), _op(h, 'set', -1)], 'crane_at_load'),
        _step('hook_on', ['Release Down and close the hook\'s latch (', _k(l), ') on the sling.'], [l],
              [_op(h, 'set', 0), _op(l, 'close')], 'crane_latch'),
        _step('hoist', ['Hold Up: hoist the crate until it clears the operating floor\'s handrail. The load cell (',
                        _k(f'{c}CW001'), ') shows its weight.'], [c, f'{c}CW001'], [_op(h, 'set', 1)],
              'crane_clear',
              f'The crane is rated {CRANE_RATED} t; the bridge and the trolley move a hooked load only once it is '
              'clear of the floor\'s edge.'),
        _step('trolley_north', ['Release Up, then hold North: bring the crate in over the operating floor.'], [c],
              [_op(h, 'set', 0), _op(t, 'set', 1)], 'crane_north'),
        _step('travel_west', ['Release North, then hold West: travel the bridge to the set-down place, clear of the '
                              'turbine.'], [c], [_op(t, 'set', 0), _op(b, 'set', -1)], 'crane_west'),
        _step('lower_floor', ['Release West, then hold Down: set the crate down on the operating floor.'], [c],
              [_op(b, 'set', 0), _op(h, 'set', -1)], 'crane_rest'),
        _step('unhook', ['Release Down and open the hook\'s latch (', _k(l), ').'], [l],
              [_op(h, 'set', 0), _op(l, 'open')], 'crane_free'),
        _step('clear', ['Hold Up to raise the empty hook clear, then release.'], [c], [_op(h, 'set', 1)],
              'crane_hook_clear'),
    ]
    return {'format': 'walkdown-plant-procedure', 'version': 1, 'id': 'crane_lift',
            'title': 'Lift a crate of spares onto the operating floor', 'kind': 'procedure', 'scenario': 'cold_iron',
            'intro': [{'p': ['Lift a crate of spares from the turbine hall\'s laydown bay onto the operating floor '
                             'with the hall\'s crane (', _k(c), '), worked from its pendant or its radio remote: '
                             'hook on, hoist, travel, set down and unhook.']}],
            'steps': S}


def procedures():
    return [roof_hoist_lift(), crane_lift()]


def screen_groups():
    """{screen id: [group]} for train_screens: the hoists are on the screens of their units (PLANT3D §7.11)."""
    return {'hrsg': [{'id': 'hoist', 'title': 'Roof monorail hoist', 'at': [3, 1], 'codes': [ROOF['code']]}],
            'st': [{'id': 'crane', 'title': 'Turbine hall crane', 'at': [3, 0], 'codes': [CRANE['code']]}]}


assert math.isclose(CRANE['span'], 47.89)
