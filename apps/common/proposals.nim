## A proposal (/api/submissions row) in words, shared by the GNOME and Windows Manage pages (Android: Manage.kt
## proposalTitle/ProposalBody, the same rules). Before 2026-10-05 the pages showed the raw payload
## ("changes: {"area":…}") and a "Now: photo <id>: null" line (the user: "unreadable").
import std/strutils
import kks/json

const FieldNames = [("area", "Building / area"), ("floor", "Floor"), ("elev", "Elevation"), ("near", "Near / landmark"),
                    ("loc", "How to find it"), ("notes", "Notes"), ("custom", "Other fields")]

proc str(n: JNode, k: string): string =
  if n == nil or n.kind != jObj or n.get(k) == nil: return ""
  let v = n[k]
  case v.kind
  of jStr: v.s
  of jNull: ""
  of jArr:
    var parts: seq[string]
    for e in v.elems:
      if e.kind == jObj: parts.add str(e, "k") & ": " & str(e, "v") else: parts.add toText(e)
    parts.join("; ")
  else: toText(v)

proc proposalTitle*(sub: JNode): string =
  ## "Location and notes · 10LCE21AA101"
  let p = sub.get("payload")
  let what = case str(sub, "kind")
    of "equipment": "Location and notes"
    of "photo": "New photo"
    of "photo_delete": "Remove a photo"
    of "link": (if p != nil and p.get("on") != nil and p["on"].kind == jBool and not p["on"].b: "Unlink from a procedure step"
                else: "Link to a procedure step")
    of "review": "Tag reading"
    of "tag_add": "Missing tag"
    else: str(sub, "kind")
  var about = str(p, "kks")
  if about.len == 0:
    let t = str(sub, "target")
    about = if ':' in t: t.split(':', 1)[1] else: t
  if about.len > 0: what & " · " & about else: what

proc proposalRows*(sub: JNode): seq[(string, string)] =
  ## (label, value) rows; a changed field reads "new  (was: old)", and "(now: …)" when it changed since
  let p = sub.get("payload")
  if p == nil or p.kind != jObj: return
  case str(sub, "kind")
  of "equipment":
    let ch = p.get("changes")
    let base = p.get("base")
    var live: JNode = nil
    if sub.get("live") != nil and sub["live"].kind == jArr and sub["live"].elems.len > 0: live = sub["live"].elems[0].get("value")
    if ch != nil and ch.kind == jObj:
      for (k, _) in ch.fields:
        var name = k
        for (f, n) in FieldNames:
          if f == k: name = n
        let old = str(base, k)
        let now = str(live, k)
        var v = str(ch, k)
        if v.len == 0: v = "(empty)"
        if old.len > 0: v.add "   (was: " & old & ")"
        if now.len > 0 and now != old: v.add "   (now: " & now & ")"
        result.add (name, v)
  of "photo":
    if str(p, "caption").len > 0: result.add ("Caption", str(p, "caption"))
  of "link":
    result.add ("Procedure", str(p, "proc"))
    result.add ("Step", str(p, "step"))
  of "review":
    let d = p.get("data")
    result.add ("Decision", if str(d, "status") == "rejected": "Not a tag" else: "Confirmed")
    if str(d, "kks").len > 0: result.add ("KKS", str(d, "kks") & str(d, "suffix"))
    if str(d, "isa").len > 0: result.add ("Function letters", str(d, "isa"))
  of "tag_add":
    result.add ("Sheet", str(p, "sheet"))
    if str(p, "isa").len > 0: result.add ("Function letters", str(p, "isa"))
    if str(p, "note").len > 0: result.add ("Note", str(p, "note"))
  of "photo_delete": discard
  else:
    for (k, v) in p.fields:
      if k in ["base", "dataUrl", "blob", "photo_id", "id", "file"]: continue
      let t = str(p, k)
      if t.len > 0: result.add (k, if t.len > 160: t[0 ..< 160] & "…" else: t)
