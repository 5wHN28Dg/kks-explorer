## The work view (docs/plant3d/REALISM.md §3.3, §2.16; milestone HW2): hands-on work at a piece of equipment with jobs.
## Opened from the card's "Work on it" when the trainee's person stands at the code's work place. The plant's piece
## (built unmerged: builder/kit_place.gd `_unmerged`) is hidden and its work scene (builder/work_build.gd: the
## Workshop's component scene for that very instance, with its mounting) stands in its place, lit by the plant's
## materials; a close camera orbits it while the plant stays drawn round it. The component states come from the model
## (a cover off stands out along its explode direction; leads, probes and clamps are marks at their anchors), moving
## over a hand action's minutes. The tool tray lists the tools carried; a component tapped (or its button) lists its
## actions, sent with the tray's tool; refusals come back from the engine and are shown as sentences beside the
## component. The meters' and the HART communicator's screens show what the model's meters show. Every action is an
## input (ui/inputs.gd), so two players at one transmitter see the same.
##
## Also the tools panel: the tools carried, and at a place that keeps tools (a toolbox, a store) taking and putting
## back (`tool` inputs, REALISM.md §2.3).
extends Control

const W = preload("res://ui/widgets.gd")
const JsonStrict = preload("res://sim/json_strict.gd")
const Hands = preload("res://sim/hands.gd")

const SCENES := "res://built/work/"
const MATS := "res://built/materials/"
const SERVICE := "res://built/content/service/"
const ORBIT_MIN := 0.25
const ORBIT_MAX := 1.6

## The engine's reasons in words (REALISM.md §2.13), where the content gives no sentence of its own.
const WHY := {
	"authority": "Not yours to do: it needs the accepted permit of a work on this equipment, and you its acceptor",
	"where": "Stand at the equipment to work on it",
	"busy": "Finish what you are doing first",
	"tool": "Take the tool for it in your hand: pick it in the tray (a tool you carry)",
	"wrong_tool": "That tool doesn't do this",
	"value": "That value is outside what it takes",
	"none_left": "None left here: someone has taken it",
	"carried": "You carry one already",
	"full": "You carry 12 tools: put one back first",
	"not_carried": "You don't carry that",
	"hart": "The communicator isn't connected (or you don't carry one)",
}
## Marks for the states that put something on a component (`<component>_<state>`): colour and size.
const MARK := {"hart": [Color(1.0, 0.85, 0.1), 0.006], "dmm": [Color(0.85, 0.1, 0.1), 0.005],
	"clamp": [Color(1.0, 0.45, 0.05), 0.012], "lift": [Color(0.8, 0.45, 0.2), 0.004]}

signal opened(code: String)
signal closed

var ui                          # ui/plant_ui.gd
var jobs := {}                  # code -> {kind, alias, loop, service}
var code := ""                  # open at this code ("" closed)
var is_open := false
var scene: Node3D = null        # the work scene's instance
var load_ms := 0.0              # the last open's load (worker thread), ms
var mem_added := 0              # static memory the last open added (bytes)
var tool_sel := ""              # the tray's tool: "" bare hands
var comp := ""                  # the component picked
var last_text := ""             # the last refusal or result shown (tests read it)
var _piece: Node3D = null       # the plant's piece hidden while open
var _labels: Array = []         # the labels near it hidden while open (codes, values, plates: huge seen this close)
var meters_panel: PanelContainer
var _cam: Camera3D = null
var _yaw := 0.6
var _pitch := -0.25
var _dist := 0.6
var _target := Vector3.ZERO
var _path := ""
var _t_req := 0
var _mem0 := 0
var _comp_nodes := {}           # component id -> Node3D
var _home := {}                 # component id -> its position at home
var _offs := {}                 # component id -> the offset now (moved toward its target each frame)
var _marks := {}                # state name -> [Node3D marks]
var _say: Label3D = null
var _say_t := 0.0
var _drag := false
var _moved := 0.0
var _sig := ""
var _ev_seen := 0
# the panel
var panel: PanelContainer
var body: VBoxContainer
var title: Label
var tray: HFlowContainer
var parts: HFlowContainer
var actions: VBoxContainer
var meters: VBoxContainer
var note: Label
var busy_l: Label
var trim_entry: LineEdit = null
# the tools panel
var tools_panel: PanelContainer
var tools_body: VBoxContainer
var _tools_sig := ""


