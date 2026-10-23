## The people's assets alone (builder/people/build_people.gd), without the rest of the content build:
##   godot --headless --path apps/plant3d --script res://builder/people/build_only.gd
extends SceneTree

func _init() -> void:
	var b = load("res://builder/people/build_people.gd").new()
	var s: Dictionary = b.build("res://built/people")
	for e in b.errors:
		printerr("build: ", e)
	if not b.errors.is_empty():
		quit(1)
		return
	print("build: people: %d looks, triangles %s, %d bones, %d clips, gaits %s" % [s.looks.size(), s.triangles, s.bones,
		s.clips.size(), s.speeds])
	quit(0)
