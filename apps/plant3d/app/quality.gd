## Quality tiers (R9; measured in decision 0041 with tools/plant3d/bench): the bench's presets, the same names.
##   full       laptops (Forward+): native resolution, shadows to 80 m in 4 cascades. 0041: 82 fps at p95 on this
##              laptop's Iris Xe at 1600×900 over 10 minutes.
##   lean+vis   phones (Mobile renderer; the Note 9 is the minimum): 60 % resolution with FSR 1, a 2048 px shadow
##              atlas, shadows to 40 m, mesh LOD threshold 4 px, and `detail` pieces cut at 3 px on the screen
##              (PLANT3D.md §10). 0041: 99.9 % of frames shown at >= 30 fps on the Note 9 over 10 minutes.
## The Compatibility renderer (no Vulkan or Direct3D 12: Godot falls back to it) gets lean+vis too; it has not been
## measured on any device.
##
## Which tier (R9: "measured on the device, not guessed"): a manual choice in the settings wins. Otherwise phones take
## lean+vis (their class was measured: full showed a 120 ms hitch on the Note 9, 0041), and a desktop measures its
## GPU once per graphics adapter at first start (probe below) and keeps the result in user://settings.cfg.
extends RefCounted

const Mat = preload("res://kit/materials.gd")
const Lighting = preload("res://app/lighting.gd")

const PRESETS := {
	"full": {"scale": 1.0, "fsr": false, "shadow_atlas": 4096, "shadow_distance": 80.0, "lod_threshold": 1.0,
		"detail_min_px": 1.5},
	"lean+vis": {"scale": 0.6, "fsr": true, "shadow_atlas": 2048, "shadow_distance": 40.0, "lod_threshold": 4.0,
		"detail_min_px": 3.0},
}
const TIERS := ["full", "lean+vis"]
const SETTINGS := "user://settings.cfg"
## The probe's limit: the full tier's GPU time per frame (median over the probe) on the heaviest view, in ms. Laptops
## must hold 60 fps (the wiki's rule): above 12 ms of GPU time the rest of the frame no longer fits in 16.7 ms.
const PROBE_LIMIT_MS := 12.0
const PROBE_FRAMES := 120
const PROBE_SKIP := 30          # the first frames compile pipelines: not counted

static func settings() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	return cf

static func save(cf: ConfigFile) -> void:
	cf.save(SETTINGS)

static func is_phone() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

static func renderer() -> String:
	return RenderingServer.get_current_rendering_method()

## {"tier": name, "why": text}, or {"tier": "", "why": "probe"} when a desktop must measure first.
static func choose(cf: ConfigFile, forced := "") -> Dictionary:
	if forced in TIERS:
		return {"tier": forced, "why": "given on the command line"}
	var mode: String = cf.get_value("quality", "mode", "auto")
	if mode in TIERS:
		return {"tier": mode, "why": "chosen in the settings"}
	if is_phone():
		return {"tier": "lean+vis", "why": "a phone: the tier measured on the Note 9 (decision 0041)"}
	if renderer() == "gl_compatibility":
		return {"tier": "lean+vis", "why": "the Compatibility renderer (no Vulkan or Direct3D 12)"}
	var adapter := RenderingServer.get_video_adapter_name()
	if cf.get_value("probe", "adapter", "") == adapter and cf.get_value("probe", "tier", "") in TIERS:
		return {"tier": cf.get_value("probe", "tier"), "why": "measured on this GPU (%.1f ms)" % float(cf.get_value("probe", "gpu_ms", 0.0))}
	return {"tier": "", "why": "probe"}

## Records a probe's result in cf (the caller saves it) (the median GPU time of the full tier on the heaviest view).
static func record_probe(cf: ConfigFile, gpu_ms: float) -> String:
	var tier := "full" if gpu_ms <= PROBE_LIMIT_MS else "lean+vis"
	cf.set_value("probe", "adapter", RenderingServer.get_video_adapter_name())
	cf.set_value("probe", "gpu_ms", snappedf(gpu_ms, 0.01))
	cf.set_value("probe", "tier", tier)
	return tier

