## Hands-on work at a transmitter in the plant (docs/plant3d/REALISM.md §3.1, §3.3, §2.16; milestone HW2), as a
## trainee plays it:
## - the work view's swap and restore: the plant's piece of condenser pressure transmitter 2 hidden and its work scene
##   standing where it stood (the plant's materials), the close camera; closed, the piece back and the walker's camera;
## - a full job as the I&C technician: transmitter 2 reads low (the instructor names the hidden cause: a loose
##   terminal), the permit asked, approved and isolated by the crews (the trainee's own lock), the job given to the
##   trainee; the tools taken at the toolbox, the permit accepted at the transmitter; a wrong order and a wrong tool
##   refused with the content's sentences, the multimeter across the signal terminals refused; the cover off, the
##   communicator and the multimeter on (their screens against the model's meters), the cause found (the multimeter's
##   current 0.3 mA under the one the transmitter says it sets) and put right (the terminals tightened; the job's step
##   that decides on the trim skips it, REALISM.md §2.16, and the communicator's trim is tried and taken back there),
##   everything off, the cover on, the work done and handed back, the tools put back: the fault repaired, the loop sound.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Hands = preload("res://sim/hands.gd")
const Maint = preload("res://tests/test_ui_maintenance.gd")

const PT2 := "30MAG10CP002"
const WORK := "wo_cond_p2_fix"
const FAULT := "cond_p2_low"

var _m = Maint.new()             # its trainee's player for the steps it knows (go, permit, lock, say, ppe…)
var _sent := {}                  # "order/step/what" -> the engine step it was sent at
var seen := {}                   # what the job saw on the way (the tests below read it)


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += await _swap(tree)
	p += await _job(tree)
	return p


static func _start(tree: SceneTree, sid: String) -> Array:
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return [null, "the app or its scenario with the crews (shift_cold) did not start"]
	ui.player.set_physics_process(false)
	Maint._scenario(ui, sid, "06:30", {"absent": ["ic2", "ic3", "ic4"]})
	var why: String = await Maint._take(tree, ui, sid, "Play I&C technician (coming on shift)")
	if why != "":
		main.free()
		return [null, why]
	return [main, ""]


static func _open(tree: SceneTree, ui, code: String) -> String:
	var e = ui.clock.engine
	var wp: int = e._sm.work_at[code]
	if e.t_at() != wp:
		ui.go_to_place(wp)
		ui._place_tick()
		ui.clock.run_steps(1)
	if not ui.work.open(code):
		return "the work view did not open at %s (%s)" % [code, ui.work.cannot(code)]
	var end := Time.get_ticks_msec() + 30000
	while not ui.work.loaded() and Time.get_ticks_msec() < end:
		await tree.process_frame
	return "" if ui.work.loaded() else "the work scene did not load"


## The swap and restore (REALISM.md §13 "the work view's swap and restore of the equipment").
func _swap(tree: SceneTree) -> Array:
	var p: Array = []
	var r: Array = await _start(tree, "test_hands_swap")
	if r[0] == null:
		return [r[1]]
	var main: Node = r[0]
	var ui = main.ui
	var node: Node3D = ui.index.nodes.get(PT2)
	var piece: Node3D = node.get_node_or_null("piece") if node != null else null
	if piece == null:
		main.free()
		return ["transmitter 2 is not built unmerged (no node `piece` under its equipment node)"]
	ui.open_card(PT2)
	await tree.process_frame
	var wb = ui.card.find_child("work_on_it", true, false)
	if wb == null:
		p.append("the card has no Work on it: %s" % App.texts(ui.card).left(300))
	elif not wb.disabled:
		p.append("Work on it is offered away from the transmitter")
	var why := await _open(tree, ui, PT2)
	if why != "":
		main.free()
		return p + [why]
	if piece.visible:
		p.append("the plant's piece is still drawn with the work view open")
	var sc: Node3D = ui.work.scene
	if not sc.global_transform.is_equal_approx(node.global_transform):
		p.append("the work scene doesn't stand where the transmitter stands: %s, %s" % [sc.global_transform, node.global_transform])
	var cam := main.get_viewport().get_camera_3d()
	if cam == ui.player.camera or cam.global_position.distance_to(node.global_position) > 2.0:
		p.append("the view's camera is not the work view's close one")
	var mats := 0
	var plain := 0
	for mi in sc.find_children("*", "GeometryInstance3D", true, false):
		if mi.has_meta("mat"):
			if mi.material_override != null and String(mi.material_override.resource_path).contains("built/materials/"):
				mats += 1
			else:
				plain += 1
	if mats == 0 or plain > 0:
		p.append("the work scene's meshes take the plant's materials: %d do, %d don't" % [mats, plain])
	if not sc.has_node("mounting"):
		p.append("the work scene has no mounting node (what the plant draws and the Workshop leaves out)")
	if ui.work.load_ms > 300.0:
		p.append("the work scene took %.0f ms to load (the budget: 300 ms, REALISM.md §11)" % ui.work.load_ms)
	if not ui.views_open() or ui.player.input_enabled:
		p.append("the walker still moves with the work view open")
	ui.work.close()
	await tree.process_frame
	if not piece.visible or is_instance_valid(sc) and sc.is_inside_tree() and not sc.is_queued_for_deletion():
		p.append("closed, the plant's piece is not back (or the work scene stays)")
	if main.get_viewport().get_camera_3d() != ui.player.camera:
		p.append("closed, the walker's camera is not back")
	main.free()
	return p


