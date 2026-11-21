# UX evidence for PR #471 (issue #447), round 2

Synthetic only: Walkdown Plant's invented plant. Made at branch commit a920be82a418bbbc405a72dddb11c7eab0011f56 by `apps/plant3d/tests/save_offer_shots.gd` under `tools/plant3d/bench/offscreen.sh` (headless mutter), Linux, Vulkan (Iris Xe), the switch forced on/off by the script.
Fixture: tests/fixtures/run-0.3.0.save sha256 1b7cded093fcd3f1db474810e4030492d8294d53f0d95db7d7c49707f0a00840 (written by plant-v0.3.0's own autosave, tools/plant3d/old_saves/).

- `before-main/`: the same fixture on origin/main's offer code (the released baseline: autosave.gd and run_save.gd unchanged from main in that checkout), 1600x900: the panel runs off the screen (fixed here, always on).
- `1600x900/` (100 %), `1366x768-ui200/` (UI size 200 %), `2220x1080-phone/` (phone layout): off-old-release (switch off), on-old-release-offer, on-old-release-making-again (progress line, slice forced small; New run holds the focus Continue had), on-old-release-continued, on-cannot-continue, on-made-again-refused (made again, then refused: New run focused), on-copy-aside-failed (Replace it focused), on-own-save, on-damaged.
- Not made: the accessibility tree (plant_a5.py under a headless GNOME session; not run, memory budget).

## sha256
```
a664a477fc91fe8212fe52d5bdce04f28699cf7aa39b7842421ca259dc2e7470  ./1366x768-ui200/desk_ui2_off-old-release.png
5504d27c82e06e9035d7c9ce3186daa22e40cc74f797c7398375cddb4448481a  ./1366x768-ui200/desk_ui2_on-cannot-continue.png
7fa6a8589ebd8f0512dc4b0cfa243f5f0f0192f40f13c272bcdd526e0763bfb6  ./1366x768-ui200/desk_ui2_on-copy-aside-failed.png
c1a7e7edb72d48b7425efbf8e81c17387e3252931298fc6cf0bf8e550f66b39b  ./1366x768-ui200/desk_ui2_on-damaged.png
1cf129fe4c4c57d2434eb8b958217fab0718acd11f79001582f97b1e217c7813  ./1366x768-ui200/desk_ui2_on-made-again-refused.png
3f9b6d4fc3c7fbce06bcb3e894771d43c6c1c29e4637155ecee2ad8d35a6a31e  ./1366x768-ui200/desk_ui2_on-old-release-continued.png
1fecdede7c05ed7cc68393693e6d20adb79abe6770c066146a603895d6963dc0  ./1366x768-ui200/desk_ui2_on-old-release-making-again.png
5fab93d59a91dee11749260ca639bc305d31c98809d34ab67879ea221123c818  ./1366x768-ui200/desk_ui2_on-old-release-offer.png
5d7e41943128fb9f3dc391ed06ba9ddc26a54012e2f45e0b32a9022f873dd6c5  ./1366x768-ui200/desk_ui2_on-own-save.png
01b9b11a242548b9e05b5edbc063c7d6906805cc4a1753d13bc3dc96f655685f  ./1600x900/desk_uidefault_off-old-release.png
13cc4cc50f643a93ae5406512bca269789e4ffe832c947e508652908cfc3d594  ./1600x900/desk_uidefault_on-cannot-continue.png
2212f829909905bb52d9281c8b37b753fa8013f1a5fadd07be948512f9df0921  ./1600x900/desk_uidefault_on-copy-aside-failed.png
b19bb6cc6d8c00e60efcc6205be77b8aa2fa3218102fcc49f53ba04d73de63f9  ./1600x900/desk_uidefault_on-damaged.png
8e2393387611a1bdf1b0fc9fe79e8a17d57b57ede294a2415916ad03908e6934  ./1600x900/desk_uidefault_on-made-again-refused.png
8b3ae5ea46ddecacdd3390e93b7fbda628c684dbc4cf33bc9a9e966985b27fee  ./1600x900/desk_uidefault_on-old-release-continued.png
de97e74da8adbdc132d77ba03f2ca7a44927b137a07359fd69969d0015952c8a  ./1600x900/desk_uidefault_on-old-release-making-again.png
d9d6f8ffaa4d35136a7e197017a6af7740480c4959a74afccf12e331f365fc0b  ./1600x900/desk_uidefault_on-old-release-offer.png
fbbbcbfcdf079114aed1d40acb61c658f0939f7c4ef00ce22092aa0c58a15db7  ./1600x900/desk_uidefault_on-own-save.png
2d35e4b320be8234ba96adec1020d75b4e173cf027e67cf5a8ad60d798806419  ./2220x1080-phone/phone_uidefault_off-old-release.png
89295fb66d06877e562f4509350da28344e5e1fc00797f36d519c293d354b38f  ./2220x1080-phone/phone_uidefault_on-cannot-continue.png
edc10d3b658bc7265d3ba8057f915319271a00f0b55bacbd5969162c948e162c  ./2220x1080-phone/phone_uidefault_on-copy-aside-failed.png
38fc5bf60406948c29d20b8ac032e83949830dc98eecdb77b0d762cce2a62e13  ./2220x1080-phone/phone_uidefault_on-damaged.png
d58002a1aa83b455eee7fe82b7672dda670831cc3199322821d40185d4f95bf5  ./2220x1080-phone/phone_uidefault_on-made-again-refused.png
9d04f6597c7481a9bbaf70bba4e2edb99a8fbf8189308a650d818602238988bb  ./2220x1080-phone/phone_uidefault_on-old-release-continued.png
fefdb9188733745bc84af890e64af9ff626423690bdc95a35e6e399308d0f278  ./2220x1080-phone/phone_uidefault_on-old-release-making-again.png
8bfaaf33759c5e031f9073a5bf77ec1ba6e530d723a81f5a44bfd8a792e4006e  ./2220x1080-phone/phone_uidefault_on-old-release-offer.png
7223f989b5eae4cded4fdc09be2b198683419a552357683470b2505f9cd4d8da  ./2220x1080-phone/phone_uidefault_on-own-save.png
f627948181c3ab8d59c9b9b9347fccbc229485f05cec9a2e53d1bbf8d646523c  ./before-main/desk_uidefault_main-old-release.png
```
