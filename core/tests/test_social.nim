import std/[unittest, tables]
import kks/[json, util, crypto, proto, replay, node, sync, plant, progress, invites, extras]
import testprovider

let P = testProvider()
var wall = 1_790_000_000_000'i64
proc tick(): int64 =
  wall += 1000
  wall

suite "invites and the retired secrets swap":
  let rootKey = P.p256Generate()
  var phone = newNode(P, newMemStore(), P.p256Generate())
  let me = P.newPersonId()
  discard phone.append("genesis", P.genesisBody(rootKey, "Test plant", phone.device, me, "boss", "The Manager"), tick())
  phone.adopt(keyString(rootKey.pub))
  var laptop = newNode(P, newMemStore(), P.p256Generate())
  discard phone.append("device_cert", deviceCertBody(laptop.device, me, "laptop"), tick())

  test "invite: bad request, waiting, accepted, used":
    let iv = newInvites()
    let now = 1_790_000_000'i64
    let inv = iv.create(P, me, phone.root, "Test plant", phone.device, @["10.0.0.2:8421"], now)
    let tok = inv["token"]
    let newKey = P.p256Generate()
    let req = P.joinRequest(newKey, "dana", "Dana User", newNull(), "phone", now)
    let joiner = P.peerId(newKey)
    check iv.offer(P, "someoneelse", newObj(@[("token", tok), ("request", req)]), now)["state"].s == "bad"
    check iv.offer(P, joiner, newObj(@[("token", tok), ("request", req)]), now)["state"].s == "waiting"
    check iv.offer(P, "intruder", newObj(@[("token", tok), ("request", req)]), now)["state"].s == "used"
    check iv.pending(now).len == 1
    check iv.decide(tok.s, true, now) != nil
    check iv.offer(P, joiner, newObj(@[("token", tok), ("request", req)]), now)["state"].s == "accepted"
    check iv.offer(P, joiner, newObj(@[("token", newStr("nope")), ("request", req)]), now)["state"].s == "unknown"
    check iv.offer(P, joiner, newObj(@[("token", tok), ("request", req)]), now + 10 * Ttl)["state"].s == "accepted"

  test "lobby: asks without a token, with matching join codes":
    let iv = newInvites()
    let k = P.p256Generate()
    let req = P.joinRequest(k, "eve", "Eve User", newNull(), "laptop", 1)
    let d = P.peerId(k)
    check iv.offer(P, d, newObj(@[("token", newNull()), ("request", req)]), 100)["state"].s == "waiting"
    check iv.decide("lobby:" & d, false, 101) != nil
    check iv.offer(P, d, newObj(@[("token", newNull()), ("request", req)]), 102)["state"].s == "refused"
    check P.joinCode(d, phone.device).len == 6

  test "a responder answers the retired secrets swap with nothing (§17: secrets travel only in sealed shares)":
    var s2 = newSession(phone, false, laptop.device)
    s2.receive(newObj(@[("t", newStr("secrets")), ("person", newStr(me)), ("secrets", newArr())]))
    check s2.outbox[0]["secrets"].len == 0 and phone.secretsOf(me).len == 0
