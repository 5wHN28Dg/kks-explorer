## The people on screen (milestone A1; docs/PLANT3D.md §18.2–§18.4; decisions 0063, 0064): the built assets within
## their budgets and in the plant's one shader and vertex format, the clip a person plays from what they are doing and
## how fast, the bands by distance (skinned LOD0 and LOD1, posed, nothing), the clips' rate by distance and out of
## view, and the tiers' shares.
extends RefCounted

const People = preload("res://app/people.gd")
const Quality = preload("res://app/quality.gd")
const SHADER := "res://kit/weathered.gdshader"
const FORMAT := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV
const SKIN := Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS
const ATTRS := FORMAT | SKIN | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3
## Every role of docs/plant3d/STAFF.md §1.
const ROLES := ["shift_sup", "ccr_op", "field_op", "elec_ap", "wtp_op", "shift_chem", "guard", "ic_tech", "ic_eng",
	"mech_tech", "mech_eng", "elec_tech", "elec_eng", "maint_sup", "chemist", "hse_officer", "plant_mgr", "ops_mgr",
	"maint_mgr", "contractor_sup", "contractor", "store", "driver", "camp"]
const SHARE := {"skinned": 2, "skinned_range": 25.0, "lod0_range": 10.0, "anim_near": 10.0, "posed_range": 80.0,
	"shadows": false}


func run(tree: SceneTree) -> Array:
	var p: Array = []
	if not People.available():
		return ["built/people/ is there (build.sh makes it)"]
	var info = JSON.parse_string(FileAccess.get_file_as_string(People.INFO))
	p += _assets(info)
	p += await _bands(tree, info)
	p += _shares(info)
	p += _crowd(tree)
	return p


## The measurement's crowd (app/crowd.gd) keeps round the walker when the walk goes round its loop: nobody jumps.
func _crowd(tree: SceneTree) -> Array:
	var p: Array = []
	var root := Node3D.new()
	tree.root.add_child(root)
	var ppl = People.new()
	root.add_child(ppl)
	ppl.setup({})
	var walker := Node3D.new()
	root.add_child(walker)
	var route := []
	for q in [Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(100, 0, -100), Vector3(0, 0, -100), Vector3(0, 0, 0)]:
		route.append({"to": q})
	var c = load("res://app/crowd.gd").new()
	root.add_child(c)
	walker.position = Vector3(0, 0, -5)   # near the loop's end (s = 395 of 400)
	c.setup(route, walker, ppl, 12)
	c.set_process(false)
	c._process(1.0 / 60.0)
	var fewest := 99
	for step in 900:
		# the walker goes on round the corner and past the loop's start
		walker.position = walker.position + Vector3(0, 0, 1.4 / 60.0) if walker.position.z < 0.0 else walker.position + Vector3(1.4 / 60.0, 0, 0)
		c._process(1.0 / 60.0)
		var near := 0
		for q in ppl.people:
			if (q.at as Vector3).distance_to(walker.position) < 26.0:
				near += 1
		fewest = mini(fewest, near)
	if fewest < 12:
		p.append("the crowd stays round the walker as the walk goes round its loop (%d of 12 at one moment)" % fewest)
	root.free()
	return p


