## The water treatment plant's screens and desks (docs/PLANT3D.md §14 `desks`, WATER-TREATMENT.md §7):
## - the main control room's desks show the train's screens and the WTP's overview, not the WTP's own screens; a WTP
##   operation is not offered there, and its card says which desk works it;
## - the WTP's own desk (00CWD10, in its control room) shows the WTP's screens and not the train's; its mimic shows
##   the WTP's equipment, values and alarms;
## - an interlocked start is refused there with the content's sentences: the RO train without its chemical dosing,
##   then without its feed; and the plant's demin tank's low alarm reaches the train's own screens.
extends RefCounted

const App = preload("res://tests/ui_app.gd")


static func settle(tree: SceneTree, ui) -> void:
	for i in 600:
		if not ui.player.scripted:
			return
		await tree.process_frame


static func tabs(mim) -> PackedStringArray:
	var out := PackedStringArray()
	for b in mim._tab_btns:
		if (b as Button).visible:
			out.append(String((b as Button).name).trim_prefix("tab_"))
	return out


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	var sm = ui.screens
	# 1. the main control room
	ui.go_control_room(false)
	ui.open_screens("wtp_ro")
	var mim = ui.mimic
	if not ui.screens_open():
		main.free()
		return p + ["the screens did not open in the main control room"]
	var t := tabs(mim)
	for want in ["overview", "aux", "wtp"]:
		if not t.has(want):
			p.append("the main control room's screens have no %s tab: %s" % [want, ", ".join(t)])
	for not_here in ["wtp_pre", "wtp_filters", "wtp_ro", "wtp_demin", "wtp_waste"]:
		if t.has(not_here):
			p.append("the main control room shows the WTP's own screen %s" % not_here)
	if mim.current != -1:
		p.append("asking for a WTP screen in the main control room did not fall back to the overview (%d)" % mim.current)
	var tiles: Array = mim._layout_of(-1).cells.map(func(c): return c.id)
	if tiles.has("screen:%d" % sm.screen_index("wtp_ro")) or not tiles.has("screen:%d" % sm.screen_index("wtp")):
		p.append("the overview's tiles are not this desk's screens: %s" % str(tiles))
	if ui.screen_reach("00GCB21AT001") or not ui.screen_reach("00GHC10BB001") or not ui.screen_reach("00GCF11CQ001"):
		p.append("the main control room reaches the RO's operations, or misses the plant's demin tank or the WTP overview")
	ui.open_card("00GCB21AT001")
	var row := App.op_row(ui.card, "00GCB21AT001", "start")
	if row.is_empty() or not (row[1] as Button).disabled \
			or not (row[5] as Label).text.contains("Water treatment plant control desk"):
		p.append("the RO's start is offered in the main control room, or its card does not say which desk works it: %s"
				% ("" if row.is_empty() else (row[5] as Label).text))
	ui.close_card()
	ui.close_screens()
	# 2. the WTP's own desk
	ui.restart("wtp_cold", true)
	ui.fly_to("00CWD10")
	await settle(tree, ui)
	if not ui.at_desk() or ui.in_control_room():
		main.free()
		return p + ["Go there did not put the trainee at the WTP's desk (%.1f m from it)" % ui.distance_to("00CWD10")]
	ui.open_card("00CWD10")              # the desk opens its screens
	if not ui.screens_open():
		main.free()
		return p + ["the WTP's desk did not open its screens"]
	t = tabs(mim)
	for want in ["wtp", "wtp_pre", "wtp_filters", "wtp_ro", "wtp_demin", "wtp_waste"]:
		if not t.has(want):
			p.append("the WTP's desk has no %s tab: %s" % [want, ", ".join(t)])
	for not_here in ["overview", "gt", "aux", "el"]:
		if t.has(not_here):
			p.append("the WTP's desk shows the train's screen %s" % not_here)
	if mim.current != sm.screen_index("wtp"):
		p.append("the WTP's desk did not open at the WTP's overview (%d)" % mim.current)
	mim.show_screen(sm.screen_index("wtp_ro"))
	await tree.process_frame
	for code in ["00GCB21AT001", "00GCB21CP002", "00GCB21CQ002", "00GCN10AP001", "00GCB11CP001"]:
		if mim.target_rect(code).size == Vector2.ZERO:
			p.append("%s is not drawn on the WTP's RO screen" % code)
	# 3. refusals at the WTP's desk: the RO without its feed and chemicals, then without its chemicals
	var e = ui.clock.engine
	ui.open_card("00GCB21AT001")
	row = App.op_row(ui.card, "00GCB21AT001", "start")
	if row.is_empty() or (row[1] as Button).disabled:
		main.free()
		return p + ["the RO's start is not offered at the WTP's desk"]
	ui.clock.run_steps(1)                # the scenario stops RO A at its first step
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	var txt: String = ui.op_result(row[0]).get("text", "")
	if not (txt.begins_with("Refused: Suction pressure below 1.5 bar") and txt.contains("Sodium bisulphite dosing not running")):
		p.append("the RO start without feed came back: %s" % txt)
	e.op("00GHA10AP001", "start")         # service water: the RO's feed
	ui.clock.run_steps(1)
	if not App.run_until(ui, "sw_p_ok", 600):
		p.append("the service water pump did not make pressure")
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	txt = ui.op_result(row[0]).get("text", "")
	if not txt.begins_with("Refused: Sodium bisulphite dosing not running: chlorine would reach the membranes"):
		p.append("the RO start without chemicals came back: %s" % txt)
	ui.card.refresh()
	if not (row[2] as Label).text.contains("✗ Antiscalant dosing not running"):
		p.append("the card does not list the failing permissives: %s" % (row[2] as Label).text)
	if e.v("ro_a_state") != 0.0:
		p.append("the refused RO moved: state %s" % e.v("ro_a_state"))
	ui.close_card()
	ui.close_screens()
	# 4. the plant's demin tank low: its alarm on the train's auxiliaries screen
	ui.restart("cold_iron", true)
	e = ui.clock.engine
	e.op("00GHC10AP001", "stop")
	e.fault("dm_drain")
	if not App.run_until(ui, "dm_l", 30000):
		p.append("the plant's demin tank did not fall below its low level")
	ui.clock.run_steps(60)
	var k := -1
	for i in ui.model.alarms.size():
		if ui.model.alarms[i]["id"] == "dm_low":
			k = i
	if k < 0 or e.astate[k] != "active_unack":
		p.append("the plant's demin tank low alarm is not raised")
	elif sm.screen_of.get("00GHC10BB001", [-1])[0] != sm.screen_index("aux"):
		p.append("the plant's demin tank is not on the train's auxiliaries screen")
	main.free()
	return p
