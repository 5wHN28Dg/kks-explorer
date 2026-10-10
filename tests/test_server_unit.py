"""The server's systemd units (deploy/install-server-user.sh; deploy/install-server-system.sh for a machine without a
TPM2, added 2026-10-10) and build (2026-10-09: the deployed server held 7.4 GB):
- the unit caps the server's memory with MemoryMax, without swap, restarts it when it is killed, and never throttles
  it with MemoryHigh (throttling took the desktop down);
- the importer's own address-space limit (import_memory_mb) is below that cap, so an import stops itself first;
- the server is built with glibc's malloc (platform/linux/kks_server.nims), which gives freed memory back.
  .venv/bin/python -m unittest tests.test_server_unit"""
import os, re, subprocess, tempfile, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def user_unit_text():
    with open(os.path.join(REPO, 'deploy', 'install-server-user.sh')) as f:
        script = f.read()
    m = re.search(r'kks-server\.service" <<UNIT\n(.*?)\nUNIT\n', script, re.S)
    assert m, 'the unit heredoc was not found in install-server-user.sh'
    return m.group(1)


def system_unit_text(user='walkdown', home='/home/walkdown'):
    return subprocess.run([os.path.join(REPO, 'deploy', 'install-server-system.sh'), '--print-unit', user, home],
                          check=True, capture_output=True, text=True).stdout


