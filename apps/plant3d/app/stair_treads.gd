## Where people's feet go on the plant's stairs and ladders (docs/PLANT3D.md §18.1 as built, phase 4), from the built
## manifest's flights and ladders (builder/plant_builder.gd). A person on a flight is walked along the slope a walker
## climbs (through the treads' nosings, up to a riser above the back of a tread); app/people.gd draws them on the line
## through the treads' middles instead (half a riser lower: their standing foot on its tread) and plays the stairs'
## clip locked to where they are along the flight, a step a tread (builder/people/rig.gd stair_clip()), from half a
## going before its first riser to half one past its last (where that line meets the landings; standing still, on the
## tread under them); on a ladder the climbing clip is locked to their height over its foot, two rungs a cycle
## (climb_clip()), facing its rungs.
## Found by a grid of CELL metres: only the people on a flight or a ladder look (`on`), and then only its cell's.
extends RefCounted

const CELL := 4.0
const SIDE := 0.3               # metres beyond a flight's sides, and its ends, that count as on it (lanes, the ramp)
const NEAR_Y := 0.6             # metres off the slope's height that still count as on a flight (one above another)

## per flight: [a (plan, Godot x and z), dir (plan, unit), across (plan, unit), run, going, rise, y0, steps, half width]
var flights: Array = []
## per ladder: [plan (x, z), foot height, top height, the climber's heading (Godot's yaw: towards the rungs)]
var ladders: Array = []
var _cells := {}                # Vector2i -> flights' indices
var _ladder_cells := {}

# on_flight()'s answer
var t := 0.0                    # metres along the flight from its first nosing (plan)
var going := 0.0
var rise := 0.0
var dir := Vector2.ZERO         # the flight's way up (plan)


## The plant's (`manifest`: app/plant.gd's), or null when it has no stairs or ladders with their flights.
static func of(manifest: Dictionary):
	var out = new()
	for s in manifest.get("stairs", []):
		for fl in s.get("flights", []):
			var a := Vector3(fl.a[0], fl.a[1], fl.a[2])
			var b := Vector3(fl.b[0], fl.b[1], fl.b[2])
			var k := int(fl.steps)
			var p := Vector2(b.x - a.x, b.z - a.z)
			var run := p.length()
			if k < 1 or run < 1e-3:
				continue
			var d := p / run
			var g := run / maxf(1.0, k - 1)    # (builder/plant_builder.gd _stair: k - 1 treads between the landings)
			out._add_flight([Vector2(a.x, a.z), d, Vector2(-d.y, d.x), run, g, (b.y - a.y) / k, a.y, k, float(fl.width) * 0.5])
	for l in manifest.get("ladders", []):
		var f: Array = l.foot
		var fr := deg_to_rad(float(l.get("facing", 0.0)))
		out._add_ladder([Vector2(f[0], f[2]), float(f[1]), float(l.top), atan2(-sin(fr), cos(fr))])
	return out if not (out.flights.is_empty() and out.ladders.is_empty()) else null


func _add_flight(fl: Array) -> void:
	var k := flights.size()
	flights.append(fl)
	var a: Vector2 = fl[0]
	var d: Vector2 = fl[1]
	var lo: Vector2 = a - d * (float(fl[4]) + SIDE)
	var hi: Vector2 = a + d * (float(fl[3]) + SIDE)
	var r: float = fl[8] + SIDE
	var mn := Vector2(minf(lo.x, hi.x), minf(lo.y, hi.y)) - Vector2(r, r)
	var mx := Vector2(maxf(lo.x, hi.x), maxf(lo.y, hi.y)) + Vector2(r, r)
	_index(_cells, mn, mx, k)


func _add_ladder(l: Array) -> void:
	var k := ladders.size()
	ladders.append(l)
	_index(_ladder_cells, l[0] - Vector2(1, 1), l[0] + Vector2(1, 1), k)


static func _index(cells: Dictionary, mn: Vector2, mx: Vector2, k: int) -> void:
	for x in range(floori(mn.x / CELL), floori(mx.x / CELL) + 1):
		for z in range(floori(mn.y / CELL), floori(mx.y / CELL) + 1):
			var key := Vector2i(x, z)
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(k)


## The flight `p` (the feet, on the slope a walker climbs) is on, or -1; sets t, going, rise and dir.
func on_flight(p: Vector3) -> int:
	var list = _cells.get(Vector2i(floori(p.x / CELL), floori(p.z / CELL)))
	if list == null:
		return -1
	var best := -1
	var best_dy := NEAR_Y
	var q := Vector2(p.x, p.z)
	for k in list:
		var fl: Array = flights[k]
		var o: Vector2 = q - fl[0]
		var tt: float = o.dot(fl[1])
		var g: float = fl[4]
		if tt < -g - SIDE or tt > fl[3] + SIDE or absf(o.dot(fl[2])) > fl[8] + SIDE:
			continue
		var dy := absf(p.y - slope(fl, tt))
		if dy < best_dy:
			best_dy = dy
			best = k
			t = tt
	if best >= 0:
		going = flights[best][4]
		rise = flights[best][5]
		dir = flights[best][1]
	return best


## The slope a walker climbs on flight `fl` at `tt` along it: from one going before its first riser (on the landing)
## to its last riser's top, through the nosings (builder/plant_builder.gd _stair).
static func slope(fl: Array, tt: float) -> float:
	var g: float = fl[4]
	var top: float = fl[6] + fl[5] * fl[7]
	return clampf(fl[6] + (tt + g) * fl[5] / g, fl[6], top)


## The line through the middles of flight `k`'s treads at `tt` (on_flight()'s t): half a riser under the slope, on
## the landings at either end.
func mid(k: int, tt: float) -> float:
	var fl: Array = flights[k]
	var g: float = fl[4]
	return clampf(fl[6] + (tt / g + 0.5) * fl[5], fl[6], fl[6] + fl[5] * fl[7])


## Whether `tt` along flight `k` is where its treads' line runs between the landings' levels (the stairs' clip there).
func on_treads(k: int, tt: float) -> bool:
	var fl: Array = flights[k]
	return tt >= -0.5 * float(fl[4]) and tt <= float(fl[3]) + 0.5 * float(fl[4])


## The top of the tread under `tt` on flight `k` (the landings beyond its ends).
func tread(k: int, tt: float) -> float:
	var fl: Array = flights[k]
	var g: float = fl[4]
	if tt < 0.0:
		return fl[6]
	return fl[6] + fl[5] * mini(int(floor(tt / g)) + 1, int(fl[7]))


## The ladder `p` is on (within 0.6 m of its foot in plan, between its foot and 2 m over its top), or -1.
func on_ladder(p: Vector3) -> int:
	var list = _ladder_cells.get(Vector2i(floori(p.x / CELL), floori(p.z / CELL)))
	if list == null:
		return -1
	var q := Vector2(p.x, p.z)
	for k in list:
		var l: Array = ladders[k]
		if q.distance_to(l[0]) <= 0.6 and p.y >= l[1] - 0.2 and p.y <= l[2] + 2.0:
			return k
	return -1
