extends RefCounted
## The plant's behaviour model and what the engine, procedures and links need of the rest of the content
## (docs/PLANT3D.md §2, §6–§8), read from the files ref/plant3d.py reads.
##
## This is not the validator: content is checked by ref/plant3d.py (and the build, decision 0054) before it reaches the
## app. The loader still refuses what it can't run (a file that isn't strict JSON, a name no value has, a node of no
## known kind) and names the file and item, so broken content fails loudly instead of running wrongly.
##
##   var m := PlantModel.from_dir("/path/to/data/plant3d")         # or from_files({rel path: bytes, text or object})
##   if m.error != "": …
##   var e := Engine.new(m, "cold_iron")

const JsonStrict = preload("json_strict.gd")
const Staff = preload("staff.gd")
const World = preload("world.gd")
const Hse = preload("hse.gd")

const STATELESS := ["const", "state", "of", "sum", "product", "min", "max", "diff", "select", "cmp", "and", "or", "not"]
const STATEFUL := ["lag", "ramp", "integrate", "latch", "delay", "timer", "wrap", "hold", "draw", "wear", "count",
		"sample"]

var error := ""
var plant := {}
var areas: Array = []                 # area objects, in plant.json order
var codes := {}                       # every KKS code of the plant (equipment, its parts, pipes, inline parts, structures)
var values: Array = []                # [name, node, kind], joined in plant.json's area order
var index := {}                       # value name -> position in values
var ext: Array = []
var ops: Array = []
var op_keys := {}                     # op_key(kks, do, trip) -> op
var interlocks: Array = []
var machines: Array = []              # each with "_ids" (state ids in order) added
var alarms: Array = []
var trips: Array = []
var alarm_area := {}                  # alarm id -> its model file's area (a reaction's `areas`, PLANT3D §17.12)
var trip_area := {}                   # trip id -> its model file's area
var bind: Array = []
var version := 1                      # plant.json's (§14)
var isolations: Array = []            # format 2 (§15.1), joined in area order
var works: Array = []                 # format 2 (§15.2)
var isolation_ix := {}                # id -> position
var work_ix := {}
var lifts: Array = []                 # format 2's lifts (§20.1), joined in area order
var scenarios := {}                   # id -> scenario, in file-name order
var procedures := {}                  # id -> procedure, in file-name order
var staff = null                      # sim/staff.gd: staff.json (§16), or null
var weather = null                    # weather.json (REALISM.md §5.1), or null
var tools = null                      # tools.json (REALISM.md §2.3): {list, ix: id -> index, at: per tool [[place, count]]}
var hse = null                        # hse.json (REALISM.md §8.6): {hazard_ix, control_ix, own: job -> [hazards, controls]}
var hands: Array = []                 # hand actions (REALISM.md §2.4), joined in area order
var hands_ix := {}                    # "code|action" -> hand action
var meters: Array = []                # meters (REALISM.md §2.5)
var meters_ix := {}                   # id -> meter
var has_wo := false                   # work orders (REALISM.md §2.20): the plant has workorders.json
var wo_doc = null                     # workorders.json as read (the app's panel reads its titles and history), or null
var wo_ids = null                     # its code lists {modes, causes, actions: [ids]} for the engine, or null
var _reads_wx := false                # a name read was the weather's kind (world_wx; known())
var _reads_world := false             # a name read was a clock value's (REALISM.md §2.1; known())
var _content_reads_world := false     # the model's or the staff's reads were: every scenario needs `world`
var _content_reads_wx := false        # likewise world_wx: every scenario needs `world.weather`


## The key an op is found by (§7.2: its equipment, its `do` and, for a reset, its trip). null when an input's parts
## can't name any op (not text), so it is an unknown op.
static func op_key(kks, do, trip):
	if typeof(kks) != TYPE_STRING or typeof(do) != TYPE_STRING:
		return null
	if trip == null:
		return "%s\n%s\n" % [kks, do]
	if typeof(trip) != TYPE_STRING:
		return null
	return "%s\n%s\nt%s" % [kks, do, trip]


static func node_kind(n) -> String:
	if typeof(n) != TYPE_DICTIONARY:
		return ""
	var st := []
	for k in STATEFUL:
		if n.has(k):
			st.append(k)
	if st.size() == 1:
		return st[0]
	var found := []
	for k in STATELESS:
		if n.has(k):
			found.append(k)
	if found.size() == 1 and st.is_empty():
		return found[0]
	return ""


