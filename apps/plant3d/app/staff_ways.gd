## The staff's ways as people walk them (docs/PLANT3D.md §18.1 as built): the lines the content build found on the
## navigation mesh for staff.json's ways, with the feet on the floors and the steps (builder/staff_paths.gd), read
## from built/staff_paths.bin. ui/people_view.gd moves a person along their way's line by the fraction of the leg's
## time gone; no path is searched at run time. A way whose line is not in the file, or whose line does not end at its
## places (another staff file than the build's), is walked straight, as before.
extends RefCounted

const FILE := "res://built/staff_paths.bin"
const FORMAT := "walkdown-plant-staff-paths-1"
const ON_FLOOR := 0
const ON_STAIRS := 1
const ON_LADDER := 2
const ENDS := 0.05              # metres: a line's ends at its places, in plan (the feet are on the floor under them)
const ENDS_Y := 0.6

var lines := {}                 # a * places + b (a < b) -> [points, times, on, the place its points start at]

# walk()'s answer
var pos := Vector3.ZERO         # the feet
var dir := Vector3.ZERO         # the stretch walked, in the way it is walked
var speed := 0.0                # m/s along it
var on := ON_FLOOR


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
		if ab.size() != 2 or not sm.pix.has(ab[0]) or not sm.pix.has(ab[1]) or typeof(w) != TYPE_ARRAY or w.size() != 3:
			continue
		var pts = w[0]
		var t = w[1]
		var o = w[2]
		if not (pts is PackedVector3Array and t is PackedFloat32Array and o is PackedByteArray) or pts.size() < 2 \
				or t.size() != pts.size() or o.size() != pts.size() - 1:
			continue
		var a: int = sm.pix[ab[0]]
		var b: int = sm.pix[ab[1]]
		if not _near(pts[0], at[a]) or not _near(pts[pts.size() - 1], at[b]):
			continue
		out.lines[mini(a, b) * np + maxi(a, b)] = [pts, t, o, a]
	return out


static func _near(p: Vector3, q: Vector3) -> bool:
	return Vector2(p.x - q.x, p.z - q.z).length() <= ENDS and absf(p.y - q.y) <= ENDS_Y


## Where a person is who has gone the fraction `k` of the time of the way `key`, from the place `from`, the whole way
## taking `seconds`: sets pos, dir, speed and on. False when the way has no line here.
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
	dir = (pts[i] - pts[i - 1]) if fwd else (pts[i - 1] - pts[i])
	speed = dir.length() / (span * seconds) if span > 0.0 and seconds > 0.0 else 0.0
	on = (l[2] as PackedByteArray)[i - 1]
	return true
