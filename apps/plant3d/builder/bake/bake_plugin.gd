## Bakes the plant's lightmap (R9; builder/lightmap.gd, app/lighting.gd). Godot bakes LightmapGI only in its editor
## (no script API: LightmapGI::bake is not bound) and only on a GPU, so build.sh `bake` starts the editor on a
## private display (tools/plant3d/bench/offscreen.sh) with `-- --bake-lightmaps`; this plugin then opens the bake
## scene the content build made (built/lit.scn), gives its LightmapGI a fresh data file at app/lighting.gd LIGHTMAP,
## presses the editor's own "Bake Lightmaps", checks the result and quits: exit 0 when the data holds lightmap
## textures and users, 1 otherwise. Without the argument it does nothing (opening the project in the editor).
@tool
extends EditorPlugin

const Lighting = preload("res://app/lighting.gd")
const SCENE := "res://built/lit.scn"

func _enter_tree() -> void:
	if "--bake-lightmaps" in OS.get_cmdline_user_args():
		_bake.call_deferred()

func _say(s: String) -> void:
	print("bake: ", s)

func _fail(s: String) -> void:
	printerr("bake: ERROR ", s)
	get_tree().quit(1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _bake() -> void:
	await _frames(30)   # the editor's first scan and imports
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning():
		await _frames(5)
	if not ResourceLoader.exists(SCENE):
		_fail("no %s: run the content build first" % SCENE)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Lighting.LIGHTMAP.get_base_dir()))
	# the lightmap's import settings, before the bake writes and imports its image (the bake keeps a mode it finds):
	# HDR kept uncompressed as RGBE9995, 4 bytes a texel on every GPU. The Note 9's Mali-G72 has no ASTC HDR: Godot
	# turned the ASTC lightmap into RGBA half floats at load (8 bytes a texel, measured 2026-10-16)
	var imp := FileAccess.open(ProjectSettings.globalize_path(Lighting.LIGHTMAP.get_basename() + ".exr.import"), FileAccess.WRITE)
	imp.store_string("[remap]\n\nimporter=\"2d_array_texture\"\ntype=\"CompressedTexture2DArray\"\n\n[params]\n\ncompress/mode=2\ncompress/hdr_compression=0\n")
	imp.close()
	var data := LightmapGIData.new()
	if ResourceSaver.save(data, Lighting.LIGHTMAP) != OK:
		_fail("cannot write " + Lighting.LIGHTMAP)
		return
	fs.scan()   # the editor must know the new folder: the bake reimports its images there
	await _frames(5)
	while fs.is_scanning():
		await _frames(5)
	EditorInterface.open_scene_from_path(SCENE)
	await _frames(10)
	var root := EditorInterface.get_edited_scene_root()
	var lm := root.get_node_or_null("lightmap") as LightmapGI if root != null else null
	if lm == null:
		_fail("the bake scene has no LightmapGI")
		return
	lm.light_data = load(Lighting.LIGHTMAP)
	# the sky and its sun as the app has them: the content build ran before the sky's import. The bake reads the
	# sky's light from its processed radiance, which Godot makes only for a sky some viewport draws: a sky handed
	# to the LightmapGI alone baked almost no sky light (the shade came out a tenth of what the sky gives, measured
	# 2026-10-16). So the sky goes into a WorldEnvironment in the edited scene, the editor's viewport draws it, and
	# the bake takes the scene's environment.
	var sky := Lighting.sky()
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.name = "bake_environment"
	we.environment = env
	root.add_child(we)
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_SCENE
	await _frames(60)
	# the guard: the sky's light as the bake will read it must not be black
	var sky_light := sky_mean(sky)
	_say("the sky's light as the bake reads it: %.3f" % sky_light)
	if sky_light < MIN_SKY:
		_fail("the sky's light reads black (its radiance was never processed): the bake would miss it")
		return
	var sun := root.get_node_or_null("sun") as DirectionalLight3D
	if sun != null:
		var want := Lighting.sun()
		sun.transform = want.transform
		want.free()
	_say("sky: %s" % ("the photograph" if not Lighting.sky_info().is_empty() and ResourceLoader.exists(Lighting.SKY) else "a physical sky"))
	EditorInterface.edit_node(lm)
	await _frames(10)
	var button := _find_button(EditorInterface.get_base_control())
	if button == null:
		_fail("the editor's Bake Lightmaps button was not found")
		return
	if button.disabled:
		_fail("the editor cannot bake here: " + button.tooltip_text)
		return
	var t0 := Time.get_ticks_msec()
	_say("baking (%s)" % RenderingServer.get_video_adapter_name())
	button.pressed.emit()   # runs the whole bake before it returns
	await _frames(5)
	var out := load(Lighting.LIGHTMAP) as LightmapGIData
	var tex: Array = out.get_lightmap_textures() if out != null else []
	var users := out.get_user_count() if out != null else 0
	if tex.is_empty() or users == 0:
		_fail("the bake made no lightmap (%d textures, %d users)" % [tex.size(), users])
		return
	var px := 0
	for t in tex:
		var tl := t as TextureLayered
		if tl != null:
			px += tl.get_width() * tl.get_height() * tl.get_layers()
	_say("baked %d meshes into %d texture(s), %d texels, in %d s" % [users, tex.size(), px, (Time.get_ticks_msec() - t0) / 1000])
	get_tree().quit(0)

## The sky's irradiance panorama as Godot bakes it for LightmapGI (RenderingServer.sky_bake_panorama, what the bake
## calls): its mean luminance. The photograph's sky, scaled to a sun of 1, gives tenths; an unprocessed sky gives 0.
const MIN_SKY := 0.02

static func sky_mean(sky: Sky) -> float:
	var img := RenderingServer.sky_bake_panorama(sky.get_rid(), Lighting.SKY_ENERGY, true, Vector2i(64, 32))
	if img == null or img.is_empty():
		return 0.0
	img.convert(Image.FORMAT_RGBAF)
	var sum := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return sum / (img.get_width() * img.get_height())

func _find_button(n: Node) -> Button:
	if n is Button and (n as Button).text == "Bake Lightmaps":
		return n
	for c in n.get_children():
		var b := _find_button(c)
		if b != null:
			return b
	return null
