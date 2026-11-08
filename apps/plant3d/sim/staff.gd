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

const Hands = preload("hands.gd")    # the hands-on engine's steps (REALISM.md §2.13)
const Hse = preload("hse.gd")        # JSAs and toolbox talks (REALISM.md §8.6)
const WorkOrders = preload("workorders.gd")    # work orders' steps and reactions (REALISM.md §2.20)

const DAY := 864000
const MINUTE := 600
const WAIT_PLACE := 15
const HANDOVER_WAIT := 60         # clock minutes an outgoing person waits at a lock for the incoming one's (§17.9)
const MAX_POINTS := 64 * 16       # every point of a model's isolations: a lock round's bound in a turn
const QUEUE_MAX := 32
const RIDE_WAIT := 1800           # steps a person waits for a lift before they take the stairs (§20.4)
const RIDE_QUIET := 50            # steps since the last board or alight before a rider closes a gate elsewhere
const RIDE_WAIT_MIN := 30         # clock minutes a person waits at a stop before walking instead (§21.4)
const EARLY_KEPT := 32           # the trainee's actions kept for a later step (§17.8)
const OPEN_KINDS := ["point", "door", "stop", "muster", "counter", "depot", "work"]
const PPE := ["helmet", "boots", "glasses", "gloves", "ear", "harness", "face_shield", "apron", "vest"]
const ACT_KINDS := ["ppe", "permit", "unsafe"]   # an unsafe act's kinds, in the order checked (§16.7, §17.11)
const NO_ACTS := [null, null, null]   # a person's sp_acts with no act going on (phase 5's count)
## and with staff.json's `audio` (REALISM.md §8.5) these two after them: music on in a banned zone, the phone carried
## in an Ex zone (kind indexes 3 and 4)
const AUDIO_KINDS := ["audio", "phone"]
const DRIVE_ACTIONS := ["wheel", "stop", "go", "auto"]     # a driver's drive input (§21.16)
const STATE_NAMES := ["none", "requested", "approved", "isolated", "issued", "accepted", "done", "returned",
		"deisolated", "closed", "cancelled"]
const PERMIT_TO := {"request": 1, "approve": 2, "issue": 4, "accept": 5, "done": 6, "return": 7, "close": 9,
		"cancel": 10}
const PERMIT_AUTH := {"request": "request", "approve": "approve", "issue": "issue", "accept": "accept",
		"done": "accept", "return": "accept", "close": "issue", "cancel": "approve"}

var error := ""
## Per-phase timers of step() (tests/bench_staff.gd, the gate walk's STAFF_PHASES): the engine's _staff_prof_on,
## _staff_prof (microseconds per PROF_NAMES[k]) and _staff_prof_n (the work done, machine-independent: task steps run in
## people's turns, the vehicles' runs due worked out, people whose acts were looked at in phase 5). On the engine, not
## here: this object is shared by an engine's clones, which a worker thread steps (the permit panel's lock check).
const PROF_NAMES := ["inputs", "duties", "react", "vehicles", "people", "acts", "after"]

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
var wait_key := PackedInt32Array()   # per place: its room's first place, or itself outside a room (_wake_at)
var work_at := {}                    # code -> its work place
var work_places := {}                # code -> every work place of it (a hand action's place, REALISM.md §2.15)
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
var has_slips := false               # a hand step has a slip (REALISM.md §2.13): the people's slip streams are kept
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
var has_homes := false               # every person has a home (§21.1)
var handovers := {}                  # task -> true: the tasks with a handover step (§21.2)
var home := PackedInt32Array()       # per person: their home's bed, -1
var off_site := PackedByteArray()    # per place: 1 when outside the plant's fence (§21.1)
var vehicles: Array = []             # {id, kind, seats, driver, home, runs: [{at, stops, dwell, days, lead}]} (§21.4)
var vehicle_ix := {}                 # vehicle id -> its index
var drive_no := PackedInt32Array()   # per place: its number among the stops and depots, -1
var drive_places := PackedInt32Array()   # the stops and depots, in place order
var drive_next: Array = []           # per drive number: PackedInt32Array of the next drive number to each, -1
# personal audio and the phone (REALISM.md §8.5), only with staff.json's `audio`
var has_audio := false
var kinds: Array = ACT_KINDS         # the act kinds: ACT_KINDS, with `audio` + AUDIO_KINDS
var nk := 3                          # their count
var no_acts: Array = NO_ACTS         # a person's sp_acts with no act going on
var audio_banned := 0                # the zones where music is an act, a bit per zone
var audio_ex := 0                    # the Ex zones, where carrying the phone is
var notice_lo := 0                   # `notice`: the clock minutes an observer takes, [lo, hi]
var notice_hi := 0
var audio_mask := 0                  # the volume from which calls are missed
var audio_rooms: Array = []          # `rooms` (the user, 2026-11-03): the rooms beyond the zones where music is banned
var place_aroom := PackedInt32Array()   # per place: its room's index in audio_rooms, or -1
const HELD_NEXT := 1 << 62           # a device taken off duty: held until the end of the next duty worked (§8.5)


static func load_from(m, doc: Dictionary):
	var s = new()
	s._build(m, doc)
	return s


func _fail(msg: String) -> void:
	if error == "":
		error = "staff.json: " + msg


## The reactions as the step reads them (PLANT3D §16.7, milestone AG2; ref/plant3d_staff.py expand_reactions): a
## permit reaction giving a work's task ("$isolate", "$deisolate", "$assign") stands for one reaction per work naming
## that task, in the works' order, with that work and its task; a reaction on a list of faults with "work": "$" for one
## per fault, in the list's order, with the work that repairs it. Every other reaction stands for itself, in order.
static func expand_reactions(rs: Array, works: Array) -> Array:
	var out := []
	for r: Dictionary in rs:
		var k: String = r["on"].keys()[0]
		var t = r["task"]
		if k == "permit" and typeof(t) == TYPE_STRING and String(t).begins_with("$"):
			var key := String(t).substr(1)
			for w: Dictionary in works:
				if w.has(key):
					var x := r.duplicate()
					x["task"] = w[key]
					x["work"] = w["id"]
					out.append(x)
		elif k == "fault" and r.get("work", null) is String and r["work"] == "$":
			for f in r["on"]["fault"]:
				for w: Dictionary in works:
					if w.get("repairs", null) == f:
						var x := r.duplicate()
						x["on"] = {"fault": f}
						x["work"] = w["id"]
						out.append(x)
						break
		else:
			out.append(r)
	return out


static func hhmm(x) -> int:
	var t: String = x
	return t.substr(0, 2).to_int() * 60 + t.substr(3, 2).to_int()


## A slot's `at` or `until`: [0 start / 1 end / 2 clock, minutes].
static func at_ref(x: String) -> Array:
	for k in [["start", 0], ["end", 1], ["prev", 3], ["next", 4]]:
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
		if p["kind"] == "work":
			if not work_places.has(p["kks"]):
				work_places[p["kks"]] = []
			work_places[p["kks"]].append(places.size() - 1)
		off_site.append(1 if p.get("off_site", false) == true else 0)
		drive_no.append(-1)
		if p["kind"] == "stop" or p["kind"] == "depot":
			drive_no[-1] = drive_places.size()
			drive_places.append(places.size() - 1)
	wait_key.resize(places.size())
	for i in places.size():
		wait_key[i] = rooms[room_of[i]][0] if room_of[i] != null else i
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
	var au = doc.get("audio")
	if au != null:                  # (REALISM.md §8.5)
		has_audio = true
		kinds = ACT_KINDS + AUDIO_KINDS
		nk = kinds.size()
		no_acts = []
		no_acts.resize(nk)
		for z in au["banned"]:
			audio_banned |= 1 << int(zone_ix[z])
		for z in au.get("ex", []):
			audio_ex |= 1 << int(zone_ix[z])
		notice_lo = int(au["notice"][0])
		notice_hi = int(au["notice"][1])
		audio_mask = int(au["mask"])
		audio_rooms = au.get("rooms", [])
	place_aroom.resize(places.size())
	for i in places.size():
		place_aroom[i] = audio_rooms.find(places[i].get("room", "")) if places[i].has("room") else -1
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
	var drive_adj: Array = []           # per drive number: [[drive number, steps]] (§21.4)
	for _k in drive_places.size():
		drive_adj.append([])
	for w in doc["ways"]:
		if not pix.has(w[0]) or not pix.has(w[1]) or not speeds.has(w[3]):
			_fail("a way joins no places: " + str(w))
			return
		var a: int = pix[w[0]]
		var b: int = pix[w[1]]
		var st := maxi(1, int(ceil(float(w[2]) * 10.0 / float(speeds[w[3]]) - 1e-9)))
		ways[mini(a, b) * np + maxi(a, b)] = st
		if w[3] == "drive":
			drive_adj[drive_no[a]].append([drive_no[b], st])
			drive_adj[drive_no[b]].append([drive_no[a], st])
			continue
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
	if not doc.get("vehicles", []).is_empty():
		for i in drive_places.size():   # a vehicle's routes, by §16.2's rule (§21.4): one search per place
			var paths := routes_from(drive_adj, i)
			var row := PackedInt32Array()
			for j in drive_places.size():
				row.append(paths[j][1] if i != j and paths[j] != null and paths[j].size() > 1 else -1)
			drive_next.append(row)
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
		for x in t["steps"]:
			if x.has("handover"):
				handovers[t["id"]] = true
			if x.has("slip"):
				has_slips = true
	for i in people.size():
		var p: Dictionary = people[i]
		post.append(str(p["role"]) + "\n" + str(p.get("routine", roles[p["role"]]["routine"])))
		home.append(-1)
		if p.has("home"):           # the home room's first bed (§21.1)
			has_homes = true
			for j in rooms.get(p["home"], PackedInt32Array()):
				if kind[j] == "bed":
					home[i] = j
					break
	for v in doc.get("vehicles", []):
		var runs := []
		for r in v["runs"]:
			var stops := PackedInt32Array()
			for x in r["stops"]:
				stops.append(pix[x])
			var lead_steps := drive_steps(pix[v["home"]], stops[0])
			runs.append({"at": hhmm(r["at"]), "stops": stops, "dwell": int(r["dwell"]), "days": r.get("days"),
					"lead": (lead_steps + tpm - 1) / tpm})
		vehicle_ix[v["id"]] = vehicles.size()
		vehicles.append({"id": v["id"], "kind": v["kind"], "seats": int(v["seats"]), "driver": v["driver"],
				"home": pix[v["home"]], "runs": runs})
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
	reactions = expand_reactions(doc.get("reactions", []), m.works)
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
			if s.has("go") and typeof(s["go"]) == TYPE_STRING and s["go"] != "home" and not pix.has(s["go"]):
				_fail("task %s: no place %s" % [t["id"], s["go"]])
			if s.has("wo") and (m.wo_ids == null or typeof(s["wo"]) != TYPE_DICTIONARY \
					or not WorkOrders.ACTIONS.has(s["wo"].get("action"))):
				_fail("task %s: a wo step the engine can't run (REALISM.md §2.20)" % t["id"])
			if s.has("unlock"):
				if not unlocks.has(t["id"]):
					unlocks[t["id"]] = {}
				unlocks[t["id"]][s["unlock"]["work"]] = true
	for r in reactions:
		if r["on"].has("wo") and (m.wo_ids == null or not WorkOrders.STATES.has(r["on"]["wo"])):
			_fail("a reaction on a work order the engine can't run (REALISM.md §2.20)")


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


