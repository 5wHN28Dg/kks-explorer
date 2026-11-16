## The Workshop's panels (docs/plant3d/WORKSHOP.md §3): the component tree (machine -> subassemblies -> components
## -> fastener groups; selecting in it selects in 3D and the other way round), the properties (name, what it does, its
## material, what it is fastened to, sealed and why), the take-apart slider with the whole machine or the selected
## subassembly, Reassemble all, Hide, Isolate, Show all, Reset, Reset view, and Back to the plant. In a session a
## strip at the top says the plant runs on and counts new alarms. Panels collapse so that the view fills the screen.
##
## Laid out by containers, not fixed offsets (#388, #389): a column filling the screen holds the top bar, the strip,
## the middle row (the tree on the left, the 3D view between, the properties or the bench on the right), the step line
## and the tools. Every size follows the UI's scale (`W.scale`, the size setting of #382): the side panels take at most
## SIDE_MAX of the width each, the tools at most TOOLS_MAX of the height and never so much that the tree and the
## properties keep under MIDDLE_MIN of it (the tools scroll inside instead), the tools' rows wrap, the
## tree's and the properties' long words wrap, and Back to the plant stays in the top bar, never scrolled away.
extends Control

const W = preload("res://ui/widgets.gd")
const RunPanel = preload("res://workshop/run_panel.gd")

const SIDE_W := 380.0           # a side panel's width at scale 1 (canvas px)...
const SIDE_MAX := 0.3           # ...and at most this share of the screen's width
const TOOLS_MAX := 0.4          # the tools' panel: at most this share of the screen's height (it scrolls past it)
const MIDDLE_MIN := 0.35        # the tree's and the properties' row keeps at least this share of the height
const FONT := 20                # the panels' text size at scale 1 (the theme's): nothing smaller (UI-UX-POLICY S1)
const TARGET_H := 52            # a control's height at scale 1, as W.button's

var ws                          # workshop/workshop.gd
var title: Label
var strip: Label
var tree: Tree
var tree_panel: PanelContainer
var props_panel: PanelContainer
var props: RichTextLabel
var note: Label
var slider: HSlider
var only_cb: CheckBox
var back_btn: Button
var manual_btn: Button
var top_bar: PanelContainer     # Back to the plant, the title and the panels' toggles
var middle: HBoxContainer       # the tree, the view's gap, the properties or the bench
var tools_panel: PanelContainer # the tools along the bottom
var tools_scroll: ScrollContainer
var tools_box: VBoxContainer
var step_slot: Control          # the step line's place in the column (the line itself is on step_layer)
var step_label: Label           # the guided steps: the next step's words (WORKSHOP.md §3, §4.6)
var step_layer: CanvasLayer     # step_label's own canvas layer, shown with the panels
var guide_btns: Array = []      # the buttons that start the steps (when the kind's data has an assembly)
var tools: Array = []           # the buttons that need a machine
var run_panel: PanelContainer   # the bench (workshop/run_panel.gd), in the properties' place while shown
var see: Dictionary = {}        # "See inside": name -> its CheckButton, the section's controls
var _items := {}                # id -> TreeItem
var _syncing := false
var _strip_n := -1

## The backing of text drawn over the 3D view (UI-UX-POLICY K5, #390): the panels' own colour.
static func backing() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	sb.set_corner_radius_all(int(8 * W.scale))
	sb.content_margin_left = 14 * W.scale
	sb.content_margin_right = 14 * W.scale
	sb.content_margin_top = 6 * W.scale
	sb.content_margin_bottom = 6 * W.scale
	return sb

