## The service lifts in the app (docs/PLANT3D.md §20.7; view only, nothing of it is in the vectors): each lift's cab
## at its model height `z`, drawn between the model's last two steps so that it moves smoothly at any frame rate, as an
## AnimatableBody3D the walker stands on and rides with; its landing gates solid only while shut (a gate never pushes
## the walker), the cab's own front solid unless it stands at a landing whose gate is open; the codes riding on the cab
## (its drive, panel and load cell) carried with it; and the trainee's `board` and `alight` (§20.3), sent with the zone
## inputs' rhythm (four times a second) from the walker's feet inside or outside the cab's floor, through the one input
## path (ui/inputs.gd), so a session's players each ride as themselves.
##
## The parts are kit/parts_lifts.gd's: the lift's node (its code) holds the `cab` piece (and `cab/gate`), each landing
## gate's node its `leaf`. Part frame to Godot: (x, y, z) -> (x, z, -y).
extends Node

const Cost = preload("res://app/script_cost.gd")

const CAB_X := 0.5                # the cab's inside half depth (front to back) and half width (kit/parts_lifts.gd)
const CAB_Y := 0.6
const CAB_H := 2.3
const LEAF_H := 2.05
const LEAF_RISE := 2.1
const GATE_HALF := 0.6
const TICK := 0.25                # the board/alight check, as the zone inputs (ui/plant_ui.gd _place_tick)
const RETRY := 1.0                # s before the same board or alight is sent again (its step not seen yet)
const FLOOR_TOP := 0.02           # the cab floor's top over its landing (kit/parts_lifts.gd)

var ui                            # ui/plant_ui.gd
var lifts: Array = []             # per drawn lift: {x (model's), k (engine's lift index), host, body, front, piece,
								  #  cab_gate, gates: [{node, leaf_body, shape, solid}], units: [[node, offset, code]],
								  #  z_draw, slot_z (value slot), slots of each landing's gate position and at}
var _tick := 0.0
var _sent_t := -100.0             # when the last board or alight was sent (s, this node's clock)
var _now := 0.0
var _step_seen := -1              # the engine's step at the last frame, and when it changed (a session's steps)
var _step_t := 0.0
var _step_dt := 0.1
var _last_who = null              # who rode for this player at the last check (a person taken while aboard)
var walker_aboard := -1           # the lift index the walker is aboard (the engine's riders), -1 none (tests read it)


func setup(u) -> void:
	ui = u
	lifts.clear()
	var e = ui.clock.engine
	if e == null:
		return
	for k in ui.info.m.lifts.size():
		var x: Dictionary = ui.info.m.lifts[k]
		var host: Node3D = ui.index.nodes.get(String(x["kks"]))
		if host == null or not host.has_node("cab"):
			continue
		var piece: Node3D = host.get_node("cab")
		var body := AnimatableBody3D.new()
		body.name = "cab_body"
		body.sync_to_physics = true
		body.set_meta("kks", String(x["kks"]))
		host.add_child(body)
		body.transform = piece.transform
		# the cab's meshes name their far-view parents by relative paths (the build's visibility ranges): kept
		var vis := []
		for n in piece.find_children("*", "Node3D", true, false) + [piece]:
			var n3 := n as Node3D
			if not n3.visibility_parent.is_empty():
				vis.append([n3, n3.get_node_or_null(n3.visibility_parent)])
				n3.visibility_parent = NodePath()     # (set again below: a stale path errors as the piece moves)
		host.remove_child(piece)
		body.add_child(piece)
		piece.transform = Transform3D()
		for v in vis:
			if v[1] != null:
				(v[0] as Node3D).visibility_parent = (v[0] as Node3D).get_path_to(v[1])
		# the floor, the walls and the roof (the part's frame turned to Godot's), the front a shape of its own
		_box(body, Vector3(0.02, FLOOR_TOP - 0.07, 0.0), Vector3(2 * CAB_X + 0.04, 0.14, 2 * CAB_Y + 0.08))
		_box(body, Vector3(0.0, CAB_H * 0.5, -(CAB_Y + 0.02)), Vector3(2 * CAB_X, CAB_H, 0.04))
		_box(body, Vector3(0.0, CAB_H * 0.5, CAB_Y + 0.02), Vector3(2 * CAB_X, CAB_H, 0.04))
		_box(body, Vector3(CAB_X + 0.02, CAB_H * 0.5, 0.0), Vector3(0.04, CAB_H, 2 * CAB_Y))
		_box(body, Vector3(0.0, CAB_H + 0.04, 0.0), Vector3(2 * CAB_X + 0.04, 0.08, 2 * CAB_Y + 0.08))
		var front := _box(body, Vector3(-CAB_X - 0.02, CAB_H * 0.5, 0.0), Vector3(0.04, CAB_H, 2 * CAB_Y))
		var L := {"x": x, "k": k, "host": host, "body": body, "front": front, "piece": piece,
				"cab_gate": piece.get_node_or_null("gate"), "gates": [], "units": [], "z_draw": NAN,
				"slot_z": e.ix[x["z"]], "z0": float(x["landings"][0]["z"]), "pos": [], "at": [], "front_solid": true,
				"base": body.transform}
		for i in x["landings"].size():
			var ld: Dictionary = x["landings"][i]
			var gn: Node3D = ui.index.nodes.get(String(ld["gate"]))
			var g := {"node": gn, "shape": null, "solid": true}
			if gn != null:
				var sb := StaticBody3D.new()
				sb.name = "leaf_body"
				gn.add_child(sb)
				g["shape"] = _box(sb, Vector3(0.0, LEAF_H * 0.5 + 0.03, 0.0), Vector3(0.06, LEAF_H, 2 * GATE_HALF - 0.04))
			L["gates"].append(g)
			L["pos"].append(e.ix[String(x["id"]) + "_gate%d_pos" % i])
			L["at"].append(e.ix[ld["at"]])
		for c in ui.info.parts_of.get(String(x["kks"]), []):
			var un: Node3D = ui.index.nodes.get(c)
			if un == null:
				continue
			# the panel is pressed where it is drawn: a small body to pick it by
			if ui.info.lift_role.get(c, [null, ""])[1] == "panel":
				_box(un, Vector3.ZERO, Vector3(0.24, 0.34, 0.08))
			L["units"].append([un, body.global_transform.affine_inverse() * un.global_transform, c])
		lifts.append(L)
	_move(true)