func setup(u) -> void:
	ui = u
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_read_jobs()
	var p := W.panel("", close)
	panel = p[0]
	body = p[1]
	title = p[2]
	panel.name = "work_panel"
	add_child(panel)
	panel.visible = false
	tray = HFlowContainer.new()
	tray.name = "tray"
	parts = HFlowContainer.new()
	parts.name = "parts"
	actions = VBoxContainer.new()
	actions.name = "actions"
	meters = VBoxContainer.new()
	meters.name = "meters"
	note = W.label("", 18, W.BAD_COLOUR)
	note.name = "note"
	busy_l = W.label("", 18, W.OK_COLOUR)
	busy_l.name = "busy"
	for x in [W.label("In your hand", 20), tray, W.label("Parts (or tap one)", 20), parts, busy_l, note, actions]:
		body.add_child(x)
	# the meters' and the communicator's screens: a panel of their own, low in the middle, always in view
	meters_panel = PanelContainer.new()
	meters_panel.name = "meters_panel"
	meters_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	meters_panel.add_child(meters)
	add_child(meters_panel)
	meters_panel.visible = false
	var tp := W.panel("Tools", close_tools)
	tools_panel = tp[0]
	tools_body = tp[1]
	tools_panel.name = "tools_panel"
	add_child(tools_panel)
	tools_panel.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(480.0 * W.scale, vs.x * 0.45)
	panel.position = Vector2(vs.x - w - 12, 12)
	panel.size = Vector2(w, vs.y - 24)
	var mw := minf(560.0 * W.scale, vs.x - w - 36)
	meters_panel.position = Vector2(maxf(12.0, (vs.x - w - 12) * 0.5 - mw * 0.5), vs.y - 12)
	meters_panel.custom_minimum_size.x = mw
	meters_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tools_panel.position = Vector2(12, 150 * W.scale)
	tools_panel.size = Vector2(minf(440.0 * W.scale, vs.x * 0.45), minf(560.0 * W.scale, vs.y - 170 * W.scale))


## The codes with jobs and their service files (built/content/service/, REALISM.md §2.16).
func _read_jobs() -> void:
	jobs.clear()
	var d := DirAccess.open(SERVICE)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var r := JsonStrict.parse(FileAccess.get_file_as_bytes(SERVICE + f))
		if not r.get("ok", false):
			push_warning("service/%s: %s" % [f, r.get("error", "")])
			continue
		var s: Dictionary = r["value"]
		for e in s.get("equipment", []):
			jobs[String(e["kks"])] = {"kind": String(s["part"]), "alias": String(e["alias"]), "loop": String(e["loop"]),
				"service": s}


func has_job(c: String) -> bool:
	return jobs.has(c) and ResourceLoader.exists(SCENES + c + ".scn")


## Why the trainee can't work on it now ("" when they can): a person played, standing at its work place.
func cannot(c: String) -> String:
	var e = ui.clock.engine
	if e == null or e._sm == null or ui.my_person() == -1:
		return "Take a role (Crew) to work on it"
	var at: int = e.t_at(ui.inputs.slot)
	if not e._sm.work_places.get(c, []).has(at):
		return "Stand at it to work on it"
	return ""


## Opens the view at a code: the scene loads on a worker thread (`load_ms`); false when it can't open.
func open(c: String) -> bool:
	if not has_job(c) or cannot(c) != "":
		return false
	if is_open:
		close()
	code = c
	is_open = true
	tool_sel = ""
	comp = ""
	last_text = ""
	_path = SCENES + c + ".scn"
	_mem0 = _mem()
	_t_req = Time.get_ticks_usec()
	var n = ui.index.nodes.get(c)
	if n != null:
		_target = (n as Node3D).global_position   # (until the scene is placed: _place aims at its box's centre)
	if ResourceLoader.load_threaded_request(_path, "PackedScene") != OK:
		_path = ""
		_place(load(SCENES + c + ".scn"))
	title.text = "%s  %s" % [c, ui.info.name_of(c)]
	panel.visible = true
	ui.close_card()
	ui.close_crew()
	_cam = Camera3D.new()
	_cam.name = "work_camera"
	_cam.near = 0.02
	_cam.fov = 55.0
	ui.main.add_child(_cam)
	_cam.make_current()
	_orbit_cam()
	_sig = ""
	_ev_seen = ui.clock.engine.events.size()
	refresh()
	if ui.main.hud != null:
		ui.main.hud.refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit(c)
	return true


