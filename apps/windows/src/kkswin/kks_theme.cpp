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
#include <oleacc.h>
#include <stdlib.h>
#include <algorithm>
using std::max;
using std::min;

enum { Window, Surface, Text, Dim, Border, Button, Hot, Down, Focus, Accent, AccentText, Disabled, Danger, DangerHot,
       DangerDown, NColours };

static int enabled = 0;      // the switch (theme.nim): nothing is subclassed or changed without it
static int dark = 0;         // the colours in use now: ours (dark) or the system's (light, high contrast)
static COLORREF pal[NColours];
static HBRUSH brWindow, brSurface;
static const UINT_PTR SubId = 0x4B4B5354;   // "KKST"
static const wchar_t *DimProp = L"kksThemeDim";
static const wchar_t *DoneProp = L"kksThemeTop";
static const wchar_t *DangerProp = L"kksThemeDanger";    // a button whose action can't be taken back (a question's)
static const wchar_t *ContainerProp = L"kksThemeContainer";

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
// the focus ring's width in device pixels: 2 px at 100 %, rounded up above it (3 at 125 and 150 %, 4 at 200 %)
extern "C" int kks_theme_ring_px(int dpi) { return max(2, (2 * dpi + 95) / 96); }
static int ringPx(HWND h) { return kks_theme_ring_px(dpiOf(h)); }

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
    LRESULT ui = SendMessageW(h, WM_QUERYUISTATE, 0, 0);
    bool cues = !(ui & UISF_HIDEACCEL);
    if (ui & UISF_HIDEFOCUS) focus = false;     // (as Windows' own buttons: no ring after a click, until a key is used)
    int ring = ringPx(h);                       // the focus ring: 2 px at 100 %, more at higher scaling
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
        COLORREF edge = disabled ? pal[Disabled] : pal[Border];
        HPEN pen = CreatePen(PS_SOLID, sc(h, 1), on && !disabled ? pal[Accent] : edge);
        // (under the mouse or pressed: the box lighter, never the focus colour)
        HBRUSH brush = CreateSolidBrush(on && !disabled ? pal[Accent] : (down ? pal[Down] : hot ? pal[Hot] : pal[Surface]));
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
        if (style & BS_MULTILINE) {      // (a label wider than the column at a larger text size: its lines wrap)
            DrawTextW(dc, text, -1, &m, DT_CALCRECT | DT_WORDBREAK | prefix);
            int th = m.bottom - m.top;
            if (th < t.bottom - t.top) t.top += (t.bottom - t.top - th) / 2;
            DrawTextW(dc, text, -1, &t, DT_LEFT | DT_WORDBREAK | prefix);
        } else {
            DrawTextW(dc, text, -1, &m, DT_CALCRECT | DT_SINGLELINE | prefix);
            DrawTextW(dc, text, -1, &t, DT_LEFT | DT_VCENTER | DT_SINGLELINE | prefix);
        }
        if (focus) {      // a ring round the label, in the text colour (3:1 and more against the window)
            int th = m.bottom - m.top;
            RECT f = {t.left - ring - sc(h, 1), r.top + (r.bottom - r.top - th) / 2 - ring,
                      min(t.left + (m.right - m.left) + ring + sc(h, 1), r.right), r.top + (r.bottom - r.top + th) / 2 + ring};
            f.top = max(f.top, r.top);
            f.bottom = min(f.bottom, r.bottom);
            frame(dc, f, pal[Focus], ring);
        }
    } else {
        // a push button: a filled box with a border; focus: a two-pixel ring in the focus colour
        bool danger = GetPropW(h, DangerProp) != nullptr;
        COLORREF face = disabled ? pal[Window] : danger ? (down ? pal[DangerDown] : hot ? pal[DangerHot] : pal[Danger])
                                                        : (down ? pal[Down] : hot ? pal[Hot] : pal[Button]);
        fill(dc, r, face);
        frame(dc, r, disabled ? pal[Disabled] : (focus ? pal[Focus] : pal[Border]), focus ? ring : 1);
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
    if (m == WM_NCCALCSIZE && w && dark && (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_CLIENTEDGE)) {
        // above 100 % the edge is as wide as the focus ring (Windows' client edge stays 2 device px at any scale)
        LRESULT res = DefSubclassProc(h, m, w, l);
        int extra = ringPx(h) - 2;
        if (extra > 0) InflateRect(&((NCCALCSIZE_PARAMS *)l)->rgrc[0], -extra, -extra);
        return res;
    }
    if (m == WM_NCPAINT && dark && (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_CLIENTEDGE)) {
        LRESULT res = DefSubclassProc(h, m, w, l);         // the scroll bars
        HDC dc = GetWindowDC(h);
        RECT r;
        GetWindowRect(h, &r);
        OffsetRect(&r, -r.left, -r.top);
        // the edge: a line in the edge colour; under the keyboard two lines in the focus colour (the second changes
        // from the field's colour to white: far above 3:1)
        bool focused = GetFocus() == h;
        int ring = ringPx(h);
        frame(dc, r, focused ? pal[Focus] : pal[Border], 1);
        InflateRect(&r, -1, -1);
        frame(dc, r, focused ? pal[Focus] : pal[Surface], ring - 1);
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
        RemovePropW(h, ContainerProp);
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
        if (isClass((HWND)l, L"Edit")) {          // a read-only field: still a field (its own colour, as its edge)
            SetTextColor((HDC)w, pal[Text]);
            SetBkColor((HDC)w, pal[Surface]);
            return (LRESULT)brSurface;
        }
        // fall through
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
        if (hd->code == NM_CUSTOMDRAW && isClass(hd->hwndFrom, L"SysTreeView32")) {
            // the selected item in the accent colour whether the tree has the keyboard or not (the theme's grey was
            // 1.1:1 on the tree; #510): the item is drawn as unselected, in our colours. The keyboard in the tree shows
            // as its edge turning white (edgeProc), as a field's
            NMTVCUSTOMDRAW *cd = (NMTVCUSTOMDRAW *)l;
            if (cd->nmcd.dwDrawStage == CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
            if (cd->nmcd.dwDrawStage == CDDS_ITEMPREPAINT && (cd->nmcd.uItemState & CDIS_SELECTED)) {
                cd->nmcd.uItemState &= ~(CDIS_SELECTED | CDIS_FOCUS);
                cd->clrText = pal[AccentText];
                cd->clrTextBk = pal[Accent];
                return CDRF_NEWFONT;
            }
            return CDRF_DODEFAULT;
        }
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
    // (not a list box: on Windows 11 26H2 the dark theme drew its selected row white, its text white on it, #506's
    // review; its scroll bar stays light)
    bool bars = ((style & (WS_VSCROLL | WS_HSCROLL)) || isClass(h, L"SysTreeView32") || isClass(h, L"msctls_trackbar32")) &&
                !isClass(h, L"ListBox");
    if (bars) SetWindowTheme(h, dark ? L"DarkMode_Explorer" : nullptr, nullptr);
    if (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_CLIENTEDGE) {
        SetWindowSubclass(h, edgeProc, SubId, 0);
        SetWindowPos(h, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
}

static void container(HWND h) {
    // once per window: a page's every new control asks for it (#506's review: hundreds of calls for a long list)
    if (GetPropW(h, ContainerProp) && GetPropW(h, ContainerProp) == (HANDLE)(INT_PTR)(dark + 1)) return;
    SetPropW(h, ContainerProp, (HANDLE)(INT_PTR)(dark + 1));
    // the app's own window classes paint their first frame in the theme's colour (no white flash as a window opens)
    wchar_t cls[64] = L"";
    GetClassNameW(h, cls, 64);
    if (!wcscmp(cls, L"KKSPage") || !wcscmp(cls, L"KKSPopup") || !wcscmp(cls, L"KKSCourse") || !wcscmp(cls, L"KKSMain"))
        SetClassLongPtrW(h, GCLP_HBRBACKGROUND, (LONG_PTR)(dark ? brWindow : GetSysColorBrush(COLOR_WINDOW)));
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
extern "C" void kks_theme_danger(HWND h) { if (enabled && h) SetPropW(h, DangerProp, (HANDLE)1); }

static BOOL CALLBACK eachChild(HWND h, LPARAM) {
    control(h);
    // a window that holds controls (a page) is subclassed already; its scroll bar follows too
    // the app's own windows that hold controls (a page) follow too; a field or list with a scroll bar is a control
    wchar_t cls[64] = L"";
    GetClassNameW(h, cls, 64);
    // (the windows that hold controls; the drawing, figures, pictures and photo canvases paint their own background)
    if (!wcscmp(cls, L"KKSPage") || !wcscmp(cls, L"KKSPopup") || !wcscmp(cls, L"KKSCourse") || !wcscmp(cls, L"KKSMain"))
        container(h);
    return TRUE;
}

static BOOL CALLBACK eachTop(HWND h, LPARAM) {
    if (!GetPropW(h, DoneProp)) return TRUE;           // only the app's own windows (not a task dialog)
    container(h);       // (its own background and class brush too: the strip behind the tabs, a course window's)
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

// ---- the app's own question to a screen reader as Windows' dialogs are: the dialog role (UI Automation's IsDialog),
// and what it means as its description (FullDescription), through the documented Dynamic Annotation (oleacc), on the
// window and its client area (UI Automation reads a top-level window's annotations from either)
static const GUID IsDialogGuid = {0x9d0dfb9b, 0x8436, 0x4501, {0xbb, 0xbb, 0xe5, 0x34, 0xa4, 0xfb, 0x3b, 0x3f}};
static const GUID FullDescriptionGuid = {0x0dc5e6ed, 0x3e16, 0x4bf1, {0x8f, 0x9a, 0xa9, 0x79, 0x87, 0x8b, 0xc1, 0x95}};
extern "C" int kks_theme_dialog_a11y(HWND h, const wchar_t *description) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);   // (already: S_FALSE or another mode; the call works either way)
    IAccPropServices *ps = nullptr;
    if (FAILED(CoCreateInstance(CLSID_AccPropServices, nullptr, CLSCTX_INPROC_SERVER, IID_IAccPropServices, (void **)&ps)))
        return 0;
    int ok = 1;
    for (LONG obj : {OBJID_WINDOW, OBJID_CLIENT}) {
        VARIANT role; VariantInit(&role); role.vt = VT_I4; role.lVal = ROLE_SYSTEM_DIALOG;
        VARIANT yes; VariantInit(&yes); yes.vt = VT_BOOL; yes.boolVal = VARIANT_TRUE;
        ok &= SUCCEEDED(ps->SetHwndProp(h, obj, CHILDID_SELF, PROPID_ACC_ROLE, role));
        ps->SetHwndProp(h, obj, CHILDID_SELF, IsDialogGuid, yes);       // (Windows 10 1809 and later)
        if (description && description[0]) {
            ok &= SUCCEEDED(ps->SetHwndPropStr(h, obj, CHILDID_SELF, PROPID_ACC_DESCRIPTION, description));
            ps->SetHwndPropStr(h, obj, CHILDID_SELF, FullDescriptionGuid, description);
            ps->SetHwndPropStr(h, obj, CHILDID_SELF, PROPID_ACC_HELP, description);   // (UI Automation's HelpText)
        }
    }
    ps->Release();
    return ok;
}
