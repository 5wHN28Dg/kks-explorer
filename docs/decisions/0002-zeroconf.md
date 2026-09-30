# 0002 `zeroconf` (Python mDNS / DNS-SD)

Date 2026-09-30 · Scope: server + desktop peer discovery (`server/syncsvc.py`) · Status: **replace** with the OS service (user decision 2026-09-30); on hold until the M6 decisions

**Needed for:** announcing and finding `_kks._tcp` devices on the same Wi-Fi. Optional: without it, sync by address,
QR and relay still work.

**Platform:**
- **Windows 10+:** `DnsServiceRegister` / `DnsServiceBrowse` in `dnsapi.dll`, desktop apps.
- **Linux:** the Avahi daemon over D-Bus on common desktop distributions. Not guaranteed on every distribution;
  *unverified* per distribution.
- **Android:** NsdManager, already used by the app (M3d).
- **Python** has no binding to any of these. Using them means ctypes (Windows) and D-Bus (Linux) adapters.

**Dependency check:** passes every criterion.

| Criterion | Evidence |
|---|---|
| Releases | 0.151.5 on 2026-09-28 |
| Maintainers | 8 active in the last 12 months |
| Security | SECURITY.md present |
| License | LGPL-2.1-or-later, compatible with AGPL-3.0 |
| Track record | since 2014 |

Note: it is a second mDNS responder beside the OS's own. It coexists (port 5353 is shared), but it duplicates a
platform service.

**Decision:** keep in the Python app. Writing two OS adapters now costs more than the dependency. M6 should use the
OS service (DNS-SD on Windows, Avahi on Linux) directly.

**Revisit:** in M6.

Sources: https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsserviceregister · https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse · https://pypi.org/pypi/zeroconf/json · https://github.com/python-zeroconf/python-zeroconf