## Waits (frames) until the scene is placed: true once it stands in the plant.
func loaded() -> bool:
	return scene != null


func _place(ps: PackedScene) -> void:
	_path = ""
	if ps == null or not is_open:
		return
	load_ms = (Time.get_ticks_usec() - _t_req) / 1000.0
	scene = ps.instantiate()
	var n = ui.index.nodes.get(code)
	ui.main.add_child(scene)
	if n != null:
		scene.global_transform = (n as Node3D).global_transform
		_piece = (n as Node3D).get_node_or_null("piece")
		if _piece != null:
			_piece.visible = false
		_labels.clear()
		for c in ui.index.nodes:
			var o: Node3D = ui.index.nodes[c]
			if o.global_position.distance_to(n.global_position) < 3.0:
				for l in o.find_children("*", "Label3D", true, false):
					if (l as Label3D).visible:
						_labels.append(l)
						(l as Label3D).visible = false
	_comp_nodes.clear()
	_home.clear()
	_offs.clear()
	_marks.clear()
	var stack: Array = [scene]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		stack.append_array(x.get_children())
		if x.has_meta("mat"):
			var m = load(MATS + String(x.get_meta("mat")) + ".tres")
			if m != null:
				(x as GeometryInstance3D).material_override = m
		if x is MultiMeshInstance3D:
			var items: Array = x.get_parent().get_meta("items", [])
			# its own MultiMesh made new, not the cached scene's (a duplicate's buffer is set before its count: Godot
			# refused it, "Cannot set a buffer on a Multimesh that is a different size"), as the Workshop's warm-up does
			(x as MultiMeshInstance3D).multimesh = _items_multimesh((x as MultiMeshInstance3D).multimesh, items)
		if x is Node3D and x.has_meta("id") and x.has_meta("explode"):
			_comp_nodes[String(x.get_meta("id"))] = x
			_home[String(x.get_meta("id"))] = (x as Node3D).position
	var box: AABB = scene.get_meta("box", AABB())
	if box.size != Vector3.ZERO:
		_target = scene.global_transform * box.get_center()
		_dist = clampf(box.size.length() * 1.5, ORBIT_MIN, ORBIT_MAX)
	_make_marks()
	_say = Label3D.new()
	_say.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_say.pixel_size = 0.0004
	_say.font_size = 32
	_say.outline_size = 8
	_say.modulate = Color(1, 0.55, 0.5)
	_say.width = 900
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.no_depth_test = true
	_say.visible = false
	scene.add_child(_say)
	mem_added = _mem() - _mem0
	_orbit_cam()
	_apply_states(true)
	_sig = ""                   # (the parts' names: the scene's words)


func close() -> void:
	if not is_open:
		return
	is_open = false
	if _path != "":
		ResourceLoader.load_threaded_get(_path)     # (let the request end)
		_path = ""
	if scene != null:
		scene.queue_free()
		scene = null
	if _piece != null and is_instance_valid(_piece):
		_piece.visible = true
	_piece = null
	for l in _labels:
		if is_instance_valid(l):
			(l as Label3D).visible = true
	_labels.clear()
	meters_panel.visible = false
	if _cam != null:
		_cam.queue_free()
		_cam = null
	ui.player.camera.make_current()
	panel.visible = false
	code = ""
	if ui.main.hud != null:
		ui.main.hud.refresh()
	closed.emit()


# ------------------------------------------------------------------ each frame

