# KKS Explorer sync protocol, version 1

Status: **M0a + M0b written 2026-09-26.** §1–7 (encoding, keys, entries, chain, clock, order): `peer/proto.py`,
vectors `peer/vectors/v1.json`. §8–14 (entry bodies, identity, authority, replay, merge, private entries):
`peer/replay.py`, vectors `peer/vectors/v2-replay.json` (`withdraw`, `vote` and review removal added 2026-09-26 for the
server on the log, M1, before anything depended on the file).
`peer/vectors/v4-malformed.json` (2026-09-26): every entry type with every field replaced by every kind of wrong value;
nothing may crash a replay (three such bodies crashed the Python replay before; a value is now type-checked before it
is used as a key, and anything a check still missed counts as `bad_body`). Implementations: Python (`peer/`) and
Kotlin (`android/core`, M3a), both pass all vector files; `tools/interop_node.py` lets the Kotlin tests sync with the
real Python engine over TCP.
Any implementation (Python, Kotlin) must reproduce every vector exactly; the vectors, not the prose, are the tiebreaker.

Design background: `docs/ARCHITECTURE.md`.

## 1. Canonical encoding

Everything that is hashed or signed is first encoded as **canonical JSON**:

- UTF-8, no byte-order mark, no whitespace between tokens (`,` and `:` only).
- Object keys sorted by code point. **Keys must match `[a-z_][a-z0-9_]{0,31}`** (ASCII, so every language sorts
  them the same way).
- Strings: characters as-is (no `\u` escaping of non-ASCII), except `"` → `\"`, `\` → `\\`, and control characters:
  `\b \f \n \r \t` as those short escapes, any other U+0000–U+001F as `\u00xx` with **lowercase** hex. Unpaired
  surrogates are invalid.
- Numbers: **integers only**, in the range ±(2^53 − 1), written in plain decimal with no leading zeros or `+`.
  No floats anywhere (Python and Kotlin print them differently). Quantities with fractions use fixed units, for
  example tag boxes in tenths of a pixel.
- `true`, `false`, `null`, arrays and objects as usual.

This is RFC 8785 (JCS) restricted to integers and ASCII keys, so JCS libraries also produce it.

## 2. Keys and peer IDs

- Every device has an **Ed25519** key pair (RFC 8032). Signatures are deterministic.
- **Peer ID** = the raw 32-byte public key in **base64url without padding** (43 characters). A peer ID *is* the key,
  so any entry can be verified without looking anything up.

## 3. Log entries

Each device appends to its own log. An entry is a JSON object with exactly these fields:

| field | type | meaning |
|---|---|---|
| `v` | int | protocol version, `1` |
| `peer` | string | peer ID of the author device |
| `seq` | int ≥ 1 | position in that device's log, counting up by 1 |
| `prev` | string / null | entry ID of the same device's entry `seq − 1`; `null` when `seq` is 1 |
| `hlc` | [int, int] | hybrid logical clock: `[milliseconds since epoch, counter]`, both ≥ 0 |
| `type` | string | entry type, same pattern as object keys (defined in M0b) |
| `body` | object | type-specific content (defined in M0b) |
| `sig` | string | Ed25519 signature, base64url without padding |

- **Signed bytes** = the ASCII bytes `kks-log-v1\n` followed by the canonical JSON of the entry **without** `sig`.
  The prefix keeps these signatures from ever being valid for anything else.
- **Entry ID** = lowercase hex SHA-256 of the canonical JSON of the whole entry **including** `sig` (64 characters).
- An entry is **valid** when it has exactly these fields with these types, `prev` is `null` exactly when `seq` is 1,
  and the signature verifies with the key in `peer`.

## 4. Chains

- A device's entries form a chain: seq 1, 2, 3 … with no gaps, each `prev` equal to the ID of the entry before.
- A receiver stores a device's entries only as an unbroken chain from seq 1. An entry whose predecessor is missing
  waits until the predecessor arrives.
- **Fork:** two different valid entries with the same `peer` and `seq`. Only a cloned or misbehaving device key can
  produce one. A fork is evidence: the receiver keeps the first chain it holds, stores both conflicting entries as
  proof, and treats the device as revoked from that `seq` on (the revocation rule itself is M0b).

## 5. Hybrid logical clock

Each device keeps a clock state `(l, c)`. `wall` is the device's wall clock in milliseconds.

- **Local event** (writing an entry): if `wall > l` then `(l, c) = (wall, 0)`, else `c = c + 1`. The entry gets `[l, c]`.
- **Receiving** an entry with clock `(l', c')`, from a device we trust:
  - Clamp first: if `l' > wall + 86 400 000` (more than 24 h ahead of our wall clock), don't let it move our clock,
    so one phone with a wrong date can't push everyone's clocks forward. The entry is still stored and ordered by
    its own `hlc`.
  - Otherwise `L = max(l, l', wall)`, and `c` becomes `max(c, c') + 1` if `L == l == l'`, `c + 1` if `L == l`,
    `c' + 1` if `L == l'`, else `0`; then `l = L`.

