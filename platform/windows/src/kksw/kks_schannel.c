/* Sync connections over Schannel (decisions 0017, 0033), driven through buffers like platform/linux/tls.nim: the
 * caller moves ciphertext between the socket and feed()/take_out(), plaintext through send()/recv(). Our trust
 * decision is the peer ID (PROTOCOL-v2 §15), so Schannel's own certificate validation is switched off
 * (SCH_CRED_MANUAL_CRED_VALIDATION) and the caller checks the peer's P-256 key. TLS 1.3 where Windows has it (11),
 * else 1.2 (Windows 10). ALPN "kks-sync/2" is required. The device certificate is self-signed for a key in a CNG key
 * storage provider, so the private key never leaves it. */
#define WIN32_LEAN_AND_MEAN
#define SECURITY_WIN32
#define SCHANNEL_USE_BLACKLISTS
#include <windows.h>
#include <winternl.h>
#include <wincrypt.h>
#include <ncrypt.h>
#include <sspi.h>
#include <schannel.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define ALPN "kks-sync/2"

/* ---------------------------------------------------------------- identity: a self-signed certificate */

typedef struct kks_identity {
    PCCERT_CONTEXT cert;
    CredHandle out_cred, in_cred;      /* client side, server side */
    int have_out, have_in;
} kks_identity;

static void set_err(char *err, size_t n, const char *what, long code) {
    if (err && n) snprintf(err, n, "%s (0x%08lx)", what, (unsigned long)code);
}

static int acquire(kks_identity *id, int client, CredHandle *h, char *err, size_t en) {
    TLS_PARAMETERS tp;
    memset(&tp, 0, sizeof tp);
    /* everything but TLS 1.2 and 1.3 disabled */
    tp.grbitDisabledProtocols = (DWORD)~(SP_PROT_TLS1_2_CLIENT | SP_PROT_TLS1_2_SERVER | SP_PROT_TLS1_3_CLIENT | SP_PROT_TLS1_3_SERVER);
    SCH_CREDENTIALS sc;
    memset(&sc, 0, sizeof sc);
    sc.dwVersion = SCH_CREDENTIALS_VERSION;
    sc.cCreds = 1;
    sc.paCred = &id->cert;
    sc.cTlsParameters = 1;
    sc.pTlsParameters = &tp;
    sc.dwFlags = client ? (SCH_CRED_MANUAL_CRED_VALIDATION | SCH_CRED_NO_DEFAULT_CREDS | SCH_CRED_NO_SERVERNAME_CHECK | SCH_USE_STRONG_CRYPTO)
                        : (SCH_CRED_NO_SYSTEM_MAPPER | SCH_USE_STRONG_CRYPTO);
    TimeStamp exp;
    SECURITY_STATUS s = AcquireCredentialsHandleW(NULL, (LPWSTR)UNISP_NAME_W, client ? SECPKG_CRED_OUTBOUND : SECPKG_CRED_INBOUND,
                                                  NULL, &sc, NULL, NULL, h, &exp);
    if (s != SEC_E_OK) { set_err(err, en, "AcquireCredentialsHandle", s); return 1; }
    return 0;
}