## The built assets: budgets (docs/PLANT3D.md §18.4), the one shader, the plant's vertex format.
func _assets(info: Dictionary) -> Array:
	var p: Array = []
	var tri: Dictionary = info.triangles
	if tri.lod0 > 4000 or tri.lod1 > 1500 or tri.posed > 500:
		p.append("the people's meshes within 4,000 / 1,500 / 500 triangles (%s)" % str(tri))
	if tri.lod1 >= tri.lod0 or tri.posed >= tri.lod1:
		p.append("each level of detail lighter than the one before (%s)" % str(tri))
	if int(info.bones) > 56:
		p.append("at most 56 bones (%d)" % info.bones)
	if info.looks.size() != 8:
		p.append("eight looks (%d)" % info.looks.size())
	if info.poses.size() != 6 or info.looks.size() * info.poses.size() > 50:
		p.append("six poses, the posed band within 50 draw calls (%d looks × %d poses)" % [info.looks.size(), info.poses.size()])
	for r in ROLES:
		if not info.roles.has(r) or not info.looks.has(info.roles[r]):
			p.append("role %s has a look" % r)
	for c in ["idle", "walk", "run", "stairs", "climb", "inspect", "talk", "radio", "type", "sit", "write",
			"kneel_work", "wrench", "handwheel", "calibrate", "carry", "sleep", "lift"]:
		if not c in info.clips:
			p.append("the clip %s is built" % c)
	for k in ["walk", "run", "stairs", "climb"]:
		var v: float = info.speeds.get(k, 0.0)
		if v <= 0.2 or v > 6.0:
			p.append("the %s clip has a natural speed (%.2f m/s)" % [k, v])
	if not info.speeds.walk < info.speeds.run:
		p.append("the run is faster than the walk at its natural speed (%s)" % str(info.speeds))
	for id in info.looks:
		var l: Dictionary = info.looks[id]
		for lod in ["lod0", "lod1"]:
			p += _surface(load(l[lod]), true, "%s %s" % [id, lod])
		for pose in l.posed:
			p += _surface(load(l.posed[pose]), false, "%s posed %s" % [id, pose])
	var av: Node = (load(info.avatar) as PackedScene).instantiate()
	var sk := av.get_node_or_null("Skeleton3D") as Skeleton3D
	var anim := av.get_node_or_null("Anim") as AnimationPlayer
	if sk == null or anim == null or av.get_node_or_null("Skeleton3D/Body") == null:
		p.append("the avatar has its skeleton, body and AnimationPlayer")
	else:
		# every track of every clip drives a bone of the skeleton (a track to nowhere is a clip that doesn't move)
		for c in anim.get_animation_list():
			var a := anim.get_animation(c)
			for t in a.get_track_count():
				var path := str(a.track_get_path(t))
				if not path.begins_with("Skeleton3D:") or sk.find_bone(path.get_slice(":", 1)) < 0:
					p.append("clip %s's track %s drives a bone" % [c, path])
					break
	av.free()
	return p


func _surface(m: Mesh, skinned: bool, what: String) -> Array:
	var p: Array = []
	if not m is ArrayMesh or m.get_surface_count() != 1:
		return ["%s: one surface of an ArrayMesh" % what]
	var mat := m.surface_get_material(0) as ShaderMaterial
	if mat == null or mat.shader.resource_path != SHADER or not mat.get_shader_parameter("use_vertex_colour"):
		p.append("%s: the weathered shader with the colours in the vertices" % what)
	var f: int = m.surface_get_format(0) & ATTRS
	var want := FORMAT | (SKIN if skinned else 0)
	if f != want:
		p.append("%s: the plant's vertex format%s (%x, not %x)" % [what, " with bones" if skinned else "", f, want])
	return p


