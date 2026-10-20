"""tools/plant3d/bench/gpu_clients.py: what else uses the GPU while the laptop's frames are measured (0057, 0060).
- an i915 fdinfo file gives its client and render engine time; a file without one (not a GPU client) gives nothing;
- a client shared by several descriptors of one process is counted once, and its time per second is the difference
  between two snapshots (a fake /proc here)."""
import os, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d', 'bench'))
import gpu_clients as G

I915 = """pos:\t0
flags:\t02100002
mnt_id:\t26
ino:\t1069
drm-driver:\ti915
drm-client-id:\t72
drm-pdev:\t0000:00:02.0
drm-total-system0:\t3720 KiB
drm-engine-render:\t%d ns
drm-engine-copy:\t0 ns
drm-engine-video:\t0 ns
drm-engine-capacity-video:\t2
"""


def fake_proc(d, render_ns):
    for pid, name, fds in (('11990', 'zed-editor', ('41', '85')), ('6485', 'gnome-shell', ())):
        os.makedirs(os.path.join(d, pid, 'fdinfo'), exist_ok=True)
        with open(os.path.join(d, pid, 'comm'), 'w') as f:
            f.write(name + '\n')
        for fd in fds:
            with open(os.path.join(d, pid, 'fdinfo', fd), 'w') as f:
                f.write(I915 % render_ns)
    with open(os.path.join(d, '6485', 'fdinfo', '3'), 'w') as f:
        f.write('pos:\t0\nflags:\t02\nmnt_id:\t26\n')   # an ordinary file
    os.makedirs(os.path.join(d, 'self'), exist_ok=True)


class GpuClients(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(G.parse_fdinfo(I915 % 4192177456636), ('72', 4192177456636))
        self.assertIsNone(G.parse_fdinfo('pos:\t0\nflags:\t02\n'))
        self.assertEqual(G.parse_fdinfo('drm-driver:\tamdgpu\ndrm-client-id:\t9\ndrm-engine-gfx:\t1500 ns\n'), ('9', 1500))

    def test_busy(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            fake_proc(a, 1_000_000_000)
            fake_proc(b, 1_000_000_000 + 2 * 450_000_000)   # 450 ms of render engine a second, over 2 s
            before, after = G.snapshot(a), G.snapshot(b)
            self.assertEqual(len(after), 1)                  # the one client, not once per descriptor
            rows = G.busy(before, after, 2.0)
            self.assertEqual(len(rows), 1)
            self.assertAlmostEqual(rows[0][0], 450.0)
            self.assertEqual(rows[0][1:], ('zed-editor', '11990'))


if __name__ == '__main__':
    unittest.main()
