## Pumps, fans, compressors and motors (docs/PLANT3D.md §9 "Rotating"). Every one has a `shaft` node turning about
## its shaft line (kit/README.md "Moving parts"): what a trainee sees turn (a coupling's painted stripe through the
## guard, a fan's blades, a cooling fan under its grille).
extends RefCounted

const C = preload("res://kit/parts_common.gd")
const PUMP_LIFT := 1.6   # (the Workshop) how far a pump's motor is lifted off its baseplate (m)

## A pipe's nominal size for a flow at a velocity (m/s), as the kit's DN table has it.
static func dn_for(g, flow_m3h: float, v: float) -> float:
	var d := sqrt(4.0 * flow_m3h / 3600.0 / (PI * v)) * 1000.0
	var best := 15.0
	for row in g.dn_table:
		best = float(row[0])
		if float(row[1]) >= d:
			break
	return best

static func pump_horizontal(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 3)
	var flow: float = g.num("flow_m3h", 100)
	var head: float = g.num("head_m", 50)
	var kw: float = g.num("motor_kw", 30)
	var zs := 0.6   # the shaft line: the suction nozzle's height (kit.json)
	var y_suc := L * 0.5
	var y_c := L * 0.25   # the casing under the discharge nozzle
	var ds: float = g.od(dn_for(g, flow, 3.0))
	var dd: float = g.od(dn_for(g, flow, 4.5))
	var Rv := clampf(0.1 + 0.0085 * sqrt(flow), 0.12, 0.46)
	var multistage := head > 150.0
	m.use("paint_pump", "identify")
	var y_back: float
	if multistage:
		# a barrel or ring-section casing: a long body, stages marked by rings
		var Rb := clampf(Rv * 0.85 + head / 6000.0, 0.16, 0.5)
		var len_c := clampf(0.4 + head / 1500.0 * 0.9, 0.5, 2.2)
		m.cyl(Vector3(0, y_c + 0.15, zs), Vector3(0, y_c + 0.15 - len_c, zs), Rb)
		m.use("paint_pump", "form")
		var nst := clampi(int(head / 150.0), 2, 10)
		for i in nst:
			var y := y_c + 0.15 - len_c * (i + 0.5) / nst
			m.cyl(Vector3(0, y - 0.02, zs), Vector3(0, y + 0.02, zs), Rb * 1.06, -1.0)
		m.use("paint_pump", "identify")
		m.cyl(Vector3(0, y_c + 0.15, zs), Vector3(0, y_c + 0.25, zs), Rb * 1.15)   # the end covers
		m.cyl(Vector3(0, y_c + 0.15 - len_c - 0.1, zs), Vector3(0, y_c + 0.15 - len_c, zs), Rb * 1.15)
		C.bolt_ring(m, Vector3(0, y_c + 0.2, zs), Vector3(0, 1, 0), Rb * 1.0, 12, 0.02, 0.14)
		y_back = y_c + 0.05 - len_c - 0.1
		for s: float in [-1.0, 1.0]:   # its feet at the shaft line (a hot pump is supported at its centre line)
			m.use("paint_pump", "form")
			m.box_lh(Vector3(Rb * s - 0.08, y_c - 0.1, 0.15), Vector3(Rb * s + 0.08, y_c + 0.1, zs))
			m.box_lh(Vector3(Rb * s - 0.08, y_back + 0.05, 0.15), Vector3(Rb * s + 0.08, y_back + 0.25, zs))
		g.plate("pump_side", Vector3(Rb * 1.0 + 0.01, y_c - len_c * 0.5, zs), Vector3(1, 0, 0), "large")
	else:
		# an end-suction volute: the scroll, its foot, the suction and the bearing frame behind
		var Tw := Rv * 0.7
		var y0 := y_c - Tw * 0.5
		var lb := 0.35 + Rv
		y_back = y0 - lb
		var prof := [[Rv * 0.45, 0.0], [Rv * 0.95, 0.0], [Rv, Tw * 0.2], [Rv, Tw * 0.8], [Rv * 0.95, Tw], [ds * 0.5, Tw]]
		_pump_comps(g, zs, y0, Tw, Rv, y_back, kw)
		g.comp("volute")
		g.only("plant", ["volute", "casing_cover", "frame", "end_cover"])
		m.lathe(Vector3(0, y0, zs), Vector3(0, 1, 0), prof, 0, true)
		_pump_casing(g, m, zs, y0, Tw, Rv, ds, prof)
		# the volute's scroll grows towards the discharge: an offset second shell
		g.only("plant", ["volute", "casing_cover", "frame", "end_cover"])
		m.use("paint_pump", "identify")
		m.cyl(Vector3(0.0, y_c - Tw * 0.4, zs + Rv * 0.12), Vector3(0.0, y_c + Tw * 0.4, zs + Rv * 0.12), Rv * 0.92, -1.0)
		_pump_scroll(g, m, zs, y_c, Tw, Rv)
		m.use("paint_pump", "identify")
		m.box_lh(Vector3(-Rv * 0.4, y_c - Tw * 0.3, 0.15), Vector3(Rv * 0.4, y_c + Tw * 0.3, zs - Rv * 0.6))
		var Rf := Rv * 0.38
		g.comp("frame")
		g.only("plant", ["volute", "casing_cover", "frame", "end_cover"])
		m.use("paint_pump", "identify")
		m.cyl(Vector3(0, y0, zs), Vector3(0, y_back, zs), Rf, Rf * 0.9)
		_pump_frame(g, m, zs, y0, y_back, Rv, Rf)
		m.use("paint_pump", "identify")
		m.box_lh(Vector3(-Rf, y_back, 0.15), Vector3(Rf, y_back + 0.15, zs))
		g.only("plant", ["casing_bolts"])
		C.bolt_ring(m, Vector3(0, y_c - Tw * 0.45, zs), Vector3(0, 1, 0), Rv * 0.75, 12, 0.008, 0.05)
		g.only()
		if g.workshop:   # the casing bolts, where the plant draws its ring: they back out towards the bearing frame
			_ring_bolts(g, "casing_bolts", Vector3(0, y_c - Tw * 0.45, zs), Vector3(0, 1, 0), Rv * 0.75, 12, 0.008, 0.05)
		_pump_insides(g, zs, y0, Tw, Rv, y_back, lb)
		g.comp("volute")
		g.plate("pump_side", Vector3(Rv + 0.01, y_c, zs), Vector3(1, 0, 0), "large")
	# suction: a reducer from the casing to the suction flange at the front (kit.json: [0, L/2, 0.6] facing north)
	var tree := not multistage   # the Workshop's tree is the end-suction pump's (kit/README.md "Workshop: the pump")
	if tree:
		g.comp("volute")
	m.use("paint_pump", "identify")
	var y_in := y_c + (0.25 if multistage else Rv * 0.35)
	m.cyl(Vector3(0, y_in, zs), Vector3(0, y_suc, zs), ds * 0.38, ds * 0.5, 0, false)
	if tree:   # its ends closed inside the casing and the flange
		g.only("workshop")
		var nr: int = m.segs(ds * 0.5)
		C._face(m, Vector3(0, y_in, zs), Vector3(0, 1, 0), 0.0, ds * 0.38, nr, false)
		m.disk(Vector3(0, y_suc, zs), Vector3(0, 1, 0), ds * 0.5, nr)
		g.only()
	var tf_s: float = C.flange_dims(ds).tf
	_pump_flange(g, m, tree, Vector3(0, y_suc, zs), Vector3(0, 1, 0), ds, "pn16",
		lerpf(ds * 0.38, ds * 0.5, (y_suc - tf_s * 2.2 - y_in) / (y_suc - y_in)))
	# discharge: up from the casing's top to its flange at 1.4 m
	var z_top := zs + (Rv if not multistage else clampf(Rv * 0.85 + head / 6000.0, 0.16, 0.5)) * 0.9
	if tree:
		g.only("plant", ["volute", "casing_cover", "frame", "end_cover"])
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, y_c, z_top - 0.1), Vector3(0, y_c, 1.4), dd * 0.5, -1.0, 0, false)
	if tree:   # in the Workshop it starts in the scroll's wall, clear of the impeller's chamber, its ends closed
		var nd: int = m.segs(dd * 0.5)
		var zb := zs + Rv * 0.82
		g.only("workshop", "split")
		m.cyl(Vector3(0, y_c, zb), Vector3(0, y_c, 1.4), dd * 0.5, -1.0, nd, false)
		g.only("workshop")
		C._face(m, Vector3(0, y_c, zb), Vector3(0, 0, 1), 0.0, dd * 0.5, nd, false)
		m.disk(Vector3(0, y_c, 1.4), Vector3(0, 0, 1), dd * 0.5, nd)
		g.only()
	_pump_flange(g, m, tree, Vector3(0, y_c, 1.4), Vector3(0, 0, 1), dd, "pn40" if head > 100 else "pn16")
	# coupling, guard and motor
	var md := C.motor_dims(kw)
	var gap := clampf(0.15 + md.h * 0.3, 0.18, 0.5)
	var y_mf := y_back - gap
	var mo := C.motor_h(m, Vector3(0, y_mf, zs), Vector3(0, 1, 0), kw, 0.15, "paint_motor", g if tree else null,
		"motor", {"explode": [Vector3(0, 0, 1), PUMP_LIFT]})
	g.plate("motor_side", Vector3(mo.r * 0.92 + 0.01, y_mf - mo.l * 0.5, zs), Vector3(1, 0, 0), "large")
	var rc := clampf(md.h * 0.35, 0.05, 0.25)
	if tree:
		g.comp("coupling", {"explode": [Vector3(0, 0, 1), 0.5], "anim": "shaft",
			"pivot": Vector3(0, (y_mf + y_back) * 0.5, zs), "sym": [Vector3(0, 1, 0), 0]})
	var sh = g.move("shaft", Vector3(0, 0, zs), Vector3(0, 1, 0), "rotate", 0.0)
	C.coupling(sh, Vector3(0, y_mf + 0.01, zs), Vector3(0, y_back - 0.01, zs), rc)
	if tree:
		g.comp("guard", {"explode": [Vector3(0, 0, 1), 0.8]})
	C.guard(m, Vector3(0, y_mf, zs), Vector3(0, y_back, zs), rc * 1.15, 0.15)
	# the baseplate under everything
	if tree:
		g.comp("baseplate", {"explode": [Vector3(0, 0, 1), 0.0]})
	var y_lo := minf(-L * 0.5, mo.back.y - 0.1)
	var w := maxf(mo.r * 2.0 + 0.2, Rv * 2.0 + 0.2)
	C.baseplate(m, Vector3(-w * 0.5, y_lo, 0.0), Vector3(w * 0.5, y_suc - 0.15, 0.15), "paint_darkgrey")
	g.solid_box(Vector3(-w * 0.5, y_lo, 0), Vector3(w * 0.5, y_suc, zs + maxf(mo.r, Rv)))
	g.axis_line = [Vector3(0, y_lo, zs), Vector3(0, y_suc, zs)]

