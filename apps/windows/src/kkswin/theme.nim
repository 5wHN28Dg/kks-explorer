## The app's colours for its own controls in Windows' dark app mode (#377, decision 0078): kks_theme.cpp paints them.
## Behind the switch `win-dark-ui` (KKS_UX, the UI and UX policy's 8.5): off, nothing is subclassed or changed and the
## app looks as before. On, the controls follow Windows' app mode ("Choose your default app mode"), also when it
## changes while the app runs; a high-contrast theme wins over both (the system's own colours, as before).

import std/os
import w32
from syncwords import uxOn

{.compile("kks_theme.cpp", "-std=c++17").}

const DarkUiSwitch* = "win-dark-ui"

type Role* = enum
  rWindow, rSurface, rText, rDim, rBorder, rButton, rHot, rDown, rFocus, rAccent, rAccentText, rDisabled

const DarkColours*: array[Role, uint32] = [
  0x1F1F1F'u32,   ## rWindow: behind everything (pages, the main window, dialogs)
  0x2B2B2B,       ## rSurface: inside fields, lists and the tree
  0xF2F2F2,       ## rText: 14.7:1 on the window, 12.7:1 in a field
  0xC8C8C8,       ## rDim: secondary text, 9.9:1 on the window
  0x9A9A9A,       ## rBorder: a button's and a field's edge, 5.9:1 on the window (3:1 needed)
  0x3A3A3A,       ## rButton
  0x474747,       ## rHot: a button under the mouse
  0x2C2C2C,       ## rDown: a button pressed
  0xFFFFFF,       ## rFocus: the keyboard focus ring, 16:1 on the window
  0x9CD0FF,       ## rAccent: a ticked check box, a chosen radio button (10:1 on the window)
  0x101010,       ## rAccentText: the tick and the dot on the accent (11.7:1)
  0x8C8C8C]       ## rDisabled: a disabled control's text and edge (exempt from the contrast minimum, still 4.9:1)

proc kksThemeInit(colours: ptr uint32, n: cint) {.importc: "kks_theme_init", cdecl.}
proc kksThemeSetDark(on: cint) {.importc: "kks_theme_set_dark", cdecl.}
proc kksThemeContainer(h: HWND) {.importc: "kks_theme_container", cdecl.}
proc kksThemeControl(h: HWND) {.importc: "kks_theme_control", cdecl.}
proc kksThemeDim(h: HWND) {.importc: "kks_theme_dim", cdecl.}
proc kksThemeApplyAll() {.importc: "kks_theme_apply_all", cdecl.}
proc menusKnown*(build: cuint): cint {.importc: "kks_theme_menus_known", cdecl.}

var
  themeOn = false       ## the switch, read once at the start
  uiDark* = false       ## the app's own dark colours are in use now
  onThemeChange*: seq[proc ()]   ## windows that make their content in the theme's colours (a course's rich text)

proc RegGetValueW(key: pointer, sub, value: WideCString, flags: uint32, typ: ptr uint32, data: pointer,
                  size: ptr uint32): int32 {.importc, stdcall, header: "<windows.h>".}

proc appsDark*(): bool =
  ## Windows' own setting for apps (Settings → Personalisation → Colours → "Choose your default app mode"): dark when
  ## AppsUseLightTheme is 0. KKS_TEST_SYSTEM_DARK (1 or 0) stands in for it in the tests.
  let t = getEnv("KKS_TEST_SYSTEM_DARK")
  if t.len > 0: return t == "1"
  var v: uint32 = 1
  var n = uint32(sizeof(v))
  let hkcu = cast[pointer](0x80000001'u)       # HKEY_CURRENT_USER
  RegGetValueW(hkcu, newWideCString("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
               newWideCString("AppsUseLightTheme"), 0x10'u32, nil, addr v, addr n) == 0 and v == 0   # RRF_RT_REG_DWORD

type HIGHCONTRASTW {.importc, header: "<windows.h>".} = object
  cbSize: UINT
  dwFlags: DWORD
  lpszDefaultScheme: WideCString
proc SystemParametersInfoHc(a: UINT, b: UINT, c: ptr HIGHCONTRASTW, d: UINT): BOOL {.importc: "SystemParametersInfoW", stdcall, header: "<windows.h>".}

proc highContrast*(): bool =
  ## a contrast theme is on (Settings → Accessibility → Contrast themes): its colours win
  var hc = HIGHCONTRASTW(cbSize: UINT(sizeof(HIGHCONTRASTW)))
  SystemParametersInfoHc(0x0042, UINT(sizeof(HIGHCONTRASTW)), addr hc, 0) != 0 and (hc.dwFlags and 1) != 0   # SPI_GETHIGHCONTRAST, HCF_HIGHCONTRASTON

proc themeEnabled*(): bool = themeOn

proc wantDark(): bool = themeOn and appsDark() and not highContrast()

proc initTheme*() =
  ## at the start, before the first window: reads the switch and the system's settings
  themeOn = uxOn(DarkUiSwitch)
  if not themeOn: return
  var cs = DarkColours
  kksThemeInit(addr cs[Role.low], cint(cs.len))
  uiDark = wantDark()
  kksThemeSetDark(cint(ord(uiDark)))

proc refreshTheme*(): bool =
  ## Windows' app mode or contrast theme may have changed: every window of the app follows. -> it changed
  if not themeOn: return false
  let d = wantDark()
  if d == uiDark: return false
  uiDark = d
  kksThemeSetDark(cint(ord(d)))
  kksThemeApplyAll()
  for f in onThemeChange:
    try: f() except CatchableError: discard
  true

proc themeContainer*(h: HWND) = (if themeOn: kksThemeContainer(h))
proc themeControl*(h: HWND) = (if themeOn: kksThemeControl(h))
proc themeDim*(h: HWND) = (if themeOn: kksThemeDim(h))

proc GetSysColor(i: cint): DWORD {.importc, stdcall, header: "<windows.h>".}

proc colorRef*(rgb: uint32): DWORD =
  ## 0xRRGGBB → GDI's 0x00BBGGRR
  DWORD(((rgb and 0xFF) shl 16) or (rgb and 0xFF00) or ((rgb shr 16) and 0xFF))

proc themeColor*(r: Role): DWORD =
  ## a colour for what the app paints itself (owner-drawn rows): ours in dark, else the system's (as before)
  if uiDark: return colorRef(DarkColours[r])
  case r
  of rWindow, rSurface, rButton, rHot, rDown: GetSysColor(5)       # COLOR_WINDOW
  of rText, rFocus: GetSysColor(8)                                 # COLOR_WINDOWTEXT
  of rDim, rDisabled: GetSysColor(17)                              # COLOR_GRAYTEXT
  of rBorder: GetSysColor(16)                                      # COLOR_BTNSHADOW
  of rAccent: GetSysColor(13)                                      # COLOR_HIGHLIGHT
  of rAccentText: GetSysColor(14)                                  # COLOR_HIGHLIGHTTEXT
