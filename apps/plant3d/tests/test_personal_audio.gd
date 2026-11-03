## Personal audio and the phone in the app (docs/plant3d/REALISM.md §8.5, milestone HS7):
## - masking: every plant sound plays on the bus "Plant", the phone's music on "Music", both into the master bus and
##   its limiter; while the music plays the Plant bus is at mask_db(volume) (−30 × (volume/100)^0.7), 0 dB when off;
## - the phone's part of the Crew panel: in free mode the music just plays and no input is sent; playing a person it
##   sends `audio` with the volume (in steps of 10, 0 when stopped) and, at a locker, `phone` leave; a `held` event
##   stops the music and says who holds the phone, `returned` that it is back;
## - the radio log: a message missed over the music is "Missed call from …" without its text, and so is a radio call
##   of the player's role (the follow-ups, 2026-11-03: the event missed with "call" last replaces the call's line);
## - the follow-ups: music off at the wheel (the engine's audio 0 with reason driving) and not played while driving;
##   the phone's words for a refusal away from a locker; held to the end of the next shift when taken off duty; the
##   debrief's words for music in the control room and a radio call missed;
## - zones say "No personal audio here" and "Ex zone: no phone" as they are entered;
## - the debrief's consequence ladder for 1, 2 and 3 stops and for a phone act stopped first, the calls missed and
##   the alarms raised while the music played;
## - the bus's engine: bound to the bus while it is out of its parked place (gain and pitch from its speed), stopped
##   when parked.
## The engine's own rules (who notices, when the device is held) are the vectors' (plant3d-realism.json, part audio);
## here the app's side, its events made by hand where the engine's would take a shift to come.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SoundPlayer = preload("res://ui/sound_player.gd")
const Debrief = preload("res://ui/debrief.gd")
const PlantUI = preload("res://ui/plant_ui.gd")
const UiParts = preload("res://tests/test_ui_parts.gd")
const Phone = preload("res://ui/phone.gd")
const PlantEngine = preload("res://sim/engine.gd")
const RunSave = preload("res://ui/run_save.gd")
const Autosave = preload("res://ui/autosave.gd")
const CrewPanelScript = preload("res://ui/crew_panel.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var dir := _sounds_dir()
	p += await _masking(tree, dir)
	p += _ladder()
	p += _zone_words()
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return p + ["the app or its scenario with the crews (shift_cold) did not start"]
	ui.sounds.load_index(dir)
	p += await _free_mode(tree, ui)
	p += await _person(tree, ui)
	p += await _vehicle(tree, ui)
	ui.sounds.stop_music()
	main.free()
	return p


## The generator's index with WAV files in a folder of the test's own: a loop, the horn, a one-shot, a footstep, the
## bus's engine and two tracks of music.
static func _sounds_dir() -> String:
	var dir := OS.get_user_data_dir().path_join("test_personal_audio")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["loop.wav", "once.wav", "music_a.wav", "music_b.wav"]:
		UiParts.wav(dir.path_join(f), 0.5)
	var loop := {"loop": true, "layers": [{"layer": "tones", "file": "loop.wav", "pitch": true}]}
	var once := {"loop": false, "layers": [{"layer": "once", "file": "once.wav", "pitch": false}]}
	var idx := {"format": "walkdown-plant-sound-files", "version": 1, "sounds": {
		"motor_large": loop, "horn_p1": loop, "breaker": once, "step_concrete": once, "bus_engine": loop},
		"music": {"music_a": {"title": "Track A", "file": "music_a.wav"},
			"music_b": {"title": "Track B", "file": "music_b.wav"}}}
	FileAccess.open(dir.path_join("index.json"), FileAccess.WRITE).store_string(JSON.stringify(idx))
	return dir


static func _bus_db(bn: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bn))


