## The replay's last pass is skipped when the cut rounds settled (replay.replayRun): the settled round's run must be
## the one the final pass would make, field for field, on every scenario of the shared vectors (revokes, forks,
## malformed bodies, reports included).
import std/[unittest, tables, sets, algorithm]
import kks/[json, replay]
import testprovider
import vectors

let P = testProvider()

proc fields(r: Run): seq[(string, string)] =
  ## everything a replay leaves that other code reads, as text
  result.add(("state", stateBytes(r.state)))
  var h = newArr()
  for x in r.history: h.elems.add x
  result.add(("history", toText(h)))
  var d = newObj()
  for k, v in r.decisions: d.fields.add((k, v))
  result.add(("decisions", toText(d)))
  var c = newObj()
  for k, v in r.comments: c.fields.add((k, newArr(v)))
  result.add(("comments", toText(c)))
  var a: seq[string]
  for k, v in r.authors: a.add k & "=" & v
  a.sort(system.cmp)
  result.add(("authors", $a))
  var o: seq[string]
  for k, v in r.eqBy: o.add k & "=" & $v
  for k, v in r.reviewBy: o.add "review " & k & "=" & $v
  o.sort(system.cmp)
  result.add(("owners", $o))
  var cu: seq[string]
  for k, v in r.cuts: cu.add k & "=" & $v
  cu.sort(system.cmp)
  result.add(("cuts", $cu))

suite "the settled round's run is the final pass's":
  test "every scenario of the vectors":
    var n = 0
    for file in ["v2-replay.json", "v2-malformed.json", "v2-reports.json"]:
      for s in loadVectors(file)["scenarios"].elems:
        forceFinalPass = true
        let full = P.replayRun(s["entries"].elems, s["root"].s)
        forceFinalPass = false
        let quick = P.replayRun(s["entries"].elems, s["root"].s)
        check full.run != quick.run          # (two runs were made: the comparison means something)
        check fields(quick.run) == fields(full.run)
        check quick.chainIgnored == full.chainIgnored
        check quick.run.ignored == full.run.ignored
        check quick.run.private == full.run.private and quick.run.reports == full.run.reports
        inc n
    check n >= 12
