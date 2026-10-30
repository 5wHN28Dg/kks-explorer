## Lifting gear (docs/PLANT3D.md §20.5): a monorail hoist (an electric chain hoist on a motorised trolley under a
## beam, the beam on portal frames, a pendant station and a barriered drop zone at grade under the beam's tip) and an
## overhead travelling crane (the bridge on its runway, the trolley, the hook block on its ropes, a pendant hanging
## from the bridge). The moving pieces are drawn at the model's values (kit/README.md "Moving parts"): `slide` pieces
## move along their axis by the value in metres, `stretch` pieces (the chain, the ropes) hang from their pivot down
## to the hook. Every slide's pivot is the part's origin, so a value is the piece's position in the part's frame:
##   monorail_hoist  origin at grade under the beam's tip, +y along the beam inwards: trolley (y, metres from the
##                   tip), trolley/hook (z, the hook's seat above grade), trolley/chain, load_y, load_y/load_z (the
##                   load's base); pendant (a marker: where the pendant station's buttons are)
##   overhead_crane  origin at grade at the runway's start on its centre line, +y along the runway: bridge (y),
##                   bridge/trolley (along -x), bridge/trolley/hook (z), bridge/trolley/rope, load_y, load_y/load_x
##                   (-x), load_y/load_x/load_z; bridge/pendant (a marker)
## The drives, the hook's latch and the load cell that ride on them are `hoist_unit` parts: codes of their own,
## carried with the piece they ride on by the app (ui/bindings.gd), drawn by their hoist.
extends RefCounted

const LATCH_H := 0.12           # the hook's seat: its value is the height of the slings' eye on it

## How far above the hook's seat the chain or the ropes reach the hook block (the stretch pieces end there).
const MONO_BLOCK_TOP := 0.45
const CRANE_BLOCK_TOP := 1.4

