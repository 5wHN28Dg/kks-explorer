## "Report a problem" (issue #446; the user's UI-UX policy FIELD1): Settings → About → Report a problem shows the report
## the app would give, in full, before anything leaves the device: the app's version and commit, the platform and
## device, the renderer and graphics adapter, the quality tier and UI size, the scenario and plant time, and the last
## lines the app logged. The run's inputs (what was done in it, enough to replay it) only when the trainee ticks the
## box. Player names, session codes, network addresses and the user's folders are left out (redact()). Nothing is sent
## by itself: the trainee saves it to a file (every platform, the system's own file dialog), shares it (Android's share
## sheet), copies it, or opens a public issue on the project's tracker with it filled in (a browser, their own act).
## Walkdown's diagnostics reports carry the same parts (app, version, platform, model, the events with their
## times); Plant has no manager to seal them to, so it shows them and lets the trainee choose.
## After a script error (a fault in the app's own code), the app says once a session where to report it.
## Switched off until the owner's check (UI-UX policy 8.5, tier 2): the project setting walkdown/report_problem.
extends VBoxContainer

signal closed

const W = preload("res://ui/widgets.gd")
const About = preload("res://app/about.gd")
const RunSave = preload("res://ui/run_save.gd")

const ISSUES := "https://github.com/5wHN28Dg/kks-explorer/issues/new"
const KEEP_LINES := 200         # log lines kept
const SHOWN_LINES := 100        # of them in a report
const LINE_MAX := 300           # characters of a line kept
const URL_MAX := 6000           # a prefilled issue's link at most this long (browsers and GitHub refuse longer)
const REPORT_MAX := 1024 * 1024 # characters: a run's inputs beyond this are left out (said so)

## tests: -1 the project setting, 0 off, 1 on
static var switch_override := -1
static func switched_on() -> bool:
	return switch_override == 1 if switch_override >= 0 else bool(ProjectSettings.get_setting("walkdown/report_problem", false))


## The app's last log lines (messages, warnings, errors), kept in memory only. Godot may call it from any thread.
class Keep extends Logger:
	var lines: Array = []
	var mutex := Mutex.new()
	var script_errors := 0
	var on_script_error := Callable()   # called (deferred) at the first script error of a session

	func _add(s: String) -> void:
		var t := Time.get_datetime_string_from_system(false, true).substr(11)
		mutex.lock()
		lines.append("%s %s" % [t, s.strip_edges().left(LINE_MAX)])
		while lines.size() > KEEP_LINES:
			lines.pop_front()
		mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		if message.strip_edges() != "":
			_add(("stderr: " if error else "") + message)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		_add("%s: %s (%s:%d %s)" % [kind, rationale if rationale != "" else code, file.get_file(), line, function])
		if error_type == ERROR_TYPE_SCRIPT:
			script_errors += 1
			if script_errors == 1 and on_script_error.is_valid():
				on_script_error.call_deferred()

	func last(n: int) -> Array:
		mutex.lock()
		var out := lines.slice(maxi(0, lines.size() - n))
		mutex.unlock()
		return out


static var keeper: Keep = null
static var _notice_to: WeakRef = null   # the app (app/main.gd) whose layer says where to report a script error

## Starts keeping the log (once a process; only while switched on); `main` says where to report the first script
## error of the session.
static func start_keeping(main) -> void:
	if not switched_on():
		return
	if keeper == null:
		keeper = Keep.new()
		keeper.on_script_error = _notice
		OS.add_logger(keeper)
	_notice_to = weakref(main)


static func _notice() -> void:
	var m = _notice_to.get_ref() if _notice_to != null else null
	if m != null and m.get("ui") != null:
		m.ui.toast("Something went wrong inside the app. To tell its makers what happened: Settings, About, Report "
				+ "a problem.", 10.0)


# ------------------------------------------------------------------ the report's text

## What must never leave in a report: the player names this device knows (its own saved one, a session's players),
## the session code. Each with the words put in its place.
static func secrets_of(main) -> Array:
	var out: Array = []
	var cf = main.get("cf") if main != null else null
	if cf is ConfigFile:
		out.append([str(cf.get_value("multiplayer", "name", "")), "[player name]"])
	var ui = main.get("ui") if main != null else null
	var s = ui.get("session") if ui != null else null
	if s != null:
		out.append([str(s.get("display_name")), "[player name]"])
		out.append([str(s.get("code")), "[session code]"])
		for r in s.get("roster") if s.get("roster") is Array else []:
			if r is Dictionary:
				out.append([str(r.get("name", "")), "[player name]"])
	return out


