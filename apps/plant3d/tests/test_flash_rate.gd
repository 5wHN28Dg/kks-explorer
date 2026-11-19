## The lightning's flashes are safe at every speed (app/weather_view.gd; UI-UX-POLICY A10, no seizures; issue #443):
## the view is driven frame by frame through many seconds of real time at every clock speed (paused, 1x, each
## fast-forward up to sim_clock.gd's FF_MAX, and jumps that make hours of steps in one frame), at several frame rates,
## with the model's flashes as flash_in places them at full lightning in a night thunderstorm, and the sun's and the
## fog's light read after each frame. Counted per WCAG 2.3.1: a transition is a change of 10 % or more of the light
## (of the brighter of the two) from the last extreme, a flash a pair of them; in no 1-second window more than 3
## flashes (6 transitions), and lit flashes FLASH_GAP real seconds apart. With Reduced motion on (`soft`): no
## transition at all (the soft glow stays under 10 %), and still each of the model's flashes is counted (heard).
## The light is a proxy for the screen's luminance (the scene's light added by the flash); tools/plant3d/flash_capture.gd
## measures the rendered frames themselves.
extends RefCounted

const WeatherView = preload("res://app/weather_view.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const SEED := 7
const SECONDS := 120.0


## The engine as the view reads it: its step.
class FakeEngine extends RefCounted:
	var step_no := 0


func run(_tree: SceneTree) -> Array:
	var p: Array = []
	var speeds := [0.0, 1.0, 2.0, 5.0, 10.0, 20.0, 30.0, SimClock.FF_MAX]
	var frames := [1.0 / 60.0, 1.0 / 144.0, 1.0 / 30.0, 1.0 / 10.0, -1.0]   # -1: uneven frames, 7 to 50 ms
	for soft in [false, true]:
		for speed in speeds:
			for dt in frames:
				p += _check(speed, dt, soft, false)
		p += _check(1.0, 1.0 / 60.0, soft, true)     # jumps: hours of steps in one frame, every 0.7 s
	return p


func _check(speed: float, dt: float, soft: bool, jumps: bool) -> Array:
	var what := "%s at %sx, %s frames%s" % ["Reduced motion" if soft else "flashes", str(speed),
			"uneven" if dt < 0.0 else "%.0f fps" % (1.0 / dt), ", with jumps" if jumps else ""]
	var wv = WeatherView.new()
	wv.env = Environment.new()
	wv.sun = DirectionalLight3D.new()
	wv.particles = WeatherView.make_particles("phone")
	wv.ui = RefCounted.new()          # no sounds
	wv.set("soft", soft)
	# a night thunderstorm: the sun at its night level, full lightning
	wv.look = WeatherView.look_of({"visibility": 3000.0, "rain": 8.0, "wind": 12.0, "lightning": 1.0, "wet": 1.0}, 0.0)
	var e := FakeEngine.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var t := 0.0
	var acc := 0.0                    # steps owed (the clock steps 10 a second times the speed)
	var next_jump := 0.7
	var want := 0                     # the model's flashes come by now
	var times: PackedFloat64Array = []
	var light: PackedFloat64Array = []
	while t < SECONDS:
		var d := dt if dt > 0.0 else rng.randf_range(0.007, 0.05)
		t += d
		acc += d * 10.0 * speed
		var n := int(acc)
		acc -= n
		if jumps and t >= next_jump:
			n += 36000                # an hour of plant time at once
			next_jump += 0.7
		# the clock's `stepped` after each step: a slot's first step decides its flash (as _on_step)
		var k0: int = e.step_no / WeatherView.FLASH_SLOT + 1
		e.step_no += n
		for k in range(k0, e.step_no / WeatherView.FLASH_SLOT + 1):
			var f := WeatherView.flash_in(SEED, k, 1.0)
			if not f.is_empty():
				wv._pending.append(f)
				want += 1
		wv._flash(e, d)
		wv._apply(wv.look)
		times.append(t)
		light.append(wv.sun.light_energy)
	var p: Array = []
	var tr := transitions(times, light)
	var worst := max_in_window(tr, 1.0)
	if worst > 6:
		p.append("%s: %d changes of the light in one second (%.1f flashes; at most 3)" % [what, worst, worst / 2.0])
	if soft and not tr.is_empty():
		p.append("%s: %d changes of 10 %% or more of the light (a soft glow has none)" % [what, tr.size()])
	# every flash the model made is still counted (heard), lit or not; the pending ones still to come
	var come: int = want - wv._pending.size()
	if wv.flashes != come:
		p.append("%s: %d flashes counted, the model made %d" % [what, wv.flashes, come])
	if speed >= 1.0 and wv.get("lit") != null and int(wv.get("lit")) == 0:
		p.append("%s: no flash lit in %d s of a thunderstorm" % [what, int(SECONDS)])
	wv.particles.free()
	wv.sun.free()
	wv.free()
	return p


## The times of the light's transitions: a change of 10 % or more (of the brighter value) from the last extreme,
## each in the other direction from the one before (WCAG 2.3.1's pair of opposing changes makes a flash).
static func transitions(times: PackedFloat64Array, light: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = []
	if light.is_empty():
		return out
	var ref := light[0]
	var dir := 0                      # 1 the last transition rose, -1 it fell, 0 none yet
	for i in range(1, light.size()):
		var x := light[i]
		var hi := maxf(x, ref)
		if hi <= 0.0:
			continue
		if dir != 1 and x > ref and (x - ref) / hi >= 0.1:
			out.append(times[i])
			dir = 1
			ref = x
		elif dir != -1 and x < ref and (ref - x) / hi >= 0.1:
			out.append(times[i])
			dir = -1
			ref = x
		elif (dir == 1 and x > ref) or (dir == -1 and x < ref):
			ref = x                   # the extreme moves on in the same direction
	return out


## The most transitions in any window of `w` seconds.
static func max_in_window(tr: PackedFloat64Array, w: float) -> int:
	var best := 0
	var j := 0
	for i in tr.size():
		while tr[i] - tr[j] > w:
			j += 1
		best = maxi(best, i - j + 1)
	return best
