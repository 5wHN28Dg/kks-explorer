extends RefCounted
## Format 2's staff (docs/PLANT3D.md §16–§17, milestone S1): staff.json as the engine runs it, and the staff step
## (step 9), bit for bit with the reference (ref/plant3d_staff.py StaffRun) on ref/vectors/plant3d-v2.json `staff`.
##
## This object holds only what is built from the content (shared by an engine's clones, never changed in a run);
## every piece of a run's staff state is a variable of the engine (sim/engine.gd, its `st_` and `sp_` variables), so
## a saved run (ui/run_save.gd) keeps it with no change there, and a clone copies it. The functions here take the
## engine as their first argument.
##
## Mirrors the reference line for line where order matters: people in file order, reactions in file order, queues by
## (priority, step made, order made), routes by the `next` table only (no search at run time, §16.2), random numbers
## by §17.5's 32-bit arithmetic on 64-bit ints (the halves' product, which never passes 2^63).

const DAY := 864000
const MINUTE := 600
const WAIT_PLACE := 15
const QUEUE_MAX := 32
const OPEN_KINDS := ["point", "door", "stop", "muster", "counter", "depot", "work"]
const STATE_NAMES := ["none", "requested", "approved", "isolated", "issued", "accepted", "done", "returned",
		"deisolated", "closed", "cancelled"]
const PERMIT_TO := {"request": 1, "approve": 2, "issue": 4, "accept": 5, "done": 6, "return": 7, "close": 9,
		"cancel": 10}
const PERMIT_AUTH := {"request": "request", "approve": "approve", "issue": "issue", "accept": "accept",
		"done": "accept", "return": "accept", "close": "issue", "cancel": "approve"}

var error := ""
var d := {}                          # staff.json as read
var ds := 6                          # plant.json's clock.day_scale
var tpm := 100                       # steps in a clock minute
var week: Array = []
var start_clock := {}                # plant.json's clock.start
var places: Array = []
var pix := {}                        # place id -> index
var kind := PackedStringArray()      # per place
var open := PackedByteArray()        # per place: 1 when it holds anyone (§16.2)
var room_of: Array = []              # per place: its room or null
var points := PackedInt32Array()     # place indexes of the points
var point_no := PackedInt32Array()   # per place: its point number, -1 for others
var stub := PackedInt32Array()       # per place: its point (places other than points), -1 for points
var ways := {}                       # a * places + b (a < b) -> steps
var next: Array = []                 # per point: PackedInt32Array of the next point to each point
var rooms := {}                      # room -> PackedInt32Array of its places
var door := {}                       # room -> its door (the first door place), or -1
var work_at := {}                    # code -> its work place
var origin := -1
var gate := -1
var roles := {}                      # id -> role
var auth := {}                       # role id -> {authority: true}
var people: Array = []
var person_ix := {}
var rosters := {}
var routines := {}                   # id -> {"slots": [[at kind, at minutes, every or -1, until kind, until minutes, task]], "idle": task}
var tasks := {}                      # id -> task
var reactions: Array = []
var messages := {}
var callable := {}                   # "role\ntask" -> true: what a trainee may call over the radio (§18.7)


static func load_from(m, doc: Dictionary):
	var s = new()
	s._build(m, doc)
	return s


func _fail(msg: String) -> void:
	if error == "":
		error = "staff.json: " + msg


static func hhmm(x) -> int:
	var t: String = x
	return t.substr(0, 2).to_int() * 60 + t.substr(3, 2).to_int()


## A slot's `at` or `until`: [0 start / 1 end / 2 clock, minutes].
static func at_ref(x: String) -> Array:
	for k in [["start", 0], ["end", 1]]:
		if x.begins_with(k[0]):
			var rest := x.substr(k[0].length())
			var sign := -1 if rest[0] == "-" else 1
			var hm := rest.substr(1).split(":")
			return [k[1], sign * (hm[0].to_int() * 60 + hm[1].to_int())]
	return [2, hhmm(x)]


func _build(m, doc: Dictionary) -> void:
	d = doc
	var clock = m.plant.get("clock")
	if clock == null:
		_fail("the plant has no clock")
		return
	ds = int(clock["day_scale"])
	tpm = MINUTE / ds
	week = clock["week"]
	start_clock = clock["start"]
	var speeds: Dictionary = doc["speeds"]
	for p in doc["places"]:
		pix[p["id"]] = places.size()
		places.append(p)
		kind.append(p["kind"])
		open.append(1 if OPEN_KINDS.has(p["kind"]) else 0)
		room_of.append(p.get("room"))
		point_no.append(-1)
		stub.append(-1)
		if p["kind"] == "point":
			point_no[-1] = points.size()
			points.append(places.size() - 1)
		if p.has("room"):
			if not rooms.has(p["room"]):
				rooms[p["room"]] = PackedInt32Array()
			var r: PackedInt32Array = rooms[p["room"]]
			r.append(places.size() - 1)
			rooms[p["room"]] = r
		if p["kind"] == "work" and not work_at.has(p["kks"]):
			work_at[p["kks"]] = places.size() - 1
	for r in rooms:
		door[r] = -1
		for i in rooms[r]:
			if kind[i] == "door":
				door[r] = i
				break
	var np := places.size()
	for w in doc["ways"]:
		if not pix.has(w[0]) or not pix.has(w[1]) or not speeds.has(w[3]):
			_fail("a way joins no places: " + str(w))
			return
		var a: int = pix[w[0]]
		var b: int = pix[w[1]]
		var st := maxi(1, int(ceil(float(w[2]) * 10.0 / float(speeds[w[3]]) - 1e-9)))
		ways[mini(a, b) * np + maxi(a, b)] = st
		if point_no[a] == -1:
			stub[a] = b
		elif point_no[b] == -1:
			stub[b] = a
	for row in doc["next"]:
		next.append(PackedInt32Array(row))
	origin = pix.get(doc["origin"], -1)
	gate = pix.get(doc["gate"], -1)
	for r in doc["roles"]:
		roles[r["id"]] = r
		var a := {}
		for x in r["authority"]:
			a[x] = true
		auth[r["id"]] = a
	for r in doc["rosters"]:
		rosters[r["id"]] = r
	people = doc["people"]
	for i in people.size():
		person_ix[people[i]["id"]] = i
	for t in doc["tasks"]:
		tasks[t["id"]] = t
	for r in doc["routines"]:
		var slots := []
		for s in r["slots"]:
			var at := at_ref(s["at"])
			var every := -1
			var until := [0, 0]
			if s.has("every"):
				var hm: PackedStringArray = String(s["every"]).split(":")
				every = hm[0].to_int() * 60 + hm[1].to_int()
				until = at_ref(s["until"])
			slots.append([at[0], at[1], every, until[0], until[1], s["task"]])
		routines[r["id"]] = {"slots": slots, "idle": r["idle"]}
	reactions = doc.get("reactions", [])
	messages = doc["messages"]
	for t in doc["tasks"]:
		for s in t["steps"]:
			if s.has("call"):
				callable[s["call"]["role"] + "\n" + s["call"]["task"]] = true
	for t in tasks.values():
		for s in t["steps"]:
			if s.has("go") and typeof(s["go"]) == TYPE_STRING and not pix.has(s["go"]):
				_fail("task %s: no place %s" % [t["id"], s["go"]])


