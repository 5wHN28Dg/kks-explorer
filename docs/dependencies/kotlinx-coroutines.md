# Dependency record: kotlinx.coroutines 1.7.3

Added: 2026-10-01 (Walkdown's Android app, decision 0032)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime
Packages covered: `org.jetbrains.kotlinx:kotlinx-coroutines-core`, `-core-jvm`, `-android` and the `-bom`, version 1.7.3.
**Not declared in `android/app2/build.gradle.kts`:** the app's code imports it directly (`kotlinx.coroutines.launch`,
`withContext`, `delay`, `Dispatchers`, … in 21 imports), but the version is whatever AndroidX resolves (Compose and
WorkManager ask for 1.7.x; Gradle picks 1.7.3).

## Purpose
Runs work off the main thread in the Android app: calls into the Nim core on its own thread, picture decoding on IO,
figure frames on `Dispatchers.Default`, sync rounds from the UI (CLAUDE.md, phase 6 and the 2026-10-02 course fixes).

## Platform alternative checked
The Android framework offers `Executor`s, `Handler`/`Looper` and `java.util.concurrent`
([background work](https://developer.android.com/develop/background-work/background-tasks/asynchronous)). They work,
but Compose's APIs (`LaunchedEffect`, `rememberCoroutineScope`) and WorkManager's `CoroutineWorker` are built on
coroutines, and Google documents coroutines as the recommended way to do asynchronous work on Android
([Kotlin coroutines on Android](https://developer.android.com/kotlin/coroutines)). Coroutines are published by
JetBrains, not Google, so they get a record. They arrive with AndroidX in any case.

## Custom implementation considered
Callbacks over `Executor`s and `Handler`s: more code at every call site, and cancellation tied to the UI's lifetime
(which `rememberCoroutineScope` gives for free) would be ours to get right.

## Transitive dependencies
Count: 3 besides `-core` (`-core-jvm`, `-android`, `-bom`), all from the same project; `kotlin-stdlib`, which it needs,
is counted in [kotlin.md](kotlin.md)   How counted: the release runtime classpath
(`./gradlew :app2:dependencies --configuration releaseRuntimeClasspath`, 2026-10-05).

## License
Apache-2.0. Compatible with AGPL-3.0.

## Maintenance signals
- Recent releases: 1.11.0 on 2026-05-08, 1.10.2 on 2025-04-08, 1.10.0 on 2024-12-19; the 1.7.3 we get dates from
  2023-07-26 ([releases](https://github.com/Kotlin/kotlinx.coroutines/releases)).
- Security response: no SECURITY.md or advisories in the repository; JetBrains' [security bulletin](https://www.jetbrains.com/privacy-security/issues-fixed/)
  covers its libraries. No CVE found for kotlinx.coroutines.
- Active maintainers: 15 commit authors in the last 12 months, led by dkhalanskyjb (34 of 80 commits) (GitHub
  contributor statistics, 2026-10-05); part of JetBrains' Kotlin libraries team.
- Age across major versions: since 2016, 1.0 in 2018, still 1.x with a stable API.

## Size impact
`kotlinx.coroutines.*` is 242 of the 3,752 classes R8 keeps (`mapping.txt`), about 170 KB of the 2.68 MB
`classes.dex` by class count (an estimate).

## Replacement cost
Medium. Used in the Compose screens and the sync service (21 imports); Compose and WorkManager depend on it anyway, so
removing our direct use would not remove the library.

## Decision
Keep: it comes with AndroidX regardless, Google documents it as the way to do asynchronous work, and JetBrains
maintains it with a team. Follow-up for the owner: declare it in `android/app2/build.gradle.kts` with an explicit
version (it is used directly but resolved through AndroidX, so a Compose or WorkManager update silently changes it),
and move it to a current release with the Kotlin update ([kotlin.md](kotlin.md)).
