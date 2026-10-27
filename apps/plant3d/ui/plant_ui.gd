## Walkdown Plant's interaction layer (docs/PLANT3D.md §6–§8, decision 0054): runs the behaviour engine at 0.1 s
## steps (ui/sim_clock.gd), and lets the trainee operate the plant through equipment cards (look or tap at a part),
## follow the alarms, procedures and tours, and open links. It sits over the app's frame (app/main.gd, app/hud.gd).
##
## Keys and buttons (app/controls.gd): E or a tap at a part opens its card (gamepad A), L the alarms (D-pad up),
## P procedures and tours (D-pad left), K pause and run (D-pad down), the full stop key fast-forward (D-pad right),
## H back to the control room and its screens (gamepad X; ui/mimic.gd: one screen per system, PLANT3D §7.11), T the
## permits to work (PLANT3D §15; gamepad: from a card or the procedures panel), Esc or B closes the top panel. The debrief (what happened in the run) opens
## at the end of a procedure and from the alarm list's Events button. A procedure's step with `"go": "walk"` shows the
## way on foot to the equipment it points at (app/walk_route.gd).
extends CanvasLayer

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const W = preload("res://ui/widgets.gd")
const Quality = preload("res://app/quality.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const Links = preload("res://sim/links.gd")
const PlantInfo = preload("res://ui/plant_info.gd")
const SceneIndex = preload("res://ui/scene_index.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Tracker = preload("res://ui/procedure_tracker.gd")
const Bindings = preload("res://ui/bindings.gd")
const SoundPlayer = preload("res://ui/sound_player.gd")
const Pointer = preload("res://ui/pointer.gd")
const LinksIn = preload("res://ui/links_in.gd")
const Card = preload("res://ui/card.gd")
const AlarmPanel = preload("res://ui/alarm_panel.gd")
const ProcedurePanel = preload("res://ui/procedure_panel.gd")
const TrainerPanel = preload("res://ui/trainer_panel.gd")
const PermitPanel = preload("res://ui/permit_panel.gd")
const Autosave = preload("res://ui/autosave.gd")
const DebriefPanel = preload("res://ui/debrief_panel.gd")
const Debrief = preload("res://ui/debrief.gd")
const WalkRoute = preload("res://app/walk_route.gd")
const Mimic = preload("res://ui/mimic.gd")
const ScreensModel = preload("res://ui/screens_model.gd")
const Trends = preload("res://ui/trends.gd")
const CrewPanel = preload("res://ui/crew_panel.gd")
const PeopleView = preload("res://ui/people_view.gd")
const Plant = preload("res://app/plant.gd")
const Inputs = preload("res://ui/inputs.gd")
const Session = preload("res://net/session.gd")
const SessionPanel = preload("res://ui/session_panel.gd")
const OthersView = preload("res://net/others_view.gd")
const Snapshot = preload("res://net/snapshot.gd")
const RunSave = preload("res://ui/run_save.gd")
const AndroidNet = preload("res://net/android_net.gd")

const CONTENT := "res://built/content"
const REACH := 6.0              # metres: within this a trainee works the equipment's local controls
## How near an operator desk outside the main control room the trainee stands to work its screens (m): within the
## water treatment plant's control room.
const DESK_REACH := 6.0
const HINT_RANGE := 15.0

signal horn_changed(priority: int)

var main
var player
var model
var info
var index
var clock
var inputs                      # ui/inputs.gd: every input of the trainee's to the plant goes through it (MP1)
var tracker
var bindings
var sounds
var pointer
var route                       # app/walk_route.gd: the way on foot to what is pointed at, in a "walk" step
var walking := false            # the current step says "go": "walk"
var links
var card
var alarms
var procedure
var trainer
var permits                     # ui/permit_panel.gd: the permits to work and their isolations (PLANT3D §15)
var autosave                    # ui/autosave.gd: the run saved to user://, offered again at start
var debrief
var screens                     # ui/screens_model.gd: the control room screens made from the model (PLANT3D §7.11)
var trends                      # ui/trends.gd: the values the screens trend, sampled as the plant runs
var mimic                       # ui/mimic.gd: the screens themselves
var run_tracker                 # the last procedure followed in this run (kept for its debrief after it is closed)
var crew                        # ui/crew_panel.gd: the trainee's role, tasks and radio (PLANT3D §18.7)
var people                      # ui/people_view.gd: the crews as markers in the plant and dots on the map
var session                     # net/session.gd while a multiplayer session is open (MULTIPLAYER.md), else null
var session_panel               # ui/session_panel.gd: Together
var others                      # net/others_view.gd: the other players in the plant
var _host_save_t := 0.0         # the host's saved session (§7.4): every 5 s while it changes
var _host_save_step := -1
var _save_job := -1
var session_ports: Array = []   # [discovery port, session port] (tests: their own); empty, the defaults
var _place_t := 0.0
var _arrived := -2              # the place the last arrive input named (-1: a leave), -2: none sent yet
var _jumps := 0                 # the engine's J when last looked at: a jump moves the walker to their placed person
var _zones := -1                # the zones the last zone inputs left the trainee in (a bit each), -1: none sent yet
var root: Control
var arrows: Control
var instructor := false
var hover := ""
var error := ""
var results := {}               # op key -> {state: sent | done | refused | unknown, text, step}
var _pending: Array = []        # [op key, op, step it takes effect]
var _ev_seen := 0
var _horn := 0
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _toast_beside_card := false
var _alarm_btn: Button
var _time: Label
var _ff_btn: Button
var _play_btn: Button
var _pause_btn: Button
var _trainer_btn: Button
var _t_hint := 0.0
var _blink := 0.0
var _flight: Tween


func setup(m, scenario := "cold_iron", content := CONTENT) -> void:
	main = m
	player = m.player
	layer = 2
	W.pick_scale()
	if m.opts.has("ui_scale"):               # the phone's scale on a desktop (tests/mimic_shots.gd --phone)
		W.scale = clampf(float(m.opts["ui_scale"]), 0.5, 3.0)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = W.make_theme()
	add_child(root)
	model = PlantModel.from_dir(content)
	if model.error != "":
		error = "The plant's model did not load: " + model.error
		_build_toast()
		toast(error, 30.0)
		return
	if not model.scenarios.has(scenario):
		scenario = model.scenarios.keys()[0] if not model.scenarios.is_empty() else ""
	info = PlantInfo.new(model)
	screens = ScreensModel.new(info, ScreensModel.load_file(content + "/screens.json"))
	if screens.error != "":
		push_warning("control room screens: " + screens.error)
	trends = Trends.new(screens.trended)
	index = SceneIndex.new()
	index.scan(m.plant)
	clock = SimClock.new()
	clock.name = "clock"
	add_child(clock)
	inputs = Inputs.new()
	inputs.clock = clock
	clock.stepped.connect(_on_step)
	clock.speed_changed.connect(_on_speed)
	pointer = Pointer.new()
	pointer.name = "pointer"
	m.add_child(pointer)
	route = WalkRoute.new()
	route.name = "walk_route"
	m.add_child(route)
	var nav_err: String = route.setup()
	if nav_err != "":
		push_warning(nav_err)      # no walking directions; everything else works
	sounds = SoundPlayer.new()
	sounds.name = "sounds"
	sounds.walker = player
	m.add_child(sounds)
	horn_changed.connect(sounds.horn)
	bindings = Bindings.new()
	bindings.name = "bindings"
	bindings.sounds = sounds
	bindings.clock = clock
	add_child(bindings)
	clock.start(model, scenario)
	bindings.setup(clock.engine, index, info, player.camera)
	sounds.engine = clock.engine
	_build()
	people = PeopleView.new()
	people.name = "people"
	m.add_child(people)
	people.setup(self)
	links = LinksIn.new()
	links.name = "links"
	links.link.connect(handle_link)
	add_child(links)
	autosave = Autosave.new()
	autosave.name = "autosave"
	add_child(autosave)
	autosave.setup(self, content)


# ------------------------------------------------------------------ building the overlay

func _build() -> void:
	var bar := HBoxContainer.new()
	bar.name = "ui_bar"
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.position = Vector2(-16, 88)
	root.add_child(bar)
	_alarm_btn = _bar_button(bar, "Alarms", func(): toggle_alarms())
	_bar_button(bar, "Procedures", func(): toggle_procedure())
	_bar_button(bar, "Permits", func(): toggle_permits())
	_bar_button(bar, "Crew", func(): toggle_crew())
	_bar_button(bar, "Control room", func(): control_room())
	_bar_button(bar, "Together", func(): toggle_session())
	_trainer_btn = _bar_button(bar, "Instructor", func(): toggle_trainer())
	_trainer_btn.visible = instructor
	_pause_btn = _bar_button(bar, "Pause", func(): clock.set_speed(SimClock.Speed.PAUSED))
	_play_btn = _bar_button(bar, "1×", func(): clock.set_speed(SimClock.Speed.NORMAL))
	_ff_btn = _bar_button(bar, "Fast", func(): fast_forward())
	_time = W.label("", 20, Color.WHITE, false)
	_time.custom_minimum_size.x = 150 * W.scale
	_time.add_theme_constant_override("outline_size", 6)
	_time.add_theme_color_override("font_outline_color", Color.BLACK)
	bar.add_child(_time)
	bar.move_child(_time, 0)
	arrows = Control.new()
	arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrows.draw.connect(_draw_arrows)
	root.add_child(arrows)
	mimic = Mimic.new()
	mimic.name = "screens"
	root.add_child(mimic)
	mimic.setup(self, screens, trends)
	card = Card.new()
	card.name = "card"
	root.add_child(card)
	card.setup(self)
	procedure = ProcedurePanel.new()
	procedure.name = "procedure"
	root.add_child(procedure)
	procedure.setup(self)
	alarms = AlarmPanel.new()
	alarms.name = "alarms"
	root.add_child(alarms)
	alarms.setup(self)
	trainer = TrainerPanel.new()
	trainer.name = "trainer"
	root.add_child(trainer)
	trainer.setup(self)
	permits = PermitPanel.new()
	permits.name = "permits"
	root.add_child(permits)
	permits.setup(self)
	crew = CrewPanel.new()
	crew.name = "crew"
	root.add_child(crew)
	crew.setup(self)
	debrief = DebriefPanel.new()
	debrief.name = "debrief"
	root.add_child(debrief)
	debrief.setup(self)
	session_panel = SessionPanel.new()
	session_panel.name = "session_panel"
	root.add_child(session_panel)
	session_panel.setup(self)
	_hint = W.label("", 20, Color.WHITE, false)
	_hint.add_theme_constant_override("outline_size", 8)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)
	_build_toast()
	root.get_viewport().size_changed.connect(_layout)
	_layout()
	_on_speed(clock.speed, "")


func _build_toast() -> void:
	_toast = W.label("", 22, Color.WHITE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.06, 0.88)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	_toast.add_theme_stylebox_override("normal", bg)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	_layout_toast()


func _bar_button(bar: Control, text: String, f: Callable) -> Button:
	var b := W.button(text, f)
	b.focus_mode = Control.FOCUS_NONE       # the bar is reached by its keys; focus stays in the panels
	b.custom_minimum_size = Vector2(0, 56 * W.scale)
	bar.add_child(b)
	return b


func _layout() -> void:
	var vs: Vector2 = root.get_viewport_rect().size
	var top0 := 88.0 + 56.0 * W.scale + 16.0
	# with the screens open the side panels stand below their tabs and alarm banner, which stay in reach
	var top := maxf(top0, mimic.canvas_top() + 8.0) if screens_open() else top0
	var w := minf(560.0 * W.scale, vs.x * 0.45)
	card.position = Vector2(vs.x - w - 16.0, top)
	_max_h = vs.y - top - 16.0
	card.size = Vector2(w, vs.y - top - 16.0)
	procedure.position = Vector2(16.0, top)
	procedure.size = Vector2(w, vs.y - top - 16.0)
	crew.position = procedure.position
	crew.size = procedure.size
	alarms.position = card.position
	alarms.size = card.size
	trainer.position = card.position
	trainer.size = card.size
	permits.position = card.position
	permits.size = card.size
	debrief.position = card.position
	debrief.size = card.size
	session_panel.position = procedure.position
	session_panel.size = procedure.size
	mimic.position = Vector2(0.0, top0)
	mimic.size = Vector2(vs.x, vs.y - top0)
	_hint.position = Vector2(vs.x * 0.5 - 400.0, vs.y * 0.5 + 24.0)
	_hint.size = Vector2(800.0, 60.0)
	_layout_toast()


func _layout_toast() -> void:
	var vs: Vector2 = root.get_viewport_rect().size
	# between the side panels when they are open (on a phone it may reach over them: it has its own background)
	var side := 0.0
	if card != null and (card.visible or alarms.visible or trainer.visible or procedure.visible or debrief.visible
			or permits.visible):
		side = card.size.x + 32.0
	_toast_beside_card = card != null and card.visible
	var w := clampf(vs.x - 2.0 * side, 360.0, minf(vs.x * 0.5, 900.0))
	var x := (vs.x - w) * 0.5
	if screens_open():
		# over the screens, at their bottom edge (the middle of a screen is where the plant is read), left of a card
		var right: float = (card.position.x if card != null and card.visible else vs.x) - 16.0
		w = clampf(right - 16.0, 360.0, 900.0)
		x = maxf(16.0, (right + 16.0 - w) * 0.5)
	_toast.position = Vector2(x, 0.0)
	_toast.size = Vector2(w, 0)
	var h := _toast.get_combined_minimum_size().y
	_toast.position.y = (vs.y - h - 16.0) if screens_open() else vs.y - 200.0 * W.scale


## The layer's rows in the settings panel (app/hud.gd), kept in the app's settings file.
func add_settings(box: VBoxContainer) -> void:
	if clock == null:
		return
	var cf: ConfigFile = main.cf
	for row in [["instructor", "Instructor mode: scenarios and trainer faults", false],
			["reduced_motion", "Reduced motion: no camera shake near machines, no head bob", false],
			["mute", "Mute the plant's sounds", false]]:
		var cb := CheckBox.new()
		cb.text = row[1]
		cb.focus_mode = Control.FOCUS_ALL
		var on: bool = cf.get_value("ui", row[0], row[2])
		cb.button_pressed = on
		_setting(row[0], on)
		cb.toggled.connect(func(v):
			cf.set_value("ui", row[0], v)
			Quality.save(cf)
			_setting(row[0], v))
		box.add_child(cb)


func _setting(key: String, on: bool) -> void:
	match key:
		"instructor": set_instructor(on)
		"reduced_motion":
			bindings.reduced_motion = on
			player.bob = not on
		"mute":
			sounds.muted = on
			horn_changed.emit(0)
			_horn = -1                  # the next tick sounds the horn again if an alarm wants it
			_alarms_step = -1           # (and looks at the alarms again, paused as well)


## Opens a panel by name (the command line's panels=…): alarms, procedure, card:CODE. (Not the instructor's:
## on Android these options can come from a shared folder.)
func open_panel(p: String) -> void:
	if clock == null:
		return
	if p == "alarms" and not alarms.visible:
		toggle_alarms()
	elif p == "procedure" and not procedure.visible:
		toggle_procedure()
	elif p == "crew" and not crew.visible:
		open_crew()
	elif p == "permits" or p.begins_with("permit:"):
		open_permits(p.substr(7) if p.begins_with("permit:") else "")
	elif p.begins_with("card:"):
		open_card(p.substr(5))
	elif p == "screens" or p.begins_with("screens:"):
		open_screens_at_desk(p.substr(8) if p.begins_with("screens:") else "")


## The screens at a screen (its id; "" the overview), from wherever the trainee is: at a desk that has it they open
## there; else the trainee goes to a desk that has it (PLANT3D §14 `desks`), the main control room when it is one of
## them, otherwise the first of its desks (the water treatment plant's own), and they open on arrival.
func open_screens_at_desk(screen_id := "") -> void:
	if screens.error != "":
		open_screens(screen_id)
		return
	var i: int = screens.screen_index(screen_id) if screen_id != "" else -1
	if screen_id != "" and i < 0:
		toast("No screen %s." % screen_id)
		return
	if at_desk() and (screen_id == "" or screen_here(i)):
		open_screens(screen_id)            # "": the desk's own first screen
		return
	var ds: Array = screens.overview.get("desks", []) if i < 0 else screens.screens[i].desks
	if ds.is_empty():
		ds = info.desks()
	var to := ""
	for d in ds:
		if info.area_of.get(d, "") == "control":
			to = d
			break
	if to != "" or ds.is_empty():
		go_control_room(false)
		open_screens(screen_id)
		return
	to = ds[0]
	fly_to(to, func():
		if at_desk() and screen_here(i):
			open_screens(screen_id)
		else:
			toast("The screens are worked at %s." % info.name_of(to)))


# ------------------------------------------------------------------ where the trainee is

func eye() -> Vector3:
	return player.camera.global_position


func distance_to(code: String) -> float:
	return index.distance(code, player.global_position + Vector3.UP * 1.0)


func near(code: String) -> bool:
	return index.has(code) and distance_to(code) <= REACH


## The operator desks whose screens the trainee is at (PLANT3D §14 `desks`): in the main control room its desks,
## elsewhere any desk within DESK_REACH (the water treatment plant's own control room).
func desks_here() -> Array:
	var out := []
	var ctl := in_control_room()
	for c in info.desks():
		if ctl and info.area_of.get(c, "") == "control":
			out.append(c)
		elif not ctl and index.has(c) and distance_to(c) <= DESK_REACH and _desk_seen(c):
			out.append(c)
	return out


## A desk outside the main control room is worked only from where its screens are in sight: nothing solid (a wall,
## a partition) between the trainee's eyes and the desk.
func _desk_seen(code: String) -> bool:
	var b: AABB = index.box(code)
	var to := b.get_center()
	var q := PhysicsRayQueryParameters3D.create(eye(), to)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or b.grow(0.3).has_point(hit.position)


## At an operator desk: its screens can be worked.
func at_desk() -> bool:
	return not desks_here().is_empty()


## Whether screen i (−1: the overview) is on a desk here.
func screen_here(i: int) -> bool:
	return screens.error == "" and screens.reached(i, desks_here())


## Whether a code's operations from the screens are offered here: a desk here has the screen that shows it.
func screen_reach(code: String) -> bool:
	if screens.error != "" or not screens.screen_of.has(code):
		return false
	return screens.reached(screens.screen_of[code][0], desks_here())


## The names of the desks that show a code's screen ("" when it is on no screen).
func desks_for(code: String) -> String:
	if screens.error != "" or not screens.screen_of.has(code):
		return ""
	var ds: Array = screens.screens[screens.screen_of[code][0]].desks
	if ds.is_empty():
		ds = info.desks()
	var names := PackedStringArray()
	for d in ds:
		var n: String = info.name_of(d)
		if not names.has(n):
			names.append(n)
	return ", ".join(names)


func in_control_room() -> bool:
	var b: Array = info.bounds.get("control", [])
	if b.is_empty():
		return false
	var p: Vector3 = player.global_position
	return p.x >= b[0][0] and p.x <= b[1][0] and -p.z >= b[0][1] and -p.z <= b[1][1]


## Gamepad or keyboard in use (no touch screen, or the gamepad the controls in use: app/input_mode.gd): panels take
## the focus so that they can be worked without a mouse.
func wants_focus() -> bool:
	if main.hud == null:
		return not DisplayServer.is_touchscreen_available()
	return not main.hud.touch_screen or main.hud.pad_on()


## A gamepad has just become the controls (app/hud.gd focus_panel): the top panel, in close_top's order, takes the
## focus unless it has it already (its first button); the screens' canvas when no panel is over them; first of all
## the saved run's offer at the start (Continue or New run). True when it gave the focus to something.
func focus_top() -> bool:
	var fo := root.get_viewport().gui_get_focus_owner()
	if autosave != null and autosave.offering():
		return _focus_in(autosave.offer_panel, fo)
	for p in [trainer, permits, debrief, alarms, card]:
		if p.visible:
			return _focus_in(p, fo)
	if screens_open():
		var had: bool = mimic.canvas.has_focus()
		mimic.take_focus()
		return not had and mimic.canvas.has_focus()
	for p in [procedure, crew]:
		if p.visible:
			return _focus_in(p, fo)
	return false


func _focus_in(p: Control, fo: Control) -> bool:
	if fo != null and p.is_ancestor_of(fo) and fo.is_visible_in_tree():
		return false
	# as the panel's own open() does: its tab (alarms, debrief), else its body's first control, else the Close button
	var b: Control = null
	if "_tabs" in p and "tab" in p and p._tabs.has(p.tab):
		b = p._tabs[p.tab]
	if b == null and "body" in p and p.body != null:
		b = _first_focusable(p.body)
	if b == null:
		b = _first_focusable(p)
	if b != null:
		b.grab_focus()
	return b != null


## The first button that can take the focus (a text field would bring up the phone's keyboard, and the D-pad would
## move its cursor; the panels' own open() choose buttons too).
static func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and c.is_visible_in_tree():
			if c is BaseButton and c.focus_mode == Control.FOCUS_ALL and not c.disabled:
				return c
			var f := _first_focusable(c)
			if f != null:
				return f
	return null


# ------------------------------------------------------------------ the trainee's inputs to the plant

func do_op(o: Dictionary, value) -> void:
	var key := Tracker.op_key(o["kks"], o["do"], o.get("trip"))
	var who = me()
	if who != null:
		# playing a person (§17.1): made from the screens or at the equipment, by them
		# (where the card offers it: the screens, or the control room away from the equipment; else at it)
		var where := "screen" if screens_open() or (in_control_room() and not near(o["kks"])) else "local"
		inputs.op(o["kks"], o["do"], value, o.get("trip"), where, who)
	else:
		inputs.op(o["kks"], o["do"], value, o.get("trip"))
	_pending.append([key, o, clock.engine.step_no + 1])
	var paused: bool = clock.speed == SimClock.Speed.PAUSED
	results[key] = {"state": "sent", "text": "Sent%s" % (": it takes effect when the plant runs (paused)" if paused else "…")}


## The person the trainee plays (§17.4), null in free mode.
func me():
	var pi: int = inputs.person() if inputs != null else -1
	return clock.engine._sm.people[pi]["id"] if pi != -1 else null


## The person the trainee plays as an index (§17.4), -1 in free mode or without staff.
func my_person() -> int:
	return inputs.person() if inputs != null else -1


## The plant clock (§16.1) when the run has staff, else model time.
func clock_text() -> String:
	var e = clock.engine
	if e == null or e._sm == null:
		return clock.clock_text()
	var t: int = e.clock()
	var s: int = (t % 864000) / 10
	return "Day %d %s %02d:%02d" % [t / 864000, e._sm.week[posmod(t / 864000 - 1, 7)].capitalize(), s / 3600, (s / 60) % 60]


## A run with the crews (a scenario with `staff`): the plant paused at its start and the role offered.
func start_shift(scenario: String) -> void:
	restart(scenario)


## The role input (§17.4) for a person, or free mode (""): only before the run's first step.
func take_role(pid: String) -> void:
	if session != null and session.active():
		# a session: a claim, settled by the host (in the lobby first come first served, later by commit order, §6.1)
		session.claim(pid)
		toast("Asked for the role: the host settles it." if pid != "" else "Free mode: the crews work around you.")
		return
	var e = clock.engine
	if pid != "":
		inputs.role(pid)
		clock.run_steps(1)
		var pi := my_person()
		if pi != -1:
			_arrived = -2
			_zones = -1
			go_to_place(e.sp_pos[pi] if e.sp_pos[pi] != -1 else e._sm.gate)
			toast("You are %s. Your tasks are in the Crew panel." % e._sm.people[pi]["call"])
		else:
			toast("That role could not be taken.")
	else:
		toast("Free mode: the crews work around you.")
	clock.set_speed(SimClock.Speed.NORMAL)


## Puts the walker at a staff place (the logical places of §16.2; the walk itself is the trainee's).
func go_to_place(i: int) -> void:
	var sm = clock.engine._sm
	if sm == null or i < 0:
		return
	var at: Array = sm.places[i]["at"]
	if _flight:
		_flight.kill()
	player.scripted = false
	player.set_mode(player.Mode.FLY)
	player.global_position = Plant.g(at[0], at[1], at[2]) + Vector3.UP * 0.05
	player.set_mode(player.Mode.WALK)
	_place_t = 1.0


## A reading written down by the trainee (the read input, §17.6).
func write_reading(code: String, text: String) -> void:
	var t := text.strip_edges().replace(",", ".")
	if not t.is_valid_float():
		toast("Type the number the gauge shows.")
		return
	inputs.read(code, t.to_float())


## Whether the trainee stands at a locker place (PPE is put on and taken off there, PLANT3D §17.11).
func at_locker() -> bool:
	var e = clock.engine
	var at: int = e.t_at(inputs.slot)
	return e._sm != null and at != -1 and e._sm.kind[at] == "locker"


## The walker to the nearest locker (the control building's locker room, or the WTP's lockers for the face shield
## and apron of chemical work, milestone S3).
func go_to_locker() -> void:
	var sm = clock.engine._sm
	var me: Vector3 = player.global_position
	var best := -1
	var bd := INF
	for i in sm.places.size():
		if sm.kind[i] == "locker":
			var at: Array = sm.places[i]["at"]
			var d: float = me.distance_squared_to(Plant.g(at[0], at[1], at[2]))
			if d < bd:
				bd = d
				best = i
	if best != -1:
		go_to_place(best)


## The trainee puts on their role's PPE ("role") or the listed items, or takes everything off ("off"), at a locker:
## one ppe input per item (§17.6).
func put_on(x) -> void:
	var e = clock.engine
	var sm = e._sm
	var pi := my_person()
	if sm == null or pi == -1:
		return
	if not at_locker():
		toast("PPE is put on at a locker.")
		return
	var worn: int = e.sp_worn[pi]
	if typeof(x) == TYPE_STRING and x == "off":
		for k in sm.PPE.size():
			if worn & (1 << k):
				inputs.ppe(sm.PPE[k], 0)
		return
	var items: Array = x if typeof(x) == TYPE_ARRAY else sm.roles[sm.people[pi]["role"]].get("ppe", [])
	for it in items:
		if not (worn & (1 << sm.PPE.find(it))):
			inputs.ppe(it, 1)


## Whether the trainee is within talking reach (3 m) of a person, where the engine has them (a place, or along a way).
func near_person(qi: int) -> bool:
	var e = clock.engine
	var sm = e._sm
	var at = null
	if not e.sp_leg[qi].is_empty():
		var leg: Array = e.sp_leg[qi]
		var k := clampf(float(e.step_no - leg[2]) / maxf(1.0, float(leg[3] - leg[2])), 0.0, 1.0)
		var a: Array = sm.places[leg[0]]["at"]
		var b: Array = sm.places[leg[1]]["at"]
		at = Vector3(lerpf(a[0], b[0], k), lerpf(a[1], b[1], k), lerpf(a[2], b[2], k))
	elif e.sp_pos[qi] != -1:
		var p: Array = sm.places[e.sp_pos[qi]]["at"]
		at = Vector3(p[0], p[1], p[2])
	if at == null:
		return false
	var g: Vector3 = player.global_position
	return Vector3(g.x, -g.z, g.y).distance_to(at) <= STOP_REACH


const STOP_REACH := 3.0         # m: how near the trainee stops someone's work


## The trainee stops an unsafe act of that person's (§16.7, §17.11): within reach of them, as a lock within reach of
## its equipment.
func stop_work(pid: String) -> void:
	var e = clock.engine
	var sm = e._sm
	if sm == null or not sm.person_ix.has(pid):
		return
	if not near_person(sm.person_ix[pid]):
		toast("Go to them first: work is stopped face to face.")
		return
	inputs.stop_act(pid)


## The zone inputs (§17.6): the zones whose outline holds the walker (within their heights), as they change.
func _zone_tick(e, here: Vector3) -> void:
	var sm = e._sm
	if sm.zone_ids.is_empty():
		return
	var zm := 0
	for z in sm.zone_ids.size():
		var zd: Dictionary = sm.d["zones"][z]
		if here.z > float(zd["z"][0]) and here.z < float(zd["z"][1]) and _inside(here.x, here.y, zd["outline"]):
			zm |= 1 << z
	var pi := my_person()
	if _zones == -1:
		_zones = e.sp_zin[pi]
	if zm == _zones:
		return
	var worn: int = e.sp_worn[pi]
	for z in sm.zone_ids.size():
		var bit: int = 1 << z
		if (zm & bit) and not (_zones & bit):
			inputs.zone(sm.zone_ids[z], "in")
			var miss := PackedStringArray()
			for k in sm.PPE.size():
				if sm.zone_ppe[z] & (1 << k) and not (worn & (1 << k)):
					miss.append(CrewPanel.PPE_WORDS.get(sm.PPE[k], sm.PPE[k]))
			var zt: String = sm.d["zones"][z].get("title", sm.zone_ids[z])
			toast("Entering the %s%s" % [zt.to_lower(), (": you need " + ", ".join(miss)) if not miss.is_empty() else ""])
		elif (_zones & bit) and not (zm & bit):
			inputs.zone(sm.zone_ids[z], "out")
	_zones = zm


static func _inside(x: float, y: float, poly: Array) -> bool:
	var inside := false
	var n := poly.size()
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		if (float(a[1]) > y) != (float(b[1]) > y) and x < float(a[0]) + (y - float(a[1])) * (float(b[0]) - float(a[0])) / (float(b[1]) - float(a[1])):
			inside = not inside
	return inside


## The arrive and leave inputs (§17.6): the trainee is at a place when within 1.5 m of it (2 m up or down).
func _place_tick() -> void:
	var e = clock.engine
	var pi := my_person()
	if e._sm == null or pi == -1:
		return
	var sm = e._sm
	if e.J != _jumps and e.st_jumped.is_empty():
		# after a jump (§17.6) the trainee's person stands where the placement put them: the walker goes there
		_jumps = e.J
		_arrived = -2
		_zones = -1
		if e.sp_pos[pi] != -1:
			go_to_place(e.sp_pos[pi])
		toast("The clock jumped to %s." % clock_text())
		return
	var g: Vector3 = player.global_position
	var here := Vector3(g.x, -g.z, g.y)
	_zone_tick(e, here)
	var best := -1
	var bd := 1.5
	for i in sm.places.size():
		var at: Array = sm.places[i]["at"]
		if absf(at[2] - here.z) > 2.0:
			continue
		var d := Vector2(at[0] - here.x, at[1] - here.y).length()
		if d < bd:
			bd = d
			best = i
	var now: int = e.sp_pos[pi] if _arrived == -2 else _arrived
	if best != -1 and best != now:
		if now >= 0:
			inputs.leave(sm.places[now]["id"])
		inputs.arrive(sm.places[best]["id"])
		_arrived = best
	elif best == -1 and now >= 0:
		var at: Array = sm.places[now]["at"]
		if Vector2(at[0] - here.x, at[1] - here.y).length() > 2.5:
			inputs.leave(sm.places[now]["id"])
			_arrived = -1


func op_result(o: Dictionary) -> Dictionary:
	return results.get(Tracker.op_key(o["kks"], o["do"], o.get("trip")), {})


func ack(alarm: String, sound := true) -> void:
	inputs.ack(alarm)
	if sound:
		sounds.once("horn_ack")


func shelve(alarm: String, seconds: float) -> void:
	inputs.shelve(alarm, seconds)
	toast("Shelved for %s of plant time." % W.model_time(int(seconds * 10)))


func unshelve(alarm: String) -> void:
	inputs.unshelve(alarm)


func fault(fid: String) -> void:
	inputs.fault(fid)
	toast("Fault pressed: it acts in the next step.")


## A fault's repair (PLANT3D §7.8): from the instructor's panel, or, in a plant without permits to work (version 1),
## by the trainee at its equipment (the card).
func repair(fid: String) -> void:
	inputs.repair(fid)
	toast("Repaired: it acts in the next step.")


## The trainee's repair at the equipment under a work's permit to work (PLANT3D §15.5, a version 2 plant).
func repair_under(fid: String, wid: String) -> void:
	inputs.repair_under(fid, wid, me())
	toast("Repaired under the permit: it acts in the next step.")


func fast_forward() -> void:
	var b: String = clock.ff_blocked()
	if b != "":
		toast("No fast-forward: " + b + ".")
		return
	clock.set_speed(SimClock.Speed.FAST)


func restart(scenario: String, quiet := false) -> void:
	stop_procedure()
	run_tracker = null
	clock.start(model, scenario)
	bindings.use_engine(clock.engine)
	sounds.engine = clock.engine
	sounds.reset_edges()
	alarms.since.clear()
	alarms._sig = ""
	trends.clear()
	results.clear()
	_pending.clear()
	permits.results.clear()
	permits._pending.clear()
	permits._sig = ""
	_ev_seen = 0
	_arrived = -2
	_zones = -1
	_jumps = 0
	crew._sig = ""
	if not quiet:
		toast("The plant restarted: %s." % model.scenarios[scenario].get("title", scenario))
	if clock.engine._sm != null and my_person() == -1:
		clock.set_speed(SimClock.Speed.PAUSED)
		open_crew()


# ------------------------------------------------------------------ cards, pointing, moving

func open_card(code: String, note := "") -> void:
	if info.part_of(code) == "operator_desk":       # an operator desk: its screens
		open_screens()
		return
	alarms.visible = false
	trainer.visible = false
	debrief.visible = false
	permits.visible = false
	card.open(code, note)
	if index.has(code) or screens_open() and screens.screen_of.has(code):
		show_me(code)
	_release_mouse()


func close_card() -> void:
	card.visible = false
	card.code = ""
	mimic.take_focus()


# ------------------------------------------------------------------ the control room screens

func screens_open() -> bool:
	return mimic != null and mimic.visible


## Opens the screens at a screen (its id; "" the overview, or the desk's first screen), at an operator desk only:
## the main control room's or the water treatment plant's, each with its own screens (PLANT3D §14).
func open_screens(screen_id := "") -> void:
	if screens.error != "" or not at_desk():
		toast("The screens are worked at an operator desk: in the control room, or the water treatment plant's." if screens.error == "" else "No control room screens: " + screens.error)
		return
	_release_mouse()
	mimic.open(screens.screen_index(screen_id) if screen_id != "" else -1)
	# the screens cover the view: the plant is not drawn behind them (the phone's GPU, decision 0041); its sounds go on
	get_viewport().disable_3d = true
	main.hud.refresh()
	_layout()


func close_screens() -> void:
	if mimic == null or not mimic.visible:
		return
	mimic.visible = false
	get_viewport().disable_3d = false
	main.hud.refresh()
	_layout()


## The Control room button (and H, gamepad X): to the control room and its screens; there, the screens on and off.
func control_room() -> void:
	if at_desk() and not player.scripted:
		if screens_open():
			close_screens()
		else:
			open_screens()
		return
	go_control_room(false)
	open_screens()


func show_me(code: String) -> void:
	var on_screens: bool = screens_open() and screens.screen_of.has(code) and mimic.here(screens.screen_of[code][0])
	if on_screens:
		# the plant is not drawn under the screens: the code is shown on its screen too (the pointer and the route
		# below are there when the screens close)
		if mimic.current != screens.screen_of[code][0]:
			mimic.show_screen(screens.screen_of[code][0])
		mimic.select(code)
	if not index.has(code):
		if on_screens:
			return
		toast("%s is not drawn in the plant." % code)
		return
	pointer.point(code, index.box(code))
	if walking:
		route.guide(player, index.box(code))


## Puts the trainee beside the equipment, facing it: a short flight, then on the floor below when there is one.
func fly_to(code: String, done: Callable = Callable()) -> void:
	if not index.has(code):
		toast("%s is not drawn in the plant." % code)
		return
	close_screens()             # first: show_me points in the plant only with the screens closed
	show_me(code)
	var b: AABB = index.box(code)
	var c := b.get_center()
	var from: Vector3 = player.global_position
	var dir := Vector3(from.x - c.x, 0, from.z - c.z)
	if dir.length() < 0.1:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	var to := stand_point(b, dir)
	var aim := Vector3(c.x, clampf(c.y, to.y + 0.3, to.y + 3.0), c.z)
	var look := aim - (to + Vector3.UP * 1.65)
	var yaw := atan2(-look.x, -look.z)
	var pitch := atan2(look.y, Vector2(look.x, look.z).length())
	if main.map.active:
		main.toggle_map()
	if _flight:
		_flight.kill()
	player.set_mode(player.Mode.FLY)
	player.scripted = true
	player.drive = Vector2.ZERO
	var t := clampf(from.distance_to(to) / 60.0, 0.4, 2.5)
	_flight = create_tween()
	_flight.tween_property(player, "global_position", to, t).set_trans(Tween.TRANS_SINE)
	_flight.parallel().tween_method(func(k: float): player.set_heading(lerp_angle(player.rotation.y, yaw, k), lerpf(player.pivot.rotation.x, pitch, k)), 0.0, 1.0, t)
	_flight.finished.connect(func():
		player.scripted = false
		player.set_heading(yaw, pitch)
		player.set_mode(player.Mode.WALK)     # lands on the floor below when there is one, else keeps flying
		if done.is_valid():
			done.call())


## Where "Go there" puts the trainee for equipment in box b, coming from direction dir (unit, plan): on the floor
## beside it (a platform, a grating, the ground; not at the foot of a column in a pit), and clear of everything
## solid: the side towards the trainee first, then round the equipment in eighths of a turn, then further out. A
## place inside a machine (a condenser's vent seen from its pit lands inside the condenser's shell) would leave
## the walker to be pushed out of it, through the floor (tests/test_ui_cold_start.gd: the condenser's vents).
func stand_point(b: AABB, dir: Vector3) -> Vector3:
	var c := b.get_center()
	var r := maxf(b.size.x, b.size.z) * 0.5
	var first := Vector3.INF
	for dist: float in [r + 2.5, r + 4.0, r + 6.0]:
		for turn: float in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
			var d := dir.rotated(Vector3.UP, deg_to_rad(turn))
			var to := c + d * minf(dist, 40.0)
			var hit: Dictionary = player.floor_below(Vector3(to.x, b.end.y + 1.0, to.z), b.size.y + 40.0)
			to.y = (hit.position.y if not hit.is_empty() else maxf(b.position.y, 0.0)) + 0.05
			if first == Vector3.INF:
				first = to
			if not hit.is_empty() and _is_floor(hit, to) and player.fits_at(to):
				return to
	return first


## A floor to stand on: not the top of a machine or a pipe (their bodies are in the groups `equipment` and `pipes`),
## and flat for the walker's width round the point (a handrail's or a wall's top is not: four rays 0.3 m out land
## within 5 cm of its height).
func _is_floor(hit: Dictionary, at: Vector3) -> bool:
	var col = hit.get("collider")
	if col is Node and ((col as Node).is_in_group("equipment") or (col as Node).is_in_group("pipes")):
		return false
	for o: Vector3 in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, -0.3)]:
		var h: Dictionary = player.floor_below(at + o + Vector3.UP * 0.5, 1.0)
		if h.is_empty() or absf(h.position.y - (at.y - 0.05)) > 0.05:
			return false
	return true


