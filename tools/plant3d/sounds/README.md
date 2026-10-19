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

The output folder holds one file per layer, `<sound>.<layer>.ogg`, and `index.json`
(format `walkdown-plant-sound-files`, version 1). For each sound the index gives:

- `loop`: true for a loop, false for a one-shot;
- `level`: its A-weighted level in dBFS at gain 1;
- `layers`: a list of the sound's layers.

Each layer has:

- `layer`, `file`, `samples`, `seconds`, `bytes`;
- `pitch`: whether the binding's pitch applies to it;
- for loops, the Vorbis `quality` and the measured `click_db` at the loop point;
- for a tone whose frequency follows a value, `of`, `table` and `ref_hz`.

Playing a sound:

- **Every layer at once.** Play all of a sound's layers together, each with the binding's gain, and with its pitch
  where the layer's `pitch` is true. A loop's layers are independent loops, so they don't need to stay in step.
- **Looping.** A loop is the whole file: set `loop = true` on the `AudioStreamOggVorbis`, with `loop_offset` 0.
- **Levels.** The files are already levelled against each other. At gain 1 and pitch 1, each sound plays at its
  `level`. Don't normalise them.
- **Layer kinds:**
  - `mains`: an electrical hum at multiples of twice the 50 Hz grid frequency. It is never pitched: a motor's hum
    stays at 100 Hz whatever its speed;
  - `tones`: the other steady tones;
  - `noise`: the band noise. Tones below 30 Hz are in it as a rate (a blade or tooth passing);
  - `tone<i>`: a tone whose frequency follows a value. Set its pitch to `hz(value) / ref_hz` (none in the first
    train);
  - `once`: a one-shot, meant for an event: `breaker` for a breaker closing, `breaker_open` for one opening,
    `motor_start` for a large motor started direct on line (its `motor_large` loop then takes over at the same
    level), `horn_ack` for an alarm acknowledged. Format 1 has no binding that says "on this edge" (PLANT3D.md
    §7.7): today only `breaker` is bound (`gt1_brk_cmd`), so the app's wiring decides when a one-shot plays
    (apps/plant3d/ui/sound_player.gd: a breaker's contacts closing and opening, a large motor's start command,
    an acknowledge). The people cues are played by name too: `step_concrete`, `step_grating` and `step_stair` once
    a stride by the floor underfoot (with a little random pitch and level), `door_slide` as a sliding door starts,
    the `door_roller` loop while a roller door moves, and the `wind` and `plant_distant` loops outdoors.

## How each sound is made

The library declares each sound's spectrum: its `tones` and its `noise` band. `VOICES` in the script adds four
things for each sound:

- `why`: the physics behind the spectrum;
- `spl`: the typical level at 1 m, in dB(A) (a one-shot that hands over to a loop, `motor_start`, is levelled to that loop instead);
- `mains`: which tones are electrical hum;
- the time structure: modulation, clicks, sounder patterns, or the one-shot event.

**The tones:**

