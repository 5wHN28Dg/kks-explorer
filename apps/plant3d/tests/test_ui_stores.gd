## The stores in the app (docs/plant3d/REALISM.md §7.2, §2.23; milestone WM2):
## - the catalogue's shelves: by class, a part's look-alike beside it (the condenser transmitters' range 3 and 4);
##   the number as written found whatever its case and spaces round it; a jump to a delivery's clock as [HH:MM, days];
##   the jump's rule in words, as the engine's (in a scenario with `world`, §7.4's amendment);
## - in the realism vectors' stores plant (run 7, the fitting replayed): the fitting's refusals in words (`part` names
##   the part to draw, `wrong_part` gives the look-alike's sentence) and the debrief's parts drawn per work and the
##   look-alike offered;
## - in the aged plant in free mode: the work order panel's "Stores" and an order's form with its issued parts (none)
##   and "Draw parts for it at the counter"; the counter's issue form on that order: a number not in the catalogue and
##   a quantity that is not a number refused on the form, the part drawn (the shelf down by one, the order's form lists
##   it), more than is on the shelf refused in words; the catalogue (the look-alikes side by side, a part's levels); a
##   part ordered from its order form (PO-0001, due by its lead time: the deliveries list it, and the jump to it is
##   offered); the debrief's parts; a jump with days through the input path;
## - a person played (on duty, not a storekeeper) away from the counter: the issue form sends them to the counter.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Stores = preload("res://ui/stores_panel.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const PlantEngine = preload("res://sim/engine.gd")
const JsonStrict = preload("res://sim/json_strict.gd")
const Debrief = preload("res://ui/debrief.gd")

const MOTOR := "00PGC10AP001"         # closed cooling water pump A's motor
const DAY := 864000


func run(tree: SceneTree) -> Array:
	var p: Array = _jumps()
	p += _fitting()
	p += await _panel(tree)
	return p


## An engine's clock for jump_to.
class Clk extends RefCounted:
	var c := 0
	func clock() -> int:
		return c


func _jumps() -> Array:
	var p: Array = []
	var e := Clk.new()
	e.c = 2 * DAY + 7 * 36000 + 30 * 600            # day 2 07:30
	# [the clock to reach, the jump]: the next HH:MM after now, then days on (30 at most); none to the past
	for x in [[2 * DAY + 8 * 36000, ["08:00", 0]], [3 * DAY + 7 * 36000, ["07:00", 0]],
			[3 * DAY + 7 * 36000 + 15, ["07:01", 0]], [2 * DAY + 7 * 36000, []], [20 * DAY, ["00:00", 17]],
			[32 * DAY + 7 * 36000 + 30 * 600, ["07:30", 29]], [33 * DAY + 7 * 36000 + 30 * 600, ["07:30", 30]],
			[34 * DAY + 7 * 36000 + 30 * 600, []], [44 * DAY + 7 * 36000 + 30 * 600, []]]:
		var got := Stores.jump_to(e, x[0])
		if got != x[1]:
			p.append("the jump to clock %d from day 2 07:30: %s, wanted %s" % [x[0], str(got), str(x[1])])
	return p


## The realism vectors' stores plant, run 7 (the fitting) replayed to its end: what the work view and the debrief say.
func _fitting() -> Array:
	var p: Array = []
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/plant3d-realism.json").simplify_path()
	var S: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value["stores"]
	var run: Dictionary = S["runs"][7]
	var files: Dictionary = S["files"].duplicate()
	files["scenarios/s1.json"] = run["scenario"]
	if run["staff"] != null:
		files["staff.json"] = run["staff"]
	var m = PlantModel.from_files(files)
	if m.error != "":
		return ["the realism stores plant did not load: " + m.error]
	var e = PlantEngine.new(m, "s1")
	var x: Dictionary = m.hands_ix["10LAB10CP501|fit_tx"]
	var i := 0
	var inputs: Array = run["inputs"]
	var said := {}
	while e.step_no < int(run["until"]):
		while i < inputs.size() and inputs[i][0] == e.step_no + 1:
			e.apply_input(inputs[i])
			i += 1
		var n0: int = e.events.size()
		e.step()
		for k in range(n0, e.events.size()):
			var ev: Array = e.events[k]
			if ev[1] == "hand" and ev[6] == "refused":
				for r in ev[7]:
					if r == "part" or r == "wrong_part":
						said[r] = Stores.fit_reason(e, x, r)     # (as the work view says it, at that step)
	if not said.get("part", "").contains("WDP-PT-UNIT-A3") or not said.get("part", "").contains("store counter"):
		p.append("the fitting without its part: %s" % said.get("part", "(not said)"))
	var want: String = m.stores["differs"]["tx_r3|tx_r4"]
	if said.get("wrong_part", "") != want:
		p.append("the look-alike offered: %s, wanted its sentence %s" % [said.get("wrong_part", "(not said)"), want])
	if Stores.fitting_words(e, x) == "" or not Stores.fitting_words(e, x).contains("WDP-PT-UNIT-A3"):
		p.append("the work view does not name the fitting's part: %s" % Stores.fitting_words(e, x))
	var lines := Stores.debrief_lines(e, e.events.size())
	var all := "\n".join(lines)
	if not all.contains("Parts drawn for") or not all.contains("1 × WDP-PT-UNIT-A4") \
			or not all.contains("1 × WDP-PT-UNIT-A3"):
		p.append("the debrief's parts drawn: %s" % all)
	var offered := 0
	for l in lines:
		if l.begins_with("A look-alike offered") and l.contains("WDP-PT-UNIT-A4 offered for WDP-PT-UNIT-A3") \
				and l.contains(want):
			offered += 1
	if offered != 2:        # (twice: before the range 3 was drawn, and again with only the look-alike left)
		p.append("the debrief's look-alikes offered (%d, wanted 2): %s" % [offered, all])
	return p


