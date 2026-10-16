# Walkdown Plant's sounds

`make_sounds.py` synthesises every `synth` sound of the library `data/plant3d/sounds.json` into Ogg Vorbis at build
time (decision 0054 §7, PLANT3D.md §11, FIRST-TRAIN.md §6; the encoder: decision 0055). It needs only NumPy and
FFmpeg with libvorbis. Nothing it makes is committed.

```
python3 tools/plant3d/sounds/make_sounds.py                 # into apps/plant3d/built/sounds
python3 tools/plant3d/sounds/make_sounds.py --out DIR --wav # 16-bit WAV, for listening only
python3 -m unittest tests.test_plant3d_sounds               # the tests
```

A run takes about 15 s.

## What the app gets

The output folder holds one file per layer, `<sound>.<layer>.ogg`, and `sounds.json`
(format `walkdown-plant-sound-files`, version 1). For each sound that file gives:

- `loop`: true for a loop, false for a one-shot;
- `lufs`: the planned loudness;
- `layers`: a list of the sound's layers.

Each layer has:

- `layer`, `file`, `seconds`, `bytes`;
- for loops, the Vorbis `quality` and the measured `click_db` at the loop point;
- for a tone whose frequency follows a value, `of`, `table` and `ref_hz`.

Playing a sound:

- **Every layer at once.** Play all of a sound's layers together, each with the binding's gain and pitch. A loop's
  layers are independent loops, so they don't need to stay in step.
- **Looping.** A loop is the whole file: set `loop = true` on the `AudioStreamOggVorbis`, with `loop_offset` 0.
- **Levels.** The files are already levelled against each other. At gain 1 and pitch 1, each sound plays at its
  `lufs`. Don't normalise them.
- **Layer kinds:**
  - `tones`: the steady tones;
  - `noise`: the band noise. Tones below 30 Hz are in it as a rate (a blade or tooth passing);
  - `tone<i>`: a tone whose frequency follows a value. Set its pitch to `hz(value) / ref_hz` (none in the first
    train);
  - `once`: a one-shot. Play it on the event: `breaker` when a breaker closes, `breaker_open` when one opens,
    `motor_start` when a large motor starts direct on line (then its `motor_large` loop takes over),
    `horn_ack` when an alarm is acknowledged.

## How each sound is made

The library declares each sound's spectrum: its `tones` and its `noise` band. `VOICES` in the script adds three
things for each sound:

- `why`: the physics behind the spectrum;
- `spl`: the typical level at 1 m, in dB(A);
- the time structure: modulation, clicks, sounder patterns, or the one-shot event.

**The tones:**

| Sound | What sets the tones |
|---|---|
| `gt_whine` | Compressor blade passing: blades × speed. 57 blades × 50 rev/s = 2,850 Hz, with its harmonic and a later stage at 3,550 Hz. Everything scales with speed, so pitch = speed covers the run from turning gear to full speed. |
| `gen_hum`, `transformer_hum` | Twice the 50 Hz grid frequency (100 Hz) and its harmonics. For a transformer that is magnetostriction (IEC 60076-10). |
| `sfc_whine` | A 12-pulse converter's harmonics, 12k ± 1 of 50 Hz (550, 650, 1,150, 1,250 Hz), and its 600 Hz ripple. |
| `motor_large`, `motor_small` | Magnetic hum at 100 Hz, rotor-slot whine (slots × speed, ± 100 Hz sidebands) and vane or fan blade passing. The large motor is lower and louder. |
| `fan_large`, `turning_gear`, `liquid_ring` | Blade, tooth or ring passing at 16, 8 and 25 Hz. These are rates, not pitches: a swell, steel clicks, a gurgle. |
| `water_rain` | Rain noise, plus single drops ringing at their bubble's Minnaert frequency. |
| `breaker`, `breaker_open` | Modal synthesis: an impact rings the mechanism's and the cubicle's modes. The close is followed by the spring-charging motor. |
| `motor_start` | Direct-on-line run-up: an inrush growl at 100 Hz, and slot whine and fan noise rising with speed. |
| `horn_p1`, `horn_p2`, `horn_p3` | A different pattern for each priority (ISA-18.2, EEMUA 191): fast pulses, slow pulses, a chime. |

The other sounds are band noise: combustion, exhaust, steam flow, vent, rain, burner.

**Seamless loops.** Every component of a loop has a whole number of cycles in it, and the noise is made periodic in
the frequency domain, so the synthesised loop is seamless to the sample. Vorbis can still leave a small tick where the
stream's end meets its start, because its coding errors at the two ends are independent. The generator tries 8
starting points of the loop at qualities 4, 6 and 8, and keeps the first one whose decoded seam is 60 dB under the
sound. It refuses a loop whose best is louder than −45 dB. The tick of each layer is `click_db` in the index.

**Levels:** LUFS = −18 − 0.5 × (105 − spl), from the vent (105 dB(A), −18 LUFS) down to the valve motor (72 dB(A),
−34.5 LUFS). This keeps the site's order with half its range. A one-shot is measured by its loudest 400 ms.

## Measured (2026-10-16)

24 sounds in 35 files, 1.47 MB of Ogg Vorbis in total. Decision 0054's budget is 150 MB for the whole package (10 MB
for clips). A loop's tone layer is 2 s (7–23 KiB) and its noise layer 8 s (35–74 KiB).
