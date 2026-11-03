## The Workshop's run and views (docs/plant3d/WORKSHOP.md §3 "Run it" and "See inside", §6, §7; milestone K3), in the
## app as the trainee gets it, on the pressure transmitter:
## - the scene carries its bench model; the Workshop loads it into the plant's engine (sim/bench_model.gd);
## - the loop supply on, the applied pressure set: the isolating diaphragm moves by its travel × the model's value,
##   the display shows the damped reading and the current, the terminals the current, the impulse line's particles
##   move and the sensor's colour follows its pressure: every channel reads the model's value (§1);
## - the faults: over-range holds 20.5 mA and alarms, a blocked impulse line holds what was trapped, an open loop
##   takes the current to 0 and the display dark; each repaired from the same button;
## - a command the machine's state doesn't take is refused with a sentence; the transmitter runs taken apart;
## - every component is drawn with ws_lit (glass see-through with ws_xray, so the display reads through its window); X-ray swaps the outer parts to ws_xray and back; the cutaway and the
##   section set the planes and give the solid components' materials ws_cap as their next pass (the cut faces), not
##   the thin window's; the machine's first frame drew the cap pass, the flow and the labels (pipelines, §7.1), and
##   the plant's early warm-up holds ws_lit, ws_cap and ws_flow;
## - the builder refuses a bench binding to an anim or a flow path the generator doesn't make.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const WB = preload("res://builder/workshop_build.gd")
const Views = preload("res://workshop/views.gd")
const Explode = preload("res://workshop/explode.gd")
const BenchModel = preload("res://sim/bench_model.gd")
const BenchView = preload("res://workshop/bench_view.gd")

## A clock that gives one value (bench_view's free rotor).
class OneValue:
	var x := 0.0
	func loaded() -> bool:
		return true
	func val(_n: String) -> float:
		return x
	func now(_n: String) -> float:
		return x

class Comps:
	var comps := {}

var p: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		p.append(what)

func run(tree: SceneTree) -> Array:
	_join()
	_planes_math()
	_loader_refuses()
	_free_rotor()
	var main := App.start(tree)
	if main.ui == null or main.workshop == null:
		main.free()
		return p + ["the app did not start with its Workshop"]
	await tree.process_frame
	var ws = main.workshop
	for i in 900:
		if ws.warmed:
			break
		await tree.process_frame
	if ws._warm != null:
		var shaders := {}
		for c in ws._warm.get_children():
			if c is GeometryInstance3D and c.material_override is ShaderMaterial:
				shaders[(c.material_override as ShaderMaterial).shader.resource_path.get_file()] = true
		for want in ["ws_xray.gdshader", "ws_lit.gdshader", "ws_cap.gdshader", "ws_flow.gdshader"]:
			check(shaders.has(want), "the plant's early warm-up holds %s (%s)" % [want, str(shaders.keys())])
	else:
		check(false, "the plant's early warm-up ran")
	ws.open("pressure_transmitter")
	if not await _wait_shown(tree, ws):
		main.free()
		return p + ["the transmitter's Workshop did not show"]
	check(ws.bench.loaded(), "the transmitter's bench model loads: %s" % ws.bench.error)
	if not ws.bench.loaded():
		main.free()
		return p
	_materials(ws)
	_views(ws)
	await _running(ws)
	_panel(ws)
	ws.close()
	await ws.left
	main.free()
	return p

func _wait_shown(tree: SceneTree, ws) -> bool:
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		if ws.machine != null and ws.entry_ms > 0.0 and ws._loading == "":
			return true
		await tree.process_frame
	return false

