# Cutover: from the v1 system to v2 (phase 9)

The plan for moving the live plant from the Python server, the packaged desktop app and the WebView Android app to the
v2 server and the native apps. Written 2026-10-03; to be **rehearsed on copies first**, then run once with the user.

## What changes

| | v1 (today) | v2 (after) |
|---|---|---|
| Server | `python3 app.py` from the development checkout; files in the repo root | `~/kks-server` (`deploy/install-server-user.sh`): an installed snapshot, a user systemd service, storage key sealed by `systemd-creds --user` |
| Plant log | v1 entries (Ed25519) in `plant.db` | v2 entries (P-256), one-time import (PROTOCOL-v2 §21) |
| Drawings | PNG + SVG per sheet | path store (`.kkp`) + JXL pyramid + the source PDF; **tags and notes kept as they are** (`kks-import --keep-tags`) |
| Android | `kks.explorer` (WebView) | the new app (native, new package ID with the new name). Phones move **by themselves** through the bridge update of the old app (decision 0042, PROTOCOL-v2 §21a): open changes and photos come along |
| Laptops | PyInstaller package / browser | GNOME: Flatpak; Windows: self-signed MSIX (decision 0022), or the zip fallback |
| Browsers | v1 pages from the Python server | v2 pages from the v2 server (iPhone path) |

## Before the day

1. **Rename decided** (the user, 2026-10-03: the project outgrew "KKS Explorer"). App IDs (Android package, Flatpak ID,
   MSIX identity) change with it: the cutover is the one moment that costs nothing extra.
2. Everything committed; a version number for the cutover release (VERSION).
3. Build the release artefacts from that commit:
   - Android: **two** APKs signed with the maintainer's key (docs/ANDROID_RELEASE.md): the old app as the bridge
     (`android/app`, `kks-explorer.apk`) and the new app (`android/app2`, `kks-explorer-2.apk`), both listed in the
     same signed `release.json` (`tools/release.py`);
   - Flatpak bundle (`flatpak build-bundle`, apps/gnome/README), for Linux laptops;
   - Windows MSIX (`packaging/windows/make-msix.sh`, decision 0043) signed with our certificate, plus the certificate
     for IT (or the zip);
   - `deploy/install-server-user.sh` run from the commit (the server snapshot).
4. **Rehearsal on copies** (no live file touched): copy `~/kks-server/v1` to a scratch folder, run steps 3–6 below
   against it on test ports, open the result in a browser and an app, compare with the v1 server. Rehearse the phone
   move on the emulator: 0.8.0 joined to the copy, an unsynced photo, the bridge from a local test release
   (`DebugUpdateReceiver`), the new app moving by itself, the photo in Approvals. Repeat until clean.
5. Inventory: the devices and people in the v1 log (`app.py users`, Manage → Devices), so every device is accounted for
   on the day.
6. Tell the team the date, and that one update is all they will need to do (no freeze for phones).

## On the day

1. **Decide what is pending in v1** (Approvals on the v1 server): the migration refuses pending proposals. Teammates
   do **not** need to stop: whatever their phones hold that hasn't reached the server comes along later (§21a).
2. **Stop the v1 server.** From here 0.8.0 phones can't sync; they keep working offline.
3. **Back up, twice.** Copy the live files (plant.db with its -wal, root.key, photos/, backups/, plant-data/) to
   `~/kks-server/v1` again, check every file's SHA-256 against the source; plus an offline copy (USB stick) including
   `root.key`. Nothing in the repo is deleted.
4. **Migrate the log.**
   - `python3 tools/m6/migrate_v1.py export` on the copy → the package. It replays v1 completely and stops on any
     doubt. Since 2026-10-03 the package also lists the v1 devices.
   - `kks-server import-v1 PACKAGE.json` into `~/kks-server/state/server.db`. It prints the v2 root and the server's
     peer ID.
   - `python3 tools/m6/migrate_v1.py succession --db COPY --root-key v1/root.key --v2-root ROOT --server PEER --out
     s.json`, then `kks-server import-succession s.json`: the v1 root key vouches for the new server, so v1 phones
     can move by themselves.
   - Compare `kks-server dump-state` with the v1 state (the dry run of 2026-09-30 matched).
   - Delete the package and s.json afterwards (the package holds password hashes).
5. **Convert the drawings.** Copy `v1/plant-data` to `state/plant-data`; for each of the 11 sheets
   `kks-import SOURCE.pdf "" ID --keep-tags --data-dir state/plant-data` (rehearsed 2026-10-03 on a copy: all 11 sheets
   came out the same size as v1, all 1,379 tags identical, names and notes kept). Then `kks-server publish-data
   state/plant-data`.
6. **Start v2** on the same machine, with the same LAN address and sync port 8421 (the phones remember that address):
   `systemctl --user start kks-server`, plus `loginctl enable-linger` so it runs without a login. It also waits in the
   v1 relay room and announces mDNS `prev`, so phones find it off the LAN too.
   Check: the web pages on the LAN address, sign in as the manager, the drawings, a tag's panel with its photos and
   notes, History.
7. **Publish the release** (`tools/release.py VERSION DIR --publish`): the bridge and the new app.
8. **Devices:**
   - **Phones, everyone's:** one message to the team: "Open the old app → Account → Updates → Download and install,
     then tap Install the new app". Nothing to type; Android asks twice. The new app joins, brings the photos and
     changes that hadn't reached the server, and the old app offers to remove itself.
   - **The manager's laptop:** the Flatpak app, "Join through a server", then back up the root key from it (Account).
9. **Check:** the moved phones' photos in Approvals; on each device the drawings, a recent change, a test edit that
   reaches the server and another device.
10. **Retire:** Manage → Devices lists the v1 devices that haven't moved yet. Once none is left, the bridge has done
    its job. Keep the v1 files read-only for 30 days.

## If something goes wrong

- Before step 7 (no release yet, no phone moved): stop v2 and start the v1 server from `~/kks-server/v1` (the repo's v1
  code at the cutover commit, with a config pointing there). Nothing is lost: phones still hold their unsynced changes
  and send them to v1 at their next sync.
- After devices joined v2: changes made in v2 since then would be lost by going back; fix forward unless the data is
  wrong, and decide that together.

## Open before the day

- The rename and its new app IDs. The new Android package ID goes into `android/app2` (applicationId),
  `Bridge.NEW_APP` in `android/app`, and both manifests (`<queries>`).
- Windows: the MSIX pipeline is built and tested with a test certificate (10 and 11). Still to do: make the real
  certificate with the new name (its subject becomes the publisher identity), and ask IT whether they will trust it
  by policy (`LocalMachine\TrustedPeople`).
- Which teammates use which devices (the inventory).
