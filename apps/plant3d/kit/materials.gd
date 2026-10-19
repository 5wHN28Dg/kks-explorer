## The kit's materials (docs/PLANT3D.md §10, decision 0054 §5): CC0 PBR sets from ambientCG (fetched by
## kit/fetch_textures.sh, pinned by SHA-256, never committed) at three texture sizes, a tier picks the size, never a
## different material. Paint colours are a material's tint over one texture set, so one set serves every colour.
## Small pieces (instruments, tag plates, handwheels, lamps) use plain materials with no textures: under a few
## pixels a texture adds shading cost and nothing a trainee sees.
##
## The builder saves every material to built/materials/<name>.tres with the 1024 px textures (the size every export
## carries); the app's tier switches them to the tier's size when it has them (apply_tier, below).
extends RefCounted

const TEX := "res://kit/tex"
const SIZES := [2048, 1024, 512]
const DEFAULT_SIZE := 1024
## The texture size per quality tier (app/quality.gd): laptops the 2048 px set, phones 1024 px (decision 0041 measured
## the Note 9 with 2048 and 1024 px: 1024 px cut its texture memory by three quarters at the same frame times).
const TIER_SIZE := {"full": 2048, "lean+vis": 1024}

## The texture sets: the maps each uses (Color, NormalGL, Roughness) and what they are for.
const SETS := {
	"PaintedMetal004": ["NormalGL", "Roughness"],     # paint: its scratches and wear only, the colour is the tint
	"Metal032": ["Color", "NormalGL", "Roughness"],   # bare and galvanised steel: stems, flanges, frames
	"Metal009": ["Color", "NormalGL", "Roughness"],   # brushed aluminium: insulation cladding
	# wall cladding, casings: the ribs only. Its colour and roughness maps are large blotches that read as
	# camouflage on a 40 m wall (second realism pass): the sheets' tone and gloss are drawn per sheet instead
	"CorrugatedSteel005": ["NormalGL"],
	"Concrete034": ["Color", "NormalGL", "Roughness"],
	"MetalWalkway010": ["Color", "NormalGL", "Roughness"],     # grating decks and treads
	"DiamondPlate008C": ["Color", "NormalGL", "Roughness"],    # chequer plate decks
	"Gravel023": ["Color", "NormalGL", "Roughness"],           # the ground between the areas
	"Asphalt031": ["Color", "NormalGL", "Roughness"],          # roads
}

## RAL-like paint colours (the colours are ours; equipment colours follow common practice: machines and motors in
## blue-grey or green, cabinets light grey, handwheels red, handrails and ladders yellow).
const PAINT := {
	"paint_machine": Color(0.30, 0.42, 0.55),    # turbines, generators (a blue-grey)
	"paint_motor": Color(0.22, 0.36, 0.52),      # electric motors (blue)
	"paint_pump": Color(0.18, 0.42, 0.30),       # pumps (green)
	"paint_grey": Color(0.70, 0.71, 0.70),       # cabinets, panels, transformers' light grey
	"paint_darkgrey": Color(0.30, 0.31, 0.32),   # valve bodies, actuators, gearboxes
	"paint_tank": Color(0.82, 0.82, 0.78),       # tanks and vessels (off-white)
	"paint_trafo": Color(0.45, 0.48, 0.47),      # transformer tanks and radiators
	"paint_red": Color(0.70, 0.08, 0.07),        # handwheels, fire equipment, stop buttons
	"paint_yellow": Color(0.92, 0.70, 0.08),     # handrails, ladders, guards, safety colour
	"paint_orange": Color(0.88, 0.40, 0.08),     # electric actuators (a common maker's colour)
	"paint_green": Color(0.10, 0.50, 0.20),      # start buttons, run lamps' housings
	"paint_white": Color(0.92, 0.92, 0.90),
	"paint_black": Color(0.06, 0.06, 0.06),
	"paint_beige": Color(0.78, 0.72, 0.58),      # GT and generator enclosures, filter house
	"paint_ct": Color(0.66, 0.70, 0.72),         # the cooling tower's FRP casing
	"paint_pipe": Color(0.50, 0.52, 0.53),       # bare pipe (its medium shows in its bands)
}

