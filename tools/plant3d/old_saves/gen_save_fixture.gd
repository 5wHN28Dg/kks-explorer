## Writes the saved-run fixture of an older release (apps/plant3d/tests/fixtures/run-<version>.save, issue #447): run
## in a checkout of that release (here plant-v0.3.0), after its `apps/plant3d/build.sh` has built the plant:
##   cp tools/plant3d/old_saves/gen_save_fixture.gd OLD/apps/plant3d/tests/
##   godot --headless --fixed-fps 60 --path OLD/apps/plant3d --script res://tests/gen_save_fixture.gd -- OUT.save
## The app's own autosave writes it: a cold start's first steps, a deviation (an operation of a later step), an
## operation sent and not yet stepped, the trainee flying somewhere else. tests/test_run_save.gd loads it.
extends SceneTree

const App = preload("res://tests/ui_app.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	Autosave.default_path = "user://gen-fixture.save"
	RunSave.remove(Autosave.default_path)
	var main := App.start(self)
	await process_frame
	var ui = main.ui
	ui.start_procedure("cold_start", null, false)
	ui.go_control_room()
	ui.do_op({"kks": "00QFA10AN001", "do": "start"}, null)
	ui.clock.run_steps(1)
	App.run_until(ui, "ia_p_norm", 20000)
	ui.clock.run_steps(30)
	ui.do_op({"kks": "00PGC10AP001", "do": "start"}, null)
	ui.clock.run_steps(200)
	ui.do_op({"kks": "30PAR10AA001", "do": "auto"}, null)      # not this step's: a deviation
	ui.clock.run_steps(40)
	ui.do_op({"kks": "00PGC10AP002", "do": "start"}, null)     # sent, not yet stepped
	ui.player.set_mode(ui.player.Mode.FLY)
	ui.player.global_position = Vector3(12.0, 9.0, -7.0)
	ui.player.set_heading(1.25, -0.3)
	await process_frame
	if not ui.autosave.save_now():
		print("GEN FAIL: not saved")
		quit(1)
		return
	var b := FileAccess.get_file_as_bytes(Autosave.default_path)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()
	var r := RunSave.decode(b)
	print("GEN OK app=%s step=%d inputs=%d events=%d bytes=%d proc=%s idx=%d devs=%s" % [r["payload"]["app"], r["payload"]["engine"]["step_no"],
			r["payload"]["engine"]["inputs"].size(), r["payload"]["engine"]["events"].size(), b.size(), r["payload"]["procedure"], r["payload"]["tracker"]["index"], str(r["payload"]["tracker"]["deviations"])])
	main.free()
	RunSave.remove(Autosave.default_path)
	quit(0)
