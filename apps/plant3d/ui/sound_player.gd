## Plays the plant's sounds (docs/PLANT3D.md §11) from the files tools/plant3d/sounds makes into built/sounds. Its
## index `index.json` (format `walkdown-plant-sound-files`, tools/plant3d/sounds/README.md) names each sound's layers,
## all played together with the binding's gain, and with its pitch on the layers marked `pitch` (a motor's mains hum
## never is). Bound sounds play at their equipment while the trainee is within earshot; the control room horn sounds
## per priority while an alarm is unacknowledged. One-shots play on edges the app sees, since format 1 binds none: a
## breaker's contacts closing and opening, a large motor's start (its loop waits until the run-up has played), an
## acknowledge. Without built/sounds (the sounds not made) everything here is silent; the hooks are called all the same.
##
## The people cues and the ambience (FIRST-TRAIN §6): a footstep once a stride while the trainee walks, by the floor
## underfoot (the content build marks each walkable slab with its deck, a stair's body as a stair: concrete, steel
## grating, a steel stair tread or chequer plate; a rung at every 0.3 m on a ladder); the doors as they run (a roller
## door's motor and slats while it moves, a sliding door once); outdoors, the wind and the rest of the plant heard
## from afar, at a level set by how much of it runs. A hard limiter on the master bus caps the output level, as the
## plant gets as loud as a real one where a real one is (the content puts hearing-protection signs at those doors).
## None of it costs more than a few sums a frame: the footsteps count metres, the outdoors test is one or two rays
## every 0.1 s.
extends Node3D

const DIR := "res://built/sounds"
const EARSHOT := 50.0           # metres: farther loops are stopped (nothing decodes for nobody)
const UPDATE := 0.1             # seconds between gain and pitch updates
const OUTPUT_CAP_DB := -6.0     # the master bus's ceiling: the app never plays louder than this (dBFS, peak)
const STRIDE := 0.75            # metres between footsteps walking (a step of a 1.6 m/s walk: about 2 a second)
const RUN_STRIDE := 1.1         # and running
const RUNG := 0.3               # metres between a ladder's rungs (builder/plant_builder.gd _ladder)
const FADE := 1.0               # seconds the ambience takes to follow the trainee in or out of a building
const STEP_SOUNDS := {"concrete": "step_concrete", "grating": "step_grating", "stair": "step_stair"}

var index := {}                 # the generator's index: sounds: {id: {loop, layers: [{layer, file, …}]}}
var engine
var muted := false
var _bound: Array = []          # [node, sound id, gain spec, pitch spec, players (or null), layers]
var _streams := {}              # file -> AudioStream
var _horn: AudioStreamPlayer
var _horn_prio := 0
var _hold := {}                 # node -> model step until which its loop waits (a motor's run-up one-shot)
var _edges: Array = []          # [node, value slot, last state]: breakers, by their contacts' value
var _t := 0.0
var listener_at := Vector3.ZERO
var dir := DIR
var walker: CharacterBody3D = null      # the trainee (app/player.gd): footsteps and whether they are outdoors
var played := {}                # sound id -> how many times it was started (the tests read it)
var outdoors := 1.0             # 0 inside a building … 1 outdoors, faded over FADE
var running := 0.0              # how much of the plant runs: the bound loops' mean gain (0–1)
var _walked := 0.0              # metres since the last footstep (or rung)
var _last_at = null             # the walker's last position (null: none yet)
var _steps := {}                # step sound id -> its player (two voices each, no node made per step)
var _rng := RandomNumberGenerator.new()
var _ambience := {}             # wind / plant_distant -> [players]
var _doors := {}                # roller door -> its players while it moves


func _ready() -> void:
	set_meta("ui", true)
	add_to_group("plant_sounds")
	cap_output()
	load_index(dir)


## The output level's cap: a hard limiter last on the master bus, its ceiling OUTPUT_CAP_DB (made once).
static func cap_output() -> AudioEffectHardLimiter:
	var bus := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(bus):
		var fx := AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectHardLimiter:
			return fx
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = OUTPUT_CAP_DB
	AudioServer.add_bus_effect(bus, lim)
	return lim


