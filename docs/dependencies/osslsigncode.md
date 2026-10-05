# Dependency record: osslsigncode 2.13 (Ubuntu package)

Added: 2026-10-03 (decision 0043)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: build-time (release signing; nothing of it ships, but the MSIX packages carry the signature it makes)
Packages covered: `osslsigncode` 2.13-1 from Ubuntu 26.04's universe archive, unpacked without root into
`~/.local/kksdev/root` (`packaging/windows/make-msix.sh` uses the system one when installed)

## Purpose
Signs `Walkdown.msix` and `Walkdown-arm64.msix` with the project's code-signing certificate (Authenticode), on the
maintainer's machine, so the private key never leaves it (0043); also verifies the signature before release.

## Platform alternative checked
Microsoft's tool is SignTool from the Windows SDK, which runs only on Windows
([SignTool](https://learn.microsoft.com/windows/win32/seccrypto/signtool)). Using it means copying the signing key
into the Windows test VM (0043's fallback, "the key copied in and wiped after"). Linux has no Authenticode signer of its
own. MakeAppx (packing) is the platform's tool and is used as such, in the VM, from the pinned NuGet package.

## Custom implementation considered
Our own Authenticode/APPX signer: a PKCS#7 signature over the package's block map and content, with Microsoft's
specific attribute layout. That is security-critical code (a mistake invalidates every install, or worse, signs the
wrong content) with no reference besides Windows' validator. Not worth owning.

## Transitive dependencies
Count: 0 beyond the OS   How counted: the package's `Depends:` (`apt-cache show osslsigncode`): `libc6`, `libssl3t64`
(OpenSSL 3), `zlib1g`, all from Ubuntu's main archive (platform-provided on the build host).

## License
GPL-3.0-or-later ([LICENSE.txt](https://github.com/mtrojnar/osslsigncode/blob/master/LICENSE.txt)). A build tool we
run, not distribute; its output (a signature) carries no license obligation. Copyleft would be "review-needed" under a
typical allowlist; this record is that review.

## Maintenance signals
- Recent releases: 2.14 on 2026-07-20, 2.13 on 2026-02-10, 2.12 on 2026-02-02, 2.11 on 2026-01-20
  ([releases](https://github.com/mtrojnar/osslsigncode/releases)).
- Security response: published GitHub advisories with fixed versions: CVE-2026-39853 (stack buffer overflow during
  verification, fixed in 2.12), CVE-2026-39855 and CVE-2026-39856 (out-of-bounds reads in PE page hashing, fixed in
  2.13) ([advisories](https://github.com/mtrojnar/osslsigncode/security/advisories)). Our 2.13 has all three fixes;
  2.14 adds APPX parsing fixes (0043, [NEWS](https://github.com/mtrojnar/osslsigncode/blob/master/NEWS.md)).
- Active maintainers: two main ones, mtrojnar (23 commits in the last 12 months) and olszomal (21), plus four
  occasional contributors (GitHub contributor statistics, 2026-10-05).
- Age across major versions: since 2005 (Per Allansson), maintained by Michał Trojnara since 2018; 1.x → 2.x, APPX/MSIX
  since 2.7 (2023).

## Size impact
None in the product (build tool). The signature adds a few KB to each MSIX.

## Replacement cost
Low. One command in `packaging/windows/make-msix.sh` (sign, then verify). SignTool in the VM is the documented fallback.

## Decision
Keep. It is the only maintained way to sign MSIX on Linux, which keeps the signing key on one machine; it has a real
security response, and the version we use contains every published fix. Weak points: Ubuntu's 2.13 lags upstream's
2.14 (APPX parsing fixes; it only parses our own package), and the package is fetched by hand, not pinned in a script.
Revisit if its signatures stop verifying after a Windows update (then SignTool, 0043).
