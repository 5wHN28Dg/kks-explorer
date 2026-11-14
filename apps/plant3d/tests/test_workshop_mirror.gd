## The Workshop's live mirror (docs/plant3d/WORKSHOP.md §6.5, milestone K6), in the app as the trainee gets it:
## - the card's Workshop opens the equipment's kind with its state in the plant on the bench: each mirrored bench value
##   is the plant's value its bindings read (units made the bench's: a condenser's kPa(a) as gauge bar), the bench's
##   machine in the plant machine's state (or the entry's `else`), the readings and the machine drawn from them;
## - read only: the panel says "Mirror of <code>, read only" and what comes from the plant; no slider, command, fault
##   or restart is offered, and one made anyway is refused;
## - single play: the plant is paused while the mirror shows and the mirror stands as the trainee left it (a plant value
##   changed meanwhile is not followed); the speed before comes back on leaving;
## - a session: the plant runs on behind it and the mirror follows the plant's values step by step;
## - the resolution is the reference's (ref/plant3d_bench.py mirror_sources; tests/test_plant3d_workshop_bench.py
##   Mirror holds the same answers); the settings' list, the manual's link and a failed part open the free bench.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Mirror = preload("res://workshop/mirror.gd")

const PT_BAR := "00QHA10CP001"      # a transmitter showing bar
const PT_KPA := "30MAG10CP001"      # a condenser's vacuum transmitter, kPa(a)
const PT_M := "00GBB11CP001"        # a filter's head loss, metres of water
const ST := "30MAA10"
const ST2 := "30MAB10"              # the other casing on the shaft: no steam sound of its own
const GT := "10MBA10"

var p: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		p.append(what)

