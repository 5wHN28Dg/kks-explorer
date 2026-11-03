extends SceneTree
## A save and restore, and a clone, while people wait asleep for a place taken or for a meeting's others (PLANT3D.md
## §21.15, staff.gd _wake_at): the first train's `shift_cold` run to the shift change (05:40), on until some wait
## asleep, then saved (ui/run_save.gd, as the app saves) into a new engine and cloned; the three go on 3,000 steps
## and must agree at every step (digest and staff state), with some woken by _wake_at after the save (else the check
## proves little). Then the full day of `shift_cold` and a shift of `shift_wtp` with the waits asleep and awake
## (_staff_wait_sleep): the same events and digests. And each way a sleeper is woken, alone: a place reserved, a
## reservation let go, a place left, someone getting off a vehicle there, a released player put back there, someone
## arriving there at the end of a way, someone there coming on duty (and _put not waking for no move). Prints "WAITS ok" or each failure.
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
	bad += _wake_paths(Engine_, m)
	bad += _awake_alike(Engine_, m, "shift_cold", 144000)
	bad += _awake_alike(Engine_, m, "shift_wtp", 30000)
	if bad == 0:
		print("WAITS ok")
		quit(0)


## The scenario run `steps` steps twice, once with the waits asleep and once with them awake every step (the engine
## before they slept, which the vectors check against the reference): the two must agree (the events every step, the
## digest every 50), and some must have slept (else the comparison proves little).
func _awake_alike(Engine_, m, sc: String, steps: int) -> int:
	var a = Engine_.new(m, sc)
	var b = Engine_.new(m, sc)
	if a._sm == null:
		print("FAIL %s: no staff" % sc)
		return 1
	b._staff_wait_sleep = false
	a._staff_prof_on = true
	b._staff_prof_on = true
	for k in steps:
		a.step()
		b.step()
		if a.events.size() != b.events.size() or (not a.events.is_empty() and a.events[-1] != b.events[-1]) \
				or (a.step_no % 50 == 0 and a.digest() != b.digest()):
			var i := mini(a.events.size(), b.events.size()) - 1
			print("FAIL %s: asleep and awake differ at step %d (%s / %s)" % [sc, a.step_no, str(a.events[i]),
					str(b.events[i])])
			return 1
	print("%s: %d steps alike; task steps run asleep %d, awake %d; woken by _wake_at %d" % [sc, steps,
			a._staff_prof_n["runs"], b._staff_prof_n["runs"], a._staff_prof_n["wakes"]])
	if a._staff_prof_n["wakes"] == 0 or a._staff_prof_n["runs"] >= b._staff_prof_n["runs"]:
		print("FAIL %s: nobody slept in a wait" % sc)
		return 1
	return 0


var _wbad := 0


func _wake_paths(Engine_, m) -> int:
	var e = Engine_.new(m, "shift_cold")
	e.step(4500)
	var sm = e._sm
	var np: int = sm.people.size()
	var p := -1                 # a place in a room, held by nobody and not open
	for i in sm.places.size():
		if sm.room_of[i] != null and not sm.open[i] and not e.st_holder.has(i):
			p = i
			break
	var w := -1                 # the sleeper and the one who acts: NPCs off site, doing nothing
	var y := -1
	for i in np:
		if e._absent.has(i) or e.st_players.has(i) or e.sp_pos[i] != -1 or e.sp_on[i] or e.sp_aboard[i] != -1:
			continue
		if w == -1:
			w = i
		elif y == -1:
			y = i
	if p == -1 or y == -1:
		print("FAIL wake paths: no place or people to use")
		return 1
	var o := -1                 # a place outside p's room (no wake)
	for i in sm.places.size():
		if sm.wait_key[i] != sm.wait_key[p]:
			o = i
			break
	_wbad = 0
	_sleep(e, sm, w, p)
	sm._put(e, y, o)
	_woken(e, w, false, "someone coming to a place in another room")
	sm._put(e, y, p)
	_woken(e, w, true, "someone coming to a place in the room")
	_sleep(e, sm, w, p)
	sm._put(e, y, p)
	_woken(e, w, false, "someone put where they already are")
	e.sp_pos[y] = -1
	_sleep(e, sm, w, p)
	sm.reserve(e, y, p)
	_woken(e, w, true, "a place reserved")
	_sleep(e, sm, w, p)
	sm.unreserve(e, y)
	_woken(e, w, true, "a reservation let go")
	e.sp_occ[y] = p
	e.st_holder[p] = y
	_sleep(e, sm, w, p)
	sm.leave_place(e, y)
	_woken(e, w, true, "a place left")
	e.sp_aboard[y] = 0
	_sleep(e, sm, w, p)
	sm.get_off(e, y, 0, p)
	_woken(e, w, true, "someone getting off a vehicle")
	e.sp_pos[y] = -1
	e.st_players[0] = y
	e.st_t_from[0] = p
	_sleep(e, sm, w, p)
	sm.let_go(e, 0)
	_woken(e, w, true, "a released player put back")
	e.sp_pos[y] = -1
	e.sp_leg[y] = [o, p, e.step_no - 1, e.step_no]
	e.sp_wake[y] = 0
	_sleep(e, sm, w, p)
	sm.turn(e, y)
	_woken(e, w, true, "someone at the end of a way")
	e.sp_leg[y] = []
	e.sp_pos[y] = p
	e.sp_on[y] = 0
	var c: int = e.clock()
	var du: Array = []
	for i in np:
		if not e.sp_duties[i].is_empty():
			du = e.sp_duties[i][0].duplicate()
			break
	du[0] = c - 1
	du[1] = c + 100000
	e.sp_duties[y] = [du]
	_sleep(e, sm, w, p)
	sm._phase1(e, c, c / sm.DAY)
	_woken(e, w, true, "someone there coming on duty")
	return _wbad


func _sleep(e, sm, w: int, p: int) -> void:
	e.sp_wait_on[w] = sm.wait_key[p]
	e.sp_wake[w] = 1 << 40


func _woken(e, w: int, want: bool, what: String) -> void:
	var got: bool = e.sp_wake[w] == 0 and e.sp_wait_on[w] == -1
	if got != want:
		print("FAIL wake paths: %s %s the sleeper" % [what, "did not wake" if want else "woke"])
		_wbad += 1
