## Bundles: a whole plant in one file (gzip JSON), for joining by file and for moving data without a network.
## {"kks_bundle": 2, "root", "plant", "created", "entries": [...], "blobs": {sha: standard base64}}.

import std/[base64, tables]
import json, node, plantdata, gz

const MaxBundle* = 2 * 1024 * 1024 * 1024 - 1

proc bundle*(n: Node, photos: bool, now: int64): string =
  var blobs = newObj()
  var shas: seq[string]
  let (ok, m) = n.latest   # the plant data always (a device joining by file needs the drawings)
  if ok:
    for _, (sha, _) in m.files: shas.add sha
  if photos and n.run != nil:
    for _, ph in n.run.photos: shas.add ph["blob"].s
  for sha in shas:
    if n.store.blobHas(sha) and not blobs.has(sha): blobs[sha] = newStr(encode(n.store.blobGet(sha)))
  let plant = if n.run != nil and n.run.settings.getOrDefault("plant") != nil: n.run.settings["plant"] else: newNull()
  gzip(toText(newObj(@[("kks_bundle", newInt(2)), ("root", newStr(n.root)), ("plant", plant), ("created", newInt(now div 1000)),
                       ("entries", newArr(n.entriesFor(newObj()))), ("blobs", blobs)])))

proc importBundle*(n: Node, raw: string, wall: int64): JNode =
  ## -> {entries, photos, adopted}. Raises ValueError for anything that isn't a bundle of this plant.
  var d: JNode
  try: d = parseStrict(gunzip(raw, MaxBundle))
  except CatchableError: raise newException(ValueError, "not a Walkdown bundle")
  if d.kind != jObj or d.get("kks_bundle") == nil or d["kks_bundle"].kind != jInt or d["kks_bundle"].i != 2 or
     d.get("entries") == nil or d["entries"].kind != jArr:
    raise newException(ValueError, "not a Walkdown bundle (version 2)")
  var adopted = false
  let root = if d.get("root") != nil and d["root"].kind == jStr: d["root"].s else: ""
  if n.root.len == 0:
    if root.len != 87: raise newException(ValueError, "the bundle names no plant")
    n.adopt(root)
    adopted = true
  elif root != n.root: raise newException(ValueError, "this bundle is from a different plant")
  let got = n.ingest(d["entries"].elems, wall)
  var blobs = 0
  if d.get("blobs") != nil and d["blobs"].kind == jObj:
    for (sha, b64) in d["blobs"].fields:
      if b64.kind == jStr:
        try:
          if n.blobOffer(sha, decode(b64.s)): inc blobs
        except ValueError: discard
  newObj(@[("entries", newInt(got)), ("photos", newInt(blobs)), ("adopted", newBool(adopted))])
