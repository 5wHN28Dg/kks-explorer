## A hoist's pendant in its card (docs/PLANT3D.md §20.5, §20.7): a row per pendant record of the hoist's part
## (`pendant`: the code it works and its two buttons' words). A motion's buttons are hold-to-run: pressed (touch,
## mouse, or a gamepad's or keyboard's accept on the focused button) they send its `set` op with 1 or -1, released
## they send 0; a motion is also let go when its button can no longer be worked (out of reach, the card closed or
## rebuilt, the app going to the background or losing the focus), so a motion never runs on unattended; a saved run
## continued lets go of every motion it was saved with (`stop_all`). The motions are worked within reach of the
## pendant (a node named `pendant` under the hoist's: on the bridge for a crane, it moves with it) or, for a crane
## with a radio remote, within REMOTE_REACH of its hook with the hook, the load or the trolley in sight (nothing solid
## between the trainee's eyes and it, as for a desk's screens); the hook's latch (a row whose code has `open` and
## `close` ops) at the hook itself, within reach of the latch's own code, which rides on it.
extends VBoxContainer

const W = preload("res://ui/widgets.gd")
const REMOTE_REACH := 30.0      # metres from the hook: the radio remote's range, the load in sight

var ui                          # ui/plant_ui.gd
var code := ""
var rows: Array = []            # [record, hold?, minus button, plus button, state label, feedback label, minus op, plus op]
var held := {}                  # row -> the direction held (-1 or 1)
var _remote := false
var _where: Label
var _cells: Array = []          # [label, value name]: the load cells' readings


static func is_hoist(info, c: String) -> bool:
	return info.part_of(c) in ["monorail_hoist", "overhead_crane"]


## The hoist whose pendant works this code ("" when none).
static func hoist_of(info, c: String) -> String:
	var h: String = info.parent_of.get(c, "")
	if h == "" or not is_hoist(info, h):
		return ""
	for r in info.params_of(h).get("pendant", []):
		if r.get("code", "") == c:
			return h
	return ""


## A `set` op of -1 to 1: a hold-to-run motion (PLANT3D §20.5).
static func hold_to_run(o: Dictionary) -> bool:
	return o.get("do", "") == "set" and o.get("range", []) == [-1, 1]


func setup(u, c: String) -> void:
	ui = u
	code = c
	var info = ui.info
	var pr: Dictionary = info.params_of(c)
	_remote = bool(pr.get("remote", false))
	add_child(W.label("Pendant" + (" and radio remote" if _remote else ""), 22))
	_where = W.label("", 16, W.DIM)
	add_child(_where)
	for rec in pr.get("pendant", []):
		var rc: String = rec.get("code", "")
		var ops: Array = info.ops_of.get(rc, [])
		var hold := ops.filter(func(o): return hold_to_run(o))
		var mo = null
		var po = null
		if not hold.is_empty():
			mo = hold[0]
			po = hold[0]
		else:
			for o in ops:
				if o["do"] == "open":
					mo = o
				elif o["do"] == "close":
					po = o
		var box := VBoxContainer.new()
		add_child(box)
		var line := HBoxContainer.new()
		box.add_child(line)
		var nm: String = info.name_of(rc)
		var st := W.label("", 17, Color.WHITE)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(st)
		var i := rows.size()
		var mb := W.button(String(rec.get("minus", "-")), func(): pass, 120)
		var pb := W.button(String(rec.get("plus", "+")), func(): pass, 120)
		mb.name = "%s_minus" % rc
		pb.name = "%s_plus" % rc
		if not hold.is_empty():
			mb.button_down.connect(press.bind(i, -1))
			mb.button_up.connect(release.bind(i))
			pb.button_down.connect(press.bind(i, 1))
			pb.button_up.connect(release.bind(i))
		else:
			mb.pressed.connect(tap.bind(i, -1))
			pb.pressed.connect(tap.bind(i, 1))
		line.add_child(mb)
		line.add_child(pb)
		var fb := W.label("", 16, W.DIM)
		box.add_child(fb)
		rows.append([rec, not hold.is_empty(), mb, pb, st, fb, mo, po, nm])
	for p in info.parts_of.get(c, []):
		if ui.info.params_of(p).get("kind", "") == "load_cell":
			for vn in info.values_of.get(p, []):
				var l := W.label("", 17, Color.WHITE)
				add_child(l)
				_cells.append([l, vn, info.name_of(p)])
	tree_exiting.connect(release_all)
	refresh()


