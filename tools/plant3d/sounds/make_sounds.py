#!/usr/bin/env python3
"""Synthesise Walkdown Plant's sounds (docs/PLANT3D.md §11, docs/plant3d/FIRST-TRAIN.md §6, decisions 0054 §7 and
0055) from the sound library data/plant3d/sounds.json into Ogg Vorbis files, at build time.

    python3 tools/plant3d/sounds/make_sounds.py [--out DIR] [--wav]

DIR defaults to apps/plant3d/built/sounds (the app's build output). It gets one file per layer and `index.json`
(format `walkdown-plant-sound-files`), which tells the app each sound's layers, whether they loop, and how a layer's
pitch follows a value. `--wav` writes 16-bit WAV files instead (for listening without Vorbis; not for the app).

How a sound is made:
- the library declares each synth sound's spectrum: `tones` (hz, gain) and a `noise` band (colour, band, gain);
- VOICES below gives what the declaration can't: the physics behind it (`why`), its level at 1 m (`spl`, dB(A)),
  and its time structure (modulation, clicks, patterns, or a one-shot event);
- a loop is periodic by construction: every tone has a whole number of cycles in the loop (frequencies are multiples
  of 1 / its length), the noise is made in the frequency domain and transformed back (inherently periodic), every
  modulation rate is a multiple of 1 / the loop's length, and anything that rings past the end (a click's decay)
  wraps around to the start. So the loop point is like any other sample;
- layers: `mains` (an electrical hum at multiples of 2 x the 50 Hz grid frequency: the app doesn't pitch it with
  the machine's speed), `tones` (the other steady tones), `tone<i>` (a tone whose frequency follows a value: played at `ref_hz`, the app
  sets pitch = hz(value) / ref_hz), `noise` (the band noise, plus tones below 30 Hz, which are a rate, not a pitch:
  blade passes, gear teeth, a liquid ring's churn, rendered as modulation or clicks of the noise), or `once` for
  one-shot events (breakers, a motor's run-up, the acknowledge tone). The app applies the binding's gain to every
  layer of a sound and its pitch to every layer but `mains`;
- levels: each sound's A-weighted level in dBFS (the same weighting as its dB(A) figure) is set from its typical
  sound pressure level at 1 m, compressed by half around the loudest: level = -26 - 0.5 * (105 - spl). One-shots by
  their loudest 400 ms, loops over the whole loop. The layers of a sound share one scale, so the declared gains keep
  their balance. A one-shot that hands over to a loop (`match`) is levelled so that its end matches that loop.

Deterministic: the noise comes from NumPy's PCG64 seeded by the sound's and layer's names, and the encoder runs
bit-exact (0055): the same library gives the same bytes on the same machine.
"""
import argparse, hashlib, json, math, os, shutil, struct, subprocess, sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
LIBRARY = os.path.join(ROOT, 'data', 'plant3d', 'sounds.json')
OUT = os.path.join(ROOT, 'apps', 'plant3d', 'built', 'sounds')

FS = 44100              # Godot's default mix rate: no resampling at playback
TONE_SECONDS = 2        # tone layers: every tone and pattern repeats exactly in 2 s
NOISE_SECONDS = 8       # noise layers: long enough that the repeat of the noise isn't heard as a pattern
RATE_HZ = 30            # a declared tone below this is a rate (blade or tooth passing), not a pitch
VORBIS_QUALITIES = (4, 6, 8)   # libvorbis -q 4 (about 64-80 kbit/s mono), higher where 4 leaves a click at the seam
ROTATIONS = 8               # loop starting points tried per quality (a loop may start anywhere: it is periodic)
CLICK_GOAL_DB = -60         # stop searching when the seam's click is this far below the sound
CLICK_MAX_DB = -45          # and refuse a loop whose best is louder than this
NO_CLICK = -300.0           # nothing at the seam that isn't elsewhere in the loop
LOUDEST_LEVEL = -26.0   # dBFS(A) of the loudest source (a vent at 105 dB(A)) at full gain: low enough that the
                        # rumbles, whose energy is mostly below the bass that A weighting discounts, don't clip
LOUDEST_SPL = 105.0
PEAK_MAX = 10 ** (-1 / 20)   # no layer above -1 dBFS (Vorbis overshoots a little)


def level_plan(spl):
    return LOUDEST_LEVEL - 0.5 * (LOUDEST_SPL - spl)


