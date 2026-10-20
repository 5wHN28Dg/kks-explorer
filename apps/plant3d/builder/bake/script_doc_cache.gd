## Gives the editor an (empty) script documentation cache before build.sh starts it to bake the lightmap.
## Without the cache (a fresh checkout: .godot/ is new) the editor regenerates the scripts' documentation on a thread
## of its own that loads every script of the project (Godot 4.7.2, editor/doc/editor_help.cpp,
## regenerate_script_doc_cache), and it does so just when the bake plugin opens the bake scene on the main thread:
## the editor crashed (signal 11, on that thread) in 6 of 7 bakes from a fresh checkout's state, and in none of 3 with
## this cache there (2026-10-20). With a cache the editor only reads it (no script is loaded). The bake needs no
## script documentation. The cost: the editor's help for this project's own scripts stays incomplete in a checkout that
## was baked (the editor reads the cache instead of regenerating it, and saves only the docs it holds); delete
## .godot/editor/editor_script_doc_cache.res to have it regenerated.
##   godot --headless --path apps/plant3d --script res://builder/bake/script_doc_cache.gd
extends SceneTree

## Where Godot 4.7 keeps it (EditorHelp::get_script_doc_cache_full_path: the project's editor settings folder).
const PATH := "res://.godot/editor/editor_script_doc_cache.res"

static func write(path := PATH) -> Error:
	var full := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var r := Resource.new()
	r.set_meta("classes", [])
	return ResourceSaver.save(r, full, ResourceSaver.FLAG_COMPRESS)

func _init() -> void:
	var err := write()
	if err != OK:
		printerr("bake: cannot write the script documentation cache %s (error %d)" % [PATH, err])
	quit(1 if err != OK else 0)
