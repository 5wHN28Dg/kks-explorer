## The trainee (R7): walks with collisions (stairs are slopes under the drawn steps, platforms and floors are solid,
## doors open in front of them), climbs ladders, and flies freely (through everything) when asked. Driven by the
## input actions (app/controls.gd) or, for scripted walks and tests, by `drive` and `aim` (app/autopilot.gd).
extends CharacterBody3D

const Controls = preload("res://app/controls.gd")

enum Mode { WALK, FLY, CLIMB }
const MOVE_ACTIONS := ["move_forward", "move_back", "move_left", "move_right"]

const RADIUS := 0.3
const HEIGHT := 1.8
const EYE := 1.65
## Gait (the user, 2026-10-22: "walk or run, like real life"). A stick or a touch stick is analogue: pushed a little
## it steps slowly, at WALK_PUSH it walks at the pace, all the way it jogs; the run modifier (Shift, the left stick's
## click) runs. Keys are not analogue: they walk at the pace, and run with the modifier.
const SLOW_SPEED := 0.5        # m/s: a stick pushed just past its dead zone, a careful step
const WALK_SPEED := 1.4        # m/s: a normal walk (the default pace)
const JOG_SPEED := 3.0         # m/s: a stick pushed all the way
const RUN_SPEED := 4.0         # m/s: running (the run modifier)
const WALK_PUSH := 0.75        # the stick's push that walks at the pace; beyond it the walk becomes a jog
const PACES := {"slow": 1.1, "normal": WALK_SPEED, "brisk": 1.7}   # the settings' pace (app/hud.gd)
const STAIR_WALK := 0.8        # m/s in plan at most on a stair, walking, and running
const STAIR_RUN := 1.4
const STAIR_NORMAL_Y := 0.97   # a floor steeper than about 14 degrees is a stair (stairs are slopes of about 33)
const ACCEL := 4.0             # m/s2 speeding up on a floor (0 to a walk in a third of a second, to a run in one)
const DECEL := 10.0            # m/s2 slowing down or turning (a run stops within a metre)
const AIR_ACCEL := 2.0         # m/s2 off the floor
const BOB_Y := 0.012           # m: the eye's dip at each step at a walk (twice that at most), and its sway
const BOB_X := 0.008
const FLY_SPEED := 8.0
const FLY_FAST := 30.0
const CLIMB_SPEED := 0.8       # m/s on a ladder
const GRAVITY := 9.81
const LOOK_RATE := 2.4         # rad/s at a full stick
const LADDER_REACH := 0.6      # how close to a ladder's foot (or its top's step-off point) a walker can take it

var mode := Mode.WALK
var pivot: Node3D
var camera: Camera3D
var ladder: Node3D = null        # the ladder being climbed
var mouse_sensitivity := 0.0025
## Scripted control: when `scripted`, input is ignored and these drive the walker. drive.x strafes right, drive.y
## walks forward (both -1..1); aim is the heading to turn to (radians about the up axis), NAN to leave it.
var scripted := false
var drive := Vector2.ZERO
var aim := NAN
var run := false
## Scripted: the most the walker may go now (the autopilot slows before a corner and at the route's end)
var speed_cap := INF
## The settings (app/hud.gd): the pace keys walk at and a stick walks at WALK_PUSH; the run modifier toggles (an
## accessibility setting: no key to hold) rather than acting while held
var pace := WALK_SPEED
var run_toggle := false
## Head bob while walking: off with reduced motion (ui/plant_ui.gd)
var bob := true
var on_stair := false            # the floor underfoot in the last move is a stair
var _run_latched := false        # run_toggle: the modifier pressed once (until pressed again or the walker stops)
var _latched_moved := false
var _bob_phase := 0.0
## The walk's own speed in plan (what the legs do), smoothed by ACCEL and DECEL. `velocity` is what move_and_slide left
## of it: kept apart, a walker pushing along a wall or a handrail slides on at the slide's share of its speed instead
## of starting again from what the wall left
var _move := Vector2.ZERO
## The lowest the feet have been (tests: nobody falls through)
var lowest_y := INF
## Off while the map or the settings have the controls (they read the same actions)
var input_enabled := true              # the lowest the feet have been (tests: nobody falls through)

signal mode_changed(mode: int)

func _ready() -> void:
	add_to_group("walkers")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT * 0.5
	add_child(cs)
	pivot = Node3D.new()
	pivot.position.y = EYE
	add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 70
	camera.near = 0.05
	camera.far = 800
	camera.cull_mask = 1   # layer 2 is the overview map's markers
	pivot.add_child(camera)
	floor_max_angle = deg_to_rad(46)   # stairs are about 33 degrees
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = true
	# a walker pushing into a wall or a handrail at a slant slides along it at the slant's share of its speed, however
	# small the slant (Godot's default stops it below 15 degrees; the walk's own speed, _move, keeps pushing)
	wall_min_slide_angle = 0.0
	max_slides = 6

