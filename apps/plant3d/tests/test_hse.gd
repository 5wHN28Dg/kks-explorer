## JSAs and toolbox talks in the app (docs/plant3d/REALISM.md §8.6, milestone HS1):
## - the first train's library (built/content/hse.json) read by the engine with its titles, every work with a job kind;
## - the permit form of a work with a job kind: its JSA section and talk section; the JSA's picker lists every hazard
##   and control with nothing picked, and sends the picked ones in the library's order as the player's; the talk's
##   picker marks the JSA's hazards and sends the points; a refusal comes back in words (the `jsa` reason);
## - the debrief's review: a JSA against the job's own list (hazards missed, controls missing, ones the job doesn't
##   have), a talk's points against the JSA and the job, a job accepted by someone not at a talk of its permit (an
##   unsafe-act observation when it is the player's), a cancel ending the permit's JSA and attendance; the summary;
## - a saved run's JSAs and attendance checked against the content.
## The engine's own rules are the vectors' (plant3d-realism.json, part hse); here the app's side.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Debrief = preload("res://ui/debrief.gd")
const Permits = preload("res://ui/permits.gd")
const RunSave = preload("res://ui/run_save.gd")

const WORK := "wo_cw_b_motor"      # a mechanical motor's bearings: motor_bearings


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	var e = ui.clock.engine
	p += _library(e)
	p += await _form(tree, ui)
	p += _review(ui)
	p += _saves(ui)
	main.free()
	return p


func _library(e) -> Array:
	var p: Array = []
	if e.m.hse == null:
		return ["the first train's hse.json was not read"]
	for w in e.m.works:
		if not w.has("jsa") or not e.m.hse["own"].has(w["jsa"]):
			p.append("work %s has no job kind of the library" % w["id"])
	var own: Array = Permits.own_list(e, WORK)
	if own.is_empty() or own[0][0] != "rotating" or not (own[1] as Array).has("loto"):
		p.append("the bearings' own list is %s" % str(own))
	if Permits.hse_title(e, "h", "rotating") != "The machine started or turned while hands are in it":
		p.append("a hazard's title: %s" % Permits.hse_title(e, "h", "rotating"))
	return p


