## The node's Store on SQLite, sealed at rest (decision 0020): every row's content is AES-256-GCM under the device's
## storage key; the associated data names the table and the row, so rows can't be swapped. The key comes from the
## platform key store (libsecret on GNOME, systemd-creds on the server); this module only takes the 32 bytes.

import std/[os, strutils, tables]
import kks/[json, crypto, util, node]
import sqlite

type DbStore* = ref object of Store
  db*: PDb
  p: Provider
  key: seq[byte]
  path*: string

const Schema = """
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
CREATE TABLE IF NOT EXISTS entries(id TEXT PRIMARY KEY, peer TEXT NOT NULL, seq INTEGER NOT NULL, data BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS evidence(id TEXT PRIMARY KEY, data BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS blobs(sha TEXT PRIMARY KEY, data BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS rows(tbl TEXT NOT NULL, k TEXT NOT NULL, v BLOB NOT NULL, PRIMARY KEY(tbl, k));
"""

proc seal(s: DbStore, where, plain: string): string =
  let nonce = s.p.randomBytes(12)
  nonce.toStr & s.p.aesGcmSeal(s.key, nonce, plain.toBytes, toBytes("kks-store-v2\n" & where)).toStr

proc open(s: DbStore, where, sealed: string): string =
  if sealed.len < 28: raise newException(CryptoError, "sealed row too short")
  s.p.aesGcmOpen(s.key, sealed[0 ..< 12].toBytes, sealed[12 .. ^1].toBytes, toBytes("kks-store-v2\n" & where)).toStr

proc openDbStore*(p: Provider, path: string, storageKey: seq[byte]): DbStore =
  if storageKey.len != 32: raise newException(ValueError, "storage key must be 32 bytes")
  createDir(parentDir(path))
  result = DbStore(db: sqlite.open(path), p: p, key: storageKey, path: path)
  result.db.exec(Schema)
  # a wrong key must fail loudly at open, not later
  let probe = result.getMeta("store_probe")
  if probe.len == 0: result.setMeta("store_probe", "ok")

method loadEntries*(s: DbStore): seq[StoredEntry] =
  for r in s.db.rows("SELECT id, data FROM entries ORDER BY peer, seq"):
    let id = r.colText(0)
    result.add((id, parseStrict(s.open("entries/" & id, r.colText(1)))))

method putEntry*(s: DbStore, id: string, e: JNode) =
  s.db.run("INSERT OR IGNORE INTO entries(id, peer, seq, data) VALUES(?,?,?,?)",
           t(id), t(e["peer"].s), i(e["seq"].i), b(s.seal("entries/" & id, toText(e))))

method loadEvidence*(s: DbStore): seq[StoredEntry] =
  for r in s.db.rows("SELECT id, data FROM evidence"):
    let id = r.colText(0)
    result.add((id, parseStrict(s.open("evidence/" & id, r.colText(1)))))

method putEvidence*(s: DbStore, id: string, e: JNode) =
  s.db.run("INSERT OR IGNORE INTO evidence(id, data) VALUES(?,?)", t(id), b(s.seal("evidence/" & id, toText(e))))

method blobHas*(s: DbStore, sha: string): bool =
  for r in s.db.rows("SELECT 1 FROM blobs WHERE sha=?", t(sha)): return true

method blobGet*(s: DbStore, sha: string): string =
  for r in s.db.rows("SELECT data FROM blobs WHERE sha=?", t(sha)): return s.open("blobs/" & sha, r.colText(0))

method blobPut*(s: DbStore, sha, data: string) =
  s.db.run("INSERT OR IGNORE INTO blobs(sha, data) VALUES(?,?)", t(sha), b(s.seal("blobs/" & sha, data)))

method getMeta*(s: DbStore, key: string): string =
  for r in s.db.rows("SELECT v FROM meta WHERE k=?", t(key)): return s.open("meta/" & key, r.colText(0))

method setMeta*(s: DbStore, key, value: string) =
  s.db.run("INSERT OR REPLACE INTO meta(k, v) VALUES(?,?)", t(key), b(s.seal("meta/" & key, value)))

