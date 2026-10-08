## Root key backup passphrases (kksl/passphrase.nim, issue #29).
import std/unittest
import kksl/passphrase
import plat

let P = testProvider()

suite "root key backup passphrase":
  test "generated: 16 base32 symbols in 4 groups, 80 bits, different every time":
    let a = P.newBackupPassphrase()
    check a.len == 19 and a[4] == '-' and a[9] == '-' and a[14] == '-'
    for i, c in a:
      if i mod 5 != 4: check c in PassphraseAlphabet
    check PassphraseAlphabet.len == 32                    # 5 bits a symbol, 16 symbols
    check P.newBackupPassphrase() != a
