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

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const W = preload("res://ui/widgets.gd")
const SimClock = preload("res://ui/sim_clock.gd")

var ui                          # ui/plant_ui.gd
var body: VBoxContainer
var title: Label
var entry: LineEdit             # the reading being written down (tests type into it)
var _entry_code := ""           # which reading step the entry is for
var _sig := ""
var _t := 0.0
var _seen := 0                  # events read so far (the radio log and readings sheet grow from there)
var _engine = null
var _j := 0                     # the jumps made up to the event read last (each line's time is its own clock's)
var _radio: Array = []          # [step, text] of every message and call
var _reads: Dictionary = {}     # person -> their read events


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
	var _c0 := Time.get_ticks_usec()
	_each_frame(delta)
	Cost.add(Cost.CREW, _c0)


func _each_frame(delta: float) -> void:
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
	return "%d|%d|%s|%s|%d|%d|%d|%s|%d|%s" % [tr, e.step_no if tr == -1 and e.step_no < 2 else 0,
			str(cur["task"]) + str(cur["step"]) + str(cur["st"].get("dest", "")) if cur != null else "",
			(str(e.sp_queue[tr].size()) + "/" + str(e.sp_slots[tr].size())) if tr != -1 else "", e.st_unacked, e.events.size() / 50 if tr == -1 else
			_radio_count(e), e.st_t_at, str(e.fast_forward()), e.J, _safety_sig(e) if tr != -1 else ""]


## What the PPE and unsafe-act part shows depends on (S2): what the trainee wears, their zones, every act going on,
## whether they stand at a locker and whom of the acting people they can reach.
func _safety_sig(e) -> String:
	var sm = e._sm
	if sm.zone_ids.is_empty():
		return ""
	var near := ""
	for qi in sm.people.size():
		if e.sp_acts[qi] != [null, null, null] and ui.near_person(qi):
			near += str(qi) + ","
	return "%d/%d/%s/%s/%s" % [e.sp_worn[e.st_trainee], e.sp_zin[e.st_trainee], str(e.sp_acts.hash()),
			str(ui.at_locker()), near]


func _radio_count(e) -> int:
	_follow(e)
	return _radio.size() * 7 + _reads.get(e._sm.people[e.st_trainee]["id"] if e.st_trainee != -1 else "", []).size()


## Reads the events once each (the list only grows within a run): the radio log and the readings.
func _follow(e) -> void:
	if e != _engine or e.events.size() < _seen:
		_engine = e
		_seen = 0
		_j = 0
		_radio.clear()
		_reads.clear()
	var sm = e._sm
	for k in range(_seen, e.events.size()):
		var ev: Array = e.events[k]
		if ev[1] == "jump" and ev[4] == "done":
			_j += ev[3] - ev[2]
		elif ev[1] == "say":
			_radio.append("%s  %s → %s: %s" % [_at(e, ev[0], _j), _call(sm, ev[2]), _to(sm, ev[4]), sm.messages.get(ev[3], ev[3])])
		elif ev[1] == "call" and ev[6] == "done":
			_radio.append("%s  %s → %s: %s" % [_at(e, ev[0], _j), _call(sm, ev[2]), _to(sm, ev[3]),
					sm.tasks[ev[4]]["title"] if sm.tasks.has(ev[4]) else ev[4]])
		elif ev[1] == "read":
			if not _reads.has(ev[2]):
				_reads[ev[2]] = []
			_reads[ev[2]].append(ev)
	_seen = e.events.size()


func refresh() -> void:
	var e = ui.clock.engine
	if e._sm != null:
		_follow(e)
	var sig := _signature(e)
	if sig == _sig:
		return
	_sig = sig
	var typed := entry.text if entry != null and is_instance_valid(entry) else ""
	var typed_for := _entry_code
	var had_focus := get_viewport() != null and get_viewport().gui_get_focus_owner() != null \
			and is_ancestor_of(get_viewport().gui_get_focus_owner())
	entry = null
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
	_radio_log(e, sm)
	if entry != null and typed != "" and typed_for == _entry_code:
		entry.text = typed                  # a reading being typed survives the panel's rebuild (the same reading's)
	if had_focus and ui.wants_focus():
		var f: Control = entry if entry != null else _first(body)
		if f:
			f.grab_focus.call_deferred()


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
	_day(e, sm, pi)
	_safety(e, sm)
	var reads: Array = _reads.get(p["id"], [])
	if not reads.is_empty():
		body.add_child(W.label("Readings sheet:", 18, W.DIM))
		for ev in reads.slice(maxi(0, reads.size() - 12)):
			var c := W.OK_COLOUR if ev[5] == "ok" else W.BAD_COLOUR
			body.add_child(W.label("%s  %s  %s" % [ev[3], _num(ev[4]), {"ok": "in range", "out_of_range":
					"OUT OF RANGE", "misread": "misread (the gauge shows another value)"}[ev[5]]], 18, c))


