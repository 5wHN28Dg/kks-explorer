extends RefCounted
## Walkdown Plant's realism base (docs/plant3d/REALISM.md §2.1, milestone RE1) as the engine runs it: the world's
## seed, its random streams by purpose and item id, and the clock values `world_hour` and `world_day`. Bit for bit
## with ref/plant3d_world.py on ref/vectors/plant3d-realism.json.

const Staff = preload("staff.gd")

## The purpose tags (§2.1).
const TAGS := {"draw": 0x44524157, "causes": 0x43415553, "weather": 0x57454154, "stores": 0x53544f52,
		"lab": 0x4c414253, "slips": 0x534c4950, "audio": 0x41554449}
## The clock values: engine-kept slots after every other value, only in a scenario with `world`.
const NAMES := ["world_hour", "world_day"]
const DAY := 864000
const HOUR := 36000


## FNV-1a, 32 bits, over the UTF-8 bytes of an item's id.
static func fnv1a(text: String) -> int:
	var h := 2166136261
	for c in text.to_utf8_buffer():
		h = Staff.mul32(h ^ c, 16777619)
	return h


## A stream's first state: mix32(mix32(seed ^ tag) ^ FNV-1a(item)), 1 for 0.
static func stream(seed: int, tag: int, item: String) -> int:
	var s := Staff.mix32(Staff.mix32(seed ^ tag) ^ fnv1a(item))
	return s if s != 0 else 1


## One draw (§17.5's generator): [the next state, r of 24 bits].
static func draw(s: int) -> Array:
	s ^= (s << 13) & 0xFFFFFFFF
	s ^= s >> 17
	s ^= (s << 5) & 0xFFFFFFFF
	return [s, s >> 8]


## The world's seed: its own, else the staff's, else 1.
static func seed_of(sc: Dictionary) -> int:
	var w: Dictionary = sc.get("world", {})
	if w.has("seed"):
		return int(w["seed"])
	if sc.has("staff"):
		return int(sc["staff"]["seed"])
	return 1


## world_hour, (C mod 864,000) / 36,000 in doubles, and world_day, C div 864,000 (C never negative).
static func hour_of(c: int) -> float:
	return float(c % DAY) / float(HOUR)


static func day_of(c: int) -> float:
	return float(c / DAY)


# ---------------------------------------------------------------- the weather (REALISM.md §5.1, milestone WX1)

## The weather's kind: an engine-kept value after the clock values, in a scenario with world.weather.
const WX_NAME := "world_wx"


## COURSES.md §9.2's piecewise linear table (rows flattened x0, y0, x1, y1, …), as ref/courses.py table_at.
static func table_at(t: PackedFloat64Array, u: float) -> float:
	var cnt := t.size() / 2
	if u < t[0]:
		return t[1]
	if u >= t[2 * (cnt - 1)]:
		return t[2 * (cnt - 1) + 1]
	var i := 0
	for j in cnt:
		if t[2 * j] <= u:
			i = j
		else:
			break
	var x0 := t[2 * i]
	var y0 := t[2 * i + 1]
	var x1 := t[2 * i + 2]
	var y1 := t[2 * i + 3]
	return y0 + (y1 - y0) * (u - x0) / (x1 - x0)


## The days of the year a season's [first, last] covers (first > last runs over the year's end).
static func season_days(days: Array) -> Array:
	var a := int(days[0])
	var z := int(days[1])
	var out := []
	if a <= z:
		for d in range(a, z + 1):
			out.append(d)
	else:
		for d in range(a, 366):
			out.append(d)
		for d in range(1, z + 1):
			out.append(d)
	return out


## The day of the year at the clock c: (year_day − 1 + world_day − 1) mod 365 + 1.
static func year_day_of(year_day: int, c: int) -> int:
	return posmod(year_day - 1 + c / DAY - 1, 365) + 1


static func _flat(t: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for row in t:
		out.append(float(row[0]))
		out.append(float(row[1]))
	return out


## The weather as the engine runs it, for a scenario with world.weather (as ref/plant3d_world.py build_weather): the
## kinds, mode (0 seeded by season, 1 fixed, 2 scripted) and script ([clock, kind]), each day's season, the hourly rows
## per season and kind ([to kinds, weights, total]), the driven values' slots and lag factors 1 − e^(−0.1 × day_scale /
## (60 × tau)), the targets per kind and value, the kind's slot, and the state at step 0 (k0, s0).
static func build_weather(sc: Dictionary, wd: Dictionary, ix: Dictionary, ds: int, seed: int, start: int) -> Dictionary:
	var w: Dictionary = sc["world"]["weather"]
	var kinds := []
	for k in wd["kinds"]:
		kinds.append(k["id"])
	var season_of := PackedInt32Array()
	season_of.resize(366)
	var rows := []
	for si in wd["seasons"].size():
		var s: Dictionary = wd["seasons"][si]
		for d in season_days(s["days"]):
			season_of[d] = si
		var per := []
		for k in kinds:
			var tos := PackedInt32Array()
			var ws := PackedInt32Array()
			var total := 0
			for r in s["hourly"]:
				if r[0] == k:
					tos.append(kinds.find(r[1]))
					ws.append(int(r[2]))
					total += int(r[2])
			per.append([tos, ws, total])
		rows.append(per)
	var mode := 0
	var k0 := 0
	var script := []
	if w.has("season"):
		for s in wd["seasons"]:
			if s["id"] == w["season"]:
				k0 = kinds.find(s["start"])
	elif w.has("fixed"):
		mode = 1
		k0 = kinds.find(w["fixed"])
	else:
		mode = 2
		for e in w["script"]:
			var t := (int(e[0]) * 1440 + Staff.hhmm(e[1])) * 600
			script.append([t, kinds.find(e[2])])
			if t <= start:
				k0 = kinds.find(e[2])
	var slots := PackedInt32Array()
	var factors := PackedFloat64Array()
	for v in wd["values"]:
		slots.append(ix[v["id"]])
		factors.append(1.0 - exp(-0.1 * float(ds) / (60.0 * float(v["tau"]))))
	var targets := []
	for k in wd["kinds"]:
		var per := []
		for v in wd["values"]:
			per.append(_flat(k["targets"][v["id"]]))
		targets.append(per)
	return {"kinds": kinds, "mode": mode, "script": script, "season_of": season_of, "rows": rows,
			"year_day": int(sc["world"].get("year_day", 1)), "slot": ix[WX_NAME], "slots": slots, "factors": factors,
			"targets": targets, "k0": k0, "s0": stream(seed, TAGS["weather"], "weather")}
