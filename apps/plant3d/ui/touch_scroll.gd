## A finger's drag that begins on a button in a scrolling panel scrolls the panel, and the button it began on is not
## pressed (UI-UX-POLICY T1's targets fill such panels on a phone: there is little else to drag). Godot's own
## ScrollContainer drags only from where its children pass the touch on, and a button takes it; a drag that begins
## elsewhere in the panel is left to it. A press on a button, or a drag that stays within the touch slop (8 dp, up or
## down), or one on a panel with nothing to scroll, is an ordinary press. The panels it serves scroll up and down. A drag that begins on a slider is the slider's.
##   TouchScroll.attach(scroll_container)
extends Node

const SLOP_DP := 8.0            # how far a finger moves before the touch is a drag (Android's touch slop, 8 dp)

var sc: ScrollContainer
var _index := -1                # the finger dragging (-1: none)
var _from := Vector2.ZERO       # where it touched down
var _scroll0 := Vector2.ZERO    # the scroll then
var _dragging := false
var _button: BaseButton         # the button the touch began on
var blocked := Callable()       # true while something drawn over the panel takes the touches (the manual's reader)


static func attach(s: ScrollContainer, over := Callable()) -> Node:
	var n = load("res://ui/touch_scroll.gd").new()
	n.name = "touch_scroll"
	n.sc = s
	n.blocked = over
	s.add_child(n, false, Node.INTERNAL_MODE_BACK)
	return n


func _input(e: InputEvent) -> void:
	if sc == null or not sc.is_visible_in_tree():
		_index = -1
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and _index < 0:
			if blocked.is_valid() and blocked.call():
				return
			_button = _button_at(t.position)
			if _button != null:
				_index = t.index
				_from = t.position
				_dragging = false
		elif not t.pressed and t.index == _index:
			_index = -1                # (the button forgot its press when the drag began: the lift presses nothing)
			_dragging = false
	elif e is InputEventScreenDrag and (e as InputEventScreenDrag).index == _index:
		var d: Vector2 = (e as InputEventScreenDrag).position - _from
		# a drag along the way the panel scrolls, when it has something to scroll: a tap that wobbles, or one on a
		# panel that fits, stays a tap
		if not _dragging and absf(d.y) > _slop() and _can_scroll():
			_dragging = true
			_cancel_press()
			# (from here: the panel may have scrolled the touched button into view since the touch)
			_from = (e as InputEventScreenDrag).position
			_scroll0 = Vector2(sc.scroll_horizontal, sc.scroll_vertical)
			d = Vector2.ZERO
		if _dragging:
			if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				sc.scroll_vertical = int(roundf(_scroll0.y - d.y))
			get_viewport().set_input_as_handled()


## The touch slop in the canvas's units (they grow with the UI size): 8 dp on the screen at every size.
func _slop() -> float:
	var vp := get_viewport()
	var px_per_unit: float = vp.get_final_transform().get_scale().y if vp != null else 1.0
	var dpi := float(DisplayServer.screen_get_dpi())
	return SLOP_DP * maxf(dpi, 160.0) / 160.0 / maxf(px_per_unit, 0.01)


func _can_scroll() -> bool:
	return sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
		and sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page > 1.0


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
		if cc is BaseButton:       # (a disabled one too: it stops the touch from reaching the scroll as well)
			found = cc
	return found


## The press the touch began on its button is let go without pressing it: a button disabled forgets the press (Godot's
## BaseButton; a toggle keeps its state), and it is enabled again at once.
func _cancel_press() -> void:
	if is_instance_valid(_button) and not _button.disabled:
		_button.disabled = true
		_button.disabled = false
