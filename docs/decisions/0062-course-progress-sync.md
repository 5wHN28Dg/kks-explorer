# 0062 Course progress follows a person's own devices, sealed so only they can read it

Date 2026-10-22 · Scope: PROTOCOL-v2 §13, §17; the Nim core (progress, replay), the server, every client · Status:
**decided by the user, 2026-10-22** (W1, R1, and the
pairing step with a 6-digit code) · Requirement: REQUIREMENTS R8, the user's decision
of 2026-10-22: "course progress syncs between a user's own devices, and only that user can read it, not the manager
and not the server".

**Question:** how does a person's set of devices share the secret that seals their course progress, so that the
server only stores and relays ciphertext, and a server that misbehaves still can't read it?

## Findings (what the code does today, 2026-10-22, main 20c7b3b)

- **Sealing is there:** every native app (Android, GNOME, Windows) saves progress through the local API
  (`/api/progress`) as `private` entries (§13): AES-256-GCM under the person secret, the person ID in the associated
  data (`core/src/kks/progress.nim`). The server answers `/api/progress` with 404, so a browser keeps progress in its
  own localStorage (`course-bridge.js`), and the server holds no person secret (§17).
- **Sharing is not:** nothing calls the §17 swap (`secretsRequest` only appears in tests). Each device makes its own
  secret on its first save (`ensureSecret`), so today a phone and a laptop of one person can't open each other's
  progress: it is private, but it doesn't follow the person.
- **§17 as written would not meet the requirement either.** A responder hands its secrets to any client that is
  "certified to the same person and not revoked". The server holds every web account's custodial key (decision 0052)
  and certifies devices with it (§16 enroll, `server.nim` `device_cert` from the custodial key). So a server, or anyone
  running code as its user, can certify a device of its own for any person with an account, and that device would be
  given the secret. The same holds for any automatic sharing to "every device of the person": **the server decides
  who the person's devices are**, so a guarantee against the server needs the person to confirm each new device.
- **The device key can't be used to receive a secret on every target.** On Android it is an AndroidKeyStore key made
  for signing only (`Keys.kt`); key agreement inside the Keystore needs Android 12, and the Note 9 runs Android 10.
  So each device needs a separate P-256 key for receiving (the *box key*), kept in its sealed store (0020) like its
  other secrets.
- **Devices rarely meet.** Phones sync with the server, LAN peers and whoever is on the relay at that moment
  (`appstate.syncAll`), so two devices of one person are seldom online together. A swap on a direct connection (§17)
  would almost never run, but anything written to the log reaches every device through the server.
- **A browser can't keep a secret from the server that serves its code.** The web app's JavaScript comes from the
  server on every load, so a compromised server could serve a version that reads a key held in the page (IndexedDB,
  even as a non-extractable WebCrypto key: it can still decrypt with it). A browser is also not a device in the log;
  it acts through the server's custodial key.

## Options considered

| | how a new device gets the secret | meets "not the server"? |
|---|---|---|
| A | §17 swap or a log share to any device certified for the person, no confirmation | **no**: the server can certify a device for the person (custodial key) |
| B | a key derived from the password, or held by the server for the person | **no**: the server checks the password and holds the custodial keys |
| C | sealed to the receiving device's own device key (ECIES, §20) | yes, but impossible on Android 10 (Keystore signing key) |
| **D** | **sealed to the receiving device's box key in a log entry, after the person paired the two devices by comparing a code on both screens** | **yes**: the server relays ciphertext; with committed nonces, a device it certifies can't steer the code to match |

## Choice (for native devices): D, pairing by code, shares through the log

