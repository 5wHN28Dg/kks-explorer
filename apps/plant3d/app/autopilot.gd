## Walks the player along a scripted route with the player's own controls (no teleporting, no path finding): the
## walking test, the frame-time walk on the phones, and later the tours' "take me there". Each step is
##   {"to": Vector3}                         walk (turning towards it) until within reach in plan
##   {"ladder": id, "dir": "up" | "down"}    climb a ladder (from its foot, or from its top's step-off point)
## The walker speeds up and slows down as a trainee does (app/player.gd): the autopilot slows it before a corner (the
## sharper, the slower) and before the route's end or a ladder, so that it turns and stops where the route says.
## A walker that makes less than 0.3 m of headway in 5 s is stuck: `stuck` is emitted with the step, and the route
## either stops (tests) or moves on to the next step from where the stuck one should have ended (`skip_stuck`).
extends Node

const Player = preload("res://app/player.gd")
const REACH := 0.35
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
var _phase := 0           # ladders: 0 walk to the start, 1 climbing

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
	var s: Dictionary = steps[i]
	var done := false
	if s.has("to"):
		done = _walk_to(s.to, _turn_speed(s.to))
	elif s.has("ladder"):
		done = _ladder(s)
	if done:
		i += 1
		_phase = 0
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
		_reset_stuck()

## The speed to pass the point of step i at: on to the next point the faster the straighter, else stopped.
func _turn_speed(target: Vector3) -> float:
	if i + 1 >= steps.size() or not (steps[i + 1] as Dictionary).has("to"):
		return 0.0
	var p: Vector3 = player.global_position
	var nx: Vector3 = steps[i + 1].to
	var a := Vector2(target.x - p.x, target.z - p.z).normalized()
	var b := Vector2(nx.x - target.x, nx.z - target.z).normalized()
	return lerpf(1.0, Player.RUN_SPEED, pow(clampf(a.dot(b), 0.0, 1.0), 4.0))   # 45 degrees: 1.75 m/s; a right angle: 1

## Walks towards `target`, slowing so as to pass it at no more than `v_end`; true when within reach.
func _walk_to(target: Vector3, v_end := 0.0) -> bool:
	var p: Vector3 = player.global_position
	var d := Vector2(target.x - p.x, target.z - p.z)
	if d.length() < REACH:
		player.drive = Vector2.ZERO
		return true
	player.aim = atan2(-d.x, -d.y)
	player.drive = Vector2(0, 1)
	# to a corner: at v_end where the step ends (within reach); to a stop: at the point itself (the walker stops on
	# past the reach, near the point)
	var left := d.length() - (REACH if v_end > 0.0 else 0.0)
	player.speed_cap = maxf(sqrt(v_end * v_end + 2.0 * BRAKE * maxf(left, 0.0)), CREEP)
	return false

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

## Where a stuck step should have left the walker (frame-time walks go on from there).
func _place_after(s: Dictionary) -> void:
	player.halt()
	if s.has("to"):
		player.global_position = s.to + Vector3.UP * 0.05
	elif s.has("ladder"):
		var l := _find_ladder(s.ladder)
		if l:
			player.global_position = (l.get_meta("exit") if s.get("dir", "up") == "up" else l.get_meta("foot")) + Vector3.UP * 0.05
	if player.mode == Player.Mode.CLIMB:
		player.set_mode(Player.Mode.WALK)
