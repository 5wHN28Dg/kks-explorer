extends RefCounted
## Walkdown Plant's job safety analyses and toolbox talks (docs/plant3d/REALISM.md §8.1, settled in §8.6; milestone
## HS1) as the engine runs them: the `jsa` and `talk` inputs, the issue refused without a JSA, the talk's attendance.
## Bit for bit with ref/plant3d_hse.py on ref/vectors/plant3d-realism.json's `hse`. Gated by the plant's hse.json
## (plant_model.gd's `hse`): a plant without it never calls in here.
##
## The engine's state (saved with a run, in the digest): jsa_of (work id -> [hazard ids, control ids, person]) and
## talked (work id -> the attendees' person indices, in order).

const JSA_HAZARDS := 32
const JSA_CONTROLS := 64
const POINTS := 32
const JSA_STATES := [0, 1, 2, 3, 9, 10]     # a JSA is made before its permit is issued
const TALK_STATES := [1, 2, 3, 4, 5]        # a talk is given for an open permit before its work is done


## Whether x is a list of lo–hi ids of ix without repeats.
static func _ids(x, ix: Dictionary, lo: int, hi: int) -> bool:
	if typeof(x) != TYPE_ARRAY or x.size() < lo or x.size() > hi:
		return false
	var seen := {}
	for y in x:
		if typeof(y) != TYPE_STRING or not ix.has(y) or seen.has(y):
			return false
		seen[y] = true
	return true


## The work's index when it is a work with `jsa` of a plant with hse.json, else -1.
static func _work(e, work) -> int:
	if e.m.hse == null or typeof(work) != TYPE_STRING or not e.m.work_ix.has(work):
		return -1
	var wi: int = e.m.work_ix[work]
	return wi if e.m.works[wi].has("jsa") else -1


## `[jsa, work, hazards, controls, person]`, in step 1: its result, its event made.
static func jsa(e, item: Array, npc: bool) -> String:
	var work = item[1]
	var hz = item[2]
	var cs = item[3]
	var person = item[4]
	var wi := _work(e, work)
	if wi == -1 or not _ids(hz, e.m.hse["hazard_ix"], 1, JSA_HAZARDS) \
			or not _ids(cs, e.m.hse["control_ix"], 0, JSA_CONTROLS):
		e._ev(["jsa", work, hz, cs, person, "unknown", []])
		return "unknown"
	var why := []
	if e._authority(person, npc, "jsa"):
		why.append("authority")
	if not JSA_STATES.has(e.pstate[wi]):
		why.append("state")
	if not why.is_empty():
		e._ev(["jsa", work, hz, cs, person, "refused", why])
		return "refused"
	e.jsa_of[work] = [hz.duplicate(), cs.duplicate(), person]
	e._ev(["jsa", work, hz, cs, person, "done", []])
	return "done"


## The people at the giver's talk, in people order: the giver and everyone else on duty at a place of the room of the
## giver's place; at a place of no room, at that same place; the giver at no place, the giver alone.
static func attendees(e, person) -> Array:
	var sm = e._sm
	if sm == null or typeof(person) != TYPE_STRING or not sm.person_ix.has(person):
		return []
	var gi: int = sm.person_ix[person]
	var gp: int = e.sp_pos[gi]
	if gp == -1:
		return [gi]
	var room = sm.places[gp].get("room")
	var where := {}
	if room != null:
		for j in sm.rooms[room]:
			where[j] = true
	else:
		where[gp] = true
	var out := []
	for qi in sm.people.size():
		if qi == gi or e.sp_on[qi] and e.sp_pos[qi] != -1 and where.has(e.sp_pos[qi]):
			out.append(qi)
	return out


## `[talk, work, points, person]`, in step 1: its result, its event made.
static func talk(e, item: Array, npc: bool) -> String:
	var work = item[1]
	var pts = item[2]
	var person = item[3]
	var wi := _work(e, work)
	if wi == -1 or not _ids(pts, e.m.hse["hazard_ix"], 1, POINTS):
		e._ev(["talk", work, pts, person, "unknown", [], []])
		return "unknown"
	var why := []
	if e._authority(person, npc, "jsa"):
		why.append("authority")
	if not TALK_STATES.has(e.pstate[wi]):
		why.append("state")
	if not e.jsa_of.has(work):
		why.append("jsa")
	if not why.is_empty():
		e._ev(["talk", work, pts, person, "refused", why, []])
		return "refused"
	var came := attendees(e, person)
	var att := {}
	for i in e.talked.get(work, []):
		att[i] = true
	for i in came:
		att[i] = true
	if not att.is_empty():      # (free mode's talk: attended by nobody)
		var keys: Array = att.keys()
		keys.sort()
		e.talked[work] = keys
	var ids := []
	for i in came:
		ids.append(e._sm.people[i]["id"])
	e._ev(["talk", work, pts, person, "done", [], ids])
	return "done"