## To the control room (`say`: with a word on what is offered there; not when the screens open at once, which it
## would cover).
func go_control_room(say := true) -> void:
	var st: Array = main.plant.start()
	if _flight:
		_flight.kill()
	player.scripted = false
	player.set_mode(player.Mode.FLY)
	player.global_position = st[0]
	player.set_heading(st[1])
	player.set_mode(player.Mode.WALK)
	if say:
		toast("In the control room: the screens' operations are offered here.")


func _release_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func toast(text: String, seconds := 4.0) -> void:
	if _toast == null or text == "":
		return
	_toast.text = text
	_layout_toast()
	_toast.visible = true
	_toast.size.y = 0
	_toast_t = seconds


# ------------------------------------------------------------------ panels

## The right-hand side holds one of the card, the alarm list and the instructor's panel; procedures stay on the left.
func _right_open(p) -> void:
	for q in [card, alarms, trainer, debrief, permits]:
		if q != p and q.visible:
			if q == card:
				close_card()
			else:
				q.visible = false
	p.open()
	_release_mouse()


func toggle_alarms() -> void:
	if alarms.visible:
		close_alarms()
	else:
		_right_open(alarms)


func close_alarms() -> void:
	alarms.visible = false
	mimic.take_focus()          # the screens' canvas again (a hidden panel's focused button lets the focus go)


