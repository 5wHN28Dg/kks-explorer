## The Workshop mode (docs/plant3d/WORKSHOP.md §2–§4, milestone K1): one part kind alone in a neutral space, taken
## apart with one slider, its parts picked up, moved and turned, hidden and isolated, and put back with Reset; then
## back to the plant exactly where the trainee was.
##
## How it is drawn (§2): a full-screen SubViewport with a world of its own (`own_world_3d`), and the main viewport's
## 3D drawing off (`disable_3d`) while it shows. The plant is neither moved nor freed; its sounds are muted. In single
## play the plant's clock pauses (hold-to-run motions released first) and its speed comes back on leaving; in a
## session the plant runs on, the player's person stands, and `pos` carries the "in the Workshop" flag
## (MULTIPLAYER.md §6.3). The machine is a pre-built scene (`built/workshop/<part>.scn`, builder/workshop_build.gd)
## loaded on a worker thread; nothing here builds geometry, and nothing here names a part kind.
extends CanvasLayer

const Explode = preload("res://workshop/explode.gd")
const Orbit = preload("res://workshop/orbit.gd")
const Panels = preload("res://workshop/panels.gd")
const Assembly = preload("res://workshop/assembly.gd")
const XRAY := preload("res://workshop/ws_xray.gdshader")
const Views = preload("res://workshop/views.gd")
const BenchClock = preload("res://workshop/bench_clock.gd")
const BenchView = preload("res://workshop/bench_view.gd")
const WARM_UP_S := 4.0          # after the plant's first walkable frame: the ghost's pipelines queued (§7.1)
const SimClock = preload("res://ui/sim_clock.gd")
const AlarmPanel = preload("res://ui/alarm_panel.gd")
const DIR := "res://built/workshop"
const SPACE := "res://built/workshop_ui/space.scn"
const MATS := "res://built/materials/%s.tres"
const HANDLE_PX := 16.0         # a pointer this near an arrow or ring of the handle takes it
const ARROW_MIN_PX := 24.0      # an arrow seen nearly end on (shorter than this on screen) can't be taken: a small drag
								# along it would throw the part far
const REASSEMBLE_S := 0.8       # seconds Reassemble all takes

signal shown(part: String)      # the machine's first frame was drawn (entry measured)
signal left                     # back in the plant, its first frame drawn

var main                        # app/main.gd
var ui                          # ui/plant_ui.gd (may be null in a build without it)
var is_open := false
var part := ""
var from_code := ""             # the equipment the card opened it from ("" from the settings)
var container: SubViewportContainer
var vp: SubViewport
var world: Node3D
var cam: Orbit
var sun: DirectionalLight3D
var machine: Node3D             # the part kind's scene, instanced
var handle: Node3D              # the three-axis handle
var panels: Panels
var spec := {}                  # Explode.spec_of(machine)
var comps := {}                 # id -> Node3D
var groups := {}                # id -> Node3D (a fastener group)
var home := {}                  # id -> Transform3D (as built, relative to the parent)
var handled := {}               # id -> Transform3D: handling on top of the explode (cleared by Reset)
var hidden := {}                # id -> true
var s := 0.0                    # the slider
var only_selected := false      # the slider works on the selected subassembly
var root_id := ""               # the subassembly the slider works on ("" the whole machine)
var selected := ""
var words := {}
var entry_ms := -1.0            # Workshop button to the machine's first frame (last entry)
var exit_ms := -1.0             # Back to the plant's first frame (last exit)
var load_ms := -1.0
var note := ""                  # the last refusal or hint (shown by the panels)
var _loading := ""
var _t0 := 0
var _prev_speed := -1
var _prev_muted := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _prev_hud := true
var _prev_ui := true
var _prev_3d := false             # the main viewport's 3D off before (the control room's screens keep it off)
var _session := false
var _mats := {}                 # name -> Material
var _tris := {}                 # Mesh -> [PackedVector3Array of its triangles' corners]
var _reassemble_t := -1.0
var _reassemble_from := 0.0
var _reassemble_handled := {}
var _drag := {}                 # the handle being dragged: {kind, axis, start…}
var _press_at := Vector2.INF
var _last_click := 0
var _alarms_at := {}            # (a session) the alarms unacknowledged when the Workshop opened: {key: true}
var _gen := 0                   # one per entry and exit: a coroutine of an earlier one ends quietly
var _orphans: Array = []        # threaded loads left by a close during loading, collected when done
var _hollow := {}               # id -> true: an ancestor whose own meshes Isolate hid
var _gcentre := {}              # group id -> its items' centre at home, in its host's frame (turned about it)
var _no_click := false          # this press became a pinch or a handle drag: its release selects nothing
var reopen_settings := false    # opened from the settings panel: leaving shows it again (§2: same panels)
var _prev_focus: Control = null
var guide := Assembly.new()     # the guided assembly or disassembly (§4.6): which parts are placed, which loose
var ghost: Node3D               # the next step's part, drawn in place with ws_xray (assembling)
var _ghost_id := ""
var _xray_mat: ShaderMaterial
var _warm: Node3D               # one hidden mesh with ws_xray in the plant's world: its pipelines queued early
var warmed := false
var _warm_draw_mat: ShaderMaterial   # ws_xray at alpha 0: the Workshop load's unseen draw of every part's ghost
var views := Views.new()        # X-ray, cutaway, section, flow; the Workshop's materials (§7)
var bench := BenchClock.new()   # the kind's bench model and its clock (§6)
var bench_view := BenchView.new()   # the bench's values drawn on the machine
var run_note := ""              # the bench's last refusal, as a sentence
var _cur_m := {}                # id -> Transform3D: each part where it stands now, in the machine's frame (apply)

func setup(m) -> void:
	views.ws = self
	bench_view.ws = self
	bench_view.clock = bench
	bench_view.views = views
	main = m
	ui = m.ui if "ui" in m else null
	layer = 60
	visible = false

## The kinds that can be opened: every built scene's part id, sorted.
static func kinds() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for f in DirAccess.get_files_at(DIR):
		var fn := f.trim_suffix(".remap")
		if fn.ends_with(".scn"):
			out.append(fn.get_basename())
	out.sort()
	return out

static func has_kind(p: String) -> bool:
	return p != "" and ResourceLoader.exists(DIR.path_join(p + ".scn"))

## "some_part_kind" -> "Some part kind" (the list's words; the scene's own words come with it).
static func title_of(p: String) -> String:
	return p.replace("_", " ").capitalize().substr(0, 1) + p.replace("_", " ").substr(1)

var force_session := false      # (tests: the plant behaves as in a session, without a network)

func session_on() -> bool:
	return force_session or (ui != null and ui.session != null and ui.session.active())

## Opens the Workshop on a part kind (from the card: `code` the equipment it was opened from).
func open(p: String, code := "") -> bool:
	if is_open or not has_kind(p) or not can_open():
		return false
	_t0 = Time.get_ticks_usec()
	_gen += 1
	is_open = true
	entry_ms = -1.0
	load_ms = -1.0
	part = p
	from_code = code
	_session = session_on()
	_leave_plant()
	_build_space()
	visible = true
	panels.loading(title_of(p))
	_loading = DIR.path_join(p + ".scn")
	ResourceLoader.load_threaded_request(_loading, "PackedScene", true)
	if main.hud != null:
		main.hud.refresh()
	return true

## Not while the plant can't be left as it stands: a scripted flight ("Go there") would land elsewhere, the tier probe
## would measure an empty frame, the map pans with the sticks.
func can_open() -> bool:
	if main.player != null and main.player.scripted:
		return false
	return not main.probing and not (main.map != null and main.map.active)

## Back to the plant: same place, view, panels and speed (§2).
func close() -> void:
	if not is_open:
		return
	_closed_frame = Engine.get_process_frames()
	var t0 := Time.get_ticks_usec()
	_gen += 1
	var gen := _gen
	is_open = false
	if _loading != "":
		_orphans.append(_loading)   # collected when its thread is done (an unretrieved request keeps the scene)
	_loading = ""
	_drag = {}
	_reassemble_t = -1.0
	_no_click = false
	_press_at = Vector2.INF
	if cam != null:
		cam.release_all()   # a finger down as the Workshop closed lifts nowhere it can be seen
	if machine != null:
		machine.queue_free()
		machine = null
	guide.stop()
	if ghost != null:
		ghost.queue_free()
	ghost = null
	_ghost_id = ""
	comps.clear()
	groups.clear()
	_hollow.clear()
	_tris.clear()
	selected = ""
	if handle != null:
		handle.visible = false
	visible = false
	if container != null:
		container.visible = false
	_back_to_plant()
	if ui != null and "held_link" in ui and ui.held_link != "":
		var url: String = ui.held_link
		ui.held_link = ""
		ui.handle_link(url)   # a link that came while the Workshop showed, now that the plant is seen
	if main.hud != null:
		main.hud.refresh()
	await main._drawn()   # the next frame drawn (headless: the next frame)
	if gen != _gen:
		return   # opened again meanwhile
	exit_ms = (Time.get_ticks_usec() - t0) / 1000.0
	left.emit()

# ------------------------------------------------------------------ the plant meanwhile

