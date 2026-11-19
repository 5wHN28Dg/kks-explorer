# Evidence for PR #445 (the minimum GPU message), synthetic only

- scripts' commit: 66bdb49432f545af90d79ad695653c1becf15de8 (branch plant-min-gpu); desktop renders and the AT-SPI tree remade at this commit (the message's final wording)
- desktop: tools/plant3d/bench/offscreen.sh $GODOT --path apps/plant3d --resolution WxH --script res://tests/min_gpu_shots.gd -- --out=DIR [--pseudo], WxH in 640x360, 1600x900, 2560x1440 (UI sizes 100/150/200 %: the window shrinks by the title bar's height above 100 %); Godot 4.7.2, Mesa Iris Xe, Forward+ (the message's look does not depend on the renderer)
- a11y: Plant run from the worktree with --rendering-method gl_compatibility --accessibility always and a temporary override.cfg turning the switch on, in apps/gnome/e2e/headless.sh; AT-SPI walked (script kept at ~/.cache/agent-tmp/min-gpu/a5/a5.py, not tracked); 'before' = unticked, 'nodes' = after an AT-SPI click on the check box
- laptop: the owner's Windows 10 laptop (Intel HD 4400, driver 10.18.15.4248), an unbaked headless export of commit 5d35e712 (before the switch: always on), real fallback to Compatibility through ANGLE/D3D11; screen captured with apps/windows/e2e/shot.cpp, cropped to the window; Enter sent to the window

- windows-vm: the kks-win10 VM (no GPU; Godot run with --rendering-method gl_compatibility --accessibility always, which goes through ANGLE on D3D11 on Microsoft Basic Render Driver), an unbaked headless export of 66bdb494 with override.cfg turning the switch on; virsh screenshot cropped above the taskbar; Enter sent to the window (log: 'the message is shown', 'continued', first frame drawn). File names carry each shot's real window size.
- a11y/uia-windows10-compat.txt: the UIA tree (raw view) of the final build in the kks-win10 VM while the message was up (System.Windows.Automation from the desktop session, apps/windows/e2e/runapp.ps1); run with --accessibility always
- speed/: the speed class's walk (2026-11-19, commit 5e897e16 plus the bake): the Linux release-style export (`build.sh bake`, then a headless export), `offscreen.sh walkdown-plant.x86_64 --resolution 1600x900 -- --quality=full --walk=frames --seconds=600` at XH_SIZE=1600x900@60 with an empty Godot data folder; gpu_clients.py before and 5 minutes in

