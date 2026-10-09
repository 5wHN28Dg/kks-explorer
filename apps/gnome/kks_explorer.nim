## Walkdown for GNOME (M6 phase 5; decisions 0014, 0016, 0031): GTK 4 + libadwaita in Nim, the Nim core
## underneath. One thread: GLib's main loop runs GTK, and asyncdispatch (sync, mDNS) is driven from it.

import std/[asyncdispatch, os, strutils, tables, sets, math, times, posix, sequtils]
import kks/[json, api]
import kks/model
import kksl/dbstore
import appstate
import kksg/[gtk, ui, viewer, win, panel, sidepages, mark, manage, join, learn, multi, systems, photos]

const AppId = "io.github._5wHN28Dg.walkdown"

proc doShowSheet(w: Win, id: string)
proc doSelectTag(w: Win, id: string, center: bool)

proc doSelectTag(w: Win, id: string, center: bool) =
  let (ok, t) = w.m.tagById(id)
  if not ok: return
  w.selected = id
  w.v.selected = id
  if center:
    let (okS, si) = w.m.sheetById(t.sheet)
    let s = if okS and si.scale > 0: si.scale else: 2.0
    w.v.centerOn(t.bbox[0] / s, t.bbox[1] / s, t.bbox[2] / s, t.bbox[3] / s)
  w.buildPanel(t)
  adw_overlay_split_view_set_show_sidebar(w.panelSplit, 1)
  gtk_widget_queue_draw(w.v.widget)

proc doShowSheet(w: Win, id: string) =
  let (ok, si) = w.m.sheetById(id)
  if not ok: return
  w.sheet = id
  adw_window_title_set_title(w.sheetTitle, si.name.cstring)
  let (_, kkp) = w.a.file("sheets/" & id & ".kkp")
  var levels: seq[string]
  for k in 0 ..< si.levels:
    let (okL, data) = w.a.file("sheets/" & id & ".o" & $k & ".jxl")
    if okL: levels.add data
  w.v.setSheet(si.name, kkp, si.raw, levels)
  w.v.tags = w.tagBoxes(id)
  w.syncChosen()
  adw_navigation_split_view_set_show_content(w.split, 1)
  discard gtk_widget_grab_focus(w.v.widget)

proc fillSheets(w: Win) =
  gtk_list_box_remove_all(w.sheetList)
  let items1 = toSeq(w.m.sheets)
  for i1 in 0 ..< items1.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let si = items1[i1]
      var n, review = 0
      for t in w.m.tagsOf(si.id):
        inc n
        if t.status == "review": inc review
      let id = si.id
      gtk_list_box_append(w.sheetList, navRow(si.name, $n & " tags" & (if review > 0: ", " & $review & " to review" else: ""),
                                              "Open " & si.name, proc () = w.showSheet(id)))

proc runSearch(w: Win) =
  let q = text(w.searchEntry).strip
  gtk_list_box_remove_all(w.resultList)
  w.v.hits.clear()
  if q.len == 0:
    gtk_widget_set_visible(w.resultList, 0)
    gtk_widget_queue_draw(w.v.widget)
    return
  let found = w.m.search(q)
  let items2 = toSeq(found)
  for i2 in 0 ..< items2.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let t = items2[i2]
      let (okS, si) = w.m.sheetById(t.sheet)
      let title = if t.full.len > 0: t.full else: "(unread)"
      let id = t.id
      let sheet = t.sheet
      let picking = w.picking     # the select mode: a result toggles its tag (the keyboard's way to select)
      gtk_list_box_append(w.resultList, navRow(title, w.m.kindName(t) & " · " & (if okS: si.name else: t.sheet),
        (if picking: "Select or unselect " else: "Show ") & title & " on " & (if okS: si.name else: t.sheet), proc () =
          if sheet != w.sheet: w.showSheet(sheet)
          if w.picking:
            let (okT, tt) = w.m.tagById(id)
            if okT:
              let (okS2, si2) = w.m.sheetById(tt.sheet)
              let sc = if okS2 and si2.scale > 0: si2.scale else: 2.0
              w.v.centerOn(tt.bbox[0] / sc, tt.bbox[1] / sc, tt.bbox[2] / sc, tt.bbox[3] / sc)
            w.togglePick(id)
          else: w.selectTag(id, true)))
      w.v.hits.incl t.id
  if found.len == 0: gtk_list_box_append(w.resultList, row("Nothing found", "Try part of the code, or a word from the description"))
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
  result.add " · " & (if reachable == 0: "no device reachable" elif reachable == 1: "1 device reachable" else: $reachable & " devices reachable")
  if last > 0: result.add " · synced " & fromUnix(last).local.format("HH:mm")
  if snap["relay"].s == "online":
    let n = snap["relay_online"].i
    result.add " · internet: " & (if n == 1: "1 device" else: $n & " devices") & " online"
    case snap["relay_how"].s
    of "direct": result.add ", last sync direct"
    of "relay": result.add ", last sync through the relay"
    else: discard

