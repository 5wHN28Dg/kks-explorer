## The water treatment plant's parts (docs/PLANT3D.md §18.6, docs/plant3d/WATER-TREATMENT.md): screens, clarifiers and
## the thickener, the gravity filter bank, cartridge filters, RO trains, the degasser, mixed beds, dosing skids and
## their metering pumps, chemical tanks in their bunds, the filter press, the sample panel, the lab bench and
## agitators. Sizes are round, typical values (kit/README.md "Tables": water treatment). Every piece is drawn with the
## kit's materials (the one lit shader and vertex format of decision 0060): nothing here adds a pipeline.
extends RefCounted

const C = preload("res://kit/parts_common.gd")

## The clarifier's and the thickener's wall: 0.3 m of concrete; the water stands this far under the wall's top.
const WALL := 0.3
const FREEBOARD := 0.35
## The bridge's deck reaches this far beyond the wall: the landing at the top of its stair.
const BRIDGE_OUT := 1.6

## A circular solids-contact clarifier (or, with `thickener`, a sludge thickener): its concrete tank standing on the
## ground, the launder ring inside the wall, the steel centre well (the reaction zone), the outlet box, and (with
## `bridge`) the bridge's girders from the centre over the wall along -x, with the rake's drive at the centre. The
## bridge's deck is a platform of the content (walkable: PLANT3D.md §5), at the wall's top + 0.6 m, and reaches
## BRIDGE_OUT beyond the wall, where its stair arrives.
static func clarifier(part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 17 if part == "clarifier" else 10)
	var H: float = g.num("height", 5.5 if part == "clarifier" else 4.5)
	var r := d * 0.5
	var n: int = m.segs(r + WALL, 16, 64)
	m.use("concrete", "form")
	m.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.15), r + WALL + 0.25, -1.0, n)      # the base's footing
	m.tube(Vector3(0, 0, 0), Vector3(0, 0, H), r + WALL, r, n)
	m.use("water", "identify")
	m.disk(Vector3(0, 0, H - FREEBOARD), Vector3(0, 0, 1), r, n)
	# the launder: a channel round the inside of the wall, its inner weir wall a little under the water
	m.use("concrete", "form")
	m.tube(Vector3(0, 0, H - FREEBOARD - 0.7), Vector3(0, 0, H - FREEBOARD + 0.05), r - 0.6, r - 0.75, n)
	m.cyl(Vector3(0, 0, H - FREEBOARD - 0.8), Vector3(0, 0, H - FREEBOARD - 0.7), r, r, n, false)
	m.use("paint_darkgrey", "detail", 0.02)   # the V-notch weir plate's top edge
	m.tube(Vector3(0, 0, H - FREEBOARD + 0.05), Vector3(0, 0, H - FREEBOARD + 0.12), r - 0.6, r - 0.63, n)
	# the centre well (the reaction and flocculation zone of a solids-contact clarifier)
	var rc := maxf(r * 0.28, 0.8)
	m.use("paint_darkgrey", "identify")
	m.tube(Vector3(0, 0, maxf(0.6, H - 3.2)), Vector3(0, 0, H + 0.25), rc, rc - 0.03, m.segs(rc, 16, 40))
	if part == "thickener":
		# the thickened sludge's cone at the floor and the picket-fence rake's posts (seen through the water)
		m.use("concrete", "form")
		m.cyl(Vector3(0, 0, 0.15), Vector3(0, 0, 0.9), r, rc * 0.6, n, false)
	# the outlet box on the wall's outside (-y), the pipe's nozzle on it
	m.use("concrete", "form")
	m.box_lh(Vector3(-0.6, -r - WALL - 0.7, H - 1.4), Vector3(0.6, -r - WALL, H - 0.1))
	m.box_lh(Vector3(-0.35, -r - WALL - 0.7, 0), Vector3(0.35, -r - WALL - 0.3, H - 1.4))
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("outlet", {})
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get("outlet", clampf(d * 0.025, 0.15, 0.6))
		C.nozzle(m, Vector3(p.x, -r - WALL - 0.65, p.z), p, od, "pipe_water")
	if g.p.get("bridge", true):
		# two girders from past the centre over the wall along -x, out to the landing a stair reaches (the deck on
		# them is the content's platform, BRIDGE_OUT beyond the wall), two posts under the landing; the drive
		m.use("paint_grey", "form")
		var xo := -(r + WALL + BRIDGE_OUT)
		for s: float in [-1.0, 1.0]:
			m.box_lh(Vector3(xo, 0.62 * s - 0.08, H + 0.08), Vector3(1.4, 0.62 * s + 0.08, H + 0.5))
			m.box_lh(Vector3(-1.4, 1.3 * s - 0.08, H + 0.08), Vector3(1.4, 1.3 * s + 0.08, H + 0.5))
			m.box_lh(Vector3(xo, 0.62 * s - 0.1, 0), Vector3(xo + 0.2, 0.62 * s + 0.1, H + 0.08))
		m.box_lh(Vector3(-r - WALL, -0.75, H), Vector3(-r - WALL + 0.4, 0.75, H + 0.08))   # the bearing on the wall
		var top := H + 0.6
		m.use("paint_motor", "identify")   # the rake's drive: a gear head and its motor on the deck at the centre
		m.cyl(Vector3(0, 0, top), Vector3(0, 0, top + 0.55), 0.55, -1.0, 24)
		m.cyl(Vector3(0, 0, top + 0.55), Vector3(0, 0, top + 1.25), 0.2, -1.0, 16)
		m.use("paint_darkgrey", "form")   # the drive shaft down to the rake's arm under the water
		m.cyl(Vector3(0, 0, 0.6), Vector3(0, 0, top), 0.12, -1.0, 12, false)
		g.solid_box(Vector3(-0.6, -0.6, H), Vector3(0.6, 0.6, top + 1.25))
	g.plate("wall", Vector3(r + WALL + 0.01, 0, 1.6), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, H), r + WALL)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## The sludge thickener: a clarifier's tank, bridge and drive, with the thickened sludge's cone at its floor.
static func thickener(part: String, g) -> void:
	clarifier(part, g)

