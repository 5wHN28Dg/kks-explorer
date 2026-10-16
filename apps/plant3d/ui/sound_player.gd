## Plays the plant's sounds (docs/PLANT3D.md §11) from the files tools/plant3d/sounds makes into built/sounds. Its
## index `index.json` (format `walkdown-plant-sound-files`, tools/plant3d/sounds/README.md) names each sound's layers,
## all played together with the binding's gain, and with its pitch on the layers marked `pitch` (a motor's mains hum
## never is). Bound sounds play at their equipment while the trainee is within earshot; the control room horn sounds
## per priority while an alarm is unacknowledged. One-shots play on edges the app sees, since format 1 binds none: a
## breaker's contacts closing and opening, a large motor's start (its loop waits until the run-up has played), an
## acknowledge. Without built/sounds (the sounds not made) everything here is silent; the hooks are called all the same.
extends Node3D

const DIR := "res://built/sounds"
const EARSHOT := 50.0           # metres: farther loops are stopped (nothing decodes for nobody)
const UPDATE := 0.1             # seconds between gain and pitch updates

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


func _ready() -> void:
	set_meta("ui", true)
	load_index(dir)


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
	for i in _bound.size():
		var b: Array = _bound[i]
		var n: Node3D = b[0]
		var lv := level_of(i)
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