Spec: PROTOCOL-v2 §17 (rewritten). In short:
- Each device publishes a **box key** (a `box_key` entry, signed in its own chain, so the server can't swap it).
- **Pairing:** the person presses Pair on each device. Each device first commits to a fresh random nonce in the log,
  and reveals it only after it holds the other's commitment; the 6-digit code comes from both device IDs, both box keys
  and both nonces. The person checks the codes match and confirms on each device. Each side then writes a
  `secret_share` entry: its secrets, ECIES-sealed (§20) to the box key the code was made with. It all goes through the
  log, so the two devices never need to be online together; it takes a few sync rounds.
- **Why the commitments** (found by the blind review, 2026-10-22): a code made from the device IDs and box keys alone
  is fixed and public, so a server could try box keys for a device of its own until it shows the real device's code
  (about a million tries for 6 digits), and hide the real one. With each nonce committed before the other is seen,
  neither side can steer the code: a stand-in matches with probability one in a million per attempt.
- A device takes secrets only from a device it paired with itself, and passes any new secret on to its other paired
  devices, so the person's devices converge without pairing every two of them. A device certified by the server alone
  is paired with nobody: it gets nothing, and secrets it shares are ignored (it can't make a device write with a key
  the server knows).
- **Which secret writes:** the newest not retired. When a device that holds the secrets is removed, the person's
  devices retire every secret they hold and move to a new one the removed device never sees, and save the order-free
  progress (solved questions, best scores) again under it.
- **Hardened after the adversarial review (2026-10-22):**
  - only holders known from trusted shares count, so devices the server certified on its own can't trigger rotations;
  - shares carry the removed devices, so a device whose replay the server keeps the revoke from still stops sharing
    to the removed one;
  - retiring old secrets on rotation means a far-future `made` can't keep a stolen device's secret writing;
  - `made` is bounded to 2^53 − 1;
  - a commitment whose nonce was already revealed is never answered, so the same two devices can pair again;
  - state is saved before a reveal is written.
- **Merging** stays as COURSES §8 and §17 say: solved and skip are objects merged by union, `finalBest` the larger,
  `last` the later in replay order. Two devices progressing offline lose nothing: every save carries the whole object,
  and replay merges every entry.
- **The server** stores and relays `box_key`, `secret_share` and `private` entries like any other. A test asserts that
  its store holds no person secret and no plaintext progress.

The cost: every new device needs one pairing with a device the person already has. Until then it keeps its own
progress, which merges in once the pairing is done.

## Known limits (from the adversarial review, 2026-10-22; accepted as they stand)

- The server sees who paired with whom and when, how many shares each device writes, and roughly how many secrets a
  share holds (its length). It never sees a secret or any progress.
- Rows name a device by its label, which the server sets for devices it certifies: the code is the check, and the
  help text says so. No fingerprint is shown next to the code.
- A commitment that was never revealed stays fresh: a re-pairing can wait until Pair is pressed again on the other
  device.
- Past 32 secrets, a newly paired device does not get old `skip` and `last` values until they are next written.
- A removal proof is checked by signature and authority, not against its author's chain: a paired device could circulate
  a revoke it never published (its effect ends once that device is cut; it could publish a real one anyway).
- A device cut by a fork, not a revoke, has no revoke entry to prove its removal; the person's devices then keep reading
  each other's progress but each writes with its own new secret.
- An honest device that holds 16 proofs all newer than one hidden removal could pass that removed device's secret on
  unretired; this needs about 17 real removals, a stolen device, and a server that hides one revoke from one device.

## The user's choices (2026-10-22)

1. **A person who uses only the web app** (or a browser next to their devices):
   - **W1 (chosen):** the browser keeps progress in that browser only, as now. Not synced, but the guarantee
     holds.
   - **W2:** the browser pairs like a device: a box key and the secrets in IndexedDB, its shares written through the
     server. Synced, but the guarantee then holds only against stored data and an honest server: a compromised
     server could serve a page that reads the secret. Web-only people would lose that protection, and so would people
     who pair a browser with their phone.
2. **All of a person's devices are lost** (or wiped):
   - **R1 (chosen):** the progress is gone. The courses can be done again. Nothing extra to keep.
   - **R2:** a recovery code (26 characters, 128 bits) shown once when the person first saves progress; the secrets,
     sealed under a key derived from it, go in the log. Entering it on a new device restores the progress. The
     server can't guess 128 bits, but whoever finds the written-down code can read the progress.
3. **The pairing step** with a 6-digit code on both screens: accepted.

So the web app keeps progress in the browser and says so, and nothing is kept anywhere to recover a lost person
secret.

## When to revisit

If the server stops holding custodial keys (0052's alternative), automatic sharing to every device of the person
(option A) would meet the requirement and the pairing step could go. Also if browsers gain a way to run code the
server can't change (signed web bundles).
