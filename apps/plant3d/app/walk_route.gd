## Walking directions (docs/PLANT3D.md §8 `"go": "walk"`, decision 0059): the way on foot from the trainee to a piece
## of equipment, over the navigation mesh the content build baked from the walkable surfaces (builder/nav_bake.gd),
## with the stairs and ladders joined by navigation links and walked along their own paths. Drawn as chevrons a
## little above the floor, from the trainee onwards; the HUD's screen-edge arrow (ui/plant_ui.gd) still points at the
## equipment, and its distance is then the walk's.
##
## Frame cost (the Note 9's lean tier): a route is found when the target changes, and again only when the trainee has
## left it by more than OFF_ROUTE (checked every CHECK_S, at most one search per REFIND_S); the chevrons are made
## once per search, for the whole route, and walking on only moves a shader's window over them (no rebuild, no
## upload). The target's point, a search and the chevrons each take a drawn frame of their own.
extends Node3D

const NAV := "res://built/nav.res"
const CHECK_S := 0.25           # how often the trainee's place on the route is checked
const REFIND_S := 1.0           # at most one search a second
const OFF_ROUTE := 2.5          # metres from the route at which it is found again
const DRAW_STEP := 1.0          # metres walked along the route before the chevrons' window moves
const DRAW_AHEAD := 60.0        # metres of route drawn ahead of the trainee
const SPACING := 1.2            # metres between chevrons
const LIFT := 0.1               # metres above the route (the mesh lies a little above the floor; stairs are walked
                                # on slopes under the drawn steps)
const LADDER_COST := 2.0        # a ladder is climbed at half the walking speed (app/player.gd)
const STAIR_COST := 1.5         # and a stair walked a little slower than a floor
const LINK_REACH := 1.0         # builder/nav_bake.gd: a stair's or a ladder's ends are this near the mesh

var map := RID()
var region := RID()
var links := {}                 # link RID -> {kind: "stair" | "ladder", id, path: the way along it, foot first}
var error := ""
var _probe := Vector3.INF       # a vertex of the mesh: the map has taken the mesh in once a search finds it
var _ready := false

var player                      # app/player.gd
var target := Vector3.INF       # the equipment's walkable point the route leads to
var route := {}                 # find()'s result for the current target
var left := 0.0                 # metres still to walk along it, from the last check
var chevrons := 0               # how many are drawn
var stats := {"setup_us": 0, "moves": 0, "points": 0, "point_us_max": 0, "finds": 0, "find_us_max": 0, "find_us_sum": 0, "draws": 0, "draw_us_max": 0, "draw_us_sum": 0}

var _mesh: ArrayMesh
var _mi: MeshInstance3D
var _t := 0.0
var _since_find := INF
var _drawn_from := -INF         # metres along the route the chevrons are shown from
var _mat: ShaderMaterial
var _box := AABB()
var _pending := ""              # "find" or "draw" on the next physics tick


## Loads the pre-built navigation mesh into this world's navigation map and joins the ends of every stair and ladder
## with a link (builder/nav_bake.gd leaves them out of the mesh).
func setup(_plant = null) -> String:
	var t0 := Time.get_ticks_usec()
	var nm := load(NAV) as NavigationMesh if ResourceLoader.exists(NAV) else null
	if nm == null:
		error = "no navigation mesh (%s): run apps/plant3d/build.sh" % NAV
		return error
	map = get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	NavigationServer3D.map_set_link_connection_radius(map, LINK_REACH)
	region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, nm)
	_probe = nm.get_vertices()[0]
	# the stairs and the ladders, as the bake found their ways (builder/nav_bake.gd): each stair's path with the
	# floor in front of its two ends, each ladder's foot and step-off point
	for w in nm.get_meta("ways", []):
		var path: Array = Array(w.path)
		if w.kind == "ladder":
			_link("ladder", w.id, path, LADDER_COST)
		else:
			var along := 0.0
			for i in range(1, path.size()):
				along += path[i - 1].distance_to(path[i])
			_link("stair", w.id, path, STAIR_COST * along / maxf(path[0].distance_to(path[-1]), 0.1))
	_mesh = ArrayMesh.new()
	_mi = MeshInstance3D.new()
	_mi.name = "route"
	_mi.mesh = _mesh
	_mi.set_meta("ui", true)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mat = ShaderMaterial.new()
	_mat.shader = _shader()
	_mi.material_override = _mat
	add_child(_mi)
	_mi.visible = false
	stats.setup_us = Time.get_ticks_usec() - t0
	return ""


