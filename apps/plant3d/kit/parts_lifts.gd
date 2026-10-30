## A rack-and-pinion service lift (docs/PLANT3D.md §20.2, decision 0071): the mast with its rack, the base enclosure
## at grade, the cab and its gate; the landing gates and the call stations. Part frames:
##   service_lift  origin at the cab floor's centre at the lowest landing; the cab's front (open to the landing gates)
##                 faces -x, the mast stands behind it (+x): cab (slide along +z: the cab floor's height above the
##                 origin, moved by the app, apps/plant3d/app/lift.gd), cab/gate (slide along +z: the cab's own gate,
##                 risen with the landing gate where the cab stands)
##   lift_gate     origin at the gate's sill, the leaf across y: leaf (translate along +z, 0 shut, 1 open: risen
##                 LEAF_RISE m)
##   lift_call     origin at the landing's floor under the station
##   lift_unit     a drive, the cab's panel or its load cell: drawn by the cab (nothing of its own)
extends RefCounted

const CAB_X := 0.5               # the cab's inside: x -0.5 .. 0.5 (front to back), y -0.6 .. 0.6, floor to roof 2.3 m
const CAB_Y := 0.6
const CAB_H := 2.3
const MAST_X0 := 0.75            # the mast: x 0.75 .. 1.2, y -0.225 .. 0.225
const MAST_W := 0.45
const LEAF_RISE := 2.1           # a landing gate's leaf rises this far to open (the walker passes under it)
const LEAF_H := 2.05
const GATE_HALF := 0.6           # a landing gate's posts at y ±0.6 (the bridges are 1.2 m wide)

