## Walkdown Plant's start (decision 0054): picks the quality tier (app/quality.gd), loads the pre-built plant
## (app/plant.gd), puts the trainee at the plant's start (the control room) and hands over to the controls.
##
## Options, after `--` on the command line (desktop) or one per line in walk.txt in the app's external files folder
## (Android: phone/frames.sh pushes it):
##   quality=full|lean+vis   this tier, whatever the settings say
##   walk=frames|climb       walk a scripted route (app/routes.gd) and log frame times; `frames` loops
##   seconds=600             (walk) how long, after the first 5 s which are not measured
##   out=DIR                 where result.txt (and shots) go (default: the external files folder on Android, the user
##                           data folder elsewhere)
##   shot=NAME@x,y,z,yaw,pitch[;NAME@…]   save the view from those points (plant coordinates, degrees) as PNGs, quit
##   map=1                   start on the overview map
##   scenario=ID             the scenario the plant starts in (default cold_iron)
##   procedure=ID            follow that procedure or tour from the start
##   panels=alarms,procedure,card:CODE   open these panels (the frame measurement with the UI open)
##   speed=fast              start the plant in fast-forward (the model's share of a core, measured in a walk)
##   walkdown-plant://…      a link (docs/PLANT3D.md §6): anywhere on the command line, as the desktop files pass it
##   fx_off=fog,tonemap      those effects off (tonemap: linear output at half exposure), fx_on=ssao,sdfgi,ssil,volfog,glow those on (measuring what each costs:
##                           app/lighting.gd); fx_off=shadow,cascades2,shadow40,shadowhard the sun's shadow's parts
##                           (app/quality.gd), fx_off=lightmap the plant without its bake (the halls dark: their lamps
##                           light through the bake only)
extends Node3D

const Quality = preload("res://app/quality.gd")
const Player = preload("res://app/player.gd")
const Plant = preload("res://app/plant.gd")
const Autopilot = preload("res://app/autopilot.gd")
const Routes = preload("res://app/routes.gd")
const Hud = preload("res://app/hud.gd")
const MapView = preload("res://app/map_view.gd")
const PlantUi = preload("res://ui/plant_ui.gd")
const Lighting = preload("res://app/lighting.gd")
const ANDROID_FILES := "/storage/emulated/0/Android/data/io.github.walkdown.plant/files"

var cf: ConfigFile
var opts := {}
var tier := ""
var tier_why := ""
var plant: Node3D
var player
var hud
var map
var ui      # ui/plant_ui.gd: the engine, the cards, alarms, procedures, links
var sun: DirectionalLight3D
var env: Environment
var auto
var out_dir := ""
# the frame log of a scripted walk
var times := PackedFloat32Array()
var gpu := PackedFloat32Array()
var last_us := 0
var t_walk := 0.0
var walk_seconds := 600.0
var first_frame_ms := -1
var lines := PackedStringArray()
var stuck_count := 0
var sim_max_ms := 0.0      # the model's busiest second during a walk (ms of model time per s: 250 = a quarter core)
var sim_sum_ms := 0.0
var sim_n := 0
var sim_t := 0.0
var probing := false     # the tier probe is running: no map, no tier changes, no walking until it ends

func _ready() -> void:
	_options()
	cf = Quality.settings()
	OS.delta_smoothing = false
	_environment()
	plant = Plant.new()
	plant.name = "plant"
	add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		_say("ERROR " + err)
		var l := Label.new()
		l.text = err
		add_child(l)
		return
	_say("loaded the plant in %d ms (%d areas)" % [plant.load_ms, plant.manifest.areas.size()])
	var lm := Lighting.lightmap_node()
	if lm != null:
		plant.add_child(lm)   # beside the areas: its users' paths are "../area_…" (app/lighting.gd)
		# meshes made at run time (the UI's markers) are not in the bake: the sky's light, not its probes
		get_tree().node_added.connect(_unbaked)
		_say("lightmap: %d meshes baked" % lm.light_data.get_user_count())
	else:
		_say("lightmap: none in this build (the sky and the sun only)")
	for l in get_tree().get_nodes_in_group("baked_lights"):
		l.queue_free()   # the halls' lamps light through the bake only (forty real-time lights in a hall cost too much)
	player = Player.new()
	player.name = "player"
	add_child(player)
	var st: Array = plant.start()
	player.global_position = st[0]
	player.set_heading(st[1])
	map = MapView.new()
	map.name = "map"
	add_child(map)
	map.setup(player, plant)
	map.jumped.connect(_on_jump)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	player.mode_changed.connect(func(_m): hud.refresh())
	ui = PlantUi.new()
	ui.name = "ui"
	add_child(ui)
	ui.setup(self, opts.get("scenario", "cold_iron"))
	ui.add_settings(hud.extra)
	if opts.has("procedure") and ui.clock != null and ui.model.procedures.has(opts.procedure):
		ui.start_procedure(opts.procedure, null, false)
	for p in String(opts.get("panels", "")).split(",", false):
		ui.open_panel(p)
	if opts.get("speed", "") == "fast" and ui.clock != null:
		ui.fast_forward()
	# the saved run (ui/autosave.gd): offered at start; a start the command line asks for (a measurement, a scenario,
	# a procedure, a speed) is saved to a file of its own, never over a trainee's run, and offers nothing
	if ui.autosave != null:
		var own := false
		for k in ["walk", "shot", "scenario", "procedure", "speed"]:
			own = own or opts.has(k)
		if own:
			ui.autosave.path = "user://run-options.save"
		ui.autosave.begin(not own)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	choose_tier()
	_first_frame()
	if opts.has("shot"):
		_shots.call_deferred()
	elif opts.has("walk"):
		while probing:
			await get_tree().process_frame
		_start_walk()
	elif opts.get("map", "") == "1":
		toggle_map()

