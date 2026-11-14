## The thermal camera's false-colour picture (docs/plant3d/REALISM.md §9.3, §2.19; milestones AG3 and K6): the pump's
## Workshop tree (its motor's inside it, built/workshop/<kind>.scn) drawn on the camera's screen with the Workshop's
## heat view (ws_lit's `ws_ramp`: no new shader), each component at the temperature of the model value the monitoring
## file names for it (the monitored bearing's housing, the frame and the sound bearings, what the water wets, the air),
## on an iron palette over the range the picture holds, with the spot's cross, the hottest component and the scale.
## What a camera sees from the floor: the components below the plant's floor (a vertical pump's string in its pit) are
## not drawn. Drawn once each time a temperature changes by more than STEP_K (a SubViewport rendered on demand).
extends VBoxContainer

const W = preload("res://ui/widgets.gd")
const LIT := preload("res://workshop/ws_lit.gdshader")
const DIR := "res://built/workshop"
const STEP_K := 0.1             # a change smaller than this is not drawn again
const SIZE := Vector2i(384, 240)
## The iron palette (black, violet, magenta, orange, yellow, white), cold to hot.
const IRON := [[0.0, Color("#000004")], [0.2, Color("#3b0f70")], [0.4, Color("#8c2981")], [0.6, Color("#de4968")],
	[0.8, Color("#fe9f6d")], [0.95, Color("#fcfdbf")], [1.0, Color("#ffffff")]]

var pic := {}                   # the point's picture: {kind, spot, parts: {component: value}}
var vp: SubViewport
var cam: Camera3D
var machine: Node3D
var tex: TextureRect
var overlay: Control
var scale_label: Label
var max_label: Label
var comps := {}                 # component id -> [GeometryInstance3D] drawn
var shown := {}                 # component id -> the temperature drawn (°C)
var lo := 0.0                   # the scale's range now
var hi := 1.0
var renders := 0                # pictures drawn (tests)
var _loading := ""
var _mat: ShaderMaterial


func setup(p: Dictionary) -> void:
	pic = p
	name = "thermal_picture"
	var box := SubViewportContainer.new()
	box.stretch = false
	box.visible = false         # (the texture below shows it, scaled to the panel)
	add_child(box)
	vp = SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	box.add_child(vp)
	var env := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color("#000004")
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color.WHITE
	en.ambient_light_energy = 0.9
	en.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = en
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	tex = TextureRect.new()
	tex.name = "picture"
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(0, 230 * W.scale)
	add_child(tex)
	overlay = Spot.new()
	overlay.pic = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.add_child(overlay)
	var bar := Scale.new()
	bar.pic = self
	bar.name = "scale_bar"
	bar.custom_minimum_size = Vector2(0, 12 * W.scale)
	add_child(bar)
	scale_label = W.label("", 15, W.DIM)
	scale_label.name = "scale"
	add_child(scale_label)
	max_label = W.label("", 16, Color.WHITE)
	max_label.name = "hottest"
	add_child(max_label)
	_loading = DIR.path_join(String(p["kind"]) + ".scn")
	if ResourceLoader.exists(_loading):
		ResourceLoader.load_threaded_request(_loading, "PackedScene", true)
	else:
		_loading = ""
		max_label.text = "No picture: the %s has no Workshop scene." % String(p["kind"]).replace("_", " ")


func _exit_tree() -> void:
	if _loading != "":
		ResourceLoader.load_threaded_get(_loading)   # (a request left behind keeps its scene)
		_loading = ""


## Each look (the monitoring view's, 4 a second): the scene once loaded, then the components' temperatures.
func update(e) -> void:
	if _loading != "":
		if ResourceLoader.load_threaded_get_status(_loading) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		var ps := ResourceLoader.load_threaded_get(_loading) as PackedScene
		_loading = ""
		if ps != null:
			_show(ps.instantiate())
	if machine == null or e == null:
		return
	var t := temps(e, pic)
	var changed := false
	for c in t:
		if not shown.has(c) or absf(float(shown[c]) - float(t[c])) > STEP_K:
			changed = true
			break
	if not changed:
		return
	shown = t
	var r := range_of(t, comps.keys())
	lo = r[0]
	hi = r[1]
	for c in comps:
		var col: Color = iron((float(t.get(c, lo)) - lo) / maxf(hi - lo, 1e-6)).srgb_to_linear()
		for g in comps[c]:
			g.set_instance_shader_parameter("ws_ramp", Color(col.r, col.g, col.b, 1.0))
	var hot := hottest(t, comps.keys())
	scale_label.text = "%.0f °C  …  %.0f °C" % [lo, hi]
	max_label.text = "Hottest: %s, %.1f °C" % [_words(hot), float(t.get(hot, 0.0))]
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1
	overlay.queue_redraw()
	get_node("scale_bar").queue_redraw()


