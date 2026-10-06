# Capability matrix: Walkdown

From the policy's templates/capability-matrix.md. Required by `NAT-3`, `WEB-1` and `OTH-2`.

Checked: 2026-10-06   Checked by: the maintainer, with Claude (vendor docs, caniuse and MDN browser-compat-data read on
2026-10-06; browserslist 4.29.3 as the policy pins it)
Declared targets (README, Targets): Windows 10 22H2 and 11, x64 and ARM64; Linux = GNOME 50 (GTK 4.22 + libadwaita
1.9, portals, D-Bus), as the Flatpak's `org.gnome.Platform` 50 runtime and Ubuntu 26.04 LTS; Android 10+ (API 29),
arm64-v8a; the web client in the browsers below (Safari 17+ is the iOS path); the server on Linux with systemd ≥ 256
user services, built with Nim 2.2.12.
Sources: one or more per row, with an evidence marker: **[V]** ran on the target (this Ubuntu 26.04 laptop, the
Windows 10 22H2 and 11 VMs, the Android emulator, the Note 9 or the Honor 600; the decision record says which);
**[D]** read in the vendor's docs, caniuse or MDN browser-compat-data (2026-09-30 or later; the caniuse and MDN data
for every web row were re-read on 2026-10-06 against Safari 17.0, Chrome 153, Firefox ESR 153); **[K]** a
long-standing vendor API, linked but not re-read for this matrix. This replaces docs/m6/CAPABILITIES.md
(2026-09-30), which stays as the record M6's design started from.

Resolved browser list (web only): the output of `browserslist` (4.29.3) for `.browserslistrc` on 2026-10-05, re-run on 2026-10-06 with the same output; CI compares it with the current output in both directions (WEB-1).

```
and_chr 154
chrome 154
chrome 153
edge 154
edge 153
firefox 157
firefox 156
firefox 153
ios_saf 27.0
ios_saf 26.6
ios_saf 26.5
ios_saf 26.4
ios_saf 26.3
ios_saf 26.2
ios_saf 26.1
ios_saf 26.0
ios_saf 18.5-18.7
ios_saf 18.4
ios_saf 18.3
ios_saf 18.2
ios_saf 18.1
ios_saf 18.0
ios_saf 17.6-17.7
ios_saf 17.5
ios_saf 17.4
ios_saf 17.3
ios_saf 17.2
ios_saf 17.1
ios_saf 17.0
safari 27
safari 26.6
safari 26.5
safari 26.4
safari 26.3
safari 26.2
safari 26.1
safari 26.0
safari 18.5-18.7
safari 18.4
safari 18.3
safari 18.2
safari 18.1
safari 18.0
safari 17.6
safari 17.5
safari 17.4
safari 17.3
safari 17.2
safari 17.1
safari 17.0
```

The first version was written before M6's architecture was chosen (docs/m6/CAPABILITIES.md, 2026-09-30); this one
adds what the decision records since then found. Rebuild it, with a new date, when a target is added or changed (a
browser in the resolved list, an OS, an OS version range, a runtime version), or when a feature needs a capability
that is not yet a row.

## Matrix

One row per requirement (IDs from docs/m6/REQUIREMENTS.md). Cells: `provided`, `optional` (present only with an
optional component, named), `partial`, `missing`, or `n/a` where the requirement doesn't run on that target (the
browsers sign in to the server rather than keeping the log; the importer runs only on the server's machine). The
web columns are engines: WebKit = Safari and iOS Safari 17+, Blink = Chrome, Edge and Chrome for Android (last two),
Gecko = Firefox (last two and ESR). Established (`NAT-1` test 4) is written for native and service facilities; web
features are covered by `WEB-3` instead.

### UI and accessibility

