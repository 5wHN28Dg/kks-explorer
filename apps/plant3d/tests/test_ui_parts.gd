## What the trainee sees and hears follow the model (docs/PLANT3D.md §7.7): a valve's disc turns with its position,
## a pump's running lamp lights, a local display shows its value up close; the plant's sounds play at their equipment
## within earshot, at the binding's gain, stop out of it, and the control room horn follows the alarms. The sounds
## come from the generator's index (tools/plant3d/sounds; a small WAV stands in for its files here).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SoundPlayer = preload("res://ui/sound_player.gd")


static func wav(path: String, seconds: float) -> void:
	var rate := 8000
	var n := int(rate * seconds)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + n * 2); f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16); f.store_16(1); f.store_16(1); f.store_32(rate); f.store_32(rate * 2); f.store_16(2); f.store_16(16)
	f.store_buffer("data".to_ascii_buffer()); f.store_32(n * 2)
	for i in n:
		f.store_16(int(8000 * sin(TAU * 200.0 * i / rate)) & 0xffff)


func run(tree: SceneTree) -> Array:
	var p: Array = []
	if absf(SoundPlayer.table(0.5, [[0, 0.5], [1, 1]]) - 0.75) > 1e-9 or SoundPlayer.table(2, [[0, 0], [1, 1]]) != 1.0 \
			or SoundPlayer.table(-1, [[0, 0.2], [1, 1]]) != 0.2:
		p.append("a sound's gain or pitch table is not read as a clamped piecewise-linear table")
	# the generator's index with WAV files in a folder of the test's own
	var dir := OS.get_user_data_dir().path_join("test_ui_sounds")
	DirAccess.make_dir_recursive_absolute(dir)
	wav(dir.path_join("motor_large.tones.wav"), 0.5)
	wav(dir.path_join("horn_p1.tones.wav"), 0.5)
	var idx := {"format": "walkdown-plant-sound-files", "version": 1, "sounds": {
		"motor_large": {"loop": true, "layers": [{"layer": "tones", "file": "motor_large.tones.wav"}]},
		"horn_p1": {"loop": true, "layers": [{"layer": "tones", "file": "horn_p1.tones.wav"}]},
		"horn_p2": {"loop": true, "layers": [{"layer": "tones", "file": "horn_p1.tones.wav"}]}}}
	FileAccess.open(dir.path_join("sounds.json"), FileAccess.WRITE).store_string(JSON.stringify(idx))
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return p + ["the interaction layer did not start"]
	ui.sounds.load_index(dir)
	ui.bindings.setup(ui.clock.engine, ui.index, ui.info, ui.player.camera)    # the bindings again, with sounds now
	await tree.process_frame
	# the valve's disc, the pump's lamp, the pressure gauge's display
	var valve: Node3D = ui.index.nodes["30PAC10AA101"]
	var disc: Node3D = valve.find_child("disc", true, false)
	var pump: Node3D = ui.index.nodes["30PAC10AP001"]
	var lamp: MeshInstance3D = pump.find_child("lamp_running", true, false)
	if disc == null or lamp == null:
		main.free()
		return p + ["no disc on CW pump A's valve or no running lamp on the pump"]
	var d0 := disc.transform
	var lamp_off: Material = lamp.material_override
	ui.go_control_room()
	ui.open_card("30PAC10AA101")
	var row := App.op_row(ui.card, "30PAC10AA101", "set")
	(row[4] as LineEdit).text = "15"
	(row[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	App.run_until(ui, "cw_a_vstart", 2000)
	ui.open_card("30PAC10AP001")
	(App.op_row(ui.card, "30PAC10AP001", "start")[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	App.run_until(ui, "cw_a_run", 200)
	ui.clock.run_steps(300)
	ui.player.set_mode(ui.player.Mode.FLY)
	ui.player.global_position = ui.index.center("30PAC10CP501") + Vector3(0, -1.0, 1.5)
	for i in 30:
		await tree.process_frame
	if disc.transform.is_equal_approx(d0):
		p.append("the valve's disc did not move with its position")
	if lamp.material_override == lamp_off:
		p.append("the running lamp did not light")
	var shows := []
	for c in ui.index.nodes["30PAC10CP501"].get_children():
		if c is Label3D and c.name == "ui_show":
			shows.append(c.text)
	if shows.is_empty() or not String(shows[0]).ends_with("bar"):
		p.append("the discharge pressure gauge shows %s up close" % str(shows))
	# the pump's motor sound plays near it, at the binding's gain (its speed), and stops far away
	var players := pump.find_children("*", "AudioStreamPlayer3D", true, false)
	if players.is_empty():
		p.append("no sound plays at the running pump within earshot")
	else:
		var want := linear_to_db(maxf(ui.clock.engine.v("cw_a_spd"), 1e-5))
		if absf((players[0] as AudioStreamPlayer3D).volume_db - want) > 0.01:
			p.append("the pump's sound is at %.2f dB, not its speed's %.2f dB" % [players[0].volume_db, want])
	ui.player.global_position = Vector3(-200, 0, 0)
	for i in 30:
		await tree.process_frame
	if not pump.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(x): return not x.is_queued_for_deletion()).is_empty():
		p.append("the pump's sound still plays out of earshot")
	# the horn: on with an unacknowledged priority 1 alarm, off when silenced
	ui.sounds.horn(1)
	if ui.sounds._horn == null or not ui.sounds._horn.playing:
		p.append("the horn does not sound for a priority 1 alarm")
	ui.sounds.horn(0)
	if ui.sounds._horn != null:
		p.append("the horn does not stop")
	ui.sounds.muted = true
	ui.sounds.horn(1)
	if ui.sounds._horn != null:
		p.append("the horn sounds while muted")
	ui.sounds.muted = false
	ui.sounds.horn(1)
	if ui.sounds._horn == null:
		p.append("the horn does not come back after unmuting")
	ui.sounds.horn(0)
	main.free()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	return p