func prio_of(tid: String) -> int:
	return int(tasks[tid].get("priority", 3))


## A person's routine: their own `routine` (§17.8), else their role's.
func routine_of(pi: int) -> Dictionary:
	var p: Dictionary = people[pi]
	return routines[p.get("routine", roles[p["role"]]["routine"])]


func idle_of(pi: int) -> String:
	return routine_of(pi)["idle"]


# ---------------------------------------------------------------- random numbers (§17.5)

static func mul32(a: int, b: int) -> int:
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF


static func mix32(x: int) -> int:
	x ^= x >> 16
	x = mul32(x, 0x7feb352d)
	x ^= x >> 15
	x = mul32(x, 0x846ca68b)
	x ^= x >> 16
	return x


static func seed_of(seed: int, i: int) -> int:
	var s := mix32(seed ^ mul32(i + 1, 0x9e3779b9))
	return s if s != 0 else 1


## One draw of person pi's stream: r of 24 bits.
static func draw(e, pi: int) -> int:
	var s: int = e.sp_rng[pi]
	s ^= (s << 13) & 0xFFFFFFFF
	s ^= s >> 17
	s ^= (s << 5) & 0xFFFFFFFF
	e.sp_rng[pi] = s
	return s >> 8


# ---------------------------------------------------------------- a run's start

func init_run(e, scen: Dictionary) -> void:
	var x: Dictionary = scen["staff"]
	var seed: int = x["seed"]
	e._absent = {}
	for a in x.get("absent", []):
		e._absent[person_ix[a]] = true
	e.st_trainee = person_ix[x["trainee"]] if x.get("trainee") != null else -1
	e._fixed_trainee = e.st_trainee != -1
	var n := people.size()
	e.sp_on.resize(n)
	e.sp_planned.resize(n)
	e.sp_pos.resize(n)
	e.sp_res.resize(n)
	e.sp_occ.resize(n)
	e.sp_rng.resize(n)
	for i in n:
		e.sp_rng[i] = seed_of(seed, i)
		e.sp_duty.append([])
		e.sp_duties.append([])
		e.sp_slots.append([])
		e.sp_leg.append([])
		e.sp_cur.append(null)
		e.sp_queue.append([])
		e.sp_result.append(null)
	e.st_vprev = []
	for r in reactions:
		e.st_vprev.append(e.truth(r["on"]["value"]) if r["on"].has("value") else null)
	place_all(e, e.clock(), -1)


# ---------------------------------------------------------------- duties and slots (§16.4, §16.5)

func duty_on_day(pi: int, day: int) -> Array:
	var pp: Dictionary = people[pi]
	var ro: Dictionary = rosters[pp["roster"]]
	var h = null
	if ro["kind"] == "rotation":
		var cyc: Array = ro["cycle"]
		var code: String = cyc[posmod(day - 1 + int(ro["crews"][pp["crew"]]), cyc.size())]
		h = ro["hours"].get(code)
	elif ro["days"].has(week[posmod(day - 1, 7)]):
		h = ro["hours"]
	if h == null:
		return []
	var s: int = (day * 1440 + hhmm(h[0])) * MINUTE
	var en: int = (day * 1440 + hhmm(h[1])) * MINUTE
	if en <= s:
		en += DAY
	return [s, en]


func _resolve(at_kind: int, at_min: int, duty: Array) -> int:
	if at_kind == 0:
		return duty[0] + at_min * MINUTE
	if at_kind == 1:
		return duty[1] + at_min * MINUTE
	var t: int = (duty[0] / DAY) * DAY + at_min * MINUTE
	return t if t >= duty[0] else t + DAY


static func _slot_less(a: Array, b: Array) -> bool:
	for k in 4:
		if a[k] != b[k]:
			return a[k] < b[k]
	return false


func plan(e, pi: int, upto: int) -> void:
	var slots: Array = e.sp_slots[pi]
	var r: Dictionary = routine_of(pi)
	for day in range(e.sp_planned[pi] + 1, upto + 1):
		var du := duty_on_day(pi, day)
		if du.is_empty():
			continue
		e.sp_duties[pi].append(du)
		var mine := []
		for k in r["slots"].size():
			var s: Array = r["slots"][k]
			var t := _resolve(s[0], s[1], du)
			if s[2] == -1:
				mine.append([t, du[0], k, 0, s[5], du])
			else:
				var u := _resolve(s[3], s[4], du)
				var rep := 0
				while t <= u:
					mine.append([t, du[0], k, rep, s[5], du])
					t += s[2] * MINUTE
					rep += 1
		slots.append_array(mine)
	slots.sort_custom(_slot_less)
	e.sp_planned[pi] = upto


