# Evidence for PR #445 (the minimum GPU message), synthetic only

- scripts' commit: bf44f58699eb66d76aefff0a7adc53c1ae1ab411 (branch plant-min-gpu)
- desktop: tools/plant3d/bench/offscreen.sh $GODOT --path apps/plant3d --resolution WxH --script res://tests/min_gpu_shots.gd -- --out=DIR [--pseudo], WxH in 640x360, 1600x900, 2560x1440 (UI sizes 100/150/200 %: the window shrinks by the title bar's height above 100 %); Godot 4.7.2, Mesa Iris Xe, Forward+ (the message's look does not depend on the renderer)
- a11y: Plant run from the worktree with --rendering-method gl_compatibility --accessibility always and a temporary override.cfg turning the switch on, in apps/gnome/e2e/headless.sh; AT-SPI walked (script kept at ~/.cache/agent-tmp/min-gpu/a5/a5.py, not tracked); 'before' = unticked, 'nodes' = after an AT-SPI click on the check box
- laptop: the owner's Windows 10 laptop (Intel HD 4400, driver 10.18.15.4248), an unbaked headless export of commit 5d35e712 (before the switch: always on), real fallback to Compatibility through ANGLE/D3D11; screen captured with apps/windows/e2e/shot.cpp, cropped to the window; Enter sent to the window

