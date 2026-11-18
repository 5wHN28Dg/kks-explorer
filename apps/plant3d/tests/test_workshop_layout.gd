## The Workshop's panels laid out on the screens they are used on (#388, #389, #390; docs/UI-UX-POLICY.md T1, T3, R1,
## S1, S2, L2, K5), for every kind the build has:
## - on a desktop (1600 × 900 canvas) and on the Note 9 (2220 × 1080 at 420 dpi: a 1850 × 900 canvas, the phone's UI
##   scale 1.35), each at the UI size's 100 % and 150 % (the settings' UI size, #382: the canvas 1.5 times smaller);
## - the panels fill the screen; the top bar with Back to the plant, the parts tree, the properties, the bench and the
##   tools are shown, inside the screen, apart, and big enough to use (the tree three rows high or more, the side
##   panels at least SIDE_MIN wide, the tools a row high);
## - no control is squeezed below its own size or cut at the screen's edge, and each can be scrolled into view;
## - no text in the panels is under the theme's size, and the words drawn over the 3D view (the step line, the
##   session's strip) have a backing of their own;
## - a long properties text scrolls inside its panel; the guided steps are reachable and start, their line shown
##   between the panels and the tools, over none of them.
extends RefCounted

const W = preload("res://ui/widgets.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")

## [name, the window's size in pixels (the canvas is 1600 × 900 stretched, expanded to its shape), the UI scale the
## app starts with (the phone's on the Note 9), the UI sizes (the settings' 100 % and 150 %, applied as the app does)]
const SCREENS := [
	["desktop", Vector2i(1600, 900), "", [1.0, 1.5]],
	["Note 9", Vector2i(2220, 1080), "1.35", [1.0, 1.5]],
]
const SIDE_MIN := 300.0          # a side panel's least width (canvas px) on these screens
const ROWS := 4                  # the tree and the properties are at least this many lines of text high
const TARGET_H := 52             # a control's height at scale 1 (W.button's)
const FONT := 20                 # the panels' least text size at scale 1 (the theme's)

var p: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		p.append(what)

func run(tree: SceneTree) -> Array:
	var size0: Vector2i = tree.root.size
	for sc in SCREENS:
		tree.root.size = sc[1]
		RunSave.remove(Autosave.default_path)   # (the run the app before saved: no offer to go on with it, a modal layer)
		var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
		if sc[2] != "":
			main.opts["ui_scale"] = sc[2]
		main.opts["ui_size"] = "1"
		tree.root.add_child(main)
		if main.workshop == null:
			main.free()
			tree.root.size = size0
			return ["the app did not start with its Workshop"]
		if main.ui != null and main.ui.clock != null:
			main.ui.clock.set_speed(SimClock.Speed.PAUSED)
		await tree.process_frame
		var ws = main.workshop
		check(not ws.is_open and ws.can_open(), "%s: the Workshop can be opened (open %s, scripted %s, map %s)" % [sc[0],
			ws.is_open, main.player.scripted, main.map.active])
		var kinds: Array = ws.kinds()
		check(not kinds.is_empty(), "the build has Workshop kinds")
		for kind in kinds:
			check(ws.open(kind), "%s: the Workshop opens" % kind)
			if not await _wait_shown(tree, ws):
				check(false, "%s: the machine did not show" % kind)
				continue
			for size in sc[3]:
				# the settings' UI size, applied live as the app applies it (app/main.gd set_ui_size, without saving)
				W.apply_ui_size(tree.root, size)
				ws.fit_resolution()
				await _frames(tree, 3)
				var at := "%s, %s at %d %%" % [kind, sc[0], roundi(size * 100.0)]
				await _layout(tree, ws, at)
				await _steps(tree, ws, at)
			W.apply_ui_size(tree.root, 1.0)
			ws.close()
			await ws.left
		for i in 3:   # (not while the last close's signal is still being sent)
			await tree.process_frame
		main.free()
		await tree.process_frame
	tree.root.size = size0
	return p

func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame

func _wait_shown(tree: SceneTree, ws) -> bool:
	var end := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < end:
		if ws.machine != null and ws.entry_ms > 0.0 and ws._loading == "":
			return true
		await tree.process_frame
	return false

