## The interiors (docs/PLANT3D.md §18.5, decision 0066): a camp block's rooms, the mess hall and its kitchen, the
## prayer room, the gym, the laundry, the recreation room, the offices. Each is a scene of its own (the build's
## manifest `interiors`), loaded on a worker thread when the trainee comes within NEAR metres of one of its building's
## doors, shown once loaded, and freed beyond FAR. Its pieces are the plant's materials and vertex format, unbaked
## (builder/kit_place.gd `unbaked`), so showing one compiles no pipeline. Checked 4 times a second.
extends Node

const Plant = preload("res://app/plant.gd")
const Quality = preload("res://app/quality.gd")

const NEAR := 15.0
const FAR := 30.0
const CHECK := 0.25

signal shown(id: String)
signal freed(id: String)

var plant: Node3D                 # app/plant.gd: the interiors go under it, beside the areas
var who: Node3D                   # the walker
var items := {}                   # id -> {scene, doors: [Vector3], rect: Rect2 (plant plan), node, loading}
var _t := 0.0

func setup(p: Node3D, walker: Node3D) -> void:
	plant = p
	who = walker
	for a in p.manifest.get("interiors", []):
		var b: Array = a.bounds
		items[a.id] = {"scene": a.scene, "doors": a.get("doors", []).map(func(d): return Plant.v3(d)),
			"rect": Rect2(Vector2(b[0][0], b[0][1]), Vector2(b[1][0] - b[0][0], b[1][1] - b[0][1])),
			"node": null, "loading": false, "title": a.get("title", a.id)}

## Metres from a point (Godot's axes) to an interior: its nearest door, or its plan rectangle when nearer.
func distance(id: String, at: Vector3) -> float:
	var it: Dictionary = items[id]
	var d := INF
	for dp in it.doors:
		d = minf(d, (dp as Vector3).distance_to(at))
	var p := Vector2(at.x, -at.z)
	var r: Rect2 = it.rect
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return minf(d, q.distance_to(p))

## The interior the point stands in (its title), or "".
func title_at(at: Vector3) -> String:
	for id in items:
		if items[id].node != null and (items[id].rect as Rect2).has_point(Vector2(at.x, -at.z)):
			return items[id].title
	return ""

func loaded(id: String) -> bool:
	return items.has(id) and items[id].node != null

func _process(delta: float) -> void:
	_t += delta
	if _t < CHECK or who == null:
		return
	_t = 0.0
	update(who.global_position)

## One check: requests, shows and frees by the distance from `at`.
func update(at: Vector3) -> void:
	for id in items:
		var it: Dictionary = items[id]
		var d := distance(id, at)
		if it.loading:
			var st := ResourceLoader.load_threaded_get_status(it.scene)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				it.loading = false
				var ps := ResourceLoader.load_threaded_get(it.scene) as PackedScene
				if ps != null and d < FAR:
					_show(id, ps)
			elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				it.loading = false   # failed: tried again next time the trainee comes near
				push_warning("interior %s: could not load %s" % [id, it.scene])
		elif it.node == null and d < NEAR:
			if ResourceLoader.load_threaded_request(it.scene, "PackedScene", true) == OK:
				it.loading = true
		elif it.node != null and d > FAR:
			it.node.queue_free()
			it.node = null
			freed.emit(id)

func _show(id: String, ps: PackedScene) -> void:
	var n := ps.instantiate()
	plant.add_child(n)
	Plant.fill_cells(n)
	if is_inside_tree():
		Quality.apply_ranges(get_viewport(), n)   # the tier's visibility ranges on its pieces
	items[id].node = n
	shown.emit(id)

## Loads every interior at once, on this thread (the tests and the navigation mesh's bake walk into all of them).
func load_all() -> void:
	for id in items:
		if items[id].node == null:
			_show(id, load(items[id].scene) as PackedScene)
