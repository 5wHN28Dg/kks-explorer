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
  [releases](https://github.com/5wHN28Dg/kks-explorer/releases) (tags `v…`).
- **Guides for teammates, the manager and the maintainer:** the [wiki](https://github.com/5wHN28Dg/kks-explorer/wiki).
  It covers [phones](https://github.com/5wHN28Dg/kks-explorer/wiki/Using-Walkdown-on-a-phone),
  [laptops](https://github.com/5wHN28Dg/kks-explorer/wiki/Laptops), the
  [manager's work](https://github.com/5wHN28Dg/kks-explorer/wiki/Manager-guide), the
  [server](https://github.com/5wHN28Dg/kks-explorer/wiki/Server) and
  [releasing](https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing).
- **Building and testing:** [Development](https://github.com/5wHN28Dg/kks-explorer/wiki/Development), and the README
  of each part (`core/`, `apps/gnome/`, `apps/windows/`, `android/app2/`, `importer/`, `relay/`, `apps/plant3d/`,
  `relay-plant/`).
- **Specifications:** `docs/PROTOCOL-v2.md` (the log, sync, the v1 import), `docs/PATHSTORE.md` (drawings),
  `docs/COURSES.md` (courses), `docs/GLYPHLIB.md` (the reader's glyph library), `docs/PLANT3D.md` and
  `docs/plant3d/` (Walkdown Plant).
- **Why things are the way they are:** the decision records in `docs/decisions/`, and M6's requirements, capability
  matrix and measurements in `docs/m6/`.

## Walkdown Plant

A walkable 3D combined-cycle plant for training, made with Godot (`apps/plant3d/`), released separately (tags
`plant-v…`) for Android, Windows and Linux. The plant is generic and invented: it is not a copy of any real plant.
It has:
- the first train to walk and operate (a gas turbine, its HRSG, the steam turbine, a wet cooling tower and the
  balance of plant), with control room screens, alarms, procedures and tours, the instructor's faults and generated
  P&IDs of its own;
- the water treatment plant, the site and the workers' camp;
- staff with roles who work the full day: shift changes, buses and meals; the trainee can take a role;
- permits to work and isolations with locks;
- lifts and hoists;
- weather, seen and heard;
- the Workshop: one piece of equipment by itself, taken apart and put back, run on its bench and seen inside
  (a pressure transmitter first);
- multiplayer sessions on a LAN;
- the start of the realism programme (`docs/plant3d/REALISM.md`): wear, weather and hands-on work in its engine.

The full day's buses, meals and off-duty life in the camp, lifts, the Workshop, weather, the generated P&IDs and
the realism work came after the newest release
(`plant-v0.3.0`): they are on `main` until the next one.

Its guides and pictures are on the wiki: [Walkdown Plant](https://github.com/5wHN28Dg/kks-explorer/wiki/Walkdown-Plant).

**No plant data is in this repository.** Drawings, tag lists, procedures and photos belong to a plant: its manager
publishes them to the plant's own devices. The program ships only the KKS decode tables (`data/kks.json`), the
Learning courses and Walkdown Plant's invented plant (`data/plant3d/`).

The old KKS Explorer code (Python server, WebView Android app, desktop package, Python reader) was removed on
2026-10-03; it is in git history, and its notes are on the wiki.
