# M7: KKS Explorer on iOS through Python/shell apps (research, 2026-09-30)

Question (docs/ARCHITECTURE.md M7): can an iPhone/iPad run KKS Explorer inside Pythonista 3, Pyto, iSH or a-Shell, and
is that usable, or is a native app needed? Nothing here was run on an iPhone or iPad (none available; no iOS simulator
on Linux). Everything is from the apps' own documentation and store pages, plus measurements on a desktop. Claims
marked *unverified* need a real device.

## Answer

**No as a peer, yes as a browser client.**
- None of the four apps can make an iPhone a real peer like the Android app (joined device, automatic sync in the
  background, found on the Wi-Fi). iOS stops them in the background, blocks mDNS for them, and three of the four lack
  the crypto library.
- An iPhone can already use KKS Explorer, with no iOS work, as a **browser client of the server**: Safari, added to
  the Home Screen, logging in with an account (server mode). That needs the server reachable over HTTPS (the remote
  access plan, docs/REMOTE_ACCESS.md). *Unverified on an iPhone.*

## What the app needs

- Python: the code is statically compatible with 3.8+ (vermin 3.8; no PEP 701 f-strings found). CI runs 3.12. It has
  not been run on 3.10, the version Pythonista and Pyto ship.
- `cryptography`: Ed25519 (signed log), X25519 + ChaCha20-Poly1305 (Noise sync, private entries). Required.
- `hashlib.scrypt` (passwords, root key backup), sqlite3, threads, TCP + UDP sockets (sync, rudp, STUN), TLS (relay).
- Optional: `zeroconf` (mDNS discovery), Pillow + pillow-jxl (photo encoding; without them photos stay as uploaded).
- A browser showing `http://127.0.0.1:<port>`: IndexedDB, fetch, a camera for QR and photos. The Python process must
  keep running while the page is used.

## The four apps

| | Pythonista 3 | Pyto | iSH | a-Shell |
|---|---|---|---|---|
| Python | 3.10 | 3.10 | Alpine's python3 (x86, emulated) | 3.11+, native |
| `cryptography` | **no** (open request since 2016) | **yes**, Full version only (also PyNaCl) | yes (`apk add py3-cryptography`) | **no** (pip only installs pure-Python packages) |
| Background | limited (old notes: up to 10 min) | `background` module (details not documented) | indefinite with the location trick (`cat /dev/location`) | none documented |
| UI | `ui.WebView` inside the app | no WebView documented in `pyto_ui` | Safari (works because iSH keeps running) | — |
| Speed | native | native | x86 emulated: reported very slow (`pip -V` ~7 min, 2019 issue) | native |
| Last App Store release | 3.4, 2023-04-27 ("Pythonista Lab" in TestFlight review since 2025-03) | 19.0.1, 2024-06-09 | maintained | maintained |
| Cost | $9.99 | Full version $14.99 | free | free |

Common to all four:
- **mDNS / multicast**: iOS 14+ requires Apple's restricted `com.apple.developer.networking.multicast` entitlement for
  custom multicast. None of these apps is documented to have it, so `zeroconf` discovery is out. Sync by address, QR
  invite or the internet relay would still work. *Unverified per app.*
- **Local Network permission**: iOS asks per app. Whether each host app declares it (needed to reach other devices on
  the Wi-Fi) is *unverified*.
- **No automatic sync when closed**: iOS suspends apps in the background. Except iSH with location tracking, the phone
  syncs only while the host app is open.
- **Distribution**: every teammate buys or installs the host app, copies the program folder into it and starts a
  script by hand. No updates through the app's self-update. The host apps change rarely (Pythonista 2023, Pyto 2024).

## Measurements (desktop, CPython 3.14, one core; a phone is slower)

Pure-Python crypto (needed in Pythonista), checked to give byte-identical signatures to `cryptography`:
- Ed25519 verify: **4.9 ms** (`cryptography`: 0.15 ms); sign 4.6 ms.
  - The engine verifies only entries arriving by sync, not its own DB, so 95 entries cost well under a second.
  - A first join of a large plant (20k entries) would take a few minutes on a phone.
- ChaCha20 (the stream half of ChaCha20-Poly1305; the Poly1305 half is not measured): **0.6 MB/s**. The ~18 MB of
  published drawings would take more than 30 s at this rate on a desktop, longer on a phone.

## Per app

- **Pythonista 3:** closest to usable without a Mac.
  - For: native speed, an in-app WebView keeps the UI in the foreground.
  - Against: it would need pure-Python Ed25519/X25519/ChaCha20-Poly1305 (feasible, measured above, slow for photos and
    drawings), and it has had no App Store update since 2023.
- **Pyto:** the only one shipping `cryptography`, so the app would run unchanged, in principle. How to show the UI is
  unclear: no documented WebView (UIKit bridge only), and Safari needs the script to stay alive in the background. Last
  updated 2024.
