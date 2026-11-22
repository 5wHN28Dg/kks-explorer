// Dark colours for the Windows app's own controls (#377, decision 0078): Win32's common controls have no documented
// dark mode, so the app paints them in its own colours through the documented messages: WM_CTLCOLOR* for labels,
// fields and lists, NM_CUSTOMDRAW for buttons, check boxes and radio buttons (Common Controls v6), WM_NCPAINT for
// the edge of a field or list, TVM_SET*COLOR for the tree, EM_SETBKGNDCOLOR for rich text, WM_ERASEBKGND for the
// windows behind them. The title bar: DwmSetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE). Scroll bars: the theme
// class names Windows' own Explorer uses ("DarkMode_Explorer") through SetWindowTheme. Menus (the window's menu, a
// field's right-click menu): uxtheme's unnamed exports, only on Windows builds where they are known (decision 0078).
// Nothing here acts until kks_theme_init: with the switch off (theme.nim) the app is exactly as before.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <uxtheme.h>
#include <dwmapi.h>
#include <richedit.h>
#include <string.h>
#include <stdlib.h>
#include <algorithm>
using std::max;
using std::min;

enum { Window, Surface, Text, Dim, Border, Button, Hot, Down, Focus, Accent, AccentText, Disabled, NColours };

static int enabled = 0;      // the switch (theme.nim): nothing is subclassed or changed without it
static int dark = 0;         // the colours in use now: ours (dark) or the system's (light, high contrast)
static COLORREF pal[NColours];
static HBRUSH brWindow, brSurface;
static const UINT_PTR SubId = 0x4B4B5354;   // "KKST"
static const wchar_t *DimProp = L"kksThemeDim";
static const wchar_t *DoneProp = L"kksThemeTop";

static COLORREF rgb(unsigned v) { return RGB((v >> 16) & 255, (v >> 8) & 255, v & 255); }

static bool isClass(HWND h, const wchar_t *cls) {
    wchar_t buf[64];
    return GetClassNameW(h, buf, 64) > 0 && _wcsicmp(buf, cls) == 0;
}

// ---- the title bar (documented: Windows 11, and Windows 10 from 20H1 with the same value)
static void topBar(HWND top) {
    BOOL v = dark ? TRUE : FALSE;
    if (FAILED(DwmSetWindowAttribute(top, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &v, sizeof v)))
        DwmSetWindowAttribute(top, 19, &v, sizeof v);      // (Windows 10 before 20H1 used 19: ignored where unknown)
}

// ---- menus: uxtheme's ordinal 135 (SetPreferredAppMode from 1903, AllowDarkModeForApp in 1809: 1 means the same,
// "allow dark") and 136 (FlushMenuThemes). Undocumented: only on the builds checked (decision 0078), else menus stay
// light. Allowed, the menus follow Windows' app mode by themselves.
typedef LONG (WINAPI *RtlGetVersionFn)(OSVERSIONINFOW *);
static DWORD windowsBuild() {
    OSVERSIONINFOW v = {};
    v.dwOSVersionInfoSize = sizeof v;
    HMODULE nt = GetModuleHandleW(L"ntdll.dll");
    RtlGetVersionFn f = nt ? (RtlGetVersionFn)(void *)GetProcAddress(nt, "RtlGetVersion") : nullptr;
    if (!f || f(&v) != 0 || v.dwMajorVersion != 10) return 0;
    return v.dwBuildNumber;
}

extern "C" int kks_theme_menus_known(unsigned build) { return build >= 17763 && build < 30000; }

typedef BOOL (WINAPI *AllowWindowFn)(HWND, BOOL);
static AllowWindowFn allowWindow = nullptr;     // ordinal 133, AllowDarkModeForWindow: a window's own menus (a
                                                // field's right-click menu belongs to the field)

static void appMenus() {
    if (!kks_theme_menus_known(windowsBuild())) return;
    HMODULE ux = LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!ux) return;
    typedef int (WINAPI *ModeFn)(int);
    typedef void (WINAPI *FlushFn)();
    ModeFn mode = (ModeFn)(void *)GetProcAddress(ux, MAKEINTRESOURCEA(135));
    FlushFn flush = (FlushFn)(void *)GetProcAddress(ux, MAKEINTRESOURCEA(136));
    allowWindow = (AllowWindowFn)(void *)GetProcAddress(ux, MAKEINTRESOURCEA(133));
    if (mode) mode(1);
    if (flush) flush();
}

// ---- painting a button, check box or radio button in our colours (NM_CUSTOMDRAW at its parent)
static int dpiOf(HWND h) { UINT d = GetDpiForWindow(h); return d ? (int)d : 96; }
static int sc(HWND h, int v) { return MulDiv(v, dpiOf(h), 96); }

