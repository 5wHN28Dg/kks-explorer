## Plant data (PROTOCOL-v2 §19): drawings, tag lists, procedures, locations and course content, published by the
## manager as a `plant_data` setting and delivered as blobs. A device serves the newest version it holds completely,
## never a mix. Port of v1's server/plantdata.py.

import std/[algorithm, strutils, tables]
import json, crypto, util, node

const MaxFiles* = 5000

type Manifest* = object
  version*: int64
  files*: OrderedTable[string, (string, int64)]   ## path → (sha, size)

proc validPath*(p: string): bool =
  var rest = p
  if p.startsWith("sheets/"): rest = p[7 .. ^1]
  elif p.startsWith("courses/"): rest = p[8 .. ^1]
  rest.len in 1..64 and rest[0] in {'a'..'z', '0'..'9'} and rest.allCharsInSet({'a'..'z', '0'..'9', '.', '_', '-'}) and
    ".." notin p

proc manifest*(v: JNode): (bool, Manifest) =
  ## A plant_data setting value -> (ok, manifest).
  if v == nil or v.kind != jObj or v.get("version") == nil or v["version"].kind != jInt or v["version"].i < 1: return
  let files = v.get("files")
  if files == nil or files.kind != jArr or files.len > MaxFiles: return
  var m = Manifest(version: v["version"].i)
  for f in files.elems:
    if not (f.kind == jArr and f.len == 3 and f[0].kind == jStr and validPath(f[0].s) and f[1].kind == jStr and
            f[1].s.len == 64 and f[1].s.allCharsInSet(HexDigits - {'A'..'F'}) and f[2].kind == jInt and f[2].i >= 0) or
       f[0].s in m.files:
      return
    m.files[f[0].s] = (f[1].s, f[2].i)
  (true, m)

proc latest*(n: Node): (bool, Manifest) =
  if n.run == nil: return
  manifest(n.run.settings.getOrDefault("plant_data"))

proc plain(m: Manifest): JNode =
  var paths: seq[string]
  for p, _ in m.files: paths.add p
  paths.sort(system.cmp)
  result = newArr()
  for p in paths: result.elems.add newArr(@[newStr(p), newStr(m.files[p][0]), newInt(m.files[p][1])])

proc complete(n: Node, m: Manifest): bool =
  for _, (sha, _) in m.files:
    if not n.store.blobHas(sha): return false
  true

proc active*(n: Node): (bool, Manifest) =
  ## The version to serve: the latest if complete, else the last complete one served (meta plant_data_active).
  let (ok, m) = n.latest
  if ok and n.complete(m):
    let s = toText(newObj(@[("version", newInt(m.version)), ("files", plain(m))]))
    if n.store.getMeta("plant_data_active") != s: n.store.setMeta("plant_data_active", s)
    return (true, m)
  let stored = n.store.getMeta("plant_data_active")
  if stored.len > 0:
    let (ok2, m2) = manifest(parseStrict(stored))
    if ok2 and n.complete(m2): return (true, m2)

proc file*(n: Node, path: string): (bool, string) =
  ## The bytes of plant file `path` in the active version.
  let (ok, a) = n.active
  if ok and path in a.files: return (true, n.store.blobGet(a.files[path][0]))

proc status*(n: Node): JNode =
  let (ok, m) = n.latest
  let (aok, a) = n.active
  var missing: Table[string, int64]
  if ok:
    for _, (sha, size) in m.files:
      if not n.store.blobHas(sha): missing[sha] = size
  var bytes = 0'i64
  for _, s in missing: bytes += s
  newObj(@[("version", if ok: newInt(m.version) else: newNull()), ("active", if aok: newInt(a.version) else: newNull()),
           ("files", newInt(if ok: m.files.len else: 0)), ("missing", newInt(missing.len)), ("missing_bytes", newInt(bytes))])

proc publishAs*(n: Node, key: PrivateKey, files: seq[(string, string)], wall: int64): int64 =
  ## A new version from (path, bytes) pairs, signed by `key` (a device of the manager). -> its number, or 0 when the
  ## files equal the latest version's.
  var hasSheets = false
  for (p, _) in files:
    if not validPath(p): raise newException(ValueError, "bad plant file path: " & p)
    if p == "sheets.json": hasSheets = true
  if not hasSheets: raise newException(ValueError, "no sheets.json")
  if files.len > MaxFiles: raise newException(ValueError, "too many files")
  var m = Manifest()
  for (p, data) in files: m.files[p] = (n.keepBlob(data), int64(data.len))
  let (ok, cur) = n.latest
  if ok and toText(plain(cur)) == toText(plain(m)): return 0
  m.version = (if ok: cur.version else: 0) + 1
  discard n.appendAs(key, "setting", newObj(@[("key", newStr("plant_data")),
                                       ("value", newObj(@[("version", newInt(m.version)), ("files", plain(m))]))]), wall)
  m.version

proc publish*(n: Node, files: seq[(string, string)], wall: int64): int64 =
  ## publishAs with this device's own key.
  n.publishAs(n.key, files, wall)