| file | sha256 |
|---|---|
| ./a11y/at-spi-linux-compat.json | 929a65f388db36aa7590a2ffc289bd669ada14c07aa700fe35004b9792381e3e |
| ./a11y/uia-windows10-compat.txt | 56b7cfc74296fe4efa267dc3af481b3daf60695e320a753c5db255d2af45feff |
| ./desktop/min-gpu-1600x863-100-pseudo-ticked.png | 4cc783f13e6a780ad8ddbfbc6e81fa56c6f2a19f8f76731351b233095504678a |
| ./desktop/min-gpu-1600x863-100-ticked.png | 26b7f4d811aa56b4992e361bd5fb467689068b585f70cee42b453885a2926117 |
| ./desktop/min-gpu-1600x863-150-pseudo.png | c6e0546df9622e6804c05c0c3ec5869c49796858b01b04859c3147019945329f |
| ./desktop/min-gpu-1600x863-150.png | 40a25d9c294091253b33b72ca8ae0841ebc2cd963c8150b06dd929e18e49a7a5 |
| ./desktop/min-gpu-1600x863-200-pseudo-words-pagedown.png | af256379df6167031ec72f9e3890a2c98fbec1e0a74dea09259219b9688a8a1b |
| ./desktop/min-gpu-1600x863-200-pseudo.png | 2b64207d6d4c263c630b718cb2d442647519630fcf8971a6467dbb4f0112cade |
| ./desktop/min-gpu-1600x863-200-words-pagedown.png | c5877e05084c3dd0b0e54c5c1181ea411bd3202248c5c1b109814b1bc886725a |
| ./desktop/min-gpu-1600x863-200.png | 678cf52217717dc3ed7c37699af45c87e46520c42cab5fc996565b28fd38f3bb |
| ./desktop/min-gpu-1600x900-100-pseudo-tab1.png | 5b84e6a82a7449576e0102be5c6c3020d940de9e91c261548ededed1eb52d634 |
| ./desktop/min-gpu-1600x900-100-pseudo-tab2.png | e7176836d0973e7dad76ee4e6d58f8bb11ab46e1933d1b1e07b79eeb82d5001a |
| ./desktop/min-gpu-1600x900-100-pseudo.png | 0eec690fd18d65afe9cd4c9eb5ab0caeeaf5951eded25128726e0862378b02d2 |
| ./desktop/min-gpu-1600x900-100-tab1.png | 98e5662348fdc1f416ee24831d611507b9989b27642df2eeea2904c9c8409de3 |
| ./desktop/min-gpu-1600x900-100-tab2.png | 2315d84bbe8ff2a54051016116e550f8ab56d348b16b5f47cb57b89e7a5c7e57 |
| ./desktop/min-gpu-1600x900-100.png | 8f5a054aa0f5b0bb87356c1dff19fdc54391725e5760bb2f4f41ad3841c8773b |
| ./desktop/min-gpu-2560x1403-100-pseudo-tab1.png | 6e1f605a44bbdeef220f816a3adaee36d17a6c6031557eae2e2be9f12f30c3d2 |
| ./desktop/min-gpu-2560x1403-100-pseudo-tab2.png | 6903e74aa3b1fca6068b752765c0f8a592db6e8a24baf4f38a69e21383ccb28c |
| ./desktop/min-gpu-2560x1403-100-pseudo-ticked.png | a69b125d8d9a950d52ad280697afedd8d4389d74af04b35122f77f7ac79733e2 |
| ./desktop/min-gpu-2560x1403-100-tab2.png | 425660421b681a8412cc63d6cfb2e58b28ea951a2e3f1605d6951f7d096b5d39 |
| ./desktop/min-gpu-2560x1403-100-ticked.png | 9b1ceec787e5a69e66d046b8f9d9e550ecbe26ddd3842392f441199f3baa964e |
| ./desktop/min-gpu-2560x1403-150-pseudo.png | 7863726606a4c49bb6266e9771abad28ccd39f6c2e756843df8b841bcd60b707 |
| ./desktop/min-gpu-2560x1403-150.png | ba2269cdc58acdc80535bd4ebd9c0c6e5a272cc0ddb293a2f6b7d5d50eac583c |
| ./desktop/min-gpu-2560x1403-200-pseudo-words-pagedown.png | f2a65e325c03400f0ef401e39e8965aaca4d8f41210512a1404b9fdb24233a16 |
| ./desktop/min-gpu-2560x1403-200-pseudo.png | 2e7d8429429e4e42fcfe2a789193e10604c31ec41b4c341fc8dacc1d193db007 |
| ./desktop/min-gpu-2560x1403-200-words-pagedown.png | 2e4cbdb2a802e7100e64af2f8778f84ab1c5fc117396a7d2536e7ea21d549364 |
| ./desktop/min-gpu-2560x1403-200.png | 5657e76c39fadf1a947fbad4551963091614ec32d0b216bd1d2197cf0bf69687 |
| ./desktop/min-gpu-2560x1440-100-pseudo.png | f475803ca7a746e2c0211d8224d202d060a0715ed576474088e68761eeaa8b7e |
| ./desktop/min-gpu-2560x1440-100-tab1.png | c900e23837817115eae32508a4e0822d119a4ff101b874dbff0f36fe9b639d58 |
| ./desktop/min-gpu-2560x1440-100.png | bf66522ed066ff8c7e756cc7d25f1ab0c3070cec1f9702394ac2c2e1fcffa552 |
| ./desktop/min-gpu-640x323-100-tab2.png | ec258bc1fd60a703071e1d3678c833c7a0d305ad1335de8672280e1d6e1e5bb2 |
| ./desktop/min-gpu-640x323-100-ticked.png | 8d26c8812bbec7d9a8c05f86d33f51ddd33208d37c330be14329b75b46681202 |
| ./desktop/min-gpu-640x323-150.png | 7b2f355fc7a5893cde98f99434bd0f1e2f57d02b91da7ddde438cc6b35883cf5 |
| ./desktop/min-gpu-640x323-200-pseudo-words-pagedown.png | d8ed53a205ea8034192dabe38ce4563086b020d017ce6d04437bbfe05648c884 |
| ./desktop/min-gpu-640x323-200-words-pagedown.png | 3a8617fd7f67743b2c434d8d7a82136b899961f000c4bfc84f1bae16f486ccd7 |
| ./desktop/min-gpu-640x323-200.png | 765f489c5ef3238319b1e49ac66d9717a19fea184491f8a8a0fc3bfe1877c6f4 |
| ./desktop/min-gpu-640x360-100-pseudo-tab1.png | db9e6da9d5868a9f68151ac3c7be77dcd397840a3480a84175bea80890c08168 |
| ./desktop/min-gpu-640x360-100-pseudo-tab2.png | 8f7e372d63dc3608137111b7519ad113cf420251f92eade6df7f8cd38b0b358a |
| ./desktop/min-gpu-640x360-100-pseudo-ticked.png | ac28134886e34f51e3019071540b879e4fc409b809a9d5131cdfc8a3722aa41c |
| ./desktop/min-gpu-640x360-100-pseudo.png | d5173fd0c8c07864a6bf3d3c7ae6dcb3cdbdda4f26faadeb6525c98e0ce6a568 |
| ./desktop/min-gpu-640x360-100-tab1.png | e6798f7acde4268cbdf37b3a8bb87af1b20a0fb8d5f9e6e7b229cac121eed7b7 |
| ./desktop/min-gpu-640x360-100.png | 7ca6dd40f4ed97066c66028744b1abfe9b5b23a622b76919bdb550d9e81195e2 |
| ./desktop/min-gpu-640x360-150-pseudo.png | c1630a1f5a302732dec9807c5d9257e248ed811e971f09f117f8408758b8f8c7 |
| ./desktop/min-gpu-640x360-200-pseudo.png | f391897a9a3a0142c4f14a38c1e0f9499841f9d134dde3575aaa1fb1525dce13 |
| ./laptop/win10-hd4400-shot1-message.png | ca0ec351e6368a66cbf97ccac30e0fdd53731991bbc916c6fc1421fdb184bb12 |
| ./laptop/win10-hd4400-shot2-after-continue.png | 64bc5cf6e2d58e742d4366a09ae9a46430222eeabdd89a216190f624ae6f9cbe |
| ./speed/gpu-before.txt | 6a97a2e61bf7431d3d8aeb367f79231e232322be32532370e19798de02b52338 |
| ./speed/gpu-during.txt | c8b71666f65ed0b5e17aae74c231ac4e7f3c43ffc5395c40372720edb51c0217 |
| ./speed/result.txt | a5f5e05e6388f55a155e2b1bba0c7cecb37d1c052116de4a50521a6adbdec315 |
| ./windows-vm/win10-after-continue.png | 3d4365647d596df0bbe724c787294925b90400adcf2538cf187124b1b07530c4 |
| ./windows-vm/win10-message.png | 9f6b2f53d6bfa405ec844a26f836d8554257f74c1d9126eb32187959ac6513f8 |
