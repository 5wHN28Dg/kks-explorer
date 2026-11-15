# UI audit 2026-11, pass 1: Walkdown Android (helper "vm")

## 1. What was run

- Build: main at 9eb5b09b (branch ui-audit-2026-11). Debug APK `./gradlew --no-daemon --max-workers=2 -PkksNativeJobs=3
  :app2:assembleDebug` (memjob 6, heavyslot), APK dated 2026-11-15 12:52, version 0.10.6. Server and importer from the same
  commit (built by the "desk" helper from the same checkout; byte-identical copies used).
- Emulator: AVD Pixel_9_Pro_XL (Android 16, x86_64 only, 1344 × 2992, density 480 = 3.0), started as CLAUDE.md says
  (own scope MemoryMax=8G, `-gpu guest`), under `vm.lock`, `ANDROID_SERIAL=emulator-5554` for every call. Demo-mode status bar (12:00) for the screenshots.
- Data (synthetic only): a fresh server with the sample sheet `importer/tests/vectors/kkp-sample.pdf`, 21 marked tags
  11LAB70AA501…521, 11LAB70AA501 with long "How to find it" text and the fixture note `مضخة التغذية 11LAB70AA501 تعمل`
  (Near and Notes), a member `تالا Member` with 20 open proposals. The phone joined as the manager.
- Driven with `android/app2/e2e/adbui.py` (uiautomator dump, input). Checked: setup, join form (wrong password, server
  down), main/drawing, search, tag panel (top, scrolled to the end, edit form), Procedures, Review, Learning, Manage and
  its pages (Approvals, History, People, Devices, Account, About, My proposals); light and dark (`cmd uimode night`),
  font_scale 1.3 and 2.0, landscape, soft keyboard (`show_ime_with_hard_keyboard 1`), Back, `am kill` of the
  backgrounded app, offline (server stopped), tap 13 dp and 22 dp beside a tag, long press on the code, `dumpsys gfxinfo`.
- Target sizes: every clickable/checkable/EditText node's bounds ÷ 3.0. Tags drawn on the sheet are left out of T1/T2
  (exempt; T4 covers them).
- Scripts (scratch, `~/kks-work/build/ui-audit/vm/`): `aud.py` (dump + screenshot + T1/T2/A2 report per screen),
  `serve.py` (the synthetic server above), `contrast.py` (WCAG ratio from a screenshot region), `run.sh`,
  `hold-emu.sh` (lock + emulator). Raw dumps, screenshots and reports: `~/kks-work/build/ui-audit/vm/android/`.
- Not run: TalkBack speech, sunlight, gloves (need a real phone, accepted limit); the photo editor (no camera picture on
  the emulator: judged from code); the Note 9.

## 2. Results