func _process(delta: float) -> void:
	if _path != "":
		var st := ResourceLoader.load_threaded_get_status(_path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_place(ResourceLoader.load_threaded_get(_path))
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_path = ""
			close()
			ui.toast("The work view did not load")
			return
	if tools_panel.visible:
		_refresh_tools()
	if not is_open:
		return
	if cannot(code) != "":
		close()                 # walked away, the role gone: the view ends (a hand action under way is abandoned)
		return
	refresh()
	_apply_states(false, delta)
	if _say != null and _say.visible:
		_say_t -= delta
		if _say_t <= 0.0:
			_say.visible = false


## The panel rebuilt when what it shows changed; the meters' values written every time.
func refresh() -> void:
	var e = ui.clock.engine
	var pid = ui.me()
	if tool_sel != "" and not e.carried.get(pid, []).has(tool_sel):
		tool_sel = ""   # (put back, or another person played: the tray's choice goes with the tool)
	var sig := "%s|%s|%s|%s|%s" % [str(e.carried.get(pid, [])), tool_sel, comp, _step_sig(e), e.busy.get(pid, [])]
	if sig != _sig:
		_sig = sig
		_build_tray(e, pid)
		_build_parts()
		_build_actions(e)
		_build_meters(e, pid)
	_write_meters(e, pid)
	var b = e.busy.get(pid)
	if b != null and b[0] == code:
		var x: Dictionary = e.m.hands_ix[b[0] + "|" + b[1]]
		var start: float = float(b[4]) - ceilf(float(x["minutes"]) * Hands.MINUTE)
		var f := clampf((e.clock() - start) / maxf(float(b[4]) - start, 1.0), 0.0, 1.0)
		busy_l.text = "%s… %d %%" % [_action_title(String(b[1])), int(f * 100.0)]
	else:
		busy_l.text = ""


func _step_sig(e) -> String:
	var s = _my_step(e)
	return str(s) if s != null else ""


## The trainee's current task step (its definition), or null.
func _my_step(e):
	var pi: int = ui.my_person()
	if pi == -1 or e._sm == null:
		return null
	var c = e.sp_cur[pi]
	if c == null:
		return null
	return e._sm.tasks[c["task"]]["steps"][c["step"]]


func _build_tray(e, pid) -> void:
	W.clear(tray)
	var hands := W.button("Bare hands", func(): pick_tool(""))
	hands.name = "tool_"
	hands.toggle_mode = true
	hands.button_pressed = tool_sel == ""
	tray.add_child(hands)
	for t in e.carried.get(pid, []):
		var tt: String = t
		var b := W.button(_tool_title(e, tt), func(): pick_tool(tt))
		b.name = "tool_" + tt
		b.toggle_mode = true
		b.button_pressed = tool_sel == tt
		tray.add_child(b)


func _build_parts() -> void:
	W.clear(parts)
	for c in _service_comps():
		var cc: String = c
		var b := W.button(_comp_name(cc), func(): pick_comp(cc))
		b.name = "part_" + cc
		b.toggle_mode = true
		b.button_pressed = comp == cc
		parts.add_child(b)


func _build_actions(e) -> void:
	W.clear(actions)
	if comp == "":
		return
	actions.add_child(W.label(_comp_name(comp), 20))
	for a in _service()["actions"]:
		if a["component"] != comp:
			continue
		var act: String = a["action"]
		var b := W.button(String(a["title"]), func(): do_action(act))
		b.name = "act_" + act
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actions.add_child(b)


## The meters of this code whose tool the person carries (its kind, with the meter's mode).
func _my_meters(e, pid) -> Array:
	var out: Array = []
	for mt in _service()["meters"]:
		var id: String = _name(String(mt["id"]))
		if e.m.meters_ix.has(id) and Hands.carries_kind(e, pid, String(mt["tool_kind"]), String(mt["mode"])):
			out.append([id, mt])
	return out


func _build_meters(e, pid) -> void:
	W.clear(meters)
	trim_entry = null
	var mine := _my_meters(e, pid)
	meters_panel.visible = not mine.is_empty() and is_open
	if mine.is_empty():
		return
	meters.add_child(W.label("Readings", 20))
	var step = _my_step(e)
	for x in mine:
		var id: String = x[0]
		var mt: Dictionary = x[1]
		var box := PanelContainer.new()
		box.name = "meter_" + id
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.12, 0.08, 0.95) if mt["tool_kind"] != "communicator" else Color(0.06, 0.08, 0.14, 0.95)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		box.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		box.add_child(v)
		v.add_child(W.label(String(mt["title"]), 16, W.DIM))
		var val := W.label("", 28, Color(0.6, 1.0, 0.6) if mt["tool_kind"] != "communicator" else Color(0.7, 0.85, 1.0))
		val.name = "value"
		v.add_child(val)
		if step != null and step.has("read") and step.get("via", "") == id and step["read"] == code:
			var rb := W.button("Report this reading", func(): report(id))
			rb.name = "report_" + id
			v.add_child(rb)
		meters.add_child(box)
	# the communicator's configuration: the sensor trim (REALISM.md §2.16), its op where "hart"
	if Hands.carries_kind(e, pid, "communicator", "hart"):
		for o in e.m.ops:
			if o["kks"] == code and o.get("where", []).has("hart") and o.has("input"):
				var row := HBoxContainer.new()
				row.name = "trim"
				trim_entry = LineEdit.new()
				trim_entry.name = "trim_ref"
				trim_entry.placeholder_text = "reference kPa(a)"
				trim_entry.custom_minimum_size.x = 170 * W.scale
				row.add_child(trim_entry)
				var od: Dictionary = o
				var tb := W.button("Sensor trim", func(): trim(od, trim_entry.text))
				tb.name = "trim_apply"
				row.add_child(tb)
				meters.add_child(row)
				break


