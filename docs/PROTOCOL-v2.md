# KKS Explorer sync protocol, version 2

**Status: draft, M6 phase 1 (started 2026-09-30).** It replaces version 1 (docs/PROTOCOL.md, frozen as the record of
v1; removed from the tree 2026-10-05 and kept in the repository's history, decision 0048) according to decision records 0017, 0020, 0024 and 0028.

Reference implementation for generating and cross-checking vectors: `ref/` (Python, test-only). The product
implementation is the Nim core (0027). The vectors in `ref/vectors/v2-*.json`, not the prose, are the tiebreaker.

**What changed from v1:**
- §2, §3: keys, peer IDs, signatures and entry IDs.
- §8: root statements, `backup_key`, `import`.
- §9: genesis import.
- §13: private-entry cipher.
- §15: the channel.
- §16, §18: messages carry keys.
- §19: file kinds.
- §20: encryption to a key. §21: migration.
- Everything else is v1's rules, restated so this document stands alone.

## 1. Canonical encoding

Everything that is hashed or signed is first encoded as **canonical JSON**:

- UTF-8, no byte-order mark, no whitespace between tokens (`,` and `:` only).
- Object keys sorted by code point. **Keys must match `[a-z_][a-z0-9_]{0,31}`** (ASCII, so every language sorts
  them the same way).
- Strings: characters as-is (no `\u` escaping of non-ASCII), except `"` → `\"`, `\` → `\\`, and control characters:
  `\b \f \n \r \t` as those short escapes, any other U+0000–U+001F as `\u00xx` with **lowercase** hex. Unpaired
  surrogates are invalid.
- Numbers: **integers only**, in the range ±(2^53 − 1), in plain decimal with no leading zeros or `+`. No floats
  anywhere. Quantities with fractions use fixed units, e.g. tag boxes in tenths of a pixel.
- `true`, `false`, `null`, arrays and objects as usual.

This is RFC 8785 (JCS) restricted to integers and ASCII keys, so JCS libraries also produce it. Only the writer must
produce these exact bytes.

**Strict reading** (decision 0029). Every JSON a device receives or loads is RFC 8259 JSON (messages, bundles,
plant-data and course files). It is read with these rules, so that the same bytes mean the same value on every
device. The input is **rejected as a whole** when it has any of the following:
- bytes that are not UTF-8, a byte-order mark, or an unpaired surrogate (raw or as a `\u` escape);
- a duplicate key in one object;
- a trailing comma, a leading zero (`01`, `-01`), `+`, `NaN`, `Infinity`, or a raw control character (U+0000–U+001F)
  inside a string;
- anything but whitespace (space, tab, LF, CR) after the value;
- nesting deeper than 128 arrays and objects.

The reader keeps three kinds of numbers apart:
- **integer:** no fraction, no exponent;
- **big integer:** the same, but outside ±(2^63 − 1);
- **float:** has a fraction or an exponent.

The rules of this section (integers within ±(2^53 − 1), no floats) are checked on the value afterwards and give
`bad_encoding`. `-0` reads as the integer 0. Platform parsers may be used if they can enforce all of this. Vectors:
`ref/vectors/v2-json.json`.

**base64url** = RFC 4648 §5 alphabet, **without padding**, everywhere in this document unless it says "standard
base64".

## 2. Keys, signatures and peer IDs

- **Curve and hash:** ECDSA over NIST P-256 (secp256r1) with SHA-256 (FIPS 186-4). Every target platform provides it
  (0017).
- **Public key** (`key`): the SEC1 **uncompressed** point, 65 bytes starting with `0x04`, in base64url (87
  characters). A key is valid only if it is a point on the curve and not the point at infinity.
- **Peer ID:** base64url of the **first 24 bytes of SHA-256(the 65 key bytes)**. That's 32 characters, pattern
  `[A-Za-z0-9_-]{32}`.
- **Signature:** 64 bytes, `r ‖ s`, each 32 bytes big-endian (IEEE P1363), in base64url (86 characters).
  - `r` and `s` must lie in 1 … n−1, and **s must be ≤ n/2** ("low-S").
  - Signers whose platform returns a high `s` replace it with `n − s`. Signers whose platform returns DER convert it.
  - Verifiers reject anything else as `bad_sig`.
  - n = FFFFFFFF 00000000 FFFFFFFF FFFFFFFF BCE6FAAD A7179E84 F3B9CAC2 FC632551.
- ECDSA signatures are randomized. Two signatures of the same bytes differ, and nothing in this protocol depends on
  signature bytes being unique (§3: entry IDs exclude the signature).

## 3. Log entries

Each device appends to its own log. An entry is a JSON object with exactly these fields:

| field | type | meaning |
|---|---|---|
| `v` | int | protocol version, `2` |
| `peer` | string | peer ID of the author device (§2) |
| `seq` | int ≥ 1 | position in that device's log, counting up by 1 |
| `prev` | string / null | entry ID of the same device's entry `seq − 1`; `null` when `seq` is 1 |
| `hlc` | [int, int] | hybrid logical clock: `[milliseconds since epoch, counter]`, both ≥ 0 |
| `type` | string | entry type, same pattern as object keys |
| `body` | object | type-specific content (§9) |
| `key` | string | **only in the entry with `seq` 1:** the device's public key (§2). Absent in every other entry. |
| `sig` | string | signature (§2) |

- **Signed bytes** = ASCII `kks-log-v2\n` followed by the canonical JSON of the entry **without** `sig`.
- **Entry ID** = lowercase hex SHA-256 of the canonical JSON of the entry **without** `sig` (64 characters). A
  re-signed or altered signature can't change an entry's ID.
- **Field check** (`bad_fields`): exactly the fields above with these types; `key` present exactly when `seq` is 1.
  `prev` is `null` exactly when `seq` is 1 (`bad_prev` otherwise). `v` is 2 (`bad_version`).
- **Key check** (`bad_key`, entries with `seq` 1): `key` decodes to a valid point, and `peer` equals its peer ID.
- **Signature check** (`bad_sig`): the signature verifies against the **chain key**, the `key` of the same device's
  entry with `seq` 1. An entry can be verified only once its device's seq-1 entry is known. Until then it waits like
  any entry with a missing predecessor (§4).
- **Copies:** entry IDs exclude the signature, so a receiver may see several copies with one ID (e.g. the same entry
  with a re-encoded or corrupted signature). The entry is valid if **any** copy passes the checks; the others are
  dropped. An error is reported under that ID only when no copy passes.

## 4. Chains

- A device's entries form a chain: seq 1, 2, 3 … with no gaps, each `prev` equal to the ID of the entry before.
- A receiver stores a device's entries only as an unbroken chain from seq 1. An entry whose predecessor is missing
  waits until it arrives.
- **Fork:** two different entry IDs with the same `peer` and `seq`, both valid. Only a cloned or misbehaving device
  key can produce one; the same content signed twice is the same entry.
  - A fork is evidence: the receiver keeps the first chain it holds, stores both conflicting entries as proof, and
    treats the device as cut from that `seq` on (§10).
  - A fork at seq 1 means two different first entries for one peer ID. Both must carry a key hashing to that ID, which
    would take a SHA-256 collision, so in practice it doesn't occur. It is still treated the same way.

## 5. Hybrid logical clock

Each device keeps a clock state `(l, c)`. `wall` is the device's wall clock in milliseconds.

- **Local event** (writing an entry): if `wall > l` then `(l, c) = (wall, 0)`, else `c = c + 1`. The entry gets
  `[l, c]`.
- **Receiving** an entry with clock `(l', c')`, from a device we trust:
  - If `l' > wall + 86 400 000` (more than 24 h ahead of our wall clock), don't let it move our clock. The entry is
    still stored and ordered by its own `hlc`.
  - Otherwise `L = max(l, l', wall)`. Then `c` becomes:
    - `max(c, c') + 1` if `L == l == l'`;
    - `c + 1` if `L == l`;
    - `c' + 1` if `L == l'`;
    - `0` otherwise.
  - Then `l = L`.

## 6. Total order

Entries from all devices are ordered by **(`hlc[0]`, `hlc[1]`, `peer`, `seq`)**. Strings compare by code point
(ASCII). Every device holding the same set of entries gets the same order; replay runs in this order.

## 7. Error codes

`bad_encoding` (not canonical JSON, float, bad key, out-of-range int) · `bad_fields` · `bad_version` · `bad_seq` ·
`bad_prev` · `bad_key` · `bad_sig` · `chain_gap` · `chain_prev` · `fork`

## 8. Statements signed by the root key

The plant's **root key** is a P-256 key held by the manager: on the laptop, plus the manager's own encrypted offline
backup (§20, passphrase rules in 0023), not on a phone. The **trust anchor** is the root's public key string (§2
`key` form, 87 characters); the **root ID** is its peer-ID form (32 characters).

