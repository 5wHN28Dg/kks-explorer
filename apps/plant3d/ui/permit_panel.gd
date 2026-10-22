## The permit form (docs/PLANT3D.md §15, §18.7): the plant's works and their permits to work. A work's form shows its
## permit's number and state, the steps it goes through, its isolation's points (with how each is made safe, which
## are locked, and by whom), the actions that come next and its history with model times. Every action goes to the
## engine as an input (sim/engine.gd: permit, lock, unlock) and its refusal comes back in words.
##
## Free mode (no staff yet, §17.1): the trainee plays each role in turn, and the form names whose step each action is.
## Locks are made at the equipment (lock-out and tag-out): a point's Lock and Remove buttons work within reach of its
## equipment, as a local operation does (a code not drawn in the plant is locked from anywhere); Go there flies there.
## Touch, keyboard and gamepad: every control is a button that takes the focus (Esc or B closes, as the other panels).
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const Permits = preload("res://ui/permits.gd")
const SimClock = preload("res://ui/sim_clock.gd")

var ui                          # ui/plant_ui.gd
var body: VBoxContainer
var title: Label
var work := ""                  # the work whose form is shown, "" for the list
var results := {}               # [work, action] or [work, "lock" | "unlock", point] as a string -> {state, text}
var _pending: Array = []        # [key, kind, work, action or point, step it takes effect]
var _sig := ""
var _t := 0.0
var feedback: Label             # the last action's result (tests read it)


func setup(u) -> void:
	ui = u
	var parts := W.panel("Permits to work", func(): ui.close_permits())
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	title = parts[2]
	visible = false


## Opens the list, or a work's form (its id), or the form of the work on a code (the only one; else the list).
func open(wid := "") -> void:
	work = wid
	visible = true
	_sig = ""
	refresh()
	_focus()


func open_for_code(code: String) -> void:
	var ws: Array = Permits.works_at(ui.clock.engine, code)
	open(ws[0]["id"] if ws.size() == 1 else "")


func _focus() -> void:
	if not ui.wants_focus():
		return
	var b := _first(body)
	if b:
		b.grab_focus()


