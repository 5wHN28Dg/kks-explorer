## Pictures of the work view (docs/plant3d/REALISM.md §3.3, milestone HW2), to look at (not a test: it needs a display):
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/work_shots.gd -- --out=DIR
## The first I&C technician played in shift_cold, at condenser pressure transmitter 2: the plant there before (its
## pieces unmerged), the work view with the cover on, the cover off with the communicator's clips and the
## multimeter's probes on (their screens), a refusal beside the component. The states are written straight into
## the engine for the pictures (the job itself is tests/test_ui_hands.gd's); the view's draw calls and triangles too.
extends SceneTree

const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const PT2 := "30MAG10CP002"

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
	img.save_png(out.path_join(name + ".png"))
	print("work_shots: %s draws=%d tris=%d" % [name,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _put(e, name: String, v: float) -> void:
	e.cur[e.ix[name]] = v
	e.prev[e.ix[name]] = v


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"      # never the trainee's run, and no offer in the shots
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "full"
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":     # (with a display the UI comes after the sky)
		await process_frame
	if main.start_error != "":
		printerr("the app did not start: " + main.start_error)
		quit(1)
		return
	ui = main.ui
	ui.player.set_physics_process(false)
	ui.start_shift("shift_cold")
	await process_frame
	ui.take_role("ic1")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	ui.go_to_place(e._sm.work_at[PT2])
	ui._place_tick()
	ui.clock.run_steps(1)
	# the walker's own view of the transmitters (the unmerged pieces among the plant)
	var node: Node3D = ui.index.nodes[PT2]
	ui.player.global_position = node.global_position + Vector3(0, -1.0, 1.6)
	ui.player.set_heading(0.0, -0.2)
	ui.player.camera.look_at(node.global_position, Vector3.UP)
	await shot("hw2_plant")
	ui.go_to_place(e._sm.work_at[PT2])
	ui._place_tick()
	ui.clock.run_steps(1)
	if not ui.work.open(PT2):
		print("work_shots: not opened: ", ui.work.cannot(PT2))
		quit(1)
		return
	while not ui.work.loaded():
		await process_frame
	print("work_shots: load %.1f ms, memory +%.1f MB, scene draws %d tris %d" % [ui.work.load_ms,
		ui.work.mem_added / 1048576.0, int(ui.work.scene.get_meta("draws")), int(ui.work.scene.get_meta("tris"))])
	ui.work._yaw = -1.9
	ui.work._pitch = -0.2
	ui.work._orbit_cam()
	await shot("hw2_cover_on")
	e.carried["ic1"] = ["sd_term", "dmm", "clamp", "hart"]
	for st in ["cpt2_cover_back_off", "cpt2_terminal_block_hart", "cpt2_terminal_block_dmm", "cpt2_terminal_block_clamp"]:
		_put(e, st, 1.0)
	ui.clock.run_steps(2)
	ui.work.pick_comp("terminal_block")
	ui.work.pick_tool("dmm")
	ui.work._dist = 0.35
	ui.work._orbit_cam()
	await shot("hw2_cover_off_meters", 60)
	ui.work.pick_tool("sd_flat8")
	ui.work._show("An 8 mm blade is too wide for the terminal screws: it slips and can short the terminals",
		"terminal_block")
	await shot("hw2_refused")
	ui.work.close()
	await shot("hw2_closed")
	quit(0)
