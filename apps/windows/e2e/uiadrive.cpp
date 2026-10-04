// Drive a window through the native UI Automation core (what Narrator uses), for the Windows app's tests (decision
// 0033). uiadrive.exe <process name> <script> <log>; each script line is TAB-separated:
//   wait <name>             wait (15 s) until an element with this name exists ("~text" = name contains text)
//   click <name>            Invoke it (buttons)
//   set <name> <text>       set its value (edits; the name a field takes from its label)
//   enter <name>            open a list item (its default action, else focus + Enter)
//   keys <name> <vk,vk,…>   post key presses (virtual-key codes, hex or decimal) to the element's window
//   drag <name> x0 y0 x1 y1 a left-button drag inside the element (fractions of its size), posted to its window
//   touchdrag <name> x0 y0 x1 y1  the same with one finger, injected as real touch input (InjectTouchInput; works
//                           without touch hardware), so the window gets WM_POINTER messages
//   select <name>           select a list item (SelectionItem), e.g. before a button that opens the selection
//   value <name> <text>     wait (15 s) until the field with this name holds a value containing text
//   gone <name>             wait until no element has this name
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
    default: return "Type" + std::to_string(t);
    }
}

static DWORD pid_of(const std::wstring &exe);

static IUIAutomationElement *find(DWORD &pid, const std::string &spec, bool dump = false, CONTROLTYPEID only = 0) {
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
                if (dump) { CONTROLTYPEID t = 0; e->get_CurrentControlType(&t); say("  " + type_name(t) + " '" + utf8(nm.c_str()) + "'"); }
                CONTROLTYPEID ct = 0;
                if (only) e->get_CurrentControlType(&ct);
                if (!dump && (!only || ct == only) && ((contains && nm.find(want) != std::wstring::npos) || (!contains && nm == want))) { hit = e; hit->AddRef(); }
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

static IUIAutomationElement *wait_for(DWORD &pid, const std::string &spec, int ms = 15000, CONTROLTYPEID only = 0) {
    for (int t = 0; t < ms; t += 300) {
        if (auto *e = find(pid, spec, false, only)) return e;
        Sleep(300);
    }
    return nullptr;
}

int wmain(int argc, wchar_t **argv) {
    if (argc < 4) { fprintf(stderr, "uiadrive <exe name> <script> <log>\n"); return 2; }
    logf = _wfopen(argv[3], L"a");
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
        if (cmd == "gone") {
            bool gone = false;
            for (int t = 0; t < 30000 && !gone; t += 300) { auto *e = find(pid, arg); if (e) { e->Release(); Sleep(300); } else gone = true; }
            if (!gone) { say("ERROR: still there: " + arg); return 1; }
            continue;
        }
        int timeout = (cmd == "wait" && f.size() > 2) ? std::stoi(f[2]) * 1000 : 15000;
        CONTROLTYPEID only = (cmd == "set" || cmd == "value") ? UIA_EditControlTypeId : cmd == "click" ? UIA_ButtonControlTypeId :
                             (cmd == "enter" || cmd == "select") ? UIA_ListItemControlTypeId : 0;
        IUIAutomationElement *e = wait_for(pid, arg, timeout, only);
        if (!e) { say("ERROR: not found: " + arg + " (line " + std::to_string(lineNo) + ")"); find(pid, "", true); return 1; }
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
            if (!ok) { say("ERROR: " + arg + " does not hold " + (f.size() > 2 ? f[2] : "")); return 1; }
            continue;
        }
        if (cmd == "click") {
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
        } else if (cmd == "keys") {
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
        } else if (cmd == "drag") {
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
            PostMessageW((HWND)hw, WM_LBUTTONUP, 0, at(4, 5));
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
        } else if (cmd == "select") {
            IUIAutomationSelectionItemPattern *sp = nullptr;
            if (FAILED(e->GetCurrentPatternAs(UIA_SelectionItemPatternId, __uuidof(IUIAutomationSelectionItemPattern), (void **)&sp)) || !sp) {
                say("ERROR: not selectable: " + arg); return 1;
            }
            sp->Select(); sp->Release();
        } else if (cmd == "enter") {
            // what a keyboard (or screen reader) user does: the window in front, the item focused and selected, Enter
            UIA_HWND hw = 0;
            for (auto *r : roots(pid)) { if (!hw) r->get_CurrentNativeWindowHandle(&hw); r->Release(); }
            if (hw) { SetForegroundWindow((HWND)hw); Sleep(200); }
            IUIAutomationSelectionItemPattern *sp = nullptr;
            if (SUCCEEDED(e->GetCurrentPatternAs(UIA_SelectionItemPatternId, __uuidof(IUIAutomationSelectionItemPattern), (void **)&sp)) && sp) {
                sp->Select(); sp->Release();
            }
            e->SetFocus();
            Sleep(200);
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
