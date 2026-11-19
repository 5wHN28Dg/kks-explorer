# UI and UX policy (Walkdown and Walkdown Plant)

Status: since 2026-11-19 this project follows the user's own UI and UX policy, version 4.13, as its rulebook. The
user asked for it in `~/kks-work/INBOX.md` on 2026-11-19 (marked read at 06:21): "I have a new UI/UX policy, adopt it instead of
the current one, it is tailor made of my projects". It replaces the project policy adopted on 2026-11-15 (its last
text: `git show 225145dc:docs/UI-UX-POLICY.md`; the 2026-11 audit in `docs/ui-audit/` uses its rule IDs).

This page holds only what is specific to this project:

1. where the rulebook and the profiles are;
2. the few project rules that stay on top of the rulebook, because the old policy was stricter there;
3. the user's decisions carried over from the old policy and from the audit issues;
4. which files count as UI;
5. a map from the old rule IDs to the new ones, and from the old audit issues to the new rules;
6. where adoption stands.

## 1. The rulebook and the profiles

- **The rulebook:** the user's `global/UI-UX-POLICY.md` in their Personal-LLM-prompts repository (on the owner's
  machine `~/Documents/GitHub/Personal-LLM-prompts/global/UI-UX-POLICY.md`), **version 4.13 (2026-11-18), sha256
  `6313744f37b408b72d99028684caa70c10e4aa6118e05e87a7bef51f6f29ffe5`**. Agents and reviewers read that file and
  check its hash; if it differs, the version in force here is still 4.13 until a PR updates this line with the new
  version line. Whether a copy of it is also kept in this public repository is the owner's choice (#442). Only the
  user changes the rules (its section 11).
- **The profiles** (its section 1):
  - [docs/ux-profile/walkdown.md](ux-profile/walkdown.md): Walkdown (web, GNOME, Windows, Android, and the server's
    command line);
  - [docs/ux-profile/plant.md](ux-profile/plant.md): Walkdown Plant (desktops and Android).
- **The review brief** (its sections 1.6 and 8.4): [docs/ux-profile/review-brief.md](ux-profile/review-brief.md),
  versioned. Until the prompt script of section 8.4 exists, the brief is pasted word for word into each reviewer's
  prompt, and the PR records its version.

Rule IDs in this repository mean the rulebook's IDs (A1, S1, GM6.1 …). The project rules below carry a `WD-` prefix.

## 2. Project rules on top of the rulebook

The old policy asked for more than the rulebook in these points. Section 0.2 of the rulebook says a stricter project
rule wins, so they stay. Each one adds to the rulebook rule named in brackets.

