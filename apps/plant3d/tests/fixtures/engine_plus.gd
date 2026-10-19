## The engine with state of a kind it doesn't have yet (tests/test_run_save.gd): a saved run must carry state added
## to the engine later without a change to ui/run_save.gd.
extends "res://sim/engine.gd"

var extra_count := 0
var extra_trace := PackedFloat64Array()
var extra_seen := {}


func _step() -> void:
	super._step()
	extra_count += step_no % 3
	extra_trace.append(cur[0] * 0.5 + extra_count)
	if extra_trace.size() > 50:
		extra_trace = extra_trace.slice(1)
	extra_seen[step_no % 7] = extra_count
