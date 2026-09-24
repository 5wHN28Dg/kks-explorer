# Plan B: running without a company server

Status: **design notes only, nothing built.** Written 2026-09-25, before the app was presented to the company.
Use this if the answer to "can it run on a plant server?" is no, and paying for a server or domain is not an option.

## 0. First, find out what the "no" covers

"No server" and "no app" are different answers. Before using any Plan B, ask plainly:

- Is the problem **hosting** (IT won't run or maintain it), or **the data** (P&IDs and KKS lists must not sit on
  personal phones and laptops)?
- If it's the data, every option below is also a no, because each one puts plant documents on personal devices,
  and full P2P puts *all* of them on *every* device, with no way to take them back. Don't route around that; it's
  the kind of thing that ends a probation period badly. What might still be allowed: the app on company machines only.
- If it's hosting, the options below are fine, and it helps to say so in writing: "OK for staff to use it on their
  own devices, without company hosting?"

## 1. The ladder: cheapest option first

Each step is useful by itself. Only climb if the step below isn't enough.

| Step | What | Cost | Covers |
|---|---|---|---|
| B0 | **Intermittent server**: the current app, run on a laptop when it's on | nothing, works today | same-network use; phones work offline in between |
| B1 | **File sync**: export queued changes / import updates as a file | ~days | people who never share a network with the laptop |
| B2 | **Full P2P**: every device a peer, signed changes, LAN sync | ~months | no machine is "the server" at all |

### B0: intermittent server (no new code)

- Run `python3 app.py` on your laptop when you're at the plant. Phones on the same Wi-Fi sync then. Between
  connections, the offline copy and the outbox already work: reading, search and edits all keep working, edits queue.
- Raise `offline_days` in `config.json` (e.g. 30) so phones stay usable between sessions.
- **Needs HTTPS for the offline app on phones.** Without a domain: your own certificate authority plus a
  certificate for the laptop's IP (`tls_cert`/`tls_key` are already supported). Install the CA certificate once per
  phone (Firefox on Android also needs "Use third party CA certificates" in its hidden settings). Give the laptop a
  fixed IP on that Wi-Fi: the installed app and its data are tied to the exact address.
- Limit: only reachable when the laptop is on and on the same network.

### B1: file sync (small addition)

- User side: "Export my queued changes" → a file (signed later, in B2) → sent by USB, WhatsApp, email.
- Manager side: "Import" → changes land in the approval queue like any other submission (they already carry
  `client_id`, so importing twice is harmless). Approve as usual.
- Back to users: "Export data update" → a file with the current approved state (equipment data, links, reviews,
  photos added since a given revision). Users import it.
- Covers HQ, or anyone who never shares a network with the laptop, without any internet server.

## 2. B2: full peer-to-peer design

The same idea "serverless" messengers use (Briar, Jami, Secure Scuttlebutt, Syncthing): **identity is a key pair,
authority is a signature, data is a log that devices exchange when they meet.**

### 2.1 Identity and authority

- Every device generates an **Ed25519 key pair** on first run. The private key never leaves the device (Android:
  Keystore; desktop: a file readable only by the user).
- **Manager root key.** Your key is the root of trust and is baked into every copy of the app (or the plant data
  bundle). Whoever holds it is the manager.
- **Certificates instead of a user table.** The manager signs `{"admin": <pubkey>, "name": "...", "since": ...}`.
  Admins sign `{"user": <pubkey>, ...}`. Any device can verify any role offline by walking the chain to the root.
- **Revocation** is a signed record too ("key X revoked as of T"). It spreads device to device, so it is **not
  instant**: until a device has seen it, that device still accepts the revoked key. Mitigate by having every sync
  exchange revocations first.
- **Losing the manager key** kills the trust root. Keep an offline backup of it (printed QR code or encrypted file
  in a safe place). Hand over the manager role (section 1 of the to-do) by signing a transfer to another key, same
  as today's transfer flow, then the old key is revoked.

### 2.2 Data: a signed, append-only log

Our server already works this way internally (submissions → approval → revisions). P2P makes the log the product.

- Each device writes its own log: `{author, seq, prev_hash, time, type, payload, signature}`. `seq` counts up per
  author and `prev_hash` chains entries, so gaps and tampering are detectable (the Secure Scuttlebutt model).
- Entry types = today's submission kinds (`equipment`, `review`, `link`, `photo`, `photo_delete`) plus
  `approve`/`reject` (by admins, referring to an entry by hash), plus the certificate/revocation records.
- **Live state** = replay of all *approved* entries, in a deterministic order. Every device computes the same result
  from the same set of entries, with no coordinator.
- **Ordering:** hybrid logical clocks (wall time + counter), ties broken by author key. Never trust phone clocks alone.
- **Conflicts:** reuse today's 3-way field merge (`server/changes.py`, `plan()`): edits to different fields merge.
  When two approvals clash on the same field: manager beats admin, then the later HLC wins, and the losing
  approval is flagged for review on every device. Same rule everywhere, or devices disagree forever.
