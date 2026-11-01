## Walks the player along a scripted route with the player's own controls (no teleporting, no path finding): the
## walking test, the frame-time walk on the phones, and later the tours' "take me there". Each step is
##   {"to": Vector3}                         walk (turning towards it) until within reach in plan
##   {"to": Vector3, "exact": true}          walk to it and come to rest there, within EXACT_REACH (a stair's approach point:
##                                           the flight's clear width leaves the walker about 0.2 m either side, less
##                                           than REACH, and a walker that came in from the side turned onto the stair
##                                           off its line and caught its side: app/walk_route.gd steps)
##   {"ladder": id, "dir": "up" | "down"}    climb a ladder (from its foot, or from its top's step-off point)
##   {"lift": code, "from": i, "dest": j}    ride a service lift from in front of landing i's gate to landing j
##                                           (PLANT3D §20.7): call the cab, open the gate, step in, close it, send the
##                                           cab from its panel, open the gate at j and step out, shutting it behind;
##                                           the controls through `ui` (ui/plant_ui.gd do_op: the one input path), as
##                                           a trainee works them; waiting for the cab is not being stuck
## The walker speeds up and slows down as a trainee does (app/player.gd): the autopilot slows it before a corner (the
## sharper, the slower) and before the route's end or a ladder, so that it turns and stops where the route says.
## A walker that makes less than 0.3 m of headway in 5 s is stuck: `stuck` is emitted with the step, and the route
## either stops (tests) or moves on to the next step from where the stuck one should have ended (`skip_stuck`).
extends Node

const Player = preload("res://app/player.gd")
const WalkRoute = preload("res://app/walk_route.gd")
const REACH := 0.35
const EXACT_REACH := 0.1
const STUCK_S := 5.0
const BRAKE := 0.8 * Player.DECEL   # m/s2 the autopilot plans to slow at (some margin under the walker's own)
const CREEP := 0.3                  # m/s: the least it slows to before a stop

var player   # app/player.gd
var steps: Array = []
var i := 0
var loop := false
var skip_stuck := false
var running := false
var _since := 0.0
var _last := Vector3.INF
var _phase := 0           # ladders: 0 walk to the start, 1 climbing; lifts: the ride's phases (_lift)
var ui = null             # ui/plant_ui.gd: a lift's controls are worked through it
var _press_t := -100.0    # when a lift control was last pressed (s, _now)
var _ride_t := -1.0       # when this ride's step began (s, _now): a ride that takes longer than RIDE_MAX is stuck
const RIDE_MAX := 300.0   # s (a lift not ready, a gate switch at fault: the walker never gets there)
var _now := 0.0

signal finished
signal stuck(step: int, at: Vector3)

func start(p, route: Array, looped := false) -> void:
	player = p
	steps = route
	i = 0
	loop = looped
	running = true
	_phase = 0
	_reset_stuck()
	player.scripted = true

func stop() -> void:
	running = false
	if player:
		player.drive = Vector2.ZERO
		player.speed_cap = INF
		player.scripted = false

func _reset_stuck() -> void:
	_since = 0.0
	_last = player.global_position if player else Vector3.INF

func _physics_process(delta: float) -> void:
	if not running:
		return
	if i >= steps.size():
		if loop:
			i = 0
		else:
			player.drive = Vector2.ZERO
			player.speed_cap = INF
			running = false
			finished.emit()
			return
	_now += delta
	var s: Dictionary = steps[i]
	var done := false
	if s.has("to"):
		done = _stop_at(s.to) if s.get("exact", false) else _walk_to(s.to, _turn_speed(s.to))
	elif s.has("ladder"):
		done = _ladder(s)
	elif s.has("lift"):
		if _phase == 0 and _ride_t < 0.0:
			_ride_t = _now
		done = _lift(s)
		if not done and _phase != 2 and _phase != 6:
			_reset_stuck()          # waiting for the cab or a gate: not stuck, for a while
			if _now - _ride_t > RIDE_MAX:
				_since = STUCK_S    # the ride never came: stuck (moved on to the step after it, or stopped)
	if done:
		i += 1
		_phase = 0
		_ride_t = -1.0
		player.speed_cap = INF
		_reset_stuck()
		return
	_since += delta
	if _since >= STUCK_S:
		if player.global_position.distance_to(_last) < 0.3:
			stuck.emit(i, player.global_position)
			if not skip_stuck:
				stop()
				return
			_place_after(s)
			i += 1
			_phase = 0
			_ride_t = -1.0
		_reset_stuck()

