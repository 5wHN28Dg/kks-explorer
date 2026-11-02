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

const MAX_FWD := 40.0 / 3.6         # m/s
const MAX_REV := 8.0 / 3.6
const ACCEL := 1.5                  # m/s²
const BRAKE := 4.0
const AUTO_BRAKE := 6.0
const ROLL := 0.3                   # coasting
const MAX_STEER := deg_to_rad(35.0)
const STEER_RATE := deg_to_rad(60.0)    # how fast the wheels turn, per second
const DOOR_RANGE := 12.0            # m from a stop or depot place: the doors may be opened there (a bus's length)
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
var braking := false                # the automatic brake holds (someone ahead)
var extra_people: Array = []        # tests: more people (global positions) for the automatic brake
var blocked := 0                    # physics frames a solid stopped it (the drive walk's DRIVE line, tests)
var blocked_by := ""                # what it ran into last
var _reversing := false             # the pilot backing up (a three-point turn)
var _rev_from := Vector3.ZERO
var _blocked_seen := 0
var off_route := false
var log: Array = []                 # per run driven: {"vehicle", "dep", "stops": [[stop, "arrive"|"passed"|"stand",
									#  late clock minutes or null]], "off_route_s", "near_misses"}
var half_w := 1.3                   # the bus's half width and its front and back (body frame, -Z forward)
var front := -6.0
var back := 6.0
var wheelbase := 6.0
var seat := Vector3(-0.7, 0.4, -4.6)    # the driver's seat (the walker's feet)
var _sent := -1                     # the step an input was last sent at (one at a time, until the engine has it)
var _ev_seen := 0
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
	var e = ui.clock.engine
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
	_log_events(e, k)
	if not vh.has("wheel"):
		if vi != -1:
			_end()
		if want_wheel and _sent != e.step_no:
			_sent = e.step_no
			ui.inputs.drive(ui.clock.engine._sm.vehicles[k]["id"], "wheel")
		_show(e, k, vh)
		return
	if vi != k:                         # the wheel is theirs from now: the bus where it is drawn
		vi = k
		xf = V["xf"]
		speed = 0.0
		steer = 0.0
		_measure(V)
		_new_run(e, k, vh)
		if p != null:
			p.driving = true
	if vh["at"] != -1:                  # standing at a place (the doors open): it does not move
		speed = 0.0
		if pilot and _sent != e.step_no and (e.clock() >= vh["dep"] if vh["k"] == 0 else e.step_no >= vh["until"]):
			doors()                     # (the drive walk: off again by the run's own rule)
	else:
		_drive(V, delta)
	_track(e, k, vh, delta)
	_show(e, k, vh)


## One physics frame of driving: the controls, the automatic brake, the bicycle model, the solids, the ground.
func _drive(V: Dictionary, delta: float) -> void:
	var c: Vector3 = control if control != null else (_pilot(V) if pilot else _controls())
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
	var hazard := _people_ahead()
	if hazard:
		if not braking and absf(speed) > NEAR_MISS and not log.is_empty():
			log[-1]["near_misses"] += 1
		braking = true
		a = -signf(speed) * minf(AUTO_BRAKE, absf(speed) / maxf(delta, 1e-3))
	else:
		braking = false
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
	if body.is_inside_tree() and body.test_move(body.global_transform, (body.get_parent() as Node3D).global_transform.basis * move, hit):
		speed = 0.0                     # a solid or another vehicle: stopped dead, no bounce
		blocked += 1
		var who = hit.get_collider()
		blocked_by = String(who.get_path()) if who is Node else str(who)
		return
	nx.origin.y = _ground(nx.origin, body)
	xf = nx


## The drive walk's driver: pure pursuit of a point 10 m ahead on the lane of the roads to the run's next target, at
## up to 8 m/s, slowing to stop at the road's end there, then the doors.
func _pilot(V: Dictionary) -> Vector3:
	var e = ui.clock.engine
	var vh: Dictionary = e.st_veh[vi]
	var path: PackedVector3Array = ui.vehicles.lane_path(V, int(vh.get("from", vh["to"])), int(vh["to"]))
	if path.size() < 2:
		return Vector3(0, 1, 0)
	var end := path[path.size() - 1]
	var left := Vector2(end.x - xf.origin.x, end.z - xf.origin.z).length()
	var le: Vector3 = xf.affine_inverse() * end
	if left < 3.0 or left < 10.0 and le.z > -1.0:      # there, or just past it: stops and opens the doors
		if absf(speed) < STILL:
			doors()
		return Vector3(0, 1, 0)
	# the nearest point of the path, then 10 m on along it
	var best := INF
	var bi := 0
	for i in path.size():
		var d := Vector2(path[i].x - xf.origin.x, path[i].z - xf.origin.z).length()
		if d < best:
			best = d
			bi = i
	var ahead := path[path.size() - 1]
	var run := 0.0
	for i in range(bi + 1, path.size()):
		run += path[i].distance_to(path[i - 1])
		if run >= 10.0:
			ahead = path[i]
			break
	var l: Vector3 = xf.affine_inverse() * ahead
	var alpha := atan2(-l.x, -l.z)
	# the way on is behind it (a turn at a stop where the run goes back the way it came) or a solid blocks it: backs up
	# turning the other way until the way on is ahead (a three-point turn), then forward again
	var stuck := blocked > _blocked_seen
	_blocked_seen = blocked
	if not _reversing and (absf(alpha) > 1.75 or stuck and speed >= 0.0):
		_reversing = true
		_rev_from = xf.origin
	elif _reversing and (absf(alpha) < 0.9 or stuck and speed <= 0.0 or xf.origin.distance_to(_rev_from) > 12.0):
		_reversing = false
	if _reversing:
		if speed > STILL:
			return Vector3(0, 1, -signf(alpha))
		return Vector3(0, 1 if speed > -2.0 else 0.0, -signf(alpha))
	var ld := maxf(Vector2(l.x, l.z).length(), 1.0)
	var ang := atan(wheelbase * 2.0 * sin(alpha) / ld)
	var want := minf(8.0, sqrt(maxf(0.0, 2.0 * 1.5 * (left - 2.0))))
	if absf(alpha) > 0.6:
		want = minf(want, 3.0)
	var th := 1.0 if speed < want - 0.3 else 0.0
	var br := 1.0 if speed > want + 0.8 else 0.0
	return Vector3(th, br, clampf(ang / MAX_STEER, -1.0, 1.0))


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
func _people_ahead() -> bool:
	if absf(speed) < 1e-3:
		return false
	var reach := speed * speed / (2.0 * AUTO_BRAKE) + CLEAR
	var gx: Transform3D = ui.vehicles.global_transform * xf
	var inv := gx.affine_inverse()
	for at in _people():
		var l: Vector3 = inv * at
		if absf(l.x) > half_w + 0.5 or absf(l.y) > 3.0:
			continue
		if speed > 0.0 and l.z <= front and l.z >= front - reach:
			return true
		if speed < 0.0 and l.z >= back and l.z <= back + reach:
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


