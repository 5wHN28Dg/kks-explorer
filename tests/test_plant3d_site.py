"""Walkdown Plant's site and camp (docs/plant3d/SITE.md, milestone C1 of docs/plant3d/MILESTONES.md):
- the validator's format 2 bits this milestone uses: version 2 areas in a version 2 plant, interiors (`"load":
  "inside"`, PLANT3D.md §18.5) held by one area, routes and partitions inside their area;
- the planting suits a desert plant site in southern Iraq and every plant has a purpose (SITE.md §4): palms shade
  walkways, courts and entrances, tamarisk is the windbreak on the north and west, oleander keeps the roads' dust off
  and is never by the mess hall, bougainvillea grows on porch and walkway posts, saltbush and caper by doors; no lawn,
  nothing planted in the process areas;
- the camp and the road to it are fenced (the country beyond is not walkable), the interiors stand in their buildings
  and hold only what the app can show without new pipelines (the kit's site parts and doors)."""
import json, math, os, re, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))
from ref import plant3d as P
import kit as K
import site_areas

DATA = os.path.join(ROOT, 'data', 'plant3d')
VECTORS = os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v1.json')
PARTS_SITE = os.path.join(ROOT, 'apps', 'plant3d', 'kit', 'parts_site.gd')
PROCESS_PACKS = ('base', 'wtp')


def species_spacing():
    """The species' usual spacing in a row, from the kit itself (kit/parts_site.gd SPECIES)."""
    with open(PARTS_SITE, encoding='utf-8') as f:
        src = f.read()
    return {m.group(1): float(m.group(2)) for m in re.finditer(r'"(\w+)": \{"height": [0-9.]+, "spacing": ([0-9.]+)', src)}


def rot(v, yaw):
    r = math.radians(yaw)
    return (v[0] * math.cos(r) + v[1] * math.sin(r), -v[0] * math.sin(r) + v[1] * math.cos(r))


def plants(area, spacing):
    """Every plant of an area's planting structures: (species, x, y, structure id), rows walked as the builder does
    (apps/plant3d/builder/kit_place.gd planting_places)."""
    out = []
    for s in area['structures']:
        if s['part'] != 'planting':
            continue
        p = s['params']
        sp = p.get('spacing', 0) or spacing[p['species']]
        at, yaw = s['at'], s.get('yaw', 0)
        route = p.get('route', [[0, 0, 0], [0, 0, 0]])
        pts = [(at[0] + rot(q, yaw)[0], at[1] + rot(q, yaw)[1]) for q in route]
        carry = 0.0
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            L = math.dist(a, b)
            if L < 1e-6 and i > 0:
                continue
            t = carry
            while t <= L + 1e-6:
                f = t / L if L > 1e-6 else 0.0
                out.append((p['species'], a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, s['id']))
                t += sp
            carry = t - L
    return out


def rect_of(s):
    """A structure's plan rectangle (its outline turned and placed), or None."""
    o = s.get('params', {}).get('outline')
    if not o:
        return None
    pts = [(s['at'][0] + rot(q, s.get('yaw', 0))[0], s['at'][1] + rot(q, s.get('yaw', 0))[1]) for q in o]
    return (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))


def dist_rect(p, r):
    dx = max(r[0] - p[0], 0, p[0] - r[2])
    dy = max(r[1] - p[1], 0, p[1] - r[3])
    return math.hypot(dx, dy)


def seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    L2 = ax * ax + ay * ay
    t = 0 if L2 == 0 else max(0, min(1, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / L2))
    return math.dist(p, (a[0] + ax * t, a[1] + ay * t))


