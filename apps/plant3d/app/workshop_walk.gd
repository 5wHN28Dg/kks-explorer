## The Workshop walk (docs/plant3d/WORKSHOP.md §8, milestone K1; `walk=workshop`): the Workshop's frame rules measured
## on a scripted 3 minutes on a fixed camera orbit, the plant held behind it. It opens the Workshop on a kind (`kind=`,
## default the first the build has), then: assembled; taken apart 0 -> 1 -> 0; a part selected and isolated; all shown;
## the selected subassembly taken apart; a part moved and turned with the handle; Reset; taken apart again and put
## back with Reassemble all; taken apart step by step (K2: each part drawn out of its place and let go) and put back
## together from a pile in the guided order (each part drawn to its place under its ghost and snapped); then back to
## the plant. The camera turns round the machine all the while. It logs
## `WORKSHOP` lines: the entry (button to the machine's first frame), the exit (back to the plant's first frame) and
## the scene's triangles (it enters, leaves and enters again first: the first entry and a second one); main.gd's frame log judges the frames from 5 s after the walk began until it leaves.
## K3: the machine runs the whole walk where its bench model allows (the transmitter: the loop supply on at 2×, the
## applied pressure swept up past its range and down to vacuum and back, so the diaphragm, the display, the terminals,
## the flow and the colours move all the while, taken apart and in the steps too); after the steps the X-ray, the
## cutaway, a section swept across the machine (flow on), each fault made and repaired, then Stop. It logs the bench's
## steps (`WORKSHOP bench steps=… max=…us mean=…us`, §8's 0.3 ms). The walk keeps its 3 minutes (§8), the K1 and K2
## phases shortened again.
## The first entry waits until the plant's warm-up has queued the Workshop's pipelines and they are made (WORKSHOP.md
## §7.1: each kind's machine in the Workshop's materials, in the background after the plant's first walkable frame), as
## for a trainee who walks a little first; `cold=1` enters at once instead (K3's measurement: the machine's first frame
## then compiles them). It logs `WORKSHOP waited … ms`.
extends Node

const SECONDS := 180.0
const ORBIT_RATE := 0.25        # radians a second
# the guided phases: taken apart step by step, then put together from a pile ([start, end] in seconds of the walk);
# each step's part is drawn over the phase's time shared by its steps, at most STEP_APART_S / STEP_PILE_S (a kind with
# few steps keeps K2's pace; the turbine's 30-odd steps are all walked: K4a's fixed pace left 14 of them loose)
const APART := [60.0, 88.0]
const PILE := [88.0, 118.0]
const STEP_APART_S := 1.4
const STEP_PILE_S := 1.6
const STEP_SLACK_S := 1.0        # kept free in each phase (each step starts where the last one's time ended, so frames
								# are not lost between steps: the slack is for the phase's own first and last frames)

var main
var ws
var kind := ""
var running := false
var t := 0.0
var done := false
var _phase := ""
var _move := {}                 # the guided step being walked: {id, from, to, t0}

func start(m, k := "") -> void:
	main = m
	ws = m.workshop
	var kinds: Array = ws.kinds()
	kind = k if k != "" else (kinds[0] if not kinds.is_empty() else "")
	# the first entry comes after the plant's warm-up has queued the Workshop's pipelines and they are made (as a trainee
	# who walks a little first finds them; §7.1), unless `cold=1` asks for the entry at once, as K3 measured it
	if String(main.opts.get("cold", "0")) in ["0", "false", ""]:
		var t0 := Time.get_ticks_msec()
		var c0 := Vector2i(-1, -1)
		var still := 0
		while Time.get_ticks_msec() - t0 < 60000 and still < 60:
			await get_tree().process_frame
			var c := Vector2i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))
			still = still + 1 if ws.warmed and ws.kinds_warmed and c == c0 else 0
			c0 = c
		main._say("WORKSHOP waited %d ms for the plant's warm-up (warmed=%s)" % [Time.get_ticks_msec() - t0, str(ws.warmed and ws.kinds_warmed)])
	if kind == "" or not ws.open(kind):
		main._say("WORKSHOP no kind to open (%s)" % str(kinds))
		done = true
		main._finish()
		return
	if not await _shown():
		return
	main._say("WORKSHOP kind=%s entry=%.0fms load=%.0fms tris=%d (the first entry)" % [kind, ws.entry_ms, ws.load_ms, int(ws.machine.get_meta("tris", 0))])
	# out and in again: the exit, and an entry with everything it needs already compiled and loaded once
	for i in 30:
		await get_tree().process_frame
	ws.close()
	await ws.left
	main._say("WORKSHOP exit=%.0fms (after the first entry)" % ws.exit_ms)
	for i in 60:
		await get_tree().process_frame
	ws.open(kind)
	if not await _shown():
		return
	main._say("WORKSHOP entry=%.0fms load=%.0fms (the second entry)" % [ws.entry_ms, ws.load_ms])
	_bench_start()
	running = true

var _ops := []                  # the bench's ops as written (machine commands, set ops)
var _made := {}                 # the faults made in the walk's fault phase