Root statements are carried inside log entries.
- Statement bytes = ASCII `kks-root-v2\n` + canonical JSON of the statement object.
- `root_sig` = the signature (§2) over them.

Statement kinds (exactly these fields):
- `{"kind":"manager","person":P}`: P is the manager.
- `{"kind":"device","device":D,"person":P}`: certifies device D (peer ID) for person P.
- `{"kind":"rotate","root":K}`: the root key is replaced by K (a key string). Statements checked later in the order
  must be signed by K; old-key signatures there are `bad_root_sig`.
- `{"kind":"revoke","device":D,"last_seq":N}`: like a `revoke` entry, with the highest priority (§10).
- `{"kind":"backup_key","key":K}`: backups (0020) are encrypted to key K (§20) from now on.
- `{"kind":"import","v1":H,"state":S}`: only inside a genesis (§9, §21). H = the v1 archive hash, S = lowercase hex
  SHA-256 of the canonical JSON (§1) of the imported state (§21 pair form).

Every replay starts from the trust anchor (in the plant-data bundle, invite or app configuration).

## 9. Entry bodies

**IDs:**
- `person`, `photo`, `tag` = 32 lowercase hex characters (random 128-bit).
- `device` = a peer ID (§2).
- `entry` = an entry ID.
- `blob` = lowercase hex SHA-256 of the blob's bytes.

Box coordinates are integers, in tenths of a sheet-image pixel. A body must have **exactly** the listed fields.

