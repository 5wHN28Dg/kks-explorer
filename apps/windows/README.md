# Walkdown for Windows (M6 phase 7)

Win32 controls and a Direct2D drawing view on the Nim core (decisions 0014, 0027, 0033). It shares the device logic
with the GNOME app (`apps/common/appstate.nim`) and the platform layer with the server
(`platform/linux/src/kksl/{dbstore,net}`, `platform/windows/src/kksw/{tls,mdns,keystore}`).

## Build (cross-compiled here, no Windows needed)

    platform/windows/build-deps.sh       # once: zlib, libjxl, zxing-cpp for Windows into ~/.local/kksdev/winx64
    apps/windows/build.sh                # → /tmp/kkswin/Walkdown.exe (one static exe, ~16 MB)
    KKS_WIN_ARCH=aarch64 sh platform/windows/build-deps.sh       # Windows on ARM64 (decision 0047):
    KKS_WIN_ARCH=aarch64 apps/windows/build.sh OUT/Walkdown.exe  # libraries in ~/.local/kksdev/winarm64

The toolchain for both architectures is llvm-mingw (clang, lld, mingw-w64, libc++; UCRT; decisions 0047, 0053),
unpacked into `~/.local/kksdev/llvm-mingw` by `sh platform/windows/fetch-llvm-mingw.sh` (one release, pinned by
SHA-256; no root needed; the build scripts run it). The Nim settings for it are in `platform/windows/toolchain.nims`,
which the `config.nims` of core/, platform/linux/, platform/windows/ and apps/windows/ include.
`res/kks.manifest` provides Common Controls v6, per-monitor DPI v2, the UTF-8 code page and the Windows 10/11 compatibility entry.

## What is where

- `kks_explorer.nim`: the window, the message loop, the timers that pump asyncdispatch and collect tiles, the
  restart after a wipe.
