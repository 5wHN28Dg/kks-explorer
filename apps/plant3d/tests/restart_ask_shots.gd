## Screenshots of the instructor's "Restart in it" asking first (#437), to look at (not a test: it needs a display;
## tests/test_ui_restart_confirm.gd checks the same question):
##   OFFSCREEN_GODOT_DATA=DIR tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d \
##     --script res://tests/restart_ask_shots.gd -- --out=DIR [--phone] [--ui-size=2]
## A run of a minute of plant time in the first scenario; the Instructor panel; Restart in it pressed for the second
## scenario (the question in its row, Keep the run focused); half a second later (Restart pressable); Keep the run
## pressed (as before, the focus back on Restart in it); the focus on Restart; the running scenario's own question.
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


func _button(n: Node, text: String) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree():
			return b
	return null


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var path := "user://shots-restart.save"
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
	ui.set_instructor(true)
	ui.toggle_trainer()
	await shot("restart_rows")
	var other := ""
	for id in ui.info.m.scenarios:
		if id != ui.clock.scenario and other == "":
			other = id
	ui.trainer.ask_restart(other)
	await create_timer(0.3).timeout       # (the question, then the focused Keep, scrolled into view)
	await shot("restart_asks", 1)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await process_frame
	await shot("restart_armed")
	ui.trainer.body.find_child("confirm_restart", true, false).grab_focus()
	await shot("restart_focus_restart")
	var keep = ui.trainer.body.find_child("keep_run", true, false)
	keep.pressed.emit()
	await shot("restart_kept")
	ui.trainer.ask_restart(ui.clock.scenario)       # the running scenario itself: "from its start"
	await shot("restart_asks_same", 50)
	main.free()
	RunSave.remove(path)
	quit()
