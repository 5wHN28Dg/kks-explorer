## Procedures and tours (docs/PLANT3D.md §8) as a guided checklist: the current step's text with its links, the
## operations it expects (ticked as they are done), why it matters, the equipment it names pointed at in the plant,
## and the step ending by itself when its `done` value turns true. A tour's stops are walked or flown along with
## Next and Back. Without a procedure open the panel lists them.
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const Runs = preload("res://ui/runs.gd")
const LinksIn = preload("res://ui/links_in.gd")
const Debrief = preload("res://ui/debrief.gd")

var ui
var body: VBoxContainer
var title: Label
var pause_box: CheckBox
var fly_box: CheckBox
var _ops_label: RichTextLabel
var _dev: Label
var _next: Button
var _at_i := 0
var _t := 0.0
var _confirm := ""              # a procedure waiting for the choice "restart or follow from here"
var _offer: Array = []          # [procedure id, step id or null] a link asks for: shown, never started by itself


func setup(u) -> void:
	ui = u
	var parts := W.panel("Procedures and tours", func(): ui.close_procedure())
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	title = parts[2]
	pause_box = CheckBox.new()
	pause_box.text = "Pause when a step is done"
	pause_box.focus_mode = Control.FOCUS_ALL
	pause_box.toggled.connect(func(on): ui.clock.pause_on_hold = on)
	fly_box = CheckBox.new()
	fly_box.text = "Fly me to each stop"
	fly_box.button_pressed = true
	fly_box.focus_mode = Control.FOCUS_ALL
	visible = false


func open() -> void:
	visible = true
	rebuild()
	if ui.wants_focus():
		var b := _first(body)
		if b:
			b.grab_focus()


static func _first(n: Node) -> Control:
	for c in n.get_children():
		if (c is Button) and not c.disabled:
			return c
		var f := _first(c)
		if f:
			return f
	return null


func rebuild() -> void:
	if pause_box.get_parent():
		pause_box.get_parent().remove_child(pause_box)
	if fly_box.get_parent():
		fly_box.get_parent().remove_child(fly_box)
	W.clear(body)
	_ops_label = null
	_dev = null
	_next = null
	var tr = ui.tracker
	if not _offer.is_empty():
		_show_offer()
	elif tr == null or tr.proc.is_empty():
		_list()
	elif tr.index < 0:
		_finished()
	else:
		_step()


func _list() -> void:
	title.text = "Procedures and tours"
	var m = ui.info.m
	if _confirm != "":
		var pr: Dictionary = m.procedures[_confirm]
		var sc: Dictionary = m.scenarios.get(pr.get("scenario", ""), {})
		body.add_child(W.label(pr["title"], 22))
		body.add_child(W.label("This procedure starts from \"%s\". The plant is not there now." % sc.get("title", pr.get("scenario", "")), 18, W.DIM))
		body.add_child(W.button("Start from there (the plant restarts)", func():
			var id := _confirm
			_confirm = ""
			ui.start_procedure(id, null, true)))
		body.add_child(W.button("Follow it from here", func():
			var id := _confirm
			_confirm = ""
			ui.start_procedure(id, null, false)))
		body.add_child(W.button("Back", func(): _confirm = ""; rebuild()))
		return
	for kind in ["procedure", "tour"]:
		body.add_child(W.label("Procedures" if kind == "procedure" else "Tours", 22))
		for id in m.procedures:
			var pr: Dictionary = m.procedures[id]
			if pr.get("kind", "") != kind:
				continue
			var row := HBoxContainer.new()
			body.add_child(row)
			var l := W.label("%s (%d steps)" % [pr["title"], pr["steps"].size()], 18)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			row.add_child(W.button("Start", _start.bind(id)))
	body.add_child(W.label("Permits to work", 22))
	var pb := W.button("Open the permits", func(): ui.open_permits())
	pb.name = "permits"
	body.add_child(pb)


## A link asks for a procedure (from outside the app: it only offers, the trainee decides).
func offer(id: String, step) -> void:
	_offer = [id, step]
	open()


func _show_offer() -> void:
	var id: String = _offer[0]
	var step = _offer[1]
	var pr: Dictionary = ui.info.m.procedures[id]
	title.text = "A link opens a procedure"
	var at := "its start"
	if step != null:
		for k in pr["steps"].size():
			if pr["steps"][k]["id"] == step:
				at = "step %d of %d" % [k + 1, pr["steps"].size()]
	body.add_child(W.label("%s, at %s." % [pr["title"], at], 20))
	var tr = ui.tracker
	if tr != null and tr.index >= 0:
		body.add_child(W.label("This stops \"%s\", which is at step %d." % [tr.proc["title"], tr.index + 1], 18, Color(1.0, 0.8, 0.4)))
	body.add_child(W.button("Follow it from here", func():
		_offer = []
		ui.start_procedure(id, step, false)))
	if step == null and pr.has("scenario"):
		body.add_child(W.button("Start from its scenario (the plant restarts)", func():
			_offer = []
			ui.start_procedure(id, null, true)))
	body.add_child(W.button("Not now", func():
		_offer = []
		rebuild()))


func _start(id: String) -> void:
	var pr: Dictionary = ui.info.m.procedures[id]
	var sc = pr.get("scenario")
	var e = ui.clock.engine
	if sc != null and (ui.clock.scenario != sc or e.step_no > 0):
		_confirm = id
		rebuild()
		return
	ui.start_procedure(id, null, false)


