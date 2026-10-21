## The content build's geometry and its refusals (decision 0054 §10: "the build's own refusals"), on small synthetic
## plants: a region with holes is cut into pieces of the right area; a stair's layout follows the step rules and
## its path climbs flight by flight to the top; the build refuses a door in a wall without a door opening, a pipe
## through a wall without an opening and a pipe through a stair's walking space, and accepts them when fixed;
## a platform a stair or a ladder passes through gets its stairwell or hatch.
extends RefCounted

const Geom = preload("res://builder/geom.gd")
const Builder = preload("res://builder/plant_builder.gd")

var problems: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		problems.append(what)

func run(_tree: SceneTree) -> Array:
	_decompose()
	_stairs()
	_refusals()
	_headroom()
	_cuts()
	_hall_floor()
	_lamp_floor()
	_crane()
	return problems

## An overhead crane whose trolley would reach into the roof's trusses is refused (the gas turbine hall's first rail
## height put it 0.75 m into them: photo pass); one that clears them is accepted, the hall gets its frame's runway.
func _crane() -> void:
	var ell := PackedVector2Array([Vector2(0, 0), Vector2(80, 0), Vector2(80, 30), Vector2(40, 30), Vector2(40, 50), Vector2(0, 50)])
	# [hall height, rail, outline, cladding, the error expected ("" none)]
	for c in [[32.0, 26.0, Geom.rect(0, 0, 80, 50), "metal", ""], [32.0, 26.0, Geom.rect(0, 0, 80, 30), "metal", ""],
			[20.0, 16.0, Geom.rect(0, 0, 80, 30), "metal", "crane_clash"], [20.0, 14.5, Geom.rect(0, 0, 80, 30), "metal", ""],
			[20.0, 14.5, Geom.rect(0, 0, 80, 30), "concrete", "crane_unsupported"],
			[20.0, 4.0, Geom.rect(0, 0, 80, 30), "metal", "crane_unsupported"],
			[20.0, 14.5, ell, "metal", "crane_unsupported"]]:
		var b := Builder.new()
		var body := Node3D.new()
		var frame := SurfaceTool.new()
		frame.begin(Mesh.PRIMITIVE_TRIANGLES)
		b._crane(body, frame, {"id": "hall", "outline": c[2], "height": c[0], "crane": c[1], "cladding": c[3]})
		var got := ""
		for e in b.errors:
			got = String(e).get_slice(" ", 0)
		check(got == c[4], "a crane on its rail at %.1f m in a %s hall %.0f m high (%d corners): %s, not %s" % [c[1], c[3], c[0], c[2].size(), c[4] if c[4] != "" else "accepted", got if got != "" else "accepted"])
		check((body.get_node_or_null("crane") != null) == (c[4] != "crane_unsupported"), "the crane is drawn where it runs")
		body.free()
	# columns step aside from openings at any height (a pipe's way 7 to 11 m up, a window), none where there is no room
	check(is_equal_approx(Builder.column_place(10.0, 50.0, []), 10.0), "a column where it is wanted when nothing is in the way")
	var t := Builder.column_place(25.0, 50.0, [[18.0, 32.0, 7.0, 11.0]])
	check(t < 0.0, "no column inside a 14 m pipe opening (got %.2f)" % t)
	t = Builder.column_place(25.0, 50.0, [[23.0, 27.0, 23.0, 25.0]])
	check(t > 0.0 and (t < 23.0 - 0.34 or t > 27.0 + 0.34), "a column beside a 4 m window (got %.2f)" % t)

func _decompose() -> void:
	var sq := Geom.rect(0, 0, 10, 10)
	check(absf(Geom.area(Geom.decompose(sq, [])) - 100.0) < 1e-6, "a 10 m square is 100 m²")
	check(absf(Geom.area(Geom.decompose(sq, [Geom.rect(2, 2, 4, 4)])) - 96.0) < 1e-6, "a square less a 2 m hole is 96 m²")
	# overlapping holes, and a hole reaching outside the outline
	var a := Geom.area(Geom.decompose(sq, [Geom.rect(2, 2, 6, 6), Geom.rect(4, 4, 8, 8), Geom.rect(9, -1, 11, 1)]))
	check(absf(a - (100.0 - 28.0 - 1.0)) < 1e-6, "overlapping holes are cut once (got %.3f m²)" % a)
	var tri := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(0, 10)])
	check(absf(Geom.area(Geom.decompose(tri, [])) - 50.0) < 1e-6, "a triangle")

