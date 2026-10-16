## Scripted routes (app/autopilot.gd steps) through the first train, in plant coordinates (x east, y north, z up).
##   climb   up HRSG 1's stair tower (30 m, nine flights), across the roof to the stack and up its ladder to the
##           stack platform at +40, then back down the same way: the walking test's route
##   frames  the frame-time walk (wiki measurement rules): out of the control room, through the turbine hall
##           (its west and east doors), along the road, up and down HRSG 1's stair tower, and back; looped
extends RefCounted

const Plant = preload("res://app/plant.gd")

## A step to (x, y, z); walking it, the walker's feet never go below z (the walking test checks: no falling through).
static func _to(x: float, y: float, z := 0.0) -> Dictionary:
	return {"to": Plant.g(x, y, z), "floor": z}

static func _stair(plant, id: String, down := false) -> Array:
	var path: Array = plant.stair_path(id)
	if down:
		path.reverse()
	return path.map(func(p): return {"to": p, "floor": p.y})

static func climb(plant) -> Array:
	var r: Array = [_to(93.5, 44.5)]
	r.append_array(_stair(plant, "hrsg1_stair"))
	# round the LP drum's downcomer (10LAB10BR001), which comes down through the walkway at (152, 65)
	r.append_array([_to(101.4, 52.5, 30), _to(101.4, 56, 30), _to(149, 56, 30), _to(149, 63.8, 30), _to(155, 63.8, 30)])
	r.append({"ladder": "hrsg1_stack_ladder", "dir": "up"})
	r.append(_to(156, 63, 40))   # along the stack platform, then back to the ladder
	r.append({"ladder": "hrsg1_stack_ladder", "dir": "down"})
	r.append_array([_to(155, 63.8, 30), _to(149, 63.8, 30), _to(149, 56, 30), _to(101.4, 56, 30), _to(101.4, 52.5, 30), _to(101.4, 49.5, 30)])
	r.append_array(_stair(plant, "hrsg1_stair", true))
	r.append(_to(93.5, 44.5))
	return r

static func frames(plant) -> Array:
	var r: Array = [_to(-20, 0), _to(-12, 0), _to(-5, 0), _to(-5, 20), _to(2, 20), _to(20, 20), _to(50, 21),
		_to(74, 5), _to(86, 5), _to(86, 34.5), _to(93.5, 44.5)]
	r.append_array(_stair(plant, "hrsg1_stair"))
	r.append_array([_to(101.4, 52.5, 30), _to(130, 56, 30), _to(101.4, 56, 30), _to(101.4, 52.5, 30), _to(101.4, 49.5, 30)])
	r.append_array(_stair(plant, "hrsg1_stair", true))
	r.append_array([_to(93.5, 44.5), _to(140, 36), _to(165, 36), _to(165, 30), _to(93.5, 36), _to(-5, 36), _to(-5, 0),
		_to(-12, 0), _to(-20, 0)])
	return r
