## Operating the plant from equipment cards (docs/PLANT3D.md §7.2): an operation is offered only where the content
## says (at the equipment or from the control room), a refused one comes back with its failed permissives in the
## content's words, a value is typed and checked against its range, a trip is reset only once its cause has cleared,
## and an accepted start shows on the card and moves the pump's shaft.
extends RefCounted

const App = preload("res://tests/ui_app.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	ui.go_control_room()
	if not ui.in_control_room():
		p.append("Control room did not put the trainee in the control room")
	# 1. a local-only operation is not offered in the control room, and says where it is
	ui.open_card("00PGB10AC001")
	var row := App.op_row(ui.card, "00PGB10AC001", "open")
	if row.is_empty() or not (row[1] as Button).disabled or not (row[5] as Label).text.contains("At the equipment only"):
		p.append("the cooler's Open (local only) is offered in the control room, or doesn't say where it is")
	# 2. a start refused: the discharge valve is not at its start position (the content's sentence)
	ui.open_card("30PAC10AP001")
	row = App.op_row(ui.card, "30PAC10AP001", "start")
	if row.is_empty() or (row[1] as Button).disabled:
		p.append("CW pump A's Start is not offered in the control room")
		main.free()
		return p
	if not (row[2] as Label).text.contains("✗ Discharge valve 30PAC10AA101 not at its start position"):
		p.append("the card does not show the failing permissive before the start: %s" % (row[2] as Label).text)
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	var res: Dictionary = ui.op_result(row[0])
	if res.get("state", "") != "refused" or not String(res.get("text", "")).contains("not at its start position"):
		p.append("the start against a closed valve came back %s" % str(res))
	ui.card.refresh()
	if not (row[3] as Label).text.begins_with("Refused: Discharge valve"):
		p.append("the card does not say why the start was refused: %s" % (row[3] as Label).text)
	# 3. the gas turbine's start at cold iron: refused, every failed permissive named, in order
	ui.open_card("10MBA10")
	row = App.op_row(ui.card, "10MBA10", "start")
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	var txt: String = ui.op_result(row[0]).get("text", "")
	if not (txt.begins_with("Refused: Lube oil pressure below 1.8 bar; Turning gear not running") and txt.contains("No feedwater pump running")):
		p.append("the GT start at cold iron came back: %s" % txt)
	# 4. a trip's reset while its cause is still there (the steam turbine's lube oil is not running)
	ui.open_card("30MAV10CP001")
	row = App.op_row(ui.card, "30MAV10CP001", "reset", "st_trip_lube")
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	txt = ui.op_result(row[0]).get("text", "")
	if not txt.contains("cause of the trip is still there"):
		p.append("the lube oil trip's reset with no oil pressure came back: %s" % txt)
	# 5. a typed value: not a number, out of range, then the start position
	ui.open_card("30PAC10AA101")
	row = App.op_row(ui.card, "30PAC10AA101", "set")
	var entry: LineEdit = row[4]
	var n0: int = ui.clock.engine.inputs.size()
	entry.text = "fifteen"
	(row[1] as Button).pressed.emit()
	if ui.clock.engine.inputs.size() != n0:
		p.append("a value that is not a number was sent")
	entry.text = "150"
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	txt = ui.op_result(row[0]).get("text", "")
	if txt != "Refused: The value must be between 0 and 100 %":
		p.append("150 %% came back: %s" % txt)
	entry.text = "15"
	(row[1] as Button).pressed.emit()
	var last: Array = ui.clock.engine.inputs[ui.clock.engine.inputs.size() - 1]
	if var_to_str(last[4]) != var_to_str(0.15):
		p.append("15 %% was sent as %s, not 0.15" % var_to_str(last[4]))
	ui.clock.run_steps(1)
	if ui.op_result(row[0]).get("state", "") != "done":
		p.append("setting the valve to 15 %% came back %s" % str(ui.op_result(row[0])))
	# 6. the pump starts once the valve is at its start position; the card says it runs, the shaft turns
	if not App.run_until(ui, "cw_a_vstart", 2000):
		p.append("the valve did not reach its start position")
	ui.open_card("30PAC10AP001")
	row = App.op_row(ui.card, "30PAC10AP001", "start")
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	if ui.op_result(row[0]).get("state", "") != "done":
		p.append("the start at the start position came back %s" % str(ui.op_result(row[0])))
	App.run_until(ui, "cw_a_run", 200)
	ui.clock.run_steps(100)
	ui.card.refresh()
	if not ui.card._state.text.contains("Running"):
		p.append("the card does not say the pump runs: %s" % ui.card._state.text)
	var shaft: Node3D = ui.index.nodes["30PAC10AP001"].find_child("shaft", true, false)
	if shaft == null:
		p.append("no shaft (kit piece or placeholder) on CW pump A")
	else:
		var b0 := shaft.transform.basis
		ui.player.global_position = ui.index.center("30PAC10AP001") + Vector3(0, 0, 4)
		for i in 5:
			await tree.process_frame
		if shaft.transform.basis.is_equal_approx(b0):
			p.append("CW pump A's shaft does not turn while it runs")
	# 7. at the equipment its local controls are offered: the cooler from beside it
	ui.open_card("00PGB10AC001")
	App.find_button(ui.card, "Go there").pressed.emit()
	for i in 600:
		if not ui.player.scripted:
			break
		await tree.process_frame
	ui.card.refresh()
	row = App.op_row(ui.card, "00PGB10AC001", "open")
	if not ui.near("00PGB10AC001") or (row[1] as Button).disabled:
		p.append("beside the cooler (%.1f m) its Open is not offered" % ui.distance_to("00PGB10AC001"))
	main.free()
	return p