# ---------------------------------------------------------------- placement (§17.2)

func place_all(e, c: int, old: int) -> void:
	var day: int = c / DAY
	e.st_holder = {}
	e.st_given = {}
	for pi in people.size():
		e.sp_duties[pi] = []
		e.sp_slots[pi] = []
		e.sp_planned[pi] = day - 3
		e.sp_cur[pi] = null
		e.sp_queue[pi] = []
		e.sp_leg[pi] = []
		e.sp_res[pi] = -1
		e.sp_occ[pi] = -1
		e.sp_result[pi] = null
		e.sp_pos[pi] = -1
		e.sp_on[pi] = 0
		e.sp_duty[pi] = []
		if e._absent.has(pi):
			continue
		plan(e, pi, day + 1)
		for du in e.sp_duties[pi]:
			if du[0] <= c and c < du[1]:
				e.sp_on[pi] = 1
				e.sp_duty[pi] = du
		var keep := []
		for du in e.sp_duties[pi]:
			if du[1] > c and du != e.sp_duty[pi]:
				keep.append(du)
		e.sp_duties[pi] = keep
		var pick = null
		var duty: Array = e.sp_duty[pi]
		for s in e.sp_slots[pi]:
			if s[0] <= c and not duty.is_empty() and s[5] == duty and s[0] >= duty[0]:
				pick = s
		if old != -1:
			for s in e.sp_slots[pi]:
				if old < s[0] and s[0] < c:
					e._ev(["task", people[pi]["id"], s[4], "skipped"])
		var rest := []
		for s in e.sp_slots[pi]:
			if s[0] > c:
				rest.append(s)
		e.sp_slots[pi] = rest
		if not e.sp_on[pi]:
			continue
		var task = pick[4] if pick != null else null
		var place := first_place(e, task) if task != null else -1
		if place == -1:
			place = first_place(e, idle_of(pi))
		if place == -1:
			place = origin
		e.sp_pos[pi] = place
		if not open[place] and not e.st_holder.has(place):
			e.st_holder[place] = pi
			e.sp_occ[pi] = place
		if task != null:
			give(e, pi, task, prio_of(task), null, null, null, null, false)
	if e.st_trainee != -1:
		e.st_t_at = e.sp_pos[e.st_trainee]


func first_place(e, tid: String) -> int:
	for s in tasks[tid]["steps"]:
		if s.has("go"):
			var x = s["go"]
			if typeof(x) == TYPE_STRING:
				return pix[x]
			if x.has("kks"):
				if x["kks"] == "$":
					continue
				return work_at[x["kks"]]
			return free_of(e, x["kind"], x["room"], -1)
		if s.has("meet"):
			return meet_place(e, s["meet"]["room"], -1)
	return -1


## The first place of a kind in a room that is free (or held by `who`), -1 when none is.
func free_of(e, k: String, room: String, who: int) -> int:
	for i in rooms.get(room, PackedInt32Array()):
		if kind[i] == k:
			if open[i] or e.st_holder.get(i, who) == who:
				return i
	return -1


## A meeting's place: the room's first seat, desk or table not held by another than `who`, else its door.
func meet_place(e, room: String, who: int) -> int:
	for i in rooms.get(room, PackedInt32Array()):
		if (kind[i] == "seat" or kind[i] == "desk" or kind[i] == "table") and e.st_holder.get(i, who) == who:
			return i
	return door.get(room, -1)


# ---------------------------------------------------------------- giving tasks (§17.3)

static func _inst_less(a: Dictionary, b: Dictionary) -> bool:
	if a["prio"] != b["prio"]:
		return a["prio"] < b["prio"]
	if a["made"] != b["made"]:
		return a["made"] < b["made"]
	return a["order"] < b["order"]


static func _enqueue(e, pi: int, inst: Dictionary) -> void:
	var q: Array = e.sp_queue[pi]
	var at := q.size()
	for k in q.size():
		if _inst_less(inst, q[k]):
			at = k
			break
	q.insert(at, inst)


func give(e, pi: int, tid: String, prio: int, made_by, work, code, alarm, count := true) -> bool:
	var c = e.sp_cur[pi]
	if e.sp_queue[pi].size() + (1 if c != null and not c["idle"] else 0) >= QUEUE_MAX:
		e._ev(["task", null, tid, "unassigned"])
		return false
	var t: Dictionary = tasks[tid]
	if work == null and t.get("work") != null:
		work = t["work"]
	var inst := {"task": tid, "prio": prio, "made": e.step_no, "order": e.st_order, "step": 0, "st": {},
			"work": work, "code": code, "alarm": alarm, "src": made_by, "idle": false, "started": false,
			"int": t.get("interruptible", true)}
	e.st_order += 1
	_enqueue(e, pi, inst)
	if made_by != null:
		e.st_given[made_by] = e.st_given.get(made_by, 0) + 1
	if count and pi == e.st_trainee:
		e.st_unacked += 1
	return true


func assign(e, role_list: Array, tid: String, prio: int, made_by, work, code, alarm) -> void:
	var cands := []
	for r in role_list:
		for pi in people.size():
			if people[pi]["role"] == r and e.sp_on[pi] and not e._absent.has(pi):
				cands.append(pi)
	if cands.is_empty():
		e._ev(["task", null, tid, "unassigned"])
		return
	for pi in cands:
		var c = e.sp_cur[pi]
		if c == null or c["idle"] or (c["prio"] > prio and c["int"]):
			give(e, pi, tid, prio, made_by, work, code, alarm)
			return
	give(e, cands[0], tid, prio, made_by, work, code, alarm)


func release(e, inst: Dictionary) -> void:
	var src = inst["src"]
	if src != null:
		e.st_given[src] -= 1
		if e.st_given[src] == 0:
			e.st_given.erase(src)


