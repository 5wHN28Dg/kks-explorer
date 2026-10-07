# 0033 Windows: toolchain, platform layer and test machines

Date 2026-10-01 · Scope: phase 7 (R1–R20 on Windows 10 22H2 and 11; N1, N1a, N3) · Status: **decided by Claude under
the user's standing instruction to continue**. The user chose the VMs (Windows 10 and 11 under virt-manager/QEMU,
2026-10-01) and an unactivated Windows 10.

**Question:**
- How do we build the Windows app from this Linux machine, and test it without a Windows PC?
- Which Windows APIs fill the platform layer? The core, the protocol and the UI toolkit are settled in 0017, 0020,
  0021, 0022, 0027 and 0029. This record covers what they left open.

## Findings

[V] = run here 2026-10-01; [D] = Microsoft documentation (links below); [V-VM] = to be run in the VMs.

| Need | What Windows provides | Gap / choice |
|---|---|---|
| Compiler | No compiler ships with Windows. Options: MSVC Build Tools (Windows-only), or **mingw-w64 GCC cross-compiling from Linux**. Ubuntu 26.04 packages mingw-w64 13.0.0 headers + GCC 13.2 [V]. Nim targets it with `-d:mingw` [D: Nim docs]. A test program using bcrypt, ncrypt, dnsapi, d2d1 and dwrite headers built and ran under wine [V]. | **mingw-w64 cross-compile**, unpacked without sudo into `~/.local/kksdev/mingw`. Maintenance: v14.0.0 2026-03-27, v13 2025-06, v12 2024-05; 6 active authors in the last 12 months (Pali Rohár 310 commits, Kirill Makurin 196, LIU Hao 112, Martin Storsjö 67, …) [V: GitHub API]. Headers are public domain or permissive; GCC's runtime exception allows any license. MSVC stays the fallback if a header or ABI gap appears. |
| Test machines | No Windows PC here | **QEMU/KVM VMs** through libvirt (virt-install; swtpm and OVMF Secure Boot firmware with Microsoft's keys are installed [V]). Windows 11 Enterprise **evaluation** ISO, 26H2 build 26300, 90 days, no key needed [D]. Microsoft no longer offers a Windows 10 evaluation (the page redirects to the end-of-support post) [D]. **Windows 10 22H2** comes from Microsoft's consumer download (SHA-256 A6F470CA…852E published on that page) and runs **unactivated** (the user's choice; the user's suggestion of third-party activation was declined). Unattended install + OpenSSH Server (a Windows optional feature) for running tests. VMs suit functional tests, installed size and UI Automation, not GPU timings (WARP renders) or company policy (see test-devices memory / MEASUREMENTS.md). |
| Crypto primitives | CNG `bcrypt`: ECDSA/ECDH P-256, AES-GCM, SHA-256, HMAC, PBKDF2, RNG [D] (0017, 0029) | `provider_cng.nim`, the third implementation of the core's Provider interface |
| Device key | NCrypt key storage providers: the Software KSP does ECDSA P-256, non-exportable, per user [D]. The Platform Crypto Provider (TPM) is documented, but its P-256 support isn't stated on that page [D] | Software KSP first. Try the TPM provider in the Windows 11 VM (swtpm) [V-VM] and prefer it where it works. |
| Storage key (0020) | DPAPI `CryptProtectData`, per user [D] | the 32-byte storage key, sealed by DPAPI in a file next to the database |
| Database | Windows ships `winsqlite3.dll`, but its version and ABI are undocumented for desktop apps | **bundle the SQLite amalgamation** (as on Android, 0032): one code path, `platform/linux/dbstore.nim` unchanged |
| TLS (0017) | Schannel via SSPI: **TLS 1.2 only on Windows 10 22H2; TLS 1.3 from Windows 11**. Microsoft: enabling 1.3 earlier "is not a safe system configuration" [D]. `SCH_CREDENTIALS` with ALPN (`TLS_PARAMETERS`) from Windows 10 1809 [D]; `SCH_CRED_MANUAL_CRED_VALIDATION` lets us check the peer ID ourselves [D] | Schannel, with the certificate made from the NCrypt key (`CertCreateSelfSignCertificate`). TLS 1.2 is allowed only where 1.3 is missing (PROTOCOL-v2 already says so). |
| Discovery | `DnsServiceRegister` / `DnsServiceBrowse` / `DnsServiceResolve`, Windows 10, desktop apps [D] | used directly (0021) |
| Sockets / event loop | Nim's asyncdispatch runs on IOCP [D: Nim docs] | the core's sync session is sans-I/O; the Linux `net.nim` loop is reused where it doesn't touch GnuTLS |
| UI, accessibility | Win32 + common controls v6, Direct2D/DirectWrite (0014, 0027). Standard controls expose UI Automation; custom-drawn views need a UIA provider (COM) [D] | the drawing view gets an `IRawElementProviderFragment` provider (tags as fragments), as on Android and GNOME |
| UI tests | UI Automation client is part of Windows (.NET Framework 4.8 `UIAutomationClient`, usable from PowerShell) [D] | e2e tests drive the app through UIA from PowerShell over SSH, the counterpart of AT-SPI (GNOME) and uiautomator (Android) |
| JPEG XL, QR | none on Windows 10 (0018, 0019) | libjxl v0.12.0 and zxing-cpp v3.1.1 cross-built with CMake + mingw, from the same pinned, SHA-256-checked sources as Android |

## Choice

**Order of work:**
1. The Nim core's tests (CNG provider) cross-built and passing in both VMs.
2. The platform layer: keys, store, Schannel, DNS-SD.
3. The app's UI.
4. Packaging (MSIX, 0022).

**Builds:** everything is built here with mingw-w64. GitHub's Windows runners (CI) come later and need the user's OK to
push.

**When to revisit:**
- if mingw-w64 lacks a needed header or interface (then MSVC Build Tools in the VM);
- if Windows 10 support is dropped (then TLS 1.3 everywhere, 0017);
- if the TPM provider proves usable for P-256 on real hardware.

Sources: https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise ·
https://www.microsoft.com/en-us/software-download/windows10ISO ·
https://learn.microsoft.com/en-us/windows/win32/secauthn/protocols-in-tls-ssl--schannel-ssp- ·
https://learn.microsoft.com/en-us/windows/win32/api/schannel/ns-schannel-sch_credentials ·
https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse ·
https://learn.microsoft.com/en-us/windows/win32/seccertenroll/cng-key-storage-providers ·
https://github.com/mingw-w64/mingw-w64/tags

## Findings 2026-10-01 (phase 7, verified in both VMs)

- **Core and platform layer, run on the targets:**
  - all core tests with the CNG provider, store, Schannel and DNS-SD tests pass on Windows 10 22H2 (19045) and
    11 26H2 (26300);
  - Schannel negotiates TLS 1.2 on Windows 10 and TLS 1.3 on Windows 11 [V], as predicted;
  - the Linux GnuTLS side accepts both.
- **CNG doesn't promise to validate EC points.** Wine's bcrypt accepted an off-curve point. Since the import check isn't
  documented, the core now checks the curve itself (`crypto.p256OnCurve`, cross-checked against GnuTLS on 400
  points) before verifying or doing ECDH.
- **TPM:** libvirt gave both VMs an emulated TPM (swtpm, "IBM"). The Platform Crypto Provider made and used a P-256 key
  there [V on swtpm, not on hardware]. The device key stays in the software key store until a hardware test.
- **Firewall:**
  - The first listen of an unpackaged exe raises Windows Defender Firewall's prompt (public networks preselected).
  - The tests use a program rule and a Private network profile.
  - For users this goes into packaging: an MSIX can declare the rule (0022).
- **Win32 lessons:**
  - Run click/select handlers after the control's notification returns (a handler that destroys the page crashed
    COMCTL32: an access violation).
  - Nim 2's `newWideCString` is an object, so it can't be cast to LPARAM (a crash in the list box). A WideCString in a
    struct field must outlive the call.
  - A UI Automation provider needs `ProviderOptions_UseComThreading`: otherwise UIA calls it on worker threads, where
    Nim memory can't be allocated (a crash at start on Windows 11).
  - A Nim exception must not unwind through a window procedure: guards log it to `crash.log`.
  - A lambda that only calls a nested closure proc (`proc () = open()`) and goes through a generic (`ui.toSpec`) must
    be written `{.closure.}`: Nim 2.2.12 typed it nimcall there and copied its environment without counting the
    reference, so closing the window freed it once too often (heap corruption, crashes later anywhere; 2026-10-07).
  - Common Controls v6, per-monitor DPI and UTF-8 come from a manifest resource; the resource type must be numeric
    (24), or the manifest is silently ignored.
- **Test harness (uiadrive, scheduled tasks), learned the hard way:**
  - The native UI Automation core sees Win32 buttons, edits and lists. The managed .NET client saw only "Pane" here.
  - Programs started over SSH can't show windows, so tests run as scheduled tasks in the logged-on session.
  - On Windows 11 a task's console program goes through conhost, because the Windows Terminal handoff drops the
    arguments. Windows 10's conhost ignores a command line.
  - PowerShell's `$Args` is automatic, and argument lines travel base64-encoded.
  - A Win32 list item has no Invoke for UIA, so lists that open things got an explicit button. That also helps keyboard
    and screen-reader users.
