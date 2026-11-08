extends RefCounted
## Walkdown Plant's discussions (docs/plant3d/REALISM.md §6.3, settled in §6.3.1; milestone DC3) as the engine runs
## them: discussions.json read, the task step `discuss` (a lead's meeting, a joiner's wait), the input `discuss`, the
## state in the digest and the snapshot. Bit for bit with ref/plant3d_discuss.py on ref/vectors/plant3d-realism.json's
## `discuss` part and the first train's vectors. Gated by the plant's discussions.json (staff.gd's `discuss`): a plant
## without it never calls in here.
##
## The engine's state (saved with a run, in the digest): `dsc`, per discussion in file order its live or last
## instance ({} before its first start): {count, lead, parts (PackedInt32Array, -1 none), mode (0 npc, 1 open), start,
## point, since, opt and by (PackedInt32Array, -1 none or a default), agreed (-1 while unended)}.

const MODES := ["npc", "open"]
const JOIN_WAIT := 15           # clock minutes: a meeting's wait for its people, a joiner's for a discussion
const EVIDENCE := {"manual": ["manual", "section"], "standard": ["cite"], "reading": ["code", "value"], "rule": []}


## discussions.json against the staff's rooms, roles and tasks: {list, ix} with each discussion's "_pix" (point id ->
## index) and "_opt" (per point: option id -> index), or a String saying why it can't be read. The reference checks
## every rule (ref/plant3d_discuss.py check); here only what the engine leans on.
static func read(doc, st, m):
	if typeof(doc) != TYPE_DICTIONARY or doc.get("format") != "walkdown-plant-discussion" \
			or typeof(doc.get("discussions")) != TYPE_ARRAY or doc["discussions"].is_empty():
		return "not a discussions file the engine can read"
	var out := []
	var ix := {}
	for x in doc["discussions"]:
		if typeof(x) != TYPE_DICTIONARY or typeof(x.get("id")) != TYPE_STRING or ix.has(x["id"]):
			return "a discussion without an id of its own"
		var did: String = x["id"]
		if not st.rooms.has(x.get("room")) or st.door.get(x["room"], -1) == -1:
			return "discussion %s: no room with a door %s" % [did, str(x.get("room"))]
		var roles = x.get("roles")
		if typeof(roles) != TYPE_ARRAY or roles.size() < 2 or roles.size() > 3:
			return "discussion %s: 2–3 roles" % did
		for r in roles:
			if not st.roles.has(r):
				return "discussion %s: no role %s" % [did, str(r)]
		if typeof(x.get("minutes")) != TYPE_INT or x["minutes"] < 1:
			return "discussion %s: its minutes" % did
		var pix := {}
		var opts := []
		if typeof(x.get("points")) != TYPE_ARRAY or x["points"].is_empty():
			return "discussion %s: no points" % did
		for pt in x["points"]:
			if typeof(pt) != TYPE_DICTIONARY or typeof(pt.get("id")) != TYPE_STRING or pix.has(pt["id"]) \
					or typeof(pt.get("minutes")) != TYPE_INT or pt["minutes"] < 1 \
					or typeof(pt.get("options")) != TYPE_ARRAY or pt["options"].size() < 2:
				return "discussion %s: a point the engine can't run" % did
			var oix := {}
			for o in pt["options"]:
				if typeof(o) != TYPE_DICTIONARY or typeof(o.get("id")) != TYPE_STRING or oix.has(o["id"]):
					return "discussion %s: an option the engine can't run" % did
				oix[o["id"]] = oix.size()
			if not oix.has(pt.get("default")):
				return "discussion %s: point %s has no default" % [did, pt["id"]]
			pix[pt["id"]] = pix.size()
			opts.append(oix)
		var ags = x.get("agreements")
		if typeof(ags) != TYPE_ARRAY or ags.is_empty():
			return "discussion %s: no agreements" % did
		for j in ags.size():
			var a = ags[j]
			if typeof(a) != TYPE_DICTIONARY or typeof(a.get("when")) != TYPE_ARRAY \
					or typeof(a.get("outcome")) != TYPE_DICTIONARY or (j == ags.size() - 1 and not a["when"].is_empty()):
				return "discussion %s: an agreement the engine can't reach" % did
			for t in a["when"]:
				if typeof(t) != TYPE_DICTIONARY:
					return "discussion %s: a term the engine can't read" % did
				if t.has("point"):
					if not pix.has(t["point"]) or not opts[pix[t["point"]]].has(t.get("option")):
						return "discussion %s: a term of no option" % did
				elif not m.ix.has(t.get("value")) or typeof(t.get("is")) != TYPE_BOOL:
					return "discussion %s: a term of no value" % did
			var tk = a["outcome"].get("task")
			if tk != null and not st.tasks.has(tk):
				return "discussion %s: no task %s" % [did, str(tk)]
		var d: Dictionary = x.duplicate()
		d["_pix"] = pix
		d["_opt"] = opts
		ix[did] = out.size()
		out.append(d)
	return {"list": out, "ix": ix}


