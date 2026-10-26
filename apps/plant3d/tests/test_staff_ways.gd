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
## walking test climbs), except on a ladder. Until 2026-10-26 this test measured the mesh's path against the way's
## length, which was measured on that same path, while people were drawn along the straight line between the places:
## through machines and rails, floating up the HRSG's stair. 45 ways' paths were more than 10 % longer than that line,
## and nothing compared the two.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const Layout = preload("res://tests/staff_layout.gd")
const StaffWays = preload("res://app/staff_ways.gd")
const StaffPaths = preload("res://builder/staff_paths.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const PeopleView = preload("res://app/people.gd")

const ON_MESH := 0.35       # m: a place's distance to the mesh
const REACH := 8.0          # m: from a work place (at eye height) to its equipment's bounds: a thermocouple high on the exhaust duct is read from the floor below
const SAMPLE := 0.1         # m between the points of a line checked
const RADIUS := 0.3         # m: the walker's capsule (app/player.gd)
const FEET := 0.05          # m: the feet off what is under them
const LENGTH := 0.1         # a line's length off its way's, at most (and 5 cm)


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
		for w in sm.d["ways"]:
			var ia: int = sm.pix[w[0]]
			var ib: int = sm.pix[w[1]]
			var steps: int = sm.ways[mini(ia, ib) * at.size() + maxi(ia, ib)]
			var res := check_line(ways, space, skip, ia, ib, at.size(), steps * SimClock.STEP, float(w[2]))
			samples += res[1]
			for e in res[0]:
				p.append("way %s–%s: %s" % [w[0], w[1], e])
				lb += 1
			if lb > 30:
				p.append("… more")
				break
		print("staff ways: %d lines walked, %d points checked" % [ways.lines.size(), samples])
	print("staff ways: %d places, %d ways checked on the mesh" % [sm.places.size(), m.staff.d["ways"].size()])
	main.free()
	return p


## A way's line as people walk it from place `ia` to place `ib` (and back), the way taking `seconds` and being
## `metres` long: [problems, points checked].
static func check_line(ways, space: PhysicsDirectSpaceState3D, skip: Array[RID], ia: int, ib: int, places: int,
		seconds: float, metres: float) -> Array:
	var out: Array = []
	var key := mini(ia, ib) * places + maxi(ia, ib)
	if not ways.lines.has(key):
		return [["no line (built/staff_paths.bin)"], 0]
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
	var n := maxi(2, ceili(length / SAMPLE))
	var hits := {}
	var feet := {}
	var fast := 0.0
	for dir in 2:
		var from := ia if dir == 0 else ib
		for i in n + 1:
			var k := float(i) / n
			if not ways.walk(key, from, k, seconds):
				return [["walk() found no line"], 0]
			var at: Vector3 = ways.pos
			fast = maxf(fast, ways.speed)
			if dir == 1:
				continue
			q.transform = Transform3D(Basis(), at + Vector3.UP * 1.1)
			for h in space.intersect_shape(q, 4):
				var c: Node = h.collider
				var name := String(c.get_parent().name) + "/" + String(c.name) if c.get_parent() != null else String(c.name)
				if not hits.has(name):
					hits[name] = at
			if ways.on != StaffWays.ON_LADDER:
				var y: float = StaffPaths.surface(space, at, 0.3, 0.5, skip)
				var gap: float = 0.5 if is_nan(y) else at.y - y
				if absf(gap) > FEET and feet.size() < 3:
					feet[at] = gap
		# the way's two ends, as walked from either
		if dir == 1 and (not ways.walk(key, ib, 0.0, seconds) or ways.pos.distance_to(pts[pts.size() - 1 if ia == ways.lines[key][3] else 0]) > 0.01):
			out.append("walked from its other end, it does not start there")
	for name in hits:
		out.append("the capsule on its line hits %s at %s" % [name, str(hits[name])])
	for at in feet:
		out.append("the feet at %s are %.2f m %s what is under them" % [str(at), absf(feet[at]),
				"above" if feet[at] > 0.0 else "into"])
	if fast > PeopleView.RUN_FROM:
		out.append("walked at %.2f m/s somewhere (a run from %.1f m/s)" % [fast, PeopleView.RUN_FROM])
	return [out, (n + 1)]
