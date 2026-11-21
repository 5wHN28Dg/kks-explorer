# UX evidence for PR #467 (issue #443), round 2

Synthetic only: Walkdown Plant's invented plant. Branch commit 6c3c64282006836e05f87398a2374f9a8d4eabd3 (the videos were made at cb4dd6f5; weather_view.gd's code is the same since apart from comments and ending a flash with its run).

## IRIS (decision 0077): EA's IRIS at d96978ac, built in user space, default appsettings.json (here)
- `iris-defaults/`: the defaults as they are (pattern detection off). `iris-patterns-on/`: the same videos with `-p 1` (pattern detection on). Videos: Godot Movie Maker, 960x540, fixed 60 fps, `flash_capture.gd --movie`; not stored (400-800 MB each), sha256 below. `storm-60x-60s-main` is the same capture with origin/main's weather_view.gd.

### Pattern detection on
```
storm-1x-120s.avi: Pass, 7393 frames (00:02:03.216003); most luminance transitions in a second 2, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.216; warning/fail frames 0; pattern fail frames 0
storm-1x-60s-soft.avi: Pass, 3793 frames (00:01:03.216000); most luminance transitions in a second 1, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.125; warning/fail frames 0; pattern fail frames 0
storm-60x-60s.avi: Pass, 3790 frames (00:01:03.166000); most luminance transitions in a second 2, red 0; largest flash area 97.7 %; largest frame-to-frame mean luminance change 0.218; warning/fail frames 0; pattern fail frames 0
storm-60x-60s-main.avi: Fail, 3793 frames (00:01:03.216000); most luminance transitions in a second 8, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.218; warning/fail frames 1335; pattern fail frames 0
storm-60x-60s-soft.avi: Pass, 3793 frames (00:01:03.216000); most luminance transitions in a second 1, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.125; warning/fail frames 0; pattern fail frames 0
```
Pattern area and detected lines are 0 in every frame of every video.

```
20b610c27993fcf6276318d2a3baa0376c03a4a1fcce462aec15e9a86a47fdf9  storm-1x-120s.avi
e0359fea1acffc2e853a8fb3bb5c17d278bcd552863afc3058b02754e2585aa3  storm-1x-60s-soft.avi
17bb7680f5d232d8ad1e221edaf59892246a64ac6d95f40b0c727b869c011d98  storm-60x-60s.avi
4decc0f9f43a8ce937c86831796080ce6fe4e36b36a526fe464bc767c207f4f0  storm-60x-60s-main.avi
98ff11ec7442dd666f284c819be5cb017e5ea749a997b20b71a71acee879afaa  storm-60x-60s-soft.avi
```

## Settings: the Reduced motion row (`tests/reduced_motion_shots.gd`)
Images as captured (the window's client area): desk_uidefault 1600x863 (100 %), desk_ui2 1366x731 (UI size 200 %), phone_uidefault 2220x1043 (phone layout, its default 150 %); each scrolled to the row and ticked by the keyboard.

## sha256 of the files here
```
9b9bbaec85c3c0a04a16d12e1c71299fe58797c42f4b24a04f6489d69b541572  ./appsettings.json
16ad55b47596961ff47723884f3f85aef3c140be9d4ca52dd92a1d1555f1d2c8  ./iris-defaults/storm-1x-120s/framedata.csv
0963f40176af6d177a39dc64ca6accd50d82da820ca2ba0421c1199cba2e1660  ./iris-defaults/storm-1x-120s/result.json
904fb48798aca0cdfe5511fbd9bd0d8482e474fbad5d84497ff3ca332a46b392  ./iris-defaults/storm-1x-60s-soft/framedata.csv
f9fbf927df6095dd021dff2e2bf8f52d540b38415bb04dbb1cf2e0024dffdd76  ./iris-defaults/storm-1x-60s-soft/result.json
99f2becd91e8ce3f4898e65995b0691a5215f891254a503ee0a3def8a8a399c7  ./iris-defaults/storm-60x-60s/framedata.csv
46b8a245acec84568c0c3b51d29462e94807fef3f381d2b3a8c49db79a51814b  ./iris-defaults/storm-60x-60s-main/framedata.csv
b2e03b463f25c063bf33285f47e01c49212ca6cc104ee70982ab69ab22dbd5e1  ./iris-defaults/storm-60x-60s-main/result.json
90393fe4e57f0350b5fb7bd687f801ba3b7868e250ee269ec7dfa319b64f94cd  ./iris-defaults/storm-60x-60s/result.json
a5dab598c4a9e76a18dd22f368c737c755d40b4369886948c3eb1f4cc1f98787  ./iris-defaults/storm-60x-60s-soft/framedata.csv
a1e8266426f1cd81c6a2a339363968385f5159c15a21390a941e8a1fe2ed96c5  ./iris-defaults/storm-60x-60s-soft/result.json
16ad55b47596961ff47723884f3f85aef3c140be9d4ca52dd92a1d1555f1d2c8  ./iris-patterns-on/storm-1x-120s/framedata.csv
641e8c1098c3fc6ad4cacefed7d95076923ae5f83642a40ef55d21aeeffc7c50  ./iris-patterns-on/storm-1x-120s/result.json
904fb48798aca0cdfe5511fbd9bd0d8482e474fbad5d84497ff3ca332a46b392  ./iris-patterns-on/storm-1x-60s-soft/framedata.csv
efb048d8197e5f8a7bce0f7d084eab250a897ebb6fc751ab5469f73dbc631f96  ./iris-patterns-on/storm-1x-60s-soft/result.json
99f2becd91e8ce3f4898e65995b0691a5215f891254a503ee0a3def8a8a399c7  ./iris-patterns-on/storm-60x-60s/framedata.csv
46b8a245acec84568c0c3b51d29462e94807fef3f381d2b3a8c49db79a51814b  ./iris-patterns-on/storm-60x-60s-main/framedata.csv
11019147b82b0c03e74b1aad339cbbd306c87933305811305a37b6c6d99e3eb2  ./iris-patterns-on/storm-60x-60s-main/result.json
d9d8ddfe5a31e588cc07ca6cf2b06a8a63c3bfe839da905eb54daf0c2e092191  ./iris-patterns-on/storm-60x-60s/result.json
a5dab598c4a9e76a18dd22f368c737c755d40b4369886948c3eb1f4cc1f98787  ./iris-patterns-on/storm-60x-60s-soft/framedata.csv
a4019d26c30848d7cefb4991fb591682136811f5f318055c941715b75e1aae6e  ./iris-patterns-on/storm-60x-60s-soft/result.json
9dd091a013a33c2495521c43c3cedf9a7cdf1093b64e6ae4cbc58a9046e5e566  ./settings/desk_ui2_reduced_motion.png
7ba24d5aba2c79d842ea1a901541e35ec93e06bd6afde41190981157cdc358e4  ./settings/desk_ui2_reduced_motion_ticked.png
8f45804057823e5196a248c36aa23244915cbfba53848f10199bdee2a617f597  ./settings/desk_uidefault_reduced_motion.png
dd5368618ded3e638b3d8ca8032101dff6763dbc40c9bc21ab2188aca060e202  ./settings/desk_uidefault_reduced_motion_ticked.png
e84178106ec09c4b3bb85753646fbf03b39e8278e9485e36f868eb912c2caffa  ./settings/phone_uidefault_reduced_motion.png
b87a6610a697d57ad6540a8f91af62d49f7ea1210128f5fa6ffa50dab189571c  ./settings/phone_uidefault_reduced_motion_ticked.png
```
