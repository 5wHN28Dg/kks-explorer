## The player's phone (docs/plant3d/REALISM.md §8.5, milestone HS7): their own music through earbuds (a track of the
## generator's, ui/sound_player.gd play_music, which masks the plant while it plays), and the phone left at a locker
## or taken again. Its controls are a part of the Crew panel (ui/crew_panel.gd): keyboard, gamepad and touch as the
## panel's other buttons.
## - Playing a person, it sends the inputs (`audio` with the volume, `phone` at a locker) and follows the engine's
##   events: a refusal or the device held by whoever stopped the act stops the music; the phone given back at the
##   end of the duty is said. The music plays at once (the engine's word on it comes a step later, or with the
##   session's commit) unless the phone is known to be held or left. Once no input of the phone's is on its way
##   (its event came, or WAIT steps went by: a host may drop an input), the phone follows the engine's own state
##   (sp_music, sp_phone): its volume, the music off, the phone left or held.
## - The sound player stopping the music by itself (its files loaded again, the plant gone) stops the phone too.
## - In free mode (no person, or no crews) the music just plays: no inputs, no rules.
## - The volume goes in steps of 10; 0 is off.
extends RefCounted

const W = preload("res://ui/widgets.gd")

const STEP := 10
const CARRIED := 1              # the engine's phone states (sp_phone): 1 carried, 0 left at a locker, 2 held
const LEFT := 0
const HELD := 2
const WAIT := 30                # model steps an input of the phone's is waited for before the engine's state rules

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
var _wait_to := -1              # the step until which an input of the phone's is waited for (-1: none on its way)


func setup(u) -> void:
	ui = u
	_pick()
	if ui.sounds != null:
		ui.sounds.music_ended.connect(_ended)


## The sound player stopped the music itself (ui/sound_player.gd music_ended: its index loaded again, the plant gone):
## the phone is stopped too, and a person's engine told (it plays nothing any more).
func _ended() -> void:
	if not playing:
		return
	playing = false
	if person() != -1 and ui.is_inside_tree() and ui.clock != null and ui.clock.engine != null:
		_send(0)
	show()


## An `audio` input, waited for (WAIT) before the engine's own state is followed again.
func _send(v: int) -> void:
	ui.inputs.audio(v)
	_wait_to = ui.clock.engine.step_no + WAIT


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
		_send(0)
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
			_send(volume)
	ui.sounds.play_music(track, volume)
	show()


## Every quarter second (ui/plant_ui.gd): another engine or person reads the phone again (a person taken while the
## music plays tells the engine); then, playing a person, the phone follows the engine's state (follow_engine).
func tick() -> void:
	var e = ui.clock.engine
	var pi := person()
	if e != _engine or pi != _person:
		_engine = e
		_person = pi
		state = CARRIED
		held_by = ""
		_wait_to = -1
		if pi != -1 and playing and _engine_volume(e, pi) == 0 and engine_state() == CARRIED:
			_apply(true)
	if pi != -1:
		follow_engine()


## The engine's music volume for person pi (-1 when the engine keeps none).
static func _engine_volume(e, pi: int) -> int:
	var sm = e.get("sp_music") if e != null else null
	return int(sm[pi]) if sm != null and sm.size() > pi else -1


## The phone in agreement with the engine (REALISM.md §8.5; the engine rules: a session's host may have dropped an
## input, a loaded run or a session's engine has its own): once no input of the phone's is on its way, the music
## plays at the engine's volume or not at all, and a phone left or held plays nothing.
func follow_engine() -> void:
	var e = ui.clock.engine
	var pi := person()
	var v := _engine_volume(e, pi)
	if pi == -1 or v == -1 or (_wait_to != -1 and e.step_no < _wait_to):
		return
	_wait_to = -1
	var st := engine_state()
	if st != CARRIED or v == 0:
		if playing:
			playing = false
			ui.sounds.stop_music()
			if st != CARRIED:
				_say(_state_words(st))
			else:
				show()
		return
	if not playing or v != volume or ui.sounds.music_volume != v:
		_pick()
		playing = true
		volume = v
		ui.sounds.play_music(track, volume)
		show()


## An event of the run (ui/plant_ui.gd _follow_events): the person played's own audio, phone, held and returned.
func on_event(ev: Array) -> void:
	var me = _me_id()
	if me == null or ev.size() < 3 or ev[2] != me:
		return
	var sm = ui.clock.engine._sm
	match ev[1]:
		"audio":
			if ev[4] == "done" and int(ev[3]) == (volume if playing else 0):
				_wait_to = -1                   # the last input asked for came: the engine's state rules again
			if ev[4] == "refused":
				_wait_to = -1
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
