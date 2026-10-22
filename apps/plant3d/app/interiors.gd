## The interiors (docs/PLANT3D.md §18.5, decision 0066): a camp block's rooms, the mess hall and its kitchen, the
## prayer room, the gym, the laundry, the recreation room, the offices. Each is a scene of its own (the build's
## manifest `interiors`), loaded on a worker thread when the trainee comes within NEAR metres of one of its building's
## doors, then put into the plant a few of its pieces a frame (BATCH), and taken out the same way beyond FAR: the Note 9
## held a frame 104-127 ms each time an interior went in whole (2026-10-22). It is instantiated on this thread (its
## bodies are made through the physics server, which is not thread-safe here: Jolt, no physics thread). Its pieces
## are the plant's materials and vertex format, unbaked (builder/kit_place.gd `unbaked`), so
## showing one compiles no pipeline. Distances checked 4 times a second.
extends Node

const Plant = preload("res://app/plant.gd")
const Quality = preload("res://app/quality.gd")

const NEAR := 15.0
const FAR := 30.0
const CHECK := 0.25
const BATCH := 12              # pieces (nodes with what they hold) put in or taken out per frame

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
			"node": null, "loading": false, "title": a.get("title", a.id),
			"pending": [], "shown": false}

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

## Whether an interior is shown whole.
func loaded(id: String) -> bool:
	return items.has(id) and items[id].shown

var _dying: Array = []   # interiors being taken out: [root, its pieces still in]

func _process(delta: float) -> void:
	_step()
	_t += delta
	if _t < CHECK or who == null:
		return
	_t = 0.0
	update(who.global_position)

## The per-frame work: interiors made go in, BATCH pieces a frame; freed ones go out the same way.
func _step() -> void:
	var budget := BATCH
	for id in items:
		var it: Dictionary = items[id]
		while budget > 0 and it.node != null and not it.pending.is_empty():
			var pair: Array = it.pending.pop_front()   # [its container (already in), the piece]
			var piece: Node = pair[1]
			(pair[0] as Node).add_child(piece)
			budget -= 1
			var mmi := piece as MultiMeshInstance3D
			if mmi != null and mmi.has_meta("xforms") and mmi.multimesh != null:   # as app/plant.gd fill_cells
				mmi.multimesh.instance_count = int(mmi.get_meta("count"))
				mmi.multimesh.buffer = mmi.get_meta("xforms")
			if is_inside_tree():
				Quality.apply_ranges(get_viewport(), piece)   # the tier's visibility ranges on its pieces
			if it.pending.is_empty():
				it.shown = true
				shown.emit(id)
	while budget > 0 and not _dying.is_empty():
		var root: Node = _dying[0][0]
		var c := _last_piece(root)
		if c == null:
			root.queue_free()
			_dying.pop_front()
			continue
		c.get_parent().remove_child(c)
		c.queue_free()
		budget -= 1

## A piece of an interior to take out: the last child of its last container that still holds one, or null.
static func _last_piece(root: Node) -> Node:
	for i in range(root.get_child_count() - 1, -1, -1):
		var c := root.get_child(i)
		if c.get_child_count() > 0:
			return c.get_child(c.get_child_count() - 1)
	return null

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
					_make(id, ps)
			elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				it.loading = false   # failed: tried again next time the trainee comes near
				push_warning("interior %s: could not load %s" % [id, it.scene])
		elif it.node == null and d < NEAR and not _dying_ids().has(id):   # (one copy at a time)
			if ResourceLoader.load_threaded_request(it.scene, "PackedScene", true) == OK:
				it.loading = true
		elif it.node != null and d > FAR:
			# out a few pieces a frame (_step), what was not yet put in at once (it holds no tree)
			for p in it.pending:
				(p[1] as Node).free()
			it.pending = []
			_dying.append([it.node, id])
			it.node = null
			it.shown = false
			freed.emit(id)

## Instantiates it (outside the tree) and puts its root and containers in: what the containers hold (structures,
## signs, the kit's cells) goes in by batches (_step).
func _make(id: String, ps: PackedScene) -> void:
	var n := ps.instantiate()
	if n == null:
		push_warning("interior %s: its scene made nothing" % id)
		return
	var pieces: Array = []
	for c in n.get_children():
		for p in c.get_children():
			pieces.append([c, p])
	for pair in pieces:
		(pair[0] as Node).remove_child(pair[1])
	var it: Dictionary = items[id]
	it.pending = pieces
	plant.add_child(n)
	it.node = n
	if pieces.is_empty():
		it.shown = true
		shown.emit(id)

func _dying_ids() -> Array:
	return _dying.map(func(d): return d[1])

## Pieces never put in hold no tree: freed with the loader (a world freed while an interior went in).
func _exit_tree() -> void:
	for id in items:
		for p in items[id].pending:
			if is_instance_valid(p[1]) and not (p[1] as Node).is_inside_tree():
				(p[1] as Node).free()
		items[id].pending = []

## Shows one at once, on this thread (load_all).
func _show(id: String, ps: PackedScene) -> void:
	var n := ps.instantiate()
	plant.add_child(n)
	Plant.fill_cells(n)
	if is_inside_tree():
		Quality.apply_ranges(get_viewport(), n)   # the tier's visibility ranges on its pieces
	items[id].node = n
	items[id].shown = true
	shown.emit(id)

## Loads every interior at once, on this thread (the tests and the navigation mesh's bake walk into all of them).
func load_all() -> void:
	for id in items:
		if items[id].node == null:
			_show(id, load(items[id].scene) as PackedScene)
