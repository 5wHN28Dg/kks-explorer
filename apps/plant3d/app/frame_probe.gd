## Where a frame's time goes (the laptop's 60 fps rule, decision 0057): `--probe=1` with a walk writes frames.csv
## beside result.txt, one line per frame: the physics steps and their time, the scripts' _process, the time up to the
## draw, the draw itself (RenderingServer's frame_pre_draw to frame_post_draw: the render thread's CPU work and any wait
## for the GPU or the swap chain), the rest (the OS's events, the wait for the next frame), and what the systems did.
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
	rows.append("t_ms,frame_ms,phys_n,phys_ms,proc_ms,to_draw_ms,draw_ms,after_ms,cpu_ms,gpu_ms,draws,objects,sim_steps")


func _phys_begin() -> void:
	if _phys_n == 0:
		_first_phys = Time.get_ticks_usec()
	_phys_n += 1


func _proc_begin() -> void:
	_proc0 = Time.get_ticks_usec()


func _proc_end() -> void:
	var now := Time.get_ticks_usec()
	var start := _first_phys if _phys_n > 0 else _proc0
	# the previous frame, now that its draw has happened
	if _frame0 > 0 and _post > 0:
		var vp: RID = get_viewport().get_viewport_rid()
		var steps := 0
		var c = main.ui.clock if main.ui != null else null
		if c != null:
			steps = c.engine.step_no if c.engine != null else 0
		rows.append("%d,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d" % [
			_frame0 / 1000, (start - _frame0) / 1000.0, _prev_phys_n, _prev_phys_ms, (_proc1 - _prev_proc0) / 1000.0,
			(_pre - _proc1) / 1000.0, (_post - _pre) / 1000.0, (start - _post) / 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), steps - _steps0])
		_steps0 = steps
	_prev_phys_n = _phys_n
	_prev_phys_ms = (_proc0 - _first_phys) / 1000.0 if _phys_n > 0 else 0.0
	_prev_proc0 = _proc0
	_proc1 = now
	_frame0 = start
	_phys_n = 0

var _prev_phys_n := 0
var _prev_phys_ms := 0.0
var _prev_proc0 := 0


func write(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("frames.csv"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(rows) + "\n")