static void frame(HDC dc, RECT r, COLORREF c, int w) {
    HBRUSH b = CreateSolidBrush(c);
    for (int i = 0; i < w; i++) {
        FrameRect(dc, &r, b);
        InflateRect(&r, -1, -1);
    }
    DeleteObject(b);
}

static void fill(HDC dc, RECT r, COLORREF c) {
    HBRUSH b = CreateSolidBrush(c);
    FillRect(dc, &r, b);
    DeleteObject(b);
}


static void drawButton(NMCUSTOMDRAW *cd) {
    HWND h = cd->hdr.hwndFrom;
    HDC dc = cd->hdc;
    RECT r = cd->rc;
    LONG style = GetWindowLongW(h, GWL_STYLE);
    int kind = style & BS_TYPEMASK;
    bool disabled = (cd->uItemState & CDIS_DISABLED) || !IsWindowEnabled(h);
    bool focus = (cd->uItemState & CDIS_FOCUS) != 0;
    bool hot = (cd->uItemState & CDIS_HOT) != 0;
    bool down = (cd->uItemState & CDIS_SELECTED) != 0;
    bool cues = !(SendMessageW(h, WM_QUERYUISTATE, 0, 0) & UISF_HIDEACCEL);
    int n = GetWindowTextLengthW(h);
    wchar_t *text = (wchar_t *)calloc(n + 1, sizeof(wchar_t));
    GetWindowTextW(h, text, n + 1);
    HGDIOBJ oldFont = SelectObject(dc, (HFONT)SendMessageW(h, WM_GETFONT, 0, 0));
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, disabled ? pal[Disabled] : pal[Text]);
    UINT prefix = cues ? 0 : DT_HIDEPREFIX;
    fill(dc, r, pal[Window]);
    if (kind == BS_AUTOCHECKBOX || kind == BS_CHECKBOX || kind == BS_AUTORADIOBUTTON || kind == BS_RADIOBUTTON) {
        bool radio = kind == BS_AUTORADIOBUTTON || kind == BS_RADIOBUTTON;
        bool on = SendMessageW(h, BM_GETCHECK, 0, 0) == BST_CHECKED;
        int box = sc(h, 14);
        int top = r.top + (r.bottom - r.top - box) / 2;
        RECT b = {r.left + sc(h, 1), top, r.left + sc(h, 1) + box, top + box};
        COLORREF edge = disabled ? pal[Disabled] : (hot || down ? pal[Focus] : pal[Border]);
        HPEN pen = CreatePen(PS_SOLID, sc(h, 1), on && !disabled ? pal[Accent] : edge);
        HBRUSH brush = CreateSolidBrush(on && !disabled ? pal[Accent] : pal[Surface]);
        HGDIOBJ op = SelectObject(dc, pen), ob = SelectObject(dc, brush);
        if (radio) {
            Ellipse(dc, b.left, b.top, b.right, b.bottom);
            if (on) {
                HBRUSH dot = CreateSolidBrush(pal[AccentText]);
                SelectObject(dc, dot);
                SelectObject(dc, GetStockObject(NULL_PEN));
                int m = box * 3 / 10;
                Ellipse(dc, b.left + m, b.top + m, b.right - m + 1, b.bottom - m + 1);
                SelectObject(dc, brush);
                DeleteObject(dot);
            }
        } else {
            Rectangle(dc, b.left, b.top, b.right, b.bottom);
            if (on) {      // a tick in the text colour on the accent
                HPEN tick = CreatePen(PS_SOLID, max(2, sc(h, 2)), pal[AccentText]);
                SelectObject(dc, tick);
                POINT pts[3] = {{b.left + box * 2 / 10, b.top + box / 2}, {b.left + box * 4 / 10, b.top + box * 7 / 10},
                                {b.left + box * 8 / 10, b.top + box * 3 / 10}};
                Polyline(dc, pts, 3);
                SelectObject(dc, pen);
                DeleteObject(tick);
            }
        }
        SelectObject(dc, op); SelectObject(dc, ob);
        DeleteObject(pen); DeleteObject(brush);
        RECT t = {b.right + sc(h, 6), r.top, r.right, r.bottom};
        RECT m = t;
        DrawTextW(dc, text, -1, &m, DT_CALCRECT | DT_SINGLELINE | prefix);
        DrawTextW(dc, text, -1, &t, DT_LEFT | DT_VCENTER | DT_SINGLELINE | prefix);
        if (focus) {      // a ring round the label, in the text colour (3:1 and more against the window)
            int th = m.bottom - m.top;
            RECT f = {t.left - sc(h, 2), r.top + (r.bottom - r.top - th) / 2 - sc(h, 1),
                      min(t.left + (m.right - m.left) + sc(h, 2), r.right), r.top + (r.bottom - r.top + th) / 2 + sc(h, 1)};
            frame(dc, f, pal[Focus], 1);
        }
    } else {
        // a push button: a filled box with a border; focus: a two-pixel ring in the focus colour
        COLORREF face = disabled ? pal[Window] : down ? pal[Down] : hot ? pal[Hot] : pal[Button];
        fill(dc, r, face);
        frame(dc, r, disabled ? pal[Disabled] : (focus ? pal[Focus] : pal[Border]), focus ? max(2, sc(h, 2)) : 1);
        RECT t = r;
        InflateRect(&t, -sc(h, 6), -sc(h, 3));
        if (style & BS_MULTILINE) {
            RECT m = t;
            DrawTextW(dc, text, -1, &m, DT_CALCRECT | DT_WORDBREAK | prefix);
            int th = m.bottom - m.top;
            if (th < t.bottom - t.top) t.top += (t.bottom - t.top - th) / 2;
            DrawTextW(dc, text, -1, &t, DT_WORDBREAK | prefix | ((style & BS_LEFT) == BS_LEFT ? DT_LEFT : DT_CENTER));
        } else {
            DrawTextW(dc, text, -1, &t, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | prefix);
        }
    }
    SelectObject(dc, oldFont);
    free(text);
}

