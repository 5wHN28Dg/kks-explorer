## The §15 channel on Linux: GnuTLS driven through buffers (decision 0030), so the same code runs over TCP, reliable UDP
## or the relay pipe, and in memory in tests. Each side presents a self-signed X.509 certificate for its device key;
## our verify function replaces certificate-authority checks and pins the peer ID (PROTOCOL-v2 §2, §15).

import kks/[crypto, util, proto]

{.passL: "-lgnutls".}
const
  HG = "<gnutls/gnutls.h>"
  HX = "<gnutls/x509.h>"
  HA = "<gnutls/abstract.h>"

type
  Session {.importc: "gnutls_session_t", header: HG.} = pointer
  Cred {.importc: "gnutls_certificate_credentials_t", header: HG.} = pointer
  Crt {.importc: "gnutls_x509_crt_t", header: HX.} = pointer
  XKey {.importc: "gnutls_x509_privkey_t", header: HX.} = pointer
  PubKey {.importc: "gnutls_pubkey_t", header: HA.} = pointer
  Datum {.importc: "gnutls_datum_t", header: HG.} = object
    data {.importc: "data".}: ptr UncheckedArray[byte]
    size {.importc: "size".}: cuint
  CurveT {.importc: "gnutls_ecc_curve_t", header: HG.} = cint
  CrdT {.importc: "gnutls_credentials_type_t", header: HG.} = cint
  CertReqT {.importc: "gnutls_certificate_request_t", header: HG.} = cint
  DigT {.importc: "gnutls_digest_algorithm_t", header: HG.} = cint
  CloseT {.importc: "gnutls_close_request_t", header: HG.} = cint
  PullFn {.importc: "gnutls_pull_func", header: HG.} = pointer
  PushFn {.importc: "gnutls_push_func", header: HG.} = pointer
  VerifyFn {.importc: "gnutls_certificate_verify_function*", header: HG.} = pointer
  ConstErr {.importc: "const char**", nodecl.} = pointer
  CTime {.importc: "time_t", header: "<time.h>".} = int64

var
  GNUTLS_SERVER {.importc, header: HG, nodecl.}: cuint
  GNUTLS_CLIENT {.importc, header: HG, nodecl.}: cuint
  GNUTLS_NONBLOCK {.importc, header: HG, nodecl.}: cuint
  GNUTLS_NO_TICKETS {.importc, header: HG, nodecl.}: cuint
  GNUTLS_CRD_CERTIFICATE {.importc, header: HG, nodecl.}: CrdT
  GNUTLS_CERT_REQUIRE {.importc, header: HG, nodecl.}: CertReqT
  GNUTLS_ECC_CURVE_SECP256R1 {.importc, header: HG, nodecl.}: CurveT
  GNUTLS_DIG_SHA256 {.importc, header: HG, nodecl.}: DigT
  GNUTLS_E_AGAIN {.importc, header: HG, nodecl.}: cint
  GNUTLS_E_INTERRUPTED {.importc, header: HG, nodecl.}: cint
  GNUTLS_SHUT_WR {.importc, header: HG, nodecl.}: CloseT
  GNUTLS_ALPN_MANDATORY {.importc, header: HG, nodecl.}: cuint
  EAGAIN {.importc, header: "<errno.h>", nodecl.}: cint

