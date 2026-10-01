/* The Windows crypto provider's C half (decisions 0029, 0033): CNG (bcrypt) for the primitives, NCrypt for keys that
 * live in a key storage provider. Every function returns 0 on success, else a nonzero status. Windows 10 or later
 * (pseudo algorithm handles, BCryptHash). */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <ncrypt.h>
#include <string.h>

#define OK(s) ((s) >= 0)

int kks_sha256(const unsigned char *data, unsigned long n, unsigned char out[32]) {
    return BCryptHash(BCRYPT_SHA256_ALG_HANDLE, NULL, 0, (PUCHAR)data, n, out, 32) < 0;
}

int kks_hmac_sha256(const unsigned char *key, unsigned long kn, const unsigned char *data, unsigned long n,
                    unsigned char out[32]) {
    /* an empty key is allowed by HMAC; CNG wants a non-null pointer */
    static unsigned char zero = 0;
    return BCryptHash(BCRYPT_HMAC_SHA256_ALG_HANDLE, kn ? (PUCHAR)key : &zero, kn, (PUCHAR)data, n, out, 32) < 0;
}

int kks_pbkdf2_sha256(const unsigned char *pw, unsigned long pn, const unsigned char *salt, unsigned long sn,
                      unsigned long long iter, unsigned char *out, unsigned long outn) {
    static unsigned char zero = 0;
    return BCryptDeriveKeyPBKDF2(BCRYPT_HMAC_SHA256_ALG_HANDLE, pn ? (PUCHAR)pw : &zero, pn, sn ? (PUCHAR)salt : &zero, sn,
                                 iter, out, outn, 0) < 0;
}

