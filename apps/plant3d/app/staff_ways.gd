## The staff's ways as people walk them (docs/PLANT3D.md §18.1 as built): the lines the content build found on the
## navigation mesh for staff.json's ways, with the feet on the floors and the steps (builder/staff_paths.gd), read
## from built/staff_paths.bin. ui/people_view.gd moves a person along their way's line by the fraction of the leg's
## time gone; no path is searched at run time. A way whose line is not in the file, or whose line does not end at its
## places (another staff file than the build's), is walked straight, as before. Each line comes with the room beside it
## and each place with the room round it (builder/lane_room.gd), where people may be drawn off them (app/keep_apart.gd).
extends RefCounted

const Lanes = preload("res://app/lanes.gd")

const FILE := "res://built/staff_paths.bin"
const FORMAT := "walkdown-plant-staff-paths-2"
const ON_FLOOR := 0
const ON_STAIRS := 1
const ON_LADDER := 2
const ENDS := 0.05              # metres: a line's ends at its places, in plan (the feet are on the floor under them)
const ENDS_Y := 0.6

var lines := {}                 # a * places + b (a < b) -> [points, times, on, the place its points start at, Lanes]
var place_room: Array = []      # per place: the room round it (builder/lane_room.gd place(), cm), or an empty array

# walk()'s answer
var pos := Vector3.ZERO         # the feet
var dir := Vector3.ZERO         # the stretch walked, in the way it is walked
var speed := 0.0                # m/s along it
var on := ON_FLOOR
var line                        # the line walked (app/lanes.gd)
var s := 0.0                    # metres along it from its first point
var sgn := 1.0                  # 1: walked the way its points run, -1: back along them


## The lines of the staff `sm` (sim/staff.gd) whose places are at `at` (Godot's frame, by place number), or null
## when the build has none.
static func open(sm, at: Array, file: String = FILE):
	if not FileAccess.file_exists(file):
		return null
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return null
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY or d.get("format", "") != FORMAT or typeof(d.get("ways")) != TYPE_DICTIONARY:
		return null
	var out = new()
	var np: int = sm.places.size()
	for key in d.ways:
		var ab: PackedStringArray = String(key).split("|")
		var w = d.ways[key]
		if ab.size() != 2 or not sm.pix.has(ab[0]) or not sm.pix.has(ab[1]) or typeof(w) != TYPE_ARRAY or w.size() != 4:
			continue
		var pts = w[0]
		var t = w[1]
		var o = w[2]
		var room = w[3]
		if not (pts is PackedVector3Array and t is PackedFloat32Array and o is PackedByteArray and room is PackedByteArray) \
				or pts.size() < 2 or t.size() != pts.size() or o.size() != pts.size() - 1:
			continue
		if not _sane(t, o) or Array(pts).any(func(v: Vector3) -> bool: return not v.is_finite()):
			continue
		var a: int = sm.pix[ab[0]]
		var b: int = sm.pix[ab[1]]
		if not _near(pts[0], at[a]) or not _near(pts[pts.size() - 1], at[b]):
			continue
		# (a room of the wrong length is no room: Lanes.make leaves it out, and the line is walked on its middle)
		out.lines[mini(a, b) * np + maxi(a, b)] = [pts, t, o, a, Lanes.make(pts, room)]
	out.place_room.resize(np)
	var rooms = d.get("places")
	for i in np:
		var r = rooms.get(sm.places[i]["id"]) if rooms is Dictionary else null
		out.place_room[i] = r if r is PackedByteArray else PackedByteArray()
	return out


## Times from 0 to 1, never back; each stretch walked on something known.
static func _sane(t: PackedFloat32Array, o: PackedByteArray) -> bool:
	if t[0] != 0.0 or t[t.size() - 1] != 1.0:
		return false
	for i in range(1, t.size()):
		if t[i] < t[i - 1] or not is_finite(t[i]):
			return false
	for v in o:
		if v > ON_LADDER:
			return false
	return true


static func _near(p: Vector3, q: Vector3) -> bool:
	return Vector2(p.x - q.x, p.z - q.z).length() <= ENDS and absf(p.y - q.y) <= ENDS_Y


## Where a person is who has gone the fraction `k` of the time of the way `key`, from the place `from`, the whole way
## taking `seconds`: sets pos, dir, speed, on, and line, s and sgn (where that is on the line, and which way it is
## walked). False when the way has no line here.
func walk(key: int, from: int, k: float, seconds: float) -> bool:
	var l = lines.get(key)
	if l == null:
		return false
	var pts: PackedVector3Array = l[0]
	var t: PackedFloat32Array = l[1]
	var fwd: bool = from == l[3]
	var kk := clampf(k if fwd else 1.0 - k, 0.0, 1.0)
	var i := clampi(t.bsearch(kk, true), 1, t.size() - 1)
	var span := t[i] - t[i - 1]
	var f := clampf((kk - t[i - 1]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	pos = pts[i - 1].lerp(pts[i], f)
	line = l[4]
	sgn = 1.0 if fwd else -1.0
	s = line.cum[i - 1] + (line.cum[i] - line.cum[i - 1]) * f
	# a stretch of no time (two times equal in single precision): its speed and heading are the next one's
	# (the next one as walked: back along the line when walked from its other end)
	while span <= 0.0 and (i < t.size() - 1 if fwd else i > 1):
		i += 1 if fwd else -1
		span = t[i] - t[i - 1]
	dir = (pts[i] - pts[i - 1]) if fwd else (pts[i - 1] - pts[i])
	speed = dir.length() / (span * seconds) if span > 0.0 and seconds > 0.0 else 0.0
	on = (l[2] as PackedByteArray)[i - 1]
	return true
