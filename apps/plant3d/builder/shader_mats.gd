## One material per shader file the app ships (`built/shaders/<name>.tres`), so that the export's shader baker compiles
## every one of them (decision 0060; WORKSHOP.md §7.1). The baker compiles only the shaders of the materials it finds
## in the exported resources (Godot's editor/export/shader_baker_export_plugin.cpp: `_customize_resource` looks at
## materials, never at a shader file alone), and the Workshop's, the walking directions' and the weather's materials
## are made by script at run time: without these their shaders were compiled on the phone, the first time in the
## plant's warm-up (a 0.7 s plant frame on the Note 9, 4.8 s after the start: the Workshop's eight surface pipelines).
## The uniforms don't change a shader's code, so one material each covers every material made from it.
extends RefCounted

const DIR := "shaders"
## Where the app's shader files are (tests/ and addons/ ship none).
const FOLDERS := ["res://app", "res://kit", "res://workshop", "res://ui", "res://sim", "res://people", "res://net", "res://voice"]

## Every shader file under FOLDERS (res:// paths, sorted).
static func shader_files() -> Array:
	var out: Array = []
	for f in FOLDERS:
		_scan(f, out)
	out.sort()
	return out

static func _scan(dir: String, out: Array) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)

## Saves the materials into `out_dir`/shaders; returns the errors.
static func build(out_dir: String) -> Array:
	var errs: Array = []
	var dir := out_dir.path_join(DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for path in shader_files():
		var sh = load(path)
		if not sh is Shader:
			errs.append("shaders: %s is not a shader" % path)
			continue
		var m := ShaderMaterial.new()
		m.shader = sh
		m.resource_name = String(path).trim_prefix("res://").get_basename().replace("/", "_")   # (unique: from the path)
		var e := ResourceSaver.save(m, dir.path_join(m.resource_name + ".tres"))
		if e != OK:
			errs.append("shaders: save %s: error %d" % [m.resource_name, e])
	return errs
