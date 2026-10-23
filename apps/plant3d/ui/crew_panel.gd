## The crews (docs/PLANT3D.md §18.7, milestone S1): the trainee's role, their task list and the radio.
##   Role: at the start of a shift (a scenario with staff, before its first step) the roles a trainee may play, with
##         the people on duty in each; or free mode (no role: every authority, as format 1).
##   Tasks: the current task's steps with the one to do now (a place to go to and "Take me there", a reading to write
##         down, a message to send, a call to make, a choice), the tasks waiting, what is new since the last look
##         ("Seen" is the task_ack input that lets fast-forward run again, §17.6), and the round's readings sheet.
##   Radio: the messages and calls between the roles (the events `say` and `call`), the trainee's own messages and
##         requests (the calls the content makes to other roles), and "Sleep to the next shift" (a jump) when allowed.
## Everything goes to the engine as an input; nothing here changes the plant itself. Touch, keyboard and gamepad:
## every control is a button or a line edit that takes the focus (Esc or B closes, as the other panels).
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const SimClock = preload("res://ui/sim_clock.gd")

var ui                          # ui/plant_ui.gd
var body: VBoxContainer
var title: Label
var entry: LineEdit             # the reading being written down (tests type into it)
var _sig := ""
var _t := 0.0


func setup(u) -> void:
	ui = u
	var parts := W.panel("Crew", func(): ui.close_crew())
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	title = parts[2]
	visible = false


func open() -> void:
	visible = true
	_sig = ""
	refresh()
	if ui.wants_focus():
		var b := _first(body)
		if b:
			b.grab_focus.call_deferred()


func _first(n: Node) -> Control:
	for c in n.get_children():
		if (c is Button and not c.disabled) or c is LineEdit:
			return c
		var f := _first(c)
		if f:
			return f
	return null


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


## What the panel shows, as text: rebuilt only when it changes (a typed reading is kept).
func _signature(e) -> String:
	var sm = e._sm
	if sm == null:
		return "none"
	var tr: int = e.st_trainee
	var cur = e.sp_cur[tr] if tr != -1 else null
	return "%d|%d|%s|%s|%d|%d|%d|%s|%d" % [tr, e.step_no if tr == -1 and e.step_no < 2 else 0,
			str(cur["task"]) + str(cur["step"]) + str(cur["st"].get("dest", "")) if cur != null else "",
			str(e.sp_queue[tr].size()) if tr != -1 else "", e.st_unacked, e.events.size() / 50 if tr == -1 else
			_radio_count(e), e.st_t_at, str(e.fast_forward()), e.J]


func _radio_count(e) -> int:
	var c := 0
	for ev in e.events:
		if ev[1] == "say" or ev[1] == "call" or ev[1] == "read":
			c += 1
	return c


func refresh() -> void:
	var e = ui.clock.engine
	var sig := _signature(e)
	if sig == _sig:
		return
	_sig = sig
	W.clear(body)
	var sm = e._sm
	if sm == null:
		body.add_child(W.label("No crews in this run: the plant as format 1, the trainee alone.", 18, W.DIM))
		for sid in ui.model.scenarios:
			if ui.model.scenarios[sid].has("staff"):
				var s := sid as String
				body.add_child(W.button("Start: " + ui.model.scenarios[s].get("title", s), func(): ui.start_shift(s)))
		return
	if e.st_trainee == -1:
		_roles(e, sm)
	else:
		_me(e, sm)
	_radio(e, sm)


# ------------------------------------------------------------------ role selection (§17.4)

func _roles(e, sm) -> void:
	if e.step_no > 0 or e._fixed_trainee:
		body.add_child(W.label("Free mode: you hold every authority; the crews work around you. A role is taken at "
				+ "the start of a shift.", 18, W.DIM))
		return
	body.add_child(W.label("Choose your role for this shift (the people on duty or coming on):", 18))
	for rid in sm.roles:
		var r: Dictionary = sm.roles[rid]
		if not r["play"]:
			continue
		body.add_child(W.label(r["title"], 20, Color(1.0, 0.85, 0.4)))
		var any := false
		for pi in sm.people.size():
			var p: Dictionary = sm.people[pi]
			if p["role"] != rid or e._absent.has(pi):
				continue
			var on: bool = e.sp_on[pi] or not e.sp_slots[pi].is_empty() and e.sp_slots[pi][0][0] <= e.clock() + 3600 * 10
			if not on:
				continue
			any = true
			var pid: String = p["id"]
			body.add_child(W.button("Play " + p["call"] + ("" if e.sp_on[pi] else " (coming on shift)"),
					func(): ui.take_role(pid)))
		if not any:
			body.add_child(W.label("Nobody of this role on duty now.", 16, W.DIM))
	body.add_child(W.button("Free mode (no role)", func(): ui.take_role("")))


# ------------------------------------------------------------------ the trainee's tasks (§18.7)

