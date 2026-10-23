## "Go there" (ui/plant_ui.gd fly_to, stand_point) puts the trainee on a floor beside the equipment, where the
## walker fits: never inside a machine (from the condenser's pit it once landed inside the condenser's shell and the
## walker was pushed through the floor), never on a machine's or a pipe's top or on a handrail. Checked for every
## piece of equipment of the plant that has a box, from the control room's side.
extends RefCounted

const App = preload("res://tests/ui_app.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null:
		main.free()
		return ["the interaction layer did not start"]
	for i in 10:
		await tree.physics_frame
	var player = ui.player
	var start: Vector3 = player.global_position
	var n := 0
	for code in ui.index.nodes.keys():
		var b: AABB = ui.index.box(code)
		if b.size == Vector3.ZERO:
			continue
		var c := b.get_center()
		var dir := Vector3(start.x - c.x, 0, start.z - c.z)
		dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, 1)
		var to: Vector3 = ui.stand_point(b, dir)
		var hit: Dictionary = player.floor_below(to + Vector3.UP * 0.5, 1.0)
		n += 1
		if hit.is_empty():
			continue   # nowhere to stand within reach: fly_to keeps the trainee flying (and says nothing wrong)
		var col = hit.collider
		if col is Node and (col.is_in_group("equipment") or col.is_in_group("pipes")):
			p.append("%s: Go there stands the trainee on %s" % [code, col.name])
		elif not player.fits_at(to):
			p.append("%s: Go there puts the trainee inside something at %s" % [code, str(to)])
		if p.size() > 20:
			break
	if n < 300:
		p.append("only %d codes checked" % n)
	print("  stand points checked for %d codes" % n)
	main.free()
	return p
