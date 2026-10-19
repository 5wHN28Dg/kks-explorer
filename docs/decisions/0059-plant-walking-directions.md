# 0059 Walkdown Plant: walking directions over a navigation mesh baked by the content build

Date 2026-10-19 · Scope: `apps/plant3d` (builder/nav_bake.gd, app/walk_route.gd, ui/plant_ui.gd, tests/test_walk.gd)
· Status: **decided** under the task's go-ahead (PLANT3D.md §8 `"go": "walk"`, 0054 §10's walking test) · Extends
0054; no new dependency (Godot's own navigation module)

**Question:** how does the app show a trainee the way on foot to a step's equipment, across stairs, ladders and
areas, updating as they walk, without baking anything at start (the Note 9 loads in 14.8 s of its 15 s) and without
per-frame cost spikes on the lean tier? And how does the walking test prove every route walkable?

## Findings

[D] Godot 4.7 documentation; [V] measured here on the first train (2026-10-19, laptop, headless and offscreen).

| | Finding | Source |
|---|---|---|
| Baking offline | `NavigationServer3D.parse_source_geometry_data` + `bake_from_source_geometry_data` run headless from the built scenes' static collision shapes; the mesh is a Resource saved with the build | [D] navigation tutorials; [V] |
| Stair towers | Recast joined flights stacked above each other in HRSG 1's switchback tower into polygons spanning 6.5 m of height (154 edges shared by 3–8 polygons; Godot's region then dropped those connections, and the way up the tower stopped at +23.5). Watershed, monotone and layer partitions all did it (12–154 such edges) | [V] |
| Stairs as links | with each stair's body left out of the bake, its flights as obstructions down to the floor below, and a navigation link between its two ends walked along the stair's own path (the one `test_walk` climbs), no such edge is left | [V] |
| Flat tops | machines' tops, roofs and fan stacks are flat and became islands of the mesh, where a route to a nearby code ended (Recast cannot know nobody walks there). Keeping only what is reached from the plant's start, on foot and by the links, drops 800 of 2543 polygons | [V] |
| What the test found in the content | a cold reheat pipe crossed the drum platform's only walkway at 1.65 m headroom (raised to +35: 2.6 m); the drum stair's top ran 0.3 m into the HP drum's end in plan (moved 0.5 m north) | [V] `test_walk` |
| Size and load | `nav.res` 17.6 KB; loading it and adding the links takes 3 ms on the laptop | [V] `test_ui_walk_route` |
| Cost of a search and a redraw | a search 0.47 ms mean, 0.63–0.86 ms worst; the chevrons' redraw 0.4 ms mean, 0.8 ms worst (laptop, 120 s of the frames walk with a walking step that keeps leaving its way: 33 searches, 124 redraws). The Note 9 runs GDScript about 3.3 times slower (the model step, README): about 3 ms for each, once a second at most, never in the same frame | [V] `main.gd` `ROUTE` line |

Alternative: a waypoint graph from the content (stair paths, ladders, surface outlines). Exact on stairs and ladders,
but on floors it needs the clearance round equipment, rails and walls that the navigation mesh computes; that is a
navigation mesh of our own.

## Choice

- The content build bakes `built/nav.res` (cell 0.1 m, the walker's 0.3 m radius and 1.8 m height, climb 0.09 m:
  what the walker's capsule rides up), doors left out, stairs left out and obstructed, unreachable islands dropped; the
  stairs' and ladders' ways (each stair's path plus the floor in front of each end, checked with the walker's capsule
  against the stair's rails) are kept in the mesh's metadata.
- The app loads it into the world's navigation map with one link per stair and ladder, finds a way when the step's
  target changes and again only when the trainee leaves it by 2.5 m (checked 4 times a second, at most one search a
  second), draws 60 m of chevrons ahead, redrawn after each metre walked; target, search and redraw each in a physics
  tick of their own. A way on a ladder or a stair follows its own path.
- `test_walk` proves every tour stop and every walking step reachable by the path finder from the control room and
  walks the walker along those routes; every stair and ladder is walked both ways.

**When to revisit:** a Godot upgrade (the stair-tower behaviour and the region's edge merging may change); content
with ramps or stairs not made as `stair` (they would need to be walkable slopes in the mesh); if the Note 9's frame
log shows the redraw (then a shader that scrolls a fixed strip instead of rebuilding it).
