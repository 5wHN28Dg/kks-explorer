# UX evidence for PR #467 (issue #443)

Synthetic only: Walkdown Plant's invented plant. Branch commit 22122e5f080c019ba93f768a3685c15dec2a2e15.

## IRIS (decision 0077): EA's IRIS at d96978ac, built in user space, default appsettings.json (copied here)
Videos: Godot Movie Maker, 960x540, 60 fps fixed (each frame 1/60 s of the player's time), `apps/plant3d/tests/flash_capture.gd --movie`, scenario cold_iron at 01:00 with the weather fixed at a thunderstorm, the trainee flying 30 m up looking down. Not stored here (about 400-800 MB each); their sha256 below. `storm-60x-60s-main` is the same capture with origin/main's app/weather_view.gd (before this PR).

```
storm-1x-120s.avi: Pass, 7393 frames (00:02:03.216003); most luminance transitions in a second 2, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.216; warning/fail frames 0; pattern fail frames 0
storm-1x-60s-soft.avi: Pass, 3793 frames (00:01:03.216000); most luminance transitions in a second 1, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.125; warning/fail frames 0; pattern fail frames 0
storm-60x-60s.avi: Pass, 3790 frames (00:01:03.166000); most luminance transitions in a second 2, red 0; largest flash area 97.7 %; largest frame-to-frame mean luminance change 0.218; warning/fail frames 0; pattern fail frames 0
storm-60x-60s-main.avi: Fail, 3793 frames (00:01:03.216000); most luminance transitions in a second 8, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.218; warning/fail frames 1335; pattern fail frames 0
storm-60x-60s-soft.avi: Pass, 3793 frames (00:01:03.216000); most luminance transitions in a second 1, red 0; largest flash area 100.0 %; largest frame-to-frame mean luminance change 0.125; warning/fail frames 0; pattern fail frames 0

storm-1x-120s.avi Pass luminance {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0} red {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0}
storm-1x-60s-soft.avi Pass luminance {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0} red {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0}
storm-60x-60s.avi Pass luminance {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0} red {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0}
storm-60x-60s-main.avi Fail luminance {'ExtendedFailFrames': 38, 'FlashFailFrames': 35, 'PassWithWarningFrames': 1262, 'TotalFailedFrames': 73} red {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0}
storm-60x-60s-soft.avi Pass luminance {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0} red {'ExtendedFailFrames': 0, 'FlashFailFrames': 0, 'PassWithWarningFrames': 0, 'TotalFailedFrames': 0}

20b610c27993fcf6276318d2a3baa0376c03a4a1fcce462aec15e9a86a47fdf9  storm-1x-120s.avi
e0359fea1acffc2e853a8fb3bb5c17d278bcd552863afc3058b02754e2585aa3  storm-1x-60s-soft.avi
17bb7680f5d232d8ad1e221edaf59892246a64ac6d95f40b0c727b869c011d98  storm-60x-60s.avi
4decc0f9f43a8ce937c86831796080ce6fe4e36b36a526fe464bc767c207f4f0  storm-60x-60s-main.avi
98ff11ec7442dd666f284c819be5cb017e5ea749a997b20b71a71acee879afaa  storm-60x-60s-soft.avi
```
The only luminance transition in the Reduced motion videos is at 0.033 s (the app's first frame: the sky to the plant), not the lightning.

## Settings: the Reduced motion row (`apps/plant3d/tests/reduced_motion_shots.gd`)
desk_uidefault (1600x900, 100 %), desk_ui2 (1366x768, UI size 200 %), phone_uidefault (2220x1080 phone layout, its default 150 %): the row scrolled into view, and ticked by the keyboard (Space with the focus on it: ticked true in all three).

## sha256 of the files here
```
9b9bbaec85c3c0a04a16d12e1c71299fe58797c42f4b24a04f6489d69b541572  ./iris/appsettings.json
16ad55b47596961ff47723884f3f85aef3c140be9d4ca52dd92a1d1555f1d2c8  ./iris/storm-1x-120s/framedata.csv
0963f40176af6d177a39dc64ca6accd50d82da820ca2ba0421c1199cba2e1660  ./iris/storm-1x-120s/result.json
904fb48798aca0cdfe5511fbd9bd0d8482e474fbad5d84497ff3ca332a46b392  ./iris/storm-1x-60s-soft/framedata.csv
f9fbf927df6095dd021dff2e2bf8f52d540b38415bb04dbb1cf2e0024dffdd76  ./iris/storm-1x-60s-soft/result.json
99f2becd91e8ce3f4898e65995b0691a5215f891254a503ee0a3def8a8a399c7  ./iris/storm-60x-60s/framedata.csv
46b8a245acec84568c0c3b51d29462e94807fef3f381d2b3a8c49db79a51814b  ./iris/storm-60x-60s-main/framedata.csv
b2e03b463f25c063bf33285f47e01c49212ca6cc104ee70982ab69ab22dbd5e1  ./iris/storm-60x-60s-main/result.json
90393fe4e57f0350b5fb7bd687f801ba3b7868e250ee269ec7dfa319b64f94cd  ./iris/storm-60x-60s/result.json
a5dab598c4a9e76a18dd22f368c737c755d40b4369886948c3eb1f4cc1f98787  ./iris/storm-60x-60s-soft/framedata.csv
a1e8266426f1cd81c6a2a339363968385f5159c15a21390a941e8a1fe2ed96c5  ./iris/storm-60x-60s-soft/result.json
9dd091a013a33c2495521c43c3cedf9a7cdf1093b64e6ae4cbc58a9046e5e566  ./settings/desk_ui2_reduced_motion.png
7ba24d5aba2c79d842ea1a901541e35ec93e06bd6afde41190981157cdc358e4  ./settings/desk_ui2_reduced_motion_ticked.png
8f45804057823e5196a248c36aa23244915cbfba53848f10199bdee2a617f597  ./settings/desk_uidefault_reduced_motion.png
dd5368618ded3e638b3d8ca8032101dff6763dbc40c9bc21ab2188aca060e202  ./settings/desk_uidefault_reduced_motion_ticked.png
e84178106ec09c4b3bb85753646fbf03b39e8278e9485e36f868eb912c2caffa  ./settings/phone_uidefault_reduced_motion.png
b87a6610a697d57ad6540a8f91af62d49f7ea1210128f5fa6ffa50dab189571c  ./settings/phone_uidefault_reduced_motion_ticked.png
```