## A bank of gravity filters (rapid sand and anthracite, WATER-TREATMENT §3 #5): `cells` concrete cells in two rows
## along y, `length` long, each row `width` across, the pipe gallery between the rows (open at both ends: a walker
## goes in under the operating deck, which is the content's platform at the bank's top). In every cell the water
## over its bed and its wash troughs; in the gallery the inlet channel's pipe under the deck, the filtered water
## header along the floor with each cell's outlet branch (the valves on them are coded parts of their own), the air
## scour header.
static func filter_bank(_part: String, g) -> void:
	var m = g.m
	var cells := int(g.num("cells", 6))
	var L: float = g.num("length", 16.5)
	var W: float = g.num("width", 5)
	var G: float = g.num("gallery", 3.5)
	var H: float = g.num("height", 4.5)
	var t := 0.3
	var per := [int(ceil(cells / 2.0)), cells / 2]   # the +x row, the -x row
	m.use("concrete", "form")
	for k in 2:
		var s := 1.0 if k == 0 else -1.0
		var x0 := G * 0.5
		var x1 := G * 0.5 + W + 2.0 * t
		var nk: int = per[k]
		if nk == 0:
			continue
		var lo := Vector3(minf(x0 * s, x1 * s), -L * 0.5, 0)
		var hi := Vector3(maxf(x0 * s, x1 * s), L * 0.5, H)
		# the row's outer walls (inner side, outer side, both ends) and the walls between its cells
		m.box_lh(Vector3(lo.x, lo.y, 0), Vector3(lo.x + t, hi.y, H))
		m.box_lh(Vector3(hi.x - t, lo.y, 0), Vector3(hi.x, hi.y, H))
		m.box_lh(Vector3(lo.x + t, lo.y, 0), Vector3(hi.x - t, lo.y + t, H))
		m.box_lh(Vector3(lo.x + t, hi.y - t, 0), Vector3(hi.x - t, hi.y, H))
		var cl := (L - t) / nk
		for i in range(1, nk):
			var y := -L * 0.5 + cl * i + t * 0.5
			m.box_lh(Vector3(lo.x + t, y - t * 0.5, 0), Vector3(hi.x - t, y + t * 0.5, H))
		# the cells' floors under the water, the water and two wash troughs across each cell
		for i in nk:
			var ya := -L * 0.5 + t + cl * i
			var yb := ya + cl - t
			m.use("water", "identify")
			m.box_lh(Vector3(lo.x + t, ya, H - 0.62), Vector3(hi.x - t, yb, H - 0.6))
			m.use("concrete", "form")
			for q: float in [0.33, 0.67]:
				var yq := lerpf(ya, yb, q)
				m.box_lh(Vector3(lo.x + t, yq - 0.22, H - 1.0), Vector3(hi.x - t, yq + 0.22, H - 0.5))
			# the cell's outlet into the gallery: a branch from the header (its valve is a part of its own, coded)
			var yc := (ya + yb) * 0.5
			var xin := G * 0.5 * s
			m.use("pipe_water", "form")
			m.cyl(Vector3(xin, yc, 0.8), Vector3(0.3 * s, yc, 0.8), 0.13, -1.0, 12, false)
			# the air scour's drop into the cell
			m.use("pipe_air", "form")
			m.cyl(Vector3(xin - 0.25 * s, yc - 0.5, 2.3), Vector3(xin, yc - 0.5, 2.3), 0.07, -1.0, 8, false)
		m.use("concrete", "form")
	# the gallery's pipes: the filtered water header along the floor out of the south end, the inlet pipe under the
	# deck from the north end, the air scour header along the -x wall
	var out_spec: Dictionary = g.ctx.get("nozzles", {}).get("outlet", {})
	var in_spec: Dictionary = g.ctx.get("nozzles", {}).get("inlet", {})
	var od_out: float = g.ctx.get("used", {}).get("outlet", 0.32)
	var od_in: float = g.ctx.get("used", {}).get("inlet", 0.41)
	var p_out: Vector3 = Vector3(0, -L * 0.5 - 0.6, 0.8) if out_spec.is_empty() else g.nozzle(out_spec)
	var p_in: Vector3 = Vector3(0, L * 0.5 + 0.6, H - 0.7) if in_spec.is_empty() else g.nozzle(in_spec)
	m.use("pipe_water", "form")
	m.cyl(Vector3(0, L * 0.5 - 0.4, p_out.z), Vector3(0, -L * 0.5 - 0.1, p_out.z), od_out * 0.5, -1.0, 0, false)
	m.cyl(Vector3(0, L * 0.5 + 0.1, p_in.z), Vector3(0, -L * 0.5 + 0.4, p_in.z), od_in * 0.5, -1.0, 0, true)
	C.nozzle(m, Vector3(0, -L * 0.5 - 0.1, p_out.z), p_out, od_out, "pipe_water")
	C.nozzle(m, Vector3(0, L * 0.5 + 0.1, p_in.z), p_in, od_in, "pipe_water")
	m.use("pipe_air", "form")
	m.cyl(Vector3(-G * 0.5 + 0.3, L * 0.5, 2.3), Vector3(-G * 0.5 + 0.3, -L * 0.5, 2.3), 0.1, -1.0, 12)
	m.use("pipe_water", "form")   # the inlet's drops into each cell's channel (both rows), over the walls' tops
	var nn: int = per[0]
	for i in nn:
		var yc := -L * 0.5 + (L / nn) * (i + 0.5)
		for s: float in [1.0, -1.0]:
			m.cyl(Vector3(0, yc, p_in.z), Vector3(G * 0.5 * s, yc, p_in.z), 0.1, -1.0, 10, false)
	g.plate("end", Vector3(G * 0.5 + t + W * 0.5, -L * 0.5 - 0.01, 1.6), Vector3(0, -1, 0), "large")
	g.solid_box(Vector3(G * 0.5, -L * 0.5, 0), Vector3(G * 0.5 + W + 2.0 * t, L * 0.5, H))
	if per[1] > 0:
		g.solid_box(Vector3(-G * 0.5 - W - 2.0 * t, -L * 0.5, 0), Vector3(-G * 0.5, L * 0.5, H))
	g.axis_line = [Vector3(0, -L * 0.5, 0), Vector3(0, L * 0.5, 0)]