// ---- a field's or list's edge (WS_EX_CLIENTEDGE): the theme draws it light, with a white inner line
static LRESULT CALLBACK edgeProc(HWND h, UINT m, WPARAM w, LPARAM l, UINT_PTR id, DWORD_PTR) {
    if (m == WM_NCDESTROY) RemoveWindowSubclass(h, edgeProc, id);
    if (m == WM_NCPAINT && dark && (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_CLIENTEDGE)) {
        LRESULT res = DefSubclassProc(h, m, w, l);         // the scroll bars
        HDC dc = GetWindowDC(h);
        RECT r;
        GetWindowRect(h, &r);
        OffsetRect(&r, -r.left, -r.top);
        frame(dc, r, GetFocus() == h ? pal[Focus] : pal[Border], 1);
        InflateRect(&r, -1, -1);
        frame(dc, r, pal[Surface], 1);
        ReleaseDC(h, dc);
        return res;
    }
    if (m == WM_PAINT && dark && GetWindowTextLengthW(h) == 0 && isClass(h, L"Edit")) {
        // an empty field's hint (EM_SETCUEBANNER): Windows draws it in a grey made for white (about 3:1 on the
        // field's dark colour); here in the secondary text colour (8.5:1)
        wchar_t cue[256] = L"";
        if (SendMessageW(h, EM_GETCUEBANNER, (WPARAM)cue, 256) && cue[0]) {
            bool caret = GetFocus() == h;
            if (caret) HideCaret(h);
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(h, &ps);
            RECT r, t;
            GetClientRect(h, &r);
            FillRect(dc, &r, brSurface);
            SendMessageW(h, EM_GETRECT, 0, (LPARAM)&t);
            HGDIOBJ of = SelectObject(dc, (HFONT)SendMessageW(h, WM_GETFONT, 0, 0));
            SetBkMode(dc, TRANSPARENT);
            SetTextColor(dc, pal[Dim]);
            DrawTextW(dc, cue, -1, &t, DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS | DT_TOP | DT_LEFT);
            SelectObject(dc, of);
            EndPaint(h, &ps);
            if (caret) ShowCaret(h);
            return 0;
        }
    }
    if ((m == WM_SETFOCUS || m == WM_KILLFOCUS) && dark) {
        LRESULT res = DefSubclassProc(h, m, w, l);
        RedrawWindow(h, nullptr, nullptr, RDW_FRAME | RDW_INVALIDATE);
        return res;
    }
    return DefSubclassProc(h, m, w, l);
}

// ---- a window holding controls: its background, and its controls' colours (they ask their parent)
static LRESULT CALLBACK containerProc(HWND h, UINT m, WPARAM w, LPARAM l, UINT_PTR id, DWORD_PTR) {
    if (m == WM_NCDESTROY) {
        RemovePropW(h, DoneProp);
        RemoveWindowSubclass(h, containerProc, id);
        return DefSubclassProc(h, m, w, l);
    }
    if (!dark) return DefSubclassProc(h, m, w, l);
    switch (m) {
    case WM_ERASEBKGND: {
        RECT r;
        GetClientRect(h, &r);
        FillRect((HDC)w, &r, brWindow);
        return 1;
    }
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN: {
        HDC dc = (HDC)w;
        HWND c = (HWND)l;
        SetTextColor(dc, !IsWindowEnabled(c) ? pal[Disabled] : GetPropW(c, DimProp) ? pal[Dim] : pal[Text]);
        SetBkColor(dc, pal[Window]);
        return (LRESULT)brWindow;
    }
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX: {
        HDC dc = (HDC)w;
        SetTextColor(dc, pal[Text]);
        SetBkColor(dc, pal[Surface]);
        return (LRESULT)brSurface;
    }
    case WM_NOTIFY: {
        NMHDR *hd = (NMHDR *)l;
        if (hd->code == NM_CUSTOMDRAW && isClass(hd->hwndFrom, L"Button")) {
            NMCUSTOMDRAW *cd = (NMCUSTOMDRAW *)l;
            if (cd->dwDrawStage == CDDS_PREPAINT) {
                drawButton(cd);
                return CDRF_SKIPDEFAULT;
            }
            return CDRF_DODEFAULT;
        }
        break;
    }
    }
    return DefSubclassProc(h, m, w, l);
}

