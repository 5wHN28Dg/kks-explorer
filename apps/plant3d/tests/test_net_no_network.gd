## No network outside a session (docs/plant3d/MULTIPLAYER.md §8.5, §12; decision 0068): the app started, a
## single-player run played and the Together panel opened and closed open no socket (the session layer's own count;
## on Linux, the process's sockets in /proc).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Udp = preload("res://net/udp.gd")


static func sockets() -> int:
	if OS.get_name() != "Linux":
		return -1
	var out := []
	OS.execute("sh", ["-c", "ls -l /proc/%d/fd 2>/dev/null | grep -c 'socket:'" % OS.get_process_id()], out)
	return str(out[0]).strip_edges().to_int() if not out.is_empty() else -1


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var s0 := sockets()
	var o0 := Udp.opened
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	ui.clock.set_speed(1)
	ui.clock.run_steps(200)
	ui.inputs.op("00QFA10AN001", "start")
	ui.clock.run_steps(20)
	ui.open_session()
	for i in 10:
		await tree.process_frame
	ui.close_session()
	if Udp.opened != o0:
		p.append("a single-player run opened %d socket(s)" % (Udp.opened - o0))
	var s1 := sockets()
	if s0 >= 0 and s1 != s0:
		p.append("the process's sockets went from %d to %d" % [s0, s1])
	if ui.session != null:
		p.append("a session object exists without a session")
	main.free()
	return p
