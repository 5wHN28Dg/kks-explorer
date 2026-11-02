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
var _lit := {}                  # name -> Material with the selection's emission
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

func setup(m) -> void:
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

## The same material with the selection's emission (the lit material's own uniform: no new shader, §3).
func _lit_mat(name: String) -> Material:
	if not _lit.has(name):
		var m := _mat(name)
		if m is ShaderMaterial:
			var d: ShaderMaterial = m.duplicate()
			d.set_shader_parameter("emission", Color(1.0, 0.62, 0.15))
			d.set_shader_parameter("emission_energy", 0.45)
			_lit[name] = d
		else:
			_lit[name] = m
	return _lit[name]

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
	s = 0.0
	only_selected = false
	root_id = ""
	selected = ""
	note = ""
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

func set_slider(v: float) -> void:
	_reassemble_t = -1.0
	s = clampf(v, 0.0, 1.0)
	apply()

func set_only_selected(on: bool) -> void:
	only_selected = on
	root_id = selected if on and comps.has(selected) else ""
	apply()

## Reassemble all: everything home, animated (the slider to 0, the handling undone).
func reassemble() -> void:
	_drag = {}
	_reassemble_from = s
	_reassemble_handled = handled.duplicate()
	_reassemble_t = 0.0

## Reset: every part at the transform it was built with, at once; everything shown.
func reset() -> void:
	_reassemble_t = -1.0
	_drag = {}
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
		root_id = selected if comps.has(selected) else ""
	note = why_not_free(selected)   # (the tree's pick says why a part can't be picked up, as the view's does)
	if panels != null:
		panels.selected_changed()
	apply()

func _highlight(id: String, on: bool) -> void:
	var n: Node = comps.get(id, groups.get(id))
	if n == null:
		return
	for c in n.get_children():
		if (c is MeshInstance3D or c is MultiMeshInstance3D) and c.has_meta("mat"):
			c.material_override = _lit_mat(c.get_meta("mat")) if on else _mat(c.get_meta("mat"))

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
	if comps.has(id) or groups.has(id):
		var at: String = spec.comps[id].parent if comps.has(id) else String(spec.groups[id].host)
		while at != "":
			if spec.comps[at].sealed:
				return String(words.get("components", {}).get(at, {}).get("sealed_why", "It is sealed."))
			at = spec.comps[at].parent
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
