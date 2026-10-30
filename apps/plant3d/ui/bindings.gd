## The model's bindings (docs/PLANT3D.md §7.7) on the built plant: moving parts, lamps, local displays and camera
## shake follow the engine's values every frame.
##
## The parts kit names each moving piece as a child node of its equipment's node (the node named by the KKS code),
## called by its channel, with the metas `anim_kind` (rotate, translate, scale, lamp, group), `anim_axis` and
## `anim_travel` (apps/plant3d/kit/README.md "Moving parts"): those are followed. Without them (the placeholders):
## `shaft`, `blades`, `handwheel` turn about the piece's own Y axis; `stem` and `contacts`
## move along their own Y axis by the value (0–1) times their `travel` meta (metres, default 0.2); `disc` turns about
## its own Y axis by the value times its `angle` meta (degrees, default 90); `needle` turns about its own Z axis
## from its `angle0` to its `angle1` meta (degrees, default 45 and −225) over the value's 0–1; `level` scales its
## own Y by the value. Lamps are children `lamp_<kind>` (`lamp_running`, …) whose material is swapped for a lit or
## an unlit one. Where the kit has no such child yet, a small placeholder marker stands in, so that a trainee sees
## the state change now (these markers carry the meta `ui` and are not part of the plant's geometry).
extends Node

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const Mat = preload("res://kit/materials.gd")
const RANGE := 60.0             # metres: farther parts are not updated (nobody sees them move)
const SHOW_RANGE := 8.0         # local displays are read up close
const SHAKE_RANGE := 15.0

var engine
var index                       # ui/scene_index.gd
var cam: Camera3D
var reduced_motion := false
var sounds                      # ui/sound_player.gd or null
var clock                       # ui/sim_clock.gd: shafts turn with plant time (still while paused, faster at fast-forward)
var _anims: Array = []          # [node, channel, slot, scale, base transform, group's kids, position, anim_kind]
var _near: Array = []           # the _anims within RANGE + NEAR_MARGIN of _near_eye: the only ones looked at each frame
var _near_eye := Vector3.INF    # where the eye was when _near was made (made again once it has moved NEAR_MARGIN)
const NEAR_MARGIN := 10.0
var _lamps: Array = []          # [node, slot, kind, lit material, unlit material, last]
var _shows: Array = []          # [label, slot, value name, last text]
var _shakes: Array = []         # [node position, slot, scale]
var _info
## Lifting gear (PLANT3D §20.5, kit/README.md "Moving parts"): pieces that slide by a value in metres or stretch to
## it, drawn between the model's last two steps by the clock's fraction of a step; and the codes that ride on them
var _slides: Array = []         # [piece, slot, kind, axis (node axes), travel, base transform, last value drawn]
var _riders: Array = []         # [unit's node, the piece it rides on, its transform in the piece's frame, code]
var _t_show := 0.0
var _mat_cache := {}


func setup(e, idx, info, camera: Camera3D) -> void:
	engine = e
	index = idx
	_info = info
	cam = camera
	_anims.clear(); _lamps.clear(); _shows.clear(); _shakes.clear(); _near.clear(); _slides.clear(); _riders.clear()
	_near_eye = Vector3.INF
	if sounds != null:
		sounds.unbind_all()
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
			if String(piece.get_meta("anim_kind", "")) in ["slide", "stretch"]:
				_slides.append([piece, e.ix[b["of"]], String(piece.get_meta("anim_kind")),
						(piece.get_meta("anim_axis", Vector3.UP) as Vector3).normalized(), float(piece.get_meta("anim_travel", 1.0)),
						_base(piece), NAN])
				continue
			var kids := []
			if piece.get_meta("anim_kind", "") == "group":
				for ch in piece.get_children():
					if ch is Node3D and ch.has_meta("anim_kind"):
						kids.append([ch, ch.transform])
			# (where the piece is, for the range: a piece turns or moves by a few centimetres, never across the plant;
			# its kind read once, not every frame)
			_anims.append([piece, b["anim"], e.ix[b["of"]], float(b.get("scale", 1.0)), piece.transform, kids,
					piece.global_position if piece.is_inside_tree() else Vector3.INF,
					String(piece.get_meta("anim_kind", ""))])
			if b["anim"] == "contacts" and sounds != null:
				sounds.watch_breaker(n, e.ix[b["of"]])
		elif b.has("lamp"):
			var lamp := _lamp(n, b["lamp"], idx.box(b["kks"]))
			_lamps.append([lamp, e.ix[b["of"]], b["lamp"], _mat(b["lamp"], true), _mat(b["lamp"], false), -1])
		elif b.has("show"):
			var old := n.find_child("ui_show", false, false)
			if old != null:
				old.free()
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
			if sounds != null and sounds.is_surge(info.units.get(b["shake"], "")):
				sounds.watch_surge(n, e.ix[b["shake"]], float(b.get("scale", 1.0)))


	_ride_setup()