func _step() -> void:
	var tr = ui.tracker
	var s: Dictionary = tr.current()
	title.text = "%s · %s %d of %d" % [tr.proc["title"], "stop" if tr.is_tour() else "step", tr.index + 1, tr.steps.size()]
	if tr.index == 0 and tr.proc.has("intro"):
		var intro := W.rich()
		intro.text = Runs.blocks(tr.proc["intro"])
		intro.meta_clicked.connect(_link)
		intro.modulate = W.DIM
		body.add_child(intro)
	var t := W.rich()
	t.text = "[b]%s[/b]" % Runs.run(s.get("text", []))
	t.meta_clicked.connect(_link)
	body.add_child(t)
	if s.has("do"):
		_ops_label = W.rich()
		body.add_child(_ops_label)
	if s.has("why"):
		var why := W.rich()
		why.text = "[i]Why: [/i]" + Runs.blocks(s["why"])
		why.meta_clicked.connect(_link)
		why.modulate = W.DIM
		body.add_child(why)
	var row := HBoxContainer.new()
	body.add_child(row)
	var at: Array = s.get("at", [])
	if not at.is_empty():
		row.add_child(W.button("Show me", _show_next))
		row.add_child(W.button("Go there", func(): ui.fly_to(at[_at_i % at.size()])))
		row.add_child(W.button("Card", func(): ui.open_card(at[_at_i % at.size()])))
	var row2 := HBoxContainer.new()
	body.add_child(row2)
	if tr.is_tour():
		var back := W.button("Back", func(): tr.back(ui.clock.engine))
		back.disabled = tr.index == 0
		row2.add_child(back)
	_next = null
	if tr.is_tour() or not s.has("done"):
		_next = W.button("Next", func(): tr.next(ui.clock.engine))
		_next.disabled = not tr.can_next(ui.clock.engine)
		row2.add_child(_next)
	elif s.has("done"):
		row2.add_child(W.label("Ends by itself when it is done.", 16, W.DIM, false))
	row2.add_child(W.button("Stop", func(): ui.stop_procedure()))
	if tr.is_tour():
		body.add_child(fly_box)
	else:
		body.add_child(pause_box)
		pause_box.set_pressed_no_signal(ui.clock.pause_on_hold)
	_dev = W.label("", 16, Color(1.0, 0.8, 0.4))
	body.add_child(_dev)
	refresh()


func _show_next() -> void:
	var at: Array = ui.tracker.current().get("at", [])
	if at.is_empty():
		return
	_at_i = (_at_i + 1) % at.size()
	ui.show_me(at[_at_i])


## A new step: point at the first equipment it names.
func on_step_changed() -> void:
	_at_i = 0
	if visible:
		rebuild()


func _finished() -> void:
	var tr = ui.tracker
	title.text = tr.proc["title"]
	var end: int = tr.log[tr.log.size() - 1][1] if not tr.log.is_empty() else 0
	body.add_child(W.label("Done: %s, in %s of plant time." % ["every step" if tr.begin_index == 0 else
			"step %d to the last" % (tr.begin_index + 1), W.model_time(end - tr.begin_step)], 22, W.OK_COLOUR))
	if not tr.is_tour():
		var d := Debrief.collect(ui.clock.engine, ui.info, tr)
		body.add_child(W.label("\n".join(Debrief.summary_lines(d)), 18, W.DIM))
		body.add_child(W.button("Debrief: every event", func(): ui.open_debrief()))
	body.add_child(W.button("Close the procedure", func(): ui.stop_procedure()))


func _link(meta) -> void:
	var s := String(meta)
	if s.begins_with("kks:"):
		ui.open_card(s.substr(4))
		ui.show_me(s.substr(4))
	elif s.begins_with("course:"):
		ui.toast(LinksIn.open_walkdown("course", s.substr(7)))
	else:
		ui.toast("This link opens nothing in Walkdown Plant.")


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


func refresh() -> void:
	var tr = ui.tracker
	if tr == null or tr.index < 0:
		return
	if _next != null:
		_next.disabled = not tr.can_next(ui.clock.engine)
	if _ops_label != null:
		var lines := PackedStringArray()
		var want: Array = tr.current().get("do", [])
		for k in want.size():
			var d: Dictionary = want[k]
			var done: bool = tr.is_done_op(d)
			var o = ui.info.m.op_keys.get(ui.info.m.op_key(d["kks"], d["do"], d.get("trip")))
			var what: String = ui.info.op_label(o) if o != null else String(d["do"])
			if d.has("value") and o != null:
				what += " to %s" % (("%s %%" % str(float(d["value"]) * 100.0).trim_suffix(".0")) if o["range"] == [0, 1] else str(d["value"]))
			lines.append("%s %s[url=kks:%s][color=#7fc8ff]%s[/color][/url] %s" % ["✓" if done else "·",
					("%d. " % (k + 1)) if tr.current().get("ordered", false) else "", d["kks"], d["kks"], Runs.esc(what)])
		var txt := "\n".join(lines)
		if _ops_label.text != txt:
			_ops_label.text = txt
			if not _ops_label.meta_clicked.is_connected(_link):
				_ops_label.meta_clicked.connect(_link)
	if _dev != null:
		var dl := PackedStringArray()
		for i in range(maxi(0, tr.deviations.size() - 3), tr.deviations.size()):
			dl.append("%s  %s" % [W.model_time(tr.deviations[i][0]), tr.deviations[i][1]])
		_dev.text = ("Outside the procedure:\n" + "\n".join(dl)) if not dl.is_empty() else ""