## Reads the generator's index in `d`; an absent or foreign one leaves the plant silent.
func load_index(d: String) -> void:
	dir = d
	index = {}
	_streams.clear()
	var f := FileAccess.open(d + "/index.json", FileAccess.READ)
	if f == null:
		f = FileAccess.open(d + "/sounds.json", FileAccess.READ)     # the generator's first name for it
	if f == null:
		return
	var j = JSON.parse_string(f.get_as_text())     # the generator's own output: no strictness needed
	if j is Dictionary and j.get("format", "") == "walkdown-plant-sound-files" and j.get("sounds") is Dictionary:
		index = j["sounds"]
		var ls: Array = index.values()[0].get("layers", []) if not index.is_empty() else []
		var first: Dictionary = ls[0] if not ls.is_empty() else {}
		print("plant: sounds: %d in %s, the first file %s" % [index.size(), d,
				"is there" if not first.is_empty() and (ResourceLoader.exists(d + "/" + first["file"]) or FileAccess.file_exists(d + "/" + first["file"])) else "is MISSING"])


func available() -> bool:
	return not index.is_empty()


func _stream(file: String, loop: bool) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var p := dir + "/" + file
	var s: AudioStream = null
	if ResourceLoader.exists(p):
		s = load(p)
	elif FileAccess.file_exists(p) and file.ends_with(".ogg"):
		s = AudioStreamOggVorbis.load_from_file(p)
	elif FileAccess.file_exists(p) and file.ends_with(".wav"):      # the generator's --wav output
		s = AudioStreamWAV.load_from_file(p)
	if s is AudioStreamOggVorbis:
		s.loop = loop
		s.loop_offset = 0.0
	elif s is AudioStreamWAV and loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	_streams[file] = s
	return s


func unbind_all() -> void:
	for b in _bound:
		if b[4] != null:
			for pl in b[4]:
				pl[0].queue_free()
	_bound.clear()
	_edges.clear()


## A sound binding (§7.7) on its equipment's node. A one-shot bound like a loop (`breaker`) is played on its edges
## instead (`watch_breaker`), not as a sound that lasts while its gain is up.
func bind(b: Dictionary, n: Node3D) -> void:
	if not index.is_empty() and not index.get(b["sound"], {}).get("loop", true):
		return
	_bound.append([n, b["sound"], b.get("gain", 1.0), b.get("pitch", 1.0), null])


## A breaker's contacts (a value 0–1): `breaker` when it closes, `breaker_open` when it opens.
func watch_breaker(n: Node3D, slot: int) -> void:
	_edges.append([n, slot, -1])


## After every model step: a breaker's contacts that changed in it (at fast-forward many steps pass in a frame).
func on_step() -> void:
	for ed in _edges:
		var on := 1 if engine.cur[ed[1]] >= 0.5 else 0
		if ed[2] != -1 and on != ed[2] and (ed[0] as Node3D).global_position.distance_to(listener_at) < EARSHOT:
			once("breaker" if on == 1 else "breaker_open", ed[0])
		ed[2] = on


## A restarted plant: the breakers' last states are forgotten (no edge from the old run's state).
func reset_edges() -> void:
	for ed in _edges:
		ed[2] = -1


## The loop bound to a piece of equipment ("" when none): a large motor's start plays `motor_start` first.
func sound_of(n: Node3D) -> String:
	for b in _bound:
		if b[0] == n:
			return b[1]
	return ""


static func table(x: float, t: Array) -> float:
	if t.is_empty():
		return x
	if x <= float(t[0][0]):
		return float(t[0][1])
	for i in range(1, t.size()):
		var a: Array = t[i - 1]
		var b: Array = t[i]
		if x <= float(b[0]):
			var w := (x - float(a[0])) / maxf(1e-12, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), w)
	return float(t[t.size() - 1][1])


func _level(spec) -> float:
	if typeof(spec) == TYPE_DICTIONARY:
		return table(engine.v(spec["of"]), spec["table"])
	return float(spec)


## The gain and pitch a bound sound has now (tests read it; the players use it).
func level_of(i: int) -> Vector2:
	var b: Array = _bound[i]
	return Vector2(_level(b[2]), _level(b[3]))


