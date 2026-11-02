## The Workshop's explode function (docs/plant3d/WORKSHOP.md §4.3): the slider's value s in [0, 1] gives every
## component's offset by a pure function, so the same s always gives the same transforms and 1 -> 0 restores them
## exactly. Each level of the tree below the chosen root moves in its own stage of s (level d of D during
## [d / D, (d + 1) / D], eased by smoothstep), children ride out with their subassembly and then leave it; a fastener
## group's items back out along their own axis in the stage of the level below their component. The children of a
## sealed component never come apart. Nothing here knows any part kind.
extends RefCounted

## The tree read from a Workshop scene (builder/workshop_build.gd): {comps: {id: {parent, dir, dist, sealed}},
## groups: {id: {host, items: [Transform3D], back_out}}, order: [ids, parents first]}.
static func spec_of(root: Node3D) -> Dictionary:
	var words: Dictionary = root.get_meta("workshop", {})
	var comps := {}
	var groups := {}
	var order: Array = []
	_walk(root, "", words, comps, groups, order)
	return {"comps": comps, "groups": groups, "order": order}

static func _walk(n: Node, parent: String, words: Dictionary, comps: Dictionary, groups: Dictionary, order: Array) -> void:
	for c in n.get_children():
		if not c is Node3D:
			continue
		if c.has_meta("explode"):
			var id: String = c.get_meta("id")
			var ex: Array = c.get_meta("explode")
			comps[id] = {"parent": parent, "dir": ex[0], "dist": float(ex[1]),
				"sealed": words.get("components", {}).get(id, {}).get("sealed", false) == true}
			order.append(id)
			_walk(c, id, words, comps, groups, order)
		elif c.has_meta("items"):
			groups[c.get_meta("id")] = {"host": parent, "items": c.get_meta("items"), "back_out": float(c.get_meta("back_out")),
				"axis": c.get_meta("back_axis", Vector3.UP)}

## Smoothstep of t clamped to [0, 1].
static func ease01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## The levels below `root` ("" the whole machine): {id: level} for every component that moves (a sealed component's
## descendants don't), and D, the number of levels (fastener groups count as a level below their host).
static func levels(spec: Dictionary, root := "") -> Array:
	var lv := {}
	var deepest := -1
	for id in spec.order:
		var d := _level(spec, id, root)
		if d < 0:
			continue
		lv[id] = d
		deepest = maxi(deepest, d)
	var glv := {}
	for g in spec.groups:
		var host: String = spec.groups[g].host
		var d: int = 0 if host == root else (lv[host] + 1 if lv.has(host) else -1)
		if d < 0 or (host != "" and (spec.comps[host].sealed or _in_sealed(spec, host))):
			continue   # a sealed component's fasteners are its own insides: they stay with it
		glv[g] = d
		deepest = maxi(deepest, d)
	return [lv, glv, deepest + 1]

## A component's level below root (0: root's children), -1 when it isn't below root or a sealed ancestor holds it.
static func _level(spec: Dictionary, id: String, root: String) -> int:
	var d := 0
	var at: String = spec.comps[id].parent
	while at != root:
		if at == "":
			return -1   # not below root
		if spec.comps[at].sealed:
			return -1
		at = spec.comps[at].parent
		d += 1
	if root != "" and (spec.comps[root].sealed or _in_sealed(spec, root)):
		return -1   # the chosen root is sealed or inside a sealed component: nothing in it comes apart
	return d

static func _in_sealed(spec: Dictionary, id: String) -> bool:
	var at := id
	while at != "":
		if spec.comps[at].sealed and at != id:
			return true
		at = spec.comps[at].parent
	return false

## Each moving component's own offset (relative to its parent, in the part's frame) at slider value s: its explode
## direction times distance times its stage's eased progress. {id: Vector3}; components not listed stay home.
static func offsets(spec: Dictionary, s: float, root := "") -> Dictionary:
	var L := levels(spec, root)
	var lv: Dictionary = L[0]
	var D: int = L[2]
	var out := {}
	if D <= 0:
		return out
	for id in lv:
		var d: int = lv[id]
		var p := ease01(s * D - d)
		var c: Dictionary = spec.comps[id]
		out[id] = (c.dir as Vector3) * c.dist * p
	return out

## Each fastener group's items' offsets at s: {group: [Vector3 per item]} (each along its own back-out axis: the
## scene's `back_axis` in the item's basis, Godot's axes).
static func fastener_offsets(spec: Dictionary, s: float, root := "") -> Dictionary:
	var L := levels(spec, root)
	var glv: Dictionary = L[1]
	var D: int = L[2]
	var out := {}
	if D <= 0:
		return out
	for g in glv:
		var p := ease01(s * D - glv[g])
		var gr: Dictionary = spec.groups[g]
		var items: Array = []
		for t in gr.items:
			items.append(((t as Transform3D).basis * (gr.axis as Vector3)).normalized() * gr.back_out * p)
		out[g] = items
	return out
