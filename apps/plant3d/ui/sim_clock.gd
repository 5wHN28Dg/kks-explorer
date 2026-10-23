## Runs the behaviour engine (sim/engine.gd) in the app: fixed 0.1 s model steps, decoupled from the frames
## (docs/PLANT3D.md §7.9, §7.10). Pause, 1× and fast-forward. Fast-forward is offered only while the engine allows it
## (no unacknowledged alarm, no active priority 1 alarm, no machine in a watched state) and stops by itself the moment
## that changes. Its speed is capped so that the model never takes more than `cpu_share` of one core, from the
## measured cost of a step (decision 0054; with the water treatment plant about 0.8 ms a step on the Note 9, so about
## 30× there; 60× on a laptop: sim/README.md).
extends Node

const PlantEngine = preload("res://sim/engine.gd")

const STEP := 0.1
const FF_MAX := 60.0            # the format's top speed (§7.9)
enum Speed { PAUSED, NORMAL, FAST }

signal stepped(engine)                    # after every model step (the procedure follows the plant with it)
signal speed_changed(speed: int, why: String)
signal restarted(engine)

var model
var engine
var scenario := ""
var speed := Speed.PAUSED
var ff_want := FF_MAX           # the fast-forward asked for; the cap may give less
var cpu_share := 0.25           # of one core, at most, for the model
var step_ms := 0.3              # a step's measured cost, moving average (ms)
var hold := false               # set by a `stepped` listener: no more steps this frame
var pause_on_hold := false      # and pause (procedures: "pause when a step is done")
var acc := 0.0
var max_frame := 0.25           # a longer frame (a hitch, the app paused) counts as this much
var steps_per_s := 0.0          # measured over the last second
var model_ms_per_s := 0.0       # wall time the model took in the last second (ms per s: 250 = a quarter core)
var _win_steps := 0
var _win_us := 0
var _win_t := 0.0


func start(m, scenario_id: String) -> void:
	model = m
	scenario = scenario_id
	engine = PlantEngine.new(m, scenario_id)
	acc = 0.0
	_calibrate()
	restarted.emit(engine)
	set_speed(Speed.NORMAL)


## A first measure of the step's cost on this device: a few steps on a copy of the plant.
func _calibrate() -> void:
	var c = engine.clone()
	var t0 := Time.get_ticks_usec()
	c.step(20)
	step_ms = maxf(0.01, (Time.get_ticks_usec() - t0) / 20000.0)


## The highest fast-forward this device gets within `cpu_share` of a core.
func ff_cap() -> float:
	return clampf(cpu_share * 1000.0 / step_ms * STEP, 1.0, FF_MAX)


func ff_rate() -> float:
	return minf(ff_want, ff_cap())


func rate() -> float:
	match speed:
		Speed.NORMAL: return 1.0
		Speed.FAST: return ff_rate()
	return 0.0


## Why fast-forward isn't allowed now, in words, or "" when it is.
func ff_blocked() -> String:
	if engine == null:
		return "no plant"
	var e = engine
	for k in e._al.size():
		if e.shelved[k] != -1:
			continue
		var s: String = e.astate[k]
		var txt: String = e.m.alarms[k].get("text", e._al[k][0])
		if s == "active_unack" or s == "cleared_unack":
			return "an alarm is not acknowledged (%s)" % txt
		if e._al[k][5] == 1 and s == "active_ack":
			return "a priority 1 alarm is active (%s)" % txt
	for mi in e._mc.size():
		if e._mc[mi][3][e.mstate[mi]][2]:
			return "%s is in a step to watch (%s)" % [e._mc[mi][0].replace("_", " "), e._mc[mi][2][e.mstate[mi]].replace("_", " ")]
	return ""


func set_speed(s: int, why := "") -> void:
	if s == Speed.FAST:
		var b := ff_blocked()
		if b != "":
			s = Speed.NORMAL
			why = "No fast-forward: " + b
	if s == speed and why == "":
		return
	speed = s
	acc = 0.0
	speed_changed.emit(speed, why)


## Runs `n` steps now, whatever the speed (tests and the debrief; still stops at a hold).
func run_steps(n: int) -> int:
	var done := 0
	hold = false
	while done < n and not hold:
		_one()
		done += 1
	return done


func _one() -> void:
	var t0 := Time.get_ticks_usec()
	engine.step()
	stepped.emit(engine)                # what follows each step (events, the procedure) is the model's cost too
	var us := Time.get_ticks_usec() - t0
	_win_steps += 1
	_win_us += us
	step_ms = step_ms * 0.98 + (us / 1000.0) * 0.02


func _process(delta: float) -> void:
	_win_t += delta
	if _win_t >= 1.0:
		steps_per_s = _win_steps / _win_t
		model_ms_per_s = _win_us / 1000.0 / _win_t
		_win_t = 0.0
		_win_steps = 0
		_win_us = 0
	if engine == null or speed == Speed.PAUSED:
		return
	delta = minf(delta, max_frame)
	acc += delta * rate()
	var n := floori(acc / STEP + 1e-9)
	if n <= 0:
		return
	# the budget of this frame: cpu_share of its time (always at least one step: 1× must keep up)
	var budget := maxi(1, floori(cpu_share * delta * 1000.0 / step_ms))
	if n > budget:
		n = budget
		acc = 0.0               # what the cap leaves out is not owed later
	else:
		acc -= n * STEP
	hold = false
	var ran := 0
	var sp := speed
	for i in n:
		# (after the first, the check at the end of the step before has looked at this very state)
		if i == 0 and speed == Speed.FAST and not engine.fast_forward():
			set_speed(Speed.NORMAL, "Fast-forward stopped: " + ff_blocked())
			break
		_one()
		ran += 1
		if hold:
			hold = false
			if pause_on_hold:
				set_speed(Speed.PAUSED, "Paused: a procedure step is done")
			elif speed == Speed.FAST:
				set_speed(Speed.NORMAL, "Fast-forward stopped: a procedure step is done")
			break
		if speed == Speed.FAST and not engine.fast_forward():
			set_speed(Speed.NORMAL, "Fast-forward stopped: " + ff_blocked())
			break
	if speed == sp and ran < n:
		acc += (n - ran) * STEP          # a hold at 1×: the steps not run this frame are still owed


## Model time as h:mm:ss.
func clock_text() -> String:
	if engine == null:
		return "--:--"
	var s := int(engine.step_no / 10)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
