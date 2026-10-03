# Walkdown for Windows (M6 phase 7)

Win32 controls and a Direct2D drawing view on the Nim core (decisions 0014, 0027, 0033). It shares the device logic
with the GNOME app (`apps/common/appstate.nim`) and the platform layer with the server
(`platform/linux/src/kksl/{dbstore,net}`, `platform/windows/src/kksw/{tls,mdns,keystore}`).

## Build (cross-compiled here, no Windows needed)

    platform/windows/build-deps.sh       # once: zlib, libjxl, zxing-cpp for Windows into ~/.local/kksdev/win64
    apps/windows/build.sh                # → /tmp/kkswin/Walkdown.exe (one static exe, ~14 MB)

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

## A real (borrowed) Windows laptop

`e2e/host/kks-test-host.ps1` prepares a laptop that isn't ours for the same tests and measurements, and undoes it
all afterwards. Run in PowerShell opened with "Run as administrator":

    powershell -ExecutionPolicy Bypass -File kks-test-host.ps1 -Setup -PublicKey "<contents of ~/.ssh/kks_vm.pub>"
    powershell -ExecutionPolicy Bypass -File kks-test-host.ps1 -Status
    powershell -ExecutionPolicy Bypass -File kks-test-host.ps1 -Revert     # before giving it back; restart; again if asked

- **Setup** makes a standard (non-admin) local account `kks` that can't open other users' folders, signs it in
  automatically (password as an LSA secret; skipped if the laptop already signs someone in), adds the OpenSSH server
  only if missing (key login for `kks` only, local network only), a separate "KKS test" power plan, firewall rules in
  group "KKS Explorer test" (local network only) and `C:\kks`. Every step is recorded in
  `C:\ProgramData\KKS-test\state.json`.
- **Revert** undoes the recorded steps in reverse order and deletes the account with its profile. The profile stays
  loaded after an SSH login until a restart: then it asks for a restart and a second `-Revert`.
- Verified on the Windows 11 VM (2026-10-03): firewall rules (names, owners, states), SSH config hash, power plans,
  accounts, profiles, OpenSSH shell and auto-login identical before and after; the test account got "access denied"
  on another profile and could not log in by password; auto-login to the test account worked after a restart and was
  restored afterwards. Not tried: installing and removing OpenSSH (the VMs need it to be reachable at all).

## Not done yet

- **Camera:** taking photos with the camera (photos come from a file). Scanning an invite QR with the webcam is built
  (decision 0039: Media Foundation + zxing-cpp); tested with a video file through the same Source Reader in both VMs
  and with this laptop's webcam passed into the Windows 11 VM (frames arrive), not yet with a real QR in front of a
  real webcam.
- **Packaging:** the firewall rule, and the real signing certificate (made with the new name; its subject is the
  package's publisher).
- **A real laptop:** GPU timings (the VMs render with WARP), company policy (Defender rules, AppLocker), Narrator by ear.
- **CI:** a GitHub Actions run needs the user's OK to push.

## MSIX (decision 0043)

    packaging/windows/make-msix.sh --test-cert DIR               # a test certificate (CN=KKS Explorer Test)
    packaging/windows/make-msix.sh VM_IP CERT.pfx OUT.msix       # password in $KKS_MSIX_PASS

The script:
- cross-builds the app and lays it out: the exe, `data/courses`, `vendor/fonts`, and logos from `icon-512.png`;
- packs it with MakeAppx from the pinned `Microsoft.Windows.SDK.BuildTools` NuGet package, in the VM;
- signs it here with osslsigncode, so the key never leaves this machine.

The package declares full trust, network client and server, the webcam, and the command-line alias
`walkdown.exe`.

Installing needs the certificate in `LocalMachine\TrustedPeople` (IT can push it by policy) and an interactive
session: `Add-AppxPackage` over SSH fails with 0x80070005 (e2e/msix.ps1 runs it in the desktop session).

The Windows e2e test runs against the installed package with:

    KKS_WIN_MSIX=OUT.msix KKS_WIN_MSIX_CER=CERT.cer python3 apps/windows/e2e/test_windows.py VM_IP

Verified 2026-10-03 on Windows 10 22H2 and 11 26H2: all three tests pass against the MSIX (11 MB). The process runs
from `C:\Program Files\WindowsApps\…` and its data goes to the package's folder. Uninstalling removes it (local
photos not yet synced would go with it: say so in the install notes). The test removes the package and the
certificate afterwards.
