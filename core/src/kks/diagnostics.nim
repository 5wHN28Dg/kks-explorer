## Diagnostics reports (PROTOCOL-v2 §13a, decision 0040): a device keeps the errors, crashes and sync failures it saw
## and, while the manager has reports switched on, seals them to the manager's report key in a `report` entry. The
## manager's own devices hold the report key (a private entry, §13) and open the reports. Platform code only calls
## `record` and `maybeReport`; everything else is here.

import std/[algorithm, strutils, tables]
import json, crypto, util, proto, replay, node, progress, extras

const
  Interval* = 6 * 3600 * 1000'i64   ## at most one report per device in this long
  MaxPlain = 32 * 1024
  MaxEvents = 200
  MaxText = 4000
  EventsKey = "diag_events"
  LastKey = "diag_last"

proc diagnosticsKey*(n: Node): string =
  ## the report key while the manager has reports on, else ""
  if n.run == nil: return ""
  let v = n.run.settings.getOrDefault("diagnostics")
  if v != nil and v.kind == jObj and v.get("key") != nil and v["key"].isStr: v["key"].s else: ""

proc pending*(n: Node): JNode =
  let raw = n.store.getMeta(EventsKey)
  if raw.len == 0: return newArr()
  try: parseStrict(raw) except JsonError: newArr()

proc record*(n: Node, kind, text: string, wall: int64) =
  ## Keep one event for the next report: `kind` crash, error or sync. The same kind + text again only counts up.
  ## Kept whether reports are on or not (the newest 200), so switching them on also sends what came before.
  if kind notin ["crash", "error", "sync"]: return
  let t = if text.len > MaxText: text[0 ..< MaxText] else: text
  var a = n.pending
  for ev in a.elems:
    if ev["kind"].s == kind and ev["text"].s == t:
      ev["at"] = newInt(wall)
      ev["n"] = newInt((if ev.get("n") != nil: ev["n"].i else: 1) + 1)
      n.store.setMeta(EventsKey, toText(a))
      return
  a.elems.add newObj(@[("at", newInt(wall)), ("kind", newStr(kind)), ("text", newStr(t)), ("n", newInt(1))])
  while a.elems.len > MaxEvents: a.elems.delete(0)
  n.store.setMeta(EventsKey, toText(a))

proc maybeReport*(n: Node, app, version, platform, model: string, wall: int64, force = false): bool =
  ## Write a report if reports are on, there is something new, and the last one is 6 h old (or `force`). -> written
  let key = n.diagnosticsKey
  if key.len == 0 or n.owner.len == 0: return false
  let last = try: parseBiggestInt(n.store.getMeta(LastKey)) except ValueError: 0'i64
  if not force and wall - last < Interval: return false
  var events = n.pending
  if events.elems.len == 0: return false
  proc clip(s: string): string = (if s.len > 80: s[0 ..< 80] else: s)
  var plain: JNode
  while true:
    plain = newObj(@[("device", newStr(n.device)), ("app", newStr(app)), ("version", newStr(clip(version))),
                     ("platform", newStr(clip(platform))), ("model", newStr(clip(model))),
                     ("from", newInt(events.elems[0]["at"].i)), ("to", newInt(events.elems[^1]["at"].i)),
                     ("events", events)])
    if canonical(plain).len <= MaxPlain or events.elems.len == 1: break
    events.elems.delete(0)                       # the oldest go first
  let sealed = n.p.eciesSeal(key, "kks-report", canonical(plain).toBytes)
  discard n.append("report", newObj(@[("sealed", sealed)]), wall)
  n.store.setMeta(EventsKey, "[]")
  n.store.setMeta(LastKey, $wall)
  true

proc isManagerDevice(n: Node): bool = n.run != nil and n.owner.len > 0 and n.owner == n.run.manager

proc enable*(n: Node, wall: int64) =
  ## The manager switches reports on from one of their own devices: a new report key, kept in a private entry only
  ## the manager's devices open, and the public half as the setting. Raises ValueError when not allowed here.
  if not n.isManagerDevice: raise newException(ValueError, "Only the manager can switch diagnostics reports on.")
  let me = n.owner
  let k = n.p.p256Generate()
  let keyStr = keyString(k.pub)
  let body = newObj(@[("key", newStr(keyStr)), ("private", newStr(b64u(k.scalar)))])
  discard n.append("private", n.p.privateBody(n.ensureSecret(me), me, "report_key", body), wall)
  discard n.append("setting", newObj(@[("key", newStr("diagnostics")), ("value", newObj(@[("key", newStr(keyStr))]))]), wall)

proc disable*(n: Node, wall: int64) =
  if not n.isManagerDevice: raise newException(ValueError, "Only the manager can switch diagnostics reports off.")
  discard n.append("setting", newObj(@[("key", newStr("diagnostics")), ("value", newNull())]), wall)

proc reportKeys(n: Node): seq[PrivateKey] =
  ## the report keys this device can open (the manager's private report_key entries)
  if not n.isManagerDevice or n.owner notin n.run.private: return
  let secrets = n.secretsOf(n.owner)
  for id in n.run.private[n.owner]:
    let e = n.entries.getOrDefault(id)
    if e == nil: continue
    for s in secrets:
      try:
        let o = n.p.privateOpen(s, e["body"])
        if o.get("type") != nil and o["type"].isStr and o["type"].s == "report_key":
          let b = o["body"]
          result.add PrivateKey(scalar: unb64u(b["private"].s), pub: unb64u(b["key"].s))
        break
      except CatchableError: discard

proc canRead*(n: Node): bool = n.reportKeys.len > 0

proc readReports*(n: Node): JNode =
  ## Every report this device can open, newest first: {entry, device, label, username, at, report} (report = the
  ## plaintext, or null when no key here opens it).
  result = newArr()
  if n.run == nil: return
  let keys = n.reportKeys
  var rows: seq[(int64, JNode)]
  for dev, ids in n.run.reports:
    let d = n.run.devices.getOrDefault(dev)
    let label = if d != nil: d["label"].s else: ""
    let person = if d != nil: d["person"].s else: ""
    let p = n.run.persons.getOrDefault(person)
    let username = if p != nil: p["username"].s elif person == n.run.manager: "manager" else: ""
    for id in ids:
      let e = n.entries.getOrDefault(id)
      if e == nil: continue
      var rep = newNull()
      for k in keys:
        try:
          rep = parseStrict(n.p.eciesOpen(k, e["body"]["sealed"]).toStr)
          break
        except CatchableError: discard
      let at = e["hlc"][0].i
      rows.add((at, newObj(@[("entry", newStr(id)), ("device", newStr(dev)), ("label", newStr(label)),
                             ("username", newStr(username)), ("at", newInt(at)), ("report", rep)])))
  rows.sort(proc (a, b: (int64, JNode)): int = cmp(b[0], a[0]))
  for (_, r) in rows: result.elems.add r