static func monorail_hoist(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 9)
	var bz: float = g.num("beam_z", 34)
	var dz: float = g.num("deck_z", 30)
	var edge: float = g.num("edge", 3)
	var zone: float = g.num("zone", 5)
	var sling: float = g.num("sling", 1.2)
	# the beam: an I-section under the portals' crossbars, safety yellow, end stops at both ends
	m.use("paint_yellow", "form")
	m.box_lh(Vector3(-0.1, 0, bz), Vector3(0.1, L, bz + 0.025))
	m.box_lh(Vector3(-0.008, 0, bz + 0.025), Vector3(0.008, L, bz + 0.375))
	m.box_lh(Vector3(-0.1, 0, bz + 0.375), Vector3(0.1, L, bz + 0.4))
	m.use("paint_red", "identify")
	for y in [0.08, L - 0.08]:
		m.box(Vector3(0, y, bz - 0.06), Vector3(0.16, 0.08, 0.12))
	# the portals on the deck: two posts and a crossbar each
	m.use("paint_frame", "form")
	for y in [edge + 0.5, L - 0.5]:
		for sx in [-1.2, 1.2]:
			m.box_lh(Vector3(sx - 0.1, y - 0.1, dz), Vector3(sx + 0.1, y + 0.1, bz + 0.6))
			m.box_lh(Vector3(sx - 0.2, y - 0.2, dz), Vector3(sx + 0.2, y + 0.2, dz + 0.02))
			g.solid_box(Vector3(sx - 0.1, y - 0.1, dz), Vector3(sx + 0.1, y + 0.1, dz + 2.0))
		m.box_lh(Vector3(-1.3, y - 0.1, bz + 0.4), Vector3(1.3, y + 0.1, bz + 0.6))
	g.plate("beam", Vector3(0.12, L - 1.6, bz + 0.2), Vector3(1, 0, 0))
	# the pendant station on the inner portal's post, its buttons (one pair a row of the pendant)
	var ps := Vector3(1.38, L - 0.5, dz + 1.25)
	_pendant_box(m, ps, g.p.get("pendant", []).size())
	g.move("pendant", ps, Vector3(0, 0, 1), "marker", 0.0)
	# the drop zone at grade: posts and two rails on three sides (the casing's wall is the fourth), a gap to go in
	if zone > 0.0:
		var y0 := edge - 0.3 - zone
		var y1 := edge - 0.3
		var h := zone * 0.5
		_barrier(g, Vector2(-h, y1), Vector2(-h, y0))
		_barrier(g, Vector2(-h, y0), Vector2(-0.6, y0))
		_barrier(g, Vector2(0.6, y0), Vector2(h, y0))
		_barrier(g, Vector2(h, y0), Vector2(h, y1))
	# the trolley on the beam's bottom flange, its drive, the chain hoist under it
	var tr = g.move("trolley", Vector3.ZERO, Vector3(0, 1, 0), "slide", 1.0)
	tr.use("paint_yellow", "form")
	for sx in [-1.0, 1.0]:
		tr.box(Vector3(sx * 0.13, 0, bz + 0.1), Vector3(0.02, 0.5, 0.36))
	tr.box_lh(Vector3(-0.14, -0.08, bz - 0.08), Vector3(0.14, 0.08, bz - 0.02))
	tr.box_lh(Vector3(-0.2, -0.22, bz - 0.6), Vector3(0.2, 0.22, bz - 0.08))
	tr.use("paint_orange", "form")
	tr.cyl(Vector3(0.14, 0.1, bz + 0.15), Vector3(0.36, 0.1, bz + 0.15), 0.07, -1.0, 10)
	tr.cyl(Vector3(0.2, 0.0, bz - 0.34), Vector3(0.45, 0.0, bz - 0.34), 0.12, -1.0, 12)
	tr.use("paint_black", "form")
	tr.box_lh(Vector3(-0.12, 0.22, bz - 0.5), Vector3(0.12, 0.32, bz - 0.2))          # the chain's bag
	_hook(g.move("trolley/hook", Vector3.ZERO, Vector3(0, 0, 1), "slide", 1.0), 0.16, MONO_BLOCK_TOP, 0.06)
	var top := bz - 0.6
	var ch = g.move("trolley/chain", Vector3(0, 0, top), Vector3(0, 0, -1), "stretch", top - MONO_BLOCK_TOP)
	ch.use("paint_black", "form")
	ch.box_lh(Vector3(-0.008, -0.008, top - 1.0), Vector3(0.008, 0.008, top))
	# the load: a spare valve on its pallet, its sling legs up to the hook's seat when taut
	g.move("load_y", Vector3.ZERO, Vector3(0, 1, 0), "slide", 1.0)
	var ld = g.move("load_y/load_z", Vector3.ZERO, Vector3(0, 0, 1), "slide", 1.0)
	ld.use("paint_beige", "form")
	ld.box_lh(Vector3(-0.5, -0.6, 0.0), Vector3(0.5, 0.6, 0.15))
	ld.use("paint_valve", "form")
	ld.cyl(Vector3(0, -0.36, 0.42), Vector3(0, 0.36, 0.42), 0.17, -1.0, 16)
	for y in [-0.36, 0.36]:
		ld.cyl(Vector3(0, y - 0.03, 0.42), Vector3(0, y + 0.03, 0.42), 0.26, -1.0, 16)
	ld.cyl(Vector3(0, 0, 0.42), Vector3(0, 0, 0.85), 0.11, -1.0, 12)
	_slings(ld, [Vector3(-0.45, -0.55, 0.15), Vector3(0.45, -0.55, 0.15), Vector3(0.45, 0.55, 0.15),
		Vector3(-0.45, 0.55, 0.15)], Vector3(0, 0, sling + 0.3), "paint_red")