## The text with the secrets, the user's folders and name, and network addresses replaced.
static func redact(text: String, secrets: Array) -> String:
	var pairs: Array = secrets.duplicate()
	pairs.append([OS.get_user_data_dir(), "<app data>"])
	pairs.append([ProjectSettings.globalize_path("user://"), "<app data>/"])
	pairs.append([OS.get_environment("HOME"), "~"])
	pairs.append([OS.get_environment("USERPROFILE"), "~"])
	for v in ["USER", "USERNAME", "LOGNAME"]:
		pairs.append([OS.get_environment(v), "[user]"])
	# the longest first: a name inside another one is never left half replaced
	pairs = pairs.filter(func(p): return String(p[0]).strip_edges().length() >= 2)
	pairs.sort_custom(func(a, b): return String(a[0]).length() > String(b[0]).length())
	for p in pairs:
		text = text.replace(String(p[0]).strip_edges(), p[1])
	var re := RegEx.new()
	re.compile("\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b")                                  # IPv4
	text = re.sub(text, "<address>", true)
	# IPv6: eight groups, or fewer with "::" (never a time of day such as 07:40:12)
	re.compile("\\b(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}\\b")
	text = re.sub(text, "<address>", true)
	re.compile("(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{1,4}:)*[0-9A-Fa-f]{0,4}::(?:[0-9A-Fa-f]{1,4}:)*[0-9A-Fa-f]{1,4}\\b")
	text = re.sub(text, "<address>", true)
	return text