## A cartridge filter housing (5 µm, WATER-TREATMENT §3 #8): a stainless vessel on three legs, its swing-bolted lid
## with the davit that lifts it, the inlet high on the -x side and the outlet low on the +x side, the differential
## pressure gauge.
static func cartridge_housing(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 0.7)
	var H: float = g.num("height", 1.8)
	var r := d * 0.5
	m.use("steel", "form")
	for k in 3:
		var a := TAU * (k + 0.25) / 3.0
		var p := Vector3(cos(a), sin(a), 0) * r * 0.85
		m.cyl(p, p + Vector3(0, 0, 0.55), 0.03, -1.0, 6)
	m.use("steel", "identify")
	m.dish(Vector3(0, 0, 0.55), Vector3(0, 0, -1), r, r * 0.3, 0, 4)
	m.cyl(Vector3(0, 0, 0.55), Vector3(0, 0, H - 0.15), r, -1.0, 0, false)
	m.cyl(Vector3(0, 0, H - 0.15), Vector3(0, 0, H - 0.08), r + 0.05)             # the lid's flange
	m.dish(Vector3(0, 0, H - 0.08), Vector3(0, 0, 1), r + 0.02, r * 0.35, 0, 4)
	m.use("steel_bolt", "detail", 0.03)
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var p := Vector3(cos(a), sin(a), 0) * (r + 0.04)
		m.cyl(p + Vector3(0, 0, H - 0.2), p + Vector3(0, 0, H - 0.03), 0.012, -1.0, 6)
	m.use("paint_yellow", "form")   # the davit: a post with an arm over the lid
	m.cyl(Vector3(-r - 0.08, -r * 0.4, 0.5), Vector3(-r - 0.08, -r * 0.4, H + 0.55), 0.035, -1.0, 8)
	m.cyl(Vector3(-r - 0.08, -r * 0.4, H + 0.5), Vector3(0, 0, H + 0.5), 0.03, -1.0, 8)
	for n in ["inlet", "outlet"]:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, clampf(d * 0.2, 0.06, 0.3))
		C.nozzle(m, Vector3(signf(p.x) * r * 0.8, p.y, p.z), p, od, "steel")
	# the differential pressure gauge on the front, on its two impulse lines
	m.use("steel", "detail", 0.02)
	m.cyl(Vector3(0, r, H * 0.75), Vector3(0, r + 0.15, H * 0.75), 0.01, -1.0, 6)
	m.cyl(Vector3(0, r, H * 0.35), Vector3(0, r + 0.15, H * 0.35), 0.01, -1.0, 6)
	m.cyl(Vector3(0, r + 0.15, H * 0.35), Vector3(0, r + 0.15, H * 0.75), 0.01, -1.0, 6)
	m.use("chrome", "identify")
	m.cyl(Vector3(0, r + 0.15, H * 0.55), Vector3(0, r + 0.2, H * 0.55), 0.06, -1.0, 16)
	m.use("dial", "identify")
	m.disk(Vector3(0, r + 0.201, H * 0.55), Vector3(0, 1, 0), 0.05, 16)
	g.plate("side", Vector3(0, r + 0.01, 0.75), Vector3(0, 1, 0), "small")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, H), r)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## A reverse osmosis train (WATER-TREATMENT §3 #9): `stage1` + `stage2` pressure vessels of `elements` elements each
## (8-inch, 1.016 m), horizontal, in columns three high on a galvanised rack along y; the feed manifold at the south
## end, permeate and concentrate manifolds at the north end; the train's local panel on the +x side.
static func ro_train(_part: String, g) -> void:
	var m = g.m
	var s1 := int(g.num("stage1", 6))
	var s2 := int(g.num("stage2", 3))
	var el := int(g.num("elements", 6))
	var n := s1 + s2
	var Lv := el * 1.016 + 0.4      # a vessel with its end caps
	var rv := 0.13
	var rows := mini(3, n)
	var cols := int(ceil(float(n) / rows))
	var dx := 0.36
	var dz := 0.42
	var z0 := 0.55
	var W := cols * dx + 0.2
	var x0 := -W * 0.5 + 0.1 + dx * 0.5
	var Hr := z0 + (rows - 1) * dz + 0.35
	var ya := -Lv * 0.5 - 0.15
	var yb := Lv * 0.5 + 0.15
	# the rack: posts at both ends and at the vessels' support points, rails at each row
	m.use("galvanised", "form")
	for y: float in [ya, -Lv * 0.25, Lv * 0.25, yb]:
		for x: float in [-W * 0.5, W * 0.5]:
			m.box_lh(Vector3(x - 0.04, y - 0.04, 0), Vector3(x + 0.04, y + 0.04, Hr))
		for row in rows:
			var z := z0 + row * dz - rv - 0.03
			m.box_lh(Vector3(-W * 0.5, y - 0.03, z - 0.05), Vector3(W * 0.5, y + 0.03, z))
	for x: float in [-W * 0.5, W * 0.5]:
		m.box_lh(Vector3(x - 0.04, ya, 0.08), Vector3(x + 0.04, yb, 0.16))
	m.use("concrete", "form")
	m.box_lh(Vector3(-W * 0.5 - 0.15, ya - 0.15, 0), Vector3(W * 0.5 + 0.15, yb + 0.15, 0.08))
	# the vessels: white FRP shells with their dark end caps; first stage below, second above
	for i in n:
		var col := i / rows
		var row := i % rows
		var x := x0 + col * dx
		var z := z0 + row * dz
		m.use("paint_white", "identify")
		m.cyl(Vector3(x, -Lv * 0.5 + 0.12, z), Vector3(x, Lv * 0.5 - 0.12, z), rv, -1.0, 16, false)
		m.use("paint_darkgrey", "identify")
		m.cyl(Vector3(x, -Lv * 0.5, z), Vector3(x, -Lv * 0.5 + 0.12, z), rv + 0.015, -1.0, 16)
		m.cyl(Vector3(x, Lv * 0.5 - 0.12, z), Vector3(x, Lv * 0.5, z), rv + 0.015, -1.0, 16)
		m.use("steel", "detail", 0.03)   # the permeate port on each end cap
		m.cyl(Vector3(x, Lv * 0.5, z), Vector3(x, Lv * 0.5 + 0.08, z), 0.025, -1.0, 6)
	# the manifolds: feed (south), concentrate and permeate (north), vertical, and their headers along the rack's foot
	var spec_f: Dictionary = g.ctx.get("nozzles", {}).get("feed_in", {})
	var spec_p: Dictionary = g.ctx.get("nozzles", {}).get("permeate_out", {})
	var spec_c: Dictionary = g.ctx.get("nozzles", {}).get("concentrate_out", {})
	m.use("steel", "form")
	var zt := z0 + (rows - 1) * dz
	m.cyl(Vector3(x0, ya, 0.3), Vector3(x0 + (cols - 1) * dx, ya, 0.3), 0.06, -1.0, 12)
	m.cyl(Vector3(x0, yb, 0.3), Vector3(x0 + (cols - 1) * dx, yb, 0.3), 0.05, -1.0, 12)
	for col in cols:
		var x := x0 + col * dx
		m.cyl(Vector3(x, ya, 0.3), Vector3(x, ya, zt), 0.04, -1.0, 8, false)
		m.cyl(Vector3(x, yb, 0.3), Vector3(x, yb, zt), 0.035, -1.0, 8, false)
	m.use("plain", "form")   # permeate: a PVC manifold
	m.cyl(Vector3(x0, yb + 0.12, 0.55), Vector3(x0 + (cols - 1) * dx, yb + 0.12, 0.55), 0.045, -1.0, 10)
	for spec_n in [["feed_in", spec_f, Vector3(x0, ya, 0.3)], ["permeate_out", spec_p, Vector3(x0, yb + 0.12, 0.55)],
			["concentrate_out", spec_c, Vector3(x0 + (cols - 1) * dx, yb, 0.3)]]:
		var spec: Dictionary = spec_n[1]
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var from: Vector3 = spec_n[2]
		m.use("steel", "form")
		m.cyl(from, Vector3(p.x, from.y, from.z), 0.04, -1.0, 8)
		C.nozzle(m, Vector3(p.x, from.y, p.z), p, g.ctx.get("used", {}).get(spec_n[0], 0.1), "steel")
	# the train's local panel with its pressure gauges, on the +x side at the feed end
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(W * 0.5 + 0.1, ya + 0.2, 0.3), Vector3(W * 0.5 + 0.35, ya + 1.4, 2.0))
	m.use("dial", "identify")
	for k in 4:
		m.disk(Vector3(W * 0.5 + 0.351, ya + 0.4 + k * 0.27, 1.5), Vector3(1, 0, 0), 0.06, 14)
	m.use("glass", "identify")
	m.box(Vector3(W * 0.5 + 0.352, ya + 0.8, 1.05), Vector3(0.004, 0.5, 0.25))
	g.plate("frame", Vector3(W * 0.5 + 0.36, ya + 0.8, 1.85), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5, ya, 0), Vector3(W * 0.5 + 0.35, yb, Hr))
	g.axis_line = [Vector3(0, ya, 0), Vector3(0, yb, 0)]

