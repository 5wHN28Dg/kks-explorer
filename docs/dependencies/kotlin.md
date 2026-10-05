# Dependency record: Kotlin 2.0.21

Added: 2026-09-26 (the v1 Android app); kept for Walkdown's Android UI (decisions 0027, 0032)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime (`kotlin-stdlib` ships in the APK) and build-time (the compiler, its Gradle plugin, the Compose compiler
plugin)
Packages covered: the Gradle plugins `org.jetbrains.kotlin.android` and `org.jetbrains.kotlin.plugin.compose` 2.0.21
(`android/build.gradle.kts`), and the runtime artifacts they add: `org.jetbrains.kotlin:kotlin-stdlib` 2.0.21 with its
companions (`kotlin-stdlib-common`, `-jdk7`, `-jdk8`) and `org.jetbrains:annotations`. kotlinx.coroutines has its own
record ([kotlinx-coroutines.md](kotlinx-coroutines.md)).

## Purpose
The language of the Android app's UI and platform glue (5,600 lines: Compose screens, JNI calls into the Nim core,
TLS, sync service, updates).

## Platform alternative checked
Android's framework languages are Java and Kotlin. Google documents Kotlin as the preferred language
([Kotlin-first](https://developer.android.com/kotlin/first)) and Jetpack Compose, Google's recommended UI toolkit,
requires it ([Compose](https://developer.android.com/develop/ui/compose)). Kotlin is published by JetBrains, not the
OS vendor, so it doesn't pass `NAT-1` test 1 on its own and gets a record. The platform alternative is Java with the
View system: it needs no extra runtime library, but gives up Compose, which is how Google builds UIs today.

## Custom implementation considered
Not applicable to a language. The cost of the alternative (Java + Views) is the older UI toolkit, which Google's
documentation now steers new apps away from in favour of Compose, and a rewrite of every screen.

## Transitive dependencies
Count: 4 runtime modules, 34 build-time modules   How counted: in the release runtime classpath
(`./gradlew :app2:dependencies --configuration releaseRuntimeClasspath`, 2026-10-05) `kotlin-stdlib` 2.0.21 brings
`kotlin-stdlib-common`, `-jdk7`, `-jdk8` (version constraints, empty on Kotlin 2) and `org.jetbrains:annotations`
23.0.0. On the build script classpath (`./gradlew buildEnvironment`) the Kotlin Gradle plugin brings 29 modules and
the Compose compiler plugin 5 (unique group:artifact pairs under each plugin).

## License
Apache-2.0 (Kotlin, the plugins, the standard library, `org.jetbrains:annotations`). Compatible with AGPL-3.0.

## Maintenance signals
- Recent releases: Kotlin 2.4.20 on 2026-09-07, 2.4.10 on 2026-07-14, 2.5.0-Beta1 on 2026-09-23; our 2.0.21 dates
  from 2024-10-10 ([releases](https://github.com/JetBrains/kotlin/releases)).
- Security response: [SECURITY.md](https://github.com/JetBrains/kotlin/blob/master/SECURITY.md); JetBrains lists
  fixed issues in its [security bulletin](https://www.jetbrains.com/privacy-security/issues-fixed/). Past CVEs were
  fixed in releases: CVE-2020-29582 (temp-file permissions, 1.4.21), CVE-2022-24329 (dependency locking, 1.6.0),
  and **CVE-2026-53914** (code execution through unsafe deserialization of build cache metadata, fixed in 2.4.20,
  [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-53914)), which affects our 2.0.21 at build time.
- Active maintainers: 155 commit authors in the last 12 months, JetBrains' Kotlin team (GitHub contributor
  statistics, 2026-10-05).
- Age across major versions: since 2011, 1.0 in 2016, 2.0 (the K2 compiler) in 2024; our code was written on 2.0.

## Size impact
`kotlin.*` classes are 207 of the 3,752 classes R8 keeps in the release build (`mapping.txt`), about 150 KB of the
2.68 MB `classes.dex` by class count (an estimate; the DEX was not split by package). Build-time parts don't ship.

## Replacement cost
High: all of the Android UI and glue is Kotlin. A version upgrade is routine (plugins in `android/build.gradle.kts`),
but 2.0 → 2.4 may bring Compose compiler changes and needs the emulator e2e suites.

## Decision
Keep the language: it is Google's documented path for Android UI, maintained by a large team, and Compose requires it.
The version is the problem: 2.0.21 is two years old and affected by CVE-2026-53914. The precondition is a poisoned
build cache (our builds use the local Gradle cache, and CI the GitHub Actions cache of this repository), so the risk is
low but real. Action for the owner: update Kotlin and the Compose BOM together (decision 0008 already asked for the
AndroidX update) and re-run the Android e2e suites; this record then needs its version fields updated (DEP-5).
