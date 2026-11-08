## The manual reader (docs/plant3d/REALISM.md §6.2.1): a manual's sections one page at a time, on paper, full screen
## on a canvas layer above the Workshop's, with the 3D view under it off while it shows (as the drawings). The contents
## beside the page; Back after a link; Close (or Escape, B). Opened from the card ("Manual"), from the work view and
## from the Workshop. Links go to another section or manual, to a code's card, to the work view's action at the
## equipment, or to the Workshop's step.
extends CanvasLayer

const W = preload("res://ui/widgets.gd")
const PAPER := Color(0.97, 0.96, 0.93)
const INK := Color(0.12, 0.12, 0.14)
const FAINT := Color(0.38, 0.38, 0.42)
const LINK := Color(0.08, 0.32, 0.66)
const RULE := Color(0.80, 0.79, 0.76)
const CALLOUT := {"warning": Color(0.80, 0.18, 0.12), "caution": Color(0.85, 0.55, 0.05), "note": Color(0.20, 0.42, 0.70)}

signal opened(manual: String, section: String)

var ui                          # ui/plant_ui.gd
var manuals                     # ui/manuals.gd
var man_id := ""
var section := ""
var code := ""                  # the equipment it was opened from ("" none): its own data in the `unit` block
var history: Array = []         # [[manual, section]] for Back
var open_ms := 0.0              # the last page's build, ms
var page_ms := {}               # "manual#section" -> its longest build, ms (walk=manuals)
var last_note := ""             # the last sentence shown (a link that could not be followed), for the tests
var root: Control
var title: Label
var back_btn: Button
var contents: VBoxContainer
var scroll: ScrollContainer
var page: VBoxContainer
var note: Label
var _links: Array = []          # the page's link targets, by index (the BBCode's url)
var _prev_3d := false
var _prev_ws_update := -1