## A forced-draft degasser (WATER-TREATMENT §3 #10): an FRP tower on a concrete plinth, its vent hood on top, two
## access manholes, the inlet high on the -y side, the outlet low on the +y side, the blower's duct at the foot on the
## +x side (the blower itself is a `compressor_skid` with its own code), a caged ladder.
static func degasser(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 1.8)
	var H: float = g.num("height", 7)
	var r := d * 0.5
	m.use("concrete", "form")
	m.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.6), r + 0.25, -1.0, m.segs(r + 0.25, 16, 48))
	m.use("paint_ct", "identify")
	m.cyl(Vector3(0, 0, 0.6), Vector3(0, 0, H), r, -1.0, 0, false)
	m.lathe(Vector3(0, 0, H), Vector3(0, 0, 1), [[r + 0.03, 0.0], [r * 0.35, r * 0.4]], 0, false)
	m.use("paint_darkgrey", "detail", 0.04)   # the shell's flanged joints
	var z := 2.0
	while z < H - 0.4:
		m.cyl(Vector3(0, 0, z - 0.03), Vector3(0, 0, z + 0.03), r + 0.04, -1.0, m.segs(r, 16, 40))
		z += 1.8
	m.use("paint_ct", "identify")   # the vent and its rain hood
	m.cyl(Vector3(0, 0, H + r * 0.4), Vector3(0, 0, H + r * 0.4 + 0.6), r * 0.3, -1.0, 16, false)
	m.lathe(Vector3(0, 0, H + r * 0.4 + 0.6), Vector3(0, 0, 1), [[r * 0.5, 0.0], [0.0, 0.25]], 16, true)
	m.use("paint_darkgrey", "identify")   # the manholes
	for zz: float in [1.4, H - 1.2]:
		m.cyl(Vector3(r * 0.71, -r * 0.71, zz), Vector3(r * 0.71 + 0.12, -r * 0.71 - 0.12, zz), 0.25, -1.0, 16)
	for n in ["inlet", "outlet"]:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, clampf(d * 0.08, 0.08, 0.3))
		C.nozzle(m, Vector3(p.x, signf(p.y) * r * 0.8, p.z), p, od, "paint_ct")
	# the blower's duct into the tower's foot on the +x side (the blower is a part of its own, coded, at the duct's end)
	m.use("paint_ct", "form")
	m.box_lh(Vector3(r * 0.8, 0.05, 0.75), Vector3(r + 0.75, 0.45, 1.15))
	C.ladder(m, Vector3(-r - 0.45, 0, 0.6), H, Vector2(1, 0))
	g.plate("side", Vector3(0, r + 0.01, 1.8), Vector3(0, 1, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, H), r + 0.25)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## A mixed bed ion exchanger (WATER-TREATMENT §3 #11): a rubber-lined steel vessel on four legs, dished heads, its
## top manway, two sight glasses (the resin's interface after separation), and the frontal pipework (-y) with its
## valve nest: inlet high, outlet low.
static func ion_exchanger(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 2)
	var H: float = g.num("height", 3.2)
	var r := d * 0.5
	var hd := d * 0.2
	var zb := 0.6 + hd
	m.use("paint_darkgrey", "form")
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := Vector3(cos(a), sin(a), 0) * r * 0.75
		m.box_lh(p - Vector3(0.07, 0.07, 0), p + Vector3(0.07, 0.07, zb + 0.2))
		m.box_lh(p - Vector3(0.15, 0.15, 0), p + Vector3(0.15, 0.15, 0.02))
	m.use("paint_tank", "identify")
	m.dish(Vector3(0, 0, zb), Vector3(0, 0, -1), r, hd, 0, 5)
	m.cyl(Vector3(0, 0, zb), Vector3(0, 0, zb + H), r, -1.0, 0, false)
	m.dish(Vector3(0, 0, zb + H), Vector3(0, 0, 1), r, hd, 0, 5)
	m.use("steel", "identify")
	m.cyl(Vector3(r * 0.3, 0, zb + H + hd * 0.7), Vector3(r * 0.3, 0, zb + H + hd + 0.25), 0.28, -1.0, 16)
	m.use("glass", "identify")   # the sight glasses, at the resin's levels
	for zz: float in [zb + H * 0.35, zb + H * 0.6]:
		m.cyl(Vector3(r * 0.5, -r * 0.87, zz), Vector3(r * 0.5 * 1.08, -r * 0.87 * 1.08 - 0.06, zz), 0.09, -1.0, 14)
	# the frontal pipework: a vertical header with five valves (inlet, outlet, backwash, regenerants, air), and the
	# inlet and outlet nozzles where the plant's pipes join it
	var yf := -r - 0.5
	m.use("steel", "form")
	m.cyl(Vector3(0, yf, 0.5), Vector3(0, yf, zb + H), 0.06, -1.0, 12)
	m.cyl(Vector3(0, yf, zb + H), Vector3(0, -r * 0.6, zb + H), 0.06, -1.0, 12)
	m.cyl(Vector3(0, yf, 0.5), Vector3(0, -r * 0.6, 0.5), 0.06, -1.0, 12)
	for k in 5:
		var zz := lerpf(0.9, zb + H - 0.3, k / 4.0)
		m.use("paint_valve", "identify")
		m.box(Vector3(0, yf, zz), Vector3(0.18, 0.18, 0.2))
		m.use("paint_actuator", "identify")
		m.box(Vector3(0, yf - 0.2, zz), Vector3(0.18, 0.22, 0.16))
	for n in ["inlet", "outlet"]:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		m.use("steel", "form")
		m.cyl(Vector3(0, yf, p.z), Vector3(p.x, yf, p.z), 0.05, -1.0, 10, false)
		C.nozzle(m, Vector3(p.x, yf, p.z), p, g.ctx.get("used", {}).get(n, 0.1), "steel")
	g.plate("front", Vector3(-r * 0.6, -r * 0.8, 1.7), Vector3(-0.6, -0.8, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, zb + H + hd), r)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, zb + H)]

