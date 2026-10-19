"""Walkdown Plant's synthesised sounds (tools/plant3d/sounds/make_sounds.py; PLANT3D.md §11, FIRST-TRAIN.md §6,
decisions 0054 §7 and 0055):
- every sound the library names is made, with a voice (its physics and level), and every binding's sound exists;
- the generator is deterministic: the same library gives the same samples and the same Ogg bytes;
- loops are seamless at the loop point: sample continuity (step, curvature and linear-prediction residual no larger
  than anywhere inside) and no burst of energy above the sound's own frequencies around the seam, in the samples;
  after Vorbis, any tick (measured on the codec's error against the samples it was made from) at most CLICK_MAX_DB
  under the sound, and a tick of half the sound's RMS refused where the measure can see one;
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


def read_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


LIBRARY = read_json(os.path.join(ROOT, 'data', 'plant3d', 'sounds.json'))
SYNTH = {s['id']: s for s in LIBRARY['sounds'] if s['kind'] == 'synth'}
SEAM_CLICK_DB = -90         # the synthesised samples: nothing at the seam beyond rounding
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
      (M.seam_click_db at twice the loudest window elsewhere: a click is a broadband burst)."""
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
    click = M.seam_click_db(x, top, factor=2)   # twice the loudest window elsewhere: rarely by chance (a rumble can reach 2.3 x)
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
            for b in read_json(path).get('bind', []):
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
            declared = {z['hz'] for z in SYNTH[sid].get('tones', []) if isinstance(z['hz'], (int, float))}
            self.assertLessEqual(set(v.get('mains', ())), declared, f'{sid}: a mains tone the library does not declare')
        # the sounds FIRST-TRAIN §6 and the task name, beyond the bindings
        for sid in ('breaker', 'breaker_open', 'motor_start', 'horn_p1', 'horn_p2', 'horn_p3', 'horn_ack',
                    'valve_motor', 'transformer_hum', 'gen_hum', 'gt_whine', 'turbine_hum', 'steam_vent',
                    'step_concrete', 'step_grating', 'step_stair', 'door_slide', 'door_roller', 'wind',
                    'plant_distant'):
            self.assertIn(sid, self.made)
        # the app plays these by name (apps/plant3d/ui/sound_player.gd): one-shots and loops as it expects
        for sid in ('step_concrete', 'step_grating', 'step_stair', 'door_slide'):
            self.assertFalse(self.made[sid][2], f'{sid} is a one-shot')
        for sid in ('door_roller', 'wind', 'plant_distant'):
            self.assertTrue(self.made[sid][2], f'{sid} loops')

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
                    seconds = M.loop_seconds(sid, k)
                    self.assertEqual(len(x), seconds * FS)
                    self.assertEqual(seam_problems(M.pcm16(x) / 32767, top_hz(SYNTH[sid], k)), [])

    def test_a_seamless_loop_passes_wherever_it_starts(self):
        """The seam check doesn't fail a seamless loop by chance: every loop layer, started at 16 other points. (A
        sounder's onset landing on the seam window would read as a click: the voices keep onsets off the seam.)"""
        for sid, (layers, _, loop) in self.made.items():
            if not loop:
                continue
            for k, x in layers.items():
                y = M.pcm16(x) / 32767
                for j in range(1, 17):
                    with self.subTest(sound=sid, layer=k, start=j):
                        self.assertEqual(seam_problems(np.roll(y, -(j * len(y) // 17)), top_hz(SYNTH[sid], k)), [])

    def test_the_seam_check_catches_a_broken_loop(self):
        for sid, k in (('transformer_hum', 'mains'), ('exhaust_rumble', 'noise'), ('valve_motor', 'tones'),
                       ('motor_large', 'tones'), ('combustion', 'noise'), ('burner', 'noise'),
                       ('liquid_ring', 'noise'), ('turning_gear', 'noise'), ('fan_large', 'noise')):
            x = self.made[sid][0][k]
            self.assertEqual(seam_problems(x, top_hz(SYNTH[sid], k)), [], sid)
            for cut in (37, 101, 1003):         # the loop's end cut short: the waveform jumps at the seam
                with self.subTest(sound=sid, cut=cut):
                    self.assertNotEqual(seam_problems(x[:-cut], top_hz(SYNTH[sid], k)), [])

    def test_levels(self):
        plans = {}
        for sid, (layers, plan, loop) in self.made.items():
            plans[sid] = plan
            if 'match' not in M.VOICES[sid]:
                self.assertAlmostEqual(plan, M.level_plan(M.VOICES[sid]['spl']))
            else:
                self.assertNotIn('spl', M.VOICES[sid], f'{sid}: levelled by match, an spl would be ignored')
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
        # (measured against the loop's own samples, not the plan the generator levelled it to)
        x = self.made['motor_start'][0]['once']
        tail = x[int(6.0 * FS):int(6.95 * FS)]
        loop = 10 * math.log10(sum(M.power(y) for y in self.made['motor_large'][0].values()))
        self.assertAlmostEqual(10 * math.log10(np.mean(M.a_weighted(tail, False)[int(0.05 * FS):] ** 2)), loop, delta=0.5)

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
            for b in read_json(path).get('bind', []):
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

    def test_footsteps_by_surface(self):
        """A footstep is two impacts (heel, then toe); concrete is a dull thump that is over at once, steel rings:
        grating higher, a stair tread lower and longer. Each starts at the heel, not after a silence."""
        def ring_time(x):         # how long the step's sound stays within 30 dB of its peak (10 ms envelope)
            env = np.sqrt(np.convolve(x * x, np.ones(441) / 441, 'same'))
            return np.flatnonzero(env > env.max() * 10 ** (-30 / 20))[-1] / FS

        def centroid(x):
            p = np.abs(np.fft.rfft(x)) ** 2
            return float((np.fft.rfftfreq(len(x), 1 / FS) * p).sum() / p.sum())
        steps = {sid: self.made[sid][0]['once'] for sid in ('step_concrete', 'step_grating', 'step_stair')}
        for sid, x in steps.items():
            env = np.abs(x)
            first = np.flatnonzero(env > env.max() * 0.1)[0] / FS
            self.assertLess(first, 0.015, f'{sid}: the heel strikes at once')
            # the toe: a second burst 80-90 ms after the heel
            seg = lambda a, b: float(np.max(env[int(a * FS):int(b * FS)]))
            self.assertGreater(seg(0.085, 0.11), 3 * seg(0.07, 0.085) if sid == 'step_concrete' else 0, sid)
        self.assertLess(ring_time(steps['step_concrete']), ring_time(steps['step_grating']))
        self.assertLess(ring_time(steps['step_grating']), ring_time(steps['step_stair']))
        self.assertGreater(centroid(steps['step_grating']), centroid(steps['step_stair']))
        # louder on steel than on concrete, as heard on site
        self.assertLess(self.made['step_concrete'][1], self.made['step_grating'][1])

    def test_ambience(self):
        """The wind blows in gusts over a 16 s loop (its envelope's slowest swell is the loop's 1/16 Hz); the
        distant plant is a low roar under the grid's hum."""
        x = self.made['wind'][0]['noise']
        self.assertEqual(len(x), 16 * FS)
        env = np.array([np.sqrt(np.mean(x[i:i + FS // 4] ** 2)) for i in range(0, len(x), FS // 4)])
        self.assertGreater(env.max() / env.min(), 2.5, 'gusts: the wind rises and falls')
        layers = self.made['plant_distant'][0]
        self.assertEqual(set(layers), {'mains', 'noise'})
        p = np.abs(np.fft.rfft(layers['noise'])) ** 2
        f = np.fft.rfftfreq(len(layers['noise']), 1 / FS)
        self.assertGreater(p[f < 700].sum() / p.sum(), 0.95, 'far away, little is left above 700 Hz')

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


class HearingProtection(unittest.TestCase):
    """FIRST-TRAIN §6: a hearing-protection sign at the doors of loud areas, as on site. A building is loud where a
    machine bound inside it sounds at 85 dB(A) or more at 1 m (its voice's `spl`; the upper exposure action value of
    EU Directive 2003/10/EC); each of its doors has the sign beside it, facing out, and no quiet building's door has
    one."""
    LOUD = 85

    def test_signs_at_the_doors_of_loud_buildings(self):
        bound = {}
        for path in glob.glob(os.path.join(ROOT, 'data', 'plant3d', 'model', '*.json')):
            for b in read_json(path).get('bind', []):
                if 'sound' in b and 'once' not in M.VOICES[b['sound']]:
                    bound[b['kks']] = max(bound.get(b['kks'], 0), M.VOICES[b['sound']]['spl'])

        def inside(p, poly):
            c = False
            for i in range(len(poly)):
                (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
                if (y1 > p[1]) != (y2 > p[1]) and p[0] < x1 + (p[1] - y1) * (x2 - x1) / (y2 - y1):
                    c = not c
            return c

        def on_edge(p, poly):
            for i in range(len(poly)):
                a, b = np.array(poly[i], float), np.array(poly[(i + 1) % len(poly)], float)
                t = np.clip(np.dot(p - a, b - a) / np.dot(b - a, b - a), 0, 1)
                if np.linalg.norm(a + t * (b - a) - p) < 0.1:
                    return True
            return False
        loud_doors, quiet_doors = 0, 0
        for path in sorted(glob.glob(os.path.join(ROOT, 'data', 'plant3d', 'areas', '*.json'))):
            a = read_json(path)
            things = []

            def walk(e):
                things.append(e)
                for c in e.get('parts', []):
                    walk(c)
            for e in a['equipment']:
                walk(e)
            signs = [g for g in a['signs'] if g['text'] == 'Hearing protection required']
            for b in (x for x in a['structures'] if x['part'] == 'building'):
                poly = [[b['at'][0] + q[0], b['at'][1] + q[1]] for q in b['params']['outline']]
                spl = max([bound.get(e['kks'], 0) for e in things if 'at' in e and inside(e['at'], poly)] + [0])
                for d in (x for x in a['structures'] if x['part'] == 'door' and on_edge(np.array(x['at'][:2], float), poly)):
                    near = [g for g in signs if math.dist(g['at'][:2], d['at'][:2]) < 4.0]
                    with self.subTest(area=a['id'], building=b['id'], door=d['id'], spl=spl):
                        if spl >= self.LOUD:
                            loud_doors += 1
                            self.assertEqual(len(near), 1, 'a loud building\'s door has one hearing-protection sign')
                            self.assertEqual(near[0]['yaw'], d.get('yaw', 0), 'the sign faces out, as the door does')
                            self.assertTrue(on_edge(np.array(near[0]['at'][:2], float), poly), 'on the wall')
                            self.assertTrue(1.5 <= near[0]['at'][2] <= 2.2, 'at eye height')
                        else:
                            quiet_doors += 1
                            self.assertEqual(near, [], 'a quiet building\'s door has no hearing-protection sign')
        # the first train: the GT hall, the turbine hall, the CW pump house and the boiler house are loud (six
        # doors); the control building is quiet
        self.assertEqual((loud_doors, quiet_doors), (6, 1))


class Vorbis(unittest.TestCase):
    """The Ogg Vorbis files the app plays (FFmpeg's libvorbis, 0055)."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='plant3d-sounds-')
        cls.index = None
        cls.made = {sid: M.make(s) for sid, s in SYNTH.items()}
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
                        # measured on the codec's error against the samples it was made from, rotated as stored
                        ref = np.roll(M.pcm16(self.made[sid][0][la['layer']]), -la['rotation']) / 32767
                        click = M.seam_click_db(x, top_hz(SYNTH[sid], la['layer']), ref=ref)
                        self.assertLessEqual(click, M.CLICK_MAX_DB)
                        self.assertEqual(round(click, 1), la['click_db'])
                        # and the bound refuses a real tick there (one sample off by half the sound's RMS) where
                        # the measure can see one: tones, and noise up to 1.2 kHz. In noise reaching several kHz
                        # Vorbis's own error is as rough sample to sample as a tick of 1-2 x RMS (and as inaudible)
                        top = top_hz(SYNTH[sid], la['layer'])
                        if la['layer'] != 'noise' or top <= 1200:
                            ticked = x.copy()
                            ticked[0] += 0.5 * np.sqrt(np.mean(ref * ref))
                            self.assertGreater(M.seam_click_db(ticked, top, ref=ref), M.CLICK_MAX_DB)
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