func _layout(tree: SceneTree, ws, at: String) -> void:
	var pn = ws.panels
	var s: float = W.scale
	var screen := Rect2(Vector2.ZERO, pn.get_viewport_rect().size)
	check(pn.size.is_equal_approx(screen.size), "%s: the panels fill the screen (%s, the screen %s)" % [at, pn.size, screen.size])
	# the panels each shown, inside the screen, apart, and big enough
	var side := minf(SIDE_MIN, screen.size.x * 0.2)
	for n in ["top_bar", "tools_panel", "tools_scroll"]:
		if pn.get(n) == null:
			check(false, "%s: the panels have no %s" % [at, n])
			return
	var shown := {"top bar": pn.top_bar, "parts tree": pn.tree_panel, "properties": pn.props_panel, "tools": pn.tools_panel}
	for n in shown:
		var c: Control = shown[n]
		check(c.is_visible_in_tree(), "%s: the %s show" % [at, n])
		check(_inside(c.get_global_rect(), screen), "%s: the %s lie inside the screen (%s)" % [at, n, c.get_global_rect()])
	for c in [pn.tree_panel, pn.props_panel]:
		check(c.size.x >= side, "%s: %s is %.0f wide (at least %.0f)" % [at, c.name, c.size.x, side])
	var fs: int = pn.tree.get_theme_font_size("font_size")
	var row: float = pn.tree.get_theme_font("font").get_height(fs) + pn.tree.get_theme_constant("v_separation")
	# (a line of text: on a phone the tree's rows are taller, targets of 48 dp, and it scrolls through them)
	var line: float = pn.tree.get_theme_font("font").get_height(fs) + 4.0 * W.scale
	if s > 1.0:   # (the phone: a row is a target, 52 at its scale: 48 dp at 150 %)
		check(row >= TARGET_H * s - 1.0, "%s: the parts tree's rows are %.0f px tall (a target: %.0f)" % [at, row, TARGET_H * s])
	check(row > 0.0 and pn.tree.size.y >= ROWS * line, "%s: the parts tree shows %d rows or more (%.0f px high, a row %.0f)" % [at, ROWS, pn.tree.size.y, row])
	check(pn.props_panel.size.y >= ROWS * line, "%s: the properties are %d rows high or more (%.0f)" % [at, ROWS, pn.props_panel.size.y])
	check(pn.tools_scroll.size.y >= TARGET_H * s - 1.0, "%s: the tools show a row at least (%.0f px)" % [at, pn.tools_scroll.size.y])
	_apart(at, [pn.top_bar, pn.tree_panel, pn.props_panel, pn.tools_panel])
	# the side panels at their width, a long part name wrapping in the tree rather than widening it (#389)
	var want_side: float = minf(pn.SIDE_W * s, screen.size.x * pn.SIDE_MAX)
	var long_it: TreeItem = pn.tree.create_item(pn.tree.get_root())
	long_it.set_text(0, "A part with a very long name that would never fit in the parts tree's width at all, however wide")
	long_it.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
	await _frames(tree, 3)
	for c in [pn.tree_panel, pn.props_panel]:
		check(absf(c.size.x - want_side) <= 1.0, "%s: %s is %.0f wide with a long name in the tree (%.0f expected)" % [at, c.name,
			c.size.x, want_side])
	long_it.free()
	# the machine's own names wrap in the tree (#389: they were cut short)
	var it: TreeItem = pn.tree.get_root()
	while it != null:
		check(it.get_autowrap_mode(0) != TextServer.AUTOWRAP_OFF, "%s: the tree's \"%s\" does not wrap" % [at, it.get_text(0)])
		it = it.get_next_in_tree()
	# the top bar takes presses on its buttons only: a drag elsewhere on it turns the 3D view under it
	for c in pn.top_bar.find_children("*", "Control", true, false) + [pn.top_bar]:
		if not (c is BaseButton) and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			check(false, "%s: the top bar's %s takes the mouse (only its buttons should)" % [at, c.name])
	# Back to the plant: always in the top bar, whole, in the screen (R1)
	check(pn.back_btn.is_visible_in_tree() and _inside(pn.back_btn.get_global_rect(), screen)
		and pn.top_bar.is_ancestor_of(pn.back_btn), "%s: Back to the plant is in the top bar, on the screen" % at)
	# every control whole: within its panel's sides (a control too big for its place spills past them: Godot never makes
	# one smaller than it needs) and the screen's, and reachable by scrolling
	for c in _controls(pn):
		var box := _panel_of(c)
		if box != null:
			var br := box.get_global_rect()
			var cr: Rect2 = c.get_global_rect()
			check(cr.position.x >= br.position.x - 0.5 and cr.end.x <= br.end.x + 0.5, "%s: %s runs past its panel %s's sides (%s in %s)" % [
				at, c.name, box.name, cr, br])
		check(c.size.y >= TARGET_H * s - 0.5 or not _target(c), "%s: %s is %.0f px high (a target: %.0f)" % [at, c.name, c.size.y, TARGET_H * s])
		var r: Rect2 = c.get_global_rect()
		check(r.position.x >= -0.5 and r.end.x <= screen.size.x + 0.5, "%s: %s is cut at the screen's edge (%s)" % [at, c.name, r])
	for c in _controls(pn.tools_panel):   # (a pixel's leeway: the scroll is rounded to whole pixels)
		pn.tools_scroll.ensure_control_visible(c)
		await _frames(tree, 2)
		check(_inside(c.get_global_rect(), pn.tools_scroll.get_global_rect().grow(1.5)), "%s: %s scrolls into view (%s in %s, scroll %d of %s, content %s)" % [at, c.name, c.get_global_rect(),
			pn.tools_scroll.get_global_rect(), pn.tools_scroll.scroll_vertical, pn.tools_scroll.get_v_scroll_bar().max_value, pn.tools_box.size])
	pn.tools_scroll.scroll_vertical = 0
	# text sizes: the theme's at least (UI-UX-POLICY S1), and a backing under the words over the 3D view (K5)
	_fonts(pn, at, int(FONT * s))
	for l in [pn.step_label, pn.strip]:
		var sb = l.get_theme_stylebox("normal")
		check(sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.a >= 0.85, "%s: %s has a backing over the 3D view" % [at, l.name])
	# the bench in the properties' place, then back
	pn.show_run(true)
	await _frames(tree, 2)
	check(pn.run_panel.is_visible_in_tree() and _inside(pn.run_panel.get_global_rect(), screen) and pn.run_panel.size.x >= side
		and pn.run_panel.size.y >= ROWS * line, "%s: the bench's panel shows, inside the screen (%s)" % [at, pn.run_panel.get_global_rect()])
	_apart(at, [pn.top_bar, pn.tree_panel, pn.run_panel, pn.tools_panel])
	check(absf(pn.run_panel.size.x - want_side) <= 1.0, "%s: the bench's panel is %.0f wide (%.0f, as the others)" % [at,
		pn.run_panel.size.x, want_side])
	var rr: Rect2 = pn.run_panel.get_global_rect()
	for c in _controls(pn.run_panel):   # its rows wrap: nothing squeezed or past the panel's sides (#389)
		var r: Rect2 = c.get_global_rect()
		check(r.position.x >= rr.position.x - 0.5 and r.end.x <= rr.end.x + 0.5,
			"%s: the bench's %s runs past the panel's sides (%s, the panel %s)" % [at, c.name, r, rr])
	pn.show_info(true)
	# the session's strip, when shown, takes its own place in the column (over nothing else)
	# (as a session the Workshop was opened in and that has ended: the panels' own tick shows the strip)
	ws._session = true
	pn._strip_n = -1          # (shown again: an earlier pass left the ended session's count)
	await _frames(tree, 3)
	check(pn.strip.is_visible_in_tree(), "%s: the strip shows in a session" % at)
	check(_inside(pn.strip.get_global_rect(), screen), "%s: the strip is on the screen (%s)" % [at, pn.strip.get_global_rect()])
	_apart(at, [pn.strip, pn.top_bar, pn.tree_panel, pn.props_panel, pn.tools_panel])
	check(pn.tree.size.y >= ROWS * line, "%s: with the strip the tree still shows %d rows (%.0f)" % [at, ROWS, pn.tree.size.y])
	ws._session = false
	await _frames(tree, 1)
	# a long properties text scrolls inside its panel: it never runs under the tools (#389)
	var long := PackedStringArray()
	for i in 60:
		long.append("Line %d of a long description that wraps at the panel's width." % i)
	pn.props.text = "\n".join(long)
	await _frames(tree, 3)
	check(_inside(pn.props_panel.get_global_rect(), screen), "%s: a long text keeps the properties inside the screen (%s)" % [at, pn.props_panel.get_global_rect()])
	_apart(at, [pn.top_bar, pn.tree_panel, pn.props_panel, pn.tools_panel])
	var sc: ScrollContainer = pn.props_panel.find_child("props_scroll", true, false)
	check(sc != null and sc.get_v_scroll_bar().max_value > sc.size.y, "%s: a long properties text scrolls" % at)
	pn.selected_changed()