# ------------------------------------------------------------------ the end-suction pump in the Workshop (K6)
# A back pull-out end-suction pump (API 610 type OH1) as the Goulds 3196 and Flowserve Mark 3 manuals describe one;
# what is simplified: kit/README.md "Workshop: the pump". Every piece here is a Workshop piece or the split of a plant
# stand-in: plant mode draws what it drew before.

## The pump's own sizes from the volute's radius: the chamber, the impeller, the cover's seal bore, the frame's bore,
## the shaft, the seal and the bearings (radii, m).
static func _pump_r(Rv: float) -> Dictionary:
	return {"chamber": Rv * 0.8, "imp": Rv * 0.62, "eye": Rv * 0.32, "cover_bore": Rv * 0.28, "frame_bore": Rv * 0.266,
		"shaft": Rv * 0.09, "seal": Rv * 0.22, "brg": Rv * 0.24, "brg_w": Rv * 0.08}

## The tree. The volute stays on the baseplate (and on its pipes); the coupling, the guard and the motor come off
## first, then the back pull-out unit (the bearing frame with everything in it) is drawn back out of the volute, then
## on the bench the impeller and the casing cover come off forwards while the shaft with its bearings and seal leaves
## the frame at the coupling end; last the seal and the bearings come off the shaft. On one line the part ahead moves
## faster than the one behind it, so none passes through another.
static func _pump_comps(g, zs: float, y0: float, Tw: float, Rv: float, y_back: float, _kw: float) -> void:
	var k := _pump_r(Rv)
	var Y := Vector3(0, 1, 0)
	var up := Vector3(0, 0, 1)
	var lb := y0 - y_back
	var Ls := y0 + Tw * 0.66 - y_back                       # the shaft's length
	var d_ib: float = lb * 0.2 + Tw * 0.66 + k.brg_w + 0.1        # the inboard bearing off the shaft's impeller end
	var d_seal: float = d_ib + 0.2
	var d_shaft: float = Ls + d_seal + 0.15
	g.comp("volute", {"explode": [up, 0.0]})
	g.comp("frame", {"parent": "volute", "explode": [-Y, 0.55 + Tw],
		"anchors": {"vib_ib": Vector3(0, y0 - lb * 0.2, zs + Rv * 0.38), "vib_ob": Vector3(0, y_back + 0.06, zs + Rv * 0.342)}})
	g.comp("casing_cover", {"parent": "frame", "explode": [Y, 0.15], "sym": [Y, 0]})
	g.comp("impeller", {"parent": "frame", "explode": [Y, 0.35], "sym": [Y, 6]})
	g.comp("shaft", {"parent": "frame", "explode": [-Y, d_shaft], "pivot": Vector3(0, y_back + Ls * 0.5, zs),
		"sym": [Y, 0]})
	g.comp("end_cover", {"parent": "frame", "explode": [-Y, d_shaft + 0.3], "sym": [Y, 0]})
	g.comp("seal", {"parent": "shaft", "explode": [Y, d_seal], "sym": [Y, 0]})
	g.comp("bearing_ib", {"parent": "shaft", "explode": [Y, d_ib], "sym": [Y, 0]})
	g.comp("bearing_ob", {"parent": "shaft", "explode": [-Y, 0.3], "sym": [Y, 0]})