## The debrief of the run: the procedure's (followed now or last), else the plant's since it started.
func open_debrief() -> void:
	_right_open(debrief)


func close_debrief() -> void:
	debrief.visible = false
	mimic.take_focus()


func debrief_tracker():
	return tracker if tracker != null and not tracker.is_tour() else run_tracker


func toggle_procedure() -> void:
	if procedure.visible:
		close_procedure()
	else:
		crew.visible = false
		procedure.open()
		_release_mouse()


func close_procedure() -> void:
	procedure.visible = false
	mimic.take_focus()


## The permits to work (PLANT3D §15): the list, a work's form (its id), or the form of the work at a code.
func open_permits(wid := "", code := "") -> void:
	if card.visible:
		close_card()
	for q in [alarms, trainer, debrief]:
		q.visible = false
	if code != "":
		permits.open_for_code(code)
	else:
		permits.open(wid)
	_release_mouse()


# ------------------------------------------------------------------ Together: a multiplayer session (MULTIPLAYER.md)

func toggle_session() -> void:
	if session_panel.visible:
		close_session()
	else:
		open_session()


func open_session() -> void:
	_right_open(null)
	procedure.visible = false
	crew.visible = false
	session_panel.open()


func close_session() -> void:
	session_panel.visible = false


## Hosts (host) or joins a session; "" or why not. The single-player run is saved first and kept apart: a session
## never saves over it (§7.4).
func start_session(host: bool, scenario: String, code_text: String, address: String, from_save: Dictionary) -> String:
	if session != null and session.active():
		return "A session is open already."
	_drop_session()
	if autosave.armed:
		autosave.save_now()
	session = Session.new()
	session.name = "session"
	add_child(session)
	session.model = model
	session.clock = clock
	session.content = autosave.content
	session.display_name = session_panel.my_name()
	if session_ports.size() == 2:
		session.discovery_port = session_ports[0]
		session.session_port = session_ports[1]
	session.install_engine = adopt_engine
	session.my_pos = _walker_state
	session.notice.connect(func(t): toast(t); session_panel.note(t))
	session.ended.connect(_session_ended)
	session.changed.connect(_session_changed)
	var why: String = session.host(scenario, from_save) if host else session.join(code_text, address)
	if why != "":
		_drop_session()
		return why
	autosave.armed = false
	inputs.sink = session.send_input
	clock.speed_request = _session_speed
	others = OthersView.new()
	others.name = "others"
	main.add_child(others)
	others.setup(self, session)
	DisplayServer.screen_set_keep_on(true)          # (a phone's screen off stops the session, §7.5)
	var m := AndroidNet.multicast(true)
	if m != "":
		push_warning("multicast lock: " + m)
	_host_save_t = 0.0
	_host_save_step = -1
	_session_changed()
	return ""