/* keyName: a persisted key in the provider (0 = software KSP, 1 = TPM) */
kks_identity *kks_identity_new(const wchar_t *keyName, int tpm, char *err, size_t en) {
    NCRYPT_PROV_HANDLE prov = 0;
    NCRYPT_KEY_HANDLE key = 0;
    const wchar_t *provName = tpm ? MS_PLATFORM_CRYPTO_PROVIDER : MS_KEY_STORAGE_PROVIDER;
    SECURITY_STATUS s = NCryptOpenStorageProvider(&prov, provName, 0);
    if (s == ERROR_SUCCESS) s = NCryptOpenKey(prov, &key, keyName, 0, 0);
    if (s != ERROR_SUCCESS) { set_err(err, en, "NCryptOpenKey", s); if (prov) NCryptFreeObject(prov); return NULL; }
    BYTE name[128];
    DWORD nlen = sizeof name;
    if (!CertStrToNameW(X509_ASN_ENCODING, L"CN=kks-device", CERT_X500_NAME_STR, NULL, name, &nlen, NULL)) {
        set_err(err, en, "CertStrToName", GetLastError()); NCryptFreeObject(key); NCryptFreeObject(prov); return NULL;
    }
    CERT_NAME_BLOB subject = { nlen, name };
    CRYPT_KEY_PROV_INFO kpi;
    memset(&kpi, 0, sizeof kpi);
    kpi.pwszContainerName = (LPWSTR)keyName;
    kpi.pwszProvName = (LPWSTR)provName;
    CRYPT_ALGORITHM_IDENTIFIER alg;
    memset(&alg, 0, sizeof alg);
    alg.pszObjId = szOID_ECDSA_SHA256;
    SYSTEMTIME start = {1971, 1, 0, 1, 0, 0, 0, 0}, end = {2999, 12, 0, 31, 0, 0, 0, 0};   /* dates are not checked (§15) */
    PCCERT_CONTEXT cert = CertCreateSelfSignCertificate((HCRYPTPROV_OR_NCRYPT_KEY_HANDLE)key, &subject, 0, &kpi, &alg,
                                                        &start, &end, NULL);
    DWORD le = GetLastError();
    NCryptFreeObject(key);
    NCryptFreeObject(prov);
    if (!cert) { set_err(err, en, "CertCreateSelfSignCertificate", le); return NULL; }
    kks_identity *id = calloc(1, sizeof *id);
    id->cert = cert;
    if (acquire(id, 1, &id->out_cred, err, en)) { CertFreeCertificateContext(cert); free(id); return NULL; }
    id->have_out = 1;
    if (acquire(id, 0, &id->in_cred, err, en)) { FreeCredentialsHandle(&id->out_cred); CertFreeCertificateContext(cert); free(id); return NULL; }
    id->have_in = 1;
    return id;
}

void kks_identity_free(kks_identity *id) {
    if (!id) return;
    if (id->have_out) FreeCredentialsHandle(&id->out_cred);
    if (id->have_in) FreeCredentialsHandle(&id->in_cred);
    if (id->cert) CertFreeCertificateContext(id->cert);
    free(id);
}

/* import a raw P-256 key (tests: identities made from known scalars) as a persisted software-KSP key */
int kks_ncrypt_import(const wchar_t *keyName, const unsigned char *pub, const unsigned char *d) {
    NCRYPT_PROV_HANDLE prov = 0;
    NCRYPT_KEY_HANDLE key = 0;
    if (NCryptOpenStorageProvider(&prov, MS_KEY_STORAGE_PROVIDER, 0) != ERROR_SUCCESS) return 1;
    if (NCryptOpenKey(prov, &key, keyName, 0, 0) == ERROR_SUCCESS) NCryptDeleteKey(key, 0);   /* replace */
    key = 0;
    unsigned char blob[sizeof(BCRYPT_ECCKEY_BLOB) + 96];
    BCRYPT_ECCKEY_BLOB *h = (BCRYPT_ECCKEY_BLOB *)blob;
    h->dwMagic = BCRYPT_ECDSA_PRIVATE_P256_MAGIC;
    h->cbKey = 32;
    memcpy(blob + sizeof *h, pub + 1, 64);
    memcpy(blob + sizeof *h + 64, d, 32);
    NCryptBuffer nb = { (ULONG)((wcslen(keyName) + 1) * sizeof(wchar_t)), NCRYPTBUFFER_PKCS_KEY_NAME, (PVOID)keyName };
    NCryptBufferDesc desc = { NCRYPTBUFFER_VERSION, 1, &nb };
    SECURITY_STATUS s = NCryptImportKey(prov, 0, BCRYPT_ECCPRIVATE_BLOB, &desc, &key, blob, sizeof blob, NCRYPT_OVERWRITE_KEY_FLAG);
    SecureZeroMemory(blob, sizeof blob);
    if (key) NCryptFreeObject(key);
    NCryptFreeObject(prov);
    return s != ERROR_SUCCESS;
}