proc refresh(w: Win) =
  ## the data changed underneath (sync, an approval): reload, keep the open sheet and selection (R20)
  w.loadModel()
  w.fillSheets()
  if w.sheet.len > 0:
    w.v.tags = w.tagBoxes(w.sheet)
    w.syncChosen()
    gtk_widget_queue_draw(w.v.widget)
  if w.selected.len > 0 and not w.panelEditing:   # never under an open form (it would lose what is typed)
    let (ok, t) = w.m.tagById(w.selected)
    if ok: w.buildPanel(t)
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
  gtk_widget_add_css_class(w.sheetList, "boxed-list")
  let more = gtk_list_box_new()
  gtk_widget_add_css_class(more, "boxed-list")
  gtk_list_box_set_selection_mode(more, GTK_SELECTION_NONE)
  more.gtk_list_box_append(navRow("Procedures", "Operation manual steps and their equipment", "Open the procedures", proc () =
    w.pushPage(w.proceduresPage(), "Procedures", "procs")))
  more.gtk_list_box_append(navRow("Equipment by system", "Every code on the drawings, by block, system and kind",
    "Open Equipment by system", proc () = w.pushPage(w.systemsPage(), "Equipment by system", "systems")))
  more.gtk_list_box_append(navRow("Learning", "The courses, with your progress", "Open Learning", proc () =
    w.pushPage(w.learningPage(), "Learning", "learning")))
  more.gtk_list_box_append(navRow("Review queue", "Tag readings to confirm or correct", "Open the review queue", proc () =
    w.pushPage(w.reviewPage(), "Review queue", "review")))
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
  adw_header_bar_pack_end(sideHeader, iconButton("view-refresh-symbolic", "Sync now", proc () =
    proc go() {.async.} =
      let n = await w.a.syncAll()
      w.toast(if n > 0: "Synced with " & $n & " device" & (if n == 1: "" else: "s") else: "No other device reached")
    asyncCheck go()))
  toolbarView(sideHeader, side)

