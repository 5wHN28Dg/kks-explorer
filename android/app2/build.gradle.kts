import java.net.URI
import java.security.MessageDigest
import java.util.Properties

// KKS Explorer v2 for Android (M6 phase 6, decisions 0014, 0027, 0032): native Compose screens on the Nim core
// (src/main/jniLibs/<abi>/libkks.so, built by ../nim/build.sh). Installed next to the v1 app until the cutover.
plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val appVersion = rootDir.parentFile.resolve("VERSION").readText().trim()
val appVersionCode = appVersion.split('.').map { it.toInt() }.let { (a, b, c) -> a * 10000 + b * 100 + c }

android {
    namespace = "kks.explorer.v2"
    compileSdk = 36
    defaultConfig {
        applicationId = "io.github.walkdown"
        minSdk = 29
        targetSdk = 36
        versionCode = appVersionCode
        versionName = "$appVersion-v2"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake {
                arguments += listOf("-DLIBJXL_SRC=${layout.buildDirectory.dir("third_party/libjxl").get().asFile}",
                    "-DZXING_SRC=${layout.buildDirectory.dir("third_party/zxing-cpp").get().asFile}",
                    "-DCMAKE_BUILD_TYPE=Release", "-DANDROID_STL=c++_static")
            }
        }
    }
    // Release signing: the maintainer's key, never in the repository or CI (as the v1 app; docs/ANDROID_RELEASE.md).
    // keystore.properties through $KKS_SIGNING or ~/.config/kks-explorer/signing/; without it the release is unsigned.
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
            isMinifyEnabled = true
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
// zxing-cpp (QR codes: drawing the invite, reading it from the camera; decision 0019), pinned the same way
val zxingSrc = layout.buildDirectory.dir("third_party/zxing-cpp")
val fetchZxing by tasks.registering {
    val url = "https://codeload.github.com/zxing-cpp/zxing-cpp/tar.gz/v3.1.1"
    val sha = "7286b1e6ade66fe82b7c8208b4595deeb55d6486b410834fdc65702f46650542"
    val dl = layout.buildDirectory.dir("third_party/download").get().asFile
    val out = zxingSrc.get().asFile
    inputs.property("source", "$url $sha")
    outputs.dir(out)
    doLast {
        dl.mkdirs()
        out.deleteRecursively()
        val f = File(dl, "zxing-cpp.tar.gz")
        fun digest() = MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString("") { "%02x".format(it) }
        if (!f.exists() || digest() != sha) {
            logger.lifecycle("Downloading zxing-cpp")
            URI(url).toURL().openStream().use { i -> f.outputStream().use { i.copyTo(it) } }
            val got = digest()
            if (got != sha) { f.delete(); throw GradleException("zxing-cpp: SHA-256 $got, expected $sha") }
        }
        copy {
            from(tarTree(resources.gzip(f)))
            eachFile { relativePath = RelativePath(true, *relativePath.segments.drop(1).toTypedArray()) }
            includeEmptyDirs = false
            into(out)
        }
    }
}
tasks.configureEach { if (name.startsWith("configureCMake") || name.startsWith("buildCMake")) dependsOn(fetchLibjxl, fetchZxing) }


// the program's own data (KKS decode tables) ships in the app
val copyData by tasks.registering(Sync::class) {
    from(File(rootDir.parentFile, "data")) { include("kks.json", "courses/*.jxl", "courses/ppt.json", "courses/fnd.json", "courses/hrsg.json") }
    into(layout.buildDirectory.dir("assets/data"))
}
// the course faces as TTF (Android's Typeface can't read the vendored WOFF2; tools/build_courses.py --ttf)
val copyFonts by tasks.registering(Sync::class) {
    from(File(rootDir.parentFile, "vendor/fonts/ttf")) { include("*.ttf") }
    into(layout.buildDirectory.dir("assets/fonts"))
}
android.sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("assets"))
tasks.named("preBuild") { dependsOn(copyData, copyFonts) }

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}
