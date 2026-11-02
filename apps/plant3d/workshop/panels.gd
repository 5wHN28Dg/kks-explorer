## The Workshop's panels (docs/plant3d/WORKSHOP.md §3): the component tree (machine -> subassemblies -> components
## -> fastener groups; selecting in it selects in 3D and the other way round), the properties (name, what it does, its
## material, what it is fastened to, sealed and why), the take-apart slider with the whole machine or the selected
## subassembly, Reassemble all, Hide, Isolate, Show all, Reset, Reset view, and Back to the plant. In a session a
## strip at the top says the plant runs on and counts new alarms. Panels collapse so that the view fills the screen.
extends Control

const W = preload("res://ui/widgets.gd")

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
var tools: Array = []           # the buttons that need a machine
var _items := {}                # id -> TreeItem
var _syncing := false
var _strip_n := -1

func setup(w) -> void:
	ws = w
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = W.make_theme()
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12 * W.scale
	top.offset_top = 10 * W.scale
	top.offset_right = -12 * W.scale
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	back_btn = W.button("Back to the plant", func(): ws.close())
	back_btn.name = "back"
	top.add_child(back_btn)
	title = W.label("", 24, Color.WHITE, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	top.add_child(title)
	var parts_btn := W.button("Parts", func(): tree_panel.visible = not tree_panel.visible)
	parts_btn.name = "parts"
	top.add_child(parts_btn)
	var info_btn := W.button("Info", func(): props_panel.visible = not props_panel.visible)
	info_btn.name = "info"
	top.add_child(info_btn)
	strip = W.label("", 18, Color(1.0, 0.8, 0.4), false)
	strip.name = "strip"
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = 72 * W.scale
	strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.add_theme_constant_override("outline_size", 6)
	strip.add_theme_color_override("font_outline_color", Color.BLACK)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.visible = false
	add_child(strip)
	# the tree, on the left
	tree_panel = PanelContainer.new()
	tree_panel.name = "tree_panel"
	tree_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	tree_panel.offset_left = 12 * W.scale
	tree_panel.offset_top = 104 * W.scale
	tree_panel.offset_bottom = -150 * W.scale
	tree_panel.offset_right = 380 * W.scale
	add_child(tree_panel)
	tree = Tree.new()
	tree.name = "tree"
	tree.hide_root = false
	tree.select_mode = Tree.SELECT_SINGLE
	tree.item_selected.connect(_on_tree_selected)
	tree.add_theme_font_size_override("font_size", int(18 * W.scale))
	tree_panel.add_child(tree)
	# the properties, on the right
	props_panel = PanelContainer.new()
	props_panel.name = "props_panel"
	props_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	props_panel.offset_left = -420 * W.scale
	props_panel.offset_right = -12 * W.scale
	props_panel.offset_top = 104 * W.scale
	props_panel.offset_bottom = -150 * W.scale
	add_child(props_panel)
	var pv := VBoxContainer.new()
	props_panel.add_child(pv)
	props = W.rich()
	props.name = "props"
	pv.add_child(props)
	note = W.label("", 18, Color(1.0, 0.75, 0.35))
	note.name = "note"
	pv.add_child(note)
	# the tools, along the bottom
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12 * W.scale
	bottom.offset_right = -12 * W.scale
	bottom.offset_top = -138 * W.scale
	bottom.offset_bottom = -10 * W.scale
	add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	var row1 := HBoxContainer.new()
	bv.add_child(row1)
	row1.add_child(W.label("Take apart", 18, W.DIM, false))
	slider = HSlider.new()
	slider.name = "explode"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.custom_minimum_size = Vector2(320 * W.scale, 44 * W.scale)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): if not _syncing: ws.set_slider(v))
	row1.add_child(slider)
	only_cb = CheckBox.new()
	only_cb.name = "only_selected"
	only_cb.text = "Selected subassembly only"
	only_cb.toggled.connect(func(on): ws.set_only_selected(on))
	row1.add_child(only_cb)
	var row2 := HBoxContainer.new()
	bv.add_child(row2)
	for b in [["Reassemble all", func(): ws.reassemble()], ["Hide", func(): ws.hide_selected(); refresh()],
			["Isolate", func(): ws.isolate(); refresh()], ["Show all", func(): ws.show_all(); refresh()],
			["Reset", func(): ws.reset()], ["Reset view", func(): ws.cam.reset_view()]]:
		var bt := W.button(b[0], b[1])
		bt.name = String(b[0]).to_lower().replace(" ", "_")
		row2.add_child(bt)
		tools.append(bt)

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
	slider.editable = true
	only_cb.set_pressed_no_signal(false)
	sync_slider()
	_fill_tree(top_name, w)
	selected_changed()
	refresh()

func _fill_tree(top_name: String, w: Dictionary) -> void:
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	root.set_text(0, top_name)
	root.set_metadata(0, "")
	for id in ws.spec.order:
		var parent: String = ws.spec.comps[id].parent
		var pi: TreeItem = _items.get(parent, root)
		var it := tree.create_item(pi)
		it.set_text(0, String(w.get("components", {}).get(id, {}).get("name", id)))
		it.set_metadata(0, id)
		_items[id] = it
	for g in ws.spec.groups:
		var host: String = ws.spec.groups[g].host
		var it := tree.create_item(_items.get(host, root))
		it.set_text(0, String(w.get("fasteners", {}).get(g, {}).get("name", g)))
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
		it.set_custom_color(0, Color(0.55, 0.55, 0.55) if ws.hidden.has(id) else Color.WHITE)

## Each frame: the session's strip.
func tick() -> void:
	if not ws._session:
		strip.visible = false
		return
	var n: int = ws.new_alarms()
	if n == _strip_n:
		return
	_strip_n = n
	strip.visible = true
	strip.text = "The plant runs on (a session)." + ("  %d new alarm%s: Back to the plant." % [n, "" if n == 1 else "s"] if n > 0 else "")
