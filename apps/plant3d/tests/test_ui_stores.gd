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
	p += _store_place()
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
	if not said.get("wrong_part", "").begins_with(want) or not said.get("wrong_part", "").contains(". Draw WDP-PT-UNIT-A3 ("):
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
	# (C1) the part a look-alike was offered for is copyable in the debrief even before it was drawn
	var first_wrong := -1
	var a3_drawn := false
	for k in e.events.size():
		var ev: Array = e.events[k]
		if ev[1] == "issue" and ev[2] == "tx_r3" and ev.size() > 6 and ev[6] == "done":
			a3_drawn = true
		if ev[1] == "hand" and ev.size() > 7 and ev[6] == "refused" and (ev[7] as Array).has("wrong_part"):
			first_wrong = k
			break
	if first_wrong == -1 or a3_drawn:
		p.append("run 7 has no look-alike offered before its part was drawn (%d, %s)" % [first_wrong, str(a3_drawn)])
	elif not Stores.debrief_numbers(e, first_wrong + 1).has("WDP-PT-UNIT-A3"):
		p.append("the part a look-alike was offered for has no Copy in the debrief: %s" % str(Stores.debrief_numbers(e,
				first_wrong + 1)))
	if offered != 2:        # (twice: before the range 3 was drawn, and again with only the look-alike left)
		p.append("the debrief's look-alikes offered (%d, wanted 2): %s" % [offered, all])
	return p


