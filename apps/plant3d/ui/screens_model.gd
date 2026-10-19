## The control room screens' content (docs/PLANT3D.md §7.11), made from the behaviour model and screens.json: every
## code the model has something for (a value with a unit, a shown or lamp or position binding, an op, a machine, an
## alarm, a trip) lands in the group whose `codes` hold the longest beginning of it, or in `left_out`. What each item
## is (a drive, a valve, a breaker, a sequence, a measurement), which value says it runs or where it stands, its
## alarms and trips and the operation it would take next are worked out here once; ui/mimic.gd draws them and reads
## the engine a few times a second. Only reads the model; nothing here changes the plant.
extends RefCounted

const JsonStrict = preload("res://sim/json_strict.gd")
const Links = preload("res://sim/links.gd")

var error := ""
var data := {}                     # screens.json
var info                           # ui/plant_info.gd
var m                              # the PlantModel
var screens: Array = []            # [{id, short, title, groups: [{id, title, at, items: [codes], extra: [values]}], lines, trend}]
var overview := {}                 # {title, short, key: [values]}
var items := {}                    # code -> item (below), in the model's order
var screen_of := {}                # code -> [screen index, group index]
var left_out := {}                 # code -> why
var unplaced: Array = []           # codes on no screen and not left out (content the reference refuses: shown as a warning)
var internal: Array = []           # values with a unit and no code that no group names (the model's workings)
var trended: Array = []            # every value a screen trends or the overview shows (ui/trends.gd samples them)

## An item: {code, kind: drive | valve | breaker | machine | measure, name, values: [names], run: value or "",
## closed: value or "", pos: value or "", machine: index or -1, lamps: [[kind, value]], alarms: [alarm positions],
## trips: [trip positions], ops: [ops]}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var r := JsonStrict.parse(FileAccess.get_file_as_bytes(path))
	return r.value if r.ok and typeof(r.value) == TYPE_DICTIONARY else {"_error": "screens.json: not strict JSON"}


func _init(plant_info, screens_json: Dictionary) -> void:
	info = plant_info
	m = info.m
	data = screens_json
	if data.has("_error"):
		error = data["_error"]
		return
	if data.is_empty():
		error = "the plant has no screens.json"
		return
	overview = data.get("overview", {})
	_collect()
	_place()
	for v in overview.get("key", []):
		if not trended.has(v):
			trended.append(v)
	for sc in screens:
		for v in sc.get("trend", []):
			if not trended.has(v):
				trended.append(v)


## The codes the screens show (§7.11), in the model's order, with what the model has for each.
func _collect() -> void:
	for v in m.values:
		var nd: Dictionary = v[1]
		if nd.has("unit") and nd.has("kks"):
			_item(nd["kks"]).values.append(v[0])
	for b in m.bind:
		if b.has("show"):
			var it := _item(b["kks"])
			if not it.values.has(b["show"]):
				it.values.append(b["show"])
		elif b.has("lamp"):
			_item(b["kks"]).lamps.append([b["lamp"], b["of"]])
		elif b.get("anim", "") in ["stem", "disc", "blades"]:
			var it := _item(b["kks"])
			if it.pos == "":
				it.pos = b["of"]
	for o in m.ops:
		_item(o["kks"]).ops.append(o)
	for k in m.machines.size():
		if m.machines[k].has("kks"):
			_item(m.machines[k]["kks"]).machine = k
	for k in m.alarms.size():
		var a: Dictionary = m.alarms[k]
		var c = a.get("kks", a.get("where"))
		if c != null:
			_item(c).alarms.append(k)
	# a trip belongs to its code and to every code whose state its actions write (a fan stopped by its probe's trip)
	var state_kks := {}
	for v in m.values:
		if v[2] == "state" and v[1].has("kks"):
			state_kks[v[0]] = v[1]["kks"]
	for k in m.trips.size():
		var t: Dictionary = m.trips[k]
		if t.has("kks"):
			_item(t["kks"]).trips.append(k)
		for act in t.get("do", []):
			for s in act.get("set", {}):
				var c = state_kks.get(s)
				if c != null and items.has(c) and not items[c].trips.has(k):
					items[c].trips.append(k)
	for c in items:
		_classify(items[c])


func _item(code: String) -> Dictionary:
	if not items.has(code):
		items[code] = {"code": code, "kind": "measure", "name": "", "values": [], "run": "", "closed": "", "pos": "",
				"machine": -1, "lamps": [], "alarms": [], "trips": [], "ops": []}
	return items[code]


func _classify(it: Dictionary) -> void:
	var code: String = it.code
	it.name = info.name_of(code)
	if it.name == "":
		it.name = _decoded(code)
	var g := Links.kks_parts(code)
	var measurement: bool = g.size() > 4 and String(g[4]).begins_with("C")
	for l in it.lamps:
		if l[0] == "running" and it.run == "" and not measurement:
			it.run = l[1]
		elif l[0] == "closed" and it.closed == "":
			it.closed = l[1]
	if it.run == "" and not measurement:
		for o in it.ops:
			if o["do"] == "start" and not o.get("set", {}).is_empty():
				it.run = o["set"].keys()[0]       # the state its start sets: what it was told to do
				break
	if it.pos != "":
		it.kind = "valve"
	elif it.closed != "":
		it.kind = "breaker"
	elif it.run != "":
		it.kind = "drive"
	elif it.machine >= 0:
		it.kind = "machine"
	else:
		it.kind = "measure"


