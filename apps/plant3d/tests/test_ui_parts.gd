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
	wav(dir.path_join("breaker.once.wav"), 0.2)
	wav(dir.path_join("breaker_open.once.wav"), 0.3)
	wav(dir.path_join("surge_thud.once.wav"), 0.4)
	var idx := {"format": "walkdown-plant-sound-files", "version": 1, "sounds": {
		"motor_large": {"loop": true, "layers": [{"layer": "mains", "file": "motor_large.tones.wav", "pitch": false},
			{"layer": "tones", "file": "motor_large.tones.wav", "pitch": true}]},
		"breaker": {"loop": false, "layers": [{"layer": "once", "file": "breaker.once.wav", "pitch": false}]},
		"breaker_open": {"loop": false, "layers": [{"layer": "once", "file": "breaker_open.once.wav", "pitch": false}]},
		"surge_thud": {"loop": false, "layers": [{"layer": "once", "file": "surge_thud.once.wav", "pitch": false}]},
		"horn_p1": {"loop": true, "layers": [{"layer": "tones", "file": "horn_p1.tones.wav"}]},
		"horn_p2": {"loop": true, "layers": [{"layer": "tones", "file": "horn_p1.tones.wav"}]}}}
	FileAccess.open(dir.path_join("index.json"), FileAccess.WRITE).store_string(JSON.stringify(idx))
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
	if players.size() < 2:
		p.append("the running pump's two layers don't play within earshot (%d players)" % players.size())
	else:
		var want := linear_to_db(maxf(ui.clock.engine.v("cw_a_spd"), 1e-5))
		if absf((players[0] as AudioStreamPlayer3D).volume_db - want) > 0.01:
			p.append("the pump's sound is at %.2f dB, not its speed's %.2f dB" % [players[0].volume_db, want])
		# the mains hum is never pitched; the other layer follows the binding's pitch (here made 0.7 whatever the speed)
		for b in ui.sounds._bound:
			if b[0] == pump:
				b[3] = 0.7
		for i in 12:
			await tree.process_frame
		for pl in ui.sounds._bound.filter(func(b): return b[0] == pump)[0][4]:
			var want_pitch := 0.7 if pl[1].get("pitch", true) else 1.0
			if absf(pl[0].pitch_scale - want_pitch) > 1e-6:
				p.append("the pump's %s layer plays at pitch %.3f, not %.1f" % [pl[1]["layer"], pl[0].pitch_scale, want_pitch])
	# a breaker's contacts: a one-shot when they close (format 1 binds no edge: the app watches the value)
	var brk: Node3D = ui.index.nodes["10BAC10"]
	ui.player.set_mode(ui.player.Mode.FLY)
	ui.player.global_position = brk.global_position + Vector3(0, 1, 3)
	for i in 10:
		await tree.process_frame
	var close_s = ui.sounds._stream("breaker.once.wav", false)
	var open_s = ui.sounds._stream("breaker_open.once.wav", false)
	var playing := func(st): return brk.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(x): return x.stream == st).size()
	ui.clock.engine.cur[ui.clock.engine.ix["gt1_brk_cmd"]] = 1.0
	ui.sounds.on_step()
	if playing.call(close_s) != 1 or playing.call(open_s) != 0:
		p.append("closing the breaker did not play the closing sound alone")
	ui.clock.engine.cur[ui.clock.engine.ix["gt1_brk_cmd"]] = 0.0
	ui.sounds.on_step()
	if playing.call(open_s) != 1:
		p.append("opening the breaker did not play the opening sound")
	ui.player.global_position = Vector3(-200, 0, 0)
	for i in 30:
		await tree.process_frame
	if not pump.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(x): return not x.is_queued_for_deletion()).is_empty():
		p.append("the pump's sound still plays out of earshot")
	# a pump started against an open valve: the surge that shakes the camera slams with a thud at the pump
	# (FIRST-TRAIN §4 step 4), once a surge, and not out of earshot
	var e = ui.clock.engine
	var surging: Array = ui.sounds._surges.map(func(sg): return String(sg[0].name))
	surging.sort()
	if surging != ["30PAC10AP001", "30PAC10AP002", "30PAC10AP003"]:
		p.append("the surges watched for a thud are %s, not the CW pumps' (a vibration never thuds)" % str(surging))
	var thud_s = ui.sounds._stream("surge_thud.once.wav", false)
	var thuds := func(): return pump.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(x): return x.stream == thud_s and not x.is_queued_for_deletion()).size()
	var surge: int = e.ix["cw_a_surge"]
	e.cur[surge] = 0.0
	ui.sounds.on_step()
	e.cur[surge] = 6.0
	ui.sounds.on_step()
	if thuds.call() != 0 or ui.sounds.played.get("surge_thud", 0) != 0:
		p.append("a surge's thud plays out of earshot")
	e.cur[surge] = 0.0
	ui.sounds.on_step()
	ui.player.global_position = ui.index.center("30PAC10AP001") + Vector3(0, 1.0, 4.0)
	for i in 10:
		await tree.process_frame
	e.cur[surge] = 0.5          # building up: 0.5 bar × 0.05 is below the slam
	ui.sounds.on_step()
	if thuds.call() != 0:
		p.append("a surge's thud plays before the surge")
	e.cur[surge] = 6.0
	ui.sounds.on_step()
	e.cur[surge] = 4.0          # dying down: the same surge
	ui.sounds.on_step()
	if thuds.call() != 1 or ui.sounds.played.get("surge_thud", 0) != 1:
		p.append("CW pump A's start surge did not play one thud at the pump (%d)" % thuds.call())
	e.cur[surge] = 0.0
	ui.sounds.on_step()
	e.cur[surge] = 6.0
	ui.sounds.on_step()
	if ui.sounds.played.get("surge_thud", 0) != 2:
		p.append("a second surge after the first had died down did not thud again")
	ui.sounds.reset_edges()     # a restarted plant seen mid-surge: no thud from the old run
	ui.sounds.on_step()
	if ui.sounds.played.get("surge_thud", 0) != 2:
		p.append("a restart in the middle of a surge played a thud")
	e.cur[surge] = 0.0
	ui.sounds.on_step()
	# and the model's own: pump A running from a start with its valve 60 % open (as the trainer's fault `cw_a_ls`
	# lets it start), stepped by the clock: one thud, through the app's step handler
	var cmd: int = e.ix["cw_a_cmd"]
	var vpos: int = e.ix["cw_a_v_pos"]
	var shook := 0.0
	var was: float = e.cur[vpos]
	e.cur[cmd] = 0.0             # (it runs from its start above, with its valve at its start position: stopped first)
	ui.clock.run_steps(5)
	e.cur[vpos] = 0.6
	e.cur[cmd] = 1.0
	for i in 40:
		ui.clock.run_steps(1)
		shook = maxf(shook, e.cur[surge])
	if ui.sounds.played.get("surge_thud", 0) != 3:
		p.append("the model's surge (%.1f bar) at CW pump A played %d thuds, not one" % [shook,
			ui.sounds.played.get("surge_thud", 0) - 2])
	# stopped and started again 4 s later, the last surge still dying away (about 1 bar): it slams again
	e.cur[cmd] = 0.0
	ui.clock.run_steps(40)
	var left: float = e.cur[surge]
	e.cur[cmd] = 1.0
	ui.clock.run_steps(40)
	if ui.sounds.played.get("surge_thud", 0) != 4:
		p.append("a restart against the open valve with the last surge at %.1f bar played %d thuds, not one" % [left,
			ui.sounds.played.get("surge_thud", 0) - 3])
	e.cur[vpos] = was            # running on as before
	ui.clock.run_steps(200)
	if e.cur[surge] >= 0.2 or ui.sounds.played.get("surge_thud", 0) != 4:
		p.append("the surge did not die down without another thud (%.2f bar)" % e.cur[surge])
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