func _stairs() -> void:
	for c in [[Vector3(3, 12, 0), Vector3(10, 16, 12), "switchback", 1.2], [Vector3(95, 46, 0), Vector3(102, 50, 30), "switchback", 1.2],
			[Vector3(57, 3.5, -6), Vector3(57, 12.16, 0), "straight", 1.0]]:
		var st := Geom.stair_steps(c[0], c[1], c[2], c[3])
		check(not st.is_empty(), "the stair %s fits the rules" % str(c))
		if st.is_empty():
			continue
		check(st.rise >= 0.15 and st.rise <= 0.20 and st.going >= 0.25, "rise and going within the rules")
		var lay := Geom.stair_layout(c[0], c[1], c[2], c[3], st)
		check(lay.flights.size() == st.flights, "one flight per 3.6 m")
		var path: Array = lay.path
		check(path[0] == c[0] and path[-1] == c[1], "the path runs from the foot to the top")
		var ok := true
		for i in range(1, path.size()):
			if path[i].z < path[i - 1].z - 1e-6:
				ok = false
		check(ok, "the path never goes down on the way up (%s)" % str(c))
		for fl in lay.flights:
			var slope: float = (fl.z1 - fl.z0) / fl.a.distance_to(fl.b)
			check(slope > 0.3 and slope < 0.9, "a flight is walkable as a slope (%.2f)" % slope)
	check(Geom.stair_steps(Vector3(0, 0, 0), Vector3(1, 0, 5), "straight", 1.0).is_empty(), "a stair too steep is refused")

## A hall's painted floor leaves a pit inside it open and refuses one across its wall (drawn over it, the floor would
## cover the opening); a pit inside an L-shaped hall's box but outside the hall is no hole of its (second realism pass).
func _hall_floor() -> void:
	var cases := [
		[Geom.rect(0, 0, 10, 10), Geom.rect(2, 2, 4, 4), 96.0, false, "a pit inside the hall"],
		[Geom.rect(0, 0, 10, 10), Geom.rect(8, 2, 12, 4), 0.0, true, "a pit across the hall's wall"],
		[PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 4), Vector2(4, 4), Vector2(4, 10), Vector2(0, 10)]),
			Geom.rect(6, 6, 8, 8), 64.0, false, "a pit in an L-shaped hall's box, outside the hall"],
	]
	for c in cases:
		var b := Builder.new()
		b.pits = [{"id": "pit", "outline": c[1]}]
		var body := Node3D.new()
		b._hall_floor(body, {"id": "hall", "outline": c[0]})
		var refused := false
		for e in b.errors:
			refused = refused or String(e).begins_with("pit_across_hall")
		check(refused == c[3], "%s: %s" % [c[4], "refused" if c[3] else "accepted"])
		if not c[3]:
			var fl := body.get_node_or_null("floor") as MeshInstance3D
			var area := 0.0
			if fl != null:
				var v: PackedVector3Array = fl.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var ix: PackedInt32Array = fl.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				for t in range(0, ix.size(), 3):
					var n := (v[ix[t + 1]] - v[ix[t]]).cross(v[ix[t + 2]] - v[ix[t]])
					if n.normalized().y > 0.99:
						area += n.length() / 2.0
			check(absf(area - c[2]) < 0.01, "%s: the floor is %.1f m², not %.1f" % [c[4], area, c[2]])
		body.free()

## A hall's lamp is set from its height over the floor under it: a deck's where there is one (from the ground, the
## turbine hall's 12 m deck got 2.6 × the light meant on it: adversarial review, second realism pass).
func _lamp_floor() -> void:
	var b := Builder.new()
	b.surfaces = [{"id": "deck", "z": 12.0, "outline": Geom.rect(0, 0, 10, 10), "holes": [Geom.rect(4, 4, 6, 6)]},
		{"id": "pit", "z": -4.0, "outline": Geom.rect(20, 0, 30, 10), "holes": []},
		{"id": "high", "z": 18.0, "outline": Geom.rect(0, 0, 10, 10), "holes": []}]
	check(is_equal_approx(b.floor_below(Vector2(2, 2), 19.0), 12.0), "a lamp over a deck: the deck's floor (1.0 m above the top deck counts nothing)")
	check(is_equal_approx(b.floor_below(Vector2(5, 5), 19.0), 0.0), "a lamp over a deck's opening: the ground")
	check(is_equal_approx(b.floor_below(Vector2(25, 5), 19.0), 0.0), "a lamp over a pit: the ground (the pit has its own lamps)")
	check(is_equal_approx(b.floor_below(Vector2(2, 2), 25.0), 18.0), "the highest floor under the lamp")
	# a lamp right over a deck's edge is set for the deck (the edge's point counted as off the deck on one side)
	check(is_equal_approx(b.lamp_floor(Vector2(10, 2), 15.0), 12.0), "a lamp over a deck's edge: the deck's floor")
	check(is_equal_approx(b.lamp_floor(Vector2(0, 2), 15.0), 12.0), "a lamp over a deck's other edge: the deck's floor")
	check(is_equal_approx(b.lamp_floor(Vector2(12, 2), 15.0), 0.0), "a lamp clear of the deck: the ground")
	# a wall piece's streaks start at the opening above it, else at the wall's top
	var cuts := [[2.0, 4.0, 1.0, 3.0]]
	check(is_equal_approx(Builder.piece_top(Rect2(2, 0, 2, 1), cuts, 10.0), 1.0), "a piece under an opening: its bottom")
	check(is_equal_approx(Builder.piece_top(Rect2(0, 0, 2, 3), cuts, 10.0), 10.0), "a piece beside an opening: the wall's top")
	check(is_equal_approx(Builder.piece_top(Rect2(0, 3, 10, 7), cuts, 10.0), 10.0), "the piece over the openings: the wall's top")
	check(is_equal_approx(Builder.piece_top(Rect2(0, 0, 10, 1), cuts, 10.0), 1.0), "a slab under an opening: the opening's bottom")

