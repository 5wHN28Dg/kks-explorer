## The water treatment plant's people in the app (milestone S3: docs/plant3d/STAFF.md, WATER-TREATMENT.md §7, PLANT3D
## §17.12), on the scenario shift_wtp (filter 1 due at about 06:05, mixed bed A's silica over the laboratory's limit
## from about 06:50), as a trainee plays them:
## - the WTP operator of crew A: their own day in the Crew panel (the WTP rounds); filter 1's head loss comes due and
##   the NPC shift supervisor orders its backwash over the radio; the trainee runs it from the WTP's desk (00CWD10):
##   the op made from the desk's screens, the air scour watched at the filter bank, the clean filter reported;
## - the shift chemist of crew A: their own day (the samples); the samples drawn at the sample panel and analysed at
##   the laboratory bench, each reading written down from the Crew panel; mixed bed A's silica over the laboratory's
##   limit logged (out of range on the readings sheet), and the NPC WTP operator, given the finding, changes the beds
##   over and starts bed A's regeneration from the WTP's desk;
## - the run with the regeneration under way goes round a save and on bit for bit, and a clone with it.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const RunSave = preload("res://ui/run_save.gd")
const PlantEngine = preload("res://sim/engine.gd")

const SID := "shift_wtp"
const FILTER := "00GBB11AT001"
const BED := "00GCF11AT001"
const SILICA := "00GCF11CQ002"


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += await _operator_backwash(tree)
	p += await _chemist_silica(tree)
	return p


static func _take(tree: SceneTree, ui, label: String) -> String:
	ui.start_shift(SID)
	await tree.process_frame
	var b := App.find_button(ui.crew, label)
	if b == null:
		return "no %s in the Crew panel: %s" % [label, App.texts(ui.crew).left(600)]
	b.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	return ""


## The Crew panel rebuilt from the engine as it is now, whatever its own signature says (the panel's buttons are
## looked for in it). Only where the step needs the panel: rebuilt every round, it took most of the test's time.
static func _fresh(ui) -> void:
	ui.crew._sig = ""
	ui.crew.refresh()


## Plays the trainee's current step as a trainee would, from the Crew panel, the WTP desk's screens and the cards
## (true when something was done). The walker is put at a place by "Take me there".
func _play(tree: SceneTree, ui, log: Array) -> bool:
	var e = ui.clock.engine
	var sm = e._sm
	var pi: int = e.st_trainee
	if not ui.crew.visible:
		ui.open_crew()
	if e.st_unacked > 0:
		_fresh(ui)                      # (rebuilt every round before: an alarm seen without waiting for the panel's own refresh)
		var seen := App.find_button(ui.crew, "Seen")
		if seen:
			seen.pressed.emit()
	var cur = e.sp_cur[pi]
	if cur == null:
		return false
	var s: Dictionary = sm.tasks[cur["task"]]["steps"][cur["step"]]
	if s.has("go") or s.has("meet") or s.has("work"):
		var dest = cur["st"].get("dest", cur["st"].get("place"))
		if dest != null and dest >= 0 and e.st_t_at != dest:
			_fresh(ui)
			var b := App.find_button(ui.crew, "Take me there")
			if b == null:
				log.append("a step with a place offers no Take me there: %s" % App.texts(ui.crew).left(300))
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
	elif s.has("ppe"):
		_fresh(ui)
		var b := App.find_button(ui.crew, "Put it on")
		if b == null:
			b = App.find_button(ui.crew, "Take me to a locker")
			if b == null:
				log.append("a ppe step offers neither a locker nor its PPE: %s" % App.texts(ui.crew).left(300))
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
		b.pressed.emit()
		return true
	elif s.has("read"):
		# the value the gauge or the analyser shows, written down from the Crew panel
		_fresh(ui)
		var v: float = e.shown(s["read"], e.cur)
		if ui.crew.entry == null:
			log.append("a reading step offers no entry: %s" % App.texts(ui.crew).left(300))
			return false
		ui.crew.entry.text = "%.3f" % v
		var b := App.find_button(ui.crew, "Write down")
		if b == null:
			return false
		b.pressed.emit()
		return true
	elif s.has("op"):
		# a screen op at the WTP's desk (the step before took the trainee there): the desk opens its screens, the
		# card of the equipment offers the op
		var o: Dictionary = s["op"]
		if o["where"] == "screen" and not ui.screens_open():
			ui.open_card("00CWD10")
		ui.open_card(o["kks"])
		var row := App.op_row(ui.card, o["kks"], o["do"])
		if row.is_empty() or (row[1] as Button).disabled:
			log.append("the card of %s offers no %s at the WTP's desk" % [o["kks"], o["do"]])
			ui.close_card()
			return false
		(row[1] as Button).pressed.emit()
		ui.close_card()
		ui.close_screens()
		return true
	elif s.has("say"):
		_fresh(ui)
		var b := App.find_button(ui.crew, "Send")
		if b:
			b.pressed.emit()
		return true
	elif s.has("call"):
		_fresh(ui)
		var b := App.find_button(ui.crew, "Call")
		if b:
			b.pressed.emit()
		return true
	elif s.has("choose"):
		e.pick(0)
		return true
	return false


