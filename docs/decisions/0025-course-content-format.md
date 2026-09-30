# 0025 Course content format

Date 2026-09-30 · Scope: R8 (courses), N2 · Status: **accepted by the user 2026-09-30**

**Given:** 0014 (b): the courses are re-authored in a platform-neutral format that each native UI renders (Windows,
GNOME, Android) plus the web UI. No web engine inside the apps.

**Inventory of today's three courses** (rumaila-handoff/courses, 2026-09-30):
- **Modules:** 36, each with goals, a warm-up question, the lesson, a worked example, practice, and recall questions
  from earlier modules.
- **Questions:**
  - about 250 multiple choice with feedback per option;
  - 9 ordering;
  - 8 scenario (a panel of instrument readings with alarm states, then a choice).
- **Blocks:**
  - 77 tables;
  - about 40 callouts (flag, "Why · general practice", "At Rumaila");
  - highlighted numbers with units;
  - 4 pressure-scale charts;
  - 28 photos with credits.
- **Special pages:** placement test, vocabulary drills, final checks (random draw, best score kept), glossary, quick
  reference, issues lists, a KKS decoder.
- **Animated figures:** 16 distinct ones (gate, globe, check, quarter-turn and safety valves, steam trap, pump, gear
  pump, generator, turbine stage, natural circulation, drum wall stress, orifice, gauge, diverter damper, pipe
  expansion). Each is hand-written JavaScript: a slider or play/pause drives one parameter, plus moving flow
  particles.
- **Progress:** last position, skipped, solved question IDs, best final score. Private entries already sync them.

**Platform facts:** no platform provides a course or quiz format. All four UIs provide rich text, tables, images,
native radio buttons and sliders with accessibility, and a 2D drawing API (the same one the viewer uses, 0016).

**Proposed:**
1. **One content model, delivered as JSON.** Every platform parses JSON natively (0024 §1). A JSON Schema plus a
   written specification with test vectors, like the protocol.
   - **Blocks:** heading, paragraph, list, table (numeric columns right-aligned), callout (warning, caution, note,
     why-general, at-plant), image (JXL, alt text, caption, credit), figure, scale chart, worked example.
   - **Inline spans:** text, strong, emphasis, number-with-unit, glossary term, link. A link can target a course, a
     module, a **KKS code (opens the equipment in the app)** or a web page.
   - **Questions:** choice, order and scenario, each with per-option feedback and a source reference.
   - **Pages:** module, drill, test (draw N from a pool, pass mark, keep best), glossary, reference, issues.
   - The KKS decoder page becomes a link to the app's own decoder.
2. **Authoring stays in text, compiled at build time.** Authors write Markdown-like source files with fenced blocks
   for questions, tables and figures. A build tool (on the developer machine, not in the apps) validates the source
   and writes the JSON. The apps never parse Markdown, so no Markdown library ships.
3. **Figures are declarative, not code:**
   - a scene of shapes (paths, rectangles, circles, text, labels with leader lines) in a view box;
   - one parameter p from 0 to 1, driven by a slider or a loop;
   - properties change with p through keyframes or piecewise-linear tables: position, rotation about a pivot, scale,
     opacity, colour, morphing between paths of the same structure;
   - a **flow** primitive: particles along routes, whose split between routes depends on p;
   - a status text built from p.
   - No scripting: four renderers must agree, and content must not be able to run code.
   - Every figure has a text alternative, and its slider is a native accessible control.
   - All 16 figures must be expressible before the format is frozen. Figures that need more (e.g. a pump curve)
     extend the model deliberately, with a new vector.
4. **Distribution:** courses become a **content set published like plant data** (PROTOCOL §19, by the manager), so a
   course fix doesn't need an app release. The source stays in the public repository, as the user chose on
   2026-09-28.
5. **Progress** stays private entries (PROTOCOL §13, AES-GCM from 0024), with the same four fields.

**Costs:**
- Re-authoring 36 modules, about 270 questions and 16 figures into the new source format. Conversion can be largely
  scripted from today's JS structures, except the figures, which need the most manual work.
- Four renderers of the model (Windows, GNOME, Android, web).
- A specification and test vectors to keep them identical.

**Revisit:** if the figure model can't express a needed animation without scripting.

Sources: inventory of rumaila-handoff/courses/*.html (grep of M.push, Q/O/S, helpers, VIS figures); docs/decisions/0014, 0016, 0024
