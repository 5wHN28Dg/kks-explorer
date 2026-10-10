## Several tags at once, the "Select tags" mode (the GNOME app's multi.nim, for Win32): pick tags on the drawing (a
## click toggles one, a dragged box adds every tag it touches; from the keyboard or a screen reader, a tag button of the
## drawing or a search result toggles its tag), then one photo, place or note for all their codes, sent as one
## /api/submit-many (core api.submitMany: an ordinary submission per code; a photo's image is kept once).
## While the mode is on, the right-hand panel shows the selection and the "… for all" actions.
## The selection is a list of codes, not of tags of one drawing (the user, 2026-10-10: equipment in one place is often
## on different P&IDs): a search result of any sheet joins it without the drawing changing, the List takes typed or
## pasted codes, and switching drawings keeps it.

import std/[strutils, sets, os, random, times]
import kks/[json, api]
import kks/model
import appstate
import w32, ui, viewer, win, photos

const PlaceFields = [("area", "Building / area", "a building / area"), ("floor", "Floor", "a floor"),
                     ("elev", "Elevation", "an elevation"), ("near", "Near / landmark", "a landmark"),
                     ("loc", "How to find it", "directions")]

## codes in one selection: the server takes up to 200 per submit-many (core api.submitMany). Tests: KKS_MAX_PICK lowers it.
let MaxPick = (try: max(1, min(200, parseInt(getEnv("KKS_MAX_PICK", "200")))) except ValueError: 200)

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

var
  pickRound = 0           ## the selection round, new each time the mode starts or ends: a photo editor opened in an
                          ## earlier round still sends for its own codes, but leaves a newer selection alone
  roundWins: seq[HWND]    ## this round's List, Place for all and Note for all windows: closed when the round ends

proc roundPopup(w: Win, title: string, width, height: int): (HWND, Page) =
  ## a window that belongs to this selection round (closed with it, so an old one can't act on a newer selection)
  var hw: HWND
  let (h, p) = popup(w.hwnd, title, width, height, onClose = (proc () =
    let i = roundWins.find(hw)
    if i >= 0: roundWins.delete(i)), escape = true)
  hw = h
  roundWins.add h
  (h, p)

proc closeRoundWindows() =
  let open = roundWins
  roundWins.setLen(0)
  for h in open:
    if IsWindow(h) != 0: DestroyWindow(h)

proc countText*(n: int): string = $n & " selected"

proc syncChosen*(w: Win) =
  ## the drawing's outline follows the selected codes (every tag that shows one of them)
  if w.v == nil: return
  w.v.chosen.clear()
  if w.picking and w.picked.len > 0:
    let codes = toHashSet(w.picked)
    for t in w.v.tags:
      if t.status != "pending" and t.code in codes: w.v.chosen.incl t.id
  w.v.invalidate()

var
  listWin: HWND             ## the List, while it is open
  listRefresh: proc ()      ## puts the selection as it is now into the open List
  listActs = false          ## the List itself is changing the selection (its rows stay as they are)

proc updatePick(w: Win) =
  w.syncChosen()
  # the selection changed outside the open List (a tag, a search result, a photo queued for some): its rows follow
  if not listActs and listRefresh != nil and listWin != nil and IsWindow(listWin) != 0: listRefresh()
  w.rebuildPanel()          # the panel shows the count and the actions while the mode is on

proc unreadOnce(w: Win) =
  if not w.pickSaidUnread:
    w.pickSaidUnread = true
    w.toast("Tags without a code can't be selected: review them first")

proc sheetsOf(w: Win, code: string): (string, seq[string]) =
  ## what a code is (its first tag's kind) and the names of the drawings that show it, in the sheet list's order
  var ids: seq[string]
  for t in w.m.tags:
    if t.full == code:
      if result[0].len == 0: result[0] = w.m.kindName(t)
      if t.sheet notin ids: ids.add t.sheet
  for si in w.m.sheets:
    if si.id in ids: result[1].add si.name
  for id in ids:                      # a tag whose sheet isn't listed (not synced yet): its id
    if not w.m.sheetById(id)[0]: result[1].add id

