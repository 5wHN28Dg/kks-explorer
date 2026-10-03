# The walkable 3D combined-cycle plant: requirements

Settled with the user 2026-10-03. Status: **requirements only**. Next come the engine and platform investigation
(capability matrix, decision records) and the measurement rules, before any architecture or code (evidence-first
policy).

## Purpose

A learning tool: a combined-cycle plant you can walk through and operate, which looks, sounds and behaves like a
real one. Everything underneath is faked or reduced (no 1:1 process simulation). It extends the courses: "nothing
beats the real thing for learning".

## Settled

- **R1 Generic, public.** A generic CCPP, not a copy of any real plant, so the whole project can be public. Codes
  follow the public KKS standard, but the plant, its layout and its codes are invented. No plant data from any real
  site goes in.
- **R2 Configuration:** 2-2-1 multi-shaft: two gas turbines with generators, two HRSGs, one steam turbine with
  generator, and the balance of plant.
- **R3 Swappable condensing:** air-cooled condenser, wet cooling tower with water-cooled condenser, and once-through
  (sea/river) cooling. All three are available, chosen per scenario: the same plant with a different cooling end.
- **R4 Whole plant.** All areas: GT, HRSG, ST, condensing, BOP (feedwater, condensate, auxiliary systems), the
  electrical side as far as operation needs it.
- **R5 Geometry is made by us** (no EPC model, no photogrammetry): a plant **description** (equipment, positions,
  pipe routes, structures) built from a **kit of parametric parts**. Content is data, like the courses (COURSES.md).
- **R6 Operate (faked behaviour).** Valves, pumps, fans, breakers and the turbines' controls can be operated. The plant
  reacts through a declarative model: states, values with plausible lags, interlocks, alarms. Sounds, vibration and
  animations follow those values. Procedures (e.g. a cold start) run against it.
- **R7 Moving around:** first-person walking (stairs, ladders, platforms, doors), free flight and a 3D overview map,
  and guided tours along a system's path.
- **R8 Devices:** laptops (Windows, Linux) and phones, with the **Samsung Galaxy Note 9 (Android 10, 2018) as the
  minimum**.
- **R9 Photo-realistic, scaling smoothly.** Hard constraint (the user's words): it scales "perfectly and smoothly from
  the Note 9 all the way to the highest level of realism that is still useful for the goal". Performance and hardware
  limits are design inputs from day one, not a later optimization. In practice:
  - one plant description and one asset set for every tier; detail levels are generated or authored for each asset
    (geometry LODs, texture mips, material variants), never a separate "phone version";
  - quality adapts at run time per device (resolution scale, LOD distances, shadows, lighting model, effects),
    measured on the device, not guessed;
  - measurement rules (frame time, memory, load time, battery/thermal on phones) written before the first
    measurement, as for the apps (docs/m6/MEASUREMENTS.md).
- **R9a Realism must serve learning** (the user, 2026-10-03): "realism here is not for its own sake, everything needs
  to justify itself". Both the top and the bottom of the quality range are set by learning value: detail that helps a
  trainee recognize, find or understand equipment and its state stays on every tier (it is never cut to save
  performance; the tier finds another way to afford it); detail that doesn't help learning is not made at all, even
  for the top tier.
- **R10 Connected to the rest of KKS Explorer:** equipment carries KKS codes; the courses link into the 3D plant (as
  they link to the drawings, `/?kks=`); procedures and guided tours share one format.

## Open (to settle after the investigation)

- The engine. Candidates to investigate per platform, in the policy's order (what the platform gives, maintained
  libraries, then our own):
  - Godot 4: MIT, Android/Windows/Linux/web, Mobile and Forward+ renderers;
  - Unreal 5: Nanite and Lumen are not available on older phones; royalty terms;
  - Unity: licence terms;
  - Bevy (young);
  - our own renderer on the platform APIs (Vulkan / Direct3D).

  Each is measured with the same test scene on the Note 9 and a laptop.
- Frame-time targets per tier (proposal to confirm: Note 9 ≥ 30 fps sustained over 10 minutes without thermal
  throttling below that; laptops ≥ 60 fps).
- Download size and on-demand content (a whole plant at photo-realistic quality is large: which parts ship, which
  stream).
- Audio sources (recorded or licensed; must be publishable).
- Whether it is part of the KKS Explorer apps or a separate app sharing the core.
- Browser/iPhone (not required now).
