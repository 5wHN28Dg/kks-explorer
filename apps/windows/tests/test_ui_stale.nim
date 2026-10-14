## The Windows app's controls and their handlers (ui.nim; #162): a handler runs after the control's notification has
## returned, from a posted message. What can come between the two on Windows, and what a handler does when its page
## was rebuilt in between: nothing. Before, it ran for the page that had gone: its fields read as empty, so an edit
## form's Save sent every field as cleared. Also: control ids are 16 bits in WM_COMMAND, and handlers were kept by id.
## Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it); runs on Windows:
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_ui_stale.exe apps/windows/tests/test_ui_stale.nim
import std/[unittest, os]
import kkswin/[w32, ui]

const H = "<windows.h>"
proc GetDlgCtrlID(h: HWND): int32 {.importc, stdcall, header: H.}
proc SetForegroundWindow(h: HWND): BOOL {.importc, stdcall, header: H, discardable.}
proc GetQueueStatus(flags: UINT): DWORD {.importc, stdcall, header: H.}
const
  WM_SETTEXT = 0x000C'u32
  BM_CLICK = 0x00F5'u32
  PM_REMOVE = 1'u32
  WM_TEST_POSTED = WM_APP + 7       # what the drawing's UI Automation provider posts when a tag is invoked
  WM_TEST_SENT = WM_APP + 9

var
  main: HWND
  order: seq[string]
  onPosted, onTimer: proc ()

proc mainProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  case m
  of WM_COMMAND:
    if dispatchCommand(wp, lp): return 0
  of WM_KKS_LATER:
    runLater()
    return 0
  of WM_TEST_POSTED:
    if onPosted != nil: onPosted()
    return 0
  of WM_TEST_SENT:
    order.add "sent"
    return 0
  of WM_TIMER:
    KillTimer(h, uint(wp))
    order.add "timer"
    if onTimer != nil: onTimer()
    return 0
  else: discard
  DefWindowProcW(h, m, wp, lp)

proc pump() =
  ## everything waiting, in the order GetMessage hands it out (the app's loop)
  var msg: MSG
  while PeekMessageW(addr msg, nil, 0, 0, PM_REMOVE) != 0:
    TranslateMessage(addr msg)
    DispatchMessageW(addr msg)

proc press(b: HWND) =
  ## the notification a pressed button sends its parent (the same message whether the mouse, the keyboard, the
  ## dialog manager or UI Automation's Invoke pressed it)
  SendMessageW(GetParent(b), WM_COMMAND, WPARAM((int(GetDlgCtrlID(b)) and 0xFFFF) or (int(BN_CLICKED) shl 16)), cast[LPARAM](b))

proc notifyList(l: HWND, row: int, code: uint32) =
  SendMessageW(l, LB_SETCURSEL, WPARAM(row), 0)
  SendMessageW(GetParent(l), WM_COMMAND, WPARAM((int(GetDlgCtrlID(l)) and 0xFFFF) or (int(code) shl 16)), cast[LPARAM](l))

proc sender(h: HWND) {.thread.} =
  SendMessageW(h, WM_TEST_SENT, 0, 0)

hinst = GetModuleHandleW(nil)
makeFonts(96)
block:
  let cls = newWideCString("KKSTestMain")
  var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: mainProc, hInstance: hinst,
                       hbrBackground: GetSysColorBrush(COLOR_WINDOW), lpszClassName: cls)
  discard RegisterClassExW(addr wc)
  main = CreateWindowExW(WS_EX_CONTROLPARENT, cls, newWideCString("ui test"), WS_OVERLAPPEDWINDOW, 0, 0, 600, 500,
                         nil, nil, hinst, nil)
  doAssert main != nil
  laterWindow = main
  ShowWindow(main, SW_SHOW)
  SetForegroundWindow(main)
let page = newPage(main)
MoveWindow(page.hwnd, 0, 0, 580, 460, 1)
pump()

# an edit form as the tag panel builds one: a field, and a Save that reads it when it runs
var
  saved: seq[string]
  builds = 0
  saveBtn, valueField: HWND

proc buildForm() =
  page.clear()
  inc builds
  let e = page.field("Notes", "pump room")
  valueField = e
  saveBtn = page.buttons(("Save", proc () {.closure.} = saved.add e.text))[0]
  page.layout()

proc fresh() =
  pump()
  order.setLen(0)
  saved.setLen(0)
  onPosted = nil
  onTimer = nil
  beforeHandler = nil
  buildForm()
  builds = 0