func setup(u, m) -> void:
	ui = u
	manuals = m
	layer = 70                  # above the Workshop (60)
	visible = false
	root = Control.new()
	root.name = "manual"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_top = 12
	v.offset_right = -16
	v.offset_bottom = -12
	root.add_child(v)
	var bar := HBoxContainer.new()
	v.add_child(bar)
	back_btn = W.button("Back", back)
	back_btn.name = "back"
	bar.add_child(back_btn)
	title = W.label("", 24, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(title)
	var close_btn := W.button("Close", close)
	close_btn.name = "close"
	bar.add_child(close_btn)
	note = W.label("", 18, CALLOUT["warning"])
	note.name = "note"
	note.visible = false
	v.add_child(note)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", int(18 * W.scale))
	v.add_child(h)
	var cs := ScrollContainer.new()
	cs.name = "contents"
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cs.custom_minimum_size.x = 300 * W.scale
	h.add_child(cs)
	contents = VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cs.add_child(contents)
	scroll = ScrollContainer.new()
	scroll.name = "page"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", int(12 * W.scale))
	scroll.add_child(page)
	root.get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vs := root.get_viewport_rect().size
	# the contents take less of a narrow screen (a phone held upright)
	contents.get_parent().custom_minimum_size.x = minf(300.0 * W.scale, vs.x * 0.28)


func is_open() -> bool:
	return visible


## Opens a manual at a section ("" its first), from a code ("" none). False when there is no such manual.
func open(id: String, sec := "", from_code := "") -> bool:
	if manuals == null or manuals.manual(id).is_empty():
		return false
	if not visible:
		history.clear()
		code = from_code
		_cover(true)
		# the control that opened it (a card's button) keeps no focus under the reader: Space would press it again
		root.get_viewport().gui_release_focus()
	else:
		if man_id != "":
			history.append([man_id, section])
		if from_code != "":
			code = from_code
	_show(id, sec)
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	_cover(false)
	man_id = ""
	section = ""
	history.clear()
	manuals.forget_figures()            # (decoded again when next shown: the memory goes with the reader)
	if ui != null and ui.main != null and ui.main.hud != null:
		ui.main.hud.refresh()
	if ui != null and ui.has_method("drawings_open") and ui.drawings_open():
		ui.drawing_view.take_focus()    # the drawings' keys again, where the reader was opened from a card on them


func back() -> void:
	if history.is_empty():
		close()
		return
	var h: Array = history.pop_back()
	_show(String(h[0]), String(h[1]))


## The 3D drawing under the reader off while it shows (the main view's, and the Workshop's own view), as it was after.
func _cover(on: bool) -> void:
	var vp := root.get_viewport()
	var ws = ui.main.workshop if ui != null and ui.main != null and "workshop" in ui.main else null
	if on:
		visible = true
		_prev_3d = vp.disable_3d
		vp.disable_3d = true
		_prev_ws_update = -1
		if ws != null and ws.is_open and ws.vp != null:
			_prev_ws_update = ws.vp.render_target_update_mode
			ws.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if ui != null and ui.main != null and ui.main.hud != null:
			ui.main.hud.refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		vp.disable_3d = _prev_3d
		if ws != null and ws.vp != null and _prev_ws_update >= 0:
			ws.vp.render_target_update_mode = _prev_ws_update
		_prev_ws_update = -1


## Esc and gamepad B go Back, then close; Start closes (before the Workshop's and the plant's keys see them: Godot's
## ui_cancel has no gamepad button). The D-pad moves between the reader's buttons; the left stick, Page Up and Down
## scroll the page.
func _input(ev: InputEvent) -> void:
	if not visible:
		return
	var b_btn: bool = ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_B and ev.pressed
	# (Escape is bound to `menu` too, app/controls.gd: ui_cancel is asked first, so it goes Back; Start alone closes)
	var go_back: bool = ev.is_action_pressed("ui_cancel") or b_btn
	if go_back or ev.is_action_pressed("menu"):
		if go_back and not history.is_empty():
			back()
		else:
			close()
		root.get_viewport().set_input_as_handled()
		return
	if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A and ev.pressed:
		var fo := root.get_viewport().gui_get_focus_owner()
		if fo is Button and root.is_ancestor_of(fo):
			(fo as Button).pressed.emit()
			root.get_viewport().set_input_as_handled()
		return
	var page := int(scroll.size.y * 0.9)
	if ev is InputEventKey and ev.pressed and ev.keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		scroll.scroll_vertical += page if ev.keycode == KEY_PAGEDOWN else -page
		root.get_viewport().set_input_as_handled()
	elif ev is InputEventJoypadMotion and ev.axis == JOY_AXIS_LEFT_Y:
		root.get_viewport().set_input_as_handled()   # (scrolled in _process: the stick's position, not its events)


func _process(delta: float) -> void:
	if not visible:
		return
	var y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y) if not Input.get_connected_joypads().is_empty() else 0.0
	if absf(y) > 0.2:
		scroll.scroll_vertical += int(y * 1600.0 * W.scale * delta)


## A gamepad's focus: the current section's button in the contents.
func take_focus() -> void:
	for b in contents.get_children():
		if (b as Button).button_pressed:
			(b as Button).grab_focus()
			return


func _show(id: String, sec: String) -> void:
	var t0 := Time.get_ticks_usec()
	var m: Dictionary = manuals.manual(id)
	var secs: Array = m["sections"]
	if sec == "" or not secs.any(func(s): return s["id"] == sec):
		sec = String(secs[0]["id"])
	var new_manual := id != man_id
	man_id = id
	section = sec
	title.text = "%s  %s" % [m["number"], m["title"]]
	back_btn.visible = not history.is_empty()
	note.visible = false
	if new_manual or contents.get_child_count() == 0:
		W.clear(contents)
		for s in secs:
			var sid := String(s["id"])
			var b := W.button(_plain(s["title"]), func(): go(sid))
			b.name = "sec_" + sid
			b.toggle_mode = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			contents.add_child(b)
	_mark_contents()
	_build_page(m, sec)
	scroll.scroll_vertical = 0
	open_ms = (Time.get_ticks_usec() - t0) / 1000.0
	opened.emit(id, sec)
	if ui != null and ui.has_method("wants_focus") and ui.wants_focus():
		take_focus()
	# to the page's first frame (its text laid out and shaped then): what the reader waits for
	var key := id + "#" + sec
	await root.get_tree().process_frame
	if man_id == id and section == sec:
		var shown := (Time.get_ticks_usec() - t0) / 1000.0
		page_ms[key] = maxf(shown, float(page_ms.get(key, 0.0)))