## A chemical dosing skid (WATER-TREATMENT §3: coagulant, polymer, hypochlorite, SBS, antiscalant, acid): a bunded
## steel skid with the day tank (polyethylene) at its -y end, its level gauge and calibration column, the plinths the
## metering pumps stand on (the pumps are parts of their own: `metering_pump`, with their codes), the discharge
## header to the outlet at the +y end.
static func dosing_skid(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 2.4)
	var W: float = g.num("width", 1.2)
	var V: float = g.num("tank_l", 1000) / 1000.0
	var td := clampf(pow(4.0 * V / (1.3 * PI), 1.0 / 3.0), 0.4, minf(W, L * 0.6))
	var th := clampf(V / (PI * td * td * 0.25), 0.4, 2.6)
	var tr := td * 0.5
	m.use("paint_darkgrey", "form")   # the skid's drip tray (bunded)
	m.box_lh(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, 0.06))
	for s: float in [-1.0, 1.0]:
		m.box_lh(Vector3(-W * 0.5, s * L * 0.5 - 0.03, 0.06), Vector3(W * 0.5, s * L * 0.5 + 0.03, 0.18))
		m.box_lh(Vector3(s * W * 0.5 - 0.03, -L * 0.5, 0.06), Vector3(s * W * 0.5 + 0.03, L * 0.5, 0.18))
	var yt := -L * 0.5 + tr + 0.08
	m.use("paint_white", "identify")
	m.cyl(Vector3(0, yt, 0.06), Vector3(0, yt, 0.06 + th), tr, -1.0, m.segs(tr, 16, 32))
	m.dish(Vector3(0, yt, 0.06 + th), Vector3(0, 0, 1), tr, tr * 0.2, m.segs(tr, 16, 32), 3)
	m.use("paint_darkgrey", "identify")   # its lid and level gauge strip
	m.cyl(Vector3(0, yt, 0.06 + th + tr * 0.18), Vector3(0, yt, 0.06 + th + tr * 0.18 + 0.05), 0.12, -1.0, 12)
	m.use("glass", "identify")
	m.box(Vector3(tr * 0.72, yt - tr * 0.72, 0.06 + th * 0.5), Vector3(0.03, 0.03, th * 0.8), Basis(Vector3(0, 0, 1), PI * 0.25))
	m.use("glass", "identify")   # the calibration column beside the tank
	m.cyl(Vector3(-W * 0.35, yt + tr + 0.15, 0.3), Vector3(-W * 0.35, yt + tr + 0.15, 1.3), 0.04, -1.0, 10)
	# the pumps' plinths along the +y half, the suction line from the tank, the discharge header to the outlet
	m.use("paint_darkgrey", "form")
	var y0 := yt + tr + 0.3
	m.box_lh(Vector3(-W * 0.3, y0, 0.06), Vector3(W * 0.3, L * 0.5 - 0.15, 0.2))
	m.use("plain", "form")   # PVC-U lines
	m.cyl(Vector3(0, yt + tr, 0.3), Vector3(0, L * 0.5 - 0.2, 0.3), 0.025, -1.0, 8)
	m.cyl(Vector3(W * 0.38, y0, 0.45), Vector3(W * 0.38, L * 0.5, 0.45), 0.02, -1.0, 8)
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("outlet", {})
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		m.cyl(Vector3(W * 0.38, L * 0.5, 0.45), Vector3(p.x, L * 0.5, p.z), 0.02, -1.0, 8)
		C.nozzle(m, Vector3(p.x, L * 0.5, p.z), p, g.ctx.get("used", {}).get("outlet", 0.04), "plain")
	g.plate("front", Vector3(0, yt - tr - 0.01, 0.06 + th * 0.6), Vector3(0, -1, 0), "small")
	g.solid_cyl(Vector3(0, yt, 0), Vector3(0, yt, 0.06 + th), tr)
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, 0.18))
	g.axis_line = [Vector3(0, -L * 0.5, 0), Vector3(0, L * 0.5, 0)]

## A metering pump (diaphragm): its motor along -x, the gearbox with the stroke knob, the pump head on the +x side
## with its suction and discharge valves. The origin is on its plinth.
static func metering_pump(_part: String, g) -> void:
	var m = g.m
	var kw: float = g.num("kw", 0.37)
	var md := C.motor_dims(kw)
	var h: float = md.h + 0.06
	m.use("paint_darkgrey", "form")
	m.box_lh(Vector3(-0.32, -0.12, 0), Vector3(0.28, 0.12, 0.04))
	C.motor_h(m, Vector3(-0.08, 0, h), Vector3(1, 0, 0), kw, 0.04)
	m.use("paint_grey", "identify")   # the gearbox
	m.box_lh(Vector3(-0.08, -0.11, 0.04), Vector3(0.12, 0.11, h + 0.14))
	m.use("paint_red", "identify")   # the stroke length knob
	m.cyl(Vector3(0.02, 0, h + 0.14), Vector3(0.02, 0, h + 0.2), 0.04, -1.0, 12)
	m.use("plain", "identify")   # the pump head (PVDF) and its valves
	m.cyl(Vector3(0.12, 0, h), Vector3(0.2, 0, h), 0.075, -1.0, 16)
	m.cyl(Vector3(0.2, 0, h - 0.12), Vector3(0.2, 0, h + 0.12), 0.025, -1.0, 8)
	g.plate("side", Vector3(-0.02, -0.111, h * 0.6), Vector3(0, -1, 0), "small")
	g.solid_box(Vector3(-0.32, -0.12, 0), Vector3(0.28, 0.12, h + 0.2))
	g.axis_line = [Vector3(-0.3, 0, h), Vector3(0.25, 0, h)]

