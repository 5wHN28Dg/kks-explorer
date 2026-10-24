## For the interaction layer's tests: the app started as a trainee gets it, with the plant paused at step 0, and
## small helpers to find and press what is on screen.
extends RefCounted

const SimClock = preload("res://ui/sim_clock.gd")


static func start(tree: SceneTree) -> Node:
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	if main.ui != null and main.ui.clock != null:
		main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	return main


## The first visible button whose text is `text` (or begins with it, when `text` ends in "…").
static func find_button(n: Node, text: String) -> Button:
	var pre := text.ends_with("…")
	for c in n.get_children():
		if c is Button and c.is_visible_in_tree() and (c.text.begins_with(text.trim_suffix("…")) if pre else c.text == text):
			return c
		var f := find_button(c, text)
		if f:
			return f
	return null


## Every text shown under a node (labels, buttons, rich text), joined by newlines.
static func texts(n: Node) -> String:
	var out := PackedStringArray()
	_texts(n, out)
	return "\n".join(out)


static func _texts(n: Node, out: PackedStringArray) -> void:
	for c in n.get_children():
		if c is Label or c is Button:
			out.append(c.text)
		elif c is RichTextLabel:
			out.append(c.get_parsed_text())
		_texts(c, out)


static func op_row(card, kks: String, do: String, trip = null) -> Array:
	for row in card._ops:
		var o: Dictionary = row[0]
		if o["kks"] == kks and o["do"] == do and o.get("trip") == trip:
			return row
	return []


## Runs model steps until the value is true (at most `limit` steps); true when it came.
static func run_until(ui, value: String, limit := 20000) -> bool:
	var e = ui.clock.engine
	for i in limit:
		if e.truth(value):
			return true
		ui.clock.run_steps(1)
	return e.truth(value)


## Waits until a lock asked from the permit form has been checked (PLANT3D §15.6: on a worker thread): sent, or its
## warning shown. False when the check took longer than `seconds` of wall time (frames are no measure: headless, a
## slow machine's worker takes many more of them).
static func lock_checked(tree: SceneTree, pm, seconds := 120.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		pm.poll_check()
		if pm.check.is_empty() or pm.check["state"] == "warn":
			return true
		await tree.process_frame
	return false
