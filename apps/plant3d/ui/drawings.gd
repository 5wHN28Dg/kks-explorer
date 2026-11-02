## The generated P&IDs (docs/plant3d/REALISM.md §6.1.1): the index (the sheets in order, each code's home sheet, the
## lettering's strokes) and the sheets themselves, read when first wanted. Made at build time by tools/plant3d/pid.py
## into built/drawings; nothing is generated on the device.
extends RefCounted

const DIR := "res://built/drawings"

var dir := DIR
var error := ""
var sheets: Array = []          # [{id, number, title, file}] in order
var home := {}                  # code -> its home sheet's id
var glyphs := {}                # character -> [PackedVector2Array per stroke] on the lettering's 4 × 6 grid
var advance := 5.0
var cap := 6.0
var _loaded := {}               # sheet id -> its data (Dictionary)


func _init(from := DIR) -> void:
	dir = from
	var d = _read(dir + "/index.json")
	if not (d is Dictionary) or d.get("format", "") != "walkdown-plant-drawings" or int(d.get("version", 0)) != 1:
		error = "no drawings in %s" % dir if d == null else "not a set of drawings this app reads"
		return
	sheets = d["sheets"]
	home = d["home"]
	var L: Dictionary = d["lettering"]
	advance = float(L["advance"])
	cap = float(L["cap"])
	for ch in L["glyphs"]:
		var strokes: Array = []
		for s in L["glyphs"][ch]:
			var p := PackedVector2Array()
			for i in range(0, s.size(), 2):
				p.append(Vector2(s[i], s[i + 1]))
			strokes.append(p)
		glyphs[ch] = strokes


static func _read(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func index_of(id: String) -> int:
	for i in sheets.size():
		if sheets[i]["id"] == id:
			return i
	return -1


## A sheet's data (read once, then kept).
func sheet(id: String) -> Dictionary:
	if not _loaded.has(id):
		var i := index_of(id)
		var d = _read(dir + "/" + String(sheets[i]["file"])) if i >= 0 else null
		_loaded[id] = d if d is Dictionary and d.get("format", "") == "walkdown-plant-drawing" else {}
	return _loaded[id]


func home_of(code: String) -> String:
	return String(home.get(code, ""))
