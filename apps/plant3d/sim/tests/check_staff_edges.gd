extends SceneTree
## Places held in cases the staff vectors don't reach, as tests/test_plant3d_staff.py checks them on the reference
## (§17.8): a `leave` naming no place keeps what the trainee holds; someone already standing at a place they are sent
## to holds it; the trainee's meeting seat is theirs again after a pause; a machine command kept for a later step is
## dropped when its machine is entered by a command or an action, not by its own `next`; a kept unlock is dropped
## when its point is locked again; a paused step is looked at again when it resumes. Prints "STAFF_EDGES bad=N" and each failure.
##   godot --headless --script apps/plant3d/sim/tests/check_staff_edges.gd -- [VECTORS2]
const PlantModel = preload("../plant_model.gd")
const PlantEngine = preload("../engine.gd")
const JsonStrict = preload("../json_strict.gd")

var _bad: Array = []
var _files := {}


func _init() -> void:
	quit(1)         # stays the exit code if a script error stops this function
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "ref/vectors/plant3d-v2.json"
	var st: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value["staff"]
	_files = st["files"].duplicate()
	_files["scenarios/s1.json"] = st["runs"][0]["scenario"]
	if st["runs"][0]["staff"] != null:
		_files["staff.json"] = st["runs"][0]["staff"]
	_leave_nowhere()
	_standing_there()
	_meeting_seat()
	_kept_command_dropped()
	for b in _bad:
		print("FAIL ", b)
	print("STAFF_EDGES bad=%d" % _bad.size())
	quit(1 if _bad.size() else 0)


func _engine(trainee: String):
	var e = PlantEngine.new(PlantModel.from_files(_files), "s1")
	if trainee != "":
		e.role(trainee)
	e.step()
	return e


func _free_place(e, sm) -> int:
	for i in sm.places.size():
		if not sm.open[i] and not e.st_holder.has(i):
			return i
	return -1


func _leave_nowhere() -> void:
	var e = _engine("a_fo1")
	var sm = e._sm
	var tp: int = e.st_trainee
	e.st_t_at = -1
	e.sp_pos[tp] = -1
	var seat := _free_place(e, sm)
	e.sp_occ[tp] = seat
	e.st_holder[seat] = tp
	e.leave("no_such_place")
	e.step()
	if e.sp_occ[tp] != seat or e.st_holder.get(seat, -1) != tp:
		_bad.append("a leave naming no place let go of the trainee's place")


func _standing_there() -> void:
	var e = _engine("")
	var sm = e._sm
	var p := -1
	for i in sm.people.size():
		if e.sp_pos[i] != -1 and e.sp_leg[i].is_empty():
			p = i
			break
	sm.leave_place(e, p)
	sm.unreserve(e, p)
	var here := _free_place(e, sm)
	e.sp_pos[p] = here
	var r: String = sm.go(e, p, {"st": {}}, here)
	if r != "next" or e.sp_occ[p] != here or e.st_holder.get(here, -1) != p:
		_bad.append("someone standing at the place they were sent to doesn't hold it (%s)" % r)


func _meeting_seat() -> void:
	var e = _engine("a_fo1")
	var sm = e._sm
	var tp: int = e.st_trainee
	e.st_t_at = -1
	e.sp_pos[tp] = -1
	sm.leave_place(e, tp)
	var room := ""
	for r in sm.rooms:
		var i: int = sm.meet_place(e, r, tp)
		if i != -1 and sm.kind[i] in ["seat", "desk", "table"]:
			room = r
			break
	var mt := {"room": room, "with": [], "minutes": 5}
	var cur := {"st": {}, "prio": 0, "made": 0, "order": 0}
	if sm.meet(e, tp, cur, mt, true) != "wait" or e.sp_res[tp] != cur["st"]["place"]:
		_bad.append("the trainee's meeting seat was not reserved")
		return
	var seat: int = cur["st"]["place"]
	e.sp_cur[tp] = cur
	sm.pause(e, tp)
	sm.meet(e, tp, cur, mt, true)
	if e.sp_res[tp] != seat or e.st_holder.get(seat, -1) != tp:
		_bad.append("after a pause the trainee's meeting seat was not theirs again")


func _kept_command_dropped() -> void:
	var e = _engine("a_fo1")
	var sm = e._sm
	e.st_early = [["op", 1, "K", "start", "local", "m"], ["op", 1, "K2", "open", "local", null], ["lock", 1, "w", 0]]
	sm.drop_kept(e, [[5, "machine", "m", "a", "b", "next"]], "a_fo1")
	if e.st_early.size() != 3:
		_bad.append("a machine moved by its own next dropped a kept command")
	sm.drop_kept(e, [[5, "machine", "m", "b", "c", "command"]], "a_fo1")
	if e.st_early != [["op", 1, "K2", "open", "local", null], ["lock", 1, "w", 0]]:
		_bad.append("a machine entered by a command kept the earlier command: %s" % [e.st_early])
	e.st_early = [["unlock", 1, "w", 0], ["unlock", 1, "w", 1], ["lock", 1, "w", 0]]
	sm.drop_kept(e, [[5, "lock", "w", 0, "a_fo1", "refused", ["state"]]], "a_fo1")
	if e.st_early.size() != 3:
		_bad.append("a refused lock dropped a kept unlock")
	sm.drop_kept(e, [[5, "lock", "w", 0, "a_elec", "done", []]], "a_fo1")
	if e.st_early.size() != 3:
		_bad.append("another person's lock dropped the trainee's kept unlock (locks stack, PLANT3D §15.1)")
	sm.drop_kept(e, [[5, "lock", "w", 0, "a_fo1", "done", []]], "a_fo1")
	if e.st_early != [["unlock", 1, "w", 1], ["lock", 1, "w", 0]]:
		_bad.append("a point locked again kept the earlier unlock: %s" % [e.st_early])
	# a paused step is looked at again when it resumes
	var tp: int = e.st_trainee
	for i in 3000:
		if e.sp_cur[tp] != null:
			break
		e.step()
	if e.sp_cur[tp] == null:
		_bad.append("the trainee was given no task")
		return
	var st: Dictionary = e.sp_cur[tp]["st"]
	st["seen"] = true
	sm.pause(e, tp)
	if st.has("seen"):
		_bad.append("a paused step keeps its first look")
