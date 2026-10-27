## A session's snapshot (docs/plant3d/MULTIPLAYER.md §5.1): what a joiner, a player coming back or a desynced player
## loads to have the host's plant at a committed step. Its own Dictionary, not a run save:
##   {"app", "content", "scenario", "engine", "session"}
## `engine` exactly the save's engine part (ui/run_save.gd capture: every state field, with its events and inputs),
## `session` the host's {"step", "roster", "settings"} at that step (nothing in them is secret from the players).
## Encoded as the save is (var_to_bytes, no objects) and compressed with zstd; the uncompressed length travels with it,
## and a joiner refuses one over the save's MAX_BYTES or of any other length once decompressed, at most 16 MiB
## compressed. The joiner checks it as the save's loader checks a save (RunSave.check, and the engine's contents as
## ui/autosave.gd checks them).
##
## The host's and the player's saved sessions (§7.4) are files of their own format, run_save.gd's container with the
## magic "WDPMSAV\n": the snapshot's Dictionary, plus `saved_unix`.
extends RefCounted

const RunSave = preload("res://ui/run_save.gd")
const Autosave = preload("res://ui/autosave.gd")
const PlantEngine = preload("res://sim/engine.gd")

const MAX_COMPRESSED := 16 * 1024 * 1024
const KEYS := {"app": TYPE_STRING, "content": TYPE_STRING, "scenario": TYPE_STRING, "engine": TYPE_DICTIONARY,
		"session": TYPE_DICTIONARY}
const MAGIC := "WDPMSAV\n"
const FORMAT := 1


## Takes the snapshot's Dictionary (on the main thread: the engine's state copied, as the save copies it).
static func take(engine, scenario: String, content: String, session: Dictionary) -> Dictionary:
	return {"app": RunSave.app_version(), "content": content, "scenario": scenario,
			"engine": RunSave.capture(engine, RunSave.engine_fields(engine)), "session": session.duplicate(true)}


## [uncompressed length, compressed bytes] (a worker thread's part).
static func encode(d: Dictionary) -> Array:
	var raw := var_to_bytes(d)
	return [raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD)]


## The Dictionary, or a String saying why not.
static func decode(raw_len: int, z: PackedByteArray):
	if z.size() > MAX_COMPRESSED:
		return "the snapshot is too large"
	if raw_len <= 0 or raw_len > RunSave.MAX_BYTES:
		return "the snapshot's length is out of bounds"
	var raw := z.decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_len:
		return "the snapshot doesn't decompress to its length"
	var d = bytes_to_var(raw)          # (never objects: bytes_to_var_with_objects is not used)
	if typeof(d) != TYPE_DICTIONARY:
		return "the snapshot is not a dictionary"
	if d.size() != KEYS.size():
		return "the snapshot has other parts"
	for k in KEYS:
		if typeof(d.get(k)) != KEYS[k]:
			return "the snapshot's part %s is missing or of the wrong kind" % k
	return d


## Why this snapshot can't be loaded here, or "".
static func check(d: Dictionary, model, content: String) -> String:
	if d["app"] != RunSave.app_version():
		return "the host runs another version of the app"
	if d["content"] != content:
		return "the host's plant content differs"
	if not model.scenarios.has(d["scenario"]):
		return "its scenario is not in this plant"
	var fresh = PlantEngine.new(model, d["scenario"], true)
	var bad := RunSave.check(fresh, RunSave.engine_fields(fresh), d["engine"])
	if bad == "":
		bad = Autosave._engine_contents(fresh, d["engine"])
	if bad == "" and not d["engine"].get("st_session", false):
		bad = "not a session run"
	if bad != "":
		return "the plant's state does not fit this version: " + bad
	var s: Dictionary = d["session"]
	if typeof(s.get("step")) != TYPE_INT or s["step"] != d["engine"].get("step_no", -1):
		return "the snapshot's step is damaged"
	return ""


# ------------------------------------------------------------------ the saved sessions (§7.4)

static func file_bytes(d: Dictionary) -> PackedByteArray:
	var p := d.duplicate()
	p["saved_unix"] = int(Time.get_unix_time_from_system())
	var body := var_to_bytes(p)
	var out := MAGIC.to_ascii_buffer()
	var nums := PackedByteArray()
	nums.resize(12)
	nums.encode_u32(0, FORMAT)
	nums.encode_u64(4, body.size())
	out.append_array(nums)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(body)
	out.append_array(h.finish())
	out.append_array(body)
	return out


static func write_file(path: String, d: Dictionary) -> Error:
	return RunSave.write(path, file_bytes(d))


## The saved session's Dictionary (the snapshot's parts, `saved_unix` taken off), or a String saying why not.
static func read_file(path: String):
	if not FileAccess.file_exists(path):
		return "there is no saved session"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > RunSave.MAX_BYTES:
		return "the saved session can't be read"
	var b := f.get_buffer(f.get_length())
	f.close()
	if b.size() < RunSave.HEAD or b.slice(0, 8) != MAGIC.to_ascii_buffer():
		return "it is not a saved session"
	if b.decode_u32(8) != FORMAT:
		return "it was saved by another version of the app"
	if b.decode_u64(12) != b.size() - RunSave.HEAD:
		return "the file is cut short or has bytes after its end"
	var body := b.slice(RunSave.HEAD)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(body)
	if h.finish() != b.slice(20, RunSave.HEAD):
		return "the file is damaged (its checksum does not match)"
	var p = bytes_to_var(body)
	if typeof(p) != TYPE_DICTIONARY or typeof(p.get("saved_unix")) != TYPE_INT:
		return "the file's contents are not a saved session"
	p.erase("saved_unix")
	if p.size() != KEYS.size():
		return "the saved session has other parts"
	for k in KEYS:
		if typeof(p.get(k)) != KEYS[k]:
			return "the saved session's part %s is missing or of the wrong kind" % k
	return p
