# Dependency record: Atkinson Hyperlegible (font, Google Fonts release)

Added: 2026-09-27 (the Learning courses, M4; decision 0011)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime (font files shipped with every client: the web pages, the GNOME and Windows apps, the Android APK)
Packages covered: `vendor/fonts/AtkinsonHyperlegible-{400,400i,700}-{latin,latin-ext}.woff2` and
`vendor/fonts/ttf/AtkinsonHyperlegible-{400,700}.ttf`, with `OFL-AtkinsonHyperlegible.txt`

## Purpose
The body text face of the three Learning courses, designed by the Braille Institute for low-vision readers; the courses
were authored with it (`course.css`, `vendor/fonts/courses.css`, the native course renderers, decision 0036).

## Platform alternative checked
Every platform has system faces (`system-ui` in browsers, Cantarell/Adwaita Sans on GNOME, Segoe UI on Windows, Roboto
on Android), and the course CSS falls back to them. None is designed for low-vision legibility in the way this face is
(distinct letterforms for I/l/1, O/0), which is why the courses use it (0011, the accessibility side of the policy).

## Custom implementation considered
Not applicable (a typeface). The alternative is the system faces above, which work, at some cost to legibility.

## Transitive dependencies
Count: 0   How counted: font files have no dependencies. They are downloaded by `tools/build_courses.py --fonts`
(WOFF2) and `--ttf` (TTF, for Android's `Typeface`) from Google Fonts and committed, with their SHA-256 in
`vendor/fonts/SHA256SUMS` and `vendor/fonts/ttf/SHA256SUMS`. The download itself is not pinned (#4).

## License
OFL-1.1 (SIL Open Font License). Compatible with AGPL-3.0; the license text ships next to the files.

## Maintenance signals
- Recent releases: none since the Google Fonts release of 2021; the design is finished (the
  [googlefonts/atkinson-hyperlegible](https://github.com/googlefonts/atkinson-hyperlegible) repository is archived).
  The Braille Institute has since published a successor family, Atkinson Hyperlegible Next (2025-02-10, seven
  weights, 150 languages; [announcement](https://www.brailleinstitute.org/about-us/news/braille-institute-launches-enhanced-atkinson-hyperlegible-font-to-make-reading-easier/)).
- Security response: none of its own. Font files are parsed by the platform's font engine (browser sanitizers such as
  OTS, FreeType, DirectWrite, Android's Minikin), which carry the security responsibility; our files are fixed and
  hash-listed.
- Active maintainers: none needed for a finished typeface; Google Fonts keeps its metadata current (last change
  2026-03-03, [google/fonts ofl/atkinsonhyperlegible](https://github.com/google/fonts/tree/main/ofl/atkinsonhyperlegible)).
- Age across major versions: created in 2019 by the Braille Institute with Applied Design Works
  ([Wikipedia](https://en.wikipedia.org/wiki/Atkinson_Hyperlegible)); one version of this family.

## Size impact
WOFF2 (web, GNOME, Windows): 81.6 KB for the six subset files. TTF (Android): 106 KB for two weights, 58 KB
compressed in the APK. The web pages load it only on course pages and cache it.

## Replacement cost
Low. One font-family name in `course.css`/`courses.css` and the native renderers' face lists; swapping to another face
or to system faces changes no data.

## Decision
Keep. A finished, freely licensed typeface with a clear accessibility reason, vendored so the courses work offline and
never contact Google. The "no maintenance" signal doesn't apply to a font in the usual sense: there is no code to fix,
and the parsing risk sits with the platform font engines. Revisit if course size becomes a measured problem on phones
(0011), or consider Atkinson Hyperlegible Next if the courses are re-styled.
