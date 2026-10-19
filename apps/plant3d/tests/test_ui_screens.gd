## The control room screens (docs/PLANT3D.md §7.11, ui/mimic.gd, ui/screens_model.gd):
## - made from the content: every code the model has something for is on exactly one screen or left out with its
##   reason, every value with a unit and a code is on the screen of its code, and a value added to the model lands on
##   its system's screen without touching screens.json;
## - reached from the control room's button, its operator desks and H, only in the control room;
## - live: the values and states follow the plant at a few hertz (not every frame), alarms show by priority on the
##   screen, its tab and the banner;
## - operating from a screen goes through the card and the engine: a start whose permissive fails is refused, with
##   the permissive's sentence, and nothing moves; once the permissive is met the same tap starts the pump.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const PlantInfo = preload("res://ui/plant_info.gd")
const ScreensModel = preload("res://ui/screens_model.gd")
const SimClock = preload("res://ui/sim_clock.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	p.append_array(_generation(ui))
	p.append_array(_flows_through(ui))
	p.append_array(await _reach(tree, ui))
	p.append_array(await _live(tree, ui))
	p.append_array(await _operate(tree, ui))
	main.free()
	return p


## Every shown code on exactly one screen or left out; every coded value with a unit on its code's screen.
func _generation(ui) -> Array:
	var p: Array = []
	var sm = ui.screens
	if sm.error != "":
		return ["the screens did not load: " + sm.error]
	if not sm.unplaced.is_empty():
		p.append("codes on no screen and not left out: %s" % str(sm.unplaced))
	var seen := {}
	for si in sm.screens.size():
		for gr in sm.screens[si].groups:
			for c in gr.items:
				if seen.has(c):
					p.append("%s is on two screens: %s and %s" % [c, seen[c], sm.screens[si].id])
				seen[c] = sm.screens[si].id
	for c in sm.items:
		if not seen.has(c) and not sm.left_out.has(c):
			p.append("%s is on no screen" % c)
		if seen.has(c) and sm.left_out.has(c):
			p.append("%s is on a screen and left out" % c)
	# the model's own lists, read afresh: values with a unit and a code, ops, lamps, positions, machines, alarms, trips
	var want := {}
	for v in ui.model.values:
		if v[1].has("unit") and v[1].has("kks"):
			want[v[1]["kks"]] = true
			if seen.has(v[1]["kks"]) and not sm.items[v[1]["kks"]].values.has(v[0]):
				p.append("value %s is not listed with its code %s" % [v[0], v[1]["kks"]])
	for o in ui.model.ops:
		want[o["kks"]] = true
	for b in ui.model.bind:
		if b.has("show") or b.has("lamp") or b.get("anim", "") in ["stem", "disc", "blades"]:
			want[b["kks"]] = true
	for a in ui.model.alarms:
		want[a.get("kks", a.get("where"))] = true
	for t in ui.model.trips:
		if t.has("kks"):
			want[t["kks"]] = true
	for mc in ui.model.machines:
		if mc.has("kks"):
			want[mc["kks"]] = true
	for c in want:
		if not seen.has(c) and not sm.left_out.has(c):
			p.append("the model's %s is on no screen and not left out" % c)
	for c in sm.left_out:
		if String(sm.left_out[c]).length() < 10:
			p.append("%s is left out without a reason" % c)
	# the extras: once each, values without a code; the rest of those are the model's workings
	var extras := {}
	for sc in sm.screens:
		for gr in sc.groups:
			for v in gr.extra:
				if extras.has(v):
					p.append("extra %s twice" % v)
				extras[v] = true
	for v in ui.model.values:
		if v[1].has("unit") and not v[1].has("kks") and not extras.has(v[0]) and not sm.internal.has(v[0]):
			p.append("value %s (a unit, no code) is neither shown nor counted as the model's workings" % v[0])
	# the user's list (2026-10-19): a screen for each of these systems, by the codes they hold
	for need in [["10MBV10AP001", "GT lube oil"], ["10MBP10AA001", "fuel gas"], ["10HAD30CL001", "HP drum"],
			["10LAB30AA001", "feedwater"], ["10LAE30AA001", "attemperation"], ["10LBA30AA901", "HP safety valve"],
			["30MAA10", "steam turbine"], ["30MAJ10AP001", "vacuum"], ["30LCB10AP001", "condensate"],
			["30PAC10AP001", "circulating water"], ["30PAD10AN001", "cooling tower"], ["00PGC10AP001", "closed cooling water"],
			["10BAC10", "generator breaker"], ["10MKC10", "excitation"]]:
		if not seen.has(need[0]):
			p.append("no screen shows %s (%s)" % [need[1], need[0]])
	var counts := {}
	for c in seen:
		counts[seen[c]] = counts.get(seen[c], 0) + 1
	print("  screens: %d codes on %d screens %s, %d left out, %d values the model's workings" % [seen.size(),
			sm.screens.size(), str(counts), sm.left_out.size(), sm.internal.size()])
	return p


## A value the content adds lands on its system's screen, screens.json untouched.
func _flows_through(ui) -> Array:
	var files := {}
	var top := "res://built/content"
	for rel in ["plant.json"]:
		files[rel] = FileAccess.get_file_as_bytes(top + "/" + rel)
	for sub in ["areas", "model", "scenarios"]:
		for f in DirAccess.get_files_at(top + "/" + sub):
			if f.ends_with(".json"):
				files[sub + "/" + f] = FileAccess.get_file_as_bytes(top + "/" + sub + "/" + f)
	var cw = JSON.parse_string(files["model/cw.json"].get_string_from_utf8())
	cw["values"].append(["cw_a_bearing_t", {"const": 41, "unit": "°C", "kks": "30PAC10CT901"}])
	files["model/cw.json"] = cw
	var m = PlantModel.from_files(files)
	if m.error != "":
		return ["the changed model did not load: " + m.error]
	var sm = ScreensModel.new(PlantInfo.new(m), ScreensModel.load_file(top + "/screens.json"))
	var at = sm.screen_of.get("30PAC10CT901")
	if at == null or sm.screens[at[0]].id != "cw":
		return ["a value added to the model under 30PAC10 is not on the circulating water screen: %s" % str(at)]
	return []


func _reach(tree: SceneTree, ui) -> Array:
	var p: Array = []
	# outside the control room: the screens are not opened
	ui.fly_to("30PAC10AP001")
	for i in 200:
		if not ui.player.scripted:
			break
		await tree.process_frame
	ui.open_screens()
	if ui.screens_open():
		p.append("the screens opened outside the control room")
	# the Control room button: there, and the screens open
	App.find_button(ui.root, "Control room").pressed.emit()
	await tree.process_frame
	if not ui.in_control_room() or not ui.screens_open():
		p.append("the Control room button did not open the screens in the control room")
	if ui.player.input_enabled:
		p.append("the trainee still walks with the screens open")
	App.find_button(ui.root, "Control room").pressed.emit()
	if ui.screens_open():
		p.append("the Control room button in the control room did not close the screens")
	if not ui.player.input_enabled:
		p.append("walking did not come back when the screens closed")
	# an operator desk: its card is the screens
	for desk in ["00CWA10", "00CWB10"]:
		if not ui.index.has(desk):
			p.append("operator desk %s is not in the built control room" % desk)
		ui.open_card(desk)
		if not ui.screens_open() or ui.card.visible:
			p.append("the operator desk %s did not open the screens" % desk)
		ui.close_screens()
	# Esc closes them (the top panel)
	ui.open_screens("cw")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	ui._unhandled_input(esc)
	if ui.screens_open():
		p.append("Esc did not close the screens")
	return p


func _live(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var mim = ui.mimic
	var sm = ui.screens
	ui.open_screens("cw")
	if mim.current != sm.screen_index("cw"):
		return ["open_screens(cw) shows screen %d" % mim.current]
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	await tree.process_frame
	var r0: int = mim.redraws
	var t0 := Time.get_ticks_msec()
	for i in 120:
		await tree.process_frame
	var secs := maxf(0.001, (Time.get_ticks_msec() - t0) / 1000.0) * Engine.time_scale
	# each piece about 4 times a second: in 120 frames (2 s at 60 fps) about 8 draws a piece, never one a frame
	var per_piece: float = float(mim.redraws - r0) / maxi(1, mim.pieces_count())
	if per_piece > 16.0 or per_piece < 2.0:
		p.append("each piece of the screen was drawn %.1f times in 120 frames: it should refresh at a few hertz" % per_piece)
	print("  screens: %d pieces, %.1f draws each in 120 frames (%.1f Hz a piece), the longest piece %d µs" % [
			mim.pieces_count(), per_piece, per_piece / maxf(secs, 2.0), mim.draw_us])
	# a state change shows: CW pump A's valve to its start position, then the pump's start (both screen ops)
	var e = ui.clock.engine
	var it: Dictionary = sm.items["30PAC10AA101"]
	if mim.item_state(it, e).words != "CLOSED":
		p.append("CW pump A's discharge valve is not shown closed at cold iron: %s" % mim.item_state(it, e).words)
	var o: Dictionary = ui.model.op_keys[ui.model.op_key("30PAC10AA101", "set", null)]
	ui.do_op(o, 0.15)
	ui.clock.run_steps(150)
	var st: Dictionary = mim.item_state(it, e)
	if st.words != "15 %" or st.on:
		p.append("the valve at its start position is shown as %s" % st.words)
	var st_moving: Dictionary = mim.item_state(it, e, 0.10)
	if not st_moving.words.begins_with("OPENING"):
		p.append("a valve whose position rose since the last look is not shown opening: %s" % st_moving.words)
	var drive: Dictionary = sm.items["30PAC10AP001"]
	if drive.kind != "drive" or mim.item_state(drive, e).words != "STOPPED":
		p.append("CW pump A is not a stopped drive: %s %s" % [drive.kind, mim.item_state(drive, e).words])
	# alarms on the screen, its tab and the banner: the instrument air low-pressure alarm (priority 1) at cold iron
	ui.clock.run_steps(1)
	var air: Dictionary = sm.items["00QFB10CP001"]
	var al: Array = sm.alarms_now(air, e)
	var k_air: int = ui.model.alarms.find(ui.model.alarms.filter(func(a): return a.get("kks", "") == "00QFB10CP001")[0])
	if e.astate[k_air] != "normal" and (al.is_empty() or al[0][0] != 1):
		p.append("the instrument air alarm is not on its item: %s" % str(al))
	var aux: int = sm.screen_index("aux")
	var counts: Dictionary = sm.screen_alarms(aux, e)
	var listed: Array = ui.alarms.entries("active")
	var on_screens := 0
	for si in sm.screens.size():
		on_screens += sm.screen_alarms(si, e).alarms.size()
	if on_screens != listed.size():
		p.append("the screens carry %d alarms, the alarm list %d" % [on_screens, listed.size()])
	print("  screens: %d active alarms at the start, auxiliaries' tab %s" % [listed.size(), str(counts.by)])
	if not listed.is_empty():
		mim.refresh()
		await tree.process_frame
		await tree.process_frame
		if mim._banner_rows.is_empty():
			p.append("the banner shows no alarm while %d are active" % listed.size())
		else:
			mim.go_to_alarm(mim._banner_rows[0][1])
			var a: Dictionary = ui.model.alarms[mim._banner_rows[0][1]]
			var c = a.get("kks", a.get("where"))
			if mim.selected != c:
				p.append("the banner's alarm did not lead to its code %s (selected %s)" % [c, mim.selected])
	ui.close_screens()
	return p


## Operating from the screen: the tap opens the card, the engine refuses or does the op as from anywhere.
func _operate(tree: SceneTree, ui) -> Array:
	var p: Array = []
	ui.restart("cold_iron", true)
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	ui.go_control_room()
	ui.open_screens("cw")
	var mim = ui.mimic
	await tree.process_frame
	await tree.process_frame
	mim.select("30PAC10AP001")
	await tree.process_frame
	var e = ui.clock.engine
	var it: Dictionary = ui.screens.items["30PAC10AP001"]
	var nt: String = mim._next_text(it, e)
	if not nt.begins_with("Start: ") or not nt.contains("missing"):
		p.append("the pump's next operation does not say its permissive is missing: %s" % nt)
	# a click on the pump's symbol, as a trainee does
	var at: Vector2 = mim.target_centre("30PAC10AP001")
	if not Rect2(Vector2.ZERO, mim.canvas.size).has_point(at):
		p.append("CW pump A is not in view after it was selected: %s" % str(at))
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		mim._canvas_input(ev)
	if not ui.card.visible or ui.card.code != "30PAC10AP001":
		return p + ["a click on CW pump A did not open its card: %s" % ui.card.code]
	if not ui.screens_open():
		p.append("the card closed the screens")
	var row := App.op_row(ui.card, "30PAC10AP001", "start")
	if row.is_empty() or (row[1] as Button).disabled:
		return p + ["the card opened from the screen does not offer the pump's start"]
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	var res: Dictionary = ui.op_result(row[0])
	if res.get("state", "") != "refused" or not String(res.get("text", "")).contains("not at its start position"):
		p.append("the start from the screen against a closed valve came back %s" % str(res))
	var ev_ref: Array = e.events.filter(func(x): return x[1] == "op" and x[2] == "30PAC10AP001")
	if ev_ref.is_empty() or ev_ref[-1][4] != "refused":
		p.append("the engine did not refuse the start: %s" % str(ev_ref))
	if e.truth(it.run):
		p.append("the refused pump runs")
	# the valve to its start position from the screen (keyboard: arrows to the valve, Enter, type, Set), then the start
	ui.close_card()
	mim.select("30PAC10AA101")
	var acc := InputEventAction.new()
	acc.action = "ui_accept"
	acc.pressed = true
	mim._canvas_input(acc)
	if ui.card.code != "30PAC10AA101":
		return p + ["Enter on the selected valve did not open its card: %s" % ui.card.code]
	row = App.op_row(ui.card, "30PAC10AA101", "set")
	(row[4] as LineEdit).text = "15"
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(200)
	mim.activate("30PAC10AP001")
	row = App.op_row(ui.card, "30PAC10AP001", "start")
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(5)
	if ui.op_result(row[0]).get("state", "") != "done" or not e.truth(it.run):
		p.append("with its valve at the start position the start from the screen came back %s" % str(ui.op_result(row[0])))
	if mim.item_state(it, e).words != "RUNNING":
		p.append("the running pump is shown %s" % mim.item_state(it, e).words)
	# moving between items with the arrows
	var before: String = mim.selected
	mim.move_selection(Vector2.RIGHT)
	if mim.selected == before:
		mim.move_selection(Vector2.DOWN)
	if mim.selected == before:
		p.append("the arrows did not move the selection from %s" % before)
	# the overview: a tile per screen; Enter on a tile opens it
	mim.show_screen(-1)
	if mim._targets().size() != ui.screens.screens.size():
		p.append("the overview has %d tiles for %d screens" % [mim._targets().size(), ui.screens.screens.size()])
	mim.activate("screen:2")
	if mim.current != 2:
		p.append("a tile did not open its screen")
	ui.close_card()
	ui.close_screens()
	return p