## The quickest routes from src to every node by §16.2's rule (as route()'s, all at once): per node its points from
## src, or null when it is not reached.
static func routes_from(adj: Array, src: int) -> Array:
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
			return path
		done[u] = 1
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
	return path


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


## The next place on a vehicle's route from a to b (§21.4), -1 at b.
func drive_hop(a: int, b: int) -> int:
	if a == b:
		return -1
	return drive_places[drive_next[drive_no[a]][drive_no[b]]]


## The steps of a vehicle's route from a to b.
func drive_steps(a: int, b: int) -> int:
	var t := 0
	while a != b:
		var c := drive_hop(a, b)
		t += int(ways[mini(a, c) * places.size() + maxi(a, c)])
		a = c
	return t


func prio_of(tid: String) -> int:
	return int(tasks[tid].get("priority", 3))


## A person's routine: their own `routine` (§17.8), else their role's.
func routine_of(pi: int) -> Dictionary:
	var p: Dictionary = people[pi]
	return routines[p.get("routine", roles[p["role"]]["routine"])]


func off_idle_of(pi: int) -> String:
	return routines[roles[people[pi]["role"]]["off"]]["idle"]


## A vehicle standing at home, on no run (§21.4).
static func vehicle_home(v: Dictionary) -> Dictionary:
	return {"at": v["home"], "leg": [], "run": -1, "dep": 0, "k": 0, "to": v["home"], "until": 0, "driver": -1,
			"riders": [], "floor": 0, "done": []}


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
	e.sp_wait_on.resize(n)
	e.sp_wait_on.fill(-1)
	e.sp_worn.resize(n)
	e.sp_zin.resize(n)
	e.sp_lin.resize(n)
	e.sp_aboard.resize(n)
	e.sp_offday.resize(n)
	e.sp_music.resize(n)            # (REALISM.md §8.5: the music off, the phone carried; its streams: engine.gd)
	e.sp_phone.resize(n)
	e.sp_phone.fill(1)
	e.sp_held_to.resize(n)
	e.sp_held_to.fill(-1)
	e.sp_locker.resize(n)
	e.sp_locker.fill(-1)
	e.sp_told.resize(n)
	for i in n:
		e.sp_rng[i] = seed_of(seed, i)
		e.sp_acts.append(no_acts.duplicate())
		e.sp_watch.append({})
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
		e.sp_spans.append([])
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


## A duty begun (in phase 1, or a jump landing inside it): a device taken off duty is held until it ends (REALISM.md
## §8.5; the user, 2026-11-07: the next duty the person actually works, so not one of their roster that passed while
## they were absent or inside a jump's gap).
func duty_worked(e, pi: int) -> void:
	if has_audio and e.sp_phone[pi] == 2 and e.sp_held_to[pi] == HELD_NEXT:
		e.sp_held_to[pi] = e.sp_duty[pi][1]


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
		var lo: int = du[0]
		var hi: int = du[1]
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
		for x in mine:
			lo = mini(lo, x[0])
			hi = maxi(hi, x[0])
		if home[pi] != -1:          # its span (§21.2; only read with homes)
			e.sp_spans[pi].append([lo, hi, du[0], du[1]])
		slots.append_array(mine)
	if home[pi] != -1:
		for day in range(e.sp_offday[pi] + 1, upto):
			off_slots(e, pi, day)
		e.sp_offday[pi] = maxi(e.sp_offday[pi], upto - 1)
		var keep := []
		for x in e.sp_spans[pi]:
			if x[1] >= (upto - 4) * DAY:
				keep.append(x)
		e.sp_spans[pi] = keep
	slots.sort_custom(_slot_less)
	e.sp_planned[pi] = upto


## The off-duty slots of a day (§21.2): each candidate time on it within no duty's span.
func off_slots(e, pi: int, day: int) -> void:
	var ro: Dictionary = routines[roles[people[pi]["role"]]["off"]]
	var lo: int = day * DAY
	var hi: int = lo + DAY
	var wd: String = week[posmod(day - 1, 7)]
	var spans: Array = e.sp_spans[pi]
	for k in ro["slots"].size():
		var s: Array = ro["slots"][k]
		if s[6] != null and not s[6].has(wd):
			continue
		var ts := []
		if s[0] == 2:
			ts = [lo + s[1] * MINUTE]
		else:
			for x in spans:
				ts.append((x[3] if s[0] == 3 else x[2]) + s[1] * MINUTE)
		for t in ts:
			if t < lo or t >= hi:
				continue
			var inside := false
			for x in spans:
				if x[0] <= t and t <= x[1]:
					inside = true
					break
			if not inside:
				e.sp_slots[pi].append([t, lo, k, 0, s[5], null])


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
	e.sp_wait_on.fill(-1)           # (everyone awake: sp_wake 0 below)
	e.st_given = {}
	e.st_pending = []
	e.st_made = {}
	e.st_next1 = 0
	e.st_veh = []                   # every vehicle home, nobody aboard (§21.4)
	for v in vehicles:
		var vh := vehicle_home(v)
		vh["floor"] = c             # (a run whose leaving time is before the placement is not made)
		e.st_veh.append(vh)
	for pi in people.size():
		e.sp_aboard[pi] = -1
		e.sp_spans[pi] = []
		e.sp_offday[pi] = -1
		e.sp_worn[pi] = 0
		e.sp_zin[pi] = 0
		e.sp_acts[pi] = no_acts.duplicate()
		e.sp_told[pi] = 0
		e.sp_watch[pi] = {}
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
		if home[pi] != -1:          # planned from a day earlier: their off slots of days C − 1 and C (§21.2)
			e.sp_planned[pi] = day - 4
			e.sp_offday[pi] = day - 2
		if e._absent.has(pi):
			continue
		plan(e, pi, day + 1)
		for du in e.sp_duties[pi]:
			if du[0] <= c and c < du[1]:
				e.sp_on[pi] = 1
				e.sp_duty[pi] = du
				e.sp_worn[pi] = role_ppe[people[pi]["role"]]     # at work already: in their PPE (§17.11)
				duty_worked(e, pi)
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
		if duty.is_empty() and home[pi] != -1:
			# off duty with a home (§21.2): in a duty's span, its latest slot at or before C; else the latest off slot
			# at or before C after the last span's end
			var span = null
			for x in e.sp_spans[pi]:
				if x[0] <= c and c <= x[1]:
					span = x
					break
			if span != null:
				for s in e.sp_slots[pi]:    # (after the duty's end, only its slots after the end: §21.2)
					if s[0] <= c and s[5] != null and s[5][0] == span[2] and (c < span[3] or s[0] >= span[3]):
						pick = s
			else:
				var last := -1
				for x in e.sp_spans[pi]:
					if x[1] < c:
						last = maxi(last, x[1])
				for s in e.sp_slots[pi]:
					if last < s[0] and s[0] <= c and s[5] == null:
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
		if not e.sp_on[pi] and home[pi] == -1:
			continue
		var task = pick[4] if pick != null else null
		var place := first_place(e, task, pi) if task != null else -1
		if place == -1:
			place = first_place(e, idle_of(pi) if e.sp_on[pi] else off_idle_of(pi), pi)
		if place == -1:
			place = origin if e.sp_on[pi] else home[pi]
		e.sp_pos[pi] = place
		if not open[place] and not e.st_holder.has(place):
			e.st_holder[place] = pi
			e.sp_occ[pi] = place
		if task != null:
			give(e, pi, task, prio_of(task), null, null, null, null, false, null, null, null,
					(1 if pick[5] == null else 2) if home[pi] != -1 else 0, pick[5][1] if pick[5] != null else 0)
	e.st_t_from.fill(-1)


## A task's first place (§17.8): its first go's or meeting's (a sleep's: home; a ride's: its stop, §21).
func first_place(e, tid: String, pi: int) -> int:
	for s in tasks[tid]["steps"]:
		if s.has("sleep"):
			return home[pi]
		if s.has("ride"):
			return pix[s["ride"]["from"]]
		if s.has("go"):
			var x = s["go"]
			if typeof(x) == TYPE_STRING and x == "home":
				return home[pi]
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
		act = null, orig = null, off := 0, dend := 0) -> bool:
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
	if off == 1:
		inst["offr"] = true         # an off-duty slot's: ended when a duty starts (§21.2)
	elif off == 2:
		inst["dslot"] = dend        # a duty's slot's: its duty's end (dropped once home after it, §21.2)
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
		if e.sp_aboard[pi] == -1 and (c == null or c["idle"] or (c["prio"] > prio and c["int"])):
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
			and typeof(pw) == TYPE_STRING and e.m.work_ix.has(pw) and kept_state(e, src, pw) != -1:
		var ident: String = src if src != null else "call|%s|%s|%s" % ["/".join(role_list), tid, str(w)]
		for pd in e.st_pending:
			if pd[0] == ident:
				return
		e.st_pending.append([ident, src, role_list.duplicate(), tid, prio, w, code, pw, kept_state(e, src, pw)])