static func node_refs(n: Dictionary, kind: String) -> Array:
	match kind:
		"const", "state":
			return []
		"sum", "product", "min", "max", "and", "or", "diff":
			return n[kind]
		"select":
			return [n["select"]] + n["cases"]
		"cmp":
			return [n["cmp"][0], n["cmp"][2]]
		"latch":
			return [n["latch"], n["reset"]]
		"hold":
			return [n["hold"], n["when"]]
		"draw":
			return []
		"wear", "count":
			var out := [n[kind]]
			for k in ["by", "reset"]:
				if n.has(k):
					out.append(n[k])
			return out
	return [n[kind]]


static func is_num(x) -> bool:
	var t := typeof(x)
	if t == TYPE_INT:
		return absi(x) < 1000000000
	if t == TYPE_FLOAT:
		return is_finite(x) and absf(x) < 1e9
	return false


static func from_dir(path: String):
	var files := {}
	var top := path.trim_suffix("/")
	for rel in ["plant.json", "kit.json", "sounds.json", "staff.json", "weather.json", "tools.json", "hse.json",
			"workorders.json"]:
		if FileAccess.file_exists(top + "/" + rel):
			files[rel] = FileAccess.get_file_as_bytes(top + "/" + rel)
	for sub in ["areas", "model", "scenarios", "procedures"]:
		var d := DirAccess.open(top + "/" + sub)
		if d == null:
			continue
		var names := d.get_files()
		for f in names:
			if f.ends_with(".json"):
				files[sub + "/" + f] = FileAccess.get_file_as_bytes(top + "/" + sub + "/" + f)
	return from_files(files)


## files: {relative path: PackedByteArray | String | Dictionary (already read)}; null removes a file.
static func from_files(files: Dictionary):
	var m = new()
	m._load(files)
	return m


func _fail(msg: String) -> void:
	if error == "":
		error = msg


func _read(files: Dictionary, rel: String):
	if not files.has(rel) or files[rel] == null:
		_fail("%s is missing" % rel)
		return null
	var v = files[rel]
	if typeof(v) == TYPE_DICTIONARY:
		return v
	var r: Dictionary
	if typeof(v) == TYPE_STRING:
		r = JsonStrict.parse_text(v)
	else:
		r = JsonStrict.parse(v)
	if not r.ok:
		_fail("%s: not strict JSON (%s)" % [rel, r.error])
		return null
	if typeof(r.value) != TYPE_DICTIONARY:
		_fail("%s: not an object" % rel)
		return null
	return r.value


