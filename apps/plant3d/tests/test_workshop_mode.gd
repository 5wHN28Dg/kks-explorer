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

var p: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		p.append(what)

func run(tree: SceneTree) -> Array:
	_fixture_explode()
	_pos_flag()
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
	check(App.find_button(main.hud.extra, "Pressure transmitter") != null, "the settings list the Workshop's kinds")
	main.hud.show_settings(false)
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
	var at: Vector3 = main.player.global_position
	var look: Vector3 = main.player.rotation
	if wbtn == null:
		main.free()
		return p
	wbtn.pressed.emit()
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
	check(ws.pick(mid) != "", "a pick on the housing finds a part")
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
	check(t1["isolator"] == at0["isolator"] and t1["sensor_cell"] == at0["sensor_cell"], "a sealed part's children never come apart")
	ws.set_slider(0.0)
	check(_transforms(ws) == at0, "back to 0, every transform is exactly as built")
	ws.set_slider(0.1)
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
	ws.handled["cover_front"] = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.05, 0.02, 0))
	ws.apply()
	check(_transforms(ws)["cover_front"] != at0["cover_front"], "a handled part moves")
	ws.hide_selected()
	check(not ws.comps["cover_front"].visible, "Hide hides the part")
	ws.select("terminal_block")
	ws.isolate()
	check(ws.comps["terminal_block"].visible and not ws.comps["manifold"].visible, "Isolate keeps the part and hides the rest")
	ws.show_all()
	check(ws.comps["manifold"].visible and ws.hidden.size() <= 1, "Show all shows them again")
	ws.reset()
	check(_transforms(ws) == at0 and ws.hidden.is_empty(), "Reset: every part where it was built, everything shown")
	# Reassemble all animates home
	ws.set_slider(1.0)
	ws.reassemble()
	for i in 120:
		await tree.process_frame
		if ws.s == 0.0:
			break
	check(ws.s == 0.0 and _transforms(ws) == at0, "Reassemble all brings everything home")
	# back to the plant
	ws.close()
	await ws.left
	check(not ws.is_open and not main.get_viewport().disable_3d, "back in the plant, its 3D drawn again")
	check(ui.clock.speed == SimClock.Speed.NORMAL, "the plant's speed before the Workshop is back")
	check(not ui.sounds.muted, "the plant's sounds are back")
	check(main.player.global_position.distance_to(at) < 0.01 and main.player.rotation.distance_to(look) < 1e-4, "the trainee stands where they were")
	check(ui.root.visible and main.hud.visible and ui.alarms.visible and ui.card.visible, "the plant's panels are as they were")
	check(ws.exit_ms >= 0.0, "the exit is measured (%.0f ms)" % ws.exit_ms)
	await tree.process_frame
	check(main.player.input_enabled or ui.screens_open(), "the walker walks again")
	# a session: the plant runs on
	ui.close_card()
	ws.force_session = true
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	ws.open("pressure_transmitter")
	check(ui.clock.speed == SimClock.Speed.NORMAL, "in a session the plant does not pause")
	await _wait_shown(tree, ws)
	check(ws.panels.strip.visible and ws.panels.strip.text.contains("runs on"), "in a session the strip says the plant runs on")
	ws.close()
	await ws.left
	ws.force_session = false
	check(ui.clock.speed == SimClock.Speed.NORMAL, "leaving a session's Workshop leaves the plant's speed alone")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	main.free()
	return p

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
	# levels: base, lid (0); core, lid_screws (1): D = 2, so at 0.5 the top level is out and the next not begun
	check((half["lid"] as Vector3).is_equal_approx(full["lid"]) and (half["core"] as Vector3) == Vector3.ZERO, "the top level is out by half way, the next level not begun")
	check((full["core"] as Vector3).length() > 0.0, "fully exploded, the core leaves the base")
	var fo := Explode.fastener_offsets(spec, 1.0)
	check(fo.has("lid_screws") and fo.lid_screws.size() == 2 and (fo.lid_screws[0] as Vector3).length() > 0.0, "the screws back out")
	root.free()