## The speed to pass the point of step i at: on to the next point the faster the straighter, else stopped.
func _turn_speed(target: Vector3) -> float:
	var n := i + 1
	if n >= steps.size() and loop:
		n = 0                            # a looped route goes on round
	if n >= steps.size() or not (steps[n] as Dictionary).has("to"):
		return 0.0
	var p: Vector3 = player.global_position
	var nx: Vector3 = steps[n].to
	var a := Vector2(target.x - p.x, target.z - p.z).normalized()
	var b := Vector2(nx.x - target.x, nx.z - target.z).normalized()
	return lerpf(1.0, Player.RUN_SPEED, pow(clampf(a.dot(b), 0.0, 1.0), 4.0))   # 45 degrees: 1.75 m/s; a right angle: 1

## Walks towards `target`, slowing so as to pass it at no more than `v_end`; true when within `reach`.
func _walk_to(target: Vector3, v_end := 0.0, reach := REACH) -> bool:
	var p: Vector3 = player.global_position
	var d := Vector2(target.x - p.x, target.z - p.z)
	if d.length() < reach:
		player.drive = Vector2.ZERO
		return true
	player.aim = atan2(-d.x, -d.y)
	player.drive = Vector2(0, 1)
	# to a corner: at v_end where the step ends (within reach); to a stop: at the point itself (the walker stops on
	# past the reach, near the point)
	var left := d.length() - (reach if v_end > 0.0 else 0.0)
	player.speed_cap = maxf(sqrt(v_end * v_end + 2.0 * BRAKE * maxf(left, 0.0)), CREEP)
	return false

## Walks to `target` and comes to rest within EXACT_REACH of it; true once at rest there (a walker that ends the step
## still moving drifts on sideways when it turns to the next).
func _stop_at(target: Vector3) -> bool:
	var p: Vector3 = player.global_position
	if Vector2(target.x - p.x, target.z - p.z).length() >= EXACT_REACH:
		_walk_to(target, 0.0, EXACT_REACH)
		return false
	player.drive = Vector2.ZERO
	return Vector2(player.velocity.x, player.velocity.z).length() < 0.05

func _find_ladder(id: String) -> Node3D:
	for l in player.get_tree().get_nodes_in_group("ladders"):
		if l.get_meta("id") == id:
			return l
	return null

func _ladder(s: Dictionary) -> bool:
	var l := _find_ladder(s.ladder)
	if l == null:
		push_error("autopilot: no ladder " + s.ladder)
		return true
	var facing: Vector3 = l.get_meta("facing")
	var up: bool = s.get("dir", "up") == "up"
	if _phase == 0:
		if player.mode == Player.Mode.CLIMB:
			_phase = 1
		else:
			var start: Vector3 = l.get_meta("foot") if up else l.get_meta("exit")
			var p: Vector3 = player.global_position
			var d := Vector2(start.x - p.x, start.z - p.z)
			if d.length() >= REACH:
				_walk_to(start)
				return false
			# at the start: face the way the climber faces and push onto the ladder (forward up, back down)
			player.aim = atan2(-facing.x, -facing.z)
			player.drive = Vector2(0, 1 if up else -1)
			return false
	player.drive = Vector2(0, 1 if up else -1)
	return player.mode != Player.Mode.CLIMB

## The lift's model entry and its view (app/lift.gd), or [] when the lift is not drawn.
func _lift_of(code: String) -> Array:
	if ui == null or ui.lifts == null:
		return []
	for L in ui.lifts.lifts:
		if String(L["x"]["kks"]) == code:
			return [L["x"], L]
	return []


## Presses one of the lift's controls (its op, as the card's button does), at most once a second.
func _press(code: String, do: String, value = null) -> void:
	if _now - _press_t < 1.0:
		return
	_press_t = _now
	for o in ui.info.ops_of.get(code, []):
		if o["do"] == do:
			ui.do_op(o, value, "local")
			return


