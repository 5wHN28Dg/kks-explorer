# 0044 Self-updates for Walkdown on Android

Date 2026-10-03 · Scope: Walkdown for Android (`android/app2`); distribution (0022) · Status: **accepted** (the user:
after the move, teammates should need nothing more than the one update message; built by Claude).

**Question:** how does Walkdown on a phone get its next version without anyone sideloading an APK by hand? The old
app had an in-app updater, but its manifest signature is Ed25519, and Walkdown carries no Ed25519: it uses only the
platform's P-256 (0017, 0032).

## Findings

| | Fact | Source |
|---|---|---|
| Installing an update | `PackageInstaller` sessions with `REQUEST_INSTALL_PACKAGES`. The person confirms in Android's own dialog, and Android checks that the update is signed like the installed app | [D] https://developer.android.com/reference/android/content/pm/PackageInstaller |
| Verifying the manifest | `Signature.getInstance("SHA256withECDSA")` is in every Android version since API 1 and takes DER signatures. `KeyFactory("EC")` reads X.509 public keys | [D] https://developer.android.com/reference/java/security/Signature |
| The old updater | GitHub `releases/latest` → `release.json` + `release.json.sig` (Ed25519 over `"kks-release-v1\n"` + bytes) → the file's SHA-256 and size from the manifest | v1 `Updates.kt`, https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing |

## Choice

- **The same release:** the same GitHub release and the same `release.json`.
- **A second signature for Walkdown:** `release.json.p256`, a DER ECDSA P-256 signature over `"kks-release-v2\n"` +
  the manifest's bytes.
  - It is made by a second release key, `release-p256.pem`, kept in the signing folder next to the Ed25519 key.
  - `tools/release.py` signs with both.
  - The public key is pinned in the app.
- **Walkdown's APK** is `walkdown.apk` in the manifest.
- **The app checks once a day** while it is open, and shows a banner when a newer version is out. "Install" downloads
  the APK, checks its SHA-256 and size against the signed manifest, and hands it to Android's installer. Nothing
  installs without the person's tap and Android's confirmation.
- **The code:** `sync/Updates.kt` (fetch, verify, install), a receiver for the installer's answers, and the banner plus
  Manage → Account → Updates. A debug-only `DebugUpdateReceiver` points it at a test release for the e2e test.
- **Desktop apps are not covered here:** Flatpak updates come from its repository, and MSIX from App Installer (0022).
  Today they need a manual install of the new bundle.

**When to revisit:** if Walkdown moves to a store, or the release key changes.
