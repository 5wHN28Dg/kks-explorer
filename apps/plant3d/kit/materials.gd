## The kit's materials (docs/PLANT3D.md §10, decision 0054 §5): CC0 PBR sets from ambientCG (fetched by
## kit/fetch_textures.sh, pinned by SHA-256, never committed) at three texture sizes, a tier picks the size, never a
## different material. Paint colours are a material's tint over one texture set, so one set serves every colour.
## Small pieces (instruments, tag plates, handwheels, lamps) use plain materials with no textures: under a few
## pixels a texture adds shading cost and nothing a trainee sees.
##
## The builder saves every material to built/materials/<name>.tres with the 1024 px textures (the size every export
## carries); the app's tier switches them to the tier's size when it has them (apply_tier, below).
extends RefCounted

const TEX := "res://kit/tex"
const SIZES := [2048, 1024, 512]
const DEFAULT_SIZE := 1024
## The texture size per quality tier (app/quality.gd): laptops the 2048 px set, phones 1024 px (decision 0041 measured
## the Note 9 with 2048 and 1024 px: 1024 px cut its texture memory by three quarters at the same frame times).
const TIER_SIZE := {"full": 2048, "lean+vis": 1024}

## The texture sets: the maps each uses (Color, NormalGL, Roughness) and what they are for.
const SETS := {
	"PaintedMetal004": ["NormalGL", "Roughness"],     # paint: its scratches and wear only, the colour is the tint
	"Metal032": ["Color", "NormalGL", "Roughness"],   # bare and galvanised steel: stems, flanges, frames
	"Metal009": ["Color", "NormalGL", "Roughness"],   # brushed aluminium: insulation cladding
	"CorrugatedSteel005": ["Color", "NormalGL", "Roughness"],  # wall cladding, casings
	"Concrete034": ["Color", "NormalGL", "Roughness"],
	"MetalWalkway010": ["Color", "NormalGL", "Roughness"],     # grating decks and treads
	"DiamondPlate008C": ["Color", "NormalGL", "Roughness"],    # chequer plate decks
	"Gravel023": ["Color", "NormalGL", "Roughness"],           # the ground between the areas
	"Asphalt031": ["Color", "NormalGL", "Roughness"],          # roads
}

## RAL-like paint colours (the colours are ours; equipment colours follow common practice: machines and motors in
## blue-grey or green, cabinets light grey, handwheels red, handrails and ladders yellow).
const PAINT := {
	"paint_machine": Color(0.30, 0.42, 0.55),    # turbines, generators (a blue-grey)
	"paint_motor": Color(0.22, 0.36, 0.52),      # electric motors (blue)
	"paint_pump": Color(0.18, 0.42, 0.30),       # pumps (green)
	"paint_grey": Color(0.70, 0.71, 0.70),       # cabinets, panels, transformers' light grey
	"paint_darkgrey": Color(0.30, 0.31, 0.32),   # valve bodies, actuators, gearboxes
	"paint_tank": Color(0.82, 0.82, 0.78),       # tanks and vessels (off-white)
	"paint_trafo": Color(0.45, 0.48, 0.47),      # transformer tanks and radiators
	"paint_red": Color(0.70, 0.08, 0.07),        # handwheels, fire equipment, stop buttons
	"paint_yellow": Color(0.92, 0.70, 0.08),     # handrails, ladders, guards, safety colour
	"paint_orange": Color(0.88, 0.40, 0.08),     # electric actuators (a common maker's colour)
	"paint_green": Color(0.10, 0.50, 0.20),      # start buttons, run lamps' housings
	"paint_white": Color(0.92, 0.92, 0.90),
	"paint_black": Color(0.06, 0.06, 0.06),
	"paint_beige": Color(0.78, 0.72, 0.58),      # GT and generator enclosures, filter house
	"paint_ct": Color(0.66, 0.70, 0.72),         # the cooling tower's FRP casing
}