# ---------------------------------------------------------------- sealed records (local tables: not log data)

proc putRow*(s: DbStore, tbl, key: string, v: JNode) =
  s.db.run("INSERT OR REPLACE INTO rows(tbl, k, v) VALUES(?,?,?)", t(tbl), t(key), b(s.seal("rows/" & tbl & "/" & key, toText(v))))

proc getRow*(s: DbStore, tbl, key: string): JNode =
  for r in s.db.rows("SELECT v FROM rows WHERE tbl=? AND k=?", t(tbl), t(key)):
    return parseStrict(s.open("rows/" & tbl & "/" & key, r.colText(0)))

proc delRow*(s: DbStore, tbl, key: string) = s.db.run("DELETE FROM rows WHERE tbl=? AND k=?", t(tbl), t(key))

proc allRows*(s: DbStore, tbl: string): seq[(string, JNode)] =
  for r in s.db.rows("SELECT k, v FROM rows WHERE tbl=? ORDER BY k", t(tbl)):
    let k = r.colText(0)
    result.add((k, parseStrict(s.open("rows/" & tbl & "/" & k, r.colText(1)))))

proc subKey(id: int64): string = align($id, 12, '0')

method subs*(s: DbStore): seq[JNode] =
  let all = s.allRows("subs")
  for i in countdown(all.high, 0): result.add all[i][1]

method putSub*(s: DbStore, row: JNode): int64 =
  if row["id"].isNull:
    let last = s.allRows("subs")
    result = if last.len == 0: 1 else: last[^1][1]["id"].i + 1
    row["id"] = newInt(result)
  else:
    result = row["id"].i
  s.putRow("subs", subKey(result), row)

method notes*(s: DbStore): seq[(string, string)] =
  for (k, v) in s.allRows("notes"): result.add((k, v.s))

method putNote*(s: DbStore, eid, note: string) = s.putRow("notes", eid, newStr(note))

method begin*(s: DbStore) =
  ## BEGIN IMMEDIATE: the write lock is taken now, so no other writer (another process on this file) can make the
  ## commit fail half-way with "busy". Not nested: a second begin is refused (see Node.atomic).
  if s.db.inTransaction: raise newException(ValueError, "a store transaction is already open")
  s.db.exec("BEGIN IMMEDIATE")

method commit*(s: DbStore) = s.db.exec("COMMIT")

method rollback*(s: DbStore) =
  ## SQLite may already have undone the transaction itself (some failed statements and a failed COMMIT do). A ROLLBACK
  ## that fails with the transaction still open closes the connection (which undoes it): the writes that come after
  ## must fail, not go into a transaction nobody commits while the node takes them into memory.
  if not s.db.inTransaction: return
  try:
    s.db.exec("ROLLBACK")
  except SqliteError:
    if s.db.inTransaction:
      s.db.close()
      s.db = nil
    raise

proc transaction*(s: DbStore, body: proc ()) =
  ## the platform's own local rows (not log entries: those go through Node.atomic, which keeps memory in step)
  s.begin()
  try:
    body()
    s.commit()
  except:
    s.rollback()
    raise

proc wipe*(s: DbStore, note: string) =
  ## A removed device deletes its plant data (§15) in place, and keeps a note for the setup screen. secure_delete
  ## overwrites the deleted content as it goes, so the data is gone even when VACUUM must wait: on Windows a scanner
  ## holding the file made VACUUM fail with "disk I/O error" once (2026-10-01), which ended the app. VACUUM and the
  ## WAL truncation are retried, then left for the next start (the rows are already overwritten).
  s.db.exec("PRAGMA secure_delete = ON")
  s.db.exec("DELETE FROM entries; DELETE FROM evidence; DELETE FROM blobs; DELETE FROM meta; DELETE FROM rows;")
  s.setMeta("removed", note)
  for attempt in 0 ..< 5:
    try:
      s.db.exec("VACUUM; PRAGMA wal_checkpoint(TRUNCATE);")
      return
    except CatchableError as e:
      stderr.writeLine "wipe: compaction failed (" & e.msg & "), retrying"
      sleep(300)

proc close*(s: DbStore) = s.db.close()
