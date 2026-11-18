## The settings' UI size (issue #382; UI-UX-POLICY T1, S1, S2, R1, L2): 100 % to 200 %. A phone starts at the size
## that gives its buttons 48 dp and its text 14 sp on its own screen (ui/widgets.gd phone_ui_size: the Note 9 at its
## density 420 150 %, at the density class 480 Godot reports 180 %, a 360 dp tall phone 180 %), a desktop at 100 %.
## On a desktop's 1600 × 900 canvas, on the Note 9's (2220 × 1080 at the phone's UI scale), a 360 dp tall phone's and a
## 16:9 phone's, at their default and at 200 %, the HUD's buttons, the layer's bar and its clock are all on screen and
## overlap nothing; where the bar doesn't fit on one row (every phone, a desktop at a large size) the bars are ONE row,
## the rest of the buttons and the settings in More's list; every panel opened lies inside the canvas below the bars
## with its Close (or Back) on screen, and nothing in it runs out at its sides; on a phone at its size or above its
## targets are 48 dp at least and its text 14 sp. The size is chosen in the settings, applied at once (the panel open
## stays inside the smaller canvas) and kept in the settings file.
extends RefCounted

const W = preload("res://ui/widgets.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const UiApp = preload("res://tests/ui_app.gd")
const Quality = preload("res://app/quality.gd")

const CLOSERS := ["Close", "Back", "Leave", "Done"]
var DP := 0.457                 # dp per canvas px at 100 % on the screen tested (docs/UI-UX-POLICY.md §2, units)


func run(tree: SceneTree) -> Array:
	var p: Array = _defaults()
	var size0: Vector2i = tree.root.size
	# [window, UI scale ("" a desktop), UI size (null: the device's default), density, the default expected, name]
	for c in [[Vector2i(1600, 900), "", null, 0.0, 1.0, "a desktop"],
			[Vector2i(1600, 900), "", 1.5, 0.0, 1.0, "a desktop"],
			[Vector2i(1600, 900), "", 2.0, 0.0, 1.0, "a desktop"],
			[Vector2i(2220, 1080), "1.35", 1.0, 420.0, 1.5, "the Note 9"],
			[Vector2i(2220, 1080), "1.35", null, 420.0, 1.5, "the Note 9"],
			[Vector2i(2220, 1080), "1.35", null, 480.0, 1.8, "the Note 9 at its density class"],
			[Vector2i(2220, 1080), "1.35", 2.0, 420.0, 1.5, "the Note 9"],
			[Vector2i(2340, 1080), "1.35", null, 480.0, 1.8, "a 360 dp tall phone"],
			[Vector2i(1920, 1080), "1.35", null, 420.0, 1.5, "a 16:9 phone"],
			[Vector2i(1920, 1080), "1.35", null, 480.0, 1.8, "a 16:9 360 dp tall phone"],
			[Vector2i(1920, 1080), "1.35", 2.0, 480.0, 1.8, "a 16:9 360 dp tall phone"]]:
		tree.root.size = c[0]
		DP = minf(c[0].x / 1600.0, c[0].y / 900.0) * 160.0 / c[3] if c[3] > 0.0 else 0.0
		p += await _at(tree, c[1], c[2], c[3], c[4], c[5])
	tree.root.size = size0
	p += await _setting(tree)
	if tree.root.content_scale_factor != 1.0:
		p.append("the window's content scale is %.2f after the app left (1 expected)" % tree.root.content_scale_factor)
		tree.root.content_scale_factor = 1.0
	return p


## The size a phone starts at: the least of the settings' sizes with 48 dp buttons and 14 sp text on its screen.
func _defaults() -> Array:
	var p: Array = []
	# [window, density, expected]
	for c in [[Vector2(2220, 1080), 420.0, 1.5], [Vector2(2220, 1080), 480.0, 1.8], [Vector2(2340, 1080), 480.0, 1.8],
			[Vector2(1920, 1080), 420.0, 1.5], [Vector2(1920, 1080), 480.0, 1.8], [Vector2(2400, 1080), 380.0, 1.4],
			[Vector2(3200, 1440), 560.0, 1.5], [Vector2(1280, 720), 384.0, 2.0], [Vector2(800, 480), 240.0, 2.0]]:
		var got := W.phone_ui_size(c[0], c[1], 1.35)
		if not is_equal_approx(got, c[2]):
			p.append("a phone %s at density %.0f starts at %d %% (%d %% expected)" % [str(c[0]), c[1], roundi(got * 100.0),
				roundi(c[2] * 100.0)])
		var dp: float = minf(c[0].x / 1600.0, c[0].y / 900.0) * 160.0 / c[1]
		if got < 2.0 and (52.0 * 1.35 * got * dp < 48.0 - 1e-3 or 20.0 * 1.35 * got * dp < 14.0 - 1e-3):
			p.append("at %d %% a phone %s at %.0f has %.1f dp buttons and %.1f sp text" % [roundi(got * 100.0), str(c[0]), c[1],
				52.0 * 1.35 * got * dp, 20.0 * 1.35 * got * dp])
		if got > 1.0 and 52.0 * 1.35 * (got - 0.1) * dp >= 48.0:
			p.append("a phone %s at %.0f starts at %d %%, but %d %% gives 48 dp already" % [str(c[0]), c[1],
				roundi(got * 100.0), roundi(got * 100.0) - 10])
	if not is_equal_approx(W.default_ui_size(Vector2(1600, 900)), 1.0):
		p.append("a desktop starts at %d %% (100 expected)" % roundi(W.default_ui_size(Vector2(1600, 900)) * 100.0))
	return p


func _start(tree: SceneTree, ui_scale: String, ui_size, density := 0.0) -> Node:
	RunSave.remove(Autosave.default_path)
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["scenario"] = "shift_aged"          # (the crews' and the work orders' panels have something to show)
	if ui_scale != "":
		main.opts["ui_scale"] = ui_scale
	if density > 0.0:
		main.opts["density"] = str(density)
	if ui_size != null:
		main.opts["ui_size"] = str(ui_size)
	tree.root.add_child(main)
	if main.ui != null and main.ui.clock != null:
		main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	return main


func _at(tree: SceneTree, ui_scale: String, size_given, density: float, dflt: float, who: String) -> Array:
	var p: Array = []
	var main := _start(tree, ui_scale, size_given, density)
	var ui_size: float = W.ui_size
	var at := "%s at %d %%%s" % [who, roundi(ui_size * 100.0), " (its default)" if size_given == null else ""]
	if size_given == null and not is_equal_approx(ui_size, dflt):
		p.append("%s starts at %d %% (%d %% expected)" % [who, roundi(ui_size * 100.0), roundi(dflt * 100.0)])
	if not is_equal_approx(W.ui_size_default, dflt):
		p.append("%s: the default is %d %% (%d %% expected)" % [at, roundi(W.ui_size_default * 100.0), roundi(dflt * 100.0)])
	for i in 6:
		await tree.process_frame
	if size_given == null and who == "the Note 9" and density == 420.0:
		# the window halved (Android's split screen): the default worked out again for it, and back
		var w0: Vector2i = tree.root.size
		tree.root.size = Vector2i(w0.x, w0.y / 2)
		await tree.process_frame
		if not is_equal_approx(W.ui_size, 2.0):
			p.append("%s: in a window half as tall the default size is %d %% (200 %% expected)" % [at, roundi(W.ui_size * 100.0)])
		tree.root.size = w0
		await tree.process_frame
		if not is_equal_approx(W.ui_size, dflt):
			p.append("%s: back at its full window the size is %d %% (%d %% expected)" % [at, roundi(W.ui_size * 100.0), roundi(dflt * 100.0)])
		for i in 3:
			await tree.process_frame
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["%s: the app did not start" % at]
	var canvas: Rect2 = ui.root.get_viewport_rect()
	var want: Vector2 = Vector2(1600.0 * maxf(1.0, float(tree.root.size.x) / float(tree.root.size.y) * 900.0 / 1600.0), 900.0) / ui_size
	if (canvas.size - want).length() > 2.0:
		p.append("%s: the canvas is %s, %s expected" % [at, str(canvas.size), str(want)])
	# a phone at its size or above: 48 dp and 14 sp (below it, by the user's choice, less)
	var phone: bool = ui_scale != "" and ui_size >= dflt - 0.001
	# the status line at its longest (the area with the longest name, running, far out): the bars still fit
	main.hud.status.text = "Auxiliary boiler, demineralised water, instrument air, closed cooling water · running · x -1234  y -1234  +123.4 m · lean+vis"
	main.hud.set_process(false)
	main.hud._measure_status()
	for i in 3:
		await tree.process_frame
	p += await _bars(main, at, canvas, phone, ui_size)
	p += await _compact(main, at, canvas, ui_scale != "" or ui_size > 1.0)
	main.hud.set_process(true)
	p += await _popups(tree, main, at, canvas, phone, ui_size)
	if ui_scale == "" and ui_size == 1.0:
		# a desktop at 100 % as before: the bar one row at 88 px, the panels from 160 px, with Instructor on too
		ui.set_instructor(true)
		for i in 3:
			await tree.process_frame
		if absf(ui.bar.get_global_rect().position.y - 88.0) > 0.5 or absf(ui.panels_top() - 160.0) > 0.5 or ui.compact:
			p.append("%s: the bar is at %.0f and the panels begin at %.0f with Instructor on (88 and 160 before), compact %s" % [at,
				ui.bar.get_global_rect().position.y, ui.panels_top(), str(ui.compact)])
		ui.set_instructor(false)
	for pn in _panels():
		await _open(tree, main, pn)
		for i in 3:
			await tree.process_frame
		p += _check_panel(main, pn, at, canvas, phone, ui_size)
		_close(main, pn)
		await tree.process_frame
	p += await _workshop(tree, main, at, ui_size)
	main.free()
	await tree.process_frame
	return p


## The compact bar (`want`: every phone, a desktop above 100 %): one row with the HUD's buttons, at the top, the 3D
## view below it from a fifth of the height at most; the clock, Alarms and More in it; every other button and the
## settings in More's list, which does what the button does. Off it (a desktop at 100 %) every button is on the bar.
func _compact(main, at: String, canvas: Rect2, want: bool) -> Array:
	var p: Array = []
	var ui = main.ui
	var hud = main.hud
	if ui.compact != want:
		return ["%s: the bar is %s (%s expected)" % [at, "compact" if ui.compact else "full", "compact" if want else "full"]]
	var more: MenuButton = ui._more
	# the choice doesn't depend on the bar's present state (the compact clock is narrower): no width flips it back
	var c0: bool = ui.compact
	for w in range(700, 2300, 7):
		ui._set_compact(false)
		var a: bool = ui._wants_compact(float(w))
		ui._set_compact(true)
		if ui._wants_compact(float(w)) != a:
			p.append("%s: at %d px the bar is compact or not as it is now" % [at, w])
			break
	ui._set_compact(c0)
	ui._layout()
	await main.get_tree().process_frame
	if not want:
		if more.visible or ui._overflow.get_child_count() > 0 or not hud.settings_btn.visible:
			p.append("%s: the full bar has More or buttons in its list, or no Settings" % at)
		return p
	# one row: every control on the bar and the HUD's at the same height band, the band from y 12
	var band: float = maxf(ui.bar.get_global_rect().end.y, hud.bar.get_global_rect().end.y)
	if ui.bar.get_global_rect().position.y > 12.5 or band > canvas.size.y * 0.2 + 0.5 or ui.panels_top() > band + 16.5:
		p.append("%s: the compact row runs %.0f to %.0f of %.0f (a fifth at most), the panels from %.0f" % [at,
			ui.bar.get_global_rect().position.y, band, canvas.size.y, ui.panels_top()])
	var top_y := 12.0
	for c in ui.bar.get_children() + hud.bar.get_children():
		var cc := c as Control
		if cc.is_visible_in_tree() and (cc.get_global_rect().position.y > top_y + 0.5 or cc.get_global_rect().end.y > band + 0.5):
			p.append("%s: the compact row's %s is on a row of its own: %s" % [at, _name(cc), str(cc.get_global_rect())])
	for c in [ui._time, ui._alarm_btn, more]:
		if not (c as Control).is_visible_in_tree() or (c as Control).get_parent() != ui.bar:
			p.append("%s: the compact row has no %s (its %.0f px: the clock %.0f, Alarms %.0f, More %.0f; the HUD's %.0f)" % [at,
				_name(c), ui._compact_room, ui._time.get_combined_minimum_size().x, ui._alarm_btn.get_combined_minimum_size().x,
				more.get_combined_minimum_size().x, hud.compact_width()])
	if hud.settings_btn.is_visible_in_tree():
		p.append("%s: Settings is on the compact row (it is in More's list)" % at)
	# More's list: each button not on the row (that would show), then Settings, and each does what its button does
	ui._fill_more()
	var pm: PopupMenu = more.get_popup()
	var listed: Array = []
	for i in pm.item_count:
		listed.append(pm.get_item_text(i))
	var wanted: Array = []
	for c in ui._bar_items:
		if c is Button and c.visible and c.get_parent() != ui.bar:
			wanted.append({"1×": "Normal speed (1×)", "Fast": "Fast-forward"}.get(c.text, c.text))
	wanted.append("Settings")
	if listed != wanted:
		p.append("%s: More's list is %s (%s expected)" % [at, str(listed), str(wanted)])
	if listed.size() < 2:
		p.append("%s: More's list holds only %s" % [at, str(listed)])
	# a button that is disabled is listed disabled, and choosing it does nothing
	var ff: Button = ui._ff_btn
	if ff.get_parent() != ui.bar:
		var was: bool = ff.disabled
		ff.disabled = true
		ui._fill_more()
		var fi: int = -1
		for i in pm.item_count:
			if pm.get_item_text(i) == "Fast-forward":
				fi = i
		var speed0: int = ui.clock.speed
		if fi < 0 or not pm.is_item_disabled(fi):
			p.append("%s: Fast-forward, disabled, is not listed disabled in More" % at)
		elif true:
			ui._on_more(pm.get_item_id(fi))
			if ui.clock.speed != speed0:
				p.append("%s: Fast-forward, disabled, ran from More's list" % at)
		ff.disabled = was
		ui._fill_more()
	var si: int = listed.find("Settings")
	ui._on_more(pm.get_item_id(si))
	await main.get_tree().process_frame
	if not hud.panel.visible:
		p.append("%s: Settings in More's list did not open the settings" % at)
	hud.show_settings(false)
	var ci: int = listed.find("Crew")
	if ci >= 0:
		ui._on_more(pm.get_item_id(ci))
		await main.get_tree().process_frame
		if not ui.crew.visible:
			p.append("%s: Crew in More's list did not open the crew" % at)
		ui.close_top()
		await main.get_tree().process_frame
	# More's rows 48 dp on a phone (the theme's list rows)
	var row: float = pm.get_theme_font("font").get_height(pm.get_theme_font_size("font_size")) + pm.get_theme_constant("v_separation")
	if DP > 0.0 and row * W.ui_size * DP < 47.5 and W.ui_size >= W.ui_size_default - 0.001:
		p.append("%s: More's list has rows %.1f dp tall (48 the least)" % [at, row * W.ui_size * DP])
	return p


## The Workshop at the UI size: its way back on screen, and its 3D view drawn with as many pixels as at 100 % (its
## resolution scaled up as the canvas's units grow).
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
	# a drag turns the view as far as it moves on the screen, whatever the UI size: 30 screen px are 30 / ui_size of
	# the canvas's units
	var m := InputEventMouseMotion.new()
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.relative = Vector2(30.0, 0.0) / ui_size
	var y0: float = ws.cam.yaw
	ws.cam.handle(m, 600.0)
	if absf((y0 - ws.cam.yaw) - 30.0 * ws.cam.ORBIT_RATE) > 1e-4:
		p.append("%s: 30 px of drag on the screen turn the Workshop's view %.4f rad (%.4f expected)" % [at, y0 - ws.cam.yaw,
			30.0 * ws.cam.ORBIT_RATE])
	ws.close()
	await tree.process_frame
	# and the map pans as far as the finger moves
	var mv = main.map
	var t0: Vector3 = mv.target
	mv._pan(Vector2(30.0, 0.0) / ui_size)
	var got: float = (mv.target - t0).length()
	if absf(got - 30.0 * mv.dist * 0.0015) > 1e-3:
		p.append("%s: 30 px of drag on the screen pan the map %.2f m (%.2f expected)" % [at, got, 30.0 * mv.dist * 0.0015])
	mv.target = t0
	return p


## The lists' popups: on the canvas, and their rows 48 dp tall on the phone at 150 % (the settings' UI size, the
## drawings' sheets).
func _popups(tree: SceneTree, main, at: String, canvas: Rect2, phone: bool, ui_size: float) -> Array:
	var p: Array = []
	main.hud.show_settings(true)
	main.ui.open_drawing()
	await tree.process_frame
	for ob in [main.hud.ui_size_opt, main.ui.drawing_view.picker]:
		var o := ob as OptionButton
		o.show_popup()
		for i in 3:
			await tree.process_frame
		var pm: PopupMenu = o.get_popup()
		var r := Rect2(Vector2(pm.position), Vector2(pm.size))
		if not canvas.grow(0.5).encloses(r):
			p.append("%s: the list of %s opens off the canvas: %s in %s" % [at, o.name, str(r), str(canvas.size)])
		# a row's height as the list lays it out: its text's line and the gap (a list taller than the canvas scrolls)
		var row: float = pm.get_theme_font("font").get_height(pm.get_theme_font_size("font_size")) \
			+ pm.get_theme_constant("v_separation")
		if phone and row * ui_size * DP < 47.5:
			p.append("%s: the list of %s has rows %.1f dp tall (48 the least)" % [at, o.name, row * ui_size * DP])
		pm.hide()
		await tree.process_frame
	main.ui.close_drawings()
	main.hud.show_settings(false)
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
		if phone and b is BaseButton and minf(r.size.x, r.size.y) * ui_size * DP < 47.5:
			p.append("%s: the bar's %s is %s, %.1f dp the least way (48 the least)" % [at, _name(b), str(r.size), minf(r.size.x, r.size.y) * ui_size * DP])
	# the touch sticks keep a thumb's size on the screen (420 px of the canvas at every UI size), in their corners
	for st in hud.sticks:
		var r: Rect2 = (st as Control).get_global_rect()
		if absf(r.size.x * ui_size - 420.0) > 1.0 or not canvas.grow(0.5).encloses(r):
			p.append("%s: the %s is %s (420 px of the screen's canvas, in its corner, expected)" % [at, st.name, str(r)])
	# flying with the touch controls: Up and Down below the bars, on screen
	var ud: Array = hud.updown
	var shown0: Array = ud.map(func(b): return b.visible)
	for b in ud:
		b.visible = true
	hud.updown_box.reset_size()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	for b in ud:
		var r: Rect2 = (b as Control).get_global_rect()
		if not canvas.grow(0.5).encloses(r) or r.position.y < ui.bar.get_global_rect().end.y - 0.5:
			p.append("%s: the flying %s %s is off screen or over the bar (it ends at %.0f)" % [at, b.text, str(r),
				ui.bar.get_global_rect().end.y])
	for i in ud.size():
		ud[i].visible = shown0[i]
	var sr: Rect2 = hud.top_box.get_global_rect()
	sr.size.y = hud.top_box.get_combined_minimum_size().y
	for o in rects:
		if rects[o].intersects(sr):
			p.append("%s: the status line %s overlaps the bar's %s %s" % [at, str(sr), o, str(rects[o])])
	if not canvas.grow(0.5).encloses(sr):
		p.append("%s: the status line is off screen: %s" % [at, str(sr)])
	# at the bottom (a narrow canvas): between the sticks' corners, clear of Up and Down
	if hud._status_low:
		for c in hud.sticks + hud.updown:
			var cr: Rect2 = (c as Control).get_global_rect()
			if c in hud.updown:
				cr = hud.updown_box.get_global_rect()
			if cr.size.x > 0.0 and cr.grow(-0.5).intersects(sr.grow(-0.5)):
				p.append("%s: the status line at the bottom %s overlaps %s %s" % [at, str(sr), c.name, str(cr)])
	# the clock shows its whole text: as wide as the longest it can say, and on screen (it was cut at the left)
	var clock: Label = ui._time
	var f: Font = clock.get_theme_font("font")
	var fs: int = clock.get_theme_font_size("font_size")
	for t in [ui.clock_label("Day 999 Wed 23:59", "paused", ui.compact), clock.text]:
		for line in t.split("\n"):
			var tw: float = f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if clock.size.x + 0.5 < tw:
				p.append("%s: the clock is %.0f px wide, its text \"%s\" %.0f" % [at, clock.size.x, line, tw])
	if clock.size.y + 0.5 < f.get_height(fs) * t_lines(clock.text):
		p.append("%s: the clock is %.0f px tall for %d lines" % [at, clock.size.y, t_lines(clock.text)])
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


static func t_lines(t: String) -> int:
	return t.split("\n").size()


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
	# (the settings keep half the canvas at least: app/hud.gd settings_top_min)
	var top_ok: float = main.ui.panels_top() if pn != "settings" else minf(main.ui.panels_top(), main.hud.settings_top_min(canvas.size.y))
	if pn not in ["screens", "drawings", "manual", "monitoring"] and pr.position.y < top_ok - 0.5:
		p.append("%s: the %s begins at %.0f, over the bars (they end at %.0f)" % [at, pn, pr.position.y,
			main.ui.panels_top()])
	if pn == "screens" and pr.end.y - main.ui.mimic.canvas_top() < canvas.size.y * 0.3:
		p.append("%s: the screens leave %.0f px of %.0f to the screen itself (30 %% the least; from %.0f, over the row %s)" % [at,
			pr.end.y - main.ui.mimic.canvas_top(), canvas.size.y, pr.position.y, str(main.ui.views_over_row)])
	# the screens' tabs and Close: no HUD button over them (the screens over the compact row hide Map)
	if pn == "screens":
		var chrome := Rect2(pr.position, Vector2(pr.size.x, main.ui.mimic.canvas_top() - pr.position.y))
		for b in main.hud.bar.get_children():
			if (b as Control).is_visible_in_tree() and (b as Control).get_global_rect().intersects(chrome):
				p.append("%s: the HUD's %s lies over the screens' tabs" % [at, _name(b)])
	# the status line at the bottom hides under what is open (it would be cut by it)
	var hud = main.hud
	if hud._status_low and hud.top_box.visible and hud.top_box.get_global_rect().intersects(pr):
		p.append("%s: the %s lies over the status line at the bottom, which shows under it" % [at, pn])
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
			if cc is BaseButton and minf(cc.size.x, cc.size.y) * ui_size * DP < 47.5:
				small.append("%s %.0f dp" % [_name(cc), minf(cc.size.x, cc.size.y) * ui_size * DP])
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
	# 100 % to 200 % in steps of 10, the desktop's start marked
	if opt.item_count != 11 or opt.get_item_text(0) != "100 % (default)" or opt.get_item_text(5) != "150 %" \
			or opt.get_item_text(opt.item_count - 1) != "200 %":
		p.append("the UI size's choices are not 100 %% (default) to 200 %%: %d, %s to %s" % [opt.item_count,
			opt.get_item_text(0), opt.get_item_text(opt.item_count - 1)])
	var i150: int = W.UI_SIZES.find(1.5)
	opt.select(i150)
	opt.item_selected.emit(i150)
	for i in 4:
		await tree.process_frame
	var canvas: Rect2 = main.ui.root.get_viewport_rect()
	if absf(canvas.size.y - 600.0) > 1.0:
		p.append("choosing 150 %% left the canvas %s (1067 × 600 expected)" % str(canvas.size))
	if not canvas.grow(0.5).encloses(hud.panel.get_global_rect()) \
			or not canvas.grow(0.5).encloses(hud.close_btn.get_global_rect()):
		p.append("after choosing 150 %% the settings or their Close are off the canvas: %s" % str(hud.panel.get_global_rect()))
	p += await _bars(main, "after choosing 150 %", canvas, false, 1.5)
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
	# 200 %, the most: the settings and their Close still inside the 800 × 450 canvas
	opt.select(opt.item_count - 1)
	opt.item_selected.emit(opt.item_count - 1)
	for i in 4:
		await tree.process_frame
	canvas = main.ui.root.get_viewport_rect()
	if absf(canvas.size.y - 450.0) > 1.0 or not canvas.grow(0.5).encloses(hud.panel.get_global_rect()) \
			or not canvas.grow(0.5).encloses(hud.close_btn.get_global_rect()):
		p.append("after choosing 200 %% the canvas is %s, the settings %s" % [str(canvas.size), str(hud.panel.get_global_rect())])
	p += await _bars(main, "after choosing 200 %", canvas, false, 2.0)
	opt.select(i150)
	opt.item_selected.emit(i150)
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
