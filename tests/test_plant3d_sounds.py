"""Walkdown Plant's synthesised sounds (tools/plant3d/sounds/make_sounds.py; PLANT3D.md §11, FIRST-TRAIN.md §6,
decisions 0054 §7 and 0055):
- every sound the library names is made, with a voice (its physics and level), and every binding's sound exists;
- the generator is deterministic: the same library gives the same samples and the same Ogg bytes;
- loops are seamless at the loop point: sample continuity (step, curvature and linear-prediction residual no larger
  than anywhere inside) and no burst of energy above the sound's own frequencies around the seam, in the samples;
  after Vorbis, any tick at most CLICK_MAX_DB under the sound;
- the seam check itself catches a broken loop. It can for tones and for noise up to about 1.5 kHz; in noise reaching
  several kHz (steam, vent, rain) a jump at the seam can't be told from the noise itself, by any measure or by ear,
  and there the seamlessness rests on the construction (a loop made by one inverse FFT is periodic);
- levels: each sound at its planned A-weighted level, the plan within range and in a sensible order, no clipping;
  a motor's run-up ends at its loop's level;
- the physics: the strongest tone where the library puts it (blade passing, twice the grid frequency), noise in its
  band, blade and tooth passing as a rate;
- one-shots start and end silent; the total size is recorded against 0054's budget.

The Ogg tests need FFmpeg with libvorbis (0055): skipped without it, unless KKS_REQUIRE_FFMPEG=1 (CI), where a
missing FFmpeg fails."""
import glob, json, math, os, shutil, sys, tempfile, unittest

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d', 'sounds'))
import make_sounds as M  # noqa: E402

FS = M.FS
HAVE_FFMPEG = shutil.which('ffmpeg') is not None
REQUIRED = os.environ.get('KKS_REQUIRE_FFMPEG') == '1'
LIBRARY = json.load(open(os.path.join(ROOT, 'data', 'plant3d', 'sounds.json'), encoding='utf-8'))
SYNTH = {s['id']: s for s in LIBRARY['sounds'] if s['kind'] == 'synth'}
SEAM_CLICK_DB = -90         # the synthesised samples: nothing at the seam beyond rounding (a cut loop is > -45)
BUDGET_BYTES = 10_000_000   # 0054 §7: 10 MB for the sounds within the 150 MB package; these are far below


def need_ffmpeg(test):
    if not HAVE_FFMPEG and REQUIRED:
        raise AssertionError('KKS_REQUIRE_FFMPEG=1 but ffmpeg is not on PATH')
    if not HAVE_FFMPEG:
        test.skipTest('ffmpeg is not installed (0055); CI runs this with KKS_REQUIRE_FFMPEG=1')


top_hz = M.top_hz


def lpc_seam_ratio(x, order=32):
    """The largest residual of an order-32 linear predictor (fitted to the whole loop, circularly) over the samples
    whose prediction reaches across the seam, divided by the largest residual elsewhere. A jump that the signal's own
    spectrum can't explain stands out after the predictor has whitened the signal."""
    x = np.asarray(x, dtype=float)
    r = np.fft.irfft(np.abs(np.fft.rfft(x)) ** 2, len(x))[:order + 1]
    R = np.array([[r[abs(i - j)] for j in range(order)] for i in range(order)])
    a = np.linalg.solve(R + 1e-9 * r[0] * np.eye(order), r[1:order + 1])
    e = np.abs(x - sum(a[k] * np.roll(x, k + 1) for k in range(order)))
    return float(e[:order + 1].max() / max(e[order + 1:].max(), 1e-30))


