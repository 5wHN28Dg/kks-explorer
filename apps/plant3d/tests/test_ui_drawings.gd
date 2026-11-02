## The generated P&IDs in the app (docs/plant3d/REALISM.md §6.1.1, milestone DC1): a card's Drawing button opens the
## code's home sheet with the code outlined, the 3D view off behind it; a tap on a code opens its card, on an
## off-sheet connector the other sheet at that code; the levels of detail are made when first needed and panning
## and zooming draw nothing again; a code no P&ID shows has no Drawing button; the lettering's strokes match the
## tool's measure; closing gives the view back.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const DrawingView = preload("res://ui/drawing_view.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	if ui.drawing_view == null or ui.drawings.error != "":
		main.free()
		return ["no drawings in the build: %s" % ui.drawings.error]
	var d = ui.drawings
	if d.sheets.size() != 10 or d.sheets[0]["id"] != "legend":
		p.append("the sheets: %s" % str(d.sheets.map(func(s): return s["id"])))
	if d.home_of("10LAC10AP001") != "hrsg1" or d.home_of("10BAC10") != "":
		p.append("the homes: %s, %s" % [d.home_of("10LAC10AP001"), d.home_of("10BAC10")])
	if App.find_button(ui.root, "Drawings") == null:
		p.append("no Drawings button in the bar")
	# a code a P&ID doesn't show (a breaker): no Drawing button on its card
	ui.open_card("10BAC10")
	if App.find_button(ui.card, "Drawing") != null:
		p.append("the breaker's card offers a drawing")
	# from a card to its sheet
	ui.open_card("10LAC10AP001")
	var b: Button = App.find_button(ui.card, "Drawing")
	if b == null:
		p.append("the feedwater pump's card has no Drawing button")
		main.free()
		return p
	b.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	var dv = ui.drawing_view
	if not ui.drawings_open() or dv.current != "hrsg1" or dv.selected != "10LAC10AP001":
		p.append("Drawing opened %s at %s (open %s)" % [dv.current, dv.selected, str(ui.drawings_open())])
	if not ui.get_viewport().disable_3d:
		p.append("the plant is still drawn behind the drawing")
	var r: Rect2 = dv.spot_rect("10LAC10AP001")
	var at: Vector2 = dv.to_canvas(r.get_center())
	if not Rect2(Vector2.ZERO, dv.canvas.size).has_point(at):
		p.append("the code is not in view: %s in %s" % [str(at), str(dv.canvas.size)])
	if dv.level() != 2 and dv.zoom < DrawingView.NEAR_Z * 0.8:
		p.append("the code is not shown at a reading zoom: %.2f px/mm" % dv.zoom)
	if not dv.open_ms.has("hrsg1"):
		p.append("the sheet's opening was not measured")
	# a tap on another code opens its card, the sheet stays
	var r2: Rect2 = dv.spot_rect("10LAC10AP002")
	dv.focus_code("10LAC10AP002")
	dv.tap(dv.to_canvas(r2.get_center()))
	if not ui.card.visible or ui.card.code != "10LAC10AP002" or not ui.drawings_open():
		p.append("a tap on 10LAC10AP002 opened %s" % (ui.card.code if ui.card.visible else "nothing"))
	# an instrument in its bubble
	var r3: Rect2 = dv.spot_rect("10HAD30CL001")
	dv.focus_code("10HAD30CL001")
	dv.tap(dv.to_canvas(r3.get_center()))
	if ui.card.code != "10HAD30CL001":
		p.append("a tap on the drum level's bubble opened %s" % ui.card.code)
	# an off-sheet connector opens the other sheet at its code
	var link: Array = []
	for l in d.sheet("hrsg1")["links"]:
		if l[0] == "st" and l[1] == "30MAA10":
			link = l
	if link.is_empty():
		p.append("no connector from the HRSG's sheet to the HP turbine")
	else:
		dv.fit()
		var lc: Vector2 = dv.to_canvas(Vector2((link[2] + link[4]) * 0.5, (link[3] + link[5]) * 0.5))
		dv.tap(lc)
		if dv.current != "st" or dv.selected != "30MAA10":
			p.append("the connector opened %s at %s" % [dv.current, dv.selected])
	# levels of detail: the far one at the whole sheet, the near one zoomed in; panning and zooming record nothing again
	dv.fit()
	await tree.process_frame
	if dv.level() != 0:
		p.append("the whole sheet is not drawn at the far level: %.2f px/mm" % dv.zoom)
	dv.zoom_by(20.0)
	await tree.process_frame
	if dv.level() != 2 or not dv.levels_made("st")[2] or not dv.levels_made("st")[0]:
		p.append("levels made: %s at %.2f px/mm" % [str(dv.levels_made("st")), dv.zoom])
	var node: Node2D = dv._lods["st"][2]
	var drawn := [0]
	node.draw.connect(func(): drawn[0] += 1)
	for i in 5:
		dv.pan(Vector2(30, 10))
		dv.zoom_by(1.05)
		await tree.process_frame
	if drawn[0] != 0:
		p.append("panning and zooming drew the sheet again %d times" % drawn[0])
	# the lettering as the tool measures it (pid_font.width): ABC at 6 mm is 14 mm long; upright text reads upwards
	var pts := PackedVector2Array()
	dv._text(pts, [0.0, 0.0, 6.0, 0, 0, "ABC"])
	var xmax := -INF
	for q in pts:
		xmax = maxf(xmax, q.x)
	if absf(xmax - 14.0) > 0.01:
		p.append("the lettering's length: %.2f, not 14" % xmax)
	var up := PackedVector2Array()
	dv._text(up, [10.0, 50.0, 6.0, 90, 0, "AB"])
	var ymin := INF
	for q in up:
		ymin = minf(ymin, q.y)
	if absf(ymin - (50.0 - 9.0)) > 0.01:
		p.append("upright text does not read upwards: %.2f" % ymin)
	# sheets kept drawn: at most KEEP
	for s in d.sheets:
		dv.open_sheet(String(s["id"]))
	if dv._lods.size() > DrawingView.KEEP:
		p.append("%d sheets kept drawn" % dv._lods.size())
	# Esc closes the card first, then the drawings; the view comes back
	while ui.close_top():
		pass
	if ui.drawings_open() or ui.get_viewport().disable_3d:
		p.append("closing left the drawings open or the plant undrawn")
	main.free()
	return p