# --------------------------------------------------------------------------------------------------- the voices
# spl: typical A-weighted sound pressure level at 1 m from the source at full load/speed (estimates from the ranges
# usually quoted for such machines; the app's attenuation does the rest). why: the physics of the declared tones and
# noise. Time structure: noise_am / tone_am [(rate Hz, depth)], rates (how tones below 30 Hz are rendered: swell,
# clicks, gurgle), drops (water drops), pattern (alarm sounders), once (a one-shot event).
VOICES = {
    'gt_whine': dict(spl=98, why=(
        'Compressor blade-pass frequency: blades x shaft speed. A 50 Hz heavy-duty gas turbine turns at 3,000 rpm '
        '(50 rev/s); a front stage of 57 blades gives 2,850 Hz, its second harmonic 5,700 Hz, a later stage of '
        '71 blades 3,550 Hz; 50 Hz is the once-per-revolution component. Pink broadband noise 200-4,000 Hz is the '
        'turbulent flow through the stages. Every part scales with speed (blade passing directly, the broadband '
        'noise by Strouhal scaling), so a pitch proportional to speed is right; the first train\'s binding pitches '
        'it from 0.1 at standstill to 1 at full speed (silent below 10 % by its gain)')),
    'combustion': dict(spl=95, noise_am=[(0.375, 0.2), (0.75, 0.15), (1.375, 0.1)], why=(
        'Turbulent combustion roar: broadband, strongest at low frequencies (brown, 30-600 Hz), flickering slowly as '
        'the flames fluctuate (amplitude modulation at 0.4-1.4 Hz)')),
    'exhaust_rumble': dict(spl=86, noise_am=[(0.25, 0.15), (0.625, 0.1)], why=(
        'Low-frequency exhaust duct rumble (brown, 20-200 Hz): large ducts radiate mostly below 200 Hz, so their '
        'dB(A) is modest (86 at the casing) while their dB(C) is some 20 dB higher; heard more through headphones '
        'than a phone speaker')),
    'sfc_whine': dict(spl=82, mains=(100, 500, 600, 700, 1100, 1200, 1300), why=(
        'Static frequency converter: a 12-pulse thyristor converter on a 50 Hz grid draws currents of order '
        '12k +/- 1 (550, 650, 1,150, 1,250 Hz); the forces in its transformer and reactors go with the current '
        'squared, so they buzz at the sums and differences: even multiples of 50 Hz around 600 and 1,200 Hz (500, '
        '600, 700, 1,100, 1,200, 1,300 Hz), and the DC reactor at the 600 Hz ripple; the converter transformer hums '
        'at 100 Hz; pink noise is the cubicle fans. (The machine-side bridge\'s ripple, 6 x the generator\'s '
        'frequency, sweeps up during the start: not modelled, the binding has no speed)')),
    'gen_hum': dict(spl=92, mains=(100, 200, 300, 400, 600), why=(
        'Generator electromagnetic hum: the magnetic forces pulse at twice the 50 Hz grid frequency (100 Hz) with '
        'harmonics at multiples of 100 Hz; pink noise 300-3,000 Hz is the windage and the cooling fans')),
    'transformer_hum': dict(spl=80, mains=(100, 200, 300, 400, 500, 600), why=(
        'Transformer hum: core magnetostriction and winding forces at twice the 50 Hz grid frequency, 100 Hz, and its '
        'harmonics (the magnetostriction is non-linear, so 200-600 Hz are strong too, IEC 60076-10); pink noise is '
        'the cooler fans')),
    'turbine_hum': dict(spl=90, noise_am=[(0.5, 0.08)], why=(
        'Steam turbine rotor at 3,000 rpm: once per revolution 50 Hz with its harmonics 100 and 150 Hz; a last-stage '
        'blade row of 72 blades passes at 3,600 Hz; pink noise 100-2,000 Hz is windage and steam. Pitch follows '
        'speed')),
    'steam_rush': dict(spl=92, noise_am=[(0.5, 0.1), (1.25, 0.06)], why=(
        'Steam flow through the control valves and inlet: aerodynamic valve noise is broadband with its peak at a '
        'few kHz (IEC 60534-8-3), white 500-8,000 Hz, gently unsteady')),
    'steam_vent': dict(spl=105, noise_am=[(0.375, 0.06)], why=(
        'Steam vented to atmosphere through a silencer: a choked jet, broadband hiss to roar 300-10,000 Hz; the '
        'loudest thing in the plant (a silenced vent is still above 100 dB(A) close by)')),
    'turning_gear': dict(spl=75, rates='clicks', click_hz=2200, mains=(100,), why=(
        'Turning gear: the rotor turned slowly by a motor through a reduction gear. The 8 Hz "tone" is the '
        'tooth-meshing rate of the last stage (e.g. 20 teeth at 24 rpm), heard as steel clicks; 100 Hz is the '
        'motor\'s magnetic hum, 600 Hz the mesh of the fast spur stage after the motor; brown noise 50-400 Hz is the '
        'gearbox')),
    'motor_large': dict(spl=92, noise_am=[(0.5, 0.05)], mains=(100, 200), why=(
        'Large induction motor driving a pump (a CW pump: 12 poles, 495 rpm, 8.25 rev/s as the model turns it): '
        'magnetic hum at twice the grid frequency, 100 Hz, and 200 Hz, which stays put whatever the speed; '
        'rotor-slot whine at slots x speed (90 x 8.25 = 742.5 Hz) with sidebands at +/- 100 Hz; the pump\'s '
        'vane passing at 6 vanes x 8.25 = 49.5 Hz; pink noise 100-2,500 Hz is the motor fan and the water. Lower '
        'and louder than motor_small. (The feedwater pumps use it too: their 2-pole motors would whine higher)')),
    'motor_small': dict(spl=82, mains=(100, 200), why=(
        'Small four-pole induction motor (1,480 rpm, 24.7 rev/s, as the model turns the air compressors and cooling '
        'water pumps): magnetic hum 100 and 200 Hz; rotor-slot whine at 44 slots x 24.7 = 1,087 Hz with +/- 100 Hz '
        'sidebands; its cooling fan\'s blade pass 11 x 24.7 = 271.5 Hz; pink noise 200-4,000 Hz is the fan')),
    'fan_large': dict(spl=88, rates='swell', noise_am=[(0.25, 0.08)], mains=(100,), why=(
        'Cooling tower fan: a large axial fan of 8 blades at 120 rpm passes a blade 16 times a second: a whoosh, '
        'not a pitch (the noise swells at 16 Hz); its right-angle gearbox meshes at 420 Hz; motor hum 100 Hz; pink '
        'noise 60-1,500 Hz is the air')),
    'water_rain': dict(spl=85, drops=(180, 0.35), why=(
        'Cooling tower rain: water falling into the basin, broadband white noise 400-9,000 Hz, plus single drops: '
        'each traps a bubble that rings at its Minnaert frequency (about 3.3 kHz / radius in mm: 1-4 kHz for 1-3 mm '
        'drops)')),
    'liquid_ring': dict(spl=85, rates='gurgle', mains=(100,), why=(
        'Liquid ring vacuum pump: the water ring churns once per shaft revolution (1,500 rpm, 25 Hz), heard as a '
        'gurgle; 12 impeller blades pass at 300 Hz; motor hum 100 Hz; brown noise 80-1,200 Hz is the water')),
    'burner': dict(spl=88, noise_am=[(0.5, 0.18), (1.125, 0.1), (2.25, 0.06)], why=(
        'Auxiliary boiler burner: combustion roar (brown, 40-800 Hz) flickering, plus the combustion air fan')),
    'valve_motor': dict(spl=72, tone_am=[(4, 0.12)], mains=(100,), why=(
        'Motor-operated valve actuator: a small motor (100 Hz magnetic hum) and the spur stage in front of its worm '
        'gear, whose mesh whines at 400 Hz with its harmonic at 800 Hz; the load ripples a few times a second (4 Hz) '
        'as the stem nut turns; pink noise is the gearbox')),
    'breaker': dict(spl=94, once=dict(kind='close'), why=(
        'Circuit breaker closing: the closing latch releases with a small click, then the spring drives the '
        'contacts shut with a heavy bang: the mechanism and cubicle ring at their modes (160, 410, 1,150, '
        '2,650 Hz, the low ones longest) over a broadband impact; then the spring-charging motor runs for 3 s to '
        're-charge the closing spring, ending with the spring\'s latch')),
    'breaker_open': dict(spl=92, once=dict(kind='open'), why=(
        'Circuit breaker opening (a trip or an open command): the trip coil releases the opening spring: a sharper, '
        'shorter bang than the close (modes 210, 530, 1,400, 3,100 Hz) and a damped rebound; no charging motor (the '
        'closing charged the opening spring)')),
    'motor_start': dict(spl=95, match=('motor_large', 6.0), once=dict(kind='run_up', seconds=6.0), why=(
        'A large induction motor started direct on line (a CW pump): the inrush current (about 6 x rated) makes a '
        'loud 100 Hz magnetic growl (about +9 dB here; the force goes with the current squared, but the run-up '
        'masks part of it) that drops when the motor nears full speed; it accelerates fastest near the end, where '
        'its torque peaks; the rotor-slot whine (742.5 Hz at full speed) and the vane passing (49.5 Hz) rise with '
        'speed; the fan noise grows with speed. Played once when the motor starts; its last second is levelled to '
        'the motor_large loop, which takes over')),
    'horn_p1': dict(spl=85, pattern=dict(period=0.25, on=0.15, at=0.05), why=(
        'Control room alarm sounder, priority 1 (high): fast pulses (4 a second) of an 880 Hz tone with harmonics '
        '(an electronic sounder\'s square-ish wave). Each priority sounds different (ISA-18.2, EEMUA 191)')),
    'horn_p2': dict(spl=82, pattern=dict(period=1.0, on=0.5, at=0.25), why=(
        'Alarm sounder, priority 2: slow pulses (one a second) of a 660 Hz tone with harmonics')),
    'horn_p3': dict(spl=78, pattern=dict(period=2.0, chime=0.35, at=0.3), why=(
        'Alarm sounder, priority 3 (low): a single 440 Hz chime every 2 s, decaying')),
    'horn_ack': dict(spl=75, once=dict(kind='beeps', count=2, on=0.07, gap=0.05), why=(
        'Acknowledge: two short 1 kHz beeps when an alarm is acknowledged')),
}


