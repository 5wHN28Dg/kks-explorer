## The Workshop's guided assembly and disassembly (docs/plant3d/WORKSHOP.md §3, §4.6, milestone K2), in the app:
## - snapping: within 2 % of the machine's box diagonal (at least 5 mm) and 10°, modulo a component's symmetry;
## - the pile: every part on the floor in front of the machine, none overlapping, the same layout every time;
## - the transmitter put back together from a pile in the guided order, each step's ghost in ws_xray where the part
##   goes; out of order a part is refused with its need's first sentence and stays loose; loose parts stay where they
##   lie in the machine's frame when their parent moves; a part placed on a loose parent rides with it; one step by a
##   drag of the handle; then taken apart in reverse, a part still needed refused with the second sentence;
## - Reassemble all and Reset end the steps with everything home;
## - the data-only fixture kind assembled from exploded (its lid's four-fold symmetry honoured);
## - the steam turbine (K4a) taken apart in the overhaul's order (the upper lagging first; the rotor held until the upper
##   casings, the bearing covers, the thrust bearing and the coupling's bolts are out) and put back from a pile;
## - ws_xray's pipelines queued early: a hidden mesh with it in the plant after the first walkable frame.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Assembly = preload("res://workshop/assembly.gd")
const Kit = preload("res://kit/kit.gd")
const WB = preload("res://builder/workshop_build.gd")
const Explode = preload("res://workshop/explode.gd")

var p: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		p.append(what)

func run(tree: SceneTree) -> Array:
	_pure()
	var main := App.start(tree)
	if main.ui == null or main.workshop == null:
		main.free()
		return p + ["the app did not start with its Workshop"]
	await tree.process_frame
	var ws = main.workshop
	# ws_xray queued in the plant's world some seconds after the first walkable frame
	for i in 900:
		if ws.warmed:
			break
		await tree.process_frame
	check(ws.warmed and ws._warm != null and ws._warm.get_parent() == main.plant and not ws._warm.visible,
		"the ghost's shader is queued early, hidden in the plant (warmed %s)" % ws.warmed)
	if ws._warm != null:
		var wm: MeshInstance3D = ws._warm.get_child(0)
		check((wm.material_override as ShaderMaterial).shader.resource_path.ends_with("ws_xray.gdshader"), "with ws_xray")
	ws.open("pressure_transmitter")
	if not await _wait_shown(tree, ws):
		main.free()
		return p + ["the transmitter's Workshop did not show"]
	var gw: Node = ws.machine.find_child("ghost_warm", false, false)
	check(gw != null, "the Workshop's load queues the ghost's shader with the machine")
	if gw != null:
		# every part's own ghost, as its step builds it, at home (the Note 9 compiled a pipeline at the set screw's
		# first ghost with only one ghost per vertex format warmed)
		var missing: Array = []
		for id in ws.comps.keys() + ws.groups.keys():
			var want: Node3D = ws._ghost_node(id, ws.xray_mat())
			var got: Node3D = gw.get_node_or_null(NodePath(id))
			if want.get_child_count() == 0:
				check(got == null, "no warm ghost for %s, which draws nothing" % id)
			elif got == null or got.get_child_count() != want.get_child_count() or \
					not got.transform.is_equal_approx(ws.home_m(id)):
				missing.append(id)
			else:
				for k in want.get_child_count():
					var a: Node3D = want.get_child(k)
					var b: Node3D = got.get_child(k)
					var bm: ShaderMaterial = b.material_override as ShaderMaterial
					var same: bool = a.get_class() == b.get_class() and a.transform.is_equal_approx(b.transform) and \
						a.cast_shadow == b.cast_shadow and bm != null and bm != ws.xray_mat() and \
						bm.shader == ws.xray_mat().shader and is_equal_approx(float(bm.get_shader_parameter("alpha")), 0.0)
					if same and a is MeshInstance3D:
						same = a.mesh == b.mesh
					elif same:
						same = a.multimesh.mesh == b.multimesh.mesh and \
							a.multimesh.instance_count == b.multimesh.instance_count and \
							a.multimesh.transform_format == b.multimesh.transform_format
						for n in a.multimesh.instance_count if same else 0:
							same = same and a.multimesh.get_instance_transform(n).is_equal_approx(b.multimesh.get_instance_transform(n))
					if not same:
						missing.append(id)
						break
			want.free()
		check(missing.is_empty() and gw.get_child_count() > 0,
			"every part's ghost is warmed with the machine, where it will stand, in ws_xray at alpha 0 (its own material) (missing or unlike: %s)" % str(missing))
		check(not gw.visible, "drawn unseen in the machine's first frame, hidden after it")
	await _transmitter(tree, ws)
	await _fixture(tree, ws)
	await _turbine(tree, ws)
	ws.close()
	await ws.left
	main.free()
	return p

