## Links into the app (docs/PLANT3D.md §6): a code opens its card and points at it; a component-level code opens
## the equipment it belongs to; a real plant's code opens the plant's equipment of the same kind, labelled as such;
## a procedure link opens that procedure at that step; anything else opens nothing and says so. The command line
## (how the desktop files hand a link over) is read for links; links out to Walkdown say why they can't open while
## Walkdown takes none.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const LinksIn = preload("res://ui/links_in.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var got := LinksIn.from_args(PackedStringArray(["--path", "x", "walkdown-plant://kks/30PAC10AP001", "--",
			"--quality=full", "walkdown-plant://procedure/cold_start", "https://example.org", "walkdown://course/x",
			"walkdown-plant://kks/" + "A".repeat(300)]))
	if got != ["walkdown-plant://kks/30PAC10AP001", "walkdown-plant://procedure/cold_start"]:
		p.append("links read from the command line: %s" % str(got))
	if not LinksIn.open_walkdown("course", "ppt/ccpp").contains("can't open links from other apps yet"):
		p.append("a link out to Walkdown, which takes none yet, does not say so")
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return p + ["the interaction layer did not start"]
	await tree.process_frame
	for c in [["walkdown-plant://kks/30PAC10AP001", "30PAC10AP001", ""],
			["walkdown-plant://kks/30PAC10AP001KP01", "30PAC10AP001", "belongs to"],
			["walkdown-plant://kks/11LAC10AP002", "10LAC10AP001", "11LAC10AP002 is not in this plant"],
			["walkdown-plant://kks/30PAC10AA101", "30PAC10AA101", ""]]:
		ui.close_card()
		ui.handle_link(c[0])
		if not ui.card.visible or ui.card.code != c[1]:
			p.append("%s opened %s, not the card of %s" % [c[0], ui.card.code if ui.card.visible else "nothing", c[1]])
		elif ui.pointer.code != c[1] or not ui.pointer.visible:
			p.append("%s does not point at %s in the plant" % [c[0], c[1]])
		elif c[2] != "" and not App.texts(ui.card).contains(c[2]):
			p.append("%s: the card does not say \"%s\"" % [c[0], c[2]])
	if not App.texts(ui.card).contains("System PAC10: Circulating water pumps"):
		p.append("the card does not decode the code in the plant's words: %s" % App.texts(ui.card).left(300))
	# a procedure link only offers it: the trainee chooses (a running procedure is not dropped by a link)
	ui.start_procedure("cw_path", null, false)
	ui.handle_link("walkdown-plant://procedure/cold_start/cw_a_start")
	if ui.tracker.proc["id"] != "cw_path" or not App.texts(ui.procedure.body).contains("This stops"):
		p.append("a procedure link replaced the running tour, or did not say it would")
	App.find_button(ui.procedure.body, "Follow it from here").pressed.emit()
	if ui.tracker == null or ui.tracker.current().get("id", "") != "cw_a_start" or not ui.procedure.visible:
		p.append("following the procedure link did not open the cold start at cw_a_start")
	ui.close_card()
	ui.handle_link("walkdown-plant://kks/../../etc")
	if ui.card.visible or not ui._toast.text.contains("not one Walkdown Plant opens"):
		p.append("a malformed link opened something or said nothing")
	main.free()
	return p