## Every component drawn with ws_lit; the caps off once the first frame was drawn; flows at rest.
func _materials(ws) -> void:
	var bad := []
	var glass := 0
	for id in ws.comps:
		for c in ws.comps[id].get_children():
			if c is MeshInstance3D and c.has_meta("mat"):
				var m = c.material_override
				var want := "ws_xray.gdshader" if ws.comps[id].get_meta("glass", false) else "ws_lit.gdshader"
				glass += 1 if want == "ws_xray.gdshader" else 0
				if not (m is ShaderMaterial and m.shader.resource_path.ends_with(want)):
					bad.append(id)
	check(bad.is_empty(), "every component is drawn with ws_lit, its glass see-through: not %s" % str(bad))
	check(glass >= 1, "the display's window is see-through")
	for name in ws.views._capped:
		check(ws.views._capped[name].next_pass == null, "no cap pass after the first frame with nothing cut (%s)" % name)
	check(not ws.views.flow_ids().is_empty(), "the impulse line's flow path has its particles")

func _mesh_mats(ws, id: String) -> Array:
	var out := []
	for c in ws.comps[id].get_children():
		if c is MeshInstance3D and c.has_meta("mat"):
			out.append(c.material_override)
	return out

func _views(ws) -> void:
	var v = ws.views
	var outer: Array = ws.words.views.xray_all
	v.set_xray(true)
	for id in outer:
		for m in _mesh_mats(ws, id):
			check(m is ShaderMaterial and m.shader.resource_path.ends_with("ws_xray.gdshader"), "X-ray takes %s" % id)
	for m in _mesh_mats(ws, "electronics"):
		check(m.shader.resource_path.ends_with("ws_lit.gdshader"), "X-ray leaves the electronics as they are")
	v.set_xray(false)
	for id in outer:
		for m in _mesh_mats(ws, id):
			check(m.shader.resource_path.ends_with("ws_lit.gdshader"), "X-ray off gives %s back its material" % id)
	# the X-ray of a selected part only
	ws.select("housing")
	v.set_xray(true)
	check(v.is_xrayed("housing") and v.is_xrayed("cover_front") and not v.is_xrayed("manifold"),
		"with a part selected the X-ray takes it and its subassembly")
	v.set_xray(false)
	ws.select("")
	# the cutaway: planes set, caps on the solid components, never the thin window's
	v.set_cut(true)
	var any: ShaderMaterial = _mesh_mats(ws, "housing")[0]
	check(any.get_shader_parameter("ws_cut_on") == 1.0, "the cutaway turns the cut on")
	var p0: Vector4 = any.get_shader_parameter("ws_plane0")
	check(absf(Vector3(p0.x, p0.y, p0.z).length() - 1.0) < 1e-5 and p0.w < 1e8, "the cutaway's first plane is set")
	check(any.next_pass != null and (any.next_pass as ShaderMaterial).shader.resource_path.ends_with("ws_cap.gdshader"),
		"a solid component's cut faces are capped (ws_cap its next pass)")
	for m in _mesh_mats(ws, "window"):
		check(m.next_pass == null, "the thin window has no cap pass")
	v.set_cut(false)
	check(any.next_pass == null and any.get_shader_parameter("ws_cut_on") == 0.0, "the cutaway off: no cut, no cap")
	# the section: its plane moves with the slider, along the axis chosen
	v.set_section(true)
	v.set_section_axis(2)
	v.set_section_at(0.25)
	var a: Vector4 = any.get_shader_parameter("ws_plane2")
	v.set_section_at(0.75)
	var b: Vector4 = any.get_shader_parameter("ws_plane2")
	check(any.get_shader_parameter("ws_sec_on") == 1.0 and b.w > a.w and absf(a.y - 1.0) < 1e-6,
		"the section plane moves up the box as its slider moves (%s, %s)" % [a, b])
	check(any.next_pass != null, "the section caps its cut faces")
	v.set_section(false)
	v.set_section_axis(0)

## Runs the bench as the frame hook does (0.1 s of bench time a call) and checks every channel against the model.
func _go(ws, seconds: float) -> void:
	for i in roundi(seconds * 10.0):
		ws.apply()
		ws._run(0.1)

