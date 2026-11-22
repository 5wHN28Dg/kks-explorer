## Screenshots of "Report a problem" (#446), to look at (not a test: it needs a display; tests/test_report_problem.gd
## checks the same):
##   OFFSCREEN_GODOT_DATA=DIR tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d \
##     --script res://tests/report_shots.gd -- --out=DIR [--phone] [--ui-size=2]
## Switched on; a synthetic player name saved and a log line holding it and an address: About with its button; the
## report; a description written (Latin and Arabic); the run's inputs ticked, the report scrolled to; a save that
## failed; after Copy (what it says).
extends SceneTree

const Report = preload("res://app/report.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")

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
	Report.switch_override = 1
	var path := "user://shots-report.save"
	Autosave.default_path = path
	RunSave.remove(path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
	if ui_size != "":
		main.opts["ui_size"] = ui_size
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	main.cf.set_value("multiplayer", "name", "Sara Zed سارة")
	main.ui.clock.run_steps(600)
	print("shots: Sara Zed سارة joined from 192.168.7.23")
	main.hud.show_about()
	await shot("report_about")
	main.hud.show_report()
	await shot("report_shown")
	var rv = main.hud.report
	rv.what_box.text = "The pump's card froze after I pressed Start. سارة saw it too."
	await shot("report_written")
	rv.inputs_cb.button_pressed = true
	rv.scroll.ensure_control_visible(rv.text_box)
	await shot("report_inputs")
	rv.write_to("user://no-such-folder/x/report.txt")
	await shot("report_save_failed")
	rv.copy()
	await shot("report_copied")
	main.free()
	RunSave.remove(path)
	quit()
