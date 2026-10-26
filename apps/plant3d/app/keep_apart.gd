## Keeping people apart on screen (docs/PLANT3D.md §18.1 as built, phase 3). View only: the engine's positions (§17.3)
## are the truth and stay the same on every player's screen; this moves only where a person is drawn, and only within
## the room the content build measured (app/lanes.gd, builder/lane_room.gd), so nobody is drawn in a machine, off a
## floor's edge, off a flight's side or through a rail.
##   walking   on their way's line, in a lane LANE m to the right (two people meeting pass each other), moved further
##             aside when someone is within SEP, and held back along the line (standing, then catching up at up to
##             CATCH faster than the line's speed) when sidestepping is not enough: up to LAG_MAX behind, never behind
##             the place they left, and caught up before the place they go to (at most half the distance left)
##   standing  at their place, moved up to STAND_MAX away from someone within SEP, in the directions the place has room
##   fixed     not moved: someone seated, and the trainee and the other players (the group "walkers": everyone keeps
##             clear of them, they are never pushed)
## Everything moves at bounded rates in plant time (PUSH_RATE aside, BACK_RATE back to the lane), so nobody jumps; a
## person who jumped in the engine (a fast-forward's jump, a restored run) starts again in their lane.
## The caller (ui/people_view.gd, the tests) adds everyone each frame (begin(), walker() / stander() / fixed()), then
## solve(dt) gives pos, fwd and speed per one added.
extends RefCounted

const Lanes = preload("res://app/lanes.gd")

const SEP := 0.7                # metres between two people's centres, kept where there is room
const LANE := 0.35              # metres to the right of the line a walker keeps to
const NEAR_DY := 1.2            # metres apart in height beyond which two people don't meet (two floors)
const PUSH_RATE := 1.2          # m/s: aside, away from someone
const BACK_RATE := 0.3          # m/s: back to the lane, or to the place's point, when nobody is near
const LAG_MAX := 1.5            # metres a walker may be drawn behind where they are
const CATCH := 0.35             # a late walker catches up at up to this fraction faster than their line's speed
const STAND_MAX := 0.5          # metres a standing person may be drawn off their place
const HEAD_ON := 0.3            # two walking at each other this nearly in line: each steps to their right
const TELEPORT := 2.0           # metres a person's logical point may move in a frame beyond their speed: a jump
const DIRS := 32                # directions round a place its room is measured in (builder/lane_room.gd)

const FIXED := 0
const WALKING := 1
const STANDING := 2

# this frame's people, in the order added
var n := 0
var ids := PackedInt32Array()           # the caller's number for each (-1: fixed and not kept)
var kind := PackedByteArray()
var lines: Array = []                   # walking: their line (app/lanes.gd)
var s_at := PackedFloat32Array()        # walking: where they are along it (the engine's)
var sgn := PackedFloat32Array()         # walking: 1 along the line's points, -1 back along them
var speed_in := PackedFloat32Array()    # walking: the line's speed there
var rooms: Array = []                   # standing: the place's room (DIRS bytes, cm)
var base := PackedVector3Array()        # standing and fixed: the point
# solve()'s answer, per one added
var pos := PackedVector3Array()         # where they are drawn (the feet)
var fwd := PackedVector3Array()         # walking: the way they walk where drawn (level, unit); else zero
var speed := PackedFloat32Array()       # walking: the speed they are drawn at (lower while held back, higher catching up)
var fresh := PackedByteArray()          # 1: new this frame, or jumped (their heading is not turned to, it is set)

# kept per person (by id) from frame to frame
var _lat := PackedFloat32Array()        # walking: metres to their right of the line
var _lag := PackedFloat32Array()        # walking: metres behind
var _off := PackedVector3Array()        # standing: from the place; walking: what is left of it after setting off
var _seen := PackedInt32Array()         # the frame each was last added in
var _kind := PackedByteArray()
var _logical := PackedVector3Array()    # their logical point last frame
var _drawn := PackedVector3Array()
var _frame := 0
var _push := PackedVector3Array()
var _near := PackedByteArray()


func begin() -> void:
	n = 0
	ids.resize(0)
	kind.resize(0)
	lines.clear()
	s_at.resize(0)
	sgn.resize(0)
	speed_in.resize(0)
	rooms.clear()
	base.resize(0)