## A store at a place the staff don't have: refused when the plant loads (not at the first issue's walk).
func _store_place() -> Array:
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/plant3d-realism.json").simplify_path()
	var S: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value["stores"]
	var run: Dictionary = S["runs"][7]
	var files: Dictionary = S["files"].duplicate(true)
	files["scenarios/s1.json"] = run["scenario"]
	if run["staff"] != null:
		files["staff.json"] = run["staff"]
	if PlantModel.from_files(files).error != "" or not String(files["stores.json"]).contains('"place": "counter"'):
		return ["the realism stores plant did not load, or its store is not at the counter"]
	files["stores.json"] = String(files["stores.json"]).replace('"place": "counter"', '"place": "no_such_place"')
	var err: String = PlantModel.from_files(files).error
	if not err.contains("no staff place no_such_place"):
		return ["a store at a place the staff don't have was taken: %s" % (err if err != "" else "(no error)")]
	return []


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
	# the panel stays on the screen, its Close with it, whatever the work order's name (UI-UX-POLICY R1)
	for i in 3:
		await tree.process_frame
	var vr: Rect2 = sp.get_viewport_rect()
	var close = sp.find_child("close", true, false)
	if not vr.encloses(sp.get_global_rect()) or close == null or not vr.encloses((close as Control).get_global_rect()):
		p.append("the counter's form leaves the screen (panel %s, Close %s, screen %s)" % [str(sp.get_global_rect()),
				str((close as Control).get_global_rect()) if close != null else "none", str(vr)])
	# the work chosen is kept by its id across rebuilds, never by its place in the list: another work order entering
	# the list before it (planned by someone else) leaves the form on the order's work, a work the trainee chose stays
	# chosen when the form is rebuilt (the form opened from the order must not take its work back), and a chosen work
	# that leaves the list leaves none chosen
	var other := ""
	for w in e.m.works:
		if w["id"] == wid:
			break
		if other == "" and not int(e.wo.get(w["id"], 0)) in Stores.WO_OPEN:
			other = w["id"]
	if other == "":
		p.append("no work before %s to plan in the test" % wid)
	else:
		var had: bool = e.wo.has(other)
		var was = e.wo.get(other)
		e.wo[other] = 2
		_fresh(sp)
		if sp.work_pick.selected < 0 or sp._work_ids[sp.work_pick.selected] != wid:
			p.append("a work entering the list moved the form off the order's work (on %s)"
					% (sp._work_ids[sp.work_pick.selected] if sp.work_pick.selected >= 0 else "none"))
		var oi: int = sp._work_ids.find(other)
		sp.work_pick.select(oi)
		sp.work_pick.item_selected.emit(oi)
		_fresh(sp)
		if sp.work_pick.selected < 0 or sp._work_ids[sp.work_pick.selected] != other:
			p.append("a rebuild took the trainee's choice of work back to the order's")
		if had:
			e.wo[other] = was
		else:
			e.wo.erase(other)
		_fresh(sp)
		if sp.work_pick.selected != -1:
			p.append("the chosen work left the list but another stayed chosen: %s" % sp._work_ids[sp.work_pick.selected])
		var wi: int = sp._work_ids.find(wid)
		sp.work_pick.select(wi)
		sp.work_pick.item_selected.emit(wi)
		_fresh(sp)
	# a number not in the catalogue, a quantity that is not a number: refused on the form, nothing sent
	var n0: int = e.inputs.size()
	# (F5, F2) no number, a quantity out of range: said at the field, nothing sent; (A1) − and + change the quantity
	sp.number_edit.text = ""
	_press(sp.body, "issue_send")
	await tree.process_frame
	var ne = sp.body.find_child("issue_number_error", true, false)
	if ne == null or not String(ne.text).begins_with("Write the part number"):
		p.append("an empty part number: %s" % (ne.text if ne != null else sp.last_text))
	sp.number_edit.text = "wdp-pt-ferrules"
	sp.qty_edit.text = "0"
	_press(sp.body, "issue_send")
	await tree.process_frame
	var qz = sp.body.find_child("issue_qty_error", true, false)
	if qz == null or not String(qz.text).begins_with("Write a quantity from 1 to 9,999"):
		p.append("a quantity of 0 was not refused at its field: %s" % sp.last_text)
	_press(sp.body, "issue_qty_plus")
	_press(sp.body, "issue_qty_plus")
	_press(sp.body, "issue_qty_minus")
	if sp.qty_edit.text != "1":
		p.append("− and + beside the quantity: %s after + + − from 0, wanted 1 (1, 2, 1)" % sp.qty_edit.text)
	sp.number_edit.text = "WDP-NOTHING-9"
	_press(sp.body, "issue_send")
	if not sp.last_text.begins_with("No part numbered WDP-NOTHING-9"):
		p.append("a number not in the catalogue: %s" % sp.last_text)
	sp.number_edit.text = "wdp-pt-ferrules"
	sp.qty_edit.text = "ten"
	_press(sp.body, "issue_send")
	if not sp.last_text.begins_with("Write the quantity"):
		p.append("a quantity that is not a number: %s" % sp.last_text)
	# (UI-UX-POLICY F5, A5) the error at its field, the focus there, what was typed kept; each field labelled and named
	await tree.process_frame
	var qe = sp.body.find_child("issue_qty_error", true, false)
	if qe == null or not String(qe.text).begins_with("Write the quantity") or not sp.qty_edit.has_focus() \
			or sp.qty_edit.text != "ten" or sp.number_edit.text != "wdp-pt-ferrules":
		p.append("the quantity's error is not at its field with the focus and the typing kept (error %s, focus %s)"
				% [str(qe.text) if qe != null else "none", str(sp.qty_edit.has_focus())])
	for f in [["issue_number", "Part number"], ["issue_qty", "Quantity"], ["issue_work", "Work order"]]:
		var fc = sp.body.find_child(f[0], true, false)
		var fl = sp.body.find_child(f[0] + "_label", true, false)
		if fc == null or fc.accessibility_name != f[1] or fl == null or fl.text != f[1]:
			p.append("the field %s has no label or name \"%s\"" % [f[0], f[1]])
	# (D3) to the catalogue and back: the number, the quantity and the work as they were
	_press(sp.body, "to_list")
	await tree.process_frame
	_press(sp.body, "to_issue")
	await tree.process_frame
	if sp.number_edit == null or sp.number_edit.text != "wdp-pt-ferrules" or sp.qty_edit.text != "ten" \
			or sp.work_pick.selected < 0 or sp._work_ids[sp.work_pick.selected] != wid:
		p.append("going to the catalogue and back lost the request: %s, %s" % [
				sp.number_edit.text if sp.number_edit != null else "no form", sp.qty_edit.text if sp.qty_edit != null else ""])
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
	if not _press(wp.body, "copy_issued_WDP-PT-FERRULES") or sp.last_copied != "WDP-PT-FERRULES":
		p.append("the order's issued part cannot be copied (%s)" % sp.last_copied)
	for i in 3:
		await tree.process_frame
	var wclose = wp.find_child("close", true, false)
	if not wp.get_viewport_rect().encloses(wp.get_global_rect()) or wclose == null \
			or not wp.get_viewport_rect().encloses((wclose as Control).get_global_rect()):
		p.append("the work order's form leaves the screen (panel %s)" % str(wp.get_global_rect()))
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
	# a notice (a toast) keeps clear of the stores panel, as of the card (it covered the rows' buttons), also one shown
	# before the panel opened, and a long one stays on the screen
	ui.close_stores()
	ui.toast("Issue of WDP-PT-SENSOR-MODULE Sensor module, absolute, range 3 refused: only 1 on the shelf: ask for 1 or "
			+ "fewer, or order more (Order, in the catalogue)")
	await tree.process_frame
	ui.open_stores()
	for i in 3:
		await tree.process_frame
	var tr: Rect2 = ui._toast.get_global_rect()
	if tr.intersects(sp.get_global_rect()) or tr.end.y > sp.get_viewport_rect().end.y:
		p.append("a notice covers the stores panel or leaves the screen: %s, panel %s" % [str(tr), str(sp.get_global_rect())])
	# (C1–C3, A1) a part's number copied, or written on the request by a press; (K4) the levels say the state in words
	_press(sp.body, "copy_pt_unit_a3")
	if sp.last_copied != "WDP-PT-UNIT-A3":
		p.append("Copy did not copy the part's number: %s" % sp.last_copied)
	_press(sp.body, "write_pt_unit_a4")
	await tree.process_frame
	if sp.view != "issue" or sp.number_edit == null or sp.number_edit.text != "WDP-PT-UNIT-A4":
		p.append("\"Write it on the request\" did not: view %s, %s" % [sp.view,
				sp.number_edit.text if sp.number_edit != null else "no field"])
	var k3: int = e._sr["ix"]["pt_unit_a3"]
	var s3: int = e.sr_stock[k3]
	e.sr_stock[k3] = 0
	if not Stores.levels_words(e, "pt_unit_a3").contains("none on the shelf"):
		p.append("an empty shelf in words: %s" % Stores.levels_words(e, "pt_unit_a3"))
	e.sr_stock[k3] = 1
	if not Stores.levels_words(e, "pt_unit_a3").contains("at or below the reorder point"):
		p.append("stock at the reorder point in words: %s" % Stores.levels_words(e, "pt_unit_a3"))
	e.sr_stock[k3] = s3
	if Stores.lead_words(1) != "1 day's lead time":
		p.append("a lead time of one day: %s" % Stores.lead_words(1))
	ui.open_stores()
	await tree.process_frame
	# an order: from the part's order form, due by its lead time
	if not _press(sp.body, "order_pt_unit_a3"):
		p.append("the catalogue offers no Order in free mode")
	else:
		await tree.process_frame
		if sp.view != "order" or sp.order_qty == null or sp.order_qty.text != "1":
			p.append("the order form's quantity (up to the max): %s" % (sp.order_qty.text if sp.order_qty != null else "none"))
		# (L2) the order form's button wraps the roles' names: the panel and its Close stay on the screen
		for i in 3:
			await tree.process_frame
		var ovr: Rect2 = sp.get_viewport_rect()
		var oc = sp.find_child("close", true, false)
		if not ovr.encloses(sp.get_global_rect()) or oc == null or not ovr.encloses((oc as Control).get_global_rect()):
			p.append("the order form leaves the screen (panel %s)" % str(sp.get_global_rect()))
		sp.order_qty.text = "2"
		# (D3) to the catalogue and back to the same part: the quantity as typed
		_press(sp.body, "to_list")
		await tree.process_frame
		_press(sp.body, "order_pt_unit_a3")
		await tree.process_frame
		if sp.order_qty == null or sp.order_qty.text != "2":
			p.append("the order form's quantity was lost on the way to the catalogue and back: %s" % (
					sp.order_qty.text if sp.order_qty != null else "no form"))
			sp.order_qty.text = "2"
		# another part's order form between: each part keeps its own
		ui.open_stores("order", "pt_unit_a4")
		await tree.process_frame
		ui.open_stores("order", "pt_unit_a3")
		await tree.process_frame
		if sp.order_qty == null or sp.order_qty.text != "2":
			p.append("another part's order form dropped this one's quantity: %s" % (
					sp.order_qty.text if sp.order_qty != null else "no form"))
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
		_press(sp.body, "copy_PO-0001")
		if sp.last_copied != "PO-0001":
			p.append("the purchase order's number was not copied: %s" % sp.last_copied)
		# (42 days on: past a jump's 30, so no jump to it is offered)
		if sp.body.find_child("jump_delivery", true, false) != null:
			p.append("a jump 42 days on was offered")
		# an order due in 7 days: the jump to it is offered, and worked out when pressed (the list is not rebuilt as
		# the clock goes past the delivery's time of day: the jump built with the list would land a day late)
		sp.order("cp_oil", 1)
		ui.clock.run_steps(2)
		await tree.process_frame
		var due := -1
		for o in e.sr_orders:
			if o[1] == "cp_oil":
				due = int(o[5])
		ui.open_stores()
		await tree.process_frame
		var j0: Array = Stores.jump_to(e, due)
		var n_run := 0
		while due >= 0 and (e.clock() % DAY) <= (due % DAY) + 600 and n_run < 400:
			ui.clock.run_steps(5)
			n_run += 1
		var j1: Array = Stores.jump_to(e, due)
		if due < 0 or j0.size() != 2 or j1.size() != 2 or int(j1[1]) != int(j0[1]) - 1:
			p.append("the delivery's jump test did not set up: due %d, %s then %s" % [due, str(j0), str(j1)])
		elif not _press(sp.body, "jump_delivery"):
			p.append("no jump to a delivery 7 days on was offered: %s" % Stores.jump_blocked(e))
		elif e.queue.is_empty() or e.queue[-1] != ["jump", j1[0], j1[1]]:
			p.append("the jump to the delivery was %s, wanted %s (the one worked out when the list was built: %s)"
					% [str(e.queue.slice(-1)), str(["jump"] + j1), str(j0)])
		if not e.queue.is_empty() and e.queue[-1][0] == "jump":
			e.queue.pop_back()      # (not taken: the rest of the test runs on this day)
	# the debrief's parts
	var d := Debrief.collect(e, ui.info, null)
	var lines := "\n".join(Debrief.summary_lines(d))
	if not lines.contains("Parts drawn for") or not lines.contains("10 × WDP-PT-FERRULES"):
		p.append("the debrief has no parts drawn: %s" % lines.right(400))
	var raw: Array = d.entries.filter(func(x): return String(x.text).begins_with("issue ") or String(x.text).begins_with("order "))
	var said_issue: Array = d.entries.filter(func(x): return String(x.text).begins_with("Issued: 10 × WDP-PT-FERRULES"))
	var said_stock: Array = d.entries.filter(func(x): return String(x.text).begins_with("Issue of WDP-PT-SENSOR-MODULE"))
	if said_stock.is_empty() or not String(said_stock[0].text).ends_with("refused: not enough on the shelf"):
		p.append("the debrief says a past refusal from today's stock: %s" % str(said_stock.map(func(x): return x.text)))
	if not raw.is_empty() or said_issue.is_empty():
		p.append("the debrief lists the stores' events as records, not words: %s" % str(raw.map(func(x): return x.text)))
	ui.open_debrief()
	await tree.process_frame
	if not _press(ui.debrief, "copy_part_WDP-PT-FERRULES") or sp.last_copied != "WDP-PT-FERRULES":
		p.append("the debrief's parts drawn cannot be copied (%s)" % sp.last_copied)
	ui.close_debrief()
	# a jump with days through the input path
	var cj: int = e.clock()
	ui.inputs.jump("07:00", 2)
	if e.queue.is_empty() or e.queue[-1] != ["jump", "07:00", 2]:
		p.append("a jump with days was queued as %s" % str(e.queue.slice(-1)))
	ui.clock.run_steps(1)
	var want: int = int(cj / DAY) * DAY + 7 * 36000          # the next 07:00, then two days on
	if want <= cj:
		want += DAY
	want += 2 * DAY
	if absi(e.clock() - want) > 600:
		p.append("the jump with days did not land at %s: from %s to %s (%s)" % [Stores.clock_words(want),
				Stores.clock_words(cj), Stores.clock_words(e.clock()), str(e.events.slice(-3))])
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
	elif e.t_at(ui.inputs.slot) == Stores.counter(e)["at"]:
		p.append("%s starts at the counter: the form away from it is not tested" % who)
	else:
		ui.open_stores("issue", "")
		await tree.process_frame
		if sp.at_counter() or sp.body.find_child("go_counter", true, false) == null \
				or sp.body.find_child("issue_send", true, false) != null:
			p.append("away from the counter the issue form was offered")
	main.free()
	return p
