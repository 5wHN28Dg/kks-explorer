# 0050 Relay room key: only the plant's devices enter its room

Date 2026-10-08 · Scope: PROTOCOL-v2 §15, §18; core (`extras`, `relaykey`, `sync`, `api`), the Linux/Windows relay
client (`kksl/internet.nim`), Android (`kks_jni.nim`, `sync/Internet.kt`), the server, `relay/` (Worker and twin),
`ref/` and the vectors · Status: **decided by the user** (2026-10-08, issue #30: "room token … the relay admits only
holders … the old devices can't use the relay until updated (LAN sync unaffected)")

**Question:** the relay admits any P-256 key into a plant's room (#30). Anyone who knows the room (a removed device, a
past invite holder, anyone who saw the root ID) can see who is online, signal devices, or fill the room to its 200
places. How does the relay tell the plant's devices from everyone else, without learning the plant's secrets and
without reading the log?

## Findings

| | Fact | Source |
|---|---|---|
| What the relay knows | Only the room name and the hello. It has no log, so it can't check a `device_cert` | `relay/src/index.js` |
| What a device statement would need | A root-signed pass per device (with an expiry, for revocation) needs the root key online to renew it. Plants without an always-on root holder would lose the relay when passes expire | PROTOCOL-v2 §8 |
| Changing `device_cert` | A body has exactly its listed fields (§9); an extra field is `bad_body` on every device that isn't updated, so their certificates would stop counting | PROTOCOL-v2 §9 |
| A new `setting` | Any key, any JSON value, manager only: old devices store and ignore it, and the replay rules don't change | PROTOCOL-v2 §9, §9a |
| A secret between two devices | §15 runs inside mutually authenticated TLS. Extra fields in `entries` are ignored by older devices (they read only `entries`, `denied`, `revoked`) | `core/src/kks/sync.nim` takeEntries |
| Deriving a key pair from a secret | Needs scalar multiplication. GnuTLS can't import a bare scalar, so each provider would need new EC code. A generated key pair travels as scalar + public point instead | CLAUDE.md lessons (GnuTLS), `crypto.nim` `PrivateKey` |

## Choice

- **The room key:** a P-256 key pair per plant. Its public key is the manager setting `relay_member` (a key string, or
  null). Its private key is held by every certified device.
- **How it travels:** in §15's `entries` message, as `"relay_member": {"key", "scalar"}`. It is sent only to a side
  the sender serves (`mayRead`: certified, not revoked), so it arrives at a device's first sync after its certificate.
  A receiver keeps it only if `key` equals its current `relay_member` setting and the scalar signs for that key. It is
  stored in the sealed store (meta `relay_member`) and wiped with the plant data.
- **Room** = the first 32 hex characters of SHA-256(`"kks-relay-room-v3\n"` + the room key's peer ID).
- **Hello** adds `member` (the room key) and `msig`: the room key's signature over `"kks-relay-member-v3\n"` + room +
  `"\n"` + peer + `"\n"` + ts.
  - The relay checks that the room is the one `member` gives, and checks both signatures.
  - It learns only a public key. It can't make a hello itself, and it can't read anything.
  - A hello without a valid member proof gets `{"t":"error","why":"the plant's relay key is missing: update the app"}`.
- **Rotation:** a new room key every time the manager saves a relay address, and every time a manager's device
  removes a device or deactivates a person. The room moves with it. A removed device is denied every sync, so it
  never learns the new key.
  - An admin's removal can't write settings, so it doesn't rotate. The removed device can then still enter the room
    until the next rotation, though it still gets nothing from any sync. The manager rotates by saving the relay
    again.
- **Grace period:** a device keeps the key it held before a rotation for 7 days. The server stays in that previous
  room meanwhile, besides the new one. A device that reaches the plant only through the relay (a phone on mobile
  data) can then still sync once with the server, learn the new key and move. The other devices leave the old room at
  once.
- **Old devices:** without the room key, the relay refuses them. LAN sync is unaffected. After updating, the manager
  saves the relay once; until then no device has a room key and nobody is online through the relay.

**Costs:**
- every device that holds the room key could let an outsider into the room until the next rotation. That device is a
  certified member, so it could hand out plant data anyway;
- one extra field per `entries` message;
- the relay must be redeployed (the user does that), and all apps updated before the relay is used again.

## When to revisit

- if presence must be cut at once for an admin's removal (give admins rotation, or the relay a revocation list);
- if the relay ever gets the log (then it could check certificates itself).

Sources: `core/src/kks/sync.nim`, `core/src/kks/api.nim` (`/api/settings/relay`, `revokeDevice`), `relay/src/index.js`,
`relay/twin.py`, PROTOCOL-v2 §8–§9a, §15, §18.
