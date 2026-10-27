## One player of the multi-instance harness (docs/plant3d/MULTIPLAYER.md §12): the engine and the session layer,
## headless, no rendering. Driven by a plan of actions; writes what it saw to a JSON file at the end.
##   godot --headless --path apps/plant3d --script res://net/tests/instance.gd -- --role=host|join --code=CODE
##     --data=DIR --scenario=ID --name=NAME --disc=PORT --port=PORT [--addr=IP:PORT] [--via=IP:PORT] [--speed=N]
##     --plan=FILE --out=FILE [--probe=1]
## The plan is a JSON array of actions, each {"t": seconds since the start (real time)} or {"step": the engine's
## step}, and optionally {"inputs_from": [slot, n]} (the host: wait until n inputs of that slot are committed) and
## {"after": seconds since the action before it ran}, and "do": input (item), claim (person), ready, start, pause, run, fast (on), jump (hhmm), instructor (slot,
## on), away (on), desync (a value of the engine changed), leave, quit. On quit (or when the session ends) it writes
## --out: its slot, its step, every 50th step's state digest, its events' hash and count, the input-to-effect delays,
## its session statistics and (the host) every commit.
extends SceneTree

const Session = preload("res://net/session.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const RunSave = preload("res://ui/run_save.gd")
const JsonStrict = preload("res://sim/json_strict.gd")
const Udp = preload("res://net/udp.gd")

var opts := {}
var session
var clock
var model
var plan: Array = []
var t0 := 0
var digests := {}
var done := false
var walk_a := 0.0
var notices: Array = []
var _printed := false
var _last_done := 0.0   # when the last action ran (s since the start)
var early := 0          # actions done before the session's welcome (the player still finding or joining it)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	Engine.time_scale = float(opts.get("speed", "1"))
	model = PlantModel.from_dir(opts["data"])
	if model.error != "":
		printerr("model: ", model.error)
		quit(2)
		return
	var r := JsonStrict.parse_text(FileAccess.get_file_as_string(opts["plan"]) if opts.has("plan") else "[]")
	plan = r["value"] if r.get("ok", false) else []
	clock = SimClock.new()
	clock.name = "clock"
	root.add_child(clock)
	clock.model = model
	clock.scenario = opts.get("scenario", "cold_iron")
	clock.stepped.connect(_on_step)
	session = Session.new()
	session.name = "session"
	session.model = model
	session.clock = clock
	session.content = RunSave.content_hash(opts["data"])
	session.display_name = opts.get("name", "P")
	session.discovery_port = int(opts.get("disc", str(Session.DISCOVERY_PORT)))
	session.session_port = int(opts.get("port", "0"))
	session.bind_address = "127.0.0.1" if opts.get("local", "1") == "1" else "*"
	session.via = opts.get("via", "")
	session.log_commits = true
	session.probe_sched = opts.get("probe", "") == "1"   # the layer's slow frames' thread time (stats "slow")
	session.my_pos = _walker
	session.notice.connect(func(t): notices.append(t))
	session.ended.connect(func(_w): _finish())
	root.add_child(session)
	t0 = Time.get_ticks_msec()
	var err := ""
	if opts.get("role", "host") == "host":
		err = session.host(clock.scenario, {}, opts.get("code", ""))
	else:
		err = session.join(opts["code"], opts.get("addr", ""))
	if err != "":
		printerr("session: ", err)
		quit(3)
		return
	print("READY %d %d" % [session._udp.port, session._disc.port if session._disc != null else 0])


func _walker() -> Array:
	walk_a += 0.05
	return [Vector3(cos(walk_a) * 5.0, 0.0, sin(walk_a) * 5.0), walk_a, 0.1, 1]


func _on_step(e) -> void:
	if e.step_no % 50 == 0:
		digests[str(e.step_no)] = e.digest().hex_encode()


func _process(_delta: float) -> bool:
	if done:
		return true
	var now := (Time.get_ticks_msec() - t0) / 1000.0
	var step: int = clock.engine.step_no if clock.engine != null else -1
	while not plan.is_empty():
		var a: Dictionary = plan[0]
		if a.has("t") and now < float(a["t"]):
			break
		if a.has("step") and step < int(a["step"]):
			break
		if a.has("inputs_from") and _committed_from(int(a["inputs_from"][0])) < int(a["inputs_from"][1]):
			break
		if a.has("after") and now < _last_done + float(a["after"]):
			break
		plan.pop_front()
		_last_done = now
		_do(a)
		if done:
			return true
	return false


## The inputs of `slot` committed so far (the host's commit log).
func _committed_from(slot: int) -> int:
	var n := 0
	for c in session.commit_log:
		for x in c[2]:
			if int(x[0]) == slot:
				n += 1
	return n


func _do(a: Dictionary) -> void:
	if session.state == Session.State.FINDING or session.state == Session.State.JOINING:
		early += 1
	match a["do"]:
		"input":
			session.send_input(a["item"])
		"claim":
			session.claim(a["person"])
		"ready":
			session.set_ready(true)
		"start":
			var w: String = session.start()
			if w != "":
				printerr("start: ", w)
		"pause":
			session.request_pause()
		"run":
			session.request_run()
		"fast":
			session.vote_fast(a.get("on", true))
		"cap":
			clock.cpu_share = float(a["share"])         # (a slower device: a lower fast-forward cap)
		"jump":
			session.vote_jump(a["hhmm"])
		"instructor":
			session.set_instructor(int(a["slot"]), a.get("on", true))
		"away":
			session.set_away(a.get("on", true))
			if a.has("freeze"):
				# Android's background: the main loop stops (§7.5); nothing of the session runs until it is back
				session.set_process(false)
				create_timer(float(a["freeze"]), true, false, true).timeout.connect(func():
					session.set_process(true)
					session.set_away(false))
		"desync":
			clock.engine.cur[int(a.get("value", 0))] += 1.0
			clock.engine.prev[int(a.get("value", 0))] += 1.0
		"leave":
			session.leave()
		"quit":
			_finish()


func _finish() -> void:
	if done:
		return
	done = true
	var e = clock.engine
	var out := {
		"role": opts.get("role", "host"), "name": opts.get("name", ""), "slot": session.slot,
		"step": e.step_no if e != null else -1, "digests": digests,
		"events": e.events.size() if e != null else 0,
		"events_sha": _sha(var_to_bytes(e.events)) if e != null else "",
		"inputs": e.inputs.size() if e != null else 0,
		"digest": e.digest().hex_encode() if e != null else "",
		"delays": session.stats["delays"], "stats": _plain_stats(), "why_ended": session.why_ended,
		"rsa_ms": session.rsa_ms, "roster": session.roster, "notices": notices, "report": session.last_report,
		"positions": session.positions.keys(), "commits": session.commit_log if session.is_host() else [],
		"scenario": session.scenario, "buffer": session.buffer_turns(), "sending": session.sending(),
		"trainees": _trainees(e), "pss_kb": _pss(), "udp": [Udp.opened, Udp.open_now],
		"ff_cap": clock.ff_cap(), "load_ms": session.stats.get("load_ms", -1.0), "early": early,
	}
	var f := FileAccess.open(opts["out"], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	session.close()


func _trainees(e) -> Array:
	var out := []
	if e == null:
		return out
	for s in 8:
		out.append(e.trainee(s))
	return out


func _plain_stats() -> Dictionary:
	var s: Dictionary = session.stats.duplicate()
	s.erase("delays")
	return s


static func _sha(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()


static func _pss() -> int:
	var f := FileAccess.open("/proc/self/smaps_rollup", FileAccess.READ)
	if f == null:
		return -1
	while true:
		var line := f.get_line()
		if line.begins_with("Pss:"):
			return line.split(":")[1].strip_edges().split(" ")[0].to_int()
		if f.eof_reached() or f.get_error() != OK:
			return -1
	return -1
