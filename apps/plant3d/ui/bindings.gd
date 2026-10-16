## The model's bindings (docs/PLANT3D.md §7.7) on the built plant: moving parts, lamps, local displays and camera
## shake follow the engine's values every frame.
##
## The parts kit names each moving piece as a child node of its equipment's node (the node named by the KKS code),
## called by its channel: `shaft`, `blades`, `handwheel` turn about the piece's own Y axis; `stem` and `contacts`
## move along their own Y axis by the value (0–1) times their `travel` meta (metres, default 0.2); `disc` turns about
## its own Y axis by the value times its `angle` meta (degrees, default 90); `needle` turns about its own Z axis
## from its `angle0` to its `angle1` meta (degrees, default 45 and −225) over the value's 0–1; `level` scales its
## own Y by the value. Lamps are children `lamp_<kind>` (`lamp_running`, …) whose material is swapped for a lit or
## an unlit one. Where the kit has no such child yet, a small placeholder marker stands in, so that a trainee sees
## the state change now (these markers carry the meta `ui` and are not part of the plant's geometry).
extends Node

const RANGE := 60.0             # metres: farther parts are not updated (nobody sees them move)
const SHOW_RANGE := 8.0         # local displays are read up close
const SHAKE_RANGE := 15.0

var engine
var index                       # ui/scene_index.gd
var cam: Camera3D
var reduced_motion := false
var sounds                      # ui/sound_player.gd or null
var _anims: Array = []          # [node, channel, slot, scale, base transform, meta]
var _lamps: Array = []          # [node, slot, kind, lit material, unlit material, last]
var _shows: Array = []          # [label, slot, value name, last text]
var _shakes: Array = []         # [node position, slot, scale]
var _info
var _t_show := 0.0
var _mat_cache := {}


func setup(e, idx, info, camera: Camera3D) -> void:
	engine = e
	index = idx
	_info = info
	cam = camera
	_anims.clear(); _lamps.clear(); _shows.clear(); _shakes.clear()
	for b in info.m.bind:
		var n: Node3D = idx.nodes.get(b["kks"])
		if b.has("sound"):
			if sounds != null and n != null:
				sounds.bind(b, n)
			continue
		if n == null:
			continue
		if b.has("anim"):
			var piece := _piece(n, b["anim"], idx.box(b["kks"]))
			_anims.append([piece, b["anim"], e.ix[b["of"]], float(b.get("scale", 1.0)), piece.transform])
		elif b.has("lamp"):
			var lamp := _lamp(n, b["lamp"], idx.box(b["kks"]))
			_lamps.append([lamp, e.ix[b["of"]], b["lamp"], _mat(b["lamp"], true), _mat(b["lamp"], false), -1])
		elif b.has("show"):
			var l := Label3D.new()
			l.set_meta("ui", true)
			l.name = "ui_show"
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.pixel_size = 0.0015
			l.font_size = 48
			l.outline_size = 10
			l.modulate = Color(1, 0.95, 0.6)
			l.visibility_range_end = SHOW_RANGE
			n.add_child(l)
			var bx: AABB = idx.box(b["kks"])
			l.global_position = Vector3(bx.get_center().x, bx.end.y + 0.12, bx.get_center().z)
			_shows.append([l, e.ix[b["show"]], b["show"], ""])
		elif b.has("shake"):
			_shakes.append([idx.center(b["kks"]), e.ix[b["shake"]], float(b.get("scale", 1.0))])


## Points the bindings at another engine (a restarted scenario) without rebuilding the nodes: slots are the same.
func use_engine(e) -> void:
	engine = e


func _piece(n: Node3D, channel: String, bx: AABB) -> Node3D:
	var found := n.find_child(channel, true, false)
	if found is Node3D and not found.has_meta("ui"):
		return found
	# a placeholder: a marker on top of the part, in the part's frame
	var mk := MeshInstance3D.new()
	mk.name = channel
	mk.set_meta("ui", true)
	var top := n.to_local(Vector3(bx.get_center().x, bx.end.y, bx.get_center().z))
	match channel:
		"shaft", "blades", "handwheel":
			var m := BoxMesh.new(); m.size = Vector3(0.9, 0.06, 0.12); mk.mesh = m
			mk.position = top + Vector3(0, 0.08, 0)
		"stem", "contacts":
			var c := CylinderMesh.new(); c.top_radius = 0.04; c.bottom_radius = 0.04; c.height = 0.4; mk.mesh = c
			mk.position = top + Vector3(0, 0.2, 0)
			mk.set_meta("travel", 0.3)
		"disc":
			var d := CylinderMesh.new(); d.top_radius = 0.25; d.bottom_radius = 0.25; d.height = 0.03; mk.mesh = d
			mk.position = top + Vector3(0, 0.3, 0)
			mk.rotation.x = PI * 0.5
		"level":
			var lv := BoxMesh.new(); lv.size = Vector3(0.1, 1.0, 0.1); mk.mesh = lv
			mk.position = top + Vector3(0, 0.5, 0)
		_:
			var s := SphereMesh.new(); s.radius = 0.08; s.height = 0.16; mk.mesh = s
			mk.position = top + Vector3(0, 0.1, 0)
	mk.material_override = _mat("marker", true)
	n.add_child(mk)
	return mk


