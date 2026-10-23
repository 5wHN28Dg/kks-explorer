## The lightmap's filter per device (app/lighting.gd lightmap_bicubic): Godot's bicubic lightmap filter drew the bake
## as dark and pale blocks on the Honor 600's Adreno 722 (2026-10-23), so phones and any Adreno read it bilinear;
## laptops keep the smoother bicubic filter; `fx_on=bicubic` turns it on anywhere (to see the fault on a device).
extends RefCounted

const Lighting = preload("res://app/lighting.gd")

func run(_tree: SceneTree) -> Array:
	var p: Array = []
	var keep := Lighting.on
	Lighting.on = PackedStringArray()
	if Lighting.lightmap_bicubic(true, "Adreno (TM) 722"):
		p.append("an Adreno phone reads the lightmap bilinear")
	if Lighting.lightmap_bicubic(true, "Mali-G72"):
		p.append("every phone reads the lightmap bilinear (phone GPUs are not measured one by one)")
	if Lighting.lightmap_bicubic(false, "Qualcomm(R) Adreno(TM) X1-85 GPU"):
		p.append("an Adreno outside a phone (Windows on Snapdragon) reads the lightmap bilinear")
	if not Lighting.lightmap_bicubic(false, "Intel(R) Iris(R) Xe Graphics (TGL GT2)"):
		p.append("a laptop keeps the bicubic filter")
	Lighting.on = PackedStringArray(["bicubic"])
	if not Lighting.lightmap_bicubic(true, "Adreno (TM) 722"):
		p.append("fx_on=bicubic turns the bicubic filter on, also on a phone")
	Lighting.on = keep
	return p
