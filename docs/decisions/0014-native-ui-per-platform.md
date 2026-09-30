# 0014 Native UI per platform, no embedded web engine

Date 2026-09-30 · Scope: M6, all targets · Status: **decided by the user**; both consequences decided (2026-09-30)

**Decision:** each platform gets a native UI built with that platform's own toolkit. No WebView or other web engine
hosts the app's UI, even though the matrix found a system web engine on every target (docs/m6/CAPABILITIES.md §1).

**Why (the user):**
- to use each platform's own controls;
- to use its accessibility stack (UI Automation, AT-SPI, TalkBack), which the native policy counts as the argument
  that ends most debates;
- to get its system integration directly.

**What it costs** (the policy says don't pretend this is zero):
- **UIs to maintain:** Windows, GNOME and Android natively, plus the browser UI for Safari/iOS and anyone without the
  app (R19), because the browser path still exists. That's **four UIs** for one developer (N6).
- The shared parts must live below the UI: protocol, data, sync, rendering data. The UI layers stay thin.
- **Testing:** UI tests per platform on the platform (policy "A cost this policy imposes"); no Windows machine is
  available today.

**Open consequences, for the user to decide:**
1. **Courses (R8)** are authored as HTML/JavaScript: text, animated SVG figures, quizzes. Without a web engine in the
   app, the options are:
   - (a) open them in the system browser, outside the app (progress then needs a small local bridge);
   - (b) re-author them in a platform-neutral content format that each native UI renders (large work, three
     renderers);
   - (c) allow one exception: a web view only for course content.

   **Decided 2026-09-30: (b).** The courses become content in a platform-neutral format with its own specification:
   text, figures, quizzes, progress. Each native UI renders it. The animated figures and the quiz types become part
   of that format's design.
2. **Browser UI (R19):** keep today's web UI for browser clients (Safari/iOS, borrowed computers), or drop browser
   access.

   **Decided 2026-09-30: keep browser access.** That makes four UIs: Windows, GNOME, Android native, plus web for
   browser clients. The web UI falls under docs/evidence-first-web-engineering.md.

**Revisit:** if maintaining four UIs proves too slow in practice. Measure it by release cadence.

Sources: docs/m6/CAPABILITIES.md §1; docs/evidence-first-platform-engineering.md (Accessibility; A cost this policy imposes)