func _lamp(n: Node3D, kind: String, bx: AABB) -> MeshInstance3D:
	var found := n.find_child("lamp_" + kind, true, false)
	if found is MeshInstance3D:
		return found
	var mk := MeshInstance3D.new()
	mk.name = "lamp_" + kind
	mk.set_meta("ui", true)
	var s := SphereMesh.new(); s.radius = 0.1; s.height = 0.2; s.radial_segments = 8; s.rings = 4
	mk.mesh = s
	mk.position = n.to_local(Vector3(bx.end.x, bx.end.y + 0.15, bx.get_center().z))
	n.add_child(mk)
	return mk


const LAMP_COLOURS := {"running": Color(0.1, 0.9, 0.2), "stopped": Color(0.9, 0.15, 0.1), "open": Color(0.1, 0.9, 0.2),
		"closed": Color(0.9, 0.15, 0.1), "fault": Color(1.0, 0.6, 0.0), "beacon": Color(1.0, 0.5, 0.0),
		"marker": Color(0.95, 0.85, 0.2)}


func _mat(kind: String, lit: bool) -> StandardMaterial3D:
	var key := "%s/%s" % [kind, lit]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var c: Color = LAMP_COLOURS.get(kind, Color.WHITE)
	var m := StandardMaterial3D.new()
	m.albedo_color = c if lit else c.darkened(0.75)
	if lit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.0
	_mat_cache[key] = m
	return m


func _process(delta: float) -> void:
	if engine == null or cam == null:
		return
	var eye := cam.global_position
	var cur: PackedFloat64Array = engine.cur
	for a in _anims:
		var piece: Node3D = a[0]
		if piece.global_position.distance_squared_to(eye) > RANGE * RANGE:
			continue
		var x: float = cur[a[2]]
		match a[1]:
			"shaft", "blades", "handwheel":
				piece.rotate_object_local(Vector3.UP, x * a[3] * TAU * delta)
			"stem", "contacts":
				var base: Transform3D = a[4]
				piece.transform = base.translated_local(Vector3.UP * clampf(x * a[3], 0, 1) * float(piece.get_meta("travel", 0.2)))
			"disc":
				var base2: Transform3D = a[4]
				piece.transform = base2.rotated_local(Vector3.UP, deg_to_rad(float(piece.get_meta("angle", 90.0))) * clampf(x * a[3], 0, 1))
			"needle":
				var base3: Transform3D = a[4]
				var a0 := deg_to_rad(float(piece.get_meta("angle0", 45.0)))
				var a1 := deg_to_rad(float(piece.get_meta("angle1", -225.0)))
				piece.transform = base3.rotated_local(Vector3.BACK, lerpf(a0, a1, clampf(x * a[3], 0, 1)))
			"level":
				var base4: Transform3D = a[4]
				piece.transform = base4.scaled_local(Vector3(1, maxf(0.01, clampf(x * a[3], 0, 1)), 1))
	for l in _lamps:
		var on := 1 if cur[l[1]] >= 0.5 else 0
		if on != l[5]:
			l[5] = on
			(l[0] as MeshInstance3D).material_override = l[3] if on == 1 else l[4]
	_t_show += delta
	if _t_show >= 0.25:
		_t_show = 0.0
		for s in _shows:
			var lab: Label3D = s[0]
			if lab.global_position.distance_squared_to(eye) > SHOW_RANGE * SHOW_RANGE:
				continue
			var t: String = _info.fmt(s[2], cur[s[1]])
			if t != s[3]:
				s[3] = t
				lab.text = t
	var shake := 0.0
	if not reduced_motion:
		for k in _shakes:
			var d: float = (k[0] as Vector3).distance_to(eye)
			if d < SHAKE_RANGE:
				shake = maxf(shake, cur[k[1]] * k[2] * (1.0 - d / SHAKE_RANGE))
	shake = clampf(shake, 0.0, 1.0) * 0.02
	cam.h_offset = randf_range(-shake, shake)
	cam.v_offset = randf_range(-shake, shake)