- `src/kkswin/`:
  - `w32.nim`: hand-written Win32 bindings;
  - `ui.nim`: pages of labelled fields, buttons and lists (the UIA names come from the labels); guards log errors to
    `crash.log`. A control's handlers are kept by its window handle (the id in `WM_COMMAND` is 16 bits, and every
    rebuilt page takes new ids). A handler runs after the control's notification has returned, and only if its
    control is still there: one whose page was rebuilt in between does nothing (#162, `tests/test_ui_stale.nim`,
    which also pins what can come in between on Windows: sent messages and earlier posted ones, never a timer). A
    page made again by one of its own buttons gets back what was typed into its other fields (`keptText`,
    `restoreText`, #168); text whose field went or changed underneath is shown to the person, never dropped unseen.
    The sidebar is never made again under the keyboard: a sync then changes only what it can in place (the search's
    results, the sheets' counts, the procedures' links), the rest once the keyboard has left;
  - `viewer.nim` + `kks_d2d.cpp`: the drawing (overview pyramid; vector tiles drawn by Direct2D into WIC bitmaps on
    worker threads; tag hotspots; marking). Dark drawings (the sidebar's three choices, remembered per device: follow Windows' app mode, always dark, always light): every
    colour's lightness inverted, its hue kept, on the worker threads (`kks_dark_rgb`, a copy of
    `apps/common/darkcolor.nim` that `tests/test_dark.nim` checks on every 8-bit colour); tag outlines lightened.
    A sheet is shared by its owner and its tile jobs and goes with the last of them, so a sheet switch never frees one
    a worker is still rendering (`tests/test_tiles.nim`);
  - `multi.nim`: "Select tags" (a check box in the sidebar): a click or a tag button toggles a tag, a dragged box adds
    the tags it touches, a search result toggles its code whatever drawing it is on (the drawing stays, and the
    selection survives switching drawings); the right-hand panel then has the count, the List (each code with its
    drawings; "Add codes" takes typed or pasted codes that are on some drawing) and one photo, place or note for all
    the codes (core `/api/submit-many`; Place for all asks before replacing values, and sends as each code's base
    what it showed before asking; Photo for all asks the floor first when a code has none, names those codes, and
    sends it with the photo: the core writes it for them only). The List, the forms and the floor question close
    when the mode ends; a tag opened from elsewhere asks before it drops a selection;
  - `kks_uia.cpp`: the drawing's tags as UI Automation buttons;
  - `win.nim`, `panel.nim`, `side.nim` (search, sheets, floors, procedures with link mode, the review queue),
    `systems.nim` (Equipment by system: core `systemsView` in a window with a search field and a native TreeView;
    Coverage opens it filtered to one system), `coverage.nim` (Coverage: core `coverageView`, totals and a row per
    sheet and per system with its photo bar, new numbers put in place at each sync; a sheet row opens the sheet
    coloured by photos, a system row Equipment by system), `links.nim` (links between drawings: core `linksView`, the
    connectors as circled hotspots and UI Automation buttons, "Connectors on this sheet"; one target opens it, several
    ask, none says so),
    `manage.nim` (approvals one card per code, my proposals with filters, the leaderboard, history, people, devices
    with the invite QR via `kks_qr.cpp` and hiding removed ones, account with the root key backup), `setup.nim` (all
    ways to join, each asking a new member's position, or a new plant);
  - `about.nim` + `aboutinfo.nim`: About Walkdown (Manage → About Walkdown…, the setup screen's button, F1 anywhere,
    the window's system menu): the version with the commit it was built from ("with local changes" for a build that
    had some; `build.sh` passes `-d:kksCommit`/`-d:kksDirty` as the server's installer does), what Walkdown is, its
    licence (with its full text), the home page, issues and help, the source of exactly this version, the
    free-software and no-warranty notice, the Windows app's third-party parts (a list; the selected one's notice and
    the full text of each of its licences beside it) and the course photos' credits with their links; Copy details
    (version, commit, Windows version). All from the shared `data/about.json` compiled in (`kksl/buildinfo`);
    `aboutinfo.nim` holds the logic without Win32 (`tests/test_about.nim`). Links open in the default browser, https
    only;
  - `photos.nim` + `kks_img.cpp`: thumbnails with who took each, a viewer, adding from a file (the floor first when
    the code has none; WIC → upright → 2560 px → `annotate.nim`, the mark-up editor with arrow, box and circle in four
    colours plus undo, the marks burned in by Direct2D → the photo queue, kept on disk (`apps/common/photoqueue.nim`:
    each photo's pixels and job as sealed rows in the device's store, whose key DPAPI protects; removed only once
    the core accepted or refused it; a restart sends what is left, in order, with the same client_id; a removed
    device's wipe deletes it): JPEG XL d1.9 on a worker thread, in order; a photo that fails is tried again a minute
    later (5 times in a run, then at the next start) and shows under "Photos not sent" with Try again and Discard;
    Photo for all goes through the same queue, sent with one submit-many), and the tag plate's photo.
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
- turns the desktop user's notifications off while it runs, and back as they were afterwards (their value is kept
  in `C:\kks\toasts-before.txt` until then): a notification left on screen until answered, such as OneDrive's
  "Turn On Windows Backup", takes the keyboard focus from the app when a script's console window closes. That needs
  an administrator account, as the VMs' is; on a borrowed laptop's standard account (below) nothing is changed and
  the test says so: answer any notification on its screen before a run.

It covers:
- joining (TLS enroll);
- a drawing tag invoked through UIA;
- Equipment by system (search, the tree item, Enter and the button open the tag, Esc closes);
- Coverage (the totals, a sheet's row updated in place by a sync with the focus in the list, a sheet row opens it
  coloured by photos, a system row opens Equipment by system filtered to it);
- links between drawings (connectors as buttons on the drawing and in Connectors on this sheet; none, one and
  several targets);
- search and the decoded panel;
- an edit synced to the server;
- a photo marked up with a box (the server's JPEG XL is decoded to check the box is in it);
- dark drawings (the drawing's pixels as drawn, overview and tiles; the choice after a restart);
- several tags at once (a dragged box, search results, a tag button; the List; place, note and photo for all; a
  member's photo for all on codes without a floor: the floor asked first and proposed with the photo; codes of
  another drawing picked from the search and typed into the List);
- the valve type from the drawing's symbol in the panel, confirmed with its button;
- a member's proposal approved in Manage;
- the floor asked before a photo and sent with it; who took each photo and set each field; My proposals' filters;
  deleting a photo;
- the photo queue (a failed encode kept, Try again, or tried again by itself; the next photo compressed while the
  panel closes; closing the window asks first; killed with photos queued, the next start sends them, once each, in
  order, even when it dies right after the core took the first);
- drafted descriptions confirmed as they are or edited;
- Approvals by code ("Use this one" only between competing photos of one kind, the card opens its tag) and the
  Leaderboard;
- a new member's position (the join form refuses without one, the admin sees it; a new plant too);
- removed devices hidden (Clear removed, Show hidden, Show … again);
- what is typed into the panel's edit form kept when a sync arrives with the keyboard elsewhere, and a Save whose
  panel was rebuilt before its handler ran sending nothing (`KKS_TEST_STALE_CLICK`);
- what is typed kept elsewhere too (#168): the Procedures and Drawings searches through syncs, with the keyboard in
  them (the list follows in place; a new floor waits until the keyboard has left) and away; the edit form through
  Confirm valve type and Confirm description, a corrected reading through Edit and Cancel;
- About Walkdown from the setup screen, F1 and Manage (the version and commit, the licence and its full text, the
  source link, libjxl's and a font's notices and licences, a photo credit's links, Copy details, Esc);
- the tabs and the sidebar's pages beside the drawing at 1366 × 768 and 1920 × 1080, never under it (rectangles apart,
  each control what the hit test finds at its middle; `tests/test_tabs.nim` the tabs at 100, 125 and 150 % scaling);
- removal and the self-wipe.

## A real (borrowed) Windows laptop

`e2e/host/kks-test-host.ps1` prepares a laptop that isn't ours for the same tests and measurements, and undoes it
all afterwards. Run in PowerShell opened with "Run as administrator":

    powershell -ExecutionPolicy Bypass -File kks-test-host.ps1 -Setup -PublicKey "<a key of its own, e.g. ~/.ssh/kks_winlaptop.pub>"
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

### Running the tests on it

    KKS_LAPTOP=1 KKS_VM_KEY=~/.ssh/kks_winlaptop python3 apps/windows/e2e/test_windows.py LAPTOP_IP APP UIADRIVE SERVER IMPORTER
    KKS_TESTS=test_flow,test_draw_timing ...      # only these tests

- `KKS_LAPTOP=1`: this machine's ports stay closed to the LAN; the server's sync port reaches the laptop through an
  SSH reverse tunnel (the app joins `127.0.0.1`), and screenshots (`KKS_SHOTS`) come from `shot.exe` (`e2e/shot.cpp`,
  built by `build.sh` next to `uiadrive.exe`) in its desktop session, which opens no window.
- The standard account is refused WMI over SSH ("Cannot connect to CIM server. Access denied"), so `runapp.ps1`
  registers its task through the Task Scheduler's COM interface, and the tests read nothing through CIM. It may not
  restart the laptop from its SSH logon either (`shutdown`: "Access is denied"): run `shutdown.exe` through
  `runapp.ps1`, in the desktop session.
- Notifications stay on (no administrator): answer any on its screen before a run.
- `uiadrive.exe` is per-monitor DPI aware: every rectangle in physical pixels at any scaling.

### Results on a real laptop (2026-11-18)

The user's laptop: Intel Core i7 4th generation U (2 cores, 4 threads), 4 GB DDR3L, Intel HD Graphics 4400 (driver
10.18.15.4248; its AMD GPU disabled on purpose), SATA SSD, Windows 10 Pro, 1920 × 1080 at 125 % (Windows'
recommended scale for its panel).

- **The e2e suite** at 125 %: 28 of 28 passed (32 minutes, with #427). Before, `test_photo_queue` failed twice:
  the photo was compressed and sent before the test's next look at "Compressing 1 photo"; the test now holds each
  compression 8 s (`KKS_TEST_ENCODE_MS`).
- **Direct2D on a GPU** (`test_draw_timing`, `KKS_TIMING`: zoomed in eight steps and panned): the window's render
  target is the hardware one (the VMs: WARP). Two runs: a paint of the drawing took 1.25 and 1.35 ms median, 46 and
  33 ms at most (about 20 paints each); a tile's render 14.2 and 8.1 ms median, 64 and 58 ms at most (21 tiles, on
  worker threads). Lines sharp zoomed in (screenshots at 125 %).
- **Scaling:** 100, 125 and 150 % set while the app runs (as Settings does) and at its start: the window follows
  (`WM_DPICHANGED`), the tabs stay in one row beside the drawing (#427's `test_tabs_beside_drawing` passes at each,
  main before #427 failed at each). Left from #377: the status line keeps the old scale's font after a live change.
- **Text size 150 %:** `TextScaleFactor` written and a restart did not change Windows' own fonts; the system fonts
  scaled to 150 % live (`SPI_SETNONCLIENTMETRICS`, as "Make text bigger" does for desktop apps) grew the title bar but
  not the app's text, whose fonts are fixed in px from the DPI (#377). Every setting was put back afterwards.
- **Dark app mode:** the drawings follow it; the rest of the window stays light (#377).
- **High Contrast Black:** the window's controls follow the theme's colours; the drawing stays light, as drawn.
- **Walkdown Plant** (its Windows export, a test build, defaults unchanged): neither Direct3D 12 nor Vulkan on this
  GPU and driver ("Cannot find a compatible Vulkan installable client driver", then "switching to OpenGL 3" and, for
  this driver, ANGLE on Direct3D 11): the Compatibility renderer, tier lean+vis. The 300 s frame walk: median 85.5 ms
  (p95 131, p99 152, max 514) on the first start, 79.8 ms (p95 121, p99 141) on a later one; 0 % of frames at 30 fps
  or better. At 1280 × 720 without shadow and fog: 54.7 ms median. The draw takes ~70 of the 80 ms (773 draw calls).
  First frame 56.6 s after the very first start (shaders compiled), 7.5 s on later starts. Memory: about 0.97 GB
  private, 1.03 GB peak working set. One of four starts ended by itself 3.6 s into the walk, with no log line or
  crash report the standard account could read (#432).
- **Arabic:** the note `مضخة التغذية 11LAB70AA501 تعمل` shows with "11" apart from "LAB70AA501", as in the VMs (#379).

## Not done yet

- **Camera:** taking photos with the camera (photos come from a file). Scanning an invite QR with the webcam is built
  (decision 0039: Media Foundation + zxing-cpp); tested with a video file through the same Source Reader in both VMs
  and with this laptop's webcam passed into the Windows 11 VM (frames arrive), not yet with a real QR in front of a
  real webcam.
- **Packaging:** the firewall rule, and the real signing certificate (made with the new name; its subject is the
  package's publisher).
- **A real laptop:** company policy (Defender rules, AppLocker), Narrator by ear (GPU timings, scaling and themes:
  above).
- **CI:** a GitHub Actions run needs the user's OK to push.

## MSIX (decision 0043)

    packaging/windows/make-msix.sh --test-cert DIR               # a test certificate (CN=KKS Explorer Test)
    packaging/windows/make-msix.sh VM_IP CERT.pfx OUT.msix       # password in $KKS_MSIX_PASS

The script:
- cross-builds the app and lays it out: the exe, `data/courses`, `vendor/fonts`, and logos from `icon-512.png`;
- packs it with MakeAppx from the pinned `Microsoft.Windows.SDK.BuildTools` NuGet package, in the VM;
- signs it here with osslsigncode, so the key never leaves this machine (2.14, built from pinned source by
  `packaging/windows/build-osslsigncode.sh`).

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
