## The start's warm-up (app/warmup.gd): every area of the built plant is drawn once before the first walkable frame,
## from points on a grid over it looking four ways, into viewports of the plant's own world that are gone afterwards;
## the app's start runs it on a display unless `fx_off=warmup`.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Warmup = preload("res://app/warmup.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = []
	var plant: Node3D = Plant.new()
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return ["the built plant loads: " + err]
	var pts: Array = Warmup.points_for(plant.manifest)
	# every area has points inside it, none further than STEP from any of its corners' grid cell
	for a in plant.manifest.areas:
		var b: Array = a.bounds
		var inside := 0
		for q: Vector3 in pts:
			if q.x >= b[0][0] and q.x <= b[1][0] and -q.z >= b[0][1] and -q.z <= b[1][1]:
				inside += 1
				if absf(q.y - Warmup.EYE) > 1e-4:
					p.append("a warm-up point stands at eye height (%s)" % q)
					break
		var need := maxi(1, ceili((b[1][0] - b[0][0]) / Warmup.STEP)) * maxi(1, ceili((b[1][1] - b[0][1]) / Warmup.STEP))
		if inside < need:
			p.append("area %s has %d warm-up points, at least %d (one per %d m square)" % [a.id, inside, need, int(Warmup.STEP)])
	var w = Warmup.new()
	tree.root.add_child(w)
	var vp := tree.root.get_viewport()
	var seen := {"viewports": 0, "shared": true, "cams": 0}
	var watch := func():
		var n := 0
		for c in w.get_children():
			if c is SubViewport:
				n += 1
				seen.shared = seen.shared and (c as SubViewport).find_world_3d() == vp.find_world_3d()
				if (c as SubViewport).get_camera_3d() != null:
					seen.cams += 1
		seen.viewports = maxi(seen.viewports, n)
	tree.process_frame.connect(watch)
	var finished := {"done": false}
	w.done.connect(func(): finished.done = true)
	w.run(plant.manifest, vp, Vector2i(64, 64))
	for i in pts.size() + 10:
		await tree.process_frame
		if finished.done:
			break
	tree.process_frame.disconnect(watch)
	if not finished.done or w.drawn != pts.size():
		p.append("the warm-up draws every point (%d of %d)" % [w.drawn, pts.size()])
	if seen.viewports != 4:
		p.append("the warm-up looks four ways at once (%d viewports)" % seen.viewports)
	if not seen.shared:
		p.append("the warm-up's viewports draw the plant's own world")
	if seen.cams == 0:
		p.append("the warm-up's viewports have their cameras")
	await tree.process_frame
	for c in w.get_children():
		if c is SubViewport and not c.is_queued_for_deletion():
			p.append("the warm-up's viewports are gone afterwards")
			break
	w.free()
	plant.free()
	# the start runs it with a display, before the first walkable frame (headless: nothing is drawn, so not there)
	var src := FileAccess.get_file_as_string("res://app/main.gd")
	var at_warm := src.find("await _warm_up()")
	if at_warm < 0 or at_warm > src.find("\t_first_frame()") or not src.contains("\"warmup\" in Lighting.off"):
		p.append("the start warms up before its first walkable frame, unless fx_off=warmup")
	return p
