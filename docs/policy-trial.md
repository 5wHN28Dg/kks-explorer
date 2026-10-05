# Policy trial: findings

Policy v1.1 (`bf69f718b0d4b30ef439ca3a71118e2994433114`), adopted as a trial on branch `adopt-policy`, PR #1,
2026-10-05, then moved to v2.1 the same day (next section). Declared: `Tier: T3`, `Type: web, native, service`.
The v2.1 PR fixes the quick items only; every other finding is an issue, fixed later in its own PR.

Sources:
- **local:** `python3 ~/Documents/GitHub/policy/tools/policy_check.py conformance --root .`;
- **CI:** the Policy workflow on PR #1 (conformance, secrets, dependencies, static-analysis);
- **review:** the Claude review on PR #1. It runs on every push and edits its one summary comment, so there were
  two passes:
  - the first, on the adoption commit: 4 leads and 1 inline comment ("review #1"–"#4" below);
  - the second, after this file was added: 7 leads and 3 more inline comments ("review 2 #1"–"#7"). Its #1, #3–#7
    repeat entries already below (1.1–1.4, 1.5, 1.10, 1.7, 1.8, 1.11); its #2 is new (1.15);
  - the third, after 1.15 was added: 7 leads and 1 more inline comment ("review 3 #1"–"#7"). All repeat entries
    below; two cite a rule that doesn't apply to this PR (2.8, 2.9);
- **gitleaks local:** gitleaks 8.30.1 (the CI version, checksum verified) run locally with a JSON report, to see what
  CI's redacted "69 leaks" were.

Every finding is sorted into one of three groups:
1. a real problem in this project;
2. a false positive, with the reason;
3. a rule, or a check, that doesn't fit this project, with the reason.

The sections 1–3 below are the v1.1 run, kept as recorded. What changed under v2.1 comes first.

## Under v2.1 (2026-10-05)