func _leave_plant() -> void:
	# a hold-to-run motion is let go first, as when its pendant closes (a session sends the release as an input)
	if ui != null and ui.card != null and ui.card.get("_pendant") != null:
		ui.card._pendant.release_all()
	if ui != null and ui.clock != null and not _session:
		_prev_speed = ui.clock.speed
		ui.clock.set_speed(SimClock.Speed.PAUSED)
	if ui != null and ui.sounds != null:
		_prev_muted = ui.sounds.muted
		bench_view.muted = _prev_muted   # (the bench's own sounds are heard unless the plant's were muted)
		ui.sounds.muted = true
		ui.horn_changed.emit(0)
	if _session and ui.clock != null and ui.clock.engine != null:
		_alarms_at = _unacked_keys()
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_prev_focus = main.get_viewport().gui_get_focus_owner()
	if main.hud != null:
		_prev_hud = main.hud.visible
		main.hud.visible = false
	if ui != null and ui.root != null:
		_prev_ui = ui.root.visible
		ui.root.visible = false
	_prev_3d = main.get_viewport().disable_3d
	main.get_viewport().disable_3d = true

func _back_to_plant() -> void:
	main.get_viewport().disable_3d = _prev_3d
	if ui != null and ui.root != null:
		ui.root.visible = _prev_ui
	if main.hud != null:
		main.hud.visible = _prev_hud
	Input.mouse_mode = _prev_mouse
	if ui != null and ui.sounds != null:
		ui.sounds.muted = _prev_muted
		if "_horn" in ui:
			ui._horn = -1               # the horn sounds again on the next tick if an alarm wants it
			ui._alarms_step = -1        # (and the alarms are looked at again, paused as well)
	# the speed before (1x, fast-forward or paused) comes back; not when a session began meanwhile
	if ui != null and ui.clock != null and not _session and not session_on() and _prev_speed >= 0:
		ui.clock.set_speed(_prev_speed)
	_prev_speed = -1
	if reopen_settings and main.hud != null:
		main.hud.show_settings(true)
	reopen_settings = false
	if is_instance_valid(_prev_focus) and _prev_focus.is_visible_in_tree():
		_prev_focus.grab_focus()
	_prev_focus = null

## The alarms unacknowledged as the horn counts them (ui/plant_ui.gd _horn_tick: not shelved, not suppressed), by
## their key: {key: true}.
func _unacked_keys() -> Dictionary:
	var e = ui.clock.engine
	var out := {}
	if e == null or not "astate" in e:
		return out
	for k in e.astate.size():
		var st := String(e.astate[k])
		if (st == "active_unack" or st == "cleared_unack") and e.shelved[k] == -1 and not AlarmPanel.suppressed(e, k):
			out[k] = true
	return out

## (A session) new alarms since the Workshop opened: those unacknowledged now that weren't then (another player
## acknowledging an old one doesn't hide a new one).
func new_alarms() -> int:
	if not _session or ui == null or ui.clock == null:
		return 0
	var n := 0
	for k in _unacked_keys():
		if not _alarms_at.has(k):
			n += 1
	return n

## The plant's speed as it stands behind the Workshop: the speed it had before in single play (the clock is paused only
## while the Workshop shows), else the clock's. An autosave stores this one.
func plant_speed() -> int:
	if is_open and _prev_speed >= 0:
		return _prev_speed
	return ui.clock.speed if ui != null and ui.clock != null else -1

# ------------------------------------------------------------------ the space

func _build_space() -> void:
	if container != null:
		container.visible = true
		_apply_tier()
		return
	container = SubViewportContainer.new()
	container.name = "workshop_view"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(container)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.handle_input_locally = false
	container.add_child(vp)
	world = Node3D.new()
	world.name = "workshop_world"
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.32, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.84)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-25), deg_to_rad(-140), 0)
	fill.light_energy = 0.35
	world.add_child(fill)
	if ResourceLoader.exists(SPACE):
		var sp: Node3D = (load(SPACE) as PackedScene).instantiate()
		world.add_child(sp)
		_resolve(sp)
		handle = sp.get_node_or_null("handle")
		if handle != null:
			handle.reparent(world)
			handle.visible = false
	cam = Orbit.new()
	world.add_child(cam)
	cam.current = true
	container.gui_input.connect(_on_view_input)
	panels = Panels.new()
	panels.name = "workshop_panels"
	add_child(panels)
	panels.setup(self)
	_apply_tier()

## The plant's tier as it is now (it can change in the settings between two entries).
func _apply_tier() -> void:
	vp.msaa_3d = main.get_viewport().msaa_3d
	vp.scaling_3d_mode = main.get_viewport().scaling_3d_mode
	vp.scaling_3d_scale = main.get_viewport().scaling_3d_scale
	sun.shadow_enabled = main.tier != "lean+vis"   # the phone cuts soft shadows first (§8)

## The plant's materials by name (§5): each mesh's meta `mat`.
func _resolve(n: Node) -> void:
	if n is MeshInstance3D and n.has_meta("mat"):
		n.material_override = _mat(n.get_meta("mat"))
	elif n is MultiMeshInstance3D and n.has_meta("mat"):
		n.material_override = _mat(n.get_meta("mat"))
	for c in n.get_children():
		_resolve(c)

func _mat(name: String) -> Material:
	if not _mats.has(name):
		var path := MATS % name
		_mats[name] = load(path) if ResourceLoader.exists(path) else null
	return _mats[name]

func _process(delta: float) -> void:
	_collect_orphans()
	if not is_open:
		return
	if _loading != "":
		_poll_load()
		return
	if machine == null:
		return
	cam.sticks(delta, _pad_move() if _panel_focused() else Vector2.INF)
	if _reassemble_t >= 0.0:
		_reassemble_t += delta
		var k := clampf(_reassemble_t / REASSEMBLE_S, 0.0, 1.0)
		s = lerpf(_reassemble_from, 0.0, Explode.ease01(k))
		for id in _reassemble_handled:
			handled[id] = (_reassemble_handled[id] as Transform3D).interpolate_with(Transform3D.IDENTITY, Explode.ease01(k))
		if k >= 1.0:
			_reassemble_t = -1.0
			handled.clear()
		if panels != null:
			panels.sync_slider()
	apply()
	_run(delta)
	_place_handle()
	if panels != null:
		panels.tick()

func _collect_orphans() -> void:
	for path in _orphans.duplicate():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(path)
			_orphans.erase(path)

func _poll_load() -> void:
	var st := ResourceLoader.load_threaded_get_status(_loading)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path := _loading
	_loading = ""
	if st != ResourceLoader.THREAD_LOAD_LOADED:
		panels.loading("The Workshop could not load %s." % title_of(part))
		return
	var ps := ResourceLoader.load_threaded_get(path) as PackedScene
	load_ms = (Time.get_ticks_usec() - _t0) / 1000.0
	_show_machine(ps)

func _show_machine(ps: PackedScene) -> void:
	var gen := _gen
	machine = ps.instantiate()
	world.add_child(machine)
	_resolve(machine)
	words = machine.get_meta("workshop", {})
	spec = Explode.spec_of(machine)
	comps.clear()
	groups.clear()
	home.clear()
	handled.clear()
	hidden.clear()
	_hollow.clear()
	_gcentre.clear()
	_collect(machine)
	views.density = 1.0 / 3.0 if main.tier == "lean+vis" else 1.0   # R9a: the phone's flow at a third (§8)
	views.machine_shown(machine, comps)
	run_note = ""
	if String(words.get("bench_text", "")) != "":
		if not bench.load_text(words.bench_text, comps.keys()):
			push_warning("Workshop: the bench model of %s can't run: %s" % [part, bench.error])
	else:
		bench.e = null
	bench_view.setup(machine)
	# the machine's first frame draws the cut faces, the flow particles and the labels unseen, so their pipelines are
	# compiled with the machine's (§7.1)
	views.warm(true)
	views.warm_flows(true)
	bench_view.warm_labels()
	s = 0.0
	only_selected = false
	root_id = ""
	selected = ""
	note = ""
	guide.stop()
	_ghost_id = ""
	ghost = null
	_warm_machine()
	var box: AABB = machine.get_meta("box", AABB(Vector3.ZERO, Vector3.ONE))
	var floor_n := world.get_node_or_null("space/floor")
	if floor_n != null:
		floor_n.position = Vector3(box.get_center().x, box.position.y - 0.001, box.get_center().z)
		floor_n.scale = Vector3.ONE * maxf(box.size.length() * 0.6, 0.15)
	cam.frame(box, false, true)
	cam.set_home()
	panels.machine_shown()
	apply()
	await main._drawn()   # the next frame drawn (headless: the next frame)
	var gw := machine.get_node_or_null("ghost_warm") if machine != null else null
	if gw != null:
		gw.visible = false   # (drawn, unseen, in the first frame: its pipelines are ready for the first ghost)
	views.warm(false)
	views.warm_flows(false)
	if not is_open or gen != _gen:
		return   # left (and maybe entered again) meanwhile
	entry_ms = (Time.get_ticks_usec() - _t0) / 1000.0
	shown.emit(part)

## Components and fastener groups by id; home transforms; fastener items to their MultiMeshes (the headless build
## keeps no MultiMesh data: the items are in a meta).
func _collect(n: Node) -> void:
	for c in n.get_children():
		if c.has_meta("explode"):
			comps[c.get_meta("id")] = c
			home[c.get_meta("id")] = c.transform
		elif c.has_meta("items"):
			groups[c.get_meta("id")] = c
			var items: Array = c.get_meta("items")
			var sum := Vector3.ZERO
			for t in items:
				sum += (t as Transform3D).origin
			_gcentre[c.get_meta("id")] = sum / maxf(items.size(), 1)
			_fill_items(c, [])
		_collect(c)

