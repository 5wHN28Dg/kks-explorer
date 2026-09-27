# R8 rules for the release build (the defaults in proguard-android-optimize.txt keep native method names).

# The web pages call these through window.KKSNative: names must survive.
-keepclassmembers class kks.explorer.WebHost$Bridge {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface

# JNI: libkksjxl looks up kks.explorer.Jxl's natives by name.
-keep class kks.explorer.Jxl { native <methods>; }

# WorkManager instantiates the worker by class name (its consumer rules cover ListenableWorker subclasses; be explicit).
-keep class kks.explorer.SyncWorker { <init>(...); }

# BouncyCastle lightweight crypto (Ed25519, X25519): plain classes, no reflection in the parts used; the rest is
# shrunk away. It references JDK classes Android doesn't have in code paths never taken here.
-dontwarn org.bouncycastle.**
-dontwarn javax.naming.**
