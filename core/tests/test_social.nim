import std/[unittest, tables]
import kks/[json, util, crypto, proto, replay, node, sync, plant, progress, invites, extras]
import testprovider

let P = testProvider()
var wall = 1_790_000_000_000'i64
proc tick(): int64 =
  wall += 1000
  wall

suite "invites, secrets, course progress":
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

  test "secrets swap only between two devices of one person, then progress merges":
    var s1 = newSession(laptop, true, phone.device, adoptRoot = phone.root)
    var s2 = newSession(phone, false, laptop.device)
    s1.wall = tick()
    s2.wall = s1.wall
    while not (s1.done and s2.done):
      while s1.outbox.len > 0:
        let m = s1.outbox[0]; s1.outbox.delete(0); s2.receive(m)
      while s2.outbox.len > 0:
        let m = s2.outbox[0]; s2.outbox.delete(0); s1.receive(m)
    check laptop.owner == me
    var d1: OrderedTable[string, string]
    d1["solved"] = """{"a":true}"""
    d1["finalBest"] = "7"
    discard phone.saveProgress("hrsg", d1, tick())
    # the laptop can't read it yet: no secret
    discard laptop.ingest(phone.entriesFor(laptop.vv), tick())
    check laptop.loadProgress(me).len == 0
    let answer = phone.secretsAnswer(laptop.device, laptop.secretsRequest())
    check laptop.takeSecretsAnswer(answer) == 1
    var d2: OrderedTable[string, string]
    d2["solved"] = """{"b":true}"""
    d2["finalBest"] = "5"
    discard laptop.saveProgress("hrsg", d2, tick())
    let got = laptop.loadProgress(me)["hrsg"]
    check parseStrict(got["solved"]) == parseStrict("""{"a":true,"b":true}""")
    check got["finalBest"] == "7"
    # a stranger asking for secrets gets none
    check phone.secretsAnswer("strangerpeer", laptop.secretsRequest())["secrets"].len == 0
