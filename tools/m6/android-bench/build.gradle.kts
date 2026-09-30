// Throwaway M6 measurement app (docs/decisions/0015): Android PdfRenderer vs Canvas drawing of grid-indexed paths.
plugins { id("com.android.application") version "8.13.2" }
android {
    namespace = "kks.bench"
    compileSdk = 36
    defaultConfig { applicationId = "kks.bench"; minSdk = 29; targetSdk = 36; versionCode = 1; versionName = "1" }
    androidResources { noCompress += listOf("pdf", "kkg") }
}
