// The screen as a BMP, for the e2e tests on a real machine (KKS_LAPTOP, test_windows.py): started in the desktop
// session by a scheduled task (runapp.ps1). A GUI-subsystem program with no window, so it never takes the foreground
// or the keyboard focus from the app under test (a console window would, #158). shot.exe <out.bmp>
#include <windows.h>
#include <stdio.h>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR cmd, int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);   // the screen's real pixels
    int x = GetSystemMetrics(SM_XVIRTUALSCREEN), y = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int w = GetSystemMetrics(SM_CXVIRTUALSCREEN), h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    HDC screen = GetDC(nullptr), mem = CreateCompatibleDC(screen);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = h;          // bottom-up, as a BMP file holds it
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bmp) return 1;
    HGDIOBJ old = SelectObject(mem, bmp);
    BOOL ok = BitBlt(mem, 0, 0, w, h, screen, x, y, SRCCOPY | CAPTUREBLT);
    GdiFlush();
    int rc = 1;
    FILE *f = ok ? _wfopen(cmd, L"wb") : nullptr;
    if (f) {
        DWORD size = (DWORD)w * h * 4;
        BITMAPFILEHEADER fh = {};
        fh.bfType = 0x4D42;
        fh.bfOffBits = sizeof(fh) + sizeof(bi.bmiHeader);
        fh.bfSize = fh.bfOffBits + size;
        rc = (fwrite(&fh, sizeof(fh), 1, f) == 1 && fwrite(&bi.bmiHeader, sizeof(bi.bmiHeader), 1, f) == 1 &&
              fwrite(bits, size, 1, f) == 1) ? 0 : 1;
        rc |= fclose(f) != 0;
    }
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
    return rc;
}
