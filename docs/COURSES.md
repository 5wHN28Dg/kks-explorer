# Course content format, version 1

**Status: draft, M6 phase 1 (2026-09-30). Not frozen** until all 16 animated figures are converted and checked
against the originals (§12). Decision record 0025. Reference implementation: `ref/courses.py` (test-only). Vectors:
`ref/vectors/courses-v1.json`. The vectors, not the prose, are the tiebreaker.

A course is one JSON file, `courses/<course>.json`, published with the plant data (PROTOCOL-v2 §19). Its images are
`courses/<file>.jxl` in the same published version. Four renderers draw it with native widgets and the platform's 2D
API:
- Windows;
- GNOME;
- Android;
- the web UI.

Nothing in a course runs code. Figures are data: shapes whose numbers are looked up in tables (§9).

Authors don't write this JSON. They write text sources that a build tool on the developer machine validates and
compiles (0025 point 2). This document defines only the compiled JSON, which is what the renderers read.

## 1. JSON rules

- Plain JSON (RFC 8259), UTF-8, read with the platform's parser. Course files are not hashed field by field, so they are
  **not** canonical JSON (PROTOCOL-v2 §1). Their bytes are covered by the plant-data file hash.
- **Numbers:**
  - may have fractions;
  - must be finite, with absolute value below 10^9;
  - where the text says *integer*, a fraction is invalid.
- **Identifiers** (course, page, question, figure, value and toggle names) match `[a-z_][a-z0-9_]{0,31}`.
- **Unknown object keys are invalid.** New features come with a new `version`, so an old renderer refuses a file it
  would draw wrong, rather than drawing part of it.
- **Limits** (a renderer refuses the file above them):
  - file size 8 MiB;
  - 400 pages;
  - 64 figures;
  - per figure: 256 values, 2000 scene elements, 1024 points per table, 1000 particles.

## 2. The course

```json
{"format": "kks-course", "version": 1, "id": "ppt", "title": "…", "short": "…", "order": 1,
 "figures": {"<figure id>": Figure, …}, "glossary": [Gloss, …], "pages": [Page, …]}
```

- **`id`** is the progress key (§8). The three existing courses keep `ppt`, `fnd` and `hrsg`, so progress saved by the
  old HTML courses carries over.
- **`order`:** an integer, the position in the course list.
- **`pages`:** in rail order. Page IDs are unique within the course.
- **`figures`:** referenced by `figure` blocks. Every figure must be used at least once, and every reference must
  exist.

## 3. Inline text (a *run*)

A run is an array of items. An item is either:
- a string: plain text, drawn as-is (no markup, no entities); or
- an object with exactly one of these keys:

| object | meaning |
|---|---|
| `{"b": run}` | strong |
| `{"i": run}` | emphasis |
| `{"small": run}` | smaller, secondary text |
| `{"num": "12.44 MPa.a"}` | a number with its unit, set in the mono face and kept on one line |
| `{"term": run, "gloss": "<term>"}` | a glossary term; `gloss` must equal a `term` in the course glossary |
| `{"link": run, "to": Target}` | a link |

**`Target`** is an object with one of these forms:
- `{"course": id}`;
- `{"page": id}` (this course);
- `{"course": id, "page": id}`;
- `{"kks": "<code>"}`: opens that equipment in the app (the code without spaces, `[0-9A-Z]{4,24}`);
- `{"url": "https://…"}`: https only; opened in the system browser.

Runs are never empty. Whitespace is significant and not collapsed.

## 4. Blocks

A block is an object with exactly one kind key (other keys as listed):

