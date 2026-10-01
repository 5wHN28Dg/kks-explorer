// The drawing's tags for screen readers on Windows (decision 0033; the counterpart of Android's AccessibilityNodeProvider
// and GNOME's accessible children): a UI Automation provider on the drawing window. The window is a fragment root;
// each tag on screen is a child fragment (a button named "11LAB70AA501, verified") that Narrator reads and can invoke.
// The viewer (Nim) answers through three callbacks: how many tags, one tag's name and rectangle, invoke one.
// ProviderOptions_UseComThreading: UIA calls the provider on the window's (STA) thread, never on its own workers;
// the callbacks allocate Nim memory, which must happen on the Nim thread (found on Windows 11: a crash at start).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ole2.h>
#include <uiautomation.h>
#include <string>
#include <vector>

typedef int (*CountFn)(void *ud);
typedef int (*InfoFn)(void *ud, int i, wchar_t *name, int cap, RECT *client);   // 1 if i exists
typedef void (*InvokeFn)(void *ud, int i);

struct Host { HWND hwnd; CountFn count; InfoFn info; InvokeFn invoke; void *ud; };

class Root;

class Tag : public IRawElementProviderSimple, public IRawElementProviderFragment, public IInvokeProvider {
    LONG ref = 1;
public:
    Host *h; Root *root; int i;
    Tag(Host *h, Root *root, int i);
    ~Tag();
    // IUnknown
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **pp) override {
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IRawElementProviderSimple)) *pp = static_cast<IRawElementProviderSimple *>(this);
        else if (riid == __uuidof(IRawElementProviderFragment)) *pp = static_cast<IRawElementProviderFragment *>(this);
        else if (riid == __uuidof(IInvokeProvider)) *pp = static_cast<IInvokeProvider *>(this);
        else { *pp = nullptr; return E_NOINTERFACE; }
        AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&ref); }
    ULONG STDMETHODCALLTYPE Release() override { LONG r = InterlockedDecrement(&ref); if (!r) delete this; return (ULONG)r; }
    // IRawElementProviderSimple
    HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *o) override { *o = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading); return S_OK; }
    HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID id, IUnknown **p) override {
        *p = nullptr;
        if (id == UIA_InvokePatternId) { *p = static_cast<IInvokeProvider *>(this); AddRef(); }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID id, VARIANT *v) override {
        v->vt = VT_EMPTY;
        wchar_t name[256] = L""; RECT r;
        if (!h->info(h->ud, i, name, 256, &r)) return UIA_E_ELEMENTNOTAVAILABLE;
        switch (id) {
        case UIA_NamePropertyId: v->vt = VT_BSTR; v->bstrVal = SysAllocString(name); break;
        case UIA_ControlTypePropertyId: v->vt = VT_I4; v->lVal = UIA_ButtonControlTypeId; break;
        case UIA_IsKeyboardFocusablePropertyId: v->vt = VT_BOOL; v->boolVal = VARIANT_FALSE; break;
        case UIA_IsInvokePatternAvailablePropertyId: v->vt = VT_BOOL; v->boolVal = VARIANT_TRUE; break;
        case UIA_AutomationIdPropertyId: v->vt = VT_BSTR; v->bstrVal = SysAllocString((L"tag" + std::to_wstring(i)).c_str()); break;
        default: break;
        }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **p) override { *p = nullptr; return S_OK; }
    // IRawElementProviderFragment
    HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection d, IRawElementProviderFragment **p) override;
    HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **ids) override {
        int rid[2] = {UiaAppendRuntimeId, i};
        *ids = SafeArrayCreateVector(VT_I4, 0, 2);
        for (LONG k = 0; k < 2; k++) SafeArrayPutElement(*ids, &k, &rid[k]);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *out) override {
        wchar_t name[8]; RECT r;
        if (!h->info(h->ud, i, name, 8, &r)) return UIA_E_ELEMENTNOTAVAILABLE;
        POINT tl = {r.left, r.top}; ClientToScreen(h->hwnd, &tl);
        out->left = tl.x; out->top = tl.y; out->width = r.right - r.left; out->height = r.bottom - r.top;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **p) override { *p = nullptr; return S_OK; }
    HRESULT STDMETHODCALLTYPE SetFocus() override { return S_OK; }
    HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **p) override;
    // IInvokeProvider
    HRESULT STDMETHODCALLTYPE Invoke() override {
        // run after this call returns (the app may rebuild its screens): through the window's message queue
        PostMessageW(h->hwnd, WM_APP + 7, (WPARAM)i, 0);
        return S_OK;
    }
};

