## The site round the areas (R9: a plant stands on paved yards between roads, inside a boundary wall, in open
## country; the bare gravel plane to the horizon was the most artificial thing in every view). Made by the build from
## the areas' bounds, the same for every plant description, nothing a trainee operates:
##   - the areas' yards paved in concrete (their bounds), gravel between them; an area that lays its own roads
##     (the site's and the camp's, SITE.md) is compacted gravel between them, its roads cut out of it;
##   - a ring road round the process areas (asphalt, kerbs, a covered drain along its inner edge);
##   - a precast concrete boundary wall with pilasters and a closed gate, round the process areas and the ring road
##     and joined with the `site` pack's areas (the admin building and the plant gate: their outer edge is the wall's
##     line), open where a road of an area crosses it (the plant gate);
##   - the windbreak (SITE.md §4, MILESTONES.md C1): two staggered rows of tamarisk along the inside of the wall's north
##     and west sides, against the dust-laden north-westerly wind (the shamal), clear of the roads and the areas;
##   - outside the wall, the `camp` pack's areas (the camp and the road to it) on their own flat ground; the country
##     beyond: a terrain to the far plane, flat near the wall and the camp, rising to low hills;
##   - with a river intake (an area `intake`, docs/plant3d/SITE.md §1): the river along the wall's east side, beyond
##     a strip of bank, its water at RIVER_LEVEL, and the headwall where the intake's channel (its pits) opens on
##     the river under the road and the wall.
## The walkable ground (z = 0 inside the wall) keeps its collision as before; kerbs and drains are drawn only (a
## walker steps over them). Everything here is static and baked into the lightmap.
extends RefCounted

const Geom = preload("res://builder/geom.gd")
const Lightmap = preload("res://builder/lightmap.gd")

const ROAD_GAP := 6.0      # from the areas' bounds to the road's inner edge
const ROAD_W := 7.0
const WALL_GAP := 12.0     # from the road's outer edge to the wall
const WALL_H := 2.6
const KERB_H := 0.12
const FAR := 760.0         # the terrain's reach from the plant's centre (the walker's far plane is 800 m)
const TERRAIN_CELL := 20.0
const RIVER_GAP := 5.0     # the bank: from the wall's east side to the river's edge
const RIVER_W := 90.0
const RIVER_LEVEL := -1.5  # the water (WATER-TREATMENT.md: the intake's wet well stands at the river's level)
const RIVER_BED := -4.0
const RIVER_SLOPE := 10.0  # the banks go down to the bed over this width

var b   # the plant builder
var river := false

func _init(builder) -> void:
	b = builder

static func grow(r: Rect2, d: float) -> Rect2:
	return r.grow(d)

static func poly_of(r: Rect2) -> PackedVector2Array:
	return Geom.rect(r.position.x, r.position.y, r.end.x, r.end.y)

## Packs whose areas are not the process plant: the site's (inside the wall, to its line) and the camp's (outside).
const SITE_PACK := "site"
const CAMP_PACK := "camp"

static func _rect(bd: Array) -> Rect2:
	return Rect2(Vector2(bd[0][0], bd[0][1]), Vector2(bd[1][0] - bd[0][0], bd[1][1] - bd[0][1]))

## An interior (PLANT3D.md §18.5) lies in the area holding its building: it has no ground of its own.
static func interior(a: Dictionary) -> bool:
	return a.data.get("load", "") == "inside"

## The extent of the process areas as a Rect2 (plant coordinates): what the ring road goes round.
func extent() -> Rect2:
	var r := Rect2()
	var any := false
	for a in b.areas:
		if interior(a) or a.data.get("pack", "") in [SITE_PACK, CAMP_PACK]:
			continue
		var ar := _rect(a.data.bounds)
		r = ar if not any else r.merge(ar)
		any = true
	if not any:
		var ex: Array = b._extent()
		return _rect(ex)
	return r

## The wall's line: the walkable ground inside it ends there. The process areas with the ring road and a verge, and
## the site's areas (the admin building and the gate stand inside the wall to its line).
func wall_rect() -> Rect2:
	var r := extent().grow(ROAD_GAP + ROAD_W + WALL_GAP)
	for a in b.areas:
		if not interior(a) and a.data.get("pack", "") == SITE_PACK:
			r = r.merge(_rect(a.data.bounds))
	return r

