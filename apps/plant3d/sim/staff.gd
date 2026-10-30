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
const HANDOVER_WAIT := 60         # clock minutes an outgoing person waits at a lock for the incoming one's (§17.9)
const MAX_POINTS := 64 * 16       # every point of a model's isolations: a lock round's bound in a turn
const QUEUE_MAX := 32
const RIDE_WAIT := 1800           # steps a person waits for a lift before they take the stairs (§20.4)
const RIDE_QUIET := 50            # steps since the last board or alight before a rider closes a gate elsewhere
const EARLY_KEPT := 32           # the trainee's actions kept for a later step (§17.8)
const OPEN_KINDS := ["point", "door", "stop", "muster", "counter", "depot", "work"]
const PPE := ["helmet", "boots", "glasses", "gloves", "ear", "harness", "face_shield", "apron", "vest"]
const ACT_KINDS := ["ppe", "permit", "unsafe"]   # an unsafe act's kinds, in the order checked (§16.7, §17.11)
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
var role_people := {}                # role -> its people's indexes, in file order
var post := PackedStringArray()      # per person: their role and routine (§17.9)
var has_left := false                # a reaction on lock_left (§17.9)
var rosters := {}
var routines := {}                   # id -> {"slots": [[at kind, at minutes, every or -1, until kind, until minutes, task]], "idle": task}
var tasks := {}                      # id -> task
var reactions: Array = []
var messages := {}
var callable := {}                   # "caller role\nrole\ntask" -> true: the radio panel's requests (§17.8)
var react_kind := PackedStringArray()  # per reaction: what it is on
var value_reactions := PackedInt32Array()   # the reactions on a value
var act_reactions := PackedInt32Array()     # the reactions on an unsafe act (§16.7)
var finding_reactions := PackedInt32Array() # the reactions on a reading out of its range (§17.12)
var value_slot := PackedInt32Array()        # per reaction on a value (value_reactions' order): its engine slot
var zone_ids: Array = []             # the zones' ids, in file order
var zone_ix := {}                    # zone id -> its index
var zone_ppe := PackedInt32Array()   # per zone: the PPE it needs, a bit per item of PPE
var place_zm := PackedInt64Array()   # per place: its zones, a bit per zone (file order)
var place_kks: Array = []            # per place: the code of a work place, else null
var role_ppe := {}                   # role -> its PPE, a bit per item
var put_right := {}                  # act kind -> the task an HSE stop gives the acting person
var unlocks := {}                    # task -> {work or "$": true} its unlock steps name (§17.11)
var has_lifts := false               # staff.json has lifts (§20.4): rides, stairs and their digest fields
var lifts: Array = []                # [lift id, PackedInt32Array of its landings' places], in staff.json's order
var lift_model: Array = []           # per staff lift: the model's lift entry
var lift_way := {}                   # a * places + b (a < b) of a lift way -> its staff lift
var stairs := {}                     # a * places + b of a lift way's ends, either way round -> the stairs' places


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
	for z in doc.get("zones", []):
		zone_ix[z["id"]] = zone_ids.size()
		zone_ids.append(z["id"])
		zone_ppe.append(ppe_mask(z["ppe"]))
	for p in places:
		var zm := 0
		for z in p.get("zones", []):
			zm |= 1 << int(zone_ix.get(z, 0))
		place_zm.append(zm)
		place_kks.append(p.get("kks") if p["kind"] == "work" else null)
	put_right = doc.get("put_right", {})
	var np := places.size()
	var landing := {}
	for x in doc.get("lifts", []):
		var pts := PackedInt32Array()
		for pid in x["landings"]:
			pts.append(pix[pid])
			landing[pix[pid]] = lifts.size()
		lifts.append([x["lift"], pts])
		for ml in m.lifts:
			if ml["id"] == x["lift"]:
				lift_model.append(ml)
	has_lifts = not lifts.is_empty()
	var walking: Array = []             # the walking ways between points (the stairs' network): per point [[point, steps]]
	for _k in points.size():
		walking.append([])
	for w in doc["ways"]:
		if not pix.has(w[0]) or not pix.has(w[1]) or not speeds.has(w[3]):
			_fail("a way joins no places: " + str(w))
			return
		var a: int = pix[w[0]]
		var b: int = pix[w[1]]
		var st := maxi(1, int(ceil(float(w[2]) * 10.0 / float(speeds[w[3]]) - 1e-9)))
		ways[mini(a, b) * np + maxi(a, b)] = st
		if w[3] == "lift":
			lift_way[mini(a, b) * np + maxi(a, b)] = landing[a]
		elif point_no[a] != -1 and point_no[b] != -1:
			walking[point_no[a]].append([point_no[b], st])
			walking[point_no[b]].append([point_no[a], st])
		if point_no[a] == -1:
			stub[a] = b
		elif point_no[b] == -1:
			stub[b] = a
	for row in doc["next"]:
		next.append(PackedInt32Array(row))
	for key in lift_way:            # the stairs beside each lift way, from each end to the other (§20.4)
		var ends := [key / np, key % np]
		for k in 2:
			var u: int = ends[k]
			var v: int = ends[1 - k]
			var r := route(walking, point_no[u], point_no[v])
			if r.is_empty():
				_fail("no stairs beside the lift way %s–%s" % [places[u]["id"], places[v]["id"]])
				return
			var pl := PackedInt32Array()
			for x in r:
				pl.append(points[x])
			stairs[u * np + v] = pl
	origin = pix.get(doc["origin"], -1)
	gate = pix.get(doc["gate"], -1)
	for r in doc["roles"]:
		roles[r["id"]] = r
		role_ppe[r["id"]] = ppe_mask(r.get("ppe", []))
		var a := {}
		for x in r["authority"]:
			a[x] = true
		auth[r["id"]] = a
	for r in doc["rosters"]:
		rosters[r["id"]] = r
	people = doc["people"]
	for i in people.size():
		person_ix[people[i]["id"]] = i
		var rp: PackedInt32Array = role_people.get(people[i]["role"], PackedInt32Array())
		rp.append(i)
		role_people[people[i]["role"]] = rp
	for t in doc["tasks"]:
		tasks[t["id"]] = t
	for i in people.size():
		var p: Dictionary = people[i]
		post.append(str(p["role"]) + "\n" + str(p.get("routine", roles[p["role"]]["routine"])))
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
			slots.append([at[0], at[1], every, until[0], until[1], s["task"], s.get("days")])
		routines[r["id"]] = {"slots": slots, "idle": r["idle"]}
	reactions = doc.get("reactions", [])
	for i in reactions.size():
		react_kind.append(reactions[i]["on"].keys()[0])
		if react_kind[i] == "value":
			value_reactions.append(i)
		elif react_kind[i] == "unsafe":
			act_reactions.append(i)
		elif react_kind[i] == "finding":
			finding_reactions.append(i)
		elif react_kind[i] == "lock_left":
			has_left = true
	messages = doc["messages"]
	for r in doc["roles"]:
		for x in r.get("requests", []):
			for s in tasks[x]["steps"]:
				if s.has("call"):
					callable[r["id"] + "\n" + s["call"]["role"] + "\n" + s["call"]["task"]] = true
	for t in tasks.values():
		for s in t["steps"]:
			if s.has("go") and typeof(s["go"]) == TYPE_STRING and not pix.has(s["go"]):
				_fail("task %s: no place %s" % [t["id"], s["go"]])
			if s.has("unlock"):
				if not unlocks.has(t["id"]):
					unlocks[t["id"]] = {}
				unlocks[t["id"]][s["unlock"]["work"]] = true


## The points of the quickest route from src to dst by §16.2's rule (the `next` table's: by steps, then the lowest
## list of point numbers), over adj (per point [[point, steps]]); empty when there is none.
static func route(adj: Array, src: int, dst: int) -> PackedInt32Array:
	var n := adj.size()
	var cost := PackedInt64Array()
	cost.resize(n)
	var path: Array = []
	path.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	path[src] = PackedInt32Array([src])
	while true:
		var u := -1
		for i in n:
			if not done[i] and path[i] != null and (u == -1 or cost[i] < cost[u]
					or (cost[i] == cost[u] and _path_less(path[i], path[u]))):
				u = i
		if u == -1:
			return PackedInt32Array()
		done[u] = 1
		if u == dst:
			return path[u]
		for x in adj[u]:
			var v: int = x[0]
			if done[v]:
				continue
			var c: int = cost[u] + x[1]
			var cand: PackedInt32Array = path[u].duplicate()
			cand.append(v)
			if path[v] == null or c < cost[v] or (c == cost[v] and _path_less(cand, path[v])):
				cost[v] = c
				path[v] = cand
	return PackedInt32Array()