## The bus's size from its meshes (body frame).
func _measure(V: Dictionary) -> void:
	var box := AABB()
	var first := true
	for c in (V["body"] as Node).get_children():
		for m in [c] + c.find_children("*", "MeshInstance3D", true, false):
			if m is MeshInstance3D and (m as MeshInstance3D).mesh != null:
				var b: AABB = (V["body"] as Node3D).global_transform.affine_inverse() * (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb() \
						if (m as Node3D).is_inside_tree() else (m as Node3D).transform * (m as MeshInstance3D).get_aabb()
				box = b if first else box.merge(b)
				first = false
	if first or box.size.z < 2.0:
		return
	half_w = box.size.x / 2.0
	front = box.position.z
	back = box.end.z
	wheelbase = box.size.z * 0.55
	seat = Vector3(box.position.x + box.size.x * 0.25, box.position.y + 0.4, front + 1.3)


## Where the trainee's bus is drawn (app/vehicles.gd pose), or null when they don't drive it.
func pose_of(k: int):
	return xf if k == vi and vi != -1 else null


## The doors' button: open them standing still within reach of a stop or the depot ("stop" there), close them standing
## ("go").
func doors() -> void:
	if vi == -1 or _sent == ui.clock.engine.step_no:
		return
	var e = ui.clock.engine
	var vh: Dictionary = e.st_veh[vi]
	var id: String = e._sm.vehicles[vi]["id"]
	if vh["at"] != -1:
		_sent = e.step_no
		ui.inputs.drive(id, "go")
	elif absf(speed) < STILL and _near != -1:
		_sent = e.step_no
		speed = 0.0
		ui.inputs.drive(id, "stop", e._sm.places[_near]["id"])


## The wheel's button: give it to the engine ("auto"), or take it again.
func toggle_wheel() -> void:
	var k := driver_of()
	if k == -1:
		return
	var e = ui.clock.engine
	want_wheel = not e.st_veh[k].has("wheel")
	if not want_wheel and _sent != e.step_no:
		_sent = e.step_no
		ui.inputs.drive(e._sm.vehicles[k]["id"], "auto")


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
	for i in sm.drive_places:
		if not sm.drive_reaches(sm.vehicles[k]["home"], i):
			continue
		var at: Vector3 = ui.vehicles.place_xz(i)
		var d := Vector2(at.x - xf.origin.x, at.z - xf.origin.z).length()
		if d < best:
			best = d
			_near = i
	# off route: the roads of the route's ways from where it came (or set off) to its next target and on to the end
	var far := INF
	for line in ui.vehicles.route_lines(V, k):
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


## A run driven: its record in the log (once per run).
func _new_run(e, k: int, vh: Dictionary) -> void:
	var id: String = e._sm.vehicles[k]["id"]
	if not log.is_empty() and log[-1]["vehicle"] == id and log[-1]["dep"] == vh["dep"]:
		return
	log.append({"vehicle": id, "dep": vh["dep"], "stops": [], "off_route_s": 0.0, "near_misses": 0})
	_ev_seen = e.events.size()


## The run's arrivals, stops passed and places stood at since the last frame, each arrival with its lateness against
## the timetable (clock minutes, rounded).
func _log_events(e, k: int) -> void:
	if log.is_empty() or _ev_seen > e.events.size():
		_ev_seen = e.events.size()
		return
	var id: String = e._sm.vehicles[k]["id"]
	for j in range(_ev_seen, e.events.size()):
		var x: Array = e.events[j]
		if x[1] != "vehicle" or x[2] != id or not x[4] in ["arrive", "passed", "stand"]:
			continue
		var late = null
		if x[4] == "arrive":
			var due := timetable(e, k, x[3])
			if due >= 0:
				late = int(round(float(e.clock() - due) / 600.0))
		log[-1]["stops"].append([x[3], x[4], late])
	_ev_seen = e.events.size()


## When the run's engine would have the vehicle arrive at stop `id` (clock tenths), -1 when it is not on the run: D at
## the first stop, then each way's steps at the plant's day scale and each later stop's dwell (§21.16).
static func timetable(e, k: int, id: String) -> int:
	var sm = e._sm
	var vh: Dictionary = e.st_veh[k]
	if vh["run"] == -1:
		return -1
	var r: Dictionary = sm.vehicles[k]["runs"][vh["run"]]
	var stops: PackedInt32Array = r["stops"]
	var t: int = vh["dep"]
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