func _masking(tree: SceneTree, dir: String) -> Array:
	var p: Array = []
	for v in [[0, 0.0], [100, -30.0], [50, -30.0 * pow(0.5, 0.7)], [10, -30.0 * pow(0.1, 0.7)]]:
		if absf(SoundPlayer.mask_db(v[0]) - v[1]) > 1e-4:
			p.append("mask_db(%d) is %.3f dB, not %.3f" % [v[0], SoundPlayer.mask_db(v[0]), v[1]])
	var sp = SoundPlayer.new()
	tree.root.add_child(sp)
	sp.load_index(dir)
	for bn in [SoundPlayer.PLANT_BUS, SoundPlayer.MUSIC_BUS]:
		var i := AudioServer.get_bus_index(bn)
		if i == -1:
			p.append("no bus %s" % bn)
		elif AudioServer.get_bus_send(i) != &"Master":
			p.append("the bus %s sends to %s, not the master bus (its limiter)" % [bn, AudioServer.get_bus_send(i)])
	var master := AudioServer.get_bus_index("Master")
	var lim := false
	for k in AudioServer.get_bus_effect_count(master):
		lim = lim or AudioServer.get_bus_effect(master, k) is AudioEffectHardLimiter
	if not lim:
		p.append("the master bus has no limiter")
	if SoundPlayer.voice_bus() != SoundPlayer.PLANT_BUS:
		p.append("the players' voice would not be masked with the plant (voice_bus %s)" % SoundPlayer.voice_bus())
	# every plant sound on the Plant bus: the horn, a one-shot, a footstep, a bound loop
	sp.horn(1)
	sp.once("breaker")
	sp.footstep("concrete")
	var n := Node3D.new()
	sp.add_child(n)
	sp._start(n, "motor_large")
	var players: Array = sp.find_children("*", "AudioStreamPlayer", true, false) \
			+ sp.find_children("*", "AudioStreamPlayer3D", true, false)
	if players.size() < 4:
		p.append("the horn, a one-shot, a footstep and a loop made %d players" % players.size())
	for pl in players:
		if pl.bus != SoundPlayer.PLANT_BUS:
			p.append("a plant sound (%s) plays on the bus %s, not Plant" % [pl.stream.resource_path if pl.stream else "?", pl.bus])
	if absf(_bus_db(SoundPlayer.PLANT_BUS)) > 1e-4:
		p.append("the plant is lowered (%.2f dB) with no music playing" % _bus_db(SoundPlayer.PLANT_BUS))
	# the music: on its own bus at its volume, the plant masked by mask_db(volume); off again, unmasked
	var tracks: Array = sp.music_tracks()
	if tracks != [["music_a", "Track A"], ["music_b", "Track B"]]:
		p.append("the tracks listed are %s" % str(tracks))
	sp.play_music("music_a", 50)
	if not sp.music_playing() or sp._music == null or sp._music.bus != SoundPlayer.MUSIC_BUS:
		p.append("the music does not play on the Music bus")
	if absf(_bus_db(SoundPlayer.PLANT_BUS) - SoundPlayer.mask_db(50)) > 1e-3:
		p.append("at volume 50 the plant is at %.2f dB, not %.2f" % [_bus_db(SoundPlayer.PLANT_BUS), SoundPlayer.mask_db(50)])
	if absf(_bus_db(SoundPlayer.MUSIC_BUS) - linear_to_db(0.5)) > 1e-3:
		p.append("at volume 50 the music is at %.2f dB" % _bus_db(SoundPlayer.MUSIC_BUS))
	sp.play_music("music_a", 100)
	if absf(_bus_db(SoundPlayer.PLANT_BUS) + 30.0) > 1e-3:
		p.append("at full volume the plant is at %.2f dB, not -30" % _bus_db(SoundPlayer.PLANT_BUS))
	sp.stop_music()
	if sp.music_playing() or absf(_bus_db(SoundPlayer.PLANT_BUS)) > 1e-4:
		p.append("the music stopped leaves the plant at %.2f dB" % _bus_db(SoundPlayer.PLANT_BUS))
	sp.play_music("music_b", 30)
	sp.free()                           # (the next plant must not start masked)
	await tree.process_frame
	if absf(_bus_db(SoundPlayer.PLANT_BUS)) > 1e-4:
		p.append("a sound player gone with its music playing leaves the plant masked")
	return p