- **iSH:** the only one where Safari + a background server works (location trick), and `py3-cryptography` installs.
  But x86 emulation makes CPython very slow, and keeping location tracking on permanently is a hack Apple may change.
- **a-Shell:** not viable. No `cryptography`, pip limited to pure Python, no background execution documented.

## Recommendation

1. For iPhone users now: the browser client path.
   - Server mode already has login, offline lease, outbox and service worker.
   - Safari keeps IndexedDB/service-worker data for Home Screen web apps; in a normal tab, Safari clears it after
     7 days of use without visiting.
   - Safari 17+ decodes JPEG XL natively.
   - It needs the server reachable over HTTPS (Cloudflare Tunnel + Access, docs/REMOTE_ACCESS.md), which waits on the
     same IT approval.
2. If an iPhone must be a peer: a native app (Swift, or the Kotlin core via Kotlin Multiplatform). This needs a Mac and
   an Apple Developer account (paid yearly), and still meets the same background and multicast limits. Out of scope
   (ARCHITECTURE D7) unless the need is real.
3. If someone wants to try anyway with a device in hand: Pyto Full is the cheapest experiment (the app runs unchanged
   if its `cryptography` has Ed25519/X25519/ChaCha20-Poly1305). Test list:
   - `import cryptography` versions;
   - `python3 app.py` in peer mode;
   - join by QR against the laptop;
   - showing the page (Safari while Pyto is in the background, or a WebView via the UIKit bridge);
   - sync by address;
   - how long it survives in the background.

## Beyond Python (added 2026-09-30)

On iOS, code from someone other than Apple runs in only three ways:
1. **Inside a web engine:** Safari, or a WebView in some app.
2. **Inside an app installed by the user:** that is either our own app (native, or any framework compiled to one), or
   someone else's app that runs our code (Pythonista, Pyto, a JavaScript runner, iSH …). These "host apps" all have
   the limits above.
3. There is no third option for a phone that isn't jailbroken. Alternative app stores exist only in the EU.

What that leaves:
- **Browser client** (above): already works, needs the server over HTTPS.
- **Browser peer** (new idea, not built): the web page itself keeps its own signed log and syncs.
  - Storage: IndexedDB or SQLite-in-WebAssembly (OPFS, Safari 17+).
  - Crypto: WebCrypto (Ed25519 since Safari 17) plus a JavaScript library for X25519 and ChaCha20-Poly1305.
  - A third implementation of the protocol, checked against the frozen vectors like the Kotlin one.
  - A page can't accept connections or use mDNS. It would sync outward only, through the internet relay's WebSocket
    pipe (M5, already built), while the page is open, and only with internet access. No App Store, no Mac, same code
    on any phone.
- **Native app:** a Mac isn't strictly needed any more:
  - GitHub Actions has macOS runners (free minutes for public repos).
  - `xtool` builds and signs iOS apps on Linux (SwiftPM).
  - What can't be avoided is Apple's account: a free Apple ID installs only on your own phone, and the app expires
    after 7 days (max 3 apps). Giving it to others (TestFlight, App Store, ad hoc) needs the paid Developer Program
    (99 USD a year). Background and multicast limits apply as above (multicast needs Apple's approval).

## Sources

- Pythonista third-party modules (3.4): https://omz-software.com/pythonista/docs-3.4/py3/ios/third-party-modules.html
- Pythonista "What's New": https://omz-software.com/pythonista/docs-3.4/py3/ios/new.html
- Pythonista cryptography request: https://github.com/omz/Pythonista-Issues/issues/49
- Pythonista App Store: https://apps.apple.com/us/app/pythonista-3/id1085978097
- Pythonista Lab status: https://github.com/omz/Pythonista
- Pyto App Store (bundled modules, versions): https://apps.apple.com/us/app/pyto-ide/id1436650069
- Pyto third-party libraries: https://pyto.readthedocs.io/en/latest/third_party.html
- Pyto FAQ (background): https://pyto.readthedocs.io/en/latest/faq.html
- a-Shell README: https://github.com/holzschu/a-shell
- a-Shell cryptography issue: https://github.com/holzschu/a-shell/issues/132
- iSH running in background: https://github.com/ish-app/ish/wiki/Running-in-background
- iSH Python speed: https://github.com/ish-app/ish/issues/331
- Apple multicast entitlement: https://developer.apple.com/news/?id=0oi77447
- Safari storage / Home Screen web apps: https://www.magicbell.com/blog/pwa-ios-limitations-safari-support-complete-guide
- Safari 17 JPEG XL: https://www.jpegxl.io/tutorials/safari/
- WebKit Ed25519 in WebCrypto: https://github.com/WebKit/WebKit/pull/8691 and https://blogs.igalia.com/jfernandez/2025/02/28/can-i-use-secure-curves-in-the-web-platform/
- xtool (iOS apps on Linux): https://github.com/xtool-org/xtool
- Free Apple ID vs paid program: https://foresightmobile.com/blog/ios-app-distribution-guide-2026
