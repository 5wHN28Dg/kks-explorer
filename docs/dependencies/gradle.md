# Dependency record: Gradle 8.13 (with the vendored wrapper)

Added: 2026-09-26 (the v1 Android app)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: build-time
Packages covered: the Gradle 8.13 distribution (`android/gradle/wrapper/gradle-wrapper.properties`), the vendored
wrapper jars `android/gradle/wrapper/gradle-wrapper.jar` and `tools/m6/android-bench/gradle/wrapper/gradle-wrapper.jar`
(the throwaway benchmark app, decision 0015)

## Purpose
Builds the Android app: runs the Android Gradle Plugin, the Kotlin compiler, CMake for the JNI libraries, and the
project's own tasks (`fetchLibjxl`, `fetchZxing`, `copyData`, `copyFonts`).

## Platform alternative checked
The Android Gradle Plugin (Google's, platform-provided, see the index) runs only inside Gradle; Google documents
Gradle as the Android build system ([Configure your build](https://developer.android.com/build)). There is no other
supported way to build an APK with AGP. Gradle itself is published by Gradle Inc., not the OS vendor, so it gets a
record.

## Custom implementation considered
Driving `aapt2`, `d8`/`r8`, `apksigner` and the NDK by hand from scripts: possible, but resource linking, R8
configuration, baseline profiles and signing are exactly what AGP does, and we would own that pipeline.

## Transitive dependencies
Count: 137 third-party jars in the distribution, plus what AGP and Kotlin add (counted in their places)
How counted: the `.jar` files in `gradle-8.13/lib/` and `lib/plugins/` of the unpacked distribution
(`~/.gradle/wrapper/dists/gradle-8.13-bin/`), minus Gradle's own `gradle-*-8.13.jar` modules (307 jars in total).

## License
Apache-2.0 (Gradle and the wrapper). Its bundled libraries are mostly Apache-2.0, MIT, BSD and EPL; they run only at
build time. Compatible with AGPL-3.0.

## Maintenance signals
- Recent releases: 9.8.0 on 2026-09-24, 9.7.1 on 2026-08-19; on the 8.x line, 8.14.4 on 2026-01-23 (the patch for the
  advisories below). Our 8.13 is from 2025-02-25 ([releases](https://github.com/gradle/gradle/releases)).
- Security response: GitHub advisories with fixed versions, e.g. CVE-2025-27148 (temporary directory, fixed in
  8.12.1) and **CVE-2026-22865 and CVE-2026-22816** (repositories that fail to answer, or have an unknown host, are not
  disabled, which can expose builds to malicious artifacts; high; affected `< 8.14.4`, fixed in 8.14.4 and 9.3.0)
  ([advisories](https://github.com/gradle/gradle/security/advisories)). **Our 8.13 is affected by both.**
- Active maintainers: 87 commit authors in the last 12 months, Gradle Inc.'s team (GitHub contributor statistics,
  2026-10-05).
- Age across major versions: 1.0 in 2012; majors 1 to 9, the Android build system throughout.

## Size impact
None in the app (build tool). The distribution is 146 MB on the build machine.

## Replacement cost
High in effort, low in risk: the whole Android build is Gradle Kotlin DSL (`android/*.gradle.kts` and
`android/app2/build.gradle.kts`, 184 lines). An
update within 8.x is a one-line change in `gradle-wrapper.properties`.

## Decision
Keep Gradle: AGP requires it. Two actions for the owner, outside this record's files:
- update the wrapper to 8.14.4 (or a 9.x that the AGP version supports) for CVE-2026-22865/22816, and re-run the
  Android builds and e2e suites;
- add `distributionSha256Sum` to `android/gradle/wrapper/gradle-wrapper.properties`, so the downloaded distribution is
  checked (today it is pinned by version only). The vendored wrapper jars match Gradle's published checksum for
  8.13 (both are SHA-256 `81a82aae…`, checked 2026-10-05 against `services.gradle.org`); a CI check (Gradle's
  wrapper-validation action) would keep it that way.
