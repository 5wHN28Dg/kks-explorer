## #371: the desktop apps' choice of sentence (apps/common/errwords.nim), as the web's K.errorText and Android's
## Errors.text choose (tests/web/test_common_sinks.py test_error_words checks the web's the same way).
##   nim r --hints:off --path:core/src --path:apps/common tests/test_errwords.nim
import std/unittest
import kks/json
import errwords

proc err(msg, code: string): JNode = newObj(@[("error", newStr(msg)), ("code", newStr(code))])

suite "errors in plain words":
  test "terse texts become sentences; a sentence is kept; a specific refusal is made a sentence":
    check errorText(404, err("not found", "not_found")) == errorWords("not_found")
    check errorText(403, err("manager only", "not_allowed")) == "Only the plant's manager can do that."
    check errorText(401, err("Wrong username or password.", "sign_in")) == "Wrong username or password."
    check errorText(400, err("note: up to 500 characters", "invalid")) == "Note: up to 500 characters."
    check errorText(400, err("bad json", "invalid")) == errorWords("invalid")
    check errorText(500, nil) == errorWords("server")
    check errorText(418, err("x", "no such kind")) == errorWords("invalid")      # (an unknown kind: by the status)
    check errorText(400, err("bad submission kind or payload", "invalid")) == errorWords("invalid")   # (a developer's text)
    check errorText(400, err("action must be start or confirm", "invalid")) == errorWords("invalid")
    check errorText(400, err("Floor: a whole number from 0 to 10 (the height goes in Elevation)", "invalid")) ==
      "Floor: a whole number from 0 to 10 (the height goes in Elevation)."
    check errorText(400, err("Username: 2-40 letters (a-z), digits, . _ - @", "invalid")) == "Username: 2-40 letters (a-z), digits, . _ - @."
    check errorText(400, err("not a readable image (decoder said no)", "invalid")) == errorWords("invalid")
  test "a refused join says the core's reason":
    check notJoined("unknown", "this invite has expired; ask for a new one") == "This invite has expired; ask for a new one."
    check notJoined("used", "") == "Not joined: the admin refused, or the request ended. Ask the admin to try again."