## Snapping and the pile, as functions.
func _pure() -> void:
	# a fastener group on or inside a sealed component rides with it (never loose: the steps can end)
	var comps := {"shell": {"parent": "", "sealed": true}, "inner": {"parent": "shell", "sealed": false},
		"lid": {"parent": "", "sealed": false}}
	var groups := {"pins": {"host": "shell"}, "deep": {"host": "inner"}, "bolts": {"host": "lid"}}
	check(Assembly.rides_of(comps, groups).keys().size() == 3 and not Assembly.rides_of(comps, groups).has("bolts"),
		"a sealed part's own and inner fasteners ride with it: %s" % str(Assembly.rides_of(comps, groups).keys()))
	groups["couple"] = {"host": "shell", "beyond": true}
	check(not Assembly.rides_of(comps, groups).has("couple"), "a sealed part's bolts to another machine don't ride with it")
	groups.erase("couple")
	var g := Assembly.new()
	g.start("assemble", [{"place": "shell"}, {"place": "inner"}, {"place": "pins"}, {"place": "lid"}, {"place": "bolts"}],
		comps, {"shell": Transform3D(), "inner": Transform3D(), "pins": Transform3D(), "lid": Transform3D(), "bolts": Transform3D()}, groups)
	check(not g.loose.has("pins") and g.real_steps() == 3 and g.step_number(3) == 2, "and their steps are not counted")
	# a parent can't come out while a placed part outside it needs a part that would come out with it
	var h := Assembly.new()
	var tree := {"p": {"parent": "", "sealed": false}, "c": {"parent": "p", "sealed": false}, "x": {"parent": "", "sealed": false}}
	h.start("disassemble", [{"place": "p"}, {"place": "c"}, {"place": "x", "needs": [["c", "x after c", "Take x off first."]]}], tree, {})
	check(h.why_not_remove("p", {"c": true}) == "Take x off first.", "a parent holding a needed part stays: '%s'" % h.why_not_remove("p", {"c": true}))
	# the Compatibility renderer's warm draw waits until it would be drawn
	var WS = load("res://workshop/workshop.gd")   # (untyped)
	check(not WS.can_draw_warm(null, false, false, 100, -100), "no camera, no warm draw")
	var c3 := Camera3D.new()
	check(not WS.can_draw_warm(c3, true, false, 100, -100) and not WS.can_draw_warm(c3, false, true, 100, -100) and
		WS.can_draw_warm(c3, false, false, 100, -100), "not with the 3D off or the Workshop open")
	# nor in the frames after a close, as the Mobile renderer's warm-up keeps out of them (the way back's frame)
	check(not WS.can_draw_warm(c3, false, false, 100, 100) and not WS.can_draw_warm(c3, false, false, 102, 100) and
		WS.can_draw_warm(c3, false, false, 103, 100), "not in the close's frame nor the two after it")
	check(not WS.may_warm(false, 101, 100) and WS.may_warm(false, 103, 100) and not WS.may_warm(true, 500, 100),
		"the same rule as the Mobile renderer's warm-up")
	c3.free()
	check(FileAccess.get_file_as_string("res://workshop/ws_xray.gdshader").contains("depth_test_disabled"), "the ghost shows through the parts in front of it")
	var box := AABB(Vector3.ZERO, Vector3(0.3, 0.4, 0.0))   # diagonal 0.5 m: 2 % is 10 mm
	check(is_equal_approx(Assembly.snap_tol(box), 0.01), "2 %% of the box diagonal (%.4f)" % Assembly.snap_tol(box))
	check(is_equal_approx(Assembly.snap_tol(AABB(Vector3.ZERO, Vector3.ONE * 0.01)), 0.005), "at least 5 mm")
	var home := Transform3D.IDENTITY
	var tol := 0.01
	check(Assembly.near_enough(Transform3D(Basis(), Vector3(0.0095, 0, 0)), home, Vector3.ZERO, [], tol), "9.5 mm off snaps")
	check(not Assembly.near_enough(Transform3D(Basis(), Vector3(0.0105, 0, 0)), home, Vector3.ZERO, [], tol), "10.5 mm off doesn't")
	check(Assembly.near_enough(Transform3D(Basis(Vector3.UP, deg_to_rad(9.5)), Vector3.ZERO), home, Vector3.ZERO, [], tol), "9.5° snaps")
	check(not Assembly.near_enough(Transform3D(Basis(Vector3.UP, deg_to_rad(10.5)), Vector3.ZERO), home, Vector3.ZERO, [], tol), "10.5° doesn't")
	var four := [Vector3(0, 0, 1), 4]
	check(Assembly.angle_off(Basis(Vector3(0, 0, 1), PI / 2.0), Basis(), four) < 1e-4, "a four-fold part turned 90° about its axis is in its place")
	check(absf(Assembly.angle_off(Basis(Vector3(0, 0, 1), PI / 4.0), Basis(), four) - PI / 4.0) < 1e-4, "turned 45° it is 45° off")
	check(absf(Assembly.angle_off(Basis(Vector3(1, 0, 0), PI / 2.0), Basis(), four) - PI / 2.0) < 1e-4, "turned about another axis it is off")
	var round := [Vector3(1, 0, 0), 0]
	check(Assembly.angle_off(Basis(Vector3(1, 0, 0), 2.1), Basis(), round) < 1e-4, "a round part turned any angle about its axis is in its place")
	check(absf(Assembly.angle_off(Basis(Vector3(0, 1, 0), 0.3), Basis(), round) - 0.3) < 1e-4, "tipped, it is off")
	# the centre is what must come near: a group turned about its centre is as near as its centre
	check(Assembly.near_enough(Transform3D(Basis(Vector3.UP, deg_to_rad(5)), Vector3(0.5, 0, 0) - Basis(Vector3.UP, deg_to_rad(5)) * Vector3(0.5, 0, 0)),
		home, Vector3(0.5, 0, 0), [], tol), "a group turned about its centre is judged at its centre")
	# the pile
	var machine := AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.3, 0.2))
	var parts := [{"id": "a", "box": AABB(Vector3(-0.05, 0.1, -0.05), Vector3(0.1, 0.1, 0.1))},
		{"id": "b", "box": AABB(Vector3(-0.1, 0.2, -0.02), Vector3(0.2, 0.04, 0.04))},
		{"id": "c", "box": AABB(Vector3(0, 0, 0), Vector3(0.01, 0.01, 0.01))},
		{"id": "d", "box": AABB(Vector3(0.02, 0.05, 0), Vector3(0.15, 0.15, 0.15))}]
	var off := Assembly.pile(parts, machine)
	check(off == Assembly.pile(parts, machine) and off.size() == 4, "the same parts, the same pile")
	var placed: Array = []
	for q in parts:
		var b: AABB = q.box
		b.position += off[q.id]
		check(is_equal_approx(b.position.y, machine.position.y), "%s lies on the floor (%.3f)" % [q.id, b.position.y])
		check(b.position.z > machine.end.z, "%s lies in front of the machine" % q.id)
		for o in placed:
			check(not b.intersects(o), "%s overlaps another part on the pile" % q.id)
		placed.append(b)