func _show(n: Node3D) -> void:
	machine = n
	vp.add_child(machine)
	var gw := machine.get_node_or_null("ghost_warm")
	if gw != null:
		gw.visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = LIT
	comps.clear()
	var box := AABB()
	var first := true
	for c in _components(machine):
		var id := String(c.get_meta("id"))
		var own := []
		for g in c.get_children():
			if g is GeometryInstance3D and g.has_meta("mat"):
				own.append(g)
		var b := _box_of(c, own)
		if b.size == Vector3.ZERO or b.end.y < 0.0:
			c.visible = false               # (below the floor: the camera can't see it)
			continue
		for g in own:
			g.material_override = _mat
		comps[id] = own
		box = b if first else box.merge(b)
		first = false
	_frame(box)


static func _components(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c.has_meta("explode"):
			out.append(c)
		out.append_array(_components(c))
	return out


func _box_of(c: Node3D, own: Array) -> AABB:
	var b := AABB()
	var first := true
	for g in own:
		if g is MeshInstance3D and g.mesh != null:
			var a: AABB = (machine.global_transform.affine_inverse() * g.global_transform) * g.mesh.get_aabb()
			b = a if first else b.merge(a)
			first = false
	return b


## A three-quarter view from above, the whole of what is drawn in the frame.
func _frame(box: AABB) -> void:
	var c := box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.1)
	var d := Vector3(0.85, 0.6, 1.0).normalized()
	cam.position = c + d * (r / sin(deg_to_rad(cam.fov * 0.5)) * 1.05)
	cam.look_at(c, Vector3.UP)
	cam.near = maxf(r * 0.05, 0.01)
	cam.far = r * 8.0


func _words(c: String) -> String:
	return c.replace("_", " ")


# ------------------------------------------------------------------ what is drawn (pure: the tests call these)

## Each component's temperature (°C) from the model's values as they stand.
static func temps(e, p: Dictionary) -> Dictionary:
	var out := {}
	var parts: Dictionary = p["parts"]
	for c in parts:
		var i: int = e.ix.get(String(parts[c]), -1)
		if i >= 0:
			out[c] = e.cur[i]
	return out


## The scale's range over the components drawn: from the coolest to the hottest, at least 10 K wide, in whole degrees.
static func range_of(t: Dictionary, drawn: Array) -> Array:
	var a := INF
	var b := -INF
	for c in drawn:
		if t.has(c):
			a = minf(a, float(t[c]))
			b = maxf(b, float(t[c]))
	if a == INF:
		return [0.0, 10.0]
	a = floorf(a) - 1.0
	b = maxf(ceilf(b) + 1.0, a + 10.0)
	return [a, b]


## The hottest component drawn (the first of equals in the tree's order).
static func hottest(t: Dictionary, drawn: Array) -> String:
	var best := ""
	for c in drawn:
		if t.has(c) and (best == "" or float(t[c]) > float(t[best])):
			best = c
	return best


## The iron palette at x (0 cold, 1 hot), held at its ends.
static func iron(x: float) -> Color:
	x = clampf(x, 0.0, 1.0)
	for i in range(1, IRON.size()):
		if x <= float(IRON[i][0]):
			var f := (x - float(IRON[i - 1][0])) / (float(IRON[i][0]) - float(IRON[i - 1][0]))
			return (IRON[i - 1][1] as Color).lerp(IRON[i][1], f)
	return IRON[-1][1]


## The spot's cross where the camera's spot is aimed (the picture's own spot component).
class Spot extends Control:
	var pic
	func _draw() -> void:
		if pic == null or pic.machine == null or not pic.comps.has(String(pic.pic["spot"])):
			return
		var gs: Array = pic.comps[String(pic.pic["spot"])]
		if gs.is_empty() or not gs[0] is MeshInstance3D:
			return
		var g: MeshInstance3D = gs[0]
		var w: Vector3 = g.global_transform * g.mesh.get_aabb().get_center()
		if pic.cam.is_position_behind(w):
			return
		var q: Vector2 = pic.cam.unproject_position(w)
		# the texture is kept to its aspect, centred in the rect
		var k := minf(size.x / float(SIZE.x), size.y / float(SIZE.y))
		var o := (size - Vector2(SIZE) * k) * 0.5
		var at := o + q * k
		var r := 10.0 * W.scale
		draw_arc(at, r, 0, TAU, 24, Color.WHITE, 2.0)
		draw_line(at - Vector2(r * 1.6, 0), at - Vector2(r * 0.5, 0), Color.WHITE, 2.0)
		draw_line(at + Vector2(r * 0.5, 0), at + Vector2(r * 1.6, 0), Color.WHITE, 2.0)
		draw_line(at - Vector2(0, r * 1.6), at - Vector2(0, r * 0.5), Color.WHITE, 2.0)
		draw_line(at + Vector2(0, r * 0.5), at + Vector2(0, r * 1.6), Color.WHITE, 2.0)


## The palette's bar under the picture (the numbers are the label below it).
class Scale extends Control:
	var pic
	func _draw() -> void:
		var n := 48
		for i in n:
			draw_rect(Rect2(size.x * float(i) / n, 0, size.x / n + 1.0, size.y), pic.iron(float(i) / (n - 1)))