| type | body | who may write it (§10) |
|---|---|---|
| `genesis` | `{plant, root, manager:{person, username, full_name, position}, stmt_manager, stmt_device, sig_manager, sig_device, import}`. `stmt_*` are §8 statements for this manager person and the writing device, `sig_*` their root signatures. `import` is `null` or `{stmt, root_sig, state}` (§21). | the device named in `stmt_device`; only the first genesis in the order counts |
| `root` | `{stmt, root_sig}`; `stmt` is not `import` | any certified device (the root signature is the authority) |
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
| `comment` | `{entry, text}`: a note on an entry; changes no state, replay lists it as side output `comments` | anyone certified |
| `private` | `{person, nonce, ct}` (§13) | a device of that person |
| `report` | `{sealed}` (§13a) | any certified device |

### 9a. Body rules

Lengths are counted in Unicode code points. Anything else is `bad_body`. Writers normalize (trim, upper-case…);
replay only accepts or ignores.

- **`person`:**
  - `person`: an ID.
  - `username`: `[A-Za-z0-9_.@-]{2,40}`, unique ignoring ASCII case, never changes.
  - `full_name`: 2–80. `position`: null or 0–80.
  - The same rules apply to genesis `manager`. `plant`: 1–80.
- **`device_cert`:** `device` `[A-Za-z0-9_-]{32}`, `person` known, `label` 0–80.
- **`revoke`:** `device` known (certified earlier), `last_seq` int ≥ 0.
- **`setting`:** `key` matches the §1 key pattern, `value` any JSON.
- **`equipment`:**
  - `kks`: `[0-9A-Z/]{3,24}`.
  - `changes` non-empty, `base` any size; their fields among `area floor elev near loc notes custom`.
  - `custom`: a list (≤ 100) of `{k (0–200), v (0–2000)}`; the other fields are strings 0–4000.
- **`review`:** `tag_id` `[A-Za-z0-9:_.-]{1,64}`, `data` null (remove the decision) or object, `base` null or object.
- **`link`:** `proc` 1–32, `step` int ≥ 0, `kks` as equipment, `on` boolean.
- **`photo`:** `photo` an ID, `kks` as equipment, `blob` 64 hex, `caption` 0–500.
  A caption that starts with `Tag plate` marks the photo of the equipment's tag plate (the metal plate with its KKS
  code); clients may show it apart. A convention, not a field: readers before 0.9.3 reject unknown photo fields, and
  read this one as a caption.
- **`photo_delete`, `tag_remove`:** an ID.
- **`tag_add`:**
  - `tag` an ID, `sheet` `[a-z0-9][a-z0-9-]{0,23}`;
  - `bbox`: 4 ints with 0 ≤ x0 < x1 ≤ 200000, and the same for y;
  - `kks` null or `[0-9]{2}[A-Z]{3}[0-9]{2}[A-Z]{2}[0-9]{3}`;
  - `suffix` `[A-Z0-9]{0,4}`, `isa` null or `[A-Z]{1,6}`, `note` 0–500.
- **`approve`, `reject`, `withdraw`, `vote`, `comment`:** `entry` 64 hex; `note` 0–500; `on` boolean; `text` 1–500.
- **`private`:** `nonce` 16 base64url characters, `ct` 22–1 400 000 base64url characters.
- **`report`:** `sealed` is a §20 object with exactly `{v, purpose, epk, nonce, ct}`: `v` the integer 2, `purpose`
  `kks-report`, `epk` a key string, `nonce` 16 base64url characters, `ct` 22–65 536 base64url characters.
- **`root` and genesis key fields:** `root` in genesis is a key string (§2). `rotate.root` and `backup_key.key` are key
  strings.
- **Genesis `import`:** see §21 for the state rules.

## 10. Authority

Replay (§11) walks all entries in the total order (§6). At each entry it knows who is who **at that point**:

- **A device is valid** if a `device_cert`, genesis or root `device` statement for it came earlier in the order, and
  the entry's `seq` is not cut (below). A device belongs to one person forever: certifying it for another person is
  `not_allowed`.
- **The device's role** is its person's role:
  - `manager` if that person is named in the latest valid `manager` statement;
  - otherwise the role in the person's latest valid `person` entry, or the imported role (§21).
  - The genesis manager's stored role is `admin`, so after a handover they are an admin.
- **An entry whose author is not valid**, or not allowed to write that type, is **ignored**. It stays in the log and
  is reported with the reason (§11).

**Revocation cuts** apply by `seq`, not by position in the order. Computed before the final pass, in rounds:
1. Cuts start as the fork cuts (§4: a device forked at seq s is cut at s − 1).
2. Replay with the current cuts and collect every authorized revocation (`revoke` entries and root `revoke`
   statements).
3. Sort them by **priority** (root statement, then author role manager, admin, user), then by the total order key of
   the entry carrying them.
4. Walk that list starting from the fork cuts:
   - skip a revocation whose own entry's seq is cut by the ones accepted so far;
   - otherwise accept it: the device's cut becomes the smaller `last_seq`.
5. Repeat 2–4 until both the cuts and the accepted set stop changing, at most 8 rounds; use the last result.
   Revocations not accepted are reported as `overridden`.