## The transmitter from a pile and back.
func _transmitter(tree: SceneTree, ws) -> void:
	var w: Dictionary = ws.words
	var at0 := _transforms(ws)
	ws.panels.only_cb.button_pressed = true   # (on, as a trainee may have left it)
	check(ws.start_guide("assemble", "pile"), "the steps start from a pile")
	var n_loose: int = ws.guide.loose.size()
	check(n_loose == ws.comps.size() + ws.groups.size() - 3,
		"every part but the sealed parts' insides lies on the pile (%d)" % n_loose)
	check(not ws.panels.slider.editable, "the take-apart slider waits while the steps are on")
	await tree.process_frame
	check(not ws.panels.only_cb.button_pressed, "the steps uncheck Selected subassembly only")
	check(ws.panels.step_label.text.begins_with("Step 1 of 13") and ws.panels.step_label.text.contains(w.components.sensor_module.name),
		"the first step names its part: %s" % ws.panels.step_label.text)
	check(ws.ghost != null and ws._ghost_id == "sensor_module" and ws.ghost.transform.is_equal_approx(ws.target_m("sensor_module")),
		"the first step's ghost stands where its part goes")
	# the pile has no gap where a sealed part's insides would have lain: neighbours in a row are one gap apart
	var row: Array = []
	for id in ws.guide.loose:
		var b: AABB = ws._home_box(id)
		b.position += (ws.guide.loose[id] as Transform3D).origin - ws.home_m(id).origin
		row.append(b)
	row.sort_custom(func(a, b): return a.position.z < b.position.z or (a.position.z == b.position.z and a.position.x < b.position.x))
	var gaps: Array = []
	var zs := {}
	for b in row:
		zs[snappedf(b.position.z, 1e-5)] = true
	for z in zs:
		var r := row.filter(func(b): return absf(b.position.z - z) < 1e-5)
		r.sort_custom(func(a, b): return a.position.x < b.position.x)
		for k in range(1, r.size()):
			gaps.append(snappedf(r[k].position.x - r[k - 1].end.x, 1e-5))
	check(gaps.size() >= 1 and gaps.all(func(g): return is_equal_approx(g, gaps[0])), "the pile's rows have even gaps: %s" % str(gaps))
	check(row.size() == ws.guide.loose.size(), "(every loose part in a row)")
	var unseen: Array = []
	for b in row:
		if not ws.cam.is_position_in_frustum(ws.machine.global_transform * (b as AABB).get_center()):
			unseen.append(b)
	check(unseen.is_empty(), "the pile is in view (%d parts out of it)" % unseen.size())
	if ws.ghost != null and ws.ghost.get_child_count() > 0:
		check((ws.ghost.get_child(0).material_override as ShaderMaterial).shader.resource_path.ends_with("ws_xray.gdshader"), "the ghost is drawn with ws_xray")
	# out of order: the flange bolts at their place before the flange: refused with the first sentence, still loose
	ws.guide.loose["flange_bolts"] = ws.target_m("flange_bolts")
	ws.select("flange_bolts")
	ws._released()
	check(ws.guide.loose.has("flange_bolts") and ws.note == "The flange bolts go in once the process flange sits on the sensor module." and ws.panels.note.text == ws.note,
		"out of order the bolts are refused with the need's sentence: '%s'" % ws.note)
	ws.guide.loose["flange_bolts"] = ws.target_m("flange_bolts").translated(Vector3(0, -0.2, 0))
	ws._released()
	check(ws.panels.note.text == "", "let go far off, the refusal goes: '%s'" % ws.panels.note.text)
	# loose parts stay where they lie when their parent moves; a part placed on a loose parent rides with it
	var cover0: Transform3D = ws._cur_m["cover_front"]
	ws.guide.loose["housing"] = (ws.guide.loose["housing"] as Transform3D).translated(Vector3(0, 0.05, 0))
	ws.apply()
	check((ws._cur_m["cover_front"] as Transform3D).is_equal_approx(cover0), "a loose part stays where it lies when its parent is moved")
	ws.guide.loose["terminal_block"] = ws.target_m("terminal_block")
	check(ws.try_place("terminal_block"), "a part goes into its loose parent")
	check(ws.panels.step_label.text.begins_with("Step 1 of 13"), "a part placed out of the guided order leaves the next step as it was")
	var tb0: Transform3D = ws._cur_m["terminal_block"]
	ws.guide.loose["housing"] = (ws.guide.loose["housing"] as Transform3D).translated(Vector3(0.02, 0, 0))
	ws.apply()
	check((ws._cur_m["terminal_block"] as Transform3D).origin.is_equal_approx(tb0.origin + Vector3(0.02, 0, 0)), "and rides with it")
	# the guided order, each part brought near its place (inside the snap, a little turned)
	var tol: float = Assembly.snap_tol(ws.machine.get_meta("box"))
	var guard := 0
	while ws.guide.next_step() >= 0 and guard < 40:
		guard += 1
		var id := String(ws.guide.steps[ws.guide.next_step()].place)
		var tg: Transform3D = ws.target_m(id)
		if id == "housing":
			# this one by the handle: 30 mm above, dragged down along the up arrow, let go
			ws.guide.loose[id] = tg.translated(Vector3(0, 0.03, 0))
			ws.apply()
			ws.select(id)
			ws._drag = {"kind": "move", "axis": Vector3.UP, "a": Vector2.ZERO, "b": Vector2(100, 0), "len": 0.03,
				"from": Vector2.ZERO, "start": ws.guide.loose[id]}
			ws._drag_handle(Vector2(-100, 0))
			ws._drag = {}
			ws._released()
			check(not ws.guide.loose.has(id), "the housing dragged by the handle onto its place snaps there")
			continue
		if id == "display":
			# the board, placed, taken out again by the handle and let go far off: the next step and its ghost are
			# the board's again
			ws.select("electronics")
			await tree.process_frame
			ws._place_handle()
			var hc: Vector3 = ws.handle.global_position
			var sc: float = ws.handle.scale.x
			var took := false
			for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				var mp: Vector2 = ws.cam.unproject_position(hc + ax * sc * 0.6)
				if ws._grab_handle(mp) and ws._drag.kind == "move":
					took = true
					ws._drag_handle(mp + ((ws._drag.b as Vector2) - (ws._drag.a as Vector2)) * 3.0)
					break
				ws._drag = {}
			check(took and ws.guide.loose.has("electronics"), "a placed part picked up by the handle lies loose")
			ws._drag = {}
			ws._released()
			check(ws.guide.loose.has("electronics") and ws._ghost_id == "electronics" and ws.panels.step_label.text.contains(w.components.electronics.name),
				"taken out while assembling, it is the next step again, its ghost with it (%s)" % ws._ghost_id)
			ws.guide.loose["electronics"] = ws.target_m("electronics")
			check(ws.try_place("electronics"), "and goes back")
			check(ws.panels.step_label.text.begins_with("Step 5 of 13"), "steps are counted as the trainee does them: %s" % ws.panels.step_label.text)
		var c: Vector3 = ws._gcentre.get(id, Vector3.ZERO) if ws.groups.has(id) else Vector3.ZERO
		var b := Basis(Vector3(0, 1, 0), deg_to_rad(6.0)) * tg.basis
		ws.guide.loose[id] = Transform3D(b, tg.origin + tg.basis * c - b * c + Vector3(tol * 0.6, 0, 0))
		if not ws.try_place(id):
			check(false, "step %s: refused or not snapped (%s)" % [id, ws.note])
			break
	check(ws.guide.done() and ws.guide.loose.is_empty(), "the transmitter is put back together in the guided order (%d loose)" % ws.guide.loose.size())
	check(_near(_transforms(ws), at0), "every part where it was built")
	check(ws.ghost == null and ws.panels.step_label.text.begins_with("Assembled"), "the end says so: %s" % ws.panels.step_label.text)
	# taken apart in reverse; a part still needed can't come out
	check(ws.start_guide("disassemble"), "the steps start taking apart")
	ws.select("housing")
	check(ws.note == "Loosen the housing rotation set screw one full turn before unscrewing the housing.", "the housing is held by its set screw: '%s'" % ws.note)
	ws._place_handle()
	check(not ws.handle.visible, "and can't be picked up")
	ws.select("cover_front")
	ws._place_handle()
	check(ws.note == "" and ws.handle.visible, "a cover can come off")
	guard = 0
	while ws.guide.next_step() >= 0 and guard < 40:
		guard += 1
		var id := String(ws.guide.steps[ws.guide.next_step()].place)
		check(ws.why_not_free(id) == "", "the next part to take out is free (%s: %s)" % [id, ws.why_not_free(id)])
		ws.guide.loose[id] = (ws._cur_m[id] as Transform3D).translated(Vector3(0, 0, 0.3))
		ws.select(id)
		ws._released()
		if not ws.guide.loose.has(id):
			check(false, "%s, taken far from its place, went back" % id)
			break
	check(ws.guide.done() and ws.panels.step_label.text.begins_with("Taken apart"), "taken apart in reverse: %s" % ws.panels.step_label.text)
	# Reassemble all brings everything home and ends the steps
	ws.reassemble()
	for i in 120:
		await tree.process_frame
		if ws._reassemble_t < 0.0:
			break
	check(not ws.guide.on() and ws.handled.is_empty() and _near(_transforms(ws), at0) and _groups_home(ws), "Reassemble all brings every loose part home")
	check(ws.panels.slider.editable, "and the slider works again")
	ws.start_guide("assemble", "exploded")
	check(not ws.guide.loose.has("sensor_module") and ws.guide.loose.has("housing"),
		"from exploded, the part the explode doesn't move is in place already, the rest loose")
	ws.guide.loose["housing"] = ws.target_m("housing")
	check(ws.try_place("housing"), "so the housing goes onto it: '%s'" % ws.note)
	ws.reset()
	check(not ws.guide.on() and _transforms(ws) == at0 and _groups_home(ws), "Reset ends the steps, every part home")

