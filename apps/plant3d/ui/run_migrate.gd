## A saved run of another build brought into this one (issue #447; apps/plant3d/README.md "Saved runs"): the engine
## is deterministic and every change a run makes to the plant is an input in the engine's log (sim/engine.gd `_q`:
## [step, kind, …]), so the run is made again: a fresh engine of this build, from this build's content, of the saved
## scenario, fed every saved input at its step, stepped to the saved step. The procedure's progress, the panels'
## records and the trainee's place are kept as saved; the positions in the event list that the procedure's progress
## holds are moved to the same model steps in the new event list (the plant may come out a little differently where the
## model changed: the trainee's actions are the same).
##
## What can't be made again is said in words (why_not): a scenario this plant hasn't, a shared session's run, an input
## of a kind this build doesn't know (a save of a newer build) or of the wrong shape. The run is made in pieces
## (advance) so the app can show its progress; nothing of the saved run is changed while it is made.
extends RefCounted

const PlantEngine = preload("res://sim/engine.gd")
const RunSave = preload("res://ui/run_save.gd")
const Tracker = preload("res://ui/procedure_tracker.gd")
const Inputs = preload("res://ui/inputs.gd")
const W = preload("res://ui/widgets.gd")

## Every input kind the engine takes (sim/engine.gd apply_input) and the lengths of its item (without the step).
const INPUT_SIZES := {"op": [5, 7], "ack": [2], "shelve": [3], "unshelve": [2], "fault": [2, 3], "repair": [2, 4],
		"permit": [4], "lock": [4], "unlock": [4], "remove_lock": [5, 6], "role": [2], "release": [1],
		"task_ack": [1], "arrive": [2], "leave": [2], "read": [3, 4], "say": [3], "pick": [2], "call": [4],
		"jump": [2, 3], "ppe": [3], "zone": [3], "stop": [2], "board": [3], "alight": [3],
		"get_on": [2], "drive": [3, 4], "weather": [2], "tool": [4], "hand": [6], "audio": [2], "phone": [2],
		"jsa": [5], "talk": [4], "wo": [5], "discuss": [4], "issue": [5], "order": [4]}

var e                           # the engine being made
var p: Dictionary               # the saved payload (not changed)
var target := 0                 # the saved step
var _by_step := {}              # step -> its inputs, in the order made


## Why the saved payload p can't be made again in this build with `model`, or "".
static func why_not(model, sp: Dictionary) -> String:
	if not model.scenarios.has(sp["scenario"]):
		return "its scenario is not in this version's plant"
	var en: Dictionary = sp["engine"]
	if en.get("st_session", false) != false:
		return "it was a shared session's run"
	if typeof(en.get("step_no")) != TYPE_INT or en["step_no"] < 0:
		return "its plant time is damaged"
	if typeof(en.get("inputs")) != TYPE_ARRAY:
		return "its record of actions is missing"
	var last := 0
	for x in en["inputs"]:
		if typeof(x) != TYPE_ARRAY or x.size() < 2 or typeof(x[0]) != TYPE_INT or typeof(x[1]) != TYPE_STRING:
			return "its record of actions is damaged"
		if x[0] < 1 or x[0] < last or x[0] > en["step_no"] + 1:
			return "its record of actions is damaged"
		last = x[0]
		if not INPUT_SIZES.has(x[1]):
			return "it holds an action this version doesn't know (%s): it was saved by a newer version" \
					% RunSave.version_of(x[1])   # (from the file: a short plain word, else "unknown")
		if not (x.size() - 1) in INPUT_SIZES[x[1]]:
			return "its record of actions is damaged"
	if typeof(en.get("events")) != TYPE_ARRAY:
		return "its record of events is missing"
	last = 0
	for x in en["events"]:
		if typeof(x) != TYPE_ARRAY or x.size() < 2 or typeof(x[0]) != TYPE_INT or x[0] < last \
				or typeof(x[1]) != TYPE_STRING:
			return "its record of events is damaged"
		last = x[0]
	# what the offer shows and the made-again run keeps: the procedure, its progress, the debrief's procedure
	if typeof(sp.get("procedure")) != TYPE_STRING or typeof(sp.get("tracker")) != TYPE_DICTIONARY \
			or typeof(sp.get("run")) != TYPE_DICTIONARY or typeof(sp.get("ui")) != TYPE_DICTIONARY:
		return "its procedure's progress is damaged"
	if sp["procedure"] != "":
		if not model.procedures.has(sp["procedure"]):
			return "its procedure is not in this version's plant"
		var why := _tracker_why(model, sp["procedure"], sp["tracker"], en["events"].size())
		if why != "":
			return why
	elif not sp["tracker"].is_empty():
		return "its procedure's progress is damaged"
	var run: Dictionary = sp["run"]
	if not run.is_empty():
		if typeof(run.get("procedure")) != TYPE_STRING or typeof(run.get("same")) != TYPE_BOOL \
				or typeof(run.get("tracker")) != TYPE_DICTIONARY:
			return "its debrief's procedure is damaged"
		if not model.procedures.has(run["procedure"]):
			return "its debrief's procedure is not in this version's plant"
		if not run["same"]:
			var why := _tracker_why(model, run["procedure"], run["tracker"], en["events"].size())
			if why != "":
				return "its debrief's procedure is damaged"
	return ""


