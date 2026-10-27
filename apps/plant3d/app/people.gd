## People on screen (docs/PLANT3D.md §18; decisions 0063, 0064): whoever drives them (the staff engine, or the crowd
## of a measurement, app/crowd.gd) sets `people`, one dictionary per person:
##   at: Vector3 (Godot's frame, the feet; on a flight, on the slope a walker climbs), yaw: float (radians; facing -Z
##   at 0, as the walker), speed: float (m/s along the ground: what clip), dir: Vector3 (the way they walk, level; on
##   a flight it says up or down), anim: String (docs/PLANT3D.md §18.3's `anim`, or "" to follow the speed), look:
##   String (built/people/people.json's looks), scale: float (the person's height over 1.75 m), on: "" | "stairs" |
##   "ladder", near: bool (someone the trainee works with: a skinned slot first), hat: bool (false on roads and outside
##   the process areas: the hat carried in the hand and a phone in the other, PLANT3D.md §18.2 as built; default true)
## and this node draws them in three bands by distance from the camera:
##   skinned   the nearest, at most the tier's `skinned` within `skinned_range`: a pool of skinned avatars made at
##             the start (never one per person), LOD0 within `lod0_range`, LOD1 beyond, their clips advanced by this
##             node (manual process) at 30 Hz within `anim_near` m, 15 Hz beyond, not at all out of view
##   posed     everyone else within `posed_range`: unskinned meshes in six poses, one MultiMesh per look and pose
##   beyond    not drawn
## Every mesh is the plant's one shader with its colours in the vertices (decision 0060): no pipeline of its own.
## Feet (docs/PLANT3D.md §18.1 as built, phase 4): a walk or a run is played at the moment of its cycle that the ground
## the person has covered in plan says (people.json's `gait` curve: builder/people/build_people.gd gait_curve()), so
## that the foot on the floor stays where it is, however the person is moved (their way, keeping apart, catching up,
## fast-forward); on a flight a person is drawn on the line
## through the treads' middles and the stairs' clip (up or down) is locked to where they are along it, a step a tread;
## on a ladder the climbing clip to their height, two rungs a cycle (app/stair_treads.gd; ui/people_view.gd turns them
## to face its rungs).
extends Node3D

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)
const PeopleDoors = preload("res://app/people_doors.gd")
const StairTreads = preload("res://app/stair_treads.gd")

const INFO := "res://built/people/people.json"
## docs/PLANT3D.md §18.3's `anim` values to the clips (builder/people/rig.gd); a value not here plays `idle`.
const ANIM_CLIP := {"inspect": "inspect", "talk": "talk", "radio": "radio", "type": "type", "sit": "sit",
	"write": "write", "kneel_work": "kneel_work", "wrench": "wrench", "handwheel": "handwheel",
	"calibrate": "calibrate", "carry": "carry", "climb": "climb", "eat": "sit", "sleep": "sleep", "lift": "lift",
	"use": "use", "idle": "idle"}
## The clips moved on by the ground covered (their curve in people.json's `gait`: the walk's for its road variant),
## and those locked to where the person is on a flight or a ladder.
const GAIT := {"walk": "walk", "walk_road": "walk", "run": "run"}
const LOCKED := ["stairs", "stairs_down", "climb"]
const SOLE_HALF := 0.13         # m: half a sole's length (standing, the soles' middle is at the feet point)
## Which posed band pose stands for a clip (docs/PLANT3D.md §18.4: stand, walk A and B, sit, work, carry).
const CLIP_POSE := {"sit": "sit", "type": "sit", "sleep": "sit", "handwheel": "work", "wrench": "work",
	"calibrate": "work", "kneel_work": "work", "inspect": "work", "use": "work", "write": "work", "carry": "carry",
	"lift": "carry"}
const RUN_FROM := 2.2           # m/s: faster than this is a run
const STILL := 0.15             # m/s: slower than this is standing
const BLEND := 0.25             # s: the crossfade between clips
const ASSIGN_HZ := 4.0          # who gets the skinned slots, re-decided this often (the posed band follows at once)
const KEEP := 2.0               # m: a person gets an avatar, or LOD0, only this far inside its edge (keeps it to the edge)

