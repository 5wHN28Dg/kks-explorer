# KKS Explorer for Windows (M6 phase 7)

Win32 controls and a Direct2D drawing view on the Nim core (decisions 0014, 0027, 0033). It shares the device logic
with the GNOME app (`apps/common/appstate.nim`) and the platform layer with the server
(`platform/linux/src/kksl/{dbstore,net}`, `platform/windows/src/kksw/{tls,mdns,keystore}`).

## Build (cross-compiled here, no Windows needed)

    platform/windows/build-deps.sh       # once: zlib, libjxl, zxing-cpp for Windows into ~/.local/kksdev/win64
    apps/windows/build.sh                # → /tmp/kkswin/KKSExplorer.exe (one static exe, ~14 MB)

The toolchain is mingw-w64 13 / GCC 13, unpacked into `~/.local/kksdev/mingw` (decision 0033).
`res/kks.manifest` provides Common Controls v6, per-monitor DPI v2, the UTF-8 code page and the Windows 10/11 compatibility entry.

## What is where

- `kks_explorer.nim`: the window, the message loop, the timers that pump asyncdispatch and collect tiles, the
  restart after a wipe.
- `src/kkswin/`:
  - `w32.nim`: hand-written Win32 bindings;
  - `ui.nim`: pages of labelled fields, buttons and lists (the UIA names come from the labels); handlers run after
    the control's notification returns; guards log errors to `crash.log`;
  - `viewer.nim` + `kks_d2d.cpp`: the drawing (overview pyramid; vector tiles drawn by Direct2D into WIC bitmaps on
    worker threads; tag hotspots; marking);
  - `kks_uia.cpp`: the drawing's tags as UI Automation buttons;
  - `win.nim`, `panel.nim`, `side.nim` (search, sheets, floors, procedures with link mode, the review queue),
    `manage.nim` (approvals, proposals, history, people, devices with the invite QR via `kks_qr.cpp`, account with
    the root key backup), `setup.nim` (all ways to join, or a new plant);
  - `photos.nim` + `kks_img.cpp`: thumbnails, a viewer, adding from a file (WIC → upright → 1600 px →
    `annotate.nim`, the mark-up editor with arrow, box and circle in four colours plus undo, the marks burned in by
    Direct2D → JPEG XL d1.9).
- The KKS decode tables (`data/kks.json`) are compiled into the exe.

## Test

Windows 10 22H2 and 11 26H2 VMs under QEMU/KVM (decision 0033):
- an unattended install from `~/vms/unattend/`;
- OpenSSH with the key `~/.ssh/kks_vm`;
- auto-logon user `kks`.

    python3 apps/windows/e2e/test_windows.py 192.168.122.181     # (the VM's address)

The test:
- starts a Nim server here with the synthetic sample sheet;
- copies the app and `uiadrive.exe` (`e2e/uiadrive.cpp`) to the VM;
- drives the app through the native UI Automation core (what Narrator uses), from a scheduled task in the desktop
  session.

It covers:
- joining (TLS enroll);
- a drawing tag invoked through UIA;
- search and the decoded panel;
- an edit synced to the server;
- a photo marked up with a box (the server's JPEG XL is decoded to check the box is in it);
- a member's proposal approved in Manage;
- removal and the self-wipe.

## Not done yet

- **Camera:** camera capture and scanning an invite QR with a webcam (Media Foundation + zxing-cpp). The VMs have no
  camera, so this waits for a real laptop. Joining with a code takes the invite's text.
- **Packaging:** MSIX (0022), its firewall rule, signing.
- **A real laptop:** GPU timings (the VMs render with WARP), company policy (Defender rules, AppLocker), Narrator by ear.
- **CI:** a GitHub Actions run needs the user's OK to push.
