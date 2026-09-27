plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "kks.explorer"
    compileSdk = 36
    defaultConfig {
        applicationId = "kks.explorer"
        minSdk = 29                       // Android 10 (decided 2026-09-26)
        targetSdk = 36
        versionCode = 1
        versionName = "0.4.0-m3c"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("web"))
    packaging { resources.excludes += setOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF") }
}

// The web viewer and the plant data come from the repository, so the app always ships the current ones.
val copyWeb by tasks.registering(Sync::class) {
    val repo = rootDir.parentFile
    from(repo) { include("index.html", "admin.html", "common.js", "manifest.webmanifest", "icon.svg", "icon-192.png", "icon-512.png") }
    from(File(repo, "data")) { into("data") }
    into(layout.buildDirectory.dir("web"))
}
tasks.named("preBuild") { dependsOn(copyWeb) }

dependencies {
    implementation(project(":core"))
    // Material 3 shell (M3c): tabs adapt to the window (bottom bar on phones, rail on tablets / foldables)
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3:material3-adaptive-navigation-suite")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.13.1")          // FileProvider for camera photos
}