## Runs the clock and plays the trainee until `done` is true or `limit` rounds of 10 steps pass.
func _steps(tree: SceneTree, ui, done: Callable, limit: int, log: Array) -> bool:
	for i in limit:
		if done.call():
			return true
		# (a step played: its outcome in the next steps; nothing to do: the clock runs on further, the suite's time on
		# CI is bounded)
		var played: bool = await _play(tree, ui, log)
		ui.clock.run_steps(10 if played else 60)
		if i % 8 == 0:
			await tree.process_frame       # (the panels' old rows are freed at the frame's end)
	return done.call()


static func _has_ev(e, want: Array) -> bool:
	for ev in e.events:
		var ok: bool = ev.size() > want.size()
		for i in want.size():
			if ok and want[i] != null and ev[1 + i] != want[i]:
				ok = false
		if ok:
			return true
	return false


static func _where(e, msg: String) -> String:
	var pi: int = e.st_trainee
	var cur = e.sp_cur[pi]
	return "%s (the trainee's task %s step %s)" % [msg, str(cur["task"]) if cur else "none",
			str(cur["step"]) if cur else ""]


func _operator_backwash(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has(SID):
		main.free()
		return ["the app or its scenario %s did not start" % SID]
	ui.player.set_physics_process(false)
	var why: String = await _take(tree, ui, "Play WTP, crew A (coming on shift)")
	if why != "":
		main.free()
		return [why]
	var e = ui.clock.engine
	ui.crew._sig = ""
	ui.crew.refresh()
	if not App.texts(ui.crew).contains("WTP round"):
		p.append("the WTP operator's day in the Crew panel has no WTP round: %s" % App.texts(ui.crew).left(400))
	var log := []
	var done := func(): return _has_ev(e, ["task", "a_wtp", "backwash_1", "done"])
	if not await _steps(tree, ui, done, 1500, log):
		main.free()
		return p + log.slice(0, 3) + [_where(e, "the trainee did not finish filter 1's backwash by %s" % ui.clock_text())]
	p += log.slice(0, 3)
	for want in [["task", "a_sup", "order_backwash_1", "start"], ["call", "a_sup", "wtp_op", "backwash_1", null, "done"],
			["task", "a_wtp", "backwash_1", "start"], ["op", FILTER, "backwash", "done", [], "screen", "a_wtp"],
			["say", "a_wtp", "backwash_done", "shift_sup"]]:
		if not _has_ev(e, want):
			p.append("no event like %s" % str(want))
	if e.v("fl1_hl") >= 0.5:
		p.append("filter 1's head loss is %.2f m after its backwash" % e.v("fl1_hl"))
	# the supervisor's order reached the trainee's radio
	ui.crew._sig = ""
	ui.crew.refresh()
	if not App.texts(ui.crew).contains("A filter is due: backwash it"):
		p.append("the radio log does not show the supervisor's order: %s" % App.texts(ui.crew).left(400))
	# the debrief's own tab lists it
	ui.open_debrief()
	ui.debrief._tab("role")
	if not App.texts(ui.debrief).contains("Backwash filter 1"):
		p.append("the debrief's Your tasks tab does not list the backwash: %s" % App.texts(ui.debrief).left(300))
	ui.close_debrief()
	main.free()
	return p


func _chemist_silica(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	ui.player.set_physics_process(false)
	var why: String = await _take(tree, ui, "Play Chemist, crew A (coming on shift)")
	if why != "":
		main.free()
		return [why]
	var e = ui.clock.engine
	ui.crew._sig = ""
	ui.crew.refresh()
	if not App.texts(ui.crew).contains("Samples"):
		p.append("the shift chemist's day in the Crew panel has no samples: %s" % App.texts(ui.crew).left(400))
	var log := []
	var found := func(): return _has_ev(e, ["read", "a_chem", SILICA, null, "out_of_range"])
	if not await _steps(tree, ui, found, 1500, log):
		main.free()
		return p + log.slice(0, 3) + [_where(e, "the trainee's sample did not log the silica out of range by %s"
				% ui.clock_text())]
	ui.crew._sig = ""
	ui.crew.refresh()
	if not App.texts(ui.crew).contains("OUT OF RANGE"):
		p.append("the readings sheet does not mark the silica out of range: %s" % App.texts(ui.crew).left(400))
	var reads: Array = e.events.filter(func(ev): return ev[1] == "read" and ev[2] == "a_chem")
	if reads.filter(func(ev): return ev[5] == "misread").size() > 0:
		p.append("a reading written down as shown was misread: %s" % str(reads))
	# the NPC WTP operator acts on the finding: the beds changed over, bed A's regeneration started
	var regen := func(): return _has_ev(e, ["op", BED, "regenerate", "done", [], "screen", "a_wtp"])
	if not await _steps(tree, ui, regen, 600, log):
		main.free()
		return p + log.slice(0, 3) + ["the NPC WTP operator did not start bed A's regeneration by %s" % ui.clock_text()]
	p += log.slice(0, 3)
	for want in [["task", "a_wtp", "mb_regen_a", "start"], ["op", "00GCF12AT001", "in_service", "done", [], "screen",
			"a_wtp"], ["machine", "mb_a", "standby", "backwash", "command"]]:
		if not _has_ev(e, want):
			p.append("no event like %s" % str(want))
	_save(ui, p)
	main.free()
	return p


## The run with the regeneration under way goes round a save and on bit for bit (and a clone).
func _save(ui, p: Array) -> void:
	var e = ui.clock.engine
	var fields := RunSave.engine_fields(e)
	var data := RunSave.capture(e, fields)
	var f2 = PlantEngine.new(ui.model, e.sc)
	var bad := RunSave.check(f2, RunSave.engine_fields(f2), data)
	if bad != "":
		p.append("a fresh engine refuses the save: " + bad)
		return
	RunSave.apply(f2, bytes_to_var(var_to_bytes(data)))
	var c = e.clone()
	for k in 600:
		e.step()
		f2.step()
		c.step()
	if var_to_bytes(e.snapshot()) != var_to_bytes(f2.snapshot()) or var_to_bytes(e.events) != var_to_bytes(f2.events):
		p.append("the restored run with the regeneration under way differs from the uninterrupted one")
	if var_to_bytes(e.snapshot()) != var_to_bytes(c.snapshot()):
		p.append("a clone with the regeneration under way went on differently")