## The plant's casing (one solid of revolution) split at the cover's joint: the volute ahead of it, hollow round the
## impeller's chamber; the casing cover behind it, its seal bore through the middle. The pump's stand-ins (the casing,
## the scroll, the pipe and flanges, the bearing frame) are one: its outline is the casing's. Every face of a split
## lists its circle's points as its cylinder does (C._face), so each part is closed.
static func _pump_casing(g, m, zs: float, y0: float, Tw: float, Rv: float, ds: float, prof: Array) -> void:
	var k := _pump_r(Rv)
	var c0 := Vector3(0, y0, zs)
	var Y := Vector3(0, 1, 0)
	var n: int = m.segs(Rv)   # the plant's casing's
	var cj := c0 + Y * Tw * 0.2
	g.only("workshop", "split")
	m.use("paint_pump", "identify")
	m.lathe(c0, Y, prof.slice(2), n, false)
	m.disk(c0 + Y * Tw, Y, ds * 0.5, n)
	g.only("workshop")
	C._face(m, cj, Y, k.chamber, Rv, n, false)        # its joint face
	m._inner(cj, c0 + Y * Tw * 0.75, k.chamber, n)   # the impeller's chamber
	C._face(m, c0 + Y * Tw * 0.75, Y, 0.0, k.chamber, n, false)
	g.comp("casing_cover")
	g.only("workshop", "split")
	m.use("paint_pump", "identify")
	m.lathe(c0, Y, prof.slice(0, 3), n, false)
	C._face(m, c0, Y, k.cover_bore, Rv * 0.45, n, false)
	g.only("workshop")
	m.ring(cj, Y, k.cover_bore, Rv, n)                # its face to the impeller
	m._inner(c0, cj, k.cover_bore, n)                 # the seal chamber's bore
	g.comp("volute")
	g.only()

## The scroll (the plant's offset shell) open at the back round the chamber, so the impeller comes out through it.
static func _pump_scroll(g, m, zs: float, y_c: float, Tw: float, Rv: float) -> void:
	var a := Vector3(0.0, y_c - Tw * 0.4, zs + Rv * 0.12)
	var b := Vector3(0.0, y_c + Tw * 0.4, zs + Rv * 0.12)
	var Y := Vector3(0, 1, 0)
	var n: int = m.segs(Rv * 0.92)   # the plant's scroll's
	g.only("workshop", "split")
	m.use("paint_pump", "identify")
	m.cyl(a, b, Rv * 0.92, -1.0, n, false)
	C._face(m, a, Y, Rv * 0.8, Rv * 0.92, n, false)
	m.disk(b, Y, Rv * 0.92, n)
	g.only("workshop")
	m._inner(a, a + Y * Tw * 0.7, Rv * 0.8, n)
	C._face(m, a + Y * Tw * 0.7, Y, 0.0, Rv * 0.8, n, false)
	g.only()

## The bearing frame (the plant's cone behind the casing): open through its bore; its back is the bearing end cover.
static func _pump_frame(g, m, zs: float, y0: float, y_back: float, Rv: float, Rf: float) -> void:
	var k := _pump_r(Rv)
	var a := Vector3(0, y0, zs)
	var b := Vector3(0, y_back, zs)
	var Y := Vector3(0, 1, 0)
	var n: int = m.segs(Rf)   # the plant's frame's
	g.only("workshop", "split")
	m.use("paint_pump", "identify")
	m.cyl(a, b, Rf, Rf * 0.9, n, false)
	C._face(m, a, -Y, k.frame_bore, Rf, n, false)
	g.only("workshop")
	m._inner(a, b, k.frame_bore, n)
	m.ring(b, -Y, k.frame_bore, Rf * 0.9, n)
	g.comp("end_cover")
	g.only("workshop", "split")
	m.use("paint_pump", "identify")
	m.disk(b, -Y, Rf * 0.9, n)
	g.only("workshop")
	m.ring(b, -Y, k.frame_bore, Rf * 0.9, n)   # its flange against the frame, facing out (in the disk's plane)
	m.cyl(b + Y * 0.03, b, k.frame_bore, -1.0, n, false)      # its spigot in the bore
	C._face(m, b + Y * 0.03, -Y, 0.0, k.frame_bore, n, false)
	g.comp("frame")
	g.only()

## What turns, in the `shaft` node: the shaft from the end cover to the impeller, the mechanical seal in the cover's
## bore, the two bearings in the frame, the closed impeller with six vanes curved back against the turn (the shaft
## turns clockwise seen from the motor, as its `shaft` node's axis has it).
static func _pump_insides(g, zs: float, y0: float, Tw: float, Rv: float, y_back: float, lb: float) -> void:
	if not g.workshop:
		return
	var k := _pump_r(Rv)
	var Y := Vector3(0, 1, 0)
	var at := func(t: float) -> Vector3: return Vector3(0, y0 + Tw * t, zs)
	var sh = g.move("shaft", Vector3(0, 0, zs), Y, "rotate", 0.0)
	g.only("workshop")
	g.comp("shaft")
	sh.use("steel", "identify")
	sh.cyl(Vector3(0, y_back + 0.001, zs), at.call(0.66), k.shaft, -1.0, 16)
	g.comp("seal")
	sh.use("chrome", "identify")
	sh.tube(Vector3(0, y0 - 0.03, zs), at.call(0.15), k.seal, k.shaft, 16)
	g.comp("bearing_ib")
	var yi := y0 - lb * 0.2
	sh.tube(Vector3(0, yi - k.brg_w * 0.5, zs), Vector3(0, yi + k.brg_w * 0.5, zs), k.brg, k.shaft, 16)
	g.comp("bearing_ob")
	sh.tube(Vector3(0, y_back + 0.04, zs), Vector3(0, y_back + 0.04 + k.brg_w, zs), k.brg, k.shaft, 16)
	g.comp("impeller")
	sh.use("steel_dark", "identify")
	sh.cyl(at.call(0.28), at.call(0.31), k.imp, -1.0, 32)              # the back shroud
	sh.tube(at.call(0.55), at.call(0.58), k.imp, k.eye, 32)            # the front shroud round the eye
	sh.cyl(at.call(0.28), at.call(0.64), k.shaft * 2.0, -1.0, 16)      # the hub
	var ax: Array = sh.across(Y)
	var r1: float = k.shaft * 2.0
	var r2: float = k.imp
	var hgt := Tw * 0.25
	var thick := Rv * 0.035
	for i in 6:
		var th0 := TAU * i / 6.0
		var pts: Array = []
		for j in 3:   # each vane's centre line from the hub to the tip, trailing back against the turn
			var rr := lerpf(r1, r2, j / 2.0)
			var th := th0 - 1.0 * (rr - r1) / (r2 - r1)
			pts.append(at.call(0.43) + (ax[0] * cos(th) + ax[1] * sin(th)) * rr)
		for j in 2:
			var p: Vector3 = pts[j]
			var q: Vector3 = pts[j + 1]
			var x: Vector3 = (q - p).normalized()
			sh.box((p + q) * 0.5, Vector3(p.distance_to(q) + thick, hgt, thick), Basis(x, Y, x.cross(Y)))
	g.only()

