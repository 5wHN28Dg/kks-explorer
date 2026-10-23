## The 3D overview map (R7): the same plant seen from above by a camera of its own, with a marker at the trainee
## and the areas' names (render layer 2, which the walker's camera leaves out). Drag to pan, wheel or pinch to zoom,
## right-drag or two fingers' turn to rotate; a tap or click on a floor puts the trainee there.
extends Node3D

const LAYER := 2
var cam: Camera3D
var marker: MeshInstance3D
var target := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(-55.0)
var dist := 260.0
var active := false
var player   # app/player.gd
var _touches := {}
var _moved := 0.0

signal jumped(to: Vector3)

func setup(p, plant) -> void:
	player = p
	cam = Camera3D.new()
	cam.fov = 50
	cam.far = 3000
	add_child(cam)
	marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.5
	cone.height = 6.0
	marker.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	marker.material_override = mat
	marker.layers = 1 << (LAYER - 1)
	marker.ignore_occlusion_culling = true   # over the trainee, under a hall's roof: drawn through it
	marker.rotation.x = -PI * 0.5   # the cone's tip points the way the trainee faces
	add_child(marker)
	for a in plant.manifest.areas:
		var b: Array = a.bounds
		var l := Label3D.new()
		l.text = a.title
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.pixel_size = 0.05
		l.font_size = 48
		l.outline_size = 10
		l.layers = 1 << (LAYER - 1)
		l.ignore_occlusion_culling = true
		l.position = Vector3((b[0][0] + b[1][0]) * 0.5, 45.0, -(b[0][1] + b[1][1]) * 0.5)
		add_child(l)
	var r: Rect2 = plant.extent()
	target = Vector3(r.get_center().x, 0, -r.get_center().y)
	visible = false

func show_map(on: bool) -> void:
	active = on
	visible = on
	if on:
		cam.make_current()
		target = Vector3(player.global_position.x, 0, player.global_position.z)
	else:
		player.camera.make_current()

func _process(_delta: float) -> void:
	if not active:
		return
	marker.global_position = player.global_position + Vector3.UP * 4.0
	marker.global_rotation = Vector3(-PI * 0.5, player.rotation.y, 0)
	var off := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, dist)
	cam.global_position = target + off
	cam.look_at(target, Vector3.UP)
	# keyboard and gamepad pan the map
	var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if mv.length() > 0.0:
		target += Basis(Vector3.UP, yaw) * Vector3(mv.x, 0, -mv.y) * dist * 0.02

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if (e is InputEventMouseButton or e is InputEventMouseMotion) and e.device == InputEvent.DEVICE_ID_EMULATION:
		return   # a mouse event Godot made from a touch: the touch itself is handled
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: dist = maxf(20.0, dist * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: dist = minf(900.0, dist * 1.1)
		elif e.button_index == MOUSE_BUTTON_LEFT: _moved = 0.0
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _moved < 8.0:
		_jump(e.position)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_pan(e.relative)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		yaw -= e.relative.x * 0.005
		pitch = clampf(pitch - e.relative.y * 0.005, deg_to_rad(-89), deg_to_rad(-15))
	elif e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			_moved = 0.0
		else:
			_touches.erase(e.index)
			if _touches.is_empty() and _moved < 12.0:
				_jump(e.position)
	elif e is InputEventScreenDrag:
		if _touches.size() == 2 and _touches.has(e.index):
			var other = _touches.keys().filter(func(k): return k != e.index)[0]
			var a: Vector2 = _touches[other]
			var before: Vector2 = _touches[e.index] - a
			var after: Vector2 = e.position - a
			if before.length() > 1.0:
				dist = clampf(dist * before.length() / maxf(after.length(), 1.0), 20.0, 900.0)
				yaw += before.angle_to(after)
			_moved += 100.0
		else:
			_pan(e.relative)
		_touches[e.index] = e.position

func _pan(rel: Vector2) -> void:
	_moved += rel.length()
	var k := dist * 0.0015
	target += Basis(Vector3.UP, yaw) * Vector3(-rel.x * k, 0, -rel.y * k)

## A tap: the trainee goes to the lowest floor under that point with room to stand (inside a building, not onto
## its roof; on the ground beside a placeholder, not on top of it). Nothing free there: nothing happens.
func _jump(screen: Vector2) -> void:
	var space := get_world_3d().direct_space_state
	var from := cam.project_ray_origin(screen)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 3000.0))
	if hit.is_empty():
		return
	var at: Vector3 = hit.position
	var best = null
	var top := at.y + 0.5
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	for i in 32:   # every surface below, top to bottom
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, top, at.z), Vector3(at.x, -60.0, at.z)))
		if down.is_empty():
			break
		if down.normal.y > 0.7:
			q.transform = Transform3D(Basis(), down.position + Vector3.UP * 0.95)
			# below ground only when nothing free is at or above it (a pit's floor under its grating is no landing)
			if space.intersect_shape(q, 1).is_empty() and (best == null or down.position.y > -0.5):
				best = down.position
		top = down.position.y - 0.05
	if best != null:
		jumped.emit(best)
