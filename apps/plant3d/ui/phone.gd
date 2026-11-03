## The player's phone (docs/plant3d/REALISM.md §8.5, milestone HS7): their own music through earbuds (a track of the
## generator's, ui/sound_player.gd play_music, which masks the plant while it plays), and the phone left at a locker
## or taken again. Its controls are a part of the Crew panel (ui/crew_panel.gd): keyboard, gamepad and touch as the
## panel's other buttons.
## - Playing a person, it sends the inputs (`audio` with the volume, `phone` at a locker) and follows the engine's
##   events: a refusal or the device held by whoever stopped the act stops the music; the phone given back at the
##   end of the duty is said. The music plays at once (the engine's word on it comes a step later, or with the
##   session's commit) unless the phone is known to be held or left.
## - In free mode (no person, or no crews) the music just plays: no inputs, no rules.
## - The volume goes in steps of 10; 0 is off.
extends RefCounted

const W = preload("res://ui/widgets.gd")

const STEP := 10
const CARRIED := 1              # the engine's phone states (sp_phone): 1 carried, 0 left at a locker, 2 held
const LEFT := 0
const HELD := 2

var ui                          # ui/plant_ui.gd
var track := ""                 # the track picked (an id of the generator's music)
var volume := 50                # the volume picked, 0–100
var playing := false            # the player asked for the music (and nothing has stopped it since)
var state := CARRIED            # the phone, as the events said (the engine's own when it can be read)
var held_by := ""               # the call sign of whoever holds it
var note := ""                  # the phone's last word, shown under its controls
var _engine = null              # the engine and person last looked at: another (a restart, a load, a role taken)
var _person := -1               # reads the phone's state again
var _status: Label = null       # the controls built into the Crew panel (build), updated in place (show)
var _play: Button = null
var _track: Button = null


func setup(u) -> void:
	ui = u
	_pick()


## A track of the build's music picked (the first) when none is, or the one picked is not there.
func _pick() -> void:
	var ts: Array = ui.sounds.music_tracks() if ui.sounds != null else []
	for t in ts:
		if t[0] == track:
			return
	track = ts[0][0] if not ts.is_empty() else ""


func person() -> int:
	return ui.my_person() if ui != null and ui.inputs != null else -1


func _me_id():
	var pi := person()
	return ui.clock.engine._sm.people[pi]["id"] if pi != -1 else null


## The engine's phone state for the person played, when the engine keeps it (sp_phone), else what the events said.
func engine_state() -> int:
	var e = ui.clock.engine
	var pi := person()
	var sp = e.get("sp_phone") if e != null else null
	if pi != -1 and sp != null and sp.size() > pi:
		return int(sp[pi])
	return state


func play() -> void:
	_pick()
	if track == "":
		_say("No music in this build.")
		return
	playing = true
	_apply(true)


func stop() -> void:
	var was := playing
	playing = false
	ui.sounds.stop_music()
	if was and person() != -1:
		ui.inputs.audio(0)
	show()


func toggle() -> void:
	if playing:
		stop()
	else:
		play()


func louder() -> void:
	set_volume(volume + STEP)


func softer() -> void:
	set_volume(volume - STEP)


func set_volume(v: int) -> void:
	volume = clampi(v, 0, 100)
	if playing:
		if volume == 0:
			stop()
			return
		_apply(true)
	show()


## The next track (the one playing changes at once; the engine knows only the volume).
func next_track() -> void:
	var ts: Array = ui.sounds.music_tracks()
	if ts.is_empty():
		return
	var k := 0
	for i in ts.size():
		if ts[i][0] == track:
			k = (i + 1) % ts.size()
	track = ts[k][0]
	if playing:
		ui.sounds.play_music(track, volume)
	show()


## The phone left at the locker the player stands at, or taken again (a person played, at a locker).
func leave() -> void:
	if person() != -1 and ui.at_locker():
		ui.inputs.phone("leave")


func take() -> void:
	if person() != -1 and ui.at_locker():
		ui.inputs.phone("take")


## The music as asked: in free mode it plays; playing a person, the input goes to the engine (`send`) and it plays
## unless the phone is known to be held or left (the engine refuses it then: its event says why).
func _apply(send: bool) -> void:
	var pi := person()
	if pi != -1:
		var st := engine_state()
		if st != CARRIED:
			playing = false
			ui.sounds.stop_music()
			_say(_state_words(st))
			return
		if send:
			ui.inputs.audio(volume)
	ui.sounds.play_music(track, volume)
	show()


