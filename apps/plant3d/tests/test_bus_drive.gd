## The driver who steers (docs/PLANT3D.md §21.16; app/bus_drive.gd):
## - the trainee as the day's bus driver: taken into the bus at the 05:40 run, the app takes the wheel ("wheel"), the
##   walker at the driver's seat; the app's driver (the drive walk's pilot) drives on its lane to the camp's stop, opens
##   the doors there ("stop": the engine's arrival, the riders on), leaves at 05:40 ("go"), and on to the next stop;
##   the bus is drawn where the app drives it, off the engine's way;
## - the automatic brake for someone ahead, and a solid ahead stops it dead;
## - the wheel given to the engine ("auto"): the engine drives it again;
## - the debrief's role tab and summary, the saved run's drive log, the session's `pos` while driving.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const BusDrive = preload("res://app/bus_drive.gd")
const Session = preload("res://net/session.gd")
const Autosave = preload("res://ui/autosave.gd")
const Debrief = preload("res://ui/debrief.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += _pos_flag()
	p += _saved_log()
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return p + ["the app or its scenario with the crews (shift_cold) did not start"]
	ui.start_shift("shift_cold")
	await tree.process_frame
	var e = ui.clock.engine
	var sm = e._sm
	var drv := ""
	for pi in sm.people.size():
		if sm.people[pi]["role"] == sm.vehicles[0]["driver"] and e.sp_on[pi]:
			drv = String(sm.people[pi]["id"])
			break
	if drv == "":
		main.free()
		return p + ["no bus driver on duty at the shift's start"]
	if main._day_driver() != drv:
		p.append("the drive walk would play %s, not the driver on duty %s" % [main._day_driver(), drv])
	ui.take_role(drv)
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var me: int = e.trainee()
	var bd = ui.bus_drive
	var vv = ui.vehicles
	var V: Dictionary = vv.vehicles[0]
	var vi: int = V["vi"]
	# to the 05:40 run: the driver taken into the bus, then the app takes the wheel
	for i in 600:
		if e.sp_aboard[me] == vi:
			break
		ui.clock.run_steps(10)
	if e.sp_aboard[me] != vi:
		main.free()
		return p + ["the trainee driver was never taken into the bus (%s)" % ui.clock_text()]
	bd._physics_process(1.0 / 30.0)
	ui.clock.run_steps(1)
	if not e.st_veh[vi].has("wheel"):
		p.append("the app did not take the wheel: %s" % str(e.events.filter(func(x): return x[1] == "drive")))
	bd._physics_process(1.0 / 30.0)
	if bd.vi != vi or not ui.player.driving:
		p.append("at the wheel, the app does not drive the bus (vi %d)" % bd.vi)
	vv._physics_process(1.0 / 30.0)
	var seat: Vector3 = vv.global_transform * (bd.xf * bd.seat)
	if ui.player.global_position.distance_to(seat) > 0.05:
		p.append("the walker is not at the driver's seat (%.2f m from it)" % ui.player.global_position.distance_to(seat))
	# the pilot drives to the camp's stop and opens the doors there; the run leaves at 05:40
	bd.pilot = true
	var arrived := -1
	var left := -1
	var second := -1
	var far := 0.0
	var start: Vector3 = bd.xf.origin
	for i in 6000:
		for k in 3:
			bd._physics_process(1.0 / 30.0)
		vv._physics_process(1.0 / 30.0)
		ui.clock.run_steps(1)
		far = maxf(far, bd.xf.origin.distance_to(start))
		for x in e.events.slice(maxi(0, e.events.size() - 12)):
			if x[0] != e.step_no or x[1] != "vehicle" or x[2] != sm.vehicles[vi]["id"]:
				continue
			if x[4] == "arrive" and arrived == -1:
				arrived = e.step_no
			elif x[4] == "depart" and arrived != -1 and left == -1:
				left = e.step_no
			elif x[4] == "arrive" and left != -1 and second == -1:
				second = e.step_no
		if second != -1:
			break
		if i % 30 == 0:
			await tree.process_frame
	var drives: Array = e.events.filter(func(x): return x[1] == "drive" and x[2] == drv)
	if arrived == -1:
		main.free()
		return p + ["the app's driver never stopped at the first stop (moved %.0f m; at %s; inputs %s)" % [far,
				str(bd.xf.origin), str(drives).left(400)]]
	if not drives.any(func(x): return x[4] == "stop" and x[6] == "done"):
		p.append("no stop input made the arrival: %s" % str(drives).left(300))
	if left == -1:
		p.append("the bus never left its first stop")
	if second == -1 and bd.blocked_by != "":     # (what it ran into, to see why)
		var dn = tree.root.get_node_or_null(NodePath(bd.blocked_by))
		var info := "%s %s at %s groups %s" % [dn.get_class(), dn.name, str(dn.global_position), str(dn.get_groups())]
		for c in dn.find_children("*", "CollisionShape3D", true, false):
			info += " shape %s at %s" % [str(c.shape), str(c.global_position)]
			if c.shape is BoxShape3D:
				info += " size %s" % str(c.shape.size)
		var bx: Transform3D = vv.global_transform * bd.xf
		info += " | bus at %s fwd %s front %.1f back %.1f halfw %.1f" % [str(bx.origin), str(-bx.basis.z), bd.front, bd.back, bd.half_w]
		var bodyn: Node3D = V["body"]
		for c in bodyn.find_children("*", "CollisionShape3D", true, false):
			info += " busshape %s at %s" % [str(c.shape), str(c.global_position)]
			if c.shape is BoxShape3D:
				info += " size %s" % str(c.shape.size)
		p.append("what stopped the bus: " + info)
	if second == -1:
		p.append("the app's driver never reached the run's second stop (moved %.0f m, at %s, speed %.2f, blocked %d by %s, near %d, the stop %.1f m away, %s)" % [far,
				str(bd.xf.origin), bd.speed, bd.blocked, bd.blocked_by, bd._near,
				vv.place_xz(e.st_veh[vi]["to"]).distance_to(bd.xf.origin), str(e.st_veh[vi]).left(200)])
	if bd.log.is_empty() or bd.log[-1]["stops"].size() < 1:
		p.append("the run driven is not in the drive log: %s" % str(bd.log))
	# while it drove, the bus was drawn where the app had it
	if not (V["xf"] as Transform3D).is_equal_approx(bd.xf):
		p.append("the steered bus is not drawn where the app drives it")
	# the automatic brake: someone just ahead of the moving bus stops it
	var steered: bool = e.st_veh[vi].has("wheel") and e.st_veh[vi]["at"] == -1
	if steered:
		bd.control = Vector3(1, 0, 0)
		for k in 60:
			bd._physics_process(1.0 / 30.0)
		var ahead: Vector3 = vv.global_transform * (bd.xf * Vector3(0, 1, bd.front - 3.0))
		bd.extra_people = [ahead]
		var near0: int = bd.log[-1]["near_misses"]
		for k in 90:
			bd._physics_process(1.0 / 30.0)
		if absf(bd.speed) > 0.01 or not bd.braking:
			p.append("someone ahead and the bus did not stop (%.2f m/s)" % bd.speed)
		if bd.log[-1]["near_misses"] < near0 + 1:      # (at least: the crews' people on the road may add theirs)
			p.append("the brake above 2 m/s is not a near miss")
		var hold: Vector3 = bd.xf.origin
		for k in 30:
			bd._physics_process(1.0 / 30.0)
		if bd.xf.origin.distance_to(hold) > 0.01:
			p.append("the bus crept on towards someone ahead")
		bd.extra_people = []
		# a solid ahead stops it dead
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8, 4, 0.5)
		cs.shape = box
		wall.add_child(cs)
		main.add_child(wall)
		wall.global_transform = Transform3D(vv.global_transform.basis * bd.xf.basis,
				vv.global_transform * (bd.xf * Vector3(0, 2, bd.front - 4.0)))
		await tree.physics_frame        # (in the physics space from its next step)
		await tree.physics_frame
		for k in 240:
			bd._physics_process(1.0 / 30.0)
		var l: Vector3 = (vv.global_transform * bd.xf).affine_inverse() * wall.global_position
		if l.z > bd.front - 0.15 or absf(bd.speed) > 0.01:     # (the wall's middle 0.25 m in: its face at the front)
			p.append("the bus went into a wall ahead (its front at %.2f, the wall at %.2f)" % [bd.front, l.z])
		wall.free()
		bd.control = null
	# the wheel to the engine and back
	bd.pilot = false
	bd.toggle_wheel()
	ui.clock.run_steps(1)
	if e.st_veh[vi].has("wheel"):
		p.append("the wheel button did not give the engine the wheel")
	bd._physics_process(1.0 / 30.0)
	if bd.vi != -1 or ui.player.driving:
		p.append("with the engine at the wheel the app still drives")
	# the debrief: the drives in the role tab, the runs in the summary
	var d: Dictionary = Debrief.collect(e, ui.info, null, ui.inputs.slot, ui.task_given, bd.log)
	var rows: Array = d.entries.filter(func(x): return x.kind == "drive")
	if rows.is_empty() or not rows.any(func(x): return String(x.text).contains("opened the doors")):
		p.append("the debrief lists no drive of the trainee's: %s" % str(rows).left(300))
	if not "\n".join(Debrief.summary_lines(d)).contains("Bus runs you drove: 1"):
		p.append("the debrief's summary has no bus run: %s" % "\n".join(Debrief.summary_lines(d)))
	main.free()
	return p


