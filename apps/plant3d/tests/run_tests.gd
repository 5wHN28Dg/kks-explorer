## The app's tests (decision 0054 §10: a SceneTree script of our own, no test framework):
##   godot --headless --fixed-fps 60 --path apps/plant3d --script res://tests/run_tests.gd [-- --only=NAME]
##   … [-- --files=NAME,NAME…]   those test files only, each of which must exist (CI's shards: tests/shards.py app)
## Each test_*.gd here has `func run(tree) -> Array` (a coroutine allowed) returning the failures (strings). Exits 0
## when every test passed, 1 otherwise. Needs the built plant (build.sh) for the walking tests.
extends SceneTree

## Counts script errors (a test function stopped by one returns as if it had passed).
class ScriptErrors extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

var errors := ScriptErrors.new()
## The app's saved run (ui/autosave.gd) goes to a file of the tests' own, removed before each test file: no test
## starts with a run another one saved, and the user's own saved run is never touched.
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const TEST_SAVE := "user://tests-run.save"

func _init() -> void:
	OS.add_logger(errors)
	_run.call_deferred()

func _run() -> void:
	Autosave.default_path = TEST_SAVE
	var only := ""
	var some: Array = []     # --files=: a shard's test files (tests/shards.py app), each of which must be here
	var given_files := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--files="):
			given_files = true
			some = Array(a.substr(8).split(",", false))
	var files: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and (only == "" or f.get_basename() == only) \
				and (not given_files or some.has(f.get_basename())):
			files.append(f)
	files.sort()
	var failed := 0
	for s in some:
		if not files.has(s + ".gd") and (only == "" or s == only):
			print("FAIL run_tests.gd: no test file %s.gd (--files)" % s)
			failed += 1
	# the runner's own check: a script error inside a test function must be seen (it returns [] after one)
	print("tests' user data: %s" % OS.get_user_data_dir())   # build.sh checks it is the run's own folder
	print("(the runner checks that it sees script errors: one is expected next)")
	var e0 := errors.count
	await load("res://tests/fixtures/script_error.gd").new().run(self)
	if errors.count == e0:
		print("FAIL run_tests.gd: a script error in a test goes unnoticed")
		failed += 1
	for f in files:
		var t0 := Time.get_ticks_msec()
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("FAIL %s: does not compile" % f)
			failed += 1
			continue
		RunSave.remove(TEST_SAVE)
		var t = script.new()
		var errors0 := errors.count
		var problems: Array = await t.run(self)
		Engine.time_scale = 1.0          # a test stopped half way must not leave its time scale to the next
		# a script error stops the test function, which then returns an empty list: count it as a failure
		if errors.count > errors0:
			problems = problems + ["%d script error(s), above" % (errors.count - errors0)]
		if problems.is_empty():
			print("ok   %s (%d ms)" % [f, Time.get_ticks_msec() - t0])
		else:
			failed += 1
			for p in problems:
				print("FAIL %s: %s" % [f, p])
	RunSave.remove(TEST_SAVE)
	print("%d of %d test files passed" % [files.size() - failed, files.size()])
	quit(1 if failed > 0 or files.is_empty() else 0)