## The bench running from the walk's start: each machine started (the first of its commands its resting state takes:
## Start, a turbine's Roll), at 2× (`bench_speed=`: a measurement may run it faster than the trainee's 2×, so that a
## turbine's plant-length soak still lets it reach full speed within the 3 minutes; logged).
func _bench_start() -> void:
	if not ws.bench.loaded():
		main._say("WORKSHOP the kind has no bench model")
		return
	ws.bench.set_speed(2.0)
	var fast := float(main.opts.get("bench_speed", "2"))
	if fast > 2.0:
		ws.bench.speed = fast   # (past the Run panel's 2×: the walk's own)
		main._say("WORKSHOP bench at %.1fx (the walk's bench_speed)" % fast)
	_ops = ws.bench.m.ops_ui
	for mc in ws.bench.m.machines:
		for o in _ops:
			if o.get("machine") == mc.id and mc.commands.has(o.do) and \
					String(mc.init) in Array(mc.commands[o.do].get("from", [])):
				ws.run_command(o.at, o.do)
				break

## What the walk switches on as it may (every 0.2 s of the walk): each op of the bench that is no machine's command,
## no slider and no trip's reset, and sets something from 0 to on, once its permissives are met (a generator's
## excitation at 95 % speed, its breaker inside the synchronising window).
func _switch_on() -> void:
	for o in _ops:
		if o.has("machine") or o.has("input") or o.has("trip") or not o.has("set"):
			continue
		var on := false
		for k in o.set:
			if float(o.set[k]) != 0.0 and ws.bench.now(k) == 0.0:
				on = true
		for nd in o.get("needs", []):   # (as the engine judges them: each at least 0.5)
			on = on and ws.bench.now(String(nd[0])) >= 0.5
		if on:
			ws.run_op(o.at, o.do)

## Each set op's slider swept over its range (a slow sine, a period of 40 s), from its low end.
func _bench_sweep() -> void:
	for o in _ops:
		if o.get("do") == "set" and o.has("range"):
			var lo: float = float(o.range[0])
			var hi: float = float(o.range[1])
			ws.bench.op_set(o.at, lo + (hi - lo) * (0.5 - 0.5 * cos(t * TAU / 40.0)))

func _process(delta: float) -> void:
	if not running or done:
		return
	t += delta
	if ws.bench.loaded() and fmod(t, 0.5) < delta:
		_bench_sweep()
	if ws.bench.loaded() and fmod(t, 0.2) < delta:
		_switch_on()
	ws.cam.yaw += ORBIT_RATE * delta
	ws.cam.place()
	var order: Array = ws.spec.order
	var first_sub := ""         # a component with children: the subassembly taken apart alone
	for id in order:
		for c in order:
			if ws.spec.comps[c].parent == id:
				first_sub = id
				break
		if first_sub != "":
			break
	var leaf: String = order[-1] if not order.is_empty() else ""
	if t < 6.0:
		_at("assembled")
	elif t < 18.0:
		_at("explode")
		ws.set_slider((t - 6.0) / 12.0)
	elif t < 26.0:
		_at("back")
		ws.set_slider(1.0 - (t - 18.0) / 8.0)
	elif t < 31.0:
		if _at("isolate"):
			ws.select(leaf)
			ws.isolate()
	elif t < 33.0:
		if _at("show all"):
			ws.show_all()
	elif t < 41.0:
		if _at("subassembly"):
			ws.select(first_sub)
			ws.set_only_selected(true)
		ws.set_slider(clampf((t - 33.0) / 5.0, 0.0, 1.0))
	elif t < 49.0:
		if _at("handle"):
			ws.set_slider(0.0)
			ws.set_only_selected(false)
			ws.select(leaf)
		var k := (t - 41.0) / 8.0
		ws.handled[leaf] = Transform3D(Basis(Vector3.UP, k * TAU * 0.5), Vector3(0, 0.05 * sin(k * TAU), 0))
		ws.apply()
	elif t < 55.0:
		if _at("reset"):
			ws.reset()
		ws.set_slider(clampf((t - 49.0) / 4.0, 0.0, 1.0))
	elif t < APART[0]:
		if _at("reassemble"):
			ws.reassemble()
	elif t < APART[1]:
		if _at("take apart step by step"):
			ws.select("")
			if not ws.start_guide("disassemble"):
				main._say("WORKSHOP the kind has no assembly steps")
			_step_s = step_secs(APART[1] - APART[0], ws.guide.real_steps(), STEP_APART_S)
			_next_t0 = -1.0
		_walk_steps(_step_s)
	elif t < PILE[1]:
		if _at("assemble from a pile"):
			_move = {}
			ws.start_guide("assemble", "pile")
			_step_s = step_secs(PILE[1] - PILE[0], ws.guide.real_steps(), STEP_PILE_S)
			_next_t0 = -1.0
		_walk_steps(_step_s)
	elif t < 120.0:
		if _at("assembled again"):
			main._say("WORKSHOP steps done: %s (%d loose)" % [str(ws.guide.done()), ws.guide.loose.size()])
			ws.reset()
	elif t < 130.0:
		if _at("x-ray"):
			ws.views.set_xray(true)
	elif t < 140.0:
		if _at("cutaway"):
			ws.views.set_xray(false)
			ws.views.set_cut(true)
	elif t < 155.0:
		if _at("section sweep"):
			ws.views.set_cut(false)
			ws.views.set_section(true)
		ws.views.set_section_at(1.0 - (t - 140.0) / 15.0)
	elif t < 173.0:
		if _at("faults"):
			ws.views.set_section(false)
			ws.views.set_cut(true)
			if ws.bench.loaded():   # (where the run got to before the faults: each machine's state)
				var st := PackedStringArray()
				for mc in ws.bench.m.machines:
					st.append("%s=%s" % [mc.id, ws.bench.machine_state(mc.id)])
				main._say("WORKSHOP bench before the faults: %s" % " ".join(st))
		var faults: Array = ws.bench.m.faults if ws.bench.loaded() else []
		if not faults.is_empty():
			# each fault for its share of the 18 s: made at its start, repaired at two thirds of it
			var share := 18.0 / faults.size()
			var fk := int((t - 155.0) / share)
			var into := fmod(t - 155.0, share)
			if fk < faults.size():
				var id := String(faults[fk].id)
				if into < share * 0.66 and not ws.bench.faulted.has(id) and not _made.has(id):
					_made[id] = true
					ws.toggle_fault(id)
				elif into >= share * 0.66 and ws.bench.faulted.has(id):
					ws.toggle_fault(id)
	elif t < SECONDS:
		if _at("stop"):
			ws.views.set_cut(false)
			for o in _ops:
				if o.has("machine") and o.do == "stop":
					ws.run_command(o.at, o.do)
	else:
		done = true
		running = false
		if ws.bench.loaded():
			main._say("WORKSHOP bench steps=%d max=%dus mean=%.1fus" % [ws.bench.steps, ws.bench.step_us_max,
				float(ws.bench.step_us_sum) / maxf(ws.bench.steps, 1)])
		ws.close()
		await ws.left
		main._say("WORKSHOP exit=%.0fms" % ws.exit_ms)
		main._finish()

