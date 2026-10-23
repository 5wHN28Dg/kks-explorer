"""The site beyond the first train (docs/plant3d/SITE.md, decision 0066, milestone C1 of docs/plant3d/MILESTONES.md):
the plant gate and its road, the admin building with its workshops, store and parking, the road west to the camp, and
the camp: accommodation blocks with porches, the mess hall and kitchen, the prayer room, gym, laundry, recreation
room, camp office, sports court, parking and bus stop. Interiors (block 1's rooms, the mess and kitchen, prayer room,
gym, laundry, recreation, the admin building's floors and the workshops) are areas of their own with `"load":
"inside"` (PLANT3D.md §18.5), loaded by the app near their doors.

Planting follows SITE.md §4: every plant has a purpose. Date palms shade the walkways people use (on the sun's side,
the south, of an east-west walkway), the mess hall's court and the admin entrance and parking; oleander hedges keep the
dust of the roads off the walkways and screen the parking from the blocks, never by the mess hall or where food is
(oleander is poisonous); bougainvillea shades the blocks' porches and the covered walkway's posts; saltbush and caper
hold the bare ground by doors; tamarisk rows are the windbreak along the camp's west and north wall (the boundary
wall's windbreak is the builder's, apps/plant3d/builder/site.gd). Gravel and compacted soil between, no lawn.
Everything is invented (R1) and generic: prefabricated single-storey blocks in light sand tones, neutral colours."""
import math

from train_areas import st, sign, rect, window

SITE_PACK = 'site'
CAMP_PACK = 'camp'
ROAD_Y = (12, 19)          # the road from the plant gate to the camp: its carriageway (7 m), as far as the camp's spine
VERGE_Y = (19, 21)         # the verge on its north side, where the palms stand (south of the walkway: its shade)
WALK_Y = (21, 23)          # the walkway along it (2 m)
WALL_X = -140              # the boundary wall's west side (the site areas reach it: builder/site.gd)


def area2(aid, title, bounds, pack, structures=(), signs=(), load=None):
    a = {'format': 'walkdown-plant-area', 'version': 2, 'id': aid, 'title': title, 'bounds': bounds, 'pack': pack,
         'equipment': [], 'pipes': [], 'structures': list(structures), 'signs': list(signs)}
    if load:
        a['load'] = load
    return a


def r3(x):
    return round(x, 3) + 0.0


def box_road(sid, x0, y0, x1, y1, surface='asphalt', kks=None):
    """A road (or walkway, or paved court) over a plan rectangle: walkable, cut out of the ground (builder/site.gd)."""
    return st(sid, 'road', [x0, y0, 0], kks=kks, params={'outline': rect(r3(x1 - x0), r3(y1 - y0)), 'surface': surface})


def room(sid, origin, z, height, walls, openings):
    """Partitions (kit `room`) given in plan coordinates: placed at `origin` (a corner of the area), relative to it."""
    ox, oy = origin
    rel = lambda q: [r3(q[0] - ox), r3(q[1] - oy)]
    return st(sid, 'room', [ox, oy, z], params={'height': height,
                                                'walls': [{'a': rel(w['a']), 'b': rel(w['b'])} for w in walls],
                                                'openings': [dict(o, at=rel(o['at'])) for o in openings]})


def row(sid, species, a, b, spacing=0, height=0):
    """A row of plants from plan point a to b (one at a, then every spacing m)."""
    p = {'species': species, 'route': [[0, 0, 0], [r3(b[0] - a[0]), r3(b[1] - a[1]), 0]]}
    if spacing:
        p['spacing'] = spacing
    if height:
        p['height'] = height
    return st(sid, 'planting', [a[0], a[1], 0], params=p)


def plant1(sid, species, at, height=0):
    p = {'species': species}
    if height:
        p['height'] = height
    return st(sid, 'planting', [at[0], at[1], 0], params=p)


def wall(sid, pts, height=2.4):
    """A precast concrete wall along plan points (the camp's perimeter, the road corridor's sides): solid, a coping on
    top; a fence's palisade, a pale every 0.2 m, was 165,000 vertices round the camp."""
    x0, y0 = pts[0]
    return st(sid, 'wall', [x0, y0, 0], params={'route': [[r3(x - x0), r3(y - y0), 0] for x, y in pts], 'height': height,
                                                 'thickness': 0.2})


def kerb(sid, a, b, painted=True):
    return st(sid, 'kerb', [a[0], a[1], 0], params={'route': [[0, 0, 0], [r3(b[0] - a[0]), r3(b[1] - a[1]), 0]],
                                                    'painted': painted})


SIDE_YAW = {'s': 180, 'n': 0, 'e': 90, 'w': 270}


def building(sid, x0, y0, x1, y1, h, kks, doors, cladding='panel', floor='vinyl', windows=(), locked=False, extra=()):
    """A building over a plan rectangle and its doors: `doors` [(side, along, kind)], `along` metres from the side's
    west or south end; `windows` [(side, along, z, w, h)]. A locked door is a shell's (it never opens)."""
    w, d = r3(x1 - x0), r3(y1 - y0)
    openings, out = [], []
    for k, (side, t, kind) in enumerate(doors):
        width = {'personnel': 1.0, 'double': 1.8, 'roller': 3.5}[kind]
        height = 3.5 if kind == 'roller' else (2.4 if kind == 'double' else 2.1)
        rel = {'s': [t, 0], 'n': [t, d], 'w': [0, t], 'e': [w, t]}[side]
        if not locked:
            openings.append({'kind': 'door', 'at': [rel[0], rel[1], 0], 'width': width, 'height': height})
        prm = {'kind': kind, 'width': width, 'height': height}
        if locked:
            prm['locked'] = True
        out.append(st(f'{sid}_door{k + 1}', 'door', [r3(x0 + rel[0]), r3(y0 + rel[1]), 0], SIDE_YAW[side], params=prm))
    for side, t, z, ww, wh in windows:
        rel = {'s': [t, 0], 'n': [t, d], 'w': [0, t], 'e': [w, t]}[side]
        openings.append(window(rel[0], rel[1], z, ww, wh))
    openings += list(extra)
    b = st(sid, 'building', [x0, y0, 0], kks=kks, params={'outline': rect(w, d), 'height': h, 'cladding': cladding,
                                                          'floor': floor, 'openings': openings})
    return [b] + out