/* ---------------------------------------------------------------- a connection */

typedef struct buf { unsigned char *p; size_t n, cap; } buf;

static void put(buf *b, const void *d, size_t n) {
    if (!n) return;
    if (b->n + n > b->cap) { b->cap = (b->n + n) * 2 + 4096; b->p = realloc(b->p, b->cap); }
    memcpy(b->p + b->n, d, n);
    b->n += n;
}
static void drop(buf *b, size_t n) {   /* remove the first n bytes */
    if (n >= b->n) { b->n = 0; return; }
    memmove(b->p, b->p + n, b->n - n);
    b->n -= n;
}

typedef struct kks_tls {
    kks_identity *id;
    int client, have_ctx, done, closed;
    CtxtHandle ctx;
    SecPkgContext_StreamSizes sizes;
    buf in, out, plain;
    char err[200];
} kks_tls;

kks_tls *kks_tls_new(kks_identity *id, int client) {
    kks_tls *c = calloc(1, sizeof *c);
    c->id = id;
    c->client = client;
    return c;
}

void kks_tls_free(kks_tls *c) {
    if (!c) return;
    if (c->have_ctx) DeleteSecurityContext(&c->ctx);
    free(c->in.p); free(c->out.p); free(c->plain.p);
    free(c);
}

const char *kks_tls_error(kks_tls *c) { return c->err; }
void kks_tls_feed(kks_tls *c, const unsigned char *d, size_t n) { put(&c->in, d, n); }

/* ciphertext to send: copies up to cap bytes, returns how many */
size_t kks_tls_take_out(kks_tls *c, unsigned char *dst, size_t cap) {
    size_t n = c->out.n < cap ? c->out.n : cap;
    memcpy(dst, c->out.p, n);
    drop(&c->out, n);
    return n;
}
size_t kks_tls_pending_out(kks_tls *c) { return c->out.n; }

static size_t alpn_buffer(unsigned char *b) {
    /* SEC_APPLICATION_PROTOCOLS { ProtocolListsSize; SEC_APPLICATION_PROTOCOL_LIST { ProtoNegoExt; ProtocolListSize; list } } */
    SEC_APPLICATION_PROTOCOLS *ap = (SEC_APPLICATION_PROTOCOLS *)b;
    SEC_APPLICATION_PROTOCOL_LIST *l = &ap->ProtocolLists[0];
    l->ProtoNegoExt = SecApplicationProtocolNegotiationExt_ALPN;
    unsigned char *p = l->ProtocolList;
    p[0] = (unsigned char)strlen(ALPN);
    memcpy(p + 1, ALPN, strlen(ALPN));
    l->ProtocolListSize = (unsigned short)(1 + strlen(ALPN));
    ap->ProtocolListsSize = (unsigned long)(offsetof(SEC_APPLICATION_PROTOCOL_LIST, ProtocolList) + l->ProtocolListSize);
    return offsetof(SEC_APPLICATION_PROTOCOLS, ProtocolLists) + ap->ProtocolListsSize;
}

#define ISC_FLAGS (ISC_REQ_SEQUENCE_DETECT | ISC_REQ_REPLAY_DETECT | ISC_REQ_CONFIDENTIALITY | ISC_REQ_ALLOCATE_MEMORY | \
                   ISC_REQ_STREAM | ISC_REQ_EXTENDED_ERROR | ISC_REQ_MANUAL_CRED_VALIDATION | ISC_REQ_USE_SUPPLIED_CREDS)
#define ASC_FLAGS (ASC_REQ_SEQUENCE_DETECT | ASC_REQ_REPLAY_DETECT | ASC_REQ_CONFIDENTIALITY | ASC_REQ_ALLOCATE_MEMORY | \
                   ASC_REQ_STREAM | ASC_REQ_EXTENDED_ERROR | ASC_REQ_MUTUAL_AUTH)