## The piece's transform as built (value 0), kept on it: a second setup finds it moved.
static func _base(piece: Node3D) -> Transform3D:
	if not piece.has_meta("anim_base"):
		piece.set_meta("anim_base", piece.transform)
	return piece.get_meta("anim_base")


## The codes riding on a hoist (`hoist_unit` parts, kit/parts_hoists.gd): each with the piece it rides on, and where
## it stands in that piece's frame as both were built.
const RIDES := {"hoist": "trolley", "trolley": "trolley", "bridge": "bridge", "latch": "hook", "load_cell": "hook"}
func _ride_setup() -> void:
	for a in _info.m.areas:
		for e in a.get("equipment", []):
			if not e.get("part", "") in ["monorail_hoist", "overhead_crane"]:
				continue
			var host: Node3D = index.nodes.get(e["kks"])
			if host == null:
				continue
			for c in e.get("parts", []):
				var un: Node3D = index.nodes.get(c["kks"])
				var piece := host.find_child(String(RIDES.get(c.get("params", {}).get("kind", ""), "")), true, false) as Node3D
				if un == null or piece == null or not un.is_inside_tree():
					continue
				if not un.has_meta("ride_offset"):
					un.set_meta("ride_offset", piece.global_transform.affine_inverse() * un.global_transform)
				_riders.append([un, piece, un.get_meta("ride_offset"), String(c["kks"])])


## The clock's fraction of a step since the last one (0 to 1): pieces are drawn between the last two steps' values.
## A session's steps come from it (the clock does not step by itself): the last step's values, then.
func _frac() -> float:
	if clock == null or clock.driven:
		return 1.0
	return clampf(clock.acc / clock.STEP, 0.0, 1.0)


## Lifting gear's pieces at their values, interpolated; the riding codes with them (and their bounds made again: their
## cards' reach and "Show me"). Nothing is done while nothing moves.
func _each_slide() -> void:
	if _slides.is_empty() or engine == null:
		return
	var cur: PackedFloat64Array = engine.cur
	var prev: PackedFloat64Array = engine.prev
	var f := _frac()
	var moved := false
	for sl in _slides:
		var k: int = sl[1]
		var x: float = cur[k] if prev.size() <= k else lerpf(prev[k], cur[k], f)
		if x == sl[6]:
			continue
		sl[6] = x
		moved = true
		var piece: Node3D = sl[0]
		var base: Transform3D = sl[5]
		var ax: Vector3 = sl[3]
		if sl[2] == "slide":
			piece.transform = Transform3D(base.basis, base.origin + base.basis * (ax * x * float(sl[4])))
		else:
			var a := ax.abs()
			var len := maxf(float(sl[4]) - x, 0.001)
			piece.transform = Transform3D(base.basis * Basis.from_scale(Vector3.ONE - a + a * len), base.origin)
	if moved:
		for r in _riders:
			(r[0] as Node3D).global_transform = (r[1] as Node3D).global_transform * (r[2] as Transform3D)
			index.forget(r[3])


## Points the bindings at another engine (a restarted scenario) without rebuilding the nodes: slots are the same.
func use_engine(e) -> void:
	engine = e


func _piece(n: Node3D, channel: String, bx: AABB) -> Node3D:
	var found := n.find_child(channel, true, false)
	if found is Node3D:
		return found            # the kit's piece, or the placeholder made by an earlier setup
	# a placeholder: a marker on top of the part, in the part's frame
	var mk := MeshInstance3D.new()
	mk.name = channel
	mk.set_meta("ui", true)
	var top := n.to_local(Vector3(bx.get_center().x, bx.end.y, bx.get_center().z))
	match channel:
		"shaft", "blades", "handwheel":
			var m := BoxMesh.new(); m.size = Vector3(0.9, 0.06, 0.12); mk.mesh = Mat.plant_mesh(m)
			mk.position = top + Vector3(0, 0.08, 0)
		"stem", "contacts":
			var c := CylinderMesh.new(); c.top_radius = 0.04; c.bottom_radius = 0.04; c.height = 0.4; mk.mesh = Mat.plant_mesh(c)
			mk.position = top + Vector3(0, 0.2, 0)
			mk.set_meta("travel", 0.3)
		"disc":
			var d := CylinderMesh.new(); d.top_radius = 0.25; d.bottom_radius = 0.25; d.height = 0.03; mk.mesh = Mat.plant_mesh(d)
			mk.position = top + Vector3(0, 0.3, 0)
			mk.rotation.x = PI * 0.5
		"level":
			var lv := BoxMesh.new(); lv.size = Vector3(0.1, 1.0, 0.1); mk.mesh = Mat.plant_mesh(lv)
			mk.position = top + Vector3(0, 0.5, 0)
		_:
			var s := SphereMesh.new(); s.radius = 0.08; s.height = 0.16; mk.mesh = Mat.plant_mesh(s)
			mk.position = top + Vector3(0, 0.1, 0)
	mk.material_override = _mat("marker", true)
	n.add_child(mk)
	return mk


