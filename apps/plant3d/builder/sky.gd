## The sky (R9): a CC0 photographed sky (Poly Haven, fetched by kit/fetch_textures.sh, pinned by SHA-256) made into
## the plant's sky at build time. The photograph's sun is taken out of it and becomes the DirectionalLight3D (a
## real-time light casts sharp shadows; a sun left in the sky would light everything a second time, without
## shadows): its direction is the brightest point, its strength the light taken out. Everything is scaled so the
## sun's light is 1 (Godot's units), so sky and sun keep the photograph's own ratio. Below the horizon the panorama
## is the plant's surroundings: a ground of the given albedo lit by that sun and sky (what a far desert plain sends
## back up). Writes built/sky/sky.exr (with its import settings) and built/sky/sky.json {sun_elevation,
## sun_azimuth, sky_energy, source}.
extends RefCounted

const OUT_W := 2048
## Above this many times the upper sky's mean luminance a pixel near the sun is sun, not sky.
const SUN_CLIP := 12.0
const SUN_CONE := 0.2   # radians round the brightest point that may be clipped (clouds elsewhere keep their glare)
const GROUND_ALBEDO := Color(0.30, 0.27, 0.22)   # dry sandy ground

static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## The direction of a panorama pixel (u, v in 0..1) as Godot's sky reads it (renderer_rd sky.glsl: u =
## atan2(x, -z) / 2π, v = acos(y) / π): u = 0 looks along -z, u = 0.25 along +x, v = 0 straight up.
static func dir_of(u: float, v: float) -> Vector3:
	var phi := u * TAU
	var theta := (0.5 - v) * PI       # elevation
	return Vector3(cos(theta) * sin(phi), sin(theta), -cos(theta) * cos(phi))

static func make(src: String, out_dir: String) -> Dictionary:
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		return {"error": "cannot read the sky " + src}
	img.convert(Image.FORMAT_RGBF)
	if img.get_width() != OUT_W:
		img.resize(OUT_W, OUT_W / 2, Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var d_az := TAU / w
	var d_el := PI / h
	# the brightest point and the upper sky's mean
	var best := -1.0
	var bu := 0
	var bv := 0
	var mean := 0.0
	var wsum := 0.0
	for y in h / 2:
		var el := (0.5 - (y + 0.5) / h) * PI
		var dw := cos(el)
		for x in w:
			var L := lum(img.get_pixel(x, y))
			mean += L * dw
			wsum += dw
			if L > best:
				best = L
				bu = x
				bv = y
	mean /= wsum
	var sun := dir_of((bu + 0.5) / w, (bv + 0.5) / h)
	var clip := mean * SUN_CLIP
	# the sun out of the sky: what lies above the clip near it, as irradiance on a surface facing it
	var e_sun := 0.0
	var e_sky := 0.0   # the sky's irradiance on a horizontal surface, after the clip
	for y in h / 2:
		var el := (0.5 - (y + 0.5) / h) * PI
		var dom := d_az * d_el * cos(el)
		for x in w:
			var c := img.get_pixel(x, y)
			var L := lum(c)
			var dv := dir_of((x + 0.5) / w, (y + 0.5) / h)
			if L > clip and dv.angle_to(sun) < SUN_CONE:
				e_sun += (L - clip) * dom * maxf(dv.dot(sun), 0.0)
				c = c * (clip / L)
				img.set_pixel(x, y, c)
				L = clip
			e_sky += L * dom * sin(el)
	if e_sun <= 0.0:
		return {"error": "no sun found in the sky " + src}
	var el_sun := asin(clampf(sun.y, -1, 1))
	# the ground below the horizon: albedo × (sun + sky) on a horizontal surface, sent back evenly (radiance = E/π)
	var e_ground := e_sun * maxf(sin(el_sun), 0.0) + e_sky
	var g := GROUND_ALBEDO * (e_ground / PI)
	for y in range(h / 2, h):
		for x in w:
			img.set_pixel(x, y, g)
	# scaled so the sun's light is 1: the sky as a panorama in those units
	var k := 1.0 / e_sun
	for y in h:
		for x in w:
			img.set_pixel(x, y, img.get_pixel(x, y) * k)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var exr := out_dir.path_join("sky.exr")
	if img.save_exr(ProjectSettings.globalize_path(exr), false) != OK:
		return {"error": "cannot write " + exr}
	var imp := FileAccess.open(ProjectSettings.globalize_path(exr) + ".import", FileAccess.WRITE)
	imp.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\ncompress/hdr_compression=1\nmipmaps/generate=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n")
	imp.close()
	var info := {"sun_elevation": rad_to_deg(el_sun), "sun_azimuth": rad_to_deg(atan2(sun.x, -sun.z)),
		"sky_to_sun": e_sky / (e_sun * maxf(sin(el_sun), 0.01)), "source": src.get_file()}
	var f := FileAccess.open(out_dir.path_join("sky.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, " "))
	return info
