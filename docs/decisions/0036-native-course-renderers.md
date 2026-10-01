# 0036 The native apps render the JSON courses

Date 2026-10-01 · Scope: phase 8 (R8 courses on GNOME, Windows, Android; decisions 0025, 0031, 0033, 0032, 0035) ·
Status: **decided by Claude under the user's standing instruction to continue**; the user can revisit.

**Question:** each native app must show the courses (docs/COURSES.md) with its own toolkit, no web engine (0014).
What does each platform provide for rich text with links, the figures' 2D drawing, native controls, and the three
course faces (Atkinson Hyperlegible, Barlow Semi Condensed, JetBrains Mono; vendored as WOFF2 subsets, 0011)?

## Shared, platform-independent

- **Evaluation and validation:** the Nim core's `courses.nim` (passes the vectors). Android calls it through the
  existing JNI library rather than a Kotlin port, so there is one evaluator for the three apps.
- **Page logic:** `apps/common/coursestate.nim` (course list, progress through the local API's `/api/progress`,
  module done, recall, test draw, placement plan). Android gets the same through JNI calls where it needs them.

## Per platform

| Need | GNOME (GTK 4.22, libadwaita 1.9) | Windows 10/11 (Win32) | Android (Compose BOM 2024.12.01) |
|---|---|---|---|
| Rich text + links | GtkLabel with Pango markup (every string escaped) and `<a href>`; `activate-link` handles our targets | RichEdit 4.1 (Msftedit.dll): CHARFORMAT2 bold/italic, `CFE_LINK` + `EN_LINK`; it has its own UIA provider | `AnnotatedString` + `LinkAnnotation` (ui 1.7) in `Text` |
| Figure drawing | Cairo on a GtkDrawingArea; text with PangoCairo (shaping and fallback for any script) | Direct2D + DirectWrite (the viewer's `kks_d2d.cpp`) | Compose `Canvas` (`DrawScope`), text via `TextMeasurer` |
| Animation clock | `gtk_widget_add_tick_callback` (frame clock) | a timer at the display rate (`SetTimer` 16 ms) | `withFrameNanos` |
| Off screen = frozen (§9.6) | not mapped / outside the scrolled viewport | not visible in the scrolled page | not composed (lazy column) |
| Reduced motion | `gtk-enable-animations` setting | `SPI_GETCLIENTAREAANIMATION` | `Settings.Global.ANIMATOR_DURATION_SCALE` = 0 |
| Controls | GtkScale, GtkCheckButton, GtkToggleButton group, GtkButton | trackbar, checkbox, radio buttons, button | `Slider`, `Checkbox`, `RadioButton`, `Button` |
| Course faces (WOFF2) | fontconfig `FcConfigAppFontAddFile` loads them: **verified here** (fontconfig 2.15 + FreeType with brotli matched `Atkinson Hyperlegible:weight=700` to the vendored WOFF2) | DirectWrite `IDWriteFactory5::UnpackFontFile` (WOFF2, Windows 10 1703+) into an in-memory font set: **to verify in the VMs** | Android's `Typeface` reads TTF/OTF, not WOFF2: **not loaded**; the system faces are used (the roles still differ: sans, condensed, monospace) |
| Photos (JPEG XL) | libjxl (already linked, 0018) → GdkMemoryTexture | libjxl → WIC bitmap (already in the app) | the app's libjxl (`Jxl.kt`) |
| Accessibility | GTK's AT-SPI: labels, buttons; the figure is a GtkDrawingArea with role img, label = title, description = alt | RichEdit's UIA; figure = a custom control with a UIA name/help text (as the viewer's tags, `kks_uia.cpp`) | `semantics { contentDescription }` on the canvas, `heading()` on headings |

Sources: GTK 4 docs (GtkLabel markup and `activate-link`, `gtk_widget_add_tick_callback`):
https://docs.gtk.org/gtk4/ · Pango markup: https://docs.gtk.org/Pango/pango_markup.html · fontconfig
`FcConfigAppFontAddFile`: https://www.freedesktop.org/software/fontconfig/fontconfig-devel/fcconfigappfontaddfile.html
· RichEdit links: https://learn.microsoft.com/windows/win32/controls/en-link · DirectWrite
`UnpackFontFile`: https://learn.microsoft.com/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefactory5-unpackfontfile ·
Compose `LinkAnnotation`: https://developer.android.com/reference/kotlin/androidx/compose/ui/text/LinkAnnotation ·
Android font formats: https://developer.android.com/guide/topics/resources/font-resource

## Choice

- One renderer per app, built from the toolkit's own widgets as in the table; no new dependency.
- Android uses the system faces until we ship TTF copies of the three faces (OFL allows it; that is a packaging step,
  not a dependency).

**When to revisit:** if RichEdit's accessibility or link handling falls short in the Windows tests (fallback: our own
DirectWrite text view with a UIA text provider, much more code).

## Results 2026-10-01

- **Shared code:** `apps/common/figdraw.nim` (the drawing rules: paints, defaults, arrowheads, labels, groups, flows)
  through a small backend; `apps/common/coursestate.nim` (list, progress, page logic) for GNOME and Windows; core
  `courses.pickCourses`/`summary` for the server, the apps and the phone. Android records the backend calls as a
  compact op list in the Nim library (`android/nim/src/kksa/figops.nim`) and Kotlin replays it on the platform canvas:
  no JSON per frame.
- **GNOME** (`apps/gnome/src/kksg/learn.nim`, `coursefig.nim`): verified by `apps/gnome/e2e/test_gnome.py
  test_courses` over AT-SPI: Learning → a course window, the rail, a static and an animated figure exposed as images
  (name = title, description = alt), a question answered (progress in the subtitle), a figure off screen does not
  move (§9.6) and moves once on screen. The WOFF2 faces load through fontconfig. AT-SPI can't scroll GTK 4 widgets
  and synthesized keys don't reach the app on Wayland: the test scrolls through a SIGUSR2 hook (test mode only).
- **Windows** (`apps/windows/src/kkswin/learn.nim`, `coursefig.nim`, `kks_fig.cpp`): verified on Windows 10 22H2 and
  Windows 11 by `apps/windows/e2e/test_windows.py test_courses` (UIA): the course list, a course window, a page
  through the rail, an answer (progress in the window title), the gate figure animating after its button took focus.
  **DirectWrite unpacked the WOFF2 faces on both** (`course faces: 1` in the trace). Findings:
  - UIA's select on a Win32 list doesn't send `LBN_SELCHANGE`: the rail got an "Open the selected page" button (as
    the main window's lists), Enter and double-click work too.
  - A focused control below the visible part of a page didn't scroll into view (keyboard users): fixed for every page
    (`ui.showFocused` after each message); Page Up/Down/Home/End scroll a focused page; the wheel over RichEdit text
    scrolls its page.
  - The course window is sized to the work area (a 1280×800 screen hid its bottom).
  - Not verified: keyboard activation of a link inside RichEdit (`EN_LINK` on Enter is handled but RichEdit may not
    send it), and Narrator reading the RichEdit text.
- **Android** (`android/app2/.../ui/Learn.kt`): verified on the Pixel 9 Pro XL emulator by `android/app2/e2e/
  test_app2.py test_courses` (accessibility tree): the Learning tab, a course, Contents, a page, the figure as an
  image with its title and alt text, an answer (progress in the top bar), the animated gate figure drawn. The app's
  own courses ship as assets (5 MB). Not on the Note 9 or Honor 600 yet.
- **Android faces (2026-10-01):** the same faces as TTF from Google Fonts (`tools/build_courses.py --ttf`,
  `vendor/fonts/ttf`, 600 KB, SHA-256 listed, OFL), loaded with `Typeface.createFromAsset`: figure text is in the
  course faces on all four platforms now.
- **Not done:** a screen-reader pass with TalkBack, Narrator and Orca themselves (the tests read the accessibility
  trees those use).
