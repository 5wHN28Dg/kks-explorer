## The water treatment plant's faults (docs/plant3d/WATER-TREATMENT.md §7, milestone W3) and its screens' links:
## - a screens link (`screens:wtp_ro`) asked in the main control room takes the trainee to the WTP's own desk 00CWD10,
##   whose screens open at that screen (its desks, PLANT3D §14); the overview's link stays in the main control room;
## - faults applied from the instructor's panel (the degasser blower's motor, a resin leak in mixed bed A, a clarifier
##   upset) are seen at the WTP's desk: the blower marked tripped and its alarms on the RO screen, the strainer's alarm
##   on the demin screen, the clarified turbidity's on the WTP's overview, each screen's tab with its count;
## - the resin leak is repaired only by its work under a permit, not at the equipment: the bed's card offers no repair.
extends RefCounted

const App = preload("res://tests/ui_app.gd")


static func settle(tree: SceneTree, ui) -> void:
	for i in 600:
		if not ui.player.scripted:
			return
		await tree.process_frame


static func _row(panel, text: String) -> HBoxContainer:
	for r in panel.body.get_children():
		if r is HBoxContainer and App.texts(r).contains(text):
			return r
	return null


static func _button(row: Node) -> Button:
	for c in row.get_children():
		if c is Button:
			return c
	return null


static func _alarm(ui, id: String) -> int:
	for i in ui.model.alarms.size():
		if ui.model.alarms[i]["id"] == id:
			return i
	return -1


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	var sm = ui.screens
	var mim = ui.mimic
	ui.restart("wtp_normal", true)
	var e = ui.clock.engine
	# 1. the screens' links: a WTP screen from the main control room is opened at the WTP's desk
	ui.go_control_room(false)
	ui.open_panel("screens:wtp_ro")
	await settle(tree, ui)
	if not ui.screens_open() or mim.current != sm.screen_index("wtp_ro"):
		p.append("screens:wtp_ro from the main control room did not open the RO screen (open %s, screen %d)"
				% [ui.screens_open(), mim.current])
	if ui.in_control_room() or not ui.desks_here().has("00CWD10"):
		p.append("screens:wtp_ro did not take the trainee to the WTP's desk (%.1f m from it)" % ui.distance_to("00CWD10"))
	ui.close_screens()
	ui.open_panel("screens")             # no screen named, at the WTP's desk: its own screens, the trainee stays
	await settle(tree, ui)
	if ui.in_control_room() or not ui.desks_here().has("00CWD10") or not ui.screens_open():
		p.append("screens (none named) at the WTP's desk did not open there")
	ui.close_screens()
	ui.open_panel("screens:aux")         # the train's screen from the WTP's desk: back to the main control room
	await settle(tree, ui)
	if not ui.in_control_room() or not ui.screens_open() or mim.current != sm.screen_index("aux"):
		p.append("screens:aux from the WTP's desk did not open the auxiliaries' screen in the main control room")
	ui.close_screens()
	# 2. faults from the instructor's panel
	ui.set_instructor(true)
	ui.toggle_trainer()
	for text in ["Degasser blower motor overload", "Mixed bed A: a broken underdrain lateral",
			"Clarifier A: its rake drive stalls"]:
		var row := _row(ui.trainer, text)
		if row == null or _button(row).text != "Apply":
			p.append("the instructor's panel has no Apply for \"%s\"" % text)
			continue
		_button(row).pressed.emit()
		ui.clock.run_steps(1)
		ui.trainer.refresh()
	ui.toggle_trainer()
	ui.clock.run_steps(4000)            # the lags: the strainer (τ 300 s) and the clarifiers (τ 600 s)
	# 3. seen at the WTP's desk
	ui.open_panel("screens:wtp_ro")
	await settle(tree, ui)
	if not ui.screens_open():
		main.free()
		return p + ["the WTP's screens did not open at its desk"]
	var want := {"wtp_ro": ["dg_tripped", "dg_co2_h"], "wtp_demin": ["mb_a_dp_h"], "wtp": ["cla_ntu_h"]}
	for sid in want:
		var si: int = sm.screen_index(sid)
		mim.show_screen(si)
		await tree.process_frame
		var a: Dictionary = sm.screen_alarms(si, e)
		for id in want[sid]:
			var k := _alarm(ui, id)
			if k < 0 or not a.alarms.has(k):
				p.append("%s is not on the %s screen (its alarms there: %s)" % [id, sid, str(a.alarms)])
		var tab: Button = mim._tab_btns[si + 1]
		if not tab.text.ends_with(str(a.by[0] + a.by[1] + a.by[2])) or a.by[0] + a.by[1] + a.by[2] == 0:
			p.append("the %s tab does not carry its alarms' count: \"%s\"" % [sid, tab.text])
	var blower: Dictionary = sm.items.get("00GCH10AN001", {})
	if blower.is_empty() or sm.tripped(blower, e) < 0:
		p.append("the degasser blower is not marked tripped on its screen")
	mim.show_screen(sm.screen_index("wtp_ro"))
	await tree.process_frame
	if mim.target_rect("00GCH10CQ001").size == Vector2.ZERO:
		p.append("the degassed water's carbon dioxide is not drawn on the RO screen")
	ui.close_screens()
	# 4. the resin leak: no repair at the bed (its work under a permit repairs it)
	ui.open_card("00GCF11AT001")
	if ui.card._repairs.any(func(rp): return String(rp[0]["id"]) == "mb_a_resin") \
			or not ui.card._repairs.any(func(rp): return String(rp[0]["id"]) == "mb_a_early"):
		p.append("mixed bed A's card offers a repair of the resin leak (only its work under a permit repairs it), or "
				+ "not its other fault's")
	ui.close_card()
	main.free()
	return p
