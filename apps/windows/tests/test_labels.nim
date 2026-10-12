## A button shows its text literally (apps/windows/src/kkswin/labels.nim): course page titles and answers come from
## data and contain "&". Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it):
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_labels.exe apps/windows/tests/test_labels.nim
import std/unittest
import ../src/kkswin/labels

suite "button labels":
  test "an ampersand is the character, not a shortcut marker":
    check buttonLabel("5 · Strain gauges & RTDs →") == "5 · Strain gauges && RTDs →"
    check buttonLabel("P&ID") == "P&&ID"
    check buttonLabel("a && b") == "a &&&& b"
  test "text without one is unchanged":
    check buttonLabel("Open the course") == "Open the course"
    check buttonLabel("") == ""
