## Windows platform layer checks that need a real Windows: DPAPI, the CNG key store (software and TPM), DNS-SD.
import std/[unittest, os, times]
import kks/[crypto, provider_cng, proto]
import kksw/[keystore, mdns]

let P = newCngProvider()

suite "Windows platform":
  test "DPAPI seals the storage key and gives back the same one":
    let dir = getTempDir() / "kks-dpapi-test"
    removeDir(dir)
    let a = storageKey(dir, proc (): seq[byte] = P.randomBytes(32))
    let b = storageKey(dir, proc (): seq[byte] = P.randomBytes(32))
    check a.len == 32 and a == b
    check readFile(dir / "storage.key.dpapi").len > 32      # sealed, not the raw key

  test "a device key in the software key store signs; the signature verifies":
    let k = P.storeKey(false, "kks-test-device")
    check k.pub.len == 65 and k.scalar.len == 0
    let sig = P.p256Sign(k, @[1'u8, 2, 3])
    check P.p256Verify(k.pub, @[1'u8, 2, 3], sig)
    check P.deleteStoreKey(k.handle)

  test "the TPM key store (Platform Crypto Provider), if present":
    try:
      let k = P.storeKey(true, "kks-test-tpm")
      let sig = P.p256Sign(k, @[9'u8])
      check P.p256Verify(k.pub, @[9'u8], sig)
      discard P.deleteStoreKey(k.handle)
      echo "    TPM: P-256 key made and used"
    except CryptoError as e:
      echo "    TPM: not usable here: ", e.msg

  test "DNS-SD: announce and find ourselves":
    let m = newMdns()
    m.announce("kks-wintest", 18999, @[("peer", "abc"), ("v", "2")])
    m.browse()
    var seen = false
    let t0 = epochTime()
    while epochTime() - t0 < 15 and not seen:
      m.pump()
      for f in m.found:
        if f.name == "kks-wintest" and f.port == 18999: seen = true
      sleep(200)
    check seen
