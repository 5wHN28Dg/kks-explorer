## The water treatment plant's day work (docs/plant3d/WATER-TREATMENT.md §7, milestone W3): RO train B cleaned in
## place by the procedure ro_cip from wtp_normal (the CIP tank filled, dosed and heated, the high-pH and then the
## low-pH cleaning, the tank drained to the pit, the pit neutralised), through the interaction layer as
## tests/test_ui_wtp_start.gd does the start: begun from the procedure panel (the plant restarts at wtp_normal), every
## operation made from its card at the WTP's own control desk 00CWD10, the plant run with the time bar. The trace must
## be the reference's (ref/vectors/plant3d-v2.json `wtp_cip`).
extends RefCounted


func run(tree: SceneTree) -> Array:
	var t = load("res://tests/test_ui_cold_start.gd").new()
	t.vector_file = "plant3d-v2.json"
	t.run_key = "wtp_cip"
	t.desk = "00CWD10"
	return await t.run(tree)