| block | fields |
|---|---|
| `{"h": run, "level": 2\|3}` | heading. Level 1 is the page title. |
| `{"p": run}` | paragraph |
| `{"ul": [run, …]}`, `{"ol": [run, …]}` | list, at least one item |
| `{"table": {"head": [run, …], "rows": [[run, …], …], "num": [int, …]}}` | Every row has as many cells as `head`. `num` lists the column indexes (0-based) that hold numbers: right-aligned, tabular figures. |
| `{"callout": kind, "label": run, "body": [block, …]}` | kind is one of `why`, `why_general`, `at_plant`, `flag`, `note`. `label` is the tag text ("Why it matters", "At Rumaila", …): content, not styling. The body holds only `p`, `ul`, `ol` and `table`. |
| `{"cards": [[run, run], …]}` | a grid of short cards: title, text |
| `{"chain": [run, …]}` | at least 2 items, drawn as a row joined by arrows, wrapping when narrow |
| `{"figure": id}` | a figure (§9) with its title, caption and controls |
| `{"image": {"file", "w", "h", "alt", "caption", "credit"}}` | Described below the table. |
| `{"issues": [[severity, run, run], …]}` | a list of source issues: severity `high`, `medium` or `low`, a title, a text |
| `{"tool": "kks_decoder"}` | opens the app's KKS decoder (0025: the course's own decoder page is dropped) |

**`image` fields:**
- `file`: `[a-z0-9][a-z0-9._-]{0,63}\.jxl`, a file in the same published version (lossless or lossy JPEG XL, 0018);
- `w`, `h`: pixel size, integers;
- `alt`: a string;
- `caption`, `credit`: runs.

## 5. Questions

All questions have a unique `id` in the course, a question text `q` (run) and a source reference `src` (run, may
be `[]`).

- **`{"type": "choice", "id", "q", "options": [Option, …], "src"}`:**
  - 2–6 options, exactly one right;
  - `Option = {"text": run, "right": bool, "why": run}`: the feedback shown when the option is picked (may be `[]`);
  - options are shown in file order.
- **`{"type": "order", "id", "q", "steps": [run, …], "src"}`:**
  - 3–10 steps, in the right order;
  - the renderer shuffles them into a pool; the learner places them one by one and then checks;
  - wrong positions are marked.
- **`{"type": "scenario", "id", "panel": [Reading, …], "q", "options": [Option, …], "src"}`:**
  - a choice question under a panel of 1–10 readings;
  - `Reading = {"name": run, "value": run, "state": "" | "ok" | "alarm" | "act"}`; the state colours the value.

**Answering.** A question is **solved** when it is answered right:
- choice and scenario: the right option picked;
- order: all steps in place when checked.

In practice, a wrong pick shows its `why` and the learner may try again. In tests (§7), the first pick counts. The
right option is then revealed with its `why`.

## 6. Modules

```json
{"kind": "module", "id", "n": "3", "title": run, "short": "…", "goals": [run, …],
 "warm": Question, "body": [block, …], "worked": Worked | null, "practice": [Question, …],
 "bridge": Bridge}
```

- **`n`** is the displayed module number (a string: "0", "1", …).
- **`short`** is the rail label, plain text.
- **`warm`** is shown before the body: guess first.
- **`Worked`** = `{"case": run, "steps": [[run, run], …]}`: a title and a text per step, revealed one step at a
  time.
- **`bridge`** (optional) = `{"title": run, "intro": run, "questions": [Question, …]}`: questions written in the
  language of the next course, shown after the practice under their own heading (`title`, `intro` may be `[]`). At
  least one question.
- **Recall:** after the practice questions, a module shows **2 recall questions**, drawn at random from the `practice`
  questions of the modules before it:
  - choice and scenario questions only;
  - the pool is empty for the first module.
- A module is **done** when its warm-up, practice and bridge questions are all solved. Recall questions don't count.

## 7. Other pages

Each page has `id`, `title` (run) and `intro` (blocks, may be `[]`).

- **`{"kind": "placement", …, "items": [{"module": id, "q": Question}, …]}`:**
  - one attempt per question;
  - a module whose items are all answered right may be skipped;
  - the result is stored in `skip` (§8).
- **`{"kind": "test", …, "items": [{"module": id, "q": Question}, …], "draw": int | null, "pass": int, "on_pass": [block, …], "on_fail": [block, …]}`:**
  - an item may instead be `{"module": id, "ref": question id}`: a question of that module (warm-up, practice or
    bridge), asked again; a reference to a question the module doesn't have is `bad_ref`;
  - `draw` questions are drawn at random from `items` (`null` = all), in random order;
  - one attempt each;
  - finished: score ≥ `pass` shows `on_pass`, else `on_fail` plus the modules of the missed questions, as links;
  - the best score is kept (`finalBest`, §8).
