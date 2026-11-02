## The trainee driving a bus (docs/PLANT3D.md §21.16): when their person is a vehicle's driver on a run, the app takes
## the wheel (the `drive` input "wheel") and the bus is theirs to steer: a kinematic bicycle model on the ground, moved
## each physics frame by the controls (keyboard, gamepad, the left touch stick), stopped dead by the world's solids and
## the other vehicles, braked by itself for people ahead; "Open the doors" standing still near a stop sends "stop" at
## it, "Close the doors" sends "go", the wheel button gives the engine the wheel back ("auto") and takes it again.
## Nothing here is in the model but those inputs: where the bus is on the road is this app's (and its `pos`, which the
## session's others draw the bus from, net/session.gd POS_DRIVING). Off route (more than 15 m from the run's roads),
## the near misses and each stop's lateness against the run's timetable go to `log` for the debrief (saved with the
## run). The bar at the bottom of the screen shows the speed, the next stop and the buttons while driving.
extends Node

const Cost = preload("res://app/script_cost.gd")

const MAX_FWD := 40.0 / 3.6         # m/s
const MAX_REV := 8.0 / 3.6
const ACCEL := 1.5                  # m/s²
const BRAKE := 4.0
const AUTO_BRAKE := 6.0
const ROLL := 0.3                   # coasting
const MAX_STEER := deg_to_rad(35.0)
const STEER_RATE := deg_to_rad(60.0)    # how fast the wheels turn, per second
const DOOR_RANGE := 10.0            # m from the bus's sides and ends to a stop or depot place: the doors may open there
const OFF_ROUTE := 15.0             # m from the run's roads
const NEAR_MISS := 2.0              # m/s: an automatic brake above it is a near miss
const CLEAR := 2.0                  # m beyond the stopping distance that must be clear of people
const STILL := 0.2                  # m/s: standing still

var ui                              # ui/plant_ui.gd
var vi := -1                        # the engine's vehicle the trainee drives (has the wheel), -1 none
var xf := Transform3D()             # where it is (app/vehicles.gd's frame)
var speed := 0.0                    # m/s along its heading, negative reversing
var steer := 0.0                    # the front wheels' angle (radians, left positive)
var want_wheel := true              # the trainee steers (the wheel button: the engine drives meanwhile)
var control = null                  # tests: Vector3(throttle, brake, steer) for the controls
var pilot := false                  # the drive walk (app/main.gd walk=drive): the app drives the run itself, on its
									# lane along the run's roads, stopping at each stop and leaving by the timetable
									# (_rail)
var braking := false                # the automatic brake holds (someone ahead)
var extra_people: Array = []        # tests: more people (global positions) for the automatic brake
var blocked := 0                    # physics frames a solid stopped it (the drive walk's DRIVE line, tests)
var blocked_by := ""                # what it ran into last
var _rail_key := ""                 # the drive walk's lane: for which [from, to], its points, how far along it is
var _rail_path := PackedVector3Array()
var _rail_s := 0.0
var _barrier_done := {}             # the bodies the barriers were let through for
var _route_key := ""                # the run's roads from here (off route), and for which state of the run
var _route: Array = []
var off_route := false
var log: Array = []                 # per run driven: {"vehicle", "dep", "stops": [[stop, "arrive"|"passed"|"stand",
									#  late clock minutes or null]], "off_route_s", "near_misses"}
var half_w := 1.3                   # the bus's half width and its front and back (body frame, -Z forward)
var front := -6.0
var back := 6.0
var wheelbase := 6.0
var seat := Vector3(-0.7, 0.4, -4.6)    # the driver's seat (the walker's feet)
var _sent := -1                     # the step the last drive input was sent at, and what it was (_send)
var _sent_key := ""
var _ev_seen := 0
var _log_vi := -1                   # the vehicle whose run is being logged, -1 none, and that run [run, D]
var _log_run := [-1, 0]
var _bar: Control
var _label: Label
var _doors: Button
var _wheel: Button
var _near: int = -1                 # the stop or depot place within reach, -1