## Bare pipe painted by the colour group of what it carries (plant.json `media`: `group`), after DIN 2403's idea of
## a colour per group, in muted shades: the medium's own band and arrow (saturated, PLANT3D.md §2) must still stand out
## on the pipe, in lightness too, for a trainee who tells colours apart badly (tests/test_realism.gd checks both for
## every medium of the plant: the yellow gas paint left the orange gas band 7 L* lighter only, adversarial review). Insulated pipe is aluminium
## cladding whatever it carries.
const PIPE_PAINT := {
	"water": Color(0.74, 0.77, 0.71),      # a pale grey green
	"steam": Color(0.78, 0.79, 0.78),      # heat-resistant aluminium paint, light
	"air": Color(0.84, 0.87, 0.90),        # a pale grey blue (the air band is a mid grey blue)
	"gas": Color(0.55, 0.48, 0.26),        # an ochre, darker than the gas band
	"oil": Color(0.42, 0.33, 0.26),        # brown
	"chemicals": Color(0.55, 0.50, 0.58),  # a grey violet
	"flue gas": Color(0.30, 0.30, 0.30),   # dark grey
}
## The material name of bare pipe carrying a medium of `group` (resolve() knows it).
static func pipe_paint(group: String) -> String:
	return "pipe_" + group if PIPE_PAINT.has(group) else "paint_pipe"

## Weathering per finish (kit/weathered.gdshaderinc): how much grime, run-off streaks, dust on top faces, rust and
## paint wear each shows. Values set by eye against photographs of plants in service: bare steel rusts, paint wears
## where it is touched, concrete stains, aluminium cladding streaks under its laps.
const WEATHER := {
	"paint": {"grime": 0.35, "streaks": 0.30, "dust": 0.20, "rust": 0.10, "wear": 0.8},
	"metal": {"grime": 0.40, "streaks": 0.30, "dust": 0.20, "rust": 0.30, "wear": 0.0},
	"galvanised": {"grime": 0.30, "streaks": 0.30, "dust": 0.20, "rust": 0.04, "wear": 0.0},
	"cladding": {"grime": 0.25, "streaks": 0.30, "dust": 0.12, "rust": 0.0, "wear": 0.0},
	"sheeting": {"grime": 0.20, "streaks": 0.50, "dust": 0.15, "rust": 0.04, "wear": 0.0},
	"concrete": {"grime": 0.45, "streaks": 0.55, "dust": 0.25, "rust": 0.0, "wear": 0.0},
	"ground": {"grime": 0.50, "streaks": 0.0, "dust": 0.15, "rust": 0.0, "wear": 0.0},
	"deck": {"grime": 0.45, "streaks": 0.20, "dust": 0.30, "rust": 0.15, "wear": 0.5},
	# a hall's painted floor: kept fairly clean
	"floor": {"grime": 0.20, "streaks": 0.0, "dust": 0.06, "rust": 0.0, "wear": 0.0},
	# small plain pieces (dials, tag plates, glass, the media's bands): kept clean, a trainee reads them
	"none": {"grime": 0.0, "streaks": 0.0, "dust": 0.0, "rust": 0.0, "wear": 0.0},
}
## Which weathering a material takes (by its texture set).
const WEATHER_OF := {"PaintedMetal004": "paint", "Metal032": "metal", "Metal009": "cladding",
	"CorrugatedSteel005": "sheeting", "Concrete034": "concrete", "Gravel023": "ground", "Asphalt031": "ground",
	"MetalWalkway010": "deck", "DiamondPlate008C": "deck"}
## How much a piece of each paint colour is touched (the vertex colour's alpha: kit/mesh.gd, the shader's `wear`):
## handrails, ladders and guards in yellow and handwheels in red most; a machine's casing hardly.
## Capped where a colour identifies (a red handwheel, a yellow guard: R9a): worn spots, never a bare part.
const EXPOSURE := {"paint_yellow": 0.6, "paint_red": 0.35, "paint_orange": 0.25, "paint_darkgrey": 0.3,
	"paint_green": 0.25}
const EXPOSURE_DEFAULT := 0.12
const SHADER := "res://kit/weathered.gdshader"
## The weathering's noise (builder/weather.gd makes it at build time: our own, no licence).
const NOISE := "res://built/weather/noise.res"