## The outcome tasks a `discuss` step may run in place of the rest of its task, in file order.
static func outcomes(st, s: Dictionary) -> Array:
	var d: Dictionary = st.discuss["list"][st.discuss["ix"][s["discuss"]]]
	var out := []
	for a in d["agreements"]:
		if a["outcome"].has("task"):
			out.append(a["outcome"]["task"])
	return out


# ---------------------------------------------------------------- the engine (§6.3.1)

## Whether the instance is live: started, no agreement yet, and its lead still has a task at a step of this
## discussion (current, queued or held).
static func _live(e, d: Dictionary, x: Dictionary) -> bool:
	if x.is_empty() or x["agreed"] >= 0:
		return false
	var q: int = x["lead"]
	var all := []
	if e.sp_cur[q] != null:
		all.append(e.sp_cur[q])
	all.append_array(e.sp_queue[q])
	all.append_array(e.sp_held[q])
	for inst in all:
		var steps: Array = e._sm.tasks[inst["task"]]["steps"]
		if inst["step"] < steps.size() and steps[inst["step"]].get("discuss") == d["id"]:
			return true
	return false


## A `discuss` step's turn for person pi: the lead's (the discussion's first role) or a joiner's. "next", "wait", a
## go's result or ["task", id] as `choose` gives.
static func step(st, e, pi: int, cur: Dictionary, did: String, trainee: bool):
	var di: int = st.discuss["ix"][did]
	var d: Dictionary = st.discuss["list"][di]
	if st.people[pi]["role"] == d["roles"][0]:
		return _lead(st, e, pi, cur, di, d, trainee)
	return _join(st, e, pi, cur, di, d, trainee)


## A meet's seating and wait (staff.gd meet's first half): "" once met (the joining roles in the room, or 15 clock
## minutes waited), else what the turn returns.
static func _gather(st, e, pi: int, cur: Dictionary, room: String, roles: Array, trainee: bool) -> String:
	var x: Dictionary = cur["st"]
	if not x.has("place"):
		x["place"] = st.meet_place(e, room, pi)
	if trainee and not x.has("seat"):
		x["seat"] = true
		if x["place"] != -1 and not st.taken(e, x["place"], pi):
			st.reserve(e, pi, x["place"])
	if not trainee:
		var r: String = st.go(e, pi, cur, int(x["place"]))
		if r != "next":
			return r
		x.erase("dest")
	elif e.sp_pos[pi] != x["place"]:
		return "wait"
	if not x.has("meet_since"):
		x["meet_since"] = e.step_no
	var rm: PackedInt32Array = st.rooms[room]
	var all := true
	for r in roles:
		var found := false
		for qi in st.role_people.get(r, PackedInt32Array()):
			if qi != pi and e.sp_on[qi] and e.sp_pos[qi] != -1 and rm.has(e.sp_pos[qi]):
				found = true
				break
		if not found:
			all = false
			break
	if all or e.step_no - int(x["meet_since"]) >= JOIN_WAIT * st.tpm:
		return ""
	return "wait"