func _decoded(code: String) -> String:
	var d := Links.decode(code, m.plant["kks"])
	if d.get("equipment") != null:
		return String(d.equipment)
	return String(d.system) if d.get("system") != null else ""


static func _owner(code: String, prefixes: Dictionary) -> String:
	var best := ""
	for p in prefixes:
		if code.begins_with(p) and p.length() > best.length():
			best = p
	return best


func _place() -> void:
	var prefixes := {}                # prefix -> [screen index, group index] or ["left", why]
	for si in data.get("screens", []).size():
		var sc: Dictionary = data["screens"][si]
		var groups := []
		for gi in sc.get("groups", []).size():
			var gr: Dictionary = sc["groups"][gi]
			groups.append({"id": gr["id"], "title": gr["title"], "at": gr["at"], "items": [], "extra": gr.get("extra", [])})
			for p in gr["codes"]:
				prefixes[p] = [si, gi]
		screens.append({"id": sc["id"], "short": sc.get("short", sc["id"]), "title": sc["title"], "groups": groups,
				"lines": sc.get("lines", []), "trend": sc.get("trend", [])})
	for x in data.get("left_out", []):
		for p in x["codes"]:
			prefixes[p] = ["left", x["why"]]
	var codes := items.keys()
	codes.sort()                      # in a group by code, as on the drawings: fan 1 to 10, then their probes
	for c in codes:
		var p := _owner(c, prefixes)
		if p == "":
			unplaced.append(c)
			continue
		var at: Array = prefixes[p]
		if typeof(at[0]) == TYPE_STRING:
			left_out[c] = at[1]
		else:
			screen_of[c] = at
			screens[at[0]].groups[at[1]].items.append(c)
	var extras := {}
	for sc in screens:
		for gr in sc.groups:
			for v in gr.extra:
				extras[v] = true
	for v in m.values:
		if v[1].has("unit") and not v[1].has("kks") and not extras.has(v[0]):
			internal.append(v[0])


func screen_index(id: String) -> int:
	for i in screens.size():
		if screens[i].id == id:
			return i
	return -1


# ------------------------------------------------------------------ what an item says now (read from the engine)

## The trip latched on the item, or -1.
func tripped(it: Dictionary, e) -> int:
	for k in it.trips:
		if e.latched[k]:
			return k
	return -1


## Its alarms as they stand: [[priority, unacknowledged, alarm position]] of those not normal, not shelved, not
## suppressed by design, most urgent first.
func alarms_now(it: Dictionary, e) -> Array:
	var out := []
	for k in it.alarms:
		var s: String = e.astate[k]
		if s == "normal" or e.shelved[k] != -1 or suppressed(e, k):
			continue
		out.append([int(e._al[k][5]), s.ends_with("unack"), k])
	out.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and int(a[1]) > int(b[1])))
	return out


static func suppressed(e, k: int) -> bool:
	var slot: int = e._al[k][3]
	return slot != -1 and e.cur[slot] >= 0.5


## Counts of the screen's alarms by priority [p1, p2, p3] and how many of them are unacknowledged.
func screen_alarms(si: int, e) -> Dictionary:
	var by := [0, 0, 0]
	var unack := 0
	var seen := {}
	for gr in screens[si].groups:
		for c in gr.items:
			for a in alarms_now(items[c], e):
				if seen.has(a[2]):
					continue
				seen[a[2]] = true
				by[clampi(a[0], 1, 3) - 1] += 1
				if a[1]:
					unack += 1
	return {"by": by, "unack": unack, "alarms": seen.keys()}


## The operation the item would take next, from its state: start or stop a drive, open or close a valve or a
## breaker, the first command its sequence takes now, a reset while a trip is latched. {} when none.
func next_op(it: Dictionary, e) -> Dictionary:
	var want := []
	var tk := tripped(it, e)
	if tk >= 0:
		for o in it.ops:
			if o["do"] == "reset" and o.get("trip") == m.trips[tk]["id"]:
				return o
	match it.kind:
		"drive":
			want = ["stop"] if e.truth(it.run) else ["start"]
		"breaker":
			want = ["open_breaker"] if e.truth(it.closed) else ["close_breaker"]
		"valve":
			want = ["close"] if e.v(it.pos) >= 0.5 else ["open"]
	for d in want:
		for o in it.ops:
			if o["do"] == d and not o.has("machine"):
				return o
	# a sequence's or controller's command it takes in its present state; else one it takes in any state ("*")
	var any := {}
	for o in it.ops:
		if o.has("machine"):
			var mi: int = info.machine_index(o["machine"])
			var from = m.machines[mi]["commands"][o["do"]]["from"]
			if typeof(from) == TYPE_STRING:
				if from == "*" and any.is_empty():
					any = o
			elif from.has(info.state_name(mi, e)):
				return o
	return any