UNITS = {'user': user_unit_text, 'system': system_unit_text}


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
        for kind, text in UNITS.items():
            with self.subTest(unit=kind):
                s = service_settings(text())
                self.assertIn('MemoryMax', s)
                cap = size(s['MemoryMax'][-1])
                # room for the importer it runs (the largest real sheet peaks near 1.85 GB resident) and the server,
                # well under the old 8G
                self.assertGreaterEqual(cap, 2 << 30)
                self.assertLessEqual(cap, 4 << 30)
                self.assertEqual(s.get('MemorySwapMax'), ['0'])
                self.assertEqual(s.get('Restart'), ['on-failure'])
                self.assertEqual(s.get('OOMPolicy'), ['continue'])

    def test_importer_stops_itself_below_the_cap(self):
        """2026-10-09: the importer's address-space limit was 6144 MB under a 3G cap, so a growing import was killed by
        the cgroup (no message) instead of stopping itself with one"""
        with open(os.path.join(REPO, 'platform', 'linux', 'src', 'kksl', 'server.nim')) as f:
            mb = int(re.search(r'importMemoryMb: (\d+)\)', f.read()).group(1))
        self.assertEqual(mb, 2560)
        for kind, text in UNITS.items():
            with self.subTest(unit=kind):
                self.assertLess(mb << 20, size(service_settings(text())['MemoryMax'][-1]))

    def test_never_memory_high(self):
        for kind, text in UNITS.items():
            with self.subTest(unit=kind):
                self.assertNotIn('MemoryHigh', service_settings(text()))

    def test_system_unit_runs_the_users_install_unprivileged(self):
        """a machine without a TPM2 (2026-10-10): a user service can't load the sealed key there, so the same install
        runs as a system service: as that user, with the machine's credential, writing only its state folder"""
        s = service_settings(system_unit_text('plant', '/srv/plant'))
        self.assertEqual(s['User'], ['plant'])
        self.assertNotIn('Group', s)  # the user's primary group, whatever its name (216/GROUP otherwise)
        self.assertEqual(s['Environment'], ['KKS_CONFIG=/srv/plant/kks-server/config.json'])
        self.assertEqual(s['ExecStart'], ['/srv/plant/kks-server/app/current/kks-server serve'])
        self.assertEqual(s['WorkingDirectory'], ['/srv/plant/kks-server/state'])
        self.assertEqual(s['LoadCredentialEncrypted'], ['kks-storage-key:/etc/credstore.encrypted/kks-storage-key'])
        self.assertEqual(s['ProtectSystem'], ['strict'])
        self.assertEqual(s['ReadWritePaths'], ['/srv/plant/kks-server/state'])
        for k in ('NoNewPrivileges', 'PrivateTmp', 'PrivateDevices', 'ProtectKernelTunables', 'ProtectKernelModules',
                  'ProtectControlGroups', 'RestrictNamespaces', 'LockPersonality', 'RestrictSUIDSGID'):
            self.assertEqual(s.get(k), ['true'], k)
        self.assertEqual(s['SystemCallArchitectures'], ['native'])
        self.assertEqual(s['CapabilityBoundingSet'], [''])
        self.assertEqual(s['RestrictAddressFamilies'], ['AF_INET AF_INET6 AF_UNIX AF_NETLINK'])

    def test_system_install_refuses_without_root(self):
        if os.geteuid() == 0:
            self.skipTest('needs an unprivileged user')
        r = subprocess.run([os.path.join(REPO, 'deploy', 'install-server-system.sh'), 'nobody'],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn('root', r.stderr)

    def install(self, tmp, **extra):
        """deploy/install-server-user.sh in a scratch home, with a stand-in compiler that writes the file named by -o:"""
        home, nim = os.path.join(tmp, 'home'), os.path.join(tmp, 'nim')
        os.makedirs(home)
        with open(nim, 'w') as f:
            f.write('#!/bin/sh\nfor a in "$@"; do case "$a" in -o:*) echo x > "${a#-o:}";; esac; done\n')
        os.chmod(nim, 0o755)
        env = dict(os.environ, HOME=home, NIM=nim, KKS_SYSTEM_UNIT_FILE=os.path.join(tmp, 'no-system-unit'))
        env.update(extra)
        env.pop('KKS_SERVER_HOME', None)
        # the install is read-only: callers make it writable again before the scratch folder goes
        r = subprocess.run([os.path.join(REPO, 'deploy', 'install-server-user.sh')], env=env, capture_output=True,
                           text=True)
        return r, home

    def test_user_install_for_a_system_unit_writes_no_user_unit_or_key(self):
        """KKS_SERVER_UNIT=system: the install stops before the user unit and the user-sealed key (two units on one
        database must never exist)"""
        with tempfile.TemporaryDirectory() as tmp:
            r, home = self.install(tmp, KKS_SERVER_UNIT='system')
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(os.path.exists(os.path.join(home, 'kks-server', 'app', 'current', 'kks-server')))
            self.assertTrue(os.path.exists(os.path.join(home, 'kks-server', 'config.json')))
            self.assertFalse(os.path.exists(os.path.join(home, 'kks-server', 'storage-key.cred')))
            self.assertFalse(os.path.exists(os.path.join(home, '.config', 'systemd', 'user', 'kks-server.service')))
            self.assertIn('install-server-system.sh', r.stdout)
            subprocess.run(['chmod', '-R', 'u+w', home])

    def test_user_install_rejects_an_unknown_unit_kind(self):
        with tempfile.TemporaryDirectory() as tmp:
            r, home = self.install(tmp, KKS_SERVER_UNIT='sytem')
            self.assertEqual(r.returncode, 2)
            self.assertEqual(os.listdir(home), [])

    def test_user_install_refuses_next_to_a_system_unit(self):
        """an update on the server run without KKS_SERVER_UNIT=system would write a user unit and a second key next to
        the system service"""
        with tempfile.TemporaryDirectory() as tmp:
            unit = os.path.join(tmp, 'kks-server.service')
            open(unit, 'w').close()
            r, home = self.install(tmp, KKS_SYSTEM_UNIT_FILE=unit)
            self.assertEqual(r.returncode, 1)
            self.assertIn('KKS_SERVER_UNIT=system', r.stderr)
            self.assertEqual(os.listdir(home), [])
        with tempfile.TemporaryDirectory() as tmp:
            unit = os.path.join(tmp, 'kks-server.service')
            open(unit, 'w').close()
            r, home = self.install(tmp, KKS_SYSTEM_UNIT_FILE=unit, KKS_SERVER_UNIT='system')
            self.assertEqual(r.returncode, 0, r.stderr)
            subprocess.run(['chmod', '-R', 'u+w', home])


if __name__ == '__main__':
    unittest.main()