## A kit piece by its metas: free rotation at x × scale turns a second, or a position x (0–1) × its travel.
static func _kit_move(piece: Node3D, base: Transform3D, x: float, scale: float, dt: float) -> void:
	var axis: Vector3 = piece.get_meta("anim_axis", Vector3.UP)
	var travel := float(piece.get_meta("anim_travel", 0.0))
	var v := clampf(x, 0.0, 1.0)
	match String(piece.get_meta("anim_kind")):
		"rotate":
			if travel == 0.0:
				piece.rotate_object_local(axis.normalized(), fmod(x * scale * TAU * dt, TAU))
			else:
				piece.transform = base.rotated_local(axis.normalized(), v * travel)
		"translate":
			piece.transform = base.translated_local(axis * v * travel)
		"scale":
			var a := axis.abs()
			piece.transform = base.scaled_local(Vector3.ONE - a + a * maxf(v, 0.001))
		"lamp":
			var on := piece.get_node_or_null("on")
			if on is Node3D:
				on.visible = x >= 0.5


func _lamp(n: Node3D, kind: String, bx: AABB) -> MeshInstance3D:
	var found := n.find_child("lamp_" + kind, true, false)
	if found is MeshInstance3D:
		return found
	var mk := MeshInstance3D.new()
	mk.name = "lamp_" + kind
	mk.set_meta("ui", true)
	var s := SphereMesh.new(); s.radius = 0.1; s.height = 0.2; s.radial_segments = 8; s.rings = 4
	mk.mesh = Mat.plant_mesh(s)
	mk.position = n.to_local(Vector3(bx.end.x, bx.end.y + 0.15, bx.get_center().z))
	n.add_child(mk)
	return mk


const LAMP_COLOURS := {"running": Color(0.1, 0.9, 0.2), "stopped": Color(0.9, 0.15, 0.1), "open": Color(0.1, 0.9, 0.2),
		"closed": Color(0.9, 0.15, 0.1), "fault": Color(1.0, 0.6, 0.0), "beacon": Color(1.0, 0.5, 0.0),
		"marker": Color(0.95, 0.85, 0.2)}


## The plant's own shader (kit/materials.gd `plain`), not Godot's standard material: another shader would be pipelines
## of its own, compiled before a phone's first frame (decision 0060).
func _mat(kind: String, lit: bool) -> ShaderMaterial:
	var key := "%s/%s" % [kind, lit]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var c: Color = LAMP_COLOURS.get(kind, Color.WHITE)
	var m := Mat.plain(c if lit else c.darkened(0.75), lit)
	_mat_cache[key] = m
	return m


func _process(delta: float) -> void:
	var _c0 := Time.get_ticks_usec()
	_each_frame(delta)
	Cost.add(Cost.BINDINGS, _c0)


func _each_frame(delta: float) -> void:
	if engine == null or cam == null:
		return
	_each_slide()
	var eye := cam.global_position
	var cur: PackedFloat64Array = engine.cur
	var dt: float = delta * (clock.rate() if clock != null else 1.0)
	# (the pieces near the eye, found again only when it has moved far enough that one could have come in range)
	if _near_eye == Vector3.INF or _near_eye.distance_squared_to(eye) > NEAR_MARGIN * NEAR_MARGIN:
		_near_eye = eye
		_near.clear()
		for a in _anims:
			if a[6] == Vector3.INF and (a[0] as Node3D).is_inside_tree():
				a[6] = (a[0] as Node3D).global_position
			if (a[6] as Vector3).distance_to(eye) <= RANGE + NEAR_MARGIN:
				_near.append(a)
	for a in _near:
		if (a[6] as Vector3).distance_squared_to(eye) > RANGE * RANGE:
			continue
		var piece: Node3D = a[0]
		var x: float = cur[a[2]]
		if a[7] != "":
			if a[7] == "group":
				for ch in a[5]:
					_kit_move(ch[0], ch[1], x, a[3], dt)
			else:
				_kit_move(piece, a[4], x, a[3], dt)
			continue
		match a[1]:
			"shaft", "blades", "handwheel":
				piece.rotate_object_local(Vector3.UP, fmod(x * a[3] * TAU * dt, TAU))
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
