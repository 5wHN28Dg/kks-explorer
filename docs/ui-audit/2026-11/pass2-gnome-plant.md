# UI/UX audit 2026-11, pass 2 (adversarial): Walkdown GNOME and Walkdown Plant

Auditor: pass 2, fresh. Policy: `docs/UI-UX-POLICY.md`. Code: main at 9eb5b09b (the audit checkout). Read-only: no
GNOME session, no Godot run, no emulator. Evidence is pass 1's raw outputs (`~/kks-work/build/ui-audit/desk/`), its
screenshots, and the code (file:line below is in the audit checkout). Small read-only scripts sampled the existing
screenshots and dumps (darkest glyph pixel against its background, as the policy asks).

Known and in progress elsewhere, not findings here: copy the KKS code from the tag panel, the panel heading and Close
staying in view, approve or reject several at once (branch tag-copy-sticky-batch); History rows showing "#" and
"<entity> <key>" (branch history-rows).

## Walkdown GNOME

### Corrections to pass 1

| Rule | Pass-1 cell | Pass-2 verdict | Evidence |
|---|---|---|---|
| D1 | Pass | **Fail** | Approvals' **Reject** acts at once, with no question and no Undo (`manage.nim:117-118`), and a rejection is final: the core then refuses any other decision with "already rejected" (`core/src/kks/api.nim:987`). **Pick this photo** rejects every other photo proposal of that equipment in one press, also without asking (`manage.nim:107-108`, toast "the other … were rejected"). These discard what members made (their photos). Pass 1 saw Reject and passed it because the item is "someone else's proposal"; the rule covers anything a user made. GNOME2-1 |
| D3 | Pass | **Fail** | Only the panel's own forms ask (`win.nim:110-127`). Every `AdwDialog` with typed input closes on Escape or its close button without a word: the photo editor (an annotated photo, its caption and note, `photos.nim:289-385`), Mark a missing tag (`mark.nim:15-56`), Place/Note for all (`multi.nim:314-324`, `formDialog` sets no `can-close`/`close-attempt`; grep for `can_close` in `apps/gnome` finds nothing). Account's Full name/Position fields are lost by the page's Back or Escape (`manage.nim:480-492`). GNOME2-2 |
| R2 | Pass (partial) | **Fail** | R2 says Escape never drops typed input without asking. The same dialogs as D3: Escape closes them and drops the photo, the drawn marks and the text. GNOME2-2 |
| S2 | Pass | **Fail** | At Large Text 1.25 the screenshots show clipped words: AdwEntryRow titles "Sync with an address (host:…" and "Internet relay (wss://…), e…" (`large-21-Account.png`), the device ID cut, and the header subtitle cut (pass 1 itself recorded the last under L2). S2 and L2 fail together. GNOME2-3 |
| L2 | Fail | Fail (wider) | Also at 100 %: Account's two AdwEntryRow titles are ellipsised, and they carry the only statement of the format (`host:port@device`, `wss://…`), so the user can't read how to fill the field (`light-21-Account.png`, `manage.nim:499,521`). GNOME2-3 |
| A2 | Pass | **Fail** | Photos are named "Open photo" or "Open photo: <caption>" (`photos.nim:782`): neither the tag nor the date, which A2 asks for. Pass 1's dumps had no photo, so nothing showed it. GNOME2-4 |
| F1 | Pass (partial) | **Fail** | Join through a server only greys the Join button while it enrolls and runs the whole first sync (`kks_explorer.nim:394-400`, `appstate.nim:445-466`): no "Joining…", nothing saying what it is doing, no progress, no Cancel, for a sync that brings the whole plant data. Save a bundle and Open a bundle run on the UI thread with no indicator (GNOME2-5). GNOME2-6 |
| F3 | Not checked | **Fail** (from code) | No count of changes waiting to be sent exists anywhere in `apps/gnome` or `apps/common` (grep for unsent/outbox/"not yet sent": none). Offline shows only as "no device reachable" inside the header subtitle, which is ellipsised at 1280 px ("Test plant · 1 device reacha…", `light-03-panel.png`), so with any real plant name the offline state itself is cut off (`kks_explorer.nim:108-126`). GNOME2-7 |
| F5 | Not checked | **Fail** (from code) | Field errors are toasts, not at the field, and the focus stays on the button: floor (`panel.nim:230-231`, `multi.nim:345-346`), an invalid KKS in the review form (`panel.nim:131-134`), Create the plant's four fields in one toast (`kks_explorer.nim:418-419`), the sync address format (`manage.nim:504-508`). The typed text is kept (that part passes). GNOME2-8 |
| B2 | N/A | **Fail** | There are bulk actions on main: **Pick this photo** rejects all the other photos (no count, no question, `manage.nim:107-108`) and **Clear removed** hides every removed device and person in one press without saying how many (`manage.nim:336-337`; display only, but undone one row at a time). GNOME2-1 |
| B1 | Fail | Fail (evidence corrected) | Pass 1 cited "removed devices (Hide per row)": Hide has a bulk form, "Clear removed" (`manage.nim:336`). What is one by one is **Remove** (revoke), which the rule names (`manage.nim:415`). Approvals and the review queue stand. |
| C2 | Not checked | **Fail** (from code) | The KKS heading copies exactly the code (`panel.nim:427`, label text = `t.full`), and the invite's Copy button copies the code alone (`join.nim:44-46`). But Account's "This device" subtitle is selectable and holds `device[0 ..< 16] & "… · sync port N"` (`manage.nim:497-498`): selecting it copies a cut ID with "…" and a label, never the identifier. Folds into GNOME-4. |
| C3 | Fail | Fail (evidence corrected) | Pass 1 said there is no Copy button on main. There are: the invite's "Copy the text" (`join.nim:44-46`) and Diagnostics' Copy / Copy all (`manage.nim:577-579`). Both toast just "Copied", never what was copied, which is the actual C3 fail. SMALL. |
| C1 | Fail | Fail (wider) | Besides device IDs and sheet names: device labels and usernames in Devices (`manage.nim:404`, `row` without `selectable`), Username in Account (`manage.nim:485`), KKS codes in search results and in the Equipment by system / review queue rows (row titles, not selectable). |
| X1 | Not checked | **Fail** (from code) | The same screen has different names: GNOME "Review queue" (`kks_explorer.nim:184-185`) where Android and Windows say "Readings to check" (`android/.../ui/Root.kt`, `apps/windows/src/kkswin/side.nim`), and GNOME's own Coverage says "Readings to review" (`coverage.nim:84`). Mark a tag: "Mark a tag the app missed" (GNOME button) and "Mark a missing tag" (the GNOME dialog, the web), with the photo button "Missing tag" on another client. GNOME2-9 |
| P3 | Not checked | **Fail** (from code) | Save a bundle builds, base64-encodes and gzips every plant data file and photo on the UI thread (`manage.nim:470-476` → `core/src/kks/bundle.nim:9-23`), and Open a bundle gunzips, parses and ingests on the UI thread (`kks_explorer.nim:430-436`). A real plant's data is about 120 MB: several seconds frozen. Not measured (synthetic data is tiny). GNOME2-5 |
| R1 | Pass (360 × 640 not checked) | Not checked, at risk | No `AdwBreakpoint` anywhere in `apps/gnome` (grep: none). The main window is a navigation split view (sidebar 260 px minimum, `kks_explorer.nim:368`) beside a header with nine buttons and an overlay split view whose panel is 320 px minimum (`kks_explorer.nim:348`), none of which collapse. A 360 × 640 window can't show that: either the window refuses to shrink or content is cut. Needs a run. GNOME2-10 |
| K1 | Fail | Fail (wider) | Also: the destructive button's red text on its own fill, "Remove this tag": 4.42:1 light, 4.26:1 dark (sampled from `light-03-panel.png`, `dark-03-panel.png`; 14.7 px bold is not large text). Empty AdwEntryRow titles (they act as the field's label): 3.0:1 light, 3.8:1 dark (`*-21-Account.png`). Lead, not confirmed: suggested-action buttons are white on Adwaita's default accent #3584e4, 3.8:1; no pass-1 screenshot shows one on screen. GNOME2-11 |
| K3 | Fail | Fail (wider) | Pass 1 reported only the review outline. From `viewer.nim:427-441,690-700` with α 0.75 on white: verified 2.6:1, auto 3.3, coverage "equipment only" amber 1.9, coverage "both" green 2.4, "plate only" 2.9; a **search hit** is shown by a yellow fill at α 0.28: 1.07:1 against the sheet. Selected (α 1): review amber 2.5, coverage amber 2.4. GNOME2-12 |
| F2 | Fail | Fail (wider) | Beyond the core's messages: join errors are "cannot reach HOST:PORT: " plus the socket's own exception text (`appstate.nim:456-457`); manage pages put a raw `e.msg` as the page's only content (`manage.nim:70,163,243,290,353,392,601`); photo queue failures show OS exception texts (`photos.nim:519-532`). An exception in any UI callback is only logged, so the user sees nothing at all (`gtk.nim:58-66`). |
| D1 (Withdraw) | (in Pass) | Fail (part of GNOME2-1) | "Withdraw this proposal?" has an empty body (`manage.nim:194`): it names neither the proposal nor what happens. |
| L4 | Pass | Advice: **Fail** | Diagnostics events show `MM-dd HH:mm` with no year (`manage.nim:625`): "11-12 14:05" reads as 11 Dec or 12 Nov. |
| T2 | Fail (History) | Fail, note | The History part of GNOME-3 (Revert and Restore 6 px apart, `light-21-History.json`) is not the history-rows branch's work (that fixes the "#" and "<entity> <key>" text); the crushed text part of GNOME-3 overlaps that branch. |

