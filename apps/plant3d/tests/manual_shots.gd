## Screenshots of the manual reader (docs/plant3d/REALISM.md §6.2.1, ui/manual_view.gd), to look at (not a test: it
## needs a display):
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/manual_shots.gd -- --out=DIR [--phone]
## The transmitter's manual from transmitter 2's card (its description with the figure, its specifications with the
## unit's data, its troubleshooting table), the steam turbine's cut figure, the valves' description table; --phone at
## the phone's UI scale (run it at the phone's resolution, `--resolution 2960x1440`). Prints each page's build time.
extends SceneTree

const SimClock = preload("res://ui/sim_clock.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const App = preload("res://tests/ui_app.gd")

var out := ""
var phone := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--phone":
			phone = true
	if out == "":
		printerr("--out=DIR")
		quit(2)
		return
	_run.call_deferred()


func shot(name: String, frames := 12) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var p := out.path_join(("phone_" if phone else "") + name + ".png")
	print("shot %s: %d" % [p, img.save_png(p)])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"
	RunSave.remove(Autosave.default_path)
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	if main.start_error != "":
		printerr("the app did not start: " + main.start_error)
		quit(1)
		return
	var ui = main.ui
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	await process_frame
	var nr: Button = App.find_button(root, "New run")
	if nr != null and nr.is_visible_in_tree():
		nr.pressed.emit()
		await process_frame
	var mv = ui.manual_view
	ui.open_manual("pressure_transmitter", "", "30MAG10CP002")
	for sec in ["description", "specifications", "troubleshooting", "parts"]:
		mv.go(sec)
		print("page pressure_transmitter#%s: %.1f ms" % [sec, mv.open_ms])
		await shot("pt_" + sec)
	mv.open("steam_turbine", "description")
	print("page steam_turbine#description: %.1f ms" % mv.open_ms)
	await shot("st_description")
	mv.open("valves", "description")
	await shot("valves_description")
	mv.close()
	quit(0)