Between two devices of the same person, only a root-signed revoke settles it. If the root key itself is stolen, the
plant needs a new trust anchor.

## 11. Replay

State = the result of applying, in the total order, every valid entry:

- Identity and settings entries apply where they stand. The genesis `import` applies at the genesis (§21).
- Entries by admin/manager devices of the data types (`equipment` … `tag_remove`) apply where they stand
  (self-approved).
- **A user's data entry is a proposal.**
  - It applies at the first valid `approve` naming it, or never if a valid `reject` or `withdraw` naming it comes
    first.
  - A `withdraw` counts only from a device of the proposal's author (else `not_allowed`).
  - Decisions naming an entry not yet seen in the order wait. When the proposal comes, they are taken in order there:
    the first valid one decides, and later ones are `already_decided`. A waiting decision whose proposal never comes is
    not reported.
  - A decision on an already decided proposal is `already_decided`.
  - An approve's `edit` replaces `kks`/`suffix`/`isa` of a `tag_add`. An edit on any other type, or one that makes the
    tag invalid, turns the approval into a rejection.
- `approve`/`reject` naming an entry that never becomes a proposal change nothing.

**Per entry, the checks run in this order, and the first failure is the reason:**
1. `revoked` (seq cut);
2. genesis handling: `second_genesis`, `bad_body`, `bad_genesis`, `bad_root_sig`;
3. `not_certified`;
4. `unknown_type`;
5. `bad_body` (field set, then §9a);
6. `bad_root_sig`;
7. `not_allowed`;
8. `username_taken` / `already_decided`;
9. `overridden`.

Entries rejected before replay keep their §7 code. Everything in a device's chain from the first break on gets that
break's code.

## 12. Merge rules

- **equipment**, per field, in field-name order:
  - `live` = the current value (`""`, or `[]` for `custom`, when unset).
  - If `live` equals the proposal's `base[field]` (same default when missing) or the new value: apply.
  - Otherwise it's a **conflict**: the new value wins, and the overwritten value is recorded in `conflicts`.
  - **Except** when `live` was set by a manager-authored or manager-approved entry and the new one is not: then `live`
    stays, and the new value is recorded as the loser. Imported values (§21) count as set by nobody.
  - A field whose value becomes `""` / `[]` is removed; an equipment item with no fields is removed.
  - "Equal" = equal canonical JSON.
- **review**: the same rule on the whole `data` value against `base` (`live` = null when unset). `data` null removes
  the review.
- **vote**: per (entry, person) set/unset, later wins; reported only for entries that are proposals.
- **link**, **photo** / **photo_delete**, **tag_add** / **tag_remove**: set/unset; the later entry wins, no conflicts.
- **Each conflict record:** `{entity, key, field, kept, lost, kept_by, lost_by}`.
  - `*_by` = the ID of the entry whose value it is. For an approved proposal that is the proposal's ID; null if nobody
    set it, or the value was imported.
  - `field` is null for reviews.

## 13. Private entries

For data only its owner may read (course progress). Each person has a 32-byte **person secret**, created on their
first device and handed to their other devices (§17), never written to the log.

- `nonce` = 12 random bytes, `ct` = **AES-256-GCM**, both base64url:
  - key = the person secret;
  - plaintext = canonical JSON of `{"type":…, "body":…}`;
  - associated data = ASCII `kks-private-v2\n` + person ID;
  - `ct` includes the 16-byte tag at the end.
- Replay stores private entries opaquely under their person. Only a device holding the secret decrypts them.

## 13a. Diagnostics reports (added 2026-10-03)

Errors, crashes and sync failures a device saw, for the manager only (decision 0040).
- **Switching on:** a manager's own device (not a server: it holds no person secret) makes a P-256 *report key* and
  writes two entries:
  - a `private` entry (§13) for the manager person, plaintext `{"type":"report_key", "body":{"key": <the public key
    string>, "private": <the 32-byte scalar, base64url>}}`, so every device of the manager can read reports;
  - the setting `diagnostics` = `{"key": <the public key string>}`.
  The setting `diagnostics` = `null` switches it off. A new key replaces the old one; reports sealed to an old key
  stay readable by devices that hold its `report_key`.
- **Reporting:** while the setting is on, a device writes a `report` entry, ECIES (§20) to the setting's key with
  purpose `kks-report`. Plaintext = canonical JSON of `{"device", "app", "version", "platform", "model", "from",
  "to", "events": [{"at", "kind", "text", "n"}, …]}`:
  - `app`: `android`, `gnome`, `windows` or `server`; `platform`/`model`: free text ≤ 80;
  - `from`/`to`: wall-clock ms of the first and last event; `kind`: `crash`, `error` or `sync`; `text` ≤ 4 000;
  - `n`: how many times the same `kind` + `text` happened since the last report (optional, 1 when absent; `at` is
    the latest time);
  - no plant data, no passwords, no names beyond the device's label.

  At most one report per device per 6 hours, only with events not reported before, and at most 32 KB of plaintext
  (the oldest events are dropped first).
- Replay checks the body (§9a) and keeps reports opaquely by device (§14 `reports`); only a holder of the report key
  opens them.

## 14. Replay output

