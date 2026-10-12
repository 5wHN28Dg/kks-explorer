## The courses' RTF (apps/windows/src/kkswin/coursertf.nim): what is bold, where a scenario's values stand, and the
## escaping. Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it):
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_coursertf.exe apps/windows/tests/test_coursertf.nim
import std/[unittest, strutils]
import kks/json
import ../src/kkswin/coursertf

suite "course text as RTF":
  test "a worked example: the case is bold, the steps are not":
    let w = parseStrict("""{"case": ["A loop reads 0 mA."], "steps": [[["Is it the process?"], ["No. Two others agree."]],
                           [["Supply"], ["You measure ", {"num": "24.1 V"}, "."]]]}""")
    var f = Flow()
    f.workedRtf(w, 2)
    check "{\\b A loop reads 0 mA.}\\par" in f.rtf
    # bold only ever as a group that closes again: none left on for what follows (it was "\pard\sa80\b …")
    check "\\b" notin f.rtf.replace("{\\b ", "")
    check "No. Two others agree." in f.rtf and "{\\f1 24.1 V}" in f.rtf       # a number: the mono face, the text's size
    var first = Flow()
    first.workedRtf(w, 1)
    check "Is it the process?" in first.rtf and "Supply" notin first.rtf
    var none = Flow()
    none.workedRtf(w, 0)
    check "Step 1" notin none.rtf

  test "a scenario's values start in one column, right of the longest name":
    let p = parseStrict("""[{"name": ["Loop current"], "value": ["0.0 mA"], "state": "act"},
                            {"name": ["Voltage at the transmitter terminals"], "value": ["24.0 V"], "state": ""},
                            {"name": ["Supply"], "value": ["24.0 V"], "state": "ok"}]""")
    var f = Flow()
    f.panelRtf(p)
    var stops: seq[string]
    for line in f.rtf.splitLines:
      if line.len == 0: continue
      let i = line.find("\\tx")
      check i >= 0 and "\\tab " in line
      if i >= 0: stops.add line[i + 3 ..< line.find('{', i)]
    check stops.len == 3 and stops[0] == stops[1] and stops[1] == stops[2]
    check parseInt(stops[0]) > 36 * 110          # wider than the 36 characters of the longest name
    check "\\cf4 0.0 mA" in f.rtf and "\\cf5 24.0 V" in f.rtf

  test "course text is escaped":
    check rtfEsc("250 Ω {a} \\ → µ") == "250 \\u937? \\{a\\} \\\\ \\u8594? \\u181?"