func _write_meters(e, pid) -> void:
	for x in _my_meters(e, pid):
		var box := meters.get_node_or_null("meter_" + String(x[0]))
		if box == null:
			continue
		var l: Label = box.find_child("value", true, false)
		l.text = meter_text(e, String(x[0]), x[1])


## What a meter's screen shows now (the model's meter, REALISM.md §2.5): its value, or the communicator's "No device
## found" when its needs fail.
func meter_text(e, id: String, mt: Dictionary) -> String:
	var x: Dictionary = e.m.meters_ix[id]
	var ok := true
	for nd in x.get("needs", []):
		ok = ok and e.cur[e.ix[nd]] >= 0.5
	if not ok and mt["tool_kind"] == "communicator":
		return "No device found"
	var v: float = Hands.shown(e, id, e.cur)
	return "%.2f %s" % [v, String(mt.get("unit", ""))]


# ------------------------------------------------------------------ what the trainee does

func pick_tool(t: String) -> void:
	tool_sel = t
	_sig = ""


func pick_comp(c: String) -> void:
	comp = c
	_sig = ""


## A MultiMesh of its own holding a scene's items (workshop.gd's _items_multimesh).
static func _items_multimesh(src: MultiMesh, items: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = src.transform_format
	mm.use_colors = src.use_colors
	mm.use_custom_data = src.use_custom_data
	mm.mesh = src.mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i])
	return mm


## A hand action sent with the tray's tool (bare hands: none).
func do_action(action: String) -> int:
	var t = tool_sel if tool_sel != "" else null
	note.text = ""
	return ui.inputs.hand(code, action, t, null, ui.me())


## The reading reported for the task step that waits on it (S1's read with the meter, REALISM.md §2.5).
func report(meter: String) -> int:
	var e = ui.clock.engine
	return ui.inputs.read(code, snappedf(Hands.shown(e, meter, e.cur), 0.01), meter)


## The sensor trim: the trim that brings the PV to the reference typed in (the op's value, within its range).
func trim(o: Dictionary, text: String) -> int:
	var t := text.strip_edges().replace(",", ".")
	if not t.is_valid_float():
		_show("Type the reference pressure the PV should read")
		return -1
	var e = ui.clock.engine
	var pv_id := ""
	for mt in _service()["meters"]:
		if mt["tool_kind"] == "communicator" and String(mt["value"]) == "@_tx":
			pv_id = _name(String(mt["id"]))
	if pv_id == "" or not e.m.meters_ix.has(pv_id):
		return -1
	if meter_text(e, pv_id, e.m.meters_ix[pv_id]) == "No device found":
		_show("No device found: the communicator reads no PV to trim against")   # (a dead loop: no HART reply)
		return -1
	var have: float = e.cur[e.ix[o["input"]]]
	var v: float = have + t.to_float() - Hands.shown(e, pv_id, e.cur)
	v = clampf(snappedf(v, 0.01), float(o["range"][0]), float(o["range"][1]))
	return ui.inputs.op(code, "set", v, null, "hart", ui.me())


