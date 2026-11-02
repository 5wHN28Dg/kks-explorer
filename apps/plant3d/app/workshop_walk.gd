## The Workshop walk (docs/plant3d/WORKSHOP.md §8, milestone K1; `walk=workshop`): the Workshop's frame rules measured
## on a scripted 3 minutes on a fixed camera orbit, the plant held behind it. It opens the Workshop on a kind (`kind=`,
## default the first the build has), then: assembled; taken apart 0 -> 1 -> 0; a part selected and isolated; all shown;
## the selected subassembly taken apart; a part moved and turned with the handle; Reset; taken apart again and put
## back with Reassemble all; then back to the plant. The camera turns round the machine all the while. It logs
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
	await ws.shown
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
	await ws.shown
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
	if t < 20.0:
		_at("assembled")
	elif t < 50.0:
		_at("explode")
		ws.set_slider((t - 20.0) / 30.0)
	elif t < 80.0:
		_at("back")
		ws.set_slider(1.0 - (t - 50.0) / 30.0)
	elif t < 100.0:
		if _at("isolate"):
			ws.select(leaf)
			ws.isolate()
	elif t < 110.0:
		if _at("show all"):
			ws.show_all()
	elif t < 130.0:
		if _at("subassembly"):
			ws.select(first_sub)
			ws.set_only_selected(true)
		ws.set_slider(clampf((t - 110.0) / 10.0, 0.0, 1.0))
	elif t < 150.0:
		if _at("handle"):
			ws.set_slider(0.0)
			ws.set_only_selected(false)
			ws.select(leaf)
		var k := (t - 130.0) / 20.0
		ws.handled[leaf] = Transform3D(Basis(Vector3.UP, k * TAU * 0.5), Vector3(0, 0.05 * sin(k * TAU), 0))
		ws.apply()
	elif t < 170.0:
		if _at("reset"):
			ws.reset()
		ws.set_slider(clampf((t - 150.0) / 10.0, 0.0, 1.0))
	elif t < SECONDS:
		if _at("reassemble"):
			ws.reassemble()
	else:
		done = true
		running = false
		ws.close()
		await ws.left
		main._say("WORKSHOP exit=%.0fms" % ws.exit_ms)
		main._finish()

## True the first frame of a phase (it is logged).
func _at(phase: String) -> bool:
	if _phase == phase:
		return false
	_phase = phase
	main._say("WORKSHOP phase %s at %.1f s" % [phase, t])
	return true
