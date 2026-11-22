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
const Code = preload("res://net/code.gd")

const ISSUES := "https://github.com/5wHN28Dg/kks-explorer/issues/new"
const KEEP_LINES := 200         # log lines kept
const SHOWN_LINES := 100        # of them in a report
const LINE_MAX := 300           # characters of a line shown (cut after redaction: a name is never half left)
const LINE_KEEP := 2000         # characters of a line kept
const URL_MAX := 2000           # a prefilled issue's link at most this long (Windows' ShellExecute: about 2,083)
const ISSUE_MAX := 60000        # characters an issue's body takes (GitHub's limit is 65,536): beyond, a file to attach
const DRAFT := "user://report-draft.txt"   # what happened, as typed (kept if the app stops; gone once given)
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
		var t := Time.get_datetime_string_from_system(true, true).substr(11)   # UTC, as the report's own time
		mutex.lock()
		lines.append("%s %s" % [t, s.strip_edges().left(LINE_KEEP)])
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
static var _seen := {}          # every secret seen this process (a player who left, a session that ended)

## A name or code to leave out of every report from now on (net/session.gd and the session panel call it as they
## see one; secrets_of() adds what it finds too). Each word of a name of 3 letters or more is left out as well.
static func remember(secret: String, words: String) -> void:
	var k := secret.strip_edges()
	if k.length() < 2 or GENERIC.has(k.to_lower()):
		return
	_seen[k] = words
	if words == "[player name]":
		for w in k.split(" ", false):
			if w.length() >= 3 and not GENERIC.has(w.to_lower()):
				_seen[w] = words
const GENERIC := ["player", "plant", "trainee"]   # a default or common word is never a name to hide

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
	for x in out:
		remember(String(x[0]), x[1])
	var all: Array = []
	for k in _seen:
		all.append([k, _seen[k]])
	return all


## The text with the secrets, the user's folders and name, and network addresses replaced.
static func redact(text: String, secrets: Array) -> String:
	var pairs: Array = secrets.duplicate()
	pairs.append([OS.get_user_data_dir(), "<app data>"])
	pairs.append([ProjectSettings.globalize_path("user://"), "<app data>/"])
	pairs.append([OS.get_environment("HOME"), "~"])
	pairs.append([OS.get_environment("USERPROFILE"), "~"])
	for v in ["USER", "USERNAME", "LOGNAME"]:
		pairs.append([OS.get_environment(v), "[user]"])
	# the longest first: a name inside another one is never left half replaced; any case (a Windows path's user
	# folder); first to marks, then the marks to words, so that a later one never matches inside a word put in
	pairs = pairs.filter(func(p): return String(p[0]).strip_edges().length() >= 2 \
			and not GENERIC.has(String(p[0]).strip_edges().to_lower()))
	pairs.sort_custom(func(a, b): return String(a[0]).length() > String(b[0]).length())
	for i in pairs.size():
		text = _replace_nocase(text, String(pairs[i][0]).strip_edges(), "\u0001%d\u0002" % i)
	for i in pairs.size():
		text = text.replace("\u0001%d\u0002" % i, pairs[i][1])
	var re := RegEx.new()
	# any session invite code, dashed or not, in any case, that passes its check character (net/code.gd)
	re.compile("(?i)\\b[0-9a-z]{4}-?[0-9a-z]{4}-?[0-9a-z]{4}-?[0-9a-z]{4}\\b")
	var found := re.search_all(text)
	for i in range(found.size() - 1, -1, -1):
		var m: RegExMatch = found[i]
		if Code.normalize(m.get_string()) != "":
			text = text.substr(0, m.get_start()) + "[session code]" + text.substr(m.get_end())
	re.compile("\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b")                                  # IPv4
	text = re.sub(text, "<address>", true)
	# IPv6: eight groups, or fewer with "::" (never a time of day such as 07:40:12)
	re.compile("\\b(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}\\b")
	text = re.sub(text, "<address>", true)
	re.compile("(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{1,4}:)*[0-9A-Fa-f]{0,4}::(?:[0-9A-Fa-f]{1,4}:)*[0-9A-Fa-f]{1,4}\\b")
	text = re.sub(text, "<address>", true)
	return text


static func _replace_nocase(text: String, what: String, with: String) -> String:
	var low := text.to_lower()
	var w := what.to_lower()
	var out := ""
	var at := 0
	var i := low.find(w)
	while i >= 0:
		# whole words only (a name's "Ali" never inside "quality"; a path's ends are not letters anyway)
		var e := i + w.length()
		var before_ok := i == 0 or not _wordish(low[i - 1]) or not _wordish(w[0])
		var after_ok := e >= low.length() or not _wordish(low[e]) or not _wordish(w[w.length() - 1])
		if before_ok and after_ok:
			out += text.substr(at, i - at) + with
			at = e
			i = low.find(w, at)
		else:
			i = low.find(w, i + 1)
	return out + text.substr(at)