func _load(files: Dictionary) -> void:
	var p = _read(files, "plant.json")
	if p == null:
		return
	plant = p
	ext = p.get("ext", [])
	version = int(p.get("version", 1))
	has_wo = files.has("workorders.json") and files["workorders.json"] != null
	for aid in p.get("areas", []):
		var a = _read(files, "areas/%s.json" % aid)
		if a == null:
			return
		areas.append(a)
		for e in a.get("equipment", []):
			codes[e["kks"]] = true
			for c in e.get("parts", []):
				codes[c["kks"]] = true
		for pp in a.get("pipes", []):
			codes[pp["kks"]] = true
			for kind in ["valves", "parts"]:
				for v in pp.get(kind, []):
					codes[v["kks"]] = true
		for s in a.get("structures", []):
			if s.has("kks"):
				codes[s["kks"]] = true
	for aid in p.get("areas", []):
		var rel := "model/%s.json" % aid
		if files.has(rel) and files[rel] != null:
			var d = _read(files, rel)
			if d == null:
				return
			_add_model(d, rel)
	if error != "":
		return
	_finish()
	if error != "":
		return
	_load_workorders(files)     # (before staff.json: its wo steps and reactions need it, REALISM.md §2.20)
	if error != "":
		return
	var rels := files.keys()
	rels.sort()
	for rel in rels:
		if files[rel] == null:
			continue
		if rel.begins_with("scenarios/"):
			var s = _read(files, rel)
			if s == null:
				return
			scenarios[s["id"]] = s
		elif rel.begins_with("procedures/"):
			var pr = _read(files, rel)
			if pr == null:
				return
			procedures[pr["id"]] = pr
	if files.has("staff.json") and files["staff.json"] != null:
		var sd = _read(files, "staff.json")
		if sd == null:
			return
		staff = Staff.load_from(self, sd)
		if staff.error != "":
			_fail(staff.error)
			return
		for r in sd.get("reactions", []):       # a staff reaction on a value (§16.7) reads it in step 9
			var on = r.get("on") if typeof(r) == TYPE_DICTIONARY else null
			if typeof(on) == TYPE_DICTIONARY and (on.get("value") == "world_hour" or on.get("value") == "world_day"):
				_reads_world = true
			if typeof(on) == TYPE_DICTIONARY and on.get("value") == "world_wx":
				_reads_wx = true
	if files.has("tools.json") and files["tools.json"] != null:
		_load_tools(_read(files, "tools.json"))
		if error != "":
			return
	if hse == null and (not files.has("hse.json") or files["hse.json"] == null):
		for w in works:
			if w.has("jsa"):
				_fail("work %s: a job kind, and the plant has no hse.json" % str(w.get("id")))
				return
	if files.has("hse.json") and files["hse.json"] != null:
		# the JSAs' hazard library (REALISM.md §8.6, milestone HS1): only in a version 2 plant with staff.json
		if version != 2 or staff == null:
			_fail("hse.json: only in a version 2 plant with staff.json")
			return
		hse = Hse.read_library(_read(files, "hse.json"))
		if hse == null:
			_fail("hse.json: a library the engine can't read")
			return
		for w in works:
			if w.has("jsa") and (typeof(w["jsa"]) != TYPE_STRING or not hse["own"].has(w["jsa"])):
				_fail("work %s: a job kind hse.json doesn't have" % str(w.get("id")))
				return
	_check_hands()
	if error != "":
		return
	for nm in ["world_hour", "world_day", "world_wx"]:
		if version == 2 and ext.has(nm):
			_fail("plant.json: the ext value %s has the name of a clock value or the weather's kind" % nm)
			return
	if files.has("weather.json") and files["weather.json"] != null:
		weather = _read(files, "weather.json")
		if weather == null:
			return
		if version != 2:
			_fail("weather.json: only in a version 2 plant")
			return
		for v in weather.get("values", []):
			if typeof(v) != TYPE_DICTIONARY:
				_fail("weather.json: a driven value the engine can't read: %s" % str(v))
				return
			if not ext.has(v.get("id")):
				_fail("weather.json: %s is not an ext value" % str(v.get("id")))
				return
		_check_weather_file()
		if error != "":
			return
	_content_reads_world = _reads_world
	_content_reads_wx = _reads_wx
	for sid in scenarios:
		_check_scenario(scenarios[sid])


func _add_model(d: Dictionary, rel: String) -> void:
	for pair in d.get("values", []):
		var name: String = pair[0]
		var kind := node_kind(pair[1])
		if kind == "":
			_fail("%s: value %s: not a node of format 1" % [rel, name])
			return
		if index.has(name) or (version == 2 and (name == "world_hour" or name == "world_day" or name == "world_wx")):
			_fail("%s: value %s: name already used" % [rel, name])
			return
		index[name] = values.size()
		values.append([name, pair[1], kind])
	for mc in d.get("machines", []):
		var ids := []
		var ix := {}
		for s in mc["states"]:
			ix[s["id"]] = ids.size()
			ids.append(s["id"])
		mc["_ids"] = ids
		mc["_ix"] = ix
		machines.append(mc)
	trips.append_array(d.get("trips", []))
	for t in d.get("trips", []):
		trip_area[t["id"]] = d["area"]
	for o in d.get("ops", []):
		op_keys[op_key(o["kks"], o["do"], o.get("trip"))] = o
		ops.append(o)
	interlocks.append_array(d.get("interlocks", []))
	alarms.append_array(d.get("alarms", []))
	for a in d.get("alarms", []):
		alarm_area[a["id"]] = d["area"]
	bind.append_array(d.get("bind", []))
	for x in d.get("isolations", []):
		isolation_ix[x["id"]] = isolations.size()
		isolations.append(x)
	for w in d.get("works", []):
		work_ix[w["id"]] = works.size()
		works.append(w)
	lifts.append_array(d.get("lifts", []))
	for x in d.get("hands", []):        # REALISM.md §2.4, §2.5 (milestone HW1)
		hands_ix[str(x["kks"]) + "|" + str(x["action"])] = x
		hands.append(x)
	for x in d.get("meters", []):
		meters_ix[x["id"]] = x
		meters.append(x)


