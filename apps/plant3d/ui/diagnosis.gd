## The debrief's diagnosis tab (docs/plant3d/REALISM.md §3.2, §2.22; milestone HW3): for each fault with hidden causes
## made in the run, its cause (shown now, in the debrief, not before), the tests made at its equipment in order with
## what each pointed to or ruled out, the fixes made (the right one, or one that wasn't the cause's), the parts used
## (and whether they were needed), the time from the fault to the first test that pointed to its cause alone (or the
## first right fix), and whether it was put right. Read from the run's events and inputs and the kind's service file
## (`causes`, `tests`, `fixes`, `parts`), so it is a view only: nothing here is in the engine.
extends RefCounted

## [{fault, text, kks, kind, cause, cause_title, found, component, bench, made, repaired, found_at, rows, parts}]
## up to event `to`. `jobs`: work_view.gd's {code: {kind, alias, loop, service}}; `run_sc`: the run's scenario.
static func review(engine, jobs: Dictionary, to: int, run_sc := {}) -> Array:
	var out: Array = []
	var evs: Array = engine.events
	to = mini(to, evs.size())
	for i in to:
		var ev: Array = evs[i]
		if ev[1] != "cause":
			continue
		var fid: String = ev[2]
		var cause: String = ev[3]
		var f := _fault(engine.m, fid, run_sc)
		var kks: String = String(f.get("kks", ""))
		if not jobs.has(kks):
			continue
		out.append(_one(engine, jobs[kks], f, cause, i, to))
	return out


static func _fault(m, fid: String, run_sc: Dictionary) -> Dictionary:
	for sc in [run_sc] + m.scenarios.values():
		for f in sc.get("faults", []):
			if f.get("id", "") == fid:
				return f
	return {}


static func _one(engine, job: Dictionary, f: Dictionary, cause: String, at: int, to: int) -> Dictionary:
	var s: Dictionary = job["service"]
	var alias: String = job["alias"]
	var kks: String = f["kks"]
	var evs: Array = engine.events
	var c := {}
	var titles := {}
	for x in s.get("causes", []):
		titles[x["id"]] = String(x["title"])
		if x["id"] == cause:
			c = x
	var by_action := {}
	var by_meter := {}
	for t in s.get("tests", []):
		if t.has("action"):
			by_action[String(t["action"])] = t
		else:
			by_meter[String(t["meter"]).replace("$_", alias + "_")] = t
	var fixes := {}
	for x in s.get("fixes", []):
		fixes[String(x[0])] = x[1]
	var parts := {}
	for x in s.get("parts", []):
		parts[String(x[0])] = [String(x[1]), String(x[2])]
	var acts := {}
	for a in s.get("actions", []):
		acts[String(a["action"])] = String(a["title"])
	var r := {"fault": f["id"], "text": String(f.get("text", f["id"])), "kks": kks, "kind": job["kind"],
			"cause": cause, "cause_title": titles.get(cause, cause), "found": String(c.get("found", "")),
			"component": String(c.get("component", "")), "bench": String(c.get("bench", "")),
			"made": int(evs[at][0]), "repaired": -1, "found_at": -1, "rows": [], "parts": []}
	var inputs: Array = engine.inputs
	for i in range(at + 1, to):
		var ev: Array = evs[i]
		var n := int(ev[0])
		if ev[1] == "repair" and ev[2] == f["id"] and r.repaired == -1:
			r.repaired = n
		elif ev[1] == "fault" and ev[2] == f["id"]:
			break                   # made again (a trainer's fault after a repair): its own review follows
		elif ev[1] == "hand" and ev[2] == kks and ev[6] == "done":
			var act: String = ev[3]
			var who = ev[5]
			if by_action.has(act):
				_test(r, n, who, by_action[act], cause, titles)
			if fixes.has(act):
				_fix(r, n, who, acts.get(act, act), fixes[act], cause)
			if parts.has(act):
				r.parts.append({"step": n, "who": who, "part": parts[act][1], "needed": cause in fixes.get(act, [])})
		elif ev[1] == "op" and ev[2] == kks and ev.size() > 7 and ev[4] == "done" and ev[6] == "hart":
			var key := "hart:%s" % ev[3]
			if fixes.has(key):
				_fix(r, n, ev[7], "Sensor trim through the communicator" if ev[3] == "set" else key, fixes[key], cause)
		elif ev[1] == "read" and ev[3] == kks and ev[5] != "tool":
			var meter := ""
			for inp in inputs:              # the reading's meter, from the input that made it (a player's)
				if int(inp[0]) == n and inp[1] == "read" and inp[2] == kks and inp.size() > 4:
					meter = String(inp[4])
					break
			if by_meter.has(meter):
				_test(r, n, ev[2], by_meter[meter], cause, titles)
	return r


static func _test(r: Dictionary, n: int, who, t: Dictionary, cause: String, titles: Dictionary) -> void:
	var shows: Array = t["shows"]
	var names := PackedStringArray()
	for x in shows:
		names.append(String(titles.get(x, x)).to_lower())
	var v := ""
	if cause in shows:
		v = ("pointed to the cause: " if shows.size() == 1 else "pointed to ") + " or ".join(names)
		if shows.size() == 1 and r.found_at == -1:
			r.found_at = n
	else:
		v = "ruled out " + " and ".join(names)
	r.rows.append({"step": n, "who": who, "kind": "test", "title": String(t["title"]), "verdict": v,
			"right": cause in shows})


static func _fix(r: Dictionary, n: int, who, title: String, cures: Array, cause: String) -> void:
	var right: bool = cause in cures
	if right and r.found_at == -1:
		r.found_at = n
	r.rows.append({"step": n, "who": who, "kind": "fix", "title": title,
			"verdict": "the cause's fix" if right else "not this cause's fix", "right": right})


## The review as lines: the fault and its cause, what was found, each row with its model time and who, the parts,
## the time to find it (clock minutes) and the outcome. `tpm`: steps in a clock minute (the staff's).
## Before the fault is put right (and while the run or its procedure goes on: `over` false), the cause stays hidden,
## and with it every verdict: only how many tests were made.
static func lines(r: Dictionary, model_time: Callable, tpm: float, over := false) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("%s  %s" % [model_time.call(r.made), r.text])
	if not shown(r, over):
		out.append("Under investigation: the cause and what each test showed appear here once it is put right " +
				"(or the run is over). Tests made so far: %d." % r.rows.filter(func(x): return x.kind == "test").size())
		return out
	out.append("The cause: %s. %s" % [r.cause_title, r.found])
	if r.rows.is_empty():
		out.append("No test or fix was made at %s." % r.kks)
	for x in r.rows:
		out.append("%s  %s%s: %s" % [model_time.call(x.step), String(x.title),
				(" (%s)" % x.who) if x.who != null else "", x.verdict])
	for p in r.parts:
		out.append("%s  Used: %s%s" % [model_time.call(p.step), p.part,
				"" if p.needed else " (not needed: it wasn't the cause)"])
	if r.found_at >= 0:
		out.append("Found %d min after the fault was made." % roundi((r.found_at - r.made) / maxf(tpm, 1.0)))
	else:
		out.append("The cause was not found.")
	out.append("Put right." if r.repaired >= 0 else "Not put right: the fault is still there.")
	return out


## Whether a review may show its cause: once its fault is put right, or the run (its procedure) is over.
static func shown(r: Dictionary, over: bool) -> bool:
	return over or int(r.repaired) >= 0