## The bands, the clips and their rates, with a share of two skinned avatars.
func _bands(tree: SceneTree, info: Dictionary) -> Array:
	var p: Array = []
	var root := Node3D.new()
	tree.root.add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)   # looking along -Z
	cam.current = true
	var ppl = People.new()
	root.add_child(ppl)
	var err: String = ppl.setup(SHARE)
	if err != "":
		root.free()
		return ["people: " + err]
	ppl.camera = cam
	ppl.set_process(false)   # stepped by hand here
	var look: String = info.looks.keys()[0]
	ppl.people = [
		{"at": Vector3(0, 0, -5), "yaw": 0.0, "speed": 1.4, "anim": "", "look": look, "on": ""},           # 0 walking, 5 m
		{"at": Vector3(1, 0, -8), "yaw": 0.0, "speed": 0.0, "anim": "handwheel", "look": look, "on": ""},  # 1 at a valve, 8 m
		{"at": Vector3(0, 0, -20), "yaw": 0.0, "speed": 3.5, "anim": "", "look": look, "on": ""},          # 2 running, 20 m
		{"at": Vector3(0, 0, -50), "yaw": 0.0, "speed": 0.0, "anim": "sit", "look": look, "on": ""},       # 3 sitting, 50 m
		{"at": Vector3(0, 0, -120), "yaw": 0.0, "speed": 1.4, "anim": "", "look": look, "on": ""},         # 4 beyond 80 m
		{"at": Vector3(2, 0, -60), "yaw": 0.0, "speed": 0.0, "anim": "type", "look": look, "on": ""},      # 5 seated, posed
	]
	ppl._assign()
	ppl._skinned(1.0 / 60.0)
	ppl._posed()
	var who := {}
	for a in ppl.avatars:
		if a.person >= 0:
			who[a.person] = a
	if who.keys().size() != 2 or not who.has(0) or not who.has(1):
		p.append("the two nearest get the skinned avatars (%s)" % str(who.keys()))
	else:
		if who[0].clip != "walk" or who[1].clip != "handwheel":
			p.append("a walker walks and a person at a valve turns its handwheel (%s, %s)" % [who[0].clip, who[1].clip])
		if who[0].lod != 0 or (who[0].body as MeshInstance3D).mesh.resource_path != info.looks[look].lod0:
			p.append("LOD0 within 10 m")
		var want: float = 1.4 / float(info.speeds.walk)
		if absf(who[0].speed_scale - want) > 1e-3:
			p.append("the walk is played at the walker's speed over the clip's (%.3f, not %.3f)" % [who[0].speed_scale, want])
		if absf(who[1].speed_scale - 1.0) > 1e-6:
			p.append("a work clip is played at its own speed (%.3f)" % who[1].speed_scale)
	# the posed band: the runner (no slot left), the seated two; nobody beyond 80 m
	if ppl.stats.posed != 3:
		p.append("three people in the posed band (%d)" % ppl.stats.posed)
	var drawn := {}
	for l in ppl.posed:
		for pose in ppl.posed[l]:
			var mi: MultiMeshInstance3D = ppl.posed[l][pose]
			if mi.visible and mi.multimesh.visible_instance_count > 0:
				drawn[pose] = mi.multimesh.visible_instance_count
	if drawn.get("sit", 0) != 2 or drawn.get("walk_a", 0) + drawn.get("walk_b", 0) != 1:
		p.append("the seated in the sitting pose, the runner in a walking one (%s)" % str(drawn))
	# LOD switching: the walker to 15 m (LOD1), then to 30 m (out of the skinned band: posed), then to 100 m (nothing)
	ppl.people[0].at = Vector3(0, 0, -15)
	ppl._assign()
	ppl._skinned(1.0 / 60.0)
	if not who.has(0) or who[0].person != 0 or who[0].lod != 1 or (who[0].body as MeshInstance3D).mesh.resource_path != info.looks[look].lod1:
		p.append("LOD1 beyond 10 m, the same avatar kept")
	ppl.people[0].at = Vector3(0, 0, -30)
	ppl._assign()
	ppl._skinned(1.0 / 60.0)
	ppl._posed()
	var skinned_ids := []
	for a in ppl.avatars:
		if a.person >= 0:
			skinned_ids.append(a.person)
	skinned_ids.sort()
	if skinned_ids != [1, 2]:
		p.append("beyond 25 m the walker leaves the skinned band, the runner at 20 m takes its avatar (%s)" % str(skinned_ids))
	if ppl.stats.posed != 3:
		p.append("the walker at 30 m is in the posed band (%d posed)" % ppl.stats.posed)
	for a in ppl.avatars:
		if a.person == 2 and a.clip != "run":
			p.append("the runner runs (%s)" % a.clip)
	ppl.people[0].at = Vector3(0, 0, -100)
	ppl._assign()
	ppl._posed()
	if ppl.stats.posed != 2:
		p.append("beyond 80 m nobody is drawn (%d posed)" % ppl.stats.posed)
	# the clips' rate: 30 Hz within 10 m, 15 Hz beyond, not advanced out of view
	ppl.people[0].at = Vector3(0, 0, -5)
	ppl.people[1].at = Vector3(1, 0, -18)
	ppl._assign()
	var adv := {}
	for a in ppl.avatars:
		if a.person >= 0:
			a.acc = 0.0
			adv[a.person] = 0
	var last := {}
	for a in ppl.avatars:
		if a.person >= 0:
			last[a.person] = a.anim.current_animation_position
	for i in 60:
		ppl._skinned(1.0 / 60.0)
		for a in ppl.avatars:
			if a.person >= 0 and a.anim.current_animation_position != last[a.person]:
				adv[a.person] += 1   # the clip itself moved on (not only the rate's timer)
				last[a.person] = a.anim.current_animation_position
	if adv.get(0, 0) < 28 or adv.get(0, 0) > 31 or adv.get(1, 0) < 14 or adv.get(1, 0) > 16:
		p.append("clips advanced 30 times a second within 10 m and 15 beyond (%s)" % str(adv))
	ppl.people[1].at = Vector3(1, 0, 18)   # behind the camera
	var t0: float = 0.0
	for a in ppl.avatars:
		if a.person == 1:
			t0 = a.anim.current_animation_position
	for i in 30:
		ppl._skinned(1.0 / 60.0)
	for a in ppl.avatars:
		if a.person == 1 and a.anim.current_animation_position != t0:
			p.append("a clip out of view is not advanced")
	# someone the trainee works with gets a slot first, though further away
	ppl.people[1].at = Vector3(1, 0, -8)
	ppl.people[3].at = Vector3(0, 0, -21)
	ppl.people[3]["near"] = true
	ppl._assign()
	var ids := []
	for a in ppl.avatars:
		if a.person >= 0:
			ids.append(a.person)
	if not 3 in ids:
		p.append("a person the trainee works with gets a skinned avatar first (%s)" % str(ids))
	ppl.people[3].erase("near")
	ppl.people[3].at = Vector3(0, 0, -50)
	# a person of a look this build has not made is not drawn (and nothing fails)
	ppl.people.append({"at": Vector3(0, 0, -3), "yaw": 0.0, "speed": 0.0, "anim": "", "look": "no_such_look", "on": ""})
	ppl._assign()
	ppl._skinned(1.0 / 60.0)
	ppl._posed()
	for a in ppl.avatars:
		if a.person == ppl.people.size() - 1:
			p.append("a person of an unknown look gets no avatar")
	ppl.people.pop_back()
	# the staff's activities to clips: stairs and ladders, standing still
	var cases := [[{"speed": 1.0, "on": "stairs"}, "stairs"], [{"speed": 0.5, "on": "ladder"}, "climb"],
		[{"speed": 0.0, "on": "ladder"}, "climb"], [{"speed": 0.0, "anim": "radio"}, "radio"],
		[{"speed": 0.0, "anim": "eat"}, "sit"], [{"speed": 0.0, "anim": "no_such"}, "idle"], [{"speed": 1.4, "anim": "radio"}, "walk"],
		[{"speed": 4.0}, "run"]]
	for c in cases:
		var got: String = ppl._clip_of(c[0])
		if got != c[1]:
			p.append("%s plays %s (%s)" % [str(c[0]), c[1], got])
	root.free()
	return p


## The tiers' shares (docs/PLANT3D.md §18.4, set by milestone A1's measurement).
func _shares(info: Dictionary) -> Array:
	var p: Array = []
	var phone: Dictionary = Quality.people_share("lean+vis")
	var full: Dictionary = Quality.people_share("full")
	if phone.skinned < 4:
		p.append("the phone draws at least 4 skinned people (MILESTONES.md: fewer is the user's question)")
	if phone.skinned > full.skinned or phone.skinned_range > 25.0 or phone.posed_range > 80.0:
		p.append("the phone's share within its limits (%s)" % str(phone))
	if full.skinned > 24 or full.skinned_range > 40.0 or full.posed_range > 150.0:
		p.append("the laptop's share within its limits (%s)" % str(full))
	for s in [phone, full]:
		if s.lod0_range > 10.0 or s.anim_near > 10.0:
			p.append("LOD0 and the 30 Hz clips within 10 m (%s)" % str(s))
	var forced: Dictionary = Quality.people_share("lean+vis", {"people_skinned": "12"})
	if forced.skinned != 12:
		p.append("a measurement sets its own skinned count")
	if info.looks.size() * info.poses.size() > 50:
		p.append("the posed band within 50 draw calls")
	return p