## The ladder from the run's events: [step, kind, …] as the engine makes them (REALISM.md §8.5).
func _ladder() -> Array:
	var p: Array = []
	var stop := func(kind): return [[10, "stop", "sup", "me", kind, "z", "done", []], [10, "held", "me", "sup"]]
	var on := [[1, "audio", "me", 60, "done", []]]
	for want in [[1, 0, "verbal warning"], [2, 1, "written warning"], [3, 2, "final written warning"], [4, 2, "final written warning"]]:
		var evs: Array = []
		for _k in want[0]:
			evs += on + stop.call("audio") + [[20, "returned", "me"]]
		var pa: Dictionary = Debrief.personal_audio("me", evs, evs.size())
		if pa.held != want[0] or pa.top != want[1]:
			p.append("%d stops: %d held, the highest rung %d (not %d)" % [want[0], pa.held, pa.top, want[1]])
		var text := "\n".join(Debrief.audio_lines(pa, 1))
		if not text.contains(String(want[2]).to_upper()):
			p.append("%d stops: the summary says %s, not the %s" % [want[0], text, want[2]])
	var first: PackedStringArray = Debrief.audio_lines(Debrief.personal_audio("me", on + stop.call("audio"), 3), 1)
	var t1 := "\n".join(first)
	for w in ["held to the end of the shift", "unsafe-act observation", "toolbox talk on personal audio"]:
		if not t1.contains(w):
			p.append("the first stop's consequence does not say \"%s\": %s" % [w, t1])
	var e3: Array = on + stop.call("audio") + on + stop.call("audio") + on + stop.call("audio")
	var t3 := "\n".join(Debrief.audio_lines(Debrief.personal_audio("me", e3, e3.size()), 1))
	for w in ["plant manager", "removal from site", "permit-to-work authorisations", "suspended"]:
		if not t3.contains(w):
			p.append("the third stop's consequence does not say \"%s\": %s" % [w, t3])
	# a phone carried into an Ex zone, stopped first: the written warning at once, then the final one
	var ph: Dictionary = Debrief.personal_audio("me", stop.call("phone"), 2)
	if ph.top != 1:
		p.append("a phone act stopped first is rung %d, not the written warning" % ph.top)
	var ph2: Dictionary = Debrief.personal_audio("me", stop.call("phone") + on + stop.call("audio"), 5)
	if ph2.rungs != [1, 2]:
		p.append("a phone act then music: rungs %s, not [1, 2]" % str(ph2.rungs))
	# a stop of the music while the player's phone act goes on (in an Ex zone): the device taken then is at least the
	# written warning, whatever the stop named; once that act has ended, the music's stop is the verbal one
	var ex_on := [[5, "unsafe", "me", "phone", "gas"], [5, "unsafe", "me", "audio", "gas"]]
	var during: Dictionary = Debrief.personal_audio("me", ex_on + stop.call("audio"), 4)
	if during.top != 1:
		p.append("a device taken while the phone act goes on is rung %d, not the written warning" % during.top)
	var after: Dictionary = Debrief.personal_audio("me", ex_on + [[8, "safe", "me", "phone", "gas"]] + stop.call("audio"), 5)
	if after.top != 0:
		p.append("a device taken after the phone act ended is rung %d, not the verbal warning" % after.top)
	# the person released (the engine turns their music off without an event): no alarm counted after it
	var rel: Dictionary = Debrief.personal_audio("me", [[1, "audio", "me", 60, "done", []], [2, "release", "me", "done", 0],
			[3, "alarm", "a1", "active_unack"]], 3)
	if rel.alarms != 0:
		p.append("an alarm raised after the person was released counts as raised while their music played")
	# someone else's device held counts nothing of the player's
	if Debrief.personal_audio("me", [[10, "held", "other", "sup"]], 1).held != 0:
		p.append("another person's device held counts as the player's")
	# the calls missed and the alarms raised while the music played (acknowledged 30 steps later); one raised before
	# the music, and one after it was turned off, are not counted
	var evs := [[1, "alarm", "a0", "active_unack"], [2, "audio", "me", 70, "done", []], [3, "missed", "me", "m1", "sup"],
		[5, "alarm", "a1", "active_unack"], [35, "alarm", "a1", "active_ack"], [36, "alarm", "a2", "active_unack"],
		[40, "audio", "me", 0, "done", []], [41, "alarm", "a3", "active_unack"], [42, "missed", "other", "m1", "sup"]]
	var pa: Dictionary = Debrief.personal_audio("me", evs, evs.size())
	if pa.missed != 1 or pa.alarms != 2 or pa.acks != [[5, 35], [36, -1]]:
		p.append("missed %d, alarms %d %s (want 1, 2 [[5, 35], [36, -1]])" % [pa.missed, pa.alarms, str(pa.acks)])
	var t := "\n".join(Debrief.audio_lines(pa, 10))
	if not t.contains("Calls missed over your music: 1") or not t.contains("acknowledged after 0:00:30, not yet"):
		p.append("the summary of missed calls and alarms: %s" % t)
	if not Debrief.audio_lines(Debrief.personal_audio("me", [], 0), 1).is_empty():
		p.append("a run without personal audio has a personal audio part")
	return p


