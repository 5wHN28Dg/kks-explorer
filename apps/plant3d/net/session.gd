## A multiplayer session on the LAN (docs/plant3d/MULTIPLAYER.md, milestone MP2; decisions 0067, 0068): the host
## orders every player's inputs into commits of turns, and every player runs the same engine through the same commits
## (lockstep, §3). This node is the whole session layer: the invite code's keys, the packets and their streams, the
## LAN query and the join, the lobby and its claims, the commits and the jitter buffer, the state digests and the
## resync by snapshot, late join and rejoin, pause, fast-forward by everyone's vote, the jump vote, the instructor
## seats, the players' positions, and the host's and the players' saved sessions.
##
## It drives the run's clock (ui/sim_clock.gd, `driven`): the clock no longer steps by itself, the session runs each
## committed step through it (so everything that follows a step in the app follows it here too). It needs no UI: the
## multi-instance harness (net/tests/) runs it headless.
##
## Not in MP2 (later milestones): host migration and removal with new keys (MP3), the relay and direct UDP (MP4),
## voice (MP5).
extends Node

const Crypt = preload("res://net/crypto.gd")
const Code = preload("res://net/code.gd")
const Wire = preload("res://net/wire.gd")
const Stream = preload("res://net/stream.gd")
const Udp = preload("res://net/udp.gd")
const InputCheck = preload("res://net/input_check.gd")
const Snapshot = preload("res://net/snapshot.gd")
const RunSave = preload("res://ui/run_save.gd")
const JsonStrict = preload("res://sim/json_strict.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const DISCOVERY_PORT := 47820
const SLOTS := 8
const HOST_SLOT := 0
const TURN := 2                 # steps a turn closes at 1× (§3.1)
const TURN_S := 0.2             # real seconds a turn is at most
const MAX_BUFFER := 5           # turns of jitter buffer, at most
const SEND_EVERY := 0.05        # s: acknowledgements and new messages go out at least this often
const POS_EVERY := 0.2          # s: 5 Hz (§6.3)
const PING_EVERY := 1.0
const SILENT_S := 10.0          # no packet: disconnected (§2.4)
const RELEASE_S := 60.0         # disconnected this long: their person to the NPCs
const AWAY_S := 120.0           # a player gone to the background keeps their person this long (§7.5)
const DIGEST_EVERY := 50        # steps × the stride (§4)
const KEEP_DIGESTS_S := 180.0
const SNAP_EVERY_S := 2.0       # a host takes at most one snapshot per 2 s (§5.1)
const RESYNC_LIMIT_S := 600.0   # twice desynced within 10 minutes: an observer (§4)
const OBSERVER_SNAP_S := 30.0
const HELLO_EVERY := 0.5
const QUERY_EVERY := 0.25
const QUERY_FOR := 2.0
const FF_MAX := 60.0
const SNAP_RELAY_LIMIT := 128 * 1024
const MAX_REPLAY := 256                 # replay windows kept at most (8 slots, their incarnations over a session)
const JUDGE_S := 3.0                    # a step's reports judged when all are in, or this long after the host's digest
const NEVER_JOINED_S := 15.0            # a hello never followed by its player's packets: its slot is given again
const FORWARD_RATE := 40.0              # a player's broadcasts the host forwards a second (positions 5, voice 25: MP5)
const FORWARD_BURST := 80.0

enum Role { NONE, HOST, PLAYER }
enum State { IDLE, FINDING, JOINING, LOBBY, RUN, ENDED }

signal changed                          # the roster, the state or the session's speed changed
signal notice(text: String)             # something to show the player
signal engine_replaced(engine)          # a snapshot was loaded (a join, a rejoin, a resync)
signal ended(why: String)

# ------------------------------------------------------------------ set up by whoever starts the session

var model                               # sim/plant_model.gd
var clock                               # ui/sim_clock.gd (driven by this node)
var content := ""                       # the content's hash (RunSave.content_hash)
var display_name := "Player"
var discovery_port := DISCOVERY_PORT    # the harness gives every instance its own
var session_port := 0                   # 0: any free one
var bind_address := "*"
var log_commits := false               # keep every commit (the harness compares players with one engine fed them)
var commit_log: Array = []
var via := ""                           # the harness's network simulator: session traffic to this "ip:port"
var install_engine := Callable()        # f(engine): the app takes a session's engine (ui/plant_ui.gd adopt_engine);
                                        # unset, the clock alone (the harness)
var my_pos := Callable()                # f() -> [Vector3, yaw, pitch, gait]: the walker, for `pos`

# ------------------------------------------------------------------ the session

var role := Role.NONE
var state := State.IDLE
var code := ""
var keys := {}
var epoch := 1
var incarnation := 0
var slot := -1
var scenario := ""
var paused := false
var paused_by := -1
var fast := false                       # the session is in fast-forward
var rate := 1.0                         # the session's rate (1, or the fast-forward rate)
var why_ended := ""
var final := false                      # ended for good (left, ended by the host, refused): its rejoin token goes too
var roster := []                        # [{slot, name, person, connected, away, ready, fast, desync, observer, instructor, host}]
var settings := {"instructors": []}     # (nothing in them is secret from the players)
var ff_choice := FF_MAX                 # the host's own choice of fast-forward rate

var _rsa: CryptoKey                     # this process's RSA key (§1.3), made once
var _rsa_thread: Thread
var rsa_ms := -1.0                      # its generation's time (measured on the Note 9, §13)
var _udp: Udp
var _disc: Udp                          # the host's discovery socket; a joiner's query socket
var _now := 0.0
var _send_t := 0.0
var _pos_t := 0.0
var _ping_t := 0.0
var _knum := 0                          # packets sent under K
var _replay := {}                       # "from:inc:key" -> Wire.Replay

# the host's
var peers := {}                         # slot -> Peer
var _by_inc := {}                       # incarnation -> slot
var _next_slot := 1
var _free_slots: Array = []             # slots whose hello was never followed by the player (given again)
var _judged := {}                       # steps whose reports were judged
var _inbox: Array = []                  # [slot, number, text] for the next turn, in the order received
var _bseq := 1                          # the broadcast stream's next sequence
var _turn_open := false
var _turn_first := 0
var _turn_t := 0.0
var _turn_inputs: Array = []            # [slot, number, text] applied at _turn_first
var _acc := 0.0
var _host_digests := {}                 # step -> [digest, time]
var _reported := {}                     # step -> {slot: digest}
var _snap_cache := {}                   # {step, raw_len, z, t} (one snapshot per 2 s)
var _snap_jobs := {}                    # task id -> [slots, Dictionary, result]
var _jump_votes := {}                   # slot -> hhmm
var _own_number := 0
var _away_host := false

# the player's
var host_ip := ""
var host_port := 0
var _p := PackedByteArray()
var _pnum := 0
var _token := PackedByteArray()
var _send_p: Stream.Sender
var _recv_b: Stream.Receiver
var _recv_p: Stream.Receiver
var _recv_snap: Stream.Receiver
var _commits := {}                      # first step -> commit {first, last, stride, rate, inputs}
var committed := 0                      # the highest step committed (the host's: its engine's)
var _next_input := 1
var _unsent: Array = []                 # inputs made before the welcome
var _mine := {}                         # input number -> [text, time made]
var _query_until := 0.0
var _query_t := 0.0
var _query_rand := PackedByteArray()
var _query_to := ""                     # a typed address, or "" for broadcasts
var _hello_t := 0.0
var _hello_json := PackedByteArray()
var _buffer := 1                        # turns
var _late_t := -1000.0
var _loading := false                   # a snapshot is being loaded
var _resyncs: Array = []
var observer := false
var _host_last_rx := 0.0
var _away := false

# what the session measured (the harness and the phone)
var stats := {"delays": [], "us": 0, "us_max": 0, "us_sum": 0, "frames": 0, "desyncs": 0, "resyncs": 0,
		"snap_ms": 0.0, "dropped": 0, "rtt": -1.0}

# other players' positions: slot -> [[t, Vector3, yaw, pitch, gait], …] (the last few)
var positions := {}


class Peer:
	var slot := 0
	var name := ""
	var ip := ""
	var port := 0
	var inc := 0
	var p := PackedByteArray()
	var token_hash := PackedByteArray()
	var connected := true
	var last_rx := 0.0
	var gone_t := -1.0                  # when it went silent or left
	var away := false
	var away_t := 0.0
	var person := ""                    # the person claimed (lobby) or played
	var released := false               # their person was handed to the NPCs
	var ready := false
	var fast := false
	var ff_cap := FF_MAX
	var at := 0                         # its engine's step, from its pings
	var desync := false
	var observer := false
	var observer_t := 0.0
	var resyncs: Array = []
	var pnum := 0
	var committed_no := 0               # its highest input number committed
	var send_p
	var snap
	var bsend
	var recv_p
	var welcome := PackedByteArray()    # the welcome's fields (repeated to a repeated hello)
	var token := PackedByteArray()      # the rejoin token it was given (§5.2)
	var rsa_pem := ""                   # the public key of its hello (a repeated hello is answered only for it)
	var turn_count := 0
	var turn_bytes := 0
	var fwd_tokens := FORWARD_BURST       # the broadcasts the host still forwards for it now (a token bucket)
	var fwd_t := 0.0
	var loading := false
	var joined := false                 # it has sent a packet under its P (a hello alone can be anyone's with K)
	var hello_t := 0.0


func _init() -> void:
	incarnation = Crypt.u32(Crypt.random_bytes(4), 0)
	if incarnation == 0:
		incarnation = 1


# ================================================================== starting and ending

## Makes this process's RSA key on a worker thread (§1.3: when the join or host screen opens).
static var _proc_rsa: CryptoKey          # this process's RSA key, made once (§1.3)
static var _proc_rsa_ms := -1.0


func prepare_key() -> void:
	if _rsa == null and _proc_rsa != null:
		_rsa = _proc_rsa
		rsa_ms = _proc_rsa_ms
	if _rsa != null or _rsa_thread != null:
		return
	_rsa_thread = Thread.new()
	_rsa_thread.start(_make_rsa)


func _make_rsa() -> Array:
	var t0 := Time.get_ticks_usec()
	var k := Crypt.crypto().generate_rsa(2048)
	return [k, (Time.get_ticks_usec() - t0) / 1000.0]


func _key_ready() -> bool:
	if _rsa != null:
		return true
	if _rsa_thread == null:
		prepare_key()
	if _rsa_thread.is_alive():
		return false
	var r: Array = _rsa_thread.wait_to_finish()
	_rsa_thread = null
	_rsa = r[0]
	rsa_ms = r[1]
	_proc_rsa = _rsa
	_proc_rsa_ms = rsa_ms
	return true


## Hosts a new session of `scenario_id` (or of a saved session's snapshot, `from_save`). Returns "" or why not.
func host(scenario_id: String, from_save := {}, with_code := "") -> String:
	if role != Role.NONE:
		return "a session is open already"
	code = with_code if with_code != "" else Code.make()
	keys = Code.keys(code)
	_udp = Udp.new()
	if _udp.open(session_port, bind_address) != OK:
		return _fail_open("the session's port %d is taken" % session_port)
	_disc = Udp.new()
	if _disc.open(discovery_port, "0.0.0.0") != OK:
		# another session on this machine holds the discovery port: joiners type this one's address (§9.3)
		_disc = null
		notice.emit("Another session on this device answers the LAN's queries: players join this one by its address.")
	role = Role.HOST
	slot = HOST_SLOT
	scenario = scenario_id
	clock.driven = true
	if not from_save.is_empty():
		var bad := Snapshot.check(from_save, model, content)
		if bad != "":
			close()
			return "the saved session can't be continued: " + bad
		scenario = from_save["scenario"]
		_install(_build(from_save, scenario))
		state = State.LOBBY
		_reclaimable = _people_of(from_save)
		_continued = true
	else:
		_install(_build({}, scenario))
		state = State.LOBBY
	committed = clock.engine.step_no
	_roster_changed()
	return ""


var _reclaimable := {}                  # a continued session: name -> person, offered again in the lobby (§7.4)
var _continued := false                 # the session continues a saved one: joiners get its snapshot in the lobby too


func _people_of(d: Dictionary) -> Dictionary:
	var out := {}
	for r in d["session"].get("roster", []):
		if typeof(r) == TYPE_DICTIONARY and typeof(r.get("name")) == TYPE_STRING and typeof(r.get("person")) == TYPE_STRING \
				and r["person"] != "":
			out[r["name"]] = r["person"]
	return out


func _fail_open(why: String) -> String:
	close()
	return why


## Joins the session of a code (typed, or from a link): first a LAN query (§9.3), to `address` ("ip" or "ip:port" of
## its discovery socket) when given, else to the broadcast addresses. Returns "" or why not.
func join(code_text: String, address := "") -> String:
	if role != Role.NONE:
		return "a session is open already"
	code = Code.normalize(code_text)
	if code == "":
		return "that is not a session code (a character is wrong or missing)"
	keys = Code.keys(code)
	_udp = Udp.new()
	if _udp.open(session_port, bind_address) != OK:
		return _fail_open("no port for the session")
	_disc = Udp.new()
	if _disc.open(0, "0.0.0.0", true) != OK:
		return _fail_open("no port for the LAN query")
	_query_to = address
	role = Role.PLAYER
	state = State.FINDING
	_query_until = _now_s() + QUERY_FOR
	_query_t = -1.0
	_query_rand = Crypt.random_bytes(8)
	prepare_key()
	changed.emit()
	return ""


## Leaves the session (a player) or ends it (the host). The players keep a copy of the run (§7.4).
func leave() -> void:
	if role == Role.NONE:
		return
	final = role == Role.HOST               # (a player keeps its token: back in the session later, in its own slot)
	if state == State.RUN or state == State.LOBBY:
		if role == Role.HOST:
			for s in peers:
				if peers[s].connected:
					peers[s].send_p.push(Wire.Kind.BYE, PackedByteArray())
		elif _send_p != null:
			_send_p.push(Wire.Kind.BYE, PackedByteArray())
		copies = 3
		_flush(true)
		copies = 1
	_end("You left the session." if role == Role.PLAYER else "You ended the session.")


func _end(why: String) -> void:
	if state == State.ENDED:
		return
	why_ended = why
	state = State.ENDED
	close()
	ended.emit(why)
	changed.emit()


## Closes the sockets (no network outside a session, §8.5).
func close() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	if _disc != null:
		_disc.close()
		_disc = null
	if clock != null:
		clock.driven = false


func active() -> bool:
	return role != Role.NONE and state != State.ENDED


func _exit_tree() -> void:
	close()
	if not _welcome_job.is_empty():
		WorkerThreadPool.wait_for_task_completion(_welcome_job["id"])
		_welcome_job = {}
	for id in _report_jobs:
		WorkerThreadPool.wait_for_task_completion(id)
	_report_jobs.clear()
	if _job != -1:
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
	for id in _stale_jobs:
		WorkerThreadPool.wait_for_task_completion(id)
	_stale_jobs.clear()
	if _rsa_thread != null:
		_rsa_thread.wait_to_finish()
		_rsa_thread = null
	for id in _snap_jobs:
		WorkerThreadPool.wait_for_task_completion(id)


func _now_s() -> float:
	return Time.get_ticks_usec() / 1000000.0


# ================================================================== the engine

## A session run's engine (sim/engine.gd made with session = true): the scenario's at step 0, or a snapshot's state
## checked as the save's loader checks a save and put into a fresh engine. A worker thread's work when a player joins or
## is resynced (§5.1, §11: off the frame but the swap); [engine, ""] or [null, why].
func _build(d: Dictionary, scen: String) -> Array:
	var PlantEngine = load("res://sim/engine.gd")
	if d.is_empty():
		return [PlantEngine.new(model, scen, true), ""]
	var bad := Snapshot.check(d, model, content)
	if bad != "":
		return [null, bad]
	var e = PlantEngine.new(model, d["scenario"], true)
	RunSave.apply(e, d["engine"])
	return [e, ""]


## The engine made: the run's from now on (the main thread's part, the swap).
func _install(r: Array) -> void:
	var e = r[0]
	clock.model = model
	clock.scenario = scenario
	if install_engine.is_valid():
		install_engine.call(e)
	else:
		clock.install(e)
	clock.driven = true
	clock.acc = 0.0
	if state != State.RUN or paused:
		clock.speed = SimClock.Speed.PAUSED
	engine_replaced.emit(e)


var _job := -1                          # the worker's task making an engine, -1 for none
var _stale_jobs: Array = []             # older snapshots' tasks, waited for once done
var _job_data: Dictionary = {}


## Starts making the engine on a worker thread: from a snapshot's bytes (decoded and checked there) or the scenario.
func _start_job(raw_len: int, z: PackedByteArray, step: int, desync: Dictionary) -> void:
	_loading = true
	var job := {"raw_len": raw_len, "z": z, "step": step, "desync": desync, "scenario": scenario,
			"r": [null, "the snapshot could not be read"],
			"d": null, "t0": Time.get_ticks_usec()}
	_job_data = job
	_job = WorkerThreadPool.add_task(_job_work.bind(job))


func _job_work(job: Dictionary) -> void:
	if job["z"].is_empty():
		job["r"] = _build({}, job["scenario"])
		return
	var d = Snapshot.decode(job["raw_len"], job["z"])
	if typeof(d) == TYPE_STRING:
		job["r"] = [null, d]
		return
	if typeof(d["session"].get("step")) != TYPE_INT or d["session"]["step"] != job["step"]:
		job["r"] = [null, "its step is damaged"]
		return
	job["d"] = d
	job["r"] = _build(d, d["scenario"])


func _poll_job() -> void:
	for id in _stale_jobs.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_stale_jobs.erase(id)
	if _job == -1 or not WorkerThreadPool.is_task_completed(_job):
		return
	WorkerThreadPool.wait_for_task_completion(_job)
	_job = -1
	var job := _job_data
	_job_data = {}
	var r: Array = job["r"]
	if r[0] == null:
		_end("The host's snapshot can't be loaded: " + r[1])
		return
	if not job["desync"].is_empty() and clock.engine != null:
		_desync_report(job["desync"], job["d"])
		stats["resyncs"] += 1
		_resyncs.append(_now)
		notice.emit("Resynchronised with the host")
	if job["d"] != null:
		scenario = job["d"]["scenario"]
		# the inputs the snapshot holds already are this player's no more (§5.1: their commits were before it)
		var cn = job["d"]["session"].get("committed_no", {})
		if typeof(cn) == TYPE_DICTIONARY and typeof(cn.get(str(slot))) == TYPE_INT:
			for n in _mine.keys():
				if n <= cn[str(slot)]:
					_mine.erase(n)
		if typeof(job["d"]["session"].get("settings")) == TYPE_DICTIONARY:
			settings = job["d"]["session"]["settings"]
	_what.append("install")
	var t0 := Time.get_ticks_usec()
	_install(r)
	stats["swap_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	stats["load_ms"] = (Time.get_ticks_usec() - job["t0"]) / 1000.0
	_loading = false
	var step: int = job["step"]
	committed = maxi(committed, step)
	for k in _commits.keys():
		if _commits[k]["first"] <= step:
			_commits.erase(k)
	_acc = 0.0
	if job["d"] != null:
		_send_control({"loaded": true})
	if state == State.RUN:
		clock.speed = SimClock.Speed.PAUSED if paused else (SimClock.Speed.FAST if fast else SimClock.Speed.NORMAL)
		clock.speed_changed.emit(clock.speed, "")
	changed.emit()


## Runs one committed step: the commit's inputs first when it starts here (in its order, each checked as the host
## checked it), then the step, then its digest when one is due.
func _run_step() -> void:
	var e = clock.engine
	var s: int = e.step_no + 1
	var c = _commits.get(s)
	if c != null:
		for x in c["inputs"]:
			var item = InputCheck.parse(x[2])
			if item == null or x[0] < 0 or x[0] >= SLOTS:
				continue            # (every player skips it alike)
			e.apply_input([s] + item + [x[0]])
			if x[0] == slot and _mine.has(x[1]):
				stats["delays"].append(_now_s() - _mine[x[1]][1])
				_mine.erase(x[1])
	clock.step_one()
	var stride: int = c["stride"] if c != null else _stride
	if c != null:
		_stride = c["stride"]
	if s % (DIGEST_EVERY * stride) == 0:
		var d: PackedByteArray = e.digest()
		if role == Role.HOST:
			_host_digests[s] = [d, _now_s()]
			_check_reports(s)
		elif not observer:
			var f := Crypt.be32(s)
			f.append_array(d)
			_send_p.push(Wire.Kind.HASH, f)


var _stride := 1


# ================================================================== the frame

func _process(delta: float) -> void:
	if role == Role.NONE or state == State.ENDED or _udp == null:
		return
	var t0 := Time.get_ticks_usec()
	_now = _now_s()
	_receive()
	if state == State.FINDING:
		_query()
	elif state == State.JOINING:
		_poll_welcome()
		_hello()
	if role == Role.HOST:
		_host_frame(delta)
	else:
		_player_frame(delta)
	if _hold_pause and (role == Role.PLAYER or not _turn_open):
		_hold_pause = false
		request_pause()
	_positions()
	_flush(_dirty)
	_dirty = false
	var us := Time.get_ticks_usec() - t0 - _step_us
	_step_us = 0
	stats["us"] = us
	if us > 2000:
		stats["over_2ms"] = stats.get("over_2ms", 0) + 1
	if us > stats["us_max"]:
		stats["us_max_what"] = ",".join(_what)   # what the worst frame did (the measurements)
	stats["us_max"] = maxi(stats["us_max"], us)
	_what.clear()
	stats["us_sum"] += us
	stats["frames"] += 1


var _step_us := 0                       # this frame's model steps (the session layer's own time is the rest)
var _what := PackedStringArray()         # what this frame's session layer did beyond the ordinary (its worst frame's)
var _hold_pause := false                # a procedure step done with "pause when a step is done": the pause asked
var _dirty := false                     # a reliable message waits: sent at the end of this frame, not the next tick


func _timed_step() -> void:
	var t := Time.get_ticks_usec()
	_run_step()
	_step_us += Time.get_ticks_usec() - t
	# a procedure step done (the tracker's hold, ui/sim_clock.gd): a notice, and the pause the player chose (§7.2)
	if clock.hold:
		clock.hold = false
		if clock.pause_on_hold:
			_hold_pause = true          # (asked once the frame's steps stop: a turn is never left half open)
		else:
			notice.emit("A procedure step is done.")


## Model steps a frame may take: as the clock budgets them (cpu_share of the frame, at most FRAME_MS).
func _budget(delta: float) -> int:
	return maxi(1, floori(minf(clock.cpu_share * delta * 1000.0, SimClock.FRAME_MS) / maxf(0.01, clock.step_ms)))


# ------------------------------------------------------------------ the host's frame

func _host_frame(delta: float) -> void:
	_watch_peers()
	_finish_snapshots()
	if state != State.RUN:
		return
	if fast:
		_host_fast(delta)
		return
	# at 1× the host commits each turn ahead, when its engine reaches the last commit (as built: the inputs of a turn
	# are known at its start, and a turn at 1× is never cut short), then runs its steps at the pace of the clock; a
	# pause takes effect after the turn committed
	_acc += minf(delta, clock.max_frame) / SimClock.STEP
	var n := floori(_acc + 1e-9)
	var cap := _budget(delta)
	if n > cap:
		n = cap
		_acc = 0.0
	else:
		_acc -= n
	for i in n:
		if clock.engine.step_no >= committed:
			if paused:
				_acc = 0.0
				break
			_commit_ahead()
		_timed_step()
		if _hold_pause and clock.engine.step_no >= committed:
			break
	if not paused and not _hold_pause and clock.engine.step_no >= committed:
		_commit_ahead()
	clock.acc = _acc * SimClock.STEP


## A 1× turn committed before its steps run: the inputs received since the last commit, at its first step.
func _commit_ahead() -> void:
	var first: int = committed + 1
	var c := {"first": first, "last": committed + _turn_len(1.0), "stride": 1, "rate": 1.0, "inputs": _inbox}
	_inbox = []
	for p in peers.values():
		p.turn_count = 0
		p.turn_bytes = 0
	for x in c["inputs"]:
		if peers.has(x[0]):
			peers[x[0]].committed_no = maxi(peers[x[0]].committed_no, x[1])
	_commits[first] = c
	committed = c["last"]
	_send_commit(c)


func _send_commit(c: Dictionary) -> void:
	if log_commits:
		var ins := []
		for x in c["inputs"]:
			ins.append([x[0], x[1], x[2].get_string_from_utf8()])
		commit_log.append([c["first"], c["last"], ins, c["rate"], _now])
	_broadcast(Wire.Kind.COMMIT, _commit_fields(c))
	_trim_commits()


## The host's engine runs the steps committed already (before a snapshot, before fast-forward begins).
func _catch_up() -> void:
	while clock.engine.step_no < committed:
		_timed_step()


## Fast-forward: the host runs a turn's steps, then commits them (§3.1): the engine may stop offering fast-forward
## within a turn, and no player may run past that point at the fast rate.
func _host_fast(delta: float) -> void:
	var e = clock.engine
	if not e.fast_forward():
		_turn_close()
		_set_fast(false, "Fast-forward stopped: " + clock.ff_blocked())
		return
	_acc += minf(delta, clock.max_frame) * rate / SimClock.STEP
	var n := floori(_acc + 1e-9)
	var cap := _budget(delta)
	if n > cap:
		n = cap
		_acc = 0.0
	else:
		_acc -= n
	var turn_len := _turn_len(rate)
	for i in n:
		if not _turn_open:
			_turn_begin()
		_timed_step()
		if _hold_pause:
			_turn_close()
			break
		if not clock.engine.fast_forward():
			_turn_close()
			_set_fast(false, "Fast-forward stopped: " + clock.ff_blocked())
			break
		if clock.engine.step_no - _turn_first + 1 >= turn_len:
			_turn_close()
	if _turn_open and _now - _turn_t >= TURN_S:
		_turn_close()
	clock.acc = _acc * SimClock.STEP


## The steps a turn closes: 2 at 1× (0.2 s), more in fast-forward, so that commits go out about 5 times a second
## whatever the rate (§3.1; the harness's model runs faster than real time too, Engine.time_scale).
static func _turn_len(r: float) -> int:
	return maxi(TURN, int(round(r * TURN * maxf(1.0, Engine.time_scale))))


func _turn_begin() -> void:
	_turn_open = true
	_turn_first = clock.engine.step_no + 1
	_turn_t = _now
	_turn_inputs = _inbox
	_inbox = []
	for p in peers.values():
		p.turn_count = 0
		p.turn_bytes = 0
	var stride := _stride_now()
	_commits[_turn_first] = {"first": _turn_first, "last": _turn_first, "stride": stride, "rate": rate,
			"inputs": _turn_inputs}
	for x in _turn_inputs:
		if peers.has(x[0]):
			peers[x[0]].committed_no = maxi(peers[x[0]].committed_no, x[1])


func _stride_now() -> int:
	return 1 if not fast else maxi(1, ceili(rate / 10.0))


func _turn_close() -> void:
	if not _turn_open:
		return
	_turn_open = false
	var last: int = clock.engine.step_no
	if last < _turn_first:
		# (no step ran: the inputs wait for the next turn)
		_commits.erase(_turn_first)
		_inbox = _turn_inputs + _inbox
		return
	var c: Dictionary = _commits[_turn_first]
	c["last"] = last
	committed = last
	_send_commit(c)


func _trim_commits() -> void:
	if _commits.size() > 600:
		var ks := _commits.keys()
		ks.sort()
		for k in ks.slice(0, ks.size() - 600):
			_commits.erase(k)


static func _commit_fields(c: Dictionary) -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(16)
	Crypt.put_u16(f, 0, 1)                      # epoch (MP2: always 1)
	Crypt.put_u32(f, 2, c["first"])
	Crypt.put_u32(f, 6, c["last"])
	Crypt.put_u16(f, 10, c["stride"])
	Crypt.put_u16(f, 12, clampi(int(round(c["rate"] * 100.0)), 1, 65535))
	Crypt.put_u16(f, 14, c["inputs"].size())
	for x in c["inputs"]:
		var h := PackedByteArray([x[0], 0, 0, 0, 0, 0, 0])
		Crypt.put_u32(h, 1, x[1])
		Crypt.put_u16(h, 5, x[2].size())
		f.append_array(h)
		f.append_array(x[2])
	return f


static func _read_commit(f: PackedByteArray):
	if f.size() < 16:
		return null
	var c := {"epoch": Crypt.u16(f, 0), "first": Crypt.u32(f, 2), "last": Crypt.u32(f, 6), "stride": Crypt.u16(f, 10),
			"rate": Crypt.u16(f, 12) / 100.0, "inputs": []}
	var n := Crypt.u16(f, 14)
	var at := 16
	for k in n:
		if at + 7 > f.size():
			return null
		var len := Crypt.u16(f, at + 5)
		if at + 7 + len > f.size():
			return null
		c["inputs"].append([f[at], Crypt.u32(f, at + 1), f.slice(at + 7, at + 7 + len)])
		at += 7 + len
	if at != f.size() or c["last"] < c["first"] or c["stride"] < 1:
		return null
	return c


func _set_fast(on: bool, why := "") -> void:
	if role != Role.HOST:
		return
	if on:
		var r := minf(ff_choice, FF_MAX)
		r = minf(r, clock.ff_cap())
		for p in peers.values():
			if p.connected:
				r = minf(r, p.ff_cap)
		r = maxf(1.0, r)
		if r <= 1.0:
			return
		_catch_up()
		fast = true
		rate = r
		_ff_rate0 = r
	else:
		if not fast:
			return
		_turn_close()
		fast = false
		rate = 1.0
		for p in peers.values():
			p.fast = false
		_my_fast = false
	clock.speed = SimClock.Speed.FAST if fast else SimClock.Speed.NORMAL
	clock.speed_changed.emit(clock.speed, why)
	_roster_changed()


var _my_fast := false
var _ff_rate0 := 1.0                    # the fast-forward rate chosen (the slowest player's cap): back to it after a lag
var _behind_t := 0.0


func _check_fast() -> void:
	if role != Role.HOST or state != State.RUN or fast or paused or not _my_fast:
		return
	for p in peers.values():
		if p.connected and not p.observer and not p.fast:
			return
	if clock.ff_blocked() != "":
		return
	_set_fast(true, "Fast-forward: everyone is ready")


## Players more than 2 s of real time behind the host: the rate comes down until they are back (§7.2).
func _check_behind() -> void:
	if not fast or _now - _behind_t < 1.0:
		return
	_behind_t = _now
	var lag := false
	for p in peers.values():
		if p.connected and not p.loading and committed - p.at > 2.0 * rate / SimClock.STEP:
			lag = true
	var r0 := rate
	rate = maxf(1.0, rate * 0.75) if lag else minf(_ff_rate0, rate * 1.25)
	if rate != r0:
		_roster_changed()


func _watch_peers() -> void:
	_old_reports()
	for p in peers.values():
		if not p.joined and _now - p.hello_t > NEVER_JOINED_S and not p.has_meta("rejoin"):
			# a hello nobody followed (or a forged one): the slot goes back, nothing of it was ever committed
			peers.erase(p.slot)
			_by_inc.erase(p.inc)
			_forget_replay(p.slot, p.inc)
			_free_slots.append(p.slot)
			_roster_changed()
			continue
		var silent = _now - p.last_rx
		if p.connected and ((not p.away and silent > SILENT_S) or (p.away and _now - p.away_t > AWAY_S)):
			p.connected = false
			p.gone_t = _now
			notice.emit("%s has lost the connection." % p.name)
			_roster_changed()
		if not p.connected and not p.released and p.gone_t >= 0.0 and _now - p.gone_t > RELEASE_S:
			_release(p)
		if p.observer and _now - p.observer_t > OBSERVER_SNAP_S and p.connected:
			p.observer_t = _now
			_send_snapshot([p.slot], {})


## Their person to the NPCs (§2.4): a `release` in the next commit.
func _release(p) -> void:
	p.released = true
	if state == State.RUN and p.person != "":
		_inbox.append([p.slot, 0, InputCheck.text(["release"])])
	_roster_changed()


# ------------------------------------------------------------------ the player's frame

func _player_frame(delta: float) -> void:
	_poll_job()
	if (state == State.RUN or state == State.LOBBY) and _now - _host_last_rx > (AWAY_S if _away_host else SILENT_S):
		_end("The host can't be reached any more (no host migration yet: MP3).")
		return
	if state != State.RUN or _loading or clock.engine == null:
		return
	# the jitter buffer (§3.1): play at the session's rate, `_buffer` turns behind the last commit; run dry and wait
	# until that much is committed again (the buffer then one turn longer, at most 5); more than a turn behind it,
	# catch up faster (never dropping a committed step); shrink again after 30 s without running dry
	var e = clock.engine
	var turn_len := _turn_len(rate)
	var ahead: int = committed - e.step_no
	if paused:
		_waiting = false
	elif _waiting:
		if ahead < _buffer * turn_len:
			_acc = 0.0
			clock.acc = 0.0
			return
		_waiting = false
	var r := rate
	if not paused and ahead > (_buffer + 1) * turn_len:
		r = maxf(rate * 2.0, minf(clock.ff_cap(), FF_MAX))
	_acc += minf(delta, clock.max_frame) * r / SimClock.STEP
	var want := floori(_acc + 1e-9)
	var n := mini(mini(want, ahead), _budget(delta))
	_acc = clampf(_acc - n, 0.0, 2.0)
	for i in n:
		_timed_step()
		if _hold_pause:
			break
	if want > ahead and not paused:
		# ran dry: a commit came later than the buffer covered
		_waiting = true
		if _now - _late_t > 1.0:
			_buffer = mini(_buffer + 1, MAX_BUFFER)
		_late_t = _now
	elif _now - _late_t > 30.0 and _buffer > 1:
		_buffer -= 1
		_late_t = _now
	clock.acc = _acc * SimClock.STEP


var _waiting := true                    # the jitter buffer fills before the player plays (and after it ran dry)




# ================================================================== receiving

func _receive() -> void:
	if _disc != null:
		for pk in _disc.poll(64):
			_on_discovery(pk[0], pk[1], pk[2])
	if _udp == null:
		return
	for pk in _udp.poll():
		_on_packet(pk[0], pk[1], pk[2])


func _on_packet(b: PackedByteArray, ip: String, port: int) -> void:
	if b.size() > Wire.MAX_UDP:
		return
	var h := Wire.read_header(b)
	if h.is_empty() or h["epoch"] != epoch:
		return
	var key := PackedByteArray()
	var peer = null
	if h["key"] == Wire.KEY_K:
		key = keys["K"]
	elif h["key"] == Wire.KEY_P:
		if role == Role.HOST:
			peer = peers.get(h["from"])
			if peer == null or h["to"] != HOST_SLOT or peer.inc != h["inc"]:
				return
			key = peer.p
		else:
			if _p.is_empty() or h["to"] != slot or h["from"] != HOST_SLOT:
				return
			key = _p
	else:
		return                              # (punches: MP4)
	var plain = Wire.open(key, b)
	if plain == null:
		return
	# the replay window (§1.3), kept only for senders this end knows: a player (its slot and incarnation, host side),
	# the host's address (player side). A joiner's hello and a host's welcome are idempotent answers and keep none, so
	# that packets with made-up senders can't grow the table (the blind review of MP2)
	var known := false
	if h["key"] == Wire.KEY_P:
		known = true
	elif role == Role.HOST:
		var kp = peers.get(h["from"])
		known = kp != null and kp.inc == h["inc"]
	else:
		known = (state == State.RUN or state == State.LOBBY) and ip == host_ip and port == host_port
	if known:
		var rk := "%d:%d:%d" % [h["from"], h["inc"], h["key"]]
		var rp: Wire.Replay = _replay.get(rk)
		if rp == null:
			if _replay.size() >= MAX_REPLAY:
				return
			rp = Wire.Replay.new()
			_replay[rk] = rp
		if not rp.fresh(h["number"]):
			return
		rp.record(h["number"])
	elif not (h["key"] == Wire.KEY_K and ((role == Role.HOST and h["from"] == Wire.NOBODY)
			or (role == Role.PLAYER and (state == State.FINDING or state == State.JOINING)))):
		return
	var msgs = Wire.messages(plain)
	if msgs == null:
		return
	if role == Role.HOST:
		_host_packet(h, msgs, b, ip, port, peer)
	else:
		_player_packet(h, msgs, ip, port)


# ------------------------------------------------------------------ the host's side

func _host_packet(h: Dictionary, msgs: Array, raw: PackedByteArray, ip: String, port: int, peer) -> void:
	if h["key"] == Wire.KEY_K:
		if h["from"] == Wire.NOBODY:
			for m in msgs:
				if m["kind"] == Wire.Kind.HELLO:
					_on_hello(m["fields"], h["inc"], ip, port)
			return
		var p = peers.get(h["from"])
		if p == null or p.inc != h["inc"] or not p.connected or not p.joined or ip != p.ip or port != p.port:
			return                          # (its address is the one its P packets come from)
		p.last_rx = _now
		# a player's broadcast (its position): forwarded unchanged to every other player (§9.4), at most FORWARD_RATE
		# a second from each (a flood is dropped here, §10)
		p.fwd_tokens = minf(FORWARD_BURST, p.fwd_tokens + (_now - p.fwd_t) * FORWARD_RATE)
		p.fwd_t = _now
		if p.fwd_tokens < 1.0:
			stats["dropped"] += 1
			return
		p.fwd_tokens -= 1.0
		for m in msgs:
			if m["kind"] == Wire.Kind.POS:
				_on_pos(h["from"], m["fields"])
		for q in peers.values():
			if q.slot != p.slot and q.connected and not q.loading:
				_udp.send(q.ip, q.port, raw)
		return
	# under P: the player's own stream
	if not peer.connected and _now - peer.gone_t > RELEASE_S:
		return                              # (its streams were given up: it joins again, §5.2)
	peer.last_rx = _now
	peer.joined = true
	peer.ip = ip
	peer.port = port
	if not peer.connected:
		peer.connected = true
		peer.gone_t = -1.0
		_roster_changed()
	for m in msgs:
		if m["reliable"]:
			if m["stream"] != Wire.STREAM_MAIN:
				continue
			for d in peer.recv_p.take(m["seq"], m["kind"], m["fields"]):
				_host_message(peer, d[0], d[1])
		else:
			match m["kind"]:
				Wire.Kind.ACK:
					_on_ack(peer, m["fields"])
				Wire.Kind.PING:
					_on_ping(peer, m["fields"])
				Wire.Kind.PONG:
					if m["fields"].size() == 8:
						peer.set_meta("rtt", _now - m["fields"].decode_double(0))


func _on_ack(peer, f: PackedByteArray) -> void:
	if f.size() != 10:
		return
	var key := f[0]
	var stream := f[1]
	var cum := Crypt.u32(f, 2)
	var mask := Crypt.u32(f, 6)
	var s = null
	if role == Role.HOST:
		if key == Wire.KEY_K:
			s = peer.bsend
		elif stream == Wire.STREAM_SNAP:
			s = peer.snap
		else:
			s = peer.send_p
	else:
		s = _send_p
	if s != null:
		s.on_ack(cum, mask, _now)


func _on_ping(peer, f: PackedByteArray) -> void:
	if f.size() != 12:
		return
	peer.at = Crypt.u32(f, 8)
	_unrel(peer, Wire.Kind.PONG, f.slice(0, 8))
	_check_behind()


var _unrel_out := {}                    # slot -> [message bytes] under P, this flush


func _unrel(peer, kind: int, fields: PackedByteArray) -> void:
	var k: int = peer.slot if peer != null else HOST_SLOT
	if not _unrel_out.has(k):
		_unrel_out[k] = []
	_unrel_out[k].append(Wire.msg(kind, fields))


func _on_hello(f: PackedByteArray, inc: int, ip: String, port: int) -> void:
	_what.append("hello")
	var r := JsonStrict.parse(f)
	if not r.get("ok", false) or typeof(r["value"]) != TYPE_DICTIONARY:
		return
	var hi: Dictionary = r["value"]
	for k in ["name", "rsa", "app", "content"]:
		if typeof(hi.get(k)) != TYPE_STRING:
			return
	var tok = hi.get("token")
	if tok != null and typeof(tok) != TYPE_STRING:
		return
	var name: String = hi["name"].strip_edges().left(24)
	if name == "":
		name = "Player"
	if hi["app"] != RunSave.app_version():
		_refuse(ip, port, inc, "version")
		return
	if hi["content"] != content:
		_refuse(ip, port, inc, "content")
		return
	if _by_inc.has(inc):
		# a hello again (its welcome lost): the same answer, only for the same RSA key, whose holder alone can read
		# P and the token in it; an incarnation is in every packet's clear header (the adversarial review of MP2)
		var p0 = peers[_by_inc[inc]]
		if hi["rsa"] == p0.rsa_pem and not p0.joined:
			p0.ip = ip
			p0.port = port
			_send_k_to(ip, port, p0.slot, [Wire.msg(Wire.Kind.WELCOME, p0.welcome)])
		return
	var key := CryptoKey.new()
	if hi["rsa"].length() > 1000 or key.load_from_string(hi["rsa"], true) != OK:
		return
	var p = null
	if tok != null:
		var th := Crypt.sha256(Marshalls.base64_to_raw(tok))
		for q in peers.values():
			if Crypt.same(q.token_hash, th):
				p = q
				break
		# a token whose player is still heard is not taken over (a replayed or stolen hello); its owner, back after a
		# drop, waits until the host has noticed it gone (SILENT_S) and its hello, repeated, is taken then
		if p != null and p.connected and p.joined and _now - p.last_rx < SILENT_S:
			return
	var fresh_slot := p == null
	if p == null:
		var live := 1
		for q in peers.values():
			if q.connected:
				live += 1
		# 8 slots a session, never given twice (§1: a player who left comes back to theirs with its token)
		if live >= SLOTS or (_next_slot >= SLOTS and _free_slots.is_empty()):
			_refuse(ip, port, inc, "full")
			return
		p = Peer.new()
		if not _free_slots.is_empty():
			p.slot = _free_slots.pop_front()
		else:
			p.slot = _next_slot
			_next_slot += 1
		peers[p.slot] = p
	else:
		_by_inc.erase(p.inc)
		_forget_replay(p.slot, p.inc)
		p.joined = false
		p.set_meta("rejoin", true)
	p.name = name
	p.ip = ip
	p.port = port
	p.inc = inc
	p.hello_t = _now
	p.rsa_pem = hi["rsa"]
	# a new token at every welcome (an old hello replayed carries one that opens nothing), sent with P inside the RSA
	# encryption: only the joiner reads it
	p.token = Crypt.random_bytes(16)
	p.token_hash = Crypt.sha256(p.token)
	p.connected = true
	p.gone_t = -1.0
	p.away = false
	p.last_rx = _now
	p.p = Crypt.random_bytes(32)
	p.pnum = 0
	p.send_p = Stream.Sender.new(Wire.STREAM_MAIN)
	p.snap = Stream.Sender.new(Wire.STREAM_SNAP)
	p.bsend = Stream.Sender.new(Wire.STREAM_MAIN)
	p.bsend.next_seq = _bseq
	p.recv_p = Stream.Receiver.new()
	p.committed_no = p.committed_no if not fresh_slot else 0
	_by_inc[inc] = p.slot
	var secret = p.p.duplicate()
	secret.append_array(p.token)
	var enc := Crypt.crypto().encrypt(key, secret)
	var w := {"inc": inc, "slot": p.slot, "epoch": epoch, "p": Marshalls.raw_to_base64(enc),
			"next_input": p.committed_no + 1, "bseq": _bseq,
			"state": "run" if state == State.RUN else "lobby", "scenario": scenario, "step": committed,
			"snap": state == State.RUN or _continued}
	p.welcome = JSON.stringify(w).to_utf8_buffer()
	_send_welcome(p)
	notice.emit("%s %s the session." % [name, "joined" if fresh_slot else "is back in"])
	# a continued session's lobby offers each player the role they had under the same name (§7.4)
	if state == State.LOBBY and fresh_slot and _reclaimable.has(name):
		_claim(p.slot, _reclaimable[name])
	if state == State.RUN or _continued:
		p.loading = true
		_send_snapshot([p.slot], {})
		if not fresh_slot and p.released and p.person != "" and _person_free(p.person):
			p.released = false
			_inbox.append([p.slot, 0, InputCheck.text(["role", p.person])])
	_roster_changed()


func _person_free(person: String) -> bool:
	var e = clock.engine
	if e == null or e._sm == null:
		return false
	var pi: int = e._sm.person_ix.get(person, -1)
	return pi != -1 and e.slot_of(pi) == -1


func _send_welcome(p) -> void:
	_send_k_to(p.ip, p.port, p.slot, [Wire.msg(Wire.Kind.WELCOME, p.welcome)])


func _refuse(ip: String, port: int, inc: int, why: String) -> void:
	var f := JSON.stringify({"inc": inc, "why": why}).to_utf8_buffer()
	_send_k_to(ip, port, Wire.NOBODY, [Wire.msg(Wire.Kind.REFUSE, f)])


func _host_message(p, kind: int, f: PackedByteArray) -> void:
	match kind:
		Wire.Kind.INPUT:
			if f.size() < 4:
				return
			var n := Crypt.u32(f, 0)
			var text := f.slice(4)
			if n <= p.committed_no:
				return                      # committed already (a resend)
			for x in _inbox:
				if x[0] == p.slot and x[1] == n:
					return
			var item = InputCheck.parse(text)
			if p.observer or item == null or not InputCheck.allowed(item, p.slot, HOST_SLOT, _instructors()):
				_drop_input(p, n, "not taken")
				return
			if item[0] == "role":
				# a claim goes through the host's claims (first come, reserved roles, the roster), as Together's
				_claim(p.slot, item[1])
				_drop_input(p, n, "")
				return
			if p.turn_count >= InputCheck.PER_TURN or p.turn_bytes + text.size() > InputCheck.PER_TURN_BYTES:
				_drop_input(p, n, "too many")
				notice.emit("Too many inputs from %s: some were dropped." % p.name)
				return
			p.turn_count += 1
			p.turn_bytes += text.size()
			_inbox.append([p.slot, n, text])
		Wire.Kind.HASH:
			if f.size() != 36:
				return
			var s := Crypt.u32(f, 0)
			_on_report(p, s, f.slice(4))
		Wire.Kind.CONTROL:
			var r := JsonStrict.parse(f)
			if r.get("ok", false) and typeof(r["value"]) == TYPE_DICTIONARY:
				_on_control(p, r["value"])
		Wire.Kind.BYE:
			p.connected = false
			p.gone_t = _now
			notice.emit("%s left the session." % p.name)
			_roster_changed()


## The replay windows of a player's earlier incarnation (it came back with a new one, or its slot was given again).
func _forget_replay(sl: int, inc: int) -> void:
	for k in [Wire.KEY_K, Wire.KEY_P]:
		_replay.erase("%d:%d:%d" % [sl, inc, k])


## An input the host won't commit: its player is told, so it doesn't wait for it ("sending…").
func _drop_input(p, n: int, why: String) -> void:
	if why != "":
		stats["dropped"] += 1
	p.send_p.push(Wire.Kind.CONTROL, JSON.stringify({"dropped": n, "why": why}).to_utf8_buffer())
	_dirty = true


func _instructors() -> Dictionary:
	var d := {}
	for s in settings.get("instructors", []):
		d[int(s)] = true
	return d


func _on_control(p, c: Dictionary) -> void:
	if c.has("claim") and typeof(c["claim"]) == TYPE_STRING:
		_claim(p.slot, c["claim"])
	if c.has("ready") and typeof(c["ready"]) == TYPE_BOOL:
		p.ready = c["ready"]
		_roster_changed()
	if c.has("pause") and c["pause"] == true:
		_pause(p.slot)
	if c.has("run") and c["run"] == true and (paused_by == p.slot):
		_resume()
	if c.has("fast") and typeof(c["fast"]) == TYPE_BOOL:
		p.fast = c["fast"]
		if c.has("cap") and (typeof(c["cap"]) == TYPE_FLOAT or typeof(c["cap"]) == TYPE_INT):
			p.ff_cap = clampf(float(c["cap"]), 1.0, FF_MAX)
		_roster_changed()
		_check_fast()
	if c.has("jump") and typeof(c["jump"]) == TYPE_STRING and c["jump"].length() <= 5:
		_jump_votes[p.slot] = c["jump"]
		_check_jump()
	if c.has("away") and typeof(c["away"]) == TYPE_BOOL:
		p.away = c["away"]
		p.away_t = _now
		_roster_changed()
	if c.has("loaded") and c["loaded"] == true:
		p.loading = false
		p.desync = false
		_roster_changed()


# ------------------------------------------------------------------ the lobby and the controls (§6.1, §7)

## A claim of a person (or "" for free mode), first come first served; in the lobby a session state, in a run an
## ordinary `role` input settled by commit order (§6.1).
func _claim(s: int, person: String) -> void:
	if person != "":
		for q in _all_claims():
			if q[1] == person and q[0] != s:
				if s == slot:
					notice.emit("Someone else has that role.")
				return
		var res = settings.get("reserved", {}).get(person)
		if res != null and int(res) != s:
			return
	if state == State.RUN:
		if person != "":
			_inbox.append([s, 0, InputCheck.text(["role", person])])
		elif clock.engine.trainee(s) != -1:
			_inbox.append([s, 0, InputCheck.text(["release"])])
		_set_person(s, person)
		return
	_set_person(s, person)


var _host_person := ""


func _set_person(s: int, person: String) -> void:
	if s == HOST_SLOT:
		_host_person = person
	elif peers.has(s):
		peers[s].person = person
	_roster_changed()


func _all_claims() -> Array:
	var out := [[HOST_SLOT, _host_person]]
	for p in peers.values():
		if p.connected or not p.released:
			out.append([p.slot, p.person])
	return out


## The host starts the run: the first commit puts every claim's `role` input at step 1 (§6.1).
func start() -> String:
	if role != Role.HOST or state != State.LOBBY:
		return "not the host of a session in its lobby"
	state = State.RUN
	paused = false
	if _continued:
		# a saved session continued (§7.4): its old players' people go back to the crews first, then the claims
		for k in SLOTS:
			if clock.engine.trainee(k) != -1:
				_inbox.append([k, 0, InputCheck.text(["release"])])
	for q in _all_claims():
		if q[1] != "" and (_continued or clock.engine.trainee(q[0]) == -1):
			_inbox.append([q[0], 0, InputCheck.text(["role", q[1]])])
	clock.speed = SimClock.Speed.NORMAL
	clock.speed_changed.emit(clock.speed, "")
	_roster_changed()
	return ""


func _pause(by: int) -> void:
	if paused or state != State.RUN:
		return
	_turn_close()
	if fast:
		_set_fast(false, "")
	paused = true
	paused_by = by
	clock.speed = SimClock.Speed.PAUSED
	clock.speed_changed.emit(clock.speed, "Paused by %s" % _name_of(by))
	_roster_changed()


func _resume() -> void:
	if not paused:
		return
	_turn_close()
	paused = false
	paused_by = -1
	_acc = 0.0
	clock.speed = SimClock.Speed.NORMAL
	clock.speed_changed.emit(clock.speed, "")
	_roster_changed()


func _check_jump() -> void:
	if role != Role.HOST or state != State.RUN:
		return
	var want = null
	var players := [[HOST_SLOT, _host_person]]
	for p in peers.values():
		if p.connected:
			players.append([p.slot, p.person])
	for q in players:
		if clock.engine.trainee(q[0]) == -1:
			continue                    # only those with a role vote (§7.2)
		var v = _jump_votes.get(q[0])
		if v == null or (want != null and v != want):
			return
		want = v
	if want == null:
		want = _jump_votes.get(HOST_SLOT)
		if want == null:
			return
	_jump_votes.clear()
	_own_number += 1
	_inbox.append([HOST_SLOT, _own_number, InputCheck.text(["jump", want])])
	_roster_changed()


func _name_of(s: int) -> String:
	for r in roster:
		if r["slot"] == s:
			return r["name"]
	return "someone"


## The roster changed: made again and broadcast (§2.2 `roster`).
func _roster_changed() -> void:
	if role != Role.HOST:
		changed.emit()
		return
	roster = [{"slot": HOST_SLOT, "name": display_name, "person": _host_person, "connected": true, "away": _away_host,
			"ready": true, "fast": _my_fast, "desync": false, "observer": false, "instructor": true, "host": true}]
	var ins := _instructors()
	for s in peers:
		var p = peers[s]
		roster.append({"slot": s, "name": p.name, "person": p.person if not p.released else "", "connected": p.connected,
				"away": p.away, "ready": p.ready, "fast": p.fast, "desync": p.desync, "observer": p.observer,
				"instructor": ins.has(s), "host": false, "addr": p.ip,
				"token": p.token_hash.hex_encode()})
	var msg := {"roster": roster, "state": "run" if state == State.RUN else "lobby", "paused": paused,
			"paused_by": paused_by, "fast": fast, "rate": rate, "settings": settings, "scenario": scenario}
	if state == State.RUN or state == State.LOBBY:
		_broadcast(Wire.Kind.ROSTER, JSON.stringify(msg).to_utf8_buffer())
	changed.emit()


## The host's own seat settings: an instructor seat for a slot (§7.3).
func set_instructor(s: int, on: bool) -> void:
	if role != Role.HOST:
		return
	var ins: Array = settings.get("instructors", [])
	if on and not ins.has(s):
		ins.append(s)
	elif not on:
		ins.erase(s)
	settings["instructors"] = ins
	_roster_changed()


## A role reserved for a slot before the start (§6.1).
func reserve(person: String, s: int) -> void:
	if role != Role.HOST or state != State.LOBBY:
		return
	var res: Dictionary = settings.get("reserved", {})
	if s < 0:
		res.erase(person)
	else:
		res[person] = s
	settings["reserved"] = res
	_roster_changed()


func _broadcast(kind: int, f: PackedByteArray) -> void:
	_dirty = true
	var seq := _bseq
	var tmp := Stream.Sender.new(Wire.STREAM_MAIN)
	tmp.next_seq = seq
	tmp.push(kind, f)
	_bseq = tmp.next_seq
	for p in peers.values():
		if p.connected or (p.gone_t >= 0.0 and _now - p.gone_t < RELEASE_S):
			for q in tmp.queue:
				p.bsend.push_raw(q[0], q[1])
		else:
			p.bsend.next_seq = _bseq


# ------------------------------------------------------------------ digests and resync (§4, §5.1)

func _on_report(p, s: int, d: PackedByteArray) -> void:
	if not _host_digests.has(s):
		return                              # (the host digests every step before its players: anything else is noise)
	if not _reported.has(s):
		_reported[s] = {}
	_reported[s][p.slot] = d
	_check_reports(s)


## Judges a step's digests once every player's report is in (or JUDGE_S after the host's own): most players
## agreeing with each other against the host end the session; a player alone against it is resynchronised (§4).
func _check_reports(s: int) -> void:
	if not _host_digests.has(s) or not _reported.has(s) or _judged.has(s):
		return
	var mine: PackedByteArray = _host_digests[s][0]
	var age: float = _now - _host_digests[s][1]
	if age > KEEP_DIGESTS_S:
		return
	var live := []
	for p in peers.values():
		if p.connected and not p.observer and not p.loading:
			live.append(p.slot)
	for sl in live:
		if not _reported[s].has(sl) and age < JUDGE_S:
			return
	_judged[s] = true
	var bad := []
	var against := {}
	for sl in _reported[s]:
		var d: PackedByteArray = _reported[s][sl]
		if d != mine:
			bad.append(sl)
			var hx := d.hex_encode()
			against[hx] = against.get(hx, 0) + 1
	# most players agree with each other against the host: the host's device differs (§4)
	for hx in against:
		if live.size() >= 2 and against[hx] * 2 > live.size():
			stats["desyncs"] += against[hx]
			_end("The host's device differs from the other players' (state digest at step %d): start again with another host." % s)
			return
	for sl in bad:
		var p = peers.get(sl)
		if p == null or p.desync:
			continue
		p.desync = true
		stats["desyncs"] += 1
		p.resyncs.append(_now)
		while not p.resyncs.is_empty() and _now - p.resyncs[0] > RESYNC_LIMIT_S:
			p.resyncs.pop_front()
		if p.resyncs.size() >= 2:
			p.observer = true
			p.observer_t = _now
			notice.emit("%s's device can't follow this session: they watch from now on." % p.name)
		else:
			notice.emit("%s was resynchronised with the host." % p.name)
		p.loading = true
		_send_snapshot([sl], {"step": s, "host_digest": mine.hex_encode()})
		_roster_changed()


## Old digests and reports go; steps still waiting for reports are judged once their time is up.
func _old_reports() -> void:
	for k in _reported.keys():
		_check_reports(k)
	for k in _host_digests.keys():
		if _now - _host_digests[k][1] > KEEP_DIGESTS_S:
			_host_digests.erase(k)
			_reported.erase(k)
			_judged.erase(k)


## Sends a snapshot of the committed step to these players (taken at most once per 2 s; encoded and compressed on a
## worker thread, §5.1).
func _send_snapshot(slots: Array, desync: Dictionary) -> void:
	_what.append("take snapshot")
	_turn_close()
	_catch_up()
	var step: int = clock.engine.step_no
	if not _snap_cache.is_empty() and _snap_cache["step"] == step and _now - _snap_cache["t"] < SNAP_EVERY_S:
		for s in slots:
			_push_snapshot(s, _snap_cache, desync)
		return
	var t0 := Time.get_ticks_usec()
	var cn := {}
	for q in peers.values():
		cn[str(q.slot)] = q.committed_no
	var d := Snapshot.take(clock.engine, scenario, content, {"step": step, "roster": roster, "settings": settings,
			"committed_no": cn})
	stats["snap_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	var job := [slots, d, null, desync, step]
	var id := WorkerThreadPool.add_task(func(): job[2] = Snapshot.encode(job[1]))
	_snap_jobs[id] = job


func _finish_snapshots() -> void:
	for id in _snap_jobs.keys():
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		var job: Array = _snap_jobs[id]
		_snap_jobs.erase(id)
		_snap_cache = {"step": job[4], "raw_len": job[2][0], "z": job[2][1], "t": _now}
		for s in job[0]:
			_push_snapshot(s, _snap_cache, job[3])


func _push_snapshot(s: int, snap: Dictionary, desync: Dictionary) -> void:
	var p = peers.get(s)
	if p == null:
		return
	var f := PackedByteArray()
	f.resize(8)
	Crypt.put_u32(f, 0, snap["raw_len"])
	Crypt.put_u32(f, 4, snap["step"])
	var dj := JSON.stringify(desync).to_utf8_buffer()
	f.append_array(Crypt.be16(dj.size()))
	f.append_array(dj)
	f.append_array(snap["z"])
	p.snap.push(Wire.Kind.SNAP, f)          # (after any still on its way: a stream never skips a message)


# ------------------------------------------------------------------ the player's side

func _player_packet(h: Dictionary, msgs: Array, ip: String, port: int) -> void:
	if h["key"] == Wire.KEY_K:
		if state == State.JOINING or state == State.FINDING:
			for m in msgs:
				if m["kind"] == Wire.Kind.WELCOME:
					_on_welcome(m["fields"], ip, port)
				elif m["kind"] == Wire.Kind.REFUSE:
					_on_refuse(m["fields"])
			return
		if ip != host_ip or port != host_port:
			return                          # a broadcast comes from the host alone on the LAN (§9.4)
		_host_last_rx = _now
		for m in msgs:
			if m["reliable"]:
				if h["from"] != HOST_SLOT or m["stream"] != Wire.STREAM_MAIN:
					continue
				for d in _recv_b.take(m["seq"], m["kind"], m["fields"]):
					_player_message(d[0], d[1])
			elif m["kind"] == Wire.Kind.POS and h["from"] != slot:
				_on_pos(h["from"], m["fields"])
			elif m["kind"] == Wire.Kind.WELCOME:
				pass                            # (a repeated welcome, answered by a repeated hello: nothing to do)
		return
	_host_last_rx = _now
	host_ip = ip
	host_port = port
	for m in msgs:
		if m["reliable"]:
			var rcv: Stream.Receiver = _recv_snap if m["stream"] == Wire.STREAM_SNAP else _recv_p
			for d in rcv.take(m["seq"], m["kind"], m["fields"]):
				_player_message(d[0], d[1])
		else:
			match m["kind"]:
				Wire.Kind.ACK:
					_on_ack(null, m["fields"])
				Wire.Kind.PONG:
					if m["fields"].size() == 8:
						stats["rtt"] = _now - m["fields"].decode_double(0)
				Wire.Kind.PING:
					if m["fields"].size() == 12:
						_unrel(null, Wire.Kind.PONG, m["fields"].slice(0, 8))


func _on_welcome(f: PackedByteArray, ip: String, port: int) -> void:
	var r := JsonStrict.parse(f)
	if not r.get("ok", false) or typeof(r["value"]) != TYPE_DICTIONARY:
		return
	var w: Dictionary = r["value"]
	if w.get("inc") != incarnation or typeof(w.get("slot")) != TYPE_INT or typeof(w.get("p")) != TYPE_STRING \
			or typeof(w.get("bseq")) != TYPE_INT \
			or typeof(w.get("next_input")) != TYPE_INT or typeof(w.get("scenario")) != TYPE_STRING \
			or typeof(w.get("step")) != TYPE_INT or not w.get("state") in ["lobby", "run"]:
		return
	if w["slot"] < 1 or w["slot"] >= 255 or not model.scenarios.has(w["scenario"]):
		return
	if not _welcome_job.is_empty():
		return                              # (a repeated welcome while P is being decrypted)
	# P decrypted on a worker thread: an RSA-2048 private-key operation takes about 12 ms on the Note 9 (§11: the
	# session layer's frame stays under 2 ms)
	var job := {"w": w, "ip": ip, "port": port, "p": PackedByteArray(), "key": _rsa}
	job["id"] = WorkerThreadPool.add_task(func(): job["p"] = Crypt.crypto().decrypt(job["key"], Marshalls.base64_to_raw(job["w"]["p"])))
	_welcome_job = job
	_what.append("welcome")


var _welcome_job := {}


## The welcome's P decrypted: the session joined.
func _poll_welcome() -> void:
	if _welcome_job.is_empty() or not WorkerThreadPool.is_task_completed(_welcome_job["id"]):
		return
	WorkerThreadPool.wait_for_task_completion(_welcome_job["id"])
	var job := _welcome_job
	_welcome_job = {}
	if job["p"].size() != 48 or state != State.JOINING:
		return
	_take_welcome(job["w"], job["p"].slice(0, 32), job["ip"], job["port"], job["p"].slice(32))


func _take_welcome(w: Dictionary, p: PackedByteArray, ip: String, port: int, token: PackedByteArray) -> void:
	_what.append("joined")
	_p = p
	slot = w["slot"]
	_token = token
	host_ip = ip
	host_port = port
	_host_last_rx = _now
	scenario = w["scenario"]
	_send_p = Stream.Sender.new(Wire.STREAM_MAIN)
	_recv_b = Stream.Receiver.new()
	_recv_b.expected = w["bseq"]
	_recv_p = Stream.Receiver.new()
	_recv_snap = Stream.Receiver.new()
	_recv_snap.max_message = Snapshot.MAX_COMPRESSED + 1024
	_next_input = maxi(_next_input, w["next_input"])
	clock.driven = true
	if w.get("snap", w["state"] == "run") != true:
		state = State.LOBBY
		committed = 0
		_start_job(0, PackedByteArray(), 0, {})       # the scenario at step 0, made on a worker thread
	else:
		state = State.RUN if w["state"] == "run" else State.LOBBY
		_loading = true
		committed = w["step"]
	_save_token()
	# the inputs made before the welcome, and those not yet committed (a rejoin), are sent now
	var again := _mine.keys()
	again.sort()
	for n in again:
		_send_input(n, _mine[n][0])
	for it in _unsent:
		send_input(it)
	_unsent.clear()
	notice.emit("Joined the session.")
	changed.emit()


func _on_refuse(f: PackedByteArray) -> void:
	var r := JsonStrict.parse(f)
	if not r.get("ok", false) or typeof(r["value"]) != TYPE_DICTIONARY or r["value"].get("inc") != incarnation:
		return
	var why: String = str(r["value"].get("why", ""))
	var words := {"full": "the session is full (8 players)", "version": "the host runs another version of the app",
			"content": "the host's plant content differs", "removed": "you were removed from the session",
			"closed": "the session has ended"}
	final = why in ["removed", "closed"]
	_end("Could not join: " + words.get(why, "refused"))


func _player_message(kind: int, f: PackedByteArray) -> void:
	match kind:
		Wire.Kind.COMMIT:
			var c = _read_commit(f)
			if c == null or c["epoch"] != epoch:
				return
			if c["first"] <= committed and not _loading:
				return                      # (one the snapshot had already)
			_commits[c["first"]] = c
			committed = maxi(committed, c["last"])
			rate = c["rate"]
			_trim_player_commits()
		Wire.Kind.ROSTER:
			var r := JsonStrict.parse(f)
			if r.get("ok", false) and typeof(r["value"]) == TYPE_DICTIONARY:
				_on_roster(r["value"])
		Wire.Kind.SNAP:
			_on_snapshot(f)
		Wire.Kind.CONTROL:
			var r := JsonStrict.parse(f)
			if r.get("ok", false) and typeof(r["value"]) == TYPE_DICTIONARY and typeof(r["value"].get("dropped")) == TYPE_INT:
				_mine.erase(r["value"]["dropped"])
				if r["value"].get("why", "") != "":
					notice.emit("The host did not take an input (%s)." % str(r["value"]["why"]))
		Wire.Kind.BYE:
			final = true
			_end("The host ended the session.")


func _trim_player_commits() -> void:
	if _commits.size() > 700:
		var ks := _commits.keys()
		ks.sort()
		var e = clock.engine
		for k in ks:
			if _commits.size() <= 600:
				break
			if e != null and _commits[k]["last"] < e.step_no:
				_commits.erase(k)


func _on_roster(m: Dictionary) -> void:
	_what.append("roster")
	for x in m.get("roster", []) if typeof(m.get("roster")) == TYPE_ARRAY else []:
		if typeof(x) == TYPE_DICTIONARY and x.get("host", false) == true:
			_away_host = x.get("away", false) == true       # (§7.5: the host in the background: wait for it)
	if typeof(m.get("roster")) != TYPE_ARRAY:
		return
	var rs := []
	for x in m["roster"]:
		if typeof(x) == TYPE_DICTIONARY and typeof(x.get("slot")) == TYPE_INT and typeof(x.get("name")) == TYPE_STRING:
			rs.append(x)
	roster = rs
	var was_run := state == State.RUN
	if m.get("state") == "run" and state == State.LOBBY:
		state = State.RUN
	paused = m.get("paused", false) == true
	paused_by = int(m.get("paused_by", -1)) if typeof(m.get("paused_by")) in [TYPE_INT, TYPE_FLOAT] else -1
	var was_fast := fast
	fast = m.get("fast", false) == true
	if typeof(m.get("rate")) in [TYPE_INT, TYPE_FLOAT]:
		rate = clampf(float(m["rate"]), 1.0, FF_MAX)
	if typeof(m.get("settings")) == TYPE_DICTIONARY:
		settings = m["settings"]
	if was_fast and not fast:
		_my_fast = false
	if clock != null:
		var sp: int = SimClock.Speed.PAUSED if paused or state != State.RUN else (SimClock.Speed.FAST if fast else SimClock.Speed.NORMAL)
		if sp != clock.speed or (state == State.RUN and not was_run):
			clock.speed = sp
			clock.speed_changed.emit(sp, ("Paused by %s" % _name_of(paused_by)) if paused else "")
	changed.emit()


func _on_snapshot(f: PackedByteArray) -> void:
	_what.append("snapshot %d B" % f.size())
	if f.size() < 10:
		return
	var raw_len := Crypt.u32(f, 0)
	var step := Crypt.u32(f, 4)
	var dl := Crypt.u16(f, 8)
	if 10 + dl > f.size():
		return
	var desync := {}
	var dr := JsonStrict.parse(f.slice(10, 10 + dl))
	if dr.get("ok", false) and typeof(dr["value"]) == TYPE_DICTIONARY:
		desync = dr["value"]
	if _job != -1:
		_stale_jobs.append(_job)        # (a newer snapshot: the older one's work is dropped when it ends)
		_job = -1
	_start_job(raw_len, f.slice(10 + dl), step, desync)


## Before loading the host's snapshot over its own state: both digests, the step, its state and the snapshot, to
## user://desync/ (§4), so that the cause can be found.
func _desync_report(desync: Dictionary, snap: Dictionary) -> void:
	_what.append("desync report")
	var dir := "user://desync"
	DirAccess.make_dir_recursive_absolute(dir)
	var e = clock.engine
	var mine := {"app": RunSave.app_version(), "content": content, "scenario": scenario,
			"engine": RunSave.capture(e, RunSave.engine_fields(e)), "session": {"step": e.step_no}}
	var rep := {"step": desync.get("step"), "host_digest": desync.get("host_digest"), "slot": slot,
			"digest": e.digest().hex_encode() if e.step_no == desync.get("step", -1) else "", "mine": mine,
			"snapshot": snap, "unix": int(Time.get_unix_time_from_system())}
	var name := "%s/desync-%d-%d.bin" % [dir, int(Time.get_unix_time_from_system()), slot]
	last_report = name
	# its encoding and writing on a worker thread (the state copied above is the main thread's part)
	_report_jobs.append(WorkerThreadPool.add_task(func():
		var fa := FileAccess.open(name, FileAccess.WRITE)
		if fa != null:
			fa.store_buffer(var_to_bytes(rep).compress(FileAccess.COMPRESSION_ZSTD))
			fa.close()))


var _report_jobs: Array = []
var last_report := ""


## A session's run continued alone (§7.4): every other slot's person is released to the NPCs at the next step.
## The player's own person moves to slot 0 (a single-player run's, which the app plays from then on: its restarts
## and saved runs know no other slot).
static func release_others(e, mine: int) -> void:
	for k in SLOTS:
		if k != mine and e.trainee(k) != -1:
			e.apply_input([e.step_no + 1, "release", k])
	var pi: int = e.trainee(mine)
	if mine != 0 and pi != -1:
		e.apply_input([e.step_no + 1, "release", mine])
		e.apply_input([e.step_no + 1, "role", e._sm.people[pi]["id"], 0])


# ================================================================== the player's requests

## An input from this player (ui/inputs.gd's sink): to the host, which commits it (§3.1).
func send_input(item: Array) -> void:
	if role == Role.HOST:
		if not (state == State.RUN or state == State.LOBBY) or not InputCheck.form_ok(item):
			return
		if item[0] == "jump":
			vote_jump(item[1])
			return
		_own_number += 1
		_inbox.append([HOST_SLOT, _own_number, InputCheck.text(item)])
		return
	if observer or not InputCheck.form_ok(item):
		return
	if item[0] == "jump":
		vote_jump(item[1])
		return
	if _send_p == null:
		_unsent.append(item)
		return
	var n := _next_input
	_next_input += 1
	var text := InputCheck.text(item)
	_mine[n] = [text, _now_s()]
	_send_input(n, text)


func _send_input(n: int, text: PackedByteArray) -> void:
	var f := Crypt.be32(n)
	f.append_array(text)
	_send_p.push(Wire.Kind.INPUT, f)
	_dirty = true


## Inputs sent and not yet committed (the UI shows them as "sending…").
func sending() -> int:
	return _mine.size()


func _send_control(c: Dictionary) -> void:
	if role == Role.HOST:
		return
	if _send_p != null:
		_send_p.push(Wire.Kind.CONTROL, JSON.stringify(c).to_utf8_buffer())


func claim(person: String) -> void:
	if role == Role.HOST:
		_claim(HOST_SLOT, person)
	else:
		_send_control({"claim": person})


func set_ready(on: bool) -> void:
	if role != Role.HOST:
		_send_control({"ready": on})


func request_pause() -> void:
	if role == Role.HOST:
		_pause(HOST_SLOT)
	else:
		_send_control({"pause": true})


## Run again: the host, or the player who paused (§7.1).
func request_run() -> void:
	if role == Role.HOST:
		_resume()
	else:
		_send_control({"run": true})


## Ready for fast-forward (§7.2): the host's press is its own vote and its rate choice.
func vote_fast(on: bool) -> void:
	_my_fast = on
	if role == Role.HOST:
		if not on and fast:
			_set_fast(false, "")
		_roster_changed()
		_check_fast()
	else:
		_send_control({"fast": on, "cap": clock.ff_cap()})


func vote_jump(hhmm: String) -> void:
	if role == Role.HOST:
		_jump_votes[HOST_SLOT] = hhmm
		_check_jump()
	else:
		_send_control({"jump": hhmm})


## Android's lifecycle (§7.5): the app goes to the background or comes back.
func set_away(on: bool) -> void:
	if _away == on:
		return
	_away = on
	if role == Role.HOST:
		_away_host = on
		if on:
			_pause(HOST_SLOT)
		_roster_changed()
		copies = 3
		_flush(true)
		copies = 1
	else:
		if not on:
			_host_last_rx = _now_s()        # (the host was not heard while the app was in the background)
		_send_control({"away": on})
		copies = 3
		_flush(true)
		copies = 1


# ================================================================== the LAN query (§9.3)

func _query() -> void:
	if _now > _query_until:
		_end("No session with that code answered on this network. If the network keeps devices apart, type the host's address.")
		return
	if _now - _query_t < QUERY_EVERY:
		return
	_query_t = _now
	var q := "WDPQ".to_ascii_buffer()
	q.append(1)
	q.append_array(keys["room"].slice(0, 8))
	q.append_array(_query_rand)
	if _query_to != "":
		var ip := _query_to
		var port := discovery_port
		if _query_to.contains("]:") or (_query_to.count(":") == 1):
			ip = _query_to.substr(0, _query_to.rfind(":")).trim_prefix("[").trim_suffix("]")
			port = _query_to.substr(_query_to.rfind(":") + 1).to_int()
		_disc.send(ip, port, q)
		return
	for a in broadcast_addresses():
		_disc.send(a, discovery_port, q)


## 255.255.255.255 and, for each IPv4 address of this device, its /24's broadcast address (Godot gives no netmask: a
## Wi-Fi's /24 is the common case; a typed address covers the rest).
static func broadcast_addresses() -> Array:
	var out := ["255.255.255.255"]
	for a in IP.get_local_addresses():
		var parts: PackedStringArray = a.split(".")
		if parts.size() == 4 and not a.begins_with("127.") and not a.begins_with("169.254."):
			var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not out.has(b):
				out.append(b)
	return out


func _on_discovery(b: PackedByteArray, ip: String, port: int) -> void:
	if role == Role.HOST:
		# a query: "WDPQ", version, the first 8 bytes of room, 8 random bytes
		if b.size() != 21 or b.slice(0, 4) != "WDPQ".to_ascii_buffer() or b[4] != 1:
			return
		if b.slice(5, 13) != keys["room"].slice(0, 8):
			return
		var a := "WDPA".to_ascii_buffer()
		a.append(1)
		a.append_array(b.slice(13, 21))
		a.append_array(Crypt.be16(_udp.port))
		a.append_array(Crypt.be16(epoch))
		a.append_array(Crypt.hmac(keys["lan"], a).slice(0, 16))
		_disc.send(ip, port, a)
		return
	# an answer: "WDPA", version, our random bytes, the session port, the epoch, 16 bytes of HMAC
	if state != State.FINDING or b.size() != 4 + 1 + 8 + 2 + 2 + 16 or b.slice(0, 4) != "WDPA".to_ascii_buffer():
		return
	if b.slice(5, 13) != _query_rand or not Crypt.same(Crypt.hmac(keys["lan"], b.slice(0, 17)).slice(0, 16), b.slice(17)):
		return
	host_ip = ip
	host_port = Crypt.u16(b, 13)
	if via != "":
		host_ip = via.substr(0, via.rfind(":"))
		host_port = via.substr(via.rfind(":") + 1).to_int()
	epoch = Crypt.u16(b, 15)
	state = State.JOINING
	_hello_t = -1.0
	_disc.close()
	_disc = null
	changed.emit()


func _hello() -> void:
	if _now - _hello_t < HELLO_EVERY:
		return
	if not _key_ready():
		return
	_hello_t = _now
	if _hello_json.is_empty():
		var tok = _saved_token()
		var hi := {"name": display_name, "rsa": _rsa.save_to_string(true), "app": RunSave.app_version(),
				"content": content, "token": Marshalls.raw_to_base64(tok) if not tok.is_empty() else null}
		_hello_json = JSON.stringify(hi).to_utf8_buffer()
	_send_k_to(host_ip, host_port, Wire.NOBODY, [Wire.msg(Wire.Kind.HELLO, _hello_json)], Wire.NOBODY)
	if _now - _query_until > 20.0:
		_end("The host didn't answer the join.")


# ------------------------------------------------------------------ the rejoin token (§5.2)

const SESSION_FILE := "user://mp-session.json"
static var _tokens := {}                # code -> token, while the app runs


func _save_token() -> void:
	_tokens[code] = _token
	var f := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"code": code, "token": Marshalls.raw_to_base64(_token)}))
		f.close()