func _running(ws) -> void:
	var c = ws.bench
	c.speed = 1.0
	ws.run_command("terminal_block", "start")
	_go(ws, 0.3)
	check(c.machine_state("supply") == "on", "Start turns the loop supply on")
	ws.run_command("terminal_block", "start")
	_go(ws, 0.2)
	check(ws.run_note != "", "a second Start is refused with a sentence: %s" % ws.run_note)
	c.op_set("process_flange", 5.0)
	_go(ws, 8.0)
	check(absf(c.now("loop_ma") - 12.0) < 1e-4, "5 bar on a 0-10 bar range gives 12 mA: %f" % c.now("loop_ma"))
	_channels(ws, "at 5 bar")
	var disp = ws.bench_view.labels.filter(func(e): return e.at == "display")
	check(disp.size() == 1 and disp[0].label.text.contains("5.00 bar") and disp[0].label.text.contains("12.00 mA"),
		"the display shows the reading and the current: %s" % (disp[0].label.text if disp.size() == 1 else "none"))
	# the impulse line's particles run while the pressure changes, and the other way when it falls
	var fl: Dictionary = ws.views._flows.values()[0]
	c.op_set("process_flange", 9.0)
	_go(ws, 0.3)
	var ph1: float = fl.phase
	_go(ws, 0.2)
	check(fl.phase != ph1 and (fl.mat as ShaderMaterial).get_shader_parameter("density") > 0.0,
		"the impulse line's particles move while the pressure rises")
	_go(ws, 8.0)
	check((fl.mat as ShaderMaterial).get_shader_parameter("density") < 0.01, "and rest when it has settled")
	# over range: 20.5 mA (NAMUR NE 43), its alarm
	ws.toggle_fault("over_range")
	_go(ws, 6.0)
	check(c.now("loop_ma") == 20.5 and c.faulted.has("over_range"), "over-range holds 20.5 mA: %f" % c.now("loop_ma"))
	check(c.alarms().any(func(a): return a[0] == "sat_high"), "and alarms")
	_channels(ws, "over range")
	ws.ack_bench_alarms()
	ws.toggle_fault("over_range")
	_go(ws, 6.0)
	check(not c.faulted.has("over_range") and absf(c.now("loop_ma") - (4.0 + 16.0 * 0.9)) < 1e-3,
		"over-range repaired from the same button: %f" % c.now("loop_ma"))
	# a blocked impulse line holds what was trapped
	ws.toggle_fault("impulse_blocked")
	_go(ws, 0.2)
	c.op_set("process_flange", 2.0)
	_go(ws, 6.0)
	check(absf(c.now("pv") - 9.0) < 1e-3, "a blocked impulse line holds the trapped 9 bar: %f" % c.now("pv"))
	_channels(ws, "blocked")
	ws.toggle_fault("impulse_blocked")
	_go(ws, 6.0)
	check(absf(c.now("pv") - 2.0) < 1e-3, "and follows again when cleared: %f" % c.now("pv"))
	# an open loop: no current, the display dark
	ws.toggle_fault("loop_open")
	_go(ws, 0.3)
	check(c.now("loop_ma") == 0.0, "an open loop carries no current")
	check(disp.size() == 1 and disp[0].label.text.strip_edges() == "", "and the loop-powered display goes dark")
	_channels(ws, "open loop")
	ws.toggle_fault("loop_open")
	_go(ws, 0.5)
	# the display says over range (its alarm is where the display is), the face text and the glass cut away with it
	ws.toggle_fault("over_range")
	_go(ws, 6.0)
	check(disp.size() == 1 and disp[0].label.text.contains("Over range"), "the display says over range: %s" %
		(disp[0].label.text if disp.size() == 1 else "none"))
	ws.views.set_section_axis(0)          # across: the display's half of the box cut away
	ws.views.set_section_at(0.5)
	ws.views.set_section(true)
	_go(ws, 0.1)
	var win: Array = ws.views._meshes.get("window", [])
	check(disp.size() == 1 and not disp[0].label.visible, "the display's text goes with the half cut away")
	check(not win.is_empty() and not win[0].visible, "and so does the see-through window")
	ws.views.set_section(false)
	_go(ws, 0.1)
	check(disp.size() == 1 and disp[0].label.visible and win[0].visible, "and come back with it")
	ws.toggle_fault("over_range")
	_go(ws, 6.0)
	# taken apart, it still runs (its data allows it); the impulse path's particles rest while the line is apart
	ws.set_slider(1.0)
	c.op_set("process_flange", 7.0)
	_go(ws, 0.3)
	check((fl.mat as ShaderMaterial).get_shader_parameter("density") == 0.0 and absf(c.now("flow_frac")) > 0.05,
		"no particles float where the parts were while it is taken apart")
	check(ws.why_no_run() == "", "the transmitter runs taken apart: %s" % ws.why_no_run())
	_go(ws, 0.3)
	_channels(ws, "exploded")
	ws.set_slider(0.0)
	ws.run_command("terminal_block", "stop")
	_go(ws, 0.3)
	check(c.machine_state("supply") == "off", "Stop turns the supply off")
	check(c.step_us_max > 0 and c.steps > 100, "the bench steps and times its steps")

