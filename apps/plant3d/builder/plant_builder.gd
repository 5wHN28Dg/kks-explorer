## The content build (decision 0054 §4): data/plant3d (already checked by ref/plant3d.py) to one pre-built scene per
## area, the ground, the materials and a manifest the app loads. Nothing here runs when the app starts.
##
## Equipment and pipes are made by the parts kit (apps/plant3d/kit, placed by builder/kit_place.gd); platforms,
## floors, stairs, ladders, doors, buildings, pits, slabs, fences and the pipe rack are made here, as solid
## geometry at their described positions, so a trainee walks where the description says.
##
## The build refuses what it can't draw (docs/PLANT3D.md §12): errors name the file, the item and the rule.
extends RefCounted

const Geom = preload("res://builder/geom.gd")
const KitPlace = preload("res://builder/kit_place.gd")
const Mat = preload("res://kit/materials.gd")
const Kit = preload("res://kit/kit.gd")
const Lightmap = preload("res://builder/lightmap.gd")
const Lighting = preload("res://app/lighting.gd")
const SkyBuild = preload("res://builder/sky.gd")
const Weather = preload("res://builder/weather.gd")
const Site = preload("res://builder/site.gd")
const SKY_SRC := "res://kit/tex/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"

const SURFACE_PARTS := ["platform", "floor", "grating", "road"]
const TOL := 0.05
const RAIL_H := 1.1
const LADDER_SPACE := 0.4      # the climber steps off this far ahead of the ladder's foot (§5)
const DECK := {"grating": 0.1, "concrete": 0.3, "steel": 0.05}
## Structure parts with geometry in this build; any other structure part is refused (unsupported).
const STRUCTURES := ["building", "floor", "platform", "grating", "road", "stair", "ladder", "door", "pit", "slab",
	"fence", "pipe_rack"]

var errors := PackedStringArray()
var warnings := PackedStringArray()
var kit: Dictionary
var plant: Dictionary
var areas: Array = []            # [{id, rel, data}]
var equipment := {}              # kks -> {pos: plant Vector3, yaw, part, params, area}
var surfaces: Array = []         # walkable: {id, kind, z, outline, holes, thick, rails, deck, area}
var stairs: Array = []           # {id, area, foot, top, layout, width, st, lay}
var ladders: Array = []          # {id, area, foot, top, facing, exit}
var buildings: Array = []        # {id, area, outline, height, openings, at}
var pits: Array = []             # {id, area, outline, depth}
var rack_tiers: Array = []       # pipe racks' tiers, where pipes rest: {outline, z}
var kp                           # the parts kit's placement (builder/kit_place.gd)
var mats := {}
var inputs := PackedStringArray()   # every file read, for the manifest's content hash

# ------------------------------------------------------------------ reading

func _err(code: String, where: String, msg: String) -> void:
	errors.append("%s %s: %s" % [code, where, msg])

func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_err("missing_file", path, "cannot read (%d)" % FileAccess.get_open_error())
		return null
	var text := f.get_as_text()
	inputs.append(path.get_file() + ":" + text.sha256_text())
	var v = JSON.parse_string(text)
	if v == null:
		_err("bad_json", path, "not JSON")
	return v

## Reads plant.json, kit.json and the areas in plant.json's order.
func read(data_dir: String) -> bool:
	Kit.clear_cache()
	var p = _read_json(data_dir.path_join("plant.json"))
	var k = _read_json(data_dir.path_join("kit.json"))
	if not (p is Dictionary and k is Dictionary):
		_err("bad_json", data_dir, "plant.json and kit.json must be objects")
		return false
	plant = p
	kit = k
	Kit.use_kit(kit)   # the parts kit reads the same kit.json as the build
	for aid in plant.areas:
		var rel := "areas/%s.json" % aid
		var a = _read_json(data_dir.path_join(rel))
		if a != null:
			areas.append({"id": aid, "rel": rel, "data": a})
	return errors.is_empty()

## The same from dictionaries (the tests' synthetic plants).
func use(plant_d: Dictionary, kit_d: Dictionary, area_list: Array) -> void:
	plant = plant_d
	kit = kit_d
	Kit.clear_cache()
	Kit.use_kit(kit)
	for a in area_list:
		areas.append({"id": a.id, "rel": "areas/%s.json" % a.id, "data": a})

func params_of(part: String, given) -> Dictionary:
	var out := {}
	var spec: Dictionary = kit.parts.get(part, {}).get("params", {})
	for k in spec:
		if spec[k].has("default"):
			out[k] = spec[k].default
	if given is Dictionary:
		for k in given:
			out[k] = given[k]
	return out

func _v3(p) -> Vector3:
	return Vector3(float(p[0]), float(p[1]), float(p[2]) if p.size() > 2 else 0.0)

# ------------------------------------------------------------------ collecting and checking

func collect() -> bool:
	for a in areas:
		var d: Dictionary = a.data
		for e in d.get("equipment", []):
			var pr := params_of(e.part, e.get("params", {}))
			var pos := _v3(e.at)
			var yaw := float(e.get("yaw", 0))
			equipment[e.kks] = {"pos": pos, "yaw": yaw, "part": e.part, "params": pr, "area": a.id, "name": e.get("name", ""),
				"plate": e.get("plate", "none")}
			for c in e.get("parts", []):
				var cp := params_of(c.part, c.get("params", {}))
				equipment[c.kks] = {"pos": pos + Geom.turn(_v3(c.at), yaw), "yaw": yaw + float(c.get("yaw", 0)),
					"part": c.part, "params": cp, "area": a.id, "name": c.get("name", ""), "child": true,
					"parent": e.kks, "at": _v3(c.at), "own_yaw": float(c.get("yaw", 0)), "plate": c.get("plate", "none")}
		for s in d.get("structures", []):
			_collect_structure(s, a)
	if not errors.is_empty():
		return false
	_cut_access()
	_check()
	kp = KitPlace.new(self)
	kp.prepare()
	return errors.is_empty()