func setup(u) -> void:
	ui = u
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var box := HBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -330
	box.offset_right = 330
	box.offset_top = -64
	box.offset_bottom = -12
	box.add_theme_constant_override("separation", 10)
	var bg := PanelContainer.new()
	bg.add_child(box)
	bg.anchor_left = 0.5
	bg.anchor_right = 0.5
	bg.anchor_top = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = -340
	bg.offset_right = 340
	bg.offset_top = -72
	bg.offset_bottom = -8
	layer.add_child(bg)
	_bar = bg
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_label)
	_doors = Button.new()
	_doors.focus_mode = Control.FOCUS_NONE
	_doors.pressed.connect(doors)
	box.add_child(_doors)
	_wheel = Button.new()
	_wheel.focus_mode = Control.FOCUS_NONE
	_wheel.pressed.connect(toggle_wheel)
	box.add_child(_wheel)
	_bar.visible = false


## The vehicle the trainee's person drives on a run, -1 none.
func driver_of() -> int:
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	if e == null or e._sm == null or not "st_veh" in e:
		return -1
	var me: int = ui.my_person()
	if me == -1:
		return -1
	for k in e.st_veh.size():
		var vh: Dictionary = e.st_veh[k]
		if vh["driver"] == me and vh["run"] != -1:
			return k
	return -1


## Whether vehicle k is steered by this app's player (the engine's wheel is their slot's).
func mine(k: int) -> bool:
	var e = ui.clock.engine
	if k < 0 or k >= e.st_veh.size() or not e.st_veh[k].has("wheel"):
		return false
	var me: int = ui.my_person()
	return me != -1 and e.st_veh[k]["driver"] == me


func _physics_process(delta: float) -> void:
	if ui == null or ui.clock == null or ui.vehicles == null:
		return
	var c0 := Time.get_ticks_usec()
	_frame(delta)
	Cost.add(Cost.BINDINGS, c0)         # (as the vehicles' own frame, app/vehicles.gd)


func _frame(delta: float) -> void:
	var e = ui.clock.engine
	_log_events(e)
	var k := driver_of()
	var p = ui.player
	if k == -1:
		if vi != -1:
			_end()
		_bar.visible = false
		return
	var vh: Dictionary = e.st_veh[k]
	var V: Dictionary = ui.vehicles._drawn(k)
	if V.is_empty():
		_bar.visible = false
		return
	if not vh.has("wheel"):
		if vi != -1:
			_end()
		if want_wheel:
			_send(e, k, "wheel")
		_show(e, k, vh)
		return
	if vi != k:                         # the wheel is theirs from now: the bus where it is drawn
		vi = k
		xf = V["xf"]
		speed = 0.0
		steer = 0.0
		_rail_key = ""
		_measure(V)
		_new_run(e, k, vh)
		_barriers(V["body"])
		if p != null:
			p.driving = true
	if vh["at"] != -1:                  # standing at a place (the doors open): it does not move
		speed = 0.0
		if pilot and (e.clock() >= vh["dep"] if vh["k"] == 0 else e.step_no >= vh["until"]):
			doors()                     # (the drive walk: off again by the run's own rule)
	else:
		_drive(V, delta)
	_track(e, k, vh, delta)
	_show(e, k, vh)


