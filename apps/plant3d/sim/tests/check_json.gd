extends SceneTree
## The strict JSON reader (json_strict.gd) against the protocol's strict JSON vectors (ref/vectors/v2-json.json, the
## same rules as ref/sjson.py): every accepted input gives the typed value, every rejected one is refused.
##   godot --headless --script apps/plant3d/sim/tests/check_json.gd -- ref/vectors/v2-json.json
## Prints "JSON checked=N bad=M" and each failure; exit code 0 when none failed.
const JsonStrict = preload("../json_strict.gd")


func typed(v) -> Dictionary:
	match typeof(v):
		TYPE_NIL:
			return {"t": "null"}
		TYPE_BOOL:
			return {"t": "bool", "v": v}
		TYPE_INT:
			return {"t": "int", "v": str(v)}
		TYPE_FLOAT:
			return {"t": "float", "v": v}
		TYPE_STRING:
			return {"t": "str", "v": v}
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(typed(x))
			return {"t": "arr", "v": a}
	var o := []
	for k in v:
		o.append([k, typed(v[k])])
	return {"t": "obj", "v": o}


## The vectors write a float as its shortest decimal: read it back (any correct reader gives the same double).
func want_of(w: Dictionary) -> Dictionary:
	if w["t"] == "float":
		var r := JsonStrict.parse_text(w["v"])
		return {"t": "float", "v": float(r.value)}
	if w["t"] == "big":
		return {"t": "float", "v": null}         # a big integer is read as a float (json_strict.gd)
	if w["t"] == "arr":
		var a := []
		for x in w["v"]:
			a.append(want_of(x))
		return {"t": "arr", "v": a}
	if w["t"] == "obj":
		var o := []
		for kv in w["v"]:
			o.append([kv[0], want_of(kv[1])])
		return {"t": "obj", "v": o}
	return w


func same(g, w) -> bool:
	if typeof(g) == TYPE_DICTIONARY and g.get("t") == "float" and w.get("t") == "float":
		if w["v"] == null:
			return true
		var a := PackedFloat64Array([g["v"]]).to_byte_array()
		var b := PackedFloat64Array([w["v"]]).to_byte_array()
		return a == b
	if typeof(g) != typeof(w):
		return false
	if typeof(g) == TYPE_DICTIONARY:
		if g.keys() != w.keys():
			return false
		for k in g:
			if not same(g[k], w[k]):
				return false
		return true
	if typeof(g) == TYPE_ARRAY:
		if g.size() != w.size():
			return false
		for i in g.size():
			if not same(g[i], w[i]):
				return false
		return true
	return g == w


func _init() -> void:
	quit(1)         # stays the exit code if a script error stops this function
	var n := 0
	var bad := 0
	for path in OS.get_cmdline_user_args():     # the vector files: v2-json.json, and the test's own extra cases
		var V: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value
		var nb := _check(V)
		n += nb[0]
		bad += nb[1]
	print("JSON checked=%d bad=%d" % [n, bad])
	quit(1 if bad or n == 0 else 0)


func _check(V: Dictionary) -> Array:
	var n := 0
	var bad := 0
	for x in V["accept"]:
		n += 1
		var r := JsonStrict.parse(x["hex"].hex_decode())
		if not r.ok:
			bad += 1
			print("BAD accept %s: refused (%s)" % [x["why"], r.error])
		elif not same(typed(r.value), want_of(x["value"])):
			bad += 1
			print("BAD accept %s: %s" % [x["why"], str(typed(r.value))])
	for x in V["reject"]:
		n += 1
		var r := JsonStrict.parse(x["hex"].hex_decode())
		if r.ok:
			bad += 1
			print("BAD reject %s: accepted" % x["why"])
	return [n, bad]
