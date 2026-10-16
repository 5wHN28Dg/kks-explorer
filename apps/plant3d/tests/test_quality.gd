## Picking the quality tier (app/quality.gd, R9): a choice in the settings wins; a desktop without a measurement asks
## for the probe; a probe's result is kept per graphics adapter and decides by the GPU time limit; a new adapter is
## measured again; the presets are the bench's measured ones (0041).
extends RefCounted

const Quality = preload("res://app/quality.gd")

func run(_tree: SceneTree) -> Array:
	var p: Array = []
	var cf := ConfigFile.new()
	if Quality.choose(cf, "lean+vis").tier != "lean+vis": p.append("the command line's tier wins")
	cf.set_value("quality", "mode", "full")
	if Quality.choose(cf).tier != "full": p.append("the settings' tier wins")
	cf.set_value("quality", "mode", "auto")
	if not Quality.is_phone():
		if Quality.choose(cf).why != "probe": p.append("a desktop without a measurement probes first")
		cf.set_value("probe", "adapter", RenderingServer.get_video_adapter_name())
		cf.set_value("probe", "tier", "lean+vis")
		if Quality.choose(cf).tier != "lean+vis": p.append("the measured tier is kept for this adapter")
		cf.set_value("probe", "adapter", "another GPU")
		if Quality.choose(cf).why != "probe": p.append("another adapter is measured again")
	var tmp := ConfigFile.new()
	if Quality.record_probe(tmp, Quality.PROBE_LIMIT_MS - 0.5) != "full": p.append("under the limit: full")
	if Quality.record_probe(tmp, Quality.PROBE_LIMIT_MS + 0.5) != "lean+vis": p.append("over the limit: lean+vis")
	var lean: Dictionary = Quality.PRESETS["lean+vis"]
	if not (lean.scale == 0.6 and lean.fsr and lean.shadow_atlas == 2048 and lean.shadow_distance == 40.0 and lean.lod_threshold == 4.0):
		p.append("lean+vis is the bench's measured preset (0041)")
	var full: Dictionary = Quality.PRESETS["full"]
	if not (full.scale == 1.0 and full.shadow_distance == 80.0):
		p.append("full is the bench's measured preset (0041)")
	return p
