## Files only this user may read (issues #28, #29, #69): written to a new 0600 file next to the target, then renamed
## over it. Never readable under the process umask meanwhile (a chmod after writeFile was), never through a symlink
## planted at the target (rename replaces the link itself), and a failed write leaves the old file as it was.

import std/[os, posix]

var O_NOFOLLOW {.importc, header: "<fcntl.h>".}: cint
proc c_rename(a, b: cstring): cint {.importc: "rename", header: "<stdio.h>".}

proc writePrivate*(path, data: string) =
  let tmp = path & ".tmp-" & $getpid()
  let fd = posix.open(tmp.cstring, O_WRONLY or O_CREAT or O_EXCL or O_NOFOLLOW or O_CLOEXEC, Mode(0o600))
  if fd < 0: raiseOSError(osLastError(), tmp)
  var ok = false
  try:
    var off = 0
    while off < data.len:
      let n = posix.write(fd, unsafeAddr data[off], data.len - off)
      if n < 0:
        if errno == EINTR: continue
        raiseOSError(osLastError(), tmp)
      off += n
    if fsync(fd) != 0: raiseOSError(osLastError(), tmp)
    ok = true
  finally:
    discard posix.close(fd)
    if not ok: discard posix.unlink(tmp.cstring)
  if c_rename(tmp.cstring, path.cstring) != 0:
    let e = osLastError()
    discard posix.unlink(tmp.cstring)
    raiseOSError(e, path)
