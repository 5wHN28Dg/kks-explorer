## The frame rules judge normal play only (the user, 2026-10-27): a measured walk counts the frames played in
## fast-forward apart (app/walk_frames.gd), the frame that starts or stops it among them, logs each change of speed
## (SPEED lines, with the phone's monotonic clock for phone/frames.sh) and logs a long frame in fast-forward as
## SPIKE_FF, which tools/plant3d/bench/reclaim_frames.py does not judge.
extends RefCounted

const WalkFrames = preload("res://app/walk_frames.gd")
const SimClock = preload("res://ui/sim_clock.gd")


func run(tree: SceneTree) -> Array:
	var p := _counts()
	p.append_array(await _walk(tree))
	return p


func _counts() -> Array:
	var p: Array = []
	var w := WalkFrames.new()
	# normal, normal, fast (starts it), fast, normal (stops it: still fast-forward's), normal, normal
	var seq := [[20.0, false], [120.0, false], [30.0, true], [150.0, true], [110.0, false], [25.0, false], [40.0, false]]
	var judged: Array = []
	for f in seq:
		judged.append(w.add(f[0], 1.0, f[1]))
	if judged != [true, true, false, false, false, true, true]:
		p.append("judged frames %s" % str(judged))
	if Array(w.times) != [20.0, 120.0, 25.0, 40.0]:
		p.append("the judged frames' times %s" % str(w.times))
	if w.gpu.size() != w.times.size():
		p.append("%d GPU times for %d frames" % [w.gpu.size(), w.times.size()])
	if w.ff_frames != 3 or w.ff_over100 != 2 or w.ff_max != 150.0:
		p.append("fast-forward: %d frames, %d over 100 ms, longest %.1f ms (want 3, 2, 150)" % [w.ff_frames, w.ff_over100, w.ff_max])
	if OS.get_name() != "Android" and WalkFrames.uptime_ms() != -1:
		p.append("uptime_ms() off Android is %d, not -1" % WalkFrames.uptime_ms())
	return p


## The app's own walk (walk=screens, the one that runs without the walker's route): fast-forward for a while, a long
## frame in it, then normal speed.
func _walk(tree: SceneTree) -> Array:
	var p: Array = []
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts = {"walk": "screens", "seconds": "600"}
	tree.root.add_child(main)
	for i in 600:
		if main.screens_walk:
			break
		await tree.process_frame
	if not main.screens_walk or main.ui == null or main.ui.clock == null:
		main.free()
		return ["walk=screens did not start"]
	main._process(6.0)                        # past the walk's first 5 s, which are not measured
	for i in 5:
		await tree.process_frame
	var normal0: int = main.frames.times.size()
	main.ui.clock.speed = SimClock.Speed.FAST   # (directly: whether fast-forward is offered is not this test's)
	for i in 10:
		await tree.process_frame
	main.last_us = Time.get_ticks_usec() - 150000
	main._process(0.15)                       # a frame of 150 ms in fast-forward
	main.ui.clock.speed = SimClock.Speed.NORMAL
	for i in 10:
		await tree.process_frame
	var lines := "\n".join(main.lines)
	if normal0 == 0:
		p.append("no frames judged before fast-forward")
	if main.frames.ff_frames < 11:
		p.append("%d frames counted in fast-forward (want at least 11)" % main.frames.ff_frames)
	if main.frames.ff_over100 < 1:
		p.append("the 150 ms frame in fast-forward was not counted")
	if main.frames.times.size() < normal0 + 5:
		p.append("frames after fast-forward not judged (%d, %d before it)" % [main.frames.times.size(), normal0])
	if not lines.contains("SPEED fast-forward at ") or not lines.contains("SPEED normal at "):
		p.append("no SPEED lines for the changes of speed:\n" + lines)
	elif not lines.contains(", uptime -1 ms"):
		p.append("a SPEED line off Android names an uptime")
	if not lines.contains("SPIKE_FF 15"):
		p.append("the long frame in fast-forward is not a SPIKE_FF line")
	for l in main.lines:
		if l.begins_with("SPIKE "):
			p.append("a frame in fast-forward logged as a judged SPIKE: " + l)
	main.free()
	return p