func _saved_token() -> PackedByteArray:
	if _tokens.has(code):
		return _tokens[code]
	if FileAccess.file_exists(SESSION_FILE):
		var r := JsonStrict.parse_text(FileAccess.get_file_as_string(SESSION_FILE))
		if r.get("ok", false) and typeof(r["value"]) == TYPE_DICTIONARY and r["value"].get("code") == code \
				and typeof(r["value"].get("token")) == TYPE_STRING:
			return Marshalls.base64_to_raw(r["value"]["token"])
	return PackedByteArray()


static func forget_session() -> void:
	_tokens.clear()
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))


# ================================================================== positions (§6.3)

func _positions() -> void:
	if state != State.RUN and state != State.LOBBY:
		return
	if _now - _pos_t < POS_EVERY:
		return
	_pos_t = _now
	if role == Role.PLAYER and _p.is_empty():
		return
	if my_pos.is_valid():
		var w: Array = my_pos.call()
		var f := pos_fields(_pos_seq, w[0], w[1], w[2], w[3])
		_pos_seq += 1
		var pk := _seal_k(slot, Wire.NOBODY, [Wire.msg(Wire.Kind.POS, f)])
		if role == Role.HOST:
			for p in peers.values():
				if p.connected and not p.loading:
					_udp.send(p.ip, p.port, pk)
		else:
			_udp.send(host_ip, host_port, pk)
	# a ping every second both ways: round trips, the player's step for the host, and a paused host's sign of life
	# (§3.1, §5.3)
	if _now - _ping_t >= PING_EVERY:
		_ping_t = _now
		var f := PackedByteArray()
		f.resize(12)
		f.encode_double(0, _now)
		Crypt.put_u32(f, 8, clock.engine.step_no if clock.engine != null and not _loading else 0)
		if role == Role.HOST:
			for p in peers.values():
				if p.connected:
					_unrel(p, Wire.Kind.PING, f)
		elif _send_p != null:
			_unrel(null, Wire.Kind.PING, f)


