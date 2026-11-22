## The instructor's panel (docs/PLANT3D.md §7.8): the scenario to run (the plant restarts in it), and the scenario's
## trainer faults, each pressed at the moment that teaches most (applied in the next model step) and repaired when
## the lesson is over (a repaired fault can be pressed again). Shown when instructor mode is on in the settings.
## "Restart in it" asks first (issue #437; the user's UI-UX policy S1, S2): the run in progress is lost, so the row
## asks, naming the scenarios and the plant time lost, with "Keep the run" focused where "Restart in it" was and the
## destructive "Restart" below it, which can't be pressed in the first half second (a double press or a held key).
extends PanelContainer

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const W = preload("res://ui/widgets.gd")

var ui
var body: VBoxContainer
var _sig := ""
var _t := 0.0
var asking := ""                # the scenario the question is about ("" when none)
var _asked_ms := 0              # when it was asked (the destructive button waits ARM_MS)
const ARM_MS := 500


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
	asking = ""                     # (a question left when the panel closed is not asked again)
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
	var _c0 := Time.get_ticks_usec()
	_each_frame(delta)
	Cost.add(Cost.PANELS, _c0)


func _each_frame(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()


func refresh() -> void:
	var e = ui.clock.engine
	var pending := {}
	var fixing := {}
	for item in e.queue:
		if item[0] == "fault":
			pending[item[1]] = true
		elif item[0] == "repair":
			fixing[item[1]] = true
	var armed := asking != "" and Time.get_ticks_msec() - _asked_ms >= ARM_MS
	var sig := "%s|%s|%s|%s|%s|%d|%s|%s" % [ui.clock.scenario, str(e.faults_done.keys()), str(e.faults_fixed.keys()),
			str(pending.keys()), str(fixing.keys()), int(e.wx_kind) if e.ix.has("world_wx") else -1, asking, armed]
	if sig == _sig:
		return
	_sig = sig
	var fo: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_name := String(fo.name) if fo != null and body.is_ancestor_of(fo) else ""
	W.clear(body)
	body.add_child(W.label("Scenario", 22))
	for id in ui.info.m.scenarios:
		var sc: Dictionary = ui.info.m.scenarios[id]
		var row := HBoxContainer.new()
		body.add_child(row)
		var l := W.label(sc.get("title", id) + (" (running)" if id == ui.clock.scenario else ""), 18)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if asking == id:
			_question(row, id, sc, armed, focus_name)
		else:
			var rb := W.button("Restart in it", ask_restart.bind(id))
			rb.name = "restart_" + id
			row.add_child(rb)
	# the instructor's weather (REALISM.md §5.1): in a scenario with weather, one button per kind; the kind now first
	if e.ix.has("world_wx"):
		body.add_child(W.label("Weather", 22))
		var kinds: Array = ui.info.m.weather.get("kinds", [])
		var now := int(e.wx_kind)
		var cur := String(kinds[now].get("id", "")) if now >= 0 and now < kinds.size() else ""
		body.add_child(W.label("Now: " + cur.replace("_", " "), 18, W.DIM))
		var grid := HFlowContainer.new()
		body.add_child(grid)
		for k in kinds:
			var kid := String(k.get("id", ""))
			var b := W.button(kid.replace("_", " ").capitalize(), func():
				ui.weather(kid)
				refresh())
			b.disabled = kid == cur
			grid.add_child(b)
	body.add_child(W.label("Faults", 22))
	var faults := trainer_faults(e)
	if faults.is_empty():
		body.add_child(W.label("This scenario has no trainer faults.", 18, W.DIM))
	for f in faults:
		var row := HBoxContainer.new()
		body.add_child(row)
		var fid: String = f["id"]
		var fixed: bool = e.faults_fixed.has(fid)
		var active: bool = e.faults_done.has(fid) and not fixed     # applied and not repaired since
		var l := W.label(f.get("text", fid), 18, W.DIM if active else Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if active and f.has("repair"):
			var r := W.button("Repairing" if fixing.has(fid) else "Repair", func():
				ui.repair(fid)
				refresh())
			r.disabled = fixing.has(fid)
			row.add_child(r)
			continue
		var b := W.button("Applied" if active else ("Pressed" if pending.has(fid) else ("Apply again" if fixed else "Apply")),
				func():
					ui.fault(fid)
					refresh())
		b.disabled = active or pending.has(fid)
		row.add_child(b)


## "Restart in it": asks first (the run in progress is lost), unless the restart would be refused anyway (a session).
func ask_restart(id: String) -> void:
	if ui.session != null and ui.session.active():
		ui.restart(id)              # (refused, and says why)
		return
	asking = id
	_asked_ms = Time.get_ticks_msec()
	_sig = ""
	refresh()
	var keep: Button = body.find_child("keep_run", true, false)
	if keep != null:
		keep.grab_focus()
	# the question and its Restart in view (a phone at a large UI size), once the panel has laid them out
	get_tree().create_timer(0.1).timeout.connect(func():
		for n in ["confirm_restart", "restart_question"]:
			if is_inside_tree() and asking != "":
				ui._keep_in_view(body.find_child(n, true, false)))
	# the destructive button comes alive after ARM_MS (refresh() runs twice a second while the panel shows)
	get_tree().create_timer(ARM_MS / 1000.0 + 0.02).timeout.connect(func():
		if is_inside_tree() and visible and asking != "":
			refresh())


## The question in the scenario's row: "Keep the run" where "Restart in it" was (focused), the words and the
## destructive "Restart" under the row, below Keep the run.
func _question(row: HBoxContainer, id: String, sc: Dictionary, armed: bool, focus_name: String) -> void:
	var keep := W.button("Keep the run", func():
		asking = ""
		_sig = ""
		refresh()
		var back: Button = body.find_child("restart_" + id, true, false)
		if back != null:
			back.grab_focus())
	keep.name = "keep_run"
	row.add_child(keep)
	var running: Dictionary = ui.info.m.scenarios.get(ui.clock.scenario, {})
	var now := String(running.get("title", ui.clock.scenario))
	var ask := ("Restart %s from its start?" % now) if id == ui.clock.scenario \
			else ("Restart in %s?" % String(sc.get("title", id)))
	var q := W.label("%s The run in progress (%s, %s of plant time) is lost: it can't be continued or undone." \
			% [ask, now, W.model_time(ui.clock.engine.step_no)], 18)
	q.name = "restart_question"
	body.add_child(q)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(24 * W.scale))
	body.add_child(bar)
	var go := W.button("Restart", func():
		if Time.get_ticks_msec() - _asked_ms < ARM_MS:
			return
		asking = ""
		_sig = ""
		ui.restart(id)
		if visible:                 # the focus to the row's own button again, not lost with the question's
			refresh()
			var back: Button = body.find_child("restart_" + id, true, false)
			if back != null:
				back.grab_focus())
	go.name = "confirm_restart"
	go.disabled = not armed
	bar.alignment = BoxContainer.ALIGNMENT_END     # under Keep the run: Down from it goes there (its neighbours too)
	bar.add_child(go)
	W.destructive(go)
	keep.focus_neighbor_bottom = keep.get_path_to(go)
	go.focus_neighbor_top = go.get_path_to(keep)
	# a screen reader says the question with either button (AccessKit; the label alone is not focusable)
	for b in [keep, go]:
		if "accessibility_description" in b:
			b.set("accessibility_description", q.text)
	if focus_name in ["keep_run", "confirm_restart"]:
		(keep if focus_name == "keep_run" or not armed else go).grab_focus.call_deferred()
