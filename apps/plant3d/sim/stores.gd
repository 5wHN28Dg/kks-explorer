extends RefCounted
## The stores (docs/plant3d/REALISM.md §7.2 and §2.23, milestone WM2) as the engine runs them: the values <part>_stock
## and <part>_due, a scenario's `stock`, the inputs [n, "issue", part, qty, work, person] and [n, "order", part, qty,
## person], the deliveries of step 3, the fitting check of a hand action naming a `part`, each work's issued parts, and
## the snapshot's and the digest's parts. Bit for bit with ref/plant3d_stores.py on ref/vectors/plant3d-realism.json's
## `stores`. Only in a plant with stores.json (the model's `stores`): a plant without it never calls in here, but for
## the inputs, which it answers unknown. The jump to a date and §7.4's rule for it are in staff.gd (jump), the NPCs'
## issue and order steps there too.
##
## The engine's state (saved with a run, in the digest): sr_stock and sr_due (per part in the file's order: on the
## shelf, on order), sr_po (the purchase order counter), sr_orders (the pending orders in the order made: [number,
## part, qty, by, ordered clock, due clock]) and sr_issued (work id -> {part: count} of the parts issued against it and
## not yet fitted, each work's parts in the file's order).

const LIMITS := {"qty": 9999, "pending": 8, "jump_days": 30}
const DAY := 864000         # a clock day in tenths of a clock second (§16.1)
const WO_OPEN := [2, 3, 4]  # §2.23: parts are issued against a work order planned, scheduled or in progress


## stores.json as far as the engine reads it (the validator, ref/plant3d_stores.py check, checks every rule): {stores,
## store_ix, parts, ix, looked_by (part -> the parts that list it in looks_like, in file order), differs ("a|b" ->
## the sentence part a gives when b is offered in its place)}, or a String saying why it can't be read.
static func read(d, ext: Array):
	if typeof(d) != TYPE_DICTIONARY or d.get("format") != "walkdown-plant-stores" \
			or typeof(d.get("stores")) != TYPE_ARRAY or d["stores"].is_empty() \
			or typeof(d.get("parts")) != TYPE_ARRAY or d["parts"].is_empty():
		return "not a stores file the engine can read"
	var store_ix := {}
	for i in d["stores"].size():
		var s = d["stores"][i]
		if typeof(s) != TYPE_DICTIONARY or typeof(s.get("id")) != TYPE_STRING or store_ix.has(s["id"]) \
				or typeof(s.get("place")) != TYPE_STRING or typeof(s.get("self_service")) != TYPE_BOOL:
			return "a store the engine can't read"
		store_ix[s["id"]] = i
	var ix := {}
	var looked_by := {}
	for i in d["parts"].size():
		var p = d["parts"][i]
		if typeof(p) != TYPE_DICTIONARY or typeof(p.get("id")) != TYPE_STRING or ix.has(p["id"]) \
				or not store_ix.has(p.get("store")):
			return "a part the engine can't read"
		for k in ["stock", "min", "reorder", "max", "lead_days"]:
			if not _whole(p.get(k)) or float(p[k]) < 0 or float(p[k]) > 9999:
				return "part %s: %s the engine can't read" % [p["id"], k]
		if int(p["stock"]) > int(p["max"]) or int(p["lead_days"]) < 1:
			return "part %s: levels the engine can't read" % p["id"]
		if ext.has(p["id"] + "_stock") or ext.has(p["id"] + "_due"):
			return "part %s: its values are already ext values" % p["id"]
		ix[p["id"]] = i
		looked_by[p["id"]] = []
	var differs := {}
	for p in d["parts"]:
		var l = p.get("looks_like", [])
		if typeof(l) != TYPE_ARRAY:
			return "part %s: looks_like the engine can't read" % p["id"]
		for x in l:
			if typeof(x) != TYPE_DICTIONARY or not ix.has(x.get("part")) or x["part"] == p["id"] \
					or typeof(x.get("differs")) != TYPE_STRING or looked_by[x["part"]].has(p["id"]):
				return "part %s: a look-alike the engine can't read" % p["id"]
			looked_by[x["part"]].append(p["id"])
			differs[p["id"] + "|" + x["part"]] = x["differs"]
	return {"stores": d["stores"], "store_ix": store_ix, "parts": d["parts"], "ix": ix, "looked_by": looked_by,
			"differs": differs}


