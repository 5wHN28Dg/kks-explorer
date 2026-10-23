## The people's assets (decisions 0063, 0064; docs/PLANT3D.md §18.2–§18.4), made by the content build into
## built/people/:
##   avatar.tscn            the skinned avatar: our skeleton (builder/people/rig.gd), a body mesh, an AnimationPlayer
##                          with every clip (KayKit's, retargeted, and our own work poses)
##   look_<id>_<lod>.res    each look's skinned mesh (builder/people/looks.gd, builder/people/body.gd), LOD 0 and 1
##   posed_<id>_<pose>.res  each look's posed band mesh in each pose: unskinned, baked here from the clips
##   people.json            what the app needs: the looks and their files, the roles' looks, the clips, the gaits'
##                          natural speeds (the app scales a clip's speed to the person's, so feet don't slide), the
##                          triangle counts
extends RefCounted

const Rig = preload("res://builder/people/rig.gd")
const Body = preload("res://builder/people/body.gd")
const Looks = preload("res://builder/people/looks.gd")
const Materials = preload("res://kit/materials.gd")

## The posed band's six poses (docs/PLANT3D.md §18.4): a clip and the moment of its cycle.
const POSES := {"stand": ["idle", 0.0], "walk_a": ["walk", 0.25], "walk_b": ["walk", 0.75], "sit": ["sit", 0.0],
	"work": ["handwheel", 0.0], "carry": ["carry", 0.25]}
const BUDGET := {"lod0": 4000, "lod1": 1500, "posed": 500}
const MAX_BONES := 56

var errors: PackedStringArray = []