func _job(tree: SceneTree) -> Array:
	var p: Array = []
	var r: Array = await _start(tree, "test_hands_job")
	if r[0] == null:
		return [r[1]]
	var main: Node = r[0]
	var ui = main.ui
	var e = ui.clock.engine
	ui.inputs.fault(FAULT, "loose")          # the instructor names the cause (REALISM.md §2.6): no draw
	ui.clock.run_steps(2)
	if e.cause_of.get(FAULT) != "loose":
		p.append("the instructor's cause was not applied: %s" % str(e.cause_of.get(FAULT)))
	var low: float = e.v("cond_p2") - e.v("cond_p1")
	var log := []
	var done := func(): return e.pstate[e.m.work_ix[WORK]] >= 8 and e.carried.get("ic1", []).is_empty() \
			and _job_over(e)
	var ok := true
	for i in 3000:
		if done.call():
			break
		if not await _play(tree, ui, log):
			await _m._play(tree, ui, log)
		ui.clock.run_steps(10)
		if i % 8 == 0:
			await tree.process_frame
	if not done.call():
		ok = false
		var cur = e.sp_cur[e.trainee()]
		p.append("the job did not end (now %s, permit state %d, the task %s step %s; %s)" % [ui.clock_text(),
				e.pstate[e.m.work_ix[WORK]], str(cur["task"]) if cur else "none", str(cur["step"]) if cur else "",
				", ".join(log.slice(0, 3))] + "; the last hand events: %s" % str(e.events.filter(
				func(x): return x[1] == "hand" and x[5] == "ic1").slice(-3)))
	ui.work.close()
	for k in ["order", "tool", "short", "dmm_screen", "found", "trim"]:
		if not seen.has(k):
			p.append("the job never checked %s" % k)
		elif seen[k] != "":
			p.append(seen[k])
	if ok:
		for want in [["tool", "sd_term", 1, "ic1", "done"], ["permit", WORK, "accept", "ic1", "done"],
				["hand", PT2, "open_cover", null, "ic1", "done"], ["hand", PT2, "tighten_terms", "sd_term", "ic1", "done"],
				["permit", WORK, "done", "ic1", "done"], ["repair", FAULT], ["tool", "hart", 0, "ic1", "done"]]:
			if not Maint._has_ev(e, want):
				p.append("no event like %s" % str(want))
		# the readings reported from the work view and the Crew panel are readings, not misreads (their tolerance)
		var reads: Array = e.events.filter(func(x): return x[1] == "read" and x[2] == "ic1")
		if reads.size() < 5:
			p.append("only %d readings reported: %s" % [reads.size(), str(reads)])
		for x in reads:
			if x[5] != "ok":
				p.append("a reading not taken as one: %s" % str(x))
		ui.clock.run_steps(5)
		for st in ["cpt2_terminal_block_loose", "cpt2_cover_back_off", "cpt2_terminal_block_hart",
				"cpt2_terminal_block_dmm", "cond_p2_low"]:
			if e.v(st) != 0.0:
				p.append("%s is %s after the job" % [st, e.v(st)])
		# REALISM.md §2.16: the job chose the terminals, not the trim (its wait skipped the trim under the loose
		# terminal): no HART op of the task's own, and the trim the trainee tried taken back
		if absf(e.v("cond_p2_trim")) > 0.002:
			p.append("the trim is %.3f after the job (the loose terminal needs none)" % e.v("cond_p2_trim"))
		var now: float = e.v("cond_p2_rx") - e.v("cond_p1")
		if low > -1.0 or absf(now - 0.1) > 0.05:
			p.append("transmitter 2 against 1: %.2f with the loose terminal, %.2f after the job (expected under -1, 0.1)" % [
					low, now])
	main.free()
	return p


