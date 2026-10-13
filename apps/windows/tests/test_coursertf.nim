## The courses' RTF (apps/windows/src/kkswin/coursertf.nim): what is bold, where a scenario's values stand, what
## keeps a number on one line with its unit, the escaping, and two lines that are plain text (a question's heading, a
## test's result). What RichEdit then does with it: test_courserich.nim. Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it):
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
    check "No. Two others agree." in f.rtf and "{\\f1 24.1\\~V}" in f.rtf    # a number: the mono face, the text's size
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

  test "a number stays with its unit: no-break spaces, and a joiner where RichEdit would end a line":
    const J = "{\\fs2\\~}"
    # up to 20 characters: whole (it was "0.385 \u937? per \u176?C", and "0.385" ended a line)
    check numRun("0.385 Ω per °C") == "0.385\\~\\u937?\\~per\\~\\u176?" & J & "C"
    check numRun("4–20 mA") == "4\\u8211?20\\~mA"
    check numRun("12 kg/s") == "12\\~kg/s"
    check numRun("pk-pk = 2 × pk") == "pk-" & J & "pk\\~=\\~2\\~\\u215?\\~pk"
    check numRun("12 × 10⁻⁶ /°C") == "12\\~\\u215?\\~10" & J & "\\u8315?" & J & "\\u8310?\\~/" & J & "\\u176?" & J & "C"
    check numRun("646 kg/m³") == "646\\~kg/m\\u179?"
    # longer: a formula or a phrase wraps at its spaces, but a number keeps the unit after it
    check numRun("V at transmitter = supply − I × R") == "V at transmitter = supply \\u8722? I \\u215? R"
    check numRun("1 mm per metre per 100 K") == "1\\~mm per metre per 100\\~K"
    check numRun("error % = (measured − ideal) ÷ span × 100") ==
      "error\\~% = (measured \\u8722? ideal) \\u247? span \\u215? 100"
    check numRun("{a} \\ b") == "\\{" & J & "a" & J & "\\}\\~\\\\\\~b"            # escaped as any course text
    # as the control holds it
    check numRun("200 °C", rtf = false) == "200\u00A0°\u00A0C"
    var f = Flow()
    f.runRtf(parseStrict("""["It is ", {"num": "24.1 V"}, ", see ", {"link": ["the ", {"num": "4–20 mA"}, " loop"], "to": {"page": "ma"}}]"""))
    check f.rtf == "It is {\\f1 24.1\\~V}, see {\\cf2 the {\\f1 4\\u8211?20\\~mA} loop}"
    check f.links == @[("the 4–20\u00A0mA loop", "page:ma")]         # a link is found in the control by its text

  test "a question's heading is shown as written":
    check questionHeading("Q7 · 4 · 4–20 mA", "choice", "") == "Q7 · 4 · 4–20 mA"        # it was "… 4–20 MA"
    check questionHeading("", "scenario", "Manual 5.2") == "Scenario   Manual 5.2"
    check questionHeading("", "order", "") == "Put in order"
    check questionHeading("", "choice", "") == "Practice"

  test "a test's result line: how many there are, then how many were right":
    check testResult(0, 0, 20) == "0 / 20 answered"            # it was "0 / 0 right"
    check testResult(0, 1, 20) == "0 / 1 right"
    check testResult(7, 9, 20) == "7 / 9 right"
    check testResult(17, 20, 20) == "17 / 20 right · finished"
