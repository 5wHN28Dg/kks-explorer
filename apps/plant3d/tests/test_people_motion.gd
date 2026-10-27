## People's movement on screen, phase 3 of the user's plan (docs/PLANT3D.md §18.1 as built): view only, the engine
## untouched.
## - Keeping apart (app/keep_apart.gd) on a scene of its own (a floor, a wall, a post), its room measured as the content
##   build measures it (builder/lane_room.gd): two people walking at each other on one line, two crossing at right
##   angles timed to meet, one walking past a player standing on their line, two walking at each other along the wall,
##   two standing at one place: never nearer than MIN_APART; and one walking past a post on their line; every drawn
##   point's capsule clear, nobody moved faster than they can walk.
## - The crews of a shift's start in the app (ui/people_view.gd), frame by frame for SECONDS of plant time: nobody turns
##   faster than people_view's TURN, nobody jumps, every walker's capsule clear of all but doors (and the standing,
##   moved aside, where their place is clear).
## - Doors (app/people_doors.gd): every door of the plant opens for someone walking through it, at a walk and at a run,
##   in time (its leaf never touches them); not for someone walking away from it or past it.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Lanes = preload("res://app/lanes.gd")
const KeepApart = preload("res://app/keep_apart.gd")
const LaneRoom = preload("res://builder/lane_room.gd")
const PeopleDoors = preload("res://app/people_doors.gd")
const PeopleView = preload("res://ui/people_view.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const MIN_APART := 0.6          # metres between two people's centres, at least, where there is room
const RADIUS := 0.3             # the walker's capsule (0.4 to 1.8 m above the feet)
const DT := 1.0 / 60.0
const SECONDS := 240.0          # of the shift's start, frame by frame


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += await _apart(tree)
	p += await _crews(tree)
	return p


static func _box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = at
	parent.add_child(b)


static func _capsule_query() -> PhysicsShapeQueryParameters3D:
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	return q


static func _hits(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, at: Vector3) -> bool:
	q.transform = Transform3D(Basis(), at + Vector3.UP * 1.1)
	return not space.intersect_shape(q, 1).is_empty()


## The scenes of keeping apart: [name, walkers ([line, from end (0 or 1), start delay s]), fixed points, standers].
func _apart(tree: SceneTree) -> Array:
	var p: Array = []
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.world_3d = World3D.new()
	tree.root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	_box(world, Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))         # the floor, its top at 0
	_box(world, Vector3(0, 1.0, 10.0), Vector3(20, 2.0, 0.2))      # a wall along x at z = 10 (its face at 9.9)
	_box(world, Vector3(-10, 1.0, -10.0), Vector3(0.2, 2.0, 0.2))  # a post
	for i in 3:
		await tree.physics_frame
	var space := world.get_world_3d().direct_space_state
	var lr := LaneRoom.new(space, null, [])
	var mk := func(a: Vector3, b: Vector3):
		var l = Lanes.make(PackedVector3Array([a, b]))
		l.room = lr.line(l, true)
		return l
	var l1 = mk.call(Vector3(-8, 0, 0), Vector3(8, 0, 0))          # along x through the middle
	var l2 = mk.call(Vector3(0, 0, -8), Vector3(0, 0, 8))          # along z, crossing it at the middle
	var l3 = mk.call(Vector3(-8, 0, 9.3), Vector3(8, 0, 9.3))      # along the wall, 0.6 m from its face
	var l4 = mk.call(Vector3(-10, 0, -4), Vector3(-10, 0, -16))    # through the post
	var room3: Vector2 = l3.room_at(8.0)
	if room3.y > 0.35 or room3.y < 0.0:
		p.append("the room beside a line 0.6 m from a wall is %.2f m on the wall's side (the capsule's 0.38 leaves 0.22)" % room3.y)
	var r4: Vector2 = l4.room_at(6.0)
	if not (r4.x > 0.0 or r4.y < 0.0):
		p.append("the room beside a line through a post does not leave the post out (%s)" % str(r4))
	var stand: PackedByteArray = lr.place(Vector3(5, 0, -5))
	var scenes := [
		["two walking at each other on one line", [[l1, 0, 0.0], [l1, 1, 0.0]], [], []],
		["two crossing at right angles, timed to meet", [[l1, 0, 0.0], [l2, 0, 0.0]], [], []],
		["one walking past a player standing on the line", [[l1, 0, 0.0]], [Vector3(0, 0, 0)], []],
		["two walking at each other along a wall", [[l3, 0, 0.0], [l3, 1, 0.0]], [], []],
		["one overtaking another on one line", [[l1, 0, 0.0], [l1, 0, 1.2]], [], []],
		["two standing at one place", [], [], [Vector3(5, 0, -5), Vector3(5, 0, -5)]],
		["one walking past a post", [[l4, 0, 0.0]], [], []],
	]
	var q := _capsule_query()
	for sc in scenes:
		var ka := KeepApart.new()
		var nearest := INF
		var problems: Array = []
		var last := {}
		for f in int(16.0 / DT):
			var t := f * DT
			ka.begin()
			for fx in sc[2]:
				ka.fixed(-1, fx)
			var ids := []
			for k in sc[1].size():
				var w: Array = sc[1][k]
				var l = w[0]
				var v := 0.7 if k == 0 and sc[0].find("overtaking") != -1 else 1.3   # (the one ahead slower)
				var go := (t - float(w[2])) * v
				if go < 0.0 or go >= l.length:
					continue
				ka.walker(k, l, go if w[1] == 0 else l.length - go, 1.0 if w[1] == 0 else -1.0, v)
				ids.append(k)
			for k in sc[3].size():
				ka.stander(10 + k, sc[3][k], stand)
				ids.append(10 + k)
			if ka.n == 0:
				break
			ka.solve(DT)
			for i in ka.n:
				var at: Vector3 = ka.pos[i]
				for j in range(i + 1, ka.n):
					var d := Vector2(at.x - ka.pos[j].x, at.z - ka.pos[j].z).length()
					# (standing: once they have had a second to step apart)
					if sc[3].is_empty() or t > 1.5:
						nearest = minf(nearest, d)
				if ka.ids[i] < 0:
					continue
				if _hits(space, q, at) and problems.size() < 3:
					problems.append("drawn at %s, in the wall or the post" % str(at))
				if last.has(ka.ids[i]) and ka.fresh[i] == 0 and at.distance_to(last[ka.ids[i]]) > 3.0 * DT and problems.size() < 3:
					problems.append("jumped %.3f m in a frame at %s" % [at.distance_to(last[ka.ids[i]]), str(at)])
				last[ka.ids[i]] = at
		if nearest < MIN_APART:
			problems.append("they came within %.2f m of each other" % nearest)
		for e in problems:
			p.append("%s: %s" % [sc[0], e])
		print("people motion: %s: nearest %.2f m" % [sc[0], nearest])
	vp.free()
	return p