static func _wordish(c: String) -> bool:
	return c == "_" or c.is_valid_int() or c.to_upper() != c.to_lower() or c.unicode_at(0) > 127


## The report, as shown and given. `with_inputs`: the run's inputs too.
static func build(main, with_inputs: bool) -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	var b := About.build_info()
	var L := PackedStringArray()
	L.append("Walkdown Plant problem report")
	L.append("Made: %s" % Time.get_datetime_string_from_system(true, true) + " UTC")
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
	var secrets := secrets_of(main)
	var head := redact("\n".join(L), secrets)
	L = PackedStringArray()
	var lines: Array = keeper.last(SHOWN_LINES) if keeper != null else []
	L.append("The app's last %d log lines:" % lines.size())
	for l in lines:
		L.append("  " + redact(String(l), secrets).left(LINE_MAX))   # (redacted whole, then cut: once)
	if lines.is_empty():
		L.append("  (none)")
	var logs := "\n".join(L)
	L = PackedStringArray()
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
	return head + "\n" + logs + ("\n" + redact("\n".join(L), secrets) if not L.is_empty() else "")


## A link to a new issue on the project's tracker with the report filled in; when it is too long for a link, the
## issue says the report was copied and is to be pasted.
static func issue_url(text: String) -> String:
	var title := "Walkdown Plant: a problem report"
	if text.length() <= URL_MAX:
		var url := "%s?title=%s&body=%s" % [ISSUES, title.uri_encode(), text.uri_encode()]
		if url.length() <= URL_MAX:
			return url
	var short := ("The report was too long for the link and was copied: paste it here." if text.length() <= ISSUE_MAX
			else "The report is too long to paste here: attach the file Walkdown Plant saved it to.")
	return "%s?title=%s&body=%s" % [ISSUES, title.uri_encode(), short.uri_encode()]


## Android's share sheet with the text (through the AndroidRuntime plugin's Java bridge): "" or why not.
static func share_android(text: String) -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return "only Android has a share sheet"
	var act = Engine.get_singleton("AndroidRuntime").getActivity()
	if act == null:
		return "the app's window was not ready"
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	var i = Intent.Intent()
	if i == null:
		return "Android refused to make the message"
	i.setAction("android.intent.action.SEND")
	i.putExtra("android.intent.extra.SUBJECT", "Walkdown Plant problem report")
	i.putExtra("android.intent.extra.TEXT", text)
	i.setType("text/plain")
	var chooser = Intent.createChooser(i, "Share the problem report")
	act.startActivity(chooser if chooser != null else i)
	return ""


# ------------------------------------------------------------------ the view (in the settings panel, as About)

