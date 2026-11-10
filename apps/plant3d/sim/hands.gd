extends RefCounted
## Walkdown Plant's hands-on engine (docs/plant3d/REALISM.md §2.3–§2.7, settled in §2.13; milestone HW1) as the
## engine runs it: tools carried, hand actions, meters, HART ops, hidden causes with works' cures and the NPCs' slips.
## Bit for bit with ref/plant3d_hands.py on ref/vectors/plant3d-realism.json's `hands`. Every piece is gated by its own
## key: a plant without them never calls in here.
##
## The engine's state (saved with a run, in the digest): tool_n (per tool, its counts per place in tools.json's order),
## carried (person id -> tool ids in the order taken), busy (person id -> [code, action, tool, value, end clock,
## place, and for a fitting the work its part came from, REALISM.md §2.23]), cause_of (fault -> its applied cause), cause_s and slip_s (the streams' states).

const Stores = preload("stores.gd")    # a fitting's part (REALISM.md §2.23)

const CARRIED := 12
const WEIGHT := 65536
const MINUTE := 600
const HOUR := 36000         # clock tenths in a clock hour
const LAB_QUEUE := 8        # samples queued per sample node (REALISM.md §2.19)


## Whether a run has any of HW1's keys: its state, saves and digest part only then.
static func keyed(m, sc: Dictionary) -> bool:
	if m.tools != null or not m.hands.is_empty() or not m.meters.is_empty():
		return true
	for w in m.works:
		if w.has("cures"):
			return true
	for f in sc.get("faults", []):
		if f.has("causes"):
			return true
	return m.staff != null and m.staff.has_slips


## (World: sim/world.gd, passed in so that this script preloads nothing: staff.gd preloads it.)
static func init(e, World) -> void:
	var m = e.m
	e._hw = keyed(m, e.sc)
	e._works_on = {}            # (also without HW1's keys: a HART op's permit, REALISM.md §2.15)
	for wi in m.works.size():
		var code: String = m.works[wi]["kks"]
		if not e._works_on.has(code):
			e._works_on[code] = []
		e._works_on[code].append(wi)
	# the lab (REALISM.md §2.19), with or without HW1's keys: each sample node in model order, its queue and its own
	# lab stream (purpose lab, the node's name)
	e._lab = []
	e._lab_of = {}
	e.lab_q = {}
	e.lab_s = {}
	var lseed := -1
	for i in m.values.size():
		if m.values[i][2] != "sample":
			continue
		var nd: Dictionary = m.values[i][1]
		var name: String = m.values[i][0]
		var t := PackedFloat64Array()
		for row in nd["spread"]:
			t.append(float(row[0]))
			t.append(float(row[1]))
		var r = nd["sample"]
		var x := [i, name, e.ix[r] if typeof(r) == TYPE_STRING else -1, 0.0 if typeof(r) == TYPE_STRING else float(r),
				t, ceili(float(nd["hours"]) * HOUR)]
		e._lab_of[name] = x
		e._lab.append(x)
		e.lab_q[name] = []
		if lseed == -1:
			lseed = World.seed_of(e.sc)
		e.lab_s[name] = World.stream(lseed, World.TAGS["lab"], name)
	if not e._hw:
		return
	e._hands = m.hands_ix
	e._meters = m.meters_ix
	e.tool_n = []
	if m.tools != null:
		for at in m.tools["at"]:
			var c := []
			for a in at:
				c.append(int(a[1]))
			e.tool_n.append(c)
	var seed: int = World.seed_of(e.sc)
	for f in e.sc.get("faults", []):
		if f.has("causes"):
			e.cause_s[f["id"]] = World.stream(seed, World.TAGS["causes"], f["id"])
	if m.staff != null and m.staff.has_slips:
		for p in m.staff.people:
			e.slip_s[p["id"]] = World.stream(seed, World.TAGS["slips"], p["id"])


## One draw (§17.5's generator, as World.draw): [the next state, r of 24 bits].
static func _draw(s: int) -> Array:
	s ^= (s << 13) & 0xFFFFFFFF
	s ^= s >> 17
	s ^= (s << 5) & 0xFFFFFFFF
	return [s, s >> 8]


static func _pi(e, person) -> int:
	if e._sm == null or typeof(person) != TYPE_STRING or not e._sm.person_ix.has(person):
		return -1
	return e._sm.person_ix[person]