## The guided steps from the tools: the button reachable and whole, the step line shown between the panels and the
## tools (over none of them), on the screen.
func _steps(tree: SceneTree, ws, at: String) -> void:
	var pn = ws.panels
	if ws.words.get("assembly", []).is_empty() or pn.get("tools_panel") == null:
		return
	var b: Button = pn.tools_panel.find_child("disassemble", true, false)
	if b == null:
		check(false, "%s: there is a Take apart step by step button" % at)
		return
	pn.tools_scroll.ensure_control_visible(b)
	await _frames(tree, 2)
	check(not b.disabled and b.is_visible_in_tree() and _inside(b.get_global_rect(), pn.tools_scroll.get_global_rect().grow(1.5)),
		"%s: Take apart step by step is on the screen" % at)
	b.pressed.emit()
	await _frames(tree, 3)
	var sl: Label = pn.step_label
	check(ws.guide.on() and sl.text.begins_with("Step 1"), "%s: the steps start (%s)" % [at, sl.text])
	var screen := Rect2(Vector2.ZERO, pn.get_viewport_rect().size)
	check(sl.is_visible_in_tree() and _inside(sl.get_global_rect(), screen), "%s: the step line is on the screen (%s)" % [at, sl.get_global_rect()])
	var slot: Rect2 = pn.step_slot.get_global_rect()
	check(sl.get_global_rect().position.distance_to(slot.position) <= 1.0 and absf(sl.size.x - slot.size.x) <= 1.0
		and absf(sl.size.y - slot.size.y) <= 1.0, "%s: the step line is not in its place in the column (%s, its place %s)" % [
		at, sl.get_global_rect(), slot])
	_apart(at, [sl, pn.top_bar, pn.tree_panel, pn.props_panel, pn.tools_panel])
	var fs: int = pn.tree.get_theme_font_size("font_size")
	var row: float = pn.tree.get_theme_font("font").get_height(fs) + pn.tree.get_theme_constant("v_separation")
	# (a line of text: on a phone the tree's rows are taller, targets of 48 dp, and it scrolls through them)
	var line: float = pn.tree.get_theme_font("font").get_height(fs) + 4.0 * W.scale
	check(pn.tree.size.y >= ROWS * line and pn.props_panel.size.y >= ROWS * line, "%s: with the step line the tree and the properties still show %d rows (%.0f, %.0f px; a row %.0f)" % [
		at, ROWS, pn.tree.size.y, pn.props_panel.size.y, row])
	ws.reset()
	await _frames(tree, 2)
	check(not sl.is_visible_in_tree() or sl.text == "", "%s: the step line goes with the steps" % at)

