# Walkdown

<!-- read by CI; do not remove -->
Tier: T3
Type: web, native, service

*Formerly KKS Explorer (renamed 2026-10-03).*

Walkdown finds any KKS code on a power plant's P&ID drawings and shows everything known about it:
- the decoded code and where the equipment is;
- photos and notes;
- the operation-manual steps that use it.

It reads the tags straight off vector P&ID PDFs (AutoCAD plots, no text layer). Every device keeps the plant's signed,
append-only log and works offline. Devices sync with the plant's server and with each other, on the same Wi-Fi or
across the internet.

- **Apps:** Android, Windows, Linux (GNOME), and the web pages for browsers. Get them from the
  [latest release](https://github.com/5wHN28Dg/kks-explorer/releases/latest).
- **Guides for teammates, the manager and the maintainer:** the [wiki](https://github.com/5wHN28Dg/kks-explorer/wiki).
  It covers the [move from KKS Explorer](https://github.com/5wHN28Dg/kks-explorer/wiki/Moving-from-KKS-Explorer), the
  [server](https://github.com/5wHN28Dg/kks-explorer/wiki/Server) and
  [releasing](https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing).
- **Building and testing:** [Development](https://github.com/5wHN28Dg/kks-explorer/wiki/Development), and the README
  of each part (`core/`, `apps/gnome/`, `apps/windows/`, `android/app2/`, `importer/`, `relay/`).
- **Specifications:** `docs/PROTOCOL-v2.md` (the log, sync, the v1 import), `docs/PATHSTORE.md` (drawings),
  `docs/COURSES.md` (courses), `docs/GLYPHLIB.md` (the reader's glyph library).
- **Why things are the way they are:** `docs/decisions/` and the development policy `docs/evidence-first-*.md`.

**No plant data is in this repository.** Drawings, tag lists, procedures and photos belong to a plant: its manager
publishes them to the plant's own devices. The program ships only the KKS decode tables (`data/kks.json`) and the
Learning courses.

The old KKS Explorer code (Python server, WebView Android app, desktop package, Python reader) was removed on
2026-10-03; it is in git history, and its notes are on the wiki.