## One physics frame of driving: the controls, the automatic brake, the bicycle model, the solids, the ground.
func _drive(V: Dictionary, delta: float) -> void:
	if pilot and control == null:
		_rail(V, delta)
		return
	var c: Vector3 = control if control != null else _controls()
	var throttle := clampf(c.x, 0.0, 1.0)
	var brake := clampf(c.y, 0.0, 1.0)
	var target := clampf(c.z, -1.0, 1.0) * MAX_STEER * clampf(1.0 - absf(speed) / (MAX_FWD * 1.6), 0.35, 1.0)
	steer = move_toward(steer, target, STEER_RATE * delta)
	# forward with the throttle; the brake slows it, and held at a standstill backs it up
	var a := 0.0
	if throttle > 0.0 and speed >= -STILL:
		a = throttle * ACCEL
	elif brake > 0.0 and speed > STILL:
		a = -brake * BRAKE
	elif brake > 0.0 and speed <= STILL:
		a = -brake * ACCEL
	elif throttle > 0.0 and speed < -STILL:
		a = throttle * BRAKE
	else:
		a = -signf(speed) * minf(ROLL, absf(speed) / maxf(delta, 1e-3))
	# the way it moves, or would move from a standstill: someone there and it brakes, or does not set off
	var way := signf(speed) if absf(speed) > 1e-3 else signf(a)
	var hazard := way != 0.0 and _people_ahead(way)
	if hazard:
		if not braking and absf(speed) > NEAR_MISS and not log.is_empty():
			log[-1]["near_misses"] += 1
		a = -signf(speed) * minf(AUTO_BRAKE, absf(speed) / maxf(delta, 1e-3))
	braking = hazard or (braking and absf(speed) > 1e-3 and way != 0.0 and _people_ahead(way))
	speed = clampf(speed + a * delta, -MAX_REV, MAX_FWD)
	if hazard and absf(speed) < STILL:
		speed = 0.0
	if absf(speed) < 1e-3:
		return
	# the bicycle model about the rear axle: heading turns by v/L·tan(steer)
	var yaw_rate := speed / wheelbase * tan(steer)
	var basis := xf.basis.rotated(Vector3.UP, yaw_rate * delta)
	var fwd := -basis.z
	fwd.y = 0.0
	var move := fwd.normalized() * speed * delta
	var body: AnimatableBody3D = V["body"]
	var nx := Transform3D(basis, xf.origin + move)
	var hit := KinematicCollision3D.new()
	var g: Transform3D = (body.get_parent() as Node3D).global_transform if body.is_inside_tree() else Transform3D()
	if body.is_inside_tree() and body.test_move(g * xf, g.basis * move, hit):
		speed = 0.0                     # a solid or another vehicle: stopped dead, no bounce
		blocked += 1
		var who = hit.get_collider()
		blocked_by = String(who.get_path()) if who is Node else str(who)
		return
	nx.origin.y = _ground(nx.origin, body)
	xf = nx


## The drive walk's driver (a measurement's, not a player's): the bus kept on the lane of the roads to the run's next
## target, exactly (the engine's own path: what its bus passes, this one passes too; a solid in the way is counted in
## `blocked`, not obeyed), at up to 8 m/s, accelerating and braking as the controls do, braking for people ahead,
## stopping at the road's end there, then the doors. Where the next road starts away from the last one's end (a turn
## at a stop where the run goes back the way it came) it is put on it.
func _rail(V: Dictionary, delta: float) -> void:
	var e = ui.clock.engine
	var vh: Dictionary = e.st_veh[vi]
	var key := "%d|%d" % [int(vh.get("from", vh["to"])), int(vh["to"])]
	if key != _rail_key:
		_rail_key = key
		_rail_path = ui.vehicles.lane_path(V, int(vh.get("from", vh["to"])), int(vh["to"]))
		_rail_s = _project(_rail_path, xf.origin)
	var path := _rail_path
	if path.size() < 2:
		speed = 0.0
		return
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	var left := total - _rail_s
	var want := minf(8.0, sqrt(maxf(0.0, 2.0 * 3.0 * (left - 0.5))))
	var a := ACCEL if speed < want else -BRAKE
	var hazard := _people_ahead(1.0)
	if hazard:
		if not braking and speed > NEAR_MISS and not log.is_empty():
			log[-1]["near_misses"] += 1
		a = -AUTO_BRAKE
	braking = hazard
	speed = clampf(speed + a * delta, 0.0, want if not hazard else MAX_FWD)
	if left < 0.6 and speed < STILL:
		speed = 0.0
		doors()
		return
	_rail_s = minf(total, _rail_s + speed * delta)
	var at := _at_along(path, _rail_s)
	var body: AnimatableBody3D = V["body"]
	var nx := Transform3D(Basis.looking_at(at[1], Vector3.UP), at[0])
	var g: Transform3D = (body.get_parent() as Node3D).global_transform if body.is_inside_tree() else Transform3D()
	if body.is_inside_tree() and body.test_move(g * xf, g.basis * (nx.origin - xf.origin)):
		blocked += 1
	nx.origin.y = _ground(nx.origin, body)
	xf = nx


