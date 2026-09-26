import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins { kotlin("jvm") }

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }

dependencies {
    // Ed25519, X25519, ChaCha20-Poly1305: not all in Android 10's platform crypto, so from BouncyCastle (lightweight API)
    implementation("org.bouncycastle:bcprov-jdk18on:1.79")
    testImplementation(kotlin("test"))
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    useJUnit()
    systemProperty("kks.repo", rootDir.parentFile.absolutePath)   // the vectors live in ../peer/vectors
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
