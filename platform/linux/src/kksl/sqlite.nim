## The SQLite C API, the part we use (decision 0030). The `header` pragma lets the C compiler check these.

when defined(kksBundledSqlite):
  # Android (decision 0032): the NDK has no SQLite, so the pinned amalgamation is compiled in (android/nim/build.sh)
  const sqliteDir {.strdefine.} = ""
  {.passC: "-I" & sqliteDir & " -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DQS=0".}
  {.compile: sqliteDir & "/sqlite3.c".}
else:
  {.passL: "-lsqlite3".}
const H = "<sqlite3.h>"

type
  Db* {.importc: "sqlite3", header: H, incompleteStruct.} = object
  Stmt* {.importc: "sqlite3_stmt", header: H, incompleteStruct.} = object
  PDb* = ptr Db
  PStmt* = ptr Stmt
  SqliteError* = object of CatchableError

var
  SQLITE_OK* {.importc, header: H, nodecl.}: cint
  SQLITE_ROW* {.importc, header: H, nodecl.}: cint
  SQLITE_DONE* {.importc, header: H, nodecl.}: cint
  SQLITE_OPEN_READWRITE {.importc, header: H, nodecl.}: cint
  SQLITE_OPEN_CREATE {.importc, header: H, nodecl.}: cint
  SQLITE_OPEN_FULLMUTEX {.importc, header: H, nodecl.}: cint
  SQLITE_TRANSIENT {.importc, header: H, nodecl.}: pointer

proc sqlite3_open_v2(name: cstring, db: ptr PDb, flags: cint, vfs: cstring): cint {.importc, header: H.}
proc sqlite3_close_v2(db: PDb): cint {.importc, header: H.}
proc sqlite3_errmsg(db: PDb): cstring {.importc, header: H.}
proc sqlite3_exec(db: PDb, sql: cstring, cb: pointer, arg: pointer, err: ptr cstring): cint {.importc, header: H.}
proc sqlite3_prepare_v2(db: PDb, sql: cstring, n: cint, s: ptr PStmt, tail: pointer): cint {.importc, header: H.}
proc sqlite3_bind_text(s: PStmt, i: cint, v: cstring, n: cint, d: pointer): cint {.importc, header: H.}
proc sqlite3_bind_blob(s: PStmt, i: cint, v: pointer, n: cint, d: pointer): cint {.importc, header: H.}
proc sqlite3_bind_int64(s: PStmt, i: cint, v: int64): cint {.importc, header: H.}
proc sqlite3_step(s: PStmt): cint {.importc, header: H.}
proc sqlite3_column_bytes(s: PStmt, i: cint): cint {.importc, header: H.}
proc sqlite3_column_blob(s: PStmt, i: cint): pointer {.importc, header: H.}
proc sqlite3_column_int64(s: PStmt, i: cint): int64 {.importc, header: H.}
proc sqlite3_finalize(s: PStmt): cint {.importc, header: H.}
proc sqlite3_get_autocommit(db: PDb): cint {.importc, header: H.}

proc check(db: PDb, r: cint) =
  if r != SQLITE_OK: raise newException(SqliteError, $sqlite3_errmsg(db))

proc open*(path: string): PDb =
  let r = sqlite3_open_v2(path, addr result, SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE or SQLITE_OPEN_FULLMUTEX, nil)
  if r != SQLITE_OK: raise newException(SqliteError, "cannot open " & path)

proc close*(db: PDb) = discard sqlite3_close_v2(db)

proc inTransaction*(db: PDb): bool =
  ## a BEGIN is open (not yet committed or undone)
  db != nil and sqlite3_get_autocommit(db) == 0

proc closed(db: PDb) =
  if db == nil: raise newException(SqliteError, "the store was closed after an error it could not undo")

proc exec*(db: PDb, sql: string) =
  db.closed
  var err: cstring
  if sqlite3_exec(db, sql, nil, nil, addr err) != SQLITE_OK:
    raise newException(SqliteError, $err)

type Val* = object
  ## A bound parameter: text, blob or integer.
  case isInt*: bool
  of true: i*: int64
  of false:
    s*: string
    blob*: bool

proc t*(s: string): Val = Val(isInt: false, s: s)
proc b*(s: string): Val = Val(isInt: false, s: s, blob: true)
proc i*(x: int64): Val = Val(isInt: true, i: x)

proc prepare(db: PDb, sql: string, args: openArray[Val]): PStmt =
  db.closed
  db.check sqlite3_prepare_v2(db, sql, cint(sql.len), addr result, nil)
  for k, a in args:
    let idx = cint(k + 1)
    if a.isInt: db.check sqlite3_bind_int64(result, idx, a.i)
    elif a.blob: db.check sqlite3_bind_blob(result, idx, (if a.s.len > 0: unsafeAddr a.s[0] else: nil), cint(a.s.len), SQLITE_TRANSIENT)
    else: db.check sqlite3_bind_text(result, idx, a.s.cstring, cint(a.s.len), SQLITE_TRANSIENT)

proc run*(db: PDb, sql: string, args: varargs[Val]) =
  let s = db.prepare(sql, args)
  let r = sqlite3_step(s)
  discard sqlite3_finalize(s)
  if r != SQLITE_DONE and r != SQLITE_ROW: raise newException(SqliteError, $sqlite3_errmsg(db))

proc colText*(s: PStmt, i: int): string =
  let n = sqlite3_column_bytes(s, cint(i))
  result = newString(n)
  if n > 0: copyMem(addr result[0], sqlite3_column_blob(s, cint(i)), n)

proc colInt*(s: PStmt, i: int): int64 = sqlite3_column_int64(s, cint(i))

iterator rows*(db: PDb, sql: string, args: varargs[Val]): PStmt =
  let s = db.prepare(sql, args)
  try:
    while true:
      let r = sqlite3_step(s)
      if r == SQLITE_ROW: yield s
      elif r == SQLITE_DONE: break
      else: raise newException(SqliteError, $sqlite3_errmsg(db))
  finally:
    discard sqlite3_finalize(s)