## The engine's events since the last look (ui/plant_ui.gd passes them on): this person's hand actions, tools and
## HART ops refused, in words beside the component.
func on_events(evs: Array, from: int) -> void:
	var pid = ui.me()
	if pid == null:
		return
	for i in range(from, evs.size()):
		var ev: Array = evs[i]
		match ev[1]:
			"hand":
				if ev[5] != pid:
					continue
				if ev[6] == "refused":
					var x = ui.clock.engine.m.hands_ix.get(str(ev[2]) + "|" + str(ev[3]))
					if ui.monitoring != null and ui.monitoring.handles(str(ev[2]), str(ev[3])):
						continue        # (an oil sample's: the monitoring view says why, once)
					var why := PackedStringArray()
					for r in ev[7]:
						why.append(hand_reason(x, String(r), ev[4]))
					_show("; ".join(why), String(x["component"]) if x != null else "")
				elif ev[6] == "done" and ev[2] == code:
					last_text = "Done: " + _action_title(String(ev[3]))
					note.text = ""
			"tool":
				if ev[4] == pid and ev[5] == "refused":
					var why := PackedStringArray()
					for r in ev[6]:
						why.append(WHY.get(String(r), String(r)))
					_show("; ".join(why))
			"op":
				if ev[2] == code and ev.size() >= 8 and ev[7] == pid and ev[4] == "refused":
					var o: Dictionary = {}
					for x in ui.clock.engine.m.ops:
						if x["kks"] == code and x["do"] == ev[3]:
							o = x
					var why := PackedStringArray()
					for f in ev[5]:
						why.append(WHY["hart"] if f == "hart" else ui.info.failed_text(o, f, ui.clock.engine))
					_show("; ".join(why))


## A refusal's reason in words: the hand action's own sentences (`wrong` for that tool, a need's) first.
static func hand_reason(x, r: String, tool) -> String:
	if x != null:
		if r == "wrong_tool" and tool != null and x.get("wrong", {}).has(tool):
			return String(x["wrong"][tool])
		for nd in x.get("needs", []):
			if nd[0] == r:
				return String(nd[1])
	return WHY.get(r, r)


func _show(text: String, at_comp := "") -> void:
	last_text = text
	note.text = text
	if not is_open:
		ui.toast(text)
		return
	if _say != null:
		var n: Node3D = _comp_nodes.get(at_comp if at_comp != "" else comp)
		_say.text = text
		_say.global_position = (n.global_position if n != null else _target) + Vector3.UP * 0.07
		_say.visible = true
		_say_t = 6.0


# ------------------------------------------------------------------ the scene: states, marks, camera

## Each component's offset from the model's states: a state `off` moves it out along its explode direction (by its
## distance); while the person's hand action on it is under way, it moves there over the action's minutes.
func _apply_states(snap: bool, delta := 0.0) -> void:
	if scene == null:
		return
	var e = ui.clock.engine
	var a: String = jobs[code]["alias"]
	var pid = ui.me()
	var b = e.busy.get(pid) if pid != null else null
	for c in _comp_nodes:
		var on := false
		var nm := "%s_%s_off" % [a, c]
		if e.ix.has(nm):
			on = e.cur[e.ix[nm]] >= 0.5
		var f := 1.0 if on else 0.0
		if b != null and b[0] == code:          # under way: from where it is to where the action leaves it
			var x: Dictionary = e.m.hands_ix[b[0] + "|" + b[1]]
			if x["component"] == c and x.get("set", {}).has(nm):
				var start: float = float(b[4]) - ceilf(float(x["minutes"]) * Hands.MINUTE)
				var p := clampf((e.clock() - start) / maxf(float(b[4]) - start, 1.0), 0.0, 1.0)
				f = lerpf(f, float(x["set"][nm]), p)
		var ex: Array = _comp_nodes[c].get_meta("explode", [Vector3.ZERO, 0.0])
		var want: Vector3 = (ex[0] as Vector3) * float(ex[1]) * f
		var now: Vector3 = _offs.get(c, want)
		now = want if snap else now.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
		_offs[c] = now
		(_comp_nodes[c] as Node3D).position = _home[c] + now
	for st in _marks:
		var on: bool = e.ix.has(st) and e.cur[e.ix[st]] >= 0.5
		for m in _marks[st]:
			m.visible = on