var info: Dictionary = {}
var cfg: Dictionary = {}        # the tier's share (app/quality.gd PRESETS[tier].people)
var people: Array = []
var treads                      # app/stair_treads.gd: the plant's flights and ladders (null: people on a flight drawn on
                                # its slope, their clips free)
var time_scale := 1.0           # the clips' speed with the plant's (fast-forward, paused: the staff's driver sets it)
var camera: Camera3D
var avatars: Array = []         # the pool: {node, body, anim, person, look, lod, clip, acc}
var posed := {}                 # look -> pose -> MultiMeshInstance3D
var _assign_t := 1.0
var doors = PeopleDoors.new(0.5 / PeopleDoors.HZ)   # the doors open for them (app/people_doors.gd), between _assign's
var _clock := 0.0
var _scene: PackedScene
var _meshes := {}               # path -> Mesh
var _gait := {}                 # GAIT's clips -> [their curve (metres covered at GAIT_SAMPLES + 1 moments), metres a cycle]
var stats := {"skinned": 0, "posed": 0, "advanced": 0, "lod0": 0, "lod1": 0, "us": 0, "us_max": 0, "frames": 0,
	"us_sum": 0, "draws_posed": 0}


## Whether this build has people (built/people/, builder/people/build_people.gd).
static func available() -> bool:
	return FileAccess.file_exists(INFO)


## Reads the people's assets and makes the pool and the posed band for the tier's share. Returns "" or what went wrong.
func setup(share: Dictionary) -> String:
	var f := FileAccess.open(INFO, FileAccess.READ)
	if f == null:
		return "no " + INFO
	var j = JSON.parse_string(f.get_as_text())
	if not j is Dictionary or j.get("format", "") != "walkdown-plant-people":
		return INFO + " is not one this app reads"
	info = j
	_scene = load(info.avatar)
	for g in info.get("gait", {}):
		var c := PackedFloat32Array(info.gait[g].curve)
		if c.size() >= 2 and c[c.size() - 1] > 0.0:
			_gait[g] = [c, c[c.size() - 1]]
	if not share.is_empty():
		apply_share(share)
	return ""