# --------------------------------------------------------------------------------------------------- measurement
def a_weighting(f):
    """|A(f)| of IEC 61672-1's A weighting (the analogue response, 0 dB at 1 kHz): what the dB(A) figures of the
    voices are measured with, so the files are levelled the same way."""
    f2 = np.asarray(f, dtype=float) ** 2
    ra = 12194.0 ** 2 * f2 * f2 / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194.0 ** 2))
    return ra * 10 ** (2.0 / 20)


def a_weighted(x, periodic):
    """x through the A weighting: circularly for a loop (exact for a periodic signal), zero padded for a one-shot."""
    n = len(x) if periodic else len(x) + FS
    spec = np.fft.rfft(x, n) * a_weighting(np.fft.rfftfreq(n, 1 / FS))
    return np.fft.irfft(spec, n)[:len(x)]


def level(x, periodic=True):
    """A-weighted level in dBFS (RMS; a full-scale 1 kHz sine reads -3.0): a loop's over the whole loop, a one-shot's
    over its loudest 400 ms (100 ms hop), like a sound level meter's reading of a short event."""
    y = a_weighted(np.asarray(x, dtype=float), periodic)
    if periodic:
        ms = float(np.mean(y * y))
    else:
        w, hop = int(0.4 * FS), int(0.1 * FS)
        ms = max(float(np.mean(y[i:i + w] ** 2)) for i in range(0, max(1, len(y) - w + 1), hop))
    return 10 * math.log10(max(ms, 1e-20))


