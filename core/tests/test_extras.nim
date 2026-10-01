import std/[unittest, times]
import kks/[json, util, crypto, proto, extras]
import testprovider
import vectors

let P = testProvider()

suite "protocol v2 outside the log (v2-crypto.json)":
  let V = loadVectors("v2-crypto.json")

  test "join codes":
    for c in V["join_code"].elems:
      check P.joinCode(c["joiner"].s, c["answering"].s) == c["code"].s

  test "join requests":
    check P.checkJoinRequest(V["join_request"]["valid"])
    for c in V["join_request"]["reject"].elems:
      check not P.checkJoinRequest(c["request"])

  test "relay":
    let r = V["relay"]
    check P.relayRoom(r["root"].s) == r["room"].s
    check P.checkRelayHello(r["hello"], r["room"].s, r["now"].i)
    for c in r["reject"].elems:
      check not P.checkRelayHello(c["hello"], r["room"].s, c["now"].i)

  test "ECIES: reproduce and open":
    let c = V["ecies"]
    let sealed = c["sealed"]
    let eph = PrivateKey(scalar: unhex(c["ephemeral_private_scalar_hex"].s), pub: unb64u(sealed["epk"].s))
    let again = P.eciesSeal(c["recipient"].s, c["purpose"].s, unhex(c["plaintext_hex"].s), eph,
                            unb64u(sealed["nonce"].s))
    check again == sealed
    let rk = PrivateKey(scalar: unhex(c["recipient_private_scalar_hex"].s), pub: unb64u(c["recipient"].s))
    check hex(P.eciesOpen(rk, sealed)) == c["plaintext_hex"].s
    var bad = copy(sealed)
    bad["purpose"] = newStr("other")
    expect CryptoError: discard P.eciesOpen(rk, bad)

  test "root key backup (PBKDF2 600k)":
    let c = V["root_backup"]
    let s = c["sealed"]
    let t0 = epochTime()
    check hex(P.passphraseOpen(c["passphrase"].s, s)) == c["plaintext_hex"].s
    echo "  PBKDF2 600k via GnuTLS: ", int((epochTime() - t0) * 1000), " ms"
    let again = P.passphraseSeal(c["passphrase"].s, unhex(c["plaintext_hex"].s), 600_000, unb64u(s["salt"].s),
                                 unb64u(s["nonce"].s))
    check again == s
    expect CryptoError: discard P.passphraseOpen("wrong", s)
    expect ValueError: discard P.passphraseSeal("x", @[1'u8], 1000)

  test "round trip with fresh keys":
    let k = P.p256Generate()
    let sealed = P.eciesSeal(keyString(k.pub), "backup", toBytes("secret"))
    check P.eciesOpen(k, sealed).toStr == "secret"
