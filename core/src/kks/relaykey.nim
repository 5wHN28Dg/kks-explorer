## The plant's relay room key (decision 0050, PROTOCOL-v2 §15, §18). The manager setting `relay_member` names its public
## key; certified devices hold the private key (sealed store, meta `relay_member`), get it inside §15's `entries` from
## a device that serves them, and present a hello signed by it to the relay.

import std/tables
import json, crypto, util, proto, node, replay

const
  MetaKey = "relay_member"
  PrevKey = "relay_member_prev"
  GraceMs* = 7'i64 * 86_400_000   ## how long an always-on node stays in the previous room after a rotation

proc relayMemberSetting*(n: Node): string =
  ## the current room key (a key string), "" = none
  if n.run == nil: return ""
  let v = n.run.settings.getOrDefault("relay_member")
  if v != nil and v.isStr: v.s else: ""

proc keyFits(p: Provider, k: PrivateKey): bool =
  ## the scalar really belongs to the public key: it signs for it
  try: p.verify(keyString(k.pub), "kks-relay-member-check\n", p.sign(k, "kks-relay-member-check\n"))
  except CatchableError: false

proc memberKey*(n: Node): (bool, PrivateKey) =
  ## the room key this device holds, if it is the plant's current one
  let want = n.relayMemberSetting
  let raw = n.store.getMeta(MetaKey)
  if want.len == 0 or raw.len == 0: return
  try:
    let j = parseStrict(raw)
    if j["key"].s != want: return
    result = (true, PrivateKey(scalar: unhex(j["scalar"].s), pub: unb64u(j["key"].s)))
  except CatchableError:
    discard

proc keepMemberKey*(n: Node, k: PrivateKey, now: int64 = 0) =
  ## the key held before (a rotation) is kept as the previous one until `now` + GraceMs: an always-on node (the server)
  ## stays in that room meanwhile, so a device that reaches the plant only through the relay can still sync once and
  ## learn the new key
  let old = n.store.getMeta(MetaKey)
  if old.len > 0:
    try:
      let j = parseStrict(old)
      if j["key"].s != keyString(k.pub):
        j["until"] = newInt(now + GraceMs)
        n.store.setMeta(PrevKey, toText(j))
    except CatchableError: discard
  n.store.setMeta(MetaKey, toText(newObj(@[("key", newStr(keyString(k.pub))), ("scalar", newStr(hex(k.scalar)))])))

proc prevMemberKey*(n: Node, now: int64): (bool, PrivateKey) =
  ## the room key replaced by the last rotation, while its grace period lasts (and only if it isn't the current one)
  let raw = n.store.getMeta(PrevKey)
  if raw.len == 0: return
  try:
    let j = parseStrict(raw)
    if j["until"].i > now and j["key"].s != n.relayMemberSetting:
      result = (true, PrivateKey(scalar: unhex(j["scalar"].s), pub: unb64u(j["key"].s)))
  except CatchableError:
    discard

proc memberKeyOut*(n: Node): JNode =
  ## the `relay_member` field of an `entries` message, or nil when this device holds no current room key
  let (ok, k) = n.memberKey
  if not ok: return nil
  newObj(@[("key", newStr(keyString(k.pub))), ("scalar", newStr(hex(k.scalar)))])

proc takeMemberKey*(n: Node, m: JNode, now: int64 = 0): bool =
  ## a `relay_member` field received: kept only if it is the log's current room key and the scalar signs for it
  if m == nil or m.kind != jObj or m.get("key") == nil or not m["key"].isStr or m.get("scalar") == nil or
     not m["scalar"].isStr or m["scalar"].s.len != 64: return false
  if m["key"].s != n.relayMemberSetting: return false
  if n.memberKey[0]: return false
  var k: PrivateKey
  try: k = PrivateKey(scalar: unhex(m["scalar"].s), pub: unb64u(m["key"].s))
  except CatchableError: return false
  if k.pub.len != 65 or not n.p.keyFits(k): return false
  n.keepMemberKey(k, now)
  true