## Whether an offer's source is a reaction on a work order ("ri|wo|work", REALISM.md §2.21).
static func wo_src(src) -> bool:
	return typeof(src) == TYPE_STRING and src.get_slice_count("|") == 3 and src.get_slice("|", 1) == "wo"


## The state an offer nobody could take is kept at (§17.10): the permit's (1 to 8), or for a reaction on a work order
## (REALISM.md §2.21) the work order's (notified to complete); -1 when it isn't kept.
static func kept_state(e, src, pw: String) -> int:
	var s: int
	if wo_src(src):
		s = e.wo.get(pw, 0)
		return s if s >= 1 and s <= 5 else -1
	s = e.pstate[e.m.work_ix[pw]]
	return s if s >= 1 and s <= 8 else -1


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
	if not e.riders.is_empty():
		e.slot_rides_as(slot, people[pi]["id"])
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
	e.sp_music[pi] = 0                  # (an NPC plays no music, REALISM.md §8.5)
	var pid: String = people[pi]["id"]
	for vi in vehicles.size():          # a driver's wheel back to the engine (§21.16)
		if e.st_veh[vi]["driver"] == pi and e.st_veh[vi].has("wheel"):
			steer_auto(e, vi)
	for k in e.riders.size():           # a person aboard leaves the ride: their alight for the next step (§20.3)
		for r in e.riders[k]:
			if _same(r, pid):
				queue_alight(e, e.m.lifts[k]["id"], pid)
	# their work counted by the player's rule (§17.4: a step at a time) is an NPC's from now: its next count is one
	# step, not the steps since the player's last (a task paused while they were played, e.g. a driver taken into a
	# cab, §21.4; the reference counts an NPC's work turn by turn)
	for inst in e.sp_queue[pi] + e.sp_held[pi]:
		var st: Dictionary = inst["st"]
		if st.has("left") and st.has("last"):
			st["resumed"] = true
	var c = e.sp_cur[pi]
	if c != null:
		if not c["idle"]:
			pause(e, pi)
	if e.sp_pos[pi] == -1 and e.sp_aboard[pi] == -1 and e.st_t_from[slot] != -1:
		_put(e, pi, e.st_t_from[slot])
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
	var pr: bool = e._staff_prof_on
	var pt := Time.get_ticks_usec() if pr else 0
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
			elif item[0] == "get_on":   # (nobody to get on, §21.4)
				var ev := ["aboard", null, item[1], null, "refused", ["authority"]]
				if e.st_session:
					ev.append(slot)
				e._ev(ev)
			elif item[0] == "drive":    # (nobody to drive, §21.16)
				var ev := ["drive", null, item[1], item[2], drive_place(item), "refused", ["authority"]]
				if e.st_session:
					ev.append(slot)
				e._ev(ev)
			continue
		if (item[0] == "arrive" or item[0] == "leave") and e.sp_aboard[tr] != -1:
			continue                    # (ignored aboard a vehicle, §21.4)
		if item[0] == "get_on":
			t_get_on(e, tr, item[1])
		elif item[0] == "drive":
			t_drive(e, tr, slot, item)
		elif item[0] == "arrive" and typeof(item[1]) == TYPE_STRING and pix.has(item[1]):
			_put(e, tr, pix[item[1]])
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
		elif item[0] == "audio":
			t_audio(e, tr, item[1], slot)
		elif item[0] == "phone":
			t_phone(e, tr, item[1], slot)
	if pr:
		pt = _prof(e, 0, pt)
	# 1. duties, then slots
	var day: int = c / DAY
	var np := people.size()
	if c >= e.st_next1:
		_phase1(e, c, day)
	if pr:
		pt = _prof(e, 1, pt)
	# 2. reactions
	react(e, n)
	if pr:
		pt = _prof(e, 2, pt)
	# 3. vehicles (§21.4), not in a jump's step (as phase 4)
	if not jump_step:
		for vi in vehicles.size():
			vehicle_turn(e, vi)
	if pr:
		pt = _prof(e, 3, pt)
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
		var playing := false
		for p in players:
			playing = playing or p != -1
		# (read once, and again after each turn: a turn wakes others; a field of an untyped object is looked up by
		# name each time it is read)
		var wake: PackedInt64Array = e.sp_wake
		for pi in np:
			var slot: int = players.find(pi) if playing else -1
			if slot != -1:
				if not absent.has(pi):
					var mine_in := []
					for si in tin:
						if si[0] == slot:
							mine_in.append(si[1])
					trainee_turn(e, pi, mine_in, slot)
					wake = e.sp_wake
			elif n >= wake[pi] and not absent.has(pi):
				turn(e, pi)
				wake = e.sp_wake
	if pr:
		pt = _prof(e, 4, pt)
	# 5. unsafe acts, then the reactions to them
	var moved := false
	for k in range(e.ev_mark, e.events.size()):
		var x: Array = e.events[k]
		if x[0] == n and x[1] == "permit" and x[5] == "done":
			moved = true
			break
	act_phase(e, n, moved)
	findings(e, n)
	if pr:
		pt = _prof(e, 5, pt)
	_slots(e)
	var vprev: Array = e.st_vprev
	var vals: PackedFloat64Array = e.cur
	for j in value_reactions.size():
		vprev[value_reactions[j]] = vals[value_slot[j]] >= 0.5
	if pr:
		_prof(e, 6, pt)


