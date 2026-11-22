## Screenshots of the photosensitivity notice where it is found again (app/flash_notice.gd, issue #443), to look at
## (not a test: it needs a display and the built plant):
##   tools/plant3d/bench/offscreen.sh godot --resolution 1600x900 --path apps/plant3d \
##     --script res://tests/flash_notice_settings_shots.gd -- --out=DIR [--phone] [--ui-size=2]
## (--phone and --ui-size as tests/no_flashes_shots.gd). The switch on (as the owner's check would have it); the notice
## kept as seen, so the plant loads at once; then the settings scrolled to "About flashing light"; the notice opened
## from it (Close, over the settings); its box ticked (the settings' row follows); About scrolled to its "Flashing
## light" section. The accessibility names of what is on screen are printed. Synthetic settings only (user:// is the
## shots' own under offscreen.sh).
extends SceneTree

const SimClock = preload("res://ui/sim_clock.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")
const SizeTest = preload("res://tests/test_ui_size.gd")
const FlashNotice = preload("res://app/flash_notice.gd")
const Quality = preload("res://app/quality.gd")

var out := ""
var phone := false
var ui_size := ""
var main: Node


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--ui-size="):
			ui_size = a.substr(10)
		elif a == "--phone":
			phone = true
	_run.call_deferred()


func shot(name: String, frames := 10) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var p := out.path_join("%s%s_%s.png" % ["phone_" if phone else "desk_", "ui" + (ui_size if ui_size != "" else "default"), name])
	print("shot %s: %d" % [p, root.get_viewport().get_texture().get_image().save_png(p)])


func _names(n: Node) -> void:
	for c in n.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and (c is BaseButton or c is ScrollContainer or c is PanelContainer) \
				and n.get_viewport().get_visible_rect().intersects(c.get_global_rect()):
			var nm: String = c.accessibility_name if c.accessibility_name != "" else (c.text if c is BaseButton else "")
			var d: String = c.accessibility_description
			print("  a11y %s %s \"%s\"%s %s" % [c.get_class(), c.name, nm, (" desc \"%s\"" % d) if d != "" else "",
					str(c.get_global_rect())])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FlashNotice.switch_override = 1
	var cf := Quality.settings()
	cf.set_value("ui", "flash_notice_seen", true)   # (the first start's notice is flash_notice_shots.gd's)
	cf.set_value("ui", "no_flashes", false)
	cf.set_value("ui", "reduced_motion", false)
	Quality.save(cf)
	Autosave.default_path = "user://shots-run.save"
	RunSave.remove(Autosave.default_path)
	main = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts["quality"] = "lean+vis" if phone else "full"
	if phone:
		main.opts["ui_scale"] = "1.35"
	if ui_size != "":
		main.opts["ui_size"] = ui_size
	root.add_child(main)
	while main.first_frame_ms < 0 and main.start_error == "":
		await process_frame
	main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	await SizeTest.new()._open(self, main, "settings")
	var b: Button = main.ui.flash_notice_btn
	if b == null:
		printerr("no About flashing light")
		quit(1)
		return
	b.grab_focus()
	main.hud.settings_scroll.ensure_control_visible(b)
	await process_frame
	print("canvas %s; About flashing light %s" % [str(root.get_visible_rect().size), str(b.get_global_rect())])
	await shot("settings_about_flashing_light")
	b.pressed.emit()
	await shot("notice_from_settings")
	_names(main.ui.flash_notice)
	main.ui.flash_notice.no_flashes.button_pressed = true
	await shot("notice_from_settings_ticked")
	main.ui.flash_notice.close()
	await process_frame
	await process_frame
	var row: CheckBox = main.hud.panel.find_child("setting_no_flashes", true, false)
	if row != null:
		main.hud.settings_scroll.ensure_control_visible(row)
		print("settings' row after the notice's box: %s; focus %s" % [str(row.button_pressed),
				str(root.gui_get_focus_owner().name if root.gui_get_focus_owner() else "none")])
	await shot("settings_after_notice")
	row.button_pressed = false
	main.hud.show_about()
	await process_frame
	var about = main.hud.about
	for c in about.body.get_children():
		if c is Label and c.text == FlashNotice.TITLE:
			about.scroll.ensure_control_visible(c)
			await process_frame
			about.scroll.scroll_vertical = int(c.position.y)
	await shot("about_flashing_light")
	main.free()
	RunSave.remove(Autosave.default_path)
	quit(0)
