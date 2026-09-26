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
  (downloaded on Wi-Fi). **Stored as JPEG XL**, visually lossless (distance ≈ 1.0) after capping the long side (e.g.
  3000 px), encoded by the device that takes/imports the photo: Android with a bundled libjxl, desktop/server with a
  bundled Python JXL encoder; browsers without the app upload JPEG and the server converts. **Display:** as of
  Sept 2026 Chrome/Android WebView and Firefox decode JXL only behind a flag (Safari by default), so the local peer
  serves `image/jxl` only to clients whose `Accept` header includes it and a cached JPEG copy to everyone else.
  Measure the real saving on field photos before relying on a number.
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

- **Course bundle:** the HTML files unchanged + the three fonts vendored (Atkinson Hyperlegible, Barlow Semi Condensed,
  JetBrains Mono, all SIL Open Font License), signed and versioned like the plant data. The font links are rewritten
  to the local copies when the bundle is built, so courses work offline and never contact Google.
- **Progress bridge:** the host injects a small script before the course's own script. It pre-fills the course's
  `localStorage` keys from the local peer and mirrors every write back, so courses need no edits.
- **Scores are private** (decided 2026-09-26): the courses are for learning, not assessment. Progress entries are
  encrypted to the person's own devices (§4); admins and the manager cannot read them. Progress follows the person
  from phone to laptop.

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
| M3 | Android: Kotlin core passing the vectors, local API, WebView viewer, M3 shell with the 3 tabs, same-Wi-Fi + file sync, multi-device pairing | 2–3 months | phones are full peers |
| M4 | Learning tab (course bundles, progress) | 1–2 weeks after seeing the courses | |
| M5 | Internet P2P (ICE + signaling + TURN; hosting decided then) | 3–5 weeks | HQ ↔ plant without files |

*One person part-time with AI help; order-of-magnitude only.

## 12. What this doesn't solve

- A device that never reconnects keeps its copy of everything; revocation reaches a device only when it syncs.
- Two approvals of the same field made apart are resolved by rule, not by asking; the loser is kept and shown, not lost.
- No internet P2P until M5; until then, cross-site changes travel by file or via the server if one exists.