## Every material: set (or "" for a plain one), tint, roughness, metallic, the texture's tile size in metres, and
## flags. A plain material's roughness and metallic are its values; with a set they scale the set's maps.
static func specs() -> Dictionary:
	var m := {}
	for k in PAINT:
		m[k] = {"set": "PaintedMetal004", "tint": PAINT[k], "rough": 1.0, "metal": 0.15, "tile": 1.5}
	m["steel"] = {"set": "Metal032", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.85, "tile": 1.0}
	m["steel_dark"] = {"set": "Metal032", "tint": Color(0.45, 0.45, 0.47), "rough": 1.0, "metal": 0.7, "tile": 1.0}
	m["galvanised"] = {"set": "Metal032", "tint": Color(0.85, 0.87, 0.88), "rough": 1.0, "metal": 0.75, "tile": 2.0}
	# insulation cladding: aluminium sheets lapped every metre along the pipe
	m["cladding"] = {"set": "Metal009", "tint": Color(0.92, 0.93, 0.95), "rough": 1.0, "metal": 0.8, "tile": 1.0, "lap": 1.0}
	# wall cladding: painted (polyester-coated) steel sheets 1 m wide, the ribs from the set's normal map
	m["corrugated"] = {"set": "CorrugatedSteel005", "tint": Color(0.50, 0.54, 0.58), "rough": 0.6, "metal": 0.1, "tile": 2.0, "sheet": 1.0}
	m["corrugated_casing"] = {"set": "CorrugatedSteel005", "tint": Color(0.52, 0.54, 0.55), "rough": 0.6, "metal": 0.1, "tile": 3.0, "sheet": 1.0}
	m["concrete"] = {"set": "Concrete034", "tint": Color(0.72, 0.71, 0.69), "rough": 1.0, "metal": 0.0, "tile": 3.0}
	# a hall's floor: grey-green epoxy paint on concrete, the concrete's relief under it, satin
	m["hall_floor"] = {"set": "Concrete034", "maps": ["NormalGL"], "tint": Color(0.42, 0.47, 0.44), "rough": 0.4, "metal": 0.0, "tile": 3.0, "weather": "floor"}
	m["grating"] = {"set": "MetalWalkway010", "tint": Color(0.75, 0.75, 0.72), "rough": 1.0, "metal": 0.6, "tile": 1.0}
	m["chequer"] = {"set": "DiamondPlate008C", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.7, "tile": 1.0}
	m["gravel"] = {"set": "Gravel023", "tint": Color(0.62, 0.60, 0.56), "rough": 1.0, "metal": 0.0, "tile": 3.0, "macro": 0.6}
	m["asphalt"] = {"set": "Asphalt031", "tint": Color(0.6, 0.6, 0.6), "rough": 1.0, "metal": 0.0, "tile": 4.0}
	# the country beyond the wall: the gravel's set, sandier and larger (seen from tens to hundreds of metres)
	m["terrain"] = {"set": "Gravel023", "tint": Color(0.78, 0.70, 0.56), "rough": 1.0, "metal": 0.0, "tile": 9.0, "macro": 1.0}
	# plain (no textures): small pieces, faces of dials, glass, rubber, porcelain, lamps
	m["plate"] = {"set": "", "tint": Color(0.93, 0.93, 0.90), "rough": 0.4, "metal": 0.0}         # tag plates (white)
	m["plate_border"] = {"set": "", "tint": Color(0.05, 0.05, 0.05), "rough": 0.6, "metal": 0.0}
	m["dial"] = {"set": "", "tint": Color(0.97, 0.97, 0.95), "rough": 0.4, "metal": 0.0}
	m["needle"] = {"set": "", "tint": Color(0.05, 0.05, 0.05), "rough": 0.5, "metal": 0.0}
	m["brass"] = {"set": "", "tint": Color(0.78, 0.62, 0.30), "rough": 0.35, "metal": 1.0}
	m["chrome"] = {"set": "", "tint": Color(0.80, 0.81, 0.83), "rough": 0.2, "metal": 1.0}        # stems, gauge cases
	m["rubber"] = {"set": "", "tint": Color(0.05, 0.05, 0.05), "rough": 0.9, "metal": 0.0}
	m["porcelain"] = {"set": "", "tint": Color(0.36, 0.20, 0.12), "rough": 0.25, "metal": 0.0}     # bushings
	m["glass"] = {"set": "", "tint": Color(0.35, 0.45, 0.50), "rough": 0.05, "metal": 0.2}
	m["water"] = {"set": "", "tint": Color(0.18, 0.30, 0.32), "rough": 0.08, "metal": 0.1}
	m["fill"] = {"set": "", "tint": Color(0.16, 0.17, 0.18), "rough": 0.8, "metal": 0.0}            # CT fill, louvres' depth
	m["dark"] = {"set": "", "tint": Color(0.03, 0.03, 0.03), "rough": 1.0, "metal": 0.0}            # openings, shadows inside
	m["lamp_off"] = {"set": "", "tint": Color(0.55, 0.52, 0.45), "rough": 0.2, "metal": 0.0}
	m["lamp_green"] = {"set": "", "tint": Color(0.1, 0.8, 0.2), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_red"] = {"set": "", "tint": Color(0.9, 0.1, 0.05), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_amber"] = {"set": "", "tint": Color(1.0, 0.6, 0.05), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_blue"] = {"set": "", "tint": Color(0.1, 0.3, 1.0), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_white"] = {"set": "", "tint": Color(1.0, 0.97, 0.9), "rough": 0.3, "metal": 0.0, "emit": true}
	m["sign_green"] = {"set": "", "tint": Color(0.0, 0.45, 0.25), "rough": 0.5, "metal": 0.0}
	m["sign_yellow"] = {"set": "", "tint": Color(0.98, 0.80, 0.05), "rough": 0.5, "metal": 0.0}
	# the materials the kit's meshes are drawn with: one per texture set and finish, the colour in the vertices
	# (`resolve`), so a cell's pieces of every paint colour are one draw call, not one per colour (decision 0041:
	# draw calls are what the phone pays for)
	m["paint"] = {"set": "PaintedMetal004", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.15, "tile": 1.5, "vc": true}
	m["metal"] = {"set": "Metal032", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.8, "tile": 1.0, "vc": true}
	m["sheeting"] = {"set": "CorrugatedSteel005", "tint": Color(0.85, 0.85, 0.85), "rough": 0.6, "metal": 0.1, "tile": 2.5, "vc": true, "sheet": 1.0}
	m["plain"] = {"set": "", "tint": Color(1, 1, 1), "rough": 0.6, "metal": 0.0, "vc": true}
	m["plain_metal"] = {"set": "", "tint": Color(1, 1, 1), "rough": 0.3, "metal": 0.9, "vc": true}
	return m

