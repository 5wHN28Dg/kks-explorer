## Heat exchange (docs/PLANT3D.md §9 "Heat exchange"): the condenser, shell-and-tube and plate heat exchangers and the
## wet cooling tower (mechanical draft, counterflow: its cells, air inlets with louvres, fill, casing, the hot water
## header; the fans stand on its deck as parts of their own, the deck itself is the content's walkable platform when
## there is one: ctx.decks).
extends RefCounted

const C = preload("res://kit/parts_common.gd")

static func _nozzles(g, names: Array, mat: String, stub := 0.6, rating := "pn16") -> void:
	for n in names:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, 0.0)
		if od <= 0.0:
			od = g.ctx.get("nozzle_od", {}).get(n, 0.2)
		var dir: Vector3 = {"n": Vector3(0, 1, 0), "s": Vector3(0, -1, 0), "e": Vector3(1, 0, 0), "w": Vector3(-1, 0, 0), "up": Vector3(0, 0, 1), "down": Vector3(0, 0, -1)}[spec.dir]
		C.nozzle(g.m, p - dir * stub, p, od, mat, rating)

static func condenser(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 14)
	var W: float = g.num("width", 12)
	var H: float = g.num("height", 16)
	var wb := int(g.num("waterboxes", 4))
	var hot: bool = g.p.get("hotwell", true)
	var zh := 1.5 if hot else 0.0
	m.use("paint_grey", "identify")
	if hot:   # the hotwell: narrower, under the shell
		m.box_lh(Vector3(-W * 0.35, -L * 0.4, 0.2), Vector3(W * 0.35, L * 0.4, zh))
	m.box_lh(Vector3(-W * 0.5, -L * 0.5, zh), Vector3(W * 0.5, L * 0.5, H - 1.0))
	# the neck up to the turbine's exhaust, with its expansion joint at the top
	m.hexa([Vector3(-W * 0.5, -L * 0.5, H - 1.0), Vector3(W * 0.5, -L * 0.5, H - 1.0), Vector3(W * 0.5, L * 0.5, H - 1.0), Vector3(-W * 0.5, L * 0.5, H - 1.0),
		Vector3(-W * 0.4, -L * 0.42, H - 0.3), Vector3(W * 0.4, -L * 0.42, H - 0.3), Vector3(W * 0.4, L * 0.42, H - 0.3), Vector3(-W * 0.4, L * 0.42, H - 0.3)])
	m.use("rubber", "identify")
	m.box_lh(Vector3(-W * 0.41, -L * 0.43, H - 0.3), Vector3(W * 0.41, L * 0.43, H))
	m.use("paint_grey", "detail", 0.12)
	var k := maxi(3, int(L / 1.5))
	for i in k + 1:   # the shell's stiffeners
		var y := -L * 0.5 + L * i / k
		for s: float in [-1.0, 1.0]:
			m.box(Vector3(s * (W * 0.5 + 0.06), y, (zh + H - 1.0) * 0.5), Vector3(0.12, 0.15, H - 1.0 - zh))
	# the water boxes on both ends: half drums, one or two per end, with manways
	var per := 2 if wb >= 4 else 1
	for s: float in [-1.0, 1.0]:
		for j in per:
			var x0 := -W * 0.5 + W * j / per
			var x1 := x0 + W / per
			var zc := 0.5 + (H * 0.55 - 0.5) * 0.5
			var rz := (H * 0.55 - 0.5) * 0.5
			m.use("paint_motor", "identify")   # the water boxes are painted apart (cooling water side)
			var prof: Array = []
			for i in 9:
				var a := PI * i / 8.0
				prof.append(Vector2(-cos(a) * rz, sin(a) * 0.9))
			# a half-round box: its section (z across, y out) extruded along x
			var pts: Array = []
			for q in prof:
				pts.append(Vector2(q.y, q.x))
			# extruded along u x w: +x on the north end, -x on the south end
			var start := Vector3(x0 + 0.05, s * L * 0.5, zc) if s > 0 else Vector3(x1 - 0.05, s * L * 0.5, zc)
			m.prism(start, Vector3(0, s, 0), Vector3(0, 0, 1), pts, (x1 - x0) - 0.1)
			m.use("steel", "identify")   # a manway cover
			m.cyl(Vector3((x0 + x1) * 0.5, s * (L * 0.5 + 0.85), zc + rz * 0.35), Vector3((x0 + x1) * 0.5, s * (L * 0.5 + 0.98), zc + rz * 0.35), 0.35, -1.0, 16)
			C.bolt_ring(m, Vector3((x0 + x1) * 0.5, s * (L * 0.5 + 0.93), zc + rz * 0.35), Vector3(0, 1, 0), 0.31, 16, 0.012, 0.08)
	_nozzles(g, ["cw_inlet_a", "cw_inlet_b", "cw_outlet_a", "cw_outlet_b"], "paint_motor", 0.15)
	_nozzles(g, ["bypass_in", "recirc_in", "hotwell_out", "air_out"], "paint_grey", 0.5)
	# feet
	m.use("concrete", "form")
	for x: float in [-W * 0.35, W * 0.35]:
		for y: float in [-L * 0.35, 0.0, L * 0.35]:
			m.box_lh(Vector3(x - 0.4, y - 0.4, 0), Vector3(x + 0.4, y + 0.4, 0.2))
	g.plate("shell", Vector3(W * 0.5 + 0.13, -L * 0.3, 3.0), Vector3(1, 0, 0), "large")
	g.plate("waterbox", Vector3(-W * 0.25, -L * 0.5 - 0.92, H * 0.3 + 0.8), Vector3(0, -1, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, H))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