func _link(kind: String, id: String, path: Array, cost: float) -> void:
	var link := NavigationServer3D.link_create()
	NavigationServer3D.link_set_map(link, map)
	NavigationServer3D.link_set_bidirectional(link, true)
	NavigationServer3D.link_set_start_position(link, path[0])
	NavigationServer3D.link_set_end_position(link, path[-1])
	NavigationServer3D.link_set_travel_cost(link, cost)
	links[link] = {"kind": kind, "id": id, "path": path}


func _exit_tree() -> void:
	for l in links:
		NavigationServer3D.free_rid(l)
	links.clear()
	if region.is_valid():
		NavigationServer3D.free_rid(region)
		region = RID()


## True once the navigation server has taken the mesh in (it does so on a physics frame after setup).
func ready_to_find() -> bool:
	if not _ready and map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
		# this region's own mesh (an earlier one leaving the map may still be there for a tick)
		_ready = NavigationServer3D.map_get_closest_point_owner(map, _probe) == region
	return _ready


## The walkable point nearest to the equipment's bounds: where a route to it ends.
func point_for(box: AABB) -> Vector3:
	var t0 := Time.get_ticks_usec()
	var c := box.get_center()
	var best := Vector3.INF
	var bd := INF
	# its centre, the middle of its bottom and of its top, and its bottom's corners and edges (a long basin's nearest
	# floor is beside it, not on a deck above its middle)
	var lo := box.position
	var hi := box.end
	var qs := [c, Vector3(c.x, lo.y, c.z), Vector3(c.x, hi.y, c.z)]
	for x in [lo.x, c.x, hi.x]:
		for z in [lo.z, c.z, hi.z]:
			if x != c.x or z != c.z:
				qs.append(Vector3(x, lo.y, z))
	for q in qs:
		var p := NavigationServer3D.map_get_closest_point(map, q)
		var d := p.distance_to(p.clamp(box.position, box.end))
		if d < bd - 0.01:
			bd = d
			best = p
	var us := Time.get_ticks_usec() - t0
	stats.points += 1
	stats.point_us_max = maxi(stats.point_us_max, us)
	return best


## The way on foot from `from` to `to`: {points, marks, length, reached}. A stair or a ladder on the way is there as
## its own path, its points marked "stair ID" or "ladder ID" (other points ""). `reached` is false when the route
## only gets to the walkable point nearest to `to` that can be reached from `from`.
func find(from: Vector3, to: Vector3) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var q := NavigationPathQueryParameters3D.new()
	q.map = map
	q.start_position = from
	q.target_position = to
	q.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES | NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_RIDS
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	var raw := r.path
	var pts := PackedVector3Array()
	var marks := PackedStringArray()
	var i := 0
	while i < raw.size():
		var rid: RID = r.path_rids[i] if i < r.path_rids.size() else RID()
		if r.path_types[i] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK and links.has(rid):
			# the link's points (where it is entered and left): its own path instead, in the way it is gone
			var l: Dictionary = links[rid]
			var lp: Array = l.path.duplicate()
			# gone from the end nearer to where the way was before it (the start when it begins the way)
			var came: Vector3 = pts[pts.size() - 1] if not pts.is_empty() else from
			if came.distance_to(lp[-1]) < came.distance_to(lp[0]):
				lp.reverse()
			for p in lp:
				pts.append(p)
				marks.append("%s %s" % [l.kind, l.id])
			while i < raw.size() and i < r.path_rids.size() and r.path_rids[i] == rid and r.path_types[i] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
				i += 1
			continue
		pts.append(raw[i])
		marks.append("")
		i += 1
	var length := 0.0
	for k in range(1, pts.size()):
		length += pts[k - 1].distance_to(pts[k])
	var us := Time.get_ticks_usec() - t0
	stats.finds += 1
	stats.find_us_sum += us
	stats.find_us_max = maxi(stats.find_us_max, us)
	var reached := pts.size() > 0 and pts[pts.size() - 1].distance_to(NavigationServer3D.map_get_closest_point(map, to)) < 0.3
	return {"points": pts, "marks": marks, "length": length, "reached": reached, "raw": raw, "types": r.path_types}