## The steam turbine: taken apart in the overhaul's order, then put back together from a pile in the guided order.
func _turbine(tree: SceneTree, ws) -> void:
	ws.close()
	await ws.left
	ws.open("steam_turbine")
	if not await _wait_shown(tree, ws):
		p.append("the steam turbine's Workshop did not show")
		return
	var at0 := _transforms(ws)
	check(ws.start_guide("disassemble"), "the turbine's steps start taking apart")
	check(String(ws.guide.steps[ws.guide.next_step()].place) == "lagging_upper", "the upper lagging comes off first")
	check(ws.why_not_free("rotor") != "", "the rotor is held while the turbine is closed")
	ws.select("casing_upper")
	check(ws.note != "", "the upper casing is held while the turbine is closed")
	var order: Array = []
	var guard := 0
	while ws.guide.next_step() >= 0 and guard < 120:
		guard += 1
		var id := String(ws.guide.steps[ws.guide.next_step()].place)
		check(ws.why_not_free(id) == "", "the next part to take out is free (%s: %s)" % [id, ws.why_not_free(id)])
		order.append(id)
		ws.guide.loose[id] = (ws._cur_m[id] as Transform3D).translated(Vector3(0, 6.0, 0))
		ws.select(id)
		ws._released()
		if not ws.guide.loose.has(id):
			check(false, "%s, taken far from its place, went back" % id)
			break
	check(ws.guide.done(), "the turbine is taken apart step by step: %s" % ws.panels.step_label.text)
	for before in ["casing_upper", "joint_bolts", "inner_upper", "inner_bolts", "carrier_upper", "cap_f", "cap_r",
			"thrust_upper", "thrust_lower", "coupling_bolts", "brg_f_upper", "brg_r_upper", "glands_upper"]:
		check(order.find(before) >= 0 and order.find(before) < order.find("rotor"), "%s comes out before the rotor: %s" % [before, str(order)])
	ws.reset()
	check(ws.start_guide("assemble", "pile"), "the turbine's steps start from a pile")
	ws.guide.loose["rotor"] = ws.target_m("rotor")
	ws.select("rotor")
	ws._released()
	check(ws.guide.loose.has("rotor") and ws.note.begins_with("The rotor rests on the journal bearings"),
		"the rotor before its bearings is refused: '%s'" % ws.note)
	var tol: float = Assembly.snap_tol(ws.machine.get_meta("box"))
	guard = 0
	while ws.guide.next_step() >= 0 and guard < 120:
		guard += 1
		var id := String(ws.guide.steps[ws.guide.next_step()].place)
		var tg: Transform3D = ws.target_m(id)
		var c: Vector3 = ws._gcentre.get(id, Vector3.ZERO) if ws.groups.has(id) else Vector3.ZERO
		var b := Basis(Vector3(0, 1, 0), deg_to_rad(6.0)) * tg.basis
		ws.guide.loose[id] = Transform3D(b, tg.origin + tg.basis * c - b * c + Vector3(tol * 0.6, 0, 0))
		if not ws.try_place(id):
			check(false, "turbine step %s: refused or not snapped (%s)" % [id, ws.note])
			break
	check(ws.guide.done() and ws.guide.loose.is_empty(), "the turbine is put back together in the guided order (%d loose)" % ws.guide.loose.size())
	check(_near(_transforms(ws), at0), "every part of the turbine where it was built")
	ws.reset()
	# the Workshop walk's guided phases walk every step of the turbine (K4a's fixed pace left 14 parts loose), at the
	# phone's worst pace of 30 frames a second: taken apart by the end of its phase, then every part put back
	var W = load("res://app/workshop_walk.gd")
	var walk = W.new()
	walk.main = ws.main
	walk.ws = ws
	walk.running = true
	walk.t = W.APART[0]
	var apart_done := false
	while walk.t < W.PILE[1] - 0.05:
		if walk.t + 1.0 / 30.0 >= W.APART[1] and not apart_done:
			apart_done = true
			check(ws.guide.mode == "disassemble" and ws.guide.done(),
				"the walk takes the turbine apart within its phase (%s, next step %d)" % [ws.guide.mode, ws.guide.next_step()])
		walk._process(1.0 / 30.0)
	check(ws.guide.mode == "assemble" and ws.guide.done() and ws.guide.loose.is_empty(),
		"the walk puts every part of the turbine back within its phase (%d loose)" % ws.guide.loose.size())
	walk.free()
	ws.reset()