- **WD-N3 (Block; adds to N3):** a Close, Back, Cancel or Done control that stays visible also stays **in the same
  place** while the content scrolls (its bounds in the accessibility tree don't change).
- **WD-E7 (Advice):** a form's Save or Send is in a bar that stays visible, or directly after the last field; never
  after a list that can grow without limit.
- **WD-I5 (Block; adds to I5):** the copy confirmation **names what was copied** ("Copied 11LAB70AA501"), except
  where the platform shows its own preview (Android 13 and later). Identifiers drawn as part of a picture (tags on a
  drawing, codes on Plant's control room screens and P&IDs) can't be selected; there the item's card or panel, one
  tap away, offers the copy. This exemption is looser than I5 read strictly: under the rulebook's 0.2 it stays only until the next
  full audit or 2027-05-18, whichever comes first, and then becomes a waiver (11.2) or goes.
- **WD-S5 (Block; adds to S5):** 20 synthetic items in each list that asks the same decision of many are decided
  in at most 4 actions (the old B1's check).
- **WD-S5a (Advice):** after a bulk action the list keeps its place and says what happened ("12 accepted").
- **WD-S2 (Block; adds to S2):** web confirmations use the page's own dialog, never the browser's `confirm()`, which
  can't name its buttons.
- **WD-C4 (Block; adds to C4):** a Walkdown feature that one client lacks is also recorded in
  `docs/m6/CAPABILITIES.md`, beside the issue for each client left out.
- **WD-A18 (Block; adds to A18):** the drawing pans with the arrow keys and zooms with + and − on every client with
  a keyboard.
- **WD-8.9 (process; adds to 8.9):** besides the rulebook's full audits, a full audit runs before each release
  that changed UI on more than one platform (the old policy's 3.1).
- **WD-A12 (Block; adds to A12):** each sheet's tags are also reachable as a list (search or the sheet's tag list)
  that opens the same panel as tapping the tag, so a screen-reader or keyboard user reaches every tag.

Everything else the old policy asked is covered by a rulebook rule at least as strict (the map in section 5), or by a
number in a profile (gloves: 48 dp targets also on the web at phone width; sun: 7:1 for codes, values and body text on
phones; the frame rules).

One old point changes by the adoption itself: the old CLAUDE.md rule made the UI audit's two passes come "on top of
the two code reviews"; the rulebook (0.2, 8.4) makes the two review passes of the global workflow also the UI passes,
with the policy, profile, brief and evidence added. A reviewer may still post the code review and the UI table as
separate comments.

Two old points were looser than the rulebook and are dropped, as the user asked for a replacement: "Advice fails never
block" (now section 9.1 decides), and "a new screen built from shared widgets carries their filed fails as
pre-existing" (now section 9.2: a fail that reaches more screens is worse).

## 3. The user's decisions carried over

Each is in a profile too, as a number, a declaration or a design choice (the tie-breakers of section 1.3 point to
them). Who decided, when and where:

| Decision | When, where | Now in |
|---|---|---|
| English UI only; user content may be Arabic or mixed | the user, 2026-09-30 (`docs/m6/REQUIREMENTS.md` N7) | both profiles, Languages |
| Android 10 minimum (Note 9); Windows 10; a current GNOME LTS; Safari 17+ (iPhones: dropped from the Walkdown profile by the user, 2026-11-19, in the session; the web app is no longer checked on an iPhone) | the user, 2026-09-26 (REQUIREMENTS.md N8); the user, 2026-11-19 | both profiles, Platforms |
| Plant's Workshop keeps its own frame rule: no frame over 100 ms the app causes, at least 95 % of frames at 30 fps over the Workshop walk; 99.9 % elsewhere in normal play | the user, 2026-11-15, #392 (PR #393) | Plant profile, Budgets (a profile number under GM6.1, not a waiver) |
| Fast-forward's frames are not judged | the user, 2026-10-27 (`docs/plant3d/MILESTONES.md`) | Plant profile, Budgets |
| Plant: a UI size setting from 100 % to 200 %; each phone starts at the size its screen needs (buttons 48 dp, text 14 sp); one compact top row on phones | the user, 2026-11-15 (#382) and 2026-11-18 ("Size by the screen, allow more", PR #410) | Plant profile (it is also Plant's text-size setting for A4 and GM4.2) |
| Plant's HUD text over the 3D view gets a small translucent backing panel (the old K5 kept as written) | the user, 2026-11-15 (#381 comment) | A6; open in #412 |
| Web phone header: the most used controls at 48 px, the rest in an overflow (⋮) menu | the user, 2026-11-15 (#367) | Walkdown profile, design choices |
| Windows: full Win32 dark (our own dark colours for every control); text size by fonts plus a fluid layout, in stages | the user, 2026-11-15 (#377) | Walkdown profile, design choices (stricter than WIN1, where dark common controls are Advice) |
| Photos stored at up to 2560 px | the user, 2026-11-17 (PR #405, decision 0074) | Walkdown profile, budgets |
| Plant is landscape only (its two-stick controls need it) | `project.godot`; old policy G3 | Plant profile, applicability (AND4's orientation: essential, WCAG 1.3.4) |
| Plant's APK at most 250 MB; MSIX and Flatpak at most 300 MB | the user, 2026-11-01 and 2026-10-23 (apps/plant3d/README.md) | Plant profile, Budgets |
| Background sync on phones that limit it: a notice with a button to the system settings, no foreground service, no FCM | CLAUDE.md, Android lessons | Walkdown profile, design choices |
| No Microsoft Store; a self-signed MSIX | the user, 2026-10-03 | both profiles, Platforms |
| Defaults the user accepted on 2026-11-15 (comments on #365–#383): a shared in-page confirm dialog with named buttons plus Undo toasts where the server can reverse the action; `rememberSaveable` for sheet, tag, scroll and drafts; corner glyphs per tag state plus words for course readings; error codes from the core plus a sentence table per client; the offline state first, then the waiting-changes count; bundle work on a worker thread; one live line naming the selection; tap to place a default box, then resize, the drag staying; web text sizes fields first, then 16/14/12 px; GNOME AdwBreakpoints; selection plus a batch endpoint for repeated decisions | the user, 2026-11-15 | Walkdown profile, design choices |

The old policy's only waiver (the Workshop's frame rule) is now a profile number, so the waiver list is empty.

## 4. What counts as UI here

A change is a UI change when it touches what a user sees, hears or does (the rulebook's "touched", section 0.3; when
unsure, it is touched). In this repository that is at least:

- **Walkdown web:** `*.html`, `index.js`, `admin.js`, `learning.js`, `course.js`, `common.js`, `tiles.js`,
  `course-bridge.js`, any stylesheet, `sw.js` where it changes what is shown offline;
- **GNOME:** `apps/gnome/`; **Windows:** `apps/windows/`; `apps/common/` where it makes or words UI;
- **Android:** `android/app2/src/main/kotlin/kks/explorer/ui/`, `MainActivity.kt`, `LinkActivity.kt`, `res/`, the
  manifest; other Kotlin where it changes what a user sees (a notification's text);
- **text from the core or the server that a user reads** (error sentences; the server's command-line output and
  `--help`, module 7.7);
- **Walkdown Plant:** `apps/plant3d/ui/`, `apps/plant3d/app/` (HUD, map, about, settings, controls),
  `apps/plant3d/workshop/` views, any `.tscn` with `Control` nodes, sounds and haptics, and the texts the UI shows
  (`tools/plant3d/manual_texts/`, scenario and procedure content: tier 2 by section 8.2);
- **courses** (`data/courses/`): content changes are tier 2 (section 8.2 and TRAIN1);
- **the README and wiki pages that tell people how to install and use the apps**: prose, checked at each release
  (section 0.1).

## 5. Old rule IDs and old audit issues

### 5.1 Old rule → new rule

| Old | New | Old | New |
|---|---|---|---|
| T1 phone targets 48 dp | A19 (48 dp also on the web at phone width: profile number), AND5, GM1.5 | F1 action shown | F1 |
| T2 no overlap, destructive 8 dp | A19 | F2 errors in plain words | W3 (CLI2 for the command line) |
| T3 desktop 24 px | A19 | F3 offline is a state | ST3, F4 |
| T4 tap near a tag (Advice) | VIEW3, GM3.4 (now Block) | F4 status to screen readers | A8 |
| T5 gesture alternatives | A20, A22 | F5 field errors | E3 |
| R1 Close never scrolls away | N3, GM4.5, WD-N3 | F6 empty screens | ST2 |
| R2 Back and Escape | N2, AND2, GM4.5 | D1 undoable or confirmed | S1, F2, A21 |
| R3 nothing under bars or sticks | AND1, WEB3, GM1.5, GM4.1 | D2 safe default | S2, WD-S2 |
| R4 Save after the last field (Advice) | WD-E7 | D3 input never lost | S3, E5 |
| C1 identifiers copyable | I5, WD-I5 | D4 sign-out counts | S3 |
| C2 exactly the identifier | I5 | X1 same name | W1, C2 |
| C3 copy says what | I5, WD-I5 | X2 feature parity | C4, WD-C4 |
| B1 bulk decisions | S5, WD-S5 (no 5-item threshold now) | X3 platform conventions | C3, I2, GNOME1, WIN1, AND1, WEB3, A18 |
| B2 bulk shows count, one undo | S5 | A1 keyboard | A18, A23, WD-A18 |
| B3 list keeps its place (Advice) | WD-S5a, P4 | A2 names | A8, AND5, GNOME4, WIN2 |
| K1 text contrast | A1 | A3 drawing without sight | A12, WD-A12 |
| K2 7:1 on phones | A1 (profile raises to 7:1) | A4 motion | A11, A10 |
| K3 non-text 3:1 | A2, A23 | A5 Plant screen readers | A8, GM7.3 |
| K4 colour not alone | A5 | L1 mixed text | L2, WIN3, GNOME5 |
| K5 text over pictures | A6, GM4.1 | L2 labels grow | L3, A4 |
| K6 dark complete | A7 | L3 units | W5 |
| K7 no white flash (Advice) | A7 (now Block) | L4 dates (Advice) | W5 (now Block) |
| S1 minimum text sizes | A3 (Plant: the game numbers, measured as text height) | L5 counts (Advice) | W5 (now Block), L1 |
| S2 system text size | A4 (now up to 200 % / 2.0 everywhere), GM4.2 | P1 Note 9 frame rule | GM6.1 (profile numbers) |
| S3 codes never cut | W7 | P2 Walkdown budgets | P5, P3 |
| Z1 synthetic data | Z1 | P3 no freeze over 1 s | P1 |
| Z2 screenshot edges | Z1 | P3a feedback in 100 ms (Advice) | F1 (now Block) |
| Z3 real findings reproduced | Z1 | P4 panning (Advice) | VIEW2 (now Block), P2 |
| G1 code fields | E2, N6 | G3 both orientations | AND4 (Plant: essential, applicability list) |
| G2 interruptions | D5, AND3, E5 | G4 thumb reach (Advice) | AND7 |

### 5.2 Old audit issues → new rules

Every open item stays tracked; they count as pre-existing fails from the adoption (section 9.2). Severity is set by
reviewers (section 9.5); the floor column is the least the rulebook allows (section 9.1). Open ones are labelled
`ux`.

| Issue | Was | Now | Severity (floor, until a reviewer rates it) |
|---|---|---|---|
| #365 (closed; follow-ups #414–#417) | G1 destructive actions | S1, S2, S5 | 2 |
| #366 (follow-ups #429–#431, #436) | G2 Back, Escape, typed input, interruptions | N2, S3, E5, D5, AND2, AND3 | 2 |
| #367 | G3 touch targets | A19, VIEW3 | 2 on main tasks |
| #368 | G4 text contrast | A1, A6 | 2 on main tasks |
| #369 | G5 highlights, focus rings, borders | A2, A23, VIEW1 | 2 on main tasks |
| #370 | G6 colour-only states | A5 | 2 on main tasks |
| #371 (closed) | G7 raw errors | W3 | — |
| #372 | G8 offline state and waiting count | ST3, F4 | 3 (proposed; no floor) |
| #373 | G9 pressed state, progress, freezes, field errors | F1, P1, E3, I1 | 3 (proposed; no floor) |
| #374 | G10 screen-reader names and announcements | A8, GNOME4, WIN2, AND5, GM7.3 | 2 on main tasks |
| #375 | G11 gesture and keyboard alternatives, tags without sight | A18, A20, A12, U1 | 2 on main tasks |
| #376 | G12 text size, zoom, narrow, landscape | A3, A4, L3, N3, AND4, AND1, V8 | 2 on main tasks |
| #377 | G13 Windows scaling, text size, dark, contrast themes, Alt keys | WIN1, A4, A7, A1, N3, L3 | 2 on main tasks |
| #378 | G14 identifiers cut or not copyable | I5, WD-I5, W7 | 3 (proposed; no floor) |
| #379 | G15 Arabic notes split codes | L2, WIN3 | 3 (proposed; no floor) |
| #380 | G16 reduced motion | A11 | 2 on main tasks |
| #381 | G17 Plant Settings off screen | N3, GM4.5, A18, L3 | 2 on main tasks |
| #382 (closed) | G18 Plant phone targets and text | A19, A3, A4, GM4.2 | — |
| #383 | G19 repeated decisions one at a time | S5 | 3 (proposed; no floor) |
| #384 | G20 names, code fields, counts, dates, empty screens | W1, C2, E2, W5, ST2, WD-E7, AND7 | 3 (proposed; no floor) |
| #412 | Plant: destructive spacing, codes on the screens, panels over the look stick, HUD backing | A19, A3, GM1.5, A6 | 2 on main tasks |
| #418 | Plant Workshop: no accessibility tree; Info not scrollable by keyboard or gamepad | A8, GM7.3, A18 | 2 on main tasks |
| #421 | Plant Workshop: the bench's refusal note off screen on phones | F1, GM3.2, W3 | 3 (proposed; no floor) |
| #422 | Plant manual reader buttons at 3.7:1 | A1 | 2 on main tasks |
| #423 | Plant alarm banner rows about 24 dp | A19, GM1.5 | 2 on main tasks |
| #424 (merged PR for #371) | errors in plain words | W3 | — |
| #425 | Plant on Android: drag on a control doesn't scroll | A18, A20, U1 | 2 on main tasks |
| #433 | Windows tabs: no selected state | A8, N1, WIN2, I1 | 2 on main tasks |

Filed at the adoption (2026-11-19): #437 Plant's "Restart in it" (S1, S2), #438 Plant evidence runs and the real
Godot user folder (Z1), #439 install warnings and steps (U1, T6), #440 the accessibility statement (T11), #441 server
updates' PASS/FAIL (S8), #447 Plant updates discard the saved run (S1, S4, GM5.2; severity 1), #448 removing a
device without a deliberate act (S2), #449 no forgot-password path (S9, U1), #443 lightning in fast-forward (A10, GM8.3), #446 Plant has no "Report a problem" (FIELD1); and the owner's decisions, #442.

The later audit issues (#391, #394–#397, #399–#404, #408, #428) keep their rules the same way: the old ID in their text
maps by the table in 5.1.

### 5.3 Old IDs in code and tools

About 50 comments in tests, tools and code cite the old policy's IDs ("UI-UX-POLICY T1, S1", "rule A5", "§3.3"; the
script `tools/ui_audit/plant_a5.py`). Several of those IDs now name different rules (S1, S2, A1, A5, T1). Read them
through the map in 5.1; they are renamed when the file is next touched, and `tools/ui_audit/` in phase 2.

## 6. Adoption

- **Phase 1** (2026-11-19, this page's PR): the hook-up in CLAUDE.md (the rulebook's Appendix G), the profiles, the
  review brief, the check of both products against the never-waivable set and U1, A1 and A5
  ([docs/ui-audit/2026-11-adoption.md](ui-audit/2026-11-adoption.md)), and the maps above.
- **Due dates:** Walkdown and Plant release by tags (they don't deploy on every merge), so the adoption issues follow
  the rulebook's 9.7 dates (severity 1 before the next release, severity 2 within two), not a burn-down plan.
- **Phase 2, by 2026-12-19:** the automated evidence (section 8.3) for each platform, built from `tools/ui_audit/`;
  every UI change tiered (section 8.2).
- **Phase 3, by 2027-02-19:** the first full audit under this rulebook (section 8.9) and the first round with real
  users (section 8.6). From then on the whole rulebook applies; until then Advice fails are backlog items only.
