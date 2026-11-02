## The camp's people in the app (docs/PLANT3D.md §21.7, milestone S4): at the shift's start (05:00) the off-duty
## crews are at home in the camp, many asleep behind their rooms' shut doors: a person at a hidden place is drawn by
## nobody (no marker, no avatar), and so is a person standing in an interior that is not loaded (§18.5, §21.7);
## everyone else on site or in the camp is.
extends RefCounted

const App = preload("res://tests/ui_app.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	ui.start_shift("shift_cold")
	await tree.process_frame
	var e = ui.clock.engine
	var sm = e._sm
	if sm == null or not sm.has_homes:
		main.free()
		return ["the first train's staff have no homes (PLANT3D §21.1)"]
	ui.people.update()              # (the places read)
	var hidden := 0
	var drawn := 0
	for pi in sm.people.size():
		if pi == ui.my_person():
			continue
		var at: int = e.sp_pos[pi]
		if at != -1 and sm.places[at].get("hidden", false) == true:
			hidden += 1
		elif (at != -1 and ui.people._shown(at)) or (at == -1 and not e.sp_leg[pi].is_empty()):
			drawn += 1
	if hidden == 0:
		p.append("nobody is asleep behind a shut door at 05:00 (the off-duty crews at home)")
	ui.people.update()
	if ui.people.shown != drawn:
		p.append("%d people drawn on the map, %d not at a hidden place (%d at one)" % [ui.people.shown, drawn, hidden])
	for x in ui.people.dot_at:
		for pi in sm.people.size():
			var at: int = e.sp_pos[pi]
			if at != -1 and sm.places[at].get("hidden", false) == true \
					and (x as Vector3).distance_to(ui.people._at[at]) < 0.01:
				p.append("a person at a hidden place is drawn (%s)" % sm.people[pi]["id"])
				break
	# people at a place inside an interior that is not loaded (the mess hall's seats, block 1's rooms) are drawn by
	# nobody; with the interiors loaded, they are
	var ints = main.interiors
	var inside := 0
	for pi in sm.people.size():
		if pi == ui.my_person():
			continue
		var at: int = e.sp_pos[pi]
		if at == -1 or sm.places[at].get("hidden", false) == true:
			continue
		var q: Vector3 = ui.people._at[at]
		for id in ints.items:
			if not ints.loaded(id) and (ints.items[id].rect as Rect2).has_point(Vector2(q.x, -q.z)):
				inside += 1
				for x in ui.people.dot_at:
					if (x as Vector3).distance_to(q) < 0.01:
						p.append("a person in an interior not loaded is drawn (%s, %s)" % [sm.people[pi]["id"], id])
	if inside == 0:
		p.append("nobody stands in an interior that is not loaded at 05:00 (the mess hall, block 1's rooms)")
	ints.load_all()
	var before: int = ui.people.shown
	ui.people.update()
	if ui.people.shown != before + inside:
		p.append("with the interiors loaded, %d people are drawn, not %d" % [ui.people.shown, before + inside])
	main.free()
	return p