## workorders.json as far as the engine reads it (REALISM.md §2.20; the validator checks the rest): its three code
## lists, and the works' finds and codes naming their ids. Without it no work names finds, codes or hours.
func _load_workorders(files: Dictionary) -> void:
	if works.size() > (512 if has_wo else 128):
		_fail("the joined model has over %d works" % (512 if has_wo else 128))
		return
	if not has_wo:
		for w in works:
			for k in ["finds", "codes", "hours"]:
				if w.has(k):
					_fail("work %s.%s: the plant has no workorders.json" % [w["id"], k])
					return
		return
	var d = _read(files, "workorders.json")
	if d == null:
		return
	if version != 2:
		_fail("workorders.json: only in a version 2 plant")
		return
	var ids := {}
	for k in ["modes", "causes", "actions"]:
		var l = d.get(k)
		if typeof(l) != TYPE_ARRAY or l.is_empty():
			_fail("workorders.json.%s: a list the engine can't read" % k)
			return
		ids[k] = []
		for x in l:
			if typeof(x) != TYPE_DICTIONARY or typeof(x.get("id")) != TYPE_STRING or ids[k].has(x["id"]):
				_fail("workorders.json.%s: an entry the engine can't read: %s" % [k, str(x)])
				return
			ids[k].append(x["id"])
	for w in works:
		var f = w.get("finds", [])
		if typeof(f) != TYPE_ARRAY:
			_fail("work %s.finds: not a list" % w["id"])
			return
		for x in f:
			if not ids["modes"].has(x):
				_fail("work %s.finds: %s is not one of modes" % [w["id"], str(x)])
				return
		if w.has("codes"):
			var c = w["codes"]
			if typeof(c) != TYPE_ARRAY or c.size() != 3 or not (c[0] == null or ids["modes"].has(c[0])) \
					or not (c[1] == null or ids["causes"].has(c[1])) or not ids["actions"].has(c[2]):
				_fail("work %s.codes: codes the engine can't read" % w["id"])
				return
	wo_doc = d
	wo_ids = ids


## tools.json as far as the engine reads it (REALISM.md §2.3; the validator checks the rest): each tool kept at places
## of staff.json, with whole counts.
func _load_tools(d) -> void:
	if d == null:
		return
	if version != 2 or staff == null:
		_fail("tools.json: only in a version 2 plant with staff.json")
		return
	var out := {"list": [], "ix": {}, "at": []}
	for t in d.get("tools", []):
		if typeof(t) != TYPE_DICTIONARY or typeof(t.get("id")) != TYPE_STRING or typeof(t.get("kind")) != TYPE_STRING:
			_fail("tools.json: a tool the engine can't read: %s" % str(t))
			return
		var at := []
		for a in t.get("at", []):
			if typeof(a) != TYPE_ARRAY or a.size() != 2 or not staff.pix.has(a[0]) or typeof(a[1]) != TYPE_INT:
				_fail("tools.json: tool %s: a place the engine can't read: %s" % [t["id"], str(a)])
				return
			at.append([int(staff.pix[a[0]]), int(a[1])])
		out["ix"][t["id"]] = out["list"].size()
		out["list"].append(t)
		out["at"].append(at)
	tools = out


## What the engine reads of the hand actions, meters, HART ops, causes and cures names what exists (the validator
## checks the rest, REALISM.md §2.13).
func _check_hands() -> void:
	for x in hands:
		var w := "hand action %s %s" % [str(x.get("kks")), str(x.get("action"))]
		_check_set(x.get("set", {}), w)
		if x.has("input"):
			_check_set({x["input"]: 0}, w)
		for nd in x.get("samples", []):     # REALISM.md §2.19: sample nodes only
			if typeof(nd) != TYPE_STRING or not index.has(nd) or values[index[nd]][2] != "sample":
				_fail("%s: %s is not a sample node" % [w, str(nd)])
		for nd in x.get("needs", []):
			_need(nd[0], w)
		for t in x.get("tools", []):
			if tools == null or not tools["ix"].has(t):
				_fail("%s: no tool %s" % [w, str(t)])
	for x in meters:
		var w := "meter " + str(x.get("id"))
		_need(x["value"], w)
		for nd in x.get("needs", []):
			_need(nd, w)
		_need_ref(x.get("else", 0), w)
	for o in ops:
		if o.has("hart"):
			_check_set({o["hart"]: 0}, "op %s %s" % [o["kks"], o["do"]])