proc gnutls_init(s: ptr Session, flags: cuint): cint {.importc, header: HG.}
proc gnutls_deinit(s: Session) {.importc, header: HG.}
proc gnutls_priority_set_direct(s: Session, prio: cstring, err: ConstErr): cint {.importc, header: HG.}
proc gnutls_credentials_set(s: Session, t: CrdT, cred: pointer): cint {.importc, header: HG.}
proc gnutls_certificate_allocate_credentials(c: ptr Cred): cint {.importc, header: HG.}
proc gnutls_certificate_free_credentials(c: Cred) {.importc, header: HG.}
proc gnutls_certificate_set_x509_key(c: Cred, certs: ptr Crt, n: cint, key: XKey): cint {.importc, header: HX.}
proc gnutls_certificate_set_verify_function(c: Cred, f: VerifyFn) {.importc, header: HG.}
proc gnutls_certificate_server_set_request(s: Session, r: CertReqT) {.importc, header: HG.}
proc gnutls_certificate_get_peers(s: Session, n: ptr cuint): ptr Datum {.importc, header: HG.}
proc gnutls_session_set_ptr(s: Session, p: pointer) {.importc, header: HG.}
proc gnutls_session_get_ptr(s: Session): pointer {.importc, header: HG.}
proc gnutls_transport_set_ptr(s: Session, p: pointer) {.importc, header: HG.}
proc gnutls_transport_set_pull_function(s: Session, f: PullFn) {.importc, header: HG.}
proc gnutls_transport_set_push_function(s: Session, f: PushFn) {.importc, header: HG.}
proc gnutls_transport_set_errno(s: Session, e: cint) {.importc, header: HG.}
proc gnutls_handshake(s: Session): cint {.importc, header: HG.}
proc gnutls_record_send(s: Session, data: pointer, n: csize_t): int {.importc, header: HG.}
proc gnutls_record_recv(s: Session, data: pointer, n: csize_t): int {.importc, header: HG.}
proc gnutls_bye(s: Session, how: CloseT): cint {.importc, header: HG.}
proc gnutls_error_is_fatal(e: cint): cint {.importc, header: HG.}
proc gnutls_strerror(e: cint): cstring {.importc, header: HG.}
proc gnutls_certificate_set_x509_system_trust(c: Cred): cint {.importc, header: HG.}
proc gnutls_server_name_set(s: Session, t: cint, name: cstring, n: csize_t): cint {.importc, header: HG.}
proc gnutls_session_set_verify_cert(s: Session, host: cstring, flags: cuint) {.importc, header: HG.}
proc gnutls_set_default_priority(s: Session): cint {.importc, header: HG.}
var GNUTLS_NAME_DNS {.importc, header: HG, nodecl.}: cint
proc gnutls_alpn_set_protocols(s: Session, p: ptr Datum, n: cuint, flags: cuint): cint {.importc, header: HG.}
proc gnutls_alpn_get_selected_protocol(s: Session, p: ptr Datum): cint {.importc, header: HG.}
proc gnutls_x509_privkey_init(k: ptr XKey): cint {.importc, header: HX.}
proc gnutls_x509_privkey_deinit(k: XKey) {.importc, header: HX.}
proc gnutls_x509_privkey_import_ecc_raw(k: XKey, c: CurveT, x, y, d: ptr Datum): cint {.importc, header: HX.}
proc gnutls_x509_crt_init(c: ptr Crt): cint {.importc, header: HX.}
proc gnutls_x509_crt_deinit(c: Crt) {.importc, header: HX.}
proc gnutls_x509_crt_import(c: Crt, d: ptr Datum, fmt: cint): cint {.importc, header: HX.}
proc gnutls_x509_crt_set_version(c: Crt, v: cuint): cint {.importc, header: HX.}
proc gnutls_x509_crt_set_serial(c: Crt, s: pointer, n: csize_t): cint {.importc, header: HX.}
proc gnutls_x509_crt_set_activation_time(c: Crt, t: CTime): cint {.importc, header: HX.}
proc gnutls_x509_crt_set_expiration_time(c: Crt, t: CTime): cint {.importc, header: HX.}
proc gnutls_x509_crt_set_key(c: Crt, k: XKey): cint {.importc, header: HX.}
proc gnutls_x509_crt_set_dn(c: Crt, dn: cstring, err: ConstErr): cint {.importc, header: HX.}
proc gnutls_x509_crt_sign2(c, issuer: Crt, k: XKey, dig: DigT, flags: cuint): cint {.importc, header: HX.}
proc gnutls_pubkey_init(k: ptr PubKey): cint {.importc, header: HA.}
proc gnutls_pubkey_deinit(k: PubKey) {.importc, header: HA.}
proc gnutls_pubkey_import_x509(k: PubKey, c: Crt, flags: cuint): cint {.importc, header: HA.}
proc gnutls_pubkey_export_ecc_raw2(k: PubKey, c: ptr CurveT, x, y: ptr Datum, flags: cuint): cint {.importc, header: HA.}
proc gfree(p: pointer) {.importc: "(gnutls_free)", header: HG.}

