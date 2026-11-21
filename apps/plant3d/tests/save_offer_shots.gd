## Screenshots of the saved run's offer at start (ui/autosave.gd, issue #447), to look at (not a test: it needs a
## display; tests/test_run_save.gd checks the same offers):
##   OFFSCREEN_GODOT_DATA=DIR tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d \
##     --script res://tests/save_offer_shots.gd -- --out=DIR [--phone] [--density=420] [--ui-size=2]
## (--phone, --density, --ui-size as tests/ui_size_shots.gd). The saves are the synthetic fixture the release before
## wrote (tests/fixtures/run-0.3.0.save) and this build's own run; they go to a file of the shots' own, never the
## trainee's run. With the switch on (`walkdown/carry_saves_over`): the release before's save offered; after Continue;
## the same save in a scenario this plant hasn't (kept aside); this build's own save (New run's line); a damaged one.
## With it off: the release before's save as plant-v0.3.0 refuses it (the baseline).
extends SceneTree

const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")

var out := ""
var phone := false
var ui_size := ""
var density := ""
var main: Node


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--ui-size="):
			ui_size = a.substr(10)
		elif a.begins_with("--density="):
			density = a.substr(10)
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


func _start() -> void:
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
		if density != "":
			main.opts["density"] = density
	if ui_size != "":
		main.opts["ui_size"] = ui_size
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	var ap = main.ui.autosave
	if ap.offer_panel != null:
		print("offer: %s" % str(ap.offer_panel.get_global_rect()))
		for b in ap.offer_panel.find_children("*", "Button", true, false):
			print("  button %s %s" % [b.text, str(b.get_global_rect())])


func _button(text: String) -> Button:
	for b in main.ui.autosave.offer_panel.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func _stop() -> void:
	main.free()
	main = null
	await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var path := "user://shots-offer.save"
	Autosave.default_path = path
	var dir := path.get_base_dir()
	var fx := FileAccess.get_file_as_bytes("res://tests/fixtures/run-0.3.0.save")
	var old: Dictionary = RunSave.decode(fx)["payload"]
	var kept_files: Array = []
	# the baseline: switched off, as plant-v0.3.0
	Autosave.switch_override = 0
	RunSave.remove(path)
	RunSave.write(path, fx)
	await _start()
	await shot("off-old-release")
	await _stop()
	Autosave.switch_override = 1
	# the release before's save: offered, then continued
	RunSave.remove(path)
	RunSave.write(path, fx)
	await _start()
	await shot("on-old-release-offer")
	kept_files.append(main.ui.autosave.kept)
	Autosave.migrate_budget_us = 1          # slowly: the progress line, New run with the focus Continue had
	_button("Continue").grab_focus()
	_button("Continue").pressed.emit()
	await shot("on-old-release-making-again", 3)
	Autosave.migrate_budget_us = 20000
	for i in 600:
		if main.ui.autosave.offer_panel == null:
			break
		await process_frame
	await shot("on-old-release-continued", 5)
	var own: Dictionary = main.ui.autosave.payload()
	await _stop()
	# the same save in a scenario this plant hasn't: kept aside
	var q := old.duplicate(true)
	q["scenario"] = "no_such_scenario"
	RunSave.remove(path)
	RunSave.write(path, RunSave.encode(q))
	await _start()
	await shot("on-cannot-continue")
	kept_files.append(main.ui.autosave.kept)
	await _stop()
	# a run made again whose state this build refuses: said after Continue, New run focused
	q = old.duplicate(true)
	q["ui"]["results"] = {"00PGC10AP001": 5}
	RunSave.remove(path)
	RunSave.write(path, RunSave.encode(q))
	await _start()
	_button("Continue").grab_focus()
	_button("Continue").pressed.emit()
	for i in 600:
		if main.ui.autosave.migrating == null:
			break
		await process_frame
	await shot("on-made-again-refused")
	await _stop()
	# the copy aside fails (a folder where the kept file goes): nothing replaced, Replace it
	q = old.duplicate(true)
	q["scenario"] = "no_such_scenario"
	RunSave.remove(path)
	RunSave.write(path, RunSave.encode(q))
	await _start()
	var kd: String = ProjectSettings.globalize_path(dir.path_join(main.ui.autosave.kept))
	DirAccess.make_dir_recursive_absolute(kd)
	_button("New run").pressed.emit()
	await shot("on-copy-aside-failed")
	await _stop()
	DirAccess.remove_absolute(kd)
	# this build's own save: the offer as before, with New run's line
	RunSave.remove(path)
	RunSave.write(path, RunSave.encode(own))
	await _start()
	await shot("on-own-save")
	await _stop()
	# a damaged one
	var b := RunSave.encode(own)
	RunSave.remove(path)
	RunSave.write(path, b.slice(0, b.size() - 3))
	await _start()
	await shot("on-damaged")
	await _stop()
	RunSave.remove(path)
	for k in DirAccess.get_files_at(dir):
		if k.begins_with("shots-offer"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(k)))
	quit()
