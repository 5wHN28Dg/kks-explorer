## The people's skeleton and animations (decision 0063, docs/PLANT3D.md §18.2–§18.3), made at build time.
##
## The skeleton is KayKit's `Rig_Medium` (KayKit Character Animations 1.1, CC0, people/kaykit/): its 23 bones, their
## names and their rest orientations unchanged, with an adult's proportions instead of KayKit's (a 1.75 m person: hips
## at 0.97 m, where KayKit's mannequin has them at 0.41 m under a large head). Because only the bones' lengths change,
## KayKit's clips play on it as they are: their rotation tracks unchanged, the hips' position track scaled by the
## hips' height, every other position or scale track dropped (they would put KayKit's lengths back).
##
## The work poses KayKit has no clip for (a handwheel, the radio, writing, typing, a ladder, stairs) are ours: each
## key a pose given as where the hands and feet are (two-bone IK) and where the spine and head point, on this skeleton.
extends RefCounted

const KAYKIT := "res://people/kaykit/"
const SKELETON_FILE := "Rig_Medium_General.glb"

## Our bones' rest positions in the model (metres; Y up, the person faces +Z, their left is +X), KayKit's names.
const JOINTS := {
	"root": Vector3(0, 0, 0),
	"hips": Vector3(0, 0.97, 0),
	"upperleg.l": Vector3(0.095, 0.93, 0), "lowerleg.l": Vector3(0.095, 0.50, 0.012), "foot.l": Vector3(0.095, 0.085, -0.02),
	"toes.l": Vector3(0.095, 0.02, 0.115),
	"upperleg.r": Vector3(-0.095, 0.93, 0), "lowerleg.r": Vector3(-0.095, 0.50, 0.012), "foot.r": Vector3(-0.095, 0.085, -0.02),
	"toes.r": Vector3(-0.095, 0.02, 0.115),
	"spine": Vector3(0, 1.07, 0), "chest": Vector3(0, 1.28, 0), "head": Vector3(0, 1.505, 0),
	"upperarm.l": Vector3(0.185, 1.43, 0), "lowerarm.l": Vector3(0.475, 1.43, -0.01), "wrist.l": Vector3(0.725, 1.43, 0),
	"hand.l": Vector3(0.775, 1.43, 0), "handslot.l": Vector3(0.84, 1.40, 0),
	"upperarm.r": Vector3(-0.185, 1.43, 0), "lowerarm.r": Vector3(-0.475, 1.43, -0.01), "wrist.r": Vector3(-0.725, 1.43, 0),
	"hand.r": Vector3(-0.775, 1.43, 0), "handslot.r": Vector3(-0.84, 1.40, 0),
}
const HIPS_KAYKIT := 0.405663   # KayKit's hips height at rest (the hips' position track is scaled by ours over it)

## How far KayKit's clips swing the legs (1: as KayKit; its cartoon walk lifts the knee to the hip): the rotation of
## every leg bone taken this part of the way from standing straight to the clip's.
const LEG_SWING := {"walk": 0.55, "run": 0.7}
## KayKit's mannequin holds its arms away from a wide body: every clip's upper arms are brought this far (radians)
## towards ours.
const ARM_IN := 0.65

## Our names for KayKit's clips (file, clip, loops). docs/PLANT3D.md §18.3's `anim` values map to these
## (app/people.gd ANIM_CLIP).
const CLIPS := {
	"idle": ["General", "Idle_A", true],
	"idle_b": ["General", "Idle_B", true],
	"walk": ["MovementBasic", "Walking_A", true],
	"run": ["MovementBasic", "Running_A", true],
	"inspect": ["General", "Interact", true],
	"use": ["General", "Use_Item", true],
	"lift": ["General", "PickUp", true],
	"kneel_work": ["Tools", "Working_A", true],
	"wrench": ["Tools", "Working_B", true],
	"calibrate": ["Tools", "Lockpicking", true],
	"carry": ["Tools", "Holding_A", true],
	"sleep": ["Simulation", "Lie_Idle", true],
	"talk": ["Simulation", "Waving", true],
}