def power(x, periodic=True):
    return 10 ** (level(x, periodic) / 10)


# --------------------------------------------------------------------------------------------------- synthesis
def rng_for(*names):
    return np.random.default_rng(int.from_bytes(hashlib.sha256('/'.join(names).encode()).digest()[:8], 'little'))


def bandpass(f, lo, hi):
    """Second-order (12 dB/octave) high pass at lo and low pass at hi, as magnitudes."""
    with np.errstate(divide='ignore'):
        return 1 / np.sqrt(1 + (lo / f) ** 4) / np.sqrt(1 + (f / hi) ** 4)


def band_noise(rng, n, colour, band):
    """Gaussian noise of RMS 1, periodic in n samples: random complex spectrum shaped by colour (white flat, pink
    -3 dB/octave, brown -6 dB/octave) and band, transformed back."""
    f = np.fft.rfftfreq(n, 1 / FS)
    spec = rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))
    mag = np.zeros(len(f))
    nz = f > 0
    mag[nz] = f[nz] ** {'white': 0.0, 'pink': -0.5, 'brown': -1.0}[colour] * bandpass(f[nz], band[0], band[1])
    x = np.fft.irfft(spec * mag, n)
    return x / np.sqrt(np.mean(x * x))


def times(n):
    return np.arange(n) / FS


def whole(rate, seconds, what):
    if abs(rate * seconds - round(rate * seconds)) > 1e-9:
        raise ValueError(f'{what}: {rate} Hz has no whole number of cycles in {seconds} s')
    return rate


def am(t, mods, rng, seconds, what):
    """Product of (1 + depth sin(2 pi rate t + random phase)): slow unsteadiness, periodic in the loop."""
    m = np.ones(len(t))
    for rate, depth in mods:
        m *= 1 + depth * np.sin(2 * np.pi * whole(rate, seconds, what) * t + rng.uniform(0, 2 * np.pi))
    return m


def tone(t, hz, gain, phase):
    return gain * math.sqrt(2) * np.sin(2 * np.pi * hz * t + phase)   # RMS = gain


def wrap_add(buf, at, kernel):
    """Adds kernel at sample `at`, wrapping what passes the end to the start (a loop rings on across its seam)."""
    n = len(buf)
    k = len(kernel)
    first = min(k, n - at)
    buf[at:at + first] += kernel[:first]
    rest = kernel[first:]
    while len(rest):
        m = min(len(rest), n)
        buf[:m] += rest[:m]
        rest = rest[m:]