- **`{"kind": "vocab_drill", …}`:**
  - draws a random glossary term;
  - offers its meaning and 3 other random meanings, shuffled;
  - repeats;
  - keeps a session score and streak (not saved).
- **`{"kind": "reading_drill", …, "items": [Reading drill item, …]}`:**
  - Item = `{"cat": "…", "name": run, "unit": "…", "context": run, "values": [number, …], "rules": [[op, number, state], …], "note": run}`.
  - `op` is one of `>=`, `>`, `<=`, `<`; `state` is `alarm` or `act`.
  - The judgement of a value is the state of the **first** rule it meets, else `ok`.
  - The page shows a random value of a random item from the selected categories. The learner picks *within limits*,
    *alarm* or *beyond limit*, then sees the right answer and `note`.
  - **Value display:** a minus sign is U+2212. Values in `mm` above 0 get a `+`.
- **`{"kind": "glossary", …}`:** the course glossary grouped by module, in module order.
- **`{"kind": "page", …, "eyebrow": "…", "body": [block, …]}`:** free content: quick reference, source issues, the
  trainer's audit, and so on.

**`Gloss`** = `{"term": "…", "meaning": run, "module": id}`:
- terms are unique;
- `module` names a module page.

**Question IDs for test copies.** The same question can appear as a module's practice and as a test item. The copies
are told apart by suffix: recall `_r`, test `_f`, placement `_p`. This is exactly what the HTML courses stored.
Question IDs in the file carry no suffix and must not end in `_r`, `_f` or `_p`.

## 8. Progress

Progress is saved as private entries `course_progress` (PROTOCOL-v2 §13), with the four keys of v1. Each value is a
JSON string:

| key | value |
|---|---|
| `last` | the ID of the page last opened |
| `skip` | object: module ID → `true` |
| `solved` | object: question ID (with suffix, §7) → `true` |
| `finalBest` | integer: the best test score |

Merging (unchanged from v1):
- objects → union;
- `finalBest` → maximum;
- otherwise the later value.

## 9. Figures

A figure is a picture in its own coordinate system (a *view box*), optionally animated.

```json
{"title": "…", "caption": run, "alt": "…", "w": 640, "h": 400,
 "period": 9, "slider": Slider, "toggles": [Toggle, …], "modes": [Mode, …],
 "values": [[name, Node], …], "scene": [Element, …], "status": Text}
```

**Fields:**
- **`w`, `h`:** the view box, integers 1–4000.
- **`alt`:** the text alternative, required.
- **`period`:** seconds per loop, 1–60. When absent, the figure is **static**:
  - no inputs;
  - no `slider`, `toggles`, `modes`, `status` or flows;
  - static figures are how charts and diagrams (pump curve, pressure scale, level ladder) are stored.
- **`slider`, `toggles`, `modes`, `status`:** each optional.

### 9.1 Inputs

Inputs are numbers that the controls and the clock set. They can be read by name:

| name | value |
|---|---|
| `t` | loop time, 0 ≤ t < 1 |
| `v` | slider value, 0–1 (0 when there is no slider) |
| each toggle's `key` | 1 when on, 0 when off |
| `mode` | the index of the selected mode, 0 when there are no modes |

**Controls:**
- **`Slider`** = `{"label": "…", "init": number, "drive": Table | absent, "text": Text}`. With `drive` (a table over
  `t`, §9.2), the slider moves by itself while playing: v = drive(t). `text` is shown next to it.
- **`Toggle`** = `{"key": id, "label": "…", "on": bool}`.
- **`Mode`** = `{"key": id, "label": "…"}`, at least 2 modes; one is selected at a time.

### 9.2 Values

`values` is an ordered list of `[name, Node]`. A node may read inputs and **earlier** values only, so the graph is
acyclic by construction. Names are unique and differ from input names.

