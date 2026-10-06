// Walkdown for Android (app2: Compose screens on the Nim core through JNI, decision 0032). The old KKS Explorer
// modules (app, core) were removed on 2026-10-03; they stay in git history.
// The plugins' classpath is locked in buildscript-gradle.lockfile, like app2's dependencies in its gradle.lockfile.
buildscript {
    dependencyLocking { lockAllConfigurations() }
    // Tool libraries that the Android Gradle plugin and lint bring in at versions with published advisories
    // (osv-scanner over the lockfiles, 2026-10-05), raised to the first fixed release in the same line. Never
    // lowers a version; the lockfiles record the result.
    val patched = mapOf(
        "org.bouncycastle:bcprov-jdk18on" to "1.85", "org.bouncycastle:bcpkix-jdk18on" to "1.85",
        "org.bouncycastle:bcutil-jdk18on" to "1.85", "org.apache.commons:commons-lang3" to "3.18.0",
        "org.jdom:jdom2" to "2.0.6.1", "org.bitbucket.b_c:jose4j" to "0.9.6",
        "org.apache.httpcomponents:httpclient" to "4.5.14")
    fun older(a: String, b: String): Boolean {
        val x = a.split('.', '-').map { it.toIntOrNull() ?: 0 }; val y = b.split('.', '-').map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(x.size, y.size)) { val d = x.getOrElse(i) { 0 } - y.getOrElse(i) { 0 }; if (d != 0) return d < 0 }
        return false
    }
    configurations.classpath {
        resolutionStrategy.eachDependency {
            val fix = patched["${requested.group}:${requested.name}"]
            if (fix != null && requested.version != null && older(requested.version!!, fix)) { useVersion(fix); because("published advisories") }
        }
    }
}
plugins {
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.20" apply false
    id("com.android.application") version "9.4.1" apply false
}
