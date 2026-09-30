# 0011 Vendored course fonts

Date 2026-09-30 · Scope: the three Learning courses (`vendor/fonts`, via tools/build_courses.py) · Status: keep

**What:** Atkinson Hyperlegible, Barlow Semi Condensed and JetBrains Mono, as Latin + Latin Extended woff2 files
(OFL-1.1), served locally instead of from Google Fonts.

**Platform:** every browser has system fonts (`system-ui`, `ui-monospace`). The courses were designed with these
three faces. Atkinson Hyperlegible exists for low-vision readability, which is on the accessibility side of the web
policy.

Vendoring instead of linking Google keeps the courses offline-capable and makes no third-party requests.

**Dependency check:** font files, not code. OFL-1.1, compatible with AGPL-3.0. SHA256SUMS in `vendor/fonts`.

**Decision:** keep. The cost is a few hundred KB, cached once. The course pages already fall back to system fonts
through their CSS stacks.

**Revisit:** if course size becomes a measured problem on phones.

Sources: `vendor/fonts/README.md`, `vendor/fonts/OFL-*.txt`
