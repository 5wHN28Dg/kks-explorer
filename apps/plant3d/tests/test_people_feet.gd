## People's feet (docs/PLANT3D.md §18.1 as built, phase 4 of the user's plan for people's movement): no foot or hand
## IK, so the clips and how they are played must put the feet where they belong.
## - Every clip with a foot on the floor has its lowest sole on it (within SOLE_FLOOR) all through: KayKit's clips on
##   our longer legs put the walk's standing foot up to 13 cm through the floor, the idle's 1 cm.
## - On level ground the foot on the floor stays put: the point of its sole that is on the floor (within ON of it)
##   moves no more than SLIDE of the ground the person covers, walking at 0.6, 1.3 and 2.0 m/s, running at 3.2, round
##   a corner in a lane, held back and catching up, pushed aside while walking, and in fast-forward (×8):
##   app/people.gd plays the walk and the run at the moment the ground covered says.
## - On the plant's stairs (app/stair_treads.gd, its treads checked against the steps as drawn), up and down: at
##   every update one foot stands on its tread (within TREAD), no sole is ever more than SUNK inside a step, and the
##   standing foot moves no more than STAIR_SLIDE of the ground covered.
## - On the ladder: a foot always on a rung (within RUNG_OFF) and a hand at one, and the foot that stands moves no more
##   than STAIR_SLIDE of the height climbed.
extends RefCounted

const People = preload("res://app/people.gd")
const StairTreads = preload("res://app/stair_treads.gd")
const BP = preload("res://builder/people/build_people.gd")
const Feet = preload("res://tests/feet.gd")
const Lanes = preload("res://app/lanes.gd")

const SOLE_FLOOR := 0.01        # m
const ON := 0.005               # m: a sole this near its floor is on it (a foot coming down is not yet)
## of the ground covered: what is left is where KayKit's walk sets a foot down still moving forward (for one update)
## and the crossfades between standing and walking (no IK yet); a walk played at one rate slid 60 to 70 %
const SLIDE := 0.15
const TREAD := 0.03             # m
const SUNK := 0.02              # m
const STAIR_SLIDE := 0.12       # of the ground covered (a stair's going is up to 3 cm off the clip's: STANCE × that)
const RUNG_OFF := 0.03          # m
const DT := 1.0 / 60.0
const TURN := 5.0               # rad/s: ui/people_view.gd's
const SHARE := {"skinned": 1, "skinned_range": 25.0, "lod0_range": 10.0, "anim_near": 10.0, "posed_range": 80.0,
	"shadows": false}


func run(tree: SceneTree) -> Array:
	if not People.available():
		return ["the build has no people (built/people/)"]
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(People.INFO))
	var feet = Feet.of(info)
	if feet.pos.size() < 20:
		return ["the soles' vertices were not found (%d)" % feet.pos.size()]
	var p: Array = []
	p += _soles(info, feet)
	p += await _level(tree, info)
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://built/plant.json"))
	var treads = StairTreads.of(m)
	if treads == null or treads.flights.is_empty():
		return p + ["the built plant's stairs have no flights (built/plant.json)"]
	p += await _treads_drawn(tree, m, treads)
	p += await _stairs(tree, info, treads)
	p += await _ladder(tree, info, treads)
	return p


## The clips' soles on the floor, 32 moments of each.
func _soles(info: Dictionary, feet) -> Array:
	var p: Array = []
	var scn: Node3D = (load(info.avatar) as PackedScene).instantiate()
	var sk: Skeleton3D = scn.get_node("Skeleton3D")
	var ap: AnimationPlayer = scn.get_node("Anim")
	for k in BP.GROUND + ["walk_road", "idle_road"]:
		var clip := ap.get_animation(k)
		var lo := INF
		var hi := -INF
		for i in 32:
			var low := BP.lowest_sole(sk, clip, clip.length * i / 32.0, feet.pos, feet.wts)
			lo = minf(lo, low)
			hi = maxf(hi, low)
		if lo < -SOLE_FLOOR or (hi > SOLE_FLOOR and not k in BP.RAISE_ONLY):
			p.append("the %s clip's lowest sole is %.3f to %.3f m off the floor" % [k, lo, hi])
	scn.free()
	return p


