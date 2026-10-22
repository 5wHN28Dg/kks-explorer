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
	"fence", "pipe_rack", "wall"]

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
## The lightmap's texel for what is being built, as a factor of each piece's own: 2 for the site's and the camp's
## areas (low buildings seen from afar: a quarter of the texels, so the bake's atlas and the package stay near the first
## train's)
var texel_scale := 1.0
const SITE_TEXEL_SCALE := 2.0
var kit_structures: Array = []   # the structures the parts kit draws (planting, vehicles, furniture): {s, area}
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
		if Kit.has_part(part):   # the site's and the camp's (kit/parts_site.gd)
			kit_structures.append({"s": s, "area": a.id})
			return
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
			"thick": DECK.get(deck, 0.2), "rails": rails, "deck": deck, "area": a.id, "finish": pr.get("finish", "epoxy"),
			"surface": pr.get("surface", "")})
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
			"rel": a.rel, "floor": pr.get("floor", "epoxy"), "crane": float(pr.get("crane", 0.0)), "kks": s.get("kks", "")})
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
			if s.part != "door" or s.get("params", {}).get("locked", false):
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
	# the ground beside the road (ruts, compacted verges: the shader's `macro`), without the road's line
	for gname in ["ground", "terrain"]:
		var gm := list[gname] as ShaderMaterial
		gm.set_shader_parameter("line_box", Vector4(rc.x, rc.z, rr.size.x * 0.5, rr.size.y * 0.5))
		gm.set_shader_parameter("road_line", 0.0)
	# a track out of the gate (the middle of the wall's south side) into the country, southwards (Godot's +z)
	var wall := Site.new(self).wall_rect()
	var gate := Geom.g([wall.get_center().x, wall.position.y, 0.0])
	(list["terrain"] as ShaderMaterial).set_shader_parameter("track", Vector4(gate.x, gate.z, 0.0, 1.0))
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

