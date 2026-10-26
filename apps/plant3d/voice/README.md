# wdp_voice: Walkdown Plant's voice codec

A small GDExtension of our own (decision `docs/decisions/0069-plant-voice-opus.md`, `docs/plant3d/MULTIPLAYER.md`
§8): Opus for push-to-talk voice between players. Godot 4.7 has no Opus. It is the plant's first native code; 0069
amends decision 0054, which kept the app script-only.

| Part | Version | Licence | What of it |
|---|---|---|---|
| libopus | 1.5.2 | BSD-3-Clause | the float codec; no DRED or OSCE (their models would add megabytes) |
| SpeexDSP | 1.2.1 | BSD-3-Clause | `resample.c` alone, its symbols prefixed `wdp_` |
| godot-cpp | 10.0.0-stable | MIT | against its `extension_api-4-7.json` (Godot 4.7's API), only the classes `build_profile.json` names |

All three are fetched by `build.sh` from the URLs in it and checked against SHA-256 (Xiph's published sums for Opus and
SpeexDSP). `pinned-sources.cdx.json` lists them, and the plant's About lists them with their own licence files
(`tools/about/plant.json`, `tools/about/notices/`).

## Build

```
apps/plant3d/voice/build.sh [linux-x86_64] [android-arm64] [windows-x86_64] [windows-arm64]   # default: all four
WDP_CHECK_REPRO=1 apps/plant3d/voice/build.sh …    # build each one twice in fresh folders and compare the bytes
```

| Target | Toolchain | Library |
|---|---|---|
| `linux-x86_64` | GCC in `org.freedesktop.Sdk//26.08`, the SDK of the Flatpak's runtime (`org.godotengine.godot.BaseApp//4.7` runs on `org.freedesktop.Platform//26.08`), run through `flatpak run` with no network and only the work folders shared. Its glibc is the one the app runs on. `WDP_LINUX_HOST=1` uses the host's GCC (a quick check, never a release) | `libwdp_voice.linux.x86_64.so` |
| `android-arm64` | NDK 27.2.12479018, API 24 (Godot 4.7's minimum), libc++ linked in, 16 KB pages | `libwdp_voice.android.arm64.so` |
| `windows-x86_64`, `windows-arm64` | llvm-mingw (`platform/windows/fetch-llvm-mingw.sh`, decisions 0047, 0053), libc++ linked in; only Windows' own DLLs (KERNEL32, the UCRT) | `libwdp_voice.windows.{x86_64,arm64}.dll` |

What it writes, all into `bin/`, none of it committed:

- the libraries;
- `wdp_voice.gdextension`, which names only the libraries that are there. An export for a platform without one
  warns and goes without voice; it does not fail on a missing file.
- `BUILD-INFO.txt`: each library's SHA-256, its size and the toolchain that made it.

The Linux library built in the SDK needs that runtime's glibc: 2.43 or later, for `sqrtf`'s new symbol version.
Inside the Flatpak, the only way the plant ships on Linux, it always has it. A bare `export/linux` binary has voice
only on a system with that glibc, and otherwise runs without it. CI's app job runs Godot on Ubuntu 24.04 (glibc 2.39),
so it builds its library with the runner's own GCC (`WDP_LINUX_HOST=1`) for the tests. The SDK build is CI's
`voice` job.

The libraries are reproducible. The objects carry no build paths (`-ffile-prefix-map`), dates (`--no-insert-timestamp`)
or build IDs. Two builds of a commit with the same toolchains give the same bytes. CI's `voice` job checks that for
each target (`.github/workflows/plant3d-app.yml`). Each library exports one symbol, `wdp_voice_library_init`
(`wdp_voice.map`, `--exclude-libs`). Nothing of libopus, the resampler or godot-cpp is exported, and the linker drops
what is unused.

`apps/plant3d/build.sh release` runs `build.sh` for all four first and refuses to export without them. Its other modes
use what `bin/` holds, and each export says whether it carries voice. CI's app job builds the Linux library (with its own GCC) before the app's tests. The exports carry the library to these places:

- APK: `lib/arm64-v8a/`;
- Linux and Windows: beside the executable;
- Flatpak (`flatpak/…yml`): `/app/bin`, beside `godot-runner`;
- MSIX (`msix/make-msix.sh`): beside `WalkdownPlant.exe`.

`build.sh` checks each export for it.

## Interface

The classes are made with `ClassDB.instantiate("WdpVoiceEncoder")`. Scripts never name them, so a build without the
library still runs, just without voice (`voice_check.gd` `available()`). An instance belongs to one thread at a time
(the voice worker, §8.4).

**`WdpVoiceEncoder`**: mono, 16 kHz, `OPUS_APPLICATION_VOIP`, 20 ms frames, complexity 5, in-band FEC on, no DTX
(§8.3).

- `setup(mix_rate) -> Error`: the input's rate, 8–192 kHz (`AudioServer.get_input_mix_rate()`).
- `encode(PackedVector2Array) -> PackedByteArray`: takes the mix rate's stereo frames (down-mixed, resampled) and
  returns the next 20 ms packet, or an empty array while less than 20 ms is buffered.
- `push_frames(frames)`, `packets_ready()`, `pop_packet()`: for more than one packet at a time.
- `bitrate`: 16,000 by default, clamped to 6,000–64,000.
- `expected_loss`: 0–100 %, the in-band FEC's redundancy follows it.
- `reset()`: a new talk spurt.
- `get_lookahead_samples()`; `get_dropped_samples()`: audio beyond 30 s waiting to be encoded is dropped (the floor's
  limit, §8.4).
- `WdpVoiceEncoder.opus_version()`.

**`WdpVoiceDecoder`**:

- `setup(mix_rate) -> Error`: the output's rate (`AudioServer.get_mix_rate()`).
- `decode(packet) -> PackedVector2Array`: stereo frames at the mix rate. An empty packet is a lost 20 ms frame, filled
  by Opus's loss concealment. A packet libopus refuses gives an empty array, and `get_last_error()` gives the Opus
  error; play it as lost.
- `decode_fec(next_packet)`: rebuilds a lost frame from the in-band FEC of the packet after it, then decode that
  packet normally. Without FEC data in it, libopus conceals.
- `WdpVoiceDecoder.packet_has_fec(packet)`, `reset()`.

What comes from scripts or the network is bounded before libopus sees it:

- a packet over 3,825 bytes is refused unparsed;
- a packet decodes to at most 120 ms;
- mix rates outside 8–192 kHz are refused;
- every buffer is sized for its call.

## Checks

- `tests/test_voice.gd`, in the app's tests:
  - round trips at 16, 44.1 and 48 kHz: delay, level, SNR, length, bitrate;
  - 10 % loss: concealment fills the gaps at about the speech's level and the decoder recovers; FEC beats
    concealment;
  - the bounds: rates, settings, over-long and 400 random packets, the 30 s limit;
  - the time per frame against the budget.

  Without the library it passes with a note, except when `WDP_VOICE_REQUIRED` is set. `build.sh` sets it when the
  Linux library is in `bin/`; CI always has it.
- `demo/voice_wav.tscn`: the test scene. It reads a WAV (`-- --wav=FILE`, default a speech-like signal written as a
  WAV first), encodes, decodes, writes `user://voice_out.wav` and prints `VOICE` lines: the round trip and the time
  per frame. On a phone, `voice=bench` in `walk.txt` (`app/main.gd`) opens it instead of the plant.

  `godot --path apps/plant3d res://voice/demo/voice_wav.tscn`

Measured (2026-10-26; the speech-like signal of `voice_check.gd`):

| | Laptop (i7-12700H, Linux) | Note 9 (Exynos 9810, Android 10) |
|---|---|---|
| encode, per 20 ms frame (48 kHz in) | 0.11 ms median | see the PR / MULTIPLAYER.md §11 |
| decode, per 20 ms frame (48 kHz out) | 0.02 ms median (0.05 ms to 44.1 kHz) | |
| round trip | delay 6.4 ms, level −0.25 dB, SNR 8.5 dB, 10–11 kbit/s | |

**FEC needs more than 16 kbit/s.** At §8.3's 16 kbit/s, libopus 1.5.2 codes no in-band FEC at any expected loss: no
packet carries any. After its own discounts for complexity and loss, the rate is below its threshold even at narrowband.
At 20 kbit/s with 10 % or more expected loss, about 78 % of the packets carry FEC, and the average is 15.5 kbit/s on
the test signal. At 24 kbit/s, FEC rebuilds a lost frame at 8.5 dB SNR, against 6.0 dB for concealment. The
bitrate is a setting; which one the sessions use is MP2's choice (MULTIPLAYER.md §8.3).
