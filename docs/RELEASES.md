# Releases and self-updates (M5b)

Devices look at the newest GitHub Release of `5wHN28Dg/kks-explorer` once a day (laptops: `update_check` in
config.json; phones: whenever the app is opened and the last check is a day old) and **only ask**: nothing is
installed without a click or tap.

## What makes a release trustworthy

Two keys, both on the maintainer's machine only (`~/.config/kks-explorer/signing/`, or `$KKS_SIGNING`), never in the
repository, never in CI. Back both up offline (USB stick in a drawer, a printed copy of the release key's hex seed).

- **Release key** (`release-ed25519.key`, Ed25519): signs `release.json`, the list of every file in a release with its
  SHA-256 and size. Its public half is pinned in `server/updates.py` and `android/core/.../Updates.kt`
  (`RELEASE_PUB`; a test checks both are the same). A device accepts a release only if this key signed it, and a file
  only if it matches the manifest. So whoever controls the GitHub account still can't ship an update on their own.
  Signature: base64url Ed25519 over `"kks-release-v1\n"` + the exact bytes of `release.json`.
- **APK signing key** (`kks-release.jks`, docs/ANDROID_RELEASE.md): Android installs an update only if it is signed
  with the same key as the installed app.

Lose the release key and devices can't be updated automatically any more: they would need one manual install of a
version that pins a new key (`python3 tools/release.py --new-key`).

## Making a release

1. Bump `VERSION` (e.g. `0.8.1`; Android's versionCode follows from it), commit, push.
2. Desktop packages: push a tag `v0.8.1` (or run Actions → Desktop packages by hand) and download the two artifacts
   into one folder, e.g. `gh run download <run id> -D ~/kks-release/0.8.1`. You get `KKS-Explorer-windows.zip` and
   `KKS-Explorer-linux.tar.gz`.
3. Android: `cd android && JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 ./gradlew :app:assembleRelease` (signed with
   your local key), then copy `app/build/outputs/apk/release/app-release.apk` into the folder as `kks-explorer.apk`.
4. Optional release notes in a text file.
5. `python3 tools/release.py 0.8.1 ~/kks-release/0.8.1 --notes notes.txt` writes and checks `release.json` +
   `release.json.sig`. Add `--publish` to create the GitHub release with all files (it asks before publishing; needs
   `gh` logged in). A release missing one of the three files is fine: those devices just don't see it.

## What devices do

- **Phone:** Account → Updates → "Download and install": the APK is downloaded, checked against the signed manifest,
  handed to Android's installer, which asks to confirm (the first time Android also asks to allow installs from KKS
  Explorer). Data stays.
- **Packaged desktop app:** Manage → Account → Updates → "Download and install": the package is checked and unpacked
  into the user folder (`versions/<version>/`); from the next start the installed program hands over to it
  (`desktop.py` → `updates.handoff`). The two newest versions are kept, older ones removed. The installed program
  itself is never modified (no admin rights needed on Windows).
- **Running from source** (a server, a git checkout): only a notice; update with `git pull` and restart.
