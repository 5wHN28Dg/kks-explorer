## The model step's cost with a synthetic realism load (docs/plant3d/REALISM.md §11, milestone RE1): the first train
## as built, then with each load made by tools/plant3d/realism_synth.py (N values shaped like the realism content,
## appended to the last area's model file, and a `world` in every scenario), each over the cold start run by its
## procedure and then at base load (as sim/tests/bench_step.gd). Measured where it runs: sim/tests/bench_realism.gd on
## a desktop, the app's `step=bench` option on a phone (app/main.gd; the loads read from its files folder, the
## result in step.txt there).
extends RefCounted

const PlantModel = preload("../sim/plant_model.gd")
const PlantEngine = preload("../sim/engine.gd")
const Procedure = preload("../sim/procedure.gd")
const JsonStrict = preload("../sim/json_strict.gd")
const WeatherFix = preload("weather_fix.gd")


## The content folder's files, read and parsed (as PlantModel.from_dir reads them).
static func read_dir(path: String) -> Dictionary:
	var files := {}
	var top := path.trim_suffix("/")
	for rel in ["plant.json", "kit.json", "sounds.json", "staff.json", "weather.json"]:
		if FileAccess.file_exists(top + "/" + rel):
			files[rel] = FileAccess.get_file_as_bytes(top + "/" + rel)
	for sub in ["areas", "model", "scenarios", "procedures"]:
		var d := DirAccess.open(top + "/" + sub)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".json"):
				files[sub + "/" + f] = FileAccess.get_file_as_bytes(top + "/" + sub + "/" + f)
	return files


## files with a synthetic load (realism_synth.py's output, its text) applied as realism_synth.apply does; {} when it
## can't be read (a load comes from a phone's shared folder: never trusted to be well formed).
static func with_load(files: Dictionary, synth_text: String) -> Dictionary:
	var r := JsonStrict.parse(synth_text.to_utf8_buffer(), 1000)
	if not r.ok or typeof(r.value) != TYPE_DICTIONARY or typeof(r.value.get("area")) != TYPE_STRING \
			or typeof(r.value.get("values")) != TYPE_ARRAY:
		return {}
	var out := files.duplicate()
	var rel := "model/%s.json" % r.value["area"]
	if not files.has(rel):
		return {}
	var mr := _parse(files[rel])
	if not mr.ok:
		return {}
	var m: Dictionary = mr.value
	m["values"] = m["values"] + r.value["values"]
	m["version"] = 2
	out[rel] = m
	# realism_synth.py --engine: the weather (REALISM.md §5.1, milestone WX1), its ext values set in every scenario
	var wx = r.value.get("weather")
	var ext = r.value.get("ext", {})
	if typeof(wx) != TYPE_NIL and (typeof(wx) != TYPE_DICTIONARY or typeof(ext) != TYPE_DICTIONARY):
		return {}
	if wx != null:
		out["weather.json"] = wx
		var p: Dictionary = _parse(files["plant.json"]).value
		p["ext"] = p["ext"] + ext.keys()
		out["plant.json"] = p
	for k in files:
		if k.begins_with("scenarios/"):
			var sc: Dictionary = _parse(files[k]).value
			sc["version"] = 2
			if not sc.has("world"):
				sc["world"] = {}
			if wx != null:
				sc["init"].merge(ext, true)
				sc["world"]["weather"] = {"season": "year"}
			out[k] = sc
	return out


## A content file as read_dir gives it (its bytes) or as text, parsed.
static func _parse(x) -> Dictionary:
	return JsonStrict.parse(x.to_utf8_buffer() if typeof(x) == TYPE_STRING else x, 1000)


## The measurement: loads {label: realism_synth text} ("" for the train as built, always first); its result lines.
## cold_iron's weather is fixed at `weather` (clear unless asked otherwise, as a measured walk's: app/main.gd
## measured_weather) where the run has the built weather.json; a load with its own weather (realism_synth --engine)
## keeps its seeded chain, whose hourly draws are what it measures.
static func run(files: Dictionary, loads: Dictionary, base_steps: int = 6000, weather: String = "clear") -> PackedStringArray:
	var out := PackedStringArray()
	var labels := [""]
	labels.append_array(loads.keys())
	for label in labels:
		var f: Dictionary = files if label == "" else with_load(files, loads[label])
		var name: String = "built" if label == "" else label
		if f.is_empty():
			out.append("ERROR %s: the load can't be read (strict JSON with an area of the plant and values)" % name)
			continue
		var m = PlantModel.from_files(f)
		if m.error != "":
			out.append("ERROR %s: %s" % [name, m.error])
			continue
		var wx := "seeded"
		if typeof(f.get("weather.json")) != TYPE_DICTIONARY and weather != "":
			if m.weather == null or not WeatherFix.fix(m.scenarios.get("cold_iron", {}), m.weather, weather):
				out.append("ERROR %s: weather=%s: cold_iron has no weather, or the kind is unknown" % [name, weather])
				continue
			wx = weather
		var e = PlantEngine.new(m, "cold_iron")
		e.timing = true
		var r: Dictionary = Procedure.run(m, "cold_start", 3600, e, null, Callable())
		e.timing = false
		if r.error != "":
			out.append("ERROR %s: %s" % [name, r.error])
			continue
		out.append("STEP load=%s values=%d weather=%s world=%s phase=cold_start %s" % [name, m.values.size(), wx,
				str(e._world), _stats(e.step_us)])
		var t := PackedInt64Array()
		t.resize(base_steps)
		for k in base_steps:
			var s := Time.get_ticks_usec()
			e.step()
			t[k] = Time.get_ticks_usec() - s
		out.append("STEP load=%s values=%d phase=base_load %s" % [name, m.values.size(), _stats(t)])
		var s2 := Time.get_ticks_usec()
		e.step(base_steps)
		var per := float(Time.get_ticks_usec() - s2) / base_steps
		out.append("BATCH load=%s values=%d steps=%d mean_us=%.1f ff_max=%dx" % [name, m.values.size(), base_steps,
				per, int(1e6 / per / 10.0)])
		if e._wx != null:
			# the weather step alone (REALISM.md §11: ≤ 0.02 ms): its lags as in most steps, and with an hour crossed
			# (one draw, the values set to their targets, as in a jump's step)
			var lags := _weather_us(e, 0)
			var hour := _weather_us(e, 36000)
			out.append("WEATHER load=%s values=%d calls=%d lags_mean_us=%.2f hour_mean_us=%.2f" % [name,
					e._wx["slots"].size(), WX_CALLS, lags, hour])
	return out


const WX_CALLS := 20000


## The weather step's mean time over WX_CALLS calls, on a clone (the engine measured is left as it was); a call that
## changes the kind makes its event, as the step would.
static func _weather_us(e, gap: int) -> float:
	var c = e.clone()
	var s := Time.get_ticks_usec()
	for k in WX_CALLS:
		c._weather(gap, c.wx_kind)
	return float(Time.get_ticks_usec() - s) / WX_CALLS


static func _stats(t: PackedInt64Array) -> String:
	if t.is_empty():
		return "steps=0"
	var s := Array(t)
	s.sort()
	var total := 0
	for x in t:
		total += x
	var mean := float(total) / t.size()
	return "steps=%d mean_us=%.1f p50_us=%d p99_us=%d max_us=%d ff_max=%dx" % [t.size(), mean, s[s.size() / 2],
			s[int(s.size() * 0.99)], s[-1], int(1e6 / mean / 10.0)]
