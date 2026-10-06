# Dependency record: Nim 2.2.12 (compiler and standard library)

Added: 2026-09-30 (decision 0027, the user's choice; core 0029)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: build-time and runtime (the compiler runs at build time; its runtime and standard library are compiled into every
native binary: the Android `libkks.so`, the GNOME and Windows apps, the server and the importer)
Packages covered: the Nim compiler and its standard library. No Nimble packages are used (every import is `std/` or
the project's own module; checked 2026-10-05).

## Purpose
The language of the shared sans-I/O core, the desktop apps, the server and the importer (25,500 lines of Nim in the
repository).

## Platform alternative checked
Each platform's own languages: C/C++ with MSVC or the Windows SDK on Windows, C (or Vala) with GTK on GNOME, Kotlin or
Java (plus C/C++ through the NDK) on Android. None is shared by all four targets except C/C++, and writing the core,
protocol and server in C/C++ means owning memory safety in parsers of untrusted input (the log, JSON, sync messages,
images). Decision 0027 compares the routes (Rust, C++, Kotlin Multiplatform, Nim); the user chose Nim for fluency and
for one core everywhere. Nim compiles to C, so each platform's own C toolchain (the NDK's clang, Ubuntu's gcc,
mingw-w64 or llvm-mingw for Windows) builds the output; it brings no runtime engine of its own beyond a small
garbage-collector/ORC runtime compiled into the binary.

## Custom implementation considered
Not applicable to a language: the alternative is the C/C++ route above, with its memory-safety cost. Within Nim, the
project already writes its own code where the standard library falls short (the strict JSON reader, decision 0029)
and uses the standard library only for async I/O, collections, strings and unit tests.

## Transitive dependencies
Count: 0   How counted: no Nimble package is imported (`grep` of every `import` in tracked `.nim` files: only `std/` and
the project's modules). The compiler is bootstrapped from the C sources inside its own tarball (`build.sh`, then
`koch boot`) with the host C compiler. Pinned by SHA-256 of `nim-2.2.12.tar.xz` in the Flatpak manifest and in
`.github/workflows/arm64.yml`; the maintainer's machine uses choosenim's 2.2.12 (`~/.nimble/bin/nim`), which is not
checked against that hash.

## License
MIT (the compiler and the standard library). Compatible with AGPL-3.0.

## Maintenance signals
- Recent releases: 2.2.12 on 2026-09-07, 2.2.10 on 2026-04-23, 2.2.8 on 2026-02-22, 2.2.6 on 2025-10-30: a patch
  release every two to four months on the 2.2 line ([tags](https://github.com/nim-lang/Nim/tags)).
- Security response: advisories are published in the [nim-lang/security](https://github.com/nim-lang/security/security/advisories)
  repository and fixed in point releases of the supported lines (CVE-2021-21372/21373/21374 in Nimble and
  `httpclient`, fixed in 1.2.10 and 1.4.4; CVE-2021-29495, `httpclient` certificate checks, fixed in 1.4.2;
  GHSA-ggrq-h43f-3w7m, the RST sandbox, 2022). No SECURITY.md in the main repository.
- Active maintainers: 52 commit authors in the last 12 months; ringabout (171) and Araq (134, the language's author)
  lead, plus a backport bot (GitHub contributor statistics, 2026-10-05). Effectively two core maintainers.
- Age across major versions: since 2008; 1.0 in 2019, 2.0 in 2023 (ORC memory management by default); our code was
  written for 2.x.

## Size impact
The runtime and standard library compiled into each binary, estimated from symbol names (`nm --size-sort -S`, symbols
of `system`, `std/*`, `pure/*`): about 0.3 MB of the server's 2.0 MB of symbols, about 0.55 MB of the Windows app's
13.9 MB. The rest of the "Nim" code is the project's own.

## Replacement cost
Very high. Every native component except the Android UI (Kotlin, 5,600 lines) is Nim; replacing the language means
rewriting the core, the desktop apps, the server and the importer. Data formats don't depend on it (they are specified
in `docs/PROTOCOL-v2.md`, `docs/PATHSTORE.md`, `docs/COURSES.md`, with independent Python references in `ref/`).

## Decision
Keep (the user's choice in 0027, revisitable). Nim gives one memory-safe core on four platforms through their own C
toolchains, with no package ecosystem pulled in. The weak signals are the small core team (two maintainers carry
most of the work) and the absence of a SECURITY.md in the main repository; the separate security repository and point
releases answer the second. Follow-up for the owner: local builds should use the same SHA-256-checked 2.2.12 tarball
as CI and the Flatpak (choosenim's download is not checked against it).
