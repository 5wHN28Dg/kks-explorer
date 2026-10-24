## The crews on screen until their avatars (milestone A1): each person is a capsule at their logical place (§17.3:
## the engine's position is the truth), moved along a way by the fraction of its time gone, in a colour per role;
## and a dot per person on the overview map (its render layer). One MultiMesh each: two draw calls for everyone, the
## instances updated 4 times a second. The trainee's own person is not drawn (they are the walker).
extends Node3D

const Plant = preload("res://app/plant.gd")
const MAP_LAYER := 2
const COLOURS := {"shift_sup": Color(0.95, 0.95, 0.95), "ccr_op": Color(0.25, 0.55, 1.0),
		"field_op": Color(1.0, 0.8, 0.1), "elec_ap": Color(1.0, 0.45, 0.1), "mech_tech": Color(0.3, 0.75, 0.35),
		"elec_tech": Color(0.85, 0.35, 0.8), "ic_tech": Color(0.3, 0.85, 0.85)}

var ui
var capsules: MultiMeshInstance3D
var dots: MultiMeshInstance3D
var _t := 0.0
var _at: Array = []             # per place: its position (Godot frame)
var shown := 0                  # people drawn at the last update (tests)


func setup(u) -> void:
	ui = u
	capsules = _mm(_capsule(), 1)
	dots = _mm(_dot(), 1 << (MAP_LAYER - 1))


func _capsule() -> Mesh:
	var c := CapsuleMesh.new()
	c.radius = 0.25
	c.height = 1.75
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	c.material = mat
	return c


func _dot() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 2.0
	c.bottom_radius = 2.0
	c.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	c.material = mat
	return c


func _mm(mesh: Mesh, layers: int) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mi.multimesh = mm
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	update()


## Places every person now (also called by the tests).
func update() -> void:
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	var sm = e._sm if e != null else null
	if sm == null:
		capsules.multimesh.instance_count = 0
		dots.multimesh.instance_count = 0
		shown = 0
		return
	if _at.size() != sm.places.size():
		_at.clear()
		for pl in sm.places:
			_at.append(Plant.g(pl["at"][0], pl["at"][1], pl["at"][2]))
	var xs := []
	var cs := []
	for pi in sm.people.size():
		if pi == e.st_trainee:
			continue
		var p := Vector3.INF
		var leg: Array = e.sp_leg[pi]
		if not leg.is_empty():
			var k := clampf(float(e.step_no - leg[2]) / maxf(1.0, float(leg[3] - leg[2])), 0.0, 1.0)
			p = (_at[leg[0]] as Vector3).lerp(_at[leg[1]], k)
		elif e.sp_pos[pi] != -1:
			p = _at[e.sp_pos[pi]]
		if p == Vector3.INF:
			continue
		xs.append(p)
		cs.append(COLOURS.get(sm.people[pi]["role"], Color.GRAY))
	shown = xs.size()
	for mi in [capsules, dots]:
		var mm: MultiMesh = mi.multimesh
		mm.instance_count = xs.size()
		for i in xs.size():
			var lift := Vector3(0, 0.9, 0) if mi == capsules else Vector3(0, 4.0, 0)
			mm.set_instance_transform(i, Transform3D(Basis(), xs[i] + lift))
			mm.set_instance_color(i, cs[i])