# ---------------------------------------------------------------- step 1: the trainee's inputs (§17.6)

func t_input(e, item: Array) -> void:
	var k: String = item[0]
	if k == "role":
		var pid = item[1]
		var ok: bool = e.step_no == 1 and not e._fixed_trainee and e.st_trainee == -1 \
				and typeof(pid) == TYPE_STRING and person_ix.has(pid) and not e._absent.has(person_ix[pid]) \
				and roles[people[person_ix[pid]]["role"]]["play"]
		e._ev(["role", pid, "done" if ok else "refused"])
		if ok:
			e.st_trainee = person_ix[pid]
			e.st_t_at = e.sp_pos[e.st_trainee]
		return
	if k == "task_ack":
		e.st_unacked = 0
		e._ev(["task_ack"])
		return
	if k == "jump":
		jump(e, item[1])
		return
	e.st_t_in.append(item)


static func is_hhmm(x) -> bool:
	if typeof(x) != TYPE_STRING or x.length() != 5 or x[2] != ":":
		return false
	for i in [0, 1, 3, 4]:
		if not "0123456789".contains(x[i]):
			return false
	return x.substr(0, 2).to_int() <= 23 and x.substr(3, 2).to_int() <= 59


func jump(e, to) -> void:
	var old: int = e.clock()
	if not is_hhmm(to):
		e._ev(["jump", old, null, "refused"])
		return
	var t: int = (old / DAY) * DAY + hhmm(to) * MINUTE
	while t <= old:
		t += DAY
	var ok: bool = e.st_trainee == -1 or e.st_unacked == 0
	if ok and not e.ff_model():
		ok = false
	if ok:
		for s in e.pstate:
			if s >= 1 and s <= 7:
				ok = false
				break
	if ok and not e.st_jumped.is_empty():
		ok = false
	if ok:
		e.J += t - old
		e.st_jumped = [old, t]
	e._ev(["jump", old, t, "done" if ok else "refused"])


# ---------------------------------------------------------------- step 9 (§17.2)

func step(e) -> void:
	var n: int = e.step_no
	var c: int = e.clock()
	var tin: Array = e.st_t_in
	e.st_t_in = []
	var jump_step := false
	if not e.st_jumped.is_empty():
		var old: int = e.st_jumped[0]
		var nw: int = e.st_jumped[1]
		e.st_jumped = []
		for pi in people.size():
			var all := []
			if e.sp_cur[pi] != null:
				all.append(e.sp_cur[pi])
			all.append_array(e.sp_queue[pi])
			for inst in all:
				e._ev(["task", people[pi]["id"], inst["task"], "skipped"])
		place_all(e, nw, old)
		jump_step = true
	var tr: int = e.st_trainee
	if tr != -1:
		for item in tin:
			if item[0] == "arrive" and typeof(item[1]) == TYPE_STRING and pix.has(item[1]):
				e.st_t_at = pix[item[1]]
				e.sp_pos[tr] = e.st_t_at
			elif item[0] == "leave" and typeof(item[1]) == TYPE_STRING and pix.get(item[1], -2) == e.st_t_at:
				e.st_t_at = -1
				e.sp_pos[tr] = -1
	# 1. duties, then slots
	var day: int = c / DAY
	var np := people.size()
	for pi in np:
		if e._absent.has(pi):
			continue
		if e.sp_planned[pi] < day + 1:
			plan(e, pi, day + 1)
		if e.sp_on[pi] and c >= e.sp_duty[pi][1]:
			e.sp_on[pi] = 0
			e.sp_duty[pi] = []
			e._ev(["duty", people[pi]["id"], "off"])
		if not e.sp_on[pi]:
			var dl: Array = e.sp_duties[pi]
			while not dl.is_empty() and dl[0][1] <= c:
				dl.pop_front()
			if not dl.is_empty() and dl[0][0] <= c:
				e.sp_on[pi] = 1
				e.sp_duty[pi] = dl.pop_front()
				e._ev(["duty", people[pi]["id"], "on"])
	for pi in np:
		if e._absent.has(pi):
			continue
		var sl: Array = e.sp_slots[pi]
		while not sl.is_empty() and sl[0][0] <= c:
			var s: Array = sl.pop_front()
			give(e, pi, s[4], prio_of(s[4]), null, null, null, null)
	# 2. reactions
	react(e, n)
	# 4. people
	if not jump_step:
		for pi in np:
			if e._absent.has(pi):
				continue
			if pi == e.st_trainee:
				trainee_turn(e, pi, tin)
			else:
				turn(e, pi)
	for i in reactions.size():
		var on: Dictionary = reactions[i]["on"]
		if on.has("value"):
			e.st_vprev[i] = e.truth(on["value"])


func react(e, n: int) -> void:
	if reactions.is_empty():
		return
	var evs := []
	for k in range(e.ev_mark, e.events.size()):
		if e.events[k][0] == n:
			evs.append(e.events[k])
	for ri in reactions.size():
		var r: Dictionary = reactions[ri]
		var on: Dictionary = r["on"]
		var k: String = on.keys()[0]
		var v = on[k]
		var prio: int = int(r.get("priority", prio_of(r["task"])))
		var hits := []          # [source key, work, code, alarm]
		if k == "value":
			var now: bool = e.truth(v)
			if now and typeof(e.st_vprev[ri]) == TYPE_BOOL and not e.st_vprev[ri]:
				hits.append(["value|" + v, null, null, null])
		else:
			for x in evs:
				if k == "alarm" and x[1] == "alarm" and x[3] == "active_unack":
					var a: Dictionary = e.m.alarms[e._al_ix[x[2]]]
					if a["priority"] <= v:
						hits.append(["alarm|" + x[2], null, a["where"], x[2]])
				elif k == "trip" and x[1] == "trip" and (v == "*" or v == x[2]):
					hits.append(["trip|" + x[2], null, null, null])
				elif k == "fault" and x[1] == "fault" and x[2] == v:
					hits.append(["fault|" + v, null, e.fault_code(v), null])
				elif k == "permit" and x[1] == "permit" and x[5] == "done":
					var nw: int = x[6][0] if x[3] == "auto" else PERMIT_TO[x[3]]
					if STATE_NAMES[nw] == v and (not r.has("work") or r["work"] == x[2]):
						hits.append(["permit|" + x[2], x[2], e.m.works[e.m.work_ix[x[2]]]["kks"], null])
		for h in hits:
			var key: String = str(ri) + "|" + h[0]
			if e.st_given.has(key):
				continue
			var w = r.get("work", h[1])
			var code = h[2]
			if code == null and w != null:
				code = e.m.works[e.m.work_ix[w]]["kks"]
			assign(e, r["roles"], r["task"], prio, key, w, code, h[3])


