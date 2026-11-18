## Errors in plain words (#371, F2 in docs/UI-UX-POLICY.md), the same sentences as the web's common.js K.errorWords
## and Android's Errors.kt: the core sends an error's kind ("code") with its own text. Its text is shown when it is
## already a sentence ("Wrong username or password."); a terse one ("not found", "admin only") becomes the sentence for
## its kind. The raw text goes to the log.
import std/[strutils]
import kks/json

const ErrorWords* = [
  ("sign_in", "Your sign-in has ended. Sign in again; what you typed is kept."),
  ("not_allowed", "You don't have the right to do that. An admin can."),
  ("not_found", "It isn't there any more: someone may have removed it. Reload to see what is there now."),
  ("conflict", "It was changed meanwhile, so this was not saved. Look at the current value and try again."),
  ("too_large", "That is too large to send."),
  ("too_many", "Too many tries. Wait a few minutes, then try again."),
  ("invalid", "That was not accepted. Check what you entered and try again."),
  ("server", "The server had a problem, so this was not done. Try again in a moment."),
  ("unreachable", "Couldn't reach the server. Check the network; what you changed is kept on this device.")]

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

proc isSentence*(t: string): bool =
  let s = t.strip
  s.len > 1 and s[0] in {'A' .. 'Z'} and s[^1] in {'.', '!', '?'}

proc errorText*(status: int, j: JNode): string =
  ## what to say for an error response (status, the JSON body or nil)
  let raw = if j != nil and j.kind == jObj and j.get("error") != nil and j["error"].isStr: j["error"].s else: ""
  if raw.isSentence: return raw
  let code = if j != nil and j.kind == jObj and j.get("code") != nil and j["code"].isStr: j["code"].s else: codeOf(status)
  errorWords(code)

proc unreachable*(host: string, port: int): string =
  ## a server this device could not connect to (joining, Sync now): plain words, the system's text goes to the log
  "Couldn't reach the server at " & host & ":" & $port & ". Check the address and that this device is on the plant's network."