## Small marks at the anchors where a state puts something (the actions that set it name the anchors): the
## communicator's clips, the multimeter's probes, the clamp, a lifted wire's end.
func _make_marks() -> void:
	var a: String = jobs[code]["alias"]
	for x in _service()["states"]:
		var c: String = x[0]
		var st: String = x[1]
		if not MARK.has(st) or not _comp_nodes.has(c):
			continue
		var nm := "%s_%s_%s" % [a, c, st]
		var host: Node3D = _comp_nodes[c]
		var anchors: Dictionary = host.get_meta("anchors", {})
		var at: Array = []
		for act in _service()["actions"]:
			if act["component"] == c and act["set"].get("$_%s_%s" % [c, st], 0) == 1:
				for an in act.get("anchors", []):
					if anchors.has(an):
						at.append(anchors[an])
		if at.is_empty():
			at.append(Vector3.ZERO)
		var col: Color = MARK[st][0]
		var r: float = MARK[st][1]
		var list: Array = []
		for p in at:
			var mi := MeshInstance3D.new()
			mi.name = "mark_%s" % st
			if st == "clamp":
				var tm := TorusMesh.new()
				tm.inner_radius = r * 0.7
				tm.outer_radius = r
				mi.mesh = tm
			else:
				var sm := SphereMesh.new()
				sm.radius = r
				sm.height = r * 2.0
				sm.radial_segments = 8
				sm.rings = 4
				mi.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.roughness = 0.6
			mi.material_override = mat
			mi.position = (p as Vector3) + (Vector3(-0.012, 0, 0) if st == "lift" else Vector3.ZERO)
			mi.visible = false
			host.add_child(mi)
			list.append(mi)
		_marks[nm] = list


func _orbit_cam() -> void:
	if _cam == null:
		return
	var dir := Vector3(cos(_pitch) * sin(_yaw), -sin(_pitch), cos(_pitch) * cos(_yaw))
	_cam.global_position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)


## Mouse and touch on the view (not on a panel): a drag orbits, the wheel or a pinch zooms, a tap picks a component.
func _unhandled_input(ev: InputEvent) -> void:
	if not is_open:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist * 0.9, ORBIT_MIN, ORBIT_MAX); _orbit_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist / 0.9, ORBIT_MIN, ORBIT_MAX); _orbit_cam()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_moved = 0.0
			else:
				_drag = false
				if _moved < 8.0:
					tap(mb.position)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and _drag:
		var mm := ev as InputEventMouseMotion
		_moved += mm.relative.length()
		_turn(mm.relative)
		get_viewport().set_input_as_handled()
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_moved += sd.relative.length()
		_turn(sd.relative)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMagnifyGesture:
		_dist = clampf(_dist / (ev as InputEventMagnifyGesture).factor, ORBIT_MIN, ORBIT_MAX); _orbit_cam()
	elif ev.is_action_pressed("look_left") or ev.is_action_pressed("move_left"):
		_turn(Vector2(-40, 0))
	elif ev.is_action_pressed("look_right") or ev.is_action_pressed("move_right"):
		_turn(Vector2(40, 0))
	elif ev.is_action_pressed("look_up") or ev.is_action_pressed("move_forward"):
		_turn(Vector2(0, -30))
	elif ev.is_action_pressed("look_down") or ev.is_action_pressed("move_back"):
		_turn(Vector2(0, 30))


func _turn(rel: Vector2) -> void:
	_yaw -= rel.x * 0.008
	_pitch = clampf(_pitch + rel.y * 0.008, -1.3, 1.3)
	_orbit_cam()


