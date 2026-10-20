#!/usr/bin/env python3
"""What else uses the GPU while the laptop's frames are measured (decisions 0057 and 0060): every process's render
engine time per second over SECONDS, from the DRM fdinfo files Linux keeps per GPU client (/proc/PID/fdinfo,
`drm-engine-render`; i915, xe and amdgpu write it). Only this user's processes are readable, which is where the
desktop's apps run.

On 2026-10-20 the laptop's full tier missed its 60 fps rule (frame p95 21.6 ms, GPU p95 7.6 ms) on a machine that
looked quiet: an editor left open kept the Iris Xe's render engine busy 420-470 ms of every second, in batches of
12-25 ms about 22 times a second, and the plant's main thread waited for each in its fence (a trivial Godot scene
showed the same long frames). Measure with nothing else on the GPU: this prints what is there.
  python3 tools/plant3d/bench/gpu_clients.py [SECONDS]      default 5; prints clients over 1 ms/s, busiest first
"""
import os, re, sys, time

RENDER = re.compile(r'^drm-engine-render:\s*(\d+)\s*ns', re.M)
CLIENT = re.compile(r'^drm-client-id:\s*(\d+)', re.M)


def parse_fdinfo(text):
    """(client id, render engine ns) of one fdinfo file, or None when it is not a GPU client with a render engine."""
    r = RENDER.search(text)
    if r is None:
        return None
    c = CLIENT.search(text)
    return (c.group(1) if c else None, int(r.group(1)))


def snapshot(proc='/proc'):
    """{(pid, client id): (process name, render ns)}: each client once, however many descriptors share it."""
    out = {}
    for pid in os.listdir(proc):
        if not pid.isdigit():
            continue
        try:
            fds = os.listdir(os.path.join(proc, pid, 'fdinfo'))
        except OSError:
            continue
        for fd in fds:
            try:
                with open(os.path.join(proc, pid, 'fdinfo', fd)) as f:
                    got = parse_fdinfo(f.read())
            except OSError:
                continue
            if got is None:
                continue
            cid = got[0] if got[0] is not None else 'fd' + fd
            if (pid, cid) in out:
                continue
            try:
                with open(os.path.join(proc, pid, 'comm')) as f:
                    name = f.read().strip()
            except OSError:
                name = '?'
            out[(pid, cid)] = (name, got[1])
    return out


def busy(before, after, seconds):
    """[(ms of render engine per second, name, pid)] for the clients in both snapshots, busiest first."""
    rows = []
    for k, (name, ns) in after.items():
        if k in before:
            rows.append(((ns - before[k][1]) / 1e6 / seconds, name, k[0]))
    return sorted(rows, reverse=True)


def main(argv):
    seconds = float(argv[1]) if len(argv) > 1 else 5.0
    a = snapshot()
    time.sleep(seconds)
    rows = busy(a, snapshot(), seconds)
    shown = [r for r in rows if r[0] >= 1.0]
    for ms, name, pid in shown:
        print(f'{name:24s} pid {pid:>8s}  render engine {ms:7.1f} ms/s')
    if not shown:
        print('no GPU client over 1 ms/s')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
