## The weather seen and heard (docs/plant3d/REALISM.md §5.4, milestone WX3): the model's weather (its kind `world_wx`
## and the values weather.json drives: wind, rain, dust, visibility, solar, lightning, wet) drawn with what the plant
## already has (decision 0073):
## - the depth fog thickens to the model's visibility and takes a sand colour in dust, grey in rain, and washes the
##   photographed sky (the fog's sky affect: no sky shader, no sky reprocessing);
## - the sun dims with `solar` against a clear sky's at the hour, and its shadows soften;
## - one particle emitter round the camera: rain streaks or blown sand, none under a roof (the build's roof map);
## - wet and dusty surfaces under the sky: global parameters of the one weathered shader (no new variant);
## - the wind, rain and sand ambiences and thunder after a flash (ui/sound_player.gd).
## Everything follows the model's values, eased over SMOOTH seconds (the model steps ten times a second and its values
## already lag their kind's targets by minutes), so every multiplayer peer, stepping the same run, sees and hears the
## same weather. The lightning's flashes are placed by the model's step number and the world seed, not by a random
## number of this device. A scenario without weather leaves the plant's light as lighting.gd set it.
extends Node

const Lighting = preload("res://app/lighting.gd")
const WeatherFix = preload("weather_fix.gd")
const PROCESS_SHADER = preload("res://app/weather_particles.gdshader")
const DRAW_SHADER = preload("res://app/weather_drops.gdshader")

const VALUES := ["wind", "rain", "dust", "visibility", "solar", "lightning", "wet"]
const SMOOTH := 2.0                         # seconds the drawn values take to follow the model's (to 63 %)
const CLEAR_FOG := 0.0003                   # lighting.gd's thin haze: never thinner
const HAZE := Color(0.70, 0.76, 0.84)       # lighting.gd's fog colour
const SAND := Color(0.74, 0.62, 0.46)
const RAIN_GREY := Color(0.56, 0.60, 0.64)
const MIST := Color(0.80, 0.82, 0.84)
## The emitter per tier: [particles at most, the box's half width in metres] (REALISM.md §11: the phone ≤ 2,000
## within 25 m, the laptop ≤ 8,000 within 40 m).
const TIERS := {"full": [8000, 40.0], "phone": [2000, 25.0]}
const BOX_HEIGHT := 12.0                    # metres: the box's half height
## The wind blows from the north-west (SITE.md's climate): towards the south-east, in Godot's axes (x east, z south).
const WIND_TO := Vector3(0.70710678, 0.0, 0.70710678)
const FLASH_SLOT := 20                      # model steps (2 s at 1x) in which at most one flash falls
const FLASH_RATE := 0.08                    # flashes per slot at `lightning` 1 (one every 25 s)
const FLASH_TIME := 0.15                    # seconds a flash lights the plant
const FLASH_ENERGY := 3.0                   # the flash's light on top of the sun's

var env: Environment
var sun: DirectionalLight3D
var ui                                      # ui/plant_ui.gd: the clock's engine, the model's weather, the sounds
var camera: Camera3D
var tier := "full"
var particles: GPUParticles3D
var on := false                             # the run has weather (its scenario's world.weather)
var drawn := {}                             # the drawn values (eased): VALUES' names -> float
var look := {}                              # the last look_of(drawn): what was set
var flashes := 0                            # flashes drawn (the tests read it)
var _flash_left := 0.0
var _pending: Array = []                    # flashes to come: [their step, distance]
const THUNDER_MAX := 3
var _thunder: Array = []                    # [seconds left, gain dB] of thunder on its way
var _slots := {}                            # value name -> engine slot
var _engine = null
## The global shader parameters last set (RenderingServer's own getter is for the editor: the tests read these).
static var globals := {}
var _clear_solar: Array = []                # the clear kind's solar table (weather.json), [] without
var _solar_tau := 0.0                       # solar's lag in clock minutes (weather.json)