## Flat ground outside the wall: the camp's areas (the camp, the road to it). Rects in plant coordinates.
func camp_rects() -> Array:
	var out: Array = []
	for a in b.areas:
		if not interior(a) and a.data.get("pack", "") == CAMP_PACK:
			out.append(_rect(a.data.bounds))
	return out

## The roads the content lays at ground level (walkable `road` surfaces at z = 0): cut out of the yards and the ground.
func roads() -> Array:
	return b.surfaces.filter(func(sf): return sf.kind == "road" and absf(float(sf.z)) < 0.01)

func make(root: Node3D, holes: Array) -> void:
	var E := extent()
	var road_in := E.grow(ROAD_GAP)
	var road_out := road_in.grow(ROAD_W)
	var wall := wall_rect()
	var pads: Array = []
	var paved: Array = []   # an area with a building is paved in concrete, an open one (an HRSG, a transformer yard) gravelled
	var site_yard: Array = []   # the site's and the camp's (a coarser lightmap texel: builder texel_scale)
	for a in b.areas:
		if interior(a):
			continue
		var bd: Array = a.data.bounds
		pads.append(_rect(bd))
		var sts: Array = a.data.get("structures", [])
		# the site's and the camp's areas lay their own roads and walkways: compacted gravel between them
		paved.append(sts.any(func(s): return s.get("part", "") == "building") and not a.data.get("pack", "") in [SITE_PACK, CAMP_PACK])
		site_yard.append(a.data.get("pack", "") in [SITE_PACK, CAMP_PACK])
	holes = holes.duplicate()
	for sf in roads():
		holes.append(sf.outline)
	# gravel between the yards, inside the ring road and its drain
	var drain_in := road_in.grow(-0.4)
	var gh: Array = []
	for h in holes:
		if drain_in.encloses(_bbox(h)):
			gh.append(h)
	for p in pads:
		if drain_in.encloses(p):
			gh.append(poly_of(p))
	b._slab(root, "ground", poly_of(drain_in), gh, 0.0, 0.5, b._mat("ground"), Lightmap.GROUND_TEXEL)
	# the yards: concrete, less pits and stairwells
	var i := 0
	for p in pads:
		var ph: Array = []
		for h in holes:
			if p.grow(0.01).encloses(_bbox(h)):
				ph.append(h)
		b.texel_scale = b.SITE_TEXEL_SCALE if site_yard[i] else 1.0
		b._slab(root, "yard_%d" % i, poly_of(p), ph, 0.0, 0.5, b._mat("yard" if paved[i] else "yard_gravel"), Lightmap.GROUND_TEXEL)
		b.texel_scale = 1.0
		i += 1
	# the ring road, and gravel from it to the wall (less the yards of the site's areas there)
	b._slab(root, "road", poly_of(road_out), [poly_of(road_in)], 0.0, 0.5, b._mat("road"), Lightmap.GROUND_TEXEL)
	var vh: Array = [poly_of(road_out)]
	for p in pads:
		if wall.encloses(p) and not road_out.intersects(p):
			vh.append(poly_of(p))
	b._slab(root, "verge", poly_of(wall), vh, 0.0, 0.5, b._mat("ground"), Lightmap.GROUND_TEXEL)
	_kerbs_and_drain(root, road_in, road_out, drain_in)
	_wall(root, wall)
	_windbreak(root, wall, road_out)
	_terrain(root, wall)
	if has_river():
		_river(root, wall)

## A river intake in the plant: an area `intake` (SITE.md §1). The river then runs along the wall's east side.
func has_river() -> bool:
	return b.areas.any(func(a): return a.id == "intake")

## The river's plan strip: x from its west edge to its east edge (the wall's east side + RIVER_GAP).
func river_x(wall: Rect2) -> Vector2:
	return Vector2(wall.end.x + RIVER_GAP, wall.end.x + RIVER_GAP + RIVER_W)