func _box(parent: Node, at: Vector3, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = at
	parent.add_child(cs)
	return cs


## The fraction of a step drawn now, 0 to 1: the clock's own when it runs the steps, else (a session's commits drive
## it) the time since the last step over the time between the last two.
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
	_move(false)
	_tick += delta
	if _tick >= TICK:
		_tick = 0.0
		_ride_tick()
	Cost.add(Cost.BINDINGS, _c0)


## Each cab at its height, the gates' and the cab's fronts solid or not, the riding codes with the cab.
func _move(force: bool) -> void:
	var e = ui.clock.engine if ui != null else null
	if e == null or lifts.is_empty():
		return
	var f := _frac(e)
	var cur: PackedFloat64Array = e.cur
	var prev: PackedFloat64Array = e.prev
	for L in lifts:
		var s: int = L["slot_z"]
		var z: float = cur[s] if prev.size() <= s else lerpf(prev[s], cur[s], f)
		var at := _at_landing(L, cur)
		var open_here := 0.0
		if at != -1:
			open_here = cur[L["pos"][at]]
		# the cab's front: open only where it stands at a landing whose gate is not shut
		var front_solid := not (at != -1 and open_here > 0.0)
		if front_solid != L["front_solid"]:
			L["front_solid"] = front_solid
			(L["front"] as CollisionShape3D).disabled = not front_solid
			if front_solid:
				_clear_gateway(L, L["body"] as Node3D, Vector3(-CAB_X - 0.02, 0, 0), L["k"] == walker_aboard)
		if L["cab_gate"] != null:
			var cg: Node3D = L["cab_gate"]
			var rise := open_here * LEAF_RISE
			if cg.position.y != rise:
				cg.position.y = rise
		for i in L["gates"].size():
			var g: Dictionary = L["gates"][i]
			if g["shape"] == null:
				continue
			var solid: bool = cur[L["pos"][i]] <= 0.0
			if solid != g["solid"]:
				g["solid"] = solid
				(g["shape"] as CollisionShape3D).disabled = not solid
				if solid:
					_clear_gateway(L, g["node"] as Node3D, Vector3.ZERO, L["k"] == walker_aboard)
		if z == L["z_draw"] and not force:
			continue
		L["z_draw"] = z
		var body: AnimatableBody3D = L["body"]
		var xf: Transform3D = L["base"]
		xf.origin.y += z - float(L["z0"])
		body.transform = xf
		for u in L["units"]:
			(u[0] as Node3D).global_transform = body.global_transform * (u[1] as Transform3D)
			ui.index.forget(String(u[2]))


## The landing the cab stands at (its `at`), -1 between landings.
func _at_landing(L: Dictionary, cur: PackedFloat64Array) -> int:
	for i in L["at"].size():
		if cur[L["at"][i]] >= 0.5:
			return i
	return -1


## A gate (or the cab's front) has just become solid: a walker standing in its gateway is put on the side their riding
## says (aboard: into the cab; else out on the landing), PLANT3D §20.7. `plane` is the gate's plane in `frame`.
func _clear_gateway(_L: Dictionary, frame: Node3D, plane: Vector3, aboard: bool) -> void:
	var p: Node3D = ui.player
	if p == null:
		return
	var l := frame.global_transform.affine_inverse() * p.global_position
	var d := l.x - plane.x
	if absf(d) < 0.32 and absf(l.z) < GATE_HALF + 0.1 and l.y > -0.5 and l.y < LEAF_H:
		# the cab lies on the gate's +x side (kit/parts_lifts.gd: the cab's front faces -x)
		l.x = plane.x + (0.35 if aboard else -0.35)
		p.global_position = frame.global_transform * l


## The walker's feet in the cab's floor, as the cab's frame has them: inside it or not.
func feet_inside(L: Dictionary, feet: Vector3) -> bool:
	var l := (L["body"] as Node3D).global_transform.affine_inverse() * feet
	return l.x > -CAB_X and l.x < CAB_X and absf(l.z) < CAB_Y and l.y > -0.3 and l.y < 1.0


## Who rides for this player: their person (§17.4), or their slot in free mode (§20.3).
func _me():
	var who = ui.me()
	return who if who != null else ui.inputs.slot


func _aboard(e, k: int, who) -> bool:
	for r in e.riders[k]:
		if typeof(r) == typeof(who) and r == who:
			return true
	return false


## The board or alight the walker's feet ask for (§20.3, §20.7): sent when the engine's riders differ from where the
## walker stands, once a second at most; a board only while the cab stands at a landing (between landings it is
## refused, its gates shut).
func _ride_tick() -> void:
	var e = ui.clock.engine
	var p: Node3D = ui.player
	if e == null or p == null or lifts.is_empty() or e.riders.size() < ui.info.m.lifts.size():
		return
	var who = _me()
	var feet := p.global_position
	var taken: bool = typeof(who) != typeof(_last_who) or who != _last_who
	_last_who = who
	walker_aboard = -1
	for L in lifts:
		var k: int = L["k"]
		var aboard := _aboard(e, k, who)
		if aboard:
			walker_aboard = k
		var inside := feet_inside(L, feet)
		if aboard and not inside and taken:
			# a person taken while aboard stays aboard (§20.3): the walker steps in where they stood
			p.global_position = (L["body"] as Node3D).global_transform * Vector3(0, 0.05, 0)
			continue
		if inside == aboard or _now - _sent_t < RETRY:
			continue
		var lid := String(L["x"]["id"])
		if inside and _at_landing(L, e.cur) != -1:
			ui.inputs.board(lid, ui.me())
			_sent_t = _now
		elif not inside:
			ui.inputs.alight(lid, ui.me())
			_sent_t = _now


## The lift the code's node rides on or belongs to, and the height its cab is drawn at (tests).
func cab_height(k: int) -> float:
	for L in lifts:
		if L["k"] == k:
			return float(L["z_draw"])
	return NAN


## Where the n-th rider of lift k stands in its cab (PLANT3D §20.7: six spots, two rows of three, in boarding order,
## the first nearest the gate), on the cab's floor as drawn now; and the way they face (the gate's, Godot's yaw).
## INF when the lift is not drawn.
const SPOTS := [Vector2(-0.22, -0.35), Vector2(-0.22, 0.35), Vector2(-0.22, 0.0), Vector2(0.22, -0.35),
		Vector2(0.22, 0.35), Vector2(0.22, 0.0)]
func rider_spot(k: int, n: int) -> Vector3:
	for L in lifts:
		if L["k"] == k:
			var s: Vector2 = SPOTS[clampi(n, 0, SPOTS.size() - 1)]
			return (L["body"] as Node3D).global_transform * Vector3(s.x, 0.0, s.y)
	return Vector3.INF


func gate_yaw(k: int) -> float:
	for L in lifts:
		if L["k"] == k:
			var f: Vector3 = (L["body"] as Node3D).global_transform.basis * Vector3(-1, 0, 0)
			return atan2(-f.x, -f.z)
	return NAN