func _mark_contents() -> void:
	for b in contents.get_children():
		(b as Button).set_pressed_no_signal(b.name == "sec_" + section)


## To a section of this manual (Back returns).
func go(sec: String) -> void:
	if sec == section:
		_mark_contents()                # (a press on the current section's button toggled it off)
		return
	history.append([man_id, section])
	_show(man_id, sec)


func _build_page(m: Dictionary, sec: String) -> void:
	W.clear(page)
	_links.clear()
	var s: Dictionary = {}
	var at := 0
	for i in m["sections"].size():
		if m["sections"][i]["id"] == sec:
			s = m["sections"][i]
			at = i
	page.add_child(_rich("[font_size=%d][b]%s[/b][/font_size]" % [int(30 * W.scale), _bb(s["title"])]))
	for b in s["blocks"]:
		var c := _block(b, m)
		if c != null:
			page.add_child(c)
	if not s.get("src", []).is_empty():
		var cites: Array = []
		for sid in s["src"]:
			for src in m["sources"]:
				if src["id"] == sid:
					cites.append("• " + _esc(String(src["cite"])))
		page.add_child(_rule())
		page.add_child(_rich("[font_size=%d][color=#%s]This section follows, in our own words:\n%s[/color][/font_size]" % [
			int(15 * W.scale), FAINT.to_html(false), "\n".join(cites)]))
	var nav := HBoxContainer.new()
	page.add_child(nav)
	if at > 0:
		var prev_id := String(m["sections"][at - 1]["id"])
		var pb := W.button("← " + _plain(m["sections"][at - 1]["title"]), func(): go(prev_id))
		pb.name = "prev"
		nav.add_child(pb)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(gap)
	if at < m["sections"].size() - 1:
		var next_id := String(m["sections"][at + 1]["id"])
		var nb := W.button(_plain(m["sections"][at + 1]["title"]) + " →", func(): go(next_id))
		nb.name = "next"
		nav.add_child(nb)


func _block(b: Dictionary, m: Dictionary) -> Control:
	if b.has("h"):
		return _rich("[font_size=%d][b]%s[/b][/font_size]" % [int(23 * W.scale), _bb(b["h"])])
	if b.has("p"):
		return _rich(_bb(b["p"]))
	if b.has("ul") or b.has("ol"):
		var items: Array = b["ul"] if b.has("ul") else b["ol"]
		var lines: Array = []
		for i in items.size():
			lines.append(("•  " if b.has("ul") else "%d.  " % (i + 1)) + _bb(items[i]))
		var r := _rich("[indent]" + "\n".join(lines) + "[/indent]")
		r.add_theme_constant_override("line_separation", int(6 * W.scale))
		return r
	if b.has("table"):
		var rows: Array = []
		for r in b["table"]["rows"]:
			rows.append(r)
		return _table(b["table"]["head"], rows)
	if b.has("trouble"):
		var rows: Array = []
		for r in b["trouble"]:
			rows.append([r["symptom"], r["cause"], r["remedy"]])
		var t := _table([["Symptom"], ["Possible cause"], ["Remedy"]], rows)
		t.name = "trouble"
		return t
	if b.has("callout"):
		var col: Color = CALLOUT.get(String(b["callout"]), FAINT)
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lerp(PAPER, 0.88)
		sb.border_color = col
		sb.border_width_left = int(6 * W.scale)
		sb.content_margin_left = 14 * W.scale
		sb.content_margin_right = 10 * W.scale
		sb.content_margin_top = 8 * W.scale
		sb.content_margin_bottom = 8 * W.scale
		p.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		p.add_child(v)
		v.add_child(_rich("[b][color=#%s]%s[/color][/b]" % [col.darkened(0.2).to_html(false), _bb(b["label"])]))
		for x in b["body"]:
			var c := _block(x, m)
			if c != null:
				v.add_child(c)
		return p
	if b.has("figure"):
		for f in m["figures"]:
			if f["id"] == b["figure"]:
				return _figure(f)
		return null
	if b.get("unit", false) == true:
		return _unit(m)
	return null


