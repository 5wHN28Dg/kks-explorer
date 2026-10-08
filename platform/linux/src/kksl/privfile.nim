## Files only this user may read: created 0600 from the start (a chmod after writeFile left them readable under the
## process umask meanwhile), and set to 0600 if they existed with another mode (issues #28, #29, #69).

import std/[os, posix]

proc writePrivate*(path, data: string) =
  let fd = posix.open(path.cstring, O_WRONLY or O_CREAT or O_TRUNC or O_CLOEXEC, Mode(0o600))
  if fd < 0: raiseOSError(osLastError(), path)
  try:
    if fchmod(fd, Mode(0o600)) != 0: raiseOSError(osLastError(), path)
    var off = 0
    while off < data.len:
      let n = posix.write(fd, unsafeAddr data[off], data.len - off)
      if n < 0:
        if errno == EINTR: continue
        raiseOSError(osLastError(), path)
      off += n
  finally:
    discard posix.close(fd)