func _me(e, sm) -> void:
	var pi: int = e.st_trainee
	var p: Dictionary = sm.people[pi]
	title.text = "Crew: you are %s" % p["call"]
	var duty := "on duty" if e.sp_on[pi] else "off duty"
	body.add_child(W.label("%s, %s, %s" % [sm.roles[p["role"]]["title"], duty, ui.clock_text()], 18, W.DIM))
	if e.st_unacked > 0:
		var row := HBoxContainer.new()
		row.add_child(W.label("%d new for you" % e.st_unacked, 20, Color(1.0, 0.75, 0.2)))
		row.add_child(W.button("Seen", func(): ui.clock.engine.task_ack()))
		body.add_child(row)
	var cur = e.sp_cur[pi]
	if cur == null:
		body.add_child(W.label("No task now.", 18, W.DIM))
	else:
		_task(e, sm, cur)
	var q: Array = e.sp_queue[pi]
	if not q.is_empty():
		body.add_child(W.label("Waiting:", 18, W.DIM))
		for inst in q:
			body.add_child(W.label("• " + sm.tasks[inst["task"]]["title"] + " (priority %d)" % inst["prio"], 18))
	var reads := []
	for ev in e.events:
		if ev[1] == "read" and ev[2] == p["id"]:
			reads.append(ev)
	if not reads.is_empty():
		body.add_child(W.label("Readings sheet:", 18, W.DIM))
		for ev in reads.slice(maxi(0, reads.size() - 12)):
			var c := W.OK_COLOUR if ev[5] == "ok" else W.BAD_COLOUR
			body.add_child(W.label("%s  %s  %s" % [ev[3], _num(ev[4]), {"ok": "in range", "out_of_range":
					"OUT OF RANGE", "misread": "misread (the gauge shows another value)"}[ev[5]]], 18, c))


static func _num(x) -> String:
	return ("%.2f" % x) if typeof(x) == TYPE_FLOAT else str(x)


func _task(e, sm, cur: Dictionary) -> void:
	var t: Dictionary = sm.tasks[cur["task"]]
	body.add_child(W.label("Now: " + t["title"], 22, Color(1.0, 0.85, 0.4)))
	var steps: Array = t["steps"]
	for k in steps.size():
		var mark := "▶ " if k == cur["step"] else ("✓ " if k < cur["step"] else "· ")
		var l := W.label(mark + describe(e, sm, cur, steps[k]), 18, Color.WHITE if k == cur["step"] else W.DIM)
		body.add_child(l)
		if k == cur["step"]:
			_controls(e, sm, cur, steps[k])


## A step in words.
func describe(e, sm, cur: Dictionary, s: Dictionary) -> String:
	if s.has("go"):
		var dest = cur["st"].get("dest")
		var where: String = sm.places[dest]["id"] if dest != null and k_is_cur(cur, s, sm) else _go_text(sm, cur, s["go"])
		return "Go to %s" % _place_name(sm, where)
	if s.has("work"):
		return "Work there %s clock min" % (str(s["work"]) if typeof(s["work"]) != TYPE_ARRAY else "%d–%d" % s["work"])
	if s.has("read"):
		var ex = s.get("expect")
		return "Read %s %s" % [s["read"], ("(expected %s to %s)" % [_num(ex[0]), _num(ex[1])]) if ex != null else ""]
	if s.has("say"):
		return "Radio to %s: \"%s\"" % [s["to"], sm.messages[s["say"]]]
	if s.has("call"):
		return "Call %s: %s" % [s["call"]["role"], sm.tasks[s["call"]["task"]]["title"]]
	if s.has("op"):
		return "%s %s (%s)" % [s["op"]["do"].replace("_", " "), s["op"]["kks"], s["op"]["where"]]
	if s.has("permit"):
		var w = cur["work"] if s["permit"]["work"] == "$" else s["permit"]["work"]
		return "Permit: %s %s" % [s["permit"]["action"], str(w)]
	if s.has("lock") or s.has("unlock"):
		var k := "lock" if s.has("lock") else "unlock"
		return "%s point %s of %s" % [k.capitalize(), str(s[k]["point"]), str(cur["work"] if s[k]["work"] == "$" else s[k]["work"])]
	if s.has("wait"):
		return "Wait: " + (str(s["wait"].get("until")) if s["wait"].has("until") else "permit %s" % str(s["wait"]["permit"]))
	if s.has("meet"):
		return "Meet in the %s" % String(s["meet"]["room"]).replace("_", " ")
	if s.has("choose"):
		return "Choose what next"
	if s.has("ack"):
		return "Acknowledge the alarm %s" % str(cur["alarm"])
	return str(s)


func k_is_cur(cur: Dictionary, s: Dictionary, sm) -> bool:
	return sm.tasks[cur["task"]]["steps"][cur["step"]] == s


