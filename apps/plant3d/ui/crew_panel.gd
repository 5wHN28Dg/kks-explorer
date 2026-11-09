## The crews (docs/PLANT3D.md §18.7, milestone S1): the trainee's role, their task list and the radio.
##   Role: at the start of a shift (a scenario with staff, before its first step) the roles a trainee may play, with
##         the people on duty in each; or free mode (no role: every authority, as format 1).
##   Tasks: the current task's steps with the one to do now (a place to go to and "Take me there", a reading to write
##         down, a message to send, a call to make, a choice), the tasks waiting, what is new since the last look
##         ("Seen" is the task_ack input that lets fast-forward run again, §17.6), and the round's readings sheet.
##   Radio: the messages and calls between the roles (the events `say` and `call`), the trainee's own messages and
##         requests (the calls the content makes to other roles), and "Sleep to the next shift" (a jump) when allowed.
##         A message or a radio call of their role the trainee missed over their music (the event `missed`,
##         REALISM.md §8.5) shows as "Missed call from …", without its text.
##   Phone: the trainee's music and phone (ui/phone.gd), in free mode too.
## Everything goes to the engine as an input; nothing here changes the plant itself. Touch, keyboard and gamepad:
## every control is a button or a line edit that takes the focus (Esc or B closes, as the other panels).
extends PanelContainer