static func overhead_crane(_part: String, g) -> void:
	var m = g.m
	var R: float = g.num("runway", 80)
	var S: float = g.num("span", 48)
	var zr: float = g.num("rail_z", 26)
	var sling: float = g.num("sling", 3)
	var hs := S * 0.5
	# the end stops at both ends of both rails (the runway itself is the hall's: builder/plant_builder.gd _crane)
	m.use("paint_yellow", "form")
	for sx in [-hs, hs]:
		for y in [0.35, R - 0.35]:
			m.box(Vector3(sx, y, zr + 0.25), Vector3(0.35, 0.3, 0.5))
			g.solid_box(Vector3(sx - 0.175, y - 0.15, zr), Vector3(sx + 0.175, y + 0.15, zr + 0.5))
	# the bridge: two box girders on their end carriages, the drives on the carriages, the pendant on its cable
	var br = g.move("bridge", Vector3.ZERO, Vector3(0, 1, 0), "slide", 1.0)
	br.use("paint_yellow", "form")
	for dy in [-1.1, 1.1]:
		br.box_lh(Vector3(-hs + 0.35, dy - 0.3, zr + 0.15), Vector3(hs - 0.35, dy + 0.3, zr + 1.75))
	for sx in [-hs, hs]:
		br.box_lh(Vector3(sx - 0.35, -2.4, zr), Vector3(sx + 0.35, 2.4, zr + 1.05))
	br.use("paint_motor", "form")
	for sx in [-hs + 0.9, hs - 0.9]:
		br.cyl(Vector3(sx, 1.6, zr + 1.3), Vector3(sx, 2.3, zr + 1.3), 0.2, -1.0, 12)
	var px: float = g.num("pendant_x", 0)
	var pz: float = g.num("pendant_z", 1.2)
	br.use("paint_black", "form")
	br.box_lh(Vector3(px - 0.006, -1.5 - 0.006, pz + 0.18), Vector3(px + 0.006, -1.5 + 0.006, zr + 0.15))
	_pendant_box(br, Vector3(px, -1.5, pz), g.p.get("pendant", []).size())
	g.move("bridge/pendant", Vector3(px, -1.5, pz), Vector3(0, 0, 1), "marker", 0.0)
	# the trolley on the girders, its rope drum
	var tr = g.move("bridge/trolley", Vector3.ZERO, Vector3(-1, 0, 0), "slide", 1.0)
	var zt := zr + 1.75
	tr.use("paint_yellow", "form")
	tr.box_lh(Vector3(-1.6, -1.8, zt), Vector3(1.6, 1.8, zt + 0.3))
	# (its top, the drum's and the housing's, 0.9 m over the frame: rail + 2.65 m, builder/plant_builder.gd CRANE_TOP)
	tr.box_lh(Vector3(-1.4, 0.6, zt + 0.3), Vector3(1.4, 1.6, zt + 0.9))
	tr.use("paint_darkgrey", "form")
	tr.cyl(Vector3(-1.1, -0.5, zt + 0.6), Vector3(1.1, -0.5, zt + 0.6), 0.3, -1.0, 16)
	tr.use("paint_motor", "form")
	tr.cyl(Vector3(1.1, 1.1, zt + 0.6), Vector3(1.6, 1.1, zt + 0.6), 0.25, -1.0, 12)
	_hook(g.move("bridge/trolley/hook", Vector3.ZERO, Vector3(0, 0, 1), "slide", 1.0), 0.5, CRANE_BLOCK_TOP, 0.2)
	var rp = g.move("bridge/trolley/rope", Vector3(0, 0, zt), Vector3(0, 0, -1), "stretch", zt - CRANE_BLOCK_TOP)
	rp.use("paint_black", "form")
	for o in [Vector2(-0.3, -0.15), Vector2(0.3, -0.15), Vector2(-0.3, 0.15), Vector2(0.3, 0.15)]:
		rp.box_lh(Vector3(o.x - 0.012, o.y - 0.012, zt - 1.0), Vector3(o.x + 0.012, o.y + 0.012, zt))
	# the load: a crate of spares on its skids, a four-leg sling
	g.move("load_y", Vector3.ZERO, Vector3(0, 1, 0), "slide", 1.0)
	g.move("load_y/load_x", Vector3.ZERO, Vector3(-1, 0, 0), "slide", 1.0)
	var ld = g.move("load_y/load_x/load_z", Vector3.ZERO, Vector3(0, 0, 1), "slide", 1.0)
	ld.use("paint_beige", "form")
	for sx in [-0.6, 0.6]:
		ld.box_lh(Vector3(sx - 0.08, -1.2, 0.0), Vector3(sx + 0.08, 1.2, 0.12))
	ld.box_lh(Vector3(-0.8, -1.2, 0.12), Vector3(0.8, 1.2, 1.4))
	for y in [-1.1, 0.0, 1.1]:
		ld.box_lh(Vector3(-0.82, y - 0.06, 0.12), Vector3(0.82, y + 0.06, 1.42))
	_slings(ld, [Vector3(-0.7, -1.1, 1.4), Vector3(0.7, -1.1, 1.4), Vector3(0.7, 1.1, 1.4), Vector3(-0.7, 1.1, 1.4)],
		Vector3(0, 0, sling + 0.3), "paint_darkgrey")

