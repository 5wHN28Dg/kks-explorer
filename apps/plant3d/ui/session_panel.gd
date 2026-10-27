## Together: multiplayer on this Wi-Fi (docs/plant3d/MULTIPLAYER.md, milestone MP2). Before a session: the player's
## name, host a session of a scenario (or continue the host's saved session), join one by its code (and, when the
## network keeps devices apart, the host's address), continue alone from the last session's copy. In a session: the
## code in its four groups, its link and QR code (a phone's camera app opens the link, decision 0056), this device's
## address, the players with their roles and states, the roles still free to claim, the host's Start and instructor
## seats, a player's Ready, Ready for fast-forward, and Leave (or End for the host). Every control is a button or a line
## edit that takes the focus (touch, keyboard and gamepad).
extends PanelContainer

const Cost = preload("res://app/script_cost.gd")
const W = preload("res://ui/widgets.gd")
const Code = preload("res://net/code.gd")
const QR = preload("res://net/qr.gd")
const Session = preload("res://net/session.gd")
const Snapshot = preload("res://net/snapshot.gd")
const Quality = preload("res://app/quality.gd")

const HOST_SAVE := "user://mp-host.save"
const LAST_SAVE := "user://mp-last.save"

var ui                          # ui/plant_ui.gd
var body: VBoxContainer
var title: Label
var name_edit: LineEdit
var code_edit: LineEdit
var addr_edit: LineEdit
var scen: OptionButton
var _scen_ids: Array = []
var _sig := ""
var _t := 0.0
var _notices: Array = []
var _qr_tex: ImageTexture
var _qr_code := ""


func setup(u) -> void:
	ui = u
	var parts := W.panel("Together", func(): ui.close_session())
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	title = v.get_child(0).get_child(0) if v.get_child(0).get_child_count() > 0 and v.get_child(0).get_child(0) is Label else null
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


static func _first(n: Node) -> Control:
	for c in n.get_children():
		if (c is Button and not c.disabled) or c is LineEdit:
			return c
		var f := _first(c)
		if f:
			return f
	return null


func note(text: String) -> void:
	_notices.append(text)
	while _notices.size() > 5:
		_notices.pop_front()
	_sig = ""


func _process(delta: float) -> void:
	var _c0 := Time.get_ticks_usec()
	if visible:
		_t += delta
		if _t >= 0.5:
			_t = 0.0
			refresh()
	Cost.add(Cost.PANELS, _c0)


func _signature() -> String:
	var s = ui.session
	if s == null or not s.active():
		return "idle|%s|%s|%s" % [FileAccess.file_exists(HOST_SAVE), FileAccess.file_exists(LAST_SAVE), str(_notices)]
	var e = ui.clock.engine
	return "%d|%d|%s|%s|%s|%s|%s|%s|%d" % [s.role, s.state, str(s.roster), s.paused, s.fast, str(_notices),
			str(s.settings), s._loading, e.step_no / 50 if e != null else -1]


func refresh() -> void:
	var sig := _signature()
	if sig == _sig:
		return
	_sig = sig
	var keep_code := code_edit.text if code_edit != null and is_instance_valid(code_edit) else ""
	var keep_addr := addr_edit.text if addr_edit != null and is_instance_valid(addr_edit) else ""
	W.clear(body)
	var s = ui.session
	if s == null or not s.active():
		_idle(keep_code, keep_addr)
	else:
		_in_session(s)
	for n in _notices:
		body.add_child(W.label(n, 16, W.DIM))


# ------------------------------------------------------------------ before a session