static func _first(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and not c.disabled:
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


# ------------------------------------------------------------------ inputs and their results

func send(action: String) -> void:
	var e = ui.clock.engine
	e.permit(work, action)
	_sent(str([work, action]), "permit", work, action, e.step_no + 1)


func send_lock(kind: String, point: int) -> void:
	var e = ui.clock.engine
	if kind == "lock":
		e.lock(work, point)
	else:
		e.unlock(work, point)
	_sent(str([work, kind, point]), kind, work, point, e.step_no + 1)


func _sent(key: String, kind: String, wid: String, what, step: int) -> void:
	_pending.append([key, kind, wid, what, step])
	var paused: bool = ui.clock.speed == SimClock.Speed.PAUSED
	results[key] = {"state": "sent", "text": "Sent%s" % (": it takes effect when the plant runs (paused)" if paused else "…")}
	_sig = ""
	refresh()


## The engine's events since the last look (ui/plant_ui.gd _sync_events): the results of what was sent.
func on_events(evs: Array, from: int) -> void:
	var e = ui.clock.engine
	for i in range(from, evs.size()):
		var ev: Array = evs[i]
		if ev[1] != "permit" and ev[1] != "lock" and ev[1] != "unlock":
			continue
		if ev[1] == "permit" and ev[3] == "auto":
			_sig = ""
			continue
		for k in _pending.size():
			var p: Array = _pending[k]
			if p[1] == ev[1] and p[2] == ev[2] and p[3] == ev[3] and int(ev[0]) >= p[4]:
				var txt: String = Permits.event_text(e, ev)
				results[p[0]] = {"state": ev[5], "text": txt}
				if feedback != null and is_instance_valid(feedback):
					feedback.text = txt
				if ev[5] != "done":
					ui.toast(txt)
				_pending.remove_at(k)
				break
		_sig = ""


# ------------------------------------------------------------------ drawing

func refresh() -> void:
	if not visible:
		return
	var e = ui.clock.engine
	# rebuilt only when what it shows changed (a rebuild while a button is focused would lose the focus)
	var near := PackedStringArray()
	var w = e.m.works[e.m.work_ix[work]] if e.m.work_ix.has(work) else null
	if w != null:
		var x: Dictionary = Permits.isolation_of(e, w)
		for pt in x.get("points", []):
			near.append("1" if _reachable(pt["kks"]) else "0")
	var hist: Array = Permits.history(e, work) if w != null else []
	var sig := "%s|%s|%s|%s|%s|%d|%s|%s" % [work, str(e.pstate), str(e.lockbits), str(e.ptw), ",".join(near),
			hist.size(), str(results), _safe_sig(e, w)]
	if sig == _sig:
		return
	var had_focus := get_viewport().gui_get_focus_owner()
	var focus_name: String = had_focus.name if had_focus != null and is_ancestor_of(had_focus) else ""
	_sig = sig
	W.clear(body)
	if w == null:
		work = ""
		_list(e)
	else:
		_form(e, w, hist)
	if focus_name != "":
		var again := body.find_child(focus_name, true, false)
		if again is Button and not again.disabled:
			again.grab_focus()
		else:
			_focus()


func _safe_sig(e, w) -> String:
	if w == null:
		return ""
	var s := ""
	for pt in Permits.isolation_of(e, w).get("points", []):
		s += "1" if not pt.has("safe") or e.truth(pt["safe"]) else "0"
	return s


func _list(e) -> void:
	title.text = "Permits to work"
	body.add_child(W.label("Each job on the plant's equipment and its permit. Open one to work it through: in free "
			+ "mode you play each role in turn.", 17, W.DIM))
	for wd in e.m.works:
		var st: int = Permits.state_of(e, wd["id"])
		var num: String = Permits.number_of(e, wd["id"])
		var row := VBoxContainer.new()
		body.add_child(row)
		var b := W.button(wd["title"], open.bind(wd["id"]))
		b.name = "open_" + wd["id"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(b)
		var words := "%s · %s" % [wd["kks"], Permits.STATE_WORDS[st]]
		if num != "" and st != 0:
			words += " · " + num
		row.add_child(W.label(words, 16, W.OK_COLOUR if st in [5, 6] else (W.BAD_COLOUR if st in [2, 3, 4, 7, 8] else W.DIM)))


func _form(e, w: Dictionary, hist: Array) -> void:
	var wid: String = w["id"]
	var st: int = Permits.state_of(e, wid)
	var num: String = Permits.number_of(e, wid)
	title.text = (num + "  " if num != "" and st != 0 else "") + w["title"]
	var top := HBoxContainer.new()
	body.add_child(top)
	var back := W.button("All permits", func(): open(""))
	back.name = "back"
	top.add_child(back)
	var card := W.button("Card", func(): ui.open_card(w["kks"]))
	card.name = "card"
	top.add_child(card)
	body.add_child(W.label("%s · %s · %s work" % [w["kks"], ui.info.name_of(w["kks"]),
			Permits.DISCIPLINES.get(w["discipline"], w["discipline"])], 17, W.DIM))
	body.add_child(W.label(Permits.PERMIT_KINDS.get(w["permit"], w["permit"]), 17, W.DIM))
	var state := W.label("Permit: %s" % Permits.STATE_WORDS[st], 22,
			W.OK_COLOUR if st in [5, 6] else (W.BAD_COLOUR if st in [2, 3, 4, 7, 8] else Color.WHITE))
	state.name = "state"
	body.add_child(state)
	body.add_child(W.label(_steps_line(st), 15, W.DIM))
	# what comes next: the actions this state takes, each with the role whose step it is
	var next := []
	for a in Permits.ACTIONS:
		if (a[1] as Array).has(st):
			next.append(a[0])
	if not next.is_empty():
		body.add_child(W.label("Next", 20))
	for a in next:
		var b := W.button("%s (as the %s)" % [Permits.ACTION_WORDS[a], Permits.role_of(a, w)], send.bind(a))
		b.name = "do_" + a
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var r: Dictionary = results.get(str([wid, a]), {})
		b.disabled = r.get("state", "") == "sent"
		body.add_child(b)
	if st == 2:
		body.add_child(W.label("Isolate it: lock and tag every point below, at the equipment. The permit is isolated "
				+ "when the last one is locked.", 16, W.DIM))
	elif st == 5:
		body.add_child(W.label("The work is under way: say Work done when it is finished.", 16, W.DIM))
	elif st == 7:
		body.add_child(W.label("Remove every lock below, at the equipment: the permit is de-isolated when the last "
				+ "one is off.", 16, W.DIM))
	feedback = W.label("", 17, Color.WHITE)
	feedback.name = "feedback"
	body.add_child(feedback)
	_isolation(e, w, st)
	body.add_child(W.label("History", 20))
	if hist.is_empty():
		body.add_child(W.label("Nothing yet.", 16, W.DIM))
	for h in hist:
		body.add_child(W.label("%s  %s" % [W.model_time(h[0]), h[1]], 16, W.BAD_COLOUR if h[2] else W.DIM))
	if not hist.is_empty():
		feedback.text = hist[-1][1] if hist[-1][2] else ""


static func _steps_line(st: int) -> String:
	var names := PackedStringArray()
	for s in [1, 2, 3, 4, 5, 6, 7, 8, 9]:
		var n: String = Permits.SHORT[s].to_lower()
		names.append(("[%s]" % n) if s == st else n)
	if st == 10:
		return "cancelled (request it again to start over)"
	return " → ".join(names)


func _isolation(e, w: Dictionary, st: int) -> void:
	var x: Dictionary = Permits.isolation_of(e, w)
	if x.is_empty():
		body.add_child(W.label("No isolation: nothing to lock for this work.", 17, W.DIM))
		return
	body.add_child(W.label("Isolation: " + x["text"], 20))
	var can_lock: bool = st == 2 or st == 3
	var can_unlock: bool = st in [2, 3, 7, 10]
	var k: int = e.m.isolation_ix[x["id"]]
	var held: bool = e.holder[k] == e.m.work_ix[w["id"]]
	for p in x["points"].size():
		var pt: Dictionary = x["points"][p]
		var box := VBoxContainer.new()
		body.add_child(box)
		var locked: bool = Permits.point_locked(e, x["id"], p)
		var kind: String = Permits.KIND_WORDS.get(pt["kind"], pt["kind"])
		box.add_child(W.label("%d. %s %s (%s)" % [p + 1, pt["kks"], ui.info.name_of(pt["kks"]), kind], 18))
		box.add_child(W.label(pt["how"], 16, W.DIM))
		var safe: bool = not pt.has("safe") or e.truth(pt["safe"])
		var status := "LOCKED and tagged" if locked else ("not locked · safe to lock" if safe else "not locked · not safe to lock yet")
		var sl := W.label(status, 17, W.BAD_COLOUR if locked else (W.OK_COLOUR if safe else W.DIM))
		sl.name = "point_%d" % p
		box.add_child(sl)
		var row := HBoxContainer.new()
		box.add_child(row)
		var reach: bool = _reachable(pt["kks"])
		var who: String = Permits.LOCKER.get(pt["kind"], "field operator")
		if not locked:
			var b := W.button("Lock and tag (as the %s)" % who, send_lock.bind("lock", p))
			b.name = "lock_%d" % p
			b.disabled = not (can_lock and held and reach) or _sent_now(str([w["id"], "lock", p]))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(b)
		else:
			var b := W.button("Remove the lock (as the %s)" % who, send_lock.bind("unlock", p))
			b.name = "unlock_%d" % p
			b.disabled = not (can_unlock and held and reach) or _sent_now(str([w["id"], "unlock", p]))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(b)
		if ui.index.has(pt["kks"]):
			var g := W.button("Go there", func(): ui.fly_to(pt["kks"]))
			g.name = "go_%d" % p
			row.add_child(g)
		if (can_lock and not locked or can_unlock and locked) and held and not reach:
			box.add_child(W.label("At the equipment only: walk up to it (or Go there)", 15, W.DIM))


func _sent_now(key: String) -> bool:
	return results.get(key, {}).get("state", "") == "sent"


## Locks are made within reach of the equipment; a code that is not drawn in the plant from anywhere.
func _reachable(code: String) -> bool:
	return ui.near(code) or not ui.index.has(code)