func _drop_session() -> void:
	if others != null:
		others.queue_free()
		others = null
	if session != null:
		session.queue_free()
		session = null
	inputs.sink = Callable()
	clock.speed_request = Callable()


## Leaves the session (a player) or ends it (the host).
func end_session() -> void:
	if session != null and session.active():
		session.leave()
	elif session != null:
		_session_ended("")


func _session_changed() -> void:
	if session == null:
		return
	inputs.slot = maxi(session.slot, 0)
	session_panel._sig = ""
	_refresh_bar()


## A speed asked for in a session goes to the host (§7.1, §7.2): a pause, a run, the player's vote for fast-forward.
func _session_speed(s: int) -> void:
	if session == null or not session.active():
		return
	match s:
		SimClock.Speed.PAUSED:
			session.request_pause()
		SimClock.Speed.NORMAL:
			if session.paused:
				session.request_run()
			elif session.fast or session.my_entry().get("fast", false):
				session.vote_fast(false)
		SimClock.Speed.FAST:
			var b: String = clock.ff_blocked()
			if b != "":
				toast("No fast-forward: " + b + ".")
				return
			session.vote_fast(true)
			if not session.fast:
				toast("Ready for fast-forward: it starts when everyone is ready.")


## The walker for `pos` (§6.3): feet, heading, pitch, speed in tenths of m/s.
func _walker_state() -> Array:
	var v: Vector3 = player.velocity if "velocity" in player else Vector3.ZERO
	return [player.global_position, player.rotation.y, player.pivot.rotation.x, clampi(int(round(v.length() * 10.0)), 0, 255)]


