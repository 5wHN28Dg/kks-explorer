## Pumps, fans, compressors and motors (docs/PLANT3D.md §9 "Rotating"). Every one has a `shaft` node turning about
## its shaft line (kit/README.md "Moving parts"): what a trainee sees turn (a coupling's painted stripe through the
## guard, a fan's blades, a cooling fan under its grille).
extends RefCounted

const C = preload("res://kit/parts_common.gd")

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
		m.lathe(Vector3(0, y_c - Tw * 0.5, zs), Vector3(0, 1, 0), [[Rv * 0.45, 0.0], [Rv * 0.95, 0.0], [Rv, Tw * 0.2], [Rv, Tw * 0.8], [Rv * 0.95, Tw], [ds * 0.5, Tw]], 0, true)
		# the volute's scroll grows towards the discharge: an offset second shell
		m.cyl(Vector3(0.0, y_c - Tw * 0.4, zs + Rv * 0.12), Vector3(0.0, y_c + Tw * 0.4, zs + Rv * 0.12), Rv * 0.92, -1.0)
		m.box_lh(Vector3(-Rv * 0.4, y_c - Tw * 0.3, 0.15), Vector3(Rv * 0.4, y_c + Tw * 0.3, zs - Rv * 0.6))
		var Rf := Rv * 0.38
		var lb := 0.35 + Rv
		m.cyl(Vector3(0, y_c - Tw * 0.5, zs), Vector3(0, y_c - Tw * 0.5 - lb, zs), Rf, Rf * 0.9)
		m.box_lh(Vector3(-Rf, y_c - Tw * 0.5 - lb, 0.15), Vector3(Rf, y_c - Tw * 0.5 - lb + 0.15, zs))
		y_back = y_c - Tw * 0.5 - lb
		C.bolt_ring(m, Vector3(0, y_c - Tw * 0.45, zs), Vector3(0, 1, 0), Rv * 0.75, 12, 0.008, 0.05)
		g.plate("pump_side", Vector3(Rv + 0.01, y_c, zs), Vector3(1, 0, 0), "large")
	# suction: a reducer from the casing to the suction flange at the front (kit.json: [0, L/2, 0.6] facing north)
	m.use("paint_pump", "identify")
	var y_in := y_c + (0.25 if multistage else Rv * 0.35)
	m.cyl(Vector3(0, y_in, zs), Vector3(0, y_suc, zs), ds * 0.38, ds * 0.5, 0, false)
	C.flange(m, Vector3(0, y_suc, zs), Vector3(0, 1, 0), ds, "paint_pump")
	# discharge: up from the casing's top to its flange at 1.4 m
	var z_top := zs + (Rv if not multistage else clampf(Rv * 0.85 + head / 6000.0, 0.16, 0.5)) * 0.9
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, y_c, z_top - 0.1), Vector3(0, y_c, 1.4), dd * 0.5, -1.0, 0, false)
	C.flange(m, Vector3(0, y_c, 1.4), Vector3(0, 0, 1), dd, "paint_pump", "pn40" if head > 100 else "pn16")
	# coupling, guard and motor
	var md := C.motor_dims(kw)
	var gap := clampf(0.15 + md.h * 0.3, 0.18, 0.5)
	var y_mf := y_back - gap
	var mo := C.motor_h(m, Vector3(0, y_mf, zs), Vector3(0, 1, 0), kw, 0.15)
	g.plate("motor_side", Vector3(mo.r * 0.92 + 0.01, y_mf - mo.l * 0.5, zs), Vector3(1, 0, 0), "large")
	var sh = g.move("shaft", Vector3(0, 0, zs), Vector3(0, 1, 0), "rotate", 0.0)
	C.coupling(sh, Vector3(0, y_mf + 0.01, zs), Vector3(0, y_back - 0.01, zs), clampf(md.h * 0.35, 0.05, 0.25))
	C.guard(m, Vector3(0, y_mf, zs), Vector3(0, y_back, zs), clampf(md.h * 0.35, 0.05, 0.25) * 1.15, 0.15)
	# the baseplate under everything
	var y_lo := minf(-L * 0.5, mo.back.y - 0.1)
	var w := maxf(mo.r * 2.0 + 0.2, Rv * 2.0 + 0.2)
	C.baseplate(m, Vector3(-w * 0.5, y_lo, 0.0), Vector3(w * 0.5, y_suc - 0.15, 0.15), "paint_darkgrey")
	g.solid_box(Vector3(-w * 0.5, y_lo, 0), Vector3(w * 0.5, y_suc, zs + maxf(mo.r, Rv)))
	g.axis_line = [Vector3(0, y_lo, zs), Vector3(0, y_suc, zs)]

