## What the voice codec's checks share (tests/test_voice.gd, voice/demo/voice_wav.gd): a speech-like test signal,
## WAV in and out, a round trip through wdp_voice with or without lost packets, its delay, level and SNR, and the
## time per 20 ms frame. wdp_voice's classes are looked up by name (ClassDB), never named: a build without the
## extension still compiles this script.
extends RefCounted

const FRAME_MS := 20
## The codec's settings (MULTIPLAYER.md §8.3) are wdp_voice's defaults; these are only what the checks change.
const BITRATE := 16000


static func available() -> bool:
	return ClassDB.class_exists("WdpVoiceEncoder") and ClassDB.class_exists("WdpVoiceDecoder")


## (Returned untyped: GDScript would refuse wdp_voice's methods on a RefCounted.)
static func encoder(mix_rate: int):
	var e = ClassDB.instantiate("WdpVoiceEncoder")
	if e == null or e.setup(mix_rate) != OK:
		return null
	return e


static func decoder(mix_rate: int):
	var d = ClassDB.instantiate("WdpVoiceDecoder")
	if d == null or d.setup(mix_rate) != OK:
		return null
	return d


## A voiced, speech-like signal at `rate`: a glottal pulse train whose pitch glides between 100 and 190 Hz, shaped
## by three formants that move between vowels every 180 ms, in syllables (4 a second) with pauses; a little breath
## noise. Deterministic (a fixed seed). Stereo frames, both channels alike, peak about 0.5.
static func speech(rate: int, seconds: float) -> PackedVector2Array:
	var n := int(rate * seconds)
	var out := PackedVector2Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 69
	var vowels := [[730.0, 1090.0, 2440.0], [270.0, 2290.0, 3010.0], [300.0, 870.0, 2240.0], [530.0, 1840.0, 2480.0],
			[570.0, 840.0, 2410.0]]
	# three two-pole resonators (formants), their coefficients updated per vowel
	var y1 := [0.0, 0.0, 0.0]
	var y2 := [0.0, 0.0, 0.0]
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var f0 := 145.0 + 45.0 * sin(TAU * 0.7 * t)
		phase += f0 / rate
		var pulse := 0.0
		if phase >= 1.0:
			phase -= 1.0
			pulse = 1.0
		var v: Array = vowels[int(t / 0.18) % vowels.size()]
		var src := pulse + 0.02 * (rng.randf() * 2.0 - 1.0)
		var s := 0.0
		for k in 3:
			var bw := 80.0 + 40.0 * k
			var r := exp(-PI * bw / rate)
			var a1 := 2.0 * r * cos(TAU * float(v[k]) / rate)
			var a2 := -r * r
			var y: float = src * (1.0 - r) + a1 * y1[k] + a2 * y2[k]
			y2[k] = y1[k]
			y1[k] = y
			s += y / (k + 1)
		# syllables: 4 a second, each 0.2 s of sound then a short gap; a longer pause every 1.5 s
		var syl := fmod(t, 0.25)
		var env := sin(PI * syl / 0.2) if syl < 0.2 else 0.0
		if fmod(t, 1.5) > 1.3:
			env = 0.0
		var x := 1.6 * s * env
		out[i] = Vector2(x, x)
	return out


## The round trip: `frames` (at in_rate) encoded 20 ms at a time, the packets in `lost` (indices) dropped, decoded at
## out_rate, each lost one concealed or (fec) rebuilt from the next packet's in-band FEC; the encoder told to expect
## expected_loss per cent of loss, at `bitrate`. -> {out:
## PackedVector2Array, packets: int, bytes: int, fec_packets: int (those carrying FEC), encode_us: Array,
## decode_us: Array (per 20 ms frame)}
static func round_trip(frames: PackedVector2Array, in_rate: int, out_rate: int, lost: Dictionary = {},
		fec := false, expected_loss := 0, bitrate := BITRATE) -> Dictionary:
	var enc = encoder(in_rate)
	var dec = decoder(out_rate)
	if enc == null or dec == null:
		return {}
	enc.bitrate = bitrate
	enc.expected_loss = expected_loss
	var packets: Array[PackedByteArray] = []
	var encode_us: Array = []
	var step := in_rate * FRAME_MS / 1000
	var at := 0
	while at < frames.size():
		var chunk := frames.slice(at, mini(at + step, frames.size()))
		at += step
		var t0 := Time.get_ticks_usec()
		enc.push_frames(chunk)
		while enc.packets_ready() > 0:
			packets.append(enc.pop_packet())
		encode_us.append(Time.get_ticks_usec() - t0)
	var out := PackedVector2Array()
	var decode_us: Array = []
	var bytes := 0
	var with_fec := 0
	for i in packets.size():
		bytes += packets[i].size()
		if dec.packet_has_fec(packets[i]):
			with_fec += 1
		var t0 := Time.get_ticks_usec()
		var got: PackedVector2Array
		if lost.has(i):
			if fec and i + 1 < packets.size() and not lost.has(i + 1):
				got = dec.decode_fec(packets[i + 1])
			else:
				got = dec.decode(PackedByteArray())
		else:
			got = dec.decode(packets[i])
		decode_us.append(Time.get_ticks_usec() - t0)
		out.append_array(got)
	return {"out": out, "packets": packets.size(), "bytes": bytes, "fec_packets": with_fec,
			"encode_us": encode_us, "decode_us": decode_us}