# ---------------------------------------------------------------- a person's turn (phase 4)

func select(e, pi: int):
	var cur = e.sp_cur[pi]
	var q: Array = e.sp_queue[pi]
	var pid: String = people[pi]["id"]
	if cur != null and cur["idle"] and (not q.is_empty() or not e.sp_on[pi]):
		e._ev(["task", pid, cur["task"], "done"])
		e.sp_cur[pi] = null
		cur = null
	if cur != null and not q.is_empty() and cur["int"] and q[0]["prio"] < cur["prio"] \
			and not cur["st"].get("busy", false):
		pause(e, pi)
		cur = null
	if cur == null and not q.is_empty():
		cur = q.pop_front()
		e.sp_cur[pi] = cur
		if not cur["started"]:
			cur["started"] = true
			e._ev(["task", pid, cur["task"], "start"])
		if e.sp_pos[pi] == -1 and pi != e.st_trainee:
			e.sp_pos[pi] = gate
			e._ev(["move", pid, null, places[gate]["id"], e.step_no])
	if cur == null and e.sp_on[pi]:
		var idle := idle_of(pi)
		cur = {"task": idle, "prio": 6, "made": e.step_no, "order": e.st_order, "step": 0, "st": {}, "work": null,
				"code": null, "alarm": null, "src": null, "idle": true, "started": true, "int": true}
		e.sp_cur[pi] = cur
		e.st_order += 1
		e._ev(["task", pid, idle, "start"])
		if e.sp_pos[pi] == -1 and pi != e.st_trainee:
			e.sp_pos[pi] = gate
			e._ev(["move", pid, null, places[gate]["id"], e.step_no])
	if cur == null and not e.sp_on[pi] and e.sp_pos[pi] != -1 and pi != e.st_trainee:
		leave_place(e, pi)
		e._ev(["move", pid, places[e.sp_pos[pi]]["id"], null, e.step_no])
		e.sp_pos[pi] = -1
	return cur


func pause(e, pi: int) -> void:
	var cur: Dictionary = e.sp_cur[pi]
	var st: Dictionary = cur["st"]
	for k in ["dest", "waiting", "wait_since", "target", "meet_since"]:
		st.erase(k)
	unreserve(e, pi)
	_enqueue(e, pi, cur)
	e.sp_cur[pi] = null


func finish(e, pi: int, how: String) -> void:
	var cur: Dictionary = e.sp_cur[pi]
	e._ev(["task", people[pi]["id"], cur["task"], how])
	release(e, cur)
	unreserve(e, pi)
	e.sp_cur[pi] = null


func unreserve(e, pi: int) -> void:
	var r: int = e.sp_res[pi]
	if r != -1:
		if e.st_holder.get(r, -1) == pi:
			e.st_holder.erase(r)
		e.sp_res[pi] = -1


func leave_place(e, pi: int) -> void:
	var o: int = e.sp_occ[pi]
	if o != -1:
		if e.st_holder.get(o, -1) == pi:
			e.st_holder.erase(o)
		e.sp_occ[pi] = -1


func turn(e, pi: int) -> void:
	var n: int = e.step_no
	var leg: Array = e.sp_leg[pi]
	if not leg.is_empty():
		if leg[3] > n:
			return
		e.sp_pos[pi] = leg[1]
		e.sp_leg[pi] = []
		if e.sp_pos[pi] == e.sp_res[pi]:
			e.sp_occ[pi] = e.sp_pos[pi]
			e.sp_res[pi] = -1
	for _k in 64:
		var cur = select(e, pi)
		if cur == null:
			return
		var r = run(e, pi, cur)
		if typeof(r) == TYPE_STRING and r == "wait":
			return
		advance(e, pi, r)


func advance(e, pi: int, r) -> void:
	var cur: Dictionary = e.sp_cur[pi]
	var steps: Array = tasks[cur["task"]]["steps"]
	var nxt: int
	if typeof(r) == TYPE_ARRAY:         # ["task", id]: choose
		e._ev(["task", people[pi]["id"], cur["task"], "done"])
		release(e, cur)
		cur["task"] = r[1]
		cur["src"] = null
		cur["step"] = 0
		cur["st"] = {}
		unreserve(e, pi)
		e._ev(["task", people[pi]["id"], r[1], "start"])
		return
	if r == "next":
		nxt = cur["step"] + 1
	else:
		var s: Dictionary = steps[cur["step"]]
		var el = s.get("else", s["wait"].get("else") if s.has("wait") else null)
		if el == null:
			finish(e, pi, "abandoned")
			return
		nxt = el
	unreserve(e, pi)
	if nxt >= steps.size():
		finish(e, pi, "done")
		return
	cur["step"] = nxt
	cur["st"] = {}