## Where the trainee can work the motions from: "pendant", "remote" or "".
func reach() -> String:
	var host: Node3D = ui.index.nodes.get(code)
	if host == null or ui.player == null:
		return ""
	var me: Vector3 = ui.player.global_position + Vector3.UP
	var pend := host.find_child("pendant", true, false) as Node3D
	if pend != null and pend.global_position.distance_to(me) <= ui.REACH:
		return "pendant"
	var hook := host.find_child("hook", true, false) as Node3D
	if _remote and hook != null and hook.global_position.distance_to(me) <= REMOTE_REACH and in_sight(host):
		return "remote"
	return ""


## The radio remote's operator sees what they move: the hook, the load or the trolley, with nothing solid between
## their eyes and it (a wall, a floor).
func in_sight(host: Node3D) -> bool:
	var eye: Vector3 = ui.eye()
	var space: PhysicsDirectSpaceState3D = ui.player.get_world_3d().direct_space_state
	for nm in ["hook", "load_z", "trolley"]:
		var n := host.find_child(nm, true, false) as Node3D
		if n == null:
			continue
		var to: Vector3 = n.global_position + (Vector3.UP * 0.3 if nm == "load_z" else Vector3.ZERO)
		var q := PhysicsRayQueryParameters3D.create(eye, to)
		q.exclude = [ui.player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 0.5:
			return true
	return false


func offered(i: int) -> bool:
	if not is_visible_in_tree():
		return false
	var r: Array = rows[i]
	if r[1]:
		return reach() != ""
	return ui.near(String(r[0].get("code", "")))


func press(i: int, dir: int) -> void:
	if not offered(i) or rows[i][6] == null:
		return
	held[i] = dir
	ui.do_op(rows[i][6], dir)
	refresh()


func release(i: int) -> void:
	if not held.has(i):
		return
	held.erase(i)
	ui.do_op(rows[i][6], 0, "local")        # let go where it was held (from the control room too, after a jump)
	refresh()


func release_all() -> void:
	for i in held.keys():
		release(i)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		release_all()                   # the app left: no hand on the button any more


## Lets go of every hold-to-run motion whose command is not 0 (a saved run continued: no button is held now). The
## motion stops as if let go the moment the run was saved (it takes one step more, as any let-go).
static func stop_all(u) -> void:
	var e = u.clock.engine
	for o in e.m.op_keys.values():
		if hold_to_run(o) and e.ix.has(String(o.get("input", ""))) and e.v(o["input"]) != 0.0:
			u.do_op(o, 0, "local")


func tap(i: int, dir: int) -> void:
	var o = rows[i][6] if dir < 0 else rows[i][7]
	if o == null or not offered(i):
		return
	ui.do_op(o, null)
	refresh()


func refresh() -> void:
	if ui == null:
		return
	var e = ui.clock.engine
	var info = ui.info
	var rch := reach()
	_where.text = {"pendant": "At the pendant: hold a button to run that motion", "remote": "By the radio remote: hold a button to run that motion",
			"": "Out of reach: walk up to the pendant" + (" or within %d m of the hook (the radio remote)" % REMOTE_REACH if _remote else "")}[rch]
	for i in rows.size():
		var r: Array = rows[i]
		var rc: String = r[0].get("code", "")
		var ok := offered(i)
		if not ok and held.has(i):
			release(i)                  # out of reach or hidden while held: the motion stops
		(r[2] as Button).disabled = not ok
		(r[3] as Button).disabled = not ok
		var txt: String = r[8]
		if r[1]:
			for vn in info.values_of.get(rc, []):
				txt += ": " + info.fmt(vn, e.v(vn))
				break
		else:
			var close = r[7]
			if close != null and close.has("set"):
				txt += ": " + ("closed, hooked on" if e.truth(close["set"].keys()[0]) else "open")
			if not ok:
				txt += " (at the hook only)"
		(r[4] as Label).text = txt
		var res: Dictionary = {}
		for o in [r[6], r[7]]:
			if o != null and not ui.op_result(o).is_empty() and ui.op_result(o).get("state", "") != "done":
				res = ui.op_result(o)
		(r[5] as Label).text = res.get("text", "")
		(r[5] as Label).add_theme_color_override("font_color", W.BAD_COLOUR if res.get("state", "") == "refused" else W.DIM)
	for c in _cells:
		(c[0] as Label).text = "%s: %s" % [c[2], info.fmt(c[1], e.v(c[1]))]
