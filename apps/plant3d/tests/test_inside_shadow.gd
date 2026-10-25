## What stands inside a building casts no shadow of the sun (builder/plant_builder.gd `_mark_no_sun`, app/quality.gd
## `apply_shadows`; decision 0066, "The last frame spikes"): in the built plant every piece marked inside a building
## (`far_inside`) that would cast is in the group `inside_shadow`, and no piece outside one is; the start's
## `apply_shadows` turns their shadows off and leaves every other caster casting; `fx_on=inside_shadow` leaves them
## casting (the measurement of what it saves). The bake is not changed: the built scenes keep every caster's setting.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Quality = preload("res://app/quality.gd")
const Lighting = preload("res://app/lighting.gd")
const OFF := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func run(tree: SceneTree) -> Array:
	var p: Array = []
	var plant: Node3D = Plant.new()
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return ["the built plant loads: " + err]
	var marked := {}    # area -> pieces in the group
	var outside: Array = []   # casters outside every building (they keep casting)
	for n in plant.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var area := _area(gi, plant)
		if gi.is_in_group("inside_shadow"):
			marked[area] = int(marked.get(area, 0)) + 1
			if not gi.has_meta("far_inside"):
				p.append("%s, in the group inside_shadow, stands inside a building" % plant.get_path_to(gi))
			if gi.cast_shadow == OFF:
				p.append("%s: the built scene keeps its shadow for the bake (it is switched off when the app runs)" % plant.get_path_to(gi))
		elif gi.has_meta("far_inside") and gi.cast_shadow != OFF:
			p.append("%s stands inside a building and would cast: it is in the group inside_shadow" % plant.get_path_to(gi))
		elif gi.cast_shadow != OFF and outside.size() < 50:
			outside.append(gi)
	for area in ["area_wtp", "area_st"]:
		if int(marked.get(area, 0)) < 20:
			p.append("%s's halls hold pieces that cast no sun shadow (%d)" % [area, int(marked.get(area, 0))])
	if outside.is_empty():
		p.append("pieces outside the buildings cast the sun's shadow")
	# the start's switch: the group off, the rest as built
	var was: PackedStringArray = Lighting.on
	Lighting.on = PackedStringArray()
	Quality.apply_shadows(plant)
	var still := 0
	for n in plant.get_tree().get_nodes_in_group("inside_shadow"):
		if (n as GeometryInstance3D).cast_shadow != OFF:
			still += 1
	if still > 0:
		p.append("apply_shadows switches off the shadows of what stands inside buildings (%d still cast)" % still)
	for gi in outside:
		if gi.cast_shadow == OFF:
			p.append("%s, outside the buildings, still casts the sun's shadow" % plant.get_path_to(gi))
			break
	# fx_on=inside_shadow: as before
	Lighting.on = PackedStringArray(["inside_shadow"])
	Quality.apply_shadows(plant)
	for n in plant.get_tree().get_nodes_in_group("inside_shadow"):
		if (n as GeometryInstance3D).cast_shadow == OFF:
			p.append("fx_on=inside_shadow leaves %s casting" % plant.get_path_to(n))
			break
	Lighting.on = was
	plant.free()
	return p

static func _area(n: Node, plant: Node) -> String:
	while n != null and n.get_parent() != plant:
		n = n.get_parent()
	return String(n.name) if n != null else ""
