# M6 capability matrix (2026-09-30)

For each requirement in REQUIREMENTS.md: what each target platform provides through its supported stack
(the platform engineering guideline (CLAUDE.md, "Engineering guidelines"), "What counts as platform-provided"), what is optional, and what is
missing.

**Targets:**
- Windows 10/11;
- Linux = GNOME, as on Ubuntu 26.04 LTS (GNOME 50);
- Android 10+ (API 29);
- Safari 17+, the iOS path. Desktop browsers (Blink, Gecko) are noted where the web platform is a candidate.

**Markers:**
- ✅ provided;
- 🟡 optional component, partial, or version-gated;
- ❌ missing.

**Evidence:**
- **[V]** verified on the target (this Ubuntu 26.04 laptop);
- **[D]** read in vendor docs or registries this session (sources at the end);
- **[K]** long-standing vendor API, source linked but not re-read this session.

## 1. UI and accessibility (R1–R13, N2, N7)

| Need | Windows | GNOME | Android | Safari |
|---|---|---|---|---|
| UI toolkit | ✅ Win32 (stable C ABI); WinUI 3 / Windows App SDK (Microsoft's current path) [K] | ✅ GTK 4.22 + libadwaita 1.9 [V] | ✅ Jetpack Compose (Google's current model) + framework Views [K] | ✅ HTML/CSS/DOM |
| Accessibility API | ✅ UI Automation [K] | ✅ AT-SPI (GTK 4 accessibility) [K] | ✅ TalkBack / accessibility framework [K] | ✅ native elements + ARIA → VoiceOver [K] |
| Right-to-left and mixed text (Arabic in notes) | ✅ DirectWrite / Uniscribe [K] | ✅ Pango [K] | ✅ framework text stack [K] | ✅ Unicode bidi in CSS/HTML [K] |
| Embedded web engine the app can use | ✅ WebView2: part of Windows 11, installed on eligible Windows 10 devices [D] | ✅ WebKitGTK 6.0 (2.52) [V] | ✅ Android System WebView [K] | — (the page *is* the browser) |

## 2. Drawings and images (R1, R9)

| Need | Windows | GNOME | Android | Safari |
|---|---|---|---|---|
| Render the original vector PDF, any region at any scale (sharp tiles) | ✅ Windows.Data.Pdf (`SourceRect` + `DestinationWidth`, Windows 10 1507+) [D] | ✅ Poppler-GLib → Cairo [V installed] | ✅ `PdfRenderer.Page.render(bitmap, clip, matrix, …)`, API 21+ [D] | ❌ no PDF API (a library or pre-converted SVG is needed) |
| Draw vector paths / SVG | ✅ Direct2D (incl. SVG documents) [K] | ✅ Cairo, librsvg 2.61 [V] | ✅ Canvas/Path [K] | ✅ SVG, Canvas |
| **Performance of the above on 40k–140k-path sheets** | **unmeasured** | **unmeasured** | **unmeasured** | **measured today** (merged SVG, CLAUDE.md) |
| JPEG XL decode | 🟡 WIC codec, but only Windows 11 24H2+, optional Store install; none on Windows 10 [D] | ✅ glycin JXL loader (default in GTK 4.20+) [V]; libjxl 0.11 [V] | ❌ no version [D] | 🟡 Safari 17+ partial (still images work); desktop: Chrome 155+/Firefox 158+ yes, **Edge no** [D] |
| JPEG XL encode | 🟡 the same WIC codec (24H2+) [D] | ✅ libjxl 0.11 installed [V] (a distribution package; not a GNOME runtime guarantee) | ❌ [D] | ❌ (no canvas encoder) |

## 3. Camera and QR (R9, R13)

| Need | Windows | GNOME | Android | Safari |
|---|---|---|---|---|
| Take a photo | ✅ CameraCaptureUI / MediaCapture [K] | ✅ Camera portal → PipeWire [D]; PipeWire 1.6 [V] | ✅ camera intent / CameraX [K] | ✅ `getUserMedia`, `<input capture>` [D] |
| Decode a QR code from the camera | 🟡 built-in camera barcode scanner with QR (Windows 10 1803+, WinRT point-of-service API; needs a package capability, so **probably requires MSIX packaging**, unverified) [D] | ❌ not in the GNOME platform; zxing-cpp 2.3 happens to be installed here [V] (a distribution library, not GNOME) | ❌ framework none; ML Kit through Play services is optional [D] | ❌ `BarcodeDetector` only behind a preference [D] |
| Draw a QR code | ❌ | ❌ | ❌ | ❌ |

## 4. Storage and security (R11, R14, N1, N1a, N5)