## Makes the emitter (hidden, not emitting) under `parent`, so that its pipelines are compiled in the start's hidden
## frame with the plant's (decision 0060).
func setup(parent: Node3D, p_env: Environment, p_sun: DirectionalLight3D, p_tier: String) -> void:
	env = p_env
	sun = p_sun
	particles = make_particles("phone")
	set_tier(p_tier)
	parent.add_child(particles)
	var rm: Dictionary = {}
	var pl = parent.get("manifest")
	if pl is Dictionary:
		rm = pl.get("roof_map", {})
	set_roof_map(rm)
	_apply_globals({"wet": 0.0, "dust_laid": 0.0, "rain": 0.0})

## The emitter's size for a tier (main.gd's: "full", else the phone's): the tier can be chosen after the plant
## loads (a desktop's first start measures its GPU) or changed in the settings.
func set_tier(t: String) -> void:
	tier = "full" if t == "full" else "phone"
	size_for(particles, tier)

static func size_for(p: GPUParticles3D, t: String) -> void:
	var spec: Array = TIERS[t]
	if p.amount != int(spec[0]):
		p.amount = int(spec[0])
	var half := Vector3(float(spec[1]), BOX_HEIGHT, float(spec[1]))
	p.visibility_aabb = AABB(-half - Vector3.ONE, (half + Vector3.ONE) * 2.0)
	(p.process_material as ShaderMaterial).set_shader_parameter("half_box", half)
	((p.draw_pass_1 as QuadMesh).material as ShaderMaterial).set_shader_parameter("far", float(spec[1]))

static func make_particles(t: String) -> GPUParticles3D:
	var spec: Array = TIERS[t]
	var p := GPUParticles3D.new()
	p.name = "weather"
	p.amount = int(spec[0])
	p.amount_ratio = 0.0
	p.lifetime = 4.0
	p.preprocess = 0.0
	p.explosiveness = 0.0
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var half := Vector3(float(spec[1]), BOX_HEIGHT, float(spec[1]))
	p.visibility_aabb = AABB(-half - Vector3.ONE, (half + Vector3.ONE) * 2.0)
	var pm := ShaderMaterial.new()
	pm.shader = PROCESS_SHADER
	pm.set_shader_parameter("half_box", half)
	p.process_material = pm
	var q := QuadMesh.new()
	var dm := ShaderMaterial.new()
	dm.shader = DRAW_SHADER
	dm.set_shader_parameter("far", float(spec[1]))
	q.material = dm
	p.draw_pass_1 = q
	p.emitting = true   # drawn (and compiled) from the start; amount_ratio 0 shows nothing
	return p

## The roof map's texture and rectangle for the shaders (the build's manifest `roof_map`; {} for none).
static func set_roof_map(rm: Dictionary) -> void:
	var rect := Vector4.ZERO
	var tex: Texture2D = null
	if rm.has("path") and ResourceLoader.exists(String(rm.path)):
		tex = load(String(rm.path)) as Texture2D
		var r: Array = rm.get("rect", [0, 0, 0, 0])
		rect = Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	if tex == null:
		rect = Vector4.ZERO
		var img := Image.create(1, 1, false, Image.FORMAT_R8)
		tex = ImageTexture.create_from_image(img)
	globals["wx_roof_rect"] = rect
	RenderingServer.global_shader_parameter_set("wx_roof_rect", rect)
	RenderingServer.global_shader_parameter_set("wx_roof", tex)