static var _specs := {}
## Extra colours by name (the media's band colours: the builder sets them from plant.json).
static var colours := {}

## The material a piece named `name` is drawn with, and its colour in the vertices: [material, Color].
static func resolve(name: String) -> Array:
	if _specs.is_empty():
		_specs = specs()
	if PAINT.has(name):
		var c: Color = PAINT[name]
		c.a = EXPOSURE.get(name, EXPOSURE_DEFAULT)
		return ["paint", c]
	if name.begins_with("pipe_") and PIPE_PAINT.has(name.trim_prefix("pipe_")):
		var c: Color = PIPE_PAINT[name.trim_prefix("pipe_")]
		c.a = EXPOSURE_DEFAULT
		return ["paint", c]
	if colours.has(name):
		return ["plain", colours[name]]
	var s: Dictionary = _specs.get(name, {})
	if s.is_empty() or s.get("vc", false):
		return [name if not s.is_empty() else "plain", Color(1, 1, 1)]
	match s.set:
		"Metal032": return ["metal", s.tint]
		"CorrugatedSteel005": return ["sheeting", s.tint]
		"":
			if not s.get("emit", false):
				return ["plain_metal" if s.metal > 0.5 else "plain", s.tint]
	return [name, Color(1, 1, 1)]

## The structures' materials (the builder's walkable and building geometry): name -> [the kit material it is made
## as, both faces drawn (buildings are seen from inside too: PLANT3D.md §5)].
const STRUCTURE_MATS := {
	"ground": ["gravel", false], "concrete": ["concrete", false], "grating": ["grating", false],
	"deck_steel": ["chequer", false], "rail": ["paint_yellow", false], "stair": ["galvanised", false],
	"wall_metal": ["corrugated", true], "wall_concrete": ["concrete", true], "wall_brick": ["concrete", true],
	"roof": ["corrugated_casing", true], "door": ["paint_motor", false], "fence": ["galvanised", true],
	"pit": ["concrete", false], "ladder": ["paint_yellow", false], "rack": ["galvanised", false],
	"yard": ["concrete", false], "road": ["asphalt", false], "drain": ["dark", false], "terrain": ["terrain", false],
	"hall_floor": ["hall_floor", false],
}