## A go's target: [place, taken], [-1, false] when there is none.
func resolve(e, pi: int, cur: Dictionary, x) -> Array:
	var i: int
	if typeof(x) == TYPE_STRING:
		i = pix[x]
	elif x.has("kks"):
		var code = cur["code"] if x["kks"] == "$" else x["kks"]
		i = work_at.get(code, -1) if code != null else -1
		if i == -1:
			return [-1, false]
	else:
		i = free_of(e, x["kind"], x["room"], pi)
		if i == -1:
			for j in rooms[x["room"]]:
				if kind[j] == x["kind"]:
					return [j, true]
		return [i, false]
	return [i, not open[i] and e.st_holder.get(i, pi) != pi]


## The next place on the route from a to b (§16.2), -1 at b.
func hop(a: int, b: int) -> int:
	if a == b:
		return -1
	if point_no[a] == -1:
		return stub[a]
	var pb := b if point_no[b] != -1 else stub[b]
	if a == pb:
		return b
	return points[next[point_no[a]][point_no[pb]]]


func walk(e, pi: int, dest: int) -> bool:
	var pos: int = e.sp_pos[pi]
	if pos == dest:
		return true
	var nx := hop(pos, dest)
	var st: int = ways[mini(pos, nx) * places.size() + maxi(pos, nx)]
	leave_place(e, pi)
	e.sp_leg[pi] = [pos, nx, e.step_no, e.step_no + st]
	e._ev(["move", people[pi]["id"], places[pos]["id"], places[nx]["id"], e.step_no + st])
	e.sp_pos[pi] = -1
	return false


func before(a: int, b: int) -> int:
	var x := a
	while true:
		var nx := hop(x, b)
		if nx == b or nx == -1:
			return x
		x = nx
	return x


func taken(e, i: int, pi: int) -> bool:
	return not open[i] and e.st_holder.get(i, pi) != pi


func reserve(e, pi: int, i: int) -> void:
	if open[i] or e.sp_occ[pi] == i:
		return
	unreserve(e, pi)
	e.sp_res[pi] = i
	e.st_holder[i] = pi


func go(e, pi: int, cur: Dictionary, x) -> String:
	var s: Dictionary = cur["st"]
	if not s.has("dest"):
		var i: int
		var tk: bool
		if typeof(x) == TYPE_INT:
			i = x
			tk = taken(e, x, pi)
		else:
			var rt := resolve(e, pi, cur, x)
			i = rt[0]
			tk = rt[1]
		if i == -1:
			return "fail"
		s["target"] = i
		if tk:
			var room = room_of[i]
			var w: int = door.get(room, -1) if room != null else -1
			if w == -1 or w == i:
				w = before(e.sp_pos[pi], i)
			s["dest"] = w
			s["waiting"] = true
		else:
			s["dest"] = i
			reserve(e, pi, i)
	if s.get("waiting", false) and e.sp_pos[pi] == s["dest"]:
		if not s.has("wait_since"):
			s["wait_since"] = e.step_no     # the 15 minutes count from the arrival where they wait
		var i: int = s["target"]
		if typeof(x) == TYPE_DICTIONARY and x.has("kind"):
			var j := free_of(e, x["kind"], x["room"], pi)
			if j != -1:
				i = j
				s["target"] = j
		if not taken(e, i, pi):
			s["dest"] = i
			s["waiting"] = false
			reserve(e, pi, i)
		elif e.step_no - s["wait_since"] >= WAIT_PLACE * tpm:
			return "fail"
		else:
			return "wait"
	if walk(e, pi, s["dest"]):
		return "wait" if s.get("waiting", false) else "next"
	return "wait"


func mins(e, pi: int, x) -> int:
	if typeof(x) == TYPE_ARRAY:
		var r := draw(e, pi)
		return int(x[0]) + ((r * (int(x[1]) - int(x[0]) + 1)) >> 24)
	return int(x)


func run(e, pi: int, cur: Dictionary):
	var n: int = e.step_no
	var s: Dictionary = tasks[cur["task"]]["steps"][cur["step"]]
	var x: Dictionary = cur["st"]
	var pid: String = people[pi]["id"]
	if s.has("go"):
		return go(e, pi, cur, s["go"])
	if s.has("work"):
		if not x.has("left"):
			x["left"] = mins(e, pi, s["work"]) * tpm
			x["last"] = n
		elif x["last"] < n:
			x["left"] -= 1
			x["last"] = n
		return "next" if x["left"] <= 0 else "wait"
	if s.has("read"):
		var code: String = s["read"]
		var val: float = e.shown(code, e.prev)
		var ex = s.get("expect")
		var ok: bool = ex == null or (ex[0] <= val and val <= ex[1])
		e._ev(["read", pid, code, val, "ok" if ok else "out_of_range"])
		return "next"
	if s.has("meet"):
		return meet(e, pi, cur, s["meet"], false)
	if s.has("say"):
		say(e, pi, s["say"], s["to"])
		return "next"
	if s.has("wait"):
		return wait(e, cur, s["wait"])
	if s.has("call"):
		var c: Dictionary = s["call"]
		var w = c.get("work", "$")
		w = cur["work"] if w == "$" else w
		e._ev(["call", pid, c["role"], c["task"], w, "done"])
		assign(e, [c["role"]], c["task"], prio_of(c["task"]), null, w, cur["code"], cur["alarm"])
		return "next"
	if s.has("choose"):
		var tot := 0
		for ch in s["choose"]:
			tot += int(ch[0])
		var r := draw(e, pi)
		var y := (r * tot) >> 24
		var acc := 0
		for ch in s["choose"]:
			acc += int(ch[0])
			if acc > y:
				return ["task", ch[1]]
	if s.has("ack"):
		var a = cur["alarm"]
		if a != null:
			var st: String = e.astate[e._al_ix[a]]
			if st == "active_unack" or st == "cleared_unack":
				e.npc_queue.append(["ack", a])
		return "next"
	if s.has("op") or s.has("permit"):
		if not x.get("busy", false):
			if s.has("op"):
				var o: Dictionary = s["op"]
				e.npc_queue.append(["op", o["kks"], o["do"], o.get("value"), o.get("trip"), o["where"], pid])
			else:
				var w = cur["work"] if s["permit"]["work"] == "$" else s["permit"]["work"]
				e.npc_queue.append(["permit", w, s["permit"]["action"], pid])
			x["busy"] = true
			e.sp_result[pi] = null
			return "wait"
		if e.sp_result[pi] == null:
			return "wait"
		var r = e.sp_result[pi]
		e.sp_result[pi] = null
		x["busy"] = false
		return "next" if r == "done" else "fail"
	if s.has("lock") or s.has("unlock"):
		var k := "lock" if s.has("lock") else "unlock"
		var w = cur["work"] if s[k]["work"] == "$" else s[k]["work"]
		var wi: int = e.m.work_ix.get(w, -1) if w != null else -1
		if wi == -1 or not e.m.works[wi].has("isolation"):
			return "fail"
		var iso: Dictionary = e.m.isolations[e.m.isolation_ix[e.m.works[wi]["isolation"]]]
		var pts := []
		if typeof(s[k]["point"]) == TYPE_STRING:
			pts = range(iso["points"].size())
		else:
			pts = [int(s[k]["point"])]
		var i: int = x.get("i", 0)
		if i >= pts.size():
			return "next"
		if not x.get("busy", false):
			var wp: int = work_at.get(iso["points"][pts[i]]["kks"], -1)
			if wp != -1:
				var r := go(e, pi, cur, wp)
				if r != "next":
					return r
			x.erase("dest")
			e.npc_queue.append([k, w, pts[i], pid])
			x["busy"] = true
			e.sp_result[pi] = null
			return "wait"
		if e.sp_result[pi] == null:
			return "wait"
		var res = e.sp_result[pi]
		e.sp_result[pi] = null
		x["busy"] = false
		if res != "done":
			return "fail"
		x["i"] = i + 1
		return "next" if i + 1 >= pts.size() else run(e, pi, cur)
	push_error("staff: no step kind in " + str(s))
	return "next"


