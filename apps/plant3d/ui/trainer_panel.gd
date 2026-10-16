## The instructor's panel (docs/PLANT3D.md §7.8): the scenario to run (the plant restarts in it), and the scenario's
## trainer faults, each pressed once at the moment that teaches most (applied in the next model step). Shown when
## instructor mode is on in the settings.
extends PanelContainer

const W = preload("res://ui/widgets.gd")

var ui
var body: VBoxContainer
var _sig := ""
var _t := 0.0


func setup(u) -> void:
	ui = u
	var parts := W.panel("Instructor", func(): ui.close_trainer())
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	visible = false


func open() -> void:
	visible = true
	_sig = ""
	refresh()
	if ui.wants_focus():
		var b := _first(body)
		if b:
			b.grab_focus()


static func _first(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and not c.disabled:
			return c
		var f := _first(c)
		if f:
			return f
	return null


## The scenario's faults the trainer presses (those without a condition).
static func trainer_faults(e) -> Array:
	return e.sc.get("faults", []).filter(func(f): return not f.has("when"))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()


func refresh() -> void:
	var e = ui.clock.engine
	var pending := {}
	for item in e.queue:
		if item[0] == "fault":
			pending[item[1]] = true
	var sig := "%s|%s|%s" % [ui.clock.scenario, str(e.faults_done.keys()), str(pending.keys())]
	if sig == _sig:
		return
	_sig = sig
	W.clear(body)
	body.add_child(W.label("Scenario", 22))
	for id in ui.info.m.scenarios:
		var sc: Dictionary = ui.info.m.scenarios[id]
		var row := HBoxContainer.new()
		body.add_child(row)
		var l := W.label(sc.get("title", id) + (" (running)" if id == ui.clock.scenario else ""), 18)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(W.button("Restart in it", func(): ui.restart(id)))
	body.add_child(W.label("Faults", 22))
	var faults := trainer_faults(e)
	if faults.is_empty():
		body.add_child(W.label("This scenario has no trainer faults.", 18, W.DIM))
	for f in faults:
		var row := HBoxContainer.new()
		body.add_child(row)
		var applied: bool = e.faults_done.has(f["id"])
		var l := W.label(f.get("text", f["id"]), 18, W.DIM if applied else Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := W.button("Applied" if applied else ("Pressed" if pending.has(f["id"]) else "Apply"), func(): ui.fault(f["id"]))
		b.disabled = applied or pending.has(f["id"])
		row.add_child(b)