static func carries_kind(e, pid, kind: String, mode = null) -> bool:
	var tools = e.m.tools
	if tools == null or typeof(pid) != TYPE_STRING:
		return false
	for t in e.carried.get(pid, []):
		var x: Dictionary = tools["list"][tools["ix"][t]]
		if x["kind"] == kind and (mode == null or x.get("modes", []).has(mode)):
			return true
	return false


# ---------------------------------------------------------------- tools carried (§2.3)

## A tool taken (take 1) or put back (0) by a person at their place: its result, its event made.
static func tool(e, item, person, take, npc: bool, tail: Array = []) -> String:
	var tools = e.m.tools
	if tools == null or typeof(item) != TYPE_STRING or not tools["ix"].has(item) or typeof(take) != TYPE_INT \
			or (take != 0 and take != 1):
		e._ev(["tool", item, take, person, "unknown", []] + tail)
		return "unknown"
	var k: int = tools["ix"][item]
	var pi := _pi(e, person)
	var why := []
	if pi == -1 or e._authority(person, npc, ""):
		why.append("authority")
	var at: Array = tools["at"][k]
	var j := -1
	if pi != -1:
		for a in at.size():
			if at[a][0] == e.sp_pos[pi]:
				j = a
				break
	if j == -1:
		why.append("where")
	var have: Array = e.carried.get(person, []) if pi != -1 else []
	if take == 1:
		if j != -1 and e.tool_n[k][j] <= 0:
			why.append("none_left")
		if have.has(item):
			why.append("carried")
		elif have.size() >= CARRIED:
			why.append("full")
	elif not have.has(item):
		why.append("not_carried")
	elif e.busy.has(person) and typeof(e.busy[person][2]) == TYPE_STRING and e.busy[person][2] == item:
		why.append("busy")          # (the tool of their hand action under way stays with it)
	if not why.is_empty():
		e._ev(["tool", item, take, person, "refused", why] + tail)
		return "refused"
	if take == 1:
		e.tool_n[k][j] -= 1
		e.carried[person] = have + [item]
	else:
		e.tool_n[k][j] += 1
		var rest := []
		for t in have:
			if t != item:
				rest.append(t)
		if rest.is_empty():
			e.carried.erase(person)
		else:
			e.carried[person] = rest
	e._ev(["tool", item, take, person, "done", []] + tail)
	return "done"


# ---------------------------------------------------------------- hand actions (§2.4)

static func _hand_authority(e, x: Dictionary, person, npc: bool) -> bool:
	if x.get("work", true):
		for wi in e._works_on.get(x["kks"], []):
			var w: Dictionary = e.m.works[wi]
			if e.pstate[wi] == 5 and not e._authority(person, npc, "accept", w["discipline"], true, w["id"]):
				return false
		return true
	# REALISM.md §2.19: taking samples needs the sample authority (S3's, the chemists'), any other operate_local
	return e._authority(person, npc, "sample" if x.has("samples") else "operate_local")


## A HART op on a locked code (REALISM.md §2.15): the work on that code whose permit is accepted, which holds every
## isolation locking it, and under which the person acts (its acceptor, or another with accept and its discipline
## while the acceptor is off duty): its index, or -1 (ref/plant3d_hands.py hart_permit).
static func hart_permit(e, kks, person, npc: bool) -> int:
	if typeof(person) != TYPE_STRING:
		return -1
	for wi in e._works_on.get(kks, []):
		if e.pstate[wi] != 5:
			continue
		var held := true
		for k in e._iso.size():
			if e.holder[k] == wi:
				continue
			var pts: Array = e._iso[k][1]
			var off: int = e._iso[k][4]
			for p in pts.size():
				if e.lockbits[off + p] and pts[p][0] == kks:
					held = false
					break
			if not held:
				break
		var w: Dictionary = e.m.works[wi]
		if held and not e._authority(person, npc, "accept", w["discipline"], true, w["id"]):
			return wi
	return -1


static func _is_num(x) -> bool:
	var t := typeof(x)
	return (t == TYPE_INT or t == TYPE_FLOAT) and is_finite(float(x)) and absf(float(x)) < 1e9