static func structure_spec(name: String) -> Dictionary:
	var spec: Dictionary = specs()[STRUCTURE_MATS[name][0]].duplicate()
	if name == "wall_brick":
		spec.tint = Color(0.72, 0.42, 0.33)
	if name in ["rail", "ladder", "stair"]:
		spec["wear"] = 0.5   # handrails, ladders and treads: worn spots where hands and feet go, never bare (R9a: safety yellow)
	if name == "grating":
		spec["grating"] = true
	if name == "yard":
		spec["joints"] = 6.0   # cast in 6 m bays
	if name in ["wall_metal", "wall_concrete", "wall_brick", "fence"]:
		spec["top_edge"] = true   # streaks hang from each panel's top (its top in the vertex colour: the builder's _panel)
	return spec

## A structure's material. Walls, roofs and fences are closed prisms (their inside and outside each have faces of
## their own), so one cull-back shader serves them.
static func make_structure(name: String) -> Material:
	return make(name, structure_spec(name))

## The texture sets whose files are not there (not fetched, or not imported yet).
static func missing_textures() -> PackedStringArray:
	var out := PackedStringArray()
	for s in SETS:
		for m in SETS[s]:
			if not ResourceLoader.exists(tex_path(s, m, DEFAULT_SIZE)):
				out.append("%s_%s" % [s, m])
	return out

static func tex_path(set_name: String, map: String, size: int) -> String:
	return "%s/%d/%s_%s.jpg" % [TEX, size, set_name, map]

## Makes a material from its spec with textures of `size` px (when they were fetched; else plain, which the build
## warns). A material with a texture set is the weathered shader (kit/weathered.gdshaderinc); plain ones (small
## pieces, lamps) stay Godot's standard material.
static func make(name: String, spec: Dictionary, size := DEFAULT_SIZE) -> Material:
	var s: String = spec.get("set", "")
	if s != "" or not spec.get("emit", false):
		# the plain ones too, without textures or weathering: one shader for every lit surface, so a phone's first
		# start compiles its pipelines once, not again for Godot's standard shader (decision 0057)
		return _make_weathered(name, spec, size)
	var mat := StandardMaterial3D.new()
	mat.resource_name = name
	mat.albedo_color = spec.tint
	mat.roughness = spec.rough
	mat.metallic = spec.metal
	if spec.get("vc", false):
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
	if spec.get("emit", false):
		mat.emission_enabled = true
		mat.emission = spec.tint
		mat.emission_energy_multiplier = 2.0
	return mat

