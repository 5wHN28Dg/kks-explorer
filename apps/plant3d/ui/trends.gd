## The control room screens' trends (docs/PLANT3D.md §7.11): the values the screens trend, sampled every
## `EVERY` model steps into a ring of `SIZE` samples (20 minutes of plant time), whatever the screens show, so a
## sparkline has its history when the trainee opens a screen. Fed by the clock's steps (ui/plant_ui.gd).
extends RefCounted

const EVERY := 50                  # model steps between samples: 5 s of plant time
const SIZE := 240                  # samples kept: 20 min of plant time

var names: Array = []
var _slot := {}                    # value name -> [index in names]
var _data := PackedFloat32Array()  # the rings, one after the other: value i's sample k at i * SIZE + k
var _n := 0                        # samples taken (the ring's write position is _n % SIZE)
var last_step := -1


func _init(value_names: Array) -> void:
	names = value_names.duplicate()
	for i in names.size():
		_slot[names[i]] = i
	_data.resize(names.size() * SIZE)


func clear() -> void:
	_n = 0
	last_step = -1


## Called after every model step: samples at every EVERY-th step of the run (and at the first one seen).
func on_step(e) -> void:
	if e.step_no % EVERY != 0 and last_step >= 0:
		return
	last_step = e.step_no
	var w := _n % SIZE
	for i in names.size():
		_data[i * SIZE + w] = e.v(names[i])
	_n += 1


func has(name: String) -> bool:
	return _slot.has(name)


## The samples of a value, oldest first (at most SIZE).
func series(name: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not _slot.has(name):
		return out
	var base: int = _slot[name] * SIZE
	var count := mini(_n, SIZE)
	out.resize(count)
	var start := _n - count
	for k in count:
		out[k] = _data[base + (start + k) % SIZE]
	return out
