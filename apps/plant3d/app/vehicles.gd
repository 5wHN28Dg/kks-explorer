## The staff's vehicles in the app (docs/PLANT3D.md §21.7; view only, nothing of it is in the vectors): each vehicle of
## staff.json is the parked kit `vehicle` the build drew as a piece of its own (builder/fleet.gd, builder/kit_place.gd
## vehicle_piece), moved here as an AnimatableBody3D: parked where the content stands it while at home, and along its
## drive way's road (the manifest's `vehicles`, the road's middle line) on the right of it, at the fraction of the
## way's time gone (between two steps as well, as the lifts' cabs are drawn), facing the way it goes; standing at a
## stop where it arrived. On the map (render layer 2) a square over each. The people aboard are not drawn
## (ui/people_view.gd draws nobody without a place or a way); the trainee aboard rides in the bus: the walker is taken
## off the floor and carried in the bus at a seat (its camera with it), until the engine puts them off at a stop.
extends Node3D

const Cost = preload("res://app/script_cost.gd")

const LANE := 1.8                 # m right of the road's middle line: the right-hand lane
const LANE_IN := 10.0             # m over which the lane is taken leaving the parked place (and left coming back)
const MAP_LAYER := 2
const SEAT := Vector3(0.7, 0.4, -4.0)    # the walker's feet at a front seat (the piece's frame: Godot's, facing -Z): the
								  # eye (1.65 m over them) at the windows' height
const MAP_COLOUR := Color(0.95, 0.78, 0.2)

var ui                            # ui/plant_ui.gd
var vehicles: Array = []          # per drawn vehicle: {id, vi (engine's), body, home (place index), parked (Transform3D),
								  #  roads: {"A|B": PackedVector3Array (Godot's, the road's middle)}, square, xf}
var walker_aboard := -1           # the vehicle index (engine's) the walker rides in, -1 none (tests read it)
var draws := 0                    # how many frames moved a vehicle (tests: nothing while all stand still)
var _step_seen := -1
var _step_t := 0.0
var _step_dt := 0.1
var _now := 0.0
var _walker_layers := 0
var _walker_mask := 0
var _bound = null                 # the staff model the vehicles were bound to (_bind)
var _ride_yaw := 0.0              # the bus's heading at the last frame the walker rode in it