## Every material: set (or "" for a plain one), tint, roughness, metallic, the texture's tile size in metres, and
## flags. A plain material's roughness and metallic are its values; with a set they scale the set's maps.
static func specs() -> Dictionary:
	var m := {}
	for k in PAINT:
		m[k] = {"set": "PaintedMetal004", "tint": PAINT[k], "rough": 1.0, "metal": 0.15, "tile": 1.5}
	m["steel"] = {"set": "Metal032", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.85, "tile": 1.0}
	m["steel_dark"] = {"set": "Metal032", "tint": Color(0.45, 0.45, 0.47), "rough": 1.0, "metal": 0.7, "tile": 1.0}
	m["galvanised"] = {"set": "Metal032", "tint": Color(0.85, 0.87, 0.88), "rough": 1.0, "metal": 0.75, "tile": 2.0}
	m["cladding"] = {"set": "Metal009", "tint": Color(0.92, 0.93, 0.95), "rough": 1.0, "metal": 0.8, "tile": 1.0}
	m["corrugated"] = {"set": "CorrugatedSteel005", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.6, "tile": 2.0}
	m["corrugated_casing"] = {"set": "CorrugatedSteel005", "tint": Color(0.80, 0.82, 0.84), "rough": 1.0, "metal": 0.5, "tile": 3.0}
	m["concrete"] = {"set": "Concrete034", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.0, "tile": 3.0}
	m["grating"] = {"set": "MetalWalkway010", "tint": Color(0.75, 0.75, 0.72), "rough": 1.0, "metal": 0.6, "tile": 1.0}
	m["chequer"] = {"set": "DiamondPlate008C", "tint": Color(1, 1, 1), "rough": 1.0, "metal": 0.7, "tile": 1.0}
	m["gravel"] = {"set": "Gravel023", "tint": Color(0.62, 0.60, 0.56), "rough": 1.0, "metal": 0.0, "tile": 3.0}
	m["asphalt"] = {"set": "Asphalt031", "tint": Color(0.6, 0.6, 0.6), "rough": 1.0, "metal": 0.0, "tile": 4.0}
	# plain (no textures): small pieces, faces of dials, glass, rubber, porcelain, lamps
	m["plate"] = {"set": "", "tint": Color(0.93, 0.93, 0.90), "rough": 0.35, "metal": 0.6}        # stainless tag plates
	m["plate_border"] = {"set": "", "tint": Color(0.05, 0.05, 0.05), "rough": 0.6, "metal": 0.0}
	m["dial"] = {"set": "", "tint": Color(0.97, 0.97, 0.95), "rough": 0.4, "metal": 0.0}
	m["needle"] = {"set": "", "tint": Color(0.05, 0.05, 0.05), "rough": 0.5, "metal": 0.0}
	m["brass"] = {"set": "", "tint": Color(0.78, 0.62, 0.30), "rough": 0.35, "metal": 1.0}
	m["chrome"] = {"set": "", "tint": Color(0.80, 0.81, 0.83), "rough": 0.2, "metal": 1.0}        # stems, gauge cases
	m["rubber"] = {"set": "", "tint": Color(0.05, 0.05, 0.05), "rough": 0.9, "metal": 0.0}
	m["porcelain"] = {"set": "", "tint": Color(0.36, 0.20, 0.12), "rough": 0.25, "metal": 0.0}     # bushings
	m["glass"] = {"set": "", "tint": Color(0.35, 0.45, 0.50), "rough": 0.05, "metal": 0.2}
	m["water"] = {"set": "", "tint": Color(0.18, 0.30, 0.32), "rough": 0.08, "metal": 0.1}
	m["fill"] = {"set": "", "tint": Color(0.16, 0.17, 0.18), "rough": 0.8, "metal": 0.0}            # CT fill, louvres' depth
	m["dark"] = {"set": "", "tint": Color(0.03, 0.03, 0.03), "rough": 1.0, "metal": 0.0}            # openings, shadows inside
	m["lamp_off"] = {"set": "", "tint": Color(0.55, 0.52, 0.45), "rough": 0.2, "metal": 0.0}
	m["lamp_green"] = {"set": "", "tint": Color(0.1, 0.8, 0.2), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_red"] = {"set": "", "tint": Color(0.9, 0.1, 0.05), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_amber"] = {"set": "", "tint": Color(1.0, 0.6, 0.05), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_blue"] = {"set": "", "tint": Color(0.1, 0.3, 1.0), "rough": 0.3, "metal": 0.0, "emit": true}
	m["lamp_white"] = {"set": "", "tint": Color(1.0, 0.97, 0.9), "rough": 0.3, "metal": 0.0, "emit": true}
	m["sign_green"] = {"set": "", "tint": Color(0.0, 0.45, 0.25), "rough": 0.5, "metal": 0.0}
	m["sign_yellow"] = {"set": "", "tint": Color(0.98, 0.80, 0.05), "rough": 0.5, "metal": 0.0}
	return m

static func tex_path(set_name: String, map: String, size: int) -> String:
	return "%s/%d/%s_%s.jpg" % [TEX, size, set_name, map]

## Makes a material from its spec with textures of `size` px (when they were fetched; else plain, which the build
## reports once).
static func make(name: String, spec: Dictionary, size := DEFAULT_SIZE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = name
	mat.albedo_color = spec.tint
	mat.roughness = spec.rough
	mat.metallic = spec.metal
	var s: String = spec.get("set", "")
	if s != "":
		_textures(mat, s, size)
		mat.uv1_scale = Vector3.ONE / float(spec.get("tile", 1.0))
	if spec.get("emit", false):
		mat.emission_enabled = true
		mat.emission = spec.tint
		mat.emission_energy_multiplier = 2.0
	return mat

static func _textures(mat: StandardMaterial3D, set_name: String, size: int) -> bool:
	var maps: Array = SETS[set_name]
	var ok := true
	for m in maps:
		var p := tex_path(set_name, m, size)
		if not ResourceLoader.exists(p):
			ok = false
			continue
		var t := load(p) as Texture2D
		match m:
			"Color": mat.albedo_texture = t
			"NormalGL":
				mat.normal_enabled = true
				mat.normal_texture = t
			"Roughness":
				mat.roughness_texture = t
	return ok

## The textures' size for a tier: the tier's size when this build carries it, else the largest smaller one, else
## the default (the Android export carries 1024 and 512 px only).
static func size_for(tier: String) -> int:
	var want: int = TIER_SIZE.get(tier, DEFAULT_SIZE)
	for s in SIZES:
		if s <= want and ResourceLoader.exists(tex_path("Concrete034", "Color", s)):
			return s
	return DEFAULT_SIZE

## Switches every built material to the tier's texture size (materials are shared resources: every mesh using one
## follows). `mats` is the built materials' folder.
static func apply_tier(tier: String, mats_dir := "res://built/materials") -> int:
	var size := size_for(tier)
	var all := specs()
	var n := 0
	for name in all:
		var p := mats_dir.path_join(name + ".tres")
		if not ResourceLoader.exists(p):
			continue
		var mat := load(p) as StandardMaterial3D
		var s: String = all[name].get("set", "")
		if mat != null and s != "" and _textures(mat, s, size):
			n += 1
	return n
