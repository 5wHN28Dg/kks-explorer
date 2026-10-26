## Points at equipment in the plant: a glowing box round it, seen through walls, and an arrow bobbing above it. The
## HUD (ui/plant_ui.gd) adds the arrow at the screen's edge and the distance when it is out of view.
extends Node3D

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

var code := ""
var box := AABB()
var _frame: MeshInstance3D
var _arrow: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	set_meta("ui", true)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.no_depth_test = true
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(1.0, 0.55, 0.0, 0.22)
	_frame = MeshInstance3D.new()
	_frame.mesh = BoxMesh.new()
	_frame.material_override = glow
	_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.ignore_occlusion_culling = true   # seen through walls: the buildings' occluders must not cull it
	add_child(_frame)
	var solid := glow.duplicate()
	solid.albedo_color = Color(1.0, 0.55, 0.0, 0.9)
	_arrow = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.35
	cone.height = 0.8
	cone.radial_segments = 12
	_arrow.mesh = cone
	_arrow.rotation.x = PI           # point down
	_arrow.material_override = solid
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.ignore_occlusion_culling = true
	add_child(_arrow)
	visible = false


func point(c: String, b: AABB) -> void:
	code = c
	box = b
	var grown := b.grow(0.15)
	(_frame.mesh as BoxMesh).size = grown.size
	_frame.global_position = grown.get_center()
	visible = c != ""


func clear() -> void:
	code = ""
	visible = false


func top() -> Vector3:
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)


func _process(delta: float) -> void:
	var _c0 := Time.get_ticks_usec()
	_each_frame(delta)
	Cost.add(Cost.OTHER, _c0)


func _each_frame(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var s := maxf(1.0, box.size.length() * 0.08)
	_arrow.scale = Vector3.ONE * s
	_arrow.global_position = top() + Vector3.UP * (0.8 * s + 0.25 * sin(_t * 4.0))
	# the frame shows where it is from afar; up close (or inside it) only the arrow, so the part itself stays visible
	var cam := get_viewport().get_camera_3d()
	_frame.visible = cam == null or box.grow(3.0).has_point(cam.global_position) == false
	(_frame.material_override as StandardMaterial3D).albedo_color.a = 0.1 + 0.08 * (0.5 + 0.5 * sin(_t * 5.0))