var skeleton: Skeleton3D          # ours: KayKit's bones at our proportions
var kaykit_rest: Array = []       # per bone: KayKit's rest Transform3D (local)
var names: PackedStringArray
var _sources := {}                # file -> AnimationPlayer of that glTF


## Reads KayKit's skeleton and makes ours. Returns "" or what went wrong.
func load_kaykit() -> String:
	var ap := _source("General")
	if ap == null:
		return "cannot read %s%s" % [KAYKIT, SKELETON_FILE]
	var src: Skeleton3D = ap.get_parent().find_child("Skeleton3D", true, false)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	var global_basis: Array = []
	for i in src.get_bone_count():
		var n := src.get_bone_name(i)
		names.append(n)
		skeleton.add_bone(n)
		skeleton.set_bone_parent(i, src.get_bone_parent(i))
		kaykit_rest.append(src.get_bone_rest(i))
		global_basis.append(src.get_bone_global_rest(i).basis)
		if not JOINTS.has(n):
			return "KayKit's skeleton has a bone this rig doesn't place: " + n
	for i in src.get_bone_count():
		var p := src.get_bone_parent(i)
		var at: Vector3 = JOINTS[names[i]]
		var local := Transform3D(kaykit_rest[i].basis, at)
		if p >= 0:
			# KayKit's orientations kept (its clips' rotations mean the same here); only the offset is ours
			var pg := Transform3D(global_basis[p], JOINTS[names[p]])
			local.origin = pg.affine_inverse() * at
		skeleton.set_bone_rest(i, local)
		skeleton.set_bone_pose(i, local)
	return ""


func _source(file: String) -> AnimationPlayer:
	if _sources.has(file):
		return _sources[file]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(KAYKIT + "Rig_Medium_%s.glb" % file, st) != OK:
		return null
	var root: Node = doc.generate_scene(st)
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	_sources[file] = ap
	return ap


func free_sources() -> void:
	for f in _sources:
		_sources[f].get_parent().free()
	_sources.clear()


## KayKit's clip on our skeleton, its tracks addressed to `track_root` (the path from the AnimationPlayer's root to
## the skeleton). Rotation tracks as they are; the hips' position scaled to our hips; other position and scale tracks
## dropped.
func clip(file: String, name: String, loop: bool, swing := 1.0, track_root := "Skeleton3D") -> Animation:
	var ap := _source(file)
	if ap == null or not ap.has_animation(name):
		return null
	var src := ap.get_animation(name)
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var k: float = JOINTS["hips"].y / HIPS_KAYKIT
	for t in src.get_track_count():
		var ty := src.track_get_type(t)
		var bone := str(src.track_get_path(t)).get_slice(":", 1)
		if names.find(bone) < 0:
			continue
		if ty == Animation.TYPE_ROTATION_3D:
			var n := out.add_track(ty)
			out.track_set_path(n, NodePath(track_root + ":" + bone))
			out.track_set_interpolation_type(n, Animation.INTERPOLATION_LINEAR)
			var bi := names.find(bone)
			var rest_q := skeleton.get_bone_rest(bi).basis.get_rotation_quaternion()
			var leg := bone.begins_with("upperleg") or bone.begins_with("lowerleg") or bone.begins_with("foot")
			var arm_in := Quaternion()
			if bone.begins_with("upperarm"):
				# about the chest's forward axis, downwards
				var fwd := skeleton.get_bone_global_rest(skeleton.get_bone_parent(bi)).basis.inverse() * Vector3.BACK
				arm_in = Quaternion(fwd.normalized(), -ARM_IN if bone.ends_with(".l") else ARM_IN)
			for j in src.track_get_key_count(t):
				var q: Quaternion = src.track_get_key_value(t, j)
				if leg and swing != 1.0:
					q = rest_q.slerp(q, swing)
				q = arm_in * q
				out.rotation_track_insert_key(n, src.track_get_key_time(t, j), q)
		elif ty == Animation.TYPE_POSITION_3D and bone == "hips":
			var n := out.add_track(ty)
			out.track_set_path(n, NodePath(track_root + ":" + bone))
			for j in src.track_get_key_count(t):
				out.position_track_insert_key(n, src.track_get_key_time(t, j), (src.track_get_key_value(t, j) as Vector3) * k)
	return out


