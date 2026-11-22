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
	var pub: Label = rv.find_child("public_note", true, false)
	if pub == null or not pub.is_visible_in_tree() or not pub.text.contains("public"):
		p.append("no line beside the buttons says an issue is public")
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
	rv.what_box.text = "it froze, " + NAME + "\nthen the walker fell\nthird line"
	rv.inputs_cb.button_pressed = true
	shown = rv.text_box.text
	if not shown.contains("\"format\":\"walkdown-plant-inputs\""):
		p.append("ticked, the report lacks the run's inputs: %s" % shown.left(200))
	if rv.what_box.text != "it froze, " + NAME + "\nthen the walker fell\nthird line":
		p.append("ticking the box changed what the trainee wrote: %s" % rv.what_box.text)
	if rv.text_box.editable:
		p.append("the report itself can be edited (what is given would differ from what is shown)")
	# saved: as shown, redacted again (the trainee typed the name)
	var out := OS.get_user_data_dir().path_join("tests-report.txt")
	rv.write_to(out)
	var saved := FileAccess.get_file_as_string(out)
	if not saved.contains("it froze, [player name]\nthen the walker fell\nthird line") or saved.contains(NAME) \
			or saved.contains("<address> UTC") or not saved.contains("walkdown-plant-inputs"):
		p.append("the saved file is not the report as shown, redacted: %s" % saved.left(200))
	if not rv.note.visible or not rv.note.text.contains("tests-report.txt"):
		p.append("saving did not say where: %s" % rv.note.text)
	if rv.what_box.text != "" or FileAccess.file_exists(Report.DRAFT):
		p.append("once saved, what happened stays for the next report: %s" % rv.what_box.text.left(40))
	rv.what_box.text = "it froze, " + NAME + "\nthen the walker fell\nthird line"
	# the draft: kept as typed, read back by a new view (the app stopped and started again)
	rv._keep_draft()
	var again := Report.new()
	if again.what_box.text != rv.what_box.text:
		p.append("the draft of what happened is not read back after a restart: %s" % again.what_box.text.left(40))
	again.free()
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
	# the issue's button says when it copies (the report with 100 log lines and the inputs is too long for a link)
	var keep_what: String = rv.what_box.text
	rv.what_box.text = keep_what + " " + "long ".repeat(2000)
	rv.refresh()
	if rv._fits() or rv.issue_btn.text != "Copy and open a public issue":
		p.append("a report too long for a link: the button says %s" % rv.issue_btn.text)
	rv.what_box.text = keep_what
	rv.refresh()
	if rv._fits() != (rv.issue_btn.text == "Open a public issue"):
		p.append("the issue's button (%s) doesn't follow whether the report fits" % rv.issue_btn.text)
	rv.inputs_cb.button_pressed = false
	# keyboard and gamepad scroll the report (it never takes the focus)
	rv.text_box.scroll_vertical = 0
	var pd := InputEventKey.new()
	pd.pressed = true
	pd.keycode = KEY_PAGEDOWN
	pd.physical_keycode = KEY_PAGEDOWN
	tree.root.push_input(pd)
	await tree.process_frame
	if rv.text_box.scroll_vertical <= 0.0:
		p.append("Page Down did not scroll the report")
	var rs := InputEventJoypadButton.new()
	rs.pressed = true
	rs.button_index = JOY_BUTTON_LEFT_SHOULDER
	var at: float = rv.text_box.scroll_vertical
	tree.root.push_input(rs)
	await tree.process_frame
	if rv.text_box.scroll_vertical >= at:
		p.append("the gamepad's left shoulder did not scroll the report back")
	# a session code in the log, dashed or not, with no session open (it ended, or never started): left out
	var Code = load("res://net/code.gd")
	var c: String = Code.make()
	print("test: a link walkdown-plant://join/%s and %s and %s" % [c, Code.pretty(c), c.to_lower()])
	rv.refresh()
	if rv.text_box.text.contains(c) or rv.text_box.text.contains(Code.pretty(c)) or rv.text_box.text.contains(c.to_lower()):
		p.append("a session code in the log reaches the report")
	# a name the session saw once (a player who left) stays out after the session ends
	Report.remember("Layla Q", "[player name]")
	print("test: Layla Q left")
	rv.refresh()
	if rv.text_box.text.contains("Layla"):
		p.append("a player who left is named in the report")
	# a name's part never replaced inside a word (a player "Ali …" and the word "quality")
	Report.remember("Ali Hassan", "[player name]")
	rv.refresh()
	if not rv.text_box.text.contains("quality") or rv.text_box.text.contains("qu[player"):
		p.append("a name's part replaced inside a word: %s" % rv.text_box.text.substr(rv.text_box.text.find("Window"), 120))
	# a join link, even one with its code cut short, never logs the code
	ui.handle_link("walkdown-plant://join/QX7K2M9F2MHT4C7")
	await tree.process_frame
	if str(Report.keeper.last(20)).contains("QX7K2M9F2MHT4C7"):
		p.append("a join link's (bad) code was logged")
	# the session notes its code and players as it sees them (net/session.gd)
	var S = load("res://net/session.gd").new()
	S.code = Code.make()
	S.display_name = "Zainab Qx"
	S.roster = [{"name": "Yusuf Rk"}]
	S._note_secrets()
	var sc: String = S.code
	S.free()
	print("test: %s with Zainab Qx and Yusuf Rk" % sc)
	rv.refresh()
	for bad in [sc, "Zainab", "Yusuf"]:
		if rv.text_box.text.contains(bad):
			p.append("a session's %s, noted by the session, reaches the report" % bad)
	# Back: About again; opened again, what was written is still there, the box unticked
	rv.back.pressed.emit()
	await tree.process_frame
	if rv.visible or not main.hud.about.visible:
		p.append("Back did not return to About")
	main.hud.show_report()
	await tree.process_frame
	if not rv.what_box.text.begins_with("it froze") or rv.inputs_cb.button_pressed:
		p.append("opened again: what was written lost (%s) or the box ticked" % rv.what_box.text.left(40))
	# Escape: About again
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	tree.root.push_input(esc)
	await tree.process_frame
	if rv.visible or not main.hud.about.visible:
		p.append("Escape did not return to About")
	# the settings closed while the report shows: opened again, they are the settings (title, About, Close)
	main.hud.show_report()
	await tree.process_frame
	main.hud.show_settings(false)
	await tree.process_frame
	main.hud.show_settings(true)
	await tree.process_frame
	if not main.hud.settings_box.visible or not main.hud.about_btn.is_visible_in_tree() or rv.visible:
		p.append("after closing the settings from the report, they open empty")
	main.hud.show_settings(false)
	# a script error: said once where to report it
	var k := Report.Keep.new()
	k.on_script_error = Report._notice
	ui._toast.visible = false
	k._log_error("f", "res://x.gd", 1, "", "test: a fault", false, Logger.ERROR_TYPE_SCRIPT, [])
	await tree.process_frame
	if not ui._toast.visible or not ui._toast.text.contains("Report a problem"):
		p.append("a script error does not say where to report it: %s" % ui._toast.text)
	ui._toast.visible = false
	k._log_error("f", "res://x.gd", 2, "", "test: another fault", false, Logger.ERROR_TYPE_SCRIPT, [])
	await tree.process_frame
	if ui._toast.visible:
		p.append("a second script error said it again")
	if not str(k.last(5)).contains("SCRIPT ERROR: test: another fault"):
		p.append("the log keeps no script error: %s" % str(k.last(5)))
	# redaction: any case, never inside words put in, generic names left alone
	var r := Report.redact("C:\\Users\\SARA <b>ZED</b> سارة\\x Player one", [[NAME, "[player name]"], ["Player", "[player name]"]])
	if r.contains("SARA") or not r.contains("Player one"):
		p.append("redaction (case, generic words): %s" % r)
	# a session's code and players: left out too
	var in_session := Report.build(fake_main, false)
	for bad in [NAME, CODE, "Omar Q", "192.168.7.23"]:
		if in_session.contains(bad):
			p.append("in a session the report shows %s" % bad)
	for f in [fake, fake_ui, fake_main]:
		f.free()
	main.free()
	Report.switch_override = -1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Report.DRAFT))
	return p


static func _fake(src: String) -> Node:
	var sc := GDScript.new()
	sc.source_code = src
	sc.reload()
	var n := Node.new()
	n.set_script(sc)
	return n
