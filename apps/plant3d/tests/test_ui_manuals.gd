## The equipment manuals in the app (docs/plant3d/REALISM.md §6.2.1, milestone DC2):
## - the built set reads (the index, every manual, the figures decode at their size);
## - a card's Manual opens its kind's manual with that unit's own data, the 3D view off behind the reader; the
##   contents, Next, a section link and Back work; the troubleshooting table shows; a code with no manual has no
##   Manual button; closing gives the view back; an inline valve's card opens the valves' manual;
## - the Workshop's Manual opens at the section its picked part's step links to, the Workshop's own view paused under
##   the reader; Escape closes the reader, not the Workshop; a Workshop link picks the step's part and shows its words;
## - a work link the trainee can't do yet says why (the work view's own sentence); the work view's Manual opens at
##   the picked part's section, and a work link from there picks that part in the work view;
## - the spare parts lists agree with the built Workshop trees: every component has its part number but those inside
##   a sealed component (one spare with it).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Explode = preload("res://workshop/explode.gd")
const Hands = preload("res://tests/test_ui_hands.gd")

const PT2 := "30MAG10CP002"


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	if ui.manual_view == null:
		main.free()
		return ["no manuals in the build: %s" % ui.manuals.error]
	p += _the_set(ui)
	p += await _card(tree, ui)
	p += _parts_against_trees(ui)
	p += await _workshop(tree, main, ui)
	await tree.process_frame        # (out of the Workshop's `left` before the app goes)
	main.free()
	await tree.process_frame
	p += await _work_view(tree)
	return p


func _the_set(ui) -> Array:
	var p: Array = []
	var m = ui.manuals
	if m.list.size() != 6 or m.list[0]["id"] != "pressure_transmitter":
		p.append("the manuals: %s" % str(m.list.map(func(x): return x["id"])))
	for e in m.list:
		var d: Dictionary = m.manual(String(e["id"]))
		if d.is_empty() or d["sections"].is_empty():
			p.append("manual %s did not read" % e["id"])
			continue
		for f in d["figures"]:
			var t: Texture2D = m.figure(String(f["file"]))
			if t == null or t.get_width() != int(f["w"]) or t.get_height() != int(f["h"]):
				p.append("figure %s: %s" % [f["file"], str(t.get_size()) if t != null else "missing"])
	if m.of_kind("valve_gate") != "valves" or m.of_kind("pressure_transmitter") != "pressure_transmitter":
		p.append("the kinds' manuals: %s" % str(m.kinds))
	return p


