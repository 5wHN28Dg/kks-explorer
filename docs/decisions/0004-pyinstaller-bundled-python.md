# 0004 PyInstaller: bundled CPython + Tk (desktop package)

Date 2026-09-30 · Scope: Windows/Linux desktop package (M2c) · Status: keep until M6

**What it does:**
- Ships a CPython runtime, Tcl/Tk (the small Open/Quit window) and our Python code as one folder (79 MB with the
  update machinery).
- The UI itself is the system's default browser.

**Platform:**
- Windows has no Python.
- Most Linux distributions do have one, but at varying versions and without our packages.

So a runtime has to be shipped somewhere. This is the "carries its own runtime" case the native policy asks to
justify. The browser part is platform-provided: the pages run in the user's own browser, and no engine is bundled.

**Dependency check (PyInstaller):** passes.

| Criterion | Evidence |
|---|---|
| Releases | 6.22.3 on 2026-09-12 |
| Maintainers | 19 active in the last 12 months |
| Security | SECURITY.md present |
| License | GPLv2+ with a bootloader exception, which allows any license for the bundled app |
| Major versions survived | 6 |

**Decision:** keep for the current desktop package. Replacing the bundled runtime is exactly M6's question, and M6
starts from the capability matrix (docs/CAPABILITIES.md). Measure the current package first: installed size, startup
time, steady memory on a clean Windows and Linux machine. That is M6's baseline.

**Revisit:** M6.

Sources: https://pypi.org/pypi/pyinstaller/json · https://github.com/pyinstaller/pyinstaller · https://pyinstaller.org/en/stable/license.html