## Why a saved tracker of procedure `pid` can't be carried over (its step, its event positions, its deviations), or "".
static func _tracker_why(model, pid: String, t: Dictionary, nev: int) -> String:
	var nsteps: int = model.procedures[pid].get("steps", []).size()
	if typeof(t.get("index")) != TYPE_INT or t["index"] < -1 or t["index"] >= nsteps:
		return "its procedure's step is not in this version's procedure"
	for k in ["_seen", "ev_from", "ev_to"]:
		if t.has(k) and (typeof(t[k]) != TYPE_INT or t[k] < -1 or t[k] > nev):
			return "its procedure's progress is damaged"
	if typeof(t.get("deviations", [])) != TYPE_ARRAY:
		return "its procedure's progress is damaged"
	for d in t.get("deviations", []):
		if typeof(d) != TYPE_ARRAY or d.size() < 3 or typeof(d[2]) != TYPE_INT or d[2] < -1 or d[2] >= nev:
			return "its procedure's progress is damaged"
	return ""


func _init(model, sp: Dictionary) -> void:
	p = sp
	target = sp["engine"]["step_no"]
	e = PlantEngine.new(model, sp["scenario"], false)
	for x in sp["engine"]["inputs"]:
		if not _by_step.has(x[0]):
			_by_step[x[0]] = []
		_by_step[x[0]].append(x)


## Makes the run again for about budget_us microseconds; true when it has reached the saved step (its inputs for the
## step after it queued, as they were saved).
func advance(budget_us: int) -> bool:
	var t0 := Time.get_ticks_usec()
	while e.step_no < target:
		_feed(e.step_no + 1)
		e.step()
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
	if e.step_no >= target and not _by_step.is_empty():
		_feed(target + 1)
	return e.step_no >= target and _by_step.is_empty()


func _feed(s: int) -> void:
	if not _by_step.has(s):
		return
	for x in _by_step[s]:
		Inputs.replay(e, x)       # (the app's inputs go one way: ui/inputs.gd)
	_by_step.erase(s)


## "" when the run made again took every saved input as it was saved (the engine's own log of them is the same).
func made_again() -> String:
	if var_to_bytes(e.inputs) != var_to_bytes(p["engine"]["inputs"]):
		return "its actions could not all be made again in this version"
	return ""