func _figure(f: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.name = "figure_" + String(f["id"])
	var tex: Texture2D = manuals.figure(String(f["file"]))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# the page's width (before its first layout, from the screen less the contents)
		var pw := scroll.size.x - 24.0
		if pw < 100.0:
			pw = root.get_viewport_rect().size.x - (contents.get_parent() as Control).custom_minimum_size.x - 80.0
		pw = maxf(pw, 320.0)
		var w := minf(pw, float(f["w"]) * W.scale)
		tr.custom_minimum_size = Vector2(w, w * float(f["h"]) / float(f["w"]))
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(tr)
	v.add_child(_rich("[font_size=%d][color=#%s][i]%s[/i][/color][/font_size]" % [int(17 * W.scale),
		FAINT.to_html(false), _bb(f["caption"])]))
	return v


## The opened code's own data: its kind and parameters (or what the block is for, when opened without a code).
func _unit(m: Dictionary) -> Control:
	var u: Dictionary = manuals.units.get(code, {})
	if code == "" or u.get("manual", "") != m["id"]:
		return _rich("[i][color=#%s]Opened from an equipment card, this shows that unit's own data.[/color][/i]" % FAINT.to_html(false))
	var rows: Array = [[["Code"], [code]], [["Name"], [ui.info.name_of(code) if ui != null and ui.info != null else ""]],
		[["Kind"], [String(u["kind"])]]]
	for r in u["rows"]:
		rows.append([[String(r[0])], [String(r[1])]])
	var t := _table([["This unit"], [""]], rows)
	t.name = "unit"
	return t


func _table(head: Array, rows: Array) -> Control:
	var g := GridContainer.new()
	g.columns = head.size()
	g.add_theme_constant_override("h_separation", int(14 * W.scale))
	g.add_theme_constant_override("v_separation", int(6 * W.scale))
	for h in head:
		var c := _rich("[b]%s[/b]" % _bb(h))
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size.x = 80 * W.scale
		g.add_child(c)
	for r in rows:
		for cell in r:
			var c := _rich(_bb(cell))
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.custom_minimum_size.x = 80 * W.scale
			g.add_child(c)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER.darkened(0.03)
	sb.border_color = RULE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10 * W.scale)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(g)
	return p


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = RULE
	r.custom_minimum_size = Vector2(0, maxf(1.0, W.scale))
	return r


func _rich(bb: String) -> RichTextLabel:
	var r := W.rich()
	r.add_theme_color_override("default_color", INK)
	r.add_theme_font_size_override("normal_font_size", int(20 * W.scale))
	r.add_theme_font_size_override("bold_font_size", int(20 * W.scale))
	r.add_theme_font_size_override("italics_font_size", int(20 * W.scale))
	r.add_theme_font_size_override("mono_font_size", int(19 * W.scale))
	r.meta_clicked.connect(_on_meta)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.text = bb
	return r


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


## A run (COURSES.md §3) as BBCode; its links numbered into _links.
func _bb(run) -> String:
	if run is String:
		return _esc(run)
	var out := ""
	for it in run:
		if it is String:
			out += _esc(it)
		elif it.has("b"):
			out += "[b]" + _bb(it["b"]) + "[/b]"
		elif it.has("i"):
			out += "[i]" + _bb(it["i"]) + "[/i]"
		elif it.has("small"):
			out += "[font_size=%d]%s[/font_size]" % [int(16 * W.scale), _bb(it["small"])]
		elif it.has("num"):
			# kept on one line (COURSES.md §3): its spaces don't break
			out += "[code]" + _esc(String(it["num"])).replace(" ", "\u00a0") + "[/code]"
		elif it.has("link"):
			_links.append(it["to"])
			out += "[url=%d][color=#%s][u]%s[/u][/color][/url]" % [_links.size() - 1, LINK.to_html(false), _bb(it["link"])]
	return out