func _fill_items(g: Node3D, offsets: Array) -> void:
	var items: Array = g.get_meta("items")
	for mmi in g.get_children():
		if mmi is MultiMeshInstance3D:
			var mm: MultiMesh = mmi.multimesh
			if mm.instance_count != items.size():
				mm.instance_count = items.size()
			for i in items.size():
				var t: Transform3D = items[i]
				if i < offsets.size():
					t.origin += offsets[i]
				mm.set_instance_transform(i, t)

# ------------------------------------------------------------------ explode, handling, hide (§3, §4.3, §4.5)

## Every component's transform from home: the explode's offset, then the handling on top; never accumulated.
func apply() -> void:
	if machine == null:
		return
	if guide.on():
		_apply_guided()
		return
	var off := Explode.offsets(spec, s, root_id)
	for id in comps:
		var t: Transform3D = home[id]
		t.origin += off.get(id, Vector3.ZERO)
		if handled.has(id):
			var h: Transform3D = handled[id]
			# turned about the component's own pivot, moved in the parent's frame
			t = Transform3D(h.basis * t.basis, t.origin + h.origin)
		comps[id].transform = t
		comps[id].visible = not hidden.has(id)
	var foff := Explode.fastener_offsets(spec, s, root_id)
	for g in groups:
		var t := Transform3D.IDENTITY
		if handled.has(g):
			# turned about the group's own centre (as a component about its pivot), moved in the host's frame
			var h: Transform3D = handled[g]
			var c: Vector3 = _gcentre.get(g, Vector3.ZERO)
			t = Transform3D(h.basis, h.origin + c - h.basis * c)
		groups[g].transform = t
		groups[g].visible = not hidden.has(g)
		_fill_items(groups[g], foff.get(g, []))
	_cur_m.clear()
	for id in spec.order:
		_cur_m[id] = _parent_m(id, _cur_m) * (comps[id] as Node3D).transform
	for g in groups:
		_cur_m[g] = _parent_m(g, _cur_m) * (groups[g] as Node3D).transform

func set_slider(v: float) -> void:
	if guide.on():
		return   # (the slider waits while the steps are on: Reset or Reassemble all ends them)
	if bench_running() and _takes_apart(clampf(v, 0.0, 1.0), root_id):
		note = RUNNING_WHY   # (back towards assembled is allowed: it opens nothing)
		if panels != null:
			panels.sync_slider()
			panels.selected_changed()
		return
	_reassemble_t = -1.0
	s = clampf(v, 0.0, 1.0)
	apply()

func set_only_selected(on: bool) -> void:
	if bench_running() and _takes_apart(s, selected if on and comps.has(selected) else ""):
		note = RUNNING_WHY
		if panels != null:
			panels.only_cb.set_pressed_no_signal(only_selected)
			panels.selected_changed()
		return
	only_selected = on
	root_id = selected if on and comps.has(selected) else ""
	apply()

## Reassemble all: everything home, animated (the slider to 0, the handling undone).
func reassemble() -> void:
	_drag = {}
	if guide.on():
		_guided_to_handled()
	_reassemble_from = s
	_reassemble_handled = handled.duplicate()
	_reassemble_t = 0.0

## Reset: every part at the transform it was built with, at once; everything shown.
func reset() -> void:
	_reassemble_t = -1.0
	_drag = {}
	_end_guide()
	handled.clear()
	hidden.clear()
	_unhollow()
	s = 0.0
	apply()
	if panels != null:
		panels.sync_slider()
		panels.refresh()

func select(id: String) -> void:
	if selected != "":
		_highlight(selected, false)
	var was := selected
	selected = id if (comps.has(id) or groups.has(id)) else ""
	if selected != was:
		_drag = {}   # a drag held on the part before (a second finger's tap in the tree) doesn't move this one
	if selected != "":
		_highlight(selected, true)
	# with "Selected subassembly only" on, a pick inside the subassembly taken apart looks at it; a pick outside it
	# takes that one apart instead
	if only_selected and not (root_id != "" and comps.has(selected) and (selected == root_id or _under(selected, root_id))):
		var nr := selected if comps.has(selected) else ""
		if not (bench_running() and _takes_apart(s, nr)):   # (running, a pick doesn't take another part apart)
			root_id = nr
	note = why_not_free(selected)   # (the tree's pick says why a part can't be picked up, as the view's does)
	views.selection_changed()
	if panels != null:
		panels.selected_changed()
	apply()

func _highlight(id: String, on: bool) -> void:
	var n: Node = comps.get(id, groups.get(id))
	if n == null:
		return
	views.set_sel(n, on)   # ws_lit's own glow (an instance uniform: no material swapped, no new pipeline)

func hide_selected() -> void:
	if selected != "":
		_drag = {}
		hidden[selected] = true
		apply()

## Isolate: the selected part and its subassembly only (its ancestors' own meshes hidden, their other children too).
func isolate() -> void:
	if selected == "":
		return
	_drag = {}
	hidden.clear()
	_unhollow()
	var keep := {}
	var at: String = selected if comps.has(selected) else spec.groups[selected].host
	if groups.has(selected):
		keep[selected] = true
	keep[at] = true
	for id in comps:
		if _under(id, at):
			keep[id] = true
	for g in groups:
		if keep.has(spec.groups[g].host) and (not groups.has(selected) or g == selected):
			keep[g] = true
	for id in comps:
		if not keep.has(id) and not _ancestor_of(id, at):
			hidden[id] = true
		elif _ancestor_of(id, at):
			_meshes(comps[id], false)
			_hollow[id] = true
	for g in groups:
		if not keep.has(g):
			hidden[g] = true
	apply()

func show_all() -> void:
	_drag = {}
	hidden.clear()
	_unhollow()
	apply()

## The ancestors' own meshes Isolate hid, shown again.
func _unhollow() -> void:
	for id in _hollow:
		if comps.has(id):
			_meshes(comps[id], true)
	_hollow.clear()