## The values the engine keeps for permits and isolations (§15.1, §15.3) and each lift's load (§20.1), in slot order.
func kept() -> Array:
	var out := []
	for x in isolations:
		out.append(x["id"] + "_locked")
		out.append(x["id"] + "_complete")
	for w in works:
		out.append(w["id"] + "_permit")
	for x in lifts:
		out.append(x["id"] + "_load")
	if has_wo:                  # (work orders, REALISM.md §2.20)
		for w in works:
			out.append(w["id"] + "_wo")
	return out


## Every name the engine will read must exist (the validator's bad_ref, kept here because a missing name would
## otherwise read slot -1).
func known(name) -> bool:
	if typeof(name) != TYPE_STRING:
		return false
	if index.has(name) or ext.has(name):
		return true
	for mc in machines:
		if name == mc["id"] + "_state":
			return true
	for t in trips:
		if name == t["id"] + "_latched":
			return true
	if version == 2 and (name == "world_hour" or name == "world_day"):
		_reads_world = true     # the clock values (REALISM.md §2.1): slots only in a scenario with `world`
		return true
	if version == 2 and name == "world_wx":
		_reads_wx = true        # the weather's kind (REALISM.md §5.1): a slot only in a scenario with world.weather
		return true
	return kept().has(name)


func _need(name, where: String) -> void:
	if not known(name):
		_fail("%s: no value %s" % [where, str(name)])


func _need_ref(r, where: String) -> void:
	if not is_num(r):
		_need(r, where)


func _finish() -> void:
	for v in values:
		for r in node_refs(v[1], v[2]):
			_need_ref(r, "value " + v[0])
		if v[2] == "sample":            # REALISM.md §2.19: its spread a table, its hours on the plant's clock
			var sp = v[1].get("spread")
			var h = v[1].get("hours")
			var ok: bool = typeof(sp) == TYPE_ARRAY and not sp.is_empty() and is_num(h) and float(h) > 0 \
					and plant.get("clock") != null
			for row in (sp if typeof(sp) == TYPE_ARRAY else []):
				ok = ok and typeof(row) == TYPE_ARRAY and row.size() == 2 and is_num(row[0]) and is_num(row[1])
			if not ok:
				_fail("value %s: a sample node the engine can't run (its spread, its hours or the plant's clock)" % v[0])
	for x in interlocks:
		_need(x["when"], "interlock " + x["id"])
		_check_actions(x["do"], "interlock " + x["id"])
	for mc in machines:
		for s in mc["states"]:
			for nx in s.get("next", []):
				_need(nx[0], "machine %s state %s" % [mc["id"], s["id"]])
				if not mc["_ix"].has(nx[1]):
					_fail("machine %s: no state %s" % [mc["id"], nx[1]])
			_check_set(s.get("set", {}), "machine %s state %s" % [mc["id"], s["id"]])
		if not mc["_ix"].has(mc["init"]):
			_fail("machine %s: no state %s" % [mc["id"], mc["init"]])
	for t in trips:
		_need(t["when"], "trip " + t["id"])
		_check_actions(t["do"], "trip " + t["id"])
	for a in alarms:
		for k in ["when", "clear", "suppress"]:
			if a.has(k):
				_need(a[k], "alarm %s.%s" % [a["id"], k])
	for o in ops:
		var w := "op %s %s" % [o["kks"], o["do"]]
		for nd in o.get("needs", []):
			_need(nd[0], w)
		_check_set(o.get("set", {}), w)
		if o.has("machine"):
			var mc = machine_by_id(o["machine"])
			if mc == null or not mc["commands"].has(o["do"]):
				_fail("%s: no machine command" % w)
		elif o["do"] == "set":
			_check_set({o["input"]: 0}, w)
		elif o["do"] == "reset" and trip_by_id(o.get("trip")) == null:
			_fail("%s: no trip %s" % [w, str(o.get("trip"))])
	for x in isolations:
		for pt in x["points"]:
			if pt.has("safe"):
				_need(pt["safe"], "isolation " + x["id"])
	for w in works:
		if w.has("isolation") and not isolation_ix.has(w["isolation"]):
			_fail("work %s: no isolation %s" % [w["id"], str(w["isolation"])])
		_check_set(w.get("set", {}), "work " + w["id"])
		for name in w.get("renews", []):        # REALISM.md §2.2: wear values, renewed under an isolation
			if not index.has(name) or values[index[name]][2] != "wear" or not w.has("isolation"):
				_fail("work %s: renews %s, not a wear value or without an isolation" % [w["id"], str(name)])