proc togglePick*(w: Win, id: string) =
  let (ok, t) = w.m.tagById(id)
  if not ok: return
  let k = t.full
  if k.len == 0:
    w.unreadOnce()
    return
  let i = w.picked.find(k)
  if i < 0 and w.picked.len >= MaxPick:
    w.toast("At most " & $MaxPick & " tags at once: send these first")
    return
  if i >= 0: w.picked.delete(i) else: w.picked.add k
  # a result of another drawing (the search): said, since nothing shows on this one
  var here = false                    # (a code that is on this drawing too shows here: nothing to say)
  for x in w.m.tags:
    if x.full == k and x.sheet == w.sheet: here = true
  let (okS, si) = w.m.sheetById(t.sheet)
  let other = if not here: " (on " & (if okS: si.name else: t.sheet) & ")" else: ""
  w.toast(k & other & (if i >= 0: " removed, " else: " selected, ") & countText(w.picked.len))
  w.updatePick()

proc splitCodes*(text: string): seq[string] =
  ## typed or pasted codes: separated by spaces, commas, semicolons or new lines; upper case; each once
  # (a no-break space, as pasted from a table or a web page, separates too)
  for part in text.replace("\xC2\xA0", " ").toUpperAscii.split({' ', '\t', '\r', '\n', ',', ';'}):
    if part.len > 0 and part notin result: result.add part

proc addCodes(w: Win, text: string): string =
  ## "Add codes" (the List): each code that is on some drawing joins the selection; -> what happened, for the person
  let want = splitCodes(text)
  if want.len == 0: return "Type or paste KKS codes first"
  var known: HashSet[string]
  for t in w.m.tags:
    if t.full.len > 0: known.incl t.full
  var added, already, over = 0
  var unknown: seq[string]
  for k in want:
    if k notin known: unknown.add k
    elif k in w.picked: inc already
    elif w.picked.len >= MaxPick: inc over
    else:
      w.picked.add k
      inc added
  var parts = @[(if added == 1: "1 code added" else: $added & " codes added")]
  if already > 0: parts.add $already & " already selected"
  if unknown.len > 0:
    parts.add "not on any drawing, not added: " & unknown[0 ..< min(10, unknown.len)].join(", ") &
              (if unknown.len > 10: " and " & $(unknown.len - 10) & " more" else: "")
  if over > 0: parts.add $over & " left out (at most " & $MaxPick & " tags at once: send these first)"
  result = parts.join(" · ") & " · " & countText(w.picked.len)
  if added > 0:
    listActs = true           # (the List fills itself again after this)
    try: w.updatePick()
    finally: listActs = false

proc addBox*(w: Win, x0, y0, x1, y1: float) =
  ## a dragged box (points): adds every tag it touches (never removes)
  var added = 0
  var unread, full = false
  for id in w.v.tagsIn(x0, y0, x1, y1):
    let (ok, t) = w.m.tagById(id)
    if not ok: continue
    if t.full.len == 0:
      unread = true
    elif t.full notin w.picked:
      if w.picked.len >= MaxPick:
        full = true
        break
      w.picked.add t.full
      inc added
  if full: w.toast("At most " & $MaxPick & " tags at once: send these first")
  elif unread and not w.pickSaidUnread: w.unreadOnce()
  else: w.toast((if added == 1: "1 code added, " else: $added & " codes added, ") & countText(w.picked.len))
  w.updatePick()

proc stopPicking*(w: Win) =
  if not w.picking: return
  w.picking = false
  inc pickRound
  closeRoundWindows()
  w.picked.setLen(0)
  w.v.endSelecting()        # a box being dragged goes too
  w.syncChosen()
  w.relayout()
  w.rebuildPanel()
  w.rebuildSide()           # the toggle, and what a search result does