The state is a JSON object:
- `root` (the current root key string);
- `manager` (person ID);
- `settings` (including `plant` from the genesis);
- `backup_key` (key string or null);
- `persons {person: {username, full_name, position, role}}`;
- `devices {device: {person, label, cut}}`: `cut` = last valid seq or null; `label` is `""` for genesis/root-certified
  devices;
- `equipment {kks: {field: value}}`;
- `reviews {tag_id: data}`;
- `links [[proc, step, kks]]` (sorted);
- `photos {photo: {kks, blob, caption}}`;
- `added_tags {tag: {sheet, bbox, kks, suffix, isa, note}}`;
- `proposals {entry: pending|approved|rejected}`;
- `conflicts [...]` (in the order they happened);
- `votes {entry: [person IDs, sorted]}` (non-empty only);
- `private {person: [entry IDs in order]}`;
- `reports {device: [entry IDs in order]}`, present only when there is at least one report (§13a);
- `ignored {entry: code}`;
- `imported` (the §21 `v1` hash or null).

**State encoding** = §1 canonical JSON, except that object keys may be any printable ASCII string of 1–64 characters.
Two implementations given the same entries, in any order, must produce the same state bytes.

## 15. Sync between two devices

**Connection:** any byte stream: TCP on the same network, the relay pipe or reliable UDP (§18).

**TLS profile (0017)**, using the platform's TLS stack:
- **Versions:** TLS 1.3. TLS 1.2 only where the platform has no 1.3 (Windows 10), and then only
  ECDHE-ECDSA-AES128-GCM-SHA256 or ECDHE-ECDSA-AES256-GCM-SHA384. No RSA, no CBC, no compression, no renegotiation, no
  session resumption.