## The session's engine is the run's from now on (a join, a rejoin, a resync: net/session.gd made it on a worker
## thread). As restart() does, with the panels following the engine's whole log at once (as a loaded save does).
func adopt_engine(e) -> void:
	clock.install(e)
	bindings.use_engine(e)
	sounds.engine = e
	sounds.reset_edges()
	alarms.since.clear()
	alarms._sig = ""
	trends.clear()
	results.clear()
	_pending.clear()
	permits.results.clear()
	permits._pending.clear()
	permits._sig = ""
	alarms.on_events(e.events, 0)
	_ev_seen = e.events.size()
	_arrived = -2
	_zones = -1
	_jumps = e.J
	crew._sig = ""
	permits.waiting_from(e)


func _session_tick(delta: float) -> void:
	if session == null or not session.active() or not session.is_host() or session.state != Session.State.RUN:
		return
	# the host saves the session every 5 s while it changes, to its own file (§7.4); written on a worker thread
	_host_save_t += delta
	if _host_save_t < Autosave.INTERVAL or clock.engine.step_no == _host_save_step:
		return
	if _save_job != -1 and not WorkerThreadPool.is_task_completed(_save_job):
		return
	if _save_job != -1:
		WorkerThreadPool.wait_for_task_completion(_save_job)
	_host_save_t = 0.0
	_host_save_step = clock.engine.step_no
	var d := Snapshot.take(clock.engine, session.scenario, autosave.content,
			{"step": clock.engine.step_no, "roster": session.roster, "settings": session.settings})
	_save_job = WorkerThreadPool.add_task(func(): Snapshot.write_file(SessionPanel.HOST_SAVE, d))