func setup(w) -> void:
	ws = w
	# (the offsets too: anchors alone, set once in the tree, keep the old zero size, #388)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = W.make_theme()
	var margin := MarginContainer.new()
	margin.name = "margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(12 * W.scale))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(10 * W.scale))
	add_child(margin)
	var col := VBoxContainer.new()
	col.name = "layout"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	# the top bar: Back to the plant always here, whatever the panels below scroll to (UI-UX-POLICY R1)
	top_bar = PanelContainer.new()
	top_bar.name = "top_bar"
	col.add_child(top_bar)
	var top := HBoxContainer.new()
	top_bar.add_child(top)
	back_btn = W.button("Back to the plant", func(): ws.close())
	back_btn.name = "back"
	top.add_child(back_btn)
	title = W.label("", 24, Color.WHITE, true)
	title.name = "title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size.x = 160 * W.scale
	top.add_child(title)
	var parts_btn := W.button("Parts", func(): tree_panel.visible = not tree_panel.visible)
	parts_btn.name = "parts"
	top.add_child(parts_btn)
	var info_btn := W.button("Info", func(): show_info(not props_panel.visible))
	info_btn.name = "info"
	top.add_child(info_btn)
	var run_btn := W.button("Run", func(): show_run(not run_panel.visible))
	run_btn.name = "run"
	top.add_child(run_btn)
	# the kind's manual (REALISM.md §6.2.1), at the section the next guided step (or the picked part) links to
	manual_btn = W.button("Manual", open_manual)
	manual_btn.name = "manual"
	top.add_child(manual_btn)
	# the tools fold away too, so that the view can fill the screen (WORKSHOP.md §3)
	var tools_btn := W.button("Tools", func(): tools_panel.visible = not tools_panel.visible)
	tools_btn.name = "tools"
	top.add_child(tools_btn)
	strip = W.label("", FONT, Color(1.0, 0.8, 0.4), false)
	strip.name = "strip"
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.add_theme_stylebox_override("normal", backing())
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.visible = false
	col.add_child(strip)
	# the middle row: the tree on the left, the 3D view between (its gap takes no input), the properties on the right
	middle = HBoxContainer.new()
	middle.name = "middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(middle)
	tree_panel = PanelContainer.new()
	tree_panel.name = "tree_panel"
	middle.add_child(tree_panel)
	tree = Tree.new()
	tree.name = "tree"
	tree.hide_root = false
	tree.select_mode = Tree.SELECT_SINGLE
	tree.scroll_horizontal_enabled = false   # (long names wrap instead: _fill_tree)
	tree.item_selected.connect(_on_tree_selected)
	tree.add_theme_font_size_override("font_size", int(FONT * W.scale))
	tree_panel.add_child(tree)
	var gap := Control.new()
	gap.name = "view_gap"
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(gap)
	props_panel = PanelContainer.new()
	props_panel.name = "props_panel"
	middle.add_child(props_panel)
	var ps := ScrollContainer.new()   # (a long text scrolls: it never runs under the tools, #389)
	ps.name = "props_scroll"
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	props_panel.add_child(ps)
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.add_child(pv)
	props = W.rich()
	props.name = "props"
	props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_child(props)
	note = W.label("", FONT, Color(1.0, 0.75, 0.35))
	note.name = "note"
	pv.add_child(note)
	# the bench, in the properties' place
	run_panel = RunPanel.new()
	run_panel.visible = false
	middle.add_child(run_panel)
	run_panel.setup(ws)
	# the step line's place, above the tools (the line itself is drawn on a canvas layer of its own: below)
	step_slot = Control.new()
	step_slot.name = "step_slot"
	step_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	step_slot.visible = false
	col.add_child(step_slot)
	# the tools, along the bottom: rows that wrap, in a panel that scrolls past TOOLS_MAX of the height
	tools_panel = PanelContainer.new()
	tools_panel.name = "tools_panel"
	col.add_child(tools_panel)
	tools_scroll = ScrollContainer.new()
	tools_scroll.name = "tools_scroll"
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tools_scroll.follow_focus = true   # (the D-pad's focus brings its row into view)
	tools_panel.add_child(tools_scroll)
	tools_box = VBoxContainer.new()
	tools_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_scroll.add_child(tools_box)
	var row1 := _row("take_apart")
	row1.add_child(_row_label("Take apart"))
	slider = HSlider.new()
	slider.name = "explode"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.custom_minimum_size = Vector2(320 * W.scale, TARGET_H * W.scale)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): if not _syncing: ws.set_slider(v))
	row1.add_child(slider)
	only_cb = CheckBox.new()
	only_cb.name = "only_selected"
	only_cb.text = "Selected subassembly only"
	only_cb.custom_minimum_size.y = TARGET_H * W.scale
	only_cb.toggled.connect(func(on): ws.set_only_selected(on))
	row1.add_child(only_cb)
	var row2 := _row("handle")
	for b in [["Reassemble all", func(): ws.reassemble()], ["Hide", func(): ws.hide_selected(); refresh()],
			["Isolate", func(): ws.isolate(); refresh()], ["Show all", func(): ws.show_all(); refresh()],
			["Reset", func(): ws.reset()], ["Reset view", func(): ws.cam.reset_view()]]:
		var bt := W.button(b[0], b[1])
		bt.name = String(b[0]).to_lower().replace(" ", "_")
		row2.add_child(bt)
		tools.append(bt)
	var row3 := _row("steps")
	row3.add_child(_row_label("Steps"))
	for b in [["Assemble from exploded", "assemble_exploded", func(): ws.start_guide("assemble", "exploded")],
			["Assemble from a pile", "assemble_pile", func(): ws.start_guide("assemble", "pile")],
			["Take apart step by step", "disassemble", func(): ws.start_guide("disassemble")]]:
		var bt := W.button(b[0], b[2])
		bt.name = b[1]
		row3.add_child(bt)
		tools.append(bt)
		guide_btns.append(bt)
	# what lets the trainee see inside (§3): X-ray, the cutaway, the section plane (its axis, turn and position), flow
	var row4 := _row("see_inside")
	row4.add_child(_row_label("See inside"))
	for b in [["X-ray", "xray", func(on): ws.views.set_xray(on)], ["Cutaway", "cutaway", func(on): ws.views.set_cut(on)],
			["Section", "section", func(on): ws.views.set_section(on)], ["Flow", "flow", func(on): ws.views.flow_on = on],
			["Heat", "heat", func(on): ws.views.heat_on = on], ["Pressure", "pressure", func(on): ws.views.pressure_on = on]]:
		var cb := CheckButton.new()
		cb.name = "see_" + b[1]
		cb.text = b[0]
		cb.custom_minimum_size.y = TARGET_H * W.scale
		cb.toggled.connect(b[2])
		row4.add_child(cb)
		see[b[1]] = cb
	var axis_btn := W.button("Across", func(): _next_axis())
	axis_btn.name = "section_axis"
	row4.add_child(axis_btn)
	see["axis"] = axis_btn
	for k in [["section_turn", 0.0, 180.0, 0.0, func(v): ws.views.set_section_turn(v)],
			["section_at", 0.0, 1.0, 0.5, func(v): ws.views.set_section_at(v)]]:
		var sl := HSlider.new()
		sl.name = k[0]
		sl.min_value = k[1]
		sl.max_value = k[2]
		sl.step = (k[2] - k[1]) / 360.0
		sl.value = k[3]
		sl.custom_minimum_size = Vector2(150 * W.scale, TARGET_H * W.scale)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(k[4])
		row4.add_child(sl)
		see[k[0]] = sl
	# the next step's words, in step_slot's place, on a backing of their own over the 3D view (#390)
	step_label = W.label("", FONT, Color.WHITE)
	step_label.name = "step"
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	step_label.add_theme_stylebox_override("normal", backing())
	step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	step_label.visible = false
	# on a canvas layer of its own, just above the Workshop's: in the panels' layer this wrapped sentence (outlined then)
	# cost about two draw calls a letter (a long assembly step ~440, the pile's view ~510 in all against §8's 300)
	step_layer = CanvasLayer.new()
	step_layer.name = "step_layer"
	step_layer.layer = ws.layer + 1   # (above the panels, as the label was drawn last among them)
	add_child(step_layer)
	step_layer.add_child(step_label)
	get_viewport().size_changed.connect(fit)
	col.sort_children.connect(_put_step)
	fit()