func run(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or main.workshop == null:
		main.free()
		return ["the app did not start with its Workshop"]
	await tree.process_frame
	var ws = main.workshop
	var e = ui.clock.engine
	_resolution(e)
	# --- single play: the transmitter mirrored, frozen as left
	_poke(e, "aux_p", 6.25)
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	var step0: int = e.step_no
	if not await _from_card(tree, ui, ws, PT_BAR):
		main.free()
		return p
	check(ws.mirror_code == PT_BAR and not ws.mirror_live, "the card opened a standing mirror of %s (%s)" % [PT_BAR,
			ws.mirror_code])
	check(ui.clock.speed == SimClock.Speed.PAUSED, "single play: the plant is paused while the mirror shows")
	var b = ws.bench
	check(b.mirrored() and b.now("p_applied") == 6.25, "the bench's applied pressure is the plant's (%s)" % b.now("p_applied"))
	check(b.machine_state("supply") == "on", "the loop supply is on: the entry's else state (%s)" % b.machine_state("supply"))
	_read_only(ws)
	_poke(e, "aux_p", 9.0)                          # (changed behind it: not followed in single play)
	await _bench_seconds(tree, ws, 3.0)
	check(b.now("p_applied") == 6.25, "the mirror stands as the trainee left the plant (%s)" % b.now("p_applied"))
	check(absf(b.now("pv") - 6.25) < 0.05, "the display reads the plant's pressure (%s)" % b.now("pv"))
	check(e.step_no == step0, "the plant did not step while the mirror showed (%d to %d)" % [step0, e.step_no])
	var t: String = App.texts(ws.panels.run_panel)
	check(t.contains("Mirror of %s, read only" % PT_BAR), "the panel says whose mirror it is: %s" % t.left(300))
	check(t.contains("as you left it") and t.contains("applied") and t.contains("supply state"),
			"the panel says what comes from the plant: %s" % t.left(400))
	(ws.panels.run_panel.find_child("run_leave_mirror", true, false) as Button).pressed.emit()
	check(ws.mirror_code == "" and not b.mirrored() and b.machine_state("supply") == "off" and
			not ws.panels.run_panel.sliders.is_empty(), "the mirror left: the bench from its start, the trainee's")
	check(ui.clock.speed == SimClock.Speed.PAUSED, "the plant stays paused behind the free bench")
	ws.close()
	await ws.left
	check(ui.clock.speed == SimClock.Speed.NORMAL, "the speed before comes back on leaving")
	check(not b.mirrored(), "leaving ends the mirror")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	# --- a manual's step link on an open mirror: the trainee's own bench (§6.5), and a pause left on the bench from
	# before doesn't freeze a mirror
	ws.bench.paused = true
	if await _from_card(tree, ui, ws, PT_BAR):
		check(not ws.bench.paused, "a mirror runs whatever pause the bench was left in")
		ui.open_manual("pressure_transmitter", "replacing", PT_BAR)
		ui.manual_view.follow({"workshop": "pressure_transmitter", "place": "housing"})
		await tree.process_frame
		check(ws.mirror_code == "" and not ws.bench.mirrored() and ws.selected == "housing",
				"a manual's link leaves the mirror for the free bench (%s, %s)" % [ws.mirror_code, ws.selected])
		ws.close()
		await ws.left
	# --- units: a condenser's absolute kPa as gauge bar
	_poke(e, "cond_p1", 9.2)
	if await _from_card(tree, ui, ws, PT_KPA):
		check(absf(ws.bench.now("p_applied") - (9.2 * 0.01 - 1.01325)) < 1e-12,
				"9.2 kPa(a) is mirrored as %s bar gauge" % ws.bench.now("p_applied"))
		ws.close()
		await ws.left
	# --- the steam turbine mid-run: its sequence's state and its speed
	_poke(e, "st_speed", 0.6)
	_poke(e, "st_flow", 30.0)
	_poke_state(e, "st_start", "accel")
	if await _from_card(tree, ui, ws, ST):
		b = ws.bench
		check(b.machine_state("turbine") == "accel" and b.now("speed") == 0.6 and b.now("flow") == 30.0,
				"the turbine mirrored in accel at 0.6 speed, 30 kg/s (%s, %s, %s)" % [b.machine_state("turbine"),
				b.now("speed"), b.now("flow")])
		await _bench_seconds(tree, ws, 1.0)
		check(absf(b.now("rpm") - 1800.0) < 2.0, "its readout 1800 rpm (%s)" % b.now("rpm"))
		check(ws.bench_running(), "a mirrored machine that runs is running on the bench: not taken apart")
		ws.set_slider(0.5)
		check(ws.s == 0.0, "the running mirror is not taken apart")
		ws.close()
		await ws.left
	if await _from_card(tree, ui, ws, ST2):
		var t2: String = App.texts(ws.panels.run_panel)
		check(ws.bench.machine_state("turbine") == "accel" and t2.contains("Not mirrored: flow"),
				"the other casing mirrors the shaft's machine and says the flow is not mirrored: %s" % t2.left(400))
		ws.close()
		await ws.left
	_poke(e, "gt1_speed", 1.0)
	_poke_state(e, "gt1_start", "loaded")
	if await _from_card(tree, ui, ws, GT):
		check(ws.bench.machine_state("turbine") == "loaded" and ws.bench.now("speed") == 1.0,
				"the gas turbine mirrored loaded at full speed")
		await _bench_seconds(tree, ws, 2.0)
		check(ws.bench.machine_state("turbine") == "loaded" and ws.bench.e.latched.find(1) == -1,
				"no bench trip moves or latches while it is mirrored (%s)" % ws.bench.machine_state("turbine"))
		ws.close()
		await ws.left
	# --- the free bench: from the settings' list, the manual's link
	check(ui.open_workshop("pressure_transmitter", PT_BAR), "the Workshop opens with a code, not mirrored")
	if await _wait_shown(tree, ws):
		check(ws.mirror_code == "" and not ws.bench.mirrored() and not ws.panels.run_panel.sliders.is_empty(),
				"opened without the mirror, the bench is the trainee's")
	ws.close()
	await ws.left
	# --- a session: the plant runs on and the mirror follows it
	ws.force_session = true
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	_poke(e, "aux_p", 3.0)
	if await _from_card(tree, ui, ws, PT_BAR):
		b = ws.bench
		check(ws.mirror_live, "in a session the mirror follows the plant")
		check(ui.clock.speed == SimClock.Speed.NORMAL, "in a session the plant is not paused")
		var s0: int = e.step_no
		await _bench_seconds(tree, ws, 1.0)
		check(e.step_no > s0, "the plant runs on behind the mirror (%d to %d)" % [s0, e.step_no])
		check(absf(b.now("p_applied") - _val(e, "aux_p")) < 1e-9, "the mirror is the plant's value (%s, %s)" % [
				b.now("p_applied"), _val(e, "aux_p")])
		ui.clock.set_speed(SimClock.Speed.PAUSED)
		_poke(e, "aux_p", 7.5)
		await _bench_seconds(tree, ws, 0.5)
		check(b.now("p_applied") == 7.5, "a change in the plant is followed (%s)" % b.now("p_applied"))
		t = App.texts(ws.panels.run_panel)
		check(t.contains("as it runs"), "the panel says it follows the plant: %s" % t.left(300))
		ws.close()
		await ws.left
	ws.force_session = false
	main.free()
	return p

## The card of `code`, its Workshop button pressed; true once the machine shows.
func _from_card(tree: SceneTree, ui, ws, code: String) -> bool:
	ui.open_card(code)
	var wbtn: Button = ui.card.find_child("workshop", true, false)
	if wbtn == null:
		check(false, "the card of %s offers the Workshop" % code)
		return false
	wbtn.pressed.emit()
	ui.close_card()
	if not await _wait_shown(tree, ws):
		check(false, "the Workshop of %s showed" % code)
		ws.close()
		return false
	return true

func _wait_shown(tree: SceneTree, ws) -> bool:
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		if ws.machine != null and ws.entry_ms > 0.0 and ws._loading == "":
			return true
		await tree.process_frame
	return false

## Frames until `s` seconds of bench time have been stepped.
func _bench_seconds(tree: SceneTree, ws, s: float) -> void:
	var want: int = ws.bench.steps + int(s * 10.0)
	var end := Time.get_ticks_msec() + 30000
	while ws.bench.steps < want and Time.get_ticks_msec() < end:
		await tree.process_frame

## The plant's value written (its step's and the step before's: a value of the paused plant as if it stood so).
func _poke(e, name: String, x: float) -> void:
	var i: int = e.ix[name]
	var c: PackedFloat64Array = e.cur
	c[i] = x
	e.cur = c
	var pv: PackedFloat64Array = e.prev
	pv[i] = x
	e.prev = pv

func _poke_state(e, mid: String, st: String) -> void:
	var mi: int = e._mc_ix[mid]
	var k: int = e.m.machine_by_id(mid)["_ids"].find(st)
	var ms: PackedInt32Array = e.mstate
	ms[mi] = k
	e.mstate = ms
	_poke(e, mid + "_state", float(k))

func _val(e, name: String) -> float:
	return e.cur[e.ix[name]]

## Nothing of the bench's own inputs offered, and each refused when made anyway.
func _read_only(ws) -> void:
	var rp = ws.panels.run_panel
	check(rp.visible, "the mirror's panel shows on entry")
	check(rp.sliders.is_empty() and rp.fault_btns.is_empty(), "no slider or fault is offered (%d, %d)" % [
			rp.sliders.size(), rp.fault_btns.size()])
	for n in ["run_restart", "run_supply_start", "run_supply_stop"]:
		check(rp.find_child(n, true, false) == null, "no %s in a mirror" % n)
	check(rp.find_child("run_mirror", true, false) != null, "the panel names the mirror")
	ws.run_command("terminal_block", "stop")
	check(ws.run_note == ws.READ_ONLY, "a command made anyway is refused: %s" % ws.run_note)
	ws.toggle_fault("loop_open")
	check(not ws.bench.faulted.has("loop_open"), "a fault made anyway is refused")
	ws.restart_bench()
	check(ws.bench.mirrored(), "a restart made anyway leaves the mirror")
	check(rp.find_child("run_leave_mirror", true, false) != null, "the panel offers to leave the mirror")

## The app's resolution gives the reference's answers (tests/test_plant3d_workshop_bench.py Mirror).
func _resolution(e) -> void:
	var BM = load("res://sim/bench_model.gd")
	var benches := {}
	for k in ["pressure_transmitter", "steam_turbine", "gas_turbine"]:
		var ps: PackedScene = load("res://built/workshop/%s.scn" % k)
		var n = ps.instantiate()
		var w: Dictionary = n.get_meta("workshop", {})
		benches[k] = BM.from_text(String(w.get("bench_text", "")), _comp_ids(n))
		n.free()
	var pm = e.m
	var r: Dictionary = Mirror.resolve(benches["steam_turbine"], pm, ST)
	check(r.values == [["speed", "st_speed", 1.0, 0.0], ["flow", "st_flow", 1.0, 0.0]] and
			r.machines == [["turbine", "st_start", ""]] and r.missing.is_empty(), "%s resolves as the reference: %s" % [ST, str(r)])
	r = Mirror.resolve(benches["steam_turbine"], pm, ST2)
	check(r.values == [["speed", "st_speed", 1.0, 0.0]] and r.machines == [["turbine", "st_start", ""]] and
			r.missing.size() == 1 and r.missing[0][0] == "flow", "%s resolves as the reference: %s" % [ST2, str(r)])
	r = Mirror.resolve(benches["gas_turbine"], pm, GT)
	check(r.values == [["speed", "gt1_speed", 1.0, 0.0]] and r.machines == [["turbine", "gt1_start", ""]] and
			r.missing.is_empty(), "%s resolves as the reference: %s" % [GT, str(r)])
	for x in [[PT_BAR, "aux_p", 1.0, 0.0], [PT_KPA, "cond_p1", 0.01, -1.01325], [PT_M, "fl1_hl", 0.0980665, 0.0]]:
		r = Mirror.resolve(benches["pressure_transmitter"], pm, x[0])
		check(r.values == [["p_applied", x[1], x[2], x[3]]] and r.machines == [["supply", "", "on"]] and
				r.missing.is_empty(), "%s resolves as the reference: %s" % [x[0], str(r)])

func _comp_ids(n: Node) -> Array:
	var out := []
	_ids(n, out)
	return out

func _ids(n: Node, out: Array) -> void:
	if n.has_meta("explode"):
		out.append(String(n.get_meta("id")))
	for c in n.get_children():
		_ids(c, out)
