## Links into Walkdown Plant (docs/PLANT3D.md §6, decision 0054 §3): `walkdown-plant://kks/<code>` and
## `walkdown-plant://procedure/<id>[/<step>]`. They come
## - on Linux and Windows on the command line, after `--` (the Flatpak's .desktop file passes `-- %u`, the MSIX's
##   `uap3:Protocol` `-- "%1"`), so that a crafted URI can't pass as one of Godot's own options;
## - on Android in the Intent that started or resumed the app (its intent filter is in the Gradle export, see
##   apps/plant3d/android), read through Godot's AndroidRuntime plugin.
## What a link opens is sim/links.gd `read_link`, the reference's rule; nothing else is read from it.
##
## Links out go to Walkdown (`walkdown://…`). Walkdown takes no links from other apps yet (its four platforms register
## no scheme: checked 2026-10-16), so WALKDOWN_TAKES is empty and the plant offers none; a course link in a procedure
## says so instead of failing silently. Add a kind here when Walkdown registers it.
extends Node

const PREFIX := "walkdown-plant://"
const WALKDOWN_TAKES: Array = []        # link kinds Walkdown opens: "course" once it registers walkdown://course/…

signal link(url: String)

var _last_intent := 0


## The links on the command line (any argument, before or after `--`).
static func from_args(args: PackedStringArray) -> Array:
	var out := []
	for a in args:
		var s := String(a).strip_edges()
		if s.begins_with(PREFIX) and s.length() <= 256:
			out.append(s)
	return out


func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for u in from_args(args):
		link.emit.call_deferred(u)
	_check_intent.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_check_intent()


## Android: the Intent of the activity (GodotActivity replaces it on onNewIntent), once per Intent.
func _check_intent() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return
	var rt = Engine.get_singleton("AndroidRuntime")
	var act = rt.getActivity()
	if act == null:
		return
	var intent = act.getIntent()
	if intent == null:
		return
	var id: int = intent.hashCode()
	if id == _last_intent:
		return
	_last_intent = id
	if int(intent.getFlags()) & 0x00100000:      # FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY: reopened from Recents, not a new link
		return
	var data = intent.getDataString()
	if typeof(data) == TYPE_STRING and String(data).begins_with(PREFIX) and String(data).length() <= 256:
		link.emit(String(data))


## Opens a link to Walkdown when Walkdown takes that kind; otherwise returns why not, in words.
static func open_walkdown(kind: String, path: String) -> String:
	if not WALKDOWN_TAKES.has(kind):
		return "Walkdown can't open links from other apps yet, so this %s can't be opened from here: open it in Walkdown." % kind
	var err := OS.shell_open("walkdown://%s/%s" % [kind, path.uri_encode().replace("%2F", "/")])
	if err != OK:
		return "Walkdown is not installed on this device (or doesn't open walkdown:// links)."
	return ""