func say(e, pi: int, msg: String, to: String) -> void:
	e._ev(["say", people[pi]["id"], msg, to])
	var t: int = e.st_trainee
	if t != -1 and t != pi and (to == people[t]["id"] or to == people[t]["role"]):
		e.st_unacked += 1


func wait(e, cur: Dictionary, w: Dictionary) -> String:
	var x: Dictionary = cur["st"]
	if not x.has("from"):
		x["from"] = e.step_no
	var ok: bool
	var gone := false
	if w.has("until"):
		ok = e.truth(w["until"])
	else:
		var wid = cur["work"] if w["permit"][0] == "$" else w["permit"][0]
		var sv: int = e.pstate[e.m.work_ix[wid]] if wid != null and e.m.work_ix.has(wid) else 0
		var want := STATE_NAMES.find(w["permit"][1])
		gone = sv == 10
		ok = not gone and want <= sv and sv <= 9
	if ok:
		return "next"
	if gone or (w.has("minutes") and e.step_no - x["from"] >= int(w["minutes"]) * tpm):
		return "fail"
	return "wait"


func meet(e, pi: int, cur: Dictionary, mt: Dictionary, trainee: bool) -> String:
	var x: Dictionary = cur["st"]
	if not x.has("place"):
		x["place"] = meet_place(e, mt["room"], pi)
	if not trainee:
		var r := go(e, pi, cur, int(x["place"]))
		if r != "next":
			return r
		x.erase("dest")
	elif e.st_t_at != x["place"]:
		return "wait"
	if not x.has("meet_since") and not x.get("met", false):
		x["meet_since"] = e.step_no
	if not x.get("met", false):
		var rm: PackedInt32Array = rooms[mt["room"]]
		var all := true
		for r in mt["with"]:
			var found := false
			for qi in people.size():
				if qi != pi and e.sp_on[qi] and people[qi]["role"] == r and e.sp_pos[qi] != -1 \
						and rm.has(e.sp_pos[qi]):
					found = true
					break
			if not found:
				all = false
				break
		if all or e.step_no - x["meet_since"] >= WAIT_PLACE * tpm:
			x["met"] = true
			x["left"] = int(mt["minutes"]) * tpm
			x["last"] = e.step_no
		else:
			return "wait"
	elif x["last"] < e.step_no:
		if not trainee or e.st_t_at == x["place"]:
			x["left"] -= 1
		x["last"] = e.step_no
	return "next" if x["left"] <= 0 else "wait"


# ---------------------------------------------------------------- the trainee's person (§17.4)

func trainee_turn(e, pi: int, tin: Array) -> void:
	var used := []
	used.resize(tin.size())
	used.fill(false)
	var mine := []
	for k in range(e.ev_mark, e.events.size()):
		if e.events[k][0] == e.step_no:
			mine.append(e.events[k])
	trainee_steps(e, pi, tin, used, mine)
	for k in tin.size():
		if used[k]:
			continue
		var item: Array = tin[k]
		if item[0] == "say" and typeof(item[1]) == TYPE_STRING and messages.has(item[1]) \
				and typeof(item[2]) == TYPE_STRING \
				and (item[2] == "channel" or roles.has(item[2]) or person_ix.has(item[2])):
			say(e, pi, item[1], item[2])
		elif item[0] == "call":
			var ok: bool = typeof(item[1]) == TYPE_STRING and typeof(item[2]) == TYPE_STRING \
					and callable.has(item[1] + "\n" + item[2]) \
					and (item[3] == null or (typeof(item[3]) == TYPE_STRING and e.m.work_ix.has(item[3])))
			e._ev(["call", people[pi]["id"], item[1], item[2], item[3], "done" if ok else "refused"])
			if ok:
				var code = e.m.works[e.m.work_ix[item[3]]]["kks"] if item[3] != null else null
				assign(e, [item[1]], item[2], prio_of(item[2]), null, item[3], code, null)


