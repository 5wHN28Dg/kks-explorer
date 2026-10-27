## The crews on screen: each person at their logical place (§17.3: the engine's position is the truth), moved along a
## way by the fraction of its time gone (the clock's part-step too, so they walk smoothly), on the way's line as the
## content build found it on the navigation mesh (app/staff_ways.gd: round machines, through doors, up the steps;
## the straight line between its places when the build has none); a dot per person on the
## overview map (its render layer), updated 4 times a second. The people themselves are app/people.gd's avatars
## (milestone A1), driven from here every frame: where they are, which way they face, how fast they walk, what their
## task's step has them do (STEP_ANIM), their look by role, the hat carried outside the process areas. A build without
## them (no built/people/) shows a capsule per person instead. The trainee's own person is not drawn (the walker).
extends Node3D

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const Plant = preload("res://app/plant.gd")
const StaffWays = preload("res://app/staff_ways.gd")
const KeepApart = preload("res://app/keep_apart.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const MAP_LAYER := 2
const COLOURS := {"shift_sup": Color(0.95, 0.95, 0.95), "ccr_op": Color(0.25, 0.55, 1.0),
		"field_op": Color(1.0, 0.8, 0.1), "elec_ap": Color(1.0, 0.45, 0.1), "mech_tech": Color(0.3, 0.75, 0.35),
		"elec_tech": Color(0.85, 0.35, 0.8), "ic_tech": Color(0.3, 0.85, 0.85), "maint_sup": Color(0.6, 0.9, 0.5),
		"hse_officer": Color(0.2, 0.6, 0.3), "contractor_sup": Color(0.35, 0.45, 0.85),
		"contractor": Color(0.2, 0.35, 0.75)}

var ui
var capsules: MultiMeshInstance3D
var dots: MultiMeshInstance3D
var _t := 0.0
var _at: Array = []             # per place: its position (Godot frame)
var ways = null                 # app/staff_ways.gd: the ways' lines (null: none built, walked straight)
var _ways_of = null             # the staff model `ways` is for
var shown := 0                  # people drawn at the last update (tests)
var avatars                     # app/people.gd, when the build has the people
var _yaw := {}                  # person -> the way they last faced
var _hat := {}                  # person -> wearing the hat (checked twice a second)
var _hat_t := 1.0
var _drove := false             # this view filled the avatars' people (and may clear them)
var _look0 = null               # the look of a role without its own (the avatars' first)
var _step_e = null              # drive(): the engine and step _anims is of (what a person does changes with a step)
var _step_n := -1
var _anim_of := PackedStringArray()     # person -> what they are seen doing when not walking, at that step
## A task step's kind to what the person is seen doing (docs/PLANT3D.md §18.3); a `work` step says its own `anim`.
const STEP_ANIM := {"read": "inspect", "meet": "talk", "say": "radio", "call": "radio", "wait": "idle", "ack": "type",
	"permit": "write", "lock": "wrench", "unlock": "wrench"}
const SEATED := ["desk", "seat", "table"]
const TURN := 5.0               # radians a second of plant time a person turns at most
const TURN_EASE := 10.0         # and, nearing the heading, a tenth of what is left in a tenth of a second
var apart := KeepApart.new()    # where people are drawn: lanes, keeping apart (app/keep_apart.gd)
var _who := PackedInt32Array()  # per one given to `apart`: the person
var _on := PackedStringArray()
var _place := PackedInt32Array()
var _line := PackedByteArray()  # 1: on a built line (else walked straight, or standing)
var _d := PackedVector3Array()  # the straight way's heading, where walked straight
var _walkers: Array = []
var _walkers_t := 0.0
var _seated := PackedByteArray()  # per place: someone there sits or lies (not moved aside)
var NO_ROOM := PackedByteArray()   # (a place without room: none)
var drawn := PackedInt32Array()     # per avatar person drive() gave: the person (the tests; as long as their people)
var drawn_kind := PackedByteArray() # and how app/keep_apart.gd took them (WALKING, STANDING, FIXED)
var drawn_fresh := PackedByteArray()  # and whether they were new or jumped this frame (their heading set, not turned)
const ON_NAMES := ["", "stairs", "ladder"]   # app/staff_ways.gd's ON_… to app/people.gd's `on`


func setup(u) -> void:
	ui = u
	if ui != null and ui.main != null and "people" in ui.main and ui.main.people != null:
		avatars = ui.main.people
	capsules = _mm(_capsule(), 1)
	dots = _mm(_dot(), 1 << (MAP_LAYER - 1))
	# the ways' lines read now, in the start, not in a drawn frame (the file is read once per staff model)
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	if e != null and e._sm != null:
		_places(e._sm)


func _capsule() -> Mesh:
	var c := CapsuleMesh.new()
	c.radius = 0.25
	c.height = 1.75
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	c.material = mat
	return c


func _dot() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 2.0
	c.bottom_radius = 2.0
	c.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	c.material = mat
	return c


func _mm(mesh: Mesh, layers: int) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mi.multimesh = mm
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	var _c0 := Time.get_ticks_usec()
	_each_frame(delta)
	Cost.add(Cost.PEOPLE_VIEW, _c0)


func _each_frame(delta: float) -> void:
	if avatars != null:
		drive(delta)
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	update()


## Places every person now (also called by the tests).
func update() -> void:
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	var sm = e._sm if e != null else null
	if sm == null:
		capsules.multimesh.instance_count = 0
		dots.multimesh.instance_count = 0
		shown = 0
		return
	_places(sm)
	var xs := []
	var cs := []
	var me: int = ui.my_person()          # (the trainee's own person is the walker)
	for pi in sm.people.size():
		if pi == me:
			continue
		var p := Vector3.INF
		var leg: Array = e.sp_leg[pi]
		if not leg.is_empty():
			var k := clampf(float(e.step_no - leg[2]) / maxf(1.0, float(leg[3] - leg[2])), 0.0, 1.0)
			if ways != null and ways.walk(mini(leg[0], leg[1]) * _at.size() + maxi(leg[0], leg[1]), leg[0], k, 1.0):
				p = ways.pos
			else:
				p = (_at[leg[0]] as Vector3).lerp(_at[leg[1]], k)
		elif e.sp_pos[pi] != -1:
			p = _at[e.sp_pos[pi]]
		if p == Vector3.INF:
			continue
		xs.append(p)
		cs.append(COLOURS.get(sm.people[pi]["role"], Color.GRAY))
	shown = xs.size()
	if avatars != null:
		capsules.multimesh.instance_count = 0   # the avatars show them
	for mi in [capsules, dots]:
		if mi == capsules and avatars != null:
			continue
		var mm: MultiMesh = mi.multimesh
		mm.instance_count = xs.size()
		for i in xs.size():
			var lift := Vector3(0, 0.9, 0) if mi == capsules else Vector3(0, 4.0, 0)
			mm.set_instance_transform(i, Transform3D(Basis(), xs[i] + lift))
			mm.set_instance_color(i, cs[i])


## The avatars' people (app/people.gd `people`) from the engine, every frame.
func drive(delta: float) -> void:
	var e = ui.clock.engine if ui != null and ui.clock != null else null
	var sm = e._sm if e != null else null
	var out: Array = avatars.people
	if sm == null:
		# no staff in this run: the people are someone else's (a measurement's crowd, app/crowd.gd) or nobody's;
		# only those this view put there are taken away
		if _drove:
			out.clear()
			_drove = false
		return
	_drove = true
	_places(sm)
	var frac: float = clampf(ui.clock.acc / SimClock.STEP, 0.0, 1.0)
	avatars.time_scale = ui.clock.rate()
	_hat_t += delta
	var check_hat := _hat_t >= 0.5
	if check_hat:
		_hat_t = 0.0
	var fresh: bool = e != _step_e or e.step_no != _step_n
	if fresh:
		_step_e = e
		_step_n = e.step_no
		_anim_of.resize(sm.people.size())
		_anim_of.fill("?")
	var dt: float = delta * ui.clock.rate()       # plant time (paused: nobody moves or turns)
	# everyone on screen to `apart`, then where it draws them
	apart.begin()
	_walkers_t -= delta
	if _walkers_t <= 0.0:              # (looked for twice a second: players come and go seldom)
		_walkers_t = 0.5
		_walkers = get_tree().get_nodes_in_group("walkers")
	for w in _walkers:                 # the trainee and the other players: kept clear of
		if is_instance_valid(w) and w is Node3D:
			_row(apart.fixed(-1, (w as Node3D).global_position), -1, "", -1, 0, Vector3.ZERO)
	var me: int = ui.my_person()          # (the trainee's own person is the walker)
	# who is too far to be drawn (beyond the posed band, app/people.gd) is not kept apart: their place is all that matters
	var cam: Vector3 = avatars.camera.global_position if avatars.camera != null else Vector3.INF
	var far_r: float = float(avatars.cfg.get("posed_range", INF)) + 10.0
	var far_r2 := far_r * far_r if cam != Vector3.INF else INF
	for pi in sm.people.size():
		if pi == me:
			continue
		var leg: Array = e.sp_leg[pi]
		var place := -1
		var row := -1
		var on := ""
		var on_line := 0
		var d := Vector3.ZERO
		if not leg.is_empty():
			var steps: float = maxf(1.0, float(leg[3] - leg[2]))
			var k := clampf((float(e.step_no - leg[2]) + frac) / steps, 0.0, 1.0)
			if ways != null and ways.walk(mini(leg[0], leg[1]) * _at.size() + maxi(leg[0], leg[1]), leg[0], k,
					steps * SimClock.STEP):
				on = ON_NAMES[ways.on]
				if ways.pos.distance_squared_to(cam) > far_r2:
					# beyond the people drawn: on their line, not kept apart (from where they are when they come in,
					# into their lane at BACK_RATE)
					row = apart.fixed(pi, ways.pos)
					on_line = 2
					d = ways.dir.normalized() * (ways.speed if k < 1.0 else 0.0)
				else:
					row = apart.walker(pi, ways.line, ways.s, ways.sgn, ways.speed if k < 1.0 else 0.0)
					on_line = 1
			else:
				var a: Vector3 = _at[leg[0]]
				var b: Vector3 = _at[leg[1]]
				d = b - a
				# walked straight (no line built): not moved aside, others keep clear
				row = apart.fixed(pi, a.lerp(b, k))
				if absf(d.y) > 0.3 * maxf(0.01, Vector2(d.x, d.z).length()):
					on = "stairs"
				if k >= 1.0:
					d = Vector3.ZERO
		elif e.sp_pos[pi] != -1:
			place = e.sp_pos[pi]
			if _seated[place] == 1 or (_at[place] as Vector3).distance_squared_to(cam) > far_r2:
				row = apart.fixed(pi, _at[place])      # seated or lying: not moved off the seat
			else:
				row = apart.stander(pi, _at[place], ways.place_room[place] if ways != null else NO_ROOM)
		else:
			continue
		_row(row, pi, on, place, on_line, d)
	apart.solve(dt)
	var n := 0
	if drawn.size() < apart.n:
		drawn.resize(apart.n)
		drawn_kind.resize(apart.n)
		drawn_fresh.resize(apart.n)
	for i in apart.n:
		var pi := _who[i]
		if pi < 0:
			continue
		var at: Vector3 = apart.pos[i]
		var speed := 0.0
		var place := _place[i]
		var target = null
		if _line[i] == 1:
			speed = apart.speed[i]
			var f: Vector3 = apart.fwd[i]
			if f.length() > 0.05:
				target = atan2(-f.x, -f.z)
		elif _line[i] == 2:
			speed = _d[i].length()
			if speed > 0.0:
				target = atan2(-_d[i].x, -_d[i].z)
		elif place == -1:
			var d := _d[i]
			var leg: Array = e.sp_leg[pi]
			var steps: float = maxf(1.0, float(leg[3] - leg[2]))
			var k := clampf((float(e.step_no - leg[2]) + frac) / steps, 0.0, 1.0)
			speed = d.length() / (steps * SimClock.STEP) if k < 1.0 else 0.0
			if Vector2(d.x, d.z).length() > 0.05:
				target = atan2(-d.x, -d.z)
		elif sm.places[place].has("yaw"):
			target = -deg_to_rad(float(sm.places[place]["yaw"]))   # (plant: degrees clockwise from north)
		var cur = _yaw.get(pi)
		if cur == null and target == null:
			_yaw[pi] = 0.0          # (facing north until they have somewhere to face: from there they turn)
		if target != null:
			if cur == null or apart.fresh[i] == 1:
				cur = target
			else:
				var left := angle_difference(cur, target)
				cur = wrapf(cur + clampf(left * minf(1.0, TURN_EASE * dt), -TURN * dt, TURN * dt), -PI, PI)
			_yaw[pi] = cur
		if n >= out.size():
			out.append({})
		var p: Dictionary = out[n]
		var role: String = sm.people[pi]["role"]
		p.at = at
		p.yaw = _yaw.get(pi, 0.0)
		# the way they walk (the doors open by it: app/people_doors.gd; their heading trails it round a corner)
		p.dir = apart.fwd[i] if _line[i] == 1 else Vector3(_d[i].x, 0.0, _d[i].z).normalized()
		p.speed = speed
		p.on = _on[i]
		if _look0 == null:
			_look0 = avatars.info.looks.keys()[0]
		p.look = avatars.info.roles.get(role, _look0)
		if speed > 0.0:
			p.anim = ""
		elif _line[i] == 1 and apart.speed_in[i] > 0.0:
			p.anim = "idle"                 # held back on the way (app/keep_apart.gd): standing, then catching up
		else:
			if _anim_of[pi] == "?":         # (once a step: the place is the same through it)
				_anim_of[pi] = _anim(e, sm, pi, place)
			p.anim = _anim_of[pi]
		p.scale = 0.94 + 0.12 * float((pi * 37) % 11) / 10.0
		if check_hat or not _hat.has(pi):     # (twice a second: what is worn and where changes with the steps)
			if sm.zone_ids.is_empty():
				_hat[pi] = ui.main.area_at(at) != "Between the areas"
			else:
				# with zones (milestone S2): the hat on the head where a zone needs it and the person wears it; in the
				# hand elsewhere (the road variant), and so too for one who has taken it off in a zone (an unsafe act
				# seen)
				_hat[pi] = hat_on(e, sm, pi)
		p.hat = _hat[pi]
		drawn[n] = pi
		drawn_kind[n] = apart.kind[i]
		drawn_fresh[n] = apart.fresh[i]
		n += 1
	out.resize(n)


## The places' positions and the ways' lines, made again when the staff model changes.
func _places(sm) -> void:
	if _at.size() == sm.places.size() and _ways_of == sm:
		return
	_at.clear()
	for pl in sm.places:
		_at.append(Plant.g(pl["at"][0], pl["at"][1], pl["at"][2]))
	_ways_of = sm
	ways = StaffWays.open(sm, _at)
	_seated.resize(sm.places.size())
	for i in sm.places.size():
		var pl: Dictionary = sm.places[i]
		_seated[i] = 1 if sm.kind[i] in SEATED or sm.kind[i] == "bed" or pl.get("pose", "") in ["sit", "lie"] else 0


## What a person not walking is seen doing: their task step's, or sitting at a desk, seat or table.
func _anim(e, sm, pi: int, place: int) -> String:
	var cur = e.sp_cur[pi]
	var a := "idle"
	if cur != null:
		var s: Dictionary = sm.tasks[cur["task"]]["steps"][cur["step"]]
		if s.has("work"):
			a = s.get("anim", "use")
		elif s.has("op"):
			var w = s["op"].get("where", "")   # a string, or a list of them (PLANT3D.md §7.2)
			a = "type" if (w is Array and "screen" in w) or (w is String and w.contains("screen")) else "handwheel"
		else:
			for k in STEP_ANIM:
				if s.has(k):
					a = STEP_ANIM[k]
					break
	if a == "idle" and place >= 0 and sm.kind[place] in SEATED:
		a = "sit"
	return a



## Whether a person's hard hat is on their head (PLANT3D §17.11): they wear one and stand in a zone that needs it.
static func hat_on(e, sm, pi: int) -> bool:
	var helmet: int = 1 << int(sm.PPE.find("helmet"))
	if (e.sp_worn[pi] & helmet) == 0:
		return false
	var zm: int = sm.zones_of(e, pi)
	for z in sm.zone_ids.size():
		if zm & (1 << z) and (sm.zone_ppe[z] & helmet) != 0:
			return true
	return false


## One given to `apart` (its index `i`): the person, what they walk on, their place, whether on a line, the straight
## way's heading. (Kept in arrays that only grow: no appending in a drawn frame.)
func _row(i: int, pi: int, on: String, place: int, on_line: int, d: Vector3) -> void:
	if i >= _who.size():
		var m := maxi(16, i * 2)
		_who.resize(m)
		_on.resize(m)
		_place.resize(m)
		_line.resize(m)
		_d.resize(m)
	_who[i] = pi
	_on[i] = on
	_place[i] = place
	_line[i] = on_line
	_d[i] = d


## Where the engine has person `pi` this frame, as app/keep_apart.gd took it (the tests: did they jump?).
func _logical_of(pi: int) -> Vector3:
	return apart._logical[pi] if pi < apart._logical.size() else Vector3.INF
