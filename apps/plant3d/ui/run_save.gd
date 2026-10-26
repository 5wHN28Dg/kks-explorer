## A run's save file (apps/plant3d/README.md "Saved runs"): the whole run, so that it continues after Android has
## killed the app or the app was closed (a cold start takes 10 minutes and more). The file is
##   "WDPSAVE\n"  u32 format (FORMAT)  u64 payload length  32 bytes SHA-256 of the payload  payload
## (little-endian), the payload being Godot's binary Variant encoding (var_to_bytes, no objects) of one Dictionary.
## Doubles are kept bit for bit: a run continued from its save goes on exactly as it would have without the break.
##
## The engine's state is saved generically: every script variable of sim/engine.gd except those built from the
## model and the scenario (ENGINE_BUILT, and every name beginning with "_": the compiled program). State added to the
## engine later is saved with no change here (tests/test_run_save.gd checks that the compiled fields never change in
## a run, and that a field added by a subclass goes round). The procedure tracker likewise (all but TRACKER_BUILT).
##
## Loading is strict: a file over MAX_BYTES, a wrong magic, length or hash, a payload that is not the expected
## Dictionary, a save of another format, app version or content, or engine state whose fields or types differ from
## this engine's, is refused with a reason; nothing of it is applied (read() and check() return a reason, never half a run).
extends RefCounted

const MAGIC := "WDPSAVE\n"
const FORMAT := 1
const HEAD := 8 + 4 + 8 + 32
const MAX_BYTES := 64 * 1024 * 1024
const ENGINE_BUILT := ["m", "sc", "names", "ix", "n", "timing", "step_us", "staff_us"]
const TRACKER_BUILT := ["proc", "steps"]
const PAYLOAD_KEYS := {"app": TYPE_STRING, "content": TYPE_STRING, "scenario": TYPE_STRING, "saved_unix": TYPE_INT,
		"engine": TYPE_DICTIONARY, "clock": TYPE_DICTIONARY, "procedure": TYPE_STRING, "tracker": TYPE_DICTIONARY,
		"ui": TYPE_DICTIONARY, "player": TYPE_DICTIONARY, "run": TYPE_DICTIONARY}


## The app's version: its configured version and the hash of the code that makes and reads a run's state, which
## build.sh writes to built/code.sha256 (sim/*.gd and the save's and the tracker's scripts: an export keeps the
## scripts only compiled, so the app can't hash them itself). A save of any other build is refused.
const CODE_HASH := "res://built/code.sha256"


static func app_version() -> String:
	var code := FileAccess.get_file_as_string(CODE_HASH).strip_edges() if FileAccess.file_exists(CODE_HASH) else ""
	return "%s+%s" % [str(ProjectSettings.get_setting("application/config/version", "")), code.left(16)]


