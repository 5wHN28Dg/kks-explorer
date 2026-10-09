"""The server's systemd unit (deploy/install-server-user.sh) and build (2026-10-09: the deployed server held 7.4 GB):
- the unit caps the server's memory with MemoryMax, without swap, restarts it when it is killed, and never throttles
  it with MemoryHigh (throttling took the desktop down);
- the server is built with glibc's malloc (platform/linux/kks_server.nims), which gives freed memory back.
  .venv/bin/python -m unittest tests.test_server_unit"""
import os, re, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def unit_text():
    with open(os.path.join(REPO, 'deploy', 'install-server-user.sh')) as f:
        script = f.read()
    m = re.search(r'kks-server\.service" <<UNIT\n(.*?)\nUNIT\n', script, re.S)
    assert m, 'the unit heredoc was not found in install-server-user.sh'
    return m.group(1)


def service_settings(unit):
    out, section = {}, None
    for line in unit.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('['):
            section = line
        elif section == '[Service]' and '=' in line:
            k, v = line.split('=', 1)
            out.setdefault(k, []).append(v)
    return out


def size(v):
    n, unit = re.fullmatch(r'(\d+)([KMG]?)', v).groups()
    return int(n) * {'': 1, 'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30}[unit]


class ServerUnit(unittest.TestCase):
    def test_memory_is_capped_and_a_killed_server_restarts(self):
        s = service_settings(unit_text())
        self.assertIn('MemoryMax', s)
        cap = size(s['MemoryMax'][-1])
        # room for the importer it runs (a large sheet peaks near 1.8 GB) and the server, well under the old 8G
        self.assertGreaterEqual(cap, 2 << 30)
        self.assertLessEqual(cap, 4 << 30)
        self.assertEqual(s.get('MemorySwapMax'), ['0'])
        self.assertEqual(s.get('Restart'), ['on-failure'])
        self.assertEqual(s.get('OOMPolicy'), ['continue'])

    def test_never_memory_high(self):
        self.assertNotIn('MemoryHigh', service_settings(unit_text()))

    def test_server_built_with_malloc(self):
        with open(os.path.join(REPO, 'platform', 'linux', 'kks_server.nims')) as f:
            nims = f.read()
        self.assertRegex(nims, r'(?m)^switch\("define", "useMalloc"\)')


if __name__ == '__main__':
    unittest.main()
