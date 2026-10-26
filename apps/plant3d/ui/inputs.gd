## The trainee's inputs to the plant, one path (docs/plant3d/MULTIPLAYER.md §3.1, milestone MP1): every input the app
## makes (a panel's button, the card, the walker's arrivals and zones, the instructor) goes through send(), in the
## trace form [kind, …] of docs/PLANT3D.md §12 and §17.6, without its step or slot. Alone, the input is queued in the
## run's engine at once and takes effect in the engine's next step, as it always has (send() returns that step). In a
## session (MP2), `sink` takes it to the session, which sends it to the host; every player's engine gets it with the
## commit that schedules it, with this player's slot, and send() returns -1 (not known yet).
## tests/test_inputs_path.py checks that nothing in the app makes an input any other way.
extends RefCounted

var clock               # ui/sim_clock.gd: its engine is the run's (a restart or a loaded save replaces it)
var slot := 0           # this player's slot (§17.13): 0 alone
var sink := Callable()  # a session's: takes the input ([kind, …]); unset, the engine directly


## The step the input takes effect in (alone), or -1 when a session decides it.
func send(item: Array) -> int:
	if sink.is_valid():
		sink.call(item)
		return -1
	var e = clock.engine
	if e == null:
		return -1
	var n: int = e.step_no + 1
	e.apply_input([n] + item + ([slot] if e.st_session else []))
	return n


## The person this player plays (§17.4), -1 in free mode or without staff.
func person() -> int:
	var e = clock.engine if clock != null else null
	if e == null or e._sm == null:
		return -1
	return e.trainee(slot)


# the inputs, by kind (§12, §17.6)

## An op; with where and person a version 2 op (§17.1).
func op(kks: String, do: String, value = null, trip = null, where = null, person_id = null) -> int:
	return send(["op", kks, do, value, trip, where, person_id] if where != null or person_id != null \
			else ["op", kks, do, value, trip])


func ack(alarm: String) -> int:
	return send(["ack", alarm])


func shelve(alarm: String, seconds: float) -> int:
	return send(["shelve", alarm, seconds])


func unshelve(alarm: String) -> int:
	return send(["unshelve", alarm])


## The instructor's fault and repair (§7.8, §15.5).
func fault(fid: String) -> int:
	return send(["fault", fid])


func repair(fid: String) -> int:
	return send(["repair", fid])


## The trainee's repair under a work's permit (§15.5).
func repair_under(fid: String, work: String, person_id) -> int:
	return send(["repair", fid, work, person_id])


func permit(work: String, action: String, person_id) -> int:
	return send(["permit", work, action, person_id])


func lock(work: String, point: int, person_id) -> int:
	return send(["lock", work, point, person_id])


func unlock(work: String, point: int, person_id) -> int:
	return send(["unlock", work, point, person_id])


## A lock removed by authority (§15.1), naming whose.
func remove_lock(work: String, point: int, person_id, reason: String, owner) -> int:
	return send(["remove_lock", work, point, person_id, reason, owner])


func role(person_id: String) -> int:
	return send(["role", person_id])


func task_ack() -> int:
	return send(["task_ack"])


func arrive(place: String) -> int:
	return send(["arrive", place])


func leave(place: String) -> int:
	return send(["leave", place])


func read(code: String, value: float) -> int:
	return send(["read", code, value])


func say(message: String, to: String) -> int:
	return send(["say", message, to])


func pick(index: int) -> int:
	return send(["pick", index])


func radio_call(role_id: String, task: String, work = null) -> int:
	return send(["call", role_id, task, work])


func jump(hhmm: String) -> int:
	return send(["jump", hhmm])


func ppe(item: String, on: int) -> int:
	return send(["ppe", item, on])


func zone(zone_id: String, how: String) -> int:
	return send(["zone", zone_id, how])


func stop_act(person_id: String) -> int:
	return send(["stop", person_id])
