## The Workshop's panels laid out on the screens they are used on (#388, #389, #390; docs/UI-UX-POLICY.md T1, T3, R1,
## S1, S2, L2, K5), for every kind the build has:
## - on a desktop (1600 × 900 canvas) and on the Note 9 (2220 × 1080 at 420 dpi: a 1850 × 900 canvas), each at the UI
##   scale it has today and at 150 % of it (the UI size setting of #382: 1.0, 1.5, 1.35, 2.025);
## - the panels fill the screen; the top bar with Back to the plant, the parts tree, the properties, the bench and the
##   tools are shown, inside the screen, apart, and big enough to use (the tree three rows high or more, the side
##   panels at least SIDE_MIN wide, the tools a row high);
## - no control is squeezed below its own size or cut at the screen's edge, and each can be scrolled into view;
## - no text in the panels is under the theme's size, and the words drawn over the 3D view (the step line, the
##   session's strip) have a backing of their own;
## - a long properties text scrolls inside its panel; the guided steps are reachable and start, their line shown
##   between the panels and the tools, over none of them.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const W = preload("res://ui/widgets.gd")

## [name, the window's size in pixels (the canvas is 1600 × 900 stretched, expanded to its shape), the UI scale]
const SCREENS := [
	["desktop", Vector2i(1600, 900), 1.0],
	["desktop at 150 %", Vector2i(1600, 900), 1.5],
	["Note 9", Vector2i(2220, 1080), 1.35],
	["Note 9 at 150 %", Vector2i(2220, 1080), 2.025],
]
const SIDE_MIN := 300.0          # a side panel's least width (canvas px) on these screens
const ROWS := 4                  # the tree and the properties show at least this many rows of text
const TARGET_H := 52             # a control's height at scale 1 (W.button's)
const FONT := 20                 # the panels' least text size at scale 1 (the theme's)

var p: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		p.append(what)

func run(tree: SceneTree) -> Array:
	var main := App.start(tree)
	if main.workshop == null:
		main.free()
		return ["the app did not start with its Workshop"]
	await tree.process_frame
	var ws = main.workshop
	var size0: Vector2i = tree.root.size
	var scale0: float = W.scale
	var kinds: Array = ws.kinds()
	check(not kinds.is_empty(), "the build has Workshop kinds")
	for kind in kinds:
		check(ws.open(kind), "%s: the Workshop opens" % kind)
		if not await _wait_shown(tree, ws):
			check(false, "%s: the machine did not show" % kind)
			continue
		for sc in SCREENS:
			tree.root.size = sc[1]
			W.scale = sc[2]
			ws.make_panels()
			await _frames(tree, 3)
			var at := "%s, %s" % [kind, sc[0]]
			await _layout(tree, ws, at)
			await _steps(tree, ws, at)
		ws.close()
		await ws.left
	tree.root.size = size0
	W.scale = scale0
	for i in 3:   # (not while the last close's signal is still being sent; the panels made last freed first)
		await tree.process_frame
	main.free()
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
	check(row > 0.0 and pn.tree.size.y >= ROWS * row, "%s: the parts tree shows %d rows or more (%.0f px high, a row %.0f)" % [at, ROWS, pn.tree.size.y, row])
	check(pn.props_panel.size.y >= ROWS * row, "%s: the properties are %d rows high or more (%.0f)" % [at, ROWS, pn.props_panel.size.y])
	check(pn.tools_scroll.size.y >= TARGET_H * s - 1.0, "%s: the tools show a row at least (%.0f px)" % [at, pn.tools_scroll.size.y])
	_apart(at, [pn.top_bar, pn.tree_panel, pn.props_panel, pn.tools_panel])
	# Back to the plant: always in the top bar, whole, in the screen (R1)
	check(pn.back_btn.is_visible_in_tree() and _inside(pn.back_btn.get_global_rect(), screen)
		and pn.top_bar.is_ancestor_of(pn.back_btn), "%s: Back to the plant is in the top bar, on the screen" % at)
	# every control whole (never squeezed below its own size, never cut at the edge), and reachable by scrolling
	for c in _controls(pn):
		var m: Vector2 = c.get_combined_minimum_size()
		check(c.size.x >= m.x - 0.5 and c.size.y >= m.y - 0.5, "%s: %s is squeezed (%s, needs %s)" % [at, c.name, c.size, m])
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
		and pn.run_panel.size.y >= ROWS * row, "%s: the bench's panel shows, inside the screen (%s)" % [at, pn.run_panel.get_global_rect()])
	_apart(at, [pn.top_bar, pn.tree_panel, pn.run_panel, pn.tools_panel])
	pn.show_info(true)
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
	var mn: Vector2 = sl.get_minimum_size()
	check(sl.size.y >= mn.y - 0.5, "%s: the step line shows all its words (%s, needs %s)" % [at, sl.size, mn])
	_apart(at, [sl, pn.top_bar, pn.tree_panel, pn.props_panel, pn.tools_panel])
	var fs: int = pn.tree.get_theme_font_size("font_size")
	var row: float = pn.tree.get_theme_font("font").get_height(fs) + pn.tree.get_theme_constant("v_separation")
	check(pn.tree.size.y >= ROWS * row and pn.props_panel.size.y >= ROWS * row, "%s: with the step line the tree and the properties still show %d rows (%.0f, %.0f px; a row %.0f)" % [
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
