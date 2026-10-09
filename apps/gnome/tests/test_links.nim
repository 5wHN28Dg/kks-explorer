## Links between drawings in the GNOME app: what the plant data's names do in toasts and in the choice dialog
## (review findings on the links PR).
import std/unittest
import kks/json
import kksg/[gtk, ui, links]

proc target(name: string, same = false): JNode =
  newObj(@[("sheet", newStr("s")), ("sheet_name", newStr(name)), ("same_sheet", newBool(same))])

suite "links":
  test "a toast is plain text: a sheet name with & or a tag is shown as written, not read as markup":
    let t = newToast("Connector C16 on Drains & vents <a href=\"x\">LP</a>")
    check adw_toast_get_use_markup(t) == 0
    check $adw_toast_get_title(t) == "Connector C16 on Drains & vents <a href=\"x\">LP</a>"
  test "the choice dialog's buttons can be told apart, and a _ in a name stays a _":
    check responseLabels(@[target("Drains"), target("FW"), target("Drains")]) ==
          @["Drains (1 of 2)", "FW", "Drains (2 of 2)"]
    check responseLabels(@[target("LP_HP"), target("x", same = true)]) == @["LP__HP", "elsewhere on this sheet"]
