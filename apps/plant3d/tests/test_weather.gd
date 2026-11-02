## The weather seen and heard (docs/plant3d/REALISM.md §5.4, milestone WX3; app/weather_view.gd): the look for each
## kind of the first train's weather.json (the fog at the model's visibility, sand or rain particles, wet and dusty
## surfaces, the sun), the measured walk's fixed weather, the lightning's flashes placed by the run (the same on every
## device), the build's roof map, and in the app: a scenario with weather draws it (the fog, the shaders' global
## parameters, the emitter, the ambiences), the instructor's panel sets a kind, a scenario without weather is clear.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const WeatherView = preload("res://app/weather_view.gd")
const Lighting = preload("res://app/lighting.gd")



static func _weather_json() -> Dictionary:
	var f := FileAccess.open("res://built/content/weather.json", FileAccess.READ)
	if f == null:
		f = FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/weather.json"), FileAccess.READ)
	return {} if f == null else JSON.parse_string(f.get_as_text())


static func _at(k: Dictionary, hour: float) -> Dictionary:
	var v := {}
	for id in k.targets:
		v[id] = WeatherView.table_at(k.targets[id], hour)
	return v


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += _looks()
	p += _fix()
	p += _flashes()
	p += _roof_map()
	p += await _app(tree)
	return p


## Each kind at noon and at night: the fog lets 5 % through at the model's visibility (never thinner than the thin
## haze), sand in a sandstorm and rain in rain, nothing falls in clear weather, wet only in rain, the sun dims in
## a storm.
func _looks() -> Array:
	var p: Array = []
	var wx := _weather_json()
	if wx.is_empty():
		return ["data/plant3d/weather.json did not load"]
	var clear_solar: Array = []
	for k in wx.kinds:
		if k.id == "clear":
			clear_solar = k.targets.solar
	var by := {}
	for k in wx.kinds:
		for hour in [12.0, 2.0]:
			var v := _at(k, hour)
			var l := WeatherView.look_of(v, WeatherView.table_at(clear_solar, hour))
			by["%s@%d" % [k.id, int(hour)]] = l
			var vis := float(v.visibility)
			var want := maxf(WeatherView.CLEAR_FOG, 3.0 / vis)
			if absf(l.fog_density - want) > 1e-9:
				p.append("%s at %d h: fog %f for visibility %d m (want %f)" % [k.id, hour, l.fog_density, vis, want])
			if vis < 9000.0 and absf(exp(-l.fog_density * vis) - exp(-3.0)) > 1e-6:
				p.append("%s: the fog does not let 5 %% through at the model's visibility" % k.id)
			for key in ["sun", "wet", "dust_laid", "rain", "sand", "ratio", "sky_affect"]:
				if float(l[key]) < 0.0 or float(l[key]) > 1.0:
					p.append("%s: %s %f outside 0-1" % [k.id, key, l[key]])
	var c: Dictionary = by["clear@12"]
	if c.ratio != 0.0 or c.wet != 0.0 or c.dust_laid != 0.0 or c.fog_density != WeatherView.CLEAR_FOG or c.sun != 1.0 \
			or c.sky_affect != 0.0:
		p.append("clear weather is not the plant's own look: %s" % str(c))
	var s: Dictionary = by["sandstorm@12"]
	if s.mode != "sand" or s.ratio < 0.9 or s.sky_affect < 0.8 or s.sun > 0.4 or s.dust_laid < 0.9:
		p.append("a sandstorm is not drawn as one: %s" % str(s))
	if s.fog_colour.r <= s.fog_colour.b:
		p.append("a sandstorm's fog is not sand-coloured: %s" % str(s.fog_colour))
	for k in ["rain@12", "thunderstorm@12"]:
		var r: Dictionary = by[k]
		if r.mode != "rain" or r.ratio <= 0.3 or r.wet != 1.0 or r.velocity.y > -5.0:
			p.append("%s is not drawn as rain: %s" % [k, str(r)])
	if by["thunderstorm@12"].lightning != 1.0 or by["rain@12"].lightning != 0.0:
		p.append("lightning only in a thunderstorm")
	if by["dust_haze@12"].ratio > 0.2 or by["dust_haze@12"].fog_density <= WeatherView.CLEAR_FOG:
		p.append("dust haze is a haze, not a storm: %s" % str(by["dust_haze@12"]))
	if by["fog@2"].ratio != 0.0 or by["fog@2"].fog_density < 0.005:
		p.append("fog at night is thick and nothing falls: %s" % str(by["fog@2"]))
	return p