## A chemical storage tank (FRP or polyethylene) in its concrete bund (the bund holds the tank's contents and 10 %:
## WATER-TREATMENT §4 GCP, GNR): the tank, its vent and level indicator, a caged ladder on tall tanks, the outlet at
## its foot on the +y side through the bund wall.
static func chemical_tank(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 2.5)
	var H: float = g.num("height", 3.5)
	var r := d * 0.5
	if g.p.get("bund", true):
		var b := r + 0.9
		var bh := clampf(H * 0.3, 0.6, 1.2)
		m.use("concrete", "form")
		m.box_lh(Vector3(-b, -b, 0), Vector3(b, b, 0.1))
		for s: float in [-1.0, 1.0]:
			m.box_lh(Vector3(-b, s * b - 0.1, 0), Vector3(b, s * b + 0.1, bh))
			m.box_lh(Vector3(s * b - 0.1, -b, 0), Vector3(s * b + 0.1, b, bh))
		g.solid_box(Vector3(-b - 0.1, -b - 0.1, 0), Vector3(b + 0.1, b + 0.1, bh))
	m.use("concrete", "form")
	m.cyl(Vector3(0, 0, 0.1), Vector3(0, 0, 0.3), r + 0.15, -1.0, m.segs(r, 16, 48))
	m.use("paint_tank", "identify")
	m.cyl(Vector3(0, 0, 0.3), Vector3(0, 0, H), r, -1.0, 0, false)
	m.dish(Vector3(0, 0, H), Vector3(0, 0, 1), r, r * 0.25, 0, 4)
	m.use("paint_tank", "detail", 0.04)   # the filament-wound shell's hoops
	var z := 1.0
	while z < H - 0.3:
		m.cyl(Vector3(0, 0, z - 0.02), Vector3(0, 0, z + 0.02), r + 0.012, -1.0, m.segs(r, 16, 40))
		z += 1.0
	m.use("paint_darkgrey", "identify")   # the vent with its goose neck, the level indicator
	m.pipe_path([Vector3(0, r * 0.4, H + r * 0.15), Vector3(0, r * 0.4, H + r * 0.15 + 0.5), Vector3(0, r * 0.4 + 0.3, H + r * 0.15 + 0.5)], 0.05, 0.1)
	m.use("glass", "identify")
	m.box(Vector3(r * 0.71 + 0.05, -r * 0.71 - 0.05, H * 0.5), Vector3(0.05, 0.05, H * 0.8), Basis(Vector3(0, 0, 1), PI * 0.25))
	if H > 2.5:
		C.ladder(m, Vector3(-r - 0.45, 0, 0.3), H, Vector2(1, 0))
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("outlet", {})
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		C.nozzle(m, Vector3(p.x, r * 0.8, p.z), p, g.ctx.get("used", {}).get("outlet", 0.06), "paint_tank")
	g.plate("side", Vector3(r * 0.71 + 0.01, r * 0.71 + 0.01, 1.4), Vector3(0.71, 0.71, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, H), r)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## A filter press (WATER-TREATMENT §3 #14): the fixed head (+y) and the moving head with its hydraulic cylinder
## (-y) on two side bars, the plates hung between them, the whole on a steel stand 1.8 m up so that the cake drops
## into the skip under it; the feed at the fixed head.
static func filter_press(_part: String, g) -> void:
	var m = g.m
	var n := int(g.num("plates", 60))
	var L: float = g.num("length", 6)
	var ps := clampf(L * 0.12 + 0.6, 0.8, 1.6)   # the plates' size
	var z0 := 1.8
	var zc := z0 + ps * 0.5 + 0.1
	m.use("paint_darkgrey", "form")   # the stand
	for y: float in [-L * 0.5 + 0.3, 0.0, L * 0.5 - 0.3]:
		for x: float in [-ps * 0.55, ps * 0.55]:
			m.box_lh(Vector3(x - 0.08, y - 0.08, 0), Vector3(x + 0.08, y + 0.08, z0))
	m.box_lh(Vector3(-ps * 0.6, -L * 0.5, z0 - 0.15), Vector3(-ps * 0.5, L * 0.5, z0))
	m.box_lh(Vector3(ps * 0.5, -L * 0.5, z0 - 0.15), Vector3(ps * 0.6, L * 0.5, z0))
	m.use("paint_motor", "identify")   # the heads and the side bars
	m.box_lh(Vector3(-ps * 0.65, L * 0.5 - 0.35, z0), Vector3(ps * 0.65, L * 0.5, zc + ps * 0.6))
	m.box_lh(Vector3(-ps * 0.65, -L * 0.5, z0), Vector3(ps * 0.65, -L * 0.5 + 0.5, zc + ps * 0.6))
	for x: float in [-ps * 0.6, ps * 0.6]:
		m.box_lh(Vector3(x - 0.06, -L * 0.5 + 0.5, zc + ps * 0.35), Vector3(x + 0.06, L * 0.5 - 0.35, zc + ps * 0.5))
	m.use("steel", "identify")   # the closing cylinder's rod
	m.cyl(Vector3(0, -L * 0.5 + 0.5, zc), Vector3(0, -L * 0.5 + 1.1, zc), 0.08, -1.0, 12)
	m.use("paint_darkgrey", "identify")
	m.box_lh(Vector3(-ps * 0.5, -L * 0.5 + 1.1, zc - ps * 0.5), Vector3(ps * 0.5, -L * 0.5 + 1.2, zc + ps * 0.5))
	# the plates: as many as fit between the moving plate and the fixed head
	var ya := -L * 0.5 + 1.25
	var yb := L * 0.5 - 0.4
	var k := mini(n, int((yb - ya) / 0.05))
	m.use("paint_grey", "identify")
	for i in k:
		var y := lerpf(ya, yb, (i + 0.5) / k)
		m.box(Vector3(0, y, zc), Vector3(ps, (yb - ya) / k * 0.85, ps))
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("feed", {})
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		C.nozzle(m, Vector3(p.x, L * 0.5, p.z), p, g.ctx.get("used", {}).get("feed", 0.1), "paint_motor")
	m.use("paint_yellow", "identify")   # the skip under the press for the cake
	m.box_lh(Vector3(-ps * 0.45, -L * 0.3, 0), Vector3(ps * 0.45, L * 0.3, 1.1))
	m.use("dark", "identify")
	m.box_lh(Vector3(-ps * 0.4, -L * 0.28, 1.0), Vector3(ps * 0.4, L * 0.28, 1.105))
	g.plate("side", Vector3(ps * 0.66, L * 0.5 - 0.2, zc), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-ps * 0.65, -L * 0.5, 0), Vector3(ps * 0.65, L * 0.5, zc + ps * 0.6))
	g.axis_line = [Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc)]