var main
var what_box: TextEdit          # what happened, in the trainee's words (kept while the app runs)
var text_box: TextEdit          # the report, read-only: shown in full, selectable
var inputs_cb: CheckBox
var note: Label
var back: Button
var save_btn: Button
var share_btn: Button
var copy_btn: Button
var issue_btn: Button
var scroll: ScrollContainer
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
	# everything but the title and the buttons scrolls (a short canvas, a large UI size): the report itself always
	# keeps a height of its own
	scroll = ScrollContainer.new()
	scroll.name = "scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(10 * W.scale))
	scroll.add_child(body)
	var intro := W.label("Nothing is sent by itself. Below is the whole report: the app's version, this device and its "
			+ "graphics, and the app's last log lines. Player names, session codes, network addresses and your "
			+ "folders are left out. Say what happened, then save, share or copy it, or open a public issue with it "
			+ "(the project's tracker on GitHub, which anyone can read).", 18)
	intro.name = "intro"
	body.add_child(intro)
	body.add_child(W.label("What happened", 18))
	what_box = TextEdit.new()
	what_box.name = "what_happened"
	what_box.placeholder_text = "What you did, what you saw, what you expected"
	what_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	what_box.custom_minimum_size.y = 110 * W.scale
	what_box.add_theme_font_size_override("font_size", int(18 * W.scale))
	what_box.accessibility_name = "What happened"
	what_box.text_changed.connect(_typed)
	what_box.text = FileAccess.get_file_as_string(DRAFT)   # (a draft the app kept when it stopped)
	_field_style(what_box)
	what_box.tab_input_mode = false          # Tab moves on to the next control (the keyboard never stays in it)
	body.add_child(what_box)
	inputs_cb = CheckBox.new()
	inputs_cb.name = "with_inputs"
	inputs_cb.text = "Include this run's inputs (what was done in it, so the problem can be replayed)"
	inputs_cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inputs_cb.add_theme_font_size_override("font_size", int(18 * W.scale))
	inputs_cb.custom_minimum_size.y = 52 * W.scale
	inputs_cb.toggled.connect(func(_on): refresh())
	# its box drawn with an edge seen on the dark row (A2: at least 3:1), ticked filled
	inputs_cb.add_theme_icon_override("unchecked", _box_icon(false))
	inputs_cb.add_theme_icon_override("checked", _box_icon(true))
	body.add_child(inputs_cb)
	body.add_child(W.label("The report" + ("" if OS.has_feature("mobile")
			else "  (Page Up and Page Down, the gamepad's shoulder buttons or its right stick scroll it)"), 18))
	text_box = TextEdit.new()
	text_box.name = "report_text"
	text_box.editable = false               # shown as it will go; it can be selected and copied
	text_box.focus_mode = Control.FOCUS_CLICK   # (the D-pad and Tab pass it by: it would hold them, moving its caret)
	text_box.add_theme_color_override("font_readonly_color", Color.WHITE)   # (read-only text is dimmed by default: A1)
	_field_style(text_box)
	text_box.custom_minimum_size.y = 260 * W.scale
	text_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_box.add_theme_font_size_override("font_size", int(18 * W.scale))
	text_box.accessibility_name = "The report"
	body.add_child(text_box)
	note = W.label("", 18)
	note.name = "said"
	note.visible = false
	if "accessibility_live" in note:
		note.set("accessibility_live", 1)
	add_child(note)
	# beside the buttons, what the issue's button means (the owner's verdict on #505: a line next to it)
	var pub := W.label("An issue on GitHub is public: anyone can read what you post there.", 16, W.DIM)
	pub.name = "public_note"
	add_child(pub)
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
	inputs_cb.set_pressed_no_signal(false)       # never ticked for the trainee (T1); what they wrote stays
	note.visible = false
	refresh()
	visible = true
	scroll.scroll_vertical = 0
	back.grab_focus()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## A check box's square, `scale`d: a light edge, filled when ticked.
static func _box_icon(ticked: bool) -> ImageTexture:
	var n := maxi(16, int(24 * W.scale))
	var b := maxi(2, int(2 * W.scale))
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(0.85, 0.88, 0.93)
	for y in n:
		for x in n:
			if x < b or y < b or x >= n - b or y >= n - b:
				img.set_pixel(x, y, edge)
			elif ticked and x >= 2 * b and y >= 2 * b and x < n - 2 * b and y < n - 2 * b:
				img.set_pixel(x, y, Color(1.0, 0.8, 0.25))
	return ImageTexture.create_from_image(img)


## A text box's edge seen against the panel (A2: at least 3:1), in every state.
static func _field_style(t: TextEdit) -> void:
	for k in ["normal", "read_only", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.055, 0.07)
		sb.border_color = Color(0.62, 0.66, 0.74) if k != "focus" else Color(1.0, 0.8, 0.25)
		sb.set_border_width_all(maxi(2, int(2 * W.scale)))
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8 * W.scale)
		t.add_theme_stylebox_override(k, sb)


## Typing: the draft kept (the app may be stopped while the browser or a file dialog is in front), the issue's
## button's words a moment later.
var _draft_due := false
func _typed() -> void:
	_issue_label_soon()
	if _draft_due or not is_inside_tree():
		return
	_draft_due = true
	get_tree().create_timer(0.5).timeout.connect(func():
		_draft_due = false
		_keep_draft())


func _keep_draft() -> void:
	var t := what_box.text
	if t.strip_edges() == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DRAFT))
		return
	var f := FileAccess.open(DRAFT, FileAccess.WRITE)
	if f != null:
		f.store_string(t)


## Given away (saved, shared, put in an issue): the next report starts empty, and the draft goes.
func _given_away() -> void:
	what_box.text = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DRAFT))


## The report made again (the box ticked or not); what the trainee wrote is its own box, untouched.
func refresh() -> void:
	report = build(main, inputs_cb.button_pressed)
	text_box.text = report
	# the issue's button says when its link can't hold the report and it is copied to be pasted (S6)
	_issue_label()


var _label_due := false
## The issue's button's words follow what is typed (a long description no longer fits a link), a moment after typing.
func _issue_label_soon() -> void:
	if _label_due or not is_inside_tree():
		return
	_label_due = true
	get_tree().create_timer(0.3).timeout.connect(func():
		_label_due = false
		_issue_label())