func set_heading(yaw: float, pitch := 0.0) -> void:
	rotation.y = yaw
	pivot.rotation.x = pitch

func look(dx: float, dy: float) -> void:
	rotation.y -= dx
	pivot.rotation.x = clampf(pivot.rotation.x - dy, -1.45, 1.45)

func set_mode(m: Mode) -> void:
	if m == mode:
		return
	if mode == Mode.FLY and m == Mode.WALK and not _land():
		return   # nothing to land on below: keep flying
	mode = m
	ladder = null if m != Mode.CLIMB else ladder
	halt()
	mode_changed.emit(mode)

## Stands still at once (a jump, a landing, a run put back).
func halt() -> void:
	velocity = Vector3.ZERO
	_move = Vector2.ZERO

func toggle_fly() -> void:
	set_mode(Mode.WALK if mode == Mode.FLY else Mode.FLY)

## Puts the walker down on the first floor below (leaving flight, or a jump on the map).
func _land() -> bool:
	var hit := floor_below(global_position + Vector3.UP * 0.5)
	if hit.is_empty():
		return false
	global_position = hit.position + Vector3.UP * 0.02
	return true

func floor_below(from: Vector3, depth := 400.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * depth)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.6:
		return {}
	return hit

## Would the walker's capsule standing at `feet` (Godot coordinates) be clear of everything solid?
func fits_at(feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT - 0.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (HEIGHT * 0.5 + 0.05))
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## The wanted movement in the walker's frame: x right, y forward (each -1..1).
func _wish() -> Vector2:
	if scripted:
		return drive
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_back", "move_forward")

## The speed wanted (m/s in plan) for a push (0..1) of the moving controls: analogue (a stick) or not (keys, the
## autopilot), with or without the run modifier, at a pace.
static func speed_for(push: float, fast: bool, analogue: bool, at_pace := WALK_SPEED) -> float:
	if push <= 0.0:
		return 0.0
	if not analogue:
		return RUN_SPEED if fast else at_pace
	push = minf(push, 1.0)
	var v := lerpf(SLOW_SPEED, at_pace, push / WALK_PUSH) if push <= WALK_PUSH \
		else lerpf(at_pace, JOG_SPEED, (push - WALK_PUSH) / (1.0 - WALK_PUSH))
	return maxf(v, RUN_SPEED * push) if fast else v

## Metres from one footstep to the next at a speed: longer steps the faster (about 2 a second at a walk, 3 running).
## The footsteps (ui/sound_player.gd) and the head bob follow it.
static func stride_for(v: float) -> float:
	return clampf(0.35 + 0.25 * v, 0.45, 1.3)

## Whether a move key is held (keys walk at the pace; a stick's push is analogue). Asked only while moving.
static func _keys_moving() -> bool:
	for a in MOVE_ACTIONS:
		for k in Controls.KEYS[a]:
			if Input.is_physical_key_pressed(k):
				return true
	return false

## Running now: the scripted run, or the modifier held (or toggled on).
func running() -> bool:
	if scripted:
		return run
	if not input_enabled:
		return false
	return _run_latched if run_toggle else Input.is_action_pressed("run")

func _physics_process(delta: float) -> void:
	if scripted:
		if not is_nan(aim):
			rotation.y = aim
	elif input_enabled:
		var lv := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if lv.length() > 0.0:
			look(lv.x * LOOK_RATE * delta, lv.y * LOOK_RATE * delta)
	var wish := _wish()
	if _run_latched:                  # a toggled run ends when the walker has come to a stop after it
		if not run_toggle or (wish == Vector2.ZERO and _latched_moved and _move.length() < 0.1):
			_run_latched = false
		_latched_moved = _latched_moved or wish != Vector2.ZERO
	var fast := running()
	match mode:
		Mode.FLY: _fly(wish, fast, delta)
		Mode.CLIMB: _climb(wish, delta)
		_: _walk(wish, fast, delta)
	_head_bob(delta)
	lowest_y = minf(lowest_y, global_position.y)

func _walk(wish: Vector2, fast: bool, delta: float) -> void:
	var basis_h := Basis(Vector3.UP, rotation.y)
	var dir := basis_h * Vector3(wish.x, 0, -wish.y)
	if _take_ladder(dir):
		return
	var push := minf(wish.length(), 1.0)
	var target := Vector3.ZERO
	var floor_now := is_on_floor()
	on_stair = floor_now and get_floor_normal().y < STAIR_NORMAL_Y
	if push > 0.0:
		var speed := speed_for(push, fast, not scripted and not _keys_moving(), pace)
		if on_stair:
			speed = minf(speed, STAIR_RUN if fast else STAIR_WALK)
		if scripted:
			speed = minf(speed, speed_cap)
		target = dir.normalized() * speed
	var to := Vector2(target.x, target.z)
	var rate := AIR_ACCEL
	if floor_now:
		rate = ACCEL if to.length_squared() > _move.length_squared() else DECEL
	_move = _move.move_toward(to, rate * delta)
	velocity.x = _move.x
	velocity.z = _move.y
	if floor_now:
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

