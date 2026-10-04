# 0047 Native ARM64 builds for Windows and Linux

Date 2026-10-04 · Scope: the Windows app (MSIX), the GNOME app (Flatpak) · Status: **accepted by the user**
("set things up so that with the next release there will be native arm64 builds for both linux and windows")

**Question:** how to ship native ARM64 builds of the desktop apps from this x86_64 machine, and test them without
ARM64 hardware?

## Findings

| | Fact | Source |
|---|---|---|
| Windows on ARM | Windows 11 on ARM runs x64 apps through emulation (Prism), so the x64 MSIX already ran there, only not natively | [D] https://learn.microsoft.com/windows/arm/apps-on-arm-x86-emulation |
| MSIX | one package per architecture: `ProcessorArchitecture="arm64"` in the manifest | [D] https://learn.microsoft.com/uwp/schemas/appxpackage/uapmanifestschema/element-identity |
| Toolchain | mingw-w64's gcc has no ARM64 Windows target; **llvm-mingw** (clang + mingw-w64 headers, `aarch64-w64-mingw32`) has, and runs on Linux x86_64. Release 20260922 (clang 23.1.2), its SHA-256 published by GitHub for the asset | [D] https://github.com/mstorsjo/llvm-mingw/releases · [V] builds here |
| Maintenance test | llvm-mingw: recent releases ✓, license (Apache 2.0 with LLVM exception, mingw-w64 ZPL/public domain) ✓, survives major versions (LLVM 13 → 23) ✓, security response: LLVM's and mingw-w64's own; **one main maintainer** (1,360 commits; the next has 14): fails "more than one active maintainer". Chosen anyway: no other toolchain builds ARM64 Windows from Linux; the code it builds is the same C/Nim we build with gcc, and if it stopped, an ARM64 build could move to MSVC/clang on a Windows ARM64 machine | [D] GitHub contributors API |
| clang vs gcc 13 | clang makes three diagnostics errors that gcc 13 warns about (Nim's stdcall procs for WNDPROC, ints for MAKEINTRESOURCE, uint32 for DWORD pointers: the same size and ABI) → `-Wno-error=` for those three; `<stddef.h>` for `offsetof`; `_WIN32_WINNT=0x0A00` stated | [V] the build |
| Linux ARM64 | a Flatpak for aarch64 needs an aarch64 runtime and either an ARM64 machine or qemu registered with binfmt_misc (root, which this machine's user has not) | [D] https://docs.flatpak.org/en/latest/flatpak-builder.html |
| Runners | GitHub-hosted `ubuntu-24.04-arm` and `windows-11-arm` are free for public repositories (this one is public) | [D] https://docs.github.com/en/actions/reference/runners/github-hosted-runners |
| Flatpak in CI | the Flatpak project's `flatpak/flatpak-github-actions` (v6.8, 2026-08-30) with Flathub's `gnome-50` container builds a bundle for an `arch` | [D] https://github.com/flatpak/flatpak-github-actions |

## Choice

- **Windows ARM64:** cross-built here with llvm-mingw (`KKS_WIN_ARCH=aarch64` for `platform/windows/build-deps.sh`,
  `apps/windows/build.sh`, `packaging/windows/make-msix.sh`); `Walkdown-arm64.msix` signed here like the x64 one (the
  key never leaves this machine). x86_64 stays on mingw-w64's gcc, unchanged.
- **Linux ARM64:** `walkdown-aarch64.flatpak` from the `ARM64` workflow (`flatpak-arm64` job) on an ARM64 runner;
  the release takes that artifact (Flatpak bundles are not signed; the signed release manifest lists its hash).
- **Tests on the target:** the workflow runs the Windows platform tests and the app's start on `windows-11-arm`, and
  the Nim core's tests on `ubuntu-24.04-arm`. The full e2e suites stay x86_64 (VMs, emulator) for now.
- **Release:** `tools/release.py` lists `Walkdown-arm64.msix` and `walkdown-aarch64.flatpak` (Releasing on the wiki).

**When to revisit:** if llvm-mingw stops releasing; if an ARM64 Windows or Linux device joins the plant (then run the
full e2e on it); if GitHub's free ARM64 runners end.
