extends RefCounted
## Work orders (docs/plant3d/REALISM.md §7.1 and §2.20, milestone WM1) as the engine runs them: the input
## [n, "wo", work, action, person, data], the move to in progress by itself, an NPC's write-up of their job, each work
## order's record and the run's history, the snapshot's and the digest's parts. Bit for bit with ref/plant3d_wo.py on
## ref/vectors/plant3d-realism.json's `wo`. Only in a plant with workorders.json (the model's wo_ids): a plant without
## it never calls in here.
##
## The engine's state (saved with a run, in the digest): wo (work id -> 0 none … 7 cancelled), wo_no (work id ->
## its current work order's number), wo_rec (work id -> its current record), wo_count, wo_history (the run's closed and
## cancelled records, in that order), wo_npc_done (this step's NPC dones, [work, person], for step 3).
##
## A record: [number, clocks (an Array of 6 ints: notified, planned, scheduled, started, completed, ended; -1 before),
## notifier, mode named, priority (0 before), day (-1 before), completer, [mode, cause, action], comment, work id].

const STATES := ["none", "notified", "planned", "scheduled", "in_progress", "complete", "closed", "cancelled"]
## action -> [the states it is made from, the state it moves to]
const ACTIONS := {"notify": [[0, 6, 7], 1], "plan": [[1], 2], "schedule": [[2], 3], "complete": [[4], 5],
		"close": [[5], 6], "cancel": [[1, 2, 3, 4], 7]}
## who may make each ("": any person, as §17.1 checks a person)
const AUTH := {"notify": "", "plan": "plan_work", "schedule": "plan_work", "complete": "accept",
		"close": "close_work", "cancel": "close_work"}
const DAY := 864000         # a clock day in tenths of a clock second (§16.1)
const DAYS_AHEAD := 365
const COMMENT := 120
const LIVE := [0, 9, 10]    # permit states that are not live: none, closed, cancelled
const DONE := [6, 7, 8, 9]  # permit states past the work: done, returned, deisolated, closed
const T_NOTIFY := 0
const T_PLAN := 1
const T_SCHEDULE := 2
const T_START := 3
const T_COMPLETE := 4
const T_END := 5


## The work order state of a fresh engine (with the model's wo_ids, else nothing).
static func init(e) -> void:
	var m = e.m
	e._wo_ids = m.wo_ids
	e.wo = {}
	e._wo_slot = PackedInt32Array()
	if m.wo_ids == null:
		return
	for w in m.works:
		e.wo[w["id"]] = 0
		e._wo_slot.append(e.ix[w["id"] + "_wo"])


static func new_record(no: String, work: String) -> Array:
	return [no, [-1, -1, -1, -1, -1, -1], null, null, 0, -1, null, [null, null, null], "", work]


static func copy_record(r: Array) -> Array:
	return [r[0], r[1].duplicate(), r[2], r[3], r[4], r[5], r[6], r[7].duplicate(), r[8], r[9]]


static func _num(x) -> bool:
	var t := typeof(x)
	if t == TYPE_INT:
		return absi(x) < 1000000000
	if t == TYPE_FLOAT:
		return is_finite(x) and absf(x) < 1e9
	return false


## A whole number as the inputs give it (3 or 3.0; not a boolean).
static func _whole(x) -> bool:
	return _num(x) and float(x) == floorf(float(x))


static func _id_in(x, ids: Array, nullable: bool) -> bool:
	if x == null:
		return nullable
	return typeof(x) == TYPE_STRING and ids.has(x)


static func _data_ok(e, action: String, data: Array) -> bool:
	var ids: Dictionary = e._wo_ids
	match action:
		"notify":
			return data.size() == 1 and _id_in(data[0], ids["modes"], true)
		"plan":
			return data.size() == 1 and _whole(data[0]) and float(data[0]) >= 1.0 and float(data[0]) <= 4.0
		"schedule":
			var today: int = e.clock() / DAY
			return data.size() == 1 and _whole(data[0]) and float(data[0]) >= float(today) \
					and float(data[0]) <= float(today + DAYS_AHEAD)
		"complete":
			return data.size() == 4 and _id_in(data[0], ids["modes"], true) and _id_in(data[1], ids["causes"], true) \
					and _id_in(data[2], ids["actions"], false) and typeof(data[3]) == TYPE_STRING \
					and String(data[3]).length() <= COMMENT
	return data.is_empty()


## The data an NPC's wo step sends without its own (§2.20).
static func npc_data(e, w: Dictionary, action: String) -> Array:
	match action:
		"notify":
			return [w["finds"][0] if w.has("finds") and not w["finds"].is_empty() else null]
		"plan":
			return [3]
		"schedule":
			return [e.clock() / DAY]
		"complete":
			return [w["codes"][0], w["codes"][1], w["codes"][2], ""]
	return []