## Whether a call or a send would be taken: the lift ready and within its rated load (else it would be refused, as
## a trainee sees on the card; the autopilot waits for that to change, or gives up after RIDE_MAX).
func _callable(e, x: Dictionary) -> bool:
	return e.v(x["ready"]) >= 0.5 and e.v(String(x["id"]) + "_load_ok") >= 0.5


func _lift(s: Dictionary) -> bool:
	var lv := _lift_of(String(s.lift))
	if lv.is_empty():
		push_error("autopilot: no lift " + String(s.lift))
		return true
	var x: Dictionary = lv[0]
	var L: Dictionary = lv[1]
	var e = ui.clock.engine
	var a: int = int(s["from"])
	var b: int = int(s["dest"])
	var lds: Array = x["landings"]
	var body: Node3D = L["body"]
	player.drive = Vector2.ZERO
	match _phase:
		0:  # the cab here with its gate open: in; else open the gate where it stands, else call it
			if e.v(lds[a]["at"]) >= 0.5 and e.v(lds[a]["open"]) >= 0.5:
				_phase = 2
			elif e.v(lds[a]["at"]) >= 0.5 and e.v(lds[a]["shut"]) >= 0.5 and e.v(String(x["id"]) + "_gate%d_cmd" % a) < 0.5:
				_press(lds[a]["gate"], "open")       # (once: it opens in 2 s)
			elif e.v(lds[a]["at"]) < 0.5 and not (e.lift_calls[L["k"]] >> a & 1) and _callable(e, x):
				_press(lds[a]["call"], "start")      # (once: the cab remembers a call)
		2:  # step in, to the cab's middle
			var c := body.global_position + Vector3.UP * 0.05
			if _stop_at(c):
				_phase = 3
		3:  # aboard (app/lift.gd sends the board): shut the gate behind, then send the cab
			if ui.lifts.walker_aboard == L["k"]:
				if e.v(lds[a]["shut"]) >= 0.5:
					_phase = 4
				elif e.v(String(x["id"]) + "_gate%d_cmd" % a) >= 0.5:
					_press(lds[a]["gate"], "close")   # (a gate commanded shut that never reads shut: waited for)
		4:  # sent; riding; at b with the cab still: open the gate there
			if e.v(lds[b]["at"]) >= 0.5:
				if e.v(lds[b]["open"]) >= 0.5:
					_phase = 6
				elif e.v(String(x["id"]) + "_gate%d_cmd" % b) < 0.5:
					_press(lds[b]["gate"], "open")
			elif e.v(x["target"]) != float(b) and not (e.lift_calls[L["k"]] >> b & 1) and _callable(e, x):
				_press(x["panel"], "set", b)         # (once: the cab remembers a send)
		6:  # out, to in front of the gate
			var g: Node3D = ui.index.nodes.get(String(lds[b]["gate"]))
			var out := g.global_transform * Vector3(-WalkRoute.LIFT_FRONT, 0.05, 0.0)
			if _stop_at(out):
				_phase = 7
		7:  # off (app/lift.gd sends the alight): shut the gate behind
			if ui.lifts.walker_aboard != L["k"]:
				if e.v(String(x["id"]) + "_gate%d_cmd" % b) >= 0.5 and e.v(lds[b]["at"]) >= 0.5:
					_press(lds[b]["gate"], "close")
				else:
					return true
	return false


## Where a stuck step should have left the walker (frame-time walks go on from there).
func _place_after(s: Dictionary) -> void:
	player.halt()
	if s.has("to"):
		player.global_position = s.to + Vector3.UP * 0.05
	elif s.has("lift"):
		var lv := _lift_of(String(s.lift))
		if not lv.is_empty():
			var g: Node3D = ui.index.nodes.get(String(lv[0]["landings"][int(s["dest"])]["gate"]))
			if g != null:
				player.global_position = g.global_transform * Vector3(-WalkRoute.LIFT_FRONT, 0.05, 0.0)
	elif s.has("ladder"):
		var l := _find_ladder(s.ladder)
		if l:
			player.global_position = (l.get_meta("exit") if s.get("dir", "up") == "up" else l.get_meta("foot")) + Vector3.UP * 0.05
	if player.mode == Player.Mode.CLIMB:
		player.set_mode(Player.Mode.WALK)
