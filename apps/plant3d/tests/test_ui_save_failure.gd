## An autosave that fails is said (issue #473; the user's UI-UX policy S3, W3), with a save path that can't be written
## (its folder is a file):
## - the first failure is said once on screen in plain words: what happened, that the run goes on but isn't kept since
##   the last save (its plant time), what to do; the HUD's status line says it for as long as it lasts;
## - later failures (a save on demand, a periodic one on its thread) say nothing more, and are tried less often
##   (the retry's wait doubles, at most a minute);
## - a save that succeeds afterwards says so, and the status line's note goes.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const W = preload("res://ui/widgets.gd")
const Autosave = preload("res://ui/autosave.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or ui.autosave == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	var a = ui.autosave
	var good: String = a.path
	var blocker := "user://tests-save-blocker"       # a file where the save's folder would be
	FileAccess.open(blocker, FileAccess.WRITE).store_string("not a folder")
	var bad := blocker.path_join("run.save")
	ui.clock.run_steps(300)
	if not a.save_now():
		p.append("the first save (a writable path) failed")
	var saved_at := W.model_time(ui.clock.engine.step_no)
	ui.clock.run_steps(300)
	# 1. the first failure: said, plainly
	a.path = bad
	ui._toast.visible = false
	if a.save_now():
		p.append("a save into a file's place succeeded")
	var said: String = ui._toast.text if ui._toast.visible else ""
	if said == "":
		p.append("a failed save said nothing on screen")
	for t in ["could not be saved", "storage may be full", "carry on", saved_at, "is lost", "Free some space",
			"tried again by itself"]:
		if said != "" and not said.contains(t):
			p.append("the failure's words lack \"%s\": %s" % [t, said])
	await tree.process_frame
	var st: String = main.hud.status.text
	if not st.begins_with("Run not saved since " + saved_at):
		p.append("the status line does not say the run isn't saved: %s" % st)
	# 2. again, on demand and on the periodic save's thread: nothing said again; tried less often
	if a.get("_retry") != Autosave.INTERVAL:
		p.append("the first retry waits %s s, not %.0f" % [a.get("_retry"), Autosave.INTERVAL])
	ui._toast.visible = false
	a.save_now()
	if ui._toast.visible:
		p.append("a second failure said it again: %s" % ui._toast.text)
	if a.get("_retry") != 2.0 * Autosave.INTERVAL:
		p.append("the retry's wait did not double (%s s)" % a.get("_retry"))
	ui.clock.run_steps(10)
	a._t = 1000.0                    # the periodic save is due
	a._each_frame(0.0)
	if a._thread == null:
		p.append("the periodic save did not try again")
	else:
		while a._thread != null and a._thread.is_alive():
			await tree.process_frame
		if a._thread != null:
			a._each_frame(0.0)       # its outcome (else the app's own frame took it)
	if ui._toast.visible:
		p.append("the periodic save's failure said it again: %s" % ui._toast.text)
	if not a.get("failing") or a.get("_retry") != 4.0 * Autosave.INTERVAL:
		p.append("after the periodic failure: failing %s, retry %s s" % [a.get("failing"), a.get("_retry")])
	for i in 6:
		a.save_now()
	if a.get("_retry") != 60.0:
		p.append("the retry's wait is %s s, not at most 60" % a.get("_retry"))
	# 3. writable again: said, and the note gone
	a.path = good
	if not a.save_now():
		p.append("the save failed after the path was writable again")
	if not ui._toast.visible or ui._toast.text != "The run is saved again.":
		p.append("a save after failures did not say the run is saved again: %s" % ui._toast.text)
	await tree.process_frame
	if main.hud.status.text.contains("not saved"):
		p.append("the status line still says the run isn't saved: %s" % main.hud.status.text)
	if a.get("failing") or a.get("_retry") != Autosave.INTERVAL:
		p.append("after a save that succeeded: failing %s, retry %s s" % [a.get("failing"), a.get("_retry")])
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	return p
