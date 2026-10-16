## The app's tests (decision 0054 §10: a SceneTree script of our own, no test framework):
##   godot --headless --fixed-fps 60 --path apps/plant3d --script res://tests/run_tests.gd [-- --only=NAME]
## Each test_*.gd here has `func run(tree) -> Array` (a coroutine allowed) returning the failures (strings). Exits 0
## when every test passed, 1 otherwise. Needs the built plant (build.sh) for the walking tests.
extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var files: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and (only == "" or f.get_basename() == only):
			files.append(f)
	files.sort()
	var failed := 0
	for f in files:
		var t0 := Time.get_ticks_msec()
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("FAIL %s: does not compile" % f)
			failed += 1
			continue
		var t = script.new()
		var problems: Array = await t.run(self)
		if problems.is_empty():
			print("ok   %s (%d ms)" % [f, Time.get_ticks_msec() - t0])
		else:
			failed += 1
			for p in problems:
				print("FAIL %s: %s" % [f, p])
	print("%d of %d test files passed" % [files.size() - failed, files.size()])
	quit(1 if failed > 0 or files.is_empty() else 0)
