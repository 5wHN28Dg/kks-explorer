# 0070 Walkdown Plant on Android: fixed versions of the build tools, and lockfiles the scan reads

Date 2026-10-27 · Scope: the Gradle build of Walkdown Plant's Android export (decision 0056) · Status: **accepted**
(the user chose it on 2026-10-27, before the plant's 0.3.0).

**Question:** the plant's Android build resolves build tools (the Android Gradle plugin's and lint's libraries, the
Kotlin Gradle plugin) at versions with published advisories, and the required dependency check (osv-scanner) never
sees them: the only record of them, `apps/plant3d/android-gradle-verification.xml`, is not a file it reads. How are
they raised to fixed versions, and how does the check see the build?

## Findings

[S] the 4.7.2 export template's Gradle files, [O] osv-scanner 2.6.0 (the version the policy action pins) and the
OSV database on 2026-10-27, [V] verified here.

| | Finding |
|---|---|
| What is affected | osv-scanner over the verification file (copied to a path it reads) finds advisories in guava 32.0.1-jre, protobuf-java 3.22.3, commons-io 2.13.0, netty 4.1.93.Final (8 modules), commons-compress 1.21, httpclient 4.5.6 (a POM only: 4.5.14 is the version used), jose4j 0.9.5, bouncycastle 1.77, jdom2 2.0.6 and kotlin-gradle-plugin 2.1.21 [O]. All are build tools: the plugins' classpath and lint; none is in the APK [V, dexdump]. |
| Fixed versions in the same line | guava: only 33.7.2-jre (no 32.x fix; the version Walkdown's own build uses); protobuf-java 3.25.5; commons-io 2.14.0; netty 4.1.137.Final (the newest fix among its advisories); commons-compress 1.26.0; jose4j 0.9.6; bouncycastle 1.85; jdom2 2.0.6.1; httpclient 4.5.14; kotlin-gradle-plugin 2.4.20 (the first 2.x release with the fix) [O]. |
| Where the template can take them | The template's root `build.gradle` and `settings.gradle` are Godot's (`build.sh` installs them from the export templates). One line added to `settings.gradle` applies a script of ours to every project (`gradle.allprojects`): a resolution rule on the buildscript classpath and every configuration, as in Walkdown's own `android/build.gradle.kts`, and dependency locking [V]. |
| What the scan reads | osv-scanner reads Gradle lockfiles by name (`gradle.lockfile`, `buildscript-gradle.lockfile`) wherever they are, and `gradle/verification-metadata.xml`; it skips files git ignores (the template's folder) [O, V]. The verification file lists every version Gradle downloaded metadata for, including the losers of conflict resolution (httpclient 4.5.6 next to 4.5.14), so scanning it would report versions the build does not use; a lockfile lists only the resolved ones [V]. |
| Kotlin 2.4.20 on the template | The template compiles only Java (`GodotApp.java`); the Kotlin plugin also sets the Kotlin standard library the app bundles, so that moves from 2.1.21 to 2.4.20 (godot-lib, compiled against 2.1, runs on the newer library: Kotlin's standard library keeps binary compatibility) [V]. Gradle 8.11.1 is still supported by the plugin, with a deprecation warning [V]. |

## Choice

- `apps/plant3d/android-gradle-pins.gradle`: the fixed versions (raised only, never lowered; netty's and protobuf's
  modules together), every configuration locked in STRICT mode. `build.sh` copies it into the template and applies
  it from `settings.gradle`.
- The lockfiles live in `apps/plant3d/android-locks/` (the template's paths), which `build.sh` copies into the template
  before each export; a configuration missing from them fails the build. The required `dependencies` check scans
  them, vulnerabilities and licenses.
- `PLANT_GRADLE_WRITE_VERIFICATION=1 build.sh export android-debug android-release`, from an empty
  `GRADLE_USER_HOME`, writes the verification file and the lockfiles again (as in 0056), to review and commit.

**When to revisit:** when Godot's template moves to a newer Android Gradle plugin or Kotlin (drop the pins it no
longer needs: the rule never lowers, so a stale pin is harmless but should go); when the scan reports a new advisory
in the lockfiles (raise the pin to the fixed version in the same line, or stop if there is none).