## A run's words without markup (the contents' buttons).
static func _plain(run) -> String:
	if run is String:
		return run
	var out := ""
	for it in run:
		if it is String:
			out += it
		else:
			for k in ["b", "i", "small", "link"]:
				if it.has(k):
					out += _plain(it[k])
			if it.has("num"):
				out += String(it["num"])
	return out


func _on_meta(meta) -> void:
	var i := int(str(meta))
	if i >= 0 and i < _links.size():
		follow(_links[i])


## Follows a link's target (REALISM.md §6.2.1).
func follow(t: Dictionary) -> void:
	if t.has("section") and not t.has("manual"):
		go(String(t["section"]))
	elif t.has("manual"):
		if manuals.has(String(t["manual"])):
			open(String(t["manual"]), String(t.get("section", "")))
	elif t.has("kks"):
		var c := String(t["kks"])
		close()
		if ui != null:
			if ui.main != null and ui.main.workshop_open():
				ui.main.workshop.close()
			ui.open_card(c)
	elif t.has("work"):
		_follow_work(String(t["work"]))
	elif t.has("workshop"):
		_follow_workshop(String(t["workshop"]), String(t["place"]))


func _say(text: String) -> void:
	last_note = text
	note.text = text
	note.visible = true


## A work view action: at the equipment the manual was opened from, when the trainee can work on it there.
func _follow_work(action: String) -> void:
	var w = ui.work if ui != null else null
	if w == null or code == "" or not w.has_job(code):
		_say("This is done in the work view at the equipment: open the manual from its card there (Work on it).")
		return
	if w.is_open and w.code != code:
		_say("The work view is open at %s, not at %s." % [w.code, code])
		return
	var comp := ""
	for a in w.jobs[code]["service"]["actions"]:
		if a["action"] == action:
			comp = String(a["component"])
	if not w.is_open:
		if ui.main != null and ui.main.workshop_open():
			_say("Back in the plant first: this is done at the equipment, not on the bench.")
			return
		var why: String = w.cannot(code)
		if why != "":
			_say(why + " (the work view at %s)." % code)
			return
		close()
		w.open(code)
	else:
		close()
	if comp != "":
		w.pick_comp(comp)


## A Workshop step: the Workshop on that kind with the step's component picked and its words shown.
func _follow_workshop(kind: String, place: String) -> void:
	var main = ui.main if ui != null else null
	if main == null or main.workshop == null or not main.workshop.has_kind(kind):
		_say("The Workshop has no %s in this build." % kind.replace("_", " "))
		return
	var ws = main.workshop
	# the code opened from goes with the link only when it is of the link's kind's manual (a valve's code does not
	# name the turbine's Workshop)
	var c := code if manuals.units.get(code, {}).get("manual", "") == manuals.of_kind(kind) else ""
	close()
	if ws.is_open and ws.part == kind:
		_pick_step(ws, place)
		return
	if ws.is_open:
		ws.close()
		await ws.left
		if ws.is_open:
			return                  # (opened again meanwhile)
	if work_open_now():
		ui.work.close()
	if not ui.open_workshop(kind, c):
		ui.toast("The Workshop can't open now (a flight under way, or the map open).")
		return
	var gen: int = ws._gen
	await ws.shown
	# (a load that failed, or a leave before the first frame, emits no `shown`: a later entry's must not pick here)
	if ws.is_open and ws.part == kind and ws._gen == gen:
		_pick_step(ws, place)


func work_open_now() -> bool:
	return ui != null and ui.work != null and ui.work.is_open


static func _pick_step(ws, place: String) -> void:
	ws.select(place)
	for st in ws.words.get("assembly", []):
		if String(st.get("place", "")) == place:
			ws.note = " ".join(st.get("text", []))
	if ws.panels != null:
		ws.panels.refresh()