## Every channel against the model's value (WORKSHOP.md §1: a channel that moves on its own is a bug).
func _channels(ws, when: String) -> void:
	var c = ws.bench
	for a in ws.bench_view.anims:
		var n: Node3D = ws.comps[a.at]
		var base: Transform3D = ws.home[a.at]
		base.origin += Explode.offsets(ws.spec, ws.s, ws.root_id).get(a.at, Vector3.ZERO)
		var want: Vector3 = a.axis * a.travel * c.val(a.of) * a.scale
		check((n.transform.origin - base.origin).distance_to(want) < 1e-6,
			"%s: %s's %s follows %s (%s, want %s)" % [when, a.at, a.kind, a.of, n.transform.origin - base.origin, want])
	for e in ws.bench_view.labels:
		var lit: bool = e.lit == "" or c.now(e.lit) >= 0.5
		for s in e.shows:
			check(e.label.text.contains(c.shown(s)) == lit, "%s: %s shows %s (%s)" % [when, e.at, c.shown(s), e.label.text])
	for r in ws.bench_view.ramps:
		var want: Color = Views.legend_colour(c.m.legends[r.legend], c.val(r.of))
		for g in ws.views._meshes[r.at]:
			var got = g.get_instance_shader_parameter("ws_ramp")
			check(got is Color and Color(got.r, got.g, got.b).is_equal_approx(Color(want.r, want.g, want.b)),
				"%s: %s's colour follows %s" % [when, r.at, r.of])

func _panel(ws) -> void:
	var rp = ws.panels.run_panel
	ws.panels.show_run(true)
	check(rp.visible and not ws.panels.props_panel.visible, "Run shows the bench's panel in the properties' place")
	rp.tick()
	check(rp.find_child("run_supply_start", true, false) != null, "the panel has the supply's Start")
	check(rp.find_child("set_p_applied", true, false) != null, "and the applied pressure's slider")
	check(rp.fault_btns.size() == 3, "and the three faults")
	var lm: Label = rp.find_child("read_loop_ma", true, false)
	check(lm != null and lm.text.contains(ws.bench.shown("loop_ma")), "the readouts show the model's values")
	ws.panels.show_info(true)

