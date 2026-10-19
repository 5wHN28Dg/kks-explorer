## Screenshots of the interaction layer in use, to look at (not a test: it needs a display):
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/ui_shots.gd -- --out=DIR
## The app as a trainee has it (app/main.tscn, the full tier), driven through the layer: a refused start at the
## pump, the cold start's step with its card, an alarm and the trips with their first out, the instructor's faults,
## a tour's stop, a link to another plant's code, and the plant at base load.
extends SceneTree

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Procedure = preload("res://sim/procedure.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")

var out := ""
var main: Node
var ui


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func shot(name: String, frames := 40) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var p := out.path_join(name + ".png")
	print("shot %s: %d" % [p, img.save_png(p)])


func at(x: float, y: float, z: float, yaw: float, pitch: float) -> void:
	ui.player.set_mode(ui.player.Mode.FLY)
	ui.player.global_position = Vector3(x, z, -y) - Vector3.UP * 1.65
	ui.player.set_heading(-deg_to_rad(yaw), deg_to_rad(pitch))


func flown() -> void:
	for i in 300:
		if not ui.player.scripted:
			return
		await process_frame


func press(row: Array) -> void:
	(row[1] as Button).pressed.emit()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"      # never the trainee's run, and no offer in the shots
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "full"
	root.add_child(main)
	ui = main.ui
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	await process_frame
	# 1. at CW pump A: its start refused (the valve is shut), the reason on the card
	ui.open_card("30PAC10AP001")
	ui.fly_to("30PAC10AP001")
	await flown()
	ui.card.refresh()
	press(App.op_row(ui.card, "30PAC10AP001", "start"))
	ui.clock.run_steps(1)
	await shot("1_pump_refused")
	# 2. the cold start at its first steps, from the control room, with the step's card
	ui.close_card()
	ui.go_control_room()
	ui.start_procedure("cold_start", null, false)
	ui.open_card("00QFA10AN001")
	await shot("2_procedure_and_card")
	# 3. an alarm: CCW pump A runs, the instructor fails its motor; the alarm list and the trips' first out
	ui.stop_procedure()
	ui.close_card()
	ui.open_card("00PGC10AP001")
	press(App.op_row(ui.card, "00PGC10AP001", "start"))
	App.run_until(ui, "ccw_flow_ok", 3000)
	ui.set_instructor(true)
	ui.toggle_trainer()
	await shot("3_instructor")
	ui.fault("ccw_a_motor")
	ui.clock.run_steps(30)
	ui.close_trainer()
	ui.close_card()
	ui.toggle_alarms()
	await shot("4_alarm_unacknowledged", 20)
	ui.alarms._tab("trips")
	await shot("5_trips_first_out", 10)
	ui.close_alarms()
	# 4. a tour's stop, flown to
	ui.start_procedure("cw_path", null, false)
	ui.tracker.next(ui.clock.engine)
	await flown()
	await shot("6_tour_stop")
	ui.stop_procedure()
	ui.close_procedure()
	# 5. a link with a real plant's code: the plant's equipment of the same kind
	ui.handle_link("walkdown-plant://kks/11LAC10AP002")
	ui.fly_to("10LAC10AP001")
	await flown()
	await shot("7_link_same_kind")
	# 6. the plant at base load (the cold start run by its procedure in the model), the GT's card and the alarms
	ui.restart("cold_iron")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	Procedure.run(ui.model, "cold_start", 3600, ui.clock.engine)
	ui.close_card()
	ui.go_control_room()
	ui.open_card("10MBA10")
	ui.toggle_procedure()
	await shot("8_base_load_gt_card")
	at(40, 58, 4, 90, -5)
	ui.close_procedure()
	ui.open_card("10MBA10")
	await shot("9_gt_hall_running")
	main.free()
	quit(0)
