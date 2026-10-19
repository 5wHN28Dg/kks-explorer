## The site round the areas (R9: a plant stands on paved yards between roads, inside a boundary wall, in open
## country; the bare gravel plane to the horizon was the most artificial thing in every view). Made by the build from
## the areas' bounds, the same for every plant description, nothing a trainee operates:
##   - the areas' yards paved in concrete (their bounds), gravel between them;
##   - a ring road round all the areas (asphalt, kerbs, a covered drain along its inner edge);
##   - a precast concrete boundary wall with pilasters and a closed gate;
##   - the country beyond: a terrain to the far plane, flat near the wall, rising to low hills.
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

var b   # the plant builder

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
	for a in b.areas:
		var bd: Array = a.data.bounds
		pads.append(Rect2(Vector2(bd[0][0], bd[0][1]), Vector2(bd[1][0] - bd[0][0], bd[1][1] - bd[0][1])))
	# gravel between the yards, inside the ring road and its drain
	var drain_in := road_in.grow(-0.4)
	var gh: Array = holes.duplicate()
	for p in pads:
		gh.append(poly_of(p))
	b._slab(root, "ground", poly_of(drain_in), gh, 0.0, 0.5, b._mat("ground"), Lightmap.GROUND_TEXEL)
	# the yards: concrete, less pits and stairwells
	var i := 0
	for p in pads:
		var ph: Array = []
		for h in holes:
			if p.grow(0.01).encloses(_bbox(h)):
				ph.append(h)
		b._slab(root, "yard_%d" % i, poly_of(p), ph, 0.0, 0.5, b._mat("yard"), Lightmap.GROUND_TEXEL)
		i += 1
	# the ring road, and gravel from it to the wall
	b._slab(root, "road", poly_of(road_out), [poly_of(road_in)], 0.0, 0.5, b._mat("road"), Lightmap.GROUND_TEXEL)
	b._slab(root, "verge", poly_of(wall), [poly_of(road_out)], 0.0, 0.5, b._mat("ground"), Lightmap.GROUND_TEXEL)
	_kerbs_and_drain(root, road_in, road_out, drain_in)
	_wall(root, wall)
	_terrain(root, wall)

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
			Geom.add_prism(kerb, pc, 0.0, KERB_H)
	b._mesh_node(root, "kerbs", kerb, b._mat("concrete"), Lightmap.GROUND_TEXEL)
	var dark: SurfaceTool = b._st()
	for pc in Geom.decompose(poly_of(road_in), [poly_of(drain_in)]):
		Geom.add_prism(dark, pc, -0.25, -0.2, false)
	b._mesh_node(root, "drain", dark, b._mat("drain"))
	b._slab(root, "drain_cover", poly_of(road_in), [poly_of(drain_in)], 0.0, 0.03, b._mat("grating"), Lightmap.TEXEL)

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
			Geom.add_prism(st, pc, 0.0, WALL_H + 0.15)
	b._mesh_node(body, "panels", st, b._mat("wall_concrete"), Lightmap.GROUND_TEXEL)
	b._mesh_node(body, "gate", gate, b._mat("fence"), Lightmap.SHEET_TEXEL)   # a thin sheet: a fine texel

## The country beyond the wall: a grid out to FAR from the centre, its height 0 at the wall, a few metres of
## undulation within 250 m and low hills towards the far plane (FastNoiseLite: the same every build). Not walkable
## (the wall keeps the walker in); lit by the bake at a coarse texel.
func _terrain(root: Node3D, wall: Rect2) -> void:
	var c := wall.get_center()
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
	return t * (1.5 * nv) + hills * (14.0 + 22.0 * nv) - 0.15 * t