| Requirement | Facility | Windows 10/11 | GNOME/Linux | Android 10+ | WebKit (Safari 17+) | Blink (Chrome, Edge) | Gecko (Firefox) | Server (Linux) | Established | Source | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Native UI on every target (R1–R13, N7) | Windows: Win32 + common controls v6, Direct2D/DirectWrite; GNOME: GTK 4 + libadwaita; Android: Jetpack Compose (Google's AndroidX library, in the APK); web: HTML, CSS, DOM | provided | provided | provided | provided | provided | provided | n/a | yes: Win32 since Windows NT; GTK 4 since 2020, libadwaita 1.0 since 2021; Compose 1.0 since 2021, Google's recommended toolkit since | [K] [common controls](https://learn.microsoft.com/en-us/windows/win32/controls/common-controls-intro) · [V] [GTK 4](https://docs.gtk.org/gtk4/) 4.22 + [libadwaita](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1-latest/) 1.9 · [K] [Compose](https://developer.android.com/develop/ui/compose) | platform, no embedded web engine (0014, 0031, 0032, 0033) |
| Screen readers reach the drawing's tags and every control (N2) | Windows: UI Automation, a fragment provider for the drawing; GNOME: GtkAccessible → AT-SPI; Android: `AccessibilityNodeProvider`; web: native elements + WAI-ARIA | provided | provided | provided | provided | provided | provided | n/a | yes | [D] [UIA providers](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-providersoverview) · [D] [GTK accessibility](https://docs.gtk.org/gtk4/section-accessibility.html) · [D] [AccessibilityNodeProvider](https://developer.android.com/reference/android/view/accessibility/AccessibilityNodeProvider) · [K] [ARIA](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA) · [V] e2e through UIA, AT-SPI; TalkBack on the Honor | platform (0031, 0032 addendum 4, 0033) |
| Right-to-left and mixed text (Arabic notes and proposals) | Windows: DirectWrite; GNOME: Pango; Android: the framework's and Compose's text layout; web: Unicode bidi, `dir` | provided | provided | provided | provided | provided | provided | n/a | yes | [K] [DirectWrite](https://learn.microsoft.com/en-us/windows/win32/directwrite/direct-write-portal) · [K] [Pango](https://docs.gtk.org/Pango/) · [K] [Android RTL](https://developer.android.com/guide/topics/resources/localization) · [K] [`dir`](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/dir) · [V] an Arabic proposal approved on the emulator | platform |
| Course pages: rich text with links (R8) | Windows: RichEdit 4.1 (Msftedit.dll, `CFE_LINK`/`EN_LINK`); GNOME: GtkLabel with Pango markup; Android: Compose `AnnotatedString` + `LinkAnnotation`; web: DOM built with `textContent` | provided | provided | provided | provided | provided | provided | n/a | yes, except Compose `LinkAnnotation`: new (Compose UI 1.7, 2024, replacing `ClickableText`); risk: Compose's text API keeps moving, a rename costs a small edit | [D] [EN_LINK](https://learn.microsoft.com/windows/win32/controls/en-link) · [D] [Pango markup](https://docs.gtk.org/Pango/pango_markup.html) · [D] [LinkAnnotation](https://developer.android.com/reference/kotlin/androidx/compose/ui/text/LinkAnnotation) · [V] each app's `test_courses` | platform (0035, 0036) |
| Course faces from WOFF2 files (R8) | Windows: DirectWrite `IDWriteFactory5::UnpackFontFile` (10 1703+); GNOME: fontconfig `FcConfigAppFontAddFile`; Android: `Typeface` (TTF/OTF only); web: `@font-face` with WOFF2 | provided | provided | partial | provided | provided | provided | n/a | yes | [D] [UnpackFontFile](https://learn.microsoft.com/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefactory5-unpackfontfile) · [D] [FcConfigAppFontAddFile](https://www.freedesktop.org/software/fontconfig/fontconfig-devel/fcconfigappfontaddfile.html) · [D] [Android font resources](https://developer.android.com/guide/topics/resources/font-resource) · [D] [caniuse woff2](https://caniuse.com/woff2) · [V] Windows 10/11, GNOME | platform; Android: TTF copies (0036) |

### Drawings

| Requirement | Facility | Windows 10/11 | GNOME/Linux | Android 10+ | WebKit (Safari 17+) | Blink (Chrome, Edge) | Gecko (Firefox) | Server (Linux) | Established | Source | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sharp vector tiles of a sheet, drawn off the UI thread, at any zoom (R1) | Windows: Direct2D on worker threads; GNOME: Cairo image surfaces → `GdkTexture` through `GtkSnapshot` (GPU compositing); Android: `Canvas`/`Path` into bitmaps; web: Canvas 2D + `Path2D` on an `OffscreenCanvas` in a module Worker | provided | provided | provided | provided | provided | provided | n/a | yes | [K] [Direct2D](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-portal) · [D] [GtkSnapshot](https://docs.gtk.org/gtk4/class.Snapshot.html) · [K] [Canvas](https://developer.android.com/reference/android/graphics/Canvas) · [D] [caniuse offscreencanvas](https://caniuse.com/offscreencanvas), [path2d](https://caniuse.com/path2d), [MDN Worker `type: module`](https://developer.mozilla.org/en-US/docs/Web/API/Worker/Worker) (Safari 15, Firefox 114) · [V] measured in 0016; web in 3 engines (0034) | platform (0016, 0034) |
| Inflate the path store (zlib/deflate) | Windows: none (the Compression API has MSZIP, XPRESS and LZMS, not a zlib stream); GNOME: zlib (runtime); Android: the NDK's `libz`; web: `DecompressionStream('deflate')`; server: zlib (distribution) | missing | provided | provided | provided | provided | provided | provided | yes | [K] [Compression API](https://learn.microsoft.com/en-us/windows/win32/cmpapi/-compression-portal) · [D] [NDK stable APIs](https://developer.android.com/ndk/guides/stable_apis) · [D] [MDN DecompressionStream](https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream) (Safari 16.4, Chrome 80, Firefox 113) | platform; Windows: zlib linked (0029, 0033) |
| Decode JPEG XL: overview pyramid, photos, course pictures (R1, R8, R9) | Windows: the WIC JPEG XL codec (11 24H2+, a Store install); GNOME: libjxl in the GNOME runtime, glycin's loader; Android: none; web: `<img>` with `image/jxl` | missing (Windows 11 24H2+: optional, the Store codec) | provided | missing | partial | missing | missing | n/a | GNOME: libjxl [V] in runtime 50 (earlier runtimes not checked); the WIC codec: new (2025) and optional | [D] [caniuse jpegxl](https://caniuse.com/jpegxl): Safari 17.0 partial (still images only, no progressive decoding); Chrome 153–154 and Firefox 153–157 only behind a flag (on by default from Chrome 155 and Firefox 158); Edge none · [D] [WIC codec (ghacks)](https://www.ghacks.net/2025/03/03/windows-11-how-to-add-jpeg-xl-support-officially/) · [V] Flatpak build (manifest header) | dependency: libjxl 0.12 (0018); web: our WebAssembly build (0037) |
| Encode JPEG XL: photos, the overview pyramid (R9, R21) | Windows: the same WIC codec; GNOME: libjxl (runtime); Android: none; web: none (no JPEG XL canvas encoder); server: libjxl 0.11 (Ubuntu package) | missing (Windows 11 24H2+: optional, the Store codec) | provided | missing | missing | missing | missing | provided | as above; server: [V] Ubuntu 26.04's libjxl0.11 | [D] [caniuse jpegxl](https://caniuse.com/jpegxl) · [D] 0018 · [V] `dpkg-query` on the server | dependency: libjxl (0018); web: WebAssembly libjxl, effort 7 (0037) |
| Read the source PDF's geometry and render it (importer, R21) | server: Poppler + Cairo (distribution) | n/a | n/a | n/a | n/a | n/a | n/a | provided | yes | [V] (0026) | dependency instead: MuPDF 1.28.2 from pinned source, because the glyph library is trained on MuPDF's rendering (0026) |
| Read the tags: contour detection, glyph classification (R21) | none | n/a | n/a | n/a | n/a | n/a | n/a | missing | — | [D] 0026 | custom: the OpenCV operations used, ported to Nim and tested against OpenCV (0026) |

### Photos, camera and QR codes

| Requirement | Facility | Windows 10/11 | GNOME/Linux | Android 10+ | WebKit (Safari 17+) | Blink (Chrome, Edge) | Gecko (Firefox) | Server (Linux) | Established | Source | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pick a file: photos, bundles, join files (R9, R13) | Windows: `GetOpenFileNameW`; GNOME: `GtkFileDialog` → FileChooser portal; Android: Storage Access Framework (`OpenDocument`, `GetContent`); web: `<input type="file">` | provided | provided | provided | provided | provided | provided | n/a | yes (Windows: still supported, though Microsoft calls the Common Item Dialog its successor; GtkFileDialog since GTK 4.10, 2023) | [K] [GetOpenFileNameW](https://learn.microsoft.com/en-us/windows/win32/api/commdlg/nf-commdlg-getopenfilenamew) · [D] [GtkFileDialog](https://docs.gtk.org/gtk4/class.FileDialog.html) · [K] [SAF](https://developer.android.com/guide/topics/providers/document-provider) · [K] [MDN input file](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/input/file) | platform |
| Take a photo (R9) | Windows: CameraCaptureUI / Media Foundation; GNOME: Camera portal → PipeWire; Android: the camera app (`ACTION_IMAGE_CAPTURE`); web: `<input type="file" accept="image/*" capture>` | provided | provided | provided | partial | partial | partial | n/a | yes | [K] [CameraCaptureUI](https://learn.microsoft.com/en-us/windows/apps/develop/camera/cameracaptureui) · [D] [Camera portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Camera.html) · [K] [ACTION_IMAGE_CAPTURE](https://developer.android.com/reference/android/provider/MediaStore#ACTION_IMAGE_CAPTURE) · [D] [caniuse html-media-capture](https://caniuse.com/html-media-capture): iOS Safari 17 and Chrome for Android yes; desktop Safari, Chrome, Edge, Firefox no · [V] Android `test_photos` | Android: platform; Windows and GNOME apps add photos from a file (camera capture not built); web: a file picker where `capture` is ignored |
| Decode a picked photo (JPEG, PNG) for the editor | Windows: WIC; GNOME: `GdkTexture`; Android: `BitmapFactory`; web: `<img>`, `createImageBitmap` | provided | provided | provided | provided | provided | provided | n/a | yes | [K] [WIC](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec) · [K] [GdkTexture](https://docs.gtk.org/gdk4/class.Texture.html) · [K] [BitmapFactory](https://developer.android.com/reference/android/graphics/BitmapFactory) · [D] [caniuse createimagebitmap](https://caniuse.com/createimagebitmap) | platform |
| Touch or mouse in the photo editor (the touch-only loupe) | Windows: `WM_POINTER` (`PT_TOUCH`); GNOME: the gesture's `GdkInputSource`; Android: `MotionEvent` tool type; web: `PointerEvent.pointerType` | provided | provided | provided | provided | provided | provided | n/a | yes | [K] [WM_POINTERDOWN](https://learn.microsoft.com/en-us/windows/win32/inputmsg/wm-pointerdown) · [K] [GdkInputSource](https://docs.gtk.org/gdk4/enum.InputSource.html) · [K] [getToolType](https://developer.android.com/reference/android/view/MotionEvent#getToolType(int)) · [D] [MDN pointerType](https://developer.mozilla.org/en-US/docs/Web/API/PointerEvent/pointerType) (Safari 13) · [V] web 3 engines, emulator, Windows 11 VM | platform |
| Camera frames to scan an invite QR (R13) | Windows: Media Foundation Source Reader; GNOME: Camera portal → PipeWire → GStreamer `appsink` (`v4l2src` without a portal); Android: Camera2 + `ImageReader`; web: `getUserMedia` (secure contexts only) | optional (N editions need the Media Feature Pack) | provided | provided | provided | provided | provided | n/a | yes | [D] [Source Reader](https://learn.microsoft.com/windows/win32/medfound/source-reader), [Media Feature Pack](https://support.microsoft.com/windows/media-feature-pack-for-windows-10-11-n-september-2022) · [D] [Camera portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Camera.html) · [K] [Camera2](https://developer.android.com/reference/android/hardware/camera2/package-summary) · [D] [MDN getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia) · [V] webcams on GNOME and the Windows 11 VM, the Honor's camera | platform (0039, 0032 addendum 2) |
| Decode a QR code from the frames (R13) | Windows: the camera barcode scanner (WinRT, 10 1803+); GNOME, Android framework: none; web: `BarcodeDetector` | partial (a WinRT API; from our full-trust MSIX not verified) | missing | optional (ML Kit through Play services) | missing (behind a preference) | partial (Chrome for Android, macOS, ChromeOS only) | missing | n/a | the Windows scanner: yes (since 1803) | [D] [camera barcode scanner](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/pos/camerabarcode-system-requirements) · [D] [ML Kit](https://developers.google.com/ml-kit/vision/barcode-scanning/android) · [D] [MDN BarcodeDetector](https://developer.mozilla.org/en-US/docs/Web/API/BarcodeDetector) | dependency: zxing-cpp 3.1.1 (0019); web: `BarcodeDetector` first, else zxing-cpp in WebAssembly (0037) |
| Draw an invite QR code (R13) | none | missing | missing | missing | missing | missing | missing | n/a | — | [D] 0019 | dependency: zxing-cpp (0019, 0037) |

### Storage and security

| Requirement | Facility | Windows 10/11 | GNOME/Linux | Android 10+ | WebKit (Safari 17+) | Blink (Chrome, Edge) | Gecko (Firefox) | Server (Linux) | Established | Source | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Local database (R15) | Windows: `winsqlite3.dll` (its version and ABI are undocumented for desktop apps); GNOME: SQLite (runtime); Android: `android.database.sqlite` in Java only, no SQLite in the NDK; web: IndexedDB (session info, the outbox of unsent changes); server: SQLite (distribution) | partial | provided | partial | provided | provided | provided | provided | yes | [D] [SQLite on Windows](https://learn.microsoft.com/en-us/windows/apps/develop/data-access/sqlite-data-access) · [V] the NDK sysroot (0032) · [D] [caniuse indexeddb](https://caniuse.com/indexeddb) · [V] SQLite 3.46 on Ubuntu 26.04 | platform; Windows and Android: the SQLite amalgamation 3.53.4 compiled in (0032, 0033) |
| Signatures, key agreement and encryption: ECDSA/ECDH P-256, AES-256-GCM, SHA-256, HKDF, a CSPRNG (R11, N1) | Windows: CNG (bcrypt, ncrypt); GNOME and server: GnuTLS/Nettle; Android: the JCA (AndroidKeyStore, Conscrypt) | provided | provided | provided | n/a | n/a | n/a | provided | yes | [D] [CNG algorithms](https://learn.microsoft.com/en-us/windows/win32/seccng/cng-algorithm-identifiers) · [K] [GnuTLS](https://www.gnutls.org/manual/) · [D] [KeyProperties](https://developer.android.com/reference/android/security/keystore/KeyProperties) · [V] the vectors on every native target | platform (0017, 0029); our own P-256 point check on CNG (0033) |
| Key store for the device key and the storage key (N1, N1a) | Windows: NCrypt Software KSP + DPAPI (per user); GNOME: Secret Service through libsecret (the Secret portal in Flatpak); Android: AndroidKeyStore (non-exportable, hardware-backed where available); web: non-extractable `CryptoKey` in IndexedDB; server: `systemd-creds --user` (TPM2 where present) + `LoadCredentialEncrypted` | provided | provided | provided | provided | provided | provided | provided | yes, except `systemd-creds --user`: new (systemd 256, 2024); risk: a server on an older systemd (Ubuntu 24.04 has 255 [K]) needs a system unit instead | [D] [Software KSP](https://learn.microsoft.com/en-us/windows/win32/seccertenroll/cng-key-storage-providers) · [D] [DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata) · [K] [libsecret](https://gnome.pages.gitlab.gnome.org/libsecret/) · [D] [Secret portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html) · [K] [Android Keystore](https://developer.android.com/privacy-and-security/keystore) · [K] [MDN CryptoKey](https://developer.mozilla.org/en-US/docs/Web/API/CryptoKey) · [D] [systemd-creds](https://man7.org/linux/man-pages/man1/systemd-creds.1.html) ("Added in version 256"); [V] systemd 259 here | platform (0020, 0030–0033); web: not used, see "Provided but not built" |
| Disk encryption guaranteed by the platform (N1a) | Windows: BitLocker device encryption (qualifying hardware only); GNOME and server: LUKS (chosen at install); Android: file-based encryption (required for devices launching with Android 10+); WebKit: iOS data protection (macOS: FileVault, optional); Blink, Gecko: the OS's | missing | missing | provided | partial | optional (the OS's disk encryption) | optional (the OS's disk encryption) | missing | yes | [D] [BitLocker](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/) · [D] [file-based encryption](https://source.android.com/docs/security/features/encryption/file-based) · [K] [Apple data protection](https://support.apple.com/guide/security/data-protection-overview-secf6276da8a/web) | custom: AES-256-GCM sealed rows and files with a per-device storage key (0020) |
| Password hashing on the server: Argon2id (R10, R19) | server: OpenSSL libcrypto ≥ 3.2, `EVP_KDF` "ARGON2ID" | n/a | n/a | n/a | n/a | n/a | n/a | provided | new: OpenSSL 3.2 (2023); Ubuntu 24.04 LTS ships 3.0 [K]; risk: the server needs Ubuntu 26.04 or another distribution with OpenSSL ≥ 3.2 | [D] [EVP_KDF-ARGON2](https://docs.openssl.org/3.2/man7/EVP_KDF-ARGON2/) · [V] OpenSSL 3.5.5 | platform (0023) |
| Passphrase key for the root key backup: PBKDF2-HMAC-SHA256 (R14) | Windows: `BCryptDeriveKeyPBKDF2`; GNOME and server: GnuTLS; Android: `PBKDF2WithHmacSHA256` | provided | provided | provided | n/a | n/a | n/a | provided | yes | [K] [BCryptDeriveKeyPBKDF2](https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptderivekeypbkdf2) · [K] [SecretKeyFactory](https://developer.android.com/reference/javax/crypto/SecretKeyFactory) | platform (0023) |
| Crash and failure records for the manager's diagnostics reports (0040) | Windows: Windows Error Reporting (reports go to Microsoft, not to the plant); GNOME: none for apps; Android: `Thread.setDefaultUncaughtExceptionHandler`; server: the systemd journal | missing | missing | provided | n/a | n/a | n/a | provided | yes | [K] [WER](https://learn.microsoft.com/en-us/windows/win32/wer/windows-error-reporting) · [D] [UncaughtExceptionHandler](https://developer.android.com/reference/java/lang/Thread.UncaughtExceptionHandler) · [K] [journald](https://www.freedesktop.org/software/systemd/man/latest/systemd-journald.service.html) | custom on desktops: guards at callback boundaries, `crash.txt`; reports sealed to the manager in the log (0040) |

### Network and sync

| Requirement | Facility | Windows 10/11 | GNOME/Linux | Android 10+ | WebKit (Safari 17+) | Blink (Chrome, Edge) | Gecko (Firefox) | Server (Linux) | Established | Source | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TCP and UDP sockets, listening (R15–R17) | Windows: Winsock (the MSIX declares `privateNetworkClientServer`; unpackaged, the firewall asks on first listen); GNOME and server: POSIX sockets; Android: `java.net` sockets; web: none | provided | provided | provided | missing | missing | missing | provided | yes | [K] [Winsock](https://learn.microsoft.com/en-us/windows/win32/winsock/windows-sockets-start-page-2) · [K] [capability declarations](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations) · [V] every e2e suite | platform; browsers talk HTTP to the server only (R19) |
| Sync channel: TLS 1.3, mutual authentication, the peer ID pinned (R11, R15; PROTOCOL-v2) | Windows: Schannel through SSPI (`SCH_CRED_MANUAL_CRED_VALIDATION`); GNOME and server: GnuTLS with our own transport functions; Android: Conscrypt `SSLEngine` | partial (TLS 1.2 on Windows 10; 1.3 from Windows 11) | provided | provided | n/a | n/a | n/a | provided | yes | [D] [Schannel protocols](https://learn.microsoft.com/en-us/windows/win32/secauthn/protocols-in-tls-ssl--schannel-ssp-) · [D] [GnuTLS transport](https://gnutls.org/manual/html_node/Setting-up-the-transport-layer.html) · [K] [SSLEngine](https://developer.android.com/reference/javax/net/ssl/SSLEngine) · [V] 1.2 on Windows 10, 1.3 on 11 (0033) | platform (0017); Windows 10: TLS 1.2 (ECDHE-ECDSA-AES-GCM) only where 1.3 is missing |
| TLS with web trust (CA chain + host name) to the relay (R17) | Windows: Schannel `SCH_CRED_AUTO_CRED_VALIDATION`; GNOME and server: GnuTLS system trust + host check; Android: `SSLSocketFactory` + endpoint identification `HTTPS` | provided | provided | provided | n/a | n/a | n/a | provided | yes | [D] [SCH_CREDENTIALS](https://learn.microsoft.com/windows/win32/api/schannel/ns-schannel-sch_credentials) · [D] [GnuTLS verification](https://www.gnutls.org/manual/html_node/Certificate-verification.html) · [D] [SSLParameters](https://developer.android.com/reference/javax/net/ssl/SSLParameters) · [V] badssl.com refusals (0038) | platform (0038) |
| WebSocket client to the relay (R17) | Windows: WinHTTP WebSockets (on its own threads and callbacks); GNOME: libsoup 3 (not on our event loop); Android: none in the SDK; server: libsoup if installed | provided | provided | missing | n/a | n/a | n/a | optional (libsoup 3, a distribution package) | yes | [K] [WinHTTP WebSocket](https://learn.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpwebsocketcompleteupgrade) · [K] [libsoup](https://libsoup.gnome.org/libsoup-3.0/) · [D] 0038 | custom: a 200-line RFC 6455 client on each side (`kksl/ws.nim`, Kotlin `WsClient`), because neither platform client runs on our single-threaded loop (0038, 0013) |
| Direct path across NATs: STUN, hole punching, a reliable stream over UDP (R17) | QUIC would be the platform candidate: Windows: none for apps (`msquic.sys` is kernel-only); Linux: OpenSSL 3.5's QUIC, not in GLib; Android: none (Cronet needs Play services) | missing | partial (OpenSSL QUIC) | missing | n/a | n/a | n/a | partial (OpenSSL QUIC) | — | [D] [MsQuic FAQ](https://github.com/microsoft/msquic/blob/main/docs/FAQ.md) · [D] [OpenSSL QUIC](https://github.com/openssl/openssl/blob/master/README-QUIC.md) · [V] field test (0028) | custom: STUN, punching and our reliable UDP (`core/src/kks/rudp.nim`) under the platform's TLS; the relay pipe when punching fails (0028) |
| Find the plant's devices on the Wi-Fi: DNS-SD (R16) | Windows: `DnsServiceRegister`/`DnsServiceBrowse` (Windows 10+); GNOME and server: Avahi over D-Bus; Android: `NsdManager`; web: none | provided | optional (avahi-daemon; installed and running on Ubuntu 26.04) | provided | missing | missing | missing | optional (avahi-daemon) | yes | [D] [DnsServiceBrowse](https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse) (re-read 2026-10-06: "Windows 10 [desktop apps only]") · [D] [Avahi D-Bus API](https://github.com/avahi/avahi/tree/master/avahi-daemon) · [K] [NsdManager](https://developer.android.com/reference/android/net/nsd/NsdManager) · [V] Avahi 0.8 | platform (0002, 0030); without it: join and sync by address |
| HTTP server for the browser client (R19) | server: Nim's `std/asynchttpserver` (the language's standard library) | n/a | n/a | n/a | n/a | n/a | n/a | provided | yes | [D] [asynchttpserver](https://nim-lang.org/docs/asynchttpserver.html) | platform: the runtime's standard library (`OTH-0`; 0030) |
| A secure context for the pages: service worker, camera, async clipboard (R19, R13) | web: the features are restricted to secure contexts (HTTPS or localhost); server: HTTP/1.1 without TLS; HTTPS only through the remote-access tunnel (wiki: Remote access) | n/a | n/a | n/a | provided | provided | provided | partial (no TLS on the LAN) | yes | [D] [MDN: features restricted to secure contexts](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts/features_restricted_to_secure_contexts) (re-read 2026-10-06) · [D] 0030 | the engine cells say what the browsers provide in a secure context; the server cell carries the deployment's limit: over plain HTTP on the LAN these features are absent (fallback in Gaps) |
| Work offline for a while in the browser (R19) | web: service worker + Cache Storage (app shell, plant data), IndexedDB (outbox) | n/a | n/a | n/a | provided | provided | provided | n/a | — | [D] [caniuse serviceworkers](https://caniuse.com/serviceworkers) (Firefox: none in private browsing) · [D] [caniuse indexeddb](https://caniuse.com/indexeddb) | platform; detected (`'serviceWorker' in navigator`) |
| Sync in the background (R18) | Windows: the per-user `Run` key, Task Scheduler, a notification-area icon; GNOME: the Background portal (`RequestBackground`, autostart); Android: WorkManager; Blink: Background Sync (one-off, while the browser runs); WebKit, Gecko: none; server: a systemd user service with linger | provided | provided | partial (OEM power managers: MagicOS's iAware blocks the jobs) | missing | partial (Background Sync; Periodic Sync only for installed apps) | missing | provided | yes | [D] [Run keys](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys) · [D] [Background portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Background.html) · [K] [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent) · [D] [MDN SyncManager](https://developer.mozilla.org/en-US/docs/Web/API/SyncManager) (Safari, Firefox: no) · [V] the Honor 600, 4 hours (docs/m6/MEASUREMENTS.md) · [K] [loginctl enable-linger](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html) | platform (0021); see Gaps and "Provided but not built" |
| CLI commands reach the running server (0045) | server: `AF_UNIX` stream socket, mode 0600; Nim `asyncnet.bindUnix` | n/a | n/a | n/a | n/a | n/a | n/a | provided | yes | [D] [unix(7)](https://man7.org/linux/man-pages/man7/unix.7.html) · [D] [asyncnet](https://nim-lang.org/docs/asyncnet.html) | platform (0045) |

### Distribution and builds

| Requirement | Facility | Windows 10/11 | GNOME/Linux | Android 10+ | WebKit (Safari 17+) | Blink (Chrome, Edge) | Gecko (Firefox) | Server (Linux) | Established | Source | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Install per user, without administrator rights (R23) | Windows: MSIX through App Installer; GNOME: Flatpak (per user); Android: an APK the person allows; web: nothing to install; server: a systemd user unit under `~/kks-server` | partial (a self-signed MSIX needs its certificate in TrustedPeople once: an admin or IT policy) | provided | provided | provided | provided | provided | provided | yes (MSIX since Windows 10 1709) | [D] [MSIX signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview) · [D] [Flatpak](https://docs.flatpak.org/en/latest/) · [V] the e2e suites against the installed MSIX (10, 11) and Flatpak | platform (0022, 0043) |
| Updates (R24) | Windows: App Installer auto-update; GNOME: Flatpak remotes (Flathub); Android: `PackageInstaller` (no automatic updates outside a store; the person confirms); web: the server serves the current pages; server: none | provided | provided | partial | provided | provided | provided | missing | yes | [D] [App Installer auto-update](https://learn.microsoft.com/en-us/windows/msix/app-installer/auto-update-and-repair--overview) · [D] [Flathub requirements](https://docs.flathub.org/docs/for-app-authors/requirements) · [D] [PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller) | Android: our check of the signed manifest (0044); server: `deploy/install-server-user.sh`; Windows and Linux: see "Provided but not built" |
| Code signing (R24) | Windows: Authenticode on the MSIX; GNOME: Flathub signs its repository (a `.flatpak` bundle is not signed); Android: the APK signature schemes | partial (no publicly trusted certificate: `CN=Walkdown` is self-signed) | partial (bundles unsigned until Flathub) | provided | n/a | n/a | n/a | n/a | yes | [D] [MSIX signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview) · [D] [Flatpak repositories](https://docs.flatpak.org/en/latest/hosting-a-repository.html) · [K] [APK signing](https://source.android.com/docs/security/features/apksigning) | fallback: the release manifest, signed with ECDSA P-256 (`release.json.p256`), lists every file's hash (0044, 0048) |
| Native toolchain for x64 and ARM64 (0033, 0046, 0047) | Windows: MSVC Build Tools (Windows-only); GNOME: the GNOME SDK (x86_64, aarch64); Android: the NDK's clang (arm64-v8a); server: the distribution's GCC | provided | provided | provided | n/a | n/a | n/a | provided | yes | [K] [Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) · [D] [Flatpak runtimes](https://docs.flatpak.org/en/latest/available-runtimes.html) · [D] [Android ABIs](https://developer.android.com/ndk/guides/abis) | Windows: cross-built on Linux with mingw-w64 (x64) and llvm-mingw (ARM64), build tools only (0033, 0047); Android: arm64-v8a only (0046) |

## Gaps

For every cell that is not `provided` (n/a cells excluded).

| Requirement | Target | Gap | Decision | Fallback or dependency |
| --- | --- | --- | --- | --- |
| Course faces | Android | `Typeface` reads TTF/OTF, not WOFF2 | custom data | the same faces as TTF (`vendor/fonts/ttf`, SHA-256 listed, OFL; [0036](decisions/0036-native-course-renderers.md), [0011](decisions/0011-vendored-fonts.md)) |
| Inflate the path store | Windows | no zlib stream in the platform | dependency | zlib built by `platform/windows/build-deps.sh` from pinned, SHA-256-checked source and linked statically ([0029](decisions/0029-nim-core-building-blocks.md), [0033](decisions/0033-windows-platform-layer.md)) |
| Decode JPEG XL | Windows | none on Windows 10; on 11 24H2+ an optional Store codec | dependency | libjxl 0.12 linked ([0018](decisions/0018-jpeg-xl-per-platform.md), [0033](decisions/0033-windows-platform-layer.md)) |
| Decode JPEG XL | Android | none at any version | dependency | libjxl through the NDK ([0018](decisions/0018-jpeg-xl-per-platform.md), [0032](decisions/0032-android-platform-layer.md)); level 0 drawn in pieces of at most 2048 px |
| Decode JPEG XL | WebKit | partial: still images only, no progressive decoding | graceful | Walkdown's JPEG XL files are still images, decoded natively; the pages probe a 1×1 JXL (`K.jxl.native` in common.js) and use the WebAssembly decoder only when that fails |
| Decode JPEG XL | Blink, Gecko | not in Chrome 153–154 or Firefox 153–157 (flag only), none in Edge | dependency (our own build) | the same probe fails → libjxl compiled to WebAssembly by us (`vendor/kks`, SIMD or scalar by `WebAssembly.validate`; [0037](decisions/0037-wasm-libjxl-zxing.md)). Revisit when Chrome 155+ and Firefox 158+ are the oldest declared versions |
| Encode JPEG XL | Windows, Android | no encoder | dependency | libjxl, distance 1.9, effort 9 ([0018](decisions/0018-jpeg-xl-per-platform.md)) |
| Encode JPEG XL | WebKit, Blink, Gecko | no JPEG XL encoder in any engine | dependency (our own build) | photos encoded in the browser with the WebAssembly libjxl in a module Worker, effort 7; the server refuses anything but JPEG XL ([0037](decisions/0037-wasm-libjxl-zxing.md)) |
| Read the tags | Server | no contour detection or classification in any platform | custom | the 12 OpenCV operations used, ported to Nim and checked pixel for pixel against OpenCV ([0026](decisions/0026-importer-and-server.md)) |
| Take a photo | WebKit (macOS), Blink (desktop), Gecko | `capture` is ignored on desktop browsers | graceful | the same `<input type="file">` opens a file picker: a photo taken elsewhere is picked instead |
| Camera frames | Windows | N editions have no Media Foundation without the Media Feature Pack | graceful | the scan window says what to install; pasting the invite text always works ([0039](decisions/0039-webcam-qr.md)) |
| Decode a QR code | Windows | partial: a WinRT scanner whose use from our full-trust MSIX is not verified | dependency | zxing-cpp 3.1.1, pinned and SHA-256-checked ([0019](decisions/0019-qr-codes.md)) |
| Decode a QR code | GNOME, WebKit, Gecko | none (Safari: behind a preference) | dependency | zxing-cpp: native on GNOME ([0039](decisions/0039-webcam-qr.md)), WebAssembly in browsers ([0037](decisions/0037-wasm-libjxl-zxing.md)) |
| Decode a QR code | Android | only ML Kit through Play services, which is optional | dependency | zxing-cpp through the NDK on Camera2 frames ([0019](decisions/0019-qr-codes.md), [0032](decisions/0032-android-platform-layer.md)) |
| Decode a QR code | Blink | `BarcodeDetector` only on Android, macOS and ChromeOS | feature detection + dependency | `BarcodeDetector` when it lists `qr_code` (common.js), else zxing-cpp in WebAssembly ([0037](decisions/0037-wasm-libjxl-zxing.md)) |
| Draw an invite QR code | all six clients | no QR encoder anywhere | dependency | zxing-cpp's writer, native and WebAssembly ([0019](decisions/0019-qr-codes.md), [0037](decisions/0037-wasm-libjxl-zxing.md)) |
| Local database | Windows, Android | Windows: `winsqlite3.dll`'s ABI undocumented for desktop apps; Android: no SQLite in the NDK | dependency | the SQLite amalgamation 3.53.4, pinned by SHA3-256, compiled in; `dbstore.nim` unchanged ([0032](decisions/0032-android-platform-layer.md), [0033](decisions/0033-windows-platform-layer.md)) |
| Disk encryption | Windows, GNOME, Server | not guaranteed (BitLocker on qualifying hardware, LUKS chosen at install) | custom | entry bodies, photos and plant-data files sealed with AES-256-GCM under a per-device storage key held by DPAPI, libsecret or `systemd-creds`; IDs and sequence numbers stay clear for sync ([0020](decisions/0020-encryption-at-rest.md)) |
| Disk encryption | WebKit (macOS), Blink, Gecko | depends on the OS | none yet | the browser keeps session info, the outbox and cached plant data protected only by the OS; 0020's wrapped WebCrypto key is not built (see below) |
| Crash records | Windows, GNOME | no crash hook that reports to the plant | custom | the apps catch exceptions at every callback boundary (GLib trampolines, window procedures), write `crash.txt`, and send it in the next sealed diagnostics report ([0040](decisions/0040-diagnostics-reports.md)) |
| Sockets | WebKit, Blink, Gecko | no listening or raw sockets in browsers | by design | browsers are clients of the server over HTTP (R19); they don't sync peer to peer |
| Sync channel TLS 1.3 | Windows | Windows 10's Schannel has TLS 1.2 only | fallback | TLS 1.2 with ECDHE-ECDSA-AES-GCM, allowed only where 1.3 is missing (PROTOCOL-v2; [0017](decisions/0017-crypto-primitives-and-transport.md), [0033](decisions/0033-windows-platform-layer.md)) |
| WebSocket client | Android, Server | Android: none in the SDK; server: libsoup only if installed | custom | RFC 6455 client, about 200 lines each (`platform/linux/src/kksl/ws.nim`, Kotlin `WsClient`; [0038](decisions/0038-v2-relay-pipe.md), [0013](decisions/0013-own-implementations.md)) |
| Direct path across NATs | Windows, Android (missing); GNOME, Server (partial) | no QUIC API for apps on Windows and Android; OpenSSL QUIC would bring its own TLS and lose the key-store device keys | custom | STUN, hole punching and our reliable UDP, wire-compatible with v1, tested under loss; a failed or silent punch falls back to the relay pipe for an hour ([0028](decisions/0028-internet-transport-rudp-or-quic.md)) |
| Discovery on the Wi-Fi | GNOME, Server | needs avahi-daemon (optional component) | graceful | join and sync by address (R16 "also by address"); invites carry addresses |
| Discovery on the Wi-Fi | WebKit, Blink, Gecko | no DNS-SD in browsers | by design | the person opens the server's address |
| Secure context for the pages: service worker, camera | Server | plain HTTP on the plant LAN; HTTPS only through the remote-access tunnel | graceful fallback | over plain HTTP the pages work online only: the service worker is skipped (`'serviceWorker' in navigator`, common.js) and the camera scan is offered only when `navigator.mediaDevices?.getUserMedia` exists (`K.canScan`), else the invite text is pasted |
| Secure context for the pages: async clipboard | Server | plain HTTP on the plant LAN | **none yet: open** | admin.html's Copy button (diagnostics codes) calls `navigator.clipboard.writeText` without a detection branch, so over plain HTTP it throws and nothing is copied (localhost and the HTTPS tunnel work). Needs a code change outside this document (`WEB-4`): detect `navigator.clipboard` and otherwise select the code for a manual copy |
| Sync in the background | Android | OEM power managers (MagicOS iAware) block WorkManager's jobs whatever the app does within Android's rules | graceful | `Sync.backgroundLimit` shows a notice in Manage → Account with a button to the app's system settings and records a diagnostics event; a foreground service or push was rejected (CLAUDE.md, 2026-10-03) |
| Sync in the background | WebKit, Gecko (missing); Blink (partial) | no background sync, or Blink-only | graceful | browsers sync while the page is open and show the last successful sync ([0021](decisions/0021-background-sync.md)) |
| Install without admin | Windows | a self-signed MSIX needs its certificate trusted once | fallback | IT trusts `CN=Walkdown` once (TrustedPeople, by policy); else the single exe in a zip ([0022](decisions/0022-distribution-and-updates.md), [0043](decisions/0043-msix-packaging.md)) |
| Updates | Android | no automatic sideload updates | custom | a daily check of `release.json` against its pinned P-256 signature, then `PackageInstaller` with the person's confirmation ([0044](decisions/0044-walkdown-android-updates.md)) |
| Updates | Server | no update mechanism for a user service | custom | the maintainer runs `deploy/install-server-user.sh` (a new versioned folder, `current`/`previous` links for rollback) |
| Code signing | Windows, GNOME | self-signed certificate; unsigned Flatpak bundles | fallback | the signed release manifest lists every file's SHA-256; Flathub signing once published ([0022](decisions/0022-distribution-and-updates.md), [0047](decisions/0047-arm64-desktop-builds.md)) |

Dependency records: the `docs/dependencies/` records (#13) will replace the decision links above for libjxl, zxing-cpp,
SQLite, zlib, MuPDF, emsdk, mingw-w64 and llvm-mingw once they merge.

**Provided but not built yet** (the platform has it; the app doesn't use it):
- background running on Windows (the `Run` key, a notification-area icon) and GNOME (the Background portal): the
  desktop apps sync while they are open ([0021](decisions/0021-background-sync.md));
- App Installer auto-update for the MSIX and publishing on Flathub: desktop updates are a manual install of the next
  package ([0022](decisions/0022-distribution-and-updates.md));
- the browser's storage key (a non-extractable WebCrypto key wrapping the cached data;
  [0020](decisions/0020-encryption-at-rest.md));
- taking photos with the camera in the Windows and GNOME apps (photos come from files there);
- Blink's Background Sync (not used: it covers one engine).

## Resulting architecture

Every target provides a native UI toolkit with an accessibility API, P-256 crypto, TLS, a key store and (except
browsers) sockets and discovery; none provides the log, sync or KKS logic, and several lack JPEG XL, QR codes,
SQLite (Windows, Android) and a WebSocket client. So the business logic is one sans-I/O Nim core (`core/`) under a
thin native adapter per platform (Win32 + Direct2D, GTK 4 + libadwaita, Compose through JNI) that uses the platform's
crypto, TLS and key store (P-256, because Ed25519 is missing from CNG and from Android below API 33), plus a few
pinned, SHA-256-checked libraries for the gaps (libjxl, zxing-cpp, SQLite, zlib; built to WebAssembly by us for the
browsers). Browsers can't listen, discover or sync in the background, so the web client is a thin client of an
always-on Linux server (a systemd user service on GnuTLS, OpenSSL's Argon2id and SQLite), and devices that can't
punch through a NAT sync through the relay pipe.
