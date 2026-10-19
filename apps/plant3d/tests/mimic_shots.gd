## Screenshots of the control room screens (docs/PLANT3D.md §7.11, ui/mimic.gd), to look at, and their cost (not a
## test: it needs a display):
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/mimic_shots.gd -- --out=DIR [--phone]
## Every screen at cold iron, at base load, and with a trip and alarms (the instructor's loss of both closed cooling
## water pumps at base load); --phone draws them at the phone's UI scale (run it at the phone's resolution,
## `--resolution 2960x1440`). Prints each screen's drawing time and the frame's CPU and GPU time with the screens
## open and shut.
extends SceneTree

const SimClock = preload("res://ui/sim_clock.gd")
const Procedure = preload("res://sim/procedure.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const W = preload("res://ui/widgets.gd")

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


func shot(name: String, frames := 12) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var p := out.path_join(("phone_" if phone else "") + name + ".png")
	print("shot %s: %d" % [p, img.save_png(p)])


## The frame's CPU and GPU time (ms) over n frames, as the renderer measures them.
func frame_ms(n := 90) -> Array:
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cpu := 0.0
	var gpu := 0.0
	var proc := 0.0
	for i in n:
		await process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return [cpu / n, gpu / n, proc / n]


func every_screen(stage: String) -> void:
	ui.open_screens()
	await shot("%s_0_overview" % stage)
	for i in ui.screens.screens.size():
		ui.mimic.show_screen(i)
		await shot("%s_%d_%s" % [stage, i + 1, ui.screens.screens[i].id])
		print("  draw %s: %d µs" % [ui.screens.screens[i].id, ui.mimic.draw_us])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
	root.add_child(main)
	ui = main.ui
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	await process_frame
	ui.go_control_room()
	await every_screen("cold")
	# the desks, seen from the start
	ui.close_screens()
	ui.player.set_heading(deg_to_rad(90.0), deg_to_rad(-10.0))
	await shot("desks", 30)
	# base load: the cold start run by its procedure in the model
	ui.restart("cold_iron", true)
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	Procedure.run(ui.model, "cold_start", 3600, ui.clock.engine)
	ui.go_control_room()
	await every_screen("base")
	# the cost: the control room's view with the screens shut, then the busiest screens open, the plant running
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	ui.close_screens()
	var shut := await frame_ms()
	ui.open_screens("ct")
	var ct := await frame_ms()
	ui.mimic.show_screen(-1)
	var ov := await frame_ms()
	print("cost (cpu ms, gpu ms, process ms per frame): screens shut %s, cooling tower %s, overview %s; redraws %d" % [
			str(shut), str(ct), str(ov), ui.mimic.redraws])
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	# a trip and alarms: both closed cooling water pumps lost at base load
	ui.fault("ccw_both")
	ui.clock.run_steps(3600)
	ui.open_screens("aux")
	await shot("trip_aux")
	ui.mimic.show_screen(-1)
	await shot("trip_overview")
	ui.mimic.show_screen(ui.screens.screen_index("gt"))
	await shot("trip_gt")
	# a card opened from a screen
	ui.mimic.show_screen(ui.screens.screen_index("aux"))
	ui.mimic.activate("00PGC10AP001")
	await shot("trip_aux_card")
	main.free()
	quit(0)