| Need | Windows | GNOME | Android | Safari |
|---|---|---|---|---|
| Local database | ✅ SQLite "included with Windows" [D] | ✅ SQLite 3.46 [V] | ✅ framework SQLite [K] | ✅ IndexedDB; OPFS (15.2+) [D] |
| Ed25519 | ❌ not in CNG [D] | ✅ Nettle/GnuTLS [V installed] | 🟡 API 33+; missing on 29–32 [D] | ✅ WebCrypto, 17+ (all engines now) [D] |
| X25519 | ✅ CNG `BCRYPT_ECC_CURVE_25519` [D] | ✅ Nettle/GnuTLS [V installed] | 🟡 `XDH` API 33+ [D] | ✅ WebCrypto, 17+ [D] |
| ChaCha20-Poly1305 / AES-GCM | ✅ both in CNG (ChaCha from Windows 10) [D] | ✅ Nettle/GnuTLS [V installed] | ✅ ChaCha API 28+, AES-GCM [D] | 🟡 AES-GCM only; no ChaCha in WebCrypto [D] |
| Password hashing (scrypt/Argon2) | ❌ (PBKDF2 only in CNG) [K] | 🟡 Nettle: PBKDF2; scrypt via OpenSSL 3.5 [V installed] | 🟡 PBKDF2 [K] | 🟡 PBKDF2 [K] |
| Secure key storage | ✅ DPAPI (per user) [D]; CNG key storage with TPM [K] | ✅ Secret Service: libsecret + GNOME Keyring [V]; Secret portal = a per-app secret for sandboxed apps [D] | ✅ Android Keystore, per app, hardware-backed where available [K] | 🟡 non-extractable WebCrypto keys in IndexedDB [K] |
| Disk encryption guaranteed | ❌ BitLocker device encryption only on qualifying hardware [D] | ❌ LUKS optional at install [K] | ✅ file-based encryption required on devices launching with Android 10+ [D] | ✅ iOS data protection [K] |

## 5. Network and sync (R15–R20)

| Need | Windows | GNOME | Android | Safari |
|---|---|---|---|---|
| TCP/UDP sockets, listening | ✅ Winsock [K] (first-run firewall prompt) | ✅ [V] | ✅ [K] | ❌ no listening, no raw sockets |
| Connections the web platform offers | — | — | — | ✅ WebSocket; WebRTC data channels (11+); WebTransport (26.4+) [D] |
| HTTP server (browser access, R19) | ✅ HTTP Server API (http.sys) [D] | ✅ libsoup 3.6 server [V installed] | 🟡 none in the framework [K] | ❌ |
| WebSocket client | ✅ WinHTTP WebSocket [K] | ✅ libsoup [V installed] | ❌ framework none (OkHttp is a library) [K] | ✅ |
| Device discovery (DNS-SD) | ✅ `DnsServiceRegister`/`Browse`, Windows 10+ [D] | ✅ Avahi 0.8 over D-Bus [V] | ✅ NsdManager [K] | ❌ |
| Background work | ✅ Task Scheduler, startup apps, tray [K] | ✅ Background portal (run in background, autostart) [D]; systemd user units [K] | ✅ WorkManager [K] | ❌ Background Sync / Periodic Sync: Blink only, not Safari or Firefox [D] |
| Notifications | ✅ app notifications (Windows App SDK) [K] | ✅ GNotification / notification portal [K] | ✅ [K] | 🟡 16.4+ only for Home Screen web apps [D] |
| Storage kept, not evicted | ✅ | ✅ | ✅ | 🟡 `persist()` 15.2+; Home Screen web apps are exempt from the 7-day eviction [D] |

## 6. Plant data tooling (R21, R22)

