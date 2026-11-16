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
const WORK := "wo_cond_p2_fix"
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
	sp.number_edit.text = ""
	_press(sp.body, "issue_send")
	await shot("counter_empty_number", sp)
	sp.number_edit.text = "WDP-PT-FERRULES"
	sp.qty_edit.text = "0"
	_press(sp.body, "issue_send")
	await shot("counter_qty_zero", sp)
	sp.qty_edit.text = "10"
	_press(sp.body, "issue_send")
	ui.clock.run_steps(2)
	await shot("counter_issued", sp)
	ui.open_work_orders(wid)
	await shot("wo_open_order", wp)
	ui.close_work_orders()
	ui.open_debrief()
	await shot("debrief_parts", ui.debrief)
	ui.close_debrief()
	ui.open_stores("order", "pt_unit_a3")
	await shot("order_form", sp)
	sp.order_qty.text = "2"
	_press(sp.body, "to_list")
	await process_frame
	_press(sp.body, "order_pt_unit_a3")
	await shot("order_after_catalogue", sp)
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
	# the look-alike issued against the job's order, its permit accepted (written in for the picture): the refusal's
	# sentence is the look-alike's, with what to do next
	e.sr_issued[WORK] = {"pt_unit_a4": 1}
	e.pstate[e.m.work_ix[WORK]] = 5
	var x: Dictionary = e.m.hands_ix[PT2 + "|fit_tx"]
	ui.work._show(Stores.fit_reason(e, x, "wrong_part"), "process_flange")
	await shot("work_wrong_part", ui.work)
	var fit = ui.work.actions.find_child("act_fit_tx", true, false)
	var p = fit.get_parent() if fit != null else null
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).ensure_control_visible(fit)
	await shot("work_wrong_part_scrolled", ui.work)
	ui.work.close()
	ui.open_stores("issue")
	await shot("counter_walk_first", ui.stores)
	ui.close_stores()
	ui.open_work_orders(WORK)
	await shot("wo_issued_parts", ui.work_orders)
	ui.close_work_orders()
	ui.open_debrief()
	ui.debrief._tab("diagnosis")
	await shot("debrief_diagnosis", ui.debrief)
	ui.inputs.repair(FAULT)
	ui.clock.run_steps(3)
	ui.debrief._diag_sig = ""
	ui.debrief._tab("diagnosis")
	await shot("debrief_diagnosis_put_right", ui.debrief)
	var fb = ui.debrief.find_child("failed_part", true, false)
	if fb is BaseButton:
		(fb as BaseButton).pressed.emit()
		var ws = ui.main.workshop
		for i in 600:
			if ws.is_open and ws.machine != null and ws.selected != "":
				break
			await process_frame
		await shot("workshop_failed_part", ws, 120)
		ws.close()
		for i in 30:
			await process_frame
		if ui.open_workshop("pressure_transmitter", PT2):
			for i in 600:
				if ws.is_open and ws.machine != null:
					break
				await process_frame
			await shot("workshop_from_settings", ws, 120)   # (the same Workshop opened the usual way, to compare)
			ws.close()
	else:
		print("wm2_shots: no failed_part button")
		ui.close_debrief()
	if ui.has_method("open_crew"):
		ui.open_crew()
	else:
		ui.crew.visible = true
	await shot("crew_jump", ui.crew)
	await _part4()
	quit(0)


## Part 4 (REALISM.md §2.24): the Crew panel as the I&C technician on the replacement job in the run with the
## storekeeper away, at the wait for the spare, held for parts, at the choice of the swap; then the list of runs
## with crews a run without them offers. The task and its step are written in for the pictures.
func _part4() -> void:
	ui.close_crew()
	ui.start_shift("shift_fail_absent")
	await process_frame
	ui.take_role("ic1")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var pi: int = ui.my_person()
	if pi == -1 or not e._sm.tasks.has("job_cond_p2_fix_tx"):
		print("wm2_shots: no technician or no replacement job")
		return
	ui.open_crew()
	for pic in [["crew_wait_issued", 5], ["crew_choose_swap", 6], ["crew_held_parts", 8], ["crew_held_stock", 10],
			["crew_held_issue", 14]]:
		e.sp_cur[pi] = {"task": "job_cond_p2_fix_tx", "prio": 2, "made": e.step_no, "order": e.st_order,
				"step": pic[1], "st": {}, "work": WORK, "code": PT2, "alarm": null, "src": null, "idle": false,
				"started": true, "int": true, "owner": null, "act": null, "orig": null}
		ui.crew.refresh()
		await process_frame
		var cur = ui.crew.body.find_child("copy_part_WDP-PT-UNIT-A3", true, false)
		if cur == null:
			for l in ui.crew.body.find_children("*", "Label", true, false):
				if (l as Label).text.begins_with("▶"):
					cur = l
		var scr = ui.crew.body.get_parent()
		if cur != null and scr is ScrollContainer:
			await process_frame
			(scr as ScrollContainer).ensure_control_visible(cur)
		await shot(pic[0], ui.crew)
	ui.close_crew()
	ui.model.scenarios.erase("shots_stores")        # (the pictures' own copy of shift_aged is not one of the list)
	ui.start_shift("cold_iron")
	await process_frame
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	ui.open_crew()
	await process_frame
	if ui.crew.body.get_parent() is ScrollContainer:
		(ui.crew.body.get_parent() as ScrollContainer).scroll_vertical = 0
	await shot("crew_start_list", ui.crew)
