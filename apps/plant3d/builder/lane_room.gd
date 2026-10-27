## The room beside the lines people walk and round the places they stand at (docs/PLANT3D.md §18.1 as built, phase 3),
## measured by the content build in the built scenes, for app/lanes.gd and app/keep_apart.gd: how far to either side of
## a line (every Lanes.STEP metres) and how far from a place (in DIRS directions) a person can be drawn with
##   a capsule of RADIUS (0.4 to 1.8 m above the feet) clear of everything but the doors (they open for people),
##   the floor under the feet within FLOOR_DY of the one under the line or the place (not off a step, a flight's side
##     or a platform's edge, not onto a kerb), looked for every FLOOR_STEP metres,
##   and, where the line or the place is on the walkable mesh, within NAV_XZ of it in plan.
## A line's room then changes by at most K metres a metre along it (so that someone at its edge is moved aside
## smoothly, never jumps), and a staff way's goes to nothing at its places (people arrive at a place's point).
extends RefCounted

const Lanes = preload("res://app/lanes.gd")
const StaffPaths = preload("res://builder/staff_paths.gd")
const KeepApart = preload("res://app/keep_apart.gd")

## The walker's 0.3 m and 11 cm: a person between two samples is within 5 cm along of one, the room between them up to
## 5 cm off that one's (at K), and the side's turn moves them up to ARC / 2 = 4 cm more, along the line too: at most
## √((0.05 + 0.04)² + 0.05²) = 0.103 from a point measured clear.
const RADIUS := 0.41
## Where the line turns, the room is at most ARC over the turn between two samples (radians): someone off the line
## sweeps an arc as its side turns, and between two samples it is at most ARC long (a corner turned within a few cm
## leaves no room: people go round it on the line).
const ARC := 0.08
const MAX := 0.9                # metres looked for on either side of a line
const K := 1.0                  # metres the room may change by per metre along the line
const FLOOR_STEP := 0.05
const FLOOR_DY := 0.08
const NAV_XZ := 0.15
const STAND_MAX := 0.6          # metres looked for round a place
## Directions round a place (app/keep_apart.gd's): between two of them (at most 5.6° from one) someone STAND_MAX out
## is within 0.6 × sin 5.6° = 6 cm of a measured one, inside RADIUS's margin.
const DIRS := KeepApart.DIRS

var space: PhysicsDirectSpaceState3D
var exclude: Array[RID] = []
# the walkable mesh's polygons in plan, by cell (Godot's own closest-point query looks at every polygon: 0.5 ms)
const NAV_CELL := 2.0
var _poly: Array = []           # [PackedVector2Array in plan, lowest y, highest y]
var _grid := {}                 # Vector2i -> Array of _poly's indices (each within NAV_XZ of the cell)
var q := PhysicsShapeQueryParameters3D.new()
var stats := {"samples": 0, "blocked": 0, "squeezed": 0, "moved": 0}


func _init(s: PhysicsDirectSpaceState3D, nm: NavigationMesh, skip: Array) -> void:
	space = s
	exclude.assign(skip)
	if nm != null:
		var v := nm.get_vertices()
		for i in nm.get_polygon_count():
			var ix := nm.get_polygon(i)
			var plan := PackedVector2Array()
			var y0 := INF
			var y1 := -INF
			var lo := Vector2(INF, INF)
			var hi := -lo
			for k in ix:
				var q := v[k]
				plan.append(Vector2(q.x, q.z))
				y0 = minf(y0, q.y)
				y1 = maxf(y1, q.y)
				lo = lo.min(Vector2(q.x, q.z))
				hi = hi.max(Vector2(q.x, q.z))
			var k := _poly.size()
			_poly.append([plan, y0, y1])
			for cx in range(floori((lo.x - NAV_XZ) / NAV_CELL), floori((hi.x + NAV_XZ) / NAV_CELL) + 1):
				for cz in range(floori((lo.y - NAV_XZ) / NAV_CELL), floori((hi.y + NAV_XZ) / NAV_CELL) + 1):
					var key := Vector2i(cx, cz)
					if not _grid.has(key):
						_grid[key] = []
					(_grid[key] as Array).append(k)
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.4 + 2.0 * (RADIUS - 0.3)    # 0.4 to 1.8 m above the feet, as the walker's
	q.shape = cap
	q.exclude = exclude


