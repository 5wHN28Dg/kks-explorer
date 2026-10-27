## The other players of a session in the plant (docs/plant3d/MULTIPLAYER.md §6.3): each where their `pos` says,
## 200 ms behind and interpolated, with their name over their head within 15 m. Their avatar is their person's role's
## (decision 0063; a free-mode player has the first look) and takes a skinned slot before the NPCs: it is added to the
## people on screen (app/people.gd `people`) as someone the trainee works with (`near`), after the staff's people are
## set each frame (ui/people_view.gd fills that list first; this node runs after it). Without the people's build, a
## capsule each.
##
## A player's person standing at a place is also drawn there by the staff's view (it shows every person but the
## trainee's own): the two stand at the same place, so this view draws that player's body only while they are away
## from their person's place (as built in MP2; MP6 measures the crowd with 7 others).
extends Node3D

const Plant = preload("res://app/plant.gd")

const NAME_RANGE := 15.0
const SAME_PLACE := 2.5         # m: a player this close to their person's place is drawn there by the staff's view

var ui                          # ui/plant_ui.gd
var session
var avatars                     # app/people.gd, or null
var _labels := {}               # slot -> Label3D
var _capsules := {}             # slot -> MeshInstance3D
var _mine: Array = []           # the entries this node added to the avatars' people (taken out again each frame)
var shown: Array = []           # slots drawn this frame (tests)


func setup(u, s) -> void:
	ui = u
	session = s
	avatars = ui.main.people if ui.main != null and "people" in ui.main else null


func _process(_delta: float) -> void:
	shown.clear()
	if session == null or not session.active():
		_clear()
		return
	var cam: Vector3 = ui.player.camera.global_position if ui.player != null else Vector3.ZERO
	var e = ui.clock.engine
	var out: Array = avatars.people if avatars != null else []
	_take_out(out)
	var seen := {}
	for r in session.roster:
		var sl: int = r["slot"]
		if sl == session.slot or not r.get("connected", true):
			continue
		var p: Array = session.position_of(sl)
		if p.is_empty():
			continue
		seen[sl] = true
		var at: Vector3 = p[0]
		var pi: int = e.trainee(sl) if e != null else -1
		var body := true
		if pi >= 0 and e._sm != null and e.sp_pos[pi] >= 0:
			var pl: Array = e._sm.places[e.sp_pos[pi]]["at"]
			body = at.distance_to(Plant.g(pl[0], pl[1], pl[2])) > SAME_PLACE
		if body:
			shown.append(sl)
			if avatars != null:
				var look = _look(e, pi)
				if look != null:
					var d := {"at": at, "yaw": p[1], "speed": p[3] / 10.0, "anim": "", "look": look, "scale": 1.0,
							"on": "", "near": true, "hat": true}
					out.append(d)
					_mine.append(d)
			else:
				_capsule(sl).global_position = at + Vector3(0, 0.9, 0)
				_capsule(sl).visible = true
		elif _capsules.has(sl):
			_capsules[sl].visible = false
		var lab := _label(sl, r["name"])
		lab.global_position = at + Vector3(0, 2.05, 0)
		lab.visible = at.distance_to(cam) <= NAME_RANGE
	for sl in _labels.keys():
		if not seen.has(sl):
			_labels[sl].queue_free()
			_labels.erase(sl)
			if _capsules.has(sl):
				_capsules[sl].queue_free()
				_capsules.erase(sl)


func _look(e, pi: int):
	if avatars.info.is_empty():
		return null
	if pi >= 0 and e._sm != null:
		var role: String = e._sm.people[pi]["role"]
		return avatars.info.roles.get(role, avatars.info.looks.keys()[0])
	return avatars.info.looks.keys()[0]


func _label(sl: int, text: String) -> Label3D:
	if not _labels.has(sl):
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 48
		l.pixel_size = 0.004
		l.outline_size = 8
		l.no_depth_test = false
		add_child(l)
		_labels[sl] = l
	var lab: Label3D = _labels[sl]
	if lab.text != text:
		lab.text = text
	return lab


func _capsule(sl: int) -> MeshInstance3D:
	if not _capsules.has(sl):
		var m := MeshInstance3D.new()
		var c := CapsuleMesh.new()
		c.radius = 0.3
		c.height = 1.8
		m.mesh = c
		add_child(m)
		_capsules[sl] = m
	return _capsules[sl]


## The entries added last frame, out of the people's list (the staff's view sets that list anew each frame only in a
## run with staff).
func _take_out(out: Array) -> void:
	if _mine.is_empty():
		return
	for i in range(out.size() - 1, -1, -1):
		for d in _mine:
			if is_same(out[i], d):
				out.remove_at(i)
				break
	_mine.clear()


func _clear() -> void:
	if avatars != null:
		_take_out(avatars.people)
	for l in _labels.values():
		l.queue_free()
	for c in _capsules.values():
		c.queue_free()
	_labels.clear()
	_capsules.clear()
