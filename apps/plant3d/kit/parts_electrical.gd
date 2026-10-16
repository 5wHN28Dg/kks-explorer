## Electrical equipment (docs/PLANT3D.md §9 "Electrical"): transformers (tank, radiators, conservator, bushings),
## breakers (the `contacts` node: a position flag behind the mechanism's window: its green face, "open", shows at
## 0, its red face, "closed", at 1; it turns by PI/2 about its axis), switchgear, cabinets, junction boxes, cable trays.
extends RefCounted

const C = preload("res://kit/parts_common.gd")

## A porcelain bushing (sheds on a core) from c up by h.
static func bushing(m, c: Vector3, h: float, r: float, dir := Vector3(0, 0, 1)) -> void:
	m.use("porcelain", "identify")
	var prof: Array = [[r * 0.8, 0.0]]
	var n := clampi(int(h / 0.12), 4, 24)
	for i in n:
		var t := h * (i + 0.2) / n
		prof.append([r * 0.75, t])
		prof.append([r * 1.4, t + h * 0.25 / n])
		prof.append([r * 0.75, t + h * 0.5 / n])
	prof.append([r * 0.6, h])
	m.lathe(c, dir, prof, 12, true)
	m.use("chrome", "identify")
	m.cyl(c + dir * h, c + dir * (h + r * 0.8), r * 0.35, -1.0, 8)

