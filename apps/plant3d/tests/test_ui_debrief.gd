## The debrief (docs/PLANT3D.md §7.6 and §8, ui/debrief.gd): a trainee starts the cold start, does step 1's operation
## and, deliberately, step 4's as well (a deviation); does step 2; then the instructor fails the running pump: its
## trip (first out), its alarm (acknowledged, then shelved). The debrief, opened from the alarm list's Events button,
## lists all of it in order with model times, marks the deviation with the step it was made in and the one it belongs
## to, and sums it up; its tabs narrow the list; keyboard and gamepad reach its rows and open a row's equipment; it
## follows the run without rebuilding its rows. (The debrief at the end of a whole procedure: test_ui_cold_start.)
extends RefCounted

const App = preload("res://tests/ui_app.gd")


static func op(ui, kks: String, do: String, value = null) -> void:
	ui.do_op(ui.model.op_keys[ui.model.op_key(kks, do, null)], value)


static func rows(panel) -> Array:
	return panel._list.get_children().map(func(b): return (b as Button).text)


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	ui.start_procedure("cold_start")
	if ui.tracker == null or ui.tracker.index != 0:
		main.free()
		return ["the cold start did not begin at its first step"]
	# step 1: the instrument air compressor, and the basin make-up's automatic (step 4's) too early
	ui.go_control_room()
	op(ui, "00QFA10AN001", "start")
	op(ui, "30PAR10AA001", "auto")
	App.run_until(ui, "ia_p_norm", 20000)
	ui.clock.run_steps(2)
	if ui.tracker.index != 1:
		p.append("step 1 did not end (at step %d)" % (ui.tracker.index + 1))
	if ui.tracker.deviations.size() != 1:
		p.append("the early operation is not one deviation: %s" % str(ui.tracker.deviations))
	# step 2: the closed cooling water pump; then the instructor fails it
	op(ui, "00PGC10AP001", "start")
	App.run_until(ui, "ccw_flow_ok", 4000)
	ui.clock.run_steps(10)
	ui.fault("ccw_a_motor")
	ui.clock.run_steps(1)
	App.run_until(ui, "ccw_a_trip_latched", 100)
	var e = ui.clock.engine
	var k: int = e._al_ix["ccw_a_tripped"]
	for i in 30:
		if e.astate[k] != "normal":
			break
		ui.clock.run_steps(1)
	ui.ack("ccw_a_tripped")
	ui.clock.run_steps(1)
	ui.shelve("ccw_a_tripped", 600)
	ui.clock.run_steps(1)
	await tree.process_frame
	# from the alarm list
	ui.toggle_alarms()
	var ev_btn := App.find_button(ui.alarms, "Events")
	if ev_btn == null:
		main.free()
		return p + ["the alarm list has no Events button"]
	ev_btn.pressed.emit()
	var d = ui.debrief
	if not d.visible or ui.alarms.visible:
		p.append("Events did not open the debrief in the alarm list's place")
	var all := rows(d)
	var txt := "\n".join(all)
	var want := ["Began: Cold start", "00QFA10AN001 Start", "30PAR10AA001 Auto",
		"DEVIATION in step 1 of 44: this belongs to step 4", "Step 1 of 44 done", "00PGC10AP001 Start",
		"Step 2 of 44 done", "Fault: Closed cooling water pump A motor fails", "TRIP: ", "(first out)",
		"Alarm raised: — 00PGC10AP001 Closed cooling water pump A tripped",
		"Alarm acknowledged: — 00PGC10AP001", "Alarm shelved for 0:10:00"]
	var at := -1
	for w in want:
		var i := -1
		for r in all.size():
			if all[r].contains(w):
				i = r
				break
		if i == -1:
			p.append("the debrief does not list \"%s\":\n%s" % [w, txt])
			break
		if i < at and not w.begins_with("(") and not w.begins_with("DEVIATION"):
			p.append("\"%s\" is listed before what came first" % w)
		at = maxi(at, i)
	for r in all:
		if not RegEx.create_from_string("^\\d+:\\d\\d:\\d\\d  ").search(r):
			p.append("a row without its model time: %s" % r)
			break
	# the deviation is on the early operation's own row
	for r in all:
		if r.contains("DEVIATION") and not r.contains("30PAR10AA001 Auto"):
			p.append("the deviation is not on its operation's row: %s" % r)
	var sm: String = d._summary.text
	for w in ["Time: ", "Steps: 2 of 44 done so far", "Operations: 3 done; 1 outside their step",
			"Alarms: 1 raised (priority 2: 1), 1 acknowledged, 1 shelved", "Trips: 1 (first out: ", "Trainer's faults: 1"]:
		if not sm.contains(w):
			p.append("the summary does not say \"%s\": %s" % [w, sm])
	# the tabs
	App.find_button(d, "Deviations").pressed.emit()
	if rows(d).size() != 1 or not rows(d)[0].contains("DEVIATION"):
		p.append("Deviations lists %s" % str(rows(d)))
	App.find_button(d, "Alarms and trips").pressed.emit()
	var al := rows(d)
	if al.size() < 4 or al.any(func(r): return r.contains(" Start") or r.contains("Step ")):
		p.append("Alarms and trips lists %s" % str(al))
	App.find_button(d, "Everything").pressed.emit()
	# keyboard and gamepad: the panel has the focus; down reaches the rows; accept on a row opens its equipment
	var fo: Control = d.get_viewport().gui_get_focus_owner()
	if ui.wants_focus() and (fo == null or not d.is_ancestor_of(fo)):
		p.append("the debrief did not take the focus")
	d._list.get_child(0).grab_focus()
	await tree.process_frame
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	tree.root.push_input(down)
	await tree.process_frame
	fo = d.get_viewport().gui_get_focus_owner()
	if fo == null or fo.get_parent() != d._list or fo.get_index() != 1:
		p.append("ui_down did not move to the next row (focus on %s)" % str(fo))
	for b in d._list.get_children():
		if (b as Button).text.contains("00PGC10AP001 Start"):
			b.grab_focus()
	var acc := InputEventAction.new()
	acc.action = "ui_accept"
	acc.pressed = true
	tree.root.push_input(acc)
	await tree.process_frame
	var rel := InputEventAction.new()
	rel.action = "ui_accept"
	rel.pressed = false
	tree.root.push_input(rel)
	await tree.process_frame
	if not ui.card.visible or ui.card.code != "00PGC10AP001":
		p.append("accepting a row did not open its equipment's card")
	# it follows the run: new rows are added under the old ones, not made again
	ui.open_debrief()
	var first: Node = d._list.get_child(0)
	var n0: int = d._list.get_child_count()
	ui.unshelve("ccw_a_tripped")
	ui.clock.run_steps(1)
	d.refresh()
	if d._list.get_child_count() <= n0 or d._list.get_child(0) != first:
		p.append("the debrief did not add the new event below the others (%d rows, was %d)" % [d._list.get_child_count(), n0])
	elif not (d._list.get_child(d._list.get_child_count() - 1) as Button).text.contains("back from the shelf"):
		p.append("the new last row is %s" % (d._list.get_child(d._list.get_child_count() - 1) as Button).text)
	# Esc (gamepad B) closes it
	ui.close_top()
	if d.visible:
		p.append("closing the top panel left the debrief open")
	# stopped half way: the procedure's debrief ends there; what the trainee does afterwards is not in it
	ui.stop_procedure()
	op(ui, "30PAD10AN001", "start")
	ui.clock.run_steps(5)
	ui.open_debrief()
	var after := "\n".join(rows(d))
	if after.contains("30PAD10AN001") or not after.contains("Stopped at step 3 of 44") \
			or not d._summary.text.contains("Steps: 2 of 44 done, then stopped"):
		p.append("after Stop the debrief is not the procedure's run up to there: %s\n%s" % [d._summary.text, after])
	# a tour taken then does not replace the procedure's debrief, while it runs or after
	for id in ui.model.procedures:
		if ui.model.procedures[id].get("kind", "") == "tour":
			ui.start_procedure(id)
			break
	ui.open_debrief()
	if not d.title.text.begins_with("Debrief: Cold start"):
		p.append("during a tour the debrief is not the procedure's: %s" % d.title.text)
	ui.stop_procedure()
	ui.open_debrief()
	if not d.title.text.begins_with("Debrief: Cold start"):
		p.append("a tour replaced the procedure's debrief: %s" % d.title.text)
	# begun part-way (as a link can) and stopped: the step it stopped at, and the summary says where it began;
	# the open panel follows the new run without waiting for an event
	ui.start_procedure("cold_start", "ccw_cooler")
	if not d.visible or not d.title.text.begins_with("Debrief: Cold start"):
		p.append("the debrief closed or changed when a procedure began")
	ui.stop_procedure()
	var part := "\n".join(rows(d))
	if not part.contains("Stopped at step 3 of 44") or not d._summary.text.contains("Steps: 0 of 44 done (began at step 3), then stopped"):
		p.append("a run begun at step 3 and stopped: %s\n%s" % [d._summary.text, part])
	main.free()
	return p
