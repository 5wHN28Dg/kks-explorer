## Pictures of the Workshop's panels (#388, #389, #390), to look at (not a test: it needs a display):
##   XH_SIZE=1600x900@60 tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/workshop_shots.gd \
##       -- --out=DIR [--phone] [--ui-size=X] [--kinds=a,b]
## Each kind (default every kind the build has) opened, its first component picked, then its guided steps started
## (where it has them), then its bench with the session's strip: `<kind>.png`, `<kind>_steps.png`, `<kind>_run_strip.png`. --phone draws at the phone's UI scale (1.35) and its UI size
## (150 %), --ui-size=X at that UI size (the settings' 1 to 1.5);
## the window is then made the Note 9's 2220 × 1080 (a 1850 × 900 canvas): run it with XH_SIZE=2220x1080@60.
extends SceneTree

const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const SimClock = preload("res://ui/sim_clock.gd")

var out := ""
var phone := false
var ui_size := ""
var only: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--phone":
			phone = true
		elif a.begins_with("--ui-size="):
			ui_size = a.substr(10)
		elif a.begins_with("--kinds="):
			only = Array(a.substr(8).split(",", false))
	_run.call_deferred()


func shot(name: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("workshop_shots: %s %dx%d draws=%d" % [name, img.get_width(), img.get_height(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Autosave.default_path = "user://shots-run.save"      # never the trainee's run, and no offer in the shots
	RunSave.remove(Autosave.default_path)
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
	if ui_size != "":
		main.opts["ui_size"] = ui_size
	if phone:
		root.size = Vector2i(2220, 1080)   # (the Note 9's screen: a 1850 × 900 canvas)
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	if main.start_error != "":
		printerr("the app did not start: " + main.start_error)
		quit(1)
		return
	main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	var ws = main.workshop
	for kind in ws.kinds():
		if not only.is_empty() and not only.has(kind):
			continue
		if not ws.open(kind):
			printerr("workshop_shots: %s did not open" % kind)
			continue
		while ws._loading != "" or ws.machine == null:
			await process_frame
		if not ws.spec.order.is_empty():
			ws.select(String(ws.spec.order[0]))
		await shot(kind)
		if not ws.words.get("assembly", []).is_empty():
			ws.start_guide("disassemble")
			await shot(kind + "_steps")
			ws.reset()
		# the bench in the properties' place, and the session's strip (as a session that ended while it showed)
		ws.panels.show_run(true)
		ws._session = true
		ws.panels._strip_n = -1
		await shot(kind + "_run_strip")
		ws._session = false
		ws.panels.show_info(true)
		ws.close()
		await ws.left
	quit(0)