- Admin/manager edits count as self-approved (as today with `admins_apply_directly`).
- Photos are **content-addressed blobs** (named by SHA-256), fetched on demand, never deleted (as today).

### 2.3 Sync protocol

- On connect: authenticate both ends by key (Noise protocol or TLS with pinned keys, no certificate authority
  needed), check certificates and revocations, then exchange a **version vector** `{author: last seq}` and send
  each other the missing entries. Blobs follow, smallest first; big ones only on Wi-Fi.
- Relaying is free: device A can carry B's entries to C (signatures prove authorship), the way messages hop
  between peers in Briar. That's how changes cross from the plant to HQ without a server: someone travels, or a file
  is sent (B1's file format = a batch of log entries).

### 2.4 Transports (in order of value)

1. **Same Wi-Fi:** discovery by mDNS/DNS-SD (`_kks._tcp`, Android NSD), then TCP. Plant Wi-Fi may block device-to-device
   traffic ("client isolation"): check that first, it would kill this transport.
2. **File / QR:** the B1 format. Always works.
3. **Wi-Fi Direct / Bluetooth** phone-to-phone (Briar does this). Nice, fiddly on Android, do last.
4. **Across the internet with no server:** realistically not without someone's infrastructure (Tor onion services
   like Briar, DHT bootstrap nodes like Jami). Out of scope; B1 files cover it.

**Shortcut worth testing first: Syncthing as the transport.** Syncthing already does LAN discovery, device keys and
encrypted P2P folder sync, and can run with global discovery and relays switched off. The app would write its signed
log entries and photos as files into a synced folder and read everyone else's. That's zero networking code of our own.
Check its Android status before relying on it (the official Android app was discontinued at the end of 2024; a
community fork exists).

### 2.5 Plant data (P&IDs, tags, procedures, locations)

- Distributed as a **bundle signed by the manager key** (sheets, `tags.json`, …, with a version number). Devices
  accept a bundle only with a valid signature and a newer version. Updates travel like log entries.
- ~20 MB today. Every device holds all of it.

### 2.6 Security on devices

- Every device carries the complete plant data plus everyone's notes and photos. Encrypt at rest (SQLCipher /
  Android Keystore-wrapped key), require a device PIN/biometric to open the app.
- A lost phone = a lost copy. Revoke its key; the data on it can't be recalled.
- This is strictly more exposure than the server version. Say so if anyone asks.

### 2.7 Platforms

- **Android:** native app (Kotlin + Jetpack Compose). A web app can't listen for connections or discover peers.
  The hardest UI piece is the sheet viewer: 6400 px images with pan/zoom and tag hotspots need tiled/subsampled
  image loading.
- **Linux / Windows:** the current Python server run locally is already a working single-user peer (`localhost`
  counts as secure, so the offline web app works). Needs the log, signatures and sync added. Alternatively Compose
  Desktop, to share code with Android.
- **iOS / macOS:** out. Building for iOS needs a Mac, and iOS restricts background networking heavily.
- **Code sharing:** either Kotlin Multiplatform (one implementation of log, merge and sync for Android + desktop), or
  two implementations (Kotlin + Python) held together by a written protocol spec and shared test vectors (fixed
  inputs → expected bytes, signatures, states). Two implementations of a sync protocol drift unless tested that way.

### 2.8 Rough effort (one person, part-time, with AI help)

Order of magnitude only, not a promise:

1. Protocol spec + test vectors (entry format, signing, ordering, merge rules): ~1–2 weeks.
2. Desktop peer: log + signatures + replay on top of the current Python code: ~2–3 weeks.
3. Android app: viewer, search, panel, offline storage: ~1–2 months.
4. LAN sync (or Syncthing integration), certificates/revocation UI: ~3–4 weeks.
5. Field testing on plant Wi-Fi: ongoing.

Compared with B0 (nothing) and B1 (days), this is the expensive rung.

### 2.9 Prior art to read before building

- **Syncthing:** device IDs = certificate hashes, local discovery, block exchange. Closest model, possibly the transport.
- **Secure Scuttlebutt:** per-author signed append-only logs, gossip replication. Closest data model.
- **Briar:** Bluetooth/Wi-Fi/Tor transports, the "Mailbox" (an always-on old phone = a server by another name).
- **Automerge / Yjs:** CRDTs, if the approval model is ever dropped for free-for-all editing (not planned).
- **Jami / OpenDHT:** what internet-wide serverless discovery costs.

## 3. Open questions to settle before B2

- Does plant Wi-Fi allow device-to-device traffic (client isolation)?
- Who else may hold the manager key backup?
- Must photos reach every device, or only on request? (Storage on phones.)
- Would the company accept B2's data exposure when it refused a server? Probably the same answer as section 0.