## The route as app/autopilot.gd's steps: walk to each point (a stair along its path), climb each ladder on the way.
func steps(rt: Dictionary) -> Array:
	var out: Array = []
	var pts: PackedVector3Array = rt.points
	var i := 0
	while i < pts.size():
		var m: String = rt.marks[i]
		if m.begins_with("ladder "):
			var up: bool = i + 1 < pts.size() and pts[i + 1].y > pts[i].y
			out.append({"ladder": m.substr(7), "dir": "up" if up else "down"})
			while i < pts.size() and rt.marks[i] == m:
				i += 1
			continue
		out.append({"to": pts[i], "floor": pts[i].y})
		i += 1
	return out


# ------------------------------------------------------------------ the guide on screen

## Shows the way from the walker to the equipment with these bounds (an empty box: none).
func guide(p, box: AABB) -> void:
	player = p
	if box.size == Vector3.ZERO or map == RID():
		clear()
		return
	if box == _box and target != Vector3.INF:
		return
	_box = box
	target = Vector3.INF          # found on the next check, once the map is ready
	route = {}
	_pending = ""
	_t = CHECK_S
	if _mi:
		_mi.visible = false       # not the old target's way meanwhile


func clear() -> void:
	_box = AABB()
	target = Vector3.INF
	route = {}
	_pending = ""
	if _mi:
		_mi.visible = false


func active() -> bool:
	return _box.size != Vector3.ZERO


## A route is on screen (`left` is then the metres still to walk along it).
func shown() -> bool:
	return _mi != null and _mi.visible and not route.is_empty()


## Once per drawn frame (the lean tier draws 30 frames a second, with two physics ticks in some of them): at most
## one of the target's point, a search and a redraw in any frame.
func _process(delta: float) -> void:
	if not active() or player == null:
		return
	_t += delta
	_since_find += delta
	if _pending != "" and player.mode != player.Mode.WALK:
		_pending = ""               # took off or onto a ladder since the check: nothing to show from there
	# the work of one check is spread over the frames after it: the target's point, the search, the drawing
	if _pending == "find":
		_pending = "build"
		route = find(player.global_position, target)
		_drawn_from = -INF
		return
	if _pending == "build":
		_pending = ""
		_build()
		var pr := _progress(player.global_position)
		left = maxf(route.length - pr[1], 0.0)
		_show_from(pr[1])
		return
	if _t < CHECK_S:
		return
	_t = 0.0
	if player.mode == player.Mode.FLY:
		_mi.visible = false     # in flight there is no way on foot to show; found again on landing
		route = {}
		return
	if player.mode == player.Mode.CLIMB:
		return                  # on a ladder: the route goes on from its end
	if not ready_to_find():
		return
	if target == Vector3.INF:
		target = point_for(_box)
		_since_find = REFIND_S
		_t = CHECK_S            # searched from the next tick
		route = {}
		return
	var pr := [0, 0.0, 0.0]
	var refind := route.is_empty()
	if not refind:
		pr = _progress(player.global_position)
		refind = pr[2] > OFF_ROUTE
	if refind:
		# off the mesh (on a stair, on top of a machine): a search would start from the nearest floor, perhaps one
		# below; the way shown stays until the trainee is on a floor again
		if not route.is_empty() and NavigationServer3D.map_get_closest_point(map, player.global_position).distance_to(player.global_position) > 1.0:
			return
		if _since_find >= REFIND_S:
			_since_find = 0.0
			_pending = "find"
		return
	left = maxf(route.length - pr[1], 0.0)
	if absf(pr[1] - _drawn_from) >= DRAW_STEP:
		_show_from(pr[1])


