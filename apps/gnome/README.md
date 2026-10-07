# Walkdown for GNOME (M6 phase 5; decisions 0014, 0016, 0031)

A native GTK 4 + libadwaita app in Nim, on the Nim core (`core/`) and the Linux platform layer (`platform/linux/`).
App ID `io.github._5wHN28Dg.walkdown`. Each device is a peer of the plant: it keeps the signed log in a sealed
SQLite store and syncs with the plant's other devices and its server.

## Build and run

Headers: GTK 4, libadwaita, libsecret, zxing-cpp and libjxl, from their -dev packages. Without root, `apt-get download` them
and unpack them into `~/.local/kksdev/root`; `config.nims` points pkg-config there. The libraries themselves are the
system's.

    cd apps/gnome && nim c -d:release kks_explorer.nim && ./kks_explorer

**Environment:**

| Variable | Effect |
|---|---|
| `KKS_DATA_DIR` | data folder; default `~/.local/share/kks-explorer`. A custom folder runs as its own application (own ID, non-unique), so two profiles can run side by side. |
| `KKS_STORAGE_KEY_FILE` | development and tests: a key file instead of the keyring |
| `KKS_SYNC_PORT` | first sync port tried (8421) |
| `KKS_NO_MDNS` | no mDNS |
| `KKS_SHOT=file.png[,secs[,quit]]` / `KKS_SHOT_ON_SIGNAL=file.png` | screenshots of the window through GTK's own renderer (tests; Wayland allows no outside capture) |
| `KKS_TIMING` | prints the startup time (docs/m6/MEASUREMENTS.md) |

## What it does

**Joining a plant:**
- through a server: username and password, sent over TLS on the sync port (PROTOCOL-v2 §16 `enroll`);
- with an invite code: the text, or a picture of the QR code read by zxing-cpp;
- by asking an admin on the same Wi-Fi: the 6-digit code;
- with a bundle file;
- or by starting a new plant.

**The drawing viewer:**
- overview pyramid levels decoded on a worker thread;
- vector tiles above the overview's resolution, drawn by Cairo and composited by GSK;
- tag hotspots by status;
- pan, zoom, pinch and keyboard (arrows, + −, 0).

**Search** by KKS (with or without the unit, partial, suffixes) or description.

**The equipment panel:**
- the decoded KKS, the location list, the person's own fields (read-only until Edit), custom fields;
- photos: annotate, JPEG XL at d1.9, a zoomable view;
- where the code appears, the procedures that use it;
- reviewing uncertain readings.

**Plant work:**
- marking missed tags;
- procedures with step ↔ equipment links (click tags in link mode, or Link in the panel);
- the review queue, a floor filter, the sheet's markup notes.

**Manage:**
- approvals (approve, approve anyway, pick a photo, reject);
- my proposals (withdraw, vote on photos);
- history (revert, restore);
- people;
- devices: invite QR, accepting devices nearby, join request files, bundles, remove;
- account: details, sync by address, root key backup and restore with a passphrase.

**Status:** devices reachable and the last sync. Screens refresh when the data changes underneath (R20).

## Tests

Run the tests headless, so no window opens on the desktop: `apps/gnome/e2e/headless.sh` starts a private
`mutter --headless` (one virtual monitor, Wayland only) in its own D-Bus session (its own accessibility bus) and its
own `XDG_RUNTIME_DIR` (so the portals it starts can't touch the desktop's `/run/user/$UID`), and runs
the command inside: `apps/gnome/e2e/headless.sh python3 apps/gnome/e2e/test_gnome.py`. Without a `mutter` binary,
unpack Ubuntu's package next to the GTK headers (`apt-get download mutter && dpkg-deb -x mutter_*.deb
~/.local/kksdev/root`; it is a launcher for the libmutter GNOME Shell already has).

`e2e/viewer_pinch.nim` checks that a touchpad pinch (a `begin` with a NULL sequence) doesn't crash the viewer; build
it and run it under `headless.sh` (the header says how).

`python3 apps/gnome/e2e/test_gnome.py` drives the app through its accessibility tree (AT-SPI), against the Nim server
and the importer, with no plant data. In about 30 s it covers:
- joining through the server;
- search and the decoded panel;
- an edit that syncs back to the server, Arabic text included;
- a member's proposal approved in the app;
- a second device joining by invite.

## Known limits and findings

**Accessibility:**
- A dialog built while GTK handles an accessibility action ("click" from a screen reader or AT-SPI) had no contents
  in the accessibility tree (GTK 4.22).
- So button handlers run from an idle callback (`ui.onClick`), and dialogs are presented from one (`ui.present`).
- Two app instances under one session's accessibility bus still interfere in tests. The test fetches what it needs
  from the first instance before starting the second.

**Flatpak** (built and tested 2026-10-03): `flatpak/` holds the manifest (GNOME 50 runtime, zxing-cpp built in, Nim
via `koch boot`), the desktop entry and the AppStream metadata. Build, install and make a single-file bundle:

    flatpak run org.flatpak.Builder --user --install --disable-rofiles-fuse --state-dir=state --force-clean build \
        apps/gnome/flatpak/io.github._5wHN28Dg.walkdown.yml
    flatpak build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo state/cache \
        walkdown.flatpak io.github._5wHN28Dg.walkdown master

The bundle is 6.7 MB (10.6 MB installed); it installs with `flatpak install --user --bundle walkdown.flatpak`.
The e2e test runs against the installed Flatpak through `e2e/flatpak-app.sh`, which passes the test's KKS_* settings
and /tmp into the sandbox, forwards its signals to the app and stops the sandbox at the end:
`python3 apps/gnome/e2e/test_gnome.py "$PWD/apps/gnome/e2e/flatpak-app.sh"`. All three tests pass, also from the
bundle. Under Flatpak the accessibility bus reports the PID of the sandbox's proxy, so `atspi.app_pid` also accepts
the newly appeared app by name.

**Not built or not verified yet:**
- pan frame times;
- Orca itself (the tree is checked through AT-SPI).