## The role's day (§18.7, milestone S3: each role plays its own task list): the slots still to come of the trainee's
## routine, with their clock times (the next eight).
func _day(e, sm, pi: int) -> void:
	var sl: Array = e.sp_slots[pi]
	if sl.is_empty():
		return
	body.add_child(W.label("Your day:", 18, W.DIM))
	var today: int = e.clock() / 864000
	for s in sl.slice(0, 8):
		var t: int = s[0] % 864000 / 10
		var day: String = "" if s[0] / 864000 == today else "tomorrow "
		body.add_child(W.label("%s%02d:%02d  %s" % [day, t / 3600, (t / 60) % 60, sm.tasks[s[4]]["title"]], 18))


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
	if s.has("ppe"):
		if typeof(s["ppe"]) == TYPE_STRING and s["ppe"] == "off":
			return "Take the PPE off at the locker"
		return "Put on at the locker: %s" % ", ".join(ppe_items(sm, e, s["ppe"]))
	if s.has("stop"):
		var a = cur.get("act")
		if a == null:
			return "Stop the unsafe act"
		return "Stop the unsafe act of %s: %s" % [sm.people[a[0]]["call"], act_text(sm, a[1], e.sp_acts[a[0]][a[1]])]
	if s.has("handover") or s.has("remove_locks"):
		var what: String = {"take": "Take over the locks of your post", "give": "Hand over your locks (remove each "
				+ "once the incoming person's lock is on)"}.get(s.get("handover"), "Remove by authority the locks "
				+ "of %s" % str(cur.get("owner")))
		if k_is_cur(cur, s, sm) and e.st_trainee != -1:
			var left: Array = sm.points_left(e, e.st_trainee, cur, s)
			var names := []
			for key in left:
				names.append(e._iso[key.x][1][key.y][0])
			what += ": " + (", ".join(names) if not names.is_empty() else "none left")
		return what
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
	# a work step counts down only where it started (§17.3): a trainee called away in the middle (a lock elsewhere,
	# a task of a higher priority) is taken back there
	if s.has("go") or s.has("meet") or s.has("lock") or s.has("unlock") or s.has("work"):
		var dest = cur["st"].get("dest", cur["st"].get("place"))
		if s.has("lock") or s.has("unlock") or (dest != null and dest < 0):
			dest = null         # (a work step begun between places: no place to go back to)
		if dest != null:
			var d: int = dest
			if e.st_t_at == d:
				row.add_child(W.label("You are there.", 18, W.OK_COLOUR))
			else:
				row.add_child(W.button("Take me there", func(): ui.go_to_place(d)))
	if s.has("read"):
		entry = LineEdit.new()
		_entry_code = "%s/%s/%s" % [s["read"], str(cur["order"]), str(cur["step"])]
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
	if s.has("ppe"):
		if ui.at_locker():
			var x = s["ppe"]
			row.add_child(W.button("Take it all off" if typeof(x) == TYPE_STRING and x == "off" else "Put it on",
					func(): ui.put_on(x)))
		else:
			row.add_child(W.button("Take me to a locker", func(): ui.go_to_locker()))
	if s.has("stop") and cur.get("act") != null:
		var qi: int = cur["act"][0]
		_stop_controls(e, sm, row, qi)
	if (s.has("handover") or s.has("remove_locks")) and e.st_trainee != -1:
		var left: Array = sm.points_left(e, e.st_trainee, cur, s)
		if not left.is_empty():
			var wi: int = e.holder[left[0].x]
			if wi != -1:
				var ws: String = e.m.works[wi]["id"]
				var b := W.button("Permit form", func(): ui.open_permits(ws))
				b.name = "handover_form"
				row.add_child(b)


## "Take me there" to an acting person, or "Stop the work" when within reach of them.
func _stop_controls(e, sm, row: Control, qi: int) -> void:
	if ui.near_person(qi):
		var pid: String = sm.people[qi]["id"]
		var b := W.button("Stop the work", func(): ui.stop_work(pid))
		b.name = "stop_" + pid
		row.add_child(b)
	else:
		var to: int = e.sp_pos[qi] if e.sp_pos[qi] != -1 else (e.sp_leg[qi][1] if not e.sp_leg[qi].is_empty() else -1)
		if to != -1:
			row.add_child(W.button("Take me to them", func(): ui.go_to_place(to)))


## A PPE step's items in words.
static func ppe_items(sm, e, x) -> PackedStringArray:
	var items: Array = x if typeof(x) == TYPE_ARRAY else sm.roles[sm.people[e.st_trainee]["role"]].get("ppe", [])
	var out := PackedStringArray()
	for it in items:
		out.append(PPE_WORDS.get(it, it))
	return out


const PPE_WORDS := {"helmet": "hard hat", "boots": "safety boots", "glasses": "safety glasses", "gloves": "gloves",
	"ear": "ear defenders", "harness": "harness", "face_shield": "face shield", "apron": "apron", "vest": "hi-vis vest"}


