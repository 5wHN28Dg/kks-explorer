import std/[unittest, times, osproc, strutils, os]
import kksl/argon2

suite "Argon2id via OpenSSL":
  test "matches the openssl command line, round trips, refuses a wrong password":
    let salt = "0123456789abcdef"
    let got = derive("correct horse", salt)
    let (cli, code) = execCmdEx("openssl kdf -keylen 32 -kdfopt pass:'correct horse' -kdfopt salt:0123456789abcdef " &
                                "-kdfopt iter:2 -kdfopt memcost:19456 -kdfopt lanes:1 ARGON2ID")
    check code == 0
    var hexs = ""
    for c in got: hexs.add toHex(ord(c), 2)
    check cli.strip.replace(":", "").toUpperAscii == hexs
    let t0 = epochTime()
    let h = hashPassword("correct horse", salt)
    echo "  one hash: ", int((epochTime() - t0) * 1000), " ms"
    check h.startsWith("$argon2id$v=19$m=19456,t=2,p=1$")
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
