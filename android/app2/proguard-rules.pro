# the core calls these from C (jni_shim.c): keep names and signatures
-keep class kks.explorer.core.NativeCrypto { public static byte[] call(int, byte[], byte[], byte[], byte[], int, int); }
-keep class kks.explorer.core.Core { static void changed(byte[]); native <methods>; }
-keep class kks.explorer.Jxl { native <methods>; }