def seam_problems(x, top):
    """What is wrong at the loop point of the loop x (an empty list when it is seamless):
    - continuity: the step, the curvature and the prediction residual across the seam are no larger than the largest
      inside the loop;
    - spectrum: no more energy above the layer's own frequencies around the seam than anywhere else in the loop
      (M.seam_click_db: a click is a broadband burst)."""
    out = []
    x = np.asarray(x, dtype=float)
    d = np.diff(np.concatenate([x, x[:1]]))           # d[-1] is the step across the seam
    if abs(d[-1]) > np.max(np.abs(d[:-1])) + 1e-9:
        out.append(f'step at the seam {abs(d[-1]):.4g} > largest inside {np.max(np.abs(d[:-1])):.4g}')
    c = np.roll(x, -1) - 2 * x + np.roll(x, 1)         # c[0] and c[-1] straddle the seam
    inner = np.max(np.abs(c[1:-1]))
    if max(abs(c[0]), abs(c[-1])) > inner + 1e-9:
        out.append(f'curvature at the seam {max(abs(c[0]), abs(c[-1])):.4g} > largest inside {inner:.4g}')
    r = lpc_seam_ratio(x)
    if r > 1:
        out.append(f'prediction residual at the seam {r:.2f} x the largest inside')
    click = M.seam_click_db(x, top)
    if click > SEAM_CLICK_DB:
        out.append(f'a click at the seam {click:.1f} dB under the sound (energy above its own frequencies)')
    return out


