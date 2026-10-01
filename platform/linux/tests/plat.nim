## The platform under test: CNG + Schannel on Windows (platform/windows), GnuTLS elsewhere.
import kks/crypto
when defined(windows):
  import kks/provider_cng, kksw/tls
  export tls
  proc testProvider*(): Provider = newCngProvider()
else:
  import kks/provider_gnutls, kksl/tls
  export tls
  proc testProvider*(): Provider = newGnuTlsProvider()