static func transformer(_part: String, g) -> void:
	var m = g.m
	var mva: float = g.num("mva", 300)
	var gsu: bool = g.p.get("kind", "gsu") == "gsu"
	var nr := int(g.num("radiators", 6))
	var nb := int(g.num("bushings", 6))
	var s := pow(maxf(mva, 0.1) / 300.0, 1.0 / 3.0)
	var W := 3.2 * s + 0.6
	var L := 6.0 * s + 0.8
	var Ht := 4.0 * s + 0.6
	var z0 := 0.4
	# the plinth and the oil pit's gravel round it
	m.use("concrete", "form")
	m.box_lh(Vector3(-W * 0.5 - 2.0, -L * 0.5 - 1.5, 0), Vector3(W * 0.5 + 2.0, L * 0.5 + 1.5, 0.15))
	m.use("gravel", "form")
	m.box_lh(Vector3(-W * 0.5 - 1.8, -L * 0.5 - 1.3, 0.15), Vector3(W * 0.5 + 1.8, L * 0.5 + 1.3, 0.2))
	m.use("concrete", "form")
	m.box_lh(Vector3(-W * 0.4, -L * 0.45, 0.2), Vector3(W * 0.4, L * 0.45, z0))
	# the tank, its cover and stiffeners
	m.use("paint_trafo", "identify")
	m.box_lh(Vector3(-W * 0.5, -L * 0.5, z0), Vector3(W * 0.5, L * 0.5, z0 + Ht))
	m.box_lh(Vector3(-W * 0.5 - 0.08, -L * 0.5 - 0.08, z0 + Ht), Vector3(W * 0.5 + 0.08, L * 0.5 + 0.08, z0 + Ht + 0.12))
	m.use("paint_trafo", "detail", 0.12)
	var k := maxi(3, int(L / 0.9))
	for i in k + 1:
		var y := -L * 0.5 + L * i / k
		for sx: float in [-1.0, 1.0]:
			m.box(Vector3(sx * (W * 0.5 + 0.06), y, z0 + Ht * 0.5), Vector3(0.12, 0.14, Ht - 0.1))
	C.bolt_ring(m, Vector3(0, 0, z0 + Ht + 0.06), Vector3(0, 0, 1), minf(W, L) * 0.45, 24, 0.012, 0.15)
	# radiator banks along both sides, with their headers and fans
	var per := (nr + 1) / 2
	var rh := Ht * 0.85
	for sx: float in [-1.0, 1.0]:
		var cnt := per if sx > 0 else nr - per
		for i in cnt:
			var y := -L * 0.4 + L * 0.8 * (i + 0.5) / maxf(cnt, 1)
			var x := sx * (W * 0.5 + 0.35 + 0.6)
			m.use("paint_trafo", "identify")
			m.box(Vector3(x, y, z0 + Ht * 0.52), Vector3(1.2, 0.55, rh))
			m.use("paint_trafo", "detail", 0.03)
			for f in 9:
				m.box(Vector3(x, y - 0.25 + f * 0.0625, z0 + Ht * 0.52), Vector3(1.24, 0.012, rh * 0.97))
			m.use("paint_trafo", "form")
			for zz: float in [z0 + Ht * 0.52 - rh * 0.5, z0 + Ht * 0.52 + rh * 0.5]:
				m.cyl(Vector3(sx * W * 0.5, y, zz), Vector3(x, y, zz), 0.07, -1.0, 8)
			if mva > 20.0:   # a cooling fan under each bank
				m.use("paint_darkgrey", "form")
				m.cyl(Vector3(x, y, z0 + Ht * 0.52 - rh * 0.5 - 0.35), Vector3(x, y, z0 + Ht * 0.52 - rh * 0.5 - 0.1), 0.35, -1.0, 16)
	# the conservator on top at one end, its pipe to the tank (Buchholz relay)
	var cr := 0.35 + s * 0.25
	var cy := L * 0.5 - cr - 0.2
	m.use("paint_trafo", "identify")
	m.cyl(Vector3(-W * 0.45, cy, z0 + Ht + 0.9 + cr), Vector3(W * 0.45, cy, z0 + Ht + 0.9 + cr), cr)
	m.use("paint_trafo", "form")
	for x: float in [-W * 0.3, W * 0.3]:
		m.box_lh(Vector3(x - 0.06, cy - 0.06, z0 + Ht + 0.12), Vector3(x + 0.06, cy + 0.06, z0 + Ht + 0.9 + cr * 0.5))
	m.cyl(Vector3(0, cy, z0 + Ht + 0.12), Vector3(0, cy, z0 + Ht + 0.9), 0.05, -1.0, 8)
	m.use("paint_darkgrey", "identify")
	m.box(Vector3(0, cy, z0 + Ht + 0.5), Vector3(0.2, 0.15, 0.15))
	# bushings: HV on one end of the cover, LV on the other (a GSU's LV goes into the bus duct)
	var nhv := clampi(nb / 2, 1, 4)
	var nlv := nb - nhv
	var hv_h := (1.2 + s * 1.8) if gsu else (0.8 + s * 0.6)
	for i in nhv:
		var x := -W * 0.35 + W * 0.7 * (i + 0.5) / nhv
		bushing(m, Vector3(x, -L * 0.3, z0 + Ht + 0.12), hv_h, 0.12 + s * 0.06)
	for i in nlv:
		var x := -W * 0.35 + W * 0.7 * (i + 0.5) / maxf(nlv, 1)
		bushing(m, Vector3(x, L * 0.05, z0 + Ht + 0.12), hv_h * 0.35, 0.1 + s * 0.04)
	if gsu:   # the isolated phase bus duct's terminal enclosure over the LV bushings
		m.use("cladding", "identify")
		m.box_lh(Vector3(-W * 0.45, L * 0.05 - 0.5, z0 + Ht + 0.2), Vector3(W * 0.45, L * 0.05 + 0.5, z0 + Ht + hv_h * 0.35 + 0.5))
		for i in nlv:
			var x := -W * 0.35 + W * 0.7 * (i + 0.5) / maxf(nlv, 1)
			m.cyl(Vector3(x, L * 0.05, z0 + Ht + hv_h * 0.35 + 0.5), Vector3(x, L * 0.05, z0 + Ht + hv_h * 0.35 + 1.4), 0.35, -1.0, 16)
	# the tap changer's compartment, the control cabinet and the cable box
	m.use("paint_trafo", "identify")
	m.box(Vector3(W * 0.5 + 0.3, -L * 0.45, z0 + Ht * 0.6), Vector3(0.6, 0.8, Ht * 0.6))
	m.use("paint_grey", "identify")
	m.box(Vector3(-W * 0.5 - 0.25, -L * 0.5 + 0.6, z0 + 0.9), Vector3(0.5, 0.8, 1.6))
	m.use("glass", "identify")
	for i in 2:   # the oil and winding temperature indicators' dials
		m.disk(Vector3(-W * 0.5 - 0.501, -L * 0.5 + 0.45 + i * 0.3, z0 + 1.35), Vector3(-1, 0, 0), 0.08, 16)
	g.plate("tank", Vector3(-W * 0.5 - 0.13, -L * 0.15, z0 + 1.6), Vector3(-1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5 - 1.6, -L * 0.5, 0), Vector3(W * 0.5 + 1.6, L * 0.5, z0 + Ht + 1.0))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, z0 + Ht)]