## The fixture kind (no Workshop code for it): from exploded, its lid's symmetry, its screws after the lid.
func _fixture(tree: SceneTree, ws) -> void:
	Kit.register("test_gadget", load("res://tests/fixtures/workshop_gadget.gd"), 2000)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/workshop_gadget.json"))
	var r := WB.scene("test_gadget", data, {})
	Kit.unregister("test_gadget")
	if r.scene == null:
		check(false, "the fixture kind's scene: %s" % str(r.errors))
		return
	ws.machine.queue_free()
	ws._show_machine(r.scene)
	await tree.process_frame
	var at0 := _transforms(ws)
	check(ws.start_guide("assemble", "exploded"), "the fixture's steps start from exploded")
	check(ws.guide.loose.size() == 4 and not (ws.guide.loose["lid"] as Transform3D).is_equal_approx(ws.home_m("lid")), "every part lies where the explode put it")
	var tol: float = Assembly.snap_tol(ws.machine.get_meta("box"))
	ws.guide.loose["lid_screws"] = ws.target_m("lid_screws")
	check(not ws.try_place("lid_screws") and ws.note == "The screws go in once the lid is on.", "the screws before the lid: '%s'" % ws.note)
	ws.guide.loose["base"] = ws.target_m("base")
	check(ws.try_place("base"), "the base goes down")
	ws.guide.loose["core"] = ws.target_m("core").translated(Vector3(tol * 1.05, 0, 0))
	check(not ws.try_place("core"), "just outside 2 % of the diagonal it doesn't snap")
	ws.guide.loose["core"] = ws.target_m("core").translated(Vector3(tol * 0.95, 0, 0))
	check(ws.try_place("core"), "just inside it snaps")
	var axis: Vector3 = (ws.comps["lid"].get_meta("sym")[0] as Vector3)
	var tl: Transform3D = ws.target_m("lid")
	ws.guide.loose["lid"] = Transform3D(Basis(axis, deg_to_rad(45.0)) * tl.basis, tl.origin)
	check(not ws.try_place("lid"), "the lid turned 45° doesn't snap")
	ws.guide.loose["lid"] = Transform3D(Basis(axis, deg_to_rad(92.0)) * tl.basis, tl.origin)
	check(ws.try_place("lid"), "turned 92° (a quarter turn of its four-fold symmetry, 2° off) it does")
	ws.guide.loose["lid_screws"] = ws.target_m("lid_screws")
	check(ws.try_place("lid_screws"), "then the screws")
	check(ws.guide.done(), "the fixture is assembled")
	# screws backing out opposite ways (radial): taken apart, the group lies out as a whole, not in its place
	var its: Array = ws.spec.groups.lid_screws.items.duplicate()
	var b1: Basis = (its[1] as Transform3D).basis
	var v1: Vector3 = (b1 * (ws.spec.groups.lid_screws.axis as Vector3)).normalized()
	var perp := v1.cross(Vector3.UP if absf(v1.y) < 0.9 else Vector3.RIGHT).normalized()
	its[1] = Transform3D(Basis(perp, PI) * b1, (its[1] as Transform3D).origin)
	ws.spec.groups.lid_screws.items = its
	var fo1: Array = Explode.fastener_offsets(ws.spec, 1.0).get("lid_screws", [])
	check(fo1.size() == 2 and ((fo1[0] as Vector3) + (fo1[1] as Vector3)).length() < 1e-5, "(the screws now back out opposite ways: %s)" % str(fo1))
	ws.start_guide("assemble", "exploded")
	var in_lid: Transform3D = (ws.guide.loose["lid"] as Transform3D) * ws.home_m("lid").affine_inverse() * ws.home_m("lid_screws")
	var away: float = in_lid.origin.distance_to((ws.guide.loose["lid_screws"] as Transform3D).origin)
	check(away > tol, "screws backing out every way don't lie as if fitted in the loose lid (%.4f m)" % away)
	ws.reset()
	check(_transforms(ws)["base"] == at0["base"] and _transforms(ws)["core"] == at0["core"], "its parts where they were built")

func _groups_home(ws) -> bool:
	return ws.groups.values().all(func(g): return g.transform == Transform3D.IDENTITY)

func _transforms(ws) -> Dictionary:
	var out := {}
	for id in ws.comps:
		out[id] = ws.comps[id].transform
	return out

func _near(a: Dictionary, b: Dictionary) -> bool:
	for id in a:
		if not (a[id] as Transform3D).is_equal_approx(b[id]):
			return false
	return true

func _wait_shown(tree: SceneTree, ws) -> bool:
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		if ws.machine != null and ws.entry_ms > 0.0 and ws._loading == "":
			return true
		await tree.process_frame
	return false