var
  GNUTLS_X509_FMT_DER {.importc, header: HX, nodecl.}: cint
  GNUTLS_EXPORT_FLAG_NO_LZ {.importc, header: HA, nodecl.}: cuint

const
  Priority* = "NONE:+VERS-TLS1.3:+VERS-TLS1.2:+AES-128-GCM:+AES-256-GCM:+AEAD:+ECDHE-ECDSA:" &
              "+GROUP-SECP256R1:+GROUP-X25519:+SIGN-ECDSA-SECP256R1-SHA256:+SIGN-ECDSA-SHA256:+CTYPE-X509:+COMP-NULL"
    ## PROTOCOL-v2 §15: TLS 1.3, or 1.2 with ECDHE-ECDSA-AES-GCM only; P-256 certificates.
  AlpnId* = "kks-sync/2"

type
  TlsError* = object of CatchableError

  Identity* = ref object
    ## This device's TLS credentials: a self-signed certificate for its device key.
    cred: Cred
    crt: Crt
    xkey: XKey

  TlsConn* = ref object
    s: Session
    id: Identity
    p: Provider
    inbuf: string        ## ciphertext received, not yet consumed by GnuTLS
    outbuf: string       ## ciphertext to send
    expectPeer*: string  ## client: the peer ID it meant to reach ("" = any, the caller decides)
    remotePeer*: string  ## set by the verify function
    handshaken*: bool
    closed*: bool
    verifyError: string
    web: bool            ## a web server (the relay's wss): the system's CAs and the host name, not a device key

proc fail(what: string, r: cint) =
  raise newException(TlsError, what & ": " & $gnutls_strerror(r))

proc datum(a: openArray[byte]): Datum =
  Datum(data: cast[ptr UncheckedArray[byte]](if a.len > 0: unsafeAddr a[0] else: nil), size: cuint(a.len))

