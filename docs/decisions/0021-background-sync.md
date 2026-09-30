# 0021 Background sync

Date 2026-09-30 · Scope: R16, R18, R20 · Status: **accepted by the user 2026-09-30**

**Requirement:**
- Devices sync without being opened: phones periodically, only on unmetered networks unless the person allows metered.
- Devices on the same Wi-Fi find each other and sync within seconds.

**What the platforms provide:**

| | Start at login / run in the background | Scheduled work | Found on the Wi-Fi (0002) |
|---|---|---|---|
| Windows | ✅ `HKEY_CURRENT_USER\…\CurrentVersion\Run`: per user, no admin [D]; notification-area icon (Shell_NotifyIcon) [K] | Task Scheduler [K] | DNS-SD `dnsapi` [D] |
| GNOME | ✅ Background portal `RequestBackground` with `autostart` [D]. GNOME lists such apps under "Background Apps"; stock GNOME has no tray icon [K] | systemd user timers [K] | Avahi [V] |
| Android | ✅ WorkManager periodic work with network constraints (today: 15 min, UNMETERED unless allowed) [K] | WorkManager | NsdManager [K] |
| Safari / browsers | ❌ nothing in the background (Background Sync and Periodic Sync are Blink-only) [D] | ❌ | ❌ |

**Proposed:**
- **Windows:**
  - Register at login in the per-user `Run` key, only when the person enables "Keep syncing in the background" in
    Settings.
  - A notification-area icon shows status and gives Open/Quit.
  - Syncs on a timer, and within seconds when a device is found or data changes (today's rules).
  - If Windows packaging becomes MSIX (0022), use its StartupTask instead.
- **GNOME:** the same setting asks the Background portal for background running plus autostart. The system shows the
  app under Background Apps, where the person can stop it. No tray icon, since GNOME doesn't have one.
- **Android:** as today. Discovery and quick syncs while the app is on screen; WorkManager every 15 minutes otherwise,
  unmetered by default, metered when allowed.
- **Browser clients:** sync only while the page is open. The page shows the last successful sync, and warns when it
  is old. That limit is accepted, and documented in docs/IOS_RESEARCH.md.
- **Default:** background sync is **on** for phones (as today) and **asked on first run** on desktops. A desktop
  program starting at login should be the person's choice.

**Costs:** there are two small platform adapters (Run key + notification icon; the portal call) with nothing to bundle.

**Revisit:** if WorkManager's minimum interval or the portal's behaviour changes.

Sources: https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys ·
https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Background.html · docs/m6/CAPABILITIES.md §5