suite "the order of events between a click and its handler":
  test "a timer that is already due comes after the handler (posted messages before WM_TIMER)":
    fresh()
    SetTimer(main, 77, 1, nil)
    sleep(60)                               # due before the click arrives
    press(saveBtn)
    pump()
    check saved == @["pump room"]
    check order == @["timer"]
    # the handler ran first: a timer's rebuild (the reload after a sync) found it done
    fresh()
    var seen = -1
    onTimer = proc () = seen = saved.len
    SetTimer(main, 77, 1, nil)
    sleep(60)
    press(saveBtn)
    pump()
    check seen == 1

  test "a thread timer (afterMs: the photo queue) that is already due comes after the handler too":
    fresh()
    var seen = -1
    discard afterMs(1, proc () = seen = saved.len)
    sleep(60)
    press(saveBtn)
    pump()
    check seen == 1

  test "a message sent from another thread comes before the handler (UI Automation's calls arrive this way)":
    fresh()
    var th: Thread[HWND]
    createThread(th, sender, main)
    # it waits in SendMessage: this thread has not looked at its queue yet (QS_SENDMESSAGE says one is waiting)
    var waiting = false
    for _ in 0 ..< 500:
      if (GetQueueStatus(0x0040) shr 16) != 0:
        waiting = true
        break
      sleep(10)
    require waiting
    check order.len == 0
    press(saveBtn)                          # the click: its handler is queued behind a posted message
    check saved.len == 0
    onPosted = nil
    var msg: MSG
    # the loop asks for the queued handler's message: the sent message is delivered before it is handed out
    var got = false
    for _ in 0 ..< 100:
      if PeekMessageW(addr msg, nil, 0, 0, PM_REMOVE) == 0: break
      if msg.message == WM_KKS_LATER:
        got = true
        break
      DispatchMessageW(addr msg)            # (anything else the system posted)
    require got
    check order == @["sent"]
    check saved.len == 0
    DispatchMessageW(addr msg)
    check saved == @["pump room"]
    joinThread(th)

suite "a handler whose page was rebuilt before it ran":
  test "the handler runs once when nothing came in between":
    fresh()
    press(saveBtn)
    check saved.len == 0                    # not inside the notification
    pump()
    check saved == @["pump room"]

  test "a real click (BM_CLICK: the button's own notification) reaches its handler":
    fresh()
    SendMessageW(saveBtn, BM_CLICK, 0, 0)
    pump()
    check saved == @["pump room"]

  test "a message posted before the click rebuilds the page: Save does nothing":
    fresh()
    onPosted = proc () = buildForm()
    PostMessageW(main, WM_TEST_POSTED, 0, 0)
    let old = saveBtn
    press(old)
    pump()
    check builds == 1
    check IsWindow(old) == 0
    check saved.len == 0                    # (it read the destroyed field as "" and would have sent that)
    # the page now on screen works
    press(saveBtn)
    pump()
    check saved == @["pump room"]

  test "two presses queued before the first ran, the first rebuilds: the second does nothing":
    fresh()
    var runs = 0
    var b: HWND
    proc build() =
      page.clear()
      let e = page.field("Notes", "pump room")
      b = page.buttons(("Save", proc () {.closure.} =
        inc runs
        saved.add e.text
        build()))[0]
    build()
    press(b)
    press(b)
    pump()
    check runs == 1
    check saved == @["pump room"]
    press(b)
    pump()
    check runs == 2

  test "something queued between the click and its handler (the app's test hook) rebuilds the page":
    fresh()
    beforeHandler = proc () = later(proc () = buildForm())
    press(saveBtn)
    beforeHandler = nil
    pump()
    check builds == 1
    check saved.len == 0

  test "a list's selection and activation, and its Open button":
    fresh()
    var got: seq[string]
    var l: HWND
    proc build(rows: seq[string]) =
      page.clear()
      l = page.list(rows, 100, onSelect = (proc (i: int) = got.add "select " & rows[i]),
                    onActivate = (proc (i: int) = got.add "open " & rows[i]), openLabel = "Open")
    build(@["a", "b", "c"])
    notifyList(l, 1, LBN_SELCHANGE)
    notifyList(l, 2, LBN_DBLCLK)
    pump()
    check got == @["select b", "open c"]
    got.setLen(0)
    # rebuilt with other rows before the handlers ran: row 1 is another thing now, nothing runs
    onPosted = proc () = build(@["x", "y", "z"])
    PostMessageW(main, WM_TEST_POSTED, 0, 0)
    notifyList(l, 1, LBN_SELCHANGE)
    notifyList(l, 1, LBN_DBLCLK)
    pump()
    check got.len == 0
    notifyList(l, 1, LBN_DBLCLK)
    pump()
    check got == @["open y"]

  test "Enter on a focused list":
    fresh()
    var got: seq[string]
    var l: HWND
    proc build(rows: seq[string]) =
      page.clear()
      l = page.list(rows, 100, onActivate = (proc (i: int) = got.add "open " & rows[i]))
    build(@["a", "b"])
    SetFocus(l)
    require GetFocus() == l
    SendMessageW(l, LB_SETCURSEL, 1, 0)
    check activateFocused()
    pump()
    check got == @["open b"]
    got.setLen(0)
    SetFocus(l)
    check activateFocused()
    build(@["x", "y"])
    pump()
    check got.len == 0

  test "a control outside a page that was destroyed before its handler ran":
    fresh()
    var runs = 0
    let (b, _) = control(main, "BUTTON", "Tab", WS_TABSTOP or BS_PUSHBUTTON)
    onClick(b, proc () = inc runs)
    press(b)
    pump()
    check runs == 1
    press(b)
    DestroyWindow(b)
    pump()
    check runs == 1
    forgetControl(b)