func _collect_structure(s: Dictionary, a: Dictionary) -> void:
	var part: String = s.part
	var where := "%s: %s" % [a.rel, s.id]
	if not part in STRUCTURES:
		_err("unsupported", where, "the build has no geometry for structure part '%s' yet" % part)
		return
	var pr := params_of(part, s.get("params", {}))
	var at := _v3(s.get("at", [0, 0, 0]))
	var yaw := float(s.get("yaw", 0))
	var off := Vector2(at.x, at.y)
	if part in SURFACE_PARTS:
		var holes: Array = []
		for o in pr.get("openings", []):
			holes.append(Geom.poly(o, off, yaw))
		var deck: String = pr.get("deck", "concrete" if part != "grating" else "grating")
		var rails: bool = part == "floor" or (part == "platform" and pr.get("edge", "handrail") == "handrail")
		surfaces.append({"id": s.id, "kind": part, "z": at.z, "outline": Geom.poly(pr.outline, off, yaw), "holes": holes,
			"thick": DECK.get(deck, 0.2), "rails": rails, "deck": deck, "area": a.id})
	elif part == "stair":
		var foot := _v3(pr.foot)
		var top := _v3(pr.top)
		var st := Geom.stair_steps(foot, top, pr.layout, float(pr.width))
		if st.is_empty():
			_err("bad_stair", where, "no step count keeps the stair rules (§5)")
			return
		var lay := Geom.stair_layout(foot, top, pr.layout, float(pr.width), st)
		stairs.append({"id": s.id, "area": a.id, "foot": foot, "top": top, "layout": pr.layout,
			"width": float(pr.width), "st": st, "lay": lay})
	elif part == "ladder":
		var foot := _v3(pr.foot)
		var hd := Geom.heading(float(pr.facing))
		var ex := Vector3(foot.x + hd.x * LADDER_SPACE, foot.y + hd.y * LADDER_SPACE, float(pr.top))
		ladders.append({"id": s.id, "area": a.id, "foot": foot, "top": float(pr.top), "facing": float(pr.facing), "exit": ex})
	elif part == "building":
		buildings.append({"id": s.id, "area": a.id, "outline": Geom.poly(pr.outline, off, yaw), "height": float(pr.height),
			"openings": pr.get("openings", []), "at": at, "yaw": yaw, "cladding": pr.get("cladding", "metal"),
			"rel": a.rel})
	elif part == "pit":
		var pg := Geom.poly(pr.outline, off, yaw)
		pits.append({"id": s.id, "area": a.id, "outline": pg, "depth": float(pr.depth)})
		surfaces.append({"id": s.id + "_floor", "kind": "pit_floor", "z": -float(pr.depth), "outline": pg, "holes": [],
			"thick": 0.3, "rails": false, "deck": "concrete", "area": a.id})
	elif part == "pipe_rack":
		var fw := Geom.heading(yaw)
		var right := Vector2(fw.y, -fw.x)
		var c := Vector2(at.x, at.y)
		var L := float(pr.length) * 0.5
		var W := float(pr.width) * 0.5
		var rect := PackedVector2Array([c - fw * L - right * W, c + fw * L - right * W, c + fw * L + right * W, c - fw * L + right * W])
		for k in int(pr.tiers):
			rack_tiers.append({"outline": rect, "z": at.z + float(pr.height) - 2.0 * (int(pr.tiers) - 1 - k)})

## Stairwells and ladder hatches: a walkable surface a stair or a ladder passes through gets an opening, except
## where the stair's own landing at that height joins it (the kit applies this, content doesn't repeat it: §5).
func _cut_access() -> void:
	for s in stairs:
		var lay: Dictionary = s.lay
		for sf in surfaces:
			var z: float = sf.z
			if z <= s.foot.z + TOL or z > s.top.z + TOL:
				continue
			if Geometry2D.intersect_polygons(lay.rect, sf.outline).is_empty():
				continue
			var same_keys := {}
			for l in lay.landings:
				if absf(l.z - z) <= TOL:
					same_keys[_key(l.poly)] = true
			for fl in lay.flights:
				sf.holes.append(Geom._strip(fl.a, fl.b, fl.side, fl.width))
			for l in lay.landings:
				if absf(l.z - z) > TOL and not same_keys.has(_key(l.poly)):
					sf.holes.append(l.poly)
	for l in ladders:
		var hd := Geom.heading(l.facing)
		var across := Vector2(hd.y, -hd.x)
		var c := Vector2(l.foot.x, l.foot.y)
		var hatch := PackedVector2Array([c - hd * 0.45 - across * 0.4, c + hd * 0.2 - across * 0.4,
			c + hd * 0.2 + across * 0.4, c - hd * 0.45 + across * 0.4])
		for sf in surfaces:
			if sf.z > l.foot.z + TOL and sf.z <= l.top + TOL and Geom.in_poly(c, sf.outline):
				sf.holes.append(hatch)

func _key(pg: PackedVector2Array) -> String:
	var c := Vector2.ZERO
	for p in pg: c += p
	c /= pg.size()
	return "%.2f,%.2f" % [c.x, c.y]

## Is there walkable ground at plan point p and height z? Surfaces (less their openings), stair landings and the
## ends of flights, and the ground at z = 0 outside pits and stairwells. `skip` leaves one surface out.
func walkable_at(p: Vector2, z: float, skip := "") -> bool:
	for sf in surfaces:
		if sf.id != skip and absf(sf.z - z) <= TOL and Geom.in_region(p, sf.outline, sf.holes):
			return true
	for s in stairs:
		for l in s.lay.landings:
			if absf(l.z - z) <= TOL and Geom.in_poly(p, l.poly):
				return true
		for fl in s.lay.flights:
			if (absf(fl.z0 - z) <= TOL or absf(fl.z1 - z) <= TOL) and Geom.in_poly(p, Geom._strip(fl.a, fl.b, fl.side, fl.width)):
				return true
	if absf(z) <= TOL and skip != "ground":
		return ground_at(p)
	return false

func ground_at(p: Vector2) -> bool:
	for pt in pits:
		if Geom.in_poly(p, pt.outline):
			return false
	for h in ground_cuts():
		if Geom.in_poly(p, h):
			return false
	return true

## Stairwells through the ground (a stair from a pit or basement up to z = 0 or above).
func ground_cuts() -> Array:
	var out: Array = []
	for s in stairs:
		if s.foot.z < -TOL and s.top.z >= -TOL:
			for fl in s.lay.flights:
				if fl.z0 < -TOL:
					out.append(Geom._strip(fl.a, fl.b, fl.side, fl.width))
	return out

func _check() -> void:
	# a door in a building's wall stands in a door opening of that wall (else it would open onto the wall)
	for a in areas:
		for s in a.data.get("structures", []):
			if s.part != "door":
				continue
			var at := _v3(s.at)
			var p := Vector2(at.x, at.y)
			var pr := params_of("door", s.get("params", {}))
			for b in buildings:
				var e := _wall_edge(b, p, 0.3)
				if e.is_empty():
					continue
				var ok := false
				for o in b.openings:
					if o.kind != "door":
						continue
					var oc := _opening_plan(b, o)
					if oc.distance_to(p) <= 0.3 and float(o.width) >= float(pr.width) - 0.01:
						ok = true
				if not ok:
					_err("unsupported", "%s: %s" % [a.rel, s.id], "the door at %s is in the wall of %s, which has no door opening there (its openings' `at` are relative to the building)" % [str(s.at), b.id])
	for b in buildings:
		for o in b.openings:
			var oc := _opening_plan(b, o)
			if float(o.at[2]) < b.height - 0.5 and _wall_edge(b, oc, 0.05).is_empty():
				_err("unsupported", "%s: %s" % [b.rel, b.id], "the %s opening at %s is on no wall of the outline" % [o.kind, str(o.at)])
	# a pipe goes through a building's wall only where the wall has an opening
	for a in areas:
		for p in a.data.get("pipes", []):
			var route: Array = [_end_point(p.from)]
			for q in p.get("points", []):
				route.append(_v3(q))
			route.append(_end_point(p.to))
			if Vector3.INF in route:
				_err("bad_ref", "%s: %s" % [a.rel, p.kks], "a pipe end names a nozzle the kit doesn't have")
				continue
			for i in range(route.size() - 1):
				var ra: Vector3 = route[i]
				var rb: Vector3 = route[i + 1]
				for b in buildings:
					var hole := _wall_crossing(b, ra, rb)
					if not hole.is_empty():
						_err("unsupported", "%s: %s" % [a.rel, p.kks], "the pipe passes the wall of %s at %s, where the wall has no opening" % [b.id, str(hole)])
				var r := ((float(p.od_mm) if p.has("od_mm") else _od(int(p.dn))) / 1000.0) * 0.5 + float(p.get("insulation_mm", 0)) / 1000.0
				for st in stairs:
					var hit := _stair_clash(st, ra, rb, r)
					if not hit.is_empty():
						_err("unsupported", "%s: %s" % [a.rel, p.kks], "the pipe passes through the walking space of %s at %s" % [st.id, str(hit)])
	# every stair and ladder end meets ground a walker can stand on (ref/plant3d.py checks the description; this
	# checks the drawn result, after stairwells and hatches were cut)
	for s in stairs:
		# an even number of switchback flights starts at the far end: the walker goes there under the first landing
		# and the second flight, which must leave room to stand
		if s.layout == "switchback" and s.st.flights % 2 == 0 and (s.top.z - s.foot.z) / s.st.flights - 0.25 < HEADROOM:
			_err("not_walkable", s.id, "%d flights of %.2f m leave no headroom on the way to the first flight" % [s.st.flights, (s.top.z - s.foot.z) / s.st.flights])
		var path: Array = s.lay.path
		var foot: Vector3 = path[0]
		var top: Vector3 = path[-1]
		if not walkable_at(Vector2(foot.x, foot.y), foot.z):
			_err("not_walkable", s.id, "the foot %s meets no walkable surface in the built plant" % str(foot))
		var beyond_ok := false
		for i in 16:
			var q := Vector2(top.x, top.y) + Vector2.from_angle(TAU * i / 8.0) * (0.3 if i < 8 else 0.5)
			if walkable_at(q, top.z) and not Geom.in_poly(q, s.lay.rect):
				beyond_ok = true
		if not beyond_ok:
			_err("not_walkable", s.id, "nothing walkable beyond the top %s" % str(top))
	for l in ladders:
		if not walkable_at(Vector2(l.foot.x, l.foot.y), l.foot.z):
			_err("not_walkable", l.id, "the foot %s meets no walkable surface in the built plant" % str(l.foot))
		if not walkable_at(Vector2(l.exit.x, l.exit.y), l.exit.z):
			_err("not_walkable", l.id, "stepping off at %s meets no walkable surface in the built plant" % str(l.exit))