## A people node with one skinned avatar, stepped by hand, its camera following the person.
func _people(tree: SceneTree, info: Dictionary, treads = null) -> Array:
	var root := Node3D.new()
	tree.root.add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var ppl = People.new()
	root.add_child(ppl)
	ppl.setup(SHARE)
	ppl.camera = cam
	ppl.treads = treads
	ppl.set_process(false)
	ppl.people = [{"at": Vector3.ZERO, "yaw": 0.0, "speed": 0.0, "anim": "", "look": info.looks.keys()[0], "on": "",
		"dir": Vector3.ZERO}]
	return [root, cam, ppl]


## One frame: the person at `at` facing `yaw`, moving `v` (plant m/s, level), on `on`; the camera behind them.
static func _step(ppl, cam: Camera3D, at: Vector3, yaw: float, v: Vector3, on: String, delta: float) -> bool:
	var q: Dictionary = ppl.people[0]
	q.at = at
	q.yaw = yaw
	q.speed = Vector2(v.x, v.z).length()
	q.dir = Vector3(v.x, 0.0, v.z).normalized() if q.speed > 0.0 else Vector3.ZERO
	q.on = on
	cam.global_position = at + Vector3(0, 1.6, 0) + Vector3(sin(yaw), 0, cos(yaw)) * 4.0
	cam.look_at(at + Vector3.UP * 1.0)
	if ppl.avatars[0].person < 0:
		ppl._assign()
	var adv: int = ppl.stats.get("advanced", 0)
	ppl._skinned(delta)
	return ppl.stats.advanced > 0 or adv < 0


## Level ground: the cases, each [name, seconds, time scale, a Callable(t) -> [position, velocity] (plant time)].
func _level(tree: SceneTree, info: Dictionary) -> Array:
	var p: Array = []
	var line = Lanes.make(PackedVector3Array([Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(6, 0, 6)]))
	var straight := func(v: float): return func(t: float): return [Vector3(v * t, 0, 0), Vector3(v, 0, 0)]
	# held back and catching up (app/keep_apart.gd: standing, then up to 35 % faster)
	var held := func(t: float):
		var x := 0.0
		var v := 1.3
		if t < 1.0:
			x = 1.3 * t
		elif t < 1.8:
			x = 1.3
			v = 0.0
		elif t < 4.0:
			x = 1.3 + 1.755 * (t - 1.8)
			v = 1.755
		else:
			x = 1.3 + 1.755 * 2.2 + 1.3 * (t - 4.0)
		return [Vector3(x, 0, 0), Vector3(v, 0, 0)]
	# pushed aside while walking (app/keep_apart.gd PUSH_RATE 1.2 m/s for 0.3 m)
	var pushed := func(t: float):
		var z := clampf((t - 1.5) * 1.2, 0.0, 0.36)
		var vz := 1.2 if t > 1.5 and t < 1.8 else 0.0
		return [Vector3(1.3 * t, 0, z), Vector3(1.3, 0, vz)]
	# a lane 0.35 m right of a line round a corner (app/lanes.gd: the side turns over 0.5 m either side of it)
	var corner := func(t: float):
		var s := minf(1.3 * t, line.length)
		var a: Vector3 = line.at(s, 0.35)
		var b: Vector3 = line.at(minf(s + 0.01, line.length), 0.35)
		return [a, (b - a) / 0.01 * 1.3]
	var cases := [["a walk at 1.3 m/s", 5.0, 1.0, straight.call(1.3)], ["a slow walk at 0.6 m/s", 6.0, 1.0, straight.call(0.6)],
		["a brisk walk at 2.0 m/s", 4.0, 1.0, straight.call(2.0)], ["a run at 3.2 m/s", 3.0, 1.0, straight.call(3.2)],
		["round a corner in a lane", 9.0, 1.0, corner], ["held back and catching up", 6.0, 1.0, held],
		["pushed aside while walking", 4.0, 1.0, pushed], ["a walk in fast-forward (x8)", 1.0, 8.0, straight.call(1.3)]]
	var feet = Feet.of(info)
	for c in cases:
		var made := _people(tree, info)
		var ppl = made[2]
		ppl.time_scale = c[2]
		var f = Feet.of(info)
		var yaw := -PI / 2.0       # facing +x
		var frames := int(c[1] / DT)
		for i in frames:
			var t: float = i * DT * float(c[2])
			var pv: Array = c[3].call(t)
			var v: Vector3 = pv[1]
			if Vector2(v.x, v.z).length() > People.STILL:
				# turning towards the way they move at TURN a second at most (ui/people_view.gd)
				var want := atan2(-v.x, -v.z)
				yaw = wrapf(yaw + clampf(angle_difference(yaw, want), -TURN * DT * c[2], TURN * DT * c[2]), -PI, PI)
			if _step(ppl, made[1], pv[0], yaw, v, "", DT) and i > 30:
				f.slide(feet.world(ppl.avatars[0].node), pv[0], func(_q): return 0.0, ON)
		var name: String = c[0]
		print("people feet: %s: the standing foot slid %.3f m over %.2f m (%.1f %%), at most %.3f m in a stance" % [
			name, f.slid, f.covered, 100.0 * f.ratio(), f.worst])
		if f.covered < 1.0:
			p.append("%s: the person covered only %.2f m" % [name, f.covered])
		elif f.ratio() > SLIDE:
			p.append("%s: the standing foot slid %.3f m over %.2f m (%.1f %%), %.3f m in one stance" % [name, f.slid,
				f.covered, 100.0 * f.ratio(), f.worst])
		made[0].free()
	return p