# ---- our own poses ------------------------------------------------------------------------------------------------

## A pose: {bone: global direction its +Y points to (towards its child)}, plus "hips_at" (the hips' position) and
## "turn" (the whole body's turn about Y, radians). Bones not named follow their parent as at rest.
## Returns per bone its local rotation.
func solve(pose: Dictionary) -> Array:
	var rots: Array = []
	var gb: Array = []   # global bases
	var turn := Basis(Vector3.UP, float(pose.get("turn", 0.0)))
	for i in names.size():
		var rest := skeleton.get_bone_rest(i)
		var p := skeleton.get_bone_parent(i)
		var pb: Basis = gb[p] if p >= 0 else Basis()
		var b0: Basis = pb * rest.basis
		if i == names.find("hips"):
			b0 = turn * b0
		if pose.has(names[i]):
			var want: Vector3 = (turn * (pose[names[i]] as Vector3)).normalized()
			var have: Vector3 = (b0 * Vector3.UP).normalized()
			var q := _arc(have, want)
			b0 = Basis(q) * b0
		gb.append(b0.orthonormalized())
		rots.append((pb.inverse() * gb[i]).get_rotation_quaternion())
	return rots


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := a.dot(b)
	if d > 0.99999:
		return Quaternion()
	if d < -0.99999:
		var ax := a.cross(Vector3.RIGHT)
		if ax.length() < 1e-4:
			ax = a.cross(Vector3.FORWARD)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(clampf(d, -1, 1)))