const HEADROOM := 2.1

## Where a pipe (segment ra-rb, radius r) passes through a stair's walking space (its flights and landings, from just
## under them to HEADROOM above): the point, or [].
func _stair_clash(s: Dictionary, ra: Vector3, rb: Vector3, r: float) -> Array:
	var rect: Rect2 = Rect2(s.lay.rect[0], Vector2.ZERO)
	for q in s.lay.rect:
		rect = rect.expand(q)
	rect = rect.grow(r)
	var seg := Rect2(Vector2(ra.x, ra.y), Vector2.ZERO).expand(Vector2(rb.x, rb.y))
	if not rect.intersects(seg, true) or maxf(ra.z, rb.z) + r < s.foot.z - 0.3 or minf(ra.z, rb.z) - r > s.top.z + HEADROOM:
		return []
	var n := int(ceil(ra.distance_to(rb) / 0.2)) + 1
	for k in n + 1:
		var q := ra.lerp(rb, float(k) / n)
		var q2 := Vector2(q.x, q.y)
		for fl in s.lay.flights:
			var strip := Geom._strip(fl.a, fl.b, fl.side, fl.width)
			if _near_poly(q2, strip, r):
				var t := clampf((q2 - fl.a).dot(fl.b - fl.a) / maxf((fl.b - fl.a).length_squared(), 1e-9), 0.0, 1.0)
				var zf: float = lerpf(fl.z0, fl.z1, t)
				if q.z - r < zf + HEADROOM and q.z + r > zf - 0.3:
					return [snappedf(q.x, 0.01), snappedf(q.y, 0.01), snappedf(q.z, 0.01)]
		for l in s.lay.landings:
			if _near_poly(q2, l.poly, r) and q.z - r < l.z + HEADROOM and q.z + r > l.z - 0.3:
				return [snappedf(q.x, 0.01), snappedf(q.y, 0.01), snappedf(q.z, 0.01)]
	return []

func _near_poly(p: Vector2, pg: PackedVector2Array, r: float) -> bool:
	if Geom.in_poly(p, pg):
		return true
	for i in pg.size():
		if Geometry2D.get_closest_point_to_segment(p, pg[i], pg[(i + 1) % pg.size()]).distance_to(p) < r:
			return true
	return false

## Where segment ra-rb (plant coordinates) passes a wall of building b with no opening there: the point, or [].
func _wall_crossing(b: Dictionary, ra: Vector3, rb: Vector3) -> Array:
	var pg: PackedVector2Array = b.outline
	var a2 := Vector2(ra.x, ra.y)
	var b2 := Vector2(rb.x, rb.y)
	if a2.distance_to(b2) < 1e-6:
		return []
	for i in pg.size():
		var w0 := pg[i]
		var w1 := pg[(i + 1) % pg.size()]
		var x = Geometry2D.segment_intersects_segment(a2, b2, w0, w1)
		if x == null:
			continue
		var z := lerpf(ra.z, rb.z, a2.distance_to(x) / a2.distance_to(b2))
		if z < 0.0 or z > b.height:
			continue
		var ok := false
		for o in b.openings:
			var oc := _opening_plan(b, o)
			if Geometry2D.get_closest_point_to_segment(oc, w0, w1).distance_to(oc) > 0.05:
				continue
			var oz := float(o.at[2])
			var zb := oz if o.kind == "door" else oz - float(o.height) * 0.5
			if oc.distance_to(x) <= float(o.width) * 0.5 and z >= zb and z <= zb + float(o.height):
				ok = true
		if not ok:
			return [snappedf(x.x, 0.01), snappedf(x.y, 0.01), snappedf(z, 0.01)]
	return []

func _opening_plan(b: Dictionary, o: Dictionary) -> Vector2:
	var t := Geom.turn(Vector3(float(o.at[0]), float(o.at[1]), 0), b.yaw)
	return Vector2(b.at.x + t.x, b.at.y + t.y)

## The wall edge [a, b] of a building's outline within tol of plan point p, or [].
func _wall_edge(b: Dictionary, p: Vector2, tol: float) -> Array:
	var pg: PackedVector2Array = b.outline
	for i in pg.size():
		var a := pg[i]
		var c := pg[(i + 1) % pg.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, c).distance_to(p) <= tol:
			return [a, c]
	return []

# ------------------------------------------------------------------ materials

## Saves every material the kit and the structures use to out_dir/materials (the 1024 px textures: decision 0041,
## kit/materials.gd), and the media's band colours. Returns the sum of the save errors.
func make_materials(out_dir: String) -> int:
	var dir := out_dir.path_join("materials")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err := Weather.make(Mat.NOISE)
	var specs := Mat.specs()
	var list := {}
	for name in specs:
		list[name] = Mat.make(name, specs[name])
	for name in Mat.STRUCTURE_MATS:
		list[name] = Mat.make_structure(name)
	var missing := Mat.missing_textures()
	if not missing.is_empty():
		warnings.append("no textures (kit/fetch_textures.sh, then Godot's import): %s" % ", ".join(missing))
		print("build: warning: materials without their textures: ", ", ".join(missing))
	for med in plant.get("media", {}):
		list["medium_" + med] = Mat.make("medium_" + med, {"set": "", "tint": Color.html(plant.media[med].band), "rough": 0.5, "metal": 0.0})
	# the ring road's centre line (builder/site.gd): a box in Godot's axes
	var rr: Rect2 = Site.new(self).extent().grow(Site.ROAD_GAP + Site.ROAD_W * 0.5)
	var rc := Geom.g([rr.get_center().x, rr.get_center().y, 0.0])
	(list["road"] as ShaderMaterial).set_shader_parameter("line_box", Vector4(rc.x, rc.z, rr.size.x * 0.5, rr.size.y * 0.5))
	var wz := _wet_zone()
	Mat.set_wet_zone(list, wz, 0.85 if wz != Vector4.ZERO else 0.0)
	for name in list:
		var path := dir.path_join(name + ".tres")
		var e := ResourceSaver.save(list[name], path, ResourceSaver.FLAG_CHANGE_PATH)
		err += e
		mats[name] = load(path)
	return err