func _card(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var mv = ui.manual_view
	ui.open_card("10BAC10")
	if App.find_button(ui.card, "Manual") != null:
		p.append("the breaker's card offers a manual")
	ui.open_card(PT2)
	var b: Button = App.find_button(ui.card, "Manual")
	if b == null:
		return p + ["transmitter 2's card has no Manual button"]
	b.pressed.emit()
	await tree.process_frame
	if not ui.manual_open() or mv.man_id != "pressure_transmitter" or mv.section != "description":
		p.append("Manual opened %s at %s (open %s)" % [mv.man_id, mv.section, str(ui.manual_open())])
	if not ui.get_viewport().disable_3d or not ui.views_open():
		p.append("the plant is still drawn (or walked) behind the manual")
	if mv.layer <= 60:
		p.append("the reader is not above the Workshop's layer: %d" % mv.layer)
	if mv.page.find_child("figure_pressure_transmitter-exploded", true, false) == null:
		p.append("the description has no exploded figure")
	mv.go("specifications")
	var unit: Node = mv.page.find_child("unit", true, false)
	if unit == null or not App.texts(unit).contains(PT2) or not App.texts(unit).contains("0 to 120 kPa(a)"):
		p.append("the specifications show no data of %s: %s" % [PT2, App.texts(mv.page).left(300)])
	var nb: Button = App.find_button(mv.page, "Installation →")
	if nb == null:
		p.append("no Next button to the installation")
	else:
		nb.pressed.emit()
		if mv.section != "installation":
			p.append("Next went to %s" % mv.section)
	mv.go("troubleshooting")
	var tr: Node = mv.page.find_child("trouble", true, false)
	if tr == null or not App.texts(tr).contains("A loose or corroded signal terminal"):
		p.append("the troubleshooting table: %s" % (App.texts(tr).left(200) if tr != null else "missing"))
	if mv.open_ms <= 0.0 or mv.open_ms > 300.0:
		p.append("the troubleshooting page took %.1f ms (budget 300)" % mv.open_ms)
	# a section link, then Back
	mv.follow({"section": "hart"})
	if mv.section != "hart":
		p.append("a section link went to %s" % mv.section)
	mv.back()
	if mv.section != "troubleshooting":
		p.append("Back went to %s" % mv.section)
	# a link to another manual keeps Back
	mv.follow({"manual": "valves", "section": "operation"})
	if mv.man_id != "valves" or mv.section != "operation":
		p.append("a manual link went to %s#%s" % [mv.man_id, mv.section])
	mv.back()
	if mv.man_id != "pressure_transmitter":
		p.append("Back from another manual went to %s" % mv.man_id)
	# the real Escape key (bound to ui_cancel and to menu) goes Back first, then closes; gamepad B too
	mv.go("calibration")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	mv._input(key)
	if not ui.manual_open() or mv.section != "troubleshooting":
		p.append("Escape with a page to go back to: open %s at %s" % [str(ui.manual_open()), mv.section])
	mv.go("hart")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.pressed = true
	mv._input(pad)
	if not ui.manual_open() or mv.section != "troubleshooting":
		p.append("gamepad B with a page to go back to: open %s at %s" % [str(ui.manual_open()), mv.section])
	# the plant's keys wait under the reader (the map stays shut)
	var m_key := InputEventAction.new()
	m_key.action = "map"
	m_key.pressed = true
	ui.main._unhandled_input(m_key)
	ui._unhandled_input(m_key)
	if ui.main.map.active:
		p.append("the map opened under the reader")
		ui.main.toggle_map()
	# a work link with no role: the work view's own sentence
	mv.follow({"work": "open_cover"})
	if not ui.manual_open() or not mv.last_note.begins_with(ui.work.cannot(PT2)):
		p.append("a work link without a role said: %s" % mv.last_note)
	mv.close()
	if ui.manual_open() or ui.get_viewport().disable_3d:
		p.append("closing the manual did not give the view back")
	# an inline valve's card
	ui.open_card("30MAA10AA201")
	var vb: Button = App.find_button(ui.card, "Manual")
	if vb == null:
		p.append("the HP stop valve's card has no Manual button")
	else:
		vb.pressed.emit()
		mv.go("specifications")
		if mv.man_id != "valves" or not App.texts(mv.page).contains("PN 160"):
			p.append("the valve's manual: %s %s" % [mv.man_id, App.texts(mv.page).left(200)])
		mv.close()
	# the gas turbine's manual opens without its figures (they come with its Workshop scene)
	if ui.open_manual("gas_turbine", "", "10MBA10"):
		mv.go("specifications")
		if not App.texts(mv.page).contains("250 MW"):
			p.append("the gas turbine's own data: %s" % App.texts(mv.page).left(200))
		mv.close()
	else:
		p.append("the gas turbine's manual did not open")
	ui.close_card()
	return p


## Every component of each kind's built Workshop tree has its part number, but those inside a sealed component.
func _parts_against_trees(ui) -> Array:
	var p: Array = []
	for e in ui.manuals.list:
		var m: Dictionary = ui.manuals.manual(String(e["id"]))
		var listed := ""
		for s in m["sections"]:
			if s["id"] == "parts":
				listed = JSON.stringify(s["blocks"])
		for k in m["kinds"]:
			var path := "res://built/workshop/%s.scn" % k
			if not ResourceLoader.exists(path):
				continue
			var root: Node3D = (load(path) as PackedScene).instantiate()
			var spec := Explode.spec_of(root)
			root.free()
			for id in spec.comps:
				var inside := false
				var at: String = spec.comps[id].parent
				while at != "":
					inside = inside or spec.comps[at].sealed
					at = spec.comps[at].parent
				var pn := "WDP-%s-%s" % [m["short"], String(id).to_upper().replace("_", "-")]
				var has := listed.contains("\"" + pn + "\"")
				if has == inside:
					p.append("%s: %s %s" % [k, pn, "listed, though it comes with a sealed part" if inside else "not listed"])
	return p


func _workshop(tree: SceneTree, main, ui) -> Array:
	var p: Array = []
	var ws = main.workshop
	var mv = ui.manual_view
	if ws == null or not ui.open_workshop("pressure_transmitter", PT2):
		return p + ["the Workshop did not open"]
	await ws.shown
	if not ws.panels.manual_btn.visible:
		p.append("the Workshop has no Manual button for the transmitter")
	ws.select("sensor_module")
	ws.panels.manual_btn.pressed.emit()
	await tree.process_frame
	if not ui.manual_open() or mv.section != "replacing" or mv.code != PT2:
		p.append("the Workshop's Manual opened %s at %s from %s" % [mv.man_id, mv.section, mv.code])
	if ws.vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		p.append("the Workshop's view is still drawn under the reader")
	# Escape closes the reader (Back first when there is history), not the Workshop
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	mv._input(esc)
	if ui.manual_open() or not ws.is_open:
		p.append("Escape: reader open %s, Workshop open %s" % [str(ui.manual_open()), str(ws.is_open)])
	if ws.vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		p.append("the Workshop's view stayed paused after the reader closed")
	# a Workshop link from the reader picks the step's part and shows its words
	ui.open_manual("pressure_transmitter", "replacing", PT2)
	mv.follow({"workshop": "pressure_transmitter", "place": "housing"})
	await tree.process_frame
	if ui.manual_open() or ws.selected != "housing" or not ws.note.contains("electronics housing"):
		p.append("a Workshop link: reader %s, selected %s, note %s" % [str(ui.manual_open()), ws.selected, ws.note])
	ws.close()
	await ws.left
	# from the plant, a Workshop link opens the Workshop on its kind
	ui.open_manual("steam_turbine", "maintenance", "30MAA10")
	mv.follow({"workshop": "steam_turbine", "place": "rotor"})
	var end := Time.get_ticks_msec() + 30000
	while not (ws.is_open and ws.part == "steam_turbine" and ws.selected == "rotor") and Time.get_ticks_msec() < end:
		await tree.process_frame
	if not ws.is_open or ws.part != "steam_turbine" or ws.selected != "rotor":
		p.append("a Workshop link from the plant: open %s on %s at %s" % [str(ws.is_open), ws.part, ws.selected])
	if ws.is_open:
		ws.close()
		await ws.left
	return p


## The work view's Manual and a work link from the reader (the technician at transmitter 2, as test_ui_hands plays it).
func _work_view(tree: SceneTree) -> Array:
	var p: Array = []
	var st: Array = await Hands._start(tree, "shift_cold")
	if st[0] == null:
		return [st[1]]
	var main = st[0]
	var ui = main.ui
	var why: String = await Hands._open(tree, ui, PT2)
	if why != "":
		main.free()
		return [why]
	var mv = ui.manual_view
	var mb: Button = App.find_button(ui.work.panel, "Manual")
	if mb == null:
		p.append("the work view has no Manual button")
	else:
		mb.pressed.emit()
		if not ui.manual_open() or mv.section != "troubleshooting" or mv.code != PT2:
			p.append("the work view's Manual opened %s at %s" % [mv.man_id, mv.section])
		mv.close()
		ui.work.pick_comp("cable_gland")
		mb.pressed.emit()
		if mv.section != "loop_current":
			p.append("with the cable gland picked the Manual opened %s" % mv.section)
		# a work link picks its part in the work view (the reader closes)
		mv.follow({"work": "connect_hart"})
		if ui.manual_open() or not ui.work.is_open or ui.work.comp != "terminal_block":
			p.append("a work link: reader %s, work view %s, part %s (%s)" % [str(ui.manual_open()), str(ui.work.is_open),
				ui.work.comp, mv.last_note])
	ui.work.close()
	main.free()
	await tree.process_frame
	return p