int kks_random(unsigned char *out, unsigned long n) {
    return BCryptGenRandom(NULL, out, n, BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0;
}

/* ---------------------------------------------------------------- P-256 */

static BCRYPT_ALG_HANDLE alg(LPCWSTR name) {
    BCRYPT_ALG_HANDLE h = NULL;
    if (!OK(BCryptOpenAlgorithmProvider(&h, name, NULL, 0))) return NULL;
    return h;
}

/* pub: 65-byte uncompressed point; d: 32-byte scalar or NULL */
static BCRYPT_KEY_HANDLE import_key(BCRYPT_ALG_HANDLE a, int ecdh, const unsigned char *pub, const unsigned char *d) {
    unsigned char blob[sizeof(BCRYPT_ECCKEY_BLOB) + 96];
    BCRYPT_ECCKEY_BLOB *h = (BCRYPT_ECCKEY_BLOB *)blob;
    h->cbKey = 32;
    if (d) h->dwMagic = ecdh ? BCRYPT_ECDH_PRIVATE_P256_MAGIC : BCRYPT_ECDSA_PRIVATE_P256_MAGIC;
    else h->dwMagic = ecdh ? BCRYPT_ECDH_PUBLIC_P256_MAGIC : BCRYPT_ECDSA_PUBLIC_P256_MAGIC;
    memcpy(blob + sizeof(*h), pub + 1, 64);
    if (d) memcpy(blob + sizeof(*h) + 64, d, 32);
    BCRYPT_KEY_HANDLE k = NULL;
    NTSTATUS s = BCryptImportKeyPair(a, NULL, d ? BCRYPT_ECCPRIVATE_BLOB : BCRYPT_ECCPUBLIC_BLOB, &k, blob,
                                     sizeof(*h) + (d ? 96 : 64), 0);
    SecureZeroMemory(blob, sizeof blob);
    return OK(s) ? k : NULL;
}

/* 1 if pub is a valid P-256 point (CNG validates the point on import) */
int kks_p256_valid(const unsigned char *pub) {
    if (pub[0] != 4) return 0;
    BCRYPT_ALG_HANDLE a = alg(BCRYPT_ECDSA_P256_ALGORITHM);
    if (!a) return 0;
    BCRYPT_KEY_HANDLE k = import_key(a, 0, pub, NULL);
    if (k) BCryptDestroyKey(k);
    BCryptCloseAlgorithmProvider(a, 0);
    return k != NULL;
}

int kks_p256_generate(unsigned char pub[65], unsigned char d[32]) {
    BCRYPT_ALG_HANDLE a = alg(BCRYPT_ECDSA_P256_ALGORITHM);
    if (!a) return 1;
    BCRYPT_KEY_HANDLE k = NULL;
    int rc = 1;
    if (OK(BCryptGenerateKeyPair(a, &k, 256, 0)) && OK(BCryptFinalizeKeyPair(k, 0))) {
        unsigned char blob[sizeof(BCRYPT_ECCKEY_BLOB) + 96];
        ULONG got = 0;
        if (OK(BCryptExportKey(k, NULL, BCRYPT_ECCPRIVATE_BLOB, blob, sizeof blob, &got, 0)) && got == sizeof blob) {
            pub[0] = 4;
            memcpy(pub + 1, blob + sizeof(BCRYPT_ECCKEY_BLOB), 64);
            memcpy(d, blob + sizeof(BCRYPT_ECCKEY_BLOB) + 64, 32);
            rc = 0;
        }
        SecureZeroMemory(blob, sizeof blob);
    }
    if (k) BCryptDestroyKey(k);
    BCryptCloseAlgorithmProvider(a, 0);
    return rc;
}

/* ECDSA-SHA256 over msg → r ‖ s */
int kks_p256_sign(const unsigned char *pub, const unsigned char *d, const unsigned char *msg, unsigned long n,
                  unsigned char sig[64]) {
    unsigned char h[32];
    if (kks_sha256(msg, n, h)) return 1;
    BCRYPT_ALG_HANDLE a = alg(BCRYPT_ECDSA_P256_ALGORITHM);
    if (!a) return 1;
    BCRYPT_KEY_HANDLE k = import_key(a, 0, pub, d);
    ULONG got = 0;
    int rc = !(k && OK(BCryptSignHash(k, NULL, h, 32, sig, 64, &got, 0)) && got == 64);
    if (k) BCryptDestroyKey(k);
    BCryptCloseAlgorithmProvider(a, 0);
    return rc;
}

int kks_p256_verify(const unsigned char *pub, const unsigned char *msg, unsigned long n, const unsigned char sig[64]) {
    unsigned char h[32];
    if (pub[0] != 4 || kks_sha256(msg, n, h)) return 0;
    BCRYPT_ALG_HANDLE a = alg(BCRYPT_ECDSA_P256_ALGORITHM);
    if (!a) return 0;
    BCRYPT_KEY_HANDLE k = import_key(a, 0, pub, NULL);
    int ok = k && OK(BCryptVerifySignature(k, NULL, h, 32, (PUCHAR)sig, 64, 0));
    if (k) BCryptDestroyKey(k);
    BCryptCloseAlgorithmProvider(a, 0);
    return ok;
}

/* the x coordinate of d·peer. CNG's raw secret ("TRUNCATE") comes out little-endian: reversed here. */
int kks_p256_ecdh(const unsigned char *pub, const unsigned char *d, const unsigned char *peer, unsigned char out[32]) {
    BCRYPT_ALG_HANDLE a = alg(BCRYPT_ECDH_P256_ALGORITHM);
    if (!a) return 1;
    BCRYPT_KEY_HANDLE k = import_key(a, 1, pub, d), p = import_key(a, 1, peer, NULL);
    BCRYPT_SECRET_HANDLE s = NULL;
    int rc = 1;
    if (k && p && OK(BCryptSecretAgreement(k, p, &s, 0))) {
        unsigned char raw[32];
        ULONG got = 0;
        if (OK(BCryptDeriveKey(s, BCRYPT_KDF_RAW_SECRET, NULL, raw, 32, &got, 0)) && got == 32) {
            for (int i = 0; i < 32; i++) out[i] = raw[31 - i];
            rc = 0;
        }
        SecureZeroMemory(raw, sizeof raw);
    }
    if (s) BCryptDestroySecret(s);
    if (k) BCryptDestroyKey(k);
    if (p) BCryptDestroyKey(p);
    BCryptCloseAlgorithmProvider(a, 0);
    return rc;
}

/* ---------------------------------------------------------------- AES-256-GCM */

static int gcm(int seal, const unsigned char *key, const unsigned char *nonce, const unsigned char *in, unsigned long n,
               const unsigned char *aad, unsigned long an, unsigned char *out, unsigned char tag[16]) {
    BCRYPT_ALG_HANDLE a = alg(BCRYPT_AES_ALGORITHM);
    if (!a) return 1;
    int rc = 1;
    BCRYPT_KEY_HANDLE k = NULL;
    if (OK(BCryptSetProperty(a, BCRYPT_CHAINING_MODE, (PUCHAR)BCRYPT_CHAIN_MODE_GCM, sizeof(BCRYPT_CHAIN_MODE_GCM), 0)) &&
        OK(BCryptGenerateSymmetricKey(a, &k, NULL, 0, (PUCHAR)key, 32, 0))) {
        BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
        BCRYPT_INIT_AUTH_MODE_INFO(info);
        info.pbNonce = (PUCHAR)nonce; info.cbNonce = 12;
        info.pbAuthData = an ? (PUCHAR)aad : NULL; info.cbAuthData = an;
        info.pbTag = tag; info.cbTag = 16;
        ULONG got = 0;
        NTSTATUS s = seal ? BCryptEncrypt(k, (PUCHAR)in, n, &info, NULL, 0, out, n, &got, 0)
                          : BCryptDecrypt(k, (PUCHAR)in, n, &info, NULL, 0, out, n, &got, 0);
        rc = !(OK(s) && got == n);
    }
    if (k) BCryptDestroyKey(k);
    BCryptCloseAlgorithmProvider(a, 0);
    return rc;
}

int kks_gcm_seal(const unsigned char *key, const unsigned char *nonce, const unsigned char *plain, unsigned long n,
                 const unsigned char *aad, unsigned long an, unsigned char *out /* n + 16 */) {
    return gcm(1, key, nonce, plain, n, aad, an, out, out + n);
}

int kks_gcm_open(const unsigned char *key, const unsigned char *nonce, const unsigned char *sealed, unsigned long n,
                 const unsigned char *aad, unsigned long an, unsigned char *out /* n - 16 */) {
    unsigned char tag[16];
    memcpy(tag, sealed + n - 16, 16);
    return gcm(0, key, nonce, sealed, n - 16, aad, an, out, tag);
}

/* ---------------------------------------------------------------- keys in a key storage provider (NCrypt) */

static NCRYPT_KEY_HANDLE open_named(const wchar_t *provider, const wchar_t *name) {
    NCRYPT_PROV_HANDLE p = 0;
    NCRYPT_KEY_HANDLE k = 0;
    if (NCryptOpenStorageProvider(&p, provider, 0) != ERROR_SUCCESS) return 0;
    if (NCryptOpenKey(p, &k, name, 0, 0) != ERROR_SUCCESS) k = 0;
    NCryptFreeObject(p);
    return k;
}

/* provider: 0 = Microsoft Software KSP, 1 = Microsoft Platform Crypto Provider (TPM).
 * Creates the named, non-exportable P-256 key if it doesn't exist; returns its public point. */
int kks_ncrypt_key(int provider, const wchar_t *name, unsigned char pub[65]) {
    const wchar_t *prov = provider ? MS_PLATFORM_CRYPTO_PROVIDER : MS_KEY_STORAGE_PROVIDER;
    NCRYPT_KEY_HANDLE k = open_named(prov, name);
    if (!k) {
        NCRYPT_PROV_HANDLE p = 0;
        if (NCryptOpenStorageProvider(&p, prov, 0) != ERROR_SUCCESS) return 1;
        SECURITY_STATUS s = NCryptCreatePersistedKey(p, &k, BCRYPT_ECDSA_P256_ALGORITHM, name, 0, 0);
        if (s == ERROR_SUCCESS) {
            DWORD policy = 0;          /* not exportable */
            NCryptSetProperty(k, NCRYPT_EXPORT_POLICY_PROPERTY, (PBYTE)&policy, sizeof policy, NCRYPT_PERSIST_FLAG);
            s = NCryptFinalizeKey(k, 0);
        }
        NCryptFreeObject(p);
        if (s != ERROR_SUCCESS) { if (k) NCryptFreeObject(k); return 2; }
    }
    unsigned char blob[sizeof(BCRYPT_ECCKEY_BLOB) + 64];
    DWORD got = 0;
    SECURITY_STATUS s = NCryptExportKey(k, 0, BCRYPT_ECCPUBLIC_BLOB, NULL, blob, sizeof blob, &got, 0);
    NCryptFreeObject(k);
    if (s != ERROR_SUCCESS || got != sizeof blob) return 3;
    pub[0] = 4;
    memcpy(pub + 1, blob + sizeof(BCRYPT_ECCKEY_BLOB), 64);
    return 0;
}

int kks_ncrypt_sign(int provider, const wchar_t *name, const unsigned char *msg, unsigned long n, unsigned char sig[64]) {
    unsigned char h[32];
    if (kks_sha256(msg, n, h)) return 1;
    NCRYPT_KEY_HANDLE k = open_named(provider ? MS_PLATFORM_CRYPTO_PROVIDER : MS_KEY_STORAGE_PROVIDER, name);
    if (!k) return 2;
    DWORD got = 0;
    SECURITY_STATUS s = NCryptSignHash(k, NULL, h, 32, sig, 64, &got, 0);
    NCryptFreeObject(k);
    return !(s == ERROR_SUCCESS && got == 64);
}

int kks_ncrypt_delete(int provider, const wchar_t *name) {
    NCRYPT_KEY_HANDLE k = open_named(provider ? MS_PLATFORM_CRYPTO_PROVIDER : MS_KEY_STORAGE_PROVIDER, name);
    if (!k) return 0;
    return NCryptDeleteKey(k, 0) != ERROR_SUCCESS;
}