## A code of its own riding on its hoist: drawn by the hoist (nothing of its own).
static func hoist_unit(_part: String, _g) -> void:
	pass

## A hook block: the sheave block from just above the hook's seat to `top`, the hook under it. w: the block's width;
## r: the hook's bend radius. The seat (where the slings' eye hangs) is at the piece's origin.
static func _hook(h, w: float, top: float, r: float) -> void:
	h.use("paint_yellow", "form")
	h.box_lh(Vector3(-w * 0.5, -w * 0.4, top * 0.3), Vector3(w * 0.5, w * 0.4, top))
	h.use("paint_darkgrey", "form")
	h.cyl(Vector3(0, 0, r + LATCH_H * 0.5), Vector3(0, 0, top * 0.3), r * 0.25, -1.0, 8)
	h.torus(Vector3(0, 0, r * 0.5), Vector3(0, 1, 0), Vector3(0, 0, -1), r, r * 0.3, PI * 1.5, 8, 6)
	h.use("paint_red", "form")
	h.box(Vector3(0, r * 0.9, r + LATCH_H * 0.3), Vector3(r * 0.15, r * 0.15, r * 0.9))   # the latch

## Sling legs from the load's lifting points to the eye.
static func _slings(m, pts: Array, eye: Vector3, mat: String) -> void:
	m.use(mat, "form")
	for p in pts:
		m.cyl(p, eye, 0.012, -1.0, 4, false)

## A pendant control box at c: yellow, a pair of buttons a row, the emergency stop on top.
static func _pendant_box(m, c: Vector3, rows: int) -> void:
	var n := maxi(rows, 1)
	var h := 0.08 * n + 0.1
	m.use("paint_yellow", "form")
	m.box(c, Vector3(0.1, 0.08, h))
	m.use("paint_black", "form")
	for i in n:
		var z := c.z + h * 0.5 - 0.09 - 0.08 * i
		for dx in [-0.022, 0.022]:
			m.cyl(Vector3(c.x + dx, c.y - 0.04, z), Vector3(c.x + dx, c.y - 0.052, z), 0.014, -1.0, 8)
	m.use("paint_red", "form")
	m.cyl(Vector3(c.x, c.y, c.z + h * 0.5), Vector3(c.x, c.y, c.z + h * 0.5 + 0.025), 0.025, -1.0, 10)

## A drop zone's barrier from a to b at grade: posts every 1.25 m or less, a top and a middle rail, solid.
static func _barrier(g, a: Vector2, b: Vector2) -> void:
	var m = g.m
	var len := a.distance_to(b)
	var n := maxi(1, int(ceil(len / 1.25)))
	m.use("paint_yellow", "form")
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		m.box_lh(Vector3(p.x - 0.03, p.y - 0.03, 0), Vector3(p.x + 0.03, p.y + 0.03, 1.05))
	m.use("paint_red", "identify")
	var c := (a + b) * 0.5
	var d := Vector3(b.x - a.x, b.y - a.y, 0).normalized()
	var along := Basis(d.cross(Vector3(0, 0, 1)), d, Vector3(0, 0, 1))
	for z in [0.5, 1.0]:
		m.box(Vector3(c.x, c.y, z), Vector3(0.04, len, 0.04), along)
	g.solid_obox(Vector3(c.x, c.y, 0.525), Vector3(0.08, len, 1.05), along)