suite "control ids":
  test "after more controls than 16 bits count, a new button runs its own handler, not an old control's":
    fresh()
    var oldRuns, newRuns = 0
    # a control that stays (a tab's button)
    let (tab, _) = control(main, "BUTTON", "Tab", WS_TABSTOP or BS_PUSHBUTTON)
    onClick(tab, proc () = inc oldRuns)
    let tabId = int(GetDlgCtrlID(tab)) and 0xFFFF
    # pages rebuilt again and again (every sync round rebuilds the side and the panel), until the next control's id
    # is the tab's in WM_COMMAND's 16 bits
    var n = 0
    while true:
      let (c, _) = control(page.hwnd, "STATIC", "x", SS_LEFT)
      let id = int(GetDlgCtrlID(c))
      DestroyWindow(c)
      inc n
      require n < 200_000
      if ((id + 1) and 0xFFFF) == tabId or (id == 0xFFFF and tabId == 1001): break
    check n > 60_000
    page.clear()
    let b = page.buttons(("Save", proc () {.closure.} = inc newRuns))[0]
    check (int(GetDlgCtrlID(b)) and 0xFFFF) == tabId
    press(b)
    pump()
    check newRuns == 1
    check oldRuns == 0
    press(tab)
    pump()
    check oldRuns == 1
    DestroyWindow(tab)
    forgetControl(tab)

suite "what was typed into a page":
  test "edited: a field a person can type into differs from what it was made with":
    fresh()
    page.clear()
    check not page.edited
    let ro = page.field("System", "LAB", readonly = true)
    let e = page.field("Floor", "3")
    let m = page.multiField("Notes", "one\ntwo")
    check not page.edited
    discard sendText(ro, WM_SETTEXT, 0, "other")     # not a person's typing: the field is read-only
    check not page.edited
    e.setText("4")
    check page.edited
    e.setText("3")
    check not page.edited
    m.setText("one\r\ntwo\r\nthree")
    check page.edited
    page.clear()
    check not page.edited

  # #168: a page made again by one of its own buttons (the tag panel's Edit, Confirm valve type …) kept nothing typed
  proc form(notes = "", custom = "x"): seq[HWND] =
    page.clear()
    result.add page.field("KKS (with suffix)", "11LAB70AA501")
    result.add page.field("Custom field value", custom)
    result.add page.field("Custom field value", custom)
    result.add page.multiField("Notes", notes)

  test "keptText and restoreText: typed text goes back into the new page's field with the same label and start":
    fresh()
    var f = form()
    f[0].setText("11LAB70AA502")
    f[2].setText("second")              # the second of two fields with the same label and start
    f[3].setText("line one\r\nline two")
    let kept = page.keptText()
    check kept.len == 3
    f = form()
    check not page.edited
    check page.restoreText(kept).len == 0
    check f[0].text == "11LAB70AA502"
    check f[1].text == "x"
    check f[2].text == "second"
    check f[3].text == "line one\r\nline two"
    check page.edited                   # still counts as typed: a sync does not rebuild over it
    page.clear()

  test "keptText leaves out what a button sent; restoreText returns what found no field":
    fresh()
    var f = form()
    f[0].setText("11LAB70AA502")
    f[3].setText("my notes")
    let kept = page.keptText(drop = [f[0]])       # the reading was sent: its field starts again from the data
    check kept.len == 1 and kept[0].name == "Notes"
    f = form(notes = "changed underneath")        # the stored notes changed meanwhile
    let lost = page.restoreText(kept)
    check lost.len == 1 and lost[0].text == "my notes"    # not put over the new value: Save would send it as a change of it
    check f[3].text == "changed underneath"
    check f[0].text == "11LAB70AA501"
    check not page.edited
    page.clear()

DestroyWindow(main)