def ring(hz, tau, seconds, phase=0.0):
    t = times(int(seconds * FS))
    return np.exp(-t / tau) * np.sin(2 * np.pi * hz * t + phase)


def sounder_pattern(t, p, seconds):
    """Alarm sounder envelope, periodic: pulses (on for `on` s every `period`, 5 ms ramps) or a decaying chime."""
    whole(1 / p['period'], seconds, 'pattern')
    ph = np.mod(t - p['at'], p['period'])
    if 'chime' in p:
        # this period's chime plus the previous one's tail, so the envelope is periodic to the sample
        return np.exp(-ph / p['chime']) * np.minimum(1, ph / 0.003) + np.exp(-(ph + p['period']) / p['chime'])
    r = 0.005
    return np.clip(np.minimum(ph / r, (p['on'] - ph) / r), 0, 1) * (ph < p['on'])


def render_loop(s, v):
    """{layer: samples} for a looped synth sound, before levelling."""
    sid = s['id']
    layers = {}
    steady = [x for x in s.get('tones', []) if isinstance(x['hz'], (int, float)) and x['hz'] >= RATE_HZ]
    rates = [x for x in s.get('tones', []) if isinstance(x['hz'], (int, float)) and x['hz'] < RATE_HZ]
    varying = [(i, x) for i, x in enumerate(s.get('tones', [])) if not isinstance(x['hz'], (int, float))]
    mains = [x for x in steady if x['hz'] in v.get('mains', ())]
    steady = [x for x in steady if x['hz'] not in v.get('mains', ())]
    if mains:   # the electrical hum: fixed by the grid, not by the machine's speed (the app doesn't pitch it)
        n = TONE_SECONDS * FS
        t = times(n)
        rng = rng_for(sid, 'mains')
        layers['mains'] = sum(tone(t, whole(z['hz'], TONE_SECONDS, sid), z.get('gain', 1), rng.uniform(0, 2 * np.pi))
                              for z in mains)
    if steady:
        n = TONE_SECONDS * FS
        t = times(n)
        rng = rng_for(sid, 'tones')
        x = sum(tone(t, whole(z['hz'], TONE_SECONDS, sid), z.get('gain', 1), rng.uniform(0, 2 * np.pi))
                for z in steady)
        if 'tone_am' in v:
            x = x * am(t, v['tone_am'], rng, TONE_SECONDS, sid)
        if 'pattern' in v:
            x = x * sounder_pattern(t, v['pattern'], TONE_SECONDS)
        layers['tones'] = x
    for i, z in varying:
        ref = max(row[1] for row in z['hz']['table'])
        if ref < RATE_HZ:
            raise ValueError(f'{sid}: tone {i} follows a value but never reaches {RATE_HZ} Hz')
        ref = round(ref * TONE_SECONDS) / TONE_SECONDS
        n = TONE_SECONDS * FS
        layers[f'tone{i}'] = tone(times(n), ref, z.get('gain', 1), rng_for(sid, f'tone{i}').uniform(0, 2 * np.pi))
    if 'noise' in s:
        nz = s['noise']
        n = NOISE_SECONDS * FS
        t = times(n)
        rng = rng_for(sid, 'noise')
        g = nz.get('gain', 1)
        x = band_noise(rng, n, nz['colour'], nz['band'])
        for z in rates:
            r = whole(z['hz'], NOISE_SECONDS, sid)
            d = z.get('gain', 1)
            style = v.get('rates', 'swell')
            if style == 'swell':      # blade passing: the noise swells r times a second
                x = x * (1 + d * np.sin(2 * np.pi * r * t + rng.uniform(0, 2 * np.pi)))
            elif style == 'gurgle':   # churning water: irregular bursts around the rate, periodic in the loop
                e = sum(rng.uniform(0.3, 1) * np.sin(2 * np.pi * k * r / 2 * t + rng.uniform(0, 2 * np.pi))
                        for k in (1, 2, 3, 4))
                e = e / np.max(np.abs(e))
                x = x * (1 + d * 1.5 * e * e - d * 0.5)
            elif style == 'clicks':   # gear teeth: a steel click at every tooth, a little uneven
                clicks = np.zeros(n)
                kern = ring(v['click_hz'], 0.004, 0.08) + 0.6 * ring(650, 0.012, 0.08)
                kern *= np.minimum(1, times(len(kern)) / 0.0003)
                for k in range(int(r * NOISE_SECONDS)):
                    wrap_add(clicks, int(round(k * FS / r)) + int(rng.integers(0, 40)), kern * rng.uniform(0.6, 1))
                x = x + clicks / np.sqrt(np.mean(clicks * clicks)) * d / g
            else:
                raise ValueError(f'{sid}: unknown rate style {style}')
        if 'drops' in v:              # single drops ringing at their bubble's frequency
            per_s, d = v['drops']
            drops = np.zeros(n)
            for _ in range(per_s * NOISE_SECONDS):
                hz = rng.uniform(1000, 4000)
                kern = ring(hz, rng.uniform(0.003, 0.008), 0.04) * np.minimum(1, times(int(0.04 * FS)) / 0.0005)
                wrap_add(drops, int(rng.integers(0, n)), kern * rng.uniform(0.2, 1))
            x = x + drops / np.sqrt(np.mean(drops * drops)) * d / g
        if 'noise_am' in v:
            x = x * am(t, v['noise_am'], rng, NOISE_SECONDS, sid)
        layers['noise'] = x * g
    elif rates:
        raise ValueError(f'{sid}: a tone below {RATE_HZ} Hz is rendered in the noise, and there is none')
    return layers