static func _press(n: Node, name: String) -> bool:
	var b = n.find_child(name, true, false)
	if b == null or not b is Button or (b as Button).disabled:
		return false
	(b as Button).pressed.emit()
	return true


static func _fresh(wp) -> void:
	wp._sig = ""
	wp.refresh()


func _panel(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_aged"):
		main.free()
		return ["the app or its aged scenario (shift_aged) did not start"]
	ui.player.set_physics_process(false)
	var sc: Dictionary = ui.model.scenarios["shift_aged"].duplicate(true)
	sc["id"] = "test_stores"
	sc["start"] = {"day": 1, "time": "06:30"}
	ui.model.scenarios["test_stores"] = sc
	ui.start_shift("test_stores")
	await tree.process_frame
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var sp = ui.stores
	if ui.me() != null or e._sr == null or not sp.available():
		main.free()
		return ["the run should be in free mode with stores.json (me %s)" % str(ui.me())]
	# the shelves: the condenser transmitters' range 3 and its look-alike side by side
	var sh: Array = Stores.shelves(e)
	var pt: Array = []
	for s in sh:
		if s[0] == "Pressure transmitter":
			pt = s[1]
	if pt.size() < 2 or pt[0] != "pt_unit_a3" or pt[1] != "pt_unit_a4":
		p.append("the transmitters' shelf: %s" % str(pt))
	if Stores.part_by_number(e, "  wdp-pt-unit-a3 ") != "pt_unit_a3" or Stores.part_by_number(e, "WDP-PT-UNIT-A9") != "":
		p.append("a catalogue number as written was not found as it should be")
	# a work order on the motor, planned: its form offers the counter
	var wp = ui.work_orders
	wp.open_for_code(MOTOR)
	wp.report(MOTOR, "vibration")
	ui.clock.run_steps(2)
	var wid: String = wp.work_for(e, MOTOR, "vibration")["id"]
	ui.inputs.work_order(wid, "plan", null, [3])
	ui.clock.run_steps(2)
	ui.open_work_orders()
	await tree.process_frame
	if wp.body.find_child("to_stores", true, false) == null:
		p.append("the work order list has no Stores")
	ui.open_work_orders(wid)
	await tree.process_frame
	var il: Label = wp.body.find_child("issued", true, false)
	if il == null or not il.text.ends_with("none"):
		p.append("the order's form does not say it has no parts: %s" % (il.text if il != null else "(no line)"))
	if not _press(wp.body, "to_counter"):
		main.free()
		return p + ["the planned order's form has no Draw parts at the counter"]
	await tree.process_frame
	if not sp.visible or sp.view != "issue" or wp.visible:
		p.append("Draw parts did not open the counter's form (stores %s, view %s)" % [str(sp.visible), sp.view])
	if sp.work_pick == null or sp.work_pick.selected < 0 or sp._work_ids[sp.work_pick.selected] != wid:
		p.append("the counter's form is not on the order's work")
	# a number not in the catalogue, a quantity that is not a number: refused on the form, nothing sent
	var n0: int = e.inputs.size()
	sp.number_edit.text = "WDP-NOTHING-9"
	_press(sp.body, "issue_send")
	if not sp.last_text.begins_with("No part numbered WDP-NOTHING-9"):
		p.append("a number not in the catalogue: %s" % sp.last_text)
	sp.number_edit.text = "wdp-pt-ferrules"
	sp.qty_edit.text = "ten"
	_press(sp.body, "issue_send")
	if not sp.last_text.begins_with("Write the quantity"):
		p.append("a quantity that is not a number: %s" % sp.last_text)
	if e.inputs.size() != n0:
		p.append("a request refused on the form was sent: %s" % str(e.inputs.slice(n0)))
	# drawn: the shelf down by ten, the order holds them
	var before: int = Stores.stock_of(e, "pt_ferrules")
	sp.qty_edit.text = "10"
	_press(sp.body, "issue_send")
	ui.clock.run_steps(2)
	await tree.process_frame
	if Stores.stock_of(e, "pt_ferrules") != before - 10 or not sp.last_text.begins_with("Issued: 10 × WDP-PT-FERRULES"):
		p.append("the ferrules not issued: stock %d of %d, %s" % [Stores.stock_of(e, "pt_ferrules"), before, sp.last_text])
	_fresh(sp)
	var issued: Label = sp.body.find_child("issued", true, false)
	if issued == null or not issued.text.contains("10 × WDP-PT-FERRULES"):
		p.append("the counter's form does not list what the order holds")
	# more than is on the shelf: refused, in words
	sp.number_edit.text = "WDP-PT-SENSOR-MODULE"
	sp.qty_edit.text = "5"
	_press(sp.body, "issue_send")
	ui.clock.run_steps(2)
	await tree.process_frame
	if not sp.last_text.contains("refused") or not sp.last_text.contains("only 1 on the shelf"):
		p.append("more than on the shelf: %s" % sp.last_text)
	ui.open_work_orders(wid)
	await tree.process_frame
	il = wp.body.find_child("issued", true, false)
	if il == null or not il.text.contains("10 × WDP-PT-FERRULES"):
		p.append("the order's form does not list its issued parts: %s" % (il.text if il != null else "(no line)"))
	# the catalogue: the look-alikes side by side, a part's levels
	ui.open_stores()
	await tree.process_frame
	var a3 = sp.body.find_child("part_pt_unit_a3", true, false)
	var a4 = sp.body.find_child("part_pt_unit_a4", true, false)
	if a3 == null or a4 == null or a4.get_index() != a3.get_index() + 1:
		p.append("the catalogue does not put the look-alikes side by side")
	else:
		var lv: Label = a3.find_child("levels", true, false)
		if lv == null or not lv.text.begins_with("Stock 2 · min 1, reorder at 1, max 3"):
			p.append("the range 3 transmitter's levels: %s" % (lv.text if lv != null else "(none)"))
	# an order: from the part's order form, due by its lead time
	if not _press(sp.body, "order_pt_unit_a3"):
		p.append("the catalogue offers no Order in free mode")
	else:
		await tree.process_frame
		if sp.view != "order" or sp.order_qty == null or sp.order_qty.text != "1":
			p.append("the order form's quantity (up to the max): %s" % (sp.order_qty.text if sp.order_qty != null else "none"))
		sp.order_qty.text = "2"
		var c0: int = e.clock()
		_press(sp.body, "order_send")
		ui.clock.run_steps(2)
		await tree.process_frame
		if not sp.last_text.begins_with("Ordered: 2 × WDP-PT-UNIT-A3") or not sp.last_text.contains("PO-0001"):
			p.append("the order: %s" % sp.last_text)
		if e.sr_orders.size() != 1 or int(e.sr_orders[0][5]) - c0 < 42 * DAY or int(e.sr_orders[0][5]) - c0 > 42 * DAY + 600:
			p.append("the order's due clock: %s" % str(e.sr_orders))
		ui.open_stores()
		await tree.process_frame
		var dl: Label = sp.body.find_child("deliveries", true, false)
		if dl == null or not dl.text.contains("PO-0001  2 × WDP-PT-UNIT-A3"):
			p.append("the deliveries do not list the order: %s" % (dl.text if dl != null else "(none)"))
		# (42 days on: past a jump's 30, so no jump to it is offered)
		if sp.body.find_child("jump_delivery", true, false) != null:
			p.append("a jump 42 days on was offered")
	# the debrief's parts
	var d := Debrief.collect(e, ui.info, null)
	var lines := "\n".join(Debrief.summary_lines(d))
	if not lines.contains("Parts drawn for") or not lines.contains("10 × WDP-PT-FERRULES"):
		p.append("the debrief has no parts drawn: %s" % lines.right(400))
	# a jump with days through the input path
	ui.inputs.jump("07:00", 2)
	if e.queue.is_empty() or e.queue[-1] != ["jump", "07:00", 2]:
		p.append("a jump with days was queued as %s" % str(e.queue.slice(-1)))
	ui.clock.run_steps(1)
	# a person played away from the counter: the form sends them there (a person is taken at a run's first step:
	# the shift again)
	ui.start_shift("test_stores")
	await tree.process_frame
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	e = ui.clock.engine
	var who := ""                   # (someone on duty who is not a storekeeper)
	for pi in e._sm.people.size():
		var rid: String = e._sm.people[pi]["role"]
		if e.sp_on[pi] and e._sm.roles[rid]["play"] and not e._sm.auth[rid].has("issue_parts"):
			who = e._sm.people[pi]["id"]
			break
	ui.inputs.role(who)
	ui.clock.run_steps(2)
	await tree.process_frame
	if ui.my_person() == -1:
		p.append("%s was not taken" % who)
	elif e.t_at(ui.inputs.slot) != Stores.counter(e)["at"]:
		ui.open_stores("issue", "")
		await tree.process_frame
		if sp.at_counter() or sp.body.find_child("go_counter", true, false) == null \
				or sp.body.find_child("issue_send", true, false) != null:
			p.append("away from the counter the issue form was offered")
	main.free()
	return p