## SHA-256 (hex) of every file under `dir`, by sorted relative path: the content a run was made with.
static func content_hash(dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	_hash_dir(ctx, dir, "")
	return ctx.finish().hex_encode()


static func _hash_dir(ctx: HashingContext, root: String, rel: String) -> void:
	var here := root.path_join(rel) if rel != "" else root
	var files := Array(DirAccess.get_files_at(here))
	files.sort()
	for f in files:
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		var b := FileAccess.get_file_as_bytes(here.path_join(f))
		ctx.update(("%s\n%d\n" % [rel.path_join(f) if rel != "" else f, b.size()]).to_utf8_buffer())
		ctx.update(b)
	var dirs := Array(DirAccess.get_directories_at(here))
	dirs.sort()
	for d in dirs:
		_hash_dir(ctx, root, rel.path_join(d) if rel != "" else d)


# ------------------------------------------------------------------ generic state of an object

## The script variables of obj that make its state: all but `built` (and, with skip_underscore, the "_" ones).
static func fields(obj: Object, built: Array, skip_underscore: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for p in obj.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var nm: String = p["name"]
		if nm in built or (skip_underscore and nm.begins_with("_")):
			continue
		out.append(nm)
	out.sort()
	return out


static func engine_fields(e: Object) -> PackedStringArray:
	return fields(e, ENGINE_BUILT, true)


static func tracker_fields(t: Object) -> PackedStringArray:
	return fields(t, TRACKER_BUILT, false)


## A deep copy of the fields' values (safe to encode on another thread while obj goes on: tests/test_run_save.gd).
## The event log is the exception: only the list is copied, not each event in it. An event is never changed once it
## is in the log, which only grows (sim/engine.gd _ev), and the log is the largest part of a long run's state: copying
## each event made the main thread's part of a save grow with the run (the app saves every 5 s).
static func capture(obj: Object, names: PackedStringArray) -> Dictionary:
	var d := {}
	for nm in names:
		var v = obj.get(nm)
		if nm == "events" and v is Array:
			v = v.duplicate(false)
		elif v is Array or v is Dictionary:
			v = v.duplicate(true)
		elif _is_packed(typeof(v)):
			v = v.duplicate()       # packed arrays are shared by reference: the engine writes `cur` in place
		d[nm] = v
	return d


static func _is_packed(t: int) -> bool:
	return t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY


## Checks data against the fresh object's fields (the same names; the same types where a field is typed; an array or packed array that the
## fresh object holds non-empty keeps its size: it is sized by the model); "" when it fits. Applies nothing.
static func check(fresh: Object, names: PackedStringArray, data: Dictionary) -> String:
	if data.size() != names.size():
		return "its fields are not this version's"
	var declared := {}
	for prop in fresh.get_property_list():
		declared[prop["name"]] = prop["type"]
	for nm in names:
		if not data.has(nm):
			return "no field %s" % nm
		var want = fresh.get(nm)
		var got = data[nm]
		if declared.get(nm, TYPE_NIL) == TYPE_NIL and typeof(got) != TYPE_OBJECT:
			continue            # an untyped field (`var x = 0`) may hold any value, but never an object
		if typeof(got) != typeof(want):
			return "field %s is a %s, not a %s" % [nm, type_string(typeof(got)), type_string(typeof(want))]
		if (want is Array or _is_packed(typeof(want))) and want.size() > 0 and got.size() != want.size():
			return "field %s has %d entries, not %d" % [nm, got.size(), want.size()]
		if want is Array and want.is_typed() and not got.is_same_typed(want):
			return "field %s is not typed as this version's" % nm
	return ""


static func apply(obj: Object, data: Dictionary) -> void:
	for nm in data:
		obj.set(nm, data[nm])


# ------------------------------------------------------------------ the file

static func encode(payload: Dictionary) -> PackedByteArray:
	var body := var_to_bytes(payload)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var out := MAGIC.to_ascii_buffer()
	var nums := PackedByteArray()
	nums.resize(12)
	nums.encode_u32(0, FORMAT)
	nums.encode_u64(4, body.size())
	out.append_array(nums)
	out.append_array(ctx.finish())
	out.append_array(body)
	return out


## {"ok": true, "payload": Dictionary} or {"ok": false, "why": code, "text": words}; why is one of corrupt,
## format (another format of this file), too_big.
static func decode(b: PackedByteArray) -> Dictionary:
	if b.size() > MAX_BYTES:
		return _no("too_big", "the file is larger than %d MiB" % (MAX_BYTES >> 20))
	if b.size() < HEAD or b.slice(0, 8) != MAGIC.to_ascii_buffer():
		return _no("corrupt", "it is not a saved run")
	var fmt := b.decode_u32(8)
	if fmt != FORMAT:
		return _no("format", "it was saved by another version of the app (save format %d)" % fmt)
	var n := b.decode_u64(12)
	if n != b.size() - HEAD:
		return _no("corrupt", "the file is cut short or has bytes after its end")
	var body := b.slice(HEAD)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	if ctx.finish() != b.slice(20, HEAD):
		return _no("corrupt", "the file is damaged (its checksum does not match)")
	var p = bytes_to_var(body)
	if typeof(p) != TYPE_DICTIONARY:
		return _no("corrupt", "the file's contents are not a saved run")
	for k in p:
		if not PAYLOAD_KEYS.has(k):
			return _no("corrupt", "the file has an unknown part %s" % str(k))
	for k in PAYLOAD_KEYS:
		if not p.has(k) or typeof(p[k]) != PAYLOAD_KEYS[k]:
			return _no("corrupt", "the file's part %s is missing or of the wrong kind" % k)
	return {"ok": true, "payload": p}


static func _no(why: String, text: String) -> Dictionary:
	return {"ok": false, "why": why, "text": text}


## Writes atomically: the bytes to a .tmp of this process's own (two app windows never write one file at once),
## then renamed over path: a reader sees the old file or the new one, never half of one. Where a rename cannot
## replace a file in one step (Windows: Godot removes the old file first), read() falls back to a complete .tmp.
static func write(path: String, bytes: PackedByteArray) -> Error:
	if bytes.size() > MAX_BYTES:
		return ERR_FILE_CANT_WRITE         # read() would refuse it
	var tmp := "%s.tmp.%d" % [path, OS.get_process_id()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return err
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))


## path and every .tmp beside it (path.tmp, path.tmp.<pid>).
static func _files(path: String) -> Array:
	var out := [path]
	var dir := path.get_base_dir()
	var stem := path.get_file() + ".tmp"
	var names := Array(DirAccess.get_files_at(dir)) if DirAccess.dir_exists_absolute(dir) else []
	names.sort()
	for nm in names:
		if nm.begins_with(stem):
			out.append(dir.path_join(nm))
	return out


## The newest complete save at path or a .tmp beside it (a rename that did not happen, Windows), by the time it was
## saved (path when equal): decode()'s result, or {"ok": false, "why": "missing"} when there is none.
static func read(path: String) -> Dictionary:
	var first := {}
	var best := {}
	for p in _files(path):
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var len := f.get_length()
		var r: Dictionary
		if len > MAX_BYTES:
			r = _no("too_big", "the file is larger than %d MiB" % (MAX_BYTES >> 20))
		else:
			r = decode(f.get_buffer(len))
		f.close()
		if r["ok"]:
			if best.is_empty() or r["payload"]["saved_unix"] > best["payload"]["saved_unix"]:
				best = r
		elif first.is_empty():
			first = r
	if not best.is_empty():
		return best
	return first if not first.is_empty() else _no("missing", "there is no saved run")


static func remove(path: String) -> void:
	for p in _files(path):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Keeps the save at path as path.prev (a new run replaces a run: one step back stays possible by hand).
static func keep_previous(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".prev"))