func _idle(keep_code: String, keep_addr: String) -> void:
	body.add_child(W.label("Play together on this Wi-Fi: one device hosts, up to 7 others join with its code. The "
			+ "network is used only while a session is open.", 18, W.DIM))
	body.add_child(W.label("Your name", 18))
	name_edit = LineEdit.new()
	name_edit.max_length = 24
	name_edit.text = my_name()
	name_edit.placeholder_text = "Your name (shown to the others)"
	name_edit.text_changed.connect(func(t): _save_name(t))
	body.add_child(name_edit)
	body.add_child(W.label("Host", 20, Color(1.0, 0.85, 0.4)))
	scen = OptionButton.new()
	_scen_ids = ui.model.scenarios.keys()
	_scen_ids.sort()
	for i in _scen_ids.size():
		scen.add_item(str(ui.model.scenarios[_scen_ids[i]].get("title", _scen_ids[i])).left(60), i)
		if _scen_ids[i] == ui.clock.scenario:
			scen.select(i)
	body.add_child(scen)
	body.add_child(W.button("Host a session", func(): _host({})))
	if FileAccess.file_exists(HOST_SAVE):
		body.add_child(W.button("Continue the saved session (a new code)", func(): _continue_hosted()))
	body.add_child(W.label("Join", 20, Color(1.0, 0.85, 0.4)))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "The session's code (XXXX-XXXX-XXXX-XXXX)"
	code_edit.max_length = 24
	code_edit.text = keep_code
	body.add_child(code_edit)
	addr_edit = LineEdit.new()
	addr_edit.placeholder_text = "The host's address, only if it isn't found"
	addr_edit.max_length = 64
	addr_edit.text = keep_addr
	body.add_child(addr_edit)
	body.add_child(W.button("Join", func(): join(code_edit.text, addr_edit.text)))
	if FileAccess.file_exists(LAST_SAVE):
		body.add_child(W.label("The last session", 20, Color(1.0, 0.85, 0.4)))
		body.add_child(W.button("Continue alone (the others' roles go to the crews)", func(): ui.continue_alone()))


func my_name() -> String:
	var cf: ConfigFile = ui.main.cf
	var n = cf.get_value("multiplayer", "name", "") if cf != null else ""
	return n if typeof(n) == TYPE_STRING and n != "" else ("Trainee %d" % (randi() % 90 + 10))


func _save_name(t: String) -> void:
	var cf: ConfigFile = ui.main.cf
	if cf == null:
		return
	cf.set_value("multiplayer", "name", t.strip_edges().left(24))
	Quality.save(cf)


func _host(from_save: Dictionary) -> void:
	_save_name(name_edit.text if name_edit != null else my_name())
	var sid: String = _scen_ids[scen.selected] if scen != null and scen.selected >= 0 else ui.clock.scenario
	var why: String = ui.start_session(true, sid, "", "", from_save)
	if why != "":
		note(why)


func _continue_hosted() -> void:
	var d = Snapshot.read_file(HOST_SAVE)
	if typeof(d) == TYPE_STRING:
		note("The saved session can't be continued: " + d)
		return
	_host(d)


## Joins by a code (typed, or a join link's) and, when given, the host's address.
func join(code_text: String, address := "") -> void:
	if name_edit != null and is_instance_valid(name_edit):
		_save_name(name_edit.text)
	var why: String = ui.start_session(false, "", code_text, address.strip_edges(), {})
	if why != "":
		note(why)


# ------------------------------------------------------------------ in a session

