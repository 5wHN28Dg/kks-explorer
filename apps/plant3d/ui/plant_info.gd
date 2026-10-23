## What the trainee is told about a piece of equipment (docs/PLANT3D.md §6, §7): its name, the plain-language
## meaning of its KKS code from the plant's own key table, its values with their units, its operations with their
## permissives, its alarms, trips and start sequence. Built once from the model (sim/plant_model.gd); everything
## here only reads the model and the engine.
extends RefCounted

const PlantModel = preload("res://sim/plant_model.gd")
const Links = preload("res://sim/links.gd")

var m                              # PlantModel
var names := {}                    # code -> name (equipment, parts, pipes, inline parts, structures)
var area_of := {}                  # code -> area id
var area_titles := {}              # area id -> title
var bounds := {}                   # area id -> [[x0, y0], [x1, y1]] (plant coordinates)
var values_of := {}                # code -> [value names with a unit] in model order
var ops_of := {}                   # code -> [ops] in model order
var alarms_of := {}                # code -> [alarm positions in m.alarms]
var trips_of := {}                 # code -> [trip positions in m.trips]
var machine_of := {}               # code -> machine position in m.machines
var lamps_of := {}                 # code -> [[kind, value]]
var position_of := {}              # code -> the value a stem, disc or blades binding moves (0–1)
var units := {}                    # value name -> unit
var parts := {}                    # code -> the kit part it is drawn with (equipment and its parts)


func _init(model) -> void:
	m = model
	for a in m.areas:
		area_titles[a["id"]] = a.get("title", a["id"])
		bounds[a["id"]] = a.get("bounds", [])
		for e in a.get("equipment", []):
			_name(e, a["id"])
			for c in e.get("parts", []):
				_name(c, a["id"])
		for p in a.get("pipes", []):
			_name(p, a["id"])
			for kind in ["valves", "parts"]:
				for v in p.get(kind, []):
					_name(v, a["id"])
		for s in a.get("structures", []):
			if s.has("kks"):
				names[s["kks"]] = s.get("name", _structure_name(s))
				area_of[s["kks"]] = a["id"]
	for v in m.values:
		var nd: Dictionary = v[1]
		if nd.has("unit"):
			units[v[0]] = nd["unit"]
			if nd.has("kks"):
				_add(values_of, nd["kks"], v[0])
	for b in m.bind:
		if b.has("show") and not values_of.get(b["kks"], []).has(b["show"]):
			_add(values_of, b["kks"], b["show"])
		elif b.has("lamp"):
			_add(lamps_of, b["kks"], [b["lamp"], b["of"]])
		elif b.get("anim", "") in ["stem", "disc", "blades"] and not position_of.has(b["kks"]):
			position_of[b["kks"]] = b["of"]
	for o in m.ops:
		_add(ops_of, o["kks"], o)
	for k in m.alarms.size():
		var a: Dictionary = m.alarms[k]
		if a.has("kks"):
			_add(alarms_of, a["kks"], k)
		if a.has("where") and a.get("where") != a.get("kks"):
			_add(alarms_of, a["where"], k)
	for k in m.trips.size():
		if m.trips[k].has("kks"):
			_add(trips_of, m.trips[k]["kks"], k)
	for k in m.machines.size():
		if m.machines[k].has("kks"):
			machine_of[m.machines[k]["kks"]] = k


func _name(e: Dictionary, area: String) -> void:
	names[e["kks"]] = e.get("name", "")
	area_of[e["kks"]] = area
	if e.has("part"):
		parts[e["kks"]] = e["part"]


func part_of(code: String) -> String:
	return parts.get(code, "")


## The operator desks of the plant (`operator_desk` parts), in content order: their screens are worked there.
func desks() -> Array:
	var out := []
	for c in parts:
		if parts[c] == "operator_desk":
			out.append(c)
	return out


static func _structure_name(s: Dictionary) -> String:
	return String(s.get("part", "structure")).capitalize()


static func _add(d: Dictionary, k, item) -> void:
	if not d.has(k):
		d[k] = []
	d[k].append(item)


## Every code the plant knows (its content's codes) or that its model operates.
func has_code(code: String) -> bool:
	return names.has(code) or ops_of.has(code) or m.codes.has(code)


func name_of(code: String) -> String:
	return names.get(code, "")