proc mainScreen(w: Win): W =
  w.loadModel()
  w.sideNav = adw_navigation_view_new()
  adw_navigation_view_add(w.sideNav, adw_navigation_page_new_with_tag(w.sideRoot(), "Sheets", "root"))
  w.sideNav.onPtr("popped", proc (p: W) =
    # leaving a procedure stops highlighting its equipment, unless link mode is on (it ends with Done)
    if w.activeProc.len > 0 and w.linkProc.len == 0:
      w.activeProc = ""
      w.applyHighlights())
  let sidebar = page(w.sideNav, "Sheets")
  # content: viewer + tag panel
  w.v = newViewer()
  w.v.setDark(w.a.store.getMeta("dark_drawings") == "1")    # per device (this device's store), like sync_peers
  w.showSheet = proc (id: string) = w.doShowSheet(id)
  w.selectTag = proc (id: string, center: bool) = w.doSelectTag(id, center)
  w.rebuildPanel = proc () =
    if w.selected.len > 0:
      w.loadModel()
      let (ok, t) = w.m.tagById(w.selected)
      if ok: w.buildPanel(t)
  w.closePanel = proc () =
    adw_overlay_split_view_set_show_sidebar(w.panelSplit, 0)
    w.selected = ""
    w.panelEditing = false
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
    else: w.selectTag(id, false)
  w.v.onMark = proc (x0, y0, x1, y1: float) =
    w.markDialog(x0, y0, x1, y1)
  w.v.onBox = proc (x0, y0, x1, y1: float) = w.addBox(x0, y0, x1, y1)
  w.v.onEscape = proc () = w.stopPicking()
  w.sheetTitle = adw_window_title_new("", "")
  let contentHeader = headerBar(w.sheetTitle)
  adw_header_bar_pack_end(contentHeader, iconButton("zoom-fit-best-symbolic", "Fit the sheet (0)", proc () = w.v.fit()))
  adw_header_bar_pack_end(contentHeader, iconButton("zoom-in-symbolic", "Zoom in (+)", proc () = w.v.zoomBy(1.5)))
  adw_header_bar_pack_end(contentHeader, iconButton("zoom-out-symbolic", "Zoom out (−)", proc () = w.v.zoomBy(1 / 1.5)))
  # dark drawings: a PDF reader's dark mode for the sheets (lightness inverted, hue kept; photos never change)
  let darkBtn = gtk_toggle_button_new()
  gtk_button_set_icon_name(darkBtn, "weather-clear-night-symbolic")
  gtk_widget_set_tooltip_text(darkBtn, "Dark drawings")
  setAccessibleLabel(darkBtn, "Dark drawings")
  gtk_toggle_button_set_active(darkBtn, cint(w.v.dark))
  darkBtn.on("toggled", proc () =
    let on = gtk_toggle_button_get_active(darkBtn) != 0
    w.v.setDark(on)
    w.a.store.setMeta("dark_drawings", if on: "1" else: ""))
  adw_header_bar_pack_end(contentHeader, darkBtn)
  adw_header_bar_pack_end(contentHeader, iconButton("camera-photo-symbolic", "Colour tags by photos", proc () =
    w.v.coverage = not w.v.coverage
    gtk_widget_queue_draw(w.v.widget)
    w.toast(if w.v.coverage: "Tags by photos: green both · amber equipment only · blue tag plate only · red none"
            else: "Tags by how they were read")))
  adw_header_bar_pack_end(contentHeader, iconButton("list-add-symbolic", "Mark a tag the app missed", proc () =
    if w.picking: w.stopPicking()
    w.startMarking()))
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
  adw_header_bar_pack_start(panelHeader, iconButton("window-close-symbolic", "Close the panel", proc () = w.closePanel()))
  w.panelSplit = adw_overlay_split_view_new()
  adw_overlay_split_view_set_sidebar_position(w.panelSplit, GTK_PACK_END)
  adw_overlay_split_view_set_content(w.panelSplit, w.v.widget)
  adw_overlay_split_view_set_sidebar(w.panelSplit, toolbarView(panelHeader, scrolled(w.panelBox)))
  adw_overlay_split_view_set_min_sidebar_width(w.panelSplit, 320)
  adw_overlay_split_view_set_max_sidebar_width(w.panelSplit, 420)
  adw_overlay_split_view_set_show_sidebar(w.panelSplit, 0)
  w.banner = adw_banner_new("")
  w.banner.on("button-clicked", proc () =
    if w.bannerAction != nil: w.bannerAction())
  let contentView = toolbarView(contentHeader, w.panelSplit)
  adw_toolbar_view_add_bottom_bar(contentView, w.pickBar())
  adw_toolbar_view_add_top_bar(contentView, w.banner)
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
  adw_navigation_view_add(nav, adw_navigation_page_new(toolbarView(headerBar(adw_window_title_new("Walkdown", "Set up this device")), root), "Set up"))
  nav

proc showMain(w: Win) =
  adw_toast_overlay_set_child(w.toasts, w.mainScreen())

# ---------------------------------------------------------------- the application