func _process(delta: float) -> void:
	if engine == null or index.is_empty():
		return
	_t += delta
	if _t < UPDATE:
		return
	_t = 0.0
	var sum := 0.0
	for i in _bound.size():
		var b: Array = _bound[i]
		var n: Node3D = b[0]
		var lv := level_of(i)
		sum += clampf(lv.x, 0.0, 1.0)
		var held: bool = _hold.get(n, -1) > engine.step_no
		var near := n.global_position.distance_to(listener_at) < EARSHOT and lv.x > 0.001 and not muted and not held
		if near and b[4] == null:
			b[4] = _start(n, b[1])
		elif not near and b[4] != null:
			for p in b[4]:
				p[0].queue_free()
			b[4] = null
		if b[4] != null:
			for p in b[4]:
				var pl: AudioStreamPlayer3D = p[0]
				pl.volume_db = linear_to_db(maxf(lv.x, 1e-5))
				var layer: Dictionary = p[1]
				if layer.has("ref_hz") and layer.has("of"):          # a tone that follows a value
					pl.pitch_scale = clampf(table(engine.v(layer["of"]), layer["table"]) / float(layer["ref_hz"]), 0.05, 4.0)
				elif layer.get("pitch", true):
					pl.pitch_scale = clampf(lv.y, 0.05, 4.0)
	running = sum / maxf(1.0, _bound.size())
	_ambience_tick()


func _start(n: Node3D, id: String) -> Array:
	var out := []
	var s: Dictionary = index.get(id, {})
	for layer in s.get("layers", []):
		var st := _stream(layer["file"], s.get("loop", true))
		if st == null:
			continue
		var p := AudioStreamPlayer3D.new()
		p.set_meta("ui", true)
		p.stream = st
		p.max_distance = EARSHOT
		p.unit_size = 6.0
		n.add_child(p)
		p.play()
		out.append([p, layer])
	return out


## The control room horn: priority 1–3 while an alarm of that priority is unacknowledged, 0 for silence.
func horn(priority: int) -> void:
	if muted:
		priority = 0                    # (recorded as silence, so that unmuting sounds it again)
	if priority == _horn_prio:
		return
	_horn_prio = priority
	if _horn != null:
		_horn.queue_free()
		_horn = null
	if priority == 0 or index.is_empty() or muted:
		return
	var s: Dictionary = index.get("horn_p%d" % priority, {})
	if s.is_empty():
		return
	_horn = AudioStreamPlayer.new()
	_horn.stream = _stream(s["layers"][0]["file"], true)
	add_child(_horn)
	_horn.play()


## A one-shot for an engine event at a place: `breaker`, `breaker_open`, `motor_start`, `horn_ack`.
func once(id: String, at: Node3D = null) -> void:
	if index.is_empty() or muted or not index.has(id):
		return
	for layer in index[id].get("layers", []):
		var st := _stream(layer["file"], false)
		if st == null:
			continue
		if id == "motor_start" and at != null:          # the motor's loop takes over when the run-up has played
			_hold[at] = engine.step_no + int(st.get_length() * 10.0)      # in plant time, as the motor's speed
		var p
		if at != null:
			var p3 := AudioStreamPlayer3D.new()
			p3.stream = st
			p3.unit_size = 6.0
			at.add_child(p3)
			p3.play()
			p = p3
		else:
			var p2 := AudioStreamPlayer.new()
			p2.stream = st
			add_child(p2)
			p2.play()
			p = p2
		p.finished.connect(p.queue_free)


# ------------------------------------------------------------------ people cues and ambience

## The floor a body is: what the content build marked (a stair's body, a slab's deck); anything else (the ground,
## a slab, equipment) sounds as concrete.
static func surface_of(body) -> String:
	if body == null or not (body is Object) or not is_instance_valid(body):
		return "concrete"
	if body.has_meta("stair"):
		return "stair"
	match String(body.get_meta("deck", "")):
		"grating": return "grating"
		"steel": return "stair"           # chequer plate rings like a stair's steel tread
	return "concrete"


## The floor under the walker now: what it stood on in its last move, else the first floor below its feet.
func surface_under(w: CharacterBody3D) -> String:
	var best = null
	var top := -INF
	for i in w.get_slide_collision_count():         # the highest floor touched (at a stair's foot: the stair)
		var c := w.get_slide_collision(i)
		if c.get_normal().y > 0.6 and c.get_position().y > top:
			top = c.get_position().y
			best = c.get_collider()
	if best != null:
		return surface_of(best)
	var hit: Dictionary = w.floor_below(w.global_position + Vector3.UP * 0.3, 1.0) if w.has_method("floor_below") else {}
	return surface_of(hit.get("collider"))


