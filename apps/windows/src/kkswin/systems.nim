## Equipment by system: every code on the drawings, grouped block → system → subsystem → component kind (core
## views.systemsView), with a search field, in a window of its own. The tree is a native TreeView (comctl32), so UI
## Automation and the keyboard come with it. Enter, a double-click or the button under the search field opens the
## selected code's tag like a search result does. Typing searches after a 200 ms pause. A sync or an approval rebuilds
## the tree (win.follow), keeping the open groups and the selection, but never while the focus is in the tree.

import std/[strutils, sets]
import kks/[json, views]
import w32, ui, win

const CC = "<commctrl.h>"
type
  HTREEITEM = pointer
  TVITEMW {.importc, header: CC.} = object
    mask: UINT
    hItem: HTREEITEM
    state, stateMask: UINT
    pszText: WideCString
    cchTextMax: cint
    iImage, iSelectedImage, cChildren: cint
    lParam: LPARAM
  TVINSERTSTRUCTW {.importc, header: CC.} = object
    hParent, hInsertAfter: HTREEITEM
    item: TVITEMW
var
  TVI_ROOT {.importc, header: CC, nodecl.}: HTREEITEM
  TVI_LAST {.importc, header: CC, nodecl.}: HTREEITEM
  TVM_INSERTITEMW {.importc, header: CC, nodecl.}: UINT
  TVM_DELETEITEM {.importc, header: CC, nodecl.}: UINT
  TVM_EXPAND {.importc, header: CC, nodecl.}: UINT
  TVM_GETNEXTITEM {.importc, header: CC, nodecl.}: UINT
  TVM_GETITEMW {.importc, header: CC, nodecl.}: UINT
  TVM_SELECTITEM {.importc, header: CC, nodecl.}: UINT
  TVM_GETITEMSTATE {.importc, header: CC, nodecl.}: UINT
  TVM_ENSUREVISIBLE {.importc, header: CC, nodecl.}: UINT
  TVIS_EXPANDED {.importc, header: CC, nodecl.}: UINT
  TVIF_TEXT {.importc, header: CC, nodecl.}: UINT
  TVIF_PARAM {.importc, header: CC, nodecl.}: UINT
  TVE_EXPAND {.importc, header: CC, nodecl.}: WPARAM
  TVGN_CARET {.importc, header: CC, nodecl.}: WPARAM
  TVGN_ROOT {.importc, header: CC, nodecl.}: WPARAM
  TVS_HASBUTTONS {.importc, header: CC, nodecl.}: uint32
  TVS_HASLINES {.importc, header: CC, nodecl.}: uint32
  TVS_LINESATROOT {.importc, header: CC, nodecl.}: uint32
  TVS_SHOWSELALWAYS {.importc, header: CC, nodecl.}: uint32
  NM_DBLCLK {.importc, header: CC, nodecl.}: UINT
  WM_SETREDRAW {.importc, header: "<windows.h>", nodecl.}: UINT

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc n(node: JNode, k: string): int =
  if node != nil and node.get(k) != nil and node[k].isInt: int(node[k].i) else: 0

proc coverWords(photos: string): string =
  ## the photo coverage of the drawings' coverage view, in words (a screen reader reads the row's text)
  case photos
  of "both": "photos: equipment and tag plate"
  of "equipment": "photo: equipment only"
  of "plate": "photo: tag plate only"
  else: "no photos"

proc codes(k: int): string = (if k == 1: "1 code" else: $k & " codes")

type Target = object
  code, tag, sheet: string

var sysWindow: HWND          ## the open window (one at a time)

proc insert(tree: HWND, parent: HTREEITEM, text: string, param = 0): HTREEITEM =
  let ws = newWideCString(text)        # lives until the call returns; the tree copies the text
  var tis = TVINSERTSTRUCTW(hParent: parent, hInsertAfter: TVI_LAST,
                            item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM, pszText: toWideCString(ws), lParam: LPARAM(param)))
  cast[HTREEITEM](SendMessageW(tree, TVM_INSERTITEMW, 0, cast[LPARAM](addr tis)))