static func pump_vertical(_part: String, g) -> void:
	var m = g.m
	var flow: float = g.num("flow_m3h", 1000)
	var kw: float = g.num("motor_kw", 200)
	var pit: float = g.num("pit_depth", 6)
	var dd: float = g.od(dn_for(g, flow, 3.0))
	var rc := dd * 0.5
	# the discharge head: from the floor up past the discharge branch at 1.5 m
	var rh := maxf(rc + 0.12, 0.25)
	var zh := 1.5 + rc + 0.25
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, 0, 0.05), Vector3(0, 0, zh), rh, rh * 0.9)
	m.use("paint_pump", "form")
	m.box(Vector3(0, 0, 0.04), Vector3(rh * 2.6, rh * 2.6, 0.08))          # sole plate
	C.bolt_ring(m, Vector3(0, 0, 0.08), Vector3(0, 0, 1), rh * 1.15, 8, 0.02, 0.08)
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, 0, 1.5), Vector3(0, 1.2, 1.5), rc, -1.0, 0, false)    # the branch to the discharge flange
	C.flange(m, Vector3(0, 1.2, 1.5), Vector3(0, 1, 0), dd, "paint_pump")
	# the column and the bowls down in the pit or can, the bell mouth at the bottom (the suction nozzle)
	m.use("paint_pump", "form")
	if pit > 0.1:
		m.cyl(Vector3(0, 0, 0.0), Vector3(0, 0, -pit + rc * 2.5), rc * 0.8, -1.0, 0, false)
		var nfl := maxi(1, int(pit / 3.0))
		for i in nfl:
			C.flange_pair(m, Vector3(0, 0, -pit * (i + 1) / (nfl + 1)), Vector3(0, 0, 1), dd * 0.8, "paint_pump")
		m.lathe(Vector3(0, 0, -pit), Vector3(0, 0, 1), [[rc * 1.5, 0.0], [rc * 1.4, rc * 0.4], [rc * 1.05, rc * 1.4], [rc * 0.8, rc * 2.5]], 0, false)
	# the motor stool (open: the coupling turns in its windows) and the motor on it
	var zs0 := zh
	var hs := clampf(0.4 + rc * 0.5, 0.45, 1.1)
	m.use("paint_pump", "identify")
	m.cyl(Vector3(0, 0, zs0), Vector3(0, 0, zs0 + 0.06), rh * 1.05)
	m.cyl(Vector3(0, 0, zs0 + hs - 0.06), Vector3(0, 0, zs0 + hs), rh * 1.05)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := Vector3(cos(a), sin(a), 0) * rh * 0.9
		m.box_lh(p + Vector3(-0.05, -0.05, zs0), p + Vector3(0.05, 0.05, zs0 + hs))
	var sh = g.move("shaft", Vector3(0, 0, zs0), Vector3(0, 0, 1), "rotate", 0.0)
	C.coupling(sh, Vector3(0, 0, zs0 + 0.06), Vector3(0, 0, zs0 + hs - 0.06), clampf(rh * 0.35, 0.06, 0.25))
	var mo := C.motor_v(m, Vector3(0, 0, zs0 + hs), kw)
	g.plate("motor_side", Vector3(mo.r + 0.01, 0, zs0 + hs + 0.6), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, mo.top), maxf(rh, mo.r))
	g.axis_line = [Vector3(0, 0, -pit), Vector3(0, 0, mo.top)]

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
	var mo := C.motor_h(m, Vector3(0, l * 0.5, zs), Vector3(0, 1, 0), kw, 0.15)
	C.baseplate(m, Vector3(-mo.r - 0.1, -l * 0.5 - 0.1, 0), Vector3(mo.r + 0.1, l * 0.5 + 0.1, 0.15))
	var sh = g.move("shaft", Vector3(0, 0, zs), Vector3(0, 1, 0), "rotate", 0.0)
	sh.use("steel", "identify")
	sh.cyl(Vector3(0, l * 0.5, zs), Vector3(0, l * 0.5 + md.h * 0.6, zs), md.h * 0.15, -1.0, 12)
	sh.use("paint_yellow", "identify")
	sh.box(Vector3(0, l * 0.5 + md.h * 0.3, zs + md.h * 0.15), Vector3(md.h * 0.05, md.h * 0.4, 0.01))
	g.plate("side", Vector3(mo.r + 0.01, 0, zs), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-mo.r, -l * 0.5, 0), Vector3(mo.r, l * 0.5, zs + mo.r))
	g.axis_line = [Vector3(0, -l * 0.5, zs), Vector3(0, l * 0.5, zs)]
