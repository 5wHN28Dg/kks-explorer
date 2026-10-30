## Runs the behaviour engine (sim/engine.gd) in the app: fixed 0.1 s model steps, decoupled from the frames
## (docs/PLANT3D.md §7.9, §7.10). Pause, 1× and fast-forward. Fast-forward is offered only while the engine allows it
## (no unacknowledged alarm, no active priority 1 alarm, no machine in a watched state; and in the app, no hold-to-run
## motion running: `held_motion`) and stops by itself the moment that changes. Its speed is capped so that the model never takes more than `cpu_share` of one core, from the
## measured cost of a step (decision 0054; with the water treatment plant about 0.8 ms a step on the Note 9, so about
## 30× there; 60× on a laptop: sim/README.md).
extends Node

const PlantEngine = preload("res://sim/engine.gd")
const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

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
## the model's work in one frame, at most (ms: its steps with the staff's, step 9, and what follows each in the app),
## however long the frame before was: a long frame (a hitch, a frame the phone held) must not make the next one long
## too. Fast-forward stops at it within the frame as well, should steps cost more than their measured average (the
## shift change's busiest steps)
const FRAME_MS := 8.0
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
## a multiplayer session runs the steps (net/session.gd: only committed steps, MULTIPLAYER.md §3.1): this clock then
## never steps by itself, and its speed shows the session's
var driven := false
## and a speed asked for goes to the session (a pause, a run, fast-forward by everyone's vote, §7.1, §7.2) instead
var speed_request := Callable()
var _held_of = null             # the model `_held` was made for
var _held: Array = []           # [value slot, code]: the hold-to-run motions' commands (held_motion)


func start(m, scenario_id: String, session := false) -> void:
	model = m
	scenario = scenario_id
	engine = PlantEngine.new(m, scenario_id, session)
	engine.timing = Cost.on         # (a measured walk: step 9's own time, read and cleared after each step)
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


## Fast-forward allowed now: the engine's rule (§7.9) and no hold-to-run motion running (`held_motion`).
func ff_ok() -> bool:
	return engine != null and engine.fast_forward() and held_motion() == ""


## A hold-to-run motion running (PLANT3D §20.5, a `set` op of -1 to 1 whose input is not 0): its code, or "". Such a
## motion runs at 1× only: a hand on a hoist's button can't stop it on target at 60× (a third of a second late is
## 20 s of travel), so fast-forward is refused while one runs and stops the moment one starts. Read from the model's
## values, so a session's host and every player see the same.
func held_motion() -> String:
	if engine == null:
		return ""
	if _held_of != engine.m:
		_held_of = engine.m
		_held = []
		for o in engine.m.op_keys.values():
			if o.get("do", "") == "set" and o.get("range", []) == [-1, 1] and engine.ix.has(String(o.get("input", ""))):
				_held.append([engine.ix[o["input"]], String(o["kks"])])
	for h in _held:
		if engine.cur[h[0]] != 0.0:
			return h[1]
	return ""


## Why fast-forward isn't allowed now, in words, or "" when it is.
func ff_blocked() -> String:
	if engine == null:
		return "no plant"
	var hm := held_motion()
	if hm != "":
		return "%s is running (a hold-to-run motion runs at 1× only: let its button go)" % hm
	var e = engine
	for k in e._al.size():
		var s: String = e.astate[k]
		if s == "normal" or e.shelved[k] != -1:
			continue            # (most alarms: looked at first, the text only for the one named)
		if s == "active_unack" or s == "cleared_unack":
			return "an alarm is not acknowledged (%s)" % e.m.alarms[k].get("text", e._al[k][0])
		if e._al[k][5] == 1 and s == "active_ack":
			return "a priority 1 alarm is active (%s)" % e.m.alarms[k].get("text", e._al[k][0])
	for mi in e._mc.size():
		if e._mc[mi][3][e.mstate[mi]][2]:
			return "%s is in a step to watch (%s)" % [e._mc[mi][0].replace("_", " "), e._mc[mi][2][e.mstate[mi]].replace("_", " ")]
	if e._sm != null and e.unacked(-1) > 0:
		return "something new for you in the Crew panel (press Seen there)"
	return ""


func set_speed(s: int, why := "") -> void:
	if driven and speed_request.is_valid():
		speed_request.call(s)
		return
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


## Takes an engine made elsewhere (a multiplayer session's, made on a worker thread: net/session.gd), keeping the
## measured step cost.
func install(e) -> void:
	engine = e
	acc = 0.0
	restarted.emit(engine)


## One step now (a session's committed step), with everything that follows a step.
func step_one() -> void:
	_one()


func _one() -> void:
	var t0 := Time.get_ticks_usec()
	engine.step()
	var t1 := Time.get_ticks_usec()
	stepped.emit(engine)                # what follows each step (events, the procedure) is the model's cost too
	var us := Time.get_ticks_usec() - t0
	if Cost.on:
		var st := 0
		for u in engine.staff_us:
			st += u
		engine.staff_us.clear()
		engine.step_us.clear()
		Cost.cur[Cost.MODEL] += t1 - t0 - st
		Cost.cur[Cost.STAFF] += st
		Cost.cur[Cost.STEPPED] += us - (t1 - t0)
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
	if engine == null or speed == Speed.PAUSED or driven:
		return
	delta = minf(delta, max_frame)
	acc += delta * rate()
	var n := floori(acc / STEP + 1e-9)
	if n <= 0:
		return
	# the budget of this frame: cpu_share of its time, at most FRAME_MS (always at least one step: 1× must keep up)
	var budget := maxi(1, floori(minf(cpu_share * delta * 1000.0, FRAME_MS) / step_ms))
	if n > budget:
		n = budget
		acc = 0.0               # what the cap leaves out is not owed later
	else:
		acc -= n * STEP
	hold = false
	var ran := 0
	var sp := speed
	var t_frame := Time.get_ticks_usec()
	var timed_out := false
	for i in n:
		if i > 0 and speed == Speed.FAST and Time.get_ticks_usec() - t_frame >= FRAME_MS * 1000.0:
			timed_out = true        # (fast-forward: what the frame's time leaves out is not owed later)
			acc = 0.0
			break
		# (after the first, the check at the end of the step before has looked at this very state)
		if i == 0 and speed == Speed.FAST and not ff_ok():
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
		if speed == Speed.FAST and not ff_ok():
			set_speed(Speed.NORMAL, "Fast-forward stopped: " + ff_blocked())
			break
	if speed == sp and ran < n and not timed_out:
		acc += (n - ran) * STEP          # a hold at 1×: the steps not run this frame are still owed


## Model time as h:mm:ss.
func clock_text() -> String:
	if engine == null:
		return "--:--"
	var s := int(engine.step_no / 10)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
