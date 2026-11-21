## Walkdown for GNOME (M6 phase 5; decisions 0014, 0016, 0031): GTK 4 + libadwaita in Nim, the Nim core
## underneath. One thread: GLib's main loop runs GTK, and asyncdispatch (sync, mDNS) is driven from it.

import std/[asyncdispatch, os, strutils, tables, sets, math, times, posix, sequtils]
import kks/[json, api, applink]
import kks/model
import kksl/dbstore
import appstate, darkcolor, syncwords
import kksg/[gtk, ui, viewer, win, panel, sidepages, mark, manage, join, learn, multi, systems, coverage, links, photos, about]

const AppId = "io.github._5wHN28Dg.walkdown"

proc gObjectTypeName(o: W): cstring {.importc: "G_OBJECT_TYPE_NAME", header: "<glib-object.h>".}
proc gtk_button_get_label(b: W): cstring {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_get_cursor(w: W): W {.importc, header: "<gtk/gtk.h>".}
proc gdk_cursor_get_name(c: W): cstring {.importc, header: "<gtk/gtk.h>".}

proc doShowSheet(w: Win, id: string)
proc doSelectTag(w: Win, id: string, center: bool)

proc doSelectTag(w: Win, id: string, center: bool) =
  let (ok, t) = w.m.tagById(id)
  if not ok: return
  let again = id == w.selected and w.formOpen     # the tag whose form is open, picked again (on the drawing, in the
  w.selected = id                                 # search): shown, and its form left as it is
  w.v.selected = id
  if center:
    let (okS, si) = w.m.sheetById(t.sheet)
    let s = if okS and si.scale > 0: si.scale else: 2.0
    w.v.centerOn(t.bbox[0] / s, t.bbox[1] / s, t.bbox[2] / s, t.bbox[3] / s)
  if not again: w.buildPanel(t)
  adw_overlay_split_view_set_show_sidebar(w.panelSplit, 1)
  gtk_widget_queue_draw(w.v.widget)

proc doShowSheet(w: Win, id: string) =
  let (ok, si) = w.m.sheetById(id)
  if not ok: return
  w.sheet = id
  adw_window_title_set_title(w.sheetTitle, si.name.cstring)
  let (_, kkp) = w.a.file("sheets/" & id & ".kkp")
  # the levels are read when the viewer first wants each (at start only the one the fitted sheet needs), from the
  # plant data version shown now: a newer one that completes meanwhile has its own sheet (set again on reload)
  var shas: seq[string]
  for k in 0 ..< si.levels: shas.add w.a.fileSha("sheets/" & id & ".o" & $k & ".jxl")
  let a = w.a
  w.v.setSheet(si.name, kkp, si.raw, si.levels, proc (k: int): string =
    if shas[k].len > 0: a.store.blobGet(shas[k])
    else:                    # (not in the plant data: the program's own data folder, as the sheet's other files)
      let (okL, data) = a.file("sheets/" & id & ".o" & $k & ".jxl")
      if okL: data else: "")
  w.panelKey = ""       # setSheet took the open panel's valve outline away: the next reload draws the panel again
  w.v.tags = w.tagBoxes(id)
  w.setLinks()
  w.syncChosen()
  adw_navigation_split_view_set_show_content(w.split, 1)
  discard gtk_widget_grab_focus(w.v.widget)

proc fillSheets(w: Win) =
  ## Every reload comes here (each finished sync round): the rows are replaced only when what they say changed. A
  ## row replaced loses the keyboard's place and a press on it (GTK sends "clicked" 250 ms after a keyboard or
  ## accessibility activation, and onClick drops the handler of a button that has gone: #147, #160).
  var rows: seq[(string, string, string)]
  var key = ""
  for si in w.m.sheets:
    var n, review = 0
    for t in w.m.tagsOf(si.id):
      inc n
      if t.status == "review": inc review
    rows.add((si.id, si.name, $n & " tags" & (if review > 0: ", " & $review & " to review" else: "")))
    key.add si.id & "\x1f" & si.name & "\x1f" & rows[^1][2] & "\x1e"
  if key == w.sheetsKey and gtk_widget_get_first_child(w.sheetList) != nil: return
  leaveFocus(w.sheetList)
  gtk_list_box_remove_all(w.sheetList)
  for i1 in 0 ..< rows.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let (id, name, sub) = rows[i1]
      gtk_list_box_append(w.sheetList, navRow(name, sub, "Open " & name, proc () = w.showSheet(id)))
  w.sheetsKey = key

var
  followTheme: proc ()        ## the open main screen's "the theme changed" (Dark drawings set to follow it)
  themeWatched = false

proc resultsKey(w: Win, found: seq[Tag], covers: Table[string, string]): string =
  ## what the search results show: the tags found and each code's photo mark
  for t in found: result.add t.id & "\x1f" & t.full & "\x1f" & covers.getOrDefault(t.full, "none") & "\x1e"
  result.add $w.picking

proc runSearch(w: Win) =
  let q = text(w.searchEntry).strip
  leaveFocus(w.resultList)
  gtk_list_box_remove_all(w.resultList)
  w.v.hits.clear()
  if q.len == 0:
    gtk_widget_set_visible(w.resultList, 0)
    gtk_widget_queue_draw(w.v.widget)
    return
  let found = w.m.search(q)
  let items2 = toSeq(found)
  let covers = w.m.photoCovers       # each result's photo mark (one pass over the photos)
  w.resultsShown = w.resultsKey(found, covers)
  var marked = false
  for i2 in 0 ..< items2.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let t = items2[i2]
      let (okS, si) = w.m.sheetById(t.sheet)
      let title = if t.full.len > 0: t.full else: "(unread)"
      let id = t.id
      let sheet = t.sheet
      let picking = w.picking     # the select mode: a result toggles its tag (the keyboard's way to select)
      let r = navRow(title, w.m.kindName(t) & " · " & (if okS: si.name else: t.sheet),
        (if picking: "Select or unselect " else: "Show ") & title & " on " & (if okS: si.name else: t.sheet), proc () =
          if w.picking: w.pickResult(id)      # the open drawing stays (multi.nim)
          else: w.goToTag(sheet, id))
      if t.full.len > 0:
        adw_action_row_add_prefix(r, photoMark(covers.getOrDefault(t.full, "none")))
        marked = true
      gtk_list_box_append(w.resultList, r)
      w.v.hits.incl t.id
  if found.len == 0: gtk_list_box_append(w.resultList, row("Nothing found", "Try part of the code, or a word from the description"))
  if marked:      # what the marks mean: a last line that is not a result
    let lr = gtk_list_box_row_new()
    gtk_list_box_row_set_child(lr, photoLegend())
    gtk_list_box_row_set_activatable(lr, 0)
    gtk_list_box_row_set_selectable(lr, 0)
    gtk_widget_set_focusable(lr, 0)
    setAccessibleLabel(lr, "Photos: ring no photos, half disc equipment photo only, square tag plate photo only, disc equipment and tag plate photos")
    gtk_list_box_append(w.resultList, lr)
  gtk_widget_set_visible(w.resultList, 1)
  gtk_widget_queue_draw(w.v.widget)

proc statusText(w: Win): string =
  ## R20: reachable devices and the last successful sync, under the plant's name
  let snap = w.a.snapshot
  var reachable = 0
  var last = 0'i64
  let now = nowMs() div 1000
  for (_, d) in snap["devices"].fields:
    if d["last_ok"].kind == jInt and d["last_ok"].i > 0:
      last = max(last, d["last_ok"].i)
      if now - d["last_ok"].i < 300 and d["error"].isNull: inc reachable
  result = w.a.plantName
  # (offline, the banner says so: the line keeps the plant and when it last synced, #372)
  if not (uxOn("offline-state") and isOffline(snap, now)):
    result.add " · " & (if reachable == 0: "no device reachable" elif reachable == 1: "1 device reachable" else: $reachable & " devices reachable")
  if last > 0: result.add " · synced " & fromUnix(last).local.format("HH:mm")
  if snap["relay"].s == "online":
    let n = snap["relay_online"].i
    result.add " · internet: " & (if n == 1: "1 device" else: $n & " devices") & " online"
    case snap["relay_how"].s
    of "direct": result.add ", last sync direct"
    of "relay": result.add ", last sync through the relay"
    else: discard

const WaitingShownAfter = 15_000   ## ms a change waits while online before the banner shows it (a sync follows an edit)

proc showSyncState(w: Win) =
  ## the sidebar's subtitle, and the banners over the sheets and over the drawing (#372): "Offline", with the changes
  ## waiting to be sent; online, the changes that have waited a while. Read out when what they say changes.
  if w.status == nil: return
  adw_window_title_set_subtitle(w.status, w.statusText().cstring)
  if w.offlineBanners.len == 0: return
  let snap = w.a.snapshot
  let wt = waitingWords(waitingOf(snap))
  let offline = isOffline(snap, nowMs() div 1000)
  if wt.len == 0: w.waitingSince = 0
  elif w.waitingSince == 0: w.waitingSince = nowMs()
  let say = if offline: OfflineWord & (if wt.len > 0: " · " & wt else: "")
            elif wt.len > 0 and nowMs() - w.waitingSince >= WaitingShownAfter: wt
            else: ""
  # the drawing's banner always; the sheets' only when the window is too narrow to show both pages (one says it)
  let narrow = w.split != nil and adw_navigation_split_view_get_collapsed(w.split) != 0
  for i, b in w.offlineBanners:
    let on = say.len > 0 and (i == 1 or narrow or w.offlineBanners.len == 1)
    if say != w.bannerSaid:
      adw_banner_set_title(b, say.cstring)       # (empty while hidden: nothing stale for a screen reader)
      gtk_widget_set_tooltip_text(b, (if offline: OfflineHelp else: "").cstring)
    gtk_widget_set_visible(b, cint(on))
    adw_banner_set_revealed(b, cint(on))
  if say == w.bannerSaid: return
  let was = w.bannerSaid
  w.bannerSaid = say
  let words = if say.len > 0: say elif was.startsWith(OfflineWord): "Back online" else: "All changes sent"
  gtk_accessible_announce(w.offlineBanners[^1], words.cstring, 1)

proc tagGone(w: Win) =
  ## the tag whose panel is open is no longer there: the panel closes, and says why
  w.closePanel()
  w.toast("This tag is no longer on the drawing")

proc refresh(w: Win) =
  ## the data changed underneath (sync, an approval): reload, keep the open sheet and selection (R20)
  w.loadModel()
  w.fillSheets()
  # the search results follow (a photo arrived: its code's mark changes), made again only when what they show changed
  # (a list rebuilt at every sync round loses the presses on it, #147)
  # Not while the focus is on a result (a keyboard's or a screen reader's place would be lost: UI/UX audit of #401):
  # the next round after it leaves makes them again.
  if w.searchEntry != nil and gtk_widget_get_visible(w.resultList) != 0 and text(w.searchEntry).strip.len > 0 and
     not focusInside(w.resultList) and
     w.resultsKey(w.m.search(text(w.searchEntry).strip), w.m.photoCovers) != w.resultsShown: w.runSearch()
  if w.sheet.len > 0:
    w.v.tags = w.tagBoxes(w.sheet)
    w.setLinks()
    w.syncChosen()
    gtk_widget_queue_draw(w.v.widget)
  # The panel: never under an open form (it would lose what is typed: only its live parts are brought up to date,
  # and the rest when the form closes), and only when what it shows changed. Every finished sync round comes here,
  # and a panel replaced each time lost the keyboard's place in it and any button pressed just before: GTK sends
  # "clicked" 250 ms after a keyboard or accessibility activation, and not at all when the button has gone by then
  # (#147; the same reason as refreshLive).
  if w.selected.len > 0:
    if w.formOpen: w.panelLive()
    elif w.panelKey != w.modelKey:
      let (ok, t) = w.m.tagById(w.selected)
      if ok: w.buildPanel(t)
      else: w.tagGone()
  w.refreshLive()
  w.refreshFollowers()

proc sideRoot(w: Win): W =
  let side = vbox(0)
  w.searchEntry = gtk_search_entry_new()
  gtk_search_entry_set_placeholder_text(w.searchEntry, "Search KKS or description")
  setAccessibleLabel(w.searchEntry, "Search equipment by KKS code or description")
  margins(w.searchEntry, 8)
  w.searchEntry.on("search-changed", proc () = w.runSearch())
  side.add w.searchEntry
  let lists = vbox(12)
  margins(lists, 8)
  w.resultList = gtk_list_box_new()
  gtk_widget_add_css_class(w.resultList, "boxed-list")
  gtk_widget_set_visible(w.resultList, 0)
  w.sheetList = gtk_list_box_new()
  w.sheetsKey = ""
  gtk_widget_add_css_class(w.sheetList, "boxed-list")
  let more = gtk_list_box_new()
  gtk_widget_add_css_class(more, "boxed-list")
  gtk_list_box_set_selection_mode(more, GTK_SELECTION_NONE)
  more.gtk_list_box_append(navRow("Procedures", "Operation manual steps and their equipment", "Open the procedures", proc () =
    w.pushPage(w.proceduresPage(), "Procedures", "procs")))
  more.gtk_list_box_append(navRow("Equipment by system", "Every code on the drawings, by block, system and kind",
    "Open Equipment by system", proc () = w.pushPage(w.systemsPage(), "Equipment by system", "systems")))
  more.gtk_list_box_append(navRow("Coverage", "What is checked, placed and photographed, per sheet and system",
    "Open Coverage", proc () = w.pushPage(w.coveragePage(), "Coverage", "coverage")))
  more.gtk_list_box_append(navRow("Learning", "The courses, with your progress", "Open Learning", proc () =
    w.pushPage(w.learningPage(), "Learning", "learning")))
  more.gtk_list_box_append(navRow("Review queue", "Tag readings to confirm or correct", "Open the review queue", proc () =
    w.pushPage(w.reviewPage(), "Review queue", "review")))
  more.gtk_list_box_append(navRow("Connectors on this sheet", "Where the lines continue on other drawings",
    "Open the sheet's connectors", proc () = w.pushPage(w.connectorsPage(), "Connectors on this sheet", "links")))
  more.gtk_list_box_append(navRow("Notes on this sheet", "Markup text in the PDF", "Open the sheet's notes", proc () =
    w.pushPage(w.notesPage(), "Notes on this sheet", "notes")))
  more.gtk_list_box_append(navRow("Manage", if w.isAdmin: "Approvals, history, people, devices, account" else: "Your proposals, devices, account",
    "Open Manage", proc () = w.pushPage(w.managePage(), "Manage", "manage")))
  # floor filter (R5): floors in use
  let floorG = gtk_list_box_new()
  gtk_widget_add_css_class(floorG, "boxed-list")
  let combo = adw_combo_row_new()
  adw_preferences_row_set_title(combo, "Floor")
  var names = @["All floors"]
  let fl = w.floors()
  for f in fl: names.add(if f.allCharsInSet(Digits): "Floor " & f else: f)
  let arr = allocCStringArray(names)
  adw_combo_row_set_model(combo, gtk_string_list_new(arr))
  deallocCStringArray(arr)
  combo.onPtr("notify::selected", proc (p: W) =
    let i = int(adw_combo_row_get_selected(combo))
    w.floor = if i <= 0 or i > fl.len: "" else: fl[i - 1]
    w.applyHighlights()
    if w.floor.len > 0: w.toast($w.v.floorIds.len & " tags on " & names[i]))
  floorG.gtk_list_box_append(combo)
  lists.add w.resultList, label("Sheets", "heading"), w.sheetList, floorG, more
  side.add scrolled(lists)
  let sideTitle = adw_window_title_new("Walkdown", w.a.plantName.cstring)
  w.status = sideTitle
  let sideHeader = headerBar(sideTitle)
  adw_header_bar_pack_end(sideHeader, primaryMenu())     # (the first packed at the end is the outermost)
  adw_header_bar_pack_end(sideHeader, iconButton("view-refresh-symbolic", "Sync now", proc () =
    proc go() {.async.} =
      let n = await w.a.syncAll()
      w.toast(if n > 0: "Synced with " & $n & " device" & (if n == 1: "" else: "s") else: "No other device reached")
    asyncCheck go()))
  result = toolbarView(sideHeader, side)
  if uxOn("offline-state"):    # #372: offline is a state of its own, above the sheets (and over the drawing, below)
    let b = adw_banner_new("")
    gtk_widget_set_visible(b, 0)
    w.offlineBanners.add b
    adw_toolbar_view_add_top_bar(result, b)

proc mainScreen(w: Win): W =
  w.loadModel()
  w.sideNav = adw_navigation_view_new()
  adw_navigation_view_add(w.sideNav, adw_navigation_page_new_with_tag(w.sideRoot(), "Sheets", "root"))
  w.sideNav.onPtr("popped", proc (p: W) =
    # the procedure's page was closed: link mode's end has no page to draw again (sidepages.nim linkEnded)
    if w.procBox != nil and gtk_widget_is_ancestor(w.procBox.w, p) != 0: w.procBox = nil
    # leaving a procedure stops highlighting its equipment, unless link mode is on (it ends with Done)
    if w.activeProc.len > 0 and w.linkProc.len == 0:
      w.activeProc = ""
      w.applyHighlights())
  let sidebar = page(w.sideNav, "Sheets")
  # content: viewer + tag panel
  w.v = newViewer()
  # the Dark drawings setting, per device (this device's store, like sync_peers): follow the theme, always dark or
  # always light (darkcolor.nim)
  w.v.setDark(darkNow(darkModeOf(w.a.store.getMeta("dark_drawings")), adw_style_manager_get_dark(adw_style_manager_get_default()) != 0))
  w.showSheet = proc (id: string) = w.doShowSheet(id)
  w.selectTag = proc (id: string, center: bool) = w.doSelectTag(id, center)
  w.rebuildPanel = proc () =
    if w.selected.len > 0:
      w.loadModel()
      let (ok, t) = w.m.tagById(w.selected)
      if ok: w.buildPanel(t)
      else: w.tagGone()       # (removed, or decided "not a tag": a panel left as it was kept its form open for
                              # good, each Save sending again)
  w.reloadPanel = proc () =
    # Every rebuild that is not a form's own Save or Cancel comes here (a photo queued or sent, link mode starting
    # or ending, a change sent from the select mode). Before #163 these rebuilt the panel under an open form: what
    # was typed was gone, and a Save pressed at that moment did nothing.
    if w.selected.len == 0: return
    if w.formOpen:
      w.loadModel()
      w.panelKey = ""       # the rest of the panel is out of date until the form closes (its Save and Cancel rebuild it)
      w.panelLive()
    else: w.rebuildPanel()
  w.closePanel = proc () =
    adw_overlay_split_view_set_show_sidebar(w.panelSplit, 0)
    w.selected = ""
    w.noForm()
    # emptied, not only hidden: its buttons would stay in the window, and a press already on its way (a second
    # Save) would still run its handler on the closed panel's form
    w.panelPhotos = nil
    w.panelLink = nil
    w.panelEdit = nil
    w.panelBox.clear()
    w.v.selected = ""
    w.v.symbolBox = @[]
    gtk_widget_queue_draw(w.v.widget)
  w.openProc = proc (id: string) =
    w.pushPage(w.procedurePage(id), id, "proc")
    adw_navigation_split_view_set_show_content(w.split, 0)
  w.v.onSelect = proc (id: string) =
    if w.picking: w.togglePick(id)  # the select mode (multi.nim)
    elif w.linkProc.len > 0:          # link mode (R7)
      let (ok, t) = w.m.tagById(id)
      if not ok or t.full.len == 0:
        w.toast("This tag has no KKS yet: review it first")
        return
      discard w.submit("link", newObj(@[("proc", newStr(w.linkProc)), ("step", newInt(w.linkStep)), ("kks", newStr(t.full)),
                       ("on", newBool(true))]), t.full & " → step " & $w.linkStep)
      w.loadModel()
      w.applyHighlights()
    else:
      # (the viewer has outlined the tag clicked: Keep editing puts the outline back on the panel's tag)
      w.goToTag(w.sheet, id, false, proc () =
        w.v.selected = w.selected
        gtk_widget_queue_draw(w.v.widget))
  w.v.onLink = proc (i: int) =
    let b = w.v.links[i]
    w.followLink(w.sheet, b.id, b.x0, b.y0)
  w.v.onMark = proc (x0, y0, x1, y1: float) =
    w.markDialog(x0, y0, x1, y1)
  w.v.onBox = proc (x0, y0, x1, y1: float) = w.addBox(x0, y0, x1, y1)
  w.sheetTitle = adw_window_title_new("", "")
  let contentHeader = headerBar(w.sheetTitle)
  adw_header_bar_pack_end(contentHeader, iconButton("zoom-fit-best-symbolic", "Fit the sheet (0)", proc () = w.v.fit()))
  adw_header_bar_pack_end(contentHeader, iconButton("zoom-in-symbolic", "Zoom in (+)", proc () = w.v.zoomBy(1.5)))
  adw_header_bar_pack_end(contentHeader, iconButton("zoom-out-symbolic", "Zoom out (−)", proc () = w.v.zoomBy(1 / 1.5)))
  # dark drawings: a PDF reader's dark mode for the sheets (lightness inverted, hue kept; photos never change)
  # A menu button with the three choices (the user, 2026-11-16: the drawings can stay dark, or light, whatever the
  # theme; until then they follow it). The choice is remembered on this device.
  let darkBtn = gtk_menu_button_new()
  gtk_menu_button_set_icon_name(darkBtn, "weather-clear-night-symbolic")
  gtk_widget_set_tooltip_text(darkBtn, DarkSetting)
  setAccessibleLabel(darkBtn, DarkSetting)
  let darkPop = gtk_popover_new()
  let darkBox = vbox(4)
  darkBox.add label(DarkSetting, "heading", wrap = false)
  let styles = adw_style_manager_get_default()
  var darkMode = darkModeOf(w.a.store.getMeta("dark_drawings"))
  let applyDark = proc () = w.v.setDark(darkNow(darkMode, adw_style_manager_get_dark(styles) != 0))
  var firstRadio: W
  for m in DarkMode:
    closureScope:
      let mode = m
      # toggle buttons in one group (one is always pressed): unlike GTK 4's check buttons they can be pressed
      # through AT-SPI, by a screen reader's own action and by the e2e
      let rb = gtk_toggle_button_new_with_label(DarkModeLabels[mode].cstring)
      if firstRadio == nil: firstRadio = rb else: gtk_toggle_button_set_group(rb, firstRadio)
      gtk_toggle_button_set_active(rb, cint(mode == darkMode))
      rb.on("toggled", proc () =
        if gtk_toggle_button_get_active(rb) == 0 or darkMode == mode: return
        darkMode = mode
        w.a.store.setMeta("dark_drawings", storedAs(mode))
        applyDark()
        idle(proc () = gtk_popover_popdown(darkPop)))     # chosen: the drawing shows it, the menu is done
      darkBox.add rb
  discard margins(darkBox, 8)
  gtk_popover_set_child(darkPop, darkBox)
  gtk_menu_button_set_popover(darkBtn, darkPop)
  # the theme changed while the app runs: the drawings follow at once when they are set to. One handler for the
  # process, calling the main screen of the moment (the screen is made again after leaving a plant and joining one)
  followTheme = proc () =
    if not w.gone: applyDark()       # (not into a window that has closed: adversarial review of #401)
  if not themeWatched:
    themeWatched = true
    styles.onPtr("notify::dark", proc (p: W) =
      if followTheme != nil: followTheme())
  adw_header_bar_pack_end(contentHeader, darkBtn)
  # a toggle: its pressed state is what Orca reads (and what the Coverage page turns on)
  w.coverBtn = gtk_toggle_button_new()
  gtk_button_set_icon_name(w.coverBtn, "camera-photo-symbolic")
  gtk_widget_set_tooltip_text(w.coverBtn, "Colour tags by photos")
  setAccessibleLabel(w.coverBtn, "Colour tags by photos")
  w.coverBtn.on("toggled", proc () =
    let on = gtk_toggle_button_get_active(w.coverBtn) != 0
    if on == w.v.coverage: return
    w.v.coverage = on
    gtk_widget_queue_draw(w.v.widget)
    w.toast(if on: "Tags by photos: green both · amber equipment only · blue tag plate only · red none"
            else: "Tags by how they were read"))
  adw_header_bar_pack_end(contentHeader, w.coverBtn)
  adw_header_bar_pack_end(contentHeader, iconButton("list-add-symbolic", "Mark a tag the app missed", proc () =
    w.leaving(proc () =       # (it closes the panel)
      if w.picking: w.stopPicking()
      w.startMarking())))
  # the select mode: one photo, place or note for several tags (multi.nim); a toggle, so its state is exposed
  w.pickBtn = gtk_toggle_button_new()
  gtk_button_set_icon_name(w.pickBtn, "selection-mode-symbolic")
  gtk_widget_set_tooltip_text(w.pickBtn, "Select tags")
  setAccessibleLabel(w.pickBtn, "Select tags")
  w.pickBtn.on("toggled", proc () =
    let on = gtk_toggle_button_get_active(w.pickBtn) != 0
    if on != w.picking:
      if on: w.startPicking() else: w.stopPicking()
    w.runSearch())              # the results' labels say what activating them does
  adw_header_bar_pack_start(contentHeader, w.pickBtn)
  w.panelBox = vbox(12)
  margins(w.panelBox, 12)
  let panelHeader = headerBar(adw_window_title_new("Equipment", ""))
  adw_header_bar_set_show_end_title_buttons(panelHeader, 0)
  adw_header_bar_pack_start(panelHeader, iconButton("window-close-symbolic", "Close the panel", proc () =
    w.leaving(proc () = w.closePanel())))
  w.panelSplit = adw_overlay_split_view_new()
  adw_overlay_split_view_set_sidebar_position(w.panelSplit, GTK_PACK_END)
  adw_overlay_split_view_set_content(w.panelSplit, w.v.widget)
  adw_overlay_split_view_set_sidebar(w.panelSplit, toolbarView(panelHeader, scrolled(w.panelBox)))
  adw_overlay_split_view_set_min_sidebar_width(w.panelSplit, 320)
  adw_overlay_split_view_set_max_sidebar_width(w.panelSplit, 420)
  adw_overlay_split_view_set_show_sidebar(w.panelSplit, 0)
  w.banner = adw_banner_new("")
  w.banner.on("button-clicked", proc () =
    w.runBanner())
  let contentView = toolbarView(contentHeader, w.panelSplit)
  adw_toolbar_view_add_bottom_bar(contentView, w.pickBar())
  adw_toolbar_view_add_top_bar(contentView, w.banner)
  if uxOn("offline-state"):    # #372: the drawing's page too (a narrow window shows it without the sheets)
    let ob = adw_banner_new("")
    gtk_widget_set_visible(ob, 0)
    w.offlineBanners.add ob
    adw_toolbar_view_add_top_bar(contentView, ob)
  w.queueBar = hbox(8)
  margins(w.queueBar, 6)
  w.queueBar.add adw_spinner_new()
  w.queueLabel = label("", "dim-label")
  w.queueBar.add w.queueLabel
  gtk_widget_set_visible(w.queueBar, 0)
  adw_toolbar_view_add_bottom_bar(contentView, w.queueBar)
  let content = page(contentView, "Drawing")
  w.split = adw_navigation_split_view_new()
  adw_navigation_split_view_set_sidebar(w.split, sidebar)
  adw_navigation_split_view_set_content(w.split, content)
  adw_navigation_split_view_set_min_sidebar_width(w.split, 260)
  w.fillSheets()
  if w.m.sheets.len > 0: w.showSheet(w.m.sheets[0].id)
  w.split

# ---------------------------------------------------------------- setup (no plant yet)

proc showMain(w: Win)

proc setupScreen(w: Win): W =
  ## a first screen of choices, each opening its own short page (one form at a time)
  let nav = adw_navigation_view_new()
  proc subpage(title: string, groups: seq[W]): W =
    let pg = adw_preferences_page_new()
    for g in groups: adw_preferences_page_add(pg, g)
    result = adw_navigation_page_new(toolbarView(headerBar(adw_window_title_new(title.cstring, "")), pg), title.cstring)
    g_object_ref_sink(result)   # kept: a popped page that was pushed (not added) would otherwise be freed
  # through a server
  let g1 = group("", "Your username and password on the plant's server. The server certifies this device for you. " &
                  "The address is the server's name or IP, with its sync port if it isn't 8421.")
  let url = entryRow("Server address", "")
  let user = entryRow("Username", "")
  let pw = passwordRow("Password")
  let go = button("Join", "suggested-action")
  gtk_widget_set_halign(go, GTK_ALIGN_END)
  gtk_widget_set_margin_top(go, 8)
  go.onClick(proc () =
    gtk_widget_set_sensitive(go, 0)
    proc run() {.async.} =
      let err = await w.a.joinServer(text(url).strip, text(user).strip, text(pw))
      gtk_widget_set_sensitive(go, 1)
      if err.len > 0: w.toast(err) else: w.showMain()
    asyncCheck run())
  for r in [url, user, pw]: adw_preferences_group_add(g1, r)
  adw_preferences_group_add(g1, go)
  let forgot = label(ForgotPassword, "dim-label", selectable = true)   # the way back in (#449)
  gtk_widget_set_margin_top(forgot, 12)
  adw_preferences_group_add(g1, forgot)
  # a new plant
  let g2 = group("", "You become its manager. This device holds the plant's root key: back it up afterwards (Manage → Account).")
  let plant = entryRow("Plant name", "")
  let u2 = entryRow("Your username", "")
  let fullName = entryRow("Your full name", "")
  let position = entryRow("Your position (job title)", "")
  gtk_widget_set_tooltip_text(position, "Required: every member needs one, e.g. Maintenance manager")
  let create = button("Create the plant", "suggested-action")
  gtk_widget_set_halign(create, GTK_ALIGN_END)
  gtk_widget_set_margin_top(create, 8)
  create.onClick(proc () =
    let pn = text(plant).strip
    let un = text(u2).strip.toLowerAscii
    let fn = text(fullName).strip
    let ps = text(position).strip
    if pn.len == 0 or un.len < 2 or fn.len == 0 or ps.len == 0:
      w.toast("Fill in the plant name, a username (2+ characters), your full name and your position (job title).")
      return
    try:
      w.a.createPlant(pn, un, fn, newStr(ps))
      w.showMain()
    except CatchableError as e: w.toast(e.msg))
  for r in [plant, u2, fullName, position]: adw_preferences_group_add(g2, r)
  adw_preferences_group_add(g2, create)
  # a bundle file from an admin
  let g3 = group("", "An admin can hand you a bundle file (Manage → Devices → Save a bundle).")
  let open = button("Open a bundle…", "suggested-action")
  gtk_widget_set_halign(open, GTK_ALIGN_START)
  open.onClick(proc () =
    openFile(w.window, "Open a KKS bundle", proc (path: string) =
      if path.len == 0: return
      let err = w.a.importBundleFile(readFile(path))
      if err.len > 0: w.toast(err)
      elif w.a.joined: w.showMain()
      else: w.toast("The bundle was imported, but this device is not certified in it yet.")))
  adw_preferences_group_add(g3, open)
  let jg = w.joinGroups(proc () = w.showMain())
  let removed = w.a.removedNote
  let choices = group("This device does not belong to a plant yet", if removed.len > 0: removed & " Its plant data was deleted here." else: "")
  let pages = [("Join through a server", "Username and password on the plant's server", subpage("Join through a server", @[g1])),
               ("Join with a code", "An admin shows a QR code; paste its text or open a picture of it", subpage("Join with a code", @[jg[0]])),
               ("Ask an admin on this Wi-Fi", "Compare a 6-digit code with an admin nearby", subpage("Ask an admin on this Wi-Fi", @[jg[1]])),
               ("Join with a file", "A bundle an admin saved for you", subpage("Join with a file", @[g3])),
               ("Start a new plant", "You become its manager", subpage("Start a new plant", @[g2]))]
  for i in 0 ..< pages.len:
    closureScope:
      let pgW = pages[i][2]
      adw_preferences_group_add(choices, navRow(pages[i][0], pages[i][1], pages[i][0], proc () = adw_navigation_view_push(nav, pgW)))
  let root = adw_preferences_page_new()
  adw_preferences_page_add(root, choices)
  let setupHeader = headerBar(adw_window_title_new("Walkdown", "Set up this device"))
  adw_header_bar_pack_end(setupHeader, primaryMenu())
  adw_navigation_view_add(nav, adw_navigation_page_new(toolbarView(setupHeader, root), "Set up"))
  nav

proc showMain(w: Win) =
  adw_toast_overlay_set_child(w.toasts, w.mainScreen())
  w.resumePhotos()       # photos left from the last run (a crash, a kill, a logout) are sent first

# ---------------------------------------------------------------- the application

proc endMode(w: Win): bool =
  ## Escape: the drawing's mode ends as that mode's own button ends it (#183: Escape ended only the viewer's half of
  ## Mark a tag, and its banner and crosshair stayed). False when no mode is on: the key is not ours then.
  if w.v == nil: return false
  if w.picking: w.stopPicking()                     # the Select tags toggle
  elif w.v.marking: w.stopMarking()                 # the banner's Cancel
  elif w.linkProc.len > 0:                          # the banner's Done
    if w.bannerAction != nil: w.runBanner()
    else: w.stopLinking()
  else: return false
  true

proc windowKey(w: Win, keyval: cuint): bool =
  ## the keys the window takes when the widget with the focus and its parents left them: Escape ends the drawing's
  ## mode with the focus on the drawing or elsewhere (after "Mark a tag" or "Select tags" it is on that button). Some
  ## widgets keep Escape for themselves first: dialogs and popovers close, a search field stops its search.
  if keyval == 0xff1b: w.endMode() else: false

proc activate(w: Win, app: W) =
  # Walkdown started again while it runs (one instance per user): GApplication sends "activate" to this one. The
  # window it has is shown, not a second one, which replaced the first's state (window, toasts, status line) and,
  # when the first then closed, marked the live one as gone.
  if w.window != nil:
    if not w.gone: gtk_window_present(w.window)
    return
  w.window = adw_application_window_new(app)
  gtk_window_set_title(w.window, "Walkdown")
  gtk_window_set_default_size(w.window, 1280, 820)
  let keys = gtk_event_controller_key_new()          # (bubble phase: after the focused widget and its parents)
  keys.onKey(proc (keyval, state: cuint): bool = w.windowKey(keyval))
  gtk_widget_add_controller(w.window, keys)
  w.toasts = adw_toast_overlay_new()
  adw_application_window_set_content(w.window, w.toasts)
  timing("window made")
  # the listener, the relay and discovery once the window is up (its first frame comes before an idle callback); on
  # the setup screen at once: it lists the admins' devices discovery finds, and there is no drawing to wait for
  proc startSync() =
    w.a.startSync(port = parseInt(getEnv("KKS_SYNC_PORT", "8421")), discovery = getEnv("KKS_NO_MDNS").len == 0)
    timing("sync started")
  if w.a.joined: idle(startSync)
  else: startSync()
  if w.a.joined: w.showMain()
  else: adw_toast_overlay_set_child(w.toasts, w.setupScreen())
  timing("main screen built")
  # Once the window is destroyed (closed: the app quits a moment later, later still on a slow machine) nothing may
  # reach it or its widgets (`gone`): the reload after a change, the photo queue's timer and the timers below stop,
  # toasts are dropped, and the status line is let go
  # (the window's pointer dangles then: the test's focus timer called gtk_root_get_focus on it, a GTK critical on
  # CI's slower runners)
  w.window.on("destroy", proc () =
    w.gone = true
    aboutForget()
    w.status = nil)
  w.a.onChange.add proc (why: string) =
    if why == "wiped":
      w.photosWiped()    # the queued photos went with the store's rows; nothing more is sent
      # the plant data is gone (§15); start over as a fresh process: new device key, the setup screen with the note
      after(200, proc () =
        # (not the links it was started with: they were for the plant left behind)
        let args = allocCStringArray(@[getAppFilename()] & commandLineParams().filterIt(not it.toLowerAscii.startsWith(LinkScheme & ":")))
        discard execv(getAppFilename().cstring, args)
        quit(1))
      return
    w.showSyncState()
    if why == "relay" or w.gone: return     # presence only: nothing to reload; or no window to reload
    if not w.reloadQueued and w.a.joined and w.m != nil:
      w.reloadQueued = true
      after(300, proc () =       # once, also when refresh fails (as a timer it then came back for good: #163)
        w.reloadQueued = false
        if not w.gone: w.refresh())
  var closing = false
  var formLeft = false      # the person chose Discard: this close goes on past the panel's form
  w.window.onCloseRequestStop(proc (): bool =
    if closing:
      closeCourseWindows()
      return false
    # a form of the tag panel holding something typed: asked first, as leaving it inside the window is (#163). The
    # close is refused meanwhile; Discard closes the window (the photos' question below still comes), Keep editing
    # leaves everything as it was. (gtk_window_close sends close-request again at once, inside the call.)
    if not formLeft and w.formDirty:
      w.leaving(proc () =
        formLeft = true
        try: gtk_window_close(w.window)
        finally: formLeft = false)
      return true
    # photos still in the queue are kept on disk and sent at the next start: say so, and offer to wait
    let n = queuedCount()
    if n == 0:
      closeCourseWindows()
      return false
    let d = adw_alert_dialog_new((if n == 1: "1 photo is still being prepared" else: $n & " photos are still being prepared").cstring,
                                 "Wait until they are sent (a moment), or close: they are kept on this computer and sent when Walkdown next starts.")
    adw_alert_dialog_add_response(d, "wait", "Wait")
    adw_alert_dialog_add_response(d, "close", "Close anyway")
    adw_alert_dialog_set_default_response(d, "wait")
    adw_alert_dialog_set_close_response(d, "wait")
    d.onResponse(proc (id: string) =
      if id == "close":
        closing = true
        gtk_window_close(w.window))
    present(d, w.window)
    true)
  gtk_window_present(w.window)
  # tests (#160): while the file KKS_TEST_STALE_CLICK names exists, the next button press is followed by a rebuild
  # of the tag panel before the button's handler runs (what a reload does when it falls in between; forced, also
  # under an open form, where no reload rebuilds the panel since #163: the handler of a button that has gone must
  # still do nothing), and the file is removed
  let staleFlag = getEnv("KKS_TEST_STALE_CLICK")
  if staleFlag.len > 0:
    beforeClickHandler = proc () =
      if fileExists(staleFlag) and w.rebuildPanel != nil:
        removeFile(staleFlag)
        w.rebuildPanel()
        stderr.writeLine "KKS_TEST_STALE_CLICK: the panel was rebuilt before a button's handler"
  # tests: when the file KKS_TEST_MOVE_FOCUS names appears, the keyboard focus goes to the first search result
  # ("result") or to the search field ("search"), and the file is removed (GTK 4's AT-SPI has no GrabFocus, and keys
  # can't be typed into the headless session)
  let moveFocus = getEnv("KKS_TEST_MOVE_FOCUS")
  if moveFocus.len > 0:
    timeout(100, proc (): bool =
      if w.gone: return false
      if fileExists(moveFocus):
        let what = readFile(moveFocus).strip
        removeFile(moveFocus)
        if what == "result":
          let r = gtk_list_box_get_row_at_index(w.resultList, 0)
          if r != nil: gtk_widget_grab_focus(r)
        elif what == "search" and w.searchEntry != nil: gtk_widget_grab_focus(w.searchEntry)
      true)
  # tests: the file KKS_TEST_FOCUS names holds what has the window's keyboard focus (a button's label, else the
  # widget's type; "" for none), written when it changes. The headless test session has no keyboard, so its window
  # is never the active one and AT-SPI reports no widget as focused.
  let focusFile = getEnv("KKS_TEST_FOCUS")
  if focusFile.len > 0:
    var said = "\x00"
    timeout(100, proc (): bool =
      if w.gone: return false
      let f = gtk_root_get_focus(w.window)
      var now = ""
      if f != nil:
        now = $gObjectTypeName(f)
        if now == "GtkButton" and gtk_button_get_label(f) != nil: now = "button " & $gtk_button_get_label(f)
      if now != said:
        said = now
        writeFile(focusFile, now)
      true)
  # tests (#183): the drawing driven without a pointer or keyboard (the headless test session has neither). Commands
  # written to the file KKS_TEST_VIEWER names, plus ".do", one per line, go through the viewer's own gesture and key
  # procs: "key 0xff1b" (a key pressed on the drawing), "window-key 0xff1b" (with the focus elsewhere),
  # "drag x y dx dy" (widget pixels), "click-tag CODE". The file itself holds the drawing's state, written when it
  # changes: "n=<commands done> marking=0|1 selecting=0|1 cursor=<name> ox=… oy=… pop_on_escape=0|1" (the sidebar's).
  let viewerFile = getEnv("KKS_TEST_VIEWER")
  if viewerFile.len > 0:
    var said = ""
    var done = 0
    timeout(100, proc (): bool =
      if w.gone: return false
      if w.v == nil: return true           # (not joined yet: no drawing)
      let todo = viewerFile & ".do"
      if fileExists(todo):
        let cmds = readFile(todo)
        removeFile(todo)
        for line in cmds.splitLines:
          let p = line.splitWhitespace
          if p.len == 0: continue
          case p[0]
          of "key":                      # on the drawing: what it leaves goes on to the window (GTK's own passing
                                         # of the key between them is not tested: no keyboard in the test session)
            let k = cuint(parseHexInt(p[1]))
            if not w.v.keyPress(k): discard w.windowKey(k)
          of "window-key": discard w.windowKey(cuint(parseHexInt(p[1])))    # the focus elsewhere
          of "drag":
            let (x, y, dx, dy) = (parseFloat(p[1]), parseFloat(p[2]), parseFloat(p[3]), parseFloat(p[4]))
            w.v.dragBegin(x, y)
            w.v.dragUpdate(dx, dy)
            w.v.dragEnd(dx, dy)
          of "click-tag":                # the tag of this code on the sheet shown, at its middle
            var ids: seq[string]
            for t in w.m.tags:
              if t.full == p[1]: ids.add t.id
            for b in w.v.tags:
              if b.id in ids:
                w.v.clickAt(((b.x0 + b.x1) / 2 - w.v.ox) * w.v.z, ((b.y0 + b.y1) / 2 - w.v.oy) * w.v.z)
                break
          else: stderr.writeLine "KKS_TEST_VIEWER: unknown command " & line
          inc done
      let c = gtk_widget_get_cursor(w.v.widget)
      let now = "n=" & $done & " marking=" & $int(w.v.marking) & " selecting=" & $int(w.v.selecting) &
                " cursor=" & (if c != nil and gdk_cursor_get_name(c) != nil: $gdk_cursor_get_name(c) else: "") &
                " ox=" & $w.v.ox & " oy=" & $w.v.oy &
                " pop_on_escape=" & $adw_navigation_view_get_pop_on_escape(w.sideNav)
      if now != said:
        said = now
        writeFile(viewerFile & ".tmp", now)
        moveFile(viewerFile & ".tmp", viewerFile)
      true)
  # tests: the About dialog's pages (about.nim aboutGo). Lines written to the file KKS_TEST_ABOUT names, plus ".do",
  # are page tags to show ("legal", "acknowledgements" …, or "back"); the file itself holds
  # where the open dialog's links go (about.nim aboutTargets), one per line, then a last line "n=<lines done>
  # page=<the visible page's tag, empty when the dialog is closed>", written when it changes.
  let aboutFile = getEnv("KKS_TEST_ABOUT")
  if aboutFile.len > 0:
    var said = "\x00"
    var done = 0
    timeout(100, proc (): bool =
      if w.gone: return false
      let todo = aboutFile & ".do"
      if fileExists(todo):
        let cmds = readFile(todo)
        removeFile(todo)
        for line in cmds.splitLines:
          if line.strip.len == 0: continue
          aboutGo(line.strip)
          inc done
      let now = aboutTargets().join("\n") & "\nn=" & $done & " page=" & aboutPage()
      if now != said:
        said = now
        writeFile(aboutFile & ".tmp", now)
        moveFile(aboutFile & ".tmp", aboutFile)
      true)
  if getEnv("KKS_DEBUG_DIALOG").len > 0:     # accessibility check: a dialog over whatever screen is up
    after(3000, proc () =
      confirm(w.window, "Debug dialog", "Body text of the debug dialog", "OK", false, proc () = discard))
  if uxOn("offline-state"):   # #372: offline comes with time (no sync for 5 minutes), not with an event
    timeout(2_000, proc (): bool =
      w.showSyncState()
      true)
  timeout(30_000, proc (): bool =
    w.showSyncState()
    w.a.saveState()        # the replayed state, for the next start (when it changed; PROTOCOL-v2 §15b)
    true)
  let shot = getEnv("KKS_SHOT")             # tests: KKS_SHOT=file.png[,seconds[,quit]]
  if shot.len > 0:
    let parts = shot.split(',')
    let secs = if parts.len > 1: parseFloat(parts[1]) else: 3.0
    after(int(secs * 1000), proc () =
      discard saveScreenshot(w.window, parts[0])
      if parts.len > 2 and parts[2] == "quit": g_application_quit(app))

var shotRequested {.volatile.} = false
proc onUsr1(sig: cint) {.noconv.} = shotRequested = true
var figRequested {.volatile.} = false
proc onUsr2(sig: cint) {.noconv.} = figRequested = true

proc g_bus_get_sync(busType: cint, cancellable: pointer, error: pointer): pointer {.importc, header: "<gio/gio.h>".}
proc g_dbus_connection_call_sync(conn: pointer, name, path, iface, meth: cstring, params, replyType: pointer,
                                 flags, timeoutMs: cint, cancellable, error: pointer): pointer {.importc, header: "<gio/gio.h>".}
proc g_variant_new_name_owner(fmt: cstring, s: cstring): pointer {.importc: "g_variant_new", header: "<glib.h>".}
proc g_variant_get_bool(v: pointer, fmt: cstring, b: ptr cint) {.importc: "g_variant_get", header: "<glib.h>".}
proc g_variant_unref(v: pointer) {.importc, header: "<glib.h>".}
proc g_object_unref_p(p: pointer) {.importc: "g_object_unref", header: "<glib-object.h>".}

proc runningElsewhere(id: string): bool =
  ## Walkdown already runs for this user (its application ID is owned on the session bus): a start that will hand its
  ## links over to it (decision 0058) and must not open the store. False when there is no session bus to ask (then
  ## GApplication can't find another instance either).
  let bus = g_bus_get_sync(2, nil, nil)                 # G_BUS_TYPE_SESSION
  if bus == nil: return false
  let r = g_dbus_connection_call_sync(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                      "NameHasOwner", g_variant_new_name_owner("(s)", id.cstring), nil, 0, 1000, nil, nil)
  if r != nil:
    var b: cint
    g_variant_get_bool(r, "(b)", addr b)
    g_variant_unref(r)
    result = b != 0
  g_object_unref_p(bus)

proc main() =
  if getEnv("KKS_TIMING").len > 0: viewer.startedAt = epochTime()
  timing("main")
  # one instance per user; a separate data folder (tests, a second profile) is its own application, with its own ID
  # (two processes sharing an ID confuse the accessibility registry)
  let custom = getEnv("KKS_DATA_DIR")
  var id = AppId
  if custom.len > 0:
    var h = 0'u32
    for c in custom: h = h * 31 + uint32(c)
    id.add ".p" & toHex(h, 8)
  # 4 = G_APPLICATION_HANDLES_OPEN: walkdown:// links (decision 0058) come to "open", in the running instance
  # (KKS_TEST_UNIQUE: a test's app on its own data folder stays unique, so that a second start hands its links over)
  let nonUnique = custom.len > 0 and getEnv("KKS_TEST_UNIQUE").len == 0
  # The store opens and the log replays on a thread of its own while GTK starts (decision 0061), unless Walkdown runs
  # already: this start then hands its links over below and ends without touching the store (decision 0058). (Two
  # starts in the same moment can both begin; the one that turns out second only reads the store, or saves the state
  # it replayed, which is a correct one, and quits.)
  if nonUnique or not runningElsewhere(id): discard openAppInBackground()
  let app = adw_application_new(id.cstring, cint(4 or (if nonUnique: 32 else: 0)))   # 32 = G_APPLICATION_NON_UNIQUE
  # GApplication sees only the program and the links: any other argument stays unread (it would take an unknown
  # option for an error, and a file for something to open)
  var args = @[getAppFilename()]
  for p in commandLineParams():
    if p.len <= MaxLinkLen and p.toLowerAscii.startsWith(LinkScheme & ":"): args.add p
  let argv = allocCStringArray(args)
  # Walkdown already runs (a second start, a link from another app): GApplication hands the links (or "activate") to
  # it, and this start ends without opening the store or the sync port the running one holds
  if g_application_register(app, nil, nil) != 0 and g_application_get_is_remote(app) != 0:
    dropBackgroundOpen()
    quit int(g_application_run(app, cint(args.len), argv))
  timing("registered")
  let w = Win(a: openedApp())
  timing("app open")
  errorHook = proc (text: string) = w.a.diag("error", text)
  # asyncdispatch inside GLib: its epoll fd wakes us, a timer covers its timers
  discard watchFd(asyncFd(), proc (): bool =
    pumpAsync()
    true)
  timeout(100, proc (): bool =
    pumpAsync()
    true)
  app.on("activate", proc () = w.activate(app))
  app.onOpen(proc (uris: seq[string]) =
    w.activate(app)
    let links = uris
    idle(proc () =        # (once the window is up)
      for u in links: w.openAppLink(u)))
  # About Walkdown: the primary menu's item, and the app.about action other parts of GNOME may call
  let aboutAction = g_simple_action_new("about", nil)
  aboutAction.onPtr("activate", proc (p: W) =
    if w.window != nil and not w.gone: showAbout(w.window, AppId, proc (): bool = not w.gone))
  g_action_map_add_action(app, aboutAction)
  g_object_unref(aboutAction)
  let shotPath = getEnv("KKS_SHOT_ON_SIGNAL")   # tests: a screenshot of the window on SIGUSR1
  if shotPath.len > 0:
    signal(SIGUSR1, onUsr1)
    signal(SIGUSR2, onUsr2)      # and on SIGUSR2, scroll course windows to their first animated figure
    timeout(100, proc (): bool =
      if figRequested:
        figRequested = false
        scrollToFigure()
      if shotRequested and w.window != nil and not w.gone:
        shotRequested = false
        let ok = saveScreenshot(w.window, shotPath)
        stderr.writeLine "screenshot " & shotPath & ": " & (if ok: "saved" else: "FAILED")
        for (id, cwin) in courseWindows():
          let pth = shotPath.changeFileExt("") & "-" & id & ".png"
          stderr.writeLine "screenshot " & pth & ": " & (if saveScreenshot(cwin, pth): "saved" else: "FAILED")
      true)
  let code = g_application_run(app, cint(args.len), argv)
  w.a.saveState()
  quit int(code)

main()
