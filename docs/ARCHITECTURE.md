# KKS Explorer v2: server mode + peer-to-peer

Status: **design, agreed 2026-09-26. Nothing below is built yet** unless a milestone says so.
Supersedes `PLAN_B_P2P.md` (kept for its background and prior-art notes).

## 1. Decisions (2026-09-26)

| # | Decision | Why |
|---|---|---|
| D1 | Build both: server mode and P2P. The app works with or without a server. | Hosting is undecided; the team needs the app either way. |
| D2 | Data on personal devices is acceptable. | The company gave staff the P&IDs and KKS lists to keep; nearly everyone is BYOD. |
| D3 | **No host, no election.** Every device keeps a signed log of changes and syncs it with whichever peers it can reach. The same rules give the same result on every device. The server is an always-on peer, nothing more. | An elected host still splits into two hosts when the peers split into groups (client isolation, internet cuts), and then everything must be merged anyway. Merging by rule from the start removes the election, the handover and split-brain. |
| D4 | **Same Wi-Fi + file/QR sync first; internet P2P is a later phase.** | Internet P2P needs signaling and, for ~1 in 5 connections, a TURN relay: both servers. Decide how to host them once the rest works. |
| D5 | **Android: native Material 3 shell + the existing P&ID viewer in a WebView.** | One viewer to maintain (pan/zoom, sharp vectors, hotspots, marking). The native side does storage, sync, navigation, settings. |
| D6 | Windows/Linux: the current Python app, packaged so it opens by double-click (no terminal). It opens the browser, as now. | Reuses everything that exists. |
| D7 | iOS/macOS: out. | Building needs Apple hardware; iOS restricts background networking. |
| D8 | One person may use several devices at the same time (phone + laptop). | Each device has its own key and peer ID, separate from the person's identity. |
| D9 | Three areas: **P&ID**, **Learning** (3 HTML courses with MCQ and diagrams), **Account & settings**. | |

## 2. The shape of it

```
 every device runs a LOCAL PEER                        sync between peers (any of these, whichever works)
 ┌──────────────────────────────────────────┐         ─ same Wi-Fi: mDNS discovery + TCP (D4)
 │ UI (web: index.html / learning pages)     │         ─ file / QR bundle (USB, WhatsApp, email)
 │   ↕ the same /api/* as today               │         ─ the server, if one exists (it is just a peer)
 │ local API  →  state (SQLite, derived)      │         ─ later: internet (ICE: STUN/TURN + signaling)
 │                ↑ replay                    │
 │ signed log  ←→  sync engine  ←→ transports │
 │ blobs (photos, plant-data bundle, courses) │
 └──────────────────────────────────────────┘
```

- **The UI always talks to a local peer**, never directly to a remote machine. On a laptop the local peer is the
  packaged Python app; on Android it is the Kotlin core behind the WebView. The web UI keeps its current `/api/*`.
