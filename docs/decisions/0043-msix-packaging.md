# 0043 Building and signing the Windows MSIX

Date 2026-10-03 · Scope: Windows distribution (0022: no Microsoft Store; a self-signed MSIX that IT trusts once, or
the zip) · Status: **accepted** (follows 0022; tools chosen by Claude, the user asked to finish it).

**Question:** with which tools do we make and sign the MSIX? The project is built on Linux: the Windows app is
cross-compiled with mingw (0033). The signing key must stay on the maintainer's machine, never in CI or a VM image.

## Findings

| Tool | What it does | Maintenance and security | Source |
|---|---|---|---|
| **MakeAppx** + **SignTool** (Windows SDK) | Microsoft's own packer and signer; Windows only | Shipped with every Windows SDK. Also in the NuGet package `Microsoft.Windows.SDK.BuildTools` (10.0.28000.2705, files dated 2026-08), so no SDK install is needed. Windows SDK licence: free to use, not ours to redistribute (we don't) | [D] https://learn.microsoft.com/windows/msix/package/create-app-package-with-makeappx-tool · https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools |
| **makemsix** (msix-packaging, MIT) | Packs and unpacks on Linux | Last release 2023 (MSIX-Core 1.2). A few commits a year; the last on 2026-08-24. Packing is off in the default build | [D] https://github.com/microsoft/msix-packaging (GitHub API, 2026-10-03) |
| **osslsigncode** (GPL-3.0) | Authenticode signing on Linux, APPX/MSIX since 2.7 (2023-09) | Active: the last push was 2026-09-30, with two main maintainers. It has a security response history: 3 advisories, and APPX parsing fixes in 2.13 and 2.14 (2026). Ubuntu ships 2.13 | [D] https://github.com/mtrojnar/osslsigncode/blob/master/NEWS.md |
| Our own packer | An MSIX is a ZIP with a block map; about 200 lines | Ours to keep right against an undocumented validator | — |

What Windows checks [D: https://learn.microsoft.com/windows/msix/package/signing-package-overview]:
- the manifest's `Publisher` must equal the certificate's subject;
- a self-signed certificate must be trusted on the machine. That means `LocalMachine\TrustedPeople`, which IT can push
  by Group Policy.

## Choice

- **Pack with MakeAppx**, from the pinned NuGet package (SHA-256 checked), inside the Windows test VM: Microsoft's
  tool makes exactly what Windows' installer expects. makemsix is too thinly maintained; our own packer would be
  custom code with no reference.
- **Sign on the host with osslsigncode** (the Ubuntu package): the key never leaves `~/.config/kks-explorer/signing`.
  GPL-3.0 is fine for a build tool we don't ship.
- **Verify on the target:** SignTool `verify /pa` in the VM, then `Add-AppxPackage` on Windows 10 and 11 with the
  certificate in TrustedPeople, then start the installed app.
- **Script:** `packaging/windows/make-msix.sh` (layout: the exe, `data/courses`, `vendor/fonts`; logos made from
  `icon-512.png`).
- **Certificate:** until the rename, a *test* certificate (`CN=KKS Explorer Test`) checks the pipeline. The real one
  is made with the new name: its subject becomes the package's publisher identity, and changing it later breaks
  updates.
- **Data:** an MSIX app's `%LOCALAPPDATA%` writes go to the package's own folder, which Windows deletes on uninstall.
  The plant data is in the log on the server and on other devices, but local photos waiting to sync would go with
  it. This goes in the install notes.

**When to revisit:** if osslsigncode signatures stop verifying on a Windows update, sign with SignTool in the VM
(the key copied in and wiped after); or if Microsoft ships a Linux MakeAppx.