// ---- one control: what its class needs beyond its parent's colours
static void control(HWND h) {
    if (allowWindow) allowWindow(h, TRUE);     // (dark menus only while Windows' app mode is dark: "allow")
    if (isClass(h, L"SysTreeView32")) {
        SendMessageW(h, TVM_SETBKCOLOR, 0, dark ? (LPARAM)pal[Surface] : (LPARAM)-1);
        SendMessageW(h, TVM_SETTEXTCOLOR, 0, dark ? (LPARAM)pal[Text] : (LPARAM)-1);
        SendMessageW(h, TVM_SETLINECOLOR, 0, dark ? (LPARAM)pal[Border] : (LPARAM)CLR_DEFAULT);
    } else if (isClass(h, L"RICHEDIT50W")) {
        SendMessageW(h, EM_SETBKGNDCOLOR, 0, dark ? (LPARAM)pal[Window] : (LPARAM)GetSysColor(COLOR_WINDOW));
    }
    LONG style = GetWindowLongW(h, GWL_STYLE);
    bool bars = (style & (WS_VSCROLL | WS_HSCROLL)) || isClass(h, L"SysTreeView32") || isClass(h, L"ListBox") ||
                isClass(h, L"msctls_trackbar32");
    if (bars) SetWindowTheme(h, dark ? L"DarkMode_Explorer" : nullptr, nullptr);
    if (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_CLIENTEDGE) SetWindowSubclass(h, edgeProc, SubId, 0);
}

static void container(HWND h) {
    if (allowWindow) allowWindow(h, TRUE);
    SetWindowSubclass(h, containerProc, SubId, 0);     // (again: the same one, nothing changes)
    if (GetWindowLongW(h, GWL_STYLE) & (WS_VSCROLL | WS_HSCROLL))
        SetWindowTheme(h, dark ? L"DarkMode_Explorer" : nullptr, nullptr);
}

extern "C" void kks_theme_init(const unsigned *colours, int n) {
    enabled = 1;
    for (int i = 0; i < NColours && i < n; i++) pal[i] = rgb(colours[i]);
    brWindow = CreateSolidBrush(pal[Window]);
    brSurface = CreateSolidBrush(pal[Surface]);
    appMenus();
}

extern "C" void kks_theme_set_dark(int on) { if (enabled) dark = on; }
extern "C" int kks_theme_dark() { return dark; }

extern "C" void kks_theme_container(HWND h) {
    if (!enabled || !h) return;
    container(h);
    HWND top = GetAncestor(h, GA_ROOT);
    if (top && !GetPropW(top, DoneProp)) {
        SetPropW(top, DoneProp, (HANDLE)1);
        container(top);
        topBar(top);
    }
}

extern "C" void kks_theme_control(HWND h) {
    if (!enabled || !h) return;
    control(h);
}

extern "C" void kks_theme_dim(HWND h) { if (enabled && h) SetPropW(h, DimProp, (HANDLE)1); }

static BOOL CALLBACK eachChild(HWND h, LPARAM) {
    control(h);
    // a window that holds controls (a page) is subclassed already; its scroll bar follows too
    if (GetWindowLongW(h, GWL_STYLE) & (WS_VSCROLL | WS_HSCROLL)) container(h);
    return TRUE;
}

static BOOL CALLBACK eachTop(HWND h, LPARAM) {
    if (!GetPropW(h, DoneProp)) return TRUE;           // only the app's own windows (not a task dialog)
    topBar(h);
    EnumChildWindows(h, eachChild, 0);
    RedrawWindow(h, nullptr, nullptr, RDW_INVALIDATE | RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN);
    return TRUE;
}

extern "C" void kks_theme_apply_all() {
    if (!enabled) return;
    typedef void (WINAPI *FlushFn)();
    if (kks_theme_menus_known(windowsBuild())) {
        HMODULE ux = GetModuleHandleW(L"uxtheme.dll");
        FlushFn flush = ux ? (FlushFn)(void *)GetProcAddress(ux, MAKEINTRESOURCEA(136)) : nullptr;
        if (flush) flush();
    }
    EnumThreadWindows(GetCurrentThreadId(), eachTop, 0);
}