static func _job_over(e) -> bool:
	var c = e.sp_cur[e.trainee()]
	return c == null or c["task"] != "job_cond_p2_fix"


func _once(e, cur: Dictionary, what: String, every := 40) -> bool:
	var key := "%s/%s/%s" % [cur["order"], cur["step"], what]
	if _sent.get(key, -100000) > e.step_no - every:
		return false
	_sent[key] = e.step_no
	return true


## The steps of hands-on work (the rest: test_ui_maintenance.gd's player): true when something was done.
func _play(tree: SceneTree, ui, log: Array) -> bool:
	var e = ui.clock.engine
	var sm = e._sm
	var pi: int = e.trainee()
	var cur = e.sp_cur[pi]
	if cur == null:
		return false
	var s: Dictionary = sm.tasks[cur["task"]]["steps"][cur["step"]]
	var pid: String = sm.people[pi]["id"]
	if e.busy.has(pid):
		return true             # a hand action under way: the clock runs
	if s.has("tool") and not s.has("hand"):
		if typeof(s["tool"]) == TYPE_ARRAY and e.t_at() == sm.pix["ic_toolbox"]:
			if not ui.work.tools_panel.visible:
				ui.work.toggle_tools()
			ui.work._tools_sig = ""
			ui.work._refresh_tools()
			var want: Array = ["sd_flat8"] + s["tool"]    # (the wrong screwdriver first, to try it)
			for t in want:
				if not e.carried.get(pid, []).has(t):
					var b = ui.work.tools_body.find_child("take_" + t, true, false)
					if b == null:
						log.append("no Take for %s at the toolbox: %s" % [t, App.texts(ui.work.tools_body).left(300)])
						return false
					if _once(e, cur, "take_" + t, 5):
						b.pressed.emit()
					return true
			return false
		if typeof(s["tool"]) == TYPE_STRING and e.t_at() == sm.pix["ic_toolbox"]:
			ui.work._tools_sig = ""
			ui.work._refresh_tools()
			for t in e.carried.get(pid, []):
				var b = ui.work.tools_body.find_child("back_" + t, true, false)
				if b != null and _once(e, cur, "back_" + t, 5):
					b.pressed.emit()
				return true
			return false
		return false            # (going there is the maintenance player's: its go steps)
	if s.has("read") and not s.has("via"):
		# a reading of the screens' value at the transmitter, written down from the Crew panel (S1's read)
		if not _once(e, cur, "read"):
			return true
		ui.write_reading(s["read"], "%.3f" % e.shown(s["read"], e.cur))
		return true
	# the step that decides on the trim (REALISM.md §2.16: the PV against the partners; under the loose terminal it
	# skips the trim to its else): the communicator's trim checked there, and taken back
	var trim_wait: bool = s.has("wait") and String(s["wait"].get("until", "")) == "cpt2_pv_low" and not seen.has("trim")
	var code = s.get("kks") if s.has("hand") else (s["read"] if s.has("read") and s.has("via") else
			(s["op"]["kks"] if s.has("op") and s["op"].get("where") == "hart" else (PT2 if trim_wait else null)))
	if code == null:
		return false
	if not ui.work.is_open or ui.work.code != code:
		var why: String = await _open(tree, ui, code)
		if why != "":
			log.append(why)
			return false
	var w = ui.work
	w.refresh()
	if s.has("hand"):
		if s["hand"] == "open_cover" and not seen.has("order"):
			await _try_wrong(tree, ui, pid)
			return true
		if s["hand"] == "connect_dmm" and not seen.has("short"):
			seen["short"] = await _refused(tree, ui, "terminal_block", "dmm", "dmm_on_sig", "short circuit")
			return true
		if s["hand"] == "tighten_terms" and not seen.has("found"):
			# the cause found: the loop current the multimeter reads against the one the transmitter sets
			var dmm: float = Hands.shown(e, "cpt2_dmm", e.cur)
			var ao: float = Hands.shown(e, "cpt2_ao", e.cur)
			seen["found"] = "" if absf(ao - dmm - 0.3) < 0.005 else \
					"the multimeter %.3f mA against the communicator's %.3f mA: not the loose terminal's 0.3 mA" % [dmm, ao]
		if not _once(e, cur, "hand"):
			return true
		w.pick_comp(e.m.hands_ix[code + "|" + s["hand"]]["component"])
		w.pick_tool(String(s.get("tool", "")))
		w.refresh()
		var b = w.actions.find_child("act_" + s["hand"], true, false)
		if b == null:
			log.append("no button for %s: %s" % [s["hand"], App.texts(w.actions).left(200)])
			return false
		b.pressed.emit()
		return true
	if s.has("read"):
		if s["via"] == "cpt2_dmm" and not seen.has("dmm_screen"):
			await tree.process_frame
			var box = w.meters.get_node_or_null("meter_cpt2_dmm")
			var want := "%.2f mA" % Hands.shown(e, "cpt2_dmm", e.cur)
			seen["dmm_screen"] = "" if box != null and App.texts(box).contains(want) and e.v("cpt2_ma") > 3.5 else \
					"the multimeter's screen doesn't show the model's %s (cpt2_ma %.3f): %s" % [want, e.v("cpt2_ma"),
					App.texts(w.meters).left(300)]
		if not _once(e, cur, "read"):
			return true
		w._sig = ""
		w.refresh()
		var b = w.meters.find_child("report_" + String(s["via"]), true, false)
		if b == null:
			log.append("no Report for %s: %s" % [s["via"], App.texts(w.meters).left(300)])
			return false
		b.pressed.emit()
		return true
	# the HART trim: a reference 0.5 kPa over the PV shown makes a trim of 0.5 more; then the PV shown before as the
	# reference takes it back (the sensor is sound, the cause was the terminal)
	if not s.has("op") and not trim_wait:
		return false
	if not _once(e, cur, "op"):
		return true
	if w.trim_entry == null:
		log.append("no sensor trim on the communicator's screen: %s" % App.texts(w.meters).left(300))
		return false
	var pv: float = Hands.shown(e, "cpt2_pv", e.cur)
	var trim_now: float = e.v("cond_p2_trim")
	w.trim_entry.text = "%.3f" % (pv + 0.5)
	seen["trim"] = ""
	var n: int = w.trim({"input": "cond_p2_trim", "range": [-5, 5]}, w.trim_entry.text)
	if n < 0:
		seen["trim"] = "the trim was not sent"
	else:
		var last: Array = e.inputs[e.inputs.size() - 1]
		if last[1] != "op" or absf(float(last[4]) - (trim_now + 0.5)) > 0.002 or last[6] != "hart":
			seen["trim"] = "the trim sent %s, not the %.2f that brings the PV to the reference" % [str(last), trim_now + 0.5]
	ui.clock.run_steps(2)
	if absf(e.v("cond_p2_trim") - (trim_now + 0.5)) > 0.002:
		seen["trim"] = "the trim was not made under the work's own permit (it is %.3f)" % e.v("cond_p2_trim")
	# and back: the reference the PV read before, so the trim is what it was
	w.trim_entry.text = "%.3f" % pv
	(w.meters.find_child("trim_apply", true, false) as Button).pressed.emit()
	return true


