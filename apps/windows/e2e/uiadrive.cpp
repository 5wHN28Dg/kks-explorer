// Drive a window through the native UI Automation core (what Narrator uses), for the Windows app's tests (decision
// 0033). uiadrive.exe <process name> <script> <log>; each script line is TAB-separated:
//   wait <name>             wait (15 s) until an element with this name exists ("~text" = name contains text)
//   click <name>            Invoke it (buttons)
//   set <name> <text>       set its value (edits; the name a field takes from its label)
//   enter <name>            open a list item (its default action, else focus + Enter)
//   keys <name> <vk,vk,…>   post key presses (virtual-key codes, hex or decimal) to the element's window
//   slide <name> <vk,vk,…>  the same to the slider of that name (a slider is named by the label before it, so
//                           `keys` finds the label): 0x24 Home = its lowest value, 0x23 End = its highest
//   drag <name> x0 y0 x1 y1 a left-button drag inside the element (fractions of its size), posted to its window
//   touchdrag <name> x0 y0 x1 y1  the same with one finger, injected as real touch input (InjectTouchInput; works
//                           without touch hardware), so the window gets WM_POINTER messages
//   select <name>           select a list item (SelectionItem), e.g. before a button that opens the selection
//   pick <name>             select a list item as a click on it does: the list box tells its parent (LBN_SELCHANGE),
//                           which SelectionItem alone doesn't, e.g. the sheet list, which opens the selected sheet
//   value <name> <text>     wait (15 s) until the field with this name holds a value containing text
//   gone <name>             wait until no element has this name
//   toggle <name>           flip a check box (Toggle)
//   state <name> on|off     wait (15 s) until the check box with this name is on / off
//   choose <name>           choose a radio button (its default action, what a screen reader does; BM_CLICK if none)
//   chosen <name>           wait (15 s) until the radio button with this name is the chosen one
//   close <name>            ask the top-level window holding this element to close (WM_CLOSE, as its X button)
//   shade <name> dark|light wait (20 s) until the middle half of the element, as drawn (PrintWindow), is dark paper
//                           with light lines (median grey < 40, some light pixels) or white paper with dark lines
//                           (median > 200, some dark pixels): dark drawings
//   boxdrag <window> <element> <fw> <fh>  a left-button drag in <window> from just above-left of <element> to its
//                           top-left plus fw × its width, fh × its height (a box around it and its neighbours)
//   escdrag <name> x0 y0 x1 y1 [hold]  a drag as `drag` that Escape (posted to its window) interrupts before the button
//                           is up; with "hold" the button stays down (until `mouseup`)
//   mouseup <name>          the left button up in the element's window
//   surface <name> dark|light  wait (10 s) until the element's whole rectangle as drawn (PrintWindow) has a median grey
//                           under 70 (dark) or over 190 (light): a control's or page's background in the app's theme
//   titlebar <name> dark|light  the same for the title bar of the window holding the element (PrintWindow with its
//                           frame): its median grey across the caption
//   dialog <name> <text>    the top-level window holding the element is a dialog to UI Automation (what a screen reader
//                           announces as one: its localized control type "dialog") and its description (FullDescription,
//                           or HelpText) holds <text>, e.g. what a question means
//   fits <name>             every control with text in the window holding the element shows all of it (#377: text size):
//                           a label's wrapped text, a field's line, a button's or check box's label and a list's rows
//                           fit their rectangles (measured with the control's own font), and no two controls of a
//                           page overlap; each one that doesn't is logged
//   range <name> <value>    set a slider (RangeValue) to the value, as a person dragging it does (Settings' Text size)
//   hover <name>            the mouse pointer to the element's middle (its hover look)
//   holddown <name>         the left button down on the element (its pressed look); letgo <name> cancels the press
//                           without a click
//   pixels <name> <rrggbb> <max>  the element as drawn (PrintWindow) has at most <max> pixels of this colour (each
//                           channel within 3): e.g. no box left on the drawing
//   press <name> <vk,vk,…>  real key presses (SendInput) with the keyboard focus on that element, its window in front:
//                           what a person's keyboard does there (an edit or list of that name before any other
//                           element of it; `keys` posts to the first element, which may be the window or a label)
//   resize <name> <w> <h>   the top-level window holding the element restored and resized to w x h physical px (the
//                           driver is per-monitor DPI aware); at most what the screen allows, logged
//   apart <drawing>         no control of the drawing's window meets the drawing's rectangle, and every button, field,
//                           list and check box wholly in view is what UI Automation's hit test finds at its middle
//   clear <drawing> <name>  the same for the controls of that name only (at least one must be there)
//   clipboard <text>        wait (10 s) until the clipboard holds exactly this text (CF_UNICODETEXT; ASCII)
//   sleep <ms>
//   dump                    log every element (type, name)
// Exits 0 when every line passed, 1 at the first failure (logged).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <uiautomation.h>
#include <cstdio>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cstdint>

static IUIAutomation *ua;
static FILE *logf;
static std::wstring exeName;     // the program is found again by name if it restarted (a wiped device does)

static std::wstring wide(const std::string &s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    std::wstring w(n ? n - 1 : 0, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
    return w;
}
static std::string utf8(const wchar_t *w) {
    if (!w) return "";
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
    std::string s(n ? n - 1 : 0, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, nullptr, nullptr);
    return s;
}
static void say(const std::string &m) {
    SYSTEMTIME t; GetLocalTime(&t);
    fprintf(logf, "%02d:%02d:%02d %s\n", t.wHour, t.wMinute, t.wSecond, m.c_str());
    fflush(logf);
}

static DWORD pid_of(const std::wstring &exe) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32W e = {sizeof e};
    DWORD pid = 0;
    for (BOOL ok = Process32FirstW(snap, &e); ok; ok = Process32NextW(snap, &e))
        if (_wcsicmp(e.szExeFile, exe.c_str()) == 0) pid = e.th32ProcessID;
    CloseHandle(snap);
    return pid;
}

// every top-level window of the process (the main window and its popups)
static std::vector<IUIAutomationElement *> roots(DWORD pid) {
    std::vector<IUIAutomationElement *> out;
    IUIAutomationElement *desk = nullptr;
    ua->GetRootElement(&desk);
    VARIANT v; v.vt = VT_I4; v.lVal = (LONG)pid;
    IUIAutomationCondition *c = nullptr;
    ua->CreatePropertyCondition(UIA_ProcessIdPropertyId, v, &c);
    IUIAutomationElementArray *arr = nullptr;
    if (desk && c && SUCCEEDED(desk->FindAll(TreeScope_Children, c, &arr)) && arr) {
        int n = 0; arr->get_Length(&n);
        for (int i = 0; i < n; i++) { IUIAutomationElement *e = nullptr; arr->GetElement(i, &e); out.push_back(e); }
        arr->Release();
    }
    if (c) c->Release();
    if (desk) desk->Release();
    return out;
}

static std::string type_name(CONTROLTYPEID t) {
    switch (t) {
    case UIA_ButtonControlTypeId: return "Button"; case UIA_EditControlTypeId: return "Edit";
    case UIA_TextControlTypeId: return "Text"; case UIA_ListControlTypeId: return "List";
    case UIA_ListItemControlTypeId: return "ListItem"; case UIA_PaneControlTypeId: return "Pane";
    case UIA_WindowControlTypeId: return "Window"; case UIA_CheckBoxControlTypeId: return "CheckBox";
    case UIA_ImageControlTypeId: return "Image"; case UIA_ScrollBarControlTypeId: return "ScrollBar";
    case UIA_TitleBarControlTypeId: return "TitleBar"; case UIA_DocumentControlTypeId: return "Document";
    case UIA_TreeControlTypeId: return "Tree"; case UIA_TreeItemControlTypeId: return "TreeItem";
    default: return "Type" + std::to_string(t);
    }
}

static DWORD pid_of(const std::wstring &exe);