func _physics_process(_delta: float) -> void:
	if walker == null or not is_instance_valid(walker):
		return
	var p := walker.global_position
	if _last_at == null:
		_last_at = p
		return
	var d: Vector3 = p - _last_at
	_last_at = p
	var mode: int = walker.get("mode")
	if d.length() > 3.0 or mode == 1:          # a jump (the map, a flight, the control room key) or flying: no steps
		_walked = 0.0
		return
	if mode == 2:                              # climbing a ladder: a rung at every RUNG
		_walked += absf(d.y)
		if _walked >= RUNG:
			_walked = 0.0
			footstep("stair")
		return
	if not walker.is_on_floor():
		return
	_walked += Vector2(d.x, d.z).length()
	if _walked >= (RUN_STRIDE if Vector2(walker.velocity.x, walker.velocity.z).length() > 2.5 else STRIDE):
		_walked = 0.0
		footstep(surface_under(walker))


## One footstep on a surface (concrete, grating, stair), a little different each time (pitch and level), as no two
## steps are alike. Two voices per surface, so a step never cuts the one before short.
func footstep(surface: String) -> void:
	var id: String = STEP_SOUNDS.get(surface, "step_concrete")
	played[id] = played.get(id, 0) + 1
	if index.is_empty() or muted or not index.has(id):
		return
	var pl: AudioStreamPlayer = _steps.get(id)
	if pl == null:
		var layers: Array = index[id].get("layers", [])
		var st: AudioStream = null
		if not layers.is_empty():
			st = _stream(layers[0]["file"], false)
		if st == null:
			return
		pl = AudioStreamPlayer.new()
		pl.stream = st
		pl.max_polyphony = 2
		add_child(pl)
		_steps[id] = pl
	pl.pitch_scale = _rng.randf_range(0.92, 1.08)
	pl.volume_db = _rng.randf_range(-1.5, 1.5)
	pl.play()


## A door starting or stopping (app/door.gd calls the group plant_sounds): a roller door's loop while it moves, a
## sliding door's run once as it starts.
func door_moving(door: Node3D, moving: bool) -> void:
	if not moving:
		if _doors.has(door):
			for p in _doors[door]:
				(p[0] as Node).queue_free()
			_doors.erase(door)
		return
	if door.global_position.distance_to(listener_at) >= EARSHOT:
		return
	if String(door.get("kind")) == "roller":
		played["door_roller"] = played.get("door_roller", 0) + 1
		if not muted and index.has("door_roller") and not _doors.has(door):
			_doors[door] = _start(door, "door_roller")
	else:
		played["door_slide"] = played.get("door_slide", 0) + 1
		once("door_slide", door)


## How loud the plant heard from afar is, from how much of it runs (the bound loops' mean gain): silent when
## nothing runs, full once about a quarter of it does.
static func distant_gain(run: float) -> float:
	return clampf(sqrt(maxf(run, 0.0) * 4.0), 0.0, 1.0)


## Is the listener outdoors? Inside when a building's roof is above it (the content build marks a building's body):
## a ray up, past at most three other things (a crane, a platform, a pipe).
func is_outdoors(at: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var from := at
	var skip: Array[RID] = []
	if walker != null and is_instance_valid(walker):
		skip.append(walker.get_rid())
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, at + Vector3.UP * 80.0)
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var c = hit.get("collider")
		if c is Object and is_instance_valid(c) and (c as Object).has_meta("building"):
			return false
		skip.append(hit["rid"])
		from = hit["position"]
	return true


func _ambience_tick() -> void:
	var want := 1.0 if is_outdoors(listener_at) else 0.0
	outdoors = move_toward(outdoors, want, UPDATE / FADE)
	for id in ["wind", "plant_distant"]:
		var g := outdoors * (1.0 if id == "wind" else distant_gain(running))
		var on := g > 0.001 and not muted and index.has(id)
		var ps: Array = _ambience.get(id, [])
		if on and ps.is_empty():
			for layer in index[id].get("layers", []):
				var st := _stream(layer["file"], true)
				if st == null:
					continue
				var pl := AudioStreamPlayer.new()
				pl.stream = st
				add_child(pl)
				pl.play()
				ps.append(pl)
			_ambience[id] = ps
		elif not on and not ps.is_empty():
			for pl in ps:
				(pl as Node).queue_free()
			_ambience[id] = []
			ps = []
		for pl in ps:
			(pl as AudioStreamPlayer).volume_db = linear_to_db(maxf(g, 1e-5))
