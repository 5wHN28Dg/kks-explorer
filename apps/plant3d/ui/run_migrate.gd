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
			return "it holds an action this version doesn't know (%s): it was saved by a newer version" % x[1]
		if not (x.size() - 1) in INPUT_SIZES[x[1]]:
			return "its record of actions is damaged"
	if typeof(en.get("events")) != TYPE_ARRAY:
		return "its record of events is missing"
	last = 0
	for x in en["events"]:
		if typeof(x) != TYPE_ARRAY or x.is_empty() or typeof(x[0]) != TYPE_INT or x[0] < last:
			return "its record of events is damaged"
		last = x[0]
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
		e.apply_input(x.duplicate(true))
	_by_step.erase(s)


## "" when the run made again took every saved input as it was saved (the engine's own log of them is the same).
func made_again() -> String:
	if var_to_bytes(e.inputs) != var_to_bytes(p["engine"]["inputs"]):
		return "its actions could not all be made again in this version"
	return ""


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
	for k in ["_seen", "ev_from", "ev_to"]:
		if out.has(k) and typeof(out[k]) == TYPE_INT and out[k] >= 0:
			out[k] = _pos(out[k], old_ev, new_ev, last_step)
	if out.has("deviations"):
		for d in out["deviations"]:
			if typeof(d) == TYPE_ARRAY and d.size() > 2 and typeof(d[2]) == TYPE_INT and d[2] >= 0:
				# the deviation's own op event: the first new op event at its step, else none
				var s: int = old_ev[d[2]][0] if d[2] < old_ev.size() else last_step + 1
				var at := -1
				for i in range(_pos(d[2], old_ev, new_ev, last_step), new_ev.size()):
					if new_ev[i][0] != s:
						break
					if new_ev[i].size() > 1 and new_ev[i][1] == "op":
						at = i
						break
				d[2] = at
	return out


static func _pos(pos: int, old_ev: Array, new_ev: Array, last_step: int) -> int:
	if pos >= old_ev.size():
		return new_ev.size()
	var s: int = old_ev[pos][0]
	if s > last_step:
		return new_ev.size()
	# the first new event at step s or later (events are in step order)
	var lo := 0
	var hi := new_ev.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if new_ev[mid][0] < s:
			lo = mid + 1
		else:
			hi = mid
	return lo