## The river's water from one end of the terrain to the other (its banks are the terrain's: _height), and the intake
## channel's headwall on the west bank, its opening dark, level with the intake's pits.
func _river(root: Node3D, wall: Rect2) -> void:
	var rx := river_x(wall)
	var c := wall.get_center()
	var st: SurfaceTool = b._st()
	# as far north and south as the terrain reaches at the river (its edge is a circle of FAR round the centre)
	var dx := maxf(absf(rx.x - c.x), absf(rx.y - c.x))
	var half := sqrt(maxf(FAR * FAR - dx * dx, 0.0))
	Geom.add_prism(st, Geom.rect(rx.x, c.y - half, rx.y, c.y + half), RIVER_LEVEL - 0.05, RIVER_LEVEL, false, false)
	b._mesh_node(root, "river", st, b._mat("water_river"), 8.0)
	var lo := INF
	var hi := -INF
	for p in b.pits:
		if p.area == "intake":
			for q: Vector2 in p.outline:
				lo = minf(lo, q.y)
				hi = maxf(hi, q.y)
	if lo < hi:
		var hw: SurfaceTool = b._st()
		# out into the water past the bank's foot (the terrain reaches the water's level about 2.5 m into the river)
		Geom.add_prism(hw, Geom.rect(rx.x - 2.0, lo - 1.5, rx.x + 3.5, hi + 1.5), RIVER_BED, 0.4)
		b._mesh_node(root, "intake_headwall", hw, b._mat("concrete"), Lightmap.TEXEL)
		var dark: SurfaceTool = b._st()
		Geom.add_prism(dark, Geom.rect(rx.x + 3.5, lo, rx.x + 3.52, hi), RIVER_BED + 0.5, RIVER_LEVEL + 0.6)
		b._mesh_node(root, "intake_opening", dark, b._mat("drain"))

static func _bbox(pg: PackedVector2Array) -> Rect2:
	var r := Rect2(pg[0], Vector2.ZERO)
	for q in pg:
		r = r.expand(q)
	return r

## Kerbs along both edges of the road (drawn only: a walker steps over 12 cm), and a drain channel with a grating
## cover in the gravel along the road's inner edge (the cover is walkable).
func _kerbs_and_drain(root: Node3D, road_in: Rect2, road_out: Rect2, drain_in: Rect2) -> void:
	var kerb: SurfaceTool = b._st()
	for ring in [[road_in.grow(0.15), road_in], [road_out, road_out.grow(-0.15)]]:
		for pc in Geom.decompose(poly_of(ring[0]), [poly_of(ring[1])]):
			_striped(kerb, pc)
	b._mesh_node(root, "kerbs", kerb, b._mat("paint"), Lightmap.GROUND_TEXEL)
	var dark: SurfaceTool = b._st()
	for pc in Geom.decompose(poly_of(road_in), [poly_of(drain_in)]):
		Geom.add_prism(dark, pc, -0.25, -0.2, false)
	b._mesh_node(root, "drain", dark, b._mat("drain"))
	b._slab(root, "drain_cover", poly_of(road_in), [poly_of(drain_in)], 0.0, 0.03, b._mat("grating"), Lightmap.TEXEL)

## The kerbs are painted in alternate black and yellow stripes KERB_STRIPE long (the paint's colours in the
## vertices: one draw call): a kerb piece (a rectangle) cut along its length.
const KERB_STRIPE := 1.0
const KERB_YELLOW := Color(0.92, 0.70, 0.08, 0.3)
const KERB_BLACK := Color(0.07, 0.07, 0.07, 0.3)
func _striped(st: SurfaceTool, pc: PackedVector2Array) -> void:
	var r := _bbox(pc)
	var along_x := r.size.x >= r.size.y
	var L := r.size.x if along_x else r.size.y
	var n := maxi(1, int(round(L / KERB_STRIPE)))
	for k in n:
		var t0 := L * k / n
		var t1 := L * (k + 1) / n
		var q := Rect2(r.position + (Vector2(t0, 0) if along_x else Vector2(0, t0)),
			Vector2(t1 - t0, r.size.y) if along_x else Vector2(r.size.x, t1 - t0))
		st.set_color(KERB_YELLOW if k % 2 == 0 else KERB_BLACK)
		Geom.add_prism(st, poly_of(q), 0.0, KERB_H)

static func _ccw(a: Vector2, c: Vector2, d: Vector2) -> bool:
	return (c - a).cross(d - a) > 0.0

