## The staff's walking network against the built plant's navigation mesh (docs/PLANT3D.md §16.2, §18.1): every place
## stands on the mesh, every work place within reach of its equipment, and every way is walkable on the mesh. Every
## place is also reached from the origin by the ways (the validator's `unreachable`, checked here on the content the
## app loads).
##
## And the lines people are drawn along (app/staff_ways.gd, built by builder/staff_paths.gd), as ui/people_view.gd
## walks them: every way has one, from its place to its place, as long as the way's length within 10 % either side
## (so a person neither hurries nor dawdles: the way's time is its length's), never a run; a 0.3 m capsule (the
## walker's, 0.4 to 1.8 m above the feet) on it every SAMPLE metres touches no collider but a door's (doors open for
## walkers); the feet are within FEET of what a walker stands on (a floor, a deck, a stair's slope, the one the
## walking test climbs, through the treads' nosings), except on a ladder; each stair way has a stretch on its steps.
## People are drawn off their lines and places only within the room the build measured beside them (phase 3,
## app/keep_apart.gd, app/lanes.gd): every OFFSET_STEP metres along every line, at the room's edges on both sides and in
## the lane either way it is walked, the capsule touches nothing but doors and the feet are within SIDE_FEET of a floor;
## round every place, at the edge of its room in every direction, likewise. The measurement crowd's lanes on the walks'
## routes (app/crowd.gd, built/crowd_lanes.bin) the same, at its lanes' widths too.
## Until 2026-10-26 this test measured the mesh's path against the way's length, which was measured on that same path,
## while people were drawn along the straight line between the places: through machines and rails, floating up the
## HRSG's stair. 45 ways' paths were more than 10 % longer than that line, and nothing compared the two.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const Layout = preload("res://tests/staff_layout.gd")
const StaffWays = preload("res://app/staff_ways.gd")
const StaffPaths = preload("res://builder/staff_paths.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const PeopleView = preload("res://app/people.gd")
const Lanes = preload("res://app/lanes.gd")
const KeepApart = preload("res://app/keep_apart.gd")
const Crowd = preload("res://app/crowd.gd")
const Routes = preload("res://app/routes.gd")

const ON_MESH := 0.35       # m: a place's distance to the mesh
const REACH := 8.0          # m: from a work place (at eye height) to its equipment's bounds: a thermocouple high on the exhaust duct is read from the floor below
const SAMPLE := 0.1         # m between the points of a line checked
const RADIUS := 0.3         # m: the walker's capsule (app/player.gd)
const FEET := 0.05          # m: the feet off what is under them
const LENGTH := 0.1         # a line's length off its way's, at most (and 5 cm)
const OFFSET_STEP := 0.05   # m between the points checked beside a line (the room's samples and half way between)
const SIDE_FEET := 0.1      # m: the floor beside a line off the one under it, at most (the build keeps 8 cm)


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var m = PlantModel.from_dir("res://built/content")
	if m.error != "" or m.staff == null:
		return ["the built content has no staff (%s)" % m.error]
	var main := App.start(tree)
	var ui = main.ui
	var r = ui.route
	# 20 s of the clock: the map is made on a worker thread, which the headless run's frames don't wait for
	var t_ready := Time.get_ticks_msec()
	while not r.ready_to_find() and Time.get_ticks_msec() - t_ready < 20000:
		await tree.physics_frame
	if not r.ready_to_find():
		main.free()
		return ["the navigation map was not ready 20 s after the start"]
	var sm = m.staff
	var bad := 0
	var local := {}
	for o in m.ops:
		if o["where"].has("local"):
			local[o["kks"]] = true
	for pl in sm.places:
		var g := Layout.godot_of(pl["at"])
		var c: Vector3 = NavigationServer3D.map_get_closest_point(r.map, g)
		if c.distance_to(g) > ON_MESH:
			p.append("place %s %s is %.2f m off the walkable mesh" % [pl["id"], str(pl["at"]), c.distance_to(g)])
		if pl["kind"] == "work" and ui.index.has(pl["kks"]):
			var box: AABB = ui.index.box(pl["kks"])
			var eye := g + Vector3.UP * 1.6
			var d := eye.distance_to(eye.clamp(box.position, box.end))
			if d > REACH:
				p.append("work place %s is %.1f m from %s (reach %.0f m)" % [pl["id"], d, pl["kks"], REACH])
			# where a local op is made, the card must offer it: within the app's reach of the walker (ui/plant_ui.gd)
			if local.has(pl["kks"]) and ui.index.distance(pl["kks"], g + Vector3.UP * 1.0) > ui.REACH:
				p.append("work place %s: %s's local ops are out of the card's reach (%.1f m)" % [pl["id"], pl["kks"],
						ui.index.distance(pl["kks"], g + Vector3.UP * 1.0)])
	for w in m.staff.d["ways"]:
		var a: Vector3 = Layout.godot_of(sm.places[sm.pix[w[0]]]["at"])
		var b: Vector3 = Layout.godot_of(sm.places[sm.pix[w[1]]]["at"])
		var f: Dictionary = r.find(a, b)
		if not f["reached"]:
			p.append("way %s–%s: not walkable on the mesh" % [w[0], w[1]])
			bad += 1
		if bad > 20:
			p.append("… more")
			break
	# the lines people walk, with every interior standing (the app loads them near their doors)
	if main.interiors != null:
		main.interiors.load_all()
	for i in 4:
		await tree.physics_frame
	p.append_array(_doors(tree, r))
	var at: Array = []
	for pl in sm.places:
		at.append(Layout.godot_of(pl["at"]))
	var ways = StaffWays.open(sm, at)
	if ways == null:
		p.append("the build has no lines for the staff's ways (%s)" % StaffWays.FILE)
	else:
		var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
		var skip: Array[RID] = [main.player.get_rid()]
		for n in tree.get_nodes_in_group("doors"):
			if n is CollisionObject3D:
				skip.append(n.get_rid())
		var lb := 0
		var samples := 0
		var on_stairs := 0
		for w in sm.d["ways"]:
			var ia: int = sm.pix[w[0]]
			var ib: int = sm.pix[w[1]]
			var steps: int = sm.ways[mini(ia, ib) * at.size() + maxi(ia, ib)]
			var res := check_line(ways, space, skip, ia, ib, at.size(), steps * SimClock.STEP, float(w[2]))
			samples += res[1]
			on_stairs += res[2]
			if w[3] == "stair" and res[2] == 0:
				p.append("way %s–%s: a stair way with no stretch on stairs" % [w[0], w[1]])
			for e in res[0]:
				p.append("way %s–%s: %s" % [w[0], w[1], e])
				lb += 1
			if lb > 30:
				p.append("… more")
				break
		# beside the lines and round the places: where people are drawn off them
		var side_n := 0
		var sb := 0
		for key in ways.lines:
			var res := check_room(ways.lines[key][4], space, skip, KeepApart.LANE, [])
			side_n += res[1]
			for e in res[0]:
				p.append("the line %s: %s" % [_way_name(sm, ways.lines[key]), e])
				sb += 1
			if sb > 30:
				p.append("… more")
				break
		var stand_n := 0
		for i in sm.places.size():
			var res := check_place(ways.place_room[i], at[i], space, skip)
			stand_n += res[1]
			for e in res[0]:
				p.append("place %s: %s" % [sm.places[i]["id"], e])
				sb += 1
			if sb > 40:
				break
		print("staff ways: %d points beside the lines checked, %d round the places" % [side_n, stand_n])
		print("staff ways: %d lines walked, %d points checked, %d on stairs" % [ways.lines.size(), samples, on_stairs])
		# the stairs' ways are among them, walked on the steps (the HRSG's, the cooling tower's, the turbine hall's)
		if on_stairs < 200:
			p.append("only %d points of the lines are on stairs" % on_stairs)
	print("staff ways: %d places, %d ways checked on the mesh" % [sm.places.size(), m.staff.d["ways"].size()])
	p.append_array(_crowd_lanes(main))
	main.free()
	return p


## The measurement crowd's lanes on the frames, camp and water plant walks' routes (app/crowd.gd as it places them).
static func _crowd_lanes(main) -> Array:
	var out: Array = []
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var skip: Array[RID] = [main.player.get_rid()]
	for n in main.get_tree().get_nodes_in_group("doors"):
		if n is CollisionObject3D:
			skip.append(n.get_rid())
	var total := 0
	for name in ["frames", "camp", "wtp"]:
		var route: Array = Routes.frames(main.plant) if name == "frames" else (Routes.camp(main.plant) if name == "camp" \
				else Routes.wtp_loop())
		var pts := Crowd.route_points(route)
		var room := Crowd.room_of(pts)
		if room.is_empty():
			out.append("the crowd's %s route has no lanes built (%s)" % [name, Crowd.LANES])
			continue
		var l = Lanes.make(pts, room, Crowd.looped(pts))
		if l.room.is_empty():
			out.append("the crowd's %s route's lanes do not fit it" % name)
			continue
		# its lanes: 0.35 to 0.85 m right of the route either way it is walked, those at work 0.8 m to its right
		var res := check_room(l, space, skip, 0.35, [0.6, 0.85, 0.8])
		total += res[1]
		for e in res[0].slice(0, 15):
			out.append("the crowd's %s route: %s" % [name, e])
		if res[0].size() > 15:
			out.append("the crowd's %s route: … %d more" % [name, res[0].size() - 15])
	print("staff ways: %d points of the crowd's lanes checked" % total)
	return out


static func _way_name(sm, l: Array) -> String:
	var a: int = l[3]
	var pts: PackedVector3Array = l[0]
	for w in sm.d["ways"]:
		if sm.pix[w[0]] == a or sm.pix[w[1]] == a:
			var other: int = sm.pix[w[1]] if sm.pix[w[0]] == a else sm.pix[w[0]]
			var b := Layout.godot_of(sm.places[other]["at"])
			if Vector2(b.x - pts[pts.size() - 1].x, b.z - pts[pts.size() - 1].z).length() < 0.06:
				return "%s–%s" % [sm.places[a]["id"], sm.places[other]["id"]]
	return sm.places[a]["id"] + "–?"


## Beside a line (app/lanes.gd) where people may be drawn: every OFFSET_STEP metres, at its room's edges and at `lane`
## (and each of `more`) either side, clamped to the room as app/keep_apart.gd and app/crowd.gd clamp: the capsule
## touches nothing (but what `skip` leaves out) and the floor there is within SIDE_FEET of the one under the line (not
## off a flight's side or a step, onto a kerb: the line's own feet are checked above). [problems, points].
static func check_room(l, space: PhysicsDirectSpaceState3D, skip: Array[RID], lane: float, more: Array) -> Array:
	var out: Array = []
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = skip
	var checked := 0
	var bad := 0
	var lanes: Array = [lane, -lane]
	for m in more:
		lanes.append_array([m, -m])
	var n := ceili(l.length / OFFSET_STEP)
	for i in n + 1:
		var s := minf(i * OFFSET_STEP, l.length)
		var r: Vector2 = l.room_at(s)
		if r.x > r.y + 1e-4:
			out.append("its room at %.2f m is the wrong way round (%s)" % [s, str(r)])
			return [out, checked]
		var offs: Array = [r.x, r.y]
		for w in lanes:
			offs.append(clampf(w, r.x, r.y))
		var y0: float = StaffPaths.surface(space, l.point(s), 0.5, 0.6, skip)
		for o in offs:
			var at: Vector3 = l.at(s, o)
			checked += 1
			q.transform = Transform3D(Basis(), at + Vector3.UP * 1.1)
			var hit := space.intersect_shape(q, 1)
			var problem := ""
			if not hit.is_empty():
				var c: Node = hit[0].collider
				problem = "the capsule %.2f m beside it at %.2f m (%s) hits %s" % [o, s, str(at),
						String(c.get_parent().name) + "/" + String(c.name) if c.get_parent() != null else String(c.name)]
			else:
				var y: float = StaffPaths.surface(space, at, 0.5, 0.6, skip)
				if not is_nan(y0) and (is_nan(y) or absf(y0 - y) > SIDE_FEET):
					problem = "the feet %.2f m beside it at %.2f m (%s) are %s" % [o, s, str(at),
							"over nothing" if is_nan(y) else "%.2f m off the floor under it" % (y0 - y)]
			if problem != "":
				bad += 1
				if bad <= 6:
					out.append(problem)
				break
	if bad > 6:
		out.append("… %d more points" % (bad - 6))
	return [out, checked]


## Round a place where people may be drawn (app/keep_apart.gd): at the edge of its room, in its measured directions
## and half way between each two, the capsule touches nothing and the floor is within SIDE_FEET of the one under it.
static func check_place(room: PackedByteArray, at: Vector3, space: PhysicsDirectSpaceState3D, skip: Array[RID]) -> Array:
	if room.is_empty():
		return [["no room measured round it"], 0]
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = skip
	var out: Array = []
	var checked := 0
	for i in 2 * KeepApart.DIRS:
		var a := PI * i / KeepApart.DIRS
		var dir := Vector3(cos(a), 0.0, sin(a))
		var r := KeepApart.stand_room(room, dir)
		if r <= 0.0:
			continue
		var p := at + dir * r
		checked += 1
		q.transform = Transform3D(Basis(), p + Vector3.UP * 1.1)
		var hit := space.intersect_shape(q, 1)
		if not hit.is_empty():
			out.append("%.2f m from it towards %s the capsule hits %s" % [r, str(dir), String(hit[0].collider.name)])
			break
		var y: float = StaffPaths.surface(space, p, 0.5, 0.6, skip)
		var y0: float = StaffPaths.surface(space, at, 0.5, 0.6, skip)
		if not is_nan(y0) and (is_nan(y) or absf(y0 - y) > SIDE_FEET):
			out.append("%.2f m from it towards %s the feet are off the floor" % [r, str(dir)])
			break
	return [out, checked]


## A way's line as people walk it from place `ia` to place `ib` (and back), the way taking `seconds` and being
## `metres` long: [problems, points checked].
static func check_line(ways, space: PhysicsDirectSpaceState3D, skip: Array[RID], ia: int, ib: int, places: int,
		seconds: float, metres: float) -> Array:
	var out: Array = []
	var key := mini(ia, ib) * places + maxi(ia, ib)
	if not ways.lines.has(key):
		return [["no line (built/staff_paths.bin)"], 0, 0]
	var pts: PackedVector3Array = ways.lines[key][0]
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	if absf(length - metres) > LENGTH * metres + 0.05:
		out.append("its line is %.2f m, its length %.2f m (more than 10 %% apart: a person would hurry or dawdle)" % [
				length, metres])
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = skip
	var hits := {}
	var feet := {}
	var stairs := 0
	var fast := 0.0
	# the line itself every SAMPLE metres: the capsule and the feet
	var on: PackedByteArray = ways.lines[key][2]
	var checked := 0
	for i in range(1, pts.size()):
		var m := maxi(1, ceili(pts[i - 1].distance_to(pts[i]) / SAMPLE))
		for k in range(0 if i == 1 else 1, m + 1):
			var at := pts[i - 1].lerp(pts[i], float(k) / m)
			checked += 1
			q.transform = Transform3D(Basis(), at + Vector3.UP * 1.1)
			for h in space.intersect_shape(q, 4):
				var c: Node = h.collider
				var name := String(c.get_parent().name) + "/" + String(c.name) if c.get_parent() != null else String(c.name)
				if not hits.has(name):
					hits[name] = at
			if on[i - 1] == StaffWays.ON_STAIRS:
				stairs += 1
			if on[i - 1] != StaffWays.ON_LADDER:
				var y: float = StaffPaths.surface(space, at, 0.3, 0.5, skip)
				var gap: float = 0.5 if is_nan(y) else at.y - y
				if absf(gap) > FEET and feet.size() < 3:
					feet[at] = gap
	# walked as ui/people_view.gd walks it, from either end: its speed, its ends
	var n := maxi(2, ceili(length / SAMPLE))
	for dir in 2:
		var from := ia if dir == 0 else ib
		var to := ib if dir == 0 else ia
		for i in n + 1:
			if not ways.walk(key, from, float(i) / n, seconds):
				return [["walk() found no line"], 0, 0]
			fast = maxf(fast, ways.speed)
			if i == 0 and Vector2(ways.pos.x - at_of(ways, key, from).x, ways.pos.z - at_of(ways, key, from).z).length() > 0.01:
				out.append("walked from %s, it does not start there" % ["its first place", "its second place"][dir])
			if i == n and Vector2(ways.pos.x - at_of(ways, key, to).x, ways.pos.z - at_of(ways, key, to).z).length() > 0.01:
				out.append("walked from %s, it does not end at the other" % ["its first place", "its second place"][dir])
	for name in hits:
		out.append("the capsule on its line hits %s at %s" % [name, str(hits[name])])
	for at in feet:
		out.append("the feet at %s are %.2f m %s what is under them" % [str(at), absf(feet[at]),
				"above" if feet[at] > 0.0 else "into"])
	if fast > PeopleView.RUN_FROM:
		out.append("walked at %.2f m/s somewhere (a run from %.1f m/s)" % [fast, PeopleView.RUN_FROM])
	return [out, checked, stairs]


## The end of a way's line at place `place`.
static func at_of(ways, key: int, place: int) -> Vector3:
	var pts: PackedVector3Array = ways.lines[key][0]
	return pts[0] if ways.lines[key][3] == place else pts[pts.size() - 1]


## Every door 1 m wide or more is walked through on the mesh: from 1 m in front of it to 1 m behind it in at most
## 3 m (the mesh keeps 0.4 m from each jamb, builder/nav_bake.gd: a 0.9 m door of the camp's rooms left the rooms off
## it, 2026-10-26). Narrower doors (the camp's bathrooms, 0.7 m) are not on it.
static func _doors(tree: SceneTree, r) -> Array:
	var out: Array = []
	var n := 0
	for d in tree.get_nodes_in_group("doors"):
		if float(d.get("width")) < 0.95:
			continue
		n += 1
		var xf: Transform3D = d.get_parent().global_transform * d.closed_xf   # where it is when shut (it may be open)
		var fwd: Vector3 = xf.basis.z.normalized()
		var p: Vector3 = xf.origin
		var f: Dictionary = r.find(p + fwd * 1.0, p - fwd * 1.0)
		if not f.reached or f.length > 3.0:
			out.append("door %s: not walked through on the mesh (%s, %.1f m)" % [d.name, "reached" if f.reached else "not reached", f.length])
	if n < 30:
		out.append("only %d doors checked" % n)
	return out