## The tier's share (a tier change, or a measurement's own count): the pool and the posed band made again.
func apply_share(share: Dictionary) -> void:
	cfg = share
	for a in avatars:
		a.node.queue_free()
	avatars.clear()
	for l in posed:
		for p in posed[l]:
			posed[l][p].queue_free()
	posed.clear()
	for i in int(cfg.skinned):
		var n: Node3D = _scene.instantiate()
		n.name = "avatar_%d" % i
		n.visible = false
		add_child(n)
		var body: MeshInstance3D = n.get_node("Skeleton3D/Body")
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cfg.get("shadows", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var anim: AnimationPlayer = n.get_node("Anim")
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		avatars.append({"node": n, "body": body, "anim": anim, "person": -1, "look": "", "lod": -1, "clip": "", "acc": 0.0,
			"rate": 1.0, "road": "", "last": Vector3.INF, "gait": "", "d": 0.0})
		# its clips played once now, in the start: the first play of an AnimationPlayer builds its caches (a frame of
		# 0.6 ms on the laptop, about ten times that on the Note 9, when the pool first took people)
		anim.play("idle")
		anim.advance(0.0)
	# every look's skinned meshes loaded now, not when someone first comes near (a load is a hitch on a phone)
	for l in info.looks:
		for lod in ["lod0", "lod1", "lod0_road", "lod1_road"]:
			_mesh(info.looks[l][lod])
	for l in info.looks:
		posed[l] = {}
		for p in info.looks[l].posed:
			var mi := MultiMeshInstance3D.new()
			mi.name = "posed_%s_%s" % [l, p]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _mesh(info.looks[l].posed[p])
			mm.instance_count = 0
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(mi)
			posed[l][p] = mi
	_assign_t = 1.0
	if is_inside_tree():
		doors.prepare(get_tree())


func _mesh(path: String) -> Mesh:
	if not _meshes.has(path):
		_meshes[path] = load(path)
	return _meshes[path]


func _process(delta: float) -> void:
	var _c0 := Time.get_ticks_usec()
	_each_frame(delta)
	Cost.add(Cost.AVATARS, _c0)


func _each_frame(delta: float) -> void:
	if is_inside_tree():
		doors.tick(get_tree(), people, delta, time_scale)
	if camera == null or cfg.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_clock += delta
	_assign_t += delta
	if _assign_t >= 1.0 / ASSIGN_HZ:
		_assign_t = 0.0
		_assign()
	_skinned(delta)
	# every frame, right after the slots: nobody missing or drawn twice when they move between the bands, and the
	# posed walkers placed smoothly (their pose changes 4 times a second)
	_posed()
	var us := Time.get_ticks_usec() - t0
	stats.us = us
	stats.us_max = maxi(stats.us_max, us)
	stats.us_sum += us
	stats.frames += 1


## The nearest people within the skinned range get the pool's avatars (those the trainee works with first); a person
## keeps their avatar while still among the nearest, so that a clip is not restarted for nothing.
func _assign() -> void:
	var cam := camera.global_position
	var r: float = float(cfg.skinned_range)
	var held := {}
	for a in avatars:
		if a.person >= 0:
			held[a.person] = true
	var cand := []
	for i in people.size():
		var p: Dictionary = people[i]
		if not info.looks.has(p.get("look", "")):
			continue   # (a look this build has not made: not drawn)
		var d2: float = (p.at as Vector3).distance_squared_to(cam)
		var lim := r - (0.0 if held.has(i) else KEEP)   # a new avatar only KEEP inside the edge: no flicker
		if d2 <= lim * lim:
			# whoever holds an avatar keeps it against someone up to KEEP nearer: no swapping between people at
			# nearly the same distance (a swap restarts a clip and turns the other into a statue)
			var dk: float = sqrt(d2) - (KEEP if held.has(i) else 0.0)
			cand.append([0 if p.get("near", false) else 1, dk, i])
	cand.sort()
	var want := {}
	for k in mini(cand.size(), avatars.size()):
		want[cand[k][2]] = true
	var free := []
	for a in avatars:
		if a.person >= 0 and want.has(a.person) and a.person < people.size():
			want.erase(a.person)
		else:
			a.person = -1
			a.node.visible = false
			free.append(a)
	for i in want:
		var a: Dictionary = free.pop_back()
		a.person = i
		a.clip = ""
		a.acc = 1.0
		a.last = Vector3.INF
		a.gait = ""
		a.node.visible = true


func _clip_of(p: Dictionary, down := false, flat := false) -> String:
	var on: String = "" if flat else p.get("on", "")
	var s: float = p.get("speed", 0.0)
	if on == "ladder":
		return "climb"
	if s > STILL:
		if on == "stairs":
			return "stairs_down" if down else "stairs"
		if s > RUN_FROM:
			return "run"
		return "walk" if p.get("hat", true) else "walk_road"
	var c: String = ANIM_CLIP.get(p.get("anim", ""), "idle")
	return "idle_road" if c == "idle" and not p.get("hat", true) else c


func _skinned(delta: float) -> void:
	var cam := camera.global_position
	var n_sk := 0
	var adv := 0
	var l0 := 0
	var l1 := 0
	var rung: float = float(info.get("stairs", {}).get("rung", 0.3))
	for a in avatars:
		if a.person < 0 or a.person >= people.size():
			continue
		var p: Dictionary = people[a.person]
		n_sk += 1
		var at: Vector3 = p.at
		var sc: float = p.get("scale", 1.0)
		var yaw: float = float(p.get("yaw", 0.0))
		# on a flight: on its treads' line, and which way (up or down), and where along it; on a ladder: how high
		var phase := -1.0
		var down := false
		var flat := false               # on a flight's slope but off its treads' line: walked as on the landing
		var on: String = p.get("on", "")
		var size := sc
		if treads != null and on == "stairs":
			var fk: int = treads.on_flight(at)
			if fk >= 0:
				var w: Vector3 = p.get("dir", Vector3.ZERO)
				var way := Vector2(w.x, w.z)
				if way.length_squared() < 0.25:
					way = Vector2(-sin(yaw), -cos(yaw))
				down = way.dot(treads.dir) < 0.0
				if not treads.on_treads(fk, treads.t):
					at.y = treads.tread(fk, treads.t)     # (the slope's foot over the landing: on the landing)
					flat = true
				elif float(p.get("speed", 0.0)) <= STILL:
					# standing still on a flight: on the highest tread under their feet (both soles level, no IK: across
					# a nosing they stand on the upper tread, over the lower one's edge, never into the step)
					at.y = treads.tread(fk, treads.t + SOLE_HALF)
				else:
					at.y = treads.mid(fk, treads.t)
					phase = fposmod((-treads.t if down else treads.t) / (2.0 * treads.going), 1.0)
					size = 1.0      # (the clip's steps a tread long: not scaled with the person)
		elif treads != null and on == "ladder":
			var lk: int = treads.on_ladder(at)
			if lk >= 0:
				phase = fposmod((at.y - float(treads.ladders[lk][1])) / (2.0 * rung), 1.0)
				size = 1.0      # (the clip's hands and feet on rungs 0.3 m apart: not scaled with the person)
		a.node.transform = Transform3D(Basis(Vector3.UP, yaw + PI).scaled(Vector3.ONE * size), at)
		var d := at.distance_to(cam)
		# LOD0 within its range; taken again only KEEP inside it (no flicker at the edge)
		var edge := float(cfg.lod0_range) - (KEEP if a.lod == 1 else 0.0)
		var lod := 0 if d <= edge else 1
		var road := "" if p.get("hat", true) else "_road"
		if a.look != p.look or a.lod != lod or a.get("road", "") != road:
			a.look = p.look
			a.lod = lod
			a.road = road
			a.body.mesh = _mesh(info.looks[p.look]["lod%d%s" % [lod, road]])
		if lod == 0:
			l0 += 1
		else:
			l1 += 1
		var clip := _clip_of(p, down, flat)
		if clip != a.clip:
			var first: bool = a.clip == ""
			a.clip = clip
			a.gait = ""
			a.anim.play(clip, 0.0 if first else BLEND)
			if clip in LOCKED and phase >= 0.0:
				# at its moment for where they are now: the crossfade then runs at the clip's own pace, not in a jump
				a.anim.seek(phase * a.anim.current_animation_length, true)
			elif first:
				# each person at their own point of the cycle
				a.anim.seek(fmod(float(a.person) * 0.37, 1.0) * a.anim.current_animation_length, true)
		# advanced at the rate for its distance, not at all out of view (docs/PLANT3D.md §18.3)
		a.acc += delta
		var hz := 30.0 if d <= float(cfg.anim_near) else 15.0
		if a.acc + 1e-4 >= 1.0 / hz:
			if _in_view(at) or d < 2.0:
				var dt: float = a.acc * time_scale
				var len: float = a.anim.current_animation_length
				var cur: float = a.anim.current_animation_position
				if clip in LOCKED and phase >= 0.0:
					# to where they are on the flight or the ladder, the shorter way round (down a ladder: back)
					_move(a, fposmod(phase * len - cur + len * 0.5, len) - len * 0.5)
					a.rate = 0.0
				elif _gait.has(GAIT.get(clip, "")):
					# at the moment of its cycle the ground covered in plan says: the standing foot stays put
					var c: Array = _gait[GAIT[clip]]
					if a.gait != clip:
						a.gait = clip
						a.d = gait_d(c[0], cur / len)
					var gone := 0.0 if a.last == Vector3.INF else Vector2(at.x - a.last.x, at.z - a.last.z).length()
					a.d = fposmod(a.d + gone / sc, c[1])
					var step := fposmod(gait_t(c[0], a.d) * len - cur, len) if gone > 0.0 else 0.0
					if step > len - 1e-6:
						step = 0.0      # (the same moment, a rounding apart: not a whole cycle on)
					_move(a, step)
					a.rate = step / dt if dt > 0.0 else 0.0
				else:
					_move(a, dt)
					a.rate = 1.0
				adv += 1
			a.acc = 0.0
			a.last = at
	stats.skinned = n_sk
	stats.advanced = adv
	stats.lod0 = l0
	stats.lod1 = l1


## Moves avatar `a`'s clip on by `t` seconds of it (back when negative), the blend from the last clip with it: one
## evaluation of the clip.
static func _move(a: Dictionary, t: float) -> void:
	var ap: AnimationPlayer = a.anim
	var sg := 1.0 if t >= 0.0 else -1.0
	if ap.speed_scale != sg:
		ap.speed_scale = sg
	ap.advance(absf(t))


## The metres covered at the fraction `f` of a gait's cycle (its curve: metres at evenly spaced moments).
static func gait_d(curve: PackedFloat32Array, f: float) -> float:
	var n := curve.size() - 1
	var x := clampf(fposmod(f, 1.0), 0.0, 1.0) * n
	var i := mini(int(x), n - 1)
	return lerpf(curve[i], curve[i + 1], x - i)


## The fraction of a gait's cycle at which `d` metres have been covered (the curve only grows).
static func gait_t(curve: PackedFloat32Array, d: float) -> float:
	var n := curve.size() - 1
	var i := clampi(curve.bsearch(d, true) - 1, 0, n - 1)
	var span := curve[i + 1] - curve[i]
	return (i + (clampf((d - curve[i]) / span, 0.0, 1.0) if span > 0.0 else 0.0)) / n


## Whether any of a person's height is in the camera's view (feet, chest, head).
func _in_view(at: Vector3) -> bool:
	for h in [0.1, 0.9, 1.7]:
		if camera.is_position_in_frustum(at + Vector3.UP * h):
			return true
	return false


## The posed band: everyone within its range who has no avatar, by look and pose.
func _posed() -> void:
	var cam := camera.global_position
	var r2: float = float(cfg.posed_range) * float(cfg.posed_range)
	var taken := {}
	for a in avatars:
		if a.person >= 0:
			taken[a.person] = true
	var groups := {}
	var n := 0
	for i in people.size():
		if taken.has(i):
			continue
		var p: Dictionary = people[i]
		var at: Vector3 = p.at
		if at.distance_squared_to(cam) > r2 or not posed.has(p.get("look", "")):
			continue
		var clip := _clip_of(p)
		if treads != null and p.get("on", "") == "stairs":
			var fk: int = treads.on_flight(at)
			if fk >= 0:     # (as the skinned: on its treads' line, or the treads under them)
				if not treads.on_treads(fk, treads.t):
					at.y = treads.tread(fk, treads.t)
				elif float(p.get("speed", 0.0)) <= STILL:
					at.y = treads.tread(fk, treads.t + SOLE_HALF)
				else:
					at.y = treads.mid(fk, treads.t)
		var pose: String
		if clip in ["walk", "walk_road", "run", "stairs", "stairs_down", "climb"]:
			# walk A and B in turn, 4 times a second, each person at their own moment
			pose = "walk_a" if int(floor((_clock + float(i) * 0.13) * 4.0)) % 2 == 0 else "walk_b"
		else:
			pose = CLIP_POSE.get(clip, "stand")
		var key: String = p.look + "/" + pose
		if not groups.has(key):
			groups[key] = []
		var sc: float = p.get("scale", 1.0)
		groups[key].append(Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0)) + PI).scaled(Vector3.ONE * sc), at))
		n += 1
	var draws := 0
	for l in posed:
		for pose in posed[l]:
			var mi: MultiMeshInstance3D = posed[l][pose]
			var xs: Array = groups.get(l + "/" + pose, [])
			var mm := mi.multimesh
			if mm.instance_count < xs.size():
				mm.instance_count = xs.size() + 4
			mm.visible_instance_count = xs.size()
			for k in xs.size():
				mm.set_instance_transform(k, xs[k])
			mi.visible = xs.size() > 0
			if xs.size() > 0:
				draws += 1
	stats.posed = n
	stats.draws_posed = draws


## What the people cost (a walk's PEOPLE line).
func summary() -> String:
	return "skinned=%d posed=%d posed_draws=%d lod0=%d lod1=%d cpu_mean=%.2fms cpu_max=%.2fms" % [stats.skinned,
		stats.posed, stats.draws_posed, stats.lod0, stats.lod1, stats.us_sum / 1000.0 / maxi(1, stats.frames),
		stats.us_max / 1000.0]
