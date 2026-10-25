## The photo pass (decision 0057, "Photo pass"): the details halls and yards in service share, in the built plant:
## - floors by finish: the gas turbine hall and the steam turbine's operating floor glazed tiles, the ground floor
##   under the deck bare concrete (cracks, dust), bar gratings over the trenches beside the gas turbine;
## - wide halls' roofs carried by trusses, the frame inside (columns, girts), an overhead crane on its runway clear of
##   the trusses; the tiles' sheen at a grazing view in the shader (no reflection probe: half a gigabyte of video
##   memory and 14 to 19 ms of the laptop's GPU time at the 95th percentile);
## - the transformers' firewalls (solid), open yards gravelled, the road's kerbs painted in yellow and white blocks and its
##   block-paved footpath (photo pass 3);
## - the media's names stencilled on the pipes, drawn as a safety sign's text is (no pipeline of their own);
## - valves' bodies black, electric actuators grey, bolts rusty.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Mat = preload("res://kit/materials.gd")
const Builder = preload("res://builder/plant_builder.gd")
const KitPlace = preload("res://builder/kit_place.gd")
const PPipe = preload("res://kit/parts_pipes.gd")
const MB = preload("res://kit/mesh.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = []
	var plant: Node3D = Plant.new()
	plant.name = "plant"
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return ["the built plant loads: " + err]
	var mats := {}
	for n in ["hall_floor", "floor_tile", "floor_concrete", "grating", "roof_steel", "rail", "firewall", "yard_gravel", "paint", "pavers"]:
		mats[n] = load("res://built/materials/%s.tres" % n)
		if mats[n] == null:
			p.append("the material %s is built" % n)
	if not p.is_empty():
		plant.free()
		return p
	# floors by finish
	var want := {"gt1_hall": "floor_tile", "st_hall": "floor_concrete", "cw_house": "floor_concrete",
		"bop_boiler_house": "floor_concrete", "ctl_building": "hall_floor"}
	for id in want:
		var body := plant.find_child(id, true, false)
		var fl := body.get_node_or_null("floor") as MeshInstance3D if body != null else null
		if fl == null or fl.material_override != mats[want[id]]:
			p.append("%s: its floor is %s" % [id, want[id]])
	var deck := plant.find_child("st_floor_12", true, false)
	var dm := deck.get_node_or_null("mesh") as MeshInstance3D if deck != null else null
	if dm == null or dm.material_override != mats.floor_tile:
		p.append("the operating floor is tiled")
	var tile := mats.floor_tile as ShaderMaterial
	if float(tile.get_shader_parameter("tile_size")) <= 0.0 or float(tile.get_shader_parameter("roughness_scale")) > 0.2:
		p.append("tiles: drawn joints and glazed (glossy)")
	if not FileAccess.get_file_as_string("res://kit/weathered.gdshaderinc").contains("base * (1.0 + sheen * TILE_SHEEN"):
		p.append("tiles: their sheen at a grazing view")
	if not plant.find_children("*", "ReflectionProbe", true, false).is_empty():
		p.append("no reflection probe (its cost: photo pass)")
	if float((mats.floor_concrete as ShaderMaterial).get_shader_parameter("cracks")) <= 0.0:
		p.append("bare concrete floors have their cracks")
	for id in ["gt1_trench_n_cover", "gt1_trench_s_cover"]:
		var g := plant.find_child(id, true, false)
		var gm := g.get_node_or_null("mesh") as MeshInstance3D if g != null else null
		if gm == null or gm.material_override != mats.grating:
			p.append("%s: a bar grating over the trench" % id)
	# halls: trusses, the frame, the crane, the probe
	for id in ["st_hall", "gt1_hall", "bop_boiler_house", "cw_house"]:
		var body := plant.find_child(id, true, false)
		if body == null:
			p.append("%s is found" % id)
			continue
		var roof := body.get_node("roof") as MeshInstance3D
		var h: float = (roof.global_transform * roof.mesh.get_aabb()).position.y
		var steel := body.get_node("roof_steel") as MeshInstance3D
		var sb := steel.global_transform * steel.mesh.get_aabb()
		var span := minf(roof.mesh.get_aabb().size.x, roof.mesh.get_aabb().size.z)
		var deep := h - sb.position.y
		if span >= Builder.TRUSS_MIN and deep < Builder.truss_depth(span) - 0.1:
			p.append("%s: its roof is carried by trusses %.1f m deep (%.1f)" % [id, Builder.truss_depth(span), deep])
		var frame := body.get_node_or_null("frame") as MeshInstance3D
		if frame == null or frame.material_override != mats.roof_steel or frame.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			p.append("%s: its frame inside (columns, girts), dark steel, baked" % id)
		else:
			var fb := frame.global_transform * frame.mesh.get_aabb()
			if fb.position.y > 0.01 or fb.end.y < h - 1.0:
				p.append("%s: its columns stand from the floor to the roof steel (%.1f to %.1f)" % [id, fb.position.y, fb.end.y])
		var crane := body.get_node_or_null("crane") as MeshInstance3D
		var has_crane: bool = id in ["st_hall", "gt1_hall"]
		if (crane != null) != has_crane:
			p.append("%s: an overhead crane only in the turbine halls" % id)
		elif crane != null:
			var cb := crane.global_transform * crane.mesh.get_aabb()
			if crane.material_override != mats.rail:
				p.append("%s: the crane in safety yellow" % id)
			if cb.end.y > sb.position.y - 0.05:
				p.append("%s: the crane clears the roof's trusses (crane to %.2f, steel from %.2f)" % [id, cb.end.y, sb.position.y])
			if cb.size.x < 15.0 and cb.size.z < 15.0:
				p.append("%s: the crane spans the hall" % id)
	# no column in a pipe's way: the auxiliary steam pipe comes through the turbine hall's east gable at y = 0, z = 9 (a
	# column stood in it: review)
	var st_frame := plant.find_child("st_hall", true, false).get_node("frame") as MeshInstance3D
	for y in [-0.3, 0.0, 0.3]:   # x 79.5: inside a gable column's plan (79.40 to 79.85), clear of the girts
		if not _hits_down(st_frame, Vector3(79.5, 0.0, -y)).is_empty():
			p.append("the turbine hall's frame stands in the auxiliary steam pipe's way at y %.1f" % y)
	# the transformers' firewalls: solid and as high as given
	for id in ["trafo_firewall_1", "trafo_firewall_2"]:
		var w := plant.find_child(id, true, false) as StaticBody3D
		var wm := w.get_node_or_null("mesh") as MeshInstance3D if w != null else null
		if wm == null or wm.material_override != mats.firewall or w.find_children("*", "CollisionShape3D", false, false).is_empty():
			p.append("%s: a solid concrete wall" % id)
		elif absf((wm.global_transform * wm.mesh.get_aabb()).end.y - 8.1) > 0.05:
			p.append("%s: 8 m high and its coping" % id)
	# the yards and the road's kerbs
	var gravel := 0
	for n in plant.find_children("yard_*", "StaticBody3D", true, false):
		var ym := n.get_node_or_null("mesh") as MeshInstance3D
		if ym != null and ym.material_override == mats.yard_gravel:
			gravel += 1
	if gravel < 3:
		p.append("the open areas' yards are gravelled (%d)" % gravel)
	var kerbs := plant.find_child("kerbs", true, false) as MeshInstance3D
	if kerbs == null or kerbs.material_override != mats.paint:
		p.append("the kerbs are painted")
	else:
		var cols: PackedColorArray = kerbs.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var yellow := false
		var white := false
		var black := false
		for c in cols:
			yellow = yellow or (c.r > 0.8 and c.b < 0.2)
			white = white or (c.r > 0.8 and c.g > 0.8 and c.b > 0.8)
			black = black or (c.r < 0.1 and c.g < 0.1)
		if not (yellow and white) or black:
			p.append("the kerbs are painted in yellow and white blocks (photo pass 3), not black and yellow")
	# the block-paved footpath along the ring road (photo pass 3)
	var fp := plant.find_child("footpath", true, false)
	var fm := fp.get_node_or_null("mesh") as MeshInstance3D if fp != null else null
	if fm == null or fm.material_override != mats.pavers:
		p.append("the ring road has its block-paved footpath")
	# stencils: the media's names, drawn as a safety sign's text, on their pipes
	var stencils := plant.find_children("stencil*", "Label3D", true, false)
	if stencils.size() < 10:
		p.append("the pipes carry their stencilled names (%d)" % stencils.size())
	var media: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://built/content/plant.json")).media
	var sign_label: Label3D = null
	for l in plant.find_children("*", "Label3D", true, false):
		if l.has_meta("symbol"):
			sign_label = l
			break
	for l: Label3D in stencils:
		var med := String(l.get_meta("stencil", ""))
		if not media.has(med) or l.text != String(media[med].get("name", "")):
			p.append("%s: the medium's name (%s)" % [l.get_path(), l.text])
			break
		if sign_label != null and (l.outline_size != sign_label.outline_size or l.double_sided != sign_label.double_sided
				or l.shaded != sign_label.shaded or l.alpha_cut != sign_label.alpha_cut or l.no_depth_test != sign_label.no_depth_test
				or l.texture_filter != sign_label.texture_filter or l.billboard != sign_label.billboard):
			p.append("%s: drawn as a sign's text (one pipeline)" % l.get_path())
			break
		if l.visibility_range_end <= 0.0 or l.visibility_range_end > 40.0:
			p.append("%s: drawn near it only" % l.get_path())
			break
		if l.get_parent().name != "pipes":
			p.append("%s: under its area's pipes" % l.get_path())
			break
	if sign_label == null:
		p.append("a safety sign's text is found (the stencils' model)")
	p.append_array(_names_clear_of_bands())
	# valves and actuators
	if Mat.PAINT.paint_valve.get_luminance() > 0.15 or absf(Mat.PAINT.paint_actuator.s) > 0.15:
		p.append("valve bodies black, actuators a neutral grey")
	var vcode := FileAccess.get_file_as_string("res://kit/parts_valves.gd")
	if vcode.contains("\"paint_motor\"") or vcode.contains("\"paint_darkgrey\""):
		p.append("valves in black and grey, not the motors' blue")
	if not FileAccess.get_file_as_string("res://kit/parts_common.gd").contains("m.use(\"steel_bolt\""):
		p.append("bolts are rusty steel")
	plant.free()
	return p

## The heights where a vertical line through p (Godot axes) meets a mesh's triangles.
static func _hits_down(mi: MeshInstance3D, p: Vector3) -> Array:
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var xf := mi.global_transform
	var out: Array = []
	var lo := xf.affine_inverse() * Vector3(p.x, 1000.0, p.z)
	for i in range(0, idx.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(lo, Vector3.DOWN, v[idx[i]], v[idx[i + 1]], v[idx[i + 2]])
		if hit != null:
			out.append((xf * (hit as Vector3)).y)
	return out


## The names' places (kit_place.gd stencil_places) against the bands and arrows the pipe kit really draws: a pipe made
## by parts_pipes.gd, its band layer's vertices projected on each level run; no name may cover one (they were spaced
## on the whole segment while the bands are spaced on the run between the bends and the bare stretches: review).
func _names_clear_of_bands() -> Array:
	var p: Array = []
	var cases := [
		# [route, od, ins, arrows, gaps, a name's width]: an insulated run of 23 m with arrows every 15 m (two bands
		# assumed on the segment, one drawn), a bare 42 m run without arrows with a valve on it, a 3d bend
		[[Vector3(0, 0, 3), Vector3(23, 0, 3), Vector3(23, 10, 3)], 0.406, 0.15, 15.0, [], 1.8, ""],
		[[Vector3(0, 0, 3), Vector3(42, 0, 3), Vector3(42, 0, 0.6)], 0.324, 0.0, 0.0, [[17.0, 18.2]], 1.0, ""],
		[[Vector3(0, 0, 3), Vector3(30, 0, 3), Vector3(30, 20, 3)], 1.6, 0.0, 10.0, [], 2.0, "3d"],
	]
	for c in cases:
		var pr := {"od": c[1], "ins": c[2], "band": "test_band", "arrows": c[3], "gaps": c[4], "bend": {"3d": 3.0}.get(c[6], 1.5)}
		var m = MB.new()
		var origin: Vector3 = c[0][0]
		PPipe.pipe(m, c[0], pr, origin)
		var marks: Array = []   # along the first run: the band and arrow vertices' distances
		for k in m.layers:
			if not String(k).begins_with("plain|id"):
				continue
			for v in m.layers[k].v:
				var q := Vector3(v.x, -v.z, v.y) + origin     # Godot's axes back to the plant's
				if absf(q.y) < 1.5 and absf(q.z - 3.0) < 1.5 and q.x < c[0][1].x - 0.01:
					marks.append(q.x)
		if marks.is_empty():
			p.append("the test pipe %s has bands" % str(c[0]))
			continue
		var places := KitPlace.stencil_places(c[0], c[1], c[2], {"arrows": c[3], "bend": c[6]}, {}, c[4], c[5])
		var on_run := places.filter(func(pl): return absf(pl[0].y) < 0.01)
		if on_run.is_empty():
			p.append("a name on the test pipe's first run (%s)" % str(c[0]))
		for pl in on_run:
			var t: float = pl[0].x
			for x in marks:
				if x > t - c[5] * 0.5 and x < t + c[5] * 0.5:
					p.append("a name at %.2f m covers a band or arrow at %.2f m (%s)" % [t, x, str(c[0])])
					break
			for g in c[4]:
				if g[0] < t + c[5] * 0.5 and g[1] > t - c[5] * 0.5:
					p.append("a name at %.2f m covers the valve at %s" % [t, str(g)])
	return p
