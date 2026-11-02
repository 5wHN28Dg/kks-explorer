## The Workshop mode (docs/plant3d/WORKSHOP.md §2–§4.5, milestone K1), in the app as the trainee gets it:
## - the card of a transmitter offers Workshop; it opens the kind alone in its own world: the main viewport's 3D off,
##   the plant paused (its speed before kept), its sounds muted, the walker's input off, the plant's panels hidden;
## - the tree lists every component and fastener group, and selecting in it selects in 3D (and the properties show the
##   part's words, what holds it, a sealed part's reason); a pick in the view finds a part;
## - the explode function: the same value gives the same transforms, back to 0 restores every transform exactly, the
##   top level moves first; the selected subassembly alone leaves the rest at home; a sealed part's children never
##   move, and picking one up says why;
## - handling, hide, isolate, show all, Reset (every part back where it was built, everything shown);
## - Back to the plant: same place, view, panels and speed; the 3D on again, the sounds back;
## - in a session the plant runs on and `pos` carries the "in the Workshop" flag (MULTIPLAYER.md §6.3), which the
##   others read; the settings list the Workshop's kinds;
## - the explode function on the data-only fixture kind (no Workshop code for it).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Explode = preload("res://workshop/explode.gd")
const Session = preload("res://net/session.gd")
const Kit = preload("res://kit/kit.gd")
const WB = preload("res://builder/workshop_build.gd")
const Workshop = preload("res://workshop/workshop.gd")
const Orbit = preload("res://workshop/orbit.gd")
const AlarmPanel = preload("res://ui/alarm_panel.gd")

## Stands in for a hoist's pendant: records the plant's speed when its held motions are let go.
class FakePendant:
	var clock
	var speeds: Array = []
	func release_all() -> void:
		speeds.append(clock.speed)

var p: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		p.append(what)