func _check_set(s: Dictionary, where: String) -> void:
	for k in s:
		if not index.has(k) or values[index[k]][2] != "state":
			_fail("%s: %s is not a state value" % [where, str(k)])


func _check_actions(acts: Array, where: String) -> void:
	for a in acts:
		if a.has("set"):
			_check_set(a["set"], where)
		else:
			var mc = machine_by_id(a["machine"])
			if mc == null or not mc["_ix"].has(a["to"]):
				_fail("%s: no machine state %s.%s" % [where, str(a["machine"]), str(a.get("to"))])


func _check_scenario(s: Dictionary) -> void:
	var w := "scenario " + str(s.get("id"))
	_reads_world = false
	_reads_wx = false
	for k in s.get("init", {}):
		if not (index.has(k) or ext.has(k)):
			_fail("%s: init names no value %s" % [w, k])
	for e in ext:
		if not s.get("init", {}).has(e):
			_fail("%s: init does not set ext value %s" % [w, e])
	for t in s.get("latched", []):
		if trip_by_id(t) == null:
			_fail("%s: no trip %s" % [w, t])
	for f in s.get("faults", []):
		_check_set(f["set"], "%s fault %s" % [w, f["id"]])
		if f.has("repair"):
			_check_set(f["repair"], "%s fault %s repair" % [w, f["id"]])
		for c in f.get("causes", []):       # hidden causes (REALISM.md §2.6)
			_check_set(c["set"], "%s fault %s cause %s" % [w, f["id"], str(c.get("id"))])
			if c.has("repair"):
				_check_set(c["repair"], "%s fault %s cause %s" % [w, f["id"], str(c.get("id"))])
			if typeof(c.get("weight")) == TYPE_STRING:
				_need(c["weight"], "%s fault %s cause %s" % [w, f["id"], str(c.get("id"))])
			if c.has("fixed"):
				_need(c["fixed"], "%s fault %s cause %s fixed" % [w, f["id"], str(c.get("id"))])
		if f.has("kks") and not codes.has(f["kks"]):
			_fail("%s fault %s: no equipment %s in the plant" % [w, f["id"], f["kks"]])
		if f.has("when"):
			if typeof(f["when"]) == TYPE_STRING:
				_need(f["when"], "%s fault %s" % [w, f["id"]])
			else:
				var kind := node_kind(f["when"])
				if kind == "" or kind == "const" or kind == "state" or STATEFUL.has(kind):
					_fail("%s fault %s: when is a value name or a stateless node" % [w, f["id"]])
				else:
					for r in node_refs(f["when"], kind):
						_need_ref(r, "%s fault %s" % [w, f["id"]])
	if (_content_reads_world or _reads_world) and not s.has("world"):
		_fail("%s: the content reads world_hour or world_day, which only a scenario with world has" % w)
	var wx = s.get("world", {}).get("weather") if typeof(s.get("world")) == TYPE_DICTIONARY else null
	if (_content_reads_wx or _reads_wx) and wx == null:
		_fail("%s: the content reads world_wx, which only a scenario with world.weather has" % w)
	if wx != null:
		var st = s.get("start", plant.get("clock", {}).get("start", {"day": 1, "time": "00:00"}))
		_check_weather(wx, w, (int(st["day"]) * 1440 + Staff.hhmm(st["time"])) * 600)