static func _lead(st, e, pi: int, cur: Dictionary, di: int, d: Dictionary, trainee: bool):
	var n: int = e.step_no
	var x: Dictionary = e.dsc[di]
	var live := _live(e, d, x)
	if live and x["lead"] != pi:
		return "wait"               # another discussion of the same id is live: the step waits
	if not live:
		var r := _gather(st, e, pi, cur, d["room"], d["roles"].slice(1), trainee)
		if r != "":
			return r
		var rm: PackedInt32Array = st.rooms[d["room"]]
		var parts := PackedInt32Array([pi])
		for role in d["roles"].slice(1):
			var who := -1
			for qi in st.people.size():     # (the first of the role in the room, in person order)
				if qi != pi and e.sp_on[qi] and e.sp_pos[qi] != -1 and rm.has(e.sp_pos[qi]) \
						and st.people[qi]["role"] == role:
					who = qi
					break
			parts.append(who)
		var mode := 0
		for i in parts:
			if i >= 0 and e.slot_of(i) != -1:
				mode = 1
		var npts: int = d["points"].size()
		var none := PackedInt32Array()
		none.resize(npts)
		none.fill(-1)
		x = {"count": (x["count"] if not x.is_empty() else 0) + 1, "lead": pi, "parts": parts, "mode": mode,
				"start": n, "point": 0, "since": n, "opt": none, "by": none.duplicate(), "agreed": -1}
		e.dsc[di] = x
		var ids := []
		for i in parts:
			ids.append(st.people[i]["id"] if i >= 0 else null)
		e._ev(["discussion", d["id"], "start", st.people[pi]["id"], ids, MODES[mode]])
		return "wait"
	var pts: Array = d["points"]
	if x["mode"] == 0:
		if n - int(x["start"]) < int(d["minutes"]) * st.tpm:
			return "wait"
		for k in pts.size():
			_take(st, e, d, x, k, d["_opt"][k][pts[k]["default"]], -1)
		x["point"] = pts.size()
	else:
		while x["point"] < pts.size():
			var k: int = x["point"]
			if x["opt"][k] < 0:
				if n - int(x["since"]) < int(pts[k]["minutes"]) * st.tpm:
					return "wait"
				_take(st, e, d, x, k, d["_opt"][k][pts[k]["default"]], -1)
			x["point"] = k + 1
			x["since"] = n
	return _end(e, d, x)


static func _take(st, e, d: Dictionary, x: Dictionary, k: int, oi: int, who: int) -> void:
	x["opt"][k] = oi
	x["by"][k] = who
	var pt: Dictionary = d["points"][k]
	e._ev(["point", d["id"], pt["id"], pt["options"][oi]["id"], st.people[who]["id"] if who >= 0 else null])


static func _holds(e, d: Dictionary, x: Dictionary, t: Dictionary) -> bool:
	if t.has("point"):
		var k: int = d["_pix"][t["point"]]
		return x["opt"][k] == d["_opt"][k][t["option"]]
	return e.truth(t["value"]) == t["is"]


## The first agreement whose terms all hold (the last has none): its event, then the lead's step ends.
static func _end(e, d: Dictionary, x: Dictionary):
	var ags: Array = d["agreements"]
	var j := 0
	for jj in ags.size():
		var ok := true
		for t in ags[jj]["when"]:
			if not _holds(e, d, x, t):
				ok = false
				break
		if ok:
			j = jj
			break
	var task = ags[j]["outcome"].get("task")
	x["agreed"] = j
	e._ev(["discussion", d["id"], "agreed", j, task])
	return ["task", task] if task != null else "next"


## A joiner's step: to the room (an NPC to the meeting's first free seat, as a meet), then done when the discussion it
## takes part in ends, or after 15 clock minutes in the room without one.
static func _join(st, e, pi: int, cur: Dictionary, di: int, d: Dictionary, trainee: bool) -> String:
	var n: int = e.step_no
	var c: Dictionary = cur["st"]
	if not c.has("place"):
		c["place"] = st.meet_place(e, d["room"], pi)
	if not trainee and not c.has("arr"):
		var r: String = st.go(e, pi, cur, int(c["place"]))
		if r != "next":
			return r
		c.erase("dest")
	var x: Dictionary = e.dsc[di]
	if not c.has("arr"):
		if e.sp_pos[pi] == -1 or not st.rooms[d["room"]].has(e.sp_pos[pi]):
			return "wait"
		c["arr"] = n
		c["cnt"] = 0 if x.is_empty() else int(x["count"]) - (1 if _live(e, d, x) else 0)     # (those ended before)
	var mine: bool = not x.is_empty() and x["count"] > c["cnt"] and x["parts"].has(pi)
	if mine and not _live(e, d, x):
		return "next"
	if not mine and n - int(c["arr"]) >= JOIN_WAIT * st.tpm:
		return "next"
	return "wait"


