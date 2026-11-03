## The Workshop's bench clock (docs/plant3d/WORKSHOP.md §3 "Run it", §6): the kind's bench model (sim/bench_model.gd)
## stepped by the plant's engine (sim/engine.gd) every 0.1 s of bench time, at a speed of 0.1× to 2× or paused; the
## trainee's inputs go to the engine as a plant's do (sliders as `set` ops, Start and Stop as the machine's commands,
## the trainer's faults and their repairs, alarm acknowledgements) and take effect in the next step. Everything drawn
## reads a model value: `val()` interpolates it between the last two steps by the clock's fraction of a step, so 0.1×
## is smooth; `now()` is the value as the last step left it. Not saved (UI state, §2); the plant's engine is another.
extends RefCounted

const BenchModel = preload("res://sim/bench_model.gd")
const Engine = preload("res://sim/engine.gd")

const STEP := 0.1
const MAX_STEPS_FRAME := 4      # a long frame steps at most this many (the bench falls behind rather than stalls)
const SPEED_MIN := 0.1
const SPEED_MAX := 2.0

var m                           # sim/bench_model.gd
var e                           # sim/engine.gd
var error := ""
var prev := PackedFloat64Array()
var acc := 0.0
var speed := 1.0
var paused := false
var steps := 0                  # stepped since the load
var step_us_max := 0            # the longest step (microseconds), and their sum: the §8 rule's 0.3 ms
var step_us_sum := 0
var _text := ""
var _comps: Array = []
var _ev_seen := 0
var _ev_mark := 0
var faulted := {}               # fault id -> true while made and not repaired (from the engine's events)


## Loads the bench file's text against the kind's component ids; false (and `error`) when it can't run.
func load_text(text: String, comps: Array) -> bool:
	_text = text
	_comps = comps
	m = BenchModel.from_text(text, comps)
	error = m.error
	if error != "":
		e = null
		return false
	restart()
	return true


## The bench from its start state again (the model as loaded; the clock's speed and pause stay).
func restart() -> void:
	e = Engine.new(m, "bench")
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


func set_speed(x: float) -> void:
	speed = clampf(x, SPEED_MIN, SPEED_MAX)


## Advances the clock by `delta` seconds of the screen's time; returns how many steps it made.
func tick(delta: float) -> int:
	if e == null or paused:
		return 0
	acc += delta * speed
	var n := 0
	while acc >= STEP and n < MAX_STEPS_FRAME:
		prev = e.cur.duplicate()
		var t0 := Time.get_ticks_usec()
		e.step()
		var us := Time.get_ticks_usec() - t0
		step_us_max = maxi(step_us_max, us)
		step_us_sum += us
		steps += 1
		acc -= STEP
		n += 1
	if n == MAX_STEPS_FRAME and acc >= STEP:
		acc = fmod(acc, STEP)
	_read_events()
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


func repair(id: String) -> void:
	if e != null:
		e.repair(id)


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


## Alarms not normal: [[id, text, state]] in the model's order.
func alarms() -> Array:
	var out := []
	if e == null:
		return out
	for k in m.alarms.size():
		if e.astate[k] != "normal":
			out.append([m.alarms[k]["id"], m.alarms[k]["text"], e.astate[k]])
	return out


## The events since the last call (refusals with their reasons, machines' moves, faults).
func new_events() -> Array:
	if e == null:
		return []
	var out: Array = e.events.slice(_ev_mark)
	_ev_mark = e.events.size()
	return out


func _read_events() -> void:
	while _ev_seen < e.events.size():
		var ev: Array = e.events[_ev_seen]
		_ev_seen += 1
		if ev.size() >= 3 and ev[1] == "fault":
			faulted[ev[2]] = true
		elif ev.size() >= 3 and ev[1] == "repair":
			faulted.erase(ev[2])