## weather.json as far as the engine reads it (REALISM.md §5.1; the validator checks the rest): every kind gives every
## driven value a table of rows, every hourly row names kinds, every day of the year is in a season, and every kind
## has a way on in every season (World.build_weather and the engine's _weather would otherwise read index -1).
func _check_weather_file() -> void:
	var kinds := []
	for k in weather.get("kinds", []):
		kinds.append(k.get("id") if typeof(k) == TYPE_DICTIONARY else null)
	if kinds.is_empty() or kinds.has(null):
		_fail("weather.json: no kinds, or a kind that is not an object")
		return
	for v in weather.get("values", []):
		if typeof(v) != TYPE_DICTIONARY or not is_num(v.get("tau")) or v["tau"] <= 0:
			_fail("weather.json: a driven value the engine can't read: %s" % str(v))
			return
	for k in weather["kinds"]:
		for v in weather.get("values", []):
			var t = k.get("targets", {}).get(v.get("id")) if typeof(k.get("targets")) == TYPE_DICTIONARY else null
			if typeof(t) != TYPE_ARRAY or t.is_empty():
				_fail("weather.json: kind %s gives no table of %s" % [str(k["id"]), str(v.get("id"))])
				return
			for row in t:
				if typeof(row) != TYPE_ARRAY or row.size() != 2 or not is_num(row[0]) or not is_num(row[1]):
					_fail("weather.json: kind %s: a row of %s that is not [x, y]" % [str(k["id"]), str(v.get("id"))])
					return
	var covered := {}
	for s in weather.get("seasons", []):
		if typeof(s) != TYPE_DICTIONARY or typeof(s.get("days")) != TYPE_ARRAY or s["days"].size() != 2 \
				or not kinds.has(s.get("start")) or typeof(s.get("hourly")) != TYPE_ARRAY:
			_fail("weather.json: a season the engine can't read")
			return
		for x in s["days"]:
			if typeof(x) != TYPE_INT or x < 1 or x > 365:
				_fail("weather.json: season %s: days of the year are 1 to 365" % str(s.get("id")))
				return
		for d in World.season_days(s["days"]):
			covered[d] = true
		var total := {}
		for r in s["hourly"]:
			if typeof(r) != TYPE_ARRAY or r.size() != 3 or not kinds.has(r[0]) or not kinds.has(r[1]):
				_fail("weather.json: season %s: an hourly row of kinds weather.json lacks" % str(s["id"]))
				return
			total[r[0]] = total.get(r[0], 0) + int(r[2])
		for k in kinds:
			if total.get(k, 0) < 1:
				_fail("weather.json: season %s: kind %s has no way on" % [str(s["id"]), str(k)])
				return
	for d in range(1, 366):
		if not covered.has(d):
			_fail("weather.json: day %d of the year is in no season" % d)
			return


## A scenario's world.weather names what weather.json has, and a script's entries are [day, "HH:MM", kind] with the
## first at or before the scenario's start (the engine would read no kind otherwise).
func _check_weather(wx, w: String, start: int) -> void:
	if weather == null or typeof(wx) != TYPE_DICTIONARY:
		_fail("%s: world.weather without weather.json" % w)
		return
	var kinds := []
	for k in weather.get("kinds", []):
		kinds.append(k.get("id"))
	if wx.has("season"):
		if not weather.get("seasons", []).any(func(x): return x.get("id") == wx["season"]):
			_fail("%s: no season %s" % [w, str(wx["season"])])
	elif wx.has("fixed"):
		if not kinds.has(wx["fixed"]):
			_fail("%s: no weather kind %s" % [w, str(wx["fixed"])])
	elif wx.has("script") and typeof(wx["script"]) == TYPE_ARRAY and not wx["script"].is_empty():
		for e in wx["script"]:
			if typeof(e) != TYPE_ARRAY or e.size() != 3 or typeof(e[0]) not in [TYPE_INT, TYPE_FLOAT] \
					or typeof(e[1]) != TYPE_STRING or not kinds.has(e[2]):
				_fail("%s: a weather script entry the engine can't read: %s" % [w, str(e)])
				return
		var e0: Array = wx["script"][0]
		if (int(e0[0]) * 1440 + Staff.hhmm(e0[1])) * 600 > start:
			_fail("%s: the weather script's first entry is after the scenario's start" % w)
	else:
		_fail("%s: world.weather is one of season, fixed or script" % w)


func machine_by_id(mid):
	for mc in machines:
		if mc["id"] == mid:
			return mc
	return null


func trip_by_id(tid):
	for t in trips:
		if t["id"] == tid:
			return t
	return null
