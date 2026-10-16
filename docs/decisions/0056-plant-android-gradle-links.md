# 0056 Walkdown Plant on Android: a Gradle export for links into the app

Date 2026-10-16 · Scope: links into Walkdown Plant (docs/PLANT3D.md §6; decision 0054 §3, "an intent filter in a
Gradle-built export, and a small Android plugin") · Status: **accepted** (built and run on the Note 9).

**Question:** how does the Android app receive `walkdown-plant://kks/<code>` and `…/procedure/<id>`, and what does
that need from the build?

## Findings

[D] Godot 4.7 documentation, [S] the 4.7.2 export template's `godot-lib` (`javap`), [V] verified here.

| | Finding |
|---|---|
| The manifest | Godot's plain (non-Gradle) export rewrites only fixed parts of the template's binary manifest; an `EditorExportPlugin`'s `_get_android_manifest_application_element_contents` is used in Gradle builds [D]. An activity alias with the VIEW intent filter in the application element works: the template's own launcher is such an alias of `com.godot.game.GodotApp` (which is not exported) [S][V]. |
| The Intent | Godot 4.4+ ships an `AndroidRuntime` plugin whose `getActivity()` GDScript can call through JavaClassWrapper [S]; `GodotActivity.onNewIntent` calls `setIntent(newIntent)` (after removing only the command-line extra) [S]. So `getActivity().getIntent().getDataString()` gives the link at start and after a new one arrives: no plugin of ours, no Java or Kotlin code [V: a cold start and a running app on the Note 9]. |
| The Gradle build | The 4.7.2 template is Gradle 8.11.1 with the Android Gradle plugin 8.6.1 and Java 17 bytecode [S]. Gradle 8.11 does not run on JDK 25, the only JDK on this laptop and the one Walkdown's own build uses [V]. Bumping the template's Gradle and plugin versions means maintaining Godot's template ourselves. |
| Supply chain | The template comes from the export templates (SHA-512, `fetch_godot.sh`); its wrapper downloads Gradle without a checksum and resolves the plugin and AndroidX from Google, Maven Central and the Gradle plugin portal (the template also lists Sonatype's snapshot repository) [S]. |
| Cost | A Gradle debug export takes about 1.5 minutes here and fits a 6 GiB cap with 2 workers and no daemon [V]; the APK keeps no INTERNET permission [V, aapt2]. |

## Choice

- The Android presets use the Gradle build; `addons/walkdown_plant_android` (editor-only, not exported) adds the
  alias `com.godot.game.WalkdownPlantLink` with the `walkdown-plant` VIEW/BROWSABLE intent filter.
- `ui/links_in.gd` reads the Intent through `AndroidRuntime` (on start and on resume, once per Intent) and the
  command line on the desktops.
- `build.sh` installs Godot's template from the checked export templates itself, pins Gradle 8.11.1 by SHA-256
  (`distributionSha256Sum`), caps Gradle (`-Xmx2g`, 2 workers, no daemon), and runs it on Eclipse Temurin 17 fetched
  by `tools/plant3d/fetch_jdk.sh` (pinned version and SHA-256, under `~/.local/kksdev`, nothing system-wide). CI does
  the same.
- **Gradle's dependency verification:** every artifact the build resolves (the Android Gradle plugin, Kotlin, AndroidX:
  320 components) must match the SHA-256 in `apps/plant3d/android-gradle-verification.xml`, recorded once from the
  artifacts downloaded here on 2026-10-16 (trust on first use; `PLANT_GRADLE_WRITE_VERIFICATION=1 build.sh export
  android-debug android-release` records it again into that file, to review and commit). A changed artifact fails the build [V: one altered checksum
  failed it].
- **The signing key never reaches Gradle:** the release is exported unsigned and then aligned and signed by
  `build.sh` with the SDK's `zipalign` and `apksigner` (password through the environment of apksigner alone), as the
  plain export did before.
- On the desktops the link comes after `--` (`Exec=godot-runner -- %u`, MSIX `Parameters="-- "%1""`), so that a
  crafted URI is never read as one of Godot's own options.

**When to revisit:** when Godot's template moves to a Gradle that runs on the JDK Walkdown uses (drop the second JDK);
if Godot gives a plain export a way to add intent filters (drop Gradle); when Godot's template changes its dependencies (record the
verification file again and review what changed).
