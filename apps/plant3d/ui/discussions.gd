## The discussions as the trainee sees them (docs/plant3d/REALISM.md §6.3.1, milestone DC3), text only: the panel in
## the crew panel while their person takes part in a discussion or is in its room (the opening lines, each option's
## lines as points are taken, the agreement's lines and outcome; for a participant in mode `open` the current point's
## options with their evidence and the time left), the lines in the radio log, and the debrief's list. Lines are not
## events (§6.3.2): they are read from discussions.json at the engine's `discussion` and `point` events.
extends RefCounted

const Disc = preload("res://sim/discuss.gd")
const W = preload("res://ui/widgets.gd")

const KIND_WORDS := {"manual": "Manual", "standard": "Standard", "reading": "Reading", "rule": "Site rule"}


## Who says a line of `role` in an instance whose participants (ids in role order, null none) are `parts`: the
## participant's call, else the role's title.
static func speaker(sm, d: Dictionary, parts: Array, role: String) -> String:
	var k: int = d["roles"].find(role)
	if k >= 0 and k < parts.size() and parts[k] != null and sm.person_ix.has(parts[k]):
		return sm.people[sm.person_ix[parts[k]]]["call"]
	return sm.roles[role]["title"] if sm.roles.has(role) else role


## The lines one event adds, [[speaker, text]] (none for an event that isn't a discussion's). `parts` holds each
## discussion id's participants at its last start, kept by the caller across events.
static func event_lines(sm, ev: Array, parts: Dictionary) -> Array:
	if sm == null or sm.discuss == null or ev.size() < 3 or not (ev[1] in ["discussion", "point"]):
		return []
	var di: int = sm.discuss["ix"].get(ev[2], -1)
	if di < 0:
		return []
	var d: Dictionary = sm.discuss["list"][di]
	var out := []
	if ev[1] == "discussion" and ev[3] == "start":
		parts[ev[2]] = ev[5]
		for t in d["turns"]:
			out.append([speaker(sm, d, ev[5], t["role"]), t["text"]])
	elif ev[1] == "point":
		var k: int = d["_pix"].get(ev[3], -1)
		var oi: int = d["_opt"][k].get(ev[4], -1) if k >= 0 else -1
		if oi < 0:
			return []
		var pt: Dictionary = d["points"][k]
		var p: Array = parts.get(ev[2], [])
		var who: String
		if ev[5] != null and sm.person_ix.has(ev[5]):
			who = sm.people[sm.person_ix[ev[5]]]["call"]
		else:           # a default: said by the point's role, else the lead
			who = speaker(sm, d, p, pt.get("role", d["roles"][0]))
		for ln in pt["options"][oi]["lines"]:
			out.append([who if ln["role"] == "$" else speaker(sm, d, p, ln["role"]), ln["text"]])
	elif ev[1] == "discussion" and ev[3] == "agreed":
		var a: Dictionary = d["agreements"][ev[4]]
		for ln in a["lines"]:
			out.append([speaker(sm, d, parts.get(ev[2], []), ln["role"]), ln["text"]])
		out.append(["Agreed", a["outcome"]["text"]])
	return out


## Every discussion of the run in its first `to` events (-1 all), in the order they started: [{id, title, start, parts (ids),
## taken: [[point id, option id, taker id or null]], outcome (text or null while unended), lines: [[step, who,
## text]]}].
static func review(engine, to: int = -1) -> Array:
	var sm = engine._sm
	var out := []
	if sm == null or sm.discuss == null:
		return out
	var parts := {}
	var open := {}          # id -> its instance's index in out
	var evs: Array = engine.events
	for i in (evs.size() if to < 0 else mini(to, evs.size())):
		var ev: Array = evs[i]
		if not (ev[1] in ["discussion", "point"]):
			continue
		var lines := event_lines(sm, ev, parts)
		if ev[1] == "discussion" and ev[3] == "start":
			var d: Dictionary = sm.discuss["list"][sm.discuss["ix"][ev[2]]]
			open[ev[2]] = out.size()
			out.append({"id": ev[2], "title": d["title"], "start": ev[0], "parts": ev[5], "taken": [], "outcome": null,
					"lines": []})
		if not open.has(ev[2]):
			continue
		var x: Dictionary = out[open[ev[2]]]
		if ev[1] == "point":
			x["taken"].append([ev[3], ev[4], ev[5]])
		elif ev[3] == "agreed":
			x["outcome"] = sm.discuss["list"][sm.discuss["ix"][ev[2]]]["agreements"][ev[4]]["outcome"]["text"]
		for ln in lines:
			x["lines"].append([ev[0], ln[0], ln[1]])
	return out