## The engine-kept values (§2.23), after the work orders': per part in the file's order, <part>_stock then <part>_due.
static func kept(stores) -> Array:
	var out := []
	if stores != null:
		for p in stores["parts"]:
			out.append(p["id"] + "_stock")
			out.append(p["id"] + "_due")
	return out


## A scenario's `stock` (§2.23) as far as the engine reads it: "" when it can.
static func check_scenario(sc: Dictionary, stores) -> String:
	if not sc.has("stock"):
		return ""
	if stores == null or typeof(sc["stock"]) != TYPE_DICTIONARY:
		return "scenario %s: a stock the engine can't read (REALISM.md §2.23)" % str(sc.get("id"))
	for k in sc["stock"]:
		var v = sc["stock"][k]
		if not stores["ix"].has(k) or not _whole(v) or float(v) < 0 \
				or float(v) > float(stores["parts"][stores["ix"][k]]["max"]):
			return "scenario %s: stock.%s the engine can't read" % [str(sc.get("id")), str(k)]
	return ""


static func _whole(x) -> bool:
	var t := typeof(x)
	if t == TYPE_INT:
		return true
	return t == TYPE_FLOAT and is_finite(x) and x == floorf(x) and absf(x) < 1e15


# ---------------------------------------------------------------- the engine's part

## The stores' state of a fresh engine (before step 0): the shelf per part (the file's stock, or the scenario's
## `stock`), on order per part, the counter, no orders, nothing issued.
static func init(e) -> void:
	var st = e.m.stores
	e._sr = st
	e.sr_stock = []
	e.sr_due = []
	e.sr_po = 0
	e.sr_orders = []
	e.sr_issued = {}
	e._sr_slot = PackedInt32Array()
	if st == null:
		return
	var given: Dictionary = e.sc.get("stock", {})
	for p in st["parts"]:
		e.sr_stock.append(int(given.get(p["id"], p["stock"])))
		e.sr_due.append(0)
		e._sr_slot.append(e.ix[p["id"] + "_stock"])
		e._sr_slot.append(e.ix[p["id"] + "_due"])


## Step 0's slots of the stores' values (§2.23).
static func step0(e) -> void:
	for k in e.sr_stock.size():
		_write(e, k)


static func _write(e, k: int) -> void:
	e.cur[e._sr_slot[2 * k]] = float(e.sr_stock[k])
	e.cur[e._sr_slot[2 * k + 1]] = float(e.sr_due[k])


## §2.23: a whole number from 1 to 9,999 (3 or 3.0; not a boolean).
static func _qty_ok(q) -> bool:
	var t := typeof(q)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	var f := float(q)
	return is_finite(f) and absf(f) < 1e9 and f == floorf(f) and f >= 1.0 and f <= float(LIMITS["qty"])


## §2.23: someone on duty at the place whose role holds issue_parts (the person themself counts).
static func keeper_at(e, place: int) -> bool:
	var sm = e._sm
	for pi in sm.people.size():
		if e.sp_on[pi] and e.sp_pos[pi] == place and sm.auth[sm.people[pi]["role"]].has("issue_parts"):
			return true
	return false