const RADIO_LINES := 10         # the radio's last lines shown
## The unsafe acts' kinds in the engine's order (PLANT3D §16.7; with staff.json's `audio` the last two, REALISM.md
## §8.5): an act's index in sp_acts.
const KINDS := ["ppe", "permit", "unsafe", "audio", "phone"]

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const W = preload("res://ui/widgets.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Debrief = preload("res://ui/debrief.gd")
const Discussions = preload("res://ui/discussions.gd")     # the discussion panel and its radio lines (REALISM.md §6.3.1)

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
var _radio_labels: Array = []   # the radio's last lines on the panel (Labels, oldest first)
var _radio_shown := -1          # how many of _radio's lines there were when they were shown
var _head: Label = null         # the trainee's header line (role, duty, clock) and its text before the clock
var _head_text := ""
var _reads: Dictionary = {}     # person -> their read events
var _disc_parts: Dictionary = {}    # discussion id -> its participants at its last start (the radio's speakers)
var _disc_lines: Dictionary = {}    # discussion id -> [[who, text]] of its last instance (the panel's, read once each)
var _disc_node: Control = null      # the discussion's part, kept across the panel's rebuilds while it is the same
var _disc_key := ""                 # what it was built from (Discussions.sig and its lines' count)
var _disc_closed: Dictionary = {}   # "id|count" -> true: an ended discussion's panel the trainee closed
var _exchanges: Dictionary = {}  # "step|caller" -> true: a call or message to the trainee missed then (its others too)
var _said: Dictionary = {}      # "from|message" -> the radio line of its last say (a missed call replaces it)


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
		return "none|" + ui.phone.sig()
	var tr: int = ui.my_person()
	var cur = e.sp_cur[tr] if tr != -1 else null
	# (free mode shows the roles or a line, and the radio's last lines; the sleep button's state, fast-forward's,
	# only with a role. The radio's new lines alone are written into the lines shown, without a rebuild: refresh)
	return "%d|%d|%s|%s|%d|%d|%d|%s|%d|%s|%s" % [tr, e.step_no if tr == -1 and e.step_no < 2 else 0,
			str(cur["task"]) + str(cur["step"]) + str(cur["st"].get("dest", "")) if cur != null else "",
			(str(e.sp_queue[tr].size()) + "/" + str(e.sp_slots[tr].size())) if tr != -1 else "", e.unacked(ui.inputs.slot),
			_reads_count(e), e.t_at(ui.inputs.slot), str(e.fast_forward()) if tr != -1 else "", e.J,
			_safety_sig(e) + _me_sig(e) + Discussions.sig(e, tr, _disc_closed) if tr != -1 else "", ui.phone.sig()]


## What else the trainee's part shows (its header's duty, the waiting tasks' priorities, whether a permit is open:
## the sleep button): these used to come along with the radio's new lines, which no longer rebuild it. The header's
## clock is written into its label at each refresh (_head)
func _me_sig(e) -> String:
	var tr: int = ui.my_person()
	var open_permit := false
	for st in e.pstate:
		open_permit = open_permit or (st >= 1 and st <= 7)
	var prios := ""
	for inst in e.sp_queue[tr]:
		prios += str(inst["prio"])
	return "|%d|%s|%s" % [e.sp_on[tr], prios, str(open_permit)]


## What the PPE and unsafe-act part shows depends on (S2): what the trainee wears, their zones, every act going on,
## whether they stand at a locker and whom of the acting people they can reach.
func _safety_sig(e) -> String:
	var sm = e._sm
	if sm.zone_ids.is_empty():
		return ""
	var near := ""
	for qi in sm.people.size():
		if _acting(e.sp_acts[qi]) and ui.near_person(qi):
			near += str(qi) + ","
	return "%d/%d/%s/%s/%s" % [e.sp_worn[ui.my_person()], e.sp_zin[ui.my_person()], str(e.sp_acts.hash()),
			str(ui.at_locker()), near]


## Whether a person's acts (one a kind, null when none) hold any.
static func _acting(acts: Array) -> bool:
	for a in acts:
		if a != null:
			return true
	return false


## The trainee's readings so far (their sheet); the events read first.
func _reads_count(e) -> int:
	_follow(e)
	return _reads.get(e._sm.people[ui.my_person()]["id"] if ui.my_person() != -1 else "", []).size()


## Reads the events once each (the list only grows within a run): the radio log and the readings.
func _follow(e) -> void:
	if e != _engine or e.events.size() < _seen:
		_engine = e
		_seen = 0
		_j = 0
		_radio.clear()
		_reads.clear()
		_said.clear()
		_exchanges.clear()
		_disc_parts.clear()
		_disc_lines.clear()
		_disc_closed.clear()
	var sm = e._sm
	var me_id = sm.people[ui.my_person()]["id"] if sm != null and ui.my_person() != -1 else null
	var me_role = sm.people[ui.my_person()]["role"] if me_id != null else null
	for k in range(_seen, e.events.size()):
		var ev: Array = e.events[k]
		if ev[1] == "jump" and ev[4] == "done":
			_j += ev[3] - ev[2]
		elif ev[1] in ["say", "call"] and _exchanges.has("%d|%s" % [ev[0], ev[2]]) \
				and ((ev[1] == "say" and (ev[4] == me_id or ev[4] == me_role)) or (ev[1] == "call" and ev[3] == me_role)):
			pass        # the rest of an exchange missed over the music (REALISM.md §8.5): its one line says so
		elif ev[1] == "say":
			_said["%s|%s" % [ev[2], ev[3]]] = _radio.size()
			_radio.append("%s  %s → %s: %s" % [_at(e, ev[0], _j), _call(sm, ev[2]), _to(sm, ev[4]), sm.messages.get(ev[3], ev[3])])
		elif ev[1] == "missed" and ui.my_person() != -1 and ev[2] == sm.people[ui.my_person()]["id"]:
			# not heard over the music (REALISM.md §8.5): who called, not what (and no sound for it)
			var line := "%s  Missed call from %s" % [_at(e, ev[0], _j), _call(sm, ev[4])]
			# (a radio call of the player's role missed carries "call" last: its call line is replaced)
			var key := ("call|%s|%s" if ev.size() > 5 and ev[5] == "call" else "%s|%s") % [ev[4], ev[3]]
			var at_line: int = _said.get(key, -1)
			if at_line >= 0:
				_radio[at_line] = line
			else:
				_radio.append(line)
			_exchanges["%d|%s" % [ev[0], ev[4]]] = true
			_radio_shown = -1           # (a line already shown changed: written again)
		elif ev[1] == "call" and ev[6] == "done":
			_said["call|%s|%s" % [ev[2], ev[4]]] = _radio.size()
			_radio.append("%s  %s → %s: %s" % [_at(e, ev[0], _j), _call(sm, ev[2]), _to(sm, ev[3]),
					sm.tasks[ev[4]]["title"] if sm.tasks.has(ev[4]) else ev[4]])
		elif ev[1] == "discussion" or ev[1] == "point":     # a discussion's lines (REALISM.md §6.3.1)
			var dl: Array = Discussions.event_lines(sm, ev, _disc_parts)
			if ev[1] == "discussion" and ev[3] == "start":
				_disc_lines[ev[2]] = []
			if not dl.is_empty():
				_disc_lines[ev[2]] = _disc_lines.get(ev[2], []) + dl
			for ln in dl:
				_radio.append("%s  %s: %s" % [_at(e, ev[0], _j), ln[0], ln[1]])
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
		ui.phone.show()
		if _radio.size() != _radio_shown:
			_radio_lines()
		if e._sm != null and ui.my_person() != -1 and is_instance_valid(_head) and _head.is_inside_tree():
			_head.text = _head_text + ui.clock_text()       # (the clock, a new minute: no rebuild)
		return
	_sig = sig
	var typed := entry.text if entry != null and is_instance_valid(entry) else ""
	var typed_for := _entry_code
	var had_focus := get_viewport() != null and get_viewport().gui_get_focus_owner() != null \
			and is_ancestor_of(get_viewport().gui_get_focus_owner())
	entry = null
	if _disc_node != null and _disc_node.get_parent() == body:
		body.remove_child(_disc_node)   # (kept: rebuilt only when what it shows changed; the Note 9's frames)
	W.clear(body)
	var sm = e._sm
	if sm == null:
		_drop_disc()
		_radio_labels.clear()           # (no radio in this run: nothing for _radio_lines to fill)
		_radio_shown = _radio.size()
		body.add_child(W.label("No crews in this run: the plant as format 1, the trainee alone.", 18, W.DIM))
		for sid in ui.model.scenarios:
			if ui.model.scenarios[sid].has("staff"):
				var s := sid as String
				body.add_child(W.button("Start: " + ui.model.scenarios[s].get("title", s), func(): ui.start_shift(s)))
		ui.phone.build(body)
		return
	if ui.my_person() == -1:
		_roles(e, sm)
	else:
		_me(e, sm)
	_drop_disc()
	ui.phone.build(body)
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
	var pi: int = ui.my_person()
	var p: Dictionary = sm.people[pi]
	title.text = "Crew: you are %s" % p["call"]
	var duty := "on duty" if e.sp_on[pi] else "off duty"
	_head = W.label("%s, %s, %s" % [sm.roles[p["role"]]["title"], duty, ui.clock_text()], 18, W.DIM)
	_head_text = _head.text.trim_suffix(ui.clock_text())
	body.add_child(_head)
	if e.unacked(ui.inputs.slot) > 0:
		var row := HBoxContainer.new()
		row.add_child(W.label("%d new for you" % e.unacked(ui.inputs.slot), 20, Color(1.0, 0.75, 0.2)))
		row.add_child(W.button("Seen", func(): ui.inputs.task_ack()))
		body.add_child(row)
	var di: int = Discussions.shown(e, pi, _disc_closed)
	if di != -1:                        # (REALISM.md §6.3.1)
		var did: String = sm.discuss["list"][di]["id"]
		var lines: Array = _disc_lines.get(did, [])
		var dk := "%s|%d|%d" % [Discussions.sig(e, pi, _disc_closed), lines.size(), pi]
		if _disc_node == null or dk != _disc_key:
			if _disc_node != null:
				_disc_node.queue_free()
			_disc_node = VBoxContainer.new()
			_disc_key = dk
			var key := "%s|%d" % [did, e.dsc[di]["count"]]
			Discussions.build(ui, e, _disc_node, di, pi, lines, func():
				_disc_closed[key] = true
				_sig = ""
				refresh())
		body.add_child(_disc_node)
	elif _disc_node != null:
		_disc_node.queue_free()
		_disc_node = null
		_disc_key = ""
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


## A meter's words (its service file's title), else its id.
func _meter_title(code: String, meter: String) -> String:
	var j: Dictionary = ui.work.jobs.get(code, {})
	for mt in j.get("service", {}).get("meters", []):
		if String(mt["id"]).replace("$_", j["alias"] + "_") == meter:
			return String(mt["title"])
	return meter


## A hand action's words (its service file's title), else its id.
func _hand_title(code: String, action: String) -> String:
	for a in ui.work.jobs.get(code, {}).get("service", {}).get("actions", []):
		if a["action"] == action:
			return String(a["title"])
	return action.replace("_", " ")


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
	if s.has("read") and s.has("via"):
		return "Read %s: %s" % [s["read"], _meter_title(s["read"], s["via"])]
	if s.has("read"):
		var ex = s.get("expect")
		return "Read %s %s" % [s["read"], ("(expected %s to %s)" % [_num(ex[0]), _num(ex[1])]) if ex != null else ""]
	if s.has("tool") and not s.has("hand"):            # (REALISM.md §2.3; a hand step names its tool too)
		if typeof(s["tool"]) == TYPE_STRING:
			return "Put the tools back"
		return "Take: %s" % ", ".join(s["tool"].map(func(t): return ui.work._tool_title(e, t)))
	if s.has("hand"):            # (REALISM.md §2.4)
		return "At %s: %s" % [s["kks"], _hand_title(s["kks"], s["hand"])]
	if s.has("say"):
		return "Radio to %s: \"%s\"" % [s["to"], sm.messages[s["say"]]]
	if s.has("call"):
		return "Call %s: %s" % [s["call"]["role"], sm.tasks[s["call"]["task"]]["title"]]
	if s.has("jsa") or s.has("talk"):           # (REALISM.md §8.6)
		var w = cur["work"] if s.get("jsa", s.get("talk")) == "$" else s.get("jsa", s.get("talk"))
		var title: String = e.m.works[e.m.work_ix[w]]["title"] if w != null and e.m.work_ix.has(w) else str(w)
		return ("Make the JSA of %s (the permit form)" if s.has("jsa") else "Give the toolbox talk of %s (the permit form)") % title
	if s.has("op") and s["op"].get("where") == "hart":
		return "Through the HART communicator at %s: %s" % [s["op"]["kks"], s["op"]["do"].replace("_", " ")]
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
	if s.has("discuss") and sm.discuss != null:     # (REALISM.md §6.3.1)
		var dd: Dictionary = sm.discuss["list"][sm.discuss["ix"][s["discuss"]]]
		return "Discuss in the %s: %s" % [String(dd["room"]).replace("_", " "), dd["title"]]
	if s.has("ride"):
		return "The bus from %s to %s (or walk)" % [_place_name(sm, s["ride"]["from"]), _place_name(sm, s["ride"]["to"])]
	if s.has("sleep"):
		var u: String = s["sleep"]["until"]
		return "Sleep at home until %s" % (u if not u.begins_with("next") else "before the next shift")
	if s.has("choose"):
		return "Choose what next"
	if s.has("ack"):
		return "Acknowledge the alarm %s" % str(cur["alarm"])
	if s.has("ppe"):
		if typeof(s["ppe"]) == TYPE_STRING and s["ppe"] == "off":
			return "Take the PPE off at the locker"
		return "Put on at the locker: %s" % ", ".join(ppe_items(sm, ui.my_person(), s["ppe"]))
	if s.has("stop"):
		var a = cur.get("act")
		if a == null:
			return "Stop the unsafe act"
		return "Stop the unsafe act of %s: %s" % [sm.people[a[0]]["call"], act_text(sm, a[1], e.sp_acts[a[0]][a[1]])]
	if s.has("handover") or s.has("remove_locks"):
		var what: String = {"take": "Take over the locks of your post", "give": "Hand over your locks (remove each "
				+ "once the incoming person's lock is on)"}.get(s.get("handover"), "Remove by authority the locks "
				+ "of %s" % str(cur.get("owner")))
		if k_is_cur(cur, s, sm) and ui.my_person() != -1:
			var left: Array = sm.points_left(e, ui.my_person(), cur, s)
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
	if s.has("go") or s.has("meet") or s.has("discuss") or s.has("lock") or s.has("unlock") or s.has("work"):
		var dest = cur["st"].get("dest", cur["st"].get("place"))
		if s.has("lock") or s.has("unlock") or (dest != null and dest < 0):
			dest = null         # (a work step begun between places: no place to go back to)
		if dest != null:
			var d: int = dest
			if e.t_at(ui.inputs.slot) == d:
				row.add_child(W.label("You are there.", 18, W.OK_COLOUR))
			else:
				row.add_child(W.button("Take me there", func(): ui.go_to_place(d)))
	if s.has("ride"):
		# at the stop with a bus there that goes where the step goes: get on; else to the stop, or walk instead
		var fr: int = sm.pix[s["ride"]["from"]]
		var to: int = sm.pix[s["ride"]["to"]]
		var me: int = ui.my_person()
		var bus := -1
		for vi in sm.vehicles.size():
			if sm.stands_for(e, vi, fr, to):
				bus = vi
				break
		if me != -1 and e.sp_aboard[me] != -1:
			row.add_child(W.label("On the bus.", 18, W.OK_COLOUR))
		elif bus != -1 and e.t_at(ui.inputs.slot) == fr and e.st_veh[bus]["riders"].size() >= int(sm.vehicles[bus]["seats"]):
			row.add_child(W.label("The bus is full: wait for the next, or walk.", 18, W.DIM))
		elif bus != -1 and e.t_at(ui.inputs.slot) == fr:
			var vid: String = sm.vehicles[bus]["id"]
			row.add_child(W.button("Get on the bus", func(): ui.inputs.get_on(vid)))
		elif e.t_at(ui.inputs.slot) != fr:
			row.add_child(W.button("Take me to the stop", func(): ui.go_to_place(fr)))
		if me == -1 or e.sp_aboard[me] == -1:      # (aboard: the engine puts them off at the stop)
			row.add_child(W.button("Walk instead", func(): ui.go_to_place(to)))
	if s.has("sleep") and ui.my_person() != -1 and sm.home[ui.my_person()] != -1:
		var h: int = sm.home[ui.my_person()]
		if e.t_at(ui.inputs.slot) != h:
			row.add_child(W.button("Take me home", func(): ui.go_to_place(h)))
	if s.has("tool") and not s.has("hand"):
		row.add_child(W.button("Tools", func(): ui.work.toggle_tools() if not ui.work.tools_panel.visible else null))
	var at_code = s.get("kks") if s.has("hand") else (s["read"] if s.has("read") and s.has("via") else
			(s["op"]["kks"] if s.has("op") and s["op"].get("where") == "hart" else null))
	var at_job := false
	if at_code != null:
		# hands-on at the equipment (the work view, REALISM.md §3.3): taken there first, when the trainee isn't
		var ac: String = at_code
		var wp: Array = sm.work_places.get(ac, [])
		if not wp.is_empty() and not wp.has(e.t_at(ui.inputs.slot)):
			var to: int = wp[0]
			row.add_child(W.button("Take me there", func(): ui.go_to_place(to)))
			at_job = true
		elif ui.work.has_job(ac):
			var wb := W.button("Work on it", func(): ui.work.open(ac))
			wb.name = "crew_work"
			row.add_child(wb)
			at_job = true
	if not at_job and s.has("read"):   # (a reading through a meter at a code without a work view: written down)
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
		row.add_child(W.button("Send", func(): ui.inputs.say(msg, to)))
	if s.has("call"):
		var c: Dictionary = s["call"]
		row.add_child(W.button("Call", func(): ui.inputs.radio_call(c["role"], c["task"], c.get("work"))))
	if s.has("choose"):
		for k in s["choose"].size():
			var kk: int = k
			row.add_child(W.button(sm.tasks[s["choose"][k][1]]["title"], func(): ui.inputs.pick(kk)))
	if s.has("ack") and cur["alarm"] != null:
		var a: String = cur["alarm"]
		row.add_child(W.button("Acknowledge", func(): ui.ack(a)))
	if s.has("jsa") or s.has("talk"):           # (REALISM.md §8.6: picked on the permit form)
		var hw = cur["work"] if s.get("jsa", s.get("talk")) == "$" else s.get("jsa", s.get("talk"))
		if hw != null:
			var hws: String = hw
			row.add_child(W.button("Permit form", func(): ui.open_permits(hws)))
	if s.has("permit") or s.has("lock") or s.has("unlock"):
		var k := "permit" if s.has("permit") else ("lock" if s.has("lock") else "unlock")
		var w = cur["work"] if s[k]["work"] == "$" else s[k]["work"]
		if w != null:
			var ws: String = w
			row.add_child(W.button("Permit form", func(): ui.open_permits(ws)))
	if s.has("op") and s["op"].get("where") != "hart":
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
	if (s.has("handover") or s.has("remove_locks")) and ui.my_person() != -1:
		var left: Array = sm.points_left(e, ui.my_person(), cur, s)
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
static func ppe_items(sm, pi: int, x) -> PackedStringArray:
	var items: Array = x if typeof(x) == TYPE_ARRAY else sm.roles[sm.people[pi]["role"]].get("ppe", [])
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
		3:
			return "listening to music in the %s" % _zone_title(sm, det)
		4:
			return "carrying a phone in the Ex zone %s" % _zone_title(sm, det)
		_:
			return "a shortcut" + (" on %s" % str(det) if det != null else "")


static func _zone_title(sm, det) -> String:
	var z: int = sm.zone_ix.get(det, -1) if sm != null else -1
	# (not a zone: a room where music is banned, REALISM.md §8.5: "control_room" is "control room")
	return String(sm.d["zones"][z].get("title", det)).to_lower() if z >= 0 else Debrief.room_words(str(det))


## What the trainee wears, what their zones need, their own unsafe acts, and (with stop_work) the acts they can see.
func _safety(e, sm) -> void:
	if sm.zone_ids.is_empty():
		return
	var pi: int = ui.my_person()
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
				var b := W.button("Take off " + PPE_WORDS.get(item, item), func(): ui.inputs.ppe(item, 0))
				b.name = "off_" + item
				row.add_child(b)
	for k in e.sp_acts[pi].size():
		var a = e.sp_acts[pi][k]
		if a != null:
			body.add_child(W.label("Unsafe act: you are " + act_text(sm, k, a), 18, W.BAD_COLOUR))
	if not sm.auth[sm.people[pi]["role"]].has("stop_work"):
		return
	var seen := false
	for qi in sm.people.size():
		if qi == pi or (sm.zones_of(e, qi) & zm) == 0:
			continue
		for k in e.sp_acts[qi].size():
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
	_radio_labels.clear()
	for k in RADIO_LINES:           # (all of them made now, those with no line yet hidden: _radio_lines fills them)
		var lab := W.label("", 16)
		_radio_labels.append(lab)
		body.add_child(lab)
	_fill_radio()
	if ui.my_person() == -1:
		return
	var me: Dictionary = sm.people[ui.my_person()]
	var row := HFlowContainer.new()
	body.add_child(row)
	for key in sm.callable:
		var parts: PackedStringArray = String(key).split("\n")
		if parts[0] != me["role"]:
			continue
		var role := parts[1]
		var task := parts[2]
		row.add_child(W.button("Call %s: %s" % [role.replace("_", " "), sm.tasks[task]["title"]],
				func(): ui.inputs.radio_call(role, task, null)))
	var nxt := _next_shift(e)
	var b := W.button("Sleep to %s" % nxt, func(): ui.inputs.jump(nxt))
	var open_permit := false
	for s in e.pstate:
		open_permit = open_permit or (s >= 1 and s <= 7)
	b.disabled = not e.fast_forward() or open_permit
	body.add_child(b)
	if open_permit:
		body.add_child(W.label("(no sleeping while a permit is open)", 16, W.DIM))


## The radio's last lines written into its labels (new messages, nothing else changed): no rebuild of the panel,
## which loses no focus and makes no new controls (in fast-forward the radio has new lines every refresh; building
## the panel again for each of the first lines cost up to 50 ms on the laptop). Labels gone (the panel built without
## the radio): the panel is built again.
func _radio_lines() -> void:
	var ok := _radio_labels.size() == RADIO_LINES
	for lab in _radio_labels:
		ok = ok and is_instance_valid(lab) and lab.is_inside_tree()
	if not ok:
		_sig = ""
		refresh()
		return
	_fill_radio()


func _fill_radio() -> void:
	_radio_shown = _radio.size()
	var want := mini(_radio.size(), RADIO_LINES)
	for k in RADIO_LINES:
		var lab: Label = _radio_labels[k]
		lab.visible = k < want
		lab.text = _radio[_radio.size() - want + k] if k < want else ""


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


## The kept discussion part freed when the rebuild didn't put it back (no discussion shown, free mode, no crews).
func _drop_disc() -> void:
	if _disc_node != null and _disc_node.get_parent() == null:
		_disc_node.queue_free()
		_disc_node = null
		_disc_key = ""


func _exit_tree() -> void:
	_drop_disc()
