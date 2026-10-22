## The site round the areas (R9: a plant stands on paved yards between roads, inside a boundary wall, in open
## country; the bare gravel plane to the horizon was the most artificial thing in every view). Made by the build from
## the areas' bounds, the same for every plant description, nothing a trainee operates:
##   - the areas' yards paved in concrete (their bounds), gravel between them;
##   - a ring road round all the areas (asphalt, kerbs, a covered drain along its inner edge);
##   - a precast concrete boundary wall with pilasters and a closed gate;
##   - the country beyond: a terrain to the far plane, flat near the wall, rising to low hills;
##   - with a river intake (an area `intake`, docs/plant3d/SITE.md §1): the river along the wall's east side, beyond
##     a strip of bank, its water at RIVER_LEVEL, and the headwall where the intake's channel (its pits) opens on
##     the river under the road and the wall.
## The ground's slabs are drawn without their undersides (never seen; half their lightmap texels).
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

## The extent of the areas as a Rect2 (plant coordinates).
func extent() -> Rect2:
	var ex: Array = b._extent()
	return Rect2(Vector2(ex[0][0], ex[0][1]), Vector2(ex[1][0] - ex[0][0], ex[1][1] - ex[0][1]))

## The wall's line: the walkable ground ends there.
func wall_rect() -> Rect2:
	return extent().grow(ROAD_GAP + ROAD_W + WALL_GAP)

func make(root: Node3D, holes: Array) -> void:
	var E := extent()
	var road_in := E.grow(ROAD_GAP)
	var road_out := road_in.grow(ROAD_W)
	var wall := wall_rect()
	var pads: Array = []
	var paved: Array = []   # an area with a building is paved in concrete, an open one (an HRSG, a transformer yard) gravelled
	for a in b.areas:
		var bd: Array = a.data.bounds
		pads.append(Rect2(Vector2(bd[0][0], bd[0][1]), Vector2(bd[1][0] - bd[0][0], bd[1][1] - bd[0][1])))
		paved.append(Array(a.data.get("structures", [])).any(func(s): return s.get("part", "") == "building"))
	# gravel between the yards, inside the ring road and its drain
	var drain_in := road_in.grow(-0.4)
	var gh: Array = holes.duplicate()
	for p in pads:
		gh.append(poly_of(p))
	b._slab(root, "ground", poly_of(drain_in), gh, 0.0, 0.5, b._mat("ground"), Lightmap.GROUND_TEXEL, false)
	# the yards: concrete, less pits and stairwells
	var i := 0
	for p in pads:
		var ph: Array = []
		for h in holes:
			if p.grow(0.01).encloses(_bbox(h)):
				ph.append(h)
		b._slab(root, "yard_%d" % i, poly_of(p), ph, 0.0, 0.5, b._mat("yard" if paved[i] else "yard_gravel"), Lightmap.GROUND_TEXEL, false)
		i += 1
	# the ring road, and gravel from it to the wall
	b._slab(root, "road", poly_of(road_out), [poly_of(road_in)], 0.0, 0.5, b._mat("road"), Lightmap.GROUND_TEXEL, false)
	b._slab(root, "verge", poly_of(wall), [poly_of(road_out)], 0.0, 0.5, b._mat("ground"), Lightmap.GROUND_TEXEL, false)
	_kerbs_and_drain(root, road_in, road_out, drain_in)
	_wall(root, wall)
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
	Geom.add_prism(st, Geom.rect(rx.x, c.y - FAR, rx.y, c.y + FAR), RIVER_LEVEL - 0.05, RIVER_LEVEL, false)
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
		Geom.add_prism(hw, Geom.rect(rx.x - 2.0, lo - 1.5, rx.x + 0.5, hi + 1.5), RIVER_BED, 0.4)
		b._mesh_node(root, "intake_headwall", hw, b._mat("concrete"), Lightmap.TEXEL)
		var dark: SurfaceTool = b._st()
		Geom.add_prism(dark, Geom.rect(rx.x + 0.5, lo, rx.x + 0.52, hi), RIVER_BED + 0.5, RIVER_LEVEL + 0.6)
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

## The boundary wall: precast panels between pilasters every 6 m, and a closed sliding gate on the south side.
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
		var n := int(ceil(L / 6.0))
		for k in n:
			var p0 := a2 + d * (L * k / n)
			var p1 := a2 + d * (L * (k + 1) / n)
			var mid := (p0 + p1) * 0.5
			var is_gate := mid.distance_to(gate_c) < 4.5
			if is_gate:
				b._wall_panel(gate, body, p0, p1, 0.0, WALL_H - 0.4, 0.08)
			else:
				b._wall_panel(st, body, p0, p1, 0.0, WALL_H, 0.2)
			var pc := Geom.rect(p0.x - 0.2, p0.y - 0.2, p0.x + 0.2, p0.y + 0.2)
			st.set_color(b.top_colour(WALL_H + 0.15))   # its own top (it stands higher than the panels: review)
			Geom.add_prism(st, pc, 0.0, WALL_H + 0.15)
	b._mesh_node(body, "panels", st, b._mat("wall_concrete"), Lightmap.GROUND_TEXEL)
	b._mesh_node(body, "gate", gate, b._mat("fence"), Lightmap.SHEET_TEXEL)   # a thin sheet: a fine texel

## The country beyond the wall: a grid out to FAR from the centre, its height 0 at the wall, a few metres of
## undulation within 250 m and low hills towards the far plane (FastNoiseLite: the same every build). Not walkable
## (the wall keeps the walker in); lit by the bake at a coarse texel.
func _terrain(root: Node3D, wall: Rect2) -> void:
	var c := wall.get_center()
	river = has_river()
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	var n := int(ceil(FAR * 2.0 / TERRAIN_CELL))
	var o := c - Vector2(FAR, FAR)
	var hs := []
	for j in n + 1:
		var row := []
		for i in n + 1:
			var p := o + Vector2(i, j) * TERRAIN_CELL
			row.append(_height(p, wall, noise))
		hs.append(row)
	var st: SurfaceTool = b._st()
	var inner := wall.grow(-1.0)
	for j in n:
		for i in n:
			var p00 := o + Vector2(i, j) * TERRAIN_CELL
			var p11 := p00 + Vector2(TERRAIN_CELL, TERRAIN_CELL)
			if inner.encloses(Rect2(p00, Vector2(TERRAIN_CELL, TERRAIN_CELL))):
				continue   # inside the wall: the site's own ground
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

static func _tri(st: SurfaceTool, a: Vector3, c: Vector3, d: Vector3) -> void:
	# the triangle's front face up (Godot: clockwise seen from the front)
	var nrm := (d - a).cross(c - a)
	var order := [a, c, d] if nrm.y > 0.0 else [a, d, c]
	for p in order:
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)

## Terrain height at a plan point: 0 inside a band round the wall, then undulating, then hills.
func _height(p: Vector2, wall: Rect2, noise: FastNoiseLite) -> float:
	var dx := maxf(maxf(wall.position.x - p.x, p.x - wall.end.x), 0.0)
	var dy := maxf(maxf(wall.position.y - p.y, p.y - wall.end.y), 0.0)
	var d := Vector2(dx, dy).length()   # outside the wall
	if d <= 0.0:
		# inside the wall: under the site's own ground (a terrain cell across the wall would otherwise lie in the
		# gravel's plane and flicker against it)
		return -0.3 if wall.grow(-0.5).has_point(p) else 0.0
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
