# UI and UX policy

Status: draft, 2026-11-15 (the user asked for it; in review, two passes, before first use).

This policy says what the user interface of both apps must do, and how a change is checked against it. It covers:

- **Walkdown:** the web client (index.html, admin.html, learning.html, course.html and the scripts they load), the
  GNOME app, the Windows app and the Android app;
- **Walkdown Plant:** its panels, cards, menus, HUD, map, drawings, manuals, control room screens and touch controls,
  on desktops and Android. The 3D world itself is covered only where a rule says so (performance, contrast of text over
  it, privacy).

Every rule below is a check with a pass or a fail. The audit (section 3) records the result of each rule on each
platform, and section 4 says which fails block a merge.

## 1. Who uses the apps, and where

The rules are adapted to these facts; when a rule is stricter than the public guideline it cites, this is why.

- **The main user is an I&C maintenance engineer on a walkdown:** standing in the plant, often wearing work gloves,
  sometimes in direct sun or at night, in noise (sound is never the only signal), with one hand free, interrupted
  often. Managers use the desktop apps and admin.html at a desk.
- **Offline is normal:** inside buildings and on the plant floor there is often no network. The apps must work
  offline and say clearly what is waiting to sync.
- **Phones:** from the Samsung Note 9 (Android 10, the oldest supported, 6.4") to current phones (Android 16).
  iPhones use the web client from the home screen (Safari 17+, docs/m6/REQUIREMENTS.md N8).
- **Dark mode** is used on night shifts and follows the system setting.
- **English UI only;** user content (notes, names, descriptions) may be Arabic or mixed Arabic and Latin
  (REQUIREMENTS.md N7).
- **Walkdown Plant** is a training simulator: keyboard and mouse, gamepad and touch (two sticks) are all first-class
  (apps/plant3d/README.md "Controls"), and the Note 9 must keep its frame-rate rule (decision 0041).

## 2. The rules

Each rule has a level:

- **Block:** a fail blocks the merge of the change that causes it (section 4).
- **Advice:** a fail is recorded, and filed as an issue if it matters, but does not block.

Units: **dp** is Android's density-independent pixel (1 dp = 1/160 inch); on the web 1 CSS px at a phone viewport
counts as 1 dp; on a desktop, sizes are in the platform's logical pixels at 100 % scaling. For Plant, convert screen
pixels to dp with the screen's density: dp = px × 160 / dpi. On a phone use `DisplayServer.screen_get_dpi()`; for
the phone layout rendered on a desktop (`--resolution 2960x1440`) use the Note 9's 516 dpi, since the desktop reports
its own.

"Phone" means Android, the web client at a viewport narrower than 600 CSS px, and Plant on Android.

### 2.1 Touch and pointer targets

Sources: Android "Make apps more accessible" (48 × 48 dp,
https://developer.android.com/guide/topics/ui/accessibility/apps); WCAG 2.2 2.5.8 Target Size (Minimum)
(https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html); Windows "Targeting" (7.5 mm, 40 × 40 epx,
larger for frequent or risky targets, https://learn.microsoft.com/en-us/windows/apps/develop/input/guidelines-for-targeting);
Apple HIG (44 × 44 pt, https://developer.apple.com/design/human-interface-guidelines/accessibility); GNOME HIG
"Pointer and touch" (https://developer.gnome.org/hig/guidelines/pointer-touch.html; it gives no size, so the numbers
come from the others).

- **T1 (Block) Phone targets are at least 48 × 48 dp.** Every button, link outside running text, list row, checkbox,
  switch, tab and field on a phone has a hit area of at least 48 × 48 dp (the visible shape may be smaller if the hit
  area around it is not). Exceptions: links inside a paragraph of text; the drawing and the 3D view themselves
  (section T4 covers what is tapped on them).
  - Why: gloves. 48 dp is Android's own minimum; a gloved fingertip is wider than a bare one.
  - Check: Android, the bounds of every clickable node in `uiautomator dump`, divided by the density; web, every
    focusable or clickable element's `getBoundingClientRect()` at a 412 × 915 viewport; Plant, every `Control` that
    takes input, in the phone layout (`--resolution 2960x1440`, the phone scale), converted to dp.
- **T2 (Block) Targets don't overlap, and destructive ones keep their distance.** Two hit areas never overlap. A
  button that deletes, discards, removes or signs out has at least 8 dp of empty space (phone) or 8 px (desktop)
  between its hit area and any other target's.
  - Why: a gloved tap that lands between two buttons must not do the destructive one.
  - Check: the same bounds as T1.
- **T3 (Block) Desktop targets are at least 24 × 24 px.** On GNOME, Windows, the web at desktop width and Plant on a
  desktop, every target is at least 24 × 24 logical px, or, as WCAG 2.5.8's spacing exception says, a 24 px circle
  centred on it does not intersect another target or another such circle.
  - Check: AT-SPI extents (GNOME), UIA BoundingRectangle (Windows), `getBoundingClientRect()` at 1280 × 800 (web),
    `Control` rects (Plant).
- **T4 (Advice) Things tapped on the drawing or in the 3D view.** A tap within 24 dp of a tag on the drawing, or of a
  part in Plant, picks it when nothing else is nearer; when two are equally near, the app asks or zooms instead of
  guessing.
  - Check: tap beside a tag on the emulator at the default zoom (e2e harness `tap` at an offset).
- **T5 (Block) Every gesture has a simple alternative.** Anything done by dragging, pinching, two-finger turning or
  long-pressing can also be done with single taps or clicks (buttons, a menu) and with the keyboard (WCAG 2.5.1
  Pointer Gestures, 2.5.7 Dragging Movements: https://www.w3.org/TR/WCAG22/#pointer-gestures,
  https://www.w3.org/TR/WCAG22/#dragging-movements).
  - Why: one gloved hand can't pinch reliably; a long press is undiscoverable.
  - Check: list the gestures of each screen and find each one's alternative.

### 2.2 Controls that stay reachable

Sources: Material 3 top app bars (https://m3.material.io/components/app-bars/guidelines); GNOME HIG header bars
(https://developer.gnome.org/hig/patterns/containers/header-bars.html); WCAG 2.4.11 Focus Not Obscured
(https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html).

- **R1 (Block) Close and back never scroll away.** Every panel, dialog, card, sheet and full-screen view that has a
  Close, Back, Cancel or Done control keeps it visible, in the same place, however far its content is scrolled and at
  every supported window size (phone portrait and landscape; desktop windows down to 360 × 640 logical px).
  - Why: on a long tag card, the user must not scroll back up to leave it.
  - Check: open the longest synthetic example of each panel, scroll to the end, and see that the control is visible
    and where it was (screenshot before and after; the control's bounds in the accessibility tree are unchanged).
- **R2 (Block) Back and Escape close the top layer.** Android's system Back (and its back gesture), Escape on
  desktops and the web, and B on a gamepad (Plant) close the topmost panel or dialog first. They never leave the app,
  or drop typed input, without asking (see D3). The web client opened from an iPhone's home screen has no browser Back
  button, so every web panel has its own Back or Close control.
  - Check: press Back or Escape on each panel in the e2e harness; the panel under it, not the app, is shown next.
- **R3 (Block) Nothing hides under bars, cut-outs, the keyboard or the touch sticks.** No control or text is covered by
  the status bar, the navigation bar, a display cut-out, the on-screen keyboard (the field being typed in stays
  visible) or, in Plant, the touch sticks. On the web this means honouring the safe areas
  (`viewport-fit=cover` with `env(safe-area-inset-*)` padding, or not using `viewport-fit=cover`).
  - Check: screenshots on the emulator in both orientations with the keyboard open on each form; Plant's phone layout
    with touch controls shown.
- **R4 (Advice) A form's Save or Send is in a bar that stays visible, or directly after the last field** (never after
  an unbounded list).

### 2.3 Identifiers can be copied

- **C1 (Block) Every identifier on screen can be copied.** KKS codes, sheet names and numbers, device names and IDs,
  fingerprints, invite and sign-up codes, version numbers and error references can be selected and copied by the
  platform's normal means, or have a Copy button beside them:
  - web: the text is selectable (no `user-select: none` on it) or a Copy button;
  - GNOME: a selectable `GtkLabel` or a Copy button;
  - Windows: a read-only edit control, a Copy item in the context menu, or a Copy button;
  - Android: `SelectionContainer` or a Copy button;
  - Plant: a Copy button (Godot labels are not selectable by touch).
  - Why: an engineer pastes codes into work orders, the CMMS and messages; retyping `11LAB70AA501` is where mistakes
    come from.
  - Check: on each platform, copy each kind of identifier and paste it into a text field of the same app (search),
    then read that field through the accessibility tree; on the web `navigator.clipboard.readText()` with the
    permission granted in Playwright. (Android 10 and later let only the foreground app read the clipboard, and the
    headless GNOME session and an SSH session in the Windows VM may not share the desktop's clipboard: pasting
    inside the app avoids both.)
- **C2 (Block) What is copied is exactly the identifier.** No label ("KKS: "), no surrounding spaces, no zero-width
  or direction marks, no thin spaces inside the code.
  - Check: the clipboard's bytes, as in C1.
- **C3 (Block) Copying says so.** A copy shows a short confirmation that names what was copied ("Copied
  11LAB70AA501"), except where the platform already shows one (Android 13 and later show their own clipboard
  preview: then the app adds none, to avoid two).

### 2.4 Bulk actions for repeated decisions

Source: Material 3 lists and selection (https://m3.material.io/components/lists/guidelines); GNOME HIG selection
mode (https://developer.gnome.org/hig/patterns/containers/selection-mode.html).

- **B1 (Block) A decision made item by item can also be made for many.** Wherever a list asks the user for the same
  decision on each item (accept or deny tags in a review queue, approve or refuse sign-ups, accept marked tags,
  remove photos, revoke devices), and the list can hold more than 5 items, the user can select several (or all that
  match a filter) and decide once. The button says the count ("Accept 12 tags").
  - Why: a sheet's review queue held 79 items; approving them one by one wastes a shift and invites mistakes.
  - Check: put 20 synthetic items in each such list and decide all of them in at most 4 actions.
- **B2 (Block) A bulk action can be checked before it runs.** A bulk action that changes or removes data shows how
  many items it will change, and D1 applies to it as a whole (one undo, or one confirmation, for the whole batch).
- **B3 (Advice) After a bulk action the list keeps its place** and says what happened ("12 accepted").

### 2.5 Contrast and colour

Sources: WCAG 2.2 1.4.1 Use of Color, 1.4.3 Contrast (Minimum), 1.4.6 Contrast (Enhanced), 1.4.11 Non-text Contrast
(https://www.w3.org/TR/WCAG22/#distinguishable); GNOME HIG "UI styling" (https://developer.gnome.org/hig/guidelines/ui-styling.html);
Windows contrast themes (https://learn.microsoft.com/en-us/windows/apps/design/accessibility/high-contrast-themes).

- **K1 (Block) Text contrast at least 4.5:1** (3:1 for text at least 18.66 px bold or 24 px regular) against what is
  behind it, in the light theme, the dark theme and the platform's high-contrast mode.
  - Check: sample the text and background colours from screenshots (or computed styles on the web) and compute the
    WCAG ratio (the audit's helper scripts, once added, are listed in §3.3).
- **K2 (Block) On phones, codes, values and body text reach 7:1.** In both the light and the dark theme, KKS codes,
  measured values and the main text of cards and lists on a phone have at least 7:1 (WCAG 1.4.6, the AAA level).
  Secondary text (hints, timestamps) keeps 4.5:1.
  - Why: direct sun on a phone screen washes out anything weaker; 7:1 is what survives glare.
- **K3 (Block) Controls, focus rings and highlights reach 3:1.** Borders of fields and buttons that have no fill,
  icons that are the only label of a control, the keyboard focus indicator, a selected tag's highlight on the drawing
  and chart lines have at least 3:1 against what is next to them (WCAG 1.4.11).
- **K4 (Block) Colour is never the only signal.** A state shown by colour (an alarm's priority, normally closed, a
  selected item, an error field, sync failed, a correct or wrong answer in a course) also has a word, an icon, a
  shape or a pattern. The drawing's highlights differ in outline or fill pattern too, not only in hue.
  - Why: about 1 in 12 men has a red-green colour vision deficiency, and glare flattens hues.
  - Check: a greyscale screenshot of each screen; every state is still told apart.
- **K5 (Block) Text over pictures, drawings or the 3D view has its own backing.** Labels on photos, on the drawing
  and over Plant's 3D view sit on a panel that gives K1 against the brightest and darkest scene behind them (Plant:
  check over the sky at noon and at night).
- **K6 (Block) Dark mode is complete in Walkdown.** Every Walkdown screen follows the system's dark setting (web:
  `prefers-color-scheme`), meets K1 to K5 there, and shows no white flash when a screen or dialog opens. Drawings and
  course figures in dark follow the existing dark rules (tests/web/test_dark.py and its vectors).
  Plant's panels are dark by design; they meet K1 to K5 as they are.

### 2.6 Text size and scaling

Sources: WCAG 2.2 1.4.4 Resize Text, 1.4.10 Reflow (https://www.w3.org/TR/WCAG22/#distinguishable);
Material 3 type scale (https://m3.material.io/styles/typography/type-scale-tokens); Windows text scaling
(https://learn.microsoft.com/en-us/windows/apps/develop/input/text-scaling).

- **S1 (Block) Minimum text sizes.** On phones, body text, list rows and codes are at least 14 sp, and no text is
  under 12 sp. On desktops, body text uses the platform's default UI font size (GNOME's interface font, Windows'
  message font, the browser's default 16 px on the web) and nothing is under 11 px (web and GNOME, at 100 % scaling)
  or 8 pt Segoe UI (Windows). In Plant, the phone limits apply in dp, measured on screen; on desktops nothing is under
  14 px at 1600 × 900. Text fields on the web are at least 16 px, or iOS Safari zooms the page when one is focused.
- **S2 (Block) The system's text size is followed.**
  - Android: at font scale 1.3 (the largest stock Android 10 offers; `adb shell settings put system font_scale 1.3`)
    every screen still shows all its text and controls, with no clipped words and no overlap; at 2.0 (Android 14 and
    later, the emulator's image) text may need scrolling, but nothing is clipped or overlapping.
  - Web: at 200 % browser zoom and at 320 CSS px width, nothing is lost and nothing needs scrolling in two directions
    except the drawing and wide tables (WCAG 1.4.4, 1.4.10).
  - GNOME: with Large Text on (text scaling 1.25), and Windows with "Text size" at 150 %, the same holds.
  - Plant: Godot does not follow the system's text size; Plant offers its own text size setting covering at least
    100 % to 150 %, and the same holds at 150 %.
- **S3 (Block) Codes are never cut short.** A KKS code or other identifier is never ellipsised or clipped: it wraps,
  scrolls or makes its row taller. (Descriptions may be ellipsised if the full text is one tap away.)

### 2.7 Feedback, loading and errors in plain words

Sources: WCAG 2.2 3.3.1 Error Identification, 3.3.3 Error Suggestion, 4.1.3 Status Messages
(https://www.w3.org/TR/WCAG22/#input-assistance, https://www.w3.org/TR/WCAG22/#status-messages); GNOME HIG
"Writing style" (https://developer.gnome.org/hig/guidelines/writing-style.html).

- **F1 (Block) Every action shows that it was taken.** A pressed control changes at once (within 100 ms). Anything
  that takes over 1 s shows that it is working and on what ("Importing sheet 3 of 7"); over 10 s it shows progress
  where it can be known, and the user can leave it or cancel it.
- **F2 (Block) Errors in plain words.** An error says what went wrong, what it means for the user's work, and what to
  do next, in everyday words ("Couldn't reach the server. Your note is saved on this phone and will be sent when you're
  back online."). Never a raw exception, stack trace, HTTP status, errno or protocol name as the message; technical
  detail may follow behind "Details" or in diagnostics.
  - Check: trigger each error the harness can (server down, wrong password, bad invite, full storage where possible)
    and read the message.
- **F3 (Block) Offline is a state, not an error.** Without a network the app says it's offline, keeps everything that
  works offline working, and shows how many changes wait to be sent. No blank screen and no spinner that never ends.
  - Check: the e2e harnesses' offline tests (web test_web_offline; the apps with the server stopped).
- **F4 (Block) Status messages reach screen readers without moving the focus** (WCAG 4.1.3): web `role="status"` or
  `aria-live`; Android Compose `semantics { liveRegion = LiveRegionMode.Polite }` (`announceForAccessibility` is
  deprecated from Android 16); GNOME `gtk_accessible_announce`; Windows a UIA notification or LiveRegionChanged event.
  Plant on desktops: a live-region status line through Godot's accessibility API (A5); Plant on Android is exempt
  while Godot has no screen-reader support there.
- **F5 (Block) A field error is shown at the field and keeps what was typed.** The message names the field, the input
  is not cleared, and the focus goes to the first field in error.
- **F6 (Advice) Empty screens say why and what to do** ("No photos yet. Take one with the camera button.").

### 2.8 Destructive actions and undo

Sources: Material 3 dialogs and snackbars (https://m3.material.io/components/dialogs/guidelines,
https://m3.material.io/components/snackbar/guidelines); GNOME HIG dialogs
(https://developer.gnome.org/hig/patterns/feedback/dialogs.html); WCAG 3.3.4 Error Prevention.

- **D1 (Block) Losing data is either undoable or confirmed.** Deleting or discarding anything the user made (a note, a
  photo, a mark, a link, a draft) offers Undo for at least 5 s (longer when the system's accessibility timeout asks
  for it, and until dismissed while a screen reader is on, as Material's snackbar with an action does on Android), or
  asks first in a dialog that names the thing and the consequence. Actions that can't be undone at all (removing a device, which wipes it; signing out with unsent
  changes; resetting a password; anything with the root key) always ask first; Undo alone is not enough for them.
- **D2 (Block) The safe choice is the default.** In such a dialog the confirming button names the action ("Remove
  photo", never "OK" or "Yes"), is styled as destructive (GNOME `destructive-action`, Material's error colour, the
  web's destructive class), is not the default button, and the focus starts on Cancel. Enter or a double tap never
  confirms a destructive action by accident. (Plant's permit lock warning already works this way: docs/PLANT3D.md
  §15.6.)
- **D3 (Block) Typed input is never lost silently.** Leaving a form, Back, closing the window or the app being
  stopped by the system (Android process death) keeps the typed text as a draft or asks first.
  - Check: type into each form, then Back, close and (Android) `am kill` the backgrounded app; the text is still there
    or a question was asked.
- **D4 (Block) Signing out says what would be lost.** If signing out or leaving the plant discards changes not yet
  sent, the question says how many.

### 2.9 Consistency across platforms

- **X1 (Block) The same thing has the same name everywhere.** A feature, a screen, a button and a state use the same
  words on the web, GNOME, Windows and Android (and in Plant, where Plant shows the same thing, such as a KKS code's
  meaning). Platform conventions decide placement and look (header bar, menu bar, top app bar, Back), never the
  words.
  - Check: list the visible labels of the changed screen on each platform (from the accessibility trees) and compare.
- **X2 (Block) A feature is on every Walkdown client or tracked.** A change that adds or changes a user-visible
  feature on one Walkdown client does the same on the others, or the PR links an issue for each one left out and
  docs/m6/CAPABILITIES.md says so.
- **X3 (Block) Each platform's own conventions are followed,** checked as these points. GNOME: a header bar with the
  window's actions, libadwaita dialogs and toasts, destructive and suggested button styles. Windows: standard Win32
  controls, Alt-key accelerators on menus and buttons, the system's colours in contrast themes. Android: Material 3
  components, system Back, edge-to-edge insets handled. Web: native HTML controls (`button`, `input`, `select`, `a`)
  before custom ones. Plant: every action of a panel works by touch, gamepad and keyboard (README "Controls").

### 2.10 Keyboard and screen-reader access

Sources: WCAG 2.2 2.1.1 Keyboard, 2.1.2 No Keyboard Trap, 2.4.3 Focus Order, 2.4.7 Focus Visible, 4.1.2 Name, Role,
Value (https://www.w3.org/TR/WCAG22/); GNOME HIG accessibility and keyboard
(https://developer.gnome.org/hig/guidelines/accessibility.html, https://developer.gnome.org/hig/guidelines/keyboard.html);
Windows keyboard and UIA (https://learn.microsoft.com/en-us/windows/apps/design/accessibility/keyboard-accessibility,
https://learn.microsoft.com/en-us/windows/win32/winauto/entry-uiauto-win32); Android TalkBack testing
(https://developer.android.com/guide/topics/ui/accessibility/testing).

- **A1 (Block) Everything works from the keyboard** on the web, GNOME, Windows and Plant on a desktop (Plant: from a
  gamepad too). The focus order follows the reading order, the focus is always visible (K3) and never hidden under
  another layer, and nothing traps it. The drawing pans with the arrow keys and zooms with + and −.
  - Check: drive each changed screen with Tab, arrows, Enter, Space and Escape only (Playwright `keyboard`, AT-SPI
    and UIA actions in the existing harnesses, Plant's `test_inputs` and `test_gamepad_switch`).
- **A2 (Block) Every control has a name, a role and its state** in the platform's accessibility tree: web semantic
  HTML or ARIA; GNOME `GtkAccessible` (AT-SPI); Windows UIA (or MSAA through UIA); Android `contentDescription` or
  semantics (TalkBack). Icon-only buttons are named by what they do; photos are named by their tag and date;
  decoration is hidden from the tree.
  - Check: the accessibility tree dump of each changed screen (Playwright `ariaSnapshot()`, `atspi.walk`, the UIA
    driver's tree, `uiautomator dump` content descriptions) has no unnamed control.
- **A3 (Block) The drawing is usable without seeing it.** Each sheet's tags are also reachable as a list (search or the
  sheet's tag list) that opens the same card, so a screen-reader or keyboard user can reach every tag.
- **A4 (Block) Motion follows the system.** With reduced motion on (web `prefers-reduced-motion`, GNOME
  `gtk-enable-animations` off, Windows "Animation effects" off, Android "Remove animations"; Plant's own "Reduced
  motion"), nothing slides, zooms or sways that isn't needed to understand the change. Nothing flashes more than 3
  times a second (WCAG 2.3.1).
- **A5 (Block) Plant's panels reach screen readers on desktops.** Godot (since 4.5) exposes `Control`s through
  AccessKit on Windows and Linux; every Plant button, card and menu item has an accessible name (its text, or
  `Control.accessibility_name` for an icon). The 3D world is exempt (it has no text a reader could use beyond what the
  cards show). Plant on Android is exempt while Godot has no screen-reader support there.
  - Check: the AT-SPI tree of Plant run in the GNOME headless session (`atspi.walk`).

### 2.11 Layouts that survive other text

The UI is English only, but user content may be Arabic or mixed (REQUIREMENTS.md N7).

- **L1 (Block) Mixed right-to-left and left-to-right text shows in the right order.** User text is shown with
  automatic direction, and a KKS code inside Arabic text keeps its characters in order. Web: `dir="auto"` or `<bdi>`.
  GTK (Pango) finds the direction from the first strong character itself, and Compose's default text direction
  (`ContentOrLtr`) does too. Win32 edit controls and DirectWrite do not: the Windows app sets the reading direction
  from the text's first strong character (`WS_EX_RTLREADING`, `DWRITE_READING_DIRECTION_RIGHT_TO_LEFT`).
  - Check: the synthetic fixture note `مضخة التغذية 11LAB70AA501 تعمل` (and a name in Arabic) on each platform's
    screenshot.
- **L2 (Block) Labels can grow.** No control or label has a width that only fits today's English: at the S2 text
  sizes (1.3 on Android, 200 % on the web, Large Text on GNOME, 150 % on Windows and in Plant), which make every label
  at least 25 % wider, labels wrap or their container grows; nothing is clipped or overlaps.
- **L3 (Block) Every value has its unit,** and a value and its unit stay on one line.
- **L4 (Advice) Dates and times are unambiguous:** 2026-11-15 14:05 or "15 Nov 2026", 24-hour; never 11/12/26.
- **L5 (Advice) Counts are grammatical:** "1 tag", "2 tags".

### 2.12 Performance budgets

- **P1 (Block) Plant keeps the Note 9's frame rule.** In normal play on the Note 9's tier, 99.9 % of frames are shown
  at 30 fps or better by Android's present times (decision 0041); a change to a panel, the HUD or the control room
  screens is measured with the walk that shows it (apps/plant3d/README.md, `phone/frames.sh`). Fast-forward may drop
  frames on a phone (docs/PLANT3D.md §7.9).
- **P2 (Block) Walkdown keeps its measured budgets:** startup, memory and size within the regression rules of
  docs/m6/MEASUREMENTS.md; the web client's download within `web-size.json` (CI's `web-size` job).
- **P3 (Block) Input feedback within 100 ms, nothing frozen over 1 s.** No interaction blocks the UI thread for more
  than 100 ms before something changes on screen (F1); longer work runs off the UI thread (Android: decode on IO; web:
  workers; GNOME and Windows: worker threads, as the viewer does).
  - Check: web `PerformanceObserver` long tasks during the changed interaction; Android `dumpsys gfxinfo` janky frames;
    desktop timings in the e2e logs.
- **P4 (Advice) Panning the drawing holds the display's frame rate** on the Note 9 (REQUIREMENTS.md N3).

### 2.13 No plant data in screenshots

- **Z1 (Block) Audits run on synthetic data only.** Screenshots, recordings, accessibility-tree dumps and notes that go
  into the repository, the wiki, issues or PRs come only from the test fixtures (e2e plant data, the generic Plant
  content). They never show the real plant's name, drawings, KKS codes taken from its drawings, photos, people's
  names, device names, server or relay addresses, IP addresses, or invite and QR codes that carry real keys.
- **Z2 (Block) Look at the edges before publishing a screenshot:** window titles, the address bar, the status bar
  (Android: use demo mode, `adb shell settings put global sysui_demo_allowed 1` and `am broadcast -a
  com.android.systemui.demo -e command enter`), notifications and file paths.
- **Z3 (Block) A finding seen on real data is reproduced on synthetic data before it is filed.**

### 2.14 Field use

- **G1 (Block) Code fields don't fight the user.** Fields where a KKS code is typed turn off autocorrect and spelling
  suggestions and start in capitals (web `autocapitalize="characters" autocorrect="off" spellcheck="false"`; Compose
  `KeyboardOptions(capitalization = Characters, autoCorrectEnabled = false)`), and search accepts a code in any case
  and with or without spaces (`11 lab70 aa501` finds `11LAB70AA501`).
- **G2 (Block) An interruption loses nothing.** Turning the phone, switching apps, or Android stopping the app in the
  background brings the user back to the same sheet, tag and scroll position, with typed text kept (D3).
- **G3 (Block) Walkdown works in both orientations** on phones (WCAG 1.3.4). Plant's 3D view is landscape only, which
  is essential to its two-stick controls; its menus before the plant loads follow the phone.
- **G4 (Advice) The main field actions are within a thumb's reach:** search, open the tag, photo and note sit in the
  lower two thirds of a phone screen or in a bottom bar.

## 3. The audit

### 3.1 When

An audit is due for every change that touches what either app shows or how it is used:

- Walkdown web: `*.html`, `common.js`, `tiles.js`, `course.js`, `course-bridge.js`, any stylesheet, `sw.js` when it
  changes what is shown offline;
- GNOME: `apps/gnome/`; Windows: `apps/windows/`; shared desktop code in `apps/common/` that makes or words UI;
- Android: `android/app2/src/main/` (Kotlin UI, resources, the manifest's screens);
- Plant: `apps/plant3d/ui/`, `apps/plant3d/app/` (hud, map, about, settings, controls), `apps/plant3d/workshop/`
  views, any `.tscn` with `Control` nodes, and the content texts the UI shows (`tools/plant3d/manual_texts/`);
- course content only when it changes a figure or layout, not its prose.

Changes to tests, docs, the core, the server's API, the importer or the relay need no audit unless they change
text or behaviour that a user sees (an error message from the core is UI).

A **full audit** (every rule, every platform, both apps) is done once after this policy is adopted (its results go
in `docs/ui-audit/2026-11.md`), and again
before each release that changed UI on more than one platform.

### 3.2 Who

Two fresh subagents, one after the other, neither told what the author thinks:

1. **Pass 1, blind audit:** given this policy, the change (task text and diff) and the evidence pack (3.3). It records
   a result for every rule on every platform the change touches.
2. **Pass 2, adversarial audit:** given the same, plus pass 1's table, it tries to make the change fail: other screen
   sizes, the largest text size, dark mode, keyboard only, the longest synthetic content, Arabic text, offline.

Auditors stay read-only in the repository. They may ask the author for more evidence; when the machine's memory rules
allow it they may run the evidence scripts themselves (one at a time, through the memory-capped job runner).

### 3.3 The evidence pack

Made by the author from synthetic data only (Z1), before and after the change, for the screens the change touches on
each platform whose code it changes (a change to `apps/common/` touches GNOME and Windows). A change that only rewords
text needs screenshots of the changed screens on one platform and the list of the changed strings on every platform
where they show (for X1, F2 and S3); no trees or sizes.


| Platform | How | Screenshots | Accessibility tree | Sizes and colours |
|---|---|---|---|---|
| Web (Chromium, WebKit, Firefox) | Playwright with `KKS_SERVER` (the web e2e's setup) | 412 × 915 and 1280 × 800, light and dark, 200 % zoom, 320 px width | `locator.ariaSnapshot()` | `getBoundingClientRect()` of every target; computed colours |
| GNOME | `apps/gnome/e2e/headless.sh` (never the user's desktop), one run at a time machine-wide (the local agent rules' GNOME e2e lock) | `KKS_SHOT_ON_SIGNAL`, light, dark, Large Text | `atspi.walk` dump | AT-SPI extents |
| Windows | `apps/windows/e2e/test_windows.py` in kks-win10 or kks-win11, one VM at a time under `vm.lock` | `virsh screenshot`, light, dark, a contrast theme, 150 % text | the UIA driver's tree | UIA BoundingRectangle |
| Android | the emulator under `vm.lock` (never with a VM); the e2e harness's `adbui` | `screencap`, demo-mode status bar, light, dark, largest font scale, landscape | `uiautomator dump` | node bounds ÷ density |
| Plant desktop | `tools/plant3d/bench/offscreen.sh` with `tests/ui_shots.gd`, `tests/mimic_shots.gd` | 1600 × 900 and the phone layout (`--resolution 2960x1440`) | AT-SPI dump of Plant run in the headless session (A5) | `Control` rects |
| Plant Android | the emulator under `vm.lock`; the Note 9 only when the user's phone time window allows (local agent rules) | `screencap` | — | P1's frame walk |

What can't be checked on an emulator or headless (real TalkBack speech, sunlight, gloves) is checked on a real phone
when the change is about it, and otherwise recorded as "not checked: needs a real phone". Never on the user's Honor
except Walkdown Plant (`io.github.walkdown.plant`).

### 3.4 How results are recorded

For a change: a table in the PR (a comment from each pass), one row per rule that applies, one column per platform the
change touches, each cell one of:

- **Pass;**
- **Fail** with where (screen, platform) and what, and the issue or fix;
- **Pre-existing fail** (already on main; issue linked);
- **N/A** with why;
- **Not checked** with why.

For a full audit: the same table for every rule and platform, in `docs/ui-audit/YYYY-MM.md`, with the screenshots
beside it (synthetic data only) and an issue for each group of fails.

## 4. What blocks a merge

A change that touches UI (3.1) merges only when both audit passes are done and:

- no **Block** rule fails because of the change, on any platform it touches;
- a fail that was already on main does not block, if it has an open issue and the change does not make it worse (an
  audit that finds such a fail with no issue yet files one, and it then counts as already on main);
- a **Block** rule marked "Not checked" on a touched platform blocks, unless the reason is in the list of limits below
  or the user accepts it for that change;
- **Advice** fails never block; they are recorded.

Limits accepted for "Not checked" (until a tool for them is added):

- TalkBack's spoken output, sunlight and gloves: need a real phone; the accessibility tree and sizes stand in.
- Safari on an iPhone and VoiceOver: no iPhone here; Playwright's WebKit stands in for Safari and the ARIA snapshot
  for VoiceOver.
- The Note 9's frame walk (P1) outside the user's phone time window: the change waits for the window when it touches Plant's
  per-frame UI, otherwise the desktop's frame probe stands in.
- Windows on ARM64: not audited separately (the same code as x86-64).

## 5. Changing this policy

A rule is added, changed or waived only by the user. Waivers are listed here with the date and the reason.

- (none yet)