| Need | Windows | GNOME | Android | Safari |
|---|---|---|---|---|
| PDF → vector geometry, SVG export (importer) | ❌ (Windows.Data.Pdf only rasterizes) [D] | ✅ Poppler + Cairo SVG surface [V installed] | n/a (manager's machine) | n/a |
| Contour detection, glyph classification | ❌ none in any platform | ❌ | n/a | n/a |

## 7. Distribution, updates, languages (R23, R24, N6)

| Need | Windows | GNOME | Android | Safari |
|---|---|---|---|---|
| Per-user install, no admin | ✅ MSIX with App Installer [D], **but needs a trusted signing certificate** (self-signed = import on every machine) [D]; or a plain per-user folder | ✅ Flatpak (per-user) [V installed 1.16]; or a plain folder | ✅ APK install (the person allows unknown sources) [K] | ✅ nothing to install |
| Platform update mechanism | ✅ App Installer auto-update outside the Store [D] | ✅ Flatpak remotes [K] | 🟡 PackageInstaller (our code, user confirms) [K] | ✅ automatic |
| Code signing | 🟡 SmartScreen reputation needs a paid or managed certificate [K] | 🟡 Flatpak repo GPG key (ours) [K] | ✅ our own APK key [K] | ✅ HTTPS |
| Languages the vendor supports | C/C++ (Win32, WinUI), C# (.NET; not preinstalled beyond .NET Framework 4.8) [K]; Rust through Microsoft's `windows-rs` (active) [D] | "C++, JavaScript, Python, Rust and Vala", C the default [D]; gtk4-rs active [D]; GJS 1.88 installed [V] | Kotlin/Java; C/C++ through the NDK (no UI) [K] | JavaScript / WebAssembly |

## Gaps: what no platform provides, or only some do

These become decision records (docs/decisions/0014 and on):
1. **Protocol and trust core** (signed history, merge, sync protocol): ours on every platform. That is the product.
2. **Ed25519** on Windows and on Android 10–12. X25519, ChaCha20-Poly1305 and AES-GCM exist almost everywhere; Safari
   has no ChaCha. So the cipher choice itself is a decision (AES-GCM is everywhere).
3. **JPEG XL** encode on Windows 10, Android and in Safari; decode on Android and in Edge (Windows' default browser)
   and on Windows 10.
4. **QR decode** on GNOME, on Android without Play services, and in Safari; on Windows possibly packaged-only.
   **QR encode** nowhere.
5. **PDF in Safari** (the browser path needs converted drawings); PDF tile rendering elsewhere is platform-provided
   but its speed on our sheets is **unmeasured**.
6. **Disk encryption** not guaranteed on Windows or GNOME. App-level encryption at rest (N1a) is needed there;
   Android and iOS have it from the platform.
7. **Background sync** impossible in Safari; the browser path syncs only while open.
8. **Importer** geometry and classification: our code on the manager's machine; Poppler is platform-provided on GNOME
   only.
9. **Windows distribution:** a trusted signing certificate is needed for a smooth per-user install and update.
10. **Password hashing** stronger than PBKDF2 is platform-provided only through OpenSSL on Linux.

## Measurements needed before deciding

The policy says measure on the target.
- **PDF tile rendering** of our heaviest sheet: time per 512 px tile at 1×, 4× and 16×, with Windows.Data.Pdf,
  Poppler and Android PdfRenderer, against today's merged-SVG approach.
- **Today's app as the baseline:**
  - startup time;
  - installed size (desktop 79 MB, APK 35 MB);
  - steady memory;
  - sync time for a day's changes;
  - measured on a clean Windows, GNOME and mid-range Android device.

## Sources

- MDN browser-compat-data: SubtleCrypto, SyncManager, PeriodicSyncManager, StorageManager, WebTransport,
  RTCDataChannel, Notification, BarcodeDetector (https://github.com/mdn/browser-compat-data); caniuse jpegxl/webp/avif.
- Windows:
  - CNG algorithm identifiers: https://learn.microsoft.com/en-us/windows/win32/seccng/cng-algorithm-identifiers
  - CNG named curves: https://learn.microsoft.com/en-us/windows/win32/seccng/cng-named-elliptic-curves
  - DPAPI `CryptProtectData`
  - HTTP Server API `HttpInitialize`
  - DNS-SD `DnsServiceRegister` / `DnsServiceBrowse`
  - WebView2 Evergreen: https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/evergreen-vs-fixed-version
  - SQLite included with Windows: https://learn.microsoft.com/en-us/windows/apps/develop/data-access/sqlite-data-access
  - Windows.Data.Pdf `PdfPageRenderOptions`
  - App Installer auto-update: https://learn.microsoft.com/en-us/windows/msix/app-installer/auto-update-and-repair--overview
  - MSIX signing: https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview
  - Camera barcode scanner: https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/pos/camerabarcode-system-requirements
  - BitLocker device encryption: https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/
  - JPEG XL Image Extension (Windows 11 24H2): https://www.ghacks.net/2025/03/03/windows-11-how-to-add-jpeg-xl-support-officially/
- GNOME:
  - installed package versions on Ubuntu 26.04 (`dpkg-query`, GNOME Shell 50.1);
  - glycin formats: https://blogs.gnome.org/sophieh/2025/06/13/making-gnomes-gdkpixbuf-image-loading-safer/
  - portals: https://flatpak.github.io/xdg-desktop-portal/docs/
  - languages: https://developer.gnome.org/documentation/introduction/languages.html
- Android:
  - `Cipher` / `Signature` / `KeyAgreement` / `KeyPairGenerator` reference;
  - `PdfRenderer.Page`;
  - supported media formats: https://developer.android.com/media/platform/supported-formats
  - file-based encryption: https://source.android.com/docs/security/features/encryption/file-based
