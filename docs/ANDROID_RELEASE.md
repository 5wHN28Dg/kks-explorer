# Android release builds (M3e)

The release APK is signed with a key that exists only on the maintainer's laptop, plus the backups the maintainer
makes. It is not in this repository and not in CI. CI (`.github/workflows/android.yml`) builds a debug APK and an
**unsigned** release APK, to check that the build works. Phones only install APKs you signed yourself.

## Where the key is

`~/.config/kks-explorer/signing/` (folder mode 700, files 600):

- `kks-release.jks`: PKCS#12 keystore, alias `kks`, RSA 4096, valid until 2056.
  SHA-256 of the certificate: `1A:3A:2B:53:BF:44:29:B3:F5:B2:FB:33:3E:28:66:E1:EE:41:61:65:48:CF:D1:9A:17:E3:E9:FF:89:EE:DE:B0`.
- `keystore.properties`: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Relative paths are resolved
  against this folder.

`KKS_SIGNING=/path/to/keystore.properties` points the build somewhere else (e.g. a USB stick).

**Back up both files together** (the password is useless without the keystore, and the keystore is useless without
the password). Put them on an encrypted USB stick, or in a password manager as attachments. Android only installs an
update if it is signed with the same key as the installed app. If the key is lost, every phone has to uninstall the
app and install it fresh, and the phone's copy of the plant log goes with it. That copy is re-synced afterwards, but
anything not yet synced is gone.

## Build

```sh
cd android
echo sdk.dir=$HOME/Android/Sdk > local.properties       # once
JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 ./gradlew :app:assembleRelease
# → app/build/outputs/apk/release/app-release.apk (signed)
~/Android/Sdk/build-tools/*/apksigner verify --print-certs app/build/outputs/apk/release/app-release.apk
```

Without `keystore.properties` the same command produces `app-release-unsigned.apk` (this is what CI makes).

Before a release: raise `versionCode` (Android refuses to install a lower or equal one over an installed app) and set
`versionName` in `app/build.gradle.kts`.

## What the release build does differently

- R8 shrinks and optimizes the code (`proguard-rules.pro` keeps the JS bridge, the JNI methods and the worker).
- Unused resources are removed.
- The debug-only pieces (`src/debug`: the DEBUG_SYNC broadcast receiver, WebView DevTools) are not in it.

## Installing

Copy the APK to the phone and open it; the first time, Android asks to allow installs from that app (Files, the
browser, …). Or, from the laptop: `adb install -r app-release.apk`. A phone that has the debug build installed
must uninstall it first, because the debug key is different.