## The WTP's sample panel (WATER-TREATMENT §3 #15): a stainless panel along x, its front at +y: per sample point a
## needle valve, a rotameter and a line into the sink; the analysers (turbidity, SDI, ORP, pH, conductivity, silica)
## in grey cases with their displays above.
static func sample_panel(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 2.4)
	var n := int(g.num("points", 6))
	m.use("steel", "identify")
	m.box_lh(Vector3(-W * 0.5, -0.1, 0), Vector3(W * 0.5, 0.0, 2.1))
	m.box_lh(Vector3(-W * 0.5, 0.0, 0.85), Vector3(W * 0.5, 0.35, 0.95))   # the sink's rim
	m.use("dark", "identify")
	m.box_lh(Vector3(-W * 0.48, 0.02, 0.951), Vector3(W * 0.48, 0.33, 0.952))
	m.use("steel", "form")
	for s: float in [-1.0, 1.0]:
		m.box_lh(Vector3(s * W * 0.5 - 0.04, 0.0, 0), Vector3(s * W * 0.5, 0.35, 0.85))
	for i in n:
		var x := -W * 0.5 + W * (i + 0.5) / n
		m.use("glass", "identify")   # the rotameter
		m.cyl(Vector3(x, 0.05, 1.05), Vector3(x, 0.05, 1.35), 0.018, -1.0, 8)
		m.use("paint_red", "identify")
		m.cyl(Vector3(x, 0.05, 1.18), Vector3(x, 0.05, 1.2), 0.022, -1.0, 8)
		m.use("steel", "detail", 0.02)
		m.cyl(Vector3(x, 0.02, 1.45), Vector3(x, 0.09, 1.45), 0.012, -1.0, 6)
		m.cyl(Vector3(x, 0.05, 0.95), Vector3(x, 0.05, 1.05), 0.006, -1.0, 6)
		m.use("paint_grey", "identify")   # an analyser per point
		m.box_lh(Vector3(x - W * 0.4 / n, 0.0, 1.55), Vector3(x + W * 0.4 / n, 0.16, 1.95))
		m.use("glass", "identify")
		m.box(Vector3(x, 0.161, 1.82), Vector3(W * 0.5 / n, 0.002, 0.12))
	g.plate("front", Vector3(0, 0.01, 2.0), Vector3(0, 1, 0), "small")
	g.solid_box(Vector3(-W * 0.5, -0.1, 0), Vector3(W * 0.5, 0.35, 2.1))
	g.axis_line = [Vector3(-W * 0.5, 0, 1), Vector3(W * 0.5, 0, 1)]

## A laboratory bench along x, against a wall at -y: white cabinets under a dark resin worktop, a sink, and the
## instruments the chemists use (a turbidimeter, a spectrophotometer, a pH and conductivity meter, an SDI kit).
static func lab_bench(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 3)
	m.use("paint_white", "identify")
	m.box_lh(Vector3(-L * 0.5, -0.38, 0.1), Vector3(L * 0.5, 0.32, 0.86))
	m.use("paint_darkgrey", "form")
	m.box_lh(Vector3(-L * 0.5, -0.38, 0), Vector3(L * 0.5, 0.28, 0.1))
	m.use("paint_black", "identify")   # the worktop and the upstand
	m.box_lh(Vector3(-L * 0.5 - 0.02, -0.38, 0.86), Vector3(L * 0.5 + 0.02, 0.37, 0.9))
	m.box_lh(Vector3(-L * 0.5 - 0.02, -0.38, 0.9), Vector3(L * 0.5 + 0.02, -0.35, 1.0))
	m.use("paint_darkgrey", "detail", 0.02)   # the doors' seams and handles
	var nd := maxi(2, int(L / 0.6))
	for i in nd:
		var x := -L * 0.5 + L * (i + 0.5) / nd
		m.box(Vector3(x + L * 0.3 / nd, 0.322, 0.7), Vector3(0.012, 0.012, 0.12))
	m.use("steel", "identify")   # the sink and its tap
	m.box_lh(Vector3(L * 0.5 - 0.65, -0.2, 0.9), Vector3(L * 0.5 - 0.2, 0.2, 0.905))
	m.cyl(Vector3(L * 0.5 - 0.42, -0.3, 0.9), Vector3(L * 0.5 - 0.42, -0.3, 1.25), 0.015, -1.0, 8)
	var inst := [[-L * 0.5 + 0.35, 0.32, 0.25, 0.18, "paint_grey"], [-L * 0.5 + 0.9, 0.5, 0.35, 0.22, "paint_white"],
		[-L * 0.5 + 1.5, 0.25, 0.2, 0.12, "paint_grey"]]
	for it in inst:
		m.use(it[4], "identify")
		m.box_lh(Vector3(it[0] - it[1] * 0.5, -0.25, 0.9), Vector3(it[0] + it[1] * 0.5, -0.25 + it[2], 0.9 + it[3]))
		m.use("glass", "identify")
		m.box(Vector3(it[0], -0.25 + it[2] + 0.001, 0.9 + it[3] * 0.6), Vector3(it[1] * 0.5, 0.002, it[3] * 0.4))
	g.plate("front", Vector3(-L * 0.5 + 0.3, 0.323, 0.75), Vector3(0, 1, 0), "small")
	g.solid_box(Vector3(-L * 0.5, -0.38, 0), Vector3(L * 0.5, 0.37, 0.9))
	g.axis_line = [Vector3(-L * 0.5, 0, 0.9), Vector3(L * 0.5, 0, 0.9)]

