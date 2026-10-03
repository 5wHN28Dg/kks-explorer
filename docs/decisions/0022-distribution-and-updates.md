# 0022 Distribution, signing and updates

Date 2026-09-30 · Scope: R23, R24, N6 · Status: **accepted by the user 2026-09-30; changed 2026-10-03: no Microsoft Store** (the user's developer-account
registration was blocked; "windows uses the fallback from now on"). Windows ships as the agreed fallback: an MSIX
signed with our own certificate, which IT trusts once on each machine (or by policy); updates through App Installer
and our own signature check. If IT won't deploy the certificate, the next option is the single exe in a zip (no admin,
one SmartScreen warning, updates verified by our Ed25519 release key)

**Requirements:**
- Desktop: one download, no administrator rights, no separate runtime to install. Android outside the Play Store.
- Updates are verified against the maintainer's signature and installed only when the person agrees.

**What the platforms provide:**

| | Package format | Signing | Updates |
|---|---|---|---|
| Windows | MSIX + App Installer, per user [D] | needs a certificate that chains to a trusted root [D]. Self-signed = trust it on every machine (admin, or IT policy) [D]. Azure Artifact Signing: individuals only in the US/Canada, organizations in the US/CA/EU/UK/… (not available here) [D]. **Microsoft Store: free for individual developers since 2025-09-10, and it signs, hosts and auto-updates MSIX apps** [D] | App Installer auto-update [D], or the Store |
| GNOME | Flatpak, per user [V 1.16 installed] | Flathub signs its repository; own repositories use our GPG key [D] | GNOME Software / `flatpak update`; the person controls automatic updates [K] |
| Android | APK, sideloaded [K] | our own key (today: RSA 4096 in ~/.config) | PackageInstaller with the person's confirmation (today's AppUpdates) [K] |
| Browser | nothing to install | HTTPS | the server serves the current UI |

**Proposed:**
- **Windows: MSIX through the Microsoft Store**, visibility **private audience**: only the listed team members can
  see or install it, and the listing is hidden even from people who have the link [D].
  - The Store signs the package, so we need no certificate and there's no "unknown publisher" warning.
  - The Store updates it, and it installs per user without admin.
  - MSIX also enables the StartupTask (0021) and the package capability for Windows' built-in camera QR scanner
    (0019: worth testing then).
  - **Question for the user:** can the HQ laptops install from the Microsoft Store? Some company IT policies block the
    Store. If they do, the fallback is an MSIX with a self-signed certificate that IT deploys once by policy, updated
    through App Installer.
  - Unverified: whether Iraq is among the Store's markets for individual registration (the announcement says "nearly
    200 markets").
- **GNOME: Flatpak on Flathub.**
  - The GNOME runtime supplies GTK, libadwaita, glycin and the portals the other decisions rely on (0020 Secret, 0021
    Background, camera). Flathub signs and serves it, and GNOME Software updates it.
  - Flathub's requirements fit: the source is public and redistributable (AGPL-3.0), the app contains no plant data,
    and no network access is used at build time [D].
  - Whether libjxl and zxing-cpp are in the GNOME runtime or must be bundled as Flatpak modules: check when packaging
    (0018, 0019 already allow bundling pinned builds).
- **Android:** APK outside the Play Store, signed with the existing release key, updated by the in-app updater with
  the person's confirmation (as today). Play Store later, not blocked (R23).
- **Headless server:** a release archive plus the systemd unit (deploy/), updated by the maintainer. The signed
  release manifest is kept for this and for Android, re-keyed to ECDSA P-256 (0017).
- **Our own desktop updater** (server/updates.py, desktop.py hand-over) **is retired** on Windows and Linux: the Store
  and Flathub are the platforms' update mechanisms.

**Costs:**
- The Store and Flathub each have review steps and submission rules to follow. That is a release-time cost.
- The app is visible on Flathub (public). The Windows Store listing can be private, the Flathub one can't. That's
  fine, since the source is public anyway and the app carries no plant data.
- Private audience on the Store needs each person's Microsoft account email added in Partner Center.

**Revisit:**
- if the Store is blocked at the company;
- if Flathub's policies change;
- when Android moves to the Play Store.

Sources: https://blogs.windows.com/windowsdeveloper/2025/05/19/microsoft-store-expands-opportunities-for-windows-app-developers/ ·
https://www.neowin.net/news/microsoft-store-now-lets-individual-developers-join-for-free/ ·
https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/visibility-options ·
https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options ·
https://learn.microsoft.com/en-nz/answers/questions/5810735/cant-create-a-new-trusted-signing-individual-ident ·
https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview ·
https://docs.flathub.org/docs/for-app-authors/requirements · https://docs.flatpak.org/en/latest/hosting-a-repository.html