/* one handshake step over what has arrived (also used for post-handshake messages: TLS 1.3 tickets).
 * 1 = done, 0 = needs more data, -1 = failed (kks_tls_error) */
static int step(kks_tls *c) {
    unsigned char alpn[64];
    size_t alen = alpn_buffer(alpn);
    SecBuffer inb[3], outb[2];
    SecBufferDesc ind = { SECBUFFER_VERSION, 0, inb }, outd = { SECBUFFER_VERSION, 2, outb };
    int first = !c->have_ctx;
    if (!c->client && c->in.n == 0) return 0;              /* the server waits for the ClientHello */
    unsigned long n = 0;
    if (!(c->client && first)) {
        inb[n].BufferType = SECBUFFER_TOKEN; inb[n].pvBuffer = c->in.p; inb[n].cbBuffer = (unsigned long)c->in.n; n++;
        inb[n].BufferType = SECBUFFER_EMPTY; inb[n].pvBuffer = NULL; inb[n].cbBuffer = 0; n++;
    }
    if (first || !c->client) { inb[n].BufferType = SECBUFFER_APPLICATION_PROTOCOLS; inb[n].pvBuffer = alpn; inb[n].cbBuffer = (unsigned long)alen; n++; }
    ind.cBuffers = n;
    outb[0].BufferType = SECBUFFER_TOKEN; outb[0].pvBuffer = NULL; outb[0].cbBuffer = 0;
    outb[1].BufferType = SECBUFFER_ALERT; outb[1].pvBuffer = NULL; outb[1].cbBuffer = 0;
    unsigned long attrs = 0;
    SECURITY_STATUS s;
    if (c->client)
        s = InitializeSecurityContextW(&c->id->out_cred, first ? NULL : &c->ctx, (SEC_WCHAR *)L"kks-device", ISC_FLAGS, 0, 0,
                                       &ind, 0, first ? &c->ctx : NULL, &outd, &attrs, NULL);
    else
        s = AcceptSecurityContext(&c->id->in_cred, first ? NULL : &c->ctx, &ind, ASC_FLAGS, 0, first ? &c->ctx : NULL,
                                  &outd, &attrs, NULL);
    if (first && s >= 0) c->have_ctx = 1;          /* SEC_E_OK or SEC_I_*: the context exists now */
    if (outb[0].pvBuffer) { put(&c->out, outb[0].pvBuffer, outb[0].cbBuffer); FreeContextBuffer(outb[0].pvBuffer); }
    if (outb[1].pvBuffer) { put(&c->out, outb[1].pvBuffer, outb[1].cbBuffer); FreeContextBuffer(outb[1].pvBuffer); }
    if (s == SEC_E_INCOMPLETE_MESSAGE) return 0;
    if (s == SEC_E_OK || s == SEC_I_CONTINUE_NEEDED || s == SEC_I_INCOMPLETE_CREDENTIALS) {
        /* consumed all input except what Schannel reports as extra */
        size_t extra = 0;
        if (!(c->client && first)) for (unsigned long i = 0; i < n; i++) if (inb[i].BufferType == SECBUFFER_EXTRA) extra = inb[i].cbBuffer;
        if (!(c->client && first)) drop(&c->in, c->in.n - extra);
        if (s == SEC_E_OK) return 1;
        return 0;
    }
    set_err(c->err, sizeof c->err, c->client ? "InitializeSecurityContext" : "AcceptSecurityContext", s);
    return -1;
}