func _session_ended(why: String) -> void:
	if session == null:
		return
	# the players keep a copy of the shared run (§7.4): continued alone from it, or looked at in its debrief
	var e = clock.engine
	if e != null and e.st_session and not session.is_host():
		var d := Snapshot.take(e, session.scenario, autosave.content,
				{"step": e.step_no, "roster": session.roster, "settings": session.settings, "slot": session.slot})
		Snapshot.write_file(SessionPanel.LAST_SAVE, d)
	if _save_job != -1:
		WorkerThreadPool.wait_for_task_completion(_save_job)
		_save_job = -1
	if why != "":
		toast(why, 8.0)
		session_panel.note(why)
	DisplayServer.screen_set_keep_on(false)
	AndroidNet.multicast(false)
	Session.forget_session()
	_drop_session.call_deferred()
	clock.driven = false
	clock.speed = SimClock.Speed.PAUSED
	clock.speed_changed.emit(clock.speed, "")
	open_session.call_deferred()


## The last session's copy goes on as a single-player run (§7.4): the other players' people go to the crews.
func continue_alone() -> void:
	var d = Snapshot.read_file(SessionPanel.LAST_SAVE)
	if typeof(d) == TYPE_STRING:
		toast("The last session can't be continued: " + d)
		return
	var bad := Snapshot.check(d, model, autosave.content)
	if bad != "":
		toast("The last session can't be continued: " + bad)
		return
	var PlantEngine = load("res://sim/engine.gd")
	var e = PlantEngine.new(model, d["scenario"], true)
	RunSave.apply(e, d["engine"])
	var mine: int = int(d["session"].get("slot", 0)) if typeof(d["session"].get("slot")) == TYPE_INT else 0
	for k in 8:
		if k != mine and e.trainee(k) != -1:
			e.apply_input([e.step_no + 1, "release", k])
	clock.scenario = d["scenario"]
	adopt_engine(e)
	inputs.slot = mine
	clock.driven = false
	autosave.armed = true
	close_session()
	toast("Alone now: the others' roles went to the crews.")
	clock.set_speed(SimClock.Speed.NORMAL)