func _in_session(s) -> void:
	var states := {Session.State.FINDING: "Looking for the session on this network…",
			Session.State.JOINING: "Joining…", Session.State.LOBBY: "In the lobby", Session.State.RUN: "Running"}
	var head: String = states.get(s.state, "")
	if s._loading:
		head = "Joining… (the plant is being loaded)"
	elif s.state == Session.State.RUN and s.paused:
		head = "Paused by %s" % s._name_of(s.paused_by)
	elif s.state == Session.State.RUN and s.fast:
		head = "Fast-forward, %.0f×" % s.rate
	body.add_child(W.label(head, 22, Color(1.0, 0.85, 0.4)))
	body.add_child(W.label("Code  " + Code.pretty(s.code), 26))
	if s.is_host():
		_qr(s)
		var addrs := ui_addresses(s)
		body.add_child(W.label("Or open %s on the other device. If it isn't found there, type this device's address: %s"
				% [Code.link(s.code), addrs], 16, W.DIM))
	if s.state == Session.State.FINDING or s.state == Session.State.JOINING:
		body.add_child(W.button("Cancel", func(): ui.end_session()))
		return
	body.add_child(W.label("Players", 20, Color(1.0, 0.85, 0.4)))
	var e = ui.clock.engine
	var sm = e._sm if e != null else null
	for r in s.roster:
		var person := ""
		var pi: int = e.trainee(r["slot"]) if e != null and s.state == Session.State.RUN else -1
		if pi >= 0 and sm != null:
			person = sm.people[pi]["call"]
		elif str(r.get("person", "")) != "" and sm != null and sm.person_ix.has(r["person"]):
			person = sm.people[sm.person_ix[r["person"]]]["call"] + " (claimed)"
		var flags := []
		if r.get("host", false):
			flags.append("host")
		if r.get("instructor", false) and not r.get("host", false):
			flags.append("instructor")
		if not r.get("connected", true):
			flags.append("not connected")
		if r.get("away", false):
			flags.append("away")
		if s.state == Session.State.LOBBY and r.get("ready", false) and not r.get("host", false):
			flags.append("ready")
		if r.get("fast", false):
			flags.append("ready for fast")
		if r.get("desync", false):
			flags.append("resynchronising")
		if r.get("observer", false):
			flags.append("watching")
		var line: String = "%s%s: %s%s" % [r["name"], " (you)" if r["slot"] == s.slot else "",
				person if person != "" else "free mode", ("  [" + ", ".join(flags) + "]") if not flags.is_empty() else ""]
		var row := HBoxContainer.new()
		var l := W.label(line, 18)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if s.is_host() and not r.get("host", false):
			var slot_no: int = r["slot"]
			var on: bool = r.get("instructor", false)
			row.add_child(W.button("Instructor: " + ("on" if on else "off"), func(): s.set_instructor(slot_no, not on)))
		body.add_child(row)
	_roles(s, e, sm)
	if s.state == Session.State.LOBBY:
		if s.is_host():
			body.add_child(W.button("Start", func(): _start(s)))
		else:
			var me: Dictionary = s.my_entry()
			var ready: bool = me.get("ready", false)
			body.add_child(W.button("Not ready" if ready else "Ready", func(): s.set_ready(not ready)))
	else:
		var mine: bool = s.my_entry().get("fast", false)
		body.add_child(W.button("Not ready for fast-forward" if mine else "Ready for fast-forward",
				func(): s.vote_fast(not mine)))
	body.add_child(W.button("End the session" if s.is_host() else "Leave the session", func(): ui.end_session()))


func _start(s) -> void:
	var why: String = s.start()
	if why != "":
		note(why)


## The play roles' people still free (§6.1): a claim in the lobby, an ordinary `role` input in a run.
func _roles(s, e, sm) -> void:
	if sm == null:
		return
	var taken := {}
	for r in s.roster:
		if str(r.get("person", "")) != "":
			taken[r["person"]] = true
	if s.state == Session.State.RUN:
		for k in 8:
			var pi: int = e.trainee(k)
			if pi >= 0:
				taken[sm.people[pi]["id"]] = true
	if e.trainee(s.slot) >= 0:
		body.add_child(W.button("Give up my role (free mode)", func(): s.claim("")))
		return
	body.add_child(W.label("Roles free to take", 20, Color(1.0, 0.85, 0.4)))
	var any := false
	for pi in sm.people.size():
		var p: Dictionary = sm.people[pi]
		if not sm.roles[p["role"]]["play"] or e._absent.has(pi) or taken.has(p["id"]) or not e.sp_on[pi]:
			continue
		any = true
		var pid: String = p["id"]
		body.add_child(W.button("Play " + p["call"], func(): ui.take_role(pid)))
	if not any:
		body.add_child(W.label("No role on duty is free now.", 16, W.DIM))


func _qr(s) -> void:
	if _qr_code != s.code:
		var q := QR.encode(Code.link(s.code))
		_qr_tex = ImageTexture.create_from_image(QR.image(q, 6)) if not q.is_empty() else null
		_qr_code = s.code
	if _qr_tex != null:
		var tr := TextureRect.new()
		tr.texture = _qr_tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tr.custom_minimum_size = Vector2(_qr_tex.get_width(), _qr_tex.get_height())
		body.add_child(tr)


## This device's IPv4 addresses with the discovery port (what a joiner types).
static func ui_addresses(s) -> String:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append("%s:%d" % [a, s.discovery_port] if s.discovery_port != Session.DISCOVERY_PORT else a)
	return ", ".join(out) if not out.is_empty() else "(no network address)"