func trainee_steps(e, pi: int, tin: Array, used: Array, mine: Array) -> void:
	var n: int = e.step_no
	var pid: String = people[pi]["id"]
	for _k in 64:
		var cur = select(e, pi)
		if cur == null:
			return
		var s: Dictionary = tasks[cur["task"]]["steps"][cur["step"]]
		var x: Dictionary = cur["st"]
		var r = "wait"
		if s.has("go"):
			if not x.has("dest"):
				var rt := resolve(e, pi, cur, s["go"])
				if rt[0] == -1:
					r = "fail"
				else:
					x["dest"] = rt[0]
					if not rt[1]:
						reserve(e, pi, rt[0])
			if r != "fail" and e.st_t_at == x["dest"]:
				r = "next"
				if e.sp_res[pi] == e.st_t_at:
					e.sp_occ[pi] = e.sp_res[pi]
					e.sp_res[pi] = -1
		elif s.has("work"):
			if not x.has("left"):
				x["left"] = mins(e, pi, s["work"]) * tpm
				x["last"] = n
				x["place"] = e.st_t_at
			elif x["last"] < n:
				if e.st_t_at == x["place"]:
					x["left"] -= 1
				x["last"] = n
			r = "next" if x["left"] <= 0 else "wait"
		elif s.has("read"):
			for k in tin.size():
				var it: Array = tin[k]
				if not used[k] and it[0] == "read" and it[1] == s["read"] and _is_num(it[2]):
					used[k] = true
					var val: float = e.shown(s["read"], e.prev)
					var ex = s.get("expect")
					var how: String
					if absf(it[2] - val) > float(s.get("tol", 0)):
						how = "misread"
					else:
						how = "ok" if ex == null or (ex[0] <= val and val <= ex[1]) else "out_of_range"
					e._ev(["read", pid, s["read"], it[2], how])
					r = "next"
					break
		elif s.has("meet"):
			r = meet(e, pi, cur, s["meet"], true)
		elif s.has("say"):
			for k in tin.size():
				var it: Array = tin[k]
				if not used[k] and it[0] == "say" and it[1] == s["say"] and it[2] == s["to"]:
					used[k] = true
					say(e, pi, s["say"], s["to"])
					r = "next"
					break
		elif s.has("wait"):
			r = wait(e, cur, s["wait"])
		elif s.has("call"):
			var c: Dictionary = s["call"]
			for k in tin.size():
				var it: Array = tin[k]
				if not used[k] and it[0] == "call" and it[1] == c["role"] and it[2] == c["task"]:
					used[k] = true
					var w = c.get("work", "$")
					w = cur["work"] if w == "$" else w
					e._ev(["call", pid, c["role"], c["task"], w, "done"])
					assign(e, [c["role"]], c["task"], prio_of(c["task"]), null, w, cur["code"], cur["alarm"])
					r = "next"
					break
		elif s.has("choose"):
			for k in tin.size():
				var it: Array = tin[k]
				if not used[k] and it[0] == "pick":
					used[k] = true
					if typeof(it[1]) == TYPE_INT and it[1] >= 0 and it[1] < s["choose"].size():
						r = ["task", s["choose"][it[1]][1]]
						break
		elif s.has("ack"):
			var a = cur["alarm"]
			if a == null:
				r = "next"
			else:
				var st: String = e.astate[e._al_ix[a]]
				if st != "active_unack" and st != "cleared_unack":
					r = "next"
		elif s.has("op"):
			var o: Dictionary = s["op"]
			for y in mine:
				if y[1] == "op" and y[2] == o["kks"] and y[3] == o["do"] and y[4] == "done" and y.size() > 7 \
						and y[7] == pid:
					r = "next"
					break
		elif s.has("permit"):
			var w = cur["work"] if s["permit"]["work"] == "$" else s["permit"]["work"]
			for y in mine:
				if y[1] == "permit" and y[2] == w and y[3] == s["permit"]["action"] and y[4] == pid \
						and y[5] == "done":
					r = "next"
					break
		elif s.has("lock") or s.has("unlock"):
			var k := "lock" if s.has("lock") else "unlock"
			var w = cur["work"] if s[k]["work"] == "$" else s[k]["work"]
			var wi: int = e.m.work_ix.get(w, -1) if w != null else -1
			if wi == -1 or not e.m.works[wi].has("isolation"):
				r = "fail"
			else:
				var npts: int = e.m.isolations[e.m.isolation_ix[e.m.works[wi]["isolation"]]]["points"].size()
				var pts := []
				if typeof(s[k]["point"]) == TYPE_STRING:
					pts = range(npts)
				else:
					pts = [int(s[k]["point"])]
				if not x.has("got"):
					x["got"] = []
				var got: Array = x["got"]
				for y in mine:
					if y[1] == k and y[2] == w and y[4] == pid and y[5] == "done" and pts.has(y[3]) \
							and not got.has(y[3]):
						got.append(y[3])
				if got.size() == pts.size():
					r = "next"
		if typeof(r) == TYPE_STRING and r == "wait":
			return
		advance(e, pi, r)


static func _is_num(x) -> bool:
	var t := typeof(x)
	if t == TYPE_INT:
		return absi(x) < 1000000000
	if t == TYPE_FLOAT:
		return is_finite(x) and absf(x) < 1e9
	return false


# ---------------------------------------------------------------- the snapshot's part (§17.7)

func snap(e) -> Dictionary:
	var out := {}
	for pi in people.size():
		var where = null
		var leg: Array = e.sp_leg[pi]
		if not leg.is_empty():
			where = ["way", places[leg[0]]["id"], places[leg[1]]["id"], leg[2], leg[3]]
		elif e.sp_pos[pi] != -1:
			where = places[e.sp_pos[pi]]["id"]
		var c = e.sp_cur[pi]
		out[people[pi]["id"]] = [where, c["task"] if c != null else null, c["step"] if c != null else null]
	return out
