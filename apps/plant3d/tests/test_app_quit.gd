## Quitting the app. A quit tears the whole tree down from the window's root, children last to first, while the root
## is busy removing them: a script that frees a node still under the root from its `_exit_tree` then corrupts the
## heap (0.3.0's first build crashed on every quit: app/hud.gd freed the input mode node, which sits last under the
## root). The tests' own runner never quits the app that way (they free `main`, whose children leave first), so the
## app is started in a process of its own and quit as a user quits it.
## Also: a quit while a periodic save is being written leaves a complete save (ui/autosave.gd waits for its thread).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const RunSave = preload("res://ui/run_save.gd")
const Autosave = preload("res://ui/autosave.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	_quit_in_own_process(p)
	await _quit_while_saving(tree, p)
	return p


## The app started headless in its own process, quit after some frames (Godot's own quit: the tree torn down from the
## root). `scenario=` keeps it off the tests' saved run (main.gd: a start the command line asks for saves apart).
func _quit_in_own_process(p: Array) -> void:
	var out: Array = []
	var args := ["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"),
		"--quit-after", "240", "--", "scenario=cold_iron"]
	# a quit that hangs fails here in 3 minutes (exit 124) instead of holding the CI job to its limit
	var code := OS.execute("timeout", ["180", OS.get_executable_path()] + args, out, true) if OS.get_name() == "Linux" \
			else OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(out)
	if not text.contains("first frame drawn"):
		p.append("the app in its own process did not start: %s" % text.right(600))
		return
	if code != 0:
		p.append("the app quit with exit code %d, not 0: %s" % [code, text.right(600)])
	for bad in ["Parent node is busy", "data.parent", "SCRIPT ERROR", "corrupted", "crashed with signal", "double free",
			"free(): ", "Segmentation fault"]:
		if text.contains(bad):
			p.append("the app's quit logged \"%s\": %s" % [bad, text.right(600)])


## A periodic save started and the app quit at once (its worker thread may still be writing): the quit waits for the
## thread, and the save on disk is the state of the step it was taken at, complete.
func _quit_while_saving(tree: SceneTree, p: Array) -> void:
	var path: String = Autosave.default_path
	RunSave.remove(path)
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or ui.autosave == null or not ui.autosave.armed:
		main.free()
		p.append("the app did not start with its autosave armed")
		return
	ui.clock.run_steps(40)
	await tree.process_frame
	var at_step: int = ui.clock.engine.step_no
	var want := var_to_bytes(RunSave.capture(ui.clock.engine, RunSave.engine_fields(ui.clock.engine)))
	ui.autosave._t = Autosave.INTERVAL
	ui.autosave._process(0.0)
	var autosave = ui.autosave
	if autosave._thread == null:
		p.append("the periodic save did not start")
	tree.root.remove_child(main)     # the quit, as the tree's teardown does it: every _exit_tree, at once
	if autosave._thread != null:
		p.append("the app left the tree with its save's thread still running")
	main.free()
	var rp := RunSave.read(path)
	if not rp["ok"]:
		p.append("a quit while saving left no complete save: %s" % rp.get("text", ""))
	elif rp["payload"]["engine"]["step_no"] != at_step or var_to_bytes(rp["payload"]["engine"]) != want:
		p.append("a quit while saving left a save of another step than the one it was taken at")
	RunSave.remove(path)