// the element as drawn, the middle half of it: (median grey, light pixels, dark pixels, pixels); false if not captured
static bool shade_of(IUIAutomationElement *e, int &median, int &light, int &dark, int &n) {
    UIA_HWND hw = 0;
    e->get_CurrentNativeWindowHandle(&hw);
    if (!hw) return false;
    HWND root = GetAncestor((HWND)hw, GA_ROOT);
    RECT rr, er;
    GetWindowRect(root, &rr);
    GetWindowRect((HWND)hw, &er);
    int W = rr.right - rr.left, H = rr.bottom - rr.top;
    if (W <= 0 || H <= 0) return false;
    HDC sdc = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(sdc);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader; bi.bmiHeader.biWidth = W; bi.bmiHeader.biHeight = -H;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP bmp = CreateDIBSection(sdc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    HGDIOBJ old = SelectObject(dc, bmp);
    bool ok = PrintWindow(root, dc, 2 /* PW_RENDERFULLCONTENT: Direct2D content too */) != 0;
    if (ok) {
        int x0 = er.left - rr.left, y0 = er.top - rr.top, w = er.right - er.left, h = er.bottom - er.top;
        std::vector<int> greys;
        light = dark = 0;
        for (int y = y0 + h / 4; y < y0 + 3 * h / 4; y++)
            for (int x = x0 + w / 4; x < x0 + 3 * w / 4; x++) {
                if (x < 0 || y < 0 || x >= W || y >= H) continue;
                const uint8_t *p = (const uint8_t *)bits + ((size_t)y * W + x) * 4;
                int b = p[0], g = p[1], r = p[2];
                int mx = std::max(r, std::max(g, b)), mn = std::min(r, std::min(g, b));
                greys.push_back((r + g + b) / 3);
                if (mn > 170 && mx - mn < 30) light++;
                if (mx < 90) dark++;
            }
        n = (int)greys.size();
        if (n == 0) ok = false;
        else { std::nth_element(greys.begin(), greys.begin() + n / 2, greys.end()); median = greys[n / 2]; }
    }
    SelectObject(dc, old); DeleteObject(bmp); DeleteDC(dc); ReleaseDC(nullptr, sdc);
    return ok;
}

// the median grey of a rectangle of the element's top-level window as drawn (PrintWindow): the element's own, or the caption
static int median_grey(IUIAutomationElement *e, bool caption) {
    UIA_HWND hw = 0;
    e->get_CurrentNativeWindowHandle(&hw);
    if (!hw) return -1;
    HWND root = GetAncestor((HWND)hw, GA_ROOT);
    RECT rr, er;
    GetWindowRect(root, &rr);
    GetWindowRect((HWND)hw, &er);
    int W = rr.right - rr.left, H = rr.bottom - rr.top;
    if (W <= 0 || H <= 0) return -1;
    HDC sdc = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(sdc);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader; bi.bmiHeader.biWidth = W; bi.bmiHeader.biHeight = -H;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP bmp = CreateDIBSection(sdc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    HGDIOBJ old = SelectObject(dc, bmp);
    // (the whole window as drawn, its frame too: a capture of the screen read the Windows 10 VM's dark title bar as white)
    bool ok = PrintWindow(root, dc, 2) != 0;
    int med = -1;
    if (ok) {
        int x0, y0, x1, y1;
        if (caption) {
            // the caption between the window's frame and its client area, away from the icon, title and buttons
            POINT c = {0, 0};
            ClientToScreen(root, &c);
            x0 = W / 3; x1 = W / 2; y0 = 4; y1 = std::max(6L, c.y - rr.top - 4);
        } else {
            x0 = er.left - rr.left; y0 = er.top - rr.top; x1 = er.right - rr.left; y1 = er.bottom - rr.top;
        }
        std::vector<int> greys;
        for (int y = std::max(0, y0); y < std::min(H, y1); y++)
            for (int x = std::max(0, x0); x < std::min(W, x1); x++) {
                const uint8_t *p = (const uint8_t *)bits + ((size_t)y * W + x) * 4;
                greys.push_back((p[0] + p[1] + p[2]) / 3);
            }
        if (!greys.empty()) {
            std::nth_element(greys.begin(), greys.begin() + greys.size() / 2, greys.end());
            med = greys[greys.size() / 2];
        }
    }
    SelectObject(dc, old); DeleteObject(bmp); DeleteDC(dc); ReleaseDC(nullptr, sdc);
    return med;
}

// ---- fits: does every control's text fit its control (measured in its own font)?
struct FitCtx { int bad; std::vector<HWND> all; };
static std::string utf8(const std::wstring &w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string s(n ? n - 1 : 0, '\0');
    if (n) WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &s[0], n, nullptr, nullptr);
    return s;
}
static BOOL CALLBACK collect(HWND h, LPARAM l) {
    if (IsWindowVisible(h)) ((FitCtx *)l)->all.push_back(h);
    return TRUE;
}
static SIZE need(HWND h, const std::wstring &t, int width, bool wrap, bool editc = false) {
    // (the control's font is the app's: a GDI handle of another process can't be selected here, so a copy is made
    // from its description)
    LOGFONTW lf = {};
    HFONT theirs = (HFONT)SendMessageW(h, WM_GETFONT, 0, 0);
    HFONT mine = theirs && GetObjectW(theirs, sizeof lf, &lf) ? CreateFontIndirectW(&lf) : nullptr;
    if (theirs && !mine) say("  (could not read the font of a control: measured in the default GUI font)");
    HDC dc = GetDC(h);
    HGDIOBJ old = SelectObject(dc, mine ? (HGDIOBJ)mine : GetStockObject(DEFAULT_GUI_FONT));
    RECT r = {0, 0, width, 0};
    // (DT_EDITCONTROL for a label with SS_EDITCONTROL: it breaks long words as an edit control does)
    DrawTextW(dc, t.c_str(), -1, &r, DT_CALCRECT | DT_NOPREFIX | (wrap ? DT_WORDBREAK : DT_SINGLELINE) | (editc ? DT_EDITCONTROL : 0));
    TEXTMETRICW tm = {};
    GetTextMetricsW(dc, &tm);
    SelectObject(dc, old);
    ReleaseDC(h, dc);
    if (mine) DeleteObject(mine);
    SIZE s = {r.right - r.left, std::max<LONG>(r.bottom - r.top, tm.tmHeight)};
    return s;
}
static int fits(IUIAutomationElement *e) {
    UIA_HWND hw = 0;
    e->get_CurrentNativeWindowHandle(&hw);
    if (!hw) return -1;
    HWND root = GetAncestor((HWND)hw, GA_ROOT);
    FitCtx c = {0, {}};
    EnumChildWindows(root, collect, (LPARAM)&c);
    for (HWND h : c.all) {
        wchar_t cls[64] = L"";
        GetClassNameW(h, cls, 64);
        int n = GetWindowTextLengthW(h);
        std::wstring t(n, L'\0');
        if (n) GetWindowTextW(h, &t[0], n + 1);
        RECT r;
        GetClientRect(h, &r);
        LONG style = GetWindowLongW(h, GWL_STYLE);
        std::string why;
        if (!_wcsicmp(cls, L"Static")) {
            int kind = style & SS_TYPEMASK;
            if (n && kind != SS_OWNERDRAW && kind != SS_ICON && kind != SS_BITMAP) {
                SIZE s = need(h, t, r.right, true, (style & SS_EDITCONTROL) != 0);
                if (s.cy > r.bottom) why = "text " + std::to_string(s.cy) + " px tall in " + std::to_string(r.bottom);
            }
        } else if (!_wcsicmp(cls, L"Edit")) {
            SIZE s = need(h, L"Ag", 1000, false);
            if (!(style & ES_MULTILINE) && s.cy > r.bottom) why = "a line " + std::to_string(s.cy) + " px tall in " + std::to_string(r.bottom);
            else if ((style & ES_MULTILINE) && (style & ES_READONLY) && n) {   // a value on several lines: all in view
                SIZE w2 = need(h, t, std::max<LONG>(1, r.right - MulDiv(8, (int)GetDpiForWindow(h), 96)), true, true);
                if (w2.cy > r.bottom) why = "value " + std::to_string(w2.cy) + " px tall in " + std::to_string(r.bottom);
            } else if (!(style & ES_MULTILINE) && (style & ES_READONLY) && n) {   // a value to read on one line: all of it
                SIZE w1 = need(h, t, 0, false);
                if (w1.cx + MulDiv(6, (int)GetDpiForWindow(h), 96) > r.right) why = "value " + std::to_string(w1.cx) + " px wide in " + std::to_string(r.right);
            }
        } else if (!_wcsicmp(cls, L"Button") && n) {
            int kind = style & BS_TYPEMASK;
            std::wstring shown;      // (the label as drawn: "&&" is one "&", a lone "&" marks the access key)
            for (size_t i = 0; i < t.size(); i++) { if (t[i] == L'&' && i + 1 < t.size()) i++; shown += t[i]; }
            if ((kind == BS_AUTOCHECKBOX || kind == BS_CHECKBOX || kind == BS_AUTORADIOBUTTON || kind == BS_RADIOBUTTON) &&
                (style & BS_MULTILINE)) {
                int box = MulDiv(24, (int)GetDpiForWindow(h), 96);
                SIZE s = need(h, shown, std::max<LONG>(1, r.right - box), true);
                if (s.cy > r.bottom) why = "label " + std::to_string(s.cy) + " px tall in " + std::to_string(r.bottom);
            } else if (kind == BS_AUTOCHECKBOX || kind == BS_CHECKBOX || kind == BS_AUTORADIOBUTTON || kind == BS_RADIOBUTTON) {
                SIZE s = need(h, shown, 0, false);
                int box = MulDiv(24, (int)GetDpiForWindow(h), 96);   // (the box and the gap before the label)
                if (s.cy > r.bottom || s.cx + box > r.right) why = "label " + std::to_string(s.cx) + "x" + std::to_string(s.cy) + " with its box";
            } else if (style & BS_MULTILINE) {
                // (and no word broken: each word on a line of its own still fits)
                size_t a = 0;
                while (why.empty() && a < shown.size()) {
                    size_t b = shown.find(L' ', a);
                    if (b == std::wstring::npos) b = shown.size();
                    SIZE ws = need(h, shown.substr(a, b - a), 0, false);
                    if (ws.cx + MulDiv(12, (int)GetDpiForWindow(h), 96) > r.right) why = "the word \"" + utf8(shown.substr(a, b - a)) + "\" broken";
                    a = b + 1;
                }
                SIZE s = need(h, shown, std::max<LONG>(1, r.right - MulDiv(12, (int)GetDpiForWindow(h), 96)), true);
                if (s.cy > r.bottom) why = "text " + std::to_string(s.cy) + " px tall in " + std::to_string(r.bottom);
            } else {
                SIZE s = need(h, shown, 0, false);
                // (with the room the button's edge and padding take: 3 px a side at 100 %)
                if (s.cy > r.bottom || s.cx + MulDiv(6, (int)GetDpiForWindow(h), 96) > r.right)
                    why = "label " + std::to_string(s.cx) + "x" + std::to_string(s.cy);
            }
        } else if (!_wcsicmp(cls, L"ListBox")) {
            SIZE s = need(h, L"Ag", 1000, false);
            LRESULT ih = SendMessageW(h, LB_GETITEMHEIGHT, 0, 0);
            if (!(style & LBS_OWNERDRAWVARIABLE) && ih < s.cy)
                why = "rows " + std::to_string(ih) + " px for a line of " + std::to_string(s.cy);
            // a plain list's rows: each one's text whole (owner-drawn rows mark a cut with an ellipsis, or wrap)
            if (why.empty() && !(style & (LBS_OWNERDRAWFIXED | LBS_OWNERDRAWVARIABLE))) {
                LRESULT count = SendMessageW(h, LB_GETCOUNT, 0, 0);
                for (LRESULT k = 0; k < count && why.empty(); k++) {
                    LRESULT len = SendMessageW(h, LB_GETTEXTLEN, k, 0);
                    if (len <= 0) continue;
                    std::wstring row(len + 1, L'\0');
                    SendMessageW(h, LB_GETTEXT, k, (LPARAM)&row[0]);
                    row.resize(len);
                    SIZE rs = need(h, row, 0, false);
                    if (rs.cx + MulDiv(4, (int)GetDpiForWindow(h), 96) > r.right) why = "row \"" + utf8(row.substr(0, 40)) + "\" cut";
                }
            }
        }
        if (!why.empty()) {
            LOGFONTW lf = {};
            HFONT hf = (HFONT)SendMessageW(h, WM_GETFONT, 0, 0);
            if (hf) GetObjectW(hf, sizeof lf, &lf);
            say("  cut off: " + utf8(cls) + " \"" + utf8(t.substr(0, 60)) + "\" " + std::to_string(r.right) + "x" +
                std::to_string(r.bottom) + ": " + why + " (font " + std::to_string(lf.lfHeight) + ")");
            c.bad++;
        }
    }
    // every control inside its parent's width (a page scrolls up and down, so only sideways): never cut by its container
    for (HWND h : c.all) {
        RECT r, pc;
        HWND par = GetParent(h);
        if (!par || !GetWindowRect(h, &r) || !GetClientRect(par, &pc)) continue;
        POINT a = {pc.left, pc.top}, b = {pc.right, pc.bottom};
        ClientToScreen(par, &a); ClientToScreen(par, &b);
        if (r.left < a.x || r.right > b.x) {
            wchar_t t[80] = L"", cls[64] = L"";
            GetWindowTextW(h, t, 80); GetClassNameW(h, cls, 64);
            say("  outside its parent's width: " + utf8(cls) + " \"" + utf8(t) + "\" " + std::to_string(r.left) + "-" +
                std::to_string(r.right) + " in " + std::to_string(a.x) + "-" + std::to_string(b.x));
            c.bad++;
        }
    }
    // no two controls of one parent overlap: the window's own parts (tabs, the sidebar, the drawing, the panel, the
    // status line) too, and a page's controls and pictures
    for (size_t i = 0; i < c.all.size(); i++)
        for (size_t j = 0; j < i; j++) {
            HWND a = c.all[i], b = c.all[j];
            if (GetParent(a) != GetParent(b)) continue;
            // (an empty label shows nothing that could be covered or cover: the status line behind the setup screen)
            wchar_t c1[16] = L"", c2[16] = L"";
            GetClassNameW(a, c1, 16); GetClassNameW(b, c2, 16);
            if ((!_wcsicmp(c1, L"Static") && !GetWindowTextLengthW(a)) || (!_wcsicmp(c2, L"Static") && !GetWindowTextLengthW(b))) continue;
            RECT ra, rb, x;
            GetWindowRect(a, &ra); GetWindowRect(b, &rb);
            if (IntersectRect(&x, &ra, &rb)) {
                wchar_t ta[80] = L"", tb[80] = L"";
                GetWindowTextW(a, ta, 80); GetWindowTextW(b, tb, 80);
                auto rs = [](RECT r) { return std::to_string(r.left) + "," + std::to_string(r.top) + "-" + std::to_string(r.right) + "," + std::to_string(r.bottom); };
                say("  overlap: \"" + utf8(ta) + "\" " + rs(ra) + " and \"" + utf8(tb) + "\" " + rs(rb));
                c.bad++;
            }
        }
    say("  " + std::to_string(c.all.size()) + " windows looked at");
    return c.bad;
}

// pixels of the element, as drawn, within 3 of this colour in each channel; -1 if not captured
static int count_colour(IUIAutomationElement *e, int R, int G, int B) {
    UIA_HWND hw = 0;
    e->get_CurrentNativeWindowHandle(&hw);
    if (!hw) return -1;
    HWND root = GetAncestor((HWND)hw, GA_ROOT);
    RECT rr, er;
    GetWindowRect(root, &rr);
    GetWindowRect((HWND)hw, &er);
    int W = rr.right - rr.left, H = rr.bottom - rr.top;
    if (W <= 0 || H <= 0) return -1;
    HDC sdc = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(sdc);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader; bi.bmiHeader.biWidth = W; bi.bmiHeader.biHeight = -H;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP bmp = CreateDIBSection(sdc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    HGDIOBJ old = SelectObject(dc, bmp);
    int n = -1;
    if (PrintWindow(root, dc, 2 /* PW_RENDERFULLCONTENT */)) {
        n = 0;
        for (int y = std::max(0L, er.top - rr.top); y < std::min((LONG)H, er.bottom - rr.top); y++)
            for (int x = std::max(0L, er.left - rr.left); x < std::min((LONG)W, er.right - rr.left); x++) {
                const uint8_t *p = (const uint8_t *)bits + ((size_t)y * W + x) * 4;
                if (abs(p[2] - R) <= 3 && abs(p[1] - G) <= 3 && abs(p[0] - B) <= 3) n++;
            }
    }
    SelectObject(dc, old); DeleteObject(bmp); DeleteDC(dc); ReleaseDC(nullptr, sdc);
    return n;
}

// only/only2: the control types that may match (0 = any); select and enter take list and tree items
static IUIAutomationElement *find(DWORD &pid, const std::string &spec, bool dump = false, CONTROLTYPEID only = 0, CONTROLTYPEID only2 = 0) {
    { auto rs = roots(pid); if (rs.empty()) { DWORD np = pid_of(exeName); if (np) pid = np; } for (auto *r : rs) r->Release(); }
    bool contains = !spec.empty() && spec[0] == '~';
    std::wstring want = wide(contains ? spec.substr(1) : spec);
    IUIAutomationCondition *all = nullptr;
    ua->CreateTrueCondition(&all);
    IUIAutomationElement *hit = nullptr;
    for (auto *r : roots(pid)) {
        IUIAutomationElementArray *arr = nullptr;
        if (!hit && SUCCEEDED(r->FindAll(TreeScope_Subtree, all, &arr)) && arr) {
            int n = 0; arr->get_Length(&n);
            for (int i = 0; i < n && !hit; i++) {
                IUIAutomationElement *e = nullptr; arr->GetElement(i, &e);
                BSTR name = nullptr; e->get_CurrentName(&name);
                std::wstring nm = name ? name : L"";
                if (dump) {
                    CONTROLTYPEID t = 0; e->get_CurrentControlType(&t);
                    std::string val;
                    if (t == UIA_EditControlTypeId) {     // an edit's value too: what a failed `value` saw
                        IUIAutomationValuePattern *vp = nullptr;
                        if (SUCCEEDED(e->GetCurrentPatternAs(UIA_ValuePatternId, __uuidof(IUIAutomationValuePattern), (void **)&vp)) && vp) {
                            BSTR v = nullptr;
                            if (SUCCEEDED(vp->get_CurrentValue(&v)) && v) { val = " = '" + utf8(v) + "'"; SysFreeString(v); }
                            vp->Release();
                        }
                    }
                    say("  " + type_name(t) + " '" + utf8(nm.c_str()) + "'" + val);
                }
                CONTROLTYPEID ct = 0;
                if (only) e->get_CurrentControlType(&ct);
                if (!dump && (!only || ct == only || (only2 && ct == only2)) && ((contains && nm.find(want) != std::wstring::npos) || (!contains && nm == want))) { hit = e; hit->AddRef(); }
                if (name) SysFreeString(name);
                e->Release();
            }
            arr->Release();
        }
        r->Release();
    }
    all->Release();
    return hit;
}

static IUIAutomationElement *wait_for(DWORD &pid, const std::string &spec, int ms = 15000, CONTROLTYPEID only = 0, CONTROLTYPEID only2 = 0) {
    for (int t = 0; t < ms; t += 300) {
        if (auto *e = find(pid, spec, false, only, only2)) return e;
        Sleep(300);
    }
    return nullptr;
}

// where the keyboard focus is instead (its name, type, process and window) and the window in front: what a failed
// focus check saw, so that a window of another program in front tells itself apart from the app moving the focus
static void say_focus() {
    IUIAutomationElement *fe = nullptr;
    std::string what = "nothing";
    if (SUCCEEDED(ua->GetFocusedElement(&fe)) && fe) {
        BSTR name = nullptr; fe->get_CurrentName(&name);
        CONTROLTYPEID t = 0; fe->get_CurrentControlType(&t);
        int pid = 0; fe->get_CurrentProcessId(&pid);
        UIA_HWND hw = 0; fe->get_CurrentNativeWindowHandle(&hw);
        wchar_t cls[128] = L""; if (hw) GetClassNameW((HWND)hw, cls, 128);
        what = "'" + utf8(name) + "' type " + std::to_string(t) + " pid " + std::to_string(pid) + " class " + utf8(cls);
        if (name) SysFreeString(name);
        fe->Release();
    }
    HWND fg = GetForegroundWindow();
    wchar_t title[256] = L"", cls[128] = L"";
    DWORD fpid = 0;
    if (fg) { GetWindowTextW(fg, title, 256); GetClassNameW(fg, cls, 128); GetWindowThreadProcessId(fg, &fpid); }
    say("  (the focus is on " + what + "; in front: '" + utf8(title) + "' class " + utf8(cls) + " pid " + std::to_string(fpid) + ")");
}

// The keyboard focus to e (select: also select it, as a click would), and look that it is there before going on, as
// a user does: a list or tree the app rebuilt after e was found (new data from a sync) holds a new item, found again
// by its spec. false (and the reason logged) if it never got there.
static bool focus_on(DWORD &pid, IUIAutomationElement *&e, const std::string &spec, int ms, CONTROLTYPEID only,
                     CONTROLTYPEID only2, bool select) {
    for (ULONGLONG end = GetTickCount64() + (ULONGLONG)ms; GetTickCount64() < end;) {   // a pass can take seconds
        if (select) {
            IUIAutomationSelectionItemPattern *sp = nullptr;
            if (SUCCEEDED(e->GetCurrentPatternAs(UIA_SelectionItemPatternId, __uuidof(IUIAutomationSelectionItemPattern), (void **)&sp)) && sp) {
                sp->Select(); sp->Release();
            }
        }
        e->SetFocus();
        Sleep(200);
        IUIAutomationElement *fe = nullptr;
        BOOL same = FALSE;
        if (SUCCEEDED(ua->GetFocusedElement(&fe)) && fe) { ua->CompareElements(fe, e, &same); fe->Release(); }
        if (same) return true;
        say("(" + spec + " is not focused: replaced since it was found; again)");
        e->Release();
        e = wait_for(pid, spec, 5000, only, only2);
        if (!e) { say("ERROR: gone: " + spec); find(pid, "", true); return false; }
        Sleep(300);
    }
    say("ERROR: can't focus " + spec); say_focus(); find(pid, "", true);
    return false;
}

static bool within(IUIAutomationElement *e, IUIAutomationElement *anc, IUIAutomationTreeWalker *tw) {
    IUIAutomationElement *x = e; x->AddRef();
    while (x) {
        BOOL same = FALSE; ua->CompareElements(x, anc, &same);
        if (same) { x->Release(); return true; }
        IUIAutomationElement *p = nullptr; tw->GetParentElement(x, &p); x->Release(); x = p;
    }
    return false;
}

// `apart` / `clear`: the controls of the drawing's window (every one, or only those named `only`) beside the drawing,
// never over or under it: no control's rectangle meets the drawing's, and each button, field, list and check box that
// is wholly in view is the element found at its middle (UI Automation's hit test, what a click there reaches; no hover
// first). -> how many failed (each logged); a named control that isn't there counts as one
static int apart(DWORD &pid, IUIAutomationElement *drawing, const std::string &only) {
    RECT dr; drawing->get_CurrentBoundingRectangle(&dr);
    UIA_HWND dh = 0; drawing->get_CurrentNativeWindowHandle(&dh);
    HWND root = dh ? GetAncestor((HWND)dh, GA_ROOT) : nullptr;
    if (!root) { say("ERROR: the drawing has no window"); return 1; }
    // the window in front first, as a person sees it (the script's console window starts in front of it); then the
    // hit test is about the window's own children. On top of the others too, even when it is already the foreground
    // window: the console of a script started by the Task Scheduler is shown above it without taking the
    // foreground, so the window could be active and still covered (#458, #480: a "Text Area" document, the
    // console's, found where the sidebar's controls are, once Windows placed that console over the sidebar)
    if (GetForegroundWindow() != root) { SetForegroundWindow(root); Sleep(500); }
    SetWindowPos(root, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    Sleep(300);
    if (GetForegroundWindow() != root) say("  (the window could not come to the front: a hit test may find what covers it)");
    RECT cr; GetClientRect(root, &cr);
    POINT c0{cr.left, cr.top}, c1{cr.right, cr.bottom}; ClientToScreen(root, &c0); ClientToScreen(root, &c1);
    MONITORINFO mi = {sizeof mi}; GetMonitorInfoW(MonitorFromWindow(root, MONITOR_DEFAULTTONEAREST), &mi);
    RECT work = mi.rcWork;
    IUIAutomationTreeWalker *tw = nullptr; ua->get_RawViewWalker(&tw);
    IUIAutomationElement *top = nullptr; ua->ElementFromHandle((UIA_HWND)root, &top);
    IUIAutomationCondition *all = nullptr; ua->CreateTrueCondition(&all);
    IUIAutomationElementArray *arr = nullptr;
    int bad = 0, seen = 0, hit = 0;
    if (top && SUCCEEDED(top->FindAll(TreeScope_Descendants, all, &arr)) && arr) {
        int n = 0; arr->get_Length(&n);
        for (int i = 0; i < n; i++) {
            IUIAutomationElement *el = nullptr; arr->GetElement(i, &el);
            BSTR bn = nullptr; el->get_CurrentName(&bn);
            std::string name = utf8(bn); if (bn) SysFreeString(bn);
            CONTROLTYPEID t = 0; el->get_CurrentControlType(&t);
            bool control = t == UIA_ButtonControlTypeId || t == UIA_EditControlTypeId || t == UIA_ListControlTypeId ||
                           t == UIA_ListItemControlTypeId || t == UIA_CheckBoxControlTypeId || t == UIA_RadioButtonControlTypeId ||
                           t == UIA_TextControlTypeId || t == UIA_ComboBoxControlTypeId || t == UIA_HyperlinkControlTypeId ||
                           t == UIA_TreeControlTypeId || t == UIA_TreeItemControlTypeId;
            RECT r; el->get_CurrentBoundingRectangle(&r);
            if (!control || (!only.empty() && name != only) || r.right <= r.left || r.bottom <= r.top || within(el, drawing, tw)) {
                el->Release(); continue;
            }
            seen++;
            std::string what = type_name(t) + " '" + name + "' at " + std::to_string(r.left) + "," + std::to_string(r.top) + " " +
                               std::to_string(r.right - r.left) + "x" + std::to_string(r.bottom - r.top);
            if (r.left < dr.right && dr.left < r.right && r.top < dr.bottom && dr.top < r.bottom) {
                bad++;
                say("  over the drawing (" + std::to_string(dr.left) + "," + std::to_string(dr.top) + " " +
                    std::to_string(dr.right - dr.left) + "x" + std::to_string(dr.bottom - dr.top) + "): " + what);
            }
            UIA_HWND hw = 0; el->get_CurrentNativeWindowHandle(&hw);
            bool test = hw && IsWindowVisible((HWND)hw) && (t == UIA_ButtonControlTypeId || t == UIA_EditControlTypeId ||
                        t == UIA_ListControlTypeId || t == UIA_CheckBoxControlTypeId || t == UIA_RadioButtonControlTypeId);
            if (test) {      // wholly in view: inside its page, the main window's client area and the work area (the
                             // taskbar, always on top, may cover the bottom of a window as tall as the screen)
                RECT pr; GetWindowRect(GetParent((HWND)hw), &pr);
                test = r.left >= std::max({pr.left, c0.x, work.left}) && r.top >= std::max({pr.top, c0.y, work.top}) &&
                       r.right <= std::min({pr.right, c1.x, work.right}) && r.bottom <= std::min({pr.bottom, c1.y, work.bottom});
            }
            if (test) {
                hit++;
                POINT mid{(r.left + r.right) / 2, (r.top + r.bottom) / 2};
                IUIAutomationElement *at = nullptr;
                if (FAILED(ua->ElementFromPoint(mid, &at)) || !at || !within(at, el, tw)) {
                    bad++;
                    std::string got = "nothing";
                    if (at) {
                        BSTR an = nullptr; at->get_CurrentName(&an); CONTROLTYPEID at_t = 0; at->get_CurrentControlType(&at_t);
                        got = type_name(at_t) + " '" + utf8(an) + "'"; if (an) SysFreeString(an);
                    }
                    say("  not reached at its middle: " + what + " (found " + got + ")");
                }
                if (at) at->Release();
            }
            el->Release();
        }
        arr->Release();
    }
    if (all) all->Release();
    if (top) top->Release();
    if (tw) tw->Release();
    say("  " + std::to_string(seen) + " controls beside the drawing, " + std::to_string(hit) + " hit-tested");
    if (!only.empty() && seen == 0) { say("  no control named " + only); bad++; }
    return bad;
}

int wmain(int argc, wchar_t **argv) {
    if (argc < 4) { fprintf(stderr, "uiadrive <exe name> <script> <log>\n"); return 2; }
    logf = _wfopen(argv[3], L"a");
    // every rectangle and point in physical pixels, UI Automation's and the window's alike: an unaware driver at 125 %
    // got UIA's rectangles and its own window metrics scaled and rounded apart (the title bar's buttons 1 px into the
    // drawing on a real laptop); at 100 %, as the VMs run, nothing changes
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation), (void **)&ua))) {
        say("ERROR: no UI Automation"); return 1;
    }
    DWORD pid = 0;
    exeName = argv[1];
    for (int t = 0; t < 20000 && !pid; t += 300) { pid = pid_of(argv[1]); if (!pid) Sleep(300); }
    if (!pid) { say("ERROR: the program is not running"); return 1; }
    std::ifstream in(argv[2]);
    std::string line;
    int lineNo = 0;
    while (std::getline(in, line)) {
        lineNo++;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty() || line[0] == '#') continue;
        std::vector<std::string> f;
        std::stringstream ss(line);
        std::string part;
        while (std::getline(ss, part, '\t')) f.push_back(part);
        const std::string &cmd = f[0];
        std::string arg = f.size() > 1 ? f[1] : "";
        say("> " + line);
        if (cmd == "sleep") { Sleep(std::stoi(arg)); continue; }
        if (cmd == "dump") { find(pid, "", true); continue; }
        if (cmd == "clipboard") {
            std::string got = "(nothing)";
            for (int t = 0; t < 10000; t += 300) {
                if (OpenClipboard(nullptr)) {
                    HANDLE h = GetClipboardData(CF_UNICODETEXT);
                    if (h) {
                        const wchar_t *w = (const wchar_t *)GlobalLock(h);
                        got.clear();
                        if (w) for (; *w; w++) got += *w < 128 ? (char)*w : '?';
                        GlobalUnlock(h);
                    }
                    CloseClipboard();
                }
                if (got == arg) break;
                Sleep(300);
            }
            if (got != arg) { say("ERROR: the clipboard holds " + got + ", not " + arg); return 1; }
            continue;
        }
        if (cmd == "gone") {
            bool gone = false;
            for (int t = 0; t < 30000 && !gone; t += 300) { auto *e = find(pid, arg); if (e) { e->Release(); Sleep(300); } else gone = true; }
            if (!gone) { say("ERROR: still there: " + arg); return 1; }
            continue;
        }
        int timeout = (cmd == "wait" && f.size() > 2) ? std::stoi(f[2]) * 1000 : 15000;
        CONTROLTYPEID only = (cmd == "set" || cmd == "settext" || cmd == "value") ? UIA_EditControlTypeId : (cmd == "slide" || cmd == "range") ? UIA_SliderControlTypeId : cmd == "click" ? UIA_ButtonControlTypeId :
                             (cmd == "enter" || cmd == "select" || cmd == "pick") ? UIA_ListItemControlTypeId :
                             (cmd == "toggle" || cmd == "state") ? UIA_CheckBoxControlTypeId :
                             (cmd == "choose" || cmd == "chosen") ? UIA_RadioButtonControlTypeId : 0;
        CONTROLTYPEID only2 = (cmd == "enter" || cmd == "select") ? UIA_TreeItemControlTypeId : 0;
        IUIAutomationElement *e = wait_for(pid, arg, timeout, only, only2);
        if (!e) { say("ERROR: not found: " + arg + " (line " + std::to_string(lineNo) + ")"); find(pid, "", true); return 1; }
        if (cmd == "resize") {
            // resize\tNAME\tW\tH: the window NAME is in, restored and made W x H (at 96 dpi): a narrow window (#371)
            UIA_HWND hw = 0; e->get_CurrentNativeWindowHandle(&hw); e->Release();
            HWND root = hw ? GetAncestor((HWND)hw, GA_ROOT) : nullptr;
            if (!root || f.size() < 4) { say("ERROR: can't resize " + arg); return 1; }
            UINT dpi = GetDpiForWindow(root);
            ShowWindow(root, SW_RESTORE); Sleep(300);
            SetWindowPos(root, nullptr, 0, 0, std::stoi(f[2]) * (int)dpi / 96, std::stoi(f[3]) * (int)dpi / 96, SWP_NOMOVE | SWP_NOZORDER);
            Sleep(500);
            continue;
        }
        if (cmd == "height") {
            // height\tNAME\tMIN: NAME is at least MIN px tall (at 96 dpi): a status line that needs two lines has them (#371)
            UIA_HWND hw = 0; e->get_CurrentNativeWindowHandle(&hw);
            RECT r; e->get_CurrentBoundingRectangle(&r); e->Release();
            UINT dpi = hw ? GetDpiForWindow((HWND)hw) : 96;
            int h = (int)(r.bottom - r.top) * 96 / (int)(dpi ? dpi : 96);
            if (f.size() < 3 || h < std::stoi(f[2])) { say("ERROR: " + arg + " is " + std::to_string(h) + " px tall, not at least " + (f.size() > 2 ? f[2] : "?")); return 1; }
            // (height\tNAME\tMIN\tMAX: and at most MAX: text at its size, not larger)
            if (f.size() > 3 && h > std::stoi(f[3])) { say("ERROR: " + arg + " is " + std::to_string(h) + " px tall, more than " + f[3]); return 1; }
            say("  " + std::to_string(h) + " px tall");
            continue;
        }
        if (cmd == "value") {
            std::wstring want = wide(f.size() > 2 ? f[2] : "");
            bool ok = false;
            for (int t = 0; t < 15000 && !ok; t += 300) {
                IUIAutomationElement *x = find(pid, arg, false, UIA_EditControlTypeId);
                if (x) {
                    IUIAutomationValuePattern *vp = nullptr;
                    if (SUCCEEDED(x->GetCurrentPatternAs(UIA_ValuePatternId, __uuidof(IUIAutomationValuePattern), (void **)&vp)) && vp) {
                        BSTR v = nullptr;
                        if (SUCCEEDED(vp->get_CurrentValue(&v)) && v) { ok = std::wstring(v).find(want) != std::wstring::npos; SysFreeString(v); }
                        vp->Release();
                    }
                    x->Release();
                }
                if (!ok) Sleep(300);
            }
            e->Release();
            if (!ok) { say("ERROR: " + arg + " does not hold " + (f.size() > 2 ? f[2] : "")); find(pid, "", true); return 1; }
            continue;
        }
        if (cmd == "state") {
            bool want = f.size() > 2 && f[2] == "on", ok = false;
            for (int t = 0; t < 15000 && !ok; t += 300) {
                IUIAutomationElement *x = find(pid, arg, false, UIA_CheckBoxControlTypeId);
                if (x) {
                    IUIAutomationTogglePattern *tp = nullptr;
                    if (SUCCEEDED(x->GetCurrentPatternAs(UIA_TogglePatternId, __uuidof(IUIAutomationTogglePattern), (void **)&tp)) && tp) {
                        ToggleState st;
                        if (SUCCEEDED(tp->get_CurrentToggleState(&st))) ok = (st == ToggleState_On) == want;
                        tp->Release();
                    }
                    x->Release();
                }
                if (!ok) Sleep(300);
            }
            e->Release();
            if (!ok) { say("ERROR: " + arg + " is not " + (f.size() > 2 ? f[2] : "")); return 1; }
            continue;
        }
        if (cmd == "chosen") {
            bool ok = false;
            for (int t = 0; t < 15000 && !ok; t += 300) {
                IUIAutomationElement *x = find(pid, arg, false, UIA_RadioButtonControlTypeId);
                if (x) {
                    IUIAutomationLegacyIAccessiblePattern *lp = nullptr;
                    if (SUCCEEDED(x->GetCurrentPatternAs(UIA_LegacyIAccessiblePatternId, __uuidof(IUIAutomationLegacyIAccessiblePattern), (void **)&lp)) && lp) {
                        DWORD st = 0;
                        if (SUCCEEDED(lp->get_CurrentState(&st))) ok = (st & 0x10 /* STATE_SYSTEM_CHECKED */) != 0;
                        lp->Release();
                    }
                    x->Release();
                }
                if (!ok) Sleep(300);
            }
            e->Release();
            if (!ok) { say("ERROR: " + arg + " is not chosen"); return 1; }
            continue;
        }
        if (cmd == "shade") {
            bool wantDark = f.size() > 2 && f[2] == "dark", ok = false;
            int med = -1, light = 0, dark = 0, n = 0;
            for (int t = 0; t < 20000 && !ok; t += 500) {
                IUIAutomationElement *x = find(pid, arg);
                if (x) {
                    if (shade_of(x, med, light, dark, n))
                        ok = wantDark ? (med < 40 && light > 0) : (med > 200 && dark > 0);
                    x->Release();
                }
                if (!ok) Sleep(500);
            }
            say("  median grey " + std::to_string(med) + ", light " + std::to_string(light) + ", dark " + std::to_string(dark) +
                " of " + std::to_string(n));
            e->Release();
            if (!ok) { say("ERROR: " + arg + " is not " + (f.size() > 2 ? f[2] : "")); return 1; }
            continue;
        }
        if (cmd == "surface" || cmd == "titlebar") {
            bool wantDark = f.size() > 2 && f[2] == "dark", ok = false;
            int med = -1;
            for (int t = 0; t < 10000 && !ok; t += 500) {
                IUIAutomationElement *x = find(pid, arg);
                if (x) {
                    med = median_grey(x, cmd == "titlebar");
                    ok = med >= 0 && (wantDark ? med < 70 : med > 190);
                    x->Release();
                }
                if (!ok) Sleep(500);
            }
            say("  median grey " + std::to_string(med));
            e->Release();
            if (!ok) { say("ERROR: " + arg + (cmd == "titlebar" ? "'s title bar" : "") + " is not " + (f.size() > 2 ? f[2] : "")); return 1; }
            continue;
        }
        if (cmd == "dialog") {
            // the window: the element's top-level window as UI Automation sees it
            UIA_HWND hw = 0; e->get_CurrentNativeWindowHandle(&hw); e->Release();
            IUIAutomationElement *w = nullptr;
            HWND root = hw ? GetAncestor((HWND)hw, GA_ROOT) : nullptr;
            if (!root || FAILED(ua->ElementFromHandle((UIA_HWND)root, &w)) || !w) { say("ERROR: no window for " + arg); return 1; }
            auto prop = [&](PROPERTYID id) {
                VARIANT v; VariantInit(&v);
                std::wstring out;
                if (SUCCEEDED(w->GetCurrentPropertyValue(id, &v)) && v.vt == VT_BSTR && v.bstrVal) out = v.bstrVal;
                VariantClear(&v);
                return out;
            };
            std::wstring type = prop(UIA_LocalizedControlTypePropertyId), name = prop(UIA_NamePropertyId);
            std::wstring desc = prop(30159 /* UIA_FullDescriptionPropertyId */) + L" | " + prop(UIA_HelpTextPropertyId);
            VARIANT isd; VariantInit(&isd);
            bool dialog = SUCCEEDED(w->GetCurrentPropertyValue(30174 /* UIA_IsDialogPropertyId */, &isd)) && isd.vt == VT_BOOL && isd.boolVal;
            VariantClear(&isd);
            if (dialog) type += L" (IsDialog: dialog)";
            w->Release();
            say("  window \"" + std::string(name.begin(), name.end()) + "\", " + std::string(type.begin(), type.end()) +
                ", description: " + std::string(desc.begin(), desc.end()));
            std::wstring want = wide(f.size() > 2 ? f[2] : "");
            if (type.find(L"dialog") == std::wstring::npos || desc.find(want) == std::wstring::npos) {
                say("ERROR: " + arg + "'s window is not a dialog with that description"); return 1;
            }
            continue;
        }
        if (cmd == "fits") {
            int bad = fits(e);
            e->Release();
            if (bad != 0) { say("ERROR: " + std::to_string(bad) + " control(s) cut off or overlapping in the window of " + arg); return 1; }
            continue;
        }
        if (cmd == "range") {
            IUIAutomationRangeValuePattern *rp = nullptr;
            e->GetCurrentPatternAs(UIA_RangeValuePatternId, __uuidof(IUIAutomationRangeValuePattern), (void **)&rp);
            HRESULT hr = rp ? rp->SetValue(std::stod(f.size() > 2 ? f[2] : "0")) : E_NOINTERFACE;
            double v = -1;
            if (rp) { rp->get_CurrentValue(&v); rp->Release(); }
            e->Release();
            say("  value " + std::to_string(v));
            double wanted = std::stod(f.size() > 2 ? f[2] : "0");
            if (FAILED(hr) || std::abs(v - wanted) > 0.5) { say("ERROR: can't set " + arg + " to " + (f.size() > 2 ? f[2] : "")); return 1; }
            continue;
        }
        if (cmd == "pixels") {
            unsigned long rgb = std::stoul(f.size() > 2 ? f[2] : "0", nullptr, 16);
            int most = f.size() > 3 ? std::stoi(f[3]) : 0;
            int n = count_colour(e, (int)(rgb >> 16) & 255, (int)(rgb >> 8) & 255, (int)rgb & 255);
            say("  " + std::to_string(n) + " pixels of " + (f.size() > 2 ? f[2] : ""));
            e->Release();
            if (n < 0 || n > most) { say("ERROR: " + arg + " has " + std::to_string(n) + " pixels of " + f[2]); return 1; }
            continue;
        }
        if (cmd == "resize") {
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            e->Release();
            if (!hw || f.size() < 4) { say("ERROR: can't resize the window of " + arg); return 1; }
            HWND root = GetAncestor((HWND)hw, GA_ROOT);
            ShowWindow(root, SW_RESTORE);
            SetWindowPos(root, nullptr, 0, 0, std::stoi(f[2]), std::stoi(f[3]), SWP_NOZORDER | SWP_NOACTIVATE);
            Sleep(800);
            RECT r; GetWindowRect(root, &r);
            say("  window " + std::to_string(r.right - r.left) + " x " + std::to_string(r.bottom - r.top) +
                (r.right - r.left != std::stoi(f[2]) || r.bottom - r.top != std::stoi(f[3]) ? " (as large as the screen allows)" : ""));
            continue;
        }
        if (cmd == "apart" || cmd == "clear") {
            int bad = apart(pid, e, cmd == "clear" ? (f.size() > 2 ? f[2] : "?") : "");
            e->Release();
            if (bad != 0) { say("ERROR: " + std::to_string(bad) + " element(s) under or over " + arg); return 1; }
            continue;
        }
        if (cmd == "toggle") {
            IUIAutomationTogglePattern *tp = nullptr;
            if (FAILED(e->GetCurrentPatternAs(UIA_TogglePatternId, __uuidof(IUIAutomationTogglePattern), (void **)&tp)) || !tp) {
                say("ERROR: not a check box: " + arg); return 1;
            }
            tp->Toggle(); tp->Release();
        } else if (cmd == "boxdrag") {
            // the box: from just above-left of the element (in its window's client coordinates) to fw × fh of its size
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            IUIAutomationElement *t = f.size() > 4 ? wait_for(pid, f[2], 15000) : nullptr;
            if (!hw || !t) { say("ERROR: can't box-drag " + arg + " around " + (f.size() > 2 ? f[2] : "")); return 1; }
            RECT r; t->get_CurrentBoundingRectangle(&r); t->Release();
            POINT a{r.left - 4, r.top - 4}, b{r.left + (LONG)((r.right - r.left) * std::stod(f[3])), r.top + (LONG)((r.bottom - r.top) * std::stod(f[4]))};
            ScreenToClient((HWND)hw, &a); ScreenToClient((HWND)hw, &b);
            PostMessageW((HWND)hw, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(a.x, a.y));
            for (int s = 1; s <= 8; s++) {
                PostMessageW((HWND)hw, WM_MOUSEMOVE, MK_LBUTTON, MAKELPARAM(a.x + (b.x - a.x) * s / 8, a.y + (b.y - a.y) * s / 8));
                Sleep(20);
            }
            PostMessageW((HWND)hw, WM_LBUTTONUP, 0, MAKELPARAM(b.x, b.y));
        } else if (cmd == "click") {
            IUIAutomationInvokePattern *ip = nullptr;
            if (FAILED(e->GetCurrentPatternAs(UIA_InvokePatternId, __uuidof(IUIAutomationInvokePattern), (void **)&ip)) || !ip) {
                say("ERROR: not clickable: " + arg); return 1;
            }
            ip->Invoke(); ip->Release();
        } else if (cmd == "set") {
            IUIAutomationValuePattern *vp = nullptr;
            if (FAILED(e->GetCurrentPatternAs(UIA_ValuePatternId, __uuidof(IUIAutomationValuePattern), (void **)&vp)) || !vp) {
                say("ERROR: no value: " + arg); return 1;
            }
            BSTR b = SysAllocString(wide(f.size() > 2 ? f[2] : "").c_str());
            vp->SetValue(b); SysFreeString(b); vp->Release();
        } else if (cmd == "settext") {
            // WM_SETTEXT straight to the edit box: not held to the field's typing limit (EM_LIMITTEXT), so the app's own
            // check of a value set from outside is what gets tested
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (!hw) { say("ERROR: no window: " + arg); return 1; }
            std::wstring v = wide(f.size() > 2 ? f[2] : "");
            // "\n" in the script is a line break (a script line can't hold one): a pasted column of codes
            for (size_t i; (i = v.find(L"\\n")) != std::wstring::npos;) v.replace(i, 2, L"\r\n");
            if (!SendMessageW((HWND)hw, WM_SETTEXT, 0, (LPARAM)v.c_str())) { say("ERROR: WM_SETTEXT refused: " + arg); return 1; }
        } else if (cmd == "keys" || cmd == "slide") {
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (!hw) { say("ERROR: no window: " + arg); return 1; }
            std::stringstream ks(f.size() > 2 ? f[2] : "");
            std::string k;
            while (std::getline(ks, k, ',')) {
                UINT vk = (UINT)std::stoul(k, nullptr, 0);
                PostMessageW((HWND)hw, WM_KEYDOWN, vk, 0);
                PostMessageW((HWND)hw, WM_KEYUP, vk, 0);
                Sleep(60);
            }
        } else if (cmd == "drag" || cmd == "escdrag") {
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            RECT rc; if (!hw || !GetClientRect((HWND)hw, &rc) || f.size() < 6) { say("ERROR: can't drag on " + arg); return 1; }
            auto at = [&](size_t a, size_t b) { return MAKELPARAM((int)(std::stod(f[a]) * rc.right), (int)(std::stod(f[b]) * rc.bottom)); };
            PostMessageW((HWND)hw, WM_LBUTTONDOWN, MK_LBUTTON, at(2, 3));
            for (int s = 1; s <= 8; s++) {
                double t = s / 8.0;
                double x = std::stod(f[2]) + (std::stod(f[4]) - std::stod(f[2])) * t, y = std::stod(f[3]) + (std::stod(f[5]) - std::stod(f[3])) * t;
                PostMessageW((HWND)hw, WM_MOUSEMOVE, MK_LBUTTON, MAKELPARAM((int)(x * rc.right), (int)(y * rc.bottom)));
                Sleep(20);
            }
            if (cmd == "escdrag") {
                Sleep(300);
                PostMessageW((HWND)hw, WM_KEYDOWN, VK_ESCAPE, 0);
                PostMessageW((HWND)hw, WM_KEYUP, VK_ESCAPE, 0);
                Sleep(300);
            }
            if (!(cmd == "escdrag" && f.size() > 6 && f[6] == "hold")) PostMessageW((HWND)hw, WM_LBUTTONUP, 0, at(4, 5));
        } else if (cmd == "hover") {
            // the mouse pointer over the element's middle (a real move: the control sees WM_MOUSEMOVE, its hover look)
            RECT r; e->get_CurrentBoundingRectangle(&r);
            SetCursorPos((r.left + r.right) / 2, (r.top + r.bottom) / 2);
        } else if (cmd == "holddown" || cmd == "letgo") {
            // holddown: the left button down on the element (its pressed look, as long as it is held); letgo: the press
            // cancelled without a click (WM_CANCELMODE), so holding a button down for a screenshot changes nothing
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (!hw) { say("ERROR: no window: " + arg); return 1; }
            RECT c; GetClientRect((HWND)hw, &c);
            if (cmd == "holddown") PostMessageW((HWND)hw, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(c.right / 2, c.bottom / 2));
            else SendMessageW((HWND)hw, WM_CANCELMODE, 0, 0);
        } else if (cmd == "mouseup") {
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (!hw) { say("ERROR: no window: " + arg); return 1; }
            PostMessageW((HWND)hw, WM_LBUTTONUP, 0, 0);
        } else if (cmd == "touchdrag") {
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            RECT rc; if (!hw || !GetClientRect((HWND)hw, &rc) || f.size() < 6) { say("ERROR: can't touch " + arg); return 1; }
            static bool ready = false;
            if (!ready) { if (!InitializeTouchInjection(1, TOUCH_FEEDBACK_NONE)) { say("ERROR: InitializeTouchInjection"); return 1; } ready = true; }
            SetForegroundWindow(GetAncestor((HWND)hw, GA_ROOT)); Sleep(300);
            auto send = [&](double fx, double fy, POINTER_FLAGS flags) {
                POINT p{(LONG)(fx * rc.right), (LONG)(fy * rc.bottom)}; ClientToScreen((HWND)hw, &p);
                POINTER_TOUCH_INFO t{}; t.pointerInfo.pointerType = PT_TOUCH; t.pointerInfo.pointerId = 0;
                t.pointerInfo.ptPixelLocation = p; t.pointerInfo.pointerFlags = flags;
                t.touchFlags = TOUCH_FLAG_NONE; t.touchMask = TOUCH_MASK_CONTACTAREA;
                t.rcContact = {p.x - 2, p.y - 2, p.x + 2, p.y + 2};
                return InjectTouchInput(1, &t);
            };
            double x0 = std::stod(f[2]), y0 = std::stod(f[3]), x1 = std::stod(f[4]), y1 = std::stod(f[5]);
            if (!send(x0, y0, POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT)) { say("ERROR: InjectTouchInput " + std::to_string(GetLastError())); return 1; }
            for (int s = 1; s <= 12; s++) {
                double t = s / 12.0;
                send(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT);
                Sleep(30);
            }
            send(x1, y1, POINTER_FLAG_UP);
        } else if (cmd == "endsession") {
            // what signing out does first: WM_QUERYENDSESSION to the element's top window; f[2]: the answer expected
            // (0: the app asks to wait, 1: it lets the session end)
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (!hw) { say("ERROR: no window: " + arg); return 1; }
            DWORD_PTR r = 0;
            if (!SendMessageTimeoutW(GetAncestor((HWND)hw, GA_ROOT), WM_QUERYENDSESSION, 0, ENDSESSION_LOGOFF, SMTO_ABORTIFHUNG, 10000, &r)) {
                say("ERROR: no answer to WM_QUERYENDSESSION"); return 1;
            }
            if (f.size() > 2 && std::to_string(r ? 1 : 0) != f[2]) { say("ERROR: WM_QUERYENDSESSION answered " + std::to_string(r)); return 1; }
        } else if (cmd == "blockreason") {
            // the shutdown block reason of the element's top window (what Windows shows when signing out): f[2] a part
            // of it, or "-" for none. Waits up to 15 s for it to change
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (!hw) { say("ERROR: no window: " + arg); return 1; }
            HWND root = GetAncestor((HWND)hw, GA_ROOT);
            std::wstring want = wide(f.size() > 2 ? f[2] : "-");
            std::wstring got;
            bool ok = false;
            for (int t = 0; t < 15000 && !ok; t += 300) {
                WCHAR buf[512] = {};
                DWORD n = 512;
                got = ShutdownBlockReasonQuery(root, buf, &n) && buf[0] ? std::wstring(buf) : L"-";
                ok = want == L"-" ? got == L"-" : got.find(want) != std::wstring::npos;
                if (!ok) Sleep(300);
            }
            if (!ok) {
                std::string g(got.begin(), got.end());
                say("ERROR: the shutdown block reason is " + g + ", not " + (f.size() > 2 ? f[2] : "-")); return 1;
            }
        } else if (cmd == "close") {
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (!hw) { say("ERROR: no window: " + arg); return 1; }
            PostMessageW(GetAncestor((HWND)hw, GA_ROOT), WM_CLOSE, 0, 0);
        } else if (cmd == "choose") {
            IUIAutomationLegacyIAccessiblePattern *lp = nullptr;
            bool done = false;
            if (SUCCEEDED(e->GetCurrentPatternAs(UIA_LegacyIAccessiblePatternId, __uuidof(IUIAutomationLegacyIAccessiblePattern), (void **)&lp)) && lp) {
                done = SUCCEEDED(lp->DoDefaultAction());
                lp->Release();
            }
            if (!done) {
                UIA_HWND hw = 0;
                e->get_CurrentNativeWindowHandle(&hw);
                if (!hw) { say("ERROR: can't choose " + arg); return 1; }
                SendMessageW((HWND)hw, BM_CLICK, 0, 0);
            }
        } else if (cmd == "select") {
            IUIAutomationSelectionItemPattern *sp = nullptr;
            if (FAILED(e->GetCurrentPatternAs(UIA_SelectionItemPatternId, __uuidof(IUIAutomationSelectionItemPattern), (void **)&sp)) || !sp) {
                say("ERROR: not selectable: " + arg); return 1;
            }
            sp->Select(); sp->Release();
        } else if (cmd == "pick") {
            IUIAutomationSelectionItemPattern *sp = nullptr;
            if (FAILED(e->GetCurrentPatternAs(UIA_SelectionItemPatternId, __uuidof(IUIAutomationSelectionItemPattern), (void **)&sp)) || !sp) {
                say("ERROR: not selectable: " + arg); return 1;
            }
            sp->Select(); sp->Release();
            IUIAutomationTreeWalker *tw = nullptr;
            IUIAutomationElement *list = nullptr;
            UIA_HWND hw = 0;
            if (SUCCEEDED(ua->get_ControlViewWalker(&tw)) && tw) { tw->GetParentElement(e, &list); tw->Release(); }
            if (list) { list->get_CurrentNativeWindowHandle(&hw); list->Release(); }
            if (!hw) { say("ERROR: no list window: " + arg); return 1; }
            PostMessageW(GetParent((HWND)hw), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID((HWND)hw), LBN_SELCHANGE), (LPARAM)hw);
        }
        if (cmd == "press") {
            IUIAutomationElement *c = find(pid, arg, false, UIA_EditControlTypeId);
            if (!c) c = find(pid, arg, false, UIA_ListControlTypeId);
            if (c) { e->Release(); e = c; }
            UIA_HWND hw = 0;
            e->get_CurrentNativeWindowHandle(&hw);
            if (hw) { SetForegroundWindow(GetAncestor((HWND)hw, GA_ROOT)); Sleep(200); }
            if (FAILED(e->SetFocus())) { say("ERROR: can't focus " + arg); e->Release(); return 1; }
            Sleep(200);
            std::stringstream ks(f.size() > 2 ? f[2] : "");
            std::string k;
            while (std::getline(ks, k, ',')) {
                INPUT in[2] = {};
                in[0].type = in[1].type = INPUT_KEYBOARD;
                in[0].ki.wVk = in[1].ki.wVk = (WORD)std::stoul(k, nullptr, 0);
                in[1].ki.dwFlags = KEYEVENTF_KEYUP;
                SendInput(2, in, sizeof(INPUT));
                Sleep(80);
            }
        }
        if (cmd == "focus" || cmd == "focused") {
            // a field's label (a Text element) carries the field's name and comes first: the field itself is meant
            CONTROLTYPEID ct = 0; e->get_CurrentControlType(&ct);
            if (ct == UIA_TextControlTypeId) {
                IUIAutomationElement *ed = find(pid, arg, false, UIA_EditControlTypeId);
                if (ed) { e->Release(); e = ed; }
            }
        }
        if (cmd == "focused") {
            // the keyboard focus is on this element now: nothing has taken it away (another window in front, a rebuild)
            IUIAutomationElement *fe = nullptr;
            BOOL same = FALSE;
            if (SUCCEEDED(ua->GetFocusedElement(&fe)) && fe) { ua->CompareElements(fe, e, &same); fe->Release(); }
            if (!same) { say("ERROR: not focused: " + arg); say_focus(); find(pid, "", true); e->Release(); return 1; }
        } else if (cmd == "focus") {
            // the keyboard focus to this element (what Tab or a screen reader's navigation does); a list or tree item
            // is looked at afterwards (focus_on: the app may have rebuilt its list since it was found)
            CONTROLTYPEID ct = 0; e->get_CurrentControlType(&ct);
            if (ct == UIA_ListItemControlTypeId || ct == UIA_TreeItemControlTypeId) {
                if (!focus_on(pid, e, arg, timeout, UIA_ListItemControlTypeId, UIA_TreeItemControlTypeId, false)) return 1;
            } else if (FAILED(e->SetFocus())) { say("ERROR: can't focus " + arg); return 1; }
        } else if (cmd == "enter") {
            // what a keyboard (or screen reader) user does: the window in front, the item focused and selected, Enter
            UIA_HWND hw = 0;
            for (auto *r : roots(pid)) { if (!hw) r->get_CurrentNativeWindowHandle(&hw); r->Release(); }
            if (hw) { SetForegroundWindow((HWND)hw); Sleep(200); }
            if (!focus_on(pid, e, arg, timeout, only, only2, true)) return 1;
            INPUT k[2] = {};
            k[0].type = k[1].type = INPUT_KEYBOARD;
            k[0].ki.wVk = k[1].ki.wVk = VK_RETURN;
            k[1].ki.dwFlags = KEYEVENTF_KEYUP;
            SendInput(2, k, sizeof(INPUT));
        }
        e->Release();
        Sleep(150);
    }
    say("PASSED");
    return 0;
}