static func shell_tube_hx(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 1.2)
	var L: float = g.num("length", 5)
	var vert: bool = g.p.get("orientation", "horizontal") == "vertical"
	var r := d * 0.5
	if vert:
		var keep: Transform3D = m.xf
		m.use("paint_tank", "identify")
		m.cyl(Vector3(0, 0, 0.6), Vector3(0, 0, L - 0.3), r)
		m.dish(Vector3(0, 0, L - 0.3), Vector3(0, 0, 1), r, r * 0.4, 0, 4)
		C.flange_pair(m, Vector3(0, 0, L - r * 0.8), Vector3(0, 0, 1), d, "paint_tank")
		m.use("paint_darkgrey", "form")
		for k in 4:
			var a := TAU * (k + 0.5) / 4.0
			m.box_lh(Vector3(cos(a) * r * 0.9 - 0.06, sin(a) * r * 0.9 - 0.06, 0), Vector3(cos(a) * r * 0.9 + 0.06, sin(a) * r * 0.9 + 0.06, 1.0))
		m.xf = keep
		g.plate("shell", Vector3(r + 0.01, 0, 1.5), Vector3(1, 0, 0), "large")
		g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, L), r)
		g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, L)]
		return
	var zc := r + 0.5
	m.use("paint_tank", "identify")
	m.cyl(Vector3(0, -L * 0.5 + 0.5, zc), Vector3(0, L * 0.5 - 0.3, zc), r, -1.0, 0, false)
	m.dish(Vector3(0, L * 0.5 - 0.3, zc), Vector3(0, 1, 0), r, 0.3, 0, 4)
	m.use("paint_grey", "identify")   # the channel head with its flange
	m.cyl(Vector3(0, -L * 0.5 + 0.1, zc), Vector3(0, -L * 0.5 + 0.5, zc), r)
	m.dish(Vector3(0, -L * 0.5 + 0.1, zc), Vector3(0, -1, 0), r, 0.1 + r * 0.2, 0, 4)
	C.flange_pair(m, Vector3(0, -L * 0.5 + 0.5, zc), Vector3(0, 1, 0), d, "paint_grey")
	m.use("paint_darkgrey", "form")
	for y: float in [-L * 0.3, L * 0.3]:
		m.box_lh(Vector3(-r * 0.75, y - 0.12, 0), Vector3(r * 0.75, y + 0.12, zc - r * 0.5))
	_nozzles(g, ["shell_in", "shell_out", "tube_in", "tube_out"], "paint_tank", 0.25)
	g.plate("shell", Vector3(r + 0.01, 0, zc), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc), r)
	g.axis_line = [Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc)]

