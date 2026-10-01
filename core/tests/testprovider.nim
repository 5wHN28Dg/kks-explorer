## The platform's crypto provider for the tests: CNG on Windows, GnuTLS elsewhere.
import kks/crypto
when defined(windows):
  import kks/provider_cng
  proc testProvider*(): Provider = newCngProvider()
else:
  import kks/provider_gnutls
  proc testProvider*(): Provider = newGnuTlsProvider()