- **ALPN:** `kks-sync/2`. The connecting side is the TLS client.
- **Mutual authentication:** both sides present an X.509 certificate whose subject public key is their **device key**
  (P-256), and the server requires the client's.
  - The certificate may be self-signed. Its names, dates and extensions are **ignored**; only the public key counts.
    The platform's default certificate-authority validation is replaced by our check (every platform allows a custom
    trust decision).
  - TLS's CertificateVerify proves that each side holds its private key, so the session is bound to both peer IDs
    (peer ID = §2 hash of the certificate's key).
- **The trust decision:**
  - The client accepts the server when the server's peer ID is the one it meant to reach: from mDNS TXT `peer`, an
    invite, a remembered address, or the relay.
  - Both sides then apply the §15 exchange rules. A stranger completes TLS but gets `denied`.

**Framing:** every application message is a 4-byte big-endian length + that many bytes of UTF-8 JSON, at most 64 MiB.

**Exchange:** every application message is an object with `t`. The initiator speaks first at every step; the
responder answers. `{"t":"error","why":...}` may be sent instead of any message, then the connection closes.

1. **`hello`** both ways: `{"t":"hello", "v":2, "root": <trust anchor or null>, "vv": {<device>: [<last seq>, <entry ID
   of that entry>]}}`.
   - Different non-null roots: stop (different plants).
   - A device with no plant yet (`root` null) continues only if the other side's root is the one it was told to join
     (§16 or the server enrolment).
2. **`entries`:** `{"t":"entries", "entries":[...], "denied": true?, "revoked"?: <entry>}`. The initiator sends first;
   the responder decides what to send only after taking in the initiator's entries.
   - **What to send:**
     - every stored entry with seq above the other side's `vv` for its device;
     - for a device whose entry at the other side's last seq has a different ID than ours, that device's whole chain;
     - all fork evidence held.
   - **Nothing** (`denied`) unless the other side is a certified, unrevoked device of a known person in our replay.
   - When it is denied because it was **revoked**, the message carries `"revoked"`: the revoke entry that cut it. The
     removed device checks that entry against its own log and only then wipes its plant data (0020 storage key
     included). The entry must:
     - verify;
     - be of type `revoke`;
     - name this device in `body.device`;
     - have an author that is certified and not revoked there, and is an admin, the manager, or a device of the same
       person.
3. **Taking entries in:**
   - verify each entry (§3);
   - replay with the batch to see which devices are certified by then, and keep only entries of those devices;
   - per device, continue the stored chain in seq order;
   - a valid entry for a (device, seq) already held with a different ID is **fork evidence**.
4. **`want`** both ways: `{"t":"want", "blobs":[<sha256 hex>...]}`: blobs referenced by the log (photos, plant data
   §19) that the sender lacks.
5. **Blobs**, initiator first: `{"t":"blob", "sha":..., "data": <standard base64>}` per wanted blob held, then
   `{"t":"blobs_end"}`.
   - Nothing unless the other side may read.
   - A receiver accepts a blob only if its log references that hash and the bytes hash to it.
6. **`bye`** both ways.

Relaying is automatic: a device sends every entry it holds, not only its own.

## 16. Join by invite (QR code)

**Invite:**
- An admin's device makes `{"kks_invite":2, "plant": <name>, "root": <trust anchor>, "peer": <the device ID that
  answers>, "addrs": ["<ip>:<port>", ...], "token": <16 random bytes, base64url>, "exp": <unix seconds>}`.
- It shows the invite's compact JSON as a QR code, and as text to copy.
- The invite is kept in memory only, is valid for 15 minutes, and serves one device.

**Asking:**
- The new device connects to one of `addrs` with TLS (§15), and stops unless the server's peer ID equals `peer`.
- Instead of `hello`, it sends `{"t":"join", "token":..., "request": <join request>}`.
- **Join request:** `{kks_join:2, device, key, username, full_name, position, label, created, sig}`.
  - `key` is the new device's key, and `device` its peer ID.
  - `sig` is by that key over `"kks-join-v2\n"` + the canonical bytes of the rest.
  - The request's `device` must be the TLS session's client peer ID.
- The answer is one `{"t":"join_ack", "state": ..., "why"?: ...}`: `waiting`, `accepted` (also carries `root` and
  `plant`), `refused`, `used`, `unknown`, or `bad`. Then the connection closes.
- The new device asks again every 2 s while `waiting`. Once `accepted`, it syncs (§15) with the same address, adopting
  the invite's `root`.

**Through a server (enroll):** for a person who has an account on the plant's server.
- The new device connects to the server's sync port with TLS (§15). It cannot pin the server's peer ID yet: trust on
  first use. TLS still keeps the password away from anyone listening on the network. This replaces v1's HTTP
  `/api/devices/enroll`, which sent the password in clear text on the plant LAN. Android forbids clear text by
  default, and N1 wants encryption end to end.
- Instead of `hello`, it sends `{"t":"enroll", "username", "password", "request": <join request>}`. The join
  request's `device` must be the TLS client's peer ID.
- **The server:**
  - checks the password (with the same throttling as sign-in);
  - certifies the device for that person with a `device_cert` from the person's custodial key. Refused when the
    device belongs to someone else or was removed.
- **The answer** is one `{"t":"enroll_ack", "state": "accepted"|"refused"|"bad", "why"?, "root"?, "plant"?}`. Then the
  connection closes.
- **Once accepted,** the device syncs (§15) with the same address, adopting `root`. From then on it pins the
  server's peer ID, as seen on this connection.

**Without an invite:**
- Devices announce on mDNS: service `_kks._tcp`, TXT `peer`, `root` (the first 16 characters of the root ID), `plant`,
  `label`, `adm`, `v=2`.
- The new device asks a device with `"token": null`, and the request waits in that device's lobby (at most 50, 15
  minutes).
- **Both screens show a 6-digit code:** the first 4 bytes of SHA-256(`"kks-join-code-v2\n"` + joiner peer ID + `"\n"`
  + answering peer ID), big-endian, mod 1 000 000, zero-padded.
- The admin accepts only if the code matches the new person's screen. The new device syncs only after its person
  confirmed that the admin's screen shows the same code.
- Username and admin rules as in v1: an existing username needs the admin's explicit OK, and only the manager adds
  devices for admins.

## 17. Person secrets between a person's own devices

- After a normal sync with a device of the same person, the initiator opens a new TLS connection (§15), checks that the
  server is the device it synced with, and sends `{"t":"secrets", "person": <person ID>, "secrets": [<32 bytes,
  base64url>, …]}` instead of `hello`.
- The responder answers `{"t":"secrets", "secrets": [...]}` with every secret it holds for that person, and takes the
  initiator's, **only if** all of these hold:
  - it is a device of that person itself;
  - the client is certified to the same person and not revoked;
  - `person` names that person.

  Otherwise it answers an empty list and keeps nothing.
- At most 16 secrets per message.
- Every device keeps all secrets it has, tries each when opening a private entry, and writes with the one whose
  SHA-256 (hex) sorts first.
- A server is nobody's own device: it holds no person secret and always answers an empty list.

**Course progress body** (inside the encryption): `{"type":"course_progress", "body":{"course": [a-z]{1,16},
"items": [[key, value], …]}}`.
- `key`: `[A-Za-z0-9_.-]{1,64}`; `value`: a JSON text.
- Reading merges per key in replay order:
  - two JSON objects → their union (later keys win);
  - keys ending in `Best` with two numbers → the larger;
  - otherwise → the later value.

## 18. Sync across the internet (relay, hole punching, reliable UDP)

This section only provides a byte stream; §15 (TLS and exchange) runs over it unchanged.

**Relay address:** a `setting` (manager only) with key `relay`, value `ws[s]://host[:port][/path]` without a trailing
`/`, or null = off.

**Room:**
- One per plant: room = the first 32 hex characters of SHA-256(`"kks-relay-room-v2\n"` + root ID).
- A device opens a WebSocket to `<relay>/v1/room/<room>` and first sends `{"t":"hello", "peer", "key", "ts", "sig"}`,
  where `sig` is by the device key over `"kks-relay-hello-v2\n"` + room + `"\n"` + ts.
- The relay checks that `peer` is the key's peer ID, the signature, and |ts − now| ≤ 300 s. Then:
  - it answers `{"t":"welcome", "peers": [...]}`;
  - it tells the others `{"t":"joined", "peer"}`, and `{"t":"left", "peer"}` when the device leaves.
- A second hello for the same device replaces the older socket. A bad hello, or more than 200 devices: `error` and
  close.
- `ping` after 25 s of silence, answered by `pong`.

