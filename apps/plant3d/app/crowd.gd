## A crowd round the walker, for measuring what people cost (milestone A1: the frames walk among 6, 12 and 24
## people, docs/PLANT3D.md §18.4) until the staff engine drives them: `count` people on the walk's own route (walkable
## all along: app/routes.gd), most walking it one way or the other in their lanes (0.35 m right of the route, as
## docs/PLANT3D.md §18.1), some standing at work beside it, all kept within AHEAD m ahead of the walker and BEHIND m
## behind (one who falls out of that comes back in at its other end). No path search at run time: positions are
## points along the route's polyline. The same people every run (a fixed seed).
extends Node

const AHEAD := 22.0
const BEHIND := 18.0
const LANE := 0.35
const WORK := ["inspect", "radio", "write", "handwheel", "calibrate", "talk", "wrench", "idle"]

var people_node          # app/people.gd
var walker: Node3D
var pts := PackedVector3Array()
var cum := PackedFloat32Array()
var length := 0.0
var s_walker := 0.0
var crowd: Array = []    # per person: {s, dir, speed, lane, work, anim}
var loop := false        # the route ends where it starts (the frames and camp walks): people go round it
var _lost := 0.0         # squared distance from the walker to the route at its last place


## `route`: app/routes.gd's steps (their `to` points), `count` people.
func setup(route: Array, w: Node3D, people, count: int) -> void:
	walker = w
	people_node = people
	for st in route:
		if st.has("to"):
			if pts.size() == 0 or (pts[pts.size() - 1] as Vector3).distance_to(st.to) > 0.01:
				pts.append(st.to)
	cum.append(0.0)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	length = cum[cum.size() - 1]
	loop = pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1.0
	# placed before the first frame is drawn, and moved before the people node places them in each frame
	process_priority = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var looks: Array = people.info.looks.keys()
	s_walker = _nearest(walker.global_position, 0.0, length)
	for i in count:
		var work := i % 3 == 2
		var p := {"s": s_walker - BEHIND + (AHEAD + BEHIND) * (float(i) + 0.5) / count,
			"dir": 1.0 if i % 2 == 0 else -1.0, "speed": rng.randf_range(1.1, 1.6), "lane": LANE + rng.randf_range(0.0, 0.5),
			"work": work, "anim": WORK[i % WORK.size()] if work else ""}
		if not work and i % 7 == 5:
			p.speed = 3.2   # a few run
		crowd.append(p)
		people.people.append({"at": Vector3.ZERO, "yaw": 0.0, "speed": 0.0, "anim": p.anim, "look": looks[i % looks.size()],
			"scale": rng.randf_range(0.94, 1.06), "on": ""})
	_process(0.0)   # their first places, before a frame is drawn


func _process(delta: float) -> void:
	if pts.size() < 2:
		return
	s_walker = _nearest(walker.global_position, s_walker - 30.0, s_walker + 30.0)
	if _lost > 25.0:   # (the walk went round to its start again)
		s_walker = _nearest(walker.global_position, 0.0, length)
	var span := AHEAD + BEHIND
	for i in crowd.size():
		var c: Dictionary = crowd[i]
		if not c.work:
			c.s += c.dir * c.speed * delta
		# the difference along the route as it loops (the walker's place is folded into the route's length)
		var ds: float = (fposmod(c.s - s_walker + length * 0.5, length) - length * 0.5) if loop else c.s - s_walker
		if ds > AHEAD:
			c.s -= span
		elif ds < -BEHIND:
			c.s += span
		# on a loop round it; on an open route kept within its ends (no one drawn at the far end)
		var s: float = fposmod(c.s, length) if loop else clampf(c.s, 0.0, length)
		var k := _segment(s)
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var f := (s - cum[k]) / maxf(1e-4, cum[k + 1] - cum[k])
		var dir := (b - a)
		var flat := Vector3(dir.x, 0, dir.z)
		var fwd := flat.normalized() if flat.length() > 1e-3 else Vector3.FORWARD
		if not c.work:
			fwd *= c.dir
		var right := fwd.cross(Vector3.UP).normalized()
		var p: Dictionary = people_node.people[i]
		var lane: float = c.lane if not c.work else 0.8
		p.at = a.lerp(b, f) + right * lane
		var face := fwd if not c.work else -right   # workers face the route
		p.yaw = atan2(-face.x, -face.z)
		p.speed = 0.0 if c.work else c.speed
		p.on = "stairs" if absf(dir.y) > 0.3 * maxf(0.01, flat.length()) else ""


func _segment(s: float) -> int:
	var lo := 0
	var hi := cum.size() - 2
	while lo < hi:
		var m := (lo + hi + 1) / 2
		if cum[m] <= s:
			lo = m
		else:
			hi = m - 1
	return lo


## The walker's place along the route (its arc length), looked for between s0 and s1.
func _nearest(at: Vector3, s0: float, s1: float) -> float:
	var best := INF
	var best_s := s_walker
	for k in pts.size() - 1:
		if cum[k + 1] < s0 or cum[k] > s1:
			continue
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var ab := b - a
		var t := clampf((at - a).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
		var d := at.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			best_s = cum[k] + t * ab.length()
	_lost = best
	return best_s