## Whether an issue lacks its JSA (refused `jsa`).
static func issue_refused(e, wi: int) -> bool:
	return e.m.hse != null and e.m.works[wi].has("jsa") and not e.jsa_of.has(e.m.works[wi]["id"])


## A close or cancel of the work's permit ends its JSA and the talk's attendance.
static func cleared(e, work: String) -> void:
	e.jsa_of.erase(work)
	e.talked.erase(work)


## The work's own list: [hazard ids, control ids].
## The work's own list (§8.6): [hazard ids, control ids]; empty lists for anything but a work with `jsa` (an NPC
## step's task without a work: its input is then `unknown`, as a permit step's is).
static func own(e, work) -> Array:
	var wi := _work(e, work)
	if wi == -1:
		return [[], []]
	return e.m.hse["own"][e.m.works[wi]["jsa"]]


## Per work with `jsa`, in model order: [has a JSA, hazard indices, control indices, person index or -1, attendees].
static func digest_part(e) -> Array:
	var out := []
	for w in e.m.works:
		if not w.has("jsa"):
			continue
		var j = e.jsa_of.get(w["id"])
		var hz := PackedInt32Array()
		var cs := PackedInt32Array()
		var pi := -1
		if j != null:
			for h in j[0]:
				hz.append(e.m.hse["hazard_ix"][h])
			for c in j[1]:
				cs.append(e.m.hse["control_ix"][c])
			if e._sm != null and typeof(j[2]) == TYPE_STRING and e._sm.person_ix.has(j[2]):
				pi = e._sm.person_ix[j[2]]
		out.append([1 if j != null else 0, hz, cs, pi, PackedInt32Array(e.talked.get(w["id"], []))])
	return out


static func snapshot_part(e, s: Dictionary) -> void:
	var out := {}
	for w in e.m.works:
		var wid: String = w["id"]
		if not e.jsa_of.has(wid) and not e.talked.has(wid):
			continue
		var x := {}
		if e.jsa_of.has(wid):
			var j: Array = e.jsa_of[wid]
			x["jsa"] = [j[0].duplicate(), j[1].duplicate(), j[2]]
		if e.talked.has(wid):
			var ids := []
			for i in e.talked[wid]:
				ids.append(e._sm.people[i]["id"])
			x["talk"] = ids
		out[wid] = x
	if not out.is_empty():
		s["hse"] = out


## hse.json as far as the engine reads it (REALISM.md §8.6; the validator checks the rest): the ids, and each job's own
## list (its hazards in order and their controls in order, each once). null when it can't be read.
static func read_library(d):
	if typeof(d) != TYPE_DICTIONARY:
		return null
	# (titles: the forms' and the debrief's words, not the engine's)
	var out := {"hazard_ix": {}, "control_ix": {}, "own": {}, "hazards": [], "controls": [], "titles": {}}
	var answers := {}
	for c in d.get("controls", []):
		if typeof(c) != TYPE_DICTIONARY or typeof(c.get("id")) != TYPE_STRING:
			return null
		out["control_ix"][c["id"]] = out["control_ix"].size()
		out["controls"].append(c["id"])
		out["titles"]["c:" + c["id"]] = str(c.get("title", c["id"]))
	for h in d.get("hazards", []):
		if typeof(h) != TYPE_DICTIONARY or typeof(h.get("id")) != TYPE_STRING or typeof(h.get("controls")) != TYPE_ARRAY:
			return null
		out["hazard_ix"][h["id"]] = out["hazard_ix"].size()
		out["hazards"].append(h["id"])
		out["titles"]["h:" + h["id"]] = str(h.get("title", h["id"]))
		answers[h["id"]] = h["controls"]
	for j in d.get("jobs", []):
		if typeof(j) != TYPE_DICTIONARY or typeof(j.get("id")) != TYPE_STRING or typeof(j.get("hazards")) != TYPE_ARRAY:
			return null
		var cs := []
		for h in j["hazards"]:
			if not answers.has(h):
				return null
			for c in answers[h]:
				if not cs.has(c):
					cs.append(c)
		out["own"][j["id"]] = [j["hazards"].duplicate(), cs]
		out["titles"]["j:" + j["id"]] = str(j.get("title", j["id"]))
	return out
