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
var deviations: Array = []      # [model step, text, its op event's position in the event list, the step it was made
                                # in, the step it belongs to (-1: none; the step it was made in: a wrong value or order)]
var ev_from := 0                # the event list's length when the procedure began: its run's events follow
var begin_step := 0             # the model step at which it began
var log: Array = []             # [[step id, model step it ended], …] (as sim/procedure.gd's log)
var _seen := 0                  # events read so far
var _in_seen := 0               # inputs matched to their op events so far (the event has no value or trip)
var _begin_inputs := 0          # inputs made before the procedure began


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
	ev_from = _seen
	begin_step = engine.step_no if engine != null else 0
	_in_seen = 0
	if engine != null:
		for inp in engine.inputs:
			if inp[0] <= engine.step_no:
				_in_seen += 1
		_begin_inputs = engine.inputs.size()
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
	var ops := []                       # this step's operations done: [event, its input]
	while _seen < evs.size():
		var ev: Array = evs[_seen]
		var at := _seen
		_seen += 1
		if ev[1] == "op":
			# the op events of a step come in the order its inputs were made: the input gives the value and trip
			var inp := []
			var made_before := false
			while _in_seen < engine.inputs.size():
				var cand: Array = engine.inputs[_in_seen]
				_in_seen += 1
				if cand[1] == "op" and cand[0] == ev[0]:
					inp = cand
					made_before = _in_seen <= _begin_inputs      # sent before the procedure began: not judged
					break
			if ev[4] == "done" and not made_before:
				ops.append([ev, inp, at])
	var s := current() if index >= 0 and not is_tour() else {}
	var completing: bool = s.has("done") and engine.step_no > start_step and engine.truth(s["done"])
	# an operation of the next step made with the last of this one (both sent while paused) belongs to the next
	var carried := []
	for o in ops:
		if completing and _find(s, o[0], o[1], false) == -1 and index + 1 < steps.size() \
				and _find(steps[index + 1], o[0], o[1], false) != -1:
			carried.append(o)
		else:
			_op_done(o[0], o[1], engine, o[2])
	if completing:
		log.append([s["id"], engine.step_no])
		step_done.emit(s["id"])
		_go(index + 1, engine)
		for o in carried:
			_op_done(o[0], o[1], engine, o[2])


static func _num(v):
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0          # as the engine reads a bool
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else null


## The position of the step's expected operation this one is (code, operation, trip; the value too when
## `with_value`), or -1.
func _find(step: Dictionary, ev: Array, inp: Array, with_value: bool) -> int:
	var value = inp[4] if inp.size() > 5 else null
	var trip = inp[5] if inp.size() > 5 else null
	var want: Array = step.get("do", [])
	for k in want.size():
		var d: Dictionary = want[k]
		if d["kks"] != ev[2] or d["do"] != ev[3] or (d.has("trip") and d["trip"] != trip):
			continue
		if with_value and d.has("value") and _num(value) != float(d["value"]):
			continue
		return k
	return -1


func _op_done(ev: Array, inp: Array, engine, at := -1) -> void:
	if is_tour() or index < 0:
		return
	var want: Array = current().get("do", [])
	var k := _find(current(), ev, inp, true)
	if k == -1:
		var loose := _find(current(), ev, inp, false)
		if loose != -1:
			_deviate(engine, "%s set to %s; this step asks for %s" % [ev[2], str(inp[4] if inp.size() > 5 else null),
					str(want[loose]["value"])], at, index)
		else:
			var home := belongs(ev, inp)
			_deviate(engine, "%s %s is not part of this step%s" % [ev[2], ev[3],
					(" (step %d's)" % (home + 1)) if home != -1 else ""], at, home)
		return
	if current().get("ordered", false):
		for j in k:
			if not is_done_op(want[j]):
				_deviate(engine, "%s %s done before %s %s (this step's order)" % [ev[2], ev[3], want[j]["kks"], want[j]["do"]],
						at, index)
				break
	did[_key(want[k])] = true


## The step an operation made outside its step belongs to: the next one that expects it, else the last earlier one
## (-1: no step does).
func belongs(ev: Array, inp: Array) -> int:
	for j in range(index + 1, steps.size()):
		if _find(steps[j], ev, inp, false) != -1:
			return j
	for j in range(index - 1, -1, -1):
		if _find(steps[j], ev, inp, false) != -1:
			return j
	return -1


func _deviate(engine, text: String, at := -1, home := -1) -> void:
	deviations.append([engine.step_no, text, at, index, home])
	deviation.emit(text)


## The operation the current step expects for this code and operation, or {} (the card offers its value).
func expected(kks: String, do: String) -> Dictionary:
	for d in current().get("do", []):
		if d["kks"] == kks and d["do"] == do:
			return d
	return {}


func is_done_op(d: Dictionary) -> bool:
	return did.has(_key(d))


static func _key(d: Dictionary) -> String:
	return op_key(d["kks"], d["do"], d.get("trip")) + "|" + str(d.get("value", ""))
