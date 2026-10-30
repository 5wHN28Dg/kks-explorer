## The hoists in the app (docs/PLANT3D.md §20.5, §20.7): HRSG 1's roof hoist worked through a whole lift from its
## pendant's hold-to-run buttons (touch, mouse and a gamepad's accept: pressed sends 1 or -1, released 0), the
## motions offered only within reach of the pendant and the hook's latch only at the hook, a motion let go when its
## card closes, the moving pieces and the codes riding on them drawn at the model's values between its steps; and the
## turbine hall's crane worked through its procedure from its pendant (which travels with the bridge) and its radio
## remote, the procedure ending with no deviation (a button let go is never one).
extends RefCounted

const App = preload("res://tests/ui_app.gd")

var p: Array = []
var tree: SceneTree


static func gd(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


func run(t: SceneTree) -> Array:
	tree = t
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	await _roof(ui)
	await _crane(ui)
	main.free()
	return p


func _stand(ui, at: Vector3) -> void:
	ui.player.global_position = at
	ui.player.velocity = Vector3.ZERO
	await tree.process_frame
	await tree.process_frame
	ui.card.refresh()


func _row(ui, code: String) -> Array:
	var pd = ui.card._pendant
	if pd == null:
		return []
	for r in pd.rows:
		if r[0].get("code", "") == code:
			return r
	return []


func _last(ui) -> Array:
	var ins: Array = ui.clock.engine.inputs
	return ins[ins.size() - 1] if not ins.is_empty() else []


## Holds a row's button through one model step and returns the value sent ("" when nothing was).
func _sent(ui, n0: int) -> String:
	var ins: Array = ui.clock.engine.inputs
	return var_to_str(ins[ins.size() - 1][4]) if ins.size() > n0 else ""


func _roof(ui) -> void:
	var e = ui.clock.engine
	# far from the pendant (the control room): the card shows the pendant, its motions not offered
	ui.go_control_room(false)
	ui.open_card("10SMF10")
	var out := _row(ui, "10SMF10AE002")
	if out.is_empty():
		p.append("the roof hoist's card has no pendant row for its trolley")
		return
	if not (out[2] as Button).disabled:
		p.append("the roof hoist's trolley buttons are offered from the control room")
	# the trolley's own card sends the trainee to the pendant and offers no typed value
	ui.open_card("10SMF10AE002")
	if not App.texts(ui.card).contains("Worked from the pendant of 10SMF10") or not ui.card._ops.is_empty():
		p.append("the trolley drive's own card does not send the trainee to the pendant: %s" % App.texts(ui.card))
	# at the pendant station on the roof
	await _stand(ui, gd(123.0, 71.0, 30.05))
	ui.open_card("10SMF10")
	out = _row(ui, "10SMF10AE002")
	if (out[2] as Button).disabled:
		p.append("the trolley's Out is not offered at the pendant (%s)" % ui.card._pendant._where.text)
	var latch := _row(ui, "10SMF10AE003")
	# 1. Out, by touch: pressed sends -1, released 0
	var n0: int = e.inputs.size()
	(out[2] as Button).button_down.emit()
	if _sent(ui, n0) != "-1":
		p.append("pressing Out sent %s, not -1" % _sent(ui, n0))
	var trolley: Node3D = ui.index.nodes["10SMF10"].find_child("trolley", true, false)
	var t0: Vector3 = trolley.global_position
	var unit_at: Vector3 = ui.index.nodes["10SMF10AE002"].global_position
	if not App.run_until(ui, "roof_hoist_at_tip", 600):
		p.append("the trolley did not reach the beam's tip")
	await tree.process_frame
	(out[2] as Button).button_up.emit()
	if _sent(ui, n0) != "0":
		p.append("letting Out go sent %s, not 0" % _sent(ui, n0))
	ui.clock.run_steps(1)
	await tree.process_frame
	var moved := trolley.global_position - t0
	if absf(moved.z + 7.5) > 0.05 or absf(moved.x) > 0.01 or absf(moved.y) > 0.01:     # (Godot's -z is north)
		p.append("the trolley is drawn %s from where it stood, not 7.5 m north" % str(moved))
	var um: Vector3 = ui.index.nodes["10SMF10AE002"].global_position - unit_at
	if um.distance_to(moved) > 0.01:
		p.append("the trolley's drive (its code) did not ride with it: %s against %s" % [str(um), str(moved)])
	# 2. Down, by a gamepad's accept on the focused button: pressed, then released
	var down: Button = _row(ui, "10SMF10AE001")[2]
	down.grab_focus()
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	n0 = e.inputs.size()
	tree.root.push_input(ev)
	await tree.process_frame
	if _sent(ui, n0) != "-1":
		p.append("a gamepad's accept on Down sent %s, not -1" % _sent(ui, n0))
	ui.clock.run_steps(20)
	var hook: Node3D = ui.index.nodes["10SMF10"].find_child("hook", true, false)
	var k: int = e.ix["roof_hoist_hook_height"]
	ui.clock.acc = ui.clock.STEP * 0.5
	ui.bindings._each_slide()
	var want := lerpf(e.prev[k], e.cur[k], 0.5)
	if absf(hook.global_position.y - want) > 0.002 or e.prev[k] == e.cur[k]:
		p.append("the hook is drawn at %.4f m, not half way between the last two steps (%.4f, %.4f)" % [hook.global_position.y, e.prev[k], e.cur[k]])
	ui.clock.acc = 0.0
	if not App.run_until(ui, "roof_hoist_at_load", 5000):
		p.append("the hook did not come down to the valve's slings")
	ev = InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = false
	n0 = e.inputs.size()
	tree.root.push_input(ev)
	await tree.process_frame
	if _sent(ui, n0) != "0":
		p.append("letting a gamepad's accept go sent %s, not 0" % _sent(ui, n0))
	ui.clock.run_steps(1)
	# 3. the latch at the hook, at grade in the drop zone; the motions are out of reach there
	await _stand(ui, gd(125.0, 80.5, 0.05))
	latch = _row(ui, "10SMF10AE003")
	if (latch[3] as Button).disabled or not (_row(ui, "10SMF10AE001")[3] as Button).disabled:
		p.append("at the hook: the latch is not offered, or the motions are (from grade)")
	(latch[3] as Button).pressed.emit()
	ui.clock.run_steps(1)
	if not e.truth("roof_hoist_latch"):
		p.append("Hook on at the slings did not close the latch: %s" % str(ui.op_result(latch[7])))
	# 4. back at the pendant, the hook 30 m below: its latch is not offered there; Up by the mouse, until the valve
	#    clears the roof's handrail
	await _stand(ui, gd(123.0, 71.0, 30.05))
	if not (_row(ui, "10SMF10AE003")[3] as Button).disabled:
		p.append("the hook's latch is offered at the pendant, 30 m above the hook")
	var up: Button = _row(ui, "10SMF10AE001")[3]
	await _in_view(up)
	n0 = e.inputs.size()
	_mouse(up, true)
	await tree.process_frame
	if _sent(ui, n0) != "1":
		var hov = tree.root.gui_get_hovered_control()
		p.append("pressing Up with the mouse sent %s, not 1 (under the pointer: %s)" % [_sent(ui, n0), str(hov.get_path()) if hov else "nothing"])
	if not App.run_until(ui, "roof_hoist_clear", 5000):
		p.append("the valve was not hoisted clear of the roof's handrail")
	_mouse(up, false)
	await tree.process_frame
	if _sent(ui, n0) != "0":
		p.append("letting the mouse go on Up sent %s, not 0" % _sent(ui, n0))
	# 5. In, then Down onto the roof
	var inb: Button = _row(ui, "10SMF10AE002")[3]
	inb.button_down.emit()
	if not App.run_until(ui, "roof_hoist_at_landing", 1000):
		p.append("the trolley did not bring the valve in over the roof")
	inb.button_up.emit()
	down.button_down.emit()
	if not App.run_until(ui, "roof_hoist_rest", 1000):
		p.append("the valve was not set down on the roof")
	down.button_up.emit()
	ui.clock.run_steps(2)
	await tree.process_frame
	var ld: Node3D = ui.index.nodes["10SMF10"].find_child("load_z", true, false)
	if ld == null or ld.global_position.distance_to(gd(125.0, 79.0 - e.v("roof_hoist_load_along"), 30.0)) > 0.02:
		p.append("the valve is not drawn on the roof where the model has it: %s" % (str(ld.global_position) if ld else "no load piece"))
	# 6. unhook at the hook (on the roof beside it), then a motion held while the card closes stops
	await _stand(ui, gd(125.5, 72.0, 30.05))
	latch = _row(ui, "10SMF10AE003")
	(latch[2] as Button).pressed.emit()
	ui.clock.run_steps(1)
	if e.truth("roof_hoist_latch"):
		p.append("Unhook with the valve resting did not open the latch: %s" % str(ui.op_result(latch[6])))
	await _stand(ui, gd(123.0, 71.0, 30.05))
	(_row(ui, "10SMF10AE001")[3] as Button).button_down.emit()
	ui.clock.run_steps(5)
	ui.close_card()
	ui.clock.run_steps(2)
	if e.v("roof_hoist_hoist_cmd") != 0.0:
		p.append("closing the card with Up held left the hoist running (%s)" % e.v("roof_hoist_hoist_cmd"))
	# 7. touch: a finger on the button and off it (the mouse emulated from touch, as on a phone)
	ui.open_card("10SMF10")
	await tree.process_frame
	await tree.process_frame
	var dn: Button = _row(ui, "10SMF10AE001")[2]
	await _in_view(dn)
	n0 = e.inputs.size()
	_touch(dn, true)
	await tree.process_frame
	var touched := _sent(ui, n0)
	_touch(dn, false)
	await tree.process_frame
	if touched != "-1" or _sent(ui, n0) != "0":
		p.append("a touch on Down sent %s, then %s (not -1, then 0)" % [touched, _sent(ui, n0)])
	ui.close_card()


## Scrolls the card so that the button is on screen (a press goes to what is under the pointer).
func _in_view(b: Button) -> void:
	var c: Node = b.get_parent()
	while c != null and not c is ScrollContainer:
		c = c.get_parent()
	if c != null:
		(c as ScrollContainer).ensure_control_visible(b)
	await tree.process_frame
	await tree.process_frame
	if not tree.root.get_visible_rect().encloses(b.get_global_rect()):
		p.append("the button %s is not on screen (%s in %s)" % [b.text, str(b.get_global_rect()), str(tree.root.get_visible_rect())])


func _mouse(b: Button, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = b.get_global_rect().get_center()
	ev.global_position = ev.position
	tree.root.push_input(ev, true)      # (at the canvas's own coordinates: the window may be scaled)


func _touch(b: Button, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = down
	ev.position = tree.root.get_screen_transform() * b.get_global_rect().get_center()   # (the window's pixels)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## The crane worked through its procedure: from the pendant, which travels with the bridge, and the radio remote
## near the hook; the hook's latch at the hook.
func _crane(ui) -> void:
	ui.start_procedure("crane_lift", null, true)
	var e = ui.clock.engine
	ui.clock.set_speed(ui.clock.Speed.PAUSED)
	ui.open_card("30SMT10")
	await tree.process_frame
	if _row(ui, "30SMT10AE003").is_empty():
		p.append("the crane's card has no pendant")
		return
	# [step, the row, minus (-1) or plus (1), where to stand ("pendant", "remote", "hook"), done]
	for s in [["travel_east", "30SMT10AE003", 1, "pendant", "crane_at_laydown"],
			["trolley_south", "30SMT10AE002", -1, "pendant", "crane_south"],
			["lower", "30SMT10AE001", -1, "pendant", "crane_at_load"],
			["hook_on", "30SMT10AE004", 1, "hook", "crane_latch"],
			["hoist", "30SMT10AE001", 1, "remote", "crane_clear"],
			["trolley_north", "30SMT10AE002", 1, "remote", "crane_north"],
			["travel_west", "30SMT10AE003", -1, "pendant", "crane_west"],
			["lower_floor", "30SMT10AE001", -1, "pendant", "crane_rest"],
			["unhook", "30SMT10AE004", -1, "hook", "crane_free"],
			["clear", "30SMT10AE001", 1, "pendant", "crane_hook_clear"]]:
		if ui.tracker.current().get("id", "") != s[0]:
			p.append("the crane's procedure is at %s, not %s" % [ui.tracker.current().get("id", "(ended)"), s[0]])
			return
		var bx: float = e.v("crane_bridge_pos")
		match s[3]:
			"pendant":     # under the pendant, on the operating floor's south side: it hangs from the bridge
				await _stand(ui, gd(bx - 1.5, -17.4, 12.05))
			"remote":      # at grade by the laydown bay, the hook in sight
				await _stand(ui, gd(74.0, -23.5, 0.05))
			"hook":
				var h: Vector3 = ui.index.nodes["30SMT10AE004"].global_position
				await _stand(ui, gd(h.x + 1.5, -h.z + (1.5 if -h.z < -20.0 else 1.0), 12.05 if h.y > 11.0 else 0.05))
		var r := _row(ui, s[1])
		var b: Button = r[2] if s[2] < 0 else r[3]
		if b.disabled:
			p.append("step %s: %s is not offered (%s; %s)" % [s[0], b.text, s[3], ui.card._pendant._where.text])
			return
		if s[3] == "remote" and ui.card._pendant.reach() != "remote":
			p.append("step %s: worked from %s, not the radio remote" % [s[0], ui.card._pendant.reach()])
		if r[1]:
			b.button_down.emit()
		else:
			b.pressed.emit()
		if not App.run_until(ui, s[4], 20000):
			p.append("step %s: %s did not come" % [s[0], s[4]])
			return
		ui.clock.run_steps(1)
		if r[1]:
			b.button_up.emit()
		ui.clock.run_steps(1)
		await tree.process_frame
	if not ui.tracker.finished():
		p.append("the crane's procedure did not finish (at %s)" % ui.tracker.current().get("id", ""))
	if not ui.tracker.deviations.is_empty():
		p.append("the crane's procedure noted deviations: %s" % str(ui.tracker.deviations.map(func(d): return d[1])))
	var crate: Node3D = ui.index.nodes["30SMT10"].find_child("load_z", true, false)
	if crate.global_position.distance_to(gd(e.v("crane_load_x"), e.v("crane_load_y"), 12.0)) > 0.02:
		p.append("the crate is not drawn on the operating floor where the model has it: %s" % str(crate.global_position))
	ui.stop_procedure()
	ui.close_card()
