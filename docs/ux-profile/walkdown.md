# UX profile: Walkdown

Stage: **live** (proposed; the owner confirms, see "Owner items" at the end) · Profile version 1 · Review: both
passes on PR #444, posted there as comments (1.7).

The rulebook is the user's `global/UI-UX-POLICY.md`, version 4.13 (where to read it: [docs/UI-UX-POLICY.md](../UI-UX-POLICY.md) section 1); project rules and the
user's carried-over decisions are in [docs/UI-UX-POLICY.md](../UI-UX-POLICY.md). Section numbers below (1.1, 8.5 …)
are the rulebook's. **No plant data in this file:** real numbers about the plant (sheet counts, reader accuracy) stay
in the gitignored `CLAUDE.local.md`. Lines marked *(assumption)* are not yet backed by watching users; the first round
with users (8.6) checks them first.

## Purpose (and what it must never do)

Given only a KKS code, an I&C maintenance engineer finds the equipment on the plant's P&IDs and sees everything known
about it (decoded meaning, location, photos, notes, the procedures that use it), on the plant floor, offline. A
manager keeps the plant's data, people and devices.

It must never show a wrong code or location as certain (a reading the reader wasn't sure of is marked), never lose a
note or photo someone took, and never let plant data leave the plant's own devices and server.

## Product kinds (7.9)

Drawing viewer (VIEW1–3), field tool (FIELD1–2), training and courses (TRAIN1–4, the Learning courses), setup that
hands something to another device (HAND1: sign-up codes, invite QR codes). Automation (AI1–AI5): the tags read off the
drawings and the draft descriptions.

## Core objects and verbs

- **Objects:** sheet (a drawing), tag (a KKS code on a sheet), photo, note, procedure, course; for the manager also
  person, device, proposal.
- **Verbs:** find, open, mark (add a tag the reader missed, correct a reading), add (a photo, a note, a location),
  sync, approve or reject; for the manager remove (a device, a person's access) and publish (new plant data).

## Experience intent and reference products

- **Finding a tag:** instant and certain. Reference: Organic Maps' search and "show on map" *(assumption: named by
  the rulebook for field tools and drawing viewers)*.
- **On the drawing:** smooth like a good map app at every zoom. Reference: Organic Maps.
- **Adding a photo or a note on the plant floor:** one-handed, done in seconds, nothing lost if the network is gone.
  Reference: Organic Maps' "add a place" and its offline edits *(assumption)*.
- **The manager's desk work (approvals, devices, people):** dense, fast, in bulk. Reference: GNOME Settings' lists
  and the GitHub notifications inbox *(assumption)*.
- **Joining:** guided, nothing scary. Reference: Signal's device linking by QR *(assumption)*.
- **Courses:** calm, readable, learnable. Reference: a good course app's reader *(assumption: none named yet)*.

## Core interactions (with feel specs, V14)

| Interaction | Response | Motion | Success | Failure | Reference |
|---|---|---|---|---|---|
| Search a code, pick the result | results update as the code is typed; picking moves the drawing to the tag within 500 ms on the Note 9 | one eased move and zoom to the tag (none with reduced motion) | the tag is highlighted with a highlight that meets A2 and A5, its panel opens | "No tag 11XXX…" says what was searched and what to try (ST2) | Organic Maps: search result to the map |
| Pan and zoom the drawing | follows the finger with no lag; holds the display's frame rate on the Note 9 (VIEW2) | inertia on fling; zoom about the pinch point | sharp lines at every zoom (the vector tiles) | — | Organic Maps |
| Tap a tag | the panel opens within 100 ms (F1) | the panel slides in (none with reduced motion) | the tag is highlighted, the panel names it | a tap between tags asks or zooms (VIEW3) | Organic Maps: tap a place |
| Add a photo | the camera opens at once; the photo appears in the panel at once, marked "waiting to send" offline | — | "Photo sent" or the waiting count (F2, ST3) | kept on the phone, retried, said in plain words (W3) | Organic Maps: add a photo *(assumption)* |

## Users

| Who | Knows | How often, why | Fears | Evidence |
|---|---|---|---|---|
| I&C maintenance engineer (the main group, about 10 people) | KKS, P&IDs and the plant well; phones well; the app a little | daily on walkdowns: find equipment, check a tag, add a photo or note | a wrong code in a work order; losing a photo; looking slow in front of a colleague | the owner is one of them; their messages; the 2026-11 audit *(the rest: assumption)* |
| Manager (the owner) | everything | weekly at a desk: approvals, devices, people, new drawings | locking someone out; publishing wrong data; a leak of plant data | own use |
| Admin (a trusted colleague) | the plant; the app well | approvals, adding devices | approving a wrong reading | assumption |
| New colleague joining | the plant, not the app | once, then daily | not getting in; a security warning | assumption |
| Course learner (any of the above) | varies | occasionally | being judged by others (progress is private) | assumption |

- **Recipients who never run it:** colleagues who receive a code or a photo pasted from the app into a work order or
  a message (I5 exactness matters to them).
- **Where and how:** standing in the plant, often with work gloves, sometimes in direct sun or at night, in noise
  (sound is never the only signal), one hand free, interrupted often; offline inside buildings; sessions of seconds
  to minutes. Managers at a desk, sessions of 10 to 30 minutes.
- **Abilities (floor, 1.1):** the floor in full: low vision, blindness, colour vision deficiency, deafness, limited
  motor control, tremor, one hand, cognitive and learning disabilities, photosensitivity, motion sensitivity. No
  group is N/A. The plant-floor conditions (gloves, sun, one hand) are the everyday case, not an edge case.
- **Age:** adults only; no children use it (T9: N/A, below).
- **Languages:** the UI is English only (the user, 2026-09-30). User content (notes, names, descriptions, photo
  notes) is Arabic, English and mixed, and must display and edit correctly (L2).

## Platforms, sizes, inputs, assistive technology, network

| Platform | Versions | Oldest / smallest device | Typical device | Sizes | First-class inputs | Secondary |
|---|---|---|---|---|---|---|
| Android | 10 and later (the user, 2026-09-26) | Samsung Galaxy Note 9, Android 10, 6.4", 2220 × 1080 px at density 420 (about 846 × 411 dp), Mali-G72, 6 GB | the owner's Honor 600, Android 16 *(colleagues' phones: assumption, mostly Android)* | portrait and landscape; phones and tablets by window size class | touch | keyboard |
| Web (from the plant's server) | Chromium, Firefox, WebKit; Safari 17+ on iPhones (from the home screen). **Open, owner item (#442):** no iPhone is reachable here; the rulebook (1.2, 1.6) asks for an oldest iPhone, owned, borrowed or rented, or else dropping iPhones, a narrowing only the owner may choose | Chromium on the Note 9 at 412 CSS px; any browser at 320 CSS px width (A4's reflow) | Chromium on Android or a laptop *(assumption)* | 320 CSS px to 1920 px; 200 % zoom | touch at phone width; keyboard and pointer at desktop width | — |
| Windows | 10 and 11, x86-64 and ARM64 | the owner's Windows 10 laptop: i7 4th gen U (2 cores), 4 GB, Intel HD 4400, 1920 × 1080 at 125 % | the same laptop *(assumption)* | windows from 360 × 640 logical px up | keyboard and pointer | touch |
| GNOME (Flatpak) | a current GNOME LTS distribution, GNOME 50 runtime | the owner's laptop is the only GNOME device (i7-12700H, about 37 GB, Iris Xe), at its smallest window, 360 × 294 logical px (GNOME2); an older Linux machine is not committed to | the same laptop | 360 × 294 to full screen | keyboard and pointer | touch (pinch on the drawing) |
| The server's command line | Linux (Debian 13 on the server) | 80 × 24 terminal | an SSH session | 80 × 24 and up | keyboard | — |

- **Assistive technology (floor, 1.2):** TalkBack, font scale up to 2.0 and Remove animations on Android; the
  browser's zoom, `forced-colors` and screen readers on the web, and VoiceOver on iOS Safari (iPhones use the web
  app); Narrator, contrast themes and text size on Windows; Orca, Large Text, High Contrast, Reduced Motion and
  animations off on GNOME.
