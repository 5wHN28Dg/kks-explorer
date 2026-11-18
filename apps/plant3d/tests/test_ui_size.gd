## The settings' UI size (issue #382; UI-UX-POLICY T1, S1, S2, R1, L2): 100 % to 150 %, a phone at 150 % by default.
## At both ends, on a desktop's 1600 × 900 canvas and on the Note 9's (2220 × 1080 at the phone's UI scale, a
## 1850 × 900 canvas), the HUD's buttons, the layer's bar and its clock are all on screen and overlap nothing; every
## panel opened lies inside the canvas below the bars with its Close (or Back) on screen, and nothing in it runs out at
## its sides; at the phone's 150 % its buttons are 48 dp tall at least and its text 14 sp. The size is chosen in the
## settings, applied at once (the panel open stays inside the smaller canvas) and kept in the settings file.
extends RefCounted

const W = preload("res://ui/widgets.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const UiApp = preload("res://tests/ui_app.gd")
const Quality = preload("res://app/quality.gd")

const DP := 0.457             # dp per canvas px on the Note 9 (docs/UI-UX-POLICY.md §2, units)
const CLOSERS := ["Close", "Back", "Leave", "Done"]


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var size0: Vector2i = tree.root.size
	for c in [[Vector2i(1600, 900), "", 1.0], [Vector2i(1600, 900), "", 1.5],
			[Vector2i(2220, 1080), "1.35", 1.0], [Vector2i(2220, 1080), "1.35", 1.5]]:
		tree.root.size = c[0]
		p += await _at(tree, c[1], c[2])
	tree.root.size = size0
	p += await _setting(tree)
	if tree.root.content_scale_factor != 1.0:
		p.append("the window's content scale is %.2f after the app left (1 expected)" % tree.root.content_scale_factor)
		tree.root.content_scale_factor = 1.0
	return p


func _start(tree: SceneTree, ui_scale: String, ui_size) -> Node:
	RunSave.remove(Autosave.default_path)
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["scenario"] = "shift_aged"          # (the crews' and the work orders' panels have something to show)
	if ui_scale != "":
		main.opts["ui_scale"] = ui_scale
	if ui_size != null:
		main.opts["ui_size"] = str(ui_size)
	tree.root.add_child(main)
	if main.ui != null and main.ui.clock != null:
		main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	return main


func _at(tree: SceneTree, ui_scale: String, ui_size: float) -> Array:
	var p: Array = []
	var at := "%s at %d %%" % ["the phone" if ui_scale != "" else "a desktop", roundi(ui_size * 100.0)]
	var main := _start(tree, ui_scale, ui_size)
	for i in 6:
		await tree.process_frame
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["%s: the app did not start" % at]
	var canvas: Rect2 = ui.root.get_viewport_rect()
	var want: Vector2 = Vector2(tree.root.size) * (1600.0 if ui_scale == "" else 1850.0) / float(tree.root.size.x) / ui_size
	if (canvas.size - want).length() > 2.0:
		p.append("%s: the canvas is %s, %s expected" % [at, str(canvas.size), str(want)])
	p += _bars(main, at, canvas, ui_scale != "" and ui_size >= 1.5, ui_size)
	if ui_scale == "" and ui_size == 1.0:
		# a desktop at 100 % as before: the bar one row at 88 px, the panels from 160 px, with Instructor on too
		ui.set_instructor(true)
		for i in 3:
			await tree.process_frame
		if absf(ui.bar.get_global_rect().position.y - 88.0) > 0.5 or absf(ui.panels_top() - 160.0) > 0.5:
			p.append("%s: the bar is at %.0f and the panels begin at %.0f with Instructor on (88 and 160 before)" % [at,
				ui.bar.get_global_rect().position.y, ui.panels_top()])
		ui.set_instructor(false)
	for pn in _panels():
		await _open(tree, main, pn)
		for i in 3:
			await tree.process_frame
		p += _check_panel(main, pn, at, canvas, ui_scale != "" and ui_size >= 1.5, ui_size)
		_close(main, pn)
		await tree.process_frame
	p += await _workshop(tree, main, at, ui_size)
	main.free()
	await tree.process_frame
	return p


## The Workshop at the UI size: its way back on screen, and its 3D view drawn with as many pixels as at 100 % (its
## resolution scaled up as the canvas's units grow). (Its panels' own layout: tests/test_workshop_layout.gd.)
func _workshop(tree: SceneTree, main, at: String, ui_size: float) -> Array:
	var p: Array = []
	var ws = main.workshop
	if ws == null or ws.kinds().is_empty():
		return ["%s: no Workshop" % at]
	if not ws.open(ws.kinds()[0]):
		return ["%s: the Workshop did not open" % at]
	for i in 4:
		await tree.process_frame
	var canvas: Rect2 = ws.container.get_viewport_rect()
	var back: Button = ws.panels.back_btn
	if back == null or not back.is_visible_in_tree() or not canvas.grow(0.5).encloses(back.get_global_rect()):
		p.append("%s: the Workshop's Back to the plant is not on screen: %s" % [at, str(back.get_global_rect()) if back else "none"])
	# the pixels it draws across: its size in the canvas's units times its scale, as at 100 % (the canvas's width in
	# the window's pixels times the plant's scale)
	var px: float = ws.vp.size.x * ws.vp.scaling_3d_scale
	var want: float = canvas.size.x * ui_size * main.get_viewport().scaling_3d_scale
	if absf(px - want) > 2.0:
		p.append("%s: the Workshop's view is drawn %.0f px across, %.0f expected (as many as at 100 %%)" % [at, px, want])
	ws.close()
	await tree.process_frame
	return p


## The HUD's buttons, its status line, the layer's bar and clock: on screen, apart, and (the phone at 150 %) 48 dp.
func _bars(main, at: String, canvas: Rect2, phone: bool, ui_size: float) -> Array:
	var p: Array = []
	var hud = main.hud
	var ui = main.ui
	var rects := {}
	for b in hud.bar.get_children() + ui.bar.get_children():
		if not (b as Control).is_visible_in_tree():
			continue
		var r: Rect2 = (b as Control).get_global_rect()
		if not canvas.grow(0.5).encloses(r):
			p.append("%s: the bar's %s is off screen: %s in %s" % [at, _name(b), str(r), str(canvas.size)])
		for o in rects:
			if rects[o].intersects(r):
				p.append("%s: the bar's %s overlaps %s" % [at, _name(b), o])
		rects[_name(b)] = r
		if phone and b is BaseButton and r.size.y * ui_size * DP < 47.5:
			p.append("%s: the bar's %s is %.1f dp tall (48 the least)" % [at, _name(b), r.size.y * ui_size * DP])
	# the touch sticks keep a thumb's size on the screen (420 px of the canvas at every UI size), in their corners
	for st in hud.sticks:
		var r: Rect2 = (st as Control).get_global_rect()
		if absf(r.size.x * ui_size - 420.0) > 1.0 or not canvas.grow(0.5).encloses(r):
			p.append("%s: the %s is %s (420 px of the screen's canvas, in its corner, expected)" % [at, st.name, str(r)])
	var sr: Rect2 = hud.top_box.get_global_rect()
	sr.size.y = hud.top_box.get_combined_minimum_size().y
	for o in rects:
		if rects[o].intersects(sr):
			p.append("%s: the status line %s overlaps the bar's %s %s" % [at, str(sr), o, str(rects[o])])
	if not canvas.grow(0.5).encloses(sr):
		p.append("%s: the status line is off screen: %s" % [at, str(sr)])
	# the clock shows its whole text: as wide as the longest it can say, and on screen (it was cut at the left)
	var clock: Label = ui._time
	var f: Font = clock.get_theme_font("font")
	var fs: int = clock.get_theme_font_size("font_size")
	for t in ["Day 999 Wed 23:59 paused", clock.text]:
		var tw: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if clock.size.x + 0.5 < tw:
			p.append("%s: the clock is %.0f px wide, its text \"%s\" %.0f" % [at, clock.size.x, t, tw])
	if not canvas.grow(0.5).encloses(clock.get_global_rect()):
		p.append("%s: the clock is off screen: %s" % [at, str(clock.get_global_rect())])
	if ui.panels_top() < ui.bar.get_global_rect().end.y:
		p.append("%s: the panels begin at %.0f, over the bar (it ends at %.0f)" % [at, ui.panels_top(),
			ui.bar.get_global_rect().end.y])
	if phone:
		var sp: float = float(ui.root.theme.default_font_size) * ui_size * DP
		if sp < 14.0 - 0.05:
			p.append("%s: the panels' text is %.1f sp (14 the least)" % [at, sp])
	return p


func _panels() -> Array:
	return ["settings", "card", "procedure", "alarms", "trainer", "permits", "work_orders", "stores", "crew",
		"debrief", "session_panel", "tools", "monitoring", "screens", "drawings", "manual"]


func _open(tree: SceneTree, main, pn: String) -> void:
	var ui = main.ui
	match pn:
		"settings": main.hud.show_settings(true)
		"card": ui.open_card("00QFA10AN001")
		"procedure": ui.toggle_procedure()
		"alarms": ui.toggle_alarms()
		"trainer":
			ui.set_instructor(true)
			ui.toggle_trainer()
		"permits": ui.toggle_permits()
		"work_orders": ui.open_work_orders()
		"stores": ui.open_stores()
		"crew": ui.open_crew()
		"debrief": ui.open_debrief()
		"session_panel": ui.open_session()
		"tools": ui.work.toggle_tools()
		"monitoring":
			ui.monitoring.open("00PGC10CY001")     # closed cooling water pump A's vibration probe
		"screens": ui.open_screens()
		"drawings": ui.open_drawing()
		"manual":
			if ui.manuals != null and ui.manual_view != null:
				ui.open_manual("steam_turbine", "parts", "30MAA10")
	await tree.process_frame


func _close(main, pn: String) -> void:
	if pn == "settings":
		main.hud.show_settings(false)
		return
	for i in 4:
		if not main.ui.close_top():
			break
	if pn == "trainer":
		main.ui.set_instructor(false)


## The panel that shows for `pn` (the node to check, its rect the panel's).
func _node(main, pn: String) -> Control:
	var ui = main.ui
	match pn:
		"settings": return main.hud.panel
		"tools": return ui.work.tools_panel
		"monitoring": return ui.monitoring.panel if ui.monitoring.is_open() else null
		"screens": return ui.mimic
		"drawings": return ui.drawing_view
		"manual": return ui.manual_view.get_child(0) if ui.manual_view != null and ui.manual_open() else null
	var n = ui.get(pn)
	return n as Control


func _check_panel(main, pn: String, at: String, canvas: Rect2, phone: bool, ui_size: float) -> Array:
	var p: Array = []
	var n := _node(main, pn)
	if n == null or not n.is_visible_in_tree():
		return ["%s: the %s did not open" % [at, pn]]
	var pr: Rect2 = n.get_global_rect()
	if not canvas.grow(0.5).encloses(pr):
		p.append("%s: the %s (%s) is not inside the canvas %s" % [at, pn, str(pr), str(canvas.size)])
	# (the full views have their own bars; condition monitoring's view stands at the right from the top, as the work
	# view's, by design)
	if pn not in ["screens", "drawings", "manual", "monitoring"] and pr.position.y < main.ui.panels_top() - 0.5:
		p.append("%s: the %s begins at %.0f, over the bars (they end at %.0f)" % [at, pn, pr.position.y,
			main.ui.panels_top()])
	var close: Button = null
	for t in CLOSERS:
		close = UiApp.find_button(n, t)
		if close != null:
			break
	if close == null:
		p.append("%s: the %s has no Close on screen" % [at, pn])
	elif not canvas.grow(0.5).encloses(close.get_global_rect()) or not pr.grow(0.5).encloses(close.get_global_rect()):
		p.append("%s: the %s's %s is not on screen: %s" % [at, pn, close.text, str(close.get_global_rect())])
	elif phone and close.size.y * ui_size * DP < 47.5:
		p.append("%s: the %s's %s is %.1f dp tall (48 the least)" % [at, pn, close.text, close.size.y * ui_size * DP])
	# nothing runs out at the panel's sides (a row cut at the right: issue #389's kind); text in a scrolled body may
	# run below it
	var cut: Array = []
	for c in n.find_children("*", "Control", true, false):
		var cc := c as Control
		if not cc.is_visible_in_tree() or cc.size.x <= 0.0 or not (cc is Label or cc is BaseButton or cc is RichTextLabel
				or cc is LineEdit):
			continue
		var r := cc.get_global_rect()
		if r.position.x < pr.position.x - 0.5 or r.end.x > pr.end.x + 0.5:
			cut.append("%s (%.0f..%.0f)" % [_name(cc), r.position.x, r.end.x])
	if phone:
		# every target in it 48 dp tall, and no text under 12 sp (UI-UX-POLICY T1, S1)
		var small: Array = []
		var tiny: Array = []
		for c in n.find_children("*", "Control", true, false):
			var cc := c as Control
			if not cc.is_visible_in_tree():
				continue
			if cc is BaseButton and cc.size.y * ui_size * DP < 47.5:
				small.append("%s %.0f dp" % [_name(cc), cc.size.y * ui_size * DP])
			if (cc is Label or cc is BaseButton) and cc.get_theme_font_size("font_size") * ui_size * DP < 12.0 - 0.05:
				tiny.append("%s %.1f sp" % [_name(cc), cc.get_theme_font_size("font_size") * ui_size * DP])
		if not small.is_empty():
			p.append("%s: in the %s %d targets under 48 dp: %s" % [at, pn, small.size(), ", ".join(small.slice(0, 4))])
		if not tiny.is_empty():
			p.append("%s: in the %s %d texts under 12 sp: %s" % [at, pn, tiny.size(), ", ".join(tiny.slice(0, 4))])
	if not cut.is_empty():
		p.append("%s: in the %s (%.0f..%.0f) %d run out at the sides: %s" % [at, pn, pr.position.x, pr.end.x, cut.size(),
			", ".join(cut.slice(0, 4))])
	return p


func _name(c: Control) -> String:
	var t = c.get("text")
	return "%s \"%s\"" % [c.get_class(), str(t).left(30)] if t != null else str(c.name)


## Chosen in the settings: applied at once (the canvas smaller, the open settings inside it, every bar button on
## screen) and kept in the settings file; a new start takes it.
func _setting(tree: SceneTree) -> Array:
	var p: Array = []
	tree.root.size = Vector2i(1600, 900)
	var main := _start(tree, "", null)
	for i in 4:
		await tree.process_frame
	var hud = main.hud
	var had = main.cf.get_value("ui", "ui_size", null)
	if absf(W.ui_size - 1.0) > 0.001 and had == null:
		p.append("a desktop starts at UI size %.2f (1 expected)" % W.ui_size)
	hud.show_settings(true)
	await tree.process_frame
	var opt: OptionButton = hud.ui_size_opt
	if opt == null or not opt.is_visible_in_tree():
		main.free()
		return p + ["the settings have no UI size"]
	if opt.item_count != W.UI_SIZES.size() or opt.get_item_text(0) != "100 %" or opt.get_item_text(opt.item_count - 1) != "150 %":
		p.append("the UI size's choices are not 100 %% to 150 %%: %d, %s to %s" % [opt.item_count, opt.get_item_text(0),
			opt.get_item_text(opt.item_count - 1)])
	opt.select(opt.item_count - 1)
	opt.item_selected.emit(opt.item_count - 1)
	for i in 4:
		await tree.process_frame
	var canvas: Rect2 = main.ui.root.get_viewport_rect()
	if absf(canvas.size.y - 600.0) > 1.0:
		p.append("choosing 150 %% left the canvas %s (1067 × 600 expected)" % str(canvas.size))
	if not canvas.grow(0.5).encloses(hud.panel.get_global_rect()) \
			or not canvas.grow(0.5).encloses(hud.close_btn.get_global_rect()):
		p.append("after choosing 150 %% the settings or their Close are off the canvas: %s" % str(hud.panel.get_global_rect()))
	p += _bars(main, "after choosing 150 %", canvas, false, 1.5)
	if hud.panel.get_global_rect().position.y < main.ui.panels_top() - 0.5:
		p.append("after choosing 150 %% the settings (from %.0f) reach over the bar (to %.0f)" % [
			hud.panel.get_global_rect().position.y, main.ui.panels_top()])
	opt.select(0)
	opt.item_selected.emit(0)
	for i in 4:
		await tree.process_frame
	if absf(main.ui.panels_top() - 160.0) > 0.5 or absf(main.ui.bar.size.y - main.ui.bar.get_combined_minimum_size().y) > 0.5:
		p.append("100 %% chosen again: the panels begin at %.0f (160 expected), the bar %.0f tall for %.0f" % [
			main.ui.panels_top(), main.ui.bar.size.y, main.ui.bar.get_combined_minimum_size().y])
	opt.select(opt.item_count - 1)
	opt.item_selected.emit(opt.item_count - 1)
	for i in 4:
		await tree.process_frame
	if float(main.cf.get_value("ui", "ui_size", 0.0)) != 1.5:
		p.append("the UI size chosen is not kept in the settings file: %s" % str(main.cf.get_value("ui", "ui_size", null)))
	var saved := ConfigFile.new()
	if saved.load("user://settings.cfg") != OK or float(saved.get_value("ui", "ui_size", 0.0)) != 1.5:
		p.append("the UI size chosen is not saved in user://settings.cfg")
	main.free()
	await tree.process_frame
	# a new start takes it; then back to 100 % (the other tests' settings file)
	main = _start(tree, "", null)
	for i in 2:
		await tree.process_frame
	if absf(W.ui_size - 1.5) > 0.001 or absf(tree.root.content_scale_factor - 1.5) > 0.001:
		p.append("a new start did not take the UI size saved (%.2f, the window's %.2f)" % [W.ui_size,
			tree.root.content_scale_factor])
	main.set_ui_size(1.0)
	await tree.process_frame
	if absf(main.ui.root.get_viewport_rect().size.y - 900.0) > 1.0:
		p.append("100 %% chosen again left the canvas %s" % str(main.ui.root.get_viewport_rect().size))
	if had == null:
		main.cf.erase_section_key("ui", "ui_size")
	else:
		main.cf.set_value("ui", "ui_size", had)
	Quality.save(main.cf)
	main.free()
	await tree.process_frame
	return p
