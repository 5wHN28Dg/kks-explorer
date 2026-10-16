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
	_cuts()
	return problems

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