## A ring of bolts as a fastener group, each item where C.bolt_ring draws one (the same hexagon, so the group matches
## the ring it replaces), backing out along -d (the horizontal pump's casing bolts d = +y, as parts_machines.gd's
## coupling bolts; bolts that back out upwards d = -z).
static func _ring_bolts(g, id: String, c: Vector3, d: Vector3, R: float, n: int, r: float, len: float) -> void:
	var items: Array = []
	var ax: Array = g.m.across(d)
	for i in n:
		var a := TAU * (i + 0.5) / n
		var p: Vector3 = c + (ax[0] * cos(a) + ax[1] * sin(a)) * R
		var by: Vector3 = ax[0]
		var bz := -d
		items.append(Transform3D(Basis(by.cross(bz), by, bz), p + d * len * 0.5))
	var bolt := func(b) -> void:
		b.use("steel_bolt", "detail", r * 3.4)
		b.cyl(Vector3.ZERO, Vector3(0, 0, len), r * 1.7, -1.0, 6)
	g.fasteners(id, "bolt", items, bolt, "split")

## A nozzle's flange: the plant's (C.flange), and in the Workshop the same with its neck closed round the pipe
## (`pipe_r`: the pipe's radius where the neck ends; the neck's bore a little inside it, so no gap is left between).
## `standin`: the components that replace the plant's flange (with its pump's casing).
static func _pump_flange(g, m, tree: bool, c: Vector3, d: Vector3, od: float, rating: String, pipe_r := 0.0,
		standin: Array = ["volute", "casing_cover", "frame", "end_cover"]) -> void:
	if not tree:
		C.flange(m, c, d, od, "paint_pump", rating)
		return
	g.only("plant", standin)
	C.flange(m, c, d, od, "paint_pump", rating)
	var f := C.flange_dims(od, rating)
	var n1: int = m.segs(f.df * 0.5, 10, 40)
	var n2: int = m.segs(od * 0.5, 8, 32)
	var e: Vector3 = c - d * (f.tf * 2.2)
	var rb: float = (pipe_r if pipe_r > 0.0 else od * 0.5) * 0.97
	g.only("workshop", "split")
	m.use("paint_pump", "form")
	m.cyl(c - d * f.tf, c, f.df * 0.5, -1.0, n1, false)
	C._face(m, c - d * f.tf, d, 0.0, f.df * 0.5, n1, false)
	m.disk(c, d, f.df * 0.5, n1)
	m.cyl(e, c - d * f.tf, od * 0.5 + f.tf * 0.6, od * 0.5 + f.tf * 0.3, n2, false)
	C._face(m, e, d, rb, od * 0.5 + f.tf * 0.6, n2, false)   # the neck's end round the pipe
	C.bolt_ring(m, c - d * f.tf * 0.5, d, f.pcd, f.n, f.bolt_r, f.tf * 2.4)
	g.only("workshop")
	m.use("paint_pump", "form")
	m._inner(e, c - d * f.tf, rb, n2)
	m.ring(c - d * f.tf, d, rb, od * 0.5 + f.tf * 0.3, n2)
	g.only()

static func pump_vertical(_part: String, g) -> void:
	var m = g.m
	var flow: float = g.num("flow_m3h", 1000)
	var kw: float = g.num("motor_kw", 200)
	var pit: float = g.num("pit_depth", 6)
	var dd: float = g.od(dn_for(g, flow, 3.0))
	var rc := dd * 0.5
	var up := Vector3(0, 0, 1)
	# the Workshop's tree (K6) is a wet-pit pump's: its column and bowls hang in the pit (kit/README.md "Workshop: the
	# vertical pump"); the stand-in is everything of the pump's casing the plant draws as one
	var tree := pit > 0.1
	var nfl := maxi(1, int(pit / 3.0))
	var SI: Array = ["head", "suction_bell", "bowl_1", "bowl_2", "discharge_case"]
	for i in nfl + 1:
		SI.append("column_%d" % (i + 1))
	for i in nfl:
		SI.append("joint_bolts_%d" % (i + 1))
	var k := _vpump_r(rc, maxf(rc + 0.12, 0.25))
	if tree:
		_vpump_comps(g, rc, pit, nfl, k)
	# the discharge head: from the floor up past the discharge branch at 1.5 m
	var rh := maxf(rc + 0.12, 0.25)
	var zh := 1.5 + rc + 0.25
	if tree:
		g.comp("head")
		g.only("plant", SI)
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, 0, 0.05), Vector3(0, 0, zh), rh, rh * 0.9)
	if tree:
		_vpump_head(g, m, rh, zh, k)
		g.comp("soleplate")
		m.use("paint_pump", "form")
	else:
		m.use("paint_pump", "form")
	m.box(Vector3(0, 0, 0.04), Vector3(rh * 2.6, rh * 2.6, 0.08))          # sole plate
	if tree:
		g.only("plant", ["head_bolts"])
	C.bolt_ring(m, Vector3(0, 0, 0.08), Vector3(0, 0, 1), rh * 1.15, 8, 0.02, 0.08)
	if tree:
		g.only()
		if g.workshop:   # the head's hold-down bolts, where the plant draws its ring: they back out upwards
			_ring_bolts(g, "head_bolts", Vector3(0, 0, 0.08), -up, rh * 1.15, 8, 0.02, 0.08)
		g.comp("head")
		g.only("plant", SI)
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, 0, 1.5), Vector3(0, 1.2, 1.5), rc, -1.0, 0, false)    # the branch to the discharge flange
	if tree:   # in the Workshop it starts in the head's wall, outside its bore, its ends closed
		var nb: int = m.segs(rc)
		var y0: float = k.bore * 1.02
		g.only("workshop", "split")
		m.cyl(Vector3(0, y0, 1.5), Vector3(0, 1.2, 1.5), rc, -1.0, nb, false)
		g.only("workshop")
		m.use("paint_pump", "identify")
		C._face(m, Vector3(0, y0, 1.5), Vector3(0, 1, 0), 0.0, rc, nb, false)
		m.disk(Vector3(0, 1.2, 1.5), Vector3(0, 1, 0), rc, nb)
		g.only()
	_pump_flange(g, m, tree, Vector3(0, 1.2, 1.5), Vector3(0, 1, 0), dd, "pn16", rc, SI)
	# the column and the bowls down in the pit or can, the bell mouth at the bottom (the suction nozzle)
	if tree:
		g.only("plant", SI)
	m.use("paint_pump", "form")
	if pit > 0.1:
		m.cyl(Vector3(0, 0, 0.0), Vector3(0, 0, -pit + rc * 2.5), rc * 0.8, -1.0, 0, false)
		for i in nfl:
			C.flange_pair(m, Vector3(0, 0, -pit * (i + 1) / (nfl + 1)), Vector3(0, 0, 1), dd * 0.8, "paint_pump")
		m.lathe(Vector3(0, 0, -pit), Vector3(0, 0, 1), [[rc * 1.5, 0.0], [rc * 1.4, rc * 0.4], [rc * 1.05, rc * 1.4], [rc * 0.8, rc * 2.5]], 0, false)
	if tree:
		_vpump_column(g, m, rc, pit, nfl, k)
		_vpump_bowls(g, m, rc, pit, k)
		g.comp("head")
		g.only("plant", SI)
	# the motor stool (open: the coupling turns in its windows) and the motor on it
	var zs0 := zh
	var hs := clampf(0.4 + rc * 0.5, 0.45, 1.1)
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, 0, zs0), Vector3(0, 0, zs0 + 0.06), rh * 1.05)
	m.cyl(Vector3(0, 0, zs0 + hs - 0.06), Vector3(0, 0, zs0 + hs), rh * 1.05)
	if tree:
		var spindle := clampf(rh * 0.35, 0.06, 0.25) * 0.35   # the coupling's spindle: the rings' bores, the shafts in it
		_vpump_stand_ring(g, m, Vector3(0, 0, zs0), rh * 1.05, spindle, true)
		_vpump_stand_ring(g, m, Vector3(0, 0, zs0 + hs - 0.06), rh * 1.05, spindle)
		g.only()
		m.use("paint_pump", "identify")
	for q in 4:
		var a := TAU * (q + 0.5) / 4.0
		var p := Vector3(cos(a), sin(a), 0) * rh * 0.9
		m.box_lh(p + Vector3(-0.05, -0.05, zs0), p + Vector3(0.05, 0.05, zs0 + hs))
	if tree:
		g.comp("coupling", {"explode": [Vector3(1, 0, 0), rh * 2.4], "anim": "shaft",
			"pivot": Vector3(0, 0, zs0 + hs * 0.5), "sym": [up, 0]})
	var sh = g.move("shaft", Vector3(0, 0, zs0), Vector3(0, 0, 1), "rotate", 0.0)
	C.coupling(sh, Vector3(0, 0, zs0 + 0.06), Vector3(0, 0, zs0 + hs - 0.06), clampf(rh * 0.35, 0.06, 0.25))
	if tree:
		_vpump_insides(g, rc, pit, zh, k)
	var mo := C.motor_v(m, Vector3(0, 0, zs0 + hs), kw, "paint_motor", g if tree else null, {"explode": [up, PUMP_LIFT],
		"shaft_r": clampf(rh * 0.35, 0.06, 0.25) * 0.35 * 0.98})
	g.plate("motor_side", Vector3(mo.r + 0.01, 0, zs0 + hs + 0.6), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, mo.top), maxf(rh, mo.r))
	g.axis_line = [Vector3(0, 0, -pit), Vector3(0, 0, mo.top)]

