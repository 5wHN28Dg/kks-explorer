## Screenshots of the minimum GPU's message (app/min_gpu.gd), to look at (not a test: it needs a display):
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/min_gpu_shots.gd -- --out=DIR
## At the window's size, at UI sizes 100 %, 150 % and 200 %, with the focus on each control in turn (Tab), and its
## controls' rectangles and the colours printed (UI-UX-POLICY's evidence pack).
extends SceneTree

const MinGpu = preload("res://app/min_gpu.gd")
const W = preload("res://ui/widgets.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://min_gpu_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	MinGpu.renderer_override = "gl_compatibility"
	MinGpu.phone_override = 0
	MinGpu.switch_override = 1
	W.pick_scale()
	for f in [1.0, 1.5, 2.0]:
		W.apply_ui_size(root, f)
		var n = MinGpu.new(ConfigFile.new())
		root.add_child(n)
		for i in 6:
			await process_frame
		var vs := root.get_visible_rect().size
		print("ui size %d %%: canvas %s, window %s" % [roundi(f * 100), str(vs), str(root.size)])
		for c: Control in [n.panel, n.scroll, n.dont_show, n.continue_button, n.quit_button]:
			print("  %s %s" % [c.name, str(c.get_global_rect())])
		print("  words fit without scrolling: %s" % str(n.scroll.get_v_scroll_bar().max_value <= n.scroll.size.y + 1.0))
		var tag := "%s-%d" % [str(root.size.x) + "x" + str(root.size.y), roundi(f * 100)]
		await _save(out + "/min-gpu-%s.png" % tag)
		if is_equal_approx(f, 1.0):
			for k in 2:   # Tab to Quit, then to the box: the focus ring on each
				var ev := InputEventKey.new()
				ev.keycode = KEY_TAB
				ev.physical_keycode = KEY_TAB
				ev.pressed = true
				root.push_input(ev)
				await process_frame
				await process_frame
				print("  focus: %s" % str(root.gui_get_focus_owner().name if root.gui_get_focus_owner() else "none"))
				await _save(out + "/min-gpu-%s-tab%d.png" % [tag, k + 1])
		if is_equal_approx(f, 1.0):
			n.dont_show.button_pressed = true
			await _save(out + "/min-gpu-%s-ticked.png" % tag)
		n.free()
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved " + path)