## An agitator (a rapid mixer's, the neutralisation pit's): the gear motor on its mounting plate at the origin (on a
## beam or a tank's top), the shaft down `shaft` metres to the impeller of diameter `d` (seen in the water).
static func agitator(_part: String, g) -> void:
	var m = g.m
	var kw: float = g.num("kw", 4)
	var D: float = g.num("d", 1.5)
	var S: float = g.num("shaft", 3)
	m.use("paint_darkgrey", "form")
	m.box_lh(Vector3(-0.4, -0.4, 0), Vector3(0.4, 0.4, 0.05))
	m.use("paint_grey", "identify")   # the gearbox
	m.cyl(Vector3(0, 0, 0.05), Vector3(0, 0, 0.45), 0.3, 0.24, 20)
	C.motor_v(m, Vector3(0, 0, 0.45), kw)
	m.use("steel", "identify")
	m.cyl(Vector3(0, 0, -S), Vector3(0, 0, 0), 0.05, -1.0, 10)
	m.use("steel", "identify")   # the impeller: a hub and four pitched blades
	m.cyl(Vector3(0, 0, -S), Vector3(0, 0, -S + 0.15), 0.1, -1.0, 12)
	for k in 4:
		var a := TAU * k / 4.0
		var dir := Vector3(cos(a), sin(a), 0)
		m.box(Vector3(0, 0, -S + 0.07) + dir * D * 0.27, Vector3(D * 0.4, 0.02, 0.12), Basis(dir, Vector3(-dir.y, dir.x, 0), Vector3(0, 0, 1)) * Basis(Vector3(1, 0, 0), 0.6))
	g.plate("motor", Vector3(0.31, 0, 0.3), Vector3(1, 0, 0), "small")
	g.solid_box(Vector3(-0.4, -0.4, 0), Vector3(0.4, 0.4, 0.6))
	g.axis_line = [Vector3(0, 0, -S), Vector3(0, 0, 1)]

## A bar screen (WATER-TREATMENT §3 #1): flat bars at 75 mm across a channel `width` wide, inclined at 75° from the
## channel's floor `depth` down to the deck, and the raking machine's frame, motor and chute over the deck. The
## origin is on the deck at the channel's centre line; the water flows towards +y.
static func bar_screen(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 3)
	var D: float = g.num("depth", 6)
	var inc := 1.0 / tan(deg_to_rad(75.0))   # metres of +y per metre up
	var nb := int(W / 0.085)
	m.use("steel_dark", "identify")
	for i in nb:
		var x := -W * 0.5 + W * (i + 0.5) / nb
		var a := Vector3(x, -D * inc * 0.5, -D)
		var b := Vector3(x, D * inc * 0.5 + 0.9 * inc, 0.9)
		var c := (a + b) * 0.5
		var dir := (b - a).normalized()
		m.box(c, Vector3(0.012, 0.06, a.distance_to(b)), Basis(Vector3(1, 0, 0), dir.cross(Vector3(1, 0, 0)), dir).orthonormalized())
	m.use("paint_motor", "form")   # the raking machine: two side frames, the head with its motor, the chute
	for s: float in [-1.0, 1.0]:
		m.box_lh(Vector3(s * (W * 0.5 + 0.1) - 0.08, -0.2, 0), Vector3(s * (W * 0.5 + 0.1) + 0.08, 0.9, 3.2))
	m.box_lh(Vector3(-W * 0.5 - 0.2, 0.1, 3.0), Vector3(W * 0.5 + 0.2, 0.9, 3.6))
	C.motor_h(m, Vector3(W * 0.5 + 0.25, 0.5, 3.3), Vector3(-1, 0, 0), 1.5, 3.0)
	m.use("steel", "identify")   # the chute from the head to the skip beside the channel (+x)
	m.box(Vector3(W * 0.5 + 0.7, 0.5, 2.4), Vector3(1.4, 0.6, 0.05), Basis(Vector3(0, 1, 0), 0.5))
	m.use("paint_yellow", "identify")   # the skip for the screenings
	m.box_lh(Vector3(W * 0.5 + 0.6, -0.2, 0), Vector3(W * 0.5 + 1.8, 1.2, 1.0))
	g.plate("side", Vector3(W * 0.5 + 0.19, 0.4, 1.6), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5 - 0.2, -0.2, 0), Vector3(W * 0.5 + 0.2, 0.9, 3.6))
	g.solid_box(Vector3(W * 0.5 + 0.6, -0.2, 0), Vector3(W * 0.5 + 1.8, 1.2, 1.0))
	g.axis_line = [Vector3(0, 0, -D), Vector3(0, 0, 3.6)]

## A travelling band screen (WATER-TREATMENT §3 #1: 9.5 mm mesh): the band between two side frames from the channel's
## floor `depth` down up to its head over the deck, the head's casing with the drive motor, the spray-wash trough.
## Origin on the deck at the channel's centre line; the water flows towards +y.
static func screen_band(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 2)
	var D: float = g.num("depth", 6)
	var kw: float = g.num("motor_kw", 1.5)
	var Hh := 3.0
	m.use("paint_motor", "form")
	for s: float in [-1.0, 1.0]:
		m.box_lh(Vector3(s * (W * 0.5 + 0.1) - 0.1, -0.5, -D), Vector3(s * (W * 0.5 + 0.1) + 0.1, 0.5, Hh))
	m.use("steel_dark", "identify")   # the band's two runs (the mesh) between the frames
	for y: float in [-0.35, 0.35]:
		m.box_lh(Vector3(-W * 0.5, y - 0.01, -D + 0.3), Vector3(W * 0.5, y + 0.01, Hh - 0.4))
	m.use("paint_grey", "identify")   # the head's casing over the deck
	m.box_lh(Vector3(-W * 0.5 - 0.2, -0.6, 1.0), Vector3(W * 0.5 + 0.2, 0.6, Hh + 0.6))
	C.motor_h(m, Vector3(W * 0.5 + 0.25, 0, Hh + 0.2), Vector3(-1, 0, 0), kw, Hh - 0.1)
	m.use("steel", "form")   # the spray header and the debris trough
	m.cyl(Vector3(-W * 0.5 - 0.3, 0.7, Hh), Vector3(W * 0.5 + 0.3, 0.7, Hh), 0.04, -1.0, 8)
	m.box_lh(Vector3(-W * 0.5 - 0.6, 0.65, 1.6), Vector3(W * 0.5 + 0.6, 1.05, 1.9))
	m.use("glass", "identify")   # the inspection window in the casing
	m.box(Vector3(0, -0.601, 2.2), Vector3(W * 0.5, 0.004, 0.5))
	g.plate("side", Vector3(-W * 0.5 - 0.21, -0.2, 1.6), Vector3(-1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5 - 0.2, -0.6, 0), Vector3(W * 0.5 + 0.2, 0.6, Hh + 0.6))
	g.axis_line = [Vector3(0, 0, -D), Vector3(0, 0, Hh)]
