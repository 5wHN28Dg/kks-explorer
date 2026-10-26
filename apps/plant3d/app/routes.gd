## Scripted routes (app/autopilot.gd steps) through the first train, in plant coordinates (x east, y north, z up).
##   climb   up HRSG 1's stair tower (30 m, nine flights), across the roof to the stack and up its ladder to the
##           stack platform at +40, then back down the same way: the walking test's route
##   pit     up the turbine hall's condenser pit stair (-6 m to the ground) and back down
##   frames  the frame-time walk (wiki measurement rules): out of the control room, through the turbine hall
##           (its west and east doors), along the road, up and down HRSG 1's stair tower, out past the cooling
##           tower to the water treatment plant (between the posts of the pipes to the train, through its
##           treatment building past the RO trains, round by the demineralised water tanks), and back; looped
##   camp    the frame-time walk through the site and the camp (milestone C1): out of the control room, along the
##           palms to the plant gate, the road to the camp, into block 1 and one of its rooms, along its corridor, across
##           the road to the mess hall and between its tables, and back; looped
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

## Out of the turbine hall's condenser pit (-6 m) by its straight stair, and back down.
static func pit(plant) -> Array:
	var r: Array = [_to(57, 2.5, -6)]
	r.append_array(_stair(plant, "st_pit_stair"))
	r.append(_to(57, 13.5, 0))
	r.append_array(_stair(plant, "st_pit_stair", true))
	r.append(_to(57, 2.5, -6))
	return r

static func frames(plant) -> Array:
	var r: Array = [_to(-20, 0), _to(-12, 0), _to(-5, 0), _to(-5, 20), _to(2, 20), _to(20, 20), _to(50, 21),
		_to(74, 5), _to(86, 5), _to(86, 34.5), _to(93.5, 44.5)]
	r.append_array(_stair(plant, "hrsg1_stair"))
	# along the roof's walkway (y 56) and back: the line from the landing's corner straight across to (130, 56) ran
	# along the landing's rails for 9 m, the walker and the crowd's lanes (app/crowd.gd) touching them (2026-10-27)
	r.append_array([_to(101.4, 52.5, 30), _to(101.4, 56, 30), _to(130, 56, 30), _to(101.4, 56, 30), _to(101.4, 52.5, 30),
		_to(101.4, 49.5, 30)])
	r.append_array(_stair(plant, "hrsg1_stair", true))
	r.append_array([_to(93.5, 44.5), _to(140, 36), _to(165, 36), _to(165, 30)])
	r.append_array(wtp_loop())
	r.append_array([_to(165, 30), _to(93.5, 36), _to(-5, 36), _to(-5, 0), _to(-12, 0), _to(-20, 0)])
	return r

## The camp walk: about 900 m, 11 minutes at a walk; the interiors load on the way (app/interiors.gd).
static func camp(_plant) -> Array:
	var out: Array = [_to(-20, 0), _to(-12, 0), _to(-5, 0), _to(-5, 21.2), _to(-42, 21.2), _to(-50, 22), _to(-139, 22),
		_to(-262, 22), _to(-411, 22), _to(-411, 35), _to(-405.5, 35),
		# block 1: its corridor, room 101 and back, out by the east door
		_to(-403, 35), _to(-403, 33.4), _to(-401.5, 32.8), _to(-403, 33.4), _to(-403, 35), _to(-365.5, 35),
		_to(-362, 35), _to(-362, 22),
		# the mess hall: across the road by its crossing, between the tables, along the serving counter, and out
		_to(-340, 22), _to(-340, 6), _to(-340, 2.5), _to(-340, -5), _to(-350, -5), _to(-340, -5), _to(-340, 2.5),
		_to(-340, 6), _to(-340, 22),
		# back to the plant
		_to(-139, 22), _to(-50, 22), _to(-42, 21.2), _to(-5, 21.2), _to(-5, 0), _to(-12, 0)]
	return out
## From the cooling tower's north-east corner into the water treatment plant and back (docs/plant3d/SITE.md): across
## the makeup and transfer pipes' post lines where their posts leave room (x 266: their posts stand at 264.25 and
## 268.75 on y = 38, at 263.4 and 267.7 on y = 41.5; y 45.5: at y 42 and 50 on x = 271, 43.5 and 47.6 on x = 274.1),
## in at the treatment building's west door, past the RO trains, out at its north door (y 82: clear of the posts of
## the permeate and mixed bed lines at y 80.3 and 80.6), and back by the demineralised water tanks.
static func wtp_loop() -> Array:
	return [_to(258, 31), _to(266, 31), _to(266, 45.5), _to(294, 45.5), _to(294, 56), _to(303, 56), _to(313, 57.2),
		_to(327, 57.2), _to(327, 71), _to(322, 71), _to(322, 82), _to(296, 82), _to(294, 72), _to(294, 45.5),
		_to(266, 45.5), _to(266, 31), _to(258, 31)]
