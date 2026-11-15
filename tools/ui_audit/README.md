# UI audit scripts

The evidence scripts of the 2026-11 full UI/UX audit (docs/UI-UX-POLICY.md, results in docs/ui-audit/2026-11.md),
kept so the next audit can start from them. They were written for one run, not as tests: expect to adjust them to
the screens you need. Synthetic data only (the policy's rule Z1): every script makes its own server from the test
fixtures. Follow CLAUDE.md's memory and lock rules (one emulator or VM at a time, GNOME only under headless.sh).

The repository root comes from `$KKS_REPO`, or else from where the script lives.

| Script | Platform | What it does | How to run |
|---|---|---|---|
| `audit_web.py` + `measure.js` | Web | Server with the sample sheet and synthetic queues; per engine and layout (phone, desktop, 200 %, 320 px; light, dark) screenshots, ARIA snapshot and measurements (targets, contrast, font sizes, overflow); keyboard, Escape, copy, offline probes | `KKS_SERVER=… KKS_IMPORTER=… .venv/bin/python tools/ui_audit/audit_web.py OUTDIR [chromium webkit firefox]` |
| `web_analyze.py` | Web | Turns audit_web.py's JSON into fails per screen and rule | `python3 tools/ui_audit/web_analyze.py OUTDIR [engine]` |
| `web_probe2.py`, `web_probe3.py` | Web | Extra probes: focus rings, Arabic note, forced colours, tap beside a tag, typed text after Close, reload, landscape; floor/cover vs selection, toast under a modal, focus under sticky headers, reduced motion in course figures, long sheet name | as audit_web.py, with the script's name |
| `contrast_region.py` | any | WCAG ratio of text in a screenshot region | `python3 tools/ui_audit/contrast_region.py SHOT.png name=x0,y0,x1,y1` |
| `contrast_pairs.py` | any | WCAG ratios of fixed colour pairs (Plant panels, drawing outlines with alpha) | edit the lists, `python3 tools/ui_audit/contrast_pairs.py` |
| `gnome_audit.py` | GNOME | Walks the app's screens in light, dark, high contrast and Large Text; AT-SPI dump and screenshot per screen; Tab walk through mutter's RemoteDesktop API | `apps/gnome/e2e/headless.sh /usr/bin/python3 tools/ui_audit/gnome_audit.py APP SERVER IMPORTER OUTDIR [modes]` |
| `gnome_analyze.py` | GNOME | Small targets, unnamed controls, overlaps from those dumps | `python3 tools/ui_audit/gnome_analyze.py OUTDIR` |
| `audit_server.py` | Android, Windows | A long-running synthetic server (marked tags, long and Arabic notes, a member with 20 proposals) | `python3 tools/ui_audit/audit_server.py SERVER IMPORTER DIR [address]` |
| `android_audit.py` | Android | uiautomator dump + screenshot per screen, T1/T2/A2 checks in dp; demo-mode status bar | a library: `ANDROID_SERIAL=emulator-NNNN` (never a real phone), then `check('name')` |
| `windows_audit.py` | Windows | uiadrive scripts, UIA dump with rectangles, `virsh` screenshot, T3/T2/A2 checks | a library: `KKS_VM_IP=…` (and `KKS_VM`); uiadrive built with `uiadrive-rects.patch` |
| `uiadrive-rects.patch` | Windows | Makes uiadrive's `dump` print each element's rectangle, focusability, off-screen state and access key | `git apply tools/ui_audit/uiadrive-rects.patch` in a scratch checkout, then build uiadrive as usual (don't commit it) |
| `windows_uiadump.ps1`, `windows_contrast_theme.ps1` | Windows (in the VM) | A UIA dump through .NET; switch "High Contrast Black" on or off | `powershell -File …` in the VM |
| `plant_audit.gd` | Plant | Opens each panel, screenshot and every visible Control (class, text, rect, font size and colour, focus mode) | `tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script "$PWD/tools/ui_audit/plant_audit.gd" -- --out=DIR [--phone]` |
| `plant_analyze.py` | Plant | Targets under 24 px / 48 dp, small fonts, overlaps from those dumps | `python3 tools/ui_audit/plant_analyze.py DIR` |
| `plant_a5.py` | Plant | Plant run with Godot's accessibility forced on; its AT-SPI tree (rule A5) | under `apps/gnome/e2e/headless.sh`: `python3 tools/ui_audit/plant_a5.py GODOT OUT.json` |

Before publishing any screenshot these scripts take, look at it (rule Z2): device names can carry the host's name,
and the Learning list shows the plant courses' titles.