- **"Server mode" only changes which peers a device tries first** (the server's address) and lets people with no app
  use the server's web page as today. There is no switch in the data path, so "the server went down mid-session"
  needs no special handling: devices keep syncing with each other, and with the server when it's back.
- The manager setting "server mode on/off" is a signed log entry, so every device learns it the normal way.

## 3. Identity and roles

- **Device key:** every install generates an Ed25519 key pair. Private key never leaves the device (Android: stored
  encrypted under a Keystore key; desktop: a file readable only by the user). Peer ID = the public key itself
  (base64url), so any entry can be verified without a lookup (docs/PROTOCOL.md §2).
- **Person:** a signed *person record* `{person_id, username, full_name, position, role}` (full name and position are
  the fields added on 2026-09-26). Roles as today: one manager, admins, users.
- **Device certificate:** binds a device key to a person. Issued by an admin/manager when the person joins (scan a
  QR shown by the admin's device, or accept an invite file), or by one of the person's own devices when they add
  another (D8: phone shows a QR, laptop scans it). A person can list and remove their own devices.
- **Manager root key:** a plant root key is the root of trust, fixed in the plant-data bundle; it signs who the manager
  is and can certify/revoke any device (PROTOCOL.md §8). Day-to-day manager actions are signed by the manager's normal
  device keys, so the root key is only needed rarely. **Keep it on the laptop + the backup, not on the phone**
  (changed 2026-09-26 while writing M0b): between two devices of the same person only a root-signed revoke decides
  who is the thief, so a phone that carries the root key makes a stolen phone unrecoverable without shipping a new
  trust anchor. Handover = the root key signs a `manager` statement for the new manager, then a `rotate` to a root key
  the new manager generated.
  Nobody else holds a copy (decided 2026-09-26). **Recommended:** a self-held encrypted backup (passphrase-protected
  file or printed QR, kept by the manager alone): unlike the server version there is no `reset-manager` shell fallback
  in P2P, so losing every device that holds the key would freeze roles, drawing updates and revocations for good.
- **Revocation** is a signed entry: "device D is valid up to its log entry N". Entries after N are rejected
  everywhere; entries up to N stay valid. This can't be dodged by back-dating, unlike a timestamp cut-off. It takes
  effect on each device when that device receives it, so an offline device keeps trusting a revoked key until then.
- **Browsers with no app (server mode only):** the server holds a custodial key per such person and signs their
  entries for them after password login, as the current server does implicitly.

## 4. Data: the signed log

- Each device appends to **its own log**. Entry: `{peer, seq, prev, hlc, type, body, sig}`: `seq` counts up per device,
  `prev` = hash of the previous entry (gaps and tampering are detectable), `hlc` = hybrid logical clock (wall time +
  counter; never trust phone clocks alone), `sig` = Ed25519 over the canonical bytes. Entry ID = SHA-256 of them.
- **Canonical bytes:** JSON with sorted keys, no whitespace, UTF-8, **integers only** (floats serialize differently in
  Python and Kotlin; box coordinates are stored in tenths of a pixel). Written down in the spec with test vectors.
- **Entry types** map onto today's submissions and admin actions: `equipment`, `review`, `link`, `photo`,
  `photo_delete`, `tag_add`, `tag_remove`, plus `approve`/`reject` (referencing an entry ID), `person`, `device_cert`,
  `revoke`, `setting`, `course_progress` (§8).
- **State** (what the UI shows) = replay of all *approved* entries in one total order: by approval HLC, then peer ID.
  Every device holding the same entries computes the same state. SQLite on each device is a cache of that replay.
- **Approvals as today:** user entries are proposals; an admin/manager `approve` makes them count; admin/manager
  edits count on their own (like `admins_apply_directly`).
- **Conflicts:** today's 3-way field merge (`server/changes.py` `plan()`): edits to different fields both apply.
  Two approvals changing the same field: manager beats admin, otherwise the later one (in the total order) wins, and
  the overwritten value is listed under "Conflicts" on every device, where an admin can restore it. Because the order
  is deterministic, two groups that worked apart (a partition) agree as soon as they exchange entries.
- **History / revert / restore** stay: revert = a new entry setting the old value.
- **Blobs** (photos, plant-data bundle, course bundles) are stored by SHA-256 and fetched on demand; big ones only on Wi-Fi.
- **Photos: per-device choice** (decided 2026-09-26): "only when opened" (default on phones) or "all photos"
  (downloaded on Wi-Fi) — not built yet. **Stored as JPEG XL**, distance 1.9 / effort 9 (decided 2026-09-27 after
  measuring: d1.0 was no smaller than the old JPEG q85; d1.9 is the same quality at ~56 % of the size), long side
  1600 px from the pages, encoded by the device that takes/imports the photo (Android: bundled libjxl; laptops and
  servers: pillow-jxl-plugin; browsers upload a JPEG and the server converts). **Display without JPEG copies:**
  browsers without native JXL decode it with libjxl compiled to WebAssembly (vendor/jxl), the Android app hands its
  WebView the decoded pixels (BMP) from its own libjxl.
- **Private data** (course progress, §8) is encrypted with a key known only to that person's own devices, so the
  entries can travel through anyone (server, relays) but only that person can read them.
- **Plant data** (sheets, tags, procedures, locations, KKS tables) is a **bundle signed by the manager** with a version
  number; a device accepts a newer signed version only. Sheet imports (Manage → Drawings) produce a new bundle version.

## 5. Sync

- On connect: mutual authentication by device key (Noise protocol, or TLS with pinned keys; no certificate authority),
  check both devices' certificates and revocations **first**, then exchange a version vector `{peer: last seq}` and send
  the missing entries, then missing blobs (small first).
- **Relaying is built in:** device A carries B's entries to C (signatures prove who wrote them). That's how an edit made
  at HQ reaches the plant with no server: someone's laptop or a file carries it.
- **Presence** ("who's online / looking at this tag") is ephemeral gossip between connected devices, per device, not
  logged.

## 6. Transports

1. **Same Wi-Fi:** mDNS/DNS-SD service `_kks._tcp` (Android NSD; `zeroconf` on desktop), then TCP.
   **Test client isolation first** (§10): if the plant Wi-Fi blocks device-to-device traffic, this transport is dead there.
2. **File / QR bundle:** a signed batch of log entries (+ blobs). "Export changes since …" / "Import". Always works.
3. **The server** (server mode): the same sync protocol over HTTPS/WebSocket to a well-known address.
4. **Later (D4): internet P2P** via ICE (WebRTC data channels on Android; `aiortc` on desktop): STUN for public
   addresses, a signaling meeting point, TURN relay for symmetric NATs. Hosting choice deferred.
5. Optional, last: Wi-Fi Direct / Bluetooth phone-to-phone.

## 7. Platforms

- **Android (Kotlin):**
  - core: log, canonical encoding, signatures, replay, merge, sync, SQLite, blob store, NSD. Must pass the shared test
    vectors (§9).
  - local API: the same `/api/*` the web UI uses, served to the WebView through `WebViewAssetLoader`/request
    interception (no open port).
  - UI: Material 3, `NavigationSuiteScaffold` (bottom bar on phones, navigation rail on foldables/tablets, drawer on
    large screens by window size class); tabs **P&ID** (WebView viewer), **Learning**, **Account & settings**
    (account, devices, sync status, queue, submissions, feedback, about). Photos from the camera go through the
    native side.
  - Distribution: signed APK files (no Play Store needed); updates by the same route.
- **Windows/Linux (Python):** the current app becomes the local peer; packaged with PyInstaller (one file/folder per
  OS). Double-click → starts the local peer on localhost → opens the browser. `localhost` counts as a secure
  context, so the offline web app keeps working. **The "standard library only" rule ends for the packaged app:**
  it needs `cryptography` (Ed25519) and `zeroconf` (mDNS), bundled inside the package, nothing to install.
- **Server:** the same Python peer, run as a service (docs/REMOTE_ACCESS.md still applies).

## 8. Learning

The 3 courses (`source/courses/`: 1 Power Plant Technology, 2 Plant Foundations, 3 HRSG) are self-contained HTML
files (118–141 KB, one inline script each, SVG diagrams, MCQs with feedback). They keep progress in `localStorage`
under a per-course prefix (`ppt.`, `fnd.`, `hrsg.`) and load three Google Fonts; nothing else comes from outside.

- **Courses** (built 2026-09-27, M4): `tools/build_courses.py` copies them to `data/courses/` with the Google Fonts
  links replaced by vendored fonts (`vendor/fonts`: Atkinson Hyperlegible, Barlow Semi Condensed, JetBrains Mono,
  Latin + Latin Extended, SIL OFL) and one bridge script added; nothing else changes. They ship with the app like the
  plant data (not yet a signed, versioned bundle: that comes with the plant-data bundles).
- **Progress bridge** (`course-bridge.js`): before the course's own script it fills the course's `localStorage`
  keys from the local peer (synchronously: the course reads them at once) and mirrors every write back.
- **Scores are private** (decided 2026-09-26): progress is `private` entries encrypted with the person's secret
  (PROTOCOL.md §13); a person's own devices swap secrets (§17), so progress follows the person from phone to laptop.
  Admins, the manager and the plant server relay the entries but can't read them. On a plant server's web pages
  (browser, no app) progress stays in that browser's localStorage.

## 9. One protocol, two implementations

Python (desktop/server) and Kotlin (Android) implement the same log, encoding, signatures, ordering and merge rules.
They are held together by **`docs/PROTOCOL.md` + shared test vectors**: fixed inputs with expected canonical bytes,
signatures, entry IDs, orderings and replayed states. Both test suites run the same vectors. Without them, two
implementations of a sync protocol drift apart silently.

## 10. Before and during the build

- ~~Client isolation~~: **checked 2026-09-26, devices reach each other on the plant Wi-Fi** (phones of the manager and
  workmates opened the server running on the manager's laptop). Same-Wi-Fi sync is viable at the plant.
- ~~Manager key backup~~: nobody else holds a copy; self-held encrypted backup recommended (§3).
- ~~Photos on phones~~: both options, per device; stored as JPEG XL (§4).
- ~~Scores visibility~~: private to the person (§8).

## 11. Build order (each milestone usable on its own)

| M | What | Rough effort* | Result |
|---|---|---|---|
| M0 | `docs/PROTOCOL.md` + Python reference of log/encoding/signatures/HLC/replay + test vectors. **Done 2026-09-26.** M0a (encoding, keys, entries, chains, HLC, order: `peer/proto.py`, `peer/vectors/v1.json`); M0b (entry bodies, identity, authority, revocation, approvals, merge, private entries: `peer/replay.py`, `peer/vectors/v2-replay.json`) | 1–2 weeks | the rules exist in one testable place |
| M1 | Server rebuilt on the log: `plant.db` becomes a cache of the replay; current data migrated into entries (current accounts become person records + custodial keys). **Done 2026-09-26:** `server/engine.py` (log, custodial keys, root key, in-memory replay), `server/changes.py` (submissions/History on the log), `server/migrate_v1.py` (+ fixture written by the old code), same API | 2–3 weeks | today's app, same behaviour, now log-based |
| M2 | Desktop package (double-click) + same-Wi-Fi sync between desktops + file/QR bundles + client-isolation test tool. **M2a done 2026-09-26:** sync core (Noise XX checked against the published vector, exchange of entries + photos, fork detection, stranger filtering; PROTOCOL.md §15, `peer/noise.py`, `peer/sync.py`, engine as a node, server listener `sync_port` 8421, `app.py sync HOST`). **M2b done 2026-09-26:** peer mode (`mode: peer`, local-only, no password), join via server enrolment or join request + bundle, mDNS discovery + auto sync (`server/syncsvc.py`), Devices tab, admin-only unencrypted bundles, people without a server account in Users. **M2c done 2026-09-26:** `desktop.py` launcher (per-user data folder, peer mode, browser + Tk Open/Quit window, single instance, `--self-test`), PyInstaller one-folder spec `packaging/`, Linux menu installer, GitHub Actions workflow for Windows + Linux (built and checked here: Linux only) | 2–3 weeks | P2P works on laptops; server optional |
| M3 | Android: Kotlin core passing the vectors, local API, WebView viewer, M3 shell with the 3 tabs, same-Wi-Fi + file sync, multi-device pairing. Decided 2026-09-26: Kotlin core (not embedded Python), minimum Android 10 (API 29). **M3a done 2026-09-26:** `android/core` (JSON/canonical, Ed25519/X25519/ChaCha via BouncyCastle, entries/chains/HLC, replay, Noise, sync, MemoryNode): all vectors (v1, v2-replay, v3-sync, noise-xx, v4-malformed) + two-way TCP sync with the Python engine. **M3b done 2026-09-26:** the phone's node (`LocalNode` + `LocalApi` in core, JUnit-tested incl. joining the real app.py server) and the app (`android/app`: SQLite store, device key under the Android Keystore, WebView at https://kks.app/ served from the app, API through a JS bridge, no open port except the sync listener); verified on an Android 16 emulator end to end. **M3c done 2026-09-27:** Material 3 shell (Compose, NavigationSuiteScaffold: P&ID / Learning placeholder / Account & settings with sync + Manage pages from admin.html), camera or gallery for photos, the phone's Back steps back through the page first; verified on the emulator. **M3d done 2026-09-27:** NSD discovery + announcing (same `_kks._tcp` records as the laptops' zeroconf), auto sync while the app is on screen (2 min, 5 s after a change, new device), background sync every 15 min on unmetered networks (WorkManager); verified on the emulator except phone↔laptop discovery (the emulator's network can't carry multicast to the host). **Before M3e (2026-09-27):** metered-network sync setting, join by invite with a QR code (PROTOCOL.md §16), photos as JPEG XL (libjxl on the phone, pillow-jxl-plugin on laptops/servers, JPEG for viewers without JXL). **M3e done 2026-09-27:** R8 release build signed with a locally held key (docs/ANDROID_RELEASE.md), Android CI (tests, debug + unsigned release APKs). **After M3e (2026-09-27):** photos at JXL distance 1.9 / effort 9, never converted to JPEG (browsers without JXL decode it with libjxl in WebAssembly, the app hands the WebView a BMP from its own libjxl); computers scan invites with a webcam; joining without camera or code by asking an admin's device found on the Wi-Fi (6-digit code on both screens). Next: M4 Learning | 2–3 months | phones are full peers |
| M4 | Learning tab (course bundles, progress). **Done 2026-09-27:** courses with vendored fonts, private progress on the log (PROTOCOL.md §13, §17), native Learning tab on Android, learning.html on computers | 1–2 weeks after seeing the courses | |
| M5 | Internet P2P (ICE + signaling + TURN; hosting decided then). **Done 2026-09-28** (PROTOCOL.md §18; decided: a Cloudflare Worker relay on the plant's own account, direct first): presence in a per-plant relay room (signed with the device key), STUN + UDP hole punching with an own reliable UDP stream (`peer/rudp.py`, `Rudp.kt`), else a WebSocket pipe through the relay; the §15 Noise sync runs unchanged over either, so the relay sees only encrypted bytes. Relay address = a manager `setting` (Devices → Internet). Laptops, server and phones (on screen or the background job; metered setting respected). Verified: Python + Kotlin tests (also against the real Worker under `wrangler dev`), Android emulator ↔ server both ways (direct). NOT verified: a real Cloudflare deployment, real NATs / mobile data, two phones over the internet | 3–5 weeks | HQ ↔ plant without files |
| M5b | Before M6 (decided 2026-09-28): plant data out of the app (drawings, tags, procedures, locations, courses as a bundle signed by the manager, delivered by sync, §4), sanitize the repo and its history, make it public, in-app self-updates from GitHub Releases (Android: download + install prompt, the OS checks the signing key; desktop: signed release files, swapped in on the next start) | not estimated yet | a public repo without plant data |
| M6 | Fully native desktop in Nim: no browser, a native GUI on Linux and Windows (added 2026-09-27 by the user; details to be decided when we reach it). It would speak the same protocol and pass the same frozen vectors as Python and Kotlin | not estimated yet | the desktop app without a browser |
| M7 | After M6 (decided 2026-09-28): research running the app on iOS inside Python/shell apps (Pythonista 3, Pyto, iSH, a-Shell): what each allows (sockets, background, local web server, file access, crypto libraries), and whether that is usable or a native app is needed | research only | a yes/no with evidence |

*One person part-time with AI help; order-of-magnitude only.

## 12. What this doesn't solve

- A device that never reconnects keeps its copy of everything; revocation reaches a device only when it syncs.
- Two approvals of the same field made apart are resolved by rule, not by asking; the loser is kept and shown, not lost.
- Internet sync (M5) needs the relay to be deployed and set by the manager; without it, cross-site changes travel by file or via the server if one exists. Two devices both behind symmetric NATs always go through the relay pipe (slower, still end-to-end encrypted).
