## Root key backup passphrases (decision 0023, issue #29), for the server's export-root-key and the desktop apps.

import kks/crypto

const PassphraseAlphabet* = "0123456789abcdefghjkmnpqrstvwxyz"   ## Crockford's base32: no i, l, o, u

proc newBackupPassphrase*(p: Provider): string =
  ## 16 random base32 symbols = 80 bits, at least the 6-word passphrase 0023 asks for (77 bits), written
  ## xxxx-xxxx-xxxx-xxxx. Generated, never chosen: a person's own choice can't be checked for strength well enough,
  ## and PBKDF2 leaves the strength to the passphrase.
  let r = p.randomBytes(16)
  for i, b in r:
    if i > 0 and i mod 4 == 0: result.add '-'
    result.add PassphraseAlphabet[int(b) and 31]   # 256 is a multiple of 32: uniform