## The component under a screen point (the nearest whose meshes' box the ray meets), picked; "" for none.
func tap(at: Vector2) -> String:
	if _cam == null or scene == null:
		return ""
	var o := _cam.project_ray_origin(at)
	var d := _cam.project_ray_normal(at)
	var best := ""
	var bd := INF
	var want := _service_comps()
	for c in _comp_nodes:
		if not want.has(c):
			continue
		for m in (_comp_nodes[c] as Node).get_children():
			if not m is MeshInstance3D or not m.name.begins_with("mesh"):
				continue
			var box: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			var hit = box.grow(0.004).intersects_ray(o, d)
			if hit != null and o.distance_to(hit) < bd:
				bd = o.distance_to(hit)
				best = c
	if best != "":
		pick_comp(best)
	return best


# ------------------------------------------------------------------ the tools panel

func toggle_tools() -> void:
	if tools_panel.visible:
		close_tools()
	else:
		tools_panel.visible = true
		_tools_sig = ""
		_refresh_tools()


func close_tools() -> void:
	tools_panel.visible = false


## The tools kept at the person's place (with how many are left there), and the tools they carry.
func _refresh_tools() -> void:
	var e = ui.clock.engine
	var pid = ui.me()
	var at: int = e.t_at(ui.inputs.slot) if pid != null else -1
	var place: String = e._sm.places[at]["id"] if at >= 0 and e._sm != null else ""
	var tools = e.m.tools
	var sig := "%s|%s|%s|%s" % [str(pid), place, str(e.carried.get(pid, [])), str(e.tool_n)]
	if sig == _tools_sig:
		return
	_tools_sig = sig
	W.clear(tools_body)
	if tools == null:
		tools_body.add_child(W.label("This plant has no tools.", 18, W.DIM))
		return
	if pid == null:
		tools_body.add_child(W.label("Take a role (Crew) to carry tools.", 18, W.DIM))
		return
	var have: Array = e.carried.get(pid, [])
	tools_body.add_child(W.label("You carry: " + (", ".join(have.map(func(t): return _tool_title(e, t)))
			if not have.is_empty() else "nothing"), 18))
	var any := false
	for ti in tools["list"].size():
		var t: Dictionary = tools["list"][ti]
		var k := -1
		for j in tools["at"][ti].size():
			if int(tools["at"][ti][j][0]) == at:
				k = j
		if k == -1:
			continue
		if not any:
			tools_body.add_child(W.label("Kept here (%s)" % place.replace("_", " "), 20))
			any = true
		var row := HBoxContainer.new()
		row.name = "row_" + String(t["id"])
		tools_body.add_child(row)
		var l := W.label("%s  (%d here)" % [t["title"], int(e.tool_n[ti][k])], 17, Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var id: String = t["id"]
		var b := W.button("Put back" if have.has(id) else "Take", func(): take(id, 0 if have.has(id) else 1))
		b.name = ("back_" if have.has(id) else "take_") + id
		row.add_child(b)
	if not any:
		tools_body.add_child(W.label("No tools are kept here: they are at a toolbox or the store.", 17, W.DIM))


func take(t: String, on: int) -> int:
	_tools_sig = ""
	return ui.inputs.tool(t, on, ui.me())


# ------------------------------------------------------------------ helpers

## The memory the view can add to: the engine's own and the GPU's (textures and buffers), bytes.
static func _mem() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC)) + int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))


func _service() -> Dictionary:
	return jobs[code]["service"] if jobs.has(code) else {"actions": [], "meters": [], "states": []}


## The service file's `$_`/`@_` name for this code.
func _name(n: String) -> String:
	return n.replace("$_", jobs[code]["alias"] + "_").replace("@_", jobs[code]["loop"] + "_")


func _service_comps() -> Array:
	var out: Array = []
	for a in _service()["actions"]:
		if not out.has(a["component"]):
			out.append(a["component"])
	return out


func _comp_name(c: String) -> String:
	if scene != null:
		var words: Dictionary = scene.get_meta("workshop", {})
		return String(words.get("components", {}).get(c, {}).get("name", c))
	return c.replace("_", " ")


func _action_title(action: String) -> String:
	for a in _service()["actions"]:
		if a["action"] == action:
			return String(a["title"])
	return action.replace("_", " ")


func _tool_title(e, t: String) -> String:
	var tools = e.m.tools
	if tools == null or not tools["ix"].has(t):
		return t
	return String(tools["list"][tools["ix"][t]]["title"])
