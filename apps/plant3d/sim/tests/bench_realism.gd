extends SceneTree
## The model step with synthetic realism loads (docs/plant3d/REALISM.md §11, milestone RE1) on a desktop, headless:
##   godot --headless --script apps/plant3d/sim/tests/bench_realism.gd -- --synth=LABEL:PATH[,LABEL:PATH…]
##         [--data=PATH] [--base-steps=N] [--weather=KIND]
## Each PATH is tools/plant3d/realism_synth.py's output. Prints app/step_bench.gd's lines (STEP, BATCH), the train as
## built first; exit code 1 on an ERROR line. cold_iron runs in clear weather unless --weather=KIND names another
## (app/step_bench.gd run).

const StepBench = preload("../../app/step_bench.gd")


func _init() -> void:
	quit(1)
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var repo := ProjectSettings.globalize_path(get_script().resource_path).get_base_dir().path_join("../../../..")
	var files := StepBench.read_dir(opts.get("data", repo.simplify_path().path_join("data/plant3d")))
	var loads := {}
	for item in String(opts.get("synth", "")).split(",", false):
		var kv := item.split(":", true, 1)
		loads[kv[0]] = FileAccess.get_file_as_string(kv[1])
	var lines := StepBench.run(files, loads, int(opts.get("base-steps", "6000")),
			String(opts.get("weather", "clear")))
	var bad := false
	for l in lines:
		print(l)
		bad = bad or l.begins_with("ERROR")
	if not bad:
		quit(0)