A *ref* is a number or the name of an input or value.

| node | result |
|---|---|
| `{"of": name, "table": [[x, y], …]}` | piecewise linear (below) |
| `{"of": name, "table": […], "step": true}` | step: y of the last point with x ≤ input (the first y below the range) |
| `{"sum": [ref, …]}` | sum |
| `{"product": [ref, …]}` | product |
| `{"select": name, "cases": [ref, …]}` | `cases[clamp(floor(input), 0, n−1)]` |
| `{"follow": name, "rate": r, "rate_down": r2, "init": number}` | smoothing towards the input (stateful) |
| `{"hold": name, "while": name}` | the input, frozen while `while` ≥ 0.5 (stateful) |

**Tables** have 1–1024 points. The x values never decrease, and no three points share one x. For input u:
- u < x₀ gives y₀; u ≥ x_last gives y_last;
- otherwise take the largest i with xᵢ ≤ u and interpolate linearly to point i+1.

Two points with the same x make a **jump**. The value at that x is the second point's (right-continuous). Formulas
(`1 − (1 − f)^2.2`, `cos`, `exp`) are sampled into tables by the build tool. Renderers never evaluate formulas.

**Stateful nodes:**
- **`follow`:**
  - state o;
  - on the figure's first frame, o = `init`, or the input if `init` is absent;
  - every frame, o ← o + (input − o) · min(1, dt · k), with k = `rate` when input ≥ o, else `rate_down` (default:
    `rate`);
  - rates are > 0.
- **`hold`:**
  - while `while` ≥ 0.5 in this frame **and** the previous frame, the result is the held value;
  - otherwise the result is the input, and the input becomes the held value;
  - "previous" is false on the first frame.

### 9.3 Paint

- **Theme tokens:** `ink`, `muted`, `rule`, `accent`, `act`, `ok`, `alarm`, `alarm_fill`, `surface`, `sunk`, `ground`.
  - Each platform maps them to its light or dark palette.
  - Reference values (light / dark), taken from the HTML courses:

| token | light | dark |
|---|---|---|
| ground | #E9EDEF | #11171B |
| surface | #F8FAFA | #182026 |
| sunk | #DDE3E6 | #0D1215 |
| ink | #16222B | #E2E8EB |
| muted | #56646E | #95A4AD |
| rule | #C6CFD4 | #2B363D |
| accent | #1F5F8B | #6DAFDC |
| ok | #2E7A4E | #62C08A |
| alarm | #9A6412 | #E4AE45 |
| alarm_fill | #E8B04A | #B9832A |
| act | #B3261E | #F0776B |

- **Other paints:**
  - **`"#rrggbb"`:** a fixed colour, the same in both themes. Use it for physical colour scales (hot/cold), not for
    UI meaning.
  - **`"none"`.**
  - **Gradient:** `{"radial": [[offset, paint, opacity], …]}`, fills only. The centre and radius are the centre and
    half the width of the element's bounding box. Offsets run 0–1 and increase.
  - **Colour scale:** `{"of": name, "stops": [[x, "#rrggbb"], …]}`, interpolated per channel in sRGB and rounded to
    the nearest integer (halves up).
  - **Colour steps:** `{"of": name, "steps": [[x, paint], …]}`: the paint of the last stop with x ≤ input (the first
    below the range). Steps may use tokens.

### 9.4 Scene

`scene` is drawn in array order; later elements cover earlier ones.

**Common fields** of every element except `flow`, `label` and `group` (all optional):

| field | default |
|---|---|
| `fill` | `none` |
| `stroke` | `none` |
| `stroke_width` | 1 |
| `opacity` | 1 |
| `dash` | none (an array of lengths) |
| `cap` | `butt` (also `round`, `square`) |
| `join` | `miter` (also `round`, `bevel`; miter limit 4) |
| `transform` | none (below) |

**Numbers and refs:**
- every number in an element may be a ref (§9.2), except `dash` lengths, `points` counts and `size`;
- an element with opacity ≤ 0 is not drawn.

**Elements:**