## Compares `b` (decoded) with `a` (the original), both at one rate: the delay that best lines them up (searched
## up to max_delay samples), the level of b against a in dB, and the SNR in dB at that delay with b scaled to a's
## level (Opus is perceptual: the waveform is matched only roughly).
static func compare(a: PackedVector2Array, b: PackedVector2Array, max_delay: int) -> Dictionary:
	var n := mini(a.size(), b.size()) - max_delay
	if n <= 0:
		return {"delay": -1, "level_db": -INF, "snr_db": -INF}
	# the delay by cross-correlation on every other sample (cheap, enough to find the peak), then refined
	var best := 0
	var best_c := -INF
	for d in range(0, max_delay, 2):
		var c := 0.0
		for i in range(0, n, 4):
			c += a[i].x * b[i + d].x
		if c > best_c:
			best_c = c
			best = d
	for d in range(maxi(0, best - 2), mini(max_delay, best + 3)):
		var c := 0.0
		for i in range(0, n, 4):
			c += a[i].x * b[i + d].x
		if c > best_c:
			best_c = c
			best = d
	var ea := 0.0
	var eb := 0.0
	var ab := 0.0
	for i in n:
		var x := a[i].x
		var y := b[i + best].x
		ea += x * x
		eb += y * y
		ab += x * y
	if ea <= 0.0 or eb <= 0.0:
		return {"delay": best, "level_db": -INF, "snr_db": -INF}
	var g := ab / eb   # the least-squares gain of b onto a
	var err := 0.0
	for i in n:
		var e := a[i].x - g * b[i + best].x
		err += e * e
	return {"delay": best, "level_db": 10.0 * log(eb / ea) / log(10.0),
			"snr_db": 10.0 * log(ea / maxf(err, 1e-20)) / log(10.0)}


static func median(xs: Array) -> float:
	if xs.is_empty():
		return NAN
	var s := xs.duplicate()
	s.sort()
	return float(s[s.size() / 2])


static func percentile(xs: Array, p: float) -> float:
	if xs.is_empty():
		return NAN
	var s := xs.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(p * s.size()))])


## The time per 20 ms frame, in ms: `reps` round trips of `frames` (in_rate in, out_rate out), the codec's work only
## (each call timed). -> {encode_ms, decode_ms (medians), encode_p95_ms, decode_p95_ms, frames}
static func bench(frames: PackedVector2Array, in_rate: int, out_rate: int, reps: int) -> Dictionary:
	var enc_us: Array = []
	var dec_us: Array = []
	for r in reps:
		var rt := round_trip(frames, in_rate, out_rate)
		if rt.is_empty():
			return {}
		enc_us.append_array(rt.encode_us)
		dec_us.append_array(rt.decode_us)
	return {"encode_ms": median(enc_us) / 1000.0, "decode_ms": median(dec_us) / 1000.0,
			"encode_p95_ms": percentile(enc_us, 0.95) / 1000.0, "decode_p95_ms": percentile(dec_us, 0.95) / 1000.0,
			"frames": enc_us.size()}


## A WAV file's samples as stereo frames, and its rate: {frames, rate}, or {} if it can't be read (16-bit PCM,
## mono or stereo: AudioStreamWAV.load_from_file).
static func read_wav(path: String) -> Dictionary:
	var w := AudioStreamWAV.load_from_file(path)
	if w == null or w.format != AudioStreamWAV.FORMAT_16_BITS:
		return {}
	var data := w.data
	var ch := 2 if w.stereo else 1
	var n := data.size() / (2 * ch)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var l := data.decode_s16(i * 2 * ch) / 32768.0
		var r := data.decode_s16(i * 2 * ch + 2) / 32768.0 if ch == 2 else l
		out[i] = Vector2(l, r)
	return {"frames": out, "rate": w.mix_rate}


## Stereo frames into a 16-bit PCM mono WAV (the left channel). -> Error
static func write_wav(path: String, frames: PackedVector2Array, rate: int) -> Error:
	var data := PackedByteArray()
	data.resize(frames.size() * 2)
	for i in frames.size():
		data.encode_s16(i * 2, clampi(int(round(frames[i].x * 32767.0)), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w.save_to_wav(path)