## The crews of a shift's start, frame by frame.
func _crews(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold") or ui.people == null:
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	if main.interiors != null:
		main.interiors.load_all()
	for i in 4:
		await tree.physics_frame
	ui.start_shift("shift_cold")
	await tree.process_frame
	ui.take_role("")
	var pv = ui.people
	pv.drive(0.0)
	if pv.avatars == null or pv.ways == null:
		main.free()
		return ["the people view has no avatars or no built lines"]
	ui.clock.set_process(false)
	pv.set_process(false)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var skip: Array[RID] = [main.player.get_rid()]
	for n in tree.get_nodes_in_group("doors"):
		if n is CollisionObject3D:
			skip.append(n.get_rid())
	var q := _capsule_query()
	q.exclude = skip
	var e = ui.clock.engine
	var place_clear := {}
	var yaw := {}
	var at := {}
	var turned := 0
	var turns: Array = []
	var jumps: Array = []
	var fresh: Array = []
	var seen := {}
	var logical := {}
	var hits: Array = []
	var walking := 0
	var close := 0
	var acc := 0.0
	for f in int(SECONDS / DT):
		acc += DT
		while acc >= SimClock.STEP:
			ui.clock.run_steps(1)
			acc -= SimClock.STEP
		ui.clock.acc = acc
		pv.drive(DT)
		var ppl: Array = pv.avatars.people
		for k in ppl.size():
			var pi: int = pv.drawn[k]
			var q_at: Vector3 = ppl[k].at
			var y: float = ppl[k].yaw
			# set at once (not turned to) only when new or jumped: never for someone drawn the frame before who has
			# not jumped in the engine (getting up from a seat, setting off from a place, a walk without a line)
			if pv.drawn_fresh[k] == 1 and seen.get(pi, -1) == f - 1 and \
					(pv._logical_of(pi) - logical.get(pi, Vector3.INF)).length() < 2.0 and fresh.size() < 5:
				fresh.append("person %d's heading was set, not turned to, at %s" % [pi, str(q_at)])
			seen[pi] = f
			logical[pi] = pv._logical_of(pi)
			if pv.drawn_fresh[k] == 0 and yaw.has(pi):
				var d := absf(angle_difference(yaw[pi], y))
				if d > PeopleView.TURN * DT + 1e-4 and turns.size() < 5:
					turns.append("person %d turned %.3f rad in a frame at %s" % [pi, d, str(q_at)])
				if d > 1e-4:
					turned += 1
				var m: float = (at[pi] as Vector3).distance_to(q_at)
				if m > 4.0 * DT + 0.01 and jumps.size() < 5:
					jumps.append("person %d moved %.2f m in a frame at %s" % [pi, m, str(q_at)])
			yaw[pi] = y
			at[pi] = q_at
			var kind: int = pv.drawn_kind[k]
			var check := kind == KeepApart.WALKING
			if kind == KeepApart.STANDING:
				var pl: int = e.sp_pos[pi]
				if not place_clear.has(pl):
					place_clear[pl] = not _hits(space, q, pv._at[pl])
				check = place_clear[pl] and q_at.distance_to(pv._at[pl]) > 0.01
			if kind == KeepApart.WALKING:
				walking += 1
			if check and _hits(space, q, q_at) and hits.size() < 8:
				hits.append("person %d drawn at %s (%s): the capsule touches %s" % [pi, str(q_at),
						"walking" if kind == KeepApart.WALKING else "standing aside",
						str(space.intersect_shape(q, 1)[0].collider.get_parent().name)])
			for j in range(k + 1, ppl.size()):
				if pv.drawn_kind[k] != KeepApart.FIXED and pv.drawn_kind[j] != KeepApart.FIXED and \
						(ppl[j].at as Vector3).distance_to(q_at) < 0.4:
					close += 1
	print("people motion: crews: %d walker-frames, %d turning, %d person-frames within 0.4 m of another" % [walking, turned, close])
	p.append_array(turns)
	p.append_array(jumps)
	p.append_array(fresh)
	p.append_array(hits)
	if walking < 2000:
		p.append("only %d walker-frames in the shift's start: the check proves little" % walking)
	if turned < 100:
		p.append("people turned in only %d frames" % turned)
	p.append_array(_doors(tree, main))
	main.free()
	return p


## Every door: someone walking through it (at a walk and at a run, either way, the check's moment early and late) is
## never touched by its leaf; nobody walking away from it or past it opens it.
static func _doors(tree: SceneTree, main) -> Array:
	var out: Array = []
	var n := 0
	for door in tree.get_nodes_in_group("doors"):
		if not door.has_method("press"):
			continue
		n += 1
		var par: Node3D = door.get_parent_node_3d()
		var shut: Transform3D = par.global_transform * door.closed_xf
		var z: Vector3 = shut.basis.z.normalized()
		var bad := ""
		# through its middle, and as far to either side as the room beside a line through it allows (the jambs and the
		# build's 0.41 m capsule: builder/lane_room.gd)
		var aside := maxf(0.0, float(door.width) * 0.5 - 0.41)
		for v in [1.3, 3.2]:
			for side in [1.0, -1.0]:
				for phase in [0.0, 0.24]:
					for x in [0.0, aside, -aside]:
						if bad == "":
							bad = _through(tree, door, shut, z * side, v, phase, shut.basis.x.normalized() * x)
		# round a corner 1.5 m before it, their heading still along the first leg (it trails: ui/people_view.gd)
		for side in [1.0, -1.0]:
			if bad == "":
				bad = _corner(tree, door, shut, z * side)
		if bad != "":
			out.append("door %s: %s" % [door.name, bad])
		# walking away from it from 2 m beyond its leaf, and past it 3 m in front: shut
		for w in [[shut.origin - z * 2.0, -z], [shut.origin + z * 3.0 - shut.basis.x * 4.0, shut.basis.x]]:
			var pd := PeopleDoors.new()
			var o: Vector3 = w[0]
			var dir: Vector3 = w[1]
			door.hold = 0.0
			for f in 120:
				var at := o + dir * (1.3 * f * DT)
				pd.tick(tree, [{"at": at, "speed": 1.3, "yaw": atan2(-dir.x, -dir.z)}], DT)
			var opened: bool = door.hold > 0.0     # (another door near it may open: not this one)
			door.hold = 0.0
			if opened:
				out.append("door %s: opened for someone walking %s it" % [door.name, "away from" if w[1] == -z else "past"])
		# someone standing in its doorway keeps it open; someone standing 1 m off it does not open it
		for st in [[0.3, true], [1.0, false]]:
			var pd := PeopleDoors.new()
			door.hold = 0.0
			pd.check(tree, [{"at": shut.origin + z * float(st[0]), "speed": 0.0, "yaw": 0.0}])
			if (door.hold > 0.0) != st[1]:
				out.append("door %s: %s for someone standing %.1f m from it" % [door.name,
						"not kept open" if st[1] else "opened", st[0]])
			door.hold = 0.0
	if n < 30:
		out.append("only %d doors checked" % n)
	return out


## Someone walking along the door's leaf 1.5 m before it, then turning through it along `dir`, facing along the first
## leg all the time: "" or what went wrong.
static func _corner(tree: SceneTree, door, shut: Transform3D, dir: Vector3) -> String:
	var pd := PeopleDoors.new(0.24)
	var across: Vector3 = shut.basis.x.normalized()
	var turn := shut.origin - dir * 1.5
	var path := [[turn - across * 4.0, turn], [turn, shut.origin + dir * 1.5]]
	var inv := shut.affine_inverse()
	var out := ""
	for leg in path:
		var a: Vector3 = leg[0]
		var b: Vector3 = leg[1]
		var d := (b - a).normalized()
		for f in int(a.distance_to(b) / 1.3 / DT):
			var at := a + d * (1.3 * f * DT)
			pd.tick(tree, [{"at": at, "speed": 1.3, "yaw": atan2(-across.x, -across.z), "dir": d}], DT)
			door._physics_process(DT)
			if out == "" and _touches(door, inv * at):
				out = "its leaf (open %.2f) touches someone who turned through it at a walk" % door.openness
	door.openness = 0.0
	door.hold = 0.0
	door.transform = door.closed_xf
	return out


## Whether the door's leaf where it is now (app/door.gd: slid aside along its width, or a roller up by its height)
## touches someone at `lp` (in the shut door's frame, the feet), their capsule RADIUS from 0.4 to 1.8 m up.
static func _touches(door, lp: Vector3) -> bool:
	var w: float = door.width
	var h: float = door.height
	var off_x: float = 0.0 if door.kind == "roller" else door.openness * w
	var off_y: float = door.openness * h if door.kind == "roller" else 0.0
	var dx := maxf(0.0, absf(lp.x - off_x) - w * 0.5)
	var dz := maxf(0.0, absf(lp.z) - 0.04)
	var dy := maxf(0.0, maxf(off_y - 1.8, 0.4 - (off_y + h)))
	return Vector3(dx, dy, dz).length() < RADIUS


## Someone walking along `dir` through `door` (its shut transform `shut`) at `v` m/s from 6 m before its leaf to 1.5 m
## beyond, the door checked by app/people_doors.gd from `phase` s in: "" or what went wrong.
static func _through(tree: SceneTree, door, shut: Transform3D, dir: Vector3, v: float, phase: float,
		aside: Vector3) -> String:
	var pd := PeopleDoors.new(phase)
	var from := shut.origin - dir * 6.0 + aside
	var inv := shut.affine_inverse()
	var out := ""
	var steps := int(7.5 / v / DT)
	for f in steps:
		var at := from + dir * (v * f * DT)
		pd.tick(tree, [{"at": at, "speed": v, "yaw": atan2(-dir.x, -dir.z), "dir": dir}], DT)
		door._physics_process(DT)
		var lp := inv * at
		if _touches(door, lp):
			out = "its leaf (open %.2f) touches someone walking through it at %.1f m/s, %.2f m from it, %.2f m off its middle" % [
					door.openness, v, lp.z, lp.x]
			break
	door.openness = 0.0
	door.hold = 0.0
	door.transform = door.closed_xf
	return out
