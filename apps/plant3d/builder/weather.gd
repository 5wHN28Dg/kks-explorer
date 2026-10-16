## The weathering's noise (kit/weathered.gdshaderinc): four tileable noise fields, one per channel, made at build time
## with Godot's FastNoiseLite (our own: no texture to license or fetch). Saved as an ImageTexture resource with its
## mipmaps, so the build's own materials can name it before Godot's import runs.
##   r  blotches (cellular-ish value noise)      g  smooth patches (simplex)
##   b  streak and dust variation (simplex, finer) a  speckle (value noise, fine)
extends RefCounted

const SIZE := 512

static func make(path: String) -> int:
	var chans: Array = []
	var specs := [[FastNoiseLite.TYPE_VALUE_CUBIC, 0.012, 11], [FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.008, 23],
		[FastNoiseLite.TYPE_SIMPLEX, 0.03, 37], [FastNoiseLite.TYPE_VALUE, 0.09, 41]]
	for sp in specs:
		var n := FastNoiseLite.new()
		n.noise_type = sp[0]
		n.frequency = sp[1]
		n.seed = sp[2]
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		chans.append(n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true))
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, Color(chans[0].get_pixel(x, y).r, chans[1].get_pixel(x, y).r,
				chans[2].get_pixel(x, y).r, chans[3].get_pixel(x, y).r))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return ResourceSaver.save(tex, path)
