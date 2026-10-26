## wdp_voice, the voice codec (decision 0069, MULTIPLAYER.md §8, §12): a speech-like signal through the encoder and
## decoder at the mix rates Godot uses (16, 44.1 and 48 kHz) comes back with a small delay, its level and a minimum
## SNR; 10 % of the packets lost are concealed (better than silence in their place) and, with in-band FEC on,
## rebuilt better still; what comes from outside is refused safely (a rate out of range, an over-long or garbage
## packet, more than 30 s waiting to be encoded); and a 20 ms frame takes at most the budget's time (encode 1 ms,
## decode 0.3 ms: the Note 9's, §11; a desktop must be well inside it).
## Without the extension built for this machine (voice/build.sh linux-x86_64) this test says so and passes, unless
## WDP_VOICE_REQUIRED is set (CI, and build.sh when the library is there): then it fails.
extends RefCounted

const V = preload("res://voice/voice_check.gd")


func run(_tree: SceneTree) -> Array:
	var fails: Array = []
	if not V.available():
		if OS.get_environment("WDP_VOICE_REQUIRED") != "":
			return ["wdp_voice is not loaded (voice/build.sh linux-x86_64, then an import of the project)"]
		print("test_voice: wdp_voice is not built for this machine: nothing checked (voice/build.sh)")
		return []
	print("test_voice: %s" % ClassDB.class_call_static("WdpVoiceEncoder", "opus_version"))
	_round_trips(fails)
	_loss(fails)
	_bounds(fails)
	_bench(fails)
	return fails


## Clean round trips: the delay the codec and the two resamplers add (measured 6.4–6.5 ms), the level (-0.25 dB),
## the SNR at that delay (8.4–8.5 dB on this signal: Opus at 16 kbit/s keeps the sound, not the waveform), the
## length, and the bitrate staying near 16 kbit/s.
func _round_trips(fails: Array) -> void:
	for rate in [16000, 44100, 48000]:
		var sig := V.speech(rate, 3.0)
		var rt := V.round_trip(sig, rate, rate)
		if rt.is_empty():
			fails.append("%d Hz: the encoder or decoder did not set up" % rate)
			continue
		var c := V.compare(sig, rt.out, rate / 10)
		var delay_ms: float = 1000.0 * c.delay / rate
		var kbps: float = rt.bytes * 8.0 / 3.0 / 1000.0
		print("test_voice: %d Hz: delay %.1f ms, level %.2f dB, SNR %.1f dB, %.1f kbit/s, %d packets" % [rate, delay_ms,
				c.level_db, c.snr_db, kbps, rt.packets])
		if delay_ms < 2.0 or delay_ms > 15.0:
			fails.append("%d Hz: delay %.1f ms (2–15 expected)" % [rate, delay_ms])
		if absf(c.level_db) > 1.5:
			fails.append("%d Hz: level %.2f dB (within 1.5 dB expected)" % [rate, c.level_db])
		if c.snr_db < 6.0:
			fails.append("%d Hz: SNR %.1f dB (at least 6 expected)" % [rate, c.snr_db])
		if absi(rt.out.size() - sig.size()) > 2 * rate * V.FRAME_MS / 1000:
			fails.append("%d Hz: %d frames out for %d in" % [rate, rt.out.size(), sig.size()])
		if kbps < 6.0 or kbps > 18.0:
			fails.append("%d Hz: %.1f kbit/s (16 set)" % [rate, kbps])
		# (the resampler's own delay leaves the last 20 ms a few samples short at 44.1 and 48 kHz)
		var whole: int = sig.size() / (rate * V.FRAME_MS / 1000)
		if rt.packets != whole and rt.packets != whole - 1:
			fails.append("%d Hz: %d packets for %d ms" % [rate, rt.packets, sig.size() * 1000 / rate])