## The look for a set of the model's weather values (VALUES' names) and a clear sky's solar at the hour (W/m²):
## {fog_density, fog_colour, sky_affect, sun (0–1 of the clear sky's), wet, dust_laid, rain, sand (0–1), mode
## ("rain" or "sand"), ratio (the emitter's share), wind (m/s), velocity}.
static func look_of(v: Dictionary, clear_solar: float) -> Dictionary:
	var vis := maxf(float(v.get("visibility", 20000.0)), 30.0)
	var rain_mm := maxf(float(v.get("rain", 0.0)), 0.0)
	var dust := maxf(float(v.get("dust", 0.0)), 0.0)
	var wind := maxf(float(v.get("wind", 0.0)), 0.0)
	var solar := maxf(float(v.get("solar", 0.0)), 0.0)
	# the meteorological visibility: where the fog lets 5 % through (Koschmieder: e^(−3) ≈ 0.05)
	var density := maxf(CLEAR_FOG, 3.0 / vis)
	var sand_w := clampf((dust - 0.3) / 3.0, 0.0, 1.0)
	var rain_w := clampf(rain_mm / 4.0, 0.0, 1.0)
	var murk := clampf((10000.0 - vis) / 9000.0, 0.0, 1.0)   # how far from a clear view: the mist's share
	var colour := HAZE.lerp(MIST, murk * (1.0 - sand_w) * (1.0 - rain_w))
	colour = colour.lerp(RAIN_GREY, rain_w)
	colour = colour.lerp(SAND, sand_w)
	# by day the model's solar against a clear sky's; at night (the app's sun stays where the sky's is) from the view;
	# blended over the low sun so that dawn and dusk don't jump
	var by_view := clampf(0.15 + 0.85 * minf(vis, 10000.0) / 10000.0 * (1.0 - rain_w), 0.1, 1.0)
	var by_sun := clampf(solar / maxf(clear_solar, 1.0), 0.1, 1.0)
	var sun_f := lerpf(by_view, by_sun, smoothstep(30.0, 200.0, clear_solar))
	var rain := clampf(rain_mm / 10.0, 0.0, 1.0)
	var sand := clampf((dust - 1.0) / 5.0, 0.0, 1.0)
	var mode := "rain" if rain >= sand else "sand"
	var vel := Vector3.ZERO
	if mode == "rain":
		vel = Vector3(0.0, -8.0, 0.0) + WIND_TO * wind * 0.5
	else:
		vel = WIND_TO * maxf(wind, 2.0) + Vector3(0.0, -0.3, 0.0)
	# the photographed sky washed toward the fog's colour: by the short view, and overcast in rain whatever the view
	var sky := maxf(clampf((8000.0 - vis) / 7000.0, 0.0, 1.0) * 0.9, rain_w * 0.8)
	return {"fog_density": density, "fog_colour": colour, "sky_affect": sky,
		"sun": sun_f, "wet": clampf(float(v.get("wet", 0.0)), 0.0, 1.0), "dust_laid": clampf((dust - 0.5) / 5.0, 0.0, 1.0),
		"rain": rain, "sand": sand, "mode": mode, "ratio": maxf(rain, sand), "wind": wind, "velocity": vel,
		"lightning": clampf(float(v.get("lightning", 0.0)), 0.0, 1.0)}

## A measured walk's weather (app/weather_fix.gd).
static func fix(sc: Dictionary, wx: Dictionary, kind: String) -> bool:
	return WeatherFix.fix(sc, wx, kind)

## The value of a table [[x, y], …] at x (linear between its points).
static func table_at(t: Array, x: float) -> float:
	return WeatherFix.table_at(t, x)

## Whether a flash falls in slot k (FLASH_SLOT steps) at `lightning` l, and the step it falls on and the strike's
## distance in metres: the same on every device that steps the run (the world seed and the slot, not a device's
## random numbers). [] for none.
static func flash_in(seed: int, k: int, l: float) -> Array:
	var h := mix32(mix32(seed & 0xFFFFFFFF) ^ (k & 0xFFFFFFFF) ^ 0x464C5348)   # "FLSH"
	var u := float(h & 0xFFFF) / 65536.0
	if l <= 0.0 or u >= l * FLASH_RATE:
		return []
	var at := k * FLASH_SLOT + int((h >> 16) & 0xFF) % FLASH_SLOT
	var dist := 400.0 + float((h >> 24) & 0x7F) / 127.0 * 5600.0
	return [at, dist]