proc startPicking*(w: Win) =
  if w.picking: return
  w.v.marking = false
  w.picking = true
  inc pickRound
  closeRoundWindows()
  w.pickSaidUnread = false
  w.picked.setLen(0)
  w.v.selecting = true
  w.toast("Select tags: click tags, or drag a box around several; from the keyboard, search and pick a result")
  w.syncChosen()
  w.relayout()
  w.rebuildPanel()
  w.rebuildSide()

proc listWindow(w: Win) =
  ## the selected codes, each with a check box and the drawings it is on: turn a mistake off (on again puts it back);
  ## "Add codes" takes codes typed or pasted, of any drawing
  if listWin != nil and IsWindow(listWin) != 0:       # one List: it follows the selection
    SetForegroundWindow(listWin)
    return
  var hw: HWND
  let (h, p) = w.roundPopup("Selected codes", 480, 560)
  hw = h
  var codes = w.picked        # the rows: a code turned off keeps its row (on again puts it back) until the next Add
  var e: HWND
  var said = ""
  proc fill(typed: string) =
    p.clear()
    for k in w.picked:
      if k notin codes: codes.add k
    # several lines: a single-line field would keep only the first line of a pasted column of codes
    let field = p.multiField("KKS codes to add (separated by spaces, commas or new lines)", typed, height = 64)
    e = field
    var addNow: proc ()
    addNow = proc () =
      # (a second click queued behind the first finds its field gone: the first one's answer stands)
      if not w.picking or e != field or IsWindow(field) == 0: return
      let msg = w.addCodes(e.text)
      w.toast(msg)
      # what was not added stays in the field, to be corrected
      var rest: seq[string]
      for k in splitCodes(e.text):
        if k notin w.picked: rest.add k
      codes = w.picked                # rows turned off before go: the list is the selection again
      said = msg
      fill(rest.join(" "))
      SetFocus(e)
    p.buttons(("Add codes", addNow))
    if said.len > 0: p.label(said)
    if codes.len == 0: p.dim("Nothing selected. Click tags on the drawing, pick search results, or add codes here.")
    else: p.dim("Turn a code off to leave it out")
    for i in 0 ..< codes.len:
      closureScope:
        let k = codes[i]
        let (kind, sheets) = w.sheetsOf(k)
        let where = (if kind.len > 0: kind & " · " else: "") & sheets.join(", ")
        p.check(k & (if where.len > 0: "  (" & where & ")" else: ""), k in w.picked, proc (on: bool) =
          if not w.picking: return
          let j = w.picked.find(k)
          if on and j < 0:
            if w.picked.len >= MaxPick:
              w.toast("At most " & $MaxPick & " tags at once: send these first")
              return
            w.picked.add k
          elif not on and j >= 0: w.picked.delete(j)
          listActs = true             # the row stays, off: on again puts the code back
          try: w.updatePick()
          finally: listActs = false)
    p.buttons(("Close the list", proc () = DestroyWindow(hw)))
    p.layout()
  fill("")
  SetFocus(e)
  listWin = hw
  listRefresh = proc () =
    # a code selected elsewhere gets a row, one unselected elsewhere keeps its row, off; what is typed stays
    # (the field's line breaks are CR LF, and the field makes them from LF itself)
    if IsWindow(e) == 0: return
    fill(e.text.replace("\r\n", "\n"))
  ShowWindow(hw, SW_SHOW)

proc clientPrefix(): string =
  ## submit-many's client_id prefix: code i goes as "<prefix>-<i>", so a retry duplicates nothing
  randomize()
  result = "wm" & $(getTime().toUnix) & "x"
  for _ in 0 ..< 10: result.add "0123456789abcdef"[rand(15)]