| Rule | Android |
|---|---|
| T1 | Fail (AND-6, AND-7) |
| T2 | Fail (AND-8) |
| T3 | N/A (desktop rule) |
| T4 | Fail, advice (AND-9) |
| T5 | Fail (AND-10) |
| R1 | Fail: in progress, branch tag-copy-sticky-batch (panel Close scrolls away: at the end of 11LAB70AA501's panel `Close` is not on screen) |
| R2 | Pass (Back closes panel, menu, Manage sub-page; on the first screen it leaves the app) [a] |
| R3 | Pass [b] |
| R4 | Fail, advice (AND-11) |
| C1 | Fail (AND-12); the tag panel's code: in progress, branch tag-copy-sticky-batch |
| C2 | Not checked [c] |
| C3 | Fail (AND-13) |
| B1 | Fail: in progress, branch tag-copy-sticky-batch (Approvals: 20 cards, Approve/Reject one by one); Review queue: no bulk either (same branch?) |
| B2 | Pass (Select tags: "Place for N codes", "x of N codes already have another value… replaced", Select.kt:185-190) |
| B3 | Not checked (no bulk approve on main) |
| K1 | Pass [d] |
| K2 | Fail (AND-14) |
| K3 | Pass (M3 outline #79747E on surface; focus not applicable to touch) |
| K4 | Fail (AND-15) |
| K5 | Pass (search field and panel are opaque Surfaces; floor line and legend sit above the drawing) |
| K6 | Pass [e] |
| K7 | Not checked (no recording) |
| S1 | Fail (AND-16) |
| S2 | Fail (AND-17) |
| S3 | Fail (AND-18) |
| F1 | Fail (AND-19) |
| F2 | Fail (AND-3) |
| F3 | Fail (AND-20) |
| F4 | Fail (AND-21) |
| F5 | Fail (AND-22) |
| F6 | Pass ("No procedures yet: they come with the plant data.", "Nothing to check…", "You have proposed nothing yet.") |
| D1 | Pass (photo delete, device remove, withdraw, revert, restore ask first, Photos.kt:152, Manage.kt:177/233/325) |
| D2 | Fail (AND-23) |
| D3 | Fail (AND-24) |
| D4 | N/A (no sign-out or leave on Android) |
| X1 | Fail (AND-25) [f] |
| X2 | N/A (full audit, no change) |
| X3 | Pass (Material 3, system Back, edge-to-edge with insets) |
| A1 | N/A (no keyboard-driven desktop UI; Android is touch) |
| A2 | Fail (AND-26) |
| A3 | Pass (every tag is a named virtual node "11LAB70AA501, verified" and reachable by search) |
| A4 | Pass (code: course figures read ANIMATOR_DURATION_SCALE, Learn.kt:1099; no other custom animation) |
| A5 | N/A (Plant) |
| L1 | Fail (AND-1) |
| L2 | Fail (AND-4, same as S2) |
| L3 | Pass (values with units come from user text; confidence shown with %) |
| L4 | Pass (yyyy-MM-dd HH:mm, Common.kt:100) |
| L5 | Fail, advice (AND-27) |
| P1 | N/A (Plant) |
| P2 | Not checked (no measurement run) |
| P3 | Pass on the emulator (gfxinfo over the whole session: 420 frames, slowest bucket 550 ms, none ≥ 1 s) |
| P3a | Fail, advice (gfxinfo: 70 % janky frames, 90th percentile 117 ms; emulator with guest GPU, so not representative) |
| P4 | Not checked (needs the Note 9) |
| Z1 | Pass (synthetic data only; the Learning tab's plant courses were not put in the repository) |
| Z2 | Pass (demo-mode status bar; the font-scale shots lost demo mode, only their bottom bar is published) |
| Z3 | N/A (nothing seen on real data) |
| G1 | Fail (AND-28) |
| G2 | Fail (AND-24) |
| G3 | Fail (AND-5) |
| G4 | Fail, advice (AND-29) |

Notes:
- [a] Back while editing the panel's fields closes the panel and drops the text: see D3 (AND-24).
- [b] With the soft keyboard on, the system pans the window: the field typed in stays visible (panel's Note for the
  approver at y 1703-1895 above the keyboard at 1895). The status bar, cut-outs and nav bar cover nothing (edge-to-edge
  insets). The app sets no `imePadding`, so the pan pushes the app bar off the top while typing.
- [c] Copy buttons exist only for the invite text and About's details (Manage.kt:434, About.kt:178); their clipboard
  bytes were not read.
- [d] Measured from screenshots, light: code #1D1B20 on #EEE5F5 13.9:1, labels #49454F on #E6E0E9 7.2:1, primary text
  buttons #6750A4 on #EEE5F5 5.3:1; dark: #E6E0E9/#282430 11.7:1, #CAC4D0/#36343B 7.2:1, #D0BCFF/#282430 8.9:1. Error text
  #B3261E (M3) on surface ≥ 5:1.
- [e] Every screen follows the system's dark setting (Root.kt:37). The drawing and its grey margin stay light unless
  "Dark drawings" is on (SheetView.kt:456): that is the existing dark rule, not a fail.
- [f] Only Android/Windows compared here (both trees dumped); the other platforms are the other helpers'.

## 3. Findings

**AND-1** L1 (Block). Tag panel, Notes / Near (view and edit form), also portrait and landscape. The fixture note
`مضخة التغذية 11LAB70AA501 تعمل` shows as `11 مضخة التغذيةLAB70AA501 تعمل`: the paragraph turns RTL from its first
Arabic letter and the digits `11` are moved away from `LAB70AA501`, so the KKS code reads wrong. Evidence:
shots/android-AND-1-arabic-note-splits-code.png; Panel.kt:55 (plain `Text`). Size SMALL: wrap KKS-shaped runs in user
text in LRI…PDI (U+2066/U+2069) before showing (a shared helper, also for the edit field's display), with a test on the
fixture string.

**AND-2** X1/F2 (Block; also a plain bug). Manage → History: every row's title is `#` and the line under it is
` ·  · added_tag 2ae1a060…` (no summary, no who, no when, raw entity and a 32-hex key). The app reads `n`, `summary`,
`note`, `by_name`, `at` (Manage.kt:245-246) but `/api/revisions` returns `rev`, `ts`, `full_name`, `entity`, `key`
(checked with curl on the test server). Windows has the same rows (WIN-6). Evidence:
shots/android-AND-2-history-rows-unreadable.png. Size SMALL: read the fields the API sends and word the entity
("Marked tag 11LAB70AA505"); test against the API's JSON.

**AND-3** F2 (Block). Join through a server, server down: `cannot reach HOST:1: failed to connect to /HOST
(port 1) from /PHONE (port 54970) after 15000ms: isConnected failed: ECONNREFUSED (Connection refused)`. Also
Manage → Account → Sync now shows `e.message` (Manage.kt:529). Wrong password is fine ("Wrong username or password.").
Evidence: the screenshot was not kept (it showed the emulator's network addresses; addresses replaced by HOST and PHONE above). Size SMALL: map connect failures to "Couldn't reach the server at
ADDRESS. Check the address and that this phone is on the plant's network." with the detail behind "Details".

**AND-4** S2/L2 (Block). Font scale 2.0: the bottom bar's "Procedures" is cut to "Procedur" (the label shrinks only down
to 0.7, Root.kt:169-170, then clips). At 1.3 every label fits but is shrunk to fit (smaller than the system asked).
Evidence: shots/android-AND-4-nav-labels-clipped-font2.png. Size SMALL: allow two lines or hide labels of unselected
items at large scales (Material's `alwaysShowLabel = false`) instead of shrinking.

**AND-5** G3 (Block). Landscape with a tag open: the panel keeps its portrait height (45 % of the portrait screen,
PanelSize, Panel.kt:81-82) and covers the whole drawing and the search field; it also overlaps the app bar's buttons by
4 dp (their bounds clipped to 44 dp). Evidence: shots/android-AND-5-landscape-panel-covers-drawing.png. Size SMALL:
compute the height from the current screen height and cap it (or a side sheet in landscape).

**AND-6** T1 (Block). The panel's drag handle is 448 × 36 dp (clickable, Panel.kt:88-95); with the soft keyboard up the
panel's Close was 61 × 42 dp and overlapped the handle (AND-8). Size SMALL: make the handle row 48 dp tall.

**AND-7** T1 (Block, code). Photo editor colour swatches are 36 × 36 dp (Photos.kt:296). Manage → Approvals'
Approve/Reject measured 40 dp tall at the list's bottom edge (cut by the bar, not a size fail). Size SMALL.

**AND-8** T2 (Block). History: Revert and Restore are adjacent TextButtons with 0 dp between them on every row
(manage-history: Revert 830-1027 px, Restore 1027-1248 px); with the keyboard up the panel's Close overlapped the drag
handle (1262-1334 px). Size SMALL: 8 dp spacing (or move Restore into a menu).

**AND-9** T4 (Advice). A tap 13 dp or 22 dp above 11LAB70AA501's box, or in the 5 dp gap between two boxes, picks
nothing at the default zoom. Hit slop is 8 screen px ≈ 2.7 dp (SheetView.kt:205-209). Size SMALL: 24 dp slop with
nearest-wins and a choice when two are equally near.

**AND-10** T5 (Block, code). Drag-only actions with no tap alternative: "Mark a missing tag" (drag a box,
Root.kt:436); in the photo editor, placing a box, arrow or circle (Photos.kt:311-335; zoom has buttons, pan does not);
panning the drawing (double tap zooms in, Fit resets; no pan buttons). Size LARGE (design: tap two corners, or
tap-to-place a default box then resize with buttons).

**AND-11** R4 (Advice). The panel's edit form: Save and Cancel come after the six fields and the approver note; with the
keyboard up they are below it. Size SMALL.

**AND-12** C1 (Block). Identifiers that can't be copied: device IDs in Devices and Account ("pmqBvEddxJw4I6eH…", cut at
16 characters, plain Text, Manage.kt:350, 481); the tag panel's code (no SelectionContainer: a long press shows no Copy;
in progress, branch tag-copy-sticky-batch); codes in Approvals/My proposals card titles (Manage.kt:119, 199). Size SMALL.

**AND-13** C3 (Block). Invite "Copy the text" says "Copied" (Manage.kt:434) without naming what, and Android 13+ already
shows its own clipboard preview (the emulator is Android 16), so the app adds a second one. "Copy all reports" and
report "Copy" say nothing (fine on 13+, nothing on Android 10-12). Size SMALL: confirm only below API 33, naming the
item.

**AND-14** K2 (Block). Light theme: the code parts in the panel (`11`, `LAB`, `AA`) are primary #6750A4 on
surfaceContainerHighest #E6E0E9 = 4.97:1 (< 7:1 for codes on phones). Dark is 7.2:1. Panel.kt:53-54. Size SMALL: use
onSurface for code text (keep primary for a non-text marker), or a darker primary.

**AND-15** K4 (Block). On the drawing, tag status (read automatically / needs checking / verified) and photo coverage
(both / equipment / plate / none) differ only by outline hue (SheetView.kt:508-516, 647-655); only "my proposed marks"
are dashed. Size LARGE (pattern or line style per state, the same on all clients).

**AND-16** S1 (Block). Text under 12 sp: the "by NAME, DATE" credit under each field and photo uses labelSmall = 11 sp
(Panel.kt:57, Photos.kt:161; measured 48 px / 3.0 ≈ 11 sp line); course image credits too (Learn.kt:643). Size SMALL:
labelMedium (12 sp) or bodySmall.

**AND-17** S2 (Block). See AND-4 (bottom bar) and AND-5. At 1.3 and 2.0 nothing else clipped or overlapped on Main,
panel, Manage, Approvals, Account (codes wrap in Approvals' card titles at 2.0, allowed).

**AND-18** S3 (Block). Device IDs are cut with "…" (AND-12) with no way to see the whole ID. Size SMALL.

**AND-19** F1 (Block). The app bar's Sync shows nothing while it runs (offline it took 2 s before "No other device
reached"; Root.kt:332-335): no progress or disabled state. Size SMALL.

**AND-20** F3 (Block). Offline (server stopped): Sync says "No other device reached", an edit says "Saved", and nothing
anywhere says the phone is offline or how many changes wait to be sent (Account shows only "Last sync …").
Size LARGE (a pending-changes count from the core, shown in the app bar or Account).

**AND-21** F4 (Block). Inline status/error texts have no live region: the join forms' messages (Setup.kt: `Text(msg)`),
the Account/Updates error lines. Snackbars are announced. Size SMALL: `semantics { liveRegion = Polite }` as Select.kt
already does.

**AND-22** F5 (Block). Field errors are shown away from the field: wrong password appears under Join, not at the
Password field, and focus stays on the button; the review form's invalid KKS goes to a snackbar (Panel.kt:216). Size
SMALL: `isError` + `supportingText` on the field, focus to it.

**AND-23** D2 (Block). The shared `Confirm` dialog (Common.kt:126-131) styles the confirming action as a plain
TextButton (not error colour) for Delete photo, Remove device, Withdraw, Revert, Restore. Names are right ("Delete",
"Remove"). Size SMALL: error-coloured confirm button.

**AND-24** D3/G2 (Block). (1) Tag panel → Edit, type into Building / area, Back: the keyboard closes, a second Back
closes the panel and the typed text is gone without a question (reopening shows the old value). (2) Type into the edit
form, Home, `am kill io.github.walkdown`, reopen: the app starts on the drawing with no panel, no open tag, no text.
State is in `remember`, not `rememberSaveable` (Root.kt:105-121, Panel.kt:84, 158). Rotation keeps state
(configChanges). Size LARGE (saveable UI state for sheet, tag, scroll and form drafts; a "discard changes?" question).

**AND-25** X1 (Block). Same things named differently on Android and Windows: Manage page "About Walkdown" vs
"About Walkdown…"; Account "This phone: ID…" vs "This device"; Manage sub-page back "‹ Manage" on both (fine); join
error wording differs (AND-3 vs Windows "The remote computer refused the network connection."). Size SMALL.

**AND-26** A2 (Block). Manage → Account: the "Sync on metered networks" Switch is a clickable node with no name
(Manage.kt:505-506: the label Text is a sibling, not merged). Size SMALL: `Modifier.toggleable` on the row.

**AND-27** L5 (Advice). "1 votes" (Manage.kt:216), "N tag(s) without a code left out" (Root.kt:407). Size SMALL.

**AND-28** G1 (Block). The main search field is a plain text field: IME inputType 0x8001 (text with auto-correct, no
caps; Root.kt:451); the review form's KKS fields (Panel.kt:210-211) and Mark a missing tag's KKS field (Root.kt:566)
have no KeyboardOptions either. Only Select's "Add codes" sets Characters + no autocorrect (Select.kt:151). Search
itself accepts `11 lab70 aa501` (found 11LAB70AA501). Size SMALL.

**AND-29** G4 (Advice). Search and the Sheets/Sync/More actions are at the top of the screen (y 180-528 px of 2992);
only the bottom bar is in thumb reach. Size LARGE (design).

## 4. Screenshots (in shots/)

android-AND-1-arabic-note-splits-code.png, android-AND-2-history-rows-unreadable.png,
android-AND-4-nav-labels-clipped-font2.png,
android-AND-5-landscape-panel-covers-drawing.png.