var _step_s := STEP_APART_S     # the guided phase's time per step
var _next_t0 := -1.0            # where the last step's time ended (the next one starts there)

## Each step's time in a guided phase of `phase_s` seconds with `steps` steps: their share of it (less the slack), at
## most `longest`.
static func step_secs(phase_s: float, steps: int, longest: float) -> float:
	return minf(longest, (phase_s - STEP_SLACK_S) / maxi(steps, 1))

## The guided steps walked: the next step's part drawn from where it stands to where it goes (assembling: its place,
## then snapped; taking apart: out and away from the machine, then let go) over `secs` seconds, then the next.
func _walk_steps(secs: float) -> void:
	if not ws.guide.on():
		return
	if _move.is_empty():
		var i: int = ws.guide.next_step()
		if i < 0:
			return
		var id := String(ws.guide.steps[i].place)
		var from: Transform3D = ws._cur_m.get(id, Transform3D.IDENTITY)
		var to: Transform3D
		if ws.guide.mode == "assemble":
			to = ws.target_m(id)
		else:
			var box: AABB = ws.machine.get_meta("box", AABB())
			var out: Vector3 = from.origin - box.get_center()
			out = (out if out.length() > 1e-4 else Vector3.BACK).normalized()
			to = from.translated(out * box.size.length() * 0.6)
		ws.select(id)
		if ws.guide.placed(id):
			ws.guide.loose[id] = from
		# from where the last step's time ended (not this frame: a frame lost between steps adds up over 30 of them)
		var t0: float = _next_t0 if _next_t0 >= 0.0 else t   # (after a hitch the steps catch up, one a frame)
		_move = {"id": id, "from": from, "to": to, "t0": t0}
	var k: float = clampf((t - float(_move.t0)) / secs, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	ws.guide.loose[_move.id] = (_move.from as Transform3D).interpolate_with(_move.to, e)
	ws.apply()
	if k >= 1.0:
		if ws.guide.mode == "assemble":
			ws.try_place(String(_move.id))
		else:
			ws._released()
		_next_t0 = float(_move.t0) + secs
		_move = {}

## Waits for the machine's first frame; false (the walk ends, logged) when it didn't come within 60 s.
func _shown() -> bool:
	var end := Time.get_ticks_msec() + 60000
	var gen: int = ws._gen
	while Time.get_ticks_msec() < end:
		if ws.is_open and ws._gen == gen and ws.machine != null and ws._loading == "" and ws.entry_ms > 0.0 and ws.part == kind:
			return true
		await get_tree().process_frame
	main._say("WORKSHOP the machine did not show (%s)" % ws.panels.note.text)
	done = true
	ws.close()
	main._finish()
	return false

## True the first frame of a phase (it is logged).
func _at(phase: String) -> bool:
	if _phase == phase:
		return false
	_phase = phase
	main._say("WORKSHOP phase %s at %.1f s" % [phase, t])
	return true
