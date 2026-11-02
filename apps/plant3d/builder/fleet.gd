## The staff's vehicles in the built plant (docs/PLANT3D.md §21.7; view only, nothing of it is in the vectors): which
## parked kit `vehicle` of the site each of staff.json's vehicles is, and the road each of its drive ways is driven
## along. The build draws a claimed vehicle as a piece of its own (builder/kit_place.gd), not merged into its cell, so
## that the app can move it (app/vehicles.gd); the roads go into the manifest (plant.json `vehicles`).
##
## A vehicle takes the parked kit `vehicle` of its kind nearest to its home place, the first in the content's order
## on a tie, one vehicle each. A drive way's road is searched on the asphalt roads (the walkable surfaces of kind
## `road` whose surface is asphalt) on a ROAD_CELL grid, keeping to the middle of the road (a cell near the road's edge
## costs more), from the road cell nearest to the way's first place to the one nearest to its last, then pulled
## straight where the asphalt allows: the road's middle line in plan, from the first place to the last (a way from the
## vehicle's home begins and a way to it ends at where the vehicle is parked). The app drives on the right of it.
extends RefCounted

const ROAD_CELL := 1.0          # m: the road search's grid
const MARGIN := 30.0            # m round the drive ways' places the grid covers
const EDGE := 4                 # cells from the road's edge within which a cell costs more (the middle is kept)
const EDGE_COST := 3.0          # the extra cost of a cell at the edge, falling to 0 at EDGE cells in
const JOIN_EDGE := 4.0          # m farther a joining cell counts per unit of its edge cost (Grid.nearest)


## {structure id: vehicle id} for the vehicles of `staff` (staff.json's dictionary) among `structures` (the kit
## structures as the build collected them: [{s, area}]).
static func claim(staff: Dictionary, structures: Array) -> Dictionary:
	var out := {}
	var at := _places(staff)
	for v in staff.get("vehicles", []):
		if not at.has(v.get("home", "")):
			continue
		var home: Vector2 = at[v["home"]]
		var best := ""
		var best_d := INF
		for ks in structures:
			var s: Dictionary = ks.s
			if s.part != "vehicle" or out.has(s.id) or String(s.get("params", {}).get("kind", "")) != String(v.get("kind", "")):
				continue
			var d := home.distance_to(Vector2(float(s.at[0]), float(s.at[1])))
			if d < best_d - 1e-6:
				best_d = d
				best = s.id
		if best != "":
			out[best] = String(v["id"])
	return out