## A 32-bit integer mix (lowbias32): the same on every platform.
static func mix32(x: int) -> int:
	x &= 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 0x7FEB352D) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 0x846CA68B) & 0xFFFFFFFF
	x ^= x >> 16
	return x

## Takes the interaction layer: binds its clock's engine now and whenever the clock takes another (a restart, a
## session's install before its catch-up steps: their slots' flashes are decided with the new engine).
func attach(p_ui) -> void:
	ui = p_ui
	if ui == null or ui.clock == null:
		return
	if not ui.clock.restarted.is_connected(_bind):
		ui.clock.restarted.connect(_bind)
	if not ui.clock.stepped.is_connected(_on_step):
		ui.clock.stepped.connect(_on_step)
	_bind(ui.clock.engine)

func _process(delta: float) -> void:
	if ui == null or ui.clock == null:
		return
	var e = ui.clock.engine
	if e != _engine:
		_bind(e)
	if not on:
		return
	var ws = ui.main.get("workshop") if ui.get("main") != null else null
	var in_workshop: bool = ws != null and bool(ws.get("is_open"))
	var a := 1.0 - exp(-delta / SMOOTH)
	for id in _slots:   # a value the content's weather does not drive keeps look_of's clear-weather default
		var x := float(e.cur[_slots[id]])
		drawn[id] = x if not drawn.has(id) else lerpf(float(drawn[id]), x, a)
	var hour := float(e.v("world_hour")) if e.ix.has("world_hour") else 12.0
	# the clear sky's solar as the model's lagged solar would be in clear weather: a first-order lag follows a ramp
	# about tau behind it (else the sun would dip at every dawn while the model's solar catches up)
	look = look_of(drawn, table_at(_clear_solar, fposmod(hour - _solar_tau / 60.0, 24.0)))
	_flash(e, delta)
	_apply(look)
	if in_workshop:   # the Workshop's bench is indoors: its materials (the same shader) stay dry and clean
		_apply_globals({"wet": 0.0, "dust_laid": 0.0, "rain": 0.0})
	if camera != null and is_instance_valid(camera):
		particles.global_position = camera.global_position

## Takes the clock's engine (a new run, a session's engine adopted): weather on when its scenario has it.
func _bind(e) -> void:
	_engine = e
	_slots.clear()
	drawn.clear()
	_thunder.clear()
	# flashes still to come stay (a session's resync installs its engine mid-slot); a new run's start at step 0
	# leaves none
	var st: int = int(e.step_no) if e != null else 0
	_pending = _pending.filter(func(f): return int(f[0]) > st)
	if ui != null and ui.clock != null and not ui.clock.stepped.is_connected(_on_step):
		ui.clock.stepped.connect(_on_step)
	on = e != null and e.ix.has("world_wx")
	_clear_solar = []
	if on:
		for id in VALUES:
			if e.ix.has(id):
				_slots[id] = e.ix[id]
		for k in ui.model.weather.get("kinds", []):
			if k.get("id", "") == "clear":
				_clear_solar = k.get("targets", {}).get("solar", [])
		for v in ui.model.weather.get("values", []):
			if v.get("id", "") == "solar":
				_solar_tau = float(v.get("tau", 0.0))
	else:
		_clear()

## Back to the plant's own light (a run without weather).
func _clear() -> void:
	look = {}
	if env != null:
		env.fog_density = CLEAR_FOG
		env.fog_light_color = HAZE
		env.fog_sky_affect = 0.0
		env.fog_light_energy = 1.0
	if sun != null:
		sun.light_energy = Lighting.SUN_ENERGY
		sun.shadow_opacity = 1.0
	if particles != null:
		particles.amount_ratio = 0.0
		particles.visible = false
	_apply_globals({"wet": 0.0, "dust_laid": 0.0, "rain": 0.0})
	if ui != null and ui.get("sounds") != null:
		ui.sounds.weather = {}

