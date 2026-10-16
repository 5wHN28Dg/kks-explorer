extends RefCounted
## Links into Walkdown Plant (docs/PLANT3D.md §6), as ref/plant3d.py read_link and decode.
##
##   Links.read_link("walkdown-plant://kks/30PAC10AP001", model) returns one of
##     {"open": "kks", "code", "match", "decode"}   match: exact, without_a3, same_kind, same_equipment or decode
##     {"open": "procedure", "id", "step"}           step null for the first step
##     {"open": "start"}                             anything else: the app's start, with a short message

const PREFIX := "walkdown-plant://"
const L := "[A-HJ-NP-Z]"

static var _kks: RegEx
static var _link_code: RegEx


static func _res() -> void:
	if _kks == null:
		_kks = RegEx.create_from_string(
				"^([0-9])([0-9])(%s{3})([0-9]{2})(?:(%s{2})([0-9]{3})(%s)?)?\\z" % [L, L, L])
		_link_code = RegEx.create_from_string("^[0-9A-Z]{4,24}\\z")


## The KKS groups of a code of format 1 (§6): unit, F0, system letters, FN, equipment letters, AN, A3 ("" where a
## level is absent), or an empty array when it is not one.
static func kks_parts(code) -> PackedStringArray:
	_res()
	if typeof(code) != TYPE_STRING:
		return PackedStringArray()
	var mt := _kks.search(code)
	if mt == null:
		return PackedStringArray()
	var g := PackedStringArray()
	for k in range(1, 8):
		g.append(mt.get_string(k))
	return g


## A code's decoding from the plant's tables: each level's name, or null when its letters are not in the plant's key.
static func decode(code: String, kks: Dictionary) -> Dictionary:
	var g := kks_parts(code)
	var eq = null
	if g[4] != "":
		eq = kks["equipment"].get(g[4], kks["measurements"].get(g[4]))
	return {"unit": kks["units"].get(g[0]), "system": kks["systems"].get(g[2]), "equipment": eq}


static func read_link(url, model) -> Dictionary:
	_res()
	var start := {"open": "start"}
	if typeof(url) != TYPE_STRING or not url.begins_with(PREFIX):
		return start
	var path: PackedStringArray = url.substr(PREFIX.length()).split("/")
	if path.size() == 2 and path[0] == "kks" and _link_code.search(path[1]) != null:
		var raw := path[1]
		var asked := ""
		for k in range(raw.length(), 0, -1):
			if not kks_parts(raw.substr(0, k)).is_empty():
				asked = raw.substr(0, k)
				break
		if asked == "":
			return start
		var codes: Dictionary = model.codes
		var out := {"open": "kks", "code": asked, "match": "exact", "decode": decode(asked, model.plant["kks"])}
		if codes.has(asked):
			return out
		var g := kks_parts(asked)
		if g[6] != "" and codes.has(asked.substr(0, asked.length() - 1)):
			out["code"] = asked.substr(0, asked.length() - 1)
			out["match"] = "without_a3"
			return out
		# a code the plant doesn't have: the lowest code (in code order) of the same kind
		var same := []
		for c in codes:
			var h := kks_parts(c)
			if h[2] == g[2] and h[4] == g[4]:
				same.append(c)
		if not same.is_empty():
			same.sort()
			out["code"] = same[0]
			out["match"] = "same_kind"
			return out
		if g[4] != "":
			for c in codes:
				if kks_parts(c)[4] == g[4]:
					same.append(c)
			if not same.is_empty():
				same.sort()
				out["code"] = same[0]
				out["match"] = "same_equipment"
				return out
		out["match"] = "decode"
		return out
	if (path.size() == 2 or path.size() == 3) and path[0] == "procedure" and model.procedures.has(path[1]):
		if path.size() == 2:
			return {"open": "procedure", "id": path[1], "step": null}
		for s in model.procedures[path[1]]["steps"]:
			if s["id"] == path[2]:
				return {"open": "procedure", "id": path[1], "step": path[2]}
	return start
