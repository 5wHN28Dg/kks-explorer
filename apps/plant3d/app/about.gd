## About Walkdown Plant (decision 0054 §7), opened from the settings panel (app/hud.gd): the app's version and the
## commit it was built from, its licence and source, the third-party assets it carries (built/about.json, from
## apps/plant3d/about.json: tools/about.py --plant) and the Godot Engine's own notices (Engine.get_license_text(),
## get_copyright_info(), get_license_info()).
## It scrolls by touch (drag), mouse wheel, keyboard (arrows, W/S, Page Up/Down, Home/End) and gamepad (either
## stick, the D-pad); Back, Esc, or gamepad B or Start goes back to the settings.
extends VBoxContainer

signal closed

const SOURCE := "https://github.com/5wHN28Dg/kks-explorer"
const SCROLL_SPEED := 1400.0    # px a second at full stick or a held key
const STEP := 120               # px a D-pad press

var scroll: ScrollContainer
var body: VBoxContainer
var back: Button
var _filled := false


func _init() -> void:
	name = "about"
	visible = false
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var t := Label.new()
	t.text = "About Walkdown Plant"
	t.add_theme_font_size_override("font_size", 28)
	add_child(t)
	scroll = ScrollContainer.new()
	scroll.name = "scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	back = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 64)
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(close)
	add_child(back)


## Builds the text the first time (Godot's notices are long) and shows it from the top.
func open() -> void:
	if not _filled:
		_filled = true
		for s in sections():
			_section(s[0], s[1])
	visible = true
	scroll.scroll_vertical = 0
	back.grab_focus()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## [[title, text], …]: what About shows, in order.
static func sections() -> Array:
	var out: Array = []
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	var b := build_info()
	var built: String
	if b.commit == "":
		built = "Built from an unknown commit (not made by apps/plant3d/build.sh)."
	else:
		built = "Built from commit %s%s.\nIts source: %s/tree/%s" % [b.commit, " with local changes" if b.changes else "",
			SOURCE, b.commit]
	var gv: Dictionary = Engine.get_version_info()
	out.append(["Walkdown Plant %s" % (v if v != "" else "(version unknown)"),
		"%s\nA generic combined-cycle power plant to walk through and operate: an invented plant, not a real one.\n\nLicence: GNU Affero General Public License v3.0 or later. Source: %s\nMade with the Godot Engine %s." % [built, SOURCE, gv.get("string", "")]])
	var a := about_data()
	if a.is_empty():
		out.append(["Assets", "The list of third-party assets is missing from this build (built/about.json)."])
	else:
		var lines := PackedStringArray([str(a.get("note", ""))])
		for x in a.get("assets", []):
			lines.append("\n%s: %s\n%s\nUsed for %s." % [x.get("name", "?"), x.get("license", "?"), x.get("url", ""), x.get("use", "")])
			if x.get("notice", "") is String and x.get("notice", "") != "":   # its own licence file (BSD, MIT: the code)
				lines.append(str(x.notice).strip_edges())
		out.append(["Assets", "\n".join(lines)])
		var lic: Dictionary = a.get("licenses", {})
		for id in lic:
			out.append(["%s (%s)" % [lic[id].get("name", id), id], str(lic[id].get("text", lic[id].get("url", "")))])
	out.append(["Godot Engine", Engine.get_license_text()])
	var parts := PackedStringArray()
	for c in Engine.get_copyright_info():
		var p := PackedStringArray([str(c.get("name", ""))])
		for part in c.get("parts", []):
			for cr in part.get("copyright", []):
				p.append("  © " + str(cr))
			p.append("  Licence: " + str(part.get("license", "")))
		parts.append("\n".join(p))
	out.append(["The Godot Engine's third-party parts", "\n\n".join(parts)])
	var li: Dictionary = Engine.get_license_info()
	var names: Array = li.keys()
	names.sort()
	for n in names:
		out.append(["Licence: %s" % n, str(li[n])])
	return out


## {commit, changes} from built/build_info.json (build.sh writes it); an empty commit when there is none.
static func build_info() -> Dictionary:
	var out := {"commit": "", "changes": false}
	var s := FileAccess.get_file_as_string("res://built/build_info.json")
	var d = JSON.parse_string(s) if s != "" else null
	if d is Dictionary and d.get("commit") is String and (d.commit as String).length() == 40 \
			and (d.commit as String).is_valid_hex_number():
		out.commit = d.commit
		out.changes = d.get("changes") == true
	return out


## The assets' notices: built/about.json (format walkdown-plant-about 1), or {} when missing or another format.
static func about_data() -> Dictionary:
	var s := FileAccess.get_file_as_string("res://built/about.json")
	var d = JSON.parse_string(s) if s != "" else null
	if d is Dictionary and d.get("format") == "walkdown-plant-about":
		return d
	return {}


func _section(title: String, text: String) -> void:
	var h := Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", 24)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(h)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 18)
	body.add_child(l)


## Back: Esc, gamepad B or Start (before the settings and the plant's panels see it; Godot's ui_cancel has no
## gamepad button). The D-pad, Page Up/Down,
## Home and End scroll.
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not e.is_pressed():
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu") \
			or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B):
		close()
		get_viewport().set_input_as_handled()
		return
	var page := int(scroll.size.y * 0.9)
	var to := -1
	if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_DOWN:
		to = scroll.scroll_vertical + STEP
	elif e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_UP:
		to = scroll.scroll_vertical - STEP
	elif e is InputEventKey and e.keycode == KEY_PAGEDOWN:
		to = scroll.scroll_vertical + page
	elif e is InputEventKey and e.keycode == KEY_PAGEUP:
		to = scroll.scroll_vertical - page
	elif e is InputEventKey and e.keycode == KEY_HOME:
		to = 0
	elif e is InputEventKey and e.keycode == KEY_END:
		to = int(scroll.get_v_scroll_bar().max_value)
	if to >= 0 or (e is InputEventJoypadButton and e.button_index in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP]):
		scroll.scroll_vertical = maxi(to, 0)
		get_viewport().set_input_as_handled()


## Held keys (arrows, W/S) and either stick scroll smoothly.
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var dy := Input.get_axis("move_forward", "move_back") + Input.get_axis("look_up", "look_down")
	if absf(dy) > 0.05:
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + int(dy * SCROLL_SPEED * delta))
