// Walkdown for Android (app2: Compose screens on the Nim core through JNI, decision 0032). The old KKS Explorer
// modules (app, core) were removed on 2026-10-03; they stay in git history.
plugins {
    kotlin("android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
    id("com.android.application") version "8.13.2" apply false
}