## The debrief's lines: each discussion, who took which option, and its outcome.
static func debrief_lines(sm, rv: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if rv.is_empty():
		return out
	out.append("Discussions: %d" % rv.size())
	for x in rv:
		var d: Dictionary = sm.discuss["list"][sm.discuss["ix"][x["id"]]]
		var picks := PackedStringArray()
		for t in x["taken"]:
			var k: int = d["_pix"][t[0]]
			var o: Dictionary = d["points"][k]["options"][d["_opt"][k][t[1]]]
			var by: String = sm.people[sm.person_ix[t[2]]]["call"] if t[2] != null and sm.person_ix.has(t[2]) \
					else "nobody picked: the default"
			picks.append("%s (%s)" % [o["text"], by])
		out.append("  %s: %s → %s" % [x["title"], "; ".join(picks) if not picks.is_empty() else "no point taken",
				x["outcome"] if x["outcome"] != null else "not agreed"])
	return out


## The discussion whose panel the trainee (person pi) sees: a live one they take part in or whose room they are in,
## else the last one they took part in or were in the room of, ended, while they are still in its room and haven't
## closed it (`closed`: "id|count" keys). -1 none.
static func shown(e, pi: int, closed: Dictionary) -> int:
	var sm = e._sm
	if sm == null or sm.discuss == null or pi < 0:
		return -1
	var best := -1
	for di in e.dsc.size():
		var x: Dictionary = e.dsc[di]
		if x.is_empty():
			continue
		var d: Dictionary = sm.discuss["list"][di]
		var here: bool = e.sp_pos[pi] != -1 and sm.rooms[d["room"]].has(e.sp_pos[pi])
		if Disc._live(e, d, x):
			if x["parts"].has(pi) or here:
				return di
		elif here and x["agreed"] >= 0 and not closed.has("%s|%d" % [d["id"], x["count"]]) \
				and (best == -1 or x["start"] > e.dsc[best]["start"]):
			best = di
	return best


## What the panel shows depends on: the discussions' state and where the trainee is.
static func sig(e, pi: int, closed: Dictionary) -> String:
	if e._sm == null or e._sm.discuss == null or pi < 0:
		return ""
	return "%d/%d/%d" % [shown(e, pi, closed), e.dsc.hash(), closed.size()]


## The clock time (HH:MM) at step `at`.
static func _hhmm(e, at: int) -> String:
	var t: int = e.clock() + (at - e.step_no) * int(e._ds)
	var s: int = (t % 864000) / 10
	return "%02d:%02d" % [s / 3600, (s / 60) % 60]


## One piece of evidence as a line (and a button for a manual's section).
static func _evidence(ui, e, box: Control, v: Dictionary) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var text := "%s: %s" % [KIND_WORDS.get(v["kind"], v["kind"]), v["text"]]
	if v["kind"] == "standard":
		text = "%s [%s]: %s" % [KIND_WORDS["standard"], v["cite"], v["text"]]
	elif v["kind"] == "reading":
		var now := ""
		if e.ix.has(v["value"]):
			now = " Now: %s (%s)." % ["yes" if e.truth(v["value"]) else "no", _shown_text(e, v["code"])]
		text = "%s at %s: %s%s" % [KIND_WORDS["reading"], v["code"], v["text"], now]
	var l := W.label("  • " + text, 16, W.DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if v["kind"] == "manual" and ui.manuals != null and ui.manuals.has(v["manual"]):
		var mid: String = v["manual"]
		var sec: String = v["section"]
		row.add_child(W.button("Open", func(): ui.open_manual(mid, sec)))


static func _shown_text(e, code: String) -> String:
	var f: float = e.shown(code, e.cur)
	return ("%.1f" % f).trim_suffix(".0") if is_finite(f) else "–"


## The panel, built into box for the trainee's person pi: the discussion `di` (shown()).
static func build(ui, e, box: Control, di: int, pi: int, close: Callable) -> void:
	var sm = e._sm
	var d: Dictionary = sm.discuss["list"][di]
	var x: Dictionary = e.dsc[di]
	var live := Disc._live(e, d, x)
	var panel := VBoxContainer.new()
	panel.name = "discussion"
	box.add_child(panel)
	panel.add_child(W.label("Discussion: " + d["title"], 20, Color(0.55, 0.8, 1.0)))
	if d.has("topic") and e.m.work_ix.has(d["topic"]):
		panel.add_child(W.label("About: " + e.m.works[e.m.work_ix[d["topic"]]]["title"], 16, W.DIM))
	var ids := []
	for i in x["parts"]:
		ids.append(sm.people[i]["id"] if i >= 0 else null)
	for pos in d["positions"]:
		panel.add_child(W.label("%s: %s" % [speaker(sm, d, ids, pos["role"]), pos["claim"]], 16))
	# the lines so far, from this instance's start
	var parts := {}
	var lines := []
	for ev in e.events:
		if ev[0] < x["start"] or not (ev[1] in ["discussion", "point"]) or ev[2] != d["id"]:
			continue
		lines.append_array(event_lines(sm, ev, parts))
	for ln in lines:
		panel.add_child(W.label("%s: %s" % [ln[0], ln[1]], 16, Color(0.9, 0.9, 0.75)))
	if not live:
		var row := HBoxContainer.new()
		var cb := W.button("Close", close)
		cb.name = "disc_close"
		row.add_child(cb)
		panel.add_child(row)
		return
	if x["mode"] != 1 or not x["parts"].has(pi):
		panel.add_child(W.label("Between the others: you follow it." if not x["parts"].has(pi)
				else "Under way; it ends at %s." % _hhmm(e, int(x["start"]) + int(d["minutes"]) * sm.tpm), 16, W.DIM))
		return
	var k: int = x["point"]
	if k >= d["points"].size():
		return
	var pt: Dictionary = d["points"][k]
	var dflt: String = pt["options"][d["_opt"][k][pt["default"]]]["text"]
	panel.add_child(W.label("Your say (point %d of %d), until %s; then «%s» stands:" % [k + 1, d["points"].size(),
			_hhmm(e, int(x["since"]) + int(pt["minutes"]) * sm.tpm), dflt], 16, W.DIM))
	var ev_ix := {}
	for v in d["evidence"]:
		ev_ix[v["id"]] = v
	for o in pt["options"]:
		var side := ""
		if o.has("side"):
			side = " (with %s)" % speaker(sm, d, ids, o["side"])
		var b := W.button(o["text"] + side, func(): ui.inputs.discuss(d["id"], pt["id"], o["id"]))
		b.name = "disc_" + o["id"]
		panel.add_child(b)
		for eid in o.get("evidence", []):
			_evidence(ui, e, panel, ev_ix[eid])
