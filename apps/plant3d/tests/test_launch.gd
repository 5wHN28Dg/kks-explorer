## The start's cost on a phone (decision 0060): a phone's first start waits for the pipelines Godot compiles, which the
## Note 9's Mali compiles one after another, about 0.7 to 0.9 s each for a lit surface. So:
## - every lit surface of the built plant is the weathered shader (kit/materials.gd), the lamps too (their light is
##   the shader's emission), in the plant's vertex format (positions, normals, tangents, colours, UV, and UV2 for what
##   is baked): no Godot standard material and no primitive mesh, each of which is pipelines of its own;
## - the UI's markers and lamps on the parts (ui/bindings.gd) are the same shader and format;
## - the app's start draws the sky alone, then the plant loaded but hidden (its pipelines start compiling), makes the
##   map, the HUD and the UI meanwhile, and only then draws the plant: its first walkable frame.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const SHADER := "res://kit/weathered.gdshader"
const FORMAT := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV
const ATTRS := FORMAT | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3

func run(tree: SceneTree) -> Array:
	var p: Array = []
	# the built materials: all the weathered shader, the lamps lit
	var lamps := 0
	for f in DirAccess.get_files_at("res://built/materials"):
		if not f.ends_with(".tres"):
			continue
		var m := load("res://built/materials/" + f) as Material
		if not (m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path == SHADER):
			p.append("built/materials/%s is the weathered shader (%s)" % [f, m.get_class() if m else "null"])
			continue
		if f.begins_with("lamp_") and f != "lamp_off.tres":
			lamps += 1
			if _f(m.get_shader_parameter("emission_energy")) <= 0.0 or not (m.get_shader_parameter("emission") is Color) or m.get_shader_parameter("emission").v <= 0.0:
				p.append("%s gives its light" % f)
	if lamps < 5:
		p.append("the lit lamps' materials are there (%d)" % lamps)
	# every lit surface in the plant
	var plant: Node3D = Plant.new()
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return p + ["the built plant loads: " + err]
	p += lit_surfaces(plant, "the plant")
	plant.free()
	# the app: its start, and the UI's markers and lamps
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts = {"staged_start": "1"}   # the start a display gets (without one, the tests start in one go)
	var seen := {"hidden_frames": 0, "frames": 0}
	var watch := func():
		if main.plant != null and main.first_frame_ms < 0:
			seen.frames += 1
			if not main.plant.visible and main.plant.get_child_count() > 1:
				seen.hidden_frames += 1
	tree.process_frame.connect(watch)
	tree.root.add_child(main)
	for i in 30:
		await tree.process_frame
		if main.first_frame_ms >= 0:
			break
	tree.process_frame.disconnect(watch)
	if main.first_frame_ms < 0:
		main.free()
		return p + ["the app drew its first frame"]
	var order := ["LAUNCH tier", "LAUNCH sky frame", "LAUNCH plant at", "LAUNCH plant's pipelines queued", "LAUNCH player, map, hud", "LAUNCH ui", "first frame drawn"]
	var at := -1
	for o in order:
		var i := -1
		for k in main.lines.size():
			if main.lines[k].begins_with(o):
				i = k
				break
		if i <= at:
			p.append("the start's stages in order: %s comes after %s (%s)" % [o, order[order.find(o) - 1] if order.find(o) > 0 else "the start", " | ".join(main.lines)])
			break
		at = i
	if seen.hidden_frames < 1:
		p.append("a frame is drawn with the plant loaded and hidden before the first walkable one (%d frames)" % seen.frames)
	if not main.plant.visible or main.hud == null or main.ui == null:
		p.append("the first frame has the plant, the HUD and the UI")
	var b = main.ui.bindings
	if b != null:
		var lit: ShaderMaterial = b._mat("running", true)
		var dark: ShaderMaterial = b._mat("running", false)
		for m in [lit, dark]:
			if m == null or m.shader.resource_path != SHADER:
				p.append("the UI's lamps and markers are the weathered shader")
		if lit != null and _f(lit.get_shader_parameter("emission_energy")) <= 0.0:
			p.append("a lit lamp gives its light")
		if dark != null and _f(dark.get_shader_parameter("emission_energy")) > 0.0:
			p.append("an unlit lamp gives none")
		var n3 := Node3D.new()
		main.add_child(n3)
		var box := AABB(Vector3.ZERO, Vector3.ONE)
		for ch in ["shaft", "stem", "disc", "level", "other"]:
			b._piece(n3, ch, box)
		var lamp: MeshInstance3D = b._lamp(n3, "running", box)
		lamp.material_override = lit   # as the bindings set it from the engine's state
		p += lit_surfaces(n3, "the UI's markers")
		var made := 0
		for c in n3.get_children():
			if c is MeshInstance3D:
				made += 1
		if made < 6:
			p.append("the markers and the lamp were made (%d)" % made)
	else:
		p.append("the UI has its bindings")
	main.free()
	return p

## A shader parameter as a number (one never set reads as null: the shader's default, 0 here).
static func _f(v) -> float:
	return float(v) if v != null else 0.0

## Problems with the lit surfaces under `root`: each the weathered shader, in the plant's vertex format.
static func lit_surfaces(root: Node, what: String) -> Array:
	var p: Array = []
	var n_ok := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = n.mesh
		elif n is MultiMeshInstance3D and n.multimesh != null:
			mesh = n.multimesh.mesh
		if mesh == null:
			continue
		var gi := n as GeometryInstance3D
		for s in mesh.get_surface_count():
			var mat: Material = gi.material_override
			if mat == null and n is MeshInstance3D:
				mat = n.get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var bm := mat as BaseMaterial3D
			if bm != null and bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue   # unshaded: small pipelines (the map's marker, the pointer)
			if not (mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path == SHADER):
				p.append("%s: %s is the weathered shader (%s)" % [what, root.get_path_to(n), mat.get_class() if mat else "no material"])
				continue
			if not (mesh is ArrayMesh):
				p.append("%s: %s is an ArrayMesh in the plant's format, not a %s" % [what, root.get_path_to(n), mesh.get_class()])
				continue
			var f: int = mesh.surface_get_format(s) & ATTRS
			if f != FORMAT and f != FORMAT | Mesh.ARRAY_FORMAT_TEX_UV2:
				p.append("%s: %s has the plant's vertex format (%x, not %x)" % [what, root.get_path_to(n), f, FORMAT])
			else:
				n_ok += 1
	if n_ok == 0:
		p.append("%s: lit surfaces were checked" % what)
	return p
