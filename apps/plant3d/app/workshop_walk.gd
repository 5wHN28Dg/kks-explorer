## The Workshop walk (docs/plant3d/WORKSHOP.md §8, milestone K1; `walk=workshop`): the Workshop's frame rules measured
## on a scripted 3 minutes on a fixed camera orbit, the plant held behind it. It opens the Workshop on a kind (`kind=`,
## default the first the build has), then: assembled; taken apart 0 -> 1 -> 0; a part selected and isolated; all shown;
## the selected subassembly taken apart; a part moved and turned with the handle; Reset; taken apart again and put
## back with Reassemble all; taken apart step by step (K2: each part drawn out of its place and let go) and put back
## together from a pile in the guided order (each part drawn to its place under its ghost and snapped); then back to
## the plant. The camera turns round the machine all the while. It logs
## `WORKSHOP` lines: the entry (button to the machine's first frame), the exit (back to the plant's first frame) and
## the scene's triangles (it enters, leaves and enters again first: the first entry and a second one); main.gd's frame log judges the frames from 5 s after the walk began until it leaves. K3 adds
## the X-ray, cutaway, section and running to the walk.
extends Node

const SECONDS := 180.0
const ORBIT_RATE := 0.25        # radians a second

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
	running = true

func _process(delta: float) -> void:
	if not running or done:
		return
	t += delta
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
	if t < 10.0:
		_at("assembled")
	elif t < 30.0:
		_at("explode")
		ws.set_slider((t - 10.0) / 20.0)
	elif t < 45.0:
		_at("back")
		ws.set_slider(1.0 - (t - 30.0) / 15.0)
	elif t < 55.0:
		if _at("isolate"):
			ws.select(leaf)
			ws.isolate()
	elif t < 60.0:
		if _at("show all"):
			ws.show_all()
	elif t < 75.0:
		if _at("subassembly"):
			ws.select(first_sub)
			ws.set_only_selected(true)
		ws.set_slider(clampf((t - 60.0) / 8.0, 0.0, 1.0))
	elif t < 90.0:
		if _at("handle"):
			ws.set_slider(0.0)
			ws.set_only_selected(false)
			ws.select(leaf)
		var k := (t - 75.0) / 15.0
		ws.handled[leaf] = Transform3D(Basis(Vector3.UP, k * TAU * 0.5), Vector3(0, 0.05 * sin(k * TAU), 0))
		ws.apply()
	elif t < 100.0:
		if _at("reset"):
			ws.reset()
		ws.set_slider(clampf((t - 90.0) / 6.0, 0.0, 1.0))
	elif t < 108.0:
		if _at("reassemble"):
			ws.reassemble()
	elif t < 140.0:
		if _at("take apart step by step"):
			ws.select("")
			if not ws.start_guide("disassemble"):
				main._say("WORKSHOP the kind has no assembly steps")
		_walk_steps(1.4)
	elif t < 178.0:
		if _at("assemble from a pile"):
			_move = {}
			ws.start_guide("assemble", "pile")
		_walk_steps(1.6)
	elif t < SECONDS:
		if _at("assembled again"):
			main._say("WORKSHOP steps done: %s (%d loose)" % [str(ws.guide.done()), ws.guide.loose.size()])
			ws.reset()
	else:
		done = true
		running = false
		ws.close()
		await ws.left
		main._say("WORKSHOP exit=%.0fms" % ws.exit_ms)
		main._finish()

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
		_move = {"id": id, "from": from, "to": to, "t0": t}
	var k: float = clampf((t - float(_move.t0)) / secs, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	ws.guide.loose[_move.id] = (_move.from as Transform3D).interpolate_with(_move.to, e)
	ws.apply()
	if k >= 1.0:
		if ws.guide.mode == "assemble":
			ws.try_place(String(_move.id))
		else:
			ws._released()
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