## A hand action in step 1 (item: [hand, code, action, tool, value, person]): "start", "done", "refused" or "unknown".
static func hand(e, item: Array, npc: bool) -> String:
	var kks = item[1]
	var action = item[2]
	var tl = item[3]
	var value = item[4]
	var person = item[5]
	var x = null
	if typeof(kks) == TYPE_STRING and typeof(action) == TYPE_STRING:
		x = e._hands.get(kks + "|" + action)
	if x == null:
		e._ev(["hand", kks, action, tl, person, "unknown", []])
		return "unknown"
	var why := []
	var pi := _pi(e, person)
	if pi == -1 or _hand_authority(e, x, person, npc):
		why.append("authority")
	if pi != -1 and not e._sm.work_places.get(kks, []).has(e.sp_pos[pi]):
		why.append("where")         # done at a work place of the code (REALISM.md §2.15)
	if pi != -1 and e.busy.has(person):
		why.append("busy")
	var have: Array = e.carried.get(person, []) if pi != -1 else []
	if tl == null:
		if x.has("tools"):
			why.append("tool")
	elif typeof(tl) != TYPE_STRING or not have.has(tl):
		why.append("tool")
	elif not x.get("tools", []).has(tl):
		why.append("wrong_tool")
	for nd in x.get("needs", []):
		if e.prev[e.ix[nd[0]]] < 0.5:
			why.append(nd[0])
	for nd in x.get("samples", []):
		if e.lab_q[nd].size() >= LAB_QUEUE:
			why.append("lab")       # a sample node's queue is full (REALISM.md §2.19)
			break
	if x.has("input") and not (_is_num(value) and float(x["range"][0]) <= float(value)
			and float(value) <= float(x["range"][1])):
		why.append("value")
	if x.has("part"):           # the fitting check (REALISM.md §2.23): part or wrong_part
		why.append_array(Stores.fit_reasons(e, x))
	if not why.is_empty():
		e._ev(["hand", kks, action, tl, person, "refused", why])
		return "refused"
	var fw = Stores.fit_take(e, x) if x.has("part") else null    # the part taken from the work's issued parts
	if x.has("minutes"):
		var end: int = e.clock() + ceili(float(x["minutes"]) * MINUTE)
		e.busy[person] = [kks, action, tl, float(value) if x.has("input") else null, end, e.sp_pos[pi]]
		if fw != null:
			e.busy[person].append(fw)   # (a fitting's busy record: the work its part came from, REALISM.md §2.23)
		e._ev(["hand", kks, action, tl, person, "start", []])
		return "start"
	write(e, x, value, e.prev)
	e._ev(["hand", kks, action, tl, person, "done", []])
	return "done"


## A hand action's writes: its set, then its input; never skipped by a lock (§2.4); then its samples (§2.19), each
## node's ref read from vals (the previous step's values in step 1, the values as they stand in step 3).
static func write(e, x: Dictionary, value, vals: PackedFloat64Array) -> void:
	var s: Dictionary = x.get("set", {})
	for k in s:
		e.cur[e.ix[k]] = float(s[k])
	if x.has("input"):
		e.cur[e.ix[x["input"]]] = float(value)
	if x.has("samples"):
		take_samples(e, x["samples"], vals)


## Step 3, after the renewals: each busy person in staff order; a jump's step or a person no longer at the place
## abandons, the end of the minutes writes and is done (§2.13).
static func end_hands(e, jumped: bool) -> void:
	if e.busy.is_empty() or e._sm == null:
		return
	var c: int = e.clock()
	var people: Array = e._sm.people
	var order := PackedInt32Array()       # the busy people in staff order (as the reference's walk over everyone)
	for pid in e.busy:
		order.append(e._sm.person_ix[pid])
	order.sort()
	for pi in order:
		var pid: String = people[pi]["id"]
		var b = e.busy[pid]
		if jumped or e.sp_pos[pi] != b[5]:
			e.busy.erase(pid)
			Stores.give_back(e, b)
			e._ev(["hand", b[0], b[1], b[2], pid, "abandoned", []])
			_result(e, pi, "abandoned")
		elif c >= b[4]:
			e.busy.erase(pid)
			write(e, e._hands[b[0] + "|" + b[1]], b[3], e.cur)
			e._ev(["hand", b[0], b[1], b[2], pid, "done", []])
			_result(e, pi, "done")


static func _result(e, pi: int, r: String) -> void:
	var c = e.sp_cur[pi]
	if e.slot_of(pi) == -1 and c != null and c["st"].get("hw", false):
		e.sp_result[pi] = r        # (only for the step that waits on it)


## An NPC pre-empted (§17.3's pause) leaves their hand action, in step 9.
static func abandon(e, pi: int) -> void:
	var pid: String = e._sm.people[pi]["id"]
	var b = e.busy.get(pid)
	if b != null:
		e.busy.erase(pid)
		Stores.give_back(e, b)
		e._ev(["hand", b[0], b[1], b[2], pid, "abandoned", []])