proc basesOf(w: Win, codes: seq[string], changes: JNode): JNode =
  ## the values this device shows now for the fields `changes` replaces (core submitMany `bases`): a value someone
  ## changed after this is a clash, not overwritten silently. Taken before any question is asked: while one is open
  ## the timer keeps syncing and reloading the model, and a base read after it would be the newer value.
  result = newObj()
  for k in codes:
    let e = w.m.equipment(k)
    var b = newObj()
    if changes != nil:                          # replaced fields only: an appended note can't lose anything
      for (f, _) in changes.fields:
        b[f] = (if e.get(f) != nil: e[f] else: newStr(""))
    result[k] = b

proc doneWith(w: Win, round: int, codes: seq[string]) =
  ## these codes were sent (or their photo queued): the mode ends for them if it is still the round the photo or form
  ## was opened in
  if round == pickRound:
    # codes picked after the photo or form was opened weren't in this send: they stay selected, the mode on
    var rest: seq[string]
    for k in w.picked:
      if k notin codes: rest.add k
    if rest.len == 0: w.stopPicking()
    else:
      w.picked = rest
      w.updatePick()
  else: w.syncChosen()      # a photo from an earlier round: the selection made since stays

proc sendMany(w: Win, round: int, codes: seq[string], kind: string, payload: JNode, note: string): bool =
  ## one submit-many for these codes (the selection when the photo or form was opened: what its title said); says how
  ## it went and leaves the mode if it is still the round the photo or form was opened in
  if codes.len == 0:
    w.toast("Nothing selected")
    return false
  var arr = newArr()
  for k in codes: arr.elems.add newStr(k)
  if kind == "equipment" and payload.get("bases") == nil: payload["bases"] = w.basesOf(codes, payload.get("changes"))
  var body = newObj(@[("kind", newStr(kind)), ("kks", arr), ("payload", payload), ("client_id", newStr(clientPrefix()))])
  if note.strip.len > 0: body["note"] = newStr(note.strip)
  var r: JNode
  try: r = w.a.call("POST", "/api/submit-many", body)
  except ApiError as e:
    w.toast(e.msg)
    return false
  var pending, held = 0
  if r.get("results") != nil:
    for x in r["results"].elems:
      case s(x, "status")
      of "approved": discard
      of "conflict": inc held
      else: inc pending
  let n = codes.len
  var msg = "Sent for " & (if n == 1: "1 code" else: $n & " codes")
  if pending > 0: msg.add " · " & $pending & " await approval"
  if held > 0: msg.add " · " & $held & " held (they clash with pending changes)"
  if pending == 0 and held == 0: msg.add " · saved"
  w.loadModel()
  if w.sheet.len > 0: w.v.tags = w.tagBoxes(w.sheet)
  w.doneWith(round, codes)
  w.toast(msg)
  true

var floorAsk: HWND          ## Photo for all's floor question, while it is open

proc photoForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  # asked already: one question, and for the selection as it is now (it may have changed since)
  if floorAsk != nil and IsWindow(floorAsk) != 0: DestroyWindow(floorAsk)
  let codes = w.picked     # the editor is a window of its own: the selection may change while it is open
  let round = pickRound
  # kept on disk and compressed on the queue's worker thread like any photo (photos.nim), then one submit-many
  proc go(floor: string) =
    w.photoForCodes(codes, floor, proc () =
      w.doneWith(round, codes)
      w.toast("Photo queued for " & (if codes.len == 1: "1 code" else: $codes.len & " codes") &
              ": it is sent once compressed"))
  # the user's rule: a photo needs its equipment's floor. Asked here, before the picture, for the codes that have
  # none (as one photo of one code does), and sent with the photo: a member can't set a floor first (it needs
  # approval before it counts), so nothing is refused for a missing floor
  # A floor still riding on a queued or kept photo doesn't count here: the job keeps one floor for its codes and the
  # core writes it for every code that has none when it arrives, so a code left out of the question could get this
  # floor (its own photo failed and waits) or none (that photo discarded). Such a code is asked again
  let missing = w.floorsMissing(codes, queued = false)
  if missing.len == 0:
    go("")
    return
  var hw: HWND
  hw = w.askFloors(missing, codes.len, go, closed = proc () =
    let i = roundWins.find(hw)
    if i >= 0: roundWins.delete(i)
    if floorAsk == hw: floorAsk = nil)
  floorAsk = hw
  roundWins.add hw           # the question belongs to this selection round: it closes with it

