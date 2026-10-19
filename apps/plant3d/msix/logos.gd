## The MSIX's logos from the app's icon (make-msix.sh): Square44x44Logo, Square150x150Logo and StoreLogo (50 px), drawn
## from icon.svg at their size by Godot's own SVG renderer (no other tool needed).
##   godot --headless --path apps/plant3d --script res://msix/logos.gd -- OUT_DIR
extends SceneTree

const SIZES := {"Square44x44Logo": 44, "Square150x150Logo": 150, "StoreLogo": 50}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else ""
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var ok := out != "" and svg != ""
	for n in SIZES:
		if not ok:
			break
		var img := Image.new()
		var px: int = SIZES[n]
		ok = img.load_svg_from_string(svg, px / 512.0) == OK   # icon.svg's viewBox is 512 × 512
		if ok and img.get_size() != Vector2i(px, px):
			img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		ok = ok and img.save_png(out.path_join(n + ".png")) == OK
	if not ok:
		printerr("logos: could not make the logos into '%s'" % out)
	quit(0 if ok else 1)