## The treads app/stair_treads.gd gives are the drawn steps' tops: every tread of three stairs, at its middle, against
## the highest level face of the steps' mesh as built over that point.
func _treads_drawn(_tree: SceneTree, m: Dictionary, treads) -> Array:
	var p: Array = []
	var checked := 0
	for want in [["hrsg1", "hrsg1_stair"], ["control", "ctl_stair"], ["st", "st_pit_stair"]]:
		var scene := ""
		for a in m.areas:
			if a.id == want[0]:
				scene = a.scene
		if scene == "":
			p.append("no area %s in the build" % want[0])
			continue
		var area: Node3D = (load(scene) as PackedScene).instantiate()
		var stair: Node3D = area.find_child(want[1], true, false)
		var steps: MeshInstance3D = stair.get_node_or_null("steps") if stair != null else null
		if steps == null:
			area.free()
			p.append("no steps drawn for %s" % want[1])
			continue
		# the level faces of the steps, in plan with their height
		var xf := _xf_in(area, steps)
		var arr := steps.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var tris: Array = []
		var n: int = idx.size() if idx != null else v.size()
		for f in range(0, n, 3):
			var a3: Vector3 = xf * v[idx[f] if idx != null else f]
			var b3: Vector3 = xf * v[idx[f + 1] if idx != null else f + 1]
			var c3: Vector3 = xf * v[idx[f + 2] if idx != null else f + 2]
			var nrm := (b3 - a3).cross(c3 - a3)
			if nrm.length() > 1e-9 and absf(nrm.normalized().y) > 0.99:     # (a level face)
				tris.append([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), Vector2(c3.x, c3.z), (a3.y + b3.y + c3.y) / 3.0])
		area.free()
		var box := AABB(Vector3(tris[0][0].x, tris[0][3], tris[0][0].y), Vector3.ZERO) if not tris.is_empty() else AABB()
		for t in tris:
			box = box.expand(Vector3(t[0].x, t[3], t[0].y))
		for k in treads.flights.size():
			var fl: Array = treads.flights[k]
			var a: Vector2 = fl[0]
			if not box.grow(0.5).has_point(Vector3(a.x, float(fl[6]) + 0.1, a.y)):
				continue      # (another stair's)
			var g: float = fl[4]
			for j in int(fl[7]) - 1:
				var t := (j + 0.5) * g
				var at: Vector2 = a + (fl[1] as Vector2) * t + (fl[2] as Vector2) * 0.07   # (off a quad's diagonal)
				var top := -INF
				for tr in tris:
					# (this flight's: a switchback's flights above stand over it)
					if tr[3] > float(fl[6]) - 0.05 and tr[3] < float(fl[6]) + float(fl[5]) * int(fl[7]) + 0.05 \
							and Geometry2D.point_is_inside_triangle(at, tr[0], tr[1], tr[2]):
						top = maxf(top, tr[3])
				checked += 1
				if top == -INF:
					p.append("%s: no drawn tread under %.2f m along a flight" % [want[1], t])
				elif absf(top - treads.tread(k, t)) > 0.002:
					p.append("%s: the drawn tread %.2f m along a flight is at %.3f, app/stair_treads.gd says %.3f" % [
						want[1], t, top, treads.tread(k, t)])
				if p.size() > 10:
					return p
	if checked < 100:
		p.append("only %d treads checked against the drawn steps" % checked)
	print("people feet: %d treads checked against the drawn steps" % checked)
	return p