## A row of the tools: it wraps onto a second line where the screen is narrow or the UI large (#389).
func _row(n: String) -> HFlowContainer:
	var r := HFlowContainer.new()
	r.name = n
	r.add_theme_constant_override("h_separation", int(8 * W.scale))
	r.add_theme_constant_override("v_separation", int(8 * W.scale))
	tools_box.add_child(r)
	return r

func _row_label(t: String) -> Label:
	var l := W.label(t, FONT, W.DIM, false)
	l.custom_minimum_size.y = TARGET_H * W.scale
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## Sizes what the containers can't size themselves to the screen: the side panels' width, the step line's height, the
## tools' height. On every change of the screen's size and each frame (the step's words and the tools' wrapping change
## the heights); the step line follows its place as soon as the column is laid out (_put_step).
func fit() -> void:
	if tools_scroll == null:
		return
	var vs := get_viewport_rect().size
	var side := minf(SIDE_W * W.scale, vs.x * SIDE_MAX)
	if tree_panel.custom_minimum_size.x != side:
		tree_panel.custom_minimum_size.x = side
		props_panel.custom_minimum_size.x = side
		run_panel.custom_minimum_size.x = side
	var col: Control = middle.get_parent()
	_size_step(col.size.x)
	# the tools take what they need up to TOOLS_MAX of the height, but leave the middle row MIDDLE_MIN of it (at a large
	# UI on a phone the tools scroll rather than squeeze the tree and the properties to a sliver)
	var others := 0.0
	var sep := float(col.get_theme_constant("separation"))
	for c in col.get_children():
		if c != middle and c != tools_panel and (c as Control).visible:
			others += (c as Control).get_combined_minimum_size().y + sep
	var frame := tools_panel.get_combined_minimum_size().y - tools_scroll.custom_minimum_size.y   # (its margins)
	var room := col.size.y - others - sep - frame - vs.y * MIDDLE_MIN
	var want := minf(tools_box.get_combined_minimum_size().y, minf(vs.y * TOOLS_MAX, maxf(room, TARGET_H * W.scale)))
	if not is_equal_approx(tools_scroll.custom_minimum_size.y, want):
		tools_scroll.custom_minimum_size.y = want
	_put_step()

