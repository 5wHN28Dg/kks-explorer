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
const Player = preload("res://app/player.gd")


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
	p.append_array(await _legible(tree, ui))
	p.append_array(_any_state(ui))
	p.append_array(await _keys(tree, ui))
	p.append_array(await _review(tree, ui))
	p.append_array(await _resize(tree, ui))
	main.free()
	p.append_array(await _measure(tree))
	return p


static func _key(code: Key, uni := 0) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.physical_keycode = code
	k.keycode = code
	k.unicode = uni
	return k


static func _joy(b: JoyButton) -> InputEventJoypadButton:
	var j := InputEventJoypadButton.new()
	j.pressed = true
	j.button_index = b
	return j


static func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var m := InputEventJoypadMotion.new()
	m.axis = a
	m.axis_value = v
	return m


## The screens' keys and gamepad: Space and Y acknowledge the screen's alarms, F and the right stick's click fit it,
## + by the character typed and the triggers zoom, the stick moves the selection, the D-pad is left to its own jobs.
func _keys(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var mim = ui.mimic
	var e = ui.clock.engine
	ui.open_screens("aux")
	await tree.process_frame
	var unack := func() -> int:
		var n := 0
		for k in sm_alarms(ui, "aux"):
			if e.astate[k] == "active_unack" or e.astate[k] == "cleared_unack":
				n += 1
		return n
	# closed cooling water pump A started, then lost: alarms on the screen, acknowledged by Y
	ui.do_op({"kks": "00PGC10AP001", "do": "start"}, null)
	ui.clock.run_steps(30)
	ui.fault("ccw_both")
	ui.clock.run_steps(50)
	if unack.call() == 0:
		p.append("losing the running closed cooling water pump raised no alarm on the auxiliaries' screen")
	mim._canvas_input(_joy(JOY_BUTTON_Y))
	ui.clock.run_steps(1)
	if unack.call() != 0:
		p.append("Y did not acknowledge the screen's alarms (%d left)" % unack.call())
	mim.zoom_by(2.0)
	var z0: float = mim.zoom
	mim._canvas_input(_key(KEY_F, 102))
	if mim.zoom >= z0:
		p.append("F did not fit the whole screen (zoom %.2f from %.2f)" % [mim.zoom, z0])
	z0 = mim.zoom
	mim._canvas_input(_key(KEY_BRACKETRIGHT, 43))         # + where another layout puts it
	if mim.zoom <= z0:
		p.append("+ (typed) did not zoom in")
	z0 = mim.zoom
	mim._canvas_input(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	mim._canvas_input(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0))   # held: once
	mim._canvas_input(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0))
	if absf(mim.zoom - z0 * 1.25) > 1e-3:
		p.append("the right trigger did not zoom in once (%.3f from %.3f)" % [mim.zoom, z0])
	z0 = mim.zoom
	mim.zoom_by(2.0)
	mim._canvas_input(_joy(JOY_BUTTON_RIGHT_STICK))
	if mim.zoom >= z0 * 2.0 - 1e-3:
		p.append("the right stick's click did not fit the screen")
	var sel: String = mim.selected
	mim._canvas_input(_joy(JOY_BUTTON_DPAD_RIGHT))
	if mim.selected != sel:
		p.append("the D-pad moved the selection: it keeps its own jobs on the screens")
	mim._canvas_input(_axis(JOY_AXIS_LEFT_X, 1.0))
	if mim.selected == sel:
		p.append("the left stick did not move the selection")
	# Space acknowledges too: instrument air compressor A started, then both compressors lost
	ui.do_op({"kks": "00QFA10AN001", "do": "start"}, null)
	ui.clock.run_steps(1)
	App.run_until(ui, "ia_p_norm", 20000)
	ui.fault("ia_lost")
	ui.clock.run_steps(50)
	if unack.call() == 0:
		p.append("losing instrument air raised no alarm on the auxiliaries' screen")
	var n_unack: int = unack.call()
	ui.sounds.played.clear()
	mim._canvas_input(_key(KEY_SPACE, 32))
	ui.clock.run_steps(1)
	if unack.call() != 0:
		p.append("Space did not acknowledge the screen's alarms")
	# one acknowledge, one sound
	if ui.sounds.played.get("horn_ack", 0) != 1:
		p.append("acknowledging the screen (%d alarms on it) played the acknowledge %d times" % [n_unack, ui.sounds.played.get("horn_ack", 0)])
	# moving the selection draws the two pieces it leaves and enters, not the whole screen
	ui.open_screens("ct")
	for k in 3:
		await tree.process_frame
	var tg: Array = mim._targets()
	var r0: int = mim.redraws
	mim.select(tg[tg.size() / 2].id)
	await tree.process_frame
	if mim.redraws - r0 > 8:
		p.append("moving the selection drew %d pieces of %d" % [mim.redraws - r0, mim._pieces.size()])
	# the map opens over the plant: the screens close (their keys would reach nothing under it)
	ui.main.toggle_map()
	if ui.screens_open():
		p.append("the screens stayed open under the map")
	ui.main.toggle_map()
	ui.close_screens()
	return p