class Synthesis(unittest.TestCase):
    """The samples (NumPy only: always runs)."""

    @classmethod
    def setUpClass(cls):
        cls.made = {sid: M.make(s) for sid, s in SYNTH.items()}

    def test_every_sound_named_is_made(self):
        bound = set()
        for path in glob.glob(os.path.join(ROOT, 'data', 'plant3d', 'model', '*.json')):
            for b in json.load(open(path, encoding='utf-8')).get('bind', []):
                if 'sound' in b:
                    bound.add(b['sound'])
        self.assertTrue(bound, 'the model binds no sound: the test reads the wrong files')
        self.assertLessEqual(bound, set(SYNTH), 'a binding names a sound the library does not make')
        self.assertEqual(set(M.VOICES), set(SYNTH), 'a voice without a sound, or a sound without a voice')
        for sid, (layers, plan, loop) in self.made.items():
            self.assertTrue(layers, sid)
            self.assertTrue(M.VOICES[sid]['why'], sid)
            if loop:
                self.assertIn('noise' if 'noise' in SYNTH[sid] else 'tones', layers, sid)
        # the electrical hum is the only layer the app doesn't pitch, and it holds only multiples of 2 x 50 Hz
        for sid, v in M.VOICES.items():
            self.assertTrue(all(h % 100 == 0 for h in v.get('mains', ())), sid)
        # the sounds FIRST-TRAIN §6 and the task name, beyond the bindings
        for sid in ('breaker', 'breaker_open', 'motor_start', 'horn_p1', 'horn_p2', 'horn_p3', 'horn_ack',
                    'valve_motor', 'transformer_hum', 'gen_hum', 'gt_whine', 'turbine_hum', 'steam_vent'):
            self.assertIn(sid, self.made)

    def test_deterministic_samples(self):
        for sid, s in SYNTH.items():
            again, _, _ = M.make(s)
            for k, x in self.made[sid][0].items():
                self.assertTrue(np.array_equal(M.pcm16(x), M.pcm16(again[k])), f'{sid}.{k}')

    def test_loops_are_seamless(self):
        for sid, (layers, _, loop) in self.made.items():
            if not loop:
                continue
            for k, x in layers.items():
                with self.subTest(sound=sid, layer=k):
                    seconds = M.NOISE_SECONDS if k == 'noise' else M.TONE_SECONDS
                    self.assertEqual(len(x), seconds * FS)
                    self.assertEqual(seam_problems(M.pcm16(x) / 32767, top_hz(SYNTH[sid], k)), [])

    def test_the_seam_check_catches_a_broken_loop(self):
        for sid, k in (('transformer_hum', 'mains'), ('exhaust_rumble', 'noise'), ('valve_motor', 'tones'),
                       ('motor_large', 'tones'), ('combustion', 'noise'), ('burner', 'noise'),
                       ('liquid_ring', 'noise'), ('turning_gear', 'noise'), ('fan_large', 'noise')):
            x = self.made[sid][0][k]
            self.assertEqual(seam_problems(x, top_hz(SYNTH[sid], k)), [], sid)
            for cut in (37, 101, 1003):         # the loop's end cut short: the waveform jumps at the seam
                with self.subTest(sound=sid, cut=cut):
                    self.assertNotEqual(seam_problems(x[:-cut], top_hz(SYNTH[sid], k)), [])
                    # and the decoded files' looser bound (below) would refuse it too

    def test_levels(self):
        plans = {}
        for sid, (layers, plan, loop) in self.made.items():
            plans[sid] = plan
            if 'match' not in M.VOICES[sid]:
                self.assertAlmostEqual(plan, M.level_plan(M.VOICES[sid]['spl']))
            self.assertTrue(-44 <= plan <= -26, f'{sid}: {plan} dBFS(A) is outside -44..-26')
            ms = sum(M.power(M.pcm16(x) / 32767, loop) for x in layers.values())
            self.assertAlmostEqual(10 * math.log10(ms), plan, delta=0.1, msg=sid)
            for k, x in layers.items():
                self.assertLessEqual(np.max(np.abs(x)), M.PEAK_MAX, f'{sid}.{k} peaks above -1 dBFS')
        # a sensible order: what is louder on site (in dB(A)) is louder here, in the same weighting
        self.assertEqual(max(plans, key=plans.get), 'steam_vent')
        loops = {k: v for k, v in plans.items() if self.made[k][2]}
        self.assertEqual(min(loops, key=loops.get), 'valve_motor')
        for loud, quiet in (('gt_whine', 'motor_large'), ('motor_large', 'motor_small'), ('gen_hum', 'transformer_hum'),
                            ('motor_small', 'valve_motor'), ('horn_p1', 'horn_p2'), ('horn_p2', 'horn_p3'),
                            ('combustion', 'exhaust_rumble'), ('exhaust_rumble', 'turning_gear'),
                            ('transformer_hum', 'valve_motor'), ('combustion', 'motor_small')):
            self.assertGreater(plans[loud], plans[quiet], f'{loud} should be louder than {quiet}')
        # the run-up hands over to its loop without a jump: its last second at the loop's level
        x = self.made['motor_start'][0]['once']
        tail = x[int(6.0 * FS):int(7.0 * FS)]
        self.assertAlmostEqual(M.level(tail, False), plans['motor_large'], delta=0.1)

    def test_level_meter(self):
        """IEC 61672's A weighting: 0 dB at 1 kHz, -19.1 dB at 100 Hz, -2.5 dB at 10 kHz; a full-scale 1 kHz sine
        reads -3.01 dBFS(A)."""
        a = 20 * np.log10(M.a_weighting(np.array([1000.0, 100.0, 10000.0, 31.5])))
        self.assertTrue(np.allclose(a, [0.0, -19.1, -2.5, -39.4], atol=0.15), a)
        t = np.arange(FS) / FS
        self.assertAlmostEqual(M.level(np.sin(2 * np.pi * 1000 * t)), -3.01, delta=0.02)

    def test_strongest_tone_is_the_declared_one(self):
        for sid, (layers, _, loop) in self.made.items():
            if not loop:
                continue
            mains = M.VOICES[sid].get('mains', ())
            for k in ('mains', 'tones'):
                if k not in layers:
                    continue
                steady = [z for z in SYNTH[sid]['tones'] if z['hz'] >= M.RATE_HZ and (z['hz'] in mains) == (k == 'mains')]
                want = max(steady, key=lambda z: z.get('gain', 1))['hz']
                x = layers[k]
                got = np.fft.rfftfreq(len(x), 1 / FS)[np.argmax(np.abs(np.fft.rfft(x)))]
                self.assertAlmostEqual(got, want, delta=0.5, msg=f'{sid}.{k}')

    def test_physics_of_the_tones(self):
        # the compressor's blade-pass frequency: 57 blades at 3,000 rpm
        self.assertEqual(max(SYNTH['gt_whine']['tones'], key=lambda z: z['gain'])['hz'], 57 * 3000 / 60)
        # electrical machines hum at twice the 50 Hz grid frequency and its harmonics
        for sid in ('transformer_hum', 'gen_hum'):
            hz = [z['hz'] for z in SYNTH[sid]['tones']]
            self.assertEqual(hz[0], 100, sid)
            self.assertTrue(all(h % 100 == 0 for h in hz), sid)
        # a 12-pulse converter's currents are 12k +/- 1 of 50 Hz; its magnetic parts buzz at the sums and differences
        # (force ~ current squared): even multiples of 50 Hz, none of the odd current harmonics themselves
        hz = {z['hz'] for z in SYNTH['sfc_whine']['tones']}
        self.assertLessEqual({600, 1200, 500, 700, 1100, 1300}, hz)
        self.assertTrue(all(h % 100 == 0 for h in hz), hz)
        # motor slot whine: rotor slots x the speed the model turns the shaft at, with sidebands at +/- 2 x 50 Hz
        shaft = {}
        for path in glob.glob(os.path.join(ROOT, 'data', 'plant3d', 'model', '*.json')):
            for b in json.load(open(path, encoding='utf-8')).get('bind', []):
                if b.get('anim') == 'shaft':
                    shaft[b['kks']] = b['scale']
        cw, ccw = shaft['30PAC10AP001'], shaft['00PGC10AP001']      # a CW pump (motor_large), a CCW pump (motor_small)
        slot_l, slot_s = 90 * cw, 44 * ccw
        large = {z['hz'] for z in SYNTH['motor_large']['tones']}
        small = {z['hz'] for z in SYNTH['motor_small']['tones']}
        self.assertLessEqual({slot_l, slot_l - 100, slot_l + 100, 6 * cw}, large)
        self.assertTrue(any(abs(h - slot_s) < 0.5 for h in small), (slot_s, small))
        self.assertTrue(any(abs(h - 11 * ccw) < 0.5 for h in small), (11 * ccw, small))
        # the large motor is lower than the small one: its slot whine and its vane passing
        self.assertLess(min(z['hz'] for z in SYNTH['motor_large']['tones']),
                        min(z['hz'] for z in SYNTH['motor_small']['tones']))

    def test_noise_in_its_band(self):
        for sid, (layers, _, loop) in self.made.items():
            v = M.VOICES[sid]
            if not loop or 'noise' not in layers or v.get('rates') == 'clicks' or 'drops' in v:
                continue
            lo, hi = SYNTH[sid]['noise']['band']
            x = layers['noise']
            p = np.abs(np.fft.rfft(x)) ** 2
            f = np.fft.rfftfreq(len(x), 1 / FS)
            inside = p[(f >= lo / 2) & (f <= hi * 2)].sum() / p.sum()
            self.assertGreater(inside, 0.9, f'{sid}: {inside:.2f} of the noise power in {lo / 2}-{hi * 2} Hz')

    def test_rates_are_heard_as_rates(self):
        """Tones below 30 Hz are blade or tooth passing: the noise's envelope repeats at that rate."""
        for sid, rate in (('fan_large', 16), ('turning_gear', 8), ('liquid_ring', 25)):
            x = self.made[sid][0]['noise']
            env = x * x
            spec = np.abs(np.fft.rfft(env - env.mean()))
            f = np.fft.rfftfreq(len(env), 1 / FS)
            near = spec[(f > 2) & (f < 60)]
            peak = f[(f > 2) & (f < 60)][np.argmax(near)]
            # the strongest envelope component is the rate, or for the gurgle one of its halves and multiples
            self.assertTrue(any(abs(peak - rate * m) < 0.2 for m in (0.5, 1, 1.5, 2)), f'{sid}: {peak} Hz')

    def test_one_shots_start_and_end_silent(self):
        for sid, (layers, _, loop) in self.made.items():
            if loop:
                continue
            x = layers['once']
            self.assertEqual(x[0], 0, sid)
            self.assertLess(np.max(np.abs(x[-int(0.001 * FS):])), 1e-3, sid)
            self.assertGreater(np.max(np.abs(x)), 0.01, sid)   # not silent: peaks above -40 dBFS
        # the motor's run-up: the 100 Hz inrush growl at the start is well above the hum at speed
        x = self.made['motor_start'][0]['once']

        def hum(a):    # the 100 Hz component of the second from a
            return np.abs(np.fft.rfft(x[int(a * FS):int(a * FS) + FS]))[100]
        self.assertGreater(hum(0.5), 2 * hum(5.9))

    def test_a_tone_that_follows_a_value(self):
        """A tone whose hz follows a value gets its own layer at the table's highest frequency (the app pitches it)."""
        s = {'id': 'probe', 'kind': 'synth', 'tones': [{'hz': {'of': 'speed', 'table': [[0, 0], [1, 1234.5]]}}]}
        layers = M.render_loop(s, {})
        self.assertEqual(list(layers), ['tone0'])
        x = layers['tone0']
        self.assertEqual(len(x), M.TONE_SECONDS * FS)
        f = np.fft.rfftfreq(len(x), 1 / FS)[np.argmax(np.abs(np.fft.rfft(x)))]
        self.assertAlmostEqual(f, 1234.5, delta=0.01)
        self.assertEqual(seam_problems(x, 1234.5), [])

    def test_a_voice_needs_whole_cycles(self):
        with self.assertRaises(ValueError):
            M.whole(16.3, M.NOISE_SECONDS, 'x')
        bad = dict(SYNTH['fan_large'], noise=None)
        del bad['noise']
        with self.assertRaises(ValueError):    # a 16 Hz rate with no noise to carry it
            M.render_loop(bad, M.VOICES['fan_large'])