## The actions whose outcome came out otherwise in the run made again (an operation done in the saved run and refused
## or unknown in this version's plant, or the other way round), in words, at most `most`; [] when every one came out
## the same. The engine logs an input when it is queued and decides it at its step, so the input logs alone can't tell.
func differences(most := 3) -> Array:
	return diff_events(p["engine"]["events"], e.events, most)


## differences() between two event lists (the saved run's, the run made again's).
static func diff_events(old_events: Array, new_events: Array, most := 3) -> Array:
	var a := outcomes(old_events)
	var b := outcomes(new_events)
	# matched by what the action was (its event without its outcome), in order, step by step: an action the new run
	# leaves out, or one it decides otherwise, is a difference; one only the new run has (the plant's own) is not
	var now := {}
	for y in b:
		var key := var_to_bytes(y[0])
		if not now.has(key):
			now[key] = []
		now[key].append(y)
	var out: Array = []
	var n := 0
	for x in a:
		var key := var_to_bytes(x[0])
		var same = null
		var list: Array = now.get(key, [])
		for i in list.size():
			if list[i][0] == x[0]:
				same = list[i]
				list.remove_at(i)
				break
		if same != null and same[1] == x[1]:
			continue
		n += 1
		if out.size() < most:
			out.append("%s at %s of plant time: %s in the saved run, %s now" % [_words(x[0]), W.model_time(x[0][0]),
					x[1], "not made" if same == null else same[1]])
	if n > out.size():
		out.append("and %d more" % (n - out.size()))
	return out