## A generator circuit breaker in its isolated phase bus (three aluminium phase enclosures and the operating
## mechanism's cabinet), or a medium voltage breaker in its panel. `contacts` is the position flag.
static func breaker(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 6)
	var gcb: bool = g.p.get("kind", "gcb") == "gcb"
	var win: Vector3
	if gcb:
		var zc := 2.4
		m.use("paint_darkgrey", "form")
		m.box_lh(Vector3(-1.6, -L * 0.5, 0), Vector3(1.6, L * 0.5, 0.1))
		for y: float in [-L * 0.35, L * 0.35]:
			for x: float in [-1.3, 1.3]:
				m.box_lh(Vector3(x - 0.08, y - 0.08, 0.1), Vector3(x + 0.08, y + 0.08, zc - 0.5))
			m.box_lh(Vector3(-1.4, y - 0.1, zc - 0.6), Vector3(1.4, y + 0.1, zc - 0.5))
		m.use("cladding", "identify")
		for i in 3:
			var x := -1.0 + i * 1.0
			m.cyl(Vector3(x, -L * 0.5, zc), Vector3(x, L * 0.5, zc), 0.42)
			m.cyl(Vector3(x, -L * 0.15, zc), Vector3(x, L * 0.15, zc), 0.55)   # the breaker's interrupter housing
			m.use("cladding", "detail", 0.05)
			for y: float in [-L * 0.15, L * 0.15, -L * 0.45, L * 0.45]:
				m.cyl(Vector3(x, y - 0.03, zc), Vector3(x, y + 0.03, zc), 0.6 if absf(y) < L * 0.2 else 0.47)
			m.use("cladding", "identify")
		m.use("paint_grey", "identify")
		m.box_lh(Vector3(1.6, -0.7, 0.1), Vector3(2.4, 0.7, 2.0))   # the operating mechanism's cabinet
		win = Vector3(2.4, 0.0, 1.5)
		g.plate("side", Vector3(2.41, -0.4, 1.85), Vector3(1, 0, 0), "large")
		g.solid_box(Vector3(-1.6, -L * 0.5, 0), Vector3(2.4, L * 0.5, zc + 0.6))
	else:
		m.use("paint_grey", "identify")
		m.box_lh(Vector3(-0.4, -0.75, 0), Vector3(0.4, 0.75, 2.3))
		m.use("paint_darkgrey", "identify")
		m.box(Vector3(0.0, 0.751, 1.2), Vector3(0.7, 0.004, 0.006))
		win = Vector3(0.0, 0.75, 1.5)
		g.plate("side", Vector3(0.0, 0.752, 2.0), Vector3(0, 1, 0), "large")
		g.solid_box(Vector3(-0.4, -0.75, 0), Vector3(0.4, 0.75, 2.3))
	# the window and the flag behind it
	var out := Vector3(1, 0, 0) if gcb else Vector3(0, 1, 0)
	m.use("glass", "identify")
	m.box(win + out * 0.002, (Vector3(0.004, 0.004, 0.004) + (Vector3(0, 1, 1) if gcb else Vector3(1, 0, 1)) * 0.16))
	# turning by +PI/2 brings the top (green) face round to the window
	var flag = g.move("contacts", win - out * 0.06, Vector3(0, 1, 0) if gcb else Vector3(-1, 0, 0), "rotate", PI * 0.5)
	var c := win - out * 0.06
	flag.use("paint_green", "identify")   # open (0): green
	flag.box(c + out * 0.05, (out * 0.01).abs() + (Vector3(0, 0.12, 0.12) if gcb else Vector3(0.12, 0, 0.12)))
	flag.use("paint_red", "identify")     # closed (1): red, on the face that turns to the window
	flag.box(c + Vector3(0, 0, 0.05), Vector3(0.12, 0.12, 0.01))
	flag.use("paint_white", "identify")   # its "I", upright once turned
	flag.box(c + Vector3(0, 0, 0.056), (out * 0.08).abs() + (Vector3(0, 0.015, 0.004) if gcb else Vector3(0.015, 0, 0.004)))
	g.axis_line = [Vector3(0, -L * 0.5, 1.5), Vector3(0, L * 0.5, 1.5)]

## A switchgear line-up: panels with the breakers' doors, their windows and the busbar chamber on top.
static func switchgear_row(_part: String, g) -> void:
	var m = g.m
	var n := int(g.num("panels", 10))
	var D: float = g.num("depth", 1.5)
	var w := 0.8
	var W := n * w
	var h := 2.3
	m.use("paint_darkgrey", "form")
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, 0), Vector3(W * 0.5, D * 0.5, 0.1))
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, 0.1), Vector3(W * 0.5, D * 0.5, h))
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, h), Vector3(W * 0.5, D * 0.3, h + 0.3))
	for i in n:
		var x := -W * 0.5 + w * (i + 0.5)
		m.use("paint_darkgrey", "identify")
		m.box(Vector3(x - w * 0.5, D * 0.5 + 0.002, h * 0.5), Vector3(0.008, 0.004, h - 0.1))
		m.box(Vector3(x, D * 0.5 + 0.002, h * 0.62), Vector3(w * 0.85, 0.004, 0.008))
		m.box(Vector3(x + w * 0.35, D * 0.5 + 0.015, h * 0.4), Vector3(0.025, 0.03, 0.18))
		m.use("glass", "identify")
		m.box(Vector3(x, D * 0.5 + 0.003, h * 0.45), Vector3(w * 0.3, 0.006, 0.15))
		m.box(Vector3(x - w * 0.15, D * 0.5 + 0.003, h * 0.8), Vector3(w * 0.4, 0.006, 0.2))
		m.use(["lamp_red", "lamp_green"][i % 2], "identify")
		m.cyl(Vector3(x + w * 0.2, D * 0.5, h * 0.8), Vector3(x + w * 0.2, D * 0.5 + 0.02, h * 0.8), 0.018, -1.0, 8)
	g.plate("front", Vector3(-W * 0.5 + 0.4, D * 0.5 + 0.004, h + 0.15), Vector3(0, 1, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -D * 0.5, 0), Vector3(W * 0.5, D * 0.5, h + 0.3))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, h)]

