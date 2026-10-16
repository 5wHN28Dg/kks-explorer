## Editor-only (never exported): registers the export plugin that puts the intent filter for walkdown-plant://
## links into the Android manifest (export.gd).
@tool
extends EditorPlugin

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("export.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
