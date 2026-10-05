# Dependency record: llvm-mingw 20260922

Added: 2026-10-04 (decision 0047)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: build-time, with runtime parts (the C runtime start-up code, `libc++`, `libc++abi`, `libunwind` and
`winpthreads` are linked statically into the ARM64 `Walkdown.exe`)
Packages covered: the release archive `llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz` (clang/LLVM 23.1.2 and
lld, mingw-w64 headers and CRT, LLVM's C++ runtime, compiler-rt)

## Purpose
Cross-compiles the Windows on ARM64 app and its libraries from the x86_64 Linux machine
(`KKS_WIN_ARCH=aarch64` in `platform/windows/build-deps.sh`, `apps/windows/build.sh`,
`packaging/windows/make-msix.sh`; the `windows-arm64-build` CI job).

## Platform alternative checked
Microsoft's toolchain for ARM64 Windows is MSVC on Windows (x64 or ARM64 hosts); there is no Microsoft compiler for
Linux. Windows 11 on ARM also runs the x64 build through emulation
([Prism](https://learn.microsoft.com/windows/arm/apps-on-arm-x86-emulation)), which is the fallback and was the state
before 0047. mingw-w64's GCC has no ARM64 Windows target (0047).

## Custom implementation considered
None (a toolchain). The alternatives are MSVC on a Windows ARM64 machine, or shipping only the emulated x64 build.

## Transitive dependencies
Count: 5 components in one archive   How counted: what the release archive bundles and the build uses: LLVM/clang and
lld, the mingw-w64 headers and CRT, `libc++`/`libc++abi`, `libunwind`, compiler-rt. Pinned by the SHA-256 GitHub
publishes for the asset (`platform/windows/fetch-llvm-mingw.sh`).

## License
llvm-mingw's own scripts: ISC; the toolchain: Apache-2.0 WITH LLVM-exception (LLVM, libc++, libunwind, compiler-rt),
mingw-w64: ZPL-2.1 and public domain ([LICENSE.txt](https://github.com/mstorsjo/llvm-mingw/blob/master/LICENSE.txt)).
The runtime exceptions allow static linking under any license; compatible with AGPL-3.0.

## Maintenance signals
- Recent releases: 20260922 (our pin, the latest), 20260908, 20260826, 20260812: about every two weeks, tracking LLVM
  releases ([releases](https://github.com/mstorsjo/llvm-mingw/releases)).
- Security response: none of its own (no SECURITY.md, no advisories); security fixes come from LLVM's
  [security group](https://llvm.org/docs/Security.html) and mingw-w64 upstream and arrive with the next release.
- Active maintainers: one. mstorsjo wrote 111 of the 114 commits of the last 12 months (GitHub contributor statistics,
  2026-10-05); he is also an LLVM and mingw-w64 maintainer. Weak.
- Age across major versions: since 2017; it has followed LLVM from 13 to 23 (0047).

## Size impact
The ARM64 `Walkdown.exe` built for this record (2026-10-05, `KKS_WIN_ARCH=aarch64 apps/windows/build.sh`) is
11.1 MB. Its COFF symbol table carries no sizes, so the C++ runtime's share was not separated; the upper bound is the
whole of llvm-mingw's ARM64 `libc++.a` (1.6 MB of code, `llvm-size -t`), of which the linker keeps only what is used
(the x86_64 build keeps 0.73 MB of `libstdc++`). Nothing ships on other targets.

## Replacement cost
Low to medium. The same C/Nim/C++ sources build with gcc (x86_64); the clang-specific `-Wno-error=` flags and
`config.nims` branch are small (0047). Replacing it means MSVC on Windows for ARM64 or dropping the native ARM64 build.

## Decision
Keep. It is the only toolchain that builds ARM64 Windows from Linux, it is pinned by hash, and it tracks LLVM closely.
The single-maintainer signal is the real risk; it is answered by the fallbacks: the x64 build runs on ARM64 Windows
through emulation, and the code also builds with MSVC/clang on Windows. Revisit if llvm-mingw stops releasing (0047).