# ------------------------------------------------------------------ the vertical pump in the Workshop (K6)
# A wet-pit vertical turbine pump as the Goulds VIT and Flowserve VTP manuals describe one; what is simplified:
# kit/README.md "Workshop: the vertical pump". Every piece here is a Workshop piece or the split of the plant's
# stand-in: plant mode draws what it drew before.

## The pump's own sizes from the column's radius rc and the head's rh: the head's bore, the column's bore, the
## pump shaft (lineshaft and bowl shaft, one), the impellers, the bowls' wall (m).
static func _vpump_r(rc: float, rh: float) -> Dictionary:
	return {"bore": rc * 0.72, "col_in": rc * 0.8 * 0.88, "shaft": rc * 0.18, "imp": rc * 0.72, "eye": rc * 0.42,
		"hub": rc * 0.3, "wall": rc * 0.1, "seal_h": 0.12, "rh": rh}

## The bowl assembly's profile points (the plant's lathe, from the bell's mouth up: [radius, height]) and the heights
## where it is split: the bell, the first stage's bowl, the second's, the discharge case.
static func _vpump_prof(rc: float) -> Array:
	var p2 := [rc * 1.05, rc * 1.4]
	var p3 := [rc * 0.8, rc * 2.5]
	var t := (2.0 - 1.4) / (2.5 - 1.4)
	var pm := [lerpf(p2[0], p3[0], t), rc * 2.0]
	return [[rc * 1.5, 0.0], [rc * 1.4, rc * 0.4], p2, pm, p3]

## The tree. The sole plate and the head stay (the head on its discharge pipe); the coupling comes out sideways
## through the stand's window and the motor is lifted off first, its parts apart above; the string in the pit is drawn
## apart downwards, each part below moving farther, the impellers rising out of their bowls (which move farther than
## they do) while the shaft stays: so none passes through another. A real pump is lifted out of the pit whole and
## laid down to be taken apart (the guided steps say so).
static func _vpump_comps(g, rc: float, pit: float, nfl: int, k: Dictionary) -> void:
	var dn := Vector3(0, 0, -1)
	g.comp("soleplate", {"explode": [Vector3(0, 0, 1), 0.0]})
	g.comp("head", {"explode": [Vector3(0, 0, 1), 0.0]})
	g.comp("seal", {"explode": [dn, 0.9], "sym": [Vector3(0, 0, 1), 0]})
	g.comp("shaft", {"explode": [dn, 0.0], "pivot": Vector3(0, 0, -pit * 0.5), "sym": [Vector3(0, 0, 1), 0]})
	for i in nfl + 1:
		g.comp("column_%d" % (i + 1), {"explode": [dn, 0.5 * (i + 1)], "sym": [Vector3(0, 0, 1), 0]})
	var d0 := 0.5 * (nfl + 1) + 0.5
	g.comp("discharge_case", {"explode": [dn, d0], "sym": [Vector3(0, 0, 1), 0]})
	g.comp("impeller_2", {"explode": [dn, d0 + 0.25], "sym": [Vector3(0, 0, 1), 5]})
	g.comp("bowl_2", {"explode": [dn, d0 + 0.6], "sym": [Vector3(0, 0, 1), 0]})
	g.comp("impeller_1", {"explode": [dn, d0 + 0.85], "sym": [Vector3(0, 0, 1), 5]})
	g.comp("bowl_1", {"explode": [dn, d0 + 1.2], "sym": [Vector3(0, 0, 1), 0]})
	g.comp("suction_bell", {"explode": [dn, d0 + 1.45], "sym": [Vector3(0, 0, 1), 0]})

## The head split: the plant's tapered cylinder open through its bore (the water's way up to the branch, round the
## shaft); its top under the stand's lower ring, its bottom in the sole plate.
static func _vpump_head(g, m, rh: float, zh: float, k: Dictionary) -> void:
	var up := Vector3(0, 0, 1)
	var n: int = m.segs(rh)   # the plant's head's
	var a := Vector3(0, 0, 0.05)
	var b := Vector3(0, 0, zh)
	g.only("workshop", "split")
	m.use("paint_pump", "identify")
	m.cyl(a, b, rh, rh * 0.9, n, false)
	g.only("workshop")
	m.use("paint_pump", "identify")
	C._face(m, a, up, k.bore, rh, n, false)
	C._face(m, b, up, k.bore, rh * 0.9, n, true)
	m._inner(a, b, k.bore, n)
	g.only()

