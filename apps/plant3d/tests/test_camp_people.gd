## The camp's people in the app (docs/PLANT3D.md §21.7, milestone S4): at the shift's start (05:00) the off-duty
## crews are at home in the camp, many asleep behind their rooms' shut doors: a person at a hidden place is drawn by
## nobody (no marker, no avatar), everyone else on site or in the camp is.
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
	var hidden := 0
	var drawn := 0
	for pi in sm.people.size():
		if pi == ui.my_person():
			continue
		var at: int = e.sp_pos[pi]
		if at != -1 and sm.places[at].get("hidden", false) == true:
			hidden += 1
		elif at != -1 or not e.sp_leg[pi].is_empty():
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
	main.free()
	return p