## The measured walk's weather: fixed, its values at the kind's targets for the start hour; refused without weather.
func _fix() -> Array:
	var p: Array = []
	var wx := _weather_json()
	var sc := {"start": {"day": 1, "time": "13:00"}, "world": {"weather": {"season": "summer"}},
		"init": {"dust": 0.08, "visibility": 20000, "wind": 2, "ambient_t": 35}}
	if not WeatherView.fix(sc, wx, "sandstorm"):
		return ["fix refused a scenario with weather"]
	if sc.world.weather != {"fixed": "sandstorm"}:
		p.append("fix did not fix the weather: %s" % str(sc.world))
	if absf(float(sc.init.dust) - (6.0 + 4.0 / 14.0 * 13.0)) > 1e-9 or float(sc.init.visibility) > 400.0:
		p.append("fix did not set the values at 13:00's targets: %s" % str(sc.init))
	if sc.init.ambient_t != 35 or sc.init.has("rain"):
		p.append("fix changed values the weather does not drive, or added some: %s" % str(sc.init))
	if WeatherView.fix({"init": {}}, wx, "sandstorm") or WeatherView.fix(sc, wx, "snow"):
		p.append("fix took a scenario without weather or an unknown kind")
	return p


## Flashes: the same for the same seed and slot, none without lightning, about FLASH_RATE a slot at full.
func _flashes() -> Array:
	var p: Array = []
	var n := 0
	for k in 20000:
		var f := WeatherView.flash_in(7, k, 1.0)
		if f != WeatherView.flash_in(7, k, 1.0):
			return ["a flash differs between two asks"]
		if not f.is_empty():
			n += 1
			if int(f[0]) / WeatherView.FLASH_SLOT != k or float(f[1]) < 400.0 or float(f[1]) > 6000.0:
				p.append("slot %d: a flash at step %d, %f m" % [k, f[0], f[1]])
				break
		if not WeatherView.flash_in(7, k, 0.0).is_empty():
			return ["a flash without lightning"]
	var rate := n / 20000.0
	if absf(rate - WeatherView.FLASH_RATE) > 0.01:
		p.append("flashes at %f a slot, not about %f" % [rate, WeatherView.FLASH_RATE])
	if WeatherView.mix32(12345) != WeatherView.mix32(12345 + 0x100000000) or WeatherView.mix32(12345) < 0 \
			or WeatherView.mix32(12345) > 0xFFFFFFFF or WeatherView.mix32(1) == WeatherView.mix32(2):
		p.append("mix32 is not a 32-bit mix")
	return p


## The build's roof map: covers the plant; a hall's floor is under a roof, the open ground far from buildings is not.
func _roof_map() -> Array:
	var f := FileAccess.open("res://built/plant.json", FileAccess.READ)
	if f == null:
		return []   # no build: the app's tests below say so
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	var rm: Dictionary = m.get("roof_map", {})
	if not rm.has("path") or not ResourceLoader.exists(rm.path):
		return ["the build has no roof map: %s" % str(rm)]
	var img := (load(rm.path) as Texture2D).get_image()
	var r: Array = rm.rect
	var roofed := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).r8 > 0:
				roofed += 1
	var share := float(roofed) / (img.get_width() * img.get_height())
	if share < 0.02 or share > 0.6:
		return ["the roof map covers %.1f %% of the plant" % (share * 100.0)]
	if absf(float(r[2]) - img.get_width() * 0.5) > 1e-6 or absf(float(r[3]) - img.get_height() * 0.5) > 1e-6:
		return ["the roof map's rect %s does not match its %dx%d half-metre texels" % [str(r), img.get_width(), img.get_height()]]
	# the steam turbine hall's middle is under its roof (at its height); the plant's start, in the open, is not
	var p: Array = []
	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://built/content/areas/st.json"))
	var hall: Dictionary = {}
	for x in st.get("structures", []):
		if x.get("part", "") == "building" and hall.is_empty():
			hall = x
	if hall.is_empty():
		return ["no building in areas/st.json"]
	var c := Vector2.ZERO
	for q in hall.params.outline:
		c += Vector2(float(q[0]), float(q[1]))
	c /= hall.params.outline.size()
	var yaw := -deg_to_rad(float(hall.get("yaw", 0)))
	var at := c.rotated(yaw) + Vector2(float(hall.at[0]), float(hall.at[1]))   # plan axes (x east, y north)
	var h := _roof(img, r, Vector3(at.x, 0.0, -at.y))
	if absf(h - float(hall.params.height)) > 0.3:
		p.append("the roof map gives %.2f m over the turbine hall's middle (%s), not its %.1f m" % [h, str(at), float(hall.params.height)])
	var s0: Array = m.start.at
	if _roof(img, r, Vector3(float(s0[0]), 0.0, float(s0[2]))) != 0.0:
		p.append("the roof map puts a roof over the plant's start, in the open")
	return p