## [issue, part, qty, work, person] in step 1 (§2.23): "done", "refused" or "unknown", its event [n, "issue", part,
## qty, work, person, result, [reasons]] made at once.
static func issue(e, item: Array, npc: bool) -> String:
	var part = item[1] if item.size() > 1 else null
	var qty = item[2] if item.size() > 2 else null
	var work = item[3] if item.size() > 3 else null
	var person = item[4] if item.size() > 4 else null
	var st = e._sr
	if st == null or typeof(part) != TYPE_STRING or not st["ix"].has(part) or typeof(work) != TYPE_STRING \
			or not e.m.work_ix.has(work):
		e._ev(["issue", part, qty, work, person, "unknown", []])
		return "unknown"
	var k: int = st["ix"][part]
	var store: Dictionary = st["stores"][st["store_ix"][st["parts"][k]["store"]]]
	var why := []
	if e._authority(person, npc, ""):           # the person check every input has (§17.1)
		why.append("authority")
	var sm = e._sm
	if sm != null and person != null:           # (free mode, person null: neither where nor storekeeper)
		var place: int = sm.pix[store["place"]]
		if typeof(person) == TYPE_STRING and sm.person_ix.has(person) and e.sp_pos[sm.person_ix[person]] != place:
			why.append("where")
		if not store["self_service"] and not keeper_at(e, place):
			why.append("storekeeper")
	if not _qty_ok(qty):
		why.append("qty")
	elif float(qty) > float(e.sr_stock[k]):     # (only for a quantity that is one)
		why.append("stock")
	if e._wo_ids != null and not WO_OPEN.has(e.wo[work]):
		why.append("work")
	if not why.is_empty():
		e._ev(["issue", part, qty, work, person, "refused", why])
		return "refused"
	var q := int(qty)
	e.sr_stock[k] -= q
	_write(e, k)
	if not e.sr_issued.has(work):
		e.sr_issued[work] = {}
	var held: Dictionary = e.sr_issued[work]
	held[part] = held.get(part, 0) + q
	e._ev(["issue", part, qty, work, person, "done", []])
	return "done"


## An NPC's order step without a qty (§2.23): up to the part's max, max - stock - due, when the input is made.
static func order_qty(e, part: String) -> int:
	var k: int = e._sr["ix"][part]
	return int(e._sr["parts"][k]["max"]) - e.sr_stock[k] - e.sr_due[k]


## [order, part, qty, person] in step 1 (§2.23); its event [n, "order", part, qty, person, result, [reasons], number]
## at once (number null unless done).
static func order(e, item: Array, npc: bool) -> String:
	var part = item[1] if item.size() > 1 else null
	var qty = item[2] if item.size() > 2 else null
	var person = item[3] if item.size() > 3 else null
	var st = e._sr
	if st == null or typeof(part) != TYPE_STRING or not st["ix"].has(part):
		e._ev(["order", part, qty, person, "unknown", [], null])
		return "unknown"
	if npc and qty == null:
		qty = order_qty(e, part)
	var k: int = st["ix"][part]
	var why := []
	if e._authority(person, npc, "order_parts"):
		why.append("authority")
	if not _qty_ok(qty):
		why.append("qty")
	var pending := 0
	for o in e.sr_orders:
		if o[1] == part:
			pending += 1
	if pending >= LIMITS["pending"]:
		why.append("pending")
	if not why.is_empty():
		e._ev(["order", part, qty, person, "refused", why, null])
		return "refused"
	var q := int(qty)
	e.sr_po += 1
	var no := "PO-%04d" % e.sr_po
	var c: int = e.clock()
	e.sr_orders.append([no, part, q, person, c, c + int(st["parts"][k]["lead_days"]) * DAY])
	e.sr_due[k] += q
	_write(e, k)
	e._ev(["order", part, qty, person, "done", [], no])
	return "done"


## Step 3, after the hand actions whose minutes end (§2.7, §2.23): every pending order whose due clock is reached, in
## the order made: the shelf up by its qty, on order down by it, the event [n, "delivery", number, part, qty].
static func deliveries(e) -> void:
	if e.sr_orders.is_empty():
		return
	var c: int = e.clock()
	var keep := []
	for o in e.sr_orders:
		if c >= o[5]:
			var k: int = e._sr["ix"][o[1]]
			e.sr_stock[k] += o[2]
			e.sr_due[k] -= o[2]
			_write(e, k)
			e._ev(["delivery", o[0], o[1], o[2]])
		else:
			keep.append(o)
	e.sr_orders = keep