def windows_along(side, length, every, z=1.5, w=1.2, h=1.0, skip=()):
    out = []
    n = int(length // every)
    for i in range(n):
        t = r3((i + 0.5) * length / n)
        if any(abs(t - s) < w for s in skip):
            continue
        out.append((side, t, z, w, h))
    return out


def lamps(prefix, a, b, every, y=None):
    out = []
    n = max(1, int(abs(b - a) // every))
    for i in range(n + 1):
        x = r3(a + (b - a) * i / n)
        out.append(st(f'{prefix}_{i + 1}', 'lamp_post', [x, y, 0], params={'height': 8}))
    return out


def palms_along(prefix, x0, x1, y, every=8.0, skip=()):
    """Date palms along y from x0 to x1 every `every` m, none within 3 m of an x in `skip` (a road, a crossing), each a
    structure of its own (a row's route can't leave gaps)."""
    out = []
    n = int(abs(x1 - x0) // every)
    k = 0
    for i in range(n + 1):
        x = r3(x0 + (x1 - x0) * i / n)
        if any(abs(x - s) < 3.5 for s in skip):
            continue
        k += 1
        out.append(plant1(f'{prefix}_{k}', 'date_palm', [x, y]))
    return out


# ---------------------------------------------------------------- the plant gate (SITE.md: `gate`)

def gate():
    x0, x1 = WALL_X, -53
    ent = (-92, -86)    # the admin building's entrance road, northwards
    s = [box_road('gate_road', x0, ROAD_Y[0], x1, ROAD_Y[1], kks='00UZA10'),
         box_road('gate_walk_w', x0, WALK_Y[0], ent[0], WALK_Y[1], 'concrete'),
         box_road('gate_walk_e', ent[1], WALK_Y[0], x1, WALK_Y[1], 'concrete'),
         box_road('gate_entrance', ent[0], ROAD_Y[1], ent[1], 40),
         # the walkway up to the admin building, beside its road
         box_road('gate_walk_admin', ent[0] - 2, WALK_Y[1], ent[0], 40, 'concrete'),
         st('gate_crossing', 'crossing', [ent[0] + 3, 22, 0], params={'width': 6, 'length': 2}),
         kerb('gate_kerb_s', [x0, ROAD_Y[0]], [x1, ROAD_Y[0]]),
         kerb('gate_kerb_nw', [x0, ROAD_Y[1]], [ent[0], ROAD_Y[1]]),
         kerb('gate_kerb_ne', [ent[1], ROAD_Y[1]], [x1, ROAD_Y[1]]),
         # in and out: a barrier across each lane, the guard's gate house beside the walkway
         st('gate_barrier_in', 'barrier', [-131, 19.6, 0], 90, params={'width': 3.6}),
         st('gate_barrier_out', 'barrier', [-127, 11.4, 0], 270, params={'width': 3.6}),
         ]
    s += building('gate_house', -122, 24.5, -114, 29.5, 3.2, '00UYE10', [('s', 4.0, 'personnel')],
                  windows=[('s', 1.5, 1.6, 1.6, 1.0), ('s', 6.5, 1.6, 1.6, 1.0), ('w', 2.5, 1.6, 2.0, 1.0)])
    # the bus stop's shelter on the walkway, a bench under it
    s += [st('gate_bus_shelter', 'canopy', [-108, 24.4, 0], 90, params={'length': 6, 'width': 2.4, 'height': 2.6}),
          st('gate_bus_bench', 'bench', [-108, 24.9, 0], params={'length': 3})]
    # palms in the verge, south of the walkway: its shade at midday (the sun stands in the south)
    s += palms_along('gate_palm', -112, -56, (VERGE_Y[0] + VERGE_Y[1]) / 2, 8, skip=(ent[0], ent[1], -108))
    s += lamps('gate_lamp', -136, -58, 26, y=11.0)
    # low beds by the gate house's door: bare ground held against the dust
    s += [row('gate_saltbush_w', 'saltbush', (-121.3, 23.7), (-119.6, 23.7)),
          row('gate_saltbush_e', 'saltbush', (-116.4, 23.7), (-114.7, 23.7))]
    signs = [sign('Plant gate', [-118, 24.5, 2.6], 180, 0.45), sign('Gate house 00UYE10', [-114, 27, 2.4], 90, 0.3),
             sign('All visitors report to the gate house', [-122, 26.5, 1.8], 270, 0.22),
             sign('Bus stop', [-108, 25.6, 2.4], 180, 0.3), sign('Speed limit 20 km/h', [-136, 11.2, 2.2], 270, 0.3)]
    return area2('gate', 'Plant gate', [[x0, 0], [x1, 40]], SITE_PACK, s, signs)


# ---------------------------------------------------------------- admin, workshops, store, parking (`admin`)

ADMIN = (-124, 98, -92, 112)        # the three-storey office block
WORKSHOP = (-128, 50, -100, 64)
STORE = (-80, 46, -62, 58)
FLOOR_H = 3.6


def admin():
    x0, x1 = WALL_X, -53
    ax0, ay0, ax1, ay1 = ADMIN
    s = [box_road('admin_entrance', -92, 40, -86, 91, kks='00UZA20'),
         box_road('admin_walk', -94, 40, -92, 91, 'concrete'),
         box_road('admin_parking', -86, 66, -58, 91, kks='00UZD10'),
         # the paved forecourt in front of the building and north of the parking, shaded by palms
         box_road('admin_forecourt', -118, 91, -58, 98, 'concrete'),
         box_road('admin_workshop_apron', -100, 54, -94, 61),   # to the walkway's edge (not over it: tests/test_ground.gd)
         box_road('admin_store_apron', -86, 49, -80, 55, 'concrete'),
         kerb('admin_kerb_w', [-92, 40], [-92, 91], False),
         ]
    # the office block: three storeys, its floors and two straight stairs at its west end
    win = []
    for z in (1.6, 1.6 + FLOOR_H, 1.6 + 2 * FLOOR_H):
        win += [(side, t, z, ww, wh) for side, t, _, ww, wh in windows_along('s', ax1 - ax0, 4, skip=(16,) if z < 3 else ())]
        win += [(side, t, z, ww, wh) for side, t, _, ww, wh in windows_along('n', ax1 - ax0, 4)]
    s += building('admin_building', ax0, ay0, ax1, ay1, 11, '00UYC10', [('s', 16, 'double')], cladding='concrete',
                  windows=win)
    for k, z in enumerate((FLOOR_H, 2 * FLOOR_H)):
        s.append(st(f'admin_floor_{k + 1}', 'floor', [ax0, ay0, z], params={'outline': rect(ax1 - ax0, ay1 - ay0),
                                                                             'finish': 'vinyl'}))
    # (a 5.6 m run: 20 risers of 0.18 m, goings of 0.29 m, 1.2 m wide: an office stair)
    s += [st('admin_stair_1', 'stair', params={'foot': [-122.2, 100.4, 0], 'top': [-122.2, 106.0, FLOOR_H],
                                                'layout': 'straight', 'width': 1.2}),
          st('admin_stair_2', 'stair', params={'foot': [-120.2, 106.0, FLOOR_H], 'top': [-120.2, 100.4, 2 * FLOOR_H],
                                                'layout': 'straight', 'width': 1.2})]
    # its shade canopy over the path to the door, palms at the entrance, low beds along its front
    s += [st('admin_door_canopy', 'canopy', [-108, 94.5, 0], params={'length': 7, 'width': 3.2, 'height': 3.0}),
          plant1('admin_palm_w1', 'date_palm', [-114, 94.5]), plant1('admin_palm_e1', 'date_palm', [-102, 94.5]),
          row('admin_bed_w', 'caper', (-121.5, 97.2), (-111.5, 97.2)),
          row('admin_bed_e', 'caper', (-104.5, 97.2), (-94.5, 97.2))]
    # the parking under car shades, palms along the forecourt shading the walk from the cars to the door
    s += [st('admin_shade_s', 'canopy', [-72, 69, 0], 90, params={'length': 26, 'width': 5.5, 'height': 2.8}),
          st('admin_shade_n', 'canopy', [-72, 88, 0], 90, params={'length': 26, 'width': 5.5, 'height': 2.8})]
    s += palms_along('admin_palm', -90, -60, 94.5, 10)
    s += [plant1(f'admin_parking_palm_{k + 1}', 'date_palm', [-55.5, y]) for k, y in enumerate((70, 79, 88))]
    colours = ['grey', 'silver', 'sand', 'blue', 'silver', 'green', 'grey', 'silver']
    for k, x in enumerate((-83, -79.7, -76.4, -73.1, -66.5, -63.2)):
        s.append(st(f'admin_car_s{k + 1}', 'vehicle', [x, 69, 0], 180, params={'kind': 'pickup' if k % 2 else 'suv',
                                                                               'colour': colours[k]}))
    for k, x in enumerate((-83, -76.4, -73.1, -69.8, -63.2)):
        s.append(st(f'admin_car_n{k + 1}', 'vehicle', [x, 88, 0], 0, params={'kind': 'suv' if k % 2 else 'pickup',
                                                                             'colour': colours[k + 3]}))
    # workshops (I&C with its calibration bench, mechanical, electrical: interior below) and the store
    wx0, wy0, wx1, wy1 = WORKSHOP
    s += building('admin_workshops', wx0, wy0, wx1, wy1, 7, '00UST10', [('e', 7.0, 'roller'), ('s', 5.0, 'personnel')],
                  cladding='metal', floor='concrete',
                  windows=windows_along('s', wx1 - wx0, 5, z=3.0, w=2.0, skip=(5.0,)) +
                  windows_along('n', wx1 - wx0, 5, z=3.0, w=2.0))
    sx0, sy0, sx1, sy1 = STORE
    s += building('admin_store', sx0, sy0, sx1, sy1, 6, '00USU10', [('w', 6.0, 'roller')], cladding='metal',
                  floor='concrete', windows=windows_along('n', sx1 - sx0, 6, z=4.2, w=2.0), locked=True)
    s += [row('admin_ws_bed', 'saltbush', (-127.2, 49.2), (-124.2, 49.2))]
    signs = [sign('Administration building 00UYC10', [-108, ay0, 3.0], 180, 0.4),
             sign('Permit office', [-110.5, ay0, 2.5], 180, 0.25),
             sign('Workshops 00UST10', [wx1, 60.5, 4.5], 90, 0.4), sign('Store 00USU10', [sx0, 55.5, 4.0], 270, 0.4),
             sign('Parking', [-86, 90.5, 2.2], 270, 0.3)]
    return area2('admin', 'Administration, workshops and store', [[x0, 40], [x1, 135]], SITE_PACK, s, signs)


def admin_inside():
    """The office block's floors: ground floor the lobby with the reception, the permit office and the meeting room;
    the first floor the engineers' offices; the second the managers' and HSE's."""
    ax0, ay0, ax1, ay1 = ADMIN
    s = []
    # ground floor
    s.append(room('admin_in_rooms_0', (ax0, ay0), 0, FLOOR_H - 0.35, walls=[
        {'a': [-116, 98.2], 'b': [-116, 111.8]}, {'a': [-116, 104], 'b': [-92.2, 104]},
        {'a': [-104, 104], 'b': [-104, 111.8]}],
        openings=[{'kind': 'door', 'at': [-116, 100.9], 'width': 1.6, 'height': 2.3},
                  {'kind': 'door', 'at': [-110, 104], 'width': 1.0},
                  {'kind': 'door', 'at': [-98, 104], 'width': 1.0}]))
    s += [st('admin_in_door_permit', 'door', [-110, 104, 0], 180), st('admin_in_door_meeting', 'door', [-98, 104, 0], 180),
          st('admin_in_reception', 'counter', [-104, 100.3, 0], 180, params={'kind': 'reception', 'length': 3.0}),
          st('admin_in_permit_counter', 'counter', [-106.5, 107.5, 0], 270, params={'kind': 'reception', 'length': 3.0}),
          st('admin_in_permit_shelf', 'shelf', [-110, 111.6, 0], 180, params={'length': 4.0}),
          st('admin_in_meeting_table', 'table', [-98, 108, 0], 90, params={'length': 4.0, 'width': 1.2}),
          st('admin_in_meeting_screen', 'screen', [-92.15, 108, 0], 270, params={'size': 1.6, 'mount': 1.5})]
    for k, x in enumerate((-99.4, -98.0, -96.6)):
        s += [st(f'admin_in_meeting_chair_s{k + 1}', 'chair', [x, 106.95, 0], 0, params={'kind': 'office'}),
              st(f'admin_in_meeting_chair_n{k + 1}', 'chair', [x, 109.05, 0], 180, params={'kind': 'office'})]
    for k, x in enumerate((-114.2, -111.6)):
        s += [st(f'admin_in_permit_desk_{k + 1}', 'desk', [x, 108.6, 0], 0),
              st(f'admin_in_permit_chair_{k + 1}', 'chair', [x, 108.0, 0], 0, params={'kind': 'office'})]
    # first floor: four offices along the north side, an open office to the south
    z1 = FLOOR_H
    s.append(room('admin_in_rooms_1', (ax0, ay0), z1, FLOOR_H - 0.35, walls=[
        {'a': [-116, 105], 'b': [-92.2, 105]}, {'a': [-110, 105], 'b': [-110, 111.8]},
        {'a': [-104, 105], 'b': [-104, 111.8]}, {'a': [-98, 105], 'b': [-98, 111.8]}, {'a': [-116, 105], 'b': [-116, 111.8]}],
        openings=[{'kind': 'door', 'at': [x, 105], 'width': 1.0} for x in (-113, -107, -101, -95)]))
    for k, x in enumerate((-113, -107, -101, -95)):
        s += [st(f'admin_in_1_door_{k + 1}', 'door', [x, 105, z1], 180),
              st(f'admin_in_1_desk_{k + 1}', 'desk', [x, 110.5, z1], 180),
              st(f'admin_in_1_chair_{k + 1}', 'chair', [x, 111.1, z1], 180, params={'kind': 'office'}),
              st(f'admin_in_1_shelf_{k + 1}', 'shelf', [x + 2.2, 105.3, z1], 0, params={'length': 1.2})]
    for k, x in enumerate((-112, -108, -104, -100, -96)):
        s += [st(f'admin_in_1_open_desk_{k + 1}', 'desk', [x, 101.0, z1], 0, params={'width': 1.4}),
              st(f'admin_in_1_open_chair_{k + 1}', 'chair', [x, 100.4, z1], 0, params={'kind': 'office'})]
    # second floor: the managers', HSE's and the plant manager's offices, the same plan
    z2 = 2 * FLOOR_H
    s.append(room('admin_in_rooms_2', (ax0, ay0), z2, 11 - z2 - 0.35, walls=[
        {'a': [-116, 105], 'b': [-92.2, 105]}, {'a': [-108, 105], 'b': [-108, 111.8]},
        {'a': [-100, 105], 'b': [-100, 111.8]}, {'a': [-116, 105], 'b': [-116, 111.8]}],
        openings=[{'kind': 'door', 'at': [x, 105], 'width': 1.0} for x in (-112, -104, -96)]))
    for k, x in enumerate((-112, -104, -96)):
        s += [st(f'admin_in_2_door_{k + 1}', 'door', [x, 105, z2], 180),
              st(f'admin_in_2_desk_{k + 1}', 'desk', [x, 110.4, z2], 180, params={'width': 1.8, 'depth': 0.8}),
              st(f'admin_in_2_chair_{k + 1}', 'chair', [x, 111.1, z2], 180, params={'kind': 'office'}),
              st(f'admin_in_2_table_{k + 1}', 'table', [x + 2.5, 107.0, z2], 0, params={'length': 1.2, 'width': 1.2}),
              st(f'admin_in_2_sofa_{k + 1}', 'sofa', [x - 2.4, 106.0, z2], 90, params={'seats': 2})]
    s += [st('admin_in_2_meeting_table', 'table', [-104, 101.5, z2], 90, params={'length': 3.0, 'width': 1.2})]
    signs = [sign('Permit office', [-110.9, 103.8, 2.2], 180, 0.2), sign('Meeting room', [-98.9, 103.8, 2.2], 180, 0.2),
             sign('Reception', [-104, 100.0, 2.4], 180, 0.2),
             sign('HSE', [-112.9, 104.8, 2.2 + z2], 180, 0.2), sign('Plant manager', [-104.9, 104.8, 2.2 + z2], 180, 0.2),
             sign('Operations manager', [-96.9, 104.8, 2.2 + z2], 180, 0.2)]
    return area2('admin_in', 'Administration building', [[ax0, ay0], [ax1, ay1]], SITE_PACK, s, signs, 'inside')


def workshop_inside():
    """Three bays: I&C (its calibration bench), mechanical, electrical; benches, shelves and lockers."""
    wx0, wy0, wx1, wy1 = WORKSHOP
    s = [room('ws_in_bays', (wx0, wy0), 0, 3.0, walls=[
        {'a': [-118.7, 50.2], 'b': [-118.7, 63.8]}, {'a': [-109.3, 50.2], 'b': [-109.3, 63.8]}],
        openings=[{'kind': 'door', 'at': [-118.7, 57], 'width': 2.0, 'height': 2.6},
                  {'kind': 'door', 'at': [-109.3, 57], 'width': 2.0, 'height': 2.6}])]
    # I&C: the calibration bench (pressure and temperature calibrators), benches, the instrument store
    s += [st('ws_in_ic_cal', 'counter', [-123.4, 63.2, 0], 180, params={'kind': 'workbench', 'length': 4.0, 'depth': 0.9}),
          st('ws_in_ic_bench', 'counter', [-127.3, 56.0, 0], 90, params={'kind': 'workbench', 'length': 3.0}),
          st('ws_in_ic_shelf', 'shelf', [-126.3, 50.4, 0], 0, params={'length': 3.0}),   # clear of the south door
          st('ws_in_ic_chair', 'chair', [-123.4, 62.3, 0], 0, params={'kind': 'office'}),
          st('ws_in_ic_desk', 'desk', [-120.2, 59.0, 0], 270)]
    s += [st('ws_in_mech_bench_1', 'counter', [-114, 63.2, 0], 180, params={'kind': 'workbench', 'length': 4.0}),
          st('ws_in_mech_bench_2', 'counter', [-114, 50.6, 0], 0, params={'kind': 'workbench', 'length': 4.0}),
          st('ws_in_mech_shelf', 'shelf', [-110.0, 59.5, 0], 270, params={'length': 2.4, 'height': 2.2})]
    s += [st('ws_in_el_bench', 'counter', [-104.5, 63.2, 0], 180, params={'kind': 'workbench', 'length': 4.0}),
          st('ws_in_el_shelf', 'shelf', [-104.5, 50.4, 0], 0, params={'length': 3.0}),
          st('ws_in_el_locker_1', 'locker', [-108.6, 61.0, 0], 90, params={'width': 1.0}),
          st('ws_in_el_locker_2', 'locker', [-108.6, 59.8, 0], 90, params={'width': 1.0})]
    signs = [sign('I&C workshop', [-118.9, 60.0, 2.2], 270, 0.25), sign('Calibration bench', [-123.4, 63.7, 2.4], 180, 0.2),
             sign('Mechanical workshop', [-109.5, 60.0, 2.2], 270, 0.25),
             sign('Electrical workshop', [-109.1, 54.0, 2.2], 90, 0.25)]
    return area2('workshop_in', 'Workshops', [[wx0, wy0], [wx1, wy1]], SITE_PACK, s, signs, 'inside')


# ---------------------------------------------------------------- the road to the camp (`road_west`)

def road_west():
    x0, x1 = -260, WALL_X
    s = [box_road('rw_road', x0, ROAD_Y[0], x1, ROAD_Y[1], kks='00UZA30'),
         box_road('rw_walk', x0, WALK_Y[0], x1, WALK_Y[1], 'concrete'),
         kerb('rw_kerb_s', [x0, ROAD_Y[0]], [x1, ROAD_Y[0]]), kerb('rw_kerb_n', [x0, ROAD_Y[1]], [x1, ROAD_Y[1]]),
         # the corridor between the camp and the plant is walled on both sides, low enough to see over (the country
         # is not walkable)
         wall('rw_wall_s', [(x0, 10.5), (x1, 10.5)], 1.2), wall('rw_wall_n', [(x0, 29.5), (x1, 29.5)], 1.2),
         # an oleander hedge between the walkway and the north wall: the dust off the road and the country
         row('rw_oleander', 'oleander', (x0 + 2, 26.0), (x1 - 2, 26.0))]
    s += palms_along('rw_palm', x0 + 4, x1 - 4, (VERGE_Y[0] + VERGE_Y[1]) / 2, 8)
    s += lamps('rw_lamp', x0 + 6, x1 - 6, 24, y=11.2)
    signs = [sign('Camp 120 m', [x1 - 3, 23.4, 2.0], 90, 0.35), sign('Plant gate', [x0 + 3, 23.4, 2.0], 270, 0.35)]
    return area2('road_west', 'Road to the camp', [[x0, 10], [x1, 30]], CAMP_PACK, s, signs)


# ---------------------------------------------------------------- the camp (`camp`, SITE.md §3)

CAMP = (-480, -40, -260, 120)
BLOCK_W, BLOCK_D, BLOCK_H = 40, 10, 3.2
AMENITY_H = 3.5
MESS_H = 4.2
COL_X = {'A': -458, 'B': -404}           # the blocks' west ends
ROW_Y = (30, 50, 70, 90)                 # their south (front) walls
WALKWAY_X = (-412, -410)                 # the covered walkway between the two columns
MESS = (-360, -16, -320, 4)
COURT = (-384, -16, -364, 4)             # the mess hall's shaded court, on its west side
GYM = (-360, 26, -344, 36)
REC = (-338, 26, -322, 36)
PRAYER = (-314, 26, -302, 36)
OFFICE = (-290, 26, -278, 34)
LAUNDRY = (-358, 46, -348, 54)
PARKING = (-300, -36, -266, -4)


def blocks():
    """Blocks 1–8: block 1 in column B's first row (by the covered walkway, nearest the gate), then alternately."""
    out = []
    n = 0
    for y in ROW_Y:
        for col in ('B', 'A'):
            n += 1
            out.append((n, COL_X[col], y, col))
    return out


def camp():
    x0, y0, x1, y1 = CAMP
    spine_w = -440
    s = [box_road('camp_spine', spine_w, ROAD_Y[0], x1, ROAD_Y[1], kks='00UZA40'),
         box_road('camp_walk', spine_w, WALK_Y[0], x1, WALK_Y[1], 'concrete'),
         kerb('camp_kerb_s1', [spine_w, ROAD_Y[0]], [-272, ROAD_Y[0]]), kerb('camp_kerb_s2', [-266, ROAD_Y[0]], [x1, ROAD_Y[0]]),
         kerb('camp_kerb_n', [spine_w, ROAD_Y[1]], [x1, ROAD_Y[1]]),
         # the camp's perimeter wall (the gate at its east side, where the road comes in) and the gate itself
         wall('camp_wall', [(x1, 10.5), (x1 - 0.5, 10.5), (x1 - 0.5, y0 + 0.5), (x0 + 0.5, y0 + 0.5),
                            (x0 + 0.5, y1 - 0.5), (x1 - 0.5, y1 - 0.5), (x1 - 0.5, 29.5), (x1, 29.5)]),
         st('camp_gate_booth', 'guard_booth', [-265.5, 26.5, 0]),
         st('camp_gate_barrier', 'barrier', [-266, 11.4, 0], 270, params={'width': 7.4}),
         st('camp_crossing', 'crossing', [-340, 15.5, 0], 90, params={'width': 7, 'length': 2.5}),
         ]
    # the windbreak: two staggered rows of tamarisk inside the west and north walls (the shamal blows from the
    # north-west, with its dust)
    for k, off in enumerate((3.0, 5.5)):
        sh = 1.25 * k
        s += [row(f'camp_tamarisk_w{k + 1}', 'tamarisk', (x0 + off, y0 + 3 + sh), (x0 + off, y1 - off)),
              row(f'camp_tamarisk_n{k + 1}', 'tamarisk', (x0 + off + 2.5 + sh, y1 - off), (x1 - 8, y1 - off))]
    # palms in the verge south of the main walkway: its shade at the shift changes
    s += palms_along('camp_palm', -270, spine_w + 4, (VERGE_Y[0] + VERGE_Y[1]) / 2, 8, skip=(-340, -411))
    s += lamps('camp_lamp', -282, spine_w + 10, 24, y=11.2)
    # oleander along the spine road's south side (dust), not by the mess hall and its court
    s += [row('camp_oleander_road', 'oleander', (spine_w + 2, 9.6), (COURT[0] - 16, 9.6)),
          # and between the parking and the blocks (dust and screening)
          row('camp_oleander_park_n', 'oleander', (PARKING[0] - 1.5, PARKING[3] + 1.5), (-274, PARKING[3] + 1.5)),
          row('camp_oleander_park_w', 'oleander', (PARKING[0] - 1.5, PARKING[1] + 1), (PARKING[0] - 1.5, PARKING[3] + 0.3))]
    # the accommodation blocks (1–8), their porches with bougainvillea on the posts, the covered walkway between them
    s += [box_road('camp_walk_blocks', WALKWAY_X[0], WALK_Y[1], WALKWAY_X[1], ROW_Y[-1] + 6, 'concrete')]
    k = 0
    for c, (y_mid, length) in enumerate(((43, 40), (80, 34))):
        s.append(st(f'camp_walk_canopy_{c + 1}', 'canopy', [-411, y_mid, 0],
                    params={'length': length, 'width': 3.0, 'height': 2.8}))
        # bougainvillea at every other post on its west side (kit/parts_site.gd canopy: posts every length / n,
        # n = ceil(length / 5.5), 0.15 m in from its sides)
        n = math.ceil(length / 5.5)
        for i in range(1, n, 2):
            k += 1
            s.append(plant1(f'camp_walk_bougainvillea_{k}', 'bougainvillea', [-412.35, r3(y_mid - length / 2 + length * i / n)]))
    for n, bx, by, col in blocks():
        sid = f'camp_block{n}'
        bx1 = bx + BLOCK_W
        inner = 'e' if col == 'A' else 'w'                 # the gable door on the walkway's side
        win = []
        for side in ('s', 'n'):
            win += [(side, BLOCK_W / 12 + 40 / 6 * i, 1.5, 1.2, 1.0) for i in range(6)]
        s += building(sid, bx, by, bx1, by + BLOCK_D, BLOCK_H, f'00UZW1{n}', [('w', 5, 'personnel'), ('e', 5, 'personnel')],
                      windows=win, locked=(n != 1))
        s.append(st(f'{sid}_porch', 'porch', [bx + BLOCK_W / 2, by, 0], 180, params={'length': BLOCK_W, 'depth': 2.5}))
        # the path from the covered walkway to the gable door
        px0, px1 = (bx1, WALKWAY_X[0]) if col == 'A' else (WALKWAY_X[1], bx)
        s.append(box_road(f'{sid}_path', px0, by + 4, px1, by + 6, 'concrete'))
        # bougainvillea at every third post of the porch (kit/parts_site.gd porch: posts every ~3.1 m)
        npost = math.ceil(BLOCK_W / 3.2)
        for i in range(0, npost + 1, 3):
            x = bx + 0.1 + (BLOCK_W - 0.2) * i / npost
            s.append(plant1(f'{sid}_bougainvillea_{i}', 'bougainvillea', [r3(x), by - 2.4]))   # at the post
    # the amenities north of the main walkway, their doors on it, a paved step to each
    for sid, (bx0, by0, bx1, by1), kks, title in (('camp_gym', GYM, '00UZW31', 'Gym'),
                                                  ('camp_rec', REC, '00UZW33', 'Recreation room'),
                                                  ('camp_prayer', PRAYER, '00UZW30', 'Prayer room'),
                                                  ('camp_office', OFFICE, '00UZW40', 'Camp office and first aid')):
        w = bx1 - bx0
        office = sid == 'camp_office'
        s += building(sid, bx0, by0, bx1, by1, AMENITY_H, kks, [('s', w / 2, 'double' if sid == 'camp_prayer' else 'personnel')],
                      windows=windows_along('s', w, 4, skip=(w / 2,)) + windows_along('n', w, 4), locked=office)
        s.append(box_road(f'{sid}_step', bx0 + w / 2 - 1.5, WALK_Y[1], bx0 + w / 2 + 1.5, by0, 'concrete'))
    # the camp office: a desk at its window, saltbush and caper by its door
    s += [st('camp_office_desk', 'desk', [-286.5, 26.9, 0], 0, params={'width': 1.4}),
          st('camp_office_chair', 'chair', [-286.5, 27.7, 0], 180, params={'kind': 'office'}),
          row('camp_office_bed_w', 'saltbush', (-286.6, 25.4), (-285.4, 25.4)),
          row('camp_office_bed_e', 'caper', (-282.6, 25.4), (-281.2, 25.4)),
          plant1('camp_gate_saltbush', 'saltbush', [-265.5, 24.6])]
    # the laundry, behind the gym, its door towards the blocks
    s += building('camp_laundry', *LAUNDRY, AMENITY_H, '00UZW32', [('w', 4, 'personnel')],
                  windows=windows_along('s', 10, 4) + windows_along('n', 10, 4))
    # the mess hall and its kitchen; a covered walkway to its door across the road's marked crossing
    mx0, my0, mx1, my1 = MESS
    s += building('camp_mess', mx0, my0, mx1, my1, MESS_H, '00UZW20', [('n', 20, 'double'), ('s', 10, 'personnel')],
                  windows=windows_along('n', 40, 4, z=1.8, w=1.6, h=1.2, skip=(20,)) +
                  windows_along('e', 20, 4, z=1.8, w=1.6, h=1.2) + windows_along('w', 20, 4, z=1.8, w=1.6, h=1.2))
    s += [box_road('camp_mess_walk', -341, my1, -339, ROAD_Y[0], 'concrete'),
          st('camp_mess_canopy', 'canopy', [-340, 8, 0], params={'length': 8, 'width': 3.0, 'height': 2.8}),
          box_road('camp_mess_service', mx0 + 8, -24, mx0 + 12, my0, 'concrete')]
    # the mess hall's court: paved, shaded by palms, tables and benches for eating outside
    cx0, cy0, cx1, cy1 = COURT
    s.append(box_road('camp_court', cx0, cy0, cx1, cy1, 'concrete'))
    for k, (x, y) in enumerate(((-380, -12), (-374, -12), (-368, -12), (-380, 0), (-374, 0), (-368, 0))):
        s.append(plant1(f'camp_court_palm_{k + 1}', 'date_palm', [x, y]))
    for k, (x, y) in enumerate(((-377, -6), (-371, -6))):
        s += [st(f'camp_court_table_{k + 1}', 'table', [x, y, 0], 90, params={'length': 2.0, 'width': 0.8}),
              st(f'camp_court_bench_{k + 1}a', 'bench', [x, y - 0.75, 0], params={'length': 2.0}),
              st(f'camp_court_bench_{k + 1}b', 'bench', [x, y + 0.75, 0], params={'length': 2.0})]
    # the parking and the bus stop: car shades over the bays, the buses between them, a shelter by the gate
    px0, py0, px1, py1 = PARKING
    s += [box_road('camp_parking', px0, py0, px1, py1, kks='00UZD20'),
          box_road('camp_parking_road', -272, py1, -266, ROAD_Y[0]),
          st('camp_shade_s', 'canopy', [-283, -32.5, 0], 90, params={'length': 30, 'width': 5.5, 'height': 2.8}),
          st('camp_shade_n', 'canopy', [-286, -7.5, 0], 90, params={'length': 24, 'width': 5.5, 'height': 2.8}),
          st('camp_bus_1', 'vehicle', [-283, -17, 0], 90, params={'kind': 'bus', 'colour': 'sand'}),
          st('camp_bus_2', 'vehicle', [-283, -23, 0], 90, params={'kind': 'bus', 'colour': 'sand'}),
          st('camp_bus_shelter', 'canopy', [-273, 24.4, 0], 90, params={'length': 6, 'width': 2.4, 'height': 2.6}),
          st('camp_bus_bench', 'bench', [-273, 24.9, 0], params={'length': 3})]
    colours = ['silver', 'grey', 'sand', 'blue', 'silver', 'green', 'grey']
    for k, x in enumerate((-297.5, -294.2, -287.6, -284.3, -277.7, -274.4)):
        s.append(st(f'camp_car_s{k + 1}', 'vehicle', [x, -32.5, 0], 180, params={'kind': 'pickup' if k % 2 else 'suv',
                                                                                 'colour': colours[k]}))
    for k, x in enumerate((-296.5, -290, -283.5)):
        s.append(st(f'camp_car_n{k + 1}', 'vehicle', [x, -7.5, 0], 0, params={'kind': 'pickup', 'colour': colours[k + 2]}))
    # the sports court, floodlit, its gate towards the main walkway
    s.append(st('camp_court_sports', 'court', [-445, -22, 0], 270, params={'length': 28, 'width': 15}))
    signs = [sign('Camp gate', [-262, 24.4, 2.6], 90, 0.4), sign('Camp office and first aid 00UZW40', [-284, 25.9, 2.8], 180, 0.25),
             sign('Mess hall 00UZW20', [-340, 4.1, 3.2], 0, 0.4), sign('Gym 00UZW31', [-352, 25.9, 2.8], 180, 0.3),
             sign('Recreation room 00UZW33', [-330, 25.9, 2.8], 180, 0.3),
             sign('Prayer room 00UZW30', [-308, 25.9, 2.9], 180, 0.3),
             sign('Laundry 00UZW32', [-358.1, 52, 2.6], 270, 0.3),
             sign('Bus stop', [-273, 25.6, 2.4], 180, 0.3), sign('Parking', [-266.2, -2, 2.2], 90, 0.3)]
    for n, bx, by, col in blocks():
        door_x = bx + BLOCK_W if col == 'A' else bx
        signs.append(sign(f'Block {n} 00UZW1{n}', [door_x, by + 7.5, 2.4], 90 if col == 'A' else 270, 0.35))
    return area2('camp', 'Camp', [[x0, y0], [x1, y1]], CAMP_PACK, s, signs)


def block1_inside():
    """Block 1: the corridor along its middle, twelve rooms with their doors and numbers; rooms 101 and 107 shown
    (bed, desk and chair, wardrobe, the bathroom with its WC, shower and basin), the others' doors shut."""
    bx, by = COL_X['B'], ROW_Y[0]
    bx1 = bx + BLOCK_W
    cy0, cy1 = by + 4.2, by + 5.8                # the corridor's walls
    pitch = BLOCK_W / 6
    walls = [{'a': [bx + 0.15, cy0], 'b': [bx1 - 0.15, cy0]}, {'a': [bx + 0.15, cy1], 'b': [bx1 - 0.15, cy1]}]
    for k in range(1, 6):
        x = r3(bx + pitch * k)
        walls += [{'a': [x, by + 0.15], 'b': [x, cy0]}, {'a': [x, cy1], 'b': [x, by + BLOCK_D - 0.15]}]
    openings, s, signs = [], [], []
    for k in range(6):
        xr = bx + pitch * k                       # the room's west wall
        for side, wy, num, open_ in (('s', cy0, 101 + k, k == 0), ('n', cy1, 107 + k, k == 0)):
            dx = r3(xr + 1.0)
            if open_:
                openings.append({'kind': 'door', 'at': [dx, wy], 'width': 0.9})
                s.append(st(f'block1_in_door_{num}', 'door', [dx, wy, 0], 180 if side == 's' else 0, params={'width': 0.9}))
            else:
                openings.append({'kind': 'door_closed', 'at': [dx, wy], 'width': 0.9})
            face = 0 if side == 's' else 180      # the number faces the corridor
            signs.append(sign(str(num), [r3(dx + 0.85), r3(wy + (-0.2 if side == 's' else 0.2)), 1.7], face, 0.15))
    # the two rooms shown: a bathroom in the corner by the corridor, then bed, desk, chair, wardrobe
    for side, num in (('s', 101), ('n', 107)):
        sgn = 1 if side == 's' else -1           # +1: the south room (its outer wall at by)
        wy = cy0 if side == 's' else cy1
        outer = by if side == 's' else by + BLOCK_D
        bath_x = r3(bx + pitch - 2.3)
        bath_y = r3(wy - sgn * 2.0)
        walls += [{'a': [bath_x, wy], 'b': [bath_x, bath_y]}, {'a': [bath_x, bath_y], 'b': [r3(bx + pitch), bath_y]}]
        openings.append({'kind': 'door', 'at': [bath_x, r3(wy - sgn * 1.2)], 'width': 0.7})
        s += [st(f'block1_in_bath_door_{num}', 'door', [bath_x, r3(wy - sgn * 1.2), 0], 270, params={'width': 0.7}),
              st(f'block1_in_wc_{num}', 'sanitary', [r3(bx + pitch - 0.7), r3(wy - sgn * 0.05), 0], 180 if side == 's' else 0,
                 params={'kind': 'wc'}),
              st(f'block1_in_shower_{num}', 'sanitary', [r3(bx + pitch - 0.1), r3(wy - sgn * 1.1), 0], 270,
                 params={'kind': 'shower'}),
              st(f'block1_in_basin_{num}', 'sanitary', [r3(bath_x + 0.75), r3(bath_y + sgn * 0.05), 0], 0 if side == 's' else 180,
                 params={'kind': 'basin'}),
              st(f'block1_in_bed_{num}', 'bed', [r3(bx + 2.6), r3(outer + sgn * 0.7), 0], 90),
              st(f'block1_in_desk_{num}', 'desk', [r3(bx + 0.48), r3(outer + sgn * 2.4), 0], 270),
              st(f'block1_in_chair_{num}', 'chair', [r3(bx + 1.15), r3(outer + sgn * 2.4), 0], 270, params={'kind': 'office'}),
              st(f'block1_in_wardrobe_{num}', 'locker', [r3(bx + pitch - 3.2), r3(wy - sgn * 0.35), 0],
                 180 if side == 's' else 0, params={'width': 1.0})]
    s.insert(0, room('block1_in_rooms', (bx, by), 0, BLOCK_H - 0.05, walls, openings))   # up to the ceiling
    return area2('block1_in', 'Block 1', [[bx, by], [bx1, by + BLOCK_D]], CAMP_PACK, s, signs, 'inside')


def mess_inside():
    """The dining hall (21 tables of six) with its serving counter and hand basins at the door; the kitchen behind it
    (ranges and their hood, worktops, the washing-up sinks, shelves, the cold room's door)."""
    mx0, my0, mx1, my1 = MESS
    wall_y = -7.0
    s = [room('mess_in_walls', (mx0, my0), 0, MESS_H - 0.05, walls=[
        {'a': [mx0 + 0.15, wall_y], 'b': [mx1 - 0.15, wall_y]}, {'a': [-352, my0 + 0.15], 'b': [-352, -11]},
        {'a': [mx0 + 0.15, -11], 'b': [-352, -11]}],
        openings=[{'kind': 'door', 'at': [-324, wall_y], 'width': 1.0},
                  {'kind': 'door_closed', 'at': [-356, -11], 'width': 1.0, 'height': 2.0}]),
         st('mess_in_kitchen_door', 'door', [-324, wall_y, 0], 180),
         st('mess_in_serving', 'counter', [-340, -6.3, 0], 0, params={'kind': 'serving', 'length': 12}),
         st('mess_in_range', 'counter', [-340, -15.45, 0], 0, params={'kind': 'range', 'length': 4.0}),
         st('mess_in_worktop', 'counter', [-333.5, -15.45, 0], 0, params={'kind': 'kitchen', 'length': 4.0}),
         st('mess_in_sinks', 'counter', [-327, -15.45, 0], 0, params={'kind': 'sink', 'length': 3.6}),
         st('mess_in_island', 'counter', [-340, -11.0, 0], 0, params={'kind': 'kitchen', 'length': 5.0, 'depth': 1.0}),
         st('mess_in_shelf_1', 'shelf', [-320.35, -13.5, 0], 270, params={'length': 3.0}),
         st('mess_in_shelf_2', 'shelf', [-320.35, -9.5, 0], 270, params={'length': 2.4}),
         st('mess_in_basins', 'counter', [-347.5, 3.5, 0], 180, params={'kind': 'basin', 'length': 2.4, 'depth': 0.55})]
    k = 0
    for ty in (-3.2, -0.2, 2.6):
        for tx in range(7):
            x = -357.5 + 5.0 * tx
            if ty > 2 and abs(x - -347.5) < 1:
                continue   # the hand basins by the door stand there
            k += 1
            s.append(st(f'mess_in_table_{k}', 'table', [x, ty, 0], 90, params={'length': 1.8, 'width': 0.9}))
            for j, dx in enumerate((-0.6, 0.0, 0.6)):
                s += [st(f'mess_in_chair_{k}_s{j + 1}', 'chair', [r3(x + dx), r3(ty - 0.72), 0], 0),
                      st(f'mess_in_chair_{k}_n{j + 1}', 'chair', [r3(x + dx), r3(ty + 0.72), 0], 180)]
    signs = [sign('Kitchen', [-324, -7.25, 2.4], 0, 0.25), sign('Cold room', [-356, -11.25, 2.2], 0, 0.2),
             sign('Wash your hands', [-346, 3.65, 2.0], 180, 0.18)]
    return area2('mess_in', 'Mess hall and kitchen', [[mx0, my0], [mx1, my1]], CAMP_PACK, s, signs, 'inside')


def prayer_inside():
    """A carpeted hall; at the door a lobby with shoe racks and an ablution row."""
    px0, py0, px1, py1 = PRAYER
    s = [room('prayer_in_lobby_wall', (px0, py0), 0, AMENITY_H - 0.05, walls=[{'a': [px0 + 0.15, 29], 'b': [px1 - 0.15, 29]}],
              openings=[{'kind': 'door', 'at': [-308, 29], 'width': 1.6, 'height': 2.3}]),
         st('prayer_in_shoes_w', 'shelf', [-311.6, 28.75, 0], 180, params={'kind': 'shoes', 'length': 2.4, 'height': 1.0}),
         st('prayer_in_shoes_e', 'shelf', [-304.4, 28.75, 0], 180, params={'kind': 'shoes', 'length': 2.4, 'height': 1.0}),
         st('prayer_in_ablution', 'sanitary', [px0 + 0.15, 27.5, 0], 90, params={'kind': 'ablution'}),
         st('prayer_in_carpet', 'carpet', [px0 + 0.15, 29.1, 0], params={'outline': rect(r3(px1 - px0 - 0.3), r3(py1 - 29.1 - 0.15)),
                                                                         'colour': 'green'}),
         st('prayer_in_shelf', 'shelf', [-303.0, 35.6, 0], 180, params={'length': 1.2, 'height': 1.4})]
    signs = [sign('Please take off your shoes', [-308, 28.75, 2.4], 180, 0.18)]
    return area2('prayer_in', 'Prayer room', [[px0, py0], [px1, py1]], CAMP_PACK, s, signs, 'inside')


def gym_inside():
    gx0, gy0, gx1, gy1 = GYM
    s = [st('gym_in_rack', 'gym_rack', [gx0 + 0.5, 31, 0], 90, params={'kind': 'weights'}),
         st('gym_in_screen', 'screen', [-352, gy1 - 0.15, 0], 180, params={'size': 1.4, 'mount': 2.0})]
    for k, x in enumerate((-357, -355, -353)):
        s.append(st(f'gym_in_treadmill_{k + 1}', 'gym_rack', [x, 34.4, 0], 0, params={'kind': 'treadmill'}))
    for k, x in enumerate((-350.5, -348.8)):
        s.append(st(f'gym_in_bike_{k + 1}', 'gym_rack', [x, 34.6, 0], 0, params={'kind': 'bike'}))
    for k, x in enumerate((-356.5, -351.5)):
        s.append(st(f'gym_in_bench_{k + 1}', 'gym_rack', [x, 29.8, 0], 0, params={'kind': 'bench'}))
    s.append(st('gym_in_lockers', 'locker', [gx1 - 0.45, 30, 0], 270, params={'width': 2.0}))
    return area2('gym_in', 'Gym', [[gx0, gy0], [gx1, gy1]], CAMP_PACK, s, [], 'inside')


def rec_inside():
    rx0, ry0, rx1, ry1 = REC
    s = [st('rec_in_screen', 'screen', [-330, ry1 - 0.15, 0], 180, params={'size': 1.9, 'mount': 1.6})]
    for k, x in enumerate((-333.2, -326.8)):
        s.append(st(f'rec_in_sofa_{k + 1}', 'sofa', [x, 32.0, 0], 0, params={'seats': 3}))
    s.append(st('rec_in_sofa_3', 'sofa', [-336.6, 33.4, 0], 90, params={'seats': 2}))
    s.append(st('rec_in_coffee', 'table', [-330, 33.3, 0], 90, params={'length': 1.2, 'width': 0.6, 'height': 0.45}))
    for k, x in enumerate((-335, -325)):
        s.append(st(f'rec_in_table_{k + 1}', 'table', [x, 28.6, 0], 0, params={'length': 1.2, 'width': 0.9}))
        for j, (dx, dy, yaw) in enumerate(((-0.75, 0, 90), (0.75, 0, 270), (0, -0.9, 0), (0, 0.9, 180))):
            s.append(st(f'rec_in_chair_{k + 1}_{j + 1}', 'chair', [r3(x + dx), r3(28.6 + dy), 0], yaw))
    return area2('rec_in', 'Recreation room', [[rx0, ry0], [rx1, ry1]], CAMP_PACK, s, [], 'inside')


def laundry_inside():
    lx0, ly0, lx1, ly1 = LAUNDRY
    s = []
    for k in range(4):
        s.append(st(f'laundry_in_washer_{k + 1}', 'washer', [r3(-356.2 + 0.8 * k), 53.5, 0], 180, params={'kind': 'washer'}))
    for k in range(3):
        s.append(st(f'laundry_in_dryer_{k + 1}', 'washer', [-348.5, r3(52.6 - 0.8 * k), 0], 270, params={'kind': 'dryer'}))
    s += [st('laundry_in_table', 'table', [-353, 49.5, 0], 90, params={'length': 2.4, 'width': 1.0, 'height': 0.9}),
          st('laundry_in_shelf', 'shelf', [-352.5, 46.4, 0], 0, params={'length': 2.4})]
    return area2('laundry_in', 'Laundry', [[lx0, ly0], [lx1, ly1]], CAMP_PACK, s, [], 'inside')


def areas():
    return [gate(), admin(), road_west(), camp(), admin_inside(), workshop_inside(), block1_inside(), mess_inside(),
            prayer_inside(), gym_inside(), rec_inside(), laundry_inside()]


# ---------------------------------------------------------------- the first train's site (MILESTONES.md C1)

def control_planting():
    """What the control building's yard gains (it had no planting): date palms along the walkway from the plant
    gate, north of the building (the walkway's south: its shade), and low beds of saltbush and caper beside its door
    on the bare ground. The control area's bounds grow east and north to hold them (the yard between it and the
    turbine hall, paved as before)."""
    s = [box_road('ctl_walk', -40, 20.5, -6, 22, 'concrete'), box_road('ctl_walk_door', -8, 1.2, -6, 20.5, 'concrete')]
    s += [plant1(f'ctl_palm_{k + 1}', 'date_palm', [x, 18.6]) for k, x in enumerate((-37, -29, -21, -13))]
    s += [row('ctl_bed_n', 'saltbush', (-8.9, 2.2), (-8.9, 4.6)), row('ctl_bed_s', 'caper', (-8.9, -2.2), (-8.9, -3.6))]
    return s


CONTROL_BOUNDS = [[-40, -15], [-3, 22]]


def add_to_train(train):
    """The first train's areas with what C1 adds to them (the control building's planting, its yard's bounds)."""
    for a in train:
        if a['id'] == 'control':
            a['bounds'] = CONTROL_BOUNDS
            a['structures'] = a['structures'] + control_planting()
    return train


def tours():
    """The walk from the control room through the site to the camp (SITE.md §1: everything walkable is reached on
    foot from the control room, the camp too)."""
    from train_content import tour, k
    return [tour('camp_path', 'Tour: from the plant gate to the camp',
                 'Walk from the control building past the admin area and through the plant gate to the camp, where '
                 'the crews live, eat and rest off shift.',
                 [(['The gate house (', k('00UYE10'), '): everyone signs in and out here; the walkway beside the road is '
                    'shaded by date palms.'], ['00UYE10']),
                  (['The administration building (', k('00UYC10'), '): the permit office is on its ground floor.'],
                   ['00UYC10']),
                  (['The workshops (', k('00UST10'), '): I&C with its calibration bench, mechanical, electrical.'],
                   ['00UST10']),
                  (['Accommodation block 1 (', k('00UZW11'), '): single rooms off a central corridor, each with its '
                    'own bathroom.'], ['00UZW11']),
                  (['The laundry (', k('00UZW32'), ').'], ['00UZW32']),
                  (['The gym (', k('00UZW31'), ') and the recreation room (', k('00UZW33'), ').'],
                   ['00UZW31', '00UZW33']),
                  (['The prayer room (', k('00UZW30'), '): shoes off and the ablution area at its door.'], ['00UZW30']),
                  (['The mess hall (', k('00UZW20'), '): its kitchen is behind the serving counter; its court is shaded '
                    'by palms.'], ['00UZW20']),
                  (['The camp office and first aid (', k('00UZW40'), '), by the camp gate.'], ['00UZW40'])])]
