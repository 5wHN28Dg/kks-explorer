extends SceneTree
## The straight-line program (engine.gd _gen_fast) against the interpreter (_run) where the reference has no result
## to compare with, headless:
##   godot --headless --script apps/plant3d/sim/tests/check_fast.gd -- --files=PATH --steps=N
##     PATH holds {relative path: text} of a plant's content: both engines run its scenario s1 for N steps, and
##     every value's bits must be equal at every step ("FAST steps=N differ=M").
##   godot --headless --script apps/plant3d/sim/tests/check_fast.gd -- --files=PATH --broken=1
##     a program that does not compile is compiled once per model, not once per engine ("BROKEN cached=…"); it
##     prints Godot's parse error on purpose.

const PlantModel = preload("../plant_model.gd")
const PlantEngine = preload("../engine.gd")


## An engine whose generated program does not compile.
class Broken extends PlantEngine:
	func _fast_source() -> String:
		return "static func run(:\n"


func _init() -> void:
	quit(1)         # stays the exit code if a script error stops this function
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var files: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(opts["files"]))
	var m = PlantModel.from_files(files)
	if m.error != "":
		print("MODEL ", m.error)
		return
	if opts.get("broken", "") == "1":
		var a = Broken.new(m, "s1")
		var b = Broken.new(m, "s1")
		var cache: Dictionary = m.get_meta(&"engine_fast", {})
		var src: String = a._fast_source()
		print("BROKEN cached=%s fast=%s,%s" % [cache.has(src) and cache[src] == null, a._fast, b._fast])
		quit(0)
		return
	var fast = PlantEngine.new(m, "s1")
	PlantEngine._interpret_only = true
	var slow = PlantEngine.new(m, "s1")
	PlantEngine._interpret_only = false
	if fast._fast == null or slow._fast != null:
		print("PROGRAM not as asked: fast=%s interpreter=%s" % [fast._fast, slow._fast])
		return
	var differ := 0
	var steps: int = opts.get("steps", "10").to_int()
	for k in steps:
		fast.step()
		slow.step()
		var x: PackedFloat64Array = fast.value_array()
		var y: PackedFloat64Array = slow.value_array()
		if x.to_byte_array() != y.to_byte_array():
			differ += 1
			for i in x.size():
				if var_to_bytes(x[i]) != var_to_bytes(y[i]):
					print("step %d %s: %s, interpreter %s" % [k + 1, fast.names[i], x[i], y[i]])
	print("FAST steps=%d differ=%d" % [steps, differ])
	quit(0)
