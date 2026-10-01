/* DNS-SD on Windows (decisions 0021, 0033): DnsServiceRegister / DnsServiceBrowse / DnsServiceResolve (dnsapi,
 * Windows 10, desktop apps). Callbacks arrive on Windows' thread pool, so results go into a locked queue that the
 * app's loop drains (kks_dnssd_next). */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windns.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static CRITICAL_SECTION lock;
static int inited;
static char *queue[256];
static int qn;
static DNS_SERVICE_CANCEL browse_cancel, register_cancel;
static int browsing, registered;
static PDNS_SERVICE_INSTANCE reg_instance;

static void init(void) {
    if (!inited) { InitializeCriticalSection(&lock); inited = 1; }
}

static void push(char *line) {
    EnterCriticalSection(&lock);
    if (qn < 256) queue[qn++] = line; else free(line);
    LeaveCriticalSection(&lock);
}

/* the next result as "instance\thost\taddress\tport\tkey=value\x1fkey=value", or NULL; the caller frees it */
char *kks_dnssd_next(void) {
    init();
    char *r = NULL;
    EnterCriticalSection(&lock);
    if (qn > 0) { r = queue[0]; memmove(queue, queue + 1, (size_t)(qn - 1) * sizeof queue[0]); qn--; }
    LeaveCriticalSection(&lock);
    return r;
}

static char *utf8(const wchar_t *w) {
    if (!w) return _strdup("");
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    char *s = malloc((size_t)n);
    WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL);
    return s;
}

static void WINAPI resolved(DWORD status, PVOID ctx, PDNS_SERVICE_INSTANCE inst) {
    (void)ctx;
    if (status != ERROR_SUCCESS || !inst) { if (inst) DnsServiceFreeInstance(inst); return; }
    char line[4096];
    char *name = utf8(inst->pszInstanceName), *host = utf8(inst->pszHostName);
    char addr[32] = "";
    if (inst->ip4Address) {
        unsigned char *b = (unsigned char *)inst->ip4Address;
        snprintf(addr, sizeof addr, "%u.%u.%u.%u", b[0], b[1], b[2], b[3]);
    }
    int n = snprintf(line, sizeof line, "%s\t%s\t%s\t%u\t", name, host, addr, (unsigned)inst->wPort);
    for (DWORD i = 0; i < inst->dwPropertyCount && n < (int)sizeof line - 2; i++) {
        char *k = utf8(inst->keys[i]), *v = utf8(inst->values[i]);
        n += snprintf(line + n, sizeof line - (size_t)n, "%s%s=%s", i ? "\x1f" : "", k, v);
        free(k); free(v);
    }
    free(name); free(host);
    DnsServiceFreeInstance(inst);
    push(_strdup(line));
}

static void WINAPI browsed(DWORD status, PVOID ctx, PDNS_RECORD rec) {
    (void)ctx;
    if (status != ERROR_SUCCESS) { if (rec) DnsRecordListFree(rec, DnsFreeRecordList); return; }
    for (PDNS_RECORD r = rec; r; r = r->pNext) {
        if (r->wType != DNS_TYPE_PTR || !r->Data.PTR.pNameHost) continue;
        DNS_SERVICE_RESOLVE_REQUEST req;
        memset(&req, 0, sizeof req);
        req.Version = DNS_QUERY_REQUEST_VERSION1;
        req.InterfaceIndex = 0;
        req.QueryName = r->Data.PTR.pNameHost;
        req.pResolveCompletionCallback = resolved;
        DNS_SERVICE_CANCEL c;
        DnsServiceResolve(&req, &c);     /* the result comes to resolved() */
    }
    if (rec) DnsRecordListFree(rec, DnsFreeRecordList);
}

/* start (or restart) browsing for _kks._tcp; 0 on success */
int kks_dnssd_browse(void) {
    init();
    if (browsing) { DnsServiceBrowseCancel(&browse_cancel); browsing = 0; }
    DNS_SERVICE_BROWSE_REQUEST req;
    memset(&req, 0, sizeof req);
    req.Version = DNS_QUERY_REQUEST_VERSION1;
    req.InterfaceIndex = 0;
    req.QueryName = L"_kks._tcp.local";
    req.pBrowseCallback = browsed;
    DNS_STATUS s = DnsServiceBrowse(&req, &browse_cancel);
    if (s != DNS_REQUEST_PENDING) return (int)s;
    browsing = 1;
    return 0;
}

static void WINAPI reg_done(DWORD status, PVOID ctx, PDNS_SERVICE_INSTANCE inst) {
    (void)status; (void)ctx;
    if (inst) DnsServiceFreeInstance(inst);
}

static wchar_t *wide(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    wchar_t *w = malloc((size_t)n * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}

/* announce name._kks._tcp.local on port with the TXT pairs (keys[i]=values[i]); replaces an earlier announcement */
int kks_dnssd_announce(const char *name, unsigned short port, int n, const char **keys, const char **values) {
    init();
    if (registered && reg_instance) {
        DNS_SERVICE_REGISTER_REQUEST old;
        memset(&old, 0, sizeof old);
        old.Version = DNS_QUERY_REQUEST_VERSION1;
        old.pServiceInstance = reg_instance;
        old.pRegisterCompletionCallback = reg_done;
        DnsServiceDeRegister(&old, NULL);
        DnsServiceFreeInstance(reg_instance);
        reg_instance = NULL;
        registered = 0;
    }
    wchar_t computer[MAX_COMPUTERNAME_LENGTH + 1];
    DWORD cn = MAX_COMPUTERNAME_LENGTH + 1;
    GetComputerNameW(computer, &cn);
    wchar_t host[300], inst[300];
    _snwprintf(host, 300, L"%ls.local", computer);
    wchar_t *wn = wide(name);
    _snwprintf(inst, 300, L"%ls._kks._tcp.local", wn);
    free(wn);
    PCWSTR *wk = calloc((size_t)n + 1, sizeof(PCWSTR)), *wv = calloc((size_t)n + 1, sizeof(PCWSTR));
    for (int i = 0; i < n; i++) { wk[i] = wide(keys[i]); wv[i] = wide(values[i]); }
    reg_instance = DnsServiceConstructInstance(inst, host, NULL, NULL, port, 0, 0, (DWORD)n, wk, wv);
    for (int i = 0; i < n; i++) { free((void *)wk[i]); free((void *)wv[i]); }
    free(wk); free(wv);
    if (!reg_instance) return 1;
    DNS_SERVICE_REGISTER_REQUEST req;
    memset(&req, 0, sizeof req);
    req.Version = DNS_QUERY_REQUEST_VERSION1;
    req.InterfaceIndex = 0;
    req.pServiceInstance = reg_instance;
    req.pRegisterCompletionCallback = reg_done;
    DWORD s = DnsServiceRegister(&req, &register_cancel);
    if (s != DNS_REQUEST_PENDING) return (int)s;
    registered = 1;
    return 0;
}
