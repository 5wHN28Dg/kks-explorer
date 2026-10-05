# Dependency record: SQLite 3.53.4 (amalgamation)

Added: 2026-10-01 (Android core, decision 0032; Windows, decision 0033)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime
Packages covered: the SQLite amalgamation (`sqlite3.c`), compiled into the Android core (`libkks.so`) and the Windows
app. GNOME and the server link the platform's SQLite instead (see the index).

## Purpose
The device store: the signed log, sealed rows, photos waiting to sync (`platform/linux/src/kksl/dbstore.nim`, shared
by every native target; decision 0020).

## Platform alternative checked
- **Android:** SQLite exists only behind the Java API `android.database.sqlite`; the NDK sysroot has no `sqlite3.h`
  and no `libsqlite` [V, decision 0032; [NDK stable APIs](https://developer.android.com/ndk/guides/stable_apis)].
  Using the Java API would split the store into a Kotlin implementation next to the Nim one, or cross JNI for every
  query.
- **Windows:** ships `winsqlite3.dll`, but Microsoft doesn't document its version or ABI for desktop apps (0033).
- **GNOME and the server:** the platform's SQLite (the GNOME runtime; Ubuntu's `libsqlite3-0`). Used there.

## Custom implementation considered
Our own storage (append-only files plus indexes) was not seriously considered: transactions, crash safety and
`secure_delete` for the wipe (0020, the removal flow) are exactly what SQLite provides and what would be hardest to get
right ourselves.

## Transitive dependencies
Count: 0   How counted: the amalgamation is one C file with no external libraries
(`android/nim/fetch_sqlite.sh` pins it by SHA3-256, the hash sqlite.org publishes; `android/nim/build.sh` and the Windows
build compile it with `-d:kksBundledSqlite`).

## License
Public domain ([sqlite.org/copyright](https://sqlite.org/copyright.html); SPDX `blessing`). Compatible with anything.

## Maintenance signals
- Recent releases: 3.53.4 on 2026-07-24 (our pin, the latest); 3.53.3 on 2026-06-26, 3.53.2 on 2026-06-03, 3.53.1 on
  2026-05-05, 3.53.0 on 2026-04-09 ([chronology](https://sqlite.org/chronology.html)).
- Security response: [sqlite.org/cves.html](https://sqlite.org/cves.html) lists every CVE with the fixing version;
  the developers say they fix reported bugs "usually within a few hours" and ship patch releases when applications
  are affected (latest: CVE-2026-11822/11824 in FTS5, fixed in 3.53.2). Most CVEs need an attacker who can run
  arbitrary SQL, which our code never accepts (fixed, parameterized statements).
- Active maintainers: three core developers wrote 2,030 of the 2,037 commits of the last 12 months (drh 1,279,
  stephan 396, dan 355; the [GitHub mirror](https://github.com/sqlite/sqlite), 2026-10-05). The team no longer lists
  names publicly ([crew](https://sqlite.org/crew.html)).
- Age across major versions: since 2000; SQLite 3 since 2004 with a file format and C API kept compatible ever since,
  supported by its developers to 2050 ([long-term support](https://sqlite.org/lts.html)).

## Size impact
The amalgamation's object is 1.23 MB of code and constant data on Android arm64 (`llvm-size` of `sqlite3.c.o`) inside
the 2.60 MB `libkks.so` of the release APK, and 1.26 MB on Windows x86_64 (mingw `size` of the object) inside
`Walkdown.exe`.

## Replacement cost
Medium. Two modules talk to it (`kksl/dbstore.nim` and the bindings `kksl/sqlite.nim`, 233 lines together); the database file is local to each
device (the log syncs as entries, not as a file), so a replacement needs no migration of shared data. On Android the
alternative would be the Java API through JNI.

## Decision
Keep. The platforms that provide SQLite (GNOME, the server host) are used; on Android and Windows bundling the
amalgamation keeps one store implementation for every target. All four maintenance signals are strong, and the
library has the most conservative compatibility record of anything we use. Revisit if Android adds SQLite to the NDK
or Windows documents `winsqlite3` for desktop apps.
