## The Workshop's bench clock (docs/plant3d/WORKSHOP.md §3 "Run it", §6): the kind's bench model (sim/bench_model.gd)
## stepped by the plant's engine (sim/engine.gd) every 0.1 s of bench time, at a speed of 0.1× to 2× or paused; the
## trainee's inputs go to the engine as a plant's do (sliders as `set` ops, Start and Stop as the machine's commands,
## the trainer's faults and their repairs, alarm acknowledgements) and take effect in the next step. Everything drawn
## reads a model value: `val()` interpolates it between the last two steps by the clock's fraction of a step, so 0.1×
## is smooth; `now()` is the value as the last step left it. Not saved (UI state, §2); the plant's engine is another.
extends RefCounted

const BenchModel = preload("res://sim/bench_model.gd")
const PlantEngine = preload("res://sim/engine.gd")

const STEP := 0.1
const MAX_STEPS_FRAME := 4      # a long frame steps at most this many (the bench falls behind rather than stalls)
const SPEED_MIN := 0.1
const SPEED_MAX := 2.0
const MAX_EVENTS := 512         # the engine's events kept at most, read or not (a reader that never reads loses the oldest)

var m                           # sim/bench_model.gd
var e                           # sim/engine.gd
var error := ""
var prev := PackedFloat64Array()
var acc := 0.0
var speed := 1.0
var max_steps := MAX_STEPS_FRAME  # steps a frame at most: a measurement run past 2× may allow more (the walk's)
var paused := false
var steps := 0                  # stepped since the load
var step_us_max := 0            # the longest step (microseconds), and their sum: the §8 rule's 0.3 ms
var step_us_sum := 0
var _text := ""
var _comps: Array = []
var _ev_seen := 0
var _ev_mark := 0
var faulted := {}               # fault id -> true while made and not repaired (from the engine's events)
var mirror_live := Callable()   # (the live mirror in a session, WORKSHOP.md §6.5) the plant's values now, as
								# [values, states] for set_mirror, read before every step; unset, the mirror stands
var _mir: Array = []            # the mirror set ([values, states]; [] none): set again after a restart


## Loads the bench file's text against the kind's component ids; false (and `error`) when it can't run.
func load_text(text: String, comps: Array) -> bool:
	_text = text
	_comps = comps
	clear_mirror()
	m = BenchModel.from_text(text, comps)
	error = m.error
	if error != "":
		e = null
		return false
	restart()
	return true


## The bench from its start state again (the model as loaded; the clock's speed and pause stay).
func restart() -> void:
	# (a measurement's speed past 2× and its steps a frame end here: a kind loaded or restarted runs at the trainee's)
	max_steps = MAX_STEPS_FRAME
	speed = clampf(speed, SPEED_MIN, SPEED_MAX)
	e = PlantEngine.new(m, BenchModel.SCENARIO)
	if not _mir.is_empty():
		e.set_mirror(_mir[0], _mir[1])
	prev = e.cur.duplicate()
	acc = 0.0
	steps = 0
	step_us_max = 0
	step_us_sum = 0
	_ev_seen = 0
	_ev_mark = 0
	faulted.clear()


func loaded() -> bool:
	return e != null


## The live mirror (WORKSHOP.md §6.5): the plant's `values` ({bench value: number}) and machine `states` ({bench
## machine: state id}) written over the engine's after step 2 from the next step on (sim/engine.gd set_mirror), until
## set again or cleared.
func set_mirror(values: Dictionary, states: Dictionary) -> void:
	_mir = [values, states]
	if e != null:
		e.set_mirror(values, states)


func mirrored() -> bool:
	return not _mir.is_empty()


func clear_mirror() -> void:
	_mir = []
	mirror_live = Callable()
	if e != null:
		e.set_mirror({}, {})


## One step at once, drawn without a blend from the start (a mirror's first frame shows the plant's state).
func prime() -> void:
	if e == null:
		return
	_mirror_now()
	e.step()
	steps += 1
	prev = e.cur.duplicate()
	acc = 0.0
	_read_events()
	_drop_read()


func _mirror_now() -> void:
	if mirror_live.is_valid():
		var r: Array = mirror_live.call()
		set_mirror(r[0], r[1])


func set_speed(x: float) -> void:
	speed = clampf(x, SPEED_MIN, SPEED_MAX)


## Advances the clock by `delta` seconds of the screen's time; returns how many steps it made.
func tick(delta: float) -> int:
	if e == null or paused:
		return 0
	acc += delta * speed
	var n := 0
	while acc >= STEP and n < max_steps:
		prev = e.cur.duplicate()
		_mirror_now()
		var t0 := Time.get_ticks_usec()
		e.step()
		var us := Time.get_ticks_usec() - t0
		step_us_max = maxi(step_us_max, us)
		step_us_sum += us
		steps += 1
		acc -= STEP
		n += 1
	if n == max_steps and acc >= STEP:
		acc = fmod(acc, STEP)
	_read_events()
	_drop_read()
	return n


## The clock's fraction of the way to the next step (0-1).
func frac() -> float:
	return clampf(acc / STEP, 0.0, 1.0)


