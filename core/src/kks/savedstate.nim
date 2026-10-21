## The saved replayed state (PROTOCOL-v2 §15b, decision 0061): what the replay of a node's log computed, kept in its
## store so that a start reads it back instead of replaying every entry again. It is only ever a copy: the log stays
## the truth, and a saved state that does not match the log it is opened with, or that this program did not write,
## is ignored and the log replayed.
##
## Bytes: "kks-saved-state-v1\n", the program's replay code id (32 hex), the input digest (64 hex), the payload's
## SHA-256 (64 hex), then the payload (binser.nim): the run (replay.putRun) and the chain rules' ignored entries.

import std/[algorithm, tables]
import json, crypto, util, replay, binser

const
  Magic = "kks-saved-state-v1\n"
  InputDomain = "kks-saved-state-input-v1\n"

proc fnv(s: string, seed: uint64): uint64 =
  result = seed
  for c in s:
    result = (result xor uint64(ord(c))) * 0x100000001b3'u64

proc codeIdOf(src: string): string =
  ## 128 bits from two FNV-1a passes: tells programs apart, not a security check (the store's seal is)
  const digits = "0123456789abcdef"
  for h in [fnv(src, 0xcbf29ce484222325'u64), fnv(src, 0x84222325cbf29ce4'u64)]:
    for i in countdown(15, 0): result.add digits[int((h shr (4 * i)) and 0xf)]

const CodeId* = codeIdOf(staticRead("replay.nim") & "\0" & staticRead("json.nim") & "\0" & staticRead("proto.nim") &
                         "\0" & staticRead("crypto.nim") & "\0" & staticRead("util.nim") & "\0" &
                         staticRead("binser.nim") & "\0" & staticRead("savedstate.nim") & "\0" &
                         staticRead("node.nim") & "\0" & NimVersion)
  ## The replay's own code, what feeds it (node.nim's rebuild), this format's, and the compiler (its standard
  ## library): a program whose replay could compute anything else has another id, so an update never reads what an
  ## older version saved.

proc inputDigest*(p: Provider, root: string, entryIds, evidenceIds: openArray[string]): string =
  ## SHA-256 (hex) of what the replay reads: the trust anchor, the IDs of every entry held and of the fork evidence
  ## (an entry's ID is the hash of its content, so the IDs name the content).
  var e = @entryIds
  var v = @evidenceIds
  e.sort(system.cmp)
  v.sort(system.cmp)
  var s = InputDomain & root & "\n" & $e.len & "\n"
  for id in e: s.add id & "\n"
  s.add $v.len & "\n"
  for id in v: s.add id & "\n"
  hex(p.sha256(s.toBytes))

proc encodeSaved*(p: Provider, digest: string, run: Run, chainIgnored: OrderedTable[string, string]): string =
  var w = Writer()
  w.putRun(run)
  w.put(chainIgnored)
  Magic & CodeId & digest & hex(p.sha256(w.buf.toOpenArrayByte(0, w.buf.high))) & w.buf

proc decodeSaved*(p: Provider, data, digest: string): (Run, OrderedTable[string, string]) =
  ## -> (run, chain-ignored); SavedStateError when it was written by another program, for another log, or is damaged
  let head = Magic.len + CodeId.len + 128
  if data.len < head or data[0 ..< Magic.len] != Magic: raise newException(SavedStateError, "saved state: not one")
  if data[Magic.len ..< Magic.len + CodeId.len] != CodeId:
    raise newException(SavedStateError, "saved state: written by another version")
  if data[Magic.len + CodeId.len ..< head - 64] != digest:
    raise newException(SavedStateError, "saved state: for another log")
  if hex(p.sha256(data.toOpenArrayByte(head, data.high))) != data[head - 64 ..< head]:
    raise newException(SavedStateError, "saved state: damaged")
  var rd = Reader(data: data, pos: head)
  result[0] = rd.getRun()
  rd.get(result[1])
  rd.done()
