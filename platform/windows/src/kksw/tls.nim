## Sync connections over Schannel (decision 0033): the same buffer-driven API as platform/linux/src/kksl/tls.nim, so
## net.nim runs unchanged. The device key stays in its CNG key store; the certificate is made for it at start.

import std/strutils
import kks/[crypto, util, proto]

{.compile: "kks_schannel.c".}
{.passL: "-lsecur32 -lcrypt32 -lncrypt -lbcrypt".}

const AlpnId* = "kks-sync/2"

type
  TlsError* = object of CatchableError
  CIdentity = pointer
  CTls = pointer

  Identity* = ref object
    ## This device's TLS credentials: a self-signed certificate for its device key.
    c: CIdentity

  TlsConn* = ref object
    c: CTls
    id: Identity
    p: Provider
    expectPeer*: string   ## client: the peer ID it meant to reach ("" = any, the caller decides)
    remotePeer*: string
    handshaken*: bool
    closed*: bool

proc c_identity_new(name: WideCString, tpm: cint, err: cstring, en: csize_t): CIdentity {.importc: "kks_identity_new", cdecl.}
proc c_identity_free(id: CIdentity) {.importc: "kks_identity_free", cdecl.}
proc c_import(name: WideCString, pub, d: pointer): cint {.importc: "kks_ncrypt_import", cdecl.}
proc c_new(id: CIdentity, client: cint): CTls {.importc: "kks_tls_new", cdecl.}
proc c_free(c: CTls) {.importc: "kks_tls_free", cdecl.}
proc c_error(c: CTls): cstring {.importc: "kks_tls_error", cdecl.}
proc c_feed(c: CTls, d: pointer, n: csize_t) {.importc: "kks_tls_feed", cdecl.}
proc c_take(c: CTls, d: pointer, cap: csize_t): csize_t {.importc: "kks_tls_take_out", cdecl.}
proc c_pending(c: CTls): csize_t {.importc: "kks_tls_pending_out", cdecl.}
proc c_handshake(c: CTls): cint {.importc: "kks_tls_handshake", cdecl.}
proc c_peer_key(c: CTls, pub: pointer): cint {.importc: "kks_tls_peer_key", cdecl.}
proc c_send(c: CTls, d: pointer, n: csize_t): cint {.importc: "kks_tls_send", cdecl.}
proc c_recv(c: CTls, d: pointer, cap: csize_t): clong {.importc: "kks_tls_recv", cdecl.}
proc c_closed(c: CTls): cint {.importc: "kks_tls_closed", cdecl.}
proc c_shutdown(c: CTls) {.importc: "kks_tls_shutdown", cdecl.}
proc c_version(c: CTls): cint {.importc: "kks_tls_version", cdecl.}

proc version*(c: TlsConn): string =
  ## the negotiated TLS version (tests, the status page): "1.3", "1.2" or ""
  case c_version(c.c)
  of 4: "1.3"
  of 3: "1.2"
  else: ""

proc newIdentity*(key: PrivateKey): Identity =
  ## key.handle "ncrypt:sw:<name>" / "ncrypt:tpm:<name>" (the device key); a key with its scalar (tests) is imported
  ## into the software key store first, under a name derived from its public point.
  var name: string
  var tpm = false
  if key.handle.startsWith("ncrypt:"):
    let parts = key.handle.split(':', 2)
    tpm = parts[1] == "tpm"
    name = parts[2]
  elif key.scalar.len == 32 and key.pub.len == 65:
    name = "kks-tls-" & hex(key.pub[1 .. 12])
    if c_import(newWideCString(name), unsafeAddr key.pub[0], unsafeAddr key.scalar[0]) != 0:
      raise newException(TlsError, "could not import the key into the software key store")
  else:
    raise newException(TlsError, "no usable device key")
  var err = newString(200)
  let c = c_identity_new(newWideCString(name), cint(ord(tpm)), cstring(err), 200)
  if c == nil: raise newException(TlsError, "TLS identity: " & $cstring(err))
  Identity(c: c)

proc free*(id: Identity) =
  if id.c != nil:
    c_identity_free(id.c)
    id.c = nil

proc newTlsConn*(p: Provider, id: Identity, client: bool, expectPeer = ""): TlsConn =
  TlsConn(c: c_new(id.c, cint(ord(client))), id: id, p: p, expectPeer: expectPeer)

proc fail(c: TlsConn, what: string) =
  raise newException(TlsError, what & ": " & $c_error(c.c))

proc feed*(c: TlsConn, bytes: string) =
  if bytes.len > 0: c_feed(c.c, unsafeAddr bytes[0], csize_t(bytes.len))

proc takeOut*(c: TlsConn): string =
  ## Ciphertext to send to the other side.
  result = newString(int(c_pending(c.c)))
  if result.len > 0: result.setLen(int(c_take(c.c, addr result[0], csize_t(result.len))))

proc handshake*(c: TlsConn): bool =
  ## Drive the handshake with what has arrived. -> true when done. Raises TlsError on failure.
  if c.handshaken: return true
  let r = c_handshake(c.c)
  if r < 0: c.fail("handshake")
  if r == 0: return false
  var pub = newSeq[byte](65)
  if c_peer_key(c.c, addr pub[0]) != 0: c.fail("peer")
  c.remotePeer = c.p.peerIdOfKey(keyString(pub))
  if c.expectPeer.len > 0 and c.remotePeer != c.expectPeer: raise newException(TlsError, "a different device answered")
  c.handshaken = true
  true

proc send*(c: TlsConn, plain: string) =
  if plain.len > 0 and c_send(c.c, unsafeAddr plain[0], csize_t(plain.len)) != 0: c.fail("send")

proc recv*(c: TlsConn): string =
  ## All plaintext that the received ciphertext holds. Sets `closed` when the other side said goodbye.
  var buf = newString(16384)
  while true:
    let n = c_recv(c.c, addr buf[0], csize_t(buf.len))
    if n < 0: c.fail("receive")
    if n == 0: break
    result.add buf[0 ..< int(n)]
  c.closed = c_closed(c.c) != 0

proc close*(c: TlsConn) =
  if c.c != nil:
    c_shutdown(c.c)
    c_free(c.c)
    c.c = nil
