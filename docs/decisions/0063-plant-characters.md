# 0063 Walkdown Plant's people: MakeHuman CC0 bodies, our own work clothes and PPE, KayKit CC0 animations

Date 2026-10-22 · Scope: avatars for format 2's staff (docs/PLANT3D.md §18.2–§18.3), `apps/plant3d` (kit props,
import), the about list · Status: **proposed**, written before any code; the asset rule stays CC0-only (0054 §5, §7);
the Quaternius and non-CC0 options are the user's questions (end) · Extends 0054

**Question:** where do the bodies, clothes and animations of about 90 generic plant staff come from, under the
project's rule that assets are CC0 (the repository and the packages are public; files are committed or fetched by a
pinned script and redistributed in the app), at a cost the Note 9 can carry (0064)?

## Findings (2026-10-22; pages read that day)

| Source | Licence | What it has for us | Notes |
|---|---|---|---|
| Quaternius Universal Animation Library 1 and 2, Universal Base Characters | pack and itch.io pages say "CC0" (UAL2 v2.2 page updated 2026-09-28); **but quaternius.com/license.html is now the "Quaternius Asset License v1.0" (2026-08-28)**, whose §3a forbids redistributing the assets "as a standalone asset, asset pack, stock file…", §7: the version in effect when obtained governs | UAL1 free tier 45 clips (idle, walks, talk, sit, interact, pick-up, kneeling fix, push, driving); 53-joint Rigify-named skeleton; base bodies ~13 k triangles | **conflicting licences**; downloads through itch.io's per-session links (no stable URL); a CC0 GitHub mirror of the 2025-06-10 free pack exists (J-Ponzo/gltf-universal-animation-library) |
| KayKit Character Animations (Kay Lousberg) | itch.io page: "Creative Commons Zero v1.0 Universal" | 161 humanoid clips in the free tier, FBX and glTF, incl. tool work (digging, hammering; v1.1, 2025-12-10); `Rig_Medium`, `Rig_Large` | characters are fantasy (not used); bone count not verified; itch.io links not stable |
| Kenney Mini Characters 1.0 | CC0 (License.txt in the zip) | 12 people, 690–876 triangles, 32 clips | 7-bone cartoon rig, doesn't retarget: a placeholder at most |
| MakeHuman / MPFB2 (Blender) | "All core assets are shared under Creative Commons, CC0"; since 2020 an export is CC0 only if every asset in it was (static.makehumancommunity.org/about/license.html); asset packs are mixed CC0 and CC-BY | realistic adults; CC0 shirts, trousers, suits, shoes, gloves, glasses, and "helmets" (Hats 02, not industrial hard hats); rigs `game_engine` (53 bones), `default` (163) | active (MPFB v2.0.18, 2026-10-11); no CC0 coveralls, hi-vis or hard hats |
| Mixamo (Adobe) | not CC0; free for use, but not to distribute "the raw character and animation files" (Adobe FAQ as quoted 2022; the page refused our fetch) | | **excluded**: a public repository and packages distribute the files |
| CMU motion capture | "free for all uses … may not resell this data directly"; FAQ: "may be copied, modified, or redistributed" | thousands of raw BVH takes | not CC0; clean-up and retargeting work |
| Bandai Namco motion dataset, LAFAN1, 100STYLE | CC BY-NC 4.0; CC BY-NC-ND 4.0; CC BY 4.0 | | excluded (not CC0) |
| Godot | import-time retargeting to `SkeletonProfileHumanoid` (BoneMap, T-pose rest, rest fixer options) | | [D] retargeting_3d_skeletons; not yet tried on these rigs |

## Choice

- **Bodies:** MakeHuman/MPFB2 exports with CC0 assets only (bodies, skins, hair, the CC0 shirt, trouser, shoe,
  glove and glasses packs), the `game_engine` rig, eight bodies of mixed build and age, decimated to the
  budgets of 0064 (LOD0 ≤ 4,000 triangles); the hard hats are ours (below), not MakeHuman's. Made once in Blender (a
  tool, not shipped) by a recorded recipe (every
  MakeHuman setting and asset name, with each asset pack's licence checked as CC0 at export) and **committed** as
  glTF with that recipe and the licences in their entries of the about list, as the sounds are (0054 §7).
- **Work clothes and PPE are ours**, made by code like the kit (coveralls as the body's clothes with our own
  colours and reflective bands as material regions; hard hats, glasses, ear defenders, harness, radio, clipboard,
  tools and the calibrator as props on bone attachments): CC0 by authorship, neutral colours (the user's choice of
  2026-10-21).
- **Animations:** KayKit Character Animations (CC0), the clips we use **committed** as glTF after checking the
  licence file in the downloaded archive, retargeted at import to Godot's humanoid profile. Work poses no source
  has (a handwheel, a calibrator, typing at a desk, reading a gauge) are our own poses on the same profile, held or
  cycled, with Godot's skeleton modifiers for reach and gaze.
- **Fallback for milestone A1's first steps:** Kenney Mini Characters (CC0), until retargeting is shown to work.
- **Not used:** Mixamo (redistribution), Quaternius (licence conflict), mocap datasets that aren't CC0, except CMU's
  under the user's decision below.

## Decided by the user (2026-10-22)

- **KayKit (CC0) first**, with our own work poses.
- **CMU's motion capture is allowed** if KayKit and our own poses look too stiff: free, not CC0 ("free for all uses
  … may not resell this data directly", http://mocap.cs.cmu.edu/). Clips taken from it are committed like the others,
  each named in the about list, and its notice joins the app's About screen.
- Quaternius is not used (its pack pages say CC0, its licence page forbids redistribution).

**When to revisit:** A1's retargeting trial fails (then Kenney's rig and simpler clips, or the user's choice above);
MakeHuman's licence policy changes; Quaternius settles its licence back to CC0.
