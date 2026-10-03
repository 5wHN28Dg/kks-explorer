/* JNI for the Nim core (decision 0032). The Kotlin side calls these from one thread ("kks-core"); the core calls back
   into Kotlin for crypto (NativeCrypto.call) and change notices (Core.changed). Strings cross as UTF-8 byte arrays
   (JNI's NewStringUTF wants modified UTF-8, which breaks characters outside the BMP). */
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static JavaVM *g_vm;
static JNIEnv *g_env;                 /* the env of the call in progress (always the core thread) */
static jclass g_crypto, g_core;
static jmethodID m_crypto_call, m_core_changed;

extern void NimMain(void);
/* in Nim (kks_jni.nim) */
extern int64_t kks_open(const char *dir, const uint8_t *key, int keylen, const char *handle, const uint8_t *pub, int publen,
                        const char *label, char **err);
extern uint8_t *kks_api(int64_t h, const char *meth, const char *path, const uint8_t *query, int qlen, const uint8_t *body,
                        int blen, int *outlen);
extern uint8_t *kks_file(int64_t h, const char *path, int *outlen);
extern int64_t kks_sync_start(int64_t h, int initiator, const char *remote, const char *adopt_root);
extern uint8_t *kks_sync_feed(int64_t s, const uint8_t *data, int len, int *outlen);
extern uint8_t *kks_sync_info(int64_t s, int *outlen);
extern void kks_sync_end(int64_t s);
extern void kks_free(void *p);
extern uint8_t *kks_sheet(int64_t h, const char *id, int *outlen);
extern int64_t kks_rudp_new(const uint8_t *session, double dead, double now);
extern uint8_t *kks_rudp_step(int64_t id, int op, const uint8_t *data, int len, double now, int *outlen);
extern uint8_t *kks_fig(int64_t h, int id, const char *cmd, int *outlen);

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved)
{
	g_vm = vm;
	JNIEnv *env;
	if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
	jclass c = (*env)->FindClass(env, "kks/explorer/core/NativeCrypto");
	if (!c) return JNI_ERR;
	g_crypto = (*env)->NewGlobalRef(env, c);
	m_crypto_call = (*env)->GetStaticMethodID(env, g_crypto, "call", "(I[B[B[B[BII)[B");
	jclass k = (*env)->FindClass(env, "kks/explorer/core/Core");
	if (!k) return JNI_ERR;
	g_core = (*env)->NewGlobalRef(env, k);
	m_core_changed = (*env)->GetStaticMethodID(env, g_core, "changed", "([B)V");
	if (!m_crypto_call || !m_core_changed) return JNI_ERR;
	return JNI_VERSION_1_6;
}

/* Nim's runtime is set up on the thread that will make every call (the Kotlin "kks-core" thread): on Android Nim
   emulates thread-local storage, so the thread that ran NimMain is the one that may run Nim code. */
JNIEXPORT void JNICALL Java_kks_explorer_core_Core_nInit(JNIEnv *env, jclass cls)
{
	static int done = 0;
	g_env = env;
	if (!done) { NimMain(); done = 1; }
}

static jbyteArray bytes(JNIEnv *env, const uint8_t *p, int n)
{
	if (!p) return NULL;
	jbyteArray a = (*env)->NewByteArray(env, n);
	if (a && n) (*env)->SetByteArrayRegion(env, a, 0, n, (const jbyte *)p);
	return a;
}

static uint8_t *copy_bytes(JNIEnv *env, jbyteArray a, int *n)
{
	if (!a) { *n = 0; return NULL; }
	*n = (*env)->GetArrayLength(env, a);
	uint8_t *p = malloc(*n ? *n : 1);
	(*env)->GetByteArrayRegion(env, a, 0, *n, (jbyte *)p);
	return p;
}

static char *copy_utf8(JNIEnv *env, jbyteArray a)   /* a UTF-8 byte array → NUL-terminated C string */
{
	int n;
	uint8_t *p = copy_bytes(env, a, &n);
	char *s = realloc(p, n + 1);
	s[n] = 0;
	return s;
}

/* ---------------------------------------------------------------- the core calls Kotlin */

/* NativeCrypto.call(op, a, b, c, d, n1, n2) → malloc'd bytes (*outlen) or NULL */
uint8_t *kks_jc_call(int op, const uint8_t *a, int alen, const uint8_t *b, int blen, const uint8_t *c, int clen,
                     const uint8_t *d, int dlen, int n1, int n2, int *outlen)
{
	JNIEnv *env = g_env;
	jbyteArray ja = bytes(env, a, alen), jb = bytes(env, b, blen), jc = bytes(env, c, clen), jd = bytes(env, d, dlen);
	jbyteArray r = (*env)->CallStaticObjectMethod(env, g_crypto, m_crypto_call, op, ja, jb, jc, jd, n1, n2);
	if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); r = NULL; }
	uint8_t *out = r ? copy_bytes(env, r, outlen) : NULL;
	if (ja) (*env)->DeleteLocalRef(env, ja);
	if (jb) (*env)->DeleteLocalRef(env, jb);
	if (jc) (*env)->DeleteLocalRef(env, jc);
	if (jd) (*env)->DeleteLocalRef(env, jd);
	if (r) (*env)->DeleteLocalRef(env, r);
	return out;
}

void kks_jc_changed(const char *why)
{
	JNIEnv *env = g_env;
	if (!env) return;
	jbyteArray a = bytes(env, (const uint8_t *)why, (int)strlen(why));
	(*env)->CallStaticVoidMethod(env, g_core, m_core_changed, a);
	if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
	(*env)->DeleteLocalRef(env, a);
}

/* ---------------------------------------------------------------- Kotlin calls the core */

