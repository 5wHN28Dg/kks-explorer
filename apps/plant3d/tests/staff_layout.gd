## The staff's places and ways measured on the built plant's navigation mesh (docs/PLANT3D.md §16.2, §18.1; decision
## 0059), for the content tool (tools/plant3d/train_staff.py): where a person stands to work on each piece of
## equipment (the walkable point nearest to its bounds, as the app's walking directions end a route), and how long the
## walk is between places. Not a test: run by the content tool's maintainer after the layout changes.
##   godot --headless --path apps/plant3d --script res://tests/staff_layout.gd -- --in=REQUESTS --out=LAYOUT
## REQUESTS (JSON): {"codes": [code…], "places": {id: [x, y, z]}, "points": [id…], "edges": [[id, id]…], "k": n}
## (plant coordinates: x east, y north, z up; "places" holds the points too). LAYOUT (JSON):
##   {"stand": {code: [x, y, z]}, "on_mesh": {id: metres off the mesh}, "stubs": {id: [[point id, metres, rise]…]},
##    "edges": {"a|b": [metres, rise, reached]}}
## Every non-point place (and every code's stand point, as "kks:CODE") is measured to its k nearest points (straight
## line), every edge as asked; metres are the way along the mesh (stairs and ladders along their own paths), rise the
## height climbed and come down.
extends SceneTree

const App = preload("res://tests/ui_app.gd")


func _init() -> void:
	_run.call_deferred()


static func plant_of(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(-v.z, 0.01), snappedf(v.y, 0.01)]


static func godot_of(p: Array) -> Vector3:
	return Vector3(p[0], p[2], -p[1])


func _run() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var req = JSON.parse_string(FileAccess.get_file_as_string(opts.get("in", "")))
	if typeof(req) != TYPE_DICTIONARY:
		print("staff_layout: no requests (--in=PATH)")
		quit(2)
		return
	var main := App.start(self)
	var ui = main.ui
	var r = ui.route
	for i in 600:
		if r.ready_to_find():
			break
		await physics_frame
	if not r.ready_to_find():
		print("staff_layout: the navigation map was not ready")
		quit(1)
		return
	var out := {"stand": {}, "on_mesh": {}, "stubs": {}, "edges": {}}
	var places: Dictionary = req["places"].duplicate()
	for code in req["codes"]:
		if not ui.index.has(code):
			print("staff_layout: no equipment %s in the scene" % code)
			continue
		var p: Vector3 = r.point_for(ui.index.box(code))
		out["stand"][code] = plant_of(p)
		places["kks:" + code] = plant_of(p)
	var pts: Array = req["points"]
	var k: int = int(req.get("k", 3))
	for id in places:
		var g := godot_of(places[id])
		var c: Vector3 = NavigationServer3D.map_get_closest_point(r.map, g)
		out["on_mesh"][id] = snappedf(c.distance_to(g), 0.001)
		if pts.has(id):
			continue
		var near := []
		for q in pts:
			near.append([g.distance_to(godot_of(places[q])), q])
		near.sort_custom(func(a, b): return a[0] < b[0])
		var res := []
		for j in mini(k, near.size()):
			var q: String = near[j][1]
			var f: Dictionary = r.find(g, godot_of(places[q]))
			if f["reached"]:
				res.append([q, snappedf(f["length"], 0.01), snappedf(_rise(f["points"]), 0.01)])
		out["stubs"][id] = res
	for e in req["edges"]:
		var f: Dictionary = r.find(godot_of(places[e[0]]), godot_of(places[e[1]]))
		out["edges"]["%s|%s" % [e[0], e[1]]] = [snappedf(f["length"], 0.01), snappedf(_rise(f["points"]), 0.01),
				f["reached"]]
	var fo := FileAccess.open(opts.get("out", "user://staff_layout.json"), FileAccess.WRITE)
	fo.store_string(JSON.stringify(out, " ", true))
	fo.close()
	print("staff_layout: %d stand points, %d stubs, %d edges" % [out["stand"].size(), out["stubs"].size(),
			out["edges"].size()])
	main.free()
	quit(0)


static func _rise(points: PackedVector3Array) -> float:
	var s := 0.0
	for i in range(1, points.size()):
		s += absf(points[i].y - points[i - 1].y)
	return s