class Vorbis(unittest.TestCase):
    """The Ogg Vorbis files the app plays (FFmpeg's libvorbis, 0055)."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='plant3d-sounds-')
        cls.index = None
        if HAVE_FFMPEG:
            cls.index = M.build(os.path.join(cls.tmp, 'a'))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def setUp(self):
        need_ffmpeg(self)

    def read(self, name, d='a'):
        with open(os.path.join(self.tmp, d, name), 'rb') as f:
            return f.read()

    def test_same_bytes_twice(self):
        again = M.build(os.path.join(self.tmp, 'b'))
        self.assertEqual(again, self.index)
        names = sorted(os.listdir(os.path.join(self.tmp, 'a')))
        self.assertEqual(names, sorted(os.listdir(os.path.join(self.tmp, 'b'))))
        for name in names:
            self.assertEqual(self.read(name, 'a'), self.read(name, 'b'), name)

    def test_index_lists_every_sound(self):
        idx = json.loads(self.read('index.json'))
        self.assertEqual(idx['format'], 'walkdown-plant-sound-files')
        self.assertEqual(idx['rate'], FS)
        self.assertEqual(set(idx['sounds']), set(SYNTH))
        for sid, e in idx['sounds'].items():
            self.assertEqual(e['loop'], 'once' not in M.VOICES[sid], sid)
            for la in e['layers']:
                self.assertTrue(os.path.isfile(os.path.join(self.tmp, 'a', la['file'])), la['file'])
                self.assertEqual(self.read(la['file'])[:4], b'OggS', la['file'])
                self.assertEqual(la['pitch'], la['layer'] != 'mains', la['file'])

    def test_decoded_loops_are_seamless_and_levelled(self):
        for sid, e in self.index['sounds'].items():
            ms = 0.0
            for la in e['layers']:
                x = M.decode(self.read(la['file']))
                with self.subTest(file=la['file']):
                    self.assertEqual(len(x), la['samples'], 'decoded length')
                    self.assertLess(np.max(np.abs(x)), 0.99, 'clips after Vorbis')
                    if e['loop']:
                        # Vorbis's error at the stream's end and at its start are independent, so the samples
                        # can't be continuous to the bit across the seam as the synthesis is; the click this
                        # leaves must be at least CLICK_MAX_DB under the sound (the generator searched for it)
                        click = M.seam_click_db(x, top_hz(SYNTH[sid], la['layer']))
                        self.assertLessEqual(click, M.CLICK_MAX_DB)
                        self.assertEqual(round(click, 1), la['click_db'])
                ms += M.power(x, e['loop'])
            self.assertAlmostEqual(10 * math.log10(ms), e['level'], delta=0.5, msg=sid)

    def test_size(self):
        total = self.index['bytes']
        self.assertEqual(total, sum(os.path.getsize(os.path.join(self.tmp, 'a', la['file']))
                                    for e in self.index['sounds'].values() for la in e['layers']))
        self.assertLess(total, BUDGET_BYTES)
        print(f'\nWalkdown Plant sounds: {len(self.index["sounds"])} sounds, {total / 1e6:.2f} MB of Ogg Vorbis',
              file=sys.stderr)


if __name__ == '__main__':
    unittest.main()
