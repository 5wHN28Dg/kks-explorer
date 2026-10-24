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
	_bar_button(bar, "Control room", func(): control_room())
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
	debrief = DebriefPanel.new()
	debrief.name = "debrief"
	root.add_child(debrief)
	debrief.setup(self)
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
	alarms.position = card.position
	alarms.size = card.size
	trainer.position = card.position
	trainer.size = card.size
	permits.position = card.position
	permits.size = card.size
	debrief.position = card.position
	debrief.size = card.size
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


## Opens a panel by name (the command line's panels=…): alarms, procedure, card:CODE. (Not the instructor's:
## on Android these options can come from a shared folder.)
func open_panel(p: String) -> void:
	if clock == null:
		return
	if p == "alarms" and not alarms.visible:
		toggle_alarms()
	elif p == "procedure" and not procedure.visible:
		toggle_procedure()
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


## Gamepad or keyboard in use (no touch screen): panels take the focus so that they can be worked without a mouse.
func wants_focus() -> bool:
	return not DisplayServer.is_touchscreen_available()


# ------------------------------------------------------------------ the trainee's inputs to the plant

func do_op(o: Dictionary, value) -> void:
	var key := Tracker.op_key(o["kks"], o["do"], o.get("trip"))
	clock.engine.op(o["kks"], o["do"], value, o.get("trip"))
	_pending.append([key, o, clock.engine.step_no + 1])
	var paused: bool = clock.speed == SimClock.Speed.PAUSED
	results[key] = {"state": "sent", "text": "Sent%s" % (": it takes effect when the plant runs (paused)" if paused else "…")}


func op_result(o: Dictionary) -> Dictionary:
	return results.get(Tracker.op_key(o["kks"], o["do"], o.get("trip")), {})


func ack(alarm: String, sound := true) -> void:
	clock.engine.ack(alarm)
	if sound:
		sounds.once("horn_ack")


func shelve(alarm: String, seconds: float) -> void:
	clock.engine.shelve(alarm, seconds)
	toast("Shelved for %s of plant time." % W.model_time(int(seconds * 10)))


func unshelve(alarm: String) -> void:
	clock.engine.unshelve(alarm)


func fault(fid: String) -> void:
	clock.engine.fault(fid)
	toast("Fault pressed: it acts in the next step.")


## A fault's repair (PLANT3D §7.8): from the instructor's panel, or, in a plant without permits to work (version 1),
## by the trainee at its equipment (the card).
func repair(fid: String) -> void:
	clock.engine.repair(fid)
	toast("Repaired: it acts in the next step.")


## The trainee's repair at the equipment under a work's permit to work (PLANT3D §15.5, a version 2 plant).
func repair_under(fid: String, wid: String) -> void:
	clock.engine.repair_under(fid, wid)
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
	if not quiet:
		toast("The plant restarted: %s." % model.scenarios[scenario].get("title", scenario))


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
	if trainer.visible:
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
	if clock == null:
		_toast_tick(delta)
		return
	_sync_events()
	_horn_tick()
	_blink += delta
	_time.text = "%s %s" % [clock.clock_text(), {0: "paused", 1: "×1", 2: "×%.0f" % clock.ff_rate()}[clock.speed]]
	_ff_btn.disabled = clock.ff_blocked() != ""
	_toast_tick(delta)
	_t_hint += delta
	if _t_hint >= 0.1:
		_t_hint = 0.0
		_look_hint()
	sounds.listener_at = eye()
	arrows.queue_redraw()
	_fit_t += delta
	if _fit_t >= 0.25:
		_fit_t = 0.0
		_fit()


var _fit_t := 0.0
var _max_h := 0.0


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
			"op":
				for k in _pending.size():         # the events come in the order the inputs were made
					var p: Array = _pending[k]
					if p[1]["kks"] == ev[2] and p[1]["do"] == ev[3] and ev[0] >= p[2]:
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


func _horn_tick() -> void:
	var e = clock.engine
	var top := 0
	var unack := 0
	for k in e._al.size():
		var s: String = e.astate[k]
		if (s == "active_unack" or s == "cleared_unack") and e.shelved[k] == -1 and not AlarmPanel.suppressed(e, k):
			unack += 1
			var pr: int = e._al[k][5]
			if top == 0 or pr < top:
				top = pr
	if top != _horn:
		_horn = top
		horn_changed.emit(top)
	var active := 0
	for k in e._al.size():
		if e.astate[k] != "normal" and e.shelved[k] == -1 and not AlarmPanel.suppressed(e, k):
			active += 1
	_alarm_btn.text = "Alarms %d" % active if active > 0 else "Alarms"
	if unack > 0:
		var on := fmod(_blink, 0.8) < 0.5
		_alarm_btn.modulate = W.PRIO_COLOURS.get(top, Color.WHITE) if on else Color.WHITE
	else:
		_alarm_btn.modulate = Color.WHITE


## The part at the middle of the view (keyboard, mouse captured, gamepad): its code and a hint.
func _look_hint() -> void:
	hover = ""
	var show := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not Input.get_connected_joypads().is_empty()
	if show and not main.map.active and not main.hud.panel.visible and not screens_open():
		var cam: Camera3D = player.camera
		var c: String = index.pick(cam, root.get_viewport_rect().size * 0.5, player.get_world_3d().direct_space_state, [player.get_rid()])
		if c != "" and index.distance(c, eye()) <= HINT_RANGE:
			hover = c
	var what := "the screens" if info.part_of(hover) == "operator_desk" else "its card"
	_hint.text = ("+\n%s  %s\nE or A: %s" % [hover, info.name_of(hover), what]) if hover != "" else ("+" if show and not screens_open() else "")


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
