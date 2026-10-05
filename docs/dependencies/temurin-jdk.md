# Dependency record: Eclipse Temurin JDK 21

Added: 2026-09-27 (the Android builds, local and CI)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: build-time
Packages covered: Eclipse Temurin 21 (OpenJDK build by Adoptium): `/usr/lib/jvm/temurin-21-jdk-amd64` on the
maintainer's machine (21.0.7+6), and the `temurin` / `21` JDK that `actions/setup-java` installs in
`.github/workflows/android.yml` (the latest 21.x at run time)

## Purpose
Runs Gradle, the Android Gradle Plugin, the Kotlin compiler and R8 for the Android build. Gradle 8.13 doesn't run on
newer JDKs (comment in `android.yml`).

## Platform alternative checked
Android Studio bundles the JetBrains Runtime (a JDK) for its own builds, and AGP documents only the required JDK
version ([Java versions in Android builds](https://developer.android.com/build/jdks)); Google publishes no standalone
JDK for command-line builds. Any OpenJDK 17+ build would do; Ubuntu's own `openjdk-21-jdk` is the platform-provided
choice on the build machine and would also work.

## Custom implementation considered
Not applicable (a JVM).

## Transitive dependencies
Count: 0 packages   How counted: the JDK is one self-contained image; OpenJDK bundles native libraries of its own
in its source tree (zlib, libpng, FreeType, HarfBuzz and others), which are part of that image and not counted
separately.

## License
GPL-2.0-only WITH Classpath-exception-2.0 (OpenJDK). Only run at build time; nothing of it ships in the APK.

## Maintenance signals
- Recent releases: quarterly with OpenJDK's critical patch updates; the latest 21 build is 21.0.12.1+1 (2026-08-19,
  [Adoptium API](https://api.adoptium.net/v3/assets/latest/21/hotspot)). The local 21.0.7+6 (2025-04-15) is five
  quarterly updates behind.
- Security response: OpenJDK's [Vulnerability Group](https://openjdk.org/groups/vulnerability/) publishes advisories
  each quarter; Adoptium ships the fixed builds the same day or soon after.
- Active maintainers: the Eclipse Adoptium working group (several companies) builds and tests Temurin; OpenJDK itself
  has a large multi-company team.
- Age across major versions: Adoptium/AdoptOpenJDK since 2017; JDK 21 is an LTS release (2023) supported into the
  2030s.

## Size impact
None in the app (build tool).

## Replacement cost
Low. Any OpenJDK 17–21 build runs the same Gradle build; changing it is setting `JAVA_HOME`.

## Decision
Keep a JDK 21 (required by the toolchain). Temurin is a well-supported OpenJDK build; Ubuntu's `openjdk-21-jdk` would
be the platform-provided equivalent and could replace it if the owner prefers fewer outside sources. Follow-up: update
the maintainer's local JDK (21.0.7 misses five quarterly security updates); CI already gets the current one.