func _unbaked(n: Node) -> void:
	var g := n as GeometryInstance3D
	if g != null and g.gi_mode == GeometryInstance3D.GI_MODE_STATIC and not (n is MeshInstance3D and n.is_in_group("kit_static")):
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

func _options() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.get_name() == "Android":
		var f := FileAccess.open(ANDROID_FILES + "/walk.txt", FileAccess.READ)
		if f:
			for line in f.get_as_text().split("\n"):
				var kv := line.strip_edges().split("=", true, 1)
				if kv.size() == 2 and kv[0] in ["walk", "seconds", "quality", "procedure", "panels", "scenario", "speed"]:   # nothing else from a shared folder
					opts[kv[0]] = kv[1]
	out_dir = ANDROID_FILES if OS.get_name() == "Android" else opts.get("out", OS.get_user_data_dir())
	Lighting.off = String(opts.get("fx_off", "")).split(",", false)
	Lighting.on = String(opts.get("fx_on", "")).split(",", false)

func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Lighting.sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = Lighting.sun()
	add_child(sun)

## Picks the tier (app/quality.gd) and applies it; a desktop without a measurement of its GPU measures it first.
func choose_tier() -> void:
	if probing:
		return   # the probe ends by choosing (the settings' choice, saved, is read then)
	var c := Quality.choose(cf, opts.get("quality", ""))
	if c.tier == "":
		if DisplayServer.get_name() == "headless":
			c = {"tier": "full", "why": "no display (nothing to measure)"}
		else:
			_probe()
			return
	tier = c.tier
	tier_why = c.why
	Quality.apply(tier, get_viewport(), sun, env)
	if hud:
		hud.refresh()
	_say("tier %s (%s), renderer %s, %s" % [tier, tier_why, Quality.renderer(), RenderingServer.get_video_adapter_name()])
	if hud:
		hud.refresh()

## The probe (R9, measured on the device): the full tier on the heaviest view (the whole plant from above its
## south-west corner) for PROBE_FRAMES frames; the median GPU time decides (app/quality.gd).
func _probe() -> void:
	probing = true
	player.input_enabled = false
	tier = "full"
	tier_why = "measuring this device"
	Quality.apply("full", get_viewport(), sun, env)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.far = 800
	add_child(cam)
	cam.global_position = Plant.g(-30, -50, 40)
	cam.look_at(Plant.g(120, 40, 0), Vector3.UP)
	cam.make_current()
	var vp := get_viewport().get_viewport_rid()
	var g := PackedFloat32Array()
	for i in Quality.PROBE_FRAMES:
		await RenderingServer.frame_post_draw
		if i >= Quality.PROBE_SKIP:
			g.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	g.sort()
	var med := g[g.size() / 2]
	var t := Quality.record_probe(cf, med)
	Quality.save(cf)
	_say("probe: full tier GPU median %.2f ms on the heaviest view -> %s" % [med, t])
	cam.queue_free()
	player.camera.make_current()
	probing = false
	choose_tier()

func toggle_map() -> void:
	if probing:
		return
	map.show_map(not map.active)
	if map.active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.refresh()

func _on_jump(to: Vector3) -> void:
	player.global_position = to + Vector3.UP * 0.05
	player.set_mode(Player.Mode.WALK)   # lands on the floor just found
	player.velocity = Vector3.ZERO
	toggle_map()

func area_at(p: Vector3) -> String:
	for a in plant.manifest.areas:
		var b: Array = a.bounds
		if p.x >= b[0][0] and p.x <= b[1][0] and -p.z >= b[0][1] and -p.z <= b[1][1]:
			return a.title
	return "Between the areas"

