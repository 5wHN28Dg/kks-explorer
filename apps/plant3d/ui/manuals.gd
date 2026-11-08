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


## A figure's picture (decoded on first use), null when missing.
func figure(file: String) -> Texture2D:
	if _figures.has(file):
		return _figures[file]
	var tex: Texture2D = null
	var p := dir.path_join(file)
	if FileAccess.file_exists(p):
		var img := Image.new()
		if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
			tex = ImageTexture.create_from_image(img)
	_figures[file] = tex
	return tex


## The section a work view action opens ([manual, section]; [] none).
func for_work(kind: String, action: String) -> Array:
	return work.get(kind + ":" + action, [])


## The section a Workshop step opens ([manual, section]; [] none).
func for_step(kind: String, place: String) -> Array:
	return workshop.get(kind + ":" + place, [])