## The roof's height over a point (Godot's axes) by the roof map, as the shaders read it.
static func _roof(img: Image, r: Array, at: Vector3) -> float:
	var u := (at.x - float(r[0])) / float(r[2])
	var v := (at.z - float(r[1])) / float(r[3])
	var i := clampi(int(u * img.get_width()), 0, img.get_width() - 1)
	var j := clampi(int(v * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(i, j).r8 * 0.25


func _app(tree: SceneTree) -> Array:
	var p: Array = []
	var main: Node = App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or main.weather == null:
		main.free()
		return ["the app did not start with its weather view"]
	await tree.process_frame
	var wv = main.weather
	var e = ui.clock.engine
	if wv.on or e.ix.has("world_wx"):
		p.append("cold_iron has no weather, yet the view is on")
	if WeatherView.globals.get("wx_wet") != 0.0 or not is_equal_approx(main.env.fog_density, WeatherView.CLEAR_FOG):
		p.append("without weather the plant is not at its own look: wet %s, fog %f" % [str(WeatherView.globals.get("wx_wet")), main.env.fog_density])
	var rect: Vector4 = WeatherView.globals.get("wx_roof_rect")
	if FileAccess.file_exists("res://built/plant.json") and rect.z <= 0.0:
		p.append("the roof map was not handed to the shaders")
	# a scenario with weather: the instructor sets a sandstorm, the values jump to its targets (a jump's step)
	ui.restart("shift_cold", true)
	await tree.process_frame
	e = ui.clock.engine
	if not wv.on:
		p.append("shift_cold has weather, yet the view is off")
	ui.set_instructor(true)
	ui.toggle_trainer()
	var sand: Button = App.find_button(ui.trainer, "Sandstorm")
	if sand == null:
		main.free()
		return p + ["the instructor's panel has no Sandstorm button"]
	sand.pressed.emit()
	ui.clock.run_steps(1)
	var kinds: Array = ui.model.weather.kinds
	if String(kinds[int(e.wx_kind)].id) != "sandstorm":
		p.append("the instructor's Sandstorm did not set the kind (%d)" % int(e.wx_kind))
	ui.trainer.refresh()
	await tree.process_frame
	if App.find_button(ui.trainer, "Sandstorm") == null or not App.find_button(ui.trainer, "Sandstorm").disabled:
		p.append("the panel does not show the sandstorm as the kind now")
	# the lags take minutes: put the driven values at the sandstorm's noon and let the view ease to them
	var sk: Dictionary = {}
	for k in kinds:
		if k.id == "sandstorm":
			sk = k
	for id in WeatherView.VALUES:
		e.cur[e.ix[id]] = WeatherView.table_at(sk.targets[id], 12.0)
	for i in 30:
		wv._process(1.0)
	var l: Dictionary = wv.look
	if absf(main.env.fog_density - 3.0 / WeatherView.table_at(sk.targets.visibility, 12.0)) > 1e-5:
		p.append("the fog is %f in a sandstorm" % main.env.fog_density)
	if wv.particles.amount_ratio < 0.9 or l.get("mode", "") != "sand":
		p.append("no blown sand in a sandstorm (ratio %f, %s)" % [wv.particles.amount_ratio, l.get("mode", "")])
	if float(WeatherView.globals.get("wx_dust")) < 0.9:
		p.append("no laid dust in a sandstorm")
	if main.sun.light_energy > Lighting.SUN_ENERGY * 0.5:
		p.append("the sun is not dimmed in a sandstorm (%f)" % main.sun.light_energy)
	ui.sounds.outdoors = 1.0
	if ui.sounds.ambience_gain("sand_hiss") < 0.9 or ui.sounds.ambience_gain("wind") <= 1.5:
		p.append("no sand or strong wind heard outdoors in a sandstorm: %s" % str(ui.sounds.weather))
	ui.sounds.outdoors = 0.0
	if ui.sounds.ambience_gain("sand_hiss") != 0.0:
		p.append("blown sand heard indoors")
	if not wv.particles.visible:
		p.append("the emitter is hidden in a sandstorm")
	if wv.particles.amount != 8000 or (wv.particles.process_material as ShaderMaterial).get_shader_parameter("half_box").x != 40.0:
		p.append("the full tier (headless) does not get 8,000 particles within 40 m: %d" % wv.particles.amount)
	wv.set_tier("lean+vis")
	if wv.particles.amount != 2000 or (wv.particles.process_material as ShaderMaterial).get_shader_parameter("half_box").x != 25.0:
		p.append("the phone tier does not get 2,000 particles within 25 m: %d" % wv.particles.amount)
	wv.set_tier("full")
	if (wv.particles.global_position - ui.player.camera.global_position).length() > 0.01:
		p.append("the emitter does not follow the camera")
	# rain: wet surfaces, rain heard (on the roof too, indoors)
	var rk: Dictionary = {}
	for k in kinds:
		if k.id == "thunderstorm":
			rk = k
	for id in WeatherView.VALUES:
		e.cur[e.ix[id]] = WeatherView.table_at(rk.targets[id], 12.0)
	for i in 30:
		wv._process(1.0)
	if float(WeatherView.globals.get("wx_wet")) < 0.9 or wv.look.mode != "rain":
		p.append("a thunderstorm is not wet and raining")
	ui.sounds.outdoors = 1.0
	if absf(ui.sounds.ambience_gain("rain") - 1.0) > 0.01:
		p.append("rain is not heard outdoors at its full level: %f" % ui.sounds.ambience_gain("rain"))
	ui.sounds.outdoors = 0.0
	if absf(ui.sounds.ambience_gain("rain") - SoundPlayerRef.ROOF_RAIN) > 0.01:
		p.append("rain on the roof is not heard indoors at ROOF_RAIN")
	if absf(WeatherView.wind_gain(2.0) - 1.0) > 1e-6:
		p.append("clear weather's wind is not as loud as before weather")
	# the flashes follow the model's lightning at each slot's first step (not the eased value): exactly those
	# flash_in gives, whatever the frames
	var f0: int = wv.flashes
	var seed := int(e.get("_world_seed"))
	var want := [0]
	var count := func(en):
		if int(en.step_no) % WeatherView.FLASH_SLOT == 0 and not WeatherView.flash_in(seed,
				int(en.step_no) / WeatherView.FLASH_SLOT, float(en.cur[en.ix["lightning"]])).is_empty():
			want[0] += 1
	ui.clock.stepped.connect(count)
	for i in 200:
		e.cur[e.ix["lightning"]] = 1.0 if i % 2 == 0 else 0.3
		ui.clock.run_steps(WeatherView.FLASH_SLOT)
		wv._process(0.016)
	ui.clock.run_steps(WeatherView.FLASH_SLOT)
	wv._process(0.016)
	ui.clock.stepped.disconnect(count)
	if want[0] == 0 or wv.flashes - f0 < want[0] - 1 or wv.flashes - f0 > want[0]:
		p.append("%d flashes in 200 slots, the model's lightning at each slot gives %d" % [wv.flashes - f0, want[0]])
	# back to a scenario without weather: the plant's own look again
	ui.restart("cold_iron", true)
	await tree.process_frame
	wv._process(0.1)
	if wv.on or not is_equal_approx(main.env.fog_density, WeatherView.CLEAR_FOG) or wv.particles.amount_ratio != 0.0 \
			or wv.particles.visible \
			or WeatherView.globals.get("wx_wet") != 0.0 or not ui.sounds.weather.is_empty():
		p.append("after a restart without weather the weather is still drawn: on %s, fog %f, ratio %f, wet %s, sounds %s" % [
			wv.on, main.env.fog_density, wv.particles.amount_ratio, str(WeatherView.globals.get("wx_wet")), str(ui.sounds.weather)])
	main.free()
	return p


const SoundPlayerRef = preload("res://ui/sound_player.gd")