func run(tree: SceneTree) -> Array:
	_fixture_explode()
	_pos_flag()
	_sealed_edges()
	_orbit_limits(tree)
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or main.workshop == null:
		main.free()
		return p + ["the app did not start with its Workshop"]
	await tree.process_frame
	var ws = main.workshop
	check(ws.kinds().has("pressure_transmitter"), "the Workshop has the pressure transmitter: %s" % str(ws.kinds()))
	# the settings list the kinds
	main.hud.show_settings(true)
	var sbtn: Button = App.find_button(main.hud.extra, "Pressure transmitter")
	check(sbtn != null, "the settings list the Workshop's kinds")
	if sbtn != null:
		sbtn.pressed.emit()
		check(ws.is_open and not main.hud.panel.visible, "the settings' button opens the Workshop, the settings closed behind it")
		ws.close()
		await ws.left
		check(main.hud.panel.visible, "leaving a Workshop opened from the settings shows the settings again")
	main.hud.show_settings(false)
	# not while a flight to equipment ("Go there") is under way: it would land while the trainee is away
	main.player.scripted = true
	check(not ws.open("pressure_transmitter") and not ws.is_open, "the Workshop doesn't open during a scripted flight")
	main.player.scripted = false
	# leaving while it loads: the worker's load is still collected (no request left holding the scene)
	var wpath := "res://built/workshop/pressure_transmitter.scn"
	ws.open("pressure_transmitter")
	ws.close()
	for i in 600:
		await tree.process_frame
		if ResourceLoader.load_threaded_get_status(wpath) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			break
	check(ResourceLoader.load_threaded_get_status(wpath) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"a close during loading leaves no threaded load behind (status %d)" % ResourceLoader.load_threaded_get_status(wpath))
	# out and in again within a frame: the first exit's and entry's coroutines say nothing for the new entry
	var stray := []
	var on_left := func():
		if ws.is_open:
			stray.append("left while open")
	var on_shown := func(_k):
		if ws.machine == null:
			stray.append("shown without a machine")
	ws.left.connect(on_left)
	ws.shown.connect(on_shown)
	ws.open("pressure_transmitter")
	await tree.process_frame
	ws.close()
	ws.open("pressure_transmitter")
	await _wait_shown(tree, ws)
	for i in 3:
		await tree.process_frame
	check(stray.is_empty(), "a quick close and open: no stray signal (%s)" % str(stray))
	ws.close()
	await ws.left
	ws.left.disconnect(on_left)
	ws.shown.disconnect(on_shown)
	# a transmitter's card offers the Workshop
	var code := ""
	for c in ui.index.nodes:
		if String(ui.index.nodes[c].get_meta("part", "")) == "pressure_transmitter":
			code = c
			break
	check(code != "", "the plant has a pressure transmitter")
	ui.go_control_room(false)
	await tree.process_frame
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	ui.toggle_alarms()
	ui.open_card(code)
	var wbtn: Button = ui.card.find_child("workshop", true, false)
	check(wbtn != null, "the card of %s offers the Workshop" % code)
	for i in 30:   # the walker settles on the floor first
		await tree.physics_frame
	var at: Vector3 = main.player.global_position
	var look: Vector3 = main.player.rotation
	var panels_before := [ui.alarms.visible, ui.card.visible]
	var walking_before: bool = main.player.input_enabled
	if wbtn == null:
		main.free()
		return p
	# touch controls on: the sticks hide (and let go) while the Workshop shows
	var touch0 = main.cf.get_value("controls", "touch", "auto")
	main.cf.set_value("controls", "touch", "on")
	main.hud.refresh()
	check(main.hud.sticks.all(func(st): return st.visible), "touch controls on: the sticks show in the plant")
	var d3_before: bool = main.get_viewport().disable_3d   # (the control room's screens may keep it off)
	var pend := FakePendant.new()
	pend.clock = ui.clock
	ui.card._pendant = pend
	wbtn.pressed.emit()
	ui.card._pendant = null
	check(pend.speeds == [SimClock.Speed.NORMAL], "a held hoist motion is let go before the plant pauses (%s)" % str(pend.speeds))
	check(main.hud.sticks.all(func(st): return not st.visible), "the touch sticks hide (and let go) in the Workshop")
	check(ws.is_open and ws.from_code == code, "the Workshop opened from the card")
	check(main.get_viewport().disable_3d, "the plant's 3D is not drawn behind the Workshop")
	check(ui.clock.speed == SimClock.Speed.PAUSED, "single play: the plant pauses in the Workshop")
	check(ui.sounds.muted, "the plant's sounds are muted in the Workshop")
	check(not main.player.input_enabled, "the walker doesn't walk while the Workshop shows")
	check(not ui.root.visible and not main.hud.visible, "the plant's panels and buttons hide behind the Workshop")
	check(ui._walker_state()[4] == Session.POS_IN_WORKSHOP, "the walker's pos carries the Workshop flag")
	var shown := await _wait_shown(tree, ws)
	check(shown, "the machine's first frame came")
	if not shown:
		ws.close()
		main.free()
		return p
	check(ws.entry_ms > 0.0, "the entry is measured (%.0f ms)" % ws.entry_ms)
	var w: Dictionary = ws.words
	# the tree: every component and fastener group, selection both ways
	var n_items := 0
	var it: TreeItem = ws.panels.tree.get_root()
	while it != null:
		n_items += 1
		it = it.get_next_in_tree()
	check(n_items == 1 + w.components.size() + w.fasteners.size(), "the tree lists the machine, %d components and %d groups (%d items)" % [w.components.size(), w.fasteners.size(), n_items])
	ws.panels._items["housing"].select(0)
	check(ws.selected == "housing", "selecting in the tree selects in 3D")
	check(ws.panels.props.get_parsed_text().contains(w.components.housing.name), "the properties show the part's name")
	ws.select("process_flange")
	check(ws.panels.tree.get_selected() == ws.panels._items["process_flange"], "selecting in 3D selects in the tree")
	check(ws.panels.props.get_parsed_text().contains(w.fasteners.flange_bolts.name), "the properties say what holds the part")
	ws.select("sensor_module")
	check(ws.panels.props.get_parsed_text().contains("Sealed"), "a sealed part says so")
	# a pick in the middle of the view finds a part
	await tree.process_frame
	var mid: Vector2 = ws.cam.unproject_position(ws.world_box("housing").get_center())
	for id in ws.comps:
		if id != "housing":
			ws.hidden[id] = true
	for g in ws.groups:
		ws.hidden[g] = true
	ws.apply()
	check(ws.pick(mid) == "housing", "a pick on the housing finds the housing (%s)" % ws.pick(mid))
	check(ws.pick(Vector2(2, 2)) == "", "a pick off the machine finds nothing")
	ws.show_all()
	# a touch pinch, then the emulated mouse's click of its first finger: nothing is selected
	ws.select("")
	await tree.process_frame   # (the handle hides with the selection: the touch below takes no handle)
	check(not ws.handle.visible, "nothing selected, no handle")
	var tp := InputEventScreenTouch.new()
	tp.index = 0; tp.position = mid; tp.pressed = true
	ws._on_view_input(tp)
	var tp1 := InputEventScreenTouch.new()
	tp1.index = 1; tp1.position = mid + Vector2(120, 0); tp1.pressed = true
	ws._on_view_input(tp1)
	var dr := InputEventScreenDrag.new()
	dr.index = 1; dr.position = mid + Vector2(160, 0); dr.relative = Vector2(40, 0)
	ws._on_view_input(dr)
	tp1.pressed = false
	ws._on_view_input(tp1)
	tp.pressed = false
	ws._on_view_input(tp)
	ws.cam.reset_view()   # (the pinch moved the camera: the point is on the machine again)
	check(ws.pick(mid) != "", "the pinch's point is on the machine")
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT; mb.position = mid; mb.pressed = pressed
		mb.device = InputEvent.DEVICE_ID_EMULATION
		ws._on_view_input(mb)
	check(ws.selected == "", "a pinch's end selects nothing (%s)" % ws.selected)
	ws.cam.reset_view()
	# the explode function
	var at0 := _transforms(ws)
	ws.set_slider(0.37)
	var a := _transforms(ws)
	ws.set_slider(0.9)
	ws.set_slider(0.37)
	check(_transforms(ws) == a, "the same slider value gives the same transforms")
	ws.set_slider(1.0)
	var moved := 0
	var t1 := _transforms(ws)
	for id in t1:
		if t1[id] != at0[id]:
			moved += 1
	check(moved >= 6, "taken apart, the parts moved (%d)" % moved)
	var fo: Dictionary = Explode.fastener_offsets(ws.spec, 1.0)
	check(fo.has("flange_bolts") and (fo.flange_bolts[0] as Vector3).y < -0.001 and absf((fo.flange_bolts[0] as Vector3).x) < 1e-4,
		"the flange bolts back out downwards, along their own axis: %s" % str(fo.get("flange_bolts")))
	check(t1["isolator"] == at0["isolator"] and t1["sensor_cell"] == at0["sensor_cell"], "a sealed part's children never come apart")
	ws.set_slider(0.0)
	check(_transforms(ws) == at0, "back to 0, every transform is exactly as built")
	# bolts back out first, then the part: at the end of the first stage's first half the flange bolts are out, the
	# flange home
	var D: int = Explode.levels(ws.spec)[2]
	ws.set_slider(0.5 / D)
	var bolts_out := _transforms(ws)
	var fo_q: Dictionary = Explode.fastener_offsets(ws.spec, 0.5 / D)
	check(bolts_out["process_flange"] == at0["process_flange"] and (fo_q.flange_bolts[0] as Vector3).is_equal_approx(fo.flange_bolts[0]),
		"the flange bolts are fully out before the process flange moves")
	ws.set_slider(0.75 / D)
	var early := _transforms(ws)
	check(early["housing"] != at0["housing"] and early["cover_front"].origin == at0["cover_front"].origin, "the top level comes out first, its parts after")
	# the selected subassembly alone
	ws.set_slider(0.0)
	ws.select("housing")
	ws.set_only_selected(true)
	ws.set_slider(1.0)
	var sub := _transforms(ws)
	check(sub["housing"] == at0["housing"] and sub["manifold"] == at0["manifold"] and sub["cover_front"] != at0["cover_front"],
		"the selected subassembly comes apart, the rest stays home")
	ws.set_only_selected(false)
	ws.set_slider(0.0)
	# a sealed part's child is not free
	check(ws.why_not_free("isolator") == w.components.sensor_module.sealed_why, "picking up a sealed part's child says why not")
	check(ws.why_not_free("cover_front") == "", "a cover is free to move")
	# handling, hide, isolate, show all, Reset
	ws.select("cover_front")
	await tree.process_frame
	check(ws.handle != null and ws.handle.visible, "the handle shows on a free part")
	# the handle stands at a part's pivot, which it turns about, not at its box's centre (the transmitter's pivots
	# are at their boxes' centres: the cover's meshes are moved off its pivot for the check, then back)
	var cf: Node3D = ws.comps["cover_front"]
	for c in cf.get_children():
		if c is MeshInstance3D:
			c.position += Vector3(0.03, 0, 0)
	await tree.process_frame
	if ws.handle != null:
		check(ws.handle.global_position.is_equal_approx(cf.global_position) and cf.global_position.distance_to(ws.world_box("cover_front").get_center()) > 0.02,
			"the handle stands at the part's pivot, which it turns about")
	for c in cf.get_children():
		if c is MeshInstance3D:
			c.position -= Vector3(0.03, 0, 0)
	# a fastener group turns about its own centre, not its host's origin
	var fb: Node3D = ws.groups["flange_bolts"]
	var fsum := Vector3.ZERO
	for t in fb.get_meta("items"):
		fsum += (t as Transform3D).origin
	var fc: Vector3 = fsum / (fb.get_meta("items") as Array).size()
	var fw0: Vector3 = fb.global_transform * fc
	ws.handled["flange_bolts"] = Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3.ZERO)
	ws.apply()
	check((fb.global_transform * fc).distance_to(fw0) < 1e-5, "a turned fastener group keeps its centre (moved %.4f m)" % (fb.global_transform * fc).distance_to(fw0))
	ws.handled.erase("flange_bolts")
	ws.apply()
	ws.handled["cover_front"] = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.05, 0.02, 0))
	ws.apply()
	check(_transforms(ws)["cover_front"] != at0["cover_front"], "a handled part moves")
	ws.hide_selected()
	check(not ws.comps["cover_front"].visible, "Hide hides the part")
	ws.select("terminal_block")
	ws.isolate()
	check(ws.comps["terminal_block"].visible and not ws.comps["manifold"].visible, "Isolate keeps the part and hides the rest")
	check(not _meshes_shown(ws, "housing"), "Isolate hides the ancestors' own meshes")
	ws.reset()
	check(_transforms(ws) == at0 and ws.hidden.is_empty() and _all_meshes_shown(ws), "Reset: every part where it was built, everything shown")
	ws.select("terminal_block")
	ws.isolate()
	ws.select("process_flange")
	ws.isolate()
	ws.hidden.erase("housing")
	ws.apply()
	check(_meshes_shown(ws, "housing"), "after a second Isolate elsewhere, the housing's own meshes are not left hidden")
	ws.select("cover_front")
	ws.hide_selected()
	ws.show_all()
	check(ws.hidden.is_empty() and _all_meshes_shown(ws), "Show all shows them again")
	ws.reset()
	await _review_checks(tree, ws, w, at0)
	ws.reset()
	# Reassemble all animates home
	ws.set_slider(1.0)
	ws.reassemble()
	for i in 120:
		await tree.process_frame
		if ws.s == 0.0:
			break
	check(ws.s == 0.0 and _transforms(ws) == at0, "Reassemble all brings everything home")
	# Reassemble all from a handled part: half way it is on its way, at the end home
	ws.handled["cover_front"] = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.05, 0.02, 0))
	ws.set_slider(1.0)
	ws.reassemble()
	var mid_seen := false
	for i in 120:
		await tree.process_frame
		if ws._reassemble_t > 0.0 and ws._reassemble_t < Workshop.REASSEMBLE_S * 0.8 and ws.handled.has("cover_front"):
			var hm: Transform3D = ws.handled["cover_front"]
			mid_seen = mid_seen or (hm != Transform3D.IDENTITY and hm.origin.length() < Vector3(0.05, 0.02, 0).length() - 1e-4)
		if ws.s == 0.0 and ws._reassemble_t < 0.0:
			break
	check(mid_seen, "Reassemble all brings a handled part home step by step")
	check(ws.s == 0.0 and ws.handled.is_empty() and _transforms(ws) == at0, "and ends with it exactly home")
	check(Explode.fastener_offsets(ws.spec, 0.0).values().all(func(a): return a.all(func(v): return v == Vector3.ZERO))
		and ws.groups.values().all(func(g): return g.transform == Transform3D.IDENTITY), "at 0 every fastener item is home too")
	# back to the plant
	ws.close()
	await ws.left
	check(not ws.is_open and main.get_viewport().disable_3d == d3_before, "back in the plant, its 3D drawn as before (%s)" % d3_before)
	check(ui.clock.speed == SimClock.Speed.NORMAL, "the plant's speed before the Workshop is back")
	check(not ui.sounds.muted, "the plant's sounds are back")
	check(main.player.global_position.distance_to(at) < 0.01 and main.player.rotation.distance_to(look) < 1e-4, "the trainee stands where they were (%s, was %s)" % [str(main.player.global_position), str(at)])
	check(ui.root.visible and main.hud.visible and [ui.alarms.visible, ui.card.visible] == panels_before, "the plant's panels are as they were")
	check(ws.exit_ms >= 0.0, "the exit is measured (%.0f ms)" % ws.exit_ms)
	await tree.process_frame
	check(main.player.input_enabled == walking_before, "the walker walks again as before (%s, was %s)" % [main.player.input_enabled, walking_before])
	check(main.hud.sticks.all(func(st): return st.visible), "the touch sticks are back")
	main.cf.set_value("controls", "touch", touch0)
	main.hud.refresh()
	# the gamepad: a press puts the focus on the Workshop's tools, A presses the focused one, B leaves
	ws.open("pressure_transmitter")
	await _wait_shown(tree, ws)
	ws.set_slider(1.0)
	main.get_viewport().push_input(_pad(JOY_BUTTON_DPAD_DOWN, true))
	main.get_viewport().push_input(_pad(JOY_BUTTON_DPAD_DOWN, false))
	var gfo: Control = main.get_viewport().gui_get_focus_owner()
	check(gfo != null and ws.panels.is_ancestor_of(gfo), "a gamepad press puts the focus on the Workshop's tools (%s)" % str(gfo))
	var rbtn: Button = ws.panels.find_child("reset", true, false)
	rbtn.grab_focus()
	main.get_viewport().push_input(_pad(JOY_BUTTON_A, true))
	main.get_viewport().push_input(_pad(JOY_BUTTON_A, false))
	await tree.process_frame
	check(ws.s == 0.0, "gamepad A presses the focused tool (Reset; the slider at %.2f)" % ws.s)
	main.get_viewport().push_input(_pad(JOY_BUTTON_B, true))
	check(not ws.is_open, "gamepad B leaves the Workshop")
	main.get_viewport().push_input(_pad(JOY_BUTTON_B, false))
	if ws.is_open:
		ws.close()
	await ws.left
	# the horn: paused with an alarm unacknowledged, it sounds again on leaving
	var ek := _free_alarm(ui.clock.engine)
	var horns: Array = []
	var on_horn := func(pr): horns.append(pr)
	ui.horn_changed.connect(on_horn)
	if ek >= 0:
		ui.clock.set_speed(SimClock.Speed.PAUSED)
		ui.clock.engine.astate[ek] = "active_unack"
		ui._alarms_step = -1
		await tree.process_frame
		await tree.process_frame
		var horn_on: int = ui._horn
		check(horn_on > 0, "an unacknowledged alarm sounds the horn (%d)" % horn_on)
		ws.open("pressure_transmitter")
		await _wait_shown(tree, ws)
		check(horns.size() > 0 and horns[-1] == 0, "the horn is silent in the Workshop")
		ws.close()
		await ws.left
		await tree.process_frame
		await tree.process_frame
		check(horns[-1] == horn_on, "back in the paused plant, the horn sounds again (%s)" % str(horns))
		ui.clock.engine.astate[ek] = "normal"
		ui._alarms_step = -1
		ui.clock.set_speed(SimClock.Speed.NORMAL)
	else:
		check(false, "an alarm to raise for the horn's check")
	ui.horn_changed.disconnect(on_horn)
	# the tier as it is now on every entry (the phone cuts soft shadows first)
	var tier0 = main.tier
	main.tier = "full" if tier0 == "lean+vis" else "lean+vis"
	ws.open("pressure_transmitter")
	check(ws.sun.shadow_enabled == (main.tier != "lean+vis"), "a tier changed between two entries reaches the Workshop")
	ws.close()
	await ws.left
	main.tier = tier0
	# a session: the plant runs on
	ui.close_card()
	ws.force_session = true
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	ws.open("pressure_transmitter")
	check(ui.clock.speed == SimClock.Speed.NORMAL, "in a session the plant does not pause")
	await _wait_shown(tree, ws)
	await tree.process_frame
	check(ws.panels.strip.visible and ws.panels.strip.text.contains("runs on"), "in a session the strip says the plant runs on")
	var sk := _free_alarm(ui.clock.engine)
	if sk >= 0:
		ui.clock.engine.astate[sk] = "active_unack"
		await tree.process_frame
		check(ws.panels.strip.text.contains("1 new alarm"), "the strip counts a new alarm: %s" % ws.panels.strip.text)
		ui.clock.engine.astate[sk] = "normal"
	# an alarm unacknowledged at entry is acknowledged by another player and a new one comes: it still counts
	var old_k := _free_alarm(ui.clock.engine)
	if old_k >= 0:
		ui.clock.engine.astate[old_k] = "active_unack"
		ws._alarms_at = ws.call("_unacked_keys") if ws.has_method("_unacked_keys") else ws.call("_unacked")   # (as at entry)
		var new_k := _free_alarm(ui.clock.engine)
		ui.clock.engine.astate[old_k] = "normal"
		ui.clock.engine.astate[new_k] = "active_unack"
		check(ws.new_alarms() == 1, "an old alarm acknowledged and a new one raised: one new alarm (%d)" % ws.new_alarms())
		ui.clock.engine.astate[new_k] = "normal"
	ws.force_session = false   # the session ends while the Workshop shows
	await tree.process_frame
	check(ws.panels.strip.text.contains("ended"), "the strip says the session ended: %s" % ws.panels.strip.text)
	ws.close()
	await ws.left
	ws.force_session = false
	check(ui.clock.speed == SimClock.Speed.NORMAL, "leaving a session's Workshop leaves the plant's speed alone")
	await _review_plant_checks(tree, main, ws, ui)
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	main.free()
	return p

