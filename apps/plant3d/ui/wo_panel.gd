## Work orders (docs/plant3d/REALISM.md §7.1, §2.20; milestone WM1): the plant's work orders from notification to
## closure, and each piece of equipment's history.
## - The list: the open orders (notified, planned, scheduled, in progress, complete) by priority and number, with the
##   backlog's planned crew hours (costs are hours, J7), then the orders closed or cancelled in this run.
## - An order's form: its number, state, who notified it and what they found, its priority and day, its permit, its
##   planned hours, the job's coding once complete, and the actions that come next (plan with a priority, schedule
##   for a day, complete with ISO 14224's failure mode, cause and maintenance action and a comment, close, cancel).
## - A code's view, from its card's "Work orders": "Report a finding" (the kinds of finding its works are written for,
##   matched to the work: §7.1) and its history, newest first: the run's own orders and the content's past orders
##   (workorders.json's `history`).
## Every action goes to the engine as the input [n, "wo", work, action, person, data] (ui/inputs.gd) and its refusal
## comes back in words. Touch, keyboard and gamepad: every control is a button that takes the focus.
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const Permits = preload("res://ui/permits.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Wo = preload("res://sim/workorders.gd")
const InputCheck = preload("res://net/input_check.gd")

const STATE_WORDS := ["No work order", "Notified", "Planned", "Scheduled", "In progress", "Complete", "Closed",
	"Cancelled"]
const PRIORITY_WORDS := {1: "Emergency", 2: "Urgent", 3: "Normal", 4: "When convenient"}
const ACTION_WORDS := {"notify": "Notify", "plan": "Plan", "schedule": "Schedule", "complete": "Complete",
	"close": "Close", "cancel": "Cancel"}
const DONE_WORDS := {"notify": "notified", "plan": "planned", "schedule": "scheduled", "complete": "completed",
	"close": "closed", "cancel": "cancelled"}
const FROM := {"notify": [0, 6, 7], "plan": [1], "schedule": [2], "complete": [4], "close": [5], "cancel": [1, 2, 3, 4]}
const KIND_WORDS := {"corrective": "Corrective", "preventive": "Preventive", "condition": "Condition-based"}
const DAY := 864000             # a clock day in tenths (§16.1)
const SCHEDULE_DAYS := [0, 1, 2, 7]     # the days offered: today, tomorrow, the day after, in a week

var ui                          # ui/plant_ui.gd
var body: VBoxContainer
var title: Label
var work := ""                  # the work whose order's form is shown
var code := ""                  # the code whose history is shown ("" with work "": the list)
var feedback: Label             # the last action's result (tests read it)
var last_text := ""
var _pending: Array = []        # [work, action, step it takes effect]
var _pick := {}                 # work -> the completion being chosen [mode, cause, action, comment]
var _sig := ""
var _t := 0.0


func setup(u) -> void:
	ui = u
	var parts := W.panel("Work orders", close)
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	title = parts[2]
	visible = false


## Whether the run's plant has work orders (workorders.json).
func available() -> bool:
	var e = ui.clock.engine
	return e != null and e.m.wo_doc != null


## The code's card offers "Work orders" when a work is written for it or the content has its past orders.
func has_orders(c: String) -> bool:
	if not available():
		return false
	var e = ui.clock.engine
	if not Permits.works_at(e, c).is_empty():
		return true
	for h in e.m.wo_doc.get("history", []):
		if h["kks"] == c:
			return true
	return false


func is_open() -> bool:
	return visible


## The list, or an order's form (its work's id).
func open(wid := "") -> void:
	work = wid
	code = ""
	_open()


## A code's history and "Report a finding".
func open_for_code(c: String) -> void:
	work = ""
	code = c
	_open()


func _open() -> void:
	visible = true
	last_text = ""
	_sig = ""
	refresh()
	_focus()


func close() -> void:
	visible = false
	work = ""
	code = ""
	ui.close_work_orders()


func _focus() -> void:
	var first := _first_button(body)
	if first != null:
		first.grab_focus()


func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and c.visible and not c.disabled:
			return c
		var b := _first_button(c)
		if b != null:
			return b
	return null


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


# ------------------------------------------------------------------ the engine's work orders

static func state_of(e, wid: String) -> int:
	var wi: int = e.m.work_ix.get(wid, -1)
	if wi < 0 or e.wo.is_empty():
		return 0
	return int(e.wo[wi]) if typeof(e.wo) != TYPE_DICTIONARY else int(e.wo.get(wid, 0))


## The work's current order's record (the reference's layout, ref/plant3d_wo.py), [] before its first notification.
static func record_of(e, wid: String) -> Array:
	if typeof(e.wo_rec) == TYPE_DICTIONARY:
		var r = e.wo_rec.get(wid, [])
		return r if typeof(r) == TYPE_ARRAY else []
	var wi: int = e.m.work_ix.get(wid, -1)
	return e.wo_rec[wi] if wi >= 0 and wi < e.wo_rec.size() and typeof(e.wo_rec[wi]) == TYPE_ARRAY else []


static func title_of(e, list: String, id) -> String:
	if id == null:
		return "none named"
	for x in e.m.wo_doc.get(list, []):
		if x["id"] == id:
			return x["title"]
	return str(id)


static func today(e) -> int:
	return int(e.clock() / DAY) if e.has_method("clock") else 0


## A clock in tenths in words: "day 2 06:40" (with the plant clock), else model time.
static func clock_words(e, c: int) -> String:
	if c < 0:
		return ""
	if e._sm == null:
		return W.model_time(c)
	var s := int(c / 10) % 86400
	return "day %d %02d:%02d" % [int(c / DAY), s / 3600, (s / 60) % 60]


## Who may make the action (§2.20), in words, for the form's buttons: the titles of the roles holding its authority
## (and the work's discipline, for a completion), from the staff's content; without staff the usual roles.
static func role_words(e, action: String, w: Dictionary) -> String:
	if action == "notify":
		return "anyone"
	var sm = e._sm if "_sm" in e else null
	if sm == null:
		if action == "complete":
			return Permits.TECH.get(w.get("discipline", ""), "technician")
		return "maintenance or shift supervisor"
	var need: String = Wo.AUTH[action]
	var out := PackedStringArray()
	for rid in sm.roles:
		var r: Dictionary = sm.roles[rid]
		if sm.auth[rid].has(need) and (action != "complete" or r.get("discipline", "") == w.get("discipline", "")):
			out.append(String(r.get("title", rid)).to_lower())
	return " or ".join(out) if not out.is_empty() else "nobody in this plant"


## Whether the person played (null: free mode) may make the action on the work (§2.20, as the engine's authority
## check: a refused action is not offered on the form).
static func may(e, me, action: String, w: Dictionary) -> bool:
	var sm = e._sm if "_sm" in e else null
	if sm == null or me == null or not sm.person_ix.has(me):
		return sm != null or me == null
	var rid: String = sm.people[sm.person_ix[me]]["role"]
	var need: String = Wo.AUTH[action]
	if need != "" and not sm.auth[rid].has(need):
		return false
	return action != "complete" or sm.roles[rid].get("discipline", "") == w.get("discipline", "")


## The work a finding of that kind on the code goes to (§7.1: matched by code and kind): the first of the code's works
## written for it without an open order, else the first written for it (whose open order it already is).
static func work_for(e, c: String, mode: String) -> Dictionary:
	var first := {}
	for w in Permits.works_at(e, c):
		if mode in w.get("finds", []):
			if state_of(e, w["id"]) in [0, 6, 7]:
				return w
			if first.is_empty():
				first = w
	return first


# ------------------------------------------------------------------ inputs and their results

func send(wid: String, action: String, data: Array) -> void:
	var e = ui.clock.engine
	ui.inputs.work_order(wid, action, ui.me(), data)
	_pending.append([wid, action, e.step_no + 1])
	var paused: bool = ui.clock.speed == SimClock.Speed.PAUSED
	_show("Sent%s" % (": it takes effect when the plant runs (paused)" if paused else "…"), true)


func report(c: String, mode: String) -> void:
	var w := work_for(ui.clock.engine, c, mode)
	if w.is_empty():
		return
	send(w["id"], "notify", [mode])


func _show(text: String, ok := false) -> void:
	last_text = text
	if feedback != null and is_instance_valid(feedback):
		feedback.text = text
		feedback.add_theme_color_override("font_color", W.OK_COLOUR if ok else W.BAD_COLOUR)


static func reason_text(e, w: Dictionary, why: String, action: String) -> String:
	match why:
		"authority":
			return "it is the %s's to do" % role_words(e, action, w)
		"state":
			return "the order is %s" % STATE_WORDS[state_of(e, w.get("id", ""))].to_lower()
		"permit":
			if action == "complete":
				return "the job's permit is not done yet"
			return "its permit is still live: close it (or cancel it) first"
		"data":
			return "what was chosen is not one of the lists (or the day is past)"
	return why


static func event_text(e, ev: Array) -> String:
	var wid = ev[2]
	var w: Dictionary = e.m.works[e.m.work_ix[wid]] if typeof(wid) == TYPE_STRING and e.m.work_ix.has(wid) else {}
	var t: String = w.get("title", str(wid))
	if ev[3] == "auto":
		return "Work order %s: %s" % [t, STATE_WORDS[int(ev[6][0])].to_lower()]
	match ev[5]:
		"done":
			var rec := record_of(e, str(wid))
			return "Work order %s: %s%s" % [t, DONE_WORDS.get(ev[3], str(ev[3])),
					(" (%s)" % rec[0]) if ev[3] == "notify" and not rec.is_empty() else ""]
		"refused":
			var why := PackedStringArray()
			for r in ev[6]:
				why.append(reason_text(e, w, String(r), String(ev[3])))
			return "Work order %s: %s refused (%s)" % [t, ACTION_WORDS.get(ev[3], str(ev[3])).to_lower(),
					"; ".join(why)]
	return "Work order %s: not an action of this plant" % t


## The engine's events since the last look (ui/plant_ui.gd _sync_events): the results of what was sent.
func on_events(evs: Array, from: int) -> void:
	var e = ui.clock.engine
	for i in range(from, evs.size()):
		var ev: Array = evs[i]
		if ev.size() < 7 or ev[1] != "wo":
			continue
		_sig = ""
		for k in _pending.size():
			var p: Array = _pending[k]
			if p[0] == ev[2] and p[1] == ev[3] and int(ev[0]) >= p[2]:
				var txt := event_text(e, ev)
				_show(txt, ev[5] == "done")
				if ev[3] == "complete" and ev[5] == "done":
					_pick.erase(ev[2])      # (a later order on the work starts with an empty completion)
				if ev[5] != "done":
					ui.toast(txt)
				_pending.remove_at(k)
				break


# ------------------------------------------------------------------ drawing

func refresh() -> void:
	if not visible:
		return
	var e = ui.clock.engine
	if e == null or e.m.wo_doc == null:
		return
	var sig := [work, code, today(e), e.wo_history.size(), ui.me()]
	# (a work's form follows only its own work: other works' moves never rebuild a completion being filled in)
	for wd in ([e.m.works[e.m.work_ix[work]]] if work != "" and e.m.work_ix.has(work) else e.m.works):
		sig.append(state_of(e, wd["id"]))
		sig.append(Permits.state_of(e, wd["id"]))
	var s := str(sig)
	if s == _sig:
		return
	var had := get_viewport().gui_get_focus_owner()
	var had_name: String = String(had.name) if had != null and is_ancestor_of(had) else ""
	_sig = s
	W.clear(body)
	feedback = W.label(last_text, 17, W.DIM)
	feedback.name = "feedback"
	if work != "" and e.m.work_ix.has(work):
		_form(e, e.m.works[e.m.work_ix[work]])
	elif code != "":
		_code_view(e)
	else:
		_list(e)
	body.add_child(feedback)
	if had_name != "":
		var b := body.find_child(had_name, true, false)
		if b is Control:
			# (deferred, by its id: another refresh may free it first)
			var id: int = b.get_instance_id()
			var again := func() -> void:
				var c = instance_from_id(id)
				if c is Control and (c as Control).is_inside_tree():
					(c as Control).grab_focus()
			again.call_deferred()


func _list(e) -> void:
	title.text = "Work orders"
	var open_ws := []
	var hours := 0.0
	for wd in e.m.works:
		var st := state_of(e, wd["id"])
		if st >= 1 and st <= 5:
			var rec := record_of(e, wd["id"])
			var pr: int = int(rec[4]) if rec.size() > 4 and int(rec[4]) > 0 else 9
			var day: int = int(rec[5]) if rec.size() > 5 and int(rec[5]) >= 0 else 1 << 30
			open_ws.append([[st, pr, day, String(rec[0]) if not rec.is_empty() else ""], wd])
			if st <= 4:
				hours += float(wd.get("hours", 0.0))
	open_ws.sort_custom(func(a, b): return _before(a[0], b[0]))     # by state, priority, day, then number
	body.add_child(W.label("Backlog: %d open order%s, %s planned crew hours" % [open_ws.size(),
			"" if open_ws.size() == 1 else "s", _hours(hours)], 18, Color.WHITE))
	if open_ws.is_empty():
		body.add_child(W.label("No open work orders. Report a finding from a piece of equipment's card (Work orders).",
				16, W.DIM))
	for x in open_ws:
		_row(e, x[1])
	if not e.wo_history.is_empty():
		body.add_child(W.label("Closed in this run", 20, Color.WHITE))
		for k in range(e.wo_history.size() - 1, -1, -1):
			body.add_child(W.label(_closed_line(e, e.wo_history[k]), 16, W.DIM))


func _row(e, wd: Dictionary) -> void:
	var st := state_of(e, wd["id"])
	var rec := record_of(e, wd["id"])
	var b := W.button("%s  %s" % [rec[0] if not rec.is_empty() else "", wd["title"]], open.bind(wd["id"]))
	b.name = "open_" + wd["id"]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(b)
	var words := "%s · %s" % [wd["kks"], STATE_WORDS[st]]
	if rec.size() > 4 and int(rec[4]) > 0:
		words += " · " + PRIORITY_WORDS.get(int(rec[4]), "")
	if rec.size() > 5 and int(rec[5]) >= 0:
		words += " · day %d" % int(rec[5])
	var colour: Color = W.PRIO_COLOURS.get(int(rec[4]) if rec.size() > 4 else 0, W.DIM)
	body.add_child(W.label(words, 16, colour if st <= 4 else W.OK_COLOUR))


## The list's order (§2.20): [state, priority, day, number], each ascending.
static func _before(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


static func _closed_line(e, r: Array) -> String:
	var wid := String(r[9])
	var t: String = e.m.works[e.m.work_ix[wid]]["title"] if wid != "" else ""
	var end: int = int(r[1][5])
	var how := "closed" if int(r[1][4]) >= 0 else "cancelled"
	return "%s  %s: %s %s%s" % [r[0], t, how, clock_words(e, end),
			(" · " + _codes_words(e, r[7])) if r[7][2] != null else ""]


static func _codes_words(e, c: Array) -> String:
	var out := PackedStringArray()
	if c[0] != null:
		out.append(title_of(e, "modes", c[0]))
	if c[1] != null:
		out.append(title_of(e, "causes", c[1]))
	if c[2] != null:
		out.append(title_of(e, "actions", c[2]))
	return ", ".join(out)


static func _hours(h: float) -> String:
	return ("%d" % int(h)) if is_equal_approx(h, roundf(h)) else ("%.1f" % h)


func _form(e, w: Dictionary) -> void:
	var wid: String = w["id"]
	var st := state_of(e, wid)
	var rec := record_of(e, wid)
	title.text = "%s\n%s" % [rec[0] if not rec.is_empty() and st != 0 else "Work order", w["title"]]
	var back := W.button("All work orders", open.bind(""))
	back.name = "to_list"
	body.add_child(back)
	body.add_child(W.label("%s · %s" % [w["kks"], STATE_WORDS[st]], 20, Color.WHITE))
	var lines := PackedStringArray()
	lines.append("Planned: %s crew hours, %s work, %s" % [_hours(float(w.get("hours", 0.0))),
			Permits.DISCIPLINES.get(w["discipline"], w["discipline"]), Permits.PERMIT_KINDS.get(w["permit"], w["permit"])])
	if not rec.is_empty() and st != 0:
		var by: String = Permits.person_words(e, rec[2])
		lines.append("Notified %s by %s: %s" % [clock_words(e, int(rec[1][0])), by, title_of(e, "modes", rec[3])])
		if int(rec[4]) > 0:
			lines.append("Priority: %s" % PRIORITY_WORDS.get(int(rec[4]), str(rec[4])))
		elif st >= 4:
			lines.append("Worked before it was planned (an emergency job)")
		if int(rec[5]) >= 0:
			lines.append("Scheduled for day %d" % int(rec[5]))
		if int(rec[1][3]) >= 0:
			lines.append("Started %s" % clock_words(e, int(rec[1][3])))
		if rec[7][2] != null:
			lines.append("Completed %s by %s: %s%s" % [clock_words(e, int(rec[1][4])), Permits.person_words(e, rec[6]),
					_codes_words(e, rec[7]), (". " + String(rec[8])) if String(rec[8]) != "" else ""])
	var ps: int = Permits.state_of(e, wid)
	lines.append("Permit: %s%s" % [Permits.STATE_WORDS[ps], (" (%s)" % Permits.number_of(e, wid)) if ps != 0 else ""])
	body.add_child(W.label("\n".join(lines), 17, W.DIM))
	var pb := W.button("Open its permit", func(): ui.open_permits(wid))
	pb.name = "to_permit"
	body.add_child(pb)
	# the actions that come next
	for a in ["notify", "plan", "schedule", "complete", "close", "cancel"]:
		if not st in FROM[a] or not may(e, ui.me(), a, w):
			continue
		var who := role_words(e, a, w)
		match a:
			"notify":
				for m in (w.get("finds", []) if not w.get("finds", []).is_empty() else [null]):
					var b := W.button("Notify: %s (as %s)" % [title_of(e, "modes", m), who],
							send.bind(wid, "notify", [m]))
					b.name = "notify_%s" % str(m)
					body.add_child(b)
			"plan":
				body.add_child(W.label("Plan it with a priority (as the %s):" % who, 17, Color.WHITE))
				var row := HFlowContainer.new()
				body.add_child(row)
				for p in [1, 2, 3, 4]:
					var b := W.button(PRIORITY_WORDS[p], send.bind(wid, "plan", [p]))
					b.name = "plan_%d" % p
					row.add_child(b)
			"schedule":
				body.add_child(W.label("Schedule it for a day (as the %s):" % who, 17, Color.WHITE))
				var row := HFlowContainer.new()
				body.add_child(row)
				var d0 := today(e)
				for k in SCHEDULE_DAYS:
					var b := W.button(["Today", "Tomorrow", "In 2 days", "In a week"][SCHEDULE_DAYS.find(k)] +
							" (day %d)" % (d0 + k), send.bind(wid, "schedule", [d0 + k]))
					b.name = "schedule_%d" % k
					row.add_child(b)
			"complete":
				_completion(e, w, who)
			"close", "cancel":
				var b := W.button("%s the work order (as the %s)" % [ACTION_WORDS[a], who], send.bind(wid, a, []))
				b.name = a
				body.add_child(b)


## Whether an input fits a session's (MULTIPLAYER.md §3.3: at most 512 bytes; a longer one would be dropped unseen, as
## a comment of 120 characters of 4-byte UTF-8 would be); always outside a session.
static func fits_session(e, item: Array) -> bool:
	return not e.st_session or InputCheck.text(item).size() <= InputCheck.MAX_BYTES


## The completion: ISO 14224's failure mode, cause and maintenance action, from the file's lists, and a comment.
func _completion(e, w: Dictionary, who: String) -> void:
	var wid: String = w["id"]
	if not _pick.has(wid):
		_pick[wid] = [null, null, null, ""]
	var pick: Array = _pick[wid]
	body.add_child(W.label("Complete it (as the %s): what was found and done" % who, 17, Color.WHITE))
	for k in 3:
		var list: String = ["modes", "causes", "actions"][k]
		var ob := OptionButton.new()
		ob.name = "pick_" + list
		ob.custom_minimum_size = Vector2(0, 52 * W.scale)
		var items: Array = e.m.wo_doc[list]
		if k < 2:
			ob.add_item("%s: none (no failure)" % ["Failure mode", "Cause"][k])
		else:
			ob.add_item("Maintenance action: choose one")
		for x in items:
			ob.add_item(x["title"])
		var cur = pick[k]
		var sel := 0
		for i in items.size():
			if items[i]["id"] == cur:
				sel = i + 1
		ob.select(sel)
		ob.item_selected.connect(func(i: int): pick[k] = null if i == 0 else items[i - 1]["id"])
		body.add_child(ob)
	var c := LineEdit.new()
	c.name = "comment"
	c.placeholder_text = "Comment (up to 120 characters)"
	c.max_length = 120
	c.text = String(pick[3])
	c.custom_minimum_size = Vector2(0, 52 * W.scale)
	c.text_changed.connect(func(t: String): pick[3] = t)
	body.add_child(c)
	var b := W.button("Complete the work order", func():
		if pick[2] == null:
			_show("Choose the maintenance action first")
			return
		var data := [pick[0], pick[1], pick[2], String(pick[3])]
		if not fits_session(ui.clock.engine, ["wo", wid, "complete", ui.me(), data]):
			_show("Too long for one input of a session (%d bytes at most): shorten the comment" % InputCheck.MAX_BYTES)
			return
		send(wid, "complete", data))
	b.name = "complete"
	body.add_child(b)


func _code_view(e) -> void:
	title.text = "Work orders\n%s  %s" % [code, ui.info.name_of(code)]
	var all := W.button("All work orders", open.bind(""))
	all.name = "to_list"
	body.add_child(all)
	var ws: Array = Permits.works_at(e, code)
	# Report a finding: the kinds its works are written for (§7.1)
	var modes := []
	for w in ws:
		for m in w.get("finds", []):
			if not m in modes:
				modes.append(m)
	if not modes.is_empty():
		body.add_child(W.label("Report a finding", 20, Color.WHITE))
		for m in modes:
			var w := work_for(e, code, m)
			var st := state_of(e, w["id"])
			if st in [0, 6, 7]:
				var b := W.button(title_of(e, "modes", m), report.bind(code, m))
				b.name = "report_" + String(m)
				body.add_child(b)
			else:
				var rec := record_of(e, w["id"])
				var b := W.button("%s: already %s (%s)" % [title_of(e, "modes", m), STATE_WORDS[st].to_lower(), rec[0]],
						open.bind(w["id"]))
				b.name = "report_" + String(m)
				body.add_child(b)
	# its works' open orders
	for w in ws:
		if state_of(e, w["id"]) in [1, 2, 3, 4, 5]:
			_row(e, w)
	# its history, newest first: the run's own orders, then the content's
	body.add_child(W.label("History", 20, Color.WHITE))
	var n := 0
	var wids := {}
	for w in ws:
		wids[w["id"]] = true
	for k in range(e.wo_history.size() - 1, -1, -1):
		var r: Array = e.wo_history[k]
		if wids.has(String(r[9])):
			body.add_child(W.label(_closed_line(e, r), 16, Color.WHITE))
			n += 1
	var past := []
	for h in e.m.wo_doc.get("history", []):
		if h["kks"] == code:
			past.append(h)
	past.sort_custom(func(a, b): return int(a["ago"]) < int(b["ago"]))
	for h in past:
		var codes := _codes_words(e, [h["mode"], h["cause"], h["action"]])
		body.add_child(W.label("%d days before the run · %s · %s\n%s · %s crew hours" % [int(h["ago"]),
				KIND_WORDS.get(h["kind"], h["kind"]), h["title"], codes, _hours(float(h["hours"]))], 16, W.DIM))
		n += 1
	if n == 0:
		body.add_child(W.label("No work orders on it yet.", 16, W.DIM))


## The debrief's lines (REALISM.md §2.20): the orders of the run, and each completion the trainee coded against the
## job's own codes (the work's `codes`).
static func debrief_lines(e, me_id) -> PackedStringArray:
	var out := PackedStringArray()
	if e == null or e.m.wo_doc == null:
		return out
	var recs: Array = e.wo_history.duplicate()
	for wd in e.m.works:
		var st := state_of(e, wd["id"])
		if st >= 1 and st <= 5:
			recs.append(record_of(e, wd["id"]))
	if recs.is_empty():
		return out
	var closed := 0
	for r in recs:
		if int(r[1][5]) >= 0 and int(r[1][4]) >= 0:
			closed += 1
	out.append("Work orders: %d raised, %d closed" % [recs.size(), closed])
	for r in recs:
		if r[7][2] == null or r[6] != me_id:
			continue
		var wid := String(r[9])
		if not e.m.work_ix.has(wid):
			continue
		var w: Dictionary = e.m.works[e.m.work_ix[wid]]
		var job: Array = w.get("codes", [])
		var same: bool = not job.is_empty() and job[0] == r[7][0] and job[1] == r[7][1] and job[2] == r[7][2]
		out.append("%s %s: you coded %s%s" % [r[0], w["title"], _codes_words(e, r[7]),
				"" if same or job.is_empty() else "; the job's own coding: " + _codes_words(e, job)])
	return out