static func _make_weathered(name: String, spec: Dictionary, size: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = name
	mat.shader = load(SHADER)
	mat.set_shader_parameter("grating", 1.0 if spec.get("grating", false) else 0.0)
	mat.set_shader_parameter("tint", spec.tint)
	mat.set_shader_parameter("roughness_scale", spec.rough)
	mat.set_shader_parameter("metallic", spec.metal)
	mat.set_shader_parameter("uv_scale", Vector2.ONE / float(spec.get("tile", 1.0)))
	mat.set_shader_parameter("use_vertex_colour", spec.get("vc", false))
	var w: Dictionary = WEATHER.get(spec.get("weather", WEATHER_OF.get(spec.set, "paint") if spec.set != "" else "none"), {})
	for k in w:
		mat.set_shader_parameter(k, float(w[k]) * float(spec.get("weather_scale", 1.0)))
	if spec.has("wear"):
		mat.set_shader_parameter("wear", float(spec.wear))
	if spec.has("joints"):
		mat.set_shader_parameter("joint_spacing", float(spec.joints))
	mat.set_shader_parameter("sheet_width", float(spec.get("sheet", 0.0)))
	mat.set_shader_parameter("lap_length", float(spec.get("lap", 0.0)))
	mat.set_shader_parameter("macro", float(spec.get("macro", 0.0)))
	mat.set_shader_parameter("top_edge", 1.0 if spec.get("top_edge", false) else 0.0)
	if ResourceLoader.exists(NOISE):
		mat.set_shader_parameter("noise_tex", load(NOISE))
	if spec.set != "":
		_textures(mat, spec.set, size, spec.get("maps", []))
	return mat

## The wet zone round water (the shader's `wet_zone`: centre x, z in Godot's axes, half sizes along x and z; `wet`
## its strength) on every weathered material in `mats`.
static func set_wet_zone(mats: Dictionary, zone: Vector4, strength: float) -> void:
	for k in mats:
		var m = mats[k]
		# not on the clean plain pieces (tag plates, dials, the media's bands: a trainee reads them)
		if m is ShaderMaterial and float(m.get_shader_parameter("grime")) > 0.0:
			m.set_shader_parameter("wet_zone", zone)
			m.set_shader_parameter("wet", strength)

## The tier's share of the weathering's samples (the shader's `detail`: 0 drops the streaks and the paint wear).
static func set_detail(mat: Material, on: bool) -> void:
	if mat is ShaderMaterial:
		mat.set_shader_parameter("detail", 1.0 if on else 0.0)

## A material's texture of one map ("Color", "NormalGL", "Roughness"), whichever kind of material it is.
static func texture_of(mat: Material, map: String) -> Texture2D:
	if mat is ShaderMaterial:
		return mat.get_shader_parameter({"Color": "albedo_tex", "NormalGL": "normal_tex", "Roughness": "rough_tex"}[map])
	if mat is StandardMaterial3D:
		return {"Color": mat.albedo_texture, "NormalGL": mat.normal_texture, "Roughness": mat.roughness_texture}[map]
	return null

## `only`: the maps of the set this material takes (all of them when empty).
static func _textures(mat: Material, set_name: String, size: int, only: Array = []) -> bool:
	var maps: Array = SETS[set_name] if only.is_empty() else only
	var ok := true
	for m in maps:
		var p := tex_path(set_name, m, size)
		if not ResourceLoader.exists(p):
			ok = false
			continue
		var t := load(p) as Texture2D
		if mat is ShaderMaterial:
			var param: String = {"Color": "albedo_tex", "NormalGL": "normal_tex", "Roughness": "rough_tex"}[m]
			mat.set_shader_parameter(param, t)
			mat.set_shader_parameter({"Color": "use_albedo", "NormalGL": "use_normal", "Roughness": "use_rough"}[m], true)
			continue
		match m:
			"Color": mat.albedo_texture = t
			"NormalGL":
				mat.normal_enabled = true
				mat.normal_texture = t
			"Roughness":
				mat.roughness_texture = t
	return ok

## The textures' size for a tier: the tier's size when this build carries it, else the largest smaller one, else
## the default (the Android export carries 1024 and 512 px only).
static func size_for(tier: String) -> int:
	var want: int = TIER_SIZE.get(tier, DEFAULT_SIZE)
	for s in SIZES:
		if s <= want and ResourceLoader.exists(tex_path("Concrete034", "Color", s)):
			return s
	return DEFAULT_SIZE

## Switches every built material to the tier's texture size (materials are shared resources: every mesh using one
## follows). `mats` is the built materials' folder.
static func apply_tier(tier: String, mats_dir := "res://built/materials") -> int:
	var size := size_for(tier)
	var all := specs()
	for name in STRUCTURE_MATS:
		all[name] = structure_spec(name)
	var n := 0
	for name in all:
		var p := mats_dir.path_join(name + ".tres")
		if not ResourceLoader.exists(p):
			continue
		var mat := load(p) as Material
		var s: String = all[name].get("set", "")
		set_detail(mat, tier == "full")
		if mat != null and s != "" and _textures(mat, s, size, all[name].get("maps", [])):
			n += 1
	return n
