# Capability matrix: Walkdown

From the policy's templates/capability-matrix.md. Required by `NAT-3`, `WEB-1` and `OTH-2`.

Checked: 2026-10-05   Checked by: the maintainer, with Claude (browserslist 4.29.3 as the policy pins it)
Declared targets: Windows 10 and 11; Linux = GNOME 50 (GTK 4.22 + libadwaita 1.9, portals, D-Bus), as on Ubuntu
26.04 LTS; Android 10+ (API 29); the web client in the browsers below (Safari 17+ is the iOS path); the server on
Linux (systemd user service).
Sources: see the rows. Until #9 rebuilds them in this form, the per-requirement rows are in
[docs/m6/CAPABILITIES.md](m6/CAPABILITIES.md) (checked 2026-09-30, with its sources).

Resolved browser list (web only): the output of `browserslist` (4.29.3) for `.browserslistrc` on 2026-10-05; CI compares it with the current output in both directions (WEB-1).

```
and_chr 154
chrome 154
chrome 153
edge 154
edge 153
firefox 157
firefox 156
firefox 153
ios_saf 27.0
ios_saf 26.6
ios_saf 26.5
ios_saf 26.4
ios_saf 26.3
ios_saf 26.2
ios_saf 26.1
ios_saf 26.0
ios_saf 18.5-18.7
ios_saf 18.4
ios_saf 18.3
ios_saf 18.2
ios_saf 18.1
ios_saf 18.0
ios_saf 17.6-17.7
ios_saf 17.5
ios_saf 17.4
ios_saf 17.3
ios_saf 17.2
ios_saf 17.1
ios_saf 17.0
safari 27
safari 26.6
safari 26.5
safari 26.4
safari 26.3
safari 26.2
safari 26.1
safari 26.0
safari 18.5-18.7
safari 18.4
safari 18.3
safari 18.2
safari 18.1
safari 18.0
safari 17.6
safari 17.5
safari 17.4
safari 17.3
safari 17.2
safari 17.1
safari 17.0
```

## Matrix

Rebuilt in this form by #9. Until then: [docs/m6/CAPABILITIES.md](m6/CAPABILITIES.md).
