# Walkdown

Tier: T3
Policy: v2.1
Type: web, native, service
Baseline: until 2027-01-03

*Formerly KKS Explorer (renamed 2026-10-03).*

Walkdown finds any KKS code on a power plant's P&ID drawings and shows everything known about it:
- the decoded code and where the equipment is;
- photos and notes;
- the operation-manual steps that use it.

It reads the tags straight off vector P&ID PDFs (AutoCAD plots, no text layer). Every device keeps the plant's signed,
append-only log and works offline. Devices sync with the plant's server and with each other, on the same Wi-Fi or
across the internet.

- **Apps:** Android, Windows, Linux (GNOME), and the web pages for browsers. Get them from the
  [latest release](https://github.com/5wHN28Dg/kks-explorer/releases/latest).
- **Guides for teammates, the manager and the maintainer:** the [wiki](https://github.com/5wHN28Dg/kks-explorer/wiki).
  It covers the [move from KKS Explorer](https://github.com/5wHN28Dg/kks-explorer/wiki/Moving-from-KKS-Explorer), the
  [server](https://github.com/5wHN28Dg/kks-explorer/wiki/Server) and
  [releasing](https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing).
- **Building and testing:** [Development](https://github.com/5wHN28Dg/kks-explorer/wiki/Development), and the README
  of each part (`core/`, `apps/gnome/`, `apps/windows/`, `android/app2/`, `importer/`, `relay/`).
- **Specifications:** `docs/PROTOCOL-v2.md` (the log, sync, the v1 import), `docs/PATHSTORE.md` (drawings),
  `docs/COURSES.md` (courses), `docs/GLYPHLIB.md` (the reader's glyph library).
- **Why things are the way they are:** `docs/decisions/` and the development policy `docs/evidence-first-*.md`.

## Targets

What each part runs on (`NAT-2`, `OTH-1`); what each platform provides is in
[docs/capability-matrix.md](docs/capability-matrix.md). No maximum versions are declared.

- **Windows:** Windows 10 22H2 and Windows 11, on x64 and ARM64 (ARM64 on Windows 11). Win32 with Direct2D and
  DirectWrite, shipped as an MSIX signed with our own certificate (`Walkdown.msix`, `Walkdown-arm64.msix`,
  `windows-msix.cer`). The MSIX manifest accepts Windows 10 1809 (10.0.17763) and later, but only 22H2 is supported
  and tested (VMs: 10 22H2 build 19045, 11 26H2 build 26300). N editions need the Media Feature Pack for the webcam.
- **Linux:** the GNOME desktop stack: GTK 4 and libadwaita, the XDG desktop portals (file chooser, camera, secret),
  D-Bus (with Avahi for discovery), PipeWire and GStreamer for the camera. Shipped as a Flatpak on the
  GNOME 50 runtime (`org.gnome.Platform//50`: GTK 4.22, libadwaita 1.9), for x86_64 and aarch64. Developed and tested
  on Ubuntu 26.04 LTS (GNOME 50).
- **Android:** Android 10 (API 29, `minSdk = 29`) and later, target API 36, on 64-bit ARM phones (arm64-v8a);
  32-bit-only phones are not supported (decision 0046).
- **Web client:** the pages the server serves (no build step), in the browsers declared in
  [.browserslistrc](.browserslistrc): Safari and iOS Safari 17 and later (the iPhone path), the last two versions of
  Chrome, Edge and Chrome for Android, the last two versions of Firefox and Firefox ESR. The resolved list is in the
  capability matrix.
- **Server (service):** Linux with systemd 256 or later, run as a systemd user service with linger
  (`systemctl --user`; `systemd-creds --user` seals its storage key, to the TPM2 where there is one), as on Ubuntu
  26.04 LTS where it runs. Built with Nim 2.2.12 and its standard library; it links the system's GnuTLS 3.8 (TLS and
  crypto), OpenSSL's libcrypto 3.2 or later (Argon2id), SQLite 3, GLib/GIO (D-Bus to Avahi) and zlib. The importer it
  runs, `kks-import`, also links MuPDF 1.28.2 (built from pinned source) and libjxl 0.11.

**Core modules:** the business logic is the sans-I/O Nim core in [`core/`](core/) (`core/src/kks/`: the log and
its replay, the sync session, the local API with the same routes the web pages use, crypto through a provider
interface, courses, diagnostics). Its tests (`cd core && nim test`) run without a device, emulator or desktop. Two
files there bind a platform's crypto behind that provider interface (`provider_gnutls.nim`, `provider_cng.nim` with
`kks_cng.c`); the rest imports no platform API (it links zlib for compression only). The platform layers
(`platform/linux`, `platform/windows`, `android/`, `apps/`) are adapters around it.

**No plant data is in this repository.** Drawings, tag lists, procedures and photos belong to a plant: its manager
publishes them to the plant's own devices. The program ships only the KKS decode tables (`data/kks.json`) and the
Learning courses.

The old KKS Explorer code (Python server, WebView Android app, desktop package, Python reader) was removed on
2026-10-03; it is in git history, and its notes are on the wiki.