func _add(id: int, k: int) -> int:
	ids.append(id)
	kind.append(k)
	lines.append(null)
	s_at.append(0.0)
	sgn.append(1.0)
	speed_in.append(0.0)
	rooms.append(null)
	base.append(Vector3.ZERO)
	n += 1
	return n - 1


## Someone on `line` at `s` along it, walking along its points (`dir` 1) or back along them (-1) at `v` m/s.
func walker(id: int, line, s: float, dir: float, v: float) -> int:
	var i := _add(id, WALKING)
	lines[i] = line
	s_at[i] = s
	sgn[i] = 1.0 if dir >= 0.0 else -1.0
	speed_in[i] = v
	base[i] = line.point(s)
	return i


## Someone standing at a place's point `at`, with its room (builder/lane_room.gd place(); empty: none).
func stander(id: int, at: Vector3, room: PackedByteArray) -> int:
	var i := _add(id, STANDING)
	base[i] = at
	rooms[i] = room
	return i


## Someone not to be moved, whom the others keep clear of.
func fixed(id: int, at: Vector3) -> int:
	var i := _add(id, FIXED)
	base[i] = at
	return i


func _grow(id: int) -> void:
	if id < _lat.size():
		return
	var m := id + 1
	_lat.resize(m)
	_lag.resize(m)
	_off.resize(m)
	_kind.resize(m)
	_logical.resize(m)
	_drawn.resize(m)
	var old := _seen.size()
	_seen.resize(m)
	for k in range(old, m):
		_seen[k] = -10


## The room at `s` on `line` to the walker's left and right (x the most to the left, as a negative, y to the right).
static func lane_room(line, s: float, dir: float) -> Vector2:
	var r: Vector2 = line.room_at(s)
	return r if dir > 0.0 else Vector2(-r.y, -r.x)


## How far someone may be drawn from a place in the level direction `dir` (unit), with its room as measured: the
## nearer of the two measured directions either side, and STAND_MAX at most.
static func stand_room(room, dir: Vector3) -> float:
	if room == null or (room as PackedByteArray).size() != DIRS:
		return 0.0
	var f := fposmod(atan2(dir.z, dir.x), TAU) / TAU * DIRS
	var i := int(floor(f)) % DIRS
	return minf(STAND_MAX, minf(room[i], room[(i + 1) % DIRS]) * 0.01)


static func _clamp_stand(room, off: Vector3) -> Vector3:
	var l := off.length()
	if l < 1e-5:
		return Vector3.ZERO
	var r := stand_room(room, off / l)
	return off if l <= r else off * (r / l)