def render_once(s, v):
    """One-shot events: a breaker closing or opening, a motor's run-up, the acknowledge beeps."""
    sid = s['id']
    ev = v['once']
    rng = rng_for(sid, 'once')
    tones = s.get('tones', [])
    nz = s.get('noise')
    if ev['kind'] in ('close', 'open'):
        total = 4.0 if ev['kind'] == 'close' else 0.8
        n = int(total * FS)
        x = np.zeros(n)
        taus = [0.12, 0.08, 0.04, 0.02] if ev['kind'] == 'close' else [0.07, 0.045, 0.025, 0.012]

        def impact(at, scale, noise_tau):
            seg = int(0.6 * FS)
            t = times(seg)
            attack = np.minimum(1, t / 0.0004)
            y = sum(z.get('gain', 1) * math.sqrt(2) * np.exp(-t / taus[i % len(taus)])
                    * np.sin(2 * np.pi * z['hz'] * t + rng.uniform(0, 2 * np.pi)) for i, z in enumerate(tones))
            if nz:
                y = y + nz.get('gain', 1) * 2.5 * np.exp(-t / noise_tau) * band_noise(rng, seg, nz['colour'],
                                                                                    nz['band'])
            i = int(at * FS)
            m = min(seg, n - i)
            x[i:i + m] += (scale * attack * y)[:m]

        if ev['kind'] == 'close':
            impact(0.010, 0.12, 0.004)            # the closing latch releasing
            impact(0.045, 1.0, 0.012)             # the contacts driven shut
            # the spring-charging motor: 0.5 s to 3.5 s, then the spring's latch
            a, b = int(0.5 * FS), int(3.5 * FS)
            t = times(b - a)
            env = np.minimum(1, t / 0.1) * np.minimum(1, (t[-1] - t) / 0.15)
            motor = (tone(t, 100, 0.3, 0) + tone(t, 520, 0.2, 1.0) + tone(t, 1040, 0.06, 2.0)
                     + 0.15 * band_noise(rng, b - a, 'pink', [400, 3000]))
            x[a:b] += 0.18 * env * motor
            impact(3.52, 0.2, 0.006)
        else:
            impact(0.010, 1.0, 0.008)             # the opening spring's bang
            impact(0.065, 0.3, 0.005)             # the damper's rebound
    elif ev['kind'] == 'run_up':
        tr = ev['seconds']
        total = tr + 1.0
        n = int(total * FS)
        t = times(n)
        u = np.minimum(t, tr) / tr
        speed = np.where(t < tr, u ** 1.6, 1.0)   # slow at first, fastest near full speed (the torque peak)
        # current: about 6 x rated until the motor nears full speed, then down to rated
        edge = np.clip((speed - 0.8) / 0.18, 0, 1)
        current = 1 + 5 * (1 - edge * edge * (3 - 2 * edge))
        steady_hz = [z for z in tones if z['hz'] == 100]
        moving = [z for z in tones if z['hz'] != 100]
        x = np.zeros(n)
        for z in steady_hz:   # the magnetic hum grows with the current: about +9 dB at inrush (6 ** 0.6)
            x += tone(t, 100, z.get('gain', 1), 0) * (current / 6) ** 0.6 * 2.9
        for z in moving:      # slot whine and vane passing rise with speed
            phase = 2 * np.pi * np.cumsum(z['hz'] * speed) / FS
            x += z.get('gain', 1) * math.sqrt(2) * np.sin(phase) * speed
        if nz:
            x += nz.get('gain', 1) * band_noise(rng, n, nz['colour'], nz['band']) * speed ** 2.5
        x *= np.minimum(1, t / 0.02)
    elif ev['kind'] == 'beeps':
        total = 0.02 + ev['count'] * (ev['on'] + ev['gap']) + 0.05
        n = int(total * FS)
        t = times(n)
        env = np.zeros(n)
        for k in range(ev['count']):
            ph = t - 0.02 - k * (ev['on'] + ev['gap'])
            env += np.clip(np.minimum(ph / 0.005, (ev['on'] - ph) / 0.005), 0, 1) * (ph >= 0) * (ph < ev['on'])
        x = env * sum(tone(t, z['hz'], z.get('gain', 1), 0) for z in tones)
    else:
        raise ValueError(f'{sid}: unknown event {ev["kind"]}')
    # every one-shot starts and ends at silence
    k = int(0.03 * FS)   # a 30 ms fade
    x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    x[0] = 0.0
    return {'once': x}