## One of the stand's two rings (the plant's discs) open round the shaft that runs through it. `flip`: drawn about the
## downward axis, so its points are those of the plant's first cap (across(-z)) rather than its cylinder's: for an odd
## count they are other points of the circle, and the two rings together give the plant's outline.
static func _vpump_stand_ring(g, m, c: Vector3, R: float, bore: float, flip := false) -> void:
	var up := Vector3(0, 0, -1) if flip else Vector3(0, 0, 1)
	if flip:
		c += Vector3(0, 0, 0.06)
	var n: int = m.segs(R)
	g.only("workshop", "split")
	m.use("paint_pump", "identify")
	m.cyl(c, c + up * 0.06, R, -1.0, n, false)
	C._face(m, c, up, bore, R, n, false)
	C._face(m, c + up * 0.06, up, bore, R, n, true)
	g.only("workshop")
	m.use("paint_pump", "identify")
	m._inner(c, c + up * 0.06, bore, n)
	g.only()

## The column split at its flanged joints: each section a pipe, the upper one of a joint carrying both its flanges
## (the plant's pair) with the lineshaft's bearing (a spider round the shaft) in it, the joint's bolts a fastener group.
static func _vpump_column(g, m, rc: float, pit: float, nfl: int, k: Dictionary) -> void:
	var up := Vector3(0, 0, 1)
	var ro := rc * 0.8
	var n: int = m.segs(ro)   # the plant's column's
	var od := rc * 2.0 * 0.8
	var f := C.flange_dims(od)
	var n1: int = m.segs(f.df * 0.5, 10, 40)
	var top := 0.0
	for i in nfl + 1:
		var id := "column_%d" % (i + 1)
		g.comp(id)
		var c := -pit * (i + 1) / (nfl + 1)
		var bot: float = c + f.tf if i < nfl else -pit + rc * 2.5
		g.only("workshop", "split")
		m.use("paint_pump", "form")
		m.cyl(Vector3(0, 0, top), Vector3(0, 0, bot), ro, -1.0, n, false)
		g.only("workshop")
		m.use("paint_pump", "form")
		C._face(m, Vector3(0, 0, top), -up, k.col_in, ro, n, false)
		C._face(m, Vector3(0, 0, bot), -up, k.col_in, ro, n, true)
		m._inner(Vector3(0, 0, top), Vector3(0, 0, bot), k.col_in, n)
		if i < nfl:   # the joint's flanges, below this section
			var a := Vector3(0, 0, c - f.tf)
			var b := Vector3(0, 0, c + f.tf)
			g.only("workshop", "split")
			m.use("paint_pump", "form")
			m.cyl(a, b, f.df * 0.5, -1.0, n1, false)
			C._face(m, a, up, k.col_in, f.df * 0.5, n1, false)
			C._face(m, b, up, k.col_in, f.df * 0.5, n1, true)
			g.only("workshop")
			m.use("paint_pump", "form")
			m._inner(a, b, k.col_in, n1)
			m.use("brass", "identify")   # the lineshaft's bearing in its retainer (a spider round the shaft)
			m.tube(a + up * 0.004, b - up * 0.004, k.col_in - 0.002, k.shaft + 0.002, 12)
			g.only()
			if g.workshop:
				_ring_bolts(g, "joint_bolts_%d" % (i + 1), Vector3(0, 0, c), -up, f.pcd, f.n, f.bolt_r, f.tf * 3.0)
			top = c - f.tf
	g.only()

## The bowl assembly split at the plant's profile points (and the third segment once more): the suction bell (closed
## at its mouth by a flat plate, with the shaft's bottom bearing in its hub), the two bowls round the impellers' chambers,
## the discharge case under the column. Each a shell round its chamber, open at its joints.
static func _vpump_bowls(g, m, rc: float, pit: float, k: Dictionary) -> void:
	var up := Vector3(0, 0, 1)
	var c0 := Vector3(0, 0, -pit)
	var prof := _vpump_prof(rc)
	var n: int = m.segs(rc * 1.5)   # the plant's lathe's
	var w: float = k.wall
	var ids := ["suction_bell", "bowl_1", "bowl_2", "discharge_case"]
	for i in 4:
		var p0: Array = prof[i]
		var p1: Array = prof[i + 1]
		var r_in1: float = p1[0] - w if i < 3 else k.col_in
		g.comp(ids[i])
		g.only("workshop", "split")
		m.use("steel_bolt", "identify")   # (the plant draws the bowls after the joints' bolts, in their material)
		m.lathe(c0, up, [p0, p1], n, false)
		if i == 0:
			C._face(m, c0, up, 0.0, p0[0], n, false)   # the plate across the bell's mouth
		if i == 3:   # its top round the column's foot: seen where the column's eight sides lie inside its circle
			C._face(m, c0 + up * p1[1], up, r_in1, p1[0], n, true)
		g.only("workshop")
		m.use("paint_pump", "form")
		var t0: float = p0[1] + (w if i == 0 else 0.0)
		var r_in0: float = p0[0] - w
		if i == 0:
			C._face(m, c0 + up * t0, up, 0.0, r_in0, n, true)          # the bell's floor inside
		else:
			C._face(m, c0 + up * t0, up, r_in0, p0[0], n, false)
		if i < 3:
			C._face(m, c0 + up * p1[1], up, r_in1, p1[0], n, true)
		m.lathe(c0, up, [[r_in1, p1[1]], [r_in0, t0]], n, false)       # the chamber's wall, facing in
		if i == 0:   # the hub on the bell's floor: the shaft's bottom bearing
			m.use("brass", "identify")
			m.tube(c0 + up * w, c0 + up * rc * 0.35, k.hub, k.shaft + 0.002, 12)
	g.only()

