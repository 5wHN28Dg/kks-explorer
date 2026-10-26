# 0069 Walkdown Plant voice: Opus through a small GDExtension of our own, built from pinned libopus and SpeexDSP

Date 2026-10-26 · Scope: docs/plant3d/MULTIPLAYER.md §8, §11; a new `apps/plant3d/voice/` (the GDExtension
`wdp_voice` and its build); the packages' microphone permissions · Status: **accepted; the native part built 2026-10-26** (MP5: `wdp_voice`, "As built" below; capture, push-to-talk
and the radio come with MP2), written before any code
under the user's decision of 2026-10-26 (up to 8 players, push-to-talk voice over the in-game radio, the microphone
permission) · Extends 0054 (its first native code); new dependencies: libopus, SpeexDSP (resampler), godot-cpp

**Question:** which codec and library carry push-to-talk voice between up to 8 players on Android arm64, Linux
x86-64 and Windows x64/ARM64, from a Godot 4.7 app, within the Note 9's budgets, and how is the microphone captured?

## Findings per target

| | Finding | Source |
|---|---|---|
| Opus in Godot 4.7 | none: `thirdparty/` has libogg, libvorbis, libtheora, no libopus; no Opus class | [S] github.com/godotengine/godot/tree/4.7-stable/thirdparty, doc/classes |
| Capture | `audio/driver/enable_input`; `AudioStreamMicrophone` + `AudioEffectCapture`, or `AudioServer.set_input_device_active` + `get_input_frames(n)` (experimental, float stereo at `get_input_mix_rate()`) | [S] 4.7 doc/classes AudioServer.xml, AudioStreamMicrophone.xml, ProjectSettings.xml |
| Android capture | the OpenSL ES driver requests `RECORD_AUDIO` when input starts and records with the default preset: no platform echo canceller or noise suppressor | [S] 4.7 platform/android/audio_driver_opensl.cpp |
| Windows / Linux capture | WASAPI; PulseAudio (PipeWire's Pulse server); Windows' privacy settings can block desktop apps (silence) | [D] ProjectSettings `audio/driver/enable_input` |
| Playback | `AudioStreamGenerator.push_buffer` | [D] |
| Opus | RFC 6716; libopus 1.5.2 (2024-04), BSD-3-Clause; VOIP mode, 6–510 kbit/s, frames 2.5–60 ms, in-band FEC, packet loss concealment | [D] opus-codec.org, RFC 6716 |
| SpeexDSP | 1.2.1, BSD-3-Clause; a resampler (Godot's input is 44.1 or 48 kHz; Opus takes 8/12/16/24/48 kHz) | [D] github.com/xiph/speexdsp |
| TwoVoIP | github.com/goatchurchprime/two-voip-godot-4: MIT; libopus 1.5.2, RNNoise, SpeexDSP built in; built by its CI for every Godot platform (Android included); v6.6 2026-09-23, pushed 2026-10-19, 187 stars; one maintainer; its README and v6.6 notes plan a v7 redesign of playback; releases as a prebuilt zip | [K] the repository, its README and releases, checked 2026-10-26 |
| godot-cpp | MIT, the official C++ bindings for GDExtension; extensions are meant to load in later 4.y | [D] |
| Our native toolchains | the NDK (libkks.so), llvm-mingw for Windows x64 and ARM64 (0047, 0053); the Linux build runs inside the Flatpak, so it is built in the Flatpak SDK matching `org.godotengine.godot.BaseApp//4.7` (the laptop's newer glibc already kept the importer off Debian 13) | android/nim/build.sh, apps/windows, CLAUDE.local deployment notes |

## Alternatives

1. **No codec** (16-bit PCM): 256 kbit/s per talker at 16 kHz: too much for mobile data and the relay.
2. **Ogg Vorbis** (what Godot plays): a music codec with long frames, and Godot has no encoder for it at run time: no.
3. **TwoVoIP as shipped:** fast to start; but a prebuilt zip (we build every native piece from pinned sources),
   a fast-moving API with a planned redesign, MQTT-oriented helpers we don't need, and RNNoise's model in every
   build.
4. **Our own GDExtension over the same libraries:** about 300 lines of C++ (an encoder with down-mix and resampling,
   a decoder with FEC and concealment), built from pinned sources like the rest of the repository; we own its
   interface. Cost: four native builds per release, 0054 §2's objection, accepted because no Godot or platform API
   encodes Opus.

All licences (BSD-3-Clause, MIT) are permissive and compatible with the repository's AGPL-3.0: nothing to ask the
user.

## Choice

- **(4): `wdp_voice`**, libopus 1.5.2 and SpeexDSP 1.2.1's resampler from pinned commits with checksums, godot-cpp at
  the tag matching Godot 4.7 (as built: godot-cpp 10.0.0, the first release versioned apart from Godot, against its
  `extension_api-4-7.json`), built for Android arm64-v8a, Linux x86-64, Windows x64 and ARM64; its notices in About.
  TwoVoIP stays the fallback if our binding can't be kept up.
- **Settings:** mono 16 kHz, VOIP mode, 20 ms frames, 16 kbit/s, complexity 5, in-band FEC, no DTX; two frames a
  message, about 30 kbit/s per talker with our headers and encryption; an adaptive jitter buffer of 60–200 ms.
- **Capture:** `AudioServer.get_input_frames` while push-to-talk is held in a session; encoding and decoding on a
  worker thread, never the main thread.
- **No echo canceller:** push-to-talk with one talker per channel (the host grants the floor), all playback muted
  while push-to-talk is held, and voice from players on the same LAN not played by default (they are in earshot), so
  a speaker never feeds a microphone that is sending. Noise left to Opus's VOIP
  mode; RNNoise (BSD-3) can be added if rooms prove loud.
- **Radio sound:** a band-pass bus and squelch clips (CC0) on playback.
- **Permissions:** Android `RECORD_AUDIO` (asked when voice is first turned on), Flatpak `--socket=pulseaudio`, MSIX
  `microphone`.
- **Budgets (Note 9, measured in MP5):** encode ≤ 1 ms and decode ≤ 0.3 ms per 20 ms frame; ≤ 1 MB added to the APK.

## As built (2026-10-26, MP5's native part)

`apps/plant3d/voice/` (its README: the build, the interface, the checks).

- **Built from pinned sources for all four targets:** libopus 1.5.2, SpeexDSP 1.2.1's `resample.c` and godot-cpp
  10.0.0, from tarballs checked against SHA-256.
  - Toolchains: Linux in `org.freedesktop.Sdk//26.08` (its commit pinned on CI), Android with NDK 27.2 at API 24,
    Windows x64 and ARM64 with llvm-mingw 20260922.
  - Each library exports one symbol.
  - The builds are reproducible: each is built a second time from sources and folders at other paths, with the same
    bytes, on the laptop and on CI.
- **Sizes:** Android 0.82 MB, stored uncompressed in the APK, so the APK grows by 0.82 MB (117.5 MB in all, of the
  150 MB limit). Linux 0.88 MB, Windows x64 0.87 MB, ARM64 0.73 MB.
- **Measured on the speech-like test signal**, per 20 ms frame, 48 kHz in, 44.1 kHz out:

  | | Encode, median | Decode, median | Round trip |
  |---|---|---|---|
  | Note 9 (3 runs of 1,000 frames) | 0.20 ms (p95 0.22) | 0.13 ms (p95 0.14) | delay 6.5 ms, level −0.26 dB |
  | Laptop | 0.10–0.13 ms | 0.02 ms (48 kHz out), 0.05–0.06 ms (44.1 kHz out) | |

  Both are inside the budgets of 1 ms and 0.3 ms.
- **Loaded and run:**
  - by the Godot 4.7.2 editor (the tests);
  - by the Linux export;
  - by the Flathub BaseApp's `godot-runner` inside `org.freedesktop.Platform//26.08`;
  - in the APK on the Note 9.

  The Windows DLLs are built and checked for their imports (KERNEL32 and the UCRT only), not yet run on Windows.
- **In-band FEC needs more than 16 kbit/s.** At the 16 kbit/s chosen above, libopus 1.5.2 codes no FEC at any
  expected loss: after its discounts for complexity and loss, the rate is under its threshold even at narrowband
  (`decide_fec`). At 20 kbit/s with 10 % or more expected loss, 78 % of the packets carry FEC, at 15.5 kbit/s on
  average; at 24 kbit/s, FEC rebuilds a lost frame at 8.5 dB SNR, against 6.0 dB for concealment. The bitrate is a
  setting: MP2 chooses it (MULTIPLAYER.md §8.3).
- **A libopus fault worked around:** 1.5.2's `opus_packet_has_lbrr` reads one byte past a packet whose first frame
  is empty, such as the 1-byte packet 0x08. `wdp_voice` parses every packet before it calls that function. The native
  test, run under the sanitizers, shows the read without the check.
- **The Linux library needs the runtime's glibc (2.43).** It is built in the Flatpak's SDK, as chosen, so it loads
  only on systems with glibc 2.43 or later. That is always true inside the Flatpak, the plant's only Linux package.

## When to revisit

- if Godot gains an Opus encoder and decoder (then drop `wdp_voice`);
- if a platform's build of `wdp_voice` fails to load after a Godot minor upgrade;
- if trainees' rooms are too loud (RNNoise) or players want full duplex (then an echo canceller: SpeexDSP's, or the
  platform's through a voice-communication capture preset Godot doesn't offer today).

Sources: https://github.com/godotengine/godot/tree/4.7-stable · https://www.rfc-editor.org/rfc/rfc6716 ·
https://opus-codec.org/ · https://github.com/xiph/opus · https://github.com/xiph/speexdsp ·
https://github.com/goatchurchprime/two-voip-godot-4 · https://github.com/godotengine/godot-cpp ·
https://docs.godotengine.org/en/stable/classes/class_audioserver.html.
