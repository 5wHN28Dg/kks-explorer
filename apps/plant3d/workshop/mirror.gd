## The Workshop's live mirror (docs/plant3d/WORKSHOP.md §6.5, milestone K6): a bench file's `mirror` entries resolved at
## the plant's equipment the Workshop was opened from, by that equipment's own bindings (no plant value name is in bench
## data), and the plant's values read through them. The engine writes what `read` gives over its step 2's values
## (sim/engine.gd set_mirror). The rules are the reference's (ref/plant3d_bench.py mirror_sources, UNITS); a test holds
## the two to the same answers.
##
##   var r := Mirror.resolve(bench_model, plant_model, "30MAA10")
##   # r.values: [[bench value, plant value, factor, offset]]  r.machines: [[bench machine, plant machine or "", else]]
##   # r.missing: [[bench value, why]]
##   var vs := Mirror.read(r, plant_engine)   # [{bench value: number}, {bench machine: state id}]
extends RefCounted

## A plant value's unit onto a bench value's: "bench|plant" -> [factor, offset], the bench's = the plant's × factor +
## offset (the reference's UNITS: gauge from absolute less 1.01325 bar; a metre of water 9.80665 kPa).
const UNITS := {"bar|kPa": [0.01, 0.0], "bar|MPa": [10.0, 0.0], "bar|mbar": [0.001, 0.0],
		"bar|kPa(a)": [0.01, -1.01325], "bar|bar(a)": [1.0, -1.01325], "bar|m": [0.0980665, 0.0]}


## The value names a plant binding reads, in its keys' order (`of`, show, a sound's gain and pitch).
static func _reads(x: Dictionary) -> Array:
	var out := []
	for k in ["of", "show"]:
		if typeof(x.get(k)) == TYPE_STRING:
			out.append(x[k])
	for k in ["gain", "pitch"]:
		if typeof(x.get(k)) == TYPE_DICTIONARY and typeof(x[k].get("of")) == TYPE_STRING:
			out.append(x[k]["of"])
	return out


## The plant machine a code's equipment runs by, mapped onto a bench machine with `states` (its state ids) by name: of
## the machines at the code, in the model's order, the first whose states are all the bench machine's (a gas turbine's
## start-up sequence, not its compressor wash); else the same among those at the code of a value the code's bindings
## read (a casing on another's shaft); null without.
static func plant_machine(pm, code: String, states: Array) -> Variant:
	for mc in pm.machines:
		if mc.get("kks") == code and _fits(mc, states):
			return mc
	for x in pm.bind:
		if x.get("kks") != code:
			continue
		for r in _reads(x):
			if not pm.index.has(r):
				continue
			var k = pm.values[pm.index[r]][1].get("kks")
			for mc in pm.machines:
				if k != null and mc.get("kks") == k and _fits(mc, states):
					return mc
	return null


static func _fits(mc: Dictionary, states: Array) -> bool:
	for st in mc["states"]:
		if not String(st["id"]) in states:
			return false
	return true


## Where each of bench model `bm`'s mirror entries comes from at the plant's equipment `code` (plant model `pm`).
static func resolve(bm, pm, code: String) -> Dictionary:
	var out := {"values": [], "machines": [], "missing": []}
	var binds := []
	for x in pm.bind:
		if x.get("kks") == code:
			binds.append(x)
	for x in bm.mirror:
		var f: Dictionary = x["from"]
		var v := String(x["value"])
		if f.has("machine"):
			var mid := v.trim_suffix("_state")
			var pid := ""
			var bst := []
			var bmc = bm.machine_by_id(mid)
			if bmc != null:
				for st in bmc["states"]:
					bst.append(String(st["id"]))
			var pmc = plant_machine(pm, code, bst)
			if pmc is Dictionary:
				pid = String(pmc.get("id", ""))
			if pid != "" or f.has("else"):
				out.machines.append([mid, pid, String(f.get("else", ""))])
			else:
				out.missing.append([v, "no machine runs %s" % code])
			continue
		# the plant's binding of that kind at the code (and of the entry's channel, kind or sound): a show names its value,
		# an anim and a lamp read `of`, a sound its gain's `of`
		var k := String(f["bind"])
		var detail := ""
		for dk in ["channel", "kind", "id"]:
			if f.has(dk):
				detail = String(f[dk])
		var src := ""
		for b in binds:
			if not b.has(k) or (detail != "" and String(b[k]) != detail):
				continue
			if detail == "":
				src = String(b[k])
			elif b.has("of"):
				src = String(b["of"])
			elif typeof(b.get("gain")) == TYPE_DICTIONARY:
				src = String(b["gain"]["of"])
			if src != "":
				break
		if src == "":
			out.missing.append([v, "no %s binding at %s" % [(k + " " + detail).strip_edges(), code]])
			continue
		var bu := String(bm.units.get(v, ""))
		var pu := ""
		if pm.index.has(src):
			pu = String(pm.values[pm.index[src]][1].get("unit", ""))
		if bu == pu:
			out.values.append([v, src, 1.0, 0.0])
		elif UNITS.has(bu + "|" + pu):
			var fo: Array = UNITS[bu + "|" + pu]
			out.values.append([v, src, fo[0], fo[1]])
		else:
			out.missing.append([v, "%s is in %s, the bench's %s in %s" % [src, pu if pu != "" else "no unit", v,
					bu if bu != "" else "no unit"]])
	return out


## The plant's values and machine states now (plant engine `pe`) as the bench's: [values, states] for set_mirror. A
## plant machine in a state the bench machine doesn't have is left out (the bench's own then).
static func read(r: Dictionary, pe) -> Array:
	var vals := {}
	var states := {}
	if pe == null:
		return [vals, states]
	for x in r.values:
		var i: int = pe.ix.get(x[1], -1)
		if i >= 0:
			vals[x[0]] = pe.cur[i] * float(x[2]) + float(x[3])
	for x in r.machines:
		if x[1] == "":
			states[x[0]] = x[2]
			continue
		var i: int = pe.ix.get(x[1] + "_state", -1)
		var mc = pe.m.machine_by_id(x[1])
		if i >= 0 and mc != null:
			var k := int(pe.cur[i])
			if k >= 0 and k < mc["_ids"].size():
				states[x[0]] = mc["_ids"][k]
	return [vals, states]


## The bench's names of what is mirrored (values and machines) and of what isn't, with why.
static func words_of(r: Dictionary) -> Dictionary:
	var got := []
	for x in r.values:
		got.append(String(x[0]))
	for x in r.machines:
		got.append(String(x[0]) + " state")
	return {"mirrored": got, "missing": r.missing}