class Root : public IRawElementProviderSimple, public IRawElementProviderFragment, public IRawElementProviderFragmentRoot {
    LONG ref = 1;
public:
    Host h;
    Root(const Host &host) : h(host) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **pp) override {
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IRawElementProviderSimple)) *pp = static_cast<IRawElementProviderSimple *>(this);
        else if (riid == __uuidof(IRawElementProviderFragment)) *pp = static_cast<IRawElementProviderFragment *>(this);
        else if (riid == __uuidof(IRawElementProviderFragmentRoot)) *pp = static_cast<IRawElementProviderFragmentRoot *>(this);
        else { *pp = nullptr; return E_NOINTERFACE; }
        AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&ref); }
    ULONG STDMETHODCALLTYPE Release() override { LONG r = InterlockedDecrement(&ref); if (!r) delete this; return (ULONG)r; }
    HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *o) override { *o = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading); return S_OK; }
    HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID, IUnknown **p) override { *p = nullptr; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID id, VARIANT *v) override {
        v->vt = VT_EMPTY;
        if (id == UIA_NamePropertyId) { v->vt = VT_BSTR; v->bstrVal = SysAllocString(L"Drawing"); }
        else if (id == UIA_ControlTypePropertyId) { v->vt = VT_I4; v->lVal = UIA_PaneControlTypeId; }
        else if (id == UIA_IsKeyboardFocusablePropertyId) { v->vt = VT_BOOL; v->boolVal = VARIANT_TRUE; }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **p) override {
        return UiaHostProviderFromHwnd(h.hwnd, p);
    }
    HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection d, IRawElementProviderFragment **p) override {
        *p = nullptr;
        int n = h.count(h.ud);
        if (n > 0 && (d == NavigateDirection_FirstChild || d == NavigateDirection_LastChild))
            *p = new Tag(&h, this, d == NavigateDirection_FirstChild ? 0 : n - 1);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **ids) override { *ids = nullptr; return S_OK; }
    HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *out) override { *out = {0, 0, 0, 0}; return S_OK; }   // from the host window
    HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **p) override { *p = nullptr; return S_OK; }
    HRESULT STDMETHODCALLTYPE SetFocus() override { ::SetFocus(h.hwnd); return S_OK; }
    HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **p) override {
        *p = this; AddRef(); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **p) override {
        *p = nullptr;
        POINT pt = {(LONG)x, (LONG)y}; ScreenToClient(h.hwnd, &pt);
        int n = h.count(h.ud);
        wchar_t name[8]; RECT r;
        for (int i = n - 1; i >= 0; i--)
            if (h.info(h.ud, i, name, 8, &r) && PtInRect(&r, pt)) { *p = new Tag(&h, this, i); return S_OK; }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetFocus(IRawElementProviderFragment **p) override { *p = nullptr; return S_OK; }
};

Tag::Tag(Host *h, Root *root, int i) : h(h), root(root), i(i) { root->AddRef(); }
Tag::~Tag() { root->Release(); }

HRESULT Tag::Navigate(NavigateDirection d, IRawElementProviderFragment **p) {
    *p = nullptr;
    int n = h->count(h->ud);
    if (d == NavigateDirection_Parent) { *p = static_cast<IRawElementProviderFragment *>(root); root->AddRef(); }
    else if (d == NavigateDirection_NextSibling && i + 1 < n) *p = new Tag(h, root, i + 1);
    else if (d == NavigateDirection_PreviousSibling && i > 0 && i - 1 < n) *p = new Tag(h, root, i - 1);
    return S_OK;
}
HRESULT Tag::get_FragmentRoot(IRawElementProviderFragmentRoot **p) { *p = root; root->AddRef(); return S_OK; }

// the provider for WM_GETOBJECT (created once per window)
extern "C" void *kks_uia_new(HWND hwnd, CountFn count, InfoFn info, InvokeFn invoke, void *ud) {
    return new Root(Host{hwnd, count, info, invoke, ud});
}

// WM_GETOBJECT → the provider (or 0 when it isn't UIA asking)
extern "C" LRESULT kks_uia_getobject(void *root, HWND hwnd, WPARAM w, LPARAM l) {
    if ((LONG)l != UiaRootObjectId) return 0;
    return UiaReturnRawElementProvider(hwnd, w, l, static_cast<IRawElementProviderSimple *>((Root *)root));
}

// the tags on screen changed (pan, zoom, new data)
extern "C" void kks_uia_changed(void *root) {
    if (UiaClientsAreListening())
        UiaRaiseStructureChangedEvent(static_cast<IRawElementProviderSimple *>((Root *)root), StructureChangeType_ChildrenInvalidated, nullptr, 0);
}

extern "C" void kks_uia_invoke(void *root, int i) { Root *r = (Root *)root; r->h.invoke(r->h.ud, i); }