| element | fields |
|---|---|
| `{"rect": [x, y, w, h], "rx": r}` | w, h ≥ 0; `rx` optional (rounded corners, clamped to half the shorter side) |
| `{"circle": [cx, cy, r]}` | |
| `{"ellipse": [cx, cy, rx, ry]}` | |
| `{"line": [x1, y1, x2, y2], "arrow": true}` | `arrow`: an arrowhead at the end (below) |
| `{"poly": [[x, y], …], "closed": bool}` | 2–1024 points |
| `{"path": [cmd, …]}` | `["M", x, y]`, `["L", x, y]`, `["C", x1, y1, x2, y2, x, y]`, `["Z"]`; the first command is M |
| `{"text": Text, "at": [x, y], "anchor": "start"\|"middle"\|"end", "size": n, "font": "body"\|"display"\|"mono", "weight": 400\|600\|700}` | defaults: start, 12, body, 400, `fill` `ink` |
| `{"label": "…", "at": [x1, y1], "to": [x2, y2], "anchor": "start"\|"end"}` | a label with a leader line (below) |
| `{"group": [Element, …], "clip": {"rect": [x, y, w, h], "rx": r}}` | `clip` optional, in the group's own coordinates (the group's transform moves it too); `opacity` and `transform` apply to the whole group |
| `{"flow": Flow}` | moving particles (§9.5) |

**`transform`:**
- a list of steps, applied first to last in the element's coordinates (as in SVG):
  - `{"translate": [dx, dy]}`;
  - `{"rotate": [degrees, cx, cy]}`: clockwise on screen, y down;
  - `{"scale": [sx, sy]}`;
- text is transformed with its element.

**Arrowhead:**
- a filled triangle in the line's stroke colour, pointing along the line;
- with stroke width w: tip at the end point plus 1.2 w along the line; base 6 w behind the tip; half-width 3 w;
- the line itself is drawn to the end point.

