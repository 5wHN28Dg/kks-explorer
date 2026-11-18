## Errors in plain words (#371, F2 in docs/UI-UX-POLICY.md), the same sentences as the web's common.js K.errorWords
## and Android's Errors.kt: the core sends an error's kind ("code") with its own text. Its text is shown when it is
## already a sentence ("Wrong username or password."); a terse one ("not found", "admin only") becomes the sentence for
## its kind. The raw text goes to the log.
import std/[strutils]
import kks/json

const ErrorWords* = [
  ("sign_in", "Your sign-in has ended. Sign in again."),
  ("not_allowed", "You don't have the right to do that here. Ask an admin if you need it."),
  ("not_found", "It isn't there any more: someone may have removed it. Open it again to see what is there now."),
  ("conflict", "It was changed meanwhile, so this was not saved. Look at the current value and try again."),
  ("too_large", "That is too large to send. Choose a smaller file or a shorter text."),
  ("too_many", "Too many tries. Wait a few minutes, then try again."),
  ("invalid", "That was not accepted. Check what you entered and try again."),
  ("server", "The server had a problem, so this was not done. Try again in a moment."),
  ("unreachable", "Couldn't reach the server. Check the network and try again.")]

## terse texts that have a sentence of their own
const ErrorTerse* = [
  ("manager only", "Only the plant's manager can do that."),
  ("admin only", "Only an admin can do that."),
  ("cross-origin request refused", "The request came from another page and was refused. Open Walkdown from its own address."),
  ("not saved on this device", "This isn't saved on this device for offline use. Connect to the server to see it."),
  ("method not allowed", "This needs a newer Walkdown here or on the server.")]

proc errorWords*(code: string): string =
  for (k, v) in ErrorWords:
    if k == code: return v
  for (k, v) in ErrorWords:
    if k == "server": return v

proc codeOf*(status: int): string =
  if status == 401: "sign_in"
  elif status == 403: "not_allowed"
  elif status == 404: "not_found"
  elif status == 409: "conflict"
  elif status == 413: "too_large"
  elif status == 429: "too_many"
  elif status >= 400 and status < 500: "invalid"
  else: "server"

proc asSentence*(t: string): string =
  ## a readable text of the core's ("this invite has expired; ask for a new one") as a sentence
  let s = t.strip
  if s.len == 0: "" else: s[0].toUpperAscii & s[1 .. ^1] & (if s[^1] in {'.', '!', '?'}: "" else: ".")

proc devText*(t: string): bool =
  ## a developer's text, not meant for people ("bad submission kind or payload", "action must be start or confirm")
  let l = t.toLowerAscii
  l.startsWith("bad ") or l.startsWith("unknown ") or l.startsWith("not a readable image") or " must be " in l or " is required" in l

proc isSentence*(t: string): bool =
  let s = t.strip
  s.len > 1 and s[0] in {'A' .. 'Z'} and s[^1] in {'.', '!', '?'}

proc known(code: string): bool =
  for (k, _) in ErrorWords:
    if k == code: return true

proc errorText*(status: int, j: JNode): string =
  ## what to say for an error response (status, the JSON body or nil): a terse text's own sentence; the server's
  ## sentence; for a request that was refused (invalid, too large, too many, not allowed) its specific text of three
  ## words or more made a sentence ("Note: up to 500 characters."); else the sentence for the kind
  let raw = (if j != nil and j.kind == jObj and j.get("error") != nil and j["error"].isStr: j["error"].s else: "").strip
  let given = if j != nil and j.kind == jObj and j.get("code") != nil and j["code"].isStr: j["code"].s else: ""
  let code = if given.known: given else: codeOf(status)
  for (k, v) in ErrorTerse:
    if k == raw: return v
  if raw.isSentence: return raw
  if code in ["invalid", "too_large", "too_many", "not_allowed", "conflict"] and raw.splitWhitespace.len >= 3 and not raw.devText:
    return raw.asSentence
  errorWords(code)

proc unreachable*(host: string, port: int): string =
  ## a server this device could not connect to (joining, Sync now): plain words, the system's text goes to the log
  "Couldn't reach the server at " & host & ":" & $port & ". Check the address and that this device is on the plant's network."

## joining and syncing, the same words on Android (Errors.kt)
const LostJoin* = "The connection to the admin's device was lost before they decided. Ask again."
const FirstSyncFailed* = "Accepted, but the first sync did not finish. Try again in a moment."

proc notJoined*(state, why: string): string =
  ## the core's own reason ("this invite has expired; ask for a new one"), else plain words for the state
  if why.strip.len > 0: why.asSentence
  else: "Not joined: the admin refused, or the request ended. Ask the admin to try again."

proc syncFailed*(host: string, port: int): string =
  "Couldn't sync with " & host & ":" & $port & ". Check that the device is on, on this network, and that its address and port are right."