int kks_tls_handshake(kks_tls *c) {
    if (c->done) return 1;
    for (;;) {
        size_t before = c->in.n;
        int r = step(c);
        if (r < 0) return -1;
        if (r == 1) {
            if (QueryContextAttributesW(&c->ctx, SECPKG_ATTR_STREAM_SIZES, &c->sizes) != SEC_E_OK) {
                snprintf(c->err, sizeof c->err, "no stream sizes"); return -1;
            }
            SecPkgContext_ApplicationProtocol ap;
            memset(&ap, 0, sizeof ap);
            if (QueryContextAttributesW(&c->ctx, SECPKG_ATTR_APPLICATION_PROTOCOL, &ap) != SEC_E_OK ||
                ap.ProtoNegoStatus != SecApplicationProtocolNegotiationStatus_Success ||
                ap.ProtocolIdSize != strlen(ALPN) || memcmp(ap.ProtocolId, ALPN, strlen(ALPN)) != 0) {
                snprintf(c->err, sizeof c->err, "the other side doesn't speak " ALPN); return -1;
            }
            c->done = 1;
            return 1;
        }
        /* keep stepping while input is being consumed (several handshake messages in one read) */
        if (c->in.n == 0 || c->in.n == before) return 0;
    }
}

/* the peer's certificate key as a 65-byte uncompressed P-256 point; 0 on success */
int kks_tls_peer_key(kks_tls *c, unsigned char pub[65]) {
    PCCERT_CONTEXT pc = NULL;
    if (QueryContextAttributesW(&c->ctx, SECPKG_ATTR_REMOTE_CERT_CONTEXT, &pc) != SEC_E_OK || !pc) {
        snprintf(c->err, sizeof c->err, "no peer certificate"); return 1;
    }
    CERT_PUBLIC_KEY_INFO *ki = &pc->pCertInfo->SubjectPublicKeyInfo;
    int rc = 1;
    if (strcmp(ki->Algorithm.pszObjId, szOID_ECC_PUBLIC_KEY) == 0 && ki->PublicKey.cbData == 65 && ki->PublicKey.pbData[0] == 4 &&
        ki->Algorithm.Parameters.cbData == 10 &&   /* OID 1.2.840.10045.3.1.7 (P-256), DER-encoded */
        memcmp(ki->Algorithm.Parameters.pbData, "\x06\x08\x2a\x86\x48\xce\x3d\x03\x01\x07", 10) == 0) {
        memcpy(pub, ki->PublicKey.pbData, 65);
        rc = 0;
    } else snprintf(c->err, sizeof c->err, "not a P-256 key");
    CertFreeCertificateContext(pc);
    return rc;
}

int kks_tls_send(kks_tls *c, const unsigned char *d, size_t n) {
    while (n > 0) {
        size_t chunk = n < c->sizes.cbMaximumMessage ? n : c->sizes.cbMaximumMessage;
        size_t total = c->sizes.cbHeader + chunk + c->sizes.cbTrailer;
        unsigned char *m = malloc(total);
        memcpy(m + c->sizes.cbHeader, d, chunk);
        SecBuffer b[4] = {
            { c->sizes.cbHeader, SECBUFFER_STREAM_HEADER, m },
            { (unsigned long)chunk, SECBUFFER_DATA, m + c->sizes.cbHeader },
            { c->sizes.cbTrailer, SECBUFFER_STREAM_TRAILER, m + c->sizes.cbHeader + chunk },
            { 0, SECBUFFER_EMPTY, NULL } };
        SecBufferDesc desc = { SECBUFFER_VERSION, 4, b };
        SECURITY_STATUS s = EncryptMessage(&c->ctx, 0, &desc, 0);
        if (s != SEC_E_OK) { free(m); set_err(c->err, sizeof c->err, "EncryptMessage", s); return -1; }
        put(&c->out, m, b[0].cbBuffer + b[1].cbBuffer + b[2].cbBuffer);
        free(m);
        d += chunk; n -= chunk;
    }
    return 0;
}

/* decrypt what has arrived into the plaintext buffer; then copy up to cap bytes of it.
 * returns bytes copied (0 = nothing yet), -1 = error; sets closed when the other side said goodbye */
