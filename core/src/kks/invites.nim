## Join by invite and the lobby (PROTOCOL-v2 §16), the answering side. In memory only; time comes in as `now`
## (seconds). A port of v1's server/invites.py.

import std/tables
import json, crypto, util, extras

const
  Ttl* = 15 * 60
  LobbyMax = 50

type
  Ask* = object
    by*: string                ## the admin's person ID ("" for the lobby)
    exp*: int64
    state*: string             ## open, asked, accepted, refused, cancelled
    device*: string
    request*: JNode            ## the full, checked join request
    seen*: int64

  Invites* = ref object
    items*: OrderedTable[string, Ask]    ## token → ask
    lobby*: OrderedTable[string, Ask]    ## device → ask (no token)

proc newInvites*(): Invites = Invites()

proc create*(iv: Invites, p: Provider, by, root, plant, peer: string, addrs: seq[string], now: int64): JNode =
  ## -> the invite (what the QR code carries).
  let token = b64u(p.randomBytes(16))
  iv.items[token] = Ask(by: by, exp: now + Ttl, state: "open")
  var a = newArr()
  for x in addrs: a.elems.add newStr(x)
  newObj(@[("kks_invite", newInt(2)), ("plant", newStr(plant)), ("root", newStr(root)), ("peer", newStr(peer)),
           ("addrs", a), ("token", newStr(token)), ("exp", newInt(now + Ttl))])

proc ack(state: string, why = ""): JNode =
  result = newObj(@[("t", newStr("join_ack")), ("state", newStr(state))])
  if why.len > 0: result["why"] = newStr(why)

proc offer*(iv: Invites, p: Provider, remote: string, msg: JNode, now: int64): JNode =
  ## A device asks with a token (or none: the lobby) and its join request. -> the join_ack message.
  let token = msg.get("token")
  let req = msg.get("request")
  proc checked(): string =
    if not p.checkJoinRequest(req): return "the join request is not valid"
    if req["device"].s != remote: return "the join request is not from the device that sent it"
    ""
  if token == nil or token.kind == jNull:
    var gone: seq[string]
    for d, v in iv.lobby:
      if v.exp < now: gone.add d
    for d in gone: iv.lobby.del d
    if remote in iv.lobby:
      let v = iv.lobby[remote]
      if v.state in ["accepted", "refused"]: return ack(v.state)
      iv.lobby[remote].seen = now
      return ack("waiting")
    if iv.lobby.len >= LobbyMax: return ack("used", "too many devices are waiting here; try again later")
    let why = checked()
    if why.len > 0: return ack("bad", why)
    iv.lobby[remote] = Ask(exp: now + Ttl, state: "asked", device: remote, request: req, seen: now)
    return ack("waiting")
  if token.kind != jStr or token.s notin iv.items: return ack("unknown", "this invite was cancelled or never existed here")
  var v = iv.items[token.s]
  if v.state == "cancelled": return ack("unknown", "this invite was cancelled or never existed here")
  if v.device.len > 0 and v.device != remote: return ack("used", "another device is already using this invite")
  if v.state in ["accepted", "refused"]: return ack(v.state)
  if v.exp < now: return ack("unknown", "this invite has expired; ask for a new one")
  if v.state == "asked":
    iv.items[token.s].seen = now
    return ack("waiting")
  let why = checked()
  if why.len > 0: return ack("bad", why)
  iv.items[token.s] = Ask(by: v.by, exp: v.exp, state: "asked", device: remote, request: req, seen: now)
  ack("waiting")

proc pending*(iv: Invites, now: int64): seq[(string, Ask)] =
  ## Requests waiting for an admin: (token or "lobby:" & device, ask).
  for t, v in iv.items:
    if v.state == "asked" and v.exp >= now: result.add((t, v))
  for d, v in iv.lobby:
    if v.state == "asked" and v.exp >= now: result.add(("lobby:" & d, v))

proc decide*(iv: Invites, key: string, accepted: bool, now: int64): JNode =
  ## The admin's answer (the caller has certified the device when accepting). -> the request, or nil.
  let state = if accepted: "accepted" else: "refused"
  if key.len > 6 and key[0 .. 5] == "lobby:":
    let d = key[6 .. ^1]
    if d in iv.lobby and iv.lobby[d].state == "asked":
      iv.lobby[d].state = state
      iv.lobby[d].exp = now + Ttl
      return iv.lobby[d].request
  elif key in iv.items and iv.items[key].state == "asked" and iv.items[key].exp >= now:
    iv.items[key].state = state
    return iv.items[key].request
  nil

proc cancel*(iv: Invites, token: string) =
  if token in iv.items and iv.items[token].state in ["open", "asked"]: iv.items[token].state = "cancelled"
