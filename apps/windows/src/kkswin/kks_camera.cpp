// The webcam for scanning an invite QR (decision 0039): Media Foundation's Source Reader on the first video capture
// device (or KKS_CAMERA_FILE, a video file through the same reader: tests), RGB32 frames turned into 8-bit grey on a
// worker thread. Media Foundation is loaded at run time: Windows N editions ship without it, and a linked mfplat.dll
// would stop the whole app from starting there.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <initguid.h>   // the Media Foundation GUIDs defined here (no mfuuid import)
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

typedef HRESULT (WINAPI *PStartup)(ULONG, DWORD);
typedef HRESULT (WINAPI *PShutdown)();
typedef HRESULT (WINAPI *PCreateAttributes)(IMFAttributes **, UINT32);
typedef HRESULT (WINAPI *PCreateMediaType)(IMFMediaType **);
typedef HRESULT (WINAPI *PEnumDeviceSources)(IMFAttributes *, IMFActivate ***, UINT32 *);
typedef HRESULT (WINAPI *PReaderFromSource)(IMFMediaSource *, IMFAttributes *, IMFSourceReader **);
typedef HRESULT (WINAPI *PReaderFromURL)(LPCWSTR, IMFAttributes *, IMFSourceReader **);

struct kks_cam {
    volatile LONG state;      // 0 starting, 1 running, -1 failed, 2 stopping
    char err[256];
    HANDLE thread;
    CRITICAL_SECTION lock;
    std::vector<unsigned char> gray, out;
    int w, h, ow, oh;
    bool fresh;
    bool file;
    wchar_t path[MAX_PATH];
};

static void fail(kks_cam *c, const char *m) { snprintf(c->err, sizeof c->err, "%s", m); InterlockedExchange(&c->state, -1); }

static DWORD WINAPI run(void *arg) {
    kks_cam *c = (kks_cam *)arg;
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    HMODULE plat = LoadLibraryW(L"mfplat.dll"), mf = LoadLibraryW(L"mf.dll"), rw = LoadLibraryW(L"mfreadwrite.dll");
    PStartup Startup = plat ? (PStartup)GetProcAddress(plat, "MFStartup") : nullptr;
    PShutdown Shutdown = plat ? (PShutdown)GetProcAddress(plat, "MFShutdown") : nullptr;
    PCreateAttributes CreateAttributes = plat ? (PCreateAttributes)GetProcAddress(plat, "MFCreateAttributes") : nullptr;
    PCreateMediaType CreateMediaType = plat ? (PCreateMediaType)GetProcAddress(plat, "MFCreateMediaType") : nullptr;
    PEnumDeviceSources EnumDeviceSources = mf ? (PEnumDeviceSources)GetProcAddress(mf, "MFEnumDeviceSources") : nullptr;
    PReaderFromSource ReaderFromSource = rw ? (PReaderFromSource)GetProcAddress(rw, "MFCreateSourceReaderFromMediaSource") : nullptr;
    PReaderFromURL ReaderFromURL = rw ? (PReaderFromURL)GetProcAddress(rw, "MFCreateSourceReaderFromURL") : nullptr;
    IMFSourceReader *reader = nullptr;
    IMFMediaSource *source = nullptr;
    IMFAttributes *attrs = nullptr;
    IMFMediaType *type = nullptr;
    LONG stride = 0;
    UINT32 fw = 0, fh = 0;
    if (!Startup || !CreateAttributes || !CreateMediaType || !EnumDeviceSources || !ReaderFromSource || !ReaderFromURL) {
        fail(c, "This Windows has no Media Foundation (an N edition needs the Media Feature Pack). Paste the invite text instead.");
        goto done;
    }
    if (FAILED(Startup(MF_VERSION, MFSTARTUP_LITE))) { fail(c, "Media Foundation could not start."); goto done; }
    CreateAttributes(&attrs, 2);
    attrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);   // lets the reader hand out RGB32
    if (c->file) {
        if (FAILED(ReaderFromURL(c->path, attrs, &reader))) { fail(c, "The test video could not be opened."); goto shutdown; }
    } else {
        IMFAttributes *q = nullptr;
        CreateAttributes(&q, 1);
        q->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
        IMFActivate **devs = nullptr;
        UINT32 n = 0;
        HRESULT hr = EnumDeviceSources(q, &devs, &n);
        q->Release();
        if (FAILED(hr) || n == 0) { fail(c, "No camera found on this computer. Paste the invite text instead."); if (devs) CoTaskMemFree(devs); goto shutdown; }
        hr = devs[0]->ActivateObject(IID_PPV_ARGS(&source));
        for (UINT32 i = 0; i < n; i++) devs[i]->Release();
        CoTaskMemFree(devs);
        if (hr == E_ACCESSDENIED) { fail(c, "Windows did not let the app use the camera: allow it in Settings → Privacy → Camera → \"Let desktop apps access your camera\"."); goto shutdown; }
        if (FAILED(hr)) { fail(c, "The camera could not be started (is another program using it?)"); goto shutdown; }
        if (FAILED(ReaderFromSource(source, attrs, &reader))) { fail(c, "The camera could not be read."); goto shutdown; }
    }
    CreateMediaType(&type);
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    if (FAILED(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, type))) { fail(c, "The camera gives no picture format the app can read."); goto shutdown; }
    type->Release(); type = nullptr;
    reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &type);
    MFGetAttributeSize(type, MF_MT_FRAME_SIZE, &fw, &fh);
    stride = (LONG)MFGetAttributeUINT32(type, MF_MT_DEFAULT_STRIDE, fw * 4);
    if (fw == 0 || fh == 0) { fail(c, "The camera reported no picture size."); goto shutdown; }
    InterlockedCompareExchange(&c->state, 1, 0);
    while (c->state == 1) {
        DWORD flags = 0;
        IMFSample *s = nullptr;
        HRESULT hr = reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, &flags, nullptr, &s);
        if (FAILED(hr)) { fail(c, hr == E_ACCESSDENIED ? "Windows stopped the camera (privacy settings)." : "The camera stopped."); break; }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
        if (!s) continue;
        IMFMediaBuffer *b = nullptr;
        if (SUCCEEDED(s->ConvertToContiguousBuffer(&b))) {
            BYTE *p = nullptr; DWORD len = 0;
            if (SUCCEEDED(b->Lock(&p, nullptr, &len)) && len >= (DWORD)(labs(stride) * (LONG)fh)) {
                EnterCriticalSection(&c->lock);
                c->gray.resize((size_t)fw * fh);
                for (UINT32 y = 0; y < fh; y++) {
                    // a negative stride means bottom-up rows
                    const BYTE *row = stride > 0 ? p + (size_t)y * stride : p + (size_t)(fh - 1 - y) * (size_t)(-stride);
                    unsigned char *g = &c->gray[(size_t)y * fw];
                    for (UINT32 x = 0; x < fw; x++) g[x] = (unsigned char)((row[x * 4 + 2] * 299 + row[x * 4 + 1] * 587 + row[x * 4] * 114) / 1000);
                }
                c->w = (int)fw; c->h = (int)fh; c->fresh = true;
                LeaveCriticalSection(&c->lock);
                b->Unlock();
            }
            b->Release();
        }
        s->Release();
        if (c->file) Sleep(66);   // a file decodes as fast as it can; play it at camera speed
    }