## What turns, in the `shaft` node: the pump's shaft from the bell's bearing up through the column to the coupling,
## and the two enclosed impellers on it (each on its taperlock), five vanes each curved back against the turn (the
## shaft turns counter-clockwise seen from the motor, +z); the seal in the head's top round the shaft (it stands).
static func _vpump_insides(g, rc: float, pit: float, zh: float, k: Dictionary) -> void:
	if not g.workshop:
		return
	var m = g.m
	var up := Vector3(0, 0, 1)
	var prof := _vpump_prof(rc)
	g.only("workshop")
	g.comp("seal")
	m.use("chrome", "identify")
	m.tube(Vector3(0, 0, zh - k.seal_h), Vector3(0, 0, zh), k.bore - 0.003, k.shaft + 0.001, 16)
	var sh = g.move("shaft", Vector3(0, 0, zh), up, "rotate", 0.0)
	g.comp("shaft")
	sh.use("steel", "identify")
	sh.cyl(Vector3(0, 0, -pit + k.wall + 0.004), Vector3(0, 0, zh + 0.07), k.shaft, -1.0, 16)   # (its top in the coupling)
	for s in 2:
		g.comp("impeller_%d" % (s + 1))
		var z0: float = -pit + rc * (0.6 if s == 0 else 1.5)
		var H: float = rc * 0.3
		var at := func(t: float) -> Vector3: return Vector3(0, 0, z0 + H * t)
		sh.use("steel_dark", "identify")
		sh.tube(at.call(0.0), at.call(0.15), k.imp, k.eye, 32)           # the front shroud round the eye (below)
		sh.cyl(at.call(0.85), at.call(1.0), k.imp, -1.0, 32)             # the back shroud
		sh.cyl(at.call(0.0), at.call(1.0), k.shaft * 1.6, -1.0, 16)      # the hub on its taperlock
		var ax: Array = sh.across(up)
		var r1: float = k.shaft * 1.6
		var r2: float = k.imp
		var thick: float = rc * 0.03
		for i in 5:
			var th0 := TAU * i / 5.0
			var pts: Array = []
			for j in 3:   # each vane's centre line from the hub to the tip, trailing back against the turn
				var rr := lerpf(r1, r2, j / 2.0)
				var th := th0 - 1.0 * (rr - r1) / (r2 - r1)
				pts.append(at.call(0.5) + (ax[0] * cos(th) + ax[1] * sin(th)) * rr)
			for j in 2:
				var p: Vector3 = pts[j]
				var q: Vector3 = pts[j + 1]
				var x: Vector3 = (q - p).normalized()
				sh.box((p + q) * 0.5, Vector3(p.distance_to(q) + thick, H * 0.7, thick), Basis(x, up, x.cross(up)))
	g.only()

## A cooling tower's fan on its deck: the stack (the velocity-recovery cylinder), the blades turning in its throat,
## the gearbox, and the motor outside the stack driving it by a shaft.
static func fan_axial(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 9.5)
	var nb := int(g.num("blades", 8))
	var kw: float = g.num("motor_kw", 200)
	var hs: float = g.num("stack_height", 3)
	var r := d * 0.5 + 0.15
	m.use("paint_ct", "form")
	if hs > 0.05:
		var prof := [[r, 0.0], [r, hs * 0.35], [r * (1.0 + 0.12 * minf(hs, 4.0) / 4.0), hs]]
		m.lathe(Vector3.ZERO, Vector3(0, 0, 1), prof, 48, false)
		m._inner(Vector3(0, 0, 0), Vector3(0, 0, hs * 0.35), r - 0.03, 48)
		m.use("paint_ct", "detail", 0.1)
		m.ring(Vector3(0, 0, hs), Vector3(0, 0, 1), r * (1.0 + 0.12 * minf(hs, 4.0) / 4.0) - 0.05, r * (1.0 + 0.12 * minf(hs, 4.0) / 4.0) + 0.05, 48)
	# the gearbox under the hub and its support beams across the stack
	m.use("paint_darkgrey", "form")
	m.box(Vector3(0, 0, 0.3), Vector3(0.9, 0.7, 0.6))
	m.use("steel", "form")
	for s: float in [-1.0, 1.0]:
		m.box(Vector3(0, s * 0.45, 0.05), Vector3(d + 0.2, 0.2, 0.1))
	# the motor outside the stack on the deck, the drive shaft through the stack's wall
	var md := C.motor_dims(kw)
	var zs: float = md.h + 0.1
	var xm := r + 0.4
	var mo := C.motor_h(m, Vector3(xm, 0, zs), Vector3(-1, 0, 0), kw, 0.0)
	m.use("steel", "identify")
	m.cyl(Vector3(0.45, 0, 0.3), Vector3(xm, 0, zs), 0.05, -1.0, 10)
	C.guard(m, Vector3(xm - 0.05, 0, zs), Vector3(xm - 0.6, 0, zs), 0.12, 0.0)
	g.plate("deck", Vector3(xm + mo.l * 0.5, -mo.r - 0.01, zs), Vector3(0, -1, 0), "large")
	# the blades and hub (moving)
	var zf := 0.75
	var sh = g.move("shaft", Vector3(0, 0, zf), Vector3(0, 0, 1), "rotate", 0.0)
	sh.use("steel", "identify")
	sh.cyl(Vector3(0, 0, zf - 0.25), Vector3(0, 0, zf + 0.25), d * 0.08, -1.0, 16)
	sh.use("paint_yellow", "identify")
	sh.dish(Vector3(0, 0, zf + 0.25), Vector3(0, 0, 1), d * 0.08, d * 0.03, 16, 3)
	sh.use("paint_grey", "identify")
	for i in nb:
		var a := TAU * i / nb
		var dir := Vector3(cos(a), sin(a), 0)
		var tang := Vector3(-sin(a), cos(a), 0)
		var pitch := deg_to_rad(14.0)
		var up := Vector3(0, 0, 1) * cos(pitch) + tang * sin(pitch)
		var chord := tang * cos(pitch) - Vector3(0, 0, 1) * sin(pitch)
		var rr := d * 0.5 - 0.05
		var c := dir * (d * 0.08 + rr) * 0.5 + Vector3(0, 0, zf)
		sh.box(c, Vector3(rr - d * 0.08, 0.5 * d / 9.5 + 0.1, 0.04), Basis(dir, chord, up).orthonormalized())
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, maxf(hs, 1.0)), r)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, hs)]

## A packaged (screw) air compressor: the enclosure with its louvres and controller, the cooler's fan on the roof
## (moving, under its grille), the air outlet at the front.
static func compressor_skid(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 4)
	var W: float = g.num("width", 2)
	var H := clampf(1.4 + g.num("kw", 250) / 1000.0, 1.6, 2.6)
	C.baseplate(m, Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, 0.15))
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(-W * 0.5 + 0.05, -L * 0.5 + 0.05, 0.15), Vector3(W * 0.5 - 0.05, L * 0.5 - 0.05, H))
	m.use("dark", "identify")
	for s: float in [-1.0, 1.0]:   # louvres on both sides
		for i in 3:
			var y := -L * 0.3 + L * 0.3 * i
			m.box(Vector3((W * 0.5 - 0.049) * s, y, H * 0.45), Vector3(0.01, L * 0.22, H * 0.4))
	m.use("paint_darkgrey", "identify")   # the doors' handles and seams
	for i in 4:
		var y := -L * 0.5 + 0.05 + (L - 0.1) * (i + 1) / 5.0
		m.box(Vector3(W * 0.5 - 0.045, y, H * 0.55), Vector3(0.012, 0.012, H * 0.8))
	# the controller's display at the front
	m.use("glass", "identify")
	m.box(Vector3(W * 0.25, L * 0.5 - 0.045, H * 0.7), Vector3(0.3, 0.012, 0.2))
	m.use("paint_red", "identify")
	m.cyl(Vector3(-W * 0.2, L * 0.5 - 0.05, H * 0.7), Vector3(-W * 0.2, L * 0.5 - 0.0, H * 0.7), 0.04, -1.0, 10)
	# the roof's fan grille
	var fr := minf(W, L) * 0.3
	m.use("paint_darkgrey", "identify")
	m.ring(Vector3(0, -L * 0.2, H + 0.001), Vector3(0, 0, 1), fr, fr + 0.05, 24)
	m.use("steel_dark", "detail", 0.01)
	for i in 5:
		var x := -fr + fr * 2.0 * (i + 0.5) / 5.0
		var h := sqrt(maxf(fr * fr - x * x, 0.0))
		m.box(Vector3(x, -L * 0.2, H + 0.01), Vector3(0.01, h * 2.0, 0.01))
	var sh = g.move("shaft", Vector3(0, -L * 0.2, H - 0.05), Vector3(0, 0, 1), "rotate", 0.0)
	sh.use("dark", "identify")
	sh.disk(Vector3(0, -L * 0.2, H - 0.06), Vector3(0, 0, 1), fr, 24)
	sh.use("paint_grey", "identify")
	for i in 5:
		var a := TAU * i / 5.0
		var dir := Vector3(cos(a), sin(a), 0)
		sh.box(Vector3(0, -L * 0.2, H - 0.05) + dir * fr * 0.5, Vector3(fr * 0.85, fr * 0.3, 0.01), Basis(dir, Vector3(-dir.y, dir.x, 0), Vector3(0, 0, 1)))
	# the air outlet (kit.json: [0, L/2, 1.0] facing north)
	C.nozzle(m, Vector3(0, L * 0.5 - 0.1, 1.0), Vector3(0, L * 0.5, 1.0), g.od(100), "paint_darkgrey")
	g.plate("side", Vector3(W * 0.5 - 0.04, 0, H * 0.85), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, H))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## A liquid-ring vacuum pump skid: the pump between its two end covers, the motor, the separator vessel, the seal