def make(s, lib=None):
    """{layer: float samples at the planned level}, the level in dBFS(A), and whether it loops. A one-shot with
    `match` (e.g. a motor's run-up) is levelled so that its last second before the fade matches that loop at gain 1,
    so the hand-over to the loop is even; its level is then what that gives."""
    v = VOICES[s['id']]
    once = 'once' in v
    layers = render_once(s, v) if once else render_loop(s, v)
    if 'match' in v:
        other, at = v['match']
        tail = layers['once'][int(at * FS):int((at + 1) * FS)]
        want = level_plan(VOICES[other]['spl'])
        scale = 10 ** ((want - level(tail, False)) / 20)
        layers = {k: x * scale for k, x in layers.items()}
        plan = level(layers['once'], False)
    else:
        plan = level_plan(v['spl'])
        total = sum(power(x, not once) for x in layers.values())
        scale = 10 ** ((plan - 10 * math.log10(total)) / 20)
        layers = {k: x * scale for k, x in layers.items()}
    for k, x in layers.items():
        peak = float(np.max(np.abs(x)))
        if peak > PEAK_MAX:
            raise ValueError(f'{s["id"]}.{k}: peak {20 * math.log10(peak):.1f} dBFS at {plan:.1f} dBFS(A): lower its spl')
    return layers, plan, not once


def pcm16(x):
    return np.clip(np.round(x * 32767), -32768, 32767).astype('<i2')


def wav_bytes(samples):
    data = samples.tobytes()
    return (b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, FS, FS * 2, 2, 16)
            + b'data' + struct.pack('<I', len(data)) + data)


def ffmpeg():
    exe = shutil.which('ffmpeg')
    if not exe:
        raise SystemExit('make_sounds: ffmpeg (with libvorbis) is needed to write Ogg Vorbis (decision 0055); '
                         'install it or use --wav')
    return exe


def vorbis(samples, quality=VORBIS_QUALITIES[0]):
    """16-bit mono samples to Ogg Vorbis, bit-exact (0055: same samples, same bytes)."""
    return subprocess.run(
        [ffmpeg(), '-nostdin', '-v', 'error', '-f', 's16le', '-ar', str(FS), '-ac', '1', '-i', '-',
         '-c:a', 'libvorbis', '-q:a', str(quality), '-fflags', '+bitexact', '-flags:a', '+bitexact',
         '-map_metadata', '-1', '-page_duration', '100000', '-f', 'ogg', '-'],
        input=samples.tobytes(), capture_output=True, check=True).stdout


def decode(data):
    """Ogg Vorbis bytes to float samples (for the tests)."""
    raw = subprocess.run([ffmpeg(), '-nostdin', '-v', 'error', '-i', '-', '-f', 's16le', '-ac', '1', '-ar', str(FS),
                          '-'], input=data, capture_output=True, check=True).stdout
    return np.frombuffer(raw, '<i2').astype(float) / 32767


def top_hz(s, layer):
    """The highest frequency a layer of sound s is made of: a click at the loop point is looked for above it."""
    v = VOICES[s['id']]
    if layer == 'noise':
        f = [s['noise']['band'][1]]
        if v.get('rates') == 'clicks':
            f.append(v['click_hz'])
        if 'drops' in v:
            f.append(4000)
        return max(f)
    return max(z['hz'] for z in s['tones'] if isinstance(z['hz'], (int, float)))


