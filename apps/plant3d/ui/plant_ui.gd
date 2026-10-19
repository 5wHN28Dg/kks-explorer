## Walkdown Plant's interaction layer (docs/PLANT3D.md §6–§8, decision 0054): runs the behaviour engine at 0.1 s
## steps (ui/sim_clock.gd), and lets the trainee operate the plant through equipment cards (look or tap at a part),
## follow the alarms, procedures and tours, and open links. It sits over the app's frame (app/main.gd, app/hud.gd).
##
## Keys and buttons (app/controls.gd): E or a tap at a part opens its card (gamepad A), L the alarms (D-pad up),
## P procedures and tours (D-pad left), K pause and run (D-pad down), the full stop key fast-forward (D-pad right),
## H back to the control room (gamepad X), Esc or B closes the top panel. The debrief (what happened in the run) opens
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
const Autosave = preload("res://ui/autosave.gd")
const DebriefPanel = preload("res://ui/debrief_panel.gd")
const WalkRoute = preload("res://app/walk_route.gd")

const CONTENT := "res://built/content"
const REACH := 6.0              # metres: within this a trainee works the equipment's local controls
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
var autosave                    # ui/autosave.gd: the run saved to user://, offered again at start
var debrief
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
	_bar_button(bar, "Control room", func(): go_control_room())
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
	var top := 88.0 + 56.0 * W.scale + 16.0
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
	debrief.position = card.position
	debrief.size = card.size
	_hint.position = Vector2(vs.x * 0.5 - 400.0, vs.y * 0.5 + 24.0)
	_hint.size = Vector2(800.0, 60.0)
	_layout_toast()


func _layout_toast() -> void:
	var vs: Vector2 = root.get_viewport_rect().size
	# between the side panels when they are open (on a phone it may reach over them: it has its own background)
	var side := 0.0
	if card != null and (card.visible or alarms.visible or trainer.visible or procedure.visible or debrief.visible):
		side = card.size.x + 32.0
	var w := clampf(vs.x - 2.0 * side, 360.0, minf(vs.x * 0.5, 900.0))
	_toast.position = Vector2((vs.x - w) * 0.5, vs.y - 200.0 * W.scale)
	_toast.size = Vector2(w, 0)


## The layer's rows in the settings panel (app/hud.gd), kept in the app's settings file.
func add_settings(box: VBoxContainer) -> void:
	if clock == null:
		return
	var cf: ConfigFile = main.cf
	for row in [["instructor", "Instructor mode: scenarios and trainer faults", false],
			["reduced_motion", "Reduced motion: no camera shake near machines", false],
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
		"reduced_motion": bindings.reduced_motion = on
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
	elif p.begins_with("card:"):
		open_card(p.substr(5))


# ------------------------------------------------------------------ where the trainee is

func eye() -> Vector3:
	return player.camera.global_position


func distance_to(code: String) -> float:
	return index.distance(code, player.global_position + Vector3.UP * 1.0)


func near(code: String) -> bool:
	return index.has(code) and distance_to(code) <= REACH


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


func ack(alarm: String) -> void:
	clock.engine.ack(alarm)
	sounds.once("horn_ack")


func shelve(alarm: String, seconds: float) -> void:
	clock.engine.shelve(alarm, seconds)
	toast("Shelved for %s of plant time." % W.model_time(int(seconds * 10)))


func unshelve(alarm: String) -> void:
	clock.engine.unshelve(alarm)


func fault(fid: String) -> void:
	clock.engine.fault(fid)
	toast("Fault pressed: it acts in the next step.")


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
	results.clear()
	_pending.clear()
	_ev_seen = 0
	if not quiet:
		toast("The plant restarted: %s." % model.scenarios[scenario].get("title", scenario))


# ------------------------------------------------------------------ cards, pointing, moving

func open_card(code: String, note := "") -> void:
	alarms.visible = false
	trainer.visible = false
	debrief.visible = false
	card.open(code, note)
	if index.has(code):
		show_me(code)
	_release_mouse()


func close_card() -> void:
	card.visible = false
	card.code = ""


func show_me(code: String) -> void:
	if not index.has(code):
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
	show_me(code)
	var b: AABB = index.box(code)
	var c := b.get_center()
	var from: Vector3 = player.global_position
	var dir := Vector3(from.x - c.x, 0, from.z - c.z)
	if dir.length() < 0.1:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	var r := maxf(b.size.x, b.size.z) * 0.5
	var to := c + dir * minf(r + 2.5, 40.0)
	# stand on the floor beside it (a platform, a grating, the ground), not at the foot of a column in a pit
	var hit: Dictionary = player.floor_below(Vector3(to.x, b.end.y + 1.0, to.z), b.size.y + 40.0)
	to.y = (hit.position.y if not hit.is_empty() else maxf(b.position.y, 0.0)) + 0.05
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


func go_control_room() -> void:
	var st: Array = main.plant.start()
	if _flight:
		_flight.kill()
	player.scripted = false
	player.set_mode(player.Mode.FLY)
	player.global_position = st[0]
	player.set_heading(st[1])
	player.set_mode(player.Mode.WALK)
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
	for q in [card, alarms, trainer, debrief]:
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


## The debrief of the run: the procedure's (followed now or last), else the plant's since it started.
func open_debrief() -> void:
	_right_open(debrief)


func close_debrief() -> void:
	debrief.visible = false


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


func toggle_trainer() -> void:
	if trainer.visible:
		close_trainer()
	else:
		_right_open(trainer)


func close_trainer() -> void:
	trainer.visible = false


func set_instructor(on: bool) -> void:
	instructor = on
	_trainer_btn.visible = on
	if not on:
		trainer.visible = false


## Closes the topmost panel; false when none was open.
func close_top() -> bool:
	if trainer.visible:
		close_trainer()
	elif debrief.visible:
		close_debrief()
	elif alarms.visible:
		close_alarms()
	elif card.visible:
		close_card()
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
	for pnl in [card, procedure, alarms, trainer, debrief]:
		if pnl.visible:
			W.fit(pnl, _max_h)


func _toast_tick(delta: float) -> void:
	if _toast_t > 0.0:
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
	if show and not main.map.active and not main.hud.panel.visible:
		var cam: Camera3D = player.camera
		var c: String = index.pick(cam, root.get_viewport_rect().size * 0.5, player.get_world_3d().direct_space_state, [player.get_rid()])
		if c != "" and index.distance(c, eye()) <= HINT_RANGE:
			hover = c
	_hint.text = ("+\n%s  %s\nE or A: its card" % [hover, info.name_of(hover)]) if hover != "" else ("+" if show else "")


func _unhandled_input(ev: InputEvent) -> void:
	if clock == null or player.scripted:
		return
	if ev.is_action_pressed("menu") or ev.is_action_pressed("ui_cancel"):
		if close_top():
			get_viewport().set_input_as_handled()
		return
	if main.map.active or main.hud.panel.visible:
		return
	if ev.is_action_pressed("use") and hover != "" and not _door_near():
		open_card(hover)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("alarms"):
		toggle_alarms(); get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("procedure"):
		toggle_procedure(); get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("pause"):
		clock.set_speed(SimClock.Speed.NORMAL if clock.speed == SimClock.Speed.PAUSED else SimClock.Speed.PAUSED)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("fast"):
		fast_forward(); get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("home"):
		go_control_room(); get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
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
