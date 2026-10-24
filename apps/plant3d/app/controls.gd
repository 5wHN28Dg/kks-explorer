## The input actions (R7): keyboard and mouse, gamepads (SDL3), and the touch sticks, which drive the same actions as
## a gamepad's sticks. Made here rather than in project.godot so that the bindings read as a table.
##
##   move      W A S D / arrows, left stick, the left touch stick (the sticks are analogue: a slow step to a jog;
##             keys walk at the settings' pace: app/player.gd speed_for)
##   look      mouse (captured: click the view), right stick, the right touch stick
##   run       Shift, left stick press (held; or pressed once each way with the settings' "Run key toggles")
##   fly       F, gamepad Y: free flight on and off
##   up, down  Space and C, gamepad RB and LB: in flight
##   map       M, Tab, gamepad Back: the overview map
##   use       E, gamepad A: press a door
##   menu      Escape, gamepad Start: settings (or closes the top panel of ui/)
##   alarms    L, gamepad D-pad up: the alarm list (ui/plant_ui.gd)
##   procedure P, gamepad D-pad left: procedures and tours
##   permits   T: the permits to work (gamepad: from a card's Permit button or the procedures panel)
##   crew      R: the crews: the role played, its tasks and the radio (gamepad: the bar's Crew button)
##   pause     K, gamepad D-pad down: pause, and run again at 1×
##   fast      . (full stop), gamepad D-pad right: fast-forward
##   home      H, gamepad X: to the control room and its screens, and the screens off again there (B is Godot's
##             ui_cancel: it closes the top panel)
extends Node

const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT], "run": [KEY_SHIFT], "fly": [KEY_F], "up": [KEY_SPACE],
	"down": [KEY_C], "map": [KEY_M, KEY_TAB], "use": [KEY_E], "menu": [KEY_ESCAPE],
	"alarms": [KEY_L], "procedure": [KEY_P], "pause": [KEY_K], "fast": [KEY_PERIOD], "home": [KEY_H],
	"permits": [KEY_T], "crew": [KEY_R],
	"look_left": [], "look_right": [], "look_up": [], "look_down": [],
}
const AXES := {   # action: [axis, direction]
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
}
const BUTTONS := {
	"run": [JOY_BUTTON_LEFT_STICK], "fly": [JOY_BUTTON_Y], "up": [JOY_BUTTON_RIGHT_SHOULDER],
	"down": [JOY_BUTTON_LEFT_SHOULDER], "map": [JOY_BUTTON_BACK], "use": [JOY_BUTTON_A], "menu": [JOY_BUTTON_START],
	"alarms": [JOY_BUTTON_DPAD_UP], "procedure": [JOY_BUTTON_DPAD_LEFT], "pause": [JOY_BUTTON_DPAD_DOWN],
	"fast": [JOY_BUTTON_DPAD_RIGHT], "home": [JOY_BUTTON_X],
}

func _init() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
		if AXES.has(action):
			var j := InputEventJoypadMotion.new()
			j.axis = AXES[action][0]
			j.axis_value = AXES[action][1]
			InputMap.action_add_event(action, j)
		for b in BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
