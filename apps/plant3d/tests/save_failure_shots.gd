## Screenshots of a failed autosave said on screen (#473), to look at (not a test: it needs a display;
## tests/test_ui_save_failure.gd checks the same):
##   OFFSCREEN_GODOT_DATA=DIR tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d \
##     --script res://tests/save_failure_shots.gd -- --out=DIR [--phone] [--ui-size=2]
## A run saved at a minute of plant time, then a save into a path whose folder is a file: the message and the status
## line; the status line alone after the message has gone; a save that succeeds again (its message, the line cleared).
extends SceneTree

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
	var path := "user://shots-savefail.save"
	var blocker := "user://shots-savefail-blocker"
	FileAccess.open(blocker, FileAccess.WRITE).store_string("not a folder")
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
	var ui = main.ui
	ui.clock.run_steps(600)
	ui.autosave.save_now()
	ui.clock.run_steps(600)
	ui.autosave.path = blocker.path_join("run.save")
	ui.autosave.save_now()
	await shot("savefail_said")
	ui._toast.visible = false
	await shot("savefail_line")
	ui.autosave.path = path
	ui.autosave.save_now()
	await shot("savefail_saved_again")
	main.free()
	RunSave.remove(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	quit()