# ---------------------------------------------------------------- fitting a part (§2.23, the look-alike's lesson)

## The work a fitting is made under: the first work on the code, in model order, whose permit is accepted; or null.
static func fit_work(e, kks: String):
	for wi in e._works_on.get(kks, []):
		if e.pstate[wi] == 5:
			return e.m.works[wi]["id"]
	return null


## After `value` (§2.23): `part` when that work holds none of the action's part (or there is no such work);
## `wrong_part` instead when it holds none but holds a part that lists it in `looks_like`; else nothing.
static func fit_reasons(e, x: Dictionary) -> Array:
	var part: String = x["part"]
	var w = fit_work(e, x["kks"])
	var held: Dictionary = e.sr_issued.get(w, {}) if w != null else {}
	if held.get(part, 0) >= 1:
		return []
	for q in e._sr["looked_by"][part]:
		if held.get(q, 0) >= 1:
			return ["wrong_part"]
	return ["part"]


## The part taken from the work's issued parts when the action starts (or is done at once): returns the work.
static func fit_take(e, x: Dictionary) -> String:
	var w: String = fit_work(e, x["kks"])
	var held: Dictionary = e.sr_issued[w]
	held[x["part"]] -= 1
	if held[x["part"]] == 0:
		held.erase(x["part"])
		if held.is_empty():
			e.sr_issued.erase(w)
	return w


## An abandoned fitting gives its part back to the work it was taken from (§2.23): a busy record's seventh element.
static func give_back(e, b: Array) -> void:
	if b.size() <= 6:
		return
	var part: String = e._hands[b[0] + "|" + b[1]]["part"]
	if not e.sr_issued.has(b[6]):
		e.sr_issued[b[6]] = {}
	var held: Dictionary = e.sr_issued[b[6]]
	held[part] = held.get(part, 0) + 1


# ---------------------------------------------------------------- the snapshot's and the digest's parts (§2.23)

## A work's issued parts as [part, count] pairs in the file's order.
static func issued_of(e, wid: String) -> Array:
	var held: Dictionary = e.sr_issued.get(wid, {})
	var out := []
	if held.is_empty():
		return out
	for p in e._sr["parts"]:
		if held.has(p["id"]):
			out.append([p["id"], held[p["id"]]])
	return out


static func snapshot_part(e, s: Dictionary) -> void:
	var stock := {}
	var due := {}
	for k in e._sr["parts"].size():
		var pid: String = e._sr["parts"][k]["id"]
		stock[pid] = e.sr_stock[k]
		if e.sr_due[k] != 0:
			due[pid] = e.sr_due[k]
	var orders := []
	for o in e.sr_orders:
		orders.append(o.duplicate())
	var issued := {}
	for w in e.m.works:
		if e.sr_issued.has(w["id"]):
			var h := {}
			for pr in issued_of(e, w["id"]):
				h[pr[0]] = pr[1]
			issued[w["id"]] = h
	s["stores"] = {"po": e.sr_po, "stock": stock, "due": due, "orders": orders, "issued": issued}


## The digest's stores part (§2.23), after the work orders': [the PO counter, the stock per part, on order per part
## (the file's order), the pending orders [number, part, qty, by, ordered, due] in the order made, per work in model
## order the issued parts as (part index, count) pairs in the file's order].
static func digest_part(e) -> Array:
	var orders := []
	for o in e.sr_orders:
		orders.append(o.duplicate())
	var per := []
	for w in e.m.works:
		var a := PackedInt64Array()
		for pr in issued_of(e, w["id"]):
			a.append(e._sr["ix"][pr[0]])
			a.append(pr[1])
		per.append(a)
	return [e.sr_po, PackedInt64Array(e.sr_stock), PackedInt64Array(e.sr_due), orders, per]