func slot(name: String) -> int:
	return e.ix.get(name, -1) if e != null else -1


## A value drawn between the last two steps.
func val(name: String) -> float:
	var i := slot(name)
	if i < 0:
		return 0.0
	return lerpf(prev[i], e.cur[i], frac())


## A value as the last step left it.
func now(name: String) -> float:
	var i := slot(name)
	return e.cur[i] if i >= 0 else 0.0


func unit(name: String) -> String:
	return String(m.units.get(name, "")) if m != null else ""


## A value as the panels and the machine's display show it: three significant figures past the point, its unit.
func shown(name: String) -> String:
	var x := now(name)
	var u := unit(name)
	var t := ("%.2f" % x) if absf(x) < 100.0 else ("%.0f" % x)
	if t == "-0.00":
		t = "0.00"
	return t + (" " + u if u != "" else "")


# ------------------------------------------------------------------ the trainee's inputs (next step's step 1)

func op_set(at: String, value: float) -> void:
	if e != null:
		e.op(at, "set", value)


func command(at: String, do: String) -> void:
	if e != null:
		e.op(at, do)


func fault(id: String) -> void:
	if e != null:
		e.fault(id)
		faulted[id] = true      # (the panel shows it pressed at once, paused too; the next step makes it)


func repair(id: String) -> void:
	if e != null:
		e.repair(id)
		for f in m.faults:          # (the engine ignores a repair of a fault that has none: it stays made)
			if f.id == id and f.repair:
				faulted.erase(id)


func ack(alarm: String) -> void:
	if e != null:
		e.ack(alarm)


## The machine's state id (the machine's `_ids` at its state value).
func machine_state(mid: String) -> String:
	if e == null:
		return ""
	for mc in m.machines:
		if mc["id"] == mid:
			return mc["_ids"][int(now(mid + "_state"))]
	return ""


## Whether machine `mid` waits for the trainee: out of its resting state, in a state whose next steps all read values
## only the trainee sets (an op's value or a slider's input) (a turbine at full speed no load waits for its breaker), not in one that moves on by itself.
func waits_for_trainee(mid: String) -> bool:
	var by_op := {}             # what the trainee sets: ops' values and sliders' inputs
	for o in m.ops_ui:
		for k in o.get("set", {}):
			by_op[k] = true
		if o.has("input"):
			by_op[String(o.input)] = true
	for mc in m.machines:
		if mc["id"] != mid:
			continue
		var st := machine_state(mid)
		if st == String(mc.init):
			return false
		for sd in mc.states:
			if String(sd.id) == st:
				if sd.get("next", []).is_empty():
					return false
				for nx in sd.get("next", []):
					if not by_op.has(String(nx[0])):
						return false
				return true
	return false

## Whether every machine of the bench waits for the trainee (waits_for_trainee); false with none.
func all_wait() -> bool:
	if m == null or m.machines.is_empty():
		return false
	for mc in m.machines:
		if not waits_for_trainee(String(mc.id)):
			return false
	return true


## Alarms not normal: [[id, text, state]] in the model's order.
func alarms() -> Array:
	var out := []
	if e == null:
		return out
	for k in m.alarms.size():
		if e.astate[k] != "normal":
			out.append([m.alarms[k]["id"], m.alarms[k]["text"], e.astate[k]])
	return out


## The texts of the active alarms (not normal, not cleared) whose `where` is the component `at`.
func alarms_at(at: String) -> Array:
	var out := []
	if e == null:
		return out
	for k in m.alarms.size():
		var a: Dictionary = m.alarms[k]
		if a.get("where") == at and (e.astate[k] == "active_unack" or e.astate[k] == "active_ack"):
			out.append(a["text"])
	return out


## The events since the last call (refusals with their reasons, machines' moves, faults).
func new_events() -> Array:
	if e == null:
		return []
	var out: Array = e.events.slice(_ev_mark)
	_ev_mark = e.events.size()
	_drop_read()
	return out


## What the bench no longer needs of the engine's logs, dropped, so they stay small for as long as a machine is open:
## the inputs (the vectors' input form: a log nothing here reads) and the events both of this clock's readers have
## read (`_read_events`, `new_events`), and past MAX_EVENTS the oldest. The engine reads its events only within a
## step, from its own `ev_mark`, and the digest leaves the logs out, so between steps nothing it steps from is lost:
## the values and the digest are what an engine that kept everything gives (tests/test_workshop_run.gd).
func _drop_read() -> void:
	e.inputs.clear()
	var k := mini(_ev_seen, _ev_mark)
	k = maxi(k, e.events.size() - MAX_EVENTS)
	if k <= 0:
		return
	e.events = e.events.slice(k)
	e.ev_mark = maxi(0, e.ev_mark - k)
	_ev_seen = maxi(0, _ev_seen - k)
	_ev_mark = maxi(0, _ev_mark - k)


func _read_events() -> void:
	while _ev_seen < e.events.size():
		var ev: Array = e.events[_ev_seen]
		_ev_seen += 1
		if ev.size() >= 3 and ev[1] == "fault":
			faulted[ev[2]] = true
		elif ev.size() >= 3 and ev[1] == "repair":
			faulted.erase(ev[2])
