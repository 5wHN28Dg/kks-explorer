## The Workshop's orbit camera (docs/plant3d/WORKSHOP.md §3 "The space"): it turns round a target, at a distance, by
## yaw and pitch; pans the target across the view; zooms by distance; frames a box. Mouse: left drag orbits, right or
## middle drag pans, the wheel zooms. Touch: one finger orbits, two pan and pinch. Gamepad: the look stick orbits, the
## move stick zooms (forward, back) and pans (left, right), as the plant's look does. Nothing here knows a part kind.
extends Camera3D

const PITCH_MIN := -1.45
const PITCH_MAX := 1.45
const ORBIT_RATE := 0.008       # radians a pixel of drag
const PAD_RATE := 2.2           # radians a second, stick fully over
var target := Vector3.ZERO
var yaw := 0.6
var pitch := -0.35
var dist := 0.6
var dist_min := 0.05
var dist_max := 20.0
var home := []                  # [target, yaw, pitch, dist]: Reset view
var _touches := {}              # index -> position

func _ready() -> void:
	fov = 40.0
	near = 0.005
	far = 200.0
	place()

## The camera where target, yaw, pitch and dist say.
func place() -> void:
	pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	dist = clampf(dist, dist_min, dist_max)
	var dir := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
	global_position = target + dir * dist
	look_at(target, Vector3.UP)

## Frames a box (the whole machine or a part): target at its centre, far enough to see all of it.
func frame(box: AABB, keep_angles := true) -> void:
	target = box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.02)
	dist = r / tan(deg_to_rad(fov * 0.5)) * 1.15
	dist_min = r * 0.15
	dist_max = maxf(r * 30.0, 2.0)
	if not keep_angles:
		yaw = 0.6
		pitch = -0.35
	place()

func set_home() -> void:
	home = [target, yaw, pitch, dist]

func reset_view() -> void:
	if home.size() == 4:
		target = home[0]; yaw = home[1]; pitch = home[2]; dist = home[3]
		place()

func orbit(d: Vector2) -> void:
	yaw -= d.x * ORBIT_RATE
	pitch -= d.y * ORBIT_RATE
	place()

## Pans by a drag in pixels across a view `h` pixels high.
func pan(d: Vector2, h: float) -> void:
	var per_px := 2.0 * dist * tan(deg_to_rad(fov * 0.5)) / maxf(h, 1.0)
	var b := global_transform.basis
	target += (-b.x * d.x + b.y * d.y) * per_px
	place()

func zoom(f: float) -> void:
	dist *= f
	place()

## A pointer event over the view (in the view's pixels). True when it was the camera's.
func handle(e: InputEvent, view_h: float) -> bool:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		return false
	if e is InputEventScreenDrag:
		var before: Vector2 = _touches.get(e.index, e.position - e.relative)
		_touches[e.index] = e.position
		if _touches.size() == 1:
			orbit(e.relative)
		elif _touches.size() >= 2:
			var ks: Array = _touches.keys()
			var other: Vector2 = _touches[ks[0] if ks[0] != e.index else ks[1]]
			var d0 := before.distance_to(other)
			var d1: float = e.position.distance_to(other)
			if d0 > 1.0 and d1 > 1.0:
				zoom(d0 / d1)
			pan(e.relative * 0.5, view_h)
		return true
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(0.9)
			return true
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.0 / 0.9)
			return true
	if e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		if e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			orbit(e.relative)
			return true
		if e.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			pan(e.relative, view_h)
			return true
	return false

## The gamepad's sticks (the look and move actions), each frame.
func sticks(delta: float) -> void:
	var lv := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if lv.length() < 0.15 and mv.length() < 0.15:
		return
	yaw -= lv.x * PAD_RATE * delta
	pitch -= lv.y * PAD_RATE * delta
	if absf(mv.y) > 0.15:
		dist *= pow(0.4, mv.y * delta)
	if absf(mv.x) > 0.15:
		target += global_transform.basis.x * mv.x * dist * delta
	place()
