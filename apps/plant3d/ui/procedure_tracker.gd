## Follows a procedure or tour (docs/PLANT3D.md §8) against the running engine: which step is current, which of its
## operations the trainee has done, when the step is done (its `done` value turns true, read after each model step,
## at the earliest one step after the step began, as sim/procedure.gd does), and operations made outside the
## current step (deviations: noted, never refused; the plant reacts as it would). A step without `done`, and every
## stop of a tour, ends when the trainee presses Next.
extends RefCounted

signal step_changed(index: int)           # a new current step (or -1: the procedure is finished)
signal step_done(step_id: String)         # a step's `done` turned true
signal deviation(text: String)

var proc: Dictionary = {}
var steps: Array = []
var index := -1                 # the current step, -1 when none (finished or not started)
var start_step := 0             # the model step at which the current step began
var did := {}                   # "kks|do|trip" -> true: the current step's operations done
var deviations: Array = []      # [model step, text]
var log: Array = []             # [[step id, model step it ended], …] (as sim/procedure.gd's log)
var _seen := 0                  # events read so far


static func op_key(kks, do, trip) -> String:
	return "%s|%s|%s" % [kks, do, trip if trip != null else ""]


func is_tour() -> bool:
	return proc.get("kind", "") == "tour"


func begin(p: Dictionary, engine, step_id = null) -> void:
	proc = p
	steps = p.get("steps", [])
	log = []
	deviations = []
	_seen = engine.events.size() if engine != null else 0
	var i := 0
	if step_id != null:
		for k in steps.size():
			if steps[k]["id"] == step_id:
				i = k
	_go(i, engine)


func current() -> Dictionary:
	return steps[index] if index >= 0 and index < steps.size() else {}


func finished() -> bool:
	return not steps.is_empty() and index == -1 and log.size() > 0


func _go(i: int, engine) -> void:
	index = i if i < steps.size() else -1
	start_step = engine.step_no if engine != null else 0
	did = {}
	step_changed.emit(index)


## The trainee's Next: ends a step that has no `done` (and every tour stop); a step with `done` ends by itself.
func can_next(engine = null) -> bool:
	if index < 0:
		return false
	if is_tour():
		return true
	# a procedure step without `done` lasts at least one model step, as in sim/procedure.gd
	return not current().has("done") and (engine == null or engine.step_no > start_step)


func next(engine) -> void:
	if not can_next(engine):
		return
	log.append([current()["id"], engine.step_no if engine != null else 0])
	_go(index + 1, engine)


## Tours only: back to the previous stop.
func back(engine) -> void:
	if is_tour() and index > 0:
		_go(index - 1, engine)


## After each model step.
func on_step(engine) -> void:
	var evs: Array = engine.events
	while _seen < evs.size():
		var ev: Array = evs[_seen]
		_seen += 1
		if ev[1] == "op" and ev[4] == "done":
			_op_done(ev, engine)
	if index < 0 or is_tour():
		return
	var s := current()
	if s.has("done") and engine.step_no > start_step and engine.truth(s["done"]):
		log.append([s["id"], engine.step_no])
		step_done.emit(s["id"])
		_go(index + 1, engine)


func _op_done(ev: Array, engine) -> void:
	if is_tour() or index < 0:
		return
	var want: Array = current().get("do", [])
	# the trip of a reset is not in the event: match on code and operation, and the trip when the step names one
	for k in want.size():
		var d: Dictionary = want[k]
		if d["kks"] == ev[2] and d["do"] == ev[3]:
			var key := op_key(d["kks"], d["do"], d.get("trip"))
			if current().get("ordered", false):
				for j in k:
					var dj: Dictionary = want[j]
					if not did.has(op_key(dj["kks"], dj["do"], dj.get("trip"))):
						_deviate(engine, "%s %s done before %s %s (this step's order)" % [ev[2], ev[3], dj["kks"], dj["do"]])
						break
			did[key] = true
			return
	_deviate(engine, "%s %s is not part of this step" % [ev[2], ev[3]])


func _deviate(engine, text: String) -> void:
	deviations.append([engine.step_no, text])
	deviation.emit(text)


## The operation the current step expects for this code and operation, or {} (the card offers its value).
func expected(kks: String, do: String) -> Dictionary:
	for d in current().get("do", []):
		if d["kks"] == kks and d["do"] == do:
			return d
	return {}


func is_done_op(d: Dictionary) -> bool:
	return did.has(op_key(d["kks"], d["do"], d.get("trip")))