## The boundary wall: precast panels between pilasters every 6 m, and a closed sliding gate on the south side; open
## where a road the content lays at ground level crosses its line (the plant gate), a pilaster on each side.
func _wall(root: Node3D, r: Rect2) -> void:
	var body: StaticBody3D = b._body(root, "boundary_wall")
	var st: SurfaceTool = b._st()
	var gate: SurfaceTool = b._st()
	var pg := poly_of(r)
	var gate_c := Vector2(r.get_center().x, r.position.y)   # the south side's middle
	for j in pg.size():
		var a2: Vector2 = pg[j]
		var c2: Vector2 = pg[(j + 1) % pg.size()]
		var L := a2.distance_to(c2)
		var d := (c2 - a2) / L
		var pieces: Array = []   # [t0, t1] of wall between the roads' gaps
		var t := 0.0
		for cut in road_cuts(a2, c2):
			if cut[0] > t:
				pieces.append([t, cut[0]])
			t = maxf(t, cut[1])
		if t < L:
			pieces.append([t, L])
		for pc in pieces:
			var t0: float = pc[0]
			var t1: float = pc[1]
			var n := int(ceil((t1 - t0) / 6.0 - 1e-6))
			for k in n:
				var p0 := a2 + d * (t0 + (t1 - t0) * k / n)
				var p1 := a2 + d * (t0 + (t1 - t0) * (k + 1) / n)
				var mid := (p0 + p1) * 0.5
				var is_gate := mid.distance_to(gate_c) < 4.5
				if is_gate:
					b._wall_panel(gate, body, p0, p1, 0.0, WALL_H - 0.4, 0.08)
				else:
					b._wall_panel(st, body, p0, p1, 0.0, WALL_H, 0.2)
				_pilaster(st, p0)
			if t1 < L - 1e-3:
				_pilaster(st, a2 + d * t1)   # the gate post on the far side of a gap
	b._mesh_node(body, "panels", st, b._mat("wall_concrete"), Lightmap.GROUND_TEXEL)
	b._mesh_node(body, "gate", gate, b._mat("fence"), Lightmap.SHEET_TEXEL)   # a thin sheet: a fine texel

func _pilaster(st: SurfaceTool, p: Vector2) -> void:
	var pc := Geom.rect(p.x - 0.2, p.y - 0.2, p.x + 0.2, p.y + 0.2)
	st.set_color(b.top_colour(WALL_H + 0.15))   # its own top (it stands higher than the panels: review)
	Geom.add_prism(st, pc, 0.0, WALL_H + 0.15)

## Where content roads at ground level cross the wall's side from a to c: [[t0, t1], …] along it (metres from a),
## sorted and merged: a road whose outline reaches within 0.3 m of the line, from its first corner on the line to its
## last; roads side by side (a road and its walkway, a verge between) are one opening.
const GATE_MERGE := 3.0
func road_cuts(a: Vector2, c: Vector2) -> Array:
	var L := a.distance_to(c)
	var d := (c - a) / L
	var nrm := Vector2(-d.y, d.x)
	var cuts: Array = []
	for sf in roads():
		var lo := INF
		var hi := -INF
		for q: Vector2 in sf.outline:
			if absf((q - a).dot(nrm)) <= 0.3:
				var t := (q - a).dot(d)
				lo = minf(lo, t)
				hi = maxf(hi, t)
		if hi > lo and hi > 0.0 and lo < L:
			cuts.append([maxf(lo, 0.0), minf(hi, L)])
	cuts.sort_custom(func(x, y): return x[0] < y[0])
	var out: Array = []
	for cu in cuts:
		if not out.is_empty() and cu[0] <= out[-1][1] + GATE_MERGE:
			out[-1][1] = maxf(out[-1][1], cu[1])
		else:
			out.append(cu)
	return out