var _pos_seq := 1


## A `pos` message's fields (24 bytes): sequence u32, x, y, z f32, heading u16, pitch u16 (of a turn), gait u8,
## flags u8, 2 spare.
static func pos_fields(seq: int, at: Vector3, yaw: float, pitch: float, gait: int) -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(24)
	Crypt.put_u32(f, 0, seq)
	f.encode_float(4, at.x)
	f.encode_float(8, at.y)
	f.encode_float(12, at.z)
	Crypt.put_u16(f, 16, int(round(fposmod(yaw, TAU) / TAU * 65536.0)) & 0xffff)
	Crypt.put_u16(f, 18, int(round(fposmod(pitch, TAU) / TAU * 65536.0)) & 0xffff)
	f[20] = clampi(gait, 0, 255)
	return f


func _on_pos(from: int, f: PackedByteArray) -> void:
	if f.size() != 24 or from < 0 or from >= 255 or from == slot:
		return
	var seq := Crypt.u32(f, 0)
	var at := Vector3(f.decode_float(4), f.decode_float(8), f.decode_float(12))
	if not at.is_finite():
		return
	var yaw := Crypt.u16(f, 16) / 65536.0 * TAU
	var pitch := Crypt.u16(f, 18) / 65536.0 * TAU
	if pitch > PI:
		pitch -= TAU
	var l: Array = positions.get(from, [])
	if not l.is_empty() and l[-1][5] >= seq:
		return
	l.append([_now, at, yaw, pitch, f[20], seq])
	while l.size() > 8:
		l.pop_front()
	positions[from] = l