## [wo, work, action, person, data] in step 1 (§2.20): "done", "refused" or "unknown", with its event at once.
static func wo_input(e, item: Array, npc: bool) -> String:
	var work = item[1] if item.size() > 1 else null
	var action = item[2] if item.size() > 2 else null
	var person = item[3] if item.size() > 3 else null
	var data = item[4] if item.size() > 4 else null
	var m = e.m
	var known_work: bool = typeof(work) == TYPE_STRING and m.work_ix.has(work)
	var known_action: bool = typeof(action) == TYPE_STRING and ACTIONS.has(action)
	if npc and data == null and e._wo_ids != null and known_work and known_action:
		data = npc_data(e, m.works[m.work_ix[work]], action)     # an NPC's step without data: the defaults, now
	if e._wo_ids == null or not known_work or not known_action or typeof(data) != TYPE_ARRAY:
		e._ev(["wo", work, action, person, "unknown", []])
		return "unknown"
	var wi: int = m.work_ix[work]
	var w: Dictionary = m.works[wi]
	var spec: Array = ACTIONS[action]
	var st: int = e.wo[work]
	var ps: int = e.pstate[wi]
	var why := []
	if e._authority(person, npc, AUTH[action], w["discipline"] if action == "complete" else null):
		why.append("authority")
	if not spec[0].has(st):
		why.append("state")
	if (action == "complete" and not DONE.has(ps)) or ((action == "close" or action == "cancel") and not LIVE.has(ps)):
		why.append("permit")
	if not _data_ok(e, action, data):
		why.append("data")
	if not why.is_empty():
		e._ev(["wo", work, action, person, "refused", why])
		return "refused"
	_move(e, wi, action, person, data, spec[1])
	e._ev(["wo", work, action, person, "done", []])
	return "done"


static func _move(e, wi: int, action: String, person, data: Array, to: int) -> void:
	var work: String = e.m.works[wi]["id"]
	var c: int = e.clock()
	var r: Array
	if action == "notify":
		e.wo_count += 1
		e.wo_no[work] = "WO-%04d" % e.wo_count
		r = new_record(e.wo_no[work], work)
		e.wo_rec[work] = r
		r[1][T_NOTIFY] = c
		r[2] = person
		r[3] = data[0]
	else:
		r = e.wo_rec[work]
		match action:
			"plan":
				r[1][T_PLAN] = c
				r[4] = int(data[0])
			"schedule":
				r[1][T_SCHEDULE] = c
				r[5] = int(data[0])
			"complete":
				r[1][T_COMPLETE] = c
				r[6] = person
				r[7] = [data[0], data[1], data[2]]
				r[8] = data[3]
			_:              # close, cancel
				r[1][T_END] = c
				e.wo_history.append(copy_record(r))
	e.wo[work] = to
	e.cur[e._wo_slot[wi]] = float(to)


## A permit's done made in step 1: an NPC's is noted for step 3's write-up (§2.20).
static func note_done(e, work, person, npc: bool) -> void:
	if npc and e._wo_ids != null:
		e.wo_npc_done.append([work, person])


## Step 3, after the permits' automatic moves (§2.20): work orders whose permit is accepted or done go to in progress,
## in model order; then each NPC's done of this step, in the order made, writes up its work order.
static func step3(e) -> void:
	var m = e.m
	var c: int = e.clock()
	for wi in m.works.size():
		var wid: String = m.works[wi]["id"]
		var s: int = e.wo[wid]
		if s >= 1 and s <= 3 and (e.pstate[wi] == 5 or e.pstate[wi] == 6):
			e.wo[wid] = 4
			e.wo_rec[wid][1][T_START] = c
			e.cur[e._wo_slot[wi]] = 4.0
			e._ev(["wo", wid, "auto", null, "done", [4]])
	var done: Array = e.wo_npc_done
	e.wo_npc_done = []
	for x in done:
		var wi: int = m.work_ix[x[0]]
		var w: Dictionary = m.works[wi]
		if e.wo[x[0]] == 4 and w.has("codes"):
			_move(e, wi, "complete", x[1], [w["codes"][0], w["codes"][1], w["codes"][2], ""], 5)
			e._ev(["wo", x[0], "complete", x[1], "done", []])


static func _rec_out(r: Array) -> Dictionary:
	return {"no": r[0], "clocks": r[1].duplicate(), "by": r[2], "mode": r[3], "priority": r[4], "day": r[5],
			"completer": r[6], "codes": r[7].duplicate(), "comment": r[8],
			"work": r[9]}


static func snapshot_part(e, s: Dictionary) -> void:
	var cur := {}
	for wi in e.m.works.size():
		var wid: String = e.m.works[wi]["id"]
		if e.wo_rec.has(wid):
			var o := _rec_out(e.wo_rec[wid])
			o["state"] = e.wo[wid]
			cur[wid] = o
	s["wo"] = cur
	var h := []
	for r in e.wo_history:
		h.append(_rec_out(r))
	s["wo_history"] = h


static func _rec_tree(r: Array) -> Array:
	return [r[0], PackedInt64Array(r[1]), r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]]


## The digest's work order part (§2.20): the counter, each work's state and record in model order (an empty list for
## a work never notified), the history.
static func digest_part(e) -> Array:
	var recs := []
	var states := PackedInt32Array()
	for w in e.m.works:
		states.append(e.wo[w["id"]])
		recs.append(_rec_tree(e.wo_rec[w["id"]]) if e.wo_rec.has(w["id"]) else [])
	var h := []
	for r in e.wo_history:
		h.append(_rec_tree(r))
	return [e.wo_count, states, recs, h]


## A work order's action still holds (§2.20): the same work order (its number) at the action's state or past it (1 to
## 6), or still cancelled.
static func holds(e, w, action: String, no) -> bool:
	var wi: int = e.m.work_ix.get(w, -1) if typeof(w) == TYPE_STRING else -1
	if wi == -1 or e._wo_ids == null:
		return false
	var cur_no = e.wo_no.get(w)
	if typeof(cur_no) != typeof(no) or cur_no != no:
		return false
	var st: int = e.wo[w]
	var to: int = ACTIONS[action][1]
	return st == 7 if to == 7 else (to <= st and st <= 6)
