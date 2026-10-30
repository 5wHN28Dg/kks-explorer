# 0071 Walkdown Plant's lifts and hoists: the cab and the hooks as model content, riders as inputs, the lift as a kind of way

Date 2026-10-30 · Scope: docs/PLANT3D.md §20 (format 2), `ref/plant3d.py`, `ref/plant3d_staff.py`, `apps/plant3d/sim`,
the first train's content, the app · Status: **proposed**, written before any code under the user's decision of
2026-10-27 (a working rack-and-pinion service lift on each HRSG, working hoists for heavy parts) · Extends 0054, 0062,
0067; no new dependency

**Question:** how does a lift that carries the trainee and the NPCs, and hoists and a crane operated in procedures,
live in the deterministic engine so that (a) every player of a session and the Python reference see the same cab, the
same riders and the same hook, bit for bit, (b) the staff's routes and walk times use the lift on long climbs, (c) a
blocked lift never leaves the staff stuck, and (d) the Note 9 keeps the frame rules?

## Findings

[V] verified here, [S] the sources named.

| | Finding |
|---|---|
| What such lifts are | Rack-and-pinion industrial lifts on HRSG stair towers are a known application: three Alimak SE 500s, one per HRSG stair tower of a UK combined-cycle plant [S1]. The SE 500: 500 kg net load, a car of about 1.04 × 1.17 m, 0.4–0.63 m/s direct on line, 0.4–1.0 m/s with frequency control [S2]. |
| Their safety | Landing gates are interlocked so the lift can't run unless they are closed [S3]; a landing gate can't open unless the car is at that landing [S4]. Makers list overload sensing among the standard protections [S5]. EN 81-20's capacity rule counts 75 kg a person [general practice]. |
| Codes | The public KKS key part extract [E2 of FIRST-TRAIN.md §1] has `SN` elevator installations (`SNB` boiler house lift), `SM` overhead cranes, permanent hoists and lifting devices (`SMF` boiler house crane, `SMT` turbine house crane), and the equipment units `AB` (access gates, doors), `AE` (turning, driving, lifting and slewing units), `GH` (control boxes) and `CW` (weight, force) [V: pdftotext of the extract]. |
| What the model can say already | A cab that goes to the landing asked for and stops where it is when it may not move is a `ramp` whose input is the target height or, while it may not move, its own last height (a stateful node reads every reference as the previous step left it, §7.1: the ramp stays put exactly) [V: worked through §7.1's rules]; gates are states with ramps; permissives, interlocks, alarms, faults, isolations and screens work on them as on any pump. A hook, a trolley and a crane's bridge are the same: a `set` op of −1, 0 or 1 per motion (the pendant's hold-to-run buttons: pressed, released), an `integrate` of the speed between its limits, a `hold` (§15.4) for a load that stays where it was put down. |
| What it can't | The load in the cab: who is aboard is not a value, and the staff step writes no value (§17.1). An NPC that takes a way of fixed time can't ride a cab that is somewhere else. |
| The routes | §16.2's `next` table is made by the content tool and only looked up; a lift way's time in that table can only be a nominal one, and a ride takes what the cab takes. |
| The phone | A model step costs 1.36–1.45 ms on the Note 9 with the staff (MILESTONES.md, S2 measured); about 40 more values are a few µs. A moving cab is one `AnimatableBody3D` as the doors are (`app/door.gd`). |

Alternatives for the cab: (1) **content of format 1's nodes**, with a small `lifts` entry naming its handles for the
staff and the engine; (2) a new engine element that is the lift (calls, direction, gates in engine code): two engines'
code for what content can already say, and nothing a trainee sees changes; (3) the lift drawn only (the app moves the
cab, the staff take a way of fixed time): not the same on every screen, and an NPC rides an empty shaft.

Alternatives for riders: (a) **`board` and `alight` inputs**, the trainee's from the app (as `zone` is) and the NPCs'
queued by step 9 for the next step's step 1 (as their ops are), and a value the engine keeps, `<lift>_load`;
(b) the staff step writing the load: breaks §17.1's rule that step 9 writes no value.

## Choice

- (1) and (a): the lift is model content made by the content tool; the model's `lifts` entry names its landings'
  values and ops and its rated load; the engine keeps the riders (in boarding order) and the value `<lift>_load`.
- The staff walk a **way of mode `lift`** between two landings' points: its time in `next` is nominal
  (`speeds.lift`); a person who takes it walks to the landing and rides by the protocol of PLANT3D.md §20.4, making
  inputs as anyone; a lift that is not ready, or a wait over 3 minutes of model time, sends them up the stairs: each
  lift way's route without lift ways, searched by both engines at load.
- Hoists and the turbine hall's crane are content only (no engine change), operated by `set` ops and used in
  procedures.
- The view (cab, gates, riders, hooks, loads) follows the model's values, interpolated between steps; nothing of it
  is in the vectors.

**Revisit** if a lift needs collective control (several calls served in one trip) or the trainee's walking
directions should use lifts (a navigation link per lift): both are possible on top of this.

Sources: [S1] Modern Power Systems, "Three Alimak elevators give access to the HRSGs",
https://www.modernpowersystems.com/whitepapers/three-alimak-elevators-give-access-to-the-hrsgs/ · [S2] Alimak, "SE/SE Ex
modular range, EN 81" data sheet (Oct 2020),
https://alimak.com/au/wp-content/uploads/sites/19/2020/11/ALIMAK-SE-SE-Ex-modular-range-EN-81-1683-EN-Oct-2020.pdf ·
[S3] UK HSE / Prospect, safety notice for service lifts, https://prospect.org.uk/news/hse-issues-safety-notice-for-service-lifts-in-wind-turbines
· [S4] LEIA, "Safety at lift landings", https://www.leia.co.uk/wp-content/uploads/2018/07/66-Safety-at-Lift-Landings-PM26-1903.pdf
· [S5] UCEL, "Common safety features in modern rack and pinion lifting systems",
https://ucelinc.com/knowledge-center/common-safety-features-in-modern-rack-and-pinion-lifting-systems
