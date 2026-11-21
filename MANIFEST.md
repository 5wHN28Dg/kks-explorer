# UX evidence for PR #471 (issue #447), round 3

Synthetic only: Walkdown Plant's invented plant. Made at branch commit 849642afc813153c98a2740f55777f25421565c3 by `apps/plant3d/tests/save_offer_shots.gd` under `tools/plant3d/bench/offscreen.sh` (headless mutter), Linux, Vulkan (Iris Xe), the switch forced on/off by the script.
Fixture: tests/fixtures/run-0.3.0.save sha256 1b7cded093fcd3f1db474810e4030492d8294d53f0d95db7d7c49707f0a00840 (written by plant-v0.3.0's own autosave, tools/plant3d/old_saves/).

- `before-main/`: the fixture on origin/main's offer code (released baseline), 1600x900.
- `1600x900/` (100 %), `1366x768-ui200/` (UI size 200 %), `2220x1080-phone/` (phone layout): off-old-release (switch off), on-old-release-offer, on-old-release-making-again (progress, Back focused), on-old-release-continued, on-cannot-continue, on-came-out-differently (an operated code this plant hasn't: listed before anything is replaced), on-copy-aside-failed, on-own-save, on-damaged.
- Not made: the accessibility tree (plant_a5.py, headless GNOME session; memory budget).

## sha256
```
a664a477fc91fe8212fe52d5bdce04f28699cf7aa39b7842421ca259dc2e7470  ./1366x768-ui200/desk_ui2_off-old-release.png
fb84c9ce08607cf3a3d60dea9199d45d580e71afbfaaa763dcb9466e52af9a75  ./1366x768-ui200/desk_ui2_on-came-out-differently.png
5504d27c82e06e9035d7c9ce3186daa22e40cc74f797c7398375cddb4448481a  ./1366x768-ui200/desk_ui2_on-cannot-continue.png
7fa6a8589ebd8f0512dc4b0cfa243f5f0f0192f40f13c272bcdd526e0763bfb6  ./1366x768-ui200/desk_ui2_on-copy-aside-failed.png
c1a7e7edb72d48b7425efbf8e81c17387e3252931298fc6cf0bf8e550f66b39b  ./1366x768-ui200/desk_ui2_on-damaged.png
3f9b6d4fc3c7fbce06bcb3e894771d43c6c1c29e4637155ecee2ad8d35a6a31e  ./1366x768-ui200/desk_ui2_on-old-release-continued.png
751eb04a588d237faba27ed83b174153e01f81e58bbe3f9f74ec43ee138ea42e  ./1366x768-ui200/desk_ui2_on-old-release-making-again.png
5fab93d59a91dee11749260ca639bc305d31c98809d34ab67879ea221123c818  ./1366x768-ui200/desk_ui2_on-old-release-offer.png
07054f9aa58586c52290e299f786160fa8543786c1447537dcdf074a32f8f960  ./1366x768-ui200/desk_ui2_on-own-save.png
01b9b11a242548b9e05b5edbc063c7d6906805cc4a1753d13bc3dc96f655685f  ./1600x900/desk_uidefault_off-old-release.png
a663c52ceedeb5653ff6f5afba3237b6be8bc873e98f6ffce2cc3dea2b966d5d  ./1600x900/desk_uidefault_on-came-out-differently.png
13cc4cc50f643a93ae5406512bca269789e4ffe832c947e508652908cfc3d594  ./1600x900/desk_uidefault_on-cannot-continue.png
2212f829909905bb52d9281c8b37b753fa8013f1a5fadd07be948512f9df0921  ./1600x900/desk_uidefault_on-copy-aside-failed.png
b19bb6cc6d8c00e60efcc6205be77b8aa2fa3218102fcc49f53ba04d73de63f9  ./1600x900/desk_uidefault_on-damaged.png
8b3ae5ea46ddecacdd3390e93b7fbda628c684dbc4cf33bc9a9e966985b27fee  ./1600x900/desk_uidefault_on-old-release-continued.png
19ccfd6dcdfcd6b505580128a3cd501ae255522dca1a5eed1c22383b7e0ed2e8  ./1600x900/desk_uidefault_on-old-release-making-again.png
d9d6f8ffaa4d35136a7e197017a6af7740480c4959a74afccf12e331f365fc0b  ./1600x900/desk_uidefault_on-old-release-offer.png
8171cd8afcc767315bfe862644f66d91d21cb53f7bffd3e5954e0c7a47b5465e  ./1600x900/desk_uidefault_on-own-save.png
2d35e4b320be8234ba96adec1020d75b4e173cf027e67cf5a8ad60d798806419  ./2220x1080-phone/phone_uidefault_off-old-release.png
b16d71f077d18f3630a7f7b0c80c2c5267db6343e71f2c25884b53cb0a4b2da3  ./2220x1080-phone/phone_uidefault_on-came-out-differently.png
89295fb66d06877e562f4509350da28344e5e1fc00797f36d519c293d354b38f  ./2220x1080-phone/phone_uidefault_on-cannot-continue.png
edc10d3b658bc7265d3ba8057f915319271a00f0b55bacbd5969162c948e162c  ./2220x1080-phone/phone_uidefault_on-copy-aside-failed.png
38fc5bf60406948c29d20b8ac032e83949830dc98eecdb77b0d762cce2a62e13  ./2220x1080-phone/phone_uidefault_on-damaged.png
9d04f6597c7481a9bbaf70bba4e2edb99a8fbf8189308a650d818602238988bb  ./2220x1080-phone/phone_uidefault_on-old-release-continued.png
daafe1679fbe8ae8ccdf94a2153db7c4bc71090412cadd165a9ba104f04b47dc  ./2220x1080-phone/phone_uidefault_on-old-release-making-again.png
8bfaaf33759c5e031f9073a5bf77ec1ba6e530d723a81f5a44bfd8a792e4006e  ./2220x1080-phone/phone_uidefault_on-old-release-offer.png
85b883a6b8580836b5d2e7abf0c1259d1064dc56026696d037ff9fea43e2051d  ./2220x1080-phone/phone_uidefault_on-own-save.png
f627948181c3ab8d59c9b9b9347fccbc229485f05cec9a2e53d1bbf8d646523c  ./before-main/desk_uidefault_main-old-release.png
```