static func service_lift(_part: String, g) -> void:
	var m = g.m
	var top: float = g.num("mast", 33)
	var x0 := MAST_X0
	var x1 := MAST_X0 + MAST_W
	var hw := MAST_W * 0.5
	# the mast: four corner tubes, a brace each way every 1.5 m, the rack on its front face
	m.use("galvanised", "form")
	for p in [Vector2(x0 + 0.03, -hw + 0.03), Vector2(x1 - 0.03, -hw + 0.03), Vector2(x0 + 0.03, hw - 0.03), Vector2(x1 - 0.03, hw - 0.03)]:
		m.cyl(Vector3(p.x, p.y, 0.0), Vector3(p.x, p.y, top), 0.03, -1.0, 6, false)
	var n := int(ceil(top / 1.5))
	for i in n:
		var z0 := top * i / n
		var z1 := top * (i + 1) / n
		for y in [-hw + 0.03, hw - 0.03]:
			m.cyl(Vector3(x0 + 0.03, y, z0), Vector3(x1 - 0.03, y, z1), 0.012, -1.0, 4, false)
		m.cyl(Vector3(x1 - 0.03, -hw + 0.03, z0), Vector3(x1 - 0.03, hw - 0.03, z1), 0.012, -1.0, 4, false)
	m.use("steel_dark", "form")
	m.box_lh(Vector3(x0 - 0.04, -0.03, 0.2), Vector3(x0, 0.03, top))          # the rack
	g.solid_box(Vector3(x0 - 0.04, -hw, 0.0), Vector3(x1, hw, top))
	g.plate("mast", Vector3(x1 + 0.01, 0.0, 1.6), Vector3(1, 0, 0))
	# the base enclosure at grade: mesh panels round the cab's and the mast's footprint, its front the bottom gate
	m.use("paint_frame", "form")
	m.box_lh(Vector3(-CAB_X - 0.1, -CAB_Y - 0.25, -0.05), Vector3(x1 + 0.25, CAB_Y + 0.25, 0.0))     # the pad
	for e in [[Vector2(-CAB_X - 0.05, -CAB_Y - 0.15), Vector2(x1 + 0.15, -CAB_Y - 0.15)],
			[Vector2(x1 + 0.15, -CAB_Y - 0.15), Vector2(x1 + 0.15, CAB_Y + 0.15)],
			[Vector2(x1 + 0.15, CAB_Y + 0.15), Vector2(-CAB_X - 0.05, CAB_Y + 0.15)]]:
		_panel(g, e[0], e[1], 0.0, 2.2)
	# buffers under the cab
	m.use("paint_black", "form")
	for y in [-0.3, 0.3]:
		m.cyl(Vector3(0.0, y, 0.0), Vector3(0.0, y, 0.25), 0.08, -1.0, 8)
	# the cab: floor, walls of mesh panels on three sides, its roof with a guard rail, the drive behind it on the mast,
	# the control panel and a lamp inside
	var cab = g.move("cab", Vector3.ZERO, Vector3(0, 0, 1), "slide", 1.0)
	cab.use("steel_dark", "form")
	cab.box_lh(Vector3(-CAB_X, -CAB_Y - 0.04, -0.14), Vector3(CAB_X + 0.04, CAB_Y + 0.04, 0.0))
	cab.use("paint_yellow", "form")
	for y in [-CAB_Y - 0.04, CAB_Y]:
		for x in [-CAB_X, CAB_X]:
			cab.box_lh(Vector3(x - 0.02, y, 0.0), Vector3(x + 0.02, y + 0.04, CAB_H))
	cab.box_lh(Vector3(-CAB_X, -CAB_Y - 0.04, CAB_H), Vector3(CAB_X + 0.04, CAB_Y + 0.04, CAB_H + 0.08))
	cab.use("galvanised", "form")
	cab.box_lh(Vector3(-CAB_X + 0.02, -CAB_Y - 0.03, 0.05), Vector3(CAB_X - 0.02, -CAB_Y - 0.01, CAB_H - 0.05))
	cab.box_lh(Vector3(-CAB_X + 0.02, CAB_Y + 0.01, 0.05), Vector3(CAB_X - 0.02, CAB_Y + 0.03, CAB_H - 0.05))
	cab.box_lh(Vector3(CAB_X + 0.01, -CAB_Y, 0.05), Vector3(CAB_X + 0.03, CAB_Y, CAB_H - 0.05))
	cab.use("paint_yellow", "form")
	for x in [-CAB_X + 0.03, CAB_X]:
		for y in [-CAB_Y, CAB_Y]:
			cab.box_lh(Vector3(x - 0.02, y - 0.02, CAB_H + 0.08), Vector3(x + 0.02, y + 0.02, CAB_H + 1.1))
	for y in [-CAB_Y, CAB_Y]:
		cab.box_lh(Vector3(-CAB_X + 0.01, y - 0.02, CAB_H + 1.06), Vector3(CAB_X + 0.02, y + 0.02, CAB_H + 1.1))
	cab.use("paint_motor", "form")
	cab.box_lh(Vector3(CAB_X + 0.04, -0.3, CAB_H - 0.7), Vector3(x0 - 0.05, 0.3, CAB_H + 0.3))   # the drive
	cab.box_lh(Vector3(CAB_X + 0.04, -0.2, 0.1), Vector3(x0 - 0.05, 0.2, 0.5))                     # the safety gear
	cab.use("steel_dark", "form")
	for z in [CAB_H - 0.5, CAB_H, 0.3]:
		cab.cyl(Vector3(x0 - 0.06, 0.0, z), Vector3(x0 - 0.04, 0.0, z), 0.08, -1.0, 10)              # the pinions
	cab.use("paint_yellow", "form")
	cab.box(Vector3(0.2, CAB_Y - 0.04, 1.25), Vector3(0.22, 0.06, 0.32))                         # the panel
	cab.use("paint_black", "form")
	for i in 3:
		cab.cyl(Vector3(0.14 + 0.06 * i, CAB_Y - 0.07, 1.3), Vector3(0.14 + 0.06 * i, CAB_Y - 0.08, 1.3), 0.017, -1.0, 8)
	cab.use("paint_red", "form")
	cab.cyl(Vector3(0.2, CAB_Y - 0.07, 1.18), Vector3(0.2, CAB_Y - 0.09, 1.18), 0.025, -1.0, 10)   # the stop
	cab.use("paint_white", "form")
	cab.box(Vector3(0.0, 0.0, CAB_H - 0.03), Vector3(0.5, 0.12, 0.04))                           # the lamp
	# the cab's own gate: rises with the landing gate where the cab stands (the app moves it)
	var cg = g.move("cab/gate", Vector3.ZERO, Vector3(0, 0, 1), "slide", 1.0)
	cg.use("paint_yellow", "form")
	cg.box_lh(Vector3(-CAB_X - 0.04, -CAB_Y + 0.02, 0.02), Vector3(-CAB_X, -CAB_Y + 0.06, 2.0))
	cg.box_lh(Vector3(-CAB_X - 0.04, CAB_Y - 0.06, 0.02), Vector3(-CAB_X, CAB_Y - 0.02, 2.0))
	cg.box_lh(Vector3(-CAB_X - 0.04, -CAB_Y + 0.02, 1.96), Vector3(-CAB_X, CAB_Y - 0.02, 2.0))
	cg.use("galvanised", "form")
	cg.box_lh(Vector3(-CAB_X - 0.03, -CAB_Y + 0.06, 0.04), Vector3(-CAB_X - 0.01, CAB_Y - 0.06, 1.96))

