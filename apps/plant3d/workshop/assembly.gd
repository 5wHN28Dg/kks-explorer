## The Workshop's guided assembly and disassembly (docs/plant3d/WORKSHOP.md §3, §4.5, §4.6, milestone K2): the steps
## of the kind's data in their guided order, which parts are placed and which lie loose, the refusals with the data's
## two sentences, snapping, and the pile's layout. Pure: no nodes here (workshop/workshop.gd moves them), and nothing
## here knows a part kind.
##
## The model: every component and fastener group is either placed (at home relative to its parent: it rides with its
## parent wherever that stands) or loose, with a transform in the machine's own frame (so a loose part stays where it
## was put when its parent moves). The insides of a sealed component are never loose: their steps are done as soon as
## the sealed part they sit in is placed. Assembled = nothing loose.
extends RefCounted

const SNAP_FRAC := 0.02         # §4.6: within 2 % of the machine's box diagonal of home ...
const SNAP_MIN := 0.005         # ... and at least 5 mm
const SNAP_DEG := 10.0          # ... and within 10° of its home orientation, modulo its symmetry
const PILE_GAP := 0.25          # the pile's gap between two parts, in parts of the largest part's size

var mode := ""                  # "" off, "assemble", "disassemble"
var steps: Array = []           # the data's `assembly`
var loose := {}                 # id -> Transform3D in the machine's frame
var rides := {}                 # id -> true: inside a sealed component (never loose on its own)

## Starts a guided assembly or disassembly over a tree (`comps` {id: {parent, sealed}}, the data's steps); `loose_at`
## the parts that lie loose at the start, {id: Transform3D in the machine's frame} (empty for a disassembly).
func start(m: String, data_steps: Array, comps: Dictionary, loose_at: Dictionary) -> void:
	mode = m
	steps = data_steps
	rides.clear()
	for id in comps:
		var at: String = comps[id].parent
		while at != "":
			if comps[at].sealed:
				rides[id] = true
				break
			at = comps[at].parent
	loose = {}
	for id in loose_at:
		if not rides.has(id):
			loose[id] = loose_at[id]

func stop() -> void:
	mode = ""
	loose = {}

func on() -> bool:
	return mode != ""

func placed(id: String) -> bool:
	return not loose.has(id)

## The step of the guided order that comes next: assembling, the first whose part is loose; taking apart, the last
## whose part is placed (and not riding inside a sealed one). -1 when there is none (assembled, or all apart).
func next_step() -> int:
	if mode == "assemble":
		for i in steps.size():
			if loose.has(String(steps[i].place)):
				return i
	elif mode == "disassemble":
		for i in range(steps.size() - 1, -1, -1):
			var p := String(steps[i].place)
			if not loose.has(p) and not rides.has(p):
				return i
	return -1

func done() -> bool:
	return next_step() < 0

## Why placing `id` is refused now: the first unmet need's first sentence ("" when it may be placed).
func why_not_place(id: String) -> String:
	for s in steps:
		if String(s.place) == id:
			for n in s.get("needs", []):
				if loose.has(String(n[0])):
					return String(n[1])
	return ""

## Why taking `id` out is refused now: a placed part needs it, that need's second sentence ("" when it may come out).
func why_not_remove(id: String) -> String:
	for s in steps:
		var p := String(s.place)
		if loose.has(p):
			continue
		for n in s.get("needs", []):
			if String(n[0]) == id:
				return String(n[2])
	return ""

## The snapping distance for a machine's box (§4.6).
static func snap_tol(box: AABB) -> float:
	return maxf(box.size.length() * SNAP_FRAC, SNAP_MIN)

## How far (radians) a basis is turned from the home orientation `home`, modulo the component's symmetry `sym`
## ([axis, n] in the part's frame: n 0 any turn about the axis, n k every 360°/k; [] none).
static func angle_off(b: Basis, home: Basis, sym: Array) -> float:
	var r := (home.orthonormalized().inverse() * b.orthonormalized()).get_rotation_quaternion().normalized()
	if sym.size() < 2:
		return _qangle(r)
	var a: Vector3 = (sym[0] as Vector3).normalized()
	var n := int(sym[1])
	if n <= 0:
		# any turn about the axis is the same: what is left is how far the axis itself is tipped
		return acos(clampf((r * a).normalized().dot(a), -1.0, 1.0))
	var best := INF
	for j in n:
		best = minf(best, _qangle(r * Quaternion(a, -TAU * j / n)))
	return best

static func _qangle(q: Quaternion) -> float:
	return 2.0 * acos(clampf(absf(q.w), 0.0, 1.0))

## Whether a part at `cur` is near enough its place `target` (both in one frame) to snap: its centre `centre` (in its
## own frame) within `tol`, its turn within SNAP_DEG modulo `sym`.
static func near_enough(cur: Transform3D, target: Transform3D, centre: Vector3, sym: Array, tol: float) -> bool:
	if (cur * centre).distance_to(target * centre) > tol:
		return false
	return angle_off(cur.basis, target.basis, sym) <= deg_to_rad(SNAP_DEG) + 1e-6

## The pile (§3: parts laid on the floor by size, a fixed layout): `parts` [{id, box}] each with its box at home in the
## machine's frame; `machine` the machine's box. Each part keeps its home orientation and is moved so that its box
## stands on the machine's floor in rows in front of the machine (+z), largest first, row after row away from it.
## {id: Vector3}: how far each part moves from home, in the machine's frame. The same parts always give the same
## layout.
static func pile(parts: Array, machine: AABB) -> Dictionary:
	var order := parts.duplicate()
	order.sort_custom(func(p, q):
		var a: float = (p.box as AABB).size.length()
		var b: float = (q.box as AABB).size.length()
		return a > b if not is_equal_approx(a, b) else String(p.id) < String(q.id))
	var out := {}
	if order.is_empty():
		return out
	var big: float = maxf((order[0].box as AABB).size.length(), 0.01)
	var gap := big * PILE_GAP
	var row_len := maxf(machine.size.x, big) * 2.0
	var x0 := machine.get_center().x - row_len * 0.5
	var x := x0
	var z := machine.end.z + gap       # the near edge of the row being filled
	var depth := 0.0                   # the row's deepest part so far
	for p in order:
		var b: AABB = p.box
		if x > x0 and x + b.size.x > x0 + row_len:
			x = x0
			z += depth + gap
			depth = 0.0
		var slot := Vector3(x, machine.position.y, z)
		out[p.id] = slot - b.position
		x += b.size.x + gap
		depth = maxf(depth, b.size.z)
	return out
