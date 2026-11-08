## Condition monitoring in the app (docs/plant3d/REALISM.md §2.19; milestone AG3), as the mechanical technician plays
## it in the aged plant:
## - what is drawn, from the monitoring file and the model: the ISO 20816-3 zones (a boundary belongs to the zone below
##   it), every vibration point's spectrum adding up to the overall (lines from model values and shares, the 1× taking
##   what they leave, scaled down when they alone would exceed it), the oil results' alert and alarm levels (ceilings
##   and the viscosity's band);
## - the card's "Condition monitoring" at closed cooling water pump A's motor (running, its bearing wearing out): its
##   points (the collector at its probe, the camera at the motor); without the tools, the screens say what to carry;
## - the tools taken at the store counter; at the pump: the collector's screen shows its meter's value, the zone and
##   the spectrum, a reading recorded (S1's read with the meter) and listed; the camera's spot reading the same;
## - the oil sample at CW pump A's motor: its hand action with the kit, ten minutes under way, the sample queued at the
##   lab; the clock moved on past the lab's turnaround (as a jump would), the results arrive: a toast, the lab's report
##   with its levels.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Hands = preload("res://sim/hands.gd")
const Mon = preload("res://ui/monitoring_view.gd")

const MOTOR := "00PGC10AP001"         # closed cooling water pump A (running in shift_aged)
const PROBE := "00PGC10CY001"
const OIL_AT := "30PAC10AP001"        # CW pump A's motor (its oil bath)


## An engine's values for the pure functions (e.v(name)).
class Vals extends RefCounted:
	var d := {}
	func v(n: String) -> float:
		return float(d.get(n, 0.0))


func run(tree: SceneTree) -> Array:
	var p: Array = _drawn()
	p += await _round(tree)
	return p


func _drawn() -> Array:
	var p: Array = []
	var vib := {"zones": [2.3, 4.5, 7.1], "floor": 0.03, "lines": [{"name": "2×", "order": 2, "share": 0.3},
		{"name": "BPFO", "order": 3.085, "value": "bt"}, {"name": "2×BPFO", "order": 6.17, "value": "bt", "share": 0.5},
		{"name": "GM", "order": 17, "value": "gx", "by": "spd", "share": 0.4}]}
	for c in [[0.0, 0], [2.3, 0], [2.31, 1], [4.5, 1], [7.1, 2], [7.11, 3], [40.0, 3]]:
		if Mon.zone(vib, c[0]) != c[1]:
			p.append("zone of %.2f mm/s: %d, wanted %d" % [c[0], Mon.zone(vib, c[0]), c[1]])
	var e := Vals.new()
	e.d = {"bt": 0.4, "gx": 0.5, "spd": 0.8}
	for ov in [0.0, 0.02, 0.5, 1.0, 3.2, 9.0]:
		var s: Dictionary = Mon.spectrum(e, vib, ov)
		var sum: float = float(s["floor"]) * float(s["floor"])
		for ln in s["lines"]:
			sum += float(ln[2]) * float(ln[2])
			if float(ln[2]) < 0.0:
				p.append("a negative line at %.2f mm/s overall: %s" % [ov, str(ln)])
		if absf(sqrt(sum) - ov) > 1e-9:
			p.append("the spectrum at %.2f mm/s overall adds up to %.6f" % [ov, sqrt(sum)])
	var s3: Dictionary = Mon.spectrum(e, vib, 3.2)
	var want := {"1×": -1.0, "2×": 0.96, "BPFO": 0.4, "2×BPFO": 0.2, "GM": 0.16}
	for ln in s3["lines"]:
		if want[ln[0]] >= 0.0 and absf(float(ln[2]) - want[ln[0]]) > 1e-9:
			p.append("line %s at 3.2 mm/s: %.4f, wanted %.4f" % [ln[0], ln[2], want[ln[0]]])
	if s3["lines"][0][0] != "1×" or float(s3["lines"][0][2]) < 2.9:
		p.append("the 1× does not take what the others leave: %s" % str(s3["lines"][0]))
	var s1: Dictionary = Mon.spectrum(e, vib, 0.3)     # the lines alone above the overall: scaled, no 1×
	if float(s1["lines"][0][2]) != 0.0:
		p.append("the 1× should be nothing when the lines alone exceed the overall: %s" % str(s1["lines"][0]))
	var fe := {"alert": 15, "alarm": 30}
	var visc := {"alert": [61.2, 74.8], "alarm": [54.4, 81.6]}
	for c in [[fe, 15.0, 0], [fe, 15.5, 1], [fe, 31.0, 2], [visc, 68.0, 0], [visc, 60.0, 1], [visc, 76.0, 1],
			[visc, 50.0, 2], [visc, 90.0, 2]]:
		if Mon.level(c[0], c[1]) != c[2]:
			p.append("level of %.1f against %s: %d, wanted %d" % [c[1], str(c[0]), Mon.level(c[0], c[1]), c[2]])
	return p