## Where the walker is along the route: [segment index, metres along, metres off it].
func _progress(at: Vector3) -> Array:
	var pts: PackedVector3Array = route.get("points", PackedVector3Array())
	var best := [0, 0.0, INF]
	var along := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-6 else clampf((at - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		# height counts less (the walker's feet on a stair's slope, the route a little above or below it)
		var off := Vector3(at.x - q.x, (at.y - q.y) * 0.5, at.z - q.z).length()
		if off < best[2]:
			best = [i - 1, along + sqrt(l2) * t, off]
		along += sqrt(l2)
	if pts.size() == 1:
		best = [0, 0.0, Vector3(at.x - pts[0].x, 0, at.z - pts[0].z).length()]
	return best


## The chevrons along the whole route, each vertex carrying its metres along it (UV.x), made once per search: walking
## on only moves the shader's window (`_show_from`), nothing is rebuilt or uploaded again.
func _build() -> void:
	var t0 := Time.get_ticks_usec()
	var pts: PackedVector3Array = route.get("points", PackedVector3Array())
	var stop: float = route.get("length", 0.0)
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var along := 0.0
	var next := 1.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var l := a.distance_to(b)
		var flat := Vector3(b.x - a.x, 0, b.z - a.z)
		var ladder: bool = String(route.marks[i]).begins_with("ladder ") and route.marks[i] == route.marks[i - 1]
		if ladder or l <= 0.01:   # up or down a ladder: nothing drawn on its rungs, the way goes on at its other end
			next = maxf(next, along + l)
			along += l
			continue
		var f := flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
		var sd := Vector3(-f.z, 0, f.x) * 0.3
		var fu := (f + Vector3.UP * ((b.y - a.y) / maxf(flat.length(), 0.05))).normalized()   # along a stair's slope
		var tip_off := fu * 0.25
		var tail_off := fu * -0.15
		var w := fu * 0.12
		while next <= along + l and next <= stop:
			var p := a.lerp(b, (next - along) / l) + Vector3.UP * LIFT
			var tip := p + tip_off
			for tail in [p + tail_off + sd, p + tail_off - sd]:   # a chevron: two bars meeting at the point ahead
				v.append_array([tip, tail, tail - w, tip, tail - w, tip - w])
			var m := Vector2(next, 0)
			uv.append_array([m, m, m, m, m, m, m, m, m, m, m, m])
			next += SPACING
		along += l
	_mesh.clear_surfaces()
	if not v.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_TEX_UV] = uv
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var us := Time.get_ticks_usec() - t0
	stats.draws += 1
	stats.draw_us_sum += us
	stats.draw_us_max = maxi(stats.draw_us_max, us)


## Shows the chevrons from 1 m ahead of `at` (metres along the route) to DRAW_AHEAD beyond: two shader parameters.
func _show_from(at: float) -> void:
	_drawn_from = at
	_mat.set_shader_parameter("from", at + 1.0)
	_mat.set_shader_parameter("to", at + 1.0 + DRAW_AHEAD)
	var length: float = route.get("length", 0.0)
	chevrons = int(maxf(minf(DRAW_AHEAD, length - at - 1.0), 0.0) / SPACING)
	_mi.visible = chevrons > 0
	stats.moves += 1


## Unshaded orange, a little see-through; chevrons outside the window collapse to a point in the vertex stage.
static func _shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float from = 0.0;
uniform float to = 1e9;
void vertex() {
	if (UV.x < from || UV.x > to) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	ALBEDO = vec3(1.0, 0.318, 0.01);   // the arrows' orange (1, 0.6, 0.1) in linear light
	ALPHA = 0.85;
}
"""
	return sh
