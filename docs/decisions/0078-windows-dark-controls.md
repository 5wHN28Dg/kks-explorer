# 0078 Walkdown for Windows: the app's own dark colours for its Win32 controls

Date 2026-11-22 · Scope: the Windows app (`apps/windows`), issue #377 (the user's decision of 2026-11-15: "full Win32
dark mode (our own dark colours for every control)") · Status: decided under that decision; shipped switched off
(`win-dark-ui`, the UI and UX policy's 8.5) until the owner's check

**Question:** Windows' app mode can be dark, and the drawings already follow it (#361), but the window around them
stays light. How does a Win32 app with common controls (buttons, check boxes, radio buttons, fields, lists, a tree,
rich text, menus, scroll bars, dialogs, the title bar) follow the dark app mode, live, without breaking high contrast,
on Windows 10 and 11?

## Findings

| | Fact | Source |
|---|---|---|
| Microsoft's own guidance for Win32 | Detect the mode (UISettings' foreground colour, `ColorValuesChanged`), and ask for a dark title bar with `DwmSetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE)`. It "does not cover specifics of how to repaint and render your app UI using a Dark mode color set" | [D] https://learn.microsoft.com/windows/apps/desktop/modernize/ui/apply-windows-themes |
| The title bar attribute | value 20, "supported starting with Windows 11 Build 22000" | [D] https://learn.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute |
| … on Windows 10 | the same value darkens the title bar on Windows 10 22H2 (19045) | [V] 2026-11-22, the Windows 10 VM, screenshots on #377's PR |
| Dark common controls | none documented: the rulebook's WIN1 says the same ("dark common controls, which Win32 doesn't support, are Advice") | [D] the UI and UX policy 4.13, WIN1 |
| Our own colours, documented | `WM_CTLCOLORSTATIC/EDIT/LISTBOX` (labels, fields, lists); `NM_CUSTOMDRAW` from buttons, check boxes and radio buttons (Common Controls 6); `WM_CTLCOLORBTN` works only for owner-drawn buttons; `TVM_SETBKCOLOR/TEXTCOLOR/LINECOLOR` (tree); `EM_SETBKGNDCOLOR` (RichEdit); `WM_NCPAINT` (a control's edge); `WM_ERASEBKGND` | [D] https://learn.microsoft.com/windows/win32/controls/button-messages, …/controls/nm-customdraw-button, …/controls/wm-ctlcolorstatic, …/controls/tvm-setbkcolor, …/controls/em-setbkgndcolor |
| Scroll bars | no documented dark scroll bar for a Win32 window; `SetWindowTheme` (documented) with the theme class name Windows' own Explorer uses, `DarkMode_Explorer` (not documented as public), draws them dark; an unknown name leaves the default (light) | [D] https://learn.microsoft.com/windows/win32/api/uxtheme/nf-uxtheme-setwindowtheme; [V] Windows 10 and 11 VMs |
| Menus (the window menu, a field's right-click menu) | no documented way. uxtheme.dll's unnamed exports: ordinal 135 (`SetPreferredAppMode` from 1903; `AllowDarkModeForApp` in 1809, where 1 means the same), 133 (`AllowDarkModeForWindow`), 136 (`FlushMenuThemes`), used by Notepad++, Windows Terminal and others since 2019; with them a field's menu is dark in dark app mode, light in light mode | [K]; [V] Windows 10 VM (19045), screenshot on the PR |
| Task dialog and message box | drawn by Windows in light colours whatever the app mode | [V] Windows 11 26H2 VM (26300), screenshot on the PR |
| High contrast | `SystemParametersInfo(SPI_GETHIGHCONTRAST)`, `HCF_HIGHCONTRASTON` (documented); the controls' default drawing follows the contrast theme | [D] https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-highcontrastw |
| Reading the app mode | the registry value `AppsUseLightTheme` (what Settings writes; the app has read it for the drawings since #361) versus UISettings (WinRT: an activation factory and COM from Nim) | [V] both VMs |

## Choice

- **Our own colours through the documented messages** for every control kind the app uses (`kks_theme.cpp`), with a
  palette in `theme.nim` that meets the profile's contrast (main text 7:1 and more, secondary 4.5:1, edges, focus ring
  and the chosen state 3:1; `tests/test_theme.nim` checks the numbers). Push buttons, check boxes and radio buttons are
  drawn whole at `NM_CUSTOMDRAW`; an empty field's hint too (its default grey is about 3:1 on the dark field).
- **The title bar**: `DWMWA_USE_IMMERSIVE_DARK_MODE` (20, then 19 for Windows 10 before 20H1, ignored where unknown).
- **Scroll bars**: `SetWindowTheme(…, "DarkMode_Explorer")`. Risk: the name goes; fallback: light scroll bars, nothing
  else changes.
- **Menus**: uxtheme's ordinals 135, 133 and 136, only on Windows builds 17763 to 29999 (`kks_theme_menus_known`), looked
  up with `GetProcAddress` (absent: nothing called). Risk: a future build gives an ordinal another meaning; the build
  range keeps unknown builds out, and the fallback is light menus. Revisit when a Windows feature update arrives on the
  VMs (raise the range after checking there) or when Microsoft documents dark common controls.
- **Questions** (`ask`, `askYesNo`, `say`): while the dark colours are on, the app's own modal dialog with the same
  buttons, default and keys (the keyboard on the safe answer; Escape and the close box keep). In light mode, switched
  off and in high contrast: the task dialog and message box as before.
- **Which mode**: dark when Windows' app mode is dark (`AppsUseLightTheme` = 0, read at `WM_SETTINGCHANGE`,
  `WM_THEMECHANGED`, `WM_SYSCOLORCHANGE` and once a second) and no contrast theme is on. A contrast theme always wins:
  the app then draws nothing of its own (the system's colours, as before). Course pages and figures follow the same
  mode (they were always light on Windows).
- **Switched off by default** (`KKS_UX=win-dark-ui`; a release turns it on in `syncwords.UxOn`): off, nothing is
  subclassed, no theme is set, no ordinal is looked up: the app is as released.
