## A button's handler runs from an idle callback (ui.onClick), and a timer can rebuild the part of the screen the
## button was in before that (#160): the handler then must not run at all. Its closure holds the old part's widgets
## (freed by then) and what the old part showed. Checked here for every way the app makes a button (button,
## iconButton, navRow, onClick) and for idleFor itself. It opens a window, so it is not in `nim test`:
##   cd apps/gnome && nim c -d:release -o:/tmp/kksgnome/stale_click e2e/stale_click.nim
##   e2e/headless.sh /tmp/kksgnome/stale_click
## Also here, for the same plumbing (#163): a second press before the first one's handler ran is dropped; a one-shot
## timer (`after`) runs once even when it fails; and the closures of idle callbacks and timers are released.
import std/[os, times]
import kksg/[gtk, ui]
proc g_signal_emit_by_name(inst: W, sig: cstring) {.importc, header: "<glib-object.h>", varargs.}
proc gtk_label_get_text(l: W): cstring {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_has_css_class(w: W, c: cstring): cint {.importc, header: "<gtk/gtk.h>".}

proc settle() =
  ## every queued idle callback (and whatever they queue)
  while g_main_context_iteration(nil, 0) != 0: discard

proc spin(ms: int) =
  ## the main loop for this long (timers come due)
  let till = epochTime() + ms / 1000
  while epochTime() < till:
    settle()
    sleep(2)

type Probe = ref object      ## held by a closure: gone when the closure is released
var probesFreed = 0
proc probeGone(p: Probe) = inc probesFreed
proc newProbe(): Probe = new(result, probeGone)

# GTK's own complaints (a failed assertion is logged, not raised), counted
var criticals = 0
proc g_log_set_default_handler(fn: pointer, data: pointer): pointer {.importc, header: "<glib.h>".}
proc g_log_default_handler(domain: cstring, level: cint, msg: cstring, data: pointer) {.importc, header: "<glib.h>".}
proc logged(domain: cstring, level: cint, msg: cstring, data: pointer) {.cdecl.} =
  if (level and 8) != 0: inc criticals       # G_LOG_LEVEL_CRITICAL
  g_log_default_handler(domain, level, msg, data)
discard g_log_set_default_handler(cast[pointer](logged), nil)

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
  # two presses before the first one's handler ran: one press (the handler ran twice: "Add the photo" and
  # "Propose", which close their dialog, sent twice). The next press counts again, also after a press whose
  # handler was dropped because the button had left the window.
  for mk in makers:
    var ran = 0
    let (top, btn) = mk.make(proc () = inc ran)
    panel.add top
    g_signal_emit_by_name(btn, "clicked")
    g_signal_emit_by_name(btn, "clicked")
    settle()
    doAssert ran == 1, mk.name & ": two presses before the handler ran it " & $ran & " times"
    g_signal_emit_by_name(btn, "clicked")
    settle()
    doAssert ran == 2, mk.name & ": a press after the handler had run was dropped"
    g_object_ref(top)
    g_signal_emit_by_name(btn, "clicked")
    gtk_box_remove(panel, top)      # out of the window: this press's handler does not run
    settle()
    doAssert ran == 2
    panel.add top                   # (a page kept and shown again, like the setup screen's)
    g_object_unref(top)
    g_signal_emit_by_name(btn, "clicked")
    settle()
    doAssert ran == 3, mk.name & ": a button shown again stayed dead after a dropped press"
    panel.clear()
    inc checked
  # a one-shot timer runs once, also when it fails. (As a `timeout` whose callback returns false at its end, the
  # reload after a change came back every 300 ms for good once it had raised.)
  block:
    var ran = 0
    after(5, proc () =
      inc ran
      raise newException(ValueError, "fails (on purpose: this line in the output is the test's)"))
    var defect = 0
    after(5, proc () =
      inc defect
      var none: seq[int]
      discard none[defect])       # IndexDefect
    var fine = 0
    after(5, proc () = inc fine)
    spin(120)
    doAssert ran == 1, "a one-shot timer that raised ran " & $ran & " times"
    doAssert defect == 1, "a one-shot timer that raised a Defect ran " & $defect & " times"
    doAssert fine == 1
    # a repeating timer keeps going after an error, and stops when it says so
    var rep = 0
    timeout(5, proc (): bool =
      inc rep
      if rep == 2: raise newException(ValueError, "fails once (on purpose)")
      rep < 4)
    spin(200)
    doAssert rep == 4, "a repeating timer ran " & $rep & " times (an error at the 2nd, stops itself at the 4th)"
    inc checked
  # the closures of idle callbacks and timers are released once they have run (or were dropped): before, each
  # was kept for ever with all it holds
  block:
    probesFreed = 0
    let l = label("here")
    panel.add l
    # (each in a proc of its own: closures made in one proc share one environment, which lives as long as any of
    # them does)
    proc viaIdle() =
      let p = newProbe()
      idle(proc () = discard p)
    proc viaAfter() =
      let p = newProbe()
      after(5, proc () = discard p)
    proc viaTimeout() =
      let p = newProbe()
      timeout(5, proc (): bool =
        discard p
        false)
    proc viaIdleFor() =
      let p = newProbe()
      idleFor(l, proc () = discard p)
    proc viaIdleForGone() =
      let p = newProbe()
      let gone = label("gone")
      panel.add gone
      idleFor(gone, proc () = discard p)
      gtk_box_remove(panel, gone)
    proc viaButton() =
      let p = newProbe()
      let b = button("Press", "", proc () = discard p)
      panel.add b
      g_signal_emit_by_name(b, "clicked")
    proc queue() =
      viaIdle()
      viaAfter()
      viaTimeout()
      viaIdleFor()
      viaIdleForGone()
      viaButton()
    queue()
    spin(120)
    GC_fullCollect()
    doAssert probesFreed == 5, $probesFreed & " of 5 closures were released after they ran"   # (f's: the button's own)
    panel.clear()
    GC_fullCollect()
    doAssert probesFreed == 6, "a button's handler was not released with the button"
    inc checked
  # An area emptied with the keyboard focus in it (the tag panel after Save): the window gives the focus up first
  # (ui.clear, gtk.leaveFocus). Left to GTK, it moved the focus on at the next frame, and when that landed on a
  # selectable label (the panel's heading) GTK logged "gtk_widget_is_ancestor: assertion 'GTK_IS_WIDGET (widget)'
  # failed" (it compared the freed button with the label). KKS_TEST_RAW_REMOVE: the same without leaveFocus, to
  # see that message here.
  block:
    let area = vbox()
    panel.add area
    proc empty() =
      if getEnv("KKS_TEST_RAW_REMOVE").len > 0:
        var c = gtk_widget_get_first_child(area)
        while c != nil:
          let n = gtk_widget_get_next_sibling(c)
          gtk_box_remove(area, c)
          c = n
      else: area.clear()
    proc build() =
      # as the tag panel: a heading that can be selected, then a form in a group, its Save rebuilding it all
      empty()
      area.add label("11LAB70AA501", "title-2", selectable = true)
      let g = group("Location and notes")
      let e = entryRow("Notes", "typed")
      adw_preferences_group_add(g, e)
      let btns = hbox(8)
      btns.add button("Save", "suggested-action", proc () = build())
      adw_preferences_group_add(g, btns)
      area.add g
    build()
    for round in 0 ..< 3:
      spin(80)
      var save: W = nil
      proc find(w: W) =
        var c = gtk_widget_get_first_child(w)
        while c != nil:
          if gtk_widget_has_css_class(c, "suggested-action") != 0: save = c
          find(c)
          c = gtk_widget_get_next_sibling(c)
      find(area)
      doAssert save != nil and gtk_widget_grab_focus(save) != 0
      spin(80)
      doAssert gtk_root_get_focus(win) == save
      g_signal_emit_by_name(save, "clicked")
      spin(300)                     # the handler, then frames: GTK's own move of the focus would come here
    doAssert criticals == 0, "GTK logged " & $criticals & " failed assertions after a focused area was emptied"
    panel.clear()
    inc checked
  doAssert checked == 2 * makers.len + 6

app.on("activate", proc () =
  # (a failed check must end the run: the signal's trampoline would log it and carry on)
  try: checks()
  except CatchableError, Defect:
    stderr.writeLine "FAILED: " & getCurrentExceptionMsg()
    quit(1)
  quit(0))
discard g_application_run(app, 0, nil)
quit("the checks did not run", 1)
