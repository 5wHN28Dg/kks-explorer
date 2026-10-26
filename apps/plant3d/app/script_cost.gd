## Where the scripts' time goes in a measured walk (`probe=1`): each part's own time per frame, the frames at normal
## speed and in fast-forward apart, written as the result's SCRIPTS lines (app/main.gd). The parts add their time with
## `add(PART, t0)` (t0 from Time.get_ticks_usec()); nothing is counted unless `on` (set by app/frame_probe.gd).
## `model` is the behaviour engine's steps without step 9, `staff` step 9 (the staff, sim/staff.gd), `stepped` what
## follows each step in the app (ui/sim_clock.gd's `stepped` listeners); `scripts` is every script's _process
## together (the frame probe's proc_ms), so what the parts leave out shows too.
extends RefCounted

enum { MODEL, STAFF, STEPPED, PEOPLE_VIEW, AVATARS, CROWD, CREW, UI, MIMIC, BINDINGS, SOUNDS, PANELS, AUTOSAVE, OTHER }
const NAMES := ["model", "staff", "stepped", "people_view", "avatars", "crowd", "crew", "ui", "mimic", "bindings",
	"sounds", "panels", "autosave", "other"]

static var on := false
static var cur := PackedInt64Array()        # this frame's microseconds per part
static var frames := PackedInt64Array([0, 0])
## per speed (0 normal or paused, 1 fast-forward), per part and the scripts' whole (last): the sum and the largest
## frame in microseconds, at [speed * (parts + 1) + part] (flat: a packed array taken out of an Array is a copy)
static var sums := PackedInt64Array()
static var maxs := PackedInt64Array()
static var times_normal := PackedFloat32Array()   # the scripts' whole per frame (ms)
static var times_fast := PackedFloat32Array()


static func start() -> void:
	on = true
	cur.resize(NAMES.size())
	cur.fill(0)
	frames = PackedInt64Array([0, 0])
	sums.resize(2 * (NAMES.size() + 1))
	sums.fill(0)
	maxs.resize(sums.size())
	maxs.fill(0)
	times_normal = PackedFloat32Array()
	times_fast = PackedFloat32Array()


static func add(part: int, t0: int) -> void:
	if on:
		cur[part] += Time.get_ticks_usec() - t0


## A frame's scripts have run: its parts (and the whole, `scripts_us`) go to the frame's speed, and the next begins.
static func frame(fast: bool, scripts_us: int) -> void:
	if not on:
		return
	var f := 1 if fast else 0
	frames[f] += 1
	var o := f * (NAMES.size() + 1)
	for i in NAMES.size():
		sums[o + i] += cur[i]
		maxs[o + i] = maxi(maxs[o + i], cur[i])
	var k := o + NAMES.size()
	sums[k] += scripts_us
	maxs[k] = maxi(maxs[k], scripts_us)
	if fast:
		times_fast.append(scripts_us / 1000.0)
	else:
		times_normal.append(scripts_us / 1000.0)
	cur.fill(0)


## The result's lines: per speed, each part's mean and largest frame (ms), the scripts' whole with its 95th and 99th
## percentile.
static func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for f in 2:
		var n: int = frames[f]
		if n == 0:
			continue
		var o := f * (NAMES.size() + 1)
		var parts := PackedStringArray()
		for i in NAMES.size():
			if maxs[o + i] > 0:
				parts.append("%s=%.2f/%.2f" % [NAMES[i], sums[o + i] / 1000.0 / n, maxs[o + i] / 1000.0])
		var t := (times_fast if f == 1 else times_normal).duplicate()
		t.sort()
		var k := o + NAMES.size()
		out.append("SCRIPTS %s frames=%d scripts=%.2f/%.2f p95=%.2f p99=%.2f (ms a frame: mean/largest) %s" % [
			"fast" if f == 1 else "normal", n, sums[k] / 1000.0 / n, maxs[k] / 1000.0, t[int(n * 0.95)], t[int(n * 0.99)],
			" ".join(parts)])
	return out
