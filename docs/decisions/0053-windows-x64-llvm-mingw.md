# 0053 The x86_64 Windows build moves to llvm-mingw

Date 2026-10-09 · Scope: every x86_64 Windows binary (Walkdown.exe, uiadrive.exe, the Windows test programs, the
libraries from `platform/windows/build-deps.sh`), CI's `windows-build` · Status: **decided by the user** (2026-10-09,
issue #4) · Changes 0033's compiler choice; extends 0047

**Question:** should the x86_64 Windows build keep mingw-w64's GCC from Ubuntu's packages, or use llvm-mingw, which the
ARM64 build already uses (0047)?

**Why it came up:** #4 asks that every third-party source and tool the build fetches be listed for vulnerability
scanning. Listing the mingw-w64, GCC and binutils packages from Ubuntu brought advisories that Ubuntu never fixed in
those packages (they are the cross toolchain, maintained less closely than the native one). One toolchain for both
architectures, pinned by a hash of an upstream release, removes those packages instead.

## Findings

| | Fact | Source |
|---|---|---|
| What is pinned | llvm-mingw 20260922 (clang 23.1.2), `ucrt-ubuntu-22.04-x86_64`, by the SHA-256 GitHub publishes for the asset, already fetched by `platform/windows/fetch-llvm-mingw.sh` and listed in `pinned-sources.cdx.json`. The same archive holds the `x86_64-w64-mingw32` target: no new download | [V] the archive here; 0047 |
| What changes in the exe | C++ runtime: LLVM's **libc++/libc++abi** instead of GCC's libstdc++; **libunwind** and **compiler-rt** builtins instead of libgcc/libgcc_eh; linker **lld** instead of GNU ld; resources by llvm-windres; C runtime **UCRT** (`ucrtbase.dll` / `api-ms-win-crt-*`) instead of the old `msvcrt.dll`. Everything is linked statically (`-static`): the exe imports only Windows' own DLLs | [V] `llvm-objdump -p` on the new exe (below) |
| UCRT on Windows 10 | the Universal CRT is part of Windows 10 and later (an OS component, serviced by Windows Update), so nothing ships with the app | [D] https://learn.microsoft.com/cpp/windows/universal-crt-deployment |
| Compiler differences | clang makes three diagnostics errors that GCC 13 warns about; the ARM64 build already turns them back into warnings (0047): Nim's stdcall procs for WNDPROC, ints for MAKEINTRESOURCE, uint32 for DWORD pointers, the same size and ABI. The same flags now apply to x86_64; `_WIN32_WINNT=0x0A00` stated | [V] the build |
| Licenses of what is linked in | libc++, libc++abi, libunwind, compiler-rt: Apache-2.0 WITH LLVM-exception (the exception lets binaries skip Apache's attribution terms); mingw-w64 CRT and headers: ZPL-2.1 and public domain; winpthreads (only if a C++ thread primitive pulls it in): MIT. GCC's were GPL-3.0-or-later WITH GCC-exception-3.1. All permissive or with a runtime exception: compatible with the AGPL-3.0. None of them is a scanned package (`pkg:generic` in the BOM); `license-allowlist.txt` covers what osv-scanner reports and needs no change | [D] the archive's LICENSE.TXT; https://llvm.org/LICENSE.txt; https://github.com/mingw-w64/mingw-w64/blob/master/COPYING |
| Maintenance | as in 0047: regular releases, LLVM's and mingw-w64's own security response, one main maintainer (the one finding against it). Moving x86_64 adds no new dependency, it removes seven Ubuntu packages | 0047 |
| Size and speed | see "Measured" below | [V] |

## Choice

- **Both Windows architectures build with llvm-mingw** (`--cc:clang`, `x86_64-w64-mingw32-clang`); one toolchain to
  pin, fetch and list. `platform/windows/fetch-mingw.sh` and the seven Ubuntu packages leave the repository, the BOM
  and CI (CI no longer installs `g++-mingw-w64-x86-64-posix` / `binutils-mingw-w64-x86-64` with apt).
- The x86_64 libraries go to `~/.local/kksdev/winx64` (was `win64`), so a library built by GCC against libstdc++ can
  never be linked with libc++ by accident.
- MSVC stays the fallback named in 0033 if clang or its headers ever lack something.

## Measured

(filled in below after the builds and the VM runs)

**When to revisit:** if llvm-mingw stops releasing or falls behind LLVM's security fixes; if a Windows ABI or header
gap appears that GCC or MSVC would not have; if the exe's size or speed regresses past the rules in
`docs/m6/MEASUREMENTS.md`.
