## Screenshots of the photosensitivity notice (app/flash_notice.gd, issue #443), to look at (not a test: it needs a
## display):
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --resolution WxH --script res://tests/flash_notice_shots.gd -- --out=DIR
##     [--pseudo]   the texts pseudo-localised (accented and 40 % longer: labels that must grow)
##     [--phone]    at the phone's UI scale (1.35, the Note 9's), at 150 % (its default size) and 200 %; run it at the
##                  phone's window, --resolution 2220x1080
## At the window's size, at UI sizes 100 %, 150 % and 200 %: the first start's notice (the focus on Continue, then Tab
## to the box, the box ticked), with Reduced motion on (the box fixed on), and as opened again from the settings (Close;
## over a stand-in for the dimmed plant). Its controls' rectangles are printed (the UI-UX policy's evidence pack).
## Synthetic settings only (a ConfigFile of its own: never the user's).
extends SceneTree

const FlashNotice = preload("res://app/flash_notice.gd")
const W = preload("res://ui/widgets.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://flash_notice_shots"
	var pseudo := false
	var phone := false
	for a in OS.get_cmdline_user_args():
		if a == "--phone":
			phone = true
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--pseudo":
			pseudo = true
	DirAccess.make_dir_recursive_absolute(out)
	FlashNotice.switch_override = 1
	FlashNotice.display_override = 1
	W.pick_scale()
	if phone:
		W.scale = 1.35
	var under := ColorRect.new()      # a stand-in for the plant under the notice opened from the settings
	under.color = Color(0.35, 0.45, 0.55)
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	for f in ([1.5, 2.0] if phone else [1.0, 1.5, 2.0]):
		W.apply_ui_size(root, f)
		for kind in ["first", "reduced", "again"]:
			var cf := ConfigFile.new()
			if kind == "reduced":
				cf.set_value("ui", "reduced_motion", true)
			if kind == "again":
				root.add_child(under)
			var n = FlashNotice.new(cf, kind == "again")
			root.add_child(n)
			if pseudo:
				_pseudo(n)
				n._place()
			for i in 6:
				await process_frame
			var vs := root.get_visible_rect().size
			print("%s, ui size %d %%: canvas %s, window %s" % [kind, roundi(f * 100), str(vs), str(root.size)])
			for c: Control in [n.panel, n.scroll, n.no_flashes, n.continue_button]:
				print("  %s %s" % [c.name, str(c.get_global_rect())])
			print("  words fit without scrolling: %s" % str(n.scroll.get_v_scroll_bar().max_value <= n.scroll.size.y + 1.0))
			print("  screen reader, with the focused button: %s" % n.continue_button.accessibility_description)
			var tag := "%s%dx%d-%d-%s%s" % ["phone-" if phone else "", root.size.x, root.size.y, roundi(f * 100), kind,
					"-pseudo" if pseudo else ""]
			await _save(out + "/flash-notice-%s.png" % tag)
			if kind == "first" and is_equal_approx(f, 1.0):
				var ev := InputEventKey.new()
				ev.keycode = KEY_TAB
				ev.physical_keycode = KEY_TAB
				ev.pressed = true
				root.push_input(ev)
				await process_frame
				await process_frame
				print("  focus after Tab: %s" % str(root.gui_get_focus_owner().name if root.gui_get_focus_owner() else "none"))
				await _save(out + "/flash-notice-%s-tab.png" % tag)
				n.no_flashes.button_pressed = true
				await process_frame
				await _save(out + "/flash-notice-%s-ticked.png" % tag)
			if is_equal_approx(f, 2.0) and n.scroll.focus_mode == Control.FOCUS_ALL:
				n.scroll.grab_focus()
				var pd := InputEventKey.new()
				pd.keycode = KEY_PAGEDOWN
				pd.physical_keycode = KEY_PAGEDOWN
				pd.pressed = true
				root.push_input(pd)
				await process_frame
				await process_frame
				print("  words scrolled by Page Down to %d" % n.scroll.scroll_vertical)
				await _save(out + "/flash-notice-%s-pagedown.png" % tag)
			n.free()
			if kind == "again":
				root.remove_child(under)
	under.free()
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved " + path)


## Pseudo-localisation: every text accented and 40 % longer, in brackets (where a label would be cut, it shows).
func _pseudo(n: Node) -> void:
	var acc := {"a": "á", "e": "é", "i": "í", "o": "ö", "u": "ü", "A": "Å", "E": "É", "O": "Ö", "c": "ç", "n": "ñ"}
	for c in n.find_children("*", "", true, false):
		if c is Label or c is Button:
			var t: String = c.text
			var o := ""
			for ch in t:
				o += acc.get(ch, ch)
			c.text = "[" + o + " " + "·".repeat(int(t.length() * 0.4)) + "]"