## A structure's mesh: static, with lightmap UV2 (builder/lightmap.gd) at `texel` metres. `baked` false: UV2 all the
## same (one vertex format: one pipeline), but lit by the sky, not the bake (a thin sheet's two faces share their
## lightmap's texels and baked as dark and brown blotches: the transformer yard's fence, second realism pass).
func _mesh_node(parent: Node, name: String, st: SurfaceTool, mat: Material, texel := Lightmap.TEXEL, baked := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	st.generate_tangents()
	st.index()
	var arr := st.commit_to_arrays()
	var lit: Mesh = null
	if not arr.is_empty() and arr[Mesh.ARRAY_INDEX] != null:
		lit = Lightmap.unwrap(Lightmap.white(arr), texel * texel_scale, false)
	if lit != null:
		mi.mesh = lit
		mi.material_override = mat
	else:
		st.set_material(mat)
		mi.mesh = st.commit()
	Lightmap.mark(mi, lit != null and baked)
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

## A thin vertical panel along plan segment a-b from z0 to z1 (rails, walls, fences), drawn into st and solid in body
## (either may be null).
func _panel(st: SurfaceTool, body: Node, a: Vector2, b: Vector2, z0: float, z1: float, t: float) -> void:
	if a.distance_to(b) < 0.01:
		return
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * (t * 0.5)
	var pc := PackedVector2Array([a - n, b - n, b + n, a + n])
	if st != null:
		Geom.add_prism(st, pc, z0, z1)
	if body != null:
		_convex(body, Geom.prism_points(pc, z0, z1))

## The vertex colour that tells the weathered shader where a wall panel's top is (its `top_edge`: streaks hang from
## there): r in quarter metres (to 63.75 m), g the fraction of a quarter. Vertex colours are stored as 8 bits.
## The top is the builder's z, which the shader compares with the world's y: right while every area and building
## stands at grade 0 (none is placed higher); one placed higher would need its offset added here.
static func top_colour(z1: float) -> Color:
	var q := clampf(z1, 0.0, 63.9) / 0.25
	return Color(floorf(q) / 255.0, q - floorf(q), 0.0, 1.0)

## A wall panel (as _panel) whose vertices carry its top (top_colour): z1, or `top` where the face goes on above the
## panel (a wall cut into pieces round its openings: a piece beside or under an opening is not the wall's top).
func _wall_panel(st: SurfaceTool, body: Node, a: Vector2, b: Vector2, z0: float, z1: float, t: float, top := -1.0) -> void:
	st.set_color(top_colour(top if top >= 0.0 else z1))
	_panel(st, body, a, b, z0, z1, t)

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
	var interiors: Array = []
	for a in areas:
		var root := Node3D.new()
		root.name = "area_" + a.id
		var inside: bool = a.data.get("load", "") == "inside"
		kp.unbaked = inside
		texel_scale = SITE_TEXEL_SCALE if a.data.get("pack", "") in ["site", "camp"] else 1.0
		_area(root, a)
		kp.unbaked = false
		texel_scale = 1.0
		var path := out_dir.path_join("areas/%s.scn" % a.id)
		err += _save(root, path)
		var bd: Array = a.data.bounds
		var entry := {"id": a.id, "title": a.data.get("title", a.id), "scene": path, "bounds": bd}
		if inside:
			# an interior (PLANT3D.md §18.5): loaded by the app near its building's doors, left out of the bake
			entry["doors"] = interior_doors(a).map(func(p): return _arr(Geom.g([p.x, p.y, 0.0])))
			interiors.append(entry)
		else:
			manifest_areas.append(entry)
	err += _bake_scene(out_dir, [out_dir.path_join("ground.scn")] + manifest_areas.map(func(a): return a.scene))
	var manifest := {
		"format": "walkdown-plant-built", "version": 1, "title": plant.get("title", ""),
		"start": {"at": _arr(Geom.g(plant.start.at)), "yaw": float(plant.start.get("yaw", 0))},
		"ground": out_dir.path_join("ground.scn"), "areas": manifest_areas, "interiors": interiors, "extent": _extent(),
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

## An interior's doors (plan points): the door openings of the buildings standing in its bounds (their shells are in
## the area that holds the interior), where the app loads it as the trainee comes near (PLANT3D.md §18.5); its bounds'
## centre when none.
func interior_doors(a: Dictionary) -> Array:
	var bd: Array = a.data.bounds
	var r := Rect2(Vector2(bd[0][0], bd[0][1]), Vector2(bd[1][0] - bd[0][0], bd[1][1] - bd[0][1]))
	var out: Array = []
	for b in buildings:
		if b.area == a.id or not r.grow(0.01).has_point(_mean(b.outline)):
			continue
		for o in b.openings:
			if o.kind == "door":
				out.append(_opening_plan(b, o))
	if out.is_empty():
		out.append(r.get_center())
	return out

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
	# the scene's environment: the bake plugin adds the sky in a WorldEnvironment the editor draws (a sky no viewport
	# has drawn reads black to the bake: builder/bake/bake_plugin.gd)
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_SCENE
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
			var n0 := sts.get_child_count()
			_surface(sts, sf)
			if sts.get_child_count() > n0:     # its slab's body (made first): what footsteps on it sound like
				sts.get_child(n0).set_meta("deck", sf.deck)
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
			"wall": _wall(sts, s)
			"pipe_rack": _rack(sts, s)
	for ks in kit_structures:
		if ks.area == a.id:
			kp.structure(sts, ks.s)
	for sg in a.data.get("signs", []):
		var l := Label3D.new()
		l.name = "sign"
		l.text = sg.text
		var size := float(sg.get("size", 0.3))
		l.pixel_size = size / 64.0
		l.font_size = 64
		l.double_sided = false
		# yaw is the way the sign's face points: it stands a little in front of the wall it is fixed to, and its
		# back is blank
		var fd := Geom.heading(float(sg.get("yaw", 0)))
		l.rotation.y = Geom.yaw_rad(float(sg.get("yaw", 0))) + PI
		var symbol: String = sg.get("symbol", "")
		if symbol == "":
			l.outline_size = 12
			l.position = Geom.g([sg.at[0] + fd.x * 0.25, sg.at[1] + fd.y * 0.25, sg.at[2]])
		else:
			# a safety sign (PLANT3D.md §5): its symbol above the text on a white board fixed to the wall, the text
			# black on it (no outline: the label is one draw call, and the board merges into its cell's)
			var w := ThemeDB.fallback_font.get_string_size(sg.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * l.pixel_size
			var base := Geom.g([sg.at[0], sg.at[1], sg.at[2]])
			var xf := Transform3D(Basis(Vector3.UP, l.rotation.y), base)      # the label's frame: x along its text, z out
			kp.sign_board(xf, symbol, w, size)
			l.outline_size = 0
			l.modulate = Color(0.02, 0.02, 0.02)
			# blended as the outlined label was (smooth glyph edges far off; a cut-out label would cast a shadow)
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			l.position = base + xf.basis.z * (kp.sign_layout(w, size).face + 0.015)   # clear of the disc's face
			l.set_meta("symbol", symbol)
			l.set_meta("text_width", w)
		signs.add_child(l)
	kp.flush(root)
	if a.data.get("pack", "") in ["site", "camp"] and a.data.get("load", "") != "inside":
		var keep := {}   # its roads and walls: drawn at every distance (long and flat: a few draw calls)
		for s in a.data.get("structures", []):
			if s.part in ["road", "wall", "fence"]:
				keep[s.id] = true
		hlod(root, a.id, _far_items(a), root, keep)

# ------------------------------------------------------------------ the far view of the site and the camp (HLOD)

## The site's and the camp's far view (PLANT3D.md §10: "merged per 12 m cell far away (Godot visibility ranges as
## HLOD)"; SITE.md §5: a new area's draw calls in any view that sees it): per HLOD_CHUNK square, one plain mesh of its
## buildings as boxes under their roofs, its plants as a trunk and a crown and its shade canopies as sheets, drawn
## beyond HLOD_RANGE of it; the area's own pieces in that square are drawn only within it (each one's
## `visibility_parent` is its square's mesh). From the train the camp is a few draw calls, not hundreds. The far
## meshes are unbaked and without UV2 (the moving pieces' pipelines: none new), and cast no shadow (beyond every
## tier's shadow distance).
const HLOD_CHUNK := 48.0
const HLOD_RANGE := 120.0
const FAR_WALL := Color(0.80, 0.77, 0.70)
const FAR_ROOF := Color(0.62, 0.63, 0.62)
const FAR_LEAF := Color(0.36, 0.44, 0.30)
const FAR_TRUNK := Color(0.42, 0.35, 0.27)
const FAR_SHEET := Color(0.80, 0.75, 0.63)

## What the far view of an area shows: {buildings: [{outline, height}], plants: [[species, plan point, height]],
## sheets: [[plan polygon, height]]}.
func _far_items(a: Dictionary) -> Dictionary:
	var out := {"buildings": [], "plants": [], "sheets": []}
	for bl in buildings:
		if bl.area == a.id:
			out.buildings.append({"outline": bl.outline, "height": bl.height})
	for ks in kit_structures:
		if ks.area != a.id:
			continue
		var s: Dictionary = ks.s
		var pr := params_of(s.part, s.get("params", {}))
		match s.part:
			"planting":
				var h := float(pr.height) if float(pr.height) > 0.0 else float(KitPlace.P_SITE.SPECIES.get(String(pr.species), {}).get("height", 2.0))
				for pl in kp.planting_places(s, pr):
					out.plants.append([String(pr.species), Vector2(pl[0].x, pl[0].y), h])
			"canopy", "porch":
				var L := float(pr.length)
				var w := float(pr.get("width", pr.get("depth", 2.5)))
				var off := Vector2.ZERO if s.part == "canopy" else Vector2(0, w * 0.5)   # a porch reaches out from its wall
				var pg := Geom.poly([[-L * 0.5 + off.x, -w * 0.5 + off.y], [L * 0.5 + off.x, -w * 0.5 + off.y],
					[L * 0.5 + off.x, w * 0.5 + off.y], [-L * 0.5 + off.x, w * 0.5 + off.y]], Vector2(s.at[0], s.at[1]), float(s.get("yaw", 0)))
				if s.part == "canopy":
					pg = Geom.poly([[-w * 0.5, -L * 0.5], [w * 0.5, -L * 0.5], [w * 0.5, L * 0.5], [-w * 0.5, L * 0.5]], Vector2(s.at[0], s.at[1]), float(s.get("yaw", 0)))
				out.sheets.append([pg, float(pr.height)])
	return out

## Builds the far meshes of `items` under root's node "far", and parents every drawn piece under root to its square's
## mesh. Returns the far meshes made.
func hlod(root: Node3D, id: String, items: Dictionary, scope: Node, keep := {}) -> int:
	var sts := {}   # Vector2i -> SurfaceTool
	var st_of := func(p: Vector2) -> SurfaceTool:
		var k := Vector2i(int(floor(p.x / HLOD_CHUNK)), int(floor(p.y / HLOD_CHUNK)))
		if not sts.has(k):
			sts[k] = _st()
		return sts[k]
	for bl in items.buildings:
		var st: SurfaceTool = st_of.call(_mean(bl.outline))
		st.set_color(FAR_WALL)
		Geom.add_prism(st, bl.outline, 0.0, bl.height)
		st.set_color(FAR_ROOF)
		Geom.add_prism(st, bl.outline, bl.height, bl.height + 0.3)
	for sh in items.sheets:
		var st: SurfaceTool = st_of.call(_mean(sh[0]))
		st.set_color(FAR_SHEET)
		Geom.add_prism(st, sh[0], sh[1], sh[1] + 0.1)
	for pl in items.plants:
		var st: SurfaceTool = st_of.call(pl[1])
		var c: Vector2 = pl[1]
		var h: float = pl[2]
		if pl[0] == "date_palm":
			st.set_color(FAR_TRUNK)
			Geom.add_prism(st, circle(c, 0.25, 4), 0.0, h - 0.8, true)
			st.set_color(FAR_LEAF)
			Geom.add_prism(st, circle(c, h * 0.38, 6), h - 1.4, h - 0.6, true)
		else:
			var w := h * (0.45 if pl[0] == "tamarisk" else 0.6)
			st.set_color(FAR_LEAF.lightened(0.1) if pl[0] in ["tamarisk", "saltbush"] else FAR_LEAF)
			Geom.add_prism(st, circle(c, w, 6), h * (0.35 if pl[0] == "tamarisk" else 0.0), h, true)
	var far := Node3D.new()
	far.name = "far"
	root.add_child(far)
	var made := {}   # Vector2i -> MeshInstance3D
	for k in sts:
		var st: SurfaceTool = sts[k]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "far_%d_%d" % [k.x, k.y]
		mi.mesh = st.commit()
		mi.material_override = _mat("matte")
		mi.visibility_range_begin = HLOD_RANGE
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Lightmap.mark(mi, false)
		far.add_child(mi)
		made[k] = mi
	# the near pieces: each drawn only while its square's far mesh is not (Godot's HLOD)
	var stack: Array = scope.get_children()
	var parented := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == far or keep.has(String(n.name)):
			continue
		stack.append_array(n.get_children())
		var gi := n as GeometryInstance3D
		if gi == null or n.has_meta("hlod_keep"):
			continue
		var c := _plan_centre(gi)
		var k := Vector2i(int(floor(c.x / HLOD_CHUNK)), int(floor(c.y / HLOD_CHUNK)))
		if made.has(k):
			gi.visibility_parent = gi.get_path_to(made[k])
			parented += 1
	print("build: area %s: far view in %d squares, %d pieces drawn near only" % [id, made.size(), parented])
	return made.size()

## A drawn piece's centre in plan (plant coordinates), from its own box: the kit's cells carry it as meta `box`.
func _plan_centre(gi: GeometryInstance3D) -> Vector2:
	var box: AABB
	if gi.has_meta("box"):
		box = gi.get_meta("box")
	elif gi is MeshInstance3D and gi.mesh != null:
		box = _global_xf(gi) * gi.mesh.get_aabb()
	else:
		var p := _global_xf(gi).origin
		box = AABB(p, Vector3.ZERO)
	var c := box.get_center()
	return Vector2(c.x, -c.z)

## A node's transform from the area's root (the root stands at the origin).
static func _global_xf(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

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
		"operator_desk": return {"kind": "box", "size": Vector3(n.call("width", 3.2), 1.0, 1.4)}
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

## A road's surface (content: `road`'s `surface`) and its material: asphalt, paved concrete (walkways, cast in bays) or
## compacted gravel.
const ROAD_MATS := {"asphalt": "road_asphalt", "concrete": "yard", "gravel": "yard_gravel"}
func _surface(parent: Node3D, sf: Dictionary) -> void:
	# a building's floors (an operating deck) are painted as its ground floor is (_hall_floor)
	var inside: bool = sf.kind == "floor" or _in_building(sf)
	var mat := _mat("grating" if sf.deck == "grating" else ("deck_steel" if sf.deck == "steel" else ("pit" if sf.kind == "pit_floor" else (FLOOR_MATS[sf.get("finish", "epoxy")] if inside else "concrete"))))
	if sf.kind == "road":
		mat = _mat(ROAD_MATS.get(sf.get("surface", "asphalt"), "road_asphalt"))
	_slab(parent, sf.id, sf.outline, sf.holes, sf.z, sf.thick, mat)
	if inside and sf.deck == "concrete" and sf.z >= DECK_SOFFIT_MIN:
		_soffit(parent, sf)
	if sf.rails:
		var st := _st()
		var body := _body(parent, sf.id + "_rails")
		if _rails(st, body, sf) > 0:
			_mesh_node(body, "mesh", st, _mat("rail"))
		else:
			body.free()

## A building's upper floor seen from below: the slab cast on profiled steel decking (a light liner, as the roof's) on
## steel beams every BAY metres across its short side. Its underside was the floor's dark epoxy paint, black over the
## turbine hall's ground floor (polish pass). Drawn only, baked.
const DECK_SOFFIT_MIN := 2.5
const DECK_BEAM_D := 0.5
const DECK_BEAM_W := 0.25
func _soffit(parent: Node3D, sf: Dictionary) -> void:
	var z0: float = sf.z - sf.thick
	var liner := _st()
	for pc in Geom.decompose(sf.outline, sf.holes):
		Geom.add_prism(liner, pc, z0 - LINER_T, z0)
	var mi := _mesh_node(parent, sf.id + "_soffit", liner, _mat("liner"))
	mi.set_meta("soffit", true)
	var r := Geom.bbox(sf.outline)
	var along_x := r.size.x >= r.size.y
	var L := r.size.x if along_x else r.size.y
	var S := r.size.y if along_x else r.size.x
	var beams := _st()
	var n := 0
	var bays := maxi(1, int(round(L / BAY)))
	for k in range(1, bays):
		var t := L * k / bays
		var a := r.position + (Vector2(t, 0.0) if along_x else Vector2(0.0, t))
		var b := r.position + (Vector2(t, S) if along_x else Vector2(S, t))
		n += _member(beams, sf.outline, sf.holes + through_deck(sf), a, b, DECK_BEAM_W, z0 - LINER_T - DECK_BEAM_D,
			z0 - LINER_T)
	if n > 0:
		_mesh_node(parent, sf.id + "_beams", beams, _mat("roof_steel"), STEEL_TEXEL)

## The plan footprints of machines that pass down through a deck (a steam turbine's exhaust to the condenser below):
## its beams stop at them (a beam through the LP exhaust trunk, review).
func through_deck(sf: Dictionary) -> Array:
	var out: Array = []
	for k in equipment:
		var e: Dictionary = equipment[k]
		if e.part != "steam_turbine" or String(e.params.get("exhaust", "")) != "down" or absf(e.pos.z - sf.z) > 0.5:
			continue
		# an LP casing exhausts downward (an HP casing's exhaust goes on to the reheater: no trunk)
		if not Array(e.params.get("casings", [])).any(func(c): return String(c.get("kind", "")) in ["lp", "ip_lp"]):
			continue
		var sh := shape_of(e.part, e.params)
		var hw: float = sh.size.x * 0.75 + 0.3      # the exhaust hood is wider than the casing
		var hl: float = sh.size.y * 0.5 + 0.3
		out.append(Geom.poly([[-hw, -hl], [hw, -hl], [hw, hl], [-hw, hl]], Vector2(e.pos.x, e.pos.y), float(e.get("yaw", 0.0))))
	return out

## How far a deck's soffit and beams hang below its top (a lamp under it hangs below them).
func deck_depth(sf: Dictionary) -> float:
	var inside: bool = sf.kind == "floor" or _in_building(sf)
	if inside and sf.deck == "concrete" and sf.z >= DECK_SOFFIT_MIN:
		return float(sf.thick) + LINER_T + DECK_BEAM_D
	return float(sf.get("thick", 0.2))

## Whether a surface stands inside a building (its outline's centre in the building's plan, under its roof).
func _in_building(sf: Dictionary) -> bool:
	var mid := Vector2.ZERO
	for q in sf.outline:
		mid += q
	mid /= sf.outline.size()
	for b in buildings:
		if sf.z < float(b.height) and Geom.in_poly(mid, b.outline):
			return true
	return false

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
	if b.get("kks", "") != "":
		body.set_meta("kks", b.kks)   # found by its code (a tour's stop, a card), as equipment is
	body.set_meta("cladding", b.cladding)
	var walls := _st()
	var liner := _st()
	var trim := _st()
	var plinth := _st()
	var louvres := _st()
	var glass := _st()
	var glass_in := _st()
	var fittings := 0   # louvres and windows drawn
	var windows := 0
	var frame := _st()  # the hall's steel frame inside: columns, girts, the crane's runway
	var pg: PackedVector2Array = b.outline
	var h: float = b.height
	var clad: bool = b.cladding == "metal"
	var roof_holes: Array = []
	# a shell nobody goes into (no door opening: its doors are `locked`, PLANT3D.md §18.6; the camp's other blocks,
	# the store): its outside only, no liner, roof steel, floor or lamps inside (they cost the bake and the package and
	# are never seen)
	var shell: bool = not b.openings.any(func(o): return o.kind == "door")
	body.set_meta("shell", shell)
	# a low building (a camp block, an office, the gate house): its liner a flat ceiling with no steel under it and its
	# lamps panels flush under it (a hall's rafters and hung bells a metre over a 1.8 m walker read as a shed)
	var low: bool = h <= LOW_CEILING
	body.set_meta("low_ceiling", low)
	for i in pg.size():
		var a := pg[i]
		var c := pg[(i + 1) % pg.size()]
		var d := c - a
		var len := d.length()
		var u := d / len
		var inward := Vector2(-u.y, u.x)
		if not Geom.in_poly((a + c) * 0.5 + inward * 0.5, pg):
			inward = -inward
		var cuts: Array = []   # [t0, t1, z0, z1]
		var blocks: Array = []   # every opening in this wall, louvres and windows too: [t0, t1, z0, z1]
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
			var ow := float(o.width)
			var zb := oz if o.kind == "door" else oz - oh * 0.5   # a door's `at` is its sill; others' their centre
			blocks.append([t - ow * 0.5, t + ow * 0.5, zb, zb + oh])
			if o.kind in ["door", "pipe"]:
				cuts.append([t - ow * 0.5, t + ow * 0.5, zb, zb + oh])
			elif o.kind == "louvre":
				_louvre(louvres, a + u * (t - ow * 0.5), a + u * (t + ow * 0.5), -inward, zb, zb + oh)
				fittings += 1
			elif o.kind == "window":
				_window(louvres, glass, glass_in, a + u * (t - ow * 0.5), a + u * (t + ow * 0.5), inward, zb, zb + oh,
					LINER_T if clad else 0.0)
				fittings += 1
				windows += 1
		# the wall's face (along the edge t, up z) less its openings, in rectangles (openings may overlap)
		var holes: Array = []
		for cu in cuts:
			holes.append(Geom.rect(cu[0], cu[2], cu[1], cu[3]))
		for pc in Geom.decompose(Geom.rect(0.0, 0.0, len, h), holes):
			var r := Rect2(pc[0], Vector2.ZERO)
			for q in pc:
				r = r.expand(q)
			if r.size.x > 0.01 and r.size.y > 0.01:
				var p0 := a + u * r.position.x
				var p1 := a + u * r.end.x
				_wall_panel(walls, body, p0, p1, r.position.y, r.end.y, 0.25, piece_top(r, cuts, h))
				if clad and not shell:
					# the inner skin, light: a hall seen from inside (polish pass)
					var off := inward * (WALL_T * 0.5 + LINER_T * 0.5)
					_panel(liner, null, p0 + off, p1 + off, r.position.y, minf(r.end.y, h - LINER_T), LINER_T)
		_wall_trims(trim, plinth, a, c, -inward, cuts, h, clad)
		if clad and not shell:
			_frame_edge(frame, body, a, c, inward, blocks, b)
	_mesh_node(body, "walls", walls, _mat("wall_" + b.cladding))
	var roof := _st()
	for pc in Geom.decompose(pg, roof_holes):
		Geom.add_prism(roof, pc, h, h + 0.3)
		_convex(body, Geom.prism_points(pc, h, h + 0.3))
		if not shell:
			Geom.add_prism(liner, pc, h - LINER_T, h)
	_mesh_node(body, "roof", roof, _mat("roof"))
	# every building's roof from inside: the liner and the steel under it (a dark ceiling with nothing under it read as
	# a black void in every hall: polish pass)
	if not shell:
		_mesh_node(body, "liner", liner, _mat("liner"))
		var steel := _st()
		if not low and _roof_steel(steel, b, roof_holes) > 0:
			_mesh_node(body, "roof_steel", steel, _mat("roof_steel"), STEEL_TEXEL)
	if clad:
		_mesh_node(body, "trims", trim, _mat("trim"), Lightmap.SHEET_TEXEL * 2.0)
	_mesh_node(body, "plinth", plinth, _mat("concrete"))
	if fittings > 0:
		_mesh_node(body, "louvres", louvres, _mat("louvre"), Lightmap.SHEET_TEXEL * 2.0)
	if windows > 0:
		_mesh_node(body, "windows", glass, _mat("window"))
		if not shell:
			_mesh_node(body, "windows_in", glass_in, _mat("window_in"))
	if float(b.get("crane", 0.0)) > 0.0:
		_crane(body, frame, b)
	if clad and not shell:
		_mesh_node(body, "frame", frame, _mat("roof_steel"), STEEL_TEXEL)
	if not shell:
		_hall_floor(body, b)
		_lamps(body, b)
	# the site's and the camp's buildings (low, closed): what is seen only inside or through a door is drawn within
	# INSIDE_RANGE of the building (its box's centre, as Godot measures a range) (SITE.md §5: the far view's budget)
	if _area_pack(b.area) in ["site", "camp"]:
		var r := INSIDE_RANGE + Site._bbox(pg).size.length() * 0.5
		for n in ["liner", "roof_steel", "frame", "windows_in", "floor", "lamp_housings", "lamp_lenses"]:
			var mi := body.get_node_or_null(n) as GeometryInstance3D
			if mi != null:
				mi.visibility_range_end = r
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

const INSIDE_RANGE := 30.0
const LOW_CEILING := 5.0

func _area_pack(id: String) -> String:
	for a in areas:
		if a.id == id:
			return a.data.get("pack", "")
	return ""

## A building's walls: 0.25 m thick on their outline; a metal-clad hall's light inner skin (its liner) 3 cm thick
## against their inside and under the roof.
const WALL_T := 0.25
const LINER_T := 0.03
## A building's roof steel (portal frames' rafters across the short span, purlins along it under the liner),
## baked at a finer texel than walls (members 0.12 to 0.3 m across).
const STEEL_TEXEL := 0.2
const PURLIN_D := 0.2
const PURLIN_W := 0.12
const PURLIN_GAP := 1.8
const RAFTER_W := 0.3
const BAY := 6.0

## The rafters' depth for a span (about a fortieth of it, as a portal frame's: 0.4 to 1.0 m).
static func rafter_depth(span: float) -> float:
	return clampf(span / 40.0, 0.4, 1.0)

## A building's roof steel under its liner: rafters every BAY metres across the short span (the frames over the
## gable walls stand in them, not drawn), purlins every PURLIN_GAP along the long one; none across a roof opening.
## A dark ceiling with nothing under it read as a black void (polish pass). Returns the members drawn.
func _roof_steel(st: SurfaceTool, b: Dictionary, roof_holes: Array) -> int:
	var pg: PackedVector2Array = b.outline
	var h: float = b.height
	var g := steel_grid(b)
	var r: Rect2 = g.r
	var along_x: bool = g.along_x
	var L: float = g.L
	var S: float = g.S
	var rd := rafter_depth(S)
	var z_p1 := h - LINER_T
	var z_p0 := z_p1 - PURLIN_D
	var z_r1 := z_p0
	var z_r0 := z_r1 - rd
	var n := 0
	var at := func(t: float, s: float) -> Vector2:
		return r.position + (Vector2(t, s) if along_x else Vector2(s, t))
	for k in range(1, g.bays):
		var t: float = L * k / g.bays
		if S >= TRUSS_MIN and b.get("cladding", "metal") == "metal":
			n += _truss(st, pg, roof_holes, at.call(t, 0.0), at.call(t, S), z_r1, truss_depth(S))
		else:
			n += _member(st, pg, roof_holes, at.call(t, 0.0), at.call(t, S), RAFTER_W, z_r0, z_r1)
	for k in range(1, g.rows):
		var s2: float = S * k / g.rows
		n += _member(st, pg, roof_holes, at.call(0.0, s2), at.call(L, s2), PURLIN_W, z_p0, z_p1)
	return n

## The roof steel's layout: {r (the outline's box), along_x (the long axis is x), L, S (long and short sides), bays
## (rafters at L·k/bays, k = 1 … bays − 1), rows (purlins at S·k/rows)}.
func steel_grid(b: Dictionary) -> Dictionary:
	var r := Geom.bbox(b.outline)
	var along_x := r.size.x >= r.size.y          # the long axis: purlins run along it, rafters across
	var L := r.size.x if along_x else r.size.y
	var S := r.size.y if along_x else r.size.x
	return {"r": r, "along_x": along_x, "L": L, "S": S, "bays": maxi(2, int(round(L / BAY))),
		"rows": maxi(2, int(round(S / PURLIN_GAP)))}

## A steel member from a to b (plan), w wide, z0 to z1, kept inside the walls' inner faces and out of roof openings.
func _member(st: SurfaceTool, pg: PackedVector2Array, roof_holes: Array, a: Vector2, b: Vector2, w: float, z0: float, z1: float) -> int:
	var n := 0
	for sp in _member_spans(pg, roof_holes, a, b):
		var p0: Vector2 = sp[0]
		var p1: Vector2 = sp[1]
		var dv := (p1 - p0).normalized()
		Geom.add_prism(st, Geom._strip(p0, p1, Vector2(-dv.y, dv.x), w), z0, z1)
		n += 1
	return n

## A wide hall's roof is carried by trusses, not solid rafters (the exposed dark trusses every turbine hall shows):
## from this span up, a rafter line is a truss truss_depth() deep: top and bottom chords, posts and diagonals.
const TRUSS_MIN := 18.0
const CHORD := 0.25

## A truss's depth for a span: about a sixteenth of it, 1.2 to 3 m (a deeper one would meet the crane's trolley).
static func truss_depth(span: float) -> float:
	return clampf(span / 16.0, 1.2, 3.0)

## A roof truss along a to b (plan), its top at z_top, `depth` deep: chords, a post at every panel point and a
## diagonal in every panel (a Howe web: the diagonals rise towards the middle, the panels about as long as the truss is deep). Returns the trusses.
func _truss(st: SurfaceTool, pg: PackedVector2Array, roof_holes: Array, a: Vector2, b: Vector2, z_top: float, depth: float) -> int:
	var n := 0
	for sp in _member_spans(pg, roof_holes, a, b):
		var p0: Vector2 = sp[0]
		var p1: Vector2 = sp[1]
		var L := p0.distance_to(p1)
		if L < depth * 2.0:
			Geom.add_prism(st, Geom._strip(p0, p1, Vector2(-(p1 - p0).y, (p1 - p0).x).normalized(), RAFTER_W), z_top - rafter_depth(L), z_top)
			n += 1
			continue
		var dv := (p1 - p0) / L
		var across := Vector2(-dv.y, dv.x)
		var zb := z_top - depth
		Geom.add_prism(st, Geom._strip(p0, p1, across, CHORD), z_top - CHORD, z_top)            # top chord
		Geom.add_prism(st, Geom._strip(p0, p1, across, CHORD * 0.8), zb, zb + CHORD * 0.8)      # bottom chord
		var panels := maxi(2, int(round(L / depth)))
		var pl := L / panels
		for k in panels + 1:
			var p := p0 + dv * (pl * k)
			var q0 := p - dv * (0.06 if k > 0 else 0.0)
			var q1 := p + dv * (0.06 if k < panels else 0.0)
			Geom.add_prism(st, Geom._strip(q0, q1, across, CHORD * 0.6), zb + CHORD * 0.8, z_top - CHORD)
			if k < panels:
				# the diagonals rise towards the middle from either end (a Howe web)
				var down := (k < panels / 2.0)
				var q := p0 + dv * (pl * (k + 1))
				var za := zb + CHORD * 0.8 if down else z_top - CHORD - 0.15
				var zq := z_top - CHORD - 0.15 if down else zb + CHORD * 0.8
				_slope_panel(st, null, p, q, za, zq, 0.15, CHORD * 0.6)
		n += 1
	return n

## The pieces of a roof member's line from a to b inside the walls' inner faces and out of roof openings: [p0, p1].
func _member_spans(pg: PackedVector2Array, roof_holes: Array, a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), pg):
		var pieces: Array = [seg]
		for hole in roof_holes:
			var next: Array = []
			for pc in pieces:
				next.append_array(Geometry2D.clip_polyline_with_polygon(pc, hole))
			pieces = next
		for pc in pieces:
			var p0: Vector2 = pc[0]
			var p1: Vector2 = pc[pc.size() - 1]
			var dl := p0.distance_to(p1)
			if dl < 0.5:
				continue
			var dv := (p1 - p0) / dl
			# kept off the walls: a wall's inner face and its liner are WALL_T / 2 + LINER_T in from its line
			var trim_end := WALL_T * 0.5 + LINER_T + 0.01
			p0 += dv * (trim_end if Geom.in_poly(p0 - dv * 0.2, pg) == false else 0.0)
			p1 -= dv * (trim_end if Geom.in_poly(p1 + dv * 0.2, pg) == false else 0.0)
			out.append([p0, p1])
	return out

## The outside of a wall from a to c (`out` its outward normal). Metal cladding: a concrete plinth along its foot,
## broken at doors and pipe openings that reach it, a flashing over its top edge (the roof's verge) and down both its
## corners. A concrete wall: a coping along its top.
## They break the plain box a clad building was (the circulating water pump house read as a dim box: polish pass).
const PLINTH_H := 0.6
const TRIM_H := 0.35
func _wall_trims(trim: SurfaceTool, plinth: SurfaceTool, a: Vector2, c: Vector2, out: Vector2, cuts: Array, h: float, metal: bool) -> void:
	var len := a.distance_to(c)
	var u := (c - a) / len
	var face := out * (WALL_T * 0.5)
	if not metal:
		_panel(plinth, null, a + face + out * 0.04 - u * 0.08, c + face + out * 0.04 + u * 0.08, h - 0.25, h + 0.4, 0.08)
		return
	# the plinth: 6 cm proud of the cladding, less the openings that come down to it
	var spans: Array = [[-0.06, len + 0.06]]   # round the corners
	for cu in cuts:
		if float(cu[2]) < PLINTH_H:
			var next: Array = []
			for sp in spans:
				if cu[1] <= sp[0] or cu[0] >= sp[1]:
					next.append(sp)
					continue
				if cu[0] > sp[0]:
					next.append([sp[0], cu[0]])
				if cu[1] < sp[1]:
					next.append([cu[1], sp[1]])
			spans = next
	for sp in spans:
		if sp[1] - sp[0] > 0.05:
			_panel(plinth, null, a + u * sp[0] + face + out * 0.03, a + u * sp[1] + face + out * 0.03, 0.0, PLINTH_H, 0.06)
	# the verge flashing over the wall's top and the roof's edge, and the corner flashings
	_panel(trim, null, a + face + out * 0.02 - u * 0.04, c + face + out * 0.02 + u * 0.04, h - TRIM_H, h + 0.38, 0.04)
	_panel(trim, null, a + face + out * 0.02 - u * 0.04, a + face + out * 0.02 + u * 0.22, PLINTH_H, h - TRIM_H, 0.04)
	_panel(trim, null, c + face + out * 0.02 - u * 0.22, c + face + out * 0.02 + u * 0.04, PLINTH_H, h - TRIM_H, 0.04)

## A louvre on a wall's outside from a to b (`out` its outward normal), z0 to z1: a frame and blades over a dark
## recess, proud of the cladding (drawn only; the wall stays whole behind it).
func _louvre(st: SurfaceTool, a: Vector2, b: Vector2, out: Vector2, z0: float, z1: float) -> void:
	var face := out * (WALL_T * 0.5)
	var u := (b - a).normalized()
	# the recess's back (dark grey galvanised in shade reads as the louvre's depth) and the frame round it
	_panel(st, null, a + face + out * 0.01, b + face + out * 0.01, z0, z1, 0.02)
	for side in [[a, a + u * 0.08], [b - u * 0.08, b]]:
		_panel(st, null, side[0] + face + out * 0.08, side[1] + face + out * 0.08, z0, z1, 0.14)
	_panel(st, null, a + face + out * 0.08, b + face + out * 0.08, z0, z0 + 0.08, 0.14)
	_panel(st, null, a + face + out * 0.08, b + face + out * 0.08, z1 - 0.08, z1, 0.14)
	# blades every 0.1 m, each leaning out and down (a thin sloped plate)
	var z := z0 + 0.12
	while z < z1 - 0.1:
		_slope_blade(st, a + u * 0.08 + face, b - u * 0.08 + face, out, z)
		z += 0.1

## One louvre blade from a to b at height z: a plate from 0.03 m out at z + 0.06 to 0.13 m out at z, 1 cm thick.
func _slope_blade(st: SurfaceTool, a: Vector2, b: Vector2, out: Vector2, z: float) -> void:
	var lo_a := Geom.g([a.x + out.x * 0.13, a.y + out.y * 0.13, z])
	var lo_b := Geom.g([b.x + out.x * 0.13, b.y + out.y * 0.13, z])
	var hi_a := Geom.g([a.x + out.x * 0.03, a.y + out.y * 0.03, z + 0.06])
	var hi_b := Geom.g([b.x + out.x * 0.03, b.y + out.y * 0.03, z + 0.06])
	var dn := Vector3(0, -0.01, 0)
	# the top face must face up and out whichever way the outline runs (_tri: clockwise is the front)
	if (hi_b - hi_a).cross(lo_a - hi_a).y < 0.0:
		Geom._quad(st, hi_a, hi_b, lo_b, lo_a)
		Geom._quad(st, lo_a + dn, lo_b + dn, hi_b + dn, hi_a + dn)
	else:
		Geom._quad(st, hi_b, hi_a, lo_a, lo_b)
		Geom._quad(st, lo_b + dn, lo_a + dn, hi_a + dn, hi_b + dn)

## A window in a wall from a to b (`inward` the hall's side), z0 to z1: a frame and glass on both faces (drawn only;
## the wall stays whole). Outside the glass reflects; inside it is the daylight beyond (`window_in`, a little light of
## its own that the bake spreads into the hall): dark panes in a lit hall read as holes.
func _window(frame: SurfaceTool, glass: SurfaceTool, glass_in: SurfaceTool, a: Vector2, b: Vector2, inward: Vector2, z0: float, z1: float, liner_t: float) -> void:
	var u := (b - a).normalized()
	for side in [-1.0, 1.0]:
		var face: Vector2 = inward * (side * (WALL_T * 0.5 + (liner_t if side > 0 else 0.0)))
		var n: Vector2 = inward * side
		_panel(glass if side < 0.0 else glass_in, null, a + face + n * 0.01, b + face + n * 0.01, z0, z1, 0.02)
		for e in [[a, a + u * 0.07], [b - u * 0.07, b]]:
			_panel(frame, null, e[0] + face + n * 0.03, e[1] + face + n * 0.03, z0, z1, 0.05)
		_panel(frame, null, a + face + n * 0.03, b + face + n * 0.03, z0, z0 + 0.07, 0.05)
		_panel(frame, null, a + face + n * 0.03, b + face + n * 0.03, z1 - 0.07, z1, 0.05)
		_panel(frame, null, (a + b) * 0.5 - u * 0.03 + face + n * 0.03, (a + b) * 0.5 + u * 0.03 + face + n * 0.03, z0, z1, 0.05)

## Where water running down a wall piece (r: along the edge x, up y) comes from: the bottom of the lowest opening
## above it, else the wall's top h. The wall is cut into slabs at every opening's height, so each slab's own top
## made a dark band and new streaks at a door's head along the whole wall (adversarial review, second pass).
static func piece_top(r: Rect2, cuts: Array, h: float) -> float:
	var top := h
	for cu in cuts:
		if cu[0] < r.end.x - 0.001 and cu[1] > r.position.x + 0.001 and cu[2] >= r.end.y - 0.001:
			top = minf(top, cu[2])
	return top

## A hall's floor on the ground (z = 0): painted, not the yard's bare concrete. Drawn only (the ground's slab is the
## walkable one) 4 mm over it, less the pits and stairwells inside the hall.
const HALL_FLOOR_T := 0.004
## A floor's finish (content: a building's `floor`, a deck's `finish`) and the material it is drawn with: painted,
## glazed tiles (a turbine hall's operating floor and walkways), bare concrete (a ground floor under a deck, a pump
## house: cracks, dust, tyre marks).
const FLOOR_MATS := {"epoxy": "hall_floor", "tile": "floor_tile", "concrete": "floor_concrete", "vinyl": "floor_vinyl"}
func _hall_floor(body: Node, b: Dictionary) -> int:
	var pg: PackedVector2Array = b.outline
	var holes: Array = []
	for h in pits.map(func(p): return p.outline) + ground_cuts():
		# a pit or stairwell inside the hall is a hole in its floor; one across the hall's wall would be covered by
		# the floor (the outline test, not the boxes': an L-shaped hall's box holds what is outside it)
		if not Geometry2D.intersect_polygons(pg, h).is_empty():
			if Geometry2D.clip_polygons(h, pg).is_empty():
				holes.append(h)
			else:
				_err("pit_across_hall", String(b.get("id", "")), "a pit or stairwell crosses the hall's outline: its painted floor would cover the opening")
	var st := _st()
	var n := 0
	for pc in Geom.decompose(pg, holes):
		Geom.add_prism(st, pc, 0.0, HALL_FLOOR_T, false)
		n += 1
	if n > 0:
		_mesh_node(body, "floor", st, _mat(FLOOR_MATS[b.get("floor", "epoxy")]), Lightmap.GROUND_TEXEL)
	return n

## High-bay lamps under a building's roof (a hall is lit by its lamps, not by the sky through its walls): a grid
## about 0.6 × the height apart (6 to 10 m), each a housing, a lit lens and a light the bake takes in whole
## (BAKE_STATIC: its light and shadow are in the lightmap; the app drops the light node once a bake is there, the
## pieces that move take the sky's light: app/main.gd). A high-bay luminaire throws its light down in a cone: pools
## on the floor under each lamp, the walls and corners darker, lit by what the floor bounces (the omni lights of the
## first pass lit every hall evenly and washed its floor out: second realism pass).
## A lamp's light on the floor under it, as a share of the sun's irradiance (the sun's energy is 1): its energy is
## this times the square of its height over the floor (inverse-square falloff, the lamp's `spot_attenuation` 2).
## A hall reads darker than the yard outside, as it does to the eye coming in; set by eye against the exposure.
const LAMP_FLOOR := 1.1
## What the reflector lets out sideways (its open bottom, the lamp's glow): an even dim light round each lamp, so walls
## and the space between pools are not black; as a share of the sun's irradiance at the floor. A wide cone down, not an
## omni light: an omni lit the ceiling a few tenths of a metre from each lamp, and those hot spots, met by few of the
## bake's bounce rays, came out as bright blotches over every floor and wall of the halls (second realism pass).
const LAMP_SPILL := 0.1
## The spill's cone, degrees from the axis: down to the walls' foot and up them, never the ceiling.
const LAMP_SPILL_ANGLE := 80.0
## A lamp's reach: the hall's height and as far again, so the floor and a pit below it are lit (a reach of 1.4 × the
## height left the turbine hall's pit black: adversarial review, 2026-10-16)
const LAMP_REACH := 2.4
## The cone: its pool on the floor about 0.4 of the lamps' spacing in radius (pools apart, darker floor between them,
## not an even floor: 0.6 merged them in the lower halls), 10 to 40 degrees from the axis to the edge.
const LAMP_POOL := 0.42
## The height of the floor under plan point p and below height z: the highest walkable surface there at least 2 m
## below z (a deck, a mezzanine), else the ground (0). A lamp's energy is set from its height over that floor: from
## the ground, a lamp over the turbine hall's 12 m deck put 2.6 × the light meant on it (adversarial review).
func floor_below(p: Vector2, z: float) -> float:
	var f := 0.0
	for sf in surfaces:
		if sf.z < z - 2.0 and sf.z > f and Geom.in_region(p, sf.outline, sf.holes):
			f = sf.z
	return f

func _lamps(body: Node, b: Dictionary) -> int:
	var pg: PackedVector2Array = b.outline
	var h: float = b.height
	var housing := _st()
	var lens := _st()
	var n := 0
	# under the roof, over the whole hall: each hung on a short rod from a purlin, midway between two rafters, as high
	# as it hung before the steel (whatever runs under the roof keeps its clearance), none under a roof opening
	var places: Array = roof_lamp_places(b)
	var low: bool = h <= LOW_CEILING
	for c in places[0]:
		if low:
			# a panel flush under the ceiling (the liner)
			var _p := _lamp(body, housing, lens, c, h - LINER_T - PANEL_T, places[1], h, n)
			n += 1
			continue
		var panel := _lamp(body, housing, lens, c, h - LAMP_DROP, places[1], h, n)
		Geom.add_prism(housing, Geom.rect(c.x - 0.015, c.y - 0.015, c.x + 0.015, c.y + 0.015),
			h - LAMP_DROP + (PANEL_T if panel else 0.25), h - LINER_T - PURLIN_D)
		n += 1
	# under each deck of the hall (an operating floor, a building's upper floor): the floor below it is out of the
	# roof lamps' reach, as a real hall's ground floor is lit by lamps under the deck (adversarial review)
	for sf in surfaces:
		var z: float = sf.z - deck_depth(sf) - 0.3
		if sf.z < 2.5 or sf.z > h - 2.0 or not Geom.in_region(_mean(sf.outline), pg, []):
			continue
		var gap := clampf(z * 0.8, 4.0, 10.0)
		var cs := _lamp_grid(sf.outline, sf.holes, gap)
		if cs.size() < 2:
			continue           # a small platform: the roof's lamps reach round it
		var machines := through_deck(sf)   # none inside a machine that passes down through the deck (review)
		for c in cs:
			if Geom.in_region(c, sf.outline, sf.holes + machines) and Geom.in_region(c, pg, []):
				var _panel := _lamp(body, housing, lens, c, z, gap, h, n)
				n += 1
	if n > 0:
		_mesh_node(body, "lamp_housings", housing, _mat("steel_dark"))
		_mesh_node(body, "lamp_lenses", lens, _mat("lamp_white"))
	return n

## A roof lamp's housing hangs this far below the roof, as before the steel (0.6 m: whatever runs under the roof keeps
## its clearance), its top 0.12 m under the purlin it hangs from.
const LAMP_DROP := 0.6

## Where a building's roof lamps hang (plan): evenly, about 0.6 × the height apart (6 to 10 m): along the long axis
## in the middle of every k-th bay between two rafters, across it under every k-th purlin, each set centred in the
## hall; none under a roof opening. [places, spacing].
func roof_lamp_places(b: Dictionary) -> Array:
	var pg: PackedVector2Array = b.outline
	var g := steel_grid(b)
	var gap := clampf(float(b.height) * 0.6, 6.0, 10.0)
	var out: Array = []
	var bay: float = g.L / g.bays
	var kb := maxi(1, int(round(gap / bay)))
	var nb := maxi(1, int(floor(float(g.bays - 1) / kb)) + 1)
	var b0 := int(floor((g.bays - 1 - (nb - 1) * kb) * 0.5))
	var row: float = g.S / g.rows
	var kr := maxi(1, int(round(gap / row)))
	var lines: int = g.rows - 1                     # purlin lines 1 … rows − 1
	var nr := maxi(1, int(floor(float(lines - 1) / kr)) + 1)
	var r0 := 1 + int(floor((lines - 1 - (nr - 1) * kr) * 0.5))
	var holes := roof_holes_of(b)
	for i in nb:
		var t: float = (b0 + i * kb + 0.5) * bay
		for j in nr:
			var s: float = (r0 + j * kr) * row
			var c: Vector2 = g.r.position + (Vector2(t, s) if g.along_x else Vector2(s, t))
			if Geom.in_region(c, pg, holes):
				out.append(c)
	return [out, maxf(kb * bay, kr * row)]

## A building's roof openings (an intake on the roof): their plan rectangles.
func roof_holes_of(b: Dictionary) -> Array:
	var out: Array = []
	for o in b.openings:
		if float(o.at[2]) >= float(b.height) - 0.5:
			var oc := _opening_plan(b, o)
			var w2 := float(o.width) * 0.5
			var h2 := float(o.height) * 0.5
			out.append(Geom.rect(oc.x - w2, oc.y - h2, oc.x + w2, oc.y + h2))
	return out

static func _mean(pg: PackedVector2Array) -> Vector2:
	var m := Vector2.ZERO
	for q in pg:
		m += q
	return m / maxf(1.0, pg.size())

## A grid of lamp places over an outline's box, about `gap` apart, the outer ones half a gap in.
static func _lamp_grid(pg: PackedVector2Array, _holes: Array, gap: float) -> Array:
	var r := Rect2(pg[0], Vector2.ZERO)
	for q in pg:
		r = r.expand(q)
	var nx := maxi(1, int(round(r.size.x / gap)))
	var ny := maxi(1, int(round(r.size.y / gap)))
	var out: Array = []
	for i in nx:
		for j in ny:
			out.append(r.position + Vector2(r.size.x * (i + 0.5) / nx, r.size.y * (j + 0.5) / ny))
	return out

## The floor a lamp at c, height z, lights: the highest floor under it or within half a metre (a lamp right over a
## deck's edge is set for the deck: from the ground, the deck's half of its pool got 2.6 × the light meant on it).
func lamp_floor(c: Vector2, z: float) -> float:
	var f := floor_below(c, z)
	for o in [Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
		f = maxf(f, floor_below(c + o, z))
	return f

## One high-bay lamp at c, its housing's underside at height z: housing, lit lens, the downlight and its spill.
## Under a low ceiling (an office, a camp block: the lamp under PANEL_BELOW metres over its floor) a lamp is a square
## panel, as such rooms are lit, not a high bay's bell (a tenth of its vertices: the site's buildings hold hundreds).
const PANEL_BELOW := 4.5
const PANEL_T := 0.06
## Returns whether it is a panel.
func _lamp(body: Node, housing: SurfaceTool, lens: SurfaceTool, c: Vector2, z: float, gap: float, h: float, n: int) -> bool:
	var panel := z - lamp_floor(c, z) < PANEL_BELOW
	if panel:
		Geom.add_prism(housing, Geom.rect(c.x - 0.3, c.y - 0.3, c.x + 0.3, c.y + 0.3), z, z + PANEL_T)
		Geom.add_prism(lens, Geom.rect(c.x - 0.27, c.y - 0.27, c.x + 0.27, c.y + 0.27), z - 0.01, z)
	else:
		# a round high-bay luminaire: the reflector's bell and the driver's housing over it, the lens under it
		Geom.add_prism(housing, circle(c, 0.28, 16), z, z + 0.12)
		Geom.add_prism(housing, circle(c, 0.17, 12), z + 0.12, z + 0.25)
		Geom.add_prism(lens, circle(c, 0.24, 16), z - 0.03, z)
	var l := SpotLight3D.new()
	l.name = "lamp_%d" % n
	l.position = Geom.g([c.x, c.y, z - 0.2])
	l.rotation_degrees = Vector3(-90, 0, 0)   # a spot shines along its -z: straight down
	l.spot_range = h * LAMP_REACH
	var d := z - 0.2 - lamp_floor(c, z - 0.2)   # to the floor under it: a deck's, or the ground
	l.spot_attenuation = 2.0
	l.spot_angle = clampf(rad_to_deg(atan(LAMP_POOL * gap / d)), 10.0, 40.0)
	l.spot_angle_attenuation = 3.0
	l.light_energy = LAMP_FLOOR * d * d
	l.set_meta("floor", z - 0.2 - d)
	var spill := SpotLight3D.new()
	spill.name = "spill"
	spill.spot_range = l.spot_range
	spill.spot_attenuation = 2.0
	spill.spot_angle = LAMP_SPILL_ANGLE
	spill.spot_angle_attenuation = 1.5
	spill.light_energy = LAMP_SPILL * d * d
	spill.light_color = Color(1.0, 0.95, 0.86)
	spill.light_bake_mode = Light3D.BAKE_STATIC
	spill.shadow_enabled = false
	spill.add_to_group("baked_lights", true)
	l.add_child(spill)
	l.light_color = Color(1.0, 0.95, 0.86)
	l.light_bake_mode = Light3D.BAKE_STATIC
	l.shadow_enabled = false
	l.add_to_group("baked_lights", true)
	body.add_child(l)
	return panel

## A circle of n sides round c (plan), radius r: a round piece's outline.
static func circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pg := PackedVector2Array()
	for i in n:
		var ang := TAU * i / n
		pg.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pg

## Lamps along a pit's walls just under its rim, every 6 m (a pit is out of reach of the roof's lamps' direct light):
## baked like the halls' lamps.
func _pit_lamps(body: Node, p: Dictionary) -> int:
	var pg: PackedVector2Array = p.outline
	var n := 0
	var lens := _st()
	for i in pg.size():
		var a := pg[i]
		var c := pg[(i + 1) % pg.size()]
		var k := maxi(1, int(round(a.distance_to(c) / 6.0)))
		var inward := Vector2((c - a).y, -(c - a).x).normalized()
		if not Geom.in_poly((a + c) * 0.5 + inward * 0.5, pg):
			inward = -inward
		for j in k:
			var q := a.lerp(c, (j + 0.5) / k) + inward * 0.35
			var z := -0.4
			Geom.add_prism(lens, Geom.rect(q.x - 0.15, q.y - 0.15, q.x + 0.15, q.y + 0.15), z - 0.05, z)
			var l := OmniLight3D.new()
			l.name = "pit_lamp_%d" % n
			l.position = Geom.g([q.x, q.y, z - 0.1])
			l.omni_range = float(p.depth) * 2.5 + 4.0
			l.omni_attenuation = 0.7
			l.light_energy = 0.6
			l.light_color = Color(1.0, 0.95, 0.86)
			l.light_bake_mode = Light3D.BAKE_STATIC
			l.shadow_enabled = false
			l.add_to_group("baked_lights", true)
			body.add_child(l)
			n += 1
	if n > 0:
		_mesh_node(body, "lamp_lenses", lens, _mat("lamp_white"))
	return n

func _pit(parent: Node3D, p: Dictionary) -> void:
	var body := _body(parent, p.id + "_walls")
	_pit_lamps(body, p)
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
	if pr.get("locked", false):
		_locked_door(parent, s, pr)
		return
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
	mi.mesh = Mat.plant_mesh(bm)   # the plant's vertex format: no pipelines of its own (decision 0060)
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

## A door that never opens (a shell's: `locked`): its leaf on the wall's outer face (the door's yaw points out of its
## building), solid, drawn with the doors' material; the wall stays whole behind it.
func _locked_door(parent: Node3D, s: Dictionary, pr: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = s.id
	var out := Geom.heading(float(s.get("yaw", 0)))
	var at := _v3(s.at)
	body.position = Geom.g([at.x + out.x * (WALL_T * 0.5 + 0.04), at.y + out.y * (WALL_T * 0.5 + 0.04), at.z])
	body.rotation.y = Geom.yaw_rad(float(s.get("yaw", 0)))
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.name = "panel"
	var bm := BoxMesh.new()
	bm.size = Vector3(float(pr.width), float(pr.height), 0.08)
	mi.mesh = Mat.plant_mesh(bm)
	mi.position.y = float(pr.height) * 0.5
	mi.material_override = _mat("door")
	Lightmap.mark(mi, false)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position = mi.position
	body.add_child(cs)

func _slab_part(parent: Node3D, s: Dictionary) -> void:
	var pr := params_of("slab", s.get("params", {}))
	var at := _v3(s.at)
	var pg := Geom.poly(pr.outline, Vector2(at.x, at.y), float(s.get("yaw", 0)))
	_slab(parent, s.id, pg, [], at.z + float(pr.thickness), float(pr.thickness), _mat("concrete"))

## A fence: steel palisade, as round a transformer yard: posts every 2.75 m, two rails on the inside, and pales with
## a pointed top a hand's width apart (a solid galvanised sheet read as a blotchy wall, worst on the phone: polish pass).
## Solid to the walker over its whole height (a panel along the route); baked at a fine texel.
const PALE_W := 0.065
const PALE_GAP := 0.14
const POST_GAP := 2.75
func _fence(parent: Node3D, s: Dictionary) -> void:
	var pr := params_of("fence", s.get("params", {}))
	var at := _v3(s.at)
	var body := _body(parent, s.id)
	var st := _st()
	var pts: Array = pr.route
	var fh := float(pr.height)
	for i in range(pts.size() - 1):
		var a := at + Geom.turn(_v3(pts[i]), float(s.get("yaw", 0)))
		var b := at + Geom.turn(_v3(pts[i + 1]), float(s.get("yaw", 0)))
		var a2 := Vector2(a.x, a.y)
		var b2 := Vector2(b.x, b.y)
		var len := a2.distance_to(b2)
		if len < 0.01:
			continue
		var u := (b2 - a2) / len
		var n := Vector2(-u.y, u.x)
		_panel(null, body, a2, b2, a.z, a.z + fh, 0.05)   # the walker's: solid
		st.set_color(top_colour(a.z + fh))                  # the streaks hang from the fence's top (top_edge)
		# posts (the route's corners have one each)
		var posts := maxi(1, int(ceil(len / POST_GAP)))
		for k in posts + 1:
			var p := a2.lerp(b2, float(k) / posts) + n * 0.06
			Geom.add_prism(st, Geom.rect(p.x - 0.05, p.y - 0.05, p.x + 0.05, p.y + 0.05), a.z, a.z + fh - 0.1)
		# rails (an angle's face) on the posts' side, low and high
		for z in [0.35, fh - 0.45]:
			_panel(st, null, a2 + n * 0.035, b2 + n * 0.035, a.z + z, a.z + z + 0.06, 0.03)
		# pales
		var count := maxi(1, int(floor(len / PALE_GAP)))
		var t0 := (len - (count - 1) * PALE_GAP) * 0.5
		for k in count:
			_pale(st, a2 + u * (t0 + k * PALE_GAP), u, n * -0.01, a.z + 0.05, a.z + fh)
	_mesh_node(body, "mesh", st, _mat("fence"), Lightmap.SHEET_TEXEL)   # thin pieces: a fine texel

## One pale centred at p (plan), along the fence u, standing off by `off`: PALE_W wide, 3 cm thick, z0 to z1 with a
## pointed top (its last 8 cm).
func _pale(st: SurfaceTool, p: Vector2, u: Vector2, off: Vector2, z0: float, z1: float) -> void:
	var nrm := Vector2(-u.y, u.x)
	var prof := [[-0.5, z0], [0.5, z0], [0.5, z1 - 0.08], [0.0, z1], [-0.5, z1 - 0.08]]
	var fr: Array = []
	var bk: Array = []
	for q in prof:
		var c: Vector2 = p + off + u * (float(q[0]) * PALE_W)
		fr.append(Geom.g([c.x + nrm.x * 0.015, c.y + nrm.y * 0.015, q[1]]))
		bk.append(Geom.g([c.x - nrm.x * 0.015, c.y - nrm.y * 0.015, q[1]]))
	for i in range(1, 4):
		Geom._tri(st, fr[0], fr[i], fr[i + 1])
		Geom._tri(st, bk[0], bk[i + 1], bk[i])
	for i in 5:
		var j := (i + 1) % 5
		Geom._quad(st, fr[i], bk[i], bk[j], fr[j])

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

# ------------------------------------------------------------------ a hall's steel frame and its crane

## A metal-clad hall's frame seen from inside (the photographs of halls in service: dark columns between light wall
## panels, girts in horizontal bands, an overhead crane on its runway): a column every BAY metres along each wall (at
## the rafters' ends on the long walls, the corners too), girts every GIRT_GAP metres up between them, none across
## an opening (a door, a window, a louvre or a pipe). Columns are solid (a walker meets them), girts drawn only.
const COLUMN_W := 0.5
const COLUMN_D := 0.45
const GIRT_GAP := 4.5
const GIRT_H := 0.2
const GIRT_D := 0.12
func _frame_edge(st: SurfaceTool, body: Node, a: Vector2, c: Vector2, inward: Vector2, blocks: Array, b: Dictionary) -> void:
	var len := a.distance_to(c)
	var u := (c - a) / len
	var h: float = b.height
	var face := inward * (WALL_T * 0.5 + LINER_T)   # the liner's inner face
	var top := h - LINER_T - PURLIN_D
	var n := maxi(1, int(round(len / BAY)))
	var cols: Array = []
	var cols_at: Array = b.get("_cols", [])
	for k in n + 1:
		var t := column_place(clampf(len * k / n, COLUMN_W * 0.5, len - COLUMN_W * 0.5), len, blocks)
		if t < 0.0:
			continue   # no room beside the opening (a wide door, a pipe's way): no column there
		cols.append(t)
		var p := a + u * t + face
		cols_at.append(p + inward * COLUMN_D * 0.5)
		var pc := PackedVector2Array([p - u * COLUMN_W * 0.5, p + u * COLUMN_W * 0.5, p + u * COLUMN_W * 0.5 + inward * COLUMN_D,
			p - u * COLUMN_W * 0.5 + inward * COLUMN_D])
		Geom.add_prism(st, pc, 0.0, top)
		_convex(body, Geom.prism_points(pc, 0.0, top))
	b["_cols"] = cols_at
	# girts: from 3 m up every GIRT_GAP, along the whole wall, broken at openings
	var z := 3.0
	while z < h - 2.0:
		var spans: Array = [[0.05, len - 0.05]]
		for o in blocks:
			if o[2] < z + GIRT_H + 0.15 and o[3] > z - 0.15:
				var next: Array = []
				for sp in spans:
					if o[1] + 0.1 <= sp[0] or o[0] - 0.1 >= sp[1]:
						next.append(sp)
						continue
					if o[0] - 0.1 > sp[0]:
						next.append([sp[0], o[0] - 0.1])
					if o[1] + 0.1 < sp[1]:
						next.append([o[1] + 0.1, sp[1]])
				spans = next
		for sp in spans:
			if sp[1] - sp[0] > 0.3:
				_panel(st, null, a + u * sp[0] + face + inward * GIRT_D * 0.5, a + u * sp[1] + face + inward * GIRT_D * 0.5,
					z, z + GIRT_H, GIRT_D)
		z += GIRT_GAP

## Where a column wanted at t along a wall stands: there, or just beside an opening it would stand in (any opening, at
## any height: a window, a louvre, a pipe's way, review), whichever side is nearer within 2.5 m; -1 when neither is
## free (inside the wall's length).
static func column_place(t: float, len: float, blocks: Array) -> float:
	var hw := COLUMN_W * 0.5 + 0.1
	var free := func(x: float) -> bool:
		return x >= COLUMN_W * 0.5 and x <= len - COLUMN_W * 0.5 and not blocks.any(func(o): return o[0] < x + hw and o[1] > x - hw)
	if free.call(t):
		return t
	var best := -1.0
	for o in blocks:
		for x in [float(o[0]) - hw - 0.05, float(o[1]) + hw + 0.05]:
			if absf(x - t) <= 2.5 and free.call(x) and (best < 0.0 or absf(x - t) < absf(best - t)):
				best = x
	return best

## An overhead travelling crane (content: the building's `crane`, its rail height): the runway girders on corbels
## along the long walls, the rails on them, and the crane parked near the hall's west (or south) end: two box girders
## spanning the hall on their end carriages, the trolley on them, the hook block hanging on its ropes. Safety yellow
## (the crane's paint, as cranes are), the runway the frame's dark steel. Drawn only, baked.
const CRANE_INSET := 0.9      # the rail's centre from the liner's face
const CRANE_RUNWAY_D := 1.0
const CRANE_GIRDER_D := 1.6
const CRANE_MIN := 6.0        # the lowest rail: the hook block hangs 3.3 m below it
func _crane(body: Node, frame: SurfaceTool, b: Dictionary) -> void:
	var g := steel_grid(b)
	var r: Rect2 = g.r
	var along_x: bool = g.along_x
	var L: float = g.L
	var S: float = g.S
	var zr: float = b.crane
	if b.get("cladding", "metal") != "metal" or Geom.bbox(b.outline).get_area() > Geom.area([b.outline]) + 0.5 or zr < CRANE_MIN:
		_err("crane_unsupported", String(b.id), "an overhead crane runs in a rectangular metal-clad hall, its rail at %.0f m or higher" % CRANE_MIN)
		return
	# the trolley's top must clear the roof's trusses (or rafters)
	var steel_lo: float = float(b.height) - LINER_T - PURLIN_D - (truss_depth(S) if S >= TRUSS_MIN else rafter_depth(S))
	if zr + 0.15 + CRANE_GIRDER_D + 0.9 > steel_lo - 0.05:
		_err("crane_clash", String(b.id), "the crane on its rail at %.1f m reaches %.2f m, into the roof steel from %.2f m" % [zr, zr + 0.15 + CRANE_GIRDER_D + 0.9, steel_lo])
	var at := func(t: float, s2: float) -> Vector2:
		return r.position + (Vector2(t, s2) if along_x else Vector2(s2, t))
	var inset := WALL_T * 0.5 + LINER_T + CRANE_INSET
	for s2 in [inset, S - inset]:
		var a: Vector2 = at.call(0.3, s2)
		var e: Vector2 = at.call(L - 0.3, s2)
		var dv := (e - a).normalized()
		var across := Vector2(-dv.y, dv.x)
		Geom.add_prism(frame, Geom._strip(a, e, across, 0.45), zr - 0.1 - CRANE_RUNWAY_D, zr - 0.1)   # runway girder
		Geom.add_prism(frame, Geom._strip(a, e, across, 0.08), zr - 0.1, zr)                          # the rail
		# a corbel on every column along this wall, from the column to under the runway (none where no column stands)
		for cp in b.get("_cols", []):
			var q: Vector2 = cp - r.position
			var t: float = q.x if along_x else q.y
			var sc: float = q.y if along_x else q.x
			if absf(sc - s2) > CRANE_INSET + 1.0:
				continue   # a column of the other long wall, or of a gable
			var p0: Vector2 = cp
			var p1: Vector2 = at.call(t, s2 + (0.3 if s2 < S * 0.5 else -0.3))
			Geom.add_prism(frame, Geom._strip(p0, p1, (p1 - p0).normalized().orthogonal(), 0.4), zr - 0.1 - CRANE_RUNWAY_D - 0.7, zr - 0.1 - CRANE_RUNWAY_D)
	# the crane, parked a sixth of the hall from its end
	var yellow := _st()
	var tc := L / 6.0
	var z0 := zr + 0.15
	for dt in [-1.1, 1.1]:   # two box girders
		var a2: Vector2 = at.call(tc + dt, inset)
		var e2: Vector2 = at.call(tc + dt, S - inset)
		Geom.add_prism(yellow, Geom._strip(a2, e2, (e2 - a2).normalized().orthogonal(), 0.6), z0, z0 + CRANE_GIRDER_D)
	for s2 in [inset, S - inset]:   # the end carriages on the rails, wheels inside
		var a3: Vector2 = at.call(tc - 2.4, s2)
		var e3: Vector2 = at.call(tc + 2.4, s2)
		Geom.add_prism(yellow, Geom._strip(a3, e3, (e3 - a3).normalized().orthogonal(), 0.7), zr, z0 + 0.9)
	# the trolley a third of the span across, its hoist; the hook block on four ropes
	var ts := S * 0.38
	var tp: Vector2 = at.call(tc, ts)
	var zt := z0 + CRANE_GIRDER_D
	Geom.add_prism(yellow, Geom.rect(tp.x - 1.8, tp.y - 1.6, tp.x + 1.8, tp.y + 1.6), zt, zt + 0.9)
	Geom.add_prism(yellow, Geom.rect(tp.x - 0.6, tp.y - 0.45, tp.x + 0.6, tp.y + 0.45), zt - 2.6, zt - 1.8)   # hook block
	var dark := _st()
	for o in [Vector2(-0.35, -0.2), Vector2(0.35, -0.2), Vector2(-0.35, 0.2), Vector2(0.35, 0.2)]:
		var q: Vector2 = tp + o
		Geom.add_prism(dark, Geom.rect(q.x - 0.015, q.y - 0.015, q.x + 0.015, q.y + 0.015), zt - 1.8, zt + 0.1)
	var hook := PackedVector2Array()
	for i in 10:
		var ang := TAU * i / 10.0
		hook.append(tp + Vector2(cos(ang), sin(ang)) * 0.12)
	Geom.add_prism(dark, hook, zt - 3.3, zt - 2.6)
	_mesh_node(body, "crane", yellow, _mat("rail"), STEEL_TEXEL)
	_mesh_node(body, "crane_hook", dark, _mat("steel_dark"), STEEL_TEXEL)

# ------------------------------------------------------------------ walls (firewalls)

## A wall along its route (content `wall`: a transformer yard's firewalls): concrete, solid, a coping on top; its
## streaks hang from its top.
func _wall(parent: Node3D, s: Dictionary) -> void:
	var pr := params_of("wall", s.get("params", {}))
	var at := _v3(s.at)
	var body := _body(parent, s.id)
	var st := _st()
	var pts: Array = pr.route
	var h := float(pr.height)
	var t := float(pr.thickness)
	for i in range(pts.size() - 1):
		var a := at + Geom.turn(_v3(pts[i]), float(s.get("yaw", 0)))
		var e := at + Geom.turn(_v3(pts[i + 1]), float(s.get("yaw", 0)))
		var a2 := Vector2(a.x, a.y)
		var e2 := Vector2(e.x, e.y)
		if a2.distance_to(e2) < 0.01:
			continue
		var u := (e2 - a2).normalized()
		_wall_panel(st, body, a2, e2, a.z, a.z + h, t)
		st.set_color(top_colour(a.z + h + 0.1))
		_panel(st, null, a2 - u * 0.05, e2 + u * 0.05, a.z + h, a.z + h + 0.1, t + 0.1)   # the coping
	_mesh_node(body, "mesh", st, _mat("firewall"))