## An alarm in its normal state that the horn would count once raised (not shelved, not suppressed); -1 when none.
func _free_alarm(e) -> int:
	for k in e._al.size():
		if e.astate[k] == "normal" and e.shelved[k] == -1 and not AlarmPanel.suppressed(e, k):
			return k
	return -1

func _pad(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	return e

## Whether a component's own meshes are shown (Isolate hides an ancestor's).
func _meshes_shown(ws, id: String) -> bool:
	for c in ws.comps[id].get_children():
		if c is MeshInstance3D and not c.visible:
			return false
	return true

func _all_meshes_shown(ws) -> bool:
	for id in ws.comps:
		if not _meshes_shown(ws, id):
			return false
	return true

func _wait_shown(tree: SceneTree, ws) -> bool:
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		if ws.machine != null and ws.entry_ms > 0.0 and ws._loading == "":
			return true
		await tree.process_frame
	return false

func _transforms(ws) -> Dictionary:
	var out := {}
	for id in ws.comps:
		out[id] = ws.comps[id].transform
	return out

## `pos` carries the flag; the receiver reads it.
func _pos_flag() -> void:
	var f := Session.pos_fields(7, Vector3(1, 2, 3), 0.5, 0.1, 12, Session.POS_IN_WORKSHOP)
	check(f.size() == 24 and f[21] == 1, "pos keeps its 24 bytes with the Workshop flag in byte 21")
	check(Session.pos_fields(7, Vector3.ZERO, 0, 0, 0)[21] == 0, "pos without the flag sends 0 there")
	var s = Session.new()
	s.slot = 0
	s._on_pos(3, f)
	check(s.in_workshop(3), "the flag is read from another player's pos")
	s._on_pos(3, Session.pos_fields(8, Vector3(1, 2, 3), 0.5, 0.1, 12))
	check(not s.in_workshop(3), "and cleared by the next pos without it")
	s.free()

## The explode function on the data-only fixture kind: the same s the same offsets, 0 none, stages in order.
func _fixture_explode() -> void:
	Kit.register("test_gadget", load("res://tests/fixtures/workshop_gadget.gd"), 2000)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/workshop_gadget.json"))
	var r := WB.scene("test_gadget", data, {})
	Kit.unregister("test_gadget")
	if r.scene == null:
		p.append("the fixture kind's scene: %s" % str(r.errors))
		return
	var root: Node3D = r.scene.instantiate()
	var spec := Explode.spec_of(root)
	check(spec.order.size() == 3 and spec.groups.has("lid_screws"), "the fixture's tree is read (%s)" % str(spec.order))
	check(Explode.offsets(spec, 0.0).values().all(func(v): return v == Vector3.ZERO), "at 0 nothing moves")
	check(Explode.offsets(spec, 0.42) == Explode.offsets(spec, 0.42), "the same s, the same offsets")
	var half := Explode.offsets(spec, 0.5)
	var full := Explode.offsets(spec, 1.0)
	# levels: base, lid, lid_screws (0); core (1): D = 2, so at 0.5 the top level is out and the next not begun
	check((half["lid"] as Vector3).is_equal_approx(full["lid"]) and (half["core"] as Vector3) == Vector3.ZERO, "the top level is out by half way, the next level not begun")
	check((full["core"] as Vector3).length() > 0.0, "fully exploded, the core leaves the base")
	var fo := Explode.fastener_offsets(spec, 1.0)
	check(fo.has("lid_screws") and fo.lid_screws.size() == 2 and (fo.lid_screws[0] as Vector3).length() > 0.0, "the screws back out")
	# bolts back out first, then the part (the user, 2026-11-02): the screws are fully out at a quarter, the lid not moved
	var q_off := Explode.offsets(spec, 0.25)
	var q_fo := Explode.fastener_offsets(spec, 0.25)
	check((q_off["lid"] as Vector3) == Vector3.ZERO and (q_fo.lid_screws[0] as Vector3).is_equal_approx(fo.lid_screws[0]),
		"the screws are fully out before the lid moves: lid %s, screw %s" % [q_off["lid"], q_fo.lid_screws[0]])
	var e_off := Explode.offsets(spec, 0.1)
	var e_fo := Explode.fastener_offsets(spec, 0.1)
	check((e_off["lid"] as Vector3) == Vector3.ZERO and (e_fo.lid_screws[0] as Vector3).length() > 0.0,
		"while the screws back out, the lid stays home")
	check((Explode.offsets(spec, 0.375)["lid"] as Vector3).length() > 0.0, "after the screws, the lid comes off")
	# §4.5: a part held by a fastener group is free once the group has backed out
	var ws := Workshop.new()
	ws.spec = spec
	ws.words = data
	for id in spec.comps:
		ws.comps[id] = root
	for g in spec.groups:
		ws.groups[g] = root
	ws.s = 0.0
	check(ws.why_not_free("lid") == "Take the screws out before the lid.", "assembled, the lid is held by its screws: %s" % ws.why_not_free("lid"))
	ws.hidden["lid_screws"] = true
	check(ws.why_not_free("lid") == "Take the screws out before the lid.", "hidden screws still hold the lid: %s" % ws.why_not_free("lid"))
	ws.hidden.clear()
	ws.s = 1.0
	check(ws.why_not_free("lid") == "", "fully exploded, the screws out, the lid is free: %s" % ws.why_not_free("lid"))
	# the lid taken apart alone: its own screws hold it to the base, which stays home, so they stay too
	var lfo := Explode.fastener_offsets(spec, 1.0, "lid")
	check(not lfo.has("lid_screws") or (lfo.lid_screws[0] as Vector3) == Vector3.ZERO, "a subassembly's own fasteners stay home with it: %s" % str(lfo))
	ws.free()
	root.free()

## A sealed component's insides never come apart: not when a part inside it is the chosen subassembly, and not its
## own fastener groups.
func _sealed_edges() -> void:
	var spec := {"comps": {
			"shell": {"parent": "", "dir": Vector3.UP, "dist": 0.1, "sealed": true},
			"inner": {"parent": "shell", "dir": Vector3.RIGHT, "dist": 0.1, "sealed": false},
			"core": {"parent": "inner", "dir": Vector3.UP, "dist": 0.1, "sealed": false},
			"lid": {"parent": "", "dir": Vector3.BACK, "dist": 0.1, "sealed": false}},
		"groups": {"shell_pins": {"host": "shell", "items": [Transform3D.IDENTITY], "back_out": 0.02, "axis": Vector3.BACK},
			"lid_bolts": {"host": "lid", "items": [Transform3D.IDENTITY], "back_out": 0.02, "axis": Vector3.BACK}},
		"order": ["shell", "inner", "core", "lid"]}
	var sub := Explode.offsets(spec, 1.0, "inner")
	check(not sub.has("core") or (sub.core as Vector3) == Vector3.ZERO, "a part inside a sealed one, taken apart alone, stays whole: %s" % str(sub))
	var fo := Explode.fastener_offsets(spec, 1.0)
	check(not fo.has("shell_pins") and fo.has("lid_bolts"), "a sealed component's own fasteners stay; another's back out: %s" % str(fo.keys()))
	# and they can't be picked up either (§4.5: a sealed component's insides are never free)
	var ws := Workshop.new()
	ws.spec = spec
	ws.words = {"components": {"shell": {"sealed_why": "The shell is sealed."}}}
	for id in spec.comps:
		ws.comps[id] = true
	for g in spec.groups:
		ws.groups[g] = true
	check(ws.why_not_free("shell_pins") == "The shell is sealed.", "a sealed component's fasteners are not free: '%s'" % ws.why_not_free("shell_pins"))
	check(ws.why_not_free("lid_bolts") == "", "another's are")
	ws.free()

## The adversarial reviews' findings, on the shown machine (each check fails without its fix).
func _review_checks(tree: SceneTree, ws, w: Dictionary, at0: Dictionary) -> void:
	# a tree pick of a sealed part's child says why it can't be picked up, as a pick in the view does
	ws.select("isolator")
	check(ws.note == w.components.sensor_module.sealed_why, "a tree pick of a sealed part's child says why: '%s'" % ws.note)
	# "Selected subassembly only": a pick inside the subassembly taken apart keeps it apart; a pick outside takes that one
	ws.select("housing")
	ws.set_only_selected(true)
	ws.set_slider(1.0)
	var apart := _transforms(ws)
	ws.select("cover_front")
	check(ws.root_id == "housing" and _transforms(ws) == apart, "a pick inside the subassembly taken apart keeps it apart (root %s)" % ws.root_id)
	ws.select("process_flange")
	check(ws.root_id == "process_flange", "a pick outside it takes that one apart (root %s)" % ws.root_id)
	ws.set_only_selected(false)
	ws.set_slider(0.0)
	# a drag held as Reset, a new selection, Hide or Reassemble comes: it moves nothing afterwards
	var fake := {"kind": "move", "axis": Vector3.RIGHT, "a": Vector2.ZERO, "b": Vector2(100, 0), "len": 0.05,
		"from": Vector2.ZERO, "start": Transform3D.IDENTITY}
	ws.select("cover_front")
	ws._drag = fake.duplicate()
	ws.reset()
	ws._drag_handle(Vector2(50, 0))
	check(ws.handled.is_empty(), "a drag held through Reset moves nothing after it (%s)" % str(ws.handled.keys()))
	ws.select("cover_front")
	ws._drag = fake.duplicate()
	ws.select("terminal_block")
	ws._drag_handle(Vector2(50, 0))
	check(not ws.handled.has("terminal_block"), "a drag held through a change of selection doesn't move the new part")
	ws._drag = fake.duplicate()
	ws.hide_selected()
	ws._drag_handle(Vector2(50, 0))
	check(ws.handled.is_empty(), "a drag held through Hide moves nothing")
	ws.reset()
	# a drag along an arrow never throws the part farther than the machine's size
	ws.select("cover_front")
	var near_on := fake.duplicate()
	near_on.b = Vector2(2, 0)
	ws._drag = near_on
	ws._drag_handle(Vector2(2000, 0))
	var reach: float = (ws.machine.get_meta("box") as AABB).size.length()
	check(ws.handled.has("cover_front") and (ws.handled.cover_front as Transform3D).origin.length() <= reach + 1e-4,
		"a drag along a short arrow stays within the machine's size (%.2f m, size %.2f m)" % [(ws.handled.get("cover_front", Transform3D()) as Transform3D).origin.length(), reach])
	ws._drag = {}
	ws.reset()
	# an arrow seen end on can't be taken
	ws.select("cover_front")
	await tree.process_frame
	var hc: Vector3 = ws.handle.global_position
	ws.cam.target = hc
	ws.cam.yaw = PI / 2.0
	ws.cam.pitch = 0.0
	ws.cam.place()
	ws._place_handle()
	var took: bool = ws._grab_handle(ws.cam.unproject_position(hc))
	check(not took or absf((ws._drag.axis as Vector3).dot(Vector3.RIGHT)) < 0.5, "an arrow seen end on is not taken (%s)" % str(ws._drag.get("axis")))
	ws._drag = {}
	ws.cam.reset_view()
	# the handle hides on a part whose parent is hidden
	ws.hidden["housing"] = true
	ws.apply()
	ws.select("cover_front")
	ws._place_handle()
	check(not ws.handle.visible, "no handle on a part inside a hidden one")
	ws.reset()
	# the move keys (the arrows) walk between the tools while one has the focus: they don't zoom
	ws.panels.slider.grab_focus()
	var d0: float = ws.cam.dist
	Input.action_press("move_forward")
	ws._process(0.1)
	Input.action_release("move_forward")
	check(is_equal_approx(ws.cam.dist, d0), "the arrow keys don't zoom while the tools have the focus (%.3f, was %.3f)" % [ws.cam.dist, d0])
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_LEFT_Y
	jm.axis_value = -1.0
	ws.get_viewport().push_input(jm)
	jm.axis_value = 0.0
	ws.get_viewport().push_input(jm)
	check(ws.get_viewport().gui_get_focus_owner() == ws.panels.slider, "the left stick doesn't walk between the tools")
	ws.panels.slider.release_focus()
	ws.select("")

## The adversarial reviews' findings on the way in and out (each check fails without its fix).
func _review_plant_checks(tree: SceneTree, main, ws, ui) -> void:
	# with the plant drawn before, it is drawn again after
	main.get_viewport().disable_3d = false
	ws.open("pressure_transmitter")
	await _wait_shown(tree, ws)
	ws.close()
	await ws.left
	check(not main.get_viewport().disable_3d, "back in the plant, its 3D drawn again")
	# the control room's screens keep the plant's 3D off: leaving the Workshop leaves it off
	main.get_viewport().disable_3d = true
	ws.open("pressure_transmitter")
	await _wait_shown(tree, ws)
	ws.close()
	await ws.left
	check(main.get_viewport().disable_3d, "back to the control room's screens, the plant's 3D stays off")
	main.get_viewport().disable_3d = false
	# single play: an autosave while the Workshop shows keeps the plant's speed from before, not paused
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	ws.open("pressure_transmitter")
	await _wait_shown(tree, ws)
	check(ui.autosave == null or int(ui.autosave.payload().clock.speed) == SimClock.Speed.NORMAL,
		"an autosave in the Workshop keeps the plant's speed from before")
	# a link that comes while the Workshop shows waits for the plant
	ui.close_card()
	ui.handle_link("walkdown-plant://kks/30PAC10AP001")
	check(not ui.card.visible and String(ui.get("held_link")) != "", "a link doesn't open a card unseen behind the Workshop")
	# a finger down as the Workshop closes is not left in the camera
	var tp := InputEventScreenTouch.new()
	tp.index = 0; tp.position = Vector2(50, 50); tp.pressed = true
	ws._on_view_input(tp)
	ws.close()
	await ws.left
	check(ws.cam._touches.is_empty(), "no finger is left down after the Workshop closed")
	check(ui.card.visible and ui.card.code == "30PAC10AP001" and String(ui.get("held_link")) == "", "back in the plant, the link opens its card")
	ui.close_card()

## Framing a small part keeps the zoom's reach out to the whole machine.
func _orbit_limits(tree: SceneTree) -> void:
	var o = Orbit.new()   # (untyped: called as the camera is)
	tree.root.add_child(o)
	o.call("frame", AABB(Vector3(-5, 0, -5), Vector3(10, 10, 10)), false, true)   # (by name: compiles against any camera)
	var far0: float = o.dist_max
	o.frame(AABB(Vector3.ZERO, Vector3.ONE * 0.02))
	check(o.dist_max >= far0, "framing a small part keeps the zoom-out limit (%.1f, was %.1f)" % [o.dist_max, far0])
	o.free()
