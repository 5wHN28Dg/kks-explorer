## The trainee (R7): walks with collisions (stairs are slopes under the drawn steps, platforms and floors are solid,
## doors open in front of them), climbs ladders, and flies freely (through everything) when asked. Driven by the
## input actions (app/controls.gd) or, for scripted walks and tests, by `drive` and `aim` (app/autopilot.gd).
extends CharacterBody3D

enum Mode { WALK, FLY, CLIMB }

const RADIUS := 0.3
const HEIGHT := 1.8
const EYE := 1.65
const WALK_SPEED := 1.6        # m/s (a brisk walk on a plant)
const RUN_SPEED := 4.0
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
	velocity = Vector3.ZERO
	mode_changed.emit(mode)

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

## The wanted movement in the walker's frame: x right, y forward (each -1..1).
func _wish() -> Vector2:
	if scripted:
		return drive
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_back", "move_forward")

func _physics_process(delta: float) -> void:
	if scripted:
		if not is_nan(aim):
			rotation.y = aim
	elif input_enabled:
		var lv := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if lv.length() > 0.0:
			look(lv.x * LOOK_RATE * delta, lv.y * LOOK_RATE * delta)
	var wish := _wish()
	var fast := run or (not scripted and Input.is_action_pressed("run"))
	match mode:
		Mode.FLY: _fly(wish, fast, delta)
		Mode.CLIMB: _climb(wish, delta)
		_: _walk(wish, fast, delta)
	lowest_y = minf(lowest_y, global_position.y)

func _walk(wish: Vector2, fast: bool, delta: float) -> void:
	var basis_h := Basis(Vector3.UP, rotation.y)
	var dir := basis_h * Vector3(wish.x, 0, -wish.y)
	if _take_ladder(dir):
		return
	var speed := RUN_SPEED if fast else WALK_SPEED
	var target := dir * speed
	var acc := 12.0 if is_on_floor() else 2.0
	velocity.x = move_toward(velocity.x, target.x, acc * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, acc * speed * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

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
	velocity = Vector3.ZERO
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
	elif event.is_action_pressed("fly"):
		toggle_fly()
	elif event.is_action_pressed("use"):
		press_door()

## Presses the nearest door in front of the walker, within 3 m.
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