func _form(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var e = ui.clock.engine
	ui.clock.set_speed(App.SimClock.Speed.PAUSED)
	var pm = ui.permits
	ui.open_permits(WORK)
	await tree.process_frame
	pm.refresh()
	var txt: String = App.texts(pm.body)
	for want in ["Job safety analysis", "None yet", "Toolbox talk", "Not given yet"]:
		if not txt.contains(want):
			p.append("the form lacks %s: %s" % [want, txt.left(400)])
	var sent: Array = []
	ui.inputs.sink = func(item): sent.append(item)
	var b = pm.body.find_child("do_jsa", true, false)
	if not b is Button or b.disabled:
		ui.inputs.sink = Callable()
		return p + ["no Make the JSA on the form: %s" % txt.left(300)]
	b.pressed.emit()
	var n_hz := 0
	var n_cs := 0
	var picked := 0
	for c in pm.body.find_children("*", "CheckBox", true, false):
		if c.name.begins_with("hz_"):
			n_hz += 1
		elif c.name.begins_with("cs_"):
			n_cs += 1
		if c.button_pressed:
			picked += 1
	if n_hz != e.m.hse["hazards"].size() or n_cs != e.m.hse["controls"].size() or picked != 0:
		p.append("the JSA's picker: %d hazards, %d controls, %d picked" % [n_hz, n_cs, picked])
	# picked out of the library's order: sent in its order
	for n in ["cs_guards", "hz_pinch", "hz_rotating", "cs_loto"]:
		(pm.body.find_child(n, true, false) as CheckBox).button_pressed = true
	(pm.body.find_child("send_pick", true, false) as Button).pressed.emit()
	if str(sent) != str([["jsa", WORK, ["rotating", "pinch"], ["loto", "guards"], null]]):
		p.append("the JSA sent %s" % str(sent))
	ui.inputs.sink = Callable()
	if not pm.pick.is_empty() or pm.body.find_child("do_jsa", true, false) == null:
		p.append("after sending, the form is not back")
	# for real: the JSA made (no permit yet: state 0 takes one), the permit requested, the talk's picker marks it
	ui.inputs.jsa(WORK, ["rotating", "pinch"], ["loto", "guards"], null)
	ui.inputs.permit(WORK, "request", null)
	ui.clock.run_steps(1)
	ui._sync_events()
	pm.refresh()
	var t = pm.body.find_child("do_talk", true, false)
	if not t is Button or t.disabled:
		return p + ["no Give the toolbox talk once the JSA is made and the permit requested: %s" % App.texts(pm.body).left(300)]
	t.pressed.emit()
	var marked: String = (pm.body.find_child("hz_rotating", true, false) as CheckBox).text
	if not marked.contains("(in the JSA)") or (pm.body.find_child("hz_noise", true, false) as CheckBox).text.contains("(in the JSA)"):
		p.append("the talk's picker marks the JSA's hazards wrongly: %s" % marked)
	if pm.body.find_child("cs_loto", true, false) != null:
		p.append("the talk's picker offers controls")
	sent.clear()
	ui.inputs.sink = func(item): sent.append(item)
	(pm.body.find_child("hz_rotating", true, false) as CheckBox).button_pressed = true
	(pm.body.find_child("send_pick", true, false) as Button).pressed.emit()
	ui.inputs.sink = Callable()
	if str(sent) != str([["talk", WORK, ["rotating"], null]]):
		p.append("the talk sent %s" % str(sent))
	# a refusal in words: a talk on a work without a JSA
	var ev := [5, "talk", "wo_cw_a_motor", ["rotating"], null, "refused", ["jsa"], []]
	var words := Permits.hse_text(e, ev)
	if not words.contains("refused") or not words.contains("no job safety analysis"):
		p.append("a talk refused for want of a JSA reads: %s" % words)
	ui.close_permits()
	return p


## The debrief's review, from events made by hand (the run itself is the vectors').
func _review(ui) -> Array:
	var p: Array = []
	var e = ui.clock.engine
	var evs := [
		[10, "jsa", WORK, ["rotating", "noise", "debris"], ["loto"], "me", "done", []],
		[11, "permit", WORK, "request", "me", "done", []],
		[12, "talk", WORK, ["rotating"], "me", "done", [], ["me", "tech"]],
		[13, "permit", WORK, "accept", "tech", "done", []],
		[14, "permit", "wo_cw_a_motor", "accept", "me", "done", []],
		[15, "permit", WORK, "cancel", "sup", "done", []],
		[16, "permit", WORK, "request", "me", "done", []],
		[17, "permit", WORK, "accept", "tech", "done", []],
	]
	var h := Debrief.hse_review(e, "me", evs, evs.size())
	var own: Array = Permits.own_list(e, WORK)
	var want_missed: int = own[0].size() - 2          # (rotating and noise named, debris not the job's)
	if h.jsas != 1 or h.mine != 1 or h.missed != want_missed or h.lacking != own[1].size() - 1:
		p.append("the review counted %s" % str(h))
	if not String(h["at"][0][0]).contains("hazards of the job missed") or not String(h["at"][0][0]).contains("1 named that the job doesn't have") \
			or not h["at"][0][1]:
		p.append("the JSA's review reads %s" % str(h["at"].get(0)))
	if not String(h["at"][2][0]).begins_with("points: 1 of the JSA's 3 hazards, 1 of the job's"):
		p.append("the talk's review reads %s" % str(h["at"].get(2)))
	if h["at"].has(3):
		p.append("an acceptor who attended the talk is marked: %s" % str(h["at"][3]))
	if h.no_talk != 2 or h.no_talk_me != 1 or not h["at"].has(4) or not h["at"][4][1] or not h["at"].has(7) \
			or h["at"][7][1]:
		p.append("jobs started without a talk: %s" % str(h))
	var lines := Debrief.hse_lines(h)
	if lines.size() != 2 or not lines[0].begins_with("JSAs: 1 made (yours 1:") or not lines[1].contains("1 of them yours"):
		p.append("the summary reads %s" % str(lines))
	if not Debrief.hse_lines(Debrief.hse_review(e, "me", [], 0)).is_empty():
		p.append("a run without JSAs has a JSA line")
	return p


func _saves(ui) -> Array:
	var p: Array = []
	var e = ui.clock.engine
	var pl: Dictionary = ui.autosave.payload()
	var why: String = ui.autosave.check(pl)
	if why != "":
		return ["a run with a JSA and a talk was refused: " + why]
	for bad in [{"jsa_of": {"wo_x": [["rotating"], [], null]}}, {"jsa_of": {WORK: [["bees"], [], null]}},
			{"jsa_of": {WORK: [["rotating"], ["loto", "loto"], null]}}, {"jsa_of": {WORK: [["rotating"], [], "nobody"]}},
			{"talked": {WORK: [3, 2]}}, {"talked": {WORK: [999]}}, {"talked": {WORK: []}}]:
		var d: Dictionary = pl.duplicate(true)
		for k in bad:
			d["engine"][k] = bad[k]
		if ui.autosave.check(d) == "":
			p.append("a save with %s was accepted" % str(bad))
	return p
