import std/[unittest, times, osproc, strutils, os, base64]
import kksl/argon2

suite "Argon2id via OpenSSL":
  test "matches the openssl command line, round trips, refuses a wrong password":
    let salt = "0123456789abcdef"
    let got = derive("correct horse", salt)
    let (cli, code) = execCmdEx("openssl kdf -keylen 32 -kdfopt pass:'correct horse' -kdfopt salt:0123456789abcdef " &
                                "-kdfopt iter:3 -kdfopt memcost:65536 -kdfopt lanes:1 ARGON2ID")
    check code == 0
    var hexs = ""
    for c in got: hexs.add toHex(ord(c), 2)
    check cli.strip.replace(":", "").toUpperAscii == hexs
    let t0 = epochTime()
    let h = hashPassword("correct horse", salt)
    echo "  one hash: ", int((epochTime() - t0) * 1000), " ms"
    check h.startsWith("$argon2id$v=19$m=65536,t=3,p=1$")   # decision 0023's parameters (issue #40)
    check not needsRehash(h)
    check checkPassword("correct horse", h)
    check not checkPassword("correct hors", h)
    check not checkPassword("x", "")

  test "v1 scrypt hashes still verify":
    let script = getTempDir() / "kks-mkscrypt.py"
    writeFile(script, "import hashlib\ns = bytes(range(16))\nprint('scrypt$16384$8$1$' + s.hex() + '$' + hashlib.scrypt(b'old password!', salt=s, n=16384, r=8, p=1, dklen=32).hex())\n")
    let (h, code) = execCmdEx("python3 " & script)
    check code == 0
    check isLegacy(h.strip)
    check checkPassword("old password!", h.strip)
    check not checkPassword("old password?", h.strip)

  test "a hash with the old parameters still verifies and asks to be replaced (issue #40)":
    let salt = "0123456789abcdef"
    let old = "$argon2id$v=19$m=19456,t=2,p=1$" & encode(salt).strip(leading = false, chars = {'='}) & "$" &
              encode(derive("correct horse", salt, 19456, 2, 1)).strip(leading = false, chars = {'='})
    check checkPassword("correct horse", old)
    check needsRehash(old)
    check needsRehash("scrypt$16384$8$1$00$00")