proc placeForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  var hw: HWND
  let (h, p) = w.roundPopup("Place for all", 460, 520)
  hw = h
  let codes = w.picked     # the form is a window of its own: it sends for what its title says
  let round = pickRound
  p.title(countText(codes.len))
  p.dim("Only the fields you fill are sent; the others stay as they are for each code.")
  var entries: seq[(string, string, HWND)]
  for (f, title, noun) in PlaceFields:
    entries.add((f, noun, p.field(title & (if f == "floor": " (0–10)" else: ""), "")))
  let note = if not w.isAdmin: p.field("Note for the approver (optional)", "") else: nil
  p.buttons(("Send", proc () =
    var changes = newObj()
    var lines: seq[string]
    for (f, noun, e) in entries:
      let v = e.text.strip
      if v.len == 0: continue
      if f == "floor" and not (v == "10" or (v.len == 1 and v[0] in Digits)):
        w.toast("Floor: a whole number from 0 to 10 (the height goes in Elevation)")
        return
      changes[f] = newStr(v)
      var have = 0
      for k in codes:
        let cur = s(w.m.equipment(k), f).strip
        if cur.len > 0 and cur != v: inc have
      if have > 0:
        lines.add $have & " of " & $codes.len & " already have " & noun & "; it will be replaced."
    if changes.len == 0:
      w.toast("Fill at least one field")
      return
    # what this device shows now, before the question: the sync goes on while it is open
    let payload = newObj(@[("changes", changes), ("bases", w.basesOf(codes, changes))])
    if lines.len > 0 and not ask(hw, "Replace values?", lines.join("\n")): return
    if round != pickRound: return     # the round ended while the question was open (its window went with it)
    if w.sendMany(round, codes, "equipment", payload, if note != nil: note.text else: "") and hw in roundWins:
      DestroyWindow(hw)),             # (unless the round's end has closed it already)
    ("Cancel", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)

proc noteForAll*(w: Win) =
  if w.picked.len == 0:
    w.toast("Select tags first")
    return
  var hw: HWND
  let (h, p) = w.roundPopup("Note for all", 460, 360)
  hw = h
  let codes = w.picked
  let round = pickRound
  p.title(countText(codes.len))
  p.dim("Added under each code's own notes; nothing already there is removed.")
  let e = p.field("Note", "")
  let note = if not w.isAdmin: p.field("Note for the approver (optional)", "") else: nil
  p.buttons(("Send", proc () =
    let v = e.text.strip
    if v.len == 0:
      w.toast("Write the note first")
      return
    if w.sendMany(round, codes, "equipment", newObj(@[("append", newObj(@[("notes", newStr(v))]))]),
                  if note != nil: note.text else: "") and hw in roundWins:
      DestroyWindow(hw)),             # (unless the round's end has closed it already)
    ("Cancel", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)

proc pickPanel*(w: Win, p: Page) =
  ## the right-hand panel while the mode is on: the count and the actions
  p.clear()
  p.title("Select tags")
  p.label(countText(w.picked.len))
  p.dim("Click tags or drag a box · or search and pick results, on any drawing · or add codes in the List. " &
        "Escape on the drawing ends the mode.")
  p.buttons(("List", proc () = w.listWindow()))
  p.buttons(("Photo for all…", proc () = w.photoForAll()))
  p.buttons(("Place for all…", proc () = w.placeForAll()))
  p.buttons(("Note for all…", proc () = w.noteForAll()))
  p.buttons(("Done", proc () = w.stopPicking()))
  if w.picked.len > 0:
    p.title("In the selection")
    for k in w.picked: p.label(k)
  p.layout()