## Each decided action's event as [what it was, its outcome]: what it was is the event up to its outcome, which is the
## last "done", "refused" or "unknown" in it ("done" is also a permit's action); the plant's own (a permit's or work
## order's "auto" action) are left out, never a trainee's (a drive's "auto" is one).
static func outcomes(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		if ev.size() < 3 or typeof(ev[1]) != TYPE_STRING or not INPUT_SIZES.has(ev[1]) \
				or ev[1] in ["permit", "wo"] and ev.size() > 3 and ev[3] == "auto":   # (as ui/permits.gd, wo_panel.gd)
			continue
		for k in range(ev.size() - 1, 1, -1):
			if typeof(ev[k]) == TYPE_STRING and ev[k] in ["done", "refused", "unknown"]:
				out.append([ev.slice(0, k), ev[k]])
				break
	return out


## An action in words: its strings after the kind (the code and what was done, for an operation), each a short plain
## word or "unknown" (they come from the file), at most four.
static func _words(w: Array) -> String:
	var parts: Array = []
	for k in range(2 if w[1] == "op" else 1, w.size()):
		if typeof(w[k]) == TYPE_STRING and parts.size() < 4:
			parts.append(RunSave.version_of(w[k]))
	return " ".join(parts)




func fraction() -> float:
	return 1.0 if target == 0 else clampf(float(e.step_no) / float(target), 0.0, 1.0)


## The payload of this build: the engine made again, this app's version and content; the procedure's progress (and the
## debrief's) with its event positions moved to the new event list.
func payload(app: String, content: String) -> Dictionary:
	var out := p.duplicate(true)
	out["app"] = app
	out["content"] = content
	out["engine"] = RunSave.capture(e, RunSave.engine_fields(e))
	var old_ev: Array = p["engine"].get("events", [])
	if not out["tracker"].is_empty():
		out["tracker"] = remap_tracker(_filled(out["tracker"]), old_ev, e.events, target)
	if not out["run"].is_empty() and not out["run"]["same"]:
		out["run"]["tracker"] = remap_tracker(_filled(out["run"]["tracker"]), old_ev, e.events, target)
	# what the panels record that an older build didn't: the tasks given (the debrief's role tab), empty
	if typeof(out["ui"]) == TYPE_DICTIONARY and not out["ui"].has("task_given"):
		out["ui"]["task_given"] = {}
	return out


## A saved tracker with the fields an older build didn't have, at a fresh tracker's values (the rest as saved; a field
## this build doesn't know stays, and the check refuses it).
static func _filled(t: Dictionary) -> Dictionary:
	var fresh = Tracker.new()
	var out := RunSave.capture(fresh, RunSave.tracker_fields(fresh))
	out.merge(t, true)
	return out


## A tracker's event positions (procedure_tracker.gd: _seen, ev_from, ev_to, each deviation's event) moved from the
## old event list to the new: a position before the old event at model step s becomes the position before the first
## new event at step s or later; the end of the old list the end of the new.
static func remap_tracker(t: Dictionary, old_ev: Array, new_ev: Array, last_step: int) -> Dictionary:
	var out := t.duplicate(true)
	# where the procedure began and ended: by its steps (begin_step, end_step), at the same place among that step's
	# events; what it has read: the same place in the list
	for kv in [["ev_from", "begin_step"], ["ev_to", "end_step"], ["_seen", ""]]:
		var k: String = kv[0]
		if out.has(k) and typeof(out[k]) == TYPE_INT and out[k] >= 0:
			var at_step = out.get(kv[1]) if kv[1] != "" else null
			if typeof(at_step) == TYPE_INT and at_step >= 0:
				out[k] = _pos_in_step(out[k], at_step, old_ev, new_ev)
			else:
				out[k] = _pos(out[k], old_ev, new_ev, last_step)
	if out.has("deviations"):
		for d in out["deviations"]:
			if typeof(d) == TYPE_ARRAY and d.size() > 2 and typeof(d[2]) == TYPE_INT and d[2] >= 0:
				d[2] = _op_at(d[2], old_ev, new_ev)
	return out


## A position in the old event list moved to the new: the same place among the events of its model step (its rank
## there, at most the new step's count), so a procedure begun in the middle of a step still begins there.
static func _pos(pos: int, old_ev: Array, new_ev: Array, last_step: int) -> int:
	if pos >= old_ev.size():
		return new_ev.size()
	var s: int = old_ev[pos][0]
	if s > last_step:
		return new_ev.size()
	return _pos_in_step(pos, s, old_ev, new_ev)


## A position in the old list, read as a place among model step s's events (its rank there; at or past the step's
## last event, after the new step's last), moved to the new list.
static func _pos_in_step(pos: int, s: int, old_ev: Array, new_ev: Array) -> int:
	var first_old := _first_at(old_ev, s)
	var n_old := _first_at(old_ev, s + 1) - first_old
	var first := _first_at(new_ev, s)
	var n := _first_at(new_ev, s + 1) - first
	var rank := clampi(pos - first_old, 0, n_old)
	if rank >= n_old:
		return first + n
	# the same event in the new step (the k-th like it, as in the old step), else the same rank
	var ev = old_ev[first_old + rank]
	var k := 0
	for i in range(first_old, first_old + rank):
		if old_ev[i] == ev:
			k += 1
	for i in range(first, first + n):
		if new_ev[i] == ev:
			if k == 0:
				return i
			k -= 1
	return first + mini(rank, n)


## A deviation's op event moved to the new list: the op event of the same rank among its step's op events (-1 when
## the new step has fewer).
static func _op_at(pos: int, old_ev: Array, new_ev: Array) -> int:
	if pos >= old_ev.size():
		return -1
	var s: int = old_ev[pos][0]
	var rank := 0
	for i in range(_first_at(old_ev, s), pos):
		if old_ev[i][1] == "op":
			rank += 1
	var i := _first_at(new_ev, s)
	while i < new_ev.size() and new_ev[i][0] == s:
		if new_ev[i][1] == "op":
			if rank == 0:
				return i
			rank -= 1
		i += 1
	return -1


## The first event at model step s or later (events are in step order).
static func _first_at(ev: Array, s: int) -> int:
	var lo := 0
	var hi := ev.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if ev[mid][0] < s:
			lo = mid + 1
		else:
			hi = mid
	return lo
