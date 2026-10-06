# Dependency record: JetBrains Mono (font, Google Fonts release)

Added: 2026-09-27 (the Learning courses, M4; decision 0011)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime (font files shipped with every client: the web pages, the GNOME and Windows apps, the Android APK)
Packages covered: `vendor/fonts/JetBrainsMono-{400,600}-{latin,latin-ext}.woff2` and
`vendor/fonts/ttf/JetBrainsMono-{400,600}.ttf`, with `OFL-JetBrainsMono.txt`

## Purpose
The monospaced face of the Learning courses: KKS codes, numbers and values in figures (the "mono" face role in
`course.css`, `course-figure.js`, the GNOME `learn.nim`/`coursefig.nim`, the Android `Learn.kt`).

## Platform alternative checked
Every platform has a monospaced system face (`ui-monospace`/Consolas/SF Mono in browsers, Adwaita Mono or DejaVu Sans
Mono on GNOME, Consolas on Windows, Droid Sans Mono on Android), and the stylesheet falls back to them. They differ in
width and in how 0/O and 1/l/I are told apart, which matters for KKS codes; the courses were designed with this face
(0011).

## Custom implementation considered
Not applicable (a typeface). The alternative is the system monospace faces.

## Transitive dependencies
Count: 0   How counted: font files have no dependencies. Downloaded from Google Fonts by `tools/build_courses.py --fonts`
and `--ttf`, committed, with SHA-256 in `vendor/fonts/SHA256SUMS` and `vendor/fonts/ttf/SHA256SUMS`. The download itself
is not pinned (#4).

## License
OFL-1.1. Compatible with AGPL-3.0; the license text ships next to the files.

## Maintenance signals
- Recent releases: v2.304 on 2023-01-14, the latest ([releases](https://github.com/JetBrains/JetBrainsMono/releases));
  last repository activity 2025-01. Google Fonts' metadata last updated 2026-03-03
  ([google/fonts ofl/jetbrainsmono](https://github.com/google/fonts/tree/main/ofl/jetbrainsmono)).
- Security response: none of its own; font files are parsed by the platform's font engines, which carry that
  responsibility. Our files are fixed and hash-listed.
- Active maintainers: JetBrains (the type designers Philipp Nurullin and Konstantin Bulenkov); no commits in the last
  12 months. Not needed for a finished face.
- Age across major versions: since 2020; 1.x → 2.x (2.000 in 2020).

## Size impact
WOFF2 (web, GNOME, Windows): 86 KB for four subset files. TTF (Android): 224 KB for two weights, 106 KB compressed in
the APK.

## Replacement cost
Low. One family name in the course stylesheets and the native renderers' face lists.

## Decision
Keep. Finished, freely licensed, made by a company that maintains it, and vendored so the courses work offline and
never contact Google. As for the other course fonts, the quiet repository isn't a risk signal for a typeface: there is
no code to patch, and parsing is the platform font engine's job. Revisit with the course-size trigger in 0011.
