## A button's handler runs from an idle callback (ui.onClick), and a timer can rebuild the part of the screen the
## button was in before that (#160): the handler then must not run at all. Its closure holds the old part's widgets
## (freed by then) and what the old part showed. Checked here for every way the app makes a button (button,
## iconButton, navRow, onClick) and for idleFor itself. It opens a window, so it is not in `nim test`:
##   cd apps/gnome && nim c -d:release -o:/tmp/kksgnome/stale_click e2e/stale_click.nim
##   e2e/headless.sh /tmp/kksgnome/stale_click
import kksg/[gtk, ui]
proc g_signal_emit_by_name(inst: W, sig: cstring) {.importc, header: "<glib-object.h>", varargs.}
proc gtk_label_get_text(l: W): cstring {.importc, header: "<gtk/gtk.h>".}

proc settle() =
  ## every queued idle callback (and whatever they queue)
  while g_main_context_iteration(nil, 0) != 0: discard

let app = adw_application_new("org.kks.StaleClickTest", 32)

proc checks() =
  var checked = 0
  let win = adw_application_window_new(app)
  let panel = vbox()
  adw_application_window_set_content(win, panel)
  gtk_window_present(win)
  settle()

  type Maker = tuple[name: string, make: proc (fn: proc ()): tuple[top, btn: W]]
  proc rowButton(row: W): W =
    ## navRow's "go" button: the row's activatable widget
    proc adw_action_row_get_activatable_widget(r: W): W {.importc, header: "<adwaita.h>".}
    adw_action_row_get_activatable_widget(row)
  let makers: seq[Maker] = @[
    ("button", proc (fn: proc ()): tuple[top, btn: W] =
      let b = button("Save", "", fn)
      (b, b)),
    ("iconButton", proc (fn: proc ()): tuple[top, btn: W] =
      let b = iconButton("window-close-symbolic", "Close", fn)
      (b, b)),
    ("onClick", proc (fn: proc ()): tuple[top, btn: W] =
      let b = button("Edit", "flat")
      b.onClick(fn)
      (b, b)),
    ("navRow", proc (fn: proc ()): tuple[top, btn: W] =
      let r = navRow("Sample sheet", "3 tags", "Open Sample sheet", fn)
      (r, rowButton(r)))]

  for mk in makers:
    # the button still there: its handler runs, once
    block:
      var ran = 0
      let entry = entryRow("Notes", "typed")
      let (top, btn) = mk.make(proc () =
        doAssert text(entry) == "typed"
        inc ran)
      panel.add entry, top
      g_signal_emit_by_name(btn, "clicked")
      doAssert ran == 0, mk.name & ": the handler waits for the idle callback (never inside the click)"
      settle()
      doAssert ran == 1, mk.name & ": the handler of a button that is still there ran " & $ran & " times"
      panel.clear()
    # the panel rebuilt between the click and the handler: the handler does not run
    block:
      var ran = 0
      let entry = entryRow("Notes", "typed")
      let (top, btn) = mk.make(proc () =
        inc ran
        discard text(entry))        # (a freed widget by now: what crashed the app)
      panel.add entry, top
      g_signal_emit_by_name(btn, "clicked")
      panel.clear()                 # what buildPanel, a follower's rebuild and the live page's do
      panel.add entryRow("Notes", "another tag's")
      settle()
      doAssert ran == 0, mk.name & ": the handler ran after its panel was rebuilt"
      panel.clear()
    # a rebuild queued before the handler (the order the app's test hook forces): the same
    block:
      var ran = 0
      let (top, btn) = mk.make(proc () = inc ran)
      panel.add top
      beforeClickHandler = proc () = panel.clear()
      g_signal_emit_by_name(btn, "clicked")
      settle()
      beforeClickHandler = nil
      doAssert ran == 0, mk.name & ": the handler ran after a rebuild that was queued before it"
    inc checked

  # idleFor itself: runs for a widget in the window, not for one taken out, and the widget is not freed under it
  block:
    var ran = 0
    let l = label("here")
    panel.add l
    idleFor(l, proc () = inc ran)
    settle()
    doAssert ran == 1
    idleFor(l, proc () = inc ran)
    panel.clear()
    settle()
    doAssert ran == 1, "idleFor ran for a widget that had left the window"
    inc checked
  # a handler that fails with a Defect ran once, not again and again (and its button was released once)
  block:
    var ran = 0
    let b = button("Fails", "", proc () =
      inc ran
      var none: seq[int]
      discard none[ran])          # IndexDefect
    panel.add b
    g_signal_emit_by_name(b, "clicked")
    for _ in 0 ..< 5: discard g_main_context_iteration(nil, 0)
    doAssert ran == 1, "a handler that raised a Defect ran " & $ran & " times"
    panel.clear()
    inc checked
  # a widget held for a later callback (a dialog's answer, the banner's button): alive, and known to be gone
  block:
    let l = label("held")
    panel.add l
    let h = hold(l)
    doAssert h.shown
    panel.clear()
    doAssert not h.shown, "a held widget that left the window still counts as shown"
    gtk_label_set_text(l, "still a widget")      # (freed without the hold)
    doAssert str(gtk_label_get_text(l)) == "still a widget"
    inc checked
  doAssert checked == makers.len + 3

app.on("activate", proc () =
  # (a failed check must end the run: the signal's trampoline would log it and carry on)
  try: checks()
  except CatchableError, Defect:
    stderr.writeLine "FAILED: " & getCurrentExceptionMsg()
    quit(1)
  quit(0))
discard g_application_run(app, 0, nil)
quit("the checks did not run", 1)
