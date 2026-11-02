## The Workshop's guided assembly and disassembly (docs/plant3d/WORKSHOP.md §3, §4.6, milestone K2), in the app:
## - snapping: within 2 % of the machine's box diagonal (at least 5 mm) and 10°, modulo a component's symmetry;
## - the pile: every part on the floor in front of the machine, none overlapping, the same layout every time;
## - the transmitter put back together from a pile in the guided order, each step's ghost in ws_xray where the part
##   goes; out of order a part is refused with its need's first sentence and stays loose; loose parts stay where they
##   lie in the machine's frame when their parent moves; a part placed on a loose parent rides with it; one step by a
##   drag of the handle; then taken apart in reverse, a part still needed refused with the second sentence;
## - Reassemble all and Reset end the steps with everything home;
## - the data-only fixture kind assembled from exploded (its lid's four-fold symmetry honoured);
## - ws_xray's pipelines queued early: a hidden mesh with it in the plant after the first walkable frame.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Assembly = preload("res://workshop/assembly.gd")
const Kit = preload("res://kit/kit.gd")
const WB = preload("res://builder/workshop_build.gd")

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
	check(ws.machine.find_child("ghost_warm", false, false) != null, "the Workshop's load queues the ghost's shader with the machine")
	await _transmitter(tree, ws)
	await _fixture(tree, ws)
	ws.close()
	await ws.left
	main.free()
	return p

## Snapping and the pile, as functions.
func _pure() -> void:
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
	check(ws.start_guide("assemble", "pile"), "the steps start from a pile")
	var n_loose: int = ws.guide.loose.size()
	check(n_loose == ws.comps.size() + ws.groups.size() - 3,
		"every part but the sealed parts' insides lies on the pile (%d)" % n_loose)
	check(not ws.panels.slider.editable, "the take-apart slider waits while the steps are on")
	await tree.process_frame
	check(ws.panels.step_label.text.begins_with("Step 1 of %d" % w.assembly.size()) and ws.panels.step_label.text.contains(w.components.sensor_module.name),
		"the first step names its part: %s" % ws.panels.step_label.text)
	check(ws.ghost != null and ws._ghost_id == "sensor_module" and ws.ghost.transform.is_equal_approx(ws.target_m("sensor_module")),
		"the first step's ghost stands where its part goes")
	if ws.ghost != null and ws.ghost.get_child_count() > 0:
		check((ws.ghost.get_child(0).material_override as ShaderMaterial).shader.resource_path.ends_with("ws_xray.gdshader"), "the ghost is drawn with ws_xray")
	# out of order: the flange bolts at their place before the flange: refused with the first sentence, still loose
	ws.guide.loose["flange_bolts"] = ws.target_m("flange_bolts")
	ws.select("flange_bolts")
	ws._released()
	check(ws.guide.loose.has("flange_bolts") and ws.note == "The flange bolts go in once the process flange sits on the sensor module." and ws.panels.note.text == ws.note,
		"out of order the bolts are refused with the need's sentence: '%s'" % ws.note)
	# loose parts stay where they lie when their parent moves; a part placed on a loose parent rides with it
	var cover0: Transform3D = ws._cur_m["cover_front"]
	ws.guide.loose["housing"] = (ws.guide.loose["housing"] as Transform3D).translated(Vector3(0, 0.05, 0))
	ws.apply()
	check((ws._cur_m["cover_front"] as Transform3D).is_equal_approx(cover0), "a loose part stays where it lies when its parent is moved")
	ws.guide.loose["terminal_block"] = ws.target_m("terminal_block")
	check(ws.try_place("terminal_block"), "a part goes into its loose parent")
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
	check(not ws.guide.on() and ws.handled.is_empty() and _near(_transforms(ws), at0), "Reassemble all brings every loose part home")
	check(ws.panels.slider.editable, "and the slider works again")
	ws.start_guide("assemble", "exploded")
	ws.reset()
	check(not ws.guide.on() and _transforms(ws) == at0, "Reset ends the steps, every part home")

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
	check(_transforms(ws)["base"] == at0["base"] and _transforms(ws)["core"] == at0["core"], "its parts where they were built")

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
