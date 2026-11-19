#!/usr/bin/env python3
"""Flash analysis of a Walkdown Plant frame capture (apps/plant3d/tests/flash_capture.gd; UI-UX-POLICY A10, issue #443).

    python3 tools/plant3d/flash_analysis.py CAPTURE [CAPTURE...]

WCAG 2.3.1's general and red flash thresholds, applied to every frame of the capture (160 x 90, each cell the average
of its part of the window) with the real time of each frame:
- relative luminance L of each cell from its sRGB colour (WCAG's formula);
- a cell's transition: a change of L by 0.1 or more from its last extreme, opposite to its previous one, where the
  darker of the two is below 0.80 (a general flash is a pair of them);
- a red transition: a change of 20 or more in max(0, (R - G - B) * 320) (linear R, G, B) from its last extreme while
  the cell is saturated red (R / (R + G + B) >= 0.8) on one side;
- a frame counts a screen transition when the cells making one in the same direction cover at least AREA of the
  frame. AREA is 341 x 256 of 1024 x 768 (WCAG's 25 % of a 10-degree field at a typical viewing distance), 11.1 %; the
  report also gives the counts at 2 % (a stricter area);
- flashes in any 1-second window of real time = screen transitions in it / 2 (rounded down); at most 3 pass.
Also the frame-to-frame change of the mean luminance. A model of the rule, not a certified analyser (Harding, PEAT
or IRIS).
"""
import sys

import numpy as np

AREA = 341 * 256 / (1024 * 768)


def load(path):
    with open(path, 'rb') as f:
        head = f.readline().decode().split()
        w, h = int(head[1]), int(head[2])
        raw = np.frombuffer(f.read(), dtype=np.uint8)
    n = raw.size // (w * h * 3)
    frames = raw[: n * w * h * 3].reshape(n, h * w, 3).astype(np.float64) / 255.0
    times = np.loadtxt(path + '.times', dtype=np.float64)[:n] / 1e6
    return ' '.join(head[3:]), frames, times


def linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def cell_transitions(values, step, dark_limit=None):
    """Per frame and cell: +1 / -1 where the cell makes a transition (from its last extreme), else 0."""
    n, cells = values.shape
    out = np.zeros((n, cells), dtype=np.int8)
    ref = values[0].copy()
    direction = np.zeros(cells, dtype=np.int8)
    for i in range(1, n):
        x = values[i]
        darker_ok = np.ones(cells, bool) if dark_limit is None else np.minimum(x, ref) < dark_limit
        up = (direction != 1) & (x - ref >= step) & darker_ok
        down = (direction != -1) & (ref - x >= step) & darker_ok
        out[i][up] = 1
        out[i][down] = -1
        direction[up] = 1
        direction[down] = -1
        moved = up | down | ((direction == 1) & (x > ref)) | ((direction == -1) & (x < ref))
        ref[moved] = x[moved]
    return out


def screen_transitions(cell_tr, times, area):
    """The times of the screen's transitions: frames where the cells changing one way cover `area`, alternating."""
    cells = cell_tr.shape[1]
    out = []
    last = 0
    for i in range(cell_tr.shape[0]):
        ups = np.count_nonzero(cell_tr[i] == 1) / cells
        downs = np.count_nonzero(cell_tr[i] == -1) / cells
        d = 1 if ups >= area and ups >= downs else (-1 if downs >= area else 0)
        if d and d != last:
            out.append(times[i])
            last = d
    return np.array(out)


def max_in_window(t, w=1.0):
    best, j = 0, 0
    for i in range(len(t)):
        while t[i] - t[j] > w:
            j += 1
        best = max(best, i - j + 1)
    return best


def analyse(path):
    what, frames, times = load(path)
    lin = linear(frames)
    lum = lin @ np.array([0.2126, 0.7152, 0.0722])
    red = np.maximum(0.0, (lin[..., 0] - lin[..., 1] - lin[..., 2]) * 320.0)
    saturated = lin[..., 0] / np.maximum(lin.sum(axis=2), 1e-9) >= 0.8
    red = np.where(saturated, red, 0.0)
    gen = cell_transitions(lum, 0.1, 0.8)
    rtr = cell_transitions(red, 20.0)
    mean = lum.mean(axis=1)
    fps = (len(times) - 1) / (times[-1] - times[0]) if len(times) > 1 else 0.0
    print(f'{path}: {what}; {len(times)} frames over {times[-1] - times[0]:.1f} s ({fps:.0f} fps)')
    print(f'  mean luminance {mean.min():.4f} to {mean.max():.4f}; largest change between two frames '
          f'{np.abs(np.diff(mean)).max() if len(mean) > 1 else 0.0:.4f}')
    print(f'  cells (of {lum.shape[1]}) ever making a general transition: {np.count_nonzero(np.any(gen != 0, axis=0))}, '
          f'a red one: {np.count_nonzero(np.any(rtr != 0, axis=0))}')
    worst = 0
    for name, tr in (('general', gen), ('red', rtr)):
        for area in (AREA, 0.02):
            st = screen_transitions(tr, times, area)
            m = max_in_window(st)
            if area == AREA:
                worst = max(worst, m // 2)
            print(f'  {name} flashes over {area * 100:.1f} % of the frame: {len(st) // 2} in all, '
                  f'at most {m // 2} in any second ({m} transitions)')
    print(f'  RESULT: at most {worst} flashes in any second: {"pass" if worst <= 3 else "FAIL"} (3 at most)')
    return worst <= 3


if __name__ == '__main__':
    ok = all([analyse(p) for p in sys.argv[1:]])
    sys.exit(0 if ok else 1)