- **Network:** often offline on the plant floor; LAN sync with the server or other devices; across the internet
  through the relay; metered networks sync only when allowed.

## Numbers this profile raises (1.5)

- **Targets (A19):** 48 × 48 dp on Android **and 48 × 48 CSS px on the web at phone width** (gloves; the old policy's
  T1, stricter than A19's 44 CSS px); destructive targets 8 dp or px from any other.
- **Contrast (A1):** on phones (Android and the web at phone width), KKS codes, measured values and the main text of
  cards and lists reach **7:1** in both themes (sun on the plant floor; the old policy's K2, WCAG 1.4.6); secondary
  text (hints, timestamps) keeps 4.5:1.
- **Copy (I5):** see WD-I5 in docs/UI-UX-POLICY.md.

## Main tasks

Targets set 2026-11-19 *(assumptions until the first round with users and the benchmark measure them; 10.1 raises
them)*. Times are an expert's, on the Note 9 unless said.

| # | Task (users' words) | Who | How often | Done means | Targets |
|---|---|---|---|---|---|
| 1 | "Find 11LAB70AA501" | engineer | many times a day | the tag is shown on its sheet and its panel is open | ≤ 3 actions plus the typed code; ≤ 10 s from the app's open screen |
| 2 | "What is this on the drawing?" (open a sheet, find a tag by looking, open it) | engineer | daily | the panel of the tapped tag is open | ≤ 4 actions from the open screen |
| 3 | "Add a photo or a note to this tag" | engineer | daily | it is sent, or waiting to send with the count shown | ≤ 4 actions after the panel is open, offline too |
| 4 | "Show me the procedure's steps and the equipment" | engineer | weekly | the steps are listed and their equipment highlighted on the drawing | ≤ 3 actions to the first step |
| 5 | "Mark a tag the reader missed; correct a reading" | engineer | weekly | the proposal is sent or waiting | ≤ 5 actions |
| 6 | "Approve or reject what people sent" (bulk) | manager, admin | weekly | the decided items leave the queue, with one Undo or one confirmation for a batch | 20 items in ≤ 4 actions (WD-S5) |
| 7 | "Add a device; remove a lost phone" (removes a device's trust: never undone) | manager, admin | monthly | the device can or can't sync | ≤ 5 actions, plus S2's confirmation |
| 8 | "Publish new drawings" (admin.html's Drawings: import, re-import, remove; or the server's `publish-data`); each publishes a new plant-data version to every device | manager | monthly | the new plant data reaches the devices; the tag list is backed up first and put back if an import fails | ≤ 5 actions in admin.html plus the import's wait; each part reports PASS or FAIL (S8, #441) |
| 9 | "Install, join the plant, and update" | new colleague | once; updates monthly | from the release page to task 1, through the install warnings, each explained beforehand (#439); joining by server sign-in, QR code, an admin on the Wi-Fi, or a file; a sign-up waits for approval as a designed state | joining ≤ 2 min excluding the wait for approval |
| 10 | "Get back in" (a forgotten password, a lost phone) | anyone | rare | a path shown in the product leads back (S9) | a forgotten password: a reset link from the manager in ≤ 5 of the manager's actions *(assumption)* |
| 11 | "Sign out; delete my photo or note; withdraw a proposal" | anyone | rare | done, with the unsent count shown before (S3) | ≤ 3 actions plus the confirmation |
| 12 | "Make it readable for me" (dark drawings; the system's text size, contrast and motion settings are followed) | anyone | once | the app follows the setting | dark drawings ≤ 2 actions; the system settings followed with no action in the app |
| 13 | "Take a course" | anyone | occasionally | a page read, a question answered, progress kept privately | ≤ 3 actions from the open screen to the page where the learner left off |
| 14 | "Report a problem" (diagnostics to the manager) | anyone | rare | the report reaches the manager privately (FIELD1) | ≤ 4 actions |
| 15 | "Remove someone's access" (deactivate a person, remove their devices; never undone for devices) | manager, admin | rare | the person can no longer sign in or sync | ≤ 4 actions plus S2's confirmation, which names the person and the consequence |
| 16 | "Open or close sign-up" (the sign-up code; admin.html) | manager | rare | new people can or can't ask to join | ≤ 3 actions |
| 17 | "Update the server" (`deploy/` scripts on the server) and its other commands (`set-signup-code`, `reset-password`, `reset-manager`, `web-sign-in`) | manager | per release | the new build runs and is healthy, or the previous one is back | each part reports PASS or FAIL (S8, CLI5; #441) |

## Screen table

The main navigation: Android's bottom bar and Windows' tabs (Drawings · Procedures · Review · Learning · Manage); the
web's header buttons (Systems, Coverage, the drawing and floor selects, Procedures, Review, Connectors, Sheet notes,
Learning, About, Account); GNOME's sidebar (Sheets, then Procedures, Equipment by system, Coverage, Learning, Review
queue, Connectors on this sheet, Notes on this sheet, Manage). One row per group with one layout template; the
evidence includes the group's most complex member. Intent order is for V1.

| Screen or group | Job (tasks) | Visible at the smallest size without scrolling | Primary action | Input per method | Intent order |
|---|---|---|---|---|---|
| Drawing viewer (all clients) | 1, 2, 4 | the drawing; the search field or its button; the sheet's name; the sync and offline state | search | touch: tap the field, tap a result, pinch, tap a tag; keyboard: `/` or the field, arrows to pan, + and − (WD-A18), Enter; pointer: click, wheel | 1. the drawing with the selected tag; 2. search; 3. sheet name and state |
| Tag panel (all clients) | 1, 2, 3, 5 | the code (whole, W7), its Copy, Close; the decoded meaning | add a photo | touch, keyboard and pointer: each button | 1. the code; 2. what it is and where; 3. photos and notes |
| Side lists: Equipment by system, Coverage, Procedures and a procedure, Review, Connectors, Notes | 1, 4, 5 | the title, Close or Back, the first rows | open the chosen item | tap, click, or arrows and Enter | 1. the list; 2. the title; 3. filters |
| Multi-select: the pick bar and its dialogs (Selected codes, Place, Note, Photo for all) | 3, 6 | the count, Done | the batch action ("Note for all") | tap, click, keyboard | 1. the count; 2. the batch actions |
| Small dialogs and confirmations (mark a missing tag, dark drawings, where does it continue, which floor, every confirmation) | 3, 5, 7, 11 | the whole dialog: its question, the object named, both buttons | the named action (destructive ones styled destructive, focus on the safe choice) | tap, click, Enter and Escape | 1. the question and the object; 2. the safe choice; 3. the action |
| Photo editor and viewer | 3 | the photo, the tools, Cancel and Use photo or Send | Use photo / Send | touch: tap to place a box, then resize (#375); pointer drag; keyboard per #375 | 1. the photo; 2. the marks; 3. Send |
| Join, sign-in, sign-up, set up this device (web overlays, Android setup, GNOME and Windows setup) | 9, 10 | the ways in, each with one line saying what it needs | the chosen way in | tap, click, keyboard; paste and QR (A26) | 1. the ways in; 2. what each needs |
| Manage and its pages: Approvals, My proposals (web "My submissions"), History, People (web "Users"), Devices, Leaderboard, Account, Diagnostics, Updates (web), Drawings (web); admin.html | 6, 7, 11, 14 | the page's title, its list's first rows, its batch bar when items are picked | per page: Approve selected; Add a device | tap, click, keyboard (I8 for tables on the web) | 1. what waits for a decision; 2. the batch actions; 3. the rest |
| About (all clients) | 9, 14 | name, version (copyable), licences | — | — | 1. name and version |
| QR scanner (joining with a code; adding a device) | 9 | the camera view, what to point it at, Cancel, the paste alternative | — (scanning is automatic) | touch, click; paste as the alternative (A26) | 1. the camera view; 2. what to do |
| Status bars and cards: the photo queue bar ("N photos waiting"), the background-sync notice (phones that limit it), the offline and sync state | 3, 9 | the count and what it means | the notice's "Open settings" | tap, click | 1. what waits or what is wrong; 2. what to do |
| Update banner and Updates card (Android), Updates tab (web admin) | 9 | what changed, Install, Later | Install | tap, click | 1. what changed; 2. Install |
| Learning list and course reader (learning.html, course.html, the apps' Learning) | 13 | the course or page title, the page, Next | Next / answer | tap, click, keyboard | 1. the page's content; 2. where in the course; 3. Next |
| The server's command line (`kks-server` commands) | 8, 10 | — (80 × 24) | — | keyboard | 1. PASS or FAIL per part; 2. what to do about a FAIL |

The screen table's coverage test (a screen the apps have that this table lacks fails) comes with the automated
evidence in phase 2. There is no settings screen: the apps follow the system's settings, and "Dark drawings" is a
dialog.

## Budgets (with tolerance) and the benchmark walk

The numbers and how they are measured are in `docs/m6/MEASUREMENTS.md` (rules written before the first measurement);
the default tolerance is 5 % or the measurement's noise (1.5), and MEASUREMENTS.md's own regression rules apply where
they are stricter or were set by the user.

- **Android (Note 9, release build):** cold start to the first sheet ≤ 3 s (MEASUREMENTS.md; stricter than P3's 5 s);
  warm start ≤ 2 s (P3's default, not yet in MEASUREMENTS.md);
  steady memory ≤ 300 MB PSS; installed size growth over 25 % needs a reason; background battery ≤ 1 % an hour.
- **Windows:** private bytes ≤ 400 MB 15 s after start; start-up ≤ 2 s warm and 5 s cold on the Windows 10 laptop
  (P3 defaults).
- **Web:** LCP ≤ 2.5 s, CLS ≤ 0.1, INP ≤ 200 ms, TBT ≤ 200 ms (P5), Chromium throttled to the Note 9; the download
  size within `web-size.json` (CI's `web-size` job; growth needs a reason in the PR, 10.3).
- **Photos:** stored at up to 2560 px on the longer side (the user, 2026-11-17, decision 0074).
- **Frame rate:** panning and zooming hold the display's frame rate on the Note 9 (VIEW2).
- **The benchmark walk** *(to be scripted in phase 2)*: a cold start; the largest synthetic sheet (generated at 10
  times the real largest sheet's path count, from the private statistics); search a code; open its panel; pan and
  zoom for 30 s; add a note offline; reconnect and sync; on the Note 9, the Windows 10 laptop and throttled Chromium.

## Real-data evaluations (1.5)

Private and local, aggregate numbers only (Z1). Baselines live in the gitignored `CLAUDE.local.md`; PRs state only
pass or fail against them.

- **The reader's accuracy per sheet:** the importer's tag readings against the verified reference sheets.
- **Find-a-tag on the real largest sheet:** the benchmark's tasks 1 and 2, timed (VIEW2's benchmark sheet).
- The combined score, the first snapshot and its held-out part are the owner's (owner items below).

## Declarations (1.5)

- **Expert tool.** Relaxes U1's "no outside documentation" and H1's time. Fallback: the named training is the plant's
  own KKS and I&C training plus the app's Learning courses (`data/courses/`) and the wiki's guides for phones,
  laptops and the manager; the domain words are in the glossary below (W1).

## Modules

WEB (7.1), GNOME (7.2), AND (7.3), WIN (7.4), CLI (7.7, the server's commands and `kks-import`), MSG (7.8, Android's
notifications), and the kinds above.

## Design system

- **The platforms' own, plus these additions:** libadwaita on GNOME; Material 3 on Android; standard Win32 controls
  drawn in our own dark colours on Windows (the user, 2026-11-15); on the web, native HTML elements and the CSS custom
  properties in `index.html`'s and `admin.html`'s stylesheets, built as elements (`K.h`), never markup.
- **The user's design choices** (tie-breakers before the platform guidelines; docs/UI-UX-POLICY.md section 3): the
  web phone header (48 px controls, the rest in ⋮); corner glyphs per tag state; one shared in-page confirm dialog
  with named buttons plus Undo toasts; the offline state then the waiting count; error sentences per client from the
  core's error kinds; one live line naming the selection; tap to place a box in the photo editor; background sync's
  notice instead of a foreground service.
- **Voice:** plain, short, calm; no exclamation marks; say what happened and what to do; never blame.
- **Glossary (first version):**
  - **KKS code:** the plant's identification code of a piece of equipment or a measurement (e.g. 11LAB70AA501).
  - **P&ID, drawing, sheet:** "sheet" in the UI; a piping and instrumentation diagram.
  - **Tag:** a KKS code drawn on a sheet. **Reading:** what the importer read off the drawing; "to review" when it
    wasn't sure.
  - **Proposal:** a change someone sent that waits for approval (web "submission": to be unified, #384).
  - **Manager, admin, member:** the roles.
  - **Device:** a phone or computer joined to the plant. **Sync:** exchanging changes with the server or other
    devices. **Offline:** no connection; changes wait to be sent.
  - **Procedure:** an operation-manual procedure; **step:** one of its lines.
  - **Course:** a Learning course.

## Evidence tools and synthetic data

- **Evidence tools** (development only, outside every product manifest): `tools/ui_audit/` (README there); the e2e
  harnesses `android/app2/e2e/` (emulator only, `ANDROID_SERIAL=emulator-…`), `platform/linux/e2e/test_web_*.py`
  and `tests/web/` (Playwright, three engines), `apps/gnome/e2e/` under `headless.sh` only, `apps/windows/e2e/` (the
  VMs, one at a time under `vm.lock`, and the owner's Windows 10 laptop when `~/kks-work/bin/laptop-free` allows); the
  servers come from `tests/e2e_server.py`. The memory and lock rules in CLAUDE.md and `~/kks-work/build/agent-rules.md` apply to every run: one emulator or VM at a time under `vm.lock`; GNOME runs only under `headless.sh` and one at a time under `flock ~/kks-work/build/gnome-e2e.lock`.
- **Synthetic data:** (the example code below is the repository's long-standing test code; whether it is safe to keep is
  an owner item, kept privately) the sample sheet `importer/tests/vectors/kkp-sample.pdf`; Walkdown Plant's generated P&IDs of an
  invented plant (the README's screenshots); the tag 11LAB70AA501 with long text; the Arabic fixture
  `مضخة التغذية 11LAB70AA501 تعمل` and the mixed line of L2; made-up people ("The Manager", "Tom Tester",
  "تالا Member"); the hostile-content fixture (T7) *(phase 2)*. Generated from recorded statistics of the real data
  (kept privately) and re-measured at each full audit *(phase 2)*.
- **Evidence store:** each PR's comments (the results tables); full audits in `docs/ui-audit/YYYY-MM.md` with their
  shots; local evidence manifests under `refs/ux-evidence/pr-<n>` *(phase 2)*.

## Applicability list (N/A per platform, with reasons)

| Rule | Platforms | Reason |
|---|---|---|
| GM1–GM10, TUI1–TUI6, READER, SHARE, ALERT, FILTER | all | not a game, a terminal UI, a reader, a file-sharing tool, an alert service or a filter |
| A14, A15 | all | no speech, video or audio in the apps or the courses (recheck when a course gains media) |
| A16 | all | no sounds (recheck if one is added) |
| A30 | web, GNOME, Windows | no haptics there (Android: applies where the app vibrates) |
| L1's plurals in other languages, L6 | all | the UI is English only (the user, 2026-09-30); English plurals still follow W5 |
| T9 | all | no children use it (adult plant staff); in any case it has no tracking, no ads and no contact with strangers |
| T13 | all | it republishes nothing |
| S8 | GNOME, Windows and Android | these clients change no network, firewall or service, and no plant data beyond proposals; S8 applies to admin.html's Drawings and Sign-up (they change the running server's published data and sign-up) and to the server's commands and update scripts, where the way back is never at risk (data, not network) but rollback and PASS/FAIL per part are tracked in #441 |
| GNOME6 | GNOME | no privileged work |
| WEB6 | web | served by a full server, not a router |
| AND6's Wi-Fi Direct part | Android | not used |
| AND4's orientation | — | not N/A: Walkdown works in both orientations |

## Accepted Not-checked reasons (9.3)

| Reason | Covers | Expires |
|---|---|---|
| No iPhone here: Safari and VoiceOver on a real iPhone (hardware not owned; Playwright's WebKit and the ARIA snapshot stand in) | WEB4's Safari, A8's VoiceOver, P5's iPhone timing | renewable (hardware); listed in the accessibility statement (#440) |
| Real TalkBack speech, sunlight and gloves: checked on the Note 9 in the owner's check before release (8.5, FIELD2); the tree and measured sizes stand in for the merge | A8's speech, A1 in sun, A19 with gloves | 2027-05-19 |
| Windows on ARM64: no ARM64 machine here (hardware not owned); the same code as x86-64. Never covers the never-waivable set (S1–S3, S8, A10, T0, T1, T9, Z1), which is checked through the shared x86-64 code | the other rules on Windows ARM64 | renewable (hardware) |

## Third-party surfaces

The system file picker and camera (photos), Android's clipboard preview, the system's notification shade, Android's
battery and app-launch settings page (the background-sync notice opens it), the browser's own UI around the web app,
the QR scanner's camera view (zxing-cpp inside the app). Noticed by the e2e runs at each platform or engine upgrade
(the emulator image, the Flatpak runtime, Playwright's browsers).

## Review brief

[review-brief.md](review-brief.md), version 1.

## Waivers

None (the old Workshop exception is a Plant budget now).

## T0: the law's interface duties

The checklist of duties per place is the owner's (T0). Places offered: GitHub releases (Android APK, Windows MSIX,
Flatpak bundle) and the plant's own server; no app store. Until the owner writes the checklist, every T0 question is
an owner-check item, and the change it belongs to doesn't merge until the owner answers (#442).

## Owner items (only the owner settles these)

Listed in #442, each with options: the stage; the owner budget (minutes a month); the cadence and people of rounds
with users; the real-data evaluations' combined score, first snapshot, held-out part and tolerance; the T0 checklist;
confirming the reference products and experience intent above.
