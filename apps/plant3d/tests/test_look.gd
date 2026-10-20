## The look's polish pass (toward plant-v0.2.0) in the built plant:
## - every building's ceiling: a light liner under its roof and the roof steel under that, the lamps hung below the
##   steel; a metal-clad hall's walls lined inside too; a hall's upper floor seen from below is decking on beams, not
##   its floor's dark paint (the ceilings were black);
## - a metal-clad building's plinth and flashings, the louvres and windows its openings name, the windows lit from
##   inside (the circulating water pump house read as a dim box);
## - the transformer yard's fence is a palisade one sees through, not a sheet (blotchy on the phone);
## - the walls' streaks have broad columns that read from afar and on a phone, longer on taller faces;
## - the ground's ruts break and its track wanders on every tier (the phone's were unbroken and straight);
## - a safety sign's board is retroreflective white with a little light of its own (grey in a wall's shade).
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Mat = preload("res://kit/materials.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = []
	var plant: Node3D = Plant.new()
	plant.name = "plant"
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return ["the built plant loads: " + err]
	var liner_mat := load("res://built/materials/liner.tres") as ShaderMaterial
	if liner_mat == null:
		p.append("the liner's material is built")
	elif _lum(liner_mat.get_shader_parameter("tint")) < 0.55:
		p.append("the liner is light (%.2f linear): a hall's ceiling is lit by what its floor bounces" % _lum(liner_mat.get_shader_parameter("tint")))
	var buildings := 0
	for body in plant.find_children("*", "StaticBody3D", true, false):
		if not body.has_meta("building"):
			continue
		buildings += 1
		var roof := body.get_node_or_null("roof") as MeshInstance3D
		var liner := body.get_node_or_null("liner") as MeshInstance3D
		var steel := body.get_node_or_null("roof_steel") as MeshInstance3D
		if roof == null or liner == null or steel == null:
			p.append("%s: its roof, liner and roof steel (%s %s %s)" % [body.name, roof != null, liner != null, steel != null])
			continue
		var roof_box := roof.global_transform * roof.mesh.get_aabb()
		var liner_box := liner.global_transform * liner.mesh.get_aabb()
		var steel_box := steel.global_transform * steel.mesh.get_aabb()
		if liner.material_override != liner_mat or liner.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			p.append("%s: the liner is the light liner, baked" % body.name)
		if absf(liner_box.end.y - roof_box.position.y) > 0.01:
			p.append("%s: the liner is right under the roof (%.2f, %.2f)" % [body.name, liner_box.end.y, roof_box.position.y])
		if steel_box.end.y > liner_box.end.y - 0.02 or steel_box.position.y > roof_box.position.y - 0.5:
			p.append("%s: the roof steel hangs under the liner, half a metre and more" % body.name)
		if steel.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			p.append("%s: the roof steel is baked" % body.name)
		# the roof's lamps hang below the steel (and none of them inside it)
		for l in body.get_children():
			if l is SpotLight3D and String(l.name).begins_with("lamp_") and l.global_position.y > roof_box.position.y - 3.0:
				if l.global_position.y > steel_box.position.y - 0.1:
					p.append("%s: hangs below the roof steel (%.2f, steel from %.2f)" % [l.get_path(), l.global_position.y, steel_box.position.y])
		var wall_box := (body.get_node("walls") as MeshInstance3D).mesh.get_aabb()
		var metal: bool = body.get_meta("cladding", "") == "metal"
		if metal:
			# lined inside from the floor to the roof
			if liner_box.position.y > 0.05 or liner_box.size.y < wall_box.size.y * 0.9:
				p.append("%s: its walls are lined inside too (liner %.1f to %.1f m)" % [body.name, liner_box.position.y, liner_box.end.y])
			for part in ["plinth", "trims"]:
				var n := body.get_node_or_null(part) as MeshInstance3D
				if n == null:
					p.append("%s: a metal-clad building has its %s" % [body.name, part])
	if buildings < 5 or plant.find_children("*", "StaticBody3D", true, false).filter(func(n): return n.get_meta("cladding", "") == "metal").size() < 4:
		p.append("the buildings are found (%d)" % buildings)
	# the turbine hall's operating floor from below: decking on beams
	var soffit := plant.find_child("st_floor_12_soffit", true, false) as MeshInstance3D
	var beams := plant.find_child("st_floor_12_beams", true, false) as MeshInstance3D
	if soffit == null or beams == null or soffit.material_override != liner_mat:
		p.append("the turbine hall's operating floor has its decking and beams under it")
	elif (beams.global_transform * beams.mesh.get_aabb()).end.y > (soffit.global_transform * soffit.mesh.get_aabb()).position.y + 0.01:
		p.append("the operating floor's beams are under its decking")
	else:
		var under := (beams.global_transform * beams.mesh.get_aabb()).position.y
		for l in tree.get_nodes_in_group("baked_lights"):
			if String(l.name).begins_with("lamp_") and String(l.get_parent().name) == "st_hall" and l.global_position.y < 12.0 \
					and l.global_position.y > under - 0.25:
				p.append("%s: a lamp under the operating floor hangs below its beams (%.2f, beams from %.2f)" % [l.get_path(), l.global_position.y, under])
	# the circulating water pump house: louvres, windows lit from inside
	var cw := plant.find_child("cw_house", true, false)
	if cw == null or cw.get_node_or_null("louvres") == null or cw.get_node_or_null("windows") == null or cw.get_node_or_null("windows_in") == null:
		p.append("the pump house has its louvres and windows")
	else:
		var day := (cw.get_node("windows_in") as MeshInstance3D).material_override as ShaderMaterial
		if day == null or float(day.get_shader_parameter("emission_energy")) <= 0.0:
			p.append("a window seen from inside is the daylight beyond (its own light)")
	# the transformer yard's fence: a palisade, seen through
	var fence := plant.find_child("trafo_fence", true, false)
	var fm := fence.get_node_or_null("mesh") as MeshInstance3D if fence != null else null
	if fm == null:
		p.append("the transformer yard's fence is found")
	else:
		var open := _see_through(fm, Vector3(-28.0, 1.2, -40.5), Vector3(1, 0, 0), 26.0, Vector3(0, 0, -1))
		if open < 0.35 or open > 0.75:
			p.append("the transformer yard's fence is a palisade one sees through (%.0f %% of sight lines through it)" % (open * 100.0))
	# the walls' streaks: broad columns too, longer on a taller face, and stronger on cladding
	var code := FileAccess.get_file_as_string("res://kit/weathered.gdshaderinc")
	if not code.contains("h / 0.75") or not code.contains("(1.0 + top * 0.12)"):
		p.append("the streaks have broad columns, longer on taller faces")
	if float(Mat.WEATHER.sheeting.streaks) < 0.6:
		p.append("cladding's streaks read on a phone (%.2f)" % float(Mat.WEATHER.sheeting.streaks))
	# the ground: ruts and the track without the tier's samples (the same on the phone)
	var a := code.find("if (macro > 0.0")
	var b := code.find("// a yard's joints")
	var ground := code.substr(a, b - a) if a >= 0 and b > a else ""
	if ground == "" or ground.contains("detail") or ground.contains("texture(noise_tex, vec2("):
		p.append("the ground's ruts break and its track wanders on every tier (no tier switch, no sample of their own)")
	# a safety sign's board: retroreflective white, its blue in the vertices, a little light of its own
	var board := load("res://built/materials/sign_board.tres") as ShaderMaterial
	if board == null or not board.get_shader_parameter("use_vertex_colour") or float(board.get_shader_parameter("emission_energy")) < 0.5:
		p.append("a sign's board is retroreflective white (its own light)")
	if not code.contains("emission_energy * (use_vertex_colour ? srgb_to_linear(COLOR.rgb)"):
		p.append("a board's light takes its colours (the blue symbol glows blue, not white)")
	plant.free()
	return p

static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b

## The share of horizontal sight lines through a mesh: from `start` along `along` every 5 cm for `len` metres, each
## 6 m long looking along `dir` from 3 m before the start (Godot axes); a line through no triangle is open.
static func _see_through(mi: MeshInstance3D, start: Vector3, along: Vector3, len: float, dir: Vector3) -> float:
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var xf := mi.global_transform
	var tris: Array = []
	for i in range(0, idx.size(), 3):
		tris.append([xf * v[idx[i]], xf * v[idx[i + 1]], xf * v[idx[i + 2]]])
	var open := 0
	var n := int(len / 0.05)
	for k in n:
		var o := start + along * (k * 0.05) - dir * 3.0
		var hit := false
		for t in tris:
			if Geometry3D.segment_intersects_triangle(o, o + dir * 6.0, t[0], t[1], t[2]) != null:
				hit = true
				break
		open += 0 if hit else 1
	return float(open) / n