Pass 1's size estimates hold, with one exception: GNOME-1 is SMALL only for the app's own labels; the destructive-button
text (GNOME2-11) is libadwaita's own style, so a local override is SMALL but a real fix is upstream.

### New findings

**GNOME2-1 (D1, B2; Block) Rejections are final and unasked.** Where: Manage → Approvals. What: Reject discards a
member's proposal at once; Pick this photo rejects every other candidate photo at once; neither asks, says how many,
or offers Undo, and the core can't undo a rejection. Withdraw's question is empty. Evidence: `manage.nim:107-118,194`,
`core/src/kks/api.nim:986-990`. SMALL: `confirm(…, "Reject <what>?", "<who>'s <kind> is discarded; this can't be
undone.", "Reject", true, …)`; for Pick, "Reject the other N photos?"; a body for Withdraw.

**GNOME2-2 (D3, R2; Block) Escape drops typed input and drawn photos.** Where: Add a photo (editor), Mark a missing tag,
Place for all, Note for all, Account. What: AdwDialog closes on Escape or its close button with no question; an annotated
photo (camera or file), its caption, the mark's code and note, the for-all values go silently. Evidence: no
`adw_dialog_set_can_close`/`close-attempt` in `apps/gnome` (grep), `photos.nim:289-385`, `mark.nim:15-56`,
`multi.nim:314-324`. SMALL: one helper in `ui.nim` that sets `can-close` false while the dialog holds input and asks
"Discard the photo?" / "Discard what you typed?" on `close-attempt` (the panel's `ask` already exists).

**GNOME2-3 (L2, S2; Block) Field titles cut, at 100 % and Large Text.** Where: Manage → Account (Sync, relay). What:
the AdwEntryRow titles "Sync with an address (host:port@device)" and "Internet relay (wss://…), empty = off" are
ellipsised in the 280 px sidebar, so the format is never readable; at 1.25 more of the page is cut. Evidence:
`light-21-Account.png`, `large-21-Account.png`, `manage.nim:499,521`. SMALL: short titles ("Address", "Relay URL")
with the format in the group's description or an AdwActionRow subtitle that wraps.

**GNOME2-4 (A2; Block) Photos unnamed by tag and date.** Where: the panel's Photos. What: the photo button's name is
"Open photo[: caption]" (`photos.nim:782`); the by-line with the date is a separate label. SMALL: "Photo of
11LAB70AA500, 2026-11-15[, caption]".

**GNOME2-5 (P3; Block) Bundles freeze the window.** Where: Manage → Devices → Save a bundle; setup → Join with a file.
What: building or importing a bundle (all plant data and photos, base64 in gzip JSON) runs on the UI thread with no
indicator. Evidence: `manage.nim:470-476`, `kks_explorer.nim:430-436`, `core/src/kks/bundle.nim:9-40`. Not measured.
SMALL-to-LARGE: a worker thread (as the viewer's tiles) plus a "Saving the bundle…" line; LARGE if the core's bundle
must stream.

**GNOME2-6 (F1; Block) Joining shows nothing while it works.** Where: setup → Join through a server. What: the button
greys out; no text, no spinner, no progress of the first sync, no Cancel. Evidence: `kks_explorer.nim:394-400`. SMALL
for a status line and spinner ("Signing in…", "Getting the plant's data…"); progress needs the sync's counts (LARGE).

**GNOME2-7 (F3; Block) Offline is hidden, waiting changes uncounted.** Where: the sidebar's header subtitle. What: the
only offline signal is "no device reachable" at the end of an ellipsised subtitle; nothing counts this device's
changes no other device has yet (photos queued are counted, nothing else). Evidence: `kks_explorer.nim:108-126`,
`light-03-panel.png`. LARGE (the core must say which entries no peer has acknowledged; then a line or banner
"Offline · 3 changes wait to be sent").

**GNOME2-8 (F5; Block) Field errors as toasts.** Where: Edit form (Floor), review form (KKS), Create the plant, Account
(sync address), Place for all (Floor). What: a toast instead of a message at the field; the focus is not moved to the
field. Evidence: `panel.nim:131-134,230-231`, `kks_explorer.nim:418-419`, `manage.nim:504-508`, `multi.nim:345-346`.
SMALL: AdwEntryRow `error` style class plus a label under it, `gtk_widget_grab_focus` on the field.

**GNOME2-9 (X1; Block) The review queue has three names.** "Review queue" (GNOME sidebar), "Readings to review"
(GNOME Coverage), "Readings to check" (Android, Windows); "Mark a tag the app missed" / "Mark a missing tag" for one
action. Evidence: `kks_explorer.nim:184`, `coverage.nim:84`, `Root.kt`, `side.nim`. SMALL (pick one per thing across
clients).

**GNOME2-10 (R1, S2; Block, not checked) No narrow layout.** No `AdwBreakpoint` in the app; the split views never
collapse, so the 360 × 640 window size of R1 can't be honoured. Evidence: grep, `kks_explorer.nim:344-368`. LARGE
(breakpoints collapsing the sidebar and turning the panel into an overlay or bottom sheet). Needs a headless run at
360 × 640 to confirm what happens.

**GNOME2-11 (K1; Block) Destructive button text below 4.5:1.** "Remove this tag" (and every `destructive-action`
button with libadwaita's tinted fill): 4.42:1 light, 4.26:1 dark, sampled. Lead for suggested-action buttons (3.8:1
computed). SMALL locally (a CSS provider darkening the text or using the solid destructive fill); the root is
libadwaita's style.

**GNOME2-12 (K3; Block) Tag outlines and search hits below 3:1.** See the corrections table: most outline colours are
under 3:1 at their α 0.75, and the search-hit fill is 1.07:1. Evidence: `viewer.nim:427-441,690-700`; ratios computed
with pass 1's own `contrast.py` formula. SMALL for α 1 and darker hues on light sheets (as `lightenForDark` does for
dark ones, with a test like `tests/test_darkcolor.nim`); the hit needs an outline, not only a fill.

## Walkdown Plant (desktop and Android)

Not finished in this pass: the sub-audit of Plant (plant-desktop.md, plant-android.md) had not reported back when this
file was handed in. Pass 1's Plant results stand unreviewed until a pass-2 check of them is done.