class Format(unittest.TestCase):
    """Format 2's area bits (PLANT3D.md §14, §18.5) in the validator, on the vectors' small plant."""

    @classmethod
    def setUpClass(cls):
        with open(VECTORS, encoding='utf-8') as f:
            v = json.load(f)
        cls.files = {k: t.encode() for k, t in v['valid'][0]['files'].items()}
        with open(os.path.join(DATA, 'kit.json'), encoding='utf-8') as f:
            now = json.load(f)['parts']
        kit = json.loads(cls.files['kit.json'])
        for part in ('table', 'room', 'planting', 'door', 'fence', 'slab'):
            kit['parts'][part] = now[part]
        cls.files['kit.json'] = json.dumps(kit).encode()

    def with_interior(self, plant_version=2, area_version=2, bounds=((5, 5), (15, 15)), **extra):
        files = dict(self.files)
        pl = json.loads(files['plant.json'])
        pl['version'] = plant_version
        pl['areas'] = pl['areas'] + ['in1']
        files['plant.json'] = json.dumps(pl).encode()
        a = {'format': 'walkdown-plant-area', 'version': area_version, 'id': 'in1', 'title': 'Inside', 'bounds': bounds,
             'pack': 'base', 'equipment': [], 'pipes': [],
             'structures': [{'id': 'in1_table', 'part': 'table', 'at': [bounds[0][0] + 1, bounds[0][1] + 1, 0]}],
             'signs': [], 'load': 'inside'}
        a.update(extra)
        files['areas/in1.json'] = json.dumps(a).encode()
        return files

    def code(self, files):
        with self.assertRaises(P.FormatError) as cm:
            P.check_files(files)
        return cm.exception.code

    def test_an_interior_inside_its_area_is_valid(self):
        P.check_files(self.with_interior())

    def test_an_interior_needs_a_version_2_plant_and_area(self):
        self.assertEqual(self.code(self.with_interior(plant_version=1)), 'bad_version')
        self.assertEqual(self.code(self.with_interior(area_version=1)), 'unknown_key')

    def test_an_interior_lies_inside_one_area(self):
        # across two areas, or out in the open, or overlapping an area it is not inside
        self.assertEqual(self.code(self.with_interior(bounds=((35, 5), (55, 15)))), 'area_overlap')
        self.assertEqual(self.code(self.with_interior(bounds=((-5, 5), (5, 15)))), 'area_overlap')
        # on ground of no area at all
        self.assertEqual(self.code(self.with_interior(bounds=((100, 100), (110, 110)))), 'area_overlap')

    def test_an_interior_holds_only_the_kits_site_parts_and_doors(self):
        slab = {'id': 'in1_slab', 'part': 'slab', 'at': [8, 8, 0], 'params': {'outline': [[0, 0], [1, 0], [1, 1]]}}
        files = self.with_interior()
        a = json.loads(files['areas/in1.json'])
        a['structures'].append(slab)
        files['areas/in1.json'] = json.dumps(a).encode()
        self.assertEqual(self.code(files), 'bad_kind')

    def test_an_interior_holds_no_equipment(self):
        eq = [{'kks': '10LAC90AP001', 'name': 'A pump', 'part': 'pump_horizontal', 'at': [8, 8, 0]}]
        self.assertEqual(self.code(self.with_interior(equipment=eq)), 'bad_kind')

    def test_load_is_inside_or_nothing(self):
        self.assertEqual(self.code(self.with_interior(load='later')), 'bad_value')

    def test_routes_and_partitions_stay_in_their_area(self):
        def area_with(s):
            files = dict(self.files)
            name = 'areas/a1.json'
            a = json.loads(files[name])
            a['structures'] = a['structures'] + [s]
            files[name] = json.dumps(a).encode()
            return files
        row = {'id': 'r1', 'part': 'planting', 'at': [1, 1, 0],
               'params': {'species': 'tamarisk', 'route': [[0, 0, 0], [60, 0, 0]]}}
        self.assertEqual(self.code(area_with(row)), 'outside_area')
        row['params']['route'] = [[0, 0, 0], [30, 0, 0]]
        P.check_files(area_with(row))
        room = {'id': 'partition_1', 'part': 'room', 'at': [1, 1, 0], 'params': {
            'walls': [{'a': [0, 0], 'b': [0, 45]}], 'openings': [{'kind': 'door', 'at': [0, 1]}]}}
        self.assertEqual(self.code(area_with(room)), 'outside_area')


