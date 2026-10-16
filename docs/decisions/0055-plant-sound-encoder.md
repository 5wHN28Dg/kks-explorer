# 0055 Walkdown Plant: the synthesised sounds are encoded to Ogg Vorbis by FFmpeg's libvorbis at build time

Date 2026-10-16 · Scope: `tools/plant3d/sounds/make_sounds.py` (the sound generator of 0054 §7 and PLANT3D.md §11),
CI's `python` job · Status: **decided** under the task's go-ahead (Ogg Vorbis asked for; revisitable) · Extends 0054

**Question:** the generator synthesises the first train's sounds with NumPy (already a pinned dependency,
requirements-dev.txt). What turns its samples into the Ogg Vorbis files Godot plays, deterministically, on this laptop
and on CI, with no new Python package?

## Findings

| | Fact | Source |
|---|---|---|
| What Godot plays natively | Ogg Vorbis, WAV (PCM, IMA-ADPCM, QOA at import) and MP3; Ogg Vorbis loops sample-exact through its granule positions | [D] docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html |
| Python options in requirements-dev.txt | none encodes Vorbis (NumPy, Pillow, OpenCV, PyMuPDF, Playwright, cryptography). A Vorbis encoder in NumPy would be our own codec | [V] the file |
| FFmpeg (`libvorbis` encoder) | LGPL-2.1+/GPL build of Ubuntu 26.04 (`ffmpeg` 8.0.1), with libvorbis 1.3.7 (BSD-3-Clause); already on this laptop; on CI one `apt-get install ffmpeg` | [V] `ffmpeg -encoders` here; packages.ubuntu.com |
| Deterministic output | with `-fflags +bitexact -flags:a +bitexact -map_metadata -1` the Ogg stream serial is 0 and no version string is written: the same samples give the same bytes, run after run | [V] encoded twice here, byte-identical; libavformat `oggenc.c` (serial = stream index under bitexact) |
| Exact length | an encoded 88,200-sample loop decodes to 88,200 samples (FFmpeg's decoder honours the end granule position) | [V] here |
| Short streams | a clip that fits in one Ogg page (under about 1 s at FFmpeg's default page duration) decodes to the wrong length in FFmpeg (+48 or −128 samples here), though its granule positions are right: pages of 0.1 s (`-page_duration 100000`) make every clip decode exactly, for 27 bytes a page | [V] here |
| Loop points | inside a stream Vorbis's coding error is smooth, but the errors at the stream's end and at its start are independent, so a loop can tick where they meet: up to −35 dB under a 20–200 Hz rumble at quality 4. A loop may start anywhere, and trying 8 starting points at qualities 4, 6 and 8 left every first-train loop at −48.8 dB or quieter, most with nothing at the seam. Godot's Ogg looping seeks to `loop_offset` with no crossfade (its beat-based fade only adds the tail) | [V] here; Godot `modules/vorbis/audio_stream_ogg_vorbis.cpp` at 4.7-stable |
| `oggenc` (vorbis-tools) | the reference command-line encoder, same libvorbis; not installed here and installing it needs sudo (outside the project) | [V] here |
| QOA in Godot's WAV import | Godot-native too and no external tool, but the task asks for Ogg Vorbis and QOA is about twice the size at the quality used here (3.2 bit/sample) | [D] the import page above |
| Shipping | the encoder is a build tool, never shipped; the app ships only the `.ogg` files, decoded by Godot's own Vorbis code (in Godot's notices, 0054 §7) | [V] |

## Choice

- The generator writes 16-bit mono PCM at 44.1 kHz (Godot's default mix rate) and pipes it to
  `ffmpeg … -c:a libvorbis -q:a Q -fflags +bitexact -flags:a +bitexact -map_metadata -1 -page_duration 100000 -f ogg`,
  Q = 4, or 6 or 8 where a loop's seam needs it (the search above); the tests hold every loop's tick at −45 dB or
  quieter.
- CI's `python` job installs `ffmpeg` with apt and sets `KKS_REQUIRE_FFMPEG=1`, so the encoding tests fail there
  without it; locally they are skipped only where FFmpeg is missing (the synthesis tests, which need only NumPy, always
  run).
- Determinism is promised per machine and FFmpeg build (same input, same bytes): the `.ogg` files are build outputs,
  not committed (0054 §7: loops synthesised at build time), so no test compares bytes across machines.

**When to revisit:** if FFmpeg's or libvorbis's output stops being bit-exact on one machine; if a recorded clip ever
needs encoding at build time (it is committed already encoded, 0054 §7); if the package size makes QOA or a lower
Vorbis quality worth measuring.