proc activate(w: Win, app: W) =
  w.window = adw_application_window_new(app)
  gtk_window_set_title(w.window, "Walkdown")
  gtk_window_set_default_size(w.window, 1280, 820)
  w.toasts = adw_toast_overlay_new()
  adw_application_window_set_content(w.window, w.toasts)
  if w.a.joined: w.showMain()
  else: adw_toast_overlay_set_child(w.toasts, w.setupScreen())
  w.a.onChange.add proc (why: string) =
    if why == "wiped":
      # the plant data is gone (§15); start over as a fresh process: new device key, the setup screen with the note
      timeout(200, proc (): bool =
        let args = allocCStringArray(@[getAppFilename()] & commandLineParams())
        discard execv(getAppFilename().cstring, args)
        quit(1))
      return
    if w.status != nil: adw_window_title_set_subtitle(w.status, w.statusText().cstring)
    if why == "relay": return     # presence only: nothing to reload
    if not w.reloadQueued and w.a.joined and w.m != nil:
      w.reloadQueued = true
      timeout(300, proc (): bool =
        w.reloadQueued = false
        w.refresh()
        false)
  var closing = false
  w.window.onCloseRequestStop(proc (): bool =
    # photos still in the queue are lost when the app closes: ask first
    let n = queuedCount()
    if n == 0 or closing: return false
    let d = adw_alert_dialog_new((if n == 1: "1 photo is still being prepared" else: $n & " photos are still being prepared").cstring,
                                 "Closing now loses them. Wait until they are sent (a moment), or close anyway.")
    adw_alert_dialog_add_response(d, "wait", "Wait")
    adw_alert_dialog_add_response(d, "close", "Close anyway")
    adw_alert_dialog_set_response_appearance(d, "close", ADW_RESPONSE_DESTRUCTIVE)
    adw_alert_dialog_set_default_response(d, "wait")
    adw_alert_dialog_set_close_response(d, "wait")
    d.onResponse(proc (id: string) =
      if id == "close":
        closing = true
        gtk_window_close(w.window))
    present(d, w.window)
    true)
  gtk_window_present(w.window)
  if getEnv("KKS_DEBUG_DIALOG").len > 0:      # accessibility check: a dialog over whatever screen is up
    timeout(3000, proc (): bool =
      confirm(w.window, "Debug dialog", "Body text of the debug dialog", "OK", false, proc () = discard)
      false)
  timeout(30_000, proc (): bool =
    if w.status != nil: adw_window_title_set_subtitle(w.status, w.statusText().cstring)
    true)
  let shot = getEnv("KKS_SHOT")             # tests: KKS_SHOT=file.png[,seconds[,quit]]
  if shot.len > 0:
    let parts = shot.split(',')
    let secs = if parts.len > 1: parseFloat(parts[1]) else: 3.0
    timeout(int(secs * 1000), proc (): bool =
      discard saveScreenshot(w.window, parts[0])
      if parts.len > 2 and parts[2] == "quit": g_application_quit(app)
      false)

var shotRequested {.volatile.} = false
proc onUsr1(sig: cint) {.noconv.} = shotRequested = true
var figRequested {.volatile.} = false
proc onUsr2(sig: cint) {.noconv.} = figRequested = true

proc main() =
  if getEnv("KKS_TIMING").len > 0: viewer.startedAt = epochTime()
  let w = Win(a: openApp())
  errorHook = proc (text: string) = w.a.diag("error", text)
  w.a.startSync(port = parseInt(getEnv("KKS_SYNC_PORT", "8421")), discovery = getEnv("KKS_NO_MDNS").len == 0)
  # asyncdispatch inside GLib: its epoll fd wakes us, a timer covers its timers
  discard watchFd(asyncFd(), proc (): bool =
    pumpAsync()
    true)
  timeout(100, proc (): bool =
    pumpAsync()
    true)
  # one instance per user; a separate data folder (tests, a second profile) is its own application, with its own ID
  # (two processes sharing an ID confuse the accessibility registry)
  let custom = getEnv("KKS_DATA_DIR")
  var id = AppId
  if custom.len > 0:
    var h = 0'u32
    for c in custom: h = h * 31 + uint32(c)
    id.add ".p" & toHex(h, 8)
  let app = adw_application_new(id.cstring, if custom.len > 0: 32 else: 0)   # 32 = G_APPLICATION_NON_UNIQUE
  app.on("activate", proc () = w.activate(app))
  let shotPath = getEnv("KKS_SHOT_ON_SIGNAL")   # tests: a screenshot of the window on SIGUSR1
  if shotPath.len > 0:
    signal(SIGUSR1, onUsr1)
    signal(SIGUSR2, onUsr2)      # and on SIGUSR2, scroll course windows to their first animated figure
    timeout(100, proc (): bool =
      if figRequested:
        figRequested = false
        scrollToFigure()
      if shotRequested and w.window != nil:
        shotRequested = false
        let ok = saveScreenshot(w.window, shotPath)
        stderr.writeLine "screenshot " & shotPath & ": " & (if ok: "saved" else: "FAILED")
        for (id, cwin) in courseWindows():
          let pth = shotPath.changeFileExt("") & "-" & id & ".png"
          stderr.writeLine "screenshot " & pth & ": " & (if saveScreenshot(cwin, pth): "saved" else: "FAILED")
      true)
  let code = g_application_run(app, 0, nil)
  quit int(code)

main()
