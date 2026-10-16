## The engine's clock in the app (docs/PLANT3D.md §7.9, decision 0054 §10): 1× runs ten 0.1 s steps a second
## whatever the frame rate; fast-forward is capped so that the model takes at most a quarter of a core from the
## measured cost of a step (the Note 9's 1.4 ms gives about 18×); it is refused while an alarm is unacknowledged and
## stops by itself when one comes up; pause stops the plant.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	var c = ui.clock
	c.step_ms = 1.4
	if absf(c.ff_cap() - 250.0 / 1.4 * 0.1) > 1e-9:
		p.append("the cap for 1.4 ms a step is %.2f×, not %.2f×" % [c.ff_cap(), 250.0 / 1.4 * 0.1])
	c.step_ms = 0.28
	if c.ff_cap() != 60.0:
		p.append("a laptop's cap is %.1f×, not the format's 60×" % c.ff_cap())
	# 1×: 3 s of frames at 30 fps give 30 steps
	c.set_speed(SimClock.Speed.NORMAL)
	var s0: int = c.engine.step_no
	for i in 90:
		c._process(1.0 / 30.0)
	if c.engine.step_no - s0 != 30:
		p.append("3 s at 1× ran %d steps, not 30" % (c.engine.step_no - s0))
	# fast-forward within a quarter of a core: each frame's steps cost at most a quarter of the frame
	c.set_speed(SimClock.Speed.FAST)
	if c.speed != SimClock.Speed.FAST:
		p.append("fast-forward refused at cold iron: %s" % c.ff_blocked())
	var t0 := Time.get_ticks_usec()
	var s1: int = c.engine.step_no
	for i in 60:
		c._process(1.0 / 60.0)
	var spent := (Time.get_ticks_usec() - t0) / 1e6
	var steps: int = c.engine.step_no - s1
	if steps <= 60:
		p.append("fast-forward ran %d steps in a second of frames" % steps)
	if steps > ceili(c.ff_rate() * 10.0) + 1:
		p.append("fast-forward ran %d steps, more than its rate %.1f× allows" % [steps, c.ff_rate()])
	print("  fast-forward: %d steps for 1 s of frames, %.0f ms of model time on this machine, cap %.0f×" % [steps, spent * 1000.0, c.ff_cap()])
	# the budget: with a step said to cost 4 ms, a 60 fps frame (16.7 ms) may run one step (a quarter is 4.2 ms)
	c.step_ms = 4.0
	var s2: int = c.engine.step_no
	c.acc = 0.0
	c._process(1.0 / 60.0)
	if c.engine.step_no - s2 > 1:
		p.append("a frame ran %d steps of 4 ms, over a quarter of its time" % (c.engine.step_no - s2))
	c.step_ms = 0.3
	# fast-forward stops by itself when an alarm comes up: closed cooling water pump A runs, then its motor fails
	c.set_speed(SimClock.Speed.PAUSED)
	ui.go_control_room()
	ui.open_card("00PGC10AP001")
	(App.op_row(ui.card, "00PGC10AP001", "start")[1] as Button).pressed.emit()
	App.run_until(ui, "ccw_flow_ok", 2000)
	c.engine.fault("ccw_a_motor")
	c.set_speed(SimClock.Speed.FAST)
	for i in 200:
		if c.speed != SimClock.Speed.FAST:
			break
		c._process(1.0 / 60.0)
	if c.speed != SimClock.Speed.NORMAL:
		p.append("fast-forward did not stop when the pump's alarm came up")
	elif c.engine.fast_forward():
		p.append("fast-forward stopped while the engine still allowed it")
	c.set_speed(SimClock.Speed.FAST)
	if c.speed == SimClock.Speed.FAST:
		p.append("fast-forward was taken with an alarm unacknowledged")
	# a hold at 1× (a procedure step done, no pause): the steps not run that frame come in the next
	ui.restart("cold_iron")
	c.set_speed(SimClock.Speed.NORMAL)
	var held := [false]
	var hold_once := func(_e):
		if not held[0]:
			held[0] = true
			c.hold = true
	c.stepped.connect(hold_once)
	var s4: int = c.engine.step_no
	c.acc = 0.0
	c._process(0.25)          # two steps due (a frame counts at most 0.25 s), held after the first
	c._process(1.0 / 60.0)
	c.stepped.disconnect(hold_once)
	if c.engine.step_no - s4 != 2:
		p.append("0.27 s at 1× with a hold after the first step ran %d steps, not 2" % (c.engine.step_no - s4))
	# a procedure step without `done` ends with Next, but only after one model step (as sim/procedure.gd)
	var Tracker = load("res://ui/procedure_tracker.gd")
	var tr = Tracker.new()
	tr.begin({"kind": "procedure", "steps": [{"id": "a", "text": ["A"]}, {"id": "b", "text": ["B"]}]}, c.engine)
	if tr.can_next(c.engine):
		p.append("Next is offered before the plant has run a step")
	c.run_steps(1)
	tr.next(c.engine)
	if tr.log != [["a", c.engine.step_no]] or tr.index != 1:
		p.append("Next after a step logged %s" % str(tr.log))
	# operations sent before a procedure began are not judged by it; one of the next step's, sent with the last of this
	# one, counts for the next step; two entries of one code told apart by their values
	var proc := {"kind": "procedure", "steps": [
		{"id": "a", "text": ["A"], "do": [{"kks": "00QFA10AN001", "do": "start"}], "done": "ia_a_cmd"},
		{"id": "b", "text": ["B"], "do": [{"kks": "30PAC10AA101", "do": "set", "value": 0.3},
			{"kks": "30PAC10AA101", "do": "set", "value": 0.15}], "done": "cw_a_vstart"}]}
	c.set_speed(SimClock.Speed.PAUSED)
	ui.restart("cold_iron")
	c.set_speed(SimClock.Speed.PAUSED)
	c.engine.op("00PGC10AP001", "start")          # before the procedure
	var t2 = Tracker.new()
	t2.begin(proc, c.engine)
	c.engine.op("00QFA10AN001", "start")          # step a's
	c.engine.op("30PAC10AA101", "set", 0.15)      # step b's, in the same model step as a's done
	c.run_steps(1)
	t2.on_step(c.engine)
	if not t2.deviations.is_empty():
		p.append("operations before the procedure or of its next step counted as deviations: %s" % str(t2.deviations))
	if t2.index != 1 or not t2.is_done_op(proc["steps"][1]["do"][1]) or t2.is_done_op(proc["steps"][1]["do"][0]):
		p.append("the next step's 15 %% was not ticked on its own entry (step %d)" % t2.index)
	# pause
	c.set_speed(SimClock.Speed.PAUSED)
	var s3: int = c.engine.step_no
	for i in 30:
		c._process(0.1)
	if c.engine.step_no != s3:
		p.append("the plant ran while paused")
	main.free()
	return p
