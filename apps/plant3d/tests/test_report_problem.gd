## "Report a problem" (issue #446, app/report.gd), switched on for the test:
## - About has "Report a problem"; it shows the whole report in place of About: the version and commit, the platform,
##   the renderer, the scenario, the app's last log lines; Back returns to About;
## - nothing personal: the player's saved name, a session's code and players, network addresses and the app's data
##   folder logged are left out, also from what is saved, copied or put in an issue's link;
## - the run's inputs only when the box is ticked (never ticked at the start);
## - saved to a file: the file holds the report as shown, with what the trainee wrote at its top; a folder that can't
##   be written is said;
## - an issue's link carries the report, or, when too long, says it was copied;
## - a script error says once where to report it;
## - switched off: no button, no view, no log kept (the app as before).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Report = preload("res://app/report.gd")

const NAME := "Sara <b>Zed</b> سارة"
const CODE := "QX7-K2M"


func run(tree: SceneTree) -> Array:
	var p: Array = []
	# switched off: nothing
	Report.switch_override = 0
	var main := App.start(tree)
	await tree.process_frame
	if main.hud.report != null or main.hud.report_btn != null:
		p.append("switched off, About has Report a problem")
	main.free()
	Report.switch_override = 1
	main = App.start(tree)
	await tree.process_frame
	var ui = main.ui
	if Report.keeper == null:
		main.free()
		Report.switch_override = -1
		return p + ["switched on, no log is kept"]
	main.cf.set_value("multiplayer", "name", NAME)
	# a session's code and players, as a session holds them, in a stand-in for the app (main, its layer, the session)
	var fake := _fake("extends Node\nvar display_name := \"%s\"\nvar code := \"%s\"\nvar roster := [{\"name\": \"Omar Q\"}]\n" % [NAME, CODE])
	var fake_ui := _fake("extends Node\nvar session\n")
	fake_ui.session = fake
	var fake_main := _fake("extends Node\nvar cf\nvar ui\nvar tier := \"full\"\n")
	fake_main.cf = main.cf
	fake_main.ui = fake_ui
	print("test: joined %s's session %s from 192.168.7.23 and fe80::1c2b:3a4d:5e6f:7a8b; saved in %s" \
			% [NAME, CODE, OS.get_user_data_dir()])
	print("test: Omar Q joined")
	push_warning("test: a warning to keep")
	# About → Report a problem
	main.hud.show_about()
	await tree.process_frame
	var rb: Button = main.hud.report_btn
	if rb == null or not rb.is_visible_in_tree():
		p.append("About has no Report a problem")
	else:
		rb.pressed.emit()
	await tree.process_frame
	var rv = main.hud.report
	if rv == null or not rv.visible or main.hud.about.visible:
		for f in [fake, fake_ui, fake_main]:
			f.free()
		main.free()
		Report.switch_override = -1
		return p + ["Report a problem did not show the report in About's place"]
	var shown: String = rv.text_box.text
	var v: String = ProjectSettings.get_setting("application/config/version", "")
	for t in ["Walkdown Plant " + v, "Platform: " + OS.get_name(), "Renderer: ", "Scenario: " + ui.clock.scenario,
			"last ", "a warning to keep", "test: joined"]:
		if not shown.contains(t):
			p.append("the report lacks %s" % t)
	for bad in [NAME, "Sara", "192.168.7.23", "fe80::1c2b", OS.get_user_data_dir()]:
		if shown.contains(bad):
			p.append("the report shows %s" % bad)
	if not shown.contains("[player name]") or not shown.contains("<address>"):
		p.append("the report doesn't say what was left out: %s" % shown.substr(shown.find("test: joined"), 160))
	# the inputs: not ticked at the start; ticked, in the report
	if rv.inputs_cb.button_pressed or shown.contains("walkdown-plant-inputs"):
		p.append("the run's inputs are in the report without the box ticked")
	rv.text_box.text = rv.text_box.text.replace("What happened (write it here): ", "What happened (write it here): it froze, " + NAME)
	rv.inputs_cb.button_pressed = true
	shown = rv.text_box.text
	if not shown.contains("\"format\":\"walkdown-plant-inputs\"") or not shown.contains("it froze"):
		p.append("ticked, the report lacks the run's inputs or lost what was written: %s" % shown.left(200))
	# saved: as shown, redacted again (the trainee typed the name)
	var out := OS.get_user_data_dir().path_join("tests-report.txt")
	rv.write_to(out)
	var saved := FileAccess.get_file_as_string(out)
	if not saved.contains("it froze, [player name]") or saved.contains(NAME) or saved.contains("<address> UTC"):
		p.append("the saved file is not the report as shown, redacted: %s" % saved.left(200))
	if not rv.note.visible or not rv.note.text.contains("tests-report.txt"):
		p.append("saving did not say where: %s" % rv.note.text)
	DirAccess.remove_absolute(out)
	rv.write_to(OS.get_user_data_dir().path_join("no-such-folder/x/report.txt"))
	if not rv.note.text.contains("could not be saved"):
		p.append("a folder that can't be written was not said: %s" % rv.note.text)
	# the issue's link: the report in it, or a note to paste it
	var short_url := Report.issue_url("short report")
	if not short_url.begins_with(Report.ISSUES) or not short_url.contains("short%20report"):
		p.append("the issue's link does not carry a short report: %s" % short_url)
	var long_url := Report.issue_url("x".repeat(20000))
	if long_url.length() > Report.URL_MAX or not long_url.contains("copied"):
		p.append("a long report's link is %d long or doesn't say it was copied" % long_url.length())
	# Back: About again
	rv.back.pressed.emit()
	await tree.process_frame
	if rv.visible or not main.hud.about.visible:
		p.append("Back did not return to About")
	# a script error: said once where to report it
	ui._toast.visible = false
	Report._notice()
	if not ui._toast.visible or not ui._toast.text.contains("Report a problem"):
		p.append("a script error does not say where to report it: %s" % ui._toast.text)
	# a session's code and players: left out too
	var in_session := Report.build(fake_main, false)
	for bad in [NAME, CODE, "Omar Q", "192.168.7.23"]:
		if in_session.contains(bad):
			p.append("in a session the report shows %s" % bad)
	for f in [fake, fake_ui, fake_main]:
		f.free()
	main.free()
	Report.switch_override = -1
	return p


static func _fake(src: String) -> Node:
	var sc := GDScript.new()
	sc.source_code = src
	sc.reload()
	var n := Node.new()
	n.set_script(sc)
	return n
