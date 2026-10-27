## A line people walk along, with the room beside it (docs/PLANT3D.md §18.1 as built, phase 3): the points of a staff
## way's line (app/staff_ways.gd) or of a measurement crowd's route (app/crowd.gd), their distances along it, the side
## of the line (its right, by the way the points run) turning smoothly through each corner, and, when the content build
## measured it (builder/lane_room.gd), how far a person may stand to either side of it every STEP metres: a 0.3 m
## capsule clear of everything but doors, the feet on the same floor or flight, on the walkable mesh where the line is.
## People are drawn off their line only within that room (their lane, keeping apart: app/keep_apart.gd).
extends RefCounted

const STEP := 0.1               # metres between the room's samples along a line
const BLEND := 0.5              # metres either side of a corner over which the side turns (at most half a stretch)

var pts := PackedVector3Array()
var cum := PackedFloat32Array()     # the distance along the line at each point
var ang := PackedFloat32Array()     # per stretch: the heading of its run in plan (atan2(z, x)); a vertical one its neighbour's
var length := 0.0
var loop := false                   # the line ends where it starts (a crowd's route): its corners go round the end too
var room := PackedByteArray()       # per sample: the room to the left and right in cm, signed (empty: no room, the line itself)


static func make(points: PackedVector3Array, room_cm: PackedByteArray = PackedByteArray(), closed := false):
	var l = new()
	l.pts = points
	l.loop = closed
	l.cum.resize(points.size())
	l.cum[0] = 0.0
	for i in range(1, points.size()):
		l.cum[i] = l.cum[i - 1] + points[i - 1].distance_to(points[i])
	l.length = l.cum[points.size() - 1]
	l.ang.resize(maxi(0, points.size() - 1))
	var last := NAN
	var first := -1
	for i in points.size() - 1:
		var d := points[i + 1] - points[i]
		if Vector2(d.x, d.z).length() > 1e-3:
			l.ang[i] = atan2(d.z, d.x)
			if is_nan(last):
				first = i
			last = l.ang[i]
		else:
			l.ang[i] = last
	# a vertical stretch at the start: the first heading's
	for i in maxi(0, first):
		l.ang[i] = l.ang[first] if first >= 0 else 0.0
	if first < 0:
		l.ang.fill(0.0)
	if room_cm.size() == 2 * samples(l.length):
		l.room = room_cm
	return l


## The number of room samples of a line `length` metres long: one every STEP metres and one at its end.
static func samples(length: float) -> int:
	return ceili(length / STEP - 1e-4) + 1


## The distance along the line of sample `j`.
func sample_s(j: int) -> float:
	return minf(j * STEP, length)


## The stretch `s` is on.
func seg(s: float) -> int:
	return clampi(cum.bsearch(s, false) - 1, 0, pts.size() - 2)


## The point at `s` along the line.
func point(s: float) -> Vector3:
	return point_in(s, seg(s))


## The point at `s` on stretch `i` (seg(s)).
func point_in(s: float, i: int) -> Vector3:
	var span := cum[i + 1] - cum[i]
	return pts[i].lerp(pts[i + 1], clampf((s - cum[i]) / span, 0.0, 1.0) if span > 0.0 else 0.0)


## The heading in plan (atan2(z, x)) at `s`: its stretch's, turning towards the next one's over the last BLEND metres
## before a corner and from the last one's over the first after it (half way at the corner).
func heading(s: float) -> float:
	return heading_in(s, seg(s))


## The heading at `s` on stretch `i` (seg(s)).
func heading_in(s: float, i: int) -> float:
	var n := pts.size() - 1
	var a: float = ang[i]
	var len_i := cum[i + 1] - cum[i]
	var u := clampf(s - cum[i], 0.0, len_i)
	var prev := i - 1 if i > 0 else (n - 1 if loop else -1)
	var next := i + 1 if i < n - 1 else (0 if loop else -1)
	if prev >= 0 and n > 1:
		var b := minf(BLEND, minf(len_i, cum[prev + 1] - cum[prev]) * 0.5)
		if b > 1e-4 and u < b:
			return ang[prev] + wrapf(a - ang[prev], -PI, PI) * (0.5 + 0.5 * u / b)
	if next >= 0 and n > 1:
		var b := minf(BLEND, minf(len_i, cum[next + 1] - cum[next]) * 0.5)
		if b > 1e-4 and len_i - u < b:
			return a + wrapf(ang[next] - a, -PI, PI) * (0.5 - 0.5 * (len_i - u) / b)
	return a


## The way along the line in plan at `s` (unit, by the way the points run).
func forward(s: float) -> Vector3:
	var a := heading(s)
	return Vector3(cos(a), 0.0, sin(a))


## The line's right at `s` (unit, level), by the way the points run: forward × up.
func side(s: float) -> Vector3:
	var a := heading(s)
	return Vector3(-sin(a), 0.0, cos(a))


## Where someone `off` metres to the right of the line at `s` (by the way the points run) stands.
func at(s: float, off: float) -> Vector3:
	return point(s) + side(s) * off


## The room at `s`: Vector2(the most to the left, the most to the right), in metres to the right of the line (by the
## way the points run); (0, 0) on a line without room. Between two samples, from one to the other (the build measured
## it with a capsule wide enough for that: builder/lane_room.gd RADIUS).
func room_at(s: float) -> Vector2:
	if room.is_empty():
		return Vector2.ZERO
	var n := room.size() / 2
	var j := clampi(int(floor(s / STEP)), 0, n - 1)
	if j + 1 >= n:
		return _room(j)
	var s0 := sample_s(j)
	var s1 := sample_s(j + 1)
	return _room(j).lerp(_room(j + 1), clampf((s - s0) / maxf(1e-6, s1 - s0), 0.0, 1.0))


func _room(j: int) -> Vector2:
	var lo := room[2 * j]
	var hi := room[2 * j + 1]
	return Vector2(float(lo - 256 if lo > 127 else lo) * 0.01, float(hi - 256 if hi > 127 else hi) * 0.01)


## A room pair as stored (cm, signed bytes), each rounded inwards (where they meet, their middle).
static func pack(lo: float, hi: float) -> PackedByteArray:
	var a := clampi(ceili(lo * 100.0 - 1e-3), -127, 127)
	var b := clampi(floori(hi * 100.0 + 1e-3), -127, 127)
	if a > b:      # (no room: one place, its middle)
		a = clampi(roundi((lo + hi) * 50.0), -127, 127)
		b = a
	return PackedByteArray([a & 0xff, b & 0xff])