**Label (the course figures' callout labels):**
- text: size 12.5, body font, ink, at `to`, with `anchor` (default `start`);
- a dot of radius 2.5 in `muted` at `at`;
- a 1-unit `muted` line from `at` to the leader end E, found as follows:
  - the text's box is [left, right] with w = 6.3 × (number of characters);
  - left = x2 − w for `end`, else x2; right = left + w;
  - if x1 < left − 2: E = (left − 4, y2 − 4);
  - else if x1 > right + 2: E = (right + 4, y2 − 4);
  - else E = (x1, y2 + 4) when y1 > y2, and (x1, y2 − 15) otherwise;
  - the estimate (not the drawn text's width) keeps the four renderers identical.

**Fonts:**
- the three roles map to the courses' faces: body = Atkinson Hyperlegible, display = Barlow Semi Condensed,
  mono = JetBrains Mono (vendored, OFL);
- sizes are in view-box units;
- the baseline is at `at`.

### 9.5 Flows

Particles moving along routes: water in a pipe, gas through a damper, bubbles in a riser.

```json
{"count": 30, "routes": [Route, …], "lanes": [[dx, dy], …], "speed": ref, "r": ref, "fill": paint,
 "stroke": paint, "stroke_width": n, "opacity": ref, "glyph": "dot"|"burst",
 "along": {"speed": T, "r": T, "opacity": T, "lane": T, "fill": [[k, paint], …]},
 "hide": [{"rect": [x0, y0, x1, y1], "when": ref}, …],
 "reverse": "wrap"|"pile", "pile": n, "wrap_x": [x0, x1]}
```

**Fields:**
- **`count`:** 1–200.
- **`Route`** = `{"path": [cmd, …], "weight": ref, "lanes": [[dx, dy], …]}`. One subpath (M, then L and C). The
  `weight` (default 1) and `lanes` (default: the flow's) fields are optional.
- **Defaults:**
  - `lanes` [[0, 0]], `speed` 0, `r` 3, `fill` `accent`, `stroke` `none`, `stroke_width` 1, `opacity` 1;
  - `glyph` `dot`, `reverse` `wrap`, `pile` 0;
  - every `along` table is absent (factor 1).
- The **`along` tables** (T, §9.2 table rules) are over the particle's position k (0–1). They multiply `speed`, `r`,
  `opacity` and the lane offset. `fill` is a step list over k.

**Particle state.** Particle i (0 … count−1) has:
- position kᵢ, starting at i / count;
- wrap counter nᵢ = 0;
- route ρᵢ = choose(i, 0).

choose(i, n):
- u = frac((i + n · count) · φ), with φ = 0.6180339887498949;
- the weights are clamped to ≥ 0 and read in route order;
- the result is the first route whose running sum exceeds u · total;
- if total is 0, route 0.

**Route geometry:**
- M/L segments stay as they are; each cubic becomes 16 segments at equal parameter steps (t = 1/16 …);
- L = the length of the resulting polyline;
- refs in routes are evaluated every frame, so routes may move.

**Every frame** (dt from §9.6), for each particle, in index order:
1. Δk = speed · along.speed(kᵢ) · dt / L (0 when L = 0).
2. kᵢ ← kᵢ + Δk.
3. With `pile` and Δk < 0: kᵢ ← max(kᵢ, min(1, pᵢ / L)), where pᵢ = pile · frac(i · φ) (pᵢ / L = 0 when L = 0).
   Particles moving backwards heap up over the first `pile` units of the route (a check valve's disc).
4. If kᵢ ≥ 1:
   - kᵢ ← kᵢ − floor(kᵢ);
   - nᵢ ← nᵢ + 1;
   - ρᵢ ← choose(i, nᵢ).

   If kᵢ < 0 (only possible with `wrap`): kᵢ ← kᵢ − floor(kᵢ). No new route.
5. Position = the point at arc length kᵢ · L, plus lane · along.lane(kᵢ). The lane is `lanes[i mod len]` of the
   route, else of the flow.
6. With `wrap_x`: x ← x0 + mod(x − x0, x1 − x0), for patterns repeating sideways.
7. Radius = r · along.r(kᵢ). Opacity = opacity · along.opacity(kᵢ), then 0 if the position lies inside a `hide`
   rect (edges included) whose `when` ≥ 0.5.

**Drawing:**
- `dot`: a circle, filled with `fill` (or `along.fill`) and stroked with `stroke`.
- `burst`: three strokes through the position:
  - horizontal and vertical, of half-length r;
  - one diagonal from (x − 5r/7, y − 5r/7) to (x + 5r/7, y + 5r/7);
  - in `stroke` with `stroke_width` (the collapse of a vapour bubble).
- Particles are drawn in index order, at the flow's place in the scene.

### 9.6 Clock and controls

**The state:**
- t = 0;
- v = `slider.init`;
- toggles as their `on`;
- mode 0;
- **playing** unless the platform asks for reduced motion (then paused).

**Frame 0** is evaluated and drawn with dt = 0 before the first tick.

**Each tick:**
1. elapsed = seconds since the last tick, capped at 0.05. If the figure is off screen, nothing happens (state frozen).
2. If playing: dt = elapsed; t ← frac(t + dt / period); with a `drive`, v ← drive(t). If paused: dt = 0.
3. Evaluate `values` in order (§9.2), then the flows (§9.5).
4. Draw the scene; update the status and slider texts.

**Controls:**
- **Play/Pause button:** toggles playing.
- **Slider:**
  - moving it sets v;
  - when the slider has a `drive`, moving it also pauses (the learner took over);
  - range 0–1 in steps of 0.001.
- **Toggle:** flips its input, sets t = 0 and plays.
- **Mode:** selects the mode and plays.

A static figure has no clock, controls or status line.

### 9.7 Text templates

A **`Text`** is either a template string, or a list of cases `[{"when": ref, "text": template}, …, {"text":
template}]`. The first case whose `when` ≥ 0.5 wins; the last case has no `when`.

**Placeholders:**
- `{name}`: rounded to an integer;
- `{name:N}`: N decimals (0–6);
- `{name:+N}`: also a sign when not negative;
- `{{` and `}}`: literal braces.

**Rounding:**
- the exact binary value, rounded half away from zero;
- the minus sign is U+2212;
- a value that rounds to zero has no minus sign.

### 9.8 Accessibility and layout

- **Scaling:** the view box is scaled to the available width, keeping its aspect ratio. It is never scaled above
  1:1 or below a width of min(w, 520); below that the figure scrolls sideways.
- **Accessible name:** the figure is exposed as an image with `title` as its name and `alt` as its description.
- **Controls:** native widgets, labelled with their `label`. The slider's accessible value is its `text`.
- **Status line:** shown below the figure; not announced on every change (it changes every frame).

## 10. Rejected files

A renderer refuses the whole file (and keeps showing the previous version) when:
- any rule above is broken;
- a key is unknown or missing;
- an ID is used twice, or a reference (page, module, figure, glossary term, value name, image file) doesn't exist;
- a value reads a later value;
- a `drive` is not a table over `t`;
- a static figure has inputs or flows;
- a limit (§1) is exceeded.

The error codes in the vectors (`ref/vectors/courses-v1.json`) name the rule:
- **Structure:** `bad_type`, `missing_key`, `unknown_key`, `bad_kind`, `bad_length`.
- **Values and IDs:** `bad_number`, `bad_value`, `bad_id`, `dup_id`, `bad_format`, `bad_version`, `limit`.
- **References:** `bad_ref`, `forward_ref`, `unused_figure`, `bad_link`.
- **Figure rules:** `bad_question`, `bad_table`, `bad_paint`, `bad_path`, `bad_template`, `bad_drive`,
  `static_inputs`.

When a file breaks several rules, the code of the first one found may differ between readers. The vectors break one
rule each.

## 11. What the vectors check

- **`valid`:** small courses that must load, with the expected page, question and figure counts.
- **`reject`:** files that must be refused, each with its code.
- **`frames`:** a figure, a list of events and the expected evaluation after each tick:
  - events: tick with elapsed seconds, slider, toggle, mode, play, pause;
  - checked results: inputs, values, flow particle positions, radii and opacities, resolved texts;
  - compared to 1e-6.

  They pin the clock, the stateful nodes, the flow update, route choice, piles, hide rects and template formatting.
  Every renderer runs them through its own evaluator. Pixels are not compared: drawing is the platform's, as for
  the path store.

## 12. The 16 animated figures in this model

Each of the course figures, and how it maps. **Simplified** marks what the original did differently.

**Verified 2026-09-30** (`tools/m6/course_figures.py`):
- all 16 are converted and pass the validator;
- 22 states (figure, t, slider, toggle, mode) are compared side by side with the original JavaScript in Chromium;
- the converted figures total 206 KB of compact JSON.

At every state, the geometry, labels, texts, status lines and particle routes match. Particle spacing differs, as
listed. Motion is not compared frame by frame: the originals are stateful and start their particles differently.

**Second implementations (2026-10-01):** the Nim core (`core/src/kks/courses.nim`) and the web renderer
(`course-figure.js`, in Chromium, Firefox and WebKit) pass the vectors. The three real courses are converted
(`tools/m6/convert_courses.py`) and pass both validators. The four renderers exist and pass their end-to-end tests
(decisions 0035, 0036). **Ready to freeze**, after the user has looked at the two additions of 2026-10-01 (`bridge`,
test items by `ref`).

| figure | inputs | how it maps |
|---|---|---|
| gate | slider (drive ping) | gate and stem y: tables of v; handwheel spoke ends: tables of v (sampled cos/sin); flow speed ∝ q(v) = 1−(1−v)^2.2 as a table; lanes = pipe heights; `hide` rect under the gate while it's down. |
| globe | slider (drive ping) | plug y: table; flow along the S-path route (curves), lane offsets squeezed in the channel via `along.lane`. |
| check | none (time) | disc angle: `follow` of a step table of t (open 62°, then 0), rate 3 up / 9 down; two flows: upstream (speed 150 → 0) and downstream (150 → −40 → −90, `pile` 20 at the disc); status: cases on t. **Simplified:** upstream particles wrap at the disc instead of continuing across it. |
| quarter | slider (drive ping) | butterfly line ends and ball rotation: tables of v; two flows with speed tables (sin^1.6, sin^2.4); `hide` rect in the ball while a < 60°. |
| safety | none (time) | lift: `follow` of an open/closed step table (rates 18 / 10); disc, spindle, spring zig-zag points and label: tables of lift; pressure trace: a polyline revealed by a clip rect whose width is a table of t, dot position tables of t; puffs: flow with `along.r` / `along.opacity`, opacity = step(lift > 0.3). |
| trap | none (time) | water level y: table of t; float centre on its arc: two tables of t; lever end = float centre; outlet plug y: step table; drop, steam and outlet flows with opacity step tables. **Simplified:** drops fall to a fixed surface line, not the moving level. |
| pump | toggle cav | impeller: group rotated by a table of t (whole turns per loop); particles on the vane spiral inside the rotating group; volute exit as a second flow fading out; bubbles: two coincident flows (dot, then burst) with `along.opacity` windows, opacity × cav. **Simplified:** random re-seeding of start angles is replaced by fixed lanes; speed rounded so the loop is seamless (120°/s instead of 110°/s). |
| gear | toggle blk | gears rotated by tables of t (288° per loop = 8 teeth, seamless; the original turned 280°); outlet pressure: `follow` of select(blk) (rate 2); needle end: tables of pressure; relief valve y, bypass flow opacity: step tables. |
| gen | none (time) | rotor: rotation table of t (two turns per loop); coil opacities and dots: tables of t (sampled \|cos\|); cursor x: table; status: three `{…:+2}` placeholders. |
| stage | none (time) | blade row: translate by a sawtooth table of t (jumps), inside a clipped group (**simplified:** blades slide out under the clip edge instead of vanishing whole; 4 blade pitches per loop instead of 3.75); particles: one route through the bands with `along.speed`, `along.fill` (red → blue at k 0.45), `along.r`; lanes spread along x; `wrap_x` [150, 640]. **Simplified:** each particle follows the route instead of relaxing its sideways speed band by band. |
| circ | toggle swell | ev: select(swell) of a table of t; level y and height, speeds, readouts: tables of ev and t; risers: coincident water and bubble flows with `along.opacity`, `along.r`; bubble radius × (4 + 3 ev); steam route moving with the level (refs in the route). |
| wall | slider (no drive) | R = step table of v (1–20 °C/min); 1/R: table; dT = 11.84 R (1 − e^(−42.86 t/R)) as product(R, table(product(t, 1/R))); strip colours: colour scales of the per-strip temperature (sum/product nodes); profile polyline points: refs. |
| orifice | slider (drive cos) | column heights: tables of v (∝ v²); flow speed × `along.speed` (fast in the vena contracta), lanes squeezed by `along.lane`. |
| gauge | modes (4) | real level: table of t; gauge = select(mode) of [real, real+120, real−120, hold(real, while blocked)]; clamped bar heights: tables; leak flows with opacity select(mode). |
| damper | slider (drive ping) | blade end: tables of v; two routes, bypass weight = v, HRSG weight = 1 − v (`choose` at each wrap); seal-air groups: opacity step tables; fan text: cases. |
| expand | slider (drive ping) | pipe width, support translations, pointer: tables of v; pipe colour: colour scale of v. |

The static figures (pump curve, valve characteristics, three-phase waves, KKS anatomy and ranges, cycle diagram,
saturation curve, pressure scale, level ladder, the diverter damper diagram) use rect, line, poly, path and text only.
The build tool computes their curves.

## 13. Not in version 1 (deliberately)

- No scripting, no expressions, no conditionals beyond tables, `select` and text cases (0025: four renderers must
  agree, and content must not run code).
- No images inside figures, no filters, no blur, no gradients other than radial fills.
- No per-course styling: the renderers own typography and colours.
- No Arabic UI. Content text in any script is drawn by the platform's text engine (REQUIREMENTS: English UI, Arabic
  content must display correctly).
