## Walking and running (the user, 2026-10-22: "walking speed should be adjustable and variable like real life"):
##   speeds       a stick's push maps to a slow step, the pace at WALK_PUSH and a jog all the way; keys walk at the
##                pace; the run modifier runs; the settings' pace moves the walk
##   controls     on the built ground with the app's own input actions: W walks, Shift runs (held, or toggled), the
##                left stick half pushed steps slowly and fully pushed jogs, its click runs, a touch stick's push is
##                analogue too; speeding up and slowing down are gradual
##   stairs       up and down a flight of HRSG 1's stair tower running, walking and at the slowest step: never faster
##                than the stair's limits; up and down the stack's ladder running: never faster than climbing
##   cadence      the footsteps' stride and level follow the speed (about 2 a second at a walk, 3 running, louder)
##   head bob     the eye dips and sways in step while walking; none with reduced motion, none standing
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Player = preload("res://app/player.gd")
const Autopilot = preload("res://app/autopilot.gd")
const SoundPlayer = preload("res://ui/sound_player.gd")
const Controls = preload("res://app/controls.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = speeds()
	p.append_array(cadence())
	var world := Node3D.new()
	tree.root.add_child(world)
	world.add_child(Controls.new())          # the input actions, as the app makes them (once: kept when there)
	var plant := Plant.new()
	world.add_child(plant)
	var err := plant.load_plant()
	if err != "":
		world.free()
		return p + [err]
	var player := Player.new()
	world.add_child(player)
	p.append_array(await controls(tree, player))
	p.append_array(await bob(tree, player))
	p.append_array(await stairs(tree, world, plant, player))
	world.free()
	return p

func speeds() -> Array:
	var p: Array = []
	var walk := Player.WALK_SPEED
	if Player.speed_for(0.0, false, true) != 0.0 or Player.speed_for(0.0, true, false) != 0.0:
		p.append("no push moves the walker")
	if not is_equal_approx(Player.speed_for(1.0, false, false), walk) or not is_equal_approx(Player.speed_for(1.0, true, false), Player.RUN_SPEED):
		p.append("keys: %.2f walking, %.2f running" % [Player.speed_for(1.0, false, false), Player.speed_for(1.0, true, false)])
	if absf(walk - 1.4) > 0.1 or Player.RUN_SPEED < 3.0 or Player.RUN_SPEED > 4.5:
		p.append("a walk is %.2f m/s and a run %.2f, not about 1.4 and 3 to 4" % [walk, Player.RUN_SPEED])
	# a stick: slow step, the pace at WALK_PUSH, a jog all the way, never slower for a further push
	var lo := Player.speed_for(0.02, false, true)
	if lo > 0.7:
		p.append("a stick just pushed goes %.2f m/s, not a slow step" % lo)
	if not is_equal_approx(Player.speed_for(Player.WALK_PUSH, false, true), walk):
		p.append("a stick at %.2f goes %.2f m/s, not the pace" % [Player.WALK_PUSH, Player.speed_for(Player.WALK_PUSH, false, true)])
	var full := Player.speed_for(1.0, false, true)
	if full < 2.5 or full > 4.0:
		p.append("a stick all the way goes %.2f m/s, not a jog" % full)
	if not is_equal_approx(Player.speed_for(1.0, true, true), Player.RUN_SPEED):
		p.append("a stick all the way with the run modifier goes %.2f m/s" % Player.speed_for(1.0, true, true))
	var last := 0.0
	var last_fast := 0.0
	for i in range(1, 101):
		var v := Player.speed_for(i / 100.0, false, true)
		var vf := Player.speed_for(i / 100.0, true, true)
		if v < last - 1e-6 or vf < last_fast - 1e-6 or vf < v - 1e-6:
			p.append("a stick at %.2f goes %.2f (running %.2f): slower than a smaller push" % [i / 100.0, v, vf])
			break
		last = v
		last_fast = vf
	# the settings' pace moves the walk, keys and stick alike
	for k in Player.PACES:
		var pace: float = Player.PACES[k]
		if not is_equal_approx(Player.speed_for(1.0, false, false, pace), pace) \
				or not is_equal_approx(Player.speed_for(Player.WALK_PUSH, false, true, pace), pace):
			p.append("the pace %s (%.2f) is not walked at" % [k, pace])
	if not (Player.PACES.slow < Player.PACES.normal and Player.PACES.normal < Player.PACES.brisk):
		p.append("the paces are not slow, normal, brisk: %s" % str(Player.PACES))
	return p

func cadence() -> Array:
	var p: Array = []
	var walk_hz := Player.WALK_SPEED / Player.stride_for(Player.WALK_SPEED)
	var run_hz := Player.RUN_SPEED / Player.stride_for(Player.RUN_SPEED)
	if walk_hz < 1.7 or walk_hz > 2.2 or run_hz < 2.6 or run_hz > 3.5:
		p.append("footsteps %.2f a second walking, %.2f running: not about 2 and 3" % [walk_hz, run_hz])
	var last_hz := 0.0
	var last_db := -INF
	for i in range(1, 41):
		var v := i * 0.1
		var hz := v / Player.stride_for(v)
		var db := SoundPlayer.step_gain_db(v)
		if hz < last_hz or db < last_db:
			p.append("at %.1f m/s the footsteps are slower (%.2f a second) or softer (%.1f dB) than slower" % [v, hz, db])
			break
		last_hz = hz
		last_db = db
	if SoundPlayer.step_gain_db(Player.WALK_SPEED) != 0.0 or SoundPlayer.step_gain_db(Player.RUN_SPEED) < 3.0 \
			or SoundPlayer.step_gain_db(Player.SLOW_SPEED) > -1.0:
		p.append("footsteps' level: %.1f dB walking, %.1f running, %.1f stepping slowly" % [SoundPlayer.step_gain_db(Player.WALK_SPEED),
			SoundPlayer.step_gain_db(Player.RUN_SPEED), SoundPlayer.step_gain_db(Player.SLOW_SPEED)])
	return p

## On the ground south of the turbine hall, facing a clear 12 m (tests/test_ui_walk_sounds.gd walks it too).
func _start(tree: SceneTree, player) -> void:
	var a := Plant.g(86, 34.5, 0)
	var b := Plant.g(93.5, 44.5, 0)
	player.set_mode(Player.Mode.FLY)
	player.global_position = a + Vector3.UP * 0.05
	player.set_mode(Player.Mode.WALK)
	player.velocity = Vector3.ZERO
	player.set_heading(atan2(-(b.x - a.x), -(b.z - a.z)))
	for i in 10:
		await tree.physics_frame

func _speed(player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()

func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame

static func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

static func _axis(a: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)

static func _button(b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)

func _release_all() -> void:
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_button(JOY_BUTTON_LEFT_STICK, false)
	for a in ["move_forward", "run"]:
		Input.action_release(a)

func controls(tree: SceneTree, player) -> Array:
	var p: Array = []
	player.scripted = false
	player.input_enabled = true
	# W: speeds up gradually to the pace
	await _start(tree, player)
	_key(KEY_W, true)
	await _frames(tree, 6)
	var early := _speed(player)
	await _frames(tree, 54)
	var walking := _speed(player)
	if early > 0.6 * Player.WALK_SPEED or absf(walking - Player.WALK_SPEED) > 0.05:
		p.append("W: %.2f m/s after 0.1 s (not gradual) and %.2f after 1 s (not the pace)" % [early, walking])
	# Shift held: runs
	_key(KEY_SHIFT, true)
	await _frames(tree, 72)
	if absf(_speed(player) - Player.RUN_SPEED) > 0.05:
		p.append("W and Shift: %.2f m/s, not a run" % _speed(player))
	_key(KEY_SHIFT, false)
	await _frames(tree, 30)
	if absf(_speed(player) - Player.WALK_SPEED) > 0.05:
		p.append("Shift let go: %.2f m/s, not back to the pace" % _speed(player))
	_key(KEY_W, false)
	await _frames(tree, 6)
	var stopping := _speed(player)
	await _frames(tree, 24)
	if stopping < 0.05 or _speed(player) > 0.01:
		p.append("W let go: %.2f m/s after 0.1 s (not gradual), %.2f after 0.5 s (not stopped)" % [stopping, _speed(player)])
	# the settings' pace
	await _start(tree, player)
	player.pace = Player.PACES.brisk
	_key(KEY_W, true)
	await _frames(tree, 60)
	if absf(_speed(player) - Player.PACES.brisk) > 0.05:
		p.append("W at a brisk pace: %.2f m/s, not %.2f" % [_speed(player), Player.PACES.brisk])
	_key(KEY_W, false)
	player.pace = Player.WALK_SPEED
	# the run key toggling (the accessibility setting): pressed once it runs, again it walks, stopping ends it
	await _start(tree, player)
	player.run_toggle = true
	_key(KEY_SHIFT, true)
	_key(KEY_SHIFT, false)
	await _frames(tree, 10)
	_key(KEY_W, true)
	await _frames(tree, 72)
	var toggled := _speed(player)
	_key(KEY_W, false)                 # let go a moment (a stick flicked through its dead zone): still running
	await _frames(tree, 2)
	_key(KEY_W, true)
	await _frames(tree, 30)
	if absf(_speed(player) - Player.RUN_SPEED) > 0.05:
		p.append("a toggled run ends when the controls let go for a moment: %.2f m/s" % _speed(player))
	_key(KEY_SHIFT, true)
	_key(KEY_SHIFT, false)
	await _frames(tree, 30)
	var untoggled := _speed(player)
	if absf(toggled - Player.RUN_SPEED) > 0.05 or absf(untoggled - Player.WALK_SPEED) > 0.05:
		p.append("the run key toggling: %.2f m/s after one press (not a run), %.2f after another (not a walk)" % [toggled, untoggled])
	_key(KEY_SHIFT, true)
	_key(KEY_SHIFT, false)
	await _frames(tree, 10)
	_key(KEY_W, false)
	await _frames(tree, 30)
	_key(KEY_W, true)
	await _frames(tree, 72)
	if absf(_speed(player) - Player.WALK_SPEED) > 0.05:
		p.append("a toggled run goes on after the walker stopped: %.2f m/s" % _speed(player))
	_key(KEY_W, false)
	player.run_toggle = false
	# the left stick: half pushed a slow step, all the way a jog, clicked a run
	await _start(tree, player)
	_axis(JOY_AXIS_LEFT_Y, -0.5)
	await _frames(tree, 60)
	var push: float = Input.get_vector("move_left", "move_right", "move_back", "move_forward").length()
	var half := _speed(player)
	if absf(half - Player.speed_for(push, false, true)) > 0.05 or half >= Player.WALK_SPEED or half < Player.SLOW_SPEED:
		p.append("the stick half pushed (%.2f past its dead zone): %.2f m/s, not a slow step (%.2f)" % [push, half, Player.speed_for(push, false, true)])
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _frames(tree, 60)
	if absf(_speed(player) - Player.JOG_SPEED) > 0.05:
		p.append("the stick all the way: %.2f m/s, not a jog" % _speed(player))
	_button(JOY_BUTTON_LEFT_STICK, true)
	await _frames(tree, 30)
	if absf(_speed(player) - Player.RUN_SPEED) > 0.05:
		p.append("the stick all the way and clicked: %.2f m/s, not a run" % _speed(player))
	_button(JOY_BUTTON_LEFT_STICK, false)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _frames(tree, 40)
	# a touch stick (Godot's VirtualJoystick presses the actions with its push's strength): analogue
	await _start(tree, player)
	Input.action_press("move_forward", 0.6)
	await _frames(tree, 60)
	push = Input.get_vector("move_left", "move_right", "move_back", "move_forward").length()
	if absf(_speed(player) - Player.speed_for(push, false, true)) > 0.05 or _speed(player) >= Player.WALK_SPEED:
		p.append("a touch stick pushed to %.2f: %.2f m/s, not %.2f" % [push, _speed(player), Player.speed_for(push, false, true)])
	_release_all()
	await _frames(tree, 40)
	return p

func bob(tree: SceneTree, player) -> Array:
	var p: Array = []
	var rest := Vector3(0, Player.EYE, 0)
	for on in [true, false]:
		await _start(tree, player)
		player.bob = on
		_key(KEY_W, true)
		var lo := INF
		var side := 0.0
		for i in 120:
			await tree.physics_frame
			lo = minf(lo, player.pivot.position.y)
			side = maxf(side, absf(player.pivot.position.x))
		_key(KEY_W, false)
		if on and (Player.EYE - lo < 0.005 or Player.EYE - lo > 0.05 or side < 0.003):
			p.append("head bob walking: the eye dips %.3f m and sways %.3f m" % [Player.EYE - lo, side])
		if not on and (not is_equal_approx(lo, Player.EYE) or side != 0.0):
			p.append("with reduced motion the eye still moves walking (%.3f down, %.3f aside)" % [Player.EYE - lo, side])
		await _frames(tree, 60)
		if player.pivot.position != rest:
			p.append("standing, the eye is not back at rest: %s" % str(player.pivot.position))
	player.bob = true
	return p

## Follows autopilot steps; the most speed in plan seen on a stair, and the most up or down on a ladder.
func _follow(tree: SceneTree, world: Node, player, route: Array) -> Dictionary:
	var auto := Autopilot.new()
	world.add_child(auto)
	# on a stair: once on it for a quarter of a second (the walker slows at DECEL as it steps on); on a ladder: between
	# two frames both on it (taking it and leaving it place the climber)
	var st := {"stuck": "", "done": false, "stair": 0.0, "stair_frames": 0, "climb": 0.0}
	auto.stuck.connect(func(i, at): st.stuck = "stuck at step %d at %s" % [i, str(at)])
	auto.finished.connect(func(): st.done = true)
	auto.start(player, route)
	var y: float = player.global_position.y
	var was_climbing := false
	var on_stair := 0
	for i in 60 * 120:
		await tree.physics_frame
		var climbing: bool = player.mode == Player.Mode.CLIMB
		if climbing and was_climbing:
			st.climb = maxf(st.climb, absf(player.global_position.y - y) * 60.0)
		on_stair = on_stair + 1 if player.on_stair and not climbing else 0
		if on_stair > 15:
			st.stair = maxf(st.stair, _speed(player))
			st.stair_frames += 1
		was_climbing = climbing
		y = player.global_position.y
		if st.done or st.stuck != "":
			break
	auto.stop()
	auto.free()
	return st

func stairs(tree: SceneTree, world: Node, plant, player) -> Array:
	var p: Array = []
	var path: Array = plant.stair_path("hrsg1_stair")
	var up: Array = path.slice(0, 4).map(func(q): return {"to": q})
	var down := up.duplicate()
	down.reverse()
	# running, walking, and at the slowest step (a stick just pushed) from the flight's foot
	var foot_up: Array = path.slice(2, 4).map(func(q): return {"to": q})
	var foot_down := foot_up.duplicate()
	foot_down.reverse()
	for gait in ["running", "walking", "at the slowest step"]:
		var fast: bool = gait == "running"
		player.run = fast
		player.pace = Player.SLOW_SPEED if gait == "at the slowest step" else Player.WALK_SPEED
		player.set_mode(Player.Mode.FLY)
		player.global_position = (path[2] if gait == "at the slowest step" else path[0]) + Vector3.UP * 0.05
		player.set_mode(Player.Mode.WALK)
		await _frames(tree, 10)
		var limit: float = Player.STAIR_RUN if fast else minf(Player.STAIR_WALK, player.pace)
		for leg in ([["up", foot_up], ["down", foot_down]] if gait == "at the slowest step" else [["up", up], ["down", down]]):
			var st: Dictionary = await _follow(tree, world, player, leg[1])
			var what := "%s HRSG 1's first flight %s" % [gait, leg[0]]
			var end: Vector3 = leg[1][-1].to
			if st.stuck != "" or not st.done or Vector2(player.global_position.x - end.x, player.global_position.z - end.z).length() > 0.5:
				p.append("%s: %s, ended at %s" % [what, st.stuck if st.stuck != "" else "did not end there", str(player.global_position)])
			elif st.stair_frames < 30 or st.stair > limit + 0.02 or st.stair < limit * 0.8:
				p.append("%s: at most %.2f m/s on the stair over %d frames, not its limit %.2f" % [what, st.stair, st.stair_frames, limit])
	player.pace = Player.WALK_SPEED
	# the stack's ladder, running: no faster than climbing
	var l: Dictionary = plant.manifest.ladders[0]
	player.run = true
	player.set_mode(Player.Mode.FLY)
	player.global_position = plant.v3(l.foot) + Vector3.UP * 0.05
	player.set_mode(Player.Mode.WALK)
	await _frames(tree, 10)
	for dir in ["up", "down"]:
		var st: Dictionary = await _follow(tree, world, player, [{"ladder": l.id, "dir": dir}])
		if st.stuck != "" or not st.done or st.climb > Player.CLIMB_SPEED + 0.02 or st.climb < Player.CLIMB_SPEED * 0.9:
			p.append("running %s the ladder %s: %s, at most %.2f m/s (climbing is %.2f)" % [dir, l.id, st.stuck, st.climb, Player.CLIMB_SPEED])
	player.run = false
	return p