## Where everyone is drawn after `dt` seconds of plant time.
func solve(dt: float) -> void:
	_frame += 1
	pos.resize(n)
	fwd.resize(n)
	speed.resize(n)
	fresh.resize(n)
	_push.resize(n)
	_near.resize(n)
	# where each is now (their kept offsets on this frame's logical points)
	for i in n:
		_push[i] = Vector3.ZERO
		_near[i] = 0
		fresh[i] = 0
		var id := ids[i]
		if kind[i] == FIXED or id < 0:
			pos[i] = base[i]
			fwd[i] = Vector3.ZERO
			speed[i] = 0.0
			continue
		_grow(id)
		var logical := base[i]
		var jumped := _seen[id] != _frame - 1 or \
				logical.distance_to(_logical[id]) > TELEPORT + 2.0 * maxf(1.0, speed_in[i]) * dt
		if jumped:
			fresh[i] = 1
			_lat[id] = LANE
			_lag[id] = 0.0
			_off[id] = Vector3.ZERO
		elif _kind[id] != kind[i]:
			# setting off from a place, or arriving at one: from where they were drawn
			if kind[i] == WALKING:
				_lat[id] = 0.0
				_lag[id] = 0.0
				_off[id] = _drawn[id] - logical
				_off[id].y = 0.0
			else:
				_off[id] = _drawn[id] - logical
				_off[id].y = 0.0
		_seen[id] = _frame
		_kind[id] = kind[i]
		_logical[id] = logical
		_place(i, id)
	# who is too near whom (along x, then the pairs that close)
	if n > 1:
		var keys := PackedInt64Array()
		keys.resize(n)
		for i in n:
			keys[i] = ((int(round(pos[i].x * 100.0)) + (1 << 30)) << 12) | i
		keys.sort()
		for a in n:
			var ia := int(keys[a] & 4095)
			var pa := pos[ia]
			for b in range(a + 1, n):
				var ib := int(keys[b] & 4095)
				var pb := pos[ib]
				if pb.x - pa.x >= SEP + 0.2:
					break
				if absf(pb.y - pa.y) > NEAR_DY:
					continue
				var d := Vector2(pa.x - pb.x, pa.z - pb.z)
				var l := d.length()
				if l >= SEP + 0.2:
					continue
				_near[ia] = 1
				_near[ib] = 1
				if l >= SEP:
					continue
				var u := Vector3(d.x / l, 0.0, d.y / l) if l > 1e-3 else \
						Vector3(cos(float(ids[ia] - ids[ib])), 0.0, sin(float(ids[ia] - ids[ib])))
				var ma := kind[ia] != FIXED and ids[ia] >= 0
				var mb := kind[ib] != FIXED and ids[ib] >= 0
				var wa := (0.5 if mb else 1.0) if ma else 0.0
				var wb := (0.5 if ma else 1.0) if mb else 0.0
				var m := SEP - l
				_push[ia] += u * (m * wa)
				_push[ib] -= u * (m * wb)
				# walking at each other nearly in line: each to their own right
				if kind[ia] == WALKING and kind[ib] == WALKING and fwd[ia].dot(fwd[ib]) < -0.5:
					var ra := fwd[ia].cross(Vector3.UP)
					if absf(u.dot(ra)) < HEAD_ON:
						_push[ia] += ra * (m * wa)
						_push[ib] += fwd[ib].cross(Vector3.UP) * (m * wb)
	# everyone moved towards where they are pushed, or back, at bounded rates; then drawn
	for i in n:
		var id := ids[i]
		if kind[i] == FIXED or id < 0:
			continue
		var push := _push[i]
		var pushed := push.length_squared() > 1e-8
		if kind[i] == WALKING:
			var right := fwd[i].cross(Vector3.UP)
			var lat0 := _lat[id]
			var lag0 := _lag[id]
			var v := speed_in[i]
			var target := lat0 + push.dot(right) if pushed else LANE
			_lat[id] = move_toward(lat0, target, (PUSH_RATE if pushed else BACK_RATE) * dt)
			var along := push.dot(fwd[i])
			if pushed and along < 0.0:
				_lag[id] = minf(lag0 - along, lag0 + v * dt)      # held back: at most standing still
			else:
				_lag[id] = maxf(0.0, lag0 - CATCH * v * dt)
			var l = lines[i]
			var prog: float = s_at[i] if sgn[i] > 0.0 else l.length - s_at[i]
			_lag[id] = clampf(_lag[id], 0.0, minf(LAG_MAX, minf(prog, 0.5 * (l.length - prog))))
			_off[id] = _off[id].move_toward(Vector3.ZERO, PUSH_RATE * dt)
			_place(i, id)
			speed[i] = maxf(0.0, v - (_lag[id] - lag0) / dt) if dt > 0.0 else v
		else:
			var off := _off[id]
			if pushed:
				off = off.move_toward(off + Vector3(push.x, 0.0, push.z), PUSH_RATE * dt)
			elif _near[i] == 0:
				off = off.move_toward(Vector3.ZERO, BACK_RATE * dt)
			_off[id] = _clamp_stand(rooms[i], off)
			_place(i, id)
		_drawn[id] = pos[i]


## Where person `i` (kept as `id`) is drawn with their kept offsets, clamped to the room: pos, fwd (and speed).
func _place(i: int, id: int) -> void:
	if kind[i] == WALKING:
		var l = lines[i]
		var sg := sgn[i]
		var s: float = clampf(s_at[i] - sg * _lag[id], 0.0, l.length)
		var r := lane_room(l, s, sg)
		_lat[id] = clampf(_lat[id], r.x, r.y) if r.x <= r.y else (r.x + r.y) * 0.5
		var a: float = l.heading(s)     # (once: the side and the way along are both of it)
		pos[i] = l.point(s) + Vector3(-sin(a), 0.0, cos(a)) * (sg * _lat[id]) + _off[id]
		fwd[i] = Vector3(cos(a), 0.0, sin(a)) * sg
		speed[i] = speed_in[i]
	else:
		_off[id] = _clamp_stand(rooms[i], _off[id])
		pos[i] = base[i] + _off[id]
		fwd[i] = Vector3.ZERO
		speed[i] = 0.0
