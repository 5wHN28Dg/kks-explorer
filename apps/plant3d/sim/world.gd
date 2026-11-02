extends RefCounted
## Walkdown Plant's realism base (docs/plant3d/REALISM.md §2.1, milestone RE1) as the engine runs it: the world's
## seed, its random streams by purpose and item id, and the clock values `world_hour` and `world_day`. Bit for bit
## with ref/plant3d_world.py on ref/vectors/plant3d-realism.json.

const Staff = preload("staff.gd")

## The purpose tags (§2.1).
const TAGS := {"draw": 0x44524157, "causes": 0x43415553, "weather": 0x57454154, "stores": 0x53544f52,
		"lab": 0x4c414253, "slips": 0x534c4950}
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