## The step line's place: shown while there are words (its height the wrapped words' at the column's width).
func _size_step(wdt: float) -> void:
	var on := step_label.text != ""
	if step_slot.visible != on:
		step_slot.visible = on
	if step_label.visible != on:
		step_label.visible = on
	if not on or wdt <= 0.0:
		return
	if step_label.size.x != wdt:
		step_label.size = Vector2(wdt, 0)
	var h := step_label.get_minimum_size().y
	if step_slot.custom_minimum_size.y != h:
		step_slot.custom_minimum_size.y = h

## The step line drawn where its place is now (also called when the column has just been laid out).
func _put_step() -> void:
	if not step_label.visible or step_slot.size.x <= 0.0:
		return
	step_label.position = step_slot.global_position
	step_label.size = Vector2(step_slot.size.x, step_slot.custom_minimum_size.y)

## The kind's manual: at the section the next guided step's component links to, else the picked part's, else its
## start (REALISM.md §6.2.1). False when there is none.
func open_manual() -> bool:
	if ws.ui == null or not ws.ui.has_method("manual_of_kind"):
		return false
	var man: String = ws.ui.manual_of_kind(ws.part)
	if man == "":
		return false
	var sec := ""
	var place := ""
	if ws.guide.on() and ws.guide.next_step() >= 0:
		place = String(ws.guide.steps[ws.guide.next_step()].place)
	elif ws.selected != "":
		place = ws.selected
	if place != "":
		var at: Array = ws.ui.manuals.for_step(ws.part, place)
		if not at.is_empty() and at[0] == man:
			sec = String(at[1])
	return ws.ui.open_manual(man, sec, ws.from_code)

## While the scene loads (or when it could not).
func loading(what: String) -> void:
	title.text = what
	props.text = ""
	note.text = "Loading…" if not what.begins_with("The Workshop could not") else what
	tree.clear()
	_items.clear()
	for b in tools:
		b.disabled = true
	slider.editable = false

func machine_shown() -> void:
	var w: Dictionary = ws.words
	var top_name: String = ws.title_of(ws.part)
	title.text = top_name + ("  ·  " + ws.from_code if ws.from_code != "" else "")
	note.text = ""
	for b in tools:
		b.disabled = false
	var has_steps: bool = not ws.words.get("assembly", []).is_empty()
	for b in guide_btns:
		b.disabled = not has_steps
	slider.editable = true
	manual_btn.visible = ws.ui != null and ws.ui.has_method("manual_of_kind") and ws.ui.manual_of_kind(ws.part) != ""
	_strip_n = -1
	only_cb.set_pressed_no_signal(false)
	sync_slider()
	_fill_tree(top_name, w)
	selected_changed()
	refresh()
	run_panel.machine_shown()
	_sync_see()
	see["cutaway"].disabled = not ws.views.has_cutaway()

## The See inside controls as the views have them (a new machine starts with everything off, flow on).
func _sync_see() -> void:
	see["xray"].set_pressed_no_signal(ws.views.xray)
	see["cutaway"].set_pressed_no_signal(ws.views.cut)
	see["section"].set_pressed_no_signal(ws.views.section)
	see["flow"].set_pressed_no_signal(ws.views.flow_on)
	see["heat"].set_pressed_no_signal(ws.views.heat_on)
	see["pressure"].set_pressed_no_signal(ws.views.pressure_on)
	see["axis"].text = ["Across", "Along", "Up"][ws.views.section_axis]

func _next_axis() -> void:
	ws.views.set_section_axis(ws.views.section_axis + 1)
	_sync_see()

func show_run(on: bool) -> void:
	run_panel.visible = on
	if on:
		props_panel.visible = false

func show_info(on: bool) -> void:
	props_panel.visible = on
	if on:
		run_panel.visible = false