## The windbreak: tamarisk (SITE.md §4) in two staggered rows WINDBREAK_ROWS metres inside the wall's north and west
## sides, the second row half a spacing along, every WINDBREAK_SPACING metres; none within WINDBREAK_CLEAR of a road
## (the gate, the ring road) or inside a process area or by a site area's building or structure. Made by the parts kit
## (planting) and baked with the ground. Returns the trees planted.
const WINDBREAK_ROWS := [3.0, 5.5]
const WINDBREAK_SPACING := 2.5
const WINDBREAK_CLEAR := 6.0
func _windbreak(root: Node3D, wall: Rect2, road_out: Rect2) -> int:
	var places := windbreak_places(wall, road_out)
	var k := 0
	for p in places:
		var s := {"id": "windbreak_%d" % k, "part": "planting", "at": [p.x, p.y, 0.0],
			"yaw": float((k * 97) % 360), "params": {"species": "tamarisk"}}
		k += 1
		b.kp.structure(root, s)
	b.kp.flush(root)
	# its far view (builder hlod): a few draw calls along the wall from afar, not one per cell and shape
	var kit: Node = root.get_node("kit")   # (app/plant.gd fills the cells of a node named so)
	var items := {"buildings": [], "sheets": [], "plants": places.map(func(p): return ["tamarisk", p, 6.0])}
	b.hlod(root, "windbreak", items, kit)
	print("build: windbreak: %d tamarisks along the wall's north and west sides" % places.size())
	return places.size()

## Where the windbreak's trees stand (plan points).
func windbreak_places(wall: Rect2, road_out: Rect2) -> Array:
	var blocked: Array = []   # rects a tree must not stand in
	for a in b.areas:
		if interior(a):
			continue
		if a.data.get("pack", "") in [SITE_PACK, CAMP_PACK]:
			for st in a.data.get("structures", []):
				if st.get("part", "") in ["building", "road", "planting", "canopy", "court", "porch", "vehicle", "lamp_post",
						"guard_booth", "barrier", "bench", "fence"]:
					var at: Array = st.get("at", [0, 0, 0])
					blocked.append(Rect2(Vector2(at[0], at[1]), Vector2.ZERO).grow(3.0))
			continue
		blocked.append(_rect(a.data.bounds).grow(2.0))
	blocked.append(road_out.grow(WINDBREAK_CLEAR))
	for sf in roads():
		blocked.append(_bbox(sf.outline).grow(WINDBREAK_CLEAR))
	for bd in b.buildings:
		blocked.append(_bbox(bd.outline).grow(2.0))
	var out: Array = []
	for row in WINDBREAK_ROWS.size():
		var off: float = WINDBREAK_ROWS[row]
		var shift := WINDBREAK_SPACING * 0.5 * row
		# the north side, west to east, and the west side, north to south (the corner planted once)
		var lines := [[Vector2(wall.position.x + off, wall.end.y - off), Vector2(wall.end.x - off, wall.end.y - off)],
			[Vector2(wall.position.x + off, wall.end.y - off - WINDBREAK_SPACING), Vector2(wall.position.x + off, wall.position.y + off)]]
		for ln in lines:
			var a: Vector2 = ln[0]
			var c: Vector2 = ln[1]
			var L := a.distance_to(c)
			var t := shift
			while t <= L:
				var p := a.lerp(c, t / L)
				t += WINDBREAK_SPACING
				if not blocked.any(func(r): return r.has_point(p)):
					out.append(p)
	return out