## Where another player is drawn: 200 ms behind, interpolated (§6.3). [at, yaw, pitch, gait] or [].
func position_of(s: int, delay := 0.2) -> Array:
	var l: Array = positions.get(s, [])
	if l.is_empty():
		return []
	var t := _now_s() - delay
	if t <= l[0][0]:
		return [l[0][1], l[0][2], l[0][3], l[0][4]]
	for i in range(l.size() - 1, 0, -1):
		var a: Array = l[i - 1]
		var b: Array = l[i]
		if t >= a[0]:
			var k := clampf((t - a[0]) / maxf(0.001, b[0] - a[0]), 0.0, 1.0)
			return [a[1].lerp(b[1], k), lerp_angle(a[2], b[2], k), lerpf(a[3], b[3], k), b[4] if k > 0.5 else a[4]]
	return [l[-1][1], l[-1][2], l[-1][3], l[-1][4]]


# ================================================================== sending

func _seal_k(from: int, to: int, msgs: Array) -> PackedByteArray:
	_knum += 1
	var plain := PackedByteArray()
	for m in msgs:
		plain.append_array(m)
	return Wire.seal(keys["K"], Wire.header(Wire.KEY_K, from, to, epoch, incarnation, _knum), plain)


func _send_k_to(ip: String, port: int, to: int, msgs: Array, from := -2) -> void:
	if _udp == null:
		return
	for pk in _pack(msgs):
		var plain := PackedByteArray()
		for m in pk:
			plain.append_array(m)
		_knum += 1
		var f: int = slot if from == -2 else from
		var sealed := Wire.seal(keys["K"], Wire.header(Wire.KEY_K, f, to, epoch, incarnation, _knum), plain)
		for c in copies:
			_udp.send(ip, port, sealed)