func _unhandled_input(e: InputEvent) -> void:
	if player == null or player.scripted:
		return
	if e.is_action_pressed("map"):
		toggle_map()
	elif e.is_action_pressed("menu"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			hud.show_settings(not hud.panel.visible)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not map.active \
			and not hud.panel.visible and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ------------------------------------------------------------------ scripted walks and their frame log

func _say(s: String) -> void:
	print("plant: ", s)
	lines.append(s)

func _first_frame() -> void:
	await RenderingServer.frame_post_draw
	first_frame_ms = Time.get_ticks_msec()
	_say("first frame drawn %d ms after the engine started" % first_frame_ms)
	# the pipelines compiled for it (what a phone's first start waits for: decision 0057)
	_say("pipelines compiled: mesh %d, surface %d, draw %d, specialization %d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)])

func _start_walk() -> void:
	var route: Array = Routes.frames(plant) if opts.walk == "frames" else Routes.climb(plant)
	walk_seconds = float(opts.get("seconds", "600"))
	auto = Autopilot.new()
	auto.skip_stuck = true
	add_child(auto)
	auto.stuck.connect(func(i, at): stuck_count += 1; _say("STUCK at step %d, %s" % [i, str(at)]))
	auto.finished.connect(_finish)
	var st: Array = plant.start()
	if opts.walk != "frames":
		player.global_position = route[0].to
	else:
		player.global_position = st[0]
	auto.start(player, route, opts.walk == "frames")
	last_us = Time.get_ticks_usec()

func _process(delta: float) -> void:
	if auto == null or not auto.running:
		return
	t_walk += delta
	var now := Time.get_ticks_usec()
	var ms := (now - last_us) / 1000.0
	last_us = now
	if t_walk > 5.0:
		times.append(ms)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		if ms > 100.0:
			_say("SPIKE %.1f ms at %.1f s, at %s" % [ms, t_walk, str(player.global_position)])
		if ui != null and ui.clock != null:
			sim_t += delta
			if sim_t >= 1.0:
				sim_t = 0.0
				var c = ui.clock
				sim_max_ms = maxf(sim_max_ms, c.model_ms_per_s)
				sim_sum_ms += c.model_ms_per_s
				sim_n += 1
				if sim_n % 60 == 0:
					_say("SIM at %.0f s: %.0f steps/s, %.0f ms of model per s, %.2f ms a step, speed %d, cap %.1fx" % [
						t_walk, c.steps_per_s, c.model_ms_per_s, c.step_ms, c.speed, c.ff_cap()])
	if t_walk > walk_seconds + 5.0:
		_finish()

## The frame log (as the bench's, decision 0041): wall-clock frame intervals and how many refreshes of a 60 Hz
## screen each one spans, the GPU time, memory.
func _finish() -> void:
	if auto:
		auto.stop()
	set_process(false)
	var n := times.size()
	if n > 0:
		var s := times.duplicate(); s.sort()
		var g := gpu.duplicate(); g.sort()
		var r1 := 0; var r2 := 0; var r3 := 0; var over100 := 0
		for d in times:
			if d <= 17.5: r1 += 1
			elif d <= 34.2: r2 += 1
			else: r3 += 1
			if d > 100.0: over100 += 1
		_say("CADENCE up_to_17.5ms=%.1f%% up_to_34.2ms=%.1f%% longer=%.1f%%" % [100.0 * r1 / n, 100.0 * r2 / n, 100.0 * r3 / n])
		_say("RESULT tier=%s renderer=%s walk=%s frames=%d median=%.1fms p95=%.1fms p99=%.1fms max=%.1fms over100=%d gpu_median=%.1fms gpu_p95=%.1fms stuck=%d static_mem=%dMB vram=%dMB first_frame=%dms load=%dms" % [
			tier, Quality.renderer(), opts.walk, n, s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], s[n - 1], over100,
			g[n / 2], g[int(n * 0.95)], stuck_count, OS.get_static_memory_usage() / 1048576,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576, first_frame_ms, plant.load_ms])
	else:
		_say("RESULT no frames (stuck=%d)" % stuck_count)
	if sim_n > 0:
		_say("SIM_RESULT model_ms_per_s_mean=%.1f model_ms_per_s_max=%.1f step_ms=%.3f ff_cap=%.1f model_time=%s" % [
			sim_sum_ms / sim_n, sim_max_ms, ui.clock.step_ms, ui.clock.ff_cap(), ui.clock.clock_text()])
	_write_out()
	get_tree().quit()

func _write_out() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("result.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")

## Views saved as PNGs (looking at the result on a laptop): shot=NAME@x,y,z,yaw,pitch;… in plant coordinates.
func _shots() -> void:
	for i in 30:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(out_dir)
	for spec in String(opts.shot).split(";"):
		var nv := spec.split("@")
		var nm := nv[0]
		if nv.size() > 1 and nv[1] != "map":
			var v := nv[1].split(",")
			if map.active: toggle_map()
			player.set_mode(Player.Mode.FLY)
			player.global_position = Plant.g(float(v[0]), float(v[1]), float(v[2])) - Vector3.UP * Player.EYE
			player.set_heading(-deg_to_rad(float(v[3])), deg_to_rad(float(v[4])))
		elif not map.active:
			toggle_map()
		for i in 45:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := out_dir.path_join(nm + ".png")
		_say("shot %s: error %d" % [p, img.save_png(p)])
	_write_out()
	get_tree().quit()
