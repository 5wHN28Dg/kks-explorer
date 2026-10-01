## Protocol v2 pieces outside the log (docs/PROTOCOL-v2.md §16 join, §18 relay, §20 encryption to a key).
## A port of ref/crypto2.py.

import std/strutils
import json, crypto, util, proto

const Pbkdf2MinIter* = 600_000

# ---------------------------------------------------------------- §16 join

proc joinCode*(p: Provider, joinerPeer, answeringPeer: string): string =
  let d = p.sha256(toBytes("kks-join-code-v2\n" & joinerPeer & "\n" & answeringPeer))
  let n = (uint32(d[0]) shl 24) or (uint32(d[1]) shl 16) or (uint32(d[2]) shl 8) or uint32(d[3])
  align($(n mod 1_000_000), 6, '0')

proc joinRequest*(p: Provider, key: PrivateKey, username, fullName: string, position: JNode, label: string,
                  created: int64): JNode =
  result = newObj(@[("kks_join", newInt(2)), ("device", newStr(p.peerId(key))), ("key", newStr(keyString(key.pub))),
                  ("username", newStr(username)), ("full_name", newStr(fullName)), ("position", position),
                  ("label", newStr(label)), ("created", newInt(created))])
  result["sig"] = newStr(p.sign(key, "kks-join-v2\n" & canon(result)))

proc checkJoinRequest*(p: Provider, req: JNode): bool =
  ## True if the request is well formed and signed by its own key, whose peer ID is `device`.
  try:
    if req.kind != jObj: return false
    let kj = req.get("kks_join")
    if kj == nil or kj.kind != jInt or kj.i != 2: return false
    let key = req["key"]
    let dev = req["device"]
    let sig = req["sig"]
    if not (key.isStr and dev.isStr and sig.isStr): return false
    if p.peerIdOfKey(key.s) != dev.s: return false
    p.verify(key.s, "kks-join-v2\n" & canon(unsignedCopy(req)), sig.s)
  except CatchableError:
    false

# ---------------------------------------------------------------- §18 relay

proc relayRoom*(p: Provider, rootKeyStr: string): string =
  hex(p.sha256(toBytes("kks-relay-room-v2\n" & p.peerIdOfKey(rootKeyStr))))[0 ..< 32]

proc helloBytes(room: string, ts: int64): string = "kks-relay-hello-v2\n" & room & "\n" & $ts

proc relayHello*(p: Provider, key: PrivateKey, room: string, ts: int64): JNode =
  newObj(@[("t", newStr("hello")), ("peer", newStr(p.peerId(key))), ("key", newStr(keyString(key.pub))), ("ts", newInt(ts)),
         ("sig", newStr(p.sign(key, helloBytes(room, ts))))])

proc checkRelayHello*(p: Provider, h: JNode, room: string, now: int64, skew = 300'i64): bool =
  try:
    let key = h["key"]
    let ts = h["ts"]
    if not (key.isStr and ts.kind == jInt and h["peer"].isStr and h["sig"].isStr): return false
    p.peerIdOfKey(key.s) == h["peer"].s and abs(ts.i - now) <= skew and
      p.verify(key.s, helloBytes(room, ts.i), h["sig"].s)
  except CatchableError:
    false

# ---------------------------------------------------------------- §20 encryption to a key

proc eciesKey(p: Provider, shared: Digest, ephPub, recipientPub: openArray[byte], purpose: string): seq[byte] =
  p.hkdfSha256(shared, @ephPub & @recipientPub, toBytes("kks-ecies-v2\n" & purpose), 32)

proc eciesSeal*(p: Provider, recipientKeyStr, purpose: string, plain: openArray[byte],
                eph = PrivateKey(), nonce: seq[byte] = @[]): JNode =
  ## `eph` and `nonce` are for vectors; normally both are fresh.
  let e = if eph.pub.len == 0: p.p256Generate() else: eph
  let n = if nonce.len == 0: p.randomBytes(12) else: nonce
  let rpub = p.publicKey(recipientKeyStr)
  let k = p.eciesKey(p.p256Ecdh(e, rpub), e.pub, rpub, purpose)
  let ct = p.aesGcmSeal(k, n, plain, purpose.toBytes)
  newObj(@[("v", newInt(2)), ("purpose", newStr(purpose)), ("epk", newStr(keyString(e.pub))), ("nonce", newStr(b64u(n))),
         ("ct", newStr(b64u(ct)))])

proc eciesOpen*(p: Provider, recipient: PrivateKey, obj: JNode): seq[byte] =
  let epub = p.publicKey(obj["epk"].s)
  let purpose = obj["purpose"].s
  let k = p.eciesKey(p.p256Ecdh(recipient, epub), epub, recipient.pub, purpose)
  p.aesGcmOpen(k, unb64u(obj["nonce"].s), unb64u(obj["ct"].s), purpose.toBytes)

const BackupAad = "kks-root-backup-v2\n"

proc passphraseSeal*(p: Provider, passphrase: string, plain: openArray[byte], iterations = Pbkdf2MinIter,
                     salt: seq[byte] = @[], nonce: seq[byte] = @[]): JNode =
  if iterations < Pbkdf2MinIter: raise newException(ValueError, "at least 600000 iterations (decision 0023)")
  let s = if salt.len == 0: p.randomBytes(16) else: salt
  let n = if nonce.len == 0: p.randomBytes(12) else: nonce
  let k = p.pbkdf2Sha256(passphrase.toBytes, s, iterations, 32)
  let ct = p.aesGcmSeal(k, n, plain, BackupAad.toBytes)
  newObj(@[("v", newInt(2)), ("kdf", newStr("pbkdf2-sha256")), ("iter", newInt(iterations)), ("salt", newStr(b64u(s))),
         ("nonce", newStr(b64u(n))), ("ct", newStr(b64u(ct)))])

proc passphraseOpen*(p: Provider, passphrase: string, obj: JNode): seq[byte] =
  if obj["kdf"].s != "pbkdf2-sha256" or obj["iter"].kind != jInt or obj["iter"].i < Pbkdf2MinIter:
    raise newException(ValueError, "unsupported key derivation")
  let k = p.pbkdf2Sha256(passphrase.toBytes, unb64u(obj["salt"].s), int(obj["iter"].i), 32)
  p.aesGcmOpen(k, unb64u(obj["nonce"].s), unb64u(obj["ct"].s), BackupAad.toBytes)