func _fill_tree(top_name: String, w: Dictionary) -> void:
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	root.set_text(0, top_name)
	root.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
	root.set_metadata(0, "")
	for id in ws.spec.order:
		var parent: String = ws.spec.comps[id].parent
		var pi: TreeItem = _items.get(parent, root)
		var it := tree.create_item(pi)
		it.set_text(0, String(w.get("components", {}).get(id, {}).get("name", id)))
		it.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)   # (a long name wraps, never cut short: #389)
		it.set_metadata(0, id)
		_items[id] = it
	for g in ws.spec.groups:
		var host: String = ws.spec.groups[g].host
		var it := tree.create_item(_items.get(host, root))
		it.set_text(0, String(w.get("fasteners", {}).get(g, {}).get("name", g)))
		it.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		it.set_metadata(0, g)
		_items[g] = it

func _on_tree_selected() -> void:
	if _syncing:
		return
	var it := tree.get_selected()
	if it == null:
		return
	ws.select(String(it.get_metadata(0)))

## The selection changed (from the view or the tree): the tree follows, and the properties show it.
func selected_changed() -> void:
	var id: String = ws.selected
	_syncing = true
	if id != "" and _items.has(id):
		var it: TreeItem = _items[id]
		var p := it.get_parent()
		while p != null:
			p.collapsed = false
			p = p.get_parent()
		it.select(0)
		tree.scroll_to_item(it)
	else:
		tree.deselect_all()
	_syncing = false
	props.text = properties(id)
	note.text = ws.note

## The properties of a component or fastener group, as text (BBCode).
func properties(id: String) -> String:
	var w: Dictionary = ws.words
	var cw: Dictionary = w.get("components", {})
	var fw: Dictionary = w.get("fasteners", {})
	if id == "":
		return "[b]%s[/b]\nPick a part in the view or in the list. Drag to turn the view, right-drag or two fingers to move it, the wheel or a pinch to zoom; double-click a part to frame it." % ws.title_of(ws.part)
	if fw.has(id):
		var f: Dictionary = fw[id]
		var names := PackedStringArray()
		for j in f.get("joins", []):
			names.append(String(cw.get(j, {}).get("name", j)))
		if f.has("beyond"):   # what it joins outside this machine
			names.append(String(f.beyond))
		return "[b]%s[/b]\nJoins: %s." % [f.get("name", id), ", ".join(names)]
	var c: Dictionary = cw.get(id, {})
	var out := "[b]%s[/b]\n%s\n[color=#bbbbbb]Material:[/color] %s" % [c.get("name", id), c.get("does", ""), c.get("material", "")]
	var held := PackedStringArray()
	for g in fw:
		var joins: Array = fw[g].get("joins", [])
		if id in joins:
			var others := PackedStringArray()
			for j in joins:
				if j != id:
					others.append(String(cw.get(j, {}).get("name", j)))
			if fw[g].has("beyond"):
				others.append(String(fw[g].beyond))
			held.append("%s (to %s)" % [fw[g].get("name", g), ", ".join(others)])
	if not held.is_empty():
		out += "\n[color=#bbbbbb]Fastened by:[/color] " + "; ".join(held)
	if c.get("sealed", false):
		out += "\n[color=#bbbbbb]Sealed:[/color] " + String(c.get("sealed_why", ""))
	return out

func sync_slider() -> void:
	_syncing = true
	slider.set_value_no_signal(ws.s)
	_syncing = false

func refresh() -> void:
	for id in _items:
		var it: TreeItem = _items[id]
		var loose: bool = ws.guide.on() and ws.guide.loose.has(id)
		it.set_custom_color(0, Color(0.55, 0.55, 0.55) if ws.hidden.has(id) else (Color(1.0, 0.8, 0.45) if loose else Color.WHITE))
	if step_label != null:
		step_label.text = ws.step_words()
	slider.editable = ws.machine != null and not ws.guide.on()   # (the slider waits while the steps are on)

## A canvas layer under a Control doesn't follow its visibility: the step words' layer follows the panels'.
func _process(_d: float) -> void:
	if step_layer != null:
		var on: bool = is_visible_in_tree() and ws.visible
		if step_layer.visible != on:
			step_layer.visible = on
		if on:
			fit()

## Each frame: the bench's panel, the session's strip.
func tick() -> void:
	run_panel.tick()
	if not ws._session:
		strip.visible = false
		return
	if not ws.session_on():   # the session ended while the Workshop showed (its notice waits in the plant)
		if _strip_n != -2:
			_strip_n = -2
			strip.visible = true
			strip.text = "The session has ended: Back to the plant."
		return
	var n: int = ws.new_alarms()
	if n == _strip_n:
		return
	_strip_n = n
	strip.visible = true
	strip.text = "The plant runs on (a session)." + ("  %d new alarm%s: Back to the plant." % [n, "" if n == 1 else "s"] if n > 0 else "")
