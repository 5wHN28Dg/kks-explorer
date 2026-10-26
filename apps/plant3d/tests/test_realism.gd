## The realism pass (decision 0057, R9, R9a) in the built plant:
## - the static meshes carry lightmap UV2 and are marked for the bake; instanced and moving ones take the sky's light (the probes lit them almost black: 0057);
## - the bake scene holds the ground and every area under names the app's plant node gives them, the sun and a
##   LightmapGI beside them (its users' paths hold in the app); an unbaked data file is not attached;
## - identify pieces (tag plates, bands) are left out of the bake;
## - the photographed sky's sun is the light's direction, and the sky is the panorama;
## - the textured materials are the weathered shader with the noise, the gratings drawn as bar gratings, the yards
##   jointed, the road's centre line round the plant, the ground wet round the cooling tower;
## - the site: gravel, yards, the ring road with kerbs and its drain, the boundary wall, the terrain;
## - each tier's environment: AgX and the haze on both, no SSAO (it cost the laptop its frame rule), the measured-and-dropped effects off.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Lighting = preload("res://app/lighting.gd")
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
	# lightmap UV2 on what stands still, the sky's light for what is instanced or moves
	var lit := 0
	for n in tree.get_nodes_in_group("kit_static"):
		var mi := n as MeshInstance3D
		lit += 1
		if mi.gi_mode != GeometryInstance3D.GI_MODE_STATIC or not (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2):
			p.append("%s: a static kit mesh has UV2 and is baked" % mi.get_path())
		if mi.mesh.lightmap_size_hint == Vector2i.ZERO:
			p.append("%s: its lightmap size is known" % mi.get_path())
	if lit < 300:
		p.append("most of the kit's meshes are baked (%d)" % lit)
	for n in tree.get_nodes_in_group("kit_cells"):
		if (n as GeometryInstance3D).gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
			p.append("%s: an instanced cell takes the sky's light, not the probes'" % n.get_path())
	# thin sheets (the fences, the gate) are baked at a fine texel: left out of the bake, an unbaked static mesh cost
	# the phone a pipeline of its own at the first frame (second realism pass)
	var sheets := 0
	for n in plant.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == null or mi.material_override.resource_path.get_file() != "fence.tres":
			continue
		sheets += 1
		if mi.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			p.append("%s: a thin sheet is baked (an unbaked static mesh is a pipeline of its own)" % mi.get_path())
		var area := mi.mesh.get_aabb().get_longest_axis_size() * mi.mesh.get_aabb().size.y
		if mi.mesh.lightmap_size_hint.x * mi.mesh.lightmap_size_hint.y < area / 0.1 / 0.1:
			p.append("%s: a thin sheet's texel is fine (%s for %.0f m²)" % [mi.get_path(), mi.mesh.lightmap_size_hint, area])
	if sheets < 2:
		p.append("the fences and the gate are found (%d)" % sheets)
	# the site
	var ground := plant.get_node_or_null("ground")
	for want in ["ground", "yard_0", "road", "verge", "kerbs_0", "drain", "drain_cover", "boundary_wall", "terrain"]:
		if ground == null or ground.find_child(want, true, false) == null:
			p.append("the site has its %s" % want)
	var terrain := ground.find_child("terrain", true, false) as MeshInstance3D if ground != null else null
	if terrain != null and terrain.mesh.get_aabb().size.x < 1000.0:
		p.append("the terrain reaches the far plane (%.0f m across)" % terrain.mesh.get_aabb().size.x)
	# identify pieces (plates, bands) are never baked: a coarse texel would grey a plate behind its code
	for n in tree.get_nodes_in_group("kit_static"):
		if "_identify_" in String(n.name):
			p.append("%s: an identify piece is not baked" % n.get_path())
	# light inside: the halls' lamps reach the floor and a pit below it; every pit has lamps of its own (the turbine
	# hall's pit was black before)
	var lamps := tree.get_nodes_in_group("baked_lights")
	var pit_lamps := lamps.filter(func(l): return String(l.name).begins_with("pit_lamp_"))
	if pit_lamps.is_empty():
		p.append("the pits have lamps")
	# a lamp is set from the floor under it: over the turbine hall's deck the deck's, and the floor under the deck has
	# lamps of its own (both were lit from the ground: adversarial reviews, second pass)
	var on_deck := 0
	var under_deck := 0
	for l in lamps:
		if String(l.name).begins_with("lamp_") and String(l.get_parent().name).begins_with("st_hall"):
			var f := float(l.get_meta("floor", 0.0))
			if f > 2.0:
				on_deck += 1
			elif l.global_position.y < 15.0:
				under_deck += 1
	if on_deck == 0 or under_deck == 0:
		p.append("the turbine hall's lamps are set for the floor under them (%d over the deck, %d under it)" % [on_deck, under_deck])
	var halls := 0
	for l in lamps:
		if String(l.name).begins_with("lamp_"):
			var hall := l.get_parent().get_node_or_null("roof") as MeshInstance3D
			var h := hall.mesh.get_aabb().position.y if hall != null else 0.0
			# a high-bay lamp throws its light down in a cone (pools on the floor, darker corners: second pass)
			var spot := l as SpotLight3D
			if spot == null:
				p.append("%s is a downlight (a spot), not an omni light that lights the hall evenly" % l.get_path())
				continue
			if spot.global_transform.basis.z.dot(Vector3.UP) < 0.99:
				p.append("%s shines straight down" % l.get_path())
			if spot.spot_range < h * 2.0:
				p.append("%s reaches the floor and below (range %.1f, hall %.1f m)" % [l.get_path(), spot.spot_range, h])
			if spot.spot_angle > 60.0:
				p.append("%s throws a cone, not a flood (%.0f degrees)" % [l.get_path(), spot.spot_angle])
			# no baked light of a lamp reaches the ceiling round it: hot spots there came out of the bake as blotches
			# over every floor and wall (an omni "spill", second pass)
			for c in spot.get_children():
				var cs := c as SpotLight3D
				if c is Light3D and (cs == null or cs.spot_angle >= 85.0):
					p.append("%s: a lamp's spill lights the ceiling (an omni or a spot wider than 85 degrees)" % c.get_path())
	# every hall has its painted floor, darker than the yard outside (a floor as light as the yard washed out under
	# the lamps: second pass)
	var floor_mat := load("res://built/materials/hall_floor.tres") as ShaderMaterial
	if floor_mat == null:
		p.append("the halls' floor material is built")
	else:
		var t: Color = floor_mat.get_shader_parameter("tint")
		var lum := 0.2126 * t.srgb_to_linear().r + 0.7152 * t.srgb_to_linear().g + 0.0722 * t.srgb_to_linear().b
		if lum > 0.25 or float(floor_mat.get_shader_parameter("roughness_scale")) > 0.6:
			p.append("a hall's floor is painted: a believable albedo (%.2f linear) and satin, not chalk" % lum)
	# each hall has its floor in its finish (painted, tiled or bare concrete: photo pass)
	var finishes := ["hall_floor", "floor_tile", "floor_concrete", "floor_vinyl"].map(func(n): return load("res://built/materials/%s.tres" % n))
	for roof in plant.find_children("roof", "MeshInstance3D", true, false):
		if roof.get_parent().get_meta("shell", false):
			continue   # a shell nobody goes into (its doors locked: the camp's other blocks) has nothing drawn inside
		halls += 1
		var fl := roof.get_parent().get_node_or_null("floor") as MeshInstance3D
		if fl == null or not fl.material_override in finishes:
			p.append("%s: the hall has its floor" % roof.get_parent().get_path())
	if halls < 3:
		p.append("the halls are found (%d)" % halls)
	if Lighting.SKY_ENERGY < 3.0:
		p.append("the sky's energy is π in Godot's light units (the photograph's ratio)")
	# materials
	var paint := load("res://built/materials/paint.tres") as ShaderMaterial
	if paint == null or paint.shader.resource_path != Mat.SHADER or paint.get_shader_parameter("noise_tex") == null:
		p.append("paint is the weathered shader with its noise")
	var grating := load("res://built/materials/grating.tres") as ShaderMaterial
	if grating == null or float(grating.get_shader_parameter("grating")) != 1.0:
		p.append("gratings are drawn as bar gratings")
	var yard := load("res://built/materials/yard.tres") as ShaderMaterial
	if yard == null or float(yard.get_shader_parameter("joint_spacing")) <= 0.0:
		p.append("the yards are jointed")
	var road := load("res://built/materials/road.tres") as ShaderMaterial
	if road == null or (road.get_shader_parameter("line_box") as Vector4).z <= 0.0:
		p.append("the road has its centre line")
	var gravel := load("res://built/materials/ground.tres") as ShaderMaterial
	var wz: Vector4 = gravel.get_shader_parameter("wet_zone") if gravel != null else Vector4.ZERO
	# the cooling tower stands at plant (215, 0): Godot x 215, z 0
	if gravel == null or float(gravel.get_shader_parameter("wet")) <= 0.0 or absf(wz.x - 215.0) > 1.0 or wz.z < 30.0:
		p.append("the ground is wet round the cooling tower (%s)" % str(wz))
	var plate := load("res://built/materials/plate.tres") as ShaderMaterial
	var pwz = plate.get_shader_parameter("wet_zone") if plate != null else null
	if plate == null or (pwz != null and pwz != Vector4.ZERO):
		p.append("tag plates are never darkened by the wet zone")
	# corrugated cladding: the ribs from the normal map, a tone per sheet; no photographed colour or roughness (their
	# large blotches read as camouflage on a wall: second pass)
	for mname in ["corrugated", "corrugated_casing", "sheeting", "wall_metal", "roof"]:
		var cm := load("res://built/materials/%s.tres" % mname) as ShaderMaterial
		if cm == null or cm.get_shader_parameter("use_albedo") or cm.get_shader_parameter("use_rough") \
				or not cm.get_shader_parameter("use_normal") or float(cm.get_shader_parameter("sheet_width")) <= 0.0:
			p.append("%s: corrugated sheets drawn from the ribs' normal map and per sheet, no blotchy maps" % mname)
	# walls' streaks hang from each panel's top: the vertex colour carries it
	for mname in ["wall_metal", "wall_concrete", "fence"]:
		var wm := load("res://built/materials/%s.tres" % mname) as ShaderMaterial
		if wm == null or float(wm.get_shader_parameter("top_edge")) != 1.0:
			p.append("%s: streaks hang from the panels' tops" % mname)
	var wall_node := ground.find_child("boundary_wall", true, false) if ground != null else null
	# (its panels in a mesh per square: builder/plant_builder.gd _mesh_cells)
	var panels: Array = wall_node.find_children("panels_*", "MeshInstance3D", false, false) if wall_node != null else []
	if panels.is_empty():
		p.append("the boundary wall's panels are found")
	else:
		var top_y := -INF
		for pm in panels:
			for v in (pm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				top_y = maxf(top_y, v.y)
		var bad := 0
		var high := 0
		var none := 0
		for pm in panels:
			var cols: PackedColorArray = pm.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var ys: PackedVector3Array = pm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			if cols.is_empty():
				none += 1
			for i in cols.size():
				var top := (roundf(cols[i].r * 255.0) + cols[i].g) * 0.25
				if top + 0.02 < ys[i].y - pm.global_position.y:   # a pier's own top too (they stand 0.15 m higher)
					bad += 1
				if top > top_y - pm.global_position.y + 0.02:   # nor above the wall: no streak would reach it
					high += 1
		if none > 0 or bad > 0 or high > 0:
			p.append("the wall's vertices carry its top (%d vertices above it, %d with a top over the wall, %d meshes without)" % [bad, high, none])
	# the ground varies (patches, ruts by the road, a track out of the gate); insulated pipe is lapped cladding
	var terr := load("res://built/materials/terrain.tres") as ShaderMaterial
	if terr == null or float(terr.get_shader_parameter("macro")) <= 0.0 or (terr.get_shader_parameter("track") as Vector4).length() < 1.0 \
			or (terr.get_shader_parameter("line_box") as Vector4).z <= 0.0 or float(terr.get_shader_parameter("road_line")) != 0.0:
		p.append("the terrain varies, with ruts by the road and a track out of the gate, and no centre line")
	if float((load("res://built/materials/ground.tres") as ShaderMaterial).get_shader_parameter("macro")) <= 0.0:
		p.append("the gravel varies")
	if float((load("res://built/materials/cladding.tres") as ShaderMaterial).get_shader_parameter("lap_length")) <= 0.0:
		p.append("insulation cladding is lapped sheets")
	# bare pipe painted by what it carries, every medium's band still standing out on it
	var media: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://built/content/plant.json")).media
	for med in media:
		var paint_name := Mat.pipe_paint(String(media[med].group))
		var r: Array = Mat.resolve(paint_name)
		if paint_name == "paint_pipe" or r[0] != "paint":
			p.append("%s: bare pipe is painted by its group (%s)" % [med, paint_name])
			continue
		var de := delta_e(r[1], Color.html(media[med].band))
		var dl := absf(_lab(r[1]).x - _lab(Color.html(media[med].band)).x)
		if de < 25.0 or dl < 15.0:
			p.append("%s: its band stands out on its pipe, in lightness too (ΔE %.1f, ΔL* %.1f)" % [med, de, dl])
	var water_pipes := 0
	for n in tree.get_nodes_in_group("pipes"):
		if n.get_meta("medium", "") == "cooling_water":
			water_pipes += 1
	if water_pipes == 0:
		p.append("the plant has cooling water pipes")
	# the bake scene
	var ps := load("res://built/lit.scn") as PackedScene
	if ps == null:
		p.append("the bake scene is built")
	else:
		var lit_scene := ps.instantiate()
		if not lit_scene.get_node_or_null("lightmap") is LightmapGI or not lit_scene.get_node_or_null("sun") is DirectionalLight3D:
			p.append("the bake scene has its LightmapGI and sun")
		for c in plant.get_children():
			if lit_scene.get_node_or_null(NodePath(c.name)) == null:
				p.append("the bake scene names %s as the app does" % c.name)
		lit_scene.free()
	# an unbaked data file is not attached (a bake that failed half way)
	if FileAccess.file_exists(ProjectSettings.globalize_path(Lighting.LIGHTMAP)):
		var d := load(Lighting.LIGHTMAP) as LightmapGIData
		if d != null and d.get_user_count() == 0 and Lighting.lightmap_node() != null:
			p.append("an empty lightmap is not attached")
	# the sky and its sun
	var info := Lighting.sky_info()
	if info.is_empty():
		p.append("the build made the sky (kit/fetch_textures.sh fetches it)")
	else:
		var sun := Lighting.sun()
		var el := deg_to_rad(float(info.sun_elevation))
		var az := deg_to_rad(float(info.sun_azimuth))
		var to_sun := Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))
		if sun.transform.basis.z.angle_to(to_sun) > 0.01:
			p.append("the sun shines from where the photograph's sun was")
		if not (float(info.sun_elevation) > 10.0 and float(info.sky_to_sun) > 0.05 and float(info.sky_to_sun) < 1.0):
			p.append("the sky's sun and light are plausible: %s" % str(info))
		sun.free()
		if not Lighting.sky().sky_material is PanoramaSkyMaterial:
			p.append("the sky is the photograph")
	# the tiers' environments
	var env := Environment.new()
	Lighting.apply("full", env)
	if not (env.fog_enabled and env.tonemap_mode == Environment.TONE_MAPPER_AGX):
		p.append("laptops: haze, AgX")
	# SSAO cost the full tier its 60 fps on the Iris Xe (second realism pass, 0057)
	if env.ssao_enabled or env.ssil_enabled or env.volumetric_fog_enabled or env.sdfgi_enabled or env.glow_enabled:
		p.append("laptops: SSIL, volumetric fog, SDFGI and glow stay off (measured: 0057)")
	Lighting.apply("lean+vis", env)
	if env.ssao_enabled or not env.fog_enabled:
		p.append("phones: no SSAO, the haze")
	plant.free()
	return p

## CIE76 colour difference between two sRGB colours.
static func delta_e(a: Color, b: Color) -> float:
	var la := _lab(a)
	var lb := _lab(b)
	return la.distance_to(lb)

static func _lab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var x := (0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047
	var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var z := (0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	return Vector3(116.0 * f.call(y) - 16.0, 500.0 * (f.call(x) - f.call(y)), 200.0 * (f.call(y) - f.call(z)))