## A plate heat exchanger: the fixed frame plate with its four nozzles (kit.json), the plate pack, the pressure
## plate, the carrying and guide bars, the end support and the tightening bolts.
static func plate_hx(_part: String, g) -> void:
	var m = g.m
	var n := int(g.num("plates", 200))
	var H: float = g.num("height", 2.2)
	var Wp := clampf(H * 0.42, 0.3, 1.6)
	var pack := clampf(n * 0.0045, 0.05, 4.0)
	var yf := 0.45
	var yb := yf - 0.08 - pack - 0.08
	var yc := yb - 0.4
	m.use("paint_motor", "identify")
	m.box_lh(Vector3(-Wp * 0.6, yf - 0.08, 0.0), Vector3(Wp * 0.6, yf, H))                 # the fixed frame plate
	m.box_lh(Vector3(-Wp * 0.6, yb, 0.15), Vector3(Wp * 0.6, yb + 0.08, H - 0.05))          # the pressure plate
	m.use("steel", "identify")   # the plate pack: corrugated stainless plates
	m.box_lh(Vector3(-Wp * 0.5, yb + 0.08, 0.2), Vector3(Wp * 0.5, yf - 0.08, H - 0.15))
	m.use("steel_dark", "detail", 0.004)
	var k := clampi(int(pack / 0.03), 2, 60)
	for i in k:
		var y := yb + 0.08 + (pack) * (i + 0.5) / k
		m.box(Vector3(Wp * 0.505, y, H * 0.5), Vector3(0.004, 0.006, H - 0.4))
	m.use("steel", "form")   # the carrying bar on top, the guide bar below, the end column
	m.box_lh(Vector3(-0.05, yc, H - 0.1), Vector3(0.05, yf, H + 0.05))
	m.box_lh(Vector3(-0.04, yc, 0.12), Vector3(0.04, yf, 0.2))
	m.use("paint_motor", "form")
	m.box_lh(Vector3(-0.12, yc - 0.12, 0), Vector3(0.12, yc + 0.12, H + 0.05))
	m.use("steel", "detail", 0.04)
	for x: float in [-Wp * 0.62, Wp * 0.62]:
		for z: float in [0.4, H * 0.5, H - 0.4]:
			m.cyl(Vector3(x, yb - 0.1, z), Vector3(x, yf + 0.06, z), 0.02, -1.0, 6)
	_nozzles(g, ["hot_in", "hot_out", "cold_in", "cold_out"], "steel", 0.15)
	g.plate("frame", Vector3(0, yf + 0.005, H * 0.55), Vector3(0, 1, 0), "large")
	g.solid_box(Vector3(-Wp * 0.6, yc - 0.12, 0), Vector3(Wp * 0.6, yf, H))
	g.axis_line = [Vector3(0, yc, H * 0.5), Vector3(0, yf, H * 0.5)]

