## Where a frame's time goes (the laptop's 60 fps rule, decision 0057): `--probe=1` with a walk writes frames.csv
## beside result.txt, one line per frame: the physics steps and their time, the scripts' _process, the time up to the
## draw, the draw itself (RenderingServer's frame_pre_draw to frame_post_draw: the render thread's CPU work and any wait
## for the GPU or the swap chain), the rest (the OS's events, the wait for the next frame), and what the systems did.
## cpu_ms and gpu_ms are the engine's last measured render times (they lag a frame or two); sim_steps are the model's
## steps run between this line's frame and the next. surf_pipes and spec_pipes are the pipelines compiled since the line
## before (a pipeline compiled after the start is a hitch on a phone: decision 0060), and events what else the app
## started in that frame (`counters`: sounds loaded and started, saves, route searches; each name with how many),
## so that a long frame can be told from the phone's own work (phone/frames.sh pulls frames.csv).
extends Node

var main: Node
var rows := PackedStringArray()
var _first_phys := 0
var _phys_n := 0
var _proc0 := 0
var _proc1 := 0
var _pre := 0
var _post := 0
var _frame0 := 0      # the previous frame's first callback
var _steps0 := 0
var _phys_first: Node
var _proc_first: Node
var _proc_last: Node
var _pipes0 := Vector2i.ZERO
## name -> Callable returning a count that only grows: a change between two lines is written in `events`
var counters := {}
var _counts := {}


class Hook extends Node:
	var on_phys: Callable
	var on_proc: Callable
	func _physics_process(_d: float) -> void:
		if on_phys.is_valid():
			on_phys.call()
	func _process(_d: float) -> void:
		if on_proc.is_valid():
			on_proc.call()


func _ready() -> void:
	_phys_first = Hook.new()
	_phys_first.process_physics_priority = -2147483647
	_phys_first.on_phys = _phys_begin
	_proc_first = Hook.new()
	_proc_first.process_priority = -2147483647
	_proc_first.on_proc = _proc_begin
	_proc_last = Hook.new()
	_proc_last.process_priority = 2147483647
	_proc_last.on_proc = _proc_end
	add_child(_phys_first)
	add_child(_proc_first)
	add_child(_proc_last)
	RenderingServer.frame_pre_draw.connect(func(): _pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): _post = Time.get_ticks_usec())
	var c = main.ui.clock if main != null and main.ui != null else null
	_steps0 = c.engine.step_no if c != null and c.engine != null else 0
	rows.append("t_ms,frame_ms,phys_n,phys_ms,proc_ms,to_draw_ms,draw_ms,after_ms,cpu_ms,gpu_ms,draws,objects,sim_steps,surf_pipes,spec_pipes,x,y,z,events")
	_pipes0 = pipelines()
	if main != null and main.ui != null:
		add_app_counters(main.ui)
	for k in counters:
		_counts[k] = int(counters[k].call())


## The pipelines Godot has compiled so far (surface, specialization).
static func pipelines() -> Vector2i:
	return Vector2i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))


## What the plant's UI starts now and then on the main thread: sound files loaded and players started, the run's saves
## written, the walking directions' searches and drawings.
func add_app_counters(u) -> void:
	if u.sounds != null:
		counters["sound_files"] = func(): return u.sounds._streams.size()
		counters["sounds"] = func():
			var n := 0
			for k in u.sounds.played:
				n += int(u.sounds.played[k])
			return n + u.sounds.loops_started
	if u.autosave != null:   # (counted when a save's thread is joined: its capture was a frame or more before)
		counters["save"] = func(): return u.autosave.saves
	if u.route != null:
		counters["route_find"] = func(): return u.route.stats.finds
		counters["route_draw"] = func(): return u.route.stats.draws


## The counters that changed since the last call, as "name+n" separated by spaces.
func _events() -> String:
	var ev := PackedStringArray()
	for k in counters:
		var v := int(counters[k].call())
		var d: int = v - int(_counts.get(k, 0))
		if d != 0:
			ev.append("%s+%d" % [k, d])
		_counts[k] = v
	return " ".join(ev)


func _phys_begin() -> void:
	if _phys_n == 0:
		_first_phys = Time.get_ticks_usec()
	_phys_n += 1


func _proc_begin() -> void:
	_proc0 = Time.get_ticks_usec()


func _proc_end() -> void:
	var now := Time.get_ticks_usec()
	var start := _first_phys if _phys_n > 0 else _proc0
	# this frame's own work (its scripts have run) and where the walker stands now: written with this frame's line,
	# which comes at the end of the next frame's scripts, once this frame has been drawn
	var ev_now := _events()
	var at_now := Vector3.ZERO   # plant coordinates: x east, y north, z up
	if main != null and main.player != null:
		var gp: Vector3 = main.player.global_position
		at_now = Vector3(gp.x, -gp.z, gp.y)
	# the previous frame, now that its draw has happened (without a display, as in the tests, nothing is drawn)
	if _frame0 > 0:
		var drawn := _pre >= _proc1 and _post >= _pre
		var vp: RID = get_viewport().get_viewport_rid()
		var steps := 0
		var c = main.ui.clock if main != null and main.ui != null else null
		if c != null:
			steps = c.engine.step_no if c.engine != null else 0
		var pipes := pipelines()
		var at := _prev_at
		rows.append("%d,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%d,%d,%.1f,%.1f,%.1f,%s" % [
			_frame0 / 1000, (start - _frame0) / 1000.0, _prev_phys_n, _prev_phys_ms, (_proc1 - _prev_proc0) / 1000.0,
			(_pre - _proc1) / 1000.0 if drawn else 0.0, (_post - _pre) / 1000.0 if drawn else 0.0,
			(start - (_post if drawn else _proc1)) / 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), steps - _steps0,
			pipes.x - _pipes0.x, pipes.y - _pipes0.y, at.x, at.y, at.z, _prev_ev])
		_steps0 = steps
		_pipes0 = pipes
	_prev_ev = ev_now
	_prev_at = at_now
	_prev_phys_n = _phys_n
	_prev_phys_ms = (_proc0 - _first_phys) / 1000.0 if _phys_n > 0 else 0.0
	_prev_proc0 = _proc0
	_proc1 = now
	_frame0 = start
	_phys_n = 0

var _prev_phys_n := 0
var _prev_phys_ms := 0.0
var _prev_proc0 := 0
var _prev_ev := ""
var _prev_at := Vector3.ZERO


func write(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("frames.csv"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(rows) + "\n")