## A synthetic plant: one area with a building (door and pipe openings), a door, a pump, a pipe and a stair.
func _plant(door_open: bool, pipe_open: bool, pipe_over_stair: bool) -> Builder:
	var kit = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/kit.json")))
	var openings: Array = []
	if door_open:
		openings.append({"kind": "door", "at": [10, 0, 0], "width": 1.2, "height": 2.4})
	if pipe_open:
		openings.append({"kind": "pipe", "at": [20, 2, 3], "width": 1, "height": 1})
	var pts := [[16, 2, 3], [25, 2, 3]] if not pipe_over_stair else [[16, 2, 3], [16, 33, 3], [16, 36.5, 3]]
	var area := {"id": "a1", "bounds": [[0, 0], [40, 40]], "pack": "base",
		"equipment": [{"kks": "10PAC10AP001", "part": "pump_horizontal", "at": [16, 5, 0], "yaw": 0, "params": {}},
			{"kks": "10PAC20AP001", "part": "pump_horizontal", "at": [16, 38, 0], "yaw": 180, "params": {}}],
		"pipes": [{"kks": "10PAC10BR001", "medium": "water", "dn": 100, "from": {"kks": "10PAC10AP001", "nozzle": "discharge"},
			"points": pts, "to": {"at": [25, 2, 0]} if not pipe_over_stair else {"kks": "10PAC20AP001", "nozzle": "discharge"}}],
		"structures": [
			{"id": "b1", "part": "building", "at": [0, 0, 0], "params": {"outline": [[0, 0], [20, 0], [20, 20], [0, 20]], "height": 8, "openings": openings}},
			{"id": "d1", "part": "door", "at": [10, 0, 0], "yaw": 180, "params": {"kind": "personnel", "width": 1.0}},
			{"id": "p1", "part": "platform", "at": [10, 25, 6], "params": {"outline": [[0, 0], [12, 0], [12, 10], [0, 10]]}},
			{"id": "s1", "part": "stair", "params": {"foot": [14, 30, 0], "top": [21, 34, 6], "layout": "switchback", "width": 1.2}}]}
	var b := Builder.new()
	b.use({"title": "t", "areas": ["a1"], "start": {"at": [1, 1, 0], "yaw": 0}, "media": {"water": {"group": "water", "band": "#2e7d32"}}}, kit, [area])
	b.collect()
	return b

func _refusals() -> void:
	var good := _plant(true, true, false)
	check(good.errors.is_empty(), "a plant with its openings builds: %s" % str(good.errors))
	var b := _plant(false, true, false)
	check(b.errors.size() == 1 and "d1" in b.errors[0] and b.errors[0].begins_with("unsupported"), "a door without an opening is refused: %s" % str(b.errors))
	b = _plant(true, false, false)
	check(b.errors.size() == 1 and "10PAC10BR001" in b.errors[0] and "wall of b1" in b.errors[0], "a pipe through a wall without an opening is refused: %s" % str(b.errors))
	b = _plant(true, true, true)
	var hit := false
	for e in b.errors:
		if "walking space of s1" in e:
			hit = true
	check(hit, "a pipe through a stair's walking space is refused: %s" % str(b.errors))

func _headroom() -> void:
	var b := _plant(true, true, false)
	b.stairs.clear()
	b.errors.clear()
	var foot := Vector3(14, 30, 0)
	var top := Vector3(19.1, 34, 4)
	var st := Geom.stair_steps(foot, top, "switchback", 1.2)
	check(not st.is_empty() and st.flights == 2, "a 4 m switchback in two flights keeps the step rules")
	b.stairs.append({"id": "low", "area": "a1", "foot": foot, "top": top, "layout": "switchback", "width": 1.2, "st": st,
		"lay": Geom.stair_layout(foot, top, "switchback", 1.2, st)})
	b._check()
	var hit := false
	for e in b.errors:
		if "low" in e and "headroom" in e:
			hit = true
	check(hit, "two 2 m flights leave no headroom under the first landing: refused (%s)" % str(b.errors))

func _cuts() -> void:
	var b := _plant(true, true, false)
	var p1: Dictionary = {}
	for sf in b.surfaces:
		if sf.id == "p1":
			p1 = sf
	check(not p1.is_empty() and p1.holes.size() > 0, "the platform the stair reaches gets a stairwell")
	if p1.is_empty():
		return
	# the stair's top landing joins the platform: walkable at +6 there, and over the flights it is not
	var top: Vector3 = b.stairs[0].lay.path[-1]
	check(b.walkable_at(Vector2(top.x - 0.3, top.y - 0.3), 6.0), "the top landing is walkable")
	var fl: Dictionary = b.stairs[0].lay.flights[0]
	var mid: Vector2 = (fl.a + fl.b) * 0.5
	check(not Geom.in_region(mid, p1.outline, p1.holes), "the platform is open over the flights")
