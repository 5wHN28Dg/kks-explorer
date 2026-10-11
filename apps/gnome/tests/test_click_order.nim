## A button's handler runs before anything else the main loop has ready (#147). It is deferred (ui.deferred: not
## inside the click, which may be an accessibility action), and it used to wait as an idle callback: a timer that
## was due ran first. The reload after a sync is such a timer, and it rebuilt the panel whose button had just been
## clicked; the handler then worked on widgets that were gone. No window and no display: only the main loop.
import std/[unittest, strutils]
import kksg/[gtk, ui]

proc turn(until: proc (): bool) =
  for _ in 0 ..< 1000:
    if until(): return
    g_main_context_iteration(nil, 1)

suite "a click and its handler":
  test "a timer that is due does not come between them":
    var order: seq[string]
    timeout(0, proc (): bool =          # due at once, like the reload 300 ms after a sync when the click arrives
      order.add "reload"
      false)
    let clicked = deferred(proc () = order.add "handler")
    clicked()                           # what GTK calls for "clicked"
    check order.len == 0                # not inside the click itself
    turn(proc (): bool = order.len == 2)
    check order == @["handler", "reload"]

  test "nor an idle callback queued before the click; two clicks keep their order":
    var order: seq[string]
    idle(proc () = order.add "idle")
    deferred(proc () = order.add "first")()
    deferred(proc () = order.add "second")()
    turn(proc (): bool = order.len == 3)
    check order == @["first", "second", "idle"]

  test "a handler that raises is reported, and the next one still runs":
    var said: seq[string]
    var ran = false
    errorHook = proc (text: string) = said.add text
    deferred(proc () = raise newException(ValueError, "boom"))()
    deferred(proc () = ran = true)()
    turn(proc (): bool = ran)
    errorHook = nil
    check ran
    check said.len == 1 and "boom" in said[0]
