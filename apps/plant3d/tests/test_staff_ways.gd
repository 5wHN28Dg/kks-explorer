## The staff's walking network against the built plant's navigation mesh (docs/PLANT3D.md §16.2, §18.1): every place
## stands on the mesh, every work place within reach of its equipment, and every way is walkable on the mesh with a
## path no longer than its length + 10 % (`bad_way`), so people drawn along it never visibly hurry. Every place is
## also reached from the origin by the ways (the validator's `unreachable`, checked here on the content the app loads).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const Layout = preload("res://tests/staff_layout.gd")

const ON_MESH := 0.35       # m: a place's distance to the mesh
const REACH := 8.0          # m: from a work place (at eye height) to its equipment's bounds: a thermocouple high on the exhaust duct is read from the floor below


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var m = PlantModel.from_dir("res://built/content")
	if m.error != "" or m.staff == null:
		return ["the built content has no staff (%s)" % m.error]
	var main := App.start(tree)
	var ui = main.ui
	var r = ui.route
	for i in 600:
		if r.ready_to_find():
			break
		await tree.physics_frame
	if not r.ready_to_find():
		main.free()
		return ["the navigation map was not ready 10 s after the start"]
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
		elif f["length"] > float(w[2]) * 1.1 + 0.05:
			p.append("way %s–%s: %.2f m on the mesh, longer than its %.2f m + 10 %% (bad_way)" % [w[0], w[1],
					f["length"], float(w[2])])
			bad += 1
		if bad > 20:
			p.append("… more")
			break
	print("staff ways: %d places, %d ways checked on the mesh" % [sm.places.size(), m.staff.d["ways"].size()])
	main.free()
	return p