## Messages into packets of at most MAX_PLAIN bytes each.
static func _pack(msgs: Array) -> Array:
	var out := []
	var cur := []
	var size := 0
	for m in msgs:
		if size + m.size() > Wire.MAX_PLAIN and not cur.is_empty():
			out.append(cur)
			cur = []
			size = 0
		cur.append(m)
		size += m.size()
	if not cur.is_empty():
		out.append(cur)
	return out


func _flush(force: bool) -> void:
	if _udp == null:
		return
	if not force and _now - _send_t < SEND_EVERY:
		return
	_send_t = _now
	if role == Role.HOST:
		for p in peers.values():
			if not p.connected and (p.gone_t < 0.0 or _now - p.gone_t > RELEASE_S):
				continue
			# under P: its stream, the snapshot's when the stream has nothing waiting, acks, pongs
			var msgs: Array = p.send_p.due(_now)
			if p.send_p.waiting() == 0 or msgs.is_empty():
				msgs.append_array(p.snap.due(_now))
			if p.recv_p.ack_due:
				var a: Array = p.recv_p.ack()
				msgs.append(Wire.msg(Wire.Kind.ACK, _ack_fields(Wire.KEY_P, Wire.STREAM_MAIN, a[0], a[1])))
				p.recv_p.ack_due = false
			msgs.append_array(_unrel_out.get(p.slot, []))
			_send_p_packets(p.ip, p.port, p.slot, HOST_SLOT, p.p, msgs, p)
			# under K: the broadcast stream
			var bm: Array = p.bsend.due(_now)
			if not bm.is_empty():
				_send_k_to(p.ip, p.port, Wire.NOBODY, bm)
	elif _send_p != null:
		var msgs: Array = _send_p.due(_now)
		for pair in [[_recv_p, Wire.KEY_P, Wire.STREAM_MAIN], [_recv_snap, Wire.KEY_P, Wire.STREAM_SNAP],
				[_recv_b, Wire.KEY_K, Wire.STREAM_MAIN]]:
			var rcv: Stream.Receiver = pair[0]
			if rcv.ack_due:
				var a: Array = rcv.ack()
				msgs.append(Wire.msg(Wire.Kind.ACK, _ack_fields(pair[1], pair[2], a[0], a[1])))
				rcv.ack_due = false
		msgs.append_array(_unrel_out.get(HOST_SLOT, []))
		_send_p_packets(host_ip, host_port, HOST_SLOT, slot, _p, msgs, null)
	_unrel_out.clear()


