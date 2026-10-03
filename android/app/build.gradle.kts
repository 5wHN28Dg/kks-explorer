import java.net.URI
import java.security.MessageDigest
import java.util.Properties

plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// One version for every platform: the repository's VERSION file (M5b self-updates compare it with GitHub Releases).
// The cutover release's v1 app is the bridge to the new app (decision 0042): it must carry the release's version, or
// it would offer itself again as an update. versionCode = major·10000 + minor·100 + patch.
val appVersion = rootDir.parentFile.resolve("VERSION").readText().trim()
val appVersionCode = appVersion.split('.').map { it.toInt() }.let { (a, b, c) -> a * 10000 + b * 100 + c }

android {
    namespace = "kks.explorer"
    compileSdk = 36
    defaultConfig {
        applicationId = "kks.explorer"
        minSdk = 29                       // Android 10 (decided 2026-09-26)
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersion
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }   // phones (64/32-bit ARM), the emulator
        externalNativeBuild {
            cmake {
                // libjxl is slow unoptimized: build it optimized in debug builds too
                arguments += listOf("-DLIBJXL_SRC=${layout.buildDirectory.dir("third_party/libjxl").get().asFile}", "-DCMAKE_BUILD_TYPE=Release", "-DANDROID_STL=c++_static")
            }
        }
    }
    // Release signing (M3e): the key stays on the maintainer's machine, never in the repository or CI. Its
    // keystore.properties (storeFile, storePassword, keyAlias, keyPassword) is found through $KKS_SIGNING or in
    // ~/.config/kks-explorer/signing/. Without it, assembleRelease makes an unsigned APK (CI). docs/ANDROID_RELEASE.md
    val signing = (System.getenv("KKS_SIGNING")?.let { File(it) }
        ?: File(System.getProperty("user.home"), ".config/kks-explorer/signing/keystore.properties"))
        .takeIf { it.isFile }?.let { f -> Properties().apply { f.inputStream().use { load(it) } } to f.parentFile }
    signingConfigs {
        if (signing != null) create("release") {
            val (p, dir) = signing
            storeFile = File(p.getProperty("storeFile")).let { if (it.isAbsolute) it else File(dir, it.path) }
            storePassword = p.getProperty("storePassword")
            keyAlias = p.getProperty("keyAlias")
            keyPassword = p.getProperty("keyPassword")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true              // R8: shrink + optimize (rules in proguard-rules.pro)
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (signing != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    ndkVersion = "27.2.12479018"
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("web"))
    packaging { resources.excludes += setOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF") }
}

// libjxl (JPEG XL, for photos) from pinned sources: the release tag and the submodule commits it names, each checked
// against its SHA-256. Unpacked once into build/third_party/libjxl; CMake builds it (src/main/cpp).
val jxlSrc = layout.buildDirectory.dir("third_party/libjxl")
val fetchLibjxl by tasks.registering {
    val sources = listOf(   // name, URL, SHA-256, where in the libjxl tree
        listOf("libjxl", "https://codeload.github.com/libjxl/libjxl/tar.gz/v0.12.0", "03e9be69a30be4011f559da75328b6d7cea8ad921fabfbd551ce10bf45cdc992", ""),
        listOf("highway", "https://codeload.github.com/google/highway/tar.gz/457c891775a7397bdb0376bb1031e6e027af1c48", "5124b0501c98d9930dbb065bfa1a5bbbd59ce0f12facb7e1e33aaef01a5f1f1a", "third_party/highway"),
        listOf("brotli", "https://codeload.github.com/google/brotli/tar.gz/028fb5a23661f123017c060daa546b55cf4bde29", "0afe09a53c8bad9861c8dd1fc1284308d54f19d2979ba3541cfdcc9b05fe360f", "third_party/brotli"),
        listOf("skcms", "https://codeload.github.com/google/skcms/tar.gz/96d9171c94b937a1b5f0293de7309ac16311b722", "9bb4b5bba0b7c04f6c2bce9ff713d61e23c9a20c4945161ae16290498ad74627", "third_party/skcms"))
    val dl = layout.buildDirectory.dir("third_party/download").get().asFile
    val out = jxlSrc.get().asFile
    inputs.property("sources", sources.toString())
    outputs.dir(out)
    doLast {
        dl.mkdirs()
        out.deleteRecursively()
        for ((name, url, sha, sub) in sources) {
            val f = File(dl, "$name.tar.gz")
            fun digest() = MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString("") { "%02x".format(it) }
            if (!f.exists() || digest() != sha) {
                logger.lifecycle("Downloading $name")
                URI(url).toURL().openStream().use { i -> f.outputStream().use { i.copyTo(it) } }
                val got = digest()
                if (got != sha) { f.delete(); throw GradleException("$name: SHA-256 $got, expected $sha") }
            }
            copy {
                from(tarTree(resources.gzip(f)))
                eachFile { relativePath = RelativePath(true, *relativePath.segments.drop(1).toTypedArray()) }   // drop "name-commit/"
                includeEmptyDirs = false
                into(File(out, sub))
            }
        }
    }
}
tasks.configureEach { if (name.startsWith("configureCMake") || name.startsWith("buildCMake")) dependsOn(fetchLibjxl) }

// The web viewer and the plant data come from the repository, so the app always ships the current ones.
val copyWeb by tasks.registering(Sync::class) {
    val repo = rootDir.parentFile
    from(repo) { include("index.html", "admin.html", "common.js", "tiles.js", "kks-wasm.js", "kks-wasm-worker.js", "vendor/kks/*", "course-bridge.js", "vendor/fonts/*.css", "vendor/fonts/*.woff2", "manifest.webmanifest", "icon.svg", "icon-192.png", "icon-512.png") }
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
    implementation("androidx.work:work-runtime-ktx:2.9.1")   // background sync (M3d)
    implementation("com.journeyapps:zxing-android-embedded:4.3.0") { isTransitive = false }   // QR scanner (join by invite)
    implementation("com.google.zxing:core:3.5.4")
}