**Signaling:**
- `{"t":"connect", "to", "id": <32 hex>, "cand": [...]}`, `{"t":"accept", "to", "id", "cand": [...]}`, and
  `{"t":"refuse", "to", "id"}`.
- The relay adds `from`, or answers `{"t":"gone", "id", "peer"}`.
- `cand`: at most 8 `"ip:port"` strings (STUN public address plus own IPv4 addresses), each at most 64 characters.
- `cand` may be empty: a device that does not do hole punching (no UDP, or a platform without it yet) sends `[]`.
  When either side's list is empty, both skip the direct path and open the pipe at once (added 2026-10-02: the v2
  apps start with the pipe only).

**Direct: hole punching + reliable UDP**, exactly as in v1 §18 (0028):
- Session = the first 8 bytes of `id`.
- Datagram = type (1 byte) + session (8 bytes) + body. Types: PUNCH 1, PUNCH_ACK 2, DATA 3 (seq u32 + ≤ 1150 bytes),
  ACK 4 (next u32 + mask u32), FIN 5, PING 6.
- Window from 8 up to 256; RFC 6298 RTO 200 ms–4 s; fast retransmit after 3; halve once per window; `dead` 15 s.

**Fallback pipe:**
- `<relay>/v1/pipe/<room>/<id>/<a|b>`; `a` is the initiator.
- Messages sent before the other side arrives are held, 1 MiB at most. An unpaired pipe closes after 30 s. The pipes
  close together.

**Then** the initiator runs §15 (TLS client) over the stream, checking that the server's peer ID is the device it
asked for.

## 19. Plant data and course content

A published version is a `setting` (manager only), key `plant_data`, value `{"version": <int ≥ 1>, "files": [[<path>,
<SHA-256 hex>, <size>], …]}`.
- At most 5000 files; no path twice.
- **Paths:** `(sheets/|courses/)?[a-z0-9][a-z0-9._-]{0,63}`, without `..`.
- The newest valid setting in replay order is the latest version. Devices show the newest version they hold
  **completely**, and never mix versions.

**File kinds:**
- `sheets.json`, `tags.json`, `procedures.json`, `locations.json` (JSON, as in v1);
- `sheets/<id>.pdf`: the original drawing, the source of record;
- `sheets/<id>.kkp`: the **grid-indexed path store** (0015; format: docs/PATHSTORE.md);
- `sheets/<id>.o<k>.jxl`: overview pyramid level k = 0, 1, … (lossless JPEG XL, 0016, 0018);
- `courses/<course>.json`: course content (0025; format: docs/COURSES.md);
- `courses/<file>.jxl`: course images.

Every file is a blob (§15 steps 4–5).

## 20. Encryption to a key (ECIES)

Used for backups (0020, to the `backup_key`) and for the root key backup file:
- The sender makes an ephemeral P-256 key pair E, and computes the ECDH shared secret with the recipient key R (the
  32-byte x coordinate).
- `k = HKDF-SHA256(ikm = shared, salt = E's 65-byte public key ‖ R's 65 bytes, info = ASCII "kks-ecies-v2\n" +
  purpose, 32 bytes)`.
- The ciphertext = AES-256-GCM(k, a 12-byte random nonce, plaintext, associated data = purpose).
- Encoded as the object `{"v":2, "purpose", "epk": <E key string>, "nonce", "ct"}`.

The root key backup is instead protected by a passphrase (0023): PBKDF2-HMAC-SHA256, at least 600 000 iterations, a
16-byte salt, then AES-256-GCM (12-byte nonce, associated data ASCII `kks-root-backup-v2\n`). Object: `{"v":2,
"kdf":"pbkdf2-sha256", "iter", "salt", "nonce", "ct"}`.

## 21. Migration from v1 (one time)

Done once by the manager with the migration tool (0024):
1. **Read and check v1.** Read the v1 log and verify it completely under v1 rules. Abort on any difference from the
   live v1 state. Abort if any proposal is still pending: the manager decides them first.
2. **Archive v1.** v1 archive hash H = lowercase hex SHA-256 of the canonical JSON of the list of all v1 entry IDs, in
   v1 total order. The v1 log is archived read-only, with H.
3. **Build the imported state.** It is taken from the v1 replay state:
   - `persons` (with roles);
   - `settings` without `plant` (the genesis carries it);
   - `equipment`, `reviews`, `links`, `photos`, `added_tags`.

   **Pair form:** the state is keyed by IDs and KKS codes, which §1 object keys don't allow, so each map is written as
   a list of `[key, value]` pairs, **sorted by key** (code point) with no key twice (otherwise `bad_genesis`):
   `{"persons": [[person, {username, full_name, position, role}], …], "settings": [[key, value], …], "equipment":
   [[kks, {field: value}], …], "reviews": [[tag_id, data], …], "links": [[proc, step, kks], …] (sorted, no
   duplicates), "photos": [[photo, {kks, blob, caption}], …], "added_tags": [[tag, {sheet, bbox, kks, suffix, isa,
   note}], …]}`. This is ordinary canonical JSON (§1).
   - Each item must pass §9a. Devices, proposals, conflicts, votes, private entries and ignored entries are **not**
     imported. Everyone re-joins. Private data travels again between a person's own devices, since the person secrets
     are unchanged.
