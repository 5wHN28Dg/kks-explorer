## The water treatment plant started from cold (docs/plant3d/WATER-TREATMENT.md §7, procedure wtp_start) through the
## interaction layer, as tests/test_ui_cold_start.gd does the train's: begun from the procedure panel (the plant
## restarts at wtp_cold), every operation made from its card at the WTP's own control desk 00CWD10 (its screens work
## the WTP; the main control room's do not), the plant run with the time bar until demineralised water is
## transferred to the train's tank. The trace must be the reference's (ref/vectors/plant3d-v2.json `wtp`).
extends RefCounted


func run(tree: SceneTree) -> Array:
	var t = load("res://tests/test_ui_cold_start.gd").new()
	t.vector_file = "plant3d-v2.json"
	t.run_key = "wtp"
	t.desk = "00CWD10"
	return await t.run(tree)