## An NPC's slip (§2.13), in step 1 (item: [slip, person, task, step]): its set written directly.
static func slip(e, item: Array) -> void:
	var t = e._sm.tasks.get(item[2]) if e._sm != null and typeof(item[2]) == TYPE_STRING else null
	if t == null or typeof(item[3]) != TYPE_INT or item[3] < 0 or item[3] >= t["steps"].size() \
			or not t["steps"][item[3]].has("slip"):
		return          # (the engine makes no other: nothing, no event)
	var s: Dictionary = t["steps"][item[3]]["slip"]["set"]
	for k in s:
		e.cur[e.ix[k]] = float(s[k])
	e._ev(["slip", item[1], item[2], item[3]])


## When an NPC's hand step is done: one draw from their slip stream (REALISM.md §3.1).
static func slip_draw(e, pid: String, cur: Dictionary, s: Dictionary) -> void:
	var d := _draw(e.slip_s[pid])
	e.slip_s[pid] = d[0]
	if (int(d[1]) * 1000) >> 24 < int(s["slip"]["per_mille"]):
		e.npc_queue.append(["slip", pid, cur["task"], cur["step"]])


## A hand action done earlier still holds: each state of its set has that value, its input the step's value.
static func hand_holds(e, kks, action, value) -> bool:
	if typeof(kks) != TYPE_STRING or typeof(action) != TYPE_STRING:
		return false
	var x = e._hands.get(kks + "|" + action)
	if x == null:
		return false
	var s: Dictionary = x.get("set", {})
	for k in s:
		if e.cur[e.ix[k]] != float(s[k]):
			return false
	if x.has("input") and value != null and e.cur[e.ix[x["input"]]] != float(value):
		return false
	return true


# ---------------------------------------------------------------- meters (§2.5)

static func shown(e, meter: String, vals: PackedFloat64Array) -> float:
	var x: Dictionary = e._meters[meter]
	var ok := true
	for nd in x.get("needs", []):
		if not (vals[e.ix[nd]] >= 0.5):     # (NaN reads false, as the reference's)
			ok = false
			break
	if ok:
		return vals[e.ix[x["value"]]]
	var el = x.get("else", 0)
	if typeof(el) == TYPE_STRING:
		return vals[e.ix[el]]
	return float(el)


static func can_read(e, pid, meter: String) -> bool:
	var x: Dictionary = e._meters[meter]
	return carries_kind(e, pid, x["tool_kind"], x["mode"])


# ---------------------------------------------------------------- hidden causes (§2.6)

## A fault with causes just made (step 3): the named cause (null: none), else one draw from its stream; the cause's
## set after the fault's, and its event.
static func draw_cause(e, f: Dictionary, vals: PackedFloat64Array, named) -> void:
	var fid: String = f["id"]
	var cs: Array = f["causes"]
	var c = null
	if named != null:
		for x in cs:
			if x["id"] == named:
				c = x
				break
	else:
		var ws := []
		var tot := 0
		for x in cs:
			var wt = x["weight"]
			var w := 0
			if typeof(wt) == TYPE_STRING:
				var v: float = vals[e.ix[wt]]
				w = 0 if not v >= 0 else (WEIGHT if v >= WEIGHT else int(floor(v)))
			else:
				w = int(wt)
			ws.append(w)
			tot += w
		var d := _draw(e.cause_s[fid])
		e.cause_s[fid] = d[0]
		c = cs[0]
		if tot > 0:
			var y: int = (int(d[1]) * tot) >> 24
			var acc := 0
			for k in cs.size():
				acc += ws[k]
				if acc > y:
					c = cs[k]
					break
	e.cause_of[fid] = c["id"]
	e._apply_set(e._sets(c["set"]))
	e._ev(["cause", fid, c["id"]])


static func cause(e, f: Dictionary) -> Variant:
	if not f.has("causes"):
		return null
	var cid = e.cause_of.get(f["id"])
	for c in f["causes"]:
		if c["id"] == cid:
			return c
	return null


static func blocked(e, f: Dictionary, wi: int) -> bool:
	if e._blocked(e._sets(f["repair"]), wi):
		return true
	var c = cause(e, f)
	return c != null and c.has("repair") and e._blocked(e._sets(c["repair"]), wi)


static func do_repair(e, f: Dictionary, wi: int) -> void:
	e._apply_set(e._sets(f["repair"]), wi)
	var c = cause(e, f)
	if c != null and c.has("repair"):
		e._apply_set(e._sets(c["repair"]), wi)