func clear(feet: Vector3) -> bool:
	q.motion = Vector3.ZERO
	q.transform = Transform3D(Basis(), feet + Vector3.UP * 1.1)
	return space.intersect_shape(q, 1).is_empty()


## How far the capsule moves from `feet` along `dir` (unit) before it touches something, up to `most`.
func reach(feet: Vector3, dir: Vector3, most: float) -> float:
	if most <= 0.0:
		return 0.0
	q.transform = Transform3D(Basis(), feet + Vector3.UP * 1.1)
	q.motion = dir * most
	var r := space.cast_motion(q)
	q.motion = Vector3.ZERO
	return most * r[0] if r.size() == 2 else 0.0


## The floor under `p` (the highest level face three rays a few mm apart meet, from 0.5 m above to 0.6 m below; a
## step's edge counts), or NAN.
func floor_at(p: Vector3) -> float:
	return StaffPaths.surface(space, p, 0.5, 0.6, exclude)


## Whether `p` is on the walkable mesh, or within NAV_XZ of it in plan (and within 0.5 m of its height).
func on_mesh(p: Vector3) -> bool:
	if _poly.is_empty():
		return true
	var list = _grid.get(Vector2i(floori(p.x / NAV_CELL), floori(p.z / NAV_CELL)))
	if list == null:
		return false
	var q := Vector2(p.x, p.z)
	var near: Array = []
	for k in list:
		var pg: Array = _poly[k]
		if p.y < pg[1] - 0.5 or p.y > pg[2] + 0.5:
			continue
		if Geometry2D.is_point_in_polygon(q, pg[0]):
			return true
		near.append(pg[0])
	for plan in near:
		var m: int = plan.size()
		for i in m:
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, plan[i], plan[(i + 1) % m])) <= NAV_XZ:
				return true
	return false


## How far from `from` along `dir` (unit, level) a person can go, up to `most`: the capsule clear, the floor at `y0`
## every FLOOR_STEP, and when `mesh` on the mesh (at the end, and where it is not, the last of FLOOR_STEP's points that
## is, halving towards it: a hole in the mesh narrower than the capsule's sweep is no matter).
func room(from: Vector3, dir: Vector3, most: float, y0: float, mesh: bool) -> float:
	var d := reach(from, dir, most)
	var o := FLOOR_STEP
	while o < d + FLOOR_STEP:
		var p := from + dir * minf(o, d)
		var y := floor_at(p)
		if is_nan(y) or absf(y - y0) > FLOOR_DY:
			d = maxf(0.0, o - FLOOR_STEP)
			break
		o += FLOOR_STEP
	if mesh and d > 0.0 and not on_mesh(from + dir * d + Vector3.UP * (y0 - from.y)):
		var good := 0.0
		var bad := d
		while bad - good > 0.02:
			var m := (good + bad) * 0.5
			if on_mesh(from + dir * m + Vector3.UP * (y0 - from.y)):
				good = m
			else:
				bad = m
		d = good
	return d