func _prof(e, k: int, t0: int) -> int:
	var t := Time.get_ticks_usec()
	e._staff_prof[k] += t - t0
	return t


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
				_wake_at(e, e.sp_pos[pi])       # (one waiting for them at a meeting there)
				e._ev(["duty", people[pi]["id"], "on"])
				duty_worked(e, pi)
				if home[pi] != -1:      # the off-duty slots' tasks end: the duty comes first (§21.2)
					end_off(e, pi)
				var held: Array = e.sp_held[pi]  # the jobs held overnight come back (§17.10)
				e.sp_held[pi] = []
				for h in held:
					_enqueue(e, pi, h)
					e._ev(["task", people[pi]["id"], h["task"], "resumed"])
		if has_audio and e.sp_phone[pi] == 2 and c >= e.sp_held_to[pi]:
			# a device held is given back when the duty it was taken in (or, taken off duty, the next one worked)
			# ends (REALISM.md §8.5): by the clock
			e.sp_phone[pi] = 1
			e.sp_held_to[pi] = -1
			e._ev(["returned", people[pi]["id"]])
	for pi in np:
		if e._absent.has(pi):
			continue
		var sl: Array = e.sp_slots[pi]
		while not sl.is_empty() and sl[0][0] <= c:
			var s: Array = sl.pop_front()
			if home[pi] != -1 and s[5] != null:
				end_off(e, pi)              # (a duty's slot: its span has begun, §21.2)
			give(e, pi, s[4], prio_of(s[4]), null, null, null, null, true, null, null, null,
					(1 if s[5] == null else 2) if home[pi] != -1 else 0, s[5][1] if s[5] != null else 0)
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
		if has_audio and e.sp_phone[pi] == 2:
			nx = mini(nx, e.sp_held_to[pi])     # (a device given back, §8.5)
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
					and off_site_now(e, pi) and _left_locks(e, pi):
				now[pi] = true
				if not e.st_left.has(pi):
					gone.append(pi)
		e.st_left = now
	# permit offers that found nobody on duty: offered again when someone of their roles comes on, at each later
	# shift until taken, while the permit is still at its state then (§17.10); a work order's the same, while the work
	# order is (REALISM.md §2.21)
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
			var now_st: int = e.wo.get(pd[7], 0) if wo_src(pd[1]) else e.pstate[e.m.work_ix[pd[7]]]
			if now_st != pd[8] or (pd[1] != null and e.st_given.has(pd[1])) \
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
		if x[1] == "alarm" or x[1] == "trip" or x[1] == "fault" or x[1] == "permit" or x[1] == "wo":
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
				elif k == "wo" and x[1] == "wo" and x[5] == "done":     # REALISM.md §2.20
					var nw: int = x[6][0] if x[3] == "auto" else WorkOrders.ACTIONS[x[3]][1]
					if WorkOrders.STATES[nw] == v and (not r.has("work") or r["work"] == x[2]):
						hits.append(["wo|" + x[2], x[2], e.m.works[e.m.work_ix[x[2]]]["kks"], null])
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
			offer(e, r["roles"], r["task"], prio, key, w, code, h[3], h[1] if k == "permit" or k == "wo" else null,
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
	var work: bool = e.sp_on[pi] or (home[pi] != -1 and in_span(e, pi))  # (a duty's idle task within its span)
	if cur != null and cur["idle"] and (not q.is_empty() or (work if cur.get("off", false)
			else not work)):     # (a duty's idle task at the duty's end, an off one at its start, §21.2)
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
		if e.sp_pos[pi] == -1 and npc and home[pi] == -1:
			_put(e, pi, gate)
			e._ev(["move", pid, null, places[gate]["id"], e.step_no])
	if cur == null and (e.sp_on[pi] or home[pi] != -1):
		# the idle task: the duty's on duty, the off-duty routine's off duty with a home (§21.2)
		var idle := idle_of(pi) if work else off_idle_of(pi)
		cur = {"task": idle, "prio": 6, "made": e.step_no, "order": e.st_order, "step": 0, "st": {}, "work": null,
				"code": null, "alarm": null, "src": null, "idle": true, "started": true, "int": true, "owner": null,
				"act": null}
		if not work:
			cur["off"] = true
		e.sp_cur[pi] = cur
		e.st_order += 1
		e._ev(["task", pid, idle, "start"])
		if e.sp_pos[pi] == -1 and npc and home[pi] == -1:
			_put(e, pi, gate)
			e._ev(["move", pid, null, places[gate]["id"], e.step_no])
	if cur == null and not e.sp_on[pi] and e.sp_pos[pi] != -1 and npc and home[pi] == -1:
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
	e.sp_wait_on[pi] = -1   # (no longer waiting: a claim, a driver taken, a pre-emption)
	if st.get("hw", false):
		st.erase("hw")
		Hands.abandon(e, pi)    # pre-empted: their hand action abandoned (REALISM.md §2.13)
	unreserve(e, pi)
	_enqueue(e, pi, cur)
	e.sp_cur[pi] = null


func finish(e, pi: int, how: String) -> void:
	var cur: Dictionary = e.sp_cur[pi]
	_drop_hand(e, pi)
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
			_wake_at(e, r)
		e.sp_res[pi] = -1


func leave_place(e, pi: int) -> void:
	var o: int = e.sp_occ[pi]
	if o != -1:
		if e.st_holder.get(o, -1) == pi:
			e.st_holder.erase(o)
			_wake_at(e, o)
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
	if e.sp_wait_on[pi] != -1:
		e.sp_wait_on[pi] = -1       # (awake: no longer waiting on anything, _wake_at)
	if e.sp_aboard[pi] != -1:       # aboard a vehicle: no turn (§21.4); getting off wakes them
		e.sp_wake[pi] = 1 << 62
		return
	e._touched[pi] = 1
	var leg: Array = e.sp_leg[pi]
	if not leg.is_empty():
		if leg[3] > n:
			e.sp_wake[pi] = leg[3]
			return
		_put(e, pi, leg[1])
		e.sp_leg[pi] = []
		if e.sp_pos[pi] == e.sp_res[pi]:
			e.sp_occ[pi] = e.sp_pos[pi]
			e.sp_res[pi] = -1
		came(e, pi)
	if has_lifts and not e.sp_ride[pi].is_empty() and not ride_turn(e, pi):
		return
	for _k in 64:
		var cur = select(e, pi)
		if cur == null:
			e.sp_wake[pi] = 1 << 62     # nothing to do and off duty: until a task or a duty wakes them
			return
		var r = run(e, pi, cur)
		if e._staff_prof_on:
			e._staff_prof_n["runs"] += 1
		if typeof(r) == TYPE_STRING and r == "wait":
			if cur["idle"] and not cur.get("off", false) and not e.sp_on[pi] and home[pi] != -1:
				# a duty's idle task off duty within its span: awake when the span ends (the reference's select
				# looks at every turn, §21.2)
				var se := _span_end(e, pi)
				if se >= 0:
					e.sp_wake[pi] = mini(e.sp_wake[pi], _step_at(e, se + 1))
			elif cur["idle"] and cur.get("off", false) and home[pi] != -1 and e.sp_wake[pi] > n + 1:
				# the off-duty routine's idle task: awake when a span begins (select ends it then, §21.2)
				var ss := _span_next(e, pi)
				if ss >= 0:
					e.sp_wake[pi] = mini(e.sp_wake[pi], _step_at(e, ss))
			return
		advance(e, pi, r)


## A task step left while its hand action is under way (a stop, a failure, a task ended): the action is abandoned
## (REALISM.md §2.13).
func _drop_hand(e, pi: int) -> void:
	var c = e.sp_cur[pi]
	if c != null and c["st"].get("hw", false):
		c["st"].erase("hw")
		Hands.abandon(e, pi)


func advance(e, pi: int, r) -> void:
	var cur: Dictionary = e.sp_cur[pi]
	_drop_hand(e, pi)
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
	if typeof(x) == TYPE_STRING and x == "home":
		i = home[pi]
	elif typeof(x) == TYPE_STRING:
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


## Those asleep waiting for a place or for the others of a meeting in p's room (or at p outside a room) look again
## at their next turn (run(): go's wait for a place taken, meet's wait for the others): a place there was taken or let
## go, someone came there, or someone there came on duty. Waking one whose wait it doesn't end is harmless (their turn
## runs as every turn would, §0062); missing one is not, so every change those waits read calls this.
## A person comes to place p (every write of a place to sp_pos but place_all's, which wakes everyone: tests check it):
## those waiting in its room look again.
func _put(e, pi: int, p: int) -> void:
	if e.sp_pos[pi] != p:
		e.sp_pos[pi] = p
		_wake_at(e, p)


func _wake_at(e, p: int) -> void:
	if p < 0:
		return
	var key: int = wait_key[p]
	var on: PackedInt32Array = e.sp_wait_on
	var k := on.find(key)
	if k == -1:
		return
	while k != -1:
		on[k] = -1
		e.sp_wake[k] = 0
		if e._staff_prof_on:
			e._staff_prof_n["wakes"] += 1
		k = on.find(key, k + 1)
	e.sp_wait_on = on


func walk(e, pi: int, dest: int) -> bool:
	var pos: int = e.sp_pos[pi]
	if pos == dest:
		if e.sp_res[pi] == dest:        # already standing there: the place reserved is now held
			e.sp_occ[pi] = dest
			e.sp_res[pi] = -1
		if has_lifts and not e.sp_stairs[pi].is_empty():
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
	_wake_at(e, i)


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
		_put(e, pi, a)
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
			_put(e, pi, pts[c])
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
			and n >= e.lift_dwell[k] and _queued(q, "board", lid) == 0:
		# (not on someone boarding, nor while the cab stands for those it came for)
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
	if not _lift_made(e, code, do, value) and e._locking(code).is_empty():     # (not again; not on a locked code)
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
			if e._staff_wait_sleep and not e.st_players.has(pi):
				# nothing changes for them until their 15 minutes are over or a place in the room is let go or taken
				# (_wake_at), or a task, a duty or a stop wakes them, as any sleeper
				e.sp_wake[pi] = int(s["wait_since"]) + WAIT_PLACE * tpm
				e.sp_wait_on[pi] = wait_key[i]
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
	if s.has("sleep"):                  # home, lying there until T (§21.3)
		if not x.has("T"):
			x["T"] = sleep_until(e, pi, s["sleep"]["until"])
		var rs := go(e, pi, cur, home[pi])
		if rs != "next":
			return rs
		if e.clock() >= x["T"]:
			return "next"
		e.sp_wake[pi] = _step_at(e, x["T"])
		return "wait"
	if s.has("ride"):                   # to the stop, on a vehicle or on foot after 30 minutes (§21.4)
		var fr: int = pix[s["ride"]["from"]]
		var to: int = pix[s["ride"]["to"]]
		if x.get("walk", false):
			return go(e, pi, cur, to)
		if e.sp_pos[pi] == to:
			return "next"
		if not x.has("since"):
			var rg := go(e, pi, cur, fr)
			if rg != "next":
				return rg
			for k in ["dest", "target", "waiting", "wait_since"]:
				x.erase(k)
			x["since"] = n
		for vi in vehicles.size():
			if stands_for(e, vi, fr, to) and e.st_veh[vi]["riders"].size() < int(vehicles[vi]["seats"]):
				get_on(e, pi, vi, to)
				return "wait"
		if n - int(x["since"]) >= RIDE_WAIT_MIN * tpm:
			x["walk"] = true
			return go(e, pi, cur, to)
		# nothing changes for them until the wait is over, a vehicle comes to stand at the stop (arrived() wakes
		# them) or a task, a duty or a stop wakes them, as for any sleeper
		e.sp_wake[pi] = int(x["since"]) + RIDE_WAIT_MIN * tpm
		return "wait"
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
	if s.has("read") and s.has("via"):     # through a meter (REALISM.md §2.5, §2.13): without the tool, to `else`
		var code: String = s["read"]
		if not Hands.can_read(e, pid, s["via"]):
			e._ev(["read", pid, code, null, "tool"])
			return "fail"
		var val: float = Hands.shown(e, s["via"], e.prev)
		var ex = s.get("expect")
		var ok: bool = ex == null or (ex[0] <= val and val <= ex[1])
		e._ev(["read", pid, code, val, "ok" if ok else "out_of_range"])
		return "next"
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
		miss_call(e, pi, c["task"], c["role"])
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
	if s.has("op") or s.has("permit") or s.has("jsa") or s.has("talk") or s.has("wo"):
		if not x.get("busy", false):
			if s.has("op"):
				var o: Dictionary = s["op"]
				e.npc_queue.append(["op", o["kks"], o["do"], o.get("value"), o.get("trip"), o["where"], pid])
			elif s.has("jsa") or s.has("talk"):
				# REALISM.md §8.6: an NPC's JSA is the work's own list, its talk's points the job's hazards
				var k := "jsa" if s.has("jsa") else "talk"
				var w = cur["work"] if s[k] == "$" else s[k]
				var own: Array = Hse.own(e, w)
				if k == "jsa":
					e.npc_queue.append(["jsa", w, own[0], own[1], pid])
				else:
					e.npc_queue.append(["talk", w, own[0], pid])
			elif s.has("wo"):           # a work order's action (REALISM.md §2.20): without data, the defaults in step 1
				var w = cur["work"] if s["wo"]["work"] == "$" else s["wo"]["work"]
				var dd = s["wo"].get("data")
				e.npc_queue.append(["wo", w, s["wo"]["action"], pid, dd.duplicate() if dd != null else null])
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
	if s.has("hand"):                   # REALISM.md §2.13: the input for step 1, then its end
		var r = null
		if x.get("hw", false):
			if e.sp_result[pi] == null:
				return "wait"
			r = e.sp_result[pi]
			e.sp_result[pi] = null
			x["hw"] = false
		else:
			if not x.get("busy", false):
				# at the code's work place, as a lock step at its point's (REALISM.md §2.15)
				var r0 := go(e, pi, cur, work_at[s["kks"]])
				if r0 != "next":
					return r0
				x.erase("dest")
				e.npc_queue.append(["hand", s["kks"], s["hand"], s.get("tool"), s.get("value"), pid])
				x["busy"] = true
				e.sp_result[pi] = null
				return "wait"
			if e.sp_result[pi] == null:
				return "wait"
			r = e.sp_result[pi]
			e.sp_result[pi] = null
			x["busy"] = false
			if r == "start":
				x["hw"] = true
				return "wait"
		if r != "done":
			return "fail"
		if s.has("slip"):
			Hands.slip_draw(e, pid, cur, s)
		return "next"
	if s.has("tool"):                   # REALISM.md §2.13: in step 9, as ppe; the first refusal to `else`
		var off: bool = typeof(s["tool"]) == TYPE_STRING
		var have: Array = e.carried.get(pid, [])
		var items := []
		if off:
			items = have.duplicate()
		else:
			for t in s["tool"]:
				if not have.has(t):
					items.append(t)
		for t in items:
			if Hands.tool(e, t, pid, 0 if off else 1, true) != "done":
				return "fail"
		return "next"
	push_error("staff: no step kind in " + str(s))
	return "next"


## A sleep's time T (§21.3): HH:MM's first occurrence at or after the clock; next-H:MM from the next duty not yet
## begun (the clock when none is planned).
func sleep_until(e, pi: int, u: String) -> int:
	var c: int = e.clock()
	if is_hhmm(u):
		var t: int = (c / DAY) * DAY + hhmm(u) * MINUTE
		return t if t >= c else t + DAY
	var hm := u.substr(5).split(":")
	var dl: Array = e.sp_duties[pi]
	if dl.is_empty():
		return c
	return int(dl[0][0]) - (hm[0].to_int() * 60 + hm[1].to_int()) * MINUTE


## The first step whose clock reaches t (§16.1), under the jumps made so far.
static func _step_at(e, t: int) -> int:
	var d: int = t - e._S - e.J
	return (d + e._ds - 1) / e._ds if d > 0 else 0


## The end of the span the clock lies in, -1 for none.
func _span_end(e, pi: int) -> int:
	var c: int = e.clock()
	for x in e.sp_spans[pi]:
		if x[0] <= c and c <= x[1]:
			return x[1]
	return -1


## The start of the person's next span after the clock, -1 for none.
func _span_next(e, pi: int) -> int:
	var c: int = e.clock()
	var best := -1
	for x in e.sp_spans[pi]:
		if x[0] > c and (best == -1 or x[0] < best):
			best = x[0]
	return best


## The clock lies within one of the person's duties' spans (§21.2).
func in_span(e, pi: int) -> bool:
	var c: int = e.clock()
	for x in e.sp_spans[pi]:
		if x[0] <= c and c <= x[1]:
			return true
	return false


## The tasks off-duty slots made end `skipped`, the current one first, then the queue's in order (§21.2).
func end_off(e, pi: int) -> void:
	var cc = e.sp_cur[pi]
	if cc != null and cc.get("offr", false):
		finish(e, pi, "skipped")
		e.sp_wake[pi] = 0
	var kq := []
	for q in e.sp_queue[pi]:
		if q.get("offr", false):
			e._ev(["task", people[pi]["id"], q["task"], "skipped"])
			release(e, q)
		else:
			kq.append(q)
	e.sp_queue[pi] = kq


## An NPC with a home off duty who comes to an off-site place leaves their PPE behind (§21.1).
func came(e, pi: int) -> void:
	var p: int = e.sp_pos[pi]
	if home[pi] != -1 and not e.sp_on[pi] and p != -1 and off_site[p] and e.slot_of(pi) == -1:
		e.sp_worn[pi] = 0
		# the duty's slots' tasks still queued end there: nobody walks back for them (§21.2); a handover's and a job
		# held for the next duty stay
		var kq := []
		for q in e.sp_queue[pi]:
			if q.has("dslot") and int(q["dslot"]) <= e.clock() and tasks[q["task"]].get("resume", "") != "next_duty" \
					and not handovers.has(q["task"]):
				e._ev(["task", people[pi]["id"], q["task"], "skipped"])
				release(e, q)
			else:
				kq.append(q)
		if kq.size() != e.sp_queue[pi].size():
			e.sp_queue[pi] = kq


## Off site (§17.9): without homes, no place and no way; with them, §21.1's rule.
func off_site_now(e, pi: int) -> bool:
	if home[pi] == -1:
		return e.sp_pos[pi] == -1 and e.sp_leg[pi].is_empty()
	var vi: int = e.sp_aboard[pi]
	if vi != -1:
		var vh: Dictionary = e.st_veh[vi]
		if not vh["leg"].is_empty():
			return off_site[vh["leg"][0]] == 1 and off_site[vh["leg"][1]] == 1
		if vh["at"] == -1:              # steered, on the road (§21.16): as on a way from where it came to its target
			return off_site[vh["from"]] == 1 and off_site[vh["to"]] == 1
		return off_site[vh["at"]] == 1
	var leg: Array = e.sp_leg[pi]
	if not leg.is_empty():
		return off_site[leg[0]] == 1 and off_site[leg[1]] == 1
	var p: int = e.sp_pos[pi]
	return (not has_lifts or e.sp_ride[pi].is_empty()) and p != -1 and off_site[p] == 1


# ---------------------------------------------------------------- vehicles (§21.4)

## Vehicle vi stands at fr (arrived, not departed) on a run whose later stops include to.
func stands_for(e, vi: int, fr: int, to: int) -> bool:
	var vh: Dictionary = e.st_veh[vi]
	if vh["run"] == -1 or not vh["leg"].is_empty() or vh["at"] != fr:
		return false
	var stops: PackedInt32Array = vehicles[vi]["runs"][vh["run"]]["stops"]
	var k: int = vh["k"]
	if k >= stops.size() or stops[k] != fr:
		return false
	for j in range(k + 1, stops.size()):
		if stops[j] == to:
			return true
	return false


## A session run's events of a player's person carry the slot (§21.4, as §20.3's).
func _tail(e, pi: int) -> Array:
	if not e.st_session:
		return []
	var k: int = e.slot_of(pi)
	return [k] if k != -1 else []


func get_on(e, pi: int, vi: int, to: int) -> void:
	var ev := ["aboard", people[pi]["id"], vehicles[vi]["id"], places[e.sp_pos[pi]]["id"], "on", []]
	ev.append_array(_tail(e, pi))
	e._ev(ev)
	leave_place(e, pi)
	e.sp_pos[pi] = -1
	e.sp_aboard[pi] = vi
	e.st_veh[vi]["riders"].append([pi, to])
	e._touched[pi] = 1


func get_off(e, pi: int, vi: int, at: int) -> void:
	var ev := ["aboard", people[pi]["id"], vehicles[vi]["id"], places[at]["id"], "off", []]
	ev.append_array(_tail(e, pi))
	e._ev(ev)
	e.sp_aboard[pi] = -1
	_put(e, pi, at)
	e.sp_wake[pi] = 0
	e._touched[pi] = 1
	came(e, pi)


## The vehicle's next run to look at, [L, run index, D], or []: the runs in the order (L, index) over the days, after
## the last one looked at and not before the placement.
func runs_due(e, vi: int, c: int) -> Array:
	var v: Dictionary = vehicles[vi]
	var vh: Dictionary = e.st_veh[vi]
	var day: int = c / DAY
	var done: Array = vh["done"]
	# the answer depends only on the day, the floor and the last run made: kept for the next step with the same
	# (the engine's _staff_due_memo, a cache, not the run's state: a clone starts without it)
	var dm: Array = e._staff_due_memo
	if dm.size() != vehicles.size():
		dm.resize(vehicles.size())
	var memo = dm[vi]
	if memo != null and memo[0] == day and memo[1] == vh["floor"] and memo[2] == done:
		return memo[3]
	var best := _runs_due(v, vh, day, done)
	if e._staff_prof_on:
		e._staff_prof_n["due"] += 1
	dm[vi] = [day, vh["floor"], done.duplicate(), best]
	return best


func _runs_due(v: Dictionary, vh: Dictionary, day: int, done: Array) -> Array:
	var best := []
	for d in [day - 1, day, day + 1]:
		var wd: String = week[posmod(d - 1, 7)]
		for k in v["runs"].size():
			var r: Dictionary = v["runs"][k]
			if r["days"] != null and not r["days"].has(wd):
				continue
			var dd: int = (d * 1440 + int(r["at"])) * MINUTE
			var l: int = dd - int(r["lead"]) * MINUTE
			if l < vh["floor"]:
				continue
			if not done.is_empty() and (l < done[0] or (l == done[0] and k <= done[1])):
				continue
			if best.is_empty() or l < best[0] or (l == best[0] and k < best[1]):
				best = [l, k, dd]
	return best


## The vehicle drives on towards its target: the next way of its route, or there.
func drive_on(e, vi: int) -> void:
	var vh: Dictionary = e.st_veh[vi]
	if vh["at"] == vh["to"]:
		arrived(e, vi)
		return
	var a: int = vh["at"]
	var nx := drive_hop(a, vh["to"])
	var n: int = e.step_no
	vh["leg"] = [a, nx, n, n + int(ways[mini(a, nx) * places.size() + maxi(a, nx)])]
	vh["at"] = -1


## The vehicle is at its target: a stop of its run (event, people off, its stand) or home (the driver off).
func arrived(e, vi: int) -> void:
	var vh: Dictionary = e.st_veh[vi]
	var v: Dictionary = vehicles[vi]
	var n: int = e.step_no
	var at: int = vh["at"]
	_wake_riders(e, at)
	var r: Dictionary = v["runs"][vh["run"]]
	var stops: PackedInt32Array = r["stops"]
	e._ev(["vehicle", v["id"], places[at]["id"], "arrive"])
	if vh["k"] >= stops.size():         # home: the driver gets off at the depot
		get_off(e, vh["driver"], vi, at)
		vh["run"] = -1
		vh["driver"] = -1
		vh["dep"] = 0
		vh["k"] = 0
		vh["until"] = 0
		vh["riders"] = []
		vh.erase("wheel")               # (the wheel the engine's again, §21.16)
		vh.erase("from")
		return
	var last: bool = vh["k"] == stops.size() - 1
	var stay := []
	for rd in vh["riders"]:
		if last or rd[1] == at:
			get_off(e, rd[0], vi, at)
		else:
			stay.append(rd)
	vh["riders"] = stay
	if vh["k"] == 0 or last:
		vh["until"] = n + 1
	else:
		vh["until"] = n + maxi(1, int(r["dwell"]) * tpm)


## The people waiting at the stop at for a ride (asleep until their wait is over, run()) look again: a vehicle stands
## there now.
func _wake_riders(e, at: int) -> void:
	var pos: PackedInt32Array = e.sp_pos
	for pi in pos.size():
		if pos[pi] == at and e.sp_cur[pi] != null:
			var cur: Dictionary = e.sp_cur[pi]
			if tasks[cur["task"]]["steps"][cur["step"]].has("ride"):     # (an idle task's ride too)
				e.sp_wake[pi] = 0


## Phase 3 for one vehicle: an arrival, a departure, then the runs due (§21.4).
func vehicle_turn(e, vi: int) -> void:
	var vh: Dictionary = e.st_veh[vi]
	var v: Dictionary = vehicles[vi]
	var n: int = e.step_no
	var c: int = e.clock()
	if not vh["leg"].is_empty() and vh["leg"][3] <= n:
		vh["at"] = vh["leg"][1]
		vh["leg"] = []
		drive_on(e, vi)
	if not vh.has("wheel") and vh["run"] != -1 and vh["leg"].is_empty() and vh["at"] == vh["to"] and n >= vh["until"] \
			and (vh["k"] != 0 or c >= vh["dep"]) and vh["k"] < v["runs"][vh["run"]]["stops"].size():
		e._ev(["vehicle", v["id"], places[vh["at"]]["id"], "depart"])
		var stops: PackedInt32Array = v["runs"][vh["run"]]["stops"]
		vh["k"] += 1
		vh["to"] = stops[vh["k"]] if vh["k"] < stops.size() else v["home"]
		drive_on(e, vi)
	while true:
		var due := runs_due(e, vi, c)
		if due.is_empty() or due[0] > c:
			break
		vh["done"] = [due[0], due[1]]
		var stops: PackedInt32Array = v["runs"][due[1]]["stops"]
		var q := -1
		if vh["run"] == -1:
			var player := -1                # (NPCs first)
			for pi in role_people.get(v["driver"], PackedInt32Array()):
				if e.sp_on[pi] and not e._absent.has(pi) and e.sp_aboard[pi] == -1 \
						and (not has_lifts or e.sp_ride[pi].is_empty()) and not _in_cab(e, pi):
					if e.slot_of(pi) == -1:
						q = pi
						break
					if player == -1:
						player = pi
			if q == -1:
				q = player
		if q == -1:
			e._ev(["vehicle", v["id"], places[stops[0]]["id"], "skipped"])
			continue
		vh["run"] = due[1]
		vh["dep"] = due[2]
		vh["k"] = 0
		vh["to"] = stops[0]
		vh["driver"] = q
		vh["riders"] = []
		take_driver(e, q, vi)
		e._ev(["vehicle", v["id"], places[vh["at"]]["id"], "depart"])
		drive_on(e, vi)


## The driver gets on at the vehicle's home, taken from where they are (§21.4).
func take_driver(e, pi: int, vi: int) -> void:
	var at: int = e.sp_pos[pi]
	var ev := ["aboard", people[pi]["id"], vehicles[vi]["id"], places[at]["id"] if at != -1 else null, "on", []]
	ev.append_array(_tail(e, pi))
	e._ev(ev)
	if has_audio and e.sp_music[pi] > 0:    # a player's music off at the wheel (REALISM.md §8.5: no headsets driving)
		e.sp_music[pi] = 0
		var ea := ["audio", people[pi]["id"], 0, "done", ["driving"]]
		ea.append_array(_tail(e, pi))
		e._ev(ea)
	e.sp_leg[pi] = []
	if has_lifts:
		e.sp_stairs[pi] = PackedInt32Array()
	leave_place(e, pi)
	unreserve(e, pi)
	e.sp_pos[pi] = -1
	e.sp_aboard[pi] = vi
	e._touched[pi] = 1
	var cur = e.sp_cur[pi]
	if cur != null:
		if cur["idle"]:
			e._ev(["task", people[pi]["id"], cur["task"], "done"])
			e.sp_cur[pi] = null
		else:
			cur["st"].erase("busy")
			e.sp_result[pi] = null
			pause(e, pi)


## Whether a person is among any lift's riders (§20.3).
func _in_cab(e, pi: int) -> bool:
	var pid: String = people[pi]["id"]
	for x in e.riders:
		for r in x:
			if _same(r, pid):
				return true
	return false


## A player's get_on (§21.4): the first reason refusing it, else they are aboard.
func t_get_on(e, ti: int, vid) -> void:
	var vi: int = vehicle_ix.get(vid, -1) if typeof(vid) == TYPE_STRING else -1
	var cur = e.sp_cur[ti]
	var s: Dictionary = tasks[cur["task"]]["steps"][cur["step"]] if cur != null else {}
	var why := ""
	var p: int = e.sp_pos[ti]
	if vi == -1:
		why = "unknown"
	elif e.sp_aboard[ti] != -1 or _in_cab(e, ti):
		why = "aboard"                  # (on a vehicle or in a lift's cab)
	elif not s.has("ride"):
		why = "no_ride"
	elif p != pix[s["ride"]["from"]] or not stands_for(e, vi, p, pix[s["ride"]["to"]]):
		why = "not_at_stop"
	elif e.st_veh[vi]["riders"].size() >= int(vehicles[vi]["seats"]):
		why = "full"
	if why != "":
		var ev := ["aboard", people[ti]["id"], vid, places[p]["id"] if p != -1 else null, "refused", [why]]
		ev.append_array(_tail(e, ti))
		e._ev(ev)
		return
	get_on(e, ti, vi, pix[s["ride"]["to"]])


## A drive input's place for its event: a stop's place as given when it is text, else null (§21.16).
static func drive_place(item: Array):
	return item[3] if item.size() > 3 and typeof(item[2]) == TYPE_STRING and item[2] == "stop" \
			and typeof(item[3]) == TYPE_STRING else null


## Place b is a stop or depot a vehicle at a reaches over drive ways.
func drive_reaches(a: int, b: int) -> bool:
	if drive_no[b] == -1:
		return false
	return a == b or drive_next[drive_no[a]][drive_no[b]] >= 0


## A player's drive (§21.16): ["drive", vehicle, action] or ["drive", vehicle, "stop", place]. The first reason
## refusing it, else done and its effect.
func t_drive(e, ti: int, slot: int, item: Array) -> void:
	var vid = item[1]
	var action = item[2]
	var pl = item[3] if item.size() > 3 else null
	var vi: int = vehicle_ix.get(vid, -1) if typeof(vid) == TYPE_STRING else -1
	var at: int = pix.get(pl, -1) if typeof(pl) == TYPE_STRING else -1
	var vh: Dictionary = e.st_veh[vi] if vi != -1 else {}
	var why := ""
	if vi == -1 or typeof(action) != TYPE_STRING or not DRIVE_ACTIONS.has(action) \
			or action == "stop" and (at == -1 or not drive_reaches(vehicles[vi]["home"], at)):
		why = "unknown"
	elif vh["run"] == -1 or vh["driver"] != ti:
		why = "not_driver"
	elif action == "wheel" and vh.has("wheel"):
		why = "steering"
	elif action != "wheel" and not vh.has("wheel"):
		why = "no_wheel"
	elif action == "stop" and vh["at"] != -1:
		why = "standing"
	elif action == "go" and vh["at"] == -1:
		why = "moving"
	var ev := ["drive", people[ti]["id"], vid, action, drive_place(item), "refused" if why != "" else "done",
			[why] if why != "" else []]
	ev.append_array(_tail(e, ti))
	e._ev(ev)
	if why != "":
		return
	if action == "wheel":
		vh["wheel"] = slot
		if not vh["leg"].is_empty():        # off its way where it is: on the road, from the way's start
			vh["from"] = vh["leg"][0]
			vh["leg"] = []
		else:
			vh["from"] = vh["at"]
	elif action == "stop":
		steer_stop(e, vi, at)
	elif action == "go":
		steer_go(e, vi)
	else:
		steer_auto(e, vi)


## The steered vehicle stands at place at: it arrives at its next target, passes the run's stops before a later one it
## stops at, or stands anywhere else (§21.16).
func steer_stop(e, vi: int, at: int) -> void:
	var vh: Dictionary = e.st_veh[vi]
	var v: Dictionary = vehicles[vi]
	var stops: PackedInt32Array = v["runs"][vh["run"]]["stops"]
	vh["at"] = at
	vh["from"] = at
	if at == vh["to"]:
		arrived(e, vi)
		return
	var j := -1
	for k in range(vh["k"], stops.size()):
		if stops[k] == at:
			j = k
			break
	if j == -1:
		e._ev(["vehicle", v["id"], places[at]["id"], "stand"])
		return
	for k in range(vh["k"], j):
		e._ev(["vehicle", v["id"], places[stops[k]]["id"], "passed"])
	vh["k"] = j
	vh["to"] = at
	arrived(e, vi)


## The steered vehicle sets off from where it stands: on to its run's next stop from one it arrived at (§21.16).
func steer_go(e, vi: int) -> void:
	var vh: Dictionary = e.st_veh[vi]
	var v: Dictionary = vehicles[vi]
	e._ev(["vehicle", v["id"], places[vh["at"]]["id"], "depart"])
	if vh["at"] == vh["to"]:
		var stops: PackedInt32Array = v["runs"][vh["run"]]["stops"]
		vh["k"] += 1
		vh["to"] = stops[vh["k"]] if vh["k"] < stops.size() else v["home"]
	vh["from"] = vh["at"]
	vh["at"] = -1


## The engine drives the vehicle again (§21.16): on the road from the place it came from, now; standing at a stop it
## arrived at, by §21.4's departure rule; standing elsewhere, on to its target now.
func steer_auto(e, vi: int) -> void:
	var vh: Dictionary = e.st_veh[vi]
	vh.erase("wheel")
	var fr: int = vh["from"]
	vh.erase("from")
	if vh["at"] == -1:
		vh["at"] = fr
		drive_on(e, vi)
	elif vh["at"] != vh["to"]:
		drive_on(e, vi)


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
	if e.sp_aboard[pi] != -1:           # aboard a vehicle: in no zone, a player too (§21.4)
		return 0
	if e.st_players.has(pi):
		return e.sp_zin[pi]
	var leg: Array = e.sp_leg[pi]
	if not leg.is_empty():
		return place_zm[leg[0]] & place_zm[leg[1]]
	var p: int = e.sp_pos[pi]
	if p == -1 and has_lifts and not e.sp_ride[pi].is_empty():     # aboard: as on a way between the landings
		return place_zm[e.sp_ride[pi][1]] & place_zm[e.sp_ride[pi][2]]
	return place_zm[p] if p != -1 else 0


## The room of `audio.rooms` person pi is in (REALISM.md §8.5: music banned there beyond the zones), as its index, or
## -1: at a place of it; on a way, when both its ends are in it; a player at the place they arrived at; aboard in none.
func audio_room(e, pi: int) -> int:
	if audio_rooms.is_empty() or e.sp_aboard[pi] != -1:
		return -1
	if not e.st_players.has(pi):
		var leg: Array = e.sp_leg[pi]
		if not leg.is_empty():
			var r: int = place_aroom[leg[0]]
			return r if r == place_aroom[leg[1]] else -1
	var p: int = e.sp_pos[pi]
	return place_aroom[p] if p != -1 else -1


## Whether person qi is where a person's music or phone can be seen (§8.5): a zone of zs (theirs), or their banned
## room (room, -1 for none).
func shares(e, zs: int, room: int, qi: int) -> bool:
	return (zs & zones_of(e, qi)) != 0 or (room != -1 and audio_room(e, qi) == room)


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
	if k >= 3:          # a player's music in a banned zone, their phone in an Ex zone (REALISM.md §8.5)
		if (e.sp_music[pi] > 0 if k == 3 else e.sp_phone[pi] == 1) and e.st_players.has(pi):
			var zm := zones_of(e, pi) & (audio_banned if k == 3 else audio_ex)
			if zm != 0:
				for z in zone_ids.size():
					if zm & (1 << z):
						return [zone_ids[z]]
			if k == 3:      # beyond the zones: a banned room (the control room), the room its detail
				var r := audio_room(e, pi)
				if r != -1:
					return [audio_rooms[r]]
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
	if has_audio:               # the observers' times kept for acts not going on (REALISM.md §8.5): before any acts
		var ws: Array = e.sp_watch  # change (a person's pruning reads only their acts and everyone's duty and zones)
		if ws.count({}) != ws.size():
			for qi in ws.size():
				if not ws[qi].is_empty() and not absent.has(qi):
					prune_watch(e, qi)
	var look: PackedByteArray = e._touched     # the people to look at: found natively (a copy: the players added)
	var players: PackedInt32Array = e.st_players
	if not players.is_empty():
		look = look.duplicate()
		for p in players:
			if p >= 0:
				look[p] = 1
	var np := people.size()
	var pi := -1
	while true:
		if permit_moved:
			pi += 1
			if pi >= np:
				break
		else:
			pi = look.find(1, pi + 1)
			if pi == -1:
				break
		if absent.has(pi):
			continue
		if e._staff_prof_on:
			e._staff_prof_n["acts"] += 1
		var acts: Array = e.sp_acts[pi]
		for k in nk:
			var now := _act_now(e, pi, k)
			var a = acts[k]
			if a != null and now.is_empty():
				acts[k] = null
				e._ev(["safe", people[pi]["id"], kinds[k], a[0]])
				if k >= 3:          # a missed call reported this act only; the observers' times stand (music off
					e.sp_told[pi] &= ~(1 << (k - 3))    # and on again in their sight is no escape, §8.5)
			elif a == null and not now.is_empty():
				acts[k] = [now[0], n, false]
				e._ev(["unsafe", people[pi]["id"], kinds[k], now[0]])
				started.append([pi, k])
	var acting := PackedInt32Array()    # the people with an act going on (in person order), for the seen reactions
	var looked := false
	for ri in act_reactions:
		var r: Dictionary = reactions[ri]
		var v: String = r["on"]["unsafe"]
		if r.get("seen", false):
			# the safety walk finds it: the first of its roles (role order, then index) in a zone of the act, in the
			# step it starts or any later one while it lasts; once per act
			if acting.is_empty() and not looked:
				looked = true
				var acts_now: Array = e.sp_acts
				if acts_now.count(no_acts) == acts_now.size():
					continue        # nobody acting (most steps: counted natively, not person by person)
				for ai in people.size():
					if acts_now[ai] != no_acts:
						acting.append(ai)
			var all_acts: Array = e.sp_acts
			var made_all: Dictionary = e.st_made
			for ai in acting:
				var aa: Array = all_acts[ai]
				for k in nk:
					var a = aa[k]
					if a == null or (v != "*" and v != kinds[k]):
						continue
					var made := Vector4i(ri, ai, k, a[1])      # (not the source key: made every step, it cost)
					if made_all.has(made):
						continue
					var obs := notice(e, ri, r["roles"], ai, k, n) if k >= 3 else observer(e, r["roles"], ai)
					if obs == -1:
						continue
					e.st_made[made] = true
					if k >= 3:
						e.sp_watch[ai].erase(Vector2i(ri, k))
					var key := "%d|unsafe|%s|%s|%d" % [ri, people[ai]["id"], kinds[k], a[1]]
					if not e.st_given.has(key):
						give(e, obs, r["task"], int(r.get("priority", prio_of(r["task"]))), key, null, null, null, true,
								null, [ai, k, a[1]])
		else:
			for sk in started:
				var k: int = sk[1]
				var key := "%d|unsafe|%s|%s|%d" % [ri, people[sk[0]]["id"], kinds[k], n]
				if (v == "*" or v == kinds[k]) and not e.st_given.has(key):
					assign(e, r["roles"], r["task"], int(r.get("priority", prio_of(r["task"]))), key, null, null,
							null, null, [sk[0], k, n])


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


## Who of the roles notices a player's music or phone act (kind 3 or 4) of person ai (REALISM.md §8.5); -1 for
## nobody. After a missed call while the act goes on: the first of the roles on duty (role order, then index), wherever
## they are. Otherwise each of the roles on duty sharing a zone with ai draws, when they first do, the clock minutes they
## take to notice (from their own stream), forgotten when they part; the first whose time has come notices.
func notice(e, ri: int, role_list: Array, ai: int, k: int, n: int) -> int:
	var on: PackedByteArray = e.sp_on
	var absent: Dictionary = e._absent
	if e.sp_told[ai] & (1 << (k - 3)):
		for r in role_list:
			for qi in role_people.get(r, PackedInt32Array()):
				if on[qi] and qi != ai and not absent.has(qi):
					return qi
		return -1
	var zs := zones_of(e, ai)
	var room := audio_room(e, ai)
	var wd: Dictionary = e.sp_watch[ai]
	var wk := Vector2i(ri, k)
	var w: Dictionary = wd.get(wk, {})
	var near := PackedInt32Array()
	for r in role_list:
		for qi in role_people.get(r, PackedInt32Array()):
			if on[qi] and qi != ai and not absent.has(qi) and shares(e, zs, room, qi):
				near.append(qi)
	for qi in w.keys():
		if not near.has(qi):
			w.erase(qi)
	var found := -1
	for qi in near:
		if not w.has(qi):
			var s: int = e.sp_aud[qi]
			s ^= (s << 13) & 0xFFFFFFFF     # (World.draw's generator, §17.5)
			s ^= s >> 17
			s ^= (s << 5) & 0xFFFFFFFF
			e.sp_aud[qi] = s
			w[qi] = n + (notice_lo + (((s >> 8) * (notice_hi - notice_lo + 1)) >> 24)) * tpm
		if found == -1 and w[qi] <= n:
			found = qi
	if w.is_empty():
		wd.erase(wk)
	else:
		wd[wk] = w
	return found


## An observer's time to notice stands while the act is off (REALISM.md §8.5), but only while they still share a zone
## with person pi, on duty; for an act going on, notice() keeps the list.
func prune_watch(e, pi: int) -> void:
	var zs := zones_of(e, pi)
	var room := audio_room(e, pi)
	var wd: Dictionary = e.sp_watch[pi]
	var acts: Array = e.sp_acts[pi]
	var on: PackedByteArray = e.sp_on
	var absent: Dictionary = e._absent
	for wk in wd.keys():
		if acts[wk.y] != null:
			continue
		var w: Dictionary = wd[wk]
		for qi in w.keys():
			if not (on[qi] and not absent.has(qi) and shares(e, zs, room, qi)):
				w.erase(qi)
		if w.is_empty():
			wd.erase(wk)


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
	var kname: String = kinds[act[1]]
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
	# the device taken until their duty ends (REALISM.md §8.5; one left at a locker in this very step stays there)
	if act[1] >= 3 and e.sp_phone[qi] == 1:
		e.sp_music[qi] = 0
		e.sp_phone[qi] = 2
		# held until the clock its duty ends (taken off duty: the end of the next duty they work, the user 2026-11-03
		# and 2026-11-07, set when it begins: duty_worked): phase 1 gives it back then
		e.sp_held_to[qi] = e.sp_duty[qi][1] if e.sp_on[qi] and not e.sp_duty[qi].is_empty() else HELD_NEXT
		e.st_next1 = mini(e.st_next1, e.sp_held_to[qi])
		e._ev(["held", people[qi]["id"], people[pi]["id"]])
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
		for k in nk:
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


## The player's music (REALISM.md §8.5): a whole volume from 0 (off) to 100; refused without `audio` (no_audio), while
## the phone is held (held) or left at a locker (left), and any but 0 while they drive a vehicle's run (driving:
## headsets never worn driving, [GEH-C25], [IOGP459]).
func t_audio(e, ti: int, level, slot: int) -> void:
	if typeof(level) != TYPE_INT or level < 0 or level > 100:
		return
	var why := []
	if not has_audio:
		why.append("no_audio")
	elif e.sp_phone[ti] == 2:
		why.append("held")
	elif e.sp_phone[ti] == 0:
		why.append("left")
	elif level > 0 and _drives(e, ti):
		why.append("driving")
	if why.is_empty():
		e.sp_music[ti] = level
	var ev := ["audio", people[ti]["id"], level, "refused" if not why.is_empty() else "done", why]
	if e.st_session:
		ev.append(slot)
	e._ev(ev)


## Whether person pi drives a vehicle's run (§21.4).
func _drives(e, pi: int) -> bool:
	for vh in e.st_veh:
		if vh["driver"] == pi:
			return true
	return false


## The player leaves the phone at a locker or takes it again (§8.5); leaving it turns the music off. Refused without
## `audio`, while held, leaving it while it is in a locker already (left), or away from a locker (locker: the place
## they arrived at is not one, or for take not the locker holding it: the user, 2026-11-07).
func t_phone(e, ti: int, what, slot: int) -> void:
	if typeof(what) != TYPE_STRING or (what != "leave" and what != "take"):
		return
	var why := []
	if not has_audio:
		why.append("no_audio")
	elif e.sp_phone[ti] == 2:
		why.append("held")
	elif what == "leave" and e.sp_phone[ti] == 0:
		why.append("left")
	elif e.sp_pos[ti] == -1 or kind[e.sp_pos[ti]] != "locker" \
			or what == "take" and e.sp_phone[ti] == 0 and e.sp_pos[ti] != e.sp_locker[ti]:
		why.append("locker")
	if why.is_empty():
		e.sp_phone[ti] = 0 if what == "leave" else 1
		e.sp_locker[ti] = e.sp_pos[ti] if what == "leave" else -1
		if what == "leave":
			e.sp_music[ti] = 0
	var ev := ["phone", people[ti]["id"], what, "refused" if not why.is_empty() else "done", why]
	if e.st_session:
		ev.append(slot)
	e._ev(ev)


# ---------------------------------------------------------------- locks at a shift change (§17.9)

## A lock's holder gone home while a job for its work is held (theirs or a colleague's): the lock stays on overnight
## and its owner removes it when the job resumes (§17.10). For the permit form.
func overnight(e, who, work: String) -> bool:
	if typeof(who) != TYPE_STRING or not person_ix.has(who):
		return false
	var pi: int = person_ix[who]
	return _kept_works(e).has(work) and not e.sp_on[pi] and off_site_now(e, pi)   # (gone home: §17.9, with homes §21.1)


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
			if has_audio and e.sp_music[t] >= audio_mask:
				# a call not heard over the music (REALISM.md §8.5): the caller reports it unanswered
				if not missed_now(e, people[t]["id"], people[pi]["id"]):
					e._ev(["missed", people[t]["id"], msg, people[pi]["id"]])
				if e.sp_acts[t][3] != null:
					e.sp_told[t] |= 1


## A radio call (a task called to a role) is missed as a message is (say, REALISM.md §8.5): by each player of the role
## but the caller, in slot order, whose music is at the mask or louder; event missed with the task.
func miss_call(e, pi: int, task: String, role: String) -> void:
	if not has_audio:
		return
	for k in e.st_players.size():
		var t: int = e.st_players[k]
		if t != -1 and t != pi and people[t]["role"] == role and e.sp_music[t] >= audio_mask:
			if not missed_now(e, people[t]["id"], people[pi]["id"]):
				e._ev(["missed", people[t]["id"], task, people[pi]["id"], "call"])
			if e.sp_acts[t][3] != null:
				e.sp_told[t] |= 1


## Whether person qid has missed a call from pid in this step already (§8.5): a call and its message together (an
## alarm's call of a role and its say) are one exchange on the radio, missed once.
func missed_now(e, qid: String, pid: String) -> bool:
	var evs: Array = e.events
	var i := evs.size() - 1
	while i >= 0:
		var x: Array = evs[i]
		if x[0] != e.step_no:
			return false
		if x[1] == "missed" and x[2] == qid and x[4] == pid:
			return true
		i -= 1
	return false


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
			if not trainee and e._staff_wait_sleep and not rm.is_empty() and int(x["place"]) != -1:
				# nothing changes for them until their 15 minutes are over, or someone comes into the room or comes on
				# duty there, or a place there is let go or taken (_wake_at); a task, a duty or a stop wakes them, as
				# any sleeper
				e.sp_wake[pi] = int(x["meet_since"]) + WAIT_PLACE * tpm
				e.sp_wait_on[pi] = wait_key[rm[0]]
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
	if e.sp_aboard[pi] == -1:           # (aboard a vehicle: no task progress, §21.4)
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
				miss_call(e, pi, item[2], item[1])
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
		elif s.has("read") and s.has("via"):
			# through a meter (REALISM.md §2.5, §2.13): the input names it; without the tool the step waits
			for k in tin.size():
				var it: Array = tin[k]
				if not used[k] and it[0] == "read" and _same(it[1], s["read"]) and _is_num(it[2]) \
						and it.size() > 3 and _same(it[3], s["via"]):
					used[k] = true
					if not Hands.can_read(e, pid, s["via"]):
						e._ev(["read", pid, s["read"], it[2], "tool"])
						continue
					var val: float = Hands.shown(e, s["via"], e.prev)
					var ex = s.get("expect")
					var how: String
					if absf(it[2] - val) > float(s.get("tol", 0)):
						how = "misread"
					else:
						how = "ok" if ex == null or (ex[0] <= val and val <= ex[1]) else "out_of_range"
					e._ev(["read", pid, s["read"], it[2], how])
					r = "next"
					break
		elif s.has("read"):
			for k in tin.size():
				var it: Array = tin[k]
				if not used[k] and it[0] == "read" and _same(it[1], s["read"]) and _is_num(it[2]) and it.size() == 3:
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
		elif s.has("sleep"):            # §21.3: done once the clock reaches T, wherever they are
			if not x.has("T"):
				x["T"] = sleep_until(e, pi, s["sleep"]["until"])
			if e.clock() >= x["T"]:
				r = "next"
		elif s.has("ride"):             # §21.4: done standing at `to`, by the bus or on foot
			if e.sp_pos[pi] == pix[s["ride"]["to"]]:
				r = "next"
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
					miss_call(e, pi, c["task"], c["role"])
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
		elif s.has("jsa") or s.has("talk"):
			# REALISM.md §8.6: their own JSA of the work (made now or before: the work's JSA is theirs), or their own
			# talk for it done in this step
			var k := "jsa" if s.has("jsa") else "talk"
			var w = cur["work"] if s[k] == "$" else s[k]
			if k == "jsa":
				if e.jsa_of.has(w) and _same(e.jsa_of[w][2], pid):
					r = "next"
			else:
				for j in mine.size():
					var y: Array = mine[j]
					if not took.has(j) and y[1] == "talk" and _same(y[2], w) and _same(y[4], pid) and y[5] == "done":
						took[j] = true
						r = "next"
						break
		elif s.has("wo"):               # REALISM.md §2.20: that action on that work, from the panel (any data)
			var w = cur["work"] if s["wo"]["work"] == "$" else s["wo"]["work"]
			var a: String = s["wo"]["action"]
			for j in mine.size():
				var y: Array = mine[j]
				if not took.has(j) and y[1] == "wo" and y[5] == "done" and _same(y[2], w) and y[3] == a \
						and _same(y[4], pid):
					took[j] = true
					r = "next"
					break
			if typeof(r) == TYPE_STRING and r == "wait" and _first_look(x) \
					and early_done(e, pi, cur, "wo", [w, a], null, slot):
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
		elif s.has("tool") and not s.has("hand"):   # REALISM.md §2.13: done once they carry them (off: none)
			var have: Array = e.carried.get(pid, [])
			if typeof(s["tool"]) == TYPE_STRING:
				if have.is_empty():
					r = "next"
			else:
				var all := true
				for t in s["tool"]:
					if not have.has(t):
						all = false
						break
				if all:
					r = "next"
		elif s.has("hand"):     # their done hand action (REALISM.md §2.13), or one done earlier that holds
			for j in mine.size():
				var y: Array = mine[j]
				if not took.has(j) and y[1] == "hand" and y[6] == "done" and _same(y[2], s["kks"]) \
						and _same(y[3], s["hand"]) and _same(y[5], pid):
					took[j] = true
					r = "next"
					break
			if typeof(r) == TYPE_STRING and r == "wait" and _first_look(x) \
					and early_done(e, pi, cur, "hand", [s["kks"], s["hand"]], s.get("value"), slot):
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
		elif kind == "hand":            # (REALISM.md §2.13)
			if y[6] == "done" and _same(y[5], pid):
				early.append(["hand", y[0], y[2], y[3]])
		elif kind == "permit" or kind == "lock" or kind == "unlock" or kind == "wo":
			if y[5] == "done" and _same(y[4], pid):
				if kind == "permit":
					early.append(["permit", y[0], y[2], y[3], e.ptw.get(y[2])])
				elif kind == "wo":      # (its work order's number, REALISM.md §2.20)
					early.append(["wo", y[0], y[2], y[3], e.wo_no.get(y[2])])
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
		elif kind == "wo":
			ok = _same(q[2], want[0]) and q[3] == want[1] and WorkOrders.holds(e, want[0], want[1], q[4])
		elif kind == "hand":
			ok = _same(q[2], want[0]) and _same(q[3], want[1]) and Hands.hand_holds(e, want[0], want[1], o)
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
		for k in nk:
			var a = e.sp_acts[pi][k]
			if a != null:
				acts.append([people[pi]["id"], kinds[k], a[0], a[1], a[2]])
	return [worn, acts]


## `audio` (REALISM.md §8.5): {person: [music, phone]} for those whose music is on or whose phone is not carried.
func snap_audio(e) -> Dictionary:
	var out := {}
	for pi in people.size():
		if e.sp_music[pi] != 0 or e.sp_phone[pi] != 1:
			out[people[pi]["id"]] = [e.sp_music[pi], e.sp_phone[pi]]
	return out


## `vehicles` (§21.4): {id: [place or [from, to, depart, arrive], [the driver, then the riders]]}.
func snap_vehicles(e) -> Dictionary:
	var out := {}
	for vi in vehicles.size():
		var vh: Dictionary = e.st_veh[vi]
		var where
		if not vh["leg"].is_empty():
			where = [places[vh["leg"][0]]["id"], places[vh["leg"][1]]["id"], vh["leg"][2], vh["leg"][3]]
		elif vh["at"] == -1:            # steered, on the road (§21.16)
			where = ["road", places[vh["from"]]["id"]]
		else:
			where = places[vh["at"]]["id"]
		var ab := []
		if vh["driver"] != -1:
			ab.append(people[vh["driver"]]["id"])
		for rd in vh["riders"]:
			ab.append(people[rd[0]]["id"])
		out[vehicles[vi]["id"]] = [where, ab]
	return out


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
		elif e.sp_aboard[pi] != -1:
			where = ["vehicle", vehicles[e.sp_aboard[pi]]["id"]]
		elif e.sp_pos[pi] != -1:
			where = places[e.sp_pos[pi]]["id"]
		var c = e.sp_cur[pi]
		out[people[pi]["id"]] = [where, c["task"] if c != null else null, c["step"] if c != null else null]
	return out