PR #1 moved to policy v2.1 (`c0aaa58ecbc6177e95e02f202ef70b31d2ca6366`) with `Baseline: until 2027-01-03`. Local
runs: the conformance checker, the v2.1 static analysis (the policy's pinned Semgrep 1.179.0, the same steps as the
sast action, inline scripts included), osv-scanner 2.6.0 and gitleaks 8.30.1. The findings register is now GitHub
issues labelled `finding` and `severity:*` (#2–#18); exceptions are in `policy-exceptions.json` (EX-1 to EX-5,
waiting for the owner's acceptance).

### Fixed in this PR

| v1.1 entry | Fix |
|---|---|
| 1.5 (DEP-7, Flatpak container) | `arm64.yml` pins `ghcr.io/flathub-infra/flatpak-github-actions:gnome-50@sha256:1de59efe…` (the multi-arch index: amd64 and arm64 images). |
| 1.8, the Python half | `requirements-dev.txt` pins its five packages with `==` (the versions the tests passed with). osv-scanner now matches them: 0 vulnerabilities. Its missing packages are #14. |
| 2.1 (gitleaks on the vectors) | `.gitleaks.toml` extends the default rules and allowlists `ref/vectors/` and `peer/vectors/`, with the reason. Local gitleaks 8.30.1 over the whole history: no leaks. The policy's `secrets-config` check passes. |
| 1.15 (no findings register) | Issues #2–#18. |

### The register and the exceptions

| v1.1 entry | Issue | Severity | Exception |
|---|---|---|---|
| 1.1 threat model | #2 | Medium | baseline warning until 2027-01-03 |
| 1.8 Gradle lockfile | #3 | Medium | EX-4 `Gov §5 (lockfile)`, `android/app2/build.gradle.kts` |
| 3.1 pinned C/C++ sources (now DEP-8) | #4 | Medium | none needed: v2.1 checks the file only when it exists |
| 1.9 branch protection | #5 | Medium | not eligible (Section 10) |
| 1.10 no x86-64 tests in CI | #6 | Medium | no check reports it |
| 1.14 and the inline-script sinks (WEB-9) | #7 | Medium | EX-2 `WEB-9`: admin.html, index.html, common.js, learning.html |
| new: no CSP (WEB-8) | #8 | Medium | EX-1 `WEB-8` |
| 1.2 capability matrix | #9 | Low | baseline warning |
| 1.3 license allowlist | #10 | Low | baseline warning |
| 1.4 budgets.json | #11 | Low | baseline warning |
| 1.6 browserslist (WEB-2) | #12 | Low | EX-5 `WEB-2` (not an artifact the baseline covers) |
| 1.7 dependency records | #13 | Low | no check reports it |
| new: requirements-dev.txt incomplete | #14 | Low | no check reports it |
| 1.12 `ws://` relay | #15 | Low | the default-ruleset result is now a warning |
| 1.13 join code unescaped | #16 | Low | inside EX-2 |
| WEB-10 sites | #17 | Low, likely not a defect (below) | EX-3 `WEB-10`: common.js, index.html |
| new: 91 inline event handlers (WEB-7 warnings) | #18 | Low | warnings only |

Not filed: 1.11 (T3 review). v2.1's Section 11 gives a solo substitute for "two reviewers": the self-review and the
CI blind pass on every PR, plus an adversarial pass for a change that touches a trust boundary. That is a procedure
to follow, not a defect.

I checked each exception in a scratch git worktree with `acceptedBy` and `accepted` filled in: conformance and
static analysis then both pass, every result covered, each reported as a warning naming its entry. As committed,
with those two fields empty, CI reports `EX-n lacks acceptedBy, accepted` for each entry and fails, as intended
until the owner accepts them (at least a day after writing, Section 11).

### New results under v2.1

1. **Real (filed):** WEB-8, no CSP (#8); the lockfile check on the Gradle build (#3); 73 WEB-7 warnings for 91 inline
   handlers (#18); DEP-8 for the pinned C/C++ sources (#4); the sink scan now reaches the inline scripts: WEB-9
   31 more sites (admin.html 18, index.html 12, learning.html 1) and WEB-10 2 more (index.html 335, 355).
2. **False positives:**
   - **The five WEB-10 results.** WEB-10's v2.1 text excludes the `src` of image and media elements, and the
     `blob:`/`data:` URLs a page made itself. Every flagged site is one of those (common.js:148 a `blob:` download
     link; common.js:468, 552 and index.html:335, 355 image sources). Section 5 closes a confirmed false positive
     with a `policy-fp` marker after a fresh-context review, not with an exception. This PR adds no markers, so EX-3
     covers them meanwhile, and #17 says so.
   - **The WEB-9 constant markup** at common.js:565–574 (2.6) is now the "constant markup marked `policy-fp`" case
     of WEB-9's check: same path, inside EX-2 meanwhile.
   - **Default-ruleset warnings (non-blocking under v2.1):**
     - `gcm-detection` at `Keys.kt:57, 60` and `NativeCrypto.kt:130–134`. The first is the decrypt branch, reading
       the nonce stored with the data; the second is the JNI bridge, whose nonce comes from the Nim core.
     - `unencrypted-socket` at `Net.kt:115`: the raw socket is wrapped in an `SSLSocket` on the next line.
     - `detect-insecure-websocket` in `docs/policy-trial.md` lines 39 and 50: this file's own text.
3. **v1.1 "doesn't fit" entries v2.1 resolved:**
   - 3.1 by DEP-8 (`pinned-sources.cdx.json`, read by the scan, advisories checked by hand at audits);
   - 3.2 by Section 11's solo substitute for T3 review;
   - 3.3 by NAT-7's `release-test` for phones and low-end laptops;
   - 3.5 for WEB-10 (image `src` and self-made `blob:`/`data:` are out of scope, though the check still flags them);
   - 3.6 (inline scripts are scanned);
   - 3.7 (default-ruleset results below ERROR/HIGH/CRITICAL, or rated low-confidence, are warnings).

   Still open: 3.4 (WEB-2 wants a browserslist with no build tool to read it).

### New "doesn't fit" or check notes under v2.1

| # | Rule or check | Note |
|---|---|---|
| 4.1 | WEB-10 check vs WEB-10 rule | The rule now excludes image `src` and self-made `blob:`/`data:` URLs, but the check can't see the element or the URL's origin, so it still fails on them. Every such site needs a `policy-fp` marker backed by a fresh-context review, or, as here, an exception for something that isn't a risk. Either way the record says "accepted risk" or "marker" for what the rule says is not in scope. |
| 4.2 | Section 1, baseline | The baseline turns missing artifacts into warnings, but a missing browser declaration (WEB-2) still fails, though `.browserslistrc` is as much a declaration file as `license-allowlist.txt`. It needed its own exception (EX-5). |
| 4.3 | Exceptions by file | EX-2 has to cover whole files (admin.html, index.html, common.js, learning.html), so a new WEB-9 sink added to those files during the exception is a warning, not a failure. The compensating control relies on the PR review to catch it. A finer grain (per site, short of a line marker) isn't offered. |
| 4.4 | The WEB-8 check reads the exceptions file as a CSP source | The CSP check counts any tracked `.json` (and `.toml`, `.yaml`, `.py`, `.nim`…) file that contains the words "Content-Security-Policy" as a place where a CSP is set. EX-1's first wording ("served with no Content-Security-Policy") was enough: once `policy-exceptions.json` was in the PR, CI reported no WEB-8 failure at all, and EX-1 covered nothing. The exception describing the missing CSP made the check pass. (This is also why a run on a plain copy without `.git`, which reads untracked files too, showed no WEB-8.) EX-1 now says "no CSP, neither as a response header nor as a meta tag", and the check reports WEB-8 again. The check could skip `policy-exceptions.json` and require a directive (`script-src`, `default-src`) next to the marker. |

### CI on the v2.1 commit (run 37354031321)

- **secrets:** passes (the gitleaks allowlist).
- **dependencies:** passes. osv-scanner matched the pinned Python packages, with no vulnerabilities; the missing
  license allowlist is a baseline warning.
- **conformance:** fails.
  - Errors: the Gradle lockfile (EX-4), WEB-2 (EX-5), and `EX-n lacks acceptedBy, accepted` for all five entries.
  - Warnings: the four missing artifacts, and the baseline period itself.
  - It did not report WEB-8; see 4.4.
- **static-analysis:** fails.
  - Errors: 40 WEB-9 (EX-2) and 5 WEB-10 (EX-3).
  - Warnings: 73 WEB-7, and the default-ruleset results below.
- **claude-review:** see the review passes in the sources above.

Claude review on the v2.1 commits (two passes, 18:11 and 18:15; 0 blocking in the second):

| Lead | Group | Note |
|---|---|---|
| The gitleaks allowlist has a reason but no `policy-fp: <reason> (<review link>)` marker, no confirmation by someone other than the author, and it covers whole directories rather than the vector files | 1, candidate, not filed | Section 5 marks a confirmed false positive "in the tool's own suppression syntax (… a commented allowlist entry)" with `policy-fp` and a review link. The allowlist was added without one, as instructed for this PR (no `policy-fp` markers). Fix: a fresh-context review of the 69 hits, then the marker with its link, and paths narrowed to the vector files (`ref/vectors/v2-*.json`, `peer/vectors/v2-replay.json`). Waiting for the owner's decision on filing it. |
| `acceptedBy` and `accepted` empty in EX-1 to EX-5 | as intended | The owner accepts them at least a day after writing (Section 11). |
| EX-2 covers 40 sinks in four files, so a new sink in those files is a warning | 3 (4.3) | Already recorded. |
| The PR description has no `Secrets config change:` / `Exception change:` line (two inline comments at 18:11) | 2 | Stale: written before the description was updated; both lines are there now. |

Default-ruleset warnings in CI that the v1.1 run blocked on or didn't show (non-blocking now):

| Rule | Where | Group | Why |
|---|---|---|---|
| `dynamic-urllib-use-detected` | `tools/build_courses.py:27, 40, 46, 60, 71` | 1, part of #4 | The course build tool downloads the three font families from Google Fonts at build time, with no hash pinned. The URLs are fixed, so the urllib warning itself is a false positive, but the fetched fonts are third-party code fetched by a build script: DEP-8. |
| `insecure-hash-algorithm-sha1` | `relay/twin.py:219` | 2 | The WebSocket handshake's `Sec-WebSocket-Accept`, which RFC 6455 defines with SHA-1. Not a security use. |
| `avoid-pickle` | `tools/m6/grid_bench.py:88, 89`, `tools/m6/gsk_bench.py:91`, `tools/m6/write_paths.py:10` | 2 | Benchmark tools that load the `.paths.pkl` cache files they wrote themselves, in the same session's working folder. No untrusted input. |
| `exported_activity` | `tools/m6/android-bench/src/main/AndroidManifest.xml:3` | 2 | The launcher activity of a benchmark app; Android requires a launcher to be exported. Not shipped. |

## 1. Real problems in this project

| # | Rule | Source | Finding |
|---|---|---|---|
| 1.1 | Gov §4 | local, CI conformance, review #1 | `docs/threat-model.md` is missing. T3 needs one, reviewed each release. The decisions cover parts of it (0017 keys, 0020 storage, 0040 diagnostics, 0045 control socket), but there is no single list of assets, actors, trust boundaries and threats. |
| 1.2 | WEB-1, NAT-3, OTH-2 | local, CI conformance, review #1 | `docs/capability-matrix.md` is missing. The project has a matrix at `docs/m6/CAPABILITIES.md` (dated 2026-09-30, 16 sources, evidence markers), but it doesn't meet the template. It has no source column per row (sources are listed at the end), no Established column, no resolved browser list, and no column for the service runtime (server, relay Worker). It also predates the Flatpak, MSIX, ARM64 and webcam work. |
| 1.3 | Gov §5 | local, CI conformance and dependencies, review #1 | `license-allowlist.txt` is missing: the license policy isn't written down in a form the scanner reads. The licenses are recorded per dependency in `docs/decisions/0001`–`0013` and later records, but not as an allow-list. |
| 1.4 | WEB-15, NAT-7, OTH-5 | local, CI conformance, review #1 | `budgets.json` is missing. The project's budgets live in `docs/m6/MEASUREMENTS.md` (rules written before measuring), which isn't in the schema and isn't read by CI. See 3.3 for the part of the rule that doesn't fit. |
| 1.5 | DEP-7 | local, CI conformance, review #2 and its inline comment | The `flatpak-arm64` job's container `ghcr.io/flathub-infra/flatpak-github-actions:gnome-50` is a tag, not an `@sha256:` digest, and the job runs `--privileged`. A re-pushed tag would change the released ARM64 Flatpak's build environment with no change in the repository. |
| 1.6 | WEB-2 | local, CI conformance | No browser declaration. The deleted evidence-first web policy named the engines (Blink, WebKit, Gecko, Safari for iOS); with it gone, the supported browsers are written nowhere. See 3.4 for the format. |
| 1.7 | DEP-2 | review #1 | No dependency records in the template's format for the existing direct dependencies. Decisions 0001–0013 and later records answer most fields, but not in `docs/dependencies/<name>.md` and not field by field (transitive count, replacement cost). |
| 1.8 | Gov §5 (pinned by lockfile) | CI dependencies log | The vulnerability scan saw almost nothing. osv-scanner found only `requirements-dev.txt` (5 packages) and set all five aside as unscannable, so "0 blocking, 0 warning" is an empty pass. `requirements-dev.txt` has no versions at all. The Android build declares versions in `build.gradle.kts` but has no Gradle lockfile, so its transitive tree is neither pinned nor scanned. |
| 1.9 | Gov §1, §5 | review #4; `gh api …/branches/main/protection` says "Branch not protected" | Branch protection is off on `main`, and no job is required for merge. Direct pushes to main have been the working practice (every commit until this PR). |
| 1.10 | Gov §5, NAT-8, OTH-6 | review #4 | CI runs no test suite for the x86-64 builds: not the Nim core (`core`, 83 tests), the platform and server tests (23), the importer, the Python vector tests (31), the GNOME, Windows or Android e2e tests, or the web Playwright tests. Only the Android build (`android.yml`) and the ARM64 jobs (core tests on Linux ARM64, platform tests on Windows ARM64) run. The tests do exist and run locally before each commit. |
| 1.11 | Gov §3, §6, §11 (T3 review) | review #3 | T3 needs two reviewers, or a reviewer plus a fresh-context pass. So far there has been one author and no PRs: everything went to main directly. |
| 1.12 | Hardening: transport security (NAT-5 spirit; semgrep `detect-insecure-websocket`) | CI static-analysis: `core/src/kks/api.nim:1038`, `android/app2/src/main/kotlin/kks/explorer/core/Relay.kt:35` | Production builds accept a `ws://` relay address. The manager's relay setting allows `ws://`, and the Android client opens a raw socket for it, which Android's cleartext policy doesn't cover. The sync itself is TLS inside the pipe, pinned to the peer, so content stays protected. But the presence traffic (room = the plant, device peer IDs, who is online) would travel in clear. `ws://` exists for the local relay twin in tests. Low. |
| 1.13 | WEB-9 | CI static-analysis: `common.js:304` | The join code from the local API is interpolated into `innerHTML` without escaping (`${st.code.slice(0, 3)}`). The source is this device's own core, and the code is digits, so the impact is low. It is still a data value in an HTML sink. |
| 1.14 | WEB-9 | CI static-analysis: `common.js:81` (`K.overlay(html)`), and the escaped templates at `common.js:277`, `:400`, `:407`, `:411`, `:696`, `:713` | These insert HTML built from templates, with data escaped by the project's own `K.esc` and numbers interpolated directly. The project's rule was "escape and audit every `innerHTML`"; WEB-9 requires `textContent`, or a maintained sanitizer. No injection is known at these sites. They are still departures from a MUST, and `K.overlay` takes a whole HTML string from many callers (see 3.6 for what the scan didn't see). |

| 1.15 | Gov §1 (findings register), §8, §10 | review 2 #2 and its inline comment on this file | The project has no findings register, and the findings above have no severity (except 1.12's Low), owner or deadline. The known unfixed issues (1.12–1.14) have no Section 10 exception either. The adoption checklist asks for a register (an issue label is enough), and Section 8 starts each deadline when a finding is recorded. This file is the trial's list, kept unfixed on purpose until the user decides, not the register. |

## 2. False positives

| # | Rule | Source | Finding | Why it's a false positive |
|---|---|---|---|---|
| 2.1 | Gov §5 secrets (gitleaks `generic-api-key`) | CI secrets ("leaks found: 69"); gitleaks local | All 69 hits are in the protocol test vectors: `ref/vectors/v2-replay.json` 28, `v2-core.json` 23, `v2-reports.json` 8, `v2-crypto.json` 6, `v2-malformed.json` 3, plus the old `peer/vectors/v2-replay.json` 1 in history. The keys matched are `key` 57, `chain_key` 5, `secret_hex` 3, `report_key`, `report_key_private_scalar_hex`, `backup_key`, `bad-key`. | They are test keys made from fixed, published seeds, on purpose: `ref/make_v2_vectors.py` derives every key as `sha256("kks-vector-seed:" + name)` so that independent implementations can reproduce the vectors byte for byte. They protect nothing. The files are frozen spec, so the keys can't be moved or reformatted. |
| 2.2 | semgrep `detect-insecure-websocket` | CI static-analysis: `platform/linux/src/kksl/ws.nim:1`, `:16`, `:153` | The matches are comments naming the `ws://` scheme. | Comments, not code. The real concern behind them is 1.12. |
| 2.3 | WEB-10 | CI static-analysis: `common.js:148` | `a.href = URL.createObjectURL(new Blob(...))` for a download. | The URL is a `blob:` URL the page makes from its own data on that line. No user input or external data reaches the scheme. |
| 2.4 | WEB-10 | CI static-analysis: `common.js:468` | `img.src = u`, where `u = await this.url(src)`. | `u` is an object URL (`blob:`) of a picture the page itself decoded from JPEG XL. The original `src` only reaches this point if it matched `/\.jxl(\?|$)/`. |
| 2.5 | WEB-10 | CI static-analysis: `common.js:552` (`K.lightbox`), `common.js:628` (the photo editor's `base.src`) | An image `src` set from a parameter. | The callers pass `this.src` of an image the page already shows (`photos/<escaped hash name>`, `data/sheets/<id>.png`), or a `data:` URL the page made itself with `canvas.toDataURL`. Image `src` can't execute script. The rule lists `src` without telling `<img>` apart from `<script>`/`<iframe>`. |
| 2.6 | WEB-9 | CI static-analysis: `common.js:565`–`574` (the photo editor's toolbar) | A template literal assigned to `innerHTML`. | Every interpolation is a constant: button labels and colours from literal arrays, and `askNote`, which picks between two literal strings. No data reaches the sink. |
| 2.7 | Review #1, the "no `docs/` files" part | review | "The only `docs/` files I found are COURSES, PROTOCOL-v2, PATHSTORE, GLYPHLIB and m6/*." | `docs/decisions/` (48 records, including the dependency audits 0001–0013) exists; the review's checkout hides it on purpose (the `hide` list). The missing-artifact part of #1 is real (1.1–1.4, 1.7). |

| 2.8 | Gov §6 block list, "disables or suppresses a CI check without a recorded reason" | review 3 #2 | Cited as blocking because known issues (1.12–1.15) are recorded without a Section 10 exception. | This PR disables and suppresses nothing: every check runs and fails as it found. The underlying point (no exception, owner or deadline for known issues) is 1.15. |
| 2.9 | Gov §6 block list, "no tests for new behavior on tier 2 and up" | review 3 #3 | Cited as blocking because CI runs no x86-64 test suite. | This PR adds no behavior (a README header, CI configuration, a findings document), so there is nothing new to test. The missing test jobs are real, and recorded as 1.10. |

## 3. Rules or checks that don't fit this project

| # | Rule | Source | Why it doesn't fit |
|---|---|---|---|
| 3.1 | Gov §5, vulnerability scan (osv-scanner) | CI dependencies | Most of this project's third-party code is C and C++, fetched as source tarballs and pinned by SHA-256 in build scripts: libjxl, zxing-cpp, MuPDF, SQLite, zlib, and the emsdk for the WebAssembly build (`platform/windows/build-deps.sh`, `importer/fetch_mupdf.sh`, `android/nim/fetch_sqlite.sh`, `platform/web/build-wasm.sh`, the Flatpak manifest). No lockfile format exists for that, and osv-scanner can't see it, so the scan passes while covering none of it. The Nim code uses no package manager at all (no nimble packages). The policy needs a way to declare such pinned sources (a manifest the scanner reads, or a rule that the release audit checks their advisories by hand, as OTH-9 does for firmware). Fixing 1.8 covers the Python and Gradle parts only. |
| 3.2 | Gov §3, T3 review: two reviewers or reviewer + fresh-context pass | review #3 | This is a solo project. Section 11 lists solo substitutes for "independent review", but T3's "two reviewers" has no substitute, except that the T3 cell itself allows "reviewer + fresh-context pass", where the only possible reviewer is the author. Section 11 says the lighter-T2 relief "does not apply to tier 3", and says nothing about T3 review for a solo developer. The result is either every PR waiting on a person who doesn't exist, or an unwritten exception. |
| 3.3 | NAT-7 (budgets measured in CI on each platform) | local, CI conformance (`budgets.json` missing) | The budgets that matter here are measured on devices: startup and battery on the Note 9 and Honor 600, memory on a phone, startup on a slow laptop. CI runners and emulators don't represent them, and battery can't be measured in CI at all. OTH-5 allows `"measuredWhere": "release-test"` for metrics that need real hardware, but NAT-7 doesn't: it requires CI to measure every native budget and fail the merge. The file itself fits (1.4); the "CI measures it" part doesn't, for phones. |
| 3.4 | WEB-2 (`browserslist` in `.browserslistrc` or `package.json`, read by the build tooling), and WEB-1's `npx browserslist` check | local, CI conformance | The web client is vanilla JS with no build step, no bundler and no `package.json`. There is no build tooling to read a browserslist, so the declaration would exist only to feed the conformance check, which would also bring Node and `caniuse-lite` into CI. The need behind the rule (declare the supported engines, especially Safari for iOS) is real (1.6); the required format assumes an npm build. |
| 3.5 | WEB-10's `src` sink, and WEB-9's template-literal sink (semgrep rules) | CI static-analysis | Both rules fire on any `src` assignment and any template literal reaching `innerHTML`, whatever the element or the values. 2.4–2.6 are the pattern: image sources the page made itself, and markup built only from constants. A rule that told `<img>.src` apart from `<script>`/`<iframe>.src`, and skipped templates without interpolated non-literals, would cut the noise without missing real sinks. |
| 3.6 | WEB-9 and WEB-10 (the sast check's reach) | CI static-analysis | The semgrep run scanned `common.js` and the other `.js` files, but not the inline `<script>` blocks in `index.html`, `admin.html` and `learning.html`. That is where most of this web client's HTML building lives: 38 `innerHTML` uses (admin.html 22, index.html 15, learning.html 1), against 10 flagged in `common.js`, including the place of the stored XSS that was fixed in `admin.html` in phase 8. The policy's sink rules are `languages: [javascript, typescript]`, so Semgrep never parses the inline scripts. So the check's green or red says little about WEB-9 for this project's structure. Not a misfit of the rule; the check needs to extract inline scripts, or the policy should say that inline-script projects must split them out. |
| 3.7 | Semgrep default rules applied across languages (`javascript.lang.security.detect-insecure-websocket`) | CI static-analysis | A JavaScript rule ran against Kotlin and Nim files through Semgrep's multi-language matching, and its findings blocked the merge (1.12, 2.2). In a Nim project, a "JavaScript" rule that matches text in comments makes the blocking result noisy. The concern it found was real once (1.12), so the problem is precision, not relevance. |

## Not findings, but noted while adopting

- The two evidence-first policy documents were removed (the user's deletion), but `CLAUDE.md` still points to them in
  "Development policy: evidence-first". `CLAUDE.md` is hidden from the Claude review on purpose, so this isn't a
  review finding; it needs updating if the trial is kept.
- The Policy workflow's `sbom` job was skipped (it runs on release tags only), as designed.
- CodeQL (GitHub's default setup, already on before this PR) passed for actions, C/C++, JavaScript and Python. It is
  not part of the policy's CI.
