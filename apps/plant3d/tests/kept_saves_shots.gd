## Screenshots of Settings' "Kept saves" (the owner, 2026-11-21, #474), to look at (not a test: it needs a display;
## tests/test_run_save.gd checks the same list):
##   OFFSCREEN_GODOT_DATA=DIR tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d \
##     --script res://tests/kept_saves_shots.gd -- --out=DIR [--phone] [--ui-size=2]
## With the switch on (ui/autosave.gd carries()), two kept files (the synthetic 0.3.0 fixture's bytes) beside a save
## path of the shots' own: the list; Delete pressed (the question in the row, Keep focused); after Delete; an empty list.
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


func _show(sec: Node) -> void:
	var sc = sec.get_parent()
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc != null:
		sc.ensure_control_visible(sec)
	await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var path := "user://shots-kept.save"
	Autosave.default_path = path
	Autosave.switch_override = 1
	var dir := path.get_base_dir()
	var fx := FileAccess.get_file_as_bytes("res://tests/fixtures/run-0.3.0.save")
	var names := ["shots-kept-kept-0.3.0-2026-11-20.save", "shots-kept-kept-damaged-2026-11-21.save"]
	for n in names:
		FileAccess.open(dir.path_join(n), FileAccess.WRITE).store_buffer(fx)
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
	main.hud.show_settings(true)
	await process_frame
	var sec = main.hud.settings_box.find_child("kept_saves", true, false)
	await _show(sec)
	await shot("kept_list")
	var row = sec.find_child("kept_" + names[1].validate_node_name(), true, false)
	_button(row, "Delete").pressed.emit()
	await _show(sec)
	await shot("kept_delete_asks")
	_button(row, "Delete for good").pressed.emit()
	await _show(sec)
	await shot("kept_after_delete")
	row = sec.find_child("kept_" + names[0].validate_node_name(), true, false)
	_button(row, "Delete").pressed.emit()
	await process_frame
	_button(row, "Delete for good").pressed.emit()
	await _show(sec)
	await shot("kept_empty")
	main.free()
	for n in names:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(n)))
	RunSave.remove(path)
	quit()
