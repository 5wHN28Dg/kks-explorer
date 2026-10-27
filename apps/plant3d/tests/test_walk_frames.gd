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
	# a fast-forward that stops in the walk's first 5 s (not measured): the first measured frame is still its
	var w5 := WalkFrames.new()
	w5.seen(true)
	if w5.add(40.0, 1.0, false) or not w5.add(20.0, 1.0, false):
		p.append("the first measured frame after a fast-forward that stopped in the first 5 s is fast-forward's")
	if Array(w.ff_times) != [30.0, 150.0, 110.0]:
		p.append("fast-forward's frames' times %s" % str(w.ff_times))
	if WalkFrames.stats(w.ff_times) != "median=110.0ms p95=150.0ms p99=150.0ms max=150.0ms" or WalkFrames.stats(PackedFloat32Array()) != "":
		p.append("stats: %s" % WalkFrames.stats(w.ff_times))
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
	# (directly, and the clock driven from outside so that it never stops fast-forward itself: whether fast-forward
	# is offered is not this test's)
	main.ui.clock.driven = true
	main.ui.clock.speed = SimClock.Speed.FAST
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
	main._frame_result()
	if not "\n".join(main.lines).contains("ff_frames=%d " % main.frames.ff_frames):
		p.append("RESULT does not count fast-forward's frames")
	# a walk in fast-forward from start to end (speed=fast): no frame at 1×, still a RESULT (memory, start) and
	# fast-forward's statistics
	var only_ff := WalkFrames.new()
	for ms in [20.0, 40.0, 120.0]:
		only_ff.add(ms, 5.0, true)
	main.frames = only_ff
	main.lines.clear()
	main._frame_result()
	var got := "\n".join(main.lines)
	if not got.contains("FASTFORWARD frames=3 over100=1 median=40.0ms") or not got.contains("gpu_median=5.0ms"):
		p.append("no FASTFORWARD statistics for a walk all in fast-forward:\n" + got)
	if not got.contains(" frames=0 over100=0 ff_frames=3 ") or not got.contains("static_mem=") or got.contains("RESULT no frames"):
		p.append("no RESULT for a walk all in fast-forward:\n" + got)
	main.free()
	return p
