## The stores (docs/plant3d/REALISM.md §7.2, §2.23; milestone WM2): the spare parts' catalogue, the counter and the
## purchase orders.
## - The catalogue, by ISO 14224 class: each part's catalogue number, title, stock on the shelf, on order, its levels
##   (min, reorder point, max) and its store; a part's look-alikes are drawn beside it, as on the shelf.
## - Deliveries due, by day: the pending purchase orders, and the jump to the next one's day.
## - The counter's issue form: the part number as the person writes it on the request (the storekeeper hands over what
##   is written, and checks nothing else: §7.2), the quantity, the work order it is drawn against. Reached at the
##   counter (with a person played: walk there first; free mode draws anywhere).
## - A part's order form: the quantity (offered up to its max), made by whoever holds `order_parts`.
## Every action goes to the engine as the input [n, "issue", part, qty, work, person] or [n, "order", part, qty,
## person] (ui/inputs.gd) and its refusal comes back in words. Touch, keyboard and gamepad: every control is a button,
## a field or a list that takes the focus.
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const Permits = preload("res://ui/permits.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const DAY := 864000             # a clock day in tenths (§16.1)
const MINUTE := 600
const WO_OPEN := [2, 3, 4]      # the work order states parts are issued against (§2.23)
const ISSUE_WHY := {
	"authority": "it is not yours to ask for: write the request as the person you play",
	"where": "parts are drawn at the store's counter: walk there first",
	"storekeeper": "nobody is at the counter to hand it over: the storekeeper is not on duty there",
	"qty": "the quantity is a whole number from 1 to 9,999",
	"work": "its work order is not planned, scheduled or in progress",
}
const ORDER_WHY := {
	"qty": "the quantity is a whole number from 1 to 9,999",
	"pending": "8 orders of it are pending already: wait for a delivery",
}

var ui                          # ui/plant_ui.gd
var body: VBoxContainer
var title: Label
var view := "list"              # "list", "issue" or "order"
var work := ""                  # the issue form's work
var part := ""                  # the order form's part
var feedback: Label             # the last action's result (tests read it)
var last_text := ""
var number_edit: LineEdit       # the issue form's fields (tests fill them)
var qty_edit: LineEdit
var work_pick: OptionButton
var order_qty: LineEdit
var _work_ids: Array = []       # the issue form's works, in the pick's order
var _pending: Array = []        # [kind, part, step it takes effect]
var _sig := ""
var _t := 0.0


func setup(u) -> void:
	ui = u
	var parts := W.panel("Stores", close)
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	title = parts[2]
	visible = false


## Whether the run's plant has stores (stores.json).
func available() -> bool:
	var e = ui.clock.engine
	return e != null and e._sr != null


func is_open() -> bool:
	return visible


## The catalogue ("list"), the counter's issue form ("issue", for a work's order) or a part's order form ("order").
func open(v := "list", id := "") -> void:
	view = v
	work = id if v == "issue" else ""
	part = id if v == "order" else ""
	visible = true
	last_text = ""
	_sig = ""
	refresh()
	_focus()


func close() -> void:
	visible = false
	ui.close_stores()


func _focus() -> void:
	var first := _first_button(body)
	if first != null:
		first.grab_focus()


func _first_button(n: Node) -> Control:
	for c in n.get_children():
		if (c is Button or c is LineEdit) and c.visible and not (c is Button and c.disabled):
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


# ------------------------------------------------------------------ the engine's stores

static func part_of(e, pid: String) -> Dictionary:
	var sr = e._sr
	if sr == null or not sr["ix"].has(pid):
		return {}
	return sr["parts"][sr["ix"][pid]]


## The part with that catalogue number, as written (case and spaces round it don't matter), or "".
static func part_by_number(e, number: String) -> String:
	var n := number.strip_edges().to_upper()
	for p in e._sr["parts"]:
		if p["number"] == n:
			return p["id"]
	return ""


static func stock_of(e, pid: String) -> int:
	return int(e.sr_stock[e._sr["ix"][pid]])


static func due_of(e, pid: String) -> int:
	return int(e.sr_due[e._sr["ix"][pid]])


## The catalogue's order (§2.23): classes in the file's order of their first part; in a class its parts in the file's
## order, each followed by its look-alikes not yet placed (whatever their class: beside each other, as on the shelf).
## [[class, [part ids]]].
static func shelves(e) -> Array:
	var sr = e._sr
	var out: Array = []
	var of := {}
	var placed := {}
	for p in sr["parts"]:
		if placed.has(p["id"]):
			continue
		var cl: String = p["class"]
		if not of.has(cl):
			of[cl] = []
			out.append([cl, of[cl]])
		of[cl].append(p["id"])
		placed[p["id"]] = true
		for x in p.get("looks_like", []):
			if not placed.has(x["part"]):
				of[cl].append(x["part"])
				placed[x["part"]] = true
	return out


## The store's place (a staff place index) of a part, -1 without staff.
static func place_of(e, pid: String) -> int:
	var sr = e._sr
	var sm = e._sm
	if sm == null:
		return -1
	var s: Dictionary = sr["stores"][sr["store_ix"][part_of(e, pid)["store"]]]
	return sm.pix.get(s["place"], -1)


## The counter (the first store not self-service, else the first store): its title and place index.
static func counter(e) -> Dictionary:
	var sr = e._sr
	var s: Dictionary = sr["stores"][0]
	for x in sr["stores"]:
		if not x["self_service"]:
			s = x
			break
	var at: int = e._sm.pix.get(s["place"], -1) if e._sm != null else -1
	return {"title": s["title"], "at": at, "id": s["id"]}


## Whether the trainee may use the counter now: free mode anywhere, a person played at the counter's place.
func at_counter() -> bool:
	var e = ui.clock.engine
	if e._sm == null or ui.my_person() == -1:
		return true
	return e.t_at(ui.inputs.slot) == counter(e)["at"]


## The roles holding an authority, in words (from the staff's content).
static func role_words(e, auth: String) -> String:
	var sm = e._sm
	if sm == null:
		return "the storekeeper or a maintenance supervisor"
	var out := PackedStringArray()
	for rid in sm.roles:
		if sm.auth[rid].has(auth):
			out.append(String(sm.roles[rid].get("title", rid)).to_lower())
	return " or ".join(out) if not out.is_empty() else "nobody in this plant"


## Whether the person played (null: free mode) may order parts (§2.23: order_parts).
static func may_order(e, me) -> bool:
	var sm = e._sm
	if sm == null or me == null or not sm.person_ix.has(me):
		return true
	return sm.auth[sm.people[sm.person_ix[me]]["role"]].has("order_parts")


## The works parts may be issued against (§2.23): with work orders, those planned, scheduled or in progress; without,
## every work.
static func issue_works(e) -> Array:
	var out: Array = []
	for w in e.m.works:
		if e._wo_ids == null or int(e.wo.get(w["id"], 0)) in WO_OPEN:
			out.append(w)
	return out


## A clock in words: "day 2 06:40".
static func clock_words(c: int) -> String:
	var s := int(c / 10) % 86400
	return "day %d %02d:%02d" % [int(c / DAY), s / 3600, (s / 60) % 60]


## The jump that lands at a clock (or the first whole minute after it): [HH:MM, days] for the input (the next
## occurrence of HH:MM after now, then days on), or [] when it is more than 30 days on or not after now.
static func jump_to(e, c: int) -> Array:
	var now: int = e.clock()
	if c <= now:
		return []
	var mins: int = int(ceil(float(c % DAY) / MINUTE))
	var t: int = (c / DAY) * DAY + mins * MINUTE
	if mins >= 1440:
		mins = 0
	var hhmm := "%02d:%02d" % [mins / 60, mins % 60]
	var first: int = (now / DAY) * DAY + mins * MINUTE
	while first <= now:
		first += DAY
	var days: int = int((t - first) / DAY) if t >= first else 0
	if days > 30:
		return []
	return [hhmm, days]


## What blocks a jump now, in words, as the engine's rule (§17.6; in a scenario with `world` §7.4's amendment,
## REALISM.md §2.23): "" when nothing does (a fast-forward not allowed and unacknowledged tasks are said elsewhere).
static func jump_blocked(e) -> String:
	if not e._world:
		for s in e.pstate:
			if s >= 1 and s <= 7:
				return "no jump while a permit is open"
		return ""
	var held := {}
	if e._sm != null:
		for pi in e._sm.people.size():
			for q in e.sp_held[pi]:
				held[q["work"]] = true
	for wi in e.pstate.size():
		if (e.pstate[wi] == 4 or e.pstate[wi] == 5) and not held.has(e.m.works[wi]["id"]):
			return "no jump while a permit is issued or accepted and its job not held"
	if not e.busy.is_empty():
		return "no jump while someone is in a hand action"
	return ""


# ------------------------------------------------------------------ inputs and their results

## Draws parts at the counter: the number as written, the quantity, the work order's work.
func issue(number: String, qty: int, wid: String) -> void:
	var e = ui.clock.engine
	var pid := part_by_number(e, number)
	if pid == "":
		_show("No part numbered %s in the catalogue: copy the number from the catalogue or the data sheet" %
				number.strip_edges())
		return
	ui.inputs.issue(pid, qty, wid, ui.me())
	_pending.append(["issue", pid, e.step_no + 1])
	_sent()


func order(pid: String, qty: int) -> void:
	var e = ui.clock.engine
	ui.inputs.order(pid, qty, ui.me())
	_pending.append(["order", pid, e.step_no + 1])
	_sent()


func _sent() -> void:
	var paused: bool = ui.clock.speed == SimClock.Speed.PAUSED
	_show("Sent%s" % (": it takes effect when the plant runs (paused)" if paused else "…"), true)


func _show(text: String, ok := false) -> void:
	last_text = text
	if feedback != null and is_instance_valid(feedback):
		feedback.text = text
		feedback.add_theme_color_override("font_color", W.OK_COLOUR if ok else W.BAD_COLOUR)


static func event_text(e, ev: Array) -> String:
	if ev[1] == "delivery":         # [n, "delivery", number, part, qty]
		var dp := part_of(e, str(ev[3]))
		return "Delivered: %d × %s %s (%s)" % [int(ev[4]), dp.get("number", ""), dp.get("title", str(ev[3])), ev[2]]
	var p := part_of(e, str(ev[2]))
	var name: String = ("%s %s" % [p["number"], p["title"]]) if not p.is_empty() else str(ev[2])
	var res: String = ev[6] if ev[1] == "issue" else ev[5]
	var why: Array = ev[7] if ev[1] == "issue" else ev[6]
	if res == "unknown":
		return "Not a part or work order of this plant"
	if ev[1] == "issue":
		if res == "done":
			return "Issued: %s × %s against %s" % [str(ev[3]), name, _work_words(e, str(ev[4]))]
		var ws := PackedStringArray()
		for r in why:
			if r == "stock":
				ws.append("only %d on the shelf" % stock_of(e, str(ev[2])))
			else:
				ws.append(ISSUE_WHY.get(r, r))
		return "Issue of %s refused: %s" % [name, "; ".join(ws)]
	if res == "done":
		return "Ordered: %s × %s (%s, due %s)" % [str(ev[3]), name, ev[7], _due_words(e, str(ev[7]))]
	var os := PackedStringArray()
	for r in why:
		os.append(("orders are the %s's to make" % role_words(e, "order_parts")) if r == "authority" \
				else ORDER_WHY.get(r, r))
	return "Order of %s refused: %s" % [name, "; ".join(os)]


static func _due_words(e, no: String) -> String:
	for o in e.sr_orders:
		if o[0] == no:
			return clock_words(int(o[5]))
	return "now"


static func _work_words(e, wid: String) -> String:
	var no = e.wo_no.get(wid) if e._wo_ids != null else null
	var t: String = e.m.works[e.m.work_ix[wid]]["title"] if e.m.work_ix.has(wid) else wid
	return ("%s %s" % [no, t]) if no != null else t


## The engine's events since the last look (ui/plant_ui.gd _sync_events): the results of what was sent, and every
## delivery (a toast).
func on_events(evs: Array, from: int) -> void:
	var e = ui.clock.engine
	if e._sr == null:
		return
	for i in range(from, evs.size()):
		var ev: Array = evs[i]
		if ev[1] == "delivery":
			_sig = ""
			ui.toast(event_text(e, ev))
			continue
		if ev[1] != "issue" and ev[1] != "order":
			continue
		_sig = ""
		for k in _pending.size():
			var p: Array = _pending[k]
			if p[0] == ev[1] and typeof(ev[2]) == TYPE_STRING and p[1] == ev[2] and int(ev[0]) >= p[2]:
				var done: bool = (ev[6] if ev[1] == "issue" else ev[5]) == "done"
				var txt := event_text(e, ev)
				_show(txt, done)
				if not done:
					ui.toast(txt)
				_pending.remove_at(k)
				break


# ------------------------------------------------------------------ drawing

func refresh() -> void:
	if not visible:
		return
	var e = ui.clock.engine
	if e == null or e._sr == null:
		return
	var sig := str([view, work, part, e.sr_po, e.sr_stock, e.sr_due, e.sr_issued, ui.me(), at_counter(),
			int(e.clock() / DAY), e.wo if e._wo_ids != null else null, jump_blocked(e)])
	if sig == _sig:
		return
	var had := get_viewport().gui_get_focus_owner()
	var had_name: String = String(had.name) if had != null and is_ancestor_of(had) else ""
	# (the issue form's fields keep what was typed across a rebuild)
	var keep := [number_edit.text if number_edit != null and is_instance_valid(number_edit) else "",
			qty_edit.text if qty_edit != null and is_instance_valid(qty_edit) else "",
			work_pick.selected if work_pick != null and is_instance_valid(work_pick) else -1,
			order_qty.text if order_qty != null and is_instance_valid(order_qty) else ""]
	_sig = sig
	W.clear(body)
	number_edit = null
	qty_edit = null
	work_pick = null
	order_qty = null
	feedback = W.label(last_text, 17, W.DIM)
	feedback.name = "feedback"
	if view == "issue":
		_issue_form(e, keep)
	elif view == "order" and not part_of(e, part).is_empty():
		_order_form(e, keep)
	else:
		_list(e)
	body.add_child(feedback)
	if had_name != "":
		var b := body.find_child(had_name, true, false)
		if b is Control:
			var id: int = b.get_instance_id()
			var again := func() -> void:
				var c = instance_from_id(id)
				if c is Control and (c as Control).is_inside_tree():
					(c as Control).grab_focus()
			again.call_deferred()


func _list(e) -> void:
	title.text = "Stores"
	var top := HFlowContainer.new()
	body.add_child(top)
	var ib := W.button("At the counter: draw parts", open.bind("issue", ""))
	ib.name = "to_issue"
	top.add_child(ib)
	if ui.work_orders != null and ui.work_orders.available():
		var wb := W.button("Work orders", func(): ui.open_work_orders())
		wb.name = "to_work_orders"
		top.add_child(wb)
	_deliveries(e)
	var sr = e._sr
	for sh in shelves(e):
		body.add_child(W.label(sh[0], 20, Color.WHITE))
		var prev := ""
		for pid in sh[1]:
			var p: Dictionary = part_of(e, pid)
			var stock := stock_of(e, pid)
			var due := due_of(e, pid)
			var low: bool = stock + due <= int(p["reorder"])
			var row := VBoxContainer.new()
			row.name = "part_" + pid
			body.add_child(row)
			var like := ""
			for x in p.get("looks_like", []):
				if x["part"] == prev:
					like = " (looks like the one above)"
			row.add_child(W.label("%s  %s%s" % [p["number"], p["title"], like], 17, Color.WHITE))
			var store: Dictionary = sr["stores"][sr["store_ix"][p["store"]]]
			var words := "Stock %d%s · min %d, reorder at %d, max %d · %s · %d days' lead time" % [stock,
					(", %d on order" % due) if due > 0 else "", int(p["min"]), int(p["reorder"]), int(p["max"]),
					store["title"], int(p["lead_days"])]
			var l := W.label(words, 15, W.BAD_COLOUR if stock == 0 else (W.PRIO_COLOURS[2] if low else W.DIM))
			l.name = "levels"
			row.add_child(l)
			if may_order(e, ui.me()):
				var ob := W.button("Order", open.bind("order", pid))
				ob.name = "order_" + pid
				ob.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				row.add_child(ob)
			prev = pid


## The pending orders by the day they are due, and the jump to the next delivery.
func _deliveries(e) -> void:
	body.add_child(W.label("Deliveries due", 20, Color.WHITE))
	if e.sr_orders.is_empty():
		var n := W.label("Nothing on order.", 16, W.DIM)
		n.name = "deliveries"
		body.add_child(n)
		return
	var by_day := {}
	var days: Array = []
	var first := -1
	for o in e.sr_orders:
		var d := int(int(o[5]) / DAY)
		if not by_day.has(d):
			by_day[d] = PackedStringArray()
			days.append(d)
		var p := part_of(e, String(o[1]))
		by_day[d].append("%s  %d × %s %s%s" % [o[0], int(o[2]), p["number"], p["title"],
				(" (ordered by %s)" % Permits.person_words(e, o[3])) if o[3] != null else ""])
		if first == -1 or int(o[5]) < first:
			first = int(o[5])
	days.sort()
	var lines := PackedStringArray()
	for d in days:
		lines.append("Day %d" % d)
		for s in by_day[d]:
			lines.append("  " + s)
	var l := W.label("\n".join(lines), 16, W.DIM)
	l.name = "deliveries"
	body.add_child(l)
	var j := jump_to(e, first)
	if not j.is_empty():
		var b := W.button("Jump to the next delivery (%s)" % clock_words(first), func(): ui.inputs.jump(j[0], j[1]))
		b.name = "jump_delivery"
		var why := jump_blocked(e)
		b.disabled = why != "" or not e.fast_forward()
		body.add_child(b)
		if why != "":
			body.add_child(W.label("(%s)" % why, 15, W.DIM))


func _issue_form(e, keep: Array) -> void:
	var c := counter(e)
	title.text = "Stores\nAt the counter: %s" % c["title"]
	var back := W.button("The catalogue", open.bind("list", ""))
	back.name = "to_list"
	body.add_child(back)
	if not at_counter():
		body.add_child(W.label("Parts are drawn at the store's counter, from the storekeeper: walk there first.", 17,
				W.DIM))
		var go := W.button("Take me to the store counter", func(): ui.go_to_place(c["at"]))
		go.name = "go_counter"
		body.add_child(go)
		return
	body.add_child(W.label("Write the request: the part number (from the catalogue or the equipment's data sheet),"
			+ " the quantity and the work order. The storekeeper hands over what is written.", 16, W.DIM))
	number_edit = LineEdit.new()
	number_edit.name = "issue_number"
	number_edit.placeholder_text = "Part number, WDP-…"
	number_edit.text = keep[0]
	number_edit.custom_minimum_size = Vector2(0, 52 * W.scale)
	body.add_child(number_edit)
	qty_edit = LineEdit.new()
	qty_edit.name = "issue_qty"
	qty_edit.placeholder_text = "Quantity"
	qty_edit.text = keep[1] if keep[1] != "" else "1"
	qty_edit.custom_minimum_size = Vector2(0, 52 * W.scale)
	body.add_child(qty_edit)
	work_pick = OptionButton.new()
	work_pick.name = "issue_work"
	work_pick.custom_minimum_size = Vector2(0, 52 * W.scale)
	_work_ids = []
	var ws := issue_works(e)
	if ws.is_empty():
		work_pick.add_item("No work order planned, scheduled or in progress")
		work_pick.disabled = true
	for w in ws:
		work_pick.add_item(_work_words(e, w["id"]))
		_work_ids.append(w["id"])
	var sel: int = _work_ids.find(work) if work != "" else int(keep[2])
	if sel >= 0 and sel < _work_ids.size():
		work_pick.select(sel)
	body.add_child(work_pick)
	var b := W.button("Hand in the request", func():
		var q := qty_edit.text.strip_edges()
		if not q.is_valid_int():
			_show("Write the quantity as a whole number")
			return
		if work_pick.selected < 0 or work_pick.selected >= _work_ids.size():
			_show("Choose the work order the parts are for")
			return
		issue(number_edit.text, q.to_int(), _work_ids[work_pick.selected]))
	b.name = "issue_send"
	b.disabled = ws.is_empty()
	body.add_child(b)
	# what each open order holds already (§2.23: its issued parts)
	var lines := PackedStringArray()
	for w in e.m.works:
		var held := issued_words(e, w["id"])
		if held != "":
			lines.append("%s: %s" % [_work_words(e, w["id"]), held])
	if not lines.is_empty():
		body.add_child(W.label("Issued and not yet fitted", 18, Color.WHITE))
		var l := W.label("\n".join(lines), 16, W.DIM)
		l.name = "issued"
		body.add_child(l)


func _order_form(e, keep: Array) -> void:
	var p := part_of(e, part)
	title.text = "Stores\nOrder: %s" % p["number"]
	var back := W.button("The catalogue", open.bind("list", ""))
	back.name = "to_list"
	body.add_child(back)
	var stock := stock_of(e, part)
	var due := due_of(e, part)
	body.add_child(W.label("%s\nStock %d, on order %d · reorder at %d, max %d · %d days' lead time" % [p["title"],
			stock, due, int(p["reorder"]), int(p["max"]), int(p["lead_days"])], 17, W.DIM))
	order_qty = LineEdit.new()
	order_qty.name = "order_qty"
	order_qty.placeholder_text = "Quantity"
	order_qty.text = keep[3] if keep[3] != "" else str(maxi(1, int(p["max"]) - stock - due))
	order_qty.custom_minimum_size = Vector2(0, 52 * W.scale)
	body.add_child(order_qty)
	var pid := part
	var b := W.button("Order (as the %s)" % role_words(e, "order_parts"), func():
		var q := order_qty.text.strip_edges()
		if not q.is_valid_int():
			_show("Write the quantity as a whole number")
			return
		order(pid, q.to_int()))
	b.name = "order_send"
	b.disabled = not may_order(e, ui.me())
	body.add_child(b)


## A work's issued parts in words ("1 × WDP-PT-UNIT-A3 …"), "" when none.
static func issued_words(e, wid: String) -> String:
	if e._sr == null or not e.sr_issued.has(wid):
		return ""
	var out := PackedStringArray()
	for p in e._sr["parts"]:
		var n: int = int(e.sr_issued[wid].get(p["id"], 0))
		if n > 0:
			out.append("%d × %s %s" % [n, p["number"], p["title"]])
	return "; ".join(out)


# ------------------------------------------------------------------ the work view's and the debrief's words

## A fitting's part (a hand action's `part`) in words: "Fits WDP-… (title)".
static func fitting_words(e, x: Dictionary) -> String:
	var p := part_of(e, String(x.get("part", "")))
	return "" if p.is_empty() else "Fits a new %s (%s), issued against the job's work order" % [p["title"], p["number"]]


## A fitting's refusal (REALISM.md §2.23) in words: `part` names the part to draw; `wrong_part` gives the look-alike's
## sentence (the part offered read against the data sheet). x: the hand action.
static func fit_reason(e, x, r: String) -> String:
	var need := part_of(e, String(x.get("part", ""))) if x != null else {}
	if need.is_empty():
		return r
	if r == "part":
		return "No %s (%s) issued against this job's work order: draw one at the store counter" % [need["title"],
				need["number"]]
	if r == "wrong_part":
		var s := differs_for(e, x)
		return s if s != "" else "The part issued is not the one this job needs (%s)" % need["number"]
	return r


## The sentence of the look-alike the fitting's work holds in place of the part it needs ("" when none).
static func differs_for(e, x: Dictionary) -> String:
	var sr = e._sr
	var pid: String = x["part"]
	var held := {}
	for wi in e._works_on.get(x["kks"], []):
		if e.pstate[wi] == 5:
			held = e.sr_issued.get(e.m.works[wi]["id"], {})
			break
	for q in sr["looked_by"].get(pid, []):
		if int(held.get(q, 0)) >= 1:
			return sr["differs"].get(pid + "|" + q, sr["differs"].get(q + "|" + pid, ""))
	return ""


## The debrief's lines (REALISM.md §2.23): the parts drawn per work (the issues done up to event `to`), and every
## look-alike offered (each fitting refused as the wrong part, with the look-alike's sentence).
static func debrief_lines(e, to: int) -> PackedStringArray:
	var out := PackedStringArray()
	if e == null or e._sr == null:
		return out
	var drawn := {}                 # work -> {part: count}
	var works: Array = []
	var offered := PackedStringArray()
	var evs: Array = e.events
	for i in mini(to, evs.size()):
		var ev: Array = evs[i]
		if ev[1] == "issue" and ev.size() > 6 and ev[6] == "done":
			var w := String(ev[4])
			if not drawn.has(w):
				drawn[w] = {}
				works.append(w)
			drawn[w][ev[2]] = int(drawn[w].get(ev[2], 0)) + int(ev[3])
		elif ev[1] == "hand" and ev.size() > 7 and ev[6] == "refused" and "wrong_part" in ev[7]:
			var x = e.m.hands_ix.get(str(ev[2]) + "|" + str(ev[3]))
			if x == null or not x.has("part"):
				continue
			var need := part_of(e, String(x["part"]))
			var like := PackedStringArray()
			for q in e._sr["looked_by"].get(x["part"], []):
				for w in works:
					if drawn[w].has(q):
						like.append(part_of(e, q)["number"])
						break
			offered.append("at %s, %s offered for %s%s" % [ev[2], ", ".join(like) if not like.is_empty() else
					"a look-alike", need["number"], (": " + _sentence(e, x, like)) if not like.is_empty() else ""])
	if works.is_empty() and offered.is_empty():
		return out
	for w in works:
		var parts := PackedStringArray()
		for p in e._sr["parts"]:
			if drawn[w].has(p["id"]):
				parts.append("%d × %s" % [int(drawn[w][p["id"]]), p["number"]])
		out.append("Parts drawn for %s: %s" % [_work_words(e, w), ", ".join(parts)])
	for s in offered:
		out.append("A look-alike offered: " + s)
	return out


static func _sentence(e, x: Dictionary, like: PackedStringArray) -> String:
	var q := part_by_number(e, like[0])
	return e._sr["differs"].get(String(x["part"]) + "|" + q, e._sr["differs"].get(q + "|" + String(x["part"]), ""))
