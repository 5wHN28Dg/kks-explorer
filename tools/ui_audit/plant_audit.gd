## Walkdown Plant UI audit (tools/ui_audit). Run from the repository root:
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script "$PWD/tools/ui_audit/plant_audit.gd" -- --out=DIR [--phone]
## UI audit walk of Walkdown Plant (pass 1, 2026-11): opens each panel in turn, takes a shot and dumps every visible
## Control (class, text, rect in canvas px, font size and colour, focus mode, accessibility name).
##   offscreen.sh godot --path apps/plant3d --script /abs/plant_audit.gd -- --out=DIR [--phone]
extends SceneTree

const SimClock = preload("res://ui/sim_clock.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const App = preload("res://tests/ui_app.gd")

var out := ""
var phone := false
var main: Node
var ui


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--phone":
			phone = true
	_run.call_deferred()


func tag(name: String) -> String:
	return ("phone_" if phone else "desk_") + name


func shot(name: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(tag(name) + ".png"))
	dump(name)


func dump(name: String) -> void:
	var rows := []
	_walk(root, rows)
	var f := FileAccess.open(out.path_join(tag(name) + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"canvas": root.get_visible_rect().size, "window": DisplayServer.window_get_size(),
			"focus": str(root.gui_get_focus_owner().get_path()) if root.gui_get_focus_owner() else "", "controls": rows}, " "))
	f.close()
	print("dumped %s: %d controls" % [name, rows.size()])


func _walk(n: Node, rows: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		var vis := root.get_visible_rect()
		if r.intersects(vis) and r.size.x > 0 and r.size.y > 0:
			var d := {"cls": c.get_class(), "path": str(c.get_path()).replace("/root/", ""),
					"rect": [r.position.x, r.position.y, r.size.x, r.size.y], "focus_mode": c.focus_mode,
					"mouse_filter": c.mouse_filter}
			if "text" in c:
				d["text"] = str(c.get("text")).substr(0, 160)
			if c is RichTextLabel:
				d["text"] = (c as RichTextLabel).get_parsed_text().substr(0, 160)
				d["font_size"] = c.get_theme_font_size("normal_font_size")
				d["font_color"] = c.get_theme_color("default_color").to_html()
			elif c is Label or c is Button or c is LineEdit:
				d["font_size"] = c.get_theme_font_size("font_size")
				d["font_color"] = c.get_theme_color("font_color").to_html()
				if c is Label:
					d["clip"] = (c as Label).clip_text
					d["overrun"] = (c as Label).text_overrun_behavior
					d["autowrap"] = (c as Label).autowrap_mode
					d["selectable"] = false
			if "accessibility_name" in c:
				d["a11y_name"] = str(c.get("accessibility_name"))
			if c is BaseButton:
				d["disabled"] = (c as BaseButton).disabled
			rows.append(d)
	for ch in n.get_children():
		_walk(ch, rows)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://audit-run.save"
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis"
	if phone:
		main.opts["ui_scale"] = "1.35"
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	if main.start_error != "":
		printerr("the app did not start: " + main.start_error)
		quit(1)
		return
	ui = main.ui
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	await process_frame
	var nr: Button = App.find_button(root, "New run")
	if nr != null:
		await shot("00_start_offer")
		nr.pressed.emit()
		await process_frame
	await shot("01_hud")
	main.hud.show_settings(true)
	await shot("02_settings")
	main.hud.show_about()
	await shot("03_about")
	main.hud.show_settings(false)
	main.toggle_map()
	await shot("04_map", 40)
	main.toggle_map()
	ui.open_card("30PAC10AP001")
	await shot("05_card")
	# the card scrolled to its end: is Close where it was?
	var sc := _first(ui.card, "ScrollContainer")
	if sc != null:
		sc.scroll_vertical = 100000
		await shot("05b_card_scrolled")
	ui.close_card()
	ui.toggle_alarms()
	await shot("06_alarms")
	ui.close_alarms()
	ui.toggle_procedure()
	await shot("07_procedures")
	ui.close_procedure()
	ui.start_procedure("cold_start", null, false)
	await shot("08_procedure_running")
	ui.stop_procedure()
	ui.close_procedure()
	ui.set_instructor(true)
	ui.toggle_trainer()
	await shot("09_instructor")
	ui.close_trainer()
	ui.open_permits()
	await shot("10_permits")
	ui.close_permits()
	ui.open_work_orders()
	await shot("11_work_orders")
	ui.close_work_orders()
	ui.open_crew()
	await shot("12_crew")
	ui.close_crew()
	ui.open_drawing("")
	await shot("13_drawings", 40)
	ui.close_drawings()
	ui.open_session()
	await shot("14_session")
	ui.close_session()
	ui.go_control_room(false)
	ui.open_screens("")
	await shot("15_screens_overview", 40)
	ui.close_screens()
	var man: String = ui.manual_of("30PAC10AP001")
	if man != "" and ui.open_manual(man, "", "30PAC10AP001"):
		await shot("16_manual", 40)
		ui.close_top()
	ui.open_debrief()
	await shot("17_debrief")
	ui.close_debrief()
	ui.toast("Copied 30PAC10AP001")
	await shot("18_toast", 5)
	main.free()
	quit(0)


func _first(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.get_class() == cls and (c as CanvasItem).is_visible_in_tree():
			return c
		var f := _first(c, cls)
		if f:
			return f
	return null