## The country beyond the wall: a grid out to FAR from the centre, its height 0 at the wall, a few metres of
## undulation within 250 m and low hills towards the far plane (FastNoiseLite: the same every build). Not walkable
## (the wall keeps the walker in); lit by the bake at a coarse texel.
## None of it lies under the site's own ground (the wall's rect, the camp's areas): the grid's lines include those
## rects' edges, so every cell is wholly inside one (left out) or wholly outside, and the terrain meets the ground's
## edge at height 0 without overlapping it. (It used to run on under the ground a little lower, cut only where a whole
## 20 m cell lay inside: across the 20 m wide road to the camp no cell did, and the terrain lay in the gravel's and the
## road's plane there, showing through them in patches that changed as one walked: the Note 9, 2026-10-23.)
func _terrain(root: Node3D, wall: Rect2) -> void:
	var c := wall.get_center()
	river = has_river()
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	var zones: Array = ground_rects(wall)
	var o := c - Vector2(FAR, FAR)
	var xs := grid_lines(o.x, zones, 0)
	var ys := grid_lines(o.y, zones, 1)
	var hs := []
	for j in ys.size():
		var row := []
		for i in xs.size():
			row.append(_height(Vector2(xs[i], ys[j]), wall, noise, zones))
		hs.append(row)
	var st: SurfaceTool = b._st()
	for j in ys.size() - 1:
		for i in xs.size() - 1:
			var p00 := Vector2(xs[i], ys[j])
			var p11 := Vector2(xs[i + 1], ys[j + 1])
			var mid := (p00 + p11) * 0.5
			if zones.any(func(r): return (r as Rect2).has_point(mid)):
				continue   # inside the wall or the camp: the site's own ground
			if p00.distance_to(c) > FAR + TERRAIN_CELL and p11.distance_to(c) > FAR + TERRAIN_CELL:
				continue
			var q := [p00, Vector2(p11.x, p00.y), p11, Vector2(p00.x, p11.y)]
			var z := [hs[j][i], hs[j][i + 1], hs[j + 1][i + 1], hs[j + 1][i]]
			var v := []
			for k in 4:
				v.append(Geom.g([q[k].x, q[k].y, z[k]]))
			_tri(st, v[0], v[1], v[2])
			_tri(st, v[0], v[2], v[3])
	st.generate_normals()
	b._mesh_node(root, "terrain", st, b._mat("terrain"), 8.0)

## The rects the site's own ground covers (plant coordinates): inside the wall, and the camp's areas outside it.
func ground_rects(wall: Rect2) -> Array:
	var out: Array = [wall]
	out.append_array(camp_rects())
	return out

## The terrain grid's lines along one axis (0: x, 1: y) from `start`: every TERRAIN_CELL to 2 × FAR, and every edge of
## the ground's rects, so that no cell crosses one (a grid line within a metre of an edge gives way to it: no slivers).
static func grid_lines(start: float, zones: Array, axis: int) -> PackedFloat64Array:
	var edges: Array = []
	for r in zones:
		var rr: Rect2 = r
		edges.append(rr.position[axis])
		edges.append(rr.end[axis])
	var all: Array = edges.duplicate()
	var n := int(ceil(FAR * 2.0 / TERRAIN_CELL))
	for k in n + 1:
		var t := start + k * TERRAIN_CELL
		if k == 0 or k == n or not edges.any(func(e): return absf(e - t) < 1.0):
			all.append(t)
	all = all.filter(func(t): return t >= start - 1e-6 and t <= start + n * TERRAIN_CELL + 1e-6)
	all.sort()
	var out := PackedFloat64Array()
	for t in all:
		if out.is_empty() or t - out[out.size() - 1] > 1e-4:
			out.append(t)
	return out

static func _tri(st: SurfaceTool, a: Vector3, c: Vector3, d: Vector3) -> void:
	# the triangle's front face up (Godot: clockwise seen from the front)
	var nrm := (d - a).cross(c - a)
	var order := [a, c, d] if nrm.y > 0.0 else [a, d, c]
	for p in order:
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)

## Plan distance from p to a rect (0 inside).
static func _dist(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dy).length()

## Terrain height at a plan point: 0 on and near the edge of the wall and the camp's ground (`zones`), then
## undulating, then hills.
func _height(p: Vector2, wall: Rect2, noise: FastNoiseLite, zones: Array = []) -> float:
	var d := _dist(p, wall)   # outside the wall
	for z in zones:
		d = minf(d, _dist(p, z))
	if d <= 0.0:
		return 0.0   # on the edge of the site's own ground (no terrain lies inside it: _terrain)
	var t := smoothstep(20.0, 120.0, d)
	var hills := smoothstep(250.0, 650.0, d)
	var nv := noise.get_noise_2d(p.x, p.y)   # -1 .. 1
	var h := t * (1.5 * nv) + hills * (14.0 + 22.0 * nv) - 0.15 * t
	if river:
		# the river's channel: the banks fall to its bed within RIVER_SLOPE of its edges, across its whole length
		var rx := river_x(wall)
		var inside := minf(p.x - rx.x, rx.y - p.x)
		if inside > -RIVER_SLOPE:
			var k := smoothstep(-RIVER_SLOPE, RIVER_SLOPE, inside)
			h = lerpf(minf(h, 0.0), RIVER_BED, k)
	return h
