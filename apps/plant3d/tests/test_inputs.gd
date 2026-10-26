## The trainee's inputs go one way (ui/inputs.gd, docs/plant3d/MULTIPLAYER.md §3.1, milestone MP1):
## - alone, an input made through it is queued in the engine as the engine's own method queues it (the same queue
##   entry, the same `inputs` record) and takes effect in the next step, which send() returns;
## - in a session run (PLANT3D.md §17.13) it carries the player's slot; with a session's sink set it goes there and
##   not to the engine;
## - the app's own buttons go through it (a role taken, an op made, an alarm acknowledged, a reading written, the
##   Crew panel's Seen);
## - a run saved with inputs still queued (a version 2 op, a staff input) is offered back: the saved run's check knew
##   only format 1's input sizes and refused them as damaged.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const PlantEngine = preload("res://sim/engine.gd")
const Inputs = preload("res://ui/inputs.gd")
const RunSave = preload("res://ui/run_save.gd")


class FakeClock:
	var engine


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var m = PlantModel.from_dir("res://built/content")
	if m.error != "":
		return ["the model did not load: " + m.error]
	_same_as_the_engine(m, p)
	_session(m, p)
	await _app(tree, p)
	return p


## Every kind of input through inputs.gd is the engine's own: the same queue and the same record.
func _same_as_the_engine(m, p: Array) -> void:
	var a = PlantEngine.new(m, "shift_cold")
	var b = PlantEngine.new(m, "shift_cold")
	var c := FakeClock.new()
	c.engine = a
	var io := Inputs.new()
	io.clock = c
	var n: int = io.role("a_fo_cw")
	b.role("a_fo_cw")
	if n != 1:
		p.append("send() did not say the input takes effect in the next step (%d)" % n)
	io.op("00PGC10AP001", "start", null, null, "local", "a_fo_cw")
	b.op("00PGC10AP001", "start", null, null, "local", "a_fo_cw")
	io.op("00PGC10AP001", "stop")
	b.op("00PGC10AP001", "stop")
	io.ack("x")
	b.ack("x")
	io.shelve("x", 30.0)
	b.shelve("x", 30.0)
	io.unshelve("x")
	b.unshelve("x")
	io.fault("cw_b_motor")
	b.fault("cw_b_motor")
	io.repair("cw_b_motor")
	b.repair("cw_b_motor")
	io.repair_under("cw_b_motor", "wo_cw_b_motor", "a_fo_cw")
	b.repair_under("cw_b_motor", "wo_cw_b_motor", "a_fo_cw")
	io.permit("wo_cw_b_motor", "request", "a_fo_cw")
	b.permit("wo_cw_b_motor", "request", "a_fo_cw")
	io.lock("wo_cw_b_motor", 0, "a_fo_cw")
	b.lock("wo_cw_b_motor", 0, "a_fo_cw")
	io.unlock("wo_cw_b_motor", 0, "a_fo_cw")
	b.unlock("wo_cw_b_motor", 0, "a_fo_cw")
	io.remove_lock("wo_cw_b_motor", 0, "a_fo_cw", "Gone home", null)
	b.remove_lock("wo_cw_b_motor", 0, "a_fo_cw", "Gone home", null, true)
	io.task_ack()
	b.task_ack()
	io.arrive("gate")
	b.arrive("gate")
	io.leave("gate")
	b.leave("gate")
	io.read("00QFB10CP001", 1.5)
	b.read("00QFB10CP001", 1.5)
	io.say("all_well", "channel")
	b.say("all_well", "channel")
	io.pick(0)
	b.pick(0)
	io.radio_call("field_op", "check_alarm", null)
	b.radio_call("field_op", "check_alarm", null)
	io.jump("06:00")
	b.jump("06:00")
	io.ppe("helmet", 1)
	b.ppe("helmet", 1)
	io.zone("z", "in")
	b.zone("z", "in")
	io.stop_act("a_fo1")
	b.stop_act("a_fo1")
	if var_to_bytes(a.queue) != var_to_bytes(b.queue) or var_to_bytes(a.inputs) != var_to_bytes(b.inputs):
		p.append("an input through inputs.gd is not the engine's own: %s / %s" % [str(a.inputs), str(b.inputs)])
	a.step()
	b.step()
	if var_to_bytes(a.events) != var_to_bytes(b.events) or a.digest() != b.digest():
		p.append("the inputs through inputs.gd did not do what the engine's own did")


## A session run: the player's slot on every input; a session's sink takes the input instead of the engine.
func _session(m, p: Array) -> void:
	var e = PlantEngine.new(m, "shift_cold", true)
	var c := FakeClock.new()
	c.engine = e
	var io := Inputs.new()
	io.clock = c
	io.slot = 3
	io.role("a_fo_cw")
	io.ack("x")
	if e.inputs != [[1, "role", "a_fo_cw", 3], [1, "ack", "x", 3]]:
		p.append("a session run's inputs do not carry the player's slot: %s" % str(e.inputs))
	e.step()
	if e.trainee(3) != e._sm.person_ix["a_fo_cw"] or io.person() != e.trainee(3):
		p.append("the role taken through inputs.gd is not slot 3's")
	var got := []
	io.sink = func(item): got.append(item)
	if io.task_ack() != -1 or got != [["task_ack"]] or e.queue.size() != 0:
		p.append("with a session's sink the input did not go to it alone: %s, %s" % [str(got), str(e.queue)])


## The app alone: its buttons go through inputs.gd (sent counts what reached the engine that way), and a run saved
## with a version 2 op and staff inputs still queued is offered back.
func _app(tree: SceneTree, p: Array) -> void:
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.inputs == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		p.append("the app did not start with its input path")
		return
	var seen := []
	ui.start_shift("shift_cold")
	var e = ui.clock.engine
	ui.inputs.sink = _watch.bind(ui, seen)     # (watches what the app sends, then hands it on as alone)
	ui.take_role("a_fo_cw")
	if e.trainee() == -1 or seen.is_empty() or seen[0] != ["role", "a_fo_cw"]:
		p.append("the role was not taken through inputs.gd: %s" % str(seen))
	ui.do_op({"kks": "00PGC10AP001", "do": "start"}, null)
	ui.ack("no_such_alarm", false)
	ui.write_reading("00QFB10CP001", "1.5")
	ui.open_crew()
	ui.crew._sig = ""
	ui.crew.refresh()
	var kinds := []
	for x in seen:
		kinds.append(x[0])
	for k in ["role", "op", "ack", "read"]:
		if not k in kinds:
			p.append("the app's %s did not go through inputs.gd (sent: %s)" % [k, str(kinds)])
	# queued and not yet stepped when the run is saved: a version 2 op, a reading, an arrival
	ui.inputs.sink = Callable()
	ui.clock.set_speed(ui.clock.Speed.PAUSED)
	ui.inputs.op("00PGC10AP001", "stop", null, null, "local", ui.me())
	ui.inputs.read("00QFB10CP001", 1.0)
	ui.inputs.arrive("gate")
	ui.inputs.task_ack()
	if e.queue.size() != 4:
		p.append("the inputs were not queued for the save (%d)" % e.queue.size())
	var why: String = ui.autosave.check(ui.autosave.payload())
	if why != "":
		p.append("a run saved with inputs queued is refused: %s" % why)
	main.free()


## A sink that notes the input and sends it on as a run alone does.
func _watch(item: Array, ui, seen: Array) -> void:
	seen.append(item)
	ui.inputs.sink = Callable()
	ui.inputs.send(item)
	ui.inputs.sink = _watch.bind(ui, seen)