func _meshes(n: Node3D, on: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			c.visible = on

func _under(id: String, root: String) -> bool:
	var at: String = spec.comps[id].parent
	while at != "":
		if at == root:
			return true
		at = spec.comps[at].parent
	return false

func _ancestor_of(a: String, id: String) -> bool:
	return comps.has(id) and _under(id, a)

## §4.5: free when no component that needs it is at home (from the assembly's needs); a sealed component's children
## never are. "" when free, else the sentence why not.
func why_not_free(id: String) -> String:
	if id == "" or not (comps.has(id) or groups.has(id)):
		return ""
	if bench_running():
		return RUNNING_WHY
	if comps.has(id) or (groups.has(id) and not spec.groups[id].get("beyond", false)):   # (a sealed part's
		#   bolts to another machine are outside its seal: Assembly.rides_of)
		var at: String = spec.comps[id].parent if comps.has(id) else String(spec.groups[id].host)
		while at != "":
			if spec.comps[at].sealed:
				return String(words.get("components", {}).get(at, {}).get("sealed_why", "It is sealed."))
			at = spec.comps[at].parent
	if guide.on():
		return guide.why_not_remove(id, _riding(id)) if guide.placed(id) else ""
	var off := Explode.offsets(spec, s, root_id)
	var foff := Explode.fastener_offsets(spec, s, root_id)
	for step in words.get("assembly", []):
		for n in step.get("needs", []):
			if n[0] == id and _at_home(String(step.place), off, foff):
				return String(n[2])
	return ""

## In place and not taken apart: a component not moved by the explode, a fastener group whose items haven't backed out.
## (Hidden is a way of looking, not of taking apart: a hidden part still holds what it held.)
func _at_home(id: String, off: Dictionary, foff := {}) -> bool:
	if handled.has(id):
		return false
	var o: Vector3 = off.get(id, Vector3.ZERO)
	if o.length() > 1e-5:
		return false
	for v in foff.get(id, []):
		if (v as Vector3).length() > 1e-5:
			return false
	return true

# ------------------------------------------------------------------ guided assembly and disassembly (§3, §4.6)

## Starts the steps: "assemble" from "exploded" (every part where the slider at 1 puts it) or from "pile" (laid on the
## floor by size, workshop/assembly.gd), or "disassemble" from the machine as built. Handling, hiding and the slider
## are cleared first; the slider waits until Reset or Reassemble all ends the steps.
func start_guide(mode: String, from := "exploded") -> bool:
	if machine == null or words.get("assembly", []).is_empty() or not mode in ["assemble", "disassemble"]:
		return false
	if bench_running():   # (assembling starts from the machine taken apart: that opens it up too)
		note = RUNNING_WHY
		if panels != null:
			panels.selected_changed()
		return false
	_end_guide()
	_reassemble_t = -1.0
	_drag = {}
	handled.clear()
	hidden.clear()
	_unhollow()
	only_selected = false
	root_id = ""
	var at := {}
	if mode == "assemble":
		if from == "pile":
			var parts: Array = []
			var rides := Assembly.rides_of(spec.comps, spec.groups)
			for id in comps.keys() + groups.keys():
				if not rides.has(id):
					parts.append({"id": id, "box": _home_box(id)})
			var off := Assembly.pile(parts, machine.get_meta("box", AABB()))
			for id in off:
				var h := home_m(id)
				at[id] = Transform3D(h.basis, h.origin + off[id])
		else:
			s = 1.0
			apply()
			at = _cur_m.duplicate()
			var foff := Explode.fastener_offsets(spec, 1.0)
			for g in groups:   # a group lies where its items backed out to (their mean: they back out together)
				var sum := Vector3.ZERO
				for v in foff.get(g, []):
					sum += v
				var hm: Transform3D = _cur_m.get(g, home_m(g))
				var mean: Vector3 = sum / maxf(foff.get(g, []).size(), 1)
				var bo := float(spec.groups[g].back_out)
				if mean.length() < bo * 0.5:
					# items backing out every way (radial screws): the group lies out as a whole, beside its host
					var host := String(spec.groups[g].host)
					# (an explode direction is in the host's parent's frame)
					var dir: Vector3 = (_parent_m(host, _cur_m).basis * (spec.comps[host].dir as Vector3)) if host != "" else Vector3.UP
					mean = hm.basis.inverse() * dir.normalized() * maxf(bo, Assembly.snap_tol(machine.get_meta("box", AABB())) * 3.0)
				at[g] = Transform3D(hm.basis, hm.origin + hm.basis * mean)
	if mode == "assemble" and from == "exploded":
		# a part the explode doesn't move (the base everything sits on) stays placed: it is where it goes
		var tol0 := Assembly.snap_tol(machine.get_meta("box", AABB()))
		for id in at.keys():
			var c0: Vector3 = _gcentre.get(id, Vector3.ZERO) if groups.has(id) else Vector3.ZERO
			if Assembly.near_enough(at[id], home_m(id), c0, [], tol0 * 0.05):
				at.erase(id)
	s = 0.0
	guide.start(mode, words.assembly, spec.comps, at, spec.groups)
	if panels != null:
		panels.only_cb.set_pressed_no_signal(false)
	note = ""
	apply()
	_update_ghost()
	if mode == "assemble" and from == "pile":
		var all: AABB = machine.get_meta("box", AABB())
		for id in guide.loose:
			var b := _home_box(id)
			b.position += (guide.loose[id] as Transform3D).origin - home_m(id).origin
			all = all.merge(b)
		cam.frame(machine.global_transform * all)   # the pile in view with the machine
	if panels != null:
		panels.sync_slider()
		panels.refresh()
	return true

## The steps ended (everything stays where it stands as handling until Reset puts it home).
func _end_guide() -> void:
	if not guide.on():
		return
	guide.stop()
	_update_ghost()
	if panels != null:
		panels.refresh()

## The loose parts handed to the handling (relative to their parents), the steps ended: Reassemble all then animates
## them home as it does handled parts.
func _guided_to_handled() -> void:
	apply()
	var cur := _cur_m.duplicate()
	var loose: Dictionary = guide.loose.duplicate()
	_end_guide()
	handled.clear()
	for id in loose:
		var pm := _parent_m(id, cur)
		var local: Transform3D = pm.affine_inverse() * (loose[id] as Transform3D)
		if comps.has(id):
			var h: Transform3D = home[id]
			handled[id] = Transform3D(local.basis * h.basis.inverse(), local.origin - h.origin)
		else:
			var c: Vector3 = _gcentre.get(id, Vector3.ZERO)
			# (a group is turned about its centre: apply() puts h.origin + c - h.basis * c)
			handled[id] = Transform3D(local.basis, local.origin - c + local.basis * c)
	apply()

## The placed parts that come out with `id` (its placed descendants and the groups on them, through placed parts only).
func _riding(id: String) -> Dictionary:
	var out := {}
	if not comps.has(id):
		return out
	var front: Array = [id]
	while not front.is_empty():
		var at: String = front.pop_back()
		for c in spec.order:
			if spec.comps[c].parent == at and guide.placed(c):
				out[c] = true
				front.append(c)
		for g in groups:
			if String(spec.groups[g].host) == at and guide.placed(g):
				out[g] = true
	return out

## A part where it stands now: placed parts at home relative to their parents, loose ones where they lie, in the
## machine's frame (so a loose part stays put when its parent moves).
func _apply_guided() -> void:
	_cur_m.clear()
	for id in spec.order:
		var pm := _parent_m(id, _cur_m)
		var t: Transform3D = home[id]
		if guide.loose.has(id):
			t = pm.affine_inverse() * (guide.loose[id] as Transform3D)
		comps[id].transform = t
		comps[id].visible = not hidden.has(id)
		_cur_m[id] = pm * t
	for g in groups:
		var pm := _parent_m(g, _cur_m)
		var t := Transform3D.IDENTITY
		if guide.loose.has(g):
			t = pm.affine_inverse() * (guide.loose[g] as Transform3D)
		groups[g].transform = t
		groups[g].visible = not hidden.has(g)
		_fill_items(groups[g], [])
		_cur_m[g] = pm * t
	if ghost != null and _ghost_id != "":
		ghost.transform = target_m(_ghost_id)

## The parent's (a group's host's) transform in the machine's frame from `cur` (identity at the machine's root).
func _parent_m(id: String, cur: Dictionary) -> Transform3D:
	var par: String = spec.comps[id].parent if comps.has(id) else String(spec.groups[id].host)
	if par == "":
		return Transform3D.IDENTITY
	return cur.get(par, home_m(par))

## A part's home in the machine's frame (as built).
func home_m(id: String) -> Transform3D:
	if groups.has(id):
		var host := String(spec.groups[id].host)
		return home_m(host) if host != "" else Transform3D.IDENTITY
	var t: Transform3D = home[id]
	var par: String = spec.comps[id].parent
	return home_m(par) * t if par != "" else t

## Where a part goes now, in the machine's frame: home relative to its parent where that stands (a loose parent too).
func target_m(id: String) -> Transform3D:
	var pm := _parent_m(id, _cur_m)
	return pm * (home[id] as Transform3D) if comps.has(id) else pm

## A part's own box at home in the machine's frame (its own meshes: not its children's).
func _home_box(id: String) -> AABB:
	var n: Node3D = comps.get(id, groups.get(id))
	var hm := home_m(id)
	var box := AABB()
	var first := true
	for c in n.get_children():
		var parts: Array = []
		if c is MeshInstance3D and c.mesh != null:
			parts.append(hm * c.transform * c.mesh.get_aabb())
		elif c is MultiMeshInstance3D:
			for t in n.get_meta("items", []):
				parts.append(hm * c.transform * (t as Transform3D) * c.multimesh.mesh.get_aabb())
		for b in parts:
			box = b if first else box.merge(b)
			first = false
	return box if not first else AABB(hm.origin, Vector3.ZERO)

## A drag of the handle in the steps: the loose part moved along, or turned about, an axis of the machine's frame.
func _drag_guided(p: Vector2) -> void:
	var start: Transform3D = _drag.start
	var ax: Vector3 = (machine.global_transform.basis.inverse() * (_drag.axis as Vector3)).normalized()
	var c: Vector3 = _gcentre.get(selected, Vector3.ZERO) if groups.has(selected) else Vector3.ZERO
	if _drag.kind == "move":
		var ab: Vector2 = _drag.b - _drag.a
		var t: float = (p - (_drag.from as Vector2)).dot(ab) / maxf(ab.length_squared(), 1e-6)
		var reach: float = (machine.get_meta("box", AABB(Vector3.ZERO, Vector3.ONE)) as AABB).size.length()
		guide.loose[selected] = Transform3D(start.basis, start.origin + ax * clampf(t * float(_drag.len), -reach, reach))
	else:
		var cc: Vector2 = _drag.centre
		var a0 := ((_drag.from as Vector2) - cc).angle()
		var a1 := (p - cc).angle()
		var toward := (cam.global_position - handle.global_position).dot(_drag.axis) > 0.0
		var b := Basis(ax, (a0 - a1) if toward else (a1 - a0)) * start.basis
		guide.loose[selected] = Transform3D(b, start.origin + start.basis * c - b * c)
	apply()

## A part let go in the steps: near enough its place and turned right, it snaps there, unless a need isn't met (the
## data's first sentence says why, and it stays where it was let go); farther, it lies loose (taken out).
func _released() -> void:
	if not guide.on() or selected == "" or not guide.loose.has(selected):
		return
	try_place(selected)
	_update_ghost()   # (a part taken out while assembling is the next step again)
	if panels != null:
		panels.selected_changed()   # (a refusal that no longer holds goes)
		panels.refresh()

## Places a loose part if it is near enough its place (§4.6); true when it snapped. A refusal goes in `note`.
func try_place(id: String) -> bool:
	if not guide.loose.has(id):
		return false
	var c: Vector3 = _gcentre.get(id, Vector3.ZERO) if groups.has(id) else Vector3.ZERO
	var sym: Array = comps[id].get_meta("sym", []) if comps.has(id) else []
	var tol := Assembly.snap_tol(machine.get_meta("box", AABB()))
	if not Assembly.near_enough(guide.loose[id], target_m(id), c, sym, tol):
		note = ""
		return false
	var why := guide.why_not_place(id)
	if why != "":
		note = why
		if panels != null:
			panels.selected_changed()
		return false
	guide.loose.erase(id)
	note = ""
	apply()
	_update_ghost()
	if panels != null:
		panels.selected_changed()
		panels.refresh()
	return true

## The next step's ghost: its part's own meshes in place, in ws_xray (assembling only).
func _update_ghost() -> void:
	var want := ""
	if guide.mode == "assemble":
		var i := guide.next_step()
		if i >= 0:
			want = String(guide.steps[i].place)
	if want == _ghost_id and (want == "" or ghost != null):
		return
	if ghost != null:
		ghost.queue_free()
		ghost = null
	_ghost_id = want
	if want == "":
		return
	ghost = _ghost_node(want, xray_mat())
	machine.add_child(ghost)
	ghost.transform = target_m(want)

## A part's ghost (its own meshes, plain or instanced as the part draws them) in `mat`, not yet placed.
func _ghost_node(id: String, mat: Material) -> Node3D:
	return _ghost_node_of(comps.get(id, groups.get(id)), mat)

## A component's or fastener group's node's ghost (its own meshes, plain or instanced, its items from its meta).
func _ghost_node_of(src: Node3D, mat: Material) -> Node3D:
	var g := Node3D.new()
	g.name = "ghost"
	for c in src.get_children():
		if c is MeshInstance3D and c.mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = c.mesh
			mi.transform = c.transform
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.add_child(mi)
		elif c is MultiMeshInstance3D:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = c.multimesh.mesh
			var items: Array = src.get_meta("items", [])
			mm.instance_count = items.size()
			for k in items.size():
				mm.set_instance_transform(k, items[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.transform = c.transform
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.add_child(mmi)
	return g

## The ghost's material (ws_xray: unshaded, blended, no depth writes; §7.1).
func xray_mat() -> ShaderMaterial:
	if _xray_mat == null:
		_xray_mat = ShaderMaterial.new()
		_xray_mat.shader = XRAY
	return _xray_mat

## The step's words for the panels: "Step 3 of 16: …" with its why, the end, or "" when the steps are off.
func step_words() -> String:
	if not guide.on():
		return ""
	var i := guide.next_step()
	if i < 0:
		return "Assembled: every part is in place." if guide.mode == "assemble" else "Taken apart: every part is out."
	var st: Dictionary = guide.steps[i]
	var name := _name_of(String(st.place))
	var verb := "Next" if guide.mode == "assemble" else "Take out next"
	var n := guide.real_steps()
	var k := guide.step_number(i)
	var out := "Step %d of %d. %s: %s. " % [k if guide.mode == "assemble" else n - k + 1, n, verb, name]
	if guide.mode == "assemble":
		out += " ".join(st.text)
		if st.has("why"):
			out += " " + " ".join(st.why)
	return out

func _name_of(id: String) -> String:
	var w: Dictionary = words.get("components", {}).get(id, words.get("fasteners", {}).get(id, {}))
	return String(w.get("name", id))

# ------------------------------------------------------------------ running: the bench (§3 "Run it", §6)

## The bench clock advanced by this frame, its values drawn on the machine, its refusals as sentences.
func _run(delta: float) -> void:
	if not bench.loaded():
		return
	bench.tick(delta)
	bench_view.draw(0.0 if bench.paused else delta * bench.speed)
	for ev in bench.new_events():
		if ev.size() >= 6 and ev[1] == "op" and ev[4] == "refused":
			run_note = refusal(ev[2], ev[3], ev[5])

## A refused op's sentence: its permissive's (from the bench file's `needs`), a slider outside its range, a machine
## command its machine's state doesn't take.
func refusal(at: String, do: String, reasons: Array) -> String:
	for o in bench.m.ops_ui:
		if o.at == at and o.do == do:
			for r in reasons:
				for nd in o.get("needs", []):
					if nd[0] == r:
						return String(nd[1])
				if o.get("input", "") == r:
					return "Outside the %s's range." % String(o.get("title", r)).to_lower()
				if o.has("machine") and r == o.machine + "_state":
					return "%s: not from %s." % [String(o.get("title", do)), bench.machine_state(o.machine)]
	return "Refused."

## Taking a running machine apart is refused: taking apart, handling and the guided steps wait until it is stopped and
## at rest, which is its bench machine back in its resting state (the turbine's standstill comes once the rotor is
## below 1 % speed, on its turning gear; the transmitter's once the loop supply is off). A kind whose bench has no
## machine is at rest when no freely turning piece turns faster than AT_REST of its unit. Hiding and isolating are ways
## of looking and stay allowed; so do Reassemble all and Reset, which put parts home.
const RUNNING_WHY := "Stop the machine and let it come to rest before opening it up."
const AT_REST := 0.01

func bench_running() -> bool:
	if bench == null or not bench.loaded():
		return false
	for mc in bench.m.machines:
		if bench.machine_state(String(mc.id)) != String(mc.init):
			return true
	if not bench.m.machines.is_empty():
		return false
	for a in bench_view.anims:
		if a.kind == "rotate" and float(a.travel) == 0.0 and absf(bench.now(a.of)) > AT_REST:
			return true
	return false

## Whether the slider at `new_s` with `new_root` as its root takes apart a part that stands at home now.
func _takes_apart(new_s: float, new_root: String) -> bool:
	var off0 := Explode.offsets(spec, s, root_id)
	var f0 := Explode.fastener_offsets(spec, s, root_id)
	var off1 := Explode.offsets(spec, new_s, new_root)
	var f1 := Explode.fastener_offsets(spec, new_s, new_root)
	for id in comps.keys() + groups.keys():
		if _at_home(id, off0, f0) and not _at_home(id, off1, f1):
			return true
	return false

## Whether every part stands at home (nothing taken apart, handled, hidden or in the steps).
func assembled() -> bool:
	if guide.on() or not handled.is_empty() or not hidden.is_empty():
		return false
	return Explode.offsets(spec, s, root_id).values().all(func(o): return (o as Vector3).length() < 1e-5)

## Why the machine can't run as it stands now ("" when it can): taken apart beyond what the kind's `run_exploded`
## allows (§4.7).
func why_no_run() -> String:
	var r = words.get("views", {}).get("run_exploded", null)
	if r is bool and r:
		return ""
	var out := []
	var off := Explode.offsets(spec, s, root_id)
	for id in comps:
		if not _at_home(id, off) or hidden.has(id):
			out.append(id)
	if out.is_empty():
		return ""
	if r is Dictionary:
		for id in out:
			if not id in r.get("allowed", []):
				return String(r.get("why", ""))
		return ""
	return "Put it together first: it runs assembled."

## A machine command from the Run panel (Start, Stop): Start is refused while the machine stands apart beyond what its
## data allows.
func run_command(at: String, do: String) -> void:
	if _starts(at, do) and why_no_run() != "":
		run_note = why_no_run()
		return
	run_note = ""
	bench.command(at, do)

## Whether a machine command takes its machine out of its first (resting) state: refused while it stands apart.
func _starts(at: String, do: String) -> bool:
	for o in bench.m.ops_ui:
		if o.at == at and o.do == do and o.has("machine"):
			var mc = bench.m.machine_by_id(o.machine)
			return mc != null and mc.commands.get(do, {}).get("to", "") != mc.init
	return false

## Any other op of the bench (an open, a close, a trip's reset) from the Run panel.
func run_op(at: String, do: String, trip = null) -> void:
	run_note = ""
	bench.e.op(at, do, null, trip)

func restart_bench() -> void:
	bench.restart()
	run_note = ""

func toggle_fault(id: String) -> void:
	if bench.faulted.has(id):
		for f in bench.m.faults:
			if f.id == id and not f.repair:
				run_note = "This fault has no repair on the bench: Restart the bench."
				return
		bench.repair(id)
	else:
		bench.fault(id)

func ack_bench_alarms() -> void:
	for a in bench.alarms():
		if a[2] == "active_unack" or a[2] == "cleared_unack":
			bench.ack(a[0])

## The ghost's pipelines (§7.1): a hidden mesh in the plant's vertex format with ws_xray, in the plant's world, some
## seconds after the plant's first walkable frame (app/main.gd calls this then): Godot queues the pipelines of every
## surface in the scene, drawn or not, and compiles them on its worker threads (decision 0060), as the walking
## directions' chevron does. The Compatibility renderer compiles a shader only when it draws it: there it is drawn
## once, fully transparent, in front of the camera.
var _warming := false

func warm_up(parent: Node) -> void:
	if warmed or _warming:
		return
	_warming = true
	await get_tree().create_timer(WARM_UP_S).timeout
	# not while the Workshop shows: its hidden meshes' pipelines are made on the main thread as they enter the plant's
	# world, a hitch in the Workshop's frames (K4a: 167 ms on the Note 9, a trainee in the Workshop 4 s after the start)
	# (nor in the frame that measures the way back to the plant, nor the one after)
	while is_inside_tree() and not may_warm(is_open, Engine.get_process_frames(), _closed_frame):
		if is_open:
			await get_tree().create_timer(0.5).timeout
		else:
			await get_tree().process_frame
	if _warm != null or not is_inside_tree() or not ResourceLoader.exists(SPACE):
		return
	var mesh: Mesh = null
	var sp: Node = (load(SPACE) as PackedScene).instantiate()
	for c in sp.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).mesh != null:
			mesh = (c as MeshInstance3D).mesh
			break
	sp.free()
	if mesh == null:
		return
	_warm = Node3D.new()
	_warm.name = "workshop_warm"
	var pieces: Array = []      # entering the plant's world one a frame (below)
	var wmat := ShaderMaterial.new()   # its own: the Compatibility path below sets its alpha, never the ghost's
	wmat.shader = XRAY
	pieces.append(_xray_pair(mesh, wmat)[0])
	pieces.append(_xray_pair(mesh, wmat)[1])
	# K3's variants (§7.1): ws_lit and ws_cap, plain and instanced, discarding every fragment (a plane that cuts
	# everything: their pipelines, never a pixel), and ws_flow's particles collapsed (density 0)
	for sh in [Views.LIT, Views.CAP]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("ws_plane0", Vector4(0, 0, 0, -1))
		m.set_shader_parameter("ws_cut_on", 1.0)
		for n in _xray_pair(mesh, m):
			pieces.append(n)
	var fm := ShaderMaterial.new()
	fm.shader = Views.FLOW
	fm.set_shader_parameter("density", 0.0)
	var q := QuadMesh.new()
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	fmm.mesh = q
	fmm.instance_count = 1
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fmm
	fmi.material_override = fm
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pieces.append(fmi)
	_warm.position = Vector3(0, -1000, 0)
	_warm.visible = false
	parent.add_child(_warm)
	# one piece a frame: each new shader's surfaces compile in the frame its piece enters the world (on the Note 9 all
	# eight in one frame made a 715 ms plant frame, 4.6 s after the start; K4b's measurement)
	_warm_pending = pieces.duplicate()   # (freed by _exit_tree if the app goes before they are in)
	for n in pieces:
		await _warm_wait()
		if not is_inside_tree() or _warm == null or not is_instance_valid(_warm):
			_free_pending()
			return
		_warm.add_child(n)
		_warm_pending.erase(n)
		warm_up_at.append(Engine.get_process_frames())
		await get_tree().process_frame
	_warm_kinds()   # (on its own: `warmed` is the ghost's warm-up, `kinds_warmed` this one's)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# drawn only when the plant's world is drawn: not while the Workshop (or the screens) has its 3D off, nor
		# without a camera; until then it waits, and `warmed` says so
		while not can_draw_warm(get_viewport().get_camera_3d(), get_viewport().disable_3d, is_open,
				Engine.get_process_frames(), _closed_frame):
			if is_open or Engine.get_process_frames() >= _closed_frame + CLOSE_CUSHION:
				await get_tree().create_timer(1.0).timeout
			else:
				await get_tree().process_frame
			if not is_inside_tree():
				return
		var cam3 := get_viewport().get_camera_3d()
		wmat.set_shader_parameter("alpha", 0.0)
		_warm.global_position = cam3.global_position - cam3.global_transform.basis.z * 2.0
		_warm.visible = true
		for i in 3:
			await RenderingServer.frame_post_draw
		_warm.visible = false
	warmed = true

## Every kind's own machine, hidden under the warm-up, in the Workshop's materials as an entry gives them (ws_lit with
## the cap as its next pass on solid components, the glass in ws_xray) and its parts' ghosts: their surfaces' pipelines
## are queued on the worker threads now, in the plant, rather than in the machine's first frame (the first entry after
## an install compiled 14 of them there on the Note 9: 4.77 s of the 5.0 s rule, K3). The scenes are loaded one at a
## time on a worker thread and freed again once their pipelines are made (the pipeline cache keeps them for later
## starts); a kind the trainee is opening meanwhile is left to its entry.
## None of it in one plant frame (the steam turbine's done at once made a 0.7 s frame on the Note 9, #318): the scene
## is instanced on a worker thread, its materials and ghosts made a slice of WARM_SLICE_US at a time, and its pieces
## enter the plant's world WARM_PER_FRAME a frame.
func _warm_kinds() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		kinds_warmed = true
		return   # (it compiles only what it draws: a hidden machine would be pure cost there)
	for k in kinds():
		var path := DIR.path_join(k + ".scn")
		# not while the tier probe measures, nor while the Workshop shows or has just closed (its entry compiles what
		# it needs)
		await _warm_wait()
		if not is_inside_tree() or ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
			continue
		_warm_loading = path
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		_warm_loading = ""
		var ps := ResourceLoader.load_threaded_get(path) as PackedScene
		if ps == null or _warm == null or not is_instance_valid(_warm):
			continue
		await _warm_wait()   # (a Workshop opened meanwhile: this kind is warmed after it closes, whichever it was)
		if not is_inside_tree():
			return
		# instanced on a worker thread (a scene outside the tree may be made there)
		var made := _warm_made
		made.clear()
		_warm_task = WorkerThreadPool.add_task(_warm_instance.bind(ps, made), false, "workshop warm-up")
		while _warm_task >= 0 and not WorkerThreadPool.is_task_completed(_warm_task):
			await get_tree().process_frame
		if _warm_task < 0:
			return   # (_exit_tree took it)
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1
		ps = null   # (not held while the next kind waits for a Workshop to close)
		if made.is_empty() or made[0] == null:
			continue
		var mc: Node3D = made[0]
		made.clear()
		_warm_mc = mc   # (freed by _exit_tree if the app goes while it is outside the tree)
		await _warm_wait()
		if not is_inside_tree() or _warm == null or not is_instance_valid(_warm):
			mc.free()
			continue
		mc.name = "warm_" + k
		var xr := ShaderMaterial.new()
		xr.shader = XRAY
		var gh := Node3D.new()
		gh.name = "ghosts"
		mc.add_child(gh)
		# the materials and ghosts, a slice at a time (outside the tree: nothing of it is drawn or queued yet)
		var t0 := Time.get_ticks_usec()
		var todo: Array = [[mc, false, false]]
		while not todo.is_empty():
			var it: Array = todo.pop_back()
			var n: Node = it[0]
			if n == gh:
				continue
			if n.has_meta("items"):   # its own MultiMeshes with the items (the scene's resource left as loaded)
				var items: Array = n.get_meta("items")
				for mmi in n.get_children():
					if mmi is MultiMeshInstance3D:
						(mmi as MultiMeshInstance3D).multimesh = _items_multimesh((mmi as MultiMeshInstance3D).multimesh, items)
			if n.has_meta("explode") or n.has_meta("items"):
				gh.add_child(_ghost_node_of(n as Node3D, xr))   # the ghost as a step builds it
			var thin: bool = it[1]
			var glass: bool = it[2]
			if n.has_meta("explode"):
				thin = n.get_meta("thin", false)
				glass = n.get_meta("glass", false)
			_warm_mat_of(n, thin, glass)
			for c in n.get_children():
				todo.append([c, thin, glass])
			t0 = await _warm_slice(t0)
			if is_inside_tree() and _warm_blocked():
				await _warm_wait()   # (no script work of its own in the Workshop's, a close's or the probe's frames)
				t0 = Time.get_ticks_usec()
			if not is_instance_valid(mc):
				break
		if not is_instance_valid(mc) or not is_inside_tree() or _warm == null or not is_instance_valid(_warm):
			if is_instance_valid(mc):
				mc.free()
			continue
		# into the plant's world a few pieces a frame (each queues its surfaces' pipelines as it enters), held
		# flat under one hidden node: where each stands doesn't matter, it is never drawn
		await get_tree().process_frame   # (the last slice's frame is not the first batch's too)
		if not is_instance_valid(mc) or not is_inside_tree() or _warm == null or not is_instance_valid(_warm):
			continue
		var pieces: Array = mc.find_children("*", "GeometryInstance3D", true, false)
		var held := Node3D.new()
		held.name = mc.name
		_warm.add_child(held)
		warm_pieces = maxi(warm_pieces, pieces.size())
		var i := 0
		while i < pieces.size():
			await _warm_wait()
			if not is_instance_valid(held) or not held.is_inside_tree():
				break
			var t1 := Time.get_ticks_usec()
			var added := 0
			while i < pieces.size() and added < WARM_PER_FRAME and (added == 0 or Time.get_ticks_usec() - t1 < warm_slice_us):
				var gi = pieces[i]
				if not is_instance_valid(gi):
					break   # (the scene was freed under it: the app went)
				gi.owner = null   # (the scene's root owns it: moved out from under it, it must not stay its owner)
				gi.get_parent().remove_child(gi)
				held.add_child(gi)
				i += 1
				added += 1
			warm_most_added = maxi(warm_most_added, added)
			warm_batches += 1
			warm_slice_us_max = maxi(warm_slice_us_max, Time.get_ticks_usec() - t1)
			await get_tree().process_frame
		if is_instance_valid(mc):
			mc.free()   # (what is left of it: the pieces' empty parents)
		_warm_mc = null
		if i >= pieces.size():
			_warm_kinds_done.append(k)
		# the pipelines are queued as the instances enter the scene; a few frames later the pieces are let go
		for f in 30:
			await get_tree().process_frame
		if is_instance_valid(held):
			held.queue_free()
	kinds_warmed = true

const WARM_SLICE_US := 4000        # the warm-up's most script time in one frame (the Note 9 runs ~8x slower)
var warm_slice_us := WARM_SLICE_US # (the tests make it small, to see the slicing)
var warm_slices := 0               # the frames the material pass was cut at (tests)
var warm_on_thread := false        # the last kind was instanced on a worker thread (tests)
const WARM_PER_FRAME := 12         # the most pieces that enter the plant's world in one frame
var warm_slice_us_max := 0         # the longest slice the warm-up took in one frame, µs (tests)
var warm_most_added := 0           # the most pieces it added in one frame (tests)
var warm_up_at: Array = []         # the process frame each of the ghost's and K3's warm pieces entered in (tests)
var _warm_pending: Array = []      # those not yet in (an app freed meanwhile frees them)

func _free_pending() -> void:
	for x in _warm_pending:
		if is_instance_valid(x) and (x as Node).get_parent() == null:
			(x as Node).free()
	_warm_pending.clear()
var warm_pieces := 0               # the most pieces one kind had (tests)
var warm_batches := 0              # the frames it added pieces in, all kinds (tests)
var _warm_mc: Node = null          # the kind being made, while outside the tree
var _warm_task := -1               # the worker thread's task instancing a kind (-1: none)
var _warm_made: Array = []         # what that task made, until the warm-up takes it

## The worker thread's part of the warm-up: one kind's scene instanced (outside the tree).
func _warm_instance(ps: PackedScene, made: Array) -> void:
	made.append(ps.instantiate())
	warm_on_thread = OS.get_thread_caller_id() != OS.get_main_thread_id()

## Whether the warm-up must keep out of the plant now: the Workshop shown or just closed, the tier probe measuring.
func _warm_blocked() -> bool:
	return not may_warm(is_open, Engine.get_process_frames(), _closed_frame) or ("probing" in main and main.probing)

## Waits while the warm-up must keep out of the plant (_warm_blocked).
func _warm_wait() -> void:
	while is_inside_tree() and _warm_blocked():
		if is_open or ("probing" in main and main.probing):
			await get_tree().create_timer(1.0).timeout
		else:
			await get_tree().process_frame

## Ends a slice of the warm-up's script work once it has run WARM_SLICE_US: waits for the next frame and returns the
## new slice's start (else the same start).
func _warm_slice(t0: int) -> int:
	var spent := Time.get_ticks_usec() - t0
	warm_slice_us_max = maxi(warm_slice_us_max, spent)
	if spent < warm_slice_us:
		return t0
	warm_slices += 1
	await get_tree().process_frame
	return Time.get_ticks_usec()

## A MultiMesh of the scene's own (`src`, its instances left as loaded) holding the component's items: a new one, not a
## duplicate (a duplicate sets the loaded buffer on its new instance count: "Cannot set a buffer on a Multimesh").
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

var _closed_frame := -100          # the process frame of the last close (the warm-up keeps out of the next ones)
const CLOSE_CUSHION := 3           # the process frames after a close the warm-up keeps out of
var _warm_loading := ""          # the kind the warm-up's threaded load is fetching ("" when none)

## Leaving the tree (the app freed or quitting) collects every threaded load the Workshop still has a request on: the
## warm-up's, an entry's and those a close during loading left. A request never collected keeps its task (and the
## scene) for the rest of the process: the test runner, which frees one app after another in one process, saw a
## later Workshop test find the transmitter's load still there, and an abort at an app's free.
func _exit_tree() -> void:
	if _warm_task >= 0:   # (the warm-up's instancing on a worker thread: waited for, what it made freed)
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1
		for n in _warm_made:
			if is_instance_valid(n):
				n.free()
		_warm_made.clear()
	_free_pending()
	if _warm_mc != null and is_instance_valid(_warm_mc) and not _warm_mc.is_inside_tree():
		_warm_mc.free()   # (made, not yet in the plant's world: nothing else holds it)
	_warm_mc = null
	for path in [_warm_loading, _loading] + _orphans:
		if path != "" and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)   # (waits for the thread when it is still loading)
	_warm_loading = ""
	_orphans.clear()

var _warm_kinds_done: Array = []   # the kinds whose machines the warm-up held (tests)
var kinds_warmed := false          # every kind's machine held (or nothing to hold on this renderer)

## The warm-up's copy of the materials an entry gives a machine (views.gd machine_shown, mat_for, glass_mat), on one
## node: `thin` and `glass` are its component's.
func _warm_mat_of(n: Node, thin: bool, glass: bool) -> void:
	if (n is MeshInstance3D or n is MultiMeshInstance3D) and n.has_meta("mat"):
		var gi := n as GeometryInstance3D
		if glass and not n.get_parent().has_meta("items"):
			gi.material_override = views.glass_mat()
		else:
			var src: Material = _mat(n.get_meta("mat"))
			var m := ShaderMaterial.new()
			m.shader = Views.LIT
			if src is ShaderMaterial:
				for u in (src as ShaderMaterial).shader.get_shader_uniform_list():
					var v = (src as ShaderMaterial).get_shader_parameter(u.name)
					if v != null:
						m.set_shader_parameter(u.name, v)
			if not thin or n.get_parent().has_meta("items"):
				var cap := ShaderMaterial.new()
				cap.shader = Views.CAP
				m.next_pass = cap
			gi.material_override = m

## Whether the warm-up may add to the plant's world now: not while the Workshop shows, nor in the frame that measures
## the way back to the plant or the next ones (CLOSE_CUSHION process frames from the close), on every renderer.
static func may_warm(workshop_open: bool, frame: int, closed_frame: int) -> bool:
	return not workshop_open and frame >= closed_frame + CLOSE_CUSHION

## Whether the Compatibility renderer's warm draw would really be drawn, and may be: a camera, the plant's 3D on, the
## Workshop shut and its close's cushion over (may_warm, as the Mobile renderer's warm-up keeps).
static func can_draw_warm(cam3: Camera3D, disabled_3d: bool, workshop_open: bool, frame: int, closed_frame: int) -> bool:
	return cam3 != null and not disabled_3d and may_warm(workshop_open, frame, closed_frame)


## The Workshop's own load (§7.1): every part's ghost drawn unseen in the machine's first frame, so the ghosts'
## pipelines are compiled with the machine's, before the first step shows one.
func _warm_machine() -> void:
	# every part's own ghost, built as its step will build it, where it will stand (home: the machine as built): the
	# Note 9 compiled a pipeline at a fastener group's first ghost even with a ghost of each vertex format warmed (the
	# pipelines depend on more than the format), so nothing short of the ghosts themselves is warm enough
	var w := Node3D.new()
	w.name = "ghost_warm"
	if _warm_draw_mat == null:
		_warm_draw_mat = ShaderMaterial.new()   # the same shader (so the same pipelines), fully transparent
		_warm_draw_mat.shader = XRAY
		_warm_draw_mat.set_shader_parameter("alpha", 0.0)
	for id in comps.keys() + groups.keys():
		var g := _ghost_node(id, _warm_draw_mat)
		if g.get_child_count() == 0:
			g.free()
			continue
		g.name = id
		g.transform = home_m(id)
		w.add_child(g)
	# drawn in the machine's first frame, unseen (alpha 0, no depth written): a hidden instance was not enough on the
	# Note 9, whose Mobile renderer compiled the ghost's pipelines at its first draw (its lights and the view's state
	# are part of them); the first frame waits for them instead (WORKSHOP.md §7.1: the load draws them first)
	machine.add_child(w)

## A mesh with the X-ray material drawn plain and instanced (a fastener group's ghost is a MultiMesh: its own pipeline
## variant), both hidden-ready: [MeshInstance3D, MultiMeshInstance3D].
func _xray_pair(mesh: Mesh, mat: Material) -> Array:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return [mi, mmi]

# ------------------------------------------------------------------ picking and the handle

func _on_view_input(e: InputEvent) -> void:
	if machine == null:
		return
	var h := container.size.y
	if e is InputEventScreenTouch and e.pressed and e.index > 0:
		_no_click = true   # a pinch or a two-finger pan: no release of it selects anything
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press_at = e.position
			if not _drag.is_empty():
				container.accept_event()   # (touch: the finger's ScreenTouch took the handle first)
				return
			if _grab_handle(e.position):
				_no_click = true
				container.accept_event()
				return
			if e.double_click:
				_frame_at(e.position)
				container.accept_event()
				return
		else:
			if not _drag.is_empty():
				_drag = {}
				_released()
			elif _press_at.distance_to(e.position) < 6.0 and not _no_click:
				select(pick(e.position))
			_press_at = Vector2.INF
			_no_click = false
		container.accept_event()
		return
	if e is InputEventMouseMotion and not _drag.is_empty():
		_drag_handle(e.position)
		container.accept_event()
		return
	if e is InputEventScreenTouch and e.pressed and e.index == 0:
		_no_click = false
		if _grab_handle(e.position):
			_no_click = true
			cam.handle(e, h)   # (the camera keeps count of the fingers down)
			container.accept_event()
			return
		if e.double_tap:
			_frame_at(e.position)
	if e is InputEventScreenTouch and not e.pressed and e.index == 0:
		if not _drag.is_empty():
			_drag = {}
			_released()
	if e is InputEventScreenDrag and not _drag.is_empty():
		if e.index == 0:
			_drag_handle(e.position)
		container.accept_event()   # another finger doesn't orbit while one holds the handle
		return
	if cam.handle(e, h):
		container.accept_event()

func _frame_at(p: Vector2) -> void:
	var hit := pick(p)
	if hit != "":
		select(hit)
		cam.frame(world_box(hit))
	else:
		cam.frame(machine.get_meta("box"))

## The component (or fastener group) under a point of the view, nearest first; "" when none.
func pick(p: Vector2) -> String:
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	var best := INF
	var best_id := ""
	for id in comps:
		var n: Node3D = comps[id]
		if not n.is_visible_in_tree():
			continue
		for c in n.get_children():
			if c is MeshInstance3D and c.visible and c.mesh != null:
				var d := _ray_mesh(c.global_transform, c.mesh, from, dir)
				if d < best:
					best = d
					best_id = id
	for g in groups:
		var n: Node3D = groups[g]
		if not n.is_visible_in_tree():
			continue
		for c in n.get_children():
			if c is MultiMeshInstance3D:
				var mm: MultiMesh = c.multimesh
				for i in mm.instance_count:
					var d := _ray_mesh(c.global_transform * mm.get_instance_transform(i), mm.mesh, from, dir)
					if d < best:
						best = d
						best_id = g
	return best_id

func _ray_mesh(xf: Transform3D, mesh: Mesh, from: Vector3, dir: Vector3) -> float:
	var inv := xf.affine_inverse()
	var lf := inv * from
	var ld := (inv.basis * dir).normalized()
	if mesh.get_aabb().grow(0.001).intersects_ray(lf, ld) == null:
		return INF
	if not _tris.has(mesh):
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var out := PackedVector3Array()
		for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
			out.append(v[i])
		_tris[mesh] = out
	var t: PackedVector3Array = _tris[mesh]
	var best := INF
	for k in range(0, t.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(lf, ld, t[k], t[k + 1], t[k + 2])
		if hit != null:
			var d := (xf * (hit as Vector3)).distance_to(from)
			best = minf(best, d)
	return best

## A part's box in the Workshop's world (its meshes where they stand now).
func world_box(id: String) -> AABB:
	var n: Node3D = comps.get(id, groups.get(id))
	var box := AABB()
	var first := true
	if n == null:
		return machine.get_meta("box")
	for c in n.get_children():
		if c is MeshInstance3D and c.mesh != null:
			var b: AABB = c.global_transform * c.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		elif c is MultiMeshInstance3D:
			var mm: MultiMesh = c.multimesh
			for i in mm.instance_count:
				var b: AABB = c.global_transform * mm.get_instance_transform(i) * mm.mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
	return box if not first else AABB(n.global_position, Vector3.ZERO)

func _place_handle() -> void:
	if handle == null:
		return
	var on := selected != "" and why_not_free(selected) == "" and shown_part(selected) and _reassemble_t < 0.0
	handle.visible = on
	if not on:
		return
	handle.global_position = turn_centre(selected)
	handle.scale = Vector3.ONE * (cam.global_position.distance_to(handle.global_position) * 0.18)

## Whether a part is shown: neither it nor a component it sits in is hidden.
func shown_part(id: String) -> bool:
	if hidden.has(id):
		return false
	var at: String = spec.comps[id].parent if comps.has(id) else String(spec.groups.get(id, {}).get("host", ""))
	while at != "":
		if hidden.has(at):
			return false
		at = spec.comps[at].parent
	return true

## Where the handle stands and the part turns about, in the Workshop's world: a component's pivot (its node's
## origin), a fastener group's items' centre.
func turn_centre(id: String) -> Vector3:
	if comps.has(id):
		return (comps[id] as Node3D).global_position
	if groups.has(id):
		var g: Node3D = groups[id]
		var c: Vector3 = _gcentre.get(id, Vector3.ZERO)
		return g.global_transform * c   # (its turn keeps this point where the handling moved it)
	return Vector3.ZERO

## Takes an arrow or a ring of the handle under the pointer. True when one was taken.
func _grab_handle(p: Vector2) -> bool:
	if handle == null or not handle.visible or _reassemble_t >= 0.0:
		return false
	if cam.is_position_behind(handle.global_position):
		return false
	var c := handle.global_position
	var sc := handle.scale.x
	var cs := cam.unproject_position(c)
	var best := HANDLE_PX
	var got := {}
	for k in ["x", "y", "z"]:
		var arrow := handle.get_node_or_null("arrow_" + k)
		if arrow == null:
			continue
		var ax: Vector3 = arrow.get_meta("axis")
		if cam.is_position_behind(c + ax * sc * 0.1) or cam.is_position_behind(c + ax * sc * 1.0):
			continue   # (a point behind the camera projects mirrored)
		var a := cam.unproject_position(c + ax * sc * 0.1)
		var b := cam.unproject_position(c + ax * sc * 1.0)
		var d := _seg_dist(p, a, b)
		if d < best and a.distance_to(b) >= ARROW_MIN_PX:
			best = d
			got = {"kind": "move", "axis": ax, "a": a, "b": b, "len": sc * 0.9, "from": p}
		var ring_d := INF
		var u: Vector3 = ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var w: Vector3 = ax.cross(u).normalized()
		for i in 48:
			var ang := TAU * i / 48.0
			var rp := c + (u * cos(ang) + w * sin(ang)) * sc * 0.62
			if not cam.is_position_behind(rp):
				ring_d = minf(ring_d, cam.unproject_position(rp).distance_to(p))
		if ring_d < best:
			best = ring_d
			got = {"kind": "turn", "axis": ax, "centre": cs, "from": p}
	if got.is_empty():
		return false
	if guide.on():
		if guide.placed(selected):
			guide.loose[selected] = _cur_m.get(selected, Transform3D.IDENTITY)   # taken out: it lies loose from now
		got["start"] = guide.loose[selected]
	else:
		got["start"] = handled.get(selected, Transform3D.IDENTITY)
	_drag = got
	return true

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _drag_handle(p: Vector2) -> void:
	if selected == "" or _drag.is_empty():
		return
	if bench_running():   # (started while a part was held: let go of it where it is)
		_drag = {}
		note = RUNNING_WHY
		return
	if guide.on():
		_drag_guided(p)
		return
	var start: Transform3D = _drag.start
	var ax: Vector3 = _drag.axis
	# the axis in the frame of the part's parent node (handling moves and turns it there)
	var n: Node3D = comps.get(selected, groups.get(selected))
	var lax := ((n.get_parent() as Node3D).global_transform.basis.inverse() * ax).normalized()
	if _drag.kind == "move":
		var ab: Vector2 = _drag.b - _drag.a
		var t: float = (p - (_drag.from as Vector2)).dot(ab) / maxf(ab.length_squared(), 1e-6)
		# never farther than the machine's size from where the drag began
		var reach: float = (machine.get_meta("box", AABB(Vector3.ZERO, Vector3.ONE)) as AABB).size.length()
		var dist := clampf(t * float(_drag.len), -reach, reach)
		handled[selected] = Transform3D(start.basis, start.origin + lax * dist)
	else:
		var c: Vector2 = _drag.centre
		var a0 := ((_drag.from as Vector2) - c).angle()
		var a1 := (p - c).angle()
		var toward := (cam.global_position - handle.global_position).dot(ax) > 0.0
		var ang := (a0 - a1) if toward else (a1 - a0)
		handled[selected] = Transform3D(Basis(lax, ang) * start.basis, start.origin)
	apply()

# ------------------------------------------------------------------ keys

## The gamepad (Godot's ui_accept and ui_cancel have no gamepad button; app/hud.gd does the same for the settings):
## the first button or D-pad press puts the focus on the slider when no Workshop control has it, so the D-pad moves
## between the tools; A presses (or toggles) the focused one; B leaves, as Esc does.
func _input(e: InputEvent) -> void:
	if is_open and machine != null and e is InputEventJoypadMotion and e.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		get_viewport().set_input_as_handled()   # the left stick zooms and pans; only the D-pad walks between the tools
		return
	if not is_open or not e is InputEventJoypadButton or panels == null:
		return
	var fo := get_viewport().gui_get_focus_owner()
	var ours: bool = fo != null and panels.is_ancestor_of(fo) and fo.is_visible_in_tree()
	if e.button_index == JOY_BUTTON_B:
		get_viewport().set_input_as_handled()
		if e.pressed:
			close()
		return
	if not ours:
		if e.pressed and panels.slider.is_visible_in_tree():
			panels.slider.grab_focus()
			get_viewport().set_input_as_handled()
		return
	if e.button_index == JOY_BUTTON_A:
		get_viewport().set_input_as_handled()
		var a := InputEventAction.new()
		a.action = "ui_accept"
		a.pressed = e.pressed
		get_viewport().push_input(a)

## The left stick alone (forward up), any pad: the move actions without the keys.
func _pad_move() -> Vector2:
	var best := Vector2.ZERO
	for d in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), -Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if v.length() > best.length():
			best = v
	return best if best.length() >= 0.15 else Vector2.ZERO

## Whether one of the Workshop's controls has the focus: the move stick and the arrow keys walk between the controls
## then, and only the look stick turns the camera.
func _panel_focused() -> bool:
	if panels == null:
		return false
	var fo := get_viewport().gui_get_focus_owner()
	return fo != null and panels.is_ancestor_of(fo) and fo.is_visible_in_tree()

func _unhandled_input(e: InputEvent) -> void:
	if not is_open:
		return
	if e.is_action_pressed("menu") or e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	# every other key and button stays here while the Workshop shows (the plant's keys wait)
	if e is InputEventKey or e is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