## An unsafe act in words (PLANT3D §16.7): [zone or work, start, stopped] of its kind.
static func act_text(sm, kind: int, a) -> String:
	var det = a[0] if a != null else null
	match kind:
		0:
			var z: int = sm.zone_ix.get(det, -1)
			return "in the %s without all its PPE" % (String(sm.d["zones"][z].get("title", det)).to_lower() if z >= 0 else str(det))
		1:
			return "working before the permit of %s is accepted" % str(det)
		_:
			return "a shortcut" + (" on %s" % str(det) if det != null else "")


## What the trainee wears, what their zones need, their own unsafe acts, and (with stop_work) the acts they can see.
func _safety(e, sm) -> void:
	if sm.zone_ids.is_empty():
		return
	var pi: int = e.st_trainee
	var worn: int = e.sp_worn[pi]
	var on := PackedStringArray()
	for k in sm.PPE.size():
		if worn & (1 << k):
			on.append(PPE_WORDS.get(sm.PPE[k], sm.PPE[k]))
	body.add_child(W.label("PPE", 20, Color(1.0, 0.85, 0.4)))
	body.add_child(W.label("Wearing: " + (", ".join(on) if not on.is_empty() else "nothing"), 18))
	var zm: int = e.sp_zin[pi]
	for z in sm.zone_ids.size():
		if zm & (1 << z):
			var need: int = sm.zone_ppe[z]
			var miss := PackedStringArray()
			for k in sm.PPE.size():
				if need & (1 << k) and not (worn & (1 << k)):
					miss.append(PPE_WORDS.get(sm.PPE[k], sm.PPE[k]))
			var zt: String = sm.d["zones"][z].get("title", sm.zone_ids[z])
			body.add_child(W.label("In the %s%s" % [zt.to_lower(), (": missing " + ", ".join(miss)) if not miss.is_empty()
					else ": all its PPE on"], 18, W.BAD_COLOUR if not miss.is_empty() else W.OK_COLOUR))
	if ui.at_locker():
		var row := HFlowContainer.new()
		body.add_child(row)
		row.add_child(W.button("Put on all my PPE", func(): ui.put_on("role")))
		for k in sm.PPE.size():
			var item: String = sm.PPE[k]
			if worn & (1 << k):
				var b := W.button("Take off " + PPE_WORDS.get(item, item), func(): ui.clock.engine.ppe(item, 0))
				b.name = "off_" + item
				row.add_child(b)
	for k in 3:
		var a = e.sp_acts[pi][k]
		if a != null:
			body.add_child(W.label("Unsafe act: you are " + act_text(sm, k, a), 18, W.BAD_COLOUR))
	if not sm.auth[sm.people[pi]["role"]].has("stop_work"):
		return
	var seen := false
	for qi in sm.people.size():
		if qi == pi or (sm.zones_of(e, qi) & zm) == 0:
			continue
		for k in 3:
			var a = e.sp_acts[qi][k]
			if a == null or a[2]:
				continue
			if not seen:
				body.add_child(W.label("Unsafe acts in sight", 20, Color(1.0, 0.85, 0.4)))
				seen = true
			var row := HBoxContainer.new()
			body.add_child(row)
			row.add_child(W.label("%s: %s" % [sm.people[qi]["call"], act_text(sm, k, a)], 18, W.BAD_COLOUR))
			_stop_controls(e, sm, row, qi)


# ------------------------------------------------------------------ the radio (§18.7)

func _radio_log(e, sm) -> void:
	body.add_child(W.label("Radio", 20, Color(1.0, 0.85, 0.4)))
	var lines := _radio
	for l in lines.slice(maxi(0, lines.size() - 10)):
		body.add_child(W.label(l, 16))
	if e.st_trainee == -1:
		return
	var me: Dictionary = sm.people[e.st_trainee]
	var row := HFlowContainer.new()
	body.add_child(row)
	for key in sm.callable:
		var parts: PackedStringArray = String(key).split("\n")
		if parts[0] != me["role"]:
			continue
		var role := parts[1]
		var task := parts[2]
		row.add_child(W.button("Call %s: %s" % [role.replace("_", " "), sm.tasks[task]["title"]],
				func(): ui.clock.engine.radio_call(role, task, null)))
	var nxt := _next_shift(e)
	var b := W.button("Sleep to %s" % nxt, func(): ui.clock.engine.jump(nxt))
	var open_permit := false
	for s in e.pstate:
		open_permit = open_permit or (s >= 1 and s <= 7)
	b.disabled = not e.fast_forward() or open_permit
	body.add_child(b)
	if open_permit:
		body.add_child(W.label("(no sleeping while a permit is open)", 16, W.DIM))


func _next_shift(e) -> String:
	var t: int = e.clock() % 864000
	return "18:00" if t >= 6 * 36000 and t < 18 * 36000 else "06:00"


static func _at(e, step: int, j: int) -> String:
	var t: int = e._S + step * e._ds + j
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