def seam_click_db(x, top):
    """How loud a click at the loop point of the loop x is, in dB under the sound around it: the energy above the
    layer's own frequencies (from 1.5 x its top frequency to 16 kHz) in a 512-sample window centred on the seam,
    beyond the largest of 63 windows elsewhere, over the mean energy of a window. A click is a broadband burst; a
    seamless loop has nothing there that the rest of the loop doesn't have (NO_CLICK)."""
    x = np.asarray(x, dtype=float)
    w = 512
    win = np.hanning(w)
    f = np.fft.rfftfreq(w, 1 / FS)
    band = (f >= min(1.5 * top, 12000)) & (f <= 16000)
    n = len(x)
    hf, total = [], []
    for k in range(64):
        c = k * n // 64
        spec = np.abs(np.fft.rfft(np.take(x, np.arange(c - w // 2, c + w // 2), mode='wrap') * win)) ** 2
        hf.append(float(spec[band].sum()))
        total.append(float(spec.sum()))
    excess = hf[0] - max(hf[1:])
    if excess <= 0:
        return NO_CLICK
    return max(NO_CLICK, 10 * math.log10(excess / max(float(np.mean(total)), 1e-30)))


def vorbis_loop(samples, top, what):
    """Ogg Vorbis for a loop. Vorbis's error is smooth inside a stream, but the error at its end and at its start are
    independent, so the jump between them can tick at the loop point. The loop may start anywhere (it is periodic):
    try ROTATIONS starting points at each quality, keep the first whose decoded seam's click is CLICK_GOAL_DB under
    the sound, else the quietest. Returns (bytes, quality, rotation in samples, click dB)."""
    best = None
    n = len(samples)
    for q in VORBIS_QUALITIES:
        for r in range(ROTATIONS):
            rot = r * n // ROTATIONS
            data = vorbis(np.roll(samples, -rot), q)
            click = seam_click_db(decode(data), top)
            if best is None or click < best[3] - 0.05:
                best = (data, q, rot, click)
            if click <= CLICK_GOAL_DB:
                return best
    if best[3] > CLICK_MAX_DB:
        raise ValueError(f'{what}: the quietest loop point after Vorbis still clicks at {best[3]:.1f} dB')
    return best


def library(path=LIBRARY):
    with open(path, encoding='utf-8') as f:
        lib = json.load(f)
    if lib.get('format') != 'walkdown-plant-sounds':
        raise ValueError(f'{path}: not a walkdown-plant-sounds file')
    synth = [s for s in lib['sounds'] if s['kind'] == 'synth']
    missing = [s['id'] for s in synth if s['id'] not in VOICES]
    if missing:
        raise ValueError(f'no voice (level and physics) for {", ".join(missing)}: add it to VOICES')
    return synth


def build(out, wav=False, lib=LIBRARY):
    """Writes every layer and the index; returns the index."""
    os.makedirs(out, exist_ok=True)
    index = {'format': 'walkdown-plant-sound-files', 'version': 1, 'rate': FS, 'sounds': {}}
    for s in library(lib):
        layers, plan, loop = make(s)
        entry = {'loop': loop, 'level': round(plan, 1), 'layers': []}
        for name, x in layers.items():
            samples = pcm16(x)
            fname = f'{s["id"]}.{name}.{"wav" if wav else "ogg"}'
            layer = {'layer': name, 'file': fname, 'samples': len(samples), 'seconds': round(len(samples) / FS, 3)}
            if wav:
                data = wav_bytes(samples)
            elif loop:
                data, q, rot, click = vorbis_loop(samples, top_hz(s, name), fname)
                layer.update({'quality': q, 'click_db': round(click, 1)})
            else:
                data = vorbis(samples)
            with open(os.path.join(out, fname), 'wb') as f:
                f.write(data)
            layer['bytes'] = len(data)
            layer['pitch'] = name != 'mains'   # the mains hum stays at 2 x grid frequency whatever the speed
            if name.startswith('tone') and name != 'tones':
                z = s['tones'][int(name[4:])]
                layer.update({'of': z['hz']['of'], 'table': z['hz']['table'],
                              'ref_hz': round(max(r[1] for r in z['hz']['table']) * TONE_SECONDS) / TONE_SECONDS})
            entry['layers'].append(layer)
        index['sounds'][s['id']] = entry
    index['bytes'] = sum(la['bytes'] for e in index['sounds'].values() for la in e['layers'])
    with open(os.path.join(out, 'index.json'), 'w', encoding='utf-8') as f:
        json.dump(index, f, indent=1, sort_keys=True)
        f.write('\n')
    return index


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--wav', action='store_true', help='16-bit WAV instead of Ogg Vorbis (for listening)')
    a = ap.parse_args(argv)
    index = build(a.out, a.wav)
    for sid, e in index['sounds'].items():
        print(f'{sid:16} {"loop" if e["loop"] else "once"} {e["level"]:6.1f} dBFS(A)  '
              + '  '.join(f'{la["layer"]} {la["seconds"]:g} s {la["bytes"] / 1024:.0f} KiB' for la in e['layers']))
    print(f'{len(index["sounds"])} sounds, {index["bytes"] / 1e6:.2f} MB in {a.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