static func _start(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_aged"):
		main.free()
		return [null, "the app or its aged scenario with the crews (shift_aged) did not start"]
	ui.player.set_physics_process(false)
	var sc: Dictionary = ui.model.scenarios["shift_aged"].duplicate(true)
	sc["id"] = "test_monitoring"
	sc["start"] = {"day": 1, "time": "06:30"}
	ui.model.scenarios["test_monitoring"] = sc
	ui.start_shift("test_monitoring")
	await tree.process_frame
	var b := App.find_button(ui.crew, "Play Mechanical…")
	if b == null:
		var t: String = App.texts(ui.crew).left(600)
		main.free()
		return [null, "no Play Mechanical … in the Crew panel: %s" % t]
	b.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	ui.clock.run_steps(2)
	if ui.me() == null:
		main.free()
		return [null, "the mechanical technician was not taken"]
	return [main, ""]


static func _go(ui, place: String) -> void:
	var sm = ui.clock.engine._sm
	ui.go_to_place(sm.pix[place])
	ui._place_tick()
	ui.clock.run_steps(2)


static func _fresh(mv) -> void:
	mv._sig = ""
	mv.refresh()


func _round(tree: SceneTree) -> Array:
	var p: Array = []
	var r: Array = await _start(tree)
	if r[0] == null:
		return [r[1]]
	var main: Node = r[0]
	var ui = main.ui
	var mv = ui.monitoring
	var e = ui.clock.engine
	var pid: String = ui.me()
	# the card offers it at the motor and at its probe; the panel holds the machine's three points
	ui.open_card(MOTOR)
	await tree.process_frame
	var cb = ui.card.body.find_child("monitoring", true, false)
	if cb == null:
		main.free()
		return p + ["no Condition monitoring on %s's card: %s" % [MOTOR, App.texts(ui.card).left(400)]]
	(cb as Button).pressed.emit()
	if not mv.is_open() or ui.card.visible:
		p.append("the monitoring panel did not open in the card's place")
	var kinds := []
	for i in mv.by_machine[Mon.machine_of(MOTOR)]:
		kinds.append([mv.points[i]["kind"], mv.points[i]["code"]])
	if kinds != [["vib", PROBE], ["ir", MOTOR]]:
		p.append("closed cooling water pump A's points: %s" % str(kinds))
	var iv: int = mv.by_machine[Mon.machine_of(MOTOR)][0]
	var ii: int = mv.by_machine[Mon.machine_of(MOTOR)][1]
	var oil_kinds := []
	for i in mv.by_machine[Mon.machine_of(OIL_AT)]:
		oil_kinds.append([mv.points[i]["kind"], mv.points[i]["code"]])
	if oil_kinds != [["vib", "30PAC10CY001"], ["ir", OIL_AT], ["oil", OIL_AT]]:
		p.append("CW pump A's points: %s" % str(oil_kinds))
	var io: int = mv.by_machine[Mon.machine_of(OIL_AT)][2]
	_fresh(mv)
	var t0: String = App.texts(mv.body)
	if mv.body.find_child("collector", true, false) != null or not t0.contains("Carry the vibration data collector") \
			or not t0.contains("Carry the thermal camera"):
		p.append("without the tools the screens should say what to carry: %s" % t0.left(500))
	# the tools at the store counter
	_go(ui, "store_counter")
	if not ui.work.tools_panel.visible:
		ui.work.toggle_tools()
	for t in ["vib_dc", "ir_cam", "oil_kit"]:
		ui.work._tools_sig = ""
		ui.work._refresh_tools()
		var b = ui.work.tools_body.find_child("take_" + t, true, false)
		if b == null:
			p.append("no Take for %s at the store counter: %s" % [t, App.texts(ui.work.tools_body).left(300)])
			continue
		(b as Button).pressed.emit()
		ui.clock.run_steps(2)
	ui.work.close_tools()
	if not (e.carried.get(pid, []).has("vib_dc") and e.carried.get(pid, []).has("ir_cam") and e.carried.get(pid, []).has("oil_kit")):
		main.free()
		return p + ["the tools were not taken: %s" % str(e.carried.get(pid, []))]
	# at the pump: the collector's screen
	_go(ui, "w_" + MOTOR.to_lower())
	if not ui.near(PROBE) and ui.index.has(PROBE):
		p.append("the probe %s is not within reach of the motor's work place (%.1f m)" % [PROBE, ui.distance_to(PROBE)])
	mv.open(MOTOR)
	_fresh(mv)
	var col = mv.body.find_child("collector", true, false)
	if col == null:
		main.free()
		return p + ["no collector screen at the pump: %s" % App.texts(mv.body).left(500)]
	var pv: Dictionary = mv.points[iv]
	var v: float = Hands.shown(e, String(pv["meter"]), e.cur)
	var vl: Label = col.find_child("value", true, false)
	if vl.text != "%.2f mm/s" % v:
		p.append("the collector shows %s, its meter %.4f" % [vl.text, v])
	var zl: Label = col.find_child("zone", true, false)
	if not zl.text.begins_with("Zone %s:" % Mon.ZONE_NAMES[Mon.zone(pv, v)]):
		p.append("the zone shown %s for %.2f mm/s" % [zl.text, v])
	var sp = col.find_child("spectrum", true, false)
	var sum: float = sp.floor_v * sp.floor_v
	for ln in sp.lines:
		sum += float(ln[2]) * float(ln[2])
	if sp.lines.size() != pv["lines"].size() + 1 or absf(sqrt(sum) - v) > 1e-6:
		p.append("the spectrum drawn (%s, floor %.3f) does not add up to %.4f mm/s" % [str(sp.lines), sp.floor_v, v])
	if v < 0.5:
		p.append("closed cooling water pump A should run in the aged plant at 06:30 (its overall %.3f mm/s)" % v)
	(col.find_child("record", true, false) as Button).pressed.emit()
	ui.clock.run_steps(2)
	var rs: Array = Mon.readings(e, pv)
	if rs.size() != 1 or absf(rs[0][1] - snappedf(v, 0.01)) > 1e-9:
		p.append("the reading recorded: %s (wanted %.2f)" % [str(rs), v])
	_fresh(mv)
	var hist = mv.body.find_child("point_%d" % iv, true, false).find_child("history", true, false)
	if hist == null or not (hist as Label).text.contains("%.2f mm/s" % snappedf(v, 0.01)):
		p.append("the reading is not listed: %s" % (hist.text if hist != null else "no history"))
	# the camera's spot reading
	var cam = mv.body.find_child("point_%d" % ii, true, false).find_child("camera", true, false)
	if cam == null:
		p.append("no camera reading at the pump: %s" % App.texts(mv.body).left(400))
	else:
		var tv: float = Hands.shown(e, String(mv.points[ii]["meter"]), e.cur)
		if not (cam.find_child("value", true, false) as Label).text.begins_with("%.1f °C" % tv):
			p.append("the camera shows %s, its meter %.2f" % [(cam.find_child("value", true, false) as Label).text, tv])
		(cam.find_child("record", true, false) as Button).pressed.emit()
		ui.clock.run_steps(2)
		if Mon.readings(e, mv.points[ii]).size() != 1:
			p.append("the camera's reading was not recorded")
	# the oil sample, at CW pump A's motor
	_go(ui, "w_" + OIL_AT.to_lower())
	mv.open(OIL_AT)
	_fresh(mv)
	var po: Dictionary = mv.points[io]
	var node0: String = po["results"][0]["node"]
	var sb = mv.body.find_child("point_%d" % io, true, false).find_child("sample", true, false)
	(sb as Button).pressed.emit()
	var end := 0
	var busy_seen := false
	while end < 20000 and e.lab_q[node0].is_empty():
		ui.clock.run_steps(10)
		end += 10
		mv.refresh()
		var bl: Label = mv.body.find_child("point_%d" % io, true, false).find_child("busy", true, false)
		busy_seen = busy_seen or bl.text.begins_with("Taking the sample")
	if e.lab_q[node0].size() != 1:
		main.free()
		return p + ["the oil sample was not taken (%s; %s)" % [mv.last_text, str(e.lab_q[node0])]]
	if not busy_seen:
		p.append("the sample's ten minutes were not shown under way")
	if mv.last_text != "Sample taken: it goes to the lab":
		p.append("the sample's result in words: %s" % mv.last_text)
	_fresh(mv)
	var ql: Label = mv.body.find_child("point_%d" % io, true, false).find_child("queue", true, false)
	if not ql.text.begins_with("At the lab: 1 sample;"):
		p.append("the lab's queue shown: %s" % ql.text)
	# past the lab's turnaround (the clock moved on as a jump moves it): the results arrive
	var due: int = int(e.lab_q[node0][0][0])
	e.J += due - e.clock() + 1
	ui._sync_events()
	ui._toast.text = ""
	ui.clock.run_steps(2)
	ui._sync_events()           # (as the next frame does: the lab's results arrive with a toast)
	var reps: Array = Mon.reports(e, po)
	if reps.size() != 1 or reps[0][1].size() != po["results"].size():
		p.append("the lab's report: %s" % str(reps))
	elif ui._toast.text != "Lab results: " + String(po["title"]):
		p.append("no toast for the lab's results: %s" % ui._toast.text)
	_fresh(mv)
	for res in po["results"]:
		var l = mv.body.find_child("res_" + String(res["node"]), true, false)
		if l == null:
			p.append("no result %s in the report: %s" % [res["node"], App.texts(mv.body).left(500)])
			continue
		var want: int = Mon.level(res, float(reps[0][1][res["node"]])) if not reps.is_empty() else 0
		if (l as Label).get_theme_color("font_color") != Mon.LEVEL_COLOURS[want]:
			p.append("the result %s is not coloured as its level %d" % [res["node"], want])
	if App.texts(mv.body).contains("No lab results yet.") or not App.texts(mv.body).contains("Lab report of"):
		p.append("the lab's report is not shown: %s" % App.texts(mv.body).left(500))
	mv.close()
	main.free()
	return p