## 6. Total order

Entries from all devices are ordered by the key **(`hlc[0]`, `hlc[1]`, `peer`, `seq`)**. Strings compare by code
point (base64url is ASCII, so byte order). Every device holding the same set of entries gets the same order;
replay (M0b) runs in this order.

## 7. Error codes

Implementations report why an entry or chain is rejected with these codes (the vectors use them):

`bad_encoding` (not canonical JSON / float / bad key / out-of-range int) · `bad_fields` (missing, extra or wrongly
typed field) · `bad_version` · `bad_seq` · `bad_prev` · `bad_sig` · `chain_gap` · `chain_prev` · `fork`

## 8. Statements signed by the root key

The plant's **root key** (an Ed25519 key held by the manager: ideally on the laptop and in the manager's own
encrypted offline backup, not on a phone) signs *statements*, carried inside log entries. Statement bytes = ASCII
`kks-root-v1\n` + canonical JSON of the statement object; `root_sig` = base64url Ed25519 signature over them.

Statement kinds (exactly these fields):

- `{"kind":"manager","person":P}`: P is the manager.
- `{"kind":"device","device":D,"person":P}`: certifies device D for person P (the manager's first device, or a new
  device while none of the manager's devices is at hand).
- `{"kind":"rotate","root":K}`: the root key is replaced by K. Statements checked later in the order must be signed
  by K; old-key signatures there are `bad_root_sig`.
- `{"kind":"revoke","device":D,"last_seq":N}`: like a `revoke` entry, with the highest priority (§10).

Every replay starts from a **trust anchor**: the root public key (shipped in the plant-data bundle / app config).

## 9. Entry bodies

IDs: `person`, `photo`, `tag` = 32 lowercase hex characters (random 128-bit). `device` = a peer ID (§2).
`entry` = an entry ID. `blob` = lowercase hex SHA-256 of the blob's bytes. Box coordinates: integers, tenths of a
sheet-image pixel. A body must have **exactly** the listed fields.

| type | body | who may write it (§10) |
|---|---|---|
| `genesis` | `{plant, root, manager:{person, username, full_name, position}, stmt_manager, stmt_device, sig_manager, sig_device}` where `stmt_*` are §8 statements for this manager person and the writing device, `sig_*` their root signatures | the device named in `stmt_device`; only the first genesis in the order counts |
| `root` | `{stmt, root_sig}` | any certified device (the root signature is the authority) |
| `person` | `{person, username, full_name, position, role}`; role `user` or `admin` | admin/manager devices (manager only for role `admin`, or to edit an admin); a person's own device may change only their own `full_name`/`position` |
| `device_cert` | `{device, person, label}` | manager devices (any person), admin devices (persons with role `user`), a person's own valid device (their own person) |
| `revoke` | `{device, last_seq}`: entries of `device` with seq > `last_seq` are invalid | manager devices (any), admin devices (devices of `user` persons), a person's own device (their own devices) |
| `setting` | `{key, value}` | manager devices |
| `equipment` | `{kks, changes:{field:value}, base:{field:value}}` | anyone certified; counts when approved |
| `review` | `{tag_id, data, base}` | anyone; counts when approved |
| `link` | `{proc, step, kks, on}` | anyone; counts when approved |
| `photo` | `{photo, kks, blob, caption}` | anyone; counts when approved |
| `photo_delete` | `{photo}` | anyone; counts when approved |
| `tag_add` | `{tag, sheet, bbox:[x0,y0,x1,y1], kks, suffix, isa, note}` | anyone; counts when approved |
| `tag_remove` | `{tag}` | anyone; counts when approved |
| `approve` | `{entry, edit}`: `edit` is `null` or `{kks, suffix, isa}` (meaningful for `tag_add` only) | admin/manager devices |
| `reject` | `{entry, note}` | admin/manager devices |
| `withdraw` | `{entry}`: the author takes back their own proposal | a device of the person who wrote the proposal |
| `vote` | `{entry, on}`: advisory (photo choice); `on:false` takes the vote back | anyone certified |
| `private` | `{person, nonce, ct}` (§13) | a device of that person |

### 9a. Body rules

Lengths are counted in Unicode code points. Anything else is `bad_body`. Writers normalize (trim, upper-case…);
replay only accepts or ignores.

- `person`: `person` ID; `username` `[A-Za-z0-9_.@-]{2,40}`, unique ignoring ASCII case, never changes;
  `full_name` 2–80; `position` null or 0–80. Same rules for genesis `manager`. `plant` 1–80.
- `device_cert`: `device` `[A-Za-z0-9_-]{43}`, `person` known, `label` 0–80. `revoke`: `device` known (certified
  earlier), `last_seq` int ≥ 0. `setting`: `key` matches the §1 key pattern, `value` any JSON.
- `equipment`: `kks` `[0-9A-Z/]{3,24}`; `changes` non-empty, `base` any size; their fields among `area floor elev near
  loc notes custom`; `custom` = list (≤ 100) of `{k (0–200), v (0–2000)}`, the others strings 0–4000.
- `review`: `tag_id` `[A-Za-z0-9:_.-]{1,64}`, `data` null (remove the decision) or object, `base` null or object.
- `link`: `proc` 1–32, `step` int ≥ 0, `kks` as equipment, `on` boolean.
- `photo`: `photo` ID, `kks` as equipment, `blob` 64 hex, `caption` 0–500. `photo_delete` / `tag_remove`: an ID.
- `tag_add`: `tag` ID, `sheet` `[a-z0-9][a-z0-9-]{0,23}`, `bbox` 4 ints with 0 ≤ x0 < x1 ≤ 200000 and the same
  for y; `kks` null or `[0-9]{2}[A-Z]{3}[0-9]{2}[A-Z]{2}[0-9]{3}`; `suffix` `[A-Z0-9]{0,4}`; `isa` null or
  `[A-Z]{1,6}`; `note` 0–500.
- `approve`/`reject`/`withdraw`/`vote`: `entry` 64 hex; `note` 0–500; `on` boolean.
- `private`: `nonce` 16 base64url characters, `ct` 22–1 400 000 base64url characters.

## 10. Authority

Replay (§11) walks all entries in the total order (§6). At each entry it knows who is who **at that point**:

- a device is **valid** if a `device_cert`, genesis or root `device` statement for it came earlier in the order,
  and the entry's `seq` is not cut (below). A device belongs to one person forever: certifying it for another person
  is `not_allowed`.
- the device's **role** is its person's role: `manager` if that person is named in the latest valid `manager`
  statement, else the role in the person's latest valid `person` entry. The genesis manager's stored role is
  `admin`, so after a handover (a new `manager` statement) they are an admin.
- an entry whose author is not valid, or not allowed to write that type (§9 table), is **ignored**. It stays in the
  log and is reported as ignored with the reason (§11), but changes nothing.

**Revocation cuts** apply by `seq`, not by position in the order, so they also remove entries that come earlier in
the order (a stolen phone's writes after `last_seq` never count). Computed before the final pass, in rounds:

1. Cuts start as the fork cuts (§4: a device forked at seq s is cut at s − 1).
2. Replay with the current cuts and collect every authorized revocation (`revoke` entries and root `revoke`
   statements).
3. Sort them by **priority** (root statement, then author role manager, admin, user), then by the total order key of
   the entry carrying them. Walk the list starting from the fork cuts: skip a revocation whose own entry's seq is cut
   by the ones accepted so far; otherwise accept it (the device's cut becomes the smaller `last_seq`).
4. Repeat 2–3 until both the cuts and the accepted set stop changing, at most 8 rounds; use the last result.
   Revocations not accepted are reported as `overridden`.

A thief with a stolen device can revoke the owner's other devices; the higher rank wins, and between equal ranks
the earlier entry wins. Clocks are self-asserted, so a thief can backdate. **Between two devices of the same
person, only a root-signed revoke settles it.** That is why the root key should not live on the manager's phone.
If the root key itself is stolen, no log rule helps: the plant needs a new trust anchor (new root key shipped with
the app/config).

## 11. Replay

State = the result of applying, in the total order, every valid entry:

- identity and settings entries apply where they stand;
- entries by admin/manager devices of the data types (`equipment` … `tag_remove`) apply where they stand
  (self-approved);
- a user's data entry is a **proposal**. It applies at the first valid `approve` naming it, or never if a valid
  `reject` or `withdraw` naming it comes first. A `withdraw` counts only from a device of the proposal's author
  (else `not_allowed`). Decisions naming an entry not yet seen in the order wait; when the proposal comes they are
  taken in order there, the first valid one decides, later ones are `already_decided` (a waiting decision whose
  proposal never comes is not reported). A decision on an already decided proposal is `already_decided`.
  An approve's `edit` replaces `kks`/`suffix`/`isa` of a `tag_add`; an edit on any other type, or one that makes the
  tag invalid, turns the approval into a rejection.
- approve/reject naming an entry that never becomes a proposal (an admin's own entry, a revoked one) change nothing.

Per entry, the checks run in this order and the first failure is the reason: `revoked` (seq cut) → genesis handling
(`second_genesis`, `bad_body`, `bad_genesis`, `bad_root_sig`) → `not_certified` → `unknown_type` → `bad_body`
(field set, then §9a) → `bad_root_sig` → `not_allowed` → `username_taken` / `already_decided` → `overridden`.
Entries rejected before replay keep their §7 code (`bad_sig`, `chain_gap`, `chain_prev`, `fork` …; everything in a
device's chain from the first break on gets that break's code). An entry that can't even be encoded is not reported.

## 12. Merge rules

- **equipment**, per field, in field-name order: `live` = current value (`""`, or `[]` for `custom`, when unset). If
  `live` equals the proposal's `base[field]` (same default when missing) or the new value, apply. Otherwise it's a
  **conflict**: the new value wins, the overwritten value is recorded in `conflicts`. **Except** when `live` was set by
  a manager-authored or manager-approved entry and the new one is not: then `live` stays and the new value is
  recorded as the loser. A field whose value becomes `""` / `[]` is removed; an equipment item with no fields is
  removed. "Equal" = equal canonical JSON.
- **review**: the same rule on the whole `data` value against `base` (`live` = null when unset); `data` null
  removes the review.
- **vote**: per (entry, person) set/unset, later wins; reported only for entries that are proposals.
- **link**, **photo** / **photo_delete**, **tag_add** / **tag_remove**: set/unset; the later entry wins, no conflicts.
- Each conflict record: `{entity, key, field, kept, lost, kept_by, lost_by}`. `*_by` = the ID of the entry whose
  value it is (for an approved proposal, the proposal's ID; null if nobody set it). `field` is null for reviews.

## 13. Private entries

For data only its owner may read (course progress). Each person has a 32-byte **person secret**, created on their
first device and handed to their other devices during pairing (never written to the log).

- `nonce` = 12 random bytes, `ct` = ChaCha20-Poly1305(key = person secret, nonce, plaintext = canonical JSON of
  `{"type":…, "body":…}`, associated data = ASCII `kks-private-v1\n` + person ID), both base64url. The associated
  data binds the entry to its person: moving it under another person fails to decrypt.
- Replay stores private entries opaquely under their person; only a device holding the secret decrypts them.
  A person who loses every device and the secret loses their private data (by design: nobody else can read it).

## 14. Replay output

The state is a JSON object:

`root` (the current root key) · `manager` (person ID) · `settings` (including `plant` from the genesis) ·
`persons {person: {username, full_name, position, role}}` · `devices {device: {person, label, cut}}` (`cut` = last
valid seq or null; label `""` for genesis/root-certified devices) · `equipment {kks: {field: value}}` ·
`reviews {tag_id: data}` · `links [[proc, step, kks]]` (sorted) · `photos {photo: {kks, blob, caption}}` ·
`added_tags {tag: {sheet, bbox, kks, suffix, isa, note}}` · `proposals {entry: pending|approved|rejected}` ·
`conflicts [...]` (in the order they happened) · `votes {entry: [person IDs, sorted]}` (non-empty only) · `private {person: [entry IDs in order]}` · `ignored {entry: code}`.

**State encoding** = §1 canonical JSON, except that object keys may be any printable ASCII string of 1–64 characters
(the state is keyed by KKS codes, peer IDs and entry IDs; §9a keeps every such key ASCII). Two implementations given
the same entries, in any order, must produce the same state bytes.

## 15. Sync between two devices

Written 2026-09-26 (M2a). Python: `peer/noise.py`, `peer/sync.py`, node side in `server/engine.py`. Vectors:
`peer/vectors/noise-xx.json` (the published Noise vector), `peer/vectors/v3-sync.json` (key derivation, identity
proof, a handshake with fixed ephemeral keys).

**Connection.** Any byte stream (TCP on the same Wi-Fi for now). Every message on the wire is a 2-byte big-endian
length followed by that many bytes. First a **Noise handshake**, `Noise_XX_25519_ChaChaPoly_SHA256` exactly as in the
Noise specification (revision 34), prologue ASCII `kks-sync-v1`, the connecting side is the initiator:

- Each device's Noise static key is X25519 with private key = HMAC-SHA256(key = its Ed25519 seed, data = ASCII
  `kks-noise-static-v1`). Nothing extra to store; the Ed25519 key stays the only secret.
- Payload of message 1: empty. Payloads of messages 2 (responder) and 3 (initiator): canonical JSON
  `{"peer": <peer ID>, "sig": <base64url Ed25519 signature over ASCII "kks-noise-static-v1\n" + the 32-byte X25519
  static public key>}`. The receiver checks the signature against the static key the handshake authenticated, so a
  session is bound to a device key. (The same construction as libp2p-noise.)
- Afterwards, transport messages as in Noise (nonce counts up from 0 per direction). An **application message** is
  UTF-8 JSON, split into pieces of at most 65 000 bytes; each piece is sent as one transport message whose plaintext
  is one flag byte (`0x01` more pieces follow, `0x00` last piece) + the piece. At most 64 MiB per application message.

**Exchange.** Every application message is an object with `t`. The initiator speaks first at every step; the
responder answers. `{"t":"error","why":...}` may be sent instead of any message, then the connection closes.

1. `hello` both ways: `{"t":"hello", "v":1, "root": <trust anchor or null>, "vv": {<device>: [<last seq>, <entry ID of
   that entry>]}}`. Different non-null roots: stop (different plants). A device with no plant yet (`root` null)
   continues only if the other side's root is the one it was told to join (from the server enrolment or an invite, §16).
2. `entries`: `{"t":"entries", "entries":[...], "denied": true?}`. The initiator sends first; the responder decides
   what to send only after taking in the initiator's entries (the initiator's own certificate may be among them).
   What to send: every stored entry with seq above the other side's `vv` for its device; for a device whose entry at
   the other side's last seq has a different ID than ours, that device's whole chain (two copies of one key: the
   receiver finds where they split); all fork evidence held. **Nothing** (`denied`) unless the other side is a
   certified, unrevoked device of a known person in our own replay.
3. Taking entries in: verify each (§3); replay with the batch to see which devices are certified by then, and keep
   only entries of those devices (a stranger's entries are not stored); per device, continue the stored chain in
   seq order (skip entries whose predecessor is missing: a later sync brings it); a valid entry for a (device, seq)
   we already hold with a different ID is **fork evidence**: stored apart and replayed (§4 cuts the device).
4. `want` both ways: `{"t":"want", "blobs":[<sha256 hex>...]}`: blobs referenced by the log (photos, and photos of
   pending proposals) that the sender lacks.
5. Blobs, initiator first: `{"t":"blob", "sha":..., "data": <standard base64>}` per wanted blob held, then
   `{"t":"blobs_end"}`. Again nothing unless the other side may read. A receiver accepts a blob only if its log
   references that hash and the bytes hash to it.
6. `bye` both ways.

Relaying is automatic: a device sends every entry it holds, not only its own, so an edit reaches a device that never
met its author.

## 16. Join by invite (QR code)

For a new device next to an admin on the same network: no files and no server account. Implemented by
`server/invites.py` + `server/node.py` (`InviteJoin`) and `android/core/.../Invites.kt`; the wire part in
`peer/sync.py` / `Sync.kt`.

**Invite.** An admin's device makes `{"kks_invite":1, "plant": <name>, "root": <trust anchor>, "peer": <the device ID
that answers on the sync port>, "addrs": ["<ip>:<port>", ...], "token": <16 random bytes, base64url>, "exp": <unix
seconds>}` and shows its compact JSON as a QR code (and as text to copy). It is kept in memory only, is valid for 15
minutes, and serves one device. The QR code is the trust channel: whoever scans it learns which plant root and which
device to trust; the token proves to the admin's device that the asker saw the code.

**Asking.** The new device connects to one of `addrs`, runs the §15 handshake, and stops unless the other side's
device ID equals `peer`. Instead of `hello` it sends `{"t":"join", "token":..., "request": <a signed join request>}`
(the `.kksjoin` object: `{kks_join:1, device, username, full_name, position, label, created, sig}`, `sig` = Ed25519 by
`device` over `"kks-join-v1\n"` + canonical bytes of the rest). The request's `device` must be the session's remote
device. The answer is one `{"t":"join_ack", "state": ..., "why"?: ...}`, then the connection closes:

| state | meaning |
|---|---|
| `waiting` | the admin sees the request (name, username, position, device label) and has not decided yet |
| `accepted` | the admin certified the device (a normal `device_cert`, plus a `person` entry for a new person) |
| `refused` | the admin refused |
| `used` | another device already asked with this token |
| `unknown` | no such invite here (expired, cancelled, or the device restarted) |
| `bad` | the join request's signature or device doesn't check out |

The new device asks again every 2 s while `waiting`. Once `accepted` it syncs (§15) with the same address, adopting
the invite's `root`; the log it receives certifies it. The same rules as importing a join request apply on the
admin's side: an existing username needs the admin's explicit OK (it adds a device for that person), and only the
manager adds devices for admins. A responder that doesn't know invites answers `unknown`; a listener still reads a
`hello` first message exactly as before, so §15 is unchanged.