func _zone_words() -> Array:
	var sm := {"d": {"audio": {"banned": ["hall", "gas"], "ex": ["gas"], "notice": [2, 10], "mask": 50}}}
	var p: Array = []
	if PlantUI.zone_audio_words(sm, "hall") != ". No personal audio here":
		p.append("entering a banned zone says %s" % PlantUI.zone_audio_words(sm, "hall"))
	if PlantUI.zone_audio_words(sm, "gas") != ". No personal audio here. Ex zone: no phone":
		p.append("entering an Ex zone says %s" % PlantUI.zone_audio_words(sm, "gas"))
	if PlantUI.zone_audio_words(sm, "yard") != "" or PlantUI.zone_audio_words({"d": {}}, "hall") != "":
		p.append("a zone without rules, or a run without `audio`, says something of personal audio")
	return p


## Free mode (no crews): the music plays from the Crew panel, and nothing goes to the engine.
func _free_mode(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var sent: Array = []
	ui.inputs.sink = func(item): sent.append(item)
	ui.open_crew()
	await tree.process_frame
	var play := App.find_button(ui.crew, "Play")
	if play == null:
		ui.inputs.sink = Callable()
		return ["no Play on the Crew panel's phone in free mode: %s" % App.texts(ui.crew).left(300)]
	play.pressed.emit()
	App.find_button(ui.crew, "Volume +").pressed.emit()
	await tree.process_frame
	if not ui.sounds.music_playing() or ui.sounds.music_volume != 60:
		p.append("in free mode the music does not play at 60 (%s, %d)" % [ui.sounds.music_playing(), ui.sounds.music_volume])
	if not App.texts(ui.crew).contains("Playing: Track A, volume 60"):
		p.append("the phone does not say what plays: %s" % App.texts(ui.crew).left(300))
	App.find_button(ui.crew, "Next track").pressed.emit()
	if ui.sounds.music_id != "music_b":
		p.append("Next track plays %s" % ui.sounds.music_id)
	App.find_button(ui.crew, "Stop").pressed.emit()
	if ui.sounds.music_playing():
		p.append("Stop leaves the music playing")
	# the sound player stopping the music by itself (its files loaded again): the phone says stopped
	App.find_button(ui.crew, "Play").pressed.emit()
	ui.sounds.load_index(ui.sounds.dir)
	ui.crew.refresh()
	if ui.phone.playing or not App.texts(ui.crew).contains("Music off") or App.find_button(ui.crew, "Play") == null:
		p.append("the sounds loaded again leave the phone playing: %s" % App.texts(ui.crew).left(300))
	if not sent.is_empty():
		p.append("free mode sent inputs: %s" % str(sent))
	ui.inputs.sink = Callable()
	ui.close_crew()
	return p


## Playing a person: the inputs, the locker, the device held and given back, a missed call in the radio log.
func _person(tree: SceneTree, ui) -> Array:
	var p: Array = []
	ui.start_shift("shift_cold")
	await tree.process_frame
	ui.open_crew()
	var b := App.find_button(ui.crew, "Play Field CW, crew A…")
	if b == null:
		return ["the shift's start offers no crew A CW field operator: %s" % App.texts(ui.crew).left(300)]
	b.pressed.emit()
	var e = ui.clock.engine
	var sm = e._sm
	var me: int = e.trainee()
	if me == -1:
		return ["the role was not taken"]
	var me_id: String = sm.people[me]["id"]
	var sent: Array = []
	ui.inputs.sink = func(item): sent.append(item)
	ui.crew._sig = ""
	ui.crew.refresh()
	await tree.process_frame
	var v0: int = ui.phone.volume           # (the volume picked in free mode, kept)
	App.find_button(ui.crew, "Play").pressed.emit()
	App.find_button(ui.crew, "Volume +").pressed.emit()
	App.find_button(ui.crew, "Volume −").pressed.emit()
	App.find_button(ui.crew, "Volume −").pressed.emit()
	App.find_button(ui.crew, "Stop").pressed.emit()
	if str(sent) != str([["audio", v0], ["audio", v0 + 10], ["audio", v0], ["audio", v0 - 10], ["audio", 0]]):
		p.append("the phone sent %s" % str(sent))
	if App.find_button(ui.crew, "Leave the phone here") != null:
		p.append("the phone can be left away from a locker")
	ui.inputs.sink = Callable()
	# at the locker: Leave the phone here sends `phone` leave
	ui.go_to_locker()
	ui._place_tick()
	ui.clock.run_steps(2)
	if not ui.at_locker():
		p.append("the walker did not reach a locker")
	else:
		sent.clear()
		ui.inputs.sink = func(item): sent.append(item)
		ui.crew._sig = ""
		ui.crew.refresh()
		var lv := App.find_button(ui.crew, "Leave the phone here")
		if lv == null:
			p.append("no Leave the phone here at the locker: %s" % App.texts(ui.crew).left(400))
		else:
			lv.pressed.emit()
			if str(sent) != str([["phone", "leave"]]):
				p.append("leaving the phone sent %s" % str(sent))
		ui.inputs.sink = Callable()
	# the device held by whoever stopped the act: the music stops, the phone says who has it until the shift's end
	var sup := -1
	for qi in sm.people.size():
		if qi != me and sm.people[qi]["role"] == "shift_sup":
			sup = qi
			break
	var sup_id: String = sm.people[sup]["id"]
	var sup_call: String = sm.people[sup]["call"]
	ui.inputs.sink = func(_item): pass         # (the music asked for, not given to the engine: the test makes its events)
	ui.phone.play()
	if not ui.sounds.music_playing():
		p.append("playing a person, the music does not play")
	e.events.append([e.step_no, "stop", sup_id, me_id, "audio", "turbine_hall", "done", []])
	e.events.append([e.step_no, "held", me_id, sup_id])
	ui._sync_events()
	var want := "Your phone is with %s until the end of your shift" % sup_call
	if ui.sounds.music_playing() or ui.phone.playing:
		p.append("the device held leaves the music playing")
	if not ui._toast.text.contains(want):
		p.append("the device held says %s, not \"%s\"" % [ui._toast.text, want])
	ui.crew.refresh()
	if not App.texts(ui.crew).contains(want):
		p.append("the phone's part does not say who holds it: %s" % App.texts(ui.crew).left(400))
	e.events.append([e.step_no, "returned", me_id])
	ui._sync_events()
	if not ui._toast.text.contains("Your phone is back"):
		p.append("the phone given back says %s" % ui._toast.text)
	# a refusal stops the music too
	ui.phone.state = Phone.CARRIED
	ui.phone.play()
	e.events.append([e.step_no, "audio", me_id, 50, "refused", ["held"]])
	ui._sync_events()
	if ui.sounds.music_playing():
		p.append("a refused `audio` leaves the music playing")
	ui.inputs.sink = Callable()
	# the radio: a message to the player said, then missed over the music: who called, without the text
	var msg: String = sm.messages.keys()[0]
	var text: String = sm.messages[msg]
	e.events.append([e.step_no, "say", sup_id, msg, sm.people[me]["role"]])
	ui.crew._sig = ""
	ui.crew.refresh()
	var heard := App.texts(ui.crew)
	if not heard.contains(text):
		p.append("a message heard is not in the radio log with its text")
	e.events.append([e.step_no, "say", sup_id, msg, sm.people[me]["role"]])
	e.events.append([e.step_no, "missed", me_id, msg, sup_id])
	ui.crew.refresh()
	var log: Array = ui.crew._radio
	if not String(log[log.size() - 1]).ends_with("Missed call from %s" % sup_call):
		p.append("the radio's last line is %s, not a missed call from %s" % [log[log.size() - 1], sup_call])
	if String(log[log.size() - 1]).contains(text):
		p.append("a missed call shows its text")
	if String(log[log.size() - 2]).contains("Missed call"):
		p.append("the message heard before became a missed call")
	var shown := App.texts(ui.crew)
	if not shown.contains("Missed call from %s" % sup_call):
		p.append("the radio on the panel does not show the missed call")
	p += _followups(ui, e, me, sup_id, sup_call)
	p += _follows_engine(ui, e, me)
	p += _saved_audio(ui, e)
	ui.close_crew()
	return p


## The phone-music follow-ups (the user, 2026-11-03): a radio call missed, music at the wheel, the locker, the hold's
## end, the control room.
func _followups(ui, e, me: int, sup_id: String, sup_call: String) -> Array:
	var p: Array = []
	var sm = e._sm
	var me_id: String = sm.people[me]["id"]
	var role: String = sm.people[me]["role"]
	# a radio call of the player's role missed: its line becomes "Missed call from …", without the task
	var task: String = ""
	for t in sm.tasks:
		if String(sm.tasks[t].get("title", "")) != "":
			task = t
			break
	e.events.append([e.step_no, "call", sup_id, role, task, null, "done"])
	ui.crew._sig = ""
	ui.crew.refresh()
	var n: int = ui.crew._radio.size()
	if not String(ui.crew._radio[n - 1]).contains(sm.tasks[task]["title"]):
		p.append("a radio call heard is not in the radio log with its task")
	e.events.append([e.step_no, "missed", me_id, task, sup_id, "call"])
	ui.crew.refresh()
	var log: Array = ui.crew._radio
	if log.size() != n or not String(log[n - 1]).ends_with("Missed call from %s" % sup_call):
		p.append("a radio call missed: the radio's last line is %s (%d lines, not %d)" % [log[log.size() - 1], log.size(), n])
	var dt := Debrief.audio_text(sm, [0, "missed", me_id, task, sup_id, "call"], me_id, -1)
	if not dt.begins_with("Missed radio call from %s" % sup_call):
		p.append("the debrief's line for a radio call missed: %s" % dt)
	# at the wheel: the engine turned the music off (taking the driver's seat), and the phone says why
	ui.inputs.sink = func(_item): pass
	ui.phone.state = Phone.CARRIED
	ui.phone.play()
	e.events.append([e.step_no, "audio", me_id, 0, "done", ["driving"]])
	ui._sync_events()
	if ui.sounds.music_playing() or ui.phone.playing:
		p.append("the music plays on at the wheel")
	if not ui._toast.text.contains("No earbuds at the wheel"):
		p.append("the music off at the wheel says %s" % ui._toast.text)
	if not Debrief.audio_text(sm, [0, "audio", me_id, 0, "done", ["driving"]], me_id, -1).contains("at the wheel"):
		p.append("the debrief does not say the music went off at the wheel")
	# driving the bus's run: the phone neither sends the music nor plays it
	var sent: Array = []
	ui.inputs.sink = func(item): sent.append(item)
	e.st_veh.append({"driver": me})
	ui.phone.play()
	e.st_veh.pop_back()
	if not sent.is_empty() or ui.sounds.music_playing():
		p.append("driving, the phone sent %s or played the music" % str(sent))
	ui.inputs.sink = Callable()
	# refusals' words: away from a locker, at the wheel
	if not ui.phone.refusal(["locker"]).contains("locker") or not ui.phone.refusal(["driving"]).contains("wheel"):
		p.append("the phone's words for locker and driving refusals: %s / %s" % [ui.phone.refusal(["locker"]),
				ui.phone.refusal(["driving"])])
	# held: to the end of this shift on duty, of the next one taken off duty, for good with no next duty
	var held_was: int = e.sp_held_to[me]
	var on_was: int = e.sp_on[me]
	var duty_was: Array = e.sp_duty[me]
	e.sp_on[me] = 1
	e.sp_duty[me] = [0, 5000]
	e.sp_held_to[me] = 5000
	var w1: String = ui.phone.held_until()
	e.sp_on[me] = 0
	e.sp_held_to[me] = 9000
	var w2: String = ui.phone.held_until()
	e.sp_held_to[me] = 1 << 62
	var w3: String = ui.phone.held_until()
	e.sp_held_to[me] = held_was
	e.sp_on[me] = on_was
	e.sp_duty[me] = duty_was
	if w1 != "until the end of your shift" or w2 != "until the end of your next shift" or w3 != "for the rest of the run":
		p.append("held until: %s / %s / %s" % [w1, w2, w3])
	# the control room (audio.rooms): the act's words name the room
	var ct := Debrief.safety_text(sm, [0, "unsafe", me_id, "audio", "control_room"])
	if not ct.contains("listening to music in the control room"):
		p.append("the debrief's words for music in the control room: %s" % ct)
	if not CrewPanelScript.act_text(sm, 3, ["control_room"]).contains("music in the control room"):
		p.append("the crew panel's words for music in the control room: %s" % CrewPanelScript.act_text(sm, 3, ["control_room"]))
	if sm.audio_rooms != ["control_room"]:
		p.append("the first train bans music in the control room: %s" % str(sm.audio_rooms))
	return p


## The phone follows the engine once its own input is no longer on its way: an input the host dropped (the engine's
## music off), the engine's volume, the device held; the sound player stopping the music tells the engine.
func _follows_engine(ui, e, me: int) -> Array:
	var p: Array = []
	var sent: Array = []
	ui.inputs.sink = func(item): sent.append(item)         # (dropped: never reaches the engine)
	ui.phone.state = Phone.CARRIED
	ui.phone.play()
	ui.phone.follow_engine()
	if not ui.phone.playing:
		p.append("the phone stopped before its input could have reached the engine")
	ui.clock.run_steps(Phone.WAIT + 1)
	ui.phone.follow_engine()
	if ui.phone.playing or ui.sounds.music_playing():
		p.append("the phone plays on although the engine never took its input (music %d)" % e.sp_music[me])
	e.sp_music[me] = 70                 # the engine's own state (a loaded run, a session's engine)
	ui.phone.follow_engine()
	if not ui.phone.playing or ui.sounds.music_volume != 70 or ui.phone.volume != 70:
		p.append("the engine's music at 70 is not followed: %s at %d" % [ui.phone.playing, ui.sounds.music_volume])
	e.sp_phone[me] = Phone.HELD
	ui.phone.follow_engine()
	if ui.phone.playing or ui.sounds.music_playing() or not ui._toast.text.contains("Your phone is with"):
		p.append("the engine's phone held is not followed: %s, %s" % [ui.phone.playing, ui._toast.text])
	e.sp_phone[me] = Phone.CARRIED
	ui.phone.follow_engine()
	if not ui.phone.playing:
		p.append("the phone given back by the engine with its music on is not followed")
	# the sound player stops the music itself: the phone stops and tells the engine
	sent.clear()
	ui.sounds.load_index(ui.sounds.dir)
	if ui.phone.playing or str(sent) != str([["audio", 0]]):
		p.append("the sounds loaded again: the phone %s, sent %s" % ["plays on" if ui.phone.playing else "stopped", str(sent)])
	e.sp_music[me] = 0
	ui.inputs.sink = Callable()
	return p


## A saved run's personal audio is checked as the rest of the engine's state (ui/autosave.gd): its own taken, each
## field damaged refused.
func _saved_audio(ui, e) -> Array:
	var p: Array = []
	var fresh = PlantEngine.new(ui.model, "shift_cold")
	var cap := RunSave.capture(e, RunSave.engine_fields(e))
	var why: String = Autosave._engine_contents(fresh, cap)
	if why != "":
		return ["a run's own save is refused: %s" % why]
	if cap.get("sp_aud", []).is_empty() or cap.get("sp_watch", []).is_empty():
		return ["the first train's run has no noticing streams or observers to save"]
	var bad := []
	for k in [["sp_music", 101], ["sp_music", -1], ["sp_phone", 3], ["sp_told", 4], ["sp_held_to", -2], ["sp_aud", 0]]:
		var a = cap[k[0]].duplicate()
		a[0] = k[1]
		bad.append({k[0]: a})
	var short = cap["sp_music"].duplicate()
	short.resize(short.size() - 1)
	bad.append({"sp_music": short})
	for wk in [Vector2i(0, 7), Vector2i(-1, 3), "x"]:
		var w: Array = cap["sp_watch"].duplicate(true)
		w[0] = {wk: {}}
		bad.append({"sp_watch": w})
	var w2: Array = cap["sp_watch"].duplicate(true)
	w2[0] = {Vector2i(0, 3): {"q": 5}}
	bad.append({"sp_watch": w2})
	for c in bad:
		var t := cap.duplicate()
		t.merge(c, true)
		if Autosave._engine_contents(fresh, t) == "":
			p.append("a save with %s was taken" % str(c).left(120))
	return p


## The bus's engine: heard while the bus is out of its parked place, its gain and pitch from the speed; silent parked.
func _vehicle(tree: SceneTree, ui) -> Array:
	var p: Array = []
	var vv = ui.vehicles
	if vv == null or vv.vehicles.is_empty():
		return ["no vehicle drawn"]
	var V: Dictionary = vv.vehicles[0]
	var body: Node3D = V["body"]
	var parked: Transform3D = V["parked"]
	ui.sounds.listener_at = body.global_position
	vv._engine(V, 0.1)
	if ui.sounds.vehicles_heard.has(body):
		p.append("the parked bus's engine is heard")
	# driven 1 m in a tenth of a second (10 m/s), a few times: the engine on, on the Plant bus, louder and higher
	for k in 6:
		vv._put(V, Transform3D(parked.basis, parked.origin + Vector3(1.0 + k, 0, 0)), false)
		ui.sounds.listener_at = body.global_position
		vv._engine(V, 0.1)
	var ps: Array = ui.sounds.vehicles_heard.get(body, [])
	if ps.is_empty():
		p.append("the moving bus's engine is not heard")
	else:
		var want: Vector2 = SoundPlayer.engine_level(V["speed"])
		var pl: AudioStreamPlayer3D = ps[0][0]
		if pl.get_parent() != body or pl.bus != SoundPlayer.PLANT_BUS:
			p.append("the engine is not played on the bus's body on the Plant bus")
		if absf(pl.volume_db - linear_to_db(want.x)) > 1e-3 or absf(pl.pitch_scale - want.y) > 1e-4:
			p.append("the engine at %.1f m/s plays at %.2f dB, pitch %.3f, not %.2f, %.3f" % [V["speed"], pl.volume_db,
					pl.pitch_scale, linear_to_db(want.x), want.y])
		if V["speed"] < 5.0 or want.x <= SoundPlayer.engine_level(0.0).x or want.y <= 1.0:
			p.append("the engine does not follow the speed (%.1f m/s: %s)" % [V["speed"], str(want)])
	# placed, not driven: a jump far away (a session's resync), or placed by the run (a load, a jump): no speed heard
	var sp0: float = V["speed"]
	vv._put(V, Transform3D(parked.basis, parked.origin + Vector3(600.0, 0, 0)), false)
	vv._engine(V, 0.1)
	if absf(V["speed"] - sp0) > 1e-6:
		p.append("a jump of 600 m in a frame was heard as speed (%.1f m/s, from %.1f)" % [V["speed"], sp0])
	vv._put(V, Transform3D(parked.basis, parked.origin + Vector3(6.0, 0, 0)), true)
	vv._engine(V, 0.1)
	if V["speed"] != 0.0:
		p.append("the bus placed by the run is heard at %.1f m/s" % V["speed"])
	# out of earshot: stopped
	ui.sounds.listener_at = body.global_position + Vector3(0, 0, SoundPlayer.EARSHOT + 10.0)
	vv._engine(V, 0.1)
	if ui.sounds.vehicles_heard.has(body):
		p.append("the engine plays out of earshot")
	# parked again: stopped
	ui.sounds.listener_at = body.global_position
	vv._engine(V, 0.1)
	vv._put(V, parked, true)
	vv._engine(V, 0.1)
	await tree.process_frame
	if ui.sounds.vehicles_heard.has(body) or not body.find_children("*", "AudioStreamPlayer3D", true, false).filter(
			func(x): return not x.is_queued_for_deletion()).is_empty():
		p.append("the parked bus's engine still plays")
	return p