func _notification(what: int) -> void:
	if session == null or not session.active():
		return
	# Android's lifecycle (§7.5): going to the background stops the main loop, and with it the session
	if what == NOTIFICATION_APPLICATION_PAUSED:
		session.set_away(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		session.set_away(false)


func toggle_crew() -> void:
	if crew.visible:
		close_crew()
	else:
		open_crew()


func open_crew() -> void:
	procedure.visible = false
	crew.open()
	_release_mouse()


func close_crew() -> void:
	crew.visible = false
	mimic.take_focus()


func toggle_permits() -> void:
	if permits.visible:
		close_permits()
	else:
		open_permits()


func close_permits() -> void:
	permits.visible = false
	mimic.take_focus()


func toggle_trainer() -> void:
	if trainer.visible:
		close_trainer()
	else:
		_right_open(trainer)


func close_trainer() -> void:
	trainer.visible = false
	mimic.take_focus()


func set_instructor(on: bool) -> void:
	instructor = on
	_trainer_btn.visible = on
	if not on:
		trainer.visible = false


## Closes the topmost panel; false when none was open.
func close_top() -> bool:
	if session_panel.visible:
		close_session()
	elif trainer.visible:
		close_trainer()
	elif permits.visible:
		close_permits()
	elif debrief.visible:
		close_debrief()
	elif alarms.visible:
		close_alarms()
	elif card.visible:
		close_card()
	elif screens_open():
		close_screens()
	elif procedure.visible:
		close_procedure()
	elif crew.visible:
		close_crew()
	else:
		return false
	return true


func start_procedure(id: String, step_id = null, restart_scenario := false) -> void:
	var pr: Dictionary = model.procedures[id]
	if restart_scenario and pr.has("scenario"):
		restart(pr["scenario"])
	if tracker != null:
		tracker.stop(clock.engine)          # the one followed until now ends here
	tracker = Tracker.new()
	tracker.step_changed.connect(_on_step_changed)
	tracker.step_done.connect(func(_id): clock.hold = true)
	tracker.deviation.connect(func(t): toast("Outside the procedure: " + t))
	tracker.begin(pr, clock.engine, step_id)
	if not tracker.is_tour():               # a tour has no debrief: the last procedure's stays
		run_tracker = tracker
	if debrief.visible:
		debrief.refresh(true)
	procedure.open()


func stop_procedure() -> void:
	if tracker != null:
		tracker.stop(clock.engine)
	tracker = null
	walking = false
	if route:
		route.clear()
	if debrief != null and debrief.visible:
		debrief.refresh(true)
	if pointer:
		pointer.clear()
	if procedure:
		procedure.rebuild()


func _on_step_changed(_i: int) -> void:
	procedure.on_step_changed()
	if tracker == null:
		return
	var at: Array = tracker.current().get("at", [])
	# a step to walk to: the way on foot to what it points at (show_me), until the step ends
	walking = tracker.current().get("go", "") == "walk" and not at.is_empty()
	if not walking:
		route.clear()
	if at.is_empty():
		return
	if tracker.is_tour() and procedure.fly_box.button_pressed:
		fly_to(at[0])
	elif index.has(at[0]):
		show_me(at[0])
	else:
		pointer.clear()
		route.clear()


# ------------------------------------------------------------------ links in

func handle_link(url: String) -> void:
	var r: Dictionary = Links.read_link(url, model)
	print("plant: link %s opens %s" % [url.left(80), JSON.stringify(r)])
	match r["open"]:
		"kks":
			var asked := url.get_slice("/", 3).left(24)
			var note := ""
			if asked != r["code"] and r["match"] == "exact":
				note = "The link named %s: this is %s, the code it begins with." % [asked, r["code"]]
			match r["match"]:
				"without_a3":
					note = "The link named %s: this is the equipment it belongs to." % asked
				"same_kind", "same_equipment":
					note = "%s is not in this plant. This is the plant's equipment of the same kind: %s." % [asked, r["code"]]
				"decode":
					note = "%s is not in this plant, which has nothing of that kind: here is what the code means." % asked
			open_card(r["code"], note)
		"procedure":
			procedure.offer(r["id"], r["step"])
		"join":
			# a session's invite (MULTIPLAYER.md §1.1): the code goes to Together and the join starts
			if session != null and session.active():
				toast("Already in a session: leave it first to join another.")
				return
			autosave.withdraw_offer()
			open_session()
			session_panel.join(r["code"])
		_:
			toast("This link is not one Walkdown Plant opens.")


# ------------------------------------------------------------------ every step and frame

func _on_step(e) -> void:
	trends.on_step(e)
	_sync_events()
	sounds.on_step()
	if tracker != null:
		tracker.on_step(e)


## The events since the last look: alarm times, operations' results, trips, sequence steps, one-shot sounds.
func _sync_events() -> void:
	var evs: Array = clock.engine.events
	if _ev_seen < evs.size():
		var from := _ev_seen
		_ev_seen = evs.size()
		alarms.on_events(evs, from)
		permits.on_events(evs, from)
		_follow_events(evs, from)


func _on_speed(_s: int, why: String) -> void:
	if why != "":
		toast(why)
	_refresh_bar()


func _refresh_bar() -> void:
	if _pause_btn == null:
		return
	_pause_btn.modulate = Color(1, 0.8, 0.3) if clock.speed == SimClock.Speed.PAUSED else Color.WHITE
	_play_btn.modulate = Color(1, 0.8, 0.3) if clock.speed == SimClock.Speed.NORMAL else Color.WHITE
	_ff_btn.modulate = Color(1, 0.8, 0.3) if clock.speed == SimClock.Speed.FAST else Color.WHITE


func _process(delta: float) -> void:
	var _c0 := Time.get_ticks_usec()
	_each_frame(delta)
	Cost.add(Cost.UI, _c0)


func _each_frame(delta: float) -> void:
	if clock == null:
		_toast_tick(delta)
		return
	_sync_events()
	_ui_t += delta
	_horn_tick()
	_blink += delta
	# the clock's text changes with a step or the speed; in fast-forward (a step or more every frame) it is shown
	# again FAST_UI_HZ times a second, as the alarms' counts (_horn_tick)
	var tk := Vector3i(clock.engine.step_no, clock.speed, roundi(clock.ff_rate()) if clock.speed == SimClock.Speed.FAST else 0)
	if clock.engine != _time_engine or (tk != _time_key and (tk.y != _time_key.y or tk.y != SimClock.Speed.FAST
			or _ui_t - _time_t >= 1.0 / FAST_UI_HZ)):
		_time_key = tk
		_time_engine = clock.engine
		_time_t = _ui_t
		var ff: float = session.rate if session != null and session.active() else clock.ff_rate()
		_time.text = "%s %s" % [clock_text(), {0: "paused", 1: "×1", 2: "×%.0f" % ff}[clock.speed]]
	_place_t += delta
	if _place_t >= 0.25:
		_place_t = 0.0
		_place_tick()
	if session != null:
		_session_tick(delta)
	_toast_tick(delta)
	_t_hint += delta
	if _t_hint >= 0.1:
		_t_hint = 0.0
		_look_hint()
	sounds.listener_at = eye()
	# the arrow to the equipment pointed at follows the view each frame while there is one (once more when it goes)
	var arrow: bool = pointer != null and pointer.visible
	if arrow or _arrow_drawn:
		arrows.queue_redraw()
	_arrow_drawn = arrow
	_fit_t += delta
	if _fit_t >= 0.25:
		_fit_t = 0.0
		_fit()


var _fit_t := 0.0
var _max_h := 0.0
var _alarms_engine = null       # _horn_tick: the engine and step its counts are of
var _alarms_step := -1
var _alarms_unack := 0
var _alarms_speed := -1
var _alarms_t := 0.0
var _time_engine = null         # the clock's text: the engine, step, speed and rate it shows, and when (_ui_t)
var _time_key := Vector3i(-1, -1, -1)
var _time_t := 0.0
var _ui_t := 0.0                # seconds of frames gone
const FAST_UI_HZ := 4.0         # in fast-forward the bar's clock and alarms are shown again at most this often
var _arrow_drawn := false       # the arrows' layer was drawn with an arrow last frame


## The side panels as tall as their content (up to the bottom of the screen), so the view and the sticks stay free.
func _fit() -> void:
	for pnl in [card, procedure, alarms, trainer, debrief, permits]:
		if pnl.visible:
			W.fit(pnl, _max_h)


func _toast_tick(delta: float) -> void:
	if _toast_t > 0.0:
		if card != null and card.visible != _toast_beside_card:
			_toast_beside_card = card.visible
			_layout_toast()                  # a card opened under the word: the word moves clear of it
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.text = ""
			_toast.visible = false


func _follow_events(evs: Array, from: int) -> void:
	var e = clock.engine
	for i in range(from, evs.size()):
		var ev: Array = evs[i]
		match ev[1]:
			"unsafe", "stop":
				_safety_toast(e, ev)
			"op":
				for k in _pending.size():         # the events come in the order the inputs were made
					var p: Array = _pending[k]
					if p[1]["kks"] == ev[2] and p[1]["do"] == ev[3] and ev[0] >= p[2] \
							and (ev.size() < 8 or ev[7] == me()):      # not a colleague's op (§17.1)
						var o: Dictionary = p[1]
						var txt := ""
						match ev[4]:
							"done": txt = "Done at %s" % W.model_time(ev[0])
							"refused":
								var why := PackedStringArray()
								for f in ev[5]:
									why.append(info.failed_text(o, f, e))
								txt = "Refused: " + "; ".join(why)
							_: txt = "Not an operation of this plant"
						results[p[0]] = {"state": ev[4], "text": txt, "step": ev[0]}
						_pending.remove_at(k)
						if ev[4] == "refused":
							toast("%s %s refused: %s" % [ev[2], info.op_label(o).to_lower(), txt.trim_prefix("Refused: ")])
						break
				if ev[4] == "done" and ev[3] == "start":
					var n = index.nodes.get(ev[2])
					if n != null and sounds.sound_of(n) == "motor_large" and n.global_position.distance_to(eye()) < sounds.EARSHOT:
						sounds.once("motor_start", n)
			"trip":
				var t = model.trip_by_id(ev[2])
				toast("TRIP: %s%s" % [t.get("text", ev[2]) if t != null else ev[2], " (first out)" if ev[3] else ""], 6.0)
			"machine":
				var mi: int = info.machine_index(ev[2])
				if mi >= 0:
					var say: String = model.machines[mi]["states"][_state_pos(mi, ev[4])].get("say", "")
					if say != "":
						toast(say)
			"repair":
				if ev.size() >= 7 and ev[6] is Array:     # the trainee's repair under a permit, not made (§15.5)
					toast("Repair not made: %s" % ("; ".join(ev[6].map(func(x): return Debrief.REPAIR_WHY.get(x, str(x))))
							if ev[5] == "refused" else "not a repair of that permit's work"))


func _state_pos(mi: int, state: String) -> int:
	return model.machines[mi]["_ids"].find(state)


## The alarms' horn and button, and fast-forward's button. What they show changes only with a model step (every input
## is applied in one, a restart makes another engine): looked at again only then, not every frame; and in fast-forward,
## which runs steps every frame, FAST_UI_HZ times a second. Fast-forward stops on any alarm the horn sounds for
## (SimClock.ff_blocked), so the horn is never late: the speed's change has it looked at again at once.
func _horn_tick() -> void:
	var e = clock.engine
	if e != _alarms_engine or clock.speed != _alarms_speed or (e.step_no != _alarms_step
			and (clock.speed != SimClock.Speed.FAST or _ui_t - _alarms_t >= 1.0 / FAST_UI_HZ)):
		_alarms_engine = e
		_alarms_step = e.step_no
		_alarms_speed = clock.speed
		_alarms_t = _ui_t
		var top := 0
		var unack := 0
		var active := 0
		for k in e._al.size():
			var s: String = e.astate[k]
			if s == "normal" or e.shelved[k] != -1 or AlarmPanel.suppressed(e, k):
				continue
			active += 1
			if s == "active_unack" or s == "cleared_unack":
				unack += 1
				var pr: int = e._al[k][5]
				if top == 0 or pr < top:
					top = pr
		_alarms_unack = unack
		if top != _horn:
			_horn = top
			horn_changed.emit(top)
		_alarm_btn.text = "Alarms %d" % active if active > 0 else "Alarms"
		_ff_btn.disabled = clock.ff_blocked() != ""
	var unack := _alarms_unack
	var top := _horn
	if unack > 0:
		var on := fmod(_blink, 0.8) < 0.5
		_alarm_btn.modulate = W.PRIO_COLOURS.get(top, Color.WHITE) if on else Color.WHITE
	else:
		_alarm_btn.modulate = Color.WHITE


## The part at the middle of the view (keyboard, mouse captured, gamepad): its code and a hint.
func _look_hint() -> void:
	hover = ""
	var pad: bool = main.hud != null and main.hud.pad_on()
	var show := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or pad
	if show and not main.map.active and not main.hud.panel.visible and not screens_open():
		var cam: Camera3D = player.camera
		var c: String = index.pick(cam, root.get_viewport_rect().size * 0.5, player.get_world_3d().direct_space_state, [player.get_rid()])
		if c != "" and index.distance(c, eye()) <= HINT_RANGE:
			hover = c
	var what := "the screens" if info.part_of(hover) == "operator_desk" else "its card"
	var key := "A" if pad else "E"
	_hint.text = ("+\n%s  %s\n%s: %s" % [hover, info.name_of(hover), key, what]) if hover != "" else ("+" if show and not screens_open() else "")


func _unhandled_input(ev: InputEvent) -> void:
	if clock == null or player.scripted:
		return
	if ev.is_action_pressed("menu") or ev.is_action_pressed("ui_cancel"):
		if close_top():
			get_viewport().set_input_as_handled()
		return
	if main.map.active or main.hud.panel.visible:
		return
	if ev.is_action_pressed("home"):
		control_room(); get_viewport().set_input_as_handled()
		return
	# with the screens open the view is theirs (ui/mimic.gd): no picking in the plant; the panels' keys still work
	if ev.is_action_pressed("use") and hover != "" and not _door_near() and not screens_open():
		open_card(hover)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("alarms"):
		toggle_alarms(); get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("procedure"):
		toggle_procedure(); get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("permits"):
		toggle_permits(); get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("crew"):
		toggle_crew(); get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("pause"):
		clock.set_speed(SimClock.Speed.NORMAL if clock.speed == SimClock.Speed.PAUSED else SimClock.Speed.PAUSED)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("fast"):
		fast_forward(); get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not screens_open():
		var at: Vector2 = ev.position
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			at = root.get_viewport_rect().size * 0.5
		var c: String = index.pick(player.camera, at, player.get_world_3d().direct_space_state, [player.get_rid()])
		if c != "":
			open_card(c)
			get_viewport().set_input_as_handled()


## A door within reach: E (gamepad A) opens it, as before the cards.
func _door_near() -> bool:
	for d in get_tree().get_nodes_in_group("doors"):
		if (d as Node3D).global_position.distance_to(player.global_position) < 3.0:     # player.press_door's reach
			return true
	return false


## The way to the equipment pointed at: an arrow at the screen's edge when it is out of view, and its distance.
func _draw_arrows() -> void:
	if pointer == null or not pointer.visible:
		return
	var cam: Camera3D = player.camera
	var p: Vector3 = pointer.top()
	var vs: Vector2 = root.get_viewport_rect().size
	var d: float = index.distance(pointer.code, eye())
	var unit := "m"
	if route != null and route.shown():
		d = route.left
		unit = "m on foot"
	var font := root.get_theme_default_font()
	var fs := int(20 * W.scale)
	var centre := vs * 0.5
	var on_screen := not cam.is_position_behind(p)
	var sp := cam.unproject_position(p) if on_screen else Vector2.ZERO
	if on_screen and Rect2(Vector2(40, 40), vs - Vector2(80, 80)).has_point(sp):
		arrows.draw_string_outline(font, sp + Vector2(-30, -20), "%.0f %s" % [d, unit], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
		arrows.draw_string(font, sp + Vector2(-30, -20), "%.0f %s" % [d, unit], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.7, 0.2))
		return
	# out of view: the direction in the camera's frame, flattened onto the screen
	var local := cam.global_transform.affine_inverse() * p
	var dir := Vector2(local.x, -local.y)
	if local.z > 0.0 and dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var r := minf(vs.x, vs.y) * 0.42
	var tip := centre + dir * r
	var side := Vector2(-dir.y, dir.x)
	var s := 26.0 * W.scale
	arrows.draw_colored_polygon(PackedVector2Array([tip, tip - dir * s + side * s * 0.6, tip - dir * s - side * s * 0.6]), Color(1, 0.6, 0.1, 0.95))
	arrows.draw_string_outline(font, tip - dir * s * 2.2 + Vector2(-30, 8), "%.0f %s" % [d, unit], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
	arrows.draw_string(font, tip - dir * s * 2.2 + Vector2(-30, 8), "%.0f %s" % [d, unit], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.7, 0.2))


## Unsafe acts and stopped work concerning the trainee (PLANT3D §16.7, §17.11), as a line on the screen.
func _safety_toast(e, ev: Array) -> void:
	var sm = e._sm
	var pi := my_person()
	if sm == null or pi == -1:
		return
	var me_id: String = sm.people[pi]["id"]
	if ev[1] == "unsafe" and ev[2] == me_id:
		var k: int = sm.ACT_KINDS.find(ev[3])
		toast("Unsafe act: you are " + CrewPanel.act_text(sm, k, [ev[4], ev[0], false]))
	elif ev[1] == "stop" and ev[3] == me_id and ev[6] == "done":
		toast("%s stopped your work: %s. Put it right (your tasks)." % [sm.people[sm.person_ix[ev[2]]]["call"]
				if sm.person_ix.has(ev[2]) else str(ev[2]), CrewPanel.act_text(sm, sm.ACT_KINDS.find(ev[4]), [ev[5]])])
	elif ev[1] == "stop" and ev[2] == me_id:
		if ev[6] == "done":
			toast("You stopped the work of %s." % sm.people[sm.person_ix[ev[3]]]["call"])
		else:
			toast("Not stopped: %s" % ("you have no authority to stop work" if "authority" in ev[7]
					else "no unsafe act of theirs goes on"))