shutdown:
    if (type) type->Release();
    if (reader) reader->Release();
    if (source) { source->Shutdown(); source->Release(); }
    if (attrs) attrs->Release();
    if (Shutdown) Shutdown();
done:
    CoUninitialize();
    return 0;
}

extern "C" kks_cam *kks_cam_open(void) {
    kks_cam *c = new kks_cam();
    InitializeCriticalSection(&c->lock);
    DWORD n = GetEnvironmentVariableW(L"KKS_CAMERA_FILE", c->path, MAX_PATH);
    c->file = n > 0 && n < MAX_PATH;
    c->thread = CreateThread(nullptr, 0, run, c, 0, nullptr);
    return c;
}

extern "C" int kks_cam_state(kks_cam *c) { return c->state == 2 ? 1 : (int)c->state; }
extern "C" const char *kks_cam_error(kks_cam *c) { return c->err; }

// the newest frame as grey rows (valid until the next call), or NULL if none arrived since
extern "C" const unsigned char *kks_cam_frame(kks_cam *c, int *w, int *h) {
    EnterCriticalSection(&c->lock);
    const unsigned char *r = nullptr;
    if (c->fresh) {
        c->out = c->gray; c->ow = c->w; c->oh = c->h; c->fresh = false;
        r = c->out.data(); *w = c->ow; *h = c->oh;
    }
    LeaveCriticalSection(&c->lock);
    return r;
}

// a preview of the last frame from kks_cam_frame, `maxw` pixels wide at most, for a STATIC control (caller deletes)
extern "C" HBITMAP kks_cam_preview(kks_cam *c, int maxw) {
    if (c->out.empty()) return nullptr;
    int W = c->ow < maxw ? c->ow : maxw, H = (int)((long long)c->oh * W / c->ow);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = W; bi.bmiHeader.biHeight = -H; bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32;
    void *bits = nullptr;
    HBITMAP hb = CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!hb) return nullptr;
    uint32_t *d = (uint32_t *)bits;
    for (int y = 0; y < H; y++) {
        const unsigned char *row = &c->out[(size_t)(y * c->oh / H) * c->ow];
        for (int x = 0; x < W; x++) { uint32_t g = row[x * c->ow / W]; d[(size_t)y * W + x] = 0xFF000000u | g << 16 | g << 8 | g; }
    }
    return hb;
}

extern "C" void kks_cam_close(kks_cam *c) {
    if (!c) return;
    InterlockedCompareExchange(&c->state, 2, 1);
    InterlockedCompareExchange(&c->state, 2, 0);
    // the reader may sit in ReadSample for up to a frame; the thread ends by itself and frees nothing we still use
    if (WaitForSingleObject(c->thread, 3000) == WAIT_OBJECT_0) {
        CloseHandle(c->thread);
        DeleteCriticalSection(&c->lock);
        delete c;
    }   // else: leave it (a stuck driver); a few KB, never touched again
}