func _issue_label() -> void:
	var g := given()
	issue_btn.text = "Open a public issue" if _fits(g) else ("Copy and open a public issue" if g.length() <= ISSUE_MAX
			else "Open a public issue to attach the file to")


## The report fits in an issue's link (else it is copied, to be pasted there, or too long even for that).
func _fits(g := "") -> bool:
	if g == "":
		g = given()
	return g.length() <= URL_MAX and issue_url(g).contains("&body=" + g.uri_encode())


## What is given: what the trainee wrote (redacted: they may have typed a name), then the report (redacted already).
func given() -> String:
	var w := redact(what_box.text.strip_edges(), secrets_of(main))
	return "What happened: %s\n\n%s" % [w if w != "" else "(not said)", report]


func _say(t: String) -> void:
	note.text = t
	note.visible = true


func copy() -> void:
	var g := given()
	DisplayServer.clipboard_set(g)
	_say("The report was copied (%d characters)." % g.length())


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
	_dialog.current_file = "walkdown-plant-report-%s.txt" % Time.get_datetime_string_from_system(true, false) \
			.replace(":", "").replace("T", "-").left(15)
	_dialog.popup_centered_ratio(0.8)


## Writes the report to `path`; says where, or why not.
func write_to(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_say("The report could not be saved there: the folder may not be writable, or the storage full. Choose "
				+ "another folder, or copy the report instead.")
		return
	f.store_string(given())
	f.close()
	_given_away()
	_say("The report was saved as %s." % path.get_file())


func share() -> void:
	var why := share_android(given())       # (what happened stays: the share may be cancelled)
	_say("Android's share sheet is open." if why == "" else "Sharing did not open (%s). Save or copy the report instead." % why)


func open_issue() -> void:
	var said := issue_btn.text                  # what the button said when it was pressed
	var t := given()
	var url := issue_url(t)
	var fits := _fits(t)
	var too_long := t.length() > ISSUE_MAX
	# copied only when the button said so (its words lag typing by a moment: then it is said, not done)
	var copied := not fits and not too_long and said.begins_with("Copy")
	if copied:
		DisplayServer.clipboard_set(t)
	var err := OS.shell_open(url)
	if err != OK:
		_say("No browser opened. Copy the report (or save it), then make a new issue at %s." % ISSUES)
		return
	_issue_label()                              # (what happened stays: the issue may be left unposted)
	if too_long:
		_say("A new issue opens in your browser. The report is too long to paste there: save it to a file, then attach "
				+ "the file to the issue. Nothing is posted until you press its button there.")
	elif not fits and not copied:
		_say("A new issue opens in your browser. The report is too long for the link: press Copy, then paste it into "
				+ "the issue. Nothing is posted until you press its button there.")
	else:
		_say("A new issue opens in your browser%s. Nothing is posted until you press its button there." \
				% (", with the report copied: paste it into the issue" if copied else ""))


## Back: Esc, gamepad B or Start (before the settings see it), as About. (Gamepad A presses the focused button through
## app/hud.gd, as in the settings.)
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not e.is_pressed():
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu") \
			or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B):
		close()
		get_viewport().set_input_as_handled()
		return
	# the report scrolls by keys and the gamepad's shoulder buttons wherever the focus is (as About): it never takes
	# the focus itself, which would hold the D-pad and the arrows in it
	if what_box.has_focus() and e is InputEventKey:
		return                                  # (Page keys move in what is being typed)
	var page := int(text_box.size.y * 0.9)
	var to := -1.0
	if e is InputEventKey and e.keycode == KEY_PAGEDOWN or e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		to = text_box.scroll_vertical + page / maxf(1.0, text_box.get_line_height())
	elif e is InputEventKey and e.keycode == KEY_PAGEUP or e is InputEventJoypadButton and e.button_index == JOY_BUTTON_LEFT_SHOULDER:
		to = maxf(0.0, text_box.scroll_vertical - page / maxf(1.0, text_box.get_line_height()))
	if to >= 0.0:
		scroll.ensure_control_visible(text_box)
		text_box.scroll_vertical = to
		get_viewport().set_input_as_handled()


## The right stick scrolls the report (its look axes; held, smoothly).
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var dy := Input.get_axis("look_up", "look_down")
	if absf(dy) > 0.2:
		text_box.scroll_vertical = maxf(0.0, text_box.scroll_vertical + dy * 30.0 * delta)


## The draft written at once when the app may be stopped (the picker, the browser or the share sheet in front, Back).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST, \
				NOTIFICATION_WM_GO_BACK_REQUEST:
			if what_box != null and visible:
				_keep_draft()