## 10 % of the packets lost (a fixed pattern): every lost one still gives 20 ms, nothing blows up, concealment fills
## the gaps with sound at about the speech's level, the decoder recovers after each, and in-band FEC rebuilds the
## lost frames better than concealment. At the spec's 16 kbit/s libopus 1.5.2 codes no FEC at all
## (its threshold at 10 % loss is about 15 kbit/s after its own discounts, measured: no packet carries any), so the
## FEC part runs at 24 kbit/s with 10 % expected loss, where it does.
func _loss(fails: Array) -> void:
	var rate := 48000
	var sig := V.speech(rate, 4.0)
	var frame := rate * V.FRAME_MS / 1000
	var lost := {}
	for i in sig.size() / frame:
		if (i * 7919) % 100 < 10:
			lost[i] = true
	var clean := V.round_trip(sig, rate, rate)
	var plc := V.round_trip(sig, rate, rate, lost)
	if clean.is_empty() or plc.is_empty():
		fails.append("loss: no codec")
		return
	if plc.out.size() != clean.out.size():
		fails.append("loss: %d frames out with %d packets lost, %d without loss" % [plc.out.size(), lost.size(), clean.out.size()])
	var peak := 0.0
	for f in plc.out:
		if is_nan(f.x) or is_inf(f.x):
			fails.append("loss: a sample is not a number")
			break
		peak = maxf(peak, absf(f.x))
	if peak > 1.0:
		fails.append("loss: the concealment peaks at %.2f" % peak)
	# concealment fills the gaps: in each lost 20 ms where the speech was sounding, the concealed output carries
	# energy near the clean decode's (silence would carry none); the decoder's output for packet i is
	# out[i * frame, (i + 1) * frame) at this rate, give or take the resampler's few samples. (A waveform SNR can't
	# judge concealment: an extrapolated pitch period a little out of phase scores below silence.)
	var ratios: Array = []
	for i in lost:
		var e_clean := 0.0
		var e_plc := 0.0
		for k in range(i * frame, mini((i + 1) * frame, clean.out.size())):
			e_clean += clean.out[k].x * clean.out[k].x
			e_plc += plc.out[k].x * plc.out[k].x
		if e_clean > 0.001 * frame:   # sounding: an RMS above about 0.03
			ratios.append(10.0 * log(maxf(e_plc, 1e-12) / e_clean) / log(10.0))
	var mid := V.median(ratios)
	print("test_voice: %d of %d packets lost: concealed energy %.1f dB from the clean decode's (median of the %d sounding)" % [
			lost.size(), plc.packets, mid, ratios.size()])
	if ratios.size() < 5 or not (mid > -10.0 and mid < 3.0):
		fails.append("loss: concealed frames carry %.1f dB of the clean decode's energy (-10 to +3 expected, %d frames)" % [mid, ratios.size()])
	# and the decoder recovers: outside the lost frames and the three after each (60 ms, while its predictors
	# settle: 6.3 dB with only one skipped, 7.7 with three, measured), the SNR is close to the clean one
	var c_clean := V.compare(sig, clean.out, rate / 10)
	var skip := {}
	for i in lost:
		skip[i] = true
		skip[i + 1] = true
		skip[i + 2] = true
		skip[i + 3] = true
	var a2 := PackedVector2Array()
	var b2 := PackedVector2Array()
	var d: int = c_clean.delay
	for i in sig.size() / frame:
		if skip.has(i):
			continue
		for k in range(i * frame, (i + 1) * frame):
			if k + d < plc.out.size():
				a2.append(sig[k])
				b2.append(plc.out[k + d])
	var c_rest := V.compare(a2, b2, 1)
	print("test_voice: SNR %.1f dB outside the lost frames, %.1f dB without loss" % [c_rest.snr_db, c_clean.snr_db])
	if c_rest.snr_db < c_clean.snr_db - 1.5:
		fails.append("loss: %.1f dB outside the lost frames, %.1f dB without loss: the decoder does not recover" % [c_rest.snr_db, c_clean.snr_db])
	# FEC: 16 kbit/s carries none; 24 kbit/s with 10 % expected loss does, and rebuilds the lost frames better
	var at16 := V.round_trip(sig, rate, rate, {}, false, 10)
	if at16.fec_packets != 0:
		print("test_voice: libopus now codes FEC at 16 kbit/s (%d packets): the note in MULTIPLAYER.md §8.3 can go" % at16.fec_packets)
	var fec_plc := V.round_trip(sig, rate, rate, lost, false, 10, 24000)
	var fec := V.round_trip(sig, rate, rate, lost, true, 10, 24000)
	var c_fp := V.compare(sig, fec_plc.out, rate / 10)
	var c_f := V.compare(sig, fec.out, rate / 10)
	print("test_voice: 24 kbit/s, 10 %% expected loss: %d of %d packets carry FEC; SNR %.1f dB with FEC, %.1f dB concealed" % [
			fec.fec_packets, fec.packets, c_f.snr_db, c_fp.snr_db])
	if fec.fec_packets < fec.packets / 2:
		fails.append("FEC: only %d of %d packets carry it at 24 kbit/s, 10 %% expected loss" % [fec.fec_packets, fec.packets])
	if not c_f.snr_db > c_fp.snr_db + 0.5:
		fails.append("FEC: %.1f dB, no better than concealment's %.1f dB" % [c_f.snr_db, c_fp.snr_db])
	if fec.out.size() != fec_plc.out.size():
		fails.append("FEC: %d frames out, %d concealed" % [fec.out.size(), fec_plc.out.size()])


