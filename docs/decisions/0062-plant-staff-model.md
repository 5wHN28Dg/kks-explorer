# 0062 Walkdown Plant's staff: a declarative day in content, run by our own deterministic engine through the trainee's inputs

Date 2026-10-22 · Scope: docs/PLANT3D.md format 2 (§15–§17, §19), docs/plant3d/STAFF.md, `ref/plant3d.py`,
`apps/plant3d/sim` · Status: **proposed**, written before any code under the user's decision of 2026-10-22 ("full
roles to play") · Extends 0054; no new dependency

**Question:** how do NPC staff decide what to do (shift rosters, routines, rounds, permits and isolations, jobs,
safety walks, meals and sleep) so that (a) their work really changes the plant, (b) the trainee can take any role
and the others are filled, (c) the same seed gives the same day, testable against vectors like the behaviour model
(§7), with the GDScript engine bit for bit with the Python reference, and (d) it costs the Note 9 almost nothing
(a model step already takes 1.4 ms there and caps fast-forward at about 18×, apps/plant3d/README.md)?

## Findings

| | Finding | Source |
|---|---|---|
| What Godot gives | No behaviour or AI framework; NavigationAgent3D (paths, RVO avoidance "in its own space … no information from navigation meshes"), AnimationTree state machines for animation | [D] class_navigationagent3d, animation docs |
| Addons | LimboAI (behaviour trees and state machines; MIT; a C++ module or a GDExtension; v1.8.1, 2026-08-20) and Beehave (behaviour trees in GDScript; MIT; v2.9.3, 2026-08-18): both active | [K] github.com/limbonaut/limboai, github.com/bitbrain/beehave |
| Why an addon doesn't fit | the vectors need a second, independent implementation (`ref/plant3d.py`) of every rule; a behaviour tree library's tick semantics (running/success/failure, re-evaluation order, decorators) would have to be re-implemented in Python exactly, and a GDExtension adds native builds per platform (0054 kept the app script-only) | [K] |
| How the model already works | content declares, the engine evaluates at a fixed 0.1 s step; trainee inputs are queued for step 1; the vectors pin inputs, events and snapshots (§7.10, §12) | docs/PLANT3D.md |
| Time | a real 12-hour shift at 1× is far too long to play; the model's fast-forward is capped at ~18× on the Note 9; process dynamics already compressed (a 4-hour cold start in 110 model minutes, FIRST-TRAIN.md §4) | README, FIRST-TRAIN.md |
| Random numbers | GDScript ints are 64-bit signed; a 32×32-bit product can pass 2⁶³, so a generator must be written to avoid it (16-bit halves) or use shifts and xors only | [D] GDScript int |
| Real practice | permits to work: request, approval, isolation (lock and tag), issue, acceptance, work, return, de-isolation, closure; shift handovers; rounds with readings | general industry practice (e.g. UK HSE's guidance on permit-to-work systems, HSG250: https://www.hse.gov.uk/pubns/books/hsg250.htm) |

Alternatives: (1) behaviour trees (an addon or our own); (2) GOAP or utility AI: emergent plans are hard to pin with
vectors and harder for a trainer to predict ("the operator will grant the permit at 08:10"); (3) schedule-driven
task lists in content with a small set of reactions: what a plant's routines and procedures already are.

## Choice

- **(3), declared in content** (`staff.json`, PLANT3D.md §16): roles with authorities, people with rosters, routines
  of timed slots, tasks as ordered steps (go, work, read, op, permit, lock, ppe, say, wait, call, meet, choose, ride,
  sleep), reactions to alarms, trips, faults, values, permits and unsafe acts. Like the model, no code in content.
- **Permits and isolations are model objects** (§15), so a lock refuses ops, skips automatic writes and suppresses
  alarms in the same step whoever made it.
- **One engine, step 9**: the staff run after the model's step 8 and act on the plant **only through inputs** queued
  for the next step, after the trainee's (§17.1). An NPC is refused exactly as the trainee would be; a day is fixed by
  the seed and the trainee's inputs. The trainee's person runs the same tasks, each step waiting for the trainee's
  matching input (§17.4).
- **Positions are logical**: places and ways (a graph made from the layout by the content tools, checked by the build
  against 0059's navigation mesh), routes by integer steps with a fixed tie rule; the app draws avatars along stored
  polylines (0064). No physics or avoidance in the logic.
- **Time**: a plant clock `day_scale` (6) times faster than model time for everything people plan by the clock, so a
  shift is 2 model hours; inventories that take hours on site run at clock rates (WATER-TREATMENT.md §5); a jump to
  the next shift when the plant is quiet holds the plant and re-places the people (§17.6), since running 2 model hours
  at the Note 9's step cost would take minutes.
- **Random numbers**: one xorshift32 stream per person, seeded through Wellons' lowbias32 mix, with 32-bit products
  defined exactly (§17.5); draws only at `work` ranges and `choose`.
- Reference in `ref/plant3d.py`, vectors `plant3d-v2.json` (§19), the GDScript engine bit for bit; cost budget 0.3 ms
  per step on the Note 9 (§18.4); with the WTP's model (0065) the fast-forward cap falls from about 18× to no less
  than 12×. Routes are never searched at run time: the content tool ships the walking network's next-point table
  (§16.2), which the reference checks; people with nothing due in a step may be skipped by an implementation as long
  as the result is the same.



**When to revisit:** if trainers need behaviour the step list can't say (then a bounded addition to the step kinds,
with vectors, before any general scripting); if the staff step's cost on the Note 9 passes its budget; if the jump's
held plant is found misleading in training (then a background run of the night).
