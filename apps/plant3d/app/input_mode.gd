## Which controls the trainee is using: a gamepad or the touch screen (the user, 2026-10-26: "when I connect a gamepad
## to the android version the app should hide on screen controls and switch to gamepad controls").
##
##   gamepad   a gamepad connects (or one is connected at the start), or a gamepad button is pressed or a stick or
##             trigger pushed past half way: the touch sticks and touch-only buttons hide (app/hud.gd), the HUD shows
##             the gamepad's buttons, and the panels take the focus (ui/plant_ui.gd wants_focus)
##   touch     the screen is touched, or the last gamepad disconnects: the touch controls come back (on a touch
##             screen) until a gamepad is used again
##
## A key or a mouse button (not one made from a touch) takes the controls from the gamepad on a desktop, where the
## gamepad's line and the hidden Fly and Use buttons would otherwise stay while the keyboard and mouse are used; not
## on a phone, where Android can send a gamepad's buttons as keys as well. A finger moving that was down before the
## gamepad took over doesn't count: only a new touch does. The settings' "Touch controls" (app/hud.gd) chooses
## what this decides: Automatic follows it, Always and Never don't.
extends Node

signal changed(pad: bool)

const PUSH := 0.5        # a stick or trigger pushed this far is the gamepad in use (not drift or a resting trigger)

var pad := false         # the gamepad is the controls in use
var pads := {}           # connected gamepads' device ids (kept here: tests connect and disconnect by the signal)
var keys_count := not OS.has_feature("mobile")   # keys and mouse buttons take the controls from the gamepad
var swallow := false     # set by a `changed` handler: the event that switched is used up (app/hud.gd focus_panel)

## The gamepads connected now: one is the controls in use from the start.
func scan() -> void:
	pads.clear()
	for d in Input.get_connected_joypads():
		pads[d] = true
	pad = not pads.is_empty()

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_connection)

func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_connection):
		Input.joy_connection_changed.disconnect(_on_connection)

func _on_connection(device: int, connected: bool) -> void:
	if connected:
		pads[device] = true
		_switch(true)
	else:
		pads.erase(device)
		if pads.is_empty():
			_switch(false)

## Before the GUI and the walker see an event (the touch that brings the sticks back reaches them), and before any
## other node's _input can mark it handled: app/hud.gd puts this node last under the window's root, and the last
## child sees an event first.
func _input(e: InputEvent) -> void:
	swallow = false
	note(e)
	if swallow:
		swallow = false
		get_viewport().set_input_as_handled()

## The last input decides: a gamepad's press or push, or a touch.
func note(e: InputEvent) -> void:
	if (e is InputEventJoypadButton and e.pressed) or (e is InputEventJoypadMotion and absf(e.axis_value) >= PUSH):
		pads[e.device] = true        # (a gamepad whose connection came before this node did)
		_switch(true)
	elif e is InputEventScreenTouch and e.pressed:
		_switch(false)
	elif keys_count and e.device != InputEvent.DEVICE_ID_EMULATION and ((e is InputEventKey and e.pressed and not e.echo)
			or (e is InputEventMouseButton and e.pressed)):
		_switch(false)

func _switch(on: bool) -> void:
	if pad != on:
		pad = on
		changed.emit(on)