## How far a point `tt` along flight `k` at height `y` is inside its steps: under the tread over it, the less of how
## far under and how far past that tread's riser (a toe a few mm past a nosing is not a riser deep in the step).
static func _into(treads, k: int, tt: float, y: float) -> float:
	var under: float = treads.tread(k, tt) - y
	if under <= 0.0:
		return 0.0
	var fl: Array = treads.flights[k]
	var g: float = fl[4]
	if tt < 0.0:
		return under
	if tt >= float(fl[3]):
		return minf(under, tt - float(fl[3]))     # (past the last riser, onto the landing above)
	return minf(under, tt - floorf(tt / g) * g)


static func _xf_in(root: Node3D, n: Node3D) -> Transform3D:
	var xf := n.transform
	var q := n.get_parent()
	while q != null and q != root and q is Node3D:
		xf = (q as Node3D).transform * xf
		q = q.get_parent()
	return root.transform * xf


## Up and down a flight of three stairs (the HRSG's tower, the control building's, the condenser pit's): the person
## on the slope a walker climbs (as ui/people_view.gd gives them), at a staff member's stair speed.
func _stairs(tree: SceneTree, info: Dictionary, treads) -> Array:
	var p: Array = []
	var feet = Feet.of(info)
	# the first flight of each stair (by its foot, Godot's frame): HRSG 1's, the control building's, the pit's
	var picks := [Vector3(95, 0, -46), Vector3(-39, 0, 14), Vector3(57, -6, -2.5)]
	var done := 0
	for pk in picks:
		var k := -1
		var best := INF
		for i in treads.flights.size():
			var fl: Array = treads.flights[i]
			var d := Vector3((fl[0] as Vector2).x, float(fl[6]), (fl[0] as Vector2).y).distance_to(pk)
			if d < best:
				best = d
				k = i
		var fl: Array = treads.flights[k]
		var a: Vector2 = fl[0]
		var dir: Vector2 = fl[1]
		var g: float = fl[4]
		var run: float = fl[3]
		for down in [false, true]:
			var made := _people(tree, info, treads)
			var ppl = made[2]
			var f = Feet.of(info)
			var v := 0.42     # m/s in plan: staff.json's stair speed (0.5 m/s along the slope)
			var t0 := -1.0 if not down else run + 1.0
			var t1 := run + 1.0 if not down else -1.0
			var n := int(absf(t1 - t0) / v / DT)
			var worst_tread := 0.0
			var worst_sunk := 0.0
			var worst_at := ""
			var name := "%s flight %d %s" % ["up" if not down else "down", k, str(pk)]
			for i in n:
				var t := lerpf(t0, t1, float(i) / n)
				var pl := a + dir * t
				var on := "stairs" if t >= -g and t <= run else ""
				var y := StairTreads.slope(fl, t)
				var vel := Vector3(dir.x, 0, dir.y) * (v if not down else -v)
				var yaw := atan2(-vel.x, -vel.z)
				var adv := _step(ppl, made[1], Vector3(pl.x, y, pl.y), yaw, vel, on, DT)
				if not adv or t < 0.5 * g or t > run - 0.5 * g:
					continue
				var pts: PackedVector3Array = feet.world(ppl.avatars[0].node)
				var tread_of := func(q: Vector3) -> float:
					return treads.tread(k, (Vector2(q.x, q.z) - a).dot(dir))
				var lo: Array = feet.lowest(pts)
				var stand := INF
				for s in 2:
					stand = minf(stand, absf(pts[lo[s]].y - float(tread_of.call(pts[lo[s]]))))
				worst_tread = maxf(worst_tread, stand)
				for q in pts:
					var tq := (Vector2(q.x, q.z) - a).dot(dir)
					var into := _into(treads, k, tq, q.y)
					if into > worst_sunk:
						worst_sunk = into
						worst_at = "the body %.3f m along it, the sole's point %.3f m along it, %.3f high" % [t, tq, q.y]
				f.slide(pts, Vector3(pl.x, y, pl.y), tread_of, ON)
			print("people feet: %s: standing foot off its tread %.3f m at worst, a sole %.3f m under a tread at worst, slid %.3f m over %.2f m (%.1f %%)" % [
				name, worst_tread, worst_sunk, f.slid, f.covered, 100.0 * f.ratio()])
			if worst_tread > TREAD:
				p.append("%s: at times no foot stands on its tread (%.3f m off it)" % [name, worst_tread])
			if worst_sunk > SUNK:
				p.append("%s: a sole %.3f m inside a step (%s)" % [name, worst_sunk, worst_at])
			if f.covered < 1.0 or f.ratio() > STAIR_SLIDE:
				p.append("%s: the standing foot slid %.3f m over %.2f m" % [name, f.slid, f.covered])
			made[0].free()
			done += 1
	if done < 6:
		p.append("only %d flights walked" % done)
	return p