## water cooler and the suction pipe up to the inlet at the front.
static func vacuum_pump_skid(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 4)
	var kw: float = g.num("kw", 160)
	var W := 1.8
	var zs := 0.75
	C.baseplate(m, Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, 0.15))
	var Rp := clampf(0.25 + kw / 2000.0, 0.28, 0.55)
	var yp := L * 0.18
	m.use("paint_pump", "identify")
	m.cyl(Vector3(-0.35, yp - 0.35, zs), Vector3(-0.35, yp + 0.35, zs), Rp)
	m.cyl(Vector3(-0.35, yp - 0.47, zs), Vector3(-0.35, yp - 0.35, zs), Rp * 0.9)
	m.cyl(Vector3(-0.35, yp + 0.35, zs), Vector3(-0.35, yp + 0.47, zs), Rp * 0.9)
	m.box_lh(Vector3(-0.35 - Rp * 0.6, yp - 0.3, 0.15), Vector3(-0.35 + Rp * 0.6, yp + 0.3, zs - Rp * 0.5))
	var mo := C.motor_h(m, Vector3(-0.35, yp - 0.75, zs), Vector3(0, 1, 0), kw, 0.15)
	var sh = g.move("shaft", Vector3(-0.35, 0, zs), Vector3(0, 1, 0), "rotate", 0.0)
	C.coupling(sh, Vector3(-0.35, yp - 0.74, zs), Vector3(-0.35, yp - 0.48, zs), 0.09)
	C.guard(m, Vector3(-0.35, yp - 0.75, zs), Vector3(-0.35, yp - 0.47, zs), 0.1, 0.15)
	# the separator: a vertical vessel beside the pump, the cooler behind it
	m.use("paint_tank", "identify")
	m.cyl(Vector3(0.45, -L * 0.2, 0.15), Vector3(0.45, -L * 0.2, 1.7), 0.35)
	m.dish(Vector3(0.45, -L * 0.2, 1.7), Vector3(0, 0, 1), 0.35, 0.12, 0, 3)
	m.use("paint_grey", "identify")
	m.box(Vector3(0.5, L * 0.05, 0.75), Vector3(0.35, 0.5, 1.2))
	m.use("steel", "detail", 0.04)
	for i in 6:
		m.box(Vector3(0.5, L * 0.05 - 0.2 + i * 0.08, 1.37), Vector3(0.38, 0.02, 0.04))
	# the suction: from the pump's top to the inlet flange at the front (kit.json: [0, L/2, 1.2] facing north)
	var dd: float = g.od(150)
	m.use("paint_pump", "identify")
	m.cyl(Vector3(-0.35, yp, zs + Rp - 0.05), Vector3(-0.35, yp, 1.2), dd * 0.5, -1.0, 0, false)
	m.pipe_path([Vector3(-0.35, yp, 1.2), Vector3(-0.35, L * 0.5 - 0.3, 1.2), Vector3(0, L * 0.5 - 0.3, 1.2), Vector3(0, L * 0.5, 1.2)], dd * 0.5, dd * 1.5)
	C.flange(m, Vector3(0, L * 0.5, 1.2), Vector3(0, 1, 0), dd, "paint_pump")
	m.use("paint_pump", "form")   # pump to separator
	m.pipe_path([Vector3(-0.35, yp - 0.3, zs + Rp * 0.7), Vector3(-0.35, yp - 0.3, 1.5), Vector3(0.45, yp - 0.3, 1.5), Vector3(0.45, -L * 0.2 + 0.36, 1.5)], g.od(100) * 0.5, g.od(100) * 1.5)
	g.plate("side", Vector3(-0.35 - mo.r - 0.01, yp - 1.2, zs), Vector3(-1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, 1.8))
	g.axis_line = [Vector3(0, -L * 0.5, zs), Vector3(0, L * 0.5, zs)]

## A motor on its own (when a driver isn't part of its machine): on a baseplate, shaft north.
static func motor(_part: String, g) -> void:
	var m = g.m
	var kw: float = g.num("kw", 100)
	var md := C.motor_dims(kw)
	var zs: float = md.h + 0.15
	var l: float = md.l
	# the Workshop's tree (WORKSHOP.md §4, milestone K6): kit/README.md "Workshop: the motor"
	var mo := C.motor_h(m, Vector3(0, l * 0.5, zs), Vector3(0, 1, 0), kw, 0.15, "paint_motor", g, "stator",
		{"explode": [Vector3(0, 0, 1), 0.0], "rotor_anim": "shaft"})
	g.comp("baseplate", {"explode": [Vector3(0, 0, 1), 0.0]})
	C.baseplate(m, Vector3(-mo.r - 0.1, -l * 0.5 - 0.1, 0), Vector3(mo.r + 0.1, l * 0.5 + 0.1, 0.15))
	g.comp("rotor")
	var sh = g.move("shaft", Vector3(0, 0, zs), Vector3(0, 1, 0), "rotate", 0.0)
	sh.use("steel", "identify")
	sh.cyl(Vector3(0, l * 0.5, zs), Vector3(0, l * 0.5 + md.h * 0.6, zs), md.h * 0.15, -1.0, 12)
	sh.use("paint_yellow", "identify")
	sh.box(Vector3(0, l * 0.5 + md.h * 0.3, zs + md.h * 0.15), Vector3(md.h * 0.05, md.h * 0.4, 0.01))
	g.plate("side", Vector3(mo.r + 0.01, 0, zs), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-mo.r, -l * 0.5, 0), Vector3(mo.r, l * 0.5, zs + mo.r))
	g.axis_line = [Vector3(0, -l * 0.5, zs), Vector3(0, l * 0.5, zs)]
