## Together (docs/plant3d/MULTIPLAYER.md, milestone MP2), in the app: the host's Together panel hosts a session of the
## first train's day shift and shows its code and QR code; a second player (the session layer headless, in this
## process, over the loopback) joins by the code and the host's address; both claim roles in the lobby and the host
## presses Start; both plants then run the same steps (the same state digests); an input of each reaches the other's
## plant; the bar's Pause pauses the session for both; the other player is drawn where its `pos` says; the host's
## End ends it for the joiner too, and the app's clock is its own again. A join link starts a join with its code.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Session = preload("res://net/session.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Udp = preload("res://net/udp.gd")
const Code = preload("res://net/code.gd")

var p: Array = []


static func _port() -> int:
	var u := PacketPeerUDP.new()
	u.bind(0, "127.0.0.1")
	var n := u.get_local_port()
	u.close()
	return n


func _wait(tree: SceneTree, cond: Callable, seconds: float) -> bool:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < seconds * 1000.0:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func run(tree: SceneTree) -> Array:
	var open0 := Udp.open_now
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	var disc := _port()
	ui.session_ports = [disc, _port()]
	ui.open_session()
	var why: String = ui.start_session(true, "shift_cold", "", "", {})
	if why != "":
		main.free()
		return ["the host's session did not start: " + why]
	var hs = ui.session
	if not ui.clock.engine.st_session or ui.clock.scenario != "shift_cold":
		p.append("the host's plant is not a session run of the day shift")
	await tree.process_frame
	ui.session_panel.refresh()
	var shown := App.texts(ui.session_panel)
	if not shown.contains(Code.pretty(hs.code)):
		p.append("the panel does not show the code in its groups")
	if ui.session_panel._qr_tex == null:
		p.append("the panel has no QR code")
	# the second player: the session layer alone, with its own clock
	var clock2 := SimClock.new()
	clock2.name = "clock2"
	tree.root.add_child(clock2)
	clock2.model = ui.model
	var s2 := Session.new()
	s2.name = "player2"
	s2.model = ui.model
	s2.clock = clock2
	s2.content = ui.autosave.content
	s2.display_name = "Second"
	s2.discovery_port = disc
	s2.my_pos = func(): return [Vector3(12.0, 0.0, -8.0), 0.5, 0.0, 14]
	tree.root.add_child(s2)
	why = s2.join(hs.code, "127.0.0.1:%d" % disc)
	if why != "":
		p.append("the join did not start: " + why)
	if not await _wait(tree, func(): return s2.state == Session.State.LOBBY and clock2.engine != null and not s2._loading, 20.0):
		p.append("the second player did not reach the lobby (state %d)" % s2.state)
		return _end(main, clock2, s2)
	if hs.roster.size() != 2 or not App.texts(ui.session_panel).contains("Second"):
		ui.session_panel.refresh()
		if not App.texts(ui.session_panel).contains("Second"):
			p.append("the host's panel does not list the second player")
	ui.take_role("a_sup")
	s2.claim("a_ccr1")
	await _wait(tree, func(): return hs.peers.has(1) and hs.peers[1].person == "a_ccr1", 5.0)
	ui.session_panel._sig = ""
	ui.session_panel.refresh()
	var start := App.find_button(ui.session_panel, "Start")
	if start == null:
		p.append("no Start button in the host's lobby")
		return _end(main, clock2, s2)
	start.pressed.emit()
	if not await _wait(tree, func(): return clock2.engine.step_no >= 60 and ui.clock.engine.step_no >= 60, 30.0):
		p.append("the run did not go on (host %d, player %d)" % [ui.clock.engine.step_no, clock2.engine.step_no])
		return _end(main, clock2, s2)
	if ui.clock.engine.trainee(0) == -1 or clock2.engine.trainee(1) == -1:
		p.append("the claims did not become the players' people (%d, %d)" % [ui.clock.engine.trainee(0), clock2.engine.trainee(1)])
	# the same steps: the digests at step 50 (both have run past it; recorded as they went)
	if ui.session._host_digests.get(50, [PackedByteArray()])[0] != _digest_at(clock2, 50):
		p.append("the two plants differ at step 50")
	# an input each way
	s2.send_input(["task_ack"])
	ui.inputs.task_ack()
	if not await _wait(tree, func(): return _has(ui.clock.engine, ["task_ack", 1]) and _has(clock2.engine, ["task_ack", 0]), 10.0):
		p.append("an input did not reach the other player's plant")
	# the other player in the plant
	if not await _wait(tree, func(): return ui.others != null and ui.others.shown.has(1), 5.0):
		p.append("the other player is not drawn")
	# the bar's Pause pauses the session for both
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	if not await _wait(tree, func(): return s2.paused and clock2.speed == SimClock.Speed.PAUSED, 5.0):
		p.append("the host's Pause did not pause the session for the player")
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	if not await _wait(tree, func(): return not s2.paused, 5.0):
		p.append("the host's 1× did not run the session again")
	# the host ends it
	ui.session_panel._sig = ""
	ui.session_panel.refresh()
	var end := App.find_button(ui.session_panel, "End the session")
	if end == null:
		p.append("no End button for the host")
	else:
		end.pressed.emit()
	if not await _wait(tree, func(): return s2.state == Session.State.ENDED and ui.session == null, 5.0):
		p.append("the host's End did not end the session for the player")
	elif not s2.why_ended.contains("host ended"):
		p.append("the player was told: " + s2.why_ended)
	if ui.clock.driven or ui.inputs.sink.is_valid():
		p.append("after the session the clock and the inputs are not the app's own again")
	# the player's own run again: a single-player run, slot 0, saved
	await _wait(tree, func(): return not ui.clock.engine.st_session, 5.0)
	if ui.clock.engine.st_session or ui.inputs.slot != 0 or not ui.autosave.armed:
		p.append("after the session the app is not back to a single-player run (session run %s, slot %d, saving %s)"
				% [str(ui.clock.engine.st_session), ui.inputs.slot, str(ui.autosave.armed)])
	# a join link starts a join with its code (no host answers here: it is cancelled)
	var code := Code.make()
	ui.handle_link("walkdown-plant://join/" + Code.pretty(code).to_lower())
	if ui.session == null or ui.session.code != code or ui.session.state != Session.State.FINDING:
		p.append("a join link did not start a join with its code")
	ui.end_session()
	return _end(main, clock2, s2, open0)


func _end(main, clock2, s2, open0 := -1) -> Array:
	if s2.active():
		s2.leave()
	s2.queue_free()
	clock2.queue_free()
	if main.ui.session != null and main.ui.session.active():
		main.ui.session.leave()
	main.free()
	if open0 >= 0 and Udp.open_now != open0:
		p.append("sockets left open: %d" % (Udp.open_now - open0))
	return p


static func _has(e, ev_tail: Array) -> bool:
	for ev in e.events:
		if ev.slice(1) == ev_tail:
			return true
	return false


func _digest_at(clock2, step: int) -> PackedByteArray:
	# the player's digest at that step: its engine replayed from its inputs (the same as it ran)
	var PlantEngine = load("res://sim/engine.gd")
	var e = PlantEngine.new(clock2.model, "shift_cold", true)
	var by := {}
	for it in clock2.engine.inputs:
		if not by.has(it[0]):
			by[it[0]] = []
		by[it[0]].append(it)
	while e.step_no < step:
		for it in by.get(e.step_no + 1, []):
			e.apply_input(it)
		e.step()
	return e.digest()