## Every quarter second (ui/plant_ui.gd): another engine or person reads the phone again; a person taken while the
## music plays tells the engine.
func tick() -> void:
	var e = ui.clock.engine
	var pi := person()
	if e == _engine and pi == _person:
		return
	var new_engine: bool = e != _engine
	_engine = e
	_person = pi
	state = CARRIED
	held_by = ""
	if pi == -1:
		return                          # free mode: the music goes on as it is
	var sm = e.get("sp_music")
	if new_engine and sm != null and sm.size() > pi:
		# a loaded run or a session's engine: its music is the person's
		state = engine_state()
		if int(sm[pi]) > 0:
			volume = int(sm[pi])
			playing = true
			ui.sounds.play_music(track, volume)
		elif playing:
			_apply(true)
		show()
		return
	if playing:
		_apply(true)


## An event of the run (ui/plant_ui.gd _follow_events): the person played's own audio, phone, held and returned.
func on_event(ev: Array) -> void:
	var me = _me_id()
	if me == null or ev.size() < 3 or ev[2] != me:
		return
	var sm = ui.clock.engine._sm
	match ev[1]:
		"audio":
			if ev[4] == "refused":
				playing = false
				ui.sounds.stop_music()
				_say(refusal(ev[5]))
		"phone":
			if ev[4] == "done":
				state = LEFT if ev[3] == "leave" else CARRIED
				if ev[3] == "leave":
					playing = false
					ui.sounds.stop_music()
				_say("Your phone is in the locker." if ev[3] == "leave" else "You have your phone again.")
			else:
				_say(refusal(ev[5]))
		"held":
			state = HELD
			held_by = sm.people[sm.person_ix[ev[3]]]["call"] if sm.person_ix.has(ev[3]) else str(ev[3])
			playing = false
			ui.sounds.stop_music()
			_say("Your phone is with %s until the end of your shift." % held_by)
		"returned":
			state = CARRIED
			held_by = ""
			_say("Your phone is back: your shift has ended.")


func refusal(reasons) -> String:
	var r: Array = reasons if reasons is Array else []
	if "held" in r:
		return _state_words(HELD)
	if "left" in r:
		return _state_words(LEFT)
	if "no_audio" in r:
		return "No personal audio in this run."
	return "Refused."


func _state_words(st: int) -> String:
	if st == HELD:
		return "Your phone is with %s until the end of your shift." % (held_by if held_by != "" else "your supervisor")
	if st == LEFT:
		return "Your phone is in the locker: take it first."
	return ""


func _say(t: String) -> void:
	note = t
	if t != "":
		ui.toast(t)
	show()


# ------------------------------------------------------------------ its part of the Crew panel

## What the part's layout depends on (the Crew panel rebuilds when it changes): the phone's state and whether the
## player stands at a locker. The music's state and volume are written into it in place (show).
func sig() -> String:
	return "%d|%d|%s|%d" % [person(), engine_state(), str(person() != -1 and ui.at_locker()), track.length()]


func build(box: Container) -> void:
	box.add_child(W.label("Phone", 20, Color(1.0, 0.85, 0.4)))
	_status = W.label("", 18)
	box.add_child(_status)
	var row := HFlowContainer.new()
	box.add_child(row)
	_play = W.button("Play", func(): toggle())
	_play.name = "phone_play"
	row.add_child(_play)
	var down := W.button("Volume −", func(): softer())
	down.name = "phone_softer"
	row.add_child(down)
	var up := W.button("Volume +", func(): louder())
	up.name = "phone_louder"
	row.add_child(up)
	_track = W.button("Next track", func(): next_track())
	_track.name = "phone_track"
	row.add_child(_track)
	if person() != -1 and ui.at_locker():
		var st := engine_state()
		if st == CARRIED:
			var b := W.button("Leave the phone here", func(): leave())
			b.name = "phone_leave"
			row.add_child(b)
		elif st == LEFT:
			var b := W.button("Take the phone", func(): take())
			b.name = "phone_take"
			row.add_child(b)
	show()


## The part's texts now (the music, its volume, the phone's state, its last word).
func show() -> void:
	if _status == null or not is_instance_valid(_status):
		return
	_pick()
	var title := track
	for t in ui.sounds.music_tracks():
		if t[0] == track:
			title = t[1]
	var st := engine_state() if person() != -1 else CARRIED
	var line := ""
	if st != CARRIED:
		line = _state_words(st)
	elif track == "":
		line = "No music in this build."
	else:
		line = "%s: %s, volume %d" % ["Playing" if playing else "Music off", title, volume]
	if note != "" and note != line:
		line += "\n" + note
	_status.text = line
	if is_instance_valid(_play):
		_play.text = "Stop" if playing else "Play"
