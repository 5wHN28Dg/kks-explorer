## The realism pass (decision 0057, R9, R9a) in the built plant:
## - the static meshes carry lightmap UV2 and are marked for the bake; instanced and moving ones take the sky's light (the probes lit them almost black: 0057);
## - the bake scene holds the ground and every area under names the app's plant node gives them, the sun and a
##   LightmapGI beside them (its users' paths hold in the app); an unbaked data file is not attached;
## - walls, roofs and fences have their back faces as geometry (each side its own lightmap texels);
## - the photographed sky's sun is the light's direction, and the sky is the panorama;
## - the textured materials are the weathered shader with the noise, the gratings drawn as bar gratings, the yards
##   jointed, the road's centre line round the plant, the ground wet round the cooling tower;
## - the site: gravel, yards, the ring road with kerbs and its drain, the boundary wall, the terrain;
## - each tier's environment: AgX and the haze on both, SSAO on laptops only, the measured-and-dropped effects off.
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
	# the site
	var ground := plant.get_node_or_null("ground")
	for want in ["ground", "yard_0", "road", "verge", "kerbs", "drain", "drain_cover", "boundary_wall", "terrain"]:
		if ground == null or ground.find_child(want, true, false) == null:
			p.append("the site has its %s" % want)
	var terrain := ground.find_child("terrain", true, false) as MeshInstance3D if ground != null else null
	if terrain != null and terrain.mesh.get_aabb().size.x < 1000.0:
		p.append("the terrain reaches the far plane (%.0f m across)" % terrain.mesh.get_aabb().size.x)
	# walls with back faces of their own: every triangle has a twin at the same place facing the other way
	var walls := 0
	for n in plant.find_children("walls", "MeshInstance3D", true, false):
		walls += 1
		var arr: Array = (n as MeshInstance3D).mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var faces := {}
		for i in range(0, idx.size(), 3):
			var a := v[idx[i]]
			var b := v[idx[i + 1]]
			var c := v[idx[i + 2]]
			var key := str(((a + b + c) / 3.0).snappedf(0.01))
			var nrm := (b - a).cross(c - a).normalized()
			faces[key] = faces.get(key, []) + [nrm]
		var single := 0
		for k in faces:
			var ns: Array = faces[k]
			if not ns.any(func(x): return ns.any(func(y): return x.dot(y) < -0.99)):
				single += 1
		if single > 0:
			p.append("%s: a wall has its back faces (%d of %d faces without)" % [n.get_path(), single, faces.size()])
	if walls < 3:
		p.append("the buildings' walls were found (%d)" % walls)
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
	if not (env.ssao_enabled and env.fog_enabled and env.tonemap_mode == Environment.TONE_MAPPER_AGX):
		p.append("laptops: SSAO, haze, AgX")
	if env.ssil_enabled or env.volumetric_fog_enabled or env.sdfgi_enabled or env.glow_enabled:
		p.append("laptops: SSIL, volumetric fog, SDFGI and glow stay off (measured: 0057)")
	Lighting.apply("lean+vis", env)
	if env.ssao_enabled or not env.fog_enabled:
		p.append("phones: no SSAO, the haze")
	plant.free()
	return p