4. **Write the v2 genesis.** A new P-256 root key signs:
   - `manager`;
   - `device` (the manager's new device);
   - `import` = `{"kind":"import", "v1": H, "state": <hex SHA-256 of the canonical imported state>}`.

   The genesis carries `import: {stmt, root_sig, state}`.
5. **Replay applies the import at the genesis.** Imported persons exist with their roles, but have no devices.
   Imported values count as set by nobody for §12.
   - The genesis `manager` person may also be in the imported `persons`, with the same ID. The genesis values then
     replace the imported ones for that person.
   - Any other imported person with the manager's username (ignoring ASCII case) makes the genesis `bad_genesis`.
   - If the state's hash doesn't match `stmt.state`, or any item breaks §9a: the genesis is `bad_genesis`.

Photos keep their blob hashes, so photo files move over unchanged.

## 21a. Moving v1 devices (added 2026-10-03, decision 0042; retired 2026-10-05, decision 0048)

**Retired.** No implementation answers `succession` or `migrate` any more, servers no longer announce TXT `prev` or
join the v1 room, and the relay accepts only v2 hellos. A v1 device joins like any new device (§16). The text below
is kept as the record of what ran from 2026-10-03 to 2026-10-05.

A v1 device moves to a new v2 device of the same person, without an admin. The v1 app proves the old device's
identity with its v1 key and hands over its open changes; the new device writes them as its own entries. v1 IDs,
keys and canonical bytes below are v1's (PROTOCOL.md §1–2): a v1 peer ID or root ID is the base64url Ed25519 public
key, and signatures are Ed25519, in base64url.

**Made at the migration** by the migration tool, which holds the v1 log and the v1 root key, after the v2 genesis:

- **v1 device table:** `[[v1 device, {person, revoked, seq, server}], …]` sorted by device.
  - `person`: the person the v1 log certified it for.
  - `revoked`: true when any v1 `revoke` names it.
  - `seq`: the highest seq of that device in the archive (0 if none).
  - `server`: true for the v1 server's own keys (one per account), which never move.
  - It is kept by the v2 server only. It is not in the log.
- **Succession statement:**
  - `stmt` = `{"kind":"succession", "v1_root", "v1": H (§21), "v2_root", "server": <the v2 server's peer ID>,
    "archived": [[v1 device, seq], …] (sorted, one per device in the table)}`;
  - `sig` = signed by the v1 root key over `"kks-succession-v1\n"` + v1-canonical(stmt).

**On the server's sync port (TLS, §15).** As with `enroll`, the connecting device can't pin the server yet. Trust
comes from the statement instead.

- **Asking for the statement:** `{"t":"succession"}` instead of `hello` → `{"t":"succession", "stmt", "sig"}`, or
  `{"t":"succession", "stmt": null}` from a node that holds none. The asker checks:
  - `sig` against the v1 root it already trusts;
  - that the TLS server's peer ID equals `stmt.server`.

  The asker drops the statement if either check fails.
- **The proof**, made by the v1 device after it has checked the statement:
  - `{"kks_migrate":1, "v1_root", "v1_device", "v2_root", "device", "key", "label", "created", "sig"}`;
  - `device` and `key` are the new v2 device's peer ID and key (§2);
  - `sig` = signed by the v1 device key over `"kks-migrate-v1\n"` + v1-canonical(the rest).
- **Moving:** `{"t":"migrate", "proof"}` instead of `hello`, on a connection pinned to `stmt.server` →
  `{"t":"migrate_ack", "state": "accepted"|"refused"|"bad", "why"?, "root"?, "plant"?}`. Then the connection
  closes.
- **The server accepts** only if all of these hold:
  - `device` is the TLS client's peer ID, and `key` hashes to `device`;
  - `v1_root` and `v2_root` are its own;
  - `v1_device` is in its table and not revoked;
  - `sig` verifies;
  - `v1_device` hasn't moved before, unless to this same `device`, which is accepted again.

  It then certifies `device` for the table's person with a `device_cert` (label = the proof's `label`). It signs
  with the person's custodial key if the person has an account on the server, else with the manager's. Once
  accepted, the device syncs (§15) with the same address, adopting `root`.

**Finding the server:**
- the v1 device's remembered sync addresses (the v2 server keeps v1's sync port);
- mDNS TXT `prev` = the first 16 characters of the v1 root ID;
- the relay: the server is also present in the v1 room, first 32 hex characters of SHA-256(`"kks-relay-room-v1\n"` +
  v1 root ID), with its v2 hello. The relay accepts v2 hellos in any room. A v2 peer ID (32 characters) tells it
  apart from v1 devices (43).

**The changes handed over** are the v1 device's own entries with seq > its `archived` seq whose type is
`equipment`, `review`, `link`, `photo`, `photo_delete` or `tag_add`/`tag_remove`, and that are still open in the
v1 device's view: pending, or applied directly (an admin's). Withdrawn, rejected and ignored entries are left out.
- The new device writes each one as a new v2 entry with the same body (§9 bodies are unchanged from v1), plus the
  author's own `comment` on it if there was one. Photo blobs keep their hashes.
- It keeps the v1 entry IDs it has written, so it never writes one twice.
- Its role decides as usual whether a change is a proposal (§10).