## The report, as shown and given. `with_inputs`: the run's inputs too.
static func build(main, with_inputs: bool) -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	var b := About.build_info()
	var L := PackedStringArray()
	L.append("Walkdown Plant problem report")
	L.append("Made: %s" % Time.get_datetime_string_from_system(true, true) + " UTC")
	L.append("")
	L.append("What happened (write it here): ")
	L.append("")
	L.append("App: Walkdown Plant %s, commit %s%s" % [v, b.commit if b.commit != "" else "unknown",
			" with local changes" if b.changes else ""])
	L.append("Platform: %s %s (%s)" % [OS.get_name(), OS.get_version(), Engine.get_architecture_name()])
	L.append("Device: %s" % OS.get_model_name())
	L.append("Processor: %s, %d threads; memory %d MB" % [OS.get_processor_name(), OS.get_processor_count(),
			int(OS.get_memory_info().get("physical", 0) / 1048576)])
	var method: String = str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	L.append("Renderer: %s, %s %s (%s)" % [method, RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	var win := DisplayServer.window_get_size()
	L.append("Window: %d x %d, screen scale %.2f; UI size %d %%; quality %s" % [win.x, win.y,
			DisplayServer.screen_get_scale(), roundi(W.ui_size * 100.0), str(main.get("tier")) if main != null else "?"])
	L.append("Godot: %s" % str(Engine.get_version_info().get("string", "")))
	var ui = main.get("ui") if main != null else null
	if ui != null and ui.get("clock") != null and ui.clock.engine != null:
		L.append("Scenario: %s, plant time %s, %d inputs so far%s" % [ui.clock.scenario, W.model_time(ui.clock.engine.step_no),
				ui.clock.engine.inputs.size(), "; in a session" if ui.get("session") != null and ui.session.active() else ""])
	L.append("")
	var lines: Array = keeper.last(SHOWN_LINES) if keeper != null else []
	L.append("The app's last %d log lines:" % lines.size())
	for l in lines:
		L.append("  " + String(l))
	if lines.is_empty():
		L.append("  (none)")
	if with_inputs and ui != null and ui.get("clock") != null and ui.clock.engine != null:
		var e = ui.clock.engine
		var d := {"format": "walkdown-plant-inputs", "app": RunSave.app_version(),
				"content": ui.autosave.content if ui.get("autosave") != null else "", "scenario": ui.clock.scenario,
				"step": e.step_no, "inputs": e.inputs}
		var js := JSON.stringify(d)
		L.append("")
		if js.length() > REPORT_MAX:
			L.append("The run's inputs: left out, %d characters is more than a report holds." % js.length())
		else:
			L.append("The run's inputs (what was done in this run, to replay it):")
			L.append(js)
	return redact("\n".join(L), secrets_of(main))


## A link to a new issue on the project's tracker with the report filled in; when it is too long for a link, the
## issue says the report was copied and is to be pasted.
static func issue_url(text: String) -> String:
	var title := "Walkdown Plant: a problem report"
	var url := "%s?title=%s&body=%s" % [ISSUES, title.uri_encode(), text.uri_encode()]
	if url.length() <= URL_MAX:
		return url
	var short := "The report was too long for the link and was copied: paste it here (Ctrl+V), below what happened."
	return "%s?title=%s&body=%s" % [ISSUES, title.uri_encode(), short.uri_encode()]


## Android's share sheet with the text (through the AndroidRuntime plugin's Java bridge): "" or why not.
static func share_android(text: String) -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return "sharing is on Android only"
	var act = Engine.get_singleton("AndroidRuntime").getActivity()
	if act == null:
		return "no activity"
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	var i = Intent.Intent()
	if i == null:
		return "no Intent"
	i.setAction("android.intent.action.SEND")
	i.putExtra("android.intent.extra.SUBJECT", "Walkdown Plant problem report")
	i.putExtra("android.intent.extra.TEXT", text)
	i.setType("text/plain")
	var chooser = Intent.createChooser(i, "Share the problem report")
	act.startActivity(chooser if chooser != null else i)
	return ""


# ------------------------------------------------------------------ the view (in the settings panel, as About)

var main
var text_box: TextEdit
var inputs_cb: CheckBox
var note: Label
var back: Button
var save_btn: Button
var share_btn: Button
var copy_btn: Button
var issue_btn: Button
var _dialog: FileDialog
var report := ""


func _init() -> void:
	name = "report"
	visible = false
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(10 * W.scale))
	var t := Label.new()
	t.text = "Report a problem"
	t.add_theme_font_size_override("font_size", int(28 * W.scale))
	add_child(t)
	var intro := W.label("Nothing is sent by itself. Below is the whole report: the app's version, this device and its "
			+ "graphics, and the app's last log lines. Player names, session codes, network addresses and your "
			+ "folders are left out. Write what happened at its top, then save, share or copy it, or open a public "
			+ "issue with it (the project's tracker on GitHub, which anyone can read).", 18)
	intro.name = "intro"
	add_child(intro)
	inputs_cb = CheckBox.new()
	inputs_cb.name = "with_inputs"
	inputs_cb.text = "Include this run's inputs (what was done in it, so the problem can be replayed)"
	inputs_cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inputs_cb.add_theme_font_size_override("font_size", int(18 * W.scale))
	inputs_cb.custom_minimum_size.y = 52 * W.scale
	inputs_cb.toggled.connect(func(_on): refresh())
	add_child(inputs_cb)
	text_box = TextEdit.new()
	text_box.name = "report_text"
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_box.add_theme_font_size_override("font_size", int(16 * W.scale))
	text_box.accessibility_name = "The report"
	add_child(text_box)
	note = W.label("", 18)
	note.name = "said"
	note.visible = false
	if "accessibility_live" in note:
		note.set("accessibility_live", 1)
	add_child(note)
	var row := HFlowContainer.new()
	row.name = "actions"
	row.add_theme_constant_override("h_separation", int(10 * W.scale))
	row.add_theme_constant_override("v_separation", int(10 * W.scale))
	add_child(row)
	save_btn = W.button("Save to a file…", save_file)
	save_btn.name = "save_file"
	row.add_child(save_btn)
	share_btn = W.button("Share…", share)
	share_btn.name = "share"
	share_btn.visible = OS.get_name() == "Android"
	row.add_child(share_btn)
	copy_btn = W.button("Copy", copy)
	copy_btn.name = "copy"
	row.add_child(copy_btn)
	issue_btn = W.button("Open a public issue", open_issue)
	issue_btn.name = "open_issue"
	row.add_child(issue_btn)
	back = W.button("Back", close)
	back.name = "back"
	row.add_child(back)


func open() -> void:
	inputs_cb.set_pressed_no_signal(false)       # never ticked for the trainee (T1)
	note.visible = false
	refresh()
	visible = true
	back.grab_focus()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## The report made again (the box ticked or not); what the trainee wrote at its top is kept.
func refresh() -> void:
	var wrote := _written()
	report = build(main, inputs_cb.button_pressed)
	text_box.text = report.replace("What happened (write it here): ", "What happened (write it here): " + wrote)
	text_box.scroll_vertical = 0


func _written() -> String:
	if text_box == null or text_box.text == "":
		return ""
	for l in text_box.text.split("\n"):
		if l.begins_with("What happened (write it here): "):
			return l.substr("What happened (write it here): ".length())
	return ""


## What is given: the box's text as the trainee sees it (with what they wrote), redacted again in case they pasted
## something.
func given() -> String:
	return redact(text_box.text, secrets_of(main))


func _say(t: String) -> void:
	note.text = t
	note.visible = true


func copy() -> void:
	DisplayServer.clipboard_set(given())
	_say("The report was copied (%d characters)." % given().length())


func save_file() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.filters = PackedStringArray(["*.txt ; Text"])
		_dialog.title = "Save the problem report"
		_dialog.file_selected.connect(write_to)
		add_child(_dialog)
	_dialog.current_file = "walkdown-plant-report-%s.txt" % Time.get_datetime_string_from_system(false, false) \
			.replace(":", "").replace("T", "-").left(15)
	_dialog.popup_centered_ratio(0.8)


## Writes the report to `path`; says where, or why not.
func write_to(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_say("The report could not be saved there (%s). Choose another folder, or copy it instead." \
				% error_string(FileAccess.get_open_error()))
		return
	f.store_string(given())
	f.close()
	_say("The report was saved as %s." % path.get_file())


func share() -> void:
	var why := share_android(given())
	_say("The system's share sheet is open." if why == "" else "Sharing did not open (%s): save or copy it instead." % why)


func open_issue() -> void:
	var t := given()
	var url := issue_url(t)
	if not url.contains(t.uri_encode()):
		DisplayServer.clipboard_set(t)
	var err := OS.shell_open(url)
	if err != OK:
		DisplayServer.clipboard_set(t)
		_say("No browser opened (%s). The report was copied: paste it into a new issue at %s." % [error_string(err), ISSUES])
	else:
		_say("A new issue opens in your browser%s. Nothing is posted until you press its button there." \
				% ("" if url.contains(t.uri_encode()) else ", with the report copied to paste in"))


## Back: Esc, gamepad B or Start (before the settings see it), as About.
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not e.is_pressed():
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu") \
			or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B):
		close()
		get_viewport().set_input_as_handled()