static func cabinet(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 1.2)
	var H: float = g.num("height", 2.2)
	var D: float = g.num("depth", 0.8)
	m.use("paint_darkgrey", "form")
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, 0), Vector3(W * 0.5, D * 0.5, 0.1))
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, 0.1), Vector3(W * 0.5, D * 0.5, H))
	var nd := maxi(1, int(round(W / 0.8)))
	for i in nd:
		var x := -W * 0.5 + W * (i + 0.5) / nd
		m.use("paint_darkgrey", "identify")
		m.box(Vector3(x - W * 0.5 / nd, D * 0.5 + 0.002, H * 0.5), Vector3(0.008, 0.004, H - 0.2))
		m.box(Vector3(x + W * 0.35 / nd, D * 0.5 + 0.015, H * 0.55), Vector3(0.025, 0.03, 0.16))
		m.use("dark", "identify")
		m.box(Vector3(x, D * 0.5 + 0.002, 0.3), Vector3(W * 0.6 / nd, 0.004, 0.15))
	g.plate("front", Vector3(-W * 0.5 + 0.25, D * 0.5 + 0.004, H - 0.15), Vector3(0, 1, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -D * 0.5, 0), Vector3(W * 0.5, D * 0.5, H))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

static func junction_box(_part: String, g) -> void:
	var m = g.m
	m.use("galvanised", "form")
	m.box(Vector3(0, -0.08, 0.6), Vector3(0.06, 0.06, 1.2))
	m.use("paint_grey", "identify")
	m.box(Vector3(0, 0.02, 1.0), Vector3(0.4, 0.15, 0.4))
	m.use("steel_dark", "detail", 0.03)
	for i in 4:
		m.cyl(Vector3(-0.15 + i * 0.1, 0.02, 0.8), Vector3(-0.15 + i * 0.1, 0.02, 0.76), 0.015, -1.0, 6)
	g.plate("front", Vector3(0, 0.096, 1.15), Vector3(0, 1, 0), "small")

## A ladder-type cable tray along its route, on posts where it runs low and on hangers otherwise.
static func cable_tray(_part: String, g) -> void:
	var m = g.m
	var route: Array = g.p.get("route", [])
	var w: float = g.num("width", 0.6)
	for i in range(route.size() - 1):
		var a := Vector3(float(route[i][0]), float(route[i][1]), float(route[i][2]) if route[i].size() > 2 else 0.0)
		var b := Vector3(float(route[i + 1][0]), float(route[i + 1][1]), float(route[i + 1][2]) if route[i + 1].size() > 2 else 0.0)
		var dl := a.distance_to(b)
		if dl < 0.01:
			continue
		var d := (b - a) / dl
		var side := d.cross(Vector3(0, 0, 1)).normalized() if absf(d.z) < 0.9 else Vector3(1, 0, 0)
		m.use("galvanised", "form")
		for s: float in [-1.0, 1.0]:
			m.box((a + b) * 0.5 + side * (w * 0.5 * s), Vector3(0.0, 0.0, 0.0) + (side * 0.01).abs() + (d * dl).abs() + Vector3(0, 0, 0.1))
		m.use("galvanised", "detail", 0.03)
		var k := int(dl / 0.3)
		for j in k:
			var p := a + d * (dl * (j + 0.5) / k)
			m.box(p - Vector3(0, 0, 0.04), (side * w).abs() + (d * 0.025).abs() + Vector3(0, 0, 0.012))
		m.use("galvanised", "form")
		var np := int(dl / 3.0)
		for j in np + 1:
			var p := a + d * (dl * j / maxf(np, 1))
			if p.z > 0.3 and p.z < 6.0:
				m.box_lh(Vector3(p.x - 0.04, p.y - 0.04, 0), Vector3(p.x + 0.04, p.y + 0.04, p.z - 0.05))
	g.axis_line = [Vector3.ZERO, Vector3(0, 0, 1)]
