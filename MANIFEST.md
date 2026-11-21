# UX evidence for PR #471 (issue #447)

Synthetic only: Walkdown Plant's invented plant; the save is tests/fixtures/run-0.3.0.save (written by plant-v0.3.0's autosave).
Made by `apps/plant3d/tests/save_offer_shots.gd` under `tools/plant3d/bench/offscreen.sh` (a private headless mutter),
at commit of branch plant-save-survives, Linux, Vulkan (Iris Xe).

| Folder | Window | UI size |
|---|---|---|
| 1600x900 | 1600 × 900 | default (100 %) |
| 1366x768-ui200 | 1366 × 768 | 200 % (the largest) |
| 2220x1080-phone | 2220 × 1080 | phone layout (density 420 default, as the Note 9) |

Shots in each: `off-old-release` (switch off: the baseline, plant-v0.3.0's refusal; note the panel no longer runs off
the screen, a fix that is always on), `on-old-release-offer`, `on-old-release-continued` (the toast naming the kept file),
`on-cannot-continue` (kept aside with its reason), `on-own-save` (this build's save: New run's new line), `on-damaged`.
Not shot: the "Making the run again: N %" progress line (the 0.3.0 run is made again within one frame's slice).