JNIEXPORT jlong JNICALL Java_kks_explorer_core_Core_nOpen(JNIEnv *env, jclass cls, jbyteArray dir, jbyteArray key,
                                                          jbyteArray handle, jbyteArray pub, jbyteArray label)
{
	g_env = env;
	int klen, plen;
	char *d = copy_utf8(env, dir), *h = copy_utf8(env, handle), *l = copy_utf8(env, label), *err = NULL;
	uint8_t *k = copy_bytes(env, key, &klen), *p = copy_bytes(env, pub, &plen);
	int64_t r = kks_open(d, k, klen, h, p, plen, l, &err);
	free(d); free(h); free(l); free(k); free(p);
	if (!r) {
		jclass ex = (*env)->FindClass(env, "java/lang/IllegalStateException");
		(*env)->ThrowNew(env, ex, err ? err : "the core could not open");
	}
	if (err) kks_free(err);
	return (jlong)r;
}

JNIEXPORT jbyteArray JNICALL Java_kks_explorer_core_Core_nApi(JNIEnv *env, jclass cls, jlong h, jbyteArray meth,
                                                              jbyteArray path, jbyteArray query, jbyteArray body)
{
	g_env = env;
	int qlen, blen, outlen = 0;
	char *m = copy_utf8(env, meth), *p = copy_utf8(env, path);
	uint8_t *q = copy_bytes(env, query, &qlen), *b = copy_bytes(env, body, &blen);
	uint8_t *out = kks_api(h, m, p, q, qlen, b, blen, &outlen);
	free(m); free(p); free(q); free(b);
	jbyteArray r = bytes(env, out, outlen);
	kks_free(out);
	return r;
}

JNIEXPORT jbyteArray JNICALL Java_kks_explorer_core_Core_nFile(JNIEnv *env, jclass cls, jlong h, jbyteArray path)
{
	g_env = env;
	int outlen = 0;
	char *p = copy_utf8(env, path);
	uint8_t *out = kks_file(h, p, &outlen);
	free(p);
	jbyteArray r = out ? bytes(env, out, outlen) : NULL;
	if (out) kks_free(out);
	return r;
}

JNIEXPORT jlong JNICALL Java_kks_explorer_core_Core_nSyncStart(JNIEnv *env, jclass cls, jlong h, jboolean initiator,
                                                               jbyteArray remote, jbyteArray adopt)
{
	g_env = env;
	char *r = copy_utf8(env, remote), *a = copy_utf8(env, adopt);
	int64_t s = kks_sync_start(h, initiator ? 1 : 0, r, a);
	free(r); free(a);
	return (jlong)s;
}

JNIEXPORT jbyteArray JNICALL Java_kks_explorer_core_Core_nSyncFeed(JNIEnv *env, jclass cls, jlong s, jbyteArray data)
{
	g_env = env;
	int n, outlen = 0;
	uint8_t *d = copy_bytes(env, data, &n);
	uint8_t *out = kks_sync_feed(s, d, n, &outlen);
	free(d);
	jbyteArray r = bytes(env, out, outlen);
	kks_free(out);
	return r;
}

JNIEXPORT jbyteArray JNICALL Java_kks_explorer_core_Core_nSyncInfo(JNIEnv *env, jclass cls, jlong s)
{
	g_env = env;
	int outlen = 0;
	uint8_t *out = kks_sync_info(s, &outlen);
	jbyteArray r = bytes(env, out, outlen);
	kks_free(out);
	return r;
}

JNIEXPORT void JNICALL Java_kks_explorer_core_Core_nSyncEnd(JNIEnv *env, jclass cls, jlong s)
{
	g_env = env;
	kks_sync_end(s);
}

JNIEXPORT jbyteArray JNICALL Java_kks_explorer_core_Core_nSheet(JNIEnv *env, jclass cls, jlong h, jbyteArray id)
{
	g_env = env;
	int outlen = 0;
	char *i = copy_utf8(env, id);
	uint8_t *out = kks_sheet(h, i, &outlen);
	free(i);
	jbyteArray r = out ? bytes(env, out, outlen) : NULL;
	if (out) kks_free(out);
	return r;
}

JNIEXPORT jbyteArray JNICALL Java_kks_explorer_core_Core_nFig(JNIEnv *env, jclass cls, jlong h, jint id, jbyteArray cmd)
{
	g_env = env;
	int outlen = 0;
	char *c = copy_utf8(env, cmd);
	uint8_t *out = kks_fig(h, id, c, &outlen);
	free(c);
	jbyteArray r = out ? bytes(env, out, outlen) : NULL;
	if (out) kks_free(out);
	return r;
}

/* the reliable UDP stream of the direct path (PROTOCOL-v2 §18): Kotlin owns the socket (sync/Direct.kt) */
JNIEXPORT jlong JNICALL Java_kks_explorer_core_Core_nRudpNew(JNIEnv *env, jclass cls, jbyteArray session, jdouble dead, jdouble now)
{
	g_env = env;
	int n;
	uint8_t *s = copy_bytes(env, session, &n);
	int64_t id = n == 8 ? kks_rudp_new(s, dead, now) : 0;
	free(s);
	return (jlong)id;
}

JNIEXPORT jbyteArray JNICALL Java_kks_explorer_core_Core_nRudpStep(JNIEnv *env, jclass cls, jlong id, jint op, jbyteArray data,
                                                                   jdouble now)
{
	g_env = env;
	int n, outlen = 0;
	uint8_t *d = copy_bytes(env, data, &n);
	uint8_t *out = kks_rudp_step(id, op, d, n, now, &outlen);
	free(d);
	jbyteArray r = bytes(env, out, outlen);
	kks_free(out);
	return r;
}