## A line's room (app/lanes.gd `room`): `taper` brings it to nothing at both ends (a staff way's places).
func line(l, taper: bool) -> PackedByteArray:
	var n: int = Lanes.samples(l.length)
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(n)
	hi.resize(n)
	var lo0 := PackedFloat32Array()     # as measured (clear), before the limits below
	var hi0 := PackedFloat32Array()
	lo0.resize(n)
	hi0.resize(n)
	for j in n:
		stats.samples += 1
		var s: float = l.sample_s(j)
		var c: Vector3 = l.point(s)
		var side: Vector3 = l.side(s)
		var y0 := floor_at(c)
		if is_nan(y0):
			y0 = c.y
		var mesh := on_mesh(Vector3(c.x, y0, c.z))
		var st: Vector3 = l.pts[l.seg(s) + 1] - l.pts[l.seg(s)]
		if absf(st.y) > 2.0 * Vector2(st.x, st.z).length():
			lo[j] = 0.0   # up a ladder: on its rungs
			hi[j] = 0.0
			continue
		# where the line itself is not clear (a crowd's route by a post): the nearest clear place beside it
		var b := 0.0
		if not _fits(c, y0):
			b = NAN
			var o := 0.05
			while o <= MAX + 1e-4 and is_nan(b):
				for sg in [1.0, -1.0]:
					if is_nan(b) and _fits(c + side * o * sg, y0):
						b = o * sg
				o += 0.05
			if is_nan(b):
				stats.blocked += 1
				lo[j] = 0.0
				hi[j] = 0.0
				continue
			stats.moved += 1
		var base := c + side * b
		hi[j] = b + room(base, side, MAX - b, y0, mesh)
		lo[j] = b - room(base, -side, MAX + b, y0, mesh)
		lo0[j] = lo[j]
		hi0[j] = hi[j]
		# the most the heading turns within a sample either side (at the ends and at every corner between: a zig-zag
		# shorter than a sample turns and turns back)
		var turn := 0.0
		var h0: float = l.heading(s)
		var at_s: Array = [maxf(s - Lanes.STEP, 0.0), minf(s + Lanes.STEP, l.length)]
		for k in l.pts.size():
			if absf(l.cum[k] - s) <= Lanes.STEP:
				at_s.append_array([maxf(l.cum[k] - 0.005, 0.0), minf(l.cum[k] + 0.005, l.length)])
		for x in at_s:
			turn = maxf(turn, absf(wrapf(l.heading(x) - h0, -PI, PI)))
		if turn > 1e-4:
			hi[j] = minf(hi[j], ARC / turn)
			lo[j] = maxf(lo[j], -ARC / turn)
		if taper:
			var e := K * minf(s, l.length - s)
			hi[j] = minf(hi[j], e)
			lo[j] = maxf(lo[j], -e)
	# changing by at most K a metre along (both ways round a loop)
	for rnd in (2 if l.loop else 1):
		for j in range(1, n):
			var ds: float = l.sample_s(j) - l.sample_s(j - 1)
			hi[j] = minf(hi[j], hi[j - 1] + K * ds)
			lo[j] = maxf(lo[j], lo[j - 1] - K * ds)
		for j in range(n - 2, -1, -1):
			var ds: float = l.sample_s(j + 1) - l.sample_s(j)
			hi[j] = minf(hi[j], hi[j + 1] + K * ds)
			lo[j] = maxf(lo[j], lo[j + 1] - K * ds)
		if l.loop:
			var a := maxf(lo[0], lo[n - 1])
			var z := minf(hi[0], hi[n - 1])
			lo[0] = a
			lo[n - 1] = a
			hi[0] = z
			hi[n - 1] = z
	var out := PackedByteArray()
	for j in n:
		if taper and (j == 0 or j == n - 1):
			lo[j] = 0.0         # (at its places: the person is at the place's point, as the engine has them)
			hi[j] = 0.0
		elif lo[j] > hi[j]:
			stats.squeezed += 1
			# one place: the middle, within what was measured clear there (not a spot found blocked)
			var m := (lo[j] + hi[j]) * 0.5
			if lo0[j] <= hi0[j]:
				m = clampf(m, lo0[j], hi0[j])
			lo[j] = m
			hi[j] = m
		out.append_array(Lanes.pack(lo[j], hi[j]))
	return out


func _fits(p: Vector3, y0: float) -> bool:
	if not clear(p):
		return false
	var y := floor_at(p)
	return not is_nan(y) and absf(y - y0) <= FLOOR_DY


## The room round a place at `at` (the feet): DIRS bytes, cm in each direction (the first along +x, then turning
## towards +z); all 0 where the place itself is not clear.
func place(at: Vector3) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(DIRS)
	out.fill(0)
	var y0 := floor_at(at)
	if is_nan(y0):
		y0 = at.y
	# (the doors solid: someone standing is not walking through one, and nobody opens it for them)
	var skip := q.exclude
	q.exclude = []
	if _fits(at, y0):
		var mesh := on_mesh(Vector3(at.x, y0, at.z))
		for i in DIRS:
			var a := TAU * i / DIRS
			out[i] = clampi(floori(room(at, Vector3(cos(a), 0.0, sin(a)), STAND_MAX, y0, mesh) * 100.0), 0, 255)
	q.exclude = skip
	return out

