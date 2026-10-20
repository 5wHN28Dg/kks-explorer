## What build.sh does before the lightmap's bake (CI cannot bake: no GPU). On a fresh checkout the editor regenerated
## the scripts' documentation on a thread of its own, loading every script while the bake plugin opened the bake
## scene, and crashed in 6 of 7 bakes (2026-10-20): build.sh now gives it an empty documentation cache first
## (builder/bake/script_doc_cache.gd). Checked here: the cache is one the editor reads (a resource whose `classes`
## is an array), it goes where Godot 4.7 looks for it, and build.sh writes it before it starts the editor's bake.
extends RefCounted

const DocCache = preload("res://builder/bake/script_doc_cache.gd")

func run(_tree: SceneTree) -> Array:
	var p: Array = []
	var path := OS.get_user_data_dir().path_join("test-bake-prep/editor_script_doc_cache.res")
	if DocCache.write(path) != OK:
		p.append("the script documentation cache is written")
	else:
		var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if r == null or typeof(r.get_meta("classes", null)) != TYPE_ARRAY or (r.get_meta("classes") as Array).size() != 0:
			p.append("the cache is a resource with an empty `classes` array, as EditorHelp reads it")
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path.get_base_dir())
	if Engine.get_version_info().major != 4 or Engine.get_version_info().minor != 7:
		p.append("the cache's path is Godot 4.7's (check EditorHelp::get_script_doc_cache_full_path on a new Godot)")
	var sh := FileAccess.get_file_as_string("res://build.sh")
	var at := sh.find("--script res://builder/bake/script_doc_cache.gd")
	var bake := sh.find("-- --bake-lightmaps")
	if at < 0 or bake < 0 or at > bake:
		p.append("build.sh writes the documentation cache before the editor's bake")
	return p