class Site(unittest.TestCase):
    """The site and the camp as content (data/plant3d, made by tools/plant3d/site_areas.py)."""

    @classmethod
    def setUpClass(cls):
        cls.b = P.check_dir(DATA)
        cls.areas = {a['id']: a for a in cls.b.areas}
        cls.spacing = species_spacing()
        cls.plants = [(a['id'],) + p for a in cls.b.areas for p in plants(a, cls.spacing)]

    def in_area(self, x, y, a):
        (x0, y0), (x1, y1) = a['bounds']
        return x0 <= x <= x1 and y0 <= y <= y1

    def test_the_kit_knows_each_species_spacing(self):
        self.assertEqual(sorted(self.spacing), sorted(K.SPECIES))

    def test_the_milestones_areas_are_there(self):
        for aid in ('gate', 'admin', 'road_west', 'camp', 'block1_in', 'mess_in', 'prayer_in', 'gym_in', 'laundry_in',
                    'rec_in', 'admin_in', 'workshop_in'):
            self.assertIn(aid, self.areas)
        self.assertEqual(sum(1 for a in self.b.areas if a.get('load') == 'inside'), 8)

    def test_nothing_is_planted_in_the_process_areas(self):
        """SITE.md §4: the train, the WTP and the transformer yard are gravel and concrete only (fire safety, access,
        drainage); nothing near the cooling tower's drift or the switchyard either. The control building's yard is
        not a process area (C1: palms on its walkway, shrubs by its door)."""
        for aid, sp, x, y, sid in self.plants:
            a = self.areas[aid]
            self.assertTrue(a['pack'] not in PROCESS_PACKS or aid == 'control', f'{sid}: planted in the process area {aid}')
            for other in self.b.areas:
                if other['pack'] in PROCESS_PACKS and other['id'] != 'control':
                    self.assertFalse(self.in_area(x, y, other), f'{sid} ({sp}) stands in the process area {other["id"]}')
            for far, d in (('ct', 30.0), ('trafo1', 10.0)):
                if far in self.areas:
                    (x0, y0), (x1, y1) = self.areas[far]['bounds']
                    self.assertGreater(dist_rect((x, y), (x0, y0, x1, y1)), d, f'{sid} is within {d} m of {far}')

    def test_no_lawn_only_the_regions_species(self):
        self.assertEqual({p[1] for p in self.plants}, set(K.SPECIES))
        self.assertEqual(set(K.SPECIES), {'date_palm', 'tamarisk', 'oleander', 'bougainvillea', 'saltbush', 'caper',
                                          'dracaena'})

    def roads(self, surfaces=('asphalt', 'concrete', 'gravel', 'pavers')):
        out = []
        for a in self.b.areas:
            for s in a['structures']:
                if s['part'] == 'road' and s['params'].get('surface', 'asphalt') in surfaces:
                    out.append(rect_of(s))
        return out

    def doors(self):
        # doors of buildings and rooms, and a guard booth's (part of its kit part)
        return [(s['at'][0], s['at'][1]) for a in self.b.areas for s in a['structures']
                if s['part'] in ('door', 'guard_booth')]

    def test_every_plant_has_a_purpose(self):
        """SITE.md §4, each species where its purpose is."""
        paved = self.roads(('concrete', 'pavers'))   # walkways, the forecourt, the mess hall's court
        asphalt = self.roads(('asphalt',))
        parking = [rect_of(s) for a in self.b.areas for s in a['structures']
                   if s['part'] == 'road' and s.get('kks', '').startswith('00UZD')]
        self.assertEqual(len(parking), 2)
        doors = self.doors()
        buildings = [rect_of(s) for a in self.b.areas for s in a['structures'] if s['part'] == 'building']
        fences = []
        for a in self.b.areas:
            for s in a['structures']:
                if s['part'] in ('fence', 'wall'):
                    pts = [(s['at'][0] + q[0], s['at'][1] + q[1]) for q in s['params']['route']]
                    fences += list(zip(pts, pts[1:]))
        posts = []   # porches' and canopies' post lines
        for a in self.b.areas:
            for s in a['structures']:
                if s['part'] in ('porch', 'canopy'):
                    posts.append(s)
        inside = {a['id'] for a in self.b.areas if a.get('load') == 'inside'}
        outside_doors = [(s['at'][0], s['at'][1]) for a in self.b.areas if a['id'] not in inside
                         for s in a['structures'] if s['part'] == 'door']
        for aid, sp, x, y, sid in self.plants:
            p = (x, y)
            with self.subTest(plant=sid, species=sp, at=(round(x, 1), round(y, 1))):
                # pot plants only indoors, every other species only outdoors
                self.assertEqual(sp == 'dracaena', aid in inside, 'a pot plant indoors, the rest outdoors')
                if sp == 'dracaena':
                    # the entrance's landscape: in a lobby, within 12 m of the building's outside door
                    self.assertTrue(any(math.dist(p, d) <= 12.0 for d in outside_doors), 'a pot plant stands by an entrance')
                elif sp == 'date_palm':
                    # beside an east-west walkway, on its south side: the sun is in the south (SITE.md §4)
                    for r in paved:
                        ew = r[2] - r[0] > 3 * (r[3] - r[1])
                        if ew and r[0] <= p[0] <= r[2] and 0 < dist_rect(p, r) <= 3.0:
                            self.assertLess(p[1], r[1], 'a palm beside an east-west walkway stands on its sunny (south) side')
                    # shade on a walkway, a court, a forecourt or an entrance people use
                    self.assertTrue(any(dist_rect(p, r) <= 3.0 for r in paved + parking) or
                                    any(math.dist(p, d) <= 12 for d in doors),
                                    'a palm shades a walkway, a court, a parking or an entrance')
                elif sp == 'tamarisk':
                    # the windbreak: along a fence on the north or west (the shamal's side)
                    near = [f for f in fences if seg_dist(p, *f) <= 6.5]
                    self.assertTrue(near, 'a tamarisk stands in a windbreak along a fence')
                    self.assertTrue(any(abs(f[0][0] - f[1][0]) < 0.01 and f[0][0] < x or
                                        abs(f[0][1] - f[1][1]) < 0.01 and f[0][1] > y for f in near),
                                    'on the fence\'s north or west side')
                elif sp == 'oleander':
                    # dust off a road, or the screen between the parking and the blocks
                    self.assertTrue(any(dist_rect(p, r) <= 7.0 for r in asphalt), 'an oleander hedge follows a road')
                elif sp == 'bougainvillea':
                    self.assertTrue(any(self.near_post(p, s) for s in posts), 'a bougainvillea grows on a porch or walkway post')
                else:
                    # low beds on the bare ground by a door or along a building's front
                    self.assertTrue(any(math.dist(p, d) <= 5.0 for d in doors) or any(dist_rect(p, r) <= 2.0 for r in buildings),
                                    f'{sp} holds the bare ground by a door or a building')

    @staticmethod
    def near_post(p, s):
        """Within 0.6 m of a post of the porch or canopy (kit/parts_site.gd: posts along both long sides)."""
        prm = s['params']
        yaw = s.get('yaw', 0)
        if s['part'] == 'porch':
            L, d = prm['length'], prm['depth']
            n = math.ceil(L / 3.2)
            pts = [(-L / 2 + 0.1 + (L - 0.2) * i / n, d - 0.1) for i in range(n + 1)]
        else:
            L, w = prm['length'], prm['width']
            n = max(1, math.ceil(L / 5.5))
            pts = [(sx * (w / 2 - 0.15), -L / 2 + L * i / n) for i in range(n + 1) for sx in (-1, 1)]
        for q in pts:
            r = rot((q[0], q[1]), yaw)
            if math.dist(p, (s['at'][0] + r[0], s['at'][1] + r[1])) <= 0.6:
                return True
        return False

    def test_oleander_is_never_by_the_mess_hall_or_food(self):
        """Oleander is poisonous (SITE.md §4): none within 15 m of the mess hall, its kitchen or its court."""
        food = [rect_of(s) for s in self.areas['camp']['structures'] if s['id'] in ('camp_mess', 'camp_court')]
        self.assertEqual(len(food), 2)
        for aid, sp, x, y, sid in self.plants:
            if sp == 'oleander':
                for r in food:
                    self.assertGreater(dist_rect((x, y), r), 15.0, f'{sid} is by the mess hall or its court')

    def test_the_c1_planting_of_the_first_train_and_the_admin_area(self):
        """MILESTONES.md C1: palms shading the walkway from the plant gate to the control building and the admin
        parking, low shrubs by the control building's door (the windbreak along the wall is the builder's: its test is
        apps/plant3d/tests/test_site.gd)."""
        ctl = [p for p in self.plants if p[0] == 'control']
        self.assertGreaterEqual(sum(1 for p in ctl if p[1] == 'date_palm'), 4)
        door = next(s['at'] for s in self.areas['control']['structures'] if s['id'] == 'ctl_door')
        shrubs = [p for p in ctl if p[1] in ('saltbush', 'caper')]
        self.assertGreaterEqual(len(shrubs), 4)
        self.assertTrue(all(math.dist((p[2], p[3]), door[:2]) < 6 for p in shrubs))
        gate_palms = [p for p in self.plants if p[0] == 'gate' and p[1] == 'date_palm']
        self.assertGreaterEqual(len(gate_palms), 6)
        parking = rect_of(next(s for s in self.areas['admin']['structures'] if s['id'] == 'admin_parking'))
        self.assertGreaterEqual(sum(1 for p in self.plants if p[1] == 'date_palm' and dist_rect((p[2], p[3]), parking) < 8), 4)

    def test_the_camp_and_its_road_are_walled(self):
        """The country beyond the wall has no ground to walk on: the camp's wall goes all round it, open only where
        the road comes in between the road's own walls, which run to the boundary wall."""
        def fence_pts(a, sid):
            s = next(x for x in self.areas[a]['structures'] if x['id'] == sid)
            return [(s['at'][0] + q[0], s['at'][1] + q[1]) for q in s['params']['route']]
        camp = fence_pts('camp', 'camp_wall')
        (x0, y0), (x1, y1) = self.areas['camp']['bounds']
        self.assertEqual(camp[0], (x1, 10.5))
        self.assertEqual(camp[-1], (x1, 29.5))
        for a, b in zip(camp, camp[1:]):
            self.assertTrue(abs(a[0] - b[0]) < 1e-9 or abs(a[1] - b[1]) < 1e-9)
        for sid, y in (('rw_wall_s', 10.5), ('rw_wall_n', 29.5)):
            pts = fence_pts('road_west', sid)
            self.assertEqual({p[1] for p in pts}, {y})
            self.assertEqual(sorted(p[0] for p in pts), [x1, site_areas.WALL_X])

    def test_interiors_stand_in_their_buildings(self):
        """§18.5: each interior's bounds are its building's outline in the area holding it, it holds only the kit's
        site parts and doors (drawn without new pipelines, apps/plant3d/builder/kit_place.gd `unbaked`), and its
        building has a door that opens."""
        site_parts = set(K.SITE_PARTS)
        for a in self.b.areas:
            if a.get('load') != 'inside':
                continue
            with self.subTest(interior=a['id']):
                holders = [h for h in self.b.areas if h is not a and h.get('load') is None and
                           self.in_area(*a['bounds'][0], h) and self.in_area(*a['bounds'][1], h)]
                self.assertEqual(len(holders), 1)
                h = holders[0]
                (x0, y0), (x1, y1) = a['bounds']
                blds = [s for s in h['structures'] if s['part'] == 'building' and rect_of(s) == (x0, y0, x1, y1)]
                self.assertEqual(len(blds), 1, 'its bounds are its building')
                self.assertTrue(any(o['kind'] == 'door' for o in blds[0]['params']['openings']), 'its building opens')
                for s in a['structures']:
                    self.assertTrue(s['part'] in site_parts or s['part'] == 'door', f'{s["id"]}: {s["part"]}')

    def test_doors_are_clear(self):
        """Nothing solid stands in a doorway: no furniture, vehicle or fitting within 0.8 m of a door (a shelf once
        stood 5 cm behind the workshops' south door)."""
        clear_of = set(K.SITE_PARTS) - {'planting', 'kerb', 'room', 'carpet', 'crossing', 'porch', 'canopy', 'court'}
        doors = [(s['id'], s['at']) for a in self.b.areas for s in a['structures'] if s['part'] == 'door']
        for a in self.b.areas:
            for s in a['structures']:
                if s['part'] in clear_of:
                    for did, d in doors:
                        if abs(d[2] - s['at'][2]) < 1.0:
                            self.assertGreater(math.dist(d[:2], s['at'][:2]), 0.8, f'{s["id"]} stands in the doorway of {did}')

    def test_the_site_buildings_have_their_codes(self):
        """SITE.md §6: the administration building, workshops, store, gate house and the camp's buildings by the
        public key's U letters."""
        want = {'00UYC10', '00UST10', '00USU10', '00UYE10', '00UZW20', '00UZW30', '00UZW31', '00UZW32', '00UZW33',
                '00UZW40'} | {f'00UZW1{n}' for n in range(1, 9)}
        have = {s.get('kks') for a in self.b.areas for s in a['structures'] if s['part'] == 'building'}
        self.assertLessEqual(want, have)


if __name__ == '__main__':
    unittest.main()