## Before the cover is off: lifting the wires is refused with the order's sentence; with the cover off, the 8 mm
## blade is refused with its own.
func _try_wrong(tree: SceneTree, ui, pid: String) -> void:
	seen["order"] = await _refused(tree, ui, "terminal_block", "sd_term", "lift_wires", "terminal cover off first")
	ui.work.pick_comp("cover_back")
	ui.work.pick_tool("")
	ui.work.do_action("open_cover")
	for i in 30:
		ui.clock.run_steps(10)
		if not ui.clock.engine.busy.has(pid):
			break
	if ui.clock.engine.v("cpt2_cover_back_off") != 1.0:
		seen["tool"] = "the cover did not come off by hand"
		return
	seen["tool"] = await _refused(tree, ui, "terminal_block", "sd_flat8", "lift_wires", "too wide")


## An action sent and refused: "" when its words came back beside the component, else what went wrong.
func _refused(tree: SceneTree, ui, comp: String, tool: String, action: String, words: String) -> String:
	var w = ui.work
	w.pick_comp(comp)
	w.pick_tool(tool)
	w.refresh()
	w.last_text = ""
	var b = w.actions.find_child("act_" + action, true, false)
	if b == null:
		return "no button for %s" % action
	b.pressed.emit()
	ui.clock.run_steps(1)
	ui._sync_events()
	await tree.process_frame
	if not w.last_text.contains(words) or not w.note.text.contains(words) or not w._say.visible:
		return "%s with %s: shown %s, not the sentence with \"%s\"" % [action, tool, w.last_text, words]
	if ui.clock.engine.v("cpt2_terminal_block_lift") != 0.0:
		return "%s refused, yet the wires were lifted" % action
	return ""