| Sound | What sets the tones |
|---|---|
| `gt_whine` | Compressor blade passing: blades × speed. 57 blades × 50 rev/s = 2,850 Hz, with its harmonic and a later stage at 3,550 Hz. All of it scales with speed. |
| `gen_hum`, `transformer_hum` | Twice the 50 Hz grid frequency (100 Hz) and its harmonics. For a transformer that is magnetostriction (IEC 60076-10). |
| `sfc_whine` | A 12-pulse converter draws currents at 12k ± 1 of 50 Hz. Its transformer and reactors buzz with the current squared: 600 and 1,200 Hz and their neighbours 500, 700, 1,100 and 1,300 Hz. |
| `motor_large`, `motor_small` | Magnetic hum at 100 Hz, rotor-slot whine (slots × speed, ± 100 Hz sidebands) and vane or fan blade passing. The shaft speeds are the ones the model turns the shafts at: 8.25 rev/s for the CW pumps, 24.7 for the small four-pole motors. The large motor is lower and louder. |
| `fan_large`, `turning_gear`, `liquid_ring` | Blade, tooth or ring passing at 16, 8 and 25 Hz. These are rates, not pitches: a swell, steel clicks, a gurgle. |
| `water_rain` | Rain noise, plus single drops ringing at their bubble's Minnaert frequency. |
| `breaker`, `breaker_open` | Modal synthesis: an impact rings the mechanism's and the cubicle's modes. The close is followed by the spring-charging motor. |
| `motor_start` | Direct-on-line run-up: an inrush growl at 100 Hz, a run-up that is fastest near full speed, and slot whine and fan noise rising with speed. |
| `horn_p1`, `horn_p2`, `horn_p3` | A different pattern for each priority (ISA-18.2, EEMUA 191): fast pulses, slow pulses, a chime. |
| `step_concrete`, `step_grating`, `step_stair` | A heel strike and a toe 80–90 ms later, each an impact ringing the floor's modes: concrete barely rings (a 90 Hz thump and grit); grating's bearing bars ring at 420–3,700 Hz and the panel rattles; a stair tread rings lower and longer (260–3,050 Hz). |
| `door_slide`, `door_roller` | A sliding door's rollers along the track (uneven at its joints), then the leaf at its stop (180, 520 Hz); a roller door's slats rattling in their guides (about 15 a second), its motor's 100 Hz and its chain's 350 Hz. |
| `plant_distant` | The grid's hum (100, 200 Hz) under a low roar: from afar the air takes the high frequencies away. |

The other sounds are band noise: combustion, exhaust, steam flow, vent, rain, burner, and the wind, in gusts over a
16 s loop (its own `seconds` in VOICES; the other noise layers are 8 s).

**Seamless loops.** Every component of a loop has a whole number of cycles in it, and the noise is made periodic in
the frequency domain, so the synthesised loop is seamless to the sample.

Vorbis can still leave a small tick where the stream's end meets its start, because its coding errors at the two
ends are independent. The tick is measured on that error (the decoded file minus the samples it was made from):
its energy above the sound's own band, in the window at the seam, beyond the loudest window elsewhere. The
generator tries 8 starting points of the loop at qualities 4, 6 and 8, and keeps the first one whose tick is 60 dB
under the sound. It refuses a loop whose best is louder than −45 dB. Each layer's tick is its `click_db` in the
index (−300: nothing beyond the rest of the loop), with the `rotation` it chose.

The bound refuses a single-sample tick of about 0.1 × the sound's RMS in tones, and of 0.5 × RMS in noise up to
about 1.2 kHz (the tests inject 0.5). In noise reaching several kHz (steam, the vent, rain, the motors' fans) Vorbis's
own error is as rough from sample to sample as a tick of 1–2 × RMS or more, so a seam jump, typically a twentieth of
that, is lost in it, by measure and by ear. (The check of the synthesised samples below works up to about 1.5 kHz:
a different measure.)

Before encoding, the tests check the synthesised loops sample by sample: step, curvature, the residual of a linear
predictor, and the high-band energy at the seam. A loop cut short by even a few samples fails them, except in noise
reaching several kHz, where a jump can't be told from the noise itself.

**Levels.** Each file is levelled by A-weighted level, the weighting of its dB(A) figure:
level = −26 − 0.5 × (105 − spl) dBFS(A). That runs from the vent (105 dB(A), −26) down to the valve motor
(72 dB(A), −42.5), keeping the site's order with half its range. The top is −26 rather than higher because the
rumbles carry most of their energy in the bass that A weighting discounts, and they must not clip. A one-shot is
measured by its loudest 400 ms. A recorded clip added later must follow the same rule, not a fixed loudness.

## Measured (2026-10-19)

31 sounds in 51 files, 1.92 MB of Ogg Vorbis in total (24 sounds, 1.57 MB before the footsteps, doors and ambience).
Decision 0054's budget is 150 MB for the whole package (10 MB for clips). A loop's tone layers are 2 s (8–22 KiB)
and its noise layer 8 s (34–74 KiB; the wind's 16 s, 133 KiB); a footstep is 5–7 KiB. The worst loop-point tick
after Vorbis is −54.2 dB under its sound; 26 of the 43 loop layers have nothing beyond the rest of the loop.

Not checked: Godot's own decoder. The seams and lengths are measured with FFmpeg's.