proc openSystems*(w: Win) =
  if sysWindow != nil:
    SetForegroundWindow(sysWindow)
    return
  let (hw, p) = popup(w.hwnd, "Equipment by system", 600, 680, proc () = sysWindow = nil, escape = true)
  sysWindow = hw
  var targets: seq[Target]
  var groups: seq[(HTREEITEM, string)]     ## the last fill's group rows and their keys (block|system|…)
  var q, status, tree: HWND
  var follower: Follower
  var pending: uint                        ## the search's timer
  proc fillTree(keep: bool)
  # typing searches once it pauses (each search rebuilds the whole tree: not on every key); what a search finds opens,
  # what was open before doesn't stay open
  q = p.field("Search codes, systems, descriptions", "", onChange = proc () =
    cancel(pending)
    pending = afterMs(200, proc () {.closure.} =
      pending = 0
      if IsWindow(tree) != 0: fillTree(false)))
  sendText(q, EM_SETCUEBANNER, 1, "e.g. LAB70, feed water, valve")
  status = p.dim("")
  proc open() =
    let it = cast[HTREEITEM](SendMessageW(tree, TVM_GETNEXTITEM, TVGN_CARET, 0))
    if it == nil: return
    var tv = TVITEMW(mask: TVIF_PARAM, hItem: it)
    if SendMessageW(tree, TVM_GETITEMW, 0, cast[LPARAM](addr tv)) == 0: return
    let i = int(tv.lParam) - 1
    if i < 0 or i >= targets.len:     # a group: Enter opens or closes it
      SendMessageW(tree, TVM_EXPAND, 3, cast[LPARAM](it))      # TVE_TOGGLE
      return
    let t = targets[i]
    w.selectTag(t.tag, true)     # it shows the sheet itself, after asking whether to drop a selection
  # {.closure.}: see ui.toSpec (a lambda that only calls a nested proc is typed nimcall there)
  p.buttons(("Show the selected code on its drawing", proc () {.closure.} = open()))
  # the static text just before the tree is its name for UI Automation (and screen readers)
  p.dim("Codes by block, system, subsystem and kind. Enter or double-click a code to show it on its drawing; " &
        "Esc closes this window.")
  tree = control(p.hwnd, "SysTreeView32", "", WS_TABSTOP or TVS_HASBUTTONS or TVS_HASLINES or TVS_LINESATROOT or
                 TVS_SHOWSELALWAYS, WS_EX_CLIENTEDGE)[0]
  p.fill(tree, 200)
  onEnter(tree, open)
  onNotify(tree, proc (code: UINT, l: LPARAM): bool =
    if code == NM_DBLCLK:
      later(open)
      return true      # a code opens; the default would also toggle a group, which we do ourselves in open()
    false)

  proc fillTree(keep: bool) =
    ## keep: open the groups that were open and select the row that was selected (a rebuild after a sync)
    if follower != nil: follower.stale = false
    var wasOpen: HashSet[string]
    var selKey = ""
    if keep:
      for (h, k) in groups:
        if (UINT(SendMessageW(tree, TVM_GETITEMSTATE, cast[WPARAM](h), LPARAM(TVIS_EXPANDED))) and TVIS_EXPANDED) != 0:
          wasOpen.incl k
      let cur = cast[HTREEITEM](SendMessageW(tree, TVM_GETNEXTITEM, TVGN_CARET, 0))
      if cur != nil:
        var tv = TVITEMW(mask: TVIF_PARAM, hItem: cur)
        if SendMessageW(tree, TVM_GETITEMW, 0, cast[LPARAM](addr tv)) != 0:
          let i = int(tv.lParam) - 1
          if i >= 0 and i < targets.len: selKey = "code|" & targets[i].code
          else:
            for (h, k) in groups:
              if h == cur: selKey = k
    groups.setLen(0)
    var select: HTREEITEM
    let query = q.text.strip
    let v = systemsView(w.m, query)
    let total = n(v, "total")
    # while searching every level opens, unless that would make too many rows at once
    let all = query.len > 0 and total <= 300
    status.setText(if query.len == 0: codes(total) & " on the drawings"
                   elif total == 0: "Nothing found"
                   else: codes(total) & " found" & (if all: "" else: " (open a system to see them)"))
    SendMessageW(tree, WM_SETREDRAW, 0, 0)
    SendMessageW(tree, TVM_DELETEITEM, 0, cast[LPARAM](TVI_ROOT))
    targets.setLen(0)
    var expand: seq[HTREEITEM]
    proc items(parent: HTREEITEM, arr: JNode) =
      for it in arr.elems:
        var parts = @[s(it, "code")]
        if s(it, "desc").len > 0: parts.add s(it, "desc")
        parts.add s(it, "sheet_name") & (if n(it, "count") > 1: " ×" & $n(it, "count") else: "")
        parts.add coverWords(s(it, "photos"))
        targets.add Target(code: s(it, "code"), tag: s(it, "tag"), sheet: s(it, "sheet"))
        let h = tree.insert(parent, parts.join(" · "), targets.len)
        if selKey == "code|" & s(it, "code"): select = h
    proc group(parent: HTREEITEM, text, key: string, open: bool): HTREEITEM =
      result = tree.insert(parent, text)
      groups.add (result, key)
      if open or key in wasOpen: expand.add result
      if key == selKey: select = result
    for b in v["blocks"].elems:
      let bn = s(b, "blk_name")
      let bk = s(b, "blk")
      # blocks always open: their systems are the first level to read
      let bi = group(TVI_ROOT, if bn.len > 0: bk & " · " & bn else: "Block " & bk, bk, true)
      for sy in b["systems"].elems:
        let sn = s(sy, "sys_name")
        let sk = bk & "|" & s(sy, "sys")
        let si = group(bi, s(sy, "sys") & (if sn.len > 0: " · " & sn else: "") & " (" & $n(sy, "count") & ")", sk, all)
        for sub in sy["subsystems"].elems:
          let subk = sk & "|" & s(sub, "code")
          let ui = group(si, s(sub, "code") & " (" & $n(sub, "count") & ")", subk, all)
          for k in sub["kinds"].elems:
            let cn = s(k, "comp_name")
            let ki = group(ui, s(k, "comp") & (if cn.len > 0: " · " & cn else: "") & " (" & $n(k, "count") & ")",
                           subk & "|" & s(k, "comp"), all)
            items(ki, k["items"])
    let other = v["other"]
    if other.elems.len > 0:
      let oi = group(TVI_ROOT, "Other: codes that don't decode as KKS (" & $other.elems.len & ")", "other", all)
      items(oi, other)
    for h in expand: SendMessageW(tree, TVM_EXPAND, TVE_EXPAND, cast[LPARAM](h))
    if select == nil: select = cast[HTREEITEM](SendMessageW(tree, TVM_GETNEXTITEM, TVGN_ROOT, 0))
    if select != nil:
      SendMessageW(tree, TVM_SELECTITEM, TVGN_CARET, cast[LPARAM](select))
      SendMessageW(tree, TVM_ENSUREVISIBLE, 0, cast[LPARAM](select))
    SendMessageW(tree, WM_SETREDRAW, 1, 0)
    InvalidateRect(tree, nil, 1)

  fillTree(false)
  # a sync or an approval rebuilds the tree (new codes, photo coverage, current tag ids), never under the focus
  follower = w.follow(tree, proc () {.closure.} = fillTree(true))
  p.layout()
  ShowWindow(hw, SW_SHOW)
  SetFocus(q)