## Up and down the plant's ladder (the HRSG stack's), at the staff's ladder speed.
func _ladder(tree: SceneTree, info: Dictionary, treads) -> Array:
	var p: Array = []
	if treads.ladders.is_empty():
		return ["the built plant has no ladder"]
	var feet = Feet.of(info)
	var l: Array = treads.ladders[0]
	var foot: float = l[1]
	var top: float = l[2]
	var rung: float = float(info.stairs.rung)
	var scn: Node3D = (load(info.avatar) as PackedScene).instantiate()
	var sk: Skeleton3D = scn.get_node("Skeleton3D")
	var wrists := [sk.find_bone("wrist.l"), sk.find_bone("wrist.r")]
	scn.free()
	for down in [false, true]:
		var made := _people(tree, info, treads)
		var ppl = made[2]
		var v := 0.3
		var y0 := foot if not down else top
		var y1 := top if not down else foot
		var n := int(absf(y1 - y0) / v / DT)
		var worst_foot := 0.0
		var worst_hand := 0.0
		var slid := 0.0
		var climbed := 0.0
		var holding := -1
		var last_y := 0.0
		var body_y := NAN
		for i in n:
			var y := lerpf(y0, y1, float(i) / n)
			var at := Vector3((l[0] as Vector2).x, y, (l[0] as Vector2).y)
			if not _step(ppl, made[1], at, 0.0, Vector3.ZERO, "ladder", DT):
				continue
			if y < foot + 2.0 * rung or y > top - 2.0 * rung:
				continue
			var node: Node3D = ppl.avatars[0].node
			var pts: PackedVector3Array = feet.world(node)
			var lo: Array = feet.lowest(pts)
			var off := [INF, INF]
			for s in 2:
				var sy: float = pts[lo[s]].y
				var k := roundf((sy - 0.015 - foot) / rung)
				off[s] = absf(sy - (foot + k * rung + 0.015))
			var s_on := 0 if off[0] <= off[1] else 1
			worst_foot = maxf(worst_foot, off[s_on])
			var sk2: Skeleton3D = node.get_node("Skeleton3D")
			var hand := INF
			for w in wrists:
				var wy: float = (sk2.global_transform * sk2.get_bone_global_pose(w)).origin.y
				hand = minf(hand, absf(wy - (foot + roundf((wy - foot) / rung) * rung)))
			worst_hand = maxf(worst_hand, hand)
			# the foot that stands, while it stands: how far it moves up or down
			var sy2: float = pts[lo[s_on]].y
			if holding == s_on:
				slid += absf(sy2 - last_y)
			holding = s_on
			last_y = sy2
			if not is_nan(body_y):
				climbed += absf(y - body_y)
			body_y = y
		var name := "down the ladder" if down else "up the ladder"
		print("people feet: %s: the standing foot off its rung %.3f m at worst, a hand %.3f m, the standing foot moved %.3f m over %.2f m climbed" % [
			name, worst_foot, worst_hand, slid, climbed])
		if worst_foot > RUNG_OFF:
			p.append("%s: at times no foot on a rung (%.3f m off)" % [name, worst_foot])
		if worst_hand > RUNG_OFF + 0.01:
			p.append("%s: at times no hand at a rung (%.3f m off)" % [name, worst_hand])
		if climbed < 3.0 or slid > STAIR_SLIDE * climbed:
			p.append("%s: the standing foot moved %.3f m over %.2f m climbed" % [name, slid, climbed])
		made[0].free()
	return p