## The code's meaning, one line per KKS level, in the plant's own words (plant.json `kks`); a level whose letters
## are not in the plant's key says so.
func meaning(code: String) -> PackedStringArray:
	var out := PackedStringArray()
	var g := Links.kks_parts(code)
	if g.is_empty():
		return out
	var d := Links.decode(code, m.plant["kks"])
	out.append("Unit %s: %s" % [g[0], d.unit if d.unit != null else "not in this plant's key"])
	out.append("System %s%s: %s" % [g[2], g[3], d.system if d.system != null else "not in this plant's key"])
	if g[4] != "":
		var what: String = d.equipment if d.equipment != null else "not in this plant's key"
		out.append("%s %s: %s, number %s%s" % ["Measurement" if m.plant["kks"]["measurements"].has(g[4]) else "Equipment",
				g[4], what, g[5], (" " + g[6]) if g[6] != "" else ""])
	return out


## A value as the trainee reads it: the number in its unit, with sensible decimals ("pu" is shown in per cent).
func fmt(name: String, x: float) -> String:
	var u: String = units.get(name, "")
	if u == "pu":
		return "%s %%" % num(x * 100.0)
	return (num(x) + " " + u).strip_edges()


static func num(x: float) -> String:
	var a := absf(x)
	if a >= 100.0 or a == 0.0:
		return "%.0f" % x
	if a >= 10.0:
		return "%.1f" % x
	if a >= 0.1:
		return "%.2f" % x
	return "%.3f" % x


const WORDS := {"hp": "HP", "ip": "IP", "lp": "LP", "st": "ST", "gt1": "GT 1", "cw": "CW", "ct": "cooling tower",
	"fw": "feedwater", "ccw": "closed cooling water", "ia": "instrument air", "aux": "auxiliary steam", "cep": "condensate pump",
	"spd": "speed", "rpm": "speed", "pos": "position", "q": "flow", "p": "pressure", "t": "temperature",
	"tsat": "saturation temperature", "tw": "metal temperature", "vib": "vibration", "amps": "current", "lvl": "level",
	"exh": "exhaust", "sp": "set point", "tgt": "target", "rt": "run time", "f": "frequency", "ph": "phase",
	"mw": "power", "ecc": "eccentricity", "cond": "condenser", "lube": "lube oil", "evap": "evaporation",
	"gen": "steam made", "cap": "capacity", "da": "deviation", "cpd": "compressor discharge", "ws": "wheel space",
	"byp": "bypass", "mk": "makeup", "hw": "hotwell", "vac": "vacuum", "brk": "breaker", "v": "valve", "l1": "level 1",
	"l2": "level 2", "l3": "level 3", "p1": "pressure 1", "p2": "pressure 2", "p3": "pressure 3", "psat": "saturation pressure"}


## The value's name in words ("cw_a_amps" reads as "CW A current").
static func value_label(name: String) -> String:
	var out := PackedStringArray()
	for w in name.split("_"):
		if WORDS.has(w):
			out.append(WORDS[w])
		elif w.begins_with("tc") and w.substr(2).is_valid_int():
			out.append("thermocouple " + w.substr(2))
		elif w.length() == 1:
			out.append(w.to_upper())
		else:
			out.append(w)
	var s := " ".join(out)
	return s.left(1).to_upper() + s.substr(1)


func op_label(o: Dictionary) -> String:
	var d: String = o["do"]
	match d:
		"close_breaker": return "Close breaker"
		"open_breaker": return "Open breaker"
		"stop_travel": return "Stop travel"
		# a motor valve's handwheel at the valve, while its actuator has no supply (PLANT3D §7.2, FIRST-TRAIN §4)
		"hand_open": return "Open by handwheel"
		"hand_close": return "Close by handwheel"
		"hand_stop": return "Stop turning"
		"set": return "Set"
		"reset":
			var t = m.trip_by_id(o["trip"])
			return "Reset: %s" % (t.get("text", o["trip"]) if t != null else o["trip"])
	return d.capitalize()