## The eye dips at each step and sways from foot to foot, at the footsteps' rate (stride_for); back to rest
## when standing, climbing or flying, or with reduced motion.
func _head_bob(delta: float) -> void:
	var rest := Vector3(0, EYE, 0)
	var want := rest
	var v := Vector2(velocity.x, velocity.z).length()
	if bob and mode == Mode.WALK and v > 0.2 and is_on_floor():
		_bob_phase = fmod(_bob_phase + PI * v / stride_for(v) * delta, TAU)
		var k := minf(v / WALK_SPEED, 2.0)
		want = Vector3(BOB_X * k * sin(_bob_phase), EYE - BOB_Y * k * absf(sin(_bob_phase)), 0)
	if pivot.position != want:
		pivot.position = pivot.position.lerp(want, minf(1.0, 15.0 * delta))
		if pivot.position.distance_squared_to(want) < 1e-8:
			pivot.position = want

func _fly(wish: Vector2, fast: bool, delta: float) -> void:
	var up := 0.0
	if not scripted and input_enabled:
		up = Input.get_action_strength("up") - Input.get_action_strength("down")
	var b := camera.global_transform.basis
	var dir := b * Vector3(wish.x, 0, -wish.y) + Vector3.UP * up
	global_position += dir * (FLY_FAST if fast else FLY_SPEED) * delta

## Takes a ladder when the walker pushes towards one: at its foot facing the way the climber faces, or at its top's
## step-off point facing back over the edge.
func _take_ladder(dir: Vector3) -> bool:
	if dir.length() < 0.3:
		return false
	var d := dir.normalized()
	var p := global_position
	for l in get_tree().get_nodes_in_group("ladders"):
		var foot: Vector3 = l.get_meta("foot")
		var ex: Vector3 = l.get_meta("exit")
		var facing: Vector3 = l.get_meta("facing")
		var top: float = l.get_meta("top")
		var flat := Vector2(p.x - foot.x, p.z - foot.z).length()
		if flat < LADDER_REACH and absf(p.y - foot.y) < 0.5 and d.dot(facing) > 0.5:
			_start_climb(l, foot.y + 0.05)
			return true
		var at_top := Vector2(p.x - ex.x, p.z - ex.z).length()
		if at_top < LADDER_REACH and absf(p.y - top) < 0.5 and d.dot(-facing) > 0.5:
			_start_climb(l, top - 0.3)
			return true
	return false

func _start_climb(l: Node3D, y: float) -> void:
	ladder = l
	var foot: Vector3 = l.get_meta("foot")
	global_position = Vector3(foot.x, y, foot.z)
	var f: Vector3 = l.get_meta("facing")
	rotation.y = atan2(-f.x, -f.z)
	halt()
	mode = Mode.CLIMB
	mode_changed.emit(mode)

func _climb(wish: Vector2, delta: float) -> void:
	var foot: Vector3 = ladder.get_meta("foot")
	var top: float = ladder.get_meta("top")
	var y := global_position.y + wish.y * CLIMB_SPEED * delta
	if y >= top:
		var ex: Vector3 = ladder.get_meta("exit")
		global_position = ex + Vector3.UP * 0.02
		ladder = null
		mode = Mode.WALK
		mode_changed.emit(mode)
		return
	if y <= foot.y and wish.y < 0.0:
		global_position = Vector3(foot.x, foot.y + 0.02, foot.z)
		ladder = null
		mode = Mode.WALK
		mode_changed.emit(mode)
		return
	global_position = Vector3(foot.x, maxf(y, foot.y), foot.z)

func _unhandled_input(event: InputEvent) -> void:
	if scripted or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative.x * mouse_sensitivity, event.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("run") and run_toggle:
		_run_latched = not _run_latched
		_latched_moved = false
	elif event.is_action_pressed("fly"):
		toggle_fly()
	elif event.is_action_pressed("use"):
		press_door()

## Presses the nearest door within 3 m.
func press_door() -> void:
	var best: Node = null
	var bd := 3.0
	for d in get_tree().get_nodes_in_group("doors"):
		var dist: float = (d as Node3D).global_position.distance_to(global_position)
		if dist < bd:
			bd = dist
			best = d
	if best != null:
		best.call("press")