long kks_tls_recv(kks_tls *c, unsigned char *dst, size_t cap) {
    while (c->in.n > 0 && !c->closed) {
        SecBuffer b[4] = { { (unsigned long)c->in.n, SECBUFFER_DATA, c->in.p }, { 0, SECBUFFER_EMPTY, NULL },
                           { 0, SECBUFFER_EMPTY, NULL }, { 0, SECBUFFER_EMPTY, NULL } };
        SecBufferDesc desc = { SECBUFFER_VERSION, 4, b };
        SECURITY_STATUS s = DecryptMessage(&c->ctx, &desc, 0, NULL);
        if (s == SEC_E_INCOMPLETE_MESSAGE) break;
        if (s == SEC_I_CONTEXT_EXPIRED) { c->closed = 1; break; }
        if (s != SEC_E_OK && s != SEC_I_RENEGOTIATE) { set_err(c->err, sizeof c->err, "DecryptMessage", s); return -1; }
        size_t extra = 0;
        unsigned char *extrap = NULL;
        for (int i = 0; i < 4; i++) {
            if (b[i].BufferType == SECBUFFER_DATA && b[i].cbBuffer) put(&c->plain, b[i].pvBuffer, b[i].cbBuffer);
            if (b[i].BufferType == SECBUFFER_EXTRA) { extra = b[i].cbBuffer; extrap = b[i].pvBuffer; }
        }
        /* keep only the extra bytes (they sit at the end of the input buffer) */
        if (extra) { memmove(c->in.p, extrap, extra); c->in.n = extra; } else c->in.n = 0;
        if (s == SEC_I_RENEGOTIATE) {
            /* TLS 1.3 post-handshake message (a ticket, a key update): hand the extra bytes to the handshake */
            int r = step(c);
            if (r < 0) return -1;
        }
    }
    size_t n = c->plain.n < cap ? c->plain.n : cap;
    memcpy(dst, c->plain.p, n);
    drop(&c->plain, n);
    return (long)n;
}

int kks_tls_closed(kks_tls *c) { return c->closed; }

/* close_notify into the output buffer */
void kks_tls_shutdown(kks_tls *c) {
    if (!c->have_ctx || !c->done) return;
    DWORD type = SCHANNEL_SHUTDOWN;
    SecBuffer b = { sizeof type, SECBUFFER_TOKEN, &type };
    SecBufferDesc d = { SECBUFFER_VERSION, 1, &b };
    if (ApplyControlToken(&c->ctx, &d) != SEC_E_OK) return;
    SecBuffer o = { 0, SECBUFFER_TOKEN, NULL };
    SecBufferDesc od = { SECBUFFER_VERSION, 1, &o };
    unsigned long attrs = 0;
    if (c->client) InitializeSecurityContextW(&c->id->out_cred, &c->ctx, NULL, ISC_FLAGS, 0, 0, NULL, 0, NULL, &od, &attrs, NULL);
    else AcceptSecurityContext(&c->id->in_cred, &c->ctx, NULL, ASC_FLAGS, 0, NULL, &od, &attrs, NULL);
    if (o.pvBuffer) { put(&c->out, o.pvBuffer, o.cbBuffer); FreeContextBuffer(o.pvBuffer); }
}

/* the negotiated protocol: 0x3 = TLS 1.2, 0x4 = TLS 1.3, 0 = unknown (SECPKG_ATTR_CONNECTION_INFO) */
int kks_tls_version(kks_tls *c) {
    SecPkgContext_ConnectionInfo ci;
    if (!c->done || QueryContextAttributesW(&c->ctx, SECPKG_ATTR_CONNECTION_INFO, &ci) != SEC_E_OK) return 0;
    if (ci.dwProtocol & (SP_PROT_TLS1_3_CLIENT | SP_PROT_TLS1_3_SERVER)) return 4;
    if (ci.dwProtocol & (SP_PROT_TLS1_2_CLIENT | SP_PROT_TLS1_2_SERVER)) return 3;
    return 0;
}
