## Screenshots of the settings' "No lightning flashes" row (the owner, 2026-11-21, #443), to look at (not a test: it
## needs a display):
##   tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d \
##     --script res://tests/no_flashes_shots.gd -- --out=DIR [--phone] [--ui-size=2]
## (--phone and --ui-size as tests/ui_size_shots.gd). The settings opened as tests/test_ui_size.gd opens them, scrolled
## to the row; the row ticked by the keyboard (focus on it, Space); then Reduced motion on (the row on and fixed).
extends SceneTree

const SimClock = preload("res://ui/sim_clock.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const SizeTest = preload("res://tests/test_ui_size.gd")

var out := ""
var phone := false
var ui_size := ""
var main: Node


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--ui-size="):
			ui_size = a.substr(10)
		elif a == "--phone":
			phone = true
	_run.call_deferred()


func shot(name: String, frames := 10) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var p := out.path_join("%s%s_%s.png" % ["phone_" if phone else "desk_", "ui" + (ui_size if ui_size != "" else "default"), name])
	print("shot %s: %d" % [p, root.get_viewport().get_texture().get_image().save_png(p)])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"      # never the trainee's run, and no offer in the shots
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
	if ui_size != "":
		main.opts["ui_size"] = ui_size
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	await SizeTest.new()._open(self, main, "settings")
	var cb: CheckBox = null
	for c in root.find_children("*", "CheckBox", true, false):
		if c.is_visible_in_tree() and c.name == "setting_no_flashes":
			cb = c
	if cb == null:
		printerr("no No lightning flashes row")
		quit(1)
		return
	var sc = cb.get_parent()
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc != null:
		sc.ensure_control_visible(cb)
	await process_frame
	var vs := root.get_visible_rect().size
	print("canvas %s; row %s; on screen: %s" % [str(vs), str(cb.get_global_rect()), str(Rect2(Vector2.ZERO, vs).encloses(cb.get_global_rect()))])
	await shot("no_flashes")
	cb.grab_focus()
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	root.push_input(up)
	await process_frame
	print("ticked by the keyboard: %s" % str(cb.button_pressed))
	await shot("no_flashes_ticked")
	cb.button_pressed = false
	var rm: CheckBox = root.find_child("setting_reduced_motion", true, false)
	rm.button_pressed = true
	await process_frame
	print("with Reduced motion on: pressed %s, disabled %s" % [str(cb.button_pressed), str(cb.disabled)])
	await shot("no_flashes_with_reduced_motion")
	rm.button_pressed = false            # (the setting back as it was: user:// is the shots' own anyway)
	main.free()
	RunSave.remove(Autosave.default_path)
	quit(0)