func _apply(l: Dictionary) -> void:
	env.fog_density = l.fog_density
	env.fog_light_color = l.fog_colour
	env.fog_sky_affect = l.sky_affect
	env.fog_light_energy = lerpf(0.55, 1.0, l.sun) + (0.6 if _flash_left > 0.0 else 0.0)
	sun.light_energy = Lighting.SUN_ENERGY * l.sun + (FLASH_ENERGY if _flash_left > 0.0 else 0.0)
	sun.shadow_opacity = lerpf(0.25, 1.0, smoothstep(0.2, 0.8, l.sun))
	_apply_globals(l)
	particles.amount_ratio = l.ratio
	particles.visible = l.ratio > 0.001   # nothing drawn in clear weather (its pipelines compiled at the start)
	var pm := particles.process_material as ShaderMaterial
	pm.set_shader_parameter("velocity", l.velocity)
	var dm := (particles.draw_pass_1 as QuadMesh).material as ShaderMaterial
	dm.set_shader_parameter("velocity", l.velocity)
	if l.mode == "rain":
		dm.set_shader_parameter("length_s", 0.05)
		dm.set_shader_parameter("width", 0.012)
		dm.set_shader_parameter("min_length", 0.0)
		dm.set_shader_parameter("colour", Color(0.78, 0.80, 0.84, 0.35))
	else:
		dm.set_shader_parameter("length_s", 0.01)
		dm.set_shader_parameter("width", 0.03)
		dm.set_shader_parameter("min_length", 0.03)
		dm.set_shader_parameter("colour", Color(0.72, 0.60, 0.44, 0.55))
	if ui.get("sounds") != null:
		ui.sounds.weather = {"wind": wind_gain(l.wind), "rain": l.rain, "sand_hiss": l.sand}

## The wind's loop by the model's wind: as before weather (1) at the clear kind's 2 m/s, about +5 dB in a sandstorm.
static func wind_gain(w: float) -> float:
	return clampf(0.6 + 0.2 * w, 0.6, 1.8)

static func _apply_globals(l: Dictionary) -> void:
	for kv in [["wx_wet", "wet"], ["wx_dust", "dust_laid"], ["wx_rain", "rain"]]:
		var x := float(l.get(kv[1], 0.0))
		globals[kv[0]] = x
		RenderingServer.global_shader_parameter_set(kv[0], x)

## Lightning, after every model step (the clock's `stepped`): at each slot's first step, whether a flash falls in it
## by the model's own `lightning` there (every peer steps the same values: never this device's eased ones), kept until
## its step comes. Thunder follows a flash after the strike's distance at 343 m/s.
func _on_step(e) -> void:
	if not on or e != _engine or not _slots.has("lightning") or int(e.step_no) % FLASH_SLOT != 0:
		return
	var f := flash_in(int(e.get("_world_seed")), int(e.step_no) / FLASH_SLOT, float(e.cur[_slots["lightning"]]))
	if not f.is_empty():
		_pending.append(f)

## The flashes whose step has come: each counted and lit (several in one frame, in fast play, light it once), the
## thunder of at most the last THUNDER_MAX of them.
func _flash(e, delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	var keep_p: Array = []
	for f in _pending:
		if int(f[0]) > int(e.step_no):
			keep_p.append(f)
			continue
		flashes += 1
		_flash_left = FLASH_TIME
		var d := float(f[1])
		_thunder.append([d / 343.0, -20.0 * log(d / 400.0) / log(10.0)])
	_pending = keep_p
	if _thunder.size() > THUNDER_MAX:
		_thunder = _thunder.slice(_thunder.size() - THUNDER_MAX)
	var keep: Array = []
	for t in _thunder:
		t[0] -= delta
		if t[0] <= 0.0:
			if ui.get("sounds") != null:
				ui.sounds.once("thunder", null, t[1])
		else:
			keep.append(t)
	_thunder = keep