## A failed permissive or check in words (an op's refusal lists value names, §7.2).
func failed_text(o: Dictionary, failed: String, engine) -> String:
	for nd in o.get("needs", []):
		if nd[0] == failed:
			return nd[1]
	if o.has("machine") and failed == o["machine"] + "_state":
		var mi: int = machine_index(o["machine"])
		var here := state_name(mi, engine)
		var spec: Dictionary = m.machines[mi]["commands"][o["do"]]
		var from = spec["from"]
		var allowed: String = "any state" if typeof(from) == TYPE_STRING else ", ".join(from.map(func(s): return String(s).replace("_", " ")))
		return "The sequence is at \"%s\": %s is taken only at %s" % [here.replace("_", " "), o["do"], allowed]
	if o["do"] == "reset" and failed == o["trip"] + "_latched":
		return "The trip is not latched: nothing to reset"
	if o["do"] == "reset":
		return "The cause of the trip is still there: it can be reset only once it has cleared"
	if o["do"] == "set" and failed == o["input"]:
		if o["range"][0] == 0 and o["range"][1] == 1:
			return "The value must be between 0 and 100 %"
		return "The value must be between %s and %s" % [num(o["range"][0]), num(o["range"][1])]
	if failed.ends_with("_locked") and m.isolation_ix.has(failed.trim_suffix("_locked")):
		return lock_words(failed.trim_suffix("_locked"), engine)
	return failed


## A lock that refuses an op (PLANT3D §15.1) in words: the isolation and the permit holding it.
func lock_words(iso_id: String, engine) -> String:
	var k: int = m.isolation_ix[iso_id]
	var h: int = engine.holder[k] if engine != null else -1
	var num: String = String(engine.ptw.get(m.works[h]["id"], "")) if h >= 0 else ""
	return "Locked out for work: %s%s. It works again when the permit's locks are removed" % [
			m.isolations[k]["text"], (" (" + num + ")") if num != "" else ""]


func machine_index(mid: String) -> int:
	for k in m.machines.size():
		if m.machines[k]["id"] == mid:
			return k
	return -1


func state_name(mi: int, engine) -> String:
	return m.machines[mi]["_ids"][engine.mstate[mi]]


## The line the control room screen shows for a machine's state (`say`), or "".
func state_say(mi: int, engine) -> String:
	return m.machines[mi]["states"][engine.mstate[mi]].get("say", "")


## Permissives of an op as they stand now: [[sentence, ok]] (read from the values the next step's check reads).
func permissives(o: Dictionary, engine) -> Array:
	var out := []
	for nd in o.get("needs", []):
		out.append([nd[1], engine.truth(nd[0])])
	if o.has("machine"):
		var mi := machine_index(o["machine"])
		var from = m.machines[mi]["commands"][o["do"]]["from"]
		var ok: bool = typeof(from) == TYPE_STRING or from.has(state_name(mi, engine))
		if not ok:
			out.append([failed_text(o, o["machine"] + "_state", engine), false])
	elif o["do"] == "reset":
		var t = m.trip_by_id(o["trip"])
		if engine.v(o["trip"] + "_latched") < 0.5:
			out.append(["The trip is not latched", false])
		elif t != null and engine.truth(t["when"]):
			out.append(["The cause of the trip is still there", false])
	# a locked code refuses every op (PLANT3D §15.1)
	for name in engine._locking(o["kks"]):
		out.append([lock_words(String(name).trim_suffix("_locked"), engine), false])
	return out


## Where the trainee can do an op from here: "local" within reach of the equipment, "screen" at a desk whose screens
## show its code (PLANT3D §14: the main control room's, or the water treatment plant's own).
static func offered(o: Dictionary, near: bool, in_control: bool) -> bool:
	var w: Array = o.get("where", ["local", "screen"])
	return (near and w.has("local")) or (in_control and w.has("screen"))


## The equipment's state in a few words: lamps, position, start sequence, latched trips.
func state_words(code: String, engine) -> PackedStringArray:
	var out := PackedStringArray()
	for l in lamps_of.get(code, []):
		var on: bool = engine.truth(l[1])
		match l[0]:
			"running": out.append("Running" if on else "Stopped")
			"stopped": out.append("Stopped" if on else "Running")
			"open": out.append("Open" if on else "Not open")
			"closed": out.append("Closed" if on else "Not closed")
			"fault": if on: out.append("Fault")
			"beacon": if on: out.append("Beacon on")
	if position_of.has(code):
		out.append("Position %s %%" % num(engine.v(position_of[code]) * 100.0))
	if machine_of.has(code):
		var mi: int = machine_of[code]
		var s := "Sequence: %s" % state_name(mi, engine).replace("_", " ")
		var say := state_say(mi, engine)
		out.append(s + ((" — " + say) if say != "" else ""))
	for k in trips_of.get(code, []):
		if engine.latched[k]:
			out.append("Tripped: %s" % m.trips[k].get("text", m.trips[k]["id"]))
	return out