## Where the ground is wet (the weathered materials' `wet_zone`): round a cooling tower's basin, which splashes and
## drips on the ground and the walls at its foot. A box in Godot's axes (centre x, z, half sizes); none without a
## tower.
func _wet_zone() -> Vector4:
	for k in equipment:
		var e: Dictionary = equipment[k]
		if e.part == "cooling_tower":
			var sh := shape_of(e.part, e.params)
			var sz: Vector3 = sh.get("size", Vector3(30, 30, 0))
			var g := Geom.g([e.pos.x, e.pos.y, 0.0])
			var turned := absf(sin(deg_to_rad(float(e.get("yaw", 0.0))))) > 0.7
			var hx := (sz.y if turned else sz.x) * 0.5 + 2.0
			var hz := (sz.x if turned else sz.y) * 0.5 + 2.0
			return Vector4(g.x, g.z, hx, hz)
	return Vector4.ZERO

func _mat(name: String) -> Material:
	return mats.get(name, mats.get("paint_grey"))

# ------------------------------------------------------------------ scene helpers

func _own(root: Node, n: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_own(root, c)

func _body(parent: Node, name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	parent.add_child(b)
	return b

func _convex(body: Node, pts: PackedVector3Array) -> void:
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	cs.shape = sh
	body.add_child(cs)

## A structure's mesh: static, with lightmap UV2 (builder/lightmap.gd) at `texel` metres.
func _mesh_node(parent: Node, name: String, st: SurfaceTool, mat: Material, texel := Lightmap.TEXEL) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	st.generate_tangents()
	st.index()
	var arr := st.commit_to_arrays()
	var lit: Mesh = null
	if not arr.is_empty() and arr[Mesh.ARRAY_INDEX] != null:
		lit = Lightmap.unwrap(Lightmap.white(arr), texel, false)
	if lit != null:
		mi.mesh = lit
		mi.material_override = mat
	else:
		st.set_material(mat)
		mi.mesh = st.commit()
	Lightmap.mark(mi, lit != null)
	parent.add_child(mi)
	return mi

func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## A slab: the region (outline less holes) from z - t to z, drawn and solid.
func _slab(parent: Node, name: String, outline: PackedVector2Array, holes: Array, z: float, t: float, mat: Material, texel := Lightmap.TEXEL) -> int:
	var pieces := Geom.decompose(outline, holes)
	if pieces.is_empty():
		return 0
	var st := _st()
	var body := _body(parent, name)
	for pc in pieces:
		Geom.add_prism(st, pc, z - t, z)
		_convex(body, Geom.prism_points(pc, z - t, z))
	_mesh_node(body, "mesh", st, mat, texel)
	return pieces.size()

## A thin vertical panel along plan segment a-b from z0 to z1 (rails, walls, fences), drawn into st and solid.
func _panel(st: SurfaceTool, body: Node, a: Vector2, b: Vector2, z0: float, z1: float, t: float) -> void:
	if a.distance_to(b) < 0.01:
		return
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * (t * 0.5)
	var pc := PackedVector2Array([a - n, b - n, b + n, a + n])
	Geom.add_prism(st, pc, z0, z1)
	if body != null:
		_convex(body, Geom.prism_points(pc, z0, z1))

## A sloped rail: a thin panel from (a, za) to (b, zb), h high.
func _slope_panel(st: SurfaceTool, body: Node, a: Vector2, b: Vector2, za: float, zb: float, h: float, t: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * (t * 0.5)
	var c := [[a - n, za], [b - n, zb], [b + n, zb], [a + n, za]]
	var pts := PackedVector3Array()
	var lo: Array = []
	var hi: Array = []
	for q in c:
		lo.append(Geom.g([q[0].x, q[0].y, q[1]]))
		hi.append(Geom.g([q[0].x, q[0].y, q[1] + h]))
		pts.append(lo[-1]); pts.append(hi[-1])
	if st != null:
		for i in 4:
			var j := (i + 1) % 4
			Geom._quad(st, lo[j], lo[i], hi[i], hi[j])
			Geom._quad(st, lo[i], lo[j], hi[j], hi[i])
	if body != null:
		_convex(body, pts)

## A handrail from (a, za) to (b, zb) (level or sloped): solid for the walker (a panel RAIL_H high), drawn as a top
## rail, a knee rail, a toe board and posts at most 1.5 m apart.
func _rail(st: SurfaceTool, body: Node, a: Vector2, b: Vector2, za: float, zb: float) -> void:
	if a.distance_to(b) < 0.01:
		return
	_slope_panel(null, body, a, b, za, zb, RAIL_H, 0.05)
	_slope_panel(st, null, a, b, za + RAIL_H - 0.05, zb + RAIL_H - 0.05, 0.05, 0.05)
	_slope_panel(st, null, a, b, za + 0.5, zb + 0.5, 0.04, 0.04)
	_slope_panel(st, null, a, b, za, zb, 0.1, 0.02)
	var n := int(ceil(a.distance_to(b) / 1.5))
	for k in n + 1:
		var f := float(k) / n
		var p := a.lerp(b, f)
		var z := lerpf(za, zb, f)
		Geom.add_prism(st, Geom.rect(p.x - 0.025, p.y - 0.025, p.x + 0.025, p.y + 0.025), z, z + RAIL_H)

## Rails along the boundary of a walkable region, except where the walker can go on (another walkable surface at
## the same height, a stair's landing or flight end, a ladder) or a building's wall stands.
func _rails(st: SurfaceTool, body: Node, sf: Dictionary) -> int:
	var count := 0
	var polys: Array = [] if sf.get("holes_only", false) else [sf.outline]
	polys.append_array(sf.holes)
	for pg in polys:
		for i in pg.size():
			var a: Vector2 = pg[i]
			var b: Vector2 = pg[(i + 1) % pg.size()]
			var len := a.distance_to(b)
			if len < 0.05:
				continue
			var d := (b - a) / len
			var n := Vector2(-d.y, d.x)
			var steps := int(ceil(len / 0.25))
			var run_start := -1.0
			for k in steps + 1:
				var on := false
				if k < steps:
					var t := (k + 0.5) * len / steps
					var m := a + d * t
					var i1 := Geom.in_region(m + n * 0.15, sf.outline, sf.holes)
					var i2 := Geom.in_region(m - n * 0.15, sf.outline, sf.holes)
					if i1 != i2:
						var q := m - n * 0.15 if i1 else m + n * 0.15
						on = not walkable_at(q, sf.z, sf.id) and not _near_wall(m, sf.z, 0.4) and not _near_ladder(m, sf.z)
				var t0 := float(k) * len / steps
				if on and run_start < 0.0:
					run_start = t0
				elif not on and run_start >= 0.0:
					_rail(st, body, a + d * run_start, a + d * t0, sf.z, sf.z)
					count += 1
					run_start = -1.0
	return count

func _near_wall(p: Vector2, z: float, tol: float) -> bool:
	for b in buildings:
		if z >= -TOL and z <= b.height and not _wall_edge(b, p, tol).is_empty():
			return true
	return false

func _near_ladder(p: Vector2, z: float) -> bool:
	for l in ladders:
		if absf(l.top - z) <= TOL or absf(l.foot.z - z) <= TOL:
			if p.distance_to(Vector2(l.foot.x, l.foot.y)) <= 1.0:
				return true
	return false

# ------------------------------------------------------------------ the scenes

func build_all(out_dir: String) -> int:
	var err := make_materials(out_dir)
	# the third-party assets' credits and licences (tools/about.py --plant), packed with the plant
	if DirAccess.copy_absolute(ProjectSettings.globalize_path("res://about.json"), ProjectSettings.globalize_path(out_dir.path_join("about.json"))) != OK:
		errors.append("cannot copy about.json (tools/about.py --plant) into the build")
		return err + 1
	var sky_src := ProjectSettings.globalize_path(SKY_SRC)
	if FileAccess.file_exists(sky_src):
		var t0 := Time.get_ticks_msec()
		var si := SkyBuild.make(sky_src, out_dir.path_join("sky"))
		if si.has("error"):
			errors.append(si.error)
			return err + 1
		print("build: sky: the sun %.1f° up at %.1f°, sky to sun on the ground %.2f, %d ms" % [si.sun_elevation, si.sun_azimuth, si.sky_to_sun, Time.get_ticks_msec() - t0])
	else:
		warnings.append("no sky photograph (kit/fetch_textures.sh): a physical sky instead")
		print("build: warning: no sky photograph, a physical sky instead")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir.path_join("areas")))
	var ground := _ground()
	err += _save(ground, out_dir.path_join("ground.scn"))
	var manifest_areas: Array = []
	for a in areas:
		var root := Node3D.new()
		root.name = "area_" + a.id
		_area(root, a)
		var path := out_dir.path_join("areas/%s.scn" % a.id)
		err += _save(root, path)
		var bd: Array = a.data.bounds
		manifest_areas.append({"id": a.id, "title": a.data.get("title", a.id), "scene": path, "bounds": bd})
	err += _bake_scene(out_dir, [out_dir.path_join("ground.scn")] + manifest_areas.map(func(a): return a.scene))
	var manifest := {
		"format": "walkdown-plant-built", "version": 1, "title": plant.get("title", ""),
		"start": {"at": _arr(Geom.g(plant.start.at)), "yaw": float(plant.start.get("yaw", 0))},
		"ground": out_dir.path_join("ground.scn"), "areas": manifest_areas, "extent": _extent(),
		"stairs": stairs.map(func(s): return {"id": s.id, "area": s.area, "path": s.lay.path.map(func(p): return _arr(Geom.g([p.x, p.y, p.z])))}),
		"ladders": ladders.map(func(l): return {"id": l.id, "area": l.area, "foot": _arr(Geom.g([l.foot.x, l.foot.y, l.foot.z])),
			"top": l.top, "facing": l.facing, "exit": _arr(Geom.g([l.exit.x, l.exit.y, l.exit.z]))}),
		"equipment": equipment.keys().filter(func(k): return not equipment[k].has("child")).map(func(k):
			var e = equipment[k]
			return {"kks": k, "name": e.name, "area": e.area, "at": _arr(Geom.g([e.pos.x, e.pos.y, e.pos.z]))}),
		"content": "\n".join(inputs).sha256_text(),
	}
	var f := FileAccess.open(out_dir.path_join("plant.json"), FileAccess.WRITE)
	if f == null:
		return err + 1
	f.store_string(JSON.stringify(manifest, " ", false))
	return err

## The scene the lightmap is baked in (builder/bake/, after this build, on a GPU): the ground and every area as
## instances under one node named as the app's plant node holds them, the sun, the sky, and the LightmapGI beside
## the areas, so the baked users' paths ("../area_…/…") hold in the app too (app/lighting.gd).
func _bake_scene(out_dir: String, scenes: Array) -> int:
	var root := Node3D.new()
	root.name = "plant"
	for path in scenes:
		var inst := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		root.add_child(inst)
		inst.owner = root
	var sun := Lighting.sun()
	root.add_child(sun)
	sun.owner = root
	var lm := LightmapGI.new()
	lm.name = "lightmap"
	lm.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lm.bounces = 3
	lm.use_denoiser = true
	lm.directional = false
	lm.interior = false
	lm.texel_scale = 1.0
	lm.max_texture_size = 4096   # the Note 9's Mali-G72 reads 8192 px; half that leaves room
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_SKY
	lm.environment_custom_sky = Lighting.sky()
	lm.environment_custom_energy = 1.0
	lm.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_SUBDIV_8
	lm.shadowmask_mode = LightmapGIData.SHADOWMASK_MODE_REPLACE   # the sun's shadow beyond the real-time distance
	root.add_child(lm)
	lm.owner = root
	var ps := PackedScene.new()
	var e := ps.pack(root)
	if e == OK:
		e = ResourceSaver.save(ps, out_dir.path_join("lit.scn"))
	root.free()
	if e != OK:
		errors.append("save the bake scene: error %d" % e)
	return e

func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func _save(root: Node, path: String) -> int:
	for c in root.get_children():
		_own(root, c)
	var ps := PackedScene.new()
	var e := ps.pack(root)
	if e == OK:
		e = ResourceSaver.save(ps, path)
	root.free()
	if e != OK:
		errors.append("save %s: error %d" % [path, e])
	return e

func _extent() -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for a in areas:
		var b: Array = a.data.bounds
		lo = Vector2(minf(lo.x, b[0][0]), minf(lo.y, b[0][1]))
		hi = Vector2(maxf(hi.x, b[1][0]), maxf(hi.y, b[1][1]))
	return [[lo.x, lo.y], [hi.x, hi.y]]

func _ground() -> Node3D:
	var root := Node3D.new()
	root.name = "ground"
	var holes: Array = []
	for p in pits:
		holes.append(p.outline)
	holes.append_array(ground_cuts())
	var site := Site.new(self)
	site.make(root, holes)
	var outline := Site.poly_of(site.wall_rect())
	# rails round open pits (a pit covered by a grating at z = 0 needs none)
	var st := _st()
	var body := _body(root, "pit_rails")
	var n := 0
	var pit_holes: Array = pits.map(func(p): return p.outline)
	if not pit_holes.is_empty():   # the ground's own outer edge, far out, gets none
		n += _rails(st, body, {"id": "ground", "z": 0.0, "outline": outline, "holes": pit_holes, "holes_only": true})
	if n > 0:
		_mesh_node(body, "mesh", st, _mat("rail"))
	else:
		body.free()
	return root

func _area(root: Node3D, a: Dictionary) -> void:
	var eq := Node3D.new(); eq.name = "equipment"; root.add_child(eq)
	var pipes := Node3D.new(); pipes.name = "pipes"; root.add_child(pipes)
	var sts := Node3D.new(); sts.name = "structures"; root.add_child(sts)
	var signs := Node3D.new(); signs.name = "signs"; root.add_child(signs)
	for e in a.data.get("equipment", []):
		kp.equipment(eq, e.kks, true)
		for c in e.get("parts", []):
			kp.equipment(eq, c.kks, false)
	for p in a.data.get("pipes", []):
		kp.pipe(pipes, p)
	for sf in surfaces:
		if sf.area == a.id:
			_surface(sts, sf)
	for s in stairs:
		if s.area == a.id:
			_stair(sts, s)
	for l in ladders:
		if l.area == a.id:
			_ladder(sts, l)
	for b in buildings:
		if b.area == a.id:
			_building(sts, b)
	for p in pits:
		if p.area == a.id:
			_pit(sts, p)
	for s in a.data.get("structures", []):
		match s.part:
			"door": _door(sts, s)
			"slab": _slab_part(sts, s)
			"fence": _fence(sts, s)
			"pipe_rack": _rack(sts, s)
	for sg in a.data.get("signs", []):
		var l := Label3D.new()
		l.name = "sign"
		l.text = sg.text
		l.pixel_size = float(sg.get("size", 0.3)) / 64.0
		l.font_size = 64
		l.outline_size = 12
		# yaw is the way the sign's face points: it stands a little in front of the wall it is fixed to, and its
		# back is blank
		var fd := Geom.heading(float(sg.get("yaw", 0)))
		l.position = Geom.g([sg.at[0] + fd.x * 0.25, sg.at[1] + fd.y * 0.25, sg.at[2]])
		l.rotation.y = Geom.yaw_rad(float(sg.get("yaw", 0))) + PI
		l.double_sided = false
		signs.add_child(l)
	kp.flush(root)

# ------------------------------------------------------------------ equipment (made by the parts kit: kit_place.gd)

## A part's rough shape in its frame (x right, y forward, z up): {kind: box | vcyl | hcyl, size, z0}, from its
## parameters: the footprint the build looks for decks over (kit_place.gd _decks).
func shape_of(part: String, p: Dictionary) -> Dictionary:
	var n := func(k: String, d: float) -> float: return float(p.get(k, d))
	match part:
		"gas_turbine": return {"kind": "hcyl", "size": Vector3(n.call("casing_d", 4.5), n.call("length", 22), n.call("casing_d", 4.5))}
		"generator", "steam_turbine", "package_boiler", "vessel_horizontal", "drum":
			return {"kind": "hcyl", "size": Vector3(n.call("d", 3), n.call("length", 8), n.call("d", 3))}
		"shell_tube_hx":
			if p.get("orientation", "horizontal") == "vertical":
				return {"kind": "vcyl", "size": Vector3(n.call("d", 1.2), n.call("d", 1.2), n.call("length", 5))}
			return {"kind": "hcyl", "size": Vector3(n.call("d", 1.2), n.call("length", 5), n.call("d", 1.2))}
		"cooling_tower":   # the kit's cooling tower has its length across (its nozzles say so)
			return {"kind": "box", "size": Vector3(n.call("length", 80), n.call("width", 32), n.call("height", 14))}
		"hrsg", "condenser", "filter_house":
			return {"kind": "box", "size": Vector3(n.call("width", 20), n.call("length", 50), n.call("height", 20))}
		"hrsg_module": return {"kind": "box", "size": Vector3(n.call("width", 20), n.call("depth", 2.5), n.call("height", 26))}
		"stack", "silencer", "tank_vertical": return {"kind": "vcyl", "size": Vector3(n.call("d", 2), n.call("d", 2), n.call("height", 4))}
		"fan_axial": return {"kind": "vcyl", "size": Vector3(n.call("d", 9.5), n.call("d", 9.5), n.call("stack_height", 3))}
		"basin": return {"kind": "box", "size": Vector3(n.call("length", 80), n.call("width", 32), 0.3), "z0": -0.25}
		"sfc", "switchgear_row": return {"kind": "box", "size": Vector3(n.call("panels", 6) * 0.8, n.call("depth", 0.8), 2.3)}
		"turning_gear": return {"kind": "box", "size": Vector3(1.2, 1.2, 1.2)}
		"pump_horizontal": return {"kind": "box", "size": Vector3(1.2, n.call("length", 3), 1.3)}
		"pump_vertical": return {"kind": "vcyl", "size": Vector3(1.6, 1.6, 3.2)}
		"compressor_skid": return {"kind": "box", "size": Vector3(n.call("width", 2), n.call("length", 4), 2.0)}
		"vacuum_pump_skid": return {"kind": "box", "size": Vector3(2.0, n.call("length", 4), 2.0)}
		"plate_hx": return {"kind": "box", "size": Vector3(1.0, 2.5, n.call("height", 2.2))}
		"transformer":
			var s := pow(n.call("mva", 300) / 300.0, 1.0 / 3.0)
			return {"kind": "box", "size": Vector3(5.0, 8.0, 6.0) * s}
		"breaker": return {"kind": "box", "size": Vector3(2.0, n.call("length", 6), 2.5)}
		"cabinet": return {"kind": "box", "size": Vector3(n.call("width", 1.2), n.call("depth", 0.8), n.call("height", 2.2))}
		"local_panel": return {"kind": "box", "size": Vector3(n.call("width", 0.8), 0.4, n.call("height", 1.8))}
		"motor": return {"kind": "box", "size": Vector3(1.0, 1.5, 1.0)}
		"damper": return {"kind": "box", "size": Vector3(n.call("width", 5), 0.6, n.call("height", 5)), "center": true}
	var g: String = kit.parts.get(part, {}).get("group", "")
	if g == "valves":
		var od := _od(int(p.get("dn", 100))) / 1000.0
		return {"kind": "box", "size": Vector3(od * 1.6, maxf(od * 1.2, 0.2), od * 1.6), "center": true}
	if g == "instruments":
		return {"kind": "box", "size": Vector3(0.15, 0.15, 0.25), "center": kit.parts.get(part, {}).get("inline", false)}
	return {"kind": "box", "size": Vector3(0.5, 0.5, 0.5)}

# ------------------------------------------------------------------ pipes

func _od(dn: int) -> float:
	var best := 0.0
	for row in kit.get("dn_od_mm", []):
		if int(row[0]) == dn:
			return float(row[1])
		if int(row[0]) < dn:
			best = float(row[1])
	return best if best > 0.0 else dn * 1.1

func _end_point(end: Dictionary) -> Vector3:
	if end.has("kks"):
		var e: Dictionary = equipment.get(end.kks, {})
		var nz: Dictionary = kit.parts.get(e.get("part", ""), {}).get("nozzles", {}).get(end.nozzle, {})
		if e.is_empty() or nz.is_empty():
			return Vector3.INF
		var c := Vector3.ZERO
		for i in 3:
			var v = nz.at[i]
			c[i] = float(v) if not v is Array else float(e.params.get(v[0], 0)) * float(v[1]) + float(v[2])
		return e.pos + Geom.turn(c, e.yaw)
	return _v3(end.at)

## A transform whose Y axis runs from a to b, centred between them (cylinders lie along Y).
func _along(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)

# ------------------------------------------------------------------ structures

func _surface(parent: Node3D, sf: Dictionary) -> void:
	var mat := _mat("grating" if sf.deck == "grating" else ("deck_steel" if sf.deck == "steel" else ("pit" if sf.kind == "pit_floor" else "concrete")))
	_slab(parent, sf.id, sf.outline, sf.holes, sf.z, sf.thick, mat)
	if sf.rails:
		var st := _st()
		var body := _body(parent, sf.id + "_rails")
		if _rails(st, body, sf) > 0:
			_mesh_node(body, "mesh", st, _mat("rail"))
		else:
			body.free()

func _stair(parent: Node3D, s: Dictionary) -> void:
	var body := _body(parent, s.id)
	body.set_meta("stair", s.id)
	var steps := _st()
	var rails := _st()
	for fl in s.lay.flights:
		var k: int = fl.steps
		var rise: float = (fl.z1 - fl.z0) / k
		var dir: Vector2 = (fl.b - fl.a)
		var run := dir.length()
		var going := run / maxf(k - 1, 1)
		dir = dir.normalized()
		# the steps as drawn: k - 1 treads between the landings (the last riser leads onto the upper landing)
		for j in range(k - 1):
			var t0 := j * going
			var pc := Geom._strip(fl.a + dir * t0, fl.a + dir * (t0 + going), fl.side, fl.width)
			Geom.add_prism(steps, pc, fl.z0 + rise * j, fl.z0 + rise * (j + 1))
		# what the walker stands on: a smooth slope from landing to landing (a walker climbs a slope, not ledges)
		# from one going before the first riser, so the slope is the stair's own pitch (rise / going, at most about
		# 39 degrees) and not steeper on short flights; that first going lies on the landing below
		_convex(body, Geom.ramp_points(fl.a - dir * going, fl.b, fl.side, fl.width, fl.z0, fl.z1, 0.25))
		for sgn in [-1.0, 1.0]:
			var off: Vector2 = fl.side * (fl.width * 0.5 * sgn)
			_rail(rails, body, fl.a + off, fl.b + off, fl.z0, fl.z1)
	for l in s.lay.landings:
		var c := Vector2.ZERO
		for p in l.poly: c += p
		c /= l.poly.size()
		if _other_walkable(c, l.z):
			continue   # ground or a floor or platform is there already (the start, a landing joining a floor)
		for pc in Geom.decompose(l.poly, []):
			Geom.add_prism(steps, pc, l.z - 0.2, l.z)
			_convex(body, Geom.prism_points(pc, l.z - 0.2, l.z))
		_rails(rails, body, {"id": "", "z": l.z, "outline": l.poly, "holes": []})
	_mesh_node(body, "steps", steps, _mat("stair"))
	_mesh_node(body, "rails", rails, _mat("rail"))

func _other_walkable(p: Vector2, z: float) -> bool:
	for sf in surfaces:
		if absf(sf.z - z) <= TOL and Geom.in_region(p, sf.outline, sf.holes):
			return true
	return absf(z) <= TOL and ground_at(p)

func _ladder(parent: Node3D, l: Dictionary) -> void:
	var root := Node3D.new()
	root.name = l.id
	root.add_to_group("ladders", true)
	# in Godot's axes, for the walker: the foot, the top's height, the way the climber faces, where they step off
	root.set_meta("foot", Geom.g([l.foot.x, l.foot.y, l.foot.z]))
	root.set_meta("top", float(l.top))
	var fd := Geom.heading(l.facing)
	root.set_meta("facing", Vector3(fd.x, 0, -fd.y))
	root.set_meta("exit", Geom.g([l.exit.x, l.exit.y, l.exit.z]))
	root.set_meta("id", l.id)
	parent.add_child(root)
	var hd := Geom.heading(l.facing)
	var across := Vector2(hd.y, -hd.x)
	var c := Vector2(l.foot.x, l.foot.y) + hd * 0.25   # the rungs, just ahead of the climber
	var z0: float = l.foot.z
	var z1: float = l.top + 1.1   # the stiles reach above the top, to hold on stepping off
	var st := _st()
	for sgn in [-1.0, 1.0]:
		var p: Vector2 = c + across * (0.23 * sgn)
		var pc := Geom._strip(p - hd * 0.03, p + hd * 0.03, across, 0.06)
		Geom.add_prism(st, pc, z0, z1)
	var z := z0 + 0.3
	while z < l.top + 0.01:
		Geom.add_prism(st, Geom._strip(c - across * 0.23, c + across * 0.23, hd, 0.03), z - 0.015, z + 0.015)
		z += 0.3
	# a cage above 3 m (EN ISO 14122-4): hoops from 2.5 m above the foot, every 1.2 m, and vertical bars
	if l.top - z0 > 3.0:
		var hz := z0 + 2.5
		while hz < z1:
			var ring := PackedVector2Array()
			for i in 13:
				var a := PI * i / 12.0
				ring.append(c + across * (cos(a) * 0.36) - hd * (sin(a) * 0.7 - 0.0))
			for i in 12:
				_panel(st, null, ring[i], ring[i + 1], hz, hz + 0.05, 0.05)
			hz += 1.2
	_mesh_node(root, "mesh", st, _mat("ladder"))

func _building(parent: Node3D, b: Dictionary) -> void:
	var body := _body(parent, b.id)
	body.set_meta("building", b.id)
	var walls := _st()
	var pg: PackedVector2Array = b.outline
	var h: float = b.height
	var roof_holes: Array = []
	for i in pg.size():
		var a := pg[i]
		var c := pg[(i + 1) % pg.size()]
		var d := c - a
		var len := d.length()
		var u := d / len
		var cuts: Array = []   # [t0, t1, z0, z1]
		for o in b.openings:
			var oc := _opening_plan(b, o)
			var oz := float(o.at[2])
			if oz >= h - 0.5:
				if i == 0:   # a roof opening (an intake on the roof)
					var w2 := float(o.width) * 0.5
					var h2 := float(o.height) * 0.5
					roof_holes.append(Geom.rect(oc.x - w2, oc.y - h2, oc.x + w2, oc.y + h2))
				continue
			if Geometry2D.get_closest_point_to_segment(oc, a, c).distance_to(oc) > 0.05:
				continue
			var t := (oc - a).dot(u)
			var oh := float(o.height)
			var zb := oz if o.kind == "door" else oz - oh * 0.5   # a door's `at` is its sill; others' their centre
			if o.kind in ["door", "pipe"]:
				cuts.append([t - float(o.width) * 0.5, t + float(o.width) * 0.5, zb, zb + oh])
		# the wall's face (along the edge t, up z) less its openings, in rectangles (openings may overlap)
		var holes: Array = []
		for cu in cuts:
			holes.append(Geom.rect(cu[0], cu[2], cu[1], cu[3]))
		for pc in Geom.decompose(Geom.rect(0.0, 0.0, len, h), holes):
			var r := Rect2(pc[0], Vector2.ZERO)
			for q in pc:
				r = r.expand(q)
			if r.size.x > 0.01 and r.size.y > 0.01:
				_panel(walls, body, a + u * r.position.x, a + u * r.end.x, r.position.y, r.end.y, 0.25)
	_mesh_node(body, "walls", walls, _mat("wall_" + b.cladding))
	var roof := _st()
	for pc in Geom.decompose(pg, roof_holes):
		Geom.add_prism(roof, pc, h, h + 0.3)
		_convex(body, Geom.prism_points(pc, h, h + 0.3))
	_mesh_node(body, "roof", roof, _mat("roof"))
	_lamps(body, b)

## High-bay lamps under a building's roof (a hall is lit by its lamps, not by the sky through its walls): a grid
## about 0.6 × the height apart (6 to 10 m), each a housing, a lit lens and a light the bake takes in whole
## (BAKE_STATIC: its light and shadow are in the lightmap; the app drops the light node once a bake is there, the
## pieces that move take the sky's light: app/main.gd).
const LAMP_LUX := 2.0   # light energy of one lamp (Godot's units), set by eye against the outdoor exposure
func _lamps(body: Node, b: Dictionary) -> int:
	var pg: PackedVector2Array = b.outline
	var h: float = b.height
	var r := Rect2(pg[0], Vector2.ZERO)
	for q in pg:
		r = r.expand(q)
	var gap := clampf(h * 0.6, 6.0, 10.0)
	var nx := maxi(1, int(round(r.size.x / gap)))
	var ny := maxi(1, int(round(r.size.y / gap)))
	var housing := _st()
	var lens := _st()
	var n := 0
	for i in nx:
		for j in ny:
			var c := r.position + Vector2(r.size.x * (i + 0.5) / nx, r.size.y * (j + 0.5) / ny)
			if not Geom.in_region(c, pg, []):
				continue
			var z := h - 0.6
			Geom.add_prism(housing, Geom.rect(c.x - 0.3, c.y - 0.3, c.x + 0.3, c.y + 0.3), z, z + 0.25)
			Geom.add_prism(lens, Geom.rect(c.x - 0.25, c.y - 0.25, c.x + 0.25, c.y + 0.25), z - 0.03, z)
			var l := OmniLight3D.new()
			l.name = "lamp_%d" % n
			l.position = Geom.g([c.x, c.y, z - 0.2])
			l.omni_range = h * 1.4
			l.omni_attenuation = 1.0
			l.light_energy = LAMP_LUX
			l.light_color = Color(1.0, 0.95, 0.86)
			l.light_bake_mode = Light3D.BAKE_STATIC
			l.shadow_enabled = false
			l.add_to_group("baked_lights", true)
			body.add_child(l)
			n += 1
	if n > 0:
		_mesh_node(body, "lamp_housings", housing, _mat("steel_dark"))
		_mesh_node(body, "lamp_lenses", lens, _mat("lamp_white"))
	return n

func _pit(parent: Node3D, p: Dictionary) -> void:
	var body := _body(parent, p.id + "_walls")
	var st := _st()
	var pg: PackedVector2Array = p.outline
	# where a stair leaves the pit its wall is open (the flight's slope would otherwise end against the wall's top)
	var strips: Array = []
	for s in stairs:
		for fl in s.lay.flights:
			if fl.z0 < -TOL:
				strips.append(Geom._strip(fl.a, fl.b, fl.side, fl.width))
	for i in pg.size():
		var a := pg[i]
		var b := pg[(i + 1) % pg.size()]
		var len := a.distance_to(b)
		var n := maxi(1, int(ceil(len / 0.1)))
		var start := -1.0
		for k in n + 1:
			var open := false
			if k < n:
				var m := a.lerp(b, (k + 0.5) / n)
				for sp in strips:
					if _near_poly(m, sp, 0.2):
						open = true
			var t := float(k) / n
			if not open and k < n and start < 0.0:
				start = t
			elif (open or k == n) and start >= 0.0:
				_panel(st, body, a.lerp(b, start), a.lerp(b, t), -float(p.depth), 0.0, 0.3)
				start = -1.0
	_mesh_node(body, "mesh", st, _mat("pit"))

func _door(parent: Node3D, s: Dictionary) -> void:
	var pr := params_of("door", s.get("params", {}))
	var door := AnimatableBody3D.new()
	door.name = s.id
	door.set_script(load("res://app/door.gd"))
	door.set("kind", pr.kind)
	door.set("width", float(pr.width))
	door.set("height", float(pr.height))
	door.position = Geom.g(s.at)
	door.rotation.y = Geom.yaw_rad(float(s.get("yaw", 0)))
	door.add_to_group("doors", true)
	parent.add_child(door)
	var mi := MeshInstance3D.new()
	mi.name = "panel"
	var bm := BoxMesh.new()
	bm.size = Vector3(float(pr.width), float(pr.height), 0.08)
	mi.mesh = bm
	mi.position.y = float(pr.height) * 0.5
	mi.material_override = _mat("door")
	Lightmap.mark(mi, false)   # it moves: the sky's light
	door.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position = mi.position
	door.add_child(cs)

func _slab_part(parent: Node3D, s: Dictionary) -> void:
	var pr := params_of("slab", s.get("params", {}))
	var at := _v3(s.at)
	var pg := Geom.poly(pr.outline, Vector2(at.x, at.y), float(s.get("yaw", 0)))
	_slab(parent, s.id, pg, [], at.z + float(pr.thickness), float(pr.thickness), _mat("concrete"))

func _fence(parent: Node3D, s: Dictionary) -> void:
	var pr := params_of("fence", s.get("params", {}))
	var at := _v3(s.at)
	var body := _body(parent, s.id)
	var st := _st()
	var pts: Array = pr.route
	for i in range(pts.size() - 1):
		var a := at + Geom.turn(_v3(pts[i]), float(s.get("yaw", 0)))
		var b := at + Geom.turn(_v3(pts[i + 1]), float(s.get("yaw", 0)))
		_panel(st, body, Vector2(a.x, a.y), Vector2(b.x, b.y), a.z, a.z + float(pr.height), 0.05)
	_mesh_node(body, "mesh", st, _mat("fence"))

func _rack(parent: Node3D, s: Dictionary) -> void:
	var pr := params_of("pipe_rack", s.get("params", {}))
	var at := _v3(s.at)
	var yaw := float(s.get("yaw", 0))
	var body := _body(parent, s.id)
	var st := _st()
	var L := float(pr.length)
	var W := float(pr.width)
	var H := float(pr.height)
	var bays := int(pr.bays)
	var tiers := int(pr.tiers)
	var c := Vector2(at.x, at.y)
	var fw := Geom.heading(yaw)
	var right := Vector2(fw.y, -fw.x)
	for i in bays + 1:
		var y := -L * 0.5 + L * i / bays
		for sx in [-0.5, 0.5]:
			var p: Vector2 = c + fw * y + right * (W * sx)
			var pc := Geom.rect(p.x - 0.15, p.y - 0.15, p.x + 0.15, p.y + 0.15)
			Geom.add_prism(st, pc, at.z, at.z + H)
			_convex(body, Geom.prism_points(pc, at.z, at.z + H))
		for k in tiers:
			var z := H - 2.0 * (tiers - 1 - k)   # tiers 2 m apart below the top (+8 and +10 for a 10 m rack)
			var p0 := c + fw * y - right * (W * 0.5)
			var p1 := c + fw * y + right * (W * 0.5)
			Geom.add_prism(st, Geom._strip(p0, p1, fw, 0.2), at.z + z - 0.3, at.z + z)
	for sx in [-0.5, 0.5]:
		var p0: Vector2 = c - fw * (L * 0.5) + right * (W * sx)
		var p1: Vector2 = c + fw * (L * 0.5) + right * (W * sx)
		Geom.add_prism(st, Geom._strip(p0, p1, right, 0.2), at.z + H - 0.3, at.z + H)
	_mesh_node(body, "mesh", st, _mat("rack"))