func _go_text(sm, cur: Dictionary, x) -> String:
	if typeof(x) == TYPE_STRING:
		return x
	if x.has("kks"):
		var code = cur["code"] if x["kks"] == "$" else x["kks"]
		return "w_" + str(code).to_lower()
	return "%s in the %s" % [x["kind"], x["room"]]


static func _place_name(sm, pid: String) -> String:
	if not sm.pix.has(pid):
		return pid.replace("_", " ")
	var pl: Dictionary = sm.places[sm.pix[pid]]
	if pl["kind"] == "work":
		return pl["kks"]
	return pid.replace("_", " ")


func _controls(e, sm, cur: Dictionary, s: Dictionary) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	if s.has("go") or s.has("meet") or s.has("lock") or s.has("unlock"):
		var dest = cur["st"].get("dest", cur["st"].get("place"))
		if s.has("lock") or s.has("unlock"):
			dest = null
		if dest != null:
			var d: int = dest
			if e.st_t_at == d:
				row.add_child(W.label("You are there.", 18, W.OK_COLOUR))
			else:
				row.add_child(W.button("Take me there", func(): ui.go_to_place(d)))
	if s.has("read"):
		entry = LineEdit.new()
		entry.placeholder_text = "the value shown"
		entry.custom_minimum_size.x = 160 * W.scale
		row.add_child(entry)
		var code: String = s["read"]
		row.add_child(W.button("Write down", func(): ui.write_reading(code, entry.text)))
	if s.has("say"):
		var msg: String = s["say"]
		var to: String = s["to"]
		row.add_child(W.button("Send", func(): ui.clock.engine.say(msg, to)))
	if s.has("call"):
		var c: Dictionary = s["call"]
		row.add_child(W.button("Call", func(): ui.clock.engine.radio_call(c["role"], c["task"], c.get("work"))))
	if s.has("choose"):
		for k in s["choose"].size():
			var kk: int = k
			row.add_child(W.button(sm.tasks[s["choose"][k][1]]["title"], func(): ui.clock.engine.pick(kk)))
	if s.has("ack") and cur["alarm"] != null:
		var a: String = cur["alarm"]
		row.add_child(W.button("Acknowledge", func(): ui.ack(a)))
	if s.has("permit") or s.has("lock") or s.has("unlock"):
		var k := "permit" if s.has("permit") else ("lock" if s.has("lock") else "unlock")
		var w = cur["work"] if s[k]["work"] == "$" else s[k]["work"]
		if w != null:
			var ws: String = w
			row.add_child(W.button("Permit form", func(): ui.open_permits(ws)))
	if s.has("op"):
		var code: String = s["op"]["kks"]
		row.add_child(W.button("Take me there", func(): ui.fly_to(code)))


# ------------------------------------------------------------------ the radio (§18.7)

func _radio(e, sm) -> void:
	body.add_child(W.label("Radio", 20, Color(1.0, 0.85, 0.4)))
	var lines := []
	for ev in e.events:
		if ev[1] == "say":
			lines.append("%s  %s → %s: %s" % [_at(e, ev[0]), _call(sm, ev[2]), _to(sm, ev[4]), sm.messages.get(ev[3], ev[3])])
		elif ev[1] == "call" and ev[6] == "done":
			lines.append("%s  %s → %s: %s" % [_at(e, ev[0]), _call(sm, ev[2]), _to(sm, ev[3]),
					sm.tasks[ev[4]]["title"] if sm.tasks.has(ev[4]) else ev[4]])
	for l in lines.slice(maxi(0, lines.size() - 10)):
		body.add_child(W.label(l, 16))
	if e.st_trainee == -1:
		return
	var me: Dictionary = sm.people[e.st_trainee]
	var row := HFlowContainer.new()
	body.add_child(row)
	for key in sm.callable:
		var parts: PackedStringArray = String(key).split("\n")
		if parts[0] == me["role"]:
			continue
		var role := parts[0]
		var task := parts[1]
		row.add_child(W.button("Call %s: %s" % [role.replace("_", " "), sm.tasks[task]["title"]],
				func(): ui.clock.engine.radio_call(role, task, null)))
	var nxt := _next_shift(e)
	var b := W.button("Sleep to %s" % nxt, func(): ui.clock.engine.jump(nxt))
	b.disabled = not e.fast_forward()
	body.add_child(b)


func _next_shift(e) -> String:
	var t: int = e.clock() % 864000
	return "18:00" if t >= 6 * 36000 and t < 18 * 36000 else "06:00"


static func _at(e, step: int) -> String:
	var t: int = e._S + step * e._ds + e.J
	var s: int = (t % 864000) / 10
	return "%02d:%02d" % [s / 3600, (s / 60) % 60]


static func _call(sm, pid) -> String:
	return sm.people[sm.person_ix[pid]]["call"] if sm.person_ix.has(pid) else str(pid)


static func _to(sm, to) -> String:
	if sm.roles.has(to):
		return sm.roles[to]["title"]
	if sm.person_ix.has(to):
		return _call(sm, to)
	return "all"