## How far along `line` the point nearest p is (in plan).
static func _project(line: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	var at := 0.0
	var run := 0.0
	var q := Vector2(p.x, p.z)
	for i in range(1, line.size()):
		var a := Vector2(line[i - 1].x, line[i - 1].z)
		var b := Vector2(line[i].x, line[i].z)
		var ab := b - a
		var L := ab.length()
		var t := 0.0 if L < 1e-6 else clampf((q - a).dot(ab) / (L * L), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)
		if d < best:
			best = d
			at = run + t * L
		run += L
	return at


## [the point, the heading (unit, level)] at distance s along line.
static func _at_along(line: PackedVector3Array, s: float) -> Array:
	var run := 0.0
	for i in range(1, line.size()):
		var L := line[i].distance_to(line[i - 1])
		if run + L >= s and L > 1e-6:
			var d := line[i] - line[i - 1]
			d.y = 0.0
			return [line[i - 1].lerp(line[i], (s - run) / L), d.normalized() if d.length() > 1e-6 else Vector3.FORWARD]
		run += L
	var d := line[line.size() - 1] - line[line.size() - 2]
	d.y = 0.0
	return [line[line.size() - 1], d.normalized() if d.length() > 1e-6 else Vector3.FORWARD]


## The controls as Vector3(throttle, brake, steer): W/S and the left stick (or the left touch stick), the triggers,
## Space to brake; steering left positive.
func _controls() -> Vector3:
	var fwd := Input.get_action_strength("move_forward")
	var back_ := Input.get_action_strength("move_back")
	var th := maxf(fwd, Input.get_action_strength("throttle"))
	var br := maxf(maxf(back_, Input.get_action_strength("brake")), Input.get_action_strength("up"))
	var st := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	return Vector3(th, br, st)


## Someone within the bus's width (and half a metre) ahead of it, closer than its stopping distance and CLEAR (behind
## it when reversing): the people the crews view draws, the session's other players.
func _people_ahead(way: float) -> bool:
	var reach := speed * speed / (2.0 * AUTO_BRAKE) + CLEAR
	var gx: Transform3D = ui.vehicles.global_transform * xf
	var inv := gx.affine_inverse()
	for at in _people():
		var l: Vector3 = inv * at
		if absf(l.x) > half_w + 0.5 or absf(l.y) > 3.0:
			continue
		if way > 0.0 and l.z <= front and l.z >= front - reach:
			return true
		if way < 0.0 and l.z >= back and l.z <= back + reach:
			return true
	return false


func _people() -> Array:
	var out := extra_people.duplicate()
	var pv = ui.people if "people" in ui else null
	if pv != null and "_was" in pv:
		for k in pv._was.size():
			if k < pv._was_ok.size() and pv._was_ok[k] == 1:
				out.append(pv.global_transform * pv._was[k])
	if "others" in ui and ui.others != null and "session" in ui.others and ui.others.session != null:
		for sl in ui.others.shown:
			var at: Array = ui.others.session.position_of(sl)
			if not at.is_empty():
				out.append(at[0])
	return out


## The ground under the bus: the highest floor within 3 m above and 6 m below (it keeps its height otherwise).
func _ground(at: Vector3, body: Node3D) -> float:
	if not body.is_inside_tree():
		return at.y
	var g: Transform3D = (body.get_parent() as Node3D).global_transform
	var from: Vector3 = g * (at + Vector3(0, 3.0, 0))
	var to: Vector3 = g * (at + Vector3(0, -6.0, 0))
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [body.get_rid()]
	if ui.player != null:
		q.exclude.append(ui.player.get_rid())
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return at.y
	return (g.affine_inverse() * (hit["position"] as Vector3)).y


## The gate barriers are raised for the bus (the guard's; drawn down, as the engine's bus passes them too): no
## collision between them and the bus. Looked for once among the areas' structures.
func _barriers(body: PhysicsBody3D) -> void:
	if _barrier_done.has(body):
		return
	_barrier_done[body] = true
	var plant = ui.main.plant if "main" in ui and ui.main != null and "plant" in ui.main else null
	if plant == null:
		return
	for area in plant.get_children():
		var st: Node = area.get_node_or_null("structures")
		if st == null:
			continue
		for b in st.get_children():
			if b is PhysicsBody3D and b.get_meta("structure", "") == "barrier":
				body.add_collision_exception_with(b)


## The bus's size (app/vehicles.gd measured it from its meshes when it was set up: the same on every machine).
func _measure(V: Dictionary) -> void:
	var z: Dictionary = V.get("size", {})
	if z.is_empty():
		return
	half_w = z["half_w"]
	front = z["front"]
	back = z["back"]
	wheelbase = z["wheelbase"]
	seat = z["seat"]


## Where the trainee's bus is drawn (app/vehicles.gd pose), or null when they don't drive it.
func pose_of(k: int):
	return xf if k == vi and vi != -1 else null


## The doors' button: open them standing still within reach of a stop or the depot ("stop" there), close them standing
## ("go").
func doors() -> void:
	if vi == -1:
		return
	var e = ui.clock.engine
	var vh: Dictionary = e.st_veh[vi]
	if vh["at"] != -1:
		_send(e, vi, "go")
	elif absf(speed) < STILL and _near != -1:
		speed = 0.0
		_send(e, vi, "stop", e._sm.places[_near]["id"])


## One drive input at a time: the same one is not sent again while the vehicle is as it was when it went (in a
## session the host takes a few steps to commit it), unless 50 steps have gone by without it taking effect.
func _send(e, k: int, action: String, place := "") -> void:
	var vh: Dictionary = e.st_veh[k]
	var key := "%s|%s|%d|%s|%d|%d" % [action, place, k, str(vh.has("wheel")), int(vh["at"]), int(vh["k"])]
	if key == _sent_key and e.step_no - _sent < 50:
		return
	_sent_key = key
	_sent = e.step_no
	ui.inputs.drive(e._sm.vehicles[k]["id"], action, place)


## The wheel's button: give it to the engine ("auto"), or take it again.
func toggle_wheel() -> void:
	var k := driver_of()
	if k == -1:
		return
	var e = ui.clock.engine
	want_wheel = not e.st_veh[k].has("wheel")      # (kept for the next runs too, until pressed again)
	if not want_wheel:
		_send(e, k, "auto")


func _unhandled_input(event: InputEvent) -> void:
	if driver_of() == -1:
		return
	if event.is_action_pressed("use"):
		doors()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fly"):
		toggle_wheel()
		get_viewport().set_input_as_handled()


## Off the wheel (the run ended, the engine has it, a load): the walker its own again.
func _end() -> void:
	vi = -1
	speed = 0.0
	braking = false
	off_route = false
	if ui.player != null:
		ui.player.driving = false


## The nearest stop or depot within DOOR_RANGE the bus's run reaches, and whether it is off its run's roads.
func _track(e, k: int, vh: Dictionary, delta: float) -> void:
	var sm = e._sm
	var V: Dictionary = ui.vehicles._drawn(k)
	_near = -1
	var best := DOOR_RANGE
	var inv := xf.affine_inverse()
	for i in sm.drive_places:
		if not sm.drive_reaches(sm.vehicles[k]["home"], i):
			continue
		# (from the bus's sides and ends: a stop beside it, the doors open onto it)
		var l: Vector3 = inv * ui.vehicles.place_xz(i)
		var d := Vector2(maxf(absf(l.x) - half_w, 0.0), maxf(maxf(front - l.z, l.z - back), 0.0)).length()
		if d < best or i == int(vh["to"]) and d < DOOR_RANGE:      # (the run's next stop first, in reach)
			best = d if i != int(vh["to"]) else -1.0
			_near = i
	# off route: the roads of the route's ways from where it came (or set off) to its next target and on to the end
	var far := INF
	var key := "%d|%d|%d|%d|%d" % [k, int(vh["run"]), int(vh["k"]), int(vh.get("from", -1)), int(vh["to"])]
	if key != _route_key:               # (the roads looked up again only when the run moves on)
		_route_key = key
		_route = ui.vehicles.route_lines(V, k)
	for line in _route:
		far = minf(far, _dist(line, xf.origin))
	off_route = far > OFF_ROUTE and far != INF
	if off_route and not log.is_empty():
		log[-1]["off_route_s"] += delta


static func _dist(line: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for i in range(1, line.size()):
		var a := Vector2(line[i - 1].x, line[i - 1].z)
		var b := Vector2(line[i].x, line[i].z)
		var ab := b - a
		var t := 0.0 if ab.length_squared() < 1e-9 else clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


## A run driven: its record in the log (once per run); its events are logged from now (_log_events) until the
## vehicle is home.
func _new_run(e, k: int, vh: Dictionary) -> void:
	var id: String = e._sm.vehicles[k]["id"]
	_log_vi = k
	_log_run = [int(vh["run"]), int(vh["dep"])]
	_ev_seen = e.events.size()
	if not log.is_empty() and log[-1]["vehicle"] == id and log[-1]["dep"] == vh["dep"]:
		return
	log.append({"vehicle": id, "dep": vh["dep"], "stops": [], "off_route_s": 0.0, "near_misses": 0})


## The driven run's arrivals, stops passed and places stood at since the last frame, the arrival home included, each
## arrival with its lateness against the timetable at the step it came (clock minutes, rounded); nothing of other runs.
func _log_events(e) -> void:
	if _ev_seen > e.events.size():
		_ev_seen = e.events.size()
	if _log_vi == -1 or log.is_empty():
		_ev_seen = e.events.size()
		return
	var id: String = e._sm.vehicles[_log_vi]["id"]
	for j in range(_ev_seen, e.events.size()):
		var x: Array = e.events[j]
		if x[1] != "vehicle" or x[2] != id or not x[4] in ["arrive", "passed", "stand"]:
			continue
		var late = null
		if x[4] == "arrive":
			var due := timetable_of(e, _log_vi, int(_log_run[0]), int(_log_run[1]), x[3])
			if due >= 0:
				late = int(round(float(e.clock() - (e.step_no - int(x[0])) * e._ds - due) / 600.0))
		log[-1]["stops"].append([x[3], x[4], late])
		if x[4] == "arrive" and x[3] == e._sm.places[e._sm.vehicles[_log_vi]["home"]]["id"] \
				and e.st_veh[_log_vi]["run"] == -1:
			_log_vi = -1                # (home: the run is over)
			break
	_ev_seen = e.events.size()


## After a load, a jump or another engine: nothing driven until the app has the wheel again, nothing logged from the
## old engine's events, the bus put where the run has it (app/vehicles.gd snap).
func reset() -> void:
	_end()
	_log_vi = -1
	_ev_seen = ui.clock.engine.events.size() if ui != null and ui.clock != null else 0
	_sent_key = ""


## When the run's engine would have the vehicle arrive at stop `id` (clock tenths), -1 when it is not on the run: D at
## the first stop, then each way's steps at the plant's day scale and each later stop's dwell (§21.16).
static func timetable(e, k: int, id: String) -> int:
	var vh: Dictionary = e.st_veh[k]
	if vh["run"] == -1:
		return -1
	return timetable_of(e, k, int(vh["run"]), int(vh["dep"]), id)


static func timetable_of(e, k: int, run: int, dep: int, id: String) -> int:
	var sm = e._sm
	var r: Dictionary = sm.vehicles[k]["runs"][run]
	var stops: PackedInt32Array = r["stops"]
	var t: int = dep
	for j in stops.size():
		if j > 0:
			t += sm.drive_steps(stops[j - 1], stops[j]) * e._ds
			if sm.places[stops[j]]["id"] == id:
				return t
			t += int(r["dwell"]) * 600
		elif sm.places[stops[j]]["id"] == id:
			return t
	return -1


func _show(e, k: int, vh: Dictionary) -> void:
	var sm = e._sm
	_bar.visible = true
	var r: Dictionary = sm.vehicles[k]["runs"][vh["run"]]
	var stops: PackedInt32Array = r["stops"]
	var next_id: String = sm.places[vh["to"]]["id"]
	var name := _name(sm, vh["to"])
	var parts := PackedStringArray()
	if vh.has("wheel"):
		parts.append("%d km/h" % int(round(absf(speed) * 3.6)))
	else:
		parts.append("The engine drives")
	if vh["k"] < stops.size():
		var due := timetable(e, k, next_id)
		var late := "" if due < 0 else (" (due %s%s)" % [_hhmm(due), "" if e.clock() <= due else
				", %d min late" % int(ceil(float(e.clock() - due) / 600.0))])
		parts.append("next: %s%s" % [name, late])
	else:
		parts.append("next: home to %s" % name)
	if off_route:
		parts.append("OFF ROUTE")
	if braking:
		parts.append("BRAKING: someone ahead")
	_label.text = " · ".join(parts)
	_doors.visible = vh.has("wheel") and (vh["at"] != -1 or (absf(speed) < STILL and _near != -1))
	_doors.text = "Close the doors" if vh["at"] != -1 else "Open the doors at %s" % (_name(sm, _near) if _near != -1 else "")
	_wheel.text = "Let the engine drive" if vh.has("wheel") else "Take the wheel"


static func _name(sm, i: int) -> String:
	if i < 0:
		return ""
	var p: Dictionary = sm.places[i]
	return String(p.get("name", p["id"]))


static func _hhmm(t: int) -> String:
	var m := posmod(t / 600, 1440)
	return "%02d:%02d" % [m / 60, m % 60]
