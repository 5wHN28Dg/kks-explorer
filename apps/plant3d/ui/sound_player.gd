## Plays the plant's sounds (docs/PLANT3D.md §11) from the files tools/plant3d/sounds makes into built/sounds:
## its index `sounds.json` (format `walkdown-plant-sound-files`) names each sound's layers, all played together with
## the binding's gain and pitch. Bound sounds play at their equipment while the trainee is within earshot; the
## control room horn sounds per priority while an alarm is unacknowledged; one-shots follow events (breakers, a large
## motor's start, an acknowledge). Without built/sounds (the sounds not made yet) everything here is silent: the
## hooks (`bind`, `horn`, `event`) are called all the same.
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
var _t := 0.0
var listener_at := Vector3.ZERO


func _ready() -> void:
	set_meta("ui", true)
	var f := FileAccess.open(DIR + "/sounds.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())     # the generator's own output: no strictness needed
	if d is Dictionary and d.get("format", "") == "walkdown-plant-sound-files":
		index = d.get("sounds", {})


func available() -> bool:
	return not index.is_empty()


func _stream(file: String, loop: bool) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var p := DIR + "/" + file
	var s: AudioStream = null
	if ResourceLoader.exists(p):
		s = load(p)
	elif FileAccess.file_exists(p):
		s = AudioStreamOggVorbis.load_from_file(p)
	if s is AudioStreamOggVorbis:
		s.loop = loop
		s.loop_offset = 0.0
	_streams[file] = s
	return s


## A sound binding (§7.7) on its equipment's node.
func bind(b: Dictionary, n: Node3D) -> void:
	_bound.append([n, b["sound"], b.get("gain", 1.0), b.get("pitch", 1.0), null])


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
		var near := n.global_position.distance_to(listener_at) < EARSHOT and lv.x > 0.001 and not muted
		if near and b[4] == null:
			b[4] = _start(n, b[1])
		elif not near and b[4] != null:
			for p in b[4]:
				p.queue_free()
			b[4] = null
		if b[4] != null:
			for p in b[4]:
				p.volume_db = linear_to_db(maxf(lv.x, 1e-5))
				p.pitch_scale = clampf(lv.y, 0.05, 4.0)


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
		out.append(p)
	return out


## The control room horn: priority 1–3 while an alarm of that priority is unacknowledged, 0 for silence.
func horn(priority: int) -> void:
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
