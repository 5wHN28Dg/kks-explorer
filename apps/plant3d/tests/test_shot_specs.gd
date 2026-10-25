## A `shot=` list (app/main.gd shot_specs), which on a phone comes from a shared folder (walk.txt): names made file
## names (no path out of the app's folder) of at most 40 characters, a view of five numbers or the map, anything else
## left out with why, and at most MAX_SHOTS views (a PNG each).
extends RefCounted

const Main = preload("res://app/main.gd")

func run(_tree: SceneTree) -> Array:
	var p: Array = []
	var bad: Array = []
	var got: Array = Main.shot_specs("a@1,2,3,90,-10;../../x/y@1,2,3,4,5;m@map;short@1,2,3;nan@1,2,x,4,5;@1,2,3,4,5;" + "n".repeat(80) + "@0,0,0,0,0", bad)
	var names: Array = got.map(func(s): return s.name)
	if names.size() != 4 or names[0] != "a" or names[2] != "m":
		p.append("the good views are kept in order (%s)" % str(names))
	elif names[1].contains("/") or names[1].contains("\\\\"):
		p.append("a name is a file name, no path (%s)" % names[1])
	elif names[3].length() != 40:
		p.append("a name is at most 40 characters (%d)" % names[3].length())
	if not got.is_empty() and got[0].at != [1.0, 2.0, 3.0, 90.0, -10.0]:
		p.append("a view is its five numbers (%s)" % str(got[0].at))
	if got.size() > 2 and got[2].at != null:
		p.append("@map is the map's view")
	if bad.size() != 3:
		p.append("a view without five numbers, or a shot without a name, is left out with why (%s)" % str(bad))
	bad = []
	var many := PackedStringArray()
	for i in Main.MAX_SHOTS + 10:
		many.append("s%d@0,0,0,0,0" % i)
	if Main.shot_specs(";".join(many), bad).size() != Main.MAX_SHOTS or bad.is_empty():
		p.append("at most %d shots" % Main.MAX_SHOTS)
	return p
