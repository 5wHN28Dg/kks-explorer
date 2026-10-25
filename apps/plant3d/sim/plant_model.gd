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

const STATELESS := ["const", "state", "of", "sum", "product", "min", "max", "diff", "select", "cmp", "and", "or", "not"]
const STATEFUL := ["lag", "ramp", "integrate", "latch", "delay", "timer", "wrap", "hold"]

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
var scenarios := {}                   # id -> scenario, in file-name order
var procedures := {}                  # id -> procedure, in file-name order
var staff = null                      # sim/staff.gd: staff.json (§16), or null


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
	for rel in ["plant.json", "kit.json", "sounds.json", "staff.json"]:
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
	for sid in scenarios:
		_check_scenario(scenarios[sid])


func _add_model(d: Dictionary, rel: String) -> void:
	for pair in d.get("values", []):
		var name: String = pair[0]
		var kind := node_kind(pair[1])
		if kind == "":
			_fail("%s: value %s: not a node of format 1" % [rel, name])
			return
		if index.has(name):
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


## The values the engine keeps for permits and isolations (§15.1, §15.3), in slot order.
func kept() -> Array:
	var out := []
	for x in isolations:
		out.append(x["id"] + "_locked")
		out.append(x["id"] + "_complete")
	for w in works:
		out.append(w["id"] + "_permit")
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
