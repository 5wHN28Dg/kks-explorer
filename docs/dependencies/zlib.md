# Dependency record: zlib 1.3.2

Added: 2026-10-01 (Windows, decisions 0029 and 0033)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime
Packages covered: zlib, built from source for the Windows app only. Android (the NDK's `libz`), GNOME (the runtime)
and the server (Ubuntu's `zlib1g`) use the platform's zlib (see the index); MuPDF's own vendored copy is counted in
[mupdf.md](mupdf.md).

## Purpose
Deflate and inflate for the drawing path store (`.kkp`, `docs/PATHSTORE.md`), plant-data bundles and gzip
(`core/src/kks/gz.nim`, `pathstore.nim`, `views.nim`: zlib's stream API, about ten functions; decision 0029).

## Platform alternative checked
Windows has no raw deflate or gzip API in Win32 (decision 0029; the Compression API offers MSZIP, XPRESS and LZMS
in its own framing: [Compression API](https://learn.microsoft.com/en-us/windows/win32/cmpapi/using-the-compression-api)). Every other
target provides zlib as a stable platform library: the NDK ([stable APIs](https://developer.android.com/ndk/guides/stable_apis)),
the GNOME runtime and Ubuntu. The formats are fixed (deflate inside our `.kkp` and gzip bundles), so a platform codec
with another algorithm doesn't help.

## Custom implementation considered
An inflate is about 1,000 lines and a decent deflate more; both parse or produce data that crosses devices, and zlib's
own history shows how subtle the bounds checks are. Owning that to save a 100 KB library is not worth it.

## Transitive dependencies
Count: 0   How counted: zlib has no dependencies; `platform/windows/build-deps.sh` builds `libz.a` from the pinned
tarball (SHA-256, the hash published on zlib.net) with `win32/Makefile.gcc`.

## License
Zlib. Permissive, compatible with AGPL-3.0.

## Maintenance signals
- Recent releases: 1.3.2 on 2026-02-17 (our pin, the latest), 1.3.1 on 2024-01-22, 1.3 on 2023-08-18
  ([zlib.net](https://zlib.net/), [releases](https://github.com/madler/zlib/releases)).
- Security response: fixes ship as releases: CVE-2018-25032 in 1.2.12, CVE-2022-37434 in 1.2.13 (fixed in the
  repository days after the report); 1.3.2 carries the fixes of a security audit ([zlib.net](https://zlib.net/),
  [ChangeLog](https://github.com/madler/zlib/blob/develop/ChangeLog)). No SECURITY.md.
- Active maintainers: Mark Adler wrote 81 of the commits of the last 12 months; 14 other authors contributed one to
  nine each (GitHub contributor statistics, 2026-10-05). In practice one maintainer. Weak.
- Age across major versions: since 1995; 1.x throughout with a stable API.

## Size impact
`libz.a` is 98 KB of code for x86_64 (mingw `size -t`); the part linked into `Walkdown.exe` is smaller (symbol-table
estimate under 0.1 MB). Nothing on the other targets.

## Replacement cost
Low. Three core modules use zlib's stream API (`gz.nim`, `pathstore.nim`, `views.nim`); any implementation of the
same API (zlib-ng in compatibility mode, for example) would do, and the formats don't change.

## Decision
Keep. Windows lacks deflate, the format is fixed, and zlib is the reference implementation on every other platform we
target. The single-maintainer signal is answered by its age, its tiny surface and its presence in every OS: a
replacement (zlib-ng, miniz) would be a drop-in. Revisit if Windows gains a documented deflate API.
