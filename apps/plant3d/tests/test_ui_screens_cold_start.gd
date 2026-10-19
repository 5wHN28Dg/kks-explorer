## The cold start (docs/plant3d/FIRST-TRAIN.md §4) worked from the control room screens (docs/PLANT3D.md §7.11): as
## tests/test_ui_cold_start.gd, but every operation the screens offer is made by a click on the equipment on its
## screen (ui/mimic.gd) and its card; the local ones in the field. The trace must still be the reference's.
extends RefCounted


func run(tree: SceneTree) -> Array:
	var t = load("res://tests/test_ui_cold_start.gd").new()
	t.via_screens = true
	return await t.run(tree)