## Applies a tier to the viewport, the sun and the environment, and (`to_plant`) to the plant's pieces and materials:
## the app's early start (decision 0060) chooses the tier before the plant is loaded and applies those after it (its
## materials, loaded and freed again before anything held them, would only cost the phone's start time).
static func apply(tier: String, vp: Viewport, sun: DirectionalLight3D, env: Environment, to_plant := true) -> void:
	var p: Dictionary = PRESETS[tier]
	if p.fsr:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = p.scale
	vp.mesh_lod_threshold = p.lod_threshold
	RenderingServer.directional_shadow_atlas_set_size(p.shadow_atlas, true)
	sun.directional_shadow_max_distance = p.shadow_distance
	Lighting.apply(tier, env)
	_measure_overrides(sun)
	vp.set_meta("detail_min_px", p.detail_min_px)
	if to_plant:
		apply_ranges(vp)
	if not vp.size_changed.is_connected(_on_resize.bind(vp)):
		vp.size_changed.connect(_on_resize.bind(vp))   # §10: the ranges again when the resolution changes
	if to_plant:
		Mat.apply_tier(tier)   # the tier's texture size (kit/materials.gd): one material set, three sizes

## Measuring what the sun's shadow costs (main.gd's `fx_off=`): `shadow` no real-time shadow, `cascades2` two
## cascades instead of four, `shadow40` shadows to 40 m, `shadowhard` no soft filtering.
static func _measure_overrides(sun: DirectionalLight3D) -> void:
	var off: PackedStringArray = Lighting.off
	if "shadow" in off:
		sun.shadow_enabled = false
	if "cascades2" in off:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if "shadow40" in off:
		sun.directional_shadow_max_distance = 40.0
	if "shadowhard" in off:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)

## The legibility of a tag plate's code (PLANT3D.md §10): its text is drawn while a character covers 8 px.
const LEGIBLE_PX := 8.0

## Visibility ranges by size (PLANT3D.md §10): `detail` pieces are drawn while they cover at least the tier's min_px
## on the screen, d_max = size × f / min_px, f the focal length in pixels at the drawn resolution; tag plates' codes
## while a character covers LEGIBLE_PX. Detail pieces carry their size in the meta "detail_size" and sit in the
## group "detail"; an instanced cell of them (builder/kit_place.gd) also carries "box_half", the half diagonal of its
## box, which is added (Godot measures a range to the centre of the instance's box: decision 0041), so no piece in
## it goes before its own distance. No fade: a piece under the tier's few pixels goes unseen, and a fading instance
## is drawn through another (transparent) pipeline, compiled the first time anything fades (a 190 ms frame on the Note 9,
## 2026-10-16). Codes are in the group "legible" with "legible_size", a character's height.
static func _on_resize(vp: Viewport) -> void:
	apply_ranges(vp)

## The walker's field of view (app/player.gd): the ranges are for walking, whatever camera is current (the map's).
const WALK_FOV := 70.0

## The drawn height in pixels: the window's real pixels (with canvas_items stretching the viewport's visible rect is
## the logical size, not the screen's), times the 3D scale.
static func drawn_height(vp: Viewport) -> float:
	var w := vp.get_window()
	var px := float(w.size.y) if w != null and w.size.y > 0 else vp.get_visible_rect().size.y
	return px * vp.scaling_3d_scale

static func apply_ranges(vp: Viewport) -> void:
	if not vp.has_meta("detail_min_px"):
		return
	var h := drawn_height(vp)
	var f := (h * 0.5) / tan(deg_to_rad(WALK_FOV * 0.5))
	var min_px: float = vp.get_meta("detail_min_px")
	for n in vp.get_tree().get_nodes_in_group("detail"):
		if n is GeometryInstance3D and n.has_meta("detail_size"):
			var d: float = float(n.get_meta("detail_size")) * f / min_px
			var margin := d * 0.1
			n.visibility_range_end = d + float(n.get_meta("box_half", 0.0)) + margin
			n.visibility_range_end_margin = margin
			n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for n in vp.get_tree().get_nodes_in_group("legible"):
		if n is GeometryInstance3D and n.has_meta("legible_size"):
			var d: float = float(n.get_meta("legible_size")) * f / LEGIBLE_PX
			n.visibility_range_end = d
			n.visibility_range_end_margin = d * 0.1
			n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