## The manifest's vehicles: [{id, structure, area, at (Godot), yaw (degrees, the content's), roads: {"A|B": [plan
## points [x, y]…]}}], a road for each drive way of staff.json the vehicles drive (both directions use one line).
static func manifest(staff: Dictionary, structures: Array, claimed: Dictionary, surfaces: Array) -> Array:
	var at := _places(staff)
	var out: Array = []
	var by_vehicle := {}
	for sid in claimed:
		by_vehicle[claimed[sid]] = sid
	var drive: Array = []
	for w in staff.get("ways", []):
		if w.size() > 3 and w[3] == "drive" and at.has(w[0]) and at.has(w[1]):
			drive.append(w)
	var grid := Grid.new()
	grid.make(surfaces, drive.map(func(w): return at[w[0]]) + drive.map(func(w): return at[w[1]]))
	for v in staff.get("vehicles", []):
		var vid := String(v["id"])
		if not by_vehicle.has(vid):
			continue
		var s: Dictionary = {}
		var area := ""
		for ks in structures:
			if ks.s.id == by_vehicle[vid]:
				s = ks.s
				area = ks.area
		var parked := Vector2(float(s.at[0]), float(s.at[1]))
		var roads := {}
		for w in drive:
			var a: Vector2 = parked if w[0] == v.get("home") else at[w[0]]
			var b: Vector2 = parked if w[1] == v.get("home") else at[w[1]]
			var line := grid.road(a, b, w[0] == v.get("home"), w[1] == v.get("home"))
			roads["%s|%s" % [w[0], w[1]]] = line.map(func(p): return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		out.append({"id": vid, "structure": s.id, "area": area, "at": [float(s.at[0]), float(s.at[1]),
				float(s.at[2]) if s.at.size() > 2 else 0.0], "yaw": float(s.get("yaw", 0)), "roads": roads})
	return out


static func _places(staff: Dictionary) -> Dictionary:
	var at := {}
	for p in staff.get("places", []):
		at[p["id"]] = Vector2(float(p["at"][0]), float(p["at"][1]))
	return at


## The asphalt on a grid round the drive ways' places, and the search on it.
class Grid:
	var origin := Vector2.ZERO
	var w := 0
	var h := 0
	var asphalt := PackedByteArray()    # per cell: asphalt
	var edge := PackedFloat32Array()    # per cell: the extra cost of being near the edge

	func make(surfaces: Array, points: Array) -> void:
		if points.is_empty():
			return
		var lo: Vector2 = points[0]
		var hi: Vector2 = points[0]
		for p in points:
			lo = lo.min(p)
			hi = hi.max(p)
		origin = (lo - Vector2.ONE * MARGIN).floor()
		w = int(ceil((hi.x - origin.x + MARGIN) / ROAD_CELL)) + 1
		h = int(ceil((hi.y - origin.y + MARGIN) / ROAD_CELL)) + 1
		asphalt.resize(w * h)
		asphalt.fill(0)
		for sf in surfaces:
			if sf.kind != "road" or String(sf.get("surface", "")) not in ["asphalt", ""]:
				continue
			var pg: PackedVector2Array = sf.outline
			var r := Rect2(pg[0], Vector2.ZERO)
			for q in pg:
				r = r.expand(q)
			var i0 := maxi(0, int(floor((r.position.x - origin.x) / ROAD_CELL)))
			var i1 := mini(w - 1, int(ceil((r.end.x - origin.x) / ROAD_CELL)))
			var j0 := maxi(0, int(floor((r.position.y - origin.y) / ROAD_CELL)))
			var j1 := mini(h - 1, int(ceil((r.end.y - origin.y) / ROAD_CELL)))
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					if Geometry2D.is_point_in_polygon(centre(i, j), pg):
						asphalt[j * w + i] = 1
		# the distance to the nearest cell off the road, in cells (city blocks), up to EDGE
		edge.resize(w * h)
		var dist := PackedInt32Array()
		dist.resize(w * h)
		for k in w * h:
			dist[k] = 0 if asphalt[k] == 0 else EDGE
		for pass_ in EDGE:
			for j in h:
				for i in w:
					var k := j * w + i
					if asphalt[k] == 0:
						continue
					var m := EDGE
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var ii := i + d.x
						var jj := j + d.y
						var n := 0 if ii < 0 or jj < 0 or ii >= w or jj >= h else dist[jj * w + ii]
						m = mini(m, n + 1)
					dist[k] = mini(dist[k], m)
		for k in w * h:
			edge[k] = EDGE_COST * float(EDGE - dist[k]) / float(EDGE) if asphalt[k] == 1 else 0.0

	func centre(i: int, j: int) -> Vector2:
		return origin + Vector2(i + 0.5, j + 0.5) * ROAD_CELL

	func _cell_of(p: Vector2) -> Vector2i:
		return Vector2i(int(floor((p.x - origin.x) / ROAD_CELL)), int(floor((p.y - origin.y) / ROAD_CELL)))

	## The road cell where a way from or to p joins the road: the nearest, a cell near the road's edge counting
	## JOIN_EDGE metres farther for each unit of its edge cost (a stop beside the road joins it at its middle, not at
	## its kerb); (-1, -1) for none.
	func nearest(p: Vector2) -> Vector2i:
		var best := Vector2i(-1, -1)
		var bd := INF
		for j in h:
			for i in w:
				var k := j * w + i
				if asphalt[k] == 1:
					var d := centre(i, j).distance_to(p) + JOIN_EDGE * edge[k]
					if d < bd:
						bd = d
						best = Vector2i(i, j)
		return best

	## The road's middle line from the road nearest to a to the road nearest to b in plan, beginning at a itself when
	## `from_a` (the parked place) and ending at b when `to_b`; [a, b] when no road joins them.
	func road(a: Vector2, b: Vector2, from_a := false, to_b := false) -> Array:
		var s := nearest(a)
		var t := nearest(b)
		if s.x < 0 or t.x < 0:
			return [a, b]
		var cells := _search(s, t)
		if cells.is_empty():
			return [a, b]
		var pts: Array = [a, centre(s.x, s.y)] if from_a else [centre(s.x, s.y)]
		var k := 0
		# pulled straight: from each kept cell, the farthest later cell in plain sight over the asphalt's middle
		while k < cells.size() - 1:
			var far := k + 1
			for m in range(cells.size() - 1, k + 1, -1):
				if _clear(cells[k], cells[m]):
					far = m
					break
			pts.append(centre(cells[far].x, cells[far].y))
			k = far
		if to_b:
			pts.append(b)
		# points closer than a metre to the one kept before are dropped (the first and the last kept)
		var last: Vector2 = pts[-1]
		var out: Array = [pts[0]]
		for i in range(1, pts.size() - 1):
			if (pts[i] as Vector2).distance_to(out[-1]) >= 1.0:
				out.append(pts[i])
		if out.size() > 1 and (out[-1] as Vector2).distance_to(last) < 1.0:
			out.remove_at(out.size() - 1)
		out.append(last)
		return out

	## A* over the road cells (8 neighbours), each cell's cost its step plus its edge cost.
	func _search(s: Vector2i, t: Vector2i) -> Array:
		var n := w * h
		var g := PackedFloat32Array()
		g.resize(n)
		g.fill(INF)
		var from := PackedInt32Array()
		from.resize(n)
		from.fill(-1)
		var closed := PackedByteArray()
		closed.resize(n)
		var open: Array = [[0.0, s.y * w + s.x]]
		g[s.y * w + s.x] = 0.0
		var goal := t.y * w + t.x
		while not open.is_empty():
			var bi := 0
			for q in open.size():
				if open[q][0] < open[bi][0]:
					bi = q
			var cur: int = open[bi][1]
			open.remove_at(bi)
			if closed[cur] == 1:
				continue
			closed[cur] = 1
			if cur == goal:
				break
			var ci := cur % w
			var cj := cur / w
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					if di == 0 and dj == 0:
						continue
					var ii: int = ci + di
					var jj: int = cj + dj
					if ii < 0 or jj < 0 or ii >= w or jj >= h:
						continue
					var k := jj * w + ii
					if asphalt[k] == 0 or closed[k] == 1:
						continue
					var c: float = g[cur] + (1.4142 if di != 0 and dj != 0 else 1.0) + edge[k]
					if c < g[k]:
						g[k] = c
						from[k] = cur
						open.append([c + Vector2(ii - t.x, jj - t.y).length(), k])
		if from[goal] == -1 and goal != s.y * w + s.x:
			return []
		var cells: Array = []
		var k := goal
		while k != -1:
			cells.push_front(Vector2i(k % w, k / w))
			k = from[k]
		return cells

	## Every cell along the straight line between two cells' centres is asphalt and away from the road's edge (kept to
	## the middle).
	func _clear(a: Vector2i, b: Vector2i) -> bool:
		var pa := centre(a.x, a.y)
		var pb := centre(b.x, b.y)
		var n := int(ceil(pa.distance_to(pb) / (ROAD_CELL * 0.5))) + 1
		for i in n + 1:
			var c := _cell_of(pa.lerp(pb, float(i) / n))
			if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
				return false
			var k := c.y * w + c.x
			if asphalt[k] == 0 or edge[k] > maxf(edge[a.y * w + a.x], edge[b.y * w + b.x]) + 1e-3:
				return false
		return true