proc newIdentity*(key: PrivateKey): Identity =
  ## A self-signed certificate for the device key. Names and dates are not checked by anyone (§15).
  result = Identity()
  if key.scalar.len != 32: raise newException(TlsError, "this TLS identity needs the key's scalar (key-store keys: see the platform adapter)")
  var r = gnutls_x509_privkey_init(addr result.xkey)
  if r < 0: fail("privkey", r)
  var x = datum(key.pub.toOpenArray(1, 32))
  var y = datum(key.pub.toOpenArray(33, 64))
  var d = datum(key.scalar)
  r = gnutls_x509_privkey_import_ecc_raw(result.xkey, GNUTLS_ECC_CURVE_SECP256R1, addr x, addr y, addr d)
  if r < 0: fail("import key", r)
  r = gnutls_x509_crt_init(addr result.crt)
  if r < 0: fail("crt", r)
  discard gnutls_x509_crt_set_version(result.crt, 3)
  var serial = [1'u8]
  discard gnutls_x509_crt_set_serial(result.crt, addr serial[0], 1)
  discard gnutls_x509_crt_set_activation_time(result.crt, CTime(0))   # 1970: dates are ignored
  discard gnutls_x509_crt_set_expiration_time(result.crt, CTime(253402300799'i64))   # 9999-12-31
  discard gnutls_x509_crt_set_dn(result.crt, "CN=kks-device", ConstErr(nil))
  r = gnutls_x509_crt_set_key(result.crt, result.xkey)
  if r < 0: fail("set key", r)
  r = gnutls_x509_crt_sign2(result.crt, result.crt, result.xkey, GNUTLS_DIG_SHA256, 0)
  if r < 0: fail("sign", r)
  r = gnutls_certificate_allocate_credentials(addr result.cred)
  if r < 0: fail("credentials", r)
  r = gnutls_certificate_set_x509_key(result.cred, addr result.crt, 1, result.xkey)
  if r < 0: fail("set credentials", r)

proc pull(p: pointer, data: pointer, size: csize_t): int {.cdecl.} =
  let c = cast[TlsConn](p)
  if c.inbuf.len == 0:
    gnutls_transport_set_errno(c.s, EAGAIN)
    return -1
  let n = min(int(size), c.inbuf.len)
  copyMem(data, addr c.inbuf[0], n)
  c.inbuf = c.inbuf[n .. ^1]
  n

proc push(p: pointer, data: pointer, size: csize_t): int {.cdecl.} =
  let c = cast[TlsConn](p)
  let start = c.outbuf.len
  c.outbuf.setLen(start + int(size))
  if size > 0: copyMem(addr c.outbuf[start], data, int(size))
  int(size)

proc verifyPeer(s: Session): cint {.cdecl.} =
  ## Our trust decision: the peer's certificate must carry a P-256 key; its peer ID is recorded, and must equal the
  ## expected one when the caller named one.
  let c = cast[TlsConn](gnutls_session_get_ptr(s))
  var n: cuint
  let certs = gnutls_certificate_get_peers(s, addr n)
  if certs == nil or n < 1:
    c.verifyError = "no certificate"
    return -1
  var crt: Crt
  var pk: PubKey
  if gnutls_x509_crt_init(addr crt) < 0: return -1
  defer: gnutls_x509_crt_deinit(crt)
  if gnutls_x509_crt_import(crt, certs, GNUTLS_X509_FMT_DER) < 0 or gnutls_pubkey_init(addr pk) < 0:
    c.verifyError = "bad certificate"
    return -1
  defer: gnutls_pubkey_deinit(pk)
  var curve: CurveT
  var x, y: Datum
  if gnutls_pubkey_import_x509(pk, crt, 0) < 0 or
     gnutls_pubkey_export_ecc_raw2(pk, addr curve, addr x, addr y, GNUTLS_EXPORT_FLAG_NO_LZ) < 0:
    c.verifyError = "not an EC key"
    return -1
  var pub = @[4'u8]
  proc pad(d: Datum): seq[byte] =
    result = newSeq[byte](32 - min(32, int(d.size)))
    for i in 0 ..< int(d.size): result.add d.data[i]
  pub.add pad(x)
  pub.add pad(y)
  gfree(x.data)
  gfree(y.data)
  if curve != GNUTLS_ECC_CURVE_SECP256R1 or pub.len != 65:
    c.verifyError = "not a P-256 key"
    return -1
  c.remotePeer = c.p.peerIdOfKey(keyString(pub))
  if c.expectPeer.len > 0 and c.remotePeer != c.expectPeer:
    c.verifyError = "a different device answered"
    return -1
  0

proc newTlsConn*(p: Provider, id: Identity, client: bool, expectPeer = ""): TlsConn =
  result = TlsConn(id: id, p: p, expectPeer: expectPeer)
  GC_ref(result)    # GnuTLS holds a raw pointer to it until close()
  var r = gnutls_init(addr result.s, (if client: GNUTLS_CLIENT else: GNUTLS_SERVER) or GNUTLS_NONBLOCK or GNUTLS_NO_TICKETS)
  if r < 0: fail("init", r)
  var err: cstring
  r = gnutls_priority_set_direct(result.s, Priority, cast[ConstErr](addr err))
  if r < 0: fail("priority at " & $err, r)
  r = gnutls_credentials_set(result.s, GNUTLS_CRD_CERTIFICATE, id.cred)
  if r < 0: fail("credentials", r)
  gnutls_certificate_set_verify_function(id.cred, cast[VerifyFn](verifyPeer))
  if not client: gnutls_certificate_server_set_request(result.s, GNUTLS_CERT_REQUIRE)
  var alpn = datum(AlpnId.toBytes)
  r = gnutls_alpn_set_protocols(result.s, addr alpn, 1, GNUTLS_ALPN_MANDATORY)
  if r < 0: fail("alpn", r)
  gnutls_session_set_ptr(result.s, cast[pointer](result))
  gnutls_transport_set_ptr(result.s, cast[pointer](result))
  gnutls_transport_set_pull_function(result.s, cast[PullFn](pull))
  gnutls_transport_set_push_function(result.s, cast[PushFn](push))

var webCred: Cred

proc newWebTlsConn*(host: string): TlsConn =
  ## A TLS client for an ordinary web server (the relay, PROTOCOL-v2 §18): the system's trusted CAs, SNI, and the
  ## certificate must name `host` (GnuTLS checks both during the handshake). Not used between devices.
  result = TlsConn(web: true)
  GC_ref(result)
  if webCred == nil:
    var r = gnutls_certificate_allocate_credentials(addr webCred)
    if r < 0: fail("credentials", r)
    r = gnutls_certificate_set_x509_system_trust(webCred)
    if r < 0: fail("system trust", r)
  var r = gnutls_init(addr result.s, GNUTLS_CLIENT or GNUTLS_NONBLOCK)
  if r < 0: fail("init", r)
  r = gnutls_set_default_priority(result.s)
  if r < 0: fail("priority", r)
  r = gnutls_credentials_set(result.s, GNUTLS_CRD_CERTIFICATE, webCred)
  if r < 0: fail("credentials", r)
  r = gnutls_server_name_set(result.s, GNUTLS_NAME_DNS, host.cstring, csize_t(host.len))
  if r < 0: fail("server name", r)
  gnutls_session_set_verify_cert(result.s, host.cstring, 0)
  gnutls_session_set_ptr(result.s, cast[pointer](result))
  gnutls_transport_set_ptr(result.s, cast[pointer](result))
  gnutls_transport_set_pull_function(result.s, cast[PullFn](pull))
  gnutls_transport_set_push_function(result.s, cast[PushFn](push))

proc feed*(c: TlsConn, bytes: string) = c.inbuf.add bytes

proc takeOut*(c: TlsConn): string =
  ## Ciphertext to send to the other side.
  result = move c.outbuf
  c.outbuf = ""

proc handshake*(c: TlsConn): bool =
  ## Drive the handshake with what has arrived. -> true when done. Raises TlsError on failure.
  if c.handshaken: return true
  let r = gnutls_handshake(c.s)
  if r == 0 and c.web:
    c.handshaken = true
    return true
  if r == 0:
    var sel: Datum
    if gnutls_alpn_get_selected_protocol(c.s, addr sel) < 0 or int(sel.size) != AlpnId.len:
      raise newException(TlsError, "the other side doesn't speak " & AlpnId)
    if c.remotePeer.len == 0: raise newException(TlsError, "no peer identity")
    c.handshaken = true
    return true
  if r == GNUTLS_E_AGAIN or r == GNUTLS_E_INTERRUPTED: return false
  if c.verifyError.len > 0: raise newException(TlsError, c.verifyError)
  fail("handshake", r)

proc send*(c: TlsConn, plain: string) =
  var off = 0
  while off < plain.len:
    let n = gnutls_record_send(c.s, unsafeAddr plain[off], csize_t(plain.len - off))
    if n < 0:
      if cint(n) == GNUTLS_E_AGAIN: continue
      fail("send", cint(n))
    off += n

proc recv*(c: TlsConn): string =
  ## All plaintext that the received ciphertext holds. Sets `closed` when the other side said goodbye.
  var buf: array[16384, byte]
  var left = c.inbuf.len
  while true:
    let n = gnutls_record_recv(c.s, addr buf[0], csize_t(buf.len))
    if n > 0:
      let start = result.len
      result.setLen(start + n)
      copyMem(addr result[start], addr buf[0], n)
    elif n == 0:
      c.closed = true
      return
    elif cint(n) == GNUTLS_E_AGAIN or cint(n) == GNUTLS_E_INTERRUPTED:
      # GnuTLS also says "again" after a post-handshake message (a TLS 1.3 session ticket from a web server) while
      # more records wait in inbuf: go on as long as it consumes something (2026-10-02, the relay's 101 sat unread)
      if c.inbuf.len == 0 or c.inbuf.len >= left: return
      left = c.inbuf.len
    elif gnutls_error_is_fatal(cint(n)) != 0:
      fail("receive", cint(n))
    else:
      return

proc close*(c: TlsConn) =
  if c.s != nil:
    discard gnutls_bye(c.s, GNUTLS_SHUT_WR)
    gnutls_deinit(c.s)
    c.s = nil
    GC_unref(c)
