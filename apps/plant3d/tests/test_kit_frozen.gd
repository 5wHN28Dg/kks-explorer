## The plant's kit output stays as recorded (docs/plant3d/WORKSHOP.md §4.2, milestone K1a): every case of
## tests/fixtures/kit_plant.json (every part of the kit, with its defaults, the content's parameter sets and its
## limits, instruments standing every way) gives the same digest of everything the plant takes from Kit.make().
## The Workshop's component tags must never change what the plant draws. A change to the plant's shape that is meant
## records the digests again (tests/kit_frozen.gd) and then bakes the lightmap and runs the plant's Note 9 walk again.
extends RefCounted

const Frozen = preload("res://tests/kit_frozen.gd")
const Kit = preload("res://kit/kit.gd")

func run(_tree: SceneTree) -> Array:
	var problems: Array = []
	var text := FileAccess.get_file_as_string(Frozen.OUT)
	var d = JSON.parse_string(text)
	if not d is Dictionary or d.get("format", "") != Frozen.FORMAT or not d.get("cases") is Array:
		return ["%s is not a frozen kit file" % Frozen.OUT]
	var covered := {}
	var changed := {}
	for c in d.cases:
		covered[c.part] = true
		var got := Frozen.digest(c.part, c.params, c.ctx)
		if got != c.sha256:
			if not changed.has(c.part):
				changed[c.part] = 0
			changed[c.part] += 1
	for part in changed:
		problems.append("%s: the plant's geometry changed in %d case(s) (tests/fixtures/kit_plant.json; if meant, record it again with tests/kit_frozen.gd, bake the lightmap and run the plant's Note 9 walk: WORKSHOP.md §4.2)" % [part, changed[part]])
	for part in Frozen.parts():
		if not covered.has(part):
			problems.append("%s: no frozen case (a new part: record the digests again with tests/kit_frozen.gd)" % part)
	for pr in Kit.problems:
		problems.append("a generator's misuse of comp()/only(): " + pr)
	if d.cases.size() < 1000:
		problems.append("only %d frozen cases" % d.cases.size())
	Kit.clear_cache()
	print("kit frozen: %d cases of %d parts, %d changed" % [d.cases.size(), covered.size(), changed.size()])
	return problems