func setup(u, manifest: Dictionary, plant: Node) -> void:
	ui = u
	for c in get_children():
		c.free()
	vehicles.clear()
	_bound = null
	for mv in manifest.get("vehicles", []):
		var host: Node3D = _find(plant, manifest, mv)
		if host == null or not host.has_node("vehicle"):
			continue
		var piece: Node3D = host.get_node("vehicle")
		var body := AnimatableBody3D.new()
		body.name = String(mv["id"])
		body.sync_to_physics = true
		add_child(body)
		# (the plant may not be in the tree yet at the app's setup: transforms put together by hand, in the plant's
		# frame, which is this node's)
		var parked := _in_plant(piece, plant)
		body.transform = parked
		# its meshes and its solids move with it
		for c in host.get_children():
			if c == piece or c is CollisionShape3D:
				var g: Transform3D = parked.affine_inverse() * _in_plant(c as Node3D, plant)
				host.remove_child(c)
				body.add_child(c)
				(c as Node3D).transform = g
		var roads := {}
		for k in mv.get("roads", {}):
			var line := PackedVector3Array()
			for p in mv["roads"][k]:
				line.append(Vector3(float(p[0]), parked.origin.y, -float(p[1])))
			roads[k] = line
		var sq := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(7.0, 0.5, 7.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = MAP_COLOUR
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		box.material = mat
		sq.mesh = box
		sq.layers = 1 << (MAP_LAYER - 1)
		sq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sq.ignore_occlusion_culling = true
		add_child(sq)
		vehicles.append({"id": String(mv["id"]), "vi": -1, "body": body, "home": -1, "parked": parked, "roads": roads,
				"square": sq, "xf": Transform3D(), "last": [], "stand_key": "", "stand_xf": parked})
	snap()


## n's transform in the plant's frame (its parents' up to the plant node put together).
static func _in_plant(n: Node3D, plant: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != plant and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## The vehicle's piece in its area's scene (searched in that scene only: the plant holds many nodes).
static func _find(plant: Node, manifest: Dictionary, mv: Dictionary) -> Node3D:
	if plant == null:
		return null
	var scene := ""
	for a in manifest.get("areas", []):
		if a.get("id", "") == mv.get("area", ""):
			scene = a.get("scene", "")
	for c in plant.get_children():
		if scene != "" and c.scene_file_path == scene:
			return c.find_child(String(mv["structure"]), true, false) as Node3D
	return null


## The engine's vehicle for each drawn one (by id), when the staff model changes (another scenario, a session's).
func _bind(sm) -> void:
	_bound = sm
	for V in vehicles:
		V["vi"] = -1
		V["home"] = -1
		V["last"] = []
		V["stand_key"] = ""
		if sm == null or not "vehicles" in sm:
			continue
		for k in sm.vehicles.size():
			if String(sm.vehicles[k]["id"]) == V["id"]:
				V["vi"] = k
				V["home"] = int(sm.vehicles[k]["home"])      # (the staff model's: a place index)


## Every vehicle where the engine has it now (after a load, a jump or a session's resync).
func snap() -> void:
	release()               # (the run puts the walker where it belongs: a ride seen again from the engine next frame)
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	_bind(e._sm if e != null else null)
	for V in vehicles:
		var xf := pose(V, 0.0)
		_put(V, xf, true)


## Where vehicle V is drawn with `f` of a step gone since the engine's last.
func pose(V: Dictionary, f: float) -> Transform3D:
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	if e == null or V["vi"] == -1 or e.st_veh.size() <= V["vi"]:
		return V["parked"]
	var vh: Dictionary = e.st_veh[V["vi"]]
	var leg: Array = vh["leg"]
	if leg.is_empty():
		var at: int = vh["at"]
		if at == V["home"] or at == -1:
			return V["parked"]
		# standing at a stop: where its last drive way ended, facing as it came (a load or a jump: the end of a road
		# into it); worked out once per stop and way
		var last: Array = V["last"]
		var key := "%d|%s" % [at, str(last)]
		if key != V["stand_key"]:
			V["stand_key"] = key
			V["stand_xf"] = _arrived(V, last) if not last.is_empty() and last[1] == at else _standing(V, at)
		return V["stand_xf"]
	var k := clampf((float(e.step_no) + f - float(leg[2])) / maxf(1.0, float(leg[3] - leg[2])), 0.0, 1.0)
	V["last"] = [int(leg[0]), int(leg[1])]
	var line := _line(V, leg[0], leg[1])
	if line.is_empty():
		return V["xf"]
	return along(line, k, leg[0] == V["home"], leg[1] == V["home"], V["parked"])


## The road from place a to place b (reversed when only b to a is there), empty for none.
func _line(V: Dictionary, a: int, b: int) -> PackedVector3Array:
	var sm = ui.clock.engine._sm
	var ia: String = sm.places[a]["id"]
	var ib: String = sm.places[b]["id"]
	if V["roads"].has(ia + "|" + ib):
		return V["roads"][ia + "|" + ib]
	if V["roads"].has(ib + "|" + ia):
		var line := (V["roads"][ib + "|" + ia] as PackedVector3Array).duplicate()
		line.reverse()
		return line
	return PackedVector3Array()


## Where a vehicle that drove `last` ([from, to]) stands at its end.
func _arrived(V: Dictionary, last: Array) -> Transform3D:
	var line := _line(V, last[0], last[1])
	if line.is_empty():
		return V["parked"]
	return along(line, 1.0, last[0] == V["home"], last[1] == V["home"], V["parked"])


## A vehicle standing at stop `at` it has not been seen to arrive at (a load, a jump): at the end of a road into it.
func _standing(V: Dictionary, at: int) -> Transform3D:
	var sm = ui.clock.engine._sm
	var id: String = sm.places[at]["id"]
	for key in V["roads"]:
		var ab: PackedStringArray = String(key).split("|")
		if ab[1] == id:
			return along(V["roads"][key], 1.0, ab[0] == sm.places[V["home"]]["id"], false, V["parked"])
		if ab[0] == id:
			var line: PackedVector3Array = (V["roads"][key] as PackedVector3Array).duplicate()
			line.reverse()
			return along(line, 1.0, ab[1] == sm.places[V["home"]]["id"], false, V["parked"])
	return V["parked"]


## The pose at fraction k of the road `line` (its length's), on the right of it (the lane taken over LANE_IN from the
## parked place where the way begins there, left over LANE_IN where it ends there), facing along it.
static func along(line: PackedVector3Array, k: float, from_home: bool, to_home: bool, parked: Transform3D) -> Transform3D:
	if line.size() < 2:
		return parked
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	if total < 1e-3:
		return Transform3D(parked.basis, line[0])      # (both ends join the road at one point: standing there)
	var want := k * total
	var p := line[line.size() - 1]
	var d := line[line.size() - 1] - line[line.size() - 2]
	var run := 0.0
	for i in range(1, line.size()):
		var L := line[i].distance_to(line[i - 1])
		if run + L >= want and L > 1e-6:
			p = line[i - 1].lerp(line[i], (want - run) / L)
			d = line[i] - line[i - 1]
			break
		run += L
	d.y = 0.0
	if d.length() < 1e-6:
		return parked
	d = d.normalized()
	var lane := LANE
	if from_home:
		lane *= clampf(want / LANE_IN, 0.0, 1.0)
	if to_home:
		lane *= clampf((total - want) / LANE_IN, 0.0, 1.0)
	var right := Vector3(-d.z, 0.0, d.x)
	var basis := Basis.looking_at(d, Vector3.UP)         # (facing -Z along d: the piece's front is +y in plan, -Z)
	if (from_home and want < 0.01) or (to_home and total - want < 0.01):
		return parked
	return Transform3D(basis, p + right * lane)


## The fraction of a step drawn now (as app/lift.gd's).
func _frac(e) -> float:
	var c = ui.clock
	if not c.driven:
		return clampf(c.acc / c.STEP, 0.0, 1.0)
	if e.step_no != _step_seen:
		if _step_seen != -1:
			_step_dt = clampf(_now - _step_t, 0.02, 0.5)
		_step_seen = e.step_no
		_step_t = _now
	return clampf((_now - _step_t) / _step_dt, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var _c0 := Time.get_ticks_usec()
	_now += delta
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	if e == null or vehicles.is_empty():
		return
	if e._sm != _bound:
		_bind(e._sm)
	var f := _frac(e)
	for V in vehicles:
		_put(V, pose(V, f), false)
	_ride(e)
	Cost.add(Cost.BINDINGS, _c0)


func _put(V: Dictionary, xf: Transform3D, force: bool) -> void:
	var body: AnimatableBody3D = V["body"]
	var sq: MeshInstance3D = V["square"]
	if not force and xf.is_equal_approx(V["xf"]):
		return
	V["xf"] = xf
	draws += 1
	if force:
		body.sync_to_physics = false
		body.transform = xf
		if body.is_inside_tree():
			body.force_update_transform()
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
		body.sync_to_physics = true
	else:
		body.transform = xf
	sq.position = xf.origin + Vector3(0, 5.0, 0)


## The trainee aboard: the walker carried at the seat, off the floor, turning with the bus (and looked round with the
## look stick, which the walker's own physics frame reads when walking), the bus's own body not drawn for its rider
## (from the seat its windows are paint-dark, its walls seen from inside), until the engine puts them off; then put
## down at the stop. Only for a vehicle drawn here.
func _ride(e) -> void:
	var me: int = ui.my_person() if e._sm != null else -1
	var vi: int = e.sp_aboard[me] if me != -1 and e.sp_aboard.size() > me else -1
	var V: Dictionary = {}
	for x in vehicles:
		if vi != -1 and x["vi"] == vi:
			V = x
	if V.is_empty():
		vi = -1                 # (a vehicle not drawn: the walker is left as it is)
	var p = ui.player
	if p == null:
		return
	if vi != walker_aboard:
		if walker_aboard != -1:
			# off: the walker put down at the stop first (not inside the bus's solids), then walking again; with
			# nobody played any more, beside the bus
			var at: int = e.sp_pos[me] if me != -1 else -1
			if at != -1:
				ui.go_to_place(at)
			else:
				var W := _drawn(walker_aboard)
				if not W.is_empty():
					p.global_position = global_transform * ((W["xf"] as Transform3D) * Vector3(2.5, 0.05, 0.0))
			release(false)
		if vi != -1:
			_walker_layers = p.collision_layer
			_walker_mask = p.collision_mask
			p.collision_layer = 0
			p.collision_mask = 0
			p.velocity = Vector3.ZERO
			p.set_physics_process(false)
			(V["body"] as Node3D).visible = false
			_ride_yaw = (V["xf"] as Transform3D).basis.get_euler().y
		walker_aboard = vi
	if vi == -1:
		return
	var xf: Transform3D = V["xf"]
	var yaw := xf.basis.get_euler().y
	p.rotation.y += wrapf(yaw - _ride_yaw, -PI, PI)       # (turning with the bus)
	_ride_yaw = yaw
	if p.input_enabled:
		var lv := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if lv.length() > 0.0:
			p.look(lv.x * p.LOOK_RATE * get_physics_process_delta_time(), lv.y * p.LOOK_RATE * get_physics_process_delta_time())
	p.global_position = global_transform * (xf * SEAT)


## The walker let go from a ride without moving it (`moved`: already put down): its collisions and physics back, the
## bus drawn again. Also after a load, a jump or a session's engine (snap), where the run puts the walker itself.
func release(moved := true) -> void:
	var p = ui.player if ui != null else null
	if walker_aboard != -1 and p != null:
		p.collision_layer = _walker_layers
		p.collision_mask = _walker_mask
		p.set_physics_process(true)
	for x in vehicles:
		(x["body"] as Node3D).visible = true
	walker_aboard = -1


func _drawn(vi: int) -> Dictionary:
	for x in vehicles:
		if x["vi"] == vi:
			return x
	return {}


## Where vehicle `vi` (the engine's index) is drawn now (tests), Vector3.INF if it is not.
func drawn_at(vi: int) -> Vector3:
	for V in vehicles:
		if V["vi"] == vi:
			return global_transform * (V["xf"] as Transform3D).origin
	return Vector3.INF
