# Dependency record: Barlow Semi Condensed (font, Google Fonts release)

Added: 2026-09-27 (the Learning courses, M4; decision 0011)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime (font files shipped with every client: the web pages, the GNOME and Windows apps, the Android APK)
Packages covered: `vendor/fonts/BarlowSemiCondensed-{500,600,700}-{latin,latin-ext}.woff2` and
`vendor/fonts/ttf/BarlowSemiCondensed-{500,600,700}.ttf`, with `OFL-BarlowSemiCondensed.txt`

## Purpose
The headings and figure-label face of the three Learning courses (`course.css`, `vendor/fonts/courses.css`, the
native course renderers and figure labels, decision 0036).

## Platform alternative checked
System faces (`system-ui`, Cantarell/Adwaita Sans, Segoe UI, Roboto) are available everywhere and the course CSS falls
back to them (`"Arial Narrow"` first). The courses' headings and figure labels (the "display" face role in
`course-figure.js`, `coursefig.nim`, `Learn.kt`) were designed with this condensed face; a wider system face changes how
labels fit in the figures. That is the shortfall (0011).

## Custom implementation considered
Not applicable (a typeface). The alternative is a system face with re-checked figure layouts.

## Transitive dependencies
Count: 0   How counted: font files have no dependencies. Downloaded from Google Fonts by `tools/build_courses.py --fonts`
and `--ttf`, committed, with SHA-256 in `vendor/fonts/SHA256SUMS` and `vendor/fonts/ttf/SHA256SUMS`. The download itself
is not pinned (#4).

## License
OFL-1.1. Compatible with AGPL-3.0; the license text ships next to the files.

## Maintenance signals
- Recent releases: 1.422 on 2019-07-16, the latest ([jpt/barlow releases](https://github.com/jpt/barlow/releases));
  the design is finished. Google Fonts' metadata was last updated 2026-02-26
  ([google/fonts ofl/barlowsemicondensed](https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed)).
- Security response: none of its own; font files are parsed by the platform's font engines (browser sanitizers such
  as OTS, FreeType, DirectWrite, Android's), which carry that responsibility. Our files are fixed and hash-listed.
- Active maintainers: one designer (Jeremy Tribby); no commits in the last 12 months. Not needed for a finished face.
- Age across major versions: since 2017 (v1.2xx), 1.4xx since 2018.

## Size impact
WOFF2 (web, GNOME, Windows): 113 KB for six subset files. TTF (Android): 259 KB for three weights, 130 KB compressed
in the APK.

## Replacement cost
Low. One family name in the course stylesheets and the native renderers' face lists; figure label fits would need a
visual check with another face.

## Decision
Keep. Finished, freely licensed, vendored so the courses work offline and never contact Google. The single-designer,
no-release signals don't carry the usual weight for a font: there is no code to patch, and the parsing risk sits with
the platform font engines. Revisit with the course-size trigger in 0011.