## `pos` while driving: the flag and the vehicle, read back by another player (MULTIPLAYER.md §6.3).
static func _pos_flag() -> Array:
	var p: Array = []
	var f := Session.pos_fields(9, Vector3(1, 2, 3), 0.5, 0.0, 30, Session.POS_DRIVING, 3)
	if f.size() != 24 or f[21] != Session.POS_DRIVING or f[22] != 3:
		p.append("pos while driving carries the flag and the vehicle (%d, %d)" % [f[21], f[22]])
	if Session.pos_fields(9, Vector3.ZERO, 0, 0, 0, 0, 3)[22] != 0:
		p.append("pos without the driving flag sends no vehicle")
	var s = Session.new()
	s.slot = 0
	s._on_pos(2, f)
	s._now = s._now + 1.0
	if s.driving_of(2, 3).is_empty() or not s.driving_of(2, 1).is_empty():
		p.append("another player's driving is read from their pos (vehicle 3 only)")
	s._on_pos(2, Session.pos_fields(10, Vector3(1, 2, 3), 0.5, 0.0, 30))
	if not s.driving_of(2, 3).is_empty():
		p.append("a pos without the flag ends it")
	s.free()
	return p


## The saved run's drive log: checked as the other panels' state is.
static func _saved_log() -> Array:
	var p: Array = []
	var good := {"results": {}, "pending": [], "task_given": {}, "drive_log": [{"vehicle": "bus_1", "dep": 20400,
			"stops": [["camp_stop", "arrive", 2], ["gate_stop", "passed", null]], "off_route_s": 1.5, "near_misses": 0}]}
	if not Autosave._ui_contents(good):
		p.append("a saved drive log is refused")
	var bad: Dictionary = good.duplicate(true)
	bad["drive_log"][0]["stops"][0][1] = "teleported"
	if Autosave._ui_contents(bad):
		p.append("a damaged drive log is taken")
	return p
