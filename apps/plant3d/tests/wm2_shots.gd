## Pictures of WM2's screens (docs/plant3d/REALISM.md §2.23–§2.24), for the UI/UX audit's evidence
## (docs/UI-UX-POLICY.md §3.3; not a test: it needs a display):
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/wm2_shots.gd -- --out=DIR [--phone]
## --phone draws them at the phone's UI scale (run it at the phone's resolution, `--resolution 2960x1440`).
## In the aged plant in free mode: the stores' catalogue, the look-alikes side by side, the counter's issue form with a
## refusal, a part's order form, the deliveries with the jump to the next one. As the I&C technician at condenser
## pressure transmitter 2 with its sensor failed: the work view naming the part a fitting needs, the look-alike's
## refusal in words, the diagnosis tab, and the crew panel's jump days. Beside each picture, DIR/<name>.txt lists every
## control that takes input (its rect in canvas px and in dp at the Note 9's factor, §2's units) and every label's
## font size and colour; the panel's background is Color(0.08, 0.09, 0.11, 0.92) (ui/widgets.gd).
extends SceneTree

const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Stores = preload("res://ui/stores_panel.gd")

const PT2 := "30MAG10CP002"
const MOTOR := "00PGC10AP001"
const FAULT := "cond_p2_low"
const DP := 0.457           # dp per canvas px on the Note 9 (docs/UI-UX-POLICY.md §2)

var out := ""
var phone := false
var main: Node
var ui


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--phone":
			phone = true
	_run.call_deferred()


func shot(name: String, panel: Node, frames := 30) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var base := out.path_join(("phone_" if phone else "") + name)
	print("wm2_shots: %s %d" % [name, img.save_png(base + ".png")])
	var lines := PackedStringArray()
	lines.append("# %s (%s): controls that take input, then labels; canvas px, dp = px × %.3f" % [name,
			"phone, ui scale 1.35" if phone else "desktop", DP])
	_dump(panel, lines)
	var f := FileAccess.open(base + ".txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")


func _dump(n: Node, lines: PackedStringArray) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		if c is BaseButton or c is LineEdit or c is OptionButton or c is TextEdit:
			var t := String(c.get("text")) if c.get("text") != null else ""
			lines.append("control %s %s \"%s\" at (%d,%d) size %dx%d px = %.0fx%.0f dp%s" % [c.get_class(), c.name,
					t.replace("\n", " ").left(60), r.position.x, r.position.y, r.size.x, r.size.y, r.size.x * DP,
					r.size.y * DP, " (disabled)" if c is BaseButton and (c as BaseButton).disabled else ""])
		elif c is Label:
			var l := c as Label
			var fs := l.get_theme_font_size("font_size")
			var col := l.get_theme_color("font_color")
			lines.append("label %s size %d px = %.1f sp colour %s \"%s\"" % [l.name, fs, fs * DP, col.to_html(false),
					l.text.replace("\n", " / ").left(90)])
	for ch in n.get_children():
		_dump(ch, lines)


func _put(e, name: String, v: float) -> void:
	e.cur[e.ix[name]] = v
	e.prev[e.ix[name]] = v


func _press(n: Node, name: String) -> void:
	var b = n.find_child(name, true, false)
	if b is BaseButton and not (b as BaseButton).disabled:
		(b as BaseButton).pressed.emit()
	else:
		print("wm2_shots: no %s to press" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"      # never the trainee's run, and no offer in the shots
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":     # (with a display the UI comes after the sky)
		await process_frame
	if main.start_error != "":
		printerr("the app did not start: " + main.start_error)
		quit(1)
		return
	ui = main.ui
	ui.player.set_physics_process(false)
	# --- the stores in the aged plant, free mode
	var sc: Dictionary = ui.model.scenarios["shift_aged"].duplicate(true)
	sc["id"] = "shots_stores"
	sc["start"] = {"day": 1, "time": "06:30"}
	ui.model.scenarios["shots_stores"] = sc
	ui.start_shift("shots_stores")
	await process_frame
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var sp = ui.stores
	var wp = ui.work_orders
	wp.open_for_code(MOTOR)
	wp.report(MOTOR, "vibration")
	ui.clock.run_steps(2)
	var wid: String = wp.work_for(e, MOTOR, "vibration")["id"]
	ui.inputs.work_order(wid, "plan", null, [3])
	ui.clock.run_steps(2)
	ui.open_stores()
	await shot("stores_catalogue", sp)
	var a3 = sp.body.find_child("part_pt_unit_a3", true, false)
	if a3 != null:
		var scr = sp.body.get_parent()
		if scr is ScrollContainer:
			await process_frame
			(scr as ScrollContainer).ensure_control_visible(a3)
	await shot("stores_lookalikes", sp)
	ui.open_stores("issue", wid)
	await process_frame
	sp.number_edit.text = "WDP-PT-SENSOR-MODULE"
	sp.qty_edit.text = "5"
	_press(sp.body, "issue_send")
	ui.clock.run_steps(2)
	await shot("counter_refused", sp)
	ui.open_stores("order", "pt_unit_a3")
	await shot("order_form", sp)
	sp.order("cp_oil", 1)
	ui.clock.run_steps(2)
	ui.open_stores()
	await process_frame
	var dl = sp.body.find_child("jump_delivery", true, false)
	if dl == null:
		dl = sp.body.find_child("deliveries", true, false)
	if dl != null and sp.body.get_parent() is ScrollContainer:
		(sp.body.get_parent() as ScrollContainer).ensure_control_visible(dl)
	await shot("stores_deliveries", sp)
	ui.close_stores()
	# --- the replacement, as the I&C technician
	ui.start_shift("shift_cold")
	await process_frame
	ui.take_role("ic1")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	e = ui.clock.engine
	ui.inputs.fault(FAULT, "failed")
	ui.clock.run_steps(2)
	ui.go_to_place(e._sm.work_at[PT2])
	ui._place_tick()
	ui.clock.run_steps(1)
	if not ui.work.open(PT2):
		print("wm2_shots: work view not opened: ", ui.work.cannot(PT2))
		quit(1)
		return
	while not ui.work.loaded():
		await process_frame
	e.carried["ic1"] = ["spanner_17", "sd_term", "hart", "dmm"]
	for st in ["cpt2_flange_bolts_off", "cpt2_cover_back_off"]:
		_put(e, st, 1.0)
	ui.clock.run_steps(2)
	ui.work.pick_comp("process_flange")
	ui.work.pick_tool("spanner_17")
	ui.work.refresh()
	await shot("work_fitting", ui.work)
	var x: Dictionary = e.m.hands_ix[PT2 + "|fit_tx"]
	ui.work._show(Stores.fit_reason(e, x, "wrong_part"), "process_flange")
	await shot("work_wrong_part", ui.work)
	ui.work.close()
	ui.open_debrief()
	ui.debrief._tab("diagnosis")
	await shot("debrief_diagnosis", ui.debrief)
	ui.close_debrief()
	if ui.has_method("open_crew"):
		ui.open_crew()
	else:
		ui.crew.visible = true
	await shot("crew_jump", ui.crew)
	quit(0)
