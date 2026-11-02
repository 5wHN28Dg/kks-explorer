## A part kind made for the tests only (docs/plant3d/WORKSHOP.md §9): it is no kit part, has no code in kit/kit.gd and
## comes in through `Kit.register`, with its Workshop data beside it (workshop_gadget.json). tests/test_workshop.gd
## builds and loads its Workshop scene, as the builder does for the app's kinds: a kind needs no Workshop code.
extends RefCounted

static func test_gadget(_part: String, g) -> void:
	var m = g.m
	g.comp("base", {"explode": [Vector3(0, 0, -1), 0.1]})
	m.use("paint_grey", "form")
	m.box(Vector3(0, 0, 0.05), Vector3(0.2, 0.2, 0.1))
	g.comp("core", {"parent": "base"})
	g.only("workshop")
	m.use("paint_green", "identify")
	m.box(Vector3(0, 0, 0.05), Vector3(0.05, 0.05, 0.05))   # hidden inside the base
	g.only()
	g.comp("lid", {"explode": [Vector3(0, 0, 1), 0.1], "sym": [Vector3(0, 0, 1), 4]})
	m.use("paint_red", "identify")
	m.box(Vector3(0, 0, 0.11), Vector3(0.2, 0.2, 0.02))
	var screw := func(b) -> void:
		b.use("steel", "detail", 0.005)
		b.cyl(Vector3.ZERO, Vector3(0, 0, 0.004), 0.004, -1.0, 6)
		b.cyl(Vector3(0, 0, -0.01), Vector3.ZERO, 0.002, -1.0, 6)
	var items: Array = []
	for x: float in [-0.08, 0.08]:
		items.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.08, 0.12)))
	g.fasteners("lid_screws", "screw", items, screw)