static func cooling_tower(_part: String, g) -> void:
	var m = g.m
	var nx := int(g.num("cells_x", 5))
	var ny := int(g.num("cells_y", 2))
	var L: float = g.num("length", 80)
	var W: float = g.num("width", 32)
	var H: float = g.num("height", 14)
	var fan_d: float = g.num("fan_d", 9.5)
	var fill: String = g.p.get("fill", "film")
	var deck := false
	for d in g.ctx.get("decks", []):
		if absf(float(d) - H) <= 0.5:
			deck = true
	var top := H - 0.15 if deck else H
	var hin := clampf(H * 0.32, 2.5, 6.0)   # the air inlets' height
	var zfill := hin + 0.1
	var cx := L / nx
	var cy := W / ny
	# columns at the cells' corners round the outside, and the casing above the air inlets
	m.use("concrete", "form")
	for i in nx + 1:
		for j: int in [0, ny]:
			var x := -L * 0.5 + cx * i
			var y := -W * 0.5 + cy * j
			m.box_lh(Vector3(x - 0.25, y - 0.25, 0.2), Vector3(x + 0.25, y + 0.25, hin))
	m.use("paint_ct", "identify")
	for s: float in [-1.0, 1.0]:   # long sides: casing above the inlets
		m.box_lh(Vector3(-L * 0.5, s * W * 0.5 - 0.06, hin), Vector3(L * 0.5, s * W * 0.5 + 0.06, top))
	for s: float in [-1.0, 1.0]:   # ends: closed walls full height
		m.box_lh(Vector3(s * L * 0.5 - 0.06, -W * 0.5, 0.2), Vector3(s * L * 0.5 + 0.06, W * 0.5, top))
	m.use("paint_ct", "detail", 0.1)
	for i in range(1, int(L / 2.0)):   # the casing panels' ribs
		var x := -L * 0.5 + i * 2.0
		for s: float in [-1.0, 1.0]:
			m.box(Vector3(x, s * (W * 0.5 + 0.07), (hin + top) * 0.5), Vector3(0.08, 0.04, top - hin))
	# the air inlets: louvres in front of the dark rain zone, the fill seen through them
	for s: float in [-1.0, 1.0]:
		m.use("dark", "identify")
		m.box_lh(Vector3(-L * 0.5, s * (W * 0.5 - 1.0) - 0.02, 0.2), Vector3(L * 0.5, s * (W * 0.5 - 1.0) + 0.02, hin))
		if s > 0:
			m.use("fill", "identify")
			m.box_lh(Vector3(-L * 0.5 + 0.1, -W * 0.5 + 0.3, zfill), Vector3(L * 0.5 - 0.1, W * 0.5 - 0.3, zfill + 1.5))
		m.use("paint_ct", "identify")
		var nl := int((hin - 0.4) / 0.45)
		for k in nl:
			var z := 0.45 + k * 0.45
			m.box(Vector3(0, s * (W * 0.5 - 0.15), z), Vector3(L, 0.32, 0.03), Basis(Vector3(1, 0, 0), deg_to_rad(40.0) * s))
	if fill == "film":   # film fill's vertical sheets show as stripes at the inlets
		m.use("dark", "detail", 0.05)
		var k := int(L / 0.6)
		for s: float in [-1.0, 1.0]:
			for i in k:
				var x := -L * 0.5 + 0.3 + i * 0.6
				m.box(Vector3(x, s * (W * 0.5 - 0.31), zfill + 0.75), Vector3(0.05, 0.01, 1.4))
	# the partition walls between the cells, seen on the deck as lines (and inside, through the inlets)
	m.use("paint_ct", "form")
	for i in range(1, nx):
		var x := -L * 0.5 + cx * i
		m.box_lh(Vector3(x - 0.05, -W * 0.5 + 1.0, zfill + 1.5), Vector3(x + 0.05, W * 0.5 - 1.0, top))
	for j in range(1, ny):
		var y := -W * 0.5 + cy * j
		m.box_lh(Vector3(-L * 0.5, y - 0.05, 0.2), Vector3(L * 0.5, y + 0.05, top))
	if not deck:   # the fan deck, when the content has none (the content's is walkable)
		m.use("concrete", "form")
		var holes: Array = []
		for i in nx:
			for j in ny:
				holes.append(Vector2(-L * 0.5 + cx * (i + 0.5), -W * 0.5 + cy * (j + 0.5)))
		m.box_lh(Vector3(-L * 0.5, -W * 0.5, H - 0.25), Vector3(L * 0.5, -W * 0.5 + (cy - fan_d) * 0.5, H))
		m.box_lh(Vector3(-L * 0.5, W * 0.5 - (cy - fan_d) * 0.5, H - 0.25), Vector3(L * 0.5, W * 0.5, H))
	# the hot water: the header along the south face from the riser (kit.json hot_water_in), a branch into each cell
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("hot_water_in", {})
	var od: float = g.ctx.get("used", {}).get("hot_water_in", 1.2)
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		var hz := p.z
		var hy := -W * 0.5 - 0.6 - od * 0.5
		m.use("galvanised", "identify")
		C.nozzle(m, Vector3(p.x, hy, hz), p, od, "galvanised")
		var ho := od * 0.6
		m.cyl(Vector3(-L * 0.5 + 2.0, hy, hz), Vector3(L * 0.5 - 2.0, hy, hz), ho * 0.5)
		m.use("galvanised", "form")
		for i in nx:
			var x := -L * 0.5 + cx * (i + 0.5)
			m.pipe_path([Vector3(x, hy, hz), Vector3(x, hy, hz + 0.0), Vector3(x, -W * 0.5 + 0.2, hz)], ho * 0.3, ho)
			m.use("paint_darkgrey", "identify")   # each cell's isolating valve (a butterfly with its gearbox)
			m.cyl(Vector3(x, hy + 0.3 + ho * 0.5, hz), Vector3(x, hy + 0.45 + ho * 0.5, hz), ho * 0.45)
			m.box(Vector3(x, hy + 0.37 + ho * 0.5, hz + ho * 0.5 + 0.15), Vector3(0.3, 0.25, 0.3))
			m.use("galvanised", "form")
		m.use("steel", "form")
		var k := maxi(2, int(L / 6.0))
		for i in k + 1:
			var x := -L * 0.5 + 2.0 + (L - 4.0) * i / k
			m.box_lh(Vector3(x - 0.08, hy - 0.08, hz - ho * 0.3 - 0.4), Vector3(x + 0.08, -W * 0.5, hz - ho * 0.3 - 0.25))
	var mspec: Dictionary = g.ctx.get("nozzles", {}).get("makeup_in", {})
	if not mspec.is_empty():
		var p: Vector3 = g.nozzle(mspec)
		C.nozzle(m, Vector3(L * 0.5 + 0.06, p.y, p.z), p, g.ctx.get("used", {}).get("makeup_in", 0.3), "galvanised")
	g.plate("basin", Vector3(L * 0.5 + 0.08, -W * 0.3, 1.8), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-L * 0.5, -W * 0.5, 0), Vector3(L * 0.5, W * 0.5, top))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]