static func _path_less(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()


static func ppe_mask(items: Array) -> int:
	var m := 0
	for x in items:
		var k := PPE.find(x)
		if k >= 0:
			m |= 1 << k
	return m


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
	_slots(e)               # (filled here, on the engine's own thread, never during a step: clones share them)
	var x: Dictionary = scen["staff"]
	var seed: int = x["seed"]
	e._absent = {}
	for a in x.get("absent", []):
		e._absent[person_ix[a]] = true
	# the players (§17.13): the scenario's trainee is slot 0's (a session run's host's); a session's other slots and a
	# single-player run without one play nobody at the start
	e.st_players.fill(-1)
	if x.get("trainee") != null:
		e.st_players[0] = person_ix[x["trainee"]]
	e._fixed_trainee = e.st_players[0] != -1
	var n := people.size()
	e.sp_on.resize(n)
	e.sp_planned.resize(n)
	e.sp_pos.resize(n)
	e.sp_res.resize(n)
	e.sp_occ.resize(n)
	e.sp_rng.resize(n)
	e.sp_wake.resize(n)
	e.sp_worn.resize(n)
	e.sp_zin.resize(n)
	e.sp_lin.resize(n)
	for i in n:
		e.sp_rng[i] = seed_of(seed, i)
		e.sp_acts.append([null, null, null])
		e.sp_duty.append([])
		e.sp_duties.append([])
		e.sp_slots.append([])
		e.sp_leg.append([])
		e.sp_cur.append(null)
		e.sp_queue.append([])
		e.sp_result.append(null)
		e.sp_held.append([])
		e.sp_ride.append([])
		e.sp_stairs.append(PackedInt32Array())
	e.st_vprev = []
	for r in reactions:
		e.st_vprev.append(e.truth(r["on"]["value"]) if r["on"].has("value") else null)
	place_all(e, e.clock(), -1)


# ---------------------------------------------------------------- duties and slots (§16.4, §16.5)

## The weekday of a clock time (tenths of a second from day 0's midnight; day 1 is the week's first), by floor
## division as the reference's: a duty planned on day −1 starts at a negative time (truncating gave day 0's weekday).
func weekday(t: int) -> String:
	return week[posmod(floori(float(t) / DAY) - 1, 7)]


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
	var t: int = duty[0] - posmod(duty[0], DAY) + at_min * MINUTE      # floor division, as the reference
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
		var wd: String = weekday(du[0])
		for k in r["slots"].size():
			var s: Array = r["slots"][k]
			if s[6] != null and not s[6].has(wd):
				continue                # a slot of other weekdays (§17.11)
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
	if e._touched.size() == people.size():
		e._touched.fill(1)         # everyone's acts looked at again in this step's phase 5
	for k in e.riders.size():       # the NPCs aboard leave the ride: their alights for the next step (§20.3)
		for r in e.riders[k]:
			if typeof(r) == TYPE_STRING and e.slot_of(person_ix[r]) == -1:
				queue_alight(e, e.m.lifts[k]["id"], r)
	e.st_holder = {}
	e.st_given = {}
	e.st_pending = []
	e.st_made = {}
	e.st_next1 = 0
	for pi in people.size():
		e.sp_worn[pi] = 0
		e.sp_zin[pi] = 0
		e.sp_acts[pi] = [null, null, null]
		e.sp_duties[pi] = []
		e.sp_slots[pi] = []
		e.sp_planned[pi] = day - 3
		e.sp_cur[pi] = null
		e.sp_queue[pi] = []
		e.sp_leg[pi] = []
		e.sp_res[pi] = -1
		e.sp_occ[pi] = -1
		e.sp_result[pi] = null
		e.sp_held[pi] = []
		e.sp_pos[pi] = -1
		e.sp_on[pi] = 0
		e.sp_duty[pi] = []
		e.sp_wake[pi] = 0
		e.sp_ride[pi] = []
		e.sp_stairs[pi] = PackedInt32Array()
		e.sp_lin[pi] = -3
		if e._absent.has(pi):
			continue
		plan(e, pi, day + 1)
		for du in e.sp_duties[pi]:
			if du[0] <= c and c < du[1]:
				e.sp_on[pi] = 1
				e.sp_duty[pi] = du
				e.sp_worn[pi] = role_ppe[people[pi]["role"]]     # at work already: in their PPE (§17.11)
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
	e.st_t_from.fill(-1)


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


func give(e, pi: int, tid: String, prio: int, made_by, work, code, alarm, count := true, owner = null,
		act = null, orig = null) -> bool:
	var c = e.sp_cur[pi]
	if e.sp_queue[pi].size() + (1 if c != null and not c["idle"] else 0) >= QUEUE_MAX:
		e._ev(["task", null, tid, "unassigned"])
		return false
	var t: Dictionary = tasks[tid]
	if work == null and t.get("work") != null:
		work = t["work"]
	var inst := {"task": tid, "prio": prio, "made": e.step_no, "order": e.st_order, "step": 0, "st": {},
			"work": work, "code": code, "alarm": alarm, "src": made_by, "idle": false, "started": false,
			"int": t.get("interruptible", true), "owner": owner, "act": act, "orig": orig}
	e.st_order += 1
	_enqueue(e, pi, inst)
	e.sp_wake[pi] = 0
	if made_by != null:
		e.st_given[made_by] = e.st_given.get(made_by, 0) + 1
	if count:
		var k: int = e.st_players.find(pi)
		if k != -1:
			e.st_acks[k] += 1
	return true


func assign(e, role_list: Array, tid: String, prio: int, made_by, work, code, alarm, owner = null,
		act = null, orig = null) -> bool:
	var cands := []
	for r in role_list:
		for pi in people.size():
			if people[pi]["role"] == r and e.sp_on[pi] and not e._absent.has(pi):
				cands.append(pi)
	if cands.is_empty():
		e._ev(["task", null, tid, "unassigned"])
		return false
	# a task that unlocks its work's isolation goes first to someone holding a lock on it: only a lock's owner
	# removes it (§15.1, §17.11)
	var w = work if work != null else tasks[tid].get("work")
	if w != null and unlocks.has(tid) and (unlocks[tid].has(w) or unlocks[tid].has("$")):
		var wi: int = e.m.work_ix.get(w, -1) if typeof(w) == TYPE_STRING else -1
		if wi != -1 and e.m.works[wi].has("isolation"):
			var ii: int = e.m.isolation_ix[e.m.works[wi]["isolation"]]
			for pi in cands:
				for key in e.lockers:
					if key.x == ii and _has(e.lockers[key], people[pi]["id"]):
						return give(e, pi, tid, prio, made_by, work, code, alarm, true, owner, act, orig)
	for pi in cands:
		var c = e.sp_cur[pi]
		if c == null or c["idle"] or (c["prio"] > prio and c["int"]):
			return give(e, pi, tid, prio, made_by, work, code, alarm, true, owner, act, orig)
	return give(e, cands[0], tid, prio, made_by, work, code, alarm, true, owner, act, orig)


## Whether someone has an instance of this task for this work, current or queued (a kept call given again).
func _given_again(e, tid: String, w) -> bool:
	for pi in people.size():
		var all: Array = e.sp_queue[pi].duplicate()
		if e.sp_cur[pi] != null:
			all.append(e.sp_cur[pi])
		for q in all:
			if q["task"] == tid and typeof(q["work"]) == typeof(w) and q["work"] == w:
				return true
	return false


## assign(), and an offer for a permit's work (pw) that found nobody of its roles on duty is kept, to be made again
## when one comes on (§17.10).
func offer(e, role_list: Array, tid: String, prio: int, src, w, code, alarm, pw, owner = null, orig = null) -> void:
	var nobody := true
	for pi in people.size():
		if role_list.has(people[pi]["role"]) and e.sp_on[pi] and not e._absent.has(pi):
			nobody = false
			break
	if not assign(e, role_list, tid, prio, src, w, code, alarm, owner, null, orig) and nobody \
			and typeof(pw) == TYPE_STRING and e.m.work_ix.has(pw) and e.pstate[e.m.work_ix[pw]] >= 1 \
			and e.pstate[e.m.work_ix[pw]] <= 8:
		var ident: String = src if src != null else "call|%s|%s|%s" % ["/".join(role_list), tid, str(w)]
		for pd in e.st_pending:
			if pd[0] == ident:
				return
		e.st_pending.append([ident, src, role_list.duplicate(), tid, prio, w, code, pw, e.pstate[e.m.work_ix[pw]]])


## The reaction on a value a job comes from (§17.12): its own source ("ri|value|name"), or the one whose task called
## it; null for none.
static func vkey(inst: Dictionary):
	var s = inst["src"]
	if typeof(s) == TYPE_STRING:
		var parts := String(s).split("|", true, 2)      # (as the reference's (reaction, "value", name))
		if parts.size() == 3 and parts[1] == "value" and parts[0].is_valid_int():
			return s
	return inst.get("orig")


## A job of a reaction on a value abandoned while the value is still true: the reaction's offer is kept, to be made
## again when someone of its roles comes on duty (§17.12, as §17.10's offers nobody could take).
func value_again(e, inst: Dictionary) -> void:
	var k = vkey(inst)
	if k == null:
		return
	if typeof(k) != TYPE_STRING:
		return
	var parts: PackedStringArray = String(k).split("|", true, 2)
	# (the engine's own keys always pass; a run restored from an edited save may hold anything)
	if parts.size() != 3 or parts[1] != "value" or not parts[0].is_valid_int() \
			or parts[0].to_int() < 0 or parts[0].to_int() >= reactions.size() \
			or reactions[parts[0].to_int()]["on"].get("value") != parts[2] or not e.ix.has(parts[2]):
		return
	var v: String = parts[2]
	if not e.truth(v):
		return
	for pd in e.st_pending:
		if pd[0] == k:
			return
	var r: Dictionary = reactions[int(parts[0])]
	var w = r.get("work")
	e.st_pending.append([k, k, r["roles"].duplicate(), r["task"],
			int(r["priority"]) if r.has("priority") else prio_of(r["task"]), w,
			e.m.works[e.m.work_ix[w]]["kks"] if w != null else null, null, v])


## Someone has a job of that reaction on a value (current, queued or held).
func value_busy(e, k: String) -> bool:
	for pi in people.size():
		var all: Array = e.sp_queue[pi] + e.sp_held[pi]
		if e.sp_cur[pi] != null:
			all.append(e.sp_cur[pi])
		for q in all:
			var vk = vkey(q)
			if typeof(vk) == TYPE_STRING and vk == k:
				return true
	return false


func release(e, inst: Dictionary) -> void:
	var src = inst["src"]
	if src != null:
		e.st_given[src] -= 1
		if e.st_given[src] == 0:
			e.st_given.erase(src)


# ---------------------------------------------------------------- step 1: the players' inputs (§17.6, §17.13)

## A player's input in step 1: role, release, task_ack and jump handled here, the rest kept for step 9. slot is the
## input's (0 in a single-player run).
func t_input(e, item: Array, slot: int = 0) -> void:
	var k: String = item[0]
	var ses: bool = e.st_session
	if k == "role":
		var pid = item[1]
		var ok: bool = typeof(pid) == TYPE_STRING and person_ix.has(pid) and not e._absent.has(person_ix[pid]) \
				and roles[people[person_ix[pid]]["role"]]["play"]
		if ses:
			# at any step: a person nobody plays, for a slot that plays nobody
			ok = ok and e.st_players[slot] == -1 and not e.st_players.has(person_ix[pid])
		else:
			ok = ok and e.step_no == 1 and not e._fixed_trainee and e.st_players[0] == -1
		e._ev(["role", pid, "done" if ok else "refused", slot] if ses else ["role", pid, "done" if ok else "refused"])
		if ok:
			claim(e, slot, person_ix[pid])
		return
	if k == "release":
		var pi: int = e.st_players[slot]
		e._ev(["release", people[pi]["id"] if pi != -1 else null, "done" if pi != -1 else "refused", slot])
		if pi != -1:
			let_go(e, slot)
		return
	if k == "task_ack":
		e.st_acks[slot] = 0
		e._ev(["task_ack", slot] if ses else ["task_ack"])
		return
	if k == "jump":
		jump(e, item[1])
		return
	e.st_t_in.append([slot, item])


## A person becomes slot's (§17.13): an NPC's current task (not the idle task) paused as a pre-emption pauses it, to be
## taken up again at their turn; one on a way is between places from now on (the place they left kept for a
## release); their zones those their place or way gives them now; nothing counted or kept for the slot.
func claim(e, slot: int, pi: int) -> void:
	if not e.st_session:                # a single-player run's role at step 1 (§17.4): the person just becomes theirs
		e.st_players[slot] = pi
		e.st_acks[slot] = 0
		e.st_kept[slot] = []
		return
	var zs := zones_of(e, pi)           # (as an NPC's, before they become the slot's)
	e.st_t_from[slot] = -1
	var leg: Array = e.sp_leg[pi]
	if not leg.is_empty():
		e.st_t_from[slot] = leg[0]
		e.sp_leg[pi] = []
		e.sp_pos[pi] = -1
	var ride: Array = e.sp_ride[pi]
	if not ride.is_empty():             # a ride given up: one aboard stays aboard, the landing kept as the place left
		if e.sp_pos[pi] == -1:
			e.st_t_from[slot] = ride[1]
		e.sp_ride[pi] = []
	e.sp_stairs[pi] = PackedInt32Array()
	var c = e.sp_cur[pi]
	if c != null:
		var x: Dictionary = c["st"]
		# a work or a stay counted up to the step before, as the reference's (one by one) has it: an NPC asleep in it
		# is counted when they wake (turn), and from now on the slot's person counts their own
		if x.has("left") and x.has("last") and not x.get("resumed", false) and x["last"] < e.step_no - 1:
			x["left"] -= e.step_no - 1 - x["last"]
			x["last"] = e.step_no - 1
		if not c["idle"]:
			x.erase("busy")
			pause(e, pi)
	e.sp_result[pi] = null
	e.sp_zin[pi] = zs
	e.st_players[slot] = pi
	e.st_acks[slot] = 0
	e.st_kept[slot] = []


## Slot's person becomes an NPC at once (§17.13): their current task (not the idle task) paused, to be taken up at
## their next turn; one between places put back at the place they last left.
func let_go(e, slot: int) -> void:
	var pi: int = e.st_players[slot]
	e.st_players[slot] = -1
	var pid: String = people[pi]["id"]
	for k in e.riders.size():           # a person aboard leaves the ride: their alight for the next step (§20.3)
		for r in e.riders[k]:
			if _same(r, pid):
				queue_alight(e, e.m.lifts[k]["id"], pid)
	var c = e.sp_cur[pi]
	if c != null:
		if not c["idle"]:
			pause(e, pi)
	if e.sp_pos[pi] == -1 and e.st_t_from[slot] != -1:
		e.sp_pos[pi] = e.st_t_from[slot]
	e.st_t_from[slot] = -1
	e.st_acks[slot] = 0
	e.st_kept[slot] = []
	e.sp_wake[pi] = 0


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
	var ok: bool = e.unacked(-1) == 0
	if ok and not e.ff_model():
		ok = false
	if ok:
		for s in e.pstate:
			if s >= 1 and s <= 7:
				ok = false
				break
	if ok and (not e.st_jumped.is_empty() or e._npc_pending > 0):
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
	var np0 := people.size()
	if e._touched.size() != np0:
		e._touched.resize(np0)
	e._touched.fill(0)
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
			all.append_array(e.sp_held[pi])
			for inst in all:
				e._ev(["task", people[pi]["id"], inst["task"], "skipped"])
		place_all(e, nw, old)
		jump_step = true
	# the players' arrive, leave, ppe, zone and stop inputs, in the order made, each for its slot's person now (a slot
	# playing nobody is in free mode: its stop refused, the others nothing)
	for si in tin:
		var slot: int = si[0]
		var item: Array = si[1]
		var tr: int = e.st_players[slot]
		if tr == -1:
			if item[0] == "stop":       # free mode: no person to stop work with
				e._ev(["stop", null, item[1], null, null, "refused", ["authority"]])
			continue
		if item[0] == "arrive" and typeof(item[1]) == TYPE_STRING and pix.has(item[1]):
			e.sp_pos[tr] = pix[item[1]]
			if e.sp_occ[tr] != e.sp_pos[tr]:
				leave_place(e, tr)          # a place held is let go when the trainee is elsewhere
			if e.sp_res[tr] == e.sp_pos[tr]:
				e.sp_occ[tr] = e.sp_res[tr]
				e.sp_res[tr] = -1
		elif item[0] == "leave" and typeof(item[1]) == TYPE_STRING and e.sp_pos[tr] != -1 \
				and pix.get(item[1], -2) == e.sp_pos[tr]:
			e.st_t_from[slot] = e.sp_pos[tr]
			e.sp_pos[tr] = -1
			leave_place(e, tr)
		elif item[0] == "ppe" and typeof(item[1]) == TYPE_STRING and PPE.has(item[1]) \
				and typeof(item[2]) == TYPE_INT and (item[2] == 0 or item[2] == 1):
			if item[2] == 1:
				e.sp_worn[tr] |= 1 << PPE.find(item[1])
			else:
				e.sp_worn[tr] &= ~(1 << PPE.find(item[1]))
		elif item[0] == "zone" and typeof(item[1]) == TYPE_STRING and zone_ix.has(item[1]) \
				and typeof(item[2]) == TYPE_STRING and (item[2] == "in" or item[2] == "out"):
			if item[2] == "in":
				e.sp_zin[tr] |= 1 << int(zone_ix[item[1]])
			else:
				e.sp_zin[tr] &= ~(1 << int(zone_ix[item[1]]))
		elif item[0] == "stop":
			t_stop(e, tr, item[1])
	# 1. duties, then slots
	var day: int = c / DAY
	var np := people.size()
	if c >= e.st_next1:
		_phase1(e, c, day)
	# 2. reactions
	react(e, n)
	# 4. people
	if jump_step:
		for slot in e.st_players.size():                # their actions of this step are kept all the same (§17.8)
			var ti: int = e.st_players[slot]
			if ti != -1 and not e._absent.has(ti):
				var mine := _mine(e)
				drop_kept(e, mine, people[ti]["id"], slot)
				keep(e, ti, mine, {}, slot)
	else:
		var absent: Dictionary = e._absent     # (made when the run starts, never changed in a step)
		var players: PackedInt32Array = e.st_players
		for pi in np:
			var slot: int = players.find(pi)
			if slot != -1:
				if not absent.has(pi):
					var mine_in := []
					for si in tin:
						if si[0] == slot:
							mine_in.append(si[1])
					trainee_turn(e, pi, mine_in, slot)
			elif n >= e.sp_wake[pi] and not absent.has(pi):
				turn(e, pi)
	# 5. unsafe acts, then the reactions to them
	var moved := false
	for k in range(e.ev_mark, e.events.size()):
		var x: Array = e.events[k]
		if x[0] == n and x[1] == "permit" and x[5] == "done":
			moved = true
			break
	act_phase(e, n, moved)
	findings(e, n)
	_slots(e)
	for j in value_reactions.size():
		e.st_vprev[value_reactions[j]] = e.cur[value_slot[j]] >= 0.5


## The engine slots of the values reactions are on (every engine of one model has the same).
func _slots(e) -> void:
	if value_slot.size() != value_reactions.size():
		for i in value_reactions:
			value_slot.append(e.ix[reactions[i]["on"]["value"]])


## Phase 1 (duties, then slots), run only when the clock reaches the next duty boundary, slot or planning day of
## anyone (st_next1): between them it would change nothing.
func _phase1(e, c: int, day: int) -> void:
	var np := people.size()
	for pi in np:
		if e._absent.has(pi):
			continue
		if e.sp_planned[pi] < day + 1:
			plan(e, pi, day + 1)
		if e.sp_on[pi] and c >= e.sp_duty[pi][1]:
			e.sp_on[pi] = 0
			e.sp_duty[pi] = []
			e.sp_wake[pi] = 0
			e._ev(["duty", people[pi]["id"], "off"])
		if not e.sp_on[pi]:
			var dl: Array = e.sp_duties[pi]
			while not dl.is_empty() and dl[0][1] <= c:
				dl.pop_front()
			if not dl.is_empty() and dl[0][0] <= c:
				e.sp_on[pi] = 1
				e.sp_duty[pi] = dl.pop_front()
				e.sp_wake[pi] = 0
				e._ev(["duty", people[pi]["id"], "on"])
				var held: Array = e.sp_held[pi]  # the jobs held overnight come back (§17.10)
				e.sp_held[pi] = []
				for h in held:
					_enqueue(e, pi, h)
					e._ev(["task", people[pi]["id"], h["task"], "resumed"])
	for pi in np:
		if e._absent.has(pi):
			continue
		var sl: Array = e.sp_slots[pi]
		while not sl.is_empty() and sl[0][0] <= c:
			var s: Array = sl.pop_front()
			give(e, pi, s[4], prio_of(s[4]), null, null, null, null)
	var nx: int = (day + 1) * DAY            # the next day, planned when it begins, at the latest
	for pi in np:
		if e._absent.has(pi):
			continue
		if e.sp_on[pi]:
			nx = mini(nx, e.sp_duty[pi][1])
		elif not e.sp_duties[pi].is_empty():
			nx = mini(nx, e.sp_duties[pi][0][0])
		if not e.sp_slots[pi].is_empty():
			nx = mini(nx, e.sp_slots[pi][0][0])
	e.st_next1 = nx


func react(e, n: int) -> void:
	var evs := []
	for k in range(e.ev_mark, e.events.size()):
		if e.events[k][0] == n:
			evs.append(e.events[k])
	# people who left the site with a lock on since the last phase 2 (§17.9)
	# a permit back to approved by itself (a suspension): its jobs (tasks with resume, given for that work) are
	# abandoned at once, held or not, so nobody works on equipment no longer isolated and the reaction to its next
	# issue offers the job again (§17.10)
	var back := {}
	for x in evs:
		if x[1] == "permit" and x[3] == "auto" and x[6] == [2]:
			back[x[2]] = true
	if not back.is_empty():
		for pi in people.size():
			var c = e.sp_cur[pi]
			if c != null and _job_of(c, back):
				finish(e, pi, "abandoned")
				e.sp_wake[pi] = 0       # (asleep in a work step: their next task starts at once, as the reference)
			var gone_q := []
			var keep_q := []
			for q in e.sp_queue[pi]:
				if _job_of(q, back):
					gone_q.append(q)
				else:
					keep_q.append(q)
			var keep_h := []
			for q in e.sp_held[pi]:
				if _job_of(q, back):
					gone_q.append(q)
				else:
					keep_h.append(q)
			for inst in gone_q:
				e._ev(["task", people[pi]["id"], inst["task"], "abandoned"])
				release(e, inst)
				value_again(e, inst)
				e.sp_wake[pi] = 0
			e.sp_queue[pi] = keep_q
			e.sp_held[pi] = keep_h
	if reactions.is_empty() and e.st_pending.is_empty():
		return
	var gone := []
	if has_left:
		for x in evs:
			if x[1] == "duty" and x[3] == "on":
				e.st_left = {}          # someone came on duty: a lock still left is given again (§17.9)
				break
		var now := {}
		# only a lock's holder can have left one: found from the locks (few), not by asking everyone every step
		var holds := PackedByteArray()
		if not e.lockers.is_empty():
			holds.resize(people.size())
			for key in e.lockers:
				for h in e.lockers[key]:
					if typeof(h) == TYPE_STRING and person_ix.has(h):
						holds[person_ix[h]] = 1
		for pi in holds.size():
			if holds[pi] and not e.st_players.has(pi) and not e._absent.has(pi) and not e.sp_on[pi] \
					and e.sp_pos[pi] == -1 and e.sp_leg[pi].is_empty() and _left_locks(e, pi):
				now[pi] = true
				if not e.st_left.has(pi):
					gone.append(pi)
		e.st_left = now
	# permit offers that found nobody on duty: offered again when someone of their roles comes on, at each later
	# shift until taken, while the permit is still at its state then (§17.10)
	if not e.st_pending.is_empty():
		var came := {}
		for x in evs:
			if x[1] == "duty" and x[3] == "on":
				came[people[person_ix[x[2]]]["role"]] = true
		var keep := []
		for pd in e.st_pending:
			# [ident, src or null, roles, task, prio, work given, code, permit's work, its state then]; a job of a
			# reaction on a value, abandoned: [key, key, roles, task, prio, work, code, null, the value's name], kept
			# while the value is true, offered again when someone of its roles comes on and nobody has a job of it
			if pd[7] == null:
				if not e.truth(pd[8]):
					continue
				var came_v := false
				for ro in pd[2]:
					if came.has(ro):
						came_v = true
				if value_busy(e, pd[0]) or not came_v or not assign(e, pd[2], pd[3], pd[4], pd[1], pd[5], pd[6], null):
					keep.append(pd)
				continue
			if e.pstate[e.m.work_ix[pd[7]]] != pd[8] or (pd[1] != null and e.st_given.has(pd[1])) \
					or (pd[1] == null and _given_again(e, pd[3], pd[5])):
				continue            # moved on, or given meanwhile (a call: the same task and work given again)
			var any_role := false
			for ro in pd[2]:
				if came.has(ro):
					any_role = true
			if not any_role or not assign(e, pd[2], pd[3], pd[4], pd[1], pd[5], pd[6], null):
				keep.append(pd)
		e.st_pending = keep
	# only these events start reactions here (the unsafe acts' are phase 5's): most steps have none of them
	var rel := []
	for x in evs:
		if x[1] == "alarm" or x[1] == "trip" or x[1] == "fault" or x[1] == "permit":
			rel.append(x)
	evs = rel
	if evs.is_empty() and value_reactions.is_empty() and gone.is_empty():
		return
	# (most steps: only the reactions on a value can be made, looked at alone in reaction order; milestone S3's
	# value reactions made a pass over every reaction each step cost a third of the staff step)
	if evs.is_empty() and gone.is_empty():
		_slots(e)
		var edge := false       # (a value turning true is rare: most steps end here)
		for j in value_reactions.size():
			var pv = e.st_vprev[value_reactions[j]]
			if e.cur[value_slot[j]] >= 0.5 and typeof(pv) == TYPE_BOOL and not pv:
				edge = true
				break
		if not edge:
			return
	var idxs = value_reactions if evs.is_empty() and gone.is_empty() else range(reactions.size())
	for ri in idxs:
		var r: Dictionary = reactions[ri]
		var k: String = react_kind[ri]
		if evs.is_empty() and k != "value" and k != "lock_left":
			continue
		var v = r["on"][k]
		var hits := []          # [source key, work, code, alarm]
		if k == "value":
			var now: bool = e.truth(v)
			if now and typeof(e.st_vprev[ri]) == TYPE_BOOL and not e.st_vprev[ri]:
				hits.append(["value|" + v, null, null, null])
		elif k == "lock_left":
			for pi in gone:
				hits.append(["lock_left|" + people[pi]["id"], null, null, null, people[pi]["id"]])
		else:
			for x in evs:
				if k == "alarm" and x[1] == "alarm" and x[3] == "active_unack":
					var a: Dictionary = e.m.alarms[e._al_ix[x[2]]]
					if a["priority"] <= v and (not r.has("areas") or r["areas"].has(e.m.alarm_area[x[2]])):
						hits.append(["alarm|" + x[2], null, a["where"], x[2]])
				elif k == "trip" and x[1] == "trip" and (v == "*" or v == x[2]) \
						and (not r.has("areas") or r["areas"].has(e.m.trip_area[x[2]])):
					hits.append(["trip|" + x[2], null, null, null])
				elif k == "fault" and x[1] == "fault" and x[2] == v:
					hits.append(["fault|" + v, null, e.fault_code(v), null])
				elif k == "permit" and x[1] == "permit" and x[5] == "done":
					var nw: int = x[6][0] if x[3] == "auto" else PERMIT_TO[x[3]]
					if STATE_NAMES[nw] == v and (not r.has("work") or r["work"] == x[2]):
						hits.append(["permit|" + x[2], x[2], e.m.works[e.m.work_ix[x[2]]]["kks"], null])
		if hits.is_empty():
			continue
		var prio: int = int(r["priority"]) if r.has("priority") else prio_of(r["task"])
		for h in hits:
			var key: String = str(ri) + "|" + h[0]
			if e.st_given.has(key):
				continue
			var w = r.get("work", h[1])
			var code = h[2]
			if code == null and w != null:
				code = e.m.works[e.m.work_ix[w]]["kks"]
			offer(e, r["roles"], r["task"], prio, key, w, code, h[3], h[1] if k == "permit" else null,
					h[4] if h.size() > 4 else null)


# ---------------------------------------------------------------- a person's turn (phase 4)

func select(e, pi: int):
	var cur = e.sp_cur[pi]
	var q: Array = e.sp_queue[pi]
	var pid: String = people[pi]["id"]
	var npc: bool = not e.st_players.has(pi)
	if cur != null and not e.sp_on[pi] and npc and not cur["idle"] \
			and not cur["st"].get("busy", false) and tasks[cur["task"]].get("resume", "") == "next_duty":
		pause(e, pi)                # a job left unfinished at the duty's end: held for the next (§17.10)
		for k in q.size():
			if is_same(q[k], cur):
				q.remove_at(k)
				break
		e.sp_held[pi].append(cur)
		e._ev(["task", pid, cur["task"], "held"])
		cur = null
	if cur == null and not e.sp_on[pi] and npc:
		var keep := []
		for qq in q:
			if tasks[qq["task"]].get("resume", "") == "next_duty":
				e.sp_held[pi].append(qq)    # queued jobs off duty: held as they are, no walk to them first
				e._ev(["task", pid, qq["task"], "held"])
			else:
				keep.append(qq)
		if keep.size() != q.size():
			q.clear()
			q.append_array(keep)
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
		if e.sp_pos[pi] == -1 and npc:
			e.sp_pos[pi] = gate
			e._ev(["move", pid, null, places[gate]["id"], e.step_no])
	if cur == null and e.sp_on[pi]:
		var idle := idle_of(pi)
		cur = {"task": idle, "prio": 6, "made": e.step_no, "order": e.st_order, "step": 0, "st": {}, "work": null,
				"code": null, "alarm": null, "src": null, "idle": true, "started": true, "int": true, "owner": null,
				"act": null}
		e.sp_cur[pi] = cur
		e.st_order += 1
		e._ev(["task", pid, idle, "start"])
		if e.sp_pos[pi] == -1 and npc:
			e.sp_pos[pi] = gate
			e._ev(["move", pid, null, places[gate]["id"], e.step_no])
	if cur == null and not e.sp_on[pi] and e.sp_pos[pi] != -1 and npc:
		leave_place(e, pi)
		e._ev(["move", pid, places[e.sp_pos[pi]]["id"], null, e.step_no])
		e.sp_pos[pi] = -1
		e.sp_worn[pi] = 0       # PPE left in the locker when leaving the site (§17.11)
	return cur


func pause(e, pi: int) -> void:
	var cur: Dictionary = e.sp_cur[pi]
	var st: Dictionary = cur["st"]
	if st.has("left") and st.has("last") and not e.st_players.has(pi):
		# the steps slept through up to the last one before the pause count; on resuming, one step does
		var m: int = e.step_no - 1
		if st["last"] < m and not st.get("resumed", false):
			st["left"] -= m - st["last"]
			st["last"] = m
		st["resumed"] = true
	for k in ["dest", "waiting", "wait_since", "target", "meet_since", "seat", "seen", "pt", "since"]:
		st.erase(k)          # (seen: a resumed step is current again, §17.8)
	unreserve(e, pi)
	_enqueue(e, pi, cur)
	e.sp_cur[pi] = null


func finish(e, pi: int, how: String) -> void:
	var cur: Dictionary = e.sp_cur[pi]
	e._ev(["task", people[pi]["id"], cur["task"], how])
	release(e, cur)
	unreserve(e, pi)
	e.sp_cur[pi] = null
	if how == "abandoned":
		value_again(e, cur)


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


## A person's turn in phase 4. Asleep until sp_wake (a walk's arrival, the end of a `work` or a meeting's stay): the
## turns in between would change nothing, so they are not run (§0062: "people with nothing due in a step may be
## skipped by an implementation as long as the result is the same"); a task given to them, a duty's start or end and
## a placement wake them at once, and a work's time is counted as the steps gone (the reference counts them one by
## one: the vectors check that the two agree).
func turn(e, pi: int) -> void:
	var n: int = e.step_no
	if n < e.sp_wake[pi]:
		return
	e._touched[pi] = 1
	var leg: Array = e.sp_leg[pi]
	if not leg.is_empty():
		if leg[3] > n:
			e.sp_wake[pi] = leg[3]
			return
		e.sp_pos[pi] = leg[1]
		e.sp_leg[pi] = []
		if e.sp_pos[pi] == e.sp_res[pi]:
			e.sp_occ[pi] = e.sp_pos[pi]
			e.sp_res[pi] = -1
	if has_lifts and not e.sp_ride[pi].is_empty() and not ride_turn(e, pi):
		return
	for _k in 64:
		var cur = select(e, pi)
		if cur == null:
			e.sp_wake[pi] = 1 << 62     # nothing to do and off duty: until a task or a duty wakes them
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
		if e.sp_res[pi] == dest:        # already standing there: the place reserved is now held
			e.sp_occ[pi] = dest
			e.sp_res[pi] = -1
		if has_lifts:
			e.sp_stairs[pi] = PackedInt32Array()
		return true
	var nx := -1
	if has_lifts:
		var sr: PackedInt32Array = e.sp_stairs[pi]
		if not sr.is_empty() and (sr[0] != dest or sr[1] != pos):
			sr = PackedInt32Array()     # (another walk: the stairs were this one's)
			e.sp_stairs[pi] = sr
		if not sr.is_empty():
			nx = sr[2]
			if sr.size() > 3:
				var rest := PackedInt32Array([dest])
				rest.append_array(sr.slice(2))
				e.sp_stairs[pi] = rest
			else:
				e.sp_stairs[pi] = PackedInt32Array()
		else:
			nx = hop(pos, dest)
			var li: int = lift_way.get(mini(pos, nx) * places.size() + maxi(pos, nx), -1)
			if li != -1:                # a lift way: they ride instead of walking it (§20.4)
				e.sp_ride[pi] = [li, pos, nx, 0, e.step_no, dest]
				e._ev(["ride", people[pi]["id"], lifts[li][0], places[pos]["id"], places[nx]["id"], "wait"])
				return false
	else:
		nx = hop(pos, dest)
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


## An alight for the next step, unless one is queued already (a release and a jump in one step).
static func queue_alight(e, lid: String, pid: String) -> void:
	for y in e.npc_queue:
		if y.size() == 3 and _same(y[0], "alight") and _same(y[1], lid) and _same(y[2], pid):
			return
	e.npc_queue.append(["alight", lid, pid])


## A person's turn on a ride (§20.4), with the values as steps 2–8 left them: true when it is over and they go on (off
## at a landing, or up the stairs), false while it lasts (ref/plant3d_staff.py ride_turn).
func ride_turn(e, pi: int) -> bool:
	var n: int = e.step_no
	var ride: Array = e.sp_ride[pi]
	var li: int = ride[0]
	var a: int = ride[1]
	var b: int = ride[2]
	var since: int = ride[4]
	var dest: int = ride[5]
	var lid: String = lifts[li][0]
	var pts: PackedInt32Array = lifts[li][1]
	var x: Dictionary = lift_model[li]
	var lds: Array = x["landings"]
	var pid: String = people[pi]["id"]
	var k: int = e._lift_ix[lid]
	var rs: Array = e.riders[k]
	var aboard := false
	for r in rs:
		if _same(r, pid):
			aboard = true
			break
	if aboard and ride[3] == 0:         # aboard now: their 3 minutes count again from here
		ride[3] = 1
		ride[4] = n
		since = n
	elif not aboard:
		ride[3] = 0
	var can: bool = n > e.sp_lin[pi] + 2
	var ia := pts.find(a)
	var ib := pts.find(b)
	var calls: int = e.lift_calls[k]
	var load: float = e.cur[e._load_slot[k]]
	var over: bool = load > float(x["rated_kg"])
	var ready := _t(e, x["ready"])
	var q: Array = e.npc_queue
	if not aboard:
		e.sp_pos[pi] = a
		if not ready or n - since >= RIDE_WAIT:
			e._ev(["ride", pid, lid, places[a]["id"], places[b]["id"], "stairs"])
			e.sp_ride[pi] = []
			var sr := PackedInt32Array([dest])
			sr.append_array(stairs[a * places.size() + b])
			e.sp_stairs[pi] = sr
			return true
		if not can:
			return false
		var at := _t(e, lds[ia]["at"])
		var boards := _queued(q, "board", lid)
		var room: bool = load + float(x["person_kg"]) * (1 + boards) <= float(x["rated_kg"])
		if at and _t(e, lds[ia]["open"]):
			if room and not _lift_made(e, lds[ia]["gate"], "close"):    # (not into a gate that is shutting)
				q.append(["board", lid, pid])
				e.sp_lin[pi] = n
		elif at and _t(e, lds[ia]["shut"]):
			if room:
				_lift_op(e, pi, lds[ia]["gate"], "open")
		elif not at and not (calls >> ia & 1) and not over:
			_lift_op(e, pi, lds[ia]["call"], "start")
		return false
	e.sp_pos[pi] = -1
	if not can:
		return false
	var c := -1
	for j in lds.size():
		if _t(e, lds[j]["at"]):
			c = j
			break
	var timeout: bool = n - since >= RIDE_WAIT
	var bumped: bool = over and _same(last_npc(e, rs), pid)
	if c != -1 and (c == ib or not ready or bumped or timeout):
		# out here: where they are going; the lift not ready; the last NPC in when the cab is over its rated load; or
		# after 3 minutes aboard (then up or down the stairs)
		var ld: Dictionary = lds[c]
		if _t(e, ld["open"]):
			var alights := _queued(q, "alight", lid)
			var boards := _queued(q, "board", lid)
			q.append(["alight", lid, pid])
			e.sp_lin[pi] = n
			if rs.size() - alights + boards == 1 and (c == ib or ready):
				_lift_op(e, pi, ld["gate"], "close")    # the last one out shuts the gate behind them
			e._ev(["ride", pid, lid, places[a]["id"], places[b]["id"], "off"])
			e.sp_ride[pi] = []
			e.sp_pos[pi] = pts[c]
			if c != ib and ready and not bumped and pts[c] != dest:
				var nx := hop(pts[c], dest)
				var key: int = pts[c] * places.size() + nx
				if stairs.has(key):
					e._ev(["ride", pid, lid, places[a]["id"], places[b]["id"], "stairs"])
					var sr := PackedInt32Array([dest])
					sr.append_array(stairs[key])
					e.sp_stairs[pi] = sr
			return true
		if _t(e, ld["shut"]) or timeout and n - e.sp_lin[pi] >= RIDE_QUIET:
			_lift_op(e, pi, ld["gate"], "open")     # (after 3 minutes, a gate neither open nor shut too: every 5 s)
		return false
	if ready and not over and not (calls >> ib & 1):
		_lift_op(e, pi, x["panel"], "set", ib)      # where they are going, from the cab's panel
	elif c != -1 and not over and _t(e, lds[c]["open"]) and n - e.lift_quiet[k] >= RIDE_QUIET \
			and _queued(q, "board", lid) == 0:     # (not on someone boarding)
		_lift_op(e, pi, lds[c]["gate"], "close")
	return false


static func _queued(q: Array, kind: String, lid: String) -> int:
	var t := 0
	for y in q:
		if _same(y[0], kind) and _same(y[1], lid):
			t += 1
	return t


## The NPC who boarded last of a lift's riders, or null.
func last_npc(e, rs: Array):
	for j in range(rs.size() - 1, -1, -1):
		if typeof(rs[j]) == TYPE_STRING and e.slot_of(person_ix[rs[j]]) == -1:
			return rs[j]
	return null


static func _t(e, name: String) -> bool:
	return e.cur[e.ix[name]] >= 0.5


## An op of the same code and do done in this step's step 1, or made in this phase 4 (with the same value).
static func _lift_made(e, code: String, do: String, value = null) -> bool:
	for y in e.npc_queue:
		if y[0] == "op" and _same(y[1], code) and _same(y[2], do) and _same(y[3], value):
			return true
	for k in range(e.ev_mark, e.events.size()):
		var y: Array = e.events[k]
		if y.size() > 4 and _same(y[1], "op") and _same(y[2], code) and _same(y[3], do) and _same(y[4], "done"):
			return true
	return false


## A rider's op (a local op by the person), not made again (_lift_made).
func _lift_op(e, pi: int, code: String, do: String, value = null) -> void:
	if not _lift_made(e, code, do, value):
		e.npc_queue.append(["op", code, do, value, null, "local", people[pi]["id"]])
		e.sp_lin[pi] = e.step_no


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
			x["place"] = e.sp_pos[pi] if e.sp_pos[pi] != -1 else null
		elif x["place"] != null and (e.sp_pos[pi] != x["place"] or x.has("back")):
			# resumed elsewhere (called away, or held overnight): back to where it was being done first, as a go; its
			# time runs again from the arrival (§17.3)
			x["back"] = true
			var r := go(e, pi, cur, int(x["place"]))
			if r != "next":
				return r
			for k in ["back", "dest", "target", "waiting", "wait_since", "resumed"]:
				x.erase(k)          # (resumed: the time away is not counted, the steps from here on are)
			x["last"] = n
		elif x["last"] < n:
			_count(x, n)
		if x["left"] <= 0:
			return "next"
		e.sp_wake[pi] = n + x["left"]
		return "wait"
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
		offer(e, [c["role"]], c["task"], prio_of(c["task"]), null, w, cur["code"], cur["alarm"], w, null, vkey(cur))
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
	if s.has("handover") or s.has("remove_locks"):
		return lock_round(e, pi, cur, s)
	if s.has("ppe"):
		if typeof(s["ppe"]) == TYPE_STRING and s["ppe"] == "off":
			e.sp_worn[pi] = 0
		else:
			e.sp_worn[pi] |= _ppe_of(pi, s["ppe"])
		return "next"
	if s.has("stop"):
		return stop_step(e, pi, cur)
	push_error("staff: no step kind in " + str(s))
	return "next"


## A ppe step's items ("role" or a list) as a bit mask.
func _ppe_of(pi: int, x) -> int:
	if typeof(x) == TYPE_STRING:
		return role_ppe[people[pi]["role"]]
	return ppe_mask(x)


## An NPC's stop step: to the place the acting person is at when the step starts (a place held by someone: its
## room's door, else its point), then the act stopped if it still goes on and nobody has stopped it (§16.7).
func stop_step(e, pi: int, cur: Dictionary) -> String:
	var act = cur["act"]
	var x: Dictionary = cur["st"]
	if act == null or act[0] == pi:
		return "next"           # (no act, or their own: nobody stops their own act)"
	if not x.has("dest"):
		var qi: int = act[0]
		var t: int = e.sp_pos[qi]
		if t == -1 and not e.sp_leg[qi].is_empty():
			t = e.sp_leg[qi][1]
		if not ongoing(e, act):
			return "next"
		if t == -1:
			return "wait"           # (the trainee between places: until they are at one, or the act is over)
		if not open[t]:
			var dr: int = door.get(room_of[t], -1) if room_of[t] != null else -1
			if dr != -1 and dr != t:
				t = dr
			elif point_no[t] == -1:
				t = stub[t]
		x["dest"] = t
	if not walk(e, pi, x["dest"]):
		return "wait"
	if ongoing(e, act):
		stop_act(e, pi, act)
	return "next"


# ---------------------------------------------------------------- unsafe acts (§16.7, phase 5) and stopping work

## A person's zones as a bit mask (§16.2): their place's; on a way, those both its ends list; the trainee's from
## their zone inputs; none off site.
func zones_of(e, pi: int) -> int:
	if e.st_players.has(pi):
		return e.sp_zin[pi]
	var leg: Array = e.sp_leg[pi]
	if not leg.is_empty():
		return place_zm[leg[0]] & place_zm[leg[1]]
	var p: int = e.sp_pos[pi]
	if p == -1 and has_lifts and not e.sp_ride[pi].is_empty():     # aboard: as on a way between the landings
		return place_zm[e.sp_ride[pi][1]] & place_zm[e.sp_ride[pi][2]]
	return place_zm[p] if p != -1 else 0


## [zone or work] while the act's condition holds, else [].
func _act_now(e, pi: int, k: int) -> Array:
	if k == 0:
		var zm := zones_of(e, pi)
		if zm == 0:
			return []
		var worn: int = e.sp_worn[pi]
		for z in zone_ids.size():
			if zm & (1 << z) and (zone_ppe[z] & ~worn) != 0:
				return [zone_ids[z]]
		return []
	var cur = e.sp_cur[pi]
	if cur == null or cur["idle"]:
		return []
	var s: Dictionary = tasks[cur["task"]]["steps"][cur["step"]]
	if k == 2:
		return [cur["work"]] if s.get("unsafe", false) == true else []
	var w = cur["work"]
	if not s.has("work") or w == null or not e.sp_leg[pi].is_empty():
		return []
	var wi: int = e.m.work_ix.get(w, -1)
	var p: int = e.sp_pos[pi]
	if wi == -1 or p == -1 or e.pstate[wi] == 5:
		return []
	if place_kks[p] != null and place_kks[p] == e.m.works[wi]["kks"]:
		return [w]
	return []


## Phase 5: acts start and end, in person order (kinds in order); then the reactions to them. Only the people whose
## state may have changed are looked at again (their turn ran, a stop, a placement; every one when a permit moved,
## and the trainee always): the others' acts stay as they are, as the reference finds them by looking at everyone.
func act_phase(e, n: int, permit_moved: bool) -> void:
	var started := []
	# (the engine's fields read once: neither changes in this loop, and a field of an untyped object is looked up by
	# name each time it is read)
	var absent: Dictionary = e._absent
	var touched: PackedByteArray = e._touched
	var players: PackedInt32Array = e.st_players
	for pi in people.size():
		if not permit_moved and not touched[pi] and not players.has(pi):
			continue
		if absent.has(pi):
			continue
		var acts: Array = e.sp_acts[pi]
		for k in 3:
			var now := _act_now(e, pi, k)
			var a = acts[k]
			if a != null and now.is_empty():
				acts[k] = null
				e._ev(["safe", people[pi]["id"], ACT_KINDS[k], a[0]])
			elif a == null and not now.is_empty():
				acts[k] = [now[0], n, false]
				e._ev(["unsafe", people[pi]["id"], ACT_KINDS[k], now[0]])
				started.append([pi, k])
	var acting := PackedInt32Array()    # the people with an act going on (in person order), for the seen reactions
	var looked := false
	for ri in act_reactions:
		var r: Dictionary = reactions[ri]
		var v: String = r["on"]["unsafe"]
		var prio: int = int(r.get("priority", prio_of(r["task"])))
		if r.get("seen", false):
			# the safety walk finds it: the first of its roles (role order, then index) in a zone of the act, in the
			# step it starts or any later one while it lasts; once per act
			if acting.is_empty() and not looked:
				looked = true
				var acts_now: Array = e.sp_acts
				for pi in people.size():
					var aa: Array = acts_now[pi]
					if aa[0] != null or aa[1] != null or aa[2] != null:
						acting.append(pi)
			var all_acts: Array = e.sp_acts
			var made_all: Dictionary = e.st_made
			for pi in acting:
				var aa: Array = all_acts[pi]
				for k in 3:
					var a = aa[k]
					if a == null or (v != "*" and v != ACT_KINDS[k]):
						continue
					var made := Vector4i(ri, pi, k, a[1])      # (not the source key: made every step, it cost)
					if made_all.has(made):
						continue
					var obs := observer(e, r["roles"], pi)
					if obs == -1:
						continue
					e.st_made[made] = true
					var key := "%d|unsafe|%s|%s|%d" % [ri, people[pi]["id"], ACT_KINDS[k], a[1]]
					if not e.st_given.has(key):
						give(e, obs, r["task"], prio, key, null, null, null, true, null, [pi, k, a[1]])
		else:
			for sk in started:
				var k: int = sk[1]
				var key := "%d|unsafe|%s|%s|%d" % [ri, people[sk[0]]["id"], ACT_KINDS[k], n]
				if (v == "*" or v == ACT_KINDS[k]) and not e.st_given.has(key):
					assign(e, r["roles"], r["task"], prio, key, null, null, null, null, [sk[0], k, n])


## Phase 5's end (§17.12): the readings of this step out of their range given by the reactions on a finding, in
## reaction order, each reading in the order made; the task's "$" code is the code read.
func findings(e, n: int) -> void:
	if finding_reactions.is_empty():
		return
	var found := []
	for k in range(e.ev_mark, e.events.size()):
		var x: Array = e.events[k]
		if x[0] == n and x[1] == "read" and x[5] == "out_of_range":
			found.append(x)
	if found.is_empty():
		return
	for ri in finding_reactions:
		var r: Dictionary = reactions[ri]
		var v: String = r["on"]["finding"]
		var prio: int = int(r.get("priority", prio_of(r["task"])))
		for x in found:
			var key := "%d|finding|%s" % [ri, x[3]]
			if (v == "*" or v == x[3]) and not e.st_given.has(key):
				assign(e, r["roles"], r["task"], prio, key, r.get("work"), x[3], null)


## Who of the roles sees an act of person ai: on duty, in a zone ai is in now (§16.7); -1 for nobody.
func observer(e, role_list: Array, ai: int) -> int:
	var zs := zones_of(e, ai)
	if zs == 0:
		return -1
	var on: PackedByteArray = e.sp_on
	var absent: Dictionary = e._absent
	for r in role_list:
		for qi in role_people.get(r, PackedInt32Array()):
			if on[qi] and qi != ai and not absent.has(qi) and (zs & zones_of(e, qi)) != 0:
				return qi
	return -1


## Whether the act [person index, kind index, start step] still goes on and nobody has stopped it.
func ongoing(e, act: Array) -> bool:
	var a = e.sp_acts[act[0]][act[1]]
	return a != null and a[1] == act[2] and not a[2]


## pi stops the act: its person's current task abandoned (or to its else), the put_right task for its kind given to
## them at priority 1 (§16.7).
func stop_act(e, pi: int, act: Array) -> void:
	var qi: int = act[0]
	var a: Array = e.sp_acts[qi][act[1]]
	a[2] = true
	var kname: String = ACT_KINDS[act[1]]
	e._ev(["stop", people[pi]["id"], people[qi]["id"], kname, a[0], "done", []])
	e._touched[qi] = 1
	e.sp_wake[qi] = 0
	var c = e.sp_cur[qi]
	if c != null:
		if c["idle"]:
			finish(e, qi, "abandoned")
		else:
			c["st"].erase("busy")
			advance(e, qi, "fail")
	if put_right.has(kname):
		give(e, qi, put_right[kname], 1, null, null, null, null)


## The trainee's stop input (§17.11): an act of that person's, the first kind not yet stopped.
func t_stop(e, ti: int, who) -> void:
	var why := []
	if not auth[people[ti]["role"]].has("stop_work"):
		why.append("authority")
	var act = null
	if typeof(who) == TYPE_STRING and person_ix.has(who) and not e._absent.has(person_ix[who]) \
			and person_ix[who] != ti:
		var qi: int = person_ix[who]
		for k in 3:
			var a = e.sp_acts[qi][k]
			if a != null and not a[2]:
				act = [qi, k, a[1]]
				break
	if act == null:
		why.append("no_act")
	if not why.is_empty():
		e._ev(["stop", people[ti]["id"], who, null, null, "refused", why])
		return
	stop_act(e, ti, act)


# ---------------------------------------------------------------- locks at a shift change (§17.9)

## A lock's holder gone home while a job for its work is held (theirs or a colleague's): the lock stays on overnight
## and its owner removes it when the job resumes (§17.10). For the permit form.
func overnight(e, who, work: String) -> bool:
	if typeof(who) != TYPE_STRING or not person_ix.has(who):
		return false
	var pi: int = person_ix[who]
	return _kept_works(e).has(work) and not e.sp_on[pi] and e.sp_pos[pi] == -1 and e.sp_leg[pi].is_empty()


## The works of anyone's jobs (tasks with resume, given for a work), held, queued or current: every lock on those
## stays on, whoever placed it, until the job ends (§17.10; the user, 2026-10-25).
func _kept_works(e) -> Dictionary:
	var out := {}
	for qi in people.size():
		var all: Array = e.sp_queue[qi] + e.sp_held[qi]
		if e.sp_cur[qi] != null:
			all.append(e.sp_cur[qi])
		for q in all:
			if typeof(q["work"]) == TYPE_STRING and tasks[q["task"]].get("resume", "") == "next_duty":
				out[q["work"]] = true
	return out


## Whether pi holds a lock that is not kept for a held job (§17.10).
func _left_locks(e, pi: int) -> bool:
	var pid: String = people[pi]["id"]
	var kept = null             # made only for someone holding a lock (asked of everyone off site, every step)
	for key in e.lockers:
		if _has(e.lockers[key], pid):
			if kept == null:
				kept = _kept_works(e)
			if not kept.has(e.m.works[e.holder[key.x]]["id"]):
				return true
	return false


## A lock of the remove_locks step's owner, not kept for a held job (§17.10).
func _removable(e, cur: Dictionary, key: Vector2i, held: Array) -> bool:
	var o = cur.get("owner")
	if o == null or not _has(held, o):
		return false
	if typeof(o) != TYPE_STRING or not person_ix.has(o):
		return true
	return not _kept_works(e).has(e.m.works[e.holder[key.x]]["id"])


## A job (a task with resume) given for one of these works.
func _job_of(inst: Dictionary, works: Dictionary) -> bool:
	return typeof(inst["work"]) == TYPE_STRING and works.has(inst["work"]) \
			and tasks[inst["task"]].get("resume", "") == "next_duty"


## Whether a point's locks hold one of this person's (any type: compared as a person).
static func _has(held: Array, who) -> bool:
	for h in held:
		if _same(h, who):
			return true
	return false


func _holds_any(e, who) -> bool:
	for key in e.lockers:
		if _has(e.lockers[key], who):
			return true
	return false


## Whether `who` (a lock's person) is a post-mate of pi: another person of pi's role and routine.
func mate(pi: int, who) -> bool:
	if typeof(who) != TYPE_STRING or who == people[pi]["id"] or not person_ix.has(who):
		return false
	var q: Dictionary = people[person_ix[who]]
	# a crew-mate hands nothing over at a shift change: they come and go together
	if q.has("crew") and people[pi].has("crew") and q["crew"] == people[pi]["crew"]:
		return false
	return post[person_ix[who]] == post[pi]


## Whether another person's take step has chosen the point and is still taking it.
func chosen(e, pi: int, key: Vector2i) -> bool:
	for qi in people.size():
		var c = e.sp_cur[qi]
		if qi != pi and c != null and c["st"].has("pt") and c["st"]["pt"] == key \
				and tasks[c["task"]]["steps"][c["step"]].get("handover", "") == "take":
			return true
	return false


## A point to take over: a post-mate's lock on it, none of theirs nor of a crew-mate of their post (already taken
## over), and its work still open (returned or cancelled: the isolation is coming off, §17.9).
func _to_take_at(e, pi: int, k: int, held: Array) -> bool:
	var pid: String = people[pi]["id"]
	if _has(held, pid):
		return false
	var st: int = e.pstate[e.holder[k]]
	if st == 7 or st == 10:
		return false
	for x in held:
		if typeof(x) == TYPE_STRING and x != pid and person_ix.has(x):
			var q: Dictionary = people[person_ix[x]]
			if post[person_ix[x]] == post[pi] and q.has("crew") and people[pi].has("crew") \
					and q["crew"] == people[pi]["crew"]:
				return false
	for x in held:
		if mate(pi, x):
			return true
	return false


## Whether the point is still to do for a take, give or remove_locks step.
func _still(e, pi: int, cur: Dictionary, s: Dictionary, key: Vector2i) -> bool:
	var held: Array = e.lockers.get(key, [])
	if held.is_empty():
		return false
	var h: String = s.get("handover", "")
	if h == "take":
		return _to_take_at(e, pi, key.x, held)
	if h == "give":
		return _has(held, people[pi]["id"])
	return _removable(e, cur, key, held)


## The next point of a take, give or remove_locks step (isolations, then points, in model order), or
## Vector2i(-1, -1). With x null (the trainee's), nothing is tried or chosen by others.
func lock_target(e, pi: int, cur: Dictionary, s: Dictionary, x) -> Vector2i:
	var tried: Array = x.get("tried", []) if x != null else []
	var take: bool = s.get("handover", "") == "take"
	for k in e._iso.size():
		for j in e._iso[k][1].size():
			var key := Vector2i(k, j)
			if not e.lockers.has(key) or tried.has(key):
				continue
			if not _still(e, pi, cur, s, key):
				continue
			if take and x != null and chosen(e, pi, key):
				continue
			return key
	return Vector2i(-1, -1)


## The points still to do for a take, give or remove_locks step (the trainee's panel, §18.7), in model order.
func points_left(e, pi: int, cur: Dictionary, s: Dictionary) -> Array:
	var out := []
	for k in e._iso.size():
		for j in e._iso[k][1].size():
			if _still(e, pi, cur, s, Vector2i(k, j)):
				out.append(Vector2i(k, j))
	return out


## An NPC's take, give or remove_locks step: one point at a time.
func lock_round(e, pi: int, cur: Dictionary, s: Dictionary):
	var x: Dictionary = cur["st"]
	if not x.has("tried"):
		x["tried"] = []
	var tried: Array = x["tried"]
	var pid: String = people[pi]["id"]
	var kind: String = s.get("handover", "remove")
	if x.get("busy", false):
		if e.sp_result[pi] == null:
			return "wait"
		e.sp_result[pi] = null
		x["busy"] = false
		tried.append(x["pt"])
		x.erase("pt")
		x.erase("since")
	for _i in MAX_POINTS:
		if not x.has("pt"):
			var t := lock_target(e, pi, cur, s, x)
			if t.x == -1:
				return "next"
			x["pt"] = t
		var key: Vector2i = x["pt"]
		if not _still(e, pi, cur, s, key):
			tried.append(key)           # no longer to do (taken, given or removed meanwhile)
			x.erase("pt")
			x.erase("since")
			continue
		var wp: int = work_at.get(e._iso[key.x][1][key.y][0], -1)
		if wp != -1:
			var r := go(e, pi, cur, wp)
			if r != "next":
				return r
			x.erase("dest")
		var wst: int = e.pstate[e.holder[key.x]]
		if kind == "give" and wst != 7 and wst != 10:
			var other := false
			for h in e.lockers[key]:
				if not _same(h, pid):
					other = true
					break
			if not other:
				if not x.has("since"):
					x["since"] = e.step_no
				if e.step_no - x["since"] < HANDOVER_WAIT * tpm:
					return "wait"
				tried.append(key)       # nobody took it over: the lock stays on
				x.erase("pt")
				x.erase("since")
				continue
		var w: String = e.m.works[e.holder[key.x]]["id"]
		if kind == "take":
			e.npc_queue.append(["lock", w, key.y, pid])
		elif kind == "give":
			e.npc_queue.append(["unlock", w, key.y, pid])
		else:
			e.npc_queue.append(["remove_lock", w, key.y, pid, messages[s["remove_locks"]], cur.get("owner")])
		x["busy"] = true
		e.sp_result[pi] = null
		return "wait"
	return "wait"


func say(e, pi: int, msg: String, to: String) -> void:
	e._ev(["say", people[pi]["id"], msg, to])
	for k in e.st_players.size():
		var t: int = e.st_players[k]
		if t != -1 and t != pi and (to == people[t]["id"] or to == people[t]["role"]):
			e.st_acks[k] += 1


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
	if trainee and not x.has("seat"):       # their seat, as an NPC's (again after a pause, which lets it go)
		x["seat"] = true
		if x["place"] != -1 and not taken(e, x["place"], pi):
			reserve(e, pi, x["place"])
	if not trainee:
		var r := go(e, pi, cur, int(x["place"]))
		if r != "next":
			return r
		x.erase("dest")
	elif e.sp_pos[pi] != x["place"]:
		return "wait"
	if not x.has("meet_since") and not x.get("met", false):
		x["meet_since"] = e.step_no
	if not x.get("met", false):
		var rm: PackedInt32Array = rooms[mt["room"]]
		var all := true
		for r in mt["with"]:
			var found := false
			for qi in role_people.get(r, PackedInt32Array()):
				if qi != pi and e.sp_on[qi] and e.sp_pos[qi] != -1 and rm.has(e.sp_pos[qi]):
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
		if trainee:
			if e.sp_pos[pi] == x["place"]:
				x["left"] -= 1
			x["last"] = e.step_no
		else:
			_count(x, e.step_no)
	if x["left"] <= 0:
		return "next"
	if not trainee:
		e.sp_wake[pi] = e.step_no + x["left"]
	return "wait"


## An NPC's work or stay counted to step n: one step per step gone since the last count (the turns slept through),
## one only after a pause (time away doesn't count, as the reference's count one by one).
static func _count(x: Dictionary, n: int) -> void:
	if x.get("resumed", false):
		x["left"] -= 1
		x.erase("resumed")
	else:
		x["left"] -= n - x["last"]
	x["last"] = n


# ---------------------------------------------------------------- the trainee's person (§17.4)

## A player's person's turn (§17.4): tin, their slot's inputs of this step in the order made.
func trainee_turn(e, pi: int, tin: Array, slot: int) -> void:
	var used := []
	used.resize(tin.size())
	used.fill(false)
	var mine := _mine(e)
	drop_kept(e, mine, people[pi]["id"], slot)
	var took := {}
	trainee_steps(e, pi, tin, used, mine, took, slot)
	keep(e, pi, mine, took, slot)
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
					and callable.has(people[pi]["role"] + "\n" + item[1] + "\n" + item[2]) \
					and item[3] == null         # a request names no work: the called task's own, if any
			e._ev(["call", people[pi]["id"], item[1], item[2], item[3], "done" if ok else "refused"])
			if ok:
				assign(e, [item[1]], item[2], prio_of(item[2]), null, null, null, null)


func _mine(e) -> Array:
	var mine := []
	for k in range(e.ev_mark, e.events.size()):
		# not the events of an NPC's input applied after a slot took its person (§17.13)
		if e.events[k][0] == e.step_no and not e._npc_evs.has(k):
			mine.append(e.events[k])
	return mine


func trainee_steps(e, pi: int, tin: Array, used: Array, mine: Array, took: Dictionary, slot: int) -> void:
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
			if r != "fail" and e.sp_pos[pi] != -1 and e.sp_pos[pi] == x["dest"]:
				r = "next"
				if e.sp_res[pi] == e.sp_pos[pi]:
					e.sp_occ[pi] = e.sp_res[pi]
					e.sp_res[pi] = -1
		elif s.has("work"):
			if not x.has("left"):
				x["left"] = mins(e, pi, s["work"]) * tpm
				x["last"] = n
				x["place"] = e.sp_pos[pi] if e.sp_pos[pi] != -1 else null    # (no place: null, as an NPC's)
			elif x["last"] < n:
				if _same(e.sp_pos[pi] if e.sp_pos[pi] != -1 else null, x["place"]):
					x["left"] -= 1
				x["last"] = n
			r = "next" if x["left"] <= 0 else "wait"
		elif s.has("read"):
			for k in tin.size():
				var it: Array = tin[k]
				if not used[k] and it[0] == "read" and _same(it[1], s["read"]) and _is_num(it[2]):
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
				if not used[k] and it[0] == "say" and _same(it[1], s["say"]) and _same(it[2], s["to"]):
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
				if not used[k] and it[0] == "call" and _same(it[1], c["role"]) and _same(it[2], c["task"]):
					used[k] = true
					var w = c.get("work", "$")
					w = cur["work"] if w == "$" else w
					e._ev(["call", pid, c["role"], c["task"], w, "done"])
					offer(e, [c["role"]], c["task"], prio_of(c["task"]), null, w, cur["code"], cur["alarm"], w, null,
							vkey(cur))
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
			for j in mine.size():
				var y: Array = mine[j]
				# (a done op's code, do, where and person are text: what the trainee typed is compared only then)
				if not took.has(j) and y[1] == "op" and y.size() > 7 and y[4] == "done" and y[2] == o["kks"] \
						and y[3] == o["do"] and y[6] == o["where"] and y[7] == pid:
					took[j] = true
					r = "next"
					break
			if typeof(r) == TYPE_STRING and r == "wait" and _first_look(x) \
					and early_done(e, pi, cur, "op", [o["kks"], o["do"], o["where"]], o, slot):
				r = "next"
		elif s.has("permit"):
			var w = cur["work"] if s["permit"]["work"] == "$" else s["permit"]["work"]
			var a: String = s["permit"]["action"]
			for j in mine.size():
				var y: Array = mine[j]
				if not took.has(j) and y[1] == "permit" and y[5] == "done" and _same(y[2], w) and y[3] == a \
						and y[4] == pid:
					took[j] = true
					r = "next"
					break
			if typeof(r) == TYPE_STRING and r == "wait" and _first_look(x) \
					and early_done(e, pi, cur, "permit", [w, a], null, slot):
				r = "next"
		elif s.has("handover") and s["handover"] == "take":
			if lock_target(e, pi, cur, s, null).x == -1:
				r = "next"
		elif s.has("handover"):
			if not x.has("from"):
				x["from"] = e.step_no
			var shared := false
			var any_mine := false
			for key in e.lockers:
				var held: Array = e.lockers[key]
				if _has(held, pid):
					any_mine = true
					for h in held:
						if not _same(h, pid):
							shared = true
			if not shared and (not any_mine or e.step_no - x["from"] >= HANDOVER_WAIT * tpm):
				r = "next"
		elif s.has("remove_locks"):
			if lock_target(e, pi, cur, s, null).x == -1:
				r = "next"
		elif s.has("ppe"):
			var worn: int = e.sp_worn[pi]
			if typeof(s["ppe"]) == TYPE_STRING and s["ppe"] == "off":
				if worn == 0:
					r = "next"
			elif (_ppe_of(pi, s["ppe"]) & ~worn) == 0:
				r = "next"
		elif s.has("stop"):
			if cur["act"] == null or not ongoing(e, cur["act"]):
				r = "next"
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
				for j in mine.size():
					var y: Array = mine[j]
					if not took.has(j) and y[1] == k and y[5] == "done" and _same(y[2], w) and y[4] == pid \
							and pts.has(y[3]) and not got.has(y[3]):
						took[j] = true
						got.append(y[3])
				if not x.has("seen"):
					for pt in pts:
						if not got.has(pt) and early_done(e, pi, cur, k, [w, pt], null, slot):
							got.append(pt)
					x["seen"] = true
				if got.size() == pts.size():
					r = "next"
		if typeof(r) == TYPE_STRING and r == "wait":
			return
		advance(e, pi, r)


# ---------------------------------------------------------------- actions before their step (§17.8)

## The step is looked at for the first time (then marked): a kept action is taken only when it becomes current.
static func _first_look(x: Dictionary) -> bool:
	if x.has("seen"):
		return false
	x["seen"] = true
	return true


## A machine entered by a command or an action in this step: an earlier command of it no longer holds.
func drop_kept(e, mine: Array, me: String, slot: int) -> void:
	var moved := {}
	for y in mine:
		if y[1] == "machine" and y[5] != "next":
			moved[y[2]] = true
	# a point they locked again: an earlier unlock of theirs no longer holds
	var relocked := []
	for y in mine:
		if y[1] == "lock" and y[5] == "done" and _same(y[4], me):
			relocked.append([y[2], y[3]])
	if moved.is_empty() and relocked.is_empty():
		return
	var out := []
	for r in e.st_kept[slot]:
		if r[0] == "op" and r[5] != null and moved.has(r[5]):
			continue
		if r[0] == "unlock" and relocked.has([r[2], r[3]]):
			continue
		out.append(r)
	e.st_kept[slot] = out


## Their actions done in this step that no step of theirs took: kept for a step that becomes current later.
func keep(e, pi: int, mine: Array, took: Dictionary, slot: int) -> void:
	var pid: String = people[pi]["id"]
	var early: Array = e.st_kept[slot]
	for j in mine.size():
		var y: Array = mine[j]
		if took.has(j):
			continue
		var kind = y[1]
		if kind == "op":
			if y.size() > 7 and y[4] == "done" and _same(y[7], pid):
				var oc = e.op_entry(y[2], y[3], null)
				var mc = oc["o"].get("machine") if oc != null else null
				early.append(["op", y[0], y[2], y[3], y[6], mc])
		elif kind == "permit" or kind == "lock" or kind == "unlock":
			if y[5] == "done" and _same(y[4], pid):
				if kind == "permit":
					early.append(["permit", y[0], y[2], y[3], e.ptw.get(y[2])])
				else:
					early.append([kind, y[0], y[2], y[3]])
	if early.size() > EARLY_KEPT:
		e.st_kept[slot] = early.slice(early.size() - EARLY_KEPT)


## The earliest kept action of this kind that matches (op: code, do, where; permit: work, action; lock or unlock:
## work, point) and still holds is taken for the step: removed from the kept ones, with the event `early`.
func early_done(e, pi: int, cur: Dictionary, kind: String, want: Array, o, slot: int) -> bool:
	var early: Array = e.st_kept[slot]
	for k in early.size():
		var q: Array = early[k]
		if q[0] != kind:
			continue
		var ok := false
		if kind == "op":
			ok = q[2] == want[0] and q[3] == want[1] and q[4] == want[2] and _op_holds(e, o)
		elif kind == "permit":
			ok = _same(q[2], want[0]) and q[3] == want[1] and _permit_holds(e, want[0], want[1], q[4])
		else:
			ok = _same(q[2], want[0]) and q[3] == want[1] and _lock_holds(e, kind, want[0], want[1], pi)
		if ok:
			early.remove_at(k)
			e._ev(["early", people[pi]["id"], cur["task"], cur["step"], q[0], q[1]])
			return true
	return false


## An op's effect still holds: every state its `set` writes has that value, a `set` op's input the step's `value`
## (when the step names one), a reset's trip is not latched.
func _op_holds(e, o: Dictionary) -> bool:
	var c = e.op_entry(o["kks"], o["do"], o.get("trip"))
	if c == null:
		return false
	var sl: PackedInt32Array = c["set"][0]
	var sv: PackedFloat64Array = c["set"][1]
	for i in sl.size():
		if e.cur[sl[i]] != sv[i]:
			return false
	var op: Dictionary = c["o"]
	if op.has("input") and o.has("value") and e.cur[e.ix[op["input"]]] != float(o["value"]):
		return false
	if op["do"] == "reset" and not op.has("machine") and e.latched[c["ti"]] != 0:
		return false
	return true


## The same permit (its number) at the action's state or past it (1 to 9), or still cancelled.
func _permit_holds(e, w, action: String, num) -> bool:
	var wi: int = e.m.work_ix.get(w, -1) if typeof(w) == TYPE_STRING else -1
	if wi == -1 or not _same(e.ptw.get(w), num):
		return false
	var st: int = e.pstate[wi]
	var to: int = PERMIT_TO[action]
	return st == 10 if to == 10 else (to <= st and st <= 9)


## A lock still in place by them under that work; an unlocked point still unlocked.
func _lock_holds(e, kind: String, w, point: int, pi: int) -> bool:
	var wi: int = e.m.work_ix.get(w, -1) if typeof(w) == TYPE_STRING else -1
	var k: int = e._wk[wi][1] if wi != -1 else -1
	if k == -1:
		return false
	var key := Vector2i(k, point)
	var held: Array = e.lockers.get(key, [])
	if kind == "unlock":
		return not _has(held, people[pi]["id"])
	return _has(held, people[pi]["id"]) and e.holder[k] == wi


## Equal and of one type: what a trainee's input typed (any JSON value) is compared with text so (GDScript's == between
## an int and a String is an error, where Python's is False).
static func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


static func _is_num(x) -> bool:
	var t := typeof(x)
	if t == TYPE_INT:
		return absi(x) < 1000000000
	if t == TYPE_FLOAT:
		return is_finite(x) and absf(x) < 1e9
	return false


# ---------------------------------------------------------------- the snapshot's part (§17.7)

## `worn` ({person: their PPE items, in PPE's order} for those wearing any) and `acts` ([[person, kind, zone or work,
## start step, stopped], …] in person order, then kind) of the snapshot (§17.11).
func snap_acts(e) -> Array:
	var worn := {}
	var acts := []
	for pi in people.size():
		var w: int = e.sp_worn[pi]
		if w != 0:
			var items := []
			for k in PPE.size():
				if w & (1 << k):
					items.append(PPE[k])
			worn[people[pi]["id"]] = items
		for k in 3:
			var a = e.sp_acts[pi][k]
			if a != null:
				acts.append([people[pi]["id"], ACT_KINDS[k], a[0], a[1], a[2]])
	return [worn, acts]


func snap(e) -> Dictionary:
	var out := {}
	for pi in people.size():
		var where = null
		var leg: Array = e.sp_leg[pi]
		if not leg.is_empty():
			where = ["way", places[leg[0]]["id"], places[leg[1]]["id"], leg[2], leg[3]]
		elif has_lifts and e.sp_pos[pi] == -1 and not e.sp_ride[pi].is_empty():
			var rd: Array = e.sp_ride[pi]
			where = ["lift", lifts[rd[0]][0], places[rd[1]]["id"], places[rd[2]]["id"]]
		elif e.sp_pos[pi] != -1:
			where = places[e.sp_pos[pi]]["id"]
		var c = e.sp_cur[pi]
		out[people[pi]["id"]] = [where, c["task"] if c != null else null, c["step"] if c != null else null]
	return out