func sm_alarms(ui, screen: String) -> Array:
	return ui.screens.screen_alarms(ui.screens.screen_index(screen), ui.clock.engine).alarms


## A resize keeps every piece where the view puts it; a turned phone lays the screen out again for its shape.
func _resize(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var mim = ui.mimic
	ui.open_screens("ct")
	await tree.process_frame
	var check := func(why: String) -> void:
		for pc in mim._pieces:
			var want: Vector2 = mim.offset + (pc[1] as Rect2).position * mim.zoom
			if (pc[0] as Control).position.distance_to(want) > 0.5:
				p.append("%s: a piece stands at %s, the view puts it at %s" % [why, str((pc[0] as Control).position), str(want)])
				return
	mim.offset += Vector2(-200, -100)
	mim._place_pieces()
	var sz: Vector2 = mim.canvas.size
	mim.canvas.size = sz * 0.9                 # the same shape, smaller: the offset is clamped again
	check.call("after a resize")
	var L0 = mim._layout_of(mim.current)
	mim.canvas.size = Vector2(sz.y, sz.x)     # turned
	if is_same(mim._layout_of(mim.current), L0):
		p.append("a turned canvas kept the layout chosen for the other shape")
	check.call("after turning")
	mim.canvas.size = sz
	ui.close_screens()
	return p


## A machine's command taken in any state (`"from": "*"`, PLANT3D.md) is what its item offers next when no command of
## its present state is there.
func _any_state(ui) -> Array:
	var sm = ui.screens
	for c in sm.items:
		var it: Dictionary = sm.items[c]
		for o in it.ops:
			if not o.has("machine"):
				continue
			var cmds: Dictionary = ui.model.machines[ui.info.machine_index(o["machine"])]["commands"]
			var keep := {}
			for k in cmds:
				keep[k] = cmds[k]["from"]
				cmds[k]["from"] = ["no such state"]
			cmds[o["do"]]["from"] = "*"
			var nx: Dictionary = sm.next_op(it, ui.clock.engine)
			for k in keep:
				cmds[k]["from"] = keep[k]
			if nx.get("do", "") != o["do"]:
				return ["%s's command %s, taken in any state, is not offered next (%s)" % [c, o["do"], str(nx)]]
			return []
	return ["no item with a machine's command"]


## The phone's measurement of the screens (app/main.gd walk=screens, phone/frames.sh): the screens open in the
## control room, each shown in turn, the frames and the screens' drawing counted.
func _measure(tree: SceneTree) -> Array:
	var p: Array = []
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts = {"walk": "screens", "seconds": "600"}
	tree.root.add_child(main)
	for i in 600:
		if main.screens_walk:
			break
		await tree.process_frame
	if not main.screens_walk or not main.ui.screens_open():
		main.free()
		return ["walk=screens did not open the screens"]
	var first: int = main.ui.mimic.current
	for i in 30:
		await tree.process_frame
	main._process(10.0)                       # 10 s on: the next screen
	for i in 30:
		await tree.process_frame
	if main.ui.mimic.current == first:
		p.append("walk=screens did not go on to the next screen")
	if main.times.is_empty() or main.ui.mimic.frames == 0:
		p.append("walk=screens counted no frames (%d, the screens %d)" % [main.times.size(), main.ui.mimic.frames])
	main.free()
	return p


## Every cell's KKS code is drawn whole (a compact cell's beside its value), every name in at most two lines of the
## cell, and a screen opens at a zoom whose text is read (on a phone's scale too: the Fit button alone goes smaller).
func _legible(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var mim = ui.mimic
	var sm = ui.screens
	var f: Font = mim._font()
	var w: float = mim.CELL_W - mim.PAD * 2
	for c in sm.items:
		var it: Dictionary = sm.items[c]
		var cw := f.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var room := w - (90.0 if mim._compact(it) else 72.0)   # a value of 9 characters, or three alarm badges
		if cw > room:
			p.append("%s's code needs %.0f px of %.0f in its cell" % [c, cw, room])
		var nl: PackedStringArray = mim._name_lines(it)
		var size := 14 if mim._compact(it) else 15
		if nl.size() > 2 or f.get_string_size(nl[nl.size() - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
			p.append("%s's name does not fit two lines of its cell: %s" % [c, str(nl)])
	if mim._name_lines({"code": "x", "name": "HP superheater spray control valve", "kind": "valve", "lamps": [],
			"values": [], "ops": [1]}).size() != 2:
		p.append("a long name is not set on two lines")
	ui.open_screens()
	for i in sm.screens.size():
		mim.show_screen(i)
		mim.fit()
		await tree.process_frame
		mim.fit(true)
		for k in 20:
			await tree.process_frame
	# at the phone's scale the overview opens at its top, its key values in view (not scrolled to its first tile)
	var Wd = load("res://ui/widgets.gd")
	var s0: float = Wd.scale
	Wd.scale = 1.35
	mim._layouts.clear()
	mim._view.clear()
	mim.selected = ""
	mim.show_screen(-1)
	mim.canvas.size = Vector2(1850, 600)      # the Note 9's canvas below the bars (its 2960 × 1440 at 1.6)
	mim._unsized = true
	mim._on_resized()
	var k0: Rect2 = mim._layout_of(-1)["keys"][0][1]
	if mim.to_screen(k0.position).y < 0.0:
		p.append("the overview opens scrolled past its key values (at %.0f)" % mim.to_screen(k0.position).y)
	Wd.scale = s0
	mim._layouts.clear()
	mim._view.clear()
	mim.show_screen(-1)
	# a word shown, then a card opened from the screen: the word moves clear of the card (its permissives)
	ui.toast("A word about the plant")
	ui.open_card("00PGC10AP001")
	for k in 3:
		await tree.process_frame
	if ui._toast.visible and ui._toast.get_global_rect().intersects(ui.card.get_global_rect()):
		p.append("the word covers the card: %s over %s" % [str(ui._toast.get_global_rect()), str(ui.card.get_global_rect())])
	ui.toast("TRIP: Steam turbine generator breaker opened by protection")      # a long word, beside the card
	await tree.process_frame
	var vr: Rect2 = ui.root.get_viewport_rect()
	var tr: Rect2 = ui._toast.get_global_rect()
	if tr.end.y > vr.end.y + 0.5 or tr.intersects(ui.card.get_global_rect()):
		p.append("a long word runs off the screen or over the card: %s (screen %s, card %s)" % [str(tr), str(vr),
				str(ui.card.get_global_rect())])
	ui.close_card()
	ui.close_screens()
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
	if not ui.get_viewport().disable_3d:
		p.append("the plant is still drawn behind the screens")
	if ui._toast.visible and ui._toast.text.contains("operations are offered"):
		p.append("the control room's word covers the screens just opened: %s" % ui._toast.text)
	App.find_button(ui.root, "Control room").pressed.emit()
	if ui.screens_open():
		p.append("the Control room button in the control room did not close the screens")
	if not ui.player.input_enabled:
		p.append("walking did not come back when the screens closed")
	if ui.get_viewport().disable_3d:
		p.append("the plant is not drawn again when the screens closed")
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
	var st_moving: Dictionary = mim.item_state(it, e, 0.10)       # it stood at 10 % at the last look
	if not st_moving.words.begins_with("OPENING"):
		p.append("a valve whose position rose since the last look is not shown opening: %s" % st_moving.words)
	var drive: Dictionary = sm.items["30PAC10AP001"]
	if drive.kind != "drive" or mim.item_state(drive, e).words != "STOPPED":
		p.append("CW pump A is not a stopped drive: %s %s" % [drive.kind, mim.item_state(drive, e).words])
	# alarms on the screen, its tab and the banner: instrument air compressor A started, then both lost
	ui.do_op({"kks": "00QFA10AN001", "do": "start"}, null)
	ui.clock.run_steps(1)
	if not App.run_until(ui, "ia_p_norm", 20000):
		p.append("instrument air did not come up")
	ui.fault("ia_lost")
	ui.clock.run_steps(50)
	var air: Dictionary = sm.items["00QFA10AN001"]
	var al: Array = sm.alarms_now(air, e)
	var want_p := 0
	for a in ui.model.alarms:
		if a.get("kks", a.get("where", "")) == "00QFA10AN001":
			want_p = int(a.get("priority", 0)) if want_p == 0 else mini(want_p, int(a.get("priority", 9)))
	if al.is_empty():
		p.append("the tripped compressor's alarm is not on its item")
	elif al[0][0] != want_p:
		p.append("the compressor's alarm shows priority %d, its alarms' highest is %d" % [al[0][0], want_p])
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
	for k in 30:                                     # what the screen drew, at its next redraws
		await tree.process_frame
	if mim.drawn.get("30PAC10AP001", "") != "RUNNING":
		p.append("the screen drew the running pump as %s" % mim.drawn.get("30PAC10AP001", "nothing"))
	# moving between items with the arrows
	var before: String = mim.selected
	mim.move_selection(Vector2.RIGHT)
	if mim.selected == before:
		mim.move_selection(Vector2.DOWN)
	if mim.selected == before:
		p.append("the arrows did not move the selection from %s" % before)
	# the overview: a tile per screen of this desk (PLANT3D §14: the main control room's); Enter on a tile opens it
	mim.show_screen(-1)
	var n_here: int = range(ui.screens.screens.size()).filter(func(i): return ui.screen_here(i)).size()
	if mim._targets().size() != n_here or n_here >= ui.screens.screens.size():
		p.append("the overview has %d tiles for this desk's %d screens (of %d)" % [mim._targets().size(), n_here,
				ui.screens.screens.size()])
	mim.activate("screen:2")
	if mim.current != 2:
		p.append("a tile did not open its screen")
	ui.close_card()
	ui.close_screens()
	return p


## What the adversarial review found (PR #222): the focus comes back to the screens when a panel over them closes,
## a valve's OPENING neither flickers nor shows at an end stop or after a restart, a long frame draws the screen once,
## flow labels and the sparkline's span stay off the groups and edges, the selection leaves a trip's red edge, "Show
## me" goes to the code on the screens, the stick moves once a push, a tap allows for the UI's scale and two fingers
## never tap, and the walking buttons leave the screens.
func _review(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var mim = ui.mimic
	var sm = ui.screens
	var e = ui.clock.engine
	ui.open_screens("cw")
	await tree.process_frame
	# the focus: a panel's button had it; the panel closes; the canvas has it again
	for panel in [["alarm list", ui.toggle_alarms, ui.close_alarms, ui.alarms], ["procedure", ui.toggle_procedure,
			ui.close_procedure, ui.procedure], ["card", func(): ui.open_card("30PAC10AP001"), ui.close_card, ui.card]]:
		(panel[1] as Callable).call()
		await tree.process_frame
		var b: Button = _first_button(panel[3])
		if b != null:
			b.grab_focus()
		(panel[2] as Callable).call()
		await tree.process_frame
		if not mim.canvas.has_focus():
			p.append("closing the %s over the screens left the canvas without the focus (%s has it)" % [panel[0],
					str(ui.get_viewport().gui_get_focus_owner())])
	# a valve: OPENING at each redraw while it moves, also two redraws in one step; its end stop said as it is
	var it: Dictionary = sm.items["30PAC10AA101"]
	var o: Dictionary = ui.model.op_keys[ui.model.op_key("30PAC10AA101", "set", null)]
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	ui.do_op(o, 0.9)
	ui.clock.run_steps(1)
	mim._valve_was(it, e)
	var words := []
	for k in 4:
		ui.clock.run_steps(3)
		words.append(mim.item_state(it, e, mim._valve_was(it, e)).words)
		words.append(mim.item_state(it, e, mim._valve_was(it, e)).words)     # a second redraw in the same step
	for w in words:
		if not String(w).begins_with("OPENING") and not String(w).begins_with("CLOSING"):
			p.append("a moving valve's words flicker between redraws: %s" % str(words))
			break
	ui.do_op(o, 1.0)
	for k in 400:
		if e.v(it.pos) > 0.99:
			break
		ui.clock.run_steps(50)
	if e.v(it.pos) <= 0.98 or mim.item_state(it, e, 0.5).words != "OPEN":
		p.append("a valve at its open stop (%.3f) is shown %s" % [e.v(it.pos), mim.item_state(it, e, 0.5).words])
	ui.do_op(o, 0.0)
	for k in 400:
		if e.v(it.pos) < 0.02:
			break
		ui.clock.run_steps(50)
	if e.v(it.pos) < 0.02 and mim.item_state(it, e, 0.5).words != "CLOSED":
		p.append("a valve at its closed stop is shown %s" % mim.item_state(it, e, 0.5).words)
	# after a restart (another engine) the last look of the old run is not compared with
	ui.do_op(o, 0.5)
	ui.clock.run_steps(200)
	mim._last_pos[it.code] = [0.0, e.step_no, 0.0, Time.get_ticks_msec()]
	mim._pos_engine = RefCounted.new()
	if mim.item_state(it, e, mim._valve_was(it, e)).moving:
		p.append("a valve is shown moving against a position from before the restart")
	# a long frame (a hitch, a resume): the next frames draw a few pieces each, not the whole screen again
	mim._process(60.0)
	var rr0: int = mim._rr
	mim._process(1.0 / 60.0)
	if mim._rr - rr0 > mim._pieces.size() / 4 + 1:
		p.append("after a long frame the next one drew %d of %d pieces" % [mim._rr - rr0, mim._pieces.size()])
	# flow labels on no group, the sparkline's span inside its tile
	for i in range(-1, sm.screens.size()):
		var L: Dictionary = mim._layout_of(i)
		for l in L.lines:
			if l[2] == "":
				continue
			var lr: Rect2 = mim.label_rect(mim.line_label(mim.line_points(l[0], l[1]), l[2]))
			for g in L.groups:
				if lr.intersects(g.rect):
					p.append("screen %d: the label %s at %s runs under the group %s" % [i, l[2], str(lr), g.title])
		for t in L.trends:
			var r: Rect2 = t[1]
			var plot := Rect2(r.position + Vector2(8, 26), r.size - Vector2(16, 34))
			if not r.encloses(Rect2(mim.spark_label_at(plot), Vector2(30, mim._font().get_height(11)))):
				p.append("a trend's span is written over its edge")
		for t in L["keys"]:
			var r: Rect2 = t[1]
			var plot := Rect2(r.position + Vector2(mim.PAD, 66), Vector2(r.size.x - mim.PAD * 2, r.size.y - 74))
			if not r.encloses(Rect2(mim.spark_label_at(plot), Vector2(30, mim._font().get_height(11)))):
				p.append("a key value's span is written over its tile's edge")
	# the selection's outline inside the trip's red edge
	var cr := Rect2(100, 100, 248, 90)
	if not cr.grow(-1.0).encloses(mim.select_rect(cr).grow(1.5)):
		p.append("the selection's outline covers a tripped item's red edge")
	# Show me on a card over the screens: the code's own screen, selected
	ui.open_screens("cw")
	ui.open_card("00PGC10AP001")
	ui.show_me("00PGC10AP001")
	if mim.current != sm.screen_index("aux") or mim.selected != "00PGC10AP001":
		p.append("Show me on the screens did not go to the code's screen (screen %d, %s)" % [mim.current, mim.selected])
	if ui.index.has("00PGC10AP001") and ui.pointer.code != "00PGC10AP001":
		p.append("Show me on the screens left the plant's pointer at %s (a procedure's step changes it there)" % ui.pointer.code)
	ui.close_card()
	# the stick: one move a push, however many events the push sends
	mim.select(mim._targets()[0].id)
	mim._canvas_input(_axis(JOY_AXIS_LEFT_X, 0.0))
	mim._canvas_input(_axis(JOY_AXIS_LEFT_X, 0.6))
	var s1: String = mim.selected
	for v in [0.8, 1.0, 0.9, 1.0, 0.55, 0.62, 0.45, 0.61]:     # and a wobble near the line while held
		mim._canvas_input(_axis(JOY_AXIS_LEFT_X, v))
	if mim.selected != s1:
		p.append("one push of the stick moved the selection more than once")
	mim._canvas_input(_axis(JOY_AXIS_LEFT_X, 0.0))
	# a tap at the phone's scale: a finger that moves a little still taps; two fingers never do
	var Wd = load("res://ui/widgets.gd")
	var s0: float = Wd.scale
	Wd.scale = 2.0
	ui.open_screens("cw")
	mim.select("30PAC10AP001")
	await tree.process_frame
	var at: Vector2 = mim.target_centre("30PAC10AP001")
	var press := func(down: bool, pos: Vector2) -> void:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = pos
		mim._canvas_input(ev)
	press.call(true, at)
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(18, 0)
	mv.position = at + mv.relative
	mim._canvas_input(mv)
	press.call(false, at + mv.relative)
	if not ui.card.visible:
		p.append("a tap that moved 18 px at scale 2 (9 px of the UI) did not open the card")
	ui.close_card()
	var touch := func(i: int, down: bool) -> void:
		var t := InputEventScreenTouch.new()
		t.index = i
		t.pressed = down
		t.position = at + Vector2(i * 60, 0)
		mim._canvas_input(t)
	touch.call(0, true)
	press.call(true, at)
	touch.call(1, true)
	touch.call(1, false)
	touch.call(0, false)
	press.call(false, at)
	if ui.card.visible:
		p.append("two fingers down and up opened a card")
		ui.close_card()
	Wd.scale = s0
	# the settings closed over the screens: the canvas has the focus again
	ui.main.hud.show_settings(true)
	await tree.process_frame
	ui.main.hud.show_settings(false)
	await tree.process_frame
	if not mim.canvas.has_focus():
		p.append("closing the settings over the screens left the canvas without the focus")
	# Acknowledge all in the alarm list: one sound
	var ks: Array = []
	for k in e._al.size():
		if e.shelved[k] == -1 and ks.size() < 3:
			ks.append(k)
	for k in ks:
		e.astate[k] = "active_unack"
	ui.sounds.played.clear()
	ui.alarms._ack_all()
	if ui.sounds.played.get("horn_ack", 0) != 1:
		p.append("Acknowledge all (%d alarms) played the acknowledge %d times" % [ks.size(), ui.sounds.played.get("horn_ack", 0)])
	# the walking buttons and the crosshair are not shown over the screens
	var hud = ui.main.hud
	var touch0 = ui.main.cf.get_value("controls", "touch", "auto")
	ui.main.cf.set_value("controls", "touch", "on")
	var mode0 = ui.main.player.mode
	ui.main.player.mode = Player.Mode.FLY
	hud.refresh()
	if hud.fly_btn.visible or hud.use_btn.visible:
		p.append("Fly or Use is shown over the screens")
	for b in hud.updown:
		if b.visible:
			p.append("the flying up and down buttons are shown over the screens")
			break
	ui.main.player.mode = mode0
	ui.main.cf.set_value("controls", "touch", touch0)
	hud.refresh()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		ui._look_hint()
		if ui._hint.text != "":
			p.append("the crosshair is shown over the screens: %s" % ui._hint.text)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.close_screens()
	return p


static func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).is_visible_in_tree() and (c as Button).focus_mode != Control.FOCUS_NONE:
			return c
		var b := _first_button(c)
		if b != null:
			return b
	return null