## What GDScript or the network can hand the codec.
func _bounds(fails: Array) -> void:
	var e = ClassDB.instantiate("WdpVoiceEncoder")
	var d = ClassDB.instantiate("WdpVoiceDecoder")
	# before setup: nothing, no crash
	if not e.encode(V.speech(48000, 0.1)).is_empty() or not d.decode(PackedByteArray([1, 2, 3])).is_empty():
		fails.append("bounds: a codec that was not set up gave output")
	for bad in [0, 7999, 192001, -48000]:
		if e.setup(bad) != ERR_INVALID_PARAMETER or d.setup(bad) != ERR_INVALID_PARAMETER:
			fails.append("bounds: mix rate %d accepted" % bad)
	if e.setup(48000) != OK or d.setup(48000) != OK:
		fails.append("bounds: 48 kHz refused")
		return
	# settings are clamped
	e.bitrate = 1
	var lo: int = e.bitrate
	e.bitrate = 10000000
	var hi: int = e.bitrate
	e.expected_loss = -5
	var l0: int = e.expected_loss
	e.expected_loss = 500
	var l1: int = e.expected_loss
	if lo != 6000 or hi != 64000 or l0 != 0 or l1 != 100:
		fails.append("bounds: bitrate %d..%d, loss %d..%d (6000..64000, 0..100 expected)" % [lo, hi, l0, l1])
	e.bitrate = V.BITRATE
	e.expected_loss = 0
	# an over-long packet is refused unparsed; garbage gives an error or a frame, never a crash
	var long := PackedByteArray()
	long.resize(5000)
	if not d.decode(long).is_empty() or d.get_last_error() == 0:
		fails.append("bounds: a 5000-byte packet was decoded")
	if not d.decode_fec(long).is_empty():
		fails.append("bounds: a 5000-byte packet was used for FEC")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var garbage_frames := 0
	for k in 2000:
		var p := PackedByteArray()
		p.resize(rng.randi_range(1, 1500))
		for j in p.size():
			p[j] = rng.randi() & 0xff
		var out: PackedVector2Array = d.decode(p) if k % 2 == 0 else d.decode_fec(p)
		garbage_frames += out.size()
		if out.size() > 48000 * 120 / 1000 + 64:
			fails.append("bounds: a garbage packet decoded to %d frames" % out.size())
			break
		for f in out:
			if is_nan(f.x) or is_inf(f.x):
				fails.append("bounds: a garbage packet decoded to a NaN")
				break
	if ClassDB.class_call_static("WdpVoiceDecoder", "packet_has_fec", long) or ClassDB.class_call_static("WdpVoiceDecoder", "packet_has_fec", PackedByteArray()):
		fails.append("bounds: packet_has_fec said yes to an empty or over-long packet")
	# the decoder still works after all that
	d.reset()
	e.reset()
	var good: PackedByteArray = e.encode(V.speech(48000, 0.04))
	if good.is_empty() or d.decode(good).size() < 800:
		fails.append("bounds: the codec does not work after garbage")
	# at most 30 s wait to be encoded; the rest is dropped and counted
	e.reset()
	var minute := PackedVector2Array()
	minute.resize(48000 * 31)
	e.push_frames(minute)
	# (16,000 samples at 16 kHz past the 30 s, less the resampler's own delay)
	if e.packets_ready() != 1500 or e.get_dropped_samples() < 15900 or e.get_dropped_samples() > 16000:
		fails.append("bounds: 31 s pushed: %d packets ready, %d samples dropped (1500 and about 16000 expected)" % [
				e.packets_ready(), e.get_dropped_samples()])
	e.reset()
	if e.packets_ready() != 0:
		fails.append("bounds: reset kept %d packets" % e.packets_ready())


## The time per 20 ms frame at 48 kHz in and out (the resamplers included): the medians must be inside the Note 9's
## budget here too (a desktop is several times faster); the result line is what voice/README.md records.
func _bench(fails: Array) -> void:
	var b := V.bench(V.speech(48000, 4.0), 48000, 48000, 3)
	if b.is_empty():
		fails.append("bench: no codec")
		return
	print("VOICE bench %s: encode %.3f ms (p95 %.3f), decode %.3f ms (p95 %.3f) per 20 ms frame, %d frames" % [
			OS.get_name(), b.encode_ms, b.encode_p95_ms, b.decode_ms, b.decode_p95_ms, b.frames])
	if b.encode_ms > 1.0:
		fails.append("bench: encode %.3f ms per frame (budget 1 ms)" % b.encode_ms)
	if b.decode_ms > 0.3:
		fails.append("bench: decode %.3f ms per frame (budget 0.3 ms)" % b.decode_ms)