## The builder's join refuses bench bindings the generator can't draw.
func _join() -> void:
	var data_dir := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/workshop").simplify_path()
	var f := FileAccess.open(data_dir.path_join("pressure_transmitter.json"), FileAccess.READ)
	var bf := FileAccess.open(data_dir.path_join("bench/pressure_transmitter.json"), FileAccess.READ)
	if f == null or bf == null:
		check(false, "the transmitter's data and bench files are readable from the project")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var bench: Dictionary = JSON.parse_string(bf.get_as_text())
	data["bench_text"] = JSON.stringify(bench)
	var r := WB.scene("pressure_transmitter", data, WB.params_for("pressure_transmitter", data, {}))
	check(r.errors.is_empty(), "the transmitter joins with its bench: %s" % str(r.errors))
	var b2 := bench.duplicate(true)
	b2.bind[0]["anim"] = "spin"
	for x in b2.bind:
		if x.has("flow"):
			x["flow"] = "nowhere"
	data["bench_text"] = JSON.stringify(b2)
	var errs: Array = WB.join(r.res, data)
	check(errs.any(func(e): return "anim spin" in e), "an anim the generator doesn't give is refused: %s" % str(errs))
	check(errs.any(func(e): return "nowhere" in e), "a flow path the generator doesn't make is refused")

## The app's loader refuses what it can't run (sim/bench_model.gd), and names it.
func _loader_refuses() -> void:
	var good := {"format": "walkdown-plant-bench", "version": 1, "part": "x", "sources": [],
		"values": [["u", {"state": 0}], ["y", {"lag": "u", "tau": 0.5}]], "start": {},
		"ops": [{"at": "body", "do": "set", "input": "u", "range": [0, 1]}]}
	var m = BenchModel.from_text(JSON.stringify(good), ["body"])
	check(m.error == "", "a small bench loads: %s" % m.error)
	var bad := good.duplicate(true)
	bad.ops[0].at = "lid"
	m = BenchModel.from_text(JSON.stringify(bad), ["body"])
	check(m.error.contains("lid"), "an op at no component is refused: %s" % m.error)
	bad = good.duplicate(true)
	bad.values[1][1].lag = "nothing"
	m = BenchModel.from_text(JSON.stringify(bad), ["body"])
	check(m.error.contains("nothing"), "a read of no value is refused: %s" % m.error)
	m = BenchModel.from_text('{"format": "walkdown-plant-bench", "format": 1}', ["body"])
	check(m.error.contains("strict JSON"), "a duplicate key is refused: %s" % m.error)
	bad = good.duplicate(true)
	bad.values[1][1] = {"cmp": ["world_hour", ">", 1]}
	m = BenchModel.from_text(JSON.stringify(bad), ["body"])
	check(m.error != "", "a clock value is refused on the bench")

## A rotor that turns freely (travel 0) turns at the value × scale revolutions a second, added up over bench time.
func _free_rotor() -> void:
	var bv := BenchView.new()
	var clock := OneValue.new()
	clock.x = 0.25
	var w := Comps.new()
	var n := Node3D.new()
	w.comps["rotor"] = n
	bv.ws = w
	bv.clock = clock
	bv.anims = [{"at": "rotor", "of": "speed", "scale": 1.0, "axis": Vector3.UP, "kind": "rotate", "travel": 0.0}]
	bv.draw(1.0)
	var b1 := n.basis
	n.transform = Transform3D.IDENTITY   # (the explode resets it every frame)
	bv.draw(1.0)
	check(b1.is_equal_approx(Basis(Vector3.UP, PI / 2.0)) and n.basis.is_equal_approx(Basis(Vector3.UP, PI)),
		"a free rotor turns a quarter turn a second at 0.25 rev/s, added up: %s, %s" % [b1, n.basis])
	n.free()

## A cutaway plane from the data: the part frame's normal to Godot's axes, the offset across the box.
func _planes_math() -> void:
	var box := AABB(Vector3(-1, 0, -2), Vector3(2, 4, 4))
	var a := Views.plane_of(Vector3(0, -1, 0), 0.0, box)    # part frame -y is Godot's +z
	check(a[0].is_equal_approx(Vector3(0, 0, 1)) and absf(a[1] - 0.0) < 1e-9, "a plane through the box's centre: %s" % str(a))
	var b := Views.plane_of(Vector3(1, 0, 0), 0.25, box)
	check(absf(b[1] - 0.5) < 1e-9, "an offset of a quarter of the box: %s" % str(b))
