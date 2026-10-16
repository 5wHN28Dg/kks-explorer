## The plant's light (R9, R9a): one sun and sky for the bake and for every tier, the baked lightmap (builder/bake/)
## attached when the build carries one, and what each tier adds at run time. Measured per tier (decision 0057,
## "Realism"): the lightmap is a texture read per pixel on every tier; SSAO, SSIL, volumetric fog and glow are the
## laptops' (Forward+); the phones get the bake, distance haze and nothing else.
extends RefCounted

## Where the bake puts its data (builder/bake/bake_plugin.gd): a LightmapGIData whose users are paths from a node
## standing beside the areas under the plant's node ("../area_gt1/kit/…").
const LIGHTMAP := "res://built/lightmap/plant.lmbake"
const SUN_ROT := Vector3(-50, 35, 0)   # degrees: the sun without a built sky (as before the bake)
## The sun's light in lux-like units for the physical sky (energy 1 = Godot's default sun). A clear sky's sun is
## about six times its sky's light on a horizontal surface; the tonemapper's exposure brings both back.
const SUN_ENERGY := 1.0
const SUN_COLOUR := Color(1.0, 0.96, 0.9)   # a little warm: mid-afternoon
const AGX_CONTRAST := 1.25   # a little more than AgX's own: the desert light is hard
const SKY_ENERGY := 1.0   # the photograph's own sky-to-sun ratio (builder/sky.gd)
const EXPOSURE := 1.0

## The sky made by the build (builder/sky.gd): a photographed sky without its sun, in units where the sun's light
## is 1, and where its sun was. Without it (a build that could not fetch it) a physical sky and the old sun.
const SKY := "res://built/sky/sky.exr"
const SKY_INFO := "res://built/sky/sky.json"

static func sky_info() -> Dictionary:
	if not FileAccess.file_exists(SKY_INFO):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SKY_INFO))
	return d if d is Dictionary else {}

static func sky() -> Sky:
	var s := Sky.new()
	s.radiance_size = Sky.RADIANCE_SIZE_128
	# the sky's light is worked out over the first frames, not all in the first (the Note 9's first start)
	s.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if ResourceLoader.exists(SKY) and not sky_info().is_empty():
		var m := PanoramaSkyMaterial.new()
		m.panorama = load(SKY)
		m.energy_multiplier = SKY_ENERGY
		s.sky_material = m
		return s
	var pm := PhysicalSkyMaterial.new()
	pm.turbidity = 8.0
	pm.ground_color = Color(0.36, 0.33, 0.28)
	s.sky_material = pm
	return s

static func sun() -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = "sun"
	var info := sky_info()
	if info.is_empty():
		l.rotation_degrees = SUN_ROT
	else:
		var el := deg_to_rad(float(info.sun_elevation))
		var az := deg_to_rad(float(info.sun_azimuth))
		var to_sun := Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))
		l.basis = Basis.looking_at(-to_sun, Vector3.UP)   # a directional light shines along its -z
	l.light_energy = SUN_ENERGY
	l.light_color = SUN_COLOUR
	l.shadow_enabled = true
	l.light_bake_mode = Light3D.BAKE_DYNAMIC   # the bake keeps its bounce; its direct light and shadow stay real-time
	return l

## The lightmap node for a plant whose areas stand under `parent`, or null when the build carries no bake.
static func lightmap_node() -> LightmapGI:
	if not ResourceLoader.exists(LIGHTMAP):
		return null
	var data := load(LIGHTMAP) as LightmapGIData
	if data == null or data.get_user_count() == 0 or data.get_lightmap_textures().is_empty():
		return null   # an unbaked data file (a bake that failed half way)
	var lm := LightmapGI.new()
	lm.name = "lightmap"
	lm.light_data = data
	return lm

## What a tier adds to the environment (measured: decision 0057). Both tiers: AgX tonemapping (a film-like curve that keeps the shade readable and the colours of paint true) with the
## same exposure, and a thin haze that grows with distance (aerial perspective: far equipment pales towards the
## sky's colour, as it does outdoors; Godot's depth fog, a few instructions per pixel). Laptops (Forward+) add
## SSAO (contact shade under what the lightmap is too coarse for: bolts, valves on pipes, a hand on a rail), SSIL
## (light bounced between nearby moving parts and their surroundings), volumetric fog (the sun's light in the air:
## shafts through a hall's doors) and a little glow on lamps. The Mobile renderer has none of SSAO, SSIL and
## volumetric fog; the phone's shade comes from the bake.
## Effects switched off for a measurement (main.gd's `fx_off=ssao,ssil,volfog,glow,fog`): which costs what.
static var off: PackedStringArray = []
## Effects switched on for a measurement only (`fx_on=sdfgi,ssil,volfog,glow`): measured and left out (0057).
static var on: PackedStringArray = []

static func apply(tier: String, env: Environment) -> void:
	var full := tier == "full"
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE
	env.tonemap_agx_contrast = AGX_CONTRAST
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.70, 0.76, 0.84)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.15
	env.fog_density = 0.0003
	env.fog_aerial_perspective = 0.0   # the sky below the horizon is the ground: looking down it would wash the view
	env.fog_sky_affect = 0.0
	env.ssao_enabled = full
	# Low quality at half size (0057: Medium cost the frame rule its margin on the Iris Xe), faded out by
	# 120 m where its contact shade is under a pixel anyway
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 120.0)
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.0
	env.ssil_enabled = false
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color(0.85, 0.87, 0.9)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = false
	env.glow_intensity = 0.3
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.5
	env.ssil_enabled = env.ssil_enabled or "ssil" in on
	env.volumetric_fog_enabled = env.volumetric_fog_enabled or "volfog" in on
	env.glow_enabled = env.glow_enabled or "glow" in on
	env.sdfgi_enabled = "sdfgi" in on
	env.ssao_enabled = env.ssao_enabled and not "ssao" in off
	env.ssil_enabled = env.ssil_enabled and not "ssil" in off
	env.volumetric_fog_enabled = env.volumetric_fog_enabled and not "volfog" in off
	env.glow_enabled = env.glow_enabled and not "glow" in off
	env.fog_enabled = env.fog_enabled and not "fog" in off
