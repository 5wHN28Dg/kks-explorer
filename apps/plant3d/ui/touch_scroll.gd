## A finger's drag that begins on a button in a scrolling panel scrolls the panel, and the button it began on is not
## pressed (UI-UX-POLICY T1's targets fill such panels on a phone: there is little else to drag). Godot's own
## ScrollContainer drags only from where its children pass the touch on, and a button takes it; a drag that begins
## elsewhere in the panel is left to it. A press on a button, or a drag that stays within DEADZONE, is an ordinary
## press. A drag that begins on a slider is the slider's.
##   TouchScroll.attach(scroll_container)
extends Node

const DEADZONE := 12.0          # canvas px a finger moves before the touch is a drag

var sc: ScrollContainer
var _index := -1                # the finger dragging (-1: none)
var _from := Vector2.ZERO       # where it touched down
var _scroll0 := Vector2.ZERO    # the scroll then
var _dragging := false


static func attach(s: ScrollContainer) -> Node:
	var n = load("res://ui/touch_scroll.gd").new()
	n.name = "touch_scroll"
	n.sc = s
	s.add_child(n, false, Node.INTERNAL_MODE_BACK)
	return n


func _input(e: InputEvent) -> void:
	if sc == null or not sc.is_visible_in_tree():
		_index = -1
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and _index < 0:
			if _button_at(t.position) != null:
				_index = t.index
				_from = t.position
				_scroll0 = Vector2(sc.scroll_horizontal, sc.scroll_vertical)
				_dragging = false
		elif not t.pressed and t.index == _index:
			_index = -1
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()   # (the lift ends the drag: it presses nothing)
	elif e is InputEventScreenDrag and (e as InputEventScreenDrag).index == _index:
		var d: Vector2 = (e as InputEventScreenDrag).position - _from
		if not _dragging and d.length() > DEADZONE:
			_dragging = true
			_cancel_presses()
		if _dragging:
			if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				sc.scroll_vertical = int(roundf(_scroll0.y - d.y))
			if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				sc.scroll_horizontal = int(roundf(_scroll0.x - d.x))
			get_viewport().set_input_as_handled()


## The button under a point inside the panel (none when it is on a slider or outside the panel's view).
func _button_at(p: Vector2) -> BaseButton:
	if not sc.get_global_rect().has_point(p):
		return null
	var found: BaseButton = null
	for c in sc.find_children("*", "Control", true, false):
		var cc := c as Control
		if not cc.is_visible_in_tree() or not cc.get_global_rect().has_point(p):
			continue
		if cc is Range and not cc is ScrollBar:
			return null
		if cc is BaseButton and not (cc as BaseButton).disabled:
			found = cc
	return found


## The press the touch began on a button is let go without pressing it: a button pressed while disabled forgets the
## press (Godot's BaseButton), and it is enabled again at once.
func _cancel_presses() -> void:
	for c in sc.find_children("*", "BaseButton", true, false):
		var b := c as BaseButton
		if not b.disabled and b.is_visible_in_tree() and b.get_global_rect().has_point(_from):
			b.disabled = true
			b.disabled = false