## Builds into `out` (res://built/people). Returns the summary written to people.json, or {} with `errors` set.
func build(out: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var rig := Rig.new()
	var e := rig.load_kaykit()
	if e != "":
		errors.append(e)
		return {}
	if rig.names.size() > MAX_BONES:
		errors.append("people: %d bones, the budget is %d" % [rig.names.size(), MAX_BONES])
	# the clips: KayKit's on our skeleton, and ours
	var lib := AnimationLibrary.new()
	for k in Rig.CLIPS:
		var c: Array = Rig.CLIPS[k]
		var a := rig.clip(c[0], c[1], c[2], Rig.LEG_SWING.get(k, 1.0))
		if a == null:
			errors.append("people: no clip %s in Rig_Medium_%s.glb" % [c[1], c[0]])
			continue
		lib.add_animation(k, a)
	var own := rig.own_clips()
	for k in own:
		lib.add_animation(k, own[k])
	rig.free_sources()
	# the material: the plant's one shader, colours from the vertices (decision 0060: no pipeline of its own)
	var mat := Materials.plain(Color.WHITE)
	mat.set_shader_parameter("use_vertex_colour", true)
	mat.resource_name = "people"
	ResourceSaver.save(mat, out.path_join("people_mat.tres"))
	mat = load(out.path_join("people_mat.tres"))
	var looks := {}
	var tri := {"lod0": 0, "lod1": 0, "posed": 0}
	var skel := rig.skeleton
	for id in Looks.LOOKS:
		var look := Looks.look(id)
		var entry := {"posed": {}}
		for lod in [0, 1]:
			var m := Body.make(rig.names, look, 2 - lod)
			m.surface_set_material(0, mat)
			var n := _tris(m)
			tri["lod%d" % lod] = maxi(tri["lod%d" % lod], n)
			var path := out.path_join("look_%s_%d.res" % [id, lod])
			ResourceSaver.save(m, path)
			entry["lod%d" % lod] = path
		var low := Body.make(rig.names, look, 0)
		tri.posed = maxi(tri.posed, _tris(low))
		for pose in POSES:
			var clip: Animation = lib.get_animation(POSES[pose][0])
			var pm := _posed(low, skel, clip, clip.length * float(POSES[pose][1]))
			pm.surface_set_material(0, mat)
			var path := out.path_join("posed_%s_%s.res" % [id, pose])
			ResourceSaver.save(pm, path)
			entry.posed[pose] = path
		looks[id] = entry
	for k in BUDGET:
		if tri[k] > BUDGET[k]:
			errors.append("people: %s mesh has %d triangles, the budget is %d (docs/PLANT3D.md §18.4)" % [k, tri[k], BUDGET[k]])
	# the gaits' natural speeds: how fast the stance foot moves back under the body; a stair's along its slope (two
	# steps of 0.28 m going and 0.18 m rise a cycle: people's speed on a stair is along it)
	var speeds := {"walk": _gait_speed(skel, lib.get_animation("walk")), "run": _gait_speed(skel, lib.get_animation("run")),
		"stairs": Vector2(0.28, 0.18).length() * 2.0 / lib.get_animation("stairs").length, "climb": 0.6 / lib.get_animation("climb").length}
	# the avatar scene
	var root := Node3D.new()
	root.name = "Avatar"
	var sk := skel.duplicate() as Skeleton3D
	root.add_child(sk)
	sk.owner = root
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = load(looks[Looks.LOOKS.keys()[0]].lod0)
	mi.skin = sk.create_skin_from_rest_transforms()
	sk.add_child(mi)
	mi.owner = root
	mi.skeleton = NodePath("..")
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	ap.add_animation_library("", lib)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(ap)
	ap.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var avatar := out.path_join("avatar.tscn")
	if ResourceSaver.save(ps, avatar) != OK:
		errors.append("people: cannot save " + avatar)
	root.free()
	var clips := PackedStringArray(lib.get_animation_list())
	var summary := {"format": "walkdown-plant-people", "version": 1, "avatar": avatar, "looks": looks,
		"roles": Looks.ROLE_LOOK, "clips": clips, "speeds": speeds, "triangles": tri, "bones": rig.names.size(),
		"poses": POSES.keys()}
	var f := FileAccess.open(out.path_join("people.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, " ", false))
	f.close()
	return summary


static func _tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var idx = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


## Every bone's pose (global, model space) in `clip` at time `t` on skeleton `sk` (its rests where the clip has no track).
static func global_pose(sk: Skeleton3D, clip: Animation, t: float) -> Array:
	var local: Array = []
	for i in sk.get_bone_count():
		local.append(sk.get_bone_rest(i))
	for tr in clip.get_track_count():
		var bone := str(clip.track_get_path(tr)).get_slice(":", 1)
		var i := sk.find_bone(bone)
		if i < 0:
			continue
		match clip.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				var x: Transform3D = local[i]
				local[i] = Transform3D(Basis(clip.rotation_track_interpolate(tr, t)), x.origin)
			Animation.TYPE_POSITION_3D:
				var x: Transform3D = local[i]
				local[i] = Transform3D(x.basis, clip.position_track_interpolate(tr, t))
	var g: Array = []
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		g.append(local[i] if p < 0 else (g[p] as Transform3D) * local[i])
	return g


## The skinned mesh `m` posed as `clip` at `t`, as an unskinned mesh in the plant's vertex format.
static func _posed(m: ArrayMesh, sk: Skeleton3D, clip: Animation, t: float) -> ArrayMesh:
	var g := global_pose(sk, clip, t)
	var skin: Array = []
	for i in sk.get_bone_count():
		skin.append((g[i] as Transform3D) * sk.get_bone_global_rest(i).affine_inverse())
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	nv.resize(v.size())
	nn.resize(v.size())
	for i in v.size():
		var p := Vector3.ZERO
		var q := Vector3.ZERO
		for k in 4:
			var wk := w[i * 4 + k]
			if wk <= 0.0:
				continue
			var x: Transform3D = skin[bones[i * 4 + k]]
			p += (x * v[i]) * wk
			q += (x.basis * n[i]) * wk
		nv[i] = p
		nn[i] = q.normalized()
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_TANGENT] = a[Mesh.ARRAY_TANGENT]
	out[Mesh.ARRAY_TEX_UV] = a[Mesh.ARRAY_TEX_UV]
	out[Mesh.ARRAY_COLOR] = a[Mesh.ARRAY_COLOR]
	out[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
	var pm := ArrayMesh.new()
	pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return pm


## A walking or running clip's natural speed (m/s): the stance foot's speed backwards under the hips, while it is
## within 3 cm of its lowest.
static func _gait_speed(sk: Skeleton3D, clip: Animation) -> float:
	var n := 240
	var ys := []
	var zs := []
	var foot := sk.find_bone("foot.l")
	var hips := sk.find_bone("hips")
	for k in n + 1:
		var g := global_pose(sk, clip, clip.length * k / n)
		var p: Vector3 = (g[foot] as Transform3D).origin
		var h: Vector3 = (g[hips] as Transform3D).origin
		ys.append(p.y)
		zs.append(p.z - h.z)
	var low: float = ys.min()
	var dist := 0.0
	var time := 0.0
	for k in n:
		if ys[k] < low + 0.03 and ys[k + 1] < low + 0.03:
			dist += zs[k] - zs[k + 1]
			time += clip.length / n
	return dist / time if time > 0.0 else 0.0
