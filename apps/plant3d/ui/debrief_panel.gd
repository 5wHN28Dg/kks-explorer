## The debrief panel (ui/debrief.gd): the run's summary (time, steps, operations, deviations, alarms, trips) over
## its events in order with their model time; Deviations and Alarms-and-trips narrow the list. Opened at the end of a
## procedure and from the alarm list (its Events button) during a run. Every row is a button, so keyboard and gamepad
## move through the list (the list scrolls to follow); a row naming equipment opens its card. While open it follows
## the run, adding new rows as events come (never rebuilding the list for them).
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const Debrief = preload("res://ui/debrief.gd")
const DEV_COLOUR := Color(1.0, 0.8, 0.4)

var ui
var body: VBoxContainer
var title: Label
var tab := "all"                # all, deviations, alarms
var data := {}                  # the last Debrief.collect
var _summary: Label
var _list: VBoxContainer
var _shown := 0                 # entries of the tab shown so far
var _events := -1               # the event list's length when last collected
var _tabs := {}
var _t := 0.0


func setup(u) -> void:
	ui = u
	var parts := W.panel("Debrief", func(): ui.close_debrief())
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	title = parts[2]
	(body.get_parent() as ScrollContainer).follow_focus = true
	var bar := HFlowContainer.new()
	v.add_child(bar)
	v.move_child(bar, 1)
	for t in [["all", "Everything"], ["deviations", "Deviations"], ["alarms", "Alarms and trips"]]:
		var b := W.button(t[1], _tab.bind(t[0]))
		b.toggle_mode = true
		bar.add_child(b)
		_tabs[t[0]] = b
	_summary = W.label("", 18)
	body.add_child(_summary)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(2 * W.scale))
	body.add_child(_list)
	visible = false


func open() -> void:
	visible = true
	_events = -1
	_shown = 0
	refresh(true)
	if ui.wants_focus():
		(_tabs[tab] as Button).grab_focus()


func _tab(t: String) -> void:
	tab = t
	refresh(true)


static func in_tab(e: Dictionary, t: String) -> bool:
	match t:
		"deviations": return e.dev != ""
		"alarms": return e.kind in ["alarm", "shelve", "unshelve", "trip"]
	return true


func entries() -> Array:
	return data.get("entries", []).filter(func(e): return in_tab(e, tab))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()


## Collects the run again when events came (or `full`); rows are added for new entries, the list rebuilt only when
## the tab changed or an entry before the last shown changed (a step that ended among them).
func refresh(full := false) -> void:
	if not visible or ui.clock == null:
		return
	for t in _tabs:
		(_tabs[t] as Button).set_pressed_no_signal(t == tab)
	var e = ui.clock.engine
	var tr = ui.debrief_tracker()
	if tr != null and tr.ev_to != -1 and _events == -2 and not full:
		return                      # an ended procedure's debrief no longer changes
	var n: int = e.events.size() + (tr.log.size() + tr.deviations.size() if tr != null else 0)
	if n == _events and not full:
		return
	_events = -2 if tr != null and tr.ev_to != -1 else n
	var old: Array = entries() if not full else []
	data = Debrief.collect(e, ui.info, tr)
	title.text = data.title
	_summary.text = "\n".join(Debrief.summary_lines(data))
	var list := entries()
	# the run only grows at its end (a step's end and a deviation come with the events of their model step), so
	# the rows shown stay as they are when the last one shown is unchanged: no comparison of every row
	var same := not full and list.size() >= _shown and old.size() >= _shown
	if same and _shown > 0:
		var a: Dictionary = list[_shown - 1]
		var b: Dictionary = old[_shown - 1]
		same = a.step == b.step and a.text == b.text and a.dev == b.dev
	if not same:
		var focus_i := _focused_row()
		W.clear(_list)
		_shown = 0
		_add_rows(list)
		if focus_i >= 0 and _list.get_child_count() > 0:
			(_list.get_child(mini(focus_i, _list.get_child_count() - 1)) as Control).grab_focus()
	else:
		_add_rows(list)


func _focused_row() -> int:
	var fo := get_viewport().gui_get_focus_owner()
	if fo != null and fo.get_parent() == _list:
		return fo.get_index()
	return -1


func _add_rows(list: Array) -> void:
	if list.is_empty() and _list.get_child_count() == 0:
		var none: String = {"all": "Nothing has happened yet.", "deviations": "No operation outside its step.",
				"alarms": "No alarm or trip."}[tab]
		_list.add_child(_row({"step": -1, "kind": "", "text": none, "code": "", "dev": "", "prio": 0}))
		return
	if not list.is_empty() and _shown == 0 and _list.get_child_count() > 0:
		W.clear(_list)              # the "nothing yet" row
	for i in range(_shown, list.size()):
		var r := _row(list[i])
		_list.add_child(r)
		var k := _list.get_child_count()
		if k > 1:                   # up and down go row by row, whatever the layout (a wrapped row is taller)
			var above: Control = _list.get_child(k - 2)
			above.focus_neighbor_bottom = above.get_path_to(r)
			r.focus_neighbor_top = r.get_path_to(above)
	_shown = list.size()


## One event as a row: its model time and text; a deviation in its own colour on a line of its own.
func _row(e: Dictionary) -> Button:
	var t: String = ("%s  %s" % [W.model_time(e.step), e.text]) if e.step >= 0 else e.text
	if e.dev != "":
		t += "\n" + e.dev
	var b := W.button(t, func(): _press(e))
	b.flat = e.dev == "" and e.kind not in ["trip", "step", "start"]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 40 * W.scale)
	b.add_theme_font_size_override("font_size", int(17 * W.scale))
	var c := Color.WHITE
	if e.dev != "":
		c = DEV_COLOUR
	elif e.kind == "trip":
		c = W.PRIO_COLOURS[1]
	elif e.kind == "alarm" and e.text.begins_with("Alarm raised"):
		c = W.PRIO_COLOURS.get(e.prio, Color.WHITE)
	elif e.kind == "step" or e.kind == "start":
		c = W.OK_COLOUR
	elif e.kind == "machine" or e.kind == "interlock":
		c = W.DIM
	for k in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, c)
	b.set_meta("entry", e)
	return b


func _press(e: Dictionary) -> void:
	if e.code != "" and ui.info.has_code(e.code):
		ui.open_card(e.code)
