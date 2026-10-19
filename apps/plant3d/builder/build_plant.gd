## The content build's entry point (decision 0054 §4), run by build.sh, never by the app:
##   godot --headless --path apps/plant3d --script res://builder/build_plant.gd [-- --data=DIR --out=res://built]
## DIR defaults to the repository's data/plant3d. The content must have passed ref/plant3d.py first (build.sh does
## that): Godot's JSON reader is not strict. Exits 1 and prints every error when the build refuses the content.
extends SceneTree

const Builder = preload("res://builder/plant_builder.gd")
const NavBake = preload("res://builder/nav_bake.gd")

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var data: String = args.get("data", ProjectSettings.globalize_path("res://").path_join("../../data/plant3d").simplify_path())
	var out: String = args.get("out", "res://built")
	var b := Builder.new()
	var t0 := Time.get_ticks_msec()
	if not b.read(data) or not b.collect():
		for e in b.errors:
			printerr("build: ", e)
		quit(1)
		return
	# a stale build must not pass for this one
	_clear(ProjectSettings.globalize_path(out))
	var err := b.build_all(out)
	for e in b.errors:
		printerr("build: ", e)
	if err != 0 or not b.errors.is_empty():
		quit(1)
		return
	print("build: %d areas, %d equipment, %d stairs, %d ladders, %d walkable surfaces in %d ms -> %s" % [b.areas.size(),
		b.equipment.size(), b.stairs.size(), b.ladders.size(), b.surfaces.size(), Time.get_ticks_msec() - t0, out])
	print("build: parts kit: %d parts placed, %d triangles at full detail, %d instanced meshes, %d pipe supports" % [
		b.kp.instances, b.kp.tris_total, b.kp.cells_made, b.kp.supports])
	for u in b.kp.unsupported:
		print("build: warning: nothing to stand a pipe support on under ", u)
	_nav.call_deferred(out, b)

## The walking directions' navigation mesh, from the scenes just saved (builder/nav_bake.gd); deferred, so that the
## scenes are parsed inside the running tree.
func _nav(out: String, b) -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("plant.json")))
	var scenes: Array = [m.ground]
	for a in m.areas:
		scenes.append(a.scene)
	var st: Array = m.start.at
	var r: Dictionary = await NavBake.bake(root, out, scenes, b.stairs, b.ladders, Vector3(st[0], st[1], st[2]))
	if r.has("error"):
		printerr("build: ", r.error)
		quit(1)
		return
	print("build: navigation mesh: %d polygons (%d out of reach dropped), %d vertices, %d doors and %d stairs left out, %d bytes, %d ms" % [
		r.polygons, r.dropped, r.vertices, r.doors, r.stairs, r.bytes, r.ms])
	quit(0)

func _clear(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for s in d.get_directories():
		_clear(dir.path_join(s))
		d.remove(s)