## A player's `[discuss, id, point, option]` in step 1, for their person tp (-1 in free mode): its event, and the
## point taken when done.
static func t_discuss(st, e, tp: int, item: Array) -> void:
	var it := item.slice(1, 4)
	while it.size() < 3:
		it.append(null)
	var did = it[0]
	var point = it[1]
	var option = it[2]
	var D = st.discuss
	var di: int = D["ix"].get(did, -1) if D != null and typeof(did) == TYPE_STRING else -1
	var d: Dictionary = D["list"][di] if di >= 0 else {}
	var k: int = d["_pix"].get(point, -1) if di >= 0 and typeof(point) == TYPE_STRING else -1
	var oi: int = d["_opt"][k].get(option, -1) if k >= 0 and typeof(option) == TYPE_STRING else -1
	var why := []
	var x := {}
	if oi < 0:
		why.append("unknown")
	else:
		x = e.dsc[di]
		var live := _live(e, d, x)
		if tp == -1 or (live and not x["parts"].has(tp)):
			why.append("authority")
		if not live or x["mode"] != 1 or x["point"] != k or x["opt"][k] >= 0:
			why.append("state")
	e._ev(["discuss", st.people[tp]["id"] if tp != -1 else null, did, point, option,
			"refused" if not why.is_empty() else "done", why])
	if why.is_empty():
		_take(st, e, d, x, k, oi, tp)


## The digest's part: per discussion in file order [] before its first start, else [count, lead, participants, mode,
## start step, current point, the step it began, options taken, takers, the agreement reached].
static func digest_part(e) -> Array:
	var out := []
	for x in e.dsc:
		out.append([] if x.is_empty() else [x["count"], x["lead"], x["parts"], x["mode"], x["start"], x["point"],
				x["since"], x["opt"], x["by"], x["agreed"]])
	return out


## The snapshot's `discussions`: {id: {...}} for each discussion started at least once.
static func snapshot_part(st, e) -> Dictionary:
	var out := {}
	for di in st.discuss["list"].size():
		var d: Dictionary = st.discuss["list"][di]
		var x: Dictionary = e.dsc[di]
		if x.is_empty():
			continue
		var parts := []
		for i in x["parts"]:
			parts.append(st.people[i]["id"] if i >= 0 else null)
		var taken := []
		for k in x["opt"].size():
			var o: int = x["opt"][k]
			var by: int = x["by"][k]
			taken.append([d["points"][k]["options"][o]["id"], st.people[by]["id"] if by >= 0 else null] if o >= 0 else null)
		out[d["id"]] = {"count": x["count"], "lead": st.people[x["lead"]]["id"], "participants": parts,
				"mode": MODES[x["mode"]], "start": x["start"], "point": x["point"], "since": x["since"], "taken": taken,
				"agreed": x["agreed"] if x["agreed"] >= 0 else null}
	return out


## Why a saved run's `dsc` can't be continued with this content, or "".
static func contents(st, d) -> String:
	if typeof(d) != TYPE_ARRAY or d.size() != (st.discuss["list"].size() if st != null and st.discuss != null else 0):
		return "a damaged dsc"
	var np: int = st.people.size() if st != null else 0
	for di in d.size():
		var x = d[di]
		if typeof(x) != TYPE_DICTIONARY:
			return "a damaged dsc"
		if x.is_empty():
			continue
		var dd: Dictionary = st.discuss["list"][di]
		var npts: int = dd["points"].size()
		for key in ["count", "lead", "mode", "start", "point", "since", "agreed"]:
			if typeof(x.get(key)) != TYPE_INT:
				return "a damaged dsc"
		for key in ["parts", "opt", "by"]:
			if typeof(x.get(key)) != TYPE_PACKED_INT32_ARRAY:
				return "a damaged dsc"
		if x.size() != 10 or x["count"] < 1 or x["lead"] < 0 or x["lead"] >= np or x["mode"] < 0 or x["mode"] > 1 \
				or x["start"] < 0 or x["since"] < x["start"] or x["point"] < 0 or x["point"] > npts \
				or x["agreed"] < -1 or x["agreed"] >= dd["agreements"].size() \
				or x["parts"].size() != dd["roles"].size() or x["parts"][0] != x["lead"] \
				or x["opt"].size() != npts or x["by"].size() != npts:
			return "a discussion in a state that doesn't exist"
		for i in x["parts"]:
			if i < -1 or i >= np:
				return "a discussion with a person who isn't there"
		for k in npts:
			var o: int = x["opt"][k]
			if o < -1 or o >= dd["points"][k]["options"].size() or x["by"][k] < -1 or x["by"][k] >= np \
					or (o == -1 and x["by"][k] != -1):
				return "a discussion with an option that doesn't exist"
	return ""
