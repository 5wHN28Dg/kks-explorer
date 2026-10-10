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
| What changes in the exe | C++ runtime: LLVM's **libc++/libc++abi** instead of GCC's libstdc++; **libunwind** and **compiler-rt** builtins instead of libgcc/libgcc_eh; linker **lld** instead of GNU ld; resources by llvm-windres; C runtime **UCRT** (`ucrtbase.dll` / `api-ms-win-crt-*`) instead of the old `msvcrt.dll`. Everything is linked statically (`-static`): the exe imports only Windows' own DLLs | [V] `llvm-objdump -p` on the new exe |
| UCRT on Windows 10 | the Universal CRT is part of Windows 10 and later (an OS component, serviced by Windows Update), so nothing ships with the app | [D] https://learn.microsoft.com/cpp/windows/universal-crt-deployment |
| Compiler differences | clang makes three diagnostics errors that GCC 13 warns about; the ARM64 build already turns them back into warnings (0047): Nim's stdcall procs for WNDPROC, ints for MAKEINTRESOURCE, uint32 for DWORD pointers, the same size and ABI. The same flags now apply to x86_64; `_WIN32_WINNT=0x0A00` stated for the Nim code, uiadrive and SQLite (the libraries keep llvm-mingw's default 0x0601; none of their sources reads it) | [V] the build |
| Licenses of what is linked in | libc++, libc++abi, libunwind, compiler-rt: Apache-2.0 WITH LLVM-exception (the exception lets binaries skip Apache's attribution terms); mingw-w64 CRT and headers: ZPL-2.1 and public domain; winpthreads (MIT) is not linked in (`llvm-nm` finds no pthread symbol in the exe). GCC's were GPL-3.0-or-later WITH GCC-exception-3.1. All permissive or with a runtime exception: compatible with the AGPL-3.0. None of them is a scanned package (`pkg:generic` in the BOM); `license-allowlist.txt` covers what osv-scanner reports and needs no change | [D] the archive's LICENSE.TXT; https://llvm.org/LICENSE.txt; https://github.com/mingw-w64/mingw-w64/blob/master/COPYING |
| Maintenance | as in 0047: regular releases, LLVM's and mingw-w64's own security response, one main maintainer (the one finding against it). Moving x86_64 adds no new dependency, it removes seven Ubuntu packages | 0047 |
| Size and speed | see "Measured" below | [V] the builds here |

## Choice

- **Both Windows architectures build with llvm-mingw** (`--cc:clang`, `x86_64-w64-mingw32-clang`); one toolchain to
  pin, fetch and list. `platform/windows/fetch-mingw.sh` and the seven Ubuntu packages leave the repository, the BOM
  and CI (CI no longer installs `g++-mingw-w64-x86-64-posix` / `binutils-mingw-w64-x86-64` with apt).
- The x86_64 libraries go to `~/.local/kksdev/winx64` (was `win64`), so a library built by GCC against libstdc++ can
  never be linked with libc++ by accident.
- MSVC stays the fallback named in 0033 if clang or its headers ever lack something.

## Measured

Built here 2026-10-09 from the same commit, release mode, as `apps/windows/build.sh` makes them:

| | GCC 13 (mingw-w64, Ubuntu) | llvm-mingw 20260922 (clang 23) |
|---|---|---|
| Walkdown.exe as built | 19,799,690 bytes (18.9 MiB) | 15,738,880 bytes (15.0 MiB), −20.5 % |
| Walkdown.exe stripped | 15,389,184 bytes | 13,486,080 bytes, −12.4 % |
| uiadrive.exe | 2,702,548 bytes | 1,480,192 bytes |
| C runtime the exe imports | `msvcrt.dll` | `api-ms-win-crt-*` (UCRT); no libc++, libunwind or winpthread DLL |
| CI `windows-test` (windows-2022 runner) | passes | passes (core, platform and app tests; the app starts to its setup screen) |

- The libraries (zlib, libjxl, zxing-cpp) build for x86_64 with no source change; one run of `build-deps.sh` with
  4 jobs takes about 1.5 minutes here.

**Speed** (2026-10-10, the Windows 11 26H2 VM of `docs/m6/MEASUREMENTS.md`, startup and memory also in the Windows 10
22H2 VM; the GCC and llvm-mingw builds of one commit; test programs: median of 3 runs, timed inside the VM):

| | GCC 13 | llvm-mingw | |
|---|---|---|---|
| test_api / test_sync / test_replay (core: JSON, log, replay, sync sessions) | 663 / 647 / 638 ms | 590 / 626 / 528 ms | −11 / −3 / −17 % |
| test_rudp / test_model | 215 / 67 ms | 128 / 35 ms | −40 / −48 % |
| test_pathstore / test_extras | 1,144 / 431 ms | 1,211 / 417 ms | +6 / −3 % |
| test_dbstore (SQLite, DPAPI) | 369 ms | 320 ms | −13 % |
| test_dark (libjxl decode, Direct2D) | 2,093 ms | 438 ms | −79 % |
| test_tiles (12 tiles of 2048 px on WARP, Direct2D's software renderer) | 138.1 s | 137.1 s | equal (Direct2D's own code) |
| test_net, test_internet (sync over TCP and the relay) | 18.1 s, 38.6 s | 13.9 s, 38.9 s | not comparable: their time is waits and timeouts (test_net's 3 runs: 8.0–18.1 s and 6.8–14.0 s) |
| Start → first overview drawn (sample sheet, 5 starts, median), Windows 11 / 10 | 105 / 93 ms | 102 / 93 ms | equal |
| Private bytes 15 s after start, Windows 11 / 10 | 20.4 / 19.4 MB | 20.8 / 19.6 MB | equal |
| Join (enrolment + the first full sync of the sample sheet) | 1–2 s | 1–2 s | equal (the driver logs whole seconds) |

libjxl (test_dark) and test_rudp/test_model gain the most; test_pathstore is the one slower program (+6 %, three runs
each, spread 1,140–1,210 vs 1,211–1,265 ms). Rough figures: two VMs, small test data, no real sheet.

**Checked in the VMs** (2026-10-10, the llvm-mingw build): on Windows 10 22H2 and 11 26H2 every core, platform and app test
program passes, and so does the whole Windows e2e (19 tests). On Windows 10 the MSIX (`make-msix.sh`, a test
certificate) builds (11.6 MB), installs, and passes the e2e as the installed package.

**When to revisit:** if llvm-mingw stops releasing or falls behind LLVM's security fixes; if a Windows ABI or header
gap appears that GCC or MSVC would not have; if the exe's size or speed regresses past the rules in
`docs/m6/MEASUREMENTS.md`.