static func _ack_fields(key: int, stream: int, cum: int, mask: int) -> PackedByteArray:
	var f := PackedByteArray([key, stream, 0, 0, 0, 0, 0, 0, 0, 0])
	Crypt.put_u32(f, 2, cum)
	Crypt.put_u32(f, 6, mask)
	return f


var copies := 1                         # each packet this many times (the last ones before Android stops the app)


func _send_p_packets(ip: String, port: int, to: int, from: int, key: PackedByteArray, msgs: Array, peer) -> void:
	if msgs.is_empty() or key.is_empty():
		return
	for pk in _pack(msgs):
		var plain := PackedByteArray()
		for m in pk:
			plain.append_array(m)
		var n: int
		if peer != null:
			peer.pnum += 1
			n = peer.pnum
		else:
			_pnum += 1
			n = _pnum
		var sealed := Wire.seal(key, Wire.header(Wire.KEY_P, from, to, epoch, incarnation, n), plain)
		for c in copies:
			_udp.send(ip, port, sealed)             # (a copy is dropped by the replay window)


# ================================================================== what the UI reads

func is_host() -> bool:
	return role == Role.HOST


func is_instructor() -> bool:
	return role == Role.HOST or _instructors().has(slot)


func my_entry() -> Dictionary:
	for r in roster:
		if r["slot"] == slot:
			return r
	return {}


func buffer_turns() -> int:
	return _buffer
