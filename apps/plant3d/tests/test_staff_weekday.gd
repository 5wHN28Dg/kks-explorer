## The weekday a duty's slots are made for (docs/PLANT3D.md §17.11, slots by weekday) is found from the duty's start
## by floor division, as the reference's: a duty planned on day −1 (planning starts two days before the run) starts
## at a negative clock time, which truncating division put on day 0 (blind review of S2).
extends RefCounted

const Staff = preload("res://sim/staff.gd")


func run(_tree: SceneTree) -> Array:
	var p: Array = []
	var s = Staff.new()
	s.week = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
	var want := {1: "mon", 7: "sun", 8: "mon", 0: "sun", -1: "sat", -2: "fri"}
	for day in want:
		for hh in [0, 6, 22]:
			var t: int = day * Staff.DAY + hh * 36000
			if s.weekday(t) != want[day]:
				p.append("day %d at %02d:00 is %s, not %s" % [day, hh, s.weekday(t), want[day]])
	return p
