# 0042 Moving phones from the v1 app to the v2 app without help (bridge update)

Date 2026-10-03 · Scope: the cutover (docs/CUTOVER.md), the v1 Android app (`android/app`, package `kks.explorer`),
the v2 Android app (`android/app2`), the v2 server, PROTOCOL-v2 §21a · Status: **accepted by the user 2026-10-03**
("Bridge update, new ID"); details by Claude.

**Question:** teammates run 0.8.0 of the v1 app on their phones, away from the manager. How do they move to the v2 app
by doing nothing more than installing an update, without losing the changes and photos that haven't reached the
server yet?

The user's constraints: teammates use phones only; the new app gets a **new package ID** (`io.github.walkdown`: the app is now called Walkdown); the
cutover waits until this is built and rehearsed.

## Findings

| | Fact | Source |
|---|---|---|
| New package ID | Android treats a different application ID as a different app: it can't be installed as an update over 0.8.0, and it can't read 0.8.0's data | [D] https://developer.android.com/build/configure-app-module#set-application-id |
| What 0.8.0 can do | It checks the GitHub release `latest` once a day (`release.json`, signed with our Ed25519 release key) and installs `kks-explorer.apk` when the person taps "Download and install" in Account → Updates. There's no badge, so teammates must be told to open Account once | the 0.8.0 code (`AppUpdates.kt`, `Updates.kt`, `Shell.kt`) |
| Installing another app | `PackageInstaller` sessions install any package. The app needs `REQUEST_INSTALL_PACKAGES`, which 0.8.0 already holds, and the person confirms | [D] https://developer.android.com/reference/android/content/pm/PackageInstaller |
| Passing data between the two apps | A `ContentProvider` guarded by a permission with `protectionLevel="signature"` only answers apps signed with the same certificate. `call()` carries small requests and `openFile()` carries files | [D] https://developer.android.com/guide/topics/manifest/permission-element · https://developer.android.com/reference/android/content/ContentProvider#call(java.lang.String,%20java.lang.String,%20android.os.Bundle) |
| Ed25519 | The v1 keys are Ed25519. Android 10's platform crypto has no Ed25519; the v1 app uses BouncyCastle (audited in 0001–0013). The v2 app uses only the platform's P-256. GnuTLS ≥ 3.6 verifies Ed25519 (the server's library) | [D] https://gnutls.org/manual/html_node/Verifying-a-certificate-in-the-context-of-TLS-session.html · v1 `Crypto.kt` |
| v1 → v2 bodies | The data bodies (`equipment`, `review`, `link`, `photo`, `photo_delete`, `tag_add`, `tag_remove`, `comment`) are identical in v1 and v2, and photos keep their blob hashes | PROTOCOL.md §9 vs PROTOCOL-v2 §9 |

## Choice

**A bridge release of the v1 app (same package, same signing key), published as the GitHub `latest` release at
the cutover.** It does one job: install the v2 app, then hand over to it. All Ed25519 work stays in the bridge and on
the server, so the v2 app gains no crypto.

1. **The teammate taps "Download and install"** in 0.8.0's Account → Updates. That installs the bridge over 0.8.0, keeping
   its data. The bridge is the v1 app built at the cutover release's version (the VERSION file), so it doesn't
   offer itself as an update again. The same signed `release.json` lists the new app's APK, `kks-explorer-2.apk`
   (`tools/release.py`).
2. **The bridge opens on a single screen**, "Moving to the new app":
   - it downloads the v2 APK listed in the same signed `release.json`, with its hash checked;
   - it installs the APK (Android asks once);
   - it opens the new app.
3. **The new app asks the bridge** (through the signature-guarded provider) for the plant's v1 root, its v1 device,
   the remembered server addresses and the relay.
4. **It finds the v2 server** at those addresses (the server keeps sync port 8421), by mDNS TXT `prev` = v1 root[:16],
   or in the **v1 relay room**, where the server is also present. It asks the server for the **succession statement**
   (§21a). The v1 root key signs that statement: the v2 root, the server's peer ID, the archive hash, and the last
   archived seq of every v1 device. TLS must show that same server peer ID.
5. **The bridge checks the statement** against the v1 root it already trusts. Only if it verifies does the bridge:
   - sign the **migration proof** with its v1 device key: the new device's P-256 key and the v2 root;
   - return its own changes after its archived seq that are still open (pending, or applied directly for admins),
     with their photo files and request notes;
   - return the person's course progress.
6. **The new app sends the proof** (`migrate`, §21a). The server verifies it against the v1 device list kept from the
   import (known, not revoked, not moved before) and certifies the new device for the same person. The new app syncs,
   writes the handed-over changes as its own entries, and syncs again. Teammates find them in Approvals as usual.
7. **The bridge offers "Remove the old app".**

**Not carried over:** votes, approvals or rejections made offline after the cutover, and an admin's held conflicts.
These are rare, and the new app lists them so the person can redo them. A v1 device the manager removed can't move.
A second move of the same v1 device, for example after the new app was wiped, is refused: that person joins
normally.

**Security:**
- The handover only reaches an app signed with our key.
- Nothing leaves the bridge until the v1 root's signature proves the server is the plant's.
- The proof binds the new key and the v2 root, so it can't be used anywhere else.
- No platform mechanism is weakened.

**Alternatives rejected:**
- *Same package ID:* the user chose the new ID.
- *Teammates re-join by hand:* not possible this weekend, and pending photos would be lost.
- *Keep the v1 server running and import late entries:* it needs the v1 replay in Nim, and devices that update late
  would still miss out.

**When to revisit:** after the cutover, once every v1 device has moved (Manage → Devices lists which haven't). Then the
bridge is retired, the v1 room presence is switched off, and the server drops the v1 device table.