## Two-bone IK: from the joint at `a` (shoulder or hip) with segment lengths l1, l2 to reach `t`, the middle joint
## bent towards `pole`. Returns [direction of the first bone, direction of the second].
static func ik(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := t - a
	var dist := clampf(d.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var dir := d.normalized()
	var cos_a := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)
	var ang := acos(clampf(cos_a, -1, 1))
	var side := (pole - dir * pole.dot(dir))
	if side.length() < 1e-4:
		side = Vector3.FORWARD
	side = side.normalized()
	var mid := a + (dir * cos(ang) + side * sin(ang)) * l1
	return [(mid - a).normalized(), (a + dir * dist - mid).normalized()]


func seg(a: String, b: String) -> float:
	return (JOINTS[b] - JOINTS[a]).length()


## Arms and legs placed by IK on top of a pose: "reach.l"/"reach.r" (where the hands are) and "step.l"/"step.r"
## (where the ankles are), model space before the pose's turn, bent towards "elbow.l"/"elbow.r"/"knee.l"/"knee.r";
## "chest" leans the shoulders with it. The other keys go to solve() as they are.
func limbs(p: Dictionary) -> Dictionary:
	var out := {}
	for k in p:
		if not (k.begins_with("reach.") or k.begins_with("step.") or k.begins_with("elbow.") or k.begins_with("knee.")):
			out[k] = p[k]
	var hips: Vector3 = p.get("hips_at", JOINTS["hips"])
	var lean: Vector3 = p.get("chest", Vector3.UP)
	var chest_at: Vector3 = hips + (JOINTS["chest"] - JOINTS["hips"])
	for s in ["l", "r"]:
		if p.has("reach." + s):
			var sh: Vector3 = chest_at + Basis(_arc(Vector3.UP, lean.normalized())) * (JOINTS["upperarm." + s] - JOINTS["chest"])
			var dirs := ik(sh, p["reach." + s], seg("upperarm." + s, "lowerarm." + s), seg("lowerarm." + s, "wrist." + s),
				p.get("elbow." + s, Vector3(0, -1, -0.3)))
			out["upperarm." + s] = dirs[0]
			out["lowerarm." + s] = dirs[1]
			out["wrist." + s] = dirs[1]
			out["hand." + s] = dirs[1]
		if p.has("step." + s):
			var hip: Vector3 = hips + (JOINTS["upperleg." + s] - JOINTS["hips"])
			var dirs := ik(hip, p["step." + s], seg("upperleg." + s, "lowerleg." + s), seg("lowerleg." + s, "foot." + s),
				p.get("knee." + s, Vector3(0, 0, 1)))
			out["upperleg." + s] = dirs[0]
			out["lowerleg." + s] = dirs[1]
	out.erase("hips_at")
	return out


## An animation of our own: keys of poses (each a dictionary for limbs() and solve()), equally spaced over `length`.
func own(keys: Array, length: float, loop: bool, track_root := "Skeleton3D") -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	var hips_track := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(hips_track, NodePath(track_root + ":hips"))
	var hi := names.find("hips")
	for i in names.size():
		var n := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(n, NodePath(track_root + ":" + names[i]))
		tracks[i] = n
	var count := keys.size()
	for k in count + (1 if loop else 0):
		var p: Dictionary = keys[k % count]
		var t := length * float(k) / float(count if loop else maxi(1, count - 1))
		var rots := solve(limbs(p))
		for i in names.size():
			a.rotation_track_insert_key(tracks[i], t, rots[i])
		var hips_at: Vector3 = p.get("hips_at", JOINTS["hips"])
		var parent_rest := skeleton.get_bone_global_rest(skeleton.get_bone_parent(hi))
		a.position_track_insert_key(hips_track, t, parent_rest.affine_inverse() * hips_at)
	return a


## Our clips: the work poses no CC0 source has (docs/PLANT3D.md §18.3: handwheel, radio, write, type, climb, and the
## stairs' step).
func own_clips() -> Dictionary:
	var out := {}
	var H: Vector3 = JOINTS["hips"]
	# a handwheel 0.45 m in front at chest height, turned hand over hand: the hands on the rim at opposite sides
	var wheel := []
	for k in 8:
		var a := TAU * k / 8.0
		var c := Vector3(0, 1.22, 0.42)
		var r := 0.17
		wheel.append({"reach.l": c + Vector3(cos(a), sin(a), 0) * r, "reach.r": c + Vector3(cos(a + PI), sin(a + PI), 0) * r,
			"elbow.l": Vector3(1, -1, 0), "elbow.r": Vector3(-1, -1, 0), "chest": Vector3(0, 1, 0.12), "head": Vector3(0, 1, 0.2)})
	out["handwheel"] = own(wheel, 3.2, true)
	# the radio: the right hand at the mouth, the head a little down
	var radio := []
	for k in 4:
		var w := 0.01 * sin(TAU * k / 4.0)
		radio.append({"reach.r": Vector3(-0.07, 1.58 + w, 0.13), "elbow.r": Vector3(-1, -0.6, 0.2),
			"reach.l": Vector3(0.2, 0.92, 0.04), "elbow.l": Vector3(1, 0, -0.5), "head": Vector3(-0.05, 1, 0.12)})
	out["radio"] = own(radio, 2.0, true)
	# writing on a clipboard held in the left hand at the waist, the right hand writing across it
	var write := []
	for k in 6:
		var x := 0.06 * sin(TAU * k / 6.0)
		write.append({"reach.l": Vector3(0.10, 1.10, 0.30), "elbow.l": Vector3(1, -1, -0.2),
			"reach.r": Vector3(0.02 + x, 1.14, 0.30 + 0.02 * cos(TAU * k / 6.0)), "elbow.r": Vector3(-1, -1, -0.2),
			"head": Vector3(0, 1, 0.45), "chest": Vector3(0, 1, 0.06)})
	out["write"] = own(write, 2.4, true)
	# typing at a desk, seated (the chair's seat at 0.47 m): the hands on a keyboard at 0.75 m
	var type := []
	for k in 4:
		var d := 0.012 * sin(TAU * k / 4.0)
		var hips := Vector3(0, 0.50, -0.05)
		type.append({"hips_at": hips, "step.l": Vector3(0.12, 0.09, 0.36), "step.r": Vector3(-0.12, 0.09, 0.36),
			"knee.l": Vector3(0, 1, 1), "knee.r": Vector3(0, 1, 1),
			"reach.l": Vector3(0.14, 0.77 + d, 0.42), "reach.r": Vector3(-0.14, 0.77 - d, 0.42),
			"elbow.l": Vector3(0.6, -1, -0.3), "elbow.r": Vector3(-0.6, -1, -0.3), "head": Vector3(0, 1, 0.12)})
	out["type"] = own(type, 1.0, true)
	# sitting on a chair (seat 0.47 m), the hands on the thighs, breathing
	var sit := []
	for k in 4:
		var d := 0.008 * sin(TAU * k / 4.0)
		sit.append({"hips_at": Vector3(0, 0.50, -0.05), "step.l": Vector3(0.13, 0.09, 0.40), "step.r": Vector3(-0.13, 0.09, 0.40),
			"knee.l": Vector3(0.2, 1, 1), "knee.r": Vector3(-0.2, 1, 1), "chest": Vector3(0, 1, -0.05 + d),
			"reach.l": Vector3(0.14, 0.58, 0.30), "reach.r": Vector3(-0.14, 0.58, 0.30),
			"elbow.l": Vector3(1, -0.5, -1), "elbow.r": Vector3(-1, -0.5, -1)})
	out["sit"] = own(sit, 3.0, true)
	# a ladder's cycle (rungs 0.3 m apart, the ladder 0.25 m in front): hands and feet in turn, 0.6 m a cycle
	var ladder := []
	for k in 4:
		var hips := H + Vector3(0, 0, 0.02)
		ladder.append({"hips_at": hips,
			"reach.l": Vector3(0.2, 1.55 + (0.3 if k == 1 or k == 2 else 0.0), 0.28),
			"reach.r": Vector3(-0.2, 1.55 + (0.3 if k == 3 or k == 0 else 0.0), 0.28),
			"elbow.l": Vector3(1, -1, -0.6), "elbow.r": Vector3(-1, -1, -0.6),
			"step.l": Vector3(0.12, 0.10 + (0.3 if k == 1 or k == 2 else 0.0), 0.18),
			"step.r": Vector3(-0.12, 0.10 + (0.3 if k == 3 or k == 0 else 0.0), 0.18),
			"knee.l": Vector3(0, 0, 1), "knee.r": Vector3(0, 0, 1), "chest": Vector3(0, 1, 0.08), "head": Vector3(0, 1, 0.1)})
	out["climb"] = own(ladder, 1.6, true)
	# up a stair (0.18 m rise, 0.28 m going): a step each half cycle, the hips rising with it (the avatar's height
	# follows the stair: the hips move only within the cycle)
	var stair := []
	for k in 4:
		var ph := k / 4.0
		var lead := "l" if k < 2 else "r"
		var trail := "r" if lead == "l" else "l"
		var sx := {"l": 0.1, "r": -0.1}
		var p := {"hips_at": H + Vector3(0, -0.04 + 0.03 * sin(PI * ph * 2.0), 0.02),
			"chest": Vector3(0, 1, 0.1), "head": Vector3(0, 1, 0.15),
			"reach.l": Vector3(0.22, 0.95, 0.04 + (0.08 if lead == "r" else -0.06)), "elbow.l": Vector3(1, 0, -1),
			"reach.r": Vector3(-0.22, 0.95, 0.04 + (0.08 if lead == "l" else -0.06)), "elbow.r": Vector3(-1, 0, -1)}
		var sub := k % 2
		p["step." + lead] = Vector3(sx[lead], 0.09 + (0.18 if sub == 1 else 0.10), 0.20 if sub == 1 else 0.12)
		p["step." + trail] = Vector3(sx[trail], 0.09 + (0.0 if sub == 1 else 0.02), -0.12 if sub == 1 else -0.05)
		p["knee.l"] = Vector3(0, 0, 1)
		p["knee.r"] = Vector3(0, 0, 1)
		stair.append(p)
	out["stairs"] = own(stair, 1.3, true)
	return out