## A landing gate: two posts tall enough to guide the risen leaf, a header, the leaf of mesh in a yellow frame.
static func lift_gate(_part: String, g) -> void:
	var m = g.m
	var h := LEAF_RISE + LEAF_H + 0.1
	m.use("paint_yellow", "form")
	for y in [-GATE_HALF, GATE_HALF]:
		m.box_lh(Vector3(-0.03, y - 0.03, 0.0), Vector3(0.03, y + 0.03, h))
		g.solid_box(Vector3(-0.03, y - 0.03, 0.0), Vector3(0.03, y + 0.03, 2.2))
	m.box_lh(Vector3(-0.03, -GATE_HALF, h - 0.06), Vector3(0.03, GATE_HALF, h))
	m.use("paint_black", "identify")
	m.box_lh(Vector3(-0.035, -GATE_HALF + 0.03, 0.0), Vector3(0.035, GATE_HALF - 0.03, 0.01))   # the sill
	var lf = g.move("leaf", Vector3.ZERO, Vector3(0, 0, 1), "translate", LEAF_RISE)
	lf.use("paint_yellow", "form")
	var w := GATE_HALF - 0.04
	lf.box_lh(Vector3(-0.02, -w, 0.03), Vector3(0.02, -w + 0.04, LEAF_H))
	lf.box_lh(Vector3(-0.02, w - 0.04, 0.03), Vector3(0.02, w, LEAF_H))
	lf.box_lh(Vector3(-0.02, -w, 0.03), Vector3(0.02, w, 0.08))
	lf.box_lh(Vector3(-0.02, -w, LEAF_H - 0.05), Vector3(0.02, w, LEAF_H))
	lf.use("galvanised", "form")
	lf.box_lh(Vector3(-0.01, -w + 0.04, 0.08), Vector3(0.01, w - 0.04, LEAF_H - 0.05))

## A call station on the gate's post: a yellow box, its call button and the "cab here" lamp.
static func lift_call(_part: String, g) -> void:
	var m = g.m
	m.use("paint_yellow", "form")
	m.box_lh(Vector3(-0.04, -0.07, 1.05), Vector3(0.04, 0.07, 1.33))
	m.use("paint_green", "form")
	m.cyl(Vector3(-0.04, 0.0, 1.22), Vector3(-0.055, 0.0, 1.22), 0.02, -1.0, 10)
	m.use("paint_white", "form")
	m.cyl(Vector3(-0.04, 0.0, 1.13), Vector3(-0.05, 0.0, 1.13), 0.012, -1.0, 8)

## A code riding on the cab: drawn by the cab.
static func lift_unit(_part: String, _g) -> void:
	pass

## A mesh panel in a frame from a to b at height z0 to z1, solid.
static func _panel(g, a: Vector2, b: Vector2, z0: float, z1: float) -> void:
	var m = g.m
	var len := a.distance_to(b)
	var c := (a + b) * 0.5
	var d := Vector3(b.x - a.x, b.y - a.y, 0).normalized()
	var along := Basis(d.cross(Vector3(0, 0, 1)), d, Vector3(0, 0, 1))
	m.use("paint_frame", "form")
	for p in [a, b]:
		m.box_lh(Vector3(p.x - 0.03, p.y - 0.03, z0), Vector3(p.x + 0.03, p.y + 0.03, z1))
	m.box(Vector3(c.x, c.y, z1 - 0.02), Vector3(0.04, len, 0.04), along)
	m.use("galvanised", "form")
	m.box(Vector3(c.x, c.y, (z0 + z1) * 0.5), Vector3(0.015, len, z1 - z0 - 0.1), along)
	g.solid_obox(Vector3(c.x, c.y, (z0 + z1) * 0.5), Vector3(0.06, len, z1 - z0), along)
