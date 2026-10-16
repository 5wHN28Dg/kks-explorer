## Alarms through the alarm list (docs/PLANT3D.md §7.5–§7.6, §7.9): a trainer fault trips a pump; its alarm comes
## up unacknowledged, sounds the horn at its priority, flashes the Alarms button and stops fast-forward; the trip is
## listed as its group's first out; Ack makes it acknowledged and silences the horn; shelving moves it to the shelved
## list until it is un-shelved; alarms suppressed by design at cold iron are listed apart and never sound.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	var horns: Array = []
	ui.horn_changed.connect(func(pr): horns.append(pr))
	await tree.process_frame
	# suppressed by design at cold iron: listed apart, no horn
	ui.toggle_alarms()
	App.find_button(ui.alarms, "Suppressed (…").pressed.emit()
	if ui.alarms.entries("suppressed").is_empty() or not App.texts(ui.alarms.body).contains("Condenser pressure high"):
		p.append("the suppressed list at cold iron does not show the condenser pressure alarms")
	ui.close_alarms()
	# closed cooling water pump A runs; then the instructor fails its motor
	ui.go_control_room()
	ui.open_card("00PGC10AP001")
	(App.op_row(ui.card, "00PGC10AP001", "start")[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	App.run_until(ui, "ccw_flow_ok", 2000)
	ui.clock.run_steps(10)
	await tree.process_frame
	if not horns.is_empty() and horns[horns.size() - 1] != 0:
		p.append("the horn sounds before any alarm: %s" % str(horns))
	main.hud.show_settings(true)
	var inst := App.find_button(main.hud.extra, "Instructor mode: scenarios and trainer faults")
	inst.button_pressed = true
	main.hud.show_settings(false)
	if not ui.instructor:
		p.append("instructor mode did not turn on from the settings")
	main.cf.set_value("ui", "instructor", false)    # the settings file is the app's own: leave it as it was
	load("res://app/quality.gd").save(main.cf)
	App.find_button(ui.root, "Instructor").pressed.emit()
	var apply: Button = null
	for row in ui.trainer.body.get_children():
		if row is HBoxContainer and (row.get_child(0) as Label).text == "Closed cooling water pump A motor fails":
			apply = row.get_child(1)
	if apply == null:
		main.free()
		return p + ["the instructor's panel has no Apply for the CCW pump A motor fault"]
	apply.pressed.emit()
	ui.clock.run_steps(1)
	App.run_until(ui, "ccw_a_trip_latched", 100)
	var e = ui.clock.engine
	var k: int = e._al_ix["ccw_a_tripped"]
	for i in 20:
		if e.astate[k] != "normal":
			break
		ui.clock.run_steps(1)
	await tree.process_frame
	if e.astate[k] != "active_unack":
		p.append("the trip's alarm is %s, not active and unacknowledged" % e.astate[k])
	if horns.is_empty() or horns[horns.size() - 1] != 2:
		p.append("the horn did not sound at priority 2: %s" % str(horns))
	if not ui.clock.ff_blocked().contains("not acknowledged"):
		p.append("fast-forward is not blocked by the unacknowledged alarm: %s" % ui.clock.ff_blocked())
	# fast-forward stops by itself: a fresh alarm while running fast is checked in test_ui_clock
	ui.toggle_alarms()
	if not App.texts(ui.alarms.body).contains("Closed cooling water pump A tripped"):
		p.append("the alarm list does not show the pump's alarm")
	App.find_button(ui.alarms, "Trips (…").pressed.emit()
	if not App.texts(ui.alarms.body).contains("FIRST OUT"):
		p.append("the trips list does not mark the first out: %s" % App.texts(ui.alarms.body))
	App.find_button(ui.alarms, "Active (…").pressed.emit()
	var ack: Button = null
	var shelve: MenuButton = null
	for row in ui.alarms.body.get_children():
		if row is Container and App.texts(row).contains("Closed cooling water pump A tripped"):
			ack = App.find_button(row, "Ack")
			shelve = App.find_button(row, "Shelve") as MenuButton
	if ack == null or shelve == null:
		main.free()
		return p + ["the alarm's row has no Ack or Shelve"]
	ack.pressed.emit()
	ui.clock.run_steps(1)
	await tree.process_frame
	if e.astate[k] != "active_ack":
		p.append("after Ack the alarm is %s" % e.astate[k])
	if horns[horns.size() - 1] != 0:
		p.append("the horn did not stop on acknowledge: %s" % str(horns))
	# shelve for 10 min of plant time: off the active list, on the shelved one, back when un-shelved
	ui.alarms.refresh()
	for row in ui.alarms.body.get_children():
		if row is Container and App.texts(row).contains("Closed cooling water pump A tripped"):
			shelve = App.find_button(row, "Shelve") as MenuButton
	shelve.get_popup().id_pressed.emit(0)
	ui.clock.run_steps(1)
	if e.shelved[k] != e.step_no + 6000:     # made in this step, for 6000 steps
		p.append("the shelf ends at step %d, not 10 min after it was made" % e.shelved[k])
	if ui.alarms.entries("active").has(k) or not ui.alarms.entries("shelved").has(k):
		p.append("a shelved alarm is still on the active list or not on the shelved one")
	App.find_button(ui.alarms, "Shelved (…").pressed.emit()
	App.find_button(ui.alarms.body, "Un-shelve").pressed.emit()
	ui.clock.run_steps(1)
	if e.shelved[k] != -1 or not ui.alarms.entries("active").has(k):
		p.append("Un-shelve did not bring the alarm back")
	# an alarm still unacknowledged when its suppression began keeps that state (§7.6) and holds fast-forward back:
	# the suppressed list offers its Ack, Acknowledge all takes it, the reason names it
	var ks: int = ui.alarms.entries("suppressed")[0]
	e.astate[ks] = "active_unack"          # (the state the engine leaves it in when suppression starts while unacknowledged)
	var stext: String = ui.info.m.alarms[ks]["text"]
	if not ui.clock.ff_blocked().contains(stext):
		p.append("the fast-forward block does not name the suppressed alarm: %s" % ui.clock.ff_blocked())
	App.find_button(ui.alarms, "Suppressed (…").pressed.emit()
	if App.find_button(ui.alarms.body, "Ack") == null:
		p.append("the suppressed list offers no Ack for an unacknowledged alarm")
	App.find_button(ui.alarms, "Acknowledge all").pressed.emit()
	ui.clock.run_steps(1)
	if e.astate[ks] != "active_ack":
		p.append("Acknowledge all left the suppressed alarm %s" % e.astate[ks])
	main.free()
	return p
