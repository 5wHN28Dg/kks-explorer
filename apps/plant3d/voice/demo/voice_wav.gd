## wdp_voice's test scene (decision 0069, milestone MP5): reads a WAV (`--wav=PATH`; by default a speech-like signal
## made here and written to user://voice_in.wav first, so the WAV path is used either way), encodes it 20 ms at a time,
## decodes it, writes user://voice_out.wav, prints the round trip's delay, level and SNR and the time per 20 ms frame
## (`VOICE` lines: the phone's log), and quits.
##   godot --path apps/plant3d res://voice/demo/voice_wav.tscn [-- --wav=FILE.wav]
##   on a phone: `voice=bench` in walk.txt (app/main.gd), the lines from `adb logcat -s godot`
## The microphone, push-to-talk and the radio come with MP2's session (MULTIPLAYER.md §8.4); this is the codec alone.
extends Node

const V = preload("res://voice/voice_check.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not V.available():
		print("VOICE unavailable: wdp_voice is not loaded on %s (voice/build.sh)" % OS.get_name())
		get_tree().quit(2)
		return
	var path := "user://voice_in.wav"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wav="):
			path = a.substr(6)
	if path == "user://voice_in.wav":
		V.write_wav(path, V.speech(48000, 4.0), 48000)
	var w := V.read_wav(path)
	if w.is_empty():
		print("VOICE cannot read %s (16-bit PCM WAV)" % path)
		get_tree().quit(1)
		return
	var frames: PackedVector2Array = w.frames
	var rate: int = w.rate
	print("VOICE %s on %s (%s), %s: %d frames at %d Hz" % [ClassDB.class_call_static("WdpVoiceEncoder", "opus_version"),
			OS.get_name(), OS.get_model_name(), path, frames.size(), rate])
	var rt := V.round_trip(frames, rate, rate)
	var c := V.compare(frames, rt.out, rate / 10)
	print("VOICE round trip: delay %.1f ms, level %.2f dB, SNR %.1f dB, %d packets, %.1f kbit/s" % [1000.0 * c.delay / rate,
			c.level_db, c.snr_db, rt.packets, rt.bytes * 8.0 / (frames.size() / float(rate)) / 1000.0])
	V.write_wav("user://voice_out.wav", rt.out, rate)
	# the time per frame from the input's rate to the output's (Godot's mix rate), as a session will run it; the
	# first pass warms the caches and the CPU's clock and is not counted
	var out_rate := int(AudioServer.get_mix_rate())
	V.bench(frames, rate, out_rate, 1)
	var b := V.bench(frames, rate, out_rate, 5)
	print("VOICE bench %s %s: encode %.3f ms (p95 %.3f), decode %.3f ms (p95 %.3f) per 20 ms frame, %d frames, %d Hz in, %d Hz out" % [
			OS.get_name(), OS.get_model_name(), b.encode_ms, b.encode_p95_ms, b.decode_ms, b.decode_p95_ms, b.frames, rate, out_rate])
	print("VOICE done")
	get_tree().quit(0)
