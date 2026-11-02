## A generator that misuses the Workshop's tags (tests/test_workshop.gd): a shared piece drawn after a Workshop-only
## block without a use() first, and a fastener group of a kind WORKSHOP.md §4.4 doesn't know. Both must be reported.
extends RefCounted

static func test_misuse(_part: String, g) -> void:
	var m = g.m
	g.comp("base")
	m.use("paint_grey", "form")
	m.box(Vector3(0, 0, 0.05), Vector3(0.2, 0.2, 0.1))
	g.only("workshop")
	m.use("chrome", "identify")
	m.box(Vector3(0, 0, 0.05), Vector3(0.05, 0.05, 0.05))
	g.only()
	m.box(Vector3(0, 0, 0.2), Vector3(0.1, 0.1, 0.1))   # no use() first: the plant would lose it
	var dot := func(b) -> void:
		b.use("steel", "detail", 0.005)
		b.box(Vector3.ZERO, Vector3(0.004, 0.004, 0.004))
	g.fasteners("rivets", "rivet", [Transform3D.IDENTITY], dot)
