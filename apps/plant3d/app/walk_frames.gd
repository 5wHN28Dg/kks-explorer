## Which of a measured walk's frames the frame rules judge (the user, 2026-10-27; docs/plant3d/MILESTONES.md): the
## rules (≥ 95 % of frames at ≥ 30 fps, none over 100 ms after the first 5 s that the app causes) apply to normal play
## only; fast-forward may drop frames on a phone. A frame is played in fast-forward when the clock was fast-forwarding
## at its start or at its end (the frame that starts or stops it carries fast-forward's work): it is counted apart and
## left out of the judged frames. app/main.gd logs each change of speed with the phone's monotonic clock
## (SystemClock.uptimeMillis, the clock of SurfaceFlinger's present times), so that phone/frames.sh can leave the same
## frames out of what the screen showed (tools/plant3d/bench/sf_frames.py --speeds).
extends RefCounted

var times := PackedFloat32Array()   # the judged frames' intervals (ms): played at 1× (or paused)
var gpu := PackedFloat32Array()     # and their GPU times
var ff_times := PackedFloat32Array()   # the frames played in fast-forward (ms), left out
var ff_gpu := PackedFloat32Array()
var ff_frames := 0                  # how many
var ff_over100 := 0                 # of them, over 100 ms
var ff_max := 0.0                   # the longest of them (ms)
var _was_ff := false


## Adds a frame of `ms` (its GPU time `gpu_ms`), `ff` whether the clock is fast-forwarding now. True when the frame
## is judged.
func add(ms: float, gpu_ms: float, ff: bool) -> bool:
	var left_out := ff or _was_ff
	_was_ff = ff
	if left_out:
		ff_frames += 1
		ff_times.append(ms)
		ff_gpu.append(gpu_ms)
		ff_max = maxf(ff_max, ms)
		if ms > 100.0:
			ff_over100 += 1
		return false
	times.append(ms)
	gpu.append(gpu_ms)
	return true


## "median=… p95=… p99=… max=…" of `t` (ms), sorted here; "" when empty.
static func stats(t: PackedFloat32Array, prefix := "") -> String:
	var n := t.size()
	if n == 0:
		return ""
	var s := t.duplicate()
	s.sort()
	return "%smedian=%.1fms %sp95=%.1fms %sp99=%.1fms %smax=%.1fms" % [prefix, s[n / 2], prefix, s[int(n * 0.95)],
		prefix, s[int(n * 0.99)], prefix, s[n - 1]]


## The phone's monotonic clock in ms (Android's SystemClock.uptimeMillis, the clock SurfaceFlinger stamps its frames
## with), or -1 where there is none.
static func uptime_ms() -> int:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return -1
	var c = JavaClassWrapper.wrap("android.os.SystemClock")
	if c == null:
		return -1
	var v = c.uptimeMillis()
	return int(v) if (v is int or v is float) else -1
