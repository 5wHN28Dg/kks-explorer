## The equipment manuals (docs/plant3d/REALISM.md §6.2.1): the index (the manuals in order, each part kind's manual,
## each code's own data, the reverse links from the work view's actions and the Workshop's steps) and the manuals
## themselves, read when first wanted; a figure decoded when first shown. Made at build time by
## tools/plant3d/manuals.py and builder/manual_figures.gd into built/manuals; nothing is generated on the device.
extends RefCounted

const JsonStrict = preload("res://sim/json_strict.gd")
const DIR := "res://built/manuals"

var dir := DIR
var error := ""
var list: Array = []            # [{id, number, title, short, kinds, file}] in order
var kinds := {}                 # part kind -> manual id
var units := {}                 # code -> {manual, kind, rows}
var work := {}                  # "<part>:<action>" -> [manual, section]
var workshop := {}              # "<kind>:<component>" -> [manual, section]
var _loaded := {}               # manual id -> its data
var _figures := {}              # file -> ImageTexture
var _tasks := {}                # file -> [worker task id, {img}, waited]: being decoded
var _orphans: Array = []        # the task ids of decodes forgotten while running, waited for once done


func _init(from := DIR) -> void:
	dir = from
	var d = _read(dir + "/index.json")
	if not (d is Dictionary) or d.get("format", "") != "walkdown-plant-manuals" or int(d.get("version", 0)) != 1:
		error = "no manuals in %s" % dir if d == null else "not a set of manuals this app reads"
		return
	list = d["manuals"]
	kinds = d["kinds"]
	units = d["units"]
	work = d["work"]
	workshop = d["workshop"]


static func _read(path: String):
	if not FileAccess.file_exists(path):
		return null
	var r := JsonStrict.parse(FileAccess.get_file_as_bytes(path))
	return r["value"] if r.get("ok", false) else null


## The manual of a part kind ("" none).
func of_kind(kind: String) -> String:
	return String(kinds.get(kind, ""))


func has(id: String) -> bool:
	for m in list:
		if m["id"] == id:
			return true
	return false


## A manual's data (read on first use); {} when it can't be read.
func manual(id: String) -> Dictionary:
	if _loaded.has(id):
		return _loaded[id]
	var out := {}
	for m in list:
		if m["id"] == id:
			var d = _read(dir.path_join(String(m["file"])))
			if d is Dictionary and d.get("format", "") == "walkdown-plant-manual" and int(d.get("version", 0)) == 1:
				out = d
	_loaded[id] = out
	return out


## A figure's picture (decoded now if it isn't yet), null when missing.
func figure(file: String) -> Texture2D:
	request_figure(file)
	if _tasks.has(file):
		_finish(file)
	return poll_figure(file)


## Waits for a figure's task (once: the pool forgets a task's id when it has been waited for).
func _finish(file: String) -> void:
	var t: Array = _tasks[file]
	if not t[2]:
		WorkerThreadPool.wait_for_task_completion(t[0])
		t[2] = true


func has_figure(file: String) -> bool:
	return FileAccess.file_exists(dir.path_join(file))


## Starts decoding a figure on a worker thread (once).
func request_figure(file: String) -> void:
	if _figures.has(file) or _tasks.has(file):
		return
	var holder := {"img": null}
	var p := dir.path_join(file)
	var id := WorkerThreadPool.add_task(func():
		if FileAccess.file_exists(p):
			var img := Image.new()
			if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
				holder["img"] = img)
	_tasks[file] = [id, holder, false]     # (whether waited for: kept out of the dictionary the worker writes)


func figure_pending(file: String) -> bool:
	return _tasks.has(file)


## The figure's picture when decoded (the texture made here, on the main thread), else null.
func poll_figure(file: String) -> Texture2D:
	if _figures.has(file):
		return _figures[file]
	if not _tasks.has(file):
		return null
	if not _tasks[file][2]:
		if not WorkerThreadPool.is_task_completed(_tasks[file][0]):
			return null
		_finish(file)
	var img: Image = _tasks[file][1]["img"]
	_tasks.erase(file)
	var tex: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_figures[file] = tex
	return tex


## Drops the decoded figures (the reader closed). Decodes still running are waited for later, once done (`reap`):
## waiting here would hold the frame that closes the reader.
func forget_figures() -> void:
	for f in _tasks:
		if not _tasks[f][2]:
			_orphans.append(_tasks[f][0])
	_tasks.clear()
	_figures.clear()


## Waits for the forgotten decodes that have finished (each frame), or for all of them (`all`: the app leaving).
func reap(all := false) -> void:
	for i in range(_orphans.size() - 1, -1, -1):
		if all or WorkerThreadPool.is_task_completed(_orphans[i]):
			WorkerThreadPool.wait_for_task_completion(_orphans[i])
			_orphans.remove_at(i)


## The section a work view action opens ([manual, section]; [] none).
func for_work(kind: String, action: String) -> Array:
	return work.get(kind + ":" + action, [])


## The section a Workshop step opens ([manual, section]; [] none).
func for_step(kind: String, place: String) -> Array:
	return workshop.get(kind + ":" + place, [])