## Whether a work puts right its fault's applied cause (a work without cures cures every cause), and the cause's fix
## is made (its `fixed` true as step 2 left it, REALISM.md §2.16).
static func cures(e, wi: int, fid: String, vals: PackedFloat64Array) -> bool:
	var w: Dictionary = e.m.works[wi]
	if not e.cause_of.has(fid):
		return true
	if w.has("cures") and not w["cures"].has(e.cause_of[fid]):
		return false
	var c = cause(e, e._fdef[fid])
	return c == null or not c.has("fixed") or vals[e.ix[c["fixed"]]] >= 0.5


# ---------------------------------------------------------------- the digest's part and the snapshot's (§2.8)

# ---------------------------------------------------------------- the lab (REALISM.md §2.19)

## A sampling hand action done: each of its sample nodes in the list's order takes a sample, ref's value plus
## spread(r / 2^24) from the next draw of its lab stream, queued with its due clock; a node whose queue filled while a
## timed action was under way takes none (no draw). (ref/plant3d_hands.py take_samples)
static func take_samples(e, names: Array, vals: PackedFloat64Array) -> void:
	var c: int = e.clock()
	for nd in names:
		var x: Array = e._lab_of[nd]
		var q: Array = e.lab_q[nd]
		if q.size() >= LAB_QUEUE:
			continue
		var dr := _draw(e.lab_s[nd])
		e.lab_s[nd] = dr[0]
		var v: float = vals[x[2]] if x[2] != -1 else x[3]
		q.append([c + x[5], v + _table_at(x[4], float(dr[1]) / 16777216.0)])


## Step 3, after the hand actions whose minutes end: each sample node in model order takes its queued results that
## are due (due <= the clock), in their order, each with its event.
static func lab_results(e) -> void:
	var c: int = e.clock()
	for x in e._lab:
		var q: Array = e.lab_q[x[1]]
		while not q.is_empty() and q[0][0] <= c:
			var it: Array = q.pop_front()
			e.cur[x[0]] = it[1]
			e._ev(["lab", x[1], it[1]])


static func lab_digest(e) -> Array:
	var out := []
	for x in e._lab:
		var dues := PackedInt64Array()
		var vs := PackedFloat64Array()
		for it in e.lab_q[x[1]]:
			dues.append(it[0])
			vs.append(it[1])
		out.append([e.lab_s[x[1]], dues, vs])
	return out


static func lab_snapshot(e, s: Dictionary) -> void:
	var out := {}
	for x in e._lab:
		var q: Array = e.lab_q[x[1]]
		if not q.is_empty():
			var c := []
			for it in q:
				c.append([it[0], it[1]])
			out[x[1]] = c
	s["lab"] = out


## A table's value at u (sim/world.gd's table_at, linear between rows; this script preloads nothing).
static func _table_at(t: PackedFloat64Array, u: float) -> float:
	var cnt := t.size() / 2
	if u < t[0]:
		return t[1]
	if u >= t[2 * (cnt - 1)]:
		return t[2 * (cnt - 1) + 1]
	var i := 0
	for j in cnt:
		if t[2 * j] <= u:
			i = j
		else:
			break
	return t[2 * i + 1] + (t[2 * i + 3] - t[2 * i + 1]) * (u - t[2 * i]) / (t[2 * i + 2] - t[2 * i])


static func digest_part(e) -> Array:
	var people: Array = e._sm.people if e._sm != null else []
	var counts := PackedInt64Array()
	for x in e.tool_n:
		for c in x:
			counts.append(c)
	var carried := []
	var busy := []
	var slips := PackedInt64Array()
	for p in people:
		var c := PackedInt64Array()
		for t in e.carried.get(p["id"], []):
			c.append(e.m.tools["ix"][t])
		carried.append(c)
		busy.append(e.busy[p["id"]].duplicate() if e.busy.has(p["id"]) else null)
		if not e.slip_s.is_empty():
			slips.append(e.slip_s[p["id"]])
	var causes := []
	for f in e.sc.get("faults", []):
		if f.has("causes"):
			causes.append([e.cause_s[f["id"]], e.cause_of.get(f["id"])])
	return [counts, carried, busy, causes, slips]


static func snapshot_part(e, s: Dictionary) -> void:
	var ks: Array = e.carried.keys()
	ks.sort()
	var c := {}
	for k in ks:
		c[k] = e.carried[k].duplicate()
	s["carried"] = c
	ks = e.busy.keys()
	ks.sort()
	var b := {}
	for k in ks:
		b[k] = [e.busy[k][0], e.busy[k][1], e.busy[k][4]]
	s["busy"] = b
	ks = e.cause_of.keys()
	ks.sort()
	var cs := {}
	for k in ks:
		cs[k] = e.cause_of[k]
	s["causes"] = cs