func _inside(r: Rect2, outer: Rect2) -> bool:
	return r.size.x > 0.0 and r.size.y > 0.0 and r.position.x >= outer.position.x - 0.5 and r.position.y >= outer.position.y - 0.5 \
		and r.end.x <= outer.end.x + 0.5 and r.end.y <= outer.end.y + 0.5

## Shown controls whose rectangles must not overlap.
func _apart(at: String, cs: Array) -> void:
	for i in cs.size():
		for j in range(i + 1, cs.size()):
			var a: Control = cs[i]
			var b: Control = cs[j]
			if not a.is_visible_in_tree() or not b.is_visible_in_tree():
				continue
			var ov := a.get_global_rect().grow(-0.5).intersects(b.get_global_rect().grow(-0.5))
			check(not ov, "%s: %s and %s overlap (%s, %s)" % [at, a.name, b.name, a.get_global_rect(), b.get_global_rect()])

## The panel a control is in (the top bar, the tree's, the properties', the bench's, the tools').
func _panel_of(c: Node) -> Control:
	var n := c.get_parent()
	while n != null and not (n is PanelContainer):
		n = n.get_parent()
	return n as Control

func _target(c: Control) -> bool:
	return c is BaseButton or c is Range

## The shown controls that take input (and the labels that don't wrap) under n.
func _controls(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Control and not (c as Control).is_visible_in_tree():
			continue
		if c is BaseButton or c is Range and not c is ScrollBar or (c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF):
			out.append(c)
		if not c is ScrollBar:
			out.append_array(_controls(c))
	return out

func _fonts(n: Node, at: String, least: int) -> void:
	for c in n.get_children():
		if c is Label or c is Button or c is Tree:
			var f: int = (c as Control).get_theme_font_size("font_size")
			check(f >= least, "%s: %s's text is %d px (at least %d)" % [at, c.name, f, least])
		elif c is RichTextLabel:
			var f: int = (c as Control).get_theme_font_size("normal_font_size")
			check(f >= least, "%s: %s's text is %d px (at least %d)" % [at, c.name, f, least])
		_fonts(c, at, least)
