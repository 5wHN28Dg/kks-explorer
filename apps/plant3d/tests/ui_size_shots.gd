## Screenshots of every panel at a UI size, to look at (not a test: it needs a display; tests/test_ui_size.gd checks
## the same panels' places):
##   tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d --script res://tests/ui_size_shots.gd \
##     -- --out=DIR [--phone] [--ui-size=1.5]
## --phone: at the phone's UI scale (run it at the Note 9's canvas, `--resolution 1850x900`). Each panel opened in turn
## as tests/test_ui_size.gd opens it, in the aged plant's shift (its crews, work orders and stores have something to
## show); then the settings with the keyboard and gamepad help open.
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


func shot(name: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var p := out.path_join("%s%s_%s.png" % ["phone_" if phone else "desk_", "ui" + (ui_size if ui_size != "" else "default"), name])
	print("shot %s: %d" % [p, img.save_png(p)])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"      # never the trainee's run, and no offer in the shots
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	main.opts["scenario"] = "shift_aged"
	if phone:
		main.opts["ui_scale"] = "1.35"
	if ui_size != "":
		main.opts["ui_size"] = ui_size
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	if main.start_error != "":
		printerr("the app did not start: " + main.start_error)
		quit(1)
		return
	main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	await shot("0_bars")
	var t = SizeTest.new()
	var i := 1
	for pn in t._panels():
		await t._open(self, main, pn)
		await shot("%02d_%s" % [i, pn])
		if pn == "settings":
			main.hud.controls_btn.button_pressed = true
			await shot("%02d_settings_controls" % i)
			main.hud.controls_btn.button_pressed = false
		t._close(main, pn)
		await process_frame
		i += 1
	main.free()
	quit(0)