| file | sha256 |
|---|---|
| ./a11y/at-spi-linux-compat.json | a3db7fc8c15ec061e1431f78c8a03b09969bc9abda09f6166aa786c083b78d53 |
| ./desktop/min-gpu-1600x863-150.png | 64c615883f5a937217d4ce97ebf8c3acfc71a2e3cba5da741f8d94d5736dd55c |
| ./desktop/min-gpu-1600x863-150-pseudo.png | 1e06c6167eb2dfb91bf876b26830a06b7c04cf5aa7b29515421eec632accea95 |
| ./desktop/min-gpu-1600x863-200.png | b1b8fd76f2e1507a0f3b62fa52bc9bd39b127095350639b399455a6bd50ce231 |
| ./desktop/min-gpu-1600x863-200-pseudo.png | ce987719435bd915dbcf0fa928ba9ccde08fed76c213602f0798b55e259ef3cf |
| ./desktop/min-gpu-1600x863-200-pseudo-words-pagedown.png | fd7acf4b3928badae41eba6231c86a2ff21d8ab629ce3faf9bf966ed4bde845b |
| ./desktop/min-gpu-1600x863-200-words-pagedown.png | 7472d20a2217644a26668cdf4c8a8191a0c9fb0a933a7c654b40d73972dbda25 |
| ./desktop/min-gpu-1600x900-100.png | 68926fd92e33e5068ddeab4c6fb9a01563e52d48037124bbae89173d48e63b94 |
| ./desktop/min-gpu-1600x900-100-pseudo.png | 2518e02b1eb5b53c7083354ffa0d0ee2f46c2c1b90b99038b91ecf009659d155 |
| ./desktop/min-gpu-1600x900-100-pseudo-tab1.png | db868cb0ccd4ad5d3f6a0efb1f724e7cefabec79a172fe1188a7d2a7324b74ec |
| ./desktop/min-gpu-1600x900-100-pseudo-tab2.png | d489694e82a8747fceac017cce4b81993e2a3024b6db28ad02eb28e7a6c019ab |
| ./desktop/min-gpu-1600x900-100-pseudo-ticked.png | e18ea4231d513650e20e7fc77e4a34805d363287e3a8d5103c0f19d75443ac8c |
| ./desktop/min-gpu-1600x900-100-tab1.png | d9c2819cca84fd263c758661e482f2f62bc8f6f76491305bc22e17bbf5a08564 |
| ./desktop/min-gpu-1600x900-100-tab2.png | b810d98e093625fd876c36a38da040e87b3eb13de9e87322204b981a2ba6730b |
| ./desktop/min-gpu-1600x900-100-ticked.png | 3e0a7116701a83a1d5bb181c2174ce62ce80efe86f525190d63d58549da4c8fc |
| ./desktop/min-gpu-2560x1403-150.png | cfc7bcded490f88fad2f12be709bb07a272f3ca71467b0a3c7be0c82a549112f |
| ./desktop/min-gpu-2560x1403-150-pseudo.png | ac7aa2d29d7b994a948d416c732e7180318f115e7803dd44e5ad16824dbff03e |
| ./desktop/min-gpu-2560x1403-200.png | f20d82e2ff8ece854cfccecad83c086b2b7d0a3cb5bb2fe5710e6848d7e80b63 |
| ./desktop/min-gpu-2560x1403-200-pseudo.png | fa1c2f2d0e4dd51b20e7aa6a37f791113ef70a6570b1a75dfb739b8e0a151463 |
| ./desktop/min-gpu-2560x1403-200-pseudo-words-pagedown.png | 9501890b11307d4b6a07125c82f3b5507969f7a9e8e34a4b674469ba33815cf3 |
| ./desktop/min-gpu-2560x1403-200-words-pagedown.png | 290b7f7ce98cd16ec6085f7da81e6f5a120b4cfa16db7926da1fb48a0891168f |
| ./desktop/min-gpu-2560x1440-100.png | ef03441b22e32f150a021a3f0b559f724e0e8d10cb0f161212de979bde1503be |
| ./desktop/min-gpu-2560x1440-100-pseudo.png | 9aa7d1283fd08211285ee417161664f8be9a486657ec7f55162a9ee179026a6c |
| ./desktop/min-gpu-2560x1440-100-pseudo-tab1.png | bdc63d7930851448fc87db188df6b897c06197a2025114f0976b9ca93ccb2e7c |
| ./desktop/min-gpu-2560x1440-100-pseudo-tab2.png | d98bc5ec2803c08e875a8963cfb663fcfe82b86bc20b5d6712175b58a736107e |
| ./desktop/min-gpu-2560x1440-100-pseudo-ticked.png | 22ef220cd8050c6977057f4197016e7fa5d732b7c6f7fa1a96c6abc904f9a93c |
| ./desktop/min-gpu-2560x1440-100-tab1.png | c27af67e0e6849ac69f5fa451a962940b87a6f452e413a0559cf868b7e498a8e |
| ./desktop/min-gpu-2560x1440-100-tab2.png | b6440fafa7dffb5459e9c2999291d3dd606add3667b38cd5f68b1bf8d7b3f525 |
| ./desktop/min-gpu-2560x1440-100-ticked.png | 9a351062e00cb779ff83bec8261f18174bf90fae4ddb5311219d6b1334dee532 |
| ./desktop/min-gpu-640x323-150.png | 5d66ec90b1f03c43c02b50aa4f5381152b358daed62b2f36a78adf785927f3d6 |
| ./desktop/min-gpu-640x323-150-pseudo.png | c800887ca0e6eedba59d299fb8209573f00b65b97d4952fd92dbff469a9fa8da |
| ./desktop/min-gpu-640x323-200.png | d45b743cd7dba9f16a9a362376567f1043b3935c990893b3442a1a4a4fe8cc7d |
| ./desktop/min-gpu-640x323-200-pseudo.png | 3f7b4bd27a18b175f3fb5e6f73a80f84dec0770e3b11856b116cda0e671a7b91 |
| ./desktop/min-gpu-640x323-200-pseudo-words-pagedown.png | 0d01aafb163d52b109a682b38a47d34eb399df2c0208b82886135d5ce56b74cf |
| ./desktop/min-gpu-640x323-200-words-pagedown.png | eed945299b523bbbbb0d1388986c5a3a6f2b513be8720cccbe07cbbc5bf7f910 |
| ./desktop/min-gpu-640x360-100.png | e504e3e3c06d2861c57c6e2cd8c7346039ac0e761c3266324696778b04485755 |
| ./desktop/min-gpu-640x360-100-pseudo.png | 4cd0cb1d3fcee5d15816c0487a2920717c20bd71c6e2cb9df5dc98b1804896f4 |
| ./desktop/min-gpu-640x360-100-pseudo-tab1.png | 864e49b2ee31109f2e4b074cf83ed40082e6aea21a014e8e03d7596e9f776146 |
| ./desktop/min-gpu-640x360-100-pseudo-tab2.png | 7a0bd8a34e20c3af5b35d3a994ea19859c731db44a80dd6867526d290d832eb8 |
| ./desktop/min-gpu-640x360-100-pseudo-ticked.png | 0359d21b58c2e50792a609b9f27685682e127d7715b77973b77c8a29bd7dfb0d |
| ./desktop/min-gpu-640x360-100-tab1.png | 83cb433b5d5339cf803b9306ea97048d252ad898f74a9405c840e091673a977a |
| ./desktop/min-gpu-640x360-100-tab2.png | c8a85cf3b878d6c81e0294ba6abd4234f60f6024bc2a3f87c84a2fe8ee225ce2 |
| ./desktop/min-gpu-640x360-100-ticked.png | db4ecf24dbf00e37318647c1cc532ef93326d771976b9f79b3c148dbf6e4fd44 |
| ./laptop/win10-hd4400-shot1-message.png | ca0ec351e6368a66cbf97ccac30e0fdd53731991bbc916c6fc1421fdb184bb12 |
| ./laptop/win10-hd4400-shot2-after-continue.png | 64bc5cf6e2d58e742d4366a09ae9a46430222eeabdd89a216190f624ae6f9cbe |
