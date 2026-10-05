# Dependency record: mingw-w64 13.0.0 with GCC 13.2 (Ubuntu 26.04 packages)

Added: 2026-10-01 (decision 0033)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: build-time, with runtime parts (the C runtime start-up code, `libstdc++`, `libgcc` and `winpthreads` are linked
statically into `Walkdown.exe` and `uiadrive.exe`)
Packages covered: the x86_64 Windows cross-toolchain from Ubuntu's archive, unpacked without root into
`~/.local/kksdev/mingw`: `binutils-mingw-w64-x86-64` 2.45.90, `gcc-mingw-w64-base`, `gcc-mingw-w64-x86-64-posix`,
`gcc-mingw-w64-x86-64-posix-runtime`, `g++-mingw-w64-x86-64-posix` (13.2.0-6ubuntu1+26.1), `mingw-w64-common`,
`mingw-w64-x86-64-dev` (13.0.0-2ubuntu1). The ARM64 build uses [llvm-mingw](llvm-mingw.md) instead.

## Purpose
Cross-compiles the Windows app (x86_64), its C/C++ libraries (`platform/windows/build-deps.sh`) and the UI Automation
test driver from the Linux machine the project is developed on.

## Platform alternative checked
Windows ships no compiler. Microsoft's toolchain is MSVC (Visual Studio Build Tools) with the Windows SDK, which runs
only on Windows ([Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)). Decision 0033 chose to build on the Linux
machine (no Windows PC; tests in VMs) and keeps MSVC as the fallback if mingw-w64 lacks a header or interface. Nim
targets mingw-w64 directly (`-d:mingw`).

## Custom implementation considered
None: a compiler toolchain is not something to write. The real alternative is MSVC in a Windows VM, which would move
every Windows build (and the signing step's inputs) into the VM.

## Transitive dependencies
Count: 7 packages   How counted: the `.deb` files `apt-get download` fetched (`~/.local/kksdev/mingw-debs/`), listed
above. They are verified by apt against Ubuntu's signed archive at download time; our scripts don't pin them by hash
(they are not in a build script: see the Decision).

## License
mingw-w64 headers and CRT: ZPL-2.1 and public domain; winpthreads: MIT; GCC's `libgcc` and `libstdc++`:
GPL-3.0-or-later WITH GCC-exception-3.1, which allows linking them into a program under any license; binutils and the
compiler: GPL-3.0-or-later (tools, not shipped). Compatible with AGPL-3.0.

## Maintenance signals
- Recent releases: mingw-w64 v14.0.0 on 2026-03-24, v13.0.0 on 2025-06-04, v12 in 2024
  ([tags](https://github.com/mingw-w64/mingw-w64/tags)); GCC 13.2 is Ubuntu's packaged cross-compiler (GCC 13 still
  receives point releases; Ubuntu updates its packages).
- Security response: no SECURITY.md or advisories in mingw-w64; GCC's [SECURITY.txt](https://github.com/gcc-mirror/gcc/blob/master/SECURITY.txt)
  covers its support libraries and private reporting; Ubuntu's security team covers the packages.
- Active maintainers: mingw-w64: 25 commit authors in the last 12 months (pali 274, maiddaisuki 181, lhmouse 137,
  mstorsjo 57, …; GitHub contributor statistics of the mirror, 2026-10-05). GCC: a large multi-company team.
- Age across major versions: mingw-w64 v1.0 in 2011, through major versions v1 to v14
  ([tags](https://github.com/mingw-w64/mingw-w64/tags)); GCC since 1987.

## Size impact
The statically linked C++ runtime is about 0.73 MB of `Walkdown.exe`'s 14.0 MB of code (symbol-table estimate by
name: `std::`, `__gnu_cxx`, `__cxa_*`); the CRT start-up and `winpthreads` add a few tens of KB. No DLLs ship.

## Replacement cost
Medium. The C and Nim code also builds with clang (llvm-mingw does it for ARM64, 0047); moving to MSVC would need the
three diagnostics fixes recorded in 0047 and changes to `config.nims` and `build-deps.sh`. No data or format depends on
the toolchain.

## Decision
Keep. It is the only way to build the Windows app on the project's Linux machine without a second build machine, its
maintainer base is broad, and its runtime licences permit static linking. Weak point: the packages are fetched by hand
and not pinned by hash in a script, so a rebuild on another machine depends on Ubuntu's archive at that time. Revisit
if a header or ABI gap appears (then MSVC in the VM), or move the x86_64 build to llvm-mingw too, which is pinned by
SHA-256 (`platform/windows/fetch-llvm-mingw.sh`).
