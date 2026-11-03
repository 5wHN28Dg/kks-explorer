extends SceneTree
## A save and restore, and a clone, while people wait asleep for a place taken or for a meeting's others (PLANT3D.md
## §21.15, staff.gd _wake_at): the first train's `shift_cold` run to the shift change (05:40), on until some wait
## asleep, then saved (ui/run_save.gd, as the app saves) into a new engine and cloned; the three go on 3,000 steps
## and must agree at every step (digest and staff state), with some woken by _wake_at after the save (else the check
## proves little). Prints "WAITS ok" or each failure.
##   godot --headless --script apps/plant3d/sim/tests/check_staff_waits.gd
const PlantModel = preload("../plant_model.gd")
const RunSave = preload("../../ui/run_save.gd")


func _init() -> void:
	quit(1)
	var repo := ProjectSettings.globalize_path(get_script().resource_path).get_base_dir().path_join("../../../..")
	var m = PlantModel.from_dir(repo.simplify_path().path_join("data/plant3d"))
	if m.error != "":
		print("FAIL ", m.error)
		return
	var Engine_ = load(get_script().resource_path.get_base_dir().path_join("../engine.gd"))
	var e = Engine_.new(m, "shift_cold")
	e.step(4000)
	var asleep := 0
	for k in 3000:
		e.step()
		asleep = 0
		for i in e.sp_wait_on.size():
			if e.sp_wait_on[i] != -1 and e.sp_wake[i] > e.step_no:
				asleep += 1
		if asleep >= 2:
			break
	if asleep < 2:
		print("FAIL nobody asleep waiting by step %d" % e.step_no)
		return
	print("asleep waiting at step %d: %d" % [e.step_no, asleep])
	var f = Engine_.new(m, "shift_cold")
	var saved := RunSave.capture(e, RunSave.engine_fields(e))
	var why := RunSave.check(f, RunSave.engine_fields(f), saved)
	if why != "":
		print("FAIL the save refused: ", why)
		return
	RunSave.apply(f, saved)
	var c = e.clone()
	e._staff_prof_on = true
	var bad := 0
	for k in 3000:
		e.step()
		f.step()
		c.step()
		var d: PackedByteArray = e.digest()
		if f.digest() != d or c.digest() != d or f.sp_wake != e.sp_wake or c.sp_wake != e.sp_wake \
				or f.sp_wait_on != e.sp_wait_on or c.sp_wait_on != e.sp_wait_on or f.events.size() != e.events.size():
			print("FAIL the restored run or the clone differs at step %d" % e.step_no)
			bad += 1
			break
	if e._staff_prof_n["wakes"] == 0:
		print("FAIL nobody woken by _wake_at after the save")
		bad += 1
	print("woken by _wake_at after the save: %d" % e._staff_prof_n["wakes"])
	if bad == 0:
		print("WAITS ok")
		quit(0)
